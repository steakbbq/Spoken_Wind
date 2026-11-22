-- Core.lua with a fake client (no game here). Run: python -I tools/lua.py core
-- Proves: one sound per fart, cooldown, on/off, self on/off, channel, never the
-- same sound twice in a row, prints only on /wind, no hooks / CVars / leaks,
-- every sound file on disk, toc lists every file and has no X- keys (the
-- Spoken addons scan toc keys), a new emote row works with no code change.
local pass, fail = 0, 0
local out = print
local function ok(name, cond, extra)
	if cond then pass = pass + 1
	else fail = fail + 1 out("FAIL " .. name .. (extra and (" :: " .. tostring(extra)) or "")) end
end

-- ---------------------------------------------------------------- fake client
local now, plays, prints, frames, forbidden
local willPlay = true
local ME, ME_GUID = "Tester", "Player-1-0000AAAA"

local function Mock()
	local f = { scripts = {}, events = {} }
	function f:SetScript(n, fn) self.scripts[n] = fn end
	function f:RegisterEvent(e) self.events[e] = true end
	function f:UnregisterEvent(e) self.events[e] = nil end
	return f
end

local BASE = {}
for k in pairs(_G) do BASE[k] = true end

local function Load(db)
	now, plays, prints, frames, forbidden = 1000, {}, {}, {}, {}
	SpokenWindDB = db
	SLASH_SPOKENWIND1, SLASH_SPOKENWIND2, SlashCmdList = nil, nil, {}
	CreateFrame = function(kind, name, parent, tmpl)
		if name or parent or tmpl then forbidden[#forbidden + 1] = "CreateFrame named/parented" end
		local f = Mock() frames[#frames + 1] = f return f
	end
	GetTime = function() return now end
	date = function() return "11-21 12:00:00" end
	print = function(...) prints[#prints + 1] = table.concat({ ... }, " ") end
	PlaySoundFile = function(path, ch) plays[#plays + 1] = { path = path, ch = ch } return willPlay, 77 end
	UnitGUID = function(u) return u == "player" and ME_GUID or nil end
	UnitName = function(u) return u == "player" and ME or nil end
	GetLocale = function() return "enUS" end
	issecretvalue = nil
	EMOTE41_TOKEN, EMOTE41_CMD1 = "FART", "/fart"
	for _, bad in ipairs({ "SetCVar", "hooksecurefunc", "SendChatMessage", "DoEmote", "RunMacroText",
		"CastSpellByName", "UseAction", "SetBinding" }) do
		_G[bad] = function() forbidden[#forbidden + 1] = bad end
	end
	local ns = {}
	local toc = assert(io.open(ADDON_DIR .. "/Spoken_Wind.toc", "rb")):read("*a")
	local files = {}
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line:match("%S") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
	end
	for _, file in ipairs(files) do
		assert(loadfile(ADDON_DIR .. "/" .. file))("Spoken_Wind", ns)
	end
	local ev = frames[1]
	ev.scripts.OnEvent(ev, "ADDON_LOADED", "SomethingElse")
	ev.scripts.OnEvent(ev, "ADDON_LOADED", "Spoken_Wind")
	ev.scripts.OnEvent(ev, "PLAYER_LOGIN")
	return ev, ns, files, toc
end

local ev, ns, files, toc
local function Emote(text, sender, guid)
	ev.scripts.OnEvent(ev, "CHAT_MSG_TEXT_EMOTE", text, sender, "", "", "", "", 0, 0, "", 0, 123, guid)
end
local function Slash(s) SlashCmdList.SPOKENWIND(s) end
local function LogHas(s)
	for _, l in ipairs(SpokenWindDB.log) do if l:find(s, 1, true) then return true end end
	return false
end
local function LastLog() return SpokenWindDB.log[#SpokenWindDB.log] or "" end
local OTHER_FART = "Bob brushes up against you and farts loudly."

-- ---------------------------------------------------------------- load + toc
ev, ns, files, toc = Load(nil)
ok("toc order", table.concat(files, ",") == "Emotes.lua,Match.lua,Pick.lua,Core.lua", table.concat(files, ","))
ok("toc title", toc:find("## Title: Spoken Wind\r?\n") ~= nil)
ok("toc no X- keys", not toc:find("##%s*[Xx]%-"))
local ALLOWED = { Interface = 1, Title = 1, Notes = 1, Version = 1, SavedVariables = 1 }
local keys = 0
for line in toc:gmatch("[^\r\n]+") do
	if line:match("^##") then
		keys = keys + 1
		local key = line:match("^##%s*([^:]+):")
		ok("toc key allowed: " .. tostring(key), key and ALLOWED[key], line)
	end
end
ok("toc 5 keys", keys == 5, keys)
ok("toc no deps", not toc:find("Dep") and not toc:find("Spoken_%u") and not toc:find("Spoken%u%l+Audio"))
ok("one frame", #frames == 1)
ok("chat event on", ev.events.CHAT_MSG_TEXT_EMOTE == true)
ok("addon_loaded off after load", ev.events.ADDON_LOADED == nil)
ok("defaults", SpokenWindDB.on == true and SpokenWindDB.ch == "SFX" and SpokenWindDB.self == true
	and SpokenWindDB.cd == 2)
ok("slash", SLASH_SPOKENWIND1 == "/wind" and SLASH_SPOKENWIND2 == "/spokenwind"
	and type(SlashCmdList.SPOKENWIND) == "function")
ok("boot line", LogHas("BOOT v=0.1.0 loc=enUS emotes=FART:checked:/fart slash=/wind clash=0 on=1 ch=SFX self=1 cd=2 n=14"))
ok("no prints at load", #prints == 0, prints[1])

-- every row: every sound file on disk (Media\<folder>\), a real ogg, short names
local SOUNDS = ns.EMOTES.FART.sounds
ok("only FART shipped", next(ns.EMOTES) == "FART" and next(ns.EMOTES, "FART") == nil)
ok("14 sounds", #SOUNDS == 14)
for token, row in pairs(ns.EMOTES) do
	for i, s in ipairs(row.sounds) do
		local f = io.open(ADDON_DIR .. "/Media/" .. row.folder .. "/" .. s.file .. ".ogg", "rb")
		local head = f and f:read(4)
		if f then f:close() end
		ok("file " .. token .. " " .. s.file, head == "OggS", head)
		ok("name short " .. token .. " " .. i, #s.name <= 12)
	end
end
ok("media path", ns.MEDIA == "Interface\\AddOns\\Spoken_Wind\\Media\\")
-- the synth's list (tools/synth.py) and the FART row agree, in order
local syn = assert(io.open(ROOT .. "/tools/synth.py", "rb")):read("*a")
local k = 0
for stem, name in syn:gmatch('%("(%d%d_[%w_]+)", "([^"]+)", f_') do
	k = k + 1
	ok("synth row " .. k, SOUNDS[k] and SOUNDS[k].file == stem and SOUNDS[k].name == name, stem)
end
ok("synth rows = table rows", k == #SOUNDS, k)

-- ---------------------------------------------------------------- plays
Emote(OTHER_FART, "Bob", "Player-1-0000BBBB")
ok("other fart plays", #plays == 1)
ok("path", plays[1] and plays[1].path:match("^Interface\\AddOns\\Spoken_Wind\\Media\\fart\\%d%d_[%a]+%.ogg$"),
	plays[1] and plays[1].path)
ok("channel SFX", plays[1] and plays[1].ch == "SFX")
ok("log PLAY", LogHas("PLAY emo=FART who=other snd="))
Emote("Bob waves at you.", "Bob", "Player-1-0000BBBB")
ok("wave no sound", #plays == 1)
ok("no prints on events", #prints == 0, prints[1])

-- cooldown: 20 farts in one second -> 1 sound
plays = {}
now = now + 10
for n = 1, 20 do Emote(OTHER_FART, "Bob", "G" .. n) now = now + 0.05 end
ok("spam -> one sound", #plays == 1, #plays)
ok("log SKIP cd", LogHas("SKIP cd emo=FART who=other dt="))
now = now + 2.01
Emote(OTHER_FART, "Bob", "Gx")
ok("after cd plays again", #plays == 2, #plays)

-- never the same sound twice in a row (cd 0, many farts)
Slash("cd 0")
ok("cd 0 set", SpokenWindDB.cd == 0)
plays = {}
for n = 1, 300 do now = now + 0.001 Emote(OTHER_FART, "Bob", "G" .. n) end
local rep = 0
for n = 2, #plays do if plays[n].path == plays[n - 1].path then rep = rep + 1 end end
ok("cd 0: every fart plays", #plays == 300, #plays)
ok("no same sound twice in a row", rep == 0, rep)
ok("log capped", #SpokenWindDB.log <= 60, #SpokenWindDB.log)
Slash("cd 2")

-- self
plays = {}
now = now + 10
Emote("You fart loudly. Phew...what stinks?", ME, ME_GUID)
ok("own fart plays (self on)", #plays == 1)
ok("log who=self", LogHas("PLAY emo=FART who=self"))
Slash("self off")
ok("self off", SpokenWindDB.self == false)
now = now + 10
Emote("You fart loudly. Phew...what stinks?", ME, ME_GUID)
Emote("You brush up against Bob and fart loudly.", ME .. "-Realm", nil)   -- no guid: name check
ok("own fart silent (self off)", #plays == 1, #plays)
ok("log SKIP self", LogHas("SKIP self emo=FART"))
Emote(OTHER_FART, "Bob", "Player-1-0000BBBB")
ok("others still play (self off)", #plays == 2)
Slash("self")
ok("self toggles on", SpokenWindDB.self == true)

-- off
Slash("off")
plays = {}
now = now + 10
Emote(OTHER_FART, "Bob", "Player-1-0000BBBB")
ok("off: silent", #plays == 0)
ok("log SKIP off", LogHas("SKIP off emo=FART who=other"))
Slash("test 4")
ok("test plays even when off", #plays == 1 and plays[1].path:find("fart\\04_trumpet", 1, true))
ok("test prints name", prints[#prints]:find("#4 Trumpet", 1, true))
ok("test logged", LastLog():find("TEST emo=FART snd=4", 1, true))
Slash("on")
ok("on", SpokenWindDB.on == true)

-- channel
Slash("ch dialog")
ok("ch Dialog", SpokenWindDB.ch == "Dialog")
plays = {}
now = now + 10
Emote(OTHER_FART, "Bob", "Player-1-0000BBBB")
ok("plays on Dialog", plays[1] and plays[1].ch == "Dialog")
Slash("ch MASTER")
ok("ch Master (any case)", SpokenWindDB.ch == "Master")
Slash("ch loud")
ok("bad ch keeps Master", SpokenWindDB.ch == "Master")
ok("bad ch says options", prints[#prints]:find("master|sfx|dialog", 1, true))

-- cd input
Slash("cd 1.25")
ok("cd 1.3 (one decimal)", SpokenWindDB.cd == 1.3, SpokenWindDB.cd)
Slash("cd 999")
ok("cd max 30", SpokenWindDB.cd == 30)
Slash("cd -1")
ok("cd -1 refused", SpokenWindDB.cd == 30)
Slash("cd abc")
ok("cd abc refused", SpokenWindDB.cd == 30)

-- muted channel: test says so
willPlay = false
Slash("test")
ok("muted test says no sound", prints[#prints]:find("no sound", 1, true))
willPlay = true

-- PlaySoundFile error never breaks the addon
local real = PlaySoundFile
PlaySoundFile = function() error("boom") end
now = now + 100
Emote(OTHER_FART, "Bob", "Player-1-0000BBBB")
ok("play error logged", LogHas("ERR play"))
PlaySoundFile = real

-- status / help: terse (two short lines)
local before = #prints
Slash("")
ok("status = 2 lines", #prints - before == 2, #prints - before)
ok("status shows set", prints[before + 1] and prints[before + 1]:find("fart 14", 1, true), prints[before + 1])
for n = before + 1, #prints do ok("line short " .. n, #prints[n] <= 100, #prints[n]) end
Slash("reset")
ok("reset", SpokenWindDB.on and SpokenWindDB.ch == "SFX" and SpokenWindDB.self and SpokenWindDB.cd == 2)
for _, l in ipairs(prints) do ok("prints tagged", l:find("Spoken Wind", 1, true) ~= nil, l) end

-- forms: real lines, names swapped out, tagged with the emote
ok("forms saved", #SpokenWindDB.forms >= 2, #SpokenWindDB.forms)
local seenMe = false
for _, f in ipairs(SpokenWindDB.forms) do
	ok("form tagged FART", f:find("^FART ") ~= nil, f)
	if f:find("Bob", 1, true) then ok("sender name hidden", false, f) end
	if f:find("<who>", 1, true) or f:find("You", 1, true) then seenMe = true end
end
ok("forms readable", seenMe)
ok("forms capped", #SpokenWindDB.forms <= 8)

-- secret values (newer clients): no error, no sound
issecretvalue = function(v) return v == "SECRET" end
plays = {}
now = now + 10
Emote("SECRET", "SECRET", "SECRET")
ok("secret: no sound, no error", #plays == 0 and not LogHas("ERR boom"))
issecretvalue = nil

-- logout summary
ev.scripts.OnEvent(ev, "PLAYER_LOGOUT")
ok("SUM line", LogHas("SUM seen=") and LogHas("hit=") and LogHas("played="))

-- saved settings survive a reload; bad ones are fixed
local saved = SpokenWindDB
saved.ch, saved.cd, saved.self = "Ambience", -3, false
Load(saved)
ok("bad ch fixed", SpokenWindDB.ch == "SFX")
ok("bad cd fixed", SpokenWindDB.cd == 2)
ok("self kept", SpokenWindDB.self == false)
ok("log kept", #SpokenWindDB.log > 1)

-- slash clash: a game emote that uses our slash word shows in BOOT
EMOTE99_TOKEN, EMOTE99_CMD2 = "WINDY", "/wind"
Load(SpokenWindDB)
ok("boot clash=1", LastLog():find("slash=/wind clash=1", 1, true), LastLog())
EMOTE99_TOKEN, EMOTE99_CMD2 = nil, nil

-- a new emote row works with no code change (test-only row and folder)
ev, ns = Load(SpokenWindDB)
SpokenWindDB.self = true
ns.EMOTES.CHEER = { folder = "cheer", stems = { enUS = { "%f[%a]cheers?%f[%A]" } },
	sounds = { { file = "01_a", name = "A" }, { file = "02_b", name = "B" } } }
ok("new row src guess", ns.SetLocale("enUS").CHEER == "guess")
plays = {}
now = now + 100
Emote("Bob cheers at you.", "Bob", "C0")
ok("new row plays its folder", plays[1] and plays[1].path:find("^Interface\\AddOns\\Spoken_Wind\\Media\\cheer\\0[12]_[ab]%.ogg$"),
	plays[1] and plays[1].path)
ok("new row logged", LastLog():find("PLAY emo=CHEER who=other", 1, true), LastLog())
SpokenWindDB.cd = 0
local cheerPaths = {}
for n = 1, 40 do now = now + 1 Emote("Bob cheers.", "Bob", "C" .. n) cheerPaths[#cheerPaths + 1] = plays[#plays].path end
local alt = true
for n = 2, #cheerPaths do if cheerPaths[n] == cheerPaths[n - 1] then alt = false end end
ok("new row: own picker, never twice in a row", alt)
now = now + 1
Emote(OTHER_FART, "Bob", "F1")
ok("fart still plays fart folder", plays[#plays].path:find("\\Media\\fart\\", 1, true) ~= nil, plays[#plays].path)
ok("fart still logged FART", LastLog():find("PLAY emo=FART", 1, true), LastLog())
ok("status lists both sets", (function()
	local b = #prints Slash("") return prints[b + 1] and prints[b + 1]:find("cheer 2 · fart 14", 1, true)
end)(), prints[#prints - 1])
ns.EMOTES.CHEER = nil

-- nothing forbidden, no stray globals
ok("no forbidden calls", #forbidden == 0, forbidden[1])
local stray = {}
for key in pairs(_G) do
	if not BASE[key] and not ({ SpokenWindDB = 1, SLASH_SPOKENWIND1 = 1, SLASH_SPOKENWIND2 = 1, SlashCmdList = 1,
		CreateFrame = 1, GetTime = 1, date = 1, PlaySoundFile = 1, UnitGUID = 1, UnitName = 1, GetLocale = 1,
		EMOTE41_TOKEN = 1, EMOTE41_CMD1 = 1, SetCVar = 1, hooksecurefunc = 1, SendChatMessage = 1, DoEmote = 1,
		RunMacroText = 1, CastSpellByName = 1, UseAction = 1, SetBinding = 1 })[key] then
		stray[#stray + 1] = key
	end
end
ok("no stray globals", #stray == 0, table.concat(stray, ","))

print = out
print(("core: %d pass, %d fail"):format(pass, fail))
if fail > 0 then error("core tests failed") end
