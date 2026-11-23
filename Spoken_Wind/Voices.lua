-- Spoken Wind: the race voices (0.7.0).
-- The 9 race packs + the Artifact pack (Packs\*.lua + Media\<pack>\*.ogg, made by the race-voices tools,
-- copied byte for byte) join the fart set AFTER the 14 old sounds: sound i = 14 + num, num = the
-- collection number #1-#1337. Old sound numbers (1-14) never change.
-- Voice = the race + body of a GUID (GetPlayerInfoByGUID). No voice (another race, no answer, a hidden
-- answer) = the old 14 (pool 0, the 0.6.x math, unchanged).
-- Pick (pool 1): the TIER first, from the seed hash, with the odds of the picking page (settings/odds v2):
--   Artifact 1 in 5000, the voice legend 1 in 500, Classic 1 in 200 (0.7.1), the rest by the tier weights
--   (poor 25, common 35, uncommon 22, rare 13, epic 5) of the tiers the voice has. Then the sound in the
--   tier, never the one before it in this step. Whole-number math only: every client gets the same sound.
-- Classic (0.7.1): the old 14 for every voice, each the same odds (1 in 14, as in 0.6.x). It goes on the
--   wire as pool 0 + the old number, so 0.6.x clients play the same sound.
-- Messages: F carries pool 1 + num. 0.6.2-0.6.6 drop a pool they do not have (no sound, no send, no error).
-- A pack that does not load (a hole in 1-1337) = no pool 1 at all: everyone plays the old 14.
local _, ns = ...

local BASE = #ns.EMOTES.FART.sounds   -- 14
ns.BASE_N = BASE

local PACKS = {   -- the order of the Collection pages; dir = the folder in Media\
	{ t = "SW1337_HUMAN", dir = "human", name = "Human" },
	{ t = "SW1337_DWARF", dir = "dwarf", name = "Dwarf" },
	{ t = "SW1337_NIGHTELF", dir = "nightelf", name = "Night Elf" },
	{ t = "SW1337_GNOME", dir = "gnome", name = "Gnome" },
	{ t = "SW1337_ORC", dir = "orc", name = "Orc" },
	{ t = "SW1337_SCOURGE", dir = "scourge", name = "Undead" },
	{ t = "SW1337_TAUREN", dir = "tauren", name = "Tauren" },
	{ t = "SW1337_TROLL", dir = "troll", name = "Troll" },
	{ t = "SW1337_SKYBORNE", dir = "skyborne", name = "Skyborne" },
	{ t = "SW1337_ARTIFACT", dir = "artifact", name = "Artifact", art = true },
}
local TIER = { poor = 1, common = 2, uncommon = 3, rare = 4, epic = 5, legendary = 6, artifact = 7 }
local ODDS = { scale = 100000, art = 20, legend = 200, classic = 500, w = { 25, 35, 22, 13, 5 } }
-- 20 = 1 in 5000, 200 = 1 in 500, 500 = 1 in 200 (of hash % 100000)
local SET_N = 1337
local MISS_MAX = 10   -- VOX miss lines per session
local M = 2147483647
local SEX = { [2] = "m", [3] = "f" }

-- voices: "Troll_m" -> { key, name, race, body, tiers = { [1..6] = { i, ... } }, all = { i, ... }, w }
-- art = { i, ... } (num order); slot[i] = the slot name of an Artifact sound; set = the pack sounds loaded
local VOX = { base = BASE, odds = ODDS, voices = {}, order = {}, art = {}, slot = {}, set = 0, ok = false, bad = 0 }
ns.VOX = VOX
local CLASSIC = {}   -- the Classic tier: the old 14 (sound i 1-14)
for i = 1, BASE do CLASSIC[i] = i end
VOX.classic = CLASSIC
local nMiss, missSeen = 0, {}

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Usable(v) return type(v) == "string" and v ~= "" and not Secret(v) end

