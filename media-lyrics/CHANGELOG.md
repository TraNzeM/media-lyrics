# Changelog

All notable changes to **Media Lyrics** are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0] — 2026-09-01

### Added

- Marquee (scrolling) titles for long track/artist names: 2 s static hold,
  then slow scroll; per-slice button keys prevent glyph overlap.
- Per-font-size marquee capacity and speed (`vwUnits(fs)`, `MARQUEE_SPEED/fs`).
- `singleLine` sanitizer for MPRIS metadata containing embedded newlines.
- Progress bar between header and lyrics (replaces the old separator).
- Localization: English + Russian UI strings.
- Screenshots, thumbnail, docs (`ROADMAP.md`), MIT license — publication-ready.

### Changed

- Visible lyric lines: 11 → 14 (carousel window).
- Lyric timing: marquee clock driven by `watch("media")` publishes
  (the host never calls panel `update()`); service publish cadence 500 → 150 ms
  for smooth animation.
- Title/artist pinned flush-left via ghost buttons with `contentAlign="start"`
  (host ignores `textAlign` on labels).
- Lyric source fallback: LRCLIB `/api/get` → `/api/search` → local `.lrc` → cache.

### Fixed

- Lyric lines wrapping and letter overlap (newline sanitizer, integer
  button heights, per-slice keys).
- Marquee not starting (host tick probe: `update()` never called on panels).
- Titles/artists drifting to center or clipping on long names.
- Progress ring under the cover removed; progress bar layout stable.

### Removed

- Shuffle/repeat randomness, progress seek buckets, cover progress ring
  (replaced by the header progress bar).
