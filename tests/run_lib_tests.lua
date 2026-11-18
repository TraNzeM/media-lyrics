-- media-lyrics tests: unit tests for the pure, host-independent logic in
-- lyrics_lib.luau. Run with:  lua tests/run_lib_tests.lua
-- Exit code 0 = all pass. No Noctalia host, no network — purely the parsing /
-- placeholder / ranking sanitizers that feed the lyric chain.

-- Resolve lyrics_lib relative to THIS file (robust to the invoking cwd:
-- both `lua tests/run_lib_tests.lua` from the repo root and
-- `lua run_lib_tests.lua` from tests/ must work).
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

-- Module-load contract (the metrics used to live INSIDE isMetadataLine and only
-- registered as a side effect of parsing): the width API must work BEFORE any
-- parseLrc call in a fresh session.
ok(type(lib.truncEm) == "function" and type(lib.charAdv) == "function"
   and type(lib.unitEm) == "function" and type(lib.toChars) == "function",
  "module load: metrics API exists without calling isMetadataLine first")
ok(lib.truncEm("x", 0.5) == "…", "module load: truncEm callable before any parse")

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

-- ── source guard: the desktop wrap math must never read a free global ──
-- (the wave-2 engine unification silently dropped `local ADV_SPACE` and the
-- balanced 2-line wrap crashed in render(); static check because the UI layer
-- has no unit harness.)
do
  local src = io.open(dir .. "/../media-lyrics/desktop.luau")
  local body = src and src:read("a") or ""
  if src then src:close() end
  ok(body:find("local ADV_SPACE = lyrics_lib.charAdv", 1, true) ~= nil,
    "desktop.luau declares ADV_SPACE from the shared width table")
end

-- Transport caps policy: unknown = enabled (the host omits them on the sync
-- path; strict "== true" disabled next/prev everywhere - owner report)
do
  local p = lib.parseMediaPlayerResponse({ title = "T" })
  ok(p.canGoNext == true and p.canGoPrev == true and p.canSeek == true,
    "caps: unknown -> enabled (optimistic transport)")
  local q = lib.parseMediaPlayerResponse({ title = "T", canGoNext = false, canGoPrev = false })
  ok(q.canGoNext == false and q.canGoPrev == false, "caps: explicit false is respected")
end

-- ── source guard: singleLine must use REAL escapes ─────────────────────────
-- desktop.luau documents the runtime pitfall: the percent-r/n/t shorthand is
-- NOT a character class here - it silently eats the letters r/n/t out of text
-- ("The Chemical Brothers" -> "B o he s"). Guard the entries against it.
do
  for _, f in ipairs({ "desktop.luau", "panel.luau", "panel-mini.luau", "widget.luau" }) do
    local src = io.open(dir .. "/../media-lyrics/" .. f)
    local body = src and src:read("a") or ""
    if src then src:close() end
    ok(body:find("[%r", 1, true) == nil and body:find("[%n", 1, true) == nil
       and body:find("[%t", 1, true) == nil,
      f .. ": no percent-r/n/t character-class shorthand (eats letters)")
  end
end

-- Single source of truth for "lyrics are shown" + geometry consistency
-- between panel.luau and the manifest panel presets (the numbers were
-- maintained in both places and could drift silently).
do
  ok(lib.isLyricsShown("ready") and lib.isLyricsShown("choose"),
    "isLyricsShown: ready/choose show lyrics")
  ok((not lib.isLyricsShown("loading")) and (not lib.isLyricsShown("empty"))
     and (not lib.isLyricsShown("error")) and (not lib.isLyricsShown("idle")),
    "isLyricsShown: loading/empty/error/idle do not")

  local panel = io.open(dir .. "/../media-lyrics/panel.luau")
  local pbody = panel and panel:read("a") or ""
  if panel then panel:close() end
  local toml = io.open(dir .. "/../media-lyrics/plugin.toml")
  local tbody = toml and toml:read("a") or ""
  if toml then toml:close() end
  for _, w in ipairs({ 440, 520, 640 }) do
    ok(pbody:find("= " .. w, 1, true) ~= nil and tbody:find("width = " .. w, 1, true) ~= nil,
      "geometry: panel width " .. w .. " exists in BOTH panel.luau and plugin.toml")
  end
end

