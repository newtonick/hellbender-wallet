#!/bin/bash
set -euo pipefail

# build-release.sh — Produce a verifiable unsigned release archive.
# Usage: ./scripts/build-release.sh
#
# Output: /tmp/birch-build/birch.xcarchive

DERIVED_DATA="/tmp/birch-build"

echo "==> Cleaning previous build artifacts..."
rm -rf "$DERIVED_DATA"

echo "==> Archiving (unsigned, Release configuration)..."
xcodebuild archive \
  -scheme birch \
  -project birch.xcodeproj \
  -archivePath "$DERIVED_DATA/birch.xcarchive" \
  -derivedDataPath "$DERIVED_DATA" \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  | xcpretty && exit ${PIPESTATUS[0]}

echo "==> Archive complete: $DERIVED_DATA/birch.xcarchive"
