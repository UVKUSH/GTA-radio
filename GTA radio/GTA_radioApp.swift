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
        hotKey.register()
    }
}
