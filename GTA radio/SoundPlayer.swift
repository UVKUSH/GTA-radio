//
//  SoundPlayer.swift
//  GTA radio
//
//  Short UI blips played as you move across stations on the radial dial.
//  Three bundled clips (menu1–3); we pick one by index so adjacent stations
//  sound different, giving the wheel a tactile "tuning" feel.
//

import AVFoundation

final class SoundPlayer {
    static let shared = SoundPlayer()
    private var players: [AVAudioPlayer] = []

    private init() {
        for name in ["menu1", "menu2", "menu3"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
               let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay()
                players.append(p)
            }
        }
    }

    /// Play the blip for a given station index (restarts if mid-play).
    func hover(_ index: Int) {
        guard !players.isEmpty else { return }
        let p = players[((index % players.count) + players.count) % players.count]
        p.currentTime = 0
        p.play()
    }
}
