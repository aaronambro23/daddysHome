#!/bin/bash
#
# Builds Daddy.app — a real macOS application bundle.
#
# Why this exists: `swift build` produces a bare Unix executable. Run from a
# terminal, macOS never registers it as a foreground application — it inherits
# the terminal's activation context. The menu bar keeps saying "Terminal", and
# anything that pastes into "the focused app" (dictation, for one) pastes into
# the terminal instead of into Daddy. The app has to be a bundle with an
# Info.plist before the system will treat it as its own thing.
#
# Usage:  ./bundle.sh [debug|release]      (default: release)

set -euo pipefail

CONFIG="${1:-release}"
cd "$(dirname "$0")"

APP_NAME="Daddy's Home"
# The menu bar and the app switcher show the *executable's* name, so the binary
# is copied in as "Daddy" rather than "DaddyApp".
EXECUTABLE="Daddy"
BUILT_BINARY="DaddyApp"
BUNDLE_ID="com.aaronambrosi.daddy"
APP="build/${APP_NAME}.app"

echo "Building ($CONFIG)…"
swift build -c "$CONFIG"

BINARY=".build/${CONFIG}/${BUILT_BINARY}"
[ -f "$BINARY" ] || { echo "No binary at $BINARY"; exit 1; }

echo "Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "$BINARY" "${APP}/Contents/MacOS/${EXECUTABLE}"

# Copy app icon if it exists
if [ -f "DaddyApp.icns" ]; then
    cp "DaddyApp.icns" "${APP}/Contents/Resources/"
fi

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>       <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>        <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>        <string>${EXECUTABLE}</string>
    <key>CFBundleIconFile</key>          <string>DaddyApp</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.4.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key>    <string>26.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <!-- false = a normal app with a Dock icon and its own menu bar. -->
    <key>LSUIElement</key>               <false/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key>   <false/>
</dict>
</plist>
PLIST

# Ad-hoc signature. Unsigned bundles get inconsistent treatment from the
# window server and from anything that inspects the frontmost application.
codesign --force --sign - "$APP" 2>/dev/null || echo "  (ad-hoc signing skipped)"

echo
echo "Built ${APP}"
echo
echo "Run it:    open ${APP}"
echo "With logs: ${APP}/Contents/MacOS/${EXECUTABLE}"
