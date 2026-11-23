-- Spoken Wind: achievements. One table, rarest first (= icon sheet order = page
-- order). Rows are data: rename or cut a row here, nothing else changes.
-- Earn = a toast (Toast.lua, own frame) + one log line "ACH <id> toast=1".
-- Dates and progress live in SpokenWindDB.ach only: names and GUIDs never leave
-- the local save. Core feeds two calls: AchSeen (every /fart, before the
-- cooldown: Machine Gun counts blocked ones) and AchPlayed (each fart that played).
-- Secret rows (secret = true) hide on the page until earned and do not count in
-- "Done N/15". The one secret row: the dev Test gives it (Core checks the dev flag).
local _, ns = ...

local ICON = "Interface\\AddOns\\Spoken_Wind\\Media\\ach\\"
-- WoW item quality: 5 legendary, 4 epic, 3 rare, 2 uncommon, 1 common (fallback colors)
local HEX = { [5] = "ff8000", [4] = "a335ee", [3] = "0070dd", [2] = "1eff00", [1] = "ffffff" }

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
}

local byId, MAIN = {}, 0
for _, row in ipairs(ns.ACH) do
	byId[row.id] = row
	if not row.secret then MAIN = MAIN + 1 end
end

local GAS, THOUSAND = 100, 1000   -- farts (SpokenWindDB.stats.all)
local PEOPLE = 10                 -- Pen Pals
local CROP_N, CROP_S = 5, 60      -- Crop Duster: people, seconds
local DOUBLE_S = 1                -- Double Trouble: two people under 1 s apart
local CALL_S = 5                  -- Call and Response
local GUN_N, GUN_S = 10, 10       -- Machine Gun: /fart, seconds
local NIGHT_END = 4               -- Night Shift: hour 0 to 3
local RECENT_MAX, PRUNE_AT = 32, 32

local db, ach, page
local lastSelf                -- GetTime() of your last /fart (session only)
local recent = {}             -- others' farts in the last 60 s: { key, t }
local burst, nBurst = {}, 0   -- key -> GetTime() of the last 10 /fart

local function Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

function ns.AchIcon(row) return row.icon or ICON .. row.id end
function ns.AchRow(id) return byId[id] end
function ns.AchHas(id) return ach ~= nil and ach.done[id] ~= nil end

