//
//  YouTubePlayerView.swift
//  GTA radio
//
//  Official YouTube IFrame Player hosted in a WKWebView. No API key, no
//  media extraction — we only embed the player exactly as YouTube intends.
//

import SwiftUI
import WebKit
import Combine

/// Holds the single long-lived web view so playback survives view redraws.
final class YouTubePlayerController: ObservableObject {
    let webView: WKWebView
    private var isLoaded = false

    init() {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // transparent
    }

    /// Load a single video by ID.
    func playVideo(_ id: String) {
        loadPlayer(embedPath: "\(id)?autoplay=1&enablejsapi=1&playsinline=1")
    }

    /// Load a playlist by ID.
    func playPlaylist(_ id: String) {
        loadPlayer(embedPath: "videoseries?list=\(id)&autoplay=1&enablejsapi=1")
    }

    private func loadPlayer(embedPath: String) {
        let html = """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
        iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src="https://www.youtube-nocookie.com/embed/\(embedPath)"
          allow="autoplay; encrypted-media; picture-in-picture"
          allowfullscreen></iframe>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        isLoaded = true
    }

    func stop() {
        webView.loadHTMLString("<body style='background:#000'></body>", baseURL: nil)
    }
}

/// SwiftUI wrapper that renders the controller's persistent web view.
struct YouTubePlayerView: NSViewRepresentable {
    @ObservedObject var controller: YouTubePlayerController

    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
