--!nonstrict
-- Desktop widget: now-playing + synced lyrics as a background layer-shell tile.
--
-- Why this exists (ROADMAP "pinned to desktop"): a persistent *panel* still goes
-- away when no panel surface is up, so "pin to the desktop" cannot be done with
-- panels. Noctalia gives plugins a real `[[desktop_widget]]` entry kind: a
-- background surface on the desktop (and on the lockscreen) that lives
-- independently of every panel. Available at plugin_api 20, i.e. below ours.
--
-- Verified live on Noctalia 5.2.0: the entry loads, gets a surface, and survives
-- with no panel open.
--
-- It is a THIN CLIENT, exactly like the panel and the bar chip: state comes from
-- noctalia.state("media") published by the service every 150 ms, and commands go
-- back over noctalia.state("panel_cmd") — the same channel the panel uses, so the
-- desktop widget drives the very same service.

local snap = nil

-- ── settings ────────────────────────────────────────────────────────────────

local function cfgBool(key, fallback)
  local ok, v = pcall(function() return noctalia.getConfig(key) end)
  if ok and type(v) == "boolean" then return v end
  return fallback
end

local function cfgInt(key, fallback, lo, hi)
  local ok, v = pcall(function() return noctalia.getConfig(key) end)
  local n = (ok and tonumber(v)) or fallback
  n = math.floor(n)
  if lo and n < lo then n = lo end
  if hi and n > hi then n = hi end
  return n
end

-- ── helpers ─────────────────────────────────────────────────────────────────

local function fmtTime(sec)
  sec = math.max(0, math.floor(tonumber(sec) or 0))
  local m = math.floor(sec / 60)
  local s = sec % 60
  return string.format("%d:%02d", m, s)
end

local function singleLine(text)
  text = tostring(text or "")
  text = text:gsub("[%r%n%t]+", " ")
  text = text:gsub("  +", " ")
  return text
end

-- Position now, interpolated from the last published sample (the service only
-- publishes every 150 ms; the desktop widget ticks on second boundaries, so a
-- naive read would step visibly).
local function interpPos(s)
  if type(s) ~= "table" then return 0 end
  local base = tonumber(s.posSec) or 0
  if not s.playing then return base end
  local at = tonumber(s.posAtMs) or 0
  if at <= 0 then return base end
  local nowMs = 0
  pcall(function() nowMs = noctalia.nowMs() end)
  if nowMs <= 0 or nowMs < at then return base end
  local pos = base + (nowMs - at) / 1000
  local len = tonumber(s.lengthSec) or 0
  if len > 0 and pos > len then pos = len end
  return pos
end

-- Which lyric line is current: the last line whose timestamp has passed.
local function activeLine(s)
  if type(s) ~= "table" or type(s.lyrics) ~= "table" then return 0 end
  local pos = interpPos(s)
  local idx = 0
  for i = 1, #s.lyrics do
    local t = tonumber(s.lyrics[i].time) or -1
    if t >= 0 and t <= pos then idx = i end
  end
  return idx
end

local function sendCmd(action)
  pcall(function() noctalia.state.set("panel_cmd", { action = action }) end)
end

-- ── render ──────────────────────────────────────────────────────────────────

