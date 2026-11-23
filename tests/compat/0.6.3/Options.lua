-- Spoken Wind: Options -> AddOns -> Spoken Wind (+ Fart log, Changelog sub-pages).
-- Achievements: one button that opens their own window (Achievements.lua).
-- The game's own Settings controls, bound to the same SpokenWindDB keys as
-- /wind, so both always show the same values. Rows are data (ns.PANEL_ROWS).
-- The Test button shows only with the dev folder (Spoken_Wind_Dev, never
-- shipped). It has no search tags (false): tags from addon code taint the
-- settings search. Old clients with no Settings API: a text-only page.
local _, ns = ...

local NAME = "Spoken Wind"
local ROWS = {
	{ key = "on", kind = "check", name = "On", tip = "Fart sounds on / off" },
	{ key = "rwbtn", kind = "check", name = "Rewards button", tip = "Left: achievements · Right: rewards" },
	{ key = "ch", kind = "list", name = "Channel", tip = "Volume slider used",
		choices = { "Master", "SFX", "Dialog" } },
	{ key = "self", kind = "check", name = "Own /fart", tip = "Your own /fart plays too" },
	{ key = "cd", kind = "slider", name = "Cooldown per person", tip = "Min gap per person",
		min = 0, max = 30, step = 0.5, fmt = "%gs" },
	{ key = "wait", kind = "slider", name = "Sync wait", tip = "Max ms to wait for a group fart msg",
		min = 0, max = 300, step = 10, fmt = "%d ms" },
}
ns.PANEL_ROWS = ROWS

-- ------------------------------------------------------------ changelog text
-- Lines fit one page (no scroll bar): at most MAX_H px tall (the sub-page
-- draws from y -40, so its last line sits at -472 or higher); older
-- versions -> "+N older".
local MAX_H = 448
local LINE, GAP = 16, 8   -- px per line, extra px before each version

-- { text, font, indent } rows, newest version first. maxH: px budget.
function ns.ChangelogLines(maxH)
	maxH = maxH or MAX_H
	local out, rows = {}, ns.CHANGELOG or {}
	local shown, h = 0, 0
	for i, row in ipairs(rows) do
		local need = GAP + LINE * (1 + #row)
		local more = i < #rows and GAP + LINE or 0   -- room for the "+N older" line
		if h + need + more > maxH then break end
		out[#out + 1] = { row.v, "GameFontNormal", 0 }
		for _, t in ipairs(row) do out[#out + 1] = { "· " .. t, "GameFontHighlight", 12 } end
		shown, h = shown + 1, h + need
	end
	if shown < #rows then out[#out + 1] = { "+" .. (#rows - shown) .. " older", "GameFontDisable", 0 } end
	return out
end

-- Writes the lines on frame f, from y down. Returns the y under the last line.
local function DrawLines(f, lines, y)
	for _, l in ipairs(lines) do
		if l[3] == 0 then y = y - GAP end
		local fs = f:CreateFontString(nil, "ARTWORK", l[2])
		fs:SetPoint("TOPLEFT", 16 + l[3], y)
		fs:SetText(l[1])
		y = y - LINE
	end
	return y
end

-- A plain frame with a title: the game's canvas pages size and place it.
local function TextPage(title)
	local f = CreateFrame("Frame")
	local fs = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	fs:SetPoint("TOPLEFT", 16, -16)
	fs:SetText(title)
	return f
end

-- Fart log under the main page: own canvas sub-page (FartLog.lua writes its lines).
-- No sub-page API: no fart log page (the log is still kept).
local function FartLog(category)
	if not (Settings.RegisterCanvasLayoutSubcategory and ns.FartLogBind) then return "none" end
	local f = TextPage("Fart log")
	ns.FartLogBind(f)
	Settings.RegisterCanvasLayoutSubcategory(category, f, "Fart log")
	return "page"
end

-- Changelog under the main page: own canvas sub-page, else section rows at the bottom.
local function Changelog(category, layout)
	if Settings.RegisterCanvasLayoutSubcategory then
		local f = TextPage("Changelog")
		DrawLines(f, ns.ChangelogLines(), -40)
		Settings.RegisterCanvasLayoutSubcategory(category, f, "Changelog")
		return "page"
	elseif CreateSettingsListSectionHeaderInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Changelog"))
		for _, l in ipairs(ns.ChangelogLines()) do
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(l[1]))
		end
		return "section"
	end
	return "none"
end

-- ------------------------------------------------------------ pages
local function Vertical(db)
	local category, layout = Settings.RegisterVerticalLayoutCategory(NAME)
	local objs = {}
	for _, row in ipairs(ROWS) do
		local key, default = row.key, ns.DEFAULTS[row.key]
		local s = Settings.RegisterAddOnSetting(category, "SpokenWind_" .. key, key, db, type(default), row.name,
			default)
		s:SetValueChangedCallback(function() ns.OnOpt(key) end)
		objs[key] = s
		if row.kind == "check" then
			Settings.CreateCheckbox(category, s, row.tip)
		elseif row.kind == "slider" then
			local o = Settings.CreateSliderOptions(row.min, row.max, row.step)
			local fmt = row.fmt
			if MinimalSliderWithSteppersMixin and o.SetLabelFormatter then
				o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmt:format(v) end)
			end
			Settings.CreateSlider(category, s, o, row.tip)
		else
			local choices = row.choices
			local function Options()
				local c = Settings.CreateControlTextContainer()
				for _, v in ipairs(choices) do c:Add(v, v) end
				return c:GetData()
			end
			local CreateDropdown = Settings.CreateDropdown or Settings.CreateDropDown
			CreateDropdown(category, s, Options, row.tip)
		end
	end
	if CreateSettingsButtonInitializer and ns.AchOpen then   -- the achievements window (own frame)
		layout:AddInitializer(CreateSettingsButtonInitializer("Achievements", "Open", function() ns.AchOpen() end,
			"Achievements window", false))
		ns.achpage = "button"
	end
	if ns.Dev() and CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("Test", "Play", function() ns.Test() end,
			"Random fart", false))
	end
	Settings.RegisterAddOnCategory(category)
	ns.panelSettings = objs
	local okLog, flog = pcall(FartLog, category)
	ns.fartlog = okLog and flog or "err"
	local ok, kind = pcall(Changelog, category, layout)
	ns.changelog = ok and kind or "err"
	return "vertical"
end

-- Old clients: one page with the slash help + changelog (no controls to taint anything).
local function Canvas()
	local canvas = Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory
	if not canvas and not InterfaceOptions_AddCategory then return "none" end
	local f = TextPage(NAME)
	f.name = NAME
	local help = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	help:SetPoint("TOPLEFT", 16, -40)
	help:SetText("/wind · " .. ns.Help())
	DrawLines(f, ns.ChangelogLines(MAX_H - 24), -64)   -- 24 px lower start than the sub-page
	if canvas then
		Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(f, NAME))
	else
		InterfaceOptions_AddCategory(f)
	end
	ns.changelog = "text"
	return "canvas"
end

-- Called once from Core at PLAYER_LOGIN. Returns the page kind for the BOOT line.
function ns.BuildPanel(db)
	ns.panelSettings, ns.changelog, ns.fartlog, ns.achpage = nil, "none", "none", "none"
	if Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting then
		local ok, kind = pcall(Vertical, db)
		if ok then return kind end
		ns.panelSettings, ns.changelog, ns.fartlog, ns.achpage = nil, "none", "none", "none"
		ns.panelError = tostring(kind)
	end
	return Canvas()
end
