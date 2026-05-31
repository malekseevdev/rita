# RITA-1: plan

<!-- This file is ephemeral — delete it after shipping. -->

Options, trade-offs, and preferred solution live in
[`README.md`](README.md) (evergreen). Load-bearing assumptions and
verifications live in [`feasibility.md`](feasibility.md) (evergreen).
This file is the working scratchpad — implementation logistics that don't
outlive the launch.

## Implementation steps

Each step is independently mergeable and testable. The limiter is built
defaulting to `shadow` (observe-only), so early steps ship with **zero**
client-facing risk.

1. **Token-bucket core (pure, no WSGI).** A `TokenBucket` (capacity =
   burst, refill rate = sustained/sec, using `time.monotonic`) and a
   `BucketStore` keyed by client IP, backed by `collections.OrderedDict`
   as a bounded LRU (cap `SEARCH_RATELIMIT_MAX_TRACKED_IPS`, evict
   least-recently-used; lazy expiry of idle buckets). Guarded by a
   `threading.Lock`. Unit-tested in isolation — no network. *(No
   client-facing behavior yet.)*
2. **IP extraction.** A function that derives the client key from the WSGI
   `environ` using the confirmed forwarded header (see
   [feasibility.md](feasibility.md) — header name is an open question).
   Fail-open: if no usable IP is found, return a sentinel that the
   limiter always allows, and increment an error metric. Unit-tested
   against crafted `environ` dicts. *(No client-facing behavior yet.)*
3. **Config + mode loader.** Reads `SEARCH_RATELIMIT_MODE`
   (`off`/`shadow`/`enforce`) and the numeric settings from the
   config source, re-reading on mtime change with a short cache so the
   toggle flips without a redeploy. Invalid/missing → `shadow` (safe
   default: observe, never block). Unit-tested. *(No client-facing
   behavior yet.)*
4. **WSGI middleware wiring + metrics + shadow rollout.** <!-- partial
   value milestone --> Wrap the search WSGI app. In `off`: pass through.
   In `shadow`: run the check, emit `decision=shadow_throttle` metrics and
   a log line on would-be-throttle, but always pass through. In `enforce`:
   return `429` with `Retry-After` when the bucket is empty. Emit all
   metrics in [metrics.md](metrics.md). **Shipping this in `shadow`
   delivers partial value immediately**: real data on who *would* be
   throttled, used to tune the threshold before any user is affected.
5. **Tune + flip to `enforce`.** Using shadow data and the answers to the
   feasibility flags (worker count → per-worker rate), set the rate/burst
   and flip the mode to `enforce`. Backed by the test-cases in
   [test-cases.md](test-cases.md).
6. **Dashboards + runbook finalization.** Wire the metrics into a Grafana
   panel and confirm the runbook diagnostic steps execute.

## Concerns

- **Performance** — Per request: one dict lookup + arithmetic under a
  short-held lock. Sub-millisecond, negligible against search query
  latency. The single global `Lock` could contend under very high
  concurrency; acceptable for a "small, stable fleet." If contention shows
  up, shard the store by IP hash (deferred — not needed now).
- **Security** — The limiter trusts a forwarded header for the client IP.
  **If the gateway passes a client-supplied `X-Forwarded-For` through
  unmodified, the value is spoofable** — a scraper could rotate fake IPs
  to evade its bucket or forge another client's IP. Mitigation: read only
  the gateway-set value; this is the load-bearing open question in
  [feasibility.md](feasibility.md). The limiter is a latency-protection
  mechanism, not an auth boundary — it must not be relied on for access
  control. No sensitive data is read or stored (only IPs, in memory).
- **Data migration** — N/A. State is in-memory and per-process; nothing
  persisted, nothing to migrate or roll back.
- **Thread safety** — The per-IP store is shared across threads within a
  worker; all mutation goes through one `threading.Lock`. Across
  *processes* there is no shared state by design (stdlib-only, no Redis):
  each worker has independent buckets, so the effective limit is
  per-worker × worker count. This is documented, not a bug, but it is the
  main correctness caveat (see feasibility worker-count flag).
