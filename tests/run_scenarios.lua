-- run_scenarios.lua: behavioral scenarios for service.luau on the fake host
-- (tests/fake_noctalia.lua). The three #1494-class failure modes the unit
-- suite cannot reach:
--   1) a host-killed async callback must still settle "loading" with an error
--      (watchdog at the loading-set point), never hang on "Loading lyrics...";
--   2) a rapid prev/next burst with out-of-order callbacks keeps the LAST
--      track (a stale callback never glues the panel to a walked-past track);
--   3) plain (untimed) lyrics load cleanly: ready + unsynced, no crash.
-- Run: lua tests/run_scenarios.lua  (exit 0 = all pass)

local script_path = debug.getinfo(1, "S").source:sub(2)
local dir = script_path:match("^(.*)[/\\][^/\\]+%.lua$") or "."
package.path = dir .. "/../media-lyrics/?.luau;" .. dir .. "/?.lua;" .. package.path

local fake = require("fake_noctalia")

local passed, failed = 0, 0
local function ok(cond, name)
  if cond then passed = passed + 1
  else failed = failed + 1; io.stderr:write("FAIL: " .. name .. "\n") end
end

local META_TOKEN = "###metadata###"
local ACTIVE_TOKEN = "###active###"
local ACTIVE2_TOKEN = "###active2###"
local EMBED_PLAIN = "###embed-plain###"

local payloads = {
  [META_TOKEN] = { data = { { data = {
    ["xesam:asText"] = { type = "s", data = "line one\nline two" },
    ["xesam:url"] = { type = "s", data = "" },
  } } } },
}

local function fields(title, artist, lenUs)
  return { title = { type = "s", data = title }, artists = { type = "s", data = artist },
    album = { type = "s", data = "" }, art_url = { type = "s", data = "" },
    playback_status = { type = "s", data = "Playing" },
    length_us = { type = "x", data = lenUs or 190000000 }, position_us = { type = "x", data = 5000000 },
    identity = { type = "s", data = "player" }, bus_name = { type = "s", data = ":1.5" },
    can_seek = { type = "b", data = true }, can_go_next = { type = "b", data = true },
    can_go_previous = { type = "b", data = true }, shuffle = { type = "b", data = false },
    loop_status = { type = "s", data = "None" } }
end
payloads[ACTIVE_TOKEN] = { data = { true, fields("Big Dawgs", "Hanumankind") } }
payloads[ACTIVE2_TOKEN] = { data = { true, fields("Beside Me", "Andromedik") } }
local ACTIVE_DRIFT1 = "###active-drift1###"
local ACTIVE_DRIFT2 = "###active-drift2###"
-- the same track with drifting MPRIS metadata: title gains a "(feat. ...)"
-- suffix and the unknown length fills in (deepseek probe_drift case).
-- A DISTINCT track pair so scenario 3's state cannot collapse the change.
payloads[ACTIVE_DRIFT1] = { data = { true, fields("Drift Song", "Someone", 0) } }
payloads[ACTIVE_DRIFT2] = { data = { true, fields("Drift Song (feat. Y)", "Someone", 190000000) } }

local host = fake.install(payloads)
noctalia = host.noctalia

-- service.luau requires its sibling with a host-style path: preload it
package.preload["./lyrics_lib.luau"] = function()
  return dofile(dir .. "/../media-lyrics/lyrics_lib.luau")
end
dofile(dir .. "/../media-lyrics/service.luau")

local function refresh()
  host.watches["panel_req"]({ action = "refresh" })
end

-- ── 1) killed callback: the loading watchdog must settle with an error ─────
do
  host.script.active = { exitCode = 0, stdout = ACTIVE_TOKEN }
  host.script.embedded = "KILL"   -- fetchEmbeddedLyrics callback dies (25 ms budget)
  refresh()
  local m = host.media()
  ok(m ~= nil and m.lyricsStatus == "loading", "killed cb: status is loading right after the track change")
  host.fireTimers()               -- let the pump pass run (no-op: nothing due)
  host.now = host.now + 76000     -- advance the fake clock past the 75 s deadline
  host.fireTimers()               -- the 75 s watchdog deadline
  m = host.media()
  ok(m ~= nil and m.lyricsStatus == "error",
    "killed cb: watchdog settles with an error, never hangs on loading (got "
    .. tostring(m and m.lyricsStatus) .. ")")
