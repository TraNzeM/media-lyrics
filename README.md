<p align="center">
  <img src="media-lyrics/thumbnail.webp" width="480" alt="Media Lyrics thumbnail">
</p>

<h1 align="center">Media Lyrics</h1>

<p align="center">
  <b>Karaoke-style synced lyrics panel for the Noctalia desktop shell.</b><br>
  Pure Luau · zero external dependencies · any MPRIS player
</p>

<p align="center">
  <a href="https://github.com/TraNZeM/media-lyrics/releases"><img alt="Release" src="https://img.shields.io/github/v/release/TraNZeM/media-lyrics"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <a href="https://github.com/TraNZeM/media-lyrics/blob/main/media-lyrics/README.md"><img alt="Plugin docs" src="https://img.shields.io/badge/docs-plugin%20README-lightgrey"></a>
</p>

A full-featured media player panel with **time-synced lyrics**: karaoke-style
lyric carousel (14 visible lines), album cover, transport controls, and a
progress bar — all in one floating panel. **No playerctl, no python daemons,
no GTK overlays** — it reads MPRIS directly via Noctalia's D-Bus aggregator
and fetches lyrics from LRCLIB in pure Luau.

## Repository layout

```
media-lyrics/          the Noctalia plugin (plugin.toml, panel, service, i18n)
  ├── README.md        plugin documentation: features, advantages, To Do
  ├── plugin.toml      manifest (id tranzem/media-lyrics, v0.8.0)
  ├── panel.luau       karaoke carousel + header UI
  ├── service.luau     MPRIS polling + LRCLIB client + cache
  └── screenshots/     light & dark theme previews
docs/ROADMAP.md        knowledge base: To Do, research, architecture
```

## Highlights

- 🎤 **Karaoke carousel** — 14 visible lyric lines, active line highlighted
- 🏃 **Marquee titles** — long track/artist names scroll instead of wrapping
- 📦 **Zero dependencies** — pure Luau, works with any MPRIS player
- 💾 **Offline-friendly** — LRCLIB cache + local `.lrc` files
- 🌐 **Bilingual** — en/ru UI

## Install

```sh
noctalia msg plugins enable tranzem/media-lyrics
noctalia msg panel-toggle tranzem/media-lyrics:panel
```

## Documentation

- [Plugin README](media-lyrics/README.md) — usage, settings, IPC, features
- [Roadmap & knowledge base](docs/ROADMAP.md) — To Do and research notes
- [Changelog](media-lyrics/CHANGELOG.md)

## License

[MIT](media-lyrics/LICENSE)
