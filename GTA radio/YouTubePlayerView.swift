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
    @Published var duration: Double = 0
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

    /// Last volume the UI asked for; re-applied on every load so tuning a new
    /// station keeps the user's level instead of resetting to 100.
    private var lastVolume = 100

    func playVideo(_ id: String, startSeconds: Double = 0) {
        lastErrorCode = nil
        currentIndex = -1
        if ready { evaluate("loadVideo('\(id)',\(startSeconds),\(lastVolume))") }
        else { pending = .video(id, startSeconds) }
    }

    func playPlaylist(_ id: String, index: Int = 0, startSeconds: Double = 0) {
        lastErrorCode = nil
        if ready { evaluate("loadList('\(id)',\(index),\(startSeconds),\(lastVolume))") }
        else { pending = .playlist(id, index, startSeconds) }
    }

    // MARK: Transport

    func play() { evaluate("ctl('play')") }
    func pause() { evaluate("ctl('pause')") }
    func togglePlayPause() { isPlaying ? pause() : play() }
    func next() { evaluate("ctl('next')") }
    func previous() { evaluate("ctl('prev')") }
    func setShuffle(_ on: Bool) { evaluate("ctl('shuffle',\(on))") }
    func setVolume(_ v: Int) { lastVolume = v; evaluate("ctl('vol',\(v))") }
    func mute() { evaluate("ctl('mute')") }
    func unmute() { evaluate("ctl('unmute')") }
    func seek(to seconds: Double) { evaluate("if(window.player)window.player.seekTo(\(seconds),true)") }

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
            if let d = body["dur"] as? Double { duration = d }
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
        case .video(let id, let s): evaluate("loadVideo('\(id)',\(s),\(lastVolume))")
        case .playlist(let id, let i, let s): evaluate("loadList('\(id)',\(i),\(s),\(lastVolume))")
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
        try{ post({type:'time', t:player.getCurrentTime(), dur:player.getDuration(), idx:(player.getPlaylistIndex?player.getPlaylistIndex():-1)}); }catch(e){}
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
    // NOTE: load*() calls autoplay on their own. Do NOT call playVideo() right
    // after them — a playVideo() issued while a new playlist is still loading
    // makes the player resume the OLD playlist and drop the new one (this was
    // the "second playlist never loads" bug).
    function applyAudio(vol){ if(!player) return; player.unMute(); if(typeof vol==='number'&&vol>=0) player.setVolume(vol); }
    function loadVideo(id,start,vol){ if(player&&player.loadVideoById){ player.loadVideoById({videoId:id, startSeconds:start||0}); applyAudio(vol); } }
    function loadList(id,index,start,vol){
      if(!player||!player.loadPlaylist) return;
      try{ player.stopVideo(); }catch(e){}   // clear old list so the new one always takes
      player.loadPlaylist({list:id, listType:'playlist', index:index||0, startSeconds:start||0});
      applyAudio(vol);
    }
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
