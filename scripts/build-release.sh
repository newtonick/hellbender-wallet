#!/bin/bash
set -euo pipefail

# build-release.sh — Produce a verifiable unsigned release archive.
# Usage: ./scripts/build-release.sh
#
# Output: /tmp/hellbender-build/hellbender.xcarchive

DERIVED_DATA="/tmp/hellbender-build"

echo "==> Cleaning previous build artifacts..."
rm -rf "$DERIVED_DATA"

echo "==> Archiving (unsigned, Release configuration)..."
xcodebuild archive \
  -scheme hellbender \
  -project hellbender.xcodeproj \
  -archivePath "$DERIVED_DATA/hellbender.xcarchive" \
  -derivedDataPath "$DERIVED_DATA" \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  | xcpretty && exit ${PIPESTATUS[0]}

echo "==> Archive complete: $DERIVED_DATA/hellbender.xcarchive"
