-- Spoken Wind: Options -> AddOns -> Spoken Wind (+ Fart log, Changelog, Credits sub-pages).
-- 0.8.0: four own canvas pages from the generated UI files (UI\sw-options, sw-fartlog, sw-changelog,
-- sw-credits). Own frames and own controls: no Settings setting objects, no search tags, no window shell
-- (no drag, no strata, no ESC). A control writes SpokenWindDB as /wind does: db[key] = v, then ns.OnOpt(key)
-- (the OPT log + side effects). The Dev rows show only with the dev folder (Spoken_Wind_Dev, never shipped).
-- Old clients with no canvas sub-pages: one text page (slash help + changelog + credits), no controls.
local _, ns = ...

local NAME = "Spoken Wind"
local NBSP, DOT = "\194\160", "\194\183"
local LQ, RQ = "\226\128\185", "\226\128\186"   -- the stepper arrows
local TOGS = { "on", "self", "random", "rwbtn" }
local CHS = { Master = "chMaster", SFX = "chSFX", Dialog = "chDialog" }
local STEPS = { cd = { 0.5, "%g s" }, wait = { 10, "%d ms" } }   -- key -> step, label (limits: 0 .. ns.CD_MAX / ns.WAIT_MAX)
local HOLD_T, HOLD_DT = 0.4, 0.08   -- an arrow held down: repeats after 0.4 s, one step per 0.08 s
local ARROW_OFF = 0.4               -- alpha of an arrow at its limit (a click there does nothing)
local Q = { [0] = "poor", "common", "uncommon", "rare", "epic", "legend", "artifact" }

-- ------------------------------------------------------------ changelog text (old-client page)
-- Lines fit one page (no scroll bar): at most MAX_H px tall; older versions -> "+N older".
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

-- ------------------------------------------------------------ credits text
local WRAP, SEP = 56, " · "   -- bytes per tester line, between names
local CRED_H = 160   -- px for the credits on the text-only page (old clients)
local INSP_W, INSP_LINES = 480, 5   -- the "Inspired by" text: wrap width (px), lines kept free for it
local INSP_H = GAP + LINE * (1 + INSP_LINES)   -- px kept free under the credits: the label + the text

-- px from the first line's top to the last line's bottom (the same math as DrawLines).
local function Px(lines)
	local h = 0
	for _, l in ipairs(lines) do h = h + LINE + (l[3] == 0 and GAP or 0) end
	return h
end

-- A class color as "rrggbb". Read only: C_ClassColor first, else RAID_CLASS_COLORS; "ffffff" (white)
-- when the token is unknown.
function ns.ClassHex(token)
	local c
	if type(token) == "string" and token ~= "" then
		if C_ClassColor and C_ClassColor.GetClassColor then
			local ok, cc = pcall(C_ClassColor.GetClassColor, token)
			if ok then c = cc end
		end
		if type(c) ~= "table" and type(RAID_CLASS_COLORS) == "table" then c = RAID_CLASS_COLORS[token] end
	end
	if type(c) ~= "table" then return "ffffff" end
	local function B(v) return type(v) == "number" and math.max(0, math.min(255, math.floor(v * 255 + 0.5))) or nil end
	local r, g, b = B(c.r), B(c.g), B(c.b)
	if not (r and g and b) then return "ffffff" end
	return ("%02x%02x%02x"):format(r, g, b)
end

-- One credits name: "Name", or { "Name", "CLASS" } = the name in its class color. Returns the text and
-- its shown bytes (the color code does not count), or nil.
local function Entry(e)
	if type(e) == "string" and e ~= "" then return e, #e end
	if type(e) == "table" and type(e[1]) == "string" and e[1] ~= "" then
		return "|cff" .. ns.ClassHex(e[2]) .. e[1] .. "|r", #e[1]
	end
	return nil
end

