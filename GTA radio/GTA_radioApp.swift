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
            ContentView()
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Toggle Radio Dial") {
                    AppDelegate.shared?.overlay.toggle()
                }
                .keyboardShortcut("r", modifiers: .option)
            }
        }

        Settings {
            SettingsView()
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

    private func applyHotKey() {
        let s = SettingsStore.shared
        hotKey.register(keyCode: UInt32(s.hotKeyCode), modifiers: s.carbonModifiers)
    }
}
