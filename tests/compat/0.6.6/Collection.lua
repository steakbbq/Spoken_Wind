-- Spoken Wind: the collection. Every fart your client PLAYS from the fart set
-- counts: your own press (own), a group or guild fart message (msg), anyone
-- else's emote by seed (emote). Reward lines never count (not a fart). Per
-- account: SpokenWindDB.dex, key = the sound file stem -> { n = times heard,
-- t = first heard (time()), own = your own rolls }. Sparse: a key only once heard.
-- Log: one "DEX add" line per NEW key only.
-- Pages are data (DexPages): today one page, the live fart set. The 1337 set adds
-- a manifest (one page per voice + Artifact) and DEX_ALIAS (old key -> new key),
-- so farts heard before it still count. The Collection tab draws from here
-- (Achievements.lua); a tile click plays the sound here only (DexPlay).
local _, ns = ...

local db
local lastPlay   -- GetTime() of the last tile click that played
local prevEnd, prevHandle   -- the preview that plays now: its end (GetTime()), its sound handle
local PLAY_GAP = 1   -- s between tile plays

ns.DEX_ALIAS = {}   -- old key -> its key in the pool (the 1337 set fills it)

local function Num(v) return type(v) == "number" and v >= 0 and v < math.huge and math.floor(v) or nil end

-- Core calls this at ADDON_LOADED: checks the save, drops what is not valid.
function ns.DexInit(saved)
	db = saved
	local d = {}
	if type(db.dex) == "table" then
		for k, e in pairs(db.dex) do
			local n = type(e) == "table" and Num(e.n)
			if type(k) == "string" and k:match("^[%w_]+$") and n and n >= 1 then
				d[k] = { n = n, t = Num(e.t) or 0, own = math.min(Num(e.own) or 0, n) }
			end
		end
	end
	db.dex = d
	lastPlay, prevEnd, prevHandle = nil, nil, nil
end

-- Core: a fart that PLAYED. i = its sound number, src = own | msg | emote.
function ns.DexAdd(token, i, src)
	local row = ns.EMOTES[token]
	local s = token == "FART" and row and row.sounds[i]
	if not s then return end
	local e = db.dex[s.file]
	if not e then
		e = { n = 0, t = time(), own = 0 }
		db.dex[s.file] = e
		ns.Log(("DEX add key=%s num=%d src=%s"):format(s.file, i, src))
	end
	e.n = e.n + 1
	if src == "own" then e.own = e.own + 1 end
	if ns.BoardTier then ns.BoardTier(token, i) end   -- this character's tier counts (tiered files only)
	if ns.AchDex then ns.AchDex() end   -- Collection rows: every play (a full old save earns too)
end

-- Keys heard so far (the BOOT line).
function ns.DexCount()
	local n = 0
	for _ in pairs(db.dex) do n = n + 1 end
	return n
end

-- The pages. A page: { name, voice = true for a race voice (Perfect Pitch),
-- tiles = { { key, num, name, q, token, i } } }. q = the tile's quality (tier).
function ns.DexPages()
	local p = { name = "Original", tiles = {} }
	for i, s in ipairs(ns.EMOTES.FART.sounds) do
		p.tiles[i] = { key = s.file, num = i, name = s.name, q = 1, token = "FART", i = i }
	end
	return { p }
end

-- key -> { n, own, t } heard so far; old keys added onto their pool key.
local function Have()
	local h = {}
	for k, e in pairs(db.dex) do
		local key = ns.DEX_ALIAS[k] or k
		local m = h[key]
		if m then
			m.n, m.own = m.n + e.n, m.own + e.own
			if e.t > 0 and (m.t == 0 or e.t < m.t) then m.t = e.t end
		else
			h[key] = { n = e.n, own = e.own, t = e.t }
		end
	end
	return h
end

-- { have, all, own, voice, full, best, bestAll, pages, heard }: pool sounds heard, pool size, sounds
-- with an own roll, a voice page exists, a voice page is full, the best voice page (heard, size).
-- Each page gets .have.
function ns.DexNums()
	local h, ps = Have(), ns.DexPages()
	local d = { have = 0, all = 0, own = 0, voice = false, full = false, best = 0, bestAll = 0, pages = ps, heard = h }
	for _, p in ipairs(ps) do
		local k = 0
		for _, t in ipairs(p.tiles) do
			local e = h[t.key]
			if e then
				k = k + 1
				if e.own > 0 then d.own = d.own + 1 end
			end
		end
		p.have = k
		d.have, d.all = d.have + k, d.all + #p.tiles
		if p.voice then
			d.voice = true
			if d.bestAll == 0 or k > d.best then d.best, d.bestAll = k, #p.tiles end
			if k == #p.tiles and k > 0 then d.full = true end
		end
	end
	return d
end

-- Collection tab top line: "Heard 9/14 · <star> Own 3".
ns.DEX_STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
function ns.DexStatsText(d)
	d = d or ns.DexNums()
	return ("Heard %d/%d · |T%s:0|t Own %d"):format(d.have, d.all, ns.DEX_STAR, d.own)
end

-- A tile click: plays a heard sound here only (no emote, no message, no count).
-- Max one per PLAY_GAP s. One preview at a time: a click while one plays is ignored
-- (DEX busy), or, when the client has StopSound, the old one stops (stop=1) and the new one plays.
-- Returns true when the game plays it.
function ns.DexPlay(tile)
	if not (tile and tile.token and tile.i) or (InCombatLockdown and InCombatLockdown()) then return false end
	local now = GetTime()
	if lastPlay and now - lastPlay < PLAY_GAP then return false end
	local stop = ""
	if prevEnd and now < prevEnd then   -- a preview still plays
		if not (StopSound and prevHandle) then
			ns.Log(("DEX busy key=%s left=%.1f"):format(tostring(tile.key), prevEnd - now))
			return false
		end
		pcall(StopSound, prevHandle)
		stop = " stop=1"
	end
	lastPlay = now
	local ok, _, handle = ns.Play(tile.token, tile.i)
	if ok then
		prevEnd, prevHandle = now + ns.SoundLen(tile.token, tile.i), handle
	else
		prevEnd, prevHandle = nil, nil
	end
	ns.Log(("DEX play key=%s ok=%d%s"):format(tile.key, ok and 1 or 0, stop))
	return ok
end
