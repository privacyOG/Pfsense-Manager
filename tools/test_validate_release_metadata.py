#!/usr/bin/env python3

import unittest

from validate_release_metadata import (
    ReleaseMetadataError,
    parse_pubspec_version,
    validate_release_metadata,
)


VALID_PUBSPEC = """name: pfsense_manager
version: 1.8.2+16
"""

VALID_CHANGELOG = """# Changelog

## [Unreleased]

## [1.8.2] - 2026-06-29

### Fixed

- Release metadata validation.
"""

VALID_README = """# pfSense Manager

Pushing `v<major>.<minor>.<patch>` builds a signed release.

storeFile=pfsense-release.jks

## Release metadata

The canonical application version is the `version:` field in `pubspec.yaml`.
"""


class ReleaseMetadataValidationTest(unittest.TestCase):
    def test_accepts_consistent_release_metadata(self) -> None:
        metadata = validate_release_metadata(
            pubspec=VALID_PUBSPEC,
            changelog=VALID_CHANGELOG,
            readme=VALID_README,
        )

        self.assertEqual(metadata.version, "1.8.2")
        self.assertEqual(metadata.build_number, "16")
        self.assertEqual(metadata.app_version, "1.8.2+16")

    def test_rejects_stale_current_version_section(self) -> None:
        readme = VALID_README + "\n## Current version\n\n`1.7.4+13`\n"

        with self.assertRaisesRegex(
            ReleaseMetadataError,
            "must not duplicate the current application version",
        ):
            validate_release_metadata(
                pubspec=VALID_PUBSPEC,
                changelog=VALID_CHANGELOG,
                readme=readme,
            )

    def test_rejects_literal_release_tag_examples(self) -> None:
        readme = VALID_README.replace(
            "`v<major>.<minor>.<patch>`",
            "`v1.7.4`",
        )

        with self.assertRaisesRegex(
            ReleaseMetadataError,
            "hard-coded application version or release tag",
        ):
            validate_release_metadata(
                pubspec=VALID_PUBSPEC,
                changelog=VALID_CHANGELOG,
                readme=readme,
            )

    def test_rejects_incorrect_keystore_property(self) -> None:
        readme = VALID_README.replace(
            "storeFile=pfsense-release.jks",
            "storeFile=app/pfsense-release.jks",
        )

        with self.assertRaisesRegex(
            ReleaseMetadataError,
            "keystore path resolved from android/app",
        ):
            validate_release_metadata(
                pubspec=VALID_PUBSPEC,
                changelog=VALID_CHANGELOG,
                readme=readme,
            )

    def test_rejects_missing_current_changelog_section(self) -> None:
        changelog = VALID_CHANGELOG.replace("[1.8.2]", "[1.8.1]")

        with self.assertRaisesRegex(
            ReleaseMetadataError,
            "has no section for version 1.8.2",
        ):
            validate_release_metadata(
                pubspec=VALID_PUBSPEC,
                changelog=changelog,
                readme=VALID_README,
            )

    def test_rejects_duplicate_changelog_headings(self) -> None:
        changelog = VALID_CHANGELOG + "\n## [1.8.2]\n\n- Duplicate.\n"

        with self.assertRaisesRegex(
            ReleaseMetadataError,
            "duplicate version headings",
        ):
            validate_release_metadata(
                pubspec=VALID_PUBSPEC,
                changelog=changelog,
                readme=VALID_README,
            )

    def test_requires_build_number_in_pubspec(self) -> None:
        with self.assertRaisesRegex(
            ReleaseMetadataError,
            "major.minor.patch\+build",
        ):
            parse_pubspec_version("version: 1.8.2\n")


if __name__ == "__main__":
    unittest.main()
