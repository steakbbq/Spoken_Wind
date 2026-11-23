-- Spoken Wind: the board (0.6.4). Per-character counts + the players you met.
-- Per character (SpokenWindDB.chars[<own GUID>]): f = own /fart presses, h = replies to
--   your farts, l = OTHER players' farts that played here (yours never), t = the 7 tier
--   counts of every pool fart that played here (untiered files skipped). They start at 0:
--   the account totals cannot be split (no double count over alts).
-- F, H and S carry ONLY these per-character numbers. Nothing links two characters.
-- Board (SpokenWindDB.board[<GUID>]): other players, from F / H (first hand) and S (gossip).
--   Per number the max (never down). A value over CAP or more than JUMP over the stored
--   one = ignored. Hide: the higher seq wins. Own characters never come from outside.
--   Names: a first-hand name (the sender field) wins over a second-hand one.
--   Raise budget (coordinator OK 2026-11-22): after the first sight, the sum of an entry's numbers
--   (f + h + l + tiers) may rise at most CFG.bud per day since that first sight, plus one day.
--   The extra is ignored (the numbers stop at the budget, nothing else changes). The first sight
--   itself: CAP + JUMP only, as before (CFG.budNew = nil; tools/sim tries a cap there). CFG.bud is
--   far above every honest player in tools/sim. Log: 'S cap who=<n-th capped player> over='.
-- S: ONE extra message per own fart key press, right after F, and the slow timer S (Sync.lua:
--   one per 300 s + 0-60 s, guild / group). Own entry first, then a few others round robin.
--   Never on receive, as a reply or relay. This file sends nothing and has no timers.
-- Seen: the last SEEN_N S gossip entries (not entry 1); a hit = already known and no number up more than RAISE.
--   The sim (tools/sim) shows it reads too high at every setting, so the UI says "Seen ?" only
--   (CFG.seenShow = false). The logs keep the number.
-- Board tab (Achievements.lua draws it): Most heard (h) + Top listener (l), top 10 each, own
--   characters in the lists, your row under a list when it is not in the top 10.
-- The B table is pure (no game calls): tools/sim runs the same code.
local _, ns = ...
ns = ns or {}

local B = {}
ns.B = B

local CAP, JUMP, LIMIT, BYTES = 1000000, 10000, 2000, 255
local TIERS = 7
B.CFG = { cap = CAP, jump = JUMP, limit = LIMIT, bytes = BYTES, k = 4, top = 2, topN = 10,
	seenN = 50, seenMin = 20, raise = 0.05, sGap = 2, logMax = 20, seenShow = false,
	bud = 3000, budNew = nil, capLog = 30 }
B.TIER_NAMES = { "Poor", "Common", "Uncommon", "Rare", "Epic", "Legend", "Shartifact" }
B.TIER_HEX = { "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80" }
local NUMS = { "f", "h", "l" }

-- ------------------------------------------------------------ base36
local DIG = "0123456789abcdefghijklmnopqrstuvwxyz"
function B.Enc(n)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then return "0" end
	local s = ""
	while n > 0 do
		local d = n % 36
		s = DIG:sub(d + 1, d + 1) .. s
		n = (n - d) / 36
	end
	return s
end

function B.Dec(s)
	if type(s) ~= "string" or #s < 1 or #s > 5 or not s:match("^[0-9a-z]+$") then return nil end
	return tonumber(s, 36)
end

-- "f.h.l" (nil = not three numbers)
function B.DecNums(s)
	if type(s) ~= "string" then return nil end
	local a, b, c = s:match("^([0-9a-z]+)%.([0-9a-z]+)%.([0-9a-z]+)$")
	a, b, c = B.Dec(a), B.Dec(b), B.Dec(c)
	if not (a and b and c) then return nil end
	return a, b, c
end

