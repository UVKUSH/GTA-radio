//
//  OverlayWindowController.swift
//  GTA radio
//
//  Full-screen, borderless, transparent panel that hosts the radial dial.
//  Closing it does NOT stop playback — the player lives in AppState.
//

import AppKit
import SwiftUI

/// Borderless panels can't become key by default; we need keys for Esc-to-close.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class OverlayWindowController {
    private var panel: NSPanel?

    func toggle() {
        if panel != nil { close() } else { show() }
    }

    func show() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        let panel = KeyablePanel(contentRect: frame,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let root = RadialOverlayView(
            onSelect: { [weak self] slot in
                AppState.shared.play(slot: slot)
                self?.close()
            },
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        panel.setFrame(frame, display: true)
        // Non-activating: the overlay floats and handles its own clicks (play/
        // pause, tune) WITHOUT pulling the main app window forward.
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
