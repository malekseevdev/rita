#!/usr/bin/env bash
#
# Hermetic `claude -p` runner — isolation primitive for Rita's evals/tests.
#
# WHY: an in-process agent (and even `claude -p` with the default config dir)
# inherits the host's user-level state — installed skills (~/.claude/skills/),
# auto-memory, settings.json, and configured MCP servers. For an A/B baseline or
# a smoke test that must measure *only* the skill under test, that ambient state
# is contamination: a "no-skill" baseline can silently pick up an installed Rita
# skill and behave as if it had it. (Observed exactly this while evaluating the
# skills — the fix is this script.)
#
# WHAT IT ISOLATES: everything under ~/.claude. It points CLAUDE_CONFIG_DIR at a
# fresh temp dir containing ONLY a copy of ~/.claude/.credentials.json (so auth
# still works), which drops user skills, memory, settings, plugins, and MCP. It
# also runs from a neutral cwd so no project-level .claude/ or repo files leak.
#
# KNOWN RESIDUAL: this isolates *discovery/auto-load*, not the filesystem. A run
# can still read arbitrary paths (e.g. a checked-out repo) if it goes looking.
# For full isolation, run inside a sandbox/container with no access to the repo.
#
# NB: do NOT add `--bare` — it also skips credential loading, yielding
# "Not logged in". An empty-but-for-credentials config dir is enough.
#
# Usage:
#   run_hermetic.sh [--model NAME] [--cwd DIR] [--output-format FMT] <prompt>
#     --model NAME        model id/alias (default: sonnet)
#     --cwd DIR           working directory for the run (default: a fresh temp dir)
#     --output-format FMT text | json | stream-json (default: text)
#
# Prints the model's output to stdout. Exit code is the claude exit code.

set -euo pipefail

MODEL="${MODEL:-sonnet}"
RUN_CWD=""
OUT_FMT="text"
while [ $# -gt 0 ]; do
  case "$1" in
    --model)         MODEL="${2:?--model needs a value}"; shift 2 ;;
    --model=*)       MODEL="${1#*=}"; shift ;;
    --cwd)           RUN_CWD="${2:?--cwd needs a value}"; shift 2 ;;
    --cwd=*)         RUN_CWD="${1#*=}"; shift ;;
    --output-format) OUT_FMT="${2:?--output-format needs a value}"; shift 2 ;;
    --output-format=*) OUT_FMT="${1#*=}"; shift ;;
    --) shift; break ;;
    -*) echo "run_hermetic.sh: unknown option '$1'" >&2; exit 2 ;;
    *)  break ;;
  esac
done
PROMPT="${1:?prompt required (see --help in the header)}"

command -v claude >/dev/null || { echo "run_hermetic.sh: claude CLI not found" >&2; exit 1; }

# Fresh config dir holding ONLY credentials — blocks skills/memory/settings/MCP.
CFG="$(mktemp -d "${TMPDIR:-/tmp}/rita-hermetic-cfg.XXXXXX")"
trap 'rm -rf "$CFG"' EXIT
[ -f "$HOME/.claude/.credentials.json" ] && cp "$HOME/.claude/.credentials.json" "$CFG/"

# Neutral cwd by default so no project-level .claude/ or repo files are discovered.
if [ -z "$RUN_CWD" ]; then
  RUN_CWD="$(mktemp -d "${TMPDIR:-/tmp}/rita-hermetic-cwd.XXXXXX")"
  trap 'rm -rf "$CFG" "$RUN_CWD"' EXIT
fi
mkdir -p "$RUN_CWD"

( cd "$RUN_CWD" \
  && CLAUDE_CONFIG_DIR="$CFG" claude -p "$PROMPT" \
       --model "$MODEL" \
       --permission-mode bypassPermissions \
       --output-format "$OUT_FMT" )
