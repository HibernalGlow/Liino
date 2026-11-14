#!/bin/sh
# Cross-compiles the FRB library for Android and stages it into jniLibs.
#
# Usage (from anywhere):
#   apps/liino_app/tool/build_android_rust.sh          # arm64 device build
#   apps/liino_app/tool/build_android_rust.sh --all    # arm64 + x86_64 (emulator)
#
# Requires ANDROID_HOME (or android/local.properties) and a Rust toolchain with
# the Android targets installed. Override the toolchain with
# LIINO_RUST_TOOLCHAIN=/path/to/toolchain.
set -eu

APP_DIR=$(cd "$(dirname "$0")/.." && pwd)
REPO_ROOT=$(cd "$APP_DIR/../.." && pwd)
cd "$REPO_ROOT"

# Prefer the project's local.properties: the ambient ANDROID_HOME may point at
# a platform-tools-only cask without an NDK.
SDK_FROM_PROJECT=""
if [ -f "$APP_DIR/android/local.properties" ]; then
  SDK_FROM_PROJECT=$(sed -n 's/^sdk\.dir=//p' "$APP_DIR/android/local.properties")
fi
ANDROID_HOME=${SDK_FROM_PROJECT:-${ANDROID_HOME:-}}
if [ -z "${ANDROID_HOME:-}" ]; then
  echo "error: set ANDROID_HOME or create android/local.properties" >&2
  exit 1
fi

NDK=$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1)
if [ -z "${NDK:-}" ]; then
  echo "error: no NDK under $ANDROID_HOME/ndk" >&2
  exit 1
fi
HOST_BIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"
CHANNEL=$(sed -n 's/^channel = "\(.*\)"/\1/p' "$REPO_ROOT/rust-toolchain.toml")
TOOLCHAIN=${LIINO_RUST_TOOLCHAIN:-$HOME/.rustup/toolchains/${CHANNEL}-aarch64-apple-darwin}
if [ ! -x "$TOOLCHAIN/bin/cargo" ]; then
  echo "error: Rust toolchain not found at $TOOLCHAIN" >&2
  echo "       install with: rustup toolchain install $CHANNEL --component clippy" >&2
  echo "       and:         rustup target add aarch64-linux-android --toolchain $CHANNEL" >&2
  exit 1
fi

# MicYou's audio core links AAudio, which the NDK only provides for API 26+.
API=26

build_target() {
  triple=$1
  abi=$2
  upper=$(echo "$triple" | tr 'a-z-' 'A-Z_')
  under=$(echo "$triple" | tr '-' '_')

  echo "==> building $triple ($abi)"
  env RUSTC="$TOOLCHAIN/bin/rustc" \
      RUSTDOC="$TOOLCHAIN/bin/rustdoc" \
      RUSTC_WRAPPER= \
      "CARGO_TARGET_${upper}_LINKER=$HOST_BIN/${triple}${API}-clang" \
      "CC_${under}=$HOST_BIN/${triple}${API}-clang" \
      "AR_${under}=$HOST_BIN/llvm-ar" \
      "RANLIB_${under}=$HOST_BIN/llvm-ranlib" \
      "$TOOLCHAIN/bin/cargo" build --release --target "$triple" -p liino_api

  mkdir -p "$APP_DIR/android/app/src/main/jniLibs/$abi"
  cp "$REPO_ROOT/target/$triple/release/libliino_api.so" \
     "$APP_DIR/android/app/src/main/jniLibs/$abi/libliino_api.so"
}

build_target aarch64-linux-android arm64-v8a
if [ "${1:-}" = "--all" ]; then
  build_target x86_64-linux-android x86_64
fi

echo "Staged Android libraries under $APP_DIR/android/app/src/main/jniLibs"
