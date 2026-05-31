#!/usr/bin/env bash
#
# Rita end-to-end test: plan generation via the rita-plan skill.
#
# Stands up a throwaway git repo with just the worked-example ticket
# (no pre-existing code — a plan precedes the implementation), installs
# the *current* version of the rita-plan skill into it, and drives
# `claude -p` to plan the feature.  Asserts the feature folder is created
# and the doc set is complete (README, feasibility, plan, test-cases,
# metrics, runbook).
#
# Drift detection is a separate, offline test — see test_drift.sh.
#
# Pick the model with --model to compare how each one executes the skill
# on the same ticket — that's what turns this into a comparison harness.
#
# The model's narration and tool calls stream to stderr as it works.
#
# Usage:
#   tests/e2e/test_claude.sh [--model NAME] [--gate-model NAME] [--keep] [--no-rank] [--help]
#     --model NAME       generation model (default: sonnet) — see --help
#     --gate-model NAME  scoring model (default: sonnet); set it different
#                        from --model to de-bias the score
#     --keep             don't delete the temp repo on exit
#     --no-rank          skip the quality scorecard
#     --help             show this help (and the model choices) and exit
#
# Env vars:
#   MODEL       default generation model (default: sonnet)
#   GATE_MODEL  default scoring model (default: sonnet)
#   BUDGET      max USD for the call (default: 5.00; hard cap)
#   MIN_PCT     the rita-review percentage must exceed this, else the
#               test fails (default: 80; ignored with --no-rank)
#
# Exit 0 = generation produced a valid feature folder AND scored above
# MIN_PCT.  Exit 1 = failure.

set -euo pipefail

MODEL="${MODEL:-sonnet}"
GATE_MODEL="${GATE_MODEL:-sonnet}"
MIN_PCT="${MIN_PCT:-80}"
BUDGET="${BUDGET:-5.00}"
KEEP=0
RANK=1

print_help() {
  cat <<'EOF'
test_claude.sh — generate a Rita plan via the rita-plan skill, then
score it.  Runs headless `claude -p` in a throwaway git repo.

Usage:
  tests/e2e/test_claude.sh [--model NAME] [--gate-model NAME] [--keep] [--no-rank] [--help]
    --model NAME       generation model (default: sonnet)
    --gate-model NAME  scoring model (default: sonnet)
    --keep             don't delete the temp repo on exit
    --no-rank          skip the quality scorecard
    --help             show this help and exit

Model choices (--model / --gate-model):
  sonnet   claude-sonnet-4-6           (default — fast, capable)
  opus     claude-opus-4-8             (strongest; slower, pricier)
  haiku    claude-haiku-4-5-20251001   (cheapest; weakest at this task)
  <id>     any full Claude model id is also accepted

Env: MODEL, GATE_MODEL (defaults sonnet), BUDGET (max USD, default
     5.00), MIN_PCT (rita-review percent must exceed it; default 80).

Examples:
  tests/e2e/test_claude.sh                 # generate + score with Sonnet
  tests/e2e/test_claude.sh --model opus    # generate with Opus
  # de-bias: generate with the cheap model, judge with the strong one
  tests/e2e/test_claude.sh --model sonnet --gate-model opus
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)         MODEL="${2:?--model needs a value}"; shift 2 ;;
    --model=*)       MODEL="${1#*=}"; shift ;;
    --gate-model)   GATE_MODEL="${2:?--gate-model needs a value}"; shift 2 ;;
    --gate-model=*) GATE_MODEL="${1#*=}"; shift ;;
    --keep)    KEEP=1; shift ;;
    --no-rank) RANK=0; shift ;;
    --help|-h) print_help; exit 0 ;;
    *) echo "FAIL: unknown argument '$1' (try --help)" >&2; exit 1 ;;
  esac
done

command -v claude  >/dev/null || { echo "FAIL: claude CLI not found"  >&2; exit 1; }
command -v python3 >/dev/null || { echo "FAIL: python3 not found"     >&2; exit 1; }

START_TS=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$REPO_ROOT/install-claude-skills.sh"
EXAMPLE_DIR="$REPO_ROOT/examples/search-rate-limit"
PROGRESS_PY="$SCRIPT_DIR/progress.py"
STREAM_JSON="$SCRIPT_DIR/stream_json.py"
for required in "$INSTALLER" "$EXAMPLE_DIR/TICKET.md" "$PROGRESS_PY" "$STREAM_JSON"; do
  [[ -f "$required" ]] || { echo "FAIL: missing $required"; exit 1; }
done
# Per-run prefix so the skill we install is the exact one invoked — a
# same-named user-level skill can't shadow it (user skills take
# precedence over project ones).  No leading "rita-", to stay clear of
# the installer's stale-skill check.
PREFIX="e2e-${RANDOM}-"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rita-e2e-claude.XXXXXX")"
cleanup() {
  if [[ $KEEP -eq 1 ]]; then echo "kept temp repo: $WORK_DIR" >&2
  else rm -rf "$WORK_DIR"; fi
}
trap cleanup EXIT

# Trace the mechanical setup (cp, git, install) so it's clear what the
# harness does.  Suspended around the model stream further down.
PS4='+ '
set -x

# The ticket is the worked example's — copied, not duplicated inline.
# Only the ticket is seeded: the plan is generated from it, with no
# pre-existing implementation to ground against (a plan precedes code).
cp "$EXAMPLE_DIR/TICKET.md" "$WORK_DIR/TICKET.md"

