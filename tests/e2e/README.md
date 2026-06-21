# End-to-end tests

These exercise Rita's real entry points against a real git repo: the
`rita-plan` skill through `claude`, and `scripts/drift_check.py` through its
CLI. (They're not "smoke" tests — they run the full workflow, not a quick
boot check. Narrower function-level tests would live in `tests/unit/`.)

Two tests, split by what they cover and whether they cost API budget:

| Test | Covers | Model? | Deterministic? |
|---|---|---|---|
| `test_drift.sh`          | drift detection (`scripts/drift_check.py`)        | no  | yes |
| `test_claude.sh`         | plan generation via the `rita-plan` skill | yes | generation isn't |

Both run in a temp dir, removed on exit unless you pass `--keep`, and
never touch this repo's own git history. Both trace their mechanical
steps (`cp`, `git`, install) via `set -x`.

## `test_drift.sh` — drift detection (offline)

Builds a self-contained throwaway git repo — a tiny feature doc that
links a one-line code file — commits with controlled dates, and asserts
`scripts/drift_check.py`:

1. reports `OK` (exit 0) when the doc was reviewed after the code's last
   change, then
2. reports `STALE` once the code is committed *after* the review date —
   exit 1 under `--fail-after 0`, exit 0 under a generous threshold.

It also sanity-checks that the committed worked example parses clean (a
plan with no linked code → drift_check.py reports OK). Fully deterministic
(dates pinned in the past); no API calls.

```bash
tests/e2e/test_drift.sh                # run the assertions
tests/e2e/test_drift.sh --show-output  # also print drift_check.py output
tests/e2e/test_drift.sh --keep         # leave the temp repo for inspection
```

## `test_claude.sh` — plan generation (calls the model)

Stands up a throwaway git repo with just the worked-example ticket
(copied from `examples/search-rate-limit/TICKET.md`; no pre-existing code
— a plan precedes the implementation), installs the *current* `rita-plan`
skill into it under a
**random per-run prefix** (project-scoped, via `install-claude-skills.sh
--prefix`), and drives `claude -p` to plan the feature by **invoking that
skill natively** (`/<prefix>rita-plan …`, with `--setting-sources
project`). The prefix guarantees the skill we just installed is the one
that runs — a same-named user-level skill can't shadow it (user skills
take precedence over project ones). The prompt it sends is printed to
stdout. Asserts the feature folder is created and the README carries a
review date; doc-set completeness is reported by the scorecard step
rather than hand-checked here.

The model's narration and tool calls stream to stderr as it works (via
`progress.py`), so the multi-minute run isn't a silent wait. **Plan
generation usage** prints first; then the scorecard step runs and prints
its own **scoring usage** — the two blocks are labelled so they're not
confused. Pass `--no-rank` to skip scoring.

The scorecard is also a **gate**: the test fails unless the rita-review
percentage exceeds `MIN_PCT` (default 80). This turns a too-weak
generated plan into a red test rather than a number you have to eyeball.
`--no-rank` skips the gate.

