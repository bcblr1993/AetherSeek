#!/bin/zsh
# Generates the Xcode project and builds AetherSeek.app into build/.
# Usage: scripts/build.sh [Debug|Release]
set -euo pipefail
cd "$(dirname "$0")/.."
configuration=${1:-Debug}
xcodegen generate --quiet
xcodebuild -project AetherSeek.xcodeproj -scheme AetherSeek -configuration "$configuration" \
  -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' -quiet build
echo "build/DerivedData/Build/Products/$configuration/AetherSeek.app"
