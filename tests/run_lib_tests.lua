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

-- offset shift: the documented contract is "positive shows lines EARLIER", so
-- a positive user offset must move every timestamp DOWN (lines fire sooner).
-- (The old assertion encoded the opposite - it expected +1s with offset=+1000.)
-- Look the line up by text: parseLrc SORTS by time, so an index is not stable
-- once a shifted timestamp changes order.
local function timeOf(list, text)
  for _, l in ipairs(list) do if l.text == text then return l.time end end
  return nil
end
local off = lib.parseLrc(lrc, 1000)   -- +1s setting -> lines 1s earlier
ok(math.abs(timeOf(off, "First verse") - 2.20) < 1e-6,
   "parseLrc: positive offset shows lines earlier (3.20 -> 2.20)")
local offNeg = lib.parseLrc(lrc, -1000)  -- negative -> lines later
ok(math.abs(timeOf(offNeg, "First verse") - 4.20) < 1e-6,
   "parseLrc: negative offset shows lines later (3.20 -> 4.20)")
local offZero = lib.parseLrc(lrc, 0)
ok(math.abs(timeOf(offZero, "First verse") - 3.20) < 1e-6,
   "parseLrc: zero offset is a no-op")
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


-- ── source guard: no percent-r / percent-n / percent-t inside a char class ──
-- In this runtime those are NOT character classes: they degrade to the literal
-- letters r, n and t. A pattern meant to strip newlines therefore strips every
-- r/n/t out of the text instead ("The Chemical Brothers" -> "The Chemical B o
-- he s"), which only shows up on Latin lyrics and hides on Cyrillic. Use real
-- escapes ([%c] or [\r\n\t]) instead.
do
  local offenders = {}
  local pipe = io.popen("grep -rnE '\\[[^]]*%[rnt][^]]*\\]' media-lyrics/*.luau 2>/dev/null")
  if pipe then
    for line in pipe:lines() do offenders[#offenders + 1] = line end
    pipe:close()
  end
  ok(#offenders == 0,
    "no %r/%n/%t inside a character class (use [%c] or real escapes)"
    .. (#offenders > 0 and ("\n      " .. table.concat(offenders, "\n      ")) or ""))
end

-- ── source guard: the active lyric index is clamped before it is used ──
-- activeLine() returns 0 until the playhead passes the first timestamp, so feeding it
-- straight into a window (lines[active]) indexes nil. That is what took the desktop
-- widget down with "attempt to index nil with 'text'".
do
  local src = io.open("media-lyrics/desktop.luau")
  local body = src and src:read("a") or ""
  if src then src:close() end
  local clamped = body:find("math.min(math.max(activeLine(s), 1), n)", 1, true) ~= nil
  local raw = body:find("local active = activeLine(s)", 1, true) ~= nil
  ok(clamped and not raw,
    "desktop.luau clamps activeLine(s) into 1..n before indexing lyrics"
    .. (not clamped and "\n      the clamp is missing" or "")
    .. (raw and "\n      a raw `local active = activeLine(s)` is back" or ""))
end

-- ── source guard: the middle band has a fixed number of slots ──
-- The band's height has to be identical in every state, because the host centres the
-- content in the widget's box: if the band grows or shrinks, the whole widget slides as
-- the lyrics arrive. A label's real height cannot be measured from Lua, so the band must
-- not depend on how many lines there are, on wrapping, or on a guessed row height.
do
  local f = io.open("media-lyrics/desktop.luau")
  local body = f and f:read("a") or ""
  if f then f:close() end
  local slots = body:find("math.max(1, math.floor((midH + 3) / (ROW_H + 3)))", 1, true) ~= nil
    and body:find("for k = 1, maxSlots do", 1, true) ~= nil
  local slack = body:find("midSlack", 1, true) ~= nil
  local perRowFont = body:find("fontSize = ROW_H_ACTIVE_FS", 1, true) ~= nil
  ok(slots and not slack and not perRowFont,
    "the lyric band is a fixed number of equal slots"
    .. (not slots and "\n      the fixed slot count is gone" or "")
    .. (slack and "\n      a content-sized slack box is back: the height would drift" or "")
    .. (perRowFont and "\n      a bigger font on the current line makes its slot taller" or ""))
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
