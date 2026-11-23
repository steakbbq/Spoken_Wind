-- Spoken Wind: "Heard" replies + fart stats (0.6.2).
-- Reply: this client PLAYED the sound of someone else's fart and that fart's F
--   message came (first, or late after the seed played): ONE hidden addon reply
--   H:1:<farter GUID>:<n>:<own GUID> on the channel the F came on (WHISPER only
--   back to the test partner). The one message Spoken Wind sends without a key
--   press: never chat, never an emote, never from a loop. One per fart, max one
--   per GAP s. No F message, Sound Off, busy (one sound per person) or not played = no reply.
--   Later builds may add fields after the known ones: ignored (ns.MsgExtra).
--   0.6.4: H carries the replier's per-character numbers (Board.lua), like F.
--   (CHAT_MSG_ADDON has no sender GUID, so the reply carries its own: People.)
-- Count: unique repliers per fart (farter GUID + n) for WINDOW s; your own
--   reply never counts. The bar's tag (Bar.lua) for SHOW s: own fart "Heard by N"
--   (green from 1); someone else's: "<name> · Heard by N" once N >= 1 (your own fart
--   wins while it shows). The totals: the bar tip. Bar off = no tag (the totals still count).
-- Totals in SpokenWindDB.stats: own (own /fart presses), heard (replies to own
--   farts), best (most in one own fart), people (GUIDs that ever replied),
--   legend (own farts that rolled the legendary), legendHeard (others' legendary
--   farts this client played). Reward lines (/legend, /superfart) never count.
-- Logs (sync ring): HEARD send / skip / got / sum.
local _, ns = ...

local WINDOW = 3      -- s a fart collects replies
local SHOW = 5        -- s the "Heard N" line stays
local GAP = 1         -- s between two own replies
local KEEP = 64       -- farts tracked, replies remembered
local NMAX = 999      -- F message numbers 1..NMAX
local ICON = "Interface\\Common\\VoiceChat-Speaker"
local CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true, SAY = true }
ns.HEARD = { window = WINDOW, show = SHOW, gap = GAP, keep = KEEP, icon = ICON }

local db, lastReply, cur
local order, farts = {}, {}       -- tracked farts (oldest first); "guid:n" -> fart
local replied, rorder = {}, {}    -- "guid:n" -> GetTime() of our reply

local function Usable(v)
	return type(v) == "string" and v ~= "" and not (issecretvalue and issecretvalue(v))
end
local function Short(g) return Usable(g) and g:sub(-6) or "?" end
local function Me()
	local g = UnitGUID and UnitGUID("player")
	return Usable(g) and g or nil
end
local function Num(v) return type(v) == "number" and v >= 0 and v < math.huge and math.floor(v) or nil end
local function Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end
local function SLog(s) if ns.SyncLog then ns.SyncLog(s) end end

-- ------------------------------------------------------------ stats
-- Core calls this at ADDON_LOADED, after the fart log. Old saves: own = the own
-- rows of the fart log; heard, best, people, legend, legendHeard start at 0.
function ns.HeardInit(saved)
	db = saved
	local s = type(db.stats) == "table" and db.stats or {}
	db.stats = s
	if not Num(s.own) then
		local n = 0
		for _, r in ipairs(type(db.farts) == "table" and db.farts or {}) do
			if type(r) == "table" and r.who == "you" then n = n + 1 end
		end
		s.own = n
	end
	s.own = Num(s.own)
	for _, k in ipairs({ "heard", "best", "legend", "legendHeard" }) do s[k] = Num(s[k]) or 0 end
	local p = {}
	if type(s.people) == "table" then
		for g, v in pairs(s.people) do if Usable(g) and v == true then p[g] = true end end
	end
	s.people = p
end

