"""Enforce Swift file limits: code lines per file and semantic extension file names."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE_LIMIT = 500
DEFAULT_TEST_LIMIT = 1000
# `Type+Concern.swift` must name its concern; numbered or generic splits hide what a file owns.
REJECTED_CONCERN = re.compile(r"^(?:Behavior|Scenarios)$|[0-9]$")


def code_line_count(source: str) -> int:
    """Count lines containing Swift code, including multiline string content."""
    count = 0
    block_comment_depth = 0
    multiline_string_hashes: int | None = None

    for line in source.splitlines():
        index = 0
        has_code = False
        while index < len(line):
            if multiline_string_hashes is not None:
                delimiter = '"""' + ("#" * multiline_string_hashes)
                end = line.find(delimiter, index)
                if end < 0:
                    has_code = has_code or bool(line[index:].strip())
                    break
                has_code = True
                index = end + len(delimiter)
                multiline_string_hashes = None
                continue

            if block_comment_depth:
                if line.startswith("/*", index):
                    block_comment_depth += 1
                    index += 2
                elif line.startswith("*/", index):
                    block_comment_depth -= 1
                    index += 2
                else:
                    index += 1
                continue

            if line[index].isspace():
                index += 1
                continue
            if line.startswith("//", index):
                break
            if line.startswith("/*", index):
                block_comment_depth = 1
                index += 2
                continue

            hashes = 0
            while index + hashes < len(line) and line[index + hashes] == "#":
                hashes += 1
            if line.startswith('"""', index + hashes):
                has_code = True
                index += hashes + 3
                delimiter = '"""' + ("#" * hashes)
                end = line.find(delimiter, index)
                if end < 0:
                    multiline_string_hashes = hashes
                    break
                index = end + len(delimiter)
                continue

            has_code = True
            if line[index] == '"' or (
                hashes and index + hashes < len(line) and line[index + hashes] == '"'
            ):
                quote = index + hashes
                index = quote + 1
                closing_hashes = "#" * hashes
                while index < len(line):
                    if line[index] == '"' and line.startswith(
                        closing_hashes, index + 1
                    ):
                        index += 1 + hashes
                        break
                    if not hashes and line[index] == "\\":
                        index += 2
                    else:
                        index += 1
                continue
            index += 1

        count += has_code

    return count


def tracked_swift_files(root: Path = ROOT) -> list[Path]:
    command = ["git", "ls-files", "--cached", "--others", "--exclude-standard"]
    result = subprocess.run(
        command, cwd=root, check=True, capture_output=True, text=True
    )
    return [
        root / relative_path
        for relative_path in result.stdout.splitlines()
        if Path(relative_path).suffix == ".swift"
        and Path(relative_path).parts[0] in {"Sources", "Tests"}
        # A tracked file deleted in the working tree has nothing left to measure.
        and (root / relative_path).exists()
    ]


def is_rejected_name(file_name: str) -> bool:
    stem = Path(file_name).stem
    if "+" not in stem:
        return False
    return REJECTED_CONCERN.search(stem.rsplit("+", 1)[1]) is not None


def misnamed_files(root: Path = ROOT) -> list[Path]:
    return sorted(
        path.relative_to(root)
        for path in tracked_swift_files(root)
        if is_rejected_name(path.name)
    )


def limit_for(relative_path: Path, source_limit: int, test_limit: int) -> int:
    return test_limit if relative_path.parts[0] == "Tests" else source_limit


def oversized_files(
    root: Path = ROOT,
    source_limit: int = DEFAULT_SOURCE_LIMIT,
    test_limit: int = DEFAULT_TEST_LIMIT,
) -> list[tuple[Path, int]]:
    results = []
    for path in tracked_swift_files(root):
        line_count = code_line_count(path.read_text(encoding="utf-8"))
        limit = limit_for(path.relative_to(root), source_limit, test_limit)
        if line_count > limit:
            results.append((path.relative_to(root), line_count))
    return sorted(results, key=lambda item: (-item[1], str(item[0])))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-limit", type=int, default=DEFAULT_SOURCE_LIMIT)
    parser.add_argument("--test-limit", type=int, default=DEFAULT_TEST_LIMIT)
    args = parser.parse_args(argv)
    violations = oversized_files(
        source_limit=args.source_limit, test_limit=args.test_limit
    )
    for path, line_count in violations:
        limit = limit_for(path, args.source_limit, args.test_limit)
        print(f"{path}: {line_count} code lines (limit {limit})")
    misnamed = misnamed_files()
    for path in misnamed:
        print(
            f"{path}: name the extension's concern instead of a number or Behavior/Scenarios"
        )
    if violations:
        print(
            f"error: {len(violations)} Swift file(s) exceed their code-line limit",
            file=sys.stderr,
        )
    if misnamed:
        print(
            f"error: {len(misnamed)} Swift file(s) have a numbered or generic extension name",
            file=sys.stderr,
        )
    if violations or misnamed:
        return 1
    print(
        f"All tracked Swift files are within {args.source_limit} code lines (Sources) "
        f"and {args.test_limit} code lines (Tests), with semantic extension names."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
