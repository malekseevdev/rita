# RITA-1: metrics

:warning: **needs human input:** how the search service exports metrics
today.  Names below are backend-neutral; the runbook writes them in
Prometheus form (`search_ratelimit_decisions_total{outcome=…}`).  If
there is no metrics client, the stdlib-only fallback (C1) is a
plain-UDP StatsD emitter (`socket`) or structured `logging` lines
scraped by the log pipeline — pick whichever the service already
feeds.

All counters count `GET`/`HEAD /search` requests only, per process;
aggregate with `sum` across processes.

| Metric (with tags) | Type | Axis | Meaning | Threshold to watch |
| --- | --- | --- | --- | --- |
| `search.ratelimit.decisions,outcome=allowed\|throttled\|would_throttle` | counter | usage | Limiter verdict per request (`would_throttle` only in shadow) | Informational: a high `throttled` share is *expected* while a scraper is active; alert on throttled keys instead |
| Distinct throttled keys, fleet-wide, last 5 min (log-derived: distinct `key=` in `ratelimit throttled` lines) | log query | usage | How many *clients* are being limited — the real-user-harm signal | > 20 → limits too tight or NAT range (runbook 1); expected: a handful |
| Top keys per process (`ratelimit topkeys` log line, every 60 s) | log | usage | Per-key request rate; source for sizing `RATE`/`BURST` (plan.md step 5) | n/a — diagnostic |
| `search.ratelimit.mode,mode=off\|shadow\|enforce` | gauge (1 = current) | usage | Mode each process is actually in | processes disagree for > 1 min after a change → propagation problem (runbook 4) |
| `search.ratelimit.key_fallback,reason=missing\|unparsable` | counter | errors | Requests passed unlimited because no client key could be derived | > 0.1% of `/search` → gateway header problem (runbook 2) |
| `search.ratelimit.errors,kind=internal\|mode_file` | counter | errors | Limiter failed open / mode file unreadable or invalid | any > 0 → look (runbook 3) |
| `search.ratelimit.evictions` | counter | errors | LRU evicted a tracked key | sustained > 100/s → key flood (runbook 2) |
| `search.ratelimit.tracked_keys` | gauge | performance | Keys in memory per process | at `MAX_KEYS` for > 10 min → key flood |
| `search.ratelimit.check_seconds` | timing | performance | Time spent in the limiter per request | p99 > 1 ms → look |
| search p95 latency (existing service metric — :warning: name unknown) | timing | business | The thing the ticket protects: latency for everyone | p95 stays within +10% of the pre-ship baseline while a key is being throttled |
| Incidents needing a deploy to stop a scraper | ticket count | business | The ticket's original pain | target 0 per quarter after ship |

## Dashboards

_(One RITA-1 dashboard: decisions by outcome, throttled keys, mode by
host, fallbacks, errors, check latency, search p95.  Link here once
created.)_

## Baseline

_(Record in the ticket before step 6: `/search` req/s per process, per-key
p99.9 rates from shadow, search p95 latency.)_
