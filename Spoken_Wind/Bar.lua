-- Spoken Wind: the buttons bar (0.8.0 UI). Frames from the generated UI files, made on first use:
--   sw-btns     the bar: achievements button (left click = window, right click = rewards), Fart button, "Heard by" tag
--   sw-rewards  the rewards popup above the bar: 15 commands, earned first (same state = list order, rarest first)
--   sw-tip-btn  the bar tip (hover); sw-tip = the reward tip (hover a reward)
--   sw-hello    the first-run note under the bar: once per account (SpokenWindDB.hello), again from the "?" button
-- Place: SpokenWindDB.rwpos = the bar's bottom left (the old Rewards button key). Drag the bar or a button.
-- Own frames only. No keyboard, no ESC close: the x, a second click on the opener, a click outside or combat closes a popup.
-- Combat: popups and tips shut, the bar takes no mouse, the Fart button shows "Combat".
local _, ns = ...
local Look, Looks = ns.Look, ns.Looks

local LEFT_X = 40   -- no saved place: left edge, middle
local TIPB = { { "Left", "Achievements" }, { "Right", "Rewards" }, { "Fart", "/fart at target" },
	{ "Right-click", "/say" } }

local db
local bar, rw, tipB, tipR, hello   -- refs of sw-btns, sw-rewards, sw-tip-btn, sw-tip, sw-hello
local over                         -- the node under the mouse with a tip open
local dragged                      -- a drag moved the bar: the click that ends it does nothing

local function InCombat() return InCombatLockdown and InCombatLockdown() end
-- No UI files (a broken copy): no bar, no note, no error.
local function HaveUI() return Look ~= nil and Looks ~= nil and Looks["sw-btns"] ~= nil and Looks["sw-hello"] ~= nil end
-- The head logo (sw-ach, sw-hello, sw-rewards): the First Wind icon in white. The design node alone is a flat gold box.
local function Logo(t)
	t:SetTexture(ns.AchIcon(ns.AchRow("first")))
	t:SetVertexColor(1, 1, 1)
end
ns.UILogo = Logo
local function Build(id)
	local L = Looks[id]
	local r = L.build(UIParent, Look.D(L.tokens))
	if r.logo then Logo(r.logo) end
	return r
end