Pick the generation model with `--model` to **compare how each executes
the skill** on the same ticket, and the scoring model with
`--gate-model` — setting it *different* from `--model` de-biases the
score (the judge isn't grading its own family). `--help` lists the
choices.

```bash
tests/e2e/test_claude.sh                              # generate + score with Sonnet
tests/e2e/test_claude.sh --model opus                 # generate with Opus
tests/e2e/test_claude.sh --model sonnet --gate-model opus  # cheap gen, strong judge
tests/e2e/test_claude.sh --keep --no-rank             # keep repo, skip scoring
```

| Flag / env | Default | Purpose |
|---|---|---|
| `--model NAME` (or `MODEL`) | `sonnet` | Generation model: `sonnet`, `opus`, `haiku`, or any full id. |
| `--gate-model NAME` (or `GATE_MODEL`) | `sonnet` | Scoring model; set it different from `--model` to de-bias. |
| `BUDGET` | `5.00` | Hard USD cap on the call (`--max-budget-usd`). |
| `MIN_PCT` | `80` | Score gate: the rita-review percentage must exceed this, else the test fails. |

Requires `claude`, `python3`, Git, and working Claude Code auth. A
typical Sonnet run is ~25–30 turns, a few minutes, under $1.

`progress.py` (live stream-json → readable stderr) and `stream_json.py`
(pull the result text / usage from the stream-json log) are standalone
Python helpers — no `jq` needed — that any other harness can reuse.

## `rank_plan.sh` — quality scorecard (runs the `rita-review` skill)

Runs the **`rita-review` skill natively** over a feature folder and relays
its scorecard (scored table + total + letter grade + top improvements) to
stdout. It installs the current `rita-review` skill under a random per-run
prefix and invokes `/<prefix>rita-review <dir>` — so it exercises the real
skill (same code path as `/rita-review` in an interactive session), not a
re-implemented rubric. Reusable standalone — point it at any feature
folder to compare quality across models or against the checked-in
reference.

```bash
tests/e2e/rank_plan.sh examples/search-rate-limit/docs/features/RITA-1-rate-limit-search
# → ┌─ Rita plan scorecard … TOTAL 36/40 (90%) grade A
```

| Env var | Default | Purpose |
|---|---|---|
| `GATE_MODEL` | `sonnet` | Model the skill runs under. |
| `BUDGET`      | `2.00`   | Hard USD cap on the call. |

The score is informational (a comparison signal), not a pass/fail gate.
The interactive equivalent is just invoking the **`rita-review`** skill in
a session — same skill, same rubric.

## `run_hermetic.sh` — hermetic isolation primitive

A wrapper that runs `claude -p` with the host's user-level state stripped:
no installed skills (`~/.claude/skills/`), no auto-memory, no
`settings.json`, no plugins, no configured MCP — **only** auth. It points
`CLAUDE_CONFIG_DIR` at a fresh temp dir holding just a copy of
`.credentials.json`, and runs from a neutral cwd so no project-level
`.claude/` leaks either.

```bash
tests/e2e/run_hermetic.sh --model sonnet "your prompt here"
tests/e2e/run_hermetic.sh --cwd /path/to/workdir --output-format json "…"
```

Why it exists: a normal subagent — and even `claude -p` with the default
config dir — *inherits* the user's installed skills. So a "no-skill"
baseline can silently auto-load an installed Rita skill and behave as if
it had it, which quietly invalidates any A/B comparison. `run_hermetic.sh`
is the clean-baseline runner for evals, and the building block for making
the smoke test below fully hermetic.

Known residual: it isolates *discovery/auto-load*, not the filesystem — a
run can still read a checked-out repo if it goes looking. Full isolation
needs a sandbox/container without repo access. (Do **not** add `--bare`:
it also skips credential loading → "Not logged in".)

> Note: `test_claude.sh` currently isolates *settings* only
> (`--setting-sources project` + a prefixed project-scoped install), so a
> user-level skill can't shadow the one under test — but it still inherits
> user memory/MCP from the default config dir. Routing it through
> `run_hermetic.sh` (credentials-only `CLAUDE_CONFIG_DIR`) is the next
> step to make it fully hermetic.

## The worked example (`examples/search-rate-limit/`)

The reference plan for the RITA-1 feature — generated once with the
skill, reviewed, and committed (whereas `test_claude.sh`'s output is
throwaway). It's a **plan**: a ticket plus the six docs, with no
implementation (the limiter is the plan's output, not its input).
`test_drift.sh` sanity-checks it parses clean. Also serves as:

- **Demo** — a complete Rita doc set with real, executed (self-contained)
  feasibility commands.
- **Model/agent eval** — `TICKET.md` is the raw input (the same file the
  generation test copies); diff a model's generated folder against this
  reference to compare quality.

Run `tests/e2e/test_drift.sh --show-output` to see sample `drift_check.py`
output (clean, then drift).
