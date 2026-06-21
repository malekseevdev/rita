#!/usr/bin/env bash
#
# Rita plan-quality ranking — runs the rita-review skill (natively, via
# `claude -p`) over a feature folder and prints its scorecard.
#
# Native by design: it installs the *current* rita-review skill under a
# unique name prefix and invokes that exact skill, rather than
# re-implementing the rubric here.  The prefix guarantees the skill we
# just installed is the one that runs — a same-named user-level skill
# can't shadow it (user skills take precedence over project skills).
#
# Reusable standalone: point it at ANY Rita feature folder — a generated
# one, the checked-in reference under examples/, or a different model's
# output — to compare quality.  test_claude.sh calls it on the folder it
# generates.
#
# Usage:
#   tests/e2e/rank_plan.sh <feature-dir> [--keep] [--usage-file PATH]
#     <feature-dir>    directory containing README.md, feasibility.md, ...
#     --keep           don't delete the temp skill-env on exit
#     --usage-file P   write the usage block to P instead of stderr (lets a
#                      caller print it later, in its own order)
#
# Env vars:
#   GATE_MODEL   model for grading (default: sonnet)
#   BUDGET        max USD for the judge call (default: 2.00; hard cap)
#
# Exit 0 = a scorecard was produced (the score is informational, not a
# pass/fail gate).  Exit 1 = invocation error.

set -euo pipefail

command -v claude  >/dev/null || { echo "FAIL: claude CLI not found" >&2; exit 1; }
command -v python3 >/dev/null || { echo "FAIL: python3 not found"    >&2; exit 1; }

FEATURE_DIR=""
KEEP=0
USAGE_OUT="/dev/stderr"   # where the usage block goes; --usage-file redirects it
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)          KEEP=1; shift ;;
    --usage-file)    USAGE_OUT="${2:?--usage-file needs a value}"; shift 2 ;;
    --usage-file=*)  USAGE_OUT="${1#*=}"; shift ;;
    -*)              echo "FAIL: unknown argument '$1'" >&2; exit 1 ;;
    *)               FEATURE_DIR="$1"; shift ;;
  esac
done
[[ -n "$FEATURE_DIR" && -d "$FEATURE_DIR" ]] || { echo "usage: rank_plan.sh <feature-dir> [--keep] [--usage-file PATH]" >&2; exit 1; }
[[ -f "$FEATURE_DIR/README.md" ]] || { echo "FAIL: $FEATURE_DIR has no README.md" >&2; exit 1; }
FEATURE_DIR="$(cd "$FEATURE_DIR" && pwd)"   # absolute, for --add-dir

START_TS=$(date +%s)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$REPO_ROOT/install-claude-skills.sh"
PROGRESS_PY="$SCRIPT_DIR/progress.py"
STREAM_JSON="$SCRIPT_DIR/stream_json.py"
for required in "$INSTALLER" "$PROGRESS_PY" "$STREAM_JSON"; do
  [[ -f "$required" ]] || { echo "FAIL: missing $required" >&2; exit 1; }
done

GATE_MODEL="${GATE_MODEL:-sonnet}"
BUDGET="${BUDGET:-2.00}"
# Random per-run prefix so the skill we install is the exact one that
# runs — nothing user-level can shadow a name this unique.  (Avoid a
# leading "rita-" so it stays outside the installer's stale-skill check.)
PREFIX="e2e-${RANDOM}-"
SKILL="${PREFIX}rita-review"

# --- isolated skill env ----------------------------------------------
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rita-rank.XXXXXX")"
# Hermetic isolation: strip user-level skills/memory/settings/
# MCP/plugins via a credentials-only CLAUDE_CONFIG_DIR, so scoring measures
# only the project-installed rita-review. (Composes cleanly when invoked by
# test_claude.sh, which sets its own.) See run_hermetic.sh for the rationale.
HERMETIC_CFG="$(mktemp -d "${TMPDIR:-/tmp}/rita-rank-cfg.XXXXXX")"
[ -f "$HOME/.claude/.credentials.json" ] && cp "$HOME/.claude/.credentials.json" "$HERMETIC_CFG/"
export CLAUDE_CONFIG_DIR="$HERMETIC_CFG"
cleanup() {
  rm -rf "$HERMETIC_CFG"   # holds a copied credential — always remove
  if [[ $KEEP -eq 1 ]]; then echo "kept temp skill-env: $WORK_DIR" >&2
  else rm -rf "$WORK_DIR"; fi
}
trap cleanup EXIT

bash "$INSTALLER" --prefix "$PREFIX" "$WORK_DIR" >/dev/null

# --- invoke the rita-review skill natively ----------------------------
echo "─── scoring $FEATURE_DIR via /$SKILL ($GATE_MODEL) ───" >&2
PROMPT="/$SKILL $FEATURE_DIR

Score this plan. You are headless — do not ask questions."

STREAM_FILE="$WORK_DIR/.claude-stream.jsonl"
CLAUDE_START_TS=$(date +%s)
set +e
( cd "$WORK_DIR" && claude -p "$PROMPT" \
    --model "$GATE_MODEL" \
    --setting-sources project \
    --permission-mode bypassPermissions \
    --add-dir "$FEATURE_DIR" \
    --max-budget-usd "$BUDGET" \
    --verbose \
    --output-format stream-json ) \
  | tee "$STREAM_FILE" \
  | python3 "$PROGRESS_PY"
CLAUDE_RC=${PIPESTATUS[0]}
set -e

RESULT_TEXT="$(python3 "$STREAM_JSON" "$STREAM_FILE" result || true)"

print_usage() {
  {
    printf '\n─── scoring (rita-review) — usage ──────────\n'
    python3 "$STREAM_JSON" "$STREAM_FILE" usage
    printf 'gate_call:      %d s\n' "$(( $(date +%s) - CLAUDE_START_TS ))"
    printf '───────────────────────────────────────────\n'
  } > "$USAGE_OUT"   # stderr by default; a file when --usage-file is given
}
trap 'print_usage; cleanup' EXIT

[[ $CLAUDE_RC -eq 0 && -n "$RESULT_TEXT" ]] || { echo "FAIL: rita-review skill produced no scorecard (exit $CLAUDE_RC)" >&2; exit 1; }

# The skill's scorecard is its final message — relay it to stdout.
printf '%s\n' "$RESULT_TEXT"

# Machine-readable summary, parsed from the skill's "TOTAL n/m … grade G"
# line, so callers (and aggregation) don't have to scrape the table.
if [[ "$RESULT_TEXT" =~ TOTAL[[:space:]]+([0-9]+)/([0-9]+) ]]; then
  t="${BASH_REMATCH[1]}"; m="${BASH_REMATCH[2]}"
  p=$(( m > 0 ? 100 * t / m : 0 ))
  printf 'RANK total=%s max=%s pct=%s\n' "$t" "$m" "$p"
fi
