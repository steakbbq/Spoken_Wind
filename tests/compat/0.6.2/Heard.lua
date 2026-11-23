-- Spoken Wind: "Heard" replies + fart stats (0.6.2).
-- Reply: this client PLAYED the sound of someone else's fart and that fart's F
--   message came (first, or late after the seed played): ONE hidden addon reply
--   H:1:<farter GUID>:<n>:<own GUID> on the channel the F came on (WHISPER only
--   back to the test partner). The one message Spoken Wind sends without a key
--   press: never chat, never an emote, never from a loop. One per fart, max one
--   per GAP s. No F message, Sound Off, cooldown or not played = no reply.
--   (CHAT_MSG_ADDON has no sender GUID, so the reply carries its own: People.)
-- Count: unique repliers per fart (farter GUID + n) for WINDOW s; your own
--   reply never counts. Own fart: speaker icon + "Heard N" beside the Rewards
--   button for SHOW s (0 dimmed); someone else's: "<name> · Heard N" once N >= 1
--   (your own fart wins while it shows). The totals show under it, and on button
--   hover. Button off = no text (the totals still count). Own frame, no mouse.
-- Totals in SpokenWindDB.stats: own (own /fart presses), heard (replies to own
--   farts), best (most in one own fart), people (GUIDs that ever replied),
--   legend (own farts that rolled the legendary), legendHeard (others' legendary
--   farts this client played). Reward lines (/legend, /superfart) never count.
-- Logs (sync ring): HEARD send / skip / got / sum.
local _, ns = ...

local WINDOW = 3      -- s a fart collects replies
local SHOW = 5        -- s the "Heard N" line stays
local GAP = 1         -- s between two own replies
local KEEP = 64       -- farts tracked, replies remembered
local NMAX = 999      -- F message numbers 1..NMAX
local LINE = 14       -- px per text line
local ICON = "Interface\\Common\\VoiceChat-Speaker"
local DIM = "|cff808080"
local CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true, SAY = true }
ns.HEARD = { window = WINDOW, show = SHOW, gap = GAP, keep = KEEP, icon = ICON }

local db, lastReply, panel, cur, hover
local order, farts = {}, {}       -- tracked farts (oldest first); "guid:n" -> fart
local replied, rorder = {}, {}    -- "guid:n" -> GetTime() of our reply

local function Usable(v)
	return type(v) == "string" and v ~= "" and not (issecretvalue and issecretvalue(v))
end
local function Short(g) return Usable(g) and g:sub(-6) or "?" end
local function Me()
	local g = UnitGUID and UnitGUID("player")
	return Usable(g) and g or nil
end
local function Num(v) return type(v) == "number" and v >= 0 and v < math.huge and math.floor(v) or nil end
local function Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end
local function SLog(s) if ns.SyncLog then ns.SyncLog(s) end end

-- ------------------------------------------------------------ stats
-- Core calls this at ADDON_LOADED, after the fart log. Old saves: own = the own
-- rows of the fart log; heard, best, people, legend, legendHeard start at 0.
function ns.HeardInit(saved)
	db = saved
	local s = type(db.stats) == "table" and db.stats or {}
	db.stats = s
	if not Num(s.own) then
		local n = 0
		for _, r in ipairs(type(db.farts) == "table" and db.farts or {}) do
			if type(r) == "table" and r.who == "you" then n = n + 1 end
		end
		s.own = n
	end
	s.own = Num(s.own)
	for _, k in ipairs({ "heard", "best", "legend", "legendHeard" }) do s[k] = Num(s[k]) or 0 end
	local p = {}
	if type(s.people) == "table" then
		for g, v in pairs(s.people) do if Usable(g) and v == true then p[g] = true end end
	end
	s.people = p
end

-- The legendary sound of a farter's pool. Race pools plug in here (each race its
-- own legend); the counters stay totals.
function ns.IsLegend(token, guid, i)
	local row = ns.EMOTES and ns.EMOTES[token]
	local s = row and row.sounds[i]
	return s ~= nil and s.file == "13_legend"
end

-- Core: your own fart line (one /fart press). snd = the roll (nil = none).
function ns.HeardSelf(token, guid, snd)
	local s = db.stats
	s.own = s.own + 1
	if snd and ns.IsLegend(token, guid, snd) then s.legend = s.legend + 1 end
	if ns.HeardDraw then ns.HeardDraw() end   -- a shown "Farts N" stays true
	if ns.AchStats then ns.AchStats() end     -- Windbag
