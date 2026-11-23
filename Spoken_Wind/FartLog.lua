-- Spoken Wind: fart log. Every fart that got a sound, kept in SpokenWindDB.farts
-- (last KEEP rows) + totals today / all time in SpokenWindDB.stats. Names stay in
-- the local save. Page "Fart log" under Options -> AddOns -> Spoken Wind (Options.lua
-- draws it): totals + rows newest first, in pages.
local _, ns = ...

local KEEP = 200   -- rows kept in the save

local db

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
	if ns.FartLogRedraw then ns.FartLogRedraw() end
end

-- { today, all }: today = 0 on a new day (until the first fart of the day).
function ns.FartLogStats()
	local s = db.stats
	return { today = s.day == Today() and s.today or 0, all = s.all }
end

-- The voice of a sound: "Orig" (the old 14), "Shartifact", or the race voice ("Human M").
local function Voice(snd)
	if snd.slot or snd.tier == 7 then return "Shartifact" end
	local v = snd.race and snd.body and ns.VOX and ns.VOX.voices[snd.race .. "_" .. snd.body]
	if v then return v.name end
	return "Orig"
end

-- The page rows, newest fart first: { when, who, me, num, name, q, voice }.
-- when: "21:04" today, "11-20 21:04" on older days. name = nil: the sound is gone (num = the saved number).
function ns.FartLogRows()
	local out, farts, day = {}, db.farts, Today()
	for i = #farts, 1, -1 do
		local r = farts[i]
		local row = ns.EMOTES[r.e or "FART"]
		local snd = row and row.sounds[r.snd]
		out[#out + 1] = {
			when = date("%Y-%m-%d", r.t) == day and date("%H:%M", r.t) or date("%m-%d %H:%M", r.t),
			who = r.who, me = r.who == "you",
			num = snd and snd.num or r.snd, name = snd and snd.name or nil,
			q = snd and snd.q or 1, voice = snd and Voice(snd) or "",
		}
	end
	return out
end
