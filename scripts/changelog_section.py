#!/usr/bin/env python3
"""Prints one version's section of CHANGELOG.md, for use as release notes.

    scripts/changelog_section.py 0.4.0

Falls back to printing nothing (exit 1) when the version has no section yet,
so a release can still go out on auto-generated notes alone.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = ROOT / "CHANGELOG.md"


def section(version: str, text: str) -> str | None:
    """The body under `## [<version>]`, up to the next version heading."""
    heading = re.compile(r"^## \[([^\]]+)\]", re.MULTILINE)
    matches = list(heading.finditer(text))
    for i, m in enumerate(matches):
        if m.group(1) != version:
            continue
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[start:end]
        # Drop the date that trails the heading, keep the notes themselves.
        body = body.split("\n", 1)[1] if "\n" in body else ""
        return body.strip()
    return None


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <version>", file=sys.stderr)
        return 2
    version = sys.argv[1]
    if not CHANGELOG.is_file():
        print(f"no {CHANGELOG.name}", file=sys.stderr)
        return 1
    body = section(version, CHANGELOG.read_text(encoding="utf-8"))
    if not body:
        print(f"no CHANGELOG section for {version}", file=sys.stderr)
        return 1
    print(f"\n## What changed in {version}\n")
    print(body)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
