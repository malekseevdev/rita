#!/usr/bin/env bash
#
# Rita drift-detection test (offline, deterministic — no model calls).
#
# scripts/drift_check.py flags a feature doc as stale when a code file it links
# has a newer git commit than the doc's `Last reviewed:` date.  This test
# builds a SELF-CONTAINED throwaway git repo — one tiny feature doc that
# links a one-line code file — and asserts:
#
#   1. Fresh — doc reviewed *after* the code's last change → OK (exit 0).
#   2. Drift — code changed *after* the review date → STALE; exit 1 under
#              --fail-after 0, exit 0 under a generous threshold.
#
# It also sanity-checks that the committed worked example parses clean:
# it's a Plan with no linked code, so drift_check.py reports OK on it.
#
# The drift fixture is built here rather than lifted from the example —
# the example is a plan (no implementation to link), so it isn't a drift
# subject.  Dates are pinned in the past so the result is deterministic.
#
# Usage:  tests/e2e/test_drift.sh [--show-output] [--keep]
#   --show-output   print drift_check.py output for each phase
#   --keep          don't delete the temp repo on exit (prints its path)
#
# Exit 0 = all assertions passed.  Exit 1 = a failure (with a message).

set -euo pipefail

SHOW_OUTPUT=0
KEEP=0
for arg in "$@"; do
  case "$arg" in
    --show-output) SHOW_OUTPUT=1 ;;
    --keep)        KEEP=1 ;;
    *) echo "FAIL: unknown argument '$arg'" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECK_PY="$REPO_ROOT/scripts/drift_check.py"
EXAMPLE_DIR="$REPO_ROOT/examples/search-rate-limit"
[[ -f "$CHECK_PY" ]] || { echo "FAIL: missing $CHECK_PY"; exit 1; }

# Pinned, in-the-past fixture dates (YYYY-MM-DD):  CODE_OLD < REVIEW < CODE_NEW.
REVIEW_DATE="2025-01-15"        # written into the fixture doc's "Last reviewed:"
CODE_OLD_DATE="2025-01-10"      # initial commit — before review → not stale
CODE_NEW_DATE="2025-02-20"      # drift commit — after review → stale
CODE_REL="src/widget.py"
DOC_REL="docs/features/DEMO-1-widget/README.md"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rita-e2e-drift.XXXXXX")"
cleanup() {
  if [[ $KEEP -eq 1 ]]; then echo "kept temp repo: $WORK_DIR" >&2
  else rm -rf "$WORK_DIR"; fi
}
trap cleanup EXIT

run_check() {  # run_check <root> <fail-after> -> sets CHECK_OUT, CHECK_RC
  set +e
  CHECK_OUT="$(python3 "$CHECK_PY" --root "$1" --fail-after "$2" 2>&1)"
  CHECK_RC=$?
  set -e
  if [[ $SHOW_OUTPUT -eq 1 ]]; then
    echo "----- drift_check.py --root $1 --fail-after $2 (exit $CHECK_RC) -----"
    echo "$CHECK_OUT"; echo
  fi
}
fail() { echo "FAIL: $1"; echo "--- check output ---"; echo "$CHECK_OUT"; exit 1; }

PS4='+ '
set -x

# --- Phase 0: the committed example parses clean ---------------------
# It's a Plan with no linked code, so drift_check.py finds the doc and reports
# OK (nothing to drift against).
run_check "$EXAMPLE_DIR" 90
[[ $CHECK_RC -eq 0 ]]           || fail "phase 0: example should report exit 0, got $CHECK_RC"
grep -q "^OK"  <<<"$CHECK_OUT"  || fail "phase 0: expected an OK line for the example"
grep -q "STALE" <<<"$CHECK_OUT" && fail "phase 0: example (a plan) should not be STALE"
set +x; echo "PASS phase 0: committed example parses clean (OK)"; set -x

# --- build the self-contained drift fixture --------------------------
mkdir -p "$WORK_DIR/$(dirname "$CODE_REL")" "$WORK_DIR/$(dirname "$DOC_REL")"
cat > "$WORK_DIR/$CODE_REL" <<'PY'
def widget(x):
    return x * 2
PY
cat > "$WORK_DIR/$DOC_REL" <<MD
# DEMO-1: widget

> Status: Implementation
> Last reviewed: $REVIEW_DATE
> Ticket: DEMO-1

## How it works

The doubling logic lives in [\`src/widget.py\`](../../../src/widget.py).
MD

cd "$WORK_DIR"
git init -q
git config user.email "test@rita.test"
git config user.name "Rita Test"
git config commit.gpgsign false

commit_all_at() {  # commit_all_at <date> <message>
  git add -A
  GIT_AUTHOR_DATE="$1T12:00:00" GIT_COMMITTER_DATE="$1T12:00:00" \
    git commit -q -m "$2"
}

# --- Phase 1: fresh doc → clean --------------------------------------
commit_all_at "$CODE_OLD_DATE" "fixture: widget + feature doc"

run_check "$WORK_DIR" 90
[[ $CHECK_RC -eq 0 ]]            || fail "phase 1: expected exit 0, got $CHECK_RC"
grep -q "^OK"  <<<"$CHECK_OUT"   || fail "phase 1: expected an OK line"
grep -q "STALE" <<<"$CHECK_OUT"  && fail "phase 1: did not expect STALE on a fresh doc"
set +x; echo "PASS phase 1: fresh feature folder reports OK (exit 0)"; set -x

# --- Phase 2: code changes after review → stale ----------------------
printf '\n# touched after review to simulate code drift\n' >> "$CODE_REL"
commit_all_at "$CODE_NEW_DATE" "tweak widget (simulated drift)"

# 2a. --fail-after 0: any drift on a past-dated doc must exit 1.
run_check "$WORK_DIR" 0
[[ $CHECK_RC -eq 1 ]]               || fail "phase 2a: expected exit 1, got $CHECK_RC"
grep -q "STALE" <<<"$CHECK_OUT"     || fail "phase 2a: expected a STALE line"
grep -q "$CODE_REL" <<<"$CHECK_OUT" || fail "phase 2a: expected the code file named as changed"
set +x; echo "PASS phase 2a: code change after review reports STALE (exit 1 at --fail-after 0)"; set -x

# 2b. A generous threshold still detects drift but does not fail the build.
run_check "$WORK_DIR" 100000
[[ $CHECK_RC -eq 0 ]]           || fail "phase 2b: expected exit 0 under a huge threshold, got $CHECK_RC"
grep -q "STALE" <<<"$CHECK_OUT" || fail "phase 2b: expected STALE to still be reported"
set +x
echo "PASS phase 2b: drift still reported but --fail-after threshold not exceeded (exit 0)"

echo
echo "OK: all drift-detection assertions passed."
