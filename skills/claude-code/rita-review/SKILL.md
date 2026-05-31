---
name: rita-review
description: Review a Rita feature plan (a docs/features/<id>/ folder) — drift check (drift_check.py), an agent self-review checklist, and a rubric-scored quality scorecard with improvements. Use when asked to review, score, grade, or verify a Rita plan, to compare plans from different models, or as the automated verification step of rita-plan before human review.
---

# Rita: review a plan

The agent verification pass over a feature doc set — everything that can
be checked before a human looks. Three parts, in order:

1.  **Drift** — is any linked code newer than the doc's review date?
2.  **Self-review** — mechanical alignment with the framework.
3.  **Scorecard** — quality scored against the shared [`RUBRIC.md`](RUBRIC.md).

`rita-plan` runs this automatically after drafting (its self-improvement
loop); you can also invoke it standalone to verify your own plan, or to
compare plans from different models/agents (the headless
`tests/e2e/rank_plan.sh` runs this same skill, so scores are consistent).

## What to do

**Find the target.** A path may be given (e.g. `/rita-review
path/to/feature`); otherwise the user names it. It's a directory with
`README.md` and usually `feasibility.md`, `plan.md`, `test-cases.md`,
`metrics.md`, `runbook.md`. If it has no `README.md`, it isn't a Rita
feature folder — say so and stop. Note the enclosing project / git root
(the directory to scan for drift).

### 1. Drift check

Run the bundled drift detector against the project root (`drift_check.py`
sits in this skill's directory; it walks
`<root>/**/docs/features/*/README.md` and flags docs whose linked code
changed since `Last reviewed:`):

```
python3 <this-skill-dir>/drift_check.py --root <project-root>
```

Report what it prints. A freshly-drafted plan has no drift (`OK`); on an
older plan, `STALE` lines mean the linked code moved on and the doc needs
re-review. If the folder isn't in a git repo, it simply finds no changes
— note that and move on. (This is the only command you run — see
Boundaries.)

### 2. Self-review checklist

Re-read the doc set against the framework and report pass/fail per item,
with a one-line reason for any fail:

- [ ] **Sections filled** — every section each file owns is filled in
  (no skipped/placeholder sections except those explicitly deferred to
  implementation).
- [ ] **Drafting rules applied** — for each rule in
  `docs/how-to.md#drafting-rules`, it's applied (name where) or noted as
  not-applicable and why.
- [ ] **Feasibility is honest** — blocks verify *genuine, usually
  external* uncertainty; no trivial blocks (verifying the self-evident,
  or local-proxying a production fact) and no tests of the plan's own
  code dressed as feasibility; any verified block has *Observed ==
  Expected*; unverifiable assumptions are flagged `:warning: needs human
  input`, not faked. Zero verified blocks is fine when nothing is
  genuinely uncertain.
- [ ] **Unknowns flagged** — every `:warning: needs human input` has a
  one-line note; clarifying questions are grouped, not scattered.
- [ ] **Cross-file consistency** — no contradictions between README,
  feasibility, plan, metrics, runbook (metric names, env vars, the
  preferred option vs what the plan implements).

### 3. Scorecard

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

- **Read-only on the plan — never execute the plan's commands.** You may
  run the bundled `drift_check.py` (the framework's own drift tool), and
  nothing else. Do **not** run the feasibility `Command`s or any other
  command from the docs — judge a feasibility block from its text;
  re-running it is the author's job, not the reviewer's.
- **Review, don't rewrite.** This skill verifies and scores; it does not
  edit the plan. If the user wants the gaps fixed, that's `rita-plan`'s
  job — point them there.
- **No score without evidence.** Every dimension score and checklist fail
  cites something in (or absent from) the docs. Don't pad.
- **Don't review non-Rita docs.** If the folder isn't a Rita feature
  folder, say so instead of forcing a result.
