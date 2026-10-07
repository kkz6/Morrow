#!/bin/bash
# Shared by app, CLI, and test builds. Keep the user's global xcode-select intact.
if [[ -z "${DEVELOPER_DIR:-}" || "$DEVELOPER_DIR" == */CommandLineTools ]]; then
    morrow_xcode_directory="$(python3 - <<'PY'
from pathlib import Path
import plistlib
choices=[]
for app in Path('/Applications').glob('Xcode*.app'):
    try:
        data=plistlib.loads((app/'Contents/Info.plist').read_bytes())
        version=tuple(int(x) for x in data['CFBundleShortVersionString'].split('.'))
        choices.append((version, str(app/'Contents/Developer')))
    except (OSError, ValueError, KeyError):
        pass
if choices: print(max(choices)[1])
PY
)"
    if [[ -z "$morrow_xcode_directory" ]]; then
        echo "A full Xcode installation is required. Set DEVELOPER_DIR if Xcode is in a custom location." >&2
        exit 1
    fi
    export DEVELOPER_DIR="$morrow_xcode_directory"
fi
MORROW_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MORROW_SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
MORROW_SDK_LINK_FLAGS=(-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$MORROW_SDK_VERSION")
