# Design Spec — First-run Onboarding + Signing/Notarization

**Date:** 2026-07-24
**App:** Wasted FM (GTA Radio) — macOS, bundle `gta.GTA-radio`, Team `L3MF4UC24F`
**Status:** approved design, pending spec review

---

## 1. Goals

Two independent deliverables that together make the app ready to hand to real users:

- **A. First-run spotlight onboarding** — a once-ever "welcome tour" that teaches the
  non-obvious core interactions (the dial, paste-a-URL, ⌥R hotkey, Wheels, Settings)
  using coach-marks that highlight the *real* UI.
- **B. Developer ID signing + notarization pipeline** — produce a downloadable,
  notarized, stapled `.dmg` that opens on any Mac with no Gatekeeper warning.

Out of scope: account/login, data import, Sparkle auto-update, Mac App Store path.

---

## 2. Deliverable A — Onboarding

### 2.1 Trigger & lifecycle
- New flag: `@AppStorage("hasCompletedOnboarding") Bool` (default `false`).
- First-run order: **intro splash (every launch)** → on its finish, if
  `!hasCompletedOnboarding`, present the onboarding overlay over `ContentView`.
- Completing (**Get started**) or skipping (**Skip** / **Esc**) sets the flag `true`.
- Intro (always) and onboarding (first-run only) stay independent — different flags.

### 2.2 Replay from Settings (cross-window)
Settings is its own window/scene, so it can't toggle main-window state directly.
- `AppState` gains `@Published var replayOnboarding: Bool` and
  `@Published var replayIntro: Bool` (or bump counters).
- `RootView` (main window) observes `AppState.shared` and re-presents the matching
  layer when either is set.
- SettingsView gets two buttons:
  - "**Replay Intro video**" → sets `AppState.shared.replayIntro = true`; RootView
    re-shows `IntroSplashView` (video + mp3, same skippable behavior). Does not touch
    the onboarding flag.
  - "**Replay welcome tour**" → sets `hasCompletedOnboarding = false` and
    `AppState.shared.replayOnboarding = true`; RootView re-presents the coach-marks.
- Both live in a Settings section (e.g. "Getting started" / under Appearance).

### 2.3 Coach-mark mechanism (robust, non-interactive)
- `enum CoachTarget { case dial, wheels, settings }` (extensible).
- `CoachAnchorKey: PreferenceKey` collecting `[CoachTarget: Anchor<CGRect>]`.
- `.coachAnchor(_:)` view modifier publishes a view's bounds via `anchorPreference`.
- Real views tagged in `ContentView`:
  - dial container → `.dial`
  - steering-wheel `HUDIconButton` → `.wheels`
  - gear `HUDIconButton` → `.settings`
- `OnboardingOverlay` is attached with `.overlayPreferenceValue(CoachAnchorKey.self)`
  wrapped in a `GeometryReader` (inside `RootView`, around `ContentView`) so anchors
  resolve to overlay coordinates.
  - Full-window dim scrim (~0.7 black).
  - **Anchored step:** rounded-rect "hole" cutout around the resolved rect (with
    padding) via even-odd fill / mask; a callout bubble positioned beside it,
    auto-flipping when near a window edge.
  - **Centered step (no anchor):** full dim + centered card.
  - **Non-interactive:** the scrim consumes all input, so the app beneath can't be
    hovered/clicked. This deliberately sidesteps the dial's hover-motion
    (`[[dial-hover-sector-based]]`) — nodes only move on real hover, impossible here.
  - **Graceful fallback:** if a step's anchor is absent (view off-screen / not built),
    that step renders as a centered card instead of breaking.

### 2.4 Steps (6)
1. **Welcome** — centered. Headline **"Wasted FM"**, tagline **"GTA Radio"**,
   one line: "Your personal radio, built from any YouTube link."
2. **The dial** — anchor `.dial`: "Click a station to tune in — 26 slots per wheel."
3. **Add anything** — anchor `.dial`: "Click an empty slot to paste any YouTube
   video *or* playlist. No API key, no sign-in."
4. **Pop it anywhere** — centered: "Press ⌥R anywhere on your Mac to summon the dial
   over any app." (global hotkey has no on-screen element to point at)
5. **Wheels** — anchor `.wheels`: "Save whole 26-station layouts as Wheels — switch
   with ⌘1–9."
6. **Settings** — anchor `.settings`: "Audio-only mode, custom hotkey, and appearance
   live here." Primary button **Get started**.