-- "|cffRRGGBB" of a quality: the game's own color, else the fallback.
function ns.AchColor(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	local hex = type(c) == "table" and c.hex
	if type(hex) == "string" and hex:match("^|c%x%x%x%x%x%x%x%x$") then return hex end
	return "|cff" .. (HEX[q] or "ffffff")
end

-- Rows done: the main ones, then the secret ones.
function ns.AchDone()
	local n, s = 0, 0
	for id in pairs(ach and ach.done or {}) do
		if byId[id].secret then s = s + 1 else n = n + 1 end
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
	ach = { done = done, heard = heard, people = people }
	db.ach = ach
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
	if page and page:IsVisible() then ns.AchDraw() end
	if ns.RewardRefresh then ns.RewardRefresh() end
end
ns.AchEarn = Earn   -- the dev folder's "fire" uses the same path as a real earn

-- Dev folder: read SpokenWindDB.ach again after it changed it (checks it,
-- redraws the page and the rewards).
function ns.AchReload()
	ns.AchInit(db)
	if page and page:IsVisible() then ns.AchDraw() end
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

-- ------------------------------------------------------------ page
-- "Achievements" under Options -> AddOns -> Spoken Wind: "Done N/15" (+N once a
-- secret row is earned), then one row each: icon (grey = locked), name in its
-- quality color, rule, date or progress. A secret row shows only once earned.
-- Layout: the page size is read on each draw (the game sizes canvas pages), then
-- the biggest icon and fewest columns that fit with no scroll bar. Size unknown:
-- 620x480 (smaller than the game's canvas, so it fits there too).
local HEAD_Y, TOP, GAP, MARGIN = -40, -64, 4, 16   -- head y, first row y, px between rows, side margin
local TEXT_W = 224                     -- px right of the icon: name (>= 160) + date/progress
local STAT_W = 56                      -- px for the date or progress (right-aligned)
local SIZES = { 40, 36, 32, 28, 24 }   -- icon px: the biggest that fits wins
local W0, H0 = 620, 480

local function Progress(id)
	if id == "orchestra" then return Heard(), #ns.EMOTES.FART.sounds end
	if id == "gas" or id == "thousand" then
		local all = type(db.stats) == "table" and tonumber(db.stats.all) or 0
		local goal = id == "gas" and GAS or THOUSAND
		return math.min(all, goal), goal
	end
	if id == "penpals" then return Count(ach.people), PEOPLE end
end

-- { head = "Done N/15", { icon, name, rule, stat, done } per shown row }
function ns.AchLines()
	local n, s = ns.AchDone()
	local out = { head = ("Done %d/%d"):format(n, MAIN) .. (s > 0 and (" +" .. s) or "") }
	for _, row in ipairs(ns.ACH) do
		local t = ach.done[row.id]
		if t or not row.secret then
			local stat = "·"
			if t then
				stat = date("%m-%d", t)
			else
				local have, goal = Progress(row.id)
				if have then stat = have .. "/" .. goal end
			end
			out[#out + 1] = { icon = ns.AchIcon(row), name = ns.AchColor(row.q) .. row.name .. "|r", rule = row.rule,
				stat = stat, done = t ~= nil }
		end
	end
	return out
end

-- n rows on a w x h page: icon px, rows per column, column width.
function ns.AchLayout(n, w, h)
	for _, px in ipairs(SIZES) do
		for cols = 1, 3 do
			local per = math.ceil(n / cols)
			local colW = math.floor((w - 2 * MARGIN) / cols)
			if colW >= px + 8 + TEXT_W and -TOP + per * (px + GAP) <= h - 8 then return px, per, colW end
		end
	end
	return SIZES[#SIZES], math.ceil(n / 2), math.floor((w - 2 * MARGIN) / 2)
end

local head
local rows = {}

-- Writes the page. Objects are made on the first draw, then only updated.
-- Cell: icon | name ... date/progress (line 1), rule (line 2).
function ns.AchDraw()
	if not page then return end
	local lines = ns.AchLines()
	if not head then
		head = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		head:SetPoint("TOPLEFT", MARGIN, HEAD_Y)
	end
	head:SetText(lines.head)
	local w = page.GetWidth and page:GetWidth() or 0
	local h = page.GetHeight and page:GetHeight() or 0
	if not (w > 200 and h > 200) then w, h = W0, H0 end
	local px, per, colW = ns.AchLayout(#lines, w, h)
	local tw = colW - px - 16   -- text width right of the icon (8 px gap each side)
	for i, l in ipairs(lines) do
		local r = rows[i]
		if not r then
			r = { icon = page:CreateTexture(nil, "ARTWORK") }
			r.name = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			r.name:SetJustifyH("LEFT")
			r.name:SetWordWrap(false)
			r.rule = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			r.rule:SetJustifyH("LEFT")
			r.rule:SetWordWrap(true)
			r.stat = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
			r.stat:SetJustifyH("RIGHT")
			r.stat:SetWordWrap(false)
			rows[i] = r
		end
		local x = MARGIN + math.floor((i - 1) / per) * colW
		local y = TOP - ((i - 1) % per) * (px + GAP)
		local tx = x + px + 8
		r.icon:ClearAllPoints()
		r.icon:SetSize(px, px)
		r.icon:SetPoint("TOPLEFT", x, y)
		r.name:ClearAllPoints()
		r.name:SetPoint("TOPLEFT", tx, y - 2)
		r.name:SetWidth(tw - STAT_W)
		r.stat:ClearAllPoints()
		r.stat:SetPoint("TOPLEFT", tx + tw - STAT_W, y - 3)
		r.stat:SetWidth(STAT_W)
		r.rule:ClearAllPoints()
		r.rule:SetPoint("TOPLEFT", tx, y - 18)
		r.rule:SetWidth(tw)
		r.icon:SetTexture(l.icon)
		r.icon:SetDesaturated(not l.done)
		r.name:SetText(l.name)
		r.rule:SetText(l.rule)
		r.stat:SetText(l.stat)
	end
end

-- Options.lua hands over the page frame; it redraws each time it is shown.
function ns.AchBind(f)
	page = f
	f:SetScript("OnShow", ns.AchDraw)
	ns.AchDraw()
end

-- Dev only (/wind ach test [n]): shows a toast, earns nothing.
function ns.AchTest(n)
	local row = ns.ACH[tonumber(n) or 0] or ns.ACH[math.random(#ns.ACH)]
	local okCall, shown = pcall(ns.Toast, row)
	local toast = okCall and shown == true
	if not toast then ns.Say("|T" .. ns.AchIcon(row) .. ":16|t " .. ns.AchColor(row.q) .. row.name .. "|r") end
	ns.Log(("ACH test %s toast=%d"):format(row.id, toast and 1 or 0))
end
