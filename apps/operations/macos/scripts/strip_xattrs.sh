#!/bin/sh
# Strip extended attributes that break macOS codesign.
# Desktop, iCloud Drive, and cloud-sync folders often add FinderInfo/provenance
# attributes that cause "resource fork, Finder information, or similar detritus
# not allowed" during CodeSign.

strip_path() {
  target="$1"
  if [ ! -e "$target" ]; then
    return 0
  fi
  /usr/bin/xattr -cr "$target" 2>/dev/null || true
  for attr in com.apple.FinderInfo com.apple.provenance com.apple.ResourceFork; do
    /usr/bin/xattr -r -d "$attr" "$target" 2>/dev/null || true
  done
}

if [ "$#" -gt 0 ]; then
  for target in "$@"; do
    strip_path "$target"
  done
else
  strip_path "${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
  strip_path "${TARGET_BUILD_DIR}"
  strip_path "${BUILT_PRODUCTS_DIR}"
  strip_path "${PROJECT_DIR}/../build/macos"
fi

if [ -n "${DERIVED_FILE_DIR:-}" ]; then
  mkdir -p "${DERIVED_FILE_DIR}"
  /bin/date > "${DERIVED_FILE_DIR}/strip_xattrs.stamp"
fi
