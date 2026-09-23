#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="dist/Typefield Sandbox.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/module-cache
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.typefield.sandbox' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Typefield Sandbox' "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/GoogleVariableFonts.json Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/"
ditto Resources/FigmaImport "$APP/Contents/Resources/FigmaImport"
swiftc -warnings-as-errors -swift-version 5 -O -module-cache-path .build/module-cache -target arm64-apple-macosx13.0 Sources/*.swift -o "$APP/Contents/MacOS/Typefield"
codesign --force --options runtime --sign - --entitlements Resources/Typefield.entitlements "$APP"
codesign --verify --deep --strict "$APP"
echo 'Sandbox development bundle created. This is not a distribution-signed App Store archive.'
