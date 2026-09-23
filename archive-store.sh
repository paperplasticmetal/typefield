#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -version >/dev/null || { echo 'Full Xcode 26 or newer is required; Command Line Tools cannot create this archive.' >&2; exit 1; }
: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team identifier}"
: "${APP_BUNDLE_ID:?Set APP_BUNDLE_ID to your registered app identifier}"
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo 'TEAM_ID must be a 10-character Apple Developer team identifier.' >&2; exit 1; }
[[ "$APP_BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || { echo 'Use a registered reverse-DNS production bundle identifier.' >&2; exit 1; }
case "$APP_BUNDLE_ID" in local.*) echo 'Replace the local development bundle identifier.' >&2; exit 1;; esac
archive="$PWD/dist/Typefield.xcarchive"
[[ ! -e "$archive" ]] || { echo "Move or remove the existing archive before creating a new one: $archive" >&2; exit 1; }
xcodebuild -project Typefield.xcodeproj -scheme Typefield -configuration Release -derivedDataPath "$PWD/.build/xcode" -destination 'generic/platform=macOS' -archivePath "$archive" DEVELOPMENT_TEAM="$TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$APP_BUNDLE_ID" SWIFT_TREAT_WARNINGS_AS_ERRORS=YES archive
./verify-store-archive.sh "$archive" "$TEAM_ID" "$APP_BUNDLE_ID"
echo 'Team-signed archive checked. Use Xcode Organizer to apply distribution signing, validate and upload to App Store Connect for TestFlight. Nothing has been uploaded.'
