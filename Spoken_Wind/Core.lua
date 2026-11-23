-- Spoken Wind: plays a sound when someone near you does an emote in
-- ns.EMOTES (now: the fart emote only).
-- Sounds only. Prints only when you type /wind or press Test. No CVars, no
-- Blizzard frames touched: one plain event frame (+ the options page in
-- Options.lua, made with the game's own Settings API, + the own achievement
-- toast in Toast.lua and window in Achievements.lua, + the own rewards button in
-- Rewards.lua).
-- The one chat line: a reward emote, from a typed slash or a click only.
-- Same fart for everyone: Sync.lua (seed + one hidden addon message per own
-- /fart, sent from a post-hook on the game's emote call).
-- Test mode: TestMode.lua (/wind pair, off by default, off at logout).
-- One sound per person at a time: a person is busy from the play start for
-- max(cd, the sound's length) (ns.LEN, Lengths.lua, made from the ogg files).
local ADDON, ns = ...
local VERSION = "0.7.0"
local TAG = "|cff9fd8a8Spoken Wind|r"
local SLASH = "/wind"
local CHANNELS = { master = "Master", sfx = "SFX", dialog = "Dialog" }
local DEFAULTS = { on = true, rwbtn = true, ch = "SFX", self = true, cd = 1, wait = 150, random = true }
local CD_MAX = 30
local WAIT_MAX = 300   -- ms
local LOG_MAX = 60
local FORMS_MAX = 8
local PRUNE_AT = 32
local LEN_DEFAULT = 5   -- s: a sound with no length in ns.LEN
ns.DEFAULTS, ns.CD_MAX, ns.WAIT_MAX, ns.VERSION = DEFAULTS, CD_MAX, WAIT_MAX, VERSION

local db
local pickers = {}
local busy, nBusy = {}, 0   -- one sound per person: throttle key -> time their sound ends
local lenMiss = {}
local panel = "none"
local sums = { seen = 0, hit = 0, played = 0, nosound = 0, cd = 0, off = 0, selfskip = 0, err = 0 }

local function Log(s)
	local log = db.log
	log[#log + 1] = date("%m-%d %H:%M:%S") .. " " .. s
	while #log > LOG_MAX do table.remove(log, 1) end
end
ns.Log = Log

local function Secret(v) return issecretvalue and issecretvalue(v) end

-- Next sound number for an emote: random, never twice in a row.
local function Pick(token)
	local p = pickers[token]
	if not p then
		p = ns.NewPicker(ns.OldN and ns.OldN(token) or #ns.EMOTES[token].sounds)   -- the old sounds (no GUID: no voice)
		pickers[token] = p
	end
	return p()
end

-- Plays sound i of an emote's set. Returns willPlay (false = muted channel / sound off),
-- true as a second value when PlaySoundFile failed, and the game's sound handle third.
-- The one place that plays a sound: a later pan / distance variant goes here.
local function Play(token, i)
	local row = ns.EMOTES[token]
	local s = row.sounds[i]
	local path = ns.MEDIA .. (s.dir or row.folder) .. "\\" .. s.file .. ".ogg"   -- dir: a race pack (Voices.lua)
	local ok, willPlay, handle = pcall(PlaySoundFile, path, db.ch)
	if not ok then
		sums.err = sums.err + 1
		Log("ERR play " .. tostring(willPlay))
		return false, true
	end
	if willPlay then sums.played = sums.played + 1 else sums.nosound = sums.nosound + 1 end
	return willPlay and true or false, nil, handle
end
ns.Play = Play

local function IsMe(sender, guid)
	if guid and not Secret(guid) and UnitGUID and guid == UnitGUID("player") then return true end
	if type(sender) ~= "string" or Secret(sender) then return false end
	local me = UnitName and UnitName("player")
	return me ~= nil and (sender:match("^[^%-]+") or sender) == me
end

-- Name for the fart log: own = "you", others = name without realm.
local function Who(sender, mine)
	if mine then return "you" end
	if type(sender) ~= "string" or sender == "" or Secret(sender) then return "?" end
	return sender:match("^[^%-]+") or sender
end

-- Cooldown key: one per person. Own emote = "self"; others = GUID, else the name.
local function Key(sender, guid, mine)
	if mine then return "self" end
	if type(guid) == "string" and guid ~= "" and not Secret(guid) then return guid end
	if type(sender) == "string" and sender ~= "" and not Secret(sender) then return sender end
	return "?"
end

-- Drops people whose sound has ended: they can never block a sound again.
local function Prune(now)
	for k, t in pairs(busy) do
		if now >= t then busy[k] = nil nBusy = nBusy - 1 end
	end
end

-- One sound per person: true = may play now, else false + seconds left.
-- A pass holds the person for max(db.cd, wait) (wait = the sync wait before the pick);
-- Hold sets the real end once the sound is picked.
local function Gate(key, now, wait)
	local t = busy[key]
	if t and now < t then return false, t - now end
	if not t then
		nBusy = nBusy + 1
		if nBusy > PRUNE_AT then Prune(now) end
	end
	busy[key] = now + math.max(db.cd, wait or 0)
	return true
end

-- Sync.lua (own key press): true + seconds left while this person's sound plays.
function ns.Busy(key, now)
	local t = busy[key]
	if t and now < t then return true, t - now end
	return false
end

-- A sound's length in s (ns.LEN: ms by file). Missing = LEN_DEFAULT, logged once per file.
local function Len(token, i)
	local row = ns.EMOTES[token]
	local f = row and row.sounds[i] and row.sounds[i].file
	local ms = f and ns.LEN and ns.LEN[f]
	if type(ms) == "number" and ms > 0 then return ms / 1000 end
	f = tostring(f)
	if not lenMiss[f] then lenMiss[f] = true Log("LEN missing key=" .. f) end
	return LEN_DEFAULT
end
ns.SoundLen = Len

-- The real end of a person's sound: play start (now, after the sync wait) + max(db.cd, its length).
local function Hold(key, token, i)
	if not busy[key] then nBusy = nBusy + 1 end
	busy[key] = GetTime() + math.max(db.cd, Len(token, i))
end

-- First few real emote lines, names swapped out: proof of the game's own text.
local function Remember(token, text, sender, mine)
	local forms = db.forms
	if #forms >= FORMS_MAX then return end
	local t = text
	local base = type(sender) == "string" and (sender:match("^[^%-]+") or sender)
	if base and base ~= "" then
		local a, b = t:find(base, 1, true)
		if a then t = t:sub(1, a - 1) .. "<who>" .. t:sub(b + 1) end
	end
	local me = UnitName and UnitName("player")
	if me and not mine then
		local a, b = t:find(me, 1, true)
		if a then t = t:sub(1, a - 1) .. "<me>" .. t:sub(b + 1) end
	end
	-- any other name (an upper case word inside a sentence) -> <name>
	t = token .. " " .. t:gsub("([^%.%?!]%s+)%u[%w']*", "%1<name>")
	for _, f in ipairs(forms) do if f == t then return end end
	forms[#forms + 1] = t
end

-- After the gate: the sound, its PLAY line, the fart log, achievements, stats.
-- i = nil: a random pick. With a sync wait this runs later (from the timer),
-- with the emote's own time. Returns the sound played + true when the game plays it.
local function Finish(token, i, sender, mine, key, now, who, by)
	i = i or Pick(token)
	Hold(key, token, i)   -- one sound per person: busy for its length
	local ok, playErr = Play(token, i)
	Log(("PLAY emo=%s who=%s snd=%d ch=%s ok=%d"):format(token, who, i, db.ch, ok and 1 or 0))
	if ns.FartLogAdd then
		local okLog, err = pcall(ns.FartLogAdd, token, Who(sender, mine), i)
		if not okLog then sums.err = sums.err + 1 Log("ERR flog " .. tostring(err)) end
	end
	if ns.AchPlayed then   -- after the fart log: Gas Giant reads its total
		local okA, err = pcall(ns.AchPlayed, token, i, key, mine, now, ok, playErr)
		if not okA then sums.err = sums.err + 1 Log("ERR ach " .. tostring(err)) end
	end
	if ns.HeardPlayed then
		local okH, err = pcall(ns.HeardPlayed, token, i, key, mine, ok)
		if not okH then sums.err = sums.err + 1 Log("ERR heard " .. tostring(err)) end
	end
	if ok and ns.DexAdd then   -- the collection: played farts only
		local okD, err = pcall(ns.DexAdd, token, i, mine and "own" or (by == "msg" and "msg" or "emote"))
		if not okD then sums.err = sums.err + 1 Log("ERR dex " .. tostring(err)) end
	end
	if mine and ns.ArtPlayed then   -- your own Artifact shart: its line (Shart.lua)
		local okA, err = pcall(ns.ArtPlayed, i)
		if not okA then sums.err = sums.err + 1 Log("ERR art " .. tostring(err)) end
	end
	return i, ok
end

-- Test mode logs a skipped fart too (its pick, why it was skipped).
local function Skipped(rec, why)
	if rec and ns.SyncSkip then pcall(ns.SyncSkip, rec, why) end
end

local function OnTextEmote(text, sender, guid)
	sums.seen = sums.seen + 1
	local token = ns.Match(text, sender)
	if not token then return end
	sums.hit = sums.hit + 1
	local mine = IsMe(sender, guid)
	local who = mine and "self" or "other"
	pcall(Remember, token, text, sender, mine)
	local now = GetTime()
	local rec
	if ns.SyncHeard then   -- every fart, before off / self / cooldown: the seed counts them all
		local okS, r = pcall(ns.SyncHeard, token, sender, guid, mine, now)
		if okS then rec = r else sums.err = sums.err + 1 Log("ERR sync " .. tostring(r)) end
	end
	if mine and token == "FART" and ns.RandTake then   -- a random fart (Random.lua) counts like yours
		local okR, rnd = pcall(ns.RandTake, now, text, rec and rec.o)
		if not okR then sums.err = sums.err + 1 Log("ERR rand " .. tostring(rnd)) end
		if not (okR and rnd) and ns.RandReset then pcall(ns.RandReset, now) end   -- a manual /fart: a new random wait
	end
	if mine and ns.HeardSelf then   -- one own /fart press (Sound Off too): Farts, Legend
		local okH, err = pcall(ns.HeardSelf, token, guid, rec and rec.snd)
		if not okH then sums.err = sums.err + 1 Log("ERR heard " .. tostring(err)) end
	end
	if not db.on then sums.off = sums.off + 1 Log(("SKIP off emo=%s who=%s"):format(token, who)) Skipped(rec, "off") return end
	local key = Key(sender, guid, mine)
	if ns.AchSeen then   -- every /fart, own too, before the gate (Machine Gun counts blocked ones)
		local okA, err = pcall(ns.AchSeen, key, mine, now)
		if not okA then sums.err = sums.err + 1 Log("ERR ach " .. tostring(err)) end
	end
	if mine and not db.self then
		sums.selfskip = sums.selfskip + 1
		Log("SKIP self emo=" .. token)
		Skipped(rec, "self")
		if rec and rec.snd and ns.ArtPlayed then   -- Own /fart off: the others still hear it, so its line goes
			local okA, err = pcall(ns.ArtPlayed, rec.snd)
			if not okA then sums.err = sums.err + 1 Log("ERR art " .. tostring(err)) end
		end
		return
	end
	local okCd, left = Gate(key, now, rec and rec.wait)
	if not okCd then   -- this person's sound still plays
		sums.cd = sums.cd + 1
		Log(("SKIP busy emo=%s who=%s left=%.1f"):format(token, who, left))
		Skipped(rec, "busy")
		return
	end
	if rec then   -- the synced sound: now, or after a short wait for its message
		local okP, err = pcall(ns.SyncPlay, rec, function(i, by) return Finish(token, i, sender, mine, key, now, who, by) end)
		if not okP then sums.err = sums.err + 1 Log("ERR sync " .. tostring(err)) end
		return
	end
	Finish(token, nil, sender, mine, key, now, who)
end

-- A reward line from someone else (CHAT_MSG_EMOTE, exact text): its sound, same
-- per-person gate as /fart. Own line: played at the slash or click already.
-- Not a fart: no fart log, no achievements. Prints nothing.
local function OnEmote(text, sender, guid)
	if Secret(text) or type(text) ~= "string" or not ns.RewardByText then return end
	local id = ns.RewardByText(text)
	if not id or IsMe(sender, guid) then return end
	if not db.on then Log(("SKIP off rw=%d who=other"):format(id)) return end
	local key = Key(sender, guid, false)
	local okCd, left = Gate(key, GetTime())
	if not okCd then Log(("SKIP busy rw=%d who=other left=%.1f"):format(id, left)) return end
	Hold(key, "FART", ns.REWARDS[id].snd)
	Play("FART", ns.REWARDS[id].snd)
	Log(("REWARD heard id=%d who=other"):format(id))
end

-- ------------------------------------------------------------ settings
local function Say(s) print(TAG .. " " .. s) end
ns.Say = Say

-- One way to change a setting (/wind and reset). With the options page, its
-- own setting object writes the value, so the page shows it at once.
local fromSlash = false
local function Set(key, value)
	if db[key] == value then return end
	local s = ns.panelSettings and ns.panelSettings[key]
	if s then
		fromSlash = true
		pcall(s.SetValue, s, value)   -- writes db[key]; its callback logs OPT
		fromSlash = false
	end
	if db[key] ~= value then
		db[key] = value
		Log(("OPT %s=%s by=slash"):format(key, tostring(value)))
		if key == "rwbtn" and ns.RewardSync then pcall(ns.RewardSync) end
		if key == "random" and ns.RandOpt then pcall(ns.RandOpt) end
	end
end

-- The options page calls this after it changed db[key].
function ns.OnOpt(key)
	Log(("OPT %s=%s by=%s"):format(key, tostring(db[key]), fromSlash and "slash" or "panel"))
	if key == "rwbtn" and ns.RewardSync then
		local ok, err = pcall(ns.RewardSync)
		if not ok then sums.err = sums.err + 1 Log("ERR rw " .. tostring(err)) end
	end
	if key == "random" and ns.RandOpt then
		local ok, err = pcall(ns.RandOpt)
		if not ok then sums.err = sums.err + 1 Log("ERR rand " .. tostring(err)) end
	end
end

-- Dev folder (Spoken_Wind_Dev, never shipped) loaded: Test button + /wind test.
local function Dev() return SPOKEN_WIND_DEV == true end
ns.Dev = Dev

-- Sound On (the achievement toast plays its sound only then).
function ns.SoundOn() return db ~= nil and db.on == true end

-- Dev folder only: its /wind dev commands get a small API at PLAYER_LOGIN (the save,
-- the achievement rows, the real earn path, the toast, the log). The public build
-- has no such command.
local devCmd
local function DevAttach()
	if not (Dev() and type(SPOKEN_WIND_DEV_TOOLS) == "function") then return end
	local ok, h = pcall(SPOKEN_WIND_DEV_TOOLS, { db = db, ACH = ns.ACH, Row = ns.AchRow, Earn = ns.AchEarn,
		Reload = ns.AchReload, Toast = ns.Toast, Log = Log, Say = Say, Thanks = ns.TestThanks })
	if ok and type(h) == "function" then devCmd = h else Log("ERR dev " .. tostring(h)) end
end

-- The set Test plays: FART (or the first row).
local function TestToken()
	return ns.EMOTES.FART and "FART" or ns.Tokens()[1]
end

-- /wind test [n] and the page's Test button (dev folder only): plays even when off.
function ns.Test(n)
	if Dev() and ns.AchTested then   -- the one achievement Test gives (secret, dev only)
		local okA, err = pcall(ns.AchTested)
		if not okA then sums.err = sums.err + 1 Log("ERR ach " .. tostring(err)) end
	end
	local token = TestToken()
	local sounds = ns.EMOTES[token].sounds
	n = tonumber(n)
	local i = n and n >= 1 and n <= #sounds and math.floor(n) or Pick(token)
	local ok = Play(token, i)
	Log(("TEST emo=%s snd=%d ch=%s ok=%d"):format(token, i, db.ch, ok and 1 or 0))
	Say(("#%d %s%s"):format(i, sounds[i].name, ok and "" or " · no sound (" .. db.ch .. " off?)"))
end

local function Sets()
	local parts = {}
	for _, token in ipairs(ns.Tokens()) do
		parts[#parts + 1] = ns.EMOTES[token].folder .. " " .. #ns.EMOTES[token].sounds
	end
	return table.concat(parts, " · ")
end

-- Command list for /wind and the text-only page. "test" only with the dev folder.
function ns.Help()
	return "on|off · " .. (Dev() and ("test [1-" .. #ns.EMOTES[TestToken()].sounds .. "] · ach test [1-"
		.. #ns.ACH .. "] · ") or "") .. "ch master|sfx|dialog · self on|off · random on|off · cd 0-" .. CD_MAX .. " · wait 0-" .. WAIT_MAX
end

local function Status()
	Say(("%s · %s · self %s · cd %ss/person · wait %dms · %s"):format(db.on and "on" or "off", db.ch,
		db.self and "on" or "off", tostring(db.cd), db.wait, Sets()))
	Say(ns.Help())
end

local function Slash(msg)
	local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "on" or cmd == "off" then
		Set("on", cmd == "on")
		Say(cmd)
	elseif cmd == "test" and Dev() then
		ns.Test(arg)
	elseif cmd == "ach" and Dev() and arg:match("^test") then
		ns.AchTest(arg:match("(%d+)"))
	elseif cmd == "ach" and ns.AchOpen then   -- the achievements window (classic / social tab)
		if not ns.AchOpen(arg ~= "" and arg or nil) then Say("ach: not in combat") end
	elseif cmd == "ch" then
		local ch = CHANNELS[arg]
		if ch then Set("ch", ch) Say("ch " .. ch) else Say("ch master|sfx|dialog") end
	elseif cmd == "self" then
		if arg == "on" then Set("self", true) elseif arg == "off" then Set("self", false)
		elseif arg == "" then Set("self", not db.self)
		else Say("self on|off") return end
		Say("self " .. (db.self and "on" or "off"))
	elseif cmd == "random" and ns.RandStatus then   -- on | off | status (no word = status)
		if arg == "on" then Set("random", true) elseif arg == "off" then Set("random", false)
		elseif arg ~= "" and arg ~= "status" then Say("random on|off|status") return end
		Say(ns.RandStatus())
	elseif cmd == "cd" then
		local n = tonumber(arg)
		if n and n >= 0 then
			Set("cd", math.min(CD_MAX, math.floor(n * 10 + 0.5) / 10))
			Say("cd " .. db.cd .. "s/person")
		else
			Say("cd 0-" .. CD_MAX)
		end
	elseif cmd == "wait" then
		local n = tonumber(arg)
		if n and n >= 0 then
			Set("wait", math.min(WAIT_MAX, math.floor(n / 10 + 0.5) * 10))
			Say("wait " .. db.wait .. "ms")
		else
			Say("wait 0-" .. WAIT_MAX)
		end
	elseif cmd == "dev" and devCmd then
		local ok, err = pcall(devCmd, arg)
		if not ok then sums.err = sums.err + 1 Log("ERR dev " .. tostring(err)) end
	elseif cmd == "board" and ns.BoardCmd then   -- off | on | status
		local ok, s = pcall(ns.BoardCmd, arg)
		if ok then Say(s) else sums.err = sums.err + 1 Log("ERR board " .. tostring(s)) end
	elseif cmd == "pair" and ns.TestCmd then   -- the name as typed (case kept)
		ns.TestCmd((msg or ""):match("^%s*%S+%s*(.-)%s*$") or "")
	elseif cmd == "reset" then
		for k, v in pairs(DEFAULTS) do Set(k, v) end
		Say("reset")
		Status()
	else
		Status()
	end
end

-- 1 when a game emote already uses our slash word (then report it).
local function SlashClash()
	local lastIndex = math.max(tonumber(_G.MAXEMOTEINDEX) or 0, 1000)
	for i = 1, lastIndex do
		for k = 1, 4 do
			if _G["EMOTE" .. i .. "_CMD" .. k] == SLASH then return 1 end
		end
	end
	return 0
end

-- ------------------------------------------------------------ boot
-- The options page waits for PLAYER_LOGIN: by then every addon is loaded (the
-- dev folder too), so the page knows if it gets the Test button.
local built = false
local rw = -1   -- reward commands made (-1 = error)
local function BuildPage()
	if built or not ns.BuildPanel then return end
	built = true
	local ok, kind = pcall(ns.BuildPanel, db)
	panel = ok and kind or "err"
	if not ok then Log("ERR panel " .. tostring(kind)) end
end

local randEv, nRandEv = {}, 0   -- Random.lua's events (each one only if this client has it)
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(self, event, a1, a2, a3, a4, _, _, _, _, _, _, _, a12)
	if event == "CHAT_MSG_ADDON" then
		if ns.SyncMessage then
			local ok, err = pcall(ns.SyncMessage, a1, a2, a3, a4)
			if not ok then sums.err = sums.err + 1 Log("ERR sync " .. tostring(err)) end
		end
	elseif event == "CHAT_MSG_TEXT_EMOTE" then
		local ok, err = pcall(OnTextEmote, a1, a2, a12)
		if not ok then sums.err = sums.err + 1 Log("ERR " .. tostring(err)) end
	elseif event == "CHAT_MSG_EMOTE" then
		local ok, err = pcall(OnEmote, a1, a2, a12)
		if not ok then sums.err = sums.err + 1 Log("ERR rw " .. tostring(err)) end
	elseif randEv[event] then   -- Random.lua: blocks, cinematics, loading screens, auras, logout
		local ok, err = pcall(ns.RandEvent, event, a1, a2)
		if not ok then sums.err = sums.err + 1 Log("ERR rand " .. tostring(err)) end
	elseif event == "ADDON_LOADED" and a1 == ADDON then
		SpokenWindDB = type(SpokenWindDB) == "table" and SpokenWindDB or {}
		db = SpokenWindDB
		for k, v in pairs(DEFAULTS) do if type(db[k]) ~= type(v) then db[k] = v end end
		local goodCh = false
		for _, v in pairs(CHANNELS) do if db.ch == v then goodCh = true end end
		if not goodCh then db.ch = DEFAULTS.ch end
		if db.cd < 0 or db.cd > CD_MAX then db.cd = DEFAULTS.cd end
		if db.wait < 0 or db.wait > WAIT_MAX or db.wait ~= db.wait then db.wait = DEFAULTS.wait end
		db.log = type(db.log) == "table" and db.log or {}
		db.forms = type(db.forms) == "table" and db.forms or {}
		if db.cdMove ~= true then   -- one time: old default 2 s -> new default 1 s (a later hand-set 2 stays)
			if db.cd == 2 then db.cd = 1 Log("CD move 2->1") end
			db.cdMove = true
		end
		if db.rwbtnMove ~= true then   -- one time: the button is on by default now (a later hand-set off stays)
			if db.rwbtn == false then db.rwbtn = true Log("RWBTN move off->on") end
			db.rwbtnMove = true
		end
		if ns.FartLogInit then ns.FartLogInit(db) end
		if ns.HeardInit then ns.HeardInit(db) end
		if ns.DexInit then ns.DexInit(db) end
		if ns.BoardInit then
			local okB, err = pcall(ns.BoardInit, db)
			if not okB then sums.err = sums.err + 1 Log("ERR board " .. tostring(err)) end
		end
		if ns.AchInit then ns.AchInit(db) end
		if ns.RewardInit then ns.RewardInit(db) end
		if ns.SyncInit then
			local okS, err = pcall(ns.SyncInit, db)
			if not okS then sums.err = sums.err + 1 Log("ERR sync " .. tostring(err)) end
		end
		if ns.RandInit then ns.RandInit(db) end
		if ns.ArtInit then ns.ArtInit(db) end
		if ns.TestInit then
			local okT, err = pcall(ns.TestInit, db)
			if not okT then sums.err = sums.err + 1 Log("ERR test " .. tostring(err)) end
		end
		SLASH_SPOKENWIND1 = SLASH
		SLASH_SPOKENWIND2 = "/spokenwind"
		SlashCmdList.SPOKENWIND = Slash
		self:UnregisterEvent("ADDON_LOADED")
		self:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
		self:RegisterEvent("CHAT_MSG_EMOTE")
		self:RegisterEvent("CHAT_MSG_ADDON")
		for _, e in ipairs(ns.RAND and ns.RAND.events or {}) do
			local okE = false
			if ns.RAND.unit and ns.RAND.unit[e] and self.RegisterUnitEvent then   -- the player only
				okE = pcall(self.RegisterUnitEvent, self, e, "player")
			end
			if not okE then okE = pcall(self.RegisterEvent, self, e) end
			if okE then randEv[e], nRandEv = true, nRandEv + 1 end
		end
	elseif event == "PLAYER_LOGIN" then
		BuildPage()
		DevAttach()
		if ns.BoardLogin then   -- this character's counters + the Mine tiers from the collection
			local okB, err = pcall(ns.BoardLogin)
			if not okB then sums.err = sums.err + 1 Log("ERR board " .. tostring(err)) end
			local okT, _, nT = pcall(ns.TiersMine)
			if okT then Log("TIERS seed from=dex n=" .. tostring(nT)) end
		end
		if ns.SyncTimerStart then   -- the board timer S (one per 300 s + 0-60 s, guild/group)
			local okS, err = pcall(ns.SyncTimerStart)
			if not okS then sums.err = sums.err + 1 Log("ERR timer " .. tostring(err)) end
		end
		if ns.RandLogin then   -- random farts: the 15 s ticker + the first wait (45-75 min)
			local okR, err = pcall(ns.RandLogin)
			if not okR then sums.err = sums.err + 1 Log("ERR rand " .. tostring(err)) end
		end
		if ns.RewardSetup then
			local okR, n = pcall(ns.RewardSetup)
			rw = okR and n or -1
			if not okR then sums.err = sums.err + 1 Log("ERR rw " .. tostring(n)) end
			local okS, err = pcall(ns.RewardSync)
			if not okS then sums.err = sums.err + 1 Log("ERR rw " .. tostring(err)) end
		end
		local loc = GetLocale and GetLocale() or "?"
		local srcs = ns.SetLocale(loc)
		local parts, n, nLen = {}, 0, 0
		for _, token in ipairs(ns.Tokens()) do
			parts[#parts + 1] = token .. ":" .. srcs[token] .. ":" .. tostring(ns.EmoteCommand(token))
			n = n + #ns.EMOTES[token].sounds
			for _, s in ipairs(ns.EMOTES[token].sounds) do
				local ms = ns.LEN and ns.LEN[s.file]
				if type(ms) == "number" and ms > 0 then nLen = nLen + 1 end
			end
		end
		Log(("BOOT v=%s loc=%s emotes=%s slash=%s clash=%d panel=%s log=%s flog=%s farts=%d ach=%s done=%d rw=%d btn=%d sync=%d/%d wait=%d tm=%d on=%d ch=%s self=%d cd=%s n=%d len=%d/%d dex=%d %s %s %s rev=%d dev=%d %s %s"):format(
			VERSION, loc, table.concat(parts, ","), SLASH, SlashClash(), panel, tostring(ns.changelog), tostring(ns.fartlog),
			#db.farts, tostring(ns.achpage), ns.AchDone and ns.AchDone() or 0, rw, db.rwbtn and 1 or 0,
			ns.syncPrefix or -1, ns.syncHooks or 0, db.wait, ns.TestCmd and 1 or 0, db.on and 1 or 0, db.ch, db.self and 1 or 0,
			tostring(db.cd), n, nLen, n, ns.DexCount and ns.DexCount() or 0, ns.HeardBoot and ns.HeardBoot() or "reply=0",
			ns.BoardBoot and (function() local ok, s = pcall(ns.BoardBoot) return ok and s or "board=-1" end)() or "board=-1",
			ns.RandBoot and ns.RandBoot() or "rnd=-1", nRandEv, Dev() and 1 or 0,
			ns.VoxBoot and (function() local ok, s = pcall(ns.VoxBoot) return ok and s or "set=-1" end)() or "set=-1",
			ns.ArtBoot and (function() local ok, s = pcall(ns.ArtBoot) return ok and s or "art=-1" end)() or "art=-1"))
	elseif event == "PLAYER_LOGOUT" and db then
		local parts = {}
		for _, k in ipairs({ "seen", "hit", "played", "nosound", "cd", "off", "selfskip", "err" }) do
			parts[#parts + 1] = k .. "=" .. sums[k]
		end
		parts[#parts + 1] = "keys=" .. nBusy
		Log("SUM " .. table.concat(parts, " "))
		if ns.SyncSum then pcall(ns.SyncSum) end
		if ns.TestOff then pcall(ns.TestOff, "logout") end
	end
end)
