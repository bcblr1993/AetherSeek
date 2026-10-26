#!/bin/zsh
# Builds a Developer ID signed Release, notarizes and staples the app and a DMG.
# Usage: scripts/release.sh [notary-keychain-profile]   (default: $NOTARY_PROFILE or AetherRoute-Notary)
# Output: build/release/<version>-<build>/AetherSeek-<version>.dmg (+ notarized .zip and notary logs)
set -euo pipefail
cd "$(dirname "$0")/.."
profile=${1:-${NOTARY_PROFILE:-AetherRoute-Notary}}
identity="Developer ID Application: YanNan Chen (5984KQD4D7)"

xcodegen generate --quiet
xcodebuild -project AetherSeek.xcodeproj -scheme AetherSeek -configuration Release \
  -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' -quiet clean build
built=build/DerivedData/Build/Products/Release/AetherSeek.app

plist=$built/Contents/Info.plist
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
out=build/release/$version-$build
rm -rf "$out"
mkdir -p "$out"

# Gatekeeper rejects anything without hardened runtime, a secure timestamp or with get-task-allow.
test "$(lipo -archs "$built/Contents/MacOS/AetherSeek")" = arm64
codesign --verify --deep --strict "$built"
details=$(codesign -dv --verbose=4 "$built" 2>&1)
grep -q '^Timestamp=' <<<"$details" || { echo "missing secure timestamp" >&2; exit 1; }
grep -q 'flags=.*runtime' <<<"$details" || { echo "hardened runtime not enabled" >&2; exit 1; }
if codesign -d --entitlements - "$built" 2>/dev/null | grep -q get-task-allow; then
  echo "get-task-allow present; not a distributable build" >&2
  exit 1
fi

notarize() {
  local file=$1 log=$2
  xcrun notarytool submit "$file" --keychain-profile "$profile" --wait --timeout 30m \
    --output-format json > "$log"
  local result=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status"))' "$log")
  if [[ $result != Accepted ]]; then
    local id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id"))' "$log")
    xcrun notarytool log "$id" --keychain-profile "$profile" >&2 || true
    echo "notarization $result: $file" >&2
    exit 1
  fi
}

app=$out/AetherSeek.app
ditto "$built" "$app"
ditto -c -k --keepParent "$app" "$out/notary-app.zip"
notarize "$out/notary-app.zip" "$out/notary-app.json"
xcrun stapler staple "$app"
rm "$out/notary-app.zip"
ditto -c -k --keepParent "$app" "$out/AetherSeek-$version.zip"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/AetherSeek.app"
ln -s /Applications "$stage/Applications"
dmg=$out/AetherSeek-$version.dmg
hdiutil create -quiet -volname "AetherSeek $version" -srcfolder "$stage" -fs APFS -format ULFO "$dmg"
codesign --sign "$identity" --timestamp "$dmg"
notarize "$dmg" "$out/notary-dmg.json"
xcrun stapler staple "$dmg"

spctl --assess --type execute --verbose=2 "$app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
xcrun stapler validate "$dmg"
echo "$dmg"
