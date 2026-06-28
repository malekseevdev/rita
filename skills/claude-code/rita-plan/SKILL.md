---
name: rita-plan
description: Use when the user asks to plan or ship a non-trivial feature. Skip for bug fixes, dependency bumps, refactors, and other small or already-documented work.
---

# Rita: plan (and ship) a feature

This skill drives the Rita framework for non-trivial feature
work.  The `docs/` and `templates/` referenced below live
alongside this `SKILL.md`, in the same skill directory
(typically `~/.claude/skills/rita-plan/` for a user-level
install, or `<project>/.claude/skills/rita-plan/` for a
project-scoped install).

When invoked, **read these two files once at the start of the
session** — refer back as you work:

1.  `docs/framework.md` (alongside this `SKILL.md`) —
    orientation, lifecycle diagram, and the "When to skip"
    opt-out table.  Check this first: if the task qualifies for
    skipping, stop and just do the change directly.
2.  `docs/how-to.md` — the procedural reference for the six
    phases of the lifecycle (sections 1-3 form a **planning
    loop** that iterates on failure; 4-6 run linearly once
    approved).  Treat this as the canonical instruction set;
    apply its *Drafting rules* throughout.

`docs/rationale.md` carries the *why* behind each decision in
how-to.  You don't need to read it cover-to-cover at the start,
but open it whenever a drafting-rule edge case comes up —
applying the rules mechanically without judgment is a
predictable failure mode.

Templates are in `templates/`.  See that directory rather than
maintaining a list of filenames here.

## When to invoke

Invoke when the user asks to plan or ship a feature that meets
the framework's threshold:

-   Ships user-observable behaviour or a state change.
-   Has non-trivial blast radius (would break a real user's day
    if rolled back hours later).
-   Is bigger than a one-line fix, a dep bump, or an
    interface-preserving refactor.

Skip the framework for changes that match
`docs/framework.md#when-to-skip-this-process`.

## What to do

### A. Confirm scope

Read the ticket.  If it qualifies for skipping per
`framework.md`, ask the user to confirm and stop here.

### B. Identify the target component

Ask the user which component the feature belongs to.  In a
monorepo, this is the top-level service/module name
(`auth-service/`, `billing/`, `frontend/`, etc.).  Don't guess
based on filenames — the user owns this choice.  If the repo
has no obvious component layer (single-package project, library
without sub-modules), use the repo root and skip the question.

### C. Bootstrap the feature folder

From the user's project root, copy the templates from this
skill's directory into a new feature folder:

```bash
cp -r <skill-dir>/templates <component>/docs/features/<TICKET-ID>-<slug>/
```

`<skill-dir>` is the directory containing this `SKILL.md` —
typically `~/.claude/skills/rita-plan/`.  Then set up the new
folder per how-to.md §1 (the `README.md` frontmatter; don't fill
in the body yet — Phase 1 directs what goes where).

### D. Walk the six lifecycle phases

Follow `docs/how-to.md` sections 1-6.  Apply the *Drafting
rules* at `docs/how-to.md#drafting-rules` throughout.

The planning loop (phases 1-3) iterates on failure:

-   Phase 1 (*Plan options*) → fill in `README.md`'s Overview,
    Why, *Invariants & constraints*, Options considered + Preferred,
    Impact.  **Then stop at the constraint-approval checkpoint: have the
    human approve or correct the *Invariants & constraints* (and
    Preferred) before Phase 2** — they're the plan's constitution.  See
    how-to §1 *Confirm the constraints before continuing* for the
    no-non-negotiables and headless cases.
-   Phase 2 (*Feasibility check*) → verify only the *genuinely
    uncertain* (usually external) load-bearing assumptions — many
    features need no verified block.  The gate: a check you *ran* that
    fails (*Observed ≠ Expected*) loops back to phase 1; an assumption you
    *can't* verify does not block — flag it and write the full plan
    anyway.  See how-to §2 for what earns a block and what doesn't.
-   Phase 3 (*Plan review*) → fill in `plan.md`, then run the
    **self-improvement loop** (how-to §3 Pass 1 owns the loop and its
    iteration cap):
    -   **Review** — spawn a fresh-context **subagent** (Agent/Task tool)
        to run `rita-review` on the folder, so the review reads what's on
        the page, not your authoring rationale.  It only *reviews* —
        returns a scorecard + improvements, edits nothing; *you* then
        apply them.
    -   **Invocation** — normally `/rita-review <folder>`, or
        `/<prefix>rita-review <folder>` under this skill's prefix; if the
        subagent can't invoke the skill, it reads `rita-review`'s
        `RUBRIC.md` + docs and returns the same scorecard + improvements.

Once approved, the path is linear:

-   Phase 4 (*Implementation*) → evolve `README.md`'s
    implementation sections + `metrics.md` + `runbook.md` +
    `test-cases.md` as code is written.
-   Phase 5 (*Ship*) → verify Definition of Done; delete
    `plan.md`.
-   Phase 6 (*Maintain*) is invoked separately, not as part of
    the initial shipping session.  When the user asks you to
    check a feature later — doc drift and doc↔code gaps (the
    `rita-delta` skill), metric health, runbook freshness — see
    how-to.md Phase 6 for what to do.

### E. Surface clarifying questions

When something is genuinely unknown, mark it
`:warning: needs human input` with a one-line note.  Don't
guess.  Group questions and ask the user in a single pass
rather than scattering them.  Fold the Phase-1 constraint-approval
checkpoint into this same pass — one interaction, before feasibility and
`plan.md`.

## Boundaries

-   **Don't make remediation decisions autonomously.**  Flipping
    feature flags, rolling back releases, or running migrations
    requires human approval.  Diagnose, propose, wait.
-   **Don't fabricate feasibility verifications.**  If you can't
    actually run the command in a realistic environment, say so
    and surface it as a clarifying question rather than
    recording an *Observed exit* you didn't observe.
-   **Don't skip the planning loop.**  If the user pushes to
    "just write the implementation steps," push back: the
    feasibility check exists to prevent two days of plan
    writing on a dead approach.

## Reporting back

After each lifecycle phase, summarise what was done in 2-3
sentences plus the file diff.  Three artifacts deserve explicit
surfacing rather than just the diff:

-   At the end of *Plan options* (phase 1): emit the *Invariants &
    constraints* and the *Preferred* option and ask the human to approve
    or correct them — the constraint-approval checkpoint (see section D
    and how-to §1).
-   At the end of *Feasibility check* (phase 2): emit each
    `feasibility.md` block you wrote, with its *Observed exit*
    and *Observed output*.  Feasibility blocks are the
    most-fabricated artifact in agent-drafted plans; surfacing
    them gives the user a focused point to spot-check before
    the rest of the plan is written.
-   At the end of *Plan review* (phase 3): emit `rita-review`'s
    output — the self-review checklist (pass/fail) and the
    scorecard — plus what you changed in response across the
    loop.  This is the artifact the human reviewer uses to decide
    whether to look at the doc or send it back for fixes.
