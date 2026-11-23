-- Spoken Wind: the Fart button (0.6.5, 2026-11-22). The button is in the bar (Bar.lua, 0.8.0),
-- shown with it (Options: Rewards button).
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
--   max 10 per 10 min. Never from a timer or an event: only inside the click.
-- Right-click = ONE /say line with the same text (for a crowd), target or not, icon or not. Max 1 per
--   5 min (own count, apart from the whispers); full = the click does nothing. Top left of the icon: the
--   wait until the next /say, red (5m ... 1m, then 59 ... 1 s), empty when free. Not in combat.
-- Count (bottom right of the button): whispers left now. None left = the time until the next
--   one is free, red (10m ... 1m, then 59 ... 1 s). Its timers only redraw that text.
-- Answer: a WHISPER "P:1" gets ONE "Q:1" back. Max 1 per sender per 30 s, 10 per minute.
-- Text: the generic line. The creator line only with the dev addon (Spoken_Wind_Dev) loaded.
-- Logs (main log, no names, no GUIDs, max 40 per session): BTN fart tgt= has=y|n|? ·
--   BTN whisper skip why= · BTN whisper icon · BTN whisper icon off · BTN whisper sent n= · BTN pong n= ·
--   BTN say sent n= · BTN say skip why=cap.
--   Sync's SUM line: btn=farts.pings.whispers.pongs (this session, no cap).
-- No frame here: Bar.lua draws ns.BtnView(). No mouse in combat, no keys, no pad, no bindings.
local _, ns = ...

local WAIT, READY, CAP_N, CAP_T = 2, 10, 10, 600
local SAY_T = 300   -- s: one /say per 5 min (right-click)
local RED = "|cffff2020"
local PONG_GAP, PONG_N, PONG_T, LOG_MAX = 30, 10, 60, 40
local ICON = "Interface\\Icons\\Spell_Nature_Cyclone"
local ICON_W = "Interface\\GossipFrame\\GossipGossipIcon"
-- One chat line each (the whisper and the /say), max 255 bytes (tests). Text B (approved 2026-11-23).
-- Only what this build has: the 1337 set (race voices, girl + boy), the board, the achievements.
local TEXT = "Wish you heard that fart? Now you can! Spoken Wind: 1337 synced farts. Girl farts sound different "
	.. "from boy farts, and every race has its own. Leaderboard and achievements. Inspired by Spoken (voiced NPCs, "
	.. "check it out). Get it on CurseForge."
local TEXT_DEV = "Wish you heard that fart? Now you can! I made Spoken Wind: 1337 synced farts. Girl farts sound "
	.. "different from boy farts, and every race has its own. Leaderboard and achievements. Inspired by Spoken "
	.. "(voiced NPCs, check it out). Get it on CurseForge."
ns.BTN = { wait = WAIT, ready = READY, capN = CAP_N, capT = CAP_T, pongGap = PONG_GAP, pongN = PONG_N,
	text = TEXT, textDev = TEXT_DEV, icon = ICON, iconW = ICON_W, sayT = SAY_T }

local shown, countText, sayText = false, "", ""   -- the bar shows the button; its corner texts (whispers, /say)
local st                       -- the open check: { g, name, t, phase = "wait" | "ready" }
local told, sentT = {}, {}     -- GUIDs whispered this session; whisper times (the cap)
local answered = {}            -- GUIDs that answered our check this session
local pongBy, pongT = {}, {}   -- our answers: last time per sender; all times (the cap)
local nSent, nLog, nFart, nPing, nPong = 0, 0, 0, 0, 0
local sayAt, nSay, sayTick = nil, 0, 0   -- the last /say (the cap), /says this session, the newest cell redraw

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

local function Usable(v) return type(v) == "string" and v ~= "" and not (issecretvalue and issecretvalue(v)) end

