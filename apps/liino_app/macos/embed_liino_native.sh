#!/bin/sh
# Embed the Flutter Rust Bridge dylib and the liino daemon into the macOS app
# bundle.
# SRCROOT is <project>/apps/liino_app/macos, so ../../.. is the Cargo workspace root.
#
# Both binaries must be built for release before running `flutter build macos`:
#   cargo build --release -p liino_api -p liino-daemon
set -eu

WORKSPACE_ROOT="${SRCROOT}/../../.."
SRC_DYLIB="${WORKSPACE_ROOT}/target/release/libliino_api.dylib"
SRC_DAEMON="${WORKSPACE_ROOT}/target/release/liino-daemon"
FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Frameworks"
RESOURCES_DIR="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Resources"

if [ ! -f "${SRC_DYLIB}" ]; then
  echo "error: ${SRC_DYLIB} not found. Run 'cargo build --release -p liino_api -p liino-daemon' first." >&2
  exit 1
fi
if [ ! -f "${SRC_DAEMON}" ]; then
  echo "error: ${SRC_DAEMON} not found. Run 'cargo build --release -p liino_api -p liino-daemon' first." >&2
  exit 1
fi

mkdir -p "${FRAMEWORKS_DIR}" "${RESOURCES_DIR}"
cp -f "${SRC_DYLIB}" "${FRAMEWORKS_DIR}/libliino_api.dylib"
codesign --force --sign - "${FRAMEWORKS_DIR}/libliino_api.dylib"
echo "Embedded ${FRAMEWORKS_DIR}/libliino_api.dylib"

cp -f "${SRC_DAEMON}" "${RESOURCES_DIR}/liino-daemon"
chmod +x "${RESOURCES_DIR}/liino-daemon"
codesign --force --sign - "${RESOURCES_DIR}/liino-daemon"
echo "Embedded ${RESOURCES_DIR}/liino-daemon"

"${SRCROOT}/bt_helper/build.sh" "${RESOURCES_DIR}"
echo "Embedded ${RESOURCES_DIR}/liino-bt-helper"
