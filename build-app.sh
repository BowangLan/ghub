#!/usr/bin/env bash
# Build a GHub.app bundle from the SwiftPM executable.
# Usage: ./build-app.sh [debug|release]   (default: release)

set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="GHub"
APP_DIR="$APP_NAME.app"
BUNDLE_ID="com.local.ghub"

cd "$(dirname "$0")"

echo "▶ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "❌ executable not found at $BIN_PATH" >&2
    exit 1
fi

echo "▶ packaging $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>            <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>                  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>           <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>           <string>APPL</string>
  <key>CFBundleVersion</key>               <string>1</string>
  <key>CFBundleShortVersionString</key>    <string>0.1.0</string>
  <key>LSMinimumSystemVersion</key>        <string>14.0</string>
  <key>LSUIElement</key>                   <true/>
  <key>NSHighResolutionCapable</key>       <true/>
  <key>NSAppleEventsUsageDescription</key> <string>$APP_NAME runs git and gh to sync repository state.</string>
</dict>
</plist>
EOF

# Ad-hoc sign so Gatekeeper doesn't refuse.
codesign --force --sign - --timestamp=none "$APP_DIR" >/dev/null 2>&1 || true

echo "✓ built $APP_DIR"
echo "  run with: open $APP_DIR     (or)     $APP_DIR/Contents/MacOS/$APP_NAME"
