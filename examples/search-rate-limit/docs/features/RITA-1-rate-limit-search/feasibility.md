# RITA-1: feasibility

Record every load-bearing assumption of the preferred solution and verify
each with the smallest possible test. An assumption is load-bearing if the
plan dies when it fails.

This file stays in the folder after shipping — it's the record of what was
true at planning time.

## Verified blocks

**None.** This is the honest result for this feature, not a gap.

Every assumption the preferred design (in-process stdlib token bucket)
depends on falls into one of two buckets, and neither is a feasibility
check:

- **It's our own code.** "A token bucket caps sustained rate while
  allowing bursts," "the WSGI middleware can read the forwarded header
  from `environ` and return a `429`," "an `OrderedDict` LRU bounds memory,"
  "a config file re-read on mtime change flips the mode without a
  restart." A competent engineer is not *uncertain* about these — they are
  the thing we are building. They are verified by the tests in
  [test-cases.md](test-cases.md), written with the implementation, not by
  prototyping the design now.
- **It's the production environment, which can't be checked from here.**
  The forwarded-IP header contract, the worker/host count, and the
  config-push mechanism are properties of infra this planning box does not
  run. A command run locally would prove nothing about production — that
  is local-proxying a production fact. These are flagged below, not faked
  as verified blocks.

The stdlib primitives the design uses (`time.monotonic`,
`threading.Lock`, `collections.OrderedDict`, the WSGI `environ`/
`start_response` contract) are present in every supported Python 3 and are
self-evident; verifying them would be noise. Planning box is Python 3.12.3
for reference.

## Unverified external unknowns (need human input)

These are load-bearing: each can break correct behavior, and none can be
honestly checked from the planning environment. They do **not** block
writing the plan, but they must be answered before tuning the threshold
and before flipping to `enforce`.

#### Gateway forwarded-IP header (most important)

- **Assumption:** The gateway forwards the real client IP in a specific,
  trustworthy header (the design assumes a gateway-set `X-Forwarded-For`,
  reading the correct entry), and the search WSGI app can read it from the
  WSGI `environ` (e.g. `HTTP_X_FORWARDED_FOR`).
- **Failure-mode:** If the app reads `REMOTE_ADDR` instead, every client
  collapses to the *gateway's* IP → one shared bucket → either everyone is
  throttled together or no one is (limiter useless or catastrophic). If
  the gateway passes through a *client-supplied* `X-Forwarded-For` without
  overwriting it, a scraper can spoof the header to evade its own limit or
  to frame another IP.
- **Why unverified:** The header name and the gateway's trust behavior
  (does it strip/overwrite client-sent `X-Forwarded-For`, or append?) are
  properties of the gateway config, which this planning box does not run
  and cannot inspect.
- :warning: **needs human input:** (1) Exactly which header carries the
  client IP, and what is its WSGI `environ` key? (2) Does the gateway
  guarantee that value is gateway-set and not client-spoofable (e.g. does
  it overwrite any inbound `X-Forwarded-For`)? If it appends, which entry
  is the trustworthy client IP — left-most untrusted, or right-most?

#### Worker / host count (sets the effective limit)

- **Assumption:** We know how many WSGI worker processes run per host and
  how many hosts serve `GET /search`, so the per-worker token-bucket rate
  can be set to produce the intended *fleet-wide* per-IP limit.
- **Failure-mode:** Buckets are per-process (no shared store — that's the
  stdlib-only constraint). If a client's requests are load-balanced across
  N workers, its effective allowance is up to N× the per-worker rate. Set
  the per-worker rate without knowing N and the real limit is N× too high
  (abuse still degrades latency) or, if N is misjudged downward, too low
  (legit users throttled).
- **Why unverified:** Worker/host topology is a deployment property
  (process manager config, autoscaling) not visible from the repo.
- :warning: **needs human input:** How many worker processes per host, how
  many hosts, and does the gateway pin a client IP to one worker (sticky)
  or spray across all? If sprayed, the per-worker rate = target ÷
  (workers × hosts).

#### Config-push path for the kill switch (no-redeploy requirement)

- **Assumption:** Operators can change `SEARCH_RATELIMIT_MODE` and have
  running processes pick it up **without a redeploy** — the design reads
  the mode from a config file/source the app re-reads on a short interval
  or mtime change. This requires that such a file exists on the hosts and
  is writable/pushable by ops out-of-band of a code deploy.
- **Failure-mode:** If the mode can only be set via an environment
  variable read at process start, then "turn enforcement off quickly"
  still requires a restart/redeploy — defeating the ticket's core ask
  (today's only mitigation is a deploy).
- **Why unverified:** Whether the prod filesystem is writable by ops and
  how config is pushed (config-management tool, mounted secret, etc.) is
  infra this planning box does not run.
- :warning: **needs human input:** What is the supported mechanism to
  change a runtime setting on the search hosts without a code deploy
  (writable config file + reload? a config service? SIGHUP)? The
  implementation's reload strategy depends on the answer.
