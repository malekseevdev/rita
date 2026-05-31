# RITA-1: metrics

See [`docs/how-to.md`](../docs/how-to.md#metric-definition-reference) for
the four axes (usage, errors, performance, business).

| Metric (with tags) | Axis | Meaning | Threshold to watch |
| --- | --- | --- | --- |
| `search.ratelimit.decision,decision=allow\|throttle\|shadow_throttle` (counter) | usage / business | One increment per request, tagged by what the limiter decided. `throttle` = a `429` was returned (`enforce`); `shadow_throttle` = would-have-throttled but passed through (`shadow`); `allow` = under limit. | In `enforce`, a sudden jump in `throttle` across **many distinct IPs** = mis-tuned threshold → flip to `shadow`. Steady small `throttle` on few IPs = working as intended. |
| `search.ratelimit.tracked_ips` (gauge) | performance | Number of IPs currently held in the bucket store. | Approaching `SEARCH_RATELIMIT_MAX_TRACKED_IPS` = high IP churn (possible rotating scraper) and constant LRU eviction. Alert near the cap. |
| `search.ratelimit.check_latency` (timing) | performance | Time spent in the limiter check per request. | p95 should be sub-millisecond. p95 > ~5ms = lock contention or a bug; investigate. |
| `search.ratelimit.errors,reason=no_client_ip\|config_unreadable\|internal` (counter) | errors | A fail-open event: the limiter could not run correctly and allowed the request. | Should be ~0. Any sustained nonzero rate means the limiter is effectively disabled for some traffic (e.g. IP header missing) — investigate immediately. |
| `search.request.latency` (timing) — *existing/derived search latency* | business | The shared search latency the feature exists to protect. | p95 should hold or improve under abuse once `enforce` is on. Regression here is the signal the whole feature targets. |

Tag cardinality note: `decision` and `errors.reason` are bounded
low-cardinality enums. Do **not** tag by client IP (unbounded
cardinality); IPs go in throttle *log lines* (rate-limited), not metric
tags.

## Dashboards

_(Link Grafana panels here once created — Phase 6. Planned panels: decision
rates stacked by `decision`; tracked_ips vs cap; check_latency p95; errors
by reason; search p95 overlaid with throttle rate.)_

## Baseline

_(Record before flipping to `enforce` — frozen values live in the RITA-1
ticket, not here:)_

- Search `request.latency` p50/p95 under normal load, and under the known
  scraper incident if reproducible.
- `shadow_throttle` count/rate observed during the shadow window for
  normal traffic vs. the scraper pattern (this is what tunes the
  threshold).
- Typical `tracked_ips` for normal traffic.

**Shadow→enforce gate (numeric exit criterion):** flip to `enforce` only
once, over a representative shadow observation window, the
`shadow_throttle` rate on *normal* traffic is **< 0.1% of `allow`+
`shadow_throttle` requests** (i.e. fewer than 1 in 1000 legitimate
requests would have been blocked) **while** the known scraper pattern *is*
flagged `shadow_throttle`. If normal-traffic shadow_throttle exceeds that,
raise `SEARCH_RATELIMIT_RATE`/`BURST` and re-observe before enforcing.
:warning: **needs human input:** confirm 0.1% is an acceptable
false-positive ceiling for this endpoint, or set the agreed value.
