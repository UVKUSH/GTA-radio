# Feature inventory

## Main window (ContentView — "Los Santos night HUD")

- Full-bleed YouTube video background (or blurred artwork + 220pt card in
  audio-only mode), with top/bottom scrim gradients.
- Top bar: wordmark, breadcrumb (folder navigation), Wheels button,
  shuffle, audio-only toggle, settings.
- Bottom HUD: now-playing block (station + track title + faux FM frequency +
  kind badge), transport, seek bar, then the **filmstrip** of 26 station dials.
- Filmstrip dials: tap to play / open folder / add; context menu
  (play, rename, clear, new folder, add URL); drag-and-drop reorder;
  hover scale; on-air ripple + equalizer badge on the playing dial.
- Window enforces 820×560 minimum; resizes freely in both video and audio
  modes (audio-mode resize was fixed 2026-07-23).

## Add-station sheet

- Paste any YouTube URL; live classification label (Video / Playlist / not
  recognized). Videos: plain **Add**.
- Playlists offer four options:
  1. **Pick videos yourself…** — in-sheet browser of up to 100 playlist
     videos (thumbnail + lazily-fetched title). Click = ordered multi-select,
     double-click = add instantly. Fills the opened slot first, then only
     *empty* slots — never overwrites.
  2. **Add as one station** — the slot plays the whole playlist.
  3. **Fill 26 slots from playlist** — each slot becomes one video, named by
     its title (⚠ overwrites occupied slots — see findings).
  4. **Set all 26 to this playlist** — every slot = same playlist.

## Radial dial overlay

- Global hotkey (default ⌥R, configurable) toggles a borderless, transparent,
  non-activating `NSPanel` at `.screenSaver` level, on all Spaces.
- 26 stations on a circle; folders open into their own ring (Esc = back/close;
  background click closes; closing never stops playback).
- Center: focused-station name/status, folder breadcrumb, transport + volume.
- Motion: staggered bloom on open, slow counter-rotating tick rings,
  dock-style fisheye + radial pop-out + wobble on hover, whole-wheel lean
  toward the hovered station, press-bounce on click, animated folder swaps.
- Hover is **sector-based** (mouse angle), works over all 26 slots including
  empty ones; every slot hop plays a rotating menu blip (menu1–3.m4a).
- Now playing: teal ring + broadcast ripple + equalizer badge.
  Hover: magenta. Teal always wins on the playing station.

## Playback

- Official YouTube IFrame player in a persistent WKWebView (`http://localhost`
  baseURL to satisfy embed origin rules — error 152 otherwise).
- Video and playlist sources; playlist transport (prev/next/shuffle) enabled
  only when a playlist is playing.
- **Resume everywhere**: position (and playlist index) saved every 5 seconds
  keyed by station uid; tuning back resumes. Committed on stop, station
  switch, and app quit.
- Volume slider (HUD + dial center). ⚠ See findings: player shell currently
  forces volume to 100 on each load.

## Wheels (saved layouts)

- Save the entire 26-slot tree under a name (same-name save overwrites).
- My Wheels sheet: thumbnail collage, station count, relative save time,
  load / rename / delete / export.
- **"Last session" auto-backup** before every load — swapping can never lose
  the current wheel.
- **⌘1–9** hot-swap via the menu-bar Wheels menu (first nine presets).
- **Export/import** as pretty-printed JSON (`.gtawheel.json`); import also
  accepts a raw `stations.json`, normalizes to 26 slots, dedupes names.
- Resume positions survive save/load round-trips (uids preserved).

## Settings (⌘,)

- Hotkey: modifier toggles + A–Z/0–9 key picker, re-registered live.
- Overlay background opacity (0.15–0.95), HUD controls opacity (0.2–1.0).
- Audio-only mode toggle (also in the top bar).

## Seeded first-run content

Five demo stations (Lofi Girl, Chillhop, Blender, Nature, Developers FM) so
the wheel is never empty on first launch.
