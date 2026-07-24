# Onboarding + Signing/Notarization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a once-ever first-run spotlight onboarding (with Settings replay for both the intro and the tour) and a Developer ID sign → notarize → staple `.dmg` release pipeline.

**Architecture:** Onboarding is a non-interactive SwiftUI overlay layered over `ContentView` inside `RootView`. It locates real UI via `anchorPreference` (a `CoachAnchorKey` preference + `.coachAnchor(_:)` modifier), dims the window, and cuts a hole around the active target with a callout beside it. A shared `AppState` flag lets the separate Settings window re-trigger the intro or the tour. Notarization is a committed `ExportOptions.plist` + `scripts/release.sh` + `docs/RELEASING.md`; the owner supplies the Developer ID cert and notary credentials.

**Tech Stack:** Swift, SwiftUI, AVKit/AVFoundation (existing intro), `@AppStorage`/`UserDefaults`, `xcodebuild`, `xcrun notarytool`/`stapler`, `hdiutil`.

## Global Constraints

- Platform: macOS app, bundle id `gta.GTA-radio`, Team `L3MF4UC24F`, `v1.0 (1)`.
- Brand copy: welcome headline **"Wasted FM"**, tagline **"GTA Radio"**. Use these exact strings.
- The project has **no XCTest target**; SwiftUI-overlay and shell-script work is verified by `xcodebuild ... build` succeeding + a manual launch/visual check. Each task's "test" step is a build + a specific manual observation. Do not add a test target.
- New source/resource files auto-bundle via the `PBXFileSystemSynchronizedRootGroup` on `GTA radio/` — never hand-edit `project.pbxproj` to add files.
- Existing intro: `IntroSplashView` shown by `RootView` (`GTA_radioApp.swift`) via `@State showIntro`. Onboarding must appear only **after** the intro finishes.
- Build command (verbatim) for every build step:
  `xcodebuild -project "GTA radio.xcodeproj" -scheme "GTA radio" -destination 'platform=macOS' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"`
- Commit after every task. Do not commit unrelated pre-existing dirty files (`AppState.swift` etc. may already be modified — only stage the lines/files this plan changes; if a file is already dirty from other work, stage it with `git add -p` limited to your hunks).

---

## File Structure

- **Create** `GTA radio/OnboardingOverlay.swift` — `CoachTarget`, `CoachAnchorKey`, `.coachAnchor(_:)`, `OnboardingStep`, `onboardingSteps`, and `OnboardingOverlay` view (scrim + cutout + callout + controls).
- **Modify** `GTA radio/AppState.swift` — add `replayIntro` / `replayOnboarding` published flags.
- **Modify** `GTA radio/ContentView.swift` — tag `filmstrip`, steering-wheel button, gear button with `.coachAnchor(...)`.
- **Modify** `GTA radio/GTA_radioApp.swift` — `RootView` gates the tour after intro and honors the two replay flags.
- **Modify** `GTA radio/SettingsView.swift` — "Replay Intro video" + "Replay welcome tour" buttons.
- **Create** `ExportOptions.plist` — Developer ID export options.
- **Create** `scripts/release.sh` — archive → export → dmg → notarize → staple → verify.
- **Create** `docs/RELEASING.md` — runbook + owner one-time steps.

---

## Task 1: Coach-mark anchor infrastructure

**Files:**
- Create: `GTA radio/OnboardingOverlay.swift`

**Interfaces:**
- Produces: `enum CoachTarget: Hashable { case stations, wheels, settings }`; `struct CoachAnchorKey: PreferenceKey` with `static defaultValue: [CoachTarget: Anchor<CGRect>] = [:]`; `extension View { func coachAnchor(_ target: CoachTarget) -> some View }`.

- [x] **Step 1: Create the file with the anchor primitives**

```swift
//
//  OnboardingOverlay.swift
//  GTA radio
//
//  First-run "welcome tour": a non-interactive scrim that dims the window and
//  spotlights real UI elements (located via anchorPreference), with a callout
//  beside each. Shown once (see hasCompletedOnboarding) after the intro, and
//  replayable from Settings.
//

import SwiftUI

/// Real UI elements the tour can point at. The radial dial is a separate ⌥R
/// overlay window, so the main-window filmstrip stands in as `.stations`.
enum CoachTarget: Hashable { case stations, wheels, settings }

/// Collects the on-screen bounds of every tagged target, keyed by target.
struct CoachAnchorKey: PreferenceKey {
    static var defaultValue: [CoachTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachTarget: Anchor<CGRect>],
                       nextValue: () -> [CoachTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's bounds so the onboarding overlay can spotlight it.
    func coachAnchor(_ target: CoachTarget) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [target: $0] }
    }
}
```

