#!/bin/bash
# Pinned official Sparkle distribution; no package-manager or global install.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION=2.10.0
SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
SIZE=16319840
CACHE="$ROOT/.build/sparkle"
ARCHIVE="$CACHE/Sparkle-$VERSION.tar.xz"
DESTINATION="$CACHE/$VERSION"
mkdir -p "$CACHE"
if [[ ! -f "$ARCHIVE" ]]; then
    DOWNLOAD="$(mktemp "$CACHE/download.XXXXXX")"
    trap 'rm -f "$DOWNLOAD"' EXIT
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
        "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" \
        --output "$DOWNLOAD"
    [[ "$(stat -f %z "$DOWNLOAD")" == "$SIZE" ]] || { echo 'Sparkle archive size mismatch' >&2; exit 1; }
    [[ "$(shasum -a 256 "$DOWNLOAD" | awk '{print $1}')" == "$SHA256" ]] || { echo 'Sparkle archive checksum mismatch' >&2; exit 1; }
    mv "$DOWNLOAD" "$ARCHIVE"
    trap - EXIT
fi
[[ "$(stat -f %z "$ARCHIVE")" == "$SIZE" ]] || { echo 'Cached Sparkle archive size mismatch' >&2; exit 1; }
[[ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" == "$SHA256" ]] || { echo 'Cached Sparkle archive checksum mismatch' >&2; exit 1; }
# Re-extract from the verified archive, so cached executable contents cannot drift.
STAGING="$(mktemp -d "$CACHE/extract.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
tar -xf "$ARCHIVE" -C "$STAGING" ./Sparkle.framework ./bin ./LICENSE ./INSTALL
codesign --verify --deep --strict "$STAGING/Sparkle.framework"
[[ -L "$STAGING/Sparkle.framework/Versions/Current" && -x "$STAGING/bin/sign_update" ]]
rm -rf "$DESTINATION"
mv "$STAGING" "$DESTINATION"
trap - EXIT
printf '%s\n' "$DESTINATION"
