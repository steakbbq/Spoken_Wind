-- Emotes.lua + Match.lua: which emote lines are farts. Run: python -I tools/lua.py match
local pass, fail = 0, 0
local function ok(name, cond, extra)
	if cond then pass = pass + 1
	else fail = fail + 1 print("FAIL " .. name .. (extra and (" :: " .. tostring(extra)) or "")) end
end

local function LoadNS()
	local n = {}
	assert(loadfile(ADDON_DIR .. "/Emotes.lua"))("Spoken_Wind", n)
	assert(loadfile(ADDON_DIR .. "/Match.lua"))("Spoken_Wind", n)
	return n
end
GetLocale = function() return "enUS" end
local ns = LoadNS()
local function IsFart(t, s) return ns.Match(t, s) == "FART" end

-- enUS: every form of the fart emote (you / someone / at you / at a target / at self)
ok("src enUS checked", ns.SetLocale("enUS").FART == "checked")
local yes = {
	{ "You fart loudly. Phew...what stinks?", "Me" },
	{ "You brush up against Bob and fart loudly.", "Me" },
	{ "Bob farts loudly. Phew...what stinks?", "Bob" },
	{ "Bob brushes up against you and farts loudly.", "Bob" },
	{ "Bob brushes up against Alice and farts loudly.", "Bob" },
	{ "Bob farts.", "Bob-OtherRealm" },
	{ "You fart.", "Me" },
	{ "Bob farts at you.", "Bob" },
	{ "Bob farts at Fartbag.", "Bob" },
	{ "Fart farts loudly.", "Fart" },                 -- player named Fart, real fart
}
for _, c in ipairs(yes) do ok("yes: " .. c[1], IsFart(c[1], c[2])) end

local no = {
	{ "Fart waves at you.", "Fart" },                 -- player named Fart, not a fart
	{ "Bob waves at Fart.", "Bob" },                  -- target named Fart
	{ "Squilliam Fartbag waves.", "Squilliam Fartbag" },
	{ "You cheer at Coleman Farthing.", "Me" },
	{ "Bob laughs at Fartface.", "Bob" },
	{ "Bob laughs.", "Bob" },
	{ "You smell Bob. Something stinks.", "Me" },
	{ "Bob is far too tired.", "Bob" },
	{ "Bob stares farther than ever.", "Bob" },      -- word edge: farther is not fart
	{ "Bob waves at the farthest hill.", "Bob" },
	{ "", "Bob" },
}
for _, c in ipairs(no) do ok("no: " .. c[1], not IsFart(c[1], c[2])) end
ok("nil text", IsFart(nil, "Bob") == false)
ok("number text", IsFart(5, "Bob") == false)
ok("nil sender", IsFart("Bob farts loudly.", nil) == true)

-- secret values (newer clients): never touched
issecretvalue = function(v) return v == "SECRET farts" end
ok("secret text skipped", IsFart("SECRET farts", "Bob") == false)
issecretvalue = nil

-- other locales (guesses, not seen in game yet)
ok("src deDE guess", ns.SetLocale("deDE").FART == "guess")
ok("deDE furzt", IsFart("Bob furzt laut.", "Bob"))
ok("deDE no", not IsFart("Bob winkt.", "Bob"))
ns.SetLocale("frFR")
ok("frFR pète", IsFart("Bob pète bruyamment.", "Bob"))
ok("frFR petit no", not IsFart("Bob est petit.", "Bob"))
ns.SetLocale("esES")
ok("esES pedo", IsFart("Bob se tira un pedo.", "Bob"))
ns.SetLocale("ruRU")
ok("ruRU", IsFart("Боб громко пукает.", "Боб"))
ns.SetLocale("zhCN")
ok("zhCN", IsFart("Bob放屁了。", "Bob"))
ok("zhCN name with the word, no case to help", not IsFart("放屁王向你挥手。", "放屁王"))
ok("zhCN name with realm", not IsFart("放屁王向你挥手。", "放屁王-Realm"))
ns.SetLocale("koKR")
ok("koKR", IsFart("Bob님이 방귀를 뀝니다.", "Bob"))

-- unknown locale: the game's own /fart word (EMOTEn_TOKEN / EMOTEn_CMD1)
EMOTE7_TOKEN, EMOTE7_CMD1 = "WAVE", "/wave"
EMOTE41_TOKEN, EMOTE41_CMD1 = "FART", "/pupsen"
ok("cmd found", ns.EmoteCommand("FART") == "/pupsen")
ok("src cmd", ns.SetLocale("xxXX").FART == "cmd")
ok("cmd word hit", IsFart("Bob pupsen laut.", "Bob"))
ok("cmd word no", not IsFart("Bob winkt.", "Bob"))
ok("cmd word in name no", not IsFart("Bob winkt Pupsenmann.", "Bob"))
EMOTE41_CMD1 = "/fa.t"
ns.SetLocale("xxXX")
ok("cmd magic chars escaped", not IsFart("Bob fart.", "Bob") and IsFart("Bob fa.t", "Bob"))
EMOTE41_TOKEN, EMOTE41_CMD1 = nil, nil
ok("no cmd -> none", ns.SetLocale("xxXX").FART == "none" and ns.EmoteCommand("FART") == nil)
ok("none uses english", IsFart("Bob farts.", "Bob"))

-- lazy locale: IsFart works before PLAYER_LOGIN set it
GetLocale = function() return "enUS" end
local ns2 = LoadNS()
ok("lazy locale", ns2.Match("Bob farts loudly.", "Bob") == "FART")

-- the table: FART is the only row, and it has the keys a row needs
local rows = 0
for token, row in pairs(ns2.EMOTES) do
	rows = rows + 1
	ok("row " .. token .. " folder", type(row.folder) == "string" and row.folder:match("^[%w_]+$") ~= nil)
	ok("row " .. token .. " sounds", type(row.sounds) == "table" and #row.sounds > 0)
	ok("row " .. token .. " enUS stems", type(row.stems) == "table" and type(row.stems.enUS) == "table")
end
ok("only FART shipped", rows == 1 and ns2.EMOTES.FART ~= nil)
ok("fart folder", ns2.EMOTES.FART.folder == "fart")

-- a new row needs no code change: add one, it matches, its own token comes back
ns2.EMOTES.CHEER = { folder = "cheer", stems = { enUS = { "%f[%a]cheers?%f[%A]" } },
	sounds = { { file = "01_x", name = "X" } } }
local srcs = ns2.SetLocale("enUS")
ok("new row source", srcs.CHEER == "guess" and srcs.FART == "checked")
ok("new row matches", ns2.Match("Bob cheers at you.", "Bob") == "CHEER")
ok("fart still FART", ns2.Match("Bob farts loudly.", "Bob") == "FART")
ok("tokens sorted", table.concat(ns2.Tokens(), ",") == "CHEER,FART")
ok("neither", ns2.Match("Bob waves.", "Bob") == nil)

print(("match: %d pass, %d fail"):format(pass, fail))
if fail > 0 then error("match tests failed") end
