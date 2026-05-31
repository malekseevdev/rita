# RITA-1: operational runbook

Agent-friendly diagnostic steps for the search rate limiter. Each step
uses a concrete command with expected output. **Diagnostic steps are safe
to run anytime; the remediation (toggle flip) requires human approval** —
flipping `SEARCH_RATELIMIT_MODE` is a runtime change to client-facing
behavior. Diagnose, propose, wait.

PromQL/metric names are from [metrics.md](metrics.md). The mode-change
command shape depends on the config-push mechanism (feasibility flag #3);
the placeholder below assumes a config file the app re-reads.

## Symptom: legitimate users report being throttled (unexpected 429s)

1.  Confirm enforcement is on and check the throttle spread:
    `query_prometheus("sum by (decision) (rate(search_ratelimit_decision[5m]))")`
    Expected normally: `throttle` small and concentrated. **Many distinct
    IPs hitting `throttle`** suggests the threshold is too low or the
    IP key is wrong (everyone sharing one bucket).

2.  Check whether all traffic shares one key (the gateway-header failure
    mode):
    `query_prometheus("search_ratelimit_tracked_ips")`
    Expected: roughly the count of active client IPs. **A value near 1**
    means IP extraction is collapsing everyone to one IP (e.g. reading
    `REMOTE_ADDR` = the gateway) → see feasibility flag #1. This is a
    real-incident trigger to flip to `shadow`.

3.  Search the logs for the throttle decisions to see which IPs:
    `query_loki_logs("{app=\"search\"} |= \"ratelimit\" |= \"throttle\"")`
    Expected: a small set of IPs. A broad spread of normal-looking IPs
    confirms over-throttling.

4.  **Remediation (needs human approval):** flip to `shadow` to stop
    blocking while keeping data, then re-tune. See "Rollout / rollback".

## Symptom: a known abuser is NOT being throttled

1.  Confirm the mode is `enforce`, not `shadow`/`off`:
    `cat <config-path>/search_ratelimit.conf` (or the configured source) —
    expected `mode=enforce`. If `shadow`/`off`, that's the cause.

2.  Check for fail-open events (limiter silently allowing):
    `query_prometheus("sum by (reason) (rate(search_ratelimit_errors[5m]))")`
    Expected: ~0. `reason=no_client_ip` means the forwarded header is
    missing/unparseable → the abuser is being allowed via fail-open.
    `reason=config_unreadable` means the limiter can't load its settings.

3.  Consider the per-worker limitation: if the abuser is spread across N
    workers, its effective allowance is N× the per-worker rate. Check the
    worker count against the configured `SEARCH_RATELIMIT_RATE` (feasibility
    flag #2). The fix is lowering the per-worker rate, not a bug.

4.  Check IP rotation:
    `query_prometheus("rate(search_ratelimit_tracked_ips[5m])")` rising
    fast + `tracked_ips` near the cap = the abuser is rotating IPs, which
    per-IP limiting cannot fully stop (known limitation — escalate toward
    option C / gateway limiting).

## Symptom: limiter adds latency

1.  `query_prometheus("histogram_quantile(0.95, sum by (le) (rate(search_ratelimit_check_latency_bucket[5m])))")`
    Expected: sub-millisecond. If p95 is multiple ms, suspect lock
    contention (see plan.md Concerns → shard the store).

## Rollout / rollback

-   **To enable enforcement:** set `SEARCH_RATELIMIT_MODE=enforce` in the
    config source; the app picks it up without a redeploy (mtime reload).
    Verify:
    `query_prometheus("sum(rate(search_ratelimit_decision{decision=\"throttle\"}[5m]))")`
    — expected: > 0 only if a client is actually over the limit.
-   **To roll back (kill switch):** set `SEARCH_RATELIMIT_MODE=shadow` (keep
    observing) or `off` (full stop). Seconds, no redeploy. **Human approval
    required.** If the deployment turned out to support only an
    env-var-at-start (feasibility flag #3 resolved that way), the
    guaranteed fallback is a **rolling restart with
    `SEARCH_RATELIMIT_MODE=off`** in the environment — still no code
    deploy. Use SIGHUP reload instead if implemented.
    Verify the flip took effect:
    `query_prometheus("sum(rate(search_ratelimit_decision{decision=\"throttle\"}[2m]))")`
    — expected: drops to 0 shortly after the flip.
-   **Confirm no data risk:** state is in-memory only; nothing to clean up
    after a rollback.