- [x] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project "GTA radio.xcodeproj" -scheme "GTA radio" -destination 'platform=macOS' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 3: Commit**

```bash
git add "GTA radio/OnboardingOverlay.swift"
git commit -m "feat(onboarding): coach-mark anchor preference infra"
```

---

## Task 2: Onboarding step model + overlay view

**Files:**
- Modify: `GTA radio/OnboardingOverlay.swift`

**Interfaces:**
- Consumes: `CoachTarget`, `CoachAnchorKey` (Task 1).
- Produces: `struct OnboardingStep { let target: CoachTarget?; let title: String; let body: String }`; `let onboardingSteps: [OnboardingStep]`; `struct OnboardingOverlay: View { init(onFinish: @escaping () -> Void) }`.

- [x] **Step 1: Append the step model and steps**

Append to `GTA radio/OnboardingOverlay.swift`:

```swift
/// One tour card. `target == nil` → a centered card (no spotlight).
struct OnboardingStep {
    let target: CoachTarget?
    let title: String
    let body: String
}

let onboardingSteps: [OnboardingStep] = [
    .init(target: nil,        title: "Wasted FM",       body: "GTA Radio — your personal radio, built from any YouTube link."),
    .init(target: .stations,  title: "Your stations",   body: "Click a station to tune in. Every wheel holds 26 slots."),
    .init(target: .stations,  title: "Add anything",    body: "Click an empty slot to paste any YouTube video or playlist. No API key, no sign-in."),
    .init(target: nil,        title: "Pop it anywhere", body: "Press ⌥R anywhere on your Mac to summon the radial dial over any app."),
    .init(target: .wheels,    title: "Wheels",          body: "Save whole 26-station layouts as Wheels — switch between them with ⌘1–9."),
    .init(target: .settings,  title: "Settings",        body: "Audio-only mode, a custom hotkey, and appearance all live here."),
]
```

- [x] **Step 2: Append the overlay view**

Append to `GTA radio/OnboardingOverlay.swift`:

```swift
struct OnboardingOverlay: View {
    var onFinish: () -> Void
    @State private var index = 0
    @State private var opacity: Double = 0

    private var step: OnboardingStep { onboardingSteps[index] }
    private var isLast: Bool { index == onboardingSteps.count - 1 }

    var body: some View {
        GeometryReader { proxy in
            // Resolve the active step's target rect (nil → centered card).
            let overlay = overlayContent(proxy: proxy)
            overlay
        }
        .ignoresSafeArea()
        .opacity(opacity)
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { opacity = 1 } }
    }

    @ViewBuilder
    private func overlayContent(proxy: GeometryProxy) -> some View {
        // The parent supplies anchors via .overlayPreferenceValue; this view is
        // rendered inside that closure (see RootView), so we read them there and
        // pass a resolved rect down. Here we just lay out scrim + callout.
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.72)
                .contentShape(Rectangle())            // eat all clicks (non-interactive app beneath)
            calloutCard
                .frame(maxWidth: 360)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            Button("Skip", action: finish)
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
                .padding(16)

            // Esc = skip. Invisible cancel-shortcut button (fires regardless of
            // focus in a window) — same proven trick IntroSplashView uses;
            // .onExitCommand is focus-dependent and can silently miss Esc here.
            Button("", action: finish)
                .keyboardShortcut(.cancelAction)
                .opacity(0).allowsHitTesting(false)
        }
    }

    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step.title).font(.gtaDisplay(26)).foregroundStyle(Theme.bone)
            Text(step.body).font(.system(size: 14)).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                ForEach(onboardingSteps.indices, id: \.self) { i in
                    Circle().fill(i == index ? Theme.magenta : .white.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
                Spacer()
                if index > 0 {
                    Button("Back") { withAnimation { index -= 1 } }.buttonStyle(.plain)
                }
                Button(isLast ? "Get started" : "Next") {
                    if isLast { finish() } else { withAnimation { index += 1 } }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
        .shadow(radius: 30)
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.25)) { opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: onFinish)
    }
}
```