### 2.5 Controls & motion
- Progress dots (6). **Back / Next**. Persistent **Skip** (top-right). **Esc** = skip.
- Overlay fades in/out ~0.3s; cutout animates between steps.

### 2.6 Files
- **New:** `GTA radio/OnboardingOverlay.swift` — overlay view, step model,
  `CoachTarget`, `CoachAnchorKey`, `.coachAnchor` modifier.
- **Edit:** `GTA radio/ContentView.swift` — 3 one-line `.coachAnchor` tags.
- **Edit:** `GTA radio/GTA_radioApp.swift` — `RootView` gates onboarding after intro,
  observes `AppState.replayOnboarding` and `AppState.replayIntro`.
- **Edit:** `GTA radio/AppState.swift` — `replayOnboarding` + `replayIntro` published
  + reset helpers.
- **Edit:** `GTA radio/SettingsView.swift` — "Replay Intro video" and
  "Replay welcome tour" buttons.

### 2.7 Testing (manual, macOS)
- Reset flag → launch → intro → onboarding appears; page through all 6; verify cutouts
  land on dial / steering-wheel / gear.
- Skip and Esc both dismiss and set the flag.
- Replay from Settings: "Replay Intro video" re-plays the splash; "Replay welcome
  tour" re-presents the coach-marks — both on the main window.
- Second launch: intro plays, no onboarding.
- Edge: force a missing anchor → step falls back to centered card; resize window
  mid-tour → cutout follows the element.

---

## 3. Deliverable B — Signing & Notarization

### 3.1 Current state
- Sandbox ✅, hardened runtime ✅ (`ENABLE_HARDENED_RUNTIME = YES`),
  `network.client` ✅, automatic signing, `v1.0 (1)`.
- Owner: paid Apple Developer Program member ✅, signed into Xcode ✅.
- **Developer ID Application** cert ❌ not on this Mac yet (only "Apple Development").
- notarytool credentials ❌ not stored yet.

### 3.2 Deliverables (committable, no secrets)
- `ExportOptions.plist` — `method = developer-id`, `teamID = L3MF4UC24F`.
- `scripts/release.sh`:
  1. `xcodebuild ... -configuration Release -archivePath build/GTARadio.xcarchive archive`
  2. `xcodebuild -exportArchive -exportOptionsPlist ExportOptions.plist ...` → signed `.app`
     (Developer ID, hardened runtime already on)
  3. Build `.dmg` (`create-dmg` if present, else `hdiutil create`) with the `.app`
     + `/Applications` symlink.
  4. `xcrun notarytool submit build/WastedFM.dmg --keychain-profile "GTARadioNotary" --wait`
  5. `xcrun stapler staple build/WastedFM.dmg`
  6. Verify: `spctl -a -vvv` on the `.app`; `stapler validate` on the `.dmg`.
  - Script pre-check: fail early with a clear message if no "Developer ID Application"
    identity is found or the keychain profile is missing.
- `docs/RELEASING.md` — the runbook.

### 3.3 Owner one-time steps (documented, NOT automated — involve credentials)
1. Create **Developer ID Application** cert: Xcode → Settings → Accounts →
   Manage Certificates → **+** → Developer ID Application.
2. Create an app-specific password at appleid.apple.com.
3. `xcrun notarytool store-credentials "GTARadioNotary" --apple-id <you>
   --team-id L3MF4UC24F --password <app-specific-password>`.

Assistant will NOT run steps 2–3 or enter any Apple credential; the owner runs them.

### 3.4 Entitlements
No changes — current entitlements are notarization-compatible. The ⌥R global hotkey
works under the sandbox as-is.

---

## 4. Risks & mitigations
- **Coach-mark anchoring fragility** → non-interactive scrim + anchor to stable
  containers + centered-card fallback for any missing anchor.
- **Release blocked without Developer ID cert** → `release.sh` checks for the identity
  and errors clearly; runbook lists the 3-click creation path.
- **Notarization rejection** → hardened runtime + sandbox already satisfied; verify
  step surfaces any issue before distribution.

---

## 5. Build order (for the implementation plan)
1. Onboarding: `AppState` flag → `OnboardingOverlay` + coach infra → `ContentView`
   anchor tags → `RootView` gate → `SettingsView` replay button → manual test.
2. Signing: `ExportOptions.plist` → `scripts/release.sh` → `docs/RELEASING.md`.
   (Runnable end-to-end only after the owner creates the Developer ID cert.)
