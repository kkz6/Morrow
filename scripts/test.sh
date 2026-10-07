#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
xcrun swift test --sdk "$MORROW_SDK_PATH" "${MORROW_SDK_LINK_FLAGS[@]}" "$@"
