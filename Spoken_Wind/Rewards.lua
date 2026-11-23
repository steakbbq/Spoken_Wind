-- Spoken Wind: rewards. Each achievement unlocks one slash command. Use = ONE
-- custom emote line (the game puts your name in front), then its sound here.
-- Other Spoken Wind users hear the same sound when that exact line comes in
-- (Core: CHAT_MSG_EMOTE, same per-person cooldown as /fart).
-- The chat line comes only from a typed slash or a click: never from a timer,
-- an event or a loop. Locked = one local line, no chat.
-- Commands are made at PLAYER_LOGIN (all addons loaded). A word the game or
-- another addon owns is skipped, never overwritten.
-- The buttons bar (Options: Rewards button, default on) and the rewards popup: Bar.lua.
local _, ns = ...

-- Order = ns.ACH order (the 15 main rows). snd = sound number in the fart set.
local REWARDS = {
	{ ach = "super", cmd = "/superfart", text = "unleashes a super legendary fart. Reality bends.", snd = 13 },
	{ ach = "legend", cmd = "/legend", text = "lets one rip that bards will sing about.", snd = 13 },
	{ ach = "orchestra", cmd = "/orchestra", text = "conducts a full fart orchestra.", snd = 4 },
	{ ach = "thousand", cmd = "/gale", text = "summons a gale from behind.", snd = 2 },
	{ ach = "gas", cmd = "/gasgiant", text = "swells up like a gas giant.", snd = 9 },
	{ ach = "penpals", cmd = "/penpal", text = "sends a scented letter.", snd = 8 },
	{ ach = "cropduster", cmd = "/cropdust", text = "dusts the crops on the way past.", snd = 10 },
	{ ach = "double", cmd = "/double", text = "fires both barrels.", snd = 6 },
	{ ach = "callback", cmd = "/pfftback", text = "answers the call of nature.", snd = 14 },
	{ ach = "machinegun", cmd = "/brrrt", text = "opens fire. Brrrrrt.", snd = 7 },
	{ ach = "sbd", cmd = "/sbd", text = "lets one slip. Nobody heard a thing.", snd = 12 },
	{ ach = "night", cmd = "/moontoot", text = "toots softly at the moon.", snd = 5 },
	{ ach = "tuba", cmd = "/tuba", text = "plays the tuba. It is not a tuba.", snd = 11 },
	{ ach = "selfstarter", cmd = "/kickstart", text = "kick-starts the engine.", snd = 3 },
	{ ach = "first", cmd = "/firstwind", text = "squeaks out a first little toot.", snd = 1 },
}
ns.REWARDS = REWARDS

local byText = {}
for i, r in ipairs(REWARDS) do byText[r.text] = i end

local SEND_GAP = 1                          -- s between two reward lines (a double click = one line)

local db, lastSend

-- Reward number of an exact emote line, else nil.
function ns.RewardByText(text) return byText[text] end

-- Core calls this at ADDON_LOADED: checks the saved bar spot.
function ns.RewardInit(saved)
	db = saved
	local p = db.rwpos
	if type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" or p.x ~= p.x or p.y ~= p.y then
		db.rwpos = nil
	end
	lastSend = nil
	if ns.BarInit then ns.BarInit(db) end
end

local function Send(text)
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	send(text, "EMOTE")
end

-- A slash or a click (by = "slash" | "button"). Returns true when the line went out.
function ns.RewardUse(i, by)
	local r = REWARDS[i]
	if not r then return false end
	if not ns.AchHas(r.ach) then
		ns.Say("locked: " .. ns.AchRow(r.ach).name)
		ns.Log(("REWARD id=%d by=%s locked"):format(i, by))
		return false
	end
	local now = GetTime()
	if lastSend and now - lastSend < SEND_GAP then
		ns.Log(("REWARD id=%d by=%s skip=fast"):format(i, by))
		return false
	end
	lastSend = now
	local ok, err = pcall(Send, r.text)
	if not ok then ns.Log("ERR send " .. tostring(err)) end
	if db.on then ns.Play("FART", r.snd) end
	ns.Log(("REWARD id=%d by=%s sent=%d"):format(i, by, ok and 1 or 0))
	return ok
end

-- Every command word the game or an addon owns now (upper case).
local function Owned()
	local set = {}
	local function Add(v) if type(v) == "string" then set[v:upper()] = true end end
	for _, list in ipairs({ SlashCmdList or {}, SecureCmdList or {}, ChatTypeInfo or {} }) do
		for key in pairs(list) do
			if type(key) == "string" then
				local n = 1
				while _G["SLASH_" .. key .. n] ~= nil do Add(_G["SLASH_" .. key .. n]) n = n + 1 end
			end
		end
	end
	if type(hash_SlashCmdList) == "table" then for k in pairs(hash_SlashCmdList) do Add(k) end end
	local lastIndex = math.max(tonumber(_G.MAXEMOTEINDEX) or 0, 1000)
	for i = 1, lastIndex do
		for k = 1, 4 do Add(_G["EMOTE" .. i .. "_CMD" .. k]) end
	end
	return set
end

-- Core calls this at PLAYER_LOGIN. Returns how many commands it made.
function ns.RewardSetup()
	local owned, n, skip = Owned(), 0, {}
	for i, r in ipairs(REWARDS) do
		local key = "SPOKENWIND_" .. r.cmd:sub(2):upper()
		if owned[r.cmd:upper()] or SlashCmdList[key] ~= nil then
			skip[#skip + 1] = r.cmd
		else
			_G["SLASH_" .. key .. "1"] = r.cmd
			SlashCmdList[key] = function() ns.RewardUse(i, "slash") end
			n = n + 1
		end
	end
	if #skip > 0 then ns.Log("REWARD skip " .. table.concat(skip, ",")) end
	return n
end

-- ------------------------------------------------------------ the bar (Bar.lua)
-- Shows or hides the bar per db.rwbtn (Options checkbox).
function ns.RewardSync()
	if ns.BarSync then ns.BarSync() end
end
