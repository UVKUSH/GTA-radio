# Playback pipeline (WKWebView + YouTube IFrame API)

## Shape

```
AppState.play(path:)
  └─ YouTubePlayerController.playVideo / playPlaylist
       └─ evaluateJavaScript("loadVideo('<id>', <start>)")   ← string-built JS
            └─ player.loadVideoById / loadPlaylist (IFrame API)
JS → Swift:  window.webkit.messageHandlers.bridge.postMessage(...)
             types: ready | state | title | time (1 Hz) | error
```

- The webview is created **once** in the controller's init and kept alive for
  the whole app run; SwiftUI only mounts/unmounts a view *onto* it. This is
  the core trick that keeps audio running when the UI changes.
- HTML shell is loaded with `baseURL: http://localhost` — YouTube rejects
  embeds whose page origin is youtube.com itself (error 152); a localhost
  origin is a valid referrer and plays **unmuted**. Same approach as Google's
  own `youtube-ios-player-helper`. (Recorded in project memory too.)
- `mediaTypesRequiringUserActionForPlayback = []` — playback can start
  without a user click, essential for "tune = play".
- Ready-gating: `loadVideo`/`loadList` calls made before the IFrame API is up
  are stored in `pending` and flushed on the JS `ready` message. Only the most
  recent pending call is kept — correct "last wins" behavior for a radio.

## State bridged back to Swift

| JS event | Swift effect |
|---|---|
| `ready` | `ready = true`, flush pending load |
| `state` (1=playing) | `isPlaying`; clears `lastErrorCode` on success |
| `title` | `nowPlayingTitle` (shown under station name) |
| `time` (1 Hz) | `currentTime`, `duration`, playlist `currentIndex` → drives SeekBar + 5-second resume commits |
| `error` | `lastErrorCode` → HUD shows "CAN'T EMBED THIS ONE" |

## Failure modes observed in review

1. **Offline / iframe_api unreachable**: the shell's `<script src=…>` never
   loads, `ready` never fires, a pending tune is queued forever, and the UI
   gives no feedback (dial says "NOW PLAYING" only after state events, so the
   HUD just sits silent). No retry logic exists. → finding M-4.
2. **Embed-restricted videos** surface as error codes (101/150/152) and the
   HUD does say "CAN'T EMBED THIS ONE" — good. The error banner clears on the
   next successful play. Adequate.
3. **`ensurePlay()` forces `setVolume(100)`** on every load, silently undoing
   the user's HUD volume. → finding M-1.
4. **JS is built by string interpolation** (`loadVideo('\(id)'…)`). Video IDs
   are strictly validated (11-char charset) so they're safe; **playlist IDs
   are not validated** in the app's classifier, making the interpolation an
   injection vector. → finding H-1. Playlist IDs from the *page scraper* are
   regex-validated (`[A-Za-z0-9_-]{11}` for videos) and safe.
5. **`seek(to:)` bypasses the `ctl()` try/catch wrapper** and calls
   `window.player.seekTo` directly — guarded by `if(window.player)`, fine, but
   inconsistent with every other control (style nit L-8).

## Performance notes

- 1 Hz time updates → 1 Hz `@Published` writes → SeekBar re-render each
  second. Cheap, no observed issue.
- Resume writes are throttled to every 5th second and deduped; each write
  re-encodes the whole resume dictionary — fine at realistic sizes.
- The persistent webview keeps decoding video even when `opacity(0)` in
  audio-only mode. That is the price of keeping audio alive with the IFrame
  player (it has no true audio-only mode). Acceptable; documented here so
  nobody "optimizes" the hidden webview away and kills the audio.
