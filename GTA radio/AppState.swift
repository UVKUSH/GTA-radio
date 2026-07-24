//
//  AppState.swift
//  GTA radio
//
//  Shared app-wide state. Stations form a tree (folders can hold their own 26),
//  so playback and navigation are addressed by paths. Resume position tracks the
//  playing station by its stable uid, so it survives reorders and nesting.
//

import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let store = RadioStore()
    let player = YouTubePlayerController()

    /// Which folder is currently open ([] = root).
    @Published var currentPath: [Int] = []
    /// The playing station's stable id (nil = off air).
    @Published var nowPlayingUID: UUID?
    @Published var nowPlayingIsPlaylist = false

    @Published var shuffleOn = false
    @Published var volume: Double = UserDefaults.standard.object(forKey: "volume") as? Double ?? 100 {
        didSet {
            player.setVolume(Int(volume))
            UserDefaults.standard.set(volume, forKey: "volume")
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var lastPersistedSecond = -1

    private init() {
        // didSet doesn't run for the initial value — hand the restored volume
        // to the player so the first tune honors it.
        player.setVolume(Int(volume))
        player.$currentTime
            .sink { [weak self] t in
                guard let self, let uid = self.nowPlayingUID else { return }
                let sec = Int(t)
                if sec != self.lastPersistedSecond, sec % 5 == 0 {
                    self.lastPersistedSecond = sec
                    self.commitPosition(uid: uid)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Navigation

    var currentStations: [Station] { store.children(at: currentPath) }
    var currentFolderName: String? { store.node(at: currentPath)?.displayName }
    var isInFolder: Bool { !currentPath.isEmpty }

    func enterFolder(index: Int) { currentPath.append(index) }
    func goBack() { if !currentPath.isEmpty { currentPath.removeLast() } }
    func goHome() { currentPath.removeAll() }

    // MARK: Playback

    var hasNowPlaying: Bool { nowPlayingUID != nil }
    var isPlaylistPlaying: Bool { nowPlayingUID != nil && nowPlayingIsPlaylist }

    /// Play the station at `path`. (Callers only pass station paths, not folders.)
    func play(path: [Int]) {
        guard let node = store.node(at: path), !node.isFolder else { return }
        if let prev = nowPlayingUID { commitPosition(uid: prev) }

        let resume = store.resume(forUID: node.uid)
        nowPlayingUID = node.uid
        // A freshly loaded list always starts unshuffled — keep the UI honest.
        shuffleOn = false

        switch node.source {
        case .video(let id):
            nowPlayingIsPlaylist = false
            player.playVideo(id, startSeconds: resume?.seconds ?? 0)
        case .playlist(let id):
            nowPlayingIsPlaylist = true
            player.playPlaylist(id, index: resume?.index ?? 0, startSeconds: resume?.seconds ?? 0)
        case .none:
            nowPlayingUID = nil
        }
    }

    func stop() {
        if let uid = nowPlayingUID { commitPosition(uid: uid) }
        player.stop()
        nowPlayingUID = nil
    }

    func commitPosition(uid: UUID) {
        store.setResume(Resume(seconds: player.currentTime, index: player.currentIndex), forUID: uid)
    }

    func commitCurrent() {
        if let uid = nowPlayingUID { commitPosition(uid: uid) }
    }

    /// Reorder within the current folder; playing station keeps playing (uid-tracked).
    func moveStation(from: Int, to: Int) {
        store.move(inFolder: currentPath, from: from, to: to)
    }

    /// Tune to a random playable station in the current folder.
    func shuffleAllStations() {
        let pool = currentStations.filter { !$0.isEmpty && !$0.isFolder && $0.uid != nowPlayingUID }
        let fallback = currentStations.filter { !$0.isEmpty && !$0.isFolder }
        if let pick = (pool.isEmpty ? fallback : pool).randomElement() {
            play(path: currentPath + [pick.id])
        }
    }

    // MARK: Transport

    func togglePlayPause() { player.togglePlayPause() }
    func next() { player.next() }
    func previous() { player.previous() }
    func seek(to seconds: Double) { player.seek(to: seconds) }
    func toggleShuffle() {
        shuffleOn.toggle()
        player.setShuffle(shuffleOn)
    }
}