-- 7 dot-joined tier counts (nil = not 7 numbers)
function B.DecTiers(s)
	if type(s) ~= "string" then return nil end
	local t = {}
	for p in (s .. "."):gmatch("([^%.]*)%.") do t[#t + 1] = B.Dec(p) or false end
	if #t ~= TIERS then return nil end
	for i = 1, TIERS do if not t[i] then return nil end end
	return t
end

-- "Player-1234-0ABCDEF0" <-> "1234-0ABCDEF0"
function B.Short(g)
	return type(g) == "string" and g:match("^Player%-(%d+%-%x+)$") or nil
end
function B.Long(s)
	return type(s) == "string" and s:match("^%d+%-%x+$") and "Player-" .. s or nil
end

-- A name for the wire: no field separators, max 24 bytes.
local function Clean(name)
	if type(name) ~= "string" then return "" end
	return (name:gsub("[,;:|]", "")):sub(1, 24)
end
B.Clean = Clean

-- ------------------------------------------------------------ own characters
function B.Char(st, g)
	local c = st.chars[g]
	if not c then
		c = { f = 0, h = 0, l = 0, t = { 0, 0, 0, 0, 0, 0, 0 }, hide = 0, hs = 0 }
		st.chars[g] = c
	end
	return c
end

-- F / H fields of a character: numbers "f.h.l" and the tiers ("" when all 0). Hidden = "", "".
function B.OwnFields(c)
	if not c or c.hide == 1 then return "", "" end
	local any, p = false, {}
	for i = 1, TIERS do
		local v = c.t and c.t[i] or 0
		if v > 0 then any = true end
		p[i] = B.Enc(v)
	end
	return B.Enc(c.f) .. "." .. B.Enc(c.h) .. "." .. B.Enc(c.l), any and table.concat(p, ".") or ""
end

-- ------------------------------------------------------------ merge
local function Ok(v, old)
	return type(v) == "number" and v >= 0 and v <= CAP and v <= (old or 0) + JUMP
end

-- The raise budget sums every number of an entry: f + h + l + the 7 tiers.
local function Sum(e)
	local s = (e.f or 0) + (e.h or 0) + (e.l or 0)
	if e.t then for i = 1, TIERS do s = s + (e.t[i] or 0) end end
	return s
end

-- One number under the budget: the value to keep, the room left, the extra so far (ignored).
local function Take(old, v, room, over)
	if not room then return v, room, over end
	local d = v - old
	if d <= room then return v, room - d, over end
	return old + room, 0, over + d - room
end

-- Drop the oldest entries (seen time) over the limit.
local function Prune(st, keep)
	while (st.boardN or 0) > LIMIT do
		local og, ot
		for g, e in pairs(st.board) do
			if g ~= keep and (not ot or (e.at or 0) < ot) then og, ot = g, e.at or 0 end
		end
		if not og then return end
		st.board[og] = nil
		st.boardN = st.boardN - 1
	end
end

-- rec = { n = name, r = realm, f, h, l, t = {7} or nil, hide = 0|1, hs = seq }.
-- fh = first hand (the sender itself). Returns "new" | "up" | "same" | "drop".
function B.Merge(st, g, rec, now, fh)
	if not B.Short(g) or st.chars[g] then return "drop" end
	local e = st.board[g]
	local new = e == nil
	if new then
		e = { f = 0, h = 0, l = 0, hide = 0, hs = 0, at = now }
		st.board[g] = e
		st.boardN = (st.boardN or 0) + 1
	end
	-- the raise budget: room = how much the sum may still rise now (nil = no limit)
	if not (e.bt and e.b0) then e.bt, e.b0 = now, Sum(e) end   -- new, or an entry from before the budget
	local days = math.max(0, now - e.bt) / 86400
	local room = B.CFG.budNew   -- the first sight: nil in the build (CAP + JUMP only, as before)
	if not new then room = math.max(0, math.floor(B.CFG.bud * (1 + days)) - (Sum(e) - e.b0)) end
	local over, up = 0, false
	for _, k in ipairs(NUMS) do
		local v = rec[k]
		if Ok(v, e[k]) and v > e[k] then
			v, room, over = Take(e[k], v, room, over)
			if v > e[k] then e[k] = v up = true end
		end
	end
	if type(rec.t) == "table" then
		e.t = e.t or { 0, 0, 0, 0, 0, 0, 0 }
		for i = 1, TIERS do
			local v = rec.t[i]
			if Ok(v, e.t[i]) and v > e.t[i] then
				v, room, over = Take(e.t[i], v, room, over)
				if v > e.t[i] then e.t[i] = v up = true end
			end
		end
	end
	if new then e.b0 = Sum(e) end   -- the budget starts after the first sight
	if B.CFG.budNeed then B.CFG.budNeed(st, g, Sum(e), e.b0, days, new) end   -- tools/sim only
	if over > 0 and B.OnCap then B.OnCap(g, over) end
	if type(rec.hs) == "number" and rec.hs <= CAP and rec.hs > (e.hs or 0) then
		e.hs, e.hide = rec.hs, rec.hide == 1 and 1 or 0
		up = true
	end
	local name = rec.n ~= "" and rec.n or nil
	if name then
		if fh then
			if e.n ~= name or e.fh ~= 1 then e.n, e.r, e.fh = name, rec.r, 1 end
		elseif not e.n then
			e.n = name
		end
	end
	e.at = now
	if new then Prune(st, g) end
	return new and "new" or (up and "up" or "same")
end

-- ------------------------------------------------------------ S message
local function Entry(g, name, e)
	local hidden = e.hide == 1
	return ("%s,%s,%s,%s,%s,%d%s"):format(B.Short(g), Clean(name), hidden and "0" or B.Enc(e.f),
		hidden and "0" or B.Enc(e.h), hidden and "0" or B.Enc(e.l), hidden and 1 or 0, B.Enc(e.hs or 0))
end

-- Keeps list = the best m GUIDs (insertion, one pass over the board: no full sort per key press).
local function Keep(list, m, g, before)
	local n = #list
	if n >= m and not before(g, list[n]) then return end
	local i = n < m and n + 1 or n
	list[i] = g
	while i > 1 and before(list[i], list[i - 1]) do
		list[i], list[i - 1] = list[i - 1], list[i]
		i = i - 1
	end
end

-- The top players of one number (hidden left out): a list of GUIDs, best first (ties: GUID).
function B.Top(st, k, n)
	local list = {}
	local function Before(a, b)
		local x, y = st.board[a][k], st.board[b][k]
		if x ~= y then return x > y end
		return a < b
	end
	for g, e in pairs(st.board) do
		if e.hide ~= 1 and (e[k] or 0) > 0 then Keep(list, n or math.huge, g, Before) end
	end
	return list
end

-- The want oldest-sent GUIDs (never sent = first, then the GUID: the same order on every run)
-- of pool (nil = the whole board), not in used. Appended to out.
local function Oldest(st, pool, used, want, out)
	if want <= 0 then return end
	local function Before(a, b)
		local x, y = st.board[a].sent or 0, st.board[b].sent or 0
		if x ~= y then return x < y end
		return a < b
	end
	local best = {}
	if pool then
		for _, g in ipairs(pool) do if not used[g] then Keep(best, want, g, Before) end end
	else
		for g in pairs(st.board) do if not used[g] then Keep(best, want, g, Before) end end
	end
	for _, g in ipairs(best) do used[g] = true out[#out + 1] = g end
end

-- The S text of the own character me: own entry + up to k others (top first), <= BYTES.
-- Marks the others sent. Returns text, others, bytes (nil = no own entry).
function B.EncodeS(st, me, name, now, k, top)
	local c = st.chars[me]
	if not (c and B.Short(me)) then return nil end
	k, top = k or B.CFG.k, top or B.CFG.top
	local text = "S:1:" .. Entry(me, name, c)
	local used, picks, tops, inTop = {}, {}, {}, {}
	for _, key in ipairs({ "h", "l" }) do   -- the union of the 2 top-10 lists
		for _, g in ipairs(B.Top(st, key, B.CFG.topN)) do
			if not inTop[g] then inTop[g] = true tops[#tops + 1] = g end
		end
	end
	Oldest(st, tops, used, math.min(top, k), picks)
	Oldest(st, nil, used, k - #picks, picks)
	local n = 0
	for _, g in ipairs(picks) do
		local e = st.board[g]
		local part = ";" .. Entry(g, e.n, e)
		if #text + #part <= BYTES then
			text = text .. part
			e.sent = now
			n = n + 1
		end
	end
	return text, n, #text
end

-- S text -> list of { g, n, f, h, l, hide, hs } (bad entries left out) + the bad count.
-- nil = not an S message. Extra fields after the known ones are ignored (later builds).
function B.DecodeS(text)
	if type(text) ~= "string" or text:sub(1, 4) ~= "S:1:" or #text > BYTES then return nil end
	local out, bad = {}, 0
	for part in (text:sub(5) .. ";"):gmatch("([^;]*);") do
		local s, name, f, h, l, hs = part:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)")
		local g = B.Long(s)
		local hide, seq = (hs or ""):match("^([01])([0-9a-z]+)$")
		f, h, l, seq = B.Dec(f), B.Dec(h), B.Dec(l), B.Dec(seq)
		if g and f and h and l and seq then
			out[#out + 1] = { g = g, n = name, f = f, h = h, l = l, hide = tonumber(hide), hs = seq }
		else
			bad = bad + 1
		end
	end
	return out, bad
end

-- ------------------------------------------------------------ seen
-- Before the merge: a hit = known with no number up more than RAISE. Own characters: left out.
function B.SeenAdd(st, rec)
	if st.chars[rec.g] then return end
	local e = st.board[rec.g]
	local hit = e ~= nil
	if hit then
		for _, k in ipairs(NUMS) do
			local v, old = rec[k] or 0, e[k] or 0
			if v > old and v > old * (1 + B.CFG.raise) then hit = false end
		end
	end
	local w = st.seenWin
	w[#w + 1] = hit and 1 or 0
	while #w > B.CFG.seenN do table.remove(w, 1) end
end

-- Seen estimate in % (nil = fewer than seenMin entries), window size, hits.
function B.Seen(st)
	local w, hits = st.seenWin, 0
	for _, v in ipairs(w) do hits = hits + v end
	if #w < B.CFG.seenMin then return nil, #w, hits end
	return math.floor(hits * 100 / #w + 0.5), #w, hits
end

-- One received S (sender = its "Name-Realm"): entry 1 is first hand. Returns n, new, up, drop.
function B.GotS(st, text, sender, now)
	local list, bad = B.DecodeS(text)
	if not list then return nil end
	local name, realm = nil, nil
	if type(sender) == "string" and sender ~= "" then name, realm = sender:match("^([^%-]+)%-?(.*)$") end
	local new, up, drop = 0, 0, bad
	for i, rec in ipairs(list) do
		if i > 1 then B.SeenAdd(st, rec) end   -- entry 1 = the sender: its F came just before (always known)
		local fh = i == 1 and name ~= nil
		if fh then rec.n, rec.r = name, realm end
		local r = B.Merge(st, rec.g, rec, now, fh)
		if r == "new" then new = new + 1 elseif r == "up" then up = up + 1 elseif r == "drop" then drop = drop + 1 end
	end
	return #list + bad, new, up, drop
end

-- ------------------------------------------------------------ sums
-- All: own characters + the board, hidden left out. Heard = the sum of l (one side only). pb = board players only
-- (other players met; the window's "SW players met" tag).
function B.All(st)
	local f, l, p, pb, oldest = 0, 0, 0, 0, nil
	local t = { 0, 0, 0, 0, 0, 0, 0 }
	local function Add(e)
		if e.hide == 1 then return end
		f, l, p = f + (e.f or 0), l + (e.l or 0), p + 1
		for i = 1, TIERS do t[i] = t[i] + (e.t and e.t[i] or 0) end
	end
	for _, c in pairs(st.chars) do Add(c) end
	for _, e in pairs(st.board) do
		Add(e)
		if e.hide ~= 1 then pb = pb + 1 end
		if e.hide ~= 1 and (not oldest or (e.at or 0) < oldest) then oldest = e.at end
	end
	return { f = f, l = l, p = p, pb = pb, t = t, oldest = oldest }
end

-- ------------------------------------------------------------ board tab
-- One list of the Board tab: k = "h" (Most heard) or "l" (Top listener). The top n of the
-- board (hidden + zero left out) and of the own characters (zero left out), best first (ties:
-- GUID). me not in the top = rows.own, with its true rank. Row = { g, n, r, v, rank, own, me,
-- f, h, l, at, hide }.
function B.Rank(st, k, n, me)
	local function V(g)
		local e = st.chars[g] or st.board[g]
		return e and e[k] or 0
	end
	local function Before(a, b)
		local x, y = V(a), V(b)
		if x ~= y then return x > y end
		return a < b
	end
	local function In(g, e) return (e[k] or 0) > 0 and (st.chars[g] ~= nil or e.hide ~= 1) end
	local list = {}
	for g, e in pairs(st.board) do if In(g, e) then Keep(list, n, g, Before) end end
	for g, c in pairs(st.chars) do if In(g, c) then Keep(list, n, g, Before) end end
	local function Row(g, rank)
		local e = st.chars[g] or st.board[g]
		return { g = g, n = e.n or "?", r = e.r or "", v = e[k] or 0, rank = rank, own = st.chars[g] ~= nil,
			me = g == me, f = e.f or 0, h = e.h or 0, l = e.l or 0, at = e.at, hide = e.hide }
	end
	local rows, inTop = {}, false
	for i, g in ipairs(list) do
		rows[i] = Row(g, i)
		if g == me then inTop = true end
	end
	if me and st.chars[me] and not inTop then
		local r = 1
		for g, e in pairs(st.board) do if In(g, e) and Before(g, me) then r = r + 1 end end
		for g, c in pairs(st.chars) do if g ~= me and In(g, c) and Before(g, me) then r = r + 1 end end
		rows.own = Row(me, r)
	end
	return rows
end

-- "Seen ?" unless CFG.seenShow (off: the sim says the number misleads).
function B.SeenText(st)
	local est = B.Seen(st)
	return (B.CFG.seenShow and est) and ("Seen ~" .. est .. "%") or "Seen ?"
end

-- ------------------------------------------------------------ addon (game calls from here on)
local db, me, myName
local nUpd = 0   -- ALL upd lines this session (capped)
local capWho, nWho, nCap, capOver, nCapLog = {}, 0, 0, 0, 0   -- the raise budget this session

local function Num(v) return type(v) == "number" and v >= 0 and v <= CAP and math.floor(v) or nil end
local function SLog(s) if ns.SyncLog then ns.SyncLog(s) end end
local function Pos(v) return type(v) == "number" and v >= 0 and v < 1e10 and math.floor(v) or nil end

-- Merge: the budget cut a number (the extra is ignored). who = the n-th player cut this session:
-- no name, no GUID in the log.
function B.OnCap(g, over)
	nCap, capOver = nCap + 1, capOver + over
	local w = capWho[g]
	if not w then nWho = nWho + 1 w = nWho capWho[g] = w end
	if nCapLog < B.CFG.capLog then
		nCapLog = nCapLog + 1
		SLog(("S cap who=%d over=%d"):format(w, over))
	end
end

-- The Fart button: a GUID on the board = a Spoken Wind user (rows come only from addon messages).
function ns.BoardHas(g) return db ~= nil and db.board ~= nil and db.board[g] ~= nil end

-- Sync SUM: the merges the budget cut this session, and the sum ignored.
function ns.BoardCaps() return nCap, capOver end

-- Core calls this at ADDON_LOADED: checks the saves, drops what is not valid.
function ns.BoardInit(saved)
	db = saved
	local chars = {}
	for g, c in pairs(type(db.chars) == "table" and db.chars or {}) do
		if B.Short(g) and type(c) == "table" then
			local t = {}
			for i = 1, TIERS do t[i] = Num(type(c.t) == "table" and c.t[i]) or 0 end
			chars[g] = { f = Num(c.f) or 0, h = Num(c.h) or 0, l = Num(c.l) or 0, t = t,
				hide = c.hide == 1 and 1 or 0, hs = Num(c.hs) or 0,
				n = type(c.n) == "string" and c.n or nil, r = type(c.r) == "string" and c.r or nil }
		end
	end
	db.chars = chars
	local board, n = {}, 0
	for g, e in pairs(type(db.board) == "table" and db.board or {}) do
		if B.Short(g) and type(e) == "table" and not chars[g] then
			local b = { f = Num(e.f) or 0, h = Num(e.h) or 0, l = Num(e.l) or 0, hide = e.hide == 1 and 1 or 0,
				hs = Num(e.hs) or 0, at = Num(e.at) or 0, sent = Num(e.sent),
				n = type(e.n) == "string" and e.n ~= "" and e.n or nil, r = type(e.r) == "string" and e.r or nil,
				fh = e.fh == 1 and 1 or nil, bt = Pos(e.bt), b0 = Pos(e.b0) }
			if type(e.t) == "table" then
				b.t = {}
				for i = 1, TIERS do b.t[i] = Num(e.t[i]) or 0 end
			end
			board[g] = b
			n = n + 1
		end
	end
	db.board, db.boardN = board, n
	local w = {}
	for _, v in ipairs(type(db.seenWin) == "table" and db.seenWin or {}) do
		if v == 0 or v == 1 then w[#w + 1] = v end
	end
	while #w > B.CFG.seenN do table.remove(w, 1) end
	db.seenWin = w
	db.boardOff = db.boardOff == true
	me, nUpd = nil, 0
	capWho, nWho, nCap, capOver, nCapLog = {}, 0, 0, 0, 0
	if db.boardN > LIMIT then Prune(db) end
end

-- PLAYER_LOGIN: this character's counters (0 the first time), its name, its hide flag.
function ns.BoardLogin()
	local g = UnitGUID and UnitGUID("player")
	if not B.Short(g) then return end
	me = g
	local c = B.Char(db, g)
	myName = UnitName and UnitName("player") or nil
	c.n = type(myName) == "string" and myName or c.n
	local realm = GetRealmName and GetRealmName() or ""
	c.r = type(realm) == "string" and realm or ""
	local want = db.boardOff and 1 or 0
	if c.hide ~= want then c.hide, c.hs = want, c.hs + 1 end
	if db.board[g] then db.board[g], db.boardN = nil, db.boardN - 1 end   -- learned from others before: own data only
end

function ns.BoardMe() return me end

-- Own counters: "f" = own press, "h" = a reply to your fart, "l" = someone else's fart played here.
function ns.BoardOwn(k)
	local c = me and db.chars[me]
	if c and c[k] and c[k] < CAP then c[k] = c[k] + 1 end
end

-- The tier of a sound (1-7) or nil (untiered: every live sound today).
function ns.SoundTier(token, i)
	local row = ns.EMOTES and ns.EMOTES[token]
	local s = row and row.sounds[i]
	local t = s and tonumber(s.tier)
	return t and t >= 1 and t <= TIERS and t or nil
end

-- Collection: a pool fart played here (own too).
function ns.BoardTier(token, i)
	local c = me and db.chars[me]
	local t = ns.SoundTier(token, i)
	if c and t and c.t[t] < CAP then c.t[t] = c.t[t] + 1 end
end

-- Mine tiers (account): from the collection counts, tier of each file x its n. Nothing is stored,
-- so plays from before 0.6.4 count once a file has a tier. Returns the 7 counts + their sum.
function ns.TiersMine()
	local tierOf = {}
	for token, row in pairs(ns.EMOTES or {}) do
		for i, s in ipairs(row.sounds or {}) do tierOf[s.file] = ns.SoundTier(token, i) end
	end
	local t, n = { 0, 0, 0, 0, 0, 0, 0 }, 0
	for k, e in pairs(type(db.dex) == "table" and db.dex or {}) do
		local tier = tierOf[(ns.DEX_ALIAS and ns.DEX_ALIAS[k]) or k]
		if tier and type(e) == "table" and tonumber(e.n) then t[tier] = t[tier] + e.n n = n + e.n end
	end
	return t, n
end

-- F / H fields of this character (numbers, tiers).
function ns.BoardFields()
	return B.OwnFields(me and db.chars[me])
end

-- First-hand numbers from an F (the farter) or an H (the replier). fields = the extra fields
-- after the author flag: [1] = "f.h.l", [2] = tiers.
function ns.BoardFirst(g, sender, nums, tiers)
	local f, h, l = B.DecNums(nums)
	local t = B.DecTiers(tiers)
	if not (f or t) then return end
	local name, realm
	if type(sender) == "string" and sender ~= "" then name, realm = sender:match("^([^%-]+)%-?(.*)$") end
	local r = B.Merge(db, g, { n = name, r = realm, f = f, h = h, l = l, t = t }, time(), name ~= nil)
	if (r == "new" or r == "up") and nUpd < B.CFG.logMax then
		nUpd = nUpd + 1
		local e = db.board[g]
		SLog(("ALL upd g=%s farts=%d heard=%d"):format(g:sub(-6), e.f, e.l))
	end
end

local lastS
-- Sync: the S text for this key press or the timer, or nil (no own entry, combat, 2 s gap).
function ns.BoardS(now)
	if not me then return nil end
	if InCombatLockdown and InCombatLockdown() then return nil end
	if lastS and now - lastS < B.CFG.sGap then return nil end
	local text, n, bytes = B.EncodeS(db, me, myName, time(), B.CFG.k, B.CFG.top)
	if text then lastS = now end
	return text, n, bytes
end

local lastGot = {}   -- sender -> { text, t }: the same S on 2 channels counts once
-- Sync: one S message from a group / guild / pair channel.
function ns.BoardGotS(text, sender, now)
	local k = tostring(sender)
	local p = lastGot[k]
	if p and p.text == text and now - p.t <= 3 then return end
	lastGot[k] = { text = text, t = now }
	local n, new, up, drop = B.GotS(db, text, sender, time())
	if n then SLog(("SYNC recv n=%d new=%d up=%d drop=%d"):format(n, new, up, drop)) end
end

-- /wind board off|on|status
function ns.BoardCmd(arg)
	if arg == "off" or arg == "on" then
		db.boardOff = arg == "off"
		local c = me and db.chars[me]
		local want = db.boardOff and 1 or 0
		if c and c.hide ~= want then c.hide, c.hs = want, c.hs + 1 end
	end
	local a = B.All(db)
	return ("board %s · %d players · %s"):format(db.boardOff and "off" or "on", a.p, B.SeenText(db))
end

-- BOOT fields.
function ns.BoardBoot()
	local c = me and db.chars[me] or { f = 0, h = 0, l = 0 }
	local a = B.All(db)
	local mine = ns.TiersMine()
	local est, win = B.Seen(db)
	return ("char=%d/%d/%d all=%d/%d/%d tiers=%s alltiers=%s board=%d hide=%d seen=%s win=%d"):format(
		c.f, c.h, c.l, a.f, a.l, a.p, table.concat(mine, "."), table.concat(a.t, "."), db.boardN or 0,
		db.boardOff and 1 or 0, est and tostring(est) or "?", win)
end

-- The Board tab: both lists, the All strip, Seen. age = days since the oldest top-10 row of
-- another player came in (nil = none). off = this character is hidden (/wind board off).
function ns.BoardLines(now)
	now = now or time()
	local a = B.All(db)
	local est, win, hits = B.Seen(db)
	local out = { heard = B.Rank(db, "h", B.CFG.topN, me), listen = B.Rank(db, "l", B.CFG.topN, me), all = a,
		seen = B.SeenText(db), est = est, win = win, hits = hits, off = db.boardOff == true,
		text = ("All · Farts %d · Heard %d · Players %d"):format(a.f, a.l, a.p) }
	local oldest
	for _, rows in ipairs({ out.heard, out.listen }) do
		for _, r in ipairs(rows) do
			if not r.own and r.at and (not oldest or r.at < oldest) then oldest = r.at end
		end
	end
	if oldest then out.age = math.max(0, math.floor((now - oldest) / 86400)) end
	return out
end
