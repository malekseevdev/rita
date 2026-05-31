# RITA-1: Rate-limit the public search endpoint

> Status: Plan
> Last reviewed: 2026-05-31
> Ticket: RITA-1

| Document                                 | Purpose                            |
| ---------------------------------------- | ---------------------------------- |
| This file                                | What the feature is and how it works |
| [feasibility.md](feasibility.md)         | Load-bearing assumptions + verifications (evergreen) |
| [plan.md](plan.md)                       | Implementation logistics — ephemeral, deleted at ship |
| [test-cases.md](test-cases.md)           | User-perspective scenarios         |
| [metrics.md](metrics.md)                 | Metrics catalog and baseline       |
| [runbook.md](runbook.md)                 | Agent-friendly operational runbook |

> **Planning assumptions (autonomous run — confirm before build).** The
> repo currently contains only `TICKET.md`; there is no search-service
> code yet. This plan assumes the WSGI app lives (or will live) under
> `search-service/` and that the rate limiter is added there as in-process
> WSGI middleware. File:line references are deferred to implementation.
> The load-bearing open questions are flagged in
> [feasibility.md](feasibility.md) — chiefly **which header the gateway
> uses to forward the client IP** and **how many worker processes/hosts
> serve the endpoint**. Neither blocks writing this plan, but both must be
> answered before the threshold can be set correctly.

## Overview

This feature adds **per-client (per-IP) rate limiting** to the public,
unauthenticated `GET /search` endpoint. Each client IP gets a token
bucket; requests that arrive faster than the configured rate receive an
HTTP `429 Too Many Requests` response with a `Retry-After` header, while
clients within their budget are unaffected. The limiter is implemented as
self-contained WSGI middleware using **only the Python standard library**
— no Redis, no `flask-limiter`, no new request-path infrastructure. A
single runtime setting (`SEARCH_RATELIMIT_MODE`) selects `off`, `shadow`
(count-and-log only, never block), or `enforce`, and can be changed
without a redeploy so operators can disable enforcement in seconds if it
misfires.

## Why

`GET /search` is public and unauthenticated. A single scraper has already
pushed enough query volume to degrade search latency for *everyone*, and
today the only mitigation is to ship a deploy — minutes-to-hours of
exposure while a human writes, reviews, and releases a change. We need to
(a) automatically throttle a small number of abusive clients before they
degrade shared latency, (b) leave normal users untouched, and (c) hold a
fast off-switch for when the limiter itself misbehaves. The constraint is
that the fix must be self-contained in the search service: standard
library only, no new infrastructure on the request path.

## Options considered

