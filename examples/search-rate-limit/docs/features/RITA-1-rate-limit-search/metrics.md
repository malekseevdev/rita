# RITA-1: metrics

See [`docs/how-to.md`](../../../docs/how-to.md#metric-definition-reference)
for the four axes (usage, errors, performance, business). Names are
the planned shape; reconcile with the service's existing metric
helper during implementation (don't invent parallel infra).

| Metric (with tags) | Axis | Meaning | Threshold to watch |
| --- | --- | --- | --- |
| `search.ratelimit.decision` (counter; `outcome=allowed\|throttled\|shadowed`) | usage / errors | One increment per `/search` request the limiter evaluated, by what it decided | `throttled` rate climbing toward legitimate traffic, or `>0` immediately after `enforce` when shadow predicted ~0 → limit too low |
| `search.ratelimit.tracked_ips` (gauge) | performance | Current number of IP buckets held in the per-process map | Sustained near `SEARCH_RATELIMIT_MAXSIZE` → distinct-IP flood / possible header-spoof bypass |
| `search.ratelimit.errors` (counter; `stage=extract_ip\|evaluate`) | errors | Limiter-internal exception caught → request was failed *open* | `>0` is a bug; request was served but the limiter is misbehaving |
| `search.ratelimit.mode` (gauge; `mode=off\|shadow\|enforce`) | usage | Current enforcement mode (so a dashboard shows what's live) | Unexpected value vs. intended rollout stage |
| `search.request.latency_p95` (timing; existing endpoint metric) | performance | `/search` p95 latency — the SLO the feature must not regress for under-limit traffic | p95 delta after enabling `shadow`/`enforce` vs. baseline |

**Business axis** — off the request path, so measured by comparison,
not a counter. Incident class to count: **`/search` p95-latency SLO
breaches attributed to single-client query volume**. Compare the
**30-day count before `enforce`** against the **30-day count after**
(re-checked at the T+30 and T+90 reviews). Success = that count
trends to ~0 with no offsetting rise in legitimate-client `429`s
(`search.ratelimit.decision{outcome=throttled}` against a known-good
client list). Frozen values live in the ticket.

## Dashboards

_(Link Grafana panels here once created: decision-rate-by-outcome,
tracked_ips gauge, errors, p95 latency overlaid with mode.)_

## Baseline

_(Record before enforcing — this is the load-bearing step that sets
the limit:_

- `/search` p95 latency, current (pre-feature).
- From **shadow mode**: the `throttled`-if-enforced rate per IP and
  the count of distinct legitimate IPs that would have been rejected
  at candidate `RATE`/`BURST` values. Choose values where that count
  is **0**.
- Peak `tracked_ips` under normal traffic, to size `MAXSIZE`.

_Values live in the ticket, frozen-in-time.)_