end

-- ── 2) rapid prev/next: a stale callback never glues the walked-past track ─
do
  local held = {}
  host.script.active = { exitCode = 0, stdout = ACTIVE_TOKEN }
  host.script.embedded = function() end -- replaced below via runAsync hook
  -- intercept the embedded Metadata calls to HOLD their callbacks
  local realRun = host.noctalia.runAsync
  host.noctalia.runAsync = function(argv, cb)
    if table.concat(argv, " "):find("Metadata") then
      held[#held + 1] = cb
      return
    end
    return realRun(argv, cb)
  end
  refresh()                        -- track 1 starts, its embedded cb is held
  host.script.active = { exitCode = 0, stdout = ACTIVE2_TOKEN }
  refresh()                        -- track 2 starts before track 1's cb returns
  ok(host.media().title == "Beside Me", "burst: snapshot follows the newest track")
  -- deliver the STALE (track 1) callback late, then the fresh one
  host.noctalia.runAsync = realRun
  host.script.embedded = { exitCode = 0, stdout = META_TOKEN }
  if held[1] then held[1]({ exitCode = 0, stdout = META_TOKEN }) end
  ok(host.media().title == "Beside Me",
    "burst: stale callback cannot glue the panel to the walked-past track")
end

-- ── 3) plain (untimed) lyrics: ready + unsynced, nothing crashes ───────────
do
  host.script.active = { exitCode = 0, stdout = ACTIVE_TOKEN }
  host.script.embedded = { exitCode = 0, stdout = META_TOKEN }
  refresh()
  local m = host.media()
  ok(m ~= nil and m.lyricsStatus == "ready", "plain lyrics: loaded (got "
    .. tostring(m and m.lyricsStatus) .. ")")
  ok(m and m.synced == false, "plain lyrics: marked unsynced")
  ok(m and type(m.lyrics) == "table" and #m.lyrics == 2, "plain lyrics: both lines parsed")
end

-- ── 4) metadata drift on the SAME track: no eternal "Loading lyrics..." ────
-- The title gains a "(feat. ...)" suffix and the length fills in while the
-- embedded fetch is still in flight. sameClaim collapses the drift, and the
-- in-flight callback must still land (the claim may NOT be re-stolen from it -
-- deepseek probe_drift reproduced an eternal "loading" hang here).
do
  local held = {}
  local realRun = host.noctalia.runAsync
  host.noctalia.runAsync = function(argv, cb)
    if table.concat(argv, " "):find("Metadata") then
      held[#held + 1] = cb
      return
    end
    return realRun(argv, cb)
  end
  host.script.active = { exitCode = 0, stdout = ACTIVE_DRIFT1 }
  refresh()                          -- track starts (loading), embedded cb held
  ok(host.media().lyricsStatus == "loading", "drift: loading right after the track change")
  host.script.active = { exitCode = 0, stdout = ACTIVE_DRIFT2 }
  refresh()                          -- same track, drifted metadata (150 ms later)
  ok(host.media().lyricsStatus == "loading", "drift: still loading (no spurious reload)")
  host.noctalia.runAsync = realRun
  host.script.embedded = { exitCode = 0, stdout = META_TOKEN }
  if held[1] then held[1]({ exitCode = 0, stdout = META_TOKEN }) end
  ok(host.media().lyricsStatus == "ready",
    "drift: the in-flight callback lands after the drift (got "
    .. tostring(host.media() and host.media().lyricsStatus) .. ")")
  host.fireTimers()
  ok(host.media().lyricsStatus == "ready", "drift: the watchdog does not clobber the ready state")
end

print(string.format("\n%d passed, %d failed (scenarios)", passed, failed))
os.exit(failed == 0 and 0 or 1)
