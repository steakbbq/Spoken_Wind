-- Spoken Wind: the same fart for everyone.
-- A (seed, always): every client picks the same sound from the farter's GUID,
--   the server-clock step (10 s) and k = farts seen from that GUID in that
--   step (counted before off / self / cooldown). Works when the farter has no
--   addon. Never the same sound twice in a row inside a step.
-- B (message): your own /fart sends ONE hidden addon message (prefix SpWind)
--   with your pick to your group and guild (+ SAY in instances). Sent only
--   from the game's emote call (a post-hook on DoEmote / C_ChatInfo.PerformEmote,
--   so it runs in your own key press): never from a timer, never an emote.
-- Wait rule: message first = play it at once. Emote first from a group or
--   guild member who sent us SpWind before = wait up to db.wait ms, then the
--   seed. Anyone else (strangers, the other faction) = the seed at once.
--   A late message never plays a second sound.
-- Logs: SYNC / SEEN lines in SpokenWindDB.sync (own ring, the main log stays short).
-- Test mode (TestMode.lua, /wind pair): T messages go there; it may skip or delay
--   the own message and gets one record per heard fart (played or skipped).
-- Heard (Heard.lua): an H reply when someone else's fart PLAYED here and its F
--   message is known (by=msg, or a late F after the seed played). H messages go there.
local _, ns = ...

local PREFIX = "SpWind"
local STEP = 10        -- s per seed step
local HOLD = 3         -- s a message waits for its emote
local LATE = 1         -- s after an emote: its message counts as late
local SEND_GAP = 1     -- s between two own messages (addon-message budget)
local SYNC_MAX = 300   -- lines kept in SpokenWindDB.sync
local KEEP = 64        -- table size that starts a prune
local QMAX = 4         -- messages held per sender
ns.SYNC = { prefix = PREFIX, step = STEP, hold = HOLD, late = LATE, gap = SEND_GAP, max = SYNC_MAX }

local db
local chain = {}     -- token..guid -> { step, k, last }: seed chain per sender
local held = {}      -- token..guid -> { {snd, t, who}, ... }: messages before their emote
local waits = {}     -- token..guid -> rec: emote waiting for its message
local open = {}      -- token..guid -> rec: emote whose message may still come (late)
local known = {}     -- guid -> { party = t, guild = t, say = t, pair = t }: sent us SpWind
local seq = {}       -- guid -> last message number (one fart reaches us on 2-3 channels)
local seenX, nSeenX = {}, 0
local ownQ = {}      -- own picks sent, waiting for their echo
local raceFaction = {}
local lastHookT, lastHookTok, lastSendT, ownSeq = nil, nil, nil, 0
local sendState = {} -- channel -> "ok" | "bad" (logged on the first of each)
local sums = { msg = 0, seed = 0, late = 0, own = 0, rand = 0, waited = 0, sent = 0, bad = 0, xf = 0 }

local function Usable(v)
	return type(v) == "string" and v ~= "" and not (issecretvalue and issecretvalue(v))
end

