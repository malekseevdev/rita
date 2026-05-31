#!/bin/bash
#
# Install the Rita Claude Code skills.
#
# Usage:
#   ./install-claude-skills.sh                      # user-level, into ~/.claude/skills/
#   ./install-claude-skills.sh <project-dir>        # project-scoped, into <project>/.claude/skills/
#   ./install-claude-skills.sh --prefix P <target>  # install each skill as P<name>
#
# Default is a user-level install — the skills become available
# in every project on this host.  Pass an explicit project
# directory to scope the install to that project only.
#
# --prefix installs each skill under a prefixed name (e.g. --prefix e2e-
# gives `e2e-rita-plan`, `e2e-rita-review`) with the frontmatter `name:`
# rewritten to match.  This guarantees a unique skill name that can't
# collide with — or be shadowed by — a same-named skill elsewhere
# (user-level skills take precedence over project-level ones), which is
# how the e2e tests pin the exact skill they install.
#
# The script copies every skill under skills/claude-code/ (rita-plan,
# rita-review, …) into <target>/.claude/skills/.  The -L flag resolves the
# docs/ and templates/ symlinks so each installed skill folder is
# self-contained and no longer depends on the Rita repo's location.  In a
# normal (unprefixed) install it also warns about stale rita-* skills
# already at the target (e.g. a renamed skill left behind).

set -eu

PREFIX=""
TARGET="$HOME"
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)   PREFIX="${2:?--prefix needs a value}"; shift 2 ;;
        --prefix=*) PREFIX="${1#*=}"; shift ;;
        -*)         echo "Error: unknown option '$1'" >&2; exit 1 ;;
        *)          TARGET="$1"; shift ;;
    esac
done

if [ ! -d "$TARGET" ]; then
    echo "Error: target directory '$TARGET' does not exist" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC_DIR="$SCRIPT_DIR/skills/claude-code"

if [ ! -d "$SKILL_SRC_DIR" ]; then
    echo "Error: skill sources not found at $SKILL_SRC_DIR" >&2
    echo "Run this script from the Rita repo root, or pass --help" >&2
    exit 1
fi

SKILLS_DIR="$TARGET/.claude/skills"
mkdir -p "$SKILLS_DIR"

# Install every skill under skills/claude-code/ (rita-plan, rita-review, …),
# optionally under a name prefix.  The -L flag resolves docs/ and
# templates/ symlinks so each installed skill folder is self-contained.
# PREFIX is "" for a normal install, so ${PREFIX}${name} is just ${name}
# and the same code path handles both — no special-casing.
INSTALLED=""
for SKILL_SRC in "$SKILL_SRC_DIR"/*/; do
    [ -f "$SKILL_SRC/SKILL.md" ] || continue
    name="$(basename "$SKILL_SRC")"
    inst="${PREFIX}${name}"
    dest="$SKILLS_DIR/$inst"
    [ -e "$dest" ] && { echo "Replacing existing skill at: $dest"; rm -rf "$dest"; }
    cp -rL "$SKILL_SRC" "$dest"
    # Keep the frontmatter `name:` in sync with the folder name (a no-op
    # when PREFIX is empty, since inst == name).
    sed -i "s/^name: ${name}\$/name: ${inst}/" "$dest/SKILL.md"
    echo "Installed $inst skill at: $dest"
    INSTALLED="$INSTALLED $inst"
done

# Warn about stale Rita skills left at the target — e.g. a renamed skill
# like the old rita-feature.  Only the bare `rita-*` namespace is checked,
# so the user's own unrelated skills (and prefixed test installs, which
# don't match) are never flagged.
for d in "$SKILLS_DIR"/rita-*/; do
    [ -d "$d" ] || continue            # no match → glob stays literal; skip
    n="$(basename "$d")"
    case " $INSTALLED " in
        *" $n "*) : ;;                 # one we just installed — fine
        *)
            echo >&2
            echo "WARNING: unexpected Rita skill at $d" >&2
            echo "         '$n' is not part of the current Rita skill set ($INSTALLED )." >&2
            echo "         If it's stale (e.g. a renamed skill), remove it:" >&2
            echo "             rm -rf \"$d\"" >&2
            ;;
    esac
done

echo
echo "Next: in Claude Code, invoke rita-plan to plan a non-trivial"
echo "feature, or rita-review to grade an existing plan.  See each"
echo "skill's SKILL.md for details."
