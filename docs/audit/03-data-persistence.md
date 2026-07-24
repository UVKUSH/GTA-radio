# Data & persistence

All app data is local. Location (sandboxed container):

```
~/Library/Containers/<bundle-id>/Data/Library/Application Support/GTARadio/
├── stations.json   # the live 26-slot tree
├── resumes.json    # uid → {seconds, index}
└── presets.json    # saved wheels (incl. "Last session" auto-backup)
```

Settings live in `UserDefaults` (hotkey, opacities, audio-only).

## Schemas

### Station (recursive)

```jsonc
{
  "id": 3,                       // slot index within parent (0–25)
  "uid": "UUID",                 // stable identity — resume + now-playing key
  "sourceURL": "https://…",      // original pasted URL (nil when empty)
  "source": { "video": { "id": "jfKfPfyJRdk" } },   // or { "playlist": … }
  "name": "Lofi Girl FM",
  "customName": false,           // user-renamed → metadata never overwrites
  "thumbnailURL": "https://i.ytimg.com/vi/<id>/mqdefault.jpg",
  "isFolder": false,
  "children": null               // [Station] × 26 when a folder
}
```

Decoding is deliberately lenient (`init(from:)` defaults every missing field),
so pre-folder-era saves and hand-edited files still load. `uid` is minted on
first decode if absent, then baked in by an immediate `persist()`.

### Resume

`{ "<uid>": { "seconds": 4123.7, "index": 2 } }` — `index` is the playlist
index (−1/0 for single videos). Written at most every 5 seconds while playing
(deduped by second), plus on stop/switch/quit. Kept **out of** `@Published`
station state so frequent writes don't redraw the grid.

### WheelPreset

```jsonc
{ "id": "UUID", "name": "Night Drive", "savedAt": "…", "stations": [ 26 × Station ] }
```

- Same-name save = overwrite (upsert). New saves insert at index 0.
- `"Last session"` is a reserved name: auto-upserted from the live wheel
  before every `loadPreset`.
- Export = the same struct, pretty-printed. Import accepts a `WheelPreset`
  **or** a bare `[Station]`, then normalizes: trim/pad to exactly 26, re-index
  `id`s positionally, fresh preset `id`, name de-duped with " 2", " 3"….

## Identity semantics worth knowing

- **`uid` survives everything by design**: reorders, folder moves, preset
  save/load, export/import. That's why resume positions follow stations
  around. Consequence: the same `uid` can exist in several saved presets (and
  the live tree) simultaneously — harmless today because only the live tree is
  ever addressed, but code should never assume global uid uniqueness across
  presets.
- **`id` must equal array position.** `move(inFolder:)` and preset import
  re-stamp `id = index`; any new mutation path must preserve this invariant
  (several views compute angles/frequencies from `id`).

## Known gaps (see 05-findings.md for severity)

- Writes are `try? data.write(to:)` — **not atomic**, and failures are silent.
- `resumes.json` grows forever: entries are cleared on re-assign but not on
  `clear(at:)`, folder deletion, or preset deletion (orphaned uids accumulate).
- `presets.json` stores full trees — fine at this scale (26×n), no action needed.
