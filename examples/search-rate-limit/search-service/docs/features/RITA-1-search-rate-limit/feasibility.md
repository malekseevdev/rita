# RITA-1: feasibility

Record of what was true (or unknown) at planning time.  If you modify the
feature later, re-check the relevant entries.

## Verified blocks

**None — deliberately.**  The limiter itself is self-contained stdlib code
(`threading`, `time.monotonic`, `collections.OrderedDict`, `ipaddress`,
`os.stat`, all present since Python 3.3); whether a token bucket enforces
its limit, or the mode file is re-read, is our own code and is covered in
[test-cases.md](test-cases.md), not here.  Every genuinely uncertain
load-bearing assumption is about the *production environment*, which
can't be checked from the planning box (the search service's source and
deployment aren't in this repository) — so they're flagged below rather
than proxied locally.

## Unverified external unknowns (need human input)

#### Gateway header

- **Assumption:** The gateway puts the real client IP into a known header
  on every request it forwards, and either *overwrites* any
  client-supplied value or *appends* to `X-Forwarded-For` so that the
  last entry is the one it wrote.  The search service is reachable only
  through the gateway.
- **Failure-mode:** If the gateway passes a client-supplied header
  through unchanged, a scraper picks any key it likes and evades the
  limit (breaks C7).  If the header is absent, every request takes the
  `key_fallback` path and nothing is limited.  If the service is reachable
  directly, those requests bypass keying.
- **Why unverified:** gateway configuration and network topology aren't
  in this repo, and a local test of `X-Forwarded-For` parsing would only
  test our own parser.
- :warning: **needs human input:** which header (`X-Forwarded-For`,
  `X-Real-IP`, `Forwarded`, custom?), does the gateway overwrite or
  append, how many trusted proxy hops sit between gateway and app, and
  is the app port firewalled to the gateway only?  The plan's default is
  "rightmost `X-Forwarded-For` entry" with the trusted-hop count as
  config (`SEARCH_RATELIMIT_TRUSTED_HOPS`, default 1).  Cheap check once
  answered: `curl -H 'X-Forwarded-For: 1.2.3.4' https://<public-host>/search?q=x`
  against staging with request logging on, and confirm the logged key is
  the curl host's IP, not `1.2.3.4`.

#### Process topology (how far one client's traffic is spread)

- **Assumption:** The number of processes serving `/search` is small,
  fixed, and known (ticket: "small and stable"), and the WSGI server's
  concurrency model is threads and/or pre-forked processes (gunicorn /
  uWSGI style), where a per-process dict + `threading.Lock` is correct.
- **Failure-mode:** Effective per-client limit = per-process limit × the
  number of processes a client's requests land on.  Wrong count → limit
  is N× too loose (scraper still degrades search) or too tight (normal
  users throttled).  Autoscaling silently changes N.
- **Why unverified:** deployment config (hosts × workers, server type,
  load-balancing policy, keep-alive pinning) isn't in this repo; running
  a server locally says nothing about production.
- :warning: **needs human input:** hosts × worker processes per host, the
  WSGI server and worker class, and whether the fleet ever autoscales.
  The shadow stage (plan.md) measures the *actual* per-process rates and
  is the empirical backstop for this number.

#### Mode-file propagation

- **Assumption:** Ops can write a file on every search host within about
  a minute without a deploy (config-management push, ssh loop, or a
  mounted config volume).
- **Failure-mode:** If the only way to change a file on the hosts is a
  deploy, the kill switch (C4) is no faster than today's remedy — C4
  holds per host, but the ticket's "quickly" does not hold fleet-wide.
- **Why unverified:** ops tooling isn't in this repo.
- :warning: **needs human input:** what mechanism changes a runtime file
  on all search hosts, and how long does it take?  If there is none, the
  fallback is a per-host `ssh` write, or at worst a config deploy that
  writes the file (the file beats the env var — ADR 0001), and the plan
  must then stop claiming "seconds".
