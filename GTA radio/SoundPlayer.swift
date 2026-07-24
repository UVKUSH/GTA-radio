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

    private var rotation = 0

    /// Play the next blip, cycling 1→2→3 so consecutive hovers never repeat.
    func hoverRotate() {
        guard SettingsStore.shared.uiSounds, !players.isEmpty else { return }
        rotation = (rotation + 1) % players.count
        let p = players[rotation]
        p.currentTime = 0
        p.play()
    }
}
