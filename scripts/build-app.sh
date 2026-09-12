#!/bin/bash
# Builds PWE Lumen Bar.app from the SwiftPM products.
#
#   ./scripts/build-app.sh              build and sign
#   ./scripts/build-app.sh --install    also copy it into /Applications and open it
#   ./scripts/build-app.sh --debug      build the debug configuration
#
# SwiftPM produces a bare executable; a menu bar app needs a bundle with an
# Info.plist (LSUIElement keeps it out of the Dock) and a signature, so we
# assemble one here rather than carrying an Xcode project around.
#
# This is the development build. `scripts/package.sh` is the one that ships.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="release"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --debug)   CONFIG="debug" ;;
    release|debug) CONFIG="$arg" ;;
    *) echo "✗ unknown option: $arg"; exit 1 ;;
  esac
done

# The bundle is assembled outside the repository on purpose.
#
# This project lives in iCloud Drive, and the file provider re-attaches
# `com.apple.FinderInfo` to anything inside it within seconds of it being
# written. codesign refuses to sign or verify a bundle carrying that xattr
# ("resource fork, Finder information, or similar detritus not allowed"), and
# stripping it does not help — it comes straight back. Anything that has to
# carry a signature is therefore built somewhere iCloud does not manage.
WORK="${TMPDIR:-/tmp}/pwelumenbar-build"
APP="$WORK/PWE Lumen Bar.app"
VERSION="$(./scripts/version.sh)"

# The bundle declares macOS 26 while the package compiles against a 14.0
# deployment target. That is deliberate: the low floor is what stops any API
# newer than 14 from creeping into the code unnoticed, and the declared floor
# is the oldest system the app has actually been reasoned about on. Everything
# version-sensitive here is private and resolved at run time — `pwelumenctl compat`
# checks it on the machine in front of you.

# Only when the geometry or the generator actually changed.
#
# These outputs are committed, and Quartz stamps a fresh CreationDate and file ID into every PDF
# it writes — so regenerating unconditionally left `Resources/AppIcon.pdf` and
# `Resources/MenuBarIcon.pdf` modified after every single build, with identical artwork inside.
# That costs twice: the first step of cutting a release is "working tree must be empty", and a
# tree that is always dirty is a tree nobody reads, which is where a real change goes to hide.
ICON_SOURCES=(scripts/icon/main.swift Sources/LumenBarUI/Brand/BrandMark.swift)
icons_stale() {
  [[ ! -f Resources/AppIcon.icns ]] && return 0
  local src
  for src in "${ICON_SOURCES[@]}"; do
    [[ "$src" -nt Resources/AppIcon.icns ]] && return 0
  done
  return 1
}

if icons_stale; then
  echo "==> generating vector icons"
  # Compiled rather than run as a script because it shares BrandMark with the app:
  # the wing in the icon and the wing in the interface are the same geometry, and
  # a second copy of it is exactly how a mark drifts.
  mkdir -p build
  swiftc -O scripts/icon/main.swift Sources/LumenBarUI/Brand/BrandMark.swift \
    -o build/make-icons -framework AppKit
  build/make-icons .
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
else
  echo "==> icons are current"
fi

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
# The command line tool ships inside the bundle, and it has to be signed in its
# own right — inside out, nested code first.
#
# `Contents/Resources` is not one of the locations codesign treats as nested
# code, so signing only the bundle seals pwelumenctl as a *resource* and leaves
# the Mach-O inside it unsigned. Nothing local complains; notarisation rejects
# the whole submission with three errors about that one file (no Developer ID,
# no secure timestamp, no hardened runtime).
  codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    "$APP/Contents/Resources/pwelumenctl" >/dev/null
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP" >/dev/null
else
  echo "==> no Developer ID identity found; falling back to ad-hoc"
  echo "    (every rebuild will revoke the Accessibility grant — media keys will need re-approving)"
  codesign --force --sign - --timestamp=none "$APP/Contents/Resources/pwelumenctl" >/dev/null 2>&1
  codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1
fi
codesign --verify --deep --strict "$APP"

echo "==> built $APP  ($VERSION)"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority=Developer" | head -2 || true

# The finished bundle, where somebody would look for it.
#
# It is assembled in $TMPDIR because iCloud's file provider keeps re-attaching com.apple.FinderInfo
# and codesign refuses to sign anything carrying it. Nothing copied it back, so `build/` held
# whatever was left there by the last run that did — a bundle from eleven days earlier, sitting
# under exactly the name anyone would reach for to check what they just built. Same `ditto` the
# Mac Monitor build uses, for the same reason.
#
# `--norsrc --noextattr --noacl`, not a plain ditto: the destination is inside iCloud Drive, and a
# plain copy carries com.apple.FinderInfo across with it — at which point `codesign --verify` on
# the copy answers "resource fork, Finder information, or similar detritus not allowed". A build
# nobody can verify in the place everybody looks for it is worse than no copy at all.
rm -rf "build/$(basename "$APP")"
mkdir -p build
ditto --norsrc --noextattr --noacl "$APP" "build/$(basename "$APP")"
echo "==> build/$(basename "$APP")"

if [[ "$INSTALL" == "1" ]]; then
  # A menu bar app is almost always running when a new build arrives, and
  # replacing the bundle underneath a running process leaves it half-alive.
  pkill -x PWELumenBar 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/PWE Lumen Bar.app"
  cp -R "$APP" "/Applications/PWE Lumen Bar.app"
  open "/Applications/PWE Lumen Bar.app"
  echo "==> installed and launched /Applications/PWE Lumen Bar.app"
else
  echo "    install it with:  ./scripts/build-app.sh --install"
fi
