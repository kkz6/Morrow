#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
    echo "Usage: scripts/build-app.sh [release|debug]" >&2
    exit 1
fi
echo "$(xcodebuild -version | head -1) · macOS SDK $MORROW_SDK_VERSION"
xcrun swift build -c "$configuration" --sdk "$MORROW_SDK_PATH" "${MORROW_SDK_LINK_FLAGS[@]}"
binary_directory="$(xcrun swift build -c "$configuration" --show-bin-path)"
app="build/Morrow.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
rm -f "$app/Contents/MacOS/Morrow"
cp "$binary_directory/MorrowMenuBar" "$app/Contents/MacOS/MorrowMenuBar"
cp "$binary_directory/morrow-cli" "$app/Contents/MacOS/morrow"
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DTSDKName string macosx$MORROW_SDK_VERSION" "$app/Contents/Info.plist"
cp Resources/ZoneBar-LICENSE.txt "$app/Contents/Resources/"
if [[ ! -f Resources/AppIcon.icns ]]; then
    xcrun swift scripts/create-icon.swift .build/AppIcon.iconset
    iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$app/Contents/Resources/"
for morrow_binary in "$app/Contents/MacOS/MorrowMenuBar" "$app/Contents/MacOS/morrow"; do
    morrow_recorded_sdk="$(otool -l "$morrow_binary" | awk '/LC_BUILD_VERSION/{inside=1} inside && $1=="sdk"{print $2; exit}')"
    if [[ "$morrow_recorded_sdk" != "$MORROW_SDK_VERSION" ]]; then
        echo "Incorrect SDK recorded in $morrow_binary: $morrow_recorded_sdk (expected $MORROW_SDK_VERSION)" >&2
        exit 1
    fi
done
codesign --force --sign - "$app/Contents/MacOS/morrow"
codesign --force --sign - "$app"
ln -sfn Morrow.app/Contents/MacOS/morrow build/morrow
echo "Built $(pwd)/$app"
du -sh "$app"
