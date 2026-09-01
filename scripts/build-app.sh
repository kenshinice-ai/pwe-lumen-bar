#!/bin/bash
# Builds Lumen.app from the SwiftPM products.
#
# SwiftPM produces a bare executable; a menu bar app needs a bundle with an
# Info.plist (LSUIElement keeps it out of the Dock) and a signature, so we
# assemble one here rather than carrying an Xcode project around.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
# The bundle declares macOS 26 while the package compiles against a 14.0
# deployment target. That is deliberate: the low floor is what stops any API
# newer than 14 from creeping into the code unnoticed, and the declared floor
# is the oldest system the app has actually been reasoned about on. Everything
# version-sensitive here is private and resolved at run time — `lumenctl compat`
# checks it on the machine in front of you.
APP="build/Lumen.app"
VERSION="0.1.0"

echo "==> generating vector icons"
swift scripts/make-icons.swift .
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product Lumen
swift build -c "$CONFIG" --product lumenctl

BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Lumen" "$APP/Contents/MacOS/Lumen"
cp "$BIN/lumenctl" "$APP/Contents/Resources/lumenctl"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.pdf "$APP/Contents/Resources/MenuBarIcon.pdf"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Lumen</string>
    <key>CFBundleDisplayName</key><string>Lumen</string>
    <key>CFBundleIdentifier</key><string>com.leeliu.lumen</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Lumen</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.leeliu.lumen.url</string>
            <key>CFBundleURLSchemes</key><array><string>lumen</string></array>
        </dict>
    </array>
    <key>NSHumanReadableCopyright</key><string>Lumen</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for local use. The private display APIs need no
# entitlements, but an unsigned bundle gets killed on launch.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1
echo "==> built $APP"
codesign -dv "$APP" 2>&1 | grep -E "Signature|Identifier" || true
