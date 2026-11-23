-- Seeded gossip simulator for the Spoken Wind board (0.6.4). Runs the REAL Spoken_Wind/Board.lua
-- (one loaded copy per account). Returns Run(cfg) -> result table, and ToJSON(table).
-- Globals set by the runner: ROOT (repo), ADDON_DIR (Spoken_Wind folder).
-- Everything the sim keeps (truth, world) is its own; the board code under test is not touched.
local bit = bit or require("bit")

-- ------------------------------------------------------------ rng (own streams: world, loss)
local function Rng(seed)
	local s = (seed * 2654435761 + 12345) % 4294967296
	if s == 0 then s = 1 end
	return function()
		s = bit.bxor(s, bit.lshift(s, 13)); s = bit.bxor(s, bit.rshift(s, 17)); s = bit.bxor(s, bit.lshift(s, 5))
		s = s % 4294967296
		return s / 4294967296
	end
end

local function Slurp(p)
	local f = assert(io.open(p, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- ------------------------------------------------------------ wire formats (verbatim from the clients)
local PAT_F = "^F:1:(%u+):([%w%-]+):(%d+):(%d+):(%d+)(.-)$"
local PAT_H = "^H:1:([%w%-]+):(%d+):([%w%-]+)(.-)$"
local COMPAT = {
	{ "tests/compat/0.6.2/Sync.lua", { PAT_F, '(a ~= "" and a ~= ":a")' } },
	{ "tests/compat/0.6.2/Heard.lua", { PAT_H, '(a ~= "" and a ~= ":a")' } },
	{ "tests/compat/0.6.3/Sync.lua", { PAT_F, 'rest:sub(1, 1) ~= ":"', 'rest:match("^:([^:]*)") == "a"', "ns.MsgExtra(rest)" } },
	{ "tests/compat/0.6.3/Heard.lua", { PAT_H, "ns.MsgExtra(rest)" } },
}
local CUR_SRC = {
	{ "Sync.lua", { PAT_F, 'text:sub(1, 4) == "S:1:"', 'text:sub(1, 4) == "H:1:"', "ns.BoardFirst" } },
	{ "Heard.lua", { PAT_H, "ns.BoardFirst" } },
}

local function CheckPatterns(root, addon)
	local missing = {}
	local function Chk(path, list)
		local src = Slurp(path)
		for _, p in ipairs(list) do
			if not src:find(p, 1, true) then missing[#missing + 1] = path:match("[^/\\]+[/\\][^/\\]+$") .. " lacks " .. p end
		end
	end
	for _, c in ipairs(COMPAT) do Chk(root .. "/" .. c[1], c[2]) end
	for _, c in ipairs(CUR_SRC) do Chk(addon .. "/" .. c[1], c[2]) end
	return missing
end

-- Sync.lua ns.MsgExtra / ns.MsgTail (0.6.4), copied
local function MsgExtra(rest)
	if rest == "" then return true, false, {} end
	if type(rest) ~= "string" or rest:sub(1, 1) ~= ":" then return false, false, {} end
	local fields = {}
	for f in (rest:sub(2) .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = f end
	return true, fields[1] == "a", fields
end
local function MsgTailOf(nums, tiers)
	local x = { "", nums or "", tiers or "" }
	while x[1] and x[#x] == "" do x[#x] = nil end
	return #x > 0 and ":" .. table.concat(x, ":") or ""
end
-- 0.6.3 MsgExtra
local function MsgExtra63(rest)
	if rest == "" then return true, false end
	if type(rest) ~= "string" or rest:sub(1, 1) ~= ":" then return false, false end
	return true, rest:match("^:([^:]*)") == "a"
end

-- an old client reading a text: returns "F" "H" "T" (taken), "dropF" "dropH" (tail refused), "none"
local function OldRecv(ver, text)
	local s4 = text:sub(1, 4)
	if s4 == "H:1:" then
		local g, n, from, rest = text:match(PAT_H)
		if not g then return "none" end
		if ver == 2 then
			if rest ~= "" and rest ~= ":a" then return "dropH" end
		elseif not MsgExtra63(rest) then return "dropH" end
		return "H"
	end
	if s4 == "T:1:" then return "T" end
	local token, guid, snd, pool, n, rest = text:match(PAT_F)
	if not token then return "none" end
	if ver == 2 then
		if rest ~= "" and rest ~= ":a" then return "dropF" end
	elseif not MsgExtra63(rest) then return "dropF" end
	return "F"
end

-- ------------------------------------------------------------ json out
local function ToJSON(v)
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "null" end
		if v == math.floor(v) and math.abs(v) < 1e15 then return ("%d"):format(v) end
		return ("%.6g"):format(v)
	elseif t == "boolean" then return tostring(v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c) return ("\\u%04x"):format(c:byte()) end) .. '"'
	elseif t == "table" then
		local out = {}
		local cnt = 0
		for _ in pairs(v) do cnt = cnt + 1 end
		if cnt == #v then   -- a real array (an empty table is [] too)
			for i = 1, #v do out[i] = ToJSON(v[i]) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local val = v[k]
			if val == nil then val = v[tonumber(k)] end
			out[#out + 1] = ToJSON(k) .. ":" .. ToJSON(val)
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end

local function Pct(arr, p)
	local n = #arr
	if n == 0 then return nil end
	local a = {}
	for i = 1, n do a[i] = arr[i] end
	table.sort(a)
	local i = math.max(1, math.min(n, math.floor(p * (n - 1) + 0.5) + 1))
	return a[i]
end

local GRID = {}
for ri, r in ipairs({ 0.02, 0.05, 0.1, 0.2 }) do
	for _, w in ipairs({ 30, 50, 100 }) do GRID[#GRID + 1] = { raise = r, W = w, ri = ri, key = ("r%g_w%d"):format(r, w) } end
end
local RAISES = { 0.02, 0.05, 0.1, 0.2 }
local DEFAULT_CI
for i, g in ipairs(GRID) do if g.raise == 0.05 and g.W == 50 then DEFAULT_CI = i end end

-- ================================================================ Run
local function Run(cfg)
	cfg = cfg or {}
	local NCH = cfg.chars or 500
	local DAYS = cfg.days or 60
	local USERS = cfg.users or NCH
	local NREALM = cfg.realms or 5
	local K, TOP = cfg.k or 4, cfg.top or 2
	local LOSS = cfg.loss or 0.02
	local CHECKS = cfg.checks ~= false
	local EST = cfg.est ~= false
	local FAKE = cfg.fakers == true
	local OPT = cfg.opt or 0.05
	local TIMER = cfg.timer == true   -- the 0.6.4 timer S (off = press S only, as sim064)
	local GSH, PSH = cfg.guildShare or 0.7, cfg.partyShare or 0.4   -- guild members, online chars in a group
	local T_WAIT, T_JIT, T_LOGIN, T_TICK, T_COMBAT = 300, 60, 60, 15, cfg.timerCombat or 0.3
	local R = Rng(cfg.seed or 1)
	local LR = Rng((cfg.seed or 1) + 7777)
	local TR = Rng((cfg.seed or 1) + 31337)   -- timer stream: jitter, combat at a tick, timer S loss
	local CP = {}
	for _, d in ipairs(cfg.checkpoints or { 1, 7, 14, 30, 60 }) do CP[d] = true end

	local res = { cfg = cfg, checks = {}, details = {}, days = {}, cp = {}, viol = {} }
	local function Viol(kind, msg)
		res.viol[kind] = (res.viol[kind] or 0) + 1
		res.details[kind] = res.details[kind] or {}
		if #res.details[kind] < 5 then res.details[kind][#res.details[kind] + 1] = msg end
	end

	local missing = CheckPatterns(ROOT, ADDON_DIR)
	res.checks[#res.checks + 1] = { "compat patterns present", #missing == 0, table.concat(missing, "; ") }

	-- ---------------------------------------------------------- world
	local nA = math.max(1, math.floor(NCH * 0.7 + 0.5))
	local accts = {}
	for i = 1, nA do accts[i] = { id = i, chars = {}, n = 1 } end
	for _ = 1, NCH - nA do
		local best
		for _ = 1, 6 do
			local a, b = accts[math.floor(R() * nA) + 1], accts[math.floor(R() * nA) + 1]
			local c = a.n >= b.n and a or b
			if c.n < 5 then best = c break end
		end
		if best then best.n = best.n + 1 end
	end
	local realmW = { 0.3, 0.25, 0.2, 0.15, 0.1 }
	local function PickRealm()
		local x, s = R(), 0
		for r = 1, NREALM do
			s = s + (realmW[r] or 0.1)
			if x < s then return r end
		end
		return NREALM
	end
	local chars, byGuid = {}, {}
	for _, a in ipairs(accts) do
		a.home = PickRealm()
		for j = 1, a.n do
			local id = #chars + 1
			local rl = (j == 1 or R() < 0.85) and a.home or PickRealm()
			local c = { id = id, acct = a, realm = rl, name = "P" .. id, rn = "R" .. rl,
				guid = ("Player-%d-%08X"):format(rl, 0x10000000 + id * 13), f = 0, h = 0, l = 0,
				presses = 0, sCount = 0, tCount = 0, hid = false, main = j == 1 }
			c.sender = c.name .. "-" .. c.rn
			c.realmName = c.rn
			c.rate = R() < 0.05 and (10 + R() * 40) or (R() * 5)
			chars[id] = c
			a.chars[j] = c
			byGuid[c.guid] = c
			if j == 1 then a.main = c end
		end
	end
	local function Shuffle(t)
		for i = #t, 2, -1 do local j = math.floor(R() * i) + 1; t[i], t[j] = t[j], t[i] end
		return t
	end
	-- guilds
	local guilds = {}
	for r = 1, NREALM do
		local pool = {}
		for _, c in ipairs(chars) do if c.realm == r and R() < GSH then pool[#pool + 1] = c end end
		Shuffle(pool)
		local i = 1
		while i <= #pool do
			local size = 10 + math.floor(R() * 31)
			if #pool - i + 1 < size then size = #pool - i + 1 end
			if size < 10 and #guilds > 0 and guilds[#guilds].realm == r then
				local g = guilds[#guilds]
				for j = i, #pool do g.members[#g.members + 1] = pool[j]; pool[j].guild = g end
			elseif size >= 2 then
				local g = { id = #guilds + 1, realm = r, members = {}, online = {} }
				for j = i, i + size - 1 do g.members[#g.members + 1] = pool[j]; pool[j].guild = g end
				guilds[#guilds + 1] = g
			end
			i = i + size
		end
	end
	-- addon users
	local order = {}
	for _, a in ipairs(accts) do order[#order + 1] = a end
	Shuffle(order)
	local have = 0
	for _, a in ipairs(order) do
		if have >= USERS then break end
		local x = R()
		a.ver = x < 0.10 and 2 or (x < 0.40 and 3 or 4)
		have = have + #a.chars
	end
	local clients, nver = {}, { [2] = 0, [3] = 0, [4] = 0 }
	for _, a in ipairs(accts) do
		if a.ver then nver[a.ver] = nver[a.ver] + #a.chars end
		a.sentF, a.sentS, a.sentH, a.sentT, a.recvB, a.hours = 0, 0, 0, 0, 0, 0
		a.ownSeq, a.synced = 0, 0
	end

	-- the fake globals the board glue reads
	local CUR, NOWT = nil, 0
	UnitGUID = function(u) return u == "player" and CUR.guid or nil end
	UnitName = function(u) return u == "player" and CUR.name or nil end
	GetRealmName = function() return CUR.rn end
	InCombatLockdown = function() return CUR.combat end
	time = function() return math.floor(NOWT) end

	-- the raise budget: off (cfg.budOff), measure the honest need (cfg.budMeasure), count the cuts
	local BUDM = cfg.budMeasure == true
	res.bud = { honestCaps = 0, fakeCaps = 0, honestOver = 0, fakeOver = 0 }
	local function BudNeed(stt, g, s, b0, days, new)
		local e = stt.board[g]
		if not e then return end
		local nb = s / (1 + days)   -- counted from 0 (the first sight inside the budget)
		if nb > (e.nB or 0) then e.nB = nb end
		if new then
			if s > (e.n0 or 0) then e.n0 = s end   -- the first-sight sum
		else
			local na = (s - b0) / (1 + days)   -- the first sight free
			if na > (e.nA or 0) then e.nA = na end
		end
	end
	local function CapSeen(g, over)
		local c = byGuid[g]
		if c and c.faker then res.bud.fakeCaps, res.bud.fakeOver = res.bud.fakeCaps + 1, res.bud.fakeOver + over
		else res.bud.honestCaps, res.bud.honestOver = res.bud.honestCaps + 1, res.bud.honestOver + over end
	end

	for _, a in ipairs(accts) do
		if a.ver == 4 then
			local ns = {}
			assert(loadfile(ADDON_DIR .. "/Board.lua"))("Spoken_Wind", ns)
			ns.B.CFG.k, ns.B.CFG.top = K, TOP
			if cfg.budOff or BUDM then ns.B.CFG.bud = math.huge end
			if BUDM then ns.B.CFG.budNeed = BudNeed end
			if cfg.budNew then ns.B.CFG.budNew = cfg.budNew end   -- try a cap on the first sight
			local oc = ns.B.OnCap
			ns.B.OnCap = function(g, over) CapSeen(g, over) oc(g, over) end
			ns.SyncLog = function(s)
				if s:sub(1, 9) == "SYNC recv" then a.synced = a.synced + 1
				elseif s:sub(1, 3) == "ERR" then res.luaErr4 = (res.luaErr4 or 0) + 1 end
			end
			a.ns, a.db = ns, {}
			ns.BoardInit(a.db)
			if EST then
				a.win = {}
				for ci = 1, #GRID do a.win[ci] = {} end
			end
			a.hidSeen, a.gotHide = {}, {}
			if R() < OPT then a.optDay = (#clients % 2 == 0) and 1 or (2 + math.floor(R() * math.max(1, DAYS - 1))) end
			clients[#clients + 1] = a
		end
	end
	if cfg.forceOpt and #clients >= 4 then
		clients[1].optDay, clients[2].optDay = 1, math.min(DAYS, 3)
	end
	-- fakers (report-only run)
	local fakers = {}
	if FAKE then
		local pool = {}
		for _, c in ipairs(chars) do if c.acct.ver == 4 then pool[#pool + 1] = c end end
		Shuffle(pool)
		for i = 1, math.max(1, math.floor(#pool * 0.01 + 0.5)) do
			if pool[i] then pool[i].faker = true; fakers[#fakers + 1] = pool[i] end
		end
	end
	local nAddonChars = 0
	for _, c in ipairs(chars) do if c.acct.ver then nAddonChars = nAddonChars + 1 end end
	res.world = { chars = NCH, accounts = nA, guilds = #guilds, addonChars = nAddonChars, v2 = nver[2], v3 = nver[3],
		v4 = nver[4], clients = #clients, fakers = #fakers, timer = TIMER }

	-- ---------------------------------------------------------- counters
	local st = { s = 0, t = 0, f = 0, h = 0, sBig = 0, sMax = 0, old = { F = 0, H = 0, dropF = 0, dropH = 0, S = 0, none = 0 },
		mis = 0, parseErr = 0, luaErr = 0, sNoPress = 0 }
	res.stats = st

	local function OldCall(a, text, kind)   -- kind: "F" | "H" | "S" (what the sim knows it sent)
		local ok, r = pcall(OldRecv, a.ver, text)
		if not ok then st.luaErr = st.luaErr + 1 Viol("old-error", tostring(r)) return "none" end
		if kind == "S" then
			st.old.S = st.old.S + 1
			if r ~= "none" then st.mis = st.mis + 1 Viol("misparse", r .. " <- " .. text:sub(1, 60)) end
		else
			st.old[r] = (st.old[r] or 0) + 1
			if r == "none" then st.parseErr = st.parseErr + 1 Viol("parse-error", kind .. " " .. text:sub(1, 60)) end
		end
		return r
	end

	-- ---------------------------------------------------------- delivery
	local function Fail(a, err) res.luaErr4 = (res.luaErr4 or 0) + 1 Viol("lua-error-0.6.4", tostring(err)) end

	local function DeliverF(m, text, ch, now, c)
		local a = m.acct
		a.recvB = a.recvB + #text
		if a.ver == 4 then
			CUR = m
			local token, guid, _, _, _, rest = text:match(PAT_F)
			if not token then st.parseErr = st.parseErr + 1 Viol("parse-error", "0.6.4 F " .. text) return false end
			local okX, _, xf = MsgExtra(rest)
			if not okX then st.parseErr = st.parseErr + 1 return false end
			if xf[2] or xf[3] then
				local ok, err = pcall(a.ns.BoardFirst, guid, c.sender, xf[2], xf[3])
				if not ok then Fail(a, err) end
			end
			return true
		end
		return OldCall(a, text, "F") == "F"
	end

	local function DeliverS(m, text, ch, now, c)
		local a = m.acct
		a.recvB = a.recvB + #text
		if a.ver ~= 4 then OldCall(a, text, "S") return end
		CUR = m
		local first = a.ns.B.Long(text:match("^S:1:([^,;]*)"))
		if not first or first == m.guid then return end
		local pend
		local list = (EST or CHECKS) and a.ns.B.DecodeS(text)
		if list then
			if EST then
				pend = {}
				local db = a.db
				for i = 2, #list do
					local rec = list[i]
					if not db.chars[rec.g] then
						local e = db.board[rec.g]
						local hits = {}
						for ri, R2 in ipairs(RAISES) do
							local hit = e ~= nil
							if hit then
								for _, k in ipairs({ "f", "h", "l" }) do
									local v, old = rec[k] or 0, e[k] or 0
									if v > old and v > old * (1 + R2) then hit = false end
								end
							end
							hits[ri] = hit and 1 or 0
						end
						pend[#pend + 1] = hits
					end
				end
			end
		end
		local before = a.synced
		local ok, err = pcall(a.ns.BoardGotS, text, c.sender, now)
		if not ok then Fail(a, err) return end
		if list and CHECKS and a.synced > before then
			for _, rec in ipairs(list) do
				if rec.hide == 1 and not a.db.chars[rec.g] then a.gotHide[rec.g] = true end
			end
		end
		if pend and a.synced > before then
			for ci, g in ipairs(GRID) do
				local w = a.win[ci]
				for _, hits in ipairs(pend) do
					w[#w + 1] = hits[g.ri]
					if #w > g.W then table.remove(w, 1) end
				end
			end
		end
	end

	local function DeliverH(r, text, ch, now, replier, farter)
		local a = r.acct
		a.recvB = a.recvB + #text
		if a.ver == 4 then
			CUR = r
			local g, n, from, rest = text:match(PAT_H)
			if not g then st.parseErr = st.parseErr + 1 Viol("parse-error", "0.6.4 H " .. text) return end
			local okX, _, xf = MsgExtra(rest)
			if not okX or g == from or from == r.guid then return end
			if xf[2] or xf[3] then
				local ok, err = pcall(a.ns.BoardFirst, from, replier.sender, xf[2], xf[3])
				if not ok then Fail(a, err) end
			end
			if r == farter then
				a.ns.BoardOwn("h")
				r.h = r.h + 1
			end
		else
			local k = OldCall(a, text, "H")
			if k == "H" and r == farter then r.h = r.h + 1 end
		end
	end

	-- one message to a channel list: sender c; text may be a function(receiver) for hand-made messages
	local function Broadcast(c, chans, text, deliver, now, kind, extra, rng)
		local base = type(text) == "function" and text(nil) or text
		local a = c.acct
		a[kind] = a[kind] + #base * #chans
		for _, ch in ipairs(chans) do
			local list = ch == "PARTY" and c.party.members or c.guild.online
			for _, m in ipairs(list) do
				if m ~= c and m.acct.ver and (rng or LR)() >= LOSS then
					local t = type(text) == "function" and text(m) or text
					deliver(m, t, ch, now, c, extra)
				end
			end
		end
	end

	-- ---------------------------------------------------------- faker texts
	local function ShortG(g) return g:match("^Player%-(%d+%-%x+)$") end
	local CAP, JUMP = 1000000, 10000
	local function Enc(n) return clients[1] and clients[1].ns.B.Enc(n) or "0" end
	-- naive faker: f, h, l + JUMP (and + JUMP on the top 3 honest). Smart (cfg.fakeMode = "hl"): only its
	-- own h + l (the 2 shown lists) + JUMP; f and the others' rows true.
	local SMART = cfg.fakeMode == "hl"
	local function Inf(e, k)
		local v = e and e[k] or 0
		if SMART and k == "f" then return v end
		return math.min(CAP, v + JUMP)
	end
	local function FakeF(c)
		return function(m)
			local base = ("F:1:FART:%s:%d:%d:%d"):format(c.guid, 1, 1, c.acct.ownSeq)
			if not m or m.acct.ver ~= 4 then return base .. "::0.0.0" end
			local e = m.acct.db.board[c.guid]
			local f, h, l = Inf(e, "f"), Inf(e, "h"), Inf(e, "l")
			return base .. MsgTailOf(Enc(f) .. "." .. Enc(h) .. "." .. Enc(l), "")
		end
	end
	local topTruth
	local function FakeS(c)
		return function(m)
			local function Ent(g, name, f, h, l) return ("%s,%s,%s,%s,%s,0%s"):format(ShortG(g), name, Enc(f), Enc(h), Enc(l), "0") end
			local own
			if not m or m.acct.ver ~= 4 then own = Ent(c.guid, c.name, 0, 0, 0)
			else
				local e = m.acct.db.board[c.guid]
				own = Ent(c.guid, c.name, Inf(e, "f"), Inf(e, "h"), Inf(e, "l"))
			end
			local t = "S:1:" .. own
			for i = 1, math.min(3, #(topTruth or {})) do
				local tc = topTruth[i]
				if SMART then t = t .. ";" .. Ent(tc.guid, tc.name, tc.f, tc.h, tc.l)
				else t = t .. ";" .. Ent(tc.guid, tc.name, math.min(CAP, tc.f + JUMP), math.min(CAP, tc.h + JUMP), math.min(CAP, tc.l + JUMP)) end
			end
			return t
		end
	end

	-- ---------------------------------------------------------- one press
	local function Press(c, now)
		NOWT = now
		local a = c.acct
		c.presses = c.presses + 1
		local party = c.party
		local gotF
		local nsent = 0
		local chans = {}
		if a.ver then
			if not (a.lastSendT and now - a.lastSendT < 1) then
				a.lastSendT = now
				if party then chans[#chans + 1] = "PARTY" end
				if c.guild then chans[#chans + 1] = "GUILD" end
				if #chans > 0 then
					a.ownSeq = a.ownSeq % 999 + 1
					local text
					if a.ver == 4 and not c.faker then
						CUR = c
						local nums, tiers = a.ns.BoardFields()
						text = ("F:1:FART:%s:%d:%d:%d"):format(c.guid, 1, 1, a.ownSeq) .. MsgTailOf(nums, tiers)
					elseif c.faker then
						text = FakeF(c)
					else
						text = ("F:1:FART:%s:%d:%d:%d"):format(c.guid, 1, 1, a.ownSeq)
					end
					st.f = st.f + 1
					gotF = {}
					Broadcast(c, chans, text, function(m, t, ch, nw, cc)
						if DeliverF(m, t, ch, nw, cc) then gotF[m] = true end
					end, now, "sentF")
					nsent = #chans
				end
			end
			if nsent > 0 and a.ver == 4 then
				CUR = c
				local ok, s = pcall(a.ns.BoardS, now)
				if not ok then Fail(a, s)
				elseif s then
					local sz = #s
					if c.faker then s = FakeS(c) sz = #s(nil) end
					st.s = st.s + 1
					c.sCount = c.sCount + 1
					if sz > st.sMax then st.sMax = sz end
					if sz > 255 then st.sBig = st.sBig + 1 Viol("S>255", c.name .. " " .. sz) end
					Broadcast(c, chans, s, DeliverS, now, "sentS")
					a.sLast = now
					if TIMER then a.tDue = now + T_WAIT + TR() * T_JIT end
				end
			end
		end
		if a.ver == 4 then CUR = c a.ns.BoardOwn("f") end
		c.f = c.f + 1
		-- the sound: everyone with an addon in the same party hears it
		if party then
			for _, m in ipairs(party.members) do
				if m ~= c and m.acct.ver then
					m.l = m.l + 1
					if m.acct.ver == 4 then CUR = m m.acct.ns.BoardOwn("l") end
				end
			end
			-- H: a listener that got the F answers once on PARTY
			if gotF then
				for _, m in ipairs(party.members) do
					local ma = m.acct
					if m ~= c and ma.ver and gotF[m] and not (ma.lastH and now - ma.lastH < 1) then
						ma.lastH = now
						local text = ("H:1:%s:%d:%s"):format(c.guid, a.ownSeq, m.guid)
						if ma.ver == 4 then
							CUR = m
							local nums, tiers = ma.ns.BoardFields()
							text = text .. MsgTailOf(nums, tiers)
						end
						st.h = st.h + 1
						Broadcast(m, { "PARTY" }, text, function(r, t, ch, nw, rep) DeliverH(r, t, ch, nw, rep, c) end, now, "sentH")
					end
				end
			end
		end
	end

	-- ---------------------------------------------------------- one timer tick (cfg.timer)
	-- The timer S: due = the last S (press or timer) + 300 s + 0-60 s. Never in the first 60 s after
	-- login, never in combat, never with the board off. GUILD or the group, one channel per send,
	-- alternate when both. Blocked = look again at the next 15 s tick. No guild + no group = wait for
	-- the next hour (groups only change on the hour here). Same BoardS text, same receive path.
	local function TimerTick(c, now, hourEnd)
		NOWT = now
		local a = c.acct
		local combat = TR() < T_COMBAT
		c.combat = combat
		if combat then a.tDue = now + T_TICK return end
		local chans = {}
		if c.party then chans[#chans + 1] = "PARTY" end
		if c.guild then chans[#chans + 1] = "GUILD" end
		if #chans == 0 then a.tDue = hourEnd return end
		local ch = chans[1]
		if #chans == 2 then
			a.tAlt = not a.tAlt
			ch = a.tAlt and "GUILD" or "PARTY"
		end
		CUR = c
		local ok, s = pcall(a.ns.BoardS, now)
		if not ok then Fail(a, s) a.tDue = now + T_TICK return end
		if not s then a.tDue = now + T_TICK return end
		if a.sLast and now - a.sLast < T_WAIT then Viol("5-timer-gap", ("%s %.0f s after the last S"):format(c.name, now - a.sLast)) end
		if now - a.loginT < T_LOGIN then Viol("5-timer-login", ("%s %.0f s after login"):format(c.name, now - a.loginT)) end
		if a.optDone or c.combat then Viol("5-timer-state", c.name .. (a.optDone and " board off" or " combat")) end
		local sz = #s
		if c.faker then s = FakeS(c) sz = #s(nil) end
		st.s, st.t = st.s + 1, st.t + 1
		c.tCount = c.tCount + 1
		if sz > st.sMax then st.sMax = sz end
		if sz > 255 then st.sBig = st.sBig + 1 Viol("S>255", c.name .. " " .. sz) end
		Broadcast(c, { ch }, s, DeliverS, now, "sentT", nil, TR)
		a.sLast = now
		a.tDue = now + T_WAIT + TR() * T_JIT
	end

	-- ---------------------------------------------------------- day end: checks + metrics
	local holdN = {}   -- char id -> { [day] = clients holding it (same realm clients) }
	local clientsByRealm = {}
	for _, a in ipairs(clients) do clientsByRealm[a.home] = (clientsByRealm[a.home] or 0) + 1 end
	local covPrev
	local function DayEnd(day)
		local B = clients[1] and clients[1].ns.B
		-- truth totals over visible 0.6.4 chars
		local tl, tlr = 0, {}
		for _, c in ipairs(chars) do
			if c.acct.ver == 4 and not c.hid then
				tl = tl + c.l
				tlr[c.realm] = (tlr[c.realm] or 0) + c.l
			end
		end
		local covs, rows, same, cross, errs, ests = {}, {}, {}, {}, {}, {}
		local gridErr = {}
		for ci = 1, #GRID do gridErr[ci] = { ok = 0, n = 0, q = 0, errs = {}, sg = {} } end
		local cp = CP[day] or day == DAYS
		if FAKE and (cp or day <= 3) then   -- faker rows in the top lists (h, l) of the honest clients
			local n1, n10, nc = 0, 0, 0
			for _, a in ipairs(clients) do
				local isF = false
				for _, c in ipairs(a.chars) do if c.faker then isF = true end end
				if not isF and next(a.db.chars) then
					nc = nc + 1
					local in1, in10 = false, false
					for _, k in ipairs({ "h", "l" }) do
						for i, g in ipairs(a.ns.B.Top(a.db, k, 10)) do
							local c = byGuid[g]
							if c and c.faker then in10 = true if i == 1 then in1 = true end end
						end
					end
					if in1 then n1 = n1 + 1 end
					if in10 then n10 = n10 + 1 end
				end
			end
			res.fakeDays = res.fakeDays or {}
			res.fakeDays[#res.fakeDays + 1] = { day = day, top1 = nc > 0 and n1 / nc or 0, top10 = nc > 0 and n10 / nc or 0, clients = nc }
		end
		for _, a in ipairs(clients) do
			local db = a.db
			if next(db.chars) then
				local ns = a.ns
				local Bd = ns.B
				-- own chars
				local ownF, ownH, ownL = 0, 0, 0
				for g, c in pairs(db.chars) do
					local tc = byGuid[g]
					if CHECKS then
						if c.f ~= tc.f or c.h ~= tc.h or c.l ~= tc.l then
							Viol("7-counters", ("%s real %d/%d/%d truth %d/%d/%d"):format(tc.name, c.f, c.h, c.l, tc.f, tc.h, tc.l))
						end
						if (c.hide == 1) ~= tc.hid then Viol("3-hidflag", tc.name .. " real hide " .. c.hide) end
					end
					if c.hide ~= 1 then ownF, ownH, ownL = ownF + c.f, ownH + c.h, ownL + c.l end
				end
				local tf = 0
				for _, c in ipairs(a.chars) do
					if db.chars[c.guid] and not c.hid then tf = tf + c.f end
				end
				if CHECKS and tf ~= ownF then Viol("2-own-alts", ("acct %d own All f %d truth %d"):format(a.id, ownF, tf)) end
				-- entries
				local sumF, sumL, nEnt = ownF, ownL, 0
				local boundF, boundL = tf, 0
				for _, c in ipairs(a.chars) do if db.chars[c.guid] and not c.hid then boundL = boundL + c.l end end
				local acctSum = {}
				local sameL, crossL = 0, 0
				for g, e in pairs(db.board) do
					local tc = byGuid[g]
					if not tc then Viol("1-unknown", "entry for unknown guid " .. g)
					else
						if CHECKS and (e.f > tc.f or e.h > tc.h or e.l > tc.l) then
							Viol("1-entry", ("%s entry %d/%d/%d truth %d/%d/%d at %s"):format(tc.name, e.f, e.h, e.l, tc.f, tc.h, tc.l, a.id))
						end
						if e.hide == 1 then
							a.hidSeen[g] = true
							res.hidEntries = (res.hidEntries or 0) + 1
							if CHECKS and not tc.hid then Viol("3-false-hide", tc.name .. " hidden on a board but not truly hidden") end
						else
							if CHECKS and a.hidSeen[g] then Viol("3-reshown", tc.name .. " shown again after its hide") end
							sumF, sumL, nEnt = sumF + e.f, sumL + e.l, nEnt + 1
							if tc.hid then res.lagShown = (res.lagShown or 0) + 1 else boundF, boundL = boundF + tc.f, boundL + tc.l end
							if tc.hid then boundF, boundL = boundF + tc.f, boundL + tc.l end
							local s = acctSum[tc.acct]
							if not s then s = { 0, 0, 0 } acctSum[tc.acct] = s end
							s[1], s[2], s[3] = s[1] + e.f, s[2] + e.h, s[3] + e.l
							if cp then
								if tc.realm == a.home then sameL = sameL + e.l else crossL = crossL + e.l end
							end
						end
						local hn = holdN[tc.id]
						if not hn then hn = {} holdN[tc.id] = hn end
						if a.home == tc.realm then hn[day] = (hn[day] or 0) + 1 end
					end
				end
				for g, c in pairs(db.chars) do
					local tc = byGuid[g]
					local hn = holdN[tc.id]
					if not hn then hn = {} holdN[tc.id] = hn end
					if a.home == tc.realm then hn[day] = (hn[day] or 0) + 1 end
					if c.hide ~= 1 and cp then
						if tc.realm == a.home then sameL = sameL + c.l else crossL = crossL + c.l end
					end
				end
				if CHECKS then
					for g in pairs(a.gotHide) do
						local e = db.board[g]
						if not e or e.hide ~= 1 then Viol("3-hide-lost", byGuid[g].name .. " hide received, entry shows it again") end
					end
					for ac, s in pairs(acctSum) do
						local tF, tH, tL = 0, 0, 0
						for _, c in ipairs(ac.chars) do tF, tH, tL = tF + c.f, tH + c.h, tL + c.l end
						if s[1] > tF or s[2] > tH or s[3] > tL then Viol("2-alt-sum", ("acct %d seen by %d: %d/%d/%d > %d/%d/%d"):format(ac.id, a.id, s[1], s[2], s[3], tF, tH, tL)) end
					end
					local All = Bd.All(db)
					if All.f ~= sumF or All.l ~= sumL then Viol("1-all-calc", ("All %d/%d vs %d/%d"):format(All.f, All.l, sumF, sumL)) end
					if All.f > boundF or All.l > boundL then Viol("1-all", ("acct %d All f %d l %d > true %d/%d"):format(a.id, All.f, All.l, boundF, boundL)) end
					for _, k in ipairs({ "f", "h", "l" }) do
						for _, g in ipairs(Bd.Top(db, k, 10)) do
							if db.board[g].hide == 1 then Viol("3-top", "hidden char in Top") end
						end
					end
				end
				if EST and CHECKS then
					local w, cpw = db.seenWin, a.win[DEFAULT_CI]
					local same_ = #w == #cpw
					if same_ then for i = 1, #w do if w[i] ~= cpw[i] then same_ = false break end end end
					if not same_ then Viol("est-copy", ("acct %d seenWin %d vs copy %d"):format(a.id, #w, #cpw)) end
				end
				-- metrics
				if tl > 0 then
					local cov = sumL / tl
					covs[#covs + 1] = cov
					rows[#rows + 1] = nEnt + (function() local n = 0 for _ in pairs(db.chars) do n = n + 1 end return n end)()
					if cp then
						local tlh = tlr[a.home] or 0
						local tlo = tl - tlh
						if tlh > 0 then same[#same + 1] = sameL / tlh end
						if tlo > 0 then cross[#cross + 1] = crossL / tlo end
						local tr = cov * 100
						if EST then
							for ci = 1, #GRID do
								local w = a.win[ci]
								local ge = gridErr[ci]
								if #w < 20 then ge.q = ge.q + 1
								else
									local hits = 0
									for i = 1, #w do hits = hits + w[i] end
									local est = math.floor(hits * 100 / #w + 0.5)
									local er = math.abs(est - tr)
									ge.n = ge.n + 1
									if er <= 10 then ge.ok = ge.ok + 1 end
									ge.errs[#ge.errs + 1] = er
									ge.sg[#ge.sg + 1] = est - tr
								end
							end
						end
					end
				end
			end
		end
		local d = { n = #covs, cov = { Pct(covs, 0.5), Pct(covs, 0.1), Pct(covs, 0.9) }, rows = Pct(rows, 0.5) }
		res.days[day] = d
		if cp then
			local c = { same = Pct(same, 0.5), cross = Pct(cross, 0.5), grid = {} }
			for ci, g in ipairs(GRID) do
				local ge = gridErr[ci]
				c.grid[g.key] = { share = ge.n > 0 and ge.ok / ge.n or nil, n = ge.n, q = ge.q, med = Pct(ge.errs, 0.5), bias = Pct(ge.sg, 0.5),
					qshare = (ge.n + ge.q) > 0 and ge.q / (ge.n + ge.q) or nil }
			end
			res.cp[day] = c
		end
	end

	-- faker report at the end
	local function FakerReport()
		local holders, tot, maxRatio, maxAbs, exF, allF, exL, allL, nFakeEnt, atCap = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
		for _, a in ipairs(clients) do
			local honest = true
			if next(a.db.chars) then
				tot = tot + 1
				local any = false
				local All = a.ns.B.All(a.db)
				allF, allL = allF + All.f, allL + All.l
				for g, e in pairs(a.db.board) do
					local tc = byGuid[g]
					if tc and e.hide ~= 1 then
						local xf, xl, xh = math.max(0, e.f - tc.f), math.max(0, e.l - tc.l), math.max(0, e.h - tc.h)
						if xf > 0 or xl > 0 or xh > 0 then
							any = true
							nFakeEnt = nFakeEnt + 1
							exF, exL = exF + xf, exL + xl
							maxAbs = math.max(maxAbs, xf, xl, xh)
							maxRatio = math.max(maxRatio, e.f / math.max(1, tc.f), e.l / math.max(1, tc.l), e.h / math.max(1, tc.h))
							if e.f >= CAP or e.l >= CAP or e.h >= CAP then atCap = atCap + 1 end
						end
					end
				end
				if any then holders = holders + 1 end
			end
		end
		res.fake = { fakers = #fakers, clients = tot, holders = holders, holderShare = tot > 0 and holders / tot or 0,
			fakedEntries = nFakeEnt, maxOverRatio = maxRatio, maxOverAbs = maxAbs, atCap = atCap,
			fakeShareF = allF > 0 and exF / allF or 0, fakeShareL = allL > 0 and exL / allL or 0, cap = CAP, jump = JUMP }
	end

	-- ---------------------------------------------------------- main loop
	local function Poisson(m)
		local L, k, p = math.exp(-m), 0, 1
		repeat k = k + 1 p = p * R() until p <= L
		return k - 1
	end

	local startT = os.clock()
	for day = 1, DAYS do
		-- sessions
		for _, a in ipairs(accts) do
			a.sess = {}
			if R() < 0.6 then
				local nS = R() < 0.35 and 2 or 1
				local used = {}
				for _ = 1, nS do
					local len = 1 + math.floor(R() * 4)
					local st0 = math.floor(R() * 24)
					if st0 + len > 24 then len = 24 - st0 end
					local clash = false
					for h = st0, st0 + len - 1 do if used[h] then clash = true end end
					if not clash and len > 0 then
						for h = st0, st0 + len - 1 do used[h] = true end
						local c = a.main
						if #a.chars > 1 and R() > 0.6 then c = a.chars[1 + math.floor(R() * #a.chars)] end
						a.sess[#a.sess + 1] = { s = st0, e = st0 + len, c = c }
					end
				end
			end
		end
		for hour = 0, 23 do
			local t0 = ((day - 1) * 24 + hour) * 3600
			NOWT = t0
			local online = {}
			for _, a in ipairs(accts) do
				local c
				for _, s in ipairs(a.sess) do if hour >= s.s and hour < s.e then c = s.c end end
				if c ~= a.cur then
					a.cur = c
					if c and a.ver == 4 then   -- login
						CUR = c
						c.combat = false
						a.ns.BoardLogin()
						c.logged = true
						a.loginT = t0
						if TIMER then
							a.tDue = math.max(t0 + T_LOGIN + TR() * T_JIT, (a.sLast or -1e9) + T_WAIT + TR() * T_JIT)
						end
						if a.optDay and day >= a.optDay and not a.optDone then
							a.optDone = true
							a.ns.BoardCmd("off")
						end
						if a.optDone then c.hid = true end
					end
				end
				if c then
					online[#online + 1] = c
					c.party = nil
					if a.ver then a.hours = a.hours + 1 end
				end
			end
			for _, g in ipairs(guilds) do g.online = {} end
			for _, c in ipairs(online) do
				if c.guild and c.acct.ver then local o = c.guild.online o[#o + 1] = c end
			end
			-- parties: ~40% of the online chars, 2-5 each, 80% same realm
			local pool = {}
			for _, c in ipairs(online) do if R() < PSH then pool[#pool + 1] = c end end
			Shuffle(pool)
			while #pool >= 2 do
				local size = 2 + math.floor(R() * 4)
				local seed = table.remove(pool)
				local party = { members = { seed } }
				seed.party = party
				for _ = 2, size do
					if #pool == 0 then break end
					local same = R() < 0.8
					local pick
					for i = #pool, 1, -1 do
						if (pool[i].realm == seed.realm) == same then pick = i break end
					end
					local m = table.remove(pool, pick or #pool)
					party.members[#party.members + 1] = m
					m.party = party
				end
				if #party.members < 2 then seed.party = nil end
			end
			-- presses
			local ev = {}
			for _, c in ipairs(online) do
				local n = Poisson(c.rate / 3)
				for _ = 1, n do
					local t = t0 + R() * 3600
					local burst = 1
					if R() < 0.3 then burst = 2 + math.floor(R() * 3) end
					for b = 1, burst do
						ev[#ev + 1] = { t = t, c = c }
						t = t + 0.3 + R() * 1.2
					end
				end
			end
			table.sort(ev, function(x, y) if x.t ~= y.t then return x.t < y.t end return x.c.id < y.c.id end)
			-- presses and timer ticks in time order (no timer: the press list only, as before)
			local tq = {}
			if TIMER then
				for _, c in ipairs(online) do if c.acct.ver == 4 and not c.acct.optDone then tq[#tq + 1] = c end end
			end
			local hourEnd = t0 + 3600
			local pi = 1
			while true do
				local e = ev[pi]
				local tc, tt
				for _, c in ipairs(tq) do
					local d = c.acct.tDue
					if d and d < hourEnd and (not tt or d < tt) then tc, tt = c, d end
				end
				if e and (not tt or e.t <= tt) then
					pi = pi + 1
					local c = e.c
					c.combat = R() < 0.3
					if topTruth == nil or e.t - (topTruth.t or -1e9) > 3600 then
						if FAKE then
							local tt2 = {}
							for _, x in ipairs(chars) do if x.acct.ver == 4 and not x.faker and not x.hid then tt2[#tt2 + 1] = x end end
							table.sort(tt2, function(p, q) if p.f ~= q.f then return p.f > q.f end return p.id < q.id end)
							topTruth = { t = e.t, tt2[1], tt2[2], tt2[3] }
						else
							topTruth = { t = e.t }
						end
					end
					Press(c, e.t)
				elseif tt then
					TimerTick(tc, tt, hourEnd)
				else
					break
				end
			end
		end
		DayEnd(day)
	end
	res.seconds = os.clock() - startT

	-- ---------------------------------------------------------- final
	-- bytes per online hour
	local sentB, recvB, sentF, sentS, sentH = {}, {}, {}, {}, {}
	local ovF, ovS, ovH, ovT, ovR, ovHrs = 0, 0, 0, 0, 0, 0
	for _, a in ipairs(clients) do
		if a.hours > 0 then
			sentB[#sentB + 1] = (a.sentF + a.sentS + a.sentH + a.sentT) / a.hours
			recvB[#recvB + 1] = a.recvB / a.hours
			ovF, ovS, ovH, ovT, ovR, ovHrs = ovF + a.sentF, ovS + a.sentS, ovH + a.sentH, ovT + a.sentT, ovR + a.recvB, ovHrs + a.hours
		end
	end
	res.bytes = { sentMed = Pct(sentB, 0.5), sentP90 = Pct(sentB, 0.9), recvMed = Pct(recvB, 0.5), recvP90 = Pct(recvB, 0.9),
		sentMean = ovHrs > 0 and (ovF + ovS + ovH + ovT) / ovHrs or 0, recvMean = ovHrs > 0 and ovR / ovHrs or 0,
		F = ovHrs > 0 and ovF / ovHrs or 0, S = ovHrs > 0 and ovS / ovHrs or 0, H = ovHrs > 0 and ovH / ovHrs or 0,
		T = ovHrs > 0 and ovT / ovHrs or 0, tPerHour = ovHrs > 0 and st.t / ovHrs or 0, hours = ovHrs }
	-- top-10 reach
	local reach, unreached, tot10, realmAll = {}, 0, 0, {}
	for r = 1, NREALM do
		local list = {}
		for _, c in ipairs(chars) do if c.realm == r and c.acct.ver == 4 and not c.hid and c.h > 0 then list[#list + 1] = c end end
		table.sort(list, function(a, b) if a.h ~= b.h then return a.h > b.h end return a.id < b.id end)
		local denom = clientsByRealm[r] or 0
		local worst, miss = 0, false
		for i = 1, math.min(10, #list) do
			tot10 = tot10 + 1
			local found
			for d = 1, DAYS do
				if ((holdN[list[i].id] or {})[d] or 0) >= 0.9 * denom then found = d break end
			end
			if found then reach[#reach + 1] = found else unreached = unreached + 1 end
			if found then worst = math.max(worst, found) else miss = true end
		end
		-- the whole top 10 of the realm known by 90% of its clients (nil = not by the last day)
		if #list > 0 then realmAll[#realmAll + 1] = { realm = r, n = math.min(10, #list), clients = denom, day = (not miss) and worst or nil } end
	end
	local nh = 0
	for _, c in ipairs(chars) do if c.hid then nh = nh + 1 end end
	res.world.hiddenChars = nh
	res.top10 = { median = Pct(reach, 0.5), p90 = Pct(reach, 0.9), reached = #reach, total = tot10, unreached = unreached, realms = realmAll }
	if FAKE then FakerReport() end
	-- the boards, as one number: the same number = the same boards everywhere (budget on vs off)
	local hsum = 0
	for ci, a in ipairs(clients) do
		for g, e in pairs(a.db.board) do
			local c = byGuid[g]
			local ts = 0
			if e.t then for i = 1, 7 do ts = ts + (e.t[i] or 0) end end
			local w = ((ci * 7919 + (c and c.id or 0) * 104729) % 1000003) + 1
			hsum = (hsum + w * (e.f * 3 + e.h * 5 + e.l * 7 + ts * 11 + (e.hide or 0) * 13 + 1)) % 35184372088832
		end
	end
	res.boardHash = hsum
	res.bud.cfg = clients[1] and clients[1].ns.B.CFG.bud ~= math.huge and clients[1].ns.B.CFG.bud or -1
	res.bud.new = clients[1] and clients[1].ns.B.CFG.budNew or -1
	if BUDM then   -- the honest need per (client, player): max over the run
		local nA, nB, n0 = {}, {}, {}
		for _, a in ipairs(clients) do
			for g, e in pairs(a.db.board) do
				local c = byGuid[g]
				if c and not c.faker then
					if e.nA then nA[#nA + 1] = e.nA end
					if e.nB then nB[#nB + 1] = e.nB end
					if e.n0 then n0[#n0 + 1] = e.n0 end
				end
			end
		end
		local function Q(l)
			return { n = #l, max = Pct(l, 1), p9999 = Pct(l, 0.9999), p999 = Pct(l, 0.999), p99 = Pct(l, 0.99), p50 = Pct(l, 0.5) }
		end
		res.bud.needA, res.bud.needB, res.bud.first0 = Q(nA), Q(nB), Q(n0)
	end

	-- ---------------------------------------------------------- pass / fail
	local function V(k)
		local n = 0
		for kind, c in pairs(res.viol) do if kind:sub(1, #k) == k then n = n + c end end
		return n
	end
	local function Add(name, ok, info) res.checks[#res.checks + 1] = { name, ok, info } end
	if CHECKS then
		Add("1 never above the truth", V("1-") == 0, V("1-"))
		Add("2 alts counted once", V("2-") == 0, V("2-"))
		Add("3 hidden stay hidden", V("3-") == 0, V("3-"))
		Add("4 S <= 255 bytes", st.sBig == 0, ("max %d"):format(st.sMax))
		local noPress = 0
		for _, c in ipairs(chars) do if c.sCount > c.presses then noPress = noPress + 1 end end
		Add("5 press S <= presses per char", noPress == 0, noPress)
		if TIMER then
			Add("5b timer S: >= 300 s after any S, >= 60 s after login, never off / combat", V("5-") == 0,
				("%d timer S, %d bad"):format(st.t, V("5-")))
		end
		Add("6 old clients: 0 errors, 0 misparse", st.luaErr == 0 and st.mis == 0 and st.parseErr == 0,
			("err %d mis %d parse %d"):format(st.luaErr, st.mis, st.parseErr))
		Add("7 real counters == truth", V("7-") == 0, V("7-"))
		Add("0.6.4 clients: 0 Lua errors", (res.luaErr4 or 0) == 0, res.luaErr4 or 0)
		if EST then Add("est copy (0.05,50) == real seenWin", V("est-copy") == 0, V("est-copy")) end
	end
	local np, nf = 0, 0
	for _, c in ipairs(res.checks) do if c[2] then np = np + 1 else nf = nf + 1 end end
	res.nPass, res.nFail = np, nf
	return res
end

return Run, ToJSON
