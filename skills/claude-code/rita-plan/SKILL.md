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
typically `~/.claude/skills/rita-plan/`.  Then set the
frontmatter in the new `README.md` (Ticket, `Status: Plan`,
`Last reviewed: <today>`).  Don't fill in the body yet —
how-to.md's Phase 1 directs what to fill where.

### D. Walk the six lifecycle phases

Follow `docs/how-to.md` sections 1-6.  Apply the *Drafting
rules* at `docs/how-to.md#drafting-rules` throughout.

The planning loop (phases 1-3) iterates on failure:

-   Phase 1 (*Plan options*) → fill in `README.md`'s Overview,
    Why, Options considered + Preferred.
-   Phase 2 (*Feasibility check*) → verify only the *genuinely
    uncertain* (usually external) load-bearing assumptions; don't
    prototype-and-test code the plan will ship, and don't verify the
    self-evident — many features need no verified block.  A check you
    *ran* that fails (*Observed ≠ Expected*) → loop back to phase 1.  An
    assumption you can't verify (infra, production, a human answer) does
    not block — flag it and write the full plan anyway.
-   Phase 3 (*Plan review*) → fill in `plan.md`, then run the
    **self-improvement loop**: have a **subagent** review the feature
    folder — a fresh context, so the review reads what's on the page, not
    your authoring rationale.  The subagent only *reviews* (it returns
    findings, it doesn't edit); **you then apply them** — edit the docs to
    resolve each improvement and failed check it reports.  **One** revision
    pass (the cap is two plan iterations: the initial draft plus one fix;
    a safety guard against churning), *then* hand to the human author/peer
    passes.  Spawn the subagent with
    the Agent/Task tool and have it run the `rita-review` skill on the
    folder — as listed in your available skills, normally `/rita-review
    <folder>`, or `/<prefix>rita-review <folder>` under the prefix this
    skill carries; if it can't invoke the skill, it reads that skill's
    `RUBRIC.md` and the docs and returns the same scorecard + improvements.

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
rather than scattering them.

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
sentences plus the file diff.  Two artifacts deserve explicit
surfacing rather than just the diff:

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