-- Name words: lower case, split at spaces and '-'. Forever: a chat or addon sender is "First Surname"
-- (maybe + "-Realm"); UnitName gives "First" + "Surname" (Name() makes "First-Surname").
local function Words(s)
	local w = {}
	for x in s:lower():gmatch("[^%s%-]+") do w[#w + 1] = x end
	return w
end

-- Same player? One compare for the whole addon (the Fart button answer, test mode, the group check).
-- True when the names are equal without case, spaces and '-' ("Bo Bo" = "BoBo" = "bo-bo"), or one name
-- is the start of the other, word by word: "First" = "First Surname" = "First-Surname" =
-- "First Surname-Realm". "First-RealmA" is not "First-RealmB"; "Bo" is not "Bob".
function ns.SameName(a, b)
	if not (Usable(a) and Usable(b)) then return false end
	local wa, wb = Words(a), Words(b)
	if not (wa[1] and wb[1]) then return false end
	if table.concat(wa) == table.concat(wb) then return true end
	for i = 1, math.min(#wa, #wb) do
		if wa[i] ~= wb[i] then return false end
	end
	return true
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

local function Draw() if ns.BarDraw then ns.BarDraw() end end

-- The corner count. Shown: one timer, to the next change (1 s while none are left).
local tick = 0   -- the newest redraw; older timers do nothing
local function Count()
	if not shown then return end
	tick = tick + 1
	local my, now, wait = tick, GetTime(), nil
	Capped(now)   -- drops whispers older than CAP_T
	local left = CAP_N - #sentT
	if left > 0 then
		countText = tostring(left)
		if sentT[1] then wait = CAP_T - (now - sentT[1]) + 0.05 end
	else
		local s = math.max(1, math.ceil(CAP_T - (now - sentT[1])))
		countText = RED .. (s >= 60 and math.ceil(s / 60) .. "m" or tostring(s)) .. "|r"
		wait = 1
	end
	if wait then
		C_Timer.After(wait, function() if my == tick and shown then Count() end end)
	end
	Draw()
end

-- The /say cell (top left): the wait until the next /say, red; empty when free. A timer only while it waits.
local function SayCount()
	if not shown then return end
	sayTick = sayTick + 1
	local my, left = sayTick, sayAt and SAY_T - (GetTime() - sayAt) or 0
	if left <= 0 then sayText = "" Draw() return end
	local s = math.max(1, math.ceil(left))
	sayText = RED .. (s >= 60 and math.ceil(s / 60) .. "m" or tostring(s)) .. "|r"
	C_Timer.After(1, function() if my == sayTick and shown then SayCount() end end)
	Draw()
end

-- ONE chat line with this build's text: the creator line only with the dev addon. True = sent.
local function Chat(chan, to)
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	local okS, err = pcall(send, ns.Dev and ns.Dev() and TEXT_DEV or TEXT, chan, nil, to)
	if not okS and ns.Log then ns.Log("ERR btn " .. tostring(err)) end
	return okS
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
	Draw()
end

-- The ready phase: the bar's "Tell? N" counts down (one redraw per second, ends with the phase).
local function Tell(c)
	if st ~= c or not shown then return end
	Draw()
	C_Timer.After(1, function() Tell(c) end)
end

-- Click 2: the whisper (no emote). False = a check fails now: the click is a plain fart click.
local function Whisper(now)
	local c = st
	Reset()
	if Block(c.g, now) then return false end
	if not Chat("WHISPER", c.name) then return true end
	told[c.g] = true
	sentT[#sentT + 1] = now
	nSent = nSent + 1
	Count()
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
		Tell(c)
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

-- Right-click: ONE /say line (for a crowd), only inside the click. Full = nothing (the cell shows the wait).
local function Say()
	if InCombat() then return end
	local now = GetTime()
	if sayAt and now - sayAt < SAY_T then Log("BTN say skip why=cap") return end
	if not Chat("SAY") then return end
	sayAt = now
	nSay = nSay + 1
	SayCount()
	Log(("BTN say sent n=%d"):format(nSay))
end

-- Sync: a WHISPER "P:1" (someone's Fart button asks) or "Q:1" (the answer to ours).
function ns.BtnGot(text, sender)
	if type(sender) ~= "string" or sender == "" then return end
	local now = GetTime()
	if text == "Q:1" then   -- in time or late (icon shown): a user, no whisper
		if st and ns.SameName(sender, st.name) then
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

-- Bar.lua: its root frame's events. Combat ends the check; a new target ends the check of the old one.
function ns.BtnEvent(event)
	if event == "PLAYER_TARGET_CHANGED" then
		if st and not (UnitGUID and UnitGUID("target") == st.g) then Reset() end
	elseif event == "PLAYER_REGEN_DISABLED" then
		Reset()
	end
end

-- Bar.lua: the bar shows (true) or hides (false).
function ns.BtnShow(show)
	shown = show == true
	if shown then Count() SayCount() else Reset() end
end

ns.BtnClick = Click
ns.BtnSay = Say   -- Bar.lua: right click on the Fart button

-- Bar.lua: what the Fart button shows. phase = base | wait | ready; tell = s left for click 2; count, say = the
-- corner texts (whispers left, the /say wait).
function ns.BtnView()
	local v = { phase = st and st.phase or "base", count = countText, say = sayText, iconW = ICON_W }
	if st and st.phase == "ready" then v.tell = math.max(1, math.ceil(READY - (GetTime() - st.t))) end
	return v
end

-- Sync's SUM line: farts.pings.whispers.pongs this session.
function ns.BtnSums() return ("%d.%d.%d.%d"):format(nFart, nPing, nSent, nPong) end
