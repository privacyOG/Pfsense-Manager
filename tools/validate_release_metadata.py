#!/usr/bin/env python3

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

PUBSPEC_VERSION = re.compile(
    r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$",
    re.MULTILINE,
)
CHANGELOG_HEADING = re.compile(
    r"^## \[([^]]+)\](?: - \d{4}-\d{2}-\d{2})?$",
)
README_CURRENT_VERSION = re.compile(
    r"^##\s+Current version\s*$",
    re.IGNORECASE | re.MULTILINE,
)
README_VERSION_LITERAL = re.compile(
    r"(?<![A-Za-z0-9])v?\d+\.\d+\.\d+(?:\+\d+)?(?![A-Za-z0-9])",
)
README_CANONICAL_VERSION_TEXT = (
    "The canonical application version is the `version:` field in `pubspec.yaml`."
)
README_GENERIC_TAG = "`v<major>.<minor>.<patch>`"
README_KEYSTORE_PROPERTY = "storeFile=pfsense-release.jks"


class ReleaseMetadataError(ValueError):
    pass


@dataclass(frozen=True)
class ReleaseMetadata:
    version: str
    build_number: str

    @property
    def app_version(self) -> str:
        return f"{self.version}+{self.build_number}"


def parse_pubspec_version(pubspec: str) -> ReleaseMetadata:
    matches = PUBSPEC_VERSION.findall(pubspec)
    if len(matches) != 1:
        raise ReleaseMetadataError(
            "pubspec.yaml must contain exactly one version in major.minor.patch+build form"
        )
    version, build_number = matches[0]
    return ReleaseMetadata(version=version, build_number=build_number)


def validate_changelog(changelog: str, metadata: ReleaseMetadata) -> None:
    lines = changelog.splitlines()
    headings = [
        match.group(1)
        for line in lines
        if (match := CHANGELOG_HEADING.fullmatch(line.strip()))
    ]
    if "Unreleased" not in headings:
        raise ReleaseMetadataError("CHANGELOG.md is missing the [Unreleased] section")
    if len(headings) != len(set(headings)):
        raise ReleaseMetadataError("CHANGELOG.md contains duplicate version headings")

    start = None
    for index, line in enumerate(lines):
        match = CHANGELOG_HEADING.fullmatch(line.strip())
        if match and match.group(1) == metadata.version:
            start = index + 1
            break
    if start is None:
        raise ReleaseMetadataError(
            f"CHANGELOG.md has no section for version {metadata.version}"
        )

    end = len(lines)
    for index in range(start, len(lines)):
        if CHANGELOG_HEADING.fullmatch(lines[index].strip()):
            end = index
            break
    notes = "\n".join(lines[start:end]).strip()
    if not notes or notes == "No notable changes yet.":
        raise ReleaseMetadataError(
            f"CHANGELOG.md section {metadata.version} is empty"
        )


def validate_readme(readme: str) -> None:
    if README_CURRENT_VERSION.search(readme):
        raise ReleaseMetadataError(
            "README.md must not duplicate the current application version"
        )
    version_literal = README_VERSION_LITERAL.search(readme)
    if version_literal:
        raise ReleaseMetadataError(
            "README.md contains a hard-coded application version or release tag: "
            f"{version_literal.group(0)}"
        )
    if README_CANONICAL_VERSION_TEXT not in readme:
        raise ReleaseMetadataError(
            "README.md must identify pubspec.yaml as the canonical version source"
        )
    if README_GENERIC_TAG not in readme:
        raise ReleaseMetadataError(
            "README.md must use the version-neutral release tag example"
        )
    if README_KEYSTORE_PROPERTY not in readme:
        raise ReleaseMetadataError(
            "README.md must use the keystore path resolved from android/app"
        )


def validate_release_metadata(
    *,
    pubspec: str,
    changelog: str,
    readme: str,
) -> ReleaseMetadata:
    metadata = parse_pubspec_version(pubspec)
    validate_changelog(changelog, metadata)
    validate_readme(readme)
    return metadata


def validate_repository(root: Path) -> ReleaseMetadata:
    return validate_release_metadata(
        pubspec=(root / "pubspec.yaml").read_text(encoding="utf-8"),
        changelog=(root / "CHANGELOG.md").read_text(encoding="utf-8"),
        readme=(root / "README.md").read_text(encoding="utf-8"),
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("."))
    args = parser.parse_args()

    try:
        metadata = validate_repository(args.root)
    except (OSError, ReleaseMetadataError) as error:
        raise SystemExit(str(error)) from error

    print(f"Validated release metadata for {metadata.app_version}")


if __name__ == "__main__":
    main()
