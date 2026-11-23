-- Board.lua (0.6.4): base36, merge, S encode/decode, Seen, sums, the addon glue. Run: python -I tools/lua.py board
local pass, fail = 0, 0
local function ok(name, cond, extra)
	if cond then pass = pass + 1
	else fail = fail + 1 print("FAIL " .. name .. (extra and (" :: " .. tostring(extra)) or "")) end
end

local ns = {}
assert(loadfile(ADDON_DIR .. "/Board.lua"))("Spoken_Wind", ns)
local B = ns.B
local function G(i) return ("Player-1-%08X"):format(i) end
local function St() return { chars = {}, board = {}, boardN = 0, seenWin = {} } end
local ME, ALT = G(0xAAAA), G(0xA1A1)

-- ---- base36 + fields
ok("enc 0 1 35 36", B.Enc(0) == "0" and B.Enc(1) == "1" and B.Enc(35) == "z" and B.Enc(36) == "10")
ok("enc cap = lfls", B.Enc(1000000) == "lfls" and B.Dec("lfls") == 1000000)
ok("enc no negatives", B.Enc(-5) == "0" and B.Enc(nil) == "0")
ok("dec bad", B.Dec("") == nil and B.Dec("ABC") == nil and B.Dec("123456") == nil and B.Dec("1.2") == nil and B.Dec(5) == nil)
;(function()
	math.randomseed(7)
	local good = true
	for _ = 1, 2000 do
		local v = math.random(0, 1000000)
		if B.Dec(B.Enc(v)) ~= v then good = false end
	end
	ok("enc/dec round trip", good)
end)()
;(function()
	local a, b, c = B.DecNums("1.2.z")
	ok("nums", a == 1 and b == 2 and c == 35)
	ok("nums bad", B.DecNums("1.2") == nil and B.DecNums("1.2.3.4") == nil and B.DecNums("") == nil and B.DecNums(nil) == nil
		and B.DecNums("1..3") == nil)
	local t = B.DecTiers("0.0.0.0.0.0.1")
	ok("tiers", t and #t == 7 and t[7] == 1 and t[1] == 0)
	ok("tiers bad", B.DecTiers("0.0.0.0.0.0") == nil and B.DecTiers("0.0.0.0.0.0.0.0") == nil
		and B.DecTiers("0.0..0.0.0.0") == nil and B.DecTiers("") == nil)
end)()
ok("short/long", B.Short(ME) == "1-0000AAAA" and B.Long("1-0000AAAA") == ME and B.Short("Creature-0-1-2") == nil
	and B.Long("x") == nil and B.Long("1-0000AAAA,") == nil)
ok("clean name", B.Clean("a,b;c:d|e") == "abcde" and #B.Clean(("x"):rep(30)) == 24 and B.Clean(nil) == "")

-- ---- merge (JUMP + CAP alone: no budget here; the budget has its own block)
;(function()
	local keepBud = B.CFG.bud
	B.CFG.bud = math.huge
	local st = St()
	local g = G(1)
	ok("merge new", B.Merge(st, g, { n = "Ann", r = "R", f = 5, h = 2, l = 3 }, 100, true) == "new"
		and st.board[g].f == 5 and st.board[g].h == 2 and st.board[g].l == 3 and st.board[g].n == "Ann"
		and st.board[g].fh == 1 and st.board[g].at == 100 and st.boardN == 1)
	local same = true
	for i = 1, 5 do
		if B.Merge(st, g, { n = "Ann", r = "R", f = 5, h = 2, l = 3 }, 100 + i, true) ~= "same" then same = false end
	end
	local e = st.board[g]
	ok("same entry 5 times changes nothing", same and e.f == 5 and e.h == 2 and e.l == 3 and st.boardN == 1)
	ok("never down", B.Merge(st, g, { f = 1, h = 0, l = 0 }, 200) == "same" and e.f == 5 and e.h == 2)
	ok("max up", B.Merge(st, g, { f = 10 }, 200) == "up" and e.f == 10 and e.h == 2)
	ok("jump over 10000 ignored", B.Merge(st, g, { f = 10 + 10001 }, 200) == "same" and e.f == 10)
	ok("jump 10000 ok", B.Merge(st, g, { f = 10 + 10000 }, 200) == "up" and e.f == 10010)
	e.f = 999999
	ok("over the cap ignored", B.Merge(st, g, { f = 1000001 }, 200) == "same" and e.f == 999999)
	ok("cap ok", B.Merge(st, g, { f = 1000000 }, 200) == "up" and e.f == 1000000)
	ok("not a number ignored", B.Merge(st, g, { f = "9", h = -1, l = 0 / 0 }, 200) == "same" and e.h == 2 and e.l == 3)
	local g2 = G(2)
	ok("new entry: jump from 0", B.Merge(st, g2, { f = 20000, h = 3 }, 300) == "new" and st.board[g2].f == 0
		and st.board[g2].h == 3)
	ok("hide: higher seq", B.Merge(st, g2, { hide = 1, hs = 2 }, 300) == "up" and st.board[g2].hide == 1 and st.board[g2].hs == 2)
	ok("hide: lower seq ignored", B.Merge(st, g2, { hide = 0, hs = 1 }, 300) == "same" and st.board[g2].hide == 1)
	ok("hide: same seq ignored", B.Merge(st, g2, { hide = 0, hs = 2 }, 300) == "same" and st.board[g2].hide == 1)
	ok("hide: next seq shows", B.Merge(st, g2, { hide = 0, hs = 3 }, 300) == "up" and st.board[g2].hide == 0)
	ok("hide: seq over the cap ignored", B.Merge(st, g2, { hide = 1, hs = 1000001 }, 300) == "same" and st.board[g2].hide == 0)
	B.Char(st, ME)
	ok("own char: never from outside", B.Merge(st, ME, { f = 9 }, 300, true) == "drop" and st.board[ME] == nil
		and st.chars[ME].f == 0)
	ok("bad GUID dropped", B.Merge(st, "Creature-0-1-2", { f = 1 }, 300) == "drop" and B.Merge(st, nil, { f = 1 }, 300) == "drop")
	local g4 = G(4)
	B.Merge(st, g4, { n = "Bob", f = 1 }, 300, false)
	ok("second hand name when none", st.board[g4].n == "Bob" and st.board[g4].fh == nil)
	B.Merge(st, g4, { n = "Bobx", f = 1 }, 300, false)
	ok("second hand never overwrites", st.board[g4].n == "Bob")
	B.Merge(st, g4, { n = "Rob", r = "Nowhere", f = 1 }, 300, true)
	ok("first hand wins", st.board[g4].n == "Rob" and st.board[g4].r == "Nowhere" and st.board[g4].fh == 1)
	B.Merge(st, g4, { n = "Zed", f = 1 }, 300, false)
	ok("second hand never over first hand", st.board[g4].n == "Rob")
	B.Merge(st, g4, { n = "", f = 1 }, 300, true)
	ok("empty name ignored", st.board[g4].n == "Rob")
	ok("tiers: max", B.Merge(st, g4, { t = { 1, 0, 0, 0, 0, 0, 2 } }, 300) == "up" and st.board[g4].t[7] == 2
		and B.Merge(st, g4, { t = { 0, 0, 0, 0, 0, 0, 1 } }, 300) == "same" and st.board[g4].t[7] == 2
		and B.Merge(st, g4, { t = { 0, 0, 0, 0, 0, 0, 5 } }, 300) == "up" and st.board[g4].t[7] == 5, st.board[g4].t[7])
	ok("seen time = last merge", st.board[g4].at == 300)
	B.CFG.bud = keepBud
end)()

-- ---- the raise budget: after the first sight, the sum of an entry may rise at most bud per day since it (+1 day)
;(function()
	local N = B.CFG.bud
	ok("budget: the build value", N == 3000 and B.CFG.budNew == nil and B.CFG.capLog == 30, N)
	ok("budget: no sim hook in the build", B.CFG.budNeed == nil)
	local cuts = {}
	local keepCap = B.OnCap
	B.OnCap = function(g, over) cuts[#cuts + 1] = { g = g, over = over } end
	local st, D, M = St(), 86400, 100
	B.CFG.bud = M   -- the rules with a small budget; the build value further down
	-- the first sight: free (CAP + JUMP only, as before); the budget starts from it
	local g = G(0x51)
	ok("budget: first sight free", B.Merge(st, g, { f = 9000, h = 9000, l = 9000, t = { 9000, 0, 0, 0, 0, 0, 0 } }, 1000) == "new"
		and st.board[g].f == 9000 and st.board[g].h == 9000 and st.board[g].l == 9000 and st.board[g].t[1] == 9000 and #cuts == 0)
	ok("budget: first sight = the start", st.board[g].bt == 1000 and st.board[g].b0 == 36000)
	-- right after: M more (the start day), the rest cut, in the order f, h, l, tiers
	ok("budget: start day = M", B.Merge(st, g, { f = 9060, h = 9030, l = 9020, t = { 9005 } }, 1000) == "up"
		and st.board[g].f == 9060 and st.board[g].h == 9030 and st.board[g].l == 9010 and st.board[g].t[1] == 9000)
	ok("budget: the cut reported (extra)", #cuts == 1 and cuts[1].g == g and cuts[1].over == 10 + 5, cuts[1] and cuts[1].over)
	-- the same second: no room left
	ok("budget: no room = same", B.Merge(st, g, { h = 9100 }, 1000) == "same" and st.board[g].h == 9030 and #cuts == 2
		and cuts[2].over == 70)
	-- one hour: M / 24 more
	local r = math.floor(M * (1 + 1 / 24)) - M
	ok("budget: +1 hour = M / 24", B.Merge(st, g, { h = 9100 }, 1000 + 3600) == "up" and st.board[g].h == 9030 + r and #cuts == 3)
	-- one day: M in all since the start day
	ok("budget: +1 day = M more", B.Merge(st, g, { h = 9130 }, 1000 + D) == "up" and st.board[g].h == 9130 and #cuts == 3)
	ok("budget: +1 day, 1 over = same", B.Merge(st, g, { h = 9131 }, 1000 + D) == "same" and #cuts == 4 and cuts[4].over == 1)
	-- half a day: M / 2 more (the rest cut)
	ok("budget: half a day = M / 2", B.Merge(st, g, { h = 9190 }, 1000 + D + D / 2) == "up"
		and st.board[g].h == 9130 + math.floor(M * 2.5) - 2 * M and cuts[5].over == 60 - (math.floor(M * 2.5) - 2 * M), st.board[g].h)
	-- a quiet week: the credit stays (a catch-up is never cut)
	local g3 = G(0x53)
	B.Merge(st, g3, { f = 1 }, 0)
	local nc = #cuts
	ok("budget: a week of credit", B.Merge(st, g3, { f = 1 + 8 * M }, 7 * D) == "up" and st.board[g3].f == 1 + 8 * M and #cuts == nc)
	-- never down: a lower value is ignored
	ok("budget: a lower value later = same", B.Merge(st, g3, { f = 5 }, 7 * D) == "same" and st.board[g3].f == 1 + 8 * M)
	-- the clock went back: no room from it, no error
	local g4 = G(0x54)
	B.Merge(st, g4, { f = 1 }, 5 * D)
	ok("budget: clock back: start day", B.Merge(st, g4, { f = 1 + M }, 5 * D) == "up" and st.board[g4].f == 1 + M)
	ok("budget: clock back = no new room", B.Merge(st, g4, { f = 1 + M + 5 }, 1 * D) == "same" and st.board[g4].f == 1 + M)
	-- JUMP + CAP still first: a claim over JUMP is ignored, not cut
	nc = #cuts
	ok("budget: over JUMP = ignored, no cut", B.Merge(st, g3, { f = 1 + 8 * M + 10001 }, 30 * D) == "same" and #cuts == nc)
	-- tiers are in the sum
	local g5 = G(0x55)
	B.Merge(st, g5, { f = 1 }, 100)
	ok("budget: tiers count", B.Merge(st, g5, { t = { 0, 0, M + 3, 0, 0, 0, 0 } }, 100) == "up" and st.board[g5].t[3] == M
		and cuts[#cuts].over == 3)
	ok("budget: tiers use the room", B.Merge(st, g5, { t = { 0, 0, M + 5, 0, 0, 0, 0 } }, 100) == "same" and st.board[g5].t[3] == M)
	-- hidden rows: the same budget
	local g6 = G(0x56)
	B.Merge(st, g6, { h = 10, hide = 1, hs = 1 }, 100)
	ok("budget: hidden rows too", B.Merge(st, g6, { h = 10 + 2 * M }, 200) == "up" and st.board[g6].h == 10 + M and st.board[g6].hide == 1)
	-- an entry from before the budget (no bt / b0): starts now from its numbers, nothing cut
	local g7 = G(0x57)
	st.board[g7] = { f = 5 * M, h = 0, l = 0, hide = 0, hs = 0, at = 1 }
	st.boardN = st.boardN + 1
	ok("budget: old entry: kept, M from now", B.Merge(st, g7, { f = 6 * M + 1 }, 400) == "up" and st.board[g7].f == 6 * M
		and st.board[g7].bt == 400 and st.board[g7].b0 == 5 * M)
	B.CFG.bud = N
	-- the build value: an honest player, +N/2 a day for 60 days, seen at random times = never cut
	local g8, v, nc8 = G(0x58), 0, #cuts
	for d = 0, 59 do
		v = v + math.floor(N / 2)
		B.Merge(st, g8, { f = math.floor(v / 3), h = math.floor(v / 3), l = v - 2 * math.floor(v / 3) }, d * D + (d * 7919) % 80000)
	end
	local e8 = st.board[g8]
	ok("budget: honest N/2 a day: never cut", #cuts == nc8 and e8.f + e8.h + e8.l == v, #cuts - nc8)
	-- a faker: +JUMP on every message, 200 messages in 12 h = JUMP (first sight) + 1.5 N at most
	local g9 = G(0x59)
	for i = 1, 200 do
		local e9 = st.board[g9]
		B.Merge(st, g9, { h = (e9 and e9.h or 0) + 10000 }, 1000 + i * 216)
	end
	ok("budget: a faker in 12 h: <= JUMP + 1.5 N", st.board[g9].h <= 10000 + math.floor(N * 1.5) and st.board[g9].h >= 10000 + N,
		st.board[g9].h)
	B.OnCap = keepCap
end)()

-- ---- limit 2000: the oldest seen time goes
;(function()
	local st = St()
	for i = 1, 2001 do B.Merge(st, G(i), { f = 1 }, i) end
	local n = 0
	for _ in pairs(st.board) do n = n + 1 end
	ok("limit 2000", st.boardN == 2000 and n == 2000 and st.board[G(1)] == nil and st.board[G(2)] ~= nil
		and st.board[G(2001)] ~= nil, st.boardN)
	B.Merge(st, G(5000), { f = 1 }, 0)   -- older seen time than all: still kept (just met)
	ok("limit: the new one stays", st.boardN == 2000 and st.board[G(5000)] ~= nil and st.board[G(2)] == nil)
end)()

-- ---- S encode
local function Parts(text)
	local p = {}
	for part in (text:sub(5) .. ";"):gmatch("([^;]*);") do p[#p + 1] = part end
	return p
end
;(function()
	local st = St()
	ok("S: no own entry = nil", B.EncodeS(st, ME, "Me", 1) == nil)
	local c = B.Char(st, ME)
	c.f, c.h, c.l = 3, 1, 40
	local a = B.Char(st, ALT)
	a.f = 99
	local text, n, bytes = B.EncodeS(st, ME, "Me", 1)
	ok("S: own entry only", text == "S:1:1-0000AAAA,Me,3,1,14,00" and n == 0 and bytes == #text, text)
ok("S: own name cleaned", B.EncodeS(st, ME, "M,e;:|x", 1) == "S:1:1-0000AAAA,Mex,3,1,14,00")
	ok("S: own alts never sent", not text:find("A1A1", 1, true))
	ok("S: bad own GUID = nil", B.EncodeS({ chars = { x = c }, board = {} }, "x", "Me", 1) == nil)
	c.hide, c.hs = 1, 3
	text = B.EncodeS(st, ME, "Me", 1)
	ok("S: hidden own = zeros + flag", text == "S:1:1-0000AAAA,Me,0,0,0,13", text)
	c.hide, c.hs = 0, 4
	-- 40 others, no top players: round robin reaches every one in 10 sends
	for i = 1, 40 do B.Merge(st, G(i), { n = "P" .. i }, 10) end
	local seen, twice = {}, false
	for s = 1, 10 do
		local t, k = B.EncodeS(st, ME, "Me", 100 + s, 4)
		local p = Parts(t)
		if k ~= 4 or #p ~= 5 then twice = true end
		for i = 2, #p do
			local g = B.Long(p[i]:match("^([^,]+)"))
			if seen[g] then twice = true end
			seen[g] = true
		end
	end
	local all = 0
	for _ in pairs(seen) do all = all + 1 end
	ok("S: round robin reaches all 40 in 10 sends, none twice", all == 40 and not twice, all)
	ok("S: marks sent", st.board[G(1)].sent ~= nil and st.board[G(1)].sent >= 101)
	-- top players: in more S than the rest
	for i = 1, 5 do st.board[G(i)].h = 50 + i end
	local cnt = {}
	for s = 1, 40 do
		local t = B.EncodeS(st, ME, "Me", 200 + s, 4)
		for _, part in ipairs({ select(2, unpack(Parts(t))) }) do
			local g = B.Long(part:match("^([^,]+)"))
			cnt[g] = (cnt[g] or 0) + 1
		end
	end
	ok("S: top players more often", (cnt[G(1)] or 0) > (cnt[G(20)] or 0) and (cnt[G(20)] or 0) > 0,
		tostring(cnt[G(1)]) .. "/" .. tostring(cnt[G(20)]))
	-- hidden others: zeros + flag, still gossiped (the hide must spread)
	st.board[G(7)].hide, st.board[G(7)].hs, st.board[G(7)].f = 1, 2, 77
	st.board[G(7)].sent = 0
	local t = B.EncodeS(st, ME, "Me", 400, 4)
	ok("S: a hidden other = zeros + flag", t:find(";1-00000007,P7,0,0,0,12", 1, true) ~= nil, t)
	st.board[G(8)].n = "Ei,g;h:t|"
st.board[G(8)].sent = 0
t = B.EncodeS(st, ME, "Me", 401, 4)
ok("S: other names cleaned", t:find(";1-00000008,Eight,", 1, true) ~= nil and select(2, B.DecodeS(t)) == 0, t)
ok("S: hidden left out of the top", (function()
		for _, g in ipairs(B.Top(st, "f", 10)) do if g == G(7) then return false end end
		return true
	end)())
end)()
;(function()   -- top: best first, ties by GUID, n cut, hidden + zero left out
	local st = St()
	st.board[G(1)], st.board[G(2)], st.board[G(3)] = { f = 5 }, { f = 9 }, { f = 9 }
	st.board[G(4)], st.board[G(5)], st.board[G(6)] = { f = 1 }, { f = 50, hide = 1 }, { f = 0 }
	local t = B.Top(st, "f", 3)
	ok("top: order", #t == 3 and t[1] == G(2) and t[2] == G(3) and t[3] == G(1), table.concat(t, " "))
	t = B.Top(st, "f")
	ok("top: no n = all shown", #t == 4 and t[4] == G(4), #t)
end)()
;(function()   -- Board tab data: Rank (top + own row + true rank), SeenText, BoardLines
	local st = St()
	st.chars[ME] = { f = 1, h = 2, l = 0, t = {}, hide = 0, hs = 0, n = "Me", r = "" }
	st.chars[ALT] = { f = 0, h = 99, l = 0, t = {}, hide = 1, hs = 1, n = "Alt", r = "" }
	for i = 1, 12 do st.board[G(i)] = { f = 0, h = i, l = 0, hide = 0, hs = 0, n = "P" .. i, r = "R", at = 100 + i } end
	st.board[G(12)].hide = 1
	local r = B.Rank(st, "h", 10, ME)
	ok("rank: top 10 best first, hidden other left out, own alt in (own screen)", #r == 10 and r[1].n == "Alt" and r[1].own and not r[1].me
		and r[2].n == "P11" and r[2].v == 11 and r[10].n == "P3", r[1].n .. " " .. r[2].n .. " " .. r[10].n)
	ok("rank: own row under the list with its true rank", r.own and r.own.me and r.own.n == "Me" and r.own.v == 2 and r.own.rank == 12,
		r.own and r.own.rank)
	st.chars[ME].h = 500
	r = B.Rank(st, "h", 10, ME)
	ok("rank: own in the top = no own row", r[1].me and r[1].rank == 1 and r.own == nil)
	r = B.Rank(st, "l", 10, ME)
	ok("rank: zeros left out, own row rank 1", #r == 0 and r.own and r.own.rank == 1 and r.own.v == 0)
	ok("rank: no me = no own row", B.Rank(st, "l", 10, nil).own == nil)
	for i = 1, 30 do st.seenWin[i] = 1 end
	ok("seen text: ? even with a number (CFG.seenShow off)", B.Seen(st) == 100 and B.SeenText(st) == "Seen ?")
	B.CFG.seenShow = true
	ok("seen text: the number only when seenShow", B.SeenText(st) == "Seen ~100%")
	B.CFG.seenShow = false
end)()
;(function()   -- size: 12-char names, big numbers: always <= 255 bytes (no budget: the big numbers stay)
	local keepBud = B.CFG.bud
	B.CFG.bud = math.huge
	local st = St()
	local c = B.Char(st, ME)
	c.f, c.h, c.l, c.hs = 1000000, 1000000, 1000000, 1000000
	for i = 1, 30 do B.Merge(st, G(0x10000000 + i), { n = ("Abcdefghijkl"), f = 9999, h = 9999, l = 9999, hs = 99999 }, 1) end
	local worst, nMin = 0, 99
	for s = 1, 20 do
		local t, n, bytes = B.EncodeS(st, ME, "Abcdefghijkl", s, 10)
		worst = math.max(worst, #t)
		nMin = math.min(nMin, n)
		if bytes ~= #t then worst = 999 end
	end
	ok("S: <= 255 bytes with 12-char names, 10 asked", worst <= 255 and nMin >= 4, worst .. " n>=" .. nMin)
	local t = B.EncodeS(st, ME, "Abcdefghijkl", 99, 4)
	ok("S: 4 others fit", #Parts(t) == 5 and #t <= 255, #t)
	-- 24-byte names (the most Clean lets through)
	for _, e in pairs(st.board) do e.n = ("x"):rep(24) end
	t = B.EncodeS(st, ME, ("y"):rep(24), 200, 10)
	ok("S: 24-byte names still <= 255", #t <= 255, #t)
	B.CFG.bud = keepBud
end)()

-- ---- S decode
;(function()
	local list, bad = B.DecodeS("S:1:1-0000AAAA,Me,3,1,14,00;1-00000002,P2,a,b,c,1z")
	ok("decode", list and bad == 0 and #list == 2 and list[1].g == ME and list[1].n == "Me" and list[1].f == 3
		and list[1].l == 40 and list[1].hide == 0 and list[1].hs == 0 and list[2].f == 10 and list[2].hide == 1 and list[2].hs == 35)
	list, bad = B.DecodeS("S:1:1-0000AAAA,Me,3,0,0,00,extra,more;1-00000002,P2,1,1,1,00")
	ok("decode: extra entry fields ignored (later builds)", list and #list == 2 and list[1].f == 3 and bad == 0)
	list, bad = B.DecodeS("S:1:1-0000AAAA,Me,3,0,0,00;garbage;Creature-1,x,1,1,1,00;1-00000003,P3,1,1,1,20;1-00000004,P4,zzzzzz,1,1,00")
	ok("decode: bad entries counted, good kept", list and #list == 1 and bad == 4, bad)
	ok("decode: not S", B.DecodeS("F:1:FART:x:1:0:1") == nil and B.DecodeS(nil) == nil)
	ok("decode: over 255 bytes", B.DecodeS("S:1:" .. ("x"):rep(252)) == nil)
	ok("decode: empty S", select(2, B.DecodeS("S:1:")) == 1)
	-- round trip
	local st = St()
	local c = B.Char(st, ME)
	c.f, c.h, c.l = 12345, 6, 789
	for i = 1, 6 do B.Merge(st, G(i), { n = "P" .. i, f = i, h = i * 2, l = i * 3, hs = i }, 1) end
	local t = B.EncodeS(st, ME, "Me", 2, 4)
	list = B.DecodeS(t)
	local good = list and #list == 5 and list[1].f == 12345 and list[1].l == 789
	for i = 2, #(list or {}) do
		local e = st.board[list[i].g]
		if not (e and e.f == list[i].f and e.h == list[i].h and e.l == list[i].l and e.hs == list[i].hs and e.n == list[i].n) then good = false end
	end
	ok("encode -> decode round trip", good, t)
end)()

-- ---- got S: first hand, merge, Seen
;(function()
	local st = St()
	B.Char(st, ME)
	local n, new, up, drop = B.GotS(st, "S:1:1-00000001,Fake,5,1,2,00;1-00000002,Two,1,1,1,00;1-0000AAAA,Me,9,9,9,00", "Ann-Nowhere", 50)
	local e1 = st.board[G(1)]
	ok("got S: counts", n == 3 and new == 2 and up == 0 and drop == 1, ("%s %s %s %s"):format(n, new, up, drop))
	ok("got S: entry 1 = first hand (the sender's name)", e1.n == "Ann" and e1.r == "Nowhere" and e1.fh == 1 and e1.f == 5)
	ok("got S: entry 2 second hand", st.board[G(2)].n == "Two" and st.board[G(2)].fh == nil)
	ok("got S: own char untouched", st.board[ME] == nil and st.chars[ME].f == 0)
	ok("got S: Seen skips entry 1 + own chars", #st.seenWin == 1 and st.seenWin[1] == 0, #st.seenWin)
	n, new, up = B.GotS(st, "S:1:1-00000001,Fake,5,1,2,00;1-00000002,Two,1,1,1,00", "Ann-Nowhere", 51)
	ok("got S: the same again = nothing new", n == 2 and new == 0 and up == 0 and #st.seenWin == 2 and st.seenWin[2] == 1)
	ok("got S: no sender = no first hand", B.GotS(st, "S:1:1-00000009,Nine,1,1,1,00", nil, 52) == 1
		and st.board[G(9)].n == "Nine" and st.board[G(9)].fh == nil)
	ok("got S: not S", B.GotS(st, "F:1:x", "Ann", 53) == nil)
end)()
;(function()
	local st = St()
	ok("seen: empty = ?", B.Seen(st) == nil)
	for i = 1, 19 do st.seenWin[i] = 1 end
	ok("seen: 19 = ?", B.Seen(st) == nil and select(2, B.Seen(st)) == 19)
	st.seenWin[20] = 0
	ok("seen: 20 = 95%", B.Seen(st) == 95)
	B.Merge(st, G(1), { f = 100, h = 100, l = 100 }, 1)
	st.seenWin = {}
	B.SeenAdd(st, { g = G(1), f = 104, h = 100, l = 100 })
	B.SeenAdd(st, { g = G(1), f = 106, h = 100, l = 100 })
	B.SeenAdd(st, { g = G(1), f = 50, h = 100, l = 100 })
	B.SeenAdd(st, { g = G(2), f = 0, h = 0, l = 0 })
	ok("seen: up 4% = hit, 6% = miss, down = hit, unknown = miss", table.concat(st.seenWin, "") == "1010", table.concat(st.seenWin, ""))
	for _ = 1, 60 do B.SeenAdd(st, { g = G(1), f = 1, h = 1, l = 1 }) end
	ok("seen: window 50", #st.seenWin == 50 and B.Seen(st) == 100)
end)()

-- ---- All: own chars + board, hidden left out, heard = sum of l
;(function()
	local keepBud = B.CFG.bud
	B.CFG.bud = math.huge
	local st = St()
	local c, a = B.Char(st, ME), B.Char(st, ALT)
	c.f, c.h, c.l, c.t[3] = 3, 100, 5, 2
	a.f, a.h, a.l = 4, 200, 6
	B.Merge(st, G(1), { f = 10, h = 1000, l = 7, t = { 0, 0, 1, 0, 0, 0, 0 } }, 20)
	B.Merge(st, G(2), { f = 20, h = 1000, l = 8, hide = 1, hs = 1 }, 10)
	B.Merge(st, G(3), { f = 1, l = 1 }, 30)
	local s = B.All(st)
	ok("all: sums", s.f == 3 + 4 + 10 + 1 and s.l == 5 + 6 + 7 + 1 and s.p == 4, ("%d %d %d"):format(s.f, s.l, s.p))
	ok("all: tiers", s.t[3] == 3)
	ok("all: oldest seen (hidden left out)", s.oldest == 20)
	c.hide = 1
	s = B.All(st)
	ok("all: own hidden char left out", s.f == 4 + 10 + 1 and s.p == 3)
	B.CFG.bud = keepBud
end)()

-- ---- per character: 2 GUIDs of one account send different numbers; S of one never has the other
;(function()
	local st = St()
	local c, a = B.Char(st, ME), B.Char(st, ALT)
	c.f, a.f = 2, 9
	local t1, t2 = B.EncodeS(st, ME, "Me", 1), B.EncodeS(st, ALT, "Alt", 1)
	ok("per char: own numbers only", t1 == "S:1:1-0000AAAA,Me,2,0,0,00" and t2 == "S:1:1-0000A1A1,Alt,9,0,0,00", t1 .. " " .. t2)
	local f1 = B.OwnFields(c)
	local f2 = B.OwnFields(a)
	ok("per char: F fields differ", f1 == "2.0.0" and f2 == "9.0.0")
	c.t[7] = 1
	ok("per char: tiers field", select(2, B.OwnFields(c)) == "0.0.0.0.0.0.1" and select(2, B.OwnFields(a)) == "")
	c.hide = 1
	local n1, t1b = B.OwnFields(c)
	ok("per char: hidden = empty fields", n1 == "" and t1b == "")
end)()

-- ---- the addon glue (fake game)
local slog = {}
ns.SyncLog = function(s) slog[#slog + 1] = s end
local function SN(s) local k = 0 for _, l in ipairs(slog) do if l:find(s, 1, true) then k = k + 1 end end return k end
local combat, clock = false, 5000
UnitGUID = function(u) return u == "player" and ME or nil end
UnitName = function(u) return u == "player" and "Me" or nil end
GetRealmName = function() return "Nowhere" end
InCombatLockdown = function() return combat end
time = function() return clock end
;(function()
	local db = { chars = { bad = { f = 1 }, [ALT] = { f = "x", h = 4, l = -1, t = { 1, 2 }, hide = 1, hs = 2 } },
		board = { [ALT] = { f = 1 }, [G(1)] = { f = 5, n = "", t = { 9, "x" } }, junk = { f = 1 }, [G(2)] = "x" },
		seenWin = { 1, 0, 2, "x", 1 }, boardOff = "yes" }
	ns.BoardInit(db)
	ok("init: bad chars dropped, numbers checked", db.chars.bad == nil and db.chars[ALT].f == 0 and db.chars[ALT].h == 4
		and db.chars[ALT].l == 0 and db.chars[ALT].t[1] == 1 and db.chars[ALT].t[3] == 0 and db.chars[ALT].hide == 1)
	ok("init: board checked (own chars out)", db.board[ALT] == nil and db.board.junk == nil and db.board[G(2)] == nil
		and db.board[G(1)].f == 5 and db.board[G(1)].n == nil and db.board[G(1)].t[2] == 0 and db.boardN == 1)
	ok("init: seen window + off flag", table.concat(db.seenWin, "") == "101" and db.boardOff == false)
	local empty = {}
	ns.BoardInit(empty)
	ok("init: a new save", next(empty.chars) == nil and next(empty.board) == nil and empty.boardN == 0 and #empty.seenWin == 0)
	ok("before login: no S, no fields", ns.BoardS(1) == nil and ns.BoardFields() == "" and ns.BoardMe() == nil)
	ns.BoardOwn("f")
	ok("before login: counters no error", next(empty.chars) == nil)
	empty.board[ME] = { f = 1, h = 0, l = 0 }
	empty.boardN = 1
	ns.BoardLogin()
	local c = empty.chars[ME]
	ok("login: char at 0, name + realm", c and c.f == 0 and c.n == "Me" and c.r == "Nowhere" and c.hide == 0 and c.hs == 0)
	ok("login: own GUID off the board", empty.board[ME] == nil and empty.boardN == 0)
	ns.BoardOwn("f") ns.BoardOwn("f") ns.BoardOwn("h") ns.BoardOwn("l") ns.BoardOwn("zz")
	ok("own counters", c.f == 2 and c.h == 1 and c.l == 1)
	ok("own fields", ns.BoardFields() == "2.1.1")
	-- S: combat, 2 s gap
	combat = true
	ok("S: not in combat", ns.BoardS(10) == nil)
	combat = false
	local t, n, bytes = ns.BoardS(10)
	ok("S: own entry", t == "S:1:1-0000AAAA,Me,2,1,1,00" and n == 0 and bytes == #t, t)
	ok("S: 2 s gap", ns.BoardS(11.9) == nil and ns.BoardS(12) ~= nil)
	-- off / on
	ok("cmd: status", ns.BoardCmd("") == "board on · 1 players · Seen ?", ns.BoardCmd(""))
	ok("cmd: off", ns.BoardCmd("off") == "board off · 0 players · Seen ?" and c.hide == 1 and c.hs == 1 and empty.boardOff == true)
	ok("off: F fields empty", select(1, ns.BoardFields()) == "")
	ok("off: S own entry = zeros + flag", ns.BoardS(20) == "S:1:1-0000AAAA,Me,0,0,0,11")
	ok("cmd: off twice = same seq", ns.BoardCmd("off") and c.hs == 1)
	ok("cmd: on", ns.BoardCmd("on"):find("^board on") and c.hide == 0 and c.hs == 2 and empty.boardOff == false)
	-- received S: same text from the same sender on 2 channels = once
	ns.BoardGotS("S:1:1-00000001,X,5,0,1,00;1-00000002,Y,1,1,1,00", "Ann-Nowhere", 30)
	ns.BoardGotS("S:1:1-00000001,X,5,0,1,00;1-00000002,Y,1,1,1,00", "Ann-Nowhere", 30.1)
	ok("got S: twice in 3 s = once", SN("SYNC recv n=2 new=2 up=0 drop=0") == 1 and #empty.seenWin == 1, SN("SYNC recv"))
	ns.BoardGotS("S:1:1-00000001,X,5,0,1,00;1-00000002,Y,1,1,1,00", "Ann-Nowhere", 34)
	ok("got S: after 3 s counts again", SN("SYNC recv n=2 new=0 up=0 drop=0") == 1 and #empty.seenWin == 2)
	ns.BoardGotS("S:1:junk", "Ann-Nowhere", 40)
	ok("got S: junk = drop count, no error", SN("SYNC recv n=1 new=0 up=0 drop=1") == 1)
	-- first hand from F / H
	ns.BoardFirst(G(3), "Cy-Nowhere", "5.1.2", "")
	ok("first hand: F numbers", empty.board[G(3)].f == 5 and empty.board[G(3)].n == "Cy" and SN("ALL upd g=000003 farts=5 heard=2") == 1)
	ns.BoardFirst(G(3), "Cy-Nowhere", "5.1.2", "")
	ok("first hand: same again = no log", SN("ALL upd g=000003") == 1)
	ns.BoardFirst(G(4), "Di", "", "")
	ok("first hand: hidden (empty) = nothing", empty.board[G(4)] == nil)
	ns.BoardFirst(G(4), "Di", nil, "0.0.0.0.0.0.3")
	ok("first hand: tiers only", empty.board[G(4)] and empty.board[G(4)].t[7] == 3 and empty.board[G(4)].f == 0)
	ns.BoardFirst(ME, "Me-Nowhere", "9.9.9", "")
	ok("first hand: own GUID never", empty.board[ME] == nil and c.f == 2)
	for i = 1, 40 do ns.BoardFirst(G(100 + i), "P" .. i, "1.0.0", "") end
	ok("ALL upd capped per session", SN("ALL upd") == 20, SN("ALL upd"))
	-- tiers: sound tiers from the emote table; Mine from the dex
	ns.EMOTES = { FART = { sounds = { { file = "a", tier = 3 }, { file = "b" }, { file = "c", tier = 9 } } } }
	ns.DEX_ALIAS = { old = "a" }
	empty.dex = { a = { n = 4 }, b = { n = 9 }, c = { n = 2 }, old = { n = 2 }, z = "x" }
	local mine, mn = ns.TiersMine()
	ok("mine tiers from the dex (tier x n, aliases)", mine[3] == 6 and mn == 6 and mine[7] == 0, mn)
	ns.BoardTier("FART", 1) ns.BoardTier("FART", 2) ns.BoardTier("FART", 3) ns.BoardTier("NOPE", 1)
	ok("char tiers: only tiered sounds", c.t[3] == 1 and c.t[7] == 0 and c.t[1] == 0)
	ok("boot fields", ns.BoardBoot():find("^char=2/1/1 all=%d+/%d+/%d+ tiers=0%.0%.6%.0%.0%.0%.0 alltiers=0%.0%.1%.0%.0%.0%.3 board=%d+ hide=0 seen=%? win=2$"),
		ns.BoardBoot())
	-- the raise budget: S rows + first-hand F/H numbers, the cap log (no names, no GUIDs), the counts
	local N = B.CFG.bud
	local c0, o0 = ns.BoardCaps()
	ok("budget: caps start at 0", c0 == 0 and o0 == 0)
	local function Row(i, h) return ("1-%08X,Zed%d,0,%s,0,00"):format(0x7700 + i, i, B.Enc(h)) end
	ns.BoardGotS("S:1:" .. Row(1, 5000) .. ";" .. Row(3, 5000), "Zed1-Nowhere", 100)
	ok("budget: S first sight free", empty.board[G(0x7701)].h == 5000 and empty.board[G(0x7703)].h == 5000 and SN("S cap") == 0)
	ns.BoardGotS("S:1:" .. Row(1, 5000 + N + 9), "Zed1-Nowhere", 101)
	ok("budget: S own row cut", empty.board[G(0x7701)].h == 5000 + N and SN("S cap who=1 over=9") == 1, SN("S cap"))
	ns.BoardGotS("S:1:" .. Row(2, 5) .. ";" .. Row(3, 5000 + N + 4), "Zed2-Nowhere", 110)
	ok("budget: S second-hand row cut", empty.board[G(0x7703)].h == 5000 + N and SN("S cap who=2 over=4") == 1)
	ns.BoardFirst(G(0x7701), "Zed1-Nowhere", "0." .. B.Enc(5000 + N + 20) .. ".0", "")
	ok("budget: F numbers cut, the same who", empty.board[G(0x7701)].h == 5000 + N and SN("S cap who=1 over=20") == 1)
	local c1, o1 = ns.BoardCaps()
	ok("budget: caps counted", c1 == 3 and o1 == 9 + 4 + 20, c1 .. " " .. o1)
	for i = 10, 50 do
		ns.BoardGotS("S:1:" .. Row(i, 1), "Zed" .. i .. "-Nowhere", 200 + i * 4)
		ns.BoardGotS("S:1:" .. Row(i, 2 + N), "Zed" .. i .. "-Nowhere", 201 + i * 4)
	end
	ok("budget: cap log max 30 lines", SN("S cap who=") == 30 and select(1, ns.BoardCaps()) == 3 + 41, SN("S cap who="))
	local clean = true
	for _, l in ipairs(slog) do
		if l:find("S cap", 1, true) and (l:find("Zed", 1, true) or l:find("770", 1, true) or l:find("Player", 1, true)
			or not l:match("^S cap who=%d+ over=%d+$")) then clean = false end
	end
	ok("budget: cap lines: no name, no GUID", clean)
	-- a reload keeps the budget (bt, b0); junk dropped
	local keep = {}
	for k, v in pairs(empty.board[G(0x7701)]) do keep[k] = v end
	local re = { board = { [G(0x7701)] = keep, [G(0x7702)] = { f = 1, bt = "x", b0 = -5 } } }
	ns.BoardInit(re)
	ok("budget: reload keeps bt + b0", re.board[G(0x7701)].bt == clock and re.board[G(0x7701)].b0 == 5000
		and re.board[G(0x7702)].bt == nil and re.board[G(0x7702)].b0 == nil)
	ok("budget: reload resets the session counts", select(1, ns.BoardCaps()) == 0)
	ns.BoardInit(empty)
	-- a new char with the board off: hidden from the start
	empty.boardOff = true
	UnitGUID = function(u) return u == "player" and ALT or nil end
	ns.BoardLogin()
	ok("login: off = the new char hidden", empty.chars[ALT].hide == 1 and empty.chars[ALT].hs == 1 and empty.chars[ME].hide == 0)
	ok("boot: off = hide=1", ns.BoardBoot():find(" hide=1 seen=", 1, true) ~= nil, ns.BoardBoot())
end)()

-- ---- static: S goes out only from the key press or the timer; no relay; no game sends in Board.lua
;(function()
	local function Read(f) local h = assert(io.open(ADDON_DIR .. "/" .. f, "rb")) local s = h:read("*a") h:close() return s end
	local sync, board = Read("Sync.lua"), Read("Board.lua")
	local n = 0
	for _ in sync:gmatch("ns%.BoardS%(") do n = n + 1 end
	for _ in sync:gmatch("ns%.BoardS,") do n = n + 1 end
	local a, z = sync:find("local function OnOwnEmote", 1, true), sync:find("ns.SyncOwnEmote = OnOwnEmote", 1, true)
	local ta, tz = sync:find("local function TimerTick", 1, true), sync:find("function ns.SyncTimerStart", 1, true)
	local at1 = sync:find("pcall(ns.BoardS,", 1, true)
	local at2 = at1 and sync:find("pcall(ns.BoardS,", at1 + 1, true)
	ok("static: S only from the key press or the timer (2 BoardS calls)", n == 2 and a and z and ta and tz and at1 and at2
		and at1 > a and at1 < z and at2 > ta and at2 < tz, n)
	-- the timer: GUILD + group only, never WHISPER / SAY / YELL / CHANNEL, never the test whisper
	local ca = sync:find("local function TimerChannels", 1, true)
	local ce = ca and sync:find("\r?\nend\r?\n", ca)
	local chans = ca and ce and sync:sub(ca, ce) or ""
	local tick = ta and tz and sync:sub(ta, tz) or ""
	ok("static: timer channels = group + GUILD only", #chans > 50 and chans:find('"GUILD"', 1, true) and chans:find('"PARTY"', 1, true)
		and not chans:find("WHISPER", 1, true) and not chans:find('"SAY"', 1, true) and not chans:find('"YELL"', 1, true)
		and not chans:find('"CHANNEL"', 1, true) and not chans:find("TestWhisper", 1, true))
	ok("static: timer tick: no whisper, no target", #tick > 200 and not tick:find("WHISPER", 1, true) and not tick:find("TestWhisper", 1, true)
		and tick:find("SendOne(fn, s, ch)", 1, true) and not tick:find("[^%w]Channels%(%)"))
	local sa = sync:find('if text:sub(1, 4) == "S:1:" then', 1, true)
	local se = sa and sync:find("\r?\n\t\treturn\r?\n\tend", sa)
	local branch = sa and se and sync:sub(sa, se) or ""
	ok("static: S receive never sends", #branch > 50 and not branch:find("Send", 1, true) and not branch:find("C_Timer", 1, true))
	ok("static: Board.lua sends nothing, no timers", not board:find("SendAddonMessage", 1, true) and not board:find("C_Timer", 1, true)
		and not board:find("SendChatMessage", 1, true) and not board:find("SetCVar", 1, true))
	for _, f in ipairs({ "Core.lua", "Heard.lua", "Collection.lua", "TestMode.lua", "Options.lua", "Achievements.lua" }) do
		ok("static: no BoardS in " .. f, not Read(f):find("BoardS", 1, true))
	end
end)()

print(("board: %d pass, %d fail"):format(pass, fail))
if fail > 0 then error("board tests failed") end
