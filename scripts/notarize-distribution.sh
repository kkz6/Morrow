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
import os
from pathlib import Path
import subprocess
import sys
output = Path(sys.argv[1])
result = json.loads((output / 'notarization.json').read_text())
if result.get('status') != 'Accepted' or not result.get('id'):
    if result.get('id'):
        log = output / 'notarization-log.json'
        diagnostic = subprocess.run(['xcrun', 'notarytool', 'log', result['id'],
            '--keychain-profile', os.environ['MORROW_NOTARY_PROFILE'],
            '--keychain', os.environ['MORROW_NOTARY_KEYCHAIN'], str(log)])
        if diagnostic.returncode == 0:
            report = json.loads(log.read_text())
            print(report.get('statusSummary'), flush=True)
            for issue in (report.get('issues') or [])[:30]:
                print(issue.get('severity'), issue.get('path'), issue.get('message'), flush=True)
    raise SystemExit('Apple did not accept these binaries; do not publish them.')
for path in output.glob('*-release.json'):
    release = json.loads(path.read_text())
    release['notarizationID'] = result['id']
    path.write_text(json.dumps(release, indent=2) + '\n')
print('Apple accepted the signed distribution packages.')
PY
