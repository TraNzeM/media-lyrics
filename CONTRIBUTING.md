# Media Lyrics

> **Media Lyrics** — karaoke-style synced lyrics panel for the Noctalia desktop shell.
> Pure Luau, zero external dependencies, any MPRIS player.

## Getting started

1. **Fork** the repository and clone your fork.
2. Create a feature branch: `git checkout -b feat/my-feature`.
3. Make your changes (see [plugin docs](media-lyrics/README.md) for architecture
   and IPC details).
4. Run the syntax check on every `.luau` file you touched:

   ```sh
   luac -p media-lyrics/panel.luau && luac -p media-lyrics/service.luau
   ```

   If `luac` is not installed, install `luau` from your distribution's
   package manager (Arch: `sudo pacman -S luau`).
5. Smoke-test the plugin locally — add the parent directory as a Noctalia
   source and enable it:

   ```sh
   noctalia msg plugins source add media-lyrics-dev path /path/to/media-lyrics-parent
   noctalia msg plugins enable tranzem/media-lyrics
   noctalia msg config-reload
   ```
6. Commit with a clear message following [Conventional Commits](https://www.conventionalcommits.org/)
   (`feat:`, `fix:`, `docs:`, `refactor:`, …), push, and open a pull request.

## Development notes

- The **host never calls `update()` / `onFrameTick` on `[[panel]]`** — any
  animation must be driven from data arriving in `noctalia.state.watch(...)`.
  The service publishes a snapshot every 150 ms.
- `textAlign` is not honored for labels in stretched boxes; pin text left with
  `ui.button` + `variant="ghost"` + `contentAlign="start"` + fixed `width`.
- Button nodes are retained by key — when swapping text, use a key per
  rendered slice (`key .. "-" .. text`) to force clean recreation.
- See `docs/ROADMAP.md` → *Engineering pitfalls worth remembering* for the
  full list of host quirks.

## Release process

1. Bump `version` in `media-lyrics/plugin.toml` and add a section to
   `media-lyrics/CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com/)).
2. Commit: `chore: release vX.Y.Z` (or `feat:`/`fix:` per the main change).
3. Tag and push: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`.
4. Create the GitHub release with notes (or run the release workflow if one
   is configured).

## Code of conduct

Be respectful, assume good intent, and keep discussions focused on the code.
This project is maintained by one person in spare time — patience is
appreciated.
