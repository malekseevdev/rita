# RITA-1: plan

<!-- This file is ephemeral — delete it after shipping. -->

Options, trade-offs, and preferred solution live in
[`README.md`](README.md) (evergreen). Load-bearing assumptions and
verifications live in [`feasibility.md`](feasibility.md) (evergreen).
This file is the working scratchpad — implementation logistics that
don't outlive the launch.

## Implementation steps

1. **Token-bucket core** — a stdlib-only `TokenBucket`/`RateLimiter`
   class: per-key `(tokens, last_refill)` state in a dict guarded by a
   `threading.Lock`; lazy refill from `time.monotonic()` deltas;
   `allow(key) -> (allowed: bool, retry_after: float)`. Capacity =
   burst, refill = rate/sec. Unit-tested in isolation (no WSGI). —
   *partial value: the algorithm is reviewable/testable on its own.*
2. **Memory bounding** — cap the IP→bucket map at `MAXSIZE` and evict
   idle entries (entry untouched for longer than its full refill
   time can be dropped — it would be recreated full anyway). Enforces
   the "memory-bounded" invariant. Test eviction under a flood of
   distinct keys.
3. **Mode + config plumbing** — read `SEARCH_RATELIMIT_*` settings
   (mode, rate, burst, maxsize, ip-header) once at startup; expose
   `mode` re-readable at request time so a flip takes effect without
   restart (mechanism per how it's wired — env re-read or a watched
   config value). Default mode `off`.
4. **WSGI middleware** — wrap the `/search` WSGI callable. Extract the
   client IP from the configured environ key; on `allow()==False`
   and `mode==enforce`, short-circuit with `429` + `Retry-After`;
   otherwise call through. In `shadow` mode, evaluate + emit metrics
   but always call through. Wrap evaluation in try/except → on any
   limiter-internal error, **fail open** (serve the request) and emit
   the error metric. — *partial value: shippable in `shadow` mode here.*
5. **Metrics** — emit the counters/gauges in
   [`metrics.md`](metrics.md) (decisions, mode, tracked-IP gauge,
   limiter errors), using the service's existing metrics helper if one
   exists (do not invent parallel infra).
6. **Tests + runbook** — implement every scenario in
   [`test-cases.md`](test-cases.md); finalise [`runbook.md`](runbook.md)
   with real metric/log queries.

Steps 1–2 are pure unit-testable logic. Step 4 in `shadow` mode is the
first deployable increment that produces the baseline needed to set
the real limit (see Deployment plan).

## Concerns

- **Performance** — adds a dict lookup, a lock acquire/release, and a
  little arithmetic per `/search` request. Negligible vs. a search
  query, but the single lock is a per-process serialization point;
  under very high RPS consider sharding the lock by key hash. Assess
  with the p95-latency delta in `shadow` mode before enforcing.
- **Security** — the limiter *is* an abuse control, but it trusts the
  client-IP source. If the IP comes from a client-settable forwarded
  header that the gateway doesn't overwrite, an attacker rotates it to
  get unlimited buckets and bypasses the limit (and inflates the
  tracked-IP map). This is the load-bearing security question — see
  the IP-source unknown in [`feasibility.md`](feasibility.md).
- **Data migration** — N/A. No schema, no persisted state.
- **Thread safety** — shared mutable state (the bucket map) is
  accessed from concurrent WSGI worker threads; all reads/writes go
  through one `threading.Lock`. State is per-process only — no
  cross-process or cross-host sharing by design (Option A trade-off).
- **Scalability** — at 10× load the first thing to strain is lock
  contention (above) and the tracked-IP map under a distinct-IP flood;
  `MAXSIZE` + eviction bound the memory, but eviction churn itself
  costs CPU. The per-process model means the *effective* limit scales
  with worker count, not down — see the worker-multiplier item in
  README Impact.
- **Observability** — decision counter (allowed/throttled/shadowed),
  current mode, tracked-IP gauge, and limiter-error counter; all in
  [`metrics.md`](metrics.md). `shadow` mode exists specifically so we
  can observe would-be-throttles before any user is affected.
- **Failure modes** — limiter bug or exhaustion → fail *open* (request
  served, error metric incremented); the endpoint never 500s because
  of the limiter (invariant). A *misconfigured* low limit → legitimate
  users get `429`; mitigated by shadow-first rollout and the
  seconds-fast mode flip.
- **Operability** — on-call needs: how to read the mode, how to flip
  it to `off`/`shadow`, and which metrics show a misfire. Covered in
  [`runbook.md`](runbook.md).

## Dependencies

