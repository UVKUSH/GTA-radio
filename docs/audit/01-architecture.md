# Architecture

## Module map

```
GTA_radioApp (App / @main)
├── AppDelegate ─── HotKeyManager (Carbon global hotkey)
│                └─ OverlayWindowController (borderless NSPanel)
│                        └─ RadialOverlayView (the dial)
├── WindowGroup ── ContentView (HUD: filmstrip, transport, sheets)
│                        ├─ WheelsSheet (presets)
│                        ├─ TransportControls / SeekBar (shared w/ dial)
│                        └─ YouTubePlayerView (renders the persistent WKWebView)
├── Settings ───── SettingsView ── SettingsStore (UserDefaults)
└── Commands ───── WheelsCommands (⌘1–9 quick-switch menu)

AppState (singleton, @MainActor)          ← the hub
├── RadioStore (station tree + presets + resume, JSON persistence)
└── YouTubePlayerController (WKWebView + IFrame API bridge)

GTARadioKit (SwiftPM package)             ← ⚠ currently unused by the app
└── YouTubeURLParser (+ tests)
```

## Key design decisions (all good, worth preserving)

- **Player outlives UI.** `YouTubePlayerController` owns one `WKWebView`
  created at startup and never recreated; `YouTubePlayerView` is just an
  `NSViewRepresentable` window onto it. Closing the overlay or resizing never
  interrupts audio. In audio-only mode the same webview is simply `opacity(0)`
  — *hidden, not removed* — which keeps sound alive.
- **Stations are a value-type tree.** `Station` is a struct; folders hold
  `children: [Station]` (26 each, recursively). All mutation goes through
  `RadioStore.update(at:)` → path-addressed `mutate` recursion → `persist()`.
  Value semantics is what makes wheel presets a safe deep copy for free.
- **Identity is `uid`, position is `id`.** `id` (0–25) is the slot index and
  changes on reorder; `uid: UUID` is stable and keys resume positions and
  now-playing. This split survives reorders, nesting, and preset round-trips.
- **Navigation is a path.** `AppState.currentPath: [Int]` addresses the open
  folder; play/rename/clear all take `basePath + [slot]` paths.
- **No API key anywhere.** Metadata via oEmbed (`youtube.com/oembed`) and
  public playlist-page HTML scraping (`PlaylistPageResolver`). Thumbnails via
  `i.ytimg.com/vi/<id>/mqdefault.jpg` (needs no fetch to construct).
- **Hotkey via Carbon `RegisterEventHotKey`** — sandbox-safe, no Accessibility
  permission needed (unlike `NSEvent` global monitors).
- **Dial hover is sector-based.** `RadialOverlayView` computes the hovered
  slot from the mouse angle (`onContinuousHover` + `atan2`), NOT per-node
  `.onHover`, because hover-driven motion moves nodes out from under the
  cursor (see docs/audit/05-findings.md → resolved items).

## Data flow

```
paste URL → RadioStore.classify → StationSource → assign(url:at:)
                                                     ├─ immediate: provisional name + thumbnail, persist
                                                     └─ async: oEmbed / playlist-page fetch → better name/thumb

tap station → AppState.play(path:) → resume lookup (uid) → player.playVideo/playPlaylist
player JS bridge → currentTime ticks → AppState commits Resume every 5s (uid-keyed)

save wheel  → WheelPreset(snapshot of [Station]) → presets.json
load wheel  → auto-backup current → stations = preset.stations → goHome()
```

## Concurrency model

Everything user-facing is `@MainActor` (`AppState`, `RadioStore`) or
main-thread-in-practice (`SettingsStore`, `YouTubePlayerController` — WKWebView
callbacks arrive on main). Async work is `Task { await ... }` from the UI with
results applied through `update(at:)` guarded by "is the node still the same
source?" checks, which prevents stale metadata landing on a reassigned slot.

## Styling system

`Theme` centralizes tokens (ink/bone/muted/magenta/teal), the condensed-black
"GTA display" font, faux FM frequencies, and shared components (`GlassPanel`,
`HUDIconButton`, `BroadcastRipple`, `EqualizerBadge`). Color language:
**teal = on air, magenta = hover/brand/add.**
