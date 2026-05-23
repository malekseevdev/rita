# Rita: Release It Toolkit (AI-first)

*Engineering coherence in the AI era.*

**Your AI agent's plan is confidently wrong, and you won't find out
until day 3 of implementation.  Rita catches it before you write
the rest of the plan.**

Rita is a codified feature lifecycle workflow.  It helps teams
preserve context, operational responsibility, and architectural
continuity from planning through long-term maintenance.

The headline above describes one of two costs Rita is built to
defend against: **plan-time wrongness** — agent hallucinations
that survive plan review and eat days of implementation.  The
other is **post-merge decay** — software development doesn't end
at merge, and AI has accelerated the rate of change along with
the rate of architectural decay, context loss, and operational
entropy.  Rita keeps the post-ship doc set alive long enough for
on-call and future modifiers to use it without re-deriving
everything from code.

Rita — *Release It Toolkit (AI-first)* — extends Michael Nygard's
[*Release It!*](https://pragprog.com/titles/mnee2/release-it-second-edition/)
*design-for-failure* stance from runtime to planning.

It's built for the era where AI agents draft plans, and defends against
their most expensive failure mode: **confident hallucination**.  An agent
writes a plausible-sounding specific ("Postgres 16 supports this index
method", "the S3 SDK exposes that flag") that survives plan review because
reviewers can't easily tell verified assertions from inferred ones — and
the gap isn't discovered until implementation tries it.  Rita's feasibility
check makes that distinction structural: every load-bearing claim ships
with a command and an observed exit code, so nothing slips through as
"the agent said so."

Beyond catching hallucinations, Rita treats **operability as a planning
concern**, not a deployment afterthought.  Feature flags and kill switches,
metrics across four axes, runbook conventions, rollback paths — all are
named decisions *before* code is written.  Features shipped with Rita are
operable by default; on-call has what they need without re-deriving it
from code.

Three core moves:

- **Verify load-bearing assumptions before writing the plan.**  Check
  whether the approach is buildable *before* drafting the rest of the
  plan, not after days of implementation reveal that it isn't.
- **Each fact lives in one file.**  README, feasibility, plan, runbook,
  metrics, test cases — six files, no overlap, no drift.
- **Detect rot mechanically.**  Linked-code mtimes vs. doc review dates,
  re-executable feasibility commands, structural lint rules.  The discipline
  survives without anyone watching.

Rita assumes AI agents draft the first pass of each document.  Without that,
the framework still applies, but the labor is higher.

## Philosophy

Rita's design follows from a specific stance: **engineering is
decision-making under epistemic scarcity.**  You can't fully prevent errors,
fully anticipate change, or fully verify your assumptions are correct.  The
framework optimises for *detection over prevention* and *evolutionary
stability* — decisions that hold up as conditions change, not decisions that
were correct at the moment they were made.

See [`docs/framework.md`](docs/framework.md) for the practice.

## What Rita is NOT

To pre-empt the comparison questions:

-   **Not a spec language.**  Rita's templates are markdown for
    humans and agents to read.  They aren't executable
    specifications that compile into code.
-   **Not a replacement for human review.**  The agent drafts,
    self-reviews, and surfaces clarifying questions.  Author
    and peer review remain human.  Rita formalises the review,
    it doesn't automate it away.
-   **Not a project-management tool.**  Tickets, milestones,
    sprint planning live in your existing tracker.  Rita
    documents the *engineering* decisions for a feature, not
    the *project* of building it.
-   **Not a code-generation framework.**  Rita produces docs
    that drive human and agent implementation decisions.  It
    doesn't generate code from a spec.
-   **Not a runtime / library / SDK.**  Rita is a discipline
    plus a few small scripts.  Nothing it ships gets linked
    into your application.

## Where Rita helps

Beyond the AI-hallucination defence, the framework earns its complexity
on a handful of recurring pain points:

-   **Coordinated multi-service changes.**  The Impact analysis section,
    cross-component Dependencies table, and deployment guidance (canary,
    percentage rollout, flag-gated) give a real coordination surface —
    not just "remember to talk to the other team."
-   **Documentation that survives author turnover.**  Options considered,
    the feasibility record, and the runbook stay in the feature folder
    after shipping.  A new team member or an on-call engineer at 2 AM
    has enough to operate without the original author present.
-   **Failure modes as first-class artefacts.**  The Concerns section,
    the runbook's symptom-indexed diagnostic steps, the metrics Errors
    axis, and the explicit rollback strategy collectively treat "what
    breaks" as planning input, not a deployment-day surprise.
-   **Operability built into the plan.**  Feature flags and kill switches
    are a planning decision, not a deployment afterthought — the
    runtime-toggle choice is part of Deployment planning, with naming
    and lifecycle conventions.  Metrics across four axes (Usage,
    Errors, Performance, Business) are part of the plan, not bolted on
    later.  By the time a feature ships, you know how to turn it off,
    what will break first, and how you'll see it break.
-   **Agents that know when to stop and ask.**  The framework bakes
    specific stop-and-ask moments into every phase: surface
    clarifying questions before review, ask the author about Impact
    items the codebase can't reveal, propose alternatives when the
    ticket implies one approach but another might be better, refuse
    to fabricate feasibility verifications.  Most agent failures
    come from confident over-action; Rita's discipline is calibrated
    stopping.

## Status

Production-ready once the first worked example lands — until
then, treat as a release candidate.  Framework documentation,
templates, the drift-detection script, and the Claude Code skill
are stable.  Additional scripts (feasibility verification, ship,
lint) and harness integrations beyond Claude Code are TODO.

## Getting started

1.  Clone:

    ```bash
    git clone https://github.com/malekseevdev/rita.git
    ```

2.  Install the Claude Code skill:

    ```bash
    cd rita
    ./install-claude-skill.sh              # user-level — available in every project
    # or
    ./install-claude-skill.sh /path/to/your-project   # project-scoped
    ```

    For other agent harnesses (Cursor, Continue, etc.) see
    [`skills/README.md`](skills/README.md) — the harness-agnostic
    agent prompt points your agent at the clone's path.

3.  When you have a non-trivial feature to plan, ask your agent
    to start working with Rita.  It bootstraps the feature
    folder, fills in what it can derive from the ticket and the
    codebase, and surfaces clarifying questions.

The full procedural reference the agent follows is in
[`docs/how-to.md`](docs/how-to.md).

Rita is graduated: the skill drafts the full feature-folder
artifact set, but you choose how much of it to engage with on a
given ticket.  Reviewing `README.md` (Options + Preferred) and
`feasibility.md` (load-bearing assumptions) is the minimum that
delivers Rita's core value; the rest of the doc set — plan,
test-cases, metrics, runbook — adds operational depth when the
team is ready for it.

## What's here

Organised by adoption level — start with the minimum, add the rest
when you want the operational depth.

**Minimum viable (~10 min to try):**

| Path | Purpose |
|---|---|
| [`docs/how-to.md`](docs/how-to.md) | The procedural reference.  *What each file owns* and *Feasibility check* sections cover the two minimum-viable practices; rest is optional. |
| [`templates/feasibility.md`](templates/feasibility.md) | The feasibility-block skeleton — copy this into your feature folder; record the critical assumptions the plan depends on. |

**Full framework (the operational depth):**

| Path | Purpose |
|---|---|
| [`docs/framework.md`](docs/framework.md) | Entry point — lifecycle diagram, "When to skip", pointers to how-to and rationale. |
| [`docs/rationale.md`](docs/rationale.md) | **Explanation.**  Why Rita is shaped this way — philosophy, lessons, agent-participation patterns.  Read narratively. |
| [`templates/`](templates/) | All six copy-and-fill skeletons (README, feasibility, plan, test-cases, metrics, runbook). |
| [`skills/`](skills/) | Agent-harness integrations.  Claude Code skill + harness-agnostic agent prompt — ships.  Cursor, Continue, etc. — TODO. |
| [`scripts/check.py`](scripts/check.py) | Drift detection.  Python 3.9+ stdlib, runs against `<root>/**/docs/features/`. |
| `scripts/feasibility_verify.py`, `ship.py`, `lint.py` | TODO — automated feasibility re-execution, ship-time ephemeral trim, structural lint. |

## Rita vs. ADRs, RFCs, design docs

If you already use ADRs, RFCs, or tech-spec templates: Rita
doesn't replace them, it extends design-doc practice through
implementation, shipping, and maintenance.  ADRs and RFCs
typically end at *approval* — the document is frozen, the work
begins.  Rita keeps the document evolving as code is written,
deletes the ephemeral planning state at ship time, and exposes
the survivors (options considered, feasibility record, runbook)
to on-call and future modifiers.  The feasibility check
primitive — falsifiable verification of load-bearing assumptions
before the rest of the plan is drafted — doesn't have a direct
equivalent in any of those, but slots in alongside them without
conflict.

The other closest neighbour is [GSD](https://github.com/gsd-build/get-shit-done) —
an AI-agent orchestration framework focused on *context engineering*
(keeping agent context windows healthy across long sessions).  GSD
optimises for greenfield agent-heavy work; Rita optimises for
long-lived production systems where on-call is downstream of the
docs.  Different diagnoses, different fits.

## Requirements

To use the framework: an AI agent (Claude Code, Cursor, or any
harness that can read the templates and follow the procedural
reference in [`docs/how-to.md`](docs/how-to.md)).  Nothing to
install.

To run the optional drift-detection script
([`scripts/check.py`](scripts/check.py)): Python 3.9+ (stdlib
only, no third-party dependencies) and Git.

## License

MIT.  See [LICENSE](LICENSE).
