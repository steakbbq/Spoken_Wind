-- Spoken Wind: random farts (0.6.6, the owner's rules for this one feature, 2026-11-22).
-- HOURLY: ONE real /fart at a random time: MIN + 0..SPAN s (45-75 min) after login or after your
--   last own /fart (random or not). On by default. Off: Options "Random farts" or
--   /wind random off (also off with Sound Off). Max one per wait: it fires, then a new wait.
-- WAKE-UP: you leave a sleeping bag (the bag aura goes, alive) = ONE /fart WAKE_MIN-WAKE_MAX s
--   later. AFK, a cast, stealth, the login 60 s or the target check in the way = try again every
--   RETRY s until WAKE_END s after the wake-up, then drop it. The campfire does not stop it.
-- FART ATTACK: ATK_P % of the wake-ups. A rumble line (chat type EMOTE, one text per race), then
--   ATK_MIN-ATK_MAX farts: the first LEAD_MIN-LEAD_MAX s after the rumble, then GAP_MIN-GAP_MAX s
--   apart. SIGH_MIN-SIGH_MAX s after the last fart: the game's /sigh. Any reason against a step =
--   the attack ends there (no more farts, no sigh).
-- At no one: DoEmote("FART", "none"), never at your target. Its own chat line is checked once:
--   the line names your target = from then on no random fart while you have a target (why=target).
-- Hourly never: first 60 s after login, dead / a ghost / feign death, AFK, stealthed, casting,
--   a cinematic / movie / loading screen, the logout timer, in a sleeping bag, at a campfire (its
--   aura + CAMP_GRACE s), while a wake-up runs. Combat is OK. Not now = look again next 15 s tick.
-- The client blocks one of our calls (ADDON_ACTION_BLOCKED / _FORBIDDEN, or an error) = no more
--   random farts this session. Never a second way around a block.
-- It plays, syncs and counts like your own /fart (F + S, Sync.lua; Farts, board, achievements).
-- Logs (sync ring, max LOG_MAX per session, no names, no GUIDs): RAND on due=N, RAND fart n=N,
--   RAND wake due=N, RAND wake wait why=X, RAND wake fart n=N, RAND attack n=N, RAND rumble race=X,
--   RAND sigh, RAND echo tgt=0|1 had=0|1,
--   RAND skip why=off|login|dead|afk|stealth|cast|cine|logout|bag|camp|wake|target|block|noapi|err.
--   Aura probe (own cap PROBE_MAX, log only): RAND aura +ID name / RAND aura -ID, for the bag,
--   campfire and rest auras only (spell ID + spell name). SYNC SUM ... rfart=N (Sync.lua).
--   Aura data the game hides (a secret value, 0.7.1): that event is skipped (no probe, no aura check,
--   so no fart from it); one RAND aura secret line per session; SYNC SUM ... rsec=N.
local ADDON, ns = ...

local R = { min = 2700, span = 1800, tick = 15, login = 60, take = 3, logMax = 60,
	wakeMin = 5, wakeMax = 50, wakeEnd = 60, retry = 1,
	atkP = 5, atkMin = 3, atkMax = 6, gapMin = 2, gapMax = 5, leadMin = 3, leadMax = 8, sighMin = 2, sighMax = 4,
	bag = 429960, camp = 1229739, campGrace = 10, logoutMax = 30, probeMax = 30,
	probeIds = { [429959] = true, [429960] = true, [429961] = true, [1229739] = true },
	probeWords = { "camp", "fire", "bag", "sleep", "rest", "cozy" },
	unit = { UNIT_AURA = true },   -- Core registers these for the player only
	events = { "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "CINEMATIC_START", "CINEMATIC_STOP",
		"PLAY_MOVIE", "STOP_MOVIE", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
		"UNIT_AURA", "PLAYER_CAMPING", "PLAYER_QUITING", "LOGOUT_CANCEL" } }
ns.RAND = R

-- The rumble line before a fart attack. Chat type EMOTE: the game puts the name in front.
-- One per race (the UnitRace token); another race gets the plain line.
local RUMBLE = {
	Human = "feels a sudden rumble in their tummy. Too much Goldshire stew?",
	Dwarf = "feels a sudden rumble in their tummy. That last ale is fighting back.",
	NightElf = "feels a sudden rumble in their tummy. Ten thousand years of moonberries, all at once.",
	Gnome = "feels a sudden rumble in their tummy. Pressure gauge: red.",
	Orc = "feels a sudden rumble in their tummy. The war drums sound from within.",
	Scourge = "feels a sudden rumble in what is left of their tummy.",
	Tauren = "feels a sudden rumble in their tummy. The plains grass is moving on.",
	Troll = "feels a sudden rumble in their tummy. Da spirits be restless, mon.",
	Skyborne = "feels a sudden rumble in their tummy. A storm front is coming in.",
	other = "feels a sudden rumble in their tummy.",
}
R.rumble = RUMBLE

local db
local ticker, loginT, due, stopped, firing, firedT, pend
local nRand, nLog, lastWhy = 0, 0, nil
local cine = {}   -- "cin" | "movie" | "load" -> true while on screen
local tgtName     -- the target's name at the last random fart: the echo check only (never saved, never logged)
local bagOn, campOn, campT, logT   -- aura state (a hidden answer keeps the last one); campfire last seen; logout start
local wk, seq = nil, 0   -- the wake-up that runs; seq: a new one (or its end) = its old timers do nothing
local nProbe, probeSeen, probeGone, probeInst = 0, {}, {}, {}
local nHid = 0   -- aura events with hidden (secret) data, skipped

local function Secret(v) return issecretvalue and issecretvalue(v) end

local function Sink(s)
	if ns.SyncLog then ns.SyncLog(s) elseif ns.Log then ns.Log(s) end
end

local function Log(s)
	if nLog >= R.logMax then return end
	nLog = nLog + 1
	Sink(s)
end

local function Arm(now)
	due = now + R.min + math.random(0, R.span)
	lastWhy = nil
end

-- The wake-up ends (why = nil: it is done).
local function End(why)
	wk, seq = nil, seq + 1
	if why then Log("RAND skip why=" .. why) end
end

local function Stop(why, err)
	stopped, due = true, nil
	wk, seq = nil, seq + 1
	Log("RAND skip why=" .. why)
	if err ~= nil then Log("ERR rand " .. tostring(err):sub(1, 80)) end
end

-- A game check: true when it says yes. A hidden (secret) answer counts as yes: skip, never guess.
local function Yes(fn, ...)
	if type(fn) ~= "function" then return false end
	local v = fn(...)
	if Secret(v) then return true end
	return v ~= nil and v ~= false
end

-- The player has this aura: true / false; nil = the game hides the answer (keep the last state).
local function Aura(id)
	local hide = C_Secrets and C_Secrets.ShouldAurasBeSecret
	if type(hide) == "function" then
		local okH, h = pcall(hide)
		if okH and (Secret(h) or h) then return nil end
	end
	local fn = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID or GetPlayerAuraBySpellID
	if type(fn) ~= "function" then return false end
	local ok, a = pcall(fn, id)
	if not ok then return false end
	if Secret(a) then return nil end
	return a ~= nil
end

-- Reasons that end a wake-up (and stop the hourly fart).
local function Hard(now)
	if not (db.random and db.on) then return "off" end
	if Yes(UnitIsDeadOrGhost, "player") or Yes(UnitIsFeignDeath, "player") then return "dead" end
	if next(cine) or Yes(InCinematic) or Yes(IsInCinematicScene) then return "cine" end
	if logT and now - logT < R.logoutMax then return "logout" end
	if bagOn then return "bag" end
	return nil
end

-- Reasons to wait a little (the wake-up fart tries again; the hourly one waits for the next tick).
local function Soft(now)
	if now - loginT < R.login then return "login" end
	if Yes(UnitIsAFK, "player") then return "afk" end
	if Yes(IsStealthed) then return "stealth" end
	if Yes(UnitCastingInfo, "player") or Yes(UnitChannelInfo, "player") then return "cast" end
	if db.randTgt and Yes(UnitExists, "target") then return "target" end
	return nil
end

-- Hourly: why not now (nil = go).
local function Why(now)
	local why = Hard(now) or Soft(now)
	if why then return why end
	if campOn or (campT and now - campT < R.campGrace) then return "camp" end
	if wk then return "wake" end
	return nil
end

-- One game call of ours (the fart, the rumble line, the sigh). false = blocked: stop for the session.
local function Call(now, fn, ...)
	firing, firedT = true, now
	local ok, err = pcall(fn, ...)
	firing = false
	if stopped then return false end   -- the block event came during the call
	if not ok then Stop("block", err) return false end
	return true
end

local function Fire(now, kind)
	tgtName = nil
	local had = Yes(UnitExists, "target")
	if had and UnitName then
		local n = UnitName("target")
		if type(n) == "string" and n ~= "" and not Secret(n) then tgtName = n end
	end
	if not Call(now, DoEmote, "FART", "none") then return false end
	nRand = nRand + 1
	pend = { t = now, had = had }
	Arm(now)
	Log((kind == "wake" and "RAND wake fart n=%d" or "RAND fart n=%d"):format(nRand))
	return true
end

-- A wake-up step after s seconds (only if this wake-up still runs then).
local function Later(s, fn)
	local my = seq
	C_Timer.After(s, function()
		if my ~= seq or stopped or not wk then return end
		local ok, err = pcall(fn, GetTime())
		if not ok then Stop("err", err) end
	end)
end

local Poll

-- The fart attack: each fart, then the sigh.
local function SighGo(now)
	Poll(now)
	if not wk then return end
	local why = Hard(now) or Soft(now)
	if why then End(why) return end
	if Call(now, DoEmote, "SIGH", "none") then
		Log("RAND sigh")
		End(nil)
	end
end

local function AtkGo(now)
	Poll(now)
	if not wk then return end
	local why = Hard(now) or Soft(now)
	if why then End(why) return end
	if not Fire(now, "atk") then return end
	wk.left = wk.left - 1
	if wk.left > 0 then
		Later(math.random(R.gapMin, R.gapMax), AtkGo)
	else
		Later(math.random(R.sighMin, R.sighMax), SighGo)
	end
end

local function Rumble(now)
	local race = "other"
	if UnitRace then
		local ok, _, tok = pcall(UnitRace, "player")
		if ok and type(tok) == "string" and not Secret(tok) and RUMBLE[tok] then race = tok end
	end
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	if type(send) ~= "function" then End("noapi") return false end
	if not Call(now, send, RUMBLE[race], "EMOTE") then return false end
	Log("RAND rumble race=" .. race)
	return true
end

-- The wake-up fart (or the start of a fart attack).
local function WakeGo(now)
	Poll(now)
	if not wk then return end
	local why = Hard(now)
	if why then End(why) return end
	why = Soft(now)
	if why then
		if now - wk.t0 >= R.wakeEnd then End(why) return end
		if why ~= wk.why then
			wk.why = why
			Log("RAND wake wait why=" .. why)
		end
		Later(R.retry, WakeGo)
		return
	end
	if not wk.atk then
		if Fire(now, "wake") then End(nil) end
		return
	end
	wk.left = math.random(R.atkMin, R.atkMax)
	Log(("RAND attack n=%d"):format(wk.left))
	if not Rumble(now) then return end
	Later(math.random(R.leadMin, R.leadMax), AtkGo)
end

-- You left the sleeping bag.
local function Wake(now)
	if stopped or not loginT then return end
	local why = Hard(now)
	if why then Log("RAND skip why=" .. why) return end
	seq = seq + 1
	wk = { t0 = now, atk = math.random(1, 100) <= R.atkP }
	local d = math.random(R.wakeMin, R.wakeMax)
	Log(("RAND wake due=%d"):format(d))
	Later(d, WakeGo)
end

-- Bag and campfire state from the auras (each aura change, each tick, each wake-up step).
Poll = function(now)
	local b = Aura(R.bag)
	if b == true and not bagOn then
		bagOn = true
		if wk then End("bag") end   -- back in the bag: no fart for the last wake-up
	elseif b == false and bagOn then
		bagOn = false
		Wake(now)
	end
	local c = Aura(R.camp)
	if c == true then
		campOn, campT = true, now
	elseif c == false and campOn then
		campOn, campT = false, now
	end
end

-- Aura data the game hides (a secret value): state unknown. One log line per session.
local function Hidden()
	nHid = nHid + 1
	if nHid == 1 then Log("RAND aura secret") end
	return true
end

-- Log only: which auras this client uses for the bag, the campfire and rest (spell ID + spell name).
-- Returns true when the game hides the data (a secret value): the caller skips this event.
local function Probe(info)
	if Secret(info) then return Hidden() end
	if type(info) ~= "table" then return false end
	local added, removed = info.addedAuras, info.removedAuraInstanceIDs
	if Secret(added) or Secret(removed) then return Hidden() end
	if nProbe >= R.probeMax then return false end
	if type(added) == "table" then
		for _, a in ipairs(added) do
			local id, name, inst
			if type(a) == "table" and not Secret(a) then id, name, inst = a.spellId, a.name, a.auraInstanceID end
			if type(id) == "number" and not Secret(id) and not Secret(name) and not Secret(inst) then
				name = type(name) == "string" and name or ""
				local hit = R.probeIds[id]
				local low = name:lower()
				for _, w in ipairs(R.probeWords) do if low:find(w, 1, true) then hit = true end end
				if hit then
					if inst then probeInst[inst] = id end
					if not probeSeen[id] and nProbe < R.probeMax then
						probeSeen[id], nProbe = true, nProbe + 1
						Sink(("RAND aura +%d %s"):format(id, name:sub(1, 40)))
					end
				end
			end
		end
	end
	if type(removed) == "table" then
		for _, inst in ipairs(removed) do
			local id = not Secret(inst) and probeInst[inst]
			if id then
				probeInst[inst] = nil
				if not probeGone[id] and nProbe < R.probeMax then
					probeGone[id], nProbe = true, nProbe + 1
					Sink(("RAND aura -%d"):format(id))
				end
			end
		end
	end
	return false
end

-- The 15 s tick: the auras; nothing before the due time; then the first tick with no reason fires.
local function Tick()
	if stopped or not db then return end
	local now = GetTime()
	Poll(now)
	if not due or now < due then return end
	local why = Why(now)
	if why then
		if why ~= lastWhy then
			lastWhy = why
			Log("RAND skip why=" .. why)
		end
		return
	end
	Fire(now, "hour")
end

-- ------------------------------------------------------------ Core / Sync / Options
-- ADDON_LOADED. db.randTgt: true only after an echo named the target.
function ns.RandInit(saved)
	db = saved
	if db.randTgt ~= true then db.randTgt = nil end
end

-- PLAYER_LOGIN (once per UI load): the 15 s ticker, the aura state, the first wait.
function ns.RandLogin()
	if not db or loginT then return end
	loginT = GetTime()
	if type(DoEmote) ~= "function" then Stop("noapi") return end
	if not (C_Timer and C_Timer.NewTicker and C_Timer.After) then Stop("noapi") return end
	ticker = C_Timer.NewTicker(R.tick, function()
		local ok, err = pcall(Tick)
		if not ok then Stop("err", err) end
	end)
	Poll(loginT)
	if db.random then
		Arm(loginT)
		Log(("RAND on due=%d"):format(due - loginT))
	else
		Log("RAND skip why=off")
	end
end

-- db.random changed (Options or /wind random): on = a new wait from now; off = no wait.
function ns.RandOpt()
	if stopped or not loginT then return end
	if db.random then
		local now = GetTime()
		Arm(now)
		Log(("RAND on due=%d"):format(due - now))
	else
		due = nil
		Log("RAND skip why=off")
	end
end

-- Sync's emote hook: true only inside one of our own calls (the random fart's DoEmote).
function ns.RandNow() return firing == true end

