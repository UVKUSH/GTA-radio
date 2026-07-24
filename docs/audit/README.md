# GTA Radio — Full App Audit (2026-07-24)

Complete review of every Swift source file (~2,850 lines across the app target
and the `GTARadioKit` package), the entitlements, persistence formats, and the
embedded YouTube player bridge.

## The app in one paragraph

A sandboxed macOS SwiftUI app that turns YouTube into a GTA-style car radio:
26 slots (any of which can be a folder holding its own 26, recursively) shown
as a filmstrip HUD over a full-bleed video, plus a global-hotkey radial dial
overlay. Playback uses the official YouTube IFrame player in a persistent
`WKWebView` — **no API key, no media extraction**. Metadata comes from public
oEmbed and playlist-page scraping. Wheels (full 26-slot layouts) can be saved,
hot-swapped with ⌘1–9, and shared as JSON files.

## Documents

| Doc | Contents |
|---|---|
| [01-architecture.md](01-architecture.md) | Module map, data flow, design patterns |
| [02-features.md](02-features.md) | Feature inventory and UX surfaces |
| [03-data-persistence.md](03-data-persistence.md) | Files, schemas, uid/resume semantics |
| [04-playback-pipeline.md](04-playback-pipeline.md) | WKWebView bridge, IFrame API, failure modes |
| [05-findings.md](05-findings.md) | **All issues, ranked by severity** |
| [06-security-privacy.md](06-security-privacy.md) | Sandbox, entitlements, injection, scraping posture |
| [07-testing.md](07-testing.md) | Test coverage and gaps |
| [08-roadmap.md](08-roadmap.md) | Recommended next work, prioritized |

## Executive summary

**Overall: healthy codebase, small and coherent.** Value-type station tree,
uid-keyed resume, and a strictly one-way UI→store mutation flow make the core
solid. The no-API-key strategy is consistently applied and well documented in
comments.

**Top items to fix** (details in [05-findings.md](05-findings.md)):

1. **HIGH — Playlist-ID JS injection**: `RadioStore.classify` accepts any
   non-empty `list=` value, which is later interpolated into JavaScript for the
   player webview. A hand-crafted "playlist" URL can execute arbitrary JS in
   the player page. One-line fix (validate the ID charset).
2. **HIGH — Non-atomic JSON writes**: `stations.json` / `resumes.json` /
   `presets.json` are written without `.atomic`; a crash mid-write can destroy
   the whole wheel. One-line fix.
3. **MEDIUM — Volume resets to 100% on every tune**: the player shell's
   `ensurePlay()` forces `setVolume(100)`, overriding the HUD volume slider on
   each station change.
4. **MEDIUM — `GTARadioKit` is dead weight**: the tested URL parser package is
   not used by the app; the app ships a weaker duplicate (`RadioStore.classify`)
   — which is exactly where finding #1 lives.

**Counts**: 2 high, 5 medium, 8 low findings. No crash-level defects found.