local function render()
  local showArtist = cfgBool("show_artist", true)
  local showCover = cfgBool("show_cover", true)
  local wantLines = cfgInt("lines", 3, 1, 9)

  if type(snap) ~= "table" or snap.hasPlayer ~= true then
    desktopWidget.render(ui.column({ gap = 4, align = "center", padding = 12,
      fill = "surface_variant/0.85", radius = 12 }, {
      ui.glyph({ key = "idle", name = "music-off", size = 20, color = "outline" }),
      ui.label({ key = "idletx", text = noctalia.tr("panel.no-media-player"),
        fontSize = 12, color = "on_surface_variant" }),
    }))
    return
  end

  local s = snap
  local dim = s.playing and 1 or 0.65
  local artOk = type(s.artUrl) == "string" and s.artUrl ~= ""
    and noctalia.fileExists(s.artUrl)

  -- header: cover + title/artist + time
  local headKids = {}
  if showCover then
    if artOk then
      headKids[#headKids + 1] = ui.image({ key = "cover", path = s.artUrl,
        width = 56, height = 56, radius = 14, fit = "cover" })
    else
      headKids[#headKids + 1] = ui.box({ key = "coverph", width = 56, height = 56,
        radius = 14, fill = "surface_variant/0.6", border = "outline/0.5", borderWidth = 1,
        align = "center" }, {
        ui.glyph({ name = "disc", size = 30, color = "on_surface_variant" }),
      })
    end
  end

  local infoKids = {
    ui.label({ key = "title", text = singleLine(s.title), fontSize = 15,
      color = "on_surface" }),
  }
  if showArtist then
    infoKids[#infoKids + 1] = ui.label({ key = "artist",
      text = singleLine(s.artist ~= "" and s.artist or s.album), fontSize = 12,
      color = "on_surface_variant" })
  end
  infoKids[#infoKids + 1] = ui.row({ key = "time", gap = 6, align = "center" }, {
    ui.glyph({ name = s.playing and "player-pause" or "player-play", size = 11, color = "primary" }),
    ui.label({ text = fmtTime(interpPos(s)) .. " / " .. fmtTime(s.lengthSec),
      fontSize = 11, color = "on_surface_variant" }),
  })
  headKids[#headKids + 1] = ui.column({ key = "info", gap = 2, align = "start", flexGrow = 1 }, infoKids)

  local header = ui.row({ key = "header", gap = 10, align = "center" }, headKids)

  -- lyrics window: the current line centred, `wantLines` lines total
  local lyricNodes = {}
  local hasLyrics = type(s.lyrics) == "table" and #s.lyrics > 0
  if hasLyrics then
    local active = activeLine(s)
    local n = #s.lyrics
    local half = math.floor((wantLines - 1) / 2)
    local from = math.max(1, active - half)
    local to = math.min(n, from + wantLines - 1)
    if to - from + 1 < wantLines then from = math.max(1, to - wantLines + 1) end
    for i = from, to do
      local line = s.lyrics[i]
      local isActive = (i == active)
      local dist = math.abs(i - active)
      local color = isActive and "primary" or (dist <= 1 and "on_surface" or "on_surface_variant")
      lyricNodes[#lyricNodes + 1] = ui.label({ key = "lyr" .. i,
        text = singleLine(line.text), fontSize = isActive and 14 or 12,
        color = color })
    end
  elseif s.lyricsStatus == "loading" then
    lyricNodes[#lyricNodes + 1] = ui.label({ key = "l1", text = noctalia.tr("panel.loading-lyrics"),
      fontSize = 11, color = "on_surface_variant" })
  else
    lyricNodes[#lyricNodes + 1] = ui.label({ key = "l1", text = noctalia.tr("panel.no-lyrics"),
      fontSize = 11, color = "on_surface_variant" })
  end

  -- transport (desktop widgets take no keyboard focus, so buttons are the only
  -- way to drive playback from here; they reuse the panel's command channel)
  local transport = ui.row({ key = "transport", gap = 4, align = "center", justify = "start" }, {
    ui.button({ glyph = "player-skip-back", glyphSize = 14, variant = "ghost", controlSize = "sm",
      enabled = s.canGoPrev ~= false, onClick = function() sendCmd("prev") end,
      tooltip = "Previous track" }),
    ui.button({ glyph = s.playing and "player-pause" or "player-play", glyphSize = 16,
      variant = "primary", controlSize = "sm",
      enabled = s.hasPlayer == true, onClick = function() sendCmd("toggle") end,
      tooltip = s.playing and "Pause" or "Play" }),
    ui.button({ glyph = "player-skip-forward", glyphSize = 14, variant = "ghost", controlSize = "sm",
      enabled = s.canGoNext ~= false, onClick = function() sendCmd("next") end,
      tooltip = "Next track" }),
  })

  desktopWidget.render(ui.column({
    key = "root", gap = 10, padding = 14, align = "start",
    fill = "surface_variant/0.85", radius = 14, border = "primary/0.35", borderWidth = 1,
  }, {
    header,
    ui.separator({ key = "sep", thickness = 1, color = "outline/0.35" }),
    ui.column({ key = "lyrics", gap = 3, align = "start", minWidth = 260 }, lyricNodes),
    transport,
  }))
end

-- ── lifecycle ───────────────────────────────────────────────────────────────

local okState, initial = pcall(function() return noctalia.state.get("media") end)
if okState and type(initial) == "table" then snap = initial end

pcall(function()
  noctalia.state.watch("media", function(value)
    if type(value) == "table" then
      snap = value
      render()
    end
  end)
end)

function update()
  -- second ticks keep the clock/progress moving while a track plays
  pcall(function() desktopWidget.setWantsSecondTicks(true) end)
  render()
end

function onOpen() -- not a panel, but harmless if the host ever calls it
  render()
end

render()
