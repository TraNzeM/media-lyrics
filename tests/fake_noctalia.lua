-- fake_noctalia.lua: lightweight stand-in for the noctalia host used by
-- behavioral tests. Provides controllable callbacks: ordering, delay, kill.
local fake = {}

local function new()
  return { callbacks = {}, now = 0, killed = {}, callLog = {} }
end

local function schedule(host, cb, ...)
  local args = {...}
  if not cb.alive then
    host.callLog[#host.callLog+1] = { name = cb.name, status = "killed" }
    return
  end
  host.now = host.now + (cb.delay or 0)
  host.callLog[#host.callLog+1] = { name = cb.name, status = "called", delay = cb.delay or 0 }
  local ok, err = pcall(cb.fn, table.unpack(args))
  if not ok then
    host.callLog[#host.callLog+1] = { name = cb.name, status = "error", err = err }
  end
end

function fake.new() return new() end

function fake.register(host, name, fn, opts)
  opts = opts or {}
  local cb = { name = name, fn = fn, alive = opts.alive ~= false,
               delay = opts.delay or 0, order = opts.order or (#host.callbacks + 1) }
  host.callbacks[#host.callbacks+1] = cb
  return cb
end

function fake.kill(host, nameOrIndex)
  for _, cb in ipairs(host.callbacks) do
    if (type(nameOrIndex) == "number" and cb.order == nameOrIndex) or cb.name == nameOrIndex then
      cb.alive = false
      host.killed[#host.killed+1] = cb.name
    end
  end
end

function fake.runAll(host, ...)
  local args = {...}
  local sorted = {}
  for _, cb in ipairs(host.callbacks) do sorted[#sorted+1] = cb end
  table.sort(sorted, function(a,b) return a.order < b.order end)
  for _, cb in ipairs(sorted) do
    schedule(host, cb, table.unpack(args))
  end
  return host.callLog
end


-- ── full host facade ────────────────────────────────────────────────────────
-- fake.install(payloads) builds a noctalia.* stand-in service.luau can live on.
-- payloads: map of opaque stdout tokens -> decoded tables (fake json.decode).
-- HTTP/D-Bus results are scripted per call via host.script.
function fake.install(payloads)
  local host = new()
  host.payloads = payloads or {}
  host.timers = {}
  host.publishes = {}
  host.watches = {}
  host.script = { active = nil, embedded = nil }  -- {exitCode=, stdout=} or "KILL"

  local state_store = {}
  host.noctalia = {
    getConfig = function() return nil end,
    tr = function(s) return s end,
    nowMs = function() return host.now end,
    expandPath = function(p) return p end,
    pluginDataDir = function() return "/tmp/ml-scen" end,
    mkdirAll = function() end,
    writeFile = function() end,
    readFile = function() return nil end,
    fileExists = function() return false end,
    download = function() end,
    setUpdateInterval = function() end,
    string = {
      trim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end,
      urlEncode = function(s) return s end,
    },
    json = { decode = function(s) return host.payloads[s] end },
    state = {
      set = function(k, v) state_store[k] = v; host.publishes[#host.publishes+1] = { k = k, v = v } end,
      get = function(k) return state_store[k] end,
      watch = function(k, fn) host.watches[k] = fn end,
    },
    runAsync = function(argv, cb)
      local cmd = argv[1]
      if cmd == "sleep" then
        host.timers[#host.timers+1] = cb
        return
      end
      local res
      if type(argv) == "table" and table.concat(argv, " "):find("GetActivePlayer") then
        res = host.script.active
      elseif type(argv) == "table" and table.concat(argv, " "):find("Metadata") then
        res = host.script.embedded
      else
        res = { exitCode = 1, stdout = "" }
      end
      if res == "KILL" then
        host.callLog[#host.callLog+1] = { name = table.concat(argv, " "), status = "killed" }
        return -- the host killed this callback (25 ms CPU budget) - never fires
      end
      cb(res or { exitCode = 1, stdout = "" })
    end,
  }

  -- fire pending watchdog timers (the sleep-45 deadline)
  function host.fireTimers()
    local t = host.timers
    host.timers = {}
    for _, cb in ipairs(t) do cb() end
  end

  function host.media() return state_store["media"] end
  return host
end

return fake