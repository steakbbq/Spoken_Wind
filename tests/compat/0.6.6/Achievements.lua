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
-- Soon rows (soon = true) stay locked until the legend tier ships.
-- Collection rows (dex = N different sounds, dexVoice = a full voice page) count
-- from Collection.lua; Soon while the pool is too small for them. Collection.lua
-- calls AchDex after each played fart.
-- Window: own frame (see below), tabs Classic, Social, Collection, Board. The Options
-- page only has a button to it.
-- Board tab (0.6.4, data from Board.lua): the All strip, Most heard + Top listener (top 10,
-- your row under a list when you are not in it), "Seen ?". Names only on this tab.
-- Tier numbers (7, tier colors, no words) at the right end of the strip: Mine on the
-- other tabs, All on the Board tab. Hover = tier names + numbers.
local _, ns = ...

local ICON = "Interface\\AddOns\\Spoken_Wind\\Media\\ach\\"
local RING = ICON .. "ring"   -- white frame ring, tinted per quality
-- WoW item quality: 5 legendary, 4 epic, 3 rare, 2 uncommon, 1 common, 0 poor (fallback colors)
local HEX = { [5] = "ff8000", [4] = "a335ee", [3] = "0070dd", [2] = "1eff00", [1] = "ffffff", [0] = "9d9d9d" }
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
	{ id = "born", tab = "social", name = "Born Legendary", q = 4, rule = "Roll your own legendary fart", soon = true },
	{ id = "witness", tab = "social", name = "Witness", q = 4, rule = "Hear another player's legendary fart",
		soon = true },
	{ id = "everywind", tab = "social", name = "Every Wind That Blows", q = 5,
		rule = "Legendary fart of all 9 races, heard or own", soon = true },
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
	{ id = "complete", tab = "collection", name = "The Complete Works", q = 5, rule = "Hear all 1337", dex = 1337,
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
local win, Draw, BoardOut

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
	if win and win:IsShown() then Draw() end
	if ns.RewardRefresh then ns.RewardRefresh() end
end
ns.AchEarn = Earn   -- the dev folder's "fire" uses the same path as a real earn; author rows too

-- Dev folder: read SpokenWindDB.ach again after it changed it (checks it,
-- redraws the window and the rewards).
function ns.AchReload()
	ns.AchInit(db)
	if win and win:IsShown() then Draw() end
	if ns.RewardRefresh then ns.RewardRefresh() end
end

-- Dev Test (Play button or /wind test): the secret row only. Not a fart: no
-- other row, no count. Core calls it only with the dev flag.
function ns.AchTested() Earn("testsmell") end

-- Sounds of the fart set heard so far (Full Orchestra).
local function Heard()
	local n = 0
	for _, s in ipairs(ns.EMOTES.FART.sounds) do if ach.heard[s.file] then n = n + 1 end end
	return n
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
	if row.dex then return d.all < row.dex end
	return row.dexVoice == true and not d.voice
end

-- Collection.lua: after each played fart. Every Collection row at its goal is earned.
function ns.AchDex()
	if not ach or not ns.DexNums then return end
	local d
	for _, row in ipairs(ns.ACH) do
		if (row.dex or row.dexVoice) and not ach.done[row.id] then
			d = d or ns.DexNums()
			if row.dex and d.have >= row.dex or row.dexVoice and d.full then Earn(row.id) end
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
	if snd.file == "11_tuba" and date("%w") == "2" then Earn("tuba") end
	if (tonumber(date("%H")) or 12) < NIGHT_END then Earn("night") end
	if ok == false and not err then Earn("sbd") end
	if token == "FART" and snd.file and not done.orchestra then
		ach.heard[snd.file] = true
		if Heard() >= #row.sounds then Earn("orchestra") end
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
	if row.dex and d then return math.min(d.have, row.dex), row.dex end
	if row.dexVoice and d then return d.best, d.bestAll end
	if id == "orchestra" then return Heard(), #ns.EMOTES.FART.sounds end
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
		gold = hidden and "Hidden · /wind board on" or nil }
