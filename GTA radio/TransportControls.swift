//
//  TransportControls.swift
//  GTA radio
//
//  Shared playback transport — used in the main-window HUD and the radial
//  dial's center. Previous / next / shuffle apply to playlists only.
//

import SwiftUI

struct TransportControls: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var player = AppState.shared.player

    /// Larger central play button + volume for the main HUD; compact for the wheel.
    var showsVolume = true
    var playSize: CGFloat = 48

    var body: some View {
        HStack(spacing: 18) {
            control("backward.fill", enabled: app.isPlaylistPlaying) { app.previous() }

            Button { app.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: playSize, weight: .semibold))
                    .foregroundStyle(Theme.bone)
                    .shadow(color: .black.opacity(0.4), radius: 6)
            }
            .buttonStyle(.plain)
            .disabled(!app.hasNowPlaying)

            control("forward.fill", enabled: app.isPlaylistPlaying) { app.next() }

            control("shuffle", enabled: app.isPlaylistPlaying, active: app.shuffleOn) { app.toggleShuffle() }

            if showsVolume {
                HStack(spacing: 6) {
                    Image(systemName: app.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                    Slider(value: $app.volume, in: 0...100)
                        .frame(width: 90)
                        .tint(Theme.teal)
                }
                .padding(.leading, 4)
            }
        }
    }

    private func control(_ system: String, enabled: Bool, active: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active ? Theme.teal : (enabled ? Theme.bone : Theme.muted.opacity(0.4)))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
