-- Spoken Wind: the Fart button (0.6.5, 2026-11-22). A small button right of the Rewards
-- button, shown with it (Options: Rewards button).
-- Click = ONE fart emote (DoEmote "FART": at your target when one is selected, the game's rule).
--   Sync's DoEmote hook sends F + S as for a key press (same gap, busy and combat rules).
-- Target = another player: a silent check in the same click. A known addon user (board, an F
--   in the last hour) = no whisper. Else ONE addon message "P:1" by WHISPER (never seen in chat).
--   A Spoken Wind 0.6.5+ client answers "Q:1". No answer in 2 s = the button shows a whisper icon
--   for 10 s. The next click on it (same target, every check again) sends ONE whisper line
--   (SendChatMessage WHISPER) and no emote. A check fails then = a plain fart click (the fart
--   still happens, no whisper). The two-click flow was picked on purpose (option A).
-- Whisper only when ALL hold, at click 1 and again at click 2: a player, not you, connected, your
--   faction (else the whisper cannot reach), close enough to see the emote (CheckInteractDistance
--   index 4 = the follow range, about 28 yd), no answer, not known. Once per player per session,
--   max 5 per 10 min. Never from a timer or an event: only inside the click.
-- Answer: a WHISPER "P:1" gets ONE "Q:1" back. Max 1 per sender per 30 s, 10 per minute.
-- Text: the generic line. The creator line only with the dev addon (Spoken_Wind_Dev) loaded.
-- Logs (main log, no names, no GUIDs, max 20 per session): BTN fart tgt= has=y|n|? ·
--   BTN whisper skip why= · BTN whisper icon · BTN whisper icon off · BTN whisper sent n= · BTN pong n=.
--   Sync's SUM line: btn=farts.pings.whispers.pongs (this session, no cap).
-- Own frame only. No mouse in combat, no keys, no pad, no bindings, no tooltip.
local _, ns = ...

local WAIT, READY, CAP_N, CAP_T = 2, 10, 5, 600
local PONG_GAP, PONG_N, PONG_T, LOG_MAX = 30, 10, 60, 20
local SIZE, GAP = 32, 4
local ICON = "Interface\\Icons\\Spell_Nature_Cyclone"
local ICON_W = "Interface\\GossipFrame\\GossipGossipIcon"
-- One chat line each, max 255 bytes (tests). Only what this build has (no sound counts, no later packs).
local TEXT = "Wish you heard that fart? Now you can! Spoken Wind: synced fart sounds, a leaderboard, "
	.. "achievements, collect them all, rewards. Inspired by Spoken (voiced NPCs, check it out), but more "
	.. "immersive. Get it on CurseForge."
local TEXT_DEV = "Wish you heard that fart? Now you can! I made Spoken Wind: synced fart sounds, a leaderboard, "
	.. "achievements, collect them all, rewards. Inspired by Spoken (voiced NPCs, check it out), but more "
	.. "immersive. Get it on CurseForge."
ns.BTN = { wait = WAIT, ready = READY, capN = CAP_N, capT = CAP_T, pongGap = PONG_GAP, pongN = PONG_N,
	text = TEXT, textDev = TEXT_DEV, icon = ICON, iconW = ICON_W }

local fb
local st                       -- the open check: { g, name, t, phase = "wait" | "ready" }
local told, sentT = {}, {}     -- GUIDs whispered this session; whisper times (the cap)
local answered = {}            -- GUIDs that answered our check this session
local pongBy, pongT = {}, {}   -- our answers: last time per sender; all times (the cap)
local nSent, nLog, nFart, nPing, nPong = 0, 0, 0, 0, 0

local function Log(s)
	if nLog >= LOG_MAX then return end
	nLog = nLog + 1
	if ns.Log then ns.Log(s) end
end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- "Name" or "Name-Realm" (another realm), as a whisper needs it.
local function Name(u)
	local n, r = UnitName(u)
	if type(n) ~= "string" or n == "" then return nil end
	if type(r) == "string" and r ~= "" then return n .. "-" .. r end
	return n
end

-- An addon sender ("Name-Realm") is the checked player ("Name" on your realm, or "Name-Realm").
local function Same(sender, name)
	if sender == name then return true end
	return not name:find("-", 1, true) and sender:match("^([^%-]+)") == name
end

-- Why the target gets no whisper (nil = every check passes). A missing game call = no whisper.
local function Why(u)
	if UnitIsUnit and UnitIsUnit(u, "player") then return "self" end
	if not (UnitIsPlayer and UnitIsPlayer(u)) then return "npc" end
	if not (UnitIsConnected and UnitIsConnected(u)) then return "offline" end
	local a = UnitFactionGroup and UnitFactionGroup(u)
	if not a or a ~= UnitFactionGroup("player") then return "faction" end
	local okD, near = false, false
	if CheckInteractDistance then okD, near = pcall(CheckInteractDistance, u, 4) end
	if not (okD and near) then return "range" end
	return nil
end

-- A Spoken Wind user: answered this session, an F in the last hour, or on the board.
local function Known(g)
	return answered[g] or (ns.SyncKnown and ns.SyncKnown(g)) or (ns.BoardHas and ns.BoardHas(g)) or false
end

local function Capped(now)
	while sentT[1] and now - sentT[1] > CAP_T do table.remove(sentT, 1) end
	return #sentT >= CAP_N
end

-- Every whisper check (click 1 and click 2). Returns the why, or nil.
local function Block(g, now)
	local why = Why("target")
	if why then return why end
	if Known(g) then return "has" end
	if told[g] then return "once" end
	if Capped(now) then return "cap" end
	return nil
end

local function Reset()
	st = nil
	if fb then fb.icon:SetTexture(ICON) end
end

-- Click 2: the whisper (no emote). False = a check fails now: the click is a plain fart click.
local function Whisper(now)
	local c = st
	Reset()
	if Block(c.g, now) then return false end
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	local okS, err = pcall(send, ns.Dev and ns.Dev() and TEXT_DEV or TEXT, "WHISPER", nil, c.name)
	if not okS then if ns.Log then ns.Log("ERR btn " .. tostring(err)) end return true end
	told[c.g] = true
	sentT[#sentT + 1] = now
	nSent = nSent + 1
	Log(("BTN whisper sent n=%d"):format(nSent))
	return true
end

-- Click 1: the fart, then the silent check.
local function Fart(now)
	local okE, err = pcall(DoEmote, "FART")
	if okE then nFart = nFart + 1 elseif ns.Log then ns.Log("ERR btn " .. tostring(err)) end
	local g = UnitExists and UnitExists("target") and UnitGUID("target")
	if not g then Log("BTN fart tgt=0 has=?") return end
	if st and st.g == g then Log("BTN fart tgt=1 has=?") return end   -- its check still runs
	Reset()
	local why = Block(g, now)
	if why then
		Log("BTN fart tgt=1 has=" .. (why == "has" and "y" or "?"))
		Log("BTN whisper skip why=" .. why)
		return
	end
	local name = Name("target")
	if not (name and ns.SyncWhisper and ns.SyncWhisper("P:1", name)) then
		Log("BTN fart tgt=1 has=?")
		Log("BTN whisper skip why=send")
		return
	end
	nPing = nPing + 1
	local c = { g = g, name = name, t = now, phase = "wait" }
	st = c
	C_Timer.After(WAIT, function()
		if st ~= c then return end
		if answered[g] then
			Reset()
			Log("BTN fart tgt=1 has=y")
			Log("BTN whisper skip why=has")
			return
		end
		Log("BTN fart tgt=1 has=n")
		c.phase, c.t = "ready", GetTime()
		fb.icon:SetTexture(ICON_W)
		Log("BTN whisper icon")
		C_Timer.After(READY, function()
			if st == c then Reset() Log("BTN whisper icon off") end
		end)
	end)
end

local function Click()
	if InCombat() then return end
	local now = GetTime()
	if st and st.phase == "ready" then
		if now - st.t <= READY and UnitGUID and UnitGUID("target") == st.g and Whisper(now) then return end
		Reset()
	end
	Fart(now)
end

-- Sync: a WHISPER "P:1" (someone's Fart button asks) or "Q:1" (the answer to ours).
function ns.BtnGot(text, sender)
	if type(sender) ~= "string" or sender == "" then return end
	local now = GetTime()
	if text == "Q:1" then   -- in time or late (icon shown): a user, no whisper
		if st and Same(sender, st.name) then
			answered[st.g] = true
			if st.phase == "ready" then Reset() Log("BTN whisper skip why=has") end
		end
		return
	end
	if text ~= "P:1" then return end
	if pongBy[sender] and now - pongBy[sender] < PONG_GAP then return end
	while pongT[1] and now - pongT[1] > PONG_T do table.remove(pongT, 1) end
	if #pongT >= PONG_N then return end
	for k, t in pairs(pongBy) do if now - t >= PONG_GAP then pongBy[k] = nil end end
	if ns.SyncWhisper and ns.SyncWhisper("Q:1", sender) then
		pongBy[sender] = now
		pongT[#pongT + 1] = now
		nPong = nPong + 1
		Log(("BTN pong n=%d"):format(#pongT))
	end
end

local function Build()
	fb = CreateFrame("Frame", nil, UIParent)
	fb:SetSize(SIZE, SIZE)
	fb:SetFrameStrata("MEDIUM")
	fb.icon = fb:CreateTexture(nil, "ARTWORK")
	fb.icon:SetSize(SIZE, SIZE)
	fb.icon:SetPoint("TOPLEFT", fb, "TOPLEFT", 0, 0)
	fb.icon:SetTexture(ICON)
	fb:SetAlpha(0.85)
	fb:EnableMouse(not InCombat())
	fb:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
	fb:SetScript("OnLeave", function(self) self:SetAlpha(0.85) end)
	fb:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then Click() end
	end)
	-- Combat: no mouse, the check ends. A new target ends the check of the old one.
	fb:RegisterEvent("PLAYER_REGEN_DISABLED")
	fb:RegisterEvent("PLAYER_REGEN_ENABLED")
	fb:RegisterEvent("PLAYER_TARGET_CHANGED")
	fb:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_TARGET_CHANGED" then
			if st and not (UnitGUID and UnitGUID("target") == st.g) then Reset() end
			return
		end
		if event == "PLAYER_REGEN_DISABLED" then Reset() end
		self:EnableMouse(event == "PLAYER_REGEN_ENABLED")
	end)
end

-- Rewards.lua: show (right of the Rewards button) or hide, with that button. Made on first use.
function ns.BtnSync(parent, show)
	if show then
		if not fb then Build() end
		fb:ClearAllPoints()
		fb:SetPoint("LEFT", parent, "RIGHT", GAP, 0)
		fb:Show()
	elseif fb then
		Reset()
		fb:Hide()
	end
end

function ns.BtnFrame() return fb end

-- Sync's SUM line: farts.pings.whispers.pongs this session.
function ns.BtnSums() return ("%d.%d.%d.%d"):format(nFart, nPing, nSent, nPong) end
