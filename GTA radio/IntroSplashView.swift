//
//  IntroSplashView.swift
//  GTA radio
//
//  First-thing-you-see intro shown on every launch: plays Media/intro.mp4
//  (its own audio muted) with Media/intro.mp3 as the sound. The clips are
//  DIFFERENT lengths on purpose (video ~4.47s, sound ~3.16s) and are never
//  trimmed — each just plays from the start; the sound finishes a touch early.
//
//  Dismisses when the video reaches its end, or immediately on a click / Esc.
//

import SwiftUI
import AVKit
import AVFoundation

struct IntroSplashView: View {
    /// Called once the intro is finished (after its fade-out) so the host can
    /// drop this view from the hierarchy.
    var onFinish: () -> Void

    @State private var player: AVPlayer?
    @State private var sound: AVAudioPlayer?
    @State private var opacity: Double = 1
    @State private var didFinish = false      // guards double-dismiss (tap + end both fire)

    var body: some View {
        ZStack {
            Color.black
            if let player {
                // .resizeAspect = letterbox: the whole frame is shown, never
                // cropped or stretched — the video plays exactly as authored.
                PlayerLayerView(player: player)
            }
            // Invisible Esc handler (reliable in a window regardless of focus).
            Button("", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)     // click anywhere to skip
        .opacity(opacity)
        .onAppear(perform: start)
        .onDisappear { player?.pause(); sound?.stop() }
    }

    private func start() {
        guard let videoURL = Bundle.main.url(forResource: "intro", withExtension: "mp4") else {
            onFinish(); return
        }
        let item = AVPlayerItem(url: videoURL)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true                         // use the mp3, not the video's track
        avPlayer.actionAtItemEnd = .pause
        player = avPlayer

        if let soundURL = Bundle.main.url(forResource: "intro", withExtension: "mp3"),
           let ap = try? AVAudioPlayer(contentsOf: soundURL) {
            ap.prepareToPlay()
            ap.play()
            sound = ap
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { _ in dismiss() }

        avPlayer.play()
    }

    private func dismiss() {
        guard !didFinish else { return }
        didFinish = true
        player?.pause()
        sound?.stop()
        withAnimation(.easeOut(duration: 0.35)) { opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: onFinish)
    }
}

/// Hosts an AVPlayerLayer with no transport controls (unlike AVKit's
/// VideoPlayer, which shows a scrubber on hover) and keeps it sized to the view.
private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView { PlayerContainer(player: player) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PlayerContainer)?.playerLayer.player = player
    }

    final class PlayerContainer: NSView {
        let playerLayer = AVPlayerLayer()

        init(player: AVPlayer) {
            super.init(frame: .zero)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            playerLayer.frame = bounds
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }
}
