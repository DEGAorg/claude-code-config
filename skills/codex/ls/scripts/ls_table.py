#!/usr/bin/env python3
"""Render a directory listing as a 3-column markdown table."""

from __future__ import annotations

import os
import sys
from pathlib import Path


def chunk(items: list[str], size: int) -> list[list[str]]:
    return [items[i:i + size] for i in range(0, len(items), size)]


def main() -> int:
    raw_target = sys.argv[1] if len(sys.argv) > 1 else "."
    target = Path(raw_target).expanduser().resolve()

    if not target.exists():
        print(f"Path does not exist: {target}", file=sys.stderr)
        return 1
    if not target.is_dir():
        print(f"Not a directory: {target}", file=sys.stderr)
        return 1

    entries: list[tuple[str, bool]] = []
    for entry in os.scandir(target):
        if entry.name.startswith("."):
            continue
        entries.append((entry.name, entry.is_dir()))

    entries.sort(key=lambda item: item[0].lower())
    display = [f"{name}/" if is_dir else name for name, is_dir in entries]
    file_count = sum(1 for _, is_dir in entries if not is_dir)
    dir_count = sum(1 for _, is_dir in entries if is_dir)

    print("| Name | Name | Name |")
    print("|---|---|---|")
    for row in chunk(display, 3):
        padded = row + [""] * (3 - len(row))
        print(f"| {padded[0]} | {padded[1]} | {padded[2]} |")

    print()
    print(f"**{len(entries)} items** ({file_count} files, {dir_count} directories)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
