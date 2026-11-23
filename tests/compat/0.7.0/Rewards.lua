-- Spoken Wind: rewards. Each achievement unlocks one slash command. Use = ONE
-- custom emote line (the game puts your name in front), then its sound here.
-- Other Spoken Wind users hear the same sound when that exact line comes in
-- (Core: CHAT_MSG_EMOTE, same per-person cooldown as /fart).
-- The chat line comes only from a typed slash or a click: never from a timer,
-- an event or a loop. Locked = one local line, no chat.
-- Commands are made at PLAYER_LOGIN (all addons loaded). A word the game or
-- another addon owns is skipped, never overwritten.
-- Rewards button (Options, default on): a small movable button. Left click = the
-- achievements window (Achievements.lua), right click = the 5x3 reward grid. The Fart button
-- (Button.lua) sits right of it and shows with it.
-- Own frames only. No mouse in combat, no keys in combat, no pad, no bindings.
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
local BTN, CELL, GAP, PAD, COLS = 32, 40, 6, 10, 5
local ROWS = math.ceil(#REWARDS / COLS)
local HOVER_H = 42                          -- three small lines under the grid
local POP_W = 2 * PAD + COLS * CELL + (COLS - 1) * GAP
local POP_H = 2 * PAD + ROWS * CELL + (ROWS - 1) * GAP + 6 + HOVER_H
ns.REWARD_POP = { w = POP_W, h = POP_H, cell = CELL, gap = GAP, pad = PAD, cols = COLS }

local db, lastSend
local btn, pop, hover
local cells = {}

-- Reward number of an exact emote line, else nil.
function ns.RewardByText(text) return byText[text] end

-- Core calls this at ADDON_LOADED: checks the saved button spot.
function ns.RewardInit(saved)
	db = saved
	local p = db.rwpos
	if type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" or p.x ~= p.x or p.y ~= p.y then
		db.rwpos = nil
	end
	lastSend = nil
end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

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

-- ------------------------------------------------------------ button + grid
local function Head()
	local n = 0
	for _, r in ipairs(REWARDS) do if ns.AchHas(r.ach) then n = n + 1 end end
	return ("Rewards %d/%d"):format(n, #REWARDS) .. (ns.HeardHead and ns.HeardHead() or "")
end

local function HoverText(i)
	local r = REWARDS[i]
	local row = ns.AchRow(r.ach)
	if ns.AchHas(r.ach) then return ns.AchColor(row.q) .. r.cmd .. "|r · " .. row.name end
	return "|cff9d9d9d" .. row.name .. " · " .. row.rule .. "|r"
end

local function Refresh()
	for i, c in ipairs(cells) do
		local has = ns.AchHas(REWARDS[i].ach)
		c.icon:SetDesaturated(not has)
		ns.AchRingPaint(c.ring, ns.AchRow(REWARDS[i].ach).q, has)
	end
	if hover then hover:SetText(Head()) end
end

-- Achievements.lua calls this on each earn: an open grid shows it at once.
function ns.RewardRefresh()
	if pop and pop:IsShown() then Refresh() end
end

-- Above the button; below it when the top of the screen is too close.
local function PlacePop()
	pop:ClearAllPoints()
	local top = btn:GetTop()
	local uh = UIParent.GetHeight and UIParent:GetHeight()
	if top and uh and top + 4 + POP_H > uh then
		pop:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -4)
	else
		pop:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 4)
	end
end