- **Scalability** — Memory is bounded by the LRU cap on tracked IPs;
  beyond the cap, least-recently-used IPs are evicted (their buckets
  reset). At 10× load the first things to watch are lock contention and
  the eviction rate (high eviction = churn through many IPs, e.g. a
  rotating scraper, which per-IP limiting cannot fully stop — a known
  limitation, not solved here).
- **Observability** — New metrics across usage/errors/performance plus the
  protected-system signal (search p95). See [metrics.md](metrics.md). A
  log line on every shadow/enforce throttle decision (rate-limited to
  avoid log floods) names the IP and current bucket level.
- **Failure modes** — Fail-open everywhere: if IP extraction fails, the
  config is unreadable, or the limiter raises, the request is **allowed**
  and an error metric increments. A limiter bug must never take down
  search. Throttled clients see a loud, explicit `429` + `Retry-After`;
  under-limit clients see no change.
- **Operability** — Ops needs: the `SEARCH_RATELIMIT_MODE` toggle and how
  to flip it without a deploy (the kill switch), the dashboard, and the
  runbook. All delivered by this work ([runbook.md](runbook.md),
  [metrics.md](metrics.md)).

## Dependencies

| Dependency           | Type        | Status      |
| -------------------- | ----------- | ----------- |
| Gateway team — confirm forwarded-IP header name + trust/overwrite behavior (feasibility flag #1) | blocks us (correct keying + security) | not started |
| Platform/ops — worker & host count, and config-push mechanism without redeploy (feasibility flags #2, #3) | blocks us (threshold tuning + kill switch) | not started |
| Metrics/observability pipeline — scrape the new metrics; Grafana panel | we block (dashboard) | not started |

The first two block flipping to `enforce`, **not** shipping in `shadow`.
Shadow mode can deploy as soon as steps 1–4 are merged, which is how we
de-risk the unknowns.

## Deployment plan

- **Runtime toggle — `SEARCH_RATELIMIT_MODE` (tri-state, not a plain
  flag).** Values: `off` | `shadow` | `enforce`. This single setting plays
  two roles deliberately:
  - *Feature-flag role:* first deploy ships in `shadow`, so new
    client-facing behavior (the `429`) is gated off until we flip to
    `enforce`. This matches "add a feature flag when the change has
    client-facing behavior with non-trivial blast radius."
  - *Kill-switch role:* setting it back to `shadow` or `off` instantly
    disables enforcement in an emergency — the ticket's core ask.
  - *Why one tri-state instead of a `FEATURE_*` flag + a `KILL_*` switch:*
    `off`/`shadow`/`enforce` are mutually exclusive states of one concept
    ("how much limiting is active"); two booleans would have a meaningless
    fourth combination and a more confusing kill path. Naming note: this
    deviates from the `FEATURE_`/`KILL_` prefix convention on purpose; the
    `SEARCH_RATELIMIT_MODE` name makes the three states legible to oncall.
    There is no existing config precedent in this (greenfield) service to
    match against. :warning: **needs human input:** confirm this naming
    fits the service's config conventions once they exist.
  - *Lifecycle:* the kill-switch role is kept indefinitely (it's the "melt
    down at 3 AM" mitigation). There is no separate flag to remove later —
    `shadow` remains a useful permanent diagnostic mode.
  - *No-redeploy requirement:* the toggle must be changeable without a
    code deploy — see feasibility flag #3; the reload mechanism depends on
    the ops answer.
- **Other settings:** `SEARCH_RATELIMIT_RATE` (sustained req/sec per IP
  *per worker*), `SEARCH_RATELIMIT_BURST` (bucket capacity),
  `SEARCH_RATELIMIT_MAX_TRACKED_IPS` (LRU cap). Defaults set conservatively
  high after shadow data; placeholders until then.
- **Rollout stages** (fleet is small/stable → big-bang deploy gated by
  mode is appropriate; no per-percentage traffic infra needed):
  1. Deploy in `shadow` to all hosts. Watch for ~a representative traffic
     window.
  2. Tune rate/burst from shadow data (target: shadow_throttle near-zero
     for normal traffic, non-zero for the known scraper pattern).
  3. Flip `SEARCH_RATELIMIT_MODE=enforce` (no redeploy).
- **Monitoring to watch at each stage** (error/perf signals move fast;
  these are the ones to gate on — see [metrics.md](metrics.md)):
  - `search.ratelimit.decision{decision=...}` rates (esp. `throttle` /
    `shadow_throttle`).
  - `search.ratelimit.errors` (fail-open events — should be ~0).
  - `search.ratelimit.check_latency` p95 (should be sub-ms).
  - **Search overall p95 latency** — the thing we're protecting; it should
    improve or hold under abuse once enforcing.
  - Distinct throttled IPs (a sudden spike across *many* IPs after
    enforce = mis-tuned threshold → flip back to `shadow`).

## Rollback strategy

- **Primary: toggle flip.** `SEARCH_RATELIMIT_MODE=shadow` (keep
  observing) or `off` (full stop) — seconds, no redeploy, no restart
  (assuming feasibility flag #3 is satisfied).
- **Contingency if flag #3 resolves to "env-var-at-start-only"** (i.e. the
  mode genuinely cannot be changed without touching the process): the
  guaranteed fast path becomes a **process restart with
  `SEARCH_RATELIMIT_MODE=off`** set in the environment (rolling restart
  across the small fleet — tens of seconds to low minutes, still far
  faster than the code-deploy that is today's only option), with a
  **SIGHUP-triggered config reload** added in implementation as the
  preferred mechanism if the host setup allows it. The "seconds, no
  redeploy" claim above holds only if a writable config source or SIGHUP
  reload is available; this contingency ensures a fast off-switch exists
  *either way*, satisfying the ticket's core ask.
- **Secondary: revert + redeploy** the middleware wiring if the toggle
  path itself is broken — minutes.
- **Blast radius while broken:** worst case is over-throttling legitimate
  users (they get `429`s). Bounded by the toggle flip above. Fail-open
  design means a *limiter crash* degrades to "no limiting," never to "no
  search."
- **Data at risk:** none. All state is in-memory; rollback loses only the
  transient buckets, which simply rebuild. No corrupted persistent state
  can survive a rollback.

## Definition of done

- [ ] Plan reviewed and approved (agent self-review + author + peer).
- [ ] `README.md` "Options considered" + "Preferred" finalised, and the
      "How it works"/"System interactions"/"Configuration" sections filled
      with file:line references to the shipped middleware.
- [ ] `feasibility.md` frozen; the three external-unknown flags resolved
      (gateway header confirmed, worker count known, config-push path
      confirmed) and any that turned into verifiable facts recorded.
- [ ] `SEARCH_RATELIMIT_MODE` setting exists, reads `off`/`shadow`/
      `enforce`, defaults to `shadow`, and is changeable without a redeploy
      (verified by changing it on a host and observing a request's decision
      flip).
- [ ] `GET /search` returns `429` with a `Retry-After` header for an IP
      that exceeds `SEARCH_RATELIMIT_RATE`/`BURST` in `enforce` mode, and
      `200` for the same load in `shadow`/`off`.
- [ ] A distinct second IP under the limit still gets `200` while the first
      is throttled (isolation), proven by a test in `test-cases.md`.
- [ ] Every scenario in `test-cases.md` is backed by an implemented test.
- [ ] Metrics `search.ratelimit.decision`, `.errors`, `.check_latency`,
      `.tracked_ips` are emitted and listed in `metrics.md` with thresholds
      + a dashboard link.
- [ ] Baseline values (pre-enforce search p95, shadow throttle counts)
      recorded in the RITA-1 ticket.
- [ ] `runbook.md` covers: "legit users getting 429s," "limiter not
      throttling a known abuser," and "how to flip the kill switch."
- [ ] `plan.md` deleted.
- [ ] Deployment plan followed (shadow → tune → enforce); rollback
      strategy documented in the ticket.
- [ ] Concerns checklist has no unresolved items.
