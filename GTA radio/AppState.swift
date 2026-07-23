//
//  AppState.swift
//  GTA radio
//
//  Shared app-wide state so the main window AND the radial overlay drive the
//  same store and the same (single) player.
//

import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let store = RadioStore()
    let player = YouTubePlayerController()
    @Published var nowPlaying: Int?

    private init() {}

    func play(slot: Int) {
        guard store.stations.indices.contains(slot) else { return }
        play(store.stations[slot])
    }

    func play(_ station: Station) {
        switch station.source {
        case .video(let id): player.playVideo(id)
        case .playlist(let id): player.playPlaylist(id)
        case .none: return
        }
        nowPlaying = station.id
    }

    func stop() {
        player.stop()
        nowPlaying = nil
    }
}
