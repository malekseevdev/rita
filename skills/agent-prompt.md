# Rita: generic agent prompt

Paste this into your agent's context (system prompt, project
instructions, or wherever the harness lets you pin durable
guidance) when starting non-trivial feature work.  It's the
harness-agnostic equivalent of the Claude Code skill — same
instructions, different packaging.

First, clone Rita on the agent's host:

```bash
git clone https://github.com/malekseevdev/rita.git
```

Before pasting, replace `<RITA-ROOT>` below with the absolute
path to that clone (e.g. `/home/alice/rita`, `~/code/rita`).
The agent needs to read files there; without a working path,
the prompt is inert.

---

You're going to plan and ship a non-trivial feature using the
**Rita framework**.  Before you write anything, **read these two
files once**:

1.  `<RITA-ROOT>/docs/framework.md` — orientation, lifecycle
    diagram, and the "When to skip" opt-out table.  If the task
    qualifies for skipping, stop and just make the change
    directly.
2.  `<RITA-ROOT>/docs/how-to.md` — the procedural reference for
    the six phases of the lifecycle (sections 1-3 form a
    **planning loop** that iterates on failure; 4-6 run linearly
    once approved).  Treat this as the canonical instruction
    set; apply its *Drafting rules* throughout.

For deeper reasoning behind any decision, see
`<RITA-ROOT>/docs/rationale.md`.

The templates live at `<RITA-ROOT>/templates/` (six files:
`README.md`, `feasibility.md`, `plan.md`, `test-cases.md`,
`metrics.md`, `runbook.md`).

## What to do

### A. Confirm scope

Read the ticket.  If it qualifies for skipping per
`framework.md`, ask the user to confirm and stop here.

### B. Identify the target component

Ask the user which component the feature belongs to.  In a
monorepo, this is the top-level service/module name
(`auth-service/`, `billing/`, `frontend/`, etc.).  Don't guess
from filenames — the user owns this choice.

### C. Bootstrap the feature folder

From the user's project root:

```bash
cp -r <RITA-ROOT>/templates <component>/docs/features/<TICKET-ID>-<slug>/
```

Then set up the new folder per how-to.md §1 (the `README.md`
frontmatter; don't fill in the body yet).

### D. Walk the six lifecycle phases

Follow `<RITA-ROOT>/docs/how-to.md` sections 1-6.  Apply the
*Drafting rules* at
`<RITA-ROOT>/docs/how-to.md#drafting-rules` throughout.

The planning loop (phases 1-3) iterates on failure:

-   Phase 1 (*Plan options*) → fill in `README.md`'s Overview,
    Why, Options considered + Preferred.
-   Phase 2 (*Feasibility check*) → a block only for the
    *genuinely uncertain* load-bearing assumptions; many features
    need none.  A check you *ran* that fails (*Observed ≠
    Expected*) loops back to phase 1; an assumption you *can't*
    verify is flagged, not blocked — write the full plan anyway
    (see how-to §2).
-   Phase 3 (*Plan review*) → fill in `plan.md`, then run the
    three-pass review.  The agent self-review pass is your job;
    do it before asking the human to look at anything.

Once approved, the path is linear:

-   Phase 4 (*Implementation*) — evolve `README.md`'s
    implementation sections + `metrics.md` + `runbook.md` +
    `test-cases.md` as code is written.
-   Phase 5 (*Ship*) — verify Definition of Done; delete
    `plan.md`.
-   Phase 6 (*Maintain*) — out of session for an agent driving
    the initial work.  Later, audit the doc set against the code:
    run `<RITA-ROOT>/scripts/drift_check.py` as a cheap first pass,
    then read the docs against the code for inconsistencies, gaps,
    unresolved `:warning:` markers, and stalled `Status:`, proposing
    a code-side and a doc-side fix for each divergence (detect and
    propose — don't mutate).

### E. Surface clarifying questions

When something is genuinely unknown, mark it
`:warning: needs human input` with a one-line note.  Don't
guess.  Group questions and ask the user in a single pass.

## Boundaries

-   Don't make remediation decisions autonomously (flipping
    flags, rolling back, running migrations).  Diagnose,
    propose, wait.
-   Don't fabricate feasibility verifications.  If you can't
    actually run the command, surface it as a clarifying
    question instead of recording an unobserved exit code.
-   Don't skip the planning loop.  The feasibility check
    prevents two days of plan writing on a dead approach.

## Reporting back

After each lifecycle phase, summarise what was done in 2-3
sentences plus the file diff.  At the end of *Plan review*
self-review, emit the explicit checklist from
`<RITA-ROOT>/docs/how-to.md#pass-1-agent-self-review` with
pass/fail per item — this is the artifact the author reviewer
uses to decide whether to look at the doc or send it back for
fixes.
