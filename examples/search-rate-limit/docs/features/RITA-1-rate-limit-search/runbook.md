# RITA-1: operational runbook

Agent-friendly diagnostic steps. Metric names per
[`metrics.md`](metrics.md); config keys per
[`README.md`](README.md) Configuration. PromQL/queries below are the
planned shape — confirm exact label names against the dashboard
during implementation.

> **Remediation note:** the *diagnostic* steps are agent-safe. The
> *mode flips* under "Rollout / rollback" change live behaviour and
> require human approval — diagnose and propose, then a human flips.

## Symptom: legitimate users report `429` on `/search` (misfire)

1. Confirm enforcement is on and what limit is set:
   `grep -E "SEARCH_RATELIMIT_(MODE|RATE|BURST)" <deployed config>`
   Expected: `MODE=enforce`. If `off`/`shadow`, the limiter isn't the
   cause — look elsewhere.

2. Check the throttle rate:
   `query_prometheus("sum(rate(search_ratelimit_decision{outcome='throttled'}[5m]))")`
   Expected: near the shadow-mode prediction. A spike well above it
   means the limit is too low for current traffic, or one shared
   egress IP (internal caller) is being throttled as a group.

3. **Mitigation (human-approved):** flip `SEARCH_RATELIMIT_MODE` to
   `shadow` (stops rejecting, keeps observing) or `off`. See Rollback.
   Then re-tune `RATE`/`BURST` from a fresh shadow baseline.

## Symptom: limiter never throttles a known abuser (bypass)

1. Check mode is `enforce` (step 1 above).

2. Check the IP key actually varies per client:
   `query_prometheus("search_ratelimit_tracked_ips")`
   Expected: roughly the count of distinct active clients. If it's
   ~1, every request is keying to the gateway/proxy IP → wrong
   `SEARCH_RATELIMIT_IP_HEADER`. If it's pinned at `MAXSIZE` and
   churning, suspect header-spoofing (many forged IPs) — confirm the
   gateway overwrites the client-supplied header.

3. Search logs for the extracted key on a sample request:
   `query_loki_logs("{app=\"search-service\"} |= \"ratelimit\" |= \"key=\"")`
   Expected: distinct client IPs, not a single proxy address.

## Symptom: `search.ratelimit.errors` is non-zero

1. `query_prometheus("sum by (stage) (rate(search_ratelimit_errors[5m]))")`
   Expected: empty/0. `stage=extract_ip` → IP key missing/malformed in
   the environ; `stage=evaluate` → bucket-logic bug. Requests are
   being served (fail-open) but the limiter is degraded.

2. `query_loki_logs("{app=\"search-service\"} |= \"ratelimit\" |= \"ERROR\"")`
   Expected: empty. Any traceback localises the failing stage.

## Rollout / rollback

- **To enable (rollout):** set `SEARCH_RATELIMIT_MODE=off → shadow`,
  observe baseline, set `RATE`/`BURST`, then `shadow → enforce`.
- **To roll back (misfire):** set `SEARCH_RATELIMIT_MODE=enforce →
  off` (or `shadow`). Takes effect in seconds with no redeploy *if* the
  stack reloads the mode live (unverified — see feasibility.md; otherwise
  it's redeploy-fast). No data to clean up — in-memory buckets reset.
- **Verify:**
  `query_prometheus("search_ratelimit_mode")` reflects the new mode,
  and `rate(search_ratelimit_decision{outcome='throttled'}[5m])` drops
  to 0 after a flip to `off`/`shadow`.
