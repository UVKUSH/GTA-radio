# Security & privacy posture

## Sandbox / entitlements

`GTA_radio.entitlements`:

| Entitlement | Why |
|---|---|
| `com.apple.security.app-sandbox` | On. All data confined to the app container. |
| `com.apple.security.network.client` | YouTube IFrame player, oEmbed, thumbnails, playlist pages. |
| `com.apple.security.files.user-selected.read-write` | Only for the wheel export/import save/open panels (powerbox: access limited to the exact files the user picks). |

No microphone/camera/location/Accessibility. The global hotkey deliberately
uses Carbon `RegisterEventHotKey`, which needs **no** Accessibility grant and
cannot observe other keystrokes — the least-privilege choice.

## Network surface (all HTTPS, all Google-owned hosts)

1. `www.youtube.com/iframe_api` + player traffic inside the WKWebView.
2. `www.youtube.com/oembed?url=…` — public metadata, no auth.
3. `www.youtube.com/playlist?list=…` — public page HTML, sent with a browser
   UA string and a `CONSENT=YES+1` cookie (bypasses the EU consent
   interstitial to get real markup).
4. `i.ytimg.com/vi/<id>/mqdefault.jpg` — thumbnails.

No analytics, no telemetry, no third-party endpoints, no credentials of any
kind. Nothing user-identifying leaves the machine beyond ordinary YouTube
embed traffic (which carries normal web-request metadata — same as a browser).

## Input trust boundaries

| Input | Validation today | Risk |
|---|---|---|
| Pasted URLs | Host allowlist + video-ID charset; **playlist IDs unvalidated** | **H-1 JS injection** (see findings) |
| Playlist page HTML | Regex extraction only; IDs charset-constrained by the regex | Low — worst case is wrong/no stations |
| oEmbed JSON | `Codable` decode | Low |
| Imported wheel files | Lenient decode + normalization (trim/pad to 26, re-id) | Low — worst case is a junk wheel; **note:** a malicious wheel file can contain a hostile playlist ID → same H-1 path, so fixing H-1 also closes the import vector |
| JS bridge messages | Typed dictionary switch, ignores unknown | Low |

## ToS / fair-use notes (worth being honest about)

- The app embeds the **official** IFrame player, unmodified, ads and all —
  the compliant way to play YouTube without an API key.
- oEmbed is a public, documented, keyless endpoint — fine.
- Scraping `playlist?list=` HTML with a spoofed browser UA + consent cookie is
  a **gray area**: it reads only public data a browser would see, but it is
  not an official interface and may break or be rate-limited at any time.
  The code treats it as best-effort (all failures degrade gracefully), which
  is the right posture. Keep it best-effort; never make core playback depend
  on scrape success.
- The `http://localhost` baseURL trick is the same one Google ships in
  `youtube-ios-player-helper`; low concern.

## Data at rest

Everything is plaintext JSON inside the sandboxed container — appropriate, as
none of it is sensitive (public video IDs, names, timestamps). Exported wheel
files reveal station uids and save dates; no personal data.

## Recommendations (mirrors findings)

1. Fix H-1 (validate playlist IDs / adopt `YouTubeURLParser`) — closes both
   the paste vector and the wheel-import vector.
2. Fix H-2 (atomic writes) — data integrity.
3. Optionally add `com.apple.security.files.user-selected.read-only` scoping
   review at ship time: read-write is correct here since export needs write.
