# RITA-1: test cases

BDD-style Given/When/Then, from the client's observable perspective.
Test paths are the *planned* locations (greenfield service); they are
written alongside the implementation in Phase 4.

---

**Given** `SEARCH_RATELIMIT_MODE=enforce` and a single client IP,
- **when** it sends requests *within* its rate/burst,
  **then** every response is `200` and unchanged from today.
- **when** it sends a burst that *empties* its bucket,
  **then** the over-limit requests get `429 Too Many Requests` with a
  `Retry-After` header, and a `decision=throttle` metric increments.
- **when** it then waits long enough for the bucket to refill,
  **then** subsequent requests get `200` again (recovery).

*Test:* `search-service/tests/test_ratelimit_enforce.py`

**Given** two distinct client IPs in `enforce` mode, one abusive and one
normal,
**when** the abusive IP is being throttled,
**then** the normal IP still receives `200` (per-IP isolation — abuse of
one client never affects another).

*Test:* `search-service/tests/test_ratelimit_enforce.py::test_ip_isolation`

**Given** `SEARCH_RATELIMIT_MODE=shadow`,
**when** a client exceeds its rate/burst,
**then** it still receives `200` (never blocked), but a
`decision=shadow_throttle` metric increments and a throttle log line is
emitted — so thresholds can be tuned against real traffic before
enforcing.

*Test:* `search-service/tests/test_ratelimit_shadow.py`

**Given** `SEARCH_RATELIMIT_MODE=off`,
**when** a client sends arbitrarily high volume,
**then** it is never throttled and no `decision` metric is emitted other
than (optionally) `allow` — the limiter is fully inert.

*Test:* `search-service/tests/test_ratelimit_off.py`

**Given** a running process in `shadow`/`off`,
**when** an operator changes the mode in the config source to `enforce`
(without a redeploy or restart),
**then** within the reload interval a new over-limit request gets `429`
— proving the no-redeploy kill switch works in both directions.

*Test:* `search-service/tests/test_ratelimit_reload.py`

**Given** a request whose forwarded-IP header is missing or unparseable
(error precondition),
**when** it reaches the limiter in `enforce` mode,
**then** the request is **allowed** (fail-open) and a
`errors,reason=no_client_ip` metric increments — a limiter that can't
identify the client must never block search.

*Test:* `search-service/tests/test_ratelimit_failopen.py`

**Given** a config source that is missing or malformed (error
precondition),
**when** the loader runs,
**then** the mode falls back to `shadow` (safe default: observe, never
block) and an `errors,reason=config_unreadable` metric increments.

*Test:* `search-service/tests/test_ratelimit_config.py`

**Given** more distinct client IPs arrive than
`SEARCH_RATELIMIT_MAX_TRACKED_IPS`,
**when** new IPs push the store past its cap,
**then** the least-recently-used buckets are evicted (memory stays
bounded) and an evicted IP that returns is treated as a fresh client.

*Test:* `search-service/tests/test_bucket_store.py::test_lru_eviction`

**Given** a spoofed client-supplied `X-Forwarded-For` (security
precondition),
**when** the gateway is configured to overwrite it with the real client
IP,
**then** the limiter keys on the gateway-set value, not the spoofed one.

*Test:* manual — verified against staging behind the real gateway once
feasibility flag #1 (header semantics) is confirmed; cannot be fully
proven in a unit test because it depends on gateway config, not our code.
