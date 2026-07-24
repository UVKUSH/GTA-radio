# Roadmap (recommended order)

## Now — correctness sprint (small, high value)

1. **Atomic writes** (`.atomic` on all three JSON writes) — H-2, one line ×3.
2. **Validate playlist IDs** (or do #3 immediately) — H-1.
3. **Adopt `GTARadioKit` in the app**; delete the `classify` duplicate — M-2.
   Closes H-1 properly and brings the parser under existing tests.
4. **Volume persistence across tunes** — M-1 (pass volume into the JS loaders
   or re-apply after load).
5. **Make "Fill 26 slots" non-destructive** (empty slots only, like the
   picker) or confirm-first — M-3.

## Next — resilience

6. Player-offline handling: ready-timeout state in the HUD + shell reload on
   app activation — M-4.
7. Resume pruning sweep — M-5.
8. Tiny oEmbed title cache (dictionary, session-lifetime) — L-2.
9. Unit tests 1–3 from 07-testing.md (classify/scraper/preset round-trip).

## Later — features that fit the product

- **Pinned ⌘-slots for wheels** (assign a wheel to a number explicitly) — L-1.
- **"Already on the wheel" hint** when adding a duplicate video — L-7.
- **Recursive shuffle** (or rename the button) — L-4.
- **Dial-side wheel switching**: hold a modifier while the dial is open to
  show the 9 wheels as an inner ring (keeps hands on the wheel, literally).
- **Now-playing ticker**: marquee the track title in the dial center; it's
  already bridged (`nowPlayingTitle`), just unused there.
- **Media-key / Now Playing integration** (`MPNowPlayingInfoCenter` +
  `MPRemoteCommandCenter`): play/pause from AirPods and the Touch Bar; shows
  artwork in Control Center. Biggest "feels like a real app" win available.
- **Per-wheel accent color** so the HUD subtly re-themes per wheel.
- **Import drag-and-drop**: drop a `.gtawheel.json` onto the window.

## Explicitly not recommended

- Any use of the YouTube Data API (breaks the no-key identity, adds quota
  and secret management for marginal gain over oEmbed+scrape).
- Audio extraction / background-only playback hacks (ToS risk; the visible
  official player is the app's legitimacy).
- Deeper scrape reliance (continuation tokens, innertube): the current
  first-100 limit is an honest ceiling; going deeper couples the app to
  private endpoints that churn.

## Codebase conventions to keep honoring (from the audit)

- Teal = on-air, magenta = hover/add; motion distinguishes states, not new
  colors.
- One-way mutation through `RadioStore.update(at:)`; `id == index` invariant;
  uid is the only identity.
- The player webview is sacred: never unmount it, never gate audio on UI.
- Dial hover stays sector-based (see memory: `dial-hover-sector-based`).
- Every network fetch is best-effort with a graceful local fallback.
