-- Spoken Wind: the Artifact sharts (0.7.0). Rules from the coordinator; line texts approved by the owner
-- (2026-11-22, no word change without a new OK).
-- Rule 1 (no repeat): your own fart (key, Fart button, random, wake-up, attack) whose seed pick is an
--   Artifact sound plays + sends the slot this account heard LEAST instead: heard from others (collection
--   n - own) + db.artPick (your own picks, played or not). Ties: random. All 5 even = a new round.
--   Only your own client swaps; the seed path never does (strangers, the other faction, a late F, a farter
--   without the addon may hear another of the 5). Log: ART pick snd=<num> least=<count> pool=<ties>.
-- Rule 2 (embarrassed line): your own Artifact shart (played, or Own /fart off) = ONE fixed line, chat type
--   EMOTE, 1 s after the sound ends. A timer chat line: the owner's order (like the rumble line).
--   Never for a heard shart. Skip at that time: dead / feign, AFK, a cinematic / movie / loading screen,
--   the logout timer (ART line skip why=dead|afk|cine|logout). Blocked (event or error) = no more lines
--   this session, never a second way (why=block). Log: ART line slot=<1-5> (the order below).
-- Logs: sync ring, max 20 ART lines per session. No names, no GUIDs.
local _, ns = ...

local LINES = {   -- keyed by the slot NAME (the pack numbers are in another order)
	{ slot = "Never Trust It", text = "freezes. That wasn't a fart. Their face turns bright red." },
	{ slot = "The Final Sputter", text = "goes very still. That wasn't a fart. They waddle off, red in the face." },
	{ slot = "Surprise Splat", text = "goes pale. That wasn't a fart. They look around, deeply embarrassed." },
	{ slot = "Floodgate", text = "stops dead. That wasn't a fart. They wish the ground would swallow them whole." },
	{ slot = "The Stutter", text = "clenches. That wasn't a fart. They blush and pretend nothing happened." },
}
local A = { after = 1, logMax = 20, window = 1, lines = LINES }
ns.ART = A
local bySlot = {}
for n, l in ipairs(LINES) do bySlot[l.slot] = n end

local db
local nLog, stopped, sending, sentT = 0, false, false, nil

local function Log(s)
	if nLog >= A.logMax then return end
	nLog = nLog + 1
	if ns.SyncLog then ns.SyncLog(s) elseif ns.Log then ns.Log(s) end
end

-- Core, ADDON_LOADED: the own pick counts (per account), checked.
function ns.ArtInit(saved)
	db = saved
	local p = {}
	if type(db.artPick) == "table" then
		for k, v in pairs(db.artPick) do
			if type(k) == "string" and bySlot[k] and type(v) == "number" and v >= 1 and v < 1e9 then p[k] = math.floor(v) end
		end
	end
	db.artPick = p
	nLog, stopped, sending, sentT = 0, false, false, nil
end

-- Heard from others + picked by you, for Artifact sound i.
local function Count(i)
	local s = ns.EMOTES.FART.sounds[i]
	local e = type(db.dex) == "table" and db.dex[s.file]
	local others = 0
	if type(e) == "table" then others = math.max(0, (tonumber(e.n) or 0) - (tonumber(e.own) or 0)) end
	return others + (db.artPick[s.slot] or 0)
end

-- Rule 1. i = the seed pick of your own fart. Returns the sound to play and send.
function ns.ArtSwap(i)
	if not db or not (ns.ArtSlot and ns.ArtSlot(i)) then return i end
	local least, ties = nil, {}
	for _, j in ipairs(ns.VOX.art) do
		local c = Count(j)
		if not least or c < least then least, ties = c, { j }
		elseif c == least then ties[#ties + 1] = j end
	end
	local pick = #ties == 1 and ties[1] or ties[math.random(1, #ties)]
	local slot = ns.ArtSlot(pick)
	db.artPick[slot] = (db.artPick[slot] or 0) + 1
	Log(("ART pick snd=%d least=%d pool=%d"):format(ns.EMOTES.FART.sounds[pick].num, least, #ties))
	return pick
end

-- One line (the timer). false = it did not go out.
local function Send(n)
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	if type(send) ~= "function" then Log("ART line skip why=noapi") return false end
	sending, sentT = true, GetTime()
	local ok, err = pcall(send, LINES[n].text, "EMOTE")
	sending = false
	if stopped then return false end   -- the block event came during the call
	if not ok then
		stopped = true
		Log("ART line skip why=block")
		Log("ERR art " .. tostring(err):sub(1, 80))
		return false
	end
	Log(("ART line slot=%d"):format(n))
	return true
end

-- Rule 2. Core: your own fart i played, or Own /fart off skipped it here. Returns true when a line waits.
function ns.ArtPlayed(i)
	local slot = ns.ArtSlot and ns.ArtSlot(i)
	local n = slot and bySlot[slot]
	if not n or stopped then return false end
	if not (C_Timer and C_Timer.After) then Log("ART line skip why=noapi") return false end
	local len = ns.SoundLen and ns.SoundLen("FART", i) or 5
	C_Timer.After(len + A.after, function()
		if stopped then return end
		local okG, why = pcall(function() return ns.RandGuard and ns.RandGuard(GetTime()) end)
		if okG and why then Log("ART line skip why=" .. why) return end
		Send(n)
	end)
	return true
end

-- Random.lua's event frame: a blocked call of ours (a2 = the function). During or right after a
-- line = no more lines.
function ns.ArtEvent(a2)
	if stopped then return end
	local fn = type(a2) == "string" and not (issecretvalue and issecretvalue(a2)) and a2 or ""
	if sending or (sentT and GetTime() - sentT <= A.window) or fn:find("SendChatMessage", 1, true) then
		stopped = true
		Log("ART line skip why=block")
	end
end

function ns.ArtBoot()
	local n = 0
	for _, v in pairs(db and db.artPick or {}) do n = n + v end
	return ("art=%d apk=%d"):format(ns.VOX and #ns.VOX.art or 0, n)
end