-- The legendary sound of a farter's pool. Race pools plug in here (each race its
-- own legend); the counters stay totals.
function ns.IsLegend(token, guid, i)
	local row = ns.EMOTES and ns.EMOTES[token]
	local s = row and row.sounds[i]
	return s ~= nil and (s.file == "13_legend" or s.tier == 6)   -- 6 = a voice legend (Voices.lua)
end

-- Core: your own fart line (one /fart press). snd = the roll (nil = none).
function ns.HeardSelf(token, guid, snd)
	local s = db.stats
	s.own = s.own + 1
	if ns.BoardOwn then ns.BoardOwn("f") end   -- this character's presses (F / H / S)
	if snd and ns.IsLegend(token, guid, snd) then s.legend = s.legend + 1 end
	if ns.HeardDraw then ns.HeardDraw() end   -- a shown "Farts N" stays true
	if ns.AchStats then ns.AchStats() end     -- Windbag
end

-- Core: a fart that played (after the fart log). Others' legendary = legendHeard.
function ns.HeardPlayed(token, i, guid, mine, ok)
	if mine or not ok then return end
	if ns.BoardOwn then ns.BoardOwn("l") end   -- listened: someone else's fart played here
	if ns.IsLegend(token, guid, i) then
		db.stats.legendHeard = db.stats.legendHeard + 1
		if ns.HeardDraw then ns.HeardDraw() end
	end
end

