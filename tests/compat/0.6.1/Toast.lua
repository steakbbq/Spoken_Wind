-- Spoken Wind: achievement toast. OUR OWN frame, made to look like the game's
-- achievement alert (the game's own art in Interface\AchievementFrame), in the
-- friend toast's corner. Never AchievementAlertSystem, AlertFrame, BNToastFrame or
-- any other Blizzard frame: BNToastFrame's spot is only read.
-- Show: slide up + fade in, a glow, a shine sweep, the game's toast sound (Sound
-- On only, max one per SOUND_GAP s). SHOW s, fade FADE s, then the next one in the
-- queue. A click hides it. No mouse in combat, no key or pad binding.
-- Art missing on this client: that texture hides; no alert background = the
-- friend toast backdrop (the 0.4 look, bigger). Made on the first toast only.
local _, ns = ...

local SHOW, FADE, IN = 6, 0.5, 0.25
local W, H, ICON, ICON_FRAME = 360, 100, 48, 70
local SLIDE = 24              -- px it slides up on show
local GLOW_T, SHINE_T = 0.6, 0.9
local SHINE_W, SHINE_H = 80, 82
local SOUND_GAP = 1           -- s: toasts back to back = one sound
local SOUND_ID = 18019        -- the friend toast sound kit (SOUNDKIT.UI_BNET_TOAST wins when it exists)
local QUEUE_MAX = 20
local AF = "Interface\\AchievementFrame\\"
local ART = {   -- the friend toast art (same as the game's BACKDROP_TOAST_12_12)
	bgFile = "Interface\\FriendsFrame\\UI-Toast-Background",
	edgeFile = "Interface\\FriendsFrame\\UI-Toast-Border",
	tile = true, tileEdge = true, tileSize = 12, edgeSize = 12,
	insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

ns.TOAST_ART = ART   -- the rewards grid uses the same art

local f, cur, t0, lastSound
local queue = {}

local function Scale(frame, ui)
	return (frame.GetEffectiveScale and frame:GetEffectiveScale() or ui) / ui
end

-- Bottom-left spot in UIParent units: the game toast's spot (above it while it
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

local function Place(dy)
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", f.x, f.y - dy)
end

-- The game's toast sound: Sound On only, once per SOUND_GAP s. 1 = played.
local function Sound()
	if not (ns.SoundOn and ns.SoundOn()) or type(PlaySound) ~= "function" then return 0 end
	local t = GetTime()
	if lastSound and t - lastSound < SOUND_GAP then return 0 end
	lastSound = t
	local kit = type(SOUNDKIT) == "table" and tonumber(SOUNDKIT.UI_BNET_TOAST) or SOUND_ID
	local ok, willPlay = pcall(PlaySound, kit, "SFX")
	return (ok and willPlay ~= false) and 1 or 0
end

local function Next()
	cur = table.remove(queue, 1)
	if not cur then f:Hide() return end
	f.icon:SetTexture(cur.icon)
	f.name:SetText(cur.color .. cur.name .. "|r")
	f.x, f.y = Spot()
	f.sliding = true
	Place(SLIDE)
	f:SetAlpha(0)
	if f.glow.ok then f.glow:SetAlpha(0) f.glow:Show() end
	if f.shine.ok then f.shine:SetAlpha(0) f.shine:Show() end
	f:EnableMouse(not (InCombatLockdown and InCombatLockdown()))
	t0 = GetTime()
	f:Show()
	if ns.Log then ns.Log(("TOAST id=%s sound=%d"):format(cur.id or "?", Sound())) end
end

local function Tick()
	local dt = GetTime() - t0
	if dt >= SHOW + FADE then Next() return end
	if dt < IN then
		local p = dt / IN
		f:SetAlpha(p)
		Place(SLIDE * (1 - p))
	else
		if f.sliding then f.sliding = false Place(0) end
		f:SetAlpha(dt > SHOW and 1 - (dt - SHOW) / FADE or 1)
	end
	if f.glow.ok and f.glow:IsShown() then
		if dt < GLOW_T then f.glow:SetAlpha(math.sin(math.pi * dt / GLOW_T)) else f.glow:Hide() end
	end
	if f.shine.ok and f.shine:IsShown() then
		if dt < SHINE_T then
			local p = dt / SHINE_T
			f.shine:SetAlpha(math.sin(math.pi * p))
			f.shine:ClearAllPoints()
			f.shine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", math.floor((W - SHINE_W) * p + 0.5), 8)
		else
			f.shine:Hide()
		end
	end
end

-- One texture of the game's art. ok = false when this client has no such file.
local function Art(layer, file, w, h, l, r, t, b, add)
	local tex = f:CreateTexture(nil, layer)
	tex.ok = tex:SetTexture(AF .. file) ~= false
	if w then tex:SetSize(w, h) end
	if l then tex:SetTexCoord(l, r, t, b) end
	if add then tex:SetBlendMode("ADD") end
	if not tex.ok then tex:Hide() end
	return tex
end

local function Build()
	f = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(W, H)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f.bg = Art("BACKGROUND", "UI-Achievement-Alert-Background", nil, nil, 0, 0.605, 0, 0.703)
	f.bg:SetAllPoints(f)
	if not f.bg.ok and f.SetBackdrop then f:SetBackdrop(BACKDROP_TOAST_12_12 or ART) end
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(ICON, ICON)
	f.icon:SetPoint("CENTER", f, "LEFT", 44, 2)
	f.iconFrame = Art("OVERLAY", "UI-Achievement-IconFrame", ICON_FRAME, ICON_FRAME, 0, 0.5625, 0, 0.5625)
	f.iconFrame:SetPoint("CENTER", f, "LEFT", 43, 3)
	f.glow = Art("OVERLAY", "UI-Achievement-Alert-Glow", W + 120, H + 95, 0, 0.78125, 0, 0.66796875, true)
	f.glow:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.shine = Art("OVERLAY", "UI-Achievement-Alert-Glow", SHINE_W, SHINE_H, 0.78125, 0.912109375, 0, 0.28125, true)
	f.shine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 8)
	f.top = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.top:SetPoint("TOP", f, "TOP", 22, -22)
	f.top:SetText("Achievement")
	f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	f.name:SetPoint("CENTER", f, "CENTER", 30, -6)
	f.name:SetWidth(W - 110)
	f.name:SetWordWrap(false)
	f:SetScript("OnMouseUp", function() Next() end)
	f:SetScript("OnUpdate", Tick)
	-- combat: no mouse at all, so it never takes a click meant for the game
	f:SetScript("OnEvent", function(_, event) f:EnableMouse(event == "PLAYER_REGEN_ENABLED") end)
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:Hide()
	if ns.Log then
		ns.Log(("TOAST art=%d icon=%d glow=%d"):format(f.bg.ok and 1 or 0, f.iconFrame.ok and 1 or 0, f.glow.ok and 1 or 0))
	end
end

-- Queues a toast for an achievement row. Returns true when it is queued.
function ns.Toast(row)
	if not f then Build() end
	if #queue >= QUEUE_MAX then return false end
	queue[#queue + 1] = { id = row.id, icon = ns.AchIcon(row), name = row.name, color = ns.AchColor(row.q) }
	if not cur then Next() end
	return true
end

function ns.ToastFrame() return f end
