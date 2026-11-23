#!/usr/bin/env bash
# Build "Claude at a Glance.app" from the SwiftPM release binary.
# Usage: [VERSION=0.2.0] scripts/build-app.sh   (output: build/Claude at a Glance.app)
# VERSION (optional) is stamped into the app's Info.plist; default is the version in Resources/Info.plist.
# Builds a universal (arm64 + x86_64) binary; falls back to the native arch with a warning.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Claude at a Glance"
EXEC_NAME="ClaudeAtAGlance"
APP_DIR="build/${APP_NAME}.app"

ARCH_FLAGS=(--arch arm64 --arch x86_64)
if ! swift build -c release "${ARCH_FLAGS[@]}"; then
    echo "warning: universal build failed, falling back to native arch only" >&2
    ARCH_FLAGS=()
    swift build -c release
fi

BIN_PATH="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/${EXEC_NAME}"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "error: release binary not found at $BIN_PATH" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/${EXEC_NAME}"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

if [[ -n "${VERSION:-}" ]]; then
    PLIST="$APP_DIR/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$PLIST"
fi

codesign --force -s - "$APP_DIR"

echo "Built $APP_DIR (archs: $(lipo -archs "$APP_DIR/Contents/MacOS/${EXEC_NAME}"))"
