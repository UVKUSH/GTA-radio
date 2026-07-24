//
//  SeekBar.swift
//  GTA radio
//
//  Scrub bar with elapsed / remaining time. Dragging seeks the player.
//

import SwiftUI

struct SeekBar: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var player = AppState.shared.player
    @State private var scrubbing: Double?

    var body: some View {
        let duration = max(player.duration, 0.1)
        let value = scrubbing ?? min(player.currentTime, duration)

        HStack(spacing: 10) {
            Text(timecode(value))
                .font(.gtaMono(10)).foregroundStyle(Theme.muted)
                .frame(width: 56, alignment: .leading)

            Slider(value: Binding(
                // Clamp: a scrub started on a longer track must not exceed the
                // range after the playlist advances to a shorter one.
                get: { min(value, duration) },
                set: { scrubbing = $0 }
            ), in: 0...duration) { editing in
                if !editing, let s = scrubbing {
                    app.seek(to: s)
                    scrubbing = nil
                }
            }
            .tint(Theme.magenta)
            .disabled(!app.hasNowPlaying || player.duration <= 0)

            Text(timecode(duration))
                .font(.gtaMono(10)).foregroundStyle(Theme.muted)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        // Long mixes and live archives run past an hour — show it.
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
