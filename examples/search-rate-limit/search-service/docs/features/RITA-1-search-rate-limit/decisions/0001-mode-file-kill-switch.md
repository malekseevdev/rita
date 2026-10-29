# ADR 0001: a mode file is the rate limiter's kill switch

- **Status:** Proposed (until the RITA-1 plan is approved)
- **Feature:** RITA-1, per-client rate limiting of `GET /search` in
  `search-service`

## Context

The search service's new per-client rate limiter can misfire: limits set
too tight, or many users behind one NAT IP, mean real users get `429`.
The ticket asks for a way to turn enforcement off *quickly*.  Today the
only lever is a deploy.  The limiter must stay standard-library only,
with no new infrastructure on the request path, so a remote flag service
or shared store is out.  The service runs as several WSGI processes on a
small, fixed set of hosts; processes share no memory.

## Decision

-   Each process reads a small text file (default
    `/etc/search-service/ratelimit-mode`, path overridable with
    `SEARCH_RATELIMIT_MODE_FILE`) containing one word: `enforce`,
    `shadow` (count what would be throttled, block nothing) or `off`.
-   The file is re-checked at most every `SEARCH_RATELIMIT_MODE_TTL`
    seconds (default 5) via `os.stat` mtime, and read again when it
    changes, so every process on a host follows a write within 5 s, with
    no restart.
-   **Precedence:** file > env.  `SEARCH_RATELIMIT_MODE` is used only when
    the file is absent (e.g. a freshly built host).  So the env default
    can be `enforce` after launch without ever overriding an operator's
    `off`.
-   Unreadable or unrecognised contents → `shadow`, plus a
    `search.ratelimit.errors{kind=mode_file}` count.  A typo neither
    blocks users nor turns observation off.
-   Three states rather than a boolean, because `shadow` is both the
    rollout stage and the safe place to re-tune limits.  Hence the name
    `SEARCH_RATELIMIT_MODE*` rather than the `KILL_…` prefix.  It is
    still the kill switch.

## Alternatives considered

-   **Env var only, read at start-up:** simple, but turning it off needs
    a restart of every process.  That's minutes, and on some setups it
    is a deploy.  Rejected as the primary path.
-   **Admin HTTP endpoint that flips an in-memory flag:** reaches only
    the one process that served the call, and adds an unauthenticated
    control surface to a public service.  Rejected.
-   **Env overrides file:** with `SEARCH_RATELIMIT_MODE=enforce`
    deployed, an operator's `off` would be ignored.  Rejected.

## Consequences

-   Per host, a mode change takes effect within 5 s.  Fleet-wide, it is
    only as fast as ops can write a file on every host.  That mechanism
    is **unconfirmed** (:warning: needs human input, RITA-1
    feasibility.md *Mode-file propagation*).  With no push tooling, the
    honest fallback is a per-host `ssh` write, or at worst a config
    deploy, and the plan must then not claim "seconds".
-   A host whose write didn't land stays in its old mode.  The fix is
    to write that host's file again; a process whose file is correct but
    whose `search.ratelimit.mode` gauge is stale gets restarted (it reads
    the file at start).
-   One `stat` per process every 5 s; negligible.
