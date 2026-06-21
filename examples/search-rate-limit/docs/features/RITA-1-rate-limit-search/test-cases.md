# RITA-1: test cases

BDD-style Given/When/Then, observable behaviour from the client's and
operator's perspective. Test names are the planned implementation
targets (filled in / confirmed during implementation).

---

**Given** `SEARCH_RATELIMIT_MODE=enforce` and a client IP that has not
exceeded its rate,
- **when** the client sends `GET /search` within its allowance,
  **then** the response is the normal search result (not `429`);
- **when** the client exceeds its rate, **then** the response is
  `429 Too Many Requests` with a `Retry-After` header;
- **when** the client waits and tokens refill, **then** a subsequent
  request succeeds again.

*Test:* `test_ratelimit.py::test_enforce_allows_under_limit`,
`::test_enforce_throttles_over_limit`,
`::test_throttled_sets_retry_after`, `::test_refill_allows_again`

**Given** `SEARCH_RATELIMIT_MODE=shadow`,
- **when** a client exceeds its rate, **then** the request is still
  served normally (no `429`);
- **and** the would-throttle decision is recorded in
  `search.ratelimit.decision` (so a baseline can be measured without
  affecting users).

*Test:* `test_ratelimit.py::test_shadow_never_rejects`,
`::test_shadow_emits_would_throttle`

**Given** `SEARCH_RATELIMIT_MODE=off`,
**when** any volume of requests arrives,
**then** no request is throttled and the limiter does no per-IP
bookkeeping.

*Test:* `test_ratelimit.py::test_off_is_noop`

**Given** the limiter raises an internal exception while evaluating a
request (fault injected),
**when** `GET /search` is called in `enforce` mode,
**then** the request is served normally (fail open, no `500`) and
`search.ratelimit.errors` is incremented.

*Test:* `test_ratelimit.py::test_fails_open_on_error`

**Given** a flood of requests from many distinct IPs exceeding
`SEARCH_RATELIMIT_MAXSIZE`,
**when** they are processed,
**then** the tracked-IP map never exceeds `MAXSIZE` (idle entries are
evicted) and memory stays bounded.

*Test:* `test_ratelimit.py::test_map_bounded`

**Given** `enforce` mode is active and on-call flips
`SEARCH_RATELIMIT_MODE` to `off`,
**when** a previously-throttled client retries,
**then** it is served without `429` **without a process restart /
redeploy**.

*Test:* `test_ratelimit.py::test_mode_flip_takes_effect_live` (or
*manual* — verified by the runbook one-shot if live re-read is
config-managed rather than unit-testable)

**Given** a single *legitimate* high-volume source behind one shared
egress IP (an internal service or batch job calling `/search`),
**when** its aggregate rate exceeds the per-IP limit in `enforce`
mode,
**then** it must NOT be throttled as if it were one abusive client
(the "normal clients are never throttled" invariant). The intended
mechanism — an allowlist of trusted IPs, or a higher per-key limit
for them — is :warning: **needs human input** (depends on confirming
such callers exist; see README Impact). Until decided, this scenario
is the canary the shadow-mode baseline must surface.

*Test:* `test_ratelimit.py::test_allowlisted_ip_not_throttled`
(pending the allowlist decision; *manual* via shadow baseline review
until then)

**Given** two requests from the same client arriving concurrently on
different worker threads,
**when** both consume from the same bucket,
**then** token accounting stays consistent (no lost decrement / double
spend).

*Test:* `test_ratelimit.py::test_concurrent_same_key_consistent`
