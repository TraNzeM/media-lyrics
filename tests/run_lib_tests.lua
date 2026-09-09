-- media-lyrics tests: unit tests for the pure, host-independent logic in
-- lyrics_lib.luau. Run with:  lua5.4 tests/run_lib_tests.lua
-- Exit code 0 = all pass. No Noctalia host, no network — purely the parsing /
-- placeholder / ranking sanitizers that feed the lyric chain.

-- Resolve lyrics_lib relative to THIS file (robust to the invoking cwd:
-- both `lua5.4 tests/run_lib_tests.lua` from the repo root and
-- `lua5.4 run_lib_tests.lua` from tests/ must work).
local script_path = debug.getinfo(1, "S").source:sub(2)
local dir = script_path:match("^(.*)[/\\][^/\\]+%.lua$") or "."
package.path = dir .. "/../media-lyrics/?.luau;" .. dir .. "/media-lyrics/?.luau;"
  .. dir .. "/../media-lyrics/?/init.lua;" .. package.path
local lib = require("lyrics_lib")

local passed, failed = 0, 0
local function ok(cond, name)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    io.stderr:write("FAIL: " .. name .. "\n")
  end
end

-- ── parseLrc: synced LRC ────────────────────────────────────────────────────
local lrc = [[[ti:Some Song]
[ar:Some Artist]
[00:00.00]Intro line
[00:03.20]First verse
[00:07.55]Second verse
[00:12.00][00:15.50]Repeated line]]
local parsed = lib.parseLrc(lrc, 0)
-- 5 entries: metadata lines dropped, repeated line emitted once per timestamp
ok(#parsed == 5, "parseLrc: 5 lyric entries (metadata dropped, repeat = 2)")
ok(math.abs(parsed[1].time - 0.0) < 1e-6, "parseLrc: first time 0")
ok(parsed[1].text == "Intro line", "parseLrc: first text")
ok(parsed[4].text == "Repeated line" and parsed[4].time == 12.0,
   "parseLrc: repeated line at 12.0")
ok(parsed[5].text == "Repeated line" and parsed[5].time == 15.5,
   "parseLrc: repeated line at 15.5")

-- offset shift
local off = lib.parseLrc(lrc, 1000)  -- +1s
ok(math.abs(off[1].time - 1.0) < 1e-6, "parseLrc: offset shifts times +1s")
-- ── parseLrc: plain text (unsynced) ─────────────────────────────────────────
local plain = "Line one\nLine two\nLine three"
local p = lib.parseLrc(plain, 0)
ok(#p == 3, "parseLrc: plain 3 lines")
ok(p[1].time < 0, "parseLrc: plain lines are unsynced (time<0)")

-- ── parseLrc: empty / whitespace ────────────────────────────────────────────
ok(#lib.parseLrc("", 0) == 0, "parseLrc: empty -> 0")
ok(#lib.parseLrc("   \n  ", 0) == 0, "parseLrc: whitespace -> 0")

-- ── isPlaceholderLyrics ─────────────────────────────────────────────────────
ok(lib.isPlaceholderLyrics("纯音乐，请欣赏") == true, "placeholder: 纯音乐请欣赏")
ok(lib.isPlaceholderLyrics("[00:00.000] 暂无歌词") == true, "placeholder: 暂无歌词")
ok(lib.isPlaceholderLyrics("Real lyric here") == false, "placeholder: real lyric false")
ok(lib.isPlaceholderLyrics("") == false, "placeholder: empty false")

-- ── stripNetEaseMeta ────────────────────────────────────────────────────────
local netease = [[作词：张三
[00:01.00]Real first lyric
[00:05.00]Real second lyric]]
local stripped = lib.stripNetEaseMeta(netease)
ok(stripped:find("作词") == nil, "stripNetEaseMeta: credit line removed")
ok(stripped:find("Real first lyric") ~= nil, "stripNetEaseMeta: lyric kept")

-- ── rankNetEaseSongs ────────────────────────────────────────────────────────
local songs = {
  { id = 1, name = "Some Song", ar = { { name = "Some Artist" } }, dt = 120000 },
  { id = 2, name = "Some Song (Remix)", ar = { { name = "Other Artist" } }, dt = 300000 },
  { id = 3, name = "completely unrelated", ar = { { name = "X" } }, dt = 1000 },
}
local ranked = lib.rankNetEaseSongs(songs, "Some Artist", "Some Song", 120)
ok(#ranked == 1, "rankNetEaseSongs: only matching candidate survives, got " .. #ranked)
if #ranked == 1 then
  ok(ranked[1].id == 1, "rankNetEaseSongs: best id is exact match (1)")
end

-- ── sanitizePart / lrcIsSynced / charCount ─────────────────────────────────
ok(lib.sanitizePart("A/B\\C") == "A_B_C", "sanitizePart: slashes -> underscores")
ok(lib.lrcIsSynced("[00:01.00]x") == true, "lrcIsSynced: true")
ok(lib.lrcIsSynced("plain text") == false, "lrcIsSynced: false")
ok(lib.charCount("héllo") == 5, "charCount: utf8 count")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
