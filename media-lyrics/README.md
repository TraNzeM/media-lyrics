# Media Lyrics (tranzem/media-lyrics)

Медиапанель для Noctalia v5 с **синхронизированным текстом песни** — адаптация
текстового слоя медиаплеера Clavis Shell под Noctalia.

## Что внутри

| Слой Clavis | Здесь |
|---|---|
| `Services/MediaManager.qml` (MPRIS active player) | Сервис опрашивает D-Bus-агрегатор Noctalia `dev.noctalia.Mpris` (`GetActivePlayer`) через `busctl` каждые 500 мс |
| `Services/LyricsTrackService.qml` (трек → Lyrics) | Сервис следит за сменой `title/artist/length` и запускает загрузку текста |
| `core/plugin/lyrics` (C++: LRCLIB providers, cache, LRC parse) | Чистый Luau: LRCLIB `/api/get` → `/api/search` → кэш `pluginDataDir()/lyrics` → локальный каталог `.lrc` |
| `Modules/Keystone/Media/Media.qml` + `LyricsContent.qml` (караоке) | Панель: карусель строк текста вокруг активной (Clavis-стиль: активная ярко, соседние тускнеют по дистанции) |

## Возможности

- Обложка, титул/артист/альбом, прогресс с интерполяцией позиции между опросами
- Transport: play/pause, prev/next, shuffle, loop, клик по битам прогресса = seek
- Синхронизированный караоке-текст (LRCLIB) + обычный текст (plain) + локальные `.lrc`
- Ручной сдвиг тайминга (ms), кэш, локальная папка текстов — в настройках плагина
- Tile в control-center для открытия панели

## Открытие панели

```
noctalia msg panel-toggle tranzem/media-lyrics:panel
```

Совет: повесьте на хоткей в `~/.config/umbriel/config.toml`:

```toml
"Ctrl+Alt+M" = "spawn:noctalia msg panel-toggle tranzem/media-lyrics:panel"
```

## Установка (path source)

```bash
noctalia msg plugins source add media-lyrics-dev path ~/dev/noctalia-plugins/media-lyrics
noctalia msg plugins enable tranzem/media-lyrics
```

## Локальные тексты

Положите `.lrc` в `~/.local/share/media-lyrics/` с именем
`Исполнитель - Название.lrc` (или просто `Название.lrc`) — они имеют приоритет
над сетью. Кэш LRCLIB автоматически пишется в данные плагина.

## Зависимости

- Noctalia v5 (plugin_api 24)
- `busctl` (systemd, есть на любом Arch)
- Доступ к `https://lrclib.net` (без прокси)