local function Num(v) return type(v) == "number" and v == math.floor(v) and v or nil end

-- Reads the pack tables into the fart set. Returns the pack sounds added.
local function Build()
	local snd = ns.EMOTES.FART.sounds
	local byNum, n = {}, 0
	for _, p in ipairs(PACKS) do
		local T = ns[p.t]
		if type(T) == "table" and type(T.rows) == "table" and T.final ~= false then   -- final = false: not approved yet
			for _, r in ipairs(T.rows) do
				local num = type(r) == "table" and not r.pending and Num(r.num) or nil   -- pending: no file yet
				local tier = num and TIER[r.tier]
				if tier and num >= 1 and num <= SET_N and not byNum[num] and (tier == 7) == (p.art == true)
					and type(r.key) == "string" and r.key:match("^[%w_]+$") and type(r.name) == "string"
					and type(r.ms) == "number" and r.ms > 0
					and (p.art and type(r.slot) == "string" or Usable(r.race) and (r.body == "m" or r.body == "f")) then
					byNum[num] = { file = r.key, dir = p.dir, name = r.name, num = num, tier = tier, q = tier - 1,
						race = r.race, body = r.body, slot = p.art and r.slot or nil, shart = tier == 7 or nil, ms = r.ms,
						page = p }
					n = n + 1
				else
					VOX.bad = VOX.bad + 1
				end
			end
		end
		ns[p.t] = nil   -- the rows live on in the fart set; the families go
	end
	if n ~= SET_N then return 0 end   -- a hole: no pool 1, the old 14 only
	for num = 1, SET_N do
		local s = byNum[num]
		local i = BASE + num
		snd[i] = s
		if ns.LEN then ns.LEN[s.file] = s.ms end
		if s.tier == 7 then
			VOX.art[#VOX.art + 1] = i
			VOX.slot[i] = s.slot
		else
			local key = s.race .. "_" .. s.body
			local v = VOX.voices[key]
			if not v then
				v = { key = key, race = s.race, body = s.body, name = s.page.name .. " " .. s.body:upper(),
					tiers = {}, all = {}, page = s.page }
				VOX.voices[key] = v
				VOX.order[#VOX.order + 1] = v
			end
			v.all[#v.all + 1] = i
			local list = v.tiers[s.tier] or {}
			list[#list + 1] = i
			v.tiers[s.tier] = list
		end
		s.page = nil
	end
	for _, v in pairs(VOX.voices) do
		v.w = 0
		for t = 1, 5 do if v.tiers[t] then v.w = v.w + ODDS.w[t] end end
	end
	table.sort(VOX.order, function(a, b) return a.all[1] < b.all[1] end)
	return n
end

local t0 = debugprofilestop and debugprofilestop()
local okB, nB = pcall(Build)
VOX.ms = t0 and debugprofilestop and (debugprofilestop() - t0) or 0
if okB and nB == SET_N and #VOX.art == 5 then
	VOX.ok, VOX.set = true, nB
else
	VOX.err = not okB and tostring(nB):sub(1, 80) or nil
	local snd = ns.EMOTES.FART.sounds
	for i = #snd, BASE + 1, -1 do snd[i] = nil end   -- never half a set
	VOX.voices, VOX.order, VOX.art, VOX.slot = {}, {}, {}, {}
end

-- An Artifact sound (i): its slot name, else nil.
function ns.ArtSlot(i) return VOX.slot[i] end

-- The voice of a GUID or nil (no pool 1, no answer, a hidden answer, a race without a pack).
function ns.VoiceOf(guid)
	if not VOX.ok or not GetPlayerInfoByGUID or not Usable(guid) then return nil end
	local ok, _, _, _, race, sex = pcall(GetPlayerInfoByGUID, guid)
	if not ok or not Usable(race) or Secret(sex) then return nil end
	local v = VOX.voices[race .. "_" .. tostring(SEX[sex])]
	if not v and nMiss < MISS_MAX and not missSeen[race .. tostring(sex)] then   -- race tokens only, no names
		nMiss, missSeen[race .. tostring(sex)] = nMiss + 1, true
		if ns.SyncLog then ns.SyncLog(("VOX miss race=%s sex=%s"):format(race:sub(1, 20), tostring(sex))) end
	end
	return v
end

-- Sound (i) of voice v for the seed hash h; never `avoid` (the sound before it in this step).
function ns.VoicePick(v, h, avoid)
	local u = h % ODDS.scale
	local h2 = (h * 48271) % M
	local list
	if u < ODDS.art and #VOX.art > 0 then list = VOX.art
	elseif u < ODDS.art + ODDS.legend then list = v.tiers[6]
	elseif u < ODDS.art + ODDS.legend + ODDS.classic then list = CLASSIC end
	if list and #list == 1 and list[1] == avoid then list = nil end   -- the legend twice in a step: a normal tier
	if not list then
		local x, tier = h2 % v.w, nil
		for t = 1, 5 do
			if v.tiers[t] then
				if x < ODDS.w[t] then tier = t break end
				x = x - ODDS.w[t]
			end
		end
		list = v.tiers[tier]
		if #list == 1 and list[1] == avoid then   -- the next tier that has sounds (fixed order)
			for d = 1, 4 do
				local t2 = (tier - 1 + d) % 5 + 1
				if v.tiers[t2] then list = v.tiers[t2] break end
			end
		end
	end
	local h3 = (h2 * 48271) % M
	local n, pos = #list, nil
	for j = 1, n do if list[j] == avoid then pos = j break end end
	if pos and n > 1 then
		local j = h3 % (n - 1) + 1
		if j >= pos then j = j + 1 end
		return list[j]
	end
	return list[h3 % n + 1]
end

-- The old sounds of an emote (FART: the 14 before the race set; another emote: all of its row).
function ns.OldN(token)
	if token == "FART" then return BASE end
	local row = ns.EMOTES[token]
	return row and #row.sounds or 0
end

-- Pools on the wire: 0 = the old sounds (FART 1-14), 1 = the race set (FART only, snd = num 1-1337).
function ns.PoolSize(pool, token)
	if pool == 0 then return ns.OldN(token or "FART") end
	if pool == 1 and VOX.ok and (token or "FART") == "FART" then return SET_N end
	return nil
end

-- A message's (pool, snd) -> sound i here.
function ns.PoolIndex(pool, snd)
	return pool == 1 and BASE + snd or snd
end

-- Sound i -> (pool, snd) for a message.
function ns.PoolWire(i)
	if i > BASE then return 1, i - BASE end
	return 0, i
end

-- The Collection pages of the set: one per voice (74, Perfect Pitch), then Artifact (5).
function ns.VoxPages()
	local out = {}
	if not VOX.ok then return out end
	local snd = ns.EMOTES.FART.sounds
	local function Page(name, list, voice)
		local p = { name = name, voice = voice, set = true, tiles = {} }
		for k, i in ipairs(list) do
			local s = snd[i]
			p.tiles[k] = { key = s.file, num = s.num, name = s.name, q = s.q, token = "FART", i = i }
		end
		return p
	end
	for _, v in ipairs(VOX.order) do out[#out + 1] = Page(v.name, v.all, true) end
	out[#out + 1] = Page("Artifact", VOX.art, false)
	return out
end

-- BOOT: the set loaded, its build ms, own voice, bad rows.
function ns.VoxBoot()
	local own = UnitGUID and ns.VoiceOf(UnitGUID("player"))
	return ("set=%d vms=%d vox=%s vbad=%d%s"):format(VOX.set, math.floor((VOX.ms or 0) + 0.5), own and own.key or "-",
		VOX.bad, VOX.err and (" verr=" .. VOX.err:gsub("%s", "_")) or "")
end
