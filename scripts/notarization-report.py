#!/usr/bin/env python3
"""Retrieve non-secret Apple diagnostics through the CI's temporary profile."""
import json
import os
from pathlib import Path
import re
import subprocess

root = Path('.build/notarization-diagnostics')
root.mkdir(parents=True, exist_ok=True)
auth = ['--keychain-profile', os.environ['MORROW_NOTARY_PROFILE'], '--keychain', os.environ['MORROW_NOTARY_KEYCHAIN']]
result = subprocess.check_output(['xcrun', 'notarytool', 'history', *auth, '--output-format', 'json'], text=True)
(root / 'history.json').write_text(result)
requested = os.environ.get('MORROW_SUBMISSION_ID', '')
if requested:
    if not re.fullmatch(r'[A-Fa-f0-9-]{36}', requested):
        raise SystemExit('Use a submission UUID.')
    submissions = [{'id': requested}]
else:
    submissions = [item for item in json.loads(result).get('history', []) if item.get('status') == 'Invalid'][:10]
for item in submissions:
    submission = item['id']
    if not re.fullmatch(r'[A-Fa-f0-9-]{36}', submission):
        raise SystemExit('Invalid Apple submission ID.')
    target = root / (submission + '.json')
    subprocess.run(['xcrun', 'notarytool', 'log', submission, *auth, str(target)], check=True)
    report = json.loads(target.read_text())
    print(submission, report.get('status'), report.get('statusSummary'))
    for issue in (report.get('issues') or [])[:30]:
        print(issue.get('severity'), issue.get('path'), issue.get('message'))
