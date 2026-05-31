#!/usr/bin/env python3
"""Rita drift detection.

Walks <root>/**/docs/features/*/ folders and reports docs whose
`Last reviewed:` date is older than the most recent commit touching
any code file the doc links to.

Usage:
    python scripts/drift_check.py [--root .] [--fail-after DAYS]

Exit codes:
    0 — no rot beyond the threshold
    1 — at least one doc is stale beyond --fail-after
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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", maxsplit=1)[0])
    parser.add_argument("--root", default=".", help="Root directory to scan (default: cwd)")
    parser.add_argument(
        "--fail-after",
        type=int,
        default=None,
        help="Exit 1 if any doc is stale by more than this many days (default: never fail)",
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
        return 0

    if args.fail_after is not None and worst_age > args.fail_after:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
