# RITA-1: plan

<!-- This file is ephemeral — delete it after shipping. -->

Options and *The model* live in [`README.md`](README.md); open
assumptions in [`feasibility.md`](feasibility.md).  None of the flagged
unknowns blocks writing this plan; steps that depend on one say so.
Paths assume the search app lives under `search-service/search/` —
:warning: needs human input: the real package layout (the source isn't
in this repo).

## Implementation steps

1.  **Limiter core** — `search-service/search/ratelimit.py`: client-key
    derivation, token-bucket store (LRU-bounded), mode reader, all
    pure/stdlib (C1).  Config, all optional env vars:
    `SEARCH_RATELIMIT_MODE` (default `off` until step 7),
    `SEARCH_RATELIMIT_MODE_FILE` (default
    `/etc/search-service/ratelimit-mode`), `SEARCH_RATELIMIT_MODE_TTL`
    (5 s), `SEARCH_RATELIMIT_RATE` / `SEARCH_RATELIMIT_BURST` (per
    process; placeholders 2 req/s and 40 until step 5 measures real
    traffic), `SEARCH_RATELIMIT_MAX_KEYS` (50 000),
    `SEARCH_RATELIMIT_TRUSTED_HOPS` (1).  Invalid numeric config refuses
    start-up.  Unit tests from [test-cases.md](test-cases.md).  No
    behaviour change.
