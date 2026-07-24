//
//  AppState.swift
//  GTA radio
//
//  Shared app-wide state so the main window AND the radial overlay drive the
//  same store and the same (single) player. Also owns playback position memory
//  so stations resume where you left off instead of restarting.
//

import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let store = RadioStore()
    let player = YouTubePlayerController()

    @Published var nowPlaying: Int?
    @Published var shuffleOn = false
    @Published var volume: Double = 100 { didSet { player.setVolume(Int(volume)) } }

    private var cancellables = Set<AnyCancellable>()
    private var lastPersistedSecond = -1

    private init() {
        // Persist the current station's position every few seconds so a resume
        // survives even if the app is force-quit mid-song.
        player.$currentTime
            .sink { [weak self] t in
                guard let self, let slot = self.nowPlaying else { return }
                let sec = Int(t)
                if sec != self.lastPersistedSecond, sec % 5 == 0 {
                    self.lastPersistedSecond = sec
                    self.commitPosition(for: slot)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Playback

    var isPlaylistPlaying: Bool {
        guard let n = nowPlaying, case .playlist = store.stations[n].source else { return false }
        return true
    }

    func play(slot: Int) {
        guard store.stations.indices.contains(slot) else { return }
        // Remember where the outgoing station was before we leave it.
        if let cur = nowPlaying, cur != slot { commitPosition(for: cur) }

        let station = store.stations[slot]
        let resume = store.resume(for: slot)
        nowPlaying = slot

        switch station.source {
        case .video(let id):
            player.playVideo(id, startSeconds: resume?.seconds ?? 0)
        case .playlist(let id):
            player.playPlaylist(id, index: resume?.index ?? 0, startSeconds: resume?.seconds ?? 0)
        case .none:
            nowPlaying = nil
        }
    }

    func stop() {
        if let cur = nowPlaying { commitPosition(for: cur) }
        player.stop()
        nowPlaying = nil
    }

    /// Reorder a station to a new slot; the playing station keeps playing.
    func moveStation(from: Int, to: Int) {
        // Save the live position first so it travels with the station.
        if let cur = nowPlaying { commitPosition(for: cur) }
        store.move(fromSlot: from, toSlot: to)
        if let cur = nowPlaying {
            nowPlaying = RadioStore.remapIndex(cur, from: from, to: to)
        }
    }

    /// Save the current player position under the given slot.
    func commitPosition(for slot: Int) {
        guard store.stations.indices.contains(slot), !store.stations[slot].isEmpty else { return }
        store.setResume(Resume(seconds: player.currentTime, index: player.currentIndex), forSlot: slot)
    }

    /// Called on app quit so the active station's position isn't lost.
    func commitCurrent() {
        if let cur = nowPlaying { commitPosition(for: cur) }
    }

    // MARK: Transport

    func togglePlayPause() { player.togglePlayPause() }
    func next() { player.next() }
    func previous() { player.previous() }
    func seek(to seconds: Double) { player.seek(to: seconds) }

    /// Tune to a random populated station (shuffle across all 26).
    func shuffleAllStations() {
        let populated = store.stations.filter { !$0.isEmpty && $0.id != nowPlaying }
        let pool = populated.isEmpty ? store.stations.filter { !$0.isEmpty } : populated
        if let pick = pool.randomElement() { play(slot: pick.id) }
    }
    func toggleShuffle() {
        shuffleOn.toggle()
        player.setShuffle(shuffleOn)
    }
}