local function SLog(s)
	local log = db.sync
	log[#log + 1] = date("%m-%d %H:%M:%S") .. " " .. s
	while #log > SYNC_MAX do table.remove(log, 1) end
end
ns.SyncLog = SLog

local function Ms(dt) return math.floor(dt * 1000 + 0.5) end
local function Short(guid) return Usable(guid) and guid:sub(-6) or "?" end

-- ------------------------------------------------------------ seed
-- 31-bit string hash: exact whole-number math, so every client gets the same number.
local M = 2147483647
local function Hash(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % M end
	if h == 0 then h = 1 end
	for _ = 1, 3 do h = (h * 48271) % M end
	return h
end
ns.SeedHash = Hash

-- Sound 1..n for (token, guid, step, k); never `avoid` (the one before it in this step).
function ns.SeedPick(token, guid, step, k, n, avoid)
	if n <= 1 then return 1 end
	local h = Hash(("%s:%s:%d:%d"):format(token, guid, step, k))
	if avoid and avoid >= 1 and avoid <= n then
		local i = h % (n - 1) + 1
		if i >= avoid then i = i + 1 end
		return i
	end
	return h % n + 1
end

local function Step()
	local t = GetServerTime and GetServerTime() or time()
	return math.floor(t / STEP)
end
ns.SyncStep = Step

-- Sound pool of a sender: the base set now (id 0). Race pools (a fixed, ordered
-- list, the same on every client) plug in here when they land.
function ns.PoolFor(token, guid)
	return 0, #ns.EMOTES[token].sounds
end

local function Prune(t, old)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	if n <= KEEP then return end
	for key, v in pairs(t) do if old(v) then t[key] = nil end end
end

-- One more fart from guid: the next seed pick. Returns snd, step, k.
local function Count(token, guid)
	local step = Step()
	local key = token .. guid
	local c = chain[key]
	local k, avoid = 0, nil
	if c and c.step == step then k, avoid = c.k + 1, c.last end
	local _, n = ns.PoolFor(token, guid)
	local snd = ns.SeedPick(token, guid, step, k, n, avoid)
	chain[key] = { step = step, k = k, last = snd }
	Prune(chain, function(v) return v.step < step - 1 end)
	return snd, step, k
end
ns.SyncCount = Count

-- ------------------------------------------------------------ faction
local OLD_RACES = { Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
	Draenei = "Alliance", Worgen = "Alliance", Orc = "Horde", Scourge = "Horde", Undead = "Horde",
	Tauren = "Horde", Troll = "Horde", BloodElf = "Horde", Goblin = "Horde" }

-- "Alliance" / "Horde" of a race file name, else nil. The game's own race table
-- first (it knows this client's extra races), then the old list.
local function FactionOf(race)
	if raceFaction[race] ~= nil then return raceFaction[race] or nil end
	local found
	local CI = C_CreatureInfo
	if CI and CI.GetRaceInfo and CI.GetFactionInfo then
		for id = 1, 100 do
			local ok, info = pcall(CI.GetRaceInfo, id)
			if ok and type(info) == "table" and info.clientFileString == race then
				local ok2, f = pcall(CI.GetFactionInfo, id)
				if ok2 and type(f) == "table" and (f.groupTag == "Alliance" or f.groupTag == "Horde") then found = f.groupTag end
				break
			end
		end
	end
	found = found or OLD_RACES[race]
	raceFaction[race] = found or false
	return found
end

-- true when the sender is the other faction (no addon messages can cross), + race.
local function OtherFaction(guid)
	if not (GetPlayerInfoByGUID and UnitFactionGroup) then return false end
	local ok, _, _, _, race = pcall(GetPlayerInfoByGUID, guid)
	if not ok or not Usable(race) then return false end
	local his, mine = FactionOf(race), UnitFactionGroup("player")
	return his ~= nil and Usable(mine) and his ~= mine, race
end

-- ------------------------------------------------------------ send (own /fart)
local function Channels()
	local out = {}
	if IsInRaid and IsInRaid() then out[#out + 1] = "RAID"
	elseif IsInGroup and IsInGroup() then out[#out + 1] = "PARTY" end
	if IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
	if IsInInstance and IsInInstance() then out[#out + 1] = "SAY" end
	return out
end

local function Send(msg)
	local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
	if not fn then return 0 end
	local n = 0
	local list = Channels()
	local tgt = ns.TestWhisper and ns.TestWhisper()   -- test mode: the partner, when not in my group
	if tgt then list[#list + 1] = "WHISPER" end
	for _, ch in ipairs(list) do
		local ok, res = pcall(fn, PREFIX, msg, ch, ch == "WHISPER" and tgt or nil)
		local good = ok and (res == nil or res == true or res == 0)
		if good then n = n + 1 sums.sent = sums.sent + 1 else sums.bad = sums.bad + 1 end
		local state = good and "ok" or "bad"
		if sendState[ch .. state] == nil then   -- first ok and first fail per channel
			sendState[ch .. state] = true
			SLog(("SYNC send ch=%s ok=%d res=%s"):format(ch, good and 1 or 0, tostring(res)))
		end
	end
	return n
end

-- A Heard.lua call: an error there never breaks the sound or the sync.
local function HeardCall(fn, ...)
	if not fn then return end
	local ok, err = pcall(fn, ...)
	if not ok then SLog("ERR heard " .. tostring(err)) end
end

-- Post-hook on the game's emote call: your own key press. One message per /fart.
local function OnOwnEmote(token)
	if not Usable(token) then return end
	token = token:upper()
	if not (ns.EMOTES and ns.EMOTES[token]) then return end
	local now = GetTime()
	if lastHookT == now and lastHookTok == token then return end   -- DoEmote + PerformEmote: one press
	lastHookT, lastHookTok = now, token
	local guid = UnitGUID and UnitGUID("player")
	if not Usable(guid) then return end
	local snd, step, k = Count(token, guid)
	local mode, delay
	if ns.TestOwnMode then mode, delay = ns.TestOwnMode() end   -- test mode: no message, or a late one
	local o = { token = token, snd = snd, t = now, step = step, k = k, sent = 0, mode = mode }
	ownQ[#ownQ + 1] = o
	while #ownQ > QMAX do table.remove(ownQ, 1) end
	if mode == "nomsg" then return end
	if lastSendT and now - lastSendT < SEND_GAP then o.mode = mode or "gap" return end
	lastSendT = now
	ownSeq = ownSeq % 999 + 1
	local pool = ns.PoolFor(token, guid)
	local msg = ("F:1:%s:%s:%d:%d:%d"):format(token, guid, snd, pool, ownSeq)
		.. (ns.Dev and ns.Dev() and ":a" or "")   -- the author (dev addon): Straight From the Source
	if delay and C_Timer and C_Timer.After then   -- still this key press's one message, only later
		o.sent = nil
		C_Timer.After(delay, function()
			o.sent = Send(msg)
			if ns.TestSent then ns.TestSent(o.trec, o.sent) end
		end)
		HeardCall(ns.HeardOwnSent, guid, ownSeq, nil)
		return
	end
	o.sent = Send(msg)
	HeardCall(ns.HeardOwnSent, guid, ownSeq, o.sent)
end
ns.SyncOwnEmote = OnOwnEmote

-- ------------------------------------------------------------ hear (emote line)
local function WhoOf(guid)
	local w = known[guid]
	if not w then return "stranger" end
	return w.party and "party" or w.guild and "guild" or w.pair and "pair" or "say"
end

local function MayWait(guid)
	local w = known[guid]
	if not w then return false end
	return (w.party ~= nil and IsInGroup ~= nil and IsInGroup()) or (w.guild ~= nil and IsInGuild ~= nil and IsInGuild())
		or (w.pair ~= nil and ns.TestPaired ~= nil and ns.TestPaired(guid))
end

local function Line(rec)
	local gap = rec.gap and ("%+dms"):format(Ms(rec.gap)) or "-"
	SLog(("SYNC by=%s why=%s gap=%s who=%s g=%s step=%s k=%s snd=%s seed=%s"):format(rec.by, rec.why or "-", gap,
		rec.who or "-", Short(rec.guid), tostring(rec.step), tostring(rec.k), tostring(rec.snd), tostring(rec.seed)))
end

-- Every matched emote, before off / self / cooldown (k counts them all).
-- Returns a record for SyncPlay. rec.snd = the sound to play (nil = no GUID: random).
function ns.SyncHeard(token, sender, guid, mine, now)
	local rec = { token = token, guid = guid, t = now, skip = true, ts = GetServerTime and GetServerTime() or time() }
	if not Usable(guid) then
		rec.by, rec.why = "rand", "noguid"
		return rec
	end
	local key = token .. guid
	rec.key = key
	if mine then
		while ownQ[1] and (now - ownQ[1].t > HOLD or ownQ[1].token ~= token) do table.remove(ownQ, 1) end
		local o = table.remove(ownQ, 1)
		if o then
			rec.snd, rec.seed, rec.step, rec.k, rec.by, rec.o = o.snd, o.snd, o.step, o.k, "own", o
		else   -- no hook ran (old client, or the hook is missing): the seed, like everyone else
			rec.seed, rec.step, rec.k = Count(token, guid)
			rec.snd, rec.by, rec.why = rec.seed, "seed", "nohook"
		end
		rec.who = "self"
		return rec
	end
	rec.seed, rec.step, rec.k = Count(token, guid)
	rec.snd = rec.seed
	rec.who = WhoOf(guid)
	local xf, race = OtherFaction(guid)
	if xf then
		rec.why = "xfaction"
		if not seenX[guid] and nSeenX < 200 then
			seenX[guid], nSeenX = true, nSeenX + 1
			SLog(("SEEN xfaction race=%s g=%s"):format(tostring(race), Short(guid)))
		end
	end
	-- a message that came first
	local q = held[key]
	while q and q[1] and now - q[1].t > HOLD do table.remove(q, 1) end
	local m = q and table.remove(q, 1)
	if m then
		rec.snd, rec.by, rec.gap, rec.who = m.snd, "msg", m.t - now, m.who
		rec.n, rec.ch, rec.from, rec.author = m.n, m.ch, m.sender, m.author
		return rec
	end
	rec.by = "seed"
	local wait = (db.wait or 0) / 1000
	if xf then   -- why = xfaction: no message can cross, never wait
	elseif not known[guid] then rec.why = "stranger"
	elseif wait <= 0 then rec.why = "nowait"
	elseif not MayWait(guid) then   -- left the group / guild, or seen only on SAY
		rec.why = (known[guid].party or known[guid].guild) and "left" or "say"
	elseif not (C_Timer and C_Timer.After) then rec.why = "notimer"
	else rec.wait = wait end
	open[key] = rec
	Prune(open, function(v) return now - v.t > LATE end)
	return rec
end

-- Test mode: one record per heard fart (played or skipped), once.
local function Done(rec)
	if rec.tested or not ns.TestRec then return end
	rec.tested = true
	local ok, err = pcall(ns.TestRec, rec)
	if not ok then SLog("ERR test " .. tostring(err)) end
end

local function Play(rec, cb)
	local ok, i, played = pcall(cb, rec.snd, rec.by)
	if ok and type(i) == "number" then rec.snd = i end
	if not ok then SLog("ERR sync play " .. tostring(i)) end
	rec.played = ok and played == true
	sums[rec.by] = (sums[rec.by] or 0) + 1
	Line(rec)
	Done(rec)
	if rec.by == "msg" and rec.played then   -- an H reply (Heard.lua checks the rest), In Sync, the author
		if rec.n then HeardCall(ns.HeardReply, rec.guid, rec.n, rec.ch, rec.from, rec.who) end
		HeardCall(ns.AchInSync, rec.who)
		if rec.author then HeardCall(ns.AchEarn, "source") end
	end
end

-- Core: off / self / cooldown stopped this emote (test mode still logs its pick).
function ns.SyncSkip(rec, why)
	rec.skipWhy = why
	Done(rec)
end

-- Test mode: the partner sent us SpWind (pairing): it may be waited for.
function ns.SyncKnow(guid, who)
	if not Usable(guid) then return end
	local w = known[guid] or {}
	w[who] = GetTime()
	known[guid] = w
end

-- Core: the cooldown let this emote through. cb(snd) plays + returns the sound played.
function ns.SyncPlay(rec, cb)
	rec.skip = false
	if not rec.wait then return Play(rec, cb) end
	rec.cb = cb
	waits[rec.key] = rec
	sums.waited = sums.waited + 1
	C_Timer.After(rec.wait, function()
		if waits[rec.key] ~= rec then return end   -- its message came
		waits[rec.key] = nil
		rec.why, rec.gap = "timeout", nil
		Play(rec, rec.cb)
	end)
end

-- ------------------------------------------------------------ hear (addon message)
local WHO = { PARTY = "party", RAID = "party", INSTANCE_CHAT = "party", GUILD = "guild", SAY = "say" }

function ns.SyncMessage(prefix, text, channel, sender)
	if prefix ~= PREFIX or not Usable(text) then return end
	if text:sub(1, 4) == "H:1:" then   -- a Heard reply
		HeardCall(ns.HeardGot, text, channel, sender)
		return
	end
	if text:sub(1, 4) == "T:1:" then   -- test mode (only from the paired partner)
		if ns.TestMessage then ns.TestMessage(text, channel, sender) end
		return
	end
	local token, guid, snd, pool, n, a = text:match("^F:1:(%u+):([%w%-]+):(%d+):(%d+):(%d+)(.-)$")
	if not token or (a ~= "" and a ~= ":a") or not (ns.EMOTES and ns.EMOTES[token]) then return end
	local author = a == ":a"   -- the author's fart (dev addon flag)
	if UnitGUID and guid == UnitGUID("player") then return end   -- own echo
	local who = WHO[channel]
	if not who and channel == "WHISPER" and ns.TestFrom and ns.TestFrom(sender, guid) then who = "pair" end
	if not who then return end
	snd, pool, n = tonumber(snd), tonumber(pool), tonumber(n)
	local myPool, size = ns.PoolFor(token, guid)
	if pool ~= myPool or snd < 1 or snd > size then return end   -- a pool this build does not have: seed
	local now = GetTime()
	local w = known[guid] or {}
	w[who] = now
	known[guid] = w
	Prune(known, function(v) return now - math.max(v.party or 0, v.guild or 0, v.say or 0, v.pair or 0) > 3600 end)
	local s = seq[guid]
	if s and s.n == n and now - s.t <= HOLD then return end   -- the same fart on a second channel
	seq[guid] = { n = n, t = now }
	Prune(seq, function(v) return now - v.t > HOLD end)
	HeardCall(ns.HeardTrack, guid, n, sender)
	local key = token .. guid
	local rec = waits[key]
	if rec then   -- its emote waits: play this one now
		waits[key] = nil
		rec.snd, rec.by, rec.gap, rec.who, rec.why = snd, "msg", now - rec.t, who, nil
		rec.n, rec.ch, rec.from, rec.author = n, channel, sender, author
		open[key] = nil
		return Play(rec, rec.cb)
	end
	rec = open[key]
	if rec and now - rec.t <= LATE then   -- the seed played (or the emote was skipped): never twice
		open[key] = nil
		if not rec.skip then
			sums.late = sums.late + 1
			SLog(("SYNC by=late gap=%+dms who=%s g=%s snd=%d seed=%s match=%d"):format(Ms(now - rec.t), who,
				Short(guid), snd, tostring(rec.snd), snd == rec.snd and 1 or 0))
			if rec.played then   -- the seed played: still heard
				HeardCall(ns.HeardReply, guid, n, channel, sender, who)
				if author then HeardCall(ns.AchEarn, "source") end
			end
		end
		if rec.trec and ns.TestLate then pcall(ns.TestLate, rec.trec, snd, now - rec.t) end
		return
	end
	local q = held[key] or {}
	while q[1] and now - q[1].t > HOLD do table.remove(q, 1) end
	q[#q + 1] = { snd = snd, t = now, who = who, n = n, ch = channel, sender = sender, author = author }
	while #q > QMAX do table.remove(q, 1) end
	held[key] = q
	Prune(held, function(v) return not v[1] or now - v[#v].t > HOLD end)
end

-- ------------------------------------------------------------ boot
-- ADDON_LOADED: the ring, the prefix, the two hooks. Returns prefix (1/0/-1), hooks.
function ns.SyncInit(saved)
	db = saved
	db.sync = type(db.sync) == "table" and db.sync or {}
	local prefix = -1
	local reg = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
	if reg then
		local ok, res = pcall(reg, PREFIX)
		prefix = (ok and res ~= false and (res == nil or res == true or res == 0)) and 1 or 0
	end
	local hooks = 0
	if hooksecurefunc then
		if type(DoEmote) == "function" and pcall(hooksecurefunc, "DoEmote", function(t) OnOwnEmote(t) end) then
			hooks = hooks + 1
		end
		if C_ChatInfo and type(C_ChatInfo.PerformEmote) == "function"
			and pcall(hooksecurefunc, C_ChatInfo, "PerformEmote", function(t) OnOwnEmote(t) end) then
			hooks = hooks + 1
		end
	end
	ns.syncPrefix, ns.syncHooks = prefix, hooks
	return prefix, hooks
end

-- PLAYER_LOGOUT: one SUM line in the sync ring.
function ns.SyncSum()
	local parts = {}
	for _, k in ipairs({ "msg", "seed", "late", "own", "rand", "waited", "sent", "bad" }) do
		parts[#parts + 1] = k .. "=" .. (sums[k] or 0)
	end
	parts[#parts + 1] = "xf=" .. nSeenX
	SLog("SYNC SUM " .. table.concat(parts, " "))
end
