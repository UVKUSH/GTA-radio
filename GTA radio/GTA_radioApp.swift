//
//  GTA_radioApp.swift
//  GTA radio
//

import SwiftUI

@main
struct GTA_radioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Toggle Radio Dial") {
                    AppDelegate.shared?.overlay.toggle()
                }
                .keyboardShortcut("r", modifiers: .option)
            }
            WheelsCommands(store: AppState.shared.store)
        }

        Settings {
            SettingsView()
        }
    }
}

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

/// "Wheels" menu: ⌘1–9 hot-swaps between the first nine saved wheels.
/// Lives in the menu bar so the shortcuts work anywhere in the app and the
/// number mapping stays discoverable.
struct WheelsCommands: Commands {
    @ObservedObject var store: RadioStore

    var body: some Commands {
        CommandMenu("Wheels") {
            if store.presets.isEmpty {
                Text("No saved wheels yet")
            } else {
                ForEach(Array(store.presets.prefix(9).enumerated()), id: \.element.id) { i, preset in
                    Button("Load “\(preset.name)”") {
                        store.loadPreset(preset)
                        AppState.shared.goHome()
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    let hotKey = HotKeyManager()
    let overlay = OverlayWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        hotKey.onTrigger = { [weak self] in
            MainActor.assumeIsolated { self?.overlay.toggle() }
        }
        // Register from saved settings, and re-register whenever they change.
        applyHotKey()
        SettingsStore.shared.onHotKeyChange = { [weak self] in self?.applyHotKey() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppState.shared.commitCurrent() }
    }

    /// Coming back to the app is the natural "network might be back" moment —
    /// retry a player shell that never became ready (offline at launch).
    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated { AppState.shared.player.reloadShellIfNeeded() }
    }

    private func applyHotKey() {
        let s = SettingsStore.shared
        hotKey.register(keyCode: UInt32(s.hotKeyCode), modifiers: s.carbonModifiers)
    }
}
