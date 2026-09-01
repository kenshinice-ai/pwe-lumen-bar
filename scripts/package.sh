#!/bin/bash
#
# Build, sign and package PWE Lumen Bar as a distributable .dmg.
#
#   ./scripts/package.sh                 build + sign + dmg
#   ./scripts/package.sh --notarize      also submit to Apple and staple the ticket
#   ./scripts/package.sh --skip-checks   skip the pre-flight self-check
#
# Signing identity is picked automatically:
#   1. "Developer ID Application: …"  → distributable, notarisable   (what you want)
#   2. anything else                  → refused; a menu bar app that Gatekeeper
#                                       blocks is not worth the download
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="PWE Lumen Bar"
TEAM_ID="2SQV3H5MH9"
PROFILE="${NOTARY_PROFILE:-PWE_NOTARY}"
VERSION="$(./scripts/version.sh)"

# Everything that carries a signature is assembled outside the repository:
# iCloud Drive re-attaches com.apple.FinderInfo to anything inside it, and
# codesign refuses to verify a bundle that has it. Only the finished disk image
# comes back into dist/.
WORK="${TMPDIR:-/tmp}/pwelumenbar-release"
STAGE="$WORK/stage"
DIST_DIR="dist"
DMG="$DIST_DIR/$APP_NAME $VERSION.dmg"

NOTARIZE=0
SKIP_CHECKS=0
for arg in "$@"; do
  case "$arg" in
    --notarize)    NOTARIZE=1 ;;
    --skip-checks) SKIP_CHECKS=1 ;;
    *) echo "✗ unknown option: $arg"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------- build

echo "▸ Building $APP_NAME $VERSION…"
./scripts/build-app.sh >/dev/null
APP="$WORK/../pwelumenbar-build/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "✗ $APP not found"; exit 1; }

# ---------------------------------------------------------------- pre-flight
#
# This app stands on private symbols resolved at run time. `compat` is the
# self-check that says whether they all still exist on the machine doing the
# packaging — if one has gone missing, the build in front of you is not a
# release, it is a bug report.

if [[ "$SKIP_CHECKS" == "0" ]]; then
  echo "▸ Pre-flight: the private interfaces…"
  REPORT="$("$APP/Contents/Resources/pwelumenctl" compat 2>&1)"
  if grep -qi "missing" <<<"$REPORT"; then
    echo "✗ Some private symbols did not resolve on this Mac — not packaging."
    echo "$REPORT" | sed 's/^/    /'
    exit 1
  fi
  echo "$REPORT" | tail -3 | sed 's/^/    /'
fi

# ---------------------------------------------------------------- sign

IDENTITY="$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | grep -v CSSMERR | head -1 \
  | sed -E 's/.*"(.*)".*/\1/' || true)"

if [[ -z "$IDENTITY" ]]; then
  cat <<'WARN'
✗ No "Developer ID Application" identity in the keychain.

  A disk image signed any other way is blocked by Gatekeeper on every Mac but
  this one, and cannot be notarised. To fix it you need the PRIVATE KEY that
  matches the certificate — the certificate alone is not enough:

    a) On the Mac where the CSR was created: Keychain Access → find
       "Developer ID Application: Li Liu (2SQV3H5MH9)" → right-click → Export
       → .p12 → copy here → double-click; or

    b) Revoke it at developer.apple.com → Certificates, then on THIS Mac:
       Keychain Access → Certificate Assistant → Request a Certificate From a
       Certificate Authority → "Saved to disk" → upload the CSR → download the
       .cer → double-click.
WARN
  exit 1
fi

echo "▸ Signing identity : $IDENTITY"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

# ---------------------------------------------------------------- notarise the app
#
# The app is notarised and stapled BEFORE it goes into the disk image, so the
# copy a customer drags to /Applications carries its own ticket — first launch
# then passes Gatekeeper even with no internet. The image is notarised
# separately below, so the download itself also verifies.

if [[ "$NOTARIZE" == "1" ]]; then
  echo "▸ Submitting the app to Apple (profile: $PROFILE)…"
  APP_ZIP="$WORK/notarize-app.zip"
  mkdir -p "$WORK"
  ditto -c -k --keepParent "$APP" "$APP_ZIP"
  xcrun notarytool submit "$APP_ZIP" --keychain-profile "$PROFILE" --wait
  rm -f "$APP_ZIP"
  echo "▸ Stapling the app…"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

# ---------------------------------------------------------------- dmg

echo "▸ Building the disk image…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" "$DIST_DIR"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# A first-run note inside the image itself. "I installed it and nothing
# happened" is the single most common report a menu bar app gets, and the disk
# image window is the last place we can answer it before the customer is on
# their own.
cp tools/templates/read-me-first.txt "$STAGE/Read Me First.txt"
cp tools/templates/licence-terms.txt "$STAGE/Licence Terms.txt"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$WORK/image.dmg" > /dev/null

# The image is signed too, so the download itself carries a valid signature.
codesign --force --sign "$IDENTITY" --timestamp "$WORK/image.dmg"

if [[ "$NOTARIZE" == "1" ]]; then
  echo "▸ Submitting the disk image to Apple…"
  xcrun notarytool submit "$WORK/image.dmg" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$WORK/image.dmg"
  xcrun stapler validate "$WORK/image.dmg"
fi

cp "$WORK/image.dmg" "$DMG"
rm -rf "$STAGE" "$WORK/image.dmg"

echo
echo "▸ $DMG"
echo "    $(du -h "$DMG" | cut -f1)   sha256 $(shasum -a 256 "$DMG" | cut -c1-16)…"
if [[ "$NOTARIZE" == "0" ]]; then
  echo
  echo "  Not notarised. Gatekeeper will warn on other Macs until you run:"
  echo "      ./scripts/package.sh --notarize"
fi
