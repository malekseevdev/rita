#!/bin/bash
#
# Install the Rita Claude Code skill.
#
# Usage:
#   ./install-claude-skill.sh                # user-level, into ~/.claude/skills/
#   ./install-claude-skill.sh <project-dir>  # project-scoped, into <project>/.claude/skills/
#
# Default is a user-level install — the skill becomes available
# in every project on this host.  Pass an explicit project
# directory to scope the install to that project only.
#
# The script copies skills/claude-code/rita-feature into
# <target>/.claude/skills/rita-feature.  The -L flag resolves the
# docs/ and templates/ symlinks so the installed skill folder is
# self-contained and no longer depends on the Rita repo's
# location.

set -eu

TARGET="${1:-$HOME}"

if [ ! -d "$TARGET" ]; then
    echo "Error: target directory '$TARGET' does not exist" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$SCRIPT_DIR/skills/claude-code/rita-feature"

if [ ! -d "$SKILL_SRC" ]; then
    echo "Error: skill source not found at $SKILL_SRC" >&2
    echo "Run this script from the Rita repo root, or pass --help" >&2
    exit 1
fi

SKILLS_DIR="$TARGET/.claude/skills"
DEST="$SKILLS_DIR/rita-feature"

mkdir -p "$SKILLS_DIR"
if [ -e "$DEST" ]; then
    echo "Replacing existing skill at: $DEST"
    rm -rf "$DEST"
fi
cp -rL "$SKILL_SRC" "$SKILLS_DIR/"

echo "Installed rita-feature skill at: $DEST"
echo
echo "Next: invoke the skill in Claude Code when planning a"
echo "non-trivial feature.  See $DEST/SKILL.md for what the"
echo "skill does and how it walks the lifecycle."