-- Core: your own /fart line that is not a random one = a new wait from now.
function ns.RandReset(now)
	if stopped or not due then return end
	Arm(now)
end

-- Core: is this own FART line a random fart? o = Sync's record of the press (nil = no hook ran:
-- then a line within TAKE s of the random fart). Logs the echo check once.
function ns.RandTake(now, text, o)
	local isRand
	if o then isRand = o.rand == true else isRand = pend ~= nil and now - pend.t <= R.take end
	if not isRand then return false end
	local had = pend ~= nil and pend.had
	pend = nil
	local tgt = tgtName ~= nil and type(text) == "string" and not Secret(text) and text:find(tgtName, 1, true) ~= nil
	tgtName = nil
	Log(("RAND echo tgt=%d had=%d"):format(tgt and 1 or 0, had and 1 or 0))
	if tgt then db.randTgt = true end
	return true
end

-- Core's event frame: blocks, cinematics, the player's auras, the logout timer.
function ns.RandEvent(event, a1, a2)
	if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		if a1 ~= ADDON then return end
		if ns.ArtEvent then pcall(ns.ArtEvent, a2) end   -- the Artifact line (Shart.lua)
		if stopped then return end
		local fn = type(a2) == "string" and not Secret(a2) and a2 or ""
		if firing or (firedT and GetTime() - firedT <= R.take) or fn:find("Emote") then Stop("block") end
	elseif event == "UNIT_AURA" then
		if a1 ~= "player" then return end
		if Probe(a2) then return end   -- hidden aura data: state unknown, no aura check this time (no fart)
		if loginT and not stopped then Poll(GetTime()) end
	elseif event == "PLAYER_CAMPING" or event == "PLAYER_QUITING" then logT = GetTime()
	elseif event == "LOGOUT_CANCEL" then logT = nil
	elseif event == "CINEMATIC_START" then cine.cin = true
	elseif event == "CINEMATIC_STOP" then cine.cin = nil
	elseif event == "PLAY_MOVIE" then cine.movie = true
	elseif event == "STOP_MOVIE" then cine.movie = nil
	elseif event == "LOADING_SCREEN_ENABLED" then cine.load = true
	elseif event == "LOADING_SCREEN_DISABLED" then cine.load = nil
	end
end

-- The Artifact line (Shart.lua): why not now (dead, afk, cine, logout), else nil.
function ns.RandGuard(now)
	if Yes(UnitIsDeadOrGhost, "player") or Yes(UnitIsFeignDeath, "player") then return "dead" end
	if Yes(UnitIsAFK, "player") then return "afk" end
	if next(cine) or Yes(InCinematic) or Yes(IsInCinematicScene) then return "cine" end
	if logT and now - logT < R.logoutMax then return "logout" end
	return nil
end

-- /wind random status.
function ns.RandStatus()
	if stopped then return "random blocked" end
	if not db.random then return "random off" end
	if not due then return "random on" end
	return ("random on · %d min"):format(math.max(0, math.ceil((due - GetTime()) / 60)))
end

function ns.RandSum() return nRand end
function ns.RandHid() return nHid end
function ns.RandBoot()
	local aur = (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID or GetPlayerAuraBySpellID) and 1 or 0
	return ("rnd=%d tgt=%d aur=%d"):format(db.random and 1 or 0, db.randTgt and 1 or 0, aur)
end
