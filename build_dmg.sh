#!/bin/bash
# Build ORTracker DMG for distribution
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_DIR/build"
APP_NAME="ORTracker"
APP_VERSION="1.1.0"
IDENTIFIER="com.mikeyates.ortracker"

echo "==> Compiling ORTracker..."
cd "$REPO_DIR"
swiftc -O ORTracker.swift -o "$BUILD_DIR/ORTracker"

echo "==> Creating .app bundle..."
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/ORTracker" "$APP_BUNDLE/Contents/MacOS/ORTracker"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>ORTracker</string>
  <key>CFBundleIdentifier</key>
  <string>$IDENTIFIER</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

echo "==> Creating app icon..."
ICON_SRC="$REPO_DIR/assets/icon_1024.png"
ICONSET_DIR="$BUILD_DIR/$APP_NAME.iconset"
mkdir -p "$ICONSET_DIR"

# Generate all required icon sizes
for SIZE in 16 32 128 256 512; do
    sips -z $SIZE $SIZE "$ICON_SRC" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" &>/dev/null
    sips -z $((SIZE*2)) $((SIZE*2)) "$ICON_SRC" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" &>/dev/null
done
# Special case
cp "$ICON_SRC" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns -o "$BUILD_DIR/$APP_NAME.icns" "$ICONSET_DIR"
cp "$BUILD_DIR/$APP_NAME.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Remove the iconset
rm -rf "$ICONSET_DIR"

echo "==> Code-sign (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "==> Creating DMG..."
DMG_PATH="$BUILD_DIR/$APP_NAME-$APP_VERSION.dmg"
rm -f "$DMG_PATH"

# Create temporary DMG
TMP_DMG="$BUILD_DIR/tmp.dmg"
STAGING="$BUILD_DIR/dmg_staging"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"

# Symlink /Applications for drag-install
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" &>/dev/null

# Cleanup
rm -rf "$STAGING" "$TMP_DMG"
rm -f "$BUILD_DIR/ORTracker"
rm -f "$BUILD_DIR/$APP_NAME.icns"

echo ""
echo "==> DMG built: $DMG_PATH"
echo "    ($(du -h "$DMG_PATH" | cut -f1))"