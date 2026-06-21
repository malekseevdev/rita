# Rita plan-quality rubric

The shared grading criteria used by both the `rita-review` skill (an
agent grades interactively) and `tests/e2e/rank_plan.sh` (a headless
LLM-as-judge).  Keep this the single source of truth — edit here, not in
copies.

Grade a Rita feature doc set (README, feasibility, plan, test-cases,
metrics, runbook).  Rita's core values: verify load-bearing assumptions
*before* planning, treat operability (flags, metrics, runbook, rollback)
as a planning concern, mark unknowns instead of guessing, keep each fact
in one file — all in defence against confident hallucination.

## Scale (per dimension)

`0` absent · `1` token · `2` weak · `3` adequate · `4` strong ·
`5` exemplary.  Be critical and cite specifics; do not be generous.  An
empty template section scores 0; boilerplate that wasn't tailored to the
feature scores 1–2.

## Dimensions (8, each 0–5)

1. **options** — Options table with honest pros/cons, includes
   *Do nothing*, and the *Preferred* choice is justified (not just the
   most-obvious-from-the-code option).
2. **feasibility** — The *genuinely uncertain* load-bearing assumptions
   are identified and verified — uncertainty that's usually external (a
   library/version, an API, a platform, real data shape/scale, a service
   not owned), each with a concrete copy-pasteable command, *Env*, and
   *Expected == Observed* exit; proxy-gaps named; no fabricated
   verifications. **Dock points for blocks that verify nothing anyone was
   unsure of** — they dilute signal, they don't add it: a test of the
   author's own code dressed as feasibility (a token bucket enforces its
   limit → belongs in `test-cases.md`); the self-evident ("the stdlib has
   `time`"); or a command run on the *planning box* that "proves" a
   *production* fact (interpreter version, worker count) — that's a
   `:warning:` flag, not a check. **Full marks include correctly
   recognising there's nothing to verify:** a self-contained feature
   whose feasibility is just a few flagged external unknowns (or empty,
   with a one-line why) scores high. Reward honesty and signal, never
   block count.
3. **impact** — Audience, coordinated cross-service changes, and
   client/backwards compatibility are addressed concretely, not as
   boilerplate.
4. **plan_operability** — Implementation steps are ordered with
   partial-value milestones; *Concerns* are actually assessed (not
   blanket "N/A"); any runtime toggle (feature flag / kill switch) is
   justified rather than reflexive; the rollback path is realistic for
   the failure modes named.
5. **metrics** — Coverage across the four axes (usage, errors,
   performance, business) with specific, actionable thresholds.
6. **runbook** — Symptom → diagnostic steps that are concrete and
   executable, not vague prose.
7. **test_cases** — Given/When/Then scenarios; each names an
   implementation (automated test or *manual*); meaningful edge cases.
8. **honesty** — Genuine unknowns are flagged (e.g.
   `:warning: needs human input`) rather than guessed; no confident but
   unsupported specifics ("the SDK exposes that flag") survive
   unverified.

## Deep checks (run these before scoring)

Don't just check that sections exist — read the plan against itself.
These are **read-and-reason** checks: judge from the text, and **never
execute the feasibility commands or anything else from the docs**
(whether a command genuinely runs is the author's concern, not the
scorer's). Perform each check, let the findings inform the dimension
scores above, and surface anything material in the verdict /
improvements:

- **Load-bearing coverage** — scan README + plan for confident specifics
  ("the gateway overwrites X", "Postgres supports Y", "the SDK exposes
  Z"). Each genuinely-uncertain one must be *either* verified in
  feasibility *or* flagged `:warning: needs human input`. An unverified
  confident claim with no block at all is the worst failure (dock
  *honesty* and *feasibility*) — the rubric otherwise only grades the
  blocks that exist, not the ones that should.
- **Traceability** — the plan must cohere with itself: every *Concern*
  that names a real risk has a matching rollback path and/or runbook
  symptom; every metric in metrics.md is actually referenced as a signal
  (deployment stage or runbook); every state enumerated in *Impact* /
  preconditions has a test case. Dangling pieces are a gap.
- **Rollback soundness** — the rollback strategy actually addresses the
  failure modes *Concerns* names, and any "fastest path" claim is real
  (a flag flip is seconds; a data migration is not reversible by a flip).
- **Options → Preferred soundness** — *Preferred* follows from the stated
  trade-offs; rejected options are rejected for reasons that hold; it's
  the right choice, not merely the most-obvious-from-the-code one.
- **Constraint coherence** — if the feature has real non-negotiables, an
  *Invariants & constraints* block declares them, each names how it's
  checked, and no detail anywhere contradicts one (details reference the
  core, not restate it). A missing or prose-only constitution where the
  feature clearly has hard limits is a gap (dock *honesty*).
- **Brevity** — detail that doesn't change a decision is bloat: it buries
  the load-bearing core and invites drift. Reward plans that push
  non-load-bearing material out of band and reference it; dock padding and
  duplicated prose (which also drive the cross-file inconsistencies above).

## Total → grade

Sum the eight scores (max 40), take the percentage:

`A` ≥ 90% · `B` ≥ 80% · `C` ≥ 70% · `D` ≥ 60% · `F` < 60%.

## Also produce: improvements

A score on its own isn't actionable.  After grading, list the **2–3
highest-leverage improvements** — the changes that would raise the score
the most.  Each one names the doc file and a *concrete, specific* change
("add a business-axis metric for support-ticket volume", not "add more
detail").  Prefer the lowest-scoring dimensions.
