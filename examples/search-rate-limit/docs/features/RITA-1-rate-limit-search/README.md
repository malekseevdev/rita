# RITA-1: Rate-limit the public search endpoint

> Status: Plan
> Last reviewed: 2026-06-28
> Ticket: RITA-1

| Document                                 | Purpose                            |
| ---------------------------------------- | ---------------------------------- |
| This file                                | What the feature is and how it works |
| [feasibility.md](feasibility.md)         | Load-bearing assumptions + verifications (evergreen) |
| [plan.md](plan.md)                       | Implementation logistics — ephemeral, deleted at ship |
| [test-cases.md](test-cases.md)           | User-perspective scenarios         |
| [metrics.md](metrics.md)                 | Metrics catalog and baseline       |
| [runbook.md](runbook.md)                 | Agent-friendly operational runbook |

## Overview

Adds per-client rate limiting to the public, unauthenticated
`GET /search` endpoint. Each client — keyed by IP — is allowed a
bounded request rate; requests above that rate are rejected with
`429 Too Many Requests` and a `Retry-After` header instead of being
served. The limiter is an in-process WSGI middleware built entirely
on the Python standard library, with no new infrastructure on the
request path. Enforcement runs in one of three modes — `off`,
`shadow` (count-only, never reject), or `enforce` — controlled by a
single setting that doubles as the emergency off-switch.

## Why

`GET /search` is public and unauthenticated, so a single abusive
client (a scraper) can push enough query volume to degrade search
latency for *every* user. Today the only mitigation is to ship a
deploy — minutes-to-hours of exposure during an incident. This
feature caps any one client's share of capacity so an abuser is
throttled while normal users are unaffected, and it gives on-call a
runtime switch to disable enforcement in seconds if it misfires
(contingent on a live config-reload mechanism — see feasibility.md).

## Invariants & constraints

The non-negotiables this feature must hold — the plan's constitution.
Everything below is subordinate; on conflict, a constraint wins.

| Constraint | Why it's load-bearing | How it's checked |
| ---------- | --------------------- | ---------------- |
| **Standard library only** — no new third-party runtime deps, no new request-path infra | Keeps the limiter self-contained and installable anywhere; ticket-mandated | `grep` import list in CI; DoD item; no new entries in `requirements.txt` |
| **Normal clients are never throttled** — limits sit above legitimate per-IP traffic | A limiter that throttles real users is worse than the abuse it prevents | `shadow`-mode baseline shows 0 legitimate clients would be rejected (metrics.md); test case for under-limit traffic |
| **A misfire is reversible in seconds without a deploy** | The whole point vs. today's deploy-only mitigation | Setting flip to `off`/`shadow`; runbook one-shot; DoD item. *Rests on a live mode-reload mechanism — flagged unverified in feasibility.md; if none exists the claim downgrades to "redeploy-fast".* |
| **The limiter never fails the request path** — limiter bugs/exhaustion must not 500 the endpoint; fail *open* | Search availability outranks rate-limit accuracy | Test case: limiter exception → request still served; metric on limiter-internal errors |
| **Per-IP state is memory-bounded** — the IP→bucket map cannot grow without limit | IP is attacker-controlled; an unbounded map is a memory-exhaustion DoS vector | Eviction of idle entries + cap; test case; `maxsize` config; metric on tracked-IP count |

## Options considered

| Option        | Pros                | Cons                  |
| ------------- | ------------------- | --------------------- |
| **(preferred) A — In-process token-bucket middleware, per IP, stdlib only** | Meets the stdlib/no-infra constraint; smooth limiting (allows short bursts, caps sustained rate); tiny memory per IP; trivially reversible via a mode setting | Per-*process* state — effective limit multiplies by worker count (see Impact); no cross-host coordination (acceptable: fleet is small/stable per ticket) |
| B — In-process fixed-window counter, per IP | Simplest possible logic | Boundary bursts: a client can send 2× the limit across a window edge; coarser fairness than a bucket for the same memory |
| C — Sliding-window log, per IP | Most accurate rate accounting | Stores a timestamp per recent request → far higher memory under attack (the exact condition we must survive); over-engineered for the goal |
| D — External limiter (Redis token bucket / nginx `limit_req` at the gateway) | Shared state across all workers/hosts; battle-tested | **Violates the standard-library / no-new-infra constraint**; adds a request-path dependency and an ops surface; rejected outright |
| Do nothing    | No cost             | Abuse continues to degrade latency for everyone; mitigation stays deploy-only |

**Preferred: A — in-process per-IP token bucket as WSGI middleware.**
A token bucket is the closest well-understood precedent for "cap
sustained rate but tolerate short bursts," and its per-IP state is
just two numbers (`tokens`, `last_refill`) — orders of magnitude less
memory than a sliding-window log (C) under the attack we must
survive. It beats a fixed-window counter (B) on boundary fairness for
the same footprint. The standard-library constraint rules out the
otherwise-attractive shared-state option (D); the ticket's "fleet is
small and stable" note is what makes per-process state acceptable —
see the worker-multiplier item in Impact, which is the main thing a
reviewer must sign off on.

The `429` response shape follows RFC 6585 / RFC 9110 (`429 Too Many
Requests` + `Retry-After`), the standard precedent for this status.

## Impact

**Cross-component (always check):**

- **Audience** — every unauthenticated caller of `GET /search`.
  Legitimate users must be unaffected (see Invariants); only clients
  exceeding the per-IP rate see `429`. :warning: **needs human
  input:** confirm no internal service or batch job calls `/search`
  through a single shared egress IP — such a caller would look like
  one heavy "client" and could be throttled as a group.
- **Coordinated changes** — none required in other services. The
  gateway already forwards client IP (ticket); we only *read* it. No
  partner change set is pulled into this plan.
- **Client compatibility** — clients that stay under the limit see no
  change. Clients over the limit must tolerate `429`/`Retry-After`;
  this is standard HTTP, but a naive scraper may retry-storm. No
  client *version* bump is needed.
- **Backwards compatibility** — `GET /search` request/response shape
  is unchanged for under-limit traffic; `429` is a new possible
  status code. No config or on-disk format changes.

**Project-specific:**

- **Edge / gateway** — the gateway forwards the client IP that keys
  the limiter. This feature does **not** change gateway config; the
  gateway is a hard scope boundary (see feasibility for the
  IP-source unknown).
- **Replication / persistence** — none. The limiter holds only
  in-memory, per-process state; nothing is written to a datastore.
- **Worker multiplier** — limits are enforced per WSGI worker
  process. With *N* workers on a host, a client's effective ceiling
  is roughly *N* × the per-process limit (load balancing across
  workers is not sticky by IP). Thresholds in `metrics.md` and the
  configured limit must account for *N*. :warning: **needs human
  input:** confirm the deployed worker/process count per host (see
  feasibility).
- **Admin UI / Analytics / External systems** — none.

<!-- Sections below are filled in during implementation: -->

## How it works

_(Filled in during implementation — will carry the end-to-end
request flow with file:line entry points once code exists.)_

## System interactions

_(Filled in during implementation.)_

## Configuration

_(Filled in during implementation. Planned settings — name, mode,
limit, burst, eviction — are drafted under_ [plan.md](plan.md)
_"Deployment plan" until ship, then move here.)_