end

-- Core: a fart that played (after the fart log). Others' legendary = legendHeard.
function ns.HeardPlayed(token, i, guid, mine, ok)
	if mine or not ok then return end
	if ns.IsLegend(token, guid, i) then
		db.stats.legendHeard = db.stats.legendHeard + 1
		if ns.HeardDraw then ns.HeardDraw() end
	end
end

-- Your counts (achievements, the window's stats strip). people = how many.
function ns.HeardNums()
	local s = db.stats
	return { own = s.own, heard = s.heard, people = Count(s.people), best = s.best, legend = s.legend,
		legendHeard = s.legendHeard }
end

function ns.HeardBoot()
	local s = db.stats
	return ("own=%d heard=%d people=%d best=%d legend=%d legendHeard=%d reply=1"):format(s.own, s.heard,
		Count(s.people), s.best, s.legend, s.legendHeard)
end

-- Rewards grid head, after "Rewards N/15".
function ns.HeardHead()
	local s = db.stats
	return (" · Farts %d\nHeard %d · People %d · Best %d\nLegend %d · Heard %d"):format(s.own, s.heard,
		Count(s.people), s.best, s.legend, s.legendHeard)
end

-- ------------------------------------------------------------ show (beside the Rewards button)
local function Build()
	panel = CreateFrame("Frame", nil, UIParent)
	panel:SetSize(170, 4 * LINE)
	panel:SetFrameStrata("MEDIUM")
	panel.lines = {}
	for i = 1, 4 do panel.lines[i] = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end
	panel:Hide()
end

-- The side away from the screen edge: button on the left half = text on its right.
local function Place(btn)
	local l = btn:GetLeft()
	local uw = UIParent.GetWidth and UIParent:GetWidth()
	local right = not (l and uw and uw > 0 and l + 16 > uw / 2)
	panel:ClearAllPoints()
	if right then panel:SetPoint("LEFT", btn, "RIGHT", 6, 0) else panel:SetPoint("RIGHT", btn, "LEFT", -6, 0) end
	local a = right and "TOPLEFT" or "TOPRIGHT"
	for i, fs in ipairs(panel.lines) do
		fs:ClearAllPoints()
		fs:SetPoint(a, panel, a, 0, -(i - 1) * LINE)
		fs:SetJustifyH(right and "LEFT" or "RIGHT")
	end
	panel.right = right
end

local function FartLine(f)
	local txt = f.own and ("Heard %d"):format(f.count) or ("%s · Heard %d"):format(f.who, f.count)
	if f.count == 0 then txt = DIM .. txt .. "|r" end
	return "|T" .. ICON .. ":14|t " .. txt
end

local function Draw()
	local btn = ns.RewardFrames and ns.RewardFrames()
	if not (btn and btn:IsShown() and (cur or hover)) then
		if panel then panel:Hide() end
		return
	end
	if not panel then Build() end
	Place(btn)
	local s, list = db.stats, {}
	if cur then list[1] = FartLine(cur) end
	list[#list + 1] = ("Farts %d"):format(s.own)
	list[#list + 1] = ("Heard %d · People %d"):format(s.heard, Count(s.people))
	list[#list + 1] = ("Legend %d · Heard %d"):format(s.legend, s.legendHeard)
	for i, fs in ipairs(panel.lines) do fs:SetText(list[i] or "") end
	panel:Show()
end
ns.HeardDraw = Draw

-- Rewards button hover (and its Options checkbox): the totals.
function ns.HeardHover(on)
	hover = on == true
	Draw()
end

-- Own fart: at once (0 dimmed). Someone else's: from its first reply (HeardGot).
local function Show(f)
	local now = GetTime()
	if cur ~= f then
		if cur and cur.own and not f.own and now - cur.shownAt < SHOW then return end   -- your own fart first
		cur, f.shownAt = f, now
		if C_Timer and C_Timer.After then
			C_Timer.After(SHOW, function() if cur == f then cur = nil Draw() end end)
		end
	end
	Draw()
end

-- ------------------------------------------------------------ count
local function Close(f)
	if f.closed then return end
	f.closed = true
	if f.own or f.count > 0 then SLog(("HEARD sum g=%s n=%d count=%d"):format(Short(f.g), f.n, f.count)) end
end

local function Track(guid, n, who, own)
	local id = guid .. ":" .. n
	local now = GetTime()
	local f = farts[id]
	if f and now - f.t <= WINDOW then return f end   -- the same fart
	f = { id = id, g = guid, n = n, who = who, own = own, t = now, from = {}, count = 0 }
	farts[id] = f
	order[#order + 1] = f
	while #order > KEEP do
		local old = table.remove(order, 1)
		if farts[old.id] == old then farts[old.id] = nil end
	end
	if C_Timer and C_Timer.After then C_Timer.After(WINDOW, function() Close(f) end) end
	return f
end

-- Sync: your own F message went out (sent = channels; nil = a test-mode timer sends it).
function ns.HeardOwnSent(guid, n, sent)
	if sent == 0 or not Usable(guid) or not tonumber(n) then return end
	Show(Track(guid, tonumber(n), "you", true))
end

-- Sync: someone else's F message (once per fart, any channel).
function ns.HeardTrack(guid, n, sender)
	if not Usable(guid) or guid == Me() or not tonumber(n) then return end
	local who = Usable(sender) and (sender:match("^[^%-]+") or sender) or "?"
	Track(guid, tonumber(n), who, false)
end

-- Sync: an H message. Bad ones are dropped without a word.
function ns.HeardGot(text, ch, sender)
	local g, n, from, a = text:match("^H:1:([%w%-]+):(%d+):([%w%-]+)(.-)$")
	n = tonumber(n)
	if not (g and n and n >= 1 and n <= NMAX) or (a ~= "" and a ~= ":a") or g == from or from == Me()
		or not Usable(sender) then return end
	if ch == "WHISPER" then
		if not (ns.TestFrom and ns.TestFrom(sender, from)) then return end
	elseif not CHANNELS[ch] then
		return
	end
	local f = farts[g .. ":" .. n]
	if not f or f.closed or GetTime() - f.t > WINDOW then return end
	if f.from[from] or f.from[sender] then return end   -- one per replier (PARTY + GUILD copies)
	f.from[from], f.from[sender] = true, true
	f.count = f.count + 1
	SLog(("HEARD got from=%s g=%s n=%d count=%d"):format(Short(from), Short(g), n, f.count))
	if f.own then
		local s = db.stats
		s.heard = s.heard + 1
		s.people[from] = true
		if f.count > s.best then s.best = f.count end
	end
	Show(f)
	if f.own then   -- your fart: Social achievements; the author's reply = Author's Note
		if a == ":a" and ns.AchEarn then ns.AchEarn("authornote") end
		if ns.AchStats then ns.AchStats() end
	end
end

-- ------------------------------------------------------------ reply
-- Sync: someone else's fart PLAYED here and its F message is known. Returns true = sent.
function ns.HeardReply(guid, n, ch, sender, who)
	local me = Me()
	n = tonumber(n)
	if not (me and Usable(guid) and n) or guid == me then return false end
	local target
	if ch == "WHISPER" then
		if who ~= "pair" or not Usable(sender) then return false end
		target = sender
	elseif not CHANNELS[ch] then
		return false
	end
	local id = guid .. ":" .. n
	local now = GetTime()
	if replied[id] and now - replied[id] <= WINDOW then return false end   -- one per fart
	if lastReply and now - lastReply < GAP then
		SLog(("HEARD skip why=gap g=%s n=%d"):format(Short(guid), n))
		return false
	end
	lastReply = now
	replied[id] = now
	rorder[#rorder + 1] = id
	while #rorder > KEEP do replied[table.remove(rorder, 1)] = nil end
	local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
	local ok, res = false, nil
	if fn then ok, res = pcall(fn, ns.SYNC.prefix, ("H:1:%s:%d:%s%s"):format(guid, n, me,
		ns.Dev and ns.Dev() and ":a" or ""), ch, target) end
	local good = ok and (res == nil or res == true or res == 0)
	SLog(("HEARD send ch=%s g=%s n=%d ok=%d"):format(ch, Short(guid), n, good and 1 or 0))
	return good
end
