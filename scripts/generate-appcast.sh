#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
: "${MORROW_RELEASE_VERSION:?Set a release version}"
: "${MORROW_SPARKLE_ED_PRIVATE_KEY:?Configure the update-signing secret}"
: "${GITHUB_REPOSITORY:?Set the repository name}"
# Reject malformed key material before passing it to tools that may echo errors.
python3 - <<'PY'
import base64, os
try:
    raw=base64.b64decode(os.environ['MORROW_SPARKLE_ED_PRIVATE_KEY'].strip(),validate=True)
    assert len(raw) == 32
except Exception:
    raise SystemExit('The update-signing secret is not a valid 32-byte Ed25519 seed.')
PY
release_directory="$(dirname "${MORROW_APP_OUTPUT:-build/release/Morrow.app}")"
archive="$release_directory/Morrow-$MORROW_RELEASE_VERSION-macos-arm64.zip"
test -f "$archive"
cp "$release_directory/release-notes.md" "${archive%.zip}.md"
printf '%s' "$MORROW_SPARKLE_ED_PRIVATE_KEY" |
    .build/artifacts/sparkle/Sparkle/bin/generate_appcast \
      --ed-key-file - --maximum-deltas 0 --embed-release-notes \
      --download-url-prefix "https://github.com/$GITHUB_REPOSITORY/releases/download/v$MORROW_RELEASE_VERSION/" \
      --link "https://github.com/$GITHUB_REPOSITORY" \
      -o "$release_directory/appcast.xml" "$release_directory"
xcrun swift scripts/verify-appcast.swift "$release_directory/appcast.xml" "$archive" \
    "${MORROW_APP_OUTPUT:-build/release/Morrow.app}/Contents/Info.plist"
