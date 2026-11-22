-- Spoken Wind: plays a sound when someone near you does an emote in
-- ns.EMOTES (now: the fart emote only).
-- Sounds only. Prints only when you type /wind. No hooks, no CVars,
-- no Blizzard frames touched: one plain event frame.
local ADDON, ns = ...
local VERSION = "0.1.0"
local TAG = "|cff9fd8a8Spoken Wind|r"
local SLASH = "/wind"
local CHANNELS = { master = "Master", sfx = "SFX", dialog = "Dialog" }
local DEFAULTS = { on = true, ch = "SFX", self = true, cd = 2 }
local CD_MAX = 30
local LOG_MAX = 60
local FORMS_MAX = 8

local db
local pickers = {}
local lastPlay
local sums = { seen = 0, hit = 0, played = 0, nosound = 0, cd = 0, off = 0, selfskip = 0, err = 0 }

local function Log(s)
	local log = db.log
	log[#log + 1] = date("%m-%d %H:%M:%S") .. " " .. s
	while #log > LOG_MAX do table.remove(log, 1) end
end

local function Secret(v) return issecretvalue and issecretvalue(v) end

-- Next sound number for an emote: random, never twice in a row.
local function Pick(token)
	local p = pickers[token]
	if not p then
		p = ns.NewPicker(#ns.EMOTES[token].sounds)
		pickers[token] = p
	end
	return p()
end

-- Plays sound i of an emote's set. Returns willPlay (false = muted channel / sound off).
local function Play(token, i)
	local row = ns.EMOTES[token]
	local path = ns.MEDIA .. row.folder .. "\\" .. row.sounds[i].file .. ".ogg"
	local ok, willPlay = pcall(PlaySoundFile, path, db.ch)
	if not ok then
		sums.err = sums.err + 1
		Log("ERR play " .. tostring(willPlay))
		return false
	end
	if willPlay then sums.played = sums.played + 1 else sums.nosound = sums.nosound + 1 end
	return willPlay and true or false
end

local function IsMe(sender, guid)
	if guid and not Secret(guid) and UnitGUID and guid == UnitGUID("player") then return true end
	if type(sender) ~= "string" or Secret(sender) then return false end
	local me = UnitName and UnitName("player")
	return me ~= nil and (sender:match("^[^%-]+") or sender) == me
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

local function OnTextEmote(text, sender, guid)
	sums.seen = sums.seen + 1
	local token = ns.Match(text, sender)
	if not token then return end
	sums.hit = sums.hit + 1
	local mine = IsMe(sender, guid)
	local who = mine and "self" or "other"
	pcall(Remember, token, text, sender, mine)
	if not db.on then sums.off = sums.off + 1 Log(("SKIP off emo=%s who=%s"):format(token, who)) return end
	if mine and not db.self then sums.selfskip = sums.selfskip + 1 Log("SKIP self emo=" .. token) return end
	local now = GetTime()
	if lastPlay and now - lastPlay < db.cd then
		sums.cd = sums.cd + 1
		Log(("SKIP cd emo=%s who=%s dt=%.1f"):format(token, who, now - lastPlay))
		return
	end
	lastPlay = now
	local i = Pick(token)
	local ok = Play(token, i)
	Log(("PLAY emo=%s who=%s snd=%d ch=%s ok=%d"):format(token, who, i, db.ch, ok and 1 or 0))
end

-- ------------------------------------------------------------ /wind
local function Say(s) print(TAG .. " " .. s) end

-- The set /wind test plays: FART (or the first row).
local function TestToken()
	return ns.EMOTES.FART and "FART" or ns.Tokens()[1]
end

local function Sets()
	local parts = {}
	for _, token in ipairs(ns.Tokens()) do
		parts[#parts + 1] = ns.EMOTES[token].folder .. " " .. #ns.EMOTES[token].sounds
	end
	return table.concat(parts, " · ")
end

local function Status()
	Say(("%s · %s · self %s · cd %ss · %s"):format(db.on and "on" or "off", db.ch,
		db.self and "on" or "off", tostring(db.cd), Sets()))
	Say("on|off · test [1-" .. #ns.EMOTES[TestToken()].sounds .. "] · ch master|sfx|dialog · self on|off · cd 0-"
		.. CD_MAX)
end

local function Slash(msg)
	local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "on" or cmd == "off" then
		db.on = cmd == "on"
		Say(cmd)
	elseif cmd == "test" then
		local token = TestToken()
		local sounds = ns.EMOTES[token].sounds
		local n = tonumber(arg)
		local i = n and n >= 1 and n <= #sounds and math.floor(n) or Pick(token)
		local ok = Play(token, i)
		Log(("TEST emo=%s snd=%d ch=%s ok=%d"):format(token, i, db.ch, ok and 1 or 0))
		Say(("#%d %s%s"):format(i, sounds[i].name, ok and "" or " · no sound (" .. db.ch .. " off?)"))
	elseif cmd == "ch" then
		local ch = CHANNELS[arg]
		if ch then db.ch = ch Say("ch " .. ch) else Say("ch master|sfx|dialog") end
	elseif cmd == "self" then
		if arg == "on" then db.self = true elseif arg == "off" then db.self = false
		elseif arg == "" then db.self = not db.self
		else Say("self on|off") return end
		Say("self " .. (db.self and "on" or "off"))
	elseif cmd == "cd" then
		local n = tonumber(arg)
		if n and n >= 0 then
			db.cd = math.min(CD_MAX, math.floor(n * 10 + 0.5) / 10)
			Say("cd " .. db.cd .. "s")
		else
			Say("cd 0-" .. CD_MAX)
		end
	elseif cmd == "reset" then
		for k, v in pairs(DEFAULTS) do db[k] = v end
		Say("reset")
		Status()
	else
		Status()
	end
end

-- 1 when a game emote already uses our slash word (then report it).
local function SlashClash()
	local last = math.max(tonumber(_G.MAXEMOTEINDEX) or 0, 1000)
	for i = 1, last do
		for k = 1, 4 do
			if _G["EMOTE" .. i .. "_CMD" .. k] == SLASH then return 1 end
		end
	end
	return 0
end

-- ------------------------------------------------------------ boot
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(self, event, a1, a2, _, _, _, _, _, _, _, _, _, a12)
	if event == "CHAT_MSG_TEXT_EMOTE" then
		local ok, err = pcall(OnTextEmote, a1, a2, a12)
		if not ok then sums.err = sums.err + 1 Log("ERR " .. tostring(err)) end
	elseif event == "ADDON_LOADED" and a1 == ADDON then
		SpokenWindDB = type(SpokenWindDB) == "table" and SpokenWindDB or {}
		db = SpokenWindDB
		for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
		local goodCh = false
		for _, v in pairs(CHANNELS) do if db.ch == v then goodCh = true end end
		if not goodCh then db.ch = DEFAULTS.ch end
		if type(db.cd) ~= "number" or db.cd < 0 then db.cd = DEFAULTS.cd end
		db.log = type(db.log) == "table" and db.log or {}
		db.forms = type(db.forms) == "table" and db.forms or {}
		SLASH_SPOKENWIND1 = SLASH
		SLASH_SPOKENWIND2 = "/spokenwind"
		SlashCmdList.SPOKENWIND = Slash
		self:UnregisterEvent("ADDON_LOADED")
		self:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
	elseif event == "PLAYER_LOGIN" then
		local loc = GetLocale and GetLocale() or "?"
		local srcs = ns.SetLocale(loc)
		local parts, n = {}, 0
		for _, token in ipairs(ns.Tokens()) do
			parts[#parts + 1] = token .. ":" .. srcs[token] .. ":" .. tostring(ns.EmoteCommand(token))
			n = n + #ns.EMOTES[token].sounds
		end
		Log(("BOOT v=%s loc=%s emotes=%s slash=%s clash=%d on=%d ch=%s self=%d cd=%s n=%d"):format(VERSION, loc,
			table.concat(parts, ","), SLASH, SlashClash(), db.on and 1 or 0, db.ch, db.self and 1 or 0,
			tostring(db.cd), n))
	elseif event == "PLAYER_LOGOUT" and db then
		local parts = {}
		for _, k in ipairs({ "seen", "hit", "played", "nosound", "cd", "off", "selfskip", "err" }) do
			parts[#parts + 1] = k .. "=" .. sums[k]
		end
		Log("SUM " .. table.concat(parts, " "))
	end
end)