cd "$WORK_DIR"
git init -q
git config user.email "test@rita.test"
git config user.name "Rita Test"
git config commit.gpgsign false
git add TICKET.md
git commit -q -m "RITA-1 ticket"

# Install the CURRENT skills under the per-run prefix, project-scoped, so
# the run invokes exactly this repo's version.
bash "$INSTALLER" --prefix "$PREFIX" "$WORK_DIR" >/dev/null

set +x

# --- the prompt: a native skill invocation -------------------------
# The skill is installed under a per-run prefix (hence the name); in real
# use you'd just type /rita-plan.
PROMPT="/${PREFIX}rita-plan Plan the feature in TICKET.md for the search
service. Work autonomously — don't ask me questions; note any assumptions
inline."

{
  echo "─── prompt sent to claude -p (skill prefixed for test isolation) ───"
  printf '%s\n' "$PROMPT"
  echo "────────────────────────────────────────────────────────────────────"
} # to stdout, on purpose — shows the native skill invocation

echo "─── generating with $MODEL (budget \$$BUDGET) — progress below ───" >&2

STREAM_FILE="$WORK_DIR/.claude-stream.jsonl"
CLAUDE_START_TS=$(date +%s)
set +e
claude -p "$PROMPT" \
  --model "$MODEL" \
  --setting-sources project \
  --permission-mode bypassPermissions \
  --verbose \
  --output-format stream-json \
  | tee "$STREAM_FILE" \
  | python3 "$PROGRESS_PY"
CLAUDE_RC=${PIPESTATUS[0]}
set -e
CLAUDE_ELAPSED=$(( $(date +%s) - CLAUDE_START_TS ))

# Both usage blocks are printed together at the very end (see below) —
# generation first, then scoring — so the run's costs read in one place.
print_gen_usage() {
  {
    printf '\n─── plan generation — usage ───────────────\n'
    python3 "$STREAM_JSON" "$STREAM_FILE" usage
    printf 'claude_call:     %d s\n' "$CLAUDE_ELAPSED"
    printf '───────────────────────────────────────────\n'
  } >&2
}

# On failure, surface the generation usage (the cost was already spent).
fail() { echo "FAIL: $1" >&2; print_gen_usage; exit 1; }
[[ $CLAUDE_RC -eq 0 ]] || fail "claude exited $CLAUDE_RC (budget? auth?)"

# --- assert the feature folder exists and is complete ----------------
set -x
README="$(find "$WORK_DIR" -path '*/docs/features/*/README.md' | head -n1)"
set +x
[[ -n "$README" && -f "$README" ]] || fail "no docs/features/*/README.md was generated"
FEATURE_DIR="$(dirname "$README")"
echo "PASS: feature folder created at ${FEATURE_DIR#"$WORK_DIR"/}" >&2

grep -qE '^>?[[:space:]]*Last reviewed:[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}' "$README" \
  || fail "README has no parseable 'Last reviewed:' date"
echo "PASS: README has a review date" >&2

echo >&2
echo "OK: plan generation produced a valid feature folder." >&2

# --- quality scorecard + score gate ----------------------------------
# rank_plan.sh runs the rita-review skill, which reports the completeness
# of the doc set (missing files score 0) — so the test doesn't hand-check
# each file; the scorecard surfaces gaps.  Its scorecard is captured (and
# still shown live) so we can gate on the total; its usage block goes to
# a file so we can print it after the generation usage, not mid-run.
SCORE_USAGE=""
SCORE_OUT=""
RANK_RC=0
if [[ $RANK -eq 1 ]]; then
  echo >&2
  SCORE_USAGE="$WORK_DIR/.score-usage"
  SCORE_OUT="$WORK_DIR/.score-out"
  set +e
  GATE_MODEL="$GATE_MODEL" "$SCRIPT_DIR/rank_plan.sh" "$FEATURE_DIR" --usage-file "$SCORE_USAGE" | tee "$SCORE_OUT"
  RANK_RC=${PIPESTATUS[0]}
  set -e
  [[ $RANK_RC -eq 0 ]] || echo "WARN: ranking failed (non-fatal)" >&2
fi

# --- usage, both blocks together at the end: generation, then scoring -
print_gen_usage
[[ -n "$SCORE_USAGE" && -f "$SCORE_USAGE" ]] && cat "$SCORE_USAGE" >&2

# --- score gate: the rita-review percentage must clear the floor -------
if [[ $RANK -eq 1 && $RANK_RC -eq 0 ]]; then
  pct="$(sed -n 's/^RANK .*pct=\([0-9]*\).*/\1/p' "$SCORE_OUT" | head -1)"
  total="$(sed -n 's/^RANK total=\([0-9]*\) .*/\1/p' "$SCORE_OUT" | head -1)"
  max="$(sed -n 's/^RANK total=[0-9]* max=\([0-9]*\).*/\1/p' "$SCORE_OUT" | head -1)"
  if [[ -z "$pct" ]]; then
    echo "WARN: could not parse a score from the rita-review output — gate skipped" >&2
  elif (( pct > MIN_PCT )); then
    echo "PASS: rita-review ${total}/${max:-40} = ${pct}% > ${MIN_PCT}%" >&2
  else
    echo "FAIL: rita-review ${total}/${max:-40} = ${pct}% is not > ${MIN_PCT}%" >&2
    exit 1
  fi
fi
