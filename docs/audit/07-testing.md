# Testing

## What exists

- `GTARadioKit/Tests/YouTubeURLParserTests.swift` (~130 lines): solid table
  of cases for the URL parser — watch/shorts/live/embed/youtu.be, playlist,
  channel/handle/user forms, invalid IDs, scheme-less input.
- **That's it.** The app target has zero tests, and (ironically) the tested
  parser isn't the one the app uses (finding M-2).

## Verification currently relied on

Manual: build (`xcodebuild`) + run + eyeball. Recent regressions that tests
would have caught earlier: the audio-mode resize lock (layout-level, hard to
unit test) and the dial hover oscillation (interaction-level, likewise) —
but also several that *are* unit-testable and went untested (below).

## Highest-value tests to add (in order)

1. **`RadioStore.classify`** — table test mirroring the package tests, plus
   the hostile cases from finding H-1 (`list=');alert(1);//` must be
   rejected). If M-2 is done (delegate to `YouTubeURLParser`), this collapses
   into the existing suite plus a thin mapping test.
2. **`PlaylistPageResolver.extractVideoIDs/extractTitle`** — pure functions
   over HTML strings; fixture files with a real (trimmed) playlist page, a
   consent page, and junk. Locks in dedupe, ordering, limit, title cleanup.
3. **Preset round-trip** — save → export data → import → identical stations
   (minus fresh preset id), name de-dupe (" 2"), pad/trim to 26, positional
   id re-stamp. All pure `RadioStore` logic; construct with a temp directory.
4. **Tree mutation invariants** — after any `move`/`assign`/`clear`/
   `makeFolder` sequence: `id == index` at every level, uid stability for
   moved nodes, resume key preserved across a move.
5. **`Station` lenient decoding** — legacy JSON without uid/isFolder/children
   still decodes; unknown junk fields ignored; uid minted once and stable
   after `persist()`.
6. **Naming helpers** — `stationName(fromCreator:)` (" - Topic" strip, FM
   suffix rules, 40-char cap) and `trackName(fromTitle:)` (ellipsis cap).

## Structural blockers & how to handle them

- `RadioStore` is `@MainActor` and touches the filesystem in `init` —
  inject the directory (or a protocol) to point at a temp dir in tests;
  annotate tests `@MainActor`. No redesign needed.
- Player/webview and overlay motion are best left to manual QA; don't chase
  UI automation for a hobby-scale app. A short manual smoke checklist lives
  below.

## Manual smoke checklist (pre-release)

1. Paste video URL → plays; paste playlist → 4 options behave; picker
   double-click and multi-select fill only empty slots.
2. Resize window in video mode **and** audio-only mode.
3. Dial: open via hotkey, hover sweep (sound on every slot, magenta hover,
   teal on-air), folder in/out, Esc behavior, click-to-tune, close ≠ stop.
4. Wheels: save, load (check "Last session" appears), ⌘1–9, export → import
   round-trip, rename/delete.
5. Resume: play 30s, switch station, switch back → resumes ±5s; quit and
   relaunch → resumes.
6. Kill network → tune → relaunch with network → player recovers (currently
   fails: finding M-4 — keep on the list to verify the fix).
