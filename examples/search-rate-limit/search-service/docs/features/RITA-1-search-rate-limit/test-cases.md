# RITA-1: test cases

<!-- rita-budget: 110 — one scenario group per constraint C1–C7, plus concurrency and start-up checks -->

All automated tests live in `search-service/tests/test_ratelimit.py`
(planned; drives the middleware with a fake WSGI app, a fake monotonic
clock and a temp mode file).  Unless a case says otherwise, mode is
`enforce`, `BURST` = 3, `RATE` = 1/s, `TRUSTED_HOPS` = 1.

### Scope (C2)

**Given** a client whose bucket is empty,
- **when** it sends `HEAD /search?q=x`, **then** it gets `429` (same
  scope as GET);
- **when** it requests `GET /search/` (trailing slash), **then** it is
  passed through unlimited;
- **when** it requests `GET /health` (or any route other than `/search`),
  **then** the response is the app's, unchanged;
- **when** it sends `POST /search`, **then** the request is not counted
  or limited (only `GET`/`HEAD /search` is in scope);
- **when** it requests `GET /search?q=x`, **then** it gets `429`.

*Test:* `test_ratelimit.py::test_only_get_head_search_is_limited`

### Throttling

**Given** a fresh client key,
- **when** it sends `BURST` requests at once, **then** all get the app's
  response;
- **when** it sends one more immediately, **then** it gets `429` with
  `Retry-After: 1` and the service's error body;
- **when** it waits `1/RATE` seconds and retries, **then** it succeeds;
- **when** a *different* client key sends a request meanwhile, **then**
  it succeeds (buckets are independent).

*Test:* `test_ratelimit.py::test_bucket_burst_refill_and_isolation`

### Client key (C7)

**Given** a request through the gateway,
- **when** `X-Forwarded-For` is `"6.6.6.6, 203.0.113.7"` (client-forged
  first entry, gateway-appended last), **then** the key is
  `203.0.113.7`;
- **when** the client IP is IPv6 `2001:db8:1:2::a` and later
  `2001:db8:1:2::b`, **then** both share key `2001:db8:1:2::/64`;
- **when** `TRUSTED_HOPS` = 2 and the header has one entry, **then** the
  request passes unlimited with `reason=unparsable` (never falls back to
  the client-controlled entry);
- **when** the header is missing or unparsable (`"garbage"`), **then**
  the request passes unlimited and `key_fallback` is counted with
  `reason=missing` / `reason=unparsable`.

*Test:* `test_ratelimit.py::test_client_key_derivation`
(the real gateway's behaviour: manual — feasibility.md *Gateway header*
curl check in staging, plan.md step 4)

### Modes and kill switch (C3, C4)

**Given** a client whose bucket is empty,
- **when** the mode file says `shadow`, **then** the request succeeds and
  `would_throttle` is counted;
- **when** it says `off`, **then** the request succeeds and no bucket is
  touched;
- **when** the file is changed from `enforce` to `off`, **then** requests
  succeed once `MODE_TTL` has elapsed, with no restart;
- **when** the file is missing, **then** the `SEARCH_RATELIMIT_MODE` env
  default applies; when the file says `off` and the env says `enforce`,
  **then** mode is `off` (file wins — ADR 0001);
- **when** the file contains `enforec` or is unreadable, **then** mode is
  `shadow` and `errors{kind=mode_file}` is counted.

*Test:* `test_ratelimit.py::test_mode_file_states`
(fleet-wide propagation: manual — kill-switch drill, plan.md step 4)

### Failure (C5)

**Given** the bucket store raises an unexpected exception, **when** a
client requests `GET /search`, **then** the app's response is returned
and `errors{kind=internal}` is counted.

*Test:* `test_ratelimit.py::test_fails_open_on_internal_error`

### Key flood (C6)

**Given** `MAX_KEYS` = 1000,
**when** 10 000 distinct client keys each send a request,
**then** at most 1000 keys are tracked, `evictions` is 9000, and an
evicted key's next request is allowed (it restarts with a full bucket).

*Test:* `test_ratelimit.py::test_lru_bound_and_eviction`

### Concurrency

**Given** one key with `BURST` = 100 and `RATE` = 0.001/s, **when** 16
threads send 50 requests each concurrently, **then** exactly 100 are
allowed (no lost updates).

*Test:* `test_ratelimit.py::test_thread_safety`

### Start-up checks

**Given** the service is starting,
- **when** `SEARCH_RATELIMIT_RATE=0` or `BURST=abc`, **then** it exits
  with an error naming the variable
  (`test_ratelimit.py::test_invalid_config_refuses_start`);
- **when** the `ratelimit` module's imports are inspected, **then** each
  is in `sys.stdlib_module_names` — C1; needs Python ≥ 3.10 in CI,
  README open question 10
  (`test_ratelimit.py::test_imports_are_stdlib_only`).