| Option        | Pros                | Cons                  |
| ------------- | ------------------- | --------------------- |
| **(preferred) A — In-process per-IP token bucket (WSGI middleware, stdlib)** | Stdlib-only, zero new infra/deps; O(1) state per IP; allows normal bursts; ships entirely inside the search service; instant `mode` toggle. | Buckets are **per worker process** — no shared state, so the effective limit is `per_worker_rate × workers × hosts` (must tune for this). Per-IP keying is defeated by IP rotation. |
| B — In-process sliding-window counter (stdlib) | More accurate at window boundaries than a fixed window; stdlib-only. | Stores per-IP timestamp lists → more memory and GC churn than a bucket; same per-process limitation as A; more code for marginal accuracy gain at our scale. |
| C — Push rate limiting to the gateway/proxy | Naturally shared across all workers/hosts (one correct limit); keeps app stateless; battle-tested limiter implementations; the gateway already terminates the client connection and knows the real IP. | Out of scope for this ticket (explicitly "self-contained in the search service, no new infra"); depends on gateway capability we may not have and a cross-team change; longer lead time. **Named honestly as the architecturally "right" long-term home — see Preferred.** |
| D — Manual IP blocklist (automate today's "ship a deploy") | Simple; precise for a known bad actor. | Reactive, not preventive; needs a human to identify and add each IP; doesn't protect against a *new* scraper degrading latency before anyone notices. |
| Do nothing | No cost. | Problem remains: one scraper can degrade latency for everyone; mitigation stays a slow deploy. |

**Preferred: A — in-process per-IP token bucket as stdlib WSGI
middleware.** It is the only option that satisfies the ticket's hard
constraints (standard library only, no new request-path infrastructure,
self-contained in the search service) while actively *preventing* latency
degradation rather than reacting to it (vs. D). The token-bucket
algorithm is chosen over a sliding window (B) because it allows the short
bursts normal clients produce while still capping sustained abuse, with
O(1) state per IP and no timestamp lists.

The honest caveat, stated up front: gateway-level limiting (C) is the
architecturally correct long-term home — it would give a single
fleet-wide limit instead of a per-worker one and keep the app stateless.
We are deliberately *not* doing C now because the ticket scopes the work
to the service and forbids new infra, and because C requires a cross-team
gateway change. **Recommendation:** ship A as the immediate,
self-contained mitigation, and file a follow-up to evaluate moving
enforcement to the gateway (C) once the fleet grows beyond where
per-worker limits are easy to reason about. The per-worker limitation of A
is acceptable *today* specifically because the ticket states the fleet is
"small and stable."

## Impact

On-call and future modifiers read this section to understand the blast
radius without re-deriving it from code.

**Cross-component (always check):**

- **Audience** — every unauthenticated caller of `GET /search`. The
  intent is that *normal* users see no change and only sustained
  high-volume clients (scrapers) see `429`s. A mis-tuned threshold or a
  bad IP extraction (see below) is the main way legitimate users could be
  affected — e.g. many users behind one corporate NAT/proxy sharing one
  IP would share one bucket. :warning: **needs human input:** is shared-IP
  traffic (corporate NAT, mobile carrier CGNAT) a real segment for this
  endpoint? It affects how generous the per-IP limit must be.
- **Coordinated changes** — depends on the **gateway** forwarding the
  client IP in a known, trustworthy header (e.g. an `X-Forwarded-For` the
  gateway sets, not a blindly-trusted client-supplied value). No code
  change is required *in* the gateway for option A, but its header
  behavior is load-bearing and must be confirmed (see
  [feasibility.md](feasibility.md)). Can be deployed independently of
  other services once that header contract is confirmed.
- **Client compatibility** — no client software change required. Clients
  that don't handle `429`/`Retry-After` will simply see a failed request
  during throttling; well-behaved clients back off. Older clients are
  safe (the endpoint contract is unchanged for under-limit traffic).
- **Backwards compatibility** — additive. Under-limit responses are
  unchanged. The only new observable behavior is the `429` response for
  over-limit clients. No API schema, config format, or on-disk format
  changes.

**Project-specific:**

- **Edge / gateway** — this introduces rate-limiting behavior at the
  *application* layer, behind the gateway. **Reconciliation rule for when
  option C ships:** when a gateway limiter is enabled, set the app-layer
  `SEARCH_RATELIMIT_MODE=shadow` so the gateway *owns* enforcement
  (fleet-wide, correct limit) and the app only observes — never two layers
  both returning `429` for the same client. The C-rollout owner is
  responsible for that cutover (flip app to `shadow` in the same change
  that enables the gateway limiter), and the app-layer limiter can later be
  removed once C is stable. Until then the app layer enforces.
- **Replication / persistence** — none. Limiter state is in-memory and
  per-process; nothing is written to a database or fans out to replicas.
- **Admin UI** — none. Control is via the `SEARCH_RATELIMIT_MODE` setting
  and the metrics dashboard, not a UI.
- **Analytics / data warehouse** — none directly; the new metrics (see
  [metrics.md](metrics.md)) may be scraped into the existing metrics
  pipeline.
- **External systems** — none on the request path (that is the point of
  the stdlib-only constraint).

<!-- Sections below are filled in during implementation: -->

## How it works

_(Filled in during implementation — Phase 4. Will document the WSGI
middleware entry point, the token-bucket data structure, IP extraction,
and the mode-toggle reload, with file:line references.)_

## System interactions

_(Filled in during implementation — Phase 4.)_

## Configuration

_(Filled in during implementation — Phase 4. Will document
`SEARCH_RATELIMIT_MODE`, the per-IP rate/burst settings, the
config-reload mechanism, and defaults. Draft intent is in
[plan.md](plan.md) under Deployment plan.)_
