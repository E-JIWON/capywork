#!/bin/sh
# Builds CapyWork.app from source at the given path (default ~/Applications/CapyWork.app).
# Used by install.sh and the Homebrew formula.
set -e
cd "$(dirname "$0")/.."
APP="${1:-$HOME/Applications/CapyWork.app}"
VERSION="${CAPYWORK_VERSION:-1.0}"

# --disable-sandbox: SwiftPM's own sandbox can't nest inside Homebrew's build sandbox.
swift build -c release --disable-sandbox --product CapyWork >/dev/null
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp "$(swift build -c release --disable-sandbox --show-bin-path)/CapyWork" "$APP/Contents/MacOS/CapyWork"
cat > "$APP/Contents/Info.plist" <<INFO
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>CapyWork</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.capywork.app</string>
  <key>CFBundleName</key><string>CapyWork</string>
  <key>CFBundleDisplayName</key><string>카피 코드 바라</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
INFO
codesign --force --sign - "$APP" 2>/dev/null
