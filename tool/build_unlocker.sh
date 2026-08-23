#!/usr/bin/env bash
#
# Builds Vynic Unlocker — and only that.
#
# The POS and the Unlocker are separate Flutter apps on purpose: `flutter build
# windows` in pos_app_client must never pull the signing tool in, or a customer
# ends up with a copy of the thing that makes their locks.
#
#   ./tool/build_unlocker.sh              # build for this machine
#   ./tool/build_unlocker.sh windows      # build the Windows executable
#   ./tool/build_unlocker.sh macos
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/pos_app_devtool"

# Default to whatever this machine can actually build.
if [ $# -ge 1 ]; then
  PLATFORM="$1"
else
  case "$(uname -s)" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
    *)      PLATFORM="windows" ;;
  esac
fi

case "$PLATFORM" in
  windows|macos|linux) ;;
  *)
    echo "Unknown platform '$PLATFORM'. Use windows, macos or linux." >&2
    exit 64
    ;;
esac

echo "Building Vynic Unlocker for $PLATFORM…"
cd "$APP_DIR"
flutter pub get
flutter build "$PLATFORM" --release

case "$PLATFORM" in
  windows) OUTPUT="$APP_DIR/build/windows/x64/runner/Release" ;;
  macos)   OUTPUT="$APP_DIR/build/macos/Build/Products/Release" ;;
  linux)   OUTPUT="$APP_DIR/build/linux/x64/release/bundle" ;;
esac

echo ""
echo "Done. Built to:"
echo "  $OUTPUT"
echo ""
echo "This binary carries no private key — it reads one from disk at startup."
echo "Keep it on your own machine anyway; it is not a customer deliverable."
