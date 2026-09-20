#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
destination="${1:-/Applications/FontShelf.app}"
parent="$(dirname "$destination")"

bash build.sh
mkdir -p "$parent"
ditto dist/FontShelf.app "$destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination" >/dev/null 2>&1 || true

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$destination/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$destination/Contents/Info.plist")
echo "Installed FontShelf ${version} (${build}) at ${destination}"