-- The text of a button that has no key (the close "x", the help "?"): its one string.
local function Glyph(node, s)
	for _, r in ipairs({ node:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "FontString" then Look.SetText(r, s) return true end
	end
	return false
end
ns.UIGlyph = Glyph

-- "12/35": main rows done over all main rows (secret rows not counted).
local function AchCount()
	local all = 0
	for _, n in pairs(ns.ACH_MAIN or {}) do all = all + n end
	return ("%d/%d"):format(ns.AchDone and (ns.AchDone()) or 0, all)
end

-- ------------------------------------------------------------ tips
-- A tip box beside owner: rows = { { label, value }, ... }.
local function TipShow(refs, L, owner, title, rows)
	Look.SetText(refs.titleText, title)
	refs._swRows = rows   -- tests: the rows shown now
	Look.GrowList(refs, L.lists[1], #rows, function(r, i)
		Look.SetText(r.l, rows[i][1])
		Look.SetText(r.r, rows[i][2])
	end)
	Look.Refit(refs.root)
	Look.TipBoxShow(owner, L, refs)
end

local function TipHide()
	over = nil
	if tipB then tipB.root:Hide() end
	if tipR then tipR.root:Hide() end
end

local function BarTip(node)
	if InCombat() then return end
	if not tipB then tipB = Build("sw-tip-btn") end
	local rows = {}
	for _, r in ipairs(TIPB) do rows[#rows + 1] = r end
	for _, r in ipairs(ns.HeardTipRows and ns.HeardTipRows() or {}) do rows[#rows + 1] = r end
	over = node
	TipShow(tipB, Looks["sw-tip-btn"], bar.root, "Spoken Wind", rows)
end

-- The tip of reward i (hover in the popup): Rule / Progress / Reward.
local function RewardTip(cell, i)
	if InCombat() then return end
	local r = ns.REWARDS[i]
	local row = ns.AchRow(r.ach)
	local has = ns.AchHas(r.ach)
	local stat = not has and ns.AchStat and ns.AchStat(r.ach) or ""
	local rows = { { "Rule", row.rule } }
	if stat ~= "" then rows[#rows + 1] = { "Progress", stat } end
	rows[#rows + 1] = { "Reward", Look.Run({ { r.cmd, has and "gold" or "dim" } }) }
	if not tipR then tipR = Build("sw-tip") end
	over = cell
	TipShow(tipR, Looks["sw-tip"], cell, row.name, rows)
end

-- The achievements window (AchWin.lua): the same tip box (sw-tip) beside owner. Not in combat.
function ns.UITip(owner, title, rows)
	if InCombat() or not (Looks and Looks["sw-tip"]) then return false end
	if not tipR then tipR = Build("sw-tip") end
	over = owner
	TipShow(tipR, Looks["sw-tip"], owner, title, rows)
	return true
end

-- owner nil = hide any tip; else only the tip of owner.
function ns.UITipHide(owner)
	if owner == nil or over == owner then TipHide() end
end

-- The bar shows now (the Rewards button of the window needs it).
function ns.BarShown() return bar ~= nil and bar.root:IsShown() end

-- ------------------------------------------------------------ the bar
-- Every text of the bar from the data. Safe any time (bar not made = nothing to do).
local function Draw()
	if not bar then return end
	Look.SetText(bar.achN, AchCount())
	local v = ns.BtnView and ns.BtnView() or { phase = "base", count = "" }
	local state, label, icon = nil, "Fart", ns.BTN and ns.BTN.icon
	if InCombat() then
		state, label = "off", "Combat"
	elseif v.phase == "ready" then
		state, label, icon = "warn", ("Tell? %d"):format(v.tell or 0), v.iconW or icon
	end
	Look.State(bar.fart, state)
	Look.SetText(bar.fartL, label)
	if icon then bar.fartIcon:SetTexture(icon) end
	Look.SetText(bar.fartW, v.count or "")
	Look.SetText(bar.fartS, v.say or "")
	local tag, n
	if ns.HeardTag then tag, n = ns.HeardTag() end
	if tag then
		Look.SetText(bar.heardByText, tag)
		Look.State(bar.heardBy, (n or 0) > 0 and "good" or nil)
		bar.heardBy:Show()
	else
		bar.heardBy:Hide()
	end
	Look.Refit(bar.root)
	if tipB and tipB.root:IsShown() and over then BarTip(over) end   -- an open tip shows the counts of now
end
ns.BarDraw = Draw

local function Place()
	local f = bar.root
	f:ClearAllPoints()
	local p = db.rwpos
	if p then f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
	else f:SetPoint("LEFT", UIParent, "LEFT", LEFT_X, 0) end
end

local function Moved(f)
	local l, b = f:GetLeft(), f:GetBottom()
	if l and b then db.rwpos = { x = math.floor(l + 0.5), y = math.floor(b + 0.5) } end
	Place()
end

local function Mouse(on)
	for _, k in ipairs({ "root", "ach", "fart" }) do bar[k]:EnableMouse(on) end
end

local RewardsHide, RewardsToggle

local function BuildBar()
	bar = Build("sw-btns")
	Looks["sw-btns"].open(bar)
	-- the /say wait (right click on the Fart button): red, top left of its icon; empty when free
	bar.fartS = bar.fart:CreateFontString(nil, "OVERLAY")
	Look.FontSet(bar.fartS, "Interface\\AddOns\\Spoken_Wind\\Media\\Fonts\\Lato.ttf", Look.Size("num"))
	bar.fartS:SetPoint("TOPLEFT", bar.fartIcon, "TOPLEFT", 1, -1)
	bar.fartS:SetText("")
	bar.achIcon:SetTexture(ns.AchIcon(ns.AchRow("first")))
	if ns.UIOnMove then ns.UIOnMove(bar.root, Moved) end
	-- a drag on a button moves the bar too (the buttons cover it)
	for _, k in ipairs({ "ach", "fart" }) do
		local b = bar[k]
		b:RegisterForDrag("LeftButton")
		b:HookScript("OnMouseDown", function() dragged = false end)
		b:SetScript("OnDragStart", function()
			if InCombat() then return end
			dragged = true
			TipHide()
			bar.root:StartMoving()
		end)
		b:SetScript("OnDragStop", function()
			bar.root:StopMovingOrSizing()
			Moved(bar.root)
		end)
		b:HookScript("OnEnter", function(self) BarTip(self) end)
		b:HookScript("OnLeave", function(self) if over == self then TipHide() end end)
	end
	bar.ach:HookScript("OnClick", function(_, button)
		if dragged then dragged = false return end
		if InCombat() then return end
		TipHide()
		if button == "RightButton" then RewardsToggle()
		elseif ns.AchToggle then ns.AchToggle() end
	end)
	bar.fart:HookScript("OnClick", function(_, button)
		if dragged then dragged = false return end
		if button == "RightButton" then
			if ns.BtnSay then ns.BtnSay() end
			return
		end
		if button ~= "LeftButton" then return end
		if ns.BtnClick then ns.BtnClick() end
	end)
	-- combat: popups and tips shut, no mouse; the Fart button's checks (combat, target)
	local f = bar.root
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:SetScript("OnEvent", function(_, event)
		if ns.BtnEvent then ns.BtnEvent(event) end
		if event == "PLAYER_REGEN_DISABLED" then
			RewardsHide()
			TipHide()
			if hello then hello.root:Hide() end
			Mouse(false)
		elseif event == "PLAYER_REGEN_ENABLED" then
			Mouse(true)
		end
		Draw()
	end)
	Mouse(not InCombat())
	Place()
end

-- ------------------------------------------------------------ rewards popup
-- Earned first; same state = list order (the list is rarest first).
local function Order()
	local list = {}
	for i in ipairs(ns.REWARDS) do list[#list + 1] = i end
	table.sort(list, function(a, b)
		local ha, hb = ns.AchHas(ns.REWARDS[a].ach), ns.AchHas(ns.REWARDS[b].ach)
		if ha ~= hb then return ha end
		return a < b
	end)
	return list
end

-- One half of a pooled row: reward i, or nil = hidden. The hooks go on once; they read the row's reward now.
local function Cell(r, side, i)
	local cell = r["cell" .. side]
	r["_sw" .. side] = i
	if not i then cell:Hide() return end
	local rd = ns.REWARDS[i]
	local has = ns.AchHas(rd.ach)
	r["icon" .. side]:SetTexture(ns.AchIcon(ns.AchRow(rd.ach)))
	Look.SetText(r["cmd" .. side], rd.cmd)
	Look.SetText(r["n" .. side], not has and ns.AchStat and ns.AchStat(rd.ach) or "")
	Look.State(cell, not has and "off" or nil)
	cell:Show()
	if not r["_swHook" .. side] then
		r["_swHook" .. side] = true
		cell:HookScript("OnClick", function(_, button)
			local k = r["_sw" .. side]
			if not k or button ~= "LeftButton" or InCombat() then return end
			if ns.RewardUse(k, "button") then RewardsHide() end
		end)
		cell:HookScript("OnEnter", function(self) local k = r["_sw" .. side] if k then RewardTip(self, k) end end)
		cell:HookScript("OnLeave", function(self) if over == self then TipHide() end end)
	end
end

local function RewardsDraw()
	if not (rw and rw.root:IsShown()) then return end
	local n = 0
	for _, r in ipairs(ns.REWARDS) do if ns.AchHas(r.ach) then n = n + 1 end end
	Look.SetText(rw.count, ("%d/%d"):format(n, #ns.REWARDS))
	local list = Order()
	rw._swRows = {}   -- tests: the row refs shown now
	Look.GrowList(rw, Looks["sw-rewards"].lists[1], math.ceil(#list / 2), function(r, k)
		rw._swRows[k] = r
		Cell(r, "A", list[2 * k - 1])
		Cell(r, "B", list[2 * k])
	end)
	Look.Refit(rw.root)
end

-- Above the bar; below it when the top of the screen is too close.
local function RewardsPlace()
	local f = rw.root
	Looks["sw-rewards"].open(rw, bar.root)
	local top, uh, h = bar.root:GetTop(), UIParent:GetHeight(), f:GetHeight()
	if top and uh and h and top + 4 + h > uh then
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", bar.root, "BOTTOMLEFT", 0, -4)
	end
end

RewardsHide = function()
	if rw then rw.root:Hide() end
end

-- Right click on the achievements button, the Rewards button of the achievements window. True = shown now.
RewardsToggle = function()
	if InCombat() or not (bar and bar.root:IsShown()) then return false end
	if not rw then
		rw = Build("sw-rewards")
		rw.root:Hide()   -- a new frame is shown; the toggle below shows it
		Glyph(rw.close, "\195\151")
		rw.close:HookScript("OnClick", function() RewardsHide() end)
		-- a click outside the popup and the bar closes it
		rw.root:SetScript("OnEvent", function(self, event)
			if event == "GLOBAL_MOUSE_DOWN" and not self:IsMouseOver() and not bar.root:IsMouseOver() then self:Hide() end
		end)
		rw.root:HookScript("OnHide", function(self)
			pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN")
			if tipR then tipR.root:Hide() end
		end)
	end
	if rw.root:IsShown() then rw.root:Hide() return false end
	rw.root:Show()
	RewardsDraw()
	RewardsPlace()
	pcall(rw.root.RegisterEvent, rw.root, "GLOBAL_MOUSE_DOWN")
	return true
end
ns.RewardsToggle = RewardsToggle

-- Achievements.lua calls this on each earn: the bar count, an open popup.
function ns.RewardRefresh()
	Draw()
	RewardsDraw()
end

-- ------------------------------------------------------------ hello (first run)
local function RandText()
	if not db.random then return "Off" end
	local R = ns.RAND or { min = 2700, span = 1800 }
	return ("On \194\183 %d-%d min"):format(math.floor(R.min / 60), math.floor((R.min + R.span) / 60))
end

local function HelloDraw()
	Look.SetText(hello.v5, RandText())
	Look.SetText(hello.randOffText, db.random and "Random off" or "Random on")   -- a switch: always shown
	Look.Refit(hello.root)
end

-- At the first login, and the "?" button of the achievements window. True = shown.
local function HelloShow(by)
	if InCombat() or not HaveUI() then return false end
	if not hello then
		hello = Build("sw-hello")
		Glyph(hello.close, "\195\151")
		local function Close() hello.root:Hide() end
		hello.ok:HookScript("OnClick", Close)
		hello.close:HookScript("OnClick", Close)
		hello.randOff:HookScript("OnClick", function()
			if InCombat() then return end
			if ns.SetOpt then ns.SetOpt("random", not db.random, "hello") end
			HelloDraw()
		end)
	end
	local owner = bar and bar.root:IsShown() and bar.root or nil
	Looks["sw-hello"].open(hello, owner)
	if not owner then
		hello.root:ClearAllPoints()
		hello.root:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	hello.root:Show()
	HelloDraw()
	db.hello = true
	ns.Log("HELLO by=" .. tostring(by or "first"))
	return true
end
ns.HelloShow = HelloShow

-- ------------------------------------------------------------ show / hide (Options: Rewards button)
-- Rewards.lua (ADDON_LOADED). hello: true once the note was shown on this account.
function ns.BarInit(saved)
	db = saved
	if db.hello ~= true then db.hello = nil end
end

-- Core at PLAYER_LOGIN, after the bar: the first login on this account shows the hello note.
function ns.BarLogin()
	if db.hello == true then return false end
	return HelloShow("first")
end

-- Shows or hides the bar per db.rwbtn. Made on first use.
function ns.BarSync()
	if not HaveUI() then return end
	if db.rwbtn then
		if not bar then BuildBar() end
		bar.root:Show()
		if ns.BtnShow then ns.BtnShow(true) end
		Draw()
	elseif bar then
		bar.root:Hide()
		RewardsHide()
		TipHide()
		if ns.BtnShow then ns.BtnShow(false) end
	end
end

-- Tests: the built refs (nil = not made yet).
function ns.BarRefs() return bar, rw, tipB, tipR, hello end
