"""Enforce the repository limit for nonblank, non-comment Swift code lines."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LIMIT = 350


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


def oversized_files(
    root: Path = ROOT, limit: int = DEFAULT_LIMIT
) -> list[tuple[Path, int]]:
    results = []
    for path in tracked_swift_files(root):
        line_count = code_line_count(path.read_text(encoding="utf-8"))
        if line_count > limit:
            results.append((path.relative_to(root), line_count))
    return sorted(results, key=lambda item: (-item[1], str(item[0])))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT)
    args = parser.parse_args(argv)
    violations = oversized_files(limit=args.limit)
    for path, line_count in violations:
        print(f"{path}: {line_count} code lines (limit {args.limit})")
    if violations:
        print(
            f"error: {len(violations)} Swift file(s) exceed {args.limit} code lines",
            file=sys.stderr,
        )
        return 1
    print(
        f"All tracked Swift files under Sources and Tests are within {args.limit} code lines."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
