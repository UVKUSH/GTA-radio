# GTA Radio v1 (No-API-Key) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A sandboxed macOS app where a user pastes any YouTube URL (video/Shorts/live/playlist/channel/@handle/legacy user) into one of 26 GTA-style radio slots and plays it via the official YouTube IFrame Player — with **zero** API keys, OAuth, or setup.

**Architecture:** All URL parsing, metadata resolution, naming, and caching live in a local Swift package `GTARadioKit` (tested via `swift test`). The app target hosts the UI: a station-manager main window, a global-hotkey radial overlay (26 slots in a circle), and a floating mini-player that owns the single persistent WKWebView running the IFrame Player.

**Tech Stack:** SwiftUI, WKWebView + YouTube IFrame Player API, URLSession, XMLParser, Carbon `RegisterEventHotKey` (sandbox-safe global hotkey), JSON file persistence.

## Global Constraints (from corrected spec — verbatim intent)

- NO YouTube Data API key, OAuth, Google Cloud project, Keychain key storage, quota handling, or credential UI anywhere. App must compile and fully function without credentials.
- Metadata sources are ONLY: public oEmbed, public page Open Graph/HTML, `https://www.youtube.com/feeds/videos.xml?channel_id=…`, video-ID thumbnail URLs (`https://i.ytimg.com/vi/<id>/hqdefault.jpg`).
- Playback ONLY via official IFrame Player in WKWebView. Never extract media URLs, download content, strip branding, block ads, or bypass embedding restrictions.
- 26 station slots. Custom names entered by the user are NEVER overwritten by metadata refresh.
- Name generation: strip leading `@`, strip "- YouTube"/"YouTube" page-title suffixes, collapse "FM FM"/"Radio Radio", cap visible length (40 chars), append "FM" (channels/videos) — e.g. "Lofi Girl FM".
- Channel resolution is one-shot + cached (no continuous scraping). Feed refresh: on station start / cache expiry. Video metadata: manual or multi-day. Playlist: daily. Offline → serve stale cache.
- Channel failure fallback: keep the generated name, show "Choose a video or playlist for this station.", accept a pasted fallback URL. Never crash, never fake playback.
- Metadata loading is async, never blocks the main thread.
- `MetadataProvider` protocol exists for a future Data-API provider, but v1 ships only no-key providers and exposes no key interface.

## File Structure

