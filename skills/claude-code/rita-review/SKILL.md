---
name: rita-review
description: Review a Rita feature plan (a docs/features/<id>/ folder) — an agent self-review checklist and a rubric-scored quality scorecard with improvements. Plan-time, doc-internal — for checking shipped docs against the code, use rita-delta instead. Use when asked to review, score, grade, or verify a Rita plan, to compare plans from different models, or as the automated verification step of rita-plan before human review.
---

# Rita: review a plan

The agent verification pass over a feature *plan* — everything that can
be checked, before a human looks, by reading the docs against themselves
and the framework. Two parts, in order:

1.  **Self-review** — mechanical alignment with the framework.
2.  **Scorecard** — quality scored against the shared [`RUBRIC.md`](RUBRIC.md).

This is plan-time and doc-internal: it does not read the docs against the
*code*. Checking a shipped or in-flight doc set against the
implementation — mechanical drift, doc↔code gaps, stalled status — is
[`rita-delta`](../rita-delta/SKILL.md)'s job.

`rita-plan` runs this automatically after drafting (its self-improvement
loop); you can also invoke it standalone to verify your own plan, or to
compare plans from different models/agents (the headless
`tests/e2e/rank_plan.sh` runs this same skill, so scores are consistent).

## What to do

**Find the target.** A path may be given (e.g. `/rita-review
path/to/feature`); otherwise the user names it. It's a directory with
`README.md` and usually `feasibility.md`, `plan.md`, `test-cases.md`,
`metrics.md`, `runbook.md`. If it has no `README.md`, it isn't a Rita
feature folder — say so and stop.

### 1. Self-review checklist

Re-read the doc set against the framework and report pass/fail per item,
with a one-line reason for any fail. This is the pass/fail gate; for the
qualitative criteria below (feasibility, coherence, brevity) apply the
matching [`RUBRIC.md`](RUBRIC.md) definition rather than restating it —
the scorecard (§2) then scores those same criteria 0–5.

- [ ] **Sections filled** — every section each file owns is filled in
  (no skipped/placeholder sections except those explicitly deferred to
  implementation).
- [ ] **Drafting rules applied** — for each rule in
  `docs/how-to.md#drafting-rules`, it's applied (name where) or noted as
  not-applicable and why.
- [ ] **Feasibility is honest** — apply RUBRIC.md's *feasibility*
  dimension and its *Load-bearing coverage* deep check: genuine
  uncertainty only, verified blocks show *Observed == Expected*,
  unverifiable assumptions flagged (not faked), and zero verified blocks
  is fine when nothing is genuinely uncertain.
- [ ] **Unknowns flagged** — every `:warning: needs human input` has a
  one-line note; clarifying questions are grouped, not scattered.
- [ ] **Consistency** — the doc set agrees with itself, along three axes.
  A finding usually fits one; if it fits more than one, report it **once**,
  under the most specific (core > internal-claim > cross-file).
  - *Cross-file* — no contradictions between README, feasibility, plan,
    metrics, runbook (a metric name, env var, or the preferred option vs
    what the plan implements, stated two ways).
  - *Internal-claim* — no claim made *unconditionally* in one place that
    another file makes *contingent*, and no behaviour described two ways
    (e.g. "disabled in seconds, no redeploy" flat in the Overview but
    flagged contingent in feasibility/plan). Name the two spots.
  - *Core coherence* — per RUBRIC.md's *Core coherence (idea +
    constraints)* deep check: flag a detail that drifts from the guiding
    idea (*Preferred*) or contradicts an *Invariants & constraints*.
- [ ] **Brevity** — per RUBRIC.md's *Brevity* check: flag detail that
  doesn't change a decision and bloat that buries the load-bearing core.

### 2. Scorecard

Load [`RUBRIC.md`](RUBRIC.md) (alongside this file): the 0–5 scale, the 8
dimensions, the deep checks, the total→grade mapping, and the
improvements requirement. Apply it as written; don't invent dimensions.
Score each dimension, grounding every score in something you can point to
(or its absence). A missing/empty section scores 0; untailored
boilerplate 1–2. Be critical — a flattering score is useless.

Output the scorecard:

```
┌─ Rita plan scorecard ─ <feature-dir>
│ options          ████░ 4/5  includes Do-nothing; preferred well argued
│ feasibility      █████ 5/5  genuine externals flagged; nothing trivial
│ impact           ███░░ 3/5  audience clear; cross-service thin
│ plan_operability ████░ 4/5  kill switch justified; rollback realistic
│ metrics          ███░░ 3/5  no business-axis metric
│ runbook          ████░ 4/5  diagnostics concrete and executable
│ test_cases       ████░ 4/5  G/W/T with named tests
│ honesty          █████ 5/5  unknowns flagged, nothing faked
├─ TOTAL 32/40 (80%) grade B
│ <1–2 sentence verdict naming the biggest win and the weakest dimension>
└─
```

Then list the **top 2–3 concrete improvements** that would raise the
score, each naming the file and the specific gap.

## Boundaries

- **Read-only, and run nothing.** Judge the plan from its text alone. Do
  **not** run the feasibility `Command`s or any other command from the
  docs — re-running a feasibility block is the author's job, not the
  reviewer's. (Checking the docs against the *code* — including running
  `drift_check.py` — is `rita-delta`, a separate skill.)
- **Review, don't rewrite.** This skill verifies and scores; it does not
  edit the plan. If the user wants the gaps fixed, that's `rita-plan`'s
  job — point them there.
- **No score without evidence.** Every dimension score and checklist fail
  cites something in (or absent from) the docs. Don't pad.
- **Don't review non-Rita docs.** If the folder isn't a Rita feature
  folder, say so instead of forcing a result.
