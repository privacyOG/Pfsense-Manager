#!/usr/bin/env python3

import argparse
import re
from pathlib import Path

SECTION = re.compile(r"^## \[([^]]+)\](?: - \d{4}-\d{2}-\d{2})?$")


def section_text(source: Path, name: str) -> str:
    lines = source.read_text(encoding="utf-8").splitlines()
    start = None
    for index, line in enumerate(lines):
        match = SECTION.fullmatch(line.strip())
        if match and match.group(1) == name:
            start = index + 1
            break

    if start is None:
        raise ValueError(f"Missing changelog section: {name}")

    end = len(lines)
    for index in range(start, len(lines)):
        if SECTION.fullmatch(lines[index].strip()):
            end = index
            break

    text = "\n".join(lines[start:end]).strip()
    if not text or text == "No notable changes yet.":
        raise ValueError(f"Empty changelog section: {name}")
    return text


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("name")
    parser.add_argument("output")
    parser.add_argument("--source", default="CHANGELOG.md")
    args = parser.parse_args()

    text = section_text(Path(args.source), args.name)
    Path(args.output).write_text(text + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
