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
app="${MORROW_APP_OUTPUT:-build/Morrow.app}"
if [[ "$app" != *.app ]]; then
    echo "MORROW_APP_OUTPUT must name an .app bundle." >&2
    exit 1
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
rm -f "$app/Contents/MacOS/Morrow"
cp "$binary_directory/MorrowMenuBar" "$app/Contents/MacOS/MorrowMenuBar"
cp "$binary_directory/morrow-cli" "$app/Contents/MacOS/morrow"
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DTSDKName string macosx$MORROW_SDK_VERSION" "$app/Contents/Info.plist"
cp -R "$binary_directory/Morrow_MorrowApp.bundle" "$app/Contents/Resources/"
cp Resources/ThirdPartyNotices.txt "$app/Contents/Resources/"
mkdir -p "$app/Contents/Library/LaunchDaemons"
cp Resources/dev.morrow.setup.plist "$app/Contents/Library/LaunchDaemons/"
rm -f "$app/Contents/Resources/ZoneBar-LICENSE.txt"
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
morrow_signing_identity="${MORROW_SIGNING_IDENTITY:--}"
if [[ "$morrow_signing_identity" == "-" ]]; then
    codesign --force --sign - "$app/Contents/MacOS/morrow"
    codesign --force --sign - "$app"
else
    codesign --force --sign "$morrow_signing_identity" --options runtime --timestamp "$app/Contents/MacOS/morrow"
    codesign --force --sign "$morrow_signing_identity" --options runtime --timestamp "$app"
    morrow_app_team="$(codesign -dv --verbose=4 "$app" 2>&1 | awk -F= '$1=="TeamIdentifier" {print $2}')"
    morrow_cli_team="$(codesign -dv --verbose=4 "$app/Contents/MacOS/morrow" 2>&1 | awk -F= '$1=="TeamIdentifier" {print $2}')"
    if [[ -z "$morrow_app_team" || "$morrow_app_team" == "not set" || "$morrow_app_team" != "$morrow_cli_team" ]]; then
        echo "Background grouping requires the app and launcher to share a valid Apple signing team." >&2
        exit 1
    fi
    codesign --verify --strict "$app/Contents/MacOS/morrow"
    codesign --verify --strict "$app"
fi
if [[ "$app" == "build/Morrow.app" ]]; then
    ln -sfn Morrow.app/Contents/MacOS/morrow build/morrow
fi
if [[ "$app" == /* ]]; then
    echo "Built $app"
else
    echo "Built $(pwd)/$app"
fi
du -sh "$app"
