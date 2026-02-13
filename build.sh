#!/bin/bash
# Build Listen.app from SPM executable target
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_DIR="$SCRIPT_DIR/.build"
APP_NAME="Listen"
APP_BUNDLE="$SCRIPT_DIR/dist/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "==> Building $APP_NAME..."
swift build -c release 2>&1

EXECUTABLE="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$EXECUTABLE" ]; then
    echo "ERROR: Build failed — executable not found at $EXECUTABLE"
    exit 1
fi

echo "==> Packaging $APP_NAME.app..."

# Clean previous
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy executable
cp "$EXECUTABLE" "$MACOS_DIR/$APP_NAME"

# Copy Info.plist
cp "$SCRIPT_DIR/Listen/Resources/Info.plist" "$CONTENTS/Info.plist"

# Copy app icon
cp "$SCRIPT_DIR/Listen/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

# Copy menu bar icon
cp "$SCRIPT_DIR/Listen/Resources/MenuBarIconTemplate.png" "$RESOURCES_DIR/MenuBarIconTemplate.png"
cp "$SCRIPT_DIR/Listen/Resources/MenuBarIconTemplate@2x.png" "$RESOURCES_DIR/MenuBarIconTemplate@2x.png"

# Copy entitlements (used for signing)
cp "$SCRIPT_DIR/Listen/Resources/Listen.entitlements" "$CONTENTS/Listen.entitlements"

# Sign with developer identity (stable signature = TCC permissions survive rebuilds)
IDENTITY=$(security find-identity -v -p codesigning | head -1 | sed 's/.*"\(.*\)"/\1/')
echo "==> Signing with: $IDENTITY"
codesign --force --deep --sign "$IDENTITY" \
    --entitlements "$CONTENTS/Listen.entitlements" \
    "$APP_BUNDLE"

echo "==> Done! App bundle at: $APP_BUNDLE"
echo ""
echo "To install: cp -r \"$APP_BUNDLE\" /Applications/"
echo "To run:     open \"$APP_BUNDLE\""
