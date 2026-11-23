-- Сквозной контур: подсветка строки по наведению.
-- Загружает РЕАЛЬНЫЕ service.luau и panel.luau под заглушками, имитирует
-- шину noctalia.state с очередью доставки (как у хоста между entry).
local script_path = debug.getinfo(1, "S").source:sub(2)
local dir = script_path:match("^(.*)[/\\][^/\\]+%.lua$") or "."
package.path = dir .. "/../media-lyrics/?.luau;" .. package.path
local lib = dofile(dir .. "/../media-lyrics/lyrics_lib.luau")
package.preload["./lyrics_lib.luau"] = function() return lib end

local T0 = 1000000
local NOW = T0
local S = {
  hasPlayer = true, playing = true, posSec = 10.0, posAtMs = T0,
  lengthSec = 197, title = "T", artist = "A", album = "", artUrl = "",
  lyricsStatus = "ready", synced = true, lyricsProvider = "Cache", offsetMs = 0,
  offsetMap = {}, lyrics = {
    { time = 10.0, text = "AAA", words = {} },
    { time = 11.0, text = "BBB", words = {} },
    { time = 12.0, text = "CCC", words = {} },
  },
}
local function copy(t) local o = {} for k,v in pairs(t) do o[k]=v end return o end

local state = {}
local watchers = {}      -- key -> { cb, ... }
local queue = {}        -- отложенная доставка: { cb, value }
local sets = {}         -- журнал state.set
local renders = {}      -- деревья panel.render
local function noop() end
local function mk(kind) return function(a,b)
  local p,k = a,b
  if type(p) ~= "table" then p = {} end
  if type(k) ~= "table" then k = {} end
  return { kind = kind, props = p, children = k }
end end
ui = setmetatable({}, { __index = function(_,k) return mk(k) end })
panel = setmetatable({ render = function(t) renders[#renders+1] = t end,
  close = noop, setWantsSecondTicks = noop, setNeedsFrameTick = noop,
  openContextMenu = function() return false end }, { __index = function() return noop end })
desktopWidget = setmetatable({}, { __index = function() return noop end })

local CFG = { panel_size = "medium", offset_ms = 0,
  word_sweep = true, source_order = "", allowlist = "", blocklist = "" }
noctalia = setmetatable({
  nowMs = function() return NOW end,
  tr = function(k) return k end,
  getConfig = function(k) return CFG[k] end,
  getSetting = function() return nil end,
  getColor = function() return "#ffffff" end,
  mediaPlayer = function() return nil end,
  fileExists = function() return false end,
  expandPath = function(p) return p end,
  readFile = function() return "" end,
  writeFile = noop,
  runAsync = function() return false end,
  runStream = function() return false end,
  setUpdateInterval = noop,
  commandExists = function() return false end,
  json = { encode = function() return "{}" end, decode = function() return {} end },
  string = { trim = function(s) return (tostring(s or ""):match("^%s*(.-)%s*$")) end,
             urlEncode = function(s) return tostring(s or "") end },
  state = {
    get = function(k) return state[k] end,
    set = function(k, v)
      sets[#sets+1] = { key = k, value = v }
      state[k] = v
      -- media доставляем явно: снимок сервиса в заглушках пустой, а хосту
      -- нужно передать панели тот же ключ трека, иначе hoveredLine сбросится.
      if k ~= "media" then
        for _, cb in ipairs(watchers[k] or {}) do queue[#queue+1] = { cb, v } end
      end
    end,
    watch = function(k, cb)
      local l = watchers[k] or {}; l[#l+1] = cb; watchers[k] = l
    end,
  },
}, { __index = function() return noop end })

local function drain()
  local n = 0
  while #queue > 0 do
    local item = table.remove(queue, 1)
    item[1](item[2]); n = n + 1
    if n > 50 then error("state bus: петелька") end
  end
  return n
end
local function deliver(k, v)
  state[k] = v
  for _, cb in ipairs(watchers[k] or {}) do queue[#queue+1] = { cb, v } end
  drain()
end
local function findOnHover(node, out)
  if type(node) ~= "table" then return end
  if type(node.props) == "table" and type(node.props.onHover) == "function" then
    out[#out+1] = { key = node.props.key, fn = node.props.onHover }
  end
  for _, c in ipairs(node.children or {}) do findOnHover(c, out) end
end
local function highlightedTexts(tree)
  local t = {}
  local function walk(n)
    if type(n) ~= "table" then return end
    local p = n.props or {}
    if p.color == "primary" and type(p.text) == "string" and p.text:match("%S") then
      t[#t+1] = p.text
    end
    for _, c in ipairs(n.children or {}) do walk(c) end
  end
  walk(tree)
  return table.concat(t, ",")
end

-- 1. Сервис регистрирует watcher'ы, панель регистрирует свои.
dofile(dir .. "/../media-lyrics/service.luau")
local serviceUpdate = update
dofile(dir .. "/../media-lyrics/panel.luau")
-- 2. Начальная публикация состояния (как после старта сервиса).
deliver("media", copy(S))
assert(#renders > 0, "панель не отрисовалась по начальному состоянию")

-- 3. Имитируем наведение на строку BBB (второй ряд лирики).
local tree = renders[#renders]
local hov = {}
findOnHover(tree, hov)
local target = nil
for _, h in ipairs(hov) do if h.key == "lyr2" then target = h end end
if not target then
  -- окно могло центрировать иначе: берём любой hover-ряд, кроме активного
  for _, h in ipairs(hov) do if h.key and h.key:match("^lyr") then target = h break end end
end
assert(target, "не найден onHover у строки лирики: " .. tostring(#hov))

local rendersBefore = #renders
target.fn("true", target.key)
local rendersInside = #renders - rendersBefore
print("HOVER: синхронных перерисовок =", rendersInside, "запросов repaint =", (function()
  local n = 0
  for _, s in ipairs(sets) do if s.key == "panel_req" and type(s.value) == "table"
    and s.value.action == "repaint" then n = n + 1 end end
  return n end)())
assert(rendersInside == 0, "render() внутри onHover — хостоубийца")

local function mediaPublishes()
  local n = 0
  for _, s in ipairs(sets) do if s.key == "media" then n = n + 1 end end
  return n
end

-- 4. Контроль: БЕЗ запроса repaint штатный тик 150 мс не публикует.
local c0 = mediaPublishes()
NOW = NOW + 150
serviceUpdate()
local c1 = mediaPublishes()
print("CONTROL: публикаций media без repaint =", c1 - c0)
assert(c1 == c0, "сервис публикует без запроса — контроль сломан")

-- 5. Доставляем hover-запрос сервису и крутим его тик: должна быть публикация.
drain()
local r0 = mediaPublishes()
NOW = NOW + 150
serviceUpdate()
local r1 = mediaPublishes()
print("REPAINT: публикаций media по запросу =", r1 - r0)
assert(r1 > r0, "сервис не опубликовал media по repaint")

-- 6. Хост доставляет опубликованный снимок панели (ключ трека не меняется).
deliver("media", copy(S))
local after = #renders
print("RENDERS: до hover =", rendersBefore, "после цепочки =", after)
assert(after > rendersBefore, "подсветка не перерисована: repaint-цепочки нет")
local hl = highlightedTexts(renders[#renders])
print("HIGHLIGHTED:", hl)
assert(hl:find("BBB", 1, true), "наведённая строка BBB не подсвечена")
print("GREEN: подсветка приходит по запросу repaint, без задержки публикации")
os.exit(0)
