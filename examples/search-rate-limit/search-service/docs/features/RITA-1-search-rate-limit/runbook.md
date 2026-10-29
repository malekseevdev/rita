# RITA-1: operational runbook

Mode file: `/etc/search-service/ratelimit-mode` (override with
`SEARCH_RATELIMIT_MODE_FILE`), contents `enforce` | `shadow` | `off`,
re-read every 5 s.  Metric names follow metrics.md in Prometheus form —
:warning: adjust once the metrics backend is confirmed (metrics.md).
Diagnose first; changing the mode in prod needs human approval.

## Symptom 1: real users report `429` from search

1.  How many clients are hit, fleet-wide:
    `query_loki_logs("count(sum by (key) (count_over_time({app=\"search-service\"} |= \"ratelimit throttled\" | logfmt [5m])))")`.
    Expected: a handful (the scrapers).  > 20 → limits too tight or a
    NAT range.  (A high throttled *share* of requests alone is normal
    during a scrape.)
2.  Which keys:
    `query_loki_logs("{app=\"search-service\"} |= \"ratelimit throttled\"")`
    — group by `key=`.  One key with many users behind it (corporate /
    mobile carrier range) → NAT.
3.  Mitigate (with approval): write `shadow` to the mode file on all
    hosts — throttling stops, observation continues.  Then raise
    `SEARCH_RATELIMIT_BURST`/`RATE` or add the allow-list follow-up.

## Symptom 2: scraper degrades search but nothing is throttled

1.  Mode on every process:
    `query_prometheus("sum by (instance, mode) (search_ratelimit_mode)")`.
    Expected: all `enforce`.  `off`/`shadow` → that's the cause.
2.  Key fallbacks:
    `query_prometheus("sum by (reason) (rate(search_ratelimit_key_fallback_total[5m]))")`.
    Expected: ~0.  Non-zero → the gateway stopped sending the client-IP
    header; requests pass unlimited (feasibility.md *Gateway header*).
3.  Scraper spreading over keys: `query_prometheus("max(search_ratelimit_tracked_keys)")`
    at `MAX_KEYS` and `query_prometheus("sum(rate(search_ratelimit_evictions_total[5m]))")`
    > 100/s → many IPs (botnet / rotating
    range); per-client limiting won't stop it — escalate (gateway-level
    blocking, README option B/E).
4.  Limit too loose: get the scraper key's per-process rate from
    `query_loki_logs("{app=\"search-service\"} |= \"ratelimit topkeys\"")`
    (requests per key per minute, per process) and compare with
    `RATE × 60`.  Above it on every process → bug; spread thin over more
    processes than planned → the fleet grew; re-tune (feasibility.md
    *Process topology*).

## Symptom 3: `search_ratelimit_errors_total` > 0

1.  `query_prometheus("sum by (kind) (rate(search_ratelimit_errors_total[5m]))")`.
2.  `kind="mode_file"`: on the host, `cat /etc/search-service/ratelimit-mode`
    — expected exactly one of the three words.  Otherwise the process is
    in `shadow` (safe); fix the file.
3.  `kind="internal"`: requests are failing open (C5) — search works but
    is unprotected.  `query_loki_logs("{app=\"search-service\"} |= \"ratelimit error\"")`
    for the traceback; file a bug.

## Symptom 4: hosts disagree on mode after a change

1.  `query_prometheus("sum by (instance, mode) (search_ratelimit_mode)")`
    — find the lagging instances.
2.  On a lagging host: `cat /etc/search-service/ratelimit-mode` and
    `stat -c %y /etc/search-service/ratelimit-mode`.  Old content → the
    push didn't reach it; write the file on that host directly (with
    approval).  New content but old gauge > 5 s later → bug; restart that
    process (with approval) — it reads the file at start, and the file
    beats the env var (ADR 0001).

## Rollout / rollback

-   To enable: write `enforce` to the mode file (plan.md steps 6–7).
-   To roll back: write `off` (or `shadow`) to the mode file — per host
    within 5 s; fleet-wide as fast as the push mechanism
    (feasibility.md *Mode-file propagation*).  Last resort: revert the
    deploy.
-   Verify: `query_prometheus("sum by (mode) (search_ratelimit_mode)")` —
    expected: every process reports the new mode.
