# AGENTS.md — working on Rita

Rita is a feature-planning discipline: a framework (`docs/`), three Claude
Code skills (`skills/`), and one drift script (`scripts/`).  This file
orients an agent *developing Rita itself*.  It is a map, not a manual — it
points to the canonical docs and states only the development rules that
aren't written down elsewhere.

**Rita is built under its own discipline.**  Everything Rita asks of a plan
— brevity, single source of truth, falsifiable claims, a legible core —
applies to this repo's own docs.  If a change to Rita would fail Rita's own
review, fix the change.

## Where things live (point, don't duplicate)

- `docs/framework.md` — the pillars, the lifecycle, the "when to skip" table.
- `docs/how-to.md` — the **canonical** procedure (six phases) and the
  drafting rules.  This is the single home for the rules.
- `docs/rationale.md` — the *why* behind each rule.  Framework changes
  start here.
- `CONTRIBUTING.md` — contributor design principles (stop-and-ask,
  detection-over-prevention, falsifiability), scope boundaries, the
  rationale-first PR order, and commit/code style.
- `skills/claude-code/{rita-plan,rita-review,rita-delta}/` — plan, review
  (read-only), audit-vs-code (read-only).
- `scripts/drift_check.py` + `tests/e2e/` — the one piece of real logic and
  its tests.

## Development invariants

Load-bearing, and not (fully) stated elsewhere:

- **Sharpen, don't add a pillar.**  The concept is frozen.  New work must
  sharpen an existing pillar —
  front-loaded feasibility, one-fact-per-file, mechanical drift detection,
  operability-as-planning.  Reject new pillars (project-management features,
  a spec DSL); be default-skeptical of new surface area.
- **Single source of truth.**  Each rule lives in exactly one place.
  `docs/how-to.md` owns the procedure and all specifics; a `SKILL.md` is a
  thin driver that *names* a phase and *points* to how-to — it must not
  restate a rule with its specifics (numbers, flag strings, trap lists),
  because two copies drift.  Skills carry only what's skill-specific (the
  install path, subagent invocation).
- **Brevity, applied to our own docs.**  As brief as possible, never
  briefer.  Push non-load-bearing detail out of band and reference it; a
  short doc has no patchwork problem.
- **The plan's core is a pair.**  The guiding idea (*Preferred*) plus the
  invariants & constraints.  Every detail is subordinate to both —
  constraint → check, idea → coherence.
- **Review skills are read-only.**  `rita-review` and `rita-delta` detect
  and propose; they never mutate the docs and never execute a plan's
  feasibility commands.  Re-running a feasibility block is the author's job.
- **Falsifiability + stdlib-only.**  Verifications must be re-checkable —
  prose-only "verified" is not verification.  Scripts are Python stdlib
  only, 3.9+ (see `CONTRIBUTING.md`).

## Workflow

- One change per commit; framework and script changes in separate commits
  (`CONTRIBUTING.md`).  End commit bodies with the `Co-Authored-By:` trailer.
- Don't edit a script while a background run of it is in flight — bash
  re-reads the file mid-run.
- After changing a skill or the framework docs, sanity-check with
  `tests/e2e/`: the drift test is deterministic; the plan/review tests call
  a model.
