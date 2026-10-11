#!/usr/bin/env python3
"""Import CI signing material privately; never print credential values."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cleanup', action='store_true')
options = parser.parse_args()
directory = Path(os.environ.get('RUNNER_TEMP', '/tmp')) / 'morrow-signing'
state_path = directory / 'state.json'

def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f'{Path(args[0]).name} {args[1]} failed; signing material was not printed.')
    return result.stdout

def private_write(path, data):
    path.write_bytes(data)
    path.chmod(0o600)

try:
    if options.cleanup:
        if state_path.exists():
            state = json.loads(state_path.read_text())
            run('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *state['search'])
            subprocess.run(['/usr/bin/security', 'delete-keychain', state['keychain']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if directory.exists():
            import shutil
            shutil.rmtree(directory)
        sys.exit(0)
    required = ['MORROW_CERTIFICATE_P12_BASE64', 'MORROW_CERTIFICATE_PASSWORD', 'MORROW_NOTARY_KEY_BASE64', 'MORROW_NOTARY_KEY_ID', 'MORROW_NOTARY_ISSUER_ID', 'MORROW_EXPECTED_TEAM']
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError('Missing release settings: ' + ', '.join(missing))
    if not re.fullmatch(r'[A-Z0-9]{10}', os.environ['MORROW_EXPECTED_TEAM']):
        raise RuntimeError('MORROW_EXPECTED_TEAM must be an Apple Team ID.')
    directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    certificate = directory / 'certificate.p12'
    notary_key = directory / 'notary.p8'
    private_write(certificate, base64.b64decode(os.environ['MORROW_CERTIFICATE_P12_BASE64'], validate=True))
    private_write(notary_key, base64.b64decode(os.environ['MORROW_NOTARY_KEY_BASE64'], validate=True))
    keychain = directory / 'release.keychain-db'
    search = shlex.split(run('/usr/bin/security', 'list-keychains', '-d', 'user'))
    password = secrets.token_urlsafe(36)
    private_write(state_path, json.dumps({'keychain': str(keychain), 'search': search}).encode())
    run('/usr/bin/security', 'create-keychain', '-p', password, str(keychain))
    run('/usr/bin/security', 'set-keychain-settings', '-lut', '21600', str(keychain))
    run('/usr/bin/security', 'unlock-keychain', '-p', password, str(keychain))
    run('/usr/bin/security', 'import', str(certificate), '-P', os.environ['MORROW_CERTIFICATE_PASSWORD'], '-k', str(keychain), '-T', '/usr/bin/codesign')
    run('/usr/bin/security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain))
    run('/usr/bin/security', 'list-keychains', '-d', 'user', '-s', str(keychain), *search)
    identities = run('/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning', str(keychain))
    matches = re.findall(r'([0-9A-F]{40}) "Developer ID Application: [^\n]+ \(([A-Z0-9]{10})\)"', identities)
    matching = [fingerprint for fingerprint, team in matches if team == os.environ['MORROW_EXPECTED_TEAM']]
    if len(matching) != 1:
        raise RuntimeError('The certificate must contain one valid Developer ID Application identity for the configured team.')
    run('/usr/bin/xcrun', 'notarytool', 'store-credentials', 'morrow-release', '--key', str(notary_key), '--key-id', os.environ['MORROW_NOTARY_KEY_ID'], '--issuer', os.environ['MORROW_NOTARY_ISSUER_ID'], '--keychain', str(keychain))
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        output.write(f'MORROW_SIGNING_IDENTITY={matching[0]}\nMORROW_NOTARY_KEYCHAIN={keychain}\nMORROW_NOTARY_PROFILE=morrow-release\n')
    print('Developer ID and notarization credentials are available in a private temporary keychain.')
except Exception as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
