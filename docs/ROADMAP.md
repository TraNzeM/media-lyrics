# Media Lyrics — Roadmap & Knowledge Base

Knowledge base for the media-lyrics plugin: the To-Do list we work from, the
research behind it (features seen in alternative lyric plugins — analyzed
without naming them), and design decisions worth remembering.

## To Do (priority order)

- [ ] **Show playback progress in the bar widget** — a thin progress bar in
      the bar chip. **DROPPED (status: probably won't implement)** — the bar
      capsule is one control tall, so a bar under the text is clipped, and
      `ui.progress` is a leaf node (no children / no z-order), so it cannot
      sit behind the text; the only working placement is beside the text,
      which adds visual noise. Revisit only if the host adds a background
      progress layer or a taller capsule.
- [ ] **Album cover in a capsule shape** — render the cover inside a capsule
      (rounded-rect) instead of a plain square; animated ring progress around
      it is a stretch goal. **DROPPED (status: probably won't implement)** —
      the cover is square (width = height), so a capsule (pill) needs a
      rectangular shape; `radius = COVER/2` on a square just makes a circle,
      not a capsule. Revisit only if the cover becomes rectangular.
- [ ] **Musixmatch / Spotify lyric sources** — the remaining network sources;
      both need API keys or OAuth tokens, so they can only ship as an opt-in
      "bring your own key" setting. (Every no-auth source we know of is done —
      see the checked entries below.)
- [x] **Seek on progress-bar click** — the bar is now a `ui.slider`, the same
      control the shell's media tab uses: click to jump, drag to scrub. The
      "blocked" note was right about the mechanism (click handlers report no
      coordinates) but wrong about the conclusion — a slider does not need
      them, it owns its own pointer handling. Supersedes the third-party
      seek-bar contributions (#848).
- [x] **Persistent mini panel** — shipped: `panel-mini` declares
      `persistent = true`, so the pinned chip survives other panels opening
      (covers #747 without a fifth 640×640 preset).
- [x] **Karaoke centering + countdown** — the active line always sits on the
      vertical centre line (symmetric window around the cursor or the playing
      line): the first line starts centred on load, the anchor stays on the
      centre line through the track, and the last line returns to the centre
      at the end. The space this frees above the first line carries a 3-2-1
      countdown, shown only inside its 3-second window. DONE in 0.9.6
      (compact / medium / large; panel-mini untouched).
- [x] **Additional lyric sources** — **NetEase Cloud Music fallback DONE in
      0.9.1** (no-auth public endpoints, last in the chain); **embedded MPRIS
      `xesam:asText` DONE in 0.9.2** (zero-network, position 2: local →
      embedded → cache → LRCLIB → NetEase). LRCLIB stays the default with
      automatic fallback in the declared order.
- [x] **Clickable lyric lines** — click a line to seek the player to that
      timestamp (D-Bus `Seek` with offset = line time − current pos).
      DONE in 0.8.5 for synced lines (click + Return/Space on cursor).
- [x] **Compact mode with a pinnable surface** — a mini panel (cover + current
      line only) pinned to the desktop / bar. **DONE** — `panel-mini`
      (360×120, floating/center, `keyboard_focus=none` +
      `dismiss_on_outside_click=false` so it stays pinned): cover +
      title/artist + current lyric line. Selectable via `panel_size` = `mini`
      (widget + control-center tile open it).
- [x] **Preconfigured widget actions** — declare default gestures in
      plugin.toml (`[widget.actions]`) so the bar widget works out of the box
      without per-user gesture binding. DONE in 0.8.1, reworked in 0.9.0 to
      mirror the shell's built-in media widget (right click = play/pause,
      back/forward + wheel = prev/next, middle click = widget settings).
- [x] **Widget size setting** — panel size presets instead of a fixed panel:
      DONE in 0.8.7 — `panel_size` select (compact 440×440, medium
      520×520, large 640×640), four `[[panel]]` entries share one
      panel.luau; widget + control-center tile open the selected preset.
      (Host has no dynamic panel resize API — presets are the supported way.)
      Visible lines are derived per preset from the measured area (0.9.7:
      9 / 12 / 16).

## Research: what alternative lyric plugins do (and what to borrow)

Analysis performed 2026-09-01 against 4 published lyric/media plugins. Each
idea below is tagged with effort (S/M/L) and fit for our architecture.

### Lyric sources & parsing

| Idea | Effort | Notes |
| --- | --- | --- |
| Multiple sources (NetEase, Musixmatch, QQMusic, Kugou, Apple Music, Spotify…) with per-source selection UI | L | **PARTIAL** — NetEase (0.9.1) + embedded MPRIS (0.9.2) done; Musixmatch/Spotify still need keys. Each source is a separate HTTP client + parser; keep the normalized-line model so the panel never changes. |
| "Choose lyrics" selector panel when LRCLIB returns several candidates | M | **DONE in 0.9.4 (variants picker)** — header button always visible while a track plays; the service fetches LRCLIB search candidates on demand (`openLyricChoices`) without touching the playing lyrics; picking applies via `acceptLyrics` and the list is kept in the snapshot so variants can be switched repeatedly; a "Default" row restores the automatic chain (`chooseLyrics` index 0). |
| Embedded MPRIS lyrics (`xesam:asText`) as a zero-network source | S | **DONE in 0.9.2** — direct player-Metadata query (aggregator doesn't forward the field), chain position 2. Few players ship it today. |
| Romanization + translation layers per line | L | Only relevant for CJK/other scripts; requires source support. |

### Rendering & interaction

| Idea | Effort | Notes |
| --- | --- | --- |
| Per-character karaoke gradient (word/char progress fill) | M | We already track line progress; per-char needs char timestamps (LRC word tags) or even distribution. |
| Animated line transitions (fade, cascade, wave, typewriter, blink) | M | Our carousel is static-render; a transition timer needs the host-tick problem solved (see below). |
| Double-line mode: translation/romanization under the original | L | Source data must provide it (see sources above). |
| Bar widget showing the current line (inline, click → panel) | S | **DONE in 0.9.2** — optional `show_lyric_line` widget setting (`Title · current line` while synced lyrics are ready; falls back to artist). |
| Active line always centred (karaoke scroll) | S | **DONE in 0.9.6** — symmetric window around the anchor (cursor while scrolling, else the playing line), balanced `flexGrow` springs; first line starts centred, last returns to the centre, countdown in the freed space. |
| Player allowlist/blocklist (multiple players) | M | **DONE** — `player_allowlist`/`player_blocklist` settings; falls back to the first allowed player from `GetPlayers` when the active one is filtered. |
| Scroll gestures on the panel (volume/seek) | M | **BLOCKED by host** — `onScroll` is only a bar-widget global callback, not a panel ui-node prop; panel nodes (row/column/box) have no scroll handler. |

### Engineering pitfalls worth remembering

- **The host never calls `update()`/`onFrameTick` on `[[panel]]`** (probe
  verified: `update() calls: 1`, `onFrameTick calls: 0`). Any animation must
  be driven from data arriving in `noctalia.state.watch(...)` — the service
  publishes a snapshot every 150 ms, and the panel computes deltas from
  `noctalia.nowMs()`.
- **`textAlign` is not honored for labels** in stretched boxes; the host
  centers. Use `ui.button` + `variant="ghost"` + `contentAlign="start"` +
  fixed `width` to pin text left (community pattern).
- **`justify="center"` is ignored on a stretched `ui.column`** — centre a
  block with two balanced `flexGrow` springs instead; and `align="center"`
  only takes effect on a node with a *fixed* height, not on a `flexGrow`
  slot.
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
- **Measure text from the font file, not by pixel-probing glyphs** — the
  theme font is Noto Sans; read per-glyph advances from `NotoSans[wght].ttf`
  (fontTools). Pixel measurement at small sizes is unreliable, and a flat
  `charUnits` coefficient over-runs mixed-case text by ~30%.
- **An `int` setting without `min`/`max` gets the host's default 0..100
  slider** — the control cannot express negatives or large values, even
  though `getConfig` itself accepts them. Always declare the range.
- **Luau `return` must be the last statement in a block** — two `return`s is
  a syntax error that renders the panel blank (and `print` goes to /dev/null;
  debug via `noctalia.writeFile`).
- **Plugin settings are re-read on plugin restart, not on `config-reload`** —
  values read at parse time (e.g. the lyric timeline) only pick up a new
  offset after `plugins disable` + `enable`.

## Architecture

```
service.luau ──busctl──▶ dev.noctalia.Mpris (active player)
     │  150 ms POLL, publishes snapshot to noctalia.state["media"]
     ▼
panel.luau ──watch("media")──▶ header (cover | marquee title/artist | transport)
     │                        + progress bar + karaoke carousel
     ▼
widget.luau / shortcut.luau ──▶ panel-toggle IPC
```

- Panel presets share one `panel.luau`: `panel` (520×520, 12 lines),
  `panel-compact` (440×440, 9), `panel-large` (640×640, 16) — all floating
  and centered; `panel-mini` (360×120) is a separate pinned surface
  (`persistent = true` since 0.9.7). The row budget is derived from the
  measured lyrics area and the row pitch (29 px), not a hardcoded count —
  see `panel-rendering-pitfalls.md`.
- Service: pure Luau lyric client (LRCLIB `/api/get` → `/api/search`, NetEase
  fallback), LRC parser, local `.lrc` folder, on-disk cache, `offset_ms` timing
  shift.
- Zero external dependencies by design (no playerctl/python/GTK); runtime
  needs only `busctl` (MPRIS) and `curl` (lyric fetches).

## Release notes history

See [CHANGELOG.md](../media-lyrics/CHANGELOG.md).
