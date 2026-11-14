#!/bin/sh
# Builds the macOS Bluetooth helper (ADR-0009). The daemon spawns it and treats
# stdin/stdout as the RFCOMM byte stream.
set -eu

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
OUT_DIR="${1:-$SRC_DIR/../../build/bt_helper}"
mkdir -p "$OUT_DIR"

swiftc -O "$SRC_DIR/main.swift" \
    -o "$OUT_DIR/liino-bt-helper" \
    -framework IOBluetooth
codesign --force --sign - "$OUT_DIR/liino-bt-helper"
echo "Built $OUT_DIR/liino-bt-helper"
