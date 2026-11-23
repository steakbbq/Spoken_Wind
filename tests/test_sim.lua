-- Gossip simulator, SMALL mode: 50 characters, 7 days, every character has the addon, fixed seed.
-- Runs the real Board.lua; asserts the board rules (never above the truth, alts once, hidden stay
-- hidden, S <= 255 bytes, old clients unharmed, counters == truth). Full mode: python tools/sim/run.py
local Run = assert(loadfile(ROOT .. "/tools/sim/sim.lua"))()
local r = Run({ chars = 50, days = 7, users = 50, realms = 2, seed = 4, forceOpt = true, opt = 0.1,
	checkpoints = { 1, 7 } })
local bad = {}
for _, c in ipairs(r.checks) do
	if not c[2] then
		bad[#bad + 1] = c[1] .. " (" .. tostring(c[3]) .. ")"
		for kind, list in pairs(r.details) do bad[#bad + 1] = kind .. ": " .. table.concat(list, " | ") end
	end
end
if (r.hidEntries or 0) == 0 then bad[#bad + 1] = "no hide ever reached a board (test too weak)" end
local d7 = r.days[7]
print(("sim: %d pass, %d fail (%d chars, %d clients, S %d, F %d, H %d, cov d7 %.0f%%, S max %d B)"):format(
	r.nPass, r.nFail, r.world.chars, r.world.clients, r.stats.s, r.stats.f, r.stats.h,
	100 * (d7 and d7.cov[1] or 0), r.stats.sMax))
if #bad > 0 then error("sim FAIL: " .. table.concat(bad, "; ")) end
-- the timer S: the same checks + 5b (gap, login, off, combat), and it really sends
local t = Run({ chars = 50, days = 7, users = 50, realms = 2, seed = 4, forceOpt = true, opt = 0.1,
	checkpoints = { 1, 7 }, timer = true })
local badT, has5b = {}, false
for _, c in ipairs(t.checks) do
	if c[1]:sub(1, 2) == "5b" then has5b = true end
	if not c[2] then
		badT[#badT + 1] = c[1] .. " (" .. tostring(c[3]) .. ")"
		for kind, list in pairs(t.details) do badT[#badT + 1] = kind .. ": " .. table.concat(list, " | ") end
	end
end
if not has5b then badT[#badT + 1] = "no timer check (5b)" end
if (t.stats.t or 0) == 0 then badT[#badT + 1] = "the timer sent no S" end
if (t.hidEntries or 0) == 0 then badT[#badT + 1] = "timer run: no hide ever reached a board" end
local t7 = t.days[7]
print(("sim timer: %d pass, %d fail (timer S %d of S %d, cov d7 %.0f%% vs %.0f%% press only)"):format(
	t.nPass, t.nFail, t.stats.t, t.stats.s, 100 * (t7 and t7.cov[1] or 0), 100 * (d7 and d7.cov[1] or 0)))
if #badT > 0 then error("sim timer FAIL: " .. table.concat(badT, "; ")) end
