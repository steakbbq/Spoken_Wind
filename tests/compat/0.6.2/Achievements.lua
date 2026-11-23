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
-- Window: own frame (see below). The Options page only has a button to it.
local _, ns = ...

local ICON = "Interface\\AddOns\\Spoken_Wind\\Media\\ach\\"
local RING = ICON .. "ring"   -- white frame ring, tinted per quality
-- WoW item quality: 5 legendary, 4 epic, 3 rare, 2 uncommon, 1 common, 0 poor (fallback colors)
local HEX = { [5] = "ff8000", [4] = "a335ee", [3] = "0070dd", [2] = "1eff00", [1] = "ffffff", [0] = "9d9d9d" }

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
}

local TABS = { "classic", "social" }
local TAB_NAME = { classic = "Classic", social = "Social" }
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
local win, Draw

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
local function Progress(row)
	local id = row.id
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
	local n, s = ns.AchDone(tab)
	return ("%s %d/%d"):format(TAB_NAME[tab], n, MAIN[tab] or 0) .. (s > 0 and (" +" .. s) or "")
end

-- Stats strip: nil when Heard.lua is not there.
function ns.AchStatsText()
	local s = ns.HeardNums and ns.HeardNums()
	if not s then return nil end
	return ("Farts %d · Heard %d · People %d · Legend %d"):format(s.own, s.heard, s.people, s.legend)
end

-- { tab, head, stats, tiles = { id, icon, name, q, done, rule, stat, cmd } } of one tab.
-- stat: "Done 11-22", "3/5", "Soon" or "". A secret row shows only once earned.
function ns.AchLines(tab)
	tab = TAB_NAME[tab] and tab or "classic"
	local out = { tab = tab, head = ns.AchTabText(tab), stats = ns.AchStatsText(), tiles = {} }
	for _, row in ipairs(ns.ACH) do
		local t = ach.done[row.id]
		if row.tab == tab and (t or not row.secret) then
			local stat = ""
			if t then
				stat = "Done " .. date("%m-%d", t)
			elseif row.soon then
				stat = "Soon"
			else
				local have, goal = Progress(row)
				if have then stat = have .. "/" .. goal end
			end
			out.tiles[#out.tiles + 1] = { id = row.id, icon = ns.AchIcon(row), name = row.name, q = row.q,
				done = t ~= nil, rule = row.rule, stat = stat, cmd = RewardOf(row.id) }
		end
	end
	return out
end

-- ------------------------------------------------------------ window
-- Own frame (FULLSCREEN_DIALOG). Opened by the Rewards button (left click),
-- /wind ach and the Options button. Tabs: Classic, Social. One tile per shown row:
-- big icon + quality ring, name under it; locked = grey icon, grey ring, grey name.
-- Hover: own tip frame (name, rule, date or progress, reward). A tile click does
-- nothing (no emote). No scroll bar: width fixed, the height fits the rows and
-- grows down from the top. Movable, spot saved (SpokenWindDB.achpos = its top left).
-- No keys at all (gamepad play, nothing can eat a key): the X, the Rewards button
-- or combat closes it.
local TILE, CELL_W, CELL_H, COLS, GAP, PAD = 92, 112, 124, 5, 6, 14
local HEAD_H, STAT_H = 24, 18      -- title + tabs row, stats strip
local TAB_W, TIP_W, TIP_LINE = 104, 220, 14
local WIN_W = 2 * PAD + COLS * CELL_W + (COLS - 1) * GAP
local GOLD, GREY = "|cffffd100", "|cff9d9d9d"
ns.ACH_WIN = { w = WIN_W, tile = TILE, cellW = CELL_W, cellH = CELL_H, cols = COLS, gap = GAP, pad = PAD,
	head = HEAD_H, stat = STAT_H }

local tip, stats, cur = nil, nil, "classic"
local tabs, tiles = {}, {}

