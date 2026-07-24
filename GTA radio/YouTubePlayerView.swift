//
//  YouTubePlayerView.swift
//  GTA radio
//
//  Official YouTube IFrame Player API hosted in a WKWebView. No API key, no
//  media extraction — we embed the player exactly as YouTube intends and drive
//  it with loadVideoById / loadPlaylist. The web view is created once and kept
//  alive so audio keeps playing while the UI (and overlay) come and go.
//
//  NOTE: the player HTML is loaded with baseURL `http://localhost`. YouTube
//  rejects an embed whose page origin is youtube.com itself (IFrame error 152);
//  a localhost origin is a valid embedding referrer and plays unmuted. This is
//  the same approach Google's youtube-ios-player-helper uses.
//

import SwiftUI
import WebKit
import Combine

final class YouTubePlayerController: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView

    @Published var isPlaying = false
    @Published var nowPlayingTitle: String?
    @Published var lastErrorCode: Int?
    @Published var currentTime: Double = 0
    @Published var currentIndex: Int = -1   // playlist index, -1 if not a playlist

    private var ready = false
    private enum Pending { case video(String, Double), playlist(String, Int, Double) }
    private var pending: Pending?

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        // Critical for a radio app: let the player start with sound, no click.
        config.mediaTypesRequiringUserActionForPlayback = []
        let ucc = WKUserContentController()
        config.userContentController = ucc

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        ucc.add(self, name: "bridge")
        webView.navigationDelegate = self
        if webView.responds(to: Selector(("setDrawsBackground:"))) {
            webView.setValue(false, forKey: "drawsBackground")
        }
        loadPlayerShell()
    }

    // MARK: Load

    func playVideo(_ id: String, startSeconds: Double = 0) {
        lastErrorCode = nil
        currentIndex = -1
        if ready { evaluate("loadVideo('\(id)',\(startSeconds))") }
        else { pending = .video(id, startSeconds) }
    }

    func playPlaylist(_ id: String, index: Int = 0, startSeconds: Double = 0) {
        lastErrorCode = nil
        if ready { evaluate("loadList('\(id)',\(index),\(startSeconds))") }
        else { pending = .playlist(id, index, startSeconds) }
    }

    // MARK: Transport

    func play() { evaluate("ctl('play')") }
    func pause() { evaluate("ctl('pause')") }
    func togglePlayPause() { isPlaying ? pause() : play() }
    func next() { evaluate("ctl('next')") }
    func previous() { evaluate("ctl('prev')") }
    func setShuffle(_ on: Bool) { evaluate("ctl('shuffle',\(on))") }
    func setVolume(_ v: Int) { evaluate("ctl('vol',\(v))") }
    func mute() { evaluate("ctl('mute')") }
    func unmute() { evaluate("ctl('unmute')") }

    func stop() {
        evaluate("ctl('stop')")
        isPlaying = false
        nowPlayingTitle = nil
        currentTime = 0
        currentIndex = -1
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            flushPending()
        case "state":
            if let s = body["state"] as? Int {
                isPlaying = (s == 1)
                if s == 1 { lastErrorCode = nil }
            }
        case "title":
            if let t = body["title"] as? String, !t.isEmpty { nowPlayingTitle = t }
        case "time":
            if let t = body["t"] as? Double { currentTime = t }
            if let i = body["idx"] as? Int { currentIndex = i }
        case "error":
            if let code = body["code"] as? Int { lastErrorCode = code }
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

    // MARK: Internals

    private func flushPending() {
        switch pending {
        case .video(let id, let s): evaluate("loadVideo('\(id)',\(s))")
        case .playlist(let id, let i, let s): evaluate("loadList('\(id)',\(i),\(s))")
        case .none: break
        }
        pending = nil
    }

    private func evaluate(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func loadPlayerShell() {
        webView.loadHTMLString(Self.playerHTML, baseURL: URL(string: "http://localhost"))
    }

    private static let playerHTML = """
    <!DOCTYPE html><html><head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{width:100%;height:100%}</style>
    </head><body>
    <div id="p"></div>
    <script>
    var player, ready=false;
    function post(m){ try{ window.webkit.messageHandlers.bridge.postMessage(m); }catch(e){} }
    function startTimer(){
      if(window._t) return;
      window._t = setInterval(function(){
        try{ post({type:'time', t:player.getCurrentTime(), idx:(player.getPlaylistIndex?player.getPlaylistIndex():-1)}); }catch(e){}
      }, 1000);
    }
    function onYouTubeIframeAPIReady(){
      player = new YT.Player('p', {
        width:'100%', height:'100%',
        playerVars:{ autoplay:0, playsinline:1, controls:1, rel:0, modestbranding:1 },
        events:{
          onReady:function(){ ready=true; window.player=player; startTimer(); post({type:'ready'}); },
          onStateChange:function(e){
            post({type:'state', state:e.data});
            if(e.data===1){ var d=player.getVideoData?player.getVideoData():null; post({type:'title', title:d?d.title:''}); }
          },
          onError:function(e){ post({type:'error', code:e.data}); }
        }
      });
    }
    function ensurePlay(){ if(!player) return; player.unMute(); player.setVolume(100); player.playVideo(); }
    function loadVideo(id,start){ if(player&&player.loadVideoById){ player.loadVideoById({videoId:id, startSeconds:start||0}); ensurePlay(); } }
    function loadList(id,index,start){ if(player&&player.loadPlaylist){ player.loadPlaylist({list:id, listType:'playlist', index:index||0, startSeconds:start||0}); ensurePlay(); } }
    function ctl(cmd,arg){
      if(!player) return;
      try{
        if(cmd==='play') player.playVideo();
        else if(cmd==='pause') player.pauseVideo();
        else if(cmd==='next') player.nextVideo();
        else if(cmd==='prev') player.previousVideo();
        else if(cmd==='shuffle') player.setShuffle(arg);
        else if(cmd==='vol'){ player.unMute(); player.setVolume(arg); }
        else if(cmd==='mute') player.mute();
        else if(cmd==='unmute') player.unMute();
        else if(cmd==='stop') player.stopVideo();
      }catch(e){}
    }
    var s=document.createElement('script'); s.src='https://www.youtube.com/iframe_api'; document.head.appendChild(s);
    </script>
    </body></html>
    """
}

/// SwiftUI wrapper that renders the controller's persistent web view.
struct YouTubePlayerView: NSViewRepresentable {
    @ObservedObject var controller: YouTubePlayerController

    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
