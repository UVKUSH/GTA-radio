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
                .frame(width: 42, alignment: .leading)

            Slider(value: Binding(
                get: { value },
                set: { scrubbing = $0 }
            ), in: 0...duration) { editing in
                if !editing, let s = scrubbing {
                    app.seek(to: s)
                    scrubbing = nil
                }
            }
            .tint(Theme.magenta)
            .disabled(app.nowPlaying == nil || player.duration <= 0)

            Text(timecode(duration))
                .font(.gtaMono(10)).foregroundStyle(Theme.muted)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
