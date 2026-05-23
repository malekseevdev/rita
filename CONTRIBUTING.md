# Contributing

Issues and pull requests welcome.  Rita is small and opinionated;
keep that in mind when proposing changes.

## Filing issues

-   **Doc bug** (typo, broken link, internally inconsistent
    guidance) — open an issue, name the file and section.
-   **Framework gap** (a real pain point the current framework
    doesn't address) — open an issue describing the scenario.
    Include enough context that a reader can judge whether the
    gap warrants new framework surface area or whether the
    existing framework already covers it under a different name.
-   **Script bug** (`scripts/check.py` does the wrong thing) —
    open an issue with the command you ran, expected output,
    observed output, and your Python version.

## Proposing changes

For framework changes (`docs/framework.md`, `docs/how-to.md`,
`docs/rationale.md`, or the templates), follow this order in the
PR:

1.  Update `docs/rationale.md` first — explain *why* the change
    is needed.  If you can't explain it there, the change
    probably doesn't belong in the framework.
2.  Update `docs/how-to.md` to reflect the operational
    consequence.
3.  Update templates and `docs/framework.md` if either is
    affected.
4.  In the PR description, name the load-bearing argument from
    `rationale.md` that the rest of the change implements.

For script changes (`scripts/check.py` or future scripts), keep
the stdlib-only constraint.  Third-party dependencies need a
strong argument and should be raised in an issue first.

## Design principles for contributors

When proposing framework changes, the following principles should
guide the design.  Reviewers will push back on changes that
violate them without a strong reason.

-   **Prefer stop-and-ask over agent autonomy.**  Rita's working
    assumption is that humans stay in the loop for judgment
    calls.  New features should add stop-and-ask moments
    (clarifying questions, author-validation prompts, refusal
    to fabricate) rather than agent autonomy.  Net new
    autonomy needs explicit justification, especially for
    decisions with operational consequences (flag flips,
    rollbacks, migrations).
-   **Detection over prevention.**  Optimise for catching
    problems where they're cheap (planning time, review time)
    rather than preventing them through up-front exhaustive
    analysis.  The framework accepts that errors happen; it
    structures the work so errors are discovered fast.
-   **Falsifiability where claims are checkable.**  When the
    framework asks for a verification, it should be structured
    so a reviewer or a script can re-check it.  Prose-only
    "verified" is not verification.

## What's out of scope

-   **Company-specific examples.**  Rita is sanitised by design.
    Don't add examples that name specific products, customers,
    or internal systems.  Generic equivalents only.
-   **Spec-language extensions.**  Rita is markdown for humans
    and agents; not a DSL that compiles into code.  Proposals to
    add a "spec compiles to behaviour" layer are out of scope —
    see the *What Rita is NOT* section in `README.md`.
-   **Process-management features.**  Rita documents engineering
    decisions, not project management.  Ticket tracking, sprint
    planning, and similar belong in your existing tooling.

## Commit style

-   One change per commit.  Framework changes and script changes
    in separate commits.
-   Subject line: imperative, ≤72 chars, no trailing period.
-   Body: explain *why* (the change you're making is obvious
    from the diff; the reasoning isn't).

## Code style

Python: stdlib only, target 3.9+.  No `requirements.txt`.

Markdown: no heading-level skips; one blank line between
sections; prefer reference-style links if a URL appears more
than twice in a file.