> NOTE for Task 5: the spotlight cutout is added in Task 5 once the overlay is wired to real anchors — this task ships a working centered-card tour first (all steps show as centered cards), which is the graceful-fallback behavior anyway.

- [x] **Step 3: Build**

Run: `xcodebuild -project "GTA radio.xcodeproj" -scheme "GTA radio" -destination 'platform=macOS' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 4: Commit**

```bash
git add "GTA radio/OnboardingOverlay.swift"
git commit -m "feat(onboarding): step model + centered-card overlay"
```

---

## Task 3: AppState replay flags

**Files:**
- Modify: `GTA radio/AppState.swift`

**Interfaces:**
- Produces: `AppState.replayIntro: Bool` and `AppState.replayOnboarding: Bool` (`@Published`, default `false`).

- [x] **Step 1: Add the flags**

In `GTA radio/AppState.swift`, inside `final class AppState`, add near the other `@Published` properties (e.g. after `@Published var shuffleOn = false`):

```swift
    /// Set by Settings (a separate window) to re-trigger the intro or the tour
    /// on the main window's RootView; RootView flips them back to false.
    @Published var replayIntro = false
    @Published var replayOnboarding = false
```

- [x] **Step 2: Build**

Run: `xcodebuild -project "GTA radio.xcodeproj" -scheme "GTA radio" -destination 'platform=macOS' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 3: Commit**

```bash
git add "GTA radio/AppState.swift"
git commit -m "feat(onboarding): AppState replayIntro/replayOnboarding flags"
```

---

## Task 4: Wire tour into RootView (first-run + replay)

**Files:**
- Modify: `GTA radio/GTA_radioApp.swift`

**Interfaces:**
- Consumes: `OnboardingOverlay` (Task 2), `AppState.replayIntro`/`replayOnboarding` (Task 3), `CoachAnchorKey` (Task 1, used in Task 5).

- [x] **Step 1: Replace `RootView` with the gated version**

In `GTA radio/GTA_radioApp.swift`, replace the existing `struct RootView` with:

```swift
/// The window's root: app UI with the launch intro layered on top, and the
/// first-run welcome tour after the intro. Both are replayable from Settings.
struct RootView: View {
    @ObservedObject private var app = AppState.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var showIntro = true
    @State private var showOnboarding = false

    var body: some View {
        ContentView()
            .overlayPreferenceValue(CoachAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    ZStack {
                        if showIntro {
                            IntroSplashView { introFinished() }
                        }
                        if showOnboarding {
                            OnboardingOverlay(anchors: anchors, proxy: proxy) {
                                showOnboarding = false
                                hasCompletedOnboarding = true
                            }
                        }
                    }
                }
            }
            .onChange(of: app.replayIntro) { _, want in
                if want { app.replayIntro = false; showOnboarding = false; showIntro = true }
            }
            .onChange(of: app.replayOnboarding) { _, want in
                if want { app.replayOnboarding = false; showIntro = false; showOnboarding = true }
            }
    }

    private func introFinished() {
        showIntro = false
        if !hasCompletedOnboarding { showOnboarding = true }
    }
}
```

> This references `OnboardingOverlay(anchors:proxy:onFinish:)`, whose `anchors`/`proxy` params are added in Task 5. Do Task 5 in the same session before building, OR temporarily call `OnboardingOverlay { ... }` and add the params in Task 5. The commit for this task happens after Task 5 builds green.

- [x] **Step 2: Proceed directly to Task 5 (they compile together).**

---

## Task 5: Spotlight cutout + real-anchor resolution

**Files:**
- Modify: `GTA radio/OnboardingOverlay.swift`
- Modify: `GTA radio/ContentView.swift`

**Interfaces:**
- Consumes: `CoachAnchorKey` anchors + `GeometryProxy` from `RootView` (Task 4).
- Produces: `OnboardingOverlay(anchors: [CoachTarget: Anchor<CGRect>], proxy: GeometryProxy, onFinish: () -> Void)`.

- [x] **Step 1: Tag the real elements in ContentView**

In `GTA radio/ContentView.swift`:

Filmstrip — change (`ContentView.swift:196`, the end of `filmstrip`):
```swift
        .frame(maxWidth: .infinity, alignment: .leading)
        .coachAnchor(.stations)
    }
```

Steering-wheel button (`ContentView.swift:104`):
```swift
                HUDIconButton(system: "steeringwheel") { showWheels = true }
                    .coachAnchor(.wheels)
```