**Create — `GTARadioKit/` (local SPM package, unit-testable core):**
- `Package.swift`
- `Sources/GTARadioKit/YouTubeURLParser.swift` — URL → `ParsedYouTubeURL` (video/playlist/channelID/handle/customName/legacyUser)
- `Sources/GTARadioKit/StationNameGenerator.swift` — FM-name rules
- `Sources/GTARadioKit/YouTubeOEmbedClient.swift` — oEmbed fetch + `OEmbedResponse` decode
- `Sources/GTARadioKit/YouTubePublicPageResolver.swift` — channel/playlist page HTML → name + canonical channel ID (pure extraction fns + async fetcher)
- `Sources/GTARadioKit/YouTubeChannelFeedParser.swift` — XMLParser delegate → `[ChannelFeedEntry]`
- `Sources/GTARadioKit/YouTubeChannelFeedService.swift` — fetch + parse channel feed
- `Sources/GTARadioKit/MetadataCache.swift` — `CachedStationMetadata` (all spec fields), JSON disk persistence, per-type staleness policy
- `Sources/GTARadioKit/MetadataProvider.swift` — protocol + `StationMetadata` value type
- `Sources/GTARadioKit/NoKeyYouTubeMetadataService.swift` — orchestrator implementing `MetadataProvider`
- `Sources/GTARadioKit/Station.swift` — `Station`, `StationSourceType`, resolution state
- `Sources/GTARadioKit/StationStore.swift` — 26 slots, JSON persistence, custom-name preservation
- `Tests/GTARadioKitTests/…` — one test file per source file above (13 spec'd test areas)

**Create — app target (`GTA radio/`):**
- `Player/YouTubePlayerView.swift` — NSViewRepresentable WKWebView (kept alive app-wide)
- `Player/YouTubePlayerCoordinator.swift` — ObservableObject; JS bridge; play/pause/mute/volume/next/prev/shuffle/loop; state + error events
- `Player/PlayerHTML.swift` — embedded IFrame-API HTML template
- `UI/RadialOverlayView.swift` + `UI/OverlayWindowController.swift` — GTA wheel over a borderless full-screen panel
- `UI/MiniPlayerView.swift` + `UI/MiniPlayerWindowController.swift` — floating always-on-top panel hosting the player
- `UI/StationEditorView.swift` — paste URL, edit name/thumbnail, fallback-URL prompt
- `UI/StationGridView.swift` — 26-slot manager (replaces ContentView body)
- `App/HotKeyManager.swift` — Carbon RegisterEventHotKey (⌥R default)
- `App/AppState.swift` — glue: store + metadata service + player coordinator
- `GTA radio.entitlements` — app-sandbox + network.client

**Modify:**
- `GTA radio.xcodeproj/project.pbxproj` — add local package dependency + entitlements reference
- `GTA radio/GTA_radioApp.swift`, `GTA radio/ContentView.swift` — wire real UI

**Delete/never create (spec):** `YouTubeAPIService.swift`, `YouTubeSettingsView.swift`, any key storage/validation/quota/OAuth code. (None exist yet — this is a fresh template; the correction applies to the plan, and this plan contains none of them.)

---

### Task 1: Package scaffold + YouTubeURLParser (TDD)
**Interfaces produced:**
```swift
public enum ParsedYouTubeURL: Equatable {
  case video(id: String)            // watch?v=, youtu.be, /shorts/, /live/, /embed/
  case playlist(id: String)         // playlist?list= or watch?…&list= (playlist wins only on /playlist path)
  case channelID(String)            // /channel/UC…
  case handle(String)               // /@handle (leading @ stripped)
  case customName(String)           // /c/name
  case legacyUser(String)           // /user/name
}
public struct YouTubeURLParser { public static func parse(_ raw: String) -> ParsedYouTubeURL? }
```
Tests: watch, youtu.be, shorts, live, embed, playlist page, watch+list (video wins), channel, @handle (with/without scheme, trailing path), /c/, /user/, garbage → nil, non-YouTube host → nil, extra query params, http→https, mobile/m. + music. hosts.
Steps: failing tests → run (`cd GTARadioKit && swift test`) → implement → green → commit.

### Task 2: StationNameGenerator (TDD)
```swift
public struct StationNameGenerator {
  public static func stationName(fromCreator name: String) -> String   // "Lofi Girl" → "Lofi Girl FM"
  public static func stationName(fromPageTitle title: String) -> String // strips " - YouTube"
  public static let playlistFallback = "YouTube Playlist FM"
  public static let videoFallback = "YouTube Radio"
}
```
Tests: @handle strip, "- YouTube" suffix strip, "FM FM" collapse, "Radio Radio" collapse, 40-char cap, existing "FM"/"Radio" suffix preserved un-duplicated, whitespace trim.

### Task 3: YouTubeOEmbedClient (TDD on decoding; network via injected `URLSession`-style fetcher)
```swift
public struct OEmbedResponse: Decodable, Equatable { public let title: String; public let authorName: String; public let thumbnailUrl: URL? }
public struct YouTubeOEmbedClient { // init(fetch: @escaping (URL) async throws -> Data)
  public func fetchVideoMetadata(videoID: String) async throws -> OEmbedResponse }
public enum YouTubeThumbnail { public static func url(videoID: String) -> URL } // i.ytimg.com hqdefault
```
Tests: decode real-shaped oEmbed JSON (author_name snake_case), thumbnail fallback URL construction, fetch-failure surfaces error (fallback handled by orchestrator).

### Task 4: YouTubePublicPageResolver (pure HTML extraction, TDD)
```swift
public struct PublicPageInfo: Equatable { public let name: String?; public let channelID: String?; public let canonicalURL: String? }
public struct YouTubePublicPageResolver {
  public static func extract(fromHTML html: String) -> PublicPageInfo  // og:title, og:url, canonical link, "channelId":"UC…", "externalId"
  public func resolveChannelPage(url: URL) async throws -> PublicPageInfo // follows redirects (URLSession default)
  public static func extractPlaylistTitle(fromHTML html: String) -> String? // og:title minus " - YouTube"
}
```
Tests: og:title extraction, channelId JSON extraction, canonical-link extraction, externalId fallback, missing-everything → empty info (no crash), playlist title strip.

### Task 5: Channel feed parser + service (TDD)
```swift
public struct ChannelFeedEntry: Equatable { public let videoID: String; public let title: String; public let thumbnailURL: URL?; public let published: Date? }
public struct YouTubeChannelFeedParser { public static func parse(_ data: Data) -> [ChannelFeedEntry] } // XMLParser, yt:videoId, media:title/thumbnail, newest-first order preserved
public struct YouTubeChannelFeedService { // init(fetch:)
  public static func feedURL(channelID: String) -> URL
  public func fetchRecentVideos(channelID: String) async throws -> [ChannelFeedEntry] }
```
Tests: parse a real-shaped Atom feed fixture (2+ entries, ordering, videoId not entry-id), malformed XML → [], missing thumbnail tolerated, feedURL format.

### Task 6: MetadataCache (TDD)
```swift
public struct CachedStationMetadata: Codable, Equatable { originalURL, normalizedURL, sourceType, channelID?, channelName?, videoIDs, titles, thumbnailURLs, lastRefresh }
public final class MetadataCache { // init(directory: URL) — file-per-normalized-key JSON
  public func store(_:); public func lookup(normalizedURL: String) -> CachedStationMetadata?
  public func isStale(_ entry:, policy: RefreshPolicy, now: Date) -> Bool }
public enum RefreshPolicy { case video /*7d*/, playlist /*1d*/, channel /*6h*/ }
```
Tests: round-trip persistence, staleness per policy boundary, stale-entry still returned (offline use), corrupt file → nil not crash.

### Task 7: MetadataProvider + NoKeyYouTubeMetadataService (orchestrator, TDD with injected fakes)
```swift
public struct StationMetadata: Equatable { public var stationName: String; public var sourceType: StationSourceType; public var videoQueue: [String]; public var playlistID: String?; public var channelID: String?; public var thumbnailURL: URL?; public var nowPlayingTitle: String?; public var needsFallbackContent: Bool }
public protocol MetadataProvider { func resolve(url: String) async -> StationMetadata? }
public final class NoKeyYouTubeMetadataService: MetadataProvider { /* per-type priority chains from spec; cache-first; never throws to UI */ }
```
Tests: video via oEmbed → "<author> FM"; oEmbed fails → thumbnail URL + "YouTube Radio" + still playable; playlist page title; playlist title fails → "YouTube Playlist FM"; channel happy path (page → name+ID → feed → queue); channel name-only (feed fails) → `needsFallbackContent = true`, name kept; cache hit skips fetch; stale cache used when fetch throws (offline).

### Task 8: Station + StationStore (TDD)
```swift
public struct Station: Codable, Equatable, Identifiable { public let id: Int /*0–25*/; public var sourceURL: String?; public var metadata-mirror fields…; public var customName: String?; public var displayName: String { customName ?? generatedName ?? "Empty Slot" } }
public final class StationStore: ObservableObject { // JSON at Application Support/GTARadio/stations.json
  @Published public private(set) var stations: [Station] // always 26
  public func assign(url: String, metadata: StationMetadata, toSlot: Int)
  public func setCustomName(_:, forSlot:); public func applyRefreshedMetadata(_:, toSlot:) // must NOT touch customName
  public func clearSlot(_:) }
```
Tests: always-26 invariant (fresh + corrupt file), persistence round-trip, custom name survives `applyRefreshedMetadata`, clearSlot resets.

### Task 9: Wire package + entitlements into the app target
- Add `XCLocalSwiftPackageReference "GTARadioKit"` + product dependency to pbxproj; create `GTA radio/GTA radio.entitlements` (app-sandbox YES, network.client YES); set `CODE_SIGN_ENTITLEMENTS`.
- Verify: `xcodebuild -project "GTA radio.xcodeproj" -scheme "GTA radio" build` succeeds and `swift test` still green. Commit.

### Task 10: Player (HTML + view + coordinator)
- `PlayerHTML.swift`: IFrame API page — `enablejsapi=1`, `origin` via loadHTMLString baseURL `https://www.youtube.com`; JS functions `loadVideo(id)`, `loadPlaylist(listId)`, `cueQueue(ids)` (uses `loadPlaylist({playlist: ids})` for channel queues), `next/prev/setShuffle/setLoop/play/pause/mute/unMute/setVolume`; posts `onStateChange`/`onError`/now-playing (`getVideoData`) through `window.webkit.messageHandlers.player`.
- `YouTubePlayerCoordinator: NSObject, ObservableObject, WKScriptMessageHandler` — published `playerState`, `nowPlayingTitle`, `isBuffering`, `lastError`; owns the single `WKWebView` (created once, never torn down when overlay closes).
- `YouTubePlayerView: NSViewRepresentable` renders the coordinator's web view.
- Playback errors (embedding blocked, private) surface as user-visible state — never faked.

### Task 11: Radial overlay + global hotkey
- `HotKeyManager` (Carbon RegisterEventHotKey, ⌥R) toggles `OverlayWindowController` — borderless, `.screenSaver`-level, transparent, full-screen NSPanel; ESC/click-outside/second-press closes; closing does NOT stop playback.
- `RadialOverlayView`: 26 station icons on a circle (angle = index/26 · 2π − π/2), center shows hovered/current station name + now-playing title, click selects & starts playback.

### Task 12: Mini player, station grid, editor
- `MiniPlayerWindowController`: small floating `.floating`-level panel hosting `MiniPlayerView` (thumbnail/webview, title, prev/play-pause/next/shuffle/loop/volume, mute).
- `StationGridView` (main window): 26 slots; paste URL → async resolve (spinner) → assigned; per-slot context: Edit (StationEditorView: name field marks custom, fallback-URL field shown when `needsFallbackContent` with copy "Choose a video or playlist for this station."), Refresh metadata, Clear.
- Wire `AppState` in `GTA_radioApp.swift`; `ContentView` hosts `StationGridView`.

### Task 13: Final verification
- `swift test` (all green) + `xcodebuild build` (no warnings about missing entitlements), manual smoke checklist in commit message; append STATE.md activity line.

## Self-Review
- Spec coverage: every corrected-spec section maps to a task (URL types→T1, naming→T2, oEmbed→T3, page resolver→T4, feed→T5, cache→T6, priority/fallback→T7, slots/custom-name→T8, playback+controls+keep-alive→T10, hotkey/overlay/mini-player→T11-12, tests→T1-8, no-key constraint→global).
- No API-key surface anywhere. `MetadataProvider` protocol satisfies future-proofing without exposing keys.
- Type names are consistent across tasks (checked: `StationMetadata`, `ParsedYouTubeURL`, `ChannelFeedEntry`, `CachedStationMetadata`).