local function BuildPop()
	pop = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	pop:SetSize(POP_W, POP_H)
	pop:SetFrameStrata("DIALOG")
	pop:SetClampedToScreen(true)
	if pop.SetBackdrop then pop:SetBackdrop(BACKDROP_TOAST_12_12 or ns.TOAST_ART) end
	pop:EnableMouse(true)   -- a click on a gap does not fall through
	pop:Hide()
	for i = 1, #REWARDS do
		local c = CreateFrame("Frame", nil, pop)
		c:SetSize(CELL, CELL)
		c:SetPoint("TOPLEFT", pop, "TOPLEFT", PAD + ((i - 1) % COLS) * (CELL + GAP),
			-PAD - math.floor((i - 1) / COLS) * (CELL + GAP))
		c.icon = c:CreateTexture(nil, "ARTWORK")
		c.icon:SetSize(CELL, CELL)
		c.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
		c.icon:SetTexture(ns.AchIcon(ns.AchRow(REWARDS[i].ach)))
		c.ring = c:CreateTexture(nil, "OVERLAY")   -- quality ring (grey = locked)
		c.ring:SetSize(CELL, CELL)
		c.ring:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
		c:EnableMouse(true)
		c:SetScript("OnEnter", function() hover:SetText(HoverText(i)) end)
		c:SetScript("OnLeave", function() hover:SetText(Head()) end)
		c:SetScript("OnMouseUp", function(_, button)
			if button ~= "LeftButton" then return end
			if ns.RewardUse(i, "button") then pop:Hide() end
		end)
		cells[i] = c
	end
	hover = pop:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hover:SetPoint("TOPLEFT", pop, "TOPLEFT", PAD, -(PAD + ROWS * CELL + (ROWS - 1) * GAP + 6))
	hover:SetWidth(POP_W - 2 * PAD)
	hover:SetJustifyH("LEFT")
	hover:SetWordWrap(true)
	-- Esc closes; every other key goes on to the game (keys only out of combat).
	pop:SetScript("OnKeyDown", function(self, key)
		if InCombat() then return end
		if key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			self:Hide()
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)
	-- A click outside the grid and the button closes it.
	pop:SetScript("OnEvent", function(self, event)
		if event == "GLOBAL_MOUSE_DOWN" and not self:IsMouseOver() and not btn:IsMouseOver() then self:Hide() end
	end)
	pop:SetScript("OnHide", function(self)
		self:EnableKeyboard(false)
		pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
	end)
end

local function Toggle()
	if InCombat() then return end
	if not pop then BuildPop() end
	if pop:IsShown() then pop:Hide() return end
	PlacePop()
	Refresh()
	pop:Show()
	pop:EnableKeyboard(true)
	pop:SetPropagateKeyboardInput(true)
	pcall(pop.RegisterEvent, pop, "GLOBAL_MOUSE_DOWN")
end

local function PlaceBtn()
	btn:ClearAllPoints()
	local p = db.rwpos
	if p then
		btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
	else
		btn:SetPoint("LEFT", UIParent, "LEFT", 40, 0)
	end
end

local function BuildBtn()
	btn = CreateFrame("Frame", nil, UIParent)
	btn:SetSize(BTN, BTN)
	btn:SetFrameStrata("MEDIUM")
	btn:SetClampedToScreen(true)
	btn:SetMovable(true)
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetSize(BTN, BTN)
	btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
	btn.icon:SetTexture(ns.AchIcon(ns.AchRow("first")))
	btn:SetAlpha(0.85)
	btn:EnableMouse(not InCombat())
	btn:RegisterForDrag("LeftButton")
	btn:SetScript("OnEnter", function(self)
		self:SetAlpha(1)
		if ns.HeardHover then ns.HeardHover(true) end
	end)
	btn:SetScript("OnLeave", function(self)
		self:SetAlpha(0.85)
		if ns.HeardHover then ns.HeardHover(false) end
	end)
	btn:SetScript("OnMouseDown", function(self) self.moved = false end)
	btn:SetScript("OnDragStart", function(self)
		if InCombat() then return end
		self.moved = true
		self:StartMoving()
	end)
	btn:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local l, b = self:GetLeft(), self:GetBottom()
		if l and b then db.rwpos = { x = math.floor(l + 0.5), y = math.floor(b + 0.5) } end
		PlaceBtn()
	end)
	btn:SetScript("OnMouseUp", function(self, button)
		if self.moved then self.moved = false return end
		if button == "LeftButton" then
			if ns.AchToggle then ns.AchToggle() end
		elseif button == "RightButton" then
			Toggle()
		end
	end)
	-- Combat: grid shut, button takes no mouse (never in the way).
	btn:RegisterEvent("PLAYER_REGEN_DISABLED")
	btn:RegisterEvent("PLAYER_REGEN_ENABLED")
	btn:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_REGEN_DISABLED" and pop then pop:Hide() end
		self:EnableMouse(event == "PLAYER_REGEN_ENABLED")
	end)
	PlaceBtn()
end

-- Shows or hides the button per db.rwbtn (Options checkbox). Made on first use.
function ns.RewardSync()
	if db.rwbtn then
		if not btn then BuildBtn() end
		btn:Show()
		if ns.BtnSync then ns.BtnSync(btn, true) end   -- the Fart button, right of it
	elseif btn then
		btn:Hide()
		if pop then pop:Hide() end
		if ns.BtnSync then ns.BtnSync(btn, false) end
	end
	if ns.HeardDraw then ns.HeardDraw() end   -- button off = no Heard text
end

function ns.RewardFrames() return btn, pop, cells, hover end