-- ── sanitizePart / lrcIsSynced / charCount ─────────────────────────────────
ok(lib.sanitizePart("A/B\\C") == "A_B_C", "sanitizePart: slashes -> underscores")
ok(lib.lrcIsSynced("[00:01.00]x") == true, "lrcIsSynced: true")
ok(lib.lrcIsSynced("plain text") == false, "lrcIsSynced: false")

ok(lib.unitEm("Привет") < 4.0, "unitEm: Cyrillic under 4.0em")


-- sanitizePart: bounded filename pieces (a 300-char title broke cache writes;
-- the cut must not leave a partial UTF-8 sequence)
do
  local long = string.rep("Привет мир ", 30)  -- multi-byte on purpose
  local out = lib.sanitizePart(long)
  ok(#out <= 80, "sanitizePart: capped at 80 bytes (got " .. #out .. ")")
  ok(out == "" or out:byte(#out) < 0x80, "sanitizePart: no trailing partial UTF-8")
  ok(lib.sanitizePart("A/B\\C") == "A_B_C", "sanitizePart: slashes still -> underscores")
end

-- ── cache paths ────────────────────────────────────────────────────────────
-- The cache writes into a `lyrics/` subfolder of the plugin data dir and the
-- host does not create parents on write, so the plan must expose the folder
-- for the writer to create it first.
do
  local p = lib.cachePaths("/data", "AC/DC", "Hells Bells")
  ok(p and p.dir == "/data/lyrics", "cachePaths names the folder to create")
  ok(p and p.file == "/data/lyrics/AC_DC__Hells Bells.lrc",
    "cachePaths builds the file inside that folder")
  ok(lib.cachePaths("", "a", "b") == nil, "cachePaths refuses an empty data dir")
  ok(lib.cachePaths(nil, "a", "b") == nil, "cachePaths refuses a missing data dir")
end

-- ── source order ───────────────────────────────────────────────────────────
-- The user picks which online provider is asked first (issue #1: NetEase
-- first for a Chinese library). A partial list must never lose a provider.
do
  local d = lib.sourceOrder("")
  ok(d[1] == "lrcmux" and d[2] == "lrclib" and d[3] == "netease" and #d == 3,
    "sourceOrder defaults to lrcmux, lrclib, netease")
  local n = lib.sourceOrder("netease, lrclib")
  ok(n[1] == "netease" and n[2] == "lrclib" and #n == 3,
    "sourceOrder honours the configured order")
  local junk = lib.sourceOrder("bogus,NETEASE")
  ok(junk[1] == "netease" and junk[2] == "lrcmux" and junk[3] == "lrclib",
    "sourceOrder drops unknown ids and is case-insensitive")
  local partial = lib.sourceOrder("netease")
  ok(partial[1] == "netease" and partial[2] == "lrcmux" and partial[3] == "lrclib",
    "sourceOrder appends an omitted provider instead of losing it")
  local dup = lib.sourceOrder("netease, netease, lrclib")
  ok(#dup == 3 and dup[1] == "netease", "sourceOrder ignores repeats")
end

-- ── word timing (enhanced LRC) ──────────────────────────────────────────────
-- Word-by-word karaoke (issue territory of the official lyrics plugin): the
-- markers are stripped from the text and their times drive the highlight.
do
  local clean, times = lib.stripWordTimes("<00:12.00>hello <00:12.45>world")
  ok(clean == "hello world", "stripWordTimes removes the <mm:ss.xx> markers")
  ok(#times == 2 and times[1] == 12.0 and math.abs(times[2] - 12.45) < 0.001,
    "stripWordTimes keeps the word start times")
  local c2, t2 = lib.stripWordTimes("plain line")
  ok(c2 == "plain line" and #t2 == 0, "stripWordTimes leaves plain text alone")
  local parsed = lib.parseLrc("[00:05.00] <00:05.00>hi <00:05.40>there", 0)
  ok(#parsed == 1 and parsed[1].text == "hi there",
    "parseLrc strips word markers out of the rendered text")
  ok(parsed[1].words and #parsed[1].words == 2 and math.abs(parsed[1].words[2] - 5.40) < 0.001,
    "parseLrc attaches the word times to the line")

  ok(lib.fillProgress({ 1.0, 1.5, 2.0 }, 0.5, 1.0, 3.0, 3) == 0,
    "fillProgress is 0 before the first word")
  local p = lib.fillProgress({ 1.0, 1.5, 2.0 }, 1.25, 1.0, 3.0, 3)
  ok(math.abs(p - 0.5) < 0.001, "fillProgress interpolates inside a word")
  ok(lib.fillProgress({ 1.0, 1.5, 2.0 }, 9.0, 1.0, 3.0, 3) == 3,
    "fillProgress saturates at the word count")
  -- The last word keeps its own slot (the average between markers): it must NOT
  -- crawl to the next line's timestamp — that tail read as "the animation is
  -- slower than the words".
  ok(lib.fillProgress({ 1.0, 1.5, 2.0 }, 2.6, 1.0, 10.0, 3) == 3,
    "the last word is done after its own slot, not at the next line")
  -- The even sweep (plain LRC) finishes a little early like the official
  -- widget: sweepSpan = span - min(span * 0.3, 0.6) = 1.4 for [1, 3].
  local q = lib.fillProgress(nil, 1.7, 1.0, 3.0, 4)
  ok(math.abs(q - 2.0) < 0.001, "fillProgress sweeps evenly without word times")
  ok(lib.fillProgress(nil, 2.4, 1.0, 3.0, 4) == 4,
    "the even sweep completes before the next line arrives")
  -- Sparser markers than visible words still sweep the whole line.
  ok(math.abs(lib.fillProgress({ 1.0, 2.0 }, 1.5, 1.0, 3.0, 4) - 1.0) < 0.001,
    "marker gaps map evenly onto the visible words")
  local r = lib.fillProgress(nil, 9.0, 1.0, 3.0, 4)
  ok(r == 4, "fillProgress caps at the word count")
end

-- ── word-timed sources ──────────────────────────────────────────────────────
do
  local lrc = lib.wordRowsToLrc({
    { start = 30780, words = {
      { start = 30780, text = "I " }, { start = 30941, text = "wanna " },
      { start = 31124, text = "feel" } } },
  })
  ok(lrc == "[0:30.78]<0:30.78>I <0:30.94>wanna <0:31.12>feel",
    "wordRowsToLrc writes one enhanced-LRC marker per word")

  local y = lib.yrcToLrc('[26630,5490](26630,300,0)Like (26930,240,0)when\n{"t":0,"c":[{"tx":"credit"}]}')
  ok(y == "[0:26.63]<0:26.63>Like <0:26.93>when",
    "yrcToLrc converts words and skips credit rows")

  -- разные версии одного трека путать нельзя: тайминги ремикса собьют всю строку
  local want = { title = "Somebody That I Used To Know", artist = "Gotye", durationSec = 244 }
  ok(lib.trackMatches(want,
      { title = "Somebody That I Used to Know", artist = "Gotye", duration = 243 }),
    "trackMatches accepts the same recording")
  ok(not lib.trackMatches(want,
      { title = "Somebody That I Used to Know (Faux Pas Remix)", artist = "Gotye", duration = 239 }),
    "trackMatches refuses a different remix")

  ok(lib.SOURCE_ORDER_DEFAULT[1] == "lrcmux",
    "the word-timed source is asked first")

  -- пословные тайминги можно подмешать только к тому же тексту
  ok(lib.textLooksSame("[00:01.00] Quarantine, fuck this disease\n[00:05.00] Nah, not for me",
      "[00:01.00] <00:01.00>Quarantine <00:01.50>fuck <00:01.80>this <00:02.00>disease\n[00:05.00] <00:05.00>Nah <00:05.40>not <00:05.60>for <00:05.80>me"),
    "textLooksSame ignores markers and punctuation")
  ok(not lib.textLooksSame("[00:01.00] Quarantine, fuck this disease",
      "[00:01.00] Somebody that I used to know"),
    "textLooksSame refuses another song")
  ok(lib.textLooksSame("[00:01.00] hello world",
      "[00:01.00] <00:01.00>hello\n[00:01.50] <00:01.50>world"),
    "textLooksSame ignores line breaks and stamps")
end

-- \u2500\u2500 parseLrc: quadratic-sort regression (community-plugins issue #1494) \u2500\u2500\u2500\u2500
-- Hundreds of lines sharing ONE timestamp used to re-scan the whole list on
-- every tie-break comparison (O(n^2)): 200 lines already took 43 ms and the
-- host kills an async callback at 25 ms of CPU, so the service died mid-parse
-- and the panel stuck on "Loading lyrics...". The order map keeps it O(n log n).
do
  local n = 2000
  local buf = {}
  for i = 1, n do buf[i] = string.format("[00:00.00]line %04d", i) end
  local t0 = os.clock()
  local parsed = lib.parseLrc(table.concat(buf, "\n"), 0)
  local elapsed = os.clock() - t0
  ok(#parsed == n, "parseLrc: " .. n .. " identical-timestamp lines all parsed")
  ok(parsed[1].text == "line 0001" and parsed[n].text == "line 2000",
    "parseLrc: tie-break keeps the input order (stable)")
  ok(elapsed < 0.5,
    string.format("parseLrc: %d identical timestamps in %.3fs (must not be quadratic)", n, elapsed))
end

-- Plain (unsynced) lyrics all compare equal on time, so their order rests on
-- the tie-break too: table.sort is not stable and used to shuffle them.
do
  local n = 40
  local buf = {}
  for i = 1, n do buf[i] = string.format("plain line %02d", i) end
  local parsed = lib.parseLrc(table.concat(buf, "\n"), 0)
  local inOrder = #parsed == n
  for i = 1, #parsed do
    if parsed[i].text ~= buf[i] then inOrder = false end
  end
  ok(inOrder, "parseLrc: unsynced lines keep the input order")
end

-- \u2500\u2500 projectPosition / parseMediaPlayerResponse (v1.1.0 media task) \u2500\u2500
do
  ok(math.abs(lib.projectPosition(10, 1000, 2000, true) - 11.0) < 1e-6, "projectPosition advances when playing")
  ok(lib.projectPosition(10, 1000, 2000, false) == 10, "projectPosition holds when paused")
  ok(lib.projectPosition(10, 2000, 1000, true) == 10, "projectPosition clamps negative delta")
  ok(lib.projectPosition(9.5, 0, 1000, true, 10) == 10, "projectPosition caps at length")
  local p = lib.parseMediaPlayerResponse({ title = "T", artist = { "A", "B" }, playback_status = "Playing", length = 120000000, position = 5000000, bus_name = "org.mpris", identity = "zen" })
  ok(p ~= nil and p.title == "T" and p.artist == "A, B" and p.playing == true, "parseMediaPlayerResponse handles list artist + playing")
  ok(p.lengthSec == 120 and p.posSec == 5 and p.busName == "org.mpris", "parseMediaPlayerResponse converts microsecond fields")
  ok(lib.parseMediaPlayerResponse(nil) == nil, "parseMediaPlayerResponse rejects non-table")
  ok(lib.trackKey("zen", "T", "A", 120000000.4) == "zen|T|A|120000000", "trackKey rounds lengthUs to integer")
  ok(lib.trackKey("zen", "T", "A", 100) == "zen" .. "|" .. "T" .. "|" .. "A" .. "|" .. "100", "trackKey concatenates fields")
  ok(lib.sameClaim({ title = "Big Dawgs", artist = "A", durationSec = 0 }, { title = "Big Dawgs (feat. Kalmi)", artist = "A", durationSec = 190 }) == true, "sameClaim collapses prefix drift with zero duration")
  ok(lib.sameClaim({ title = "Big Dawgs", artist = "A", durationSec = 100 }, { title = "Big Dawgs (feat. Kalmi)", artist = "A", durationSec = 190 }) == false, "sameClaim does not collapse suffix with both durations known")
  ok(lib.sameClaim({ title = "Big Dawgs", artist = "A" }, { title = "Other", artist = "A" }) == false, "sameClaim rejects non-prefix title")
  ok(lib.sameClaim({ title = "T", artist = "A" }, { title = "T", artist = "B" }) == false, "sameClaim rejects artist change")
  ok(lib.sameClaim({ title = "Big Dawgs", artist = "", durationSec = 0 }, { title = "Big Dawgs (feat. Kalmi)", artist = "Kalmi", durationSec = 190 }) == true, "sameClaim allows late artist (empty one side)")
  ok(lib.sameClaim({ title = "Big Dawgs", artist = "A", durationSec = 100 }, { title = "Kalmi Song", artist = "B", durationSec = 200 }) == false, "sameClaim rejects rapid prev/next (distinct tracks)")
end

-- activeIndex tests
do
  local synced = { {time=5}, {time=10}, {time=15} }
  ok(lib.activeIndex(synced, 0) == -1, "activeIndex before first -> -1")
  ok(lib.activeIndex(synced, 4.9) == -1, "activeIndex just before first -> -1")
  ok(lib.activeIndex(synced, 5) == 1, "activeIndex at first -> 1")
  ok(lib.activeIndex(synced, 7) == 1, "activeIndex between 1/2 -> 1")
  ok(lib.activeIndex(synced, 12) == 2, "activeIndex between 2/3 -> 2")
  ok(lib.activeIndex(synced, 99) == 3, "activeIndex after last -> 3")
  local plain = { {time=-1}, {time=-1} }
  ok(lib.activeIndex(plain, 100) == -1, "activeIndex plain never active")
  ok(lib.activeIndex({}, 5) == -1, "activeIndex empty -> -1")
end

-- NetEase meta/credit filtering (raw JSON rows, credit tags)
do
  ok(lib.isNetEaseMetaLine('{"t":1000,"c":[{"tx":"x"}]}') == true, "JSON word-timing row is meta")
  ok(lib.isNetEaseMetaLine("[4F5C][66F2]: Axel Demarbaix") == true, "bracketed CJK credit tags are meta")
  ok(lib.isNetEaseMetaLine("[4F5C]: composer") == true, "single tag + colon is meta")
  ok(lib.isNetEaseMetaLine("Just be beside me") == false, "plain lyric line is not meta")
  ok(lib.isNetEaseMetaLine("[Beef] I love you") == false, "lone hex-looking bracket in lyrics survives")
  ok(lib.isPlaceholderLyrics('{"t":1000,"c":[{"tx":"x"}]}') == true, "placeholder filter covers JSON rows")
end

-- parseMediaPlayerResponse exposes artUrl (sync path renders cover from it)
do
  local p = lib.parseMediaPlayerResponse({ title = "T", artUrl = "file:///a.png", identity = "zen" })
  ok(p ~= nil and p.artUrl == "file:///a.png", "parseMediaPlayerResponse returns artUrl")
end

-- parseMediaPlayerResponse unit normalization (the "1:25 / 0:00" regression)
do
  local a = lib.parseMediaPlayerResponse({ title = "T", lengthMs = 240000, positionMs = 85000 })
  ok(a.lengthSec == 240 and a.posSec == 85, "lengthMs/positionMs -> seconds")
  local b = lib.parseMediaPlayerResponse({ title = "T", lengthUs = 240000000 })
  ok(b.lengthSec == 240, "lengthUs -> seconds")
  local c = lib.parseMediaPlayerResponse({ title = "T", length = 240 })
  ok(c.lengthSec == 240, "bare length in seconds stays seconds")
  local d = lib.parseMediaPlayerResponse({ title = "T", length = 240000 })
  ok(d.lengthSec == 240, "bare length in ms -> seconds")
end

-- interpPos clamp (the 3:18 / 3:16 class)
do
  ok(lib.interpPos(218, 0, 0, false, 196) == 196, "interpPos clamps even a stale base")
  local p = lib.projectPosition(190, 0, 10000, true, 196)
  ok(p == 196, "projectPosition clamps to lengthSec")
  ok(lib.projectPosition(5, 0, 1000, true, 0) == 6, "projectPosition without length runs free")
end

-- exact width table vs the old flat estimate (bar-widget budget)
do
  ok(lib.charAdv("m") == 0.92 and lib.charAdv("w") == 0.80, "charAdv: wide glyphs measured, not flat 0.62")
  ok(math.abs(lib.unitEm("Mm") - (lib.charAdv("M") + 0.92)) < 1e-9, "unitEm sums charAdv")
  ok(lib.truncEm("Мандала", 0.5) == "…", "truncEm: budget under one glyph shows the ellipsis marker")
  -- self-consistent expectation: walk the same width table and cut at the
  -- first glyph that would exceed the budget (never mid-glyph, ellipsis after)
  local exp, w = "", 0
  for ch in ("Mandala"):gmatch(".") do
    local a = lib.charAdv(ch)
    if w + a > 3.0 then break end
    exp = exp .. ch
    w = w + a
  end
  ok(lib.truncEm("Mandala", 3.0) == exp .. "…", "truncEm: cuts by width at a glyph boundary")
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
