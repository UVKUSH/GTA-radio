#!/usr/bin/env bash
# Build → sign (Developer ID) → notarize → staple → verify a distributable .dmg.
# Prereqs (owner, one-time): see docs/RELEASING.md. Requires a "Developer ID
# Application" identity and a stored notary profile named GTARadioNotary.
set -euo pipefail

PROJECT="GTA radio.xcodeproj"
SCHEME="GTA radio"
APP_NAME="Wasted FM"
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

# --- notarize the app, then staple IT -----------------------------------------
# Notarization matches by content hash, so submit a zip of the .app and staple
# the .app itself. This is what makes a copy dragged to /Applications validate
# offline — stapling only the .dmg leaves the extracted app without a ticket.
APP_ZIP="$BUILD/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

# --- package .dmg from the stapled app ----------------------------------------
DMG="$BUILD/$DMG_NAME.dmg"
STAGE="$BUILD/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$DMG_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
xcrun stapler staple "$DMG"     # staple the container too (belt and suspenders)

# --- verify -------------------------------------------------------------------
echo "== Gatekeeper assessment =="
spctl -a -vvv --type install "$DMG" || spctl -a -vvv "$APP" || true
stapler validate "$DMG"
echo "DONE → $DMG"
