-- Pick.lua: random, never the same twice in a row. Run: python -I tools/lua.py pick
local pass, fail = 0, 0
local function ok(name, cond, extra)
	if cond then pass = pass + 1
	else fail = fail + 1 print("FAIL " .. name .. (extra and (" :: " .. tostring(extra)) or "")) end
end

local ns = {}
assert(loadfile(ADDON_DIR .. "/Pick.lua"))("Spoken_Wind", ns)

math.randomseed(12345)
local N, RUNS = 14, 70000
local p = ns.NewPicker(N)
local count, prev, repeats, outside = {}, nil, 0, 0
for _ = 1, RUNS do
	local k = p()
	if k == prev then repeats = repeats + 1 end
	if k < 1 or k > N or k ~= math.floor(k) then outside = outside + 1 end
	count[k] = (count[k] or 0) + 1
	prev = k
end
ok("never twice in a row", repeats == 0, repeats)
ok("always 1..N", outside == 0, outside)
local lo, hi = math.huge, 0
for i = 1, N do lo = math.min(lo, count[i] or 0) hi = math.max(hi, count[i] or 0) end
ok("every fart used", lo > 0)
ok("fair: each within 10% of even", lo > RUNS / N * 0.9 and hi < RUNS / N * 1.1, lo .. ".." .. hi)

-- edges
local one = ns.NewPicker(1)
ok("n=1 gives 1", one() == 1 and one() == 1)
local two = ns.NewPicker(2)
local a = two()
local alt = true
for _ = 1, 50 do local b = two() if b == a then alt = false end a = b end
ok("n=2 alternates", alt)

-- uses the rand it is given (rand(m) = 1..m), so no hidden state
local calls = {}
local fixed = ns.NewPicker(5, function(m) calls[#calls + 1] = m return m end)
ok("first pick from all", fixed() == 5 and calls[1] == 5)
ok("next pick skips last", fixed() == 4 and calls[2] == 4)
local low = ns.NewPicker(5, function() return 1 end)
ok("low rand", low() == 1 and low() == 2 and low() == 1)

print(("pick: %d pass, %d fail"):format(pass, fail))
if fail > 0 then error("pick tests failed") end
