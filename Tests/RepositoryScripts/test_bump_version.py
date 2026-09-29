"""Behavior tests for the release version bump command."""

from __future__ import annotations

import contextlib
import io
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from Scripts.Release import bump_version

INFO_PLIST = Path("Sources/OpenJoystickDriver/App/Info.plist")


class BumpVersionTests(unittest.TestCase):
    def make_root(self) -> Path:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        (root / INFO_PLIST).parent.mkdir(parents=True)
        (root / INFO_PLIST).write_bytes(
            plistlib.dumps({"CFBundleShortVersionString": "0.5.0-beta.4"})
        )
        return root

    def run_bump(self, root: Path, version: str) -> int:
        with (
            mock.patch.object(bump_version, "ROOT", root),
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            try:
                return bump_version.main([version])
            except SystemExit as exit_:
                return int(exit_.code or 0)

    def short_version(self, root: Path) -> str:
        return plistlib.loads((root / INFO_PLIST).read_bytes())[
            "CFBundleShortVersionString"
        ]

    def test_sets_the_app_version_without_a_changelog_heading(self) -> None:
        root = self.make_root()

        self.assertEqual(self.run_bump(root, "0.5.0-beta.5"), 0)
        self.assertEqual(self.short_version(root), "0.5.0-beta.5")

    def test_refuses_build_metadata_and_keeps_the_app_version(self) -> None:
        root = self.make_root()

        self.assertNotEqual(self.run_bump(root, "0.5.0-beta.5+build.1"), 0)
        self.assertEqual(self.short_version(root), "0.5.0-beta.4")


if __name__ == "__main__":
    unittest.main()
