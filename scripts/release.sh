#!/usr/bin/env bash
# Build → sign (Developer ID) → notarize → staple → verify a distributable .dmg.
# Prereqs (owner, one-time): see docs/RELEASING.md. Requires a "Developer ID
# Application" identity and a stored notary profile named GTARadioNotary.
set -euo pipefail

PROJECT="GTA radio.xcodeproj"
SCHEME="GTA radio"
APP_NAME="GTA radio"
DMG_NAME="WastedFM"
NOTARY_PROFILE="GTARadioNotary"
BUILD="build"
ARCHIVE="$BUILD/GTARadio.xcarchive"
EXPORT="$BUILD/export"

# --- pre-flight ---------------------------------------------------------------
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "ERROR: no 'Developer ID Application' certificate found in the keychain."
  echo "       Create it in Xcode → Settings → Accounts → Manage Certificates → +."
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "ERROR: notary profile '$NOTARY_PROFILE' not found."
  echo "       Run: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
  echo "              --apple-id <you> --team-id L3MF4UC24F --password <app-specific-password>"
  exit 1
fi

rm -rf "$BUILD"; mkdir -p "$BUILD"

# --- archive ------------------------------------------------------------------
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive

# --- export (Developer ID signed, hardened runtime already on) ----------------
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$EXPORT"

APP="$EXPORT/$APP_NAME.app"

# --- package .dmg -------------------------------------------------------------
DMG="$BUILD/$DMG_NAME.dmg"
STAGE="$BUILD/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$DMG_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

# --- notarize + staple --------------------------------------------------------
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# --- verify -------------------------------------------------------------------
echo "== Gatekeeper assessment =="
spctl -a -vvv --type install "$DMG" || spctl -a -vvv "$APP" || true
stapler validate "$DMG"
echo "DONE → $DMG"
