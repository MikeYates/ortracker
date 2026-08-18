#!/bin/bash
set -e

REPO="mikeyates/ortracker"
VERSION="${1:-latest}"
APP_NAME="ORTracker"
INSTALL_DIR="/Applications"
CONFIG_DIR="$HOME/.ortracker"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}  ORTracker — OpenRouter Balance Tracker${NC}"
echo "  ==============================="
echo ""

# --- Check macOS ---
if [ "$(uname)" != "Darwin" ]; then
    echo -e "${RED}  Error: ORTracker requires macOS 13+.${NC}"
    exit 1
fi

# --- Check Xcode CLI tools ---
if ! xcode-select -p &>/dev/null; then
    echo -e "  ${YELLOW}Xcode Command Line Tools not found. Installing...${NC}"
    xcode-select --install
    echo "  Please re-run the installer after the tools finish installing."
    exit 1
fi

# --- API key ---
if [ -z "$OPENROUTER_API_KEY" ]; then
    if [ -f "$CONFIG_DIR/config" ]; then
        API_KEY=$(python3 -c "import json; print(json.load(open('$CONFIG_DIR/config')).get('api_key',''))" 2>/dev/null || echo "")
    fi
    if [ -z "$API_KEY" ]; then
        echo -e "  ${YELLOW}OpenRouter API key not found.${NC}"
        echo ""
        echo "  Get your key at: https://openrouter.ai/keys"
        echo ""
        read -p "  Enter your OpenRouter API key (sk-or-...): " API_KEY
        if [ -z "$API_KEY" ]; then
            echo -e "${RED}  No key provided. Aborting.${NC}"
            exit 1
        fi
    fi
else
    API_KEY="$OPENROUTER_API_KEY"
fi

echo -e "  ${GREEN}✓${NC} API key configured"

# --- Download ---
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo -n "  Downloading ORTracker..."
if [ "$VERSION" = "latest" ]; then
    SOURCE_URL="https://raw.githubusercontent.com/$REPO/main/ORTracker.swift"
else
    SOURCE_URL="https://raw.githubusercontent.com/$REPO/$VERSION/ORTracker.swift"
fi

if curl -fsSL "$SOURCE_URL" -o "$TMPDIR/ORTracker.swift" 2>/dev/null; then
    echo -e " ${GREEN}done${NC}"
else
    echo -e " ${RED}failed${NC}"
    exit 1
fi

# --- Compile ---
echo -n "  Compiling..."
if swiftc -O "$TMPDIR/ORTracker.swift" -o "$TMPDIR/ORTracker" 2>/dev/null; then
    echo -e " ${GREEN}done${NC}"
else
    echo -e " ${RED}compilation failed${NC}"
    exit 1
fi

# --- Create .app bundle ---
echo -n "  Creating app bundle..."
APP_BUNDLE="$TMPDIR/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$TMPDIR/ORTracker" "$APP_BUNDLE/Contents/MacOS/ORTracker"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>ORTracker</string>
  <key>CFBundleIdentifier</key>
  <string>com.mikeyates.ortracker</string>
  <key>CFBundleName</key>
  <string>ORTracker</string>
  <key>CFBundleDisplayName</key>
  <string>ORTracker</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF
echo -e " ${GREEN}done${NC}"

# --- Install ---
echo -n "  Installing to /Applications..."
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi
cp -R "$APP_BUNDLE" "$INSTALL_DIR/$APP_NAME.app"
codesign --force --deep --sign - "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
echo -e " ${GREEN}done${NC}"

# --- Save API key ---
mkdir -p "$CONFIG_DIR"
echo "{\"api_key\": \"$API_KEY\"}" > "$CONFIG_DIR/config"
chmod 600 "$CONFIG_DIR/config"

echo -e ""
echo -e "  ${GREEN}✓ ORTracker installed to /Applications${NC}"
echo ""
echo -e "  ${BOLD}Getting started:${NC}"
echo "   1. Open ORTracker from your Applications folder"
echo "   (or run: open /Applications/ORTracker.app)"
echo ""
echo -e "  ${BOLD}Menu bar:${NC}"
echo "   The app sits in your menu bar showing your OpenRouter balance"
echo "   Click to see: usage stats, auto-update toggle, check for updates"
echo ""
echo -e "  ${BOLD}Auto-updates:${NC}"
echo "   Enabled by default — updates silently in the background"
echo ""
echo -e "  ${BOLD}To uninstall:${NC}"
echo "   rm -rf /Applications/ORTracker.app ~/.ortracker"
echo ""

# Launch
open "/Applications/ORTracker.app"
echo -e "  ${GREEN}Launched!${NC} Look for the balance icon in your menu bar."
echo ""