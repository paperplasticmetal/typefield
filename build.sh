#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python3 scripts/localization/generate.py --check
SPARKLE="$(bash scripts/updater/prepare-sparkle.sh)"
APP="dist/Typefield.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" .build/module-cache
cp Resources/Info.plist "$APP/Contents/Info.plist"
for localization in Sources/Localizations/*.lproj; do
    ditto "$localization" "$APP/Contents/Resources/$(basename "$localization")"
done
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp Resources/GoogleVariableFonts.json "$APP/Contents/Resources/GoogleVariableFonts.json"
cp "$SPARKLE/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
ditto Resources/FigmaImport "$APP/Contents/Resources/FigmaImport"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
swiftc -warnings-as-errors -swift-version 5 -O -module-cache-path .build/module-cache -target arm64-apple-macosx13.0 \
    -D TYPEFIELD_DIRECT_DISTRIBUTION -F "$SPARKLE" -framework Sparkle \
    -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
    Sources/*.swift -o "$APP/Contents/MacOS/Typefield"
# Sign inside out. --deep is only used for verification, never for signing.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
for HELPER in "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
              "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" \
              "$FRAMEWORK/Versions/B/Updater.app" \
              "$FRAMEWORK/Versions/B/Autoupdate"; do
    codesign --force --sign - --timestamp=none --preserve-metadata=entitlements "$HELPER"
done
codesign --force --sign - --timestamp=none "$FRAMEWORK"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/Typefield" --self-test
