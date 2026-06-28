# RITA-1: feasibility

Record every load-bearing assumption of the preferred solution and
verify each with the smallest possible test. An assumption is
load-bearing if the plan dies when it fails.

This file stays in the folder after shipping — it's the record of
what was true at planning time.

See [`docs/how-to.md`](../../../docs/how-to.md#2-feasibility-check)
for the reasoning.

## Verified blocks

**None.** The preferred approach (A) is an in-process token bucket
built on stdlib primitives (`threading.Lock`, `time.monotonic`, a
plain dict). Whether those primitives exist and behave as documented
is self-evident for a competent engineer — verifying them would be
noise, not signal — and that a token bucket enforces its own limit is
*test-cases.md* territory, written with the implementation, not a
feasibility check.

The assumptions that *are* genuinely uncertain here all depend on the
production/gateway environment, which cannot be checked meaningfully
from the planning box (and there is no service code in this repo
yet). They are flagged below rather than faked as verified blocks.

## Unverified external unknowns (need human input)

#### Client IP source in the WSGI environ

- **Assumption:** The gateway forwards the real client IP to the
  search app, and it arrives in a known WSGI environ key
  (`REMOTE_ADDR`, or a forwarded header such as
  `HTTP_X_FORWARDED_FOR` / `HTTP_X_REAL_IP`) that the middleware can
  read to key buckets per client.
- **Failure-mode:** If we key on the wrong field, every request keys
  to the *gateway's* IP (or a proxy hop), so all clients share one
  bucket — the limiter would throttle the entire user base as a
  single "client", or never trigger at all. This directly breaks the
  "normal clients are never throttled" invariant.
- **Why unverified:** Depends on gateway configuration and the
  deployed WSGI stack, neither of which is in this repo or runnable
  from the planning environment. The ticket states "clients are keyed
  by IP (the gateway forwards it)" but does not name the header.
- :warning: **needs human input:** Which environ key carries the
  client IP in production, and is it trustworthy (set by *our*
  gateway, not spoofable by the client)? If it's a forwarded header,
  confirm the gateway strips/overwrites any client-supplied value —
  otherwise an attacker rotates the header to dodge the limit.

#### Worker / process count per host

- **Assumption:** The deployed worker count *N* per host is small and
  stable (ticket: "the fleet is small and stable today"), so
  per-process buckets give a predictable effective limit of roughly
  *N* × the per-process rate.
- **Failure-mode:** If *N* is large or autoscaling, the effective
  per-client ceiling is much higher than configured (under-throttle),
  or unpredictable — the configured limit can't be reasoned about.
- **Why unverified:** This is a deployment topology fact (WSGI server
  config / process manager), not something the planning box can
  observe.
- :warning: **needs human input:** What is the worker/process count
  per host, and is it fixed or autoscaled? This sets the multiplier
  used to derive the configured limit and the `metrics.md`
  thresholds.

#### Live mode flip without a restart

- **Assumption:** Changing `SEARCH_RATELIMIT_MODE` takes effect on the
  running process *without* a redeploy/restart — i.e. the deployed
  stack has a mechanism (env re-read on a signal, a watched
  config file/value, or a control endpoint) the mode can be re-read
  through at request time.
- **Failure-mode:** If the setting is only read once at startup, the
  "disable in seconds" / kill-switch invariant is false — disabling a
  misfire would require a redeploy, which is exactly the slow path the
  ticket wants to avoid.
- **Why unverified:** Depends on how the deployed WSGI stack manages
  config (process manager, env, config service) — none of which is in
  this repo. The ticket asks for a fast off-switch but doesn't specify
  the config mechanism.
- :warning: **needs human input:** How does the deployed stack reload
  a setting live? If there is none, either add one (a watched value /
  control endpoint) or downgrade the kill-switch claim to
  "redeploy-fast" — this changes README's "in seconds" wording and the
  `test_mode_flip_takes_effect_live` test.

#### `/search` is a wrappable plain WSGI app

- **Assumption:** `GET /search` is served by a plain WSGI callable the
  limiter can wrap as outer middleware (per ticket: "a plain WSGI app,
  not a framework").
- **Failure-mode:** If the entry point is not a standard WSGI
  callable, the middleware-wrapping integration point in the plan
  doesn't exist and the implementation step changes.
- **Why unverified:** No service code is present in this repo yet to
  inspect; relying on the ticket's statement.
- :warning: **needs human input:** Confirm the WSGI entry point /
  module to wrap (so implementation step 4 can name the file).
