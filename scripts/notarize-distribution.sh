#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
morrow_distribution_output="${1:?Pass the distribution output directory}"
: "${MORROW_NOTARY_PROFILE:?Set a notarization keychain profile}"
: "${MORROW_NOTARY_KEYCHAIN:?Set the signing keychain path}"
xcrun notarytool submit "$morrow_distribution_output/notary-submission.zip" \
    --keychain-profile "$MORROW_NOTARY_PROFILE" --keychain "$MORROW_NOTARY_KEYCHAIN" \
    --wait --timeout 30m --output-format json > "$morrow_distribution_output/notarization.json"
python3 - "$morrow_distribution_output" <<'PY'
import json
from pathlib import Path
import sys
output = Path(sys.argv[1])
result = json.loads((output / 'notarization.json').read_text())
if result.get('status') != 'Accepted' or not result.get('id'):
    raise SystemExit('Apple did not accept these binaries; do not publish them.')
for path in output.glob('*-release.json'):
    release = json.loads(path.read_text())
    release['notarizationID'] = result['id']
    path.write_text(json.dumps(release, indent=2) + '\n')
print('Apple accepted both signed distribution packages.')
PY