| Dependency           | Type        | Status      |
| -------------------- | ----------- | ----------- |
| Confirm client-IP environ key + gateway trust (feasibility) | blocks `enforce` (not `shadow`) | needs human input |
| Worker count per host (feasibility) | blocks limit-value choice | needs human input |
| Existing metrics helper / emit path in the search service | blocks step 5 | unknown — no code in repo yet |
| Live config-reload mechanism for `MODE` (feasibility) | blocks the "seconds" kill-switch claim | needs human input |

We block: nothing. No downstream consumer depends on this.

## Deployment plan

**Runtime toggle — a permanent mode setting (not a temporary flag).**
`SEARCH_RATELIMIT_MODE ∈ {off, shadow, enforce}`, default **`off`**.

- It gates new client-facing behaviour during rollout (`off → shadow →
  enforce`), the feature-flag role.
- It is **kept indefinitely** as the emergency off-switch (flip
  `enforce → off`/`shadow` in seconds, no deploy) — the kill-switch
  role the ticket asks for.

A single tri-state setting is chosen over two booleans because the
states are mutually exclusive and `shadow` (the safe middle) must be
first-class. It deliberately departs from the `FEATURE_`/`KILL_`
naming convention because it is neither purely temporary nor purely
emergency — it is a permanent operational mode. The other settings:
`SEARCH_RATELIMIT_RATE` (sustained req/s per IP), `_BURST` (bucket
capacity), `_MAXSIZE` (max tracked IPs), `_IP_HEADER` (environ key).

**Rollout stages** (gradual; blast radius is all `/search` users):

1. **Deploy in `off`** — code present, zero behaviour change.
2. **`shadow` in staging, then production** — limiter evaluates and
   emits metrics but never rejects. Watch the *would-throttle* rate
   and tracked-IP gauge. Set the real `RATE`/`BURST` from this
   baseline so that **0 legitimate clients would be rejected**
   (invariant). This step resolves the "what limit?" question with
   data instead of a guess.
3. **`enforce` for a small slice, then full** — flip to `enforce`;
   watch the throttle rate, `/search` p95 latency, and the 5xx rate.
   Roll to 100% once the throttle rate matches the shadow prediction
   and latency is unchanged for under-limit traffic.

**Signals to watch** (from [`metrics.md`](metrics.md), error/perf
first — usage/business move slower): `search.ratelimit.decision`
(throttled vs allowed), `/search` p95 latency delta, `/search` 5xx
rate, `search.ratelimit.errors`, `search.ratelimit.tracked_ips`.

## Rollback strategy

- **Primary: mode flip** — `enforce → shadow` (keep observing, stop
  rejecting) or `→ off` (fully disabled). Seconds, no deploy. This is
  the realistic failure path (limit set too low → legitimate `429`s)
  and it is cheaply reversible, which is why a percentage rollout —
  not more gates — is sufficient.
- **Secondary: revert + redeploy** — if the middleware itself is
  faulty in a way the mode flip doesn't neutralise. Minutes.
- **Data at risk:** none. State is in-memory and per-process; a
  restart or rollback simply drops all buckets (clients start fresh).

## Definition of done

- [ ] Plan reviewed and approved before implementation started
- [ ] `README.md` "Options considered" + "Preferred" finalised
- [ ] `feasibility.md` frozen; the three external unknowns resolved by
      a human (IP environ key + gateway trust; worker count; WSGI
      entry point) — recorded in the ticket
- [ ] `README.md` "How it works" / "System interactions" /
      "Configuration" filled with file:line refs to the shipped code
- [ ] Limiter uses **standard library only** — CI grep over the
      limiter module shows no third-party imports; `requirements.txt`
      unchanged
- [ ] `429` response carries a `Retry-After` header (test
      `test_ratelimit.py::test_throttled_sets_retry_after`)
- [ ] Limiter-internal exception → request still served, not `500`
      (test `test_ratelimit.py::test_fails_open_on_error`)
- [ ] Tracked-IP map is bounded at `SEARCH_RATELIMIT_MAXSIZE` under a
      distinct-IP flood (test `test_ratelimit.py::test_map_bounded`)
- [ ] `SEARCH_RATELIMIT_MODE` flip (`enforce`→`off`) takes effect
      without a redeploy (runbook one-shot verified)
- [ ] `plan.md` deleted
- [ ] Metrics in `metrics.md` (decision, mode, tracked_ips, errors)
      emitted and listed with thresholds + dashboard link
- [ ] Shadow-mode baseline recorded in the ticket; chosen `RATE`/
      `BURST` shown to reject 0 legitimate clients at that baseline
- [ ] Runbook covers: misfire (legit users throttled), bypass
      (limit never trips), and limiter errors
- [ ] Concerns checklist has no unresolved items
