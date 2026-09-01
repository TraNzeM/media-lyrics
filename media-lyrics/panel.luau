--!nonstrict
-- media-lyrics panel: cover art with progress line, track info + transport,
-- karaoke lyric layer. Redesign v0.2 ("quiet premium"): one hero (the cover),
-- minimal chrome, type-driven hierarchy. Layout (2 bands):
--   A. chrome header:  NOW PLAYING ......... [reload] [close]   (11px ghost)
--   B. info row:       [cover 50 + progress 2.5] [title / artist - album] | transport+time
--   hairline separator
--   C. lyrics: karaoke carousel (synced) or clipped list (plain), flexGrow
--   D. footer: provider - mode label (11px, low-contrast)
--
-- Progress: verified live on this host build —
--   * no arc primitive exists, and VERTICAL ui.progress bars do not render
--     at all, so the v0.1 8-segment perimeter ring and the per-edge bars were
--     dropped for a single native horizontal ui.progress (2.5px) under the art;
--   * ui.box cannot hold children (host drops them with warnings);
--   * labels centered by default: text with maxWidth inside a stretched
--     column loses left alignment -> infoCol hugs content, springer pushes
--     transport to the right edge.
--
-- The panel is a thin client: state comes from noctalia.state("media"),
-- commands go back over noctalia.state("panel_cmd").

-- ============================= design tokens =============================
-- One table, one place. Spacing on a 4px grid; colors are palette role tokens
-- with alpha so everything tracks the active Noctalia theme.

local T = {
  -- layout
  pad = 4,               -- root padding
  gapBand = 8,           -- between bands A/B/hairline/C
  gapInline = 12,         -- cover <-> text
  gapMicro = 6,           -- inside groups (transport step, meta stack)

  -- cover + ring
  cover = 50,             -- inner cover size (logical px)
  ring = 2.5,             -- ring thickness
  coverRadius = 10,       -- inner cover corner radius

  -- typography
  fsOverline = 11,        -- chrome header / footer
  fsTitle = 19,
  fsMeta = 13,
  fsTime = 12,
  fsActiveLyric = 17,
  fsNearLyric = 15,
  fsFarLyric = 14,

  -- colors (state colors live here too)
  colOverline = "on_surface_variant",
  colTitle = "on_surface",
  colMeta = "on_surface_variant",
  colTime = "on_surface_variant",
  ringTrack = "outline/0.5",
  ringFill = "primary",
  lyricActive = "primary",
  lyricNear = "on_surface",
  lyricFar = "on_surface_variant",
  footer = "on_surface_variant/0.7",
  hairline = "outline/0.35",
  emptyState = "on_surface_variant",
}

local snap = nil       -- latest snapshot from the service
local viewOffset = 0   -- manual lyric scroll offset from the playback line
local lastSnapMs = 0

local function nowMs()
  local ok, v = pcall(function() return noctalia.nowMs() end)
  if ok and type(v) == "number" then return v end
  return os.time() * 1000
end

local function interpPos(s)
  -- interpolate position between service polls for smooth lyrics
  if not s then return 0 end
  if not s.playing then return s.posSec or 0 end
  local elapsed = (lastSnapMs > 0) and ((nowMs() - lastSnapMs) / 1000) or 0
  local p = (s.posSec or 0) + elapsed
  if s.lengthSec and s.lengthSec > 0 and p > s.lengthSec then p = s.lengthSec end
  return p
end

local function fmtTime(sec)
  sec = tonumber(sec) or 0
  if sec < 0 then sec = 0 end
  local s = math.floor(sec)
  return math.floor(s / 60) .. ":" .. string.format("%02d", s % 60)
end

local glyphFor = {
  prev = "player-skip-back-filled",
  next = "player-skip-forward-filled",
  play = "player-play-filled",
  pause = "player-pause-filled",
}

local function sendCmd(action, extra)
  local cmd = { action = action }
  if extra then
    for k, v in pairs(extra) do cmd[k] = v end
  end
  noctalia.state.set("panel_cmd", cmd)
end

-- ============================= lyrics rendering =============================

local VISIBLE = 14          -- lyric lines visible at once (carousel window)
local ACTIVE_ROW = 4        -- 1-based slot of the active line inside the window

