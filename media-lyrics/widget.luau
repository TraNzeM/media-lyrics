--!nonstrict
-- Bar widget: compact now-playing indicator; click opens the lyrics panel.
--
-- Reads the snapshot published by the service (noctalia.state "media") and
-- renders glyph + truncated title. Left click toggles the panel, middle click
-- toggles play/pause, scroll switches tracks.

local glyphPlay = "player-play"
local glyphPause = "player-pause"

-- Widget presentation settings (plugin.toml [[setting]]): size knobs for
-- the compact now-playing indicator. getConfig returns nil for undeclared
-- keys, so fall back to the manifest defaults.
local function settingInt(key, fallback)
  local v = noctalia.getConfig(key)
  if type(v) == "number" then return math.floor(v) end
  return fallback
end

local function widgetMaxChars() return settingInt("widget_max_chars", 26) end
local function widgetGlyphSize() return settingInt("widget_glyph_size", 14) end
local function widgetFontSize() return settingInt("widget_font_size", 12) end

local function truncate(s, maxChars)
  s = tostring(s or "")
  if #s <= maxChars then return s end
  return s:sub(1, maxChars - 1) .. "…"
end

local function media()
  local ok, v = pcall(function() return noctalia.state.get("media") end)
  if ok and type(v) == "table" then return v end
  return nil
end

local function renderFrom(m)
  local glyphSize = widgetGlyphSize()
  if not m or not m.hasPlayer then
    -- Empty state is ALSO a render() tree: the host warns that
    -- setGlyph/setText have no visible effect once a render() tree is
    -- active (verified live), so a plain disc glyph is rendered instead.
    -- No explicit color roles — the widget instance's Color/Icon Color
    -- settings apply.
    barWidget.render(ui.row({ gap = 6, align = "center" }, {
      ui.glyph({ name = "disc", size = glyphSize }),
    }))
    return
  end
  local g = m.playing and glyphPause or glyphPlay
  local title = truncate(m.title ~= "" and m.title or "No title", widgetMaxChars())
  -- No explicit color roles: the host applies the widget instance's Color /
  -- Icon Color settings (Default = theme role). Explicit roles here would
  -- silently ignore the user's per-widget color configuration.
  barWidget.render(ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = g, size = glyphSize }),
    ui.label({ text = title, fontSize = widgetFontSize() }),
  }))
end

function update()
  renderFrom(media())
end

noctalia.state.watch("media", function(value)
  renderFrom(value)
end)

noctalia.setUpdateInterval(2000)

function onClick()
  noctalia.togglePanel("tranzem/media-lyrics:panel")
end

function onMiddleClick()
  noctalia.state.set("panel_cmd", { action = "toggle" })
end

-- scroll up = next, down = previous (mirrors the built-in media widget)
function onScroll(axis, steps, startsGesture)
  if axis ~= "vertical" or startsGesture then return end
  local dir = (steps or 0) > 0 and "next" or "prev"
  noctalia.state.set("panel_cmd", { action = dir })
end
