#!/bin/bash
set -euo pipefail
archive="${1:?Usage: verify-store-archive.sh ARCHIVE TEAM_ID BUNDLE_ID}"
team="${2:?Set the expected team identifier}"
bundle="${3:?Set the expected bundle identifier}"
archive="$(cd "$archive" && pwd)"
cd "$(dirname "$0")"
app="$archive/Products/Applications/Typefield.app"
[[ -d "$app" ]] || { echo "Typefield.app is missing from $archive" >&2; exit 1; }
info="$app/Contents/Info.plist"
actual_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")
[[ "$actual_bundle" == "$bundle" ]] || { echo "Bundle ID mismatch: $actual_bundle" >&2; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")
[[ "$version" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info-Store.plist)" ]] || { echo 'Archive version differs from the Store plist.' >&2; exit 1; }
[[ "$build" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info-Store.plist)" ]] || { echo 'Archive build differs from the Store plist.' >&2; exit 1; }
[[ -f "$app/Contents/Resources/PrivacyInfo.xcprivacy" ]] || { echo 'Privacy manifest is missing.' >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$app"
signature=$(codesign -dv --verbose=4 "$app" 2>&1)
[[ "$signature" == *"TeamIdentifier=$team"* ]] || { echo 'The archive is not signed by the expected team.' >&2; exit 1; }
[[ "$signature" != *"Signature=adhoc"* ]] || { echo 'The archive has an ad-hoc signature.' >&2; exit 1; }
entitlements=$(mktemp)
trap 'rm -f "$entitlements"' EXIT
codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null
for key in com.apple.security.app-sandbox com.apple.security.files.bookmarks.app-scope com.apple.security.files.user-selected.read-write com.apple.security.network.client; do
  value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$entitlements" 2>/dev/null || true)
  [[ "$value" == true ]] || { echo "Missing required entitlement: $key" >&2; exit 1; }
done
echo "Verified team-signed Store archive: $actual_bundle $version ($build), team $team, entitlements and privacy manifest. Organizer still must apply distribution signing and validate the app."
