from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "Scripts" / "Quality" / "check_swift_file_length.py"
SPEC = importlib.util.spec_from_file_location("check_swift_file_length", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SwiftFileLengthTests(unittest.TestCase):
    def test_counts_code_and_ignores_blank_and_comment_only_lines(self) -> None:
        source = """
// heading
let first = 1 // trailing comment
/* outer
  /* nested */
*/ let second = 2

"""
        self.assertEqual(MODULE.code_line_count(source), 2)

    def test_comment_markers_inside_strings_are_code(self) -> None:
        source = 'let slash = "//"\nlet block = "/* not a comment */"'
        self.assertEqual(MODULE.code_line_count(source), 2)

    def test_counts_nonblank_multiline_string_content(self) -> None:
        source = '''
let value = """
payload

/* literal content */
"""
'''
        self.assertEqual(MODULE.code_line_count(source), 4)

    def test_supports_raw_multiline_strings(self) -> None:
        source = '''
let value = #"""
""" is content until the hashed delimiter
"""#
'''
        self.assertEqual(MODULE.code_line_count(source), 3)

    def test_reports_only_tracked_swift_files_over_the_limit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Sources").mkdir()
            (root / "Tests").mkdir()
            (root / "Sources/Long.swift").write_text("let a = 1\nlet b = 2\n")
            (root / "Tests/Short.swift").write_text("let value = 1\n")
            import subprocess

            subprocess.run(["git", "init", "--quiet"], cwd=root, check=True)
            subprocess.run(
                ["git", "add", "Sources/Long.swift", "Tests/Short.swift"],
                cwd=root,
                check=True,
            )

            self.assertEqual(
                MODULE.oversized_files(root, source_limit=1, test_limit=1),
                [(Path("Sources/Long.swift"), 2)],
            )

    def test_applies_separate_limits_to_sources_and_tests(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Sources").mkdir()
            (root / "Tests").mkdir()
            (root / "Sources/Long.swift").write_text("let a = 1\nlet b = 2\n")
            (root / "Tests/Long.swift").write_text("let a = 1\nlet b = 2\nlet c = 3\n")
            import subprocess

            subprocess.run(["git", "init", "--quiet"], cwd=root, check=True)
            subprocess.run(["git", "add", "Sources", "Tests"], cwd=root, check=True)

            self.assertEqual(
                MODULE.oversized_files(root, source_limit=1, test_limit=3),
                [(Path("Sources/Long.swift"), 2)],
            )
            self.assertEqual(
                MODULE.oversized_files(root, source_limit=2, test_limit=2),
                [(Path("Tests/Long.swift"), 3)],
            )

    def test_rejects_numbered_and_generic_extension_file_names(self) -> None:
        for name in (
            "Server+Behavior.swift",
            "Server+Behavior2.swift",
            "RPCTests+Scenarios.swift",
            "RPCTests+Scenarios1.swift",
            "Coordinator+OutputScenarios3.swift",
            "Layout+Layouts2.swift",
        ):
            with self.subTest(name=name):
                self.assertTrue(MODULE.is_rejected_name(name))

    def test_accepts_semantic_extension_file_names(self) -> None:
        for name in (
            "Server.swift",
            "SonyBluetoothCRC32.swift",
            "DeviceManager+Queries.swift",
            "JoyConPairCharacterizationTests+PairBehavior.swift",
            "ControllerSessionTests+DS4Liveness.swift",
            "DriverParseCharacterizationTests+DualShock4Parsing.swift",
            "main+XIDChecks.swift",
        ):
            with self.subTest(name=name):
                self.assertFalse(MODULE.is_rejected_name(name))

    def test_reports_rejected_names_among_tracked_swift_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Sources").mkdir()
            (root / "Tests").mkdir()
            (root / "Sources/Server+Behavior1.swift").write_text("let a = 1\n")
            (root / "Sources/Server+Queries.swift").write_text("let b = 1\n")
            (root / "Tests/RPCTests+Scenarios.swift").write_text("let c = 1\n")
            import subprocess

            subprocess.run(["git", "init", "--quiet"], cwd=root, check=True)
            subprocess.run(["git", "add", "Sources", "Tests"], cwd=root, check=True)

            self.assertEqual(
                MODULE.misnamed_files(root),
                [
                    Path("Sources/Server+Behavior1.swift"),
                    Path("Tests/RPCTests+Scenarios.swift"),
                ],
            )

    def test_default_limits_are_500_for_sources_and_1000_for_tests(self) -> None:
        self.assertEqual(MODULE.DEFAULT_SOURCE_LIMIT, 500)
        self.assertEqual(MODULE.DEFAULT_TEST_LIMIT, 1000)


if __name__ == "__main__":
    unittest.main()