-- Your counts (achievements, the window's stats strip). people = how many.
function ns.HeardNums()
	local s = db.stats
	return { own = s.own, heard = s.heard, people = Count(s.people), best = s.best, legend = s.legend,
		legendHeard = s.legendHeard }
end

function ns.HeardBoot()
	local s = db.stats
	return ("own=%d heard=%d people=%d best=%d legend=%d legendHeard=%d reply=1"):format(s.own, s.heard,
		Count(s.people), s.best, s.legend, s.legendHeard)
end

-- The bar tip: the totals.
function ns.HeardTipRows()
	local s = db.stats
	return { { "Farts", tostring(s.own) }, { "Heard", tostring(s.heard) }, { "People", tostring(Count(s.people)) },
		{ "Best", tostring(s.best) }, { "Legend", tostring(s.legend) }, { "Legend heard", tostring(s.legendHeard) } }
end

-- ------------------------------------------------------------ show (the bar's tag)
-- The tag text and count of the fart shown now; nil = none.
function ns.HeardTag()
	if not cur then return nil end
	local txt = cur.own and ("Heard by %d"):format(cur.count) or ("%s · Heard by %d"):format(cur.who, cur.count)
	return txt, cur.count
end

local function Draw()
	if ns.BarDraw then ns.BarDraw() end
end
ns.HeardDraw = Draw

-- Own fart: at once (0 = base color). Someone else's: from its first reply (HeardGot).
local function Show(f)
	local now = GetTime()
	if cur ~= f then
		if cur and cur.own and not f.own and now - cur.shownAt < SHOW then return end   -- your own fart first
		cur, f.shownAt = f, now
		if C_Timer and C_Timer.After then
			C_Timer.After(SHOW, function() if cur == f then cur = nil Draw() end end)
		end
	end
	Draw()
end

-- ------------------------------------------------------------ count
local function Close(f)
	if f.closed then return end
	f.closed = true
	if f.own or f.count > 0 then SLog(("HEARD sum g=%s n=%d count=%d"):format(Short(f.g), f.n, f.count)) end
end

local function Track(guid, n, who, own)
	local id = guid .. ":" .. n
	local now = GetTime()
	local f = farts[id]
	if f and now - f.t <= WINDOW then return f end   -- the same fart
	f = { id = id, g = guid, n = n, who = who, own = own, t = now, from = {}, count = 0 }
	farts[id] = f
	order[#order + 1] = f
	while #order > KEEP do
		local old = table.remove(order, 1)
		if farts[old.id] == old then farts[old.id] = nil end
	end
	if C_Timer and C_Timer.After then C_Timer.After(WINDOW, function() Close(f) end) end
	return f
end

-- Sync: your own F message went out (sent = channels; nil = a test-mode timer sends it).
function ns.HeardOwnSent(guid, n, sent)
	if sent == 0 or not Usable(guid) or not tonumber(n) then return end
	Show(Track(guid, tonumber(n), "you", true))
end

-- Sync: someone else's F message (once per fart, any channel).
function ns.HeardTrack(guid, n, sender)
	if not Usable(guid) or guid == Me() or not tonumber(n) then return end
	local who = Usable(sender) and (sender:match("^[^%-]+") or sender) or "?"
	Track(guid, tonumber(n), who, false)
end

-- Sync: an H message. Bad ones are dropped without a word.
function ns.HeardGot(text, ch, sender)
	local g, n, from, rest = text:match("^H:1:([%w%-]+):(%d+):([%w%-]+)(.-)$")
	local okX, author, xf = ns.MsgExtra(rest)   -- Sync.lua: unknown extra fields are ignored
	n = tonumber(n)
	if not (g and n and n >= 1 and n <= NMAX) or not okX or g == from or from == Me()
		or not Usable(sender) then return end
	if ch == "WHISPER" then
		if not (ns.TestFrom and ns.TestFrom(sender, from)) then return end
	elseif not CHANNELS[ch] then
		return
	end
	if ns.BoardFirst and (xf[2] or xf[3]) then   -- the replier's own numbers (first hand)
		local okB, err = pcall(ns.BoardFirst, from, sender, xf[2], xf[3])
		if not okB then SLog("ERR board " .. tostring(err)) end
	end
	local f = farts[g .. ":" .. n]
	if not f or f.closed or GetTime() - f.t > WINDOW then return end
	if f.from[from] or f.from[sender] then return end   -- one per replier (PARTY + GUILD copies)
	f.from[from], f.from[sender] = true, true
	f.count = f.count + 1
	SLog(("HEARD got from=%s g=%s n=%d count=%d"):format(Short(from), Short(g), n, f.count))
	if f.own then
		local s = db.stats
		s.heard = s.heard + 1
		if ns.BoardOwn then ns.BoardOwn("h") end   -- this character's farts heard
		s.people[from] = true
		if f.count > s.best then s.best = f.count end
	end
	Show(f)
	if f.own then   -- your fart: Social achievements; the author's reply = Author's Note
		if author and ns.AchEarn then ns.AchEarn("authornote") end
		if ns.AchStats then ns.AchStats() end
	end
end

-- ------------------------------------------------------------ reply
-- Sync: someone else's fart PLAYED here and its F message is known. Returns true = sent.
function ns.HeardReply(guid, n, ch, sender, who)
	local me = Me()
	n = tonumber(n)
	if not (me and Usable(guid) and n) or guid == me then return false end
	local target
	if ch == "WHISPER" then
		if who ~= "pair" or not Usable(sender) then return false end
		target = sender
	elseif not CHANNELS[ch] then
		return false
	end
	local id = guid .. ":" .. n
	local now = GetTime()
	if replied[id] and now - replied[id] <= WINDOW then return false end   -- one per fart
	if lastReply and now - lastReply < GAP then
		SLog(("HEARD skip why=gap g=%s n=%d"):format(Short(guid), n))
		return false
	end
	lastReply = now
	replied[id] = now
	rorder[#rorder + 1] = id
	while #rorder > KEEP do replied[table.remove(rorder, 1)] = nil end
	local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
	local ok, res = false, nil
	if fn then ok, res = pcall(fn, ns.SYNC.prefix, ("H:1:%s:%d:%s%s"):format(guid, n, me,
		ns.MsgTail and ns.MsgTail() or ""), ch, target) end
	local good = ok and (res == nil or res == true or res == 0)
	SLog(("HEARD send ch=%s g=%s n=%d ok=%d"):format(ch, Short(guid), n, good and 1 or 0))
	return good
end
