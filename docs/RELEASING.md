# Releasing Wasted FM (GTA Radio)

Produces a notarized, stapled `.dmg` that opens on any Mac with no Gatekeeper
warning. The app is already sandboxed with hardened runtime on.

## One-time setup (owner — involves your Apple credentials)

You are a paid Apple Developer Program member and signed into Xcode. Two things
remain, and only you can do them:

1. **Create the Developer ID Application certificate**
   Xcode → Settings → Accounts → (your Apple ID) → Manage Certificates →
   **+** → **Developer ID Application**. This Mac currently has only an
   "Apple Development" cert; the release needs this one.

2. **Store notarization credentials** (keychain profile the script reads)
   - Create an app-specific password at appleid.apple.com → Sign-In & Security →
     App-Specific Passwords.
   - Run:
     ```bash
     xcrun notarytool store-credentials "GTARadioNotary" \
       --apple-id "<your-apple-id-email>" \
       --team-id L3MF4UC24F \
       --password "<app-specific-password>"
     ```

## Cut a release

```bash
./scripts/release.sh
```

Output: `build/WastedFM.dmg` — notarized and stapled. Distribute that file.

## Verify by hand (optional)

```bash
spctl -a -vvv build/dmg/"Wasted FM.app"   # -> "accepted / source=Notarized Developer ID"
stapler validate build/WastedFM.dmg       # -> "The validate action worked!"
```

## Bumping the version

Edit `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in the target build
settings before running the script.
