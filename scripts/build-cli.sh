#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
configuration="${1:-release}"
echo "$(xcodebuild -version | head -1) · macOS SDK $MORROW_SDK_VERSION"
xcrun swift build -c "$configuration" --product morrow-cli --sdk "$MORROW_SDK_PATH" "${MORROW_SDK_LINK_FLAGS[@]}"
morrow_cli_directory="$(xcrun swift build -c "$configuration" --show-bin-path)"
mkdir -p build/cli
cp "$morrow_cli_directory/morrow-cli" build/cli/morrow
codesign --force --sign - build/cli/morrow
echo "CLI: $(pwd)/build/cli/morrow"
