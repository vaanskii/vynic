#!/usr/bin/env bash
# Configures Flutter Apple (iOS/macOS) builds when the repo lives on iCloud Desktop.
#
# Xcode code signing fails with "resource fork, Finder information, or similar detritus
# not allowed" when build artifacts are written under ~/Desktop. Redirecting the Flutter
# build directory to ~/Developer avoids that.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR_REL="../../../Developer/vynic_pos_build"
BUILD_DIR_ABS="$(cd "$ROOT" && cd "$BUILD_DIR_REL" && pwd)"

mkdir -p "$BUILD_DIR_ABS"

echo "Using Flutter build directory: $BUILD_DIR_ABS"
flutter config --build-dir="$BUILD_DIR_REL"

cd "$ROOT/ios"
pod install

cd "$ROOT/macos"
pod install

echo ""
echo "Apple build setup complete."
echo "Run the app with: ./scripts/flutter.sh run -d macos"
echo "              or: ./scripts/flutter.sh run -d \"iPhone\""
