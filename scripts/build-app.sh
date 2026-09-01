#!/bin/bash
# Builds PWE Lumen Bar.app from the SwiftPM products.
#
# SwiftPM produces a bare executable; a menu bar app needs a bundle with an
# Info.plist (LSUIElement keeps it out of the Dock) and a signature, so we
# assemble one here rather than carrying an Xcode project around.
#
# This is the development build. `scripts/package.sh` is the one that signs,
# notarises and ships.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
# The bundle declares macOS 26 while the package compiles against a 14.0
# deployment target. That is deliberate: the low floor is what stops any API
# newer than 14 from creeping into the code unnoticed, and the declared floor
# is the oldest system the app has actually been reasoned about on. Everything
# version-sensitive here is private and resolved at run time — `pwelumenctl compat`
# checks it on the machine in front of you.
APP="build/PWE Lumen Bar.app"
VERSION="$(./scripts/version.sh)"

echo "==> generating vector icons"
# Compiled rather than run as a script because it shares BrandMark with the app:
# the wing in the icon and the wing in the interface are the same geometry, and
# a second copy of it is exactly how a mark drifts.
mkdir -p build
swiftc -O scripts/icon/main.swift Sources/LumenBarUI/Brand/BrandMark.swift \
  -o build/make-icons -framework AppKit
build/make-icons .
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product PWELumenBar
swift build -c "$CONFIG" --product pwelumenctl

BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/PWELumenBar" "$APP/Contents/MacOS/PWELumenBar"
cp "$BIN/pwelumenctl" "$APP/Contents/Resources/pwelumenctl"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.pdf "$APP/Contents/Resources/MenuBarIcon.pdf"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PWE Lumen Bar</string>
    <key>CFBundleDisplayName</key><string>PWE Lumen Bar</string>
    <key>CFBundleIdentifier</key><string>com.pwegroup.pwelumenbar</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>PWELumenBar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <!-- The app carries both languages in code (see L10n), so it declares both:
         that is what makes Locale.preferredLanguages report zh-Hans to a Chinese
         system instead of falling back to the development region. -->
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>zh-Hans</string></array>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.pwegroup.pwelumenbar.url</string>
            <key>CFBundleURLSchemes</key><array><string>pwelumen</string></array>
        </dict>
    </array>
    <key>NSHumanReadableCopyright</key><string>© 2026 PWE Group Pty Ltd · A PARADISE PRODUCTION</string>
</dict>
</plist>
PLIST

# Signing identity, in order of preference.
#
# This matters more here than in most apps: macOS ties an Accessibility grant to
# the code signature, so an ad-hoc signature — which changes on every single
# rebuild — silently revokes the permission the media keys need. Signing every
# development build with the same Developer ID certificate keeps that grant
# alive across rebuilds, which is the difference between "the F1 key works" and
# "the F1 key works until you rebuild".
IDENTITY="$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | grep -v CSSMERR | head -1 \
  | sed -E 's/.*"(.*)".*/\1/' || true)"

if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP" >/dev/null
else
  echo "==> no Developer ID identity found; falling back to ad-hoc"
  echo "    (every rebuild will revoke the Accessibility grant — media keys will need re-approving)"
  codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1
fi

echo "==> built $APP  ($VERSION)"
codesign -dv "$APP" 2>&1 | grep -E "Signature|Identifier|Authority" | head -4 || true
