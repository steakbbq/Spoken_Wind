-- Spoken Wind: fart log. Every fart that got a sound, kept in SpokenWindDB.farts
-- (last KEEP rows) + totals today / all time in SpokenWindDB.stats. Names stay in
-- the local save. Page "Fart log" under Options -> AddOns -> Spoken Wind: plain
-- text, newest first, no scroll bar: what fits, then "+N older".
local _, ns = ...

local KEEP = 200   -- rows kept in the save
local SHOW = 26    -- fart rows on the page at most (+ totals + "+N older" = 28 lines)
local LINE = 16    -- px per line
local TOP = -40    -- y of the first line (the title sits above)

local db, page
local strings = {}

local function Today() return date("%Y-%m-%d") end

local function GoodRow(r)
	return type(r) == "table" and type(r.t) == "number" and type(r.who) == "string" and type(r.snd) == "number"
end

-- Core calls this at ADDON_LOADED: checks the saved rows and totals.
function ns.FartLogInit(saved)
	db = saved
	local rows = {}
	if type(db.farts) == "table" then
		for _, r in ipairs(db.farts) do if GoodRow(r) then rows[#rows + 1] = r end end
	end
	while #rows > KEEP do table.remove(rows, 1) end
	db.farts = rows
	local s = type(db.stats) == "table" and db.stats or {}
	s.all = type(s.all) == "number" and s.all >= 0 and s.all or #rows
	s.today = type(s.today) == "number" and s.today or 0
	s.day = type(s.day) == "string" and s.day or ""
	db.stats = s
end

-- One fart that got a sound. emo: emote token, who: "you" or a name (no realm),
-- snd: sound number. Redraws the page when it is open.
function ns.FartLogAdd(emo, who, snd)
	local farts = db.farts
	farts[#farts + 1] = { t = time(), e = emo, who = who, snd = snd }
	while #farts > KEEP do table.remove(farts, 1) end
	local s, day = db.stats, Today()
	if s.day ~= day then s.day, s.today = day, 0 end
	s.all, s.today = s.all + 1, s.today + 1
	if page and page:IsVisible() then ns.FartLogDraw() end
end

-- { text, font } lines, newest fart first, at most max fart rows.
-- Today: "21:04 · Bob · #4 Trumpet"; older days: "11-20 21:04 · ...".
function ns.FartLogLines(max)
	local s, farts, day = db.stats, db.farts, Today()
	local out = { { ("Today %d · All %d"):format(s.day == day and s.today or 0, s.all), "GameFontNormal" } }
	local n = #farts
	local shown = math.min(n, max)
	for i = n, n - shown + 1, -1 do
		local r = farts[i]
		local row = ns.EMOTES[r.e or "FART"]
		local snd = row and row.sounds[r.snd]
		local when = date("%Y-%m-%d", r.t) == day and date("%H:%M", r.t) or date("%m-%d %H:%M", r.t)
		out[#out + 1] = { ("%s · %s · #%d %s%s"):format(when, r.who, r.snd, snd and snd.name or "?",
			r.race and (" · " .. r.race) or ""), "GameFontHighlight" }
	end
	if n == 0 then out[#out + 1] = { "None yet", "GameFontDisable" } end
	if n > shown then out[#out + 1] = { "+" .. (n - shown) .. " older", "GameFontDisable" } end
	return out
end

-- Fart rows that fit the page height (the game sizes canvas pages; unknown -> SHOW).
local function Fit()
	local h = page.GetHeight and page:GetHeight()
	if type(h) == "number" and h > 120 then
		return math.max(1, math.min(SHOW, math.floor((h + TOP) / LINE) - 2))
	end
	return SHOW
end

-- Writes the lines on the page, reusing its font strings (no new frames).
function ns.FartLogDraw()
	if not page then return end
	local lines = ns.FartLogLines(Fit())
	for i, l in ipairs(lines) do
		local fs = strings[i]
		if not fs then
			fs = page:CreateFontString(nil, "ARTWORK", l[2])
			fs:SetPoint("TOPLEFT", 16, TOP - (i - 1) * LINE)
			strings[i] = fs
		end
		fs:SetFontObject(l[2])
		fs:SetText(l[1])
		fs:Show()
	end
	for i = #lines + 1, #strings do
		strings[i]:SetText("")
		strings[i]:Hide()
	end
end

-- Options.lua hands over the page frame; it redraws each time it is shown.
function ns.FartLogBind(f)
	page = f
	f:SetScript("OnShow", ns.FartLogDraw)
	ns.FartLogDraw()
end
