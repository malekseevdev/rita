#!/usr/bin/env python3
"""Rita drift detection.

Two passes over <root>/**/docs/features/*/ feature folders:

  * Date drift (always) — reports docs whose `Last reviewed:` date is
    older than the most recent commit touching any code file the doc
    links to.
  * Referential integrity (--refs) — extracts identifiers the docs
    assert exist in code (backticked metric names, env vars, and
    FEATURE_*/KILL_* flags) and reports the ones it can't find anywhere
    in the tree outside the feature docs.  These are *candidates to
    verify*, not confirmed gaps: an identifier can be built at runtime
    (a metric name assembled from a prefix, a flag read via a constant)
    and so be real yet unfindable by literal search.

Usage:
    python scripts/drift_check.py [--root .] [--fail-after DAYS] [--refs]

Exit codes:
    0 — no date drift beyond the threshold
    1 — at least one doc is stale beyond --fail-after
        (the --refs pass is advisory and never changes the exit code)
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import subprocess
import sys
from pathlib import Path

# Markdown link pattern: [text](path).  We only care about local paths
# (no scheme), so we exclude http/https/mailto.  Paths with anchors
# (#section) are stripped to the file portion.
LINK_RE = re.compile(r"\[[^\]]+\]\(([^)#]+)(?:#[^)]*)?\)")
LAST_REVIEWED_RE = re.compile(r"^>?\s*Last reviewed:\s*(\d{4}-\d{2}-\d{2})\s*$", re.MULTILINE)


def find_feature_docs(root: Path) -> list[Path]:
    """Find all <root>/**/docs/features/*/README.md files."""
    return sorted(root.glob("**/docs/features/*/README.md"))


def parse_review_date(doc: Path) -> dt.date | None:
    """Extract the `Last reviewed: YYYY-MM-DD` line from a doc."""
    match = LAST_REVIEWED_RE.search(doc.read_text(encoding="utf-8"))
    if not match:
        return None
    try:
        return dt.date.fromisoformat(match.group(1))
    except ValueError:
        return None


def extract_links(doc: Path) -> list[Path]:
    """Return paths of local code files linked from the doc."""
    text = doc.read_text(encoding="utf-8")
    out: list[Path] = []
    for raw in LINK_RE.findall(text):
        # Skip external URLs, mailto, etc.
        if "://" in raw or raw.startswith("mailto:"):
            continue
        # Resolve relative to the doc's directory.
        target = (doc.parent / raw).resolve()
        # Only flag files that exist; broken links are a separate lint concern.
        if target.is_file():
            out.append(target)
    return out


def last_modified(path: Path) -> dt.date | None:
    """Return the date of the most recent commit touching `path`."""
    result = subprocess.run(
        ["git", "log", "-1", "--format=%cs", "--", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    stamp = result.stdout.strip()
    if not stamp:
        return None
    try:
        return dt.date.fromisoformat(stamp)
    except ValueError:
        return None


def check_doc(doc: Path) -> tuple[dt.date | None, list[tuple[Path, dt.date]]]:
    """Return (review_date, stale_links).  stale_links is a list of
    (linked_file, file_mtime) pairs where file_mtime > review_date."""
    review = parse_review_date(doc)
    if review is None:
        return None, []
    stale: list[tuple[Path, dt.date]] = []
    for link in extract_links(doc):
        mtime = last_modified(link)
        if mtime and mtime > review:
            stale.append((link, mtime))
    return review, stale


# --- Referential integrity (--refs) --------------------------------------
# Identifiers the docs assert exist in code.  We extract conservatively —
# only backticked tokens that look like code identifiers, plus the framework's
# own flag/kill-switch naming convention — so the noise floor stays low.
BACKTICK_RE = re.compile(r"`([^`]+)`")
# A dotted lower-snake token (metric names: `app.feature.thing_measured`).
DOTTED_SNAKE_RE = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+$")
# An UPPER_SNAKE token with at least one underscore (env vars, config keys).
UPPER_SNAKE_RE = re.compile(r"^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+$")
# Rita's flag / kill-switch convention, backticked or bare.
FLAG_RE = re.compile(r"\b(?:FEATURE|KILL)_[A-Z0-9_]+\b")
# Tokens ending in a source/doc file extension are filenames, not the kind of
# runtime identifier this pass is about — drop them (the date-drift pass
# already covers linked files).
FILE_EXT_RE = re.compile(
    r"\.(?:md|py|pyi|js|jsx|ts|tsx|txt|json|ya?ml|toml|ini|cfg|env|lock|sh|"
    r"go|rs|rb|java|kt|sql|csv|html?|css)$",
    re.IGNORECASE,
)


def extract_identifiers(folder: Path) -> dict[str, list[tuple[Path, int]]]:
    """Map each documented code identifier in a feature folder's `*.md`
    files to the (doc, line) locations that mention it."""
    out: dict[str, list[tuple[Path, int]]] = {}
    for doc in sorted(folder.glob("*.md")):
        for lineno, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
            tokens: set[str] = set()
            for tok in BACKTICK_RE.findall(line):
                tok = tok.strip()
                if "/" in tok or FILE_EXT_RE.search(tok):
                    continue
                if DOTTED_SNAKE_RE.match(tok) or UPPER_SNAKE_RE.match(tok):
                    tokens.add(tok)
            tokens.update(FLAG_RE.findall(line))
            for tok in tokens:
                out.setdefault(tok, []).append((doc, lineno))
    return out


def found_in_code(token: str, root: Path) -> bool:
    """True if `token` appears literally in a file under `root` that is not
    itself a feature doc.  Uses `git grep` where available, else walks."""
    result = subprocess.run(
        ["git", "grep", "-F", "-l", "-e", token],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    # rc 0 = matches, 1 = no matches; both are clean answers from git.
    if result.returncode in (0, 1) and not result.stderr.strip():
        return any(
            "docs/features/" not in line for line in result.stdout.splitlines()
        )
    # No git (or not a repo): best-effort walk, skipping .git and feature docs.
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if rel.startswith(".git/") or "docs/features/" in rel:
            continue
        try:
            if token in path.read_text(encoding="utf-8"):
                return True
        except (UnicodeDecodeError, OSError):
            continue
    return False


def report_refs(docs: list[Path], root: Path) -> None:
    """Print the referential-integrity pass for each feature folder."""
    for folder in sorted({doc.parent for doc in docs}):
        ids = extract_identifiers(folder)
        if not ids:
            continue
        rel = folder.relative_to(root)
        missing = [(t, locs) for t, locs in sorted(ids.items()) if not found_in_code(t, root)]
        if not missing:
            print(f"REFS  {rel}: {len(ids)} documented identifier(s), all found in code.")
            continue
        print(f"REFS  {rel}: {len(missing)} of {len(ids)} documented identifier(s) not found in code")
        for token, locs in missing:
            where = ", ".join(f"{d.relative_to(root)}:{n}" for d, n in locs[:3])
            print(f"      └─ `{token}`  ({where}) — verify; may be runtime-assembled")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", maxsplit=1)[0])
    parser.add_argument("--root", default=".", help="Root directory to scan (default: cwd)")
    parser.add_argument(
        "--fail-after",
        type=int,
        default=None,
        help="Exit 1 if any doc is stale by more than this many days (default: never fail)",
    )
    parser.add_argument(
        "--refs",
        action="store_true",
        help="Also run the referential-integrity pass (documented identifiers "
        "not found in code).  Advisory — never changes the exit code.",
    )
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    docs = find_feature_docs(root)
    if not docs:
        print(f"No feature docs found under {root}/**/docs/features/")
        return 0

    today = dt.date.today()
    any_stale = False
    worst_age = 0

    for doc in docs:
        review, stale = check_doc(doc)
        rel = doc.relative_to(root)
        if review is None:
            print(f"WARN  {rel}: no `Last reviewed:` line")
            continue
        if not stale:
            continue
        any_stale = True
        age = (today - review).days
        worst_age = max(worst_age, age)
        print(f"STALE {rel}  (reviewed {review}, {age}d ago)")
        for link, mtime in stale:
            print(f"      └─ {link.relative_to(root)} changed {mtime}")

    if not any_stale:
        print(f"OK    {len(docs)} feature doc(s) reviewed.")
        exit_code = 0
    elif args.fail_after is not None and worst_age > args.fail_after:
        exit_code = 1
    else:
        exit_code = 0

    if args.refs:
        report_refs(docs, root)

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
