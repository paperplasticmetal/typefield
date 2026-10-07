#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

app="dist/Typefield.app"
if [[ ! -d "$app" ]]; then
    echo "Build the app with bash build.sh before packaging the beta." >&2
    exit 1
fi

codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
output="${1:-dist/Typefield-${version}-beta.dmg}"
mkdir -p "$(dirname "$output")"

staging=$(mktemp -d "${TMPDIR:-/tmp/}typefield-beta.XXXXXX")
trap 'rm -rf "$staging"' EXIT

ditto "$app" "$staging/Typefield.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -ov -srcfolder "$staging" -volname "Typefield Beta" -format UDZO "$output"

shasum -a 256 "$output"
