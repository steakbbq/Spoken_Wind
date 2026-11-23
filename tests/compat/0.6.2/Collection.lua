-- Spoken Wind: the collection save (the Collection tab comes later). Every fart
-- your client PLAYS from the fart set counts: your own press (own), a group or
-- guild fart message (msg), anyone else's emote by seed (emote). Reward lines
-- never count (not a fart). Per account: SpokenWindDB.dex, key = the sound file
-- stem -> { n = times heard, t = first heard (time()), own = your own rolls }.
-- Sparse: a key only once heard. Tile numbers come from a manifest at draw time.
-- Log: one "DEX add" line per NEW key only.
local _, ns = ...

local db

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
end

-- Keys heard so far (the BOOT line).
function ns.DexCount()
	local n = 0
	for _ in pairs(db.dex) do n = n + 1 end
	return n
end
