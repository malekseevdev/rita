# How to use Rita

A procedural reference for the agent (or human) executing the
work.  Sections 1-3 are the **planning loop** (iterate on failure);
sections 4-6 run linearly once approved.  For the reasoning behind
any of these steps, see [`rationale.md`](rationale.md); for the
high-level phase diagram, [`framework.md`](framework.md#lifecycle).

## What each file owns

Don't duplicate prose across docs.

| Information | Owns it |
|---|---|
| What the change is, options considered, preferred solution + why, impact (audience + affected systems), how it works, system interactions, configuration | `README.md` |
| Load-bearing assumptions and their verifications | `feasibility.md` |
| Implementation steps, dependencies, deployment, rollback, DoD | `plan.md` (deleted at ship time) |
| Symptoms → diagnostics → fixes; operator one-shots | `runbook.md` |
| Metric names, thresholds, dashboards, baselines | `metrics.md` |
| Given/When/Then user-perspective scenarios | `test-cases.md` |

Throughout the work, take initiative — don't just elaborate on what
the user already wrote:

-   When something is genuinely unknown, mark it
    `:warning: needs human input` with a one-line note on what's
    missing.  Don't guess.
-   Surface clarifying questions proactively — scoped, informed,
    grouped — so the human can answer them in a single pass rather
    than discovering scattered `:warning:` markers at review time.
-   **Propose alternatives the user didn't ask for** if you see
    them.  The ticket is a starting point, not a constraint;
    engineering judgment includes spotting better paths and naming
    the trade-offs honestly: *"the ticket implies A, but B avoids
    the data migration; here's why I'd lean B."*  If the user
    confirms the original direction after seeing the alternative,
    fine — but make the choice deliberate.

## Drafting rules

These apply while filling in any of the docs.  Treat each as a
check against your draft — the failure mode is rework caught at
review instead of caught at writing.  Full reasoning for each
rule lives in [`rationale.md#drafting-pitfalls`](rationale.md#drafting-pitfalls).

-   **Ground every API/schema proposal in the closest existing
    precedent.**  Name the precedent in the plan so the reviewer
    has something concrete to compare against.  Divergence is
    fine; *unintentional* divergence is rework.
-   **Enumerate states around any precondition.**  When an action
    only applies in "some" states, list every state the object
    can be in and decide allowed/rejected for each.  The obvious
    state usually has an equally-valid twin that's easy to miss.
-   **Treat external services as hard scope boundaries.**  Name
    what *we* expose and stop there.  Don't pull a partner's
    change set into our plan.  External services go under
    *Dependencies*, not *Implementation steps*.
-   **For every data consumer, ask both "hide" and "keep visible".**
    Changes to visibility usually affect some consumers and not
    others.  List both sides explicitly.
-   **Don't add a runtime toggle by reflex.**  Feature flags and
    kill switches exist to manage real risk and cost ongoing
    complexity — see [Deployment planning](#deployment-planning).
-   **Merge test cases that share a Given.**  One Given with a
    bulleted When/Then list, not duplicated Given lines across
    several cases.
-   **Make Definition-of-Done items verifiable from the doc
    alone.**  Each checkbox names the artifact — the table and
    column, the URL, the file, the endpoint, the UI element.
    Vague verbs ("added", "implemented", "works") hide the
    thing being checked.

## 1. Plan options

Bootstrap a feature folder if you haven't already — either via
your agent harness's skill install (the rita-feature skill
handles this automatically) or by manually copying
[`../templates/`](../templates/) into
`<component>/docs/features/<TICKET-ID>-<slug>/`.  Set the
frontmatter in `README.md` (Ticket ID, `Status: Plan`,
`Last reviewed: <today>`).

Read the ticket.  Then fill in:

-   `README.md` *Overview* — one paragraph; what the feature does.
-   `README.md` *Why* — the problem this solves; distil it, don't
    paste the ticket.
-   `README.md` *Options considered* — the table of alternatives
    and trade-offs, with *Preferred* named.  Include options the
    ticket didn't mention if you see them — this is the place
    where "I considered B but rejected it because X" lives.
    Always include *Do nothing* — it forces the work to justify
    itself.
-   `README.md` *Impact* — which user segments and which systems
    this feature affects.  This is evergreen; on-call and future
    modifiers will read it.

Stop here and move to section 2.  Don't fill in `plan.md` yet —
feasibility may invalidate the preferred approach.

## 2. Feasibility check

For every load-bearing assumption of the preferred solution,
record a block in `feasibility.md`.  An assumption is load-bearing
if the plan dies when it fails.

Format:

```markdown
#### <short label>

- **Assumption:** <one sentence — what must be true for the plan to work>
- **Failure-mode:** <observable thing that would be different if false>
- **Command:** `<single shell command, copy-pasteable>`
- **Env:** <runtime version, distro, dependencies — whatever
  makes the verification reproducible>
- **Expected exit:** 0
- **Observed exit:** 0
- **Observed output:**
  ```
  <last ~10 lines of stdout/stderr that prove the assumption>
  ```
- **Recorded:** YYYY-MM-DD by <username>
```

Worked example:

```markdown
#### PostgreSQL 16 supports new_index_type

- **Assumption:** The `new_index_type` index method works on
  PostgreSQL 16 for this column type.
- **Failure-mode:** `CREATE INDEX` fails with a syntax error or
  "unsupported access method" error.
- **Command:** `psql -d testdb -c "CREATE INDEX CONCURRENTLY foo_idx ON items USING new_index_type (col)"`
- **Env:** postgres 16.1, ubuntu-24.04
- **Expected exit:** 0
- **Observed exit:** 0
- **Observed output:**
  ```
  CREATE INDEX
  ```
- **Recorded:** 2026-05-23 by alice
```

If an assumption is too expensive to verify directly (production
data shape, scale-dependent behaviour), record the cheapest proxy
plus a **`Proxy-gap:`** line stating what the proxy doesn't cover:

```markdown
- **Proxy-gap:** Stage bucket holds 500K keys, not 50M.  Linear
  extrapolation suggests ~1s at 50M; non-linear behaviour on
  the production prefix is not exercised by this proxy.
```

**Termination rule:** if *Observed exit ≠ Expected exit* and
there's no working alternative, loop back to section 1.  Pick a
different *Preferred* option (or close the ticket).  Don't
continue to section 3.

## 3. Plan review

Once every feasibility block has *Observed exit == Expected exit*,
fill in `plan.md`:

-   *Implementation steps* — ordered; mark partial-value milestones.
-   *Concerns* — concrete assessment per item (performance,
    security, etc.), not "N/A" everywhere.
-   *Dependencies* — what blocks us, what we block.
-   *Deployment plan* + *Rollback strategy* — see *Deployment
    planning* below.
-   *Definition of done* — verifiable items.

### Deployment planning

Three decisions to make explicitly, not by reflex:

**Runtime toggle — feature flag, kill switch, or none?**  These
are the two shapes of runtime control over shipped behaviour;
pick the one that matches the failure you're guarding against.

-   **Feature flag** — defaults *off*, you flip it *on* to
    enable.  Used to gate new client-facing behaviour during
    rollout; removed once the feature is stable everywhere.
    Add one when the change has client-facing behaviour with
    non-trivial blast radius (a bad rollout would break a real
    user's day).
-   **Kill switch** — defaults *on*, you flip it *off* to
    disable in an emergency.  Used to retain the ability to
    turn a feature *off* long after it's launched, when the
    failure mode is "this could melt down at 3 AM and we want
    a 30-second mitigation."  Kept indefinitely; not removed
    on the same schedule as feature flags.
-   **Neither.**  Skip both when the change is admin-only, has
    no client-facing behaviour, or is easy to revert with a
    follow-up MR.

Pick a name in the form `FEATURE_<area>_<thing>` for flags and
`KILL_<area>_<thing>` for kill switches — the prefix makes the
toggle's intent legible to oncall.  For feature flags, also
decide the flag's lifecycle: when does it get removed?
Cargo-culted flags accumulate cost.

**Rollout pattern.**  Default to gradual: staging deployment,
then a small percentage of production traffic (e.g. 10%), then
full.  For higher-risk changes consider a canary (a single host
or a marked subset of traffic) before the percentage rollout.
Big-bang releases are appropriate only for changes with
trivial blast radius or that have already been gated by a flag
defaulting off.  Name the *signals* to watch at each stage —
specifically the error and performance metrics from
`metrics.md`, since usage and business metrics need more time
to move.

**Rollback path.**  Toggle flip (feature flag off, or kill
switch off) is fastest — seconds.  Revert plus redeploy is
slower — minutes to hours.  Migration rollback is slowest and
may be impossible if data has been written in the new format;
in that case, the rollback is forward-fix-only, and the plan
should say so plainly.  Pick the strategy that matches the
failure modes the *Concerns* section flagged.  If the
realistic failure can't be cheaply reversed, the deployment
plan needs more gates, not less.

### Review — three passes (recommended)

Plan review works best as three sequential passes, not one.
Each catches what the others can't: agent self-review without
author review hides the human judgment; author review without
peer review hides the outside perspective.

For features at the framework's threshold (real blast radius,
real on-call implications), run all three.  For borderline
features that are still inside the framework's scope but on
the lighter end, agent self-review plus peer review may be
enough — the author and peer reviewer can be the same person.
Pick the rigour to match the risk.

#### Pass 1 — agent self-review

Before any human sees the draft, the agent re-reads its own work.
The job is mechanical alignment with the framework, not judgment.
Output a short report of what was checked and any items that
failed:

-   [ ] Every section per [What each file owns](#what-each-file-owns)
    is filled in (no skipped sections).
-   [ ] Every [drafting rule](#drafting-rules) was applied — for
    each rule, name where it applies in the draft (or note that
    it doesn't apply and why).
-   [ ] All `:warning: needs human input` markers have a one-line
    note explaining what's missing.
-   [ ] Clarifying questions are surfaced in a single grouped
    block (scoped, informed, grouped), not scattered.
-   [ ] `feasibility.md` is complete — every load-bearing
    assumption has a block with *Observed exit == Expected exit*.
-   [ ] Cross-file references are consistent — no contradictions
    between `README.md`, `feasibility.md`, `plan.md`, `metrics.md`.

If anything fails, fix it before handing off.  If a rule
genuinely doesn't apply, say so explicitly — silent omission
reads as oversight.

#### Pass 2 — author review

The human who owns the ticket reviews next.  This pass catches
what the agent can't know: institutional context, real
constraints, what the team actually wants.

**The agent drives this pass actively** — don't expect the author
to discover the questions on their own.  After self-review,
present the author with the doc set *and* the list of questions
below, framed as the prompts they should answer before approving:

-   Does *Preferred* match what you actually want?  Did I reach
    for the most-obvious-from-the-code option rather than the
    right one?
-   Are the *Options considered* honest — including alternatives
    you've thought about that I missed?
-   Are there constraints (timeline, customer, political,
    cross-team) you couldn't have written into the ticket?
-   Are the *Impact* assessments in `README.md` accurate?  Did
    I identify the right user segments, coordinated changes,
    and downstream consumers — or did I miss any that you know
    about?  Impact requires institutional knowledge that isn't
    in the code; agent-filled impact items always need a human
    pass.
-   Did I misread the codebase anywhere?  Worth spot-checking
    file:line references in `README.md` and `feasibility.md`.
-   Are the clarifying questions I surfaced the right ones, or
    are there others you'd add?
-   Is the feasibility evidence convincing to you — not just
    that *Observed == Expected*, but that the *Command* actually
    tests the assumption you care about?

The author either approves and forwards to peer review, or sends
back with specific fixes.

#### Pass 3 — peer review

A second human — another developer or stakeholder, not the
ticket owner — reviews the doc set.  This pass catches what the
author can't see: design choices that look obvious to the
author but aren't, gaps the author has blind spots on.

In practice this happens in a merge request (or equivalent code-
review surface).  **The agent posts the review prompts in the MR
description or as a top-level comment** so the peer reviewer
sees them up front rather than guessing what to look at:

-   Can you explain the preferred solution from `README.md` alone?
-   Are there options that weren't considered?
-   Does every load-bearing assumption have a block in
    `feasibility.md` with *Observed exit == Expected exit*?
-   For each block, does the *Failure-mode* name something the
    *Command* would actually exhibit?  (Meaningful, not hollow.)
-   Do `plan.md`'s *Concerns* items have realistic assessments —
    not just "N/A" on everything?
-   Does `plan.md`'s *Rollback strategy* cover the realistic
    failure modes?
-   Are the metrics in `metrics.md` specific enough to know if
    this worked in 30 days?
-   Is the implementation ordered so partial value ships early
    and the work can stop if priorities change?
-   Are the dependencies listed and realistic?
-   Would you be comfortable being on-call when this ships?

If the peer reviewer raises a design concern, loop back to
section 1.  If they question an assumption, loop back to
section 2.  If they catch something the author or agent should
have caught, the prior pass needs sharpening — flag it.  Once
the peer reviewer approves, move to section 4.

## 4. Implementation

Update `Status: Implementation` in `README.md`.  As code is
written:

-   Fill in `README.md` *How it works* with file:line references.
-   Fill in `README.md` *System interactions* as integrations are
    built.
-   Fill in `README.md` *Configuration* as settings are added.
-   Update `test-cases.md` as edge cases are discovered.
-   Fill in `metrics.md` with actual metric names and thresholds.
-   Fill in `runbook.md` with real debug steps.
-   Update `Last reviewed:` on each iteration.

If implementation reveals that a load-bearing assumption was
wrong, update `feasibility.md` and re-enter the planning loop.

## 5. Ship

Before declaring done, verify the Definition of Done — in
addition to the existing per-component DoD (linters, tests, code
review):

-   [ ] Plan was reviewed and approved before implementation started.
-   [ ] `README.md` has all shipped-state sections including
    *Options considered* and *Preferred*.
-   [ ] `feasibility.md` has all load-bearing assumptions verified
    (*Observed exit == Expected exit*) and is frozen.
-   [ ] `plan.md` is deleted.
-   [ ] Every scenario in `test-cases.md` is backed by an
    implemented test — either automated (named in the scenario) or
    explicitly tagged *manual* with a one-line note on how it's
    verified.  A scenario without an implementation is a TODO, not
    a shipped behaviour.
-   [ ] Metrics for all applicable axes are emitted.
-   [ ] Metrics catalog in `metrics.md` lists names + thresholds +
    dashboards.
-   [ ] Baseline values are recorded in the ticket (frozen-in-time,
    so they live there, not in the repo).
-   [ ] Deployment plan was followed; rollback strategy is
    documented in the ticket.
-   [ ] *Concerns* checklist has no unresolved items.
-   [ ] A review date is on a calendar (T+30 / T+90).

Final folder state after shipping:

```
<TICKET-ID>-<slug>/
  README.md         — Overview, Why, Options considered, How it works, System interactions, Configuration
  feasibility.md    — verified load-bearing assumptions (frozen at planning time)
  test-cases.md     — updated with edge cases discovered during implementation
  metrics.md        — actual metric names, thresholds, dashboards
  runbook.md        — agent-friendly diagnostic steps
  (plan.md deleted)
```

## 6. Maintain

Three maintenance activities, each catching a different kind of
rot:

### Doc drift

Run the drift-detection script:

```bash
python /path/to/rita/scripts/check.py --root . --fail-after 90
```

The script walks `<root>/**/docs/features/*/README.md`, parses
the `Last reviewed:` line, and reports any doc whose linked code
files have been modified since the review date.  Exit 1 when any
doc is unreviewed for more than `--fail-after` days.

### Metric health

Periodically — at the *Review date* recorded at ship time (T+30
and T+90 by default), or whenever the doc is touched — re-read
`metrics.md` and check each metric against the production
dashboard.  Specifically:

-   Are the metrics still being emitted?  Instrumentation breaks
    silently after refactors; a metric that's gone flat or zero
    may mean the code path stopped firing, not that the feature
    is unused.
-   Are the *Thresholds* still right for current traffic?  A
    threshold tuned for launch-day baseline becomes wrong as load
    grows or shrinks.  Update the threshold; record the new
    baseline in the ticket.
-   Are the *Dashboard* links still working?  Dashboards get
    renamed, deleted, or moved between Grafana orgs.

### Runbook freshness

Re-run the runbook's *diagnostic* steps periodically (the
*remediation* steps are too risky to exercise outside a real
incident — diagnostic only).  Each `query_prometheus(...)` /
`query_loki_logs(...)` / `grep ...` command should still execute
without error and produce output of the expected shape, even if
the values are different.  A broken diagnostic step discovered at
2 AM during a real incident is the failure mode this prevents.

If a step has rotted (renamed metric, dropped log field, moved
config path), fix the runbook in the same change set as the code
change that caused the rot.

---

## Metric definition reference

The four axes every applicable feature should cover:

| Axis             | Question it answers              | Examples                                                  |
| ---------------- | -------------------------------- | --------------------------------------------------------- |
| **Usage**        | Is anyone using it?              | Request volume, feature-invocation count, active users    |
| **Errors**       | Does it work reliably?           | Exception rate by type, retry count, decode failures      |
| **Performance**  | Does it meet its SLOs?           | p50/p95 latency, queue depth, batch size                  |
| **Business**     | Did it move the needle?          | Conversion lift, incidents avoided, support tickets       |

For each metric in `metrics.md`, write down:

```
Name:        <app>.<feature>.<thing_measured>
Type:        counter | gauge | timing
Tags:        outcome=<...>, kind=<...>
Meaning:     One sentence on what causes this metric to move.
Dashboard:   <link>
Threshold:   What value triggers a manual look / an alert.
```

## Observability MCP config

To run runbook diagnostic steps directly, an observability MCP
server should be configured in your agent's MCP settings.  Example
for Claude Code:

```json
{
  "mcpServers": {
    "observability": {
      "url": "https://your-mcp-server.example.com/sse"
    }
  }
}
```

Then runbook steps written like
`query_prometheus("sum(rate(feature_x_outcome{outcome='success'}[5m]))")`
become executable by the agent.
