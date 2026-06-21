---
name: rita-delta
description: Audit a Rita feature folder (docs/features/<id>/) against the code for the doc↔code delta — mechanical drift (drift_check.py), doc↔code inconsistencies and gaps, unresolved open questions, and stalled status — then propose fix options (change the code, or change the doc) for the user to choose. Read-only: detects and proposes, never mutates. Use when asked to check drift, audit, or verify a feature folder is still accurate against the implementation.
---

# Rita: delta — audit a feature folder against the code

Where `rita-review` asks *"is this a good plan?"* (plan-time, the docs
read against themselves), `rita-delta` asks *"is this doc set still
true?"* (implementation- and maintenance-time, the docs read against the
**code**). It is the agent half of the framework's *Maintain* phase
(`docs/how-to.md` §6 in the Rita repo), and it also runs
mid-implementation to catch the plan and the code diverging before ship.

The two reviewer skills divide along one axis:

- `rita-review` → **internal** consistency (doc↔doc) + quality. No code.
- `rita-delta` → **external** consistency (doc↔code) + hygiene. Code is
  the source of truth to compare against.

**This skill detects and proposes. It never mutates** — not the docs, not
the code. When a doc and the code disagree, *either* could be the one
that's wrong, so it surfaces both fix directions and lets the human
decide. Applying a doc fix is `rita-plan`'s job; applying a code fix is
normal dev work.

## What to do

### 0. Find the target and pick the mode

A path may be given (e.g. `/rita-delta path/to/feature`); otherwise the
user names it. It's a directory with `README.md` and usually
`feasibility.md`, `test-cases.md`, `metrics.md`, `runbook.md`, and —
before ship — `plan.md`. If there's no `README.md`, it isn't a Rita
feature folder: say so and stop. Note the enclosing project / git root.

Read `README.md`'s frontmatter (`Status:`, `Last reviewed:`) and check
whether `plan.md` exists. That fixes the **mode** — both modes audit the
docs against the code; they differ only in *which* docs carry the intent:

- **Pre-ship** (`Status: Plan`/`Implementation`, `plan.md` present) —
  `plan.md`'s *Implementation steps* + *Definition of done* are the
  primary statement of intent, alongside the evergreen sections. Best
  question: *did we build what the plan said?*
- **Post-ship** (`Status: Shipped`, `plan.md` deleted per the §5 DoD) —
  `plan.md` is gone, so the evergreen docs carry all the intent: README
  *How it works* / *System interactions* / *Configuration*, plus
  `metrics.md`, `runbook.md`, `test-cases.md`. Best question: *do the
  docs still describe the code that's there now?*

State the mode you detected in the report header.

### 1. Mechanical pass — the cheap, deterministic pre-filter

Run the bundled detector against the project root with `--refs`
(`drift_check.py` sits in this skill's directory):

```
python3 <this-skill-dir>/drift_check.py --root <project-root> --refs
```

It does two deterministic passes that triage the expensive read below:

- **Date drift** — `STALE` lines name a doc and the linked code file that
  has a newer commit than the doc's `Last reviewed:` date. Read those
  paths first.
- **Referential integrity** (`--refs`) — `REFS` lines name documented
  identifiers (backticked metric names, env vars, `FEATURE_*`/`KILL_*`
  flags) that don't appear anywhere in the tree outside the feature docs.
  These are **candidates, not confirmed gaps**: an identifier can be
  assembled at runtime (a metric name built from a prefix, a flag read
  through a constant) and so be real yet unfindable by literal search.
  Confirm each against the code in step 2 before reporting it — see the
  false-positive note there.

`OK`/no `REFS` lines don't mean "no drift": the doc may link nothing,
claims can rot without the linked file changing, and prose-level
divergence is invisible to both passes. They mean the mechanical
heuristics found nothing — the semantic pass still runs. If the folder
isn't in a git repo, both passes degrade (no commit dates; identifier
search falls back to a file walk) — note it and lean harder on step 2.

The mechanical pass *narrows* the read; it doesn't replace it.

### 2. Doc↔code consistency and gaps — the semantic pass

Start from step 1's output — the `STALE` paths and the `REFS` candidates
— then read the doc set against the actual code and find where they
disagree. Gaps run **both directions**:

- **Doc claims, code lacks** — a `metrics.md` metric with no emission
  site; a `test-cases.md` scenario with no implemented test; a README
  *Configuration* env var the code never reads; a `runbook.md` diagnostic
  referencing a renamed metric/log field/path; a `plan.md` *Implementation
  step* or *Definition of done* item not present in the code (pre-ship).
  The `--refs` pass already surfaced the mechanically-findable subset of
  these; **adjudicate each candidate** rather than passing it through.
- **Code does, doc omits** — behaviour, a config knob, an endpoint, or an
  error path the code has that no doc mentions. Undocumented behaviour is
  drift too. (The mechanical pass cannot see this direction at all — it's
  yours to find.)