-- { text, font, indent } rows: Author + the name, Testers + the names packed in
-- lines of at most WRAP shown bytes. maxH: px budget; testers past it -> "+N more".
function ns.CreditsLines(maxH)
	maxH = maxH or MAX_H
	local c = type(ns.CREDITS) == "table" and ns.CREDITS or {}
	local out = {}
	local author = Entry(c.author)
	if author then
		out[#out + 1] = { "Author", "GameFontNormal", 0 }
		out[#out + 1] = { author, "GameFontHighlight", 12 }
	end
	local rows = {}   -- { text, names in it, shown bytes }
	for _, e in ipairs(type(c.testers) == "table" and c.testers or {}) do
		local text, n = Entry(e)
		if text then
			local r = rows[#rows]
			if r and r[3] + #SEP + n <= WRAP then
				r[1], r[2], r[3] = r[1] .. SEP .. text, r[2] + 1, r[3] + #SEP + n
			else
				rows[#rows + 1] = { text, 1, n }
			end
		end
	end
	if #rows == 0 then return out end
	out[#out + 1] = { "Testers", "GameFontNormal", 0 }
	local h, left = Px(out), 0
	for _, r in ipairs(rows) do left = left + r[2] end
	for i, r in ipairs(rows) do
		local more = i < #rows and LINE or 0   -- room for the "+N more" line
		if h + LINE + more > maxH then break end
		out[#out + 1] = { r[1], "GameFontHighlight", 12 }
		h, left = h + LINE, left - r[2]
	end
	if left > 0 then out[#out + 1] = { "+" .. left .. " more", "GameFontDisable", 12 } end
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

-- The "Inspired by" text (ns.CREDITS.inspired, shown as is), or nil.
local function Inspired()
	local c = type(ns.CREDITS) == "table" and ns.CREDITS or {}
	return type(c.inspired) == "string" and c.inspired ~= "" and c.inspired or nil
end

-- "Inspired by" + the text as one string, wrapped at INSP_W, on f from y down. Returns the y under it.
local function DrawInspired(f, y)
	local t = Inspired()
	if not t then return y end
	y = DrawLines(f, { { "Inspired by", "GameFontNormal", 0 } }, y)
	local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("TOPLEFT", 28, y)
	fs:SetWidth(INSP_W)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	fs:SetText(t)
	return y - math.max(LINE, math.ceil(fs:GetStringHeight()))
end

-- A plain frame with a title: the game's canvas pages size and place it.
local function TextPage(title)
	local f = CreateFrame("Frame")
	local fs = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	fs:SetPoint("TOPLEFT", 16, -16)
	fs:SetText(title)
	return f
end

-- ------------------------------------------------------------ the canvas pages (0.8.0)
local Look, Looks = ns.Look, ns.Looks
local db
local P = {}      -- page refs: opt, log, chg, cred
local subs = {}   -- sub-page categories: log, chg, cred
local held        -- an arrow held down: { key, dir, from, nextT }

local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- "4,210"
local function Comma(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local k
	repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end

-- A page: a plain frame + the screen in it. No window shell (L.open): no drag, no strata, no ESC, no saved place.
local function Page(id)
	local L = Looks[id]
	local f = CreateFrame("Frame")
	local refs = L.build(f, Look.D(L.tokens))
	refs.root:SetPoint("TOPLEFT")
	return f, refs
end

local function Max(key) return key == "cd" and (ns.CD_MAX or 30) or (ns.WAIT_MAX or 300) end

-- The main page: every control = the save now.
local function OptDraw()
	local r = P.opt
	if not (r and db) then return end
	Look.Tag(r.ver, tostring(ns.VERSION))
	for _, k in ipairs(TOGS) do
		local on = db[k] and true or false
		Look.State(r[k], on and "on" or nil)
		Look.SetText(r[k], on and "On" or "Off")
	end
	for v, id in pairs(CHS) do Look.State(r[id], db.ch == v and "sel" or nil) end
	for k, st in pairs(STEPS) do
		local v = tonumber(db[k]) or 0
		Look.SetText(r[k], st[2]:format(v))
		r[k .. "Down"]:SetAlpha(v <= 0 and ARROW_OFF or 1)
		r[k .. "Up"]:SetAlpha(v >= Max(k) and ARROW_OFF or 1)
	end
	local dev = ns.Dev and ns.Dev() and true or false
	for _, n in ipairs({ "secDev", "testR" }) do
		if dev then r[n]:Show() else r[n]:Hide() end
	end
	Look.Refit(r.root)
end

-- A click: the save, the OPT log + side effects (Core), the page.
local function Set(key, v)
	if db[key] == v then return end
	db[key] = v
	ns.OnOpt(key)
	OptDraw()
end

-- One step of a stepper (an arrow at its limit does nothing). true = the value moved.
local function Bump(key, dir)
	local step = STEPS[key][1]
	local v = math.floor((tonumber(db[key]) or 0) / step + 0.5) * step + dir * step
	v = math.max(0, math.min(Max(key), v))
	if v == db[key] then return false end
	db[key] = v
	OptDraw()
	return true
end

-- The held arrow lets go: one OPT log for the whole hold.
local function Release()
	local h = held
	held = nil
	if P.opt then P.opt.root:SetScript("OnUpdate", nil) end
	if h and db[h.key] ~= h.from then ns.OnOpt(h.key) end
end

local function HoldTick()
	if not held then return end
	if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then Release() return end   -- let go off the arrow
	local now = GetTime()
	if now < held.nextT then return end
	held.nextT = now + HOLD_DT
	if not Bump(held.key, held.dir) then Release() end   -- at the limit: the hold ends
end

local function Arrow(btn, key, dir)
	btn:HookScript("OnMouseDown", function(_, button)
		if button and button ~= "LeftButton" then return end
		Release()
		held = { key = key, dir = dir, from = db[key], nextT = GetTime() + HOLD_T }
		if Bump(key, dir) then P.opt.root:SetScript("OnUpdate", HoldTick) else held = nil end
	end)
	btn:HookScript("OnMouseUp", Release)
end

-- A sub-page in the game's Options (a Pages button). Not in combat. Log "OPT page= ok=".
local function OpenSub(k)
	if InCombat() then return false end
	local c = subs[k]
	local id = c and (c.GetID and c:GetID() or c.ID)
	local ok = false
	if id and Settings and Settings.OpenToCategory then ok = pcall(Settings.OpenToCategory, id) end
	ns.Log(("OPT page=%s ok=%d"):format(k, ok and 1 or 0))
	return ok
end

local function BindOpt(f, r)
	for v, id in pairs(CHS) do Look.SetText(r[id], v) end
	for k in pairs(STEPS) do
		Look.SetText(r[k .. "Down"], LQ)
		Look.SetText(r[k .. "Up"], RQ)
	end
	Look.Tag(r.devTag, "Dev")
	for _, k in ipairs(TOGS) do
		r[k]:HookScript("OnClick", function() Set(k, not db[k]) end)
	end
	for v, id in pairs(CHS) do
		r[id]:HookScript("OnClick", function() Set("ch", v) end)
	end
	for k in pairs(STEPS) do
		Arrow(r[k .. "Down"], k, -1)
		Arrow(r[k .. "Up"], k, 1)
	end
	r.defaults:HookScript("OnClick", function()
		for k, v in pairs(ns.DEFAULTS) do Set(k, v) end
	end)
	r.achOpen:HookScript("OnClick", function() if ns.AchOpen then ns.AchOpen() end end)
	r.pgLog:HookScript("OnClick", function() OpenSub("log") end)
	r.pgLogC:HookScript("OnClick", function() OpenSub("chg") end)
	r.pgCred:HookScript("OnClick", function() OpenSub("cred") end)
	r.testPlay:HookScript("OnClick", function() if ns.Dev() and ns.Test then ns.Test() end end)
	f:HookScript("OnShow", OptDraw)
	r.root:HookScript("OnHide", Release)
	OptDraw()   -- the values (and the Dev rows hidden) from the start
end

-- /wind and the hello note change the save: the shown page follows.
function ns.OptRedraw()
	if P.opt and P.opt.root:IsVisible() then OptDraw() end
end

-- The fart log page: totals + the rows (pages, newest first). reset: back to page 1.
local function LogDraw(reset)
	local r = P.log
	if not (r and ns.FartLogRows) then return end
	local s = ns.FartLogStats()
	Look.SetText(r.today, Comma(s.today))
	Look.SetText(r.all, Comma(s.all))
	local rows = ns.FartLogRows()
	Look.Pages(r, Looks["sw-fartlog"].lists[1], #rows, function(x, i)
		local l = rows[i]
		Look.SetText(x.when, l.when)
		Look.SetText(x.who, Look.Run({ { l.who, l.me and "gold" or "text" } }))
		Look.SetText(x.snd, l.name and Look.Run({ { "#" .. l.num .. NBSP, "dim" }, { l.name, Q[l.q] or "common" } })
			or Look.Run({ { "#" .. l.num .. NBSP .. "?", "dim" } }))
		Look.SetText(x.voice, l.voice)
	end, { reset = reset or nil })
end

-- A fart got a sound: the shown page follows (same page).
function ns.FartLogRedraw()
	if P.log and P.log.root:IsVisible() then LogDraw() end
end

-- The changelog: one row per line; the version on its first line, and again on a page's first row.
local function ChgDraw(reset)
	local r = P.chg
	Look.Tag(r.ver, tostring(ns.VERSION))   -- "sel" = the screen's own state
	local rows = {}
	for _, row in ipairs(ns.CHANGELOG or {}) do
		for j, t in ipairs(row) do rows[#rows + 1] = { ver = row.v, first = j == 1, t = t } end
	end
	Look.Pages(r, Looks["sw-changelog"].lists[1], #rows, function(x, i, ls)
		local l = rows[i]
		local top = (i - 1) % math.max(1, ls.perPage or 1) == 0
		Look.SetText(x.v, (l.first or top) and l.ver or "")
		Look.SetText(x.t, Look.Run({ { DOT .. NBSP, "dim" }, { l.t, "text" } }))
	end, { reset = reset or nil })
end

-- The "Inspired by" text on the Credits screen: one wrapped paragraph under the thanks row (own frame + font
-- string, made once with the page; the screen has free height, the page grows for it).
local LATO = "Interface\\AddOns\\Spoken_Wind\\Media\\Fonts\\Lato.ttf"
local INSP_PAD = 32   -- the screen body's side pads (16 + 16)
local function InspBuild(r)
	local t = Inspired()
	if not t then return end
	local row = Look.Frame(r.body, "insp", "Frame")
	local para = Look.Text(row, "insp:t", LATO, Look.Size("body"), Look.C("text"), "LEFT", "TOP")
	para:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	para:SetWordWrap(true)
	para:SetText(t)
	Look.Kid(r.body, row, { cls = "S", mt = 6 })
	r.insp, r.inspT = row, para
end

-- The credits: author + testers in class colors, the fonts and thanks (static in the screen).
local function CredDraw()
	local r = P.cred
	local c = type(ns.CREDITS) == "table" and ns.CREDITS or {}
	Look.SetText(r.ver, NAME .. " " .. tostring(ns.VERSION))
	Look.SetText(r.author, Entry(c.author) or "")
	local names = {}
	for _, e in ipairs(type(c.testers) == "table" and c.testers or {}) do
		local t = Entry(e)
		if t then names[#names + 1] = t end
	end
	Look.SetText(r.testersN, tostring(#names))
	Look.GrowList(r, Looks["sw-credits"].lists[1], #names, function(x, i) Look.SetText(x.tn, names[i]) end)
	if r.inspT then
		r.inspT:SetWidth(r.root:GetWidth() - INSP_PAD)
		r.insp:SetHeight(math.ceil(r.inspT:GetStringHeight()) + 2)
	end
	Look.Refit(r.root)
end

-- One sub-page under cat; its errors stay its own ("err"), the other pages still come.
local function Sub(cat, k, f, title)
	local ok, c = pcall(Settings.RegisterCanvasLayoutSubcategory, cat, f, title)
	if ok then subs[k] = c end
	return ok and "page" or "err"
end

-- The 0.8.0 pages. nil = this client has no canvas sub-pages (the text page takes over).
local function LookPages()
	local S = Settings
	if not (S.RegisterCanvasLayoutCategory and S.RegisterAddOnCategory and S.RegisterCanvasLayoutSubcategory
		and Look and Looks and Looks["sw-options"] and Looks["sw-fartlog"] and Looks["sw-changelog"]
		and Looks["sw-credits"]) then return nil end
	-- every frame first: a build error registers nothing (the text page takes over)
	local okB, err = pcall(function()
		local fo, ro = Page("sw-options")
		local fl, rl = Page("sw-fartlog")
		local fc, rc = Page("sw-changelog")
		local fr, rr = Page("sw-credits")
		P.opt, P.log, P.chg, P.cred = ro, rl, rc, rr
		P.fo, P.fl, P.fc, P.fr = fo, fl, fc, fr
		BindOpt(fo, ro)
		fl:HookScript("OnShow", function() LogDraw(true) end)
		fc:HookScript("OnShow", function() ChgDraw(true) end)
		InspBuild(rr)
		fr:HookScript("OnShow", CredDraw)
	end)
	if not okB then
		for k in pairs(P) do P[k] = nil end
		ns.panelError = tostring(err)
		return nil
	end
	local okR, cat = pcall(S.RegisterCanvasLayoutCategory, P.fo, NAME)
	if not (okR and cat) or not pcall(S.RegisterAddOnCategory, cat) then
		for k in pairs(P) do P[k] = nil end
		ns.panelError = "register"
		return nil
	end
	ns.optCat = cat
	ns.achpage = "button"
	ns.fartlog = Sub(cat, "log", P.fl, "Fart log")
	ns.changelog = Sub(cat, "chg", P.fc, "Changelog")
	ns.credits = Sub(cat, "cred", P.fr, "Credits")
	return "look"
end

-- Old clients: one page with the slash help + changelog + credits (no controls to taint anything).
local function Canvas()
	local canvas = Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory
	if not canvas and not InterfaceOptions_AddCategory then return "none" end
	local f = TextPage(NAME)
	f.name = NAME
	local help = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	help:SetPoint("TOPLEFT", 16, -40)
	help:SetText("/wind · " .. ns.Help())
	local cred = ns.CreditsLines(CRED_H)
	local insp = Inspired() and INSP_H or 0
	local y = DrawLines(f, ns.ChangelogLines(MAX_H - 24 - Px(cred) - insp), -64)   -- 24 px lower start than the sub-page
	DrawInspired(f, DrawLines(f, cred, y))
	if canvas then
		local cat = Settings.RegisterCanvasLayoutCategory(f, NAME)
		Settings.RegisterAddOnCategory(cat)
		ns.optCat = cat
	else
		InterfaceOptions_AddCategory(f)
	end
	ns.changelog, ns.credits = "text", "text"
	return "canvas"
end

-- The Options button of the achievements window: this page in the game's Options. A click only, not in
-- combat. true = asked the game to open it. Log "OPT open by= ok=".
function ns.OptOpen(by)
	if InCombatLockdown and InCombatLockdown() then return false end
	local cat = ns.optCat
	local id = cat and (cat.GetID and cat:GetID() or cat.ID)
	local ok = false
	if id and Settings and Settings.OpenToCategory then ok = pcall(Settings.OpenToCategory, id) end
	ns.Log(("OPT open by=%s ok=%d"):format(tostring(by or "?"), ok and 1 or 0))
	return ok
end

-- Tests: the page refs (opt, log, chg, cred) and the sub-page categories.
function ns.OptRefs() return P, subs end

-- Called once from Core at PLAYER_LOGIN. Returns the page kind for the BOOT line.
function ns.BuildPanel(saved)
	db = saved
	ns.changelog, ns.fartlog, ns.achpage, ns.credits = "none", "none", "none", "none"
	ns.optCat = nil
	if Settings then
		local kind = LookPages()
		if kind then return kind end
	end
	return Canvas()
end