Gear button (`ContentView.swift:108`):
```swift
                HUDIconButton(system: "gearshape.fill") { openSettings() }
                    .coachAnchor(.settings)
```

- [x] **Step 2: Update `OnboardingOverlay` to take anchors and draw the cutout**

Replace the `OnboardingOverlay` struct header + `body` + `overlayContent` from Task 2 with:

```swift
struct OnboardingOverlay: View {
    let anchors: [CoachTarget: Anchor<CGRect>]
    let proxy: GeometryProxy
    var onFinish: () -> Void
    @State private var index = 0
    @State private var opacity: Double = 0

    private var step: OnboardingStep { onboardingSteps[index] }
    private var isLast: Bool { index == onboardingSteps.count - 1 }

    /// Resolved spotlight rect for the active step, or nil (→ centered card).
    private var spotlight: CGRect? {
        guard let t = step.target, let a = anchors[t] else { return nil }
        return proxy[a].insetBy(dx: -10, dy: -10)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            scrim
            callout
            Button("Skip", action: finish)
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
                .padding(16)

            // Esc = skip. Invisible cancel-shortcut button (fires regardless of
            // focus in a window) — same proven trick IntroSplashView uses;
            // .onExitCommand is focus-dependent and can silently miss Esc here.
            Button("", action: finish)
                .keyboardShortcut(.cancelAction)
                .opacity(0).allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .opacity(opacity)
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { opacity = 1 } }
    }

    /// Dim everything; punch a rounded hole around the spotlight rect.
    private var scrim: some View {
        Color.black.opacity(0.72)
            .contentShape(Rectangle())
            .mask {
                ZStack {
                    Rectangle()
                    if let r = spotlight {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                            .blendMode(.destinationOut)   // correct SwiftUI mask-cutout blend
                    }
                }
                .compositingGroup()
            }
            .animation(.easeInOut(duration: 0.25), value: index)
    }

    /// Callout: near the spotlight (below, or above if low); centered if none.
    @ViewBuilder private var callout: some View {
        if let r = spotlight {
            calloutCard
                .frame(maxWidth: 340)
                .position(calloutPosition(for: r))
                .animation(.easeInOut(duration: 0.25), value: index)
        } else {
            calloutCard
                .frame(maxWidth: 360)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func calloutPosition(for r: CGRect) -> CGPoint {
        let size = proxy.size
        let below = r.maxY + 90
        let y = below + 60 < size.height ? below : r.minY - 90
        let x = min(max(r.midX, 190), size.width - 190)
        return CGPoint(x: x, y: y)
    }

    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step.title).font(.gtaDisplay(26)).foregroundStyle(Theme.bone)
            Text(step.body).font(.system(size: 14)).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                ForEach(onboardingSteps.indices, id: \.self) { i in
                    Circle().fill(i == index ? Theme.magenta : .white.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
                Spacer()
                if index > 0 { Button("Back") { withAnimation { index -= 1 } }.buttonStyle(.plain) }
                Button(isLast ? "Get started" : "Next") {
                    if isLast { finish() } else { withAnimation { index += 1 } }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
        .shadow(radius: 30)
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.25)) { opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: onFinish)
    }
}
```

(Delete the now-duplicated `overlayContent`/old `calloutCard`/old `body` from Task 2 so only this version remains.)

- [x] **Step 3: Build**

Run: `xcodebuild -project "GTA radio.xcodeproj" -scheme "GTA radio" -destination 'platform=macOS' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 4: Manual verification**

```bash
# reset the first-run flag for THIS app's sandbox container, then launch
defaults delete gta.GTA-radio hasCompletedOnboarding 2>/dev/null || true
osascript -e 'quit app "GTA radio"' 2>/dev/null; sleep 1
open "$(ls -dt ~/Library/Developer/Xcode/DerivedData*/GTA_radio-*/Build/Products/Debug/'GTA radio.app' | head -1)"
```
Observe: intro plays → tour appears → step 2 spotlights the filmstrip, step 5 the steering-wheel, step 6 the gear; Next/Back/dots/Skip/Esc all work; "Get started" dismisses.

- [x] **Step 5: Commit (Tasks 4 + 5 together)**

```bash
git add "GTA radio/OnboardingOverlay.swift" "GTA radio/ContentView.swift" "GTA radio/GTA_radioApp.swift"
git commit -m "feat(onboarding): first-run spotlight tour wired to real UI + replay hooks"
```

---

## Task 6: Settings replay buttons

**Files:**
- Modify: `GTA radio/SettingsView.swift`

**Interfaces:**
- Consumes: `AppState.replayIntro`/`replayOnboarding` (Task 3), `@AppStorage("hasCompletedOnboarding")`.

- [x] **Step 1: Add a "Getting started" section**

In `GTA radio/SettingsView.swift`, add a new `Section` inside the `Form` (after the existing audio/sounds `Section` near `SettingsView.swift:56`):

```swift
            Section("Getting started") {
                Button("Replay Intro video") {
                    AppState.shared.replayIntro = true
                }
                Button("Replay welcome tour") {
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                    AppState.shared.replayOnboarding = true
                }
            }
