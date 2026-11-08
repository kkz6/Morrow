#!/usr/bin/env python3
"""Validate a stable app release before importing signing credentials."""
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess

version = os.environ.get('REQUESTED_VERSION', '')
if os.environ.get('GITHUB_EVENT_NAME') == 'push':
    tag = os.environ.get('GITHUB_REF_NAME', '')
    version = tag.removeprefix('v')
    if tag != 'v' + version:
        raise SystemExit('Release tags must start with v.')
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('Use a stable numeric version such as 0.2.0.')
info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
if info['CFBundleShortVersionString'] != version:
    raise SystemExit('The release version must match Resources/Info.plist.')
tag_commit = subprocess.run(['git', 'rev-parse', '--verify', f'refs/tags/v{version}^{{commit}}'], capture_output=True, text=True)
if tag_commit.returncode == 0:
    source_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if tag_commit.stdout.strip() != source_commit:
        raise SystemExit('The existing release tag points to different source. Use its commit or a new version.')
# Published releases are immutable, and a stable feed must never move backward.
result = subprocess.run(['gh', 'api', f'repos/{os.environ["GITHUB_REPOSITORY"]}/releases/latest'], capture_output=True, text=True)
if result.returncode == 0:
    latest = json.loads(result.stdout)['tag_name'].removeprefix('v')
    if not re.fullmatch(r'\d+\.\d+\.\d+', latest):
        raise SystemExit('Review the existing release version before replacing the stable feed.')
    if tuple(map(int, version.split('.'))) <= tuple(map(int, latest.split('.'))):
        raise SystemExit('Choose a version newer than the latest published release.')
elif 'HTTP 404' not in result.stderr:
    raise SystemExit('Could not verify the latest release. Publication was stopped.')
with open(os.environ['GITHUB_ENV'], 'a') as output:
    output.write(f'MORROW_RELEASE_VERSION={version}\n')
release = Path('build/release')
release.mkdir(parents=True, exist_ok=True)
changelog = Path('CHANGELOG.md').read_text()
notes = changelog.split('## Unreleased', 1)[1].split('\n## ', 1)[0].strip()
(release / 'release-notes.md').write_text(notes + '\n')
print(f'Validated Morrow {version} for Apple silicon.')
