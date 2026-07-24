//
//  Theme.swift
//  GTA radio
//
//  "Los Santos night HUD" design tokens + shared building blocks.
//

import SwiftUI

enum Theme {
    static let ink = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let bone = Color(red: 0.906, green: 0.890, blue: 0.847)
    static let muted = Color(red: 0.54, green: 0.53, blue: 0.60)
    static let magenta = Color(red: 1.0, green: 0.243, blue: 0.498)   // brand / add
    static let teal = Color(red: 0.169, green: 0.902, blue: 0.776)    // now-playing lock

    /// A playful faux FM frequency derived from the slot, for car-radio flavor.
    static func frequency(for slot: Int) -> String {
        let f = 88.1 + Double(slot) * 0.4     // 88.1 … 98.1
        return String(format: "%.1f", f)
    }

    /// A distinct emoji for each empty slot so the wheel is never blank.
    private static let emojis = ["📻","🎧","🎸","🎹","🎺","🥁","🎷","🎤","🪕","🎻",
                                 "🎚️","🎛️","💿","📀","🔊","🎼","🕺","💃","🌃","🚗",
                                 "🛻","🌆","🎶","🎵","⭐️","🔥"]
    static func emoji(for slot: Int) -> String {
        emojis[((slot % emojis.count) + emojis.count) % emojis.count]
    }
}

/// Condensed-black display type — the GTA wordmark / station-name look.
extension Font {
    static func gtaDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.compressed)
    }
    static func gtaMono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

/// Frosted-glass surface used for the HUD bars and panels.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}

/// Radiating "on air" ripple that sits over the playing station's circle.
/// Restarts on its own whenever it (re)appears, so it can be conditionally
/// attached with `if isCurrent`.
struct BroadcastRipple: View {
    @State private var pulse = false
    var body: some View {
        Circle()
            .stroke(Theme.teal.opacity(pulse ? 0 : 0.55), lineWidth: pulse ? 1 : 3)
            .scaleEffect(pulse ? 1.55 : 1)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

/// Tiny 3-bar bouncing equalizer shown on the now-playing station.
struct EqualizerBadge: View {
    @State private var animating = false
    private let low: [CGFloat] = [4, 7, 5]
    private let high: [CGFloat] = [11, 5, 9]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(Theme.teal)
                    .frame(width: 3, height: animating ? high[i] : low[i])
                    .animation(.easeInOut(duration: 0.38 + Double(i) * 0.11)
                        .repeatForever(autoreverses: true), value: animating)
            }
        }
        .frame(height: 12, alignment: .bottom)
        .allowsHitTesting(false)
        .onAppear { animating = true }
    }
}

/// Small circular glass icon button used across the HUD.
struct HUDIconButton: View {
    let system: String
    var active = false
    var tint: Color = Theme.bone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Theme.teal : tint)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(active ? Theme.teal : Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