local function buildLyricsBody(s)
  local lines = s.lyrics or {}
  local n = #lines

  if s.lyricsStatus == "loading" then
    return { ui.label({ text = "Loading lyrics…", color = T.colMeta,
      fontSize = T.fsFarLyric, fontWeight = "medium", textAlign = "center" }) }
  end
  if s.lyricsStatus == "error" then
    return { ui.label({ text = "Lyrics error: " .. (s.lyricsError or ""),
      color = "error", fontSize = T.fsFarLyric, textAlign = "center" }) }
  end
  if s.lyricsStatus ~= "ready" or n == 0 then
    return { ui.label({ text = "No lyrics found", color = T.emptyState,
      fontSize = T.fsFarLyric, fontWeight = "medium", textAlign = "center" }) }
  end

  if not s.synced then
    -- unsynced: static list inside a clipping scroll (a bare column does not
    -- clip its children), dimmed, centered, generous line spacing
    local rows = {}
    for i, l in ipairs(lines) do
      rows[#rows + 1] = ui.label({
        key = "lyr" .. i, text = l.text, fontSize = T.fsFarLyric,
        color = T.lyricNear, opacity = 0.8, textAlign = "center",
      })
      rows[#rows + 1] = ui.spacer({ key = "lgap" .. i, height = T.gapMicro })
    end
    return { ui.scroll({ flexGrow = 1, align = "stretch" }, rows) }
  end

  -- synchronized: carousel around the playback line (karaoke fade ladder)
  local pos = interpPos(s)
  local active = -1
  for i = 1, n do
    if (s.lyrics[i].time >= 0) and (s.lyrics[i].time <= pos) then active = i end
    if (s.lyrics[i].time >= 0) and (s.lyrics[i].time > pos) then break end
  end

  local showCount = math.min(VISIBLE, n)
  local centerY = active >= 1 and ACTIVE_ROW or math.ceil(showCount / 2)
  local base = active - centerY + viewOffset
  local rows = {}
  for k = 1, showCount do
    local idx = base + k - 1
    if idx >= 1 and idx <= n then
      local isActive = (idx == active)
      local dist = math.abs(idx - active)
      local fontSize = isActive and T.fsActiveLyric
        or (dist <= 2 and T.fsNearLyric or T.fsFarLyric)
      local fontWeight = isActive and "bold"
        or (dist <= 2 and "medium" or "normal")
      local color = isActive and T.lyricActive
        or (dist <= 2 and T.lyricNear or T.lyricFar)
      local opacity = isActive and 1 or (dist <= 2 and 0.9 or (dist <= 5 and 0.55 or 0.3))
      rows[k] = ui.label({
        key = "lyr" .. idx,
        text = s.lyrics[idx].text,
        fontSize = fontSize,
        fontWeight = fontWeight,
        color = color,
        opacity = opacity,
        textAlign = "center",
      })
    else
      rows[k] = ui.spacer({ key = "gap" .. k, height = 24 })
    end
  end
  return rows
end

-- ============================= cover: art + progress =============================

-- Cover art with a thin progress line under it. VERIFIED LIVE on this host:
--   * ui.box cannot hold children (host drops them with warnings);
--   * ui.image renders at DECLARED size only when NOT wrapped in a padded
--     container (inside a padded plate column it came out oversize), so the
--     frame is the image's own border (ui.image border/borderWidth/radius);
--   * vertical ui.progress bars do not render at all -> single horizontal
--     native progress bar under the art (agreed auto-fallback).
local function buildCoverRing(s)
  local COVER = T.cover
  local BAR = T.ring
  local total = s.lengthSec or 0
  local cur = interpPos(s)
  local frac = (total > 0) and math.min(1, cur / total) or 0

  local coverInner
  if s.artUrl and s.artUrl ~= "" then
    coverInner = ui.image({
      key = "cover", path = s.artUrl, width = COVER, height = COVER,
      fit = "cover", radius = T.coverRadius,
      border = T.ringTrack, borderWidth = 1,
      onClick = function() sendCmd("toggle") end,
    })
  else
    coverInner = ui.box({ key = "coverbox", width = COVER, height = COVER,
      fill = "surface_variant/0.6", border = "outline/0.5", borderWidth = 1,
      radius = T.coverRadius }, {
        ui.glyph({ name = "disc", size = 44, color = "on_surface_variant" }),
      })
  end

  -- one native bar under the art, spanning exactly the art width
  local bar = ui.progress({ key = "pbar", progress = frac,
    fill = T.ringFill, track = T.ringTrack,
    width = COVER, height = BAR, radius = BAR / 2 })

  return
    ui.column({ key = "ringCol", gap = 0, align = "center" }, { coverInner }),
    ui.column({ key = "ringColMid", gap = 0, align = "center" }, { bar })
end

-- ============================= header (cover + info + transport) =============================

local function buildInfoRow(s)
  if not s.hasPlayer then
    return { ui.row({ key = "noplayer", height = T.cover + 2 * T.ring, align = "center" }, {
      ui.label({ text = "No media player", color = T.emptyState, fontSize = T.fsMeta }),
    }) }
  end

  local topEdge, coverMid, bottomEdge = buildCoverRing(s)

  local function ctl(glyph, action, enabled, size)
    return ui.button({
      glyph = glyph, glyphSize = size or 18, variant = "ghost",
      enabled = enabled ~= false, onClick = function() sendCmd(action) end,
    })
  end

  local mainGlyph = s.playing and glyphFor.pause or glyphFor.play
  local cur = interpPos(s)
  local total = s.lengthSec or 0

  -- right block: transport row (the hero pill sits on the cover's axis) +
  -- quiet time label underneath, right-aligned
  local transportCol = ui.column({ key = "transportCol", gap = 2, align = "center", justify = "center" }, {
    ui.row({ gap = T.gapMicro, align = "center", justify = "end" }, {
      ctl(glyphFor.prev, "prev", s.canGoPrev ~= false, 18),
      ui.button({
        glyph = mainGlyph, glyphSize = 22, variant = "primary",
        enabled = s.hasPlayer == true, onClick = function() sendCmd("toggle") end,
        controlSize = "sm",
      }),
      ctl(glyphFor.next, "next", s.canGoNext ~= false, 18),
    }),
    ui.label({ key = "time", text = fmtTime(cur) .. " / " .. fmtTime(total),
      fontSize = T.fsTime, color = T.colTime }),
  })

  -- middle block: title + artist - album (album debuts here). VERIFIED LIVE:
  -- a stretched label centers its text in Noctalia's panel host regardless of
  -- textAlign, so the column must HUG its content (no flexGrow, maxWidth caps
  -- long titles) and a springer pushes transport to the right edge.
  local artistLine = s.artist ~= "" and s.artist or "Unknown artist"
  if s.album ~= "" then artistLine = artistLine .. " - " .. s.album end
  local infoCol = ui.column({ key = "infoCol", gap = 3, align = "start" }, {
    ui.label({ key = "ttl", text = s.title ~= "" and s.title or "(no title)",
      fontSize = T.fsTitle, fontWeight = "semibold", color = T.colTitle,
      maxLines = 1, maxWidth = 280 }),
    ui.label({ key = "art", text = artistLine,
      fontSize = T.fsMeta, color = T.colMeta,
      maxLines = 2, maxWidth = 280 }),
  })

  -- single band, everything centered on the art's vertical axis
  return {
    ui.row({ key = "infoRow", align = "center", justify = "start", height = 62 }, {
      ui.column({ key = "coverWrap", gap = 1, align = "center",
        width = T.cover + 2 }, {
          topEdge, coverMid, bottomEdge,
        }),
      ui.spacer({ key = "coverGap", width = T.gapInline }),
      infoCol,
      ui.spacer({ key = "spring1", flexGrow = 1 }),
      transportCol,
    }),
  }
end

-- ============================= render =============================

local function render()
  local s = snap or {
    hasPlayer = false, title = "", artist = "", album = "", artUrl = "",
    playing = false, lengthSec = 0, posSec = 0, lyrics = {},
    lyricsStatus = "loading", lyricsProvider = "", synced = false,
  }
  local infoRow = buildInfoRow(s)

  -- footer: provider + mode in one quiet label (empty string hides itself)
  local footerTxt = ""
  if s.lyricsStatus == "ready" then
    footerTxt = (s.lyricsProvider ~= "" and s.lyricsProvider or "")
      .. (s.synced and " - synced" or " - unsynced")
  end

  panel.render(ui.column({ flexGrow = 1, padding = T.pad, gap = T.gapBand }, {
    -- A. chrome header: overline left, two ghost glyph buttons right
    ui.row({ key = "chrome", align = "center", justify = "space_between" }, {
      ui.label({ text = "NOW PLAYING", fontSize = T.fsOverline, fontWeight = "semibold",
        color = T.colOverline }),
      ui.row({ gap = T.gapMicro, align = "center" }, {
        ui.button({ glyph = "refresh", glyphSize = 14, variant = "ghost", controlSize = "sm",
          width = 22, height = 22,
          tooltip = "Reload lyrics",
          onClick = function() noctalia.state.set("panel_req", { action = "reloadLyrics" }) end }),
        ui.button({ glyph = "close", glyphSize = 14, variant = "ghost", controlSize = "sm",
          width = 22, height = 22,
          onClick = function() panel.close() end }),
      }),
    }),
    -- B. info band (cover | info | transport)
    infoRow[1],
    -- hairline (the only separator in the interface)
    ui.separator({ key = "hair", thickness = 1, color = T.hairline }),
    -- C. lyrics (flexGrow)
    ui.column({ key = "lyrics", flexGrow = 1, gap = T.gapMicro }, buildLyricsBody(s)),
    -- D. footer: provider - mode
    ui.label({ key = "footer", text = footerTxt, fontSize = T.fsOverline,
      color = T.footer, visible = footerTxt ~= "" }),
  }))
end

-- ============================= state wiring =============================

noctalia.state.watch("media", function(value)
  snap = value
  lastSnapMs = nowMs()
  render()
end)

function update()
  render()
end

function onOpen(_context)
  viewOffset = 0
  -- second ticks keep position + lyrics moving between service polls
  panel.setWantsSecondTicks(true)
  noctalia.state.set("panel_req", { action = "refresh" })
  render()
end