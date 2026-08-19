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
    BASE="https://raw.githubusercontent.com/$REPO/main"
else
    BASE="https://raw.githubusercontent.com/$REPO/$VERSION"
fi

if curl -fsSL "$BASE/ORTracker.swift" -o "$TMPDIR/ORTracker.swift" 2>/dev/null && \
   curl -fsSL "$BASE/or_usage.py" -o "$TMPDIR/or_usage.py" 2>/dev/null; then
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
  <string>1.1.0</string>
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

# --- Install Python backend ---
mkdir -p "$CONFIG_DIR"
cp "$TMPDIR/or_usage.py" "$CONFIG_DIR/or_usage.py"

# --- Save API key ---
echo "{\"api_key\": \"$API_KEY\"}" > "$CONFIG_DIR/config"
chmod 600 "$CONFIG_DIR/config"

# --- Auto-start via launchd ---
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$HOME/Library/LaunchAgents/com.ortracker.menubar.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.ortracker.menubar</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>$INSTALL_DIR/$APP_NAME.app</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>ProcessType</key>
  <string>Interactive</string>
</dict>
</plist>
EOF
launchctl load "$HOME/Library/LaunchAgents/com.ortracker.menubar.plist" 2>/dev/null || true

echo -e ""
echo -e "  ${GREEN}✓ ORTracker installed to /Applications${NC}"
echo -e "  ${GREEN}✓ Auto-start configured${NC}"
echo -e "  ${GREEN}✓ Python backend at $CONFIG_DIR/or_usage.py${NC}"
echo ""

# Track install
curl -fsSL "https://ortracker.yates.id/track-install" &>/dev/null &

echo -e "  ${BOLD}Getting started:${NC}"
echo "   The app is now launching in your menu bar."
echo "   Look for the OpenRouter logo in the top-right menu bar."
echo ""
echo -e "  ${BOLD}To uninstall:${NC}"
echo "   rm -rf /Applications/ORTracker.app ~/.ortracker"
echo "   launchctl unload ~/Library/LaunchAgents/com.ortracker.menubar.plist"
echo "   rm ~/Library/LaunchAgents/com.ortracker.menubar.plist"
echo ""