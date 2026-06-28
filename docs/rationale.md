# Why Rita is shaped this way

The case for the design, one decision at a time.  For what to
actually do, see [`how-to.md`](how-to.md); for the lifecycle
diagram and opt-out criteria, see [`framework.md`](framework.md);
for the philosophical stance Rita is built on, see the
[Philosophy](../README.md#philosophy) section in `README.md`.

## Why "each fact lives in one file"

Documentation rots when the same fact is written in two places.
Six months later, one copy gets updated and the other doesn't,
and now the doc set is internally inconsistent.  The reader can't
tell which copy is current, and the next person who edits
discovers the conflict the hard way.

Rita's six files have non-overlapping responsibilities by
design.  The lookup table in `how-to.md` says exactly which file
owns each kind of information.  If a paragraph would naturally
fit in two files, one of those files is wrong; pick the right
home and link from the other.

Common drift sources to watch for:

- "Why this approach" rationale repeated in `README.md` and
  `plan.md` (it belongs in `plan.md` while ephemeral, in
  `README.md` after ship).
- Operational steps duplicated between `README.md` and
  `runbook.md` (operational stuff is `runbook.md`-only).
- Metric explanations duplicated between feature docs and
  `metrics.md` (centralise in `metrics.md`).

## Why feasibility check

The feasibility check exists because plans die at the assumption
layer more often than they die anywhere else.  Two days of plan
writing — Concerns, Implementation steps, Rollback strategy,
Deployment plan — can be invalidated by minutes of verification
that the load-bearing approach actually works.  The asymmetric
cost is the whole point: spend those minutes first.

### Why this matters more with AI agents

The risk sharpens when an AI agent drafts the plan.  Agents
fabricate plausible-sounding assumptions confidently — "Postgres
16's new index method supports this column type", "Redis 7's
`FUNCTION` command is available", "the S3 SDK exposes a
`max-keys` value that high", "the JSON serialiser preserves
field ordering."  Each of those *might* be true.  Some are.
Some are training-data artefacts that no longer hold against
your specific version, your specific config, your specific
production environment.

Plausible-sounding fabrications survive plan review because
reviewers can't easily tell which assertions the agent
*verified* and which it *inferred*.  The feasibility check
makes that distinction structural: every load-bearing claim has
a *Command* and an *Observed exit*.  Nothing slips through as
"the agent said so."

**Worked example of the failure mode.**  An agent drafts a
400-line plan for a feature using PostgreSQL 16's new
`brin_minmax_multi_ops` operator class.  It writes the
migration, the rollback, the deployment plan, the monitoring
queries — all internally consistent, all confidently asserted.
Day three of implementation, someone tries the actual
`CREATE INDEX` against the production database and discovers it
runs PostgreSQL 13, where the operator class doesn't exist.
The plan is dead at the assumption layer.  Three days of work,
zero shipped.

The feasibility check would have caught it before any of the plan
was written:

```
- **Command:** `psql -d testdb -c "CREATE INDEX foo_test ON items USING brin (col) WITH (op_class=brin_minmax_multi_ops);"`
- **Expected exit:** 0
- **Observed exit:** 1
- **Observed output:**
  ```
  ERROR:  operator class "brin_minmax_multi_ops" does not exist for access method "brin"
  ```
```

The plan halts at section 2 — the "Implementation steps,
Concerns, Rollback strategy" 400 lines never get written, and
the agent goes back to *Options considered* to pick a different
approach.

This pattern — confident hallucination, plausible specifics,
survives review until implementation tries it — is the load-
bearing reason agents and feasibility-by-design belong together.
Hand-written plans had it too, but humans tend to hedge with
"we should check that this works"; agents don't, by default.
The format makes the check non-optional.

The same instinct has a failure mode worth naming: a feasibility
check is only worth writing when the outcome is genuinely
*uncertain* — typically because it depends on something external
(a version's behaviour, an API, a platform, real data, a service
you don't own).  When a feature is self-contained and built on
well-understood in-house mechanics, agents (being eager to look
rigorous) tend to *prototype the implementation and unit-test it*,
then file that as feasibility.  Those blocks verify nothing anyone
was unsure of — "a token bucket enforces its limit", "a lock
prevents lost updates" — and they duplicate what `test-cases.md`
will cover once the code exists.  The discipline is to verify
uncertainty, not to re-prove textbook code: if checking an
assumption means writing the very code the plan will ship, it's a
test, and a feature with no real external unknown is allowed an
almost-empty feasibility section.  Padding it with prototype-tests
is the confident-rigour analogue of confident hallucination.

### Why feasibility lives in its own file

Verifications are a distinct kind of content from the rest of the
plan: structured records of "I ran this command and observed this
exit code at this time."  They're not narrative; they're not
implementation logistics; they don't get deleted at ship time
because they're load-bearing evidence the team needed *at planning
time*, and future readers (or modifiers of the feature) need to
know what was verified and under what env.

Keeping them in their own file (`feasibility.md`) makes three
things cleaner:

1.  The file has a single purpose — a structured record of
    verifications.  Reviewers can audit it at a glance; lightweight
    tooling (regex parsing of the labelled bullets) can extract the
    blocks for re-invocation in CI when the user has a comparable
    environment.  "Re-execute every block automatically" is harder
    than it sounds — commands typically need credentials, network
    access, or the recorded distro/kernel to mean anything — but
    the parseable format keeps that option open for teams that can
    set up the environment.
2.  The feasibility evidence survives `plan.md`'s deletion at ship
    time.
3.  The `plan.md` scratch space stays narrowly focused on
    implementation logistics, not mixed with structured
    verification records.

### Falsifiability by design

A verification that can't fail is not a verification.  The
*Failure-mode* line in each feasibility block is the
falsifiability anchor: a **pre-commitment** that says "if this
assumption were false, you would observe X."  If the author
can't write a *Failure-mode* that the *Command* would actually
exhibit, the verification is hollow — the command would pass
regardless of whether the assumption holds — and the reviewer
rejects it.

This is borrowed from property-based testing's stance: the
useful question isn't "did the test pass," it's "would the test
fail in the conditions the test is supposed to detect."  Same
move, applied to plan assumptions.

### Why "before the rest of the plan"

*Concerns*, *Implementation steps*, *Rollback strategy*, and
*Deployment plan* are all downstream of "the approach works."
Writing them before verifying the load-bearing assumption is
sunk cost if the approach turns out to be infeasible.  Verifying
first — even when the verification takes real effort — saves the
days of plan writing that would otherwise be wasted.

This is also the place where the framework leans hardest on the
philosophy: *detection over prevention*.  You can't prevent your
assumption from being wrong, but you can structure the work so
that wrongness is detected at the cheapest possible point.

### Why proxy-gap matters

Some load-bearing assumptions are genuinely expensive to verify
ahead of time — production data shape, scale-dependent
behaviour, customer-specific environments.  The escape hatch is
the *Proxy-gap* line: record what you *can* check (a stage
bucket, a synthetic dataset), and explicitly note what the proxy
doesn't cover.

The proxy-gap is itself load-bearing by implication.  If the gap
turns out to matter, the plan was approved on insufficient
evidence — and the failure that follows is on the reviewers, not
on the author, because the gap was visible.  This is *honesty
about epistemic limits*, not hand-waving.  Reviewers must read
proxy-gap entries with the same weight as a fully-verified
assumption.

## Drafting pitfalls

These are lessons from past plan reviews.  They apply equally to
humans and agents drafting the first pass.  The compact
operational list lives in
[`how-to.md#drafting-rules`](how-to.md#drafting-rules) — read
that while you work; come here for the *why* behind each rule.

-   **Ground every API/schema proposal in the closest existing
    precedent.**  The cost this avoids is *unintentional*
    divergence — deliberate divergence is fine, but the kind you
    didn't notice is rework, and a named precedent gives the
    reviewer a concrete thing to compare against.  (Operational
    form in [`how-to.md#drafting-rules`](how-to.md#drafting-rules).)

-   **Enumerate states around any precondition.**  Why it's a rule
    and not an instinct: the obvious state usually has an
    equally-valid twin that's easy to miss — "enabled only in test"
    and "disabled in all feeds" both describe a release that never
    progressed, and a plan that handles only the first silently
    drops the second.  (The rule is in
    [`how-to.md#drafting-rules`](how-to.md#drafting-rules).)

-   **Treat external services as hard scope boundaries.**  A plan
    that pulls another service's change set into its own
    implementation steps can no longer be estimated, reviewed, or
    shipped on its own — that's the cost the boundary buys back.
    (Operational form in
    [`how-to.md#drafting-rules`](how-to.md#drafting-rules).)

-   **For every data consumer, ask both "hide" and "keep
    visible".**  The trap is asymmetry: downstream tooling (batch
    jobs, reporting services, UI clients) often needs the opposite
    of what the request-path API needs, so a visibility change
    that's correct for one breaks the other unless both sides are
    named.  (The rule is in
    [`how-to.md#drafting-rules`](how-to.md#drafting-rules).)

-   **Don't add a feature flag by reflex.**  Ship directly when
    the change is admin-only, has no client-facing behaviour, and
    is easy to revert.  Feature flags exist to manage risk, and
    they cost ongoing complexity — use them where risk is real,
    not as cargo-culted ceremony.

-   **Merge test cases that share a Given.**  Multiple scenarios
    with identical preconditions but different When/Then branches
    should be one case with bulleted When/Then lists, not several
    cases with duplicated Given lines.  Duplication hides that
    the preconditions are the same and inflates the file.
    Example:

    ```
    **Given** an item marked `archived=true`,
    - **when** `GET /items` is requested, **then** the item does
      not appear;
    - **when** `GET /admin/items` is requested, **then** the item
      DOES still appear (admin tooling depends on it);
    - **when** `GET /items/<id>` is requested directly, **then**
      the response includes the `archived` flag.
    ```

-   **Make Definition-of-Done items verifiable from the doc
    alone.**  Naming the artifact is what lets a reviewer at T+30
    walk the list without reopening the MR to find out what was
    meant — the rule and its artifact list are in
    [`how-to.md#drafting-rules`](how-to.md#drafting-rules).  The
    contrast makes the point:

    Bad:
    ```
    - [ ] DB migration added and tested
    - [ ] Admin UI button
    - [ ] Audit event shown on history tab
    ```

    Good:
    ```
    - [ ] `items.status` column added via DB migration
    - [ ] "Archive" button on `/admin/items/<id>`
      (shown only when precondition holds)
    - [ ] Audit event visible on the item detail page's
      History tab
    ```

## Writing style

**"How it works" should be architecture-level.**  Describe the
flow in terms of HTTP endpoints, databases, replication, caching
layers, and system boundaries — not function names, line numbers,
or internal variable names.  A reader should understand what
talks to what and where data lives without opening the source
code.  Use a diagram when the flow has more than 3 steps.  Save
implementation details for the code and its docstrings.

**Test cases use BDD-style Given/When/Then format.**  This forces
clarity about preconditions, actions, and expected outcomes.
Focus on observable behaviour from the user's or operator's
perspective:

```
**Given** an item marked as `needs_review`
**and** no reviewer is assigned,
**when** the item appears in the default list,
**then** the response includes a `pending_review` flag.
```

You don't need BDD tooling (Cucumber, etc.) — just the writing
convention.

## Why evergreen vs ephemeral

The plan document and the feature doc serve different audiences.
The plan exists for *the person deciding whether to do the work
and how*.  The feature doc exists for *everyone afterwards —
on-call engineers at 2 AM, new hires reading the code, the future
you who forgot the context*.

Implementation step sequence, dependencies on other teams,
launch-day baselines — these are load-bearing *during* the work
and useless *after*.  Keeping them in the doc forever turns the
feature doc into archaeology; deleting them at ship time keeps it
readable.

But three things that look ephemeral at first actually need to
survive:

-   **Options considered + preferred solution.**  A future reader
    looking at the shipped feature will eventually ask "why this
    shape, not something else?" — and that question is much
    easier to answer when the alternatives are written down next
    to the chosen approach.  These live in `README.md` from the
    start, not in `plan.md`.
-   **Feasibility verifications.**  The record of "we checked
    that X was true, here's the command, here's what we observed"
    is load-bearing evidence if anyone later modifies the feature
    and needs to know what was verified.  Lives in
    `feasibility.md`, which survives `plan.md`'s deletion.
-   **Rollback strategy.**  If the feature breaks down the line,
    the original rollback plan is a useful starting point — even
    if details have drifted.  But the *planning-day* version
    with its specific flag values and monitoring choices is
    ephemeral; the *general approach* (flag flip vs revert vs
    migration rollback) belongs in the ticket and/or as a short
    note in `runbook.md`.

The git history preserves `plan.md` if anyone ever needs the
original implementation logistics.  Nobody usually does.  And in
the rare case they do, `git log -- path/to/plan.md` finds it
instantly.

## Agent-assisted workflows

The plan template, feature docs, and runbooks are structured so
that AI agents can participate at every phase — not autonomously,
but as force multipliers where a human stays in the loop for
judgment calls.

### Plan drafting

Ask the agent to fill out the plan template for a given ticket.
The agent reads the codebase, fills in what it can derive from
code and docs, and marks what it can't with `needs human input`
rather than guessing.

After producing the first draft, the agent should **proactively
ask clarifying questions** — not wait for the human to discover
gaps.  The agent has just read the codebase and the plan
template; it knows which decisions require judgment, which
assumptions need validation, and where cross-component
interactions create ambiguity.  Surfacing these as explicit
questions (with options and trade-offs when possible) is more
productive than leaving `:warning:` markers for the human to
stumble upon during review.

Good clarifying questions are:
-   Scoped ("should X appear in Y?" not "what should we do?")
-   Informed (show what the agent found and what the options are)
-   Grouped (ask all questions at once so the human can answer
    in a single pass)

This solves the blank-page problem — the agent produces a
complete first draft in minutes, then drives the conversation
toward the decisions that matter.  The human spends their time
on judgment calls (options trade-offs, political constraints,
historical context) rather than mechanical assembly or hunting
for gaps.

### Guided implementation

Once the plan is approved, the developer brings it into the
implementation session — either by continuing the planning
agent into the implementation phase, or by handing the approved
plan to a fresh agent session as context ("implement step 3 of
this plan").  The approved plan constrains the agent — it won't
wander into a different approach because the approach is
written down.  The concerns checklist and impact analysis tell
it what to watch for (thread safety, replication, coordinated
changes, etc.).

### Incident triage

When something goes wrong, the on-call engineer hands the agent
the feature's runbook along with the observed symptom.  With a
metrics/logs MCP server
(e.g. [Grafana MCP](https://github.com/grafana/mcp-grafana))
connected, the agent can execute every diagnostic step
autonomously — querying Prometheus for metric rates, searching
Loki for errors, grepping config files — and report back:
"here's what I checked, here's what I found, here are the
likely causes ranked by evidence."  The on-call engineer
decides what to do.

### Proactive monitoring

An agent running on a schedule can periodically check key
metrics defined in the feature's `metrics.md` and alert (via
chat, issue tracker, etc.) when thresholds are breached.  The
runbook defines what to check and what values are normal — the
agent follows it.

### What agents can't do

-   **"Options considered"** requires judgment the agent doesn't
    have — it doesn't know the team's real constraints.  Treat
    agent-generated options as a starting point.
-   **Impact analysis** requires institutional knowledge that
    isn't in the code — frozen customer versions, ongoing
    migrations, ops team capacity.  Always review agent-filled
    impact items.
-   **Remediation** (flipping flags, rolling back releases)
    should require human approval.  An agent that can diagnose
    and also act could fix a problem or make it worse — the
    runbook should distinguish diagnostic steps (agent-safe)
    from remediation steps (human-approved).
-   **Plan review** is inherently human.

> **Convention for agent-drafted plans:** when an agent fills out
> the plan template, any item it cannot confidently assess from
> the codebase alone must be marked with a warning marker and a
> short note explaining what information is missing.  Example:
>
> ```
> - **Security** — :warning: needs human input: this touches the
>   auth middleware but I can't determine whether the new header
>   is exposed to untrusted clients.  Check with the team.
> ```
>
> This tells the human reviewer exactly where to focus instead of
> re-reading the entire plan looking for plausible-sounding
> guesses.

## Writing agent-friendly runbooks

Operational runbooks should be usable not just by humans but
also by AI agents investigating an incident or helping with
on-call triage.  A human reads "check the request-rate metrics"
and knows to open the dashboard.  An agent doesn't — it needs
concrete commands, observable outputs, and explicit decision
criteria.

Guidelines:

-   **Concrete commands over vague verbs.**  Instead of "check
    setting X", write the actual command:
    `grep FEATURE_X_ENABLED app/config.py`.  Instead of
    "look at metrics", give a query or a dashboard URL.
-   **Expected output.**  After each command, describe what
    success and failure look like: "should print `True`; if
    `False` or missing, this is the problem."
-   **Decision criteria, not judgment calls.**  Instead of "if
    the rate is high", write "if the rate exceeds 100/min" or
    "if it dominates (>90% of total)".  An agent can evaluate a
    threshold; it can't evaluate "high".
-   **One symptom per section.**  Start each runbook entry with
    a symptom the agent can match against a problem description
    ("Symptom: feature_x not activating for any requests"), then
    list diagnostic steps in order.
-   **File paths and config keys.**  Reference exact file paths
    (`app/config.py:42`), exact config key names, exact metric
    names with tags.  Agents can grep and query; they can't
    guess.
-   **Link to dashboards and tools.**  If an MCP tool, CLI
    command, or dashboard can answer the question, link it.
    The agent can follow the link; it can't discover tools on
    its own.

Worked runbook example using an observability MCP:

```markdown
### Symptom: feature_x success rate dropped below threshold

1. Query Prometheus for the success counter:
   `query_prometheus("sum(rate(feature_x_outcome{outcome='success'}[5m]))")`
   Expected: >0 if the feature is in use.  0 means either
   no traffic or the feature is broken.

2. Check for recent config changes:
   `query_loki_logs("{app=\"my-app\"} |= \"feature_x.enabled changed\"")`
```

**Logs as a diagnostic tool.**  Application logs are a primary
troubleshooting source — they carry request context, error
tracebacks, and timing that metrics alone can't provide.  When
writing runbooks, include the log patterns to search for (logger
name, log level, key phrases) so an agent can construct a query:

```markdown
3. Search for feature_x errors in the last hour:
   `query_loki_logs("{app=\"my-app\"} |= \"feature_x_handler\" |= \"ERROR\"")`
   Expected: empty.  Any results indicate a downstream
   failure in the feature_x path.
```

The goal is not to make every runbook a script — some steps
genuinely require human judgment (calling a customer, deciding
whether to wake up on-call).  But every *diagnostic* step should
be executable by an agent, so that by the time a human gets
involved, the agent has already narrowed the problem.

## Metrics vs. logs: pick the right tool

For **rare, discrete events** (admin toggles, manual
interventions, config changes), a log entry is usually a better
record than a counter.  Log entries carry actor, target,
timestamp, and context; counters carry only a count.  Reach for
logs when the question you'll ask later is "who changed X,
when?" rather than "how often does X happen?".

For **high-volume request-path events**, counters are the right
answer — emitting a log line per request adds load and noise
that counters avoid.

If logs are the right answer but the log surface is hard to
query (e.g. no filters by event type, no index on the field you
need), fix the log surface rather than working around it with
extra metrics.  Treat that as a separate work item, not a reason
to instrument twice.

## Use your project's existing helpers

If your project already has metrics helpers (a `@measured`
decorator, a statsd client, an OpenTelemetry wrapper), use them
rather than inventing parallel infrastructure.  The point is
consistency across the codebase — the metric *names* and tag
*shapes* matter more than which library emits them.

## Maintenance

-   When you touch a feature in code, update its doc in the same
    change set — refresh `Last reviewed:` and re-confirm the
    metrics catalog matches the code.
-   Periodically (annually, or alongside a related code change),
    re-read the doc and trim anything that has gone stale.
-   When a feature is removed, delete the doc — don't leave a
    tombstone.  Removal is captured in `git log`.
-   When a feature is significantly reshaped, treat it as a new
    feature: new plan, new review.

The intent of automated rot detection (`scripts/drift_check.py`) is
**soft pressure, not blocking enforcement** — a stale doc is
rarely an incident, but a year of drift is.

## What this is *not*

-   Not a replacement for code comments.  In-doc explanation
    should cover *system shape*, not individual function
    behaviour — that belongs in docstrings.
-   Not a replacement for runbooks/playbooks for incidents.
    Those can live in the same file under "Operational runbook"
    or link out to a separate page if they grow large.
-   Not a replacement for ticket-tracking workflow.  The plan
    document captures *what* and *how*; the ticket tracks *who*,
    *when*, and *status*.
