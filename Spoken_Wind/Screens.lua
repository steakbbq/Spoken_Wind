-- Spoken Wind screens: the glue between the generated UI files (UI\*.lua: ns.Look, ns.Looks) and SW data.
-- The UI files only define tables at load. Frames are made here, when a screen is first needed.
-- Rules: own frames only. No keyboard, no ESC close. Never the design's sample text (fake names).
local ADDON, ns = ...
local Look = ns.Look

-- Fonts: the 3 shipped files. Some clients refuse SetFont on a font file in some addon folders,
-- so Look tests each file once on a hidden string (log: "UI font file=<file> ok=Spoken_Wind|none").
-- A file that does not load: Look retries (log: "UI font retry ..."); its texts use the game font.
local FONT_DIR = "Interface\\AddOns\\Spoken_Wind\\Media\\Fonts\\"
local FONTS = { Lato = "Lato.ttf", Barlow = "Barlow-Bold.ttf", DejaVu = "DejaVuSans.ttf" }
ns.FONT_DIR = FONT_DIR

local fontState
-- Once, at PLAYER_LOGIN. -> the BOOT field (font=): ok = all 3 files loaded at the first test;
-- wait = one or more did not (Look retries); login = Look waits for the login; -1 = no Look.
function ns.UIFonts()
	if fontState then return fontState end
	if not (Look and Look.SetFonts and Look.fontRetry) then
		fontState = "-1"
		return fontState
	end
	local map = {}
	for fam, file in pairs(FONTS) do map[fam] = FONT_DIR .. file end
	Look.SetFonts(map)
	local st = Look.fontRetry.state
	fontState = st == "idle" and "ok" or tostring(st)
	return fontState
end

-- After a drag: the screen's own save (ns.UIOnMove), else Look's place store. One hook for all screens (Look.On).
local onMove = setmetatable({}, { __mode = "k" })
function ns.UIOnMove(f, fn) onMove[f] = fn end
if Look and Look.On then
	Look.On("moved", function(f)
		local fn = onMove[f]
		if fn then fn(f) else Look.SavePlace(f) end
	end)
end
