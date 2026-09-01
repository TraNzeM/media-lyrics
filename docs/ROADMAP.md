# Media Lyrics — Roadmap & Knowledge Base

Knowledge base for the media-lyrics plugin: the To-Do list we work from, the
research behind it (features seen in alternative lyric plugins — analyzed
without naming them), and design decisions worth remembering.

## To Do (priority order)

- [ ] **Album cover in a capsule shape** — render the cover inside a capsule
      (rounded-rect) instead of a plain square; animated ring progress around
      it is a stretch goal.
- [ ] **Additional lyric sources** — NetEase, Musixmatch, Spotify, embedded
      MPRIS metadata (`xesam:asText`). LRCLIB stays the default
      with automatic fallback in the declared order.
- [x] **Clickable lyric lines** — click a line to seek the player to that
      timestamp (D-Bus `Seek` with offset = line time − current pos).
      DONE in 0.8.5 for synced lines (click + Return/Space on cursor).
- [ ] **Seek on progress-bar click** — clicking the progress bar seeks the
      track (service already exposes `Seek`; panel-side click handling is
      missing).
- [ ] **Compact mode with a pinnable widget** — a mini panel (cover + current
      line only) that can be pinned to the desktop / bar.
- [x] **Preconfigured widget actions** — declare default gestures in
      plugin.toml (`[widget.actions]`: `middle = "none"` frees the middle
      button for play/pause; scroll_up/scroll_down for track switching) so
      the bar widget works out of the box without per-user gesture binding.
      DONE in 0.8.1 (middle), scroll via onScroll in widget.luau.
- [ ] **Widget size setting** — expose the bar widget's size (glyph size,
      title length, scale) as plugin settings instead of hard-coded constants.

## Research: what alternative lyric plugins do (and what to borrow)

Analysis performed 2026-09-01 against 4 published lyric/media plugins. Each
idea below is tagged with effort (S/M/L) and fit for our architecture.

### Lyric sources & parsing

| Idea | Effort | Notes |
| --- | --- | --- |
| Multiple sources (NetEase, Musixmatch, QQMusic, Kugou, Apple Music, Spotify…) with per-source selection UI | L | Each source is a separate HTTP client + parser; keep the normalized-line model so the panel never changes. |
| "Choose lyrics" selector panel when LRCLIB returns several candidates | M | A panel listing candidates (title/artist/album/duration); click to apply. Reuses our panel infra. |
| Embedded MPRIS lyrics (`xesam:asText`) as a zero-network source | S | Read the metadata field first; LRCLIB only if absent. |
| Romanization + translation layers per line | L | Only relevant for CJK/other scripts; requires source support. |

### Rendering & interaction

| Idea | Effort | Notes |
| --- | --- | --- |
| Per-character karaoke gradient (word/char progress fill) | M | We already track line progress; per-char needs char timestamps (LRC word tags) or even distribution. |
| Animated line transitions (fade, cascade, wave, typewriter, blink) | M | Our carousel is static-render; a transition timer needs the host-tick problem solved (see below). |
| Double-line mode: translation/romanization under the original | L | Source data must provide it (see sources above). |
| Bar widget showing the current line (inline, click → panel) | S | We already have a bar widget (`now-playing`); add the lyric line + click-through. |
| Player allowlist/blocklist (multiple players) | M | We auto-pick the active player; allow/block is a nice filter for multi-player setups. |
| Scroll gestures on the panel (volume/seek) | M | `onScroll` wiring; service has `Seek`. |

### Engineering pitfalls worth remembering

- **The host never calls `update()`/`onFrameTick` on `[[panel]]`** (probe
  verified: `update() calls: 1`, `onFrameTick calls: 0`). Any animation must
  be driven from data arriving in `noctalia.state.watch(...)` — the service
  publishes a snapshot every 150 ms, and the panel computes deltas from
  `noctalia.nowMs()`.
- **`textAlign` is not honored for labels** in stretched boxes; the host
  centers. Use `ui.button` + `variant="ghost"` + `contentAlign="start"` +
  fixed `width` to pin text left (community pattern).
- **Button nodes are retained by key**: changing `text` on a fixed key
  re-types glyphs in place and visibly overlaps old glyphs. Key per
  rendered slice (`key .. "-" .. text`) to force clean recreation.
- **Marquee capacity must be per-font-size**: `vwUnits(fs) = (TEXT_W − 26) / fs`,
  speed `MARQUEE_SPEED / fs`. A single fs13-derived constant made fs19 slices
  1.46× too wide → mid-travel wrap.
- **MPRIS metadata can contain embedded newlines** (`title = "A\nB"`); a
  `singleLine` sanitizer is mandatory before rendering, or rows wrap and
  overlap.
- **Integer button heights** (`math.floor(fs * 1.35 + 0.5)`) prevent
  subpixel overlap between adjacent text rows.
- **CJK vs ASCII width**: uniform `charUnits` 0.72 fits this theme's font;
  CJK needs ~1.0 units/char.

## Architecture

```
service.luau ──busctl──▶ dev.noctalia.Mpris (active player)
     │  150 ms POLL, publishes snapshot to noctalia.state["media"]
     ▼
panel.luau ──watch("media")──▶ header (cover | marquee title/artist | transport)
     │                        + progress bar + 14-line karaoke carousel
     ▼
widget.luau / shortcut.luau ──▶ panel-toggle IPC
```

- Panel: `tranzem/media-lyrics:panel` (520×520, floating, centered).
- Service: pure Luau LRCLIB client (`/api/get` → `/api/search`), LRC parser,
  local `.lrc` folder, on-disk cache, `offset_ms` timing shift.
- Zero external dependencies by design (no playerctl/python/GTK).

## Release notes history

See [CHANGELOG.md](../media-lyrics/CHANGELOG.md).
