# <Ticket-ID>: operational runbook

Agent-friendly diagnostic steps.  Each step should use concrete
commands with expected output so an agent with an observability
MCP (Grafana, Datadog, Honeycomb, etc.) can execute them directly.
See [`docs/rationale.md`](../docs/rationale.md#writing-agent-friendly-runbooks)
for guidelines.

## Symptom: <describe what's wrong>

1.  Check <setting/config>:
    `<concrete command>`
    Expected: <what success looks like>.  If <other>, this is the
    problem.

2.  Query metrics:
    `query_prometheus("<promql query>")`
    Expected: <threshold>.

3.  Search logs:
    `query_loki_logs("{app=\"<app>\"} |= \"<pattern>\"")`
    Expected: empty / <what results mean>.

## Rollout / rollback

-   To enable: <what to change and where>.
-   To roll back: <what to change>.
-   Verify: `query_prometheus("<query>")` — expected: <value>.
