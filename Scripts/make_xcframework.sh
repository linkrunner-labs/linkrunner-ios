#!/usr/bin/env bash
set -euo pipefail
SCHEME="Linkrunner"
ARCHIVE_DIR="build"
FRAMEWORK="Linkrunner.xcframework"

rm -rf "$ARCHIVE_DIR" "$FRAMEWORK"

echo "▶︎ Archiving for device"
xcodebuild archive \
  -scheme "$SCHEME" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_DIR/ios.xcarchive" \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

echo "▶︎ Archiving for simulator (arm64 + x86_64)"
xcodebuild archive \
  -scheme "$SCHEME" \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "$ARCHIVE_DIR/iossim.xcarchive" \
  SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

echo "▶︎ Creating XCFramework"
xcodebuild -create-xcframework \
  -framework "$ARCHIVE_DIR/ios.xcarchive/Products/Library/Frameworks/$SCHEME.framework" \
  -framework "$ARCHIVE_DIR/iossim.xcarchive/Products/Library/Frameworks/$SCHEME.framework" \
  -output "$FRAMEWORK"

echo "✅  XCFramework created at $FRAMEWORK"
