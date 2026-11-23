-- Spoken Wind: achievement toast (0.8.0 UI: sw-toast). OUR OWN frame SpokenWindToast, above the bar
-- (above the rewards popup while it is open over the bar). Bar off: the friend toast's corner (BNToastFrame
-- is only read), else above the chat. Never AchievementAlertSystem, AlertFrame, BNToastFrame or any other
-- Blizzard frame.
-- Show: slide up + fade in, the game's toast sound (Sound On only, max one per SOUND_GAP s). SHOW s, fade
-- FADE s, then the next one in the queue. A click hides it; a left click also opens the achievements window
-- on the row's tab with its tile glowing (ns.AchShow). The mouse on it holds the fade.
-- No mouse in combat or while hidden, no key or pad binding. Made on the first toast only.
-- Text: "Achievement" + the reward command (a row with a reward), the name in its quality color, the rule.
local _, ns = ...
local Look, Looks = ns.Look, ns.Looks

local SHOW, FADE, IN = 6, 0.5, 0.25
local SLIDE = 24              -- px it slides up on show
local GAP = 8                 -- px above the bar (or the open rewards popup)
local SOUND_GAP = 1           -- s: toasts back to back = one sound
local SOUND_ID = 18019        -- the friend toast sound kit (SOUNDKIT.UI_BNET_TOAST wins when it exists)
local QUEUE_MAX = 40   -- more than all rows (the dev "show all" fits)

-- The friend toast art (same as the game's BACKDROP_TOAST_12_12): the old-style windows use it.
ns.TOAST_ART = {
	bgFile = "Interface\\FriendsFrame\\UI-Toast-Background",
	edgeFile = "Interface\\FriendsFrame\\UI-Toast-Border",
	tile = true, tileEdge = true, tileSize = 12, edgeSize = 12,
	insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

local t, f, cur, t0, lastSound   -- t = the sw-toast refs, f = its root frame
local queue = {}

local function InCombat() return InCombatLockdown and InCombatLockdown() end

local function Scale(frame, ui)
	return (frame.GetEffectiveScale and frame:GetEffectiveScale() or ui) / ui
end

-- Bar off: bottom-left spot in UIParent units: the game toast's spot (above it while it
-- is up), else above the chat, else a fixed spot.
local function Spot()
	local ui = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
	local bn = BNToastFrame
	if bn and bn.GetLeft then
		local l, b = bn:GetLeft(), bn:GetBottom()
		if l and b then
			local s = Scale(bn, ui)
			local top = bn:IsShown() and bn:GetTop()
			if top then return l * s, top * s + 4 end
			return l * s, b * s
		end
	end
	local cf = ChatFrame1
	if cf and cf.GetLeft then
		local l, top = cf:GetLeft(), cf:GetTop()
		if l and top then
			local s = Scale(cf, ui)
			return l * s, top * s + 40
		end
	end
	return 20, 240
end

-- The frame it sits on: the rewards popup when it is open over the bar, else the bar; nil = bar off.
local function Owner()
	local bar, rw = nil, nil
	if ns.BarRefs then bar, rw = ns.BarRefs() end
	if not (bar and bar.root:IsShown()) then return nil end
	if rw and rw.root:IsShown() and rw.root:GetPoint(1) == "BOTTOMLEFT" then return rw.root end
	return bar.root
end

local function Place(dy)
	f:ClearAllPoints()
	if f.owner then f:SetPoint("BOTTOMLEFT", f.owner, "TOPLEFT", 0, GAP - dy)
	else f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", f.x, f.y - dy) end
end

-- The game's toast sound: Sound On only, once per SOUND_GAP s. 1 = played.
local function Sound()
	if not (ns.SoundOn and ns.SoundOn()) or type(PlaySound) ~= "function" then return 0 end
	local now = GetTime()
	if lastSound and now - lastSound < SOUND_GAP then return 0 end
	lastSound = now
	local kit = type(SOUNDKIT) == "table" and tonumber(SOUNDKIT.UI_BNET_TOAST) or SOUND_ID
	local ok, willPlay = pcall(PlaySound, kit, "SFX")
	return (ok and willPlay ~= false) and 1 or 0
end

local function Next()
	cur = table.remove(queue, 1)
	if not cur then
		f.hover = false
		f:EnableMouse(false)   -- hidden: never in the way
		f:Hide()
		return
	end
	t.icon:SetTexture(cur.icon)
	Look.SetText(t.name, cur.color .. cur.name .. "|r")
	Look.SetText(t.cmd, cur.cmd or "")
	Look.SetText(t.rule, cur.rule or "")
	Look.Refit(f)
	f.owner = Owner()
	if not f.owner then f.x, f.y = Spot() end
	f.sliding = true
	Place(SLIDE)
	f:SetAlpha(0)
	f:EnableMouse(not InCombat())
	t0 = GetTime()
	f:Show()
	if ns.Log then ns.Log(("TOAST id=%s sound=%d"):format(cur.id or "?", Sound())) end
end

local function Tick()
	local now = GetTime()
	if f.hover and now - t0 > SHOW then t0 = now - SHOW end   -- the mouse is on it: the fade waits
	local dt = now - t0
	if dt >= SHOW + FADE then Next() return end
	if dt < IN then
		local p = dt / IN
		f:SetAlpha(p)
		Place(SLIDE * (1 - p))
	else
		if f.sliding then f.sliding = false Place(0) end
		f:SetAlpha(dt > SHOW and 1 - (dt - SHOW) / FADE or 1)
	end
end

local function Build()
	local L = Looks["sw-toast"]
	t = L.build(UIParent, Look.D(L.tokens))
	f = t.root
	L.open(t)   -- the shell: TOOLTIP strata, clamped; placed per toast
	f:Hide()
	f:EnableMouse(false)
	f:HookScript("OnMouseUp", function(_, button)
		local id = cur and cur.id
		Next()
		if button == "LeftButton" and id and ns.AchShow then
			local tab, glow = ns.AchShow(id)
			if ns.Log then ns.Log(("TOAST click id=%s tab=%s glow=%d"):format(id, tostring(tab), glow and 1 or 0)) end
		end
	end)
	f:HookScript("OnEnter", function() f.hover = true end)
	f:HookScript("OnLeave", function() f.hover = false end)
	f:SetScript("OnUpdate", Tick)
	-- combat: no mouse at all, so it never takes a click meant for the game
	f:SetScript("OnEvent", function(_, event) f:EnableMouse(event == "PLAYER_REGEN_ENABLED" and f:IsShown()) end)
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- The reward command of an achievement row ("" = none).
local function Cmd(id)
	for _, r in ipairs(ns.REWARDS or {}) do if r.ach == id then return r.cmd end end
	return ""
end

-- Queues a toast for an achievement row. Returns true when it is queued. No UI files = false (the chat line).
function ns.Toast(row)
	if not f then
		if not (Look and Looks and Looks["sw-toast"]) then return false end
		Build()
	end
	if #queue >= QUEUE_MAX then return false end
	queue[#queue + 1] = { id = row.id, icon = ns.AchIcon(row), name = row.name, color = ns.AchColor(row.q), q = row.q,
		cmd = Cmd(row.id), rule = row.rule }
	if not cur then Next() end
	return true
end

function ns.ToastFrame() return f end
function ns.ToastRefs() return t end
