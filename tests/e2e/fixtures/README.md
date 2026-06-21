# Eval fixtures

Deliberately-constructed feature folders for evaluating the **`rita-review`**
and **`rita-delta`** skills — each with *known, planted* defects so a run can be
graded objectively (did the skill catch what's there, and nothing it shouldn't?).

They're plain files: no `.git` history is committed. A consuming test builds a
throwaway git repo with pinned commit dates at runtime (the way `test_drift.sh`
already does), so the date-sensitive checks are deterministic. The semantic and
`--refs` checks work without git; only date-drift / "stale review date" needs it.

The clean *plan* case for `rita-review` isn't here — the committed worked example
(`examples/search-rate-limit/`) already serves that role.

## `review-flawed/` — for `rita-review`

`docs/features/DEMO-9-export/` — a plausible-looking plan with five planted
defects a good review must catch:

1. **Options table omits *Do nothing*** (`README.md`).
2. **Fabricated feasibility block** — a *production* fact ("object store accepts
   5 GB uploads") "verified" by a trivial command on a *dev laptop*
   (`feasibility.md`).
3. **Trivial/self-evident block** — verifies the stdlib `csv` writer
   (`feasibility.md`).
4. **Empty Rollback** — literal `TODO`; `Concerns` are blanket `N/A` (`plan.md`).
5. **Cross-file metric-name contradiction** — `export.jobs.completed` (README)
   vs `export.completed.count` (metrics/runbook).

(Also present, as secondary signals: an unused `EXPORT_JOB_TTL_HOURS`,
single-axis metrics, one happy-path test.)

## `delta-*/` — for `rita-delta`

Each is a feature folder plus the code it describes, for the doc↔code audit.

- **`delta-postship-drift/`** (`DEMO-2-widget`, post-ship) — code diverged from
  docs: metric `svc.widget.processed` (docs) vs `svc.widget.handled` (code); flag
  `FEATURE_WIDGET_FAST` (docs) vs `FEATURE_WIDGET_TURBO` (code); the fast path is
  a behaviour switch, not just a perf toggle (undocumented). Plus an unresolved
  `:warning:` and an intentionally old `Last reviewed` date (stale once git is
  built). Expected: surface all of these with A/B fix options.

- **`delta-postship-clean/`** (`DEMO-3-widget`, post-ship) — docs and code agree
  exactly. Expected: report **in sync**, and *not* manufacture findings (the
  anti-fabrication check).

- **`delta-preship-diverge/`** (`DEMO-4-throttle`, pre-ship; `plan.md` present) —
  plan/DoD say 100 req/min, configurable via `THROTTLE_RATE`, behind a kill
  switch; code hardcodes 60, no `THROTTLE_RATE`, no switch. Expected: detect
  **pre-ship mode** and flag the plan↔code divergences (without false-flagging
  the metric the code *does* emit).