end

-- The Board tab: out.board = BoardLines, out.cols = the 2 lists as lines, out.stats = the All strip.
BoardOut = function(out)
	local b = ns.BoardLines and ns.BoardLines() or nil
	if not b then return out end
	local now = time()
	out.board, out.stats, out.tiers, out.tierHead = b, b.text, b.all.t, "All"
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

-- { tab, head, stats, tiles = { id, icon, name, q, done, rule, stat, cmd } } of one tab.
-- stat: "Done 11-22", "3/5", "Soon" or "". A secret row shows only once earned.
-- The Collection tab adds the sounds of one page (pg): sounds = { key, token, i, q, done,
-- heard, star, text, name, rule, stat, gold }, page, pages, pageHead, have, all.
function ns.AchLines(tab, pg)
	tab = TAB_NAME[tab] and tab or "classic"
	local d = tab == "collection" and ns.DexNums and ns.DexNums() or nil
	local out = { tab = tab, head = ns.AchTabText(tab), tiles = {} }
	if tab == "board" then return BoardOut(out) end
	if d then out.stats = ns.DexStatsText(d) else out.stats = ns.AchStatsText() end
	local okT, t = pcall(function() return ns.TiersMine and (ns.TiersMine()) end)
	if okT and t then out.tiers, out.tierHead = t, "Mine" end
	for _, row in ipairs(ns.ACH) do
		local t = ach.done[row.id]
		if row.tab == tab and (t or not row.secret) then
			local stat = ""
			if t then
				stat = "Done " .. date("%m-%d", t)
			elseif row.soon or d and DexSoon(row, d) then
				stat = "Soon"
			else
				local have, goal = Progress(row, d)
				if have then stat = have .. "/" .. goal end
			end
			out.tiles[#out.tiles + 1] = { id = row.id, icon = ns.AchIcon(row), name = row.name, q = row.q,
				done = t ~= nil, rule = row.rule, stat = stat, cmd = RewardOf(row.id), ord = #out.tiles + 1 }
		end
	end
	if d then
		local ps = d.pages
		local n = math.min(math.max(math.floor(tonumber(pg) or 1), 1), #ps)
		local p = ps[n]
		out.page, out.pages, out.have, out.all = n, #ps, d.have, d.all
		out.pageHead = ("%s %d/%d"):format(p.name, p.have, #p.tiles)
		out.sounds = {}
		for _, t in ipairs(p.tiles) do
			local e = d.heard[t.key]
			local num = "#" .. t.num
			if e then
				out.sounds[#out.sounds + 1] = { key = t.key, token = t.token, i = t.i, q = t.q, done = true, heard = true,
					star = e.own > 0, text = GREY .. num .. "|r " .. ns.AchColor(t.q) .. t.name .. "|r",
					name = num .. " " .. t.name, rule = ("Heard %d · Own %d"):format(e.n, e.own),
					stat = e.t > 0 and ("First " .. date("%m-%d", e.t)) or "", gold = "Click = play" }
			else
				out.sounds[#out.sounds + 1] = { key = t.key, q = t.q, done = false, heard = false, star = false,
					text = GREY .. num .. " ???|r", name = num .. " ???", rule = "Not heard yet", stat = "" }
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

-- ------------------------------------------------------------ window
-- Own frame (FULLSCREEN_DIALOG). Opened by the Rewards button (left click),
-- /wind ach and the Options button. Tabs: Classic, Social, Collection, Board. One tile per shown row:
-- big icon + quality ring, name under it; locked = grey icon, grey ring, grey name.
-- Earned tiles first, rarest first; then the locked ones in list order.
-- A toast click opens the row's tab with its tile glowing (AchShow): GLOW_S s, or until hovered.
-- Hover: own tip frame (name, rule, date or progress, reward). A tile click does
-- nothing (no emote). No scroll bar: width fixed, the height fits the rows and
-- grows down from the top. Movable, spot saved (SpokenWindDB.achpos = its top left).
-- No keys at all (gamepad play, nothing can eat a key): the X, the Rewards button
-- or combat closes it.
-- Collection tab: the 5 Collection rows as a strip of small tiles, then the sounds of
-- one page, 5 a row: "#12 Name" (quality color), dim "#12 ???" until heard, a star
-- once you rolled it yourself. A heard tile click plays it here (DexPlay, max 1/s).
-- Page arrows only when the pool has more than one page.
local TILE, CELL_W, CELL_H, COLS, GAP, PAD = 92, 112, 124, 5, 6, 14
local HEAD_H, STAT_H = 24, 18      -- title + tabs row, stats strip
local TAB_W, TIP_W, TIP_LINE = 98, 220, 14
local ROW_H, LIST_H, OWN_GAP, COL_GAP = 18, 20, 6, 20   -- Board tab: row, list head, gap over your row
local RANK_W, NUM_W, TIER_W = 24, 70, 220
local STILE, SCELL_H = 48, 80              -- Collection strip: small icon, cell height
local SND_H, SND_GAP, PAGE_H = 22, 4, 20   -- sound tile height, gap, page head
local WIN_W = 2 * PAD + COLS * CELL_W + (COLS - 1) * GAP
local COL_W = (WIN_W - 2 * PAD - COL_GAP) / 2
ns.ACH_WIN = { w = WIN_W, tile = TILE, cellW = CELL_W, cellH = CELL_H, cols = COLS, gap = GAP, pad = PAD,
	head = HEAD_H, stat = STAT_H, stile = STILE, scellH = SCELL_H, sndH = SND_H, sndGap = SND_GAP, pageH = PAGE_H,
	row = ROW_H, list = LIST_H, ownGap = OWN_GAP, colW = COL_W, colGap = COL_GAP }

local tip, stats, cur, page = nil, nil, "classic", 1
local tabs, tiles, strip, snd = {}, {}, {}, {}
local pageText, prev, nxt
local heads, brows, seenFs, seenHit, tierFs, tierHit, allHit = {}, { {}, {} }, nil, nil, nil, nil, nil
local GLOW_S, GLOW_P = 5, 1.2   -- toast click: the tile glows 5 s, one pulse per 1.2 s
local GLOW_TEX = "Interface\\Buttons\\UI-ActionButton-Border"
local glowId, glowT0

-- Window height for n tiles (statsOn: the stats strip shows).
function ns.AchWinH(n, statsOn)
	local rows = math.max(1, math.ceil(n / COLS))
	return PAD + HEAD_H + (statsOn and STAT_H or 0) + rows * CELL_H + (rows - 1) * GAP + PAD
end

-- Collection tab height: nStrip strip tiles, n sounds, pages (> 1 = the page head shows).
function ns.DexWinH(nStrip, n, pages)
	local rs, rows = math.max(1, math.ceil(nStrip / COLS)), math.max(1, math.ceil(n / COLS))
	return PAD + HEAD_H + STAT_H + rs * SCELL_H + (rs - 1) * GAP + GAP + ((pages or 1) > 1 and PAGE_H or 0)
		+ rows * SND_H + (rows - 1) * SND_GAP + PAD
end

-- Board tab height: rows per list (n1, n2) and whether your own row shows under it (o1, o2).
function ns.BoardWinH(n1, o1, n2, o2)
	local function H(n, o) return n * ROW_H + (o and (OWN_GAP + ROW_H) or 0) end
	return PAD + HEAD_H + STAT_H + LIST_H + math.max(H(n1, o1), H(n2, o2), ROW_H) + PAD
end

local function HideTip() if tip then tip:Hide() end end

local function ShowTip(cell)
	local l = cell.line
	if not l then return end
	if not tip then
		tip = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		tip:SetFrameStrata("TOOLTIP")
		tip:SetClampedToScreen(true)
		if tip.SetBackdrop then tip:SetBackdrop(BACKDROP_TOAST_12_12 or ns.TOAST_ART) end
		tip.lines = {}
	end
	local text = { (l.color or (l.done and ns.AchColor(l.q) or GREY)) .. l.name .. "|r" }
	if l.rule then text[#text + 1] = l.rule end
	if l.stat and l.stat ~= "" then text[#text + 1] = l.stat end
	for _, m in ipairs(l.more or {}) do text[#text + 1] = m end
	if l.cmd then text[#text + 1] = GOLD .. "Reward " .. l.cmd .. "|r"
	elseif l.gold then text[#text + 1] = GOLD .. l.gold .. "|r" end
	for k = #tip.lines + 1, math.max(4, #text) do
		local fs = tip:CreateFontString(nil, "ARTWORK", k == 1 and "GameFontNormal" or "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", tip, "TOPLEFT", 10, -8 - (k - 1) * TIP_LINE)
		fs:SetWidth(TIP_W - 20)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		tip.lines[k] = fs
	end
	for k, fs in ipairs(tip.lines) do
		fs:SetText(text[k] or "")
		if text[k] then fs:Show() else fs:Hide() end
	end
	tip:SetSize(TIP_W, 16 + #text * TIP_LINE)
	tip:ClearAllPoints()
	tip:SetPoint("TOPLEFT", cell, "TOPRIGHT", 4, 0)
	tip:Show()
end
ns.AchShowTip = ShowTip

local function StopGlow()
	glowId = nil
	for _, pool in ipairs({ tiles, strip }) do
		for _, c in ipairs(pool) do c.glow:Hide() end
	end
	if win then win:SetScript("OnUpdate", nil) end
end

-- Window OnUpdate while a tile glows: the pulse, on whichever tile (or strip tile) holds that row now.
local function GlowTick()
	local dt = GetTime() - glowT0
	if dt >= GLOW_S then StopGlow() return end
	local a = 0.4 + 0.6 * (0.5 + 0.5 * math.cos(2 * math.pi * dt / GLOW_P))
	for _, pool in ipairs({ tiles, strip }) do
		for _, c in ipairs(pool) do
			if c:IsShown() and c.line and c.line.id == glowId then c.glow:SetAlpha(a) c.glow:Show() else c.glow:Hide() end
		end
	end
end

local function TileEnter(c)
	if glowId and c.line and c.line.id == glowId then StopGlow() end
	ShowTip(c)
end

-- An achievement tile: icon + ring of size px, the name under it.
local function Tile(size)
	local c = CreateFrame("Frame", nil, win)
	c:SetSize(CELL_W, size + 32)
	c.cellH = size + 32
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(size, size)
	c.icon:SetPoint("TOP", c, "TOP", 0, 0)
	c.ring = c:CreateTexture(nil, "OVERLAY")
	c.ring:SetSize(size, size)
	c.ring:SetPoint("TOP", c, "TOP", 0, 0)
	c.name = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	c.name:SetPoint("TOP", c, "TOP", 0, -(size + 4))
	c.name:SetWidth(CELL_W)
	c.name:SetJustifyH("CENTER")
	c.name:SetWordWrap(true)
	if c.name.SetMaxLines then c.name:SetMaxLines(2) end
	c.glow = c:CreateTexture(nil, "OVERLAY")   -- toast click: a soft pulse in the quality color
	c.glow:SetTexture(GLOW_TEX)
	c.glow:SetBlendMode("ADD")
	c.glow:SetSize(size * 1.7, size * 1.7)
	c.glow:SetPoint("CENTER", c.icon, "CENTER", 0, 0)
	c.glow:Hide()
	c:EnableMouse(true)
	c:SetScript("OnEnter", TileEnter)
	c:SetScript("OnLeave", HideTip)
	return c
end

-- A sound tile: "#12 Name" on a faint plate, a star at the right end.
local function SoundTile()
	local c = CreateFrame("Frame", nil, win)
	c:SetSize(CELL_W, SND_H)
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints(c)
	c.text = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	c.text:SetPoint("LEFT", c, "LEFT", 4, 0)
	c.text:SetWidth(CELL_W - 22)
	c.text:SetJustifyH("LEFT")
	c.text:SetWordWrap(false)
	c.star = c:CreateTexture(nil, "OVERLAY")
	c.star:SetSize(12, 12)
	c.star:SetPoint("RIGHT", c, "RIGHT", -4, 0)
	c.star:SetTexture(ns.DEX_STAR)
	c:EnableMouse(true)
	c:SetScript("OnEnter", ShowTip)
	c:SetScript("OnLeave", HideTip)
	c:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.line and self.line.heard then ns.DexPlay(self.line) end
	end)
	return c
end

-- The 7 tier numbers in the tier colors, no words.
local function TierText(t)
	local p = {}
	for i = 1, #ns.B.TIER_HEX do p[i] = "|cff" .. ns.B.TIER_HEX[i] .. (t[i] or 0) .. "|r" end
	return table.concat(p, "  ")
end

local function TierTip(head, t)
	local more = {}
	for i, name in ipairs(ns.B.TIER_NAMES) do more[i] = "|cff" .. ns.B.TIER_HEX[i] .. name .. "|r " .. (t[i] or 0) end
	return { name = head, color = GOLD, more = more }
end

-- A Board row: rank (grey), name, number at the right. Hover = the tip.
local function BoardRow()
	local c = CreateFrame("Frame", nil, win)
	c:SetSize(COL_W, ROW_H)
	c.rank = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	c.rank:SetPoint("LEFT", c, "LEFT", 0, 0)
	c.rank:SetWidth(RANK_W)
	c.rank:SetJustifyH("RIGHT")
	c.name = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	c.name:SetPoint("LEFT", c, "LEFT", RANK_W + 6, 0)
	c.name:SetWidth(COL_W - RANK_W - 6 - NUM_W - 4)
	c.name:SetJustifyH("LEFT")
	c.name:SetWordWrap(false)
	c.num = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	c.num:SetPoint("RIGHT", c, "RIGHT", 0, 0)
	c.num:SetWidth(NUM_W)
	c.num:SetJustifyH("RIGHT")
	c:EnableMouse(true)
	c:SetScript("OnEnter", ShowTip)
	c:SetScript("OnLeave", HideTip)
	return c
end

local function HideBoard()
	for _, fs in ipairs(heads) do fs:Hide() end
	for _, pool in ipairs(brows) do for _, c in ipairs(pool) do c:Hide() end end
	if seenFs then seenFs:Hide() seenHit:Hide() allHit:Hide() end
end

-- Board tab: the 2 list heads, "Seen ?" at the right, the rows from top down. Returns the height.
local function DrawBoard(lines, top)
	local h = {}
	for k, col in ipairs(lines.cols) do
		local x = PAD + (k - 1) * (COL_W + COL_GAP)
		heads[k]:ClearAllPoints()
		heads[k]:SetPoint("TOPLEFT", win, "TOPLEFT", x, top - 2)
		heads[k]:SetText(col.head)
		heads[k]:Show()
		local list = {}
		for i, l in ipairs(col.rows) do list[i] = l end
		if col.own then list[#list + 1] = col.own end
		local pool, y = brows[k], top - LIST_H
		for i, l in ipairs(list) do
			if l == col.own then y = y - OWN_GAP end
			local c = pool[i] or BoardRow()
			pool[i] = c
			c.line = l
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", win, "TOPLEFT", x, y)
			c.rank:SetText(GREY .. l.rank .. "|r")
			c.name:SetText(l.color .. l.short .. "|r")
			c.num:SetText(tostring(l.num))
			c:Show()
			y = y - ROW_H
		end
		for i = #list + 1, #pool do pool[i]:Hide() end
		h[k] = { #col.rows, col.own ~= nil }
	end
	seenFs:ClearAllPoints()
	seenFs:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, top - 2)
	seenFs:SetText(lines.board.seen)
	seenFs:Show()
	seenHit.line = lines.seenTip
	seenHit:ClearAllPoints()
	seenHit:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, top)
	seenHit:Show()
	allHit.line = lines.allTip
	allHit:Show()
	return ns.BoardWinH(h[1][1], h[1][2], h[2][1], h[2][2])
end

-- Collection tab: the page head (only with more than one page) and the sounds from top down.
local function DrawSounds(lines, top)
	local multi = lines.pages > 1
	for _, f in ipairs({ prev, nxt }) do
		if multi then f:Show() else f:Hide() end
	end
	if multi then
		prev:ClearAllPoints()
		prev:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, top)
		nxt:ClearAllPoints()
		nxt:SetPoint("TOPLEFT", win, "TOPLEFT", WIN_W - PAD - 20, top)
		pageText:ClearAllPoints()
		pageText:SetPoint("TOP", win, "TOP", 0, top - 3)
		pageText:SetText(lines.pageHead)
		pageText:Show()
		top = top - PAGE_H
	else
		pageText:Hide()
	end
	for i, l in ipairs(lines.sounds) do
		local c = snd[i] or SoundTile()
		snd[i] = c
		c.line = l
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + ((i - 1) % COLS) * (CELL_W + GAP),
			top - math.floor((i - 1) / COLS) * (SND_H + SND_GAP))
		c.text:SetText(l.text)
		c.bg:SetColorTexture(1, 1, 1, l.heard and 0.08 or 0.03)
		if l.star then c.star:Show() else c.star:Hide() end
		c:Show()
	end
	for i = #lines.sounds + 1, #snd do snd[i]:Hide() end
end

Draw = function()
	local lines = ns.AchLines(cur, page)
	page = lines.page or page
	for k, key in ipairs(TABS) do
		local t = tabs[k]
		t.text:SetText((key == cur and GOLD or GREY) .. ns.AchTabText(key) .. "|r")
		if key == cur then t.line:Show() else t.line:Hide() end
	end
	stats:SetText(lines.stats or "")
	if lines.stats and lines.tiers and ns.B then
		tierFs:SetText(TierText(lines.tiers))
		tierFs:Show()
		tierHit.line = TierTip(lines.tierHead, lines.tiers)
		tierHit:Show()
	else
		tierFs:Hide()
		tierHit:Hide()
	end
	local top = -(PAD + HEAD_H + (lines.stats and STAT_H or 0))
	if lines.cols then
		for _, pool in ipairs({ tiles, strip, snd }) do for _, c in ipairs(pool) do c:Hide() end end
		pageText:Hide() prev:Hide() nxt:Hide()
		win:SetSize(WIN_W, DrawBoard(lines, top))
		return lines
	end
	HideBoard()
	local dex = lines.sounds ~= nil
	local pool, size = dex and strip or tiles, dex and STILE or TILE
	for _, c in ipairs(dex and tiles or strip) do c:Hide() end
	for i, l in ipairs(lines.tiles) do
		local c = pool[i] or Tile(size)
		pool[i] = c
		c.line = l
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + ((i - 1) % COLS) * (CELL_W + GAP),
			top - math.floor((i - 1) / COLS) * (c.cellH + GAP))
		c.icon:SetTexture(l.icon)
		c.icon:SetDesaturated(not l.done)
		ns.AchRingPaint(c.ring, l.q, l.done)
		c.name:SetText((l.done and ns.AchColor(l.q) or GREY) .. l.name .. "|r")
		c.glow:SetVertexColor(ns.AchRGB(l.q))
		if l.id == glowId then c.glow:Show() else c.glow:Hide() end
		c:Show()
	end
	for i = #lines.tiles + 1, #pool do pool[i]:Hide() end
	if dex then
		local rs = math.max(1, math.ceil(#lines.tiles / COLS))
		DrawSounds(lines, top - rs * SCELL_H - (rs - 1) * GAP - GAP)
		win:SetSize(WIN_W, ns.DexWinH(#lines.tiles, #lines.sounds, lines.pages))
	else
		for _, c in ipairs(snd) do c:Hide() end
		if pageText then pageText:Hide() prev:Hide() nxt:Hide() end
		win:SetSize(WIN_W, ns.AchWinH(#lines.tiles, lines.stats ~= nil))
	end
	return lines
end

-- "DEX show" when the Collection tab shows (open or a tab click).
local function ShowLog(lines)
	local b = lines.board
	if b then
		ns.Log(("BOARD show n=%d heard=%d listen=%d off=%d"):format(b.all.p, #b.heard, #b.listen, b.off and 1 or 0))
		ns.Log(("BOARD seen est=%s win=%d hits=%d"):format(b.est and tostring(b.est) or "?", b.win or 0, b.hits or 0))
	end
	if lines.sounds then
		ns.Log(("DEX show n=%d/%d page=%d/%d"):format(lines.have, lines.all, lines.page, lines.pages))
	end
end

local function PlaceWin()
	win:ClearAllPoints()
	local p = db.achpos
	if p then
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
	else
		win:SetPoint("TOP", UIParent, "TOP", 0, -120)
	end
end

local function Btn(parent, w, h)
	local b = CreateFrame("Frame", nil, parent)
	b:SetSize(w, h)
	b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
	b:EnableMouse(true)
	return b
end

local function Build()
	win = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	win:SetSize(WIN_W, ns.AchWinH(1, true))
	win:SetFrameStrata("FULLSCREEN_DIALOG")
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	if win.SetBackdrop then win:SetBackdrop(BACKDROP_TOAST_12_12 or ns.TOAST_ART) end
	win:EnableMouse(true)   -- a click on a gap does not fall through
	win:RegisterForDrag("LeftButton")
	win:Hide()
	local title = win:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -PAD)
	title:SetText("Achievements")
	for k, key in ipairs(TABS) do
		local t = Btn(win, TAB_W, HEAD_H - 4)
		t:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 150 + (k - 1) * (TAB_W + GAP), -PAD + 2)
		t.line = t:CreateTexture(nil, "ARTWORK")
		t.line:SetColorTexture(1, 0.82, 0, 0.9)
		t.line:SetSize(TAB_W - 8, 2)
		t.line:SetPoint("BOTTOM", t, "BOTTOM", 0, 0)
		t:SetScript("OnMouseUp", function(_, button)
			if button ~= "LeftButton" or cur == key then return end
			cur = key
			HideTip()
			ShowLog(Draw())
		end)
		tabs[k] = t
	end
	local close = Btn(win, 20, 20)
	close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -8)
	close.text:SetText("X")
	-- page arrows (Collection tab, only with more than one page): wrap around
	pageText = win:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	prev, nxt = Btn(win, 20, 20), Btn(win, 20, 20)
	prev.text:SetText("<")
	nxt.text:SetText(">")
	for _, b in ipairs({ { prev, -1 }, { nxt, 1 } }) do
		b[1]:SetScript("OnMouseUp", function(_, button)
			if button ~= "LeftButton" then return end
			local n = ns.DexPages and #ns.DexPages() or 1
			page = (page - 1 + b[2]) % n + 1
			HideTip()
			Draw()
		end)
		b[1]:Hide()
	end
	pageText:Hide()
	close:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then win:Hide() end end)
	win.close = close
	stats = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	stats:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(PAD + HEAD_H))
	stats:SetJustifyH("LEFT")
	-- tier numbers at the right end of the strip + hover spots (own frames, no keys)
	tierFs = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	tierFs:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -(PAD + HEAD_H))
	tierFs:SetJustifyH("RIGHT")
	local function Hit(w)
		local f = CreateFrame("Frame", nil, win)
		f:SetSize(w, STAT_H)
		f:EnableMouse(true)
		f:SetScript("OnEnter", ShowTip)
		f:SetScript("OnLeave", HideTip)
		f:Hide()
		return f
	end
	tierHit = Hit(TIER_W)
	tierHit:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -(PAD + HEAD_H))
	allHit = Hit(WIN_W - 2 * PAD - TIER_W - GAP)
	allHit:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(PAD + HEAD_H))
	seenHit = Hit(80)
	seenFs = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	seenFs:SetJustifyH("RIGHT")
	seenFs:Hide()
	for k = 1, 2 do
		heads[k] = win:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		heads[k]:SetJustifyH("LEFT")
		heads[k]:Hide()
	end
	win:SetScript("OnDragStart", function(self)
		if InCombat() then return end
		self:StartMoving()
	end)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local l, t = self:GetLeft(), self:GetTop()
		if l and t then db.achpos = { x = math.floor(l + 0.5), y = math.floor(t + 0.5) } end
		PlaceWin()
	end)
	-- Combat closes it (never in the way).
	win:RegisterEvent("PLAYER_REGEN_DISABLED")
	win:SetScript("OnEvent", function(self) self:Hide() end)
	win:SetScript("OnHide", function() HideTip() StopGlow() end)
end

-- Opens the window (tab: "classic" / "social" / "collection", else the last one). false in combat.
function ns.AchOpen(tab)
	if InCombat() or not ach then return false end
	if not win then Build() end
	if TAB_NAME[tab] then cur = tab end
	PlaceWin()
	local lines = Draw()
	win:Show()
	ns.Log(("ACH open tab=%s n=%d"):format(cur, #lines.tiles))
	ShowLog(lines)
	return true
end

-- Rewards button (left click): open, or close when it is open.
function ns.AchToggle()
	if win and win:IsShown() then win:Hide() return false end
	return ns.AchOpen()
end

-- Glows the tile of row id when the window shows it. true = a tile glows.
function ns.AchGlow(id)
	if not (win and win:IsShown()) then return false end
	StopGlow()
	for _, pool in ipairs({ tiles, strip }) do
		for _, c in ipairs(pool) do
			if c:IsShown() and c.line and c.line.id == id then
				glowId, glowT0 = id, GetTime()
				win:SetScript("OnUpdate", GlowTick)
				GlowTick()
				return true
			end
		end
	end
	return false
end

-- Toast click: the window on the row's tab, its tile glowing. Returns tab, glow.
-- In combat: no window, one short line (as /wind ach).
function ns.AchShow(id)
	local row = byId[id]
	local tab = row and row.tab or cur
	if not ns.AchOpen(tab) then
		ns.Say("ach: not in combat")
		return tab, false
	end
	return tab, ns.AchGlow(id)
end

function ns.AchFrames()
	return win, tabs, tiles, tip, stats, strip, snd, { text = pageText, prev = prev, nxt = nxt },
		{ rows = brows, heads = heads, seen = seenFs, seenHit = seenHit, tier = tierFs, tierHit = tierHit, allHit = allHit }
end

-- Dev only (/wind ach test [n]): shows a toast, earns nothing.
function ns.AchTest(n)
	local row = ns.ACH[tonumber(n) or 0] or ns.ACH[math.random(#ns.ACH)]
	local okCall, shown = pcall(ns.Toast, row)
	local toast = okCall and shown == true
	if not toast then ns.Say("|T" .. ns.AchIcon(row) .. ":16|t " .. ns.AchColor(row.q) .. row.name .. "|r") end
	ns.Log(("ACH test %s toast=%d"):format(row.id, toast and 1 or 0))
end
