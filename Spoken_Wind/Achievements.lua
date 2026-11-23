-- Spoken Wind: achievements. One table: the Classic tab (rarest first = icon sheet
-- order), then the Social tab (sheet order). Rows are data: rename or cut a row
-- here, nothing else changes. Stat rows (stat + goal) need no code.
-- Earn = a toast (Toast.lua, own frame) + one log line "ACH <id> toast=1".
-- Dates and progress live in SpokenWindDB.ach only: names and GUIDs never leave
-- the local save. Core feeds two calls: AchSeen (every /fart, before the
-- cooldown: Machine Gun counts blocked ones) and AchPlayed (each fart that played).
-- Heard.lua calls AchStats after your counts change; Sync calls AchInSync.
-- Secret rows (secret = true) hide until earned and do not count in "N/M".
-- The author rows (Lab Partner, Straight From the Source, Author's Note) come from
-- the author's dev addon flag (TestMode, Sync, Heard call AchEarn).
-- Legend rows (leg = true: Born Legendary, Witness, Every Wind That Blows): Soon without
-- the race set. With it, only a legend tier sound (tier 6) earns them. An Artifact
-- sound (tier 7) never does.
-- Collection rows (dex = N different sounds, dexVoice = a full voice page) count
-- from Collection.lua; Soon while the pool is too small for them. Collection.lua
-- calls AchDex after each played fart.
-- Window: AchWin.lua (own frame from the UI screens sw-ach + 4 tab bodies). The Options
-- page only has a button to it.
-- Board tab (0.6.4, data from Board.lua): the All strip, Most heard + Top listener (top 10,
-- your row under a list when you are not in it), "Seen ?". Names only on this tab.
-- Tier numbers (7, tier colors, no words) at the right end of the strip: Mine on the
-- other tabs, All on the Board tab. Hover = tier names + numbers.
local _, ns = ...

local ICON = "Interface\\AddOns\\Spoken_Wind\\Media\\ach\\"
local RING = ICON .. "ring"   -- white frame ring, tinted per quality
-- WoW item quality: 5 legendary, 4 epic, 3 rare, 2 uncommon, 1 common, 0 poor (fallback colors)
local HEX = { [6] = "e6cc80", [5] = "ff8000", [4] = "a335ee", [3] = "0070dd", [2] = "1eff00", [1] = "ffffff", [0] = "9d9d9d" }
local GOLD, GREY, WHITE = "|cffffd100", "|cff9d9d9d", "|cffffffff"

ns.ACH = {
	{ id = "super", name = "Super Legendary", q = 5, rule = "Hear the super legendary fart" },
	{ id = "legend", name = "Legend Has It", q = 4, rule = "Hear #13 Legend" },
	{ id = "orchestra", name = "Full Orchestra", q = 4, rule = "Hear all 14 sounds" },
	{ id = "thousand", name = "Thousand Winds", q = 4, rule = "1000 farts" },
	{ id = "gas", name = "Gas Giant", q = 4, rule = "100 farts" },
	{ id = "penpals", name = "Pen Pals", q = 3, rule = "Farts from 10 people" },
	{ id = "cropduster", name = "Crop Duster", q = 3, rule = "5 people in 60s" },
	{ id = "double", name = "Double Trouble", q = 3, rule = "2 people in 1s" },
	{ id = "callback", name = "Call and Response", q = 3, rule = "A fart 5s after yours" },
	{ id = "machinegun", name = "Machine Gun", q = 3, rule = "One person, 10 /fart in 10s (silent count)" },
	{ id = "sbd", name = "Silent But Deadly", q = 2, rule = "A fart on a muted channel" },
	{ id = "night", name = "Night Shift", q = 2, rule = "A fart 00:00-04:00" },
	{ id = "tuba", name = "Tuba Tuesday", q = 2, rule = "#11 Tuba on a Tuesday" },
	{ id = "selfstarter", name = "Self-Starter", q = 2, rule = "Your own /fart" },
	{ id = "first", name = "First Wind", q = 2, rule = "Hear a fart" },
	-- secret: only the dev Test (Spoken_Wind_Dev) gives it; icon = the game's question mark
	{ id = "testsmell", name = "Test Farts Don't Smell", q = 1, rule = "Press Play on Test", secret = true,
		icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
	-- secret: an Artifact shart (#1333-#1337, Voices.lua) played here, own or heard
	{ id = "shart", name = "That wasn't a fart", q = 5, rule = "Hear a Shartifact", secret = true,
		icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
	-- Social (stats from Heard.lua: best = most in one fart, heard, people, own presses)
	{ id = "heard", tab = "social", name = "Someone Heard That", q = 2, rule = "1 player heard your fart",
		stat = "best", goal = 1 },
	{ id = "packed", tab = "social", name = "Packed House", q = 3, rule = "1 fart heard by 5", stat = "best", goal = 5 },
	{ id = "ovation", tab = "social", name = "Standing Ovation", q = 4, rule = "1 fart heard by 10",
		stat = "best", goal = 10 },
	{ id = "around", tab = "social", name = "Word Gets Around", q = 2, rule = "Heard 25", stat = "heard", goal = 25 },
	{ id = "town", tab = "social", name = "Talk of the Town", q = 3, rule = "Heard 100", stat = "heard", goal = 100 },
	{ id = "fame", tab = "social", name = "Wind of Fame", q = 4, rule = "Heard 500", stat = "heard", goal = 500 },
	{ id = "fanclub", tab = "social", name = "Fan Club", q = 2, rule = "5 people heard you", stat = "people", goal = 5 },
	{ id = "cult", tab = "social", name = "Cult Following", q = 3, rule = "25 people heard you",
		stat = "people", goal = 25 },
	{ id = "household", tab = "social", name = "Household Name", q = 4, rule = "100 people heard you",
		stat = "people", goal = 100 },
	{ id = "insync", tab = "social", name = "In Sync", q = 3, rule = "10 group or guild farts in sync",
		stat = "sync", goal = 10 },
	{ id = "born", tab = "social", name = "Born Legendary", q = 4, rule = "Roll your own legendary fart", leg = true },
	{ id = "witness", tab = "social", name = "Witness", q = 4, rule = "Hear another player's legendary fart",
		leg = true },
	{ id = "everywind", tab = "social", name = "Every Wind That Blows", q = 5,
		rule = "Legendary fart of all 9 races, heard or own", leg = true },
	{ id = "labpartner", tab = "social", name = "Lab Partner", q = 4, rule = "Help the author test (pair test)",
		secret = true },
	{ id = "source", tab = "social", name = "Straight From the Source", q = 4, rule = "Hear the author fart",
		secret = true },
	{ id = "authornote", tab = "social", name = "Author's Note", q = 4, rule = "The author heard your fart",
		secret = true },
	{ id = "windbag", tab = "social", name = "Windbag", q = 3, rule = "250 own /fart", stat = "own", goal = 250 },
	-- Collection (different sounds heard; icons = the game's own until the author draws them)
	{ id = "starter", tab = "collection", name = "Starter Pack", q = 2, rule = "Hear 10 sounds", dex = 10,
		icon = "Interface\\Icons\\INV_Misc_Bag_10" },
	{ id = "collector", tab = "collection", name = "Collector", q = 3, rule = "Hear 100 sounds", dex = 100,
		icon = "Interface\\Icons\\INV_Box_01" },
	{ id = "gasologist", tab = "collection", name = "Gasologist", q = 4, rule = "Hear 500 sounds", dex = 500,
		icon = "Interface\\Icons\\Spell_Nature_Cyclone" },
	{ id = "pitch", tab = "collection", name = "Perfect Pitch", q = 4, rule = "Hear all 74 of one voice",
		dexVoice = true, icon = "Interface\\Icons\\INV_Misc_Drum_01" },
	{ id = "complete", tab = "collection", name = "The Complete Works", q = 5, rule = "Hear all 1337", dex = 1337, set = true,
		icon = "Interface\\Icons\\INV_Crown_01" },
}

local TABS = { "classic", "social", "collection", "board" }
local TAB_NAME = { classic = "Classic", social = "Social", collection = "Collection", board = "Board" }
local byId, MAIN = {}, {}
for _, row in ipairs(ns.ACH) do
	row.tab = row.tab or "classic"
	byId[row.id] = row
	if not row.secret then MAIN[row.tab] = (MAIN[row.tab] or 0) + 1 end
end
ns.ACH_TABS, ns.ACH_MAIN = TABS, MAIN

local GAS, THOUSAND = 100, 1000   -- farts (SpokenWindDB.stats.all)
local PEOPLE = 10                 -- Pen Pals
local CROP_N, CROP_S = 5, 60      -- Crop Duster: people, seconds
local DOUBLE_S = 1                -- Double Trouble: two people under 1 s apart
local CALL_S = 5                  -- Call and Response
local GUN_N, GUN_S = 10, 10       -- Machine Gun: /fart, seconds
local NIGHT_END = 4               -- Night Shift: hour 0 to 3
local RECENT_MAX, PRUNE_AT = 32, 32

local db, ach
local lastSelf                -- GetTime() of your last /fart (session only)
local recent = {}             -- others' farts in the last 60 s: { key, t }
local burst, nBurst = {}, 0   -- key -> GetTime() of the last 10 /fart
local BoardOut

local function Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end
local function Num(v) return type(v) == "number" and v >= 0 and v < math.huge and math.floor(v) or nil end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

function ns.AchIcon(row) return row.icon or ICON .. row.id end
function ns.AchRow(id) return byId[id] end
function ns.AchHas(id) return ach ~= nil and ach.done[id] ~= nil end
ns.ACH_RING = RING

-- "|cffRRGGBB" of a quality: the game's own color, else the fallback.
function ns.AchColor(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	local hex = type(c) == "table" and c.hex
	if type(hex) == "string" and hex:match("^|c%x%x%x%x%x%x%x%x$") then return hex end
	return "|cff" .. (HEX[q] or "ffffff")
end

-- r, g, b (0-1) of a quality, for the ring: the game's own color, else the fallback.
function ns.AchRGB(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
		return c.r, c.g, c.b
	end
	local hex = HEX[q] or "ffffff"
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- A ring texture: the quality color when done, else grey (poor).
function ns.AchRingPaint(tex, q, done)
	tex:SetTexture(RING)
	tex:SetVertexColor(ns.AchRGB(done and q or 0))
end

-- Rows done (all tabs, or one): the main ones, then the secret ones.
function ns.AchDone(tab)
	local n, s = 0, 0
	for id in pairs(ach and ach.done or {}) do
		local row = byId[id]
		if not tab or row.tab == tab then
			if row.secret then s = s + 1 else n = n + 1 end
		end
	end
	return n, s
end

-- Core calls this at ADDON_LOADED: checks the save, drops what is not valid.
function ns.AchInit(saved)
	db = saved
	local a = type(db.ach) == "table" and db.ach or {}
	local done, heard, people = {}, {}, {}
	if type(a.done) == "table" then
		for id, t in pairs(a.done) do if byId[id] and type(t) == "number" then done[id] = t end end
	end
	if type(a.heard) == "table" then
		for f, v in pairs(a.heard) do if type(f) == "string" and v == true then heard[f] = true end end
	end
	if type(a.people) == "table" and not done.penpals then
		local n = 0
		for k, v in pairs(a.people) do
			if type(k) == "string" and v == true and n < PEOPLE then people[k] = true n = n + 1 end
		end
	end
	ach = { done = done, heard = heard, people = people, sync = Num(a.sync) or 0 }
	db.ach = ach
	local p = db.achpos
	if type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" or p.x ~= p.x or p.y ~= p.y then
		db.achpos = nil
	end
	lastSelf, recent, burst, nBurst = nil, {}, {}, 0
	if ns.AchWinInit then ns.AchWinInit(db) end
end

local function Earn(id)
	if ach.done[id] then return end
	ach.done[id] = time()
	local row = byId[id]
	local okCall, shown = false, false
	if ns.Toast then okCall, shown = pcall(ns.Toast, row) end
	local toast = okCall and shown == true
	if not okCall and ns.Toast then ns.Log("ERR toast " .. tostring(shown)) end
	if not toast then ns.Say("|T" .. ns.AchIcon(row) .. ":16|t " .. ns.AchColor(row.q) .. row.name .. "|r") end
	ns.Log(("ACH %s toast=%d"):format(id, toast and 1 or 0))
	if ns.AchRedraw then ns.AchRedraw() end
	if ns.RewardRefresh then ns.RewardRefresh() end
end
ns.AchEarn = Earn   -- the dev folder's "fire" uses the same path as a real earn; author rows too

-- Dev folder: read SpokenWindDB.ach again after it changed it (checks it,
-- redraws the window and the rewards).
function ns.AchReload()
	ns.AchInit(db)
	if ns.AchRedraw then ns.AchRedraw() end
	if ns.RewardRefresh then ns.RewardRefresh() end
end

-- Dev Test (Play button or /wind test): the secret row only. Not a fart: no
-- other row, no count. Core calls it only with the dev flag.
function ns.AchTested() Earn("testsmell") end

-- The old 14 heard so far (Full Orchestra; the race set has its own Collection rows).
local function OldN() return ns.BASE_N or #ns.EMOTES.FART.sounds end
local function Heard()
	local n, snd = 0, ns.EMOTES.FART.sounds
	for i = 1, OldN() do if ach.heard[snd[i].file] then n = n + 1 end end
	return n
end

-- Every Wind That Blows: races with a legend tier sound (VOX), and the races of
-- those heard or own so far (the collection keys + the sound i that plays now).
local function LegendRaces(now)
	local vox, snd = ns.VOX, ns.EMOTES.FART.sounds
	local dex = type(db.dex) == "table" and db.dex or {}
	local all, have, nAll, nHave = {}, {}, 0, 0
	for _, v in ipairs(vox and vox.ok and vox.order or {}) do
		for _, i in ipairs(v.tiers[6] or {}) do
			if not all[v.race] then all[v.race] = true nAll = nAll + 1 end
			if not have[v.race] and (i == now or dex[snd[i].file]) then have[v.race] = true nHave = nHave + 1 end
		end
	end
	return nHave, nAll
end

-- A stat row's number now: Heard.lua's counts, or In Sync's own count.
local function StatNum(key)
	if key == "sync" then return ach.sync end
	local s = ns.HeardNums and ns.HeardNums()
	return s and tonumber(s[key]) or 0
end

-- Heard.lua: your counts changed. Every stat row at its goal is earned.
function ns.AchStats()
	if not ach then return end
	for _, row in ipairs(ns.ACH) do
		if row.stat and not ach.done[row.id] and StatNum(row.stat) >= row.goal then Earn(row.id) end
	end
end

-- A Collection row the pool cannot give yet: a count over the pool size, or
-- Perfect Pitch with no voice page. d = ns.DexNums().
local function DexSoon(row, d)
	if row.dex then return (row.set and d.setAll or d.all) < row.dex end
	return row.dexVoice == true and not d.voice
end

-- Collection.lua: after each played fart. Every Collection row at its goal is earned.
function ns.AchDex()
	if not ach or not ns.DexNums then return end
	local d
	for _, row in ipairs(ns.ACH) do
		if (row.dex or row.dexVoice) and not ach.done[row.id] then
			d = d or ns.DexNums()
			if row.dex and (row.set and d.setHave or d.have) >= row.dex or row.dexVoice and d.full then Earn(row.id) end
		end
	end
end

-- Sync: a group or guild fart played from its message (in sync). who = how it came.
function ns.AchInSync(who)
	if not ach or who == "pair" or ach.done.insync then return end
	ach.sync = ach.sync + 1
	ns.AchStats()
end

-- Every /fart near you (yours too), before the cooldown check. key: one per person.
function ns.AchSeen(key, mine, now)
	if mine then lastSelf = now end
	if ach.done.machinegun or key == "?" then return end
	local b = burst[key]
	if not b then
		nBurst = nBurst + 1
		if nBurst > PRUNE_AT then
			for k, list in pairs(burst) do
				if now - list[#list] > GUN_S then burst[k] = nil nBurst = nBurst - 1 end
			end
		end
		b = {}
		burst[key] = b
	end
	b[#b + 1] = now
	if #b > GUN_N then table.remove(b, 1) end
	if #b == GUN_N and now - b[1] <= GUN_S then Earn("machinegun") burst, nBurst = {}, 0 end
end

-- A fart that played. ok: the game said it plays (false = muted channel),
-- err: PlaySoundFile failed (then no Silent But Deadly).
function ns.AchPlayed(token, i, key, mine, now, ok, err)
	local done = ach.done
	local row = ns.EMOTES[token]
	local snd = row and row.sounds[i] or {}
	Earn("first")
	if snd.super then Earn("super") end
	if snd.file == "13_legend" then Earn("legend") end
	if snd.shart then Earn("shart") end
	if snd.tier == 6 and token == "FART" then   -- the race set's legend tier only (Artifact = tier 7)
		Earn(mine and "born" or "witness")
		if not done.everywind then
			local have, all = LegendRaces(i)
			if all > 0 and have >= all then Earn("everywind") end
		end
	end
	if snd.file == "11_tuba" and date("%w") == "2" then Earn("tuba") end
	if (tonumber(date("%H")) or 12) < NIGHT_END then Earn("night") end
	if ok == false and not err then Earn("sbd") end
	if token == "FART" and snd.file and not done.orchestra and i <= OldN() then
		ach.heard[snd.file] = true
		if Heard() >= OldN() then Earn("orchestra") end
	end
	local all = type(db.stats) == "table" and tonumber(db.stats.all) or 0
	if all >= GAS then Earn("gas") end
	if all >= THOUSAND then Earn("thousand") end
	if mine then Earn("selfstarter") return end
	-- others only from here
	if lastSelf and now - lastSelf <= CALL_S then Earn("callback") end
	if key == "?" then return end
	if not done.penpals then
		ach.people[key] = true
		if Count(ach.people) >= PEOPLE then Earn("penpals") ach.people = {} end
	end
	while recent[1] and now - recent[1].t > CROP_S do table.remove(recent, 1) end
	local people, double = { [key] = true }, false
	for _, r in ipairs(recent) do
		if r.key ~= key then
			people[r.key] = true
			if now - r.t < DOUBLE_S then double = true end
		end
	end
	if double then Earn("double") end
	if Count(people) >= CROP_N then Earn("cropduster") end
	recent[#recent + 1] = { key = key, t = now }
	if #recent > RECENT_MAX then table.remove(recent, 1) end
end

-- ------------------------------------------------------------ lines
local function Progress(row, d)
	local id = row.id
	if row.dex and d then return math.min(row.set and d.setHave or d.have, row.dex), row.dex end
	if row.dexVoice and d then return d.best, d.bestAll end
	if id == "orchestra" then return Heard(), OldN() end
	if id == "everywind" then return LegendRaces() end
	if id == "gas" or id == "thousand" then
		local all = type(db.stats) == "table" and tonumber(db.stats.all) or 0
		local goal = id == "gas" and GAS or THOUSAND
		return math.min(all, goal), goal
	end
	if id == "penpals" then return Count(ach.people), PEOPLE end
	if row.stat then return math.min(StatNum(row.stat), row.goal), row.goal end
end

local function RewardOf(id)
	for _, r in ipairs(ns.REWARDS or {}) do if r.ach == id then return r.cmd end end
end

-- Tab label: "Classic 3/15" (+N once a secret row is earned).
function ns.AchTabText(tab)
	if tab == "board" then return TAB_NAME.board end
	local n, s = ns.AchDone(tab)
	return ("%s %d/%d"):format(TAB_NAME[tab], n, MAIN[tab] or 0) .. (s > 0 and (" +" .. s) or "")
end

-- Stats strip: nil when Heard.lua is not there.
function ns.AchStatsText()
	local s = ns.HeardNums and ns.HeardNums()
	if not s then return nil end
	return ("Farts %d · Heard %d · People %d · Legend %d"):format(s.own, s.heard, s.people, s.legend)
end

-- A Board row as a line: rank, short name, number + the tip (name-realm, numbers, seen).
local function RowLine(r, now)
	local stat
	if r.me then stat = "This character"
	elseif r.own then stat = "Your character"
	elseif r.at then
		local d = math.floor((now - r.at) / 86400)
		stat = d <= 0 and "Seen today" or ("Seen %d d ago"):format(d)
	else stat = "" end
	local hidden = r.own and r.hide == 1
	return { rank = r.rank, short = r.n, num = r.v, me = r.me, own = r.own,
		name = r.n .. (r.r ~= "" and ("-" .. r.r) or ""), color = hidden and GREY or r.own and GOLD or WHITE,
		rule = ("Farts %d · Heard %d · Listened %d"):format(r.f, r.h, r.l), stat = stat,
		gold = hidden and "Hidden · /wind board on" or nil,
		kind = "board", f = r.f, h = r.h, l = r.l, at = r.at, hidden = hidden or nil }
end

-- The Board tab: out.board = BoardLines, out.cols = the 2 lists as lines, out.stats = the All strip.
BoardOut = function(out)
	local b = ns.BoardLines and ns.BoardLines() or nil
	if not b then return out end
	local now = time()
	out.board, out.stats = b, b.text
	out.cols = {}
	for k, src in ipairs({ { "Most heard", b.heard }, { "Top listener", b.listen } }) do
		local col = { head = src[1], rows = {} }
		for i, r in ipairs(src[2]) do col.rows[i] = RowLine(r, now) end
		if src[2].own then col.own = RowLine(src[2].own, now) end
		out.cols[k] = col
	end
	local age = b.age and (" · Top 10 oldest %d d"):format(b.age) or ""
	out.allTip = { name = "All players", color = GOLD, rule = "Players you met with the addon",
		stat = b.all.oldest and ("Oldest " .. date("%m-%d", b.all.oldest)) or "", gold = b.seen .. age }
	out.seenTip = { name = b.seen, color = GOLD,
		rule = b.age and ("Top 10 oldest %d d"):format(b.age) or "Top 10 empty" }
	return out
end

-- The stat of a row: "Done 11-22", "Soon", "3/5" or "".
local function Stat(row, d)
	local t = ach.done[row.id]
	if t then return "Done " .. date("%m-%d", t) end
	if row.soon or row.leg and not (ns.VOX and ns.VOX.ok) or d and DexSoon(row, d) then return "Soon" end
	local have, goal = Progress(row, d)
	return have and (have .. "/" .. goal) or ""
end

-- One row's stat, as on its tile (the rewards popup, the reward tip).
function ns.AchStat(id)
	local row = byId[id]
	if not row then return "" end
	return Stat(row, row.tab == "collection" and ns.DexNums and ns.DexNums() or nil)
end

-- { tab, head, stats, tiles = { id, icon, name, q, done, rule, stat, cmd } } of one tab.
-- stat: "Done 11-22", "3/5", "Soon" or "". A secret row shows only once earned.
-- The Collection tab adds the sounds of one page (pg): sounds = { key, token, i, q, done,
-- heard, star, text, name, fit, rule, stat, gold }, page, pages, pageHead, have, all.
-- fit = the label once heard (no colors): the row height fits it, so nothing is cut.
function ns.AchLines(tab, pg)
	tab = TAB_NAME[tab] and tab or "classic"
	local d = tab == "collection" and ns.DexNums and ns.DexNums() or nil
	local out = { tab = tab, head = ns.AchTabText(tab), tiles = {} }
	if tab == "board" then return BoardOut(out) end
	if d then out.stats = ns.DexStatsText(d) else out.stats = ns.AchStatsText() end
	for _, row in ipairs(ns.ACH) do
		local t = ach.done[row.id]
		if row.tab == tab and (t or not row.secret) then
			local stat = Stat(row, d)
			local have, goal
			if not t and stat ~= "Soon" and stat ~= "" then have, goal = Progress(row, d) end
			out.tiles[#out.tiles + 1] = { id = row.id, icon = ns.AchIcon(row), name = row.name, q = row.q,
				done = t ~= nil, rule = row.rule, stat = stat, cmd = RewardOf(row.id), ord = #out.tiles + 1,
				t = t, have = have, goal = goal }
		end
	end
	if d then
		local ps = d.pages
		local n = math.min(math.max(math.floor(tonumber(pg) or 1), 1), #ps)
		local p = ps[n]
		out.page, out.pages, out.have, out.all = n, #ps, d.have, d.all
		out.pageHead = ("%s %d/%d"):format(p.name, p.have, #p.tiles)
		out.pageName, out.pageHave, out.pageAll = p.name, p.have, #p.tiles
		out.sounds = {}
		for _, t in ipairs(p.tiles) do
			local e = d.heard[t.key]
			local num = "#" .. t.num
			if e then
				out.sounds[#out.sounds + 1] = { key = t.key, token = t.token, i = t.i, q = t.q, done = true, heard = true,
					star = e.own > 0, text = GREY .. num .. "|r " .. ns.AchColor(t.q) .. t.name .. "|r",
					name = num .. " " .. t.name, fit = num .. " " .. t.name,
					rule = ("Heard %d · Own %d"):format(e.n, e.own),
					stat = e.t > 0 and ("First " .. date("%m-%d", e.t)) or "", gold = "Click = play",
					kind = "sound", num = t.num, sname = t.name, n = e.n, own = e.own, t = e.t }
			else
				out.sounds[#out.sounds + 1] = { key = t.key, q = t.q, done = false, heard = false, star = false,
					text = GREY .. num .. " ???|r", name = num .. " ???", fit = num .. " " .. t.name, rule = "Not heard yet",
					stat = "", kind = "sound", num = t.num }
			end
		end
	end
	-- Earned first, rarest first (same rarity = list order), then the locked ones in list order.
	-- Same rule on the Collection strip.
	table.sort(out.tiles, function(a, b)
		if a.done ~= b.done then return a.done end
		if a.done and a.q ~= b.q then return a.q > b.q end
		return a.ord < b.ord
	end)
	return out
end

-- Dev only (/wind ach test [n]): shows a toast, earns nothing.
function ns.AchTest(n)
	local row = ns.ACH[tonumber(n) or 0] or ns.ACH[math.random(#ns.ACH)]
	local okCall, shown = pcall(ns.Toast, row)
	local toast = okCall and shown == true
	if not toast then ns.Say("|T" .. ns.AchIcon(row) .. ":16|t " .. ns.AchColor(row.q) .. row.name .. "|r") end
	ns.Log(("ACH test %s toast=%d"):format(row.id, toast and 1 or 0))
end
