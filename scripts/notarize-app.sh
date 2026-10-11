#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
app="${MORROW_APP_OUTPUT:-build/release/Morrow.app}"
: "${MORROW_RELEASE_VERSION:?Set a release version}"
: "${MORROW_NOTARY_PROFILE:?Set a notarization keychain profile}"
: "${MORROW_NOTARY_KEYCHAIN:?Set the signing keychain path}"
if [[ ! "$MORROW_RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Use a numeric release version such as 0.1.0.' >&2
    exit 1
fi
release_directory="$(dirname "$app")"
submission="$release_directory/notary-submission.zip"
report="$release_directory/notarization.json"
codesign --verify --strict "$app/Contents/MacOS/morrow"
codesign --verify --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$submission"
submission_status=0
xcrun notarytool submit "$submission" --keychain-profile "$MORROW_NOTARY_PROFILE" --keychain "$MORROW_NOTARY_KEYCHAIN" --wait --timeout 45m --output-format json > "$report" || submission_status=$?
morrow_submission_id="$(python3 - "$report" <<'PY'
import json, sys
try: print(json.load(open(sys.argv[1])).get('id',''))
except (OSError, ValueError): pass
PY
)"
if [[ -n "$morrow_submission_id" ]]; then
    xcrun notarytool log "$morrow_submission_id" --keychain-profile "$MORROW_NOTARY_PROFILE" --keychain "$MORROW_NOTARY_KEYCHAIN" "$release_directory/notarization-log.json" || true
fi
python3 - "$report" "$submission_status" <<'PY'
import json, sys
result=json.load(open(sys.argv[1]))
if int(sys.argv[2]) or result.get('status') != 'Accepted':
    raise SystemExit('Apple did not accept this submission; it will not be released.')
print('Apple accepted the notarization submission.')
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute "$app"
release="$release_directory/Morrow-$MORROW_RELEASE_VERSION-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$release"
(cd "$release_directory" && shasum -a 256 "$(basename "$release")" > SHA256SUMS)
rm "$submission"
echo "Packaged the signed and notarized release: $release"