2.  **Wire the middleware** around the WSGI app in its entry point, mode
    `off` by default.  Ship to prod: a no-op that proves the wrapper is
    harmless (C2, C3).  Signal: search error rate and p95 unchanged (the
    limiter's own metrics arrive in step 3).
3.  **Observability** — emit the [metrics.md](metrics.md) catalog and a
    sampled throttle log line (first throttle per key per minute, so a
    scraper can't flood logs), and a once-a-minute `ratelimit topkeys`
    log line per process with the 10 busiest keys and their request
    counts (the per-key rate source for step 5 and the runbook); build
    the dashboard.
4.  **Staging** — set the mode file to `shadow`; run the
    feasibility.md *Gateway header* curl check; drill the kill switch
    (`enforce` → `off`, observe the mode gauge flip within 5 s).
5.  **Prod shadow, ≥ 7 days** <!-- partial value milestone: we now see
    who is scraping, without blocking anyone -->.  Size limits from the
    data: `BURST` ≥ 3× the p99.9 per-key 10-second request count,
    `RATE` ≥ 3× the p99.9 per-key sustained rate, both per process.
    :warning: needs human input: approve the chosen numbers.
6.  **Canary enforce** — mode file `enforce` on one host for 24 h.
7.  **Fleet enforce** — mode file `enforce` everywhere; then a follow-up
    deploy sets `SEARCH_RATELIMIT_MODE=enforce` so a host whose mode
    file is lost on rebuild doesn't silently fall back to `off`.
    <!-- partial value milestone: the ticket's ask is met -->

## Concerns

- **Performance** — per `/search` request: one header parse, one dict
  lookup + move-to-end, a few float ops under a lock held for
  microseconds, and an `os.stat` of the mode file at most every 5 s per
  process.  Expected well under 0.1 ms (measured as
  `search.ratelimit.check_seconds`).  Memory ≈ 200–300 B per tracked key
  (estimate — measure with `tracemalloc` in step 1), so ≤ ~15 MB per
  process at `MAX_KEYS` = 50 000.
- **Security** — the client key is security-relevant: trusting a
  spoofable header defeats the feature (C7, feasibility.md *Gateway
  header*).  IPv6 is keyed per /64 to stop trivial address rotation.  A
  botnet with many IPs is out of scope — per-client limiting can't stop
  it; option E (load shedding) would.  Throttle logs contain client IPs
  — :warning: needs human input: is logging IPs allowed under our data
  retention policy, or should we log a keyed hash?
- **Data migration** — N/A: no persisted state; buckets live in memory
  and reset on restart (a restart briefly forgives everyone — acceptable).
- **Thread safety** — the bucket store is shared by all threads of a
  process; one `threading.Lock` guards read-modify-write of a bucket and
  LRU eviction.  Processes share nothing (by design — README Options A).
  The mode cache is a single reference swap, safe without the lock.
- **Scalability** — CPU cost is flat per request.  What breaks first at
  10× is *correctness of the limit*, not speed: more processes means a
  looser effective per-client limit (feasibility.md *Process topology*)
  — re-tune `RATE`/`BURST`, and at autoscaling scale move to the gateway
  (README option B).  Key floods are bounded by `MAX_KEYS` (C6).
- **Observability** — decisions by outcome, mode per process, errors,
  key fallbacks, check latency, tracked keys — see metrics.md.
- **Failure modes** — (a) limits too tight / NAT users share a bucket →
  real users get `429` (loud: throttled-rate and throttled-keys
  metrics; runbook symptom 1); (b) gateway header missing → nothing is
  limited (silent to users, loud on `key_fallback`; runbook symptom 2);
  (c) limiter bug → fails open, counted (C5; runbook symptom 3); (d) key
  flood → LRU eviction resets buckets, scraper partially escapes
  (`evictions` metric); (e) mode file not propagated → hosts disagree
  (`mode` gauge; runbook symptom 4).
- **Operability** — new runbook ([runbook.md](runbook.md)), one
  dashboard, and on-call needs to know the mode file path and the three
  values (ADR 0001).

## Dependencies

| Dependency | Type | Status |
| ---------- | ---- | ------ |
| Gateway owners: answer feasibility.md *Gateway header* | blocks step 4 (correct keying) | :warning: not started |
| Ops: mechanism to write the mode file on all hosts (feasibility.md *Mode-file propagation*) | blocks step 4 (drill) and step 5 (fleet-wide shadow) | :warning: not started |
| Observability: how service metrics are exported today | blocks step 3 | :warning: not started — see metrics.md |
| Gateway owners: rate limiting at the gateway (README option B) | follow-up if fleet grows | not proposed yet |

## Deployment plan

- **Runtime toggle:** a kill switch, justified: the ticket asks for it,
  and the failure (real users throttled) is client-facing.  Shape: the
  mode file (ADR 0001), env default `off` until step 7, then `enforce`;
  kept indefinitely.
- **Rollout:** prod `off` (step 2) → staging `shadow` (4) → prod
  `shadow` ≥ 7 days (5) → one-host canary `enforce` 24 h (6) → fleet
  `enforce` (7).
- **Signals per stage:** step 2: search error rate and p95 unchanged.
  From step 4 on: `search.ratelimit.errors` = 0 and `check_seconds` p99
  < 1 ms; in shadow, the
  `would_throttle` rate and distinct would-throttle keys (should be a
  handful of obvious scrapers, not hundreds of keys); in canary/fleet,
  `throttled` rate and search p95 latency (metrics.md).

## Rollback strategy

- **Fastest:** write `off` (or `shadow`) to the mode file — effective per
  host within 5 s; fleet-wide time is contingent on feasibility.md
  *Mode-file propagation*.  Covers (a).  For (e) — a host that missed
  the write — re-write that host's file, or restart a process whose
  gauge is stale (runbook symptom 4; ADR 0001).
- **Slower:** revert the deploy that wired the middleware (minutes);
  for (c) if failing open isn't enough (e.g. a latency regression).
- **Blast radius while broken:** at worst, anonymous search users get
  `429` until the switch is flipped.  No data at risk: there is no
  persisted state, so nothing survives a rollback.

## Definition of done

- [ ] Plan reviewed and approved, including C1–C7 in README
- [ ] All README *Open questions* and feasibility.md `:warning:` items
      answered and the docs updated
- [ ] `search-service` dependency manifest unchanged by this feature (C1)
- [ ] `search-service/search/ratelimit.py` wired into the WSGI entry
      point; `search-service/tests/test_ratelimit.py` covers every
      scenario in test-cases.md
- [ ] Mode file at `/etc/search-service/ratelimit-mode` contains
      `enforce` on every search host, and `SEARCH_RATELIMIT_MODE=enforce`
      in the deployed env
- [ ] Kill-switch drill done in staging and recorded in the ticket
      (time from write to `mode` gauge flip, per host and fleet-wide)
- [ ] Every metric in metrics.md visible on the RITA-1 dashboard; its
      link recorded in metrics.md *Dashboards*
- [ ] Shadow-stage baseline and chosen `RATE`/`BURST` recorded in the
      ticket
- [ ] runbook.md symptoms 1–4 diagnostic steps executed once against
      prod and still return the expected shape
- [ ] README *How it works*, *System interactions*, *Configuration*
      filled in; `plan.md` deleted