```

- [x] **Step 2: Build**

Run: `xcodebuild -project "GTA radio.xcodeproj" -scheme "GTA radio" -destination 'platform=macOS' build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 3: Manual verification**

Launch the app, open Settings (⌘,). Click **Replay Intro video** → the intro plays on the main window. Click **Replay welcome tour** → the tour appears on the main window.

- [x] **Step 4: Commit**

```bash
git add "GTA radio/SettingsView.swift"
git commit -m "feat(settings): replay Intro video and welcome tour"
```

---

## Task 7: Export options + release script

**Files:**
- Create: `ExportOptions.plist`
- Create: `scripts/release.sh`

**Interfaces:**
- Produces: a runnable `scripts/release.sh` (requires the owner's Developer ID cert + `GTARadioNotary` keychain profile at run time).

- [ ] **Step 1: Create `ExportOptions.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>L3MF4UC24F</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

- [ ] **Step 2: Create `scripts/release.sh`**

```bash
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
```

- [ ] **Step 3: Make it executable + shell-syntax check**

Run:
```bash
chmod +x scripts/release.sh
bash -n scripts/release.sh && echo "syntax OK"
```
Expected: `syntax OK`

- [ ] **Step 4: Commit**

```bash
git add ExportOptions.plist scripts/release.sh
git commit -m "build: Developer ID export options + notarization release script"
```

---

## Task 8: Release runbook

**Files:**
- Create: `docs/RELEASING.md`

- [ ] **Step 1: Write the runbook**

```markdown
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
spctl -a -vvv build/dmg/"GTA radio.app"   # -> "accepted / source=Notarized Developer ID"
stapler validate build/WastedFM.dmg       # -> "The validate action worked!"
```

## Bumping the version

Edit `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in the target build
settings before running the script.
```

- [ ] **Step 2: Commit**

```bash
git add docs/RELEASING.md
git commit -m "docs: release + notarization runbook"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** Trigger/lifecycle → T4; replay-from-Settings (intro+tour) → T3/T4/T6; coach mechanism + anchors + fallback → T1/T2/T5; 6 steps + copy → T2; controls → T2/T5; files list → all tasks; signing deliverables (ExportOptions, release.sh, RELEASING.md) → T7/T8; owner one-time steps → T8; entitlements unchanged → noted in constraints. No gaps.
- **Placeholder scan:** none — every code step has real content.
- **Type consistency:** `CoachTarget`/`CoachAnchorKey`/`coachAnchor` consistent T1→T5; `OnboardingOverlay` param evolution (T2 centered-only → T5 `anchors:proxy:onFinish:`) is called out explicitly in T4 and T5 so they build together; `replayIntro`/`replayOnboarding` consistent T3→T4→T6; `hasCompletedOnboarding` key string identical in T4 and T6.
- **Esc handling (verified 2026-07-24):** deployment target is macOS 26.4, so two-param `.onChange(of:_:)` compiles. Esc dismissal uses an invisible `Button(...).keyboardShortcut(.cancelAction)` inside the overlay ZStack — matching `IntroSplashView`'s documented "reliable regardless of focus" trick — instead of the focus-dependent `.onExitCommand`.
- **Open copy decision (welcome step):** T2 renders the welcome card as headline **"Wasted FM"** + body **"GTA Radio — your personal radio, built from any YouTube link."** (tagline folded into the body). If you want "GTA Radio" as a distinct styled tagline line instead, split the body string in T2's `onboardingSteps[0]` and add a middle `Text` — trivial, isolated to one array entry.
```
