#!/usr/bin/env bash
# Run Flutter with the project Apple build settings (see setup_apple_build.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR_REL="../../../Developer/vynic_pos_build"
CURRENT_BUILD_DIR="$(flutter config --list 2>/dev/null | sed -n 's/^build-dir: //p' | head -1 || true)"

if [[ "${CURRENT_BUILD_DIR:-build}" != "$BUILD_DIR_REL" ]]; then
  echo "Apple build directory is not configured (current: ${CURRENT_BUILD_DIR:-build})."
  echo "Running setup_apple_build.sh ..."
  "$ROOT/scripts/setup_apple_build.sh"
fi

exec flutter "$@"