-- Window height for n tiles (statsOn: the stats strip shows).
function ns.AchWinH(n, statsOn)
	local rows = math.max(1, math.ceil(n / COLS))
	return PAD + HEAD_H + (statsOn and STAT_H or 0) + rows * CELL_H + (rows - 1) * GAP + PAD
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
		for k = 1, 4 do
			local fs = tip:CreateFontString(nil, "ARTWORK", k == 1 and "GameFontNormal" or "GameFontHighlightSmall")
			fs:SetPoint("TOPLEFT", tip, "TOPLEFT", 10, -8 - (k - 1) * TIP_LINE)
			fs:SetWidth(TIP_W - 20)
			fs:SetJustifyH("LEFT")
			fs:SetWordWrap(false)
			tip.lines[k] = fs
		end
	end
	local text = { (l.done and ns.AchColor(l.q) or GREY) .. l.name .. "|r", l.rule }
	if l.stat ~= "" then text[#text + 1] = l.stat end
	if l.cmd then text[#text + 1] = GOLD .. "Reward " .. l.cmd .. "|r" end
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

local function Tile()
	local c = CreateFrame("Frame", nil, win)
	c:SetSize(CELL_W, CELL_H)
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(TILE, TILE)
	c.icon:SetPoint("TOP", c, "TOP", 0, 0)
	c.ring = c:CreateTexture(nil, "OVERLAY")
	c.ring:SetSize(TILE, TILE)
	c.ring:SetPoint("TOP", c, "TOP", 0, 0)
	c.name = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	c.name:SetPoint("TOP", c, "TOP", 0, -(TILE + 4))
	c.name:SetWidth(CELL_W)
	c.name:SetJustifyH("CENTER")
	c.name:SetWordWrap(true)
	if c.name.SetMaxLines then c.name:SetMaxLines(2) end
	c:EnableMouse(true)
	c:SetScript("OnEnter", ShowTip)
	c:SetScript("OnLeave", HideTip)
	return c
end

Draw = function()
	local lines = ns.AchLines(cur)
	for k, key in ipairs(TABS) do
		local t = tabs[k]
		t.text:SetText((key == cur and GOLD or GREY) .. ns.AchTabText(key) .. "|r")
		if key == cur then t.line:Show() else t.line:Hide() end
	end
	stats:SetText(lines.stats or "")
	local top = -(PAD + HEAD_H + (lines.stats and STAT_H or 0))
	for i, l in ipairs(lines.tiles) do
		local c = tiles[i] or Tile()
		tiles[i] = c
		c.line = l
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + ((i - 1) % COLS) * (CELL_W + GAP),
			top - math.floor((i - 1) / COLS) * (CELL_H + GAP))
		c.icon:SetTexture(l.icon)
		c.icon:SetDesaturated(not l.done)
		ns.AchRingPaint(c.ring, l.q, l.done)
		c.name:SetText((l.done and ns.AchColor(l.q) or GREY) .. l.name .. "|r")
		c:Show()
	end
	for i = #lines.tiles + 1, #tiles do tiles[i]:Hide() end
	win:SetSize(WIN_W, ns.AchWinH(#lines.tiles, lines.stats ~= nil))
	return lines
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
			Draw()
		end)
		tabs[k] = t
	end
	local close = Btn(win, 20, 20)
	close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -8)
	close.text:SetText("X")
	close:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then win:Hide() end end)
	win.close = close
	stats = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	stats:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(PAD + HEAD_H))
	stats:SetJustifyH("LEFT")
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
	win:SetScript("OnHide", HideTip)
end

-- Opens the window (tab: "classic" / "social", else the last one). false in combat.
function ns.AchOpen(tab)
	if InCombat() or not ach then return false end
	if not win then Build() end
	if TAB_NAME[tab] then cur = tab end
	PlaceWin()
	local lines = Draw()
	win:Show()
	ns.Log(("ACH open tab=%s n=%d"):format(cur, #lines.tiles))
	return true
end

-- Rewards button (left click): open, or close when it is open.
function ns.AchToggle()
	if win and win:IsShown() then win:Hide() return false end
	return ns.AchOpen()
end

function ns.AchFrames() return win, tabs, tiles, tip, stats end

-- Dev only (/wind ach test [n]): shows a toast, earns nothing.
function ns.AchTest(n)
	local row = ns.ACH[tonumber(n) or 0] or ns.ACH[math.random(#ns.ACH)]
	local okCall, shown = pcall(ns.Toast, row)
	local toast = okCall and shown == true
	if not toast then ns.Say("|T" .. ns.AchIcon(row) .. ":16|t " .. ns.AchColor(row.q) .. row.name .. "|r") end
	ns.Log(("ACH test %s toast=%d"):format(row.id, toast and 1 or 0))
end
