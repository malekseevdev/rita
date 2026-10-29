# RITA-1: per-client rate limiting for `GET /search`

> Status: Plan
> Last reviewed: 2026-10-29
> Ticket: RITA-1

| Document                                 | Purpose                            |
| ---------------------------------------- | ---------------------------------- |
| This file                                | What the feature is and how it works |
| [feasibility.md](feasibility.md)         | Load-bearing assumptions + verifications (evergreen) |
| [plan.md](plan.md)                       | Implementation logistics — ephemeral, deleted at ship |
| [test-cases.md](test-cases.md)           | User-perspective scenarios         |
| [metrics.md](metrics.md)                 | Metrics catalog and baseline       |
| [runbook.md](runbook.md)                 | Agent-friendly operational runbook |

> **Planning assumptions (headless run, no human consulted):**
> - The component is `search-service/` (from the ticket's *Component*
>   field).  The search service's source is **not in this repository**,
>   so every file path below is a proposal, not a reference to existing
>   code.
> - No in-repo precedent exists to ground the API in; the `429` +
>   `Retry-After` contract follows RFC 6585 / RFC 9110.
> - Open questions are collected in
>   [Open questions](#open-questions-needs-human-input) at the bottom of
>   this section, and in [feasibility.md](feasibility.md).

## Overview

A small WSGI middleware in front of the search app gives every client IP
a token bucket.  Requests to `GET`/`HEAD /search` that find the client's bucket
empty get `429 Too Many Requests` with a `Retry-After` header; everything
else passes through untouched.  The limiter has three runtime modes —
`enforce`, `shadow` (count and log what *would* be throttled, block
nothing) and `off` — and operators change the mode by editing a file on
the host, without a deploy or restart.  How fast that reaches the
*whole* fleet depends on ops tooling we haven't confirmed
(feasibility.md *Mode-file propagation*).

## Why

`GET /search` is public and unauthenticated.  One scraper has already
pushed enough volume to degrade latency for every user, and the only
remedy today is shipping a deploy.  We need the service itself to shed a
single abusive client's excess load, and we need an equally fast way to
switch that protection off if it starts hurting real users.

## Invariants & constraints

:warning: **needs human input — confirm before build.**  Drafted from the
ticket in a headless run; approve, edit or add.

| # | Constraint | Why it's load-bearing | How it's checked |
| - | ---------- | --------------------- | ---------------- |
| C1 | Python standard library only — no new third-party runtime dependency, no new infrastructure (Redis, sidecar, DB) on the request path | Ticket requirement; keeps the limiter self-contained and verifiable with zero installs | DoD: `search-service` dependency manifest diff is empty; `grep -E '^(import|from) ' ratelimit.py` lists only stdlib modules |
| C2 | Only `GET`/`HEAD /search` is limited; every other route and method is byte-for-byte unaffected | Health checks and internal routes must never be throttled | test-cases.md *Scope* scenarios |
| C3 | In `off` and `shadow` modes no request is ever rejected by the limiter | These modes are the kill switch and the safe rollout stage | test-cases.md *Modes* scenarios |
| C4 | A mode change takes effect on every process of a host within `SEARCH_RATELIMIT_MODE_TTL` (default 5 s) of the file being written, with no restart or deploy | Ticket: "turn enforcement off quickly"; deploys are the problem we're removing | test-cases.md *Kill switch* scenario |
| C5 | The limiter fails open: any internal error in the limiter lets the request through and is counted | A limiter bug must not become a search outage | test-cases.md *Failure* scenario; `search.ratelimit.errors` metric |
| C6 | Limiter memory is bounded (`SEARCH_RATELIMIT_MAX_KEYS`) regardless of how many distinct client keys arrive | A scraper rotating IPs must not exhaust worker memory | test-cases.md *Key-flood* scenario |
| C7 | The client key cannot be chosen by the client — it is derived only from the hop the gateway itself wrote | Otherwise a scraper evades the limit by sending a fake `X-Forwarded-For` | test-cases.md *Client key* scenarios; depends on feasibility.md *Gateway header* |

## Options considered

| Option | Pros | Cons |
| ------ | ---- | ---- |
| **(preferred) A. In-process token bucket per client IP, WSGI middleware, file-based mode switch** | Stdlib only (C1); no new hop; O(1) per request; burst-tolerant so normal users browsing quickly aren't hit; mode file gives a no-deploy kill switch | Each process has its own view, so the effective per-client limit is *per-process limit × processes the client's traffic spreads over* — tuned by hand, re-tuned when the fleet changes; mode-file propagation across hosts relies on existing ops tooling |
| B. Rate limit at the gateway (e.g. nginx `limit_req`) | One global view per gateway; rejects before reaching the app; mature | Not ours to change (external service, separate team / config); gateway technology is unknown to us; ticket asks for the search service to own it.  **Worth raising with the gateway owners as the long-term home** if the fleet grows |
| C. Shared counter store (Redis / memcached / SQLite on shared disk) | Exact global limit across the fleet | Violates C1 (third-party client and/or new infra on the request path); adds a network hop and a new failure mode per request |
| D. Fixed-window counter per IP instead of token bucket | Simpler to explain | Allows 2× bursts at window boundaries; punishes users at window edges; no real saving in code |
| E. Global concurrency cap / load shedding (not per client) | Protects latency regardless of who causes load | Sheds *normal* users together with the scraper — the opposite of the ask.  Complementary, not a substitute |
| Do nothing | No cost | Next scraper degrades search for everyone again; mitigation still needs a deploy |

**Preferred: A.**  It is the only option that satisfies C1 and is
entirely inside the search service.  Its weakness — per-process rather
than global counting — is acceptable *because the fleet is small and
stable* (ticket): we divide the target per-client rate by the number of
processes a client's traffic spreads over and accept the approximation.
The approximation is only as good as that process count: if it is wrong
the limit is N× too loose or too tight (feasibility.md *Process
topology*), and a client pinned to one process by keep-alive gets *less*
than the target — which is why `BURST`/`RATE` are sized from shadow-mode
measurements of real per-process traffic, with 3× headroom (plan.md step
5), rather than computed.  If the fleet grows or autoscales, the fix is
option B, not a shared store.

**Decision records** (each self-contained):

-   [ADR 0001 — mode file as the kill switch](decisions/0001-mode-file-kill-switch.md)
    — precedence file > env, fail-to-shadow, propagation fallback.
-   [ADR 0002 — client-key derivation](decisions/0002-client-key-derivation.md)
    — rightmost-trusted `X-Forwarded-For`, IPv6 /64, fail-open on no key.

## The model

```
request ─► GET/HEAD /search? ── no ──► app             (C2)
                │ yes
                ▼
           mode = read mode file (cached ≤ MODE_TTL)   (C4)
           off ──────────────────────────────► app
                │ shadow / enforce
                ▼
           key = client_key(environ)                    (C7)
           no key ──► count key_fallback ────────────► app
           bucket[key]: tokens = min(BURST, tokens + RATE × Δt)   (monotonic clock)
           tokens ≥ 1 ? ── yes ──► tokens -= 1 ──► app
                │ no
                ▼
           shadow  ─► count "would_throttle" ──► app   (C3)
           enforce ─► 429 + Retry-After = ceil((1 − tokens) / RATE) s
any exception inside the limiter ─► count error ──► app  (C5)
```

-   **Scope:** `GET` and `HEAD /search` (HEAD runs the same search work);
    every other method and path, including `/search/`, passes through.
-   **Client key** ([ADR 0002](decisions/0002-client-key-derivation.md)):
    the `SEARCH_RATELIMIT_TRUSTED_HOPS`-th `X-Forwarded-For` entry from
    the right, IPv6 truncated to `/64`.  No usable key → pass unlimited,
    counted as `key_fallback`.
-   **State:** one `OrderedDict[key → (tokens, last_seen, count)]` per
    process, guarded by one `threading.Lock`, LRU-evicted beyond
    `MAX_KEYS` (C6).  An evicted key restarts with a full bucket.
-   **Mode** ([ADR 0001](decisions/0001-mode-file-kill-switch.md)): the
    mode file (`enforce` | `shadow` | `off`) wins; the
    `SEARCH_RATELIMIT_MODE` env var applies only when the file is absent;
    unreadable or unrecognised contents → `shadow`, counted.
-   **Config:** `RATE` and `BURST` must be > 0 and integers/floats must
    parse, else the process refuses to start — loud, at deploy time, never
    per request.

## Impact

-   **Audience** — anonymous `GET /search` callers.  Normal users should
    see no change; heavy automated clients see `429`s.  At-risk segment:
    many users behind one IP (corporate NAT, carrier-grade NAT, schools)
    share a bucket — the shadow stage exists to size `BURST`/`RATE` so
    these don't trip.  :warning: needs human input — are there known
    high-volume *legitimate* clients (partners, internal tools, our own
    frontend server-side rendering through the gateway) that need an
    allow-list?  The model has none today.
-   **Coordinated changes** — none required to ship.  Correct keying
    *depends on* the gateway's forwarding behaviour (feasibility.md) but
    needs no gateway change if it behaves as assumed.  Ops tooling must be
    able to write the mode file on every search host (Dependencies in
    plan.md).
-   **Client compatibility** — clients that already handle `429` /
    `Retry-After` (RFC 6585 / RFC 9110) back off correctly.  Clients that
    don't will see errors only once they exceed the limit, which normal
    users won't.  The `429` body follows the service's existing error
    shape — :warning: needs human input: what that shape is.
-   **Backwards compatibility** — no API, schema, or on-disk format
    changes.  New env vars are all optional with safe defaults.
-   **Edge / gateway** — no routing or caching change.  If the gateway
    caches `GET /search`, cached hits never reach the limiter (fine) and
    `429`s must not be cached — :warning: needs human input: does the
    gateway cache 4xx responses?
-   **Persistence / analytics** — none; limiter state is in memory and
    deliberately lost on restart.

### Open questions (needs human input)

1.  Constraints C1–C7 and *The model*: approve / edit / add?
2.  Gateway header, process topology, mode-file propagation — see
    feasibility.md.
3.  Legitimate high-volume clients needing an allow-list (Impact).
4.  Existing error-body shape for the `429` (Impact).
5.  Does the gateway cache 4xx? (Impact)
6.  How metrics leave the process today, and the name of the existing
    search p95 latency metric (metrics.md).
7.  The search app's package layout and entry point (plan.md, top).
8.  Approval of the `RATE`/`BURST` values derived in shadow (plan.md
    step 5).
9.  May throttle logs contain raw client IPs, or must they be hashed?
    (plan.md *Security*)
10. CI Python version: the stdlib-only test uses
    `sys.stdlib_module_names` (≥ 3.10); if CI is older, it hardcodes an
    allow-list instead (test-cases.md *Standard library only*).

<!-- Sections below are filled in during implementation: -->

## How it works

_(Filled in during implementation.)_

## System interactions

_(Filled in during implementation.)_

## Configuration

_(Filled in during implementation — planned knobs are listed in plan.md
step 1.)_
