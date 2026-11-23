-- Spoken Wind: test mode (0.6.1). Two players judge the same-fart sync together.
-- /wind pair [name]: pairs with ONE partner who runs it too (a name, the target,
--   or the one party member). Off by default, off at logout, /wind pair off or End.
-- Talks only to the partner: hidden addon messages (prefix SpWind, kind T) on
--   WHISPER, each under 255 bytes, results 1 message per second. Nothing other
--   players can see.
-- Never sends an emote: every fart is a player's own key press. Test mode only
--   changes this addon's own sync message (none, or sent 100 / 400 ms late) and
--   what it logs.
-- AUTO: seed check (50 fixed inputs -> one hash: "seed match" / "seed DIFF") and
--   clock check (each client's server-second tick + 3 pings -> offset + round trip).
-- GUIDED: 7 steps; the window shows the next one (the farter's client counts).
-- Send: both swap their per-fart records; both show one table (match N/M + why).
-- Everything is in SpokenWindDB.test (lines, records, table).
local _, ns = ...

local KIND = "T:1:"
local LONG = 250        -- max bytes of one addon message (the client cuts at 255)
local CHUNK = 200       -- bytes of records in one results message
local PACE = 1          -- s between two results messages
local PINGS = 3
local TICK_MAX = 2.5    -- s to see the server second change
local RETRY = 1.5       -- s: the partner had no tick yet, ping again (3 times max)
local MATCH_S = 2       -- s: the same fart on both clients
local REC_MAX = 200
local LINE_MAX = 300
local MISS_MAX = 40
local MAXL = 16         -- text lines in the window (never a scroll bar)
local W, LINE, PAD, BTN_W, BTN_H, GAP, TOP_Y = 300, 14, 10, 60, 20, 6, -150
local STAGES = {
	{ id = "1", side = 1, mode = "norm", goal = 5 },
	{ id = "2", side = 1, mode = "nomsg", goal = 5 },
	{ id = "3a", side = 2, mode = "norm", goal = 5 },
	{ id = "3b", side = 2, mode = "nomsg", goal = 5 },
	{ id = "4a", side = 1, mode = "+100ms", goal = 3, delay = 0.1 },
	{ id = "4b", side = 1, mode = "+400ms", goal = 3, delay = 0.4 },
	{ id = "5", side = 0, mode = "norm", goal = 3 },
}
ns.TEST = { stages = STAGES, pace = PACE, chunk = CHUNK, long = LONG, match = MATCH_S, pings = PINGS, w = W,
	maxl = MAXL, line = LINE, pad = PAD, btnh = BTN_H, top = TOP_Y }
local BY = { own = "o", msg = "m", seed = "s", rand = "r" }
local UNBY = { o = "own", m = "msg", s = "seed", r = "rand" }
local WHY = { "edge", "kdrift", "late", "lost", "hash" }

local db, T             -- T = db.test (saved)
local S                 -- this test's live state (not saved): tick, pings, queues
local win               -- the window (made on first use)
local Refresh, Stop

local function Fresh() return { pings = {}, nPing = 0, retry = 0, sent = {}, inb = {}, q = {} } end

local function Usable(v)
	return type(v) == "string" and v ~= "" and not (issecretvalue and issecretvalue(v))
end
local function Srv() return GetServerTime and GetServerTime() or time() end
local function Ms(dt) return math.floor(dt * 1000 + 0.5) end
local function G8(guid) return Usable(guid) and guid:sub(-8) or "?" end
local function Short(name) return Usable(name) and (name:match("^[^%-]+") or name) or "?" end

-- Same player? "Name" matches "Name-Realm"; case and spaces do not count.
local function SameName(a, b)
	if not (Usable(a) and Usable(b)) then return false end
	local na, ra = a:gsub("%s", ""):lower():match("^([^%-]+)%-?(.*)$")
	local nb, rb = b:gsub("%s", ""):lower():match("^([^%-]+)%-?(.*)$")
	return na ~= nil and na == nb and (ra == "" or rb == "" or ra == rb)
end
ns.TestSameName = SameName

local function MyFaction()
	local f = UnitFactionGroup and UnitFactionGroup("player")
	return Usable(f) and f or "?"
end

local function TLog(s)
	local l = T.lines
	l[#l + 1] = date("%m-%d %H:%M:%S") .. " " .. s
	while #l > LINE_MAX do table.remove(l, 1) end
end

-- One hidden addon message to the partner only (WHISPER). true = the client took it.
local function Raw(body)
	if not (T and T.on and Usable(T.partner)) then return false end
	local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
	if not fn then return false end
	local msg = KIND .. body
	if #msg > LONG then TLog("ERR long " .. #msg) return false end
	local ok, res = pcall(fn, ns.SYNC.prefix, msg, "WHISPER", T.partner)
	local good = ok and (res == nil or res == true or res == 0)
	if not good then
		T.bad = (T.bad or 0) + 1
		if T.bad == 1 then TLog("SEND fail res=" .. tostring(res)) end
	end
	return good
end

-- ------------------------------------------------------------ auto: seed
-- 50 fixed inputs -> one number. Same number on both clients = same seed math.
local function SeedSum()
	local n = #ns.EMOTES.FART.sounds
	local picks = {}
	for i = 1, 50 do
		local guid = ("Player-%d-%d"):format(1000 + i * 37, (i * 48271) % 2147483647)
		local avoid = i % 3 == 0 and (i % n + 1) or nil
		picks[i] = ns.SeedPick("FART", guid, 178000000 + i * 13, i % 5, n, avoid)
	end
	return ns.SeedHash(table.concat(picks, ",")), n
end
ns.TestSeedSum = SeedSum

-- ------------------------------------------------------------ auto: clock
-- Server time of this client in ms, under the second: GetTime() + the base found
-- at the moment GetServerTime() changed.
local function Est() return S.base and (GetTime() + S.base) * 1000 or nil end

local function Ping()
	if not (T.on and T.paired and S.base and S.nPing < PINGS) then return end
	S.nPing = S.nPing + 1
	local est = Est()
	S.pings[S.nPing] = { t = GetTime(), est = est }
	Raw(("PI:%d:%.0f"):format(S.nPing, est))
end

local function OnPong(i, est)
	local p = S.pings[i]
	if not p or p.done then return end
	p.done = true
	if est == "-" then   -- the partner has no tick yet
		S.pings[i], S.nPing, S.retry = nil, S.nPing - 1, S.retry + 1
		if S.retry <= 3 and C_Timer and C_Timer.After then
			local s = S
			C_Timer.After(RETRY, function() if S == s then Ping() end end)
		end
		return
	end
	local rtt = (GetTime() - p.t) * 1000
	local off = tonumber(est) - (p.est + rtt / 2)
	off, rtt = math.floor(off + 0.5), math.floor(rtt + 0.5)
	TLog(("CLOCK ping=%d off=%+dms rtt=%dms"):format(i, off, rtt))
	if not T.clock or rtt < T.clock.rtt then T.clock = { off = off, rtt = rtt } end
	Ping()
	Refresh()
end

local function TickStart()
	local s = S
	s.s0, s.t0, s.base = Srv(), GetTime(), nil
	win:SetScript("OnUpdate", function(self)
		if S ~= s then self:SetScript("OnUpdate", nil) return end
		local sv, t = Srv(), GetTime()
		if sv ~= s.s0 then
			s.base = sv - t
			self:SetScript("OnUpdate", nil)
			TLog("CLOCK tick ok")
			Ping()
		elseif t - s.t0 > TICK_MAX then
			s.base = false
			self:SetScript("OnUpdate", nil)
			TLog("CLOCK tick none")
			Refresh()
		end
	end)
end

-- ------------------------------------------------------------ pair
local function Hello(kind)
	local guid = UnitGUID and UnitGUID("player")
	if not Usable(guid) then return false end
	local seed, n = SeedSum()
	return Raw(("%s:%s:%s:%s:%d:%d:%.0f"):format(kind, guid, ns.VERSION or "?", MyFaction(), seed, n, T.id))
end

local function OnHello(kind, rest, sender)
	local guid, ver, fac, seed, n, id = rest:match("^([%w%-]+):([%w%.]+):([%a%?]+):(%d+):(%d+):(%d+)$")
	if not guid then return end
	local mine = MyFaction()
	if fac ~= "?" and mine ~= "?" and fac ~= mine then
		T.xf = true
		return Stop("xfaction", false)
	end
	local myGuid = UnitGUID and UnitGUID("player")
	if not Usable(myGuid) or guid == myGuid then return end
	local mySeed, myN = SeedSum()
	T.partner, T.pguid, T.pver = sender, guid, ver
	T.side = myGuid < guid and 1 or 2
	T.id = math.min(T.id, tonumber(id) or T.id)
	T.seed = (tonumber(seed) == mySeed and tonumber(n) == myN) and "match" or "DIFF"
	if ns.SyncKnow then ns.SyncKnow(guid, "pair") end
	local was = T.paired
	T.paired = true
	if not was then
		TLog(("PAIR ok side=%d seed=%s ver=%s pver=%s pg=%s"):format(T.side, T.seed, tostring(ns.VERSION), ver, G8(guid)))
	end
	if kind == "HI" then Hello("OK") end
	if not was then Ping() end
	Refresh()
end

local function UnitFull(u)
	if not UnitName then return nil end
	local n, r = UnitName(u)
	if not Usable(n) then return nil end
	return Usable(r) and (n .. "-" .. r) or n
end

-- Partner name + a unit for it (for the faction check), else nil.
local function Resolve(arg)
	if arg ~= "" then
		for _, u in ipairs({ "target", "party1", "party2", "party3", "party4" }) do
			local full = UnitFull(u)
			if full and SameName(full, arg) then return arg, u end
		end
		return arg, nil
	end
	if UnitIsPlayer and UnitIsPlayer("target") and not (UnitIsUnit and UnitIsUnit("target", "player")) then
		local full = UnitFull("target")
		if full then return full, "target" end
	end
	if GetNumGroupMembers and GetNumGroupMembers() == 2 and not (IsInRaid and IsInRaid()) then
		local full = UnitFull("party1")
		if full then return full, "party1" end
	end
	return nil
end

local function OtherSide(unit)
	if not (unit and UnitFactionGroup) then return false end
	local his, mine = UnitFactionGroup(unit), UnitFactionGroup("player")
	return Usable(his) and Usable(mine) and his ~= mine
end

local function InMyGroup(name)
	local n = GetNumGroupMembers and GetNumGroupMembers() or 0
	if n == 0 then return false end
	local raid = IsInRaid and IsInRaid()
	for i = 1, raid and n or n - 1 do
		local full = UnitFull((raid and "raid" or "party") .. i)
		if full and SameName(full, name) then return true end
	end
	return false
end

-- ------------------------------------------------------------ guided steps
local function Who(side)
	if side == 0 then return "stranger" end
	return side == T.side and "you" or Short(T.partner)
end

local function Label(st)
	local sg = STAGES[st]
	if not sg then return st == 0 and "-" or "after" end
	return sg.id .. " " .. Who(sg.side) .. (sg.mode ~= "norm" and (" " .. sg.mode) or "")
end

-- how: nil = the goal was reached, "s" = Skip.
local function SetStage(n, tell, how)
	if not T.on or n <= T.stage then return end
	T.stage, T.cnt = math.min(n, #STAGES + 1), 0
	TLog("STEP " .. (STAGES[T.stage] and STAGES[T.stage].id or "done") .. (how and (" " .. how) or ""))
	if tell then Raw("ST:" .. T.stage .. (how and (":" .. how) or "")) end
	Refresh()
end

-- Is r a fart of this step's farter? (side 0 = anyone but the two testers)
local function IsFarter(sg, r)
	if sg.side == 0 then return r.who ~= "self" and r.g ~= G8(T.pguid) end
	if sg.side == T.side then return r.who == "self" end
	return r.g == G8(T.pguid)
end

-- The farter's client counts its farts and moves both windows on.
local function Count(r)
	local sg = STAGES[T.stage]
	if not (sg and T.paired and IsFarter(sg, r)) then return end
	T.cnt = T.cnt + 1
	if T.cnt >= sg.goal and (sg.side == 0 or sg.side == T.side) then SetStage(T.stage + 1, true) end
end

-- ------------------------------------------------------------ hooks from Sync
-- Every heard FART (played or skipped) while test mode is on: one record + one line.
function ns.TestRec(rec)
	if not (T and T.on) or rec.token ~= "FART" then return end
	local o = rec.o
	local r = { st = T.paired and T.stage or 0, g = G8(rec.guid), ts = rec.ts or Srv(), step = rec.step or 0,
		k = rec.k or 0, snd = rec.snd or 0, by = rec.by, gap = rec.gap and Ms(rec.gap) or nil, who = rec.who,
		sent = o and o.sent or nil, mode = o and o.mode or nil, skip = rec.skipWhy }
	if o then o.trec = r end
	rec.trec = r
	local ow = S.owe   -- the farter's ST came before its last farts: they still belong to the old step
	local owed = ow and ow.n > 0 and GetTime() - ow.t <= MATCH_S and IsFarter(STAGES[ow.st], r)
	if owed then ow.n, r.st = ow.n - 1, ow.st end
	local recs = T.recs
	recs[#recs + 1] = r
	while #recs > REC_MAX do table.remove(recs, 1) end
	TLog(("TEST id=%.0f st=%s g=%s step=%d k=%d snd=%d by=%s gap=%s who=%s%s%s%s"):format(T.id,
		STAGES[r.st] and STAGES[r.st].id or tostring(r.st), r.g, r.step, r.k, r.snd, tostring(r.by),
		r.gap and ("%+dms"):format(r.gap) or "-", tostring(r.who), r.sent and (" sent=" .. r.sent) or "",
		r.mode and (" mode=" .. r.mode) or "", r.skip and (" skip=" .. r.skip) or ""))
	if not owed then Count(r) end
	Refresh()
end

-- A message after its seed played: noted on the record (never a second sound).
function ns.TestLate(r, snd, dt)
	if not (T and T.on) then return end
	r.late = snd
	TLog(("TEST late g=%s snd=%d seed=%d gap=%+dms match=%d"):format(r.g, snd, r.snd, Ms(dt), snd == r.snd and 1 or 0))
end

-- A delayed own message went out: its channel count on the record.
function ns.TestSent(r, n)
	if r then r.sent = n end
end

-- This client's own sync message in the current step: nil (normal), "nomsg", or a delay.
function ns.TestOwnMode()
	if not (T and T.on and T.paired) then return nil end
	local sg = STAGES[T.stage]
	if sg and sg.side == T.side and sg.mode ~= "norm" then return sg.mode, sg.delay end
	return nil
end

-- Own sync message also to the partner by WHISPER when not in my group.
function ns.TestWhisper()
	if not (T and T.on and T.paired and Usable(T.partner)) then return nil end
	if InMyGroup(T.partner) then return nil end
	return T.partner
end

function ns.TestPaired(guid) return T ~= nil and T.on and T.paired and guid == T.pguid or false end
function ns.TestFrom(sender, guid) return ns.TestPaired(guid) and SameName(sender, T.partner) end

-- ------------------------------------------------------------ results
local function Pack(r)
	return ("%d,%s,%d,%d,%d,%d,%s,%s,%s,%s,%s"):format(r.st, r.g, r.ts - T.id, r.step - math.floor(T.id / 10), r.k,
		r.snd, BY[r.by] or "?", r.gap or "", r.sent or "", r.late or "", r.skip and "1" or "")
end

local function Unpack(s)
	local st, g, ts, step, k, snd, by, gap, sent, late, skip =
		s:match("^(%d+),([^,]+),(%-?%d+),(%-?%d+),(%d+),(%d+),(.),(%-?%d*),(%d*),(%d*),(1?)$")
	if not st then return nil end
	return { st = tonumber(st), g = g, ts = tonumber(ts) + T.id, step = tonumber(step) + math.floor(T.id / 10),
		k = tonumber(k), snd = tonumber(snd), by = UNBY[by] or by, gap = tonumber(gap), sent = tonumber(sent),
		late = tonumber(late), skip = skip == "1" or nil }
end
ns.TestPack, ns.TestUnpack = Pack, Unpack

local function Chunks(round)
	local out, cur, len = {}, {}, 0
	for _, r in ipairs(T.recs) do
		if r.g ~= "?" then
			local p = Pack(r)
			if len + #p + 1 > CHUNK and #cur > 0 then out[#out + 1] = table.concat(cur, ";") cur, len = {}, 0 end
			cur[#cur + 1] = p
			len = len + #p + 1
		end
	end
	if #cur > 0 or #out == 0 then out[#out + 1] = table.concat(cur, ";") end
	for i, body in ipairs(out) do out[i] = ("RS:%d:%d:%d:%s"):format(round, i, #out, body) end
	return out
end

-- One message now, the next one PACE s later (under the addon-message limit).
local function Pump(s)
	if S ~= s or not (T.on and T.paired) then s.busy = false return end
	local body = table.remove(s.q, 1)
	if not body then s.busy = false return end
	Raw(body)
	if s.q[1] and C_Timer and C_Timer.After then
		s.busy = true
		C_Timer.After(PACE, function() Pump(s) end)
	else
		s.busy, s.q = false, {}
	end
	Refresh()
end

local function SendResults(round)
	if not (T.on and T.paired) then return false end
	round = round or (T.round or 0) + 1
	T.round = math.max(T.round or 0, round)
	S.sent[round] = true
	local q = Chunks(round)
	for _, b in ipairs(q) do S.q[#S.q + 1] = b end
	TLog(("SEND round=%d msgs=%d recs=%d"):format(round, #q, #T.recs))
	if not S.busy then Pump(S) end
	return true
end

-- Why two clients picked different sounds for one fart.
local function Reason(a, b)
	local fa, fb = a.by == "own" or a.by == "msg", b.by == "own" or b.by == "msg"
	if fa ~= fb then   -- one used the farter's pick, one its own seed
		local seedSide, farSide = fa and b or a, fa and a or b
		if seedSide.late then return "late" end
		if farSide.by == "msg" or (farSide.sent or 0) > 0 then return "lost" end
	end
	if a.step ~= b.step then return "edge" end
	if a.k ~= b.k then return "kdrift" end
	return "hash"
end

-- A = side 1 (lower GUID), B = side 2: the same table on both clients.
-- Pairs one fart per GUID in order (inside MATCH_S); the rest = heard by one side.
function ns.TestCompare(A, B)
	local byG, gs = {}, {}
	for side, list in ipairs({ A, B }) do
		for _, r in ipairs(list) do
			local e = byG[r.g]
			if not e then e = { {}, {} } byG[r.g] = e gs[#gs + 1] = r.g end
			e[side][#e[side] + 1] = r
		end
	end
	table.sort(gs)
	local res = { n = 0, m = 0, one = 0, rows = {}, misses = {} }
	local function Row(st)
		local w = res.rows[st]
		if not w then w = { n = 0, m = 0, why = {} } res.rows[st] = w end
		return w
	end
	for _, g in ipairs(gs) do
		local la, lb = byG[g][1], byG[g][2]
		local i, j = 1, 1
		while la[i] or lb[j] do
			local a, b = la[i], lb[j]
			if a and b and math.abs(a.ts - b.ts) <= MATCH_S then
				local st = a.by == "own" and a.st or b.by == "own" and b.st or math.min(a.st, b.st)
				local w = Row(st)
				w.m, res.m = w.m + 1, res.m + 1
				if a.snd == b.snd then
					w.n, res.n = w.n + 1, res.n + 1
				else
					local why = Reason(a, b)
					w.why[why] = (w.why[why] or 0) + 1
					if #res.misses < MISS_MAX then
						res.misses[#res.misses + 1] = ("st=%s g=%s snd=%d/%d step=%d/%d k=%d/%d by=%s/%s why=%s"):format(
							STAGES[st] and STAGES[st].id or tostring(st), g, a.snd, b.snd, a.step, b.step, a.k, b.k,
							tostring(a.by), tostring(b.by), why)
					end
				end
				for _, r in ipairs({ a, b }) do
					if r.by == "msg" and r.gap and (not res.gap or r.gap > res.gap) then res.gap = r.gap end
				end
				i, j = i + 1, j + 1
			elseif a and (not b or a.ts < b.ts) then
				res.one, i = res.one + 1, i + 1
			else
				res.one, j = res.one + 1, j + 1
			end
		end
	end
	return res
end

local function WhyText(why)
	local parts = {}
	for _, k in ipairs(WHY) do
		if why[k] then parts[#parts + 1] = k .. " " .. why[k] end
	end
	return #parts > 0 and (" · " .. table.concat(parts, " · ")) or ""
end

local function Compute()
	local mine = {}
	for _, r in ipairs(T.recs) do
		if r.g ~= "?" then mine[#mine + 1] = Unpack(Pack(r)) end   -- the same rounding as the partner's copy
	end
	local a, b = mine, T.theirs or {}
	if T.side == 2 then a, b = b, a end
	local res = ns.TestCompare(a, b)
	local lines = {}
	for st = 0, #STAGES + 1 do
		local w = res.rows[st]
		if w then lines[#lines + 1] = ("%s · %d/%d%s"):format(Label(st), w.n, w.m, WhyText(w.why)) end
	end
	lines[#lines + 1] = ("all %d/%d · 1 side %d · gap %s"):format(res.n, res.m, res.one,
		res.gap and ("%+dms"):format(res.gap) or "-")
	T.result = { n = res.n, m = res.m, one = res.one, gap = res.gap, lines = lines, misses = res.misses,
		seed = T.seed, clock = T.clock, round = T.round }
	for _, l in ipairs(lines) do TLog("RESULT " .. l) end
	for _, l in ipairs(res.misses) do TLog("MISS " .. l) end
	Refresh()
end

local function OnChunk(rest)
	local round, i, n, body = rest:match("^(%d+):(%d+):(%d+):(.*)$")
	round, i, n = tonumber(round), tonumber(i), tonumber(n)
	if not (round and i and n) or n < 1 or n > 100 or i < 1 or i > n then return end
	local box = S.inb[round]
	if not box or box.n ~= n then box = { n = n, got = 0, parts = {} } S.inb[round] = box end
	if box.parts[i] then return end
	box.parts[i] = body
	box.got = box.got + 1
	if box.got < n then return Refresh() end
	local theirs = {}
	for k = 1, n do
		for one in box.parts[k]:gmatch("[^;]+") do
			local r = Unpack(one)
			if r then theirs[#theirs + 1] = r end
		end
	end
	T.theirs = theirs
	T.round = math.max(T.round or 0, round)
	TLog(("GOT round=%d msgs=%d recs=%d"):format(round, n, #theirs))
	if not S.sent[round] then SendResults(round) end
	Compute()
end

-- Every T message (Sync routes them here). Only from the partner, only on WHISPER.
function ns.TestMessage(text, channel, sender)
	if not (T and T.on) or channel ~= "WHISPER" or not SameName(sender, T.partner) then return end
	local kind, rest = text:match("^T:1:(%u%u):?(.*)$")
	if kind == "HI" or kind == "OK" then return OnHello(kind, rest, sender) end
	if not T.paired then return end
	if kind == "PI" then
		local i = tonumber(rest:match("^(%d+):"))
		local est = Est()
		if i then Raw(("PO:%d:%s"):format(i, est and ("%.0f"):format(est) or "-")) end
	elseif kind == "PO" then
		local i, est = rest:match("^(%d+):([%d%-]+)$")
		if i then OnPong(tonumber(i), est) end
	elseif kind == "ST" then
		local n, how = rest:match("^(%d+):?(%a?)$")
		n = tonumber(n)
		local sg = STAGES[T.stage]
		if n and how == "" and sg and sg.side ~= T.side and n > T.stage then   -- goal reached on the other client
			S.owe = { st = T.stage, n = math.max(0, sg.goal - T.cnt), t = GetTime() }
		end
		if n then SetStage(n, false) end
	elseif kind == "RS" then
		OnChunk(rest)
	elseif kind == "BY" then
		Stop("partner", false)
	end
end

-- ------------------------------------------------------------ window
local function Btn(label, fn)
	local b = CreateFrame("Frame", nil, win)
	b:SetSize(BTN_W, BTN_H)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetSize(BTN_W, BTN_H)
	b.bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	b.bg:SetColorTexture(0.25, 0.22, 0.18, 0.9)
	b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.text:SetText(label)
	b:EnableMouse(true)
	b:SetScript("OnEnter", function() b.bg:SetColorTexture(0.4, 0.34, 0.25, 0.95) end)
	b:SetScript("OnLeave", function() b.bg:SetColorTexture(0.25, 0.22, 0.18, 0.9) end)
	b:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then fn() end end)
	return b
end

local function Build()
	win = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	win:SetSize(W, 2 * PAD + LINE + GAP + BTN_H)
	win:SetPoint("TOP", UIParent, "TOP", 0, TOP_Y)
	win:SetFrameStrata("DIALOG")
	win:SetClampedToScreen(true)
	if win.SetBackdrop then win:SetBackdrop(BACKDROP_TOAST_12_12 or ns.TOAST_ART) end
	win:EnableMouse(true)
	win.lines = {}
	for i = 1, MAXL do
		local fs = win:CreateFontString(nil, "ARTWORK", i == 1 and "GameFontNormal" or "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -PAD - (i - 1) * LINE)
		fs:SetWidth(W - 2 * PAD)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		win.lines[i] = fs
	end
	win.skip = Btn("Skip", function() if T.on and T.paired then SetStage(T.stage + 1, true, "s") end end)
	win.send = Btn("Send", function() SendResults() end)
	win.stop = Btn("End", function()
		if T.on then Stop("end", true) end
		win:Hide()
	end)
	win:Hide()
end

function Refresh()
	if not (win and T) then return end
	local L = {}
	local head = "Wind test · " .. Short(T.partner)
	if T.xf then head = head .. " · xfaction: no msgs"
	elseif not T.on then head = head .. " · end"
	elseif not T.paired then head = head .. " · wait" end
	L[1] = head
	if not T.xf then
		local c = T.clock
		L[2] = ("seed %s · clock %s"):format(T.seed or "?", c and ("%+dms · rtt %dms · edge~%.1f%%"):format(c.off, c.rtt,
			(math.abs(c.off) + c.rtt / 2) / (ns.SYNC.step * 10)) or "?")
		local sg = STAGES[T.stage or 1]
		local step = sg and ("Step %s · %s /fart %d/%d%s"):format(sg.id, Who(sg.side), T.cnt or 0, sg.goal,
			sg.mode ~= "norm" and (" · " .. sg.mode) or "") or "Done · Send"
		if S.q[1] then step = step .. (" · sending %d"):format(#S.q) end
		if T.on and not T.paired then step = "partner: /wind pair " .. tostring(UnitName and UnitName("player") or "?") end
		L[3] = step
		for _, l in ipairs(T.result and T.result.lines or {}) do L[#L + 1] = l end
	end
	local n = math.min(#L, MAXL)
	for i = 1, MAXL do
		local fs = win.lines[i]
		if i <= n then fs:SetText(L[i]) fs:Show() else fs:SetText("") fs:Hide() end
	end
	local y = -(PAD + n * LINE + GAP)
	local x = PAD
	for _, b in ipairs({ win.skip, win.send, win.stop }) do
		local show = b == win.stop or (T.on and T.paired and (b ~= win.skip or STAGES[T.stage] ~= nil))
		b:ClearAllPoints()
		if show then
			b:SetPoint("TOPLEFT", win, "TOPLEFT", x, y)
			x = x + BTN_W + GAP
			b:Show()
		else
			b:Hide()
		end
	end
	win:SetSize(W, PAD + n * LINE + GAP + BTN_H + PAD)
end

local function Show()
	if not win then Build() end
	win:Show()
	Refresh()
end

-- ------------------------------------------------------------ start / stop
local function Start(name)
	local old = T
	local keep = (type(old.recs) == "table" and #old.recs > 0) and old or old.prev   -- the last test with farts
	if type(keep) == "table" then keep.prev = nil else keep = nil end
	T = { on = true, partner = name, id = Srv(), stage = 1, cnt = 0, recs = {}, lines = {}, n = (old.n or 0) + 1,
		prev = keep }
	db.test = T
	S = Fresh()
	TLog(("PAIR start n=%d ver=%s"):format(T.n, tostring(ns.VERSION)))
end

function Stop(why, tell)
	if tell and T.on and T.paired then Raw("BY") end
	T.on, T.ended = false, why
	S = Fresh()   -- stops the tick, the pings and the results queue of this test
	if win then win:SetScript("OnUpdate", nil) end
	TLog("PAIR end why=" .. why)
	Refresh()
end

-- /wind pair [name] | off
function ns.TestCmd(arg)
	arg = arg or ""
	if arg:lower() == "off" then
		if T.on then Stop("off", true) end
		if win then win:Hide() end
		return
	end
	local name, unit = Resolve(arg)
	if not name then ns.Say("pair <name>") return end
	if T.on then Stop("new", true) end
	Start(name)
	Show()
	if OtherSide(unit) then   -- the other faction: no addon message can cross
		T.on, T.xf = false, true
		TLog("PAIR xfaction: no msgs")
		return Refresh()
	end
	TickStart()
	Hello("HI")
	Refresh()
end

-- ADDON_LOADED: test mode is always off after a load (it never starts by itself).
function ns.TestInit(saved)
	db = saved
	T = type(db.test) == "table" and db.test or {}
	db.test = T
	T.on, T.paired = false, false
	T.recs = type(T.recs) == "table" and T.recs or {}
	T.lines = type(T.lines) == "table" and T.lines or {}
	S = Fresh()
end

-- PLAYER_LOGOUT: off (records and the table stay in the save).
function ns.TestOff(why)
	if T and T.on then Stop(why or "logout", false) end
end

function ns.TestFrame() return win end
function ns.TestState() return T, S end