- **Both disagree on specifics** — doc says limit 100/min, code uses 60;
  a flag named `FEATURE_X` in the doc, `FLAG_X` in code; a threshold in
  `metrics.md` that doesn't match the alert in code.

Ground every finding in `file:line` (the doc location) and a code
`path:line` (or its absence). A finding you can't point to is a guess;
drop it.

**Rule out indirection before declaring a "code lacks" gap.** Literal
search misses identifiers the code builds at runtime — a metric name
concatenated from a prefix, an env var read via a settings object, a flag
behind a constant or an enum. Before you report a documented identifier
as missing, check for the *mechanism* that would produce it (a format
string, a `getattr`, a config loader, a registry). Only report it once
you've looked and it genuinely isn't there. A `REFS` candidate that turns
out to be runtime-assembled is **not** a finding — say so and move on.

### 3. Open questions

Grep the folder for unresolved `:warning: needs human input` markers (and
any `TODO`/`TBD` left in the docs). Each one still standing after ship —
or lingering through implementation — is an open gap. List them with
their one-line note; don't try to answer them (that's the human's call),
just surface that they're still open.

### 4. Status hygiene

Check the `Status:`/`Last reviewed:` frontmatter against reality:

- **Stalled in Plan** — `Status: Plan` but linked code already exists /
  has been committed: implementation started without advancing the
  status.
- **Stalled in Implementation** — `Status: Implementation` but
  `Last reviewed:` is long ago (≳30d) with the code merged: the doc
  never advanced to shipped, or stopped being maintained.
- **Stale review date** — `Last reviewed:` predates recent commits to
  linked code (this is what step 1 flags as `STALE`); restate it here as
  a hygiene item if the doc owner needs to re-review.
- **Ship-state mismatch** — `plan.md` still present while `Status:
  Shipped` (the §5 DoD deletes `plan.md` at ship), or the inverse:
  `Status: Shipped` but DoD checkboxes in a lingering `plan.md` are
  unchecked.

These are heuristics, not hard rules — report what you see and why it
looks stalled, don't fail a run over a date.

### 5. The delta report

Lead with a header box, then the findings. For **every** consistency and
status finding, give the user a choice of fix directions — that's the
point of the skill:

```
┌─ Rita delta report ─ <feature-dir>  [mode: pre-ship | post-ship]
│ status        Implementation · last reviewed 2026-04-02 (67d ago)
│ mechanical    2 docs STALE (drift_check.py)
│ consistency   3 doc↔code mismatches, 1 undocumented behaviour
│ open items    1 unresolved :warning:
│ hygiene       1 stalled-status flag
└─
```

Then each finding, grouped by category, most load-bearing first:

```
[consistency] metrics.md:14 — metric `search.ratelimit.rejected` is
  documented but never emitted (grep finds no call site in search/).
  Fix options:
    (A) code — emit the metric at the rejection path, search/limiter.py:88.
    (B) doc  — the code emits `search.rl.blocked`; rename it in metrics.md
               (and the runbook query at runbook.md:40) to match.
  → choose A or B.

[hygiene] README.md:2 — Status: Implementation, last reviewed 67d ago;
  search/limiter.py was committed 60d ago. Looks shipped-but-not-closed.
  Fix options:
    (A) advance Status to Shipped and run the §5 ship checklist (this
        deletes plan.md once its DoD is verified).
    (B) if still in flight, re-review and bump Last reviewed.
  → choose A or B.
```

For open-question items there's usually no A/B — surface the marker and
note it needs a human answer.

Close with a one-line verdict: the single most load-bearing divergence,
and whether the doc set is safe to trust as-is.

**A clean audit is the honest, good result — don't manufacture findings.**
If the docs and the code agree, say so plainly: report zero divergences
and a "doc set is in sync" verdict. The same way `feasibility.md` should
have no fabricated verifications, this report should have no invented
findings. A skill that always finds something teaches the reader to
ignore it. Report only divergences you can point to in both the doc and
the code (or its confirmed absence).

## Boundaries

- **Read-only — detect and propose, never mutate.** You do not edit the
  docs or the code. Applying a doc fix routes to `rita-plan`; applying a
  code fix is ordinary dev work the user drives.
- **Static inspection only.** You may run `drift_check.py` and read-only
  inspection (reading files, `grep`/`rg`, `git log`/`git blame`, `ls`).
  Do **not** run the feature's tests, run the app, or execute any
  `Command` from `feasibility.md` or `runbook.md` — those can have side
  effects and re-running them is the author's/operator's job, not the
  auditor's.
- **Don't pick a side for the user.** When doc and code disagree, the
  code is not automatically right — it may have drifted from a still-valid
  intent. Present both fix directions; the human decides which is the
  source of truth.
- **Point at everything.** Every finding cites a doc `file:line` and a
  code `path:line` (or names the absence you searched for). No
  unsubstantiated findings.
- **Don't audit non-Rita folders.** If it isn't a Rita feature folder
  (no `README.md`), say so instead of forcing a result.
