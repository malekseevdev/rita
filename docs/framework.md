# The framework

A guide for planning, building, documenting, and proving that
non-trivial features actually work in production.  Applies to any
epic that ships user-observable behaviour or a state change — not
to bug fixes, dependency bumps, or small refactors (see
[When to skip this process](#when-to-skip-this-process) below).

> Templates: [`../templates/`](../templates/) — copy into your
> project's `<component>/docs/features/<TICKET-ID>-<slug>/` and
> fill in.

## Lifecycle

Planning is iterative; everything after is mostly linear:

```
┌─── Planning loop ────────────────────────────────────────┐
│                                                          │
│   Plan options ──► Feasibility ──► Plan Review           │
│        ▲                                │                │
│        └────── rework on failure ───────┘                │
│                                                          │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼ approved
          Implementation ──► Ship ──► Maintain
```

Inside the planning loop, three failure modes loop back to drafting:

-   Feasibility check fails → the load-bearing assumption doesn't
    hold; rework the approach (or close the ticket).
-   Reviewer questions an assumption → re-verify, possibly with a
    different command or proxy.
-   Reviewer raises a design concern → revise the plan and re-submit.

Once approved, the path is linear in the common case.  Implementation
can occasionally surface a broken assumption that requires looping
back, but that's the exception — the feasibility check exists to
catch those before this point.

The feature folder starts at
`<component>/docs/features/<TICKET-ID>-<slug>/`.  Its files evolve:
during implementation the ephemeral parts (implementation steps,
dependencies, deployment plan) get trimmed and the evergreen parts
(how it works, options considered, metrics, runbook, feasibility
record) stay.  By the time the feature ships, the doc set has
become the long-term feature documentation.

## When to skip this process

The full process is overkill for small, contained, or
already-documented work.  Skip it explicitly (don't just forget)
when the change matches one of the categories below.

| Skip when…                                                       | Why                                                                  |
| ---------------------------------------------------------------- | -------------------------------------------------------------------- |
| One-line bug fix or typo                                         | Commit message + test is the documentation.                          |
| Removing dead code where consumers are known                     | The deletion *is* the change; `git log` records why.                 |
| Pure dependency upgrade with no behavioural change               | `requirements.txt` diff + changelog link in the commit is enough.    |
| Test-only changes                                                | Tests are documentation; coverage report is the metric.              |
| Documentation-only changes                                       | Self-evident.                                                        |

**Size and impact matter more than type.**  Small refactors, small
tooling changes, and small experiments are usually contained and fit
the skip criteria above.  Their larger counterparts — multi-week
refactors of a critical subsystem, build-system or CI migrations,
experiments running against real production traffic — benefit from
at least an *impact analysis* and a *feasibility check* even if you
skip the rest of the framework.  The framework is graduated; adopt
the parts that earn their place for the change in front of you.

If you're unsure, ask: "in 12 months, will someone unfamiliar with
this change need to understand it from the repo alone?"  If yes,
write the doc.  If no, skip it.

## Read more

Two files, one for each reading mode:

| File | When to read it |
|---|---|
| [`how-to.md`](how-to.md) | You're using the framework on a real feature.  Procedural reference: templates, format specs, checklists, commands. |
| [`rationale.md`](rationale.md) | You're trying to understand why Rita is shaped this way — or considering adopting it.  Philosophy, lessons learned, agent-participation patterns. |
