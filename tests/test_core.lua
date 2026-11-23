-- Core.lua + Options.lua with a fake client (no game here). Run: python -I tools/lua.py core
-- Proves: one sound per fart, cooldown per person (not global), old keys pruned,
-- on/off, self on/off, channel, never the same sound twice in a row, prints only
-- on /wind or Test, no hooks but the 2 emote calls, no CVars / leaks, every sound file on disk, toc lists
-- every file and has no X- keys (the Spoken addons scan toc keys), a new emote
-- row works with no code change, the options page and /wind share the same values,
-- Test button + /wind test exist only with the dev folder (Spoken_Wind_Dev),
-- fart log: newest first, totals, capped, page fits (no scroll bar),
-- achievements: 15 rows, every rule both ways, own toast (the game's
-- BNToastFrame is only read), queue, fade, click, no mouse in combat, page,
-- secret row 16 (dev Test only, hidden until earned),
-- rewards: 15 commands as approved, chat line only from a slash or a click,
-- clash = skip, exact-text receive with the same cooldown, button + 5x3 grid,
-- sync (0.6.0): same seed pick on 2 clients, wait rule, late message, other faction,
-- one addon message per own key press, step-edge miss rate.
-- test mode (0.6.1): 2 paired clients, seed + clock check, 7 guided steps,
-- results swapped in paced chunks to the partner only, one table on both.
local pass, fail = 0, 0
local out = print
local function ok(name, cond, extra)
	if cond then pass = pass + 1
	else fail = fail + 1 out("FAIL " .. name .. (extra and (" :: " .. tostring(extra)) or "")) end
end

-- ---------------------------------------------------------------- fake client
local now, plays, prints, frames, forbidden, reg
local sent, hw, preLogin = {}, false, nil   -- chat lines out; true only inside a slash or a click
local SY = { timers = {}, hooks = {}, asent = {} }
local TS = { snd = {}, missing = {} }   -- toast: PlaySound calls, art paths this client "has not"   -- sync: timers, the 2 emote hooks, addon messages out
local CLOCK0 = os.time({ year = 2026, month = 11, day = 21, hour = 12, min = 0, sec = 0 })
local clock = CLOCK0
local willPlay = true
local ME, ME_GUID = "Tester", "Player-1-0000AAAA"
local DEF = { on = true, rwbtn = true, ch = "SFX", self = true, cd = 1, wait = 150 }

-- The rest of the frame API, for the 0.8.0 UI files (UI\Look.lua builds frames from tables).
-- Every fake frame, texture and string is "own" (SY.own): hooksecurefunc and names are allowed only on these.
-- Positions: from the points (anchors) and sizes, as the game does; UIParent = 0..1365 x 0..768.
-- A method the fake has not got: recorded in SY.unknownM and nil (as in a client without it).
SY.own = setmetatable({}, { __mode = "k" })
SY.unknownM = {}
local Rich
do
local function Def(o, k, fn) if rawget(o, k) == nil then o[k] = fn end end
local function Strip(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  ")) end
SY.Strip = Strip
local SIDE = { TOPLEFT = { "l", "t" }, TOP = { "c", "t" }, TOPRIGHT = { "r", "t" }, LEFT = { "l", "m" }, CENTER = { "c", "m" },
	RIGHT = { "r", "m" }, BOTTOMLEFT = { "l", "b" }, BOTTOM = { "c", "b" }, BOTTOMRIGHT = { "r", "b" } }
local function IsUIP(o) return type(o) == "table" and rawget(o, "isUIParent") == true end
local function Rect(o, depth)   -- l, r, t, b or nil (no points)
	depth = (depth or 0) + 1
	if depth > 40 then return nil end
	if IsUIP(o) then return 0, 1365, 768, 0 end
	if type(o) ~= "table" or not o.points or #o.points == 0 then return nil end
	local w, h = o:GetWidth(), o:GetHeight()
	local xs, ys = {}, {}
	for _, p in ipairs(o.points) do
		local me, rel, rp, x, y = p[1], p[2], p[3], p[4], p[5]
		local rl, rr, rt, rb = Rect(rel, depth)
		if not rl then return nil end
		local s, rs = SIDE[me], SIDE[rp]
		if not (s and rs) then return nil end
		local rx = rs[1] == "l" and rl or rs[1] == "r" and rr or (rl + rr) / 2
		local ry = rs[2] == "t" and rt or rs[2] == "b" and rb or (rt + rb) / 2
		xs[s[1]] = rx + (x or 0)
		ys[s[2]] = ry + (y or 0)
	end
	local l, r, tp, b
	if xs.l and xs.r then l, r = xs.l, xs.r
	elseif xs.l then l, r = xs.l, xs.l + w
	elseif xs.r then l, r = xs.r - w, xs.r
	elseif xs.c then l, r = xs.c - w / 2, xs.c + w / 2
	else return nil end
	if ys.t and ys.b then tp, b = ys.t, ys.b
	elseif ys.t then tp, b = ys.t, ys.t - h
	elseif ys.b then tp, b = ys.b + h, ys.b
	elseif ys.m then tp, b = ys.m + h / 2, ys.m - h / 2
	else return nil end
	return l, r, tp, b
end
Rich = function(o, otype, parent)
	SY.own[o] = true
	o.otype, o.points = otype, {}
	if parent ~= nil and o.parent == nil then o.parent = parent end
	if parent and SY.own[parent] and otype ~= "Frame" and otype ~= "Button" then
		parent.regions = parent.regions or {}
		parent.regions[#parent.regions + 1] = o
	end
	-- points: the old fake's fields (point / x, y / pt) stay as they were
	local sp, ca = o.SetPoint, o.ClearAllPoints
	o.SetPoint = function(self, a, b, c, d, e)
		if sp then sp(self, a, b, c, d, e) end
		local rel, rp, x, y
		if type(b) == "number" then x, y = b, c
		elseif b ~= nil then rel, rp, x, y = b, c, d, e end
		if type(rel) == "string" then rel = _G[rel] end
		for i, p in ipairs(self.points) do if p[1] == a then table.remove(self.points, i) break end end
		self.points[#self.points + 1] = { a, rel or self.parent, rp or a, x or 0, y or 0 }
	end
	o.ClearAllPoints = function(self)
		if ca then ca(self) end
		self.points = {}
	end
	local sa = o.SetAllPoints
	o.SetAllPoints = function(self, rel)
		if sa then sa(self, rel) end
		rel = rel or self.parent
		self.points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
	end
	Def(o, "GetNumPoints", function(self) return #self.points end)
	Def(o, "GetPoint", function(self, i)
		local p = self.points[i or 1]
		if p then return p[1], p[2], p[3], p[4], p[5] end
	end)
	-- size: SetSize keeps the old w, h fields too
	local ss = o.SetSize
	o.SetSize = function(self, w, h)
		if ss then ss(self, w, h) end
		self.width, self.height = w, h
	end
	local sw = o.SetWidth
	o.SetWidth = function(self, w)
		if sw then sw(self, w) end
		self.width = w
	end
	Def(o, "SetHeight", function(self, h) self.height = h end)
	if otype == "FontString" then
		Def(o, "GetStringWidth", function(self) return #Strip(self.text) * (self.fontSize or 12) * 0.5 end)
		Def(o, "GetUnboundedStringWidth", function(self) return self:GetStringWidth() end)
		Def(o, "GetWidth", function(self) return self.width or self:GetStringWidth() end)
		Def(o, "GetHeight", function(self) return self.height or self:GetStringHeight() end)
	else
		Def(o, "GetWidth", function(self) return self.width or self.w or 0 end)
		Def(o, "GetHeight", function(self) return self.height or self.h or 0 end)
	end
	Def(o, "GetSize", function(self) return self:GetWidth(), self:GetHeight() end)
	-- positions: a test may set .left / .top / ... (the old fake); else from the points
	local function Side(k, i)
		return function(self)
			if rawget(self, k) ~= nil then return rawget(self, k) end
			return (select(i, Rect(self)))
		end
	end
	o.GetLeft, o.GetRight, o.GetTop, o.GetBottom = Side("left", 1), Side("right", 2), Side("top", 3), Side("bottom", 4)
	Def(o, "GetCenter", function(self)
		local l, r, tp, b = Rect(self)
		if l then return (l + r) / 2, (tp + b) / 2 end
	end)
	Def(o, "GetRect", function(self)
		local l, r, tp, b = Rect(self)
		if l then return l, b, r - l, tp - b end
	end)
	-- show / hide / alpha / parent / type
	Def(o, "SetShown", function(self, v) if v then self:Show() else self:Hide() end end)
	Def(o, "GetAlpha", function(self) return self.alpha or 1 end)
	Def(o, "SetAlpha", function(self, a) self.alpha = a end)
	Def(o, "GetParent", function(self) return self.parent end)
	Def(o, "SetParent", function(self, p) self.parent = p end)
	Def(o, "GetObjectType", function() return otype end)
	Def(o, "IsObjectType", function(_, ty) return ty == otype or (ty == "Frame" and otype == "Button")
		or (ty == "Region" and otype ~= "Frame" and otype ~= "Button") end)
	Def(o, "IsForbidden", function() return false end)
	Def(o, "SetDrawLayer", function(self, l, sub) self.layer, self.sublayer = l, sub end)
	Def(o, "GetDrawLayer", function(self) return self.layer or "ARTWORK", self.sublayer or 0 end)
	Def(o, "IsVisible", function(self)
		if not self:IsShown() then return false end
		local p = self.parent
		if IsUIP(p) then return true end
		return p ~= nil and p:IsVisible() == true
	end)
	if otype == "Texture" then
		Def(o, "GetTexture", function(self) return self.path end)
		Def(o, "GetVertexColor", function(self) local c = self.vc or { 1, 1, 1 } return c[1], c[2], c[3], 1 end)
		Def(o, "SetGradient", function(self, ...) self.grad = { ... } end)
		Def(o, "SetRotation", function(self, r) self.rot = r end)
		Def(o, "SetSnapToPixelGrid", function(self, v) self.snap = v end)
		Def(o, "SetTexelSnappingBias", function(self, v) self.bias = v end)
		Def(o, "SetHorizTile", function(self, v) self.htile = v end)
		Def(o, "SetVertTile", function(self, v) self.vtile = v end)
	elseif otype == "FontString" then
		Def(o, "GetText", function(self) return self.text end)
		Def(o, "SetTextColor", function(self, r, g, b, a) self.tc = { r, g, b, a } end)
		Def(o, "GetTextColor", function(self) local c = self.tc or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] or 1 end)
		Def(o, "SetJustifyV", function(self, v) self.justifyV = v end)
		Def(o, "GetJustifyH", function(self) return self.justify or "CENTER" end)
		Def(o, "SetShadowOffset", function(self, x, y) self.shadow = { x, y } end)
		Def(o, "SetShadowColor", function(self, ...) self.shadowC = { ... } end)
		Def(o, "SetMaxLines", function(self, n) self.maxLines = n end)
		Def(o, "SetSpacing", function(self, n) self.spacing = n end)
		Def(o, "SetNonSpaceWrap", function(self, v) self.nsWrap = v end)
		Def(o, "SetIndentedWordWrap", function(self, v) self.indWrap = v end)
		Def(o, "IsShown", function(self) return self.shown end)
		-- the game keeps the last good font when SetFont fails
		local sf = o.SetFont
		o.SetFont = function(self, path, size, flags)
			local okF = sf(self, path, size, flags)
			if okF then self.goodFont = { path, size, flags } end
			return okF
		end
		Def(o, "GetFont", function(self)
			local g = self.goodFont
			if g then return g[1], g[2], g[3] end
		end)
	else
		-- frames and buttons
		Def(o, "GetName", function(self) return self.name end)
		Def(o, "GetChildren", function(self) return unpack(self.kids or {}) end)
		Def(o, "GetNumChildren", function(self) return #(self.kids or {}) end)
		Def(o, "GetRegions", function(self) return unpack(self.regions or {}) end)
		Def(o, "GetNumRegions", function(self) return #(self.regions or {}) end)
		Def(o, "HookScript", function(self, n, fn)
			local old = self.scripts[n]
			self.scripts[n] = old and function(...) old(...) return fn(...) end or fn
		end)
		Def(o, "GetScript", function(self, n) return self.scripts[n] end)
		Def(o, "HasScript", function() return true end)
		Def(o, "SetFrameLevel", function(self, v) self.level = v end)
		Def(o, "GetFrameLevel", function(self)
			if self.level then return self.level end
			local p = self.parent
			return ((p and not IsUIP(p) and p.GetFrameLevel) and p:GetFrameLevel() or 0) + 1
		end)
		Def(o, "GetFrameStrata", function(self)
			if self.strata then return self.strata end
			local p = self.parent
			return (p and not IsUIP(p) and p.GetFrameStrata) and p:GetFrameStrata() or "MEDIUM"
		end)
		Def(o, "SetToplevel", function(self, v) self.toplevel = v end)
		Def(o, "SetScale", function(self, s) self.scale = s end)
		Def(o, "GetScale", function(self) return self.scale or 1 end)
		Def(o, "GetEffectiveScale", function(self)
			local p = self.parent
			return (self.scale or 1) * ((p and p.GetEffectiveScale) and p:GetEffectiveScale() or 1)
		end)
		Def(o, "SetResizable", function(self, v) self.resizable = v end)
		Def(o, "SetResizeBounds", function(self, ...) self.bounds = { ... } end)
		Def(o, "StartSizing", function(self, p) self.sizing = p or true end)
		Def(o, "SetClipsChildren", function(self, v) self.clips = v end)
		Def(o, "SetHitRectInsets", function(self, ...) self.hit = { ... } end)
		Def(o, "RegisterForClicks", function(self, ...) self.clicks = { ... } end)
		Def(o, "Click", function(self, btn)
			if self.scripts.OnClick then self.scripts.OnClick(self, btn or "LeftButton", false) end
		end)
		Def(o, "IsProtected", function() return false end)
		Def(o, "IsMouseEnabled", function(self) return self.mouse == true end)
		Def(o, "SetEnabled", function(self, v) self.disabled = not v end)
		Def(o, "Enable", function(self) self.disabled = false end)
		Def(o, "Disable", function(self) self.disabled = true end)
		Def(o, "IsEnabled", function(self) return not self.disabled end)
		for _, k in ipairs({ "Normal", "Pushed", "Highlight", "Disabled" }) do
			Def(o, "Set" .. k .. "Texture", function(self, x) self["tex" .. k] = x end)
			Def(o, "Get" .. k .. "Texture", function(self) return self["tex" .. k] end)
		end
	end
	setmetatable(o, { __index = function(_, k)
		if type(k) == "string" and k:find("^%u") then SY.unknownM[otype .. ":" .. k] = true end
	end })
	return o
end
end

local function Mock()
	local f = { scripts = {}, events = {}, strings = {}, textures = {}, shown = true }
	function f:SetScript(n, fn) self.scripts[n] = fn end
	function f:SetSize(w, h) self.w, self.h = w, h end
	function f:SetFrameStrata(v) self.strata = v end
	function f:SetClampedToScreen(v) self.clamped = v end
	function f:SetBackdrop(v) self.backdrop = v end
	function f:ClearAllPoints() self.point = nil end
	function f:SetPoint(...) self.point = { ... } end
	function f:SetAlpha(a) self.alpha = a end
	function f:Show()
		local was = self.shown
		self.shown = true
		if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
	end
	function f:Hide()
		local was = self.shown
		self.shown = false
		if was and self.scripts.OnHide then self.scripts.OnHide(self) end
	end
	function f:SetMovable(v) self.movable = v end
	function f:RegisterForDrag(b) self.drag = b end
	function f:StartMoving() self.moving = true end
	function f:StopMovingOrSizing() self.moving = false end
	function f:GetLeft() return self.left end
	function f:GetBottom() return self.bottom end
	function f:GetTop() return self.top end
	function f:IsMouseOver() return self.over == true end
	function f:EnableKeyboard(v) self.kb = v end
	function f:SetPropagateKeyboardInput(v)
		-- InCombatLockdown, not the "combat" local: that local is made later in this file
		if InCombatLockdown and InCombatLockdown() then forbidden[#forbidden + 1] = "SetPropagateKeyboardInput in combat" end
		self.prop = v
	end
	function f:EnableGamePadButton() forbidden[#forbidden + 1] = "pad capture" end
	function f:EnableGamePadStick() forbidden[#forbidden + 1] = "pad capture" end
	function f:IsShown() return self.shown end
	function f:EnableMouse(v) self.mouse = v end
	function f:CreateTexture()
		local t = { desat = false, shown = true }
		function t:SetTexture(v) self.path = v return not TS.missing[v] end
		function t:SetTexCoord(...) self.coord = { ... } end
		function t:SetBlendMode(m) self.blend = m end
		function t:SetAlpha(a) self.alpha = a end
		function t:Show() self.shown = true end
		function t:Hide() self.shown = false end
		function t:IsShown() return self.shown end
		function t:SetAllPoints(f) self.all = f end
		function t:SetSize(w, h) self.w, self.h = w, h end
		function t:SetPoint(a, b, c, d, e)
			if type(b) == "number" then self.x, self.y = b, c else self.x, self.y = d, e end
		end
		function t:SetDesaturated(v) self.desat = v end
		function t:SetVertexColor(r, g, b) self.vc = { r, g, b } end
		function t:SetColorTexture(...) self.color = { ... } end
		function t:ClearAllPoints() self.x, self.y = nil, nil end
		self.textures[#self.textures + 1] = t
		return Rich(t, "Texture", self)
	end
	function f:GetHeight() return self.height or 0 end
	function f:GetWidth() return self.width or 0 end
	function f:IsVisible()   -- a test may set .visible; else shown + a visible parent (UIParent: visible)
		if self.visible ~= nil then return self.visible end
		if not self.shown then return false end
		local p = self.parent
		if type(p) == "table" and rawget(p, "isUIParent") then return true end
		return p ~= nil and p.IsVisible ~= nil and p:IsVisible() == true
	end
	function f:RegisterEvent(e) self.events[e] = true end
	function f:RegisterUnitEvent(e, u)
		self.events[e] = true
		self.units = self.units or {}
		self.units[e] = u
	end
	function f:UnregisterEvent(e) self.events[e] = nil end
	function f:CreateFontString(_, _, font)
		local fs = { font = font, shown = true }
		function fs:SetFontObject(o) self.font = o end
		function fs:SetFont(path, size, flags)   -- the game returns false when the file did not load
			self.fontPath, self.fontSize, self.fontFlags = path, size, flags
			return not (TS.fontBad and TS.fontBad[path])
		end
		function fs:Show() self.shown = true end
		function fs:Hide() self.shown = false end
		function fs:SetPoint(a, b, c, d, e)
			self.pt = { a, b, c, d, e }
			if type(b) == "number" then self.x, self.y = b, c else self.x, self.y = d, e end
		end
		function fs:SetText(t) self.text = t end
		function fs:ClearAllPoints() self.x, self.y = nil, nil end
		function fs:SetWidth(w) self.width = w end
		function fs:SetWordWrap(v) self.wrap = v end
		function fs:SetJustifyH(v) self.justify = v end
		-- a fake font: TS.fontW px a char, TS.fontH px a line, word wrap at the width; TS.fontH0 = no height
		function fs:GetStringHeight()
			local t = tostring(self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			if TS.fontH0 or t == "" then return 0 end
			local cw, lh = TS.fontW or 5.5, TS.fontH or 12
			if not (self.wrap and self.width) then return lh end
			local lines, used = 1, 0
			for w in t:gmatch("%S+") do
				local need = #w * cw + (used > 0 and cw or 0)
				if used > 0 and used + need > self.width then lines, used = lines + 1, #w * cw else used = used + need end
			end
			return lines * lh
		end
		if not TS.noCut then function fs:IsTruncated() return TS.fontCut == true end end
		self.strings[#self.strings + 1] = fs
		return Rich(fs, "FontString", self)
	end
	return f
end

-- The game's Settings API (this client has the vertical AND the canvas pages; 0.8.0 uses canvas pages only,
-- the old builds in tests/compat the vertical one).
-- mode: "vertical" (this client), "error" (the vertical API breaks), "suberr" (the Changelog sub-page breaks),
-- "nosub" (no sub-pages), "canvas" (no vertical API, no sub-pages), "old" (no Settings, InterfaceOptions only),
-- "none" (nothing).
-- reg.byVar.SpokenWind_<key> on 0.8.0: a stand-in setting (SetValue = clicks on the page, GetValue = the save).
local function MockSettings(mode)
	reg = { list = {}, controls = {}, buttons = {}, cats = {}, canvas = {}, subs = {} }
	reg.byVar = setmetatable({}, { __index = function(_, var)
		local key = type(var) == "string" and var:match("^SpokenWind_(%w+)$")
		if not key then return nil end
		return { key = key, SetValue = function(_, v) SY.PageSet(key, v) end, GetValue = function() return SpokenWindDB[key] end }
	end })
	MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
	CreateSettingsListSectionHeaderInitializer = function(text) return { header = text } end
	CreateSettingsButtonInitializer = function(name, text, fn, tip, tags)
		local b = { name = name, text = text, fn = fn, tip = tip, tags = tags }
		reg.buttons[#reg.buttons + 1] = b
		return b
	end
	InterfaceOptions_AddCategory = function(f) reg.canvas[#reg.canvas + 1] = f end
	if mode == "none" then Settings, InterfaceOptions_AddCategory = nil, nil return end
	if mode == "old" then Settings = nil return end
	Settings = {
		RegisterCanvasLayoutCategory = function(f, name)
			reg.canvas[#reg.canvas + 1] = f
			reg.cat = { frame = f, name = name, GetID = function() return 77 end }
			return reg.cat
		end,
		RegisterAddOnCategory = function(c) reg.cats[#reg.cats + 1] = c end,
	}
	if mode == "canvas" then return end
	if mode ~= "nosub" then
		Settings.RegisterCanvasLayoutSubcategory = function(parent, f, name)
			if mode == "suberr" and name == "Changelog" then error("sub broke") end
			local c = { parent = parent, frame = f, name = name, id = 80 + #reg.subs }
			c.GetID = function() return c.id end
			reg.subs[#reg.subs + 1] = c
			return c
		end
	end
	Settings.RegisterVerticalLayoutCategory = function(name)
		local layout = { inits = {} }
		function layout:AddInitializer(i) self.inits[#self.inits + 1] = i end
		reg.cat, reg.layout = { name = name, GetID = function() return 77 end }, layout
		return reg.cat, layout
	end
	Settings.OpenToCategory = function(id) reg.opened = id end
	Settings.RegisterAddOnSetting = function(cat, variable, key, tbl, vtype, name, default)
		if mode == "error" then error("vertical broke") end
		local s = { cat = cat, variable = variable, key = key, tbl = tbl, vtype = vtype, name = name, default = default }
		function s:GetValue() return self.tbl[self.key] end
		function s:SetValue(v)
			if self.tbl[self.key] == v then return end
			self.tbl[self.key] = v
			if self.cb then self.cb(self, v) end
		end
		function s:SetValueChangedCallback(cb) self.cb = cb end
		reg.list[#reg.list + 1] = s
		reg.byVar[variable] = s
		return s
	end
	Settings.CreateCheckbox = function(cat, s, tip) reg.controls[#reg.controls + 1] = { kind = "check", s = s, tip = tip } end
	Settings.CreateSliderOptions = function(a, b, step)
		local o = { min = a, max = b, step = step }
		function o:SetLabelFormatter(_, fn) self.fmt = fn end
		return o
	end
	Settings.CreateSlider = function(cat, s, o, tip)
		reg.controls[#reg.controls + 1] = { kind = "slider", s = s, o = o, tip = tip }
	end
	Settings.CreateControlTextContainer = function()
		local c = { d = {} }
		function c:Add(v, l) self.d[#self.d + 1] = { value = v, label = l } end
		function c:GetData() return self.d end
		return c
	end
	Settings.CreateDropdown = function(cat, s, opts, tip)
		reg.controls[#reg.controls + 1] = { kind = "list", s = s, opts = opts, tip = tip }
	end
end

local BASE = {}
for k in pairs(_G) do BASE[k] = true end

-- The game's friend toast: Spoken Wind may only READ its spot. Any other call
-- or any write = forbidden.
local combat, bnState = false, nil
local function BNMock()
	local st = { left = 30, bottom = 200, top = 260, shown = false, scale = 1, reads = 0 }
	local api = {
		GetLeft = function() st.reads = st.reads + 1 return st.left end,
		GetBottom = function() st.reads = st.reads + 1 return st.bottom end,
		GetTop = function() st.reads = st.reads + 1 return st.top end,
		IsShown = function() st.reads = st.reads + 1 return st.shown end,
		GetEffectiveScale = function() return st.scale end,
	}
	local bn = setmetatable({}, {
		__index = function(_, k)
			if api[k] then return api[k] end
			return function() forbidden[#forbidden + 1] = "BNToastFrame:" .. tostring(k) end
		end,
		__newindex = function(_, k) forbidden[#forbidden + 1] = "BNToastFrame." .. tostring(k) .. " written" end,
	})
	return bn, st
end

-- The dev folder is private (never in the public repo). Here: load its real file;
-- in a copy without it: set the same flag by hand.
local DEV_DIR = ROOT .. "/dev/Spoken_Wind_Dev"
do   -- a copy next to the addon wins (the mutant run copies both)
	local sib = io.open(ADDON_DIR .. "/../Spoken_Wind_Dev/Dev.lua", "rb")
	if sib then sib:close() DEV_DIR = ADDON_DIR .. "/../Spoken_Wind_Dev" end
end
local devLua = io.open(DEV_DIR .. "/Dev.lua", "rb")
local HAVE_DEV = devLua ~= nil
if devLua then devLua:close() end

-- dev: the dev addon loads after Spoken Wind's ADDON_LOADED (its toc lists
-- Spoken_Wind as a dependency), before PLAYER_LOGIN. Same order as the game.
-- the 5 approved Artifact lines (owner OK 2026-11-22): exact text, keyed by slot name
SY.ART_TEXT = {
	["freezes. That wasn't a fart. Their face turns bright red."] = "Never Trust It",
	["goes very still. That wasn't a fart. They waddle off, red in the face."] = "The Final Sputter",
	["goes pale. That wasn't a fart. They look around, deeply embarrassed."] = "Surprise Splat",
	["stops dead. That wasn't a fart. They wish the ground would swallow them whole."] = "Floodgate",
	["clenches. That wasn't a fart. They blush and pretend nothing happened."] = "The Stutter",
}
local devFiles
local function DevFiles()   -- the dev toc's files, in order
	if devFiles then return devFiles end
	devFiles = {}
	local dtoc = assert(io.open(DEV_DIR .. "/Spoken_Wind_Dev.toc", "rb")):read("*a")
	for line in dtoc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line:match("%S") then devFiles[#devFiles + 1] = line:match("^%s*(.-)%s*$") end
	end
	return devFiles
end
local function Load(db, mode, dev)
	now, plays, prints, frames = 1000, {}, {}, {}
	forbidden = forbidden or {}   -- kept over every load: checked once at the end
	clock = CLOCK0
	SPOKEN_WIND_DEV, SPOKEN_WIND_DEV_TOOLS = nil, nil
	SpokenWindDB = db
	SLASH_SPOKENWIND1, SLASH_SPOKENWIND2, SlashCmdList = nil, nil, {}
	CreateFrame = function(kind, name, parent, tmpl)
		-- names: only SpokenWind<Name> (the 0.8.0 windows; the game makes a named frame a global)
		if name ~= nil and not (type(name) == "string" and name:find("^SpokenWind%u%a*$")) then forbidden[#forbidden + 1] = "CreateFrame named" end
		local own = false   -- a child of one of our own frames is OK
		for _, x in ipairs(frames) do if x == parent then own = true end end
		if parent ~= nil and parent ~= UIParent and not own then forbidden[#forbidden + 1] = "CreateFrame parented" end
		if tmpl ~= nil and tmpl ~= "BackdropTemplate" then forbidden[#forbidden + 1] = "CreateFrame " .. tostring(tmpl) end
		if kind ~= "Frame" and kind ~= "Button" then forbidden[#forbidden + 1] = "CreateFrame " .. tostring(kind) end   -- no ScrollFrame
		local f = Mock() f.parent, f.tmpl, f.kind, f.name = parent, tmpl, kind, name frames[#frames + 1] = f
		Rich(f, kind == "Button" and "Button" or "Frame", parent)
		if own then parent.kids = parent.kids or {} parent.kids[#parent.kids + 1] = f end
		if name then _G[name] = f end
		return f
	end
	UIParent = setmetatable({ isUIParent = true, GetEffectiveScale = function() return 1 end, GetWidth = function() return 1365 end,
		GetHeight = function() return 768 end, GetScale = function() return 1 end, GetSize = function() return 1365, 768 end,
		GetLeft = function() return 0 end, GetRight = function() return 1365 end, GetTop = function() return 768 end,
		GetBottom = function() return 0 end, GetCenter = function() return 682.5, 384 end, GetFrameLevel = function() return 0 end,
		GetFrameStrata = function() return "MEDIUM" end, IsShown = function() return true end, IsVisible = function() return true end,
		GetName = function() return "UIParent" end, GetObjectType = function() return "Frame" end,
		IsObjectType = function(_, ty) return ty == "Frame" end, IsForbidden = function() return false end },
		-- a field read (Look reads parent._lookFrames) is nil, as in the game; a method the fake has not got = forbidden
		{ __index = function(_, k) if type(k) == "string" and k:find("^%u") then forbidden[#forbidden + 1] = "UIParent:" .. k end end,
		  __newindex = function(_, k) forbidden[#forbidden + 1] = "UIParent write " .. tostring(k) end })
	BackdropTemplateMixin = {}
	BNToastFrame, bnState = BNMock()
	ChatFrame1 = { GetLeft = function() return 32 end, GetTop = function() return 300 end,
		GetEffectiveScale = function() return 1 end }
	combat = false
	InCombatLockdown = function() return combat end
	SY.loggedIn = false
	IsLoggedIn = function() return SY.loggedIn end
	ITEM_QUALITY_COLORS, BACKDROP_TOAST_12_12 = nil, nil
	GetTime = function() return now end
	time = function() return clock end
	date = function(fmt, t) return os.date(fmt or "%c", t or clock) end
	print = function(...) prints[#prints + 1] = table.concat({ ... }, " ") end
	PlaySoundFile = function(path, ch) plays[#plays + 1] = { path = path, ch = ch } return willPlay, 77 end
	TS.snd, SOUNDKIT = {}, nil
	PlaySound = function(kit, ch)
		TS.snd[#TS.snd + 1] = { kit = kit, ch = ch }
		if TS.sndErr then error("snd boom") end
		return true
	end
	UnitGUID = function(u) return u == "player" and ME_GUID or nil end
	UnitName = function(u) return u == "player" and ME or nil end
	GetLocale = function() return "enUS" end
	issecretvalue = nil
	EMOTE41_TOKEN, EMOTE41_CMD1 = "FART", "/fart"
	sent, hw = {}, false
	SY.artSent = {}
	hash_SlashCmdList, SecureCmdList, ChatTypeInfo, C_ChatInfo = nil, nil, nil, nil
	SendChatMessage = function(text, chan, lang, tgt)   -- only inside a typed slash or a click
		sent[#sent + 1] = { text = text, chan = chan, lang = lang, tgt = tgt, tick = SY.inTick }
		-- + 0.6.6 fart attack: its rumble line from a timer (SY.inTick), EMOTE, one of the fixed texts only
		local rumble = not hw and SY.inTick and chan == "EMOTE" and tostring(text):find("^feels a sudden rumble in ") ~= nil
		-- + 0.7.0 Artifact shart: its line from a timer, EMOTE, one of the 5 approved texts only, no language, no target
		local art = not hw and chan == "EMOTE" and SY.ART_TEXT[text] ~= nil and lang == nil and tgt == nil
		if art then SY.artSent[#SY.artSent + 1] = { text = text, at = now } end
		if not hw and not rumble and not art then forbidden[#forbidden + 1] = "SendChatMessage outside a click or slash" end
		if SY.chatErr then error("chat boom") end
		if SY.chatHook then SY.chatHook(text, chan) end
		if #tostring(text) > 255 then forbidden[#forbidden + 1] = "chat line over 255" end
		if chan == "WHISPER" and (type(tgt) ~= "string" or tgt == "") then forbidden[#forbidden + 1] = "whisper without a name" end
	end
	for _, bad in ipairs({ "SetCVar", "RunMacroText",
		"CastSpellByName", "UseAction", "SetBinding", "SetBindingClick", "SetOverrideBinding", "SetOverrideBindingClick" }) do
		_G[bad] = function() forbidden[#forbidden + 1] = bad end
	end
	-- same-fart sync (0.6.0): addon messages + the 2 emote-call hooks; anything else is forbidden
	SY.timers, SY.hooks, SY.asent, SY.sendRes = {}, {}, {}, nil
	-- DoEmote (the Fart button, 0.6.5): only inside a click, max ONE per click (SY.clickN = the test click
	-- helper's count); the game then runs the hooks (Sync's DoEmote hook)
	SY.emotes, SY.clickN, SY.emoteErr = {}, nil, nil
	SY.chatErr, SY.chatHook = nil, nil
	-- 0.6.6 random fart: the one exception, from a ticker tick or a timer (SY.inTick): FART at "none" (no
	-- target) only; + the fart attack's SIGH at "none"
	SY.randEmote = false
	DoEmote = function(token, unit)
		SY.emotes[#SY.emotes + 1] = { token = token, unit = unit, hw = hw, tick = SY.inTick }
		local rnd = not hw and SY.inTick and (token == "FART" or token == "SIGH") and unit == "none"
		if not hw and not rnd then forbidden[#forbidden + 1] = "DoEmote outside a click" end
		if SY.clickN then
			SY.clickN = SY.clickN + 1
			if SY.clickN > 1 then forbidden[#forbidden + 1] = "two emotes in one click" end
		end
		if SY.emoteErr then error("emote boom") end
		if SY.emoteHook then SY.emoteHook(token, unit) end   -- a test's own client reaction (a block event)
		SY.randEmote = rnd and true or false
		if SY.hooks.DoEmote then SY.hooks.DoEmote(token, unit) end
		SY.randEmote = false
	end
	GetServerTime = function() return clock end
	SY.tickers = {}
	C_Timer = { After = function(s, fn) SY.timers[#SY.timers + 1] = { at = now + s, s = s, fn = fn } end }
	if not SY.noTicker then   -- the board timer S (0.6.4): tests run the ticks by hand (SY.inTick)
		C_Timer.NewTicker = function(s, fn)
			local tk = { s = s, fn = fn }
			function tk.Cancel() tk.dead = true end
			SY.tickers[#SY.tickers + 1] = tk
			return tk
		end
	end
	IsInGroup, IsInRaid, IsInGuild, IsInInstance = nil, nil, nil, nil
	GetPlayerInfoByGUID, UnitFactionGroup, C_CreatureInfo = nil, nil, nil
	RegisterAddonMessagePrefix, SendAddonMessage = nil, nil
	C_ChatInfo = {
		RegisterAddonMessagePrefix = function(p)
			SY.prefix = p
			if SY.prefixRes == nil then return true end
			return SY.prefixRes
		end,
		SendAddonMessage = function(p, m, ch, tgt)
			SY.asent[#SY.asent + 1] = { p = p, m = m, ch = ch, tgt = tgt, hw = hw, tick = SY.inTick }
			-- the exceptions: a Heard reply (0.6.2), the board timer S, only from a ticker tick (0.6.4), and the
			-- Fart button answer Q:1 by WHISPER (0.6.5)
			local kind = tostring(m):sub(1, 4)
			-- + the random fart's own F and S (0.6.6), only inside its DoEmote call
			if not hw and kind ~= "H:1:" and not (SY.inTick and kind == "S:1:") and not (m == "Q:1" and ch == "WHISPER")
				and not (SY.randEmote and (kind == "F:1:" or kind == "S:1:")) then
				forbidden[#forbidden + 1] = "SendAddonMessage outside a key press"
			end
			if (m == "P:1" or m == "Q:1") and (ch ~= "WHISPER" or type(tgt) ~= "string" or tgt == "") then
				forbidden[#forbidden + 1] = "button check not a whisper " .. tostring(ch)
			end
			if ch == "WHISPER" and m ~= "P:1" and m ~= "Q:1" and kind ~= "T:1:" then
				forbidden[#forbidden + 1] = "addon whisper not a button check " .. tostring(m)
			end
			if SY.inTick and not SY.randEmote and kind == "S:1:" and (ch == "WHISPER" or ch == "SAY" or ch == "YELL" or ch == "CHANNEL" or tgt ~= nil) then
				forbidden[#forbidden + 1] = "timer S on " .. tostring(ch)
			end
			if #tostring(p) + #tostring(m) > 254 then forbidden[#forbidden + 1] = "addon message too long" end
			return SY.sendRes
		end,
		PerformEmote = function() forbidden[#forbidden + 1] = "PerformEmote" end,
	}
	local function FromDev()   -- the caller is the dev addon (Dev.lua), never Spoken Wind
		for lv = 2, 8 do
			local i = debug.getinfo(lv, "S")
			if not i then return false end
			if tostring(i.source):find("Spoken_Wind_Dev[\\/]Dev%.lua$") then return true end
		end
		return false
	end
	hooksecurefunc = function(a, b, c)   -- only the game's 2 emote calls: never a frame, never anything else
		if a == "DoEmote" and type(b) == "function" and c == nil and not SY.hooks.DoEmote then SY.hooks.DoEmote = b
		elseif a ~= nil and a == C_ChatInfo and b == "PerformEmote" and type(c) == "function" and not SY.hooks.PerformEmote then
			SY.hooks.PerformEmote = c
		elseif a ~= nil and a == C_ChatInfo and b == "SendAddonMessage" and type(c) == "function" and type(a[b]) == "function"
			and not SY.hooks.SendAddonMessage and FromDev() then
			-- dev 1.4.0 only (the Msgs view): a post-hook like the game's: the send first, then the hook, the send's result back
			SY.hooks.SendAddonMessage = c
			local send = a[b]
			a[b] = function(...)
				local r = send(...)
				c(...)
				return r
			end
		elseif type(a) == "table" and SY.own[a] and type(b) == "string" and type(c) == "function" then
			local fn = a[b]
			if type(fn) ~= "function" then error("hooksecurefunc: no method " .. b) end
			SY.ownHooks = (SY.ownHooks or 0) + 1
			a[b] = function(...)
				local r = { fn(...) }
				c(...)
				return unpack(r)
			end
		else forbidden[#forbidden + 1] = "hooksecurefunc " .. tostring(a) .. " " .. tostring(b) end
	end
	if SY.noApi then C_ChatInfo, hooksecurefunc = nil, nil end
	MockSettings(mode or "vertical")
	local ns = {}
	reg.ns = ns
	local toc = assert(io.open(ADDON_DIR .. "/Spoken_Wind.toc", "rb")):read("*a")
	local files = {}
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line:match("%S") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
	end
	for _, file in ipairs(files) do   -- SY.noPacks: the race packs do not load (= the old 14 only)
		if not (SY.noPacks and file:find("^Packs[\\/]")) and not (SY.noUI and file:find("^UI[\\/]")) then assert(loadfile(ADDON_DIR .. "/" .. (file:gsub("\\", "/"))))("Spoken_Wind", ns) end
	end
	local ev = frames[1]
	ev.scripts.OnEvent(ev, "ADDON_LOADED", "SomethingElse")
	ev.scripts.OnEvent(ev, "ADDON_LOADED", "Spoken_Wind")
	if dev then
		if HAVE_DEV then
			local dns = {}
			SY.dns = dns
			for _, file in ipairs(DevFiles()) do assert(loadfile(DEV_DIR .. "/" .. (file:gsub("\\", "/"))))("Spoken_Wind_Dev", dns) end
		else SPOKEN_WIND_DEV = true end
	end
	if preLogin then preLogin(ns) end   -- other addons (loaded before login)
	SY.loggedIn = true
	ev.scripts.OnEvent(ev, "PLAYER_LOGIN")
	return ev, ns, files, toc
end

local ev, ns, files, toc
local function Emote(text, sender, guid)
	ev.scripts.OnEvent(ev, "CHAT_MSG_TEXT_EMOTE", text, sender, "", "", "", "", 0, 0, "", 0, 123, guid)
end
local function Slash(s) SlashCmdList.SPOKENWIND(s) end
local function LogHas(s)
	for _, l in ipairs(SpokenWindDB.log) do if l:find(s, 1, true) then return true end end
	return false
end
local function LastLog() return SpokenWindDB.log[#SpokenWindDB.log] or "" end
local function LastPlay()   -- achievements log after PLAY: the newest PLAY line
	for n = #SpokenWindDB.log, 1, -1 do
		if SpokenWindDB.log[n]:find(" PLAY ", 1, true) then return SpokenWindDB.log[n] end
	end
	return ""
end
local function SumKeys()
	ev.scripts.OnEvent(ev, "PLAYER_LOGOUT")
	return tonumber(LastLog():match("keys=(%d+)"))
end
-- Tests only: every sound length = ms (false = no lengths at all) until SY.ShortLen() puts the real ones back.
SY.ShortLen = function(ms)
	if not SY.lenReal then SY.lenReal = {} for k, v in pairs(ns.LEN) do SY.lenReal[k] = v end end
	for k, v in pairs(SY.lenReal) do
		if ms == nil then ns.LEN[k] = v elseif ms == false then ns.LEN[k] = nil else ns.LEN[k] = ms end
	end
	if ms == nil then SY.lenReal = nil end
end
-- Sync tests: one person farts fast there (cd 0); 0.1 ms sounds keep the length gate out of their way.
SY.Tiny = function(n) for k in pairs(n.LEN) do n.LEN[k] = 0.1 end end
local OTHER_FART = "Bob brushes up against you and farts loudly."
local function FartBy(name) return (name:match("^[^%-]+")) .. " farts loudly." end
local ANN_FART = FartBy("Ann")
local BOB, ANN = "Player-1-0000BBBB", "Player-1-0000CCCC"

-- BOOT len=: a sound with no length is not counted
preLogin = function(n) n.LEN["01_squeak"] = nil end
Load(nil)
preLogin = nil
ok("BOOT len: a sound with no length is not counted", LogHas(" n=1351 len=1350/1351 dex="))
-- ---------------------------------------------------------------- load + toc
ev, ns, files, toc = Load(nil)
ok("toc order", table.concat(files, ",") ==
	"UI\\Look.lua,UI\\Parts.lua,UI\\sw-ach.lua,UI\\sw-ach-social.lua,UI\\sw-ach-classic.lua,UI\\sw-ach-collection.lua,"
		.. "UI\\sw-ach-board.lua,UI\\sw-btns.lua,UI\\sw-hello.lua,UI\\sw-tip.lua,UI\\sw-tip-btn.lua,UI\\sw-toast.lua,"
		.. "UI\\sw-rewards.lua,UI\\sw-options.lua,UI\\sw-fartlog.lua,UI\\sw-changelog.lua,UI\\sw-credits.lua,"
		.. "Emotes.lua,Lengths.lua,Packs\\human.lua,Packs\\dwarf.lua,Packs\\nightelf.lua,Packs\\gnome.lua,Packs\\orc.lua,"
		.. "Packs\\scourge.lua,Packs\\tauren.lua,Packs\\troll.lua,Packs\\skyborne.lua,Packs\\artifact.lua,Voices.lua,"
		.. "Match.lua,Pick.lua,Changelog.lua,FartLog.lua,Achievements.lua,AchWin.lua,Toast.lua,Rewards.lua,Button.lua,Random.lua,Shart.lua,Sync.lua,Heard.lua,Board.lua,Collection.lua,TestMode.lua,Screens.lua,Bar.lua,Core.lua,Options.lua",
	table.concat(files, ","))
ok("toc title", toc:find("## Title: Spoken Wind\r?\n") ~= nil)
ok("toc version 0.8.4", toc:find("## Version: 0.8.4\r?\n") ~= nil)
ok("toc no X- keys", not toc:find("##%s*[Xx]%-"))
local ALLOWED = { Interface = 1, Title = 1, Notes = 1, Author = 1, Version = 1, SavedVariables = 1 }
local keys = 0
for line in toc:gmatch("[^\r\n]+") do
	if line:match("^##") then
		keys = keys + 1
		local key = line:match("^##%s*([^:]+):")
		ok("toc key allowed: " .. tostring(key), key and ALLOWED[key], line)
	end
end
ok("toc 6 keys", keys == 6, keys)
ok("toc no deps", not toc:find("Dep") and not toc:find("Spoken_%u") and not toc:find("Spoken%u%l+Audio"))

-- ---------------------------------------------------------------- UI fonts (0.8.0): the 3 shipped files, tested once at login
do
	local FD = "Interface\\AddOns\\Spoken_Wind\\Media\\Fonts\\"
	local function BootLine()
		for i = #SpokenWindDB.log, 1, -1 do if SpokenWindDB.log[i]:find(" BOOT v=", 1, true) then return SpokenWindDB.log[i] end end
		return ""
	end
	local function Lines(pre)
		local r = {}
		for _, l in ipairs(SpokenWindDB.log) do
			local s = l:match(" (UI font .*)$")
			if s and s:find(pre, 1, true) == 1 then r[#r + 1] = s end
		end
		return r
	end
	local function Step(s)   -- the clock on by s; due timers run in order
		local stop = now + s
		while true do
			local nx
			for _, x in ipairs(SY.timers) do if x.at <= stop and (not nx or x.at < nx.at) then nx = x end end
			if not nx then break end
			for i, x in ipairs(SY.timers) do if x == nx then table.remove(SY.timers, i) break end end
			now = math.max(now, nx.at)
			nx.fn()
		end
		now = stop
	end
	local _, fns = Load(nil)
	local LK = fns.Look
	ok("font: BOOT font=ok (all 3 loaded at the first test)", BootLine():find(" cred=page font=ok$") ~= nil, BootLine())
	local fl = Lines("UI font file=")
	table.sort(fl)
	ok("font: one log line per file, ok=Spoken_Wind", table.concat(fl, "|") == "UI font file=Barlow-Bold.ttf ok=Spoken_Wind tried=Spoken_Wind"
		.. "|UI font file=DejaVuSans.ttf ok=Spoken_Wind tried=Spoken_Wind|UI font file=Lato.ttf ok=Spoken_Wind tried=Spoken_Wind",
		table.concat(fl, "|"))
	ok("font: the 3 shipped paths", LK.fonts.Lato == FD .. "Lato.ttf" and LK.fonts.Barlow == FD .. "Barlow-Bold.ttf"
		and LK.fonts.DejaVu == FD .. "DejaVuSans.ttf" and LK.Font("Barlow") == FD .. "Barlow-Bold.ttf")
	ok("font: no retry (state idle, no retry line)", LK.fontRetry.state == "idle" and #Lines("UI font retry") == 0, LK.fontRetry.state)
	ok("font: a second call tests nothing again", fns.UIFonts() == "ok" and #Lines("UI font file=") == 3)
	Step(120)
	ok("font: no late lines", #Lines("UI font") == 3)
	-- a file that does not load: BOOT font=wait, Look retries (0.2 ... 40 s), then a late try every 60 s
	TS.fontBad = { [FD .. "Barlow-Bold.ttf"] = true }
	_, fns = Load(nil)
	LK = fns.Look
	ok("font miss: BOOT font=wait", BootLine():find(" font=wait$") ~= nil, BootLine())
	ok("font miss: the 2 others logged at once, no Barlow line yet", #Lines("UI font file=") == 2
		and #Lines("UI font file=Barlow") == 0 and LK.fontRetry.state == "wait", LK.fontRetry.state)
	Step(41)
	ok("font miss: after the last try = ok=none + one fail line", table.concat(Lines("UI font file=Barlow"), "|")
		== "UI font file=Barlow-Bold.ttf ok=none tried=Spoken_Wind" and table.concat(Lines("UI font retry"), "|")
		== "UI font retry fail tries=7 fixed=0 out=Barlow-Bold.ttf via=- wait=11" and LK.fontRetry.state == "fail",   -- wait=11: the Barlow texts made at login (bar + option pages)
		table.concat(Lines("UI font"), "|"))
	ok("font miss: the BOOT value is kept (one test per session)", fns.UIFonts() == "wait")
	ok("font miss: no addon list = no scan (scan=0)", LK.fontRetry.scan == 0, LK.fontRetry.scan)
	TS.fontBad = nil
	Step(60)
	ok("font miss: a late try finds it = late ok + the file line again", table.concat(Lines("UI font file=Barlow"), "|")
		== "UI font file=Barlow-Bold.ttf ok=none tried=Spoken_Wind|UI font file=Barlow-Bold.ttf ok=Spoken_Wind tried=Spoken_Wind"
		and Lines("UI font retry")[2] == "UI font retry late ok tries=8 fixed=11 via=fresh wait=0" and LK.fontRetry.state == "ok",   -- fixed=11: those texts
		table.concat(Lines("UI font"), "|"))
	-- v4 (0.8.3): every SW copy refused; from try 3 (2 s) ONE scan of the other loaded addons' Media\Fonts folders (names from the
	-- client, "fresh" route only, max 20 tests a frame). Fakes here only: C_AddOns (list + loaded), CreateFont (a counter),
	-- C_Timer.After wrapped to record Look.fontRetry.scan at each After(0) (= each scan step)
	do
		local LATO = FD .. "Lato.ttf"
		local function Other(n) return "Interface\\AddOns\\" .. n .. "\\Media\\Fonts\\Lato.ttf" end
		local list, loaded, nCF = {}, {}, 0
		local function V4(names, isLoaded, bad)
			list, loaded = names, isLoaded
			TS.fontBad = { [LATO] = true }
			for _, n in ipairs(bad) do TS.fontBad[Other(n)] = true end
			C_AddOns = { GetNumAddOns = function() return #list end, GetAddOnInfo = function(i) return list[i] end,
				IsAddOnLoaded = function(n) return loaded[n] or false end }
			nCF = 0
			CreateFont = function()
				nCF = nCF + 1
				return { SetFont = function(_, p) return not (TS.fontBad and TS.fontBad[p]) end }
			end
			local _, f = Load(nil)
			SY.a0 = {}
			local A = C_Timer.After
			C_Timer.After = function(s, fn)
				if s == 0 then SY.a0[#SY.a0 + 1] = f.Look.fontRetry.scan end
				return A(s, fn)
			end
			return f.Look
		end
		local L4 = V4({ "Alpha", "Spoken_Wind", "Zed", "Beta", "Gamma" }, { Alpha = true, Beta = true, Gamma = true }, { "Alpha" })
		ok("font v4: BOOT font=wait, no scan at load", BootLine():find(" font=wait$") ~= nil and L4.fontRetry.scan == 0, BootLine())
		Step(1.5)
		ok("font v4: tries 1-2 = no scan yet (it starts at try 3)", L4.fontRetry.scan == 0 and #SY.a0 == 0, L4.fontRetry.scan)
		Step(1)
		ok("font v4: try 3 scans: Alpha misses, Beta loads (own folder + not-loaded Zed skipped, Gamma never): 2 tests, 1 step",
			L4.fontRetry.scan == 2 and table.concat(SY.a0, ",") == "0" and L4.fontRetry.out == "" and L4.fontRetry.via == "fresh",
			L4.fontRetry.scan .. " " .. table.concat(SY.a0, ",") .. " out=" .. L4.fontRetry.out .. " via=" .. L4.fontRetry.via)
		local o = CreateFrame("Frame"):CreateFontString()
		ok("font v4: real texts take Beta's copy", L4.FontSet(o, LATO, 12) == true and o.fontPath == Other("Beta"), tostring(o.fontPath))
		Step(40)
		local rl = Lines("UI font retry")
		ok("font v4: last try = Lato 'ok=Beta tried=Spoken_Wind,+2' + ONE 'font retry ok tries=7 fixed=N via=fresh wait=0'",
			table.concat(Lines("UI font file=Lato"), "|") == "UI font file=Lato.ttf ok=Beta tried=Spoken_Wind,+2"
			and #rl == 1 and rl[1]:match("^UI font retry ok tries=7 fixed=%d+ via=fresh wait=0$") ~= nil and L4.fontRetry.state == "ok"
			and L4.fontRetry.scan == 2, table.concat(Lines("UI font"), "|"))
		local names, ld = {}, {}
		for i = 1, 30 do names[i] = ("A%02d"):format(i); ld[names[i]] = true end
		local L5 = V4(names, ld, names)
		local cf0 = nCF
		Step(41)
		rl = Lines("UI font retry")
		ok("font v4: 30 loaded addons, none has it: 30 tests, at most 20 a frame (scan at each step: 0, 20)",
			L5.fontRetry.scan == 30 and table.concat(SY.a0, ",") == "0,20", L5.fontRetry.scan .. " " .. table.concat(SY.a0, ","))
		ok("font v4: the scan makes no Font object (only the regular tries do: " .. (nCF - cf0) .. " < 30)", nCF - cf0 < 30, nCF - cf0)
		ok("font v4: none found = Lato 'ok=none tried=Spoken_Wind,+30' + ONE 'font retry fail tries=7 fixed=0 out=Lato.ttf'",
			table.concat(Lines("UI font file=Lato"), "|") == "UI font file=Lato.ttf ok=none tried=Spoken_Wind,+30"
			and #rl == 1 and rl[1]:match("^UI font retry fail tries=7 fixed=0 out=Lato%.ttf via=%- wait=%d+$") ~= nil,
			table.concat(Lines("UI font"), "|"))
		Step(130)
		ok("font v4: late tries do not scan again", L5.fontRetry.scan == 30, L5.fontRetry.scan)
		TS.fontBad, C_AddOns, CreateFont, SY.a0 = nil, nil, nil, nil
	end
	-- no UI files (no Look): BOOT font=-1, the rest still boots
	SY.noUI = true
	local _, nsU = Load(nil)
	SY.noUI = nil
	ok("font: no Look = font=-1, the old text pages", BootLine():find(" panel=canvas log=text flog=none ", 1, true)
		and BootLine():find(" cred=text font=%-1$") ~= nil, BootLine())
	ok("no Look: no bar, no hello note, no ERR", nsU.BarRefs() == nil and select(5, nsU.BarRefs()) == nil and not LogHas("ERR"),
		table.concat(Lines("ERR"), "|"))
	ok("no Look: a toast = false (the chat line), no frame", nsU.Toast(nsU.ACH[1]) == false and nsU.ToastFrame() == nil
		and nsU.ToastRefs() == nil)
	-- the font test breaks: BOOT font=-1 + one ERR line
	preLogin = function(n) n.UIFonts = function() error("font boom") end end
	Load(nil)
	preLogin = nil
	ok("font: an error = font=-1 + ERR font", BootLine():find(" font=%-1$") ~= nil and LogHas("ERR font ") and LogHas("font boom"), BootLine())
end
ev, ns, files, toc = Load(nil)   -- the state the next tests start from

-- UI files (0.8.0): own frames only; never the fake sample text; never a keyboard close
do
	local srcs = {}
	for _, file in ipairs(files) do
		if not file:find("^Packs[\\/]") then
			srcs[file] = assert(io.open(ADDON_DIR .. "/" .. (file:gsub("\\", "/")), "rb")):read("*a")
		end
	end
	local nUI = 0
	-- other addon names: the word list is private (dev/banned-words.txt, never in the public repo). No list = no check.
	local banned = {}
	local bf = io.open(ROOT .. "/dev/banned-words.txt", "rb")
	if bf then
		for line in bf:read("*a"):gmatch("[^\r\n]+") do
			if not line:find("^#") then banned[#banned + 1] = line:lower() end
		end
		bf:close()
		ok("ui src: the private word list (5 words)", #banned == 5, #banned)
	end
	for file, s in pairs(srcs) do
		local ui = file:find("^UI[\\/]") ~= nil
		if ui then nUI = nUI + 1 end
		local low = s:lower()
		local hit
		for _, w in ipairs(banned) do if low:find(w, 1, true) then hit = w end end
		ok("ui src: no other addon names: " .. file, hit == nil, hit)
		ok("ui src: no keyboard close: " .. file, not s:find("UISpecialFrames", 1, true) and not s:find("hooks.esc", 1, true)
			and (file == "Rewards.lua" or not s:find("SetPropagateKeyboardInput", 1, true))
			and (file == "Rewards.lua" or not s:find("EnableKeyboard", 1, true))
			and (file == "Rewards.lua" or not s:find("OnKeyDown", 1, true)))
		if not ui then ok("ui src: never L.sample: " .. file, not s:find("%.sample%s*%(")) end
		if ui then
			local fonts = {}
			for p in s:gmatch("Interface\\\\AddOns\\\\([^\\]+)\\\\") do fonts[p] = true end
			local other
			for p in pairs(fonts) do if p ~= "Spoken_Wind" and p ~= "X" then other = p end end   -- X: a doc example in Look.lua
			ok("ui src: font paths only in Spoken_Wind: " .. file, other == nil, other)
		end
	end
	ok("ui src: 17 UI files in the toc", nUI == 17, nUI)
	local lk = srcs["UI\\Look.lua"] or ""
	ok("ui src: Look.lua MIT head", lk:find("^%-%- Spoken Wind UI runtime %(Look%.lua%)%. MIT License, see LICENSE in the repo root%.\r?\n"
		.. "%-%- Copyright %(c%) 2026 Spoken Wind authors\r?\n") ~= nil)
	ok("ui src: Look.lua reads no other addon's globals", not lk:find("rawget%(_G, \"%u%l+UI") and lk:find("local FALLBACK = {}", 1, true) ~= nil)
end

-- UI screens (0.8.0): every generated screen builds + opens with the fake client.
-- No error, nothing forbidden, own frames only (names SpokenWind<Name>), no keyboard, no method the fake does not know.
do
	local forb0 = #forbidden
	SY.unknownM = {}
	local hooks0 = SY.ownHooks or 0
	local _, sns = Load(nil, "vertical", true)
	local Look, Looks = sns.Look, sns.Looks
	local nScreens = 0
	for _ in pairs(Looks) do nScreens = nScreens + 1 end
	ok("ui build: 15 public screens + Look + Parts", nScreens == 15 and type(Look) == "table" and type(Look.Shell) == "function", nScreens)
	local store = {}
	Look.SetStore(store)
	local built, errs = {}, {}
	local function Build(L, id, parent, owner, canvas)
		local okB, refs = pcall(function()
			local r = L.build(parent, Look.D(L.tokens))
			if not canvas and L.open then L.open(r, owner) end
			return r
		end)
		if not okB then errs[#errs + 1] = id .. ": " .. tostring(refs) return nil end
		built[id] = refs
		return refs
	end
	local btns = Build(Looks["sw-btns"], "sw-btns", UIParent)
	local ach = Build(Looks["sw-ach"], "sw-ach", UIParent)
	local tabs
	if ach then
		local okT, t = pcall(Look.Tabs, ach, Looks["sw-ach"], {})
		if okT then tabs = t else errs[#errs + 1] = "tabs: " .. tostring(t) end
	end
	local owner = btns and btns.root
	for _, id in ipairs({ "sw-rewards", "sw-hello", "sw-toast" }) do Build(Looks[id], id, UIParent, owner) end
	for _, id in ipairs({ "sw-tip", "sw-tip-btn" }) do Build(Looks[id], id, UIParent, nil, true) end
	-- Settings pages: a plain frame + L.build, no L.open (no drag, no strata, no store)
	for _, id in ipairs({ "sw-options", "sw-fartlog", "sw-changelog", "sw-credits" }) do
		local host = CreateFrame("Frame")
		Build(Looks[id], id, host, nil, true)
	end
	ok("ui build: no error in any build / open", #errs == 0, table.concat(errs, " | "))
	ok("ui build: 4 tab bodies", tabs ~= nil and tabs.bodies ~= nil and tabs.bodies["sw-ach-social"] ~= nil and tabs.bodies["sw-ach-classic"] ~= nil
		and tabs.bodies["sw-ach-collection"] ~= nil and tabs.bodies["sw-ach-board"] ~= nil)
	local names = {}
	for k, v in pairs(_G) do if type(k) == "string" and k:find("^SpokenWind%u%a*$") and SY.own[v] then names[#names + 1] = k end end
	table.sort(names)
	ok("ui build: the 11 named windows, own frames", table.concat(names, ",") == "SpokenWindAch,SpokenWindBtnTip,SpokenWindButtons,"
		.. "SpokenWindChangelog,SpokenWindCredits,SpokenWindFartLog,SpokenWindHello,SpokenWindOptions,SpokenWindRewards,SpokenWindTip,SpokenWindToast",
		table.concat(names, ","))
	ok("ui build: each root is its named frame", btns and _G.SpokenWindButtons == btns.root and ach and _G.SpokenWindAch == ach.root)
	-- the fake places frames from their points, as the game does: the rewards popup sits 4 px above the bar
	local rw = built["sw-rewards"]
	btns.root:ClearAllPoints()
	btns.root:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 100, 200)   -- a window with no stored place has no point (the glue gives one)
	local bl, bt, rl, rb = btns.root:GetLeft(), btns.root:GetTop(), rw and rw.root:GetLeft(), rw and rw.root:GetBottom()
	ok("ui build: positions (rewards popup BOTTOMLEFT = bar TOPLEFT + 4)", bl ~= nil and bt ~= nil and bl == 100 and rl == bl and rb == bt + 4,
		tostring(bl) .. "," .. tostring(bt) .. " / " .. tostring(rl) .. "," .. tostring(rb))
	ok("ui build: sizes from the design (bar and window not 0)", btns.root:GetWidth() > 0 and btns.root:GetHeight() > 0
		and ach.root:GetWidth() > 0 and ach.root:GetHeight() > 0, btns.root:GetWidth() .. "x" .. btns.root:GetHeight())
	local kb = {}
	for _, f in ipairs(frames) do
		if f.kb ~= nil or f.prop ~= nil or f.scripts.OnKeyDown or f.scripts.OnKeyUp or f.scripts.OnMouseWheel then kb[#kb + 1] = tostring(f.name or f._lookId) end
	end
	ok("ui build: no keyboard, no wheel on any frame", #kb == 0, table.concat(kb, ","))
	ok("ui build: nothing forbidden", #forbidden == forb0, forbidden[forb0 + 1])
	ok("ui build: row layouts hook own objects only (and do hook)", (SY.ownHooks or 0) > hooks0)
	-- probes: Look asks a region for GetChildren (in a pcall) to tell regions from frames; the game has none either
	local PROBE = { ["Texture:GetChildren"] = true, ["FontString:GetChildren"] = true }
	local function Unknown()
		local r = {}
		for k in pairs(SY.unknownM) do if not PROBE[k] then r[#r + 1] = k end end
		table.sort(r)
		return r
	end
	local unk = Unknown()
	ok("ui build: no method the fake client does not know", #unk == 0, table.concat(unk, ","))
	SY.uiBuilt = built
	-- the dev addon: its own Look copy + 2 screens (window + panel under it)
	if HAVE_DEV then
		local dLook, dLooks = SY.dns.Look, SY.dns.Looks
		local nD = 0
		for _ in pairs(dLooks or {}) do nD = nD + 1 end
		ok("ui build dev: own Look copy (not SW's) + 2 screens", type(dLook) == "table" and dLook ~= Look and nD == 2, nD)
		dLook.SetStore({})
		local derr
		local okD, e = pcall(function()
			local dv = dLooks["sw-dev"].build(UIParent, dLook.D(dLooks["sw-dev"].tokens))
			dLooks["sw-dev"].open(dv)
			local mg = dLooks["sw-dev-msgs"].build(UIParent, dLook.D(dLooks["sw-dev-msgs"].tokens))
			dLooks["sw-dev-msgs"].open(mg, dv.root)
			return dv
		end)
		if not okD then derr = e end
		ok("ui build dev: builds + opens, named SpokenWindDev / SpokenWindDevMsgs", okD and SY.own[_G.SpokenWindDev] and SY.own[_G.SpokenWindDevMsgs], derr)
		ok("ui build dev: nothing forbidden", #forbidden == forb0, forbidden[forb0 + 1])
		unk = Unknown()
		ok("ui build dev: no unknown method", #unk == 0, table.concat(unk, ","))
	end
	ev, ns, files, toc = Load(nil)
end
-- The bar (0.8.0) in tests: a node's state (Look.State; "base" = none); a click as the game makes it
-- (down, up, click; a hardware event); a shown text in any frame.
function SY.State(x)
	local b = x._lookSt or (x.root and x.root._lookSt)
	local v = b and b.su.cur[b.k]
	if v == "" then return "base" end
	return v
end
function SY.Click(f, button)
	button = button or "LeftButton"
	hw = true
	if f.scripts.OnMouseDown then f.scripts.OnMouseDown(f, button) end
	if f.scripts.OnMouseUp then f.scripts.OnMouseUp(f, button) end
	if f.scripts.OnClick then f.scripts.OnClick(f, button, false) end
	hw = false
end
function SY.HasText(s)
	for _, f in ipairs(frames) do
		for _, fs in ipairs(f.strings or {}) do if fs.text == s and fs.shown then return true end end
	end
	return false
end
-- The 0.8.0 option pages in tests: the page refs (opt, log, chg, cred; frames fo, fl, fc, fr); a page shown or hidden
-- as the game does it (the Settings panel shows the frame); a control set to v the way a player does it (clicks;
-- a stepper: one arrow click per step); the shown text of a node; the shown rows of a Look list box, top down
-- (the text of each font string; raw = with the color codes).
function SY.Opt() return (reg.ns.OptRefs()) end
function SY.ShowPage(f) f.visible = true if f.scripts.OnShow then f.scripts.OnShow(f) end end
function SY.HidePage(f) f.visible = false if f.scripts.OnHide then f.scripts.OnHide(f) end end
function SY.PageSet(key, v)
	local r = SY.Opt().opt
	if key == "ch" then SY.Click(r["ch" .. v]) return end
	if key == "cd" or key == "wait" then
		for _ = 1, 1000 do
			local cur = SpokenWindDB[key]
			if cur == v then return end
			SY.Click(cur < v and r[key .. "Up"] or r[key .. "Down"])
			if SpokenWindDB[key] == cur then return end   -- at a limit
		end
		return
	end
	if (SpokenWindDB[key] and true or false) ~= (v and true or false) then SY.Click(r[key]) end
end
function SY.Tx(n) return SY.Strip((n._lookText or n).text) end
function SY.ListRows(box, raw)
	local out = {}
	for _, k in ipairs(box.kids or {}) do
		if k.shown then
			local row = {}
			for _, fs in ipairs(k.strings or {}) do row[#row + 1] = raw and (fs.text or "") or SY.Strip(fs.text) end
			out[#out + 1] = row
		end
	end
	return out
end

ok("toc no dev file", not toc:find("Dev"))
-- at login: events + the font test + 2 Look helpers (plain frames), the 4 option pages, then the bar + the hello note (UI frames)
do
	local bar, _, _, _, hello = ns.BarRefs()
	local OP = ns.OptRefs()
	local pages = { [OP.fo] = true, [OP.fl] = true, [OP.fc] = true, [OP.fr] = true }
	local plain, ui, pg = 0, 0, 0
	for _, f in ipairs(frames) do
		local p, kind = f, "plain"
		while p do
			if p == (bar and bar.root) or p == (hello and hello.root) then kind = "ui" break end
			if pages[p] then kind = "page" break end
			p = p.parent
		end
		if kind == "ui" then ui = ui + 1 elseif kind == "page" then pg = pg + 1 else plain = plain + 1 end
	end
	-- 2 Look helpers: the screen-size watch and the flow-row after-combat frame
	ok("frames at login: 4 plain (events, the font test, 2 Look helpers) + the 4 option pages + the bar + the hello note",
		plain == 4 and pg > 4 and ui > 0 and frames[1].scripts.OnEvent ~= nil and bar and bar.root.shown and hello and hello.root.shown,
		plain .. "/" .. pg .. "/" .. ui)
	SY.nLogin = #frames
end
ok("chat event on", ev.events.CHAT_MSG_TEXT_EMOTE == true)
ok("reward event on", ev.events.CHAT_MSG_EMOTE == true)
ok("addon_loaded off after load", ev.events.ADDON_LOADED == nil)
ok("defaults", SpokenWindDB.on == true and SpokenWindDB.ch == "SFX" and SpokenWindDB.self == true
	and SpokenWindDB.cd == 1 and SpokenWindDB.wait == 150)
ok("new install: cd 1, move flag set, no move line", SpokenWindDB.cdMove == true and not LogHas("CD move"))
ok("slash", SLASH_SPOKENWIND1 == "/wind" and SLASH_SPOKENWIND2 == "/spokenwind"
	and type(SlashCmdList.SPOKENWIND) == "function")
ok("boot line", LogHas("BOOT v=0.8.4 loc=enUS emotes=FART:checked:/fart slash=/wind clash=0 panel=look log=page flog=page farts=0 ach=button done=0 rw=15 btn=1 sync=1/2 wait=150 tm=1 on=1 ch=SFX self=1 cd=1 n=1351 len=1351/1351 dex=0 own=0 heard=0 people=0 best=0 legend=0 legendHeard=0 reply=1 char=0/0/0 all=0/0/1 tiers=0.0.0.0.0.0.0 alltiers=0.0.0.0.0.0.0 board=0 hide=0 seen=? win=0 rnd=1 tgt=0 aur=0 rev=12 dev=0 set=1337 vms=0 vox=- vbad=0 art=5 apk=0"),
	LastLog())
ok("no prints at load", #prints == 0, prints[1])
ok("public: no dev flag", SPOKEN_WIND_DEV == nil)
ev.scripts.OnEvent(ev, "PLAYER_LOGIN")   -- a second login event never builds a second page
ok("page built once", #reg.cats == 1 and #reg.subs == 3 and #frames == SY.nLogin, #reg.cats)

-- every row: every sound file on disk (Media\<folder>\), a real ogg, short names
local SOUNDS = ns.EMOTES.FART.sounds
ok("only FART shipped", next(ns.EMOTES) == "FART" and next(ns.EMOTES, "FART") == nil)
ok("the old 14 + the 1337 set", #SOUNDS == 1351 and ns.BASE_N == 14, #SOUNDS)
for token, row in pairs(ns.EMOTES) do
	for i, s in ipairs(row.sounds) do
		local f = io.open(ADDON_DIR .. "/Media/" .. (s.dir or row.folder) .. "/" .. s.file .. ".ogg", "rb")
		local head = f and f:read(4)
		if f then f:close() end
		ok("file " .. token .. " " .. s.file, head == "OggS", head)
		ok("name short " .. token .. " " .. i, #s.name <= (i <= ns.BASE_N and 12 or 25), s.name)   -- a pack name: max 25
	end
end
ok("media path", ns.MEDIA == "Interface\\AddOns\\Spoken_Wind\\Media\\")
-- the synth's list (tools/synth.py) and the FART row agree, in order
local syn = assert(io.open(ROOT .. "/tools/synth.py", "rb")):read("*a")
local k = 0
for stem, name in syn:gmatch('%("(%d%d_[%w_]+)", "([^"]+)", f_') do
	k = k + 1
	ok("synth row " .. k, SOUNDS[k] and SOUNDS[k].file == stem and SOUNDS[k].name == name, stem)
end
ok("synth rows = the old 14", k == ns.BASE_N, k)

-- ---------------------------------------------------------------- options page (0.8.0: own canvas pages)
ok("no prints from page build", #prints == 0)
;(function()   -- UI\sw-options in a plain frame: every control = the save at once (as /wind)
	local OP, OS = ns.OptRefs()
	local O = OP.opt
	ok("page registered: one canvas page Spoken Wind", #reg.cats == 1 and reg.cats[1] == reg.cat and reg.cat.name == "Spoken Wind"
		and reg.cat.frame == OP.fo and ns.optCat == reg.cat)
	ok("page: 3 sub-pages under it: Fart log, Changelog, Credits", #reg.subs == 3 and reg.subs[1].name == "Fart log"
		and reg.subs[2].name == "Changelog" and reg.subs[3].name == "Credits" and reg.subs[1].frame == OP.fl
		and reg.subs[2].frame == OP.fc and reg.subs[3].frame == OP.fr and reg.subs[1].parent == reg.cat
		and reg.subs[2].parent == reg.cat and reg.subs[3].parent == reg.cat and OS.log == reg.subs[1] and OS.chg == reg.subs[2]
		and OS.cred == reg.subs[3])
	ok("page: no game setting objects, no vertical page", #reg.list == 0 and #reg.controls == 0 and #reg.buttons == 0
		and reg.layout == nil)
	ok("page: the screen in a plain frame, no window shell", O and O.root.parent == OP.fo and _G.SpokenWindOptions == O.root
		and not O.root.movable and O.root.strata == nil and O.root.kb == nil and O.root.drag == nil)
	ok("page: public = no Dev rows (from the start)", not O.secDev.shown and not O.testR.shown)
	SY.ShowPage(OP.fo)
	ok("page: version", SY.Tx(O.ver) == tostring(ns.VERSION), SY.Tx(O.ver))
	for _, k in ipairs({ "on", "self", "random", "rwbtn" }) do
		ok("page: toggle " .. k .. " On (the default)", SY.Tx(O[k]) == "On" and SY.State(O[k]) == "on", SY.Tx(O[k]))
	end
	ok("page: channel chips, SFX picked", SY.Tx(O.chMaster) == "Master" and SY.Tx(O.chSFX) == "SFX" and SY.Tx(O.chDialog) == "Dialog"
		and SY.State(O.chSFX) == "sel" and SY.State(O.chMaster) == "base" and SY.State(O.chDialog) == "base")
	ok("page: steppers", SY.Tx(O.cd) == "1 s" and SY.Tx(O.wait) == "150 ms" and SY.Tx(O.cdDown) == "\226\128\185"
		and SY.Tx(O.cdUp) == "\226\128\186" and SY.Tx(O.waitDown) == "\226\128\185" and SY.Tx(O.waitUp) == "\226\128\186",
		SY.Tx(O.cd) .. " " .. SY.Tx(O.wait))
	ok("page: arrows lit (no value at a limit)", O.cdDown:GetAlpha() == 1 and O.cdUp:GetAlpha() == 1 and O.waitDown:GetAlpha() == 1
		and O.waitUp:GetAlpha() == 1)
	ok("page: public = no Dev rows", not O.secDev.shown and not O.testR.shown and SY.Tx(O.devTag) == "Dev")
	ok("page: the screen's labels", SY.Tx(O.onL) == "Sounds" and SY.Tx(O.waitL) == "Sync wait", SY.Tx(O.onL))
	-- a toggle click: the save, the OPT line, the page
	SY.Click(O.self)
	ok("page click: Own /fart off", SpokenWindDB.self == false and LastLog():find("OPT self=false by=panel$")
		and SY.Tx(O.self) == "Off" and SY.State(O.self) == "base", LastLog())
	SY.Click(O.self)
	ok("page click: Own /fart on", SpokenWindDB.self == true and SY.Tx(O.self) == "On" and SY.State(O.self) == "on")
	SY.Click(O.chDialog)
	ok("page click: channel Dialog", SpokenWindDB.ch == "Dialog" and SY.State(O.chDialog) == "sel" and SY.State(O.chSFX) == "base"
		and LastLog():find("OPT ch=Dialog by=panel$"), LastLog())
	local n0 = #SpokenWindDB.log
	SY.Click(O.chDialog)
	ok("page click: the picked chip again = nothing", #SpokenWindDB.log == n0 and SpokenWindDB.ch == "Dialog")
	SY.Click(O.chSFX)
	-- steppers: one click = one step; at a limit the arrow is dim and does nothing
	SY.Click(O.cdUp)
	ok("page stepper: cd +0.5", SpokenWindDB.cd == 1.5 and SY.Tx(O.cd) == "1.5 s" and LastLog():find("OPT cd=1.5 by=panel$"), LastLog())
	SY.Click(O.cdDown) SY.Click(O.cdDown) SY.Click(O.cdDown)
	ok("page stepper: cd down to 0, dim at 0", SpokenWindDB.cd == 0 and SY.Tx(O.cd) == "0 s" and O.cdDown:GetAlpha() < 1
		and O.cdUp:GetAlpha() == 1, SY.Tx(O.cd))
	n0 = #SpokenWindDB.log
	SY.Click(O.cdDown)
	ok("page stepper: at 0 the arrow does nothing", SpokenWindDB.cd == 0 and #SpokenWindDB.log == n0 and O.root.scripts.OnUpdate == nil)
	SY.Click(O.waitUp)
	ok("page stepper: wait +10", SpokenWindDB.wait == 160 and SY.Tx(O.wait) == "160 ms", SY.Tx(O.wait))
	for _ = 1, 20 do SY.Click(O.waitUp) end
	ok("page stepper: wait stops at 300, dim", SpokenWindDB.wait == 300 and SY.Tx(O.wait) == "300 ms" and O.waitUp:GetAlpha() < 1
		and O.waitDown:GetAlpha() == 1, SY.Tx(O.wait))
	-- a held arrow: the first step at once, repeats after 0.4 s, one step per 0.08 s, one OPT line on release
	SpokenWindDB.wait = 150
	ns.OptRedraw()
	local nl = #SpokenWindDB.log
	O.waitDown.scripts.OnMouseDown(O.waitDown, "LeftButton")
	ok("page hold: the first step at once", SpokenWindDB.wait == 140 and O.root.scripts.OnUpdate ~= nil)
	now = now + 0.3 O.root.scripts.OnUpdate(O.root, 0.3)
	ok("page hold: no repeat before 0.4 s", SpokenWindDB.wait == 140, SpokenWindDB.wait)
	now = now + 0.15 O.root.scripts.OnUpdate(O.root, 0.15)
	ok("page hold: repeats after 0.4 s", SpokenWindDB.wait == 130, SpokenWindDB.wait)
	for _ = 1, 5 do now = now + 0.08 O.root.scripts.OnUpdate(O.root, 0.08) end
	ok("page hold: one step per 0.08 s", SpokenWindDB.wait == 80 and SY.Tx(O.wait) == "80 ms", SpokenWindDB.wait)
	ok("page hold: no OPT line while held", #SpokenWindDB.log == nl, LastLog())
	O.waitDown.scripts.OnMouseUp(O.waitDown, "LeftButton")
	ok("page hold: one OPT line on release, no OnUpdate", #SpokenWindDB.log == nl + 1 and LastLog():find("OPT wait=80 by=panel$")
		and O.root.scripts.OnUpdate == nil, LastLog())
	O.waitDown.scripts.OnMouseDown(O.waitDown, "LeftButton")
	for _ = 1, 40 do now = now + 0.5 if O.root.scripts.OnUpdate then O.root.scripts.OnUpdate(O.root, 0.5) end end
	ok("page hold: the hold ends at the limit", SpokenWindDB.wait == 0 and O.root.scripts.OnUpdate == nil
		and LastLog():find("OPT wait=0 by=panel$"), LastLog())
	nl = #SpokenWindDB.log
	O.waitDown.scripts.OnMouseUp(O.waitDown, "LeftButton")
	ok("page hold: the late release logs nothing more", #SpokenWindDB.log == nl)
	O.cdUp.scripts.OnMouseDown(O.cdUp, "LeftButton")
	O.root.scripts.OnHide(O.root)
	ok("page hold: the page hides = let go", SpokenWindDB.cd == 0.5 and O.root.scripts.OnUpdate == nil
		and LastLog():find("OPT cd=0.5 by=panel$"), LastLog())
	IsMouseButtonDown = function() return false end   -- the button let go off the arrow (no OnMouseUp here)
	O.cdUp.scripts.OnMouseDown(O.cdUp, "LeftButton")
	now = now + 0.5 O.root.scripts.OnUpdate(O.root, 0.5)
	ok("page hold: no button down = let go", SpokenWindDB.cd == 1 and O.root.scripts.OnUpdate == nil
		and LastLog():find("OPT cd=1 by=panel$"), LastLog())
	IsMouseButtonDown = nil
	n0 = #SpokenWindDB.log
	SY.Click(O.cdUp, "RightButton")
	ok("page stepper: a right click = nothing", SpokenWindDB.cd == 1 and #SpokenWindDB.log == n0)
	SpokenWindDB.cd = 1.3   -- an old save off the 0.5 grid: the next step lands on the grid
	SY.Click(O.cdUp)
	ok("page stepper: an off-grid save snaps to the step", SpokenWindDB.cd == 2 and SY.Tx(O.cd) == "2 s", SpokenWindDB.cd)
	-- Defaults = /wind reset
	SpokenWindDB.wait = 150
	SY.Click(O.random) SY.Click(O.chMaster) SY.Click(O.cdUp)
	SY.Click(O.defaults)
	local allDef = true
	for k, v in pairs(ns.DEFAULTS) do if SpokenWindDB[k] ~= v then allDef = false end end
	ok("page Defaults: every default back, on the page", allDef and SY.Tx(O.random) == "On" and SY.State(O.chSFX) == "sel"
		and SY.Tx(O.cd) == "1 s" and SY.Tx(O.wait) == "150 ms" and LastLog():find(" by=panel$"), LastLog())
	-- Achievements Open = the own window
	SY.Click(O.achOpen)
	ok("page: Achievements Open = the window", ns.AchRefs() ~= nil and ns.AchRefs().root.shown and LogHas("ACH open tab=classic"))
	ns.AchRefs().root:Hide()
	-- Pages: the 3 sub-pages in the game's Options (a click only, not in combat)
	SY.Click(O.pgLog)
	ok("page Pages: Fart log", reg.opened == reg.subs[1].id and LastLog():find("OPT page=log ok=1$"), LastLog())
	SY.Click(O.pgLogC)
	ok("page Pages: Changelog", reg.opened == reg.subs[2].id and LastLog():find("OPT page=chg ok=1$"), LastLog())
	SY.Click(O.pgCred)
	ok("page Pages: Credits", reg.opened == reg.subs[3].id and LastLog():find("OPT page=cred ok=1$"), LastLog())
	reg.opened = nil
	combat = true
	n0 = #SpokenWindDB.log
	SY.Click(O.pgLog)
	ok("page Pages: in combat nothing", reg.opened == nil and #SpokenWindDB.log == n0)
	combat = false
	local open = Settings.OpenToCategory
	Settings.OpenToCategory = function() error("no page") end
	SY.Click(O.pgCred)
	ok("page Pages: an error = ok=0, no Lua error", LastLog():find("OPT page=cred ok=0$"), LastLog())
	Settings.OpenToCategory = open
	-- /wind -> the shown page at once; a hidden page waits for its next show
	local pb = #prints
	Slash("self off")
	ok("/wind -> shown page", SY.Tx(O.self) == "Off" and SY.State(O.self) == "base")
	Slash("self on")
	SY.HidePage(OP.fo)
	Slash("cd 3")
	ok("/wind -> hidden page: not drawn", SY.Tx(O.cd) == "1 s", SY.Tx(O.cd))
	SY.ShowPage(OP.fo)
	ok("page shown again: fresh values", SY.Tx(O.cd) == "3 s", SY.Tx(O.cd))
	Slash("cd 1")
	SY.HidePage(OP.fo)
	for i = #prints, pb + 1, -1 do prints[i] = nil end
end)()

-- changelog: one table, newest first, top row = toc Version = BOOT v=
local CL = ns.CHANGELOG
local tocV = toc:match("## Version: (%S+)")
ok("changelog top = toc Version", CL and CL[1] and CL[1].v == tocV, CL and CL[1] and CL[1].v)
ok("changelog top = BOOT v=", LogHas("BOOT v=" .. tostring(CL[1].v) .. " "))
local function Num(v)   -- 1.2.3 or a hotfix 1.2.3.4
	local a, b, c, d = v:match("^(%d+)%.(%d+)%.(%d+)$")
	if not a then a, b, c, d = v:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$") end
	return a and tonumber(a) * 1e9 + tonumber(b) * 1e6 + tonumber(c) * 1e3 + tonumber(d or 0)
end
ok("changelog Num: a hotfix sorts between", Num("0.6.2") < Num("0.6.2.1") and Num("0.6.2.1") < Num("0.6.3")
	and Num("0.6.2.1.5") == nil and Num("0.6") == nil)
for i, row in ipairs(CL) do
	ok("changelog v format " .. i, Num(row.v) ~= nil, row.v)
	if i > 1 then ok("changelog newest first " .. i, Num(row.v) and Num(CL[i - 1].v) and Num(row.v) < Num(CL[i - 1].v)) end
	ok("changelog lines " .. row.v, #row >= 1 and #row <= 6, #row)
	for _, t in ipairs(row) do
		-- 34: the 0.7.0 row text is the coordinator's (33 chars); an options row fits far more
		ok("changelog terse: " .. t, #t <= 34 and not t:find("[%.!?]$") and not t:find("%. "), t)
	end
end
ok("changelog 0.8.4", CL[1].v == "0.8.4" and table.concat(CL[1], ",") == "New look for every window,Credits page,Fart button: whispers left,Right-click Fart = /say,Artifact tier is now Shartifact", table.concat(CL[1], ","))
ok("changelog 0.7.1", CL[2].v == "0.7.1" and table.concat(CL[2], ",") == "Rare Classic farts, 1 in 200,Fix: error spam on hidden auras", table.concat(CL[2], ","))
ok("changelog 0.7.0", CL[3].v == "0.7.0" and table.concat(CL[3], ",") == "Race voices: 74 per race and body,Collection pages per voice", table.concat(CL[3], ","))
ok("changelog 0.6.6", CL[4].v == "0.6.6" and table.concat(CL[4], ",") == "Random farts: 1 per hour,Wake-up fart,/wind random off", table.concat(CL[4], ","))
ok("changelog 0.6.5", CL[5].v == "0.6.5" and table.concat(CL[5], ",") == "Fart button", table.concat(CL[5], ","))
ok("changelog 0.6.4", CL[6].v == "0.6.4" and table.concat(CL[6], ",") == "Board tab,All players,Rarity rows,/wind board off", table.concat(CL[6], ","))
ok("changelog 0.6.3", CL[7].v == "0.6.3" and table.concat(CL[7], ",") == "Collection tab,5 new achievements,Click a sound = play,One sound per person")
ok("changelog 0.6.2.1", CL[8] and CL[8].v == "0.6.2.1" and table.concat(CL[8], ",") == "Toast text centered,Toast click = window,Earned first by rarity",
	table.concat(CL[7], ","))
ok("changelog 0.6.2", CL[9] and CL[9].v == "0.6.2" and table.concat(CL[9], ",") == "Heard count,Farts · Heard · People,Achievements window,17 Social achievements")
ok("changelog 0.6.1", CL[10] and CL[10].v == "0.6.1" and table.concat(CL[10], ",") == "Pair test: /wind pair,Bigger toast + sound")
ok("changelog 0.6.0", CL[11] and CL[11].v == "0.6.0" and table.concat(CL[11], ",") == "Same fart for all,Sync wait 0-300ms")
ok("changelog 0.5.0", CL[12] and CL[12].v == "0.5.0" and table.concat(CL[12], ",") == "15 reward emotes,Rewards button")
ok("changelog 0.4.1", CL[13] and CL[13].v == "0.4.1" and table.concat(CL[13], ",") == "Bigger icons,Clearer Machine Gun,Cooldown 1s,Dev: 1 secret")
ok("changelog 0.4.0", CL[14] and CL[14].v == "0.4.0" and table.concat(CL[14], ",") == "15 achievements,Toasts,Icons by the author")
ok("changelog 0.3.0", CL[15] and CL[15].v == "0.3.0" and table.concat(CL[15], ",") == "Fart log")
ok("changelog 0.2.1", CL[16] and CL[16].v == "0.2.1" and table.concat(CL[16], ",") == "Test: dev only")
ok("changelog 0.2.0", CL[17] and CL[17].v == "0.2.0" and table.concat(CL[17], ",") == "Cooldown per person,Options page,Changelog")
ok("changelog 0.1.0", CL[18] and CL[18].v == "0.1.0" and table.concat(CL[18], ",") == "First release,14 toots,/wind commands")
;(function()   -- the Changelog sub-page (UI\sw-changelog): one row per line, newest first, in pages
	local OP = ns.OptRefs()
	local C = OP.chg
	local sub = reg.subs[2]
	ok("changelog sub-page 2nd (credits last)", #reg.subs == 3 and sub.parent == reg.cat and sub.name == "Changelog" and sub.frame == OP.fc)
	SY.ShowPage(OP.fc)
	ok("changelog page: version tag", SY.Tx(C.ver) == tostring(ns.VERSION) and SY.State(C.ver) == "sel", SY.Tx(C.ver))
	local want = {}   -- every line: its version (first line of a version) + the text
	for _, row in ipairs(CL) do
		for j, t in ipairs(row) do want[#want + 1] = { v = row.v, first = j == 1, t = "\194\183\194\160" .. t } end
	end
	local rows = SY.ListRows(C.lines)
	local per = #rows
	ok("changelog page: a full page (482 px / 24 px rows)", per == 20, per)
	local function Page(p)   -- what page p must show: the version on its first line and on the page's first row
		local out = {}
		for i = (p - 1) * per + 1, math.min(#want, p * per) do
			local w = want[i]
			out[#out + 1] = ((w.first or i == (p - 1) * per + 1) and w.v or "") .. "|" .. w.t
		end
		return table.concat(out, "\n")
	end
	local function Got()
		local out = {}
		for _, r in ipairs(SY.ListRows(C.lines)) do out[#out + 1] = table.concat(r, "|") end
		return table.concat(out, "\n")
	end
	local pages = math.ceil(#want / per)
	ok("changelog page 1", Got() == Page(1), Got())
	ok("changelog page 1: newest first", rows[1][1] == CL[1].v and rows[1][2] == "\194\183\194\160" .. CL[1][1], rows[1][1])
	ok("changelog pager", SY.Tx(C.page) == "1/" .. pages and pages >= 2, SY.Tx(C.page))
	SY.Click(C.next)
	ok("changelog page 2: its first row shows the version", Got() == Page(2) and SY.Tx(C.page) == "2/" .. pages, Got())
	local raw = SY.ListRows(C.lines, true)
	ok("changelog: the dot and the text in 2 colors", select(2, raw[1][2]:gsub("|c%x%x%x%x%x%x%x%x", "")) == 2, raw[1][2])
	SY.HidePage(OP.fc)
	SY.ShowPage(OP.fc)
	ok("changelog: shown again = page 1", Got() == Page(1) and SY.Tx(C.page) == "1/" .. pages, SY.Tx(C.page))
	SY.HidePage(OP.fc)
end)()
-- many versions later: still one page, older ones summed up
local saveCL = ns.CHANGELOG
local big = {}
for i = 40, 1, -1 do big[#big + 1] = { v = "0." .. i .. ".0", "Line A", "Line B", "Line C" } end
ns.CHANGELOG = big
local lines = ns.ChangelogLines()
ok("changelog capped", #lines <= 29, #lines)
ok("changelog cap says older", lines[#lines][1]:find("^%+%d+ older$"), lines[#lines][1])
ok("changelog cap keeps newest", lines[1][1] == "0.40.0")
local function Px(ls)   -- px from the first line's top to the last line's bottom (same math as the page)
	local h = 0
	for _, l in ipairs(ls) do h = h + 16 + (l[3] == 0 and 8 or 0) end
	return h
end
ok("changelog cap: pixel budget", Px(lines) <= 448 and Px(ns.ChangelogLines(424)) <= 424, Px(lines))
ok("changelog cap: fills the page", Px(lines) > 448 - 72, Px(lines))
ns.CHANGELOG = saveCL

;(function()   -- credits: own sub-page (author + testers), the toc Author, packed tester lines, no scroll
	local C = ns.CREDITS
	local function Flat(list) local o = {} for _, e in ipairs(list) do o[#o + 1] = tostring(e[1]) .. "/" .. tostring(e[2]) end return table.concat(o, "|") end
	ok("credits: author + class", C and type(C.author) == "table" and C.author[1] == "Hals Dunngold" and C.author[2] == "HUNTER",
		C and Flat({ C.author }))
	ok("credits: testers (only the OK'd names, game spelling, class)", C and type(C.testers) == "table"
		and Flat(C.testers) == "Bumm Farto/PRIEST|Chrissy Walnutz/WARRIOR", C and type(C.testers) == "table" and Flat(C.testers))
	ok("credits: toc Author = the credits author", toc:match("## Author: ([^\r\n]+)") == (C and C.author[1]), toc:match("## Author: ([^\r\n]+)"))
	local cs = reg.subs[3]
	local OP = ns.OptRefs()
	local R = OP.cred
	ok("credits: sub-page last, under the main page", cs and cs.parent == reg.cat and cs.name == "Credits" and cs.frame == OP.fr,
		cs and cs.name)
	SY.ShowPage(OP.fr)
	ok("credits page: version", SY.Tx(R.ver) == "Spoken Wind " .. tostring(ns.VERSION), SY.Tx(R.ver))
	-- no color API in the test game: every class = white
	ok("credits page: the author in the class color (white here)", R.author.text == "|cffffffffHals Dunngold|r", R.author.text)
	local tr = SY.ListRows(R.testers, true)
	ok("credits page: testers, one a row, class colors", SY.Tx(R.testersN) == "2" and #tr == 2
		and tr[1][1] == "|cffffffffBumm Farto|r" and tr[2][1] == "|cffffffffChrissy Walnutz|r", #tr)
	-- the "Inspired by" paragraph (0.8.0): the approved text, byte for byte, under the thanks row, wrapped to the page
	;(function()
		local T = "I really like the Spoken addon. It gives the NPCs a voice, so I started thinking about which emotes I could make sound effects for. I landed on /fart, because a fart addon with way too much effort put into it felt perfect. Spoken Wind isn't made by the Spoken team. And no, I don't have a fart fetish."
		local p, row = R.inspT, R.insp
		ok("credits page: Inspired by text = the approved text, byte for byte", p ~= nil and p.text == T and #T == 301
			and SY.Tx(R.secThanksL) == "Inspired by", p and #tostring(p.text))
		local k = R.body._look.kids
		ok("credits page: the text row last, under the Spoken row", row ~= nil and k[#k].obj == row and k[#k - 1].obj == R.th1
			and k[#k].m.cls == "S" and row:IsShown())
		ok("credits page: the text wraps to the page width (568 px), left, Lato body", p and p.wrap == true and p.width == 568
			and p.justify == "LEFT" and tostring(p.fontPath):find("Lato.ttf", 1, true) ~= nil, p and tostring(p.width))
		ok("credits page: the row holds every line", p and row:GetHeight() == math.ceil(p:GetStringHeight()) + 2
			and p:GetStringHeight() >= 36, row and row:GetHeight())
		local y
		for _, q in ipairs(row and row.points or {}) do if q[1] == "TOPLEFT" then y = q[5] end end
		ok("credits page: the page grows for it (no scroll bar)", y ~= nil and y < -100
			and R.body:GetHeight() >= -y + row:GetHeight() and R.root:GetHeight() >= R.body:GetHeight(),
			tostring(y) .. " " .. R.body:GetHeight())
	end)()
	local saveC = ns.CREDITS
	ns.CREDITS = 7
	SY.HidePage(OP.fr)
	SY.ShowPage(OP.fr)
	ok("credits page: bad data = no names, no error", SY.Tx(R.testersN) == "0" and R.author.text == "", SY.Tx(R.testersN))
	ns.CREDITS = saveC
	SY.HidePage(OP.fr)
	ok("credits: BOOT cred=page", LogHas(" apk=0 cred=page"))

	local function Px(ls) local h = 0 for _, l in ipairs(ls) do h = h + 16 + (l[3] == 0 and 8 or 0) end return h end
	local function Names(ls, from)   -- the names on the tester lines (not "+N more")
		local got = {}
		for i = from, #ls do
			if not ls[i][1]:find("^%+%d+ more$") then
				for n in (ls[i][1] .. " · "):gmatch("(.-) · ") do got[#got + 1] = n end
			end
		end
		return got
	end
	local save = ns.CREDITS
	-- 30 testers: packed in lines of at most 56 bytes, every name once, in order, one page
	local names = {}
	for i = 1, 30 do names[i] = "Tester" .. i end
	ns.CREDITS = { author = "A", testers = names }
	local ls = ns.CreditsLines()
	ok("credits many: Author, A, Testers first", ls[1][1] == "Author" and ls[2][1] == "A" and ls[3][1] == "Testers"
		and ls[3][3] == 0 and ls[4][3] == 12 and ls[4][2] == "GameFontHighlight")
	ok("credits many: every name once, in order", table.concat(Names(ls, 4), ",") == table.concat(names, ","),
		table.concat(Names(ls, 4), ","))
	local long = 0
	for i = 4, #ls do long = math.max(long, #ls[i][1]) end
	ok("credits many: packed (fewer lines than names), no line over 56 bytes", #ls - 3 < 10 and long <= 56 and long > 45, #ls .. " " .. long)
	ok("credits many: one page, no +more", Px(ls) <= 448 and not ls[#ls][1]:find("more", 1, true), Px(ls))
	-- too many for one page: the newest lines are cut, "+N more" counts the names left out
	local lots = {}
	for i = 1, 600 do lots[i] = "T" .. i end
	ns.CREDITS = { author = "A", testers = lots }
	ls = ns.CreditsLines()
	local nm = tonumber(ls[#ls][1]:match("^%+(%d+) more$"))
	ok("credits cap: +N more, last, grey", nm ~= nil and ls[#ls][2] == "GameFontDisable", ls[#ls][1])
	ok("credits cap: shown + N = all", nm and #Names(ls, 4) + nm == 600 and table.concat(Names(ls, 4), ","):sub(1, 9) == "T1,T2,T3,",
		#Names(ls, 4) .. " + " .. tostring(nm))
	ok("credits cap: fits the page", Px(ls) <= 448 and Px(ls) > 448 - 40, Px(ls))
	ls = ns.CreditsLines(160)
	nm = tonumber(ls[#ls][1]:match("^%+(%d+) more$"))
	ok("credits cap: old-client budget 160 px", Px(ls) <= 160 and nm and #Names(ls, 4) + nm == 600, Px(ls))
	-- the edges
	ns.CREDITS = { author = "A", testers = { "x", ("y"):rep(70), "z" } }
	ls = ns.CreditsLines()
	ok("credits: a name over 56 bytes = its own line", #ls == 6 and ls[4][1] == "x" and ls[5][1] == ("y"):rep(70) and ls[6][1] == "z",
		#ls)
	local a30, b26, c26, d26 = ("a"):rep(30), ("b"):rep(26), ("c"):rep(26), ("d"):rep(26)
	ns.CREDITS = { testers = { a30, b26, c26, d26 } }
	ls = ns.CreditsLines()
	ok("credits: the ' · ' bytes count in the 56", #ls == 4 and ls[2][1] == a30 and ls[3][1] == b26 .. " \194\183 " .. c26
		and #ls[3][1] == 56 and ls[4][1] == d26, #ls .. " " .. tostring(ls[2] and #ls[2][1]))
	-- class colors (read only): C_ClassColor first, else RAID_CLASS_COLORS, else white
	ok("class color: no color API = white", ns.ClassHex("HUNTER") == "ffffff" and ns.ClassHex(nil) == "ffffff")
	local RCC = { HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, PRIEST = { r = 1, g = 1, b = 1 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
		ROGUE = { r = 1, g = 0.96, b = 0.41 }, BAD = { r = "x", g = 0, b = 0 }, HOT = { r = 1.2, g = -0.1, b = 0.5 } }
	local function Snap() local o = {} for k, v in pairs(RCC) do o[#o + 1] = k .. "=" .. tostring(v.r) .. tostring(v.g) .. tostring(v.b) end table.sort(o) return table.concat(o, ",") end
	local snap = Snap()
	RAID_CLASS_COLORS = RCC
	ok("class color: RAID_CLASS_COLORS, the 3 credits classes", ns.ClassHex("HUNTER") == "abd473" and ns.ClassHex("PRIEST") == "ffffff"
		and ns.ClassHex("WARRIOR") == "c79c6e", ns.ClassHex("HUNTER") .. " " .. ns.ClassHex("WARRIOR"))
	ok("class color: missing or bad token = white", ns.ClassHex("NOPE") == "ffffff" and ns.ClassHex("") == "ffffff"
		and ns.ClassHex(nil) == "ffffff" and ns.ClassHex("BAD") == "ffffff", ns.ClassHex("BAD"))
	ok("class color: clamped to 00-ff", ns.ClassHex("HOT") == "ff0080", ns.ClassHex("HOT"))
	C_ClassColor = { GetClassColor = function(t)
		if t == "HUNTER" then return { r = 0, g = 1, b = 0 } end
		if t == "WARRIOR" then error("api boom") end
	end }
	ok("class color: C_ClassColor first; none or an error = RAID_CLASS_COLORS", ns.ClassHex("HUNTER") == "00ff00"
		and ns.ClassHex("WARRIOR") == "c79c6e" and ns.ClassHex("ROGUE") == "fff569", ns.ClassHex("HUNTER") .. " " .. ns.ClassHex("ROGUE"))
	ns.CREDITS = { author = { "A", "HUNTER" }, testers = { { "x", "PRIEST" }, { "y", "WARRIOR" }, { "z", "NOPE" }, "w", { "", "ROGUE" }, { 5 } } }
	ls = ns.CreditsLines()
	ok("credits color: author + testers in class colors, a plain name stays plain, no empty name", #ls == 4 and ls[2][1] == "|cff00ff00A|r"
		and ls[4][1] == "|cffffffffx|r \194\183 |cffc79c6ey|r \194\183 |cffffffffz|r \194\183 w", ls[4] and ls[4][1])
	ns.CREDITS = { testers = { { a30, "HUNTER" }, { b26, "WARRIOR" }, { c26, "WARRIOR" }, { d26, "ROGUE" } } }
	ls = ns.CreditsLines()
	ok("credits color: the color code does not count in the 56", #ls == 4 and ls[2][1] == "|cff00ff00" .. a30 .. "|r"
		and ls[3][1] == "|cffc79c6e" .. b26 .. "|r \194\183 |cffc79c6e" .. c26 .. "|r" and ls[4][1] == "|cfffff569" .. d26 .. "|r", #ls)
	ok("class color: RAID_CLASS_COLORS only read", Snap() == snap and RAID_CLASS_COLORS == RCC)
	C_ClassColor, RAID_CLASS_COLORS = nil, nil
	ns.CREDITS = { author = "A", testers = {} }
	ls = ns.CreditsLines()
	ok("credits: no testers = no Testers label", #ls == 2 and ls[2][1] == "A", #ls)
	ok("credits: the label gold, the name white + in", ls[1][2] == "GameFontNormal" and ls[1][3] == 0
		and ls[2][2] == "GameFontHighlight" and ls[2][3] == 12, tostring(ls[2][2]))
	ns.CREDITS = { testers = { "x" } }
	ls = ns.CreditsLines()
	ok("credits: no author = no Author label", #ls == 2 and ls[1][1] == "Testers" and ls[2][1] == "x", #ls)
	ns.CREDITS = { author = "", testers = { 5, "", "ok", false } }
	ls = ns.CreditsLines()
	ok("credits: only non-empty text", #ls == 2 and ls[1][1] == "Testers" and ls[2][1] == "ok", #ls)
	ns.CREDITS = nil
	ok("credits: no data = no lines", #ns.CreditsLines() == 0)
	ns.CREDITS = 5
	local okB, nB = pcall(function() return #ns.CreditsLines() end)
	ok("credits: bad data = no lines, no error", okB and nB == 0, tostring(nB))
	ns.CREDITS = save
end)()

-- page -> db -> addon
local S = reg.byVar
S.SpokenWind_cd:SetValue(0)
ok("page cd -> db", SpokenWindDB.cd == 0)
ok("page cd logged", LastLog():find("OPT cd=0 by=panel", 1, true), LastLog())
S.SpokenWind_on:SetValue(false)
plays = {}
Emote(OTHER_FART, "Bob", BOB)
ok("page off -> silent", #plays == 0)
S.SpokenWind_on:SetValue(true)
S.SpokenWind_ch:SetValue("Dialog")
Emote(OTHER_FART, "Bob", BOB)
ok("page ch -> play channel", plays[1] and plays[1].ch == "Dialog")
S.SpokenWind_self:SetValue(false)
Emote("You fart loudly. Phew...what stinks?", ME, ME_GUID)
ok("page own off -> silent", #plays == 1, #plays)
local b = #prints
Slash("")
ok("/wind shows page values", prints[b + 1] and prints[b + 1]:find("on · Dialog · self off · cd 0s/person", 1, true),
	prints[b + 1])
-- /wind -> db -> page
Slash("cd 5")
ok("/wind cd -> page", S.SpokenWind_cd:GetValue() == 5 and SpokenWindDB.cd == 5)
ok("/wind cd logged", LastLog():find("OPT cd=5 by=slash", 1, true), LastLog())
Slash("ch master")
ok("/wind ch -> page", S.SpokenWind_ch:GetValue() == "Master")
Slash("self")
ok("/wind self -> page", S.SpokenWind_self:GetValue() == true)
Slash("off")
ok("/wind off -> page", S.SpokenWind_on:GetValue() == false)
Slash("reset")
for key, def in pairs(DEF) do ok("reset -> page " .. key, S["SpokenWind_" .. key]:GetValue() == def) end
-- public: no /wind test (the word only shows the status), no "test" in the help
Slash("off")
plays, b = {}, #prints
Slash("test 4")
ok("public: /wind test plays nothing", #plays == 0, #plays)
ok("public: /wind test = status", #prints == b + 2 and prints[b + 2]:find("on|off · ch master", 1, true), prints[b + 2])
ok("public: help has no test", prints[b + 2] and not prints[b + 2]:find("test", 1, true), prints[b + 2])
ok("public: no TEST log", not LogHas("TEST emo="))
Slash("reset")

-- ---------------------------------------------------------------- plays
plays = {}
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("other fart plays", #plays == 1)
ok("path", plays[1] and plays[1].path:match("^Interface\\AddOns\\Spoken_Wind\\Media\\fart\\%d%d_[%a]+%.ogg$"),
	plays[1] and plays[1].path)
ok("channel SFX", plays[1] and plays[1].ch == "SFX")
ok("log PLAY", LogHas("PLAY emo=FART who=other snd="))
Emote("Bob waves at you.", "Bob", BOB)
ok("wave no sound", #plays == 1)

-- one sound per person. Short sounds here (0.5 s), so cd (the min gap) decides; the length tests follow.
SY.ShortLen(500)
-- cooldown per person: Bob spams 20 in a second -> 1 sound; Ann at the same time -> plays too
plays = {}
now = now + 10
for n = 1, 20 do Emote(OTHER_FART, "Bob", BOB) now = now + 0.05 end
ok("one person spam -> one sound", #plays == 1, #plays)
ok("log SKIP busy", LogHas("SKIP busy emo=FART who=other left="))
Emote(ANN_FART, "Ann", ANN)
ok("second person plays during first's cd", #plays == 2, #plays)
Emote(ANN_FART, "Ann", ANN)
ok("second person own cd", #plays == 2, #plays)
Emote("You fart loudly. Phew...what stinks?", ME, ME_GUID)
ok("own fart has its own key", #plays == 3, #plays)
Emote("You fart loudly. Phew...what stinks?", ME, ME_GUID)
ok("own fart own cd", #plays == 3, #plays)
ok("log SKIP busy who=self", LogHas("SKIP busy emo=FART who=self left="))
now = now + 2.01
Emote(OTHER_FART, "Bob", BOB)
ok("same person after cd plays again", #plays == 4, #plays)
now = now + 0.99
Emote(OTHER_FART, "Bob", BOB)
ok("default cd 1 s: 0.99 s later skips", #plays == 4, #plays)
now = now + 0.02
Emote(OTHER_FART, "Bob", BOB)
ok("default cd 1 s: 1.01 s later plays", #plays == 5, #plays)
-- no GUID: the name is the key (Name-Realm kept whole)
plays = {}
now = now + 10
Emote(FartBy("Bob-RealmA"), "Bob-RealmA", nil)
Emote(FartBy("Bob-RealmA"), "Bob-RealmA", nil)
Emote(FartBy("Bob-RealmB"), "Bob-RealmB", nil)
Emote(ANN_FART, "Ann", nil)
ok("no guid: name keys", #plays == 3, #plays)
-- two people at the very same moment, many times: never blocked by each other
plays = {}
for n = 1, 10 do
	now = now + 2.5
	Emote(OTHER_FART, "Bob", BOB)
	Emote(ANN_FART, "Ann", ANN)
end
ok("A+B every 2.5 s -> all 20 play", #plays == 20, #plays)

-- keys are pruned: 100 people, each farts once, 31 s apart -> table stays small
for n = 1, 100 do now = now + 31 Emote(FartBy("P" .. n), "P" .. n, "Player-1-P" .. n) end
local kn = SumKeys()
ok("keys pruned (100 people)", kn and kn <= 33, kn)
-- prune never drops a key still in its cooldown: 40 people in 1 s, then again
now = now + 100
plays = {}
for n = 1, 40 do Emote(FartBy("Q" .. n), "Q" .. n, "Player-1-Q" .. n) now = now + 0.01 end
for n = 1, 40 do Emote(FartBy("Q" .. n), "Q" .. n, "Player-1-Q" .. n) now = now + 0.01 end
ok("40 people: 40 sounds, repeats blocked", #plays == 40, #plays)
now = now + 31
Emote(FartBy("Z"), "Z", "Player-1-Z")
ok("old keys dropped later", SumKeys() == 1, LastLog())

-- never the same sound twice in a row (cd 0, many farts)
Slash("cd 0")
ok("cd 0 set", SpokenWindDB.cd == 0)
SY.ShortLen(0.1)   -- 0.1 ms sounds: with cd 0 every fart plays
plays = {}
for n = 1, 300 do now = now + 0.001 Emote(OTHER_FART, "Bob", BOB) end
local rep = 0
for n = 2, #plays do if plays[n].path == plays[n - 1].path then rep = rep + 1 end end
ok("cd 0: every fart plays", #plays == 300, #plays)
ok("no same sound twice in a row", rep == 0, rep)
ok("log capped", #SpokenWindDB.log <= 60, #SpokenWindDB.log)
SY.ShortLen()
ok("len: every sound of the pool has a length", (function()
	for _, token in ipairs(ns.Tokens()) do
		for _, s in ipairs(ns.EMOTES[token].sounds) do
			if not (type(ns.LEN[s.file]) == "number" and ns.LEN[s.file] > 0) then return false end
		end
	end
	return true
end)())

-- one sound per person: busy for max(cd, the picked sound's length) from the play start
Slash("cd 1")
;(function()
	local OWN = "You fart loudly. Phew...what stinks?"
	local function Stem(p) return p and p.path:match("([^\\]+)%.ogg$") end
	-- the real length of the sound that played
	plays = {}
	now = now + 10
	local t0 = now
	Emote(OTHER_FART, "Bob", BOB)
	local f = Stem(plays[1])
	local L = f and ns.LEN[f] and ns.LEN[f] / 1000
	ok("len: the played sound has its length", #plays == 1 and L and L > 0, f)
	L = math.max(1, L or 0)
	now = t0 + L - 0.05
	Emote(OTHER_FART, "Bob", BOB)
	ok("len: same person blocked until its sound ends", #plays == 1
		and LastLog():find("SKIP busy emo=FART who=other left=", 1, true) ~= nil, LastLog())
	now = t0 + L + 0.01
	Emote(OTHER_FART, "Bob", BOB)
	ok("len: plays again once its sound ended", #plays == 2, #plays)
	-- a 3 s fart: blocks the same person 3 s, not another person
	SY.ShortLen(3000)
	plays = {}
	now = now + 10
	t0 = now
	Emote(OTHER_FART, "Bob", BOB)
	now = t0 + 1.5
	Emote(OTHER_FART, "Bob", BOB)
	ok("len 3 s: blocked at 1.5 s (cd 1 is over)", #plays == 1
		and LastLog():find("SKIP busy emo=FART who=other left=1.5", 1, true) ~= nil, LastLog())
	Emote(ANN_FART, "Ann", ANN)
	ok("len 3 s: another person is not blocked", #plays == 2, #plays)
	now = t0 + 2.95
	Emote(OTHER_FART, "Bob", BOB)
	ok("len 3 s: blocked at 2.95 s", #plays == 2, #plays)
	now = t0 + 3.01
	Emote(OTHER_FART, "Bob", BOB)
	ok("len 3 s: plays at 3.01 s", #plays == 3, #plays)
	-- your own sound: the same rule (key self)
	now = now + 10
	t0 = now
	Emote(OWN, ME, ME_GUID)
	now = t0 + 2
	Emote(OWN, ME, ME_GUID)
	ok("len 3 s: your own sound blocks your next one", #plays == 4
		and LastLog():find("SKIP busy emo=FART who=self left=1.0", 1, true) ~= nil, LastLog())
	now = t0 + 3.01
	Emote(OWN, ME, ME_GUID)
	ok("len 3 s: your own plays at 3.01 s", #plays == 5, #plays)
	-- cd 1 still holds for short sounds
	SY.ShortLen(300)
	plays = {}
	now = now + 10
	t0 = now
	Emote(OTHER_FART, "Bob", BOB)
	now = t0 + 0.5
	Emote(OTHER_FART, "Bob", BOB)
	ok("cd 1, 0.3 s sound: blocked at 0.5 s", #plays == 1 and LastLog():find("left=0.5", 1, true) ~= nil, LastLog())
	now = t0 + 1.01
	Emote(OTHER_FART, "Bob", BOB)
	ok("cd 1, 0.3 s sound: plays at 1.01 s", #plays == 2, #plays)
	-- a sound with no length: the 5 s default, logged once per file
	SY.ShortLen(false)
	plays = {}
	now = now + 10
	t0 = now
	Emote(OTHER_FART, "Bob", BOB)
	local f2 = Stem(plays[1])
	ok("len missing: logged", f2 ~= nil and LogHas("LEN missing key=" .. f2), f2)
	now = t0 + 4.9
	Emote(OTHER_FART, "Bob", BOB)
	ok("len missing: the 5 s default: blocked at 4.9 s", #plays == 1, #plays)
	now = t0 + 5.01
	Emote(OTHER_FART, "Bob", BOB)
	ok("len missing: plays at 5.01 s", #plays == 2, #plays)
	for _ = 1, 12 do now = now + 5.01 Emote(OTHER_FART, "Bob", BOB) end
	local seen, twice = {}, 0
	for _, l in ipairs(SpokenWindDB.log) do
		local k = l:match("LEN missing key=(%S+)")
		if k then
			if seen[k] then twice = twice + 1 end
			seen[k] = true
		end
	end
	ok("len missing: logged once per file", #plays == 14 and twice == 0, twice)
	SY.ShortLen()
end)()
Slash("cd 2")

-- self
plays = {}
now = now + 10
Emote("You fart loudly. Phew...what stinks?", ME, ME_GUID)
ok("own fart plays (self on)", #plays == 1)
ok("log who=self", LogHas("PLAY emo=FART who=self"))
Slash("self off")
ok("self off", SpokenWindDB.self == false)
now = now + 10
Emote("You fart loudly. Phew...what stinks?", ME, ME_GUID)
Emote("You brush up against Bob and fart loudly.", ME .. "-Realm", nil)   -- no guid: name check
ok("own fart silent (self off)", #plays == 1, #plays)
ok("log SKIP self", LogHas("SKIP self emo=FART"))
Emote(OTHER_FART, "Bob", BOB)
ok("others still play (self off)", #plays == 2)
Slash("self")
ok("self toggles on", SpokenWindDB.self == true)

-- off
Slash("off")
plays = {}
now = now + 10
Emote(OTHER_FART, "Bob", BOB)
ok("off: silent", #plays == 0)
ok("log SKIP off", LogHas("SKIP off emo=FART who=other"))
Slash("on")
ok("on", SpokenWindDB.on == true)

-- channel
Slash("ch dialog")
ok("ch Dialog", SpokenWindDB.ch == "Dialog")
plays = {}
now = now + 10
Emote(OTHER_FART, "Bob", BOB)
ok("plays on Dialog", plays[1] and plays[1].ch == "Dialog")
Slash("ch MASTER")
ok("ch Master (any case)", SpokenWindDB.ch == "Master")
Slash("ch loud")
ok("bad ch keeps Master", SpokenWindDB.ch == "Master")
ok("bad ch says options", prints[#prints]:find("master|sfx|dialog", 1, true))

-- cd input
Slash("cd 1.25")
ok("cd 1.3 (one decimal)", SpokenWindDB.cd == 1.3, SpokenWindDB.cd)
Slash("cd 999")
ok("cd max 30", SpokenWindDB.cd == 30)
Slash("cd -1")
ok("cd -1 refused", SpokenWindDB.cd == 30)
Slash("cd abc")
ok("cd abc refused", SpokenWindDB.cd == 30)

-- PlaySoundFile error never breaks the addon
local real = PlaySoundFile
PlaySoundFile = function() error("boom") end
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("play error logged", LogHas("ERR play"))
PlaySoundFile = real

-- status / help: terse (two short lines)
local before = #prints
Slash("")
ok("status = 2 lines", #prints - before == 2, #prints - before)
ok("status shows set", prints[before + 1] and prints[before + 1]:find("fart 1351", 1, true), prints[before + 1])
for n = before + 1, #prints do   -- the length the player sees: color codes are not shown
	local seen = prints[n]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	ok("line short " .. n, #seen <= 100, #seen)
end
Slash("reset")
ok("reset", SpokenWindDB.on and SpokenWindDB.ch == "SFX" and SpokenWindDB.self and SpokenWindDB.cd == 1
	and SpokenWindDB.wait == 150)
for _, l in ipairs(prints) do ok("prints tagged", l:find("Spoken Wind", 1, true) ~= nil, l) end

-- forms: real lines, names swapped out, tagged with the emote
ok("forms saved", #SpokenWindDB.forms >= 2, #SpokenWindDB.forms)
local seenMe = false
for _, f in ipairs(SpokenWindDB.forms) do
	ok("form tagged FART", f:find("^FART ") ~= nil, f)
	if f:find("Bob", 1, true) or f:find("Ann", 1, true) then ok("sender name hidden", false, f) end
	if f:find("<who>", 1, true) or f:find("You", 1, true) then seenMe = true end
end
ok("forms readable", seenMe)
ok("forms capped", #SpokenWindDB.forms <= 8)

-- secret values (newer clients): no error, no sound
issecretvalue = function(v) return v == "SECRET" end
plays = {}
now = now + 10
Emote("SECRET", "SECRET", "SECRET")
ok("secret: no sound, no error", #plays == 0 and not LogHas("ERR boom"))
Emote(OTHER_FART, "Bob", "SECRET")   -- secret guid: the name is the key
ok("secret guid: plays by name", #plays == 1)
issecretvalue = nil

-- logout summary
ev.scripts.OnEvent(ev, "PLAYER_LOGOUT")
ok("SUM line", LogHas("SUM seen=") and LogHas("hit=") and LogHas("played=") and LastLog():find("keys=%d+$"))

-- saved settings survive a reload; bad ones are fixed
local saved = SpokenWindDB
saved.ch, saved.cd, saved.self, saved.on = "Ambience", -3, false, "yes"
Load(saved)
ok("bad ch fixed", SpokenWindDB.ch == "SFX")
ok("bad cd fixed", SpokenWindDB.cd == 1)
ok("bad on fixed", SpokenWindDB.on == true)
ok("self kept", SpokenWindDB.self == false)
ok("log kept", #SpokenWindDB.log > 1)
saved.cd = 31
Load(saved)
ok("cd over max fixed", SpokenWindDB.cd == 1)
SpokenWindDB.self = true
-- one-time move: the old default 2 s -> 1 s (saves from 0.4.0 and before); runs once, so a later 2 stays
local function MoveLines()
	local c = 0
	for _, l in ipairs(SpokenWindDB.log) do if l:find("CD move 2->1", 1, true) then c = c + 1 end end
	return c
end
Load({ on = true, ch = "SFX", self = true, cd = 2, log = {} })
ok("cd move: old save 2 -> 1", SpokenWindDB.cd == 1 and SpokenWindDB.cdMove == true, SpokenWindDB.cd)
ok("cd move logged once", MoveLines() == 1, MoveLines())
SpokenWindDB.cd = 2   -- set by hand after the move
Load(SpokenWindDB)
ok("cd move: second load keeps a hand-set 2", SpokenWindDB.cd == 2, SpokenWindDB.cd)
ok("cd move: second load logs nothing", MoveLines() == 1, MoveLines())
Load({ on = true, ch = "SFX", self = true, cd = 5, log = {} })
ok("cd move: old save 5 stays 5", SpokenWindDB.cd == 5 and SpokenWindDB.cdMove == true and MoveLines() == 0,
	SpokenWindDB.cd)
Load({ cd = 2, cdMove = "x", log = {} })
ok("cd move: odd flag = not moved yet", SpokenWindDB.cd == 1 and SpokenWindDB.cdMove == true and MoveLines() == 1)
Load(saved)
ok("cd move: flag kept over loads", saved.cdMove == true and MoveLines() == 0)
SpokenWindDB.cd = 1

-- page fallbacks: no sub-pages / no vertical API / old client / nothing
for _, case in ipairs({ { "nosub", "canvas" }, { "canvas", "canvas" }, { "old", "canvas" }, { "none", "none" } }) do
	ev, ns = Load(SpokenWindDB, case[1])
	ok("fallback " .. case[1] .. " -> panel=" .. case[2], LastLog():find("panel=" .. case[2] .. " ", 1, true), LastLog())
	ok("fallback " .. case[1] .. " no ERR", not LastLog():find("ERR", 1, true))
	ok("fallback " .. case[1] .. " flog=none", LastLog():find(" flog=none ", 1, true), LastLog())
	ok("fallback " .. case[1] .. " ach=none", LastLog():find(" ach=none ", 1, true), LastLog())
	ok("fallback " .. case[1] .. " no page controls", ns.OptRefs().opt == nil and #reg.subs == 0)
	if case[2] == "canvas" then
		local f = reg.canvas[1]
		ok("fallback " .. case[1] .. " page named", f and f.name == "Spoken Wind")
		ok("fallback " .. case[1] .. " page text", f and f.strings[2] and f.strings[2].text:find("/wind", 1, true))
		ok("fallback " .. case[1] .. " no test (public)", f and f.strings[2] and not f.strings[2].text:find("test", 1, true))
		local hasLog = false
		for _, fs in ipairs(f and f.strings or {}) do if fs.text == ns.CHANGELOG[1].v then hasLog = true end end
		ok("fallback " .. case[1] .. " changelog on page", hasLog and LastLog():find(" log=text ", 1, true), LastLog())
		local low = 0
		for _, fs in ipairs(f and f.strings or {}) do if fs.y then low = math.min(low, fs.y) end end
		ok("fallback " .. case[1] .. " changelog fits", low >= -472 and low < -300, low)
		local fs = f and f.strings or {}
		ok("fallback " .. case[1] .. " credits last on the page", #fs > 6 and fs[#fs].text == ns.CREDITS.inspired
			and fs[#fs - 1].text == "Inspired by" and fs[#fs - 2].text == "|cffffffffBumm Farto|r \194\183 |cffffffffChrissy Walnutz|r"
			and fs[#fs - 3].text == "Testers" and fs[#fs - 4].text == "|cffffffffHals Dunngold|r" and fs[#fs - 5].text == "Author"
			and LastLog():find(" cred=text", 1, true), LastLog())
		ok("fallback " .. case[1] .. " Inspired by text wrapped, fits", fs[#fs].wrap == true and fs[#fs].width == 480
			and fs[#fs].x == 28 and fs[#fs - 1].x == 16 and fs[#fs].justify == "LEFT"
			and fs[#fs].y - fs[#fs]:GetStringHeight() >= -472, fs[#fs].y)
	else
		ok("fallback none log=none", LastLog():find(" log=none ", 1, true), LastLog())
		ok("fallback none cred=none", LastLog():find(" cred=none", 1, true), LastLog())
	end
	Slash("cd 4")
	ok("fallback " .. case[1] .. " /wind still sets", SpokenWindDB.cd == 4 and LastLog():find("OPT cd=4 by=slash", 1, true))
	plays = {}
	now = now + 10
	Emote(OTHER_FART, "Bob", BOB)
	ok("fallback " .. case[1] .. " still plays", #plays == 1)
	Slash("cd 2")
end

-- old-client text page, 600 testers: the credits are cut at 160 px, the changelog keeps the rest
preLogin = function(n)
	local t = {}
	for i = 1, 600 do t[i] = "T" .. i end
	n.CREDITS = { author = "A", testers = t, inspired = n.CREDITS.inspired }
end
ev, ns = Load(SpokenWindDB, "old")
preLogin = nil
;(function()
	local fs = reg.canvas[1] and reg.canvas[1].strings or {}
	local a
	for i, s in ipairs(fs) do if s.text == "Author" then a = i end end
	local want, wt, got = ns.CreditsLines(160), {}, {}
	for i, l in ipairs(want) do wt[i] = l[1] end
	for i = a or #fs + 1, #fs - 2 do got[#got + 1] = fs[i].text end
	ok("fallback 600 testers: credits = the 160 px cut", a ~= nil and table.concat(got, "|") == table.concat(wt, "|")
		and Px(want) <= 160 and want[#want][1]:find("^%+%d+ more$") ~= nil, #got .. " vs " .. #wt)
	local p = fs[#fs]
	ok("fallback 600 testers: then Inspired by + the text, it fits", p and p.text == ns.CREDITS.inspired and #p.text == 301
		and fs[#fs - 1].text == "Inspired by" and p.y - p:GetStringHeight() >= -472, p and p.y)
	local hasLog, low = false, 0
	for _, s in ipairs(fs) do
		if s.text == ns.CHANGELOG[1].v then hasLog = true end
		if s.y then low = math.min(low, s.y) end
	end
	ok("fallback 600 testers: changelog still there, page fits", hasLog and low >= -472, low)
end)()

-- the vertical API breaks: 0.8.0 does not use it
ev, ns = Load(SpokenWindDB, "error")
ok("vertical error: 0.8.0 pages anyway", LastLog():find("panel=look log=page flog=page ", 1, true) and #reg.subs == 3, LastLog())
-- a page build error: nothing registered from it, the text page instead
preLogin = function(n) n.Looks["sw-credits"].build = function() error("build broke") end end
ev, ns = Load(SpokenWindDB)
preLogin = nil
ok("page build error: the text page", LastLog():find("panel=canvas log=text flog=none ", 1, true) and #reg.subs == 0
	and #reg.cats == 1 and ns.OptRefs().opt == nil and not LastLog():find("ERR", 1, true), LastLog())
ok("page build error: kept for the log", type(ns.panelError) == "string" and ns.panelError:find("build broke", 1, true) ~= nil,
	tostring(ns.panelError))
Slash("cd 4")
ok("page build error: /wind still sets", SpokenWindDB.cd == 4)
Slash("cd 1")
-- a bind error after the refs are set: the refs go too, the text page instead
preLogin = function(n)
	local b = n.Looks["sw-options"].build
	n.Looks["sw-options"].build = function(...) local r = b(...) r.devTag = nil return r end
end
ev, ns = Load(SpokenWindDB)
preLogin = nil
ok("page bind error: refs cleared, the text page", ns.OptRefs().opt == nil and ns.OptRefs().cred == nil
	and ns.OptRefs().fo == nil and #reg.subs == 0 and LastLog():find("panel=canvas log=text flog=none ", 1, true)
	and not LastLog():find("ERR", 1, true), LastLog())
-- the main page does not register: the text page
preLogin = function() Settings.RegisterAddOnCategory = function() error("reg broke") end end
ev, ns = Load(SpokenWindDB)
preLogin = nil
ok("page register error: Lua error caught, no sub-pages", #reg.subs == 0 and ns.OptRefs().opt == nil
	and (LastLog():find("panel=err ", 1, true) or LastLog():find("panel=canvas ", 1, true)), LastLog())
-- one sub-page fails: that page err, the others come
ev, ns = Load(SpokenWindDB, "suberr")
ok("sub-page error: changelog err, the rest pages", LastLog():find("panel=look log=err flog=page ", 1, true)
	and LastLog():find(" cred=page", 1, true) and #reg.subs == 2 and reg.subs[1].name == "Fart log" and reg.subs[2].name == "Credits",
	LastLog())
SY.Click(SY.Opt().opt.pgLogC)
ok("sub-page error: its Pages button = ok=0", LastLog():find("OPT page=chg ok=0$"), LastLog())

-- ---------------------------------------------------------------- dev folder (never shipped)
-- Spoken_Wind_Dev sets SPOKEN_WIND_DEV after Spoken Wind's ADDON_LOADED. Only
-- then: the Test button on the page, /wind test, "test" in the help line.
if HAVE_DEV then
	local dtoc = assert(io.open(DEV_DIR .. "/Spoken_Wind_Dev.toc", "rb")):read("*a")
	local dfiles = {}
	for line in dtoc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line:match("%S") then dfiles[#dfiles + 1] = line:match("^%s*(.-)%s*$") end
	end
	ok("dev toc: own Look copy + 2 screens, then Dev.lua", table.concat(dfiles, ",")
		== "UI\\Look.lua,UI\\Parts.lua,UI\\sw-dev.lua,UI\\sw-dev-msgs.lua,Dev.lua", table.concat(dfiles, ","))
	ok("dev toc: loads after Spoken_Wind", dtoc:find("## Dependencies: Spoken_Wind\r?\n") ~= nil)
	ok("dev toc: same Interface", dtoc:match("## Interface: ([^\r\n]+)") == toc:match("## Interface: ([^\r\n]+)"))
	ok("dev toc: no saves", not dtoc:find("SavedVariables"))
end
ev, ns = Load(SpokenWindDB, "vertical", true)
ok("dev: BOOT dev=1", LastLog():find(" dev=1 set=%d+ "), LastLog())
local DO = ns.OptRefs().opt
SY.ShowPage(ns.OptRefs().fo)
ok("dev: the Dev rows shown (Dev tag + Test Play)", DO and DO.secDev.shown and DO.testR.shown and SY.Tx(DO.testPlay) == "Play"
	and SY.Tx(DO.devTag) == "Dev")
ok("dev: still no game setting objects", #reg.list == 0 and #reg.buttons == 0)
-- Test Play: plays (even when off), logs, one line
Slash("off")
plays, b = {}, #prints
local nf = #SpokenWindDB.farts
if DO then SY.Click(DO.testPlay) end
ok("dev: test not in fart log", #SpokenWindDB.farts == nf)
ok("dev: button plays", #plays == 1 and plays[1].path:find("\\Media\\fart\\", 1, true))
ok("dev: button logged", LastLog():find("TEST emo=FART snd=", 1, true), LastLog())
ok("dev: button one line", #prints == b + 1 and prints[b + 1] and prints[b + 1]:find("^|cff9fd8a8Spoken Wind|r #%d+ "), prints[b + 1])
-- /wind test n: plays sound n even when off
plays = {}
Slash("test 4")
ok("dev: test plays even when off", #plays == 1 and plays[1].path:find("fart\\04_trumpet", 1, true))
ok("dev: test prints name", prints[#prints]:find("#4 Trumpet", 1, true), prints[#prints])
ok("dev: test logged", LastLog():find("TEST emo=FART snd=4", 1, true), LastLog())
-- muted channel: test says so
willPlay = false
Slash("test")
ok("dev: muted test says no sound", prints[#prints]:find("no sound", 1, true), prints[#prints])
willPlay = true
b = #prints
Slash("")
ok("dev: help shows test", prints[b + 2] and prints[b + 2]:find("test [1-1351]", 1, true), prints[b + 2])
ok("dev: help shows ach test", prints[b + 2] and prints[b + 2]:find("ach test [1-39]", 1, true), prints[b + 2])
Slash("on")
-- dev + text-only page: help says test too
ev, ns = Load(SpokenWindDB, "canvas", true)
ok("dev canvas: help shows test", reg.canvas[1] and reg.canvas[1].strings[2].text:find("test [1-1351]", 1, true))
ok("dev canvas: BOOT dev=1", LastLog():find("panel=canvas .* dev=1 set=%d+ "), LastLog())

-- ---------------------------------------------------------------- fart log
-- Every fart that got a sound: newest first, totals today / all, 200 kept.
-- The page (UI\sw-fartlog): totals + one row per fart (when, who, #n name, voice) in pages, names without realm.
ev, ns = Load(nil)
local FL
for _, c in ipairs(reg.subs) do if c.name == "Fart log" then FL = c end end
local FP = ns.OptRefs()
local FR = FP.log
ok("fart log sub-page first", FL and FL.parent == reg.cat and reg.subs[1] == FL and reg.subs[2].name == "Changelog"
	and FL.frame == FP.fl)
ok("fart log BOOT", LastLog():find(" log=page flog=page farts=0 ", 1, true), LastLog())
local function Rows()   -- the shown rows, top down: "when|who|snd|voice"
	local t = {}
	for _, r in ipairs(SY.ListRows(FR.log)) do t[#t + 1] = table.concat(r, "|") end
	return t
end
local function Tot() return SY.Tx(FR.today) .. " " .. SY.Tx(FR.all) end
local function Show() SY.ShowPage(FP.fl) end
local function Hide() SY.HidePage(FP.fl) end
local function Vo(s)   -- the voice column of a sound
	if s.slot or s.tier == 7 then return "Shartifact" end
	if s.race then return ns.VOX.voices[s.race .. "_" .. s.body].name end
	return "Orig"
end
local function Row(r, when)   -- the page row of a saved fart
	local s = ns.EMOTES[r.e or "FART"].sounds[r.snd]
	return (when or os.date("%H:%M", r.t)) .. "|" .. r.who .. "|#" .. tostring(s.num or r.snd) .. "\194\160" .. s.name .. "|" .. Vo(s)
end
Show()
ok("fart log empty: totals 0, one None yet row", Tot() == "0 0" and table.concat(Rows(), "\n") == "||None yet|",
	Tot() .. " / " .. table.concat(Rows(), "\n"))
Hide()
local F = SpokenWindDB.farts
now = now + 100
Emote(FartBy("Bob-RealmA"), "Bob-RealmA", BOB)
ok("fart logged", #F == 1 and F[1].e == "FART" and F[1].snd == tonumber(LastPlay():match("PLAY .* snd=(%d+)")), LastPlay())
ok("fart log: realm cut", F[1] and F[1].who == "Bob", F[1] and F[1].who)
ok("fart log: time", F[1] and F[1].t == clock)
Emote("You fart loudly. Phew...what stinks?", ME, ME_GUID)
ok("fart log: own = you", F[2] and F[2].who == "you")
Emote(FartBy("Bob-RealmA"), "Bob-RealmA", BOB)
ok("fart log: cd skip not logged", #F == 2, #F)
Slash("off")
now = now + 10
Emote(ANN_FART, "Ann", ANN)
ok("fart log: off not logged", #F == 2, #F)
Slash("on")
Slash("self off")
Emote("You fart loudly. Phew...what stinks?", ME, ME_GUID)
ok("fart log: own off not logged", #F == 2, #F)
Slash("self on")
Show()
ok("fart log page", Tot() == "2 2" and table.concat(Rows(), "\n") == Row(F[2]) .. "\n" .. Row(F[1]), table.concat(Rows(), "\n"))
;(function()
	local rr = SY.ListRows(FR.log, true)
	local cy, cb = rr[1][2]:match("^|c(%x%x%x%x%x%x%x%x)"), rr[2][2]:match("^|c(%x%x%x%x%x%x%x%x)")
	ok("fart log: you in gold, others not", cy and cy:lower() == "ffffd100" and cb ~= cy, tostring(cy) .. " " .. tostring(cb))
end)()
-- open page: a new fart shows at once
now = now + 10
Emote(ANN_FART, "Ann", ANN)
ok("fart log live", Rows()[1] == Row(F[3]) and Tot() == "3 3", Rows()[1])
Hide()
-- next day: today starts at 0, older rows show the date
clock = clock + 86400
Show()
ok("new day: today 0", Tot() == "0 3", Tot())
ok("new day: old rows dated", Rows()[1] == Row(F[3], os.date("%m-%d %H:%M", F[3].t)), Rows()[1])
Hide()
now = now + 10
Emote(ANN_FART, "Ann", ANN)
ok("hidden page: not drawn", Tot() == "0 3", Tot())
Show()
ok("new day: counts", Tot() == "1 4", Tot())
ok("new day: new row time only", Rows()[1] == Row(F[4]) and Rows()[1]:find("^%d%d:%d%d|Ann|#"), Rows()[1])
Hide()
-- secret sender name (newer clients): logged as ?
issecretvalue = function(v) return v == "SECRET" end
now = now + 10
Emote(OTHER_FART, "SECRET", "Player-1-S1")
ok("secret name -> ?", F[#F].who == "?", F[#F].who)
issecretvalue = nil
-- 250 more: 200 kept, all counted; the page = 17 rows a page, the pager, no new frames
SpokenWindDB.cd = 0
SY.ShortLen(0.1)   -- 0.1 ms sounds: every fart plays
local pb = #prints
for n = 1, 250 do now = now + 0.01 Emote(OTHER_FART, "Bob", BOB) end
SY.ShortLen()
ok("fart log: farts print nothing", #prints == pb, #prints - pb)
ok("fart log capped 200", #SpokenWindDB.farts == 200, #SpokenWindDB.farts)
ok("fart log: all counts every fart", SpokenWindDB.stats.all == 255 and SpokenWindDB.stats.today == 252,
	SpokenWindDB.stats.all .. " " .. SpokenWindDB.stats.today)
Show()
local nf1 = #frames
local pg = Rows()
ok("fart log page: 17 rows (456 px / 26 px), pager 1/12", #pg == 17 and SY.Tx(FR.page) == "1/12", #pg .. " " .. SY.Tx(FR.page))
ok("fart log page: newest first", pg[1] == Row(F[200]) and pg[17] == Row(F[184]), pg[1])
ok("fart log page: totals with a comma past 999", (function()
	local s = SpokenWindDB.stats.all
	SpokenWindDB.stats.all = 12345
	Hide() Show()
	local r = SY.Tx(FR.all)
	SpokenWindDB.stats.all = s
	Hide() Show()
	return r == "12,345"
end)(), SY.Tx(FR.all))
SY.Click(FR.next)
ok("fart log page 2", Rows()[1] == Row(F[183]) and SY.Tx(FR.page) == "2/12", SY.Tx(FR.page))
now = now + 10
Emote(ANN_FART, "Ann", ANN)
ok("fart log: a new fart keeps page 2 (rows move down one)", SpokenWindDB.stats.all == 256 and SY.Tx(FR.page) == "2/12"
	and Rows()[1] == Row(F[183]), SpokenWindDB.stats.all .. " " .. SY.Tx(FR.page))
for _ = 1, 20 do SY.Click(FR.next) end
ok("fart log: last page 12 = 13 rows", SY.Tx(FR.page) == "12/12" and #Rows() == 13 and Rows()[13] == Row(F[1]), #Rows())
Hide() Show()
ok("fart log: shown again = page 1", SY.Tx(FR.page) == "1/12" and Rows()[1] == Row(F[200]), SY.Tx(FR.page))
ok("fart log: no new frames over redraws", #frames == nf1, #frames - nf1)
Hide()
-- the voice column: Orig (the old 14), a race voice, Artifact; a sound gone from the set = "#n ?"
;(function()
	local S = ns.EMOTES.FART.sounds
	local iPack, iArt
	for i, s in ipairs(S) do
		if not iPack and s.race and not s.slot and s.tier ~= 7 and s.q and s.q ~= (S[1].q or 1) then iPack = i end
		if not iArt and (s.slot or s.tier == 7) then iArt = i end
	end
	local saveF = SpokenWindDB.farts
	SpokenWindDB.farts = { { t = clock, e = "FART", who = "A", snd = 1 }, { t = clock, e = "FART", who = "B", snd = iPack },
		{ t = clock, e = "FART", who = "C", snd = iArt or 1 }, { t = clock, e = "FART", who = "D", snd = 99999 } }
	Show()
	local r = Rows()
	local hm = os.date("%H:%M", clock)
	ok("fart log voice: a gone sound = #n ?", r[1] == hm .. "|D|#99999\194\160?|", r[1])
	ok("fart log voice: Shartifact", iArt == nil or r[2] == Row(SpokenWindDB.farts[3]) and r[2]:find("|Shartifact$"), r[2])
	ok("fart log voice: a race voice (set number)", iPack and r[3] == Row(SpokenWindDB.farts[2])
		and r[3]:find("|#" .. S[iPack].num .. "\194\160", 1, true) and not r[3]:find("|Orig$"), r[3])
	ok("fart log voice: the old 14 = Orig", r[4] == hm .. "|A|#1\194\160" .. S[1].name .. "|Orig", r[4])
	local rr = SY.ListRows(FR.log, true)
	local qa, qb = rr[4][3]:match("|r|c(%x%x%x%x%x%x%x%x)"), rr[3][3]:match("|r|c(%x%x%x%x%x%x%x%x)")
	ok("fart log: the name in its quality color", qa and qb and qa ~= qb, tostring(qa) .. " " .. tostring(qb))
	Hide()
	SpokenWindDB.farts = saveF
end)()
SpokenWindDB.cd = 1
-- old or bad saves: bad rows dropped, over 200 cut to the newest, totals fixed
local rows = { "junk", { t = "x", who = "A", snd = 1 } }
for n = 1, 300 do rows[#rows + 1] = { t = CLOCK0 + n, who = "P", snd = 1 } end
rows[#rows + 1] = "junk"                          -- bad rows among the newest too
rows[#rows + 1] = { t = CLOCK0 + 999, who = 7, snd = 1 }
SpokenWindDB.farts, SpokenWindDB.stats = rows, "bad"
ev, ns = Load(SpokenWindDB)
local allGood = true
for _, r in ipairs(SpokenWindDB.farts) do if type(r) ~= "table" or type(r.who) ~= "string" then allGood = false end end
ok("bad rows dropped, newest 200 kept", allGood and #SpokenWindDB.farts == 200 and SpokenWindDB.farts[1].t == CLOCK0 + 101
	and SpokenWindDB.farts[200].t == CLOCK0 + 300, #SpokenWindDB.farts)
ok("bad stats fixed", type(SpokenWindDB.stats) == "table" and SpokenWindDB.stats.all == 200 and SpokenWindDB.stats.today == 0)
ok("BOOT farts=200", LastLog():find(" farts=200 ", 1, true), LastLog())
SpokenWindDB.stats.all = 9999
ev, ns = Load(SpokenWindDB)
ok("all kept over rows", SpokenWindDB.stats.all == 9999)
SpokenWindDB.stats.all = 0
ev, ns = Load(SpokenWindDB)
ok("all 0 stays 0", SpokenWindDB.stats.all == 0, SpokenWindDB.stats.all)
SpokenWindDB.stats.all = -5
ev, ns = Load(SpokenWindDB)
ok("all < 0 -> rows", SpokenWindDB.stats.all == 200, SpokenWindDB.stats.all)
SpokenWindDB.stats.all = 9999

-- ---------------------------------------------------------------- achievements
-- Classic: 15 rows, rarest first (= the icon sheet), + 1 secret. Social: 17 rows
-- (3 secret author rows, 3 soon rows). Every rule both ways. Earn = own toast
-- (looks like the friend toast; the game's BNToastFrame is only read)
-- + "ACH <id> toast=1". Own window: grey icon + grey ring = locked.
local function Fresh(dev)
	ev, ns = Load(nil, "vertical", dev)
	willPlay = true
end
local function Done() return SpokenWindDB.ach.done end
local OWN_FART = "You fart loudly. Phew...what stinks?"
Fresh()
local A = ns.ACH
local ids, qs, nms = {}, {}, {}
for _, r in ipairs(A) do ids[#ids + 1] = r.id qs[#qs + 1] = r.q nms[#nms + 1] = r.name end
ok("ach: 15 rows, sheet order, the secret row, then 17 social rows, then 5 collection rows", table.concat(ids, ",") ==
	"super,legend,orchestra,thousand,gas,penpals,cropduster,double,callback,machinegun,sbd,night,tuba,selfstarter,first,"
	.. "testsmell,shart,heard,packed,ovation,around,town,fame,fanclub,cult,household,insync,born,witness,everywind,"
	.. "labpartner,source,authornote,windbag,starter,collector,gasologist,pitch,complete", table.concat(ids, ","))
ok("ach: rarity = frame colors, secret common", table.concat(qs) == "544443333322222152342342343445444323445", table.concat(qs))
ok("ach: tabs", (function()
	for i, r in ipairs(A) do
		if r.tab ~= (i <= 17 and "classic" or i <= 34 and "social" or "collection") then return false end
	end
	return ns.ACH_TABS[1] == "classic" and ns.ACH_TABS[2] == "social" and ns.ACH_TABS[3] == "collection"
		and ns.ACH_TABS[4] == "board" and #ns.ACH_TABS == 4 and ns.ACH_MAIN.classic == 15 and ns.ACH_MAIN.social == 14 and ns.ACH_MAIN.collection == 5
end)())
ok("ach: Machine Gun says cd-blocked /fart count", A[10].id == "machinegun"
	and A[10].rule == "One person, 10 /fart in 10s (silent count)", A[10].rule)
ok("ach: secret rows = testsmell + shart + the 3 author rows", (function()
	local s = {}
	for _, r in ipairs(A) do if r.secret then s[#s + 1] = r.id end end
	return table.concat(s, ",") == "testsmell,shart,labpartner,source,authornote"
end)())
ok("ach: legend rows (leg) = the 3 legend rows, no Soon row left", (function()
	local s = {}
	for _, r in ipairs(A) do if r.leg then s[#s + 1] = r.id end if r.soon then return false end end
	return table.concat(s, ",") == "born,witness,everywind"
end)())
ok("ach: stat rows (stat, goal)", (function()
	local s = {}
	for _, r in ipairs(A) do if r.stat then s[#s + 1] = r.id .. "=" .. r.stat .. r.goal end end
	return table.concat(s, ",") == "heard=best1,packed=best5,ovation=best10,around=heard25,town=heard100,fame=heard500,"
		.. "fanclub=people5,cult=people25,household=people100,insync=sync10,windbag=own250"
end)())
ok("ach: names", table.concat(nms, ",") == "Super Legendary,Legend Has It,Full Orchestra,Thousand Winds,Gas Giant,"
	.. "Pen Pals,Crop Duster,Double Trouble,Call and Response,Machine Gun,Silent But Deadly,Night Shift,Tuba Tuesday,"
	.. "Self-Starter,First Wind,Test Farts Don't Smell,That wasn't a fart,Someone Heard That,Packed House,Standing Ovation,Word Gets Around,"
	.. "Talk of the Town,Wind of Fame,Fan Club,Cult Following,Household Name,In Sync,Born Legendary,Witness,"
	.. "Every Wind That Blows,Lab Partner,Straight From the Source,Author's Note,Windbag,Starter Pack,Collector,"
	.. "Gasologist,Perfect Pitch,The Complete Works", table.concat(nms, ","))
ok("ach: collection rows (dex = different sounds, dexVoice = a full voice)", (function()
	local s = {}
	for _, r in ipairs(A) do
		if r.dex or r.dexVoice then s[#s + 1] = r.id .. "=" .. (r.dex or "voice") end
	end
	return table.concat(s, ",") == "starter=10,collector=100,gasologist=500,pitch=voice,complete=1337"
end)())
local GAME_ICON = { starter = "INV_Misc_Bag_10", collector = "INV_Box_01", gasologist = "Spell_Nature_Cyclone",
	pitch = "INV_Misc_Drum_01", complete = "INV_Crown_01" }
for _, r in ipairs(A) do
	ok("ach rule terse " .. r.id, type(r.rule) == "string" and #r.rule <= 44 and not r.rule:find("[%.!]$"), r.rule)
	if r.id == "testsmell" or r.id == "shart" then
		ok("ach icon " .. r.id .. ": the game's question mark", ns.AchIcon(r) == "Interface\\Icons\\INV_Misc_QuestionMark")
	elseif r.tab == "collection" then   -- the game's own icons until the author draws them
		local fh = io.open(ADDON_DIR .. "/Media/ach/" .. r.id .. ".tga", "rb")
		if fh then fh:close() end
		ok("ach icon " .. r.id .. ": the game's icon, no art file", ns.AchIcon(r) == "Interface\\Icons\\" .. GAME_ICON[r.id]
			and fh == nil, ns.AchIcon(r))
	else
		local fh = io.open(ADDON_DIR .. "/Media/ach/" .. r.id .. ".tga", "rb")
		local h = fh and fh:read(18)
		local size = fh and fh:seek("end")
		if fh then fh:close() end
		ok("ach icon " .. r.id .. ": 128x128 32-bit TGA", h and #h == 18 and h:byte(3) == 2
			and h:byte(13) + h:byte(14) * 256 == 128 and h:byte(15) + h:byte(16) * 256 == 128 and h:byte(17) == 32
			and h:byte(18) == 8, h and h:byte(3))
		ok("ach icon " .. r.id .. " small", size and size <= 66000, size)
		ok("ach icon path " .. r.id, ns.AchIcon(r) == "Interface\\AddOns\\Spoken_Wind\\Media\\ach\\" .. r.id)
	end
end
local tga = io.open(ADDON_DIR .. "/Media/ach/testsmell.tga", "rb")
ok("ach: no art file for the test row", tga == nil)
if tga then tga:close() end
tga = io.open(ADDON_DIR .. "/Media/ach/ring.tga", "rb")
local rh = tga and tga:read(18)
if tga then tga:close() end
ok("ach: ring = 128x128 32-bit TGA", ns.ACH_RING == "Interface\\AddOns\\Spoken_Wind\\Media\\ach\\ring" and rh and #rh == 18
	and rh:byte(13) + rh:byte(14) * 256 == 128 and rh:byte(15) + rh:byte(16) * 256 == 128 and rh:byte(17) == 32)
ok("ach: quality colors (fallback)", ns.AchColor(5) == "|cffff8000" and ns.AchColor(4) == "|cffa335ee"
	and ns.AchColor(3) == "|cff0070dd" and ns.AchColor(2) == "|cff1eff00" and ns.AchColor(1) == "|cffffffff")
ITEM_QUALITY_COLORS = { [4] = { hex = "|cffaa00ff" }, [3] = { hex = "bad" } }
ok("ach: the game's quality color first, bad one ignored", ns.AchColor(4) == "|cffaa00ff" and ns.AchColor(3) == "|cff0070dd",
	ns.AchColor(4))
ITEM_QUALITY_COLORS = nil
ok("ach: BOOT", LastLog():find(" farts=0 ach=button done=0 rw=15 btn=1 sync=1/2 wait=150 tm=1 on=", 1, true), LastLog())
local function AchPage(tab)   -- head + the tiles of one tab, as the window draws them (ns.AchLines)
	local l = ns.AchLines(tab or "classic")
	local rows = {}
	for i, t in ipairs(l.tiles) do
		rows[i] = { id = t.id, name = (t.done and ns.AchColor(t.q) or "|cff9d9d9d") .. t.name .. "|r", rule = t.rule,
			stat = t.stat, grey = not t.done, icon = t.icon, cmd = t.cmd }
	end
	return l.head, rows, l
end
local Id = {}   -- find rows + tiles by id (the window sorts: earned first by rarity); also keeps spots between steps
function Id.row(rows, id)   -- the line of row id, and its spot
	for i, r in ipairs(rows) do if r.id == id then return r, i end end
	return {}
end
function Id.W()   -- the window refs (nil = not made), the shown tab body, Look.Tabs, the line of a node, pinned, glow id
	local w, bodies, T, lineOf, pinned, glow = ns.AchRefs()
	return w, w and T and bodies[T.Selected()], T, lineOf, pinned, glow
end
function Id.tiles()   -- the shown tiles of the shown tab, in order: { cell, line, icon, name, rule, stat, fill }
	local w, b, _, lineOf = Id.W()
	local out = {}
	if not (w and w.root.shown and b) then return out end
	local function Add(c, i, n, r, s, f)
		if c and c.shown then out[#out + 1] = { cell = c, line = lineOf[c], icon = i, name = n, rule = r, stat = s, fill = f } end
	end
	if b.cell1 then
		for k = 1, 5 do Add(b["cell" .. k], b["icon" .. k], b["name" .. k], b["rule" .. k], b["stat" .. k], b["fill" .. k]) end
	else
		for _, r in ipairs(b._swRows or {}) do
			for _, X in ipairs({ "A", "B" }) do
				Add(r["cell" .. X], r["icon" .. X], r["name" .. X], r["rule" .. X], r["stat" .. X], r["fill" .. X])
			end
		end
	end
	return out
end
function Id.tile(id)   -- the shown window tile of row id, and its spot
	for i, t in ipairs(Id.tiles()) do if t.line and t.line.id == id then return t, i end end
end
function Id.glow(t) return t ~= nil and t.cell._swGlow ~= nil and t.cell._swGlow.shown == true end
function Id.nglow()   -- glowing tiles, all tabs
	local _, bodies = ns.AchRefs()
	local n = 0
	for _, b in pairs(bodies or {}) do
		local cs = {}
		for k = 1, 5 do if b["cell" .. k] then cs[#cs + 1] = b["cell" .. k] end end
		for _, r in ipairs(b._swRows or {}) do
			if r.cellA then cs[#cs + 1] = r.cellA end
			if r.cellB then cs[#cs + 1] = r.cellB end
		end
		for _, c in ipairs(cs) do if c._swGlow and c._swGlow.shown then n = n + 1 end end
	end
	return n
end
function Id.tip()   -- the tip box: shown, title, "label=value|...", its refs
	local _, _, _, R = ns.BarRefs()
	if not R then return false, nil, "" end
	local t = {}
	for _, x in ipairs(R._swRows or {}) do t[#t + 1] = x[1] .. "=" .. x[2] end
	return R.root.shown == true, R.titleText.text, table.concat(t, "|"), R
end
function Id.tab(name) SY.Click((ns.AchRefs())["tab" .. name]) end   -- Classic, Social, Coll, Board
function Id.on(x) x.scripts.OnEnter(x) end   -- the mouse on a node
function Id.off(x) x.scripts.OnLeave(x) end
local function Near(vc, r, g, b)   -- a ring tint = these hex bytes
	return vc ~= nil and math.abs(vc[1] - r / 255) < 0.002 and math.abs(vc[2] - g / 255) < 0.002
		and math.abs(vc[3] - b / 255) < 0.002
end
;(function()   -- lines: what the window shows (head, tiles, progress, reward)
	local head, rows = AchPage()
	ok("ach lines: head", head == "Classic 0/15", head)
	ok("ach lines: 15 tiles, the secret row hidden", #rows == 15, #rows)
	local allGrey, inOrder = true, true
	for i, r in ipairs(rows) do
		if not r.grey then allGrey = false end
		if r.id ~= A[i].id or r.icon ~= ns.AchIcon(A[i]) or r.name ~= "|cff9d9d9d" .. A[i].name .. "|r" or r.rule ~= A[i].rule then
			inOrder = false
		end
	end
	ok("ach lines: all locked = grey", allGrey)
	ok("ach lines: rows in table order", inOrder, rows[1].name)
	ok("ach lines: progress", rows[3].stat == "0/14" and rows[4].stat == "0/1000" and rows[5].stat == "0/100"
		and rows[6].stat == "0/10" and rows[1].stat == "", rows[3].stat .. " " .. rows[5].stat)
	ok("ach lines: reward command", rows[1].cmd == "/superfart" and rows[15].cmd == "/firstwind", rows[1].cmd)
	local sh, sr, sl = AchPage("social")
	local st = {}
	for i, r in ipairs(sr) do st[i] = r.id .. "=" .. r.stat end
	ok("ach lines: social head", sh == "Social 0/14", sh)
	ok("ach lines: social: 14 tiles, secrets hidden, legend rows count (race set)", table.concat(st, ",") ==
		"heard=0/1,packed=0/5,ovation=0/10,around=0/25,town=0/100,fame=0/500,fanclub=0/5,cult=0/25,household=0/100,"
		.. "insync=0/10,born=,witness=,everywind=0/9,windbag=0/250", table.concat(st, ","))
	ok("ach lines: social rows have no reward", (function()
		for _, r in ipairs(sr) do if r.cmd then return false end end
		return true
	end)())
	ok("ach lines: stats strip", sl.stats == "Farts 0 · Heard 0 · People 0 · Legend 0", sl.stats)
	ok("ach lines: a bad tab = classic", ns.AchLines("bogus").tab == "classic" and ns.AchLines().tab == "classic")
end)()
;(function()   -- the window: own frame (AchWin.lua, the sw-ach screens): 4 tabs, tiles 2 a row, tips, pin, drag
	ok("ach window: not built at load", ns.AchRefs() == nil)
	b = #prints
	SY.Click(SY.Opt().opt.achOpen)   -- the Options page button
	local W, B = Id.W()
	local R = W and W.root
	ok("ach window: the Options button opens it", R ~= nil and R.shown and LastLog():find("ACH open tab=classic n=15$"), LastLog())
	ok("ach window: no chat line", #prints == b, prints[#prints])
	ok("ach window: own frame SpokenWindAch on UIParent, HIGH, toplevel, clamped, movable", R.name == "SpokenWindAch"
		and R.parent == UIParent and R.strata == "HIGH" and R.toplevel == true and R.clamped == true and R.movable == true,
		tostring(R.name) .. " " .. tostring(R.strata))
	ok("ach window: default spot: top center, 120 px down", R.point[1] == "TOP" and R.point[2] == UIParent
		and R.point[3] == "TOP" and R.point[5] == -120, tostring(R.point[1]) .. " " .. tostring(R.point[5]))
	ok("ach window: logo = the First Wind icon, total 0/34", W.logo.path == ns.AchIcon(ns.AchRow("first"))
		and W.totalText.text == "0/34", W.totalText.text)
	ok("ach window: tab texts", W.tabClassicText.text == "Classic 0/15" and W.tabSocialText.text == "Social 0/14"
		and W.tabCollText.text == ns.AchTabText("collection") and W.tabBoardText.text == "Board", W.tabClassicText.text)
	ok("ach window: Classic tab selected", SY.State(W.tabClassic) == "sel" and SY.State(W.tabSocial) ~= "sel",
		SY.State(W.tabClassic))
	ok("ach window: classic strip: farts, rewards, secret tag", B.farts.text == "0" and B.rew.text == "0/" .. #ns.REWARDS
		and B.secretText.text == "Secret 0/1" and SY.State(B.secret) == "base", B.rew.text .. " " .. B.secretText.text)
	local TL = Id.tiles()
	ok("ach window: 16 tiles (15 + a ??? for the secret row), 2 a row", #TL == 16 and #B._swRows == 8, #TL)
	local grey, inOrder = true, true
	for i = 1, 15 do
		local t = TL[i]
		if SY.State(t.cell) ~= "off" or not t.icon.desat or t.name.text ~= "|cff9d9d9d" .. A[i].name .. "|r" then grey = false end
		if t.line.id ~= A[i].id or t.icon.path ~= ns.AchIcon(A[i]) or t.rule.text ~= A[i].rule then inOrder = false end
	end
	ok("ach window: locked = off state, grey icon, grey name", grey, TL[1].name.text)
	ok("ach window: tiles in table order (icon, rule)", inOrder, TL[1].line.id)
	ok("ach window: ??? tile for Shart (secret, not earned)", TL[16].line.id == "shart" and TL[16].line.place
		and TL[16].name.text == "|cff9d9d9d???|r" and TL[16].icon.path == "Interface\\Icons\\INV_Misc_QuestionMark",
		TL[16].name.text)
	ok("ach window: progress text + no bar at 0", TL[3].stat.text == "|cff9d9d9d0/14|r" and not TL[3].fill.shown
		and TL[1].stat.text == "", TL[3].stat.text)
	-- hover: the tip box (title, rows)
	Id.on(TL[1].cell)
	local sh, title, rows, TR = Id.tip()
	ok("ach tip: name grey, rule, tier, reward, click", sh and title == "|cff9d9d9dSuper Legendary|r"
		and rows:find("^Rule=Hear the super legendary fart|Tier=|c%x+%a[%a ]*|r|Reward=|cff9d9d9d/superfart|r|Click=|cff9d9d9dPin|r$"),
		tostring(title) .. " " .. rows)
	ok("ach tip: own frame, tooltip strata", TR.root.parent == UIParent and TR.root.strata == "TOOLTIP", TR.root.strata)
	Id.on(TL[3].cell)
	sh, title, rows = Id.tip()
	ok("ach tip: progress row", rows:find("|Progress=0/14|Reward=|cff9d9d9d/orchestra|r|", 1, true) ~= nil, rows)
	Id.off(TL[3].cell)
	ok("ach tip: hides on leave", not (Id.tip()))
	-- click = pin (the tip stays), right click does nothing, a click again = unpin
	b = #prints
	SY.Click(TL[1].cell)
	sh, title, rows = Id.tip()
	ok("ach pin: a click pins the tip", sh and select(5, Id.W()) == TL[1].cell and rows:find("Click=|cff9d9d9dUnpin|r", 1, true)
		and #prints == b, rows)
	Id.on(TL[3].cell)
	ok("ach pin: an other tile shows its own tip", select(2, Id.tip()) == "|cff9d9d9dFull Orchestra|r")
	Id.off(TL[3].cell)
	ok("ach pin: leave = the pinned tip again", select(2, Id.tip()) == "|cff9d9d9dSuper Legendary|r" and (Id.tip()))
	SY.Click(TL[3].cell, "RightButton")
	ok("ach pin: right click does nothing", select(5, Id.W()) == TL[1].cell)
	SY.Click(TL[1].cell)
	Id.off(TL[1].cell)
	ok("ach pin: a click again unpins, leave hides it", select(5, Id.W()) == nil and not (Id.tip()))
	-- tabs
	Id.on(TL[1].cell)
	Id.tab("Social")
	local _, S = Id.W()
	TL = Id.tiles()
	ok("ach tab: Social: 17 tiles (14 + 3 ???), tip closed", #TL == 17 and #S._swRows == 9 and not (Id.tip())
		and TL[1].line.id == "heard" and TL[1].icon.path == ns.AchIcon(ns.AchRow("heard")), #TL)
	ok("ach tab: Social selected", SY.State(W.tabSocial) == "sel" and SY.State(W.tabClassic) ~= "sel")
	ok("ach tab: social strip", S.heard.text == "0" and S.people.text == "0" and S.best.text == "0" and S.born.text == "0"
		and S.wit.text == "0" and S.swnText.text == "SW players met 0", S.swnText.text)
	Id.on(TL[11].cell)
	sh, title, rows = Id.tip()
	ok("ach tip: legend row: no progress, no reward", title == "|cff9d9d9dBorn Legendary|r"
		and rows:find("^Rule=Roll your own legendary fart|Tier=|c%x+%a[%a ]*|r|Click=|cff9d9d9dPin|r$"), rows)
	Id.off(TL[11].cell)
	Id.on(TL[15].cell)
	sh, title, rows = Id.tip()
	ok("ach tip: ??? tile = Secret", TL[15].line.place and title == "|cff9d9d9d???|r" and rows == "Rule=Secret|Click=|cff9d9d9dPin|r",
		rows)
	Id.off(TL[15].cell)
	local nT = #frames
	Id.tab("Classic")
	Id.tab("Social")
	ns.AchOpen()
	ok("ach window: tabs + reopen make no new frames", #frames == nT, #frames - nT)
	-- no keys at all (gamepad play)
	ok("ach window: never takes keys", R.scripts.OnKeyDown == nil and R.scripts.OnKeyUp == nil
		and R.scripts.OnGamePadButtonDown == nil and R.kb == nil and R.prop == nil and ns.Look.hooks.esc == nil)
	ok("ach window: not in UISpecialFrames", (function()
		for _, n in ipairs(UISpecialFrames or {}) do if n == "SpokenWindAch" then return false end end
		return true
	end)())
	Id.on(Id.tiles()[1].cell)
	SY.Click(W.close)
	ok("ach window: X closes, the tip closes too", not R.shown and not (Id.tip()))
	-- /wind ach [tab]: the last tab kept
	b = #prints
	Slash("ach")
	ok("/wind ach: opens the last tab", R.shown and LastLog():find("ACH open tab=social n=14$") and #prints == b, LastLog())
	Slash("ach classic")
	ok("/wind ach classic", R.shown and SY.State(W.tabClassic) == "sel" and LastLog():find("ACH open tab=classic n=15$"), LastLog())
	-- the head buttons: ? = the hello note, Options = the game's Options page, Rewards = the popup
	SY.Click(W.help)
	local HL = select(5, ns.BarRefs())
	ok("ach ?: the hello note", HL and HL.root.shown and LastLog():find("HELLO by=ach$"), LastLog())
	HL.root:Hide()
	SY.Click(W.options)
	ok("ach Options: opens the game's Options on our page", reg.opened == 77 and LastLog():find("OPT open by=ach ok=1$"), LastLog())
	ok("ach Rewards: shown with the bar", W.rewards.shown)
	SY.Click(W.rewards)
	local _, POP = ns.BarRefs()
	ok("ach Rewards: opens the rewards popup", POP and POP.root.shown and R.shown)
	-- the head logo (0.8.1 fix: live 0.8.0 showed a flat gold box on the rewards popup + hello note):
	-- every UI screen with a logo ref, built, shows the First Wind icon in white
	do
		local tocS = assert(io.open(ADDON_DIR .. "/Spoken_Wind.toc", "rb")):read("*a")
		local built = { ["sw-ach"] = W, ["sw-hello"] = HL, ["sw-rewards"] = POP }
		local ICON1 = ns.AchIcon(ns.AchRow("first"))
		local ids, good, why = {}, true, {}
		for line in tocS:gmatch("[^\r\n]+") do
			local path, id = line:match("^%s*(UI[\\/](sw%-[%w%-]+)%.lua)%s*$")
			if path then
				local src = assert(io.open(ADDON_DIR .. "/" .. path:gsub("\\", "/"), "rb")):read("*a")
				if src:find('refs["logo"]', 1, true) then
					ids[#ids + 1] = id
					local lg = built[id] and built[id].logo
					local vc = lg and lg.vc
					if not (lg and lg.path == ICON1 and vc and vc[1] == 1 and vc[2] == 1 and vc[3] == 1) then
						good = false
						why[#why + 1] = id .. "=" .. tostring(lg and lg.path)
					end
				end
			end
		end
		table.sort(ids)
		ok("head logo: every screen with a logo (ach, hello, rewards) = the First Wind icon, white, not the gold box",
			good and table.concat(ids, ",") == "sw-ach,sw-hello,sw-rewards", table.concat(ids, ",") .. " " .. table.concat(why, " "))
		local tga = io.open(ADDON_DIR .. "/Media/ach/first.tga", "rb")
		ok("head logo: the icon file is in the addon (Media/ach/first.tga)", tga ~= nil and ICON1 == "Interface\\AddOns\\Spoken_Wind\\Media\\ach\\first")
		if tga then tga:close() end
	end
	SY.Click(W.rewards)
	ok("ach Rewards: again = closed", not POP.root.shown)
	reg.byVar.SpokenWind_rwbtn:SetValue(false)
	ns.AchRedraw()
	ok("ach Rewards: no bar = no button", not W.rewards.shown)
	reg.byVar.SpokenWind_rwbtn:SetValue(true)
	ns.AchRedraw()
	ok("ach Rewards: bar back = button back", W.rewards.shown)
	SY.Click(W.close)
	ok("ach window: X closes", not R.shown)
	-- the bar's achievements button: left = the window, right = the rewards popup
	local RB = (ns.BarRefs()).ach
	SY.Click(RB)
	ok("achievements button: left click opens the window", R.shown)
	SY.Click(RB)
	ok("achievements button: left click again closes it", not R.shown)
	SY.Click(RB, "RightButton")
	ok("achievements button: right click = the rewards popup, not the window", POP.root.shown and not R.shown)
	SY.Click(RB, "RightButton")
	ok("achievements button: right click again closes the popup", not POP.root.shown)
	-- combat: closes it; no open, no tip, no pin, no drag in combat
	ns.AchOpen()
	R.scripts.OnEvent(R, "PLAYER_REGEN_DISABLED")
	ok("ach combat: closes the window", not R.shown and R.events.PLAYER_REGEN_DISABLED == true)
	combat = true
	b = #prints
	ok("ach combat: no open", ns.AchOpen() == false and not R.shown)
	Slash("ach")
	ok("/wind ach in combat: one line, no window", not R.shown and #prints == b + 1
		and prints[b + 1]:find("not in combat", 1, true), prints[b + 1])
	R:Show()
	TL = Id.tiles()
	Id.on(TL[1].cell)
	SY.Click(TL[1].cell)
	ok("ach combat: no tip, no pin", not (Id.tip()) and select(5, Id.W()) == nil)
	R.left, R.top = 50, 60
	W.head.scripts.OnDragStart(W.head)
	ok("ach combat: no drag", not R.moving)
	SY.Click(W.options)
	ok("ach combat: Options does nothing", not LastLog():find("OPT open"), LastLog())
	combat = false
	Id.off(TL[1].cell)
	R:Hide()
	-- drag by the head: moves, the spot is saved (its top left), kept over a reload
	ns.AchOpen()
	W.head.scripts.OnDragStart(W.head)
	ok("ach drag: moves by the head", R.moving == true and W.head.drag == "LeftButton")
	R.left, R.top = 300.4, 700.6
	W.head.scripts.OnDragStop(W.head)
	ok("ach drag: spot saved", not R.moving and SpokenWindDB.achpos.x == 300 and SpokenWindDB.achpos.y == 701
		and R.point[1] == "TOPLEFT" and R.point[2] == UIParent and R.point[3] == "BOTTOMLEFT" and R.point[4] == 300
		and R.point[5] == 701, R.point[1])
	R:Hide()
	ev, ns = Load(SpokenWindDB)
	ns.AchOpen()
	R = Id.W().root
	ok("ach drag: spot kept over a reload", R.point[1] == "TOPLEFT" and R.point[4] == 300 and R.point[5] == 701, R.point[4])
	R:Hide()
	SpokenWindDB.achpos = { x = "a", y = 5 }
	ev, ns = Load(SpokenWindDB)
	ns.AchOpen()
	R = Id.W().root
	ok("ach drag: bad spot -> default", SpokenWindDB.achpos == nil and R.point[1] == "TOP", R.point[1])
	R:Hide()
	ok("ach window: Toggle", ns.AchToggle() == true and R.shown and ns.AchToggle() == false and not R.shown)
end)()
Fresh()
ok("ach: the login frames, no toast yet", #frames == SY.nLogin and ns.ToastFrame() == nil, #frames - SY.nLogin)

-- first fart: First Wind, own toast at the game toast's spot
plays, b = {}, #prints
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("first fart -> First Wind", Done().first == clock and LogHas("ACH first toast=1"), LastLog())
local T = ns.ToastFrame()
local TR = ns.ToastRefs()   -- 0.8.0: the sw-toast refs (T = TR.root)
ok("toast: own frame (root + 2 rows), made on the first earn", T and TR and TR.root == T and #frames == SY.nLogin + 3
	and frames[#frames - 2] == T and frames[#frames - 1].parent == T, #frames - SY.nLogin)
ok("toast: sw-toast on UIParent, named, 360 x 84", T and T.parent == UIParent and T.name == "SpokenWindToast"
	and T.w == 360 and T.h == 84, T and (tostring(T.w) .. "x" .. tostring(T.h)))
ok("toast: TOOLTIP strata, clamped", T and T.strata == "TOOLTIP" and T.clamped == true, T and T.strata)
ok("toast: the row's icon, 52 px", TR.icon.path == ns.AchIcon(A[15]) and TR.icon.width == 52 and TR.icon.height == 52,
	TR.icon.path .. " " .. tostring(TR.icon.width))
ok("toast: 'Achievement' + the reward command", TR.kind.text == "Achievement" and TR.cmd.text == "/firstwind", TR.cmd.text)
ok("toast: the name in its quality color, the rule under it", TR.name.text == "|cff1eff00First Wind|r"
	and TR.rule.text == "Hear a fart", TR.name.text)
ok("toast: no game art, no backdrop", T.backdrop == nil and not LogHas("TOAST art="))
ok("toast: starts 24 px low + clear, on the bar", T.shown and T.alpha == 0 and T.point[1] == "BOTTOMLEFT"
	and T.point[2] == ns.BarRefs().root and T.point[3] == "TOPLEFT" and T.point[4] == 0 and T.point[5] == -16, T.point[5])
ok("toast: the game's toast sound, SFX, once", #TS.snd == 1 and TS.snd[1].kit == 18019 and TS.snd[1].ch == "SFX"
	and LogHas("TOAST id=first sound=1"), #TS.snd)
local function Tick(dt) now = now + (dt or 0) T.scripts.OnUpdate(T, dt or 0) end
Tick(0.125)
ok("toast: slides + fades in", math.abs(T.alpha - 0.5) < 0.01 and T.point[5] == -4, T.alpha .. " " .. T.point[5])
Tick(0.15)
ok("toast: 8 px above the bar", T.point[2] == ns.BarRefs().root and T.point[5] == 8 and T.alpha == 1, T.point[5])
ok("toast: mouse on (out of combat)", T.mouse == true)
ok("toast: no chat line", #prints == b, prints[#prints])
ok("toast: no key or pad scripts", T.scripts.OnKeyDown == nil and T.scripts.OnGamePadButtonDown == nil)
Tick(0.8)
ok("toast: holds full, in place", T.shown and T.alpha == 1 and T.point[5] == 8, T.alpha)
-- 6 s, then a 0.5 s fade, then gone
Tick(4.8)
ok("toast: 6 s full", T.shown and T.alpha == 1, T.alpha)
Tick(0.375)
ok("toast: then fades", T.shown and math.abs(T.alpha - 0.5) < 0.01, T.alpha)
Tick(0.3)
ok("toast: gone after 6.5 s", not T.shown)
local h15 = Id.row(select(2, AchPage()), "first")
ok("ach sort: the one earned row is first", select(2, Id.row(select(2, AchPage()), "first")) == 1)
ok("ach lines: done = color + date", not h15.grey and h15.stat == "Done " .. os.date("%m-%d", clock)
	and h15.name == "|cff1eff00First Wind|r", h15.stat)
;(function()   -- the window shows it: base state, color icon, color name, the date, a full bar, the tip
	ns.AchOpen("classic")
	local D = (os.date("%m-%d", clock):gsub("%-", "%%-"))
	local TL = Id.tiles()
	local c = TL[1]
	ok("ach window: done tile = base state, color icon, color name, date, full bar", c.line.id == "first"
		and SY.State(c.cell) == "base" and c.icon.desat == false and c.name.text == "|cff1eff00First Wind|r"
		and c.stat.text:find("^|c%x+" .. D .. "|r$") and c.fill.shown and c.fill:GetWidth() == 76
		and TL[2].icon.desat == true and TL[15].icon.desat == true, c.stat.text .. " " .. tostring(c.fill:GetWidth()))
	ok("ach window: total + tab count", Id.W().totalText.text == "1/34" and Id.W().tabClassicText.text == "Classic 1/15",
		Id.W().totalText.text)
	Id.on(c.cell)
	local _, title, rows = Id.tip()
	ok("ach tip: done = the date, the reward gold", title == "|cff1eff00First Wind|r"
		and rows:find("|Done=" .. D .. "|Reward=|c%x+/firstwind|r|Click=") ~= nil, rows)
	Id.off(c.cell)
	Id.W().root:Hide()
end)()

-- two at once (own /fart at night): a queue; a click shows the next one
clock = os.time({ year = 2026, month = 11, day = 22, hour = 2, min = 0, sec = 0 })
ns.AchOpen("classic")
Id.nightAt = select(2, Id.tile("night"))
now = now + 10
Emote(OWN_FART, ME, ME_GUID)
ok("night + own fart: 2 earned", Done().night and Done().selfstarter)
ok("own fart alone: no Call and Response", not Done().callback)
ok("ach window: redraws at once when open", Id.W().tabClassicText.text == "Classic 3/15" and Id.W().totalText.text == "3/34"
	and Id.tiles()[1].icon.desat == false, Id.W().tabClassicText.text)
ok("ach sort: a fresh earn moves the tile up (13 -> 1); same rarity = list order", Id.nightAt == 13
	and select(2, Id.tile("night")) == 1 and select(2, Id.tile("selfstarter")) == 2 and select(2, Id.tile("first")) == 3, Id.nightAt)
Id.W().root:Hide()
ok("toast queue: first one shows", T.shown and TR.name.text == "|cff1eff00Night Shift|r" and TR.cmd.text == "/moontoot",
	TR.name.text)
T.scripts.OnMouseUp(T, "LeftButton")
ok("toast click: next one, its own text", T.shown and TR.name.text == "|cff1eff00Self-Starter|r" and TR.cmd.text == "/kickstart"
	and TR.rule.text == ns.AchRow("selfstarter").rule and TR.icon.path == ns.AchIcon(ns.AchRow("selfstarter")), TR.name.text)
ok("toast: 2 back to back = 1 sound", LogHas("TOAST id=night sound=1") and LogHas("TOAST id=selfstarter sound=0"))
T.scripts.OnMouseUp(T, "LeftButton")
ok("toast click: hides at the end", not T.shown)
;(function()   -- a left click: the window on the row's tab, its tile glowing (a Classic id)
	local t0 = now   -- the glow steps move the clock; put it back for Call and Response
	local W = Id.W()
	local R = W.root
	local g = Id.tile("selfstarter")
	local G = g and g.cell._swGlow
	ok("toast click: opens Classic, the clicked row glows (one tile)", R.shown and SY.State(W.tabClassic) == "sel"
		and LogHas("TOAST click id=night tab=classic glow=1") and LogHas("TOAST click id=selfstarter tab=classic glow=1")
		and Id.glow(g) and Id.nglow() == 1, LastLog())
	ok("toast glow: quality color, additive, centered on the icon, 1.7 x the icon", G and Near(G.vc, 0x1e, 0xff, 0x00)
		and G.blend == "ADD" and G.path == "Interface\\Buttons\\UI-ActionButton-Border" and G.w == G.h
		and math.abs(G.w - g.icon:GetWidth() * 1.7) < 0.01 and G.x == 0 and G.y == 0, G and tostring(G.w))
	now = now + 0.6 R.scripts.OnUpdate(R, 0.6)
	local dim = G.alpha
	now = now + 0.6 R.scripts.OnUpdate(R, 0.6)
	ok("toast glow: pulses (dim, bright)", math.abs(dim - 0.4) < 0.01 and math.abs(G.alpha - 1) < 0.01 and G.shown, dim)
	now = now + 3.6 R.scripts.OnUpdate(R, 3.6)
	ok("toast glow: still on before 5 s", G.shown and R.scripts.OnUpdate ~= nil)
	now = now + 0.3 R.scripts.OnUpdate(R, 0.3)
	ok("toast glow: off after 5 s, no OnUpdate left", not G.shown and R.scripts.OnUpdate == nil and Id.nglow() == 0)
	ok("glow: a locked tile glows too", ns.AchGlow("super") == true and Id.glow(Id.tile("super")))
	ok("glow: one tile at a time", ns.AchGlow("first") == true and not Id.glow(Id.tile("super"))
		and Id.glow(Id.tile("first")) and Id.nglow() == 1)
	Id.tab("Social")
	local offT = Id.nglow()
	Id.tab("Classic")
	ok("glow: an other tab hides it, back = it glows again", offT == 0 and Id.glow(Id.tile("first")) and Id.nglow() == 1, offT)
	Id.on(Id.tile("night").cell)
	ok("glow: the mouse on an other tile keeps it", Id.glow(Id.tile("first")))
	Id.off(Id.tile("night").cell)
	Id.on(Id.tile("first").cell)
	ok("glow: the mouse on the glowing tile ends it, the tip shows", not Id.glow(Id.tile("first"))
		and R.scripts.OnUpdate == nil and (Id.tip()))
	Id.off(Id.tile("first").cell)
	ns.AchGlow("first")
	ok("glow: a row with no tile on this tab = no glow; the old glow stops", ns.AchGlow("fame") == false
		and Id.nglow() == 0 and R.scripts.OnUpdate == nil)
	ns.AchOpen("social")
	ok("glow: a tile of an other tab (hidden) never glows", ns.AchGlow("first") == false and Id.nglow() == 0)
	ns.AchOpen("classic")
	ns.AchGlow("first")
	R:Hide()
	ok("glow: the window closes = off", Id.nglow() == 0 and R.scripts.OnUpdate == nil and ns.AchGlow("first") == false)
	now = t0
end)()
-- Call and Response: someone else 5 s after your /fart
now = now + 5
ns.AchOpen("classic")
ns.AchGlow("first")
Id.first0 = select(2, Id.tile("first"))
Emote(OTHER_FART, "Bob", BOB)
ok("Call and Response: 5 s after yours", Done().callback ~= nil)
;(function()
	local g, at = Id.tile("first")
	ok("ach sort: an earn while open moves rows; the glow lands on its row's new spot", Id.first0 == 3 and at and at > 3
		and select(2, Id.tile("callback")) < at and Id.glow(g) and Id.nglow() == 1 and not Id.glow(Id.tiles()[3]), at)
	Id.W().root:Hide()
end)()
while T.shown do T.scripts.OnMouseUp(T) end   -- the seed pick may earn one more: clear the queue
;(function()   -- a bar never runs past its tile (have > goal on a row not done yet)
	local real, id = ns.AchLines, nil
	ns.AchLines = function(...)
		local L = real(...)
		for i, l in ipairs(L.tiles or {}) do
			if not id and not l.done and not l.place and (l.goal or 0) > 0 then
				local c = {}
				for k, v in pairs(l) do c[k] = v end
				c.have = c.goal * 3
				L.tiles[i], id = c, c.id
			end
		end
		return L
	end
	ns.AchOpen("social")
	ns.AchLines = real
	local tl = id and Id.tile(id)
	ok("ach bar: 3 x the goal = the full bar (76 px), no more", tl ~= nil and tl.fill.shown and tl.fill:GetWidth() == 76,
		tl and tl.fill:GetWidth())
	Id.W().root:Hide()
end)()

-- bar off: above the game toast while it is up, its scale, else above the chat, else fixed
reg.byVar.SpokenWind_rwbtn:SetValue(false)
local function Pop(i) ns.Toast(A[i]) Tick(0.3) local pt = T.point T.scripts.OnMouseUp(T) return pt end
bnState.shown = true
local pt = Pop(1)
ok("toast: bar off = above the shown game toast", pt[2] == UIParent and pt[4] == 30 and pt[5] == 264, pt[5])
bnState.shown, bnState.scale = false, 2
pt = Pop(1)
ok("toast: game toast scale", pt[4] == 60 and pt[5] == 400, pt[4])
bnState.scale, bnState.left = 1, nil
pt = Pop(1)
ok("toast: game toast not placed -> above the chat", pt[4] == 32 and pt[5] == 340, pt[5])
local saveBN, saveCF = BNToastFrame, ChatFrame1
BNToastFrame, ChatFrame1 = nil, nil
pt = Pop(1)
ok("toast: no game toast, no chat -> fixed spot", pt[4] == 20 and pt[5] == 240, pt[4])
BNToastFrame, ChatFrame1 = saveBN, saveCF
ok("toast: the game toast was read", bnState.reads > 0)
reg.byVar.SpokenWind_rwbtn:SetValue(true)
;(function()   -- the rewards popup open over the bar: the toast sits on it; below the bar or closed = on the bar
	local bar = ns.BarRefs()
	SY.Click(bar.ach, "RightButton")
	local _, rw = ns.BarRefs()
	local p = Pop(1)
	ok("toast: above the open rewards popup", rw and rw.root.shown and p[2] == rw.root and p[3] == "TOPLEFT" and p[5] == 8,
		p[2] == bar.root and "bar" or tostring(p[2]))
	SY.Click(bar.ach, "RightButton")
	p = Pop(1)
	ok("toast: popup closed (still placed over the bar) = on the bar", not rw.root.shown
		and rw.root:GetPoint(1) == "BOTTOMLEFT" and p[2] == bar.root and p[5] == 8, tostring(p[2]))
	SY.Click(bar.ach, "RightButton")
	rw.root:ClearAllPoints()
	rw.root:SetPoint("TOPLEFT", bar.root, "BOTTOMLEFT", 0, -4)
	p = Pop(1)
	ok("toast: popup below the bar = on the bar", rw.root.shown and p[2] == bar.root, tostring(p[2]))
	SY.Click(bar.ach, "RightButton")
	ok("toast: the popup closed again", not rw.root.shown)
end)()
-- combat: shows, but takes no mouse
combat = true
ns.Toast(A[2])
ok("combat: toast shows, no mouse", T.shown and T.mouse == false)
T.scripts.OnEvent(T, "PLAYER_REGEN_ENABLED")
ok("combat end: mouse back", T.mouse == true)
T.scripts.OnEvent(T, "PLAYER_REGEN_DISABLED")
ok("combat start: mouse off", T.mouse == false)
ok("combat events", T.events.PLAYER_REGEN_DISABLED and T.events.PLAYER_REGEN_ENABLED)
combat = false
T.scripts.OnMouseUp(T)
-- queue capped
for _ = 1, 41 do ns.Toast(A[1]) end   -- 1 shows, 40 wait
ok("toast queue capped at 40 (more than all rows)", ns.Toast(A[1]) == false
	and #ns.ACH < 40)

-- 0.6.2.1: earned first by rarity, toast click (tab + glow), combat, hover holds the fade, hidden = no mouse
while T.shown do T.scripts.OnMouseUp(T) end
ok("toast: hidden = no mouse (never blocks a click)", not T.shown and T.mouse == false)
T.scripts.OnEvent(T, "PLAYER_REGEN_ENABLED")
ok("toast: combat ends while hidden = still no mouse", T.mouse == false)
;(function()   -- sort: a mix of earned rarities + locked, both tabs
	local save = SpokenWindDB.ach.done
	local function Want(tab, done)   -- by buckets: q 5 down to 0 in list order, then the locked ones in list order
		local w = {}
		for q = 5, 0, -1 do
			for _, r in ipairs(ns.ACH) do if r.tab == tab and r.q == q and done[r.id] then w[#w + 1] = r.id end end
		end
		for _, r in ipairs(ns.ACH) do if r.tab == tab and not r.secret and not done[r.id] then w[#w + 1] = r.id end end
		return table.concat(w, " ")
	end
	local function Got(tab)
		local g = {}
		for i, r in ipairs(select(2, AchPage(tab))) do g[i] = r.id end
		return table.concat(g, " ")
	end
	SpokenWindDB.ach.done = { first = 1, gas = 2, sbd = 3, super = 4, double = 5, legend = 6 }
	local got = Got("classic")
	ok("ach sort: Classic = legendary, epics, rare, greens, then locked in list order", got == Want("classic",
		SpokenWindDB.ach.done) and got:find("^super legend gas double sbd first orchestra thousand penpals ") ~= nil, got)
	SpokenWindDB.ach.done = { heard = 1, fame = 2, cult = 3, everywind = 4, around = 5 }
	got = Got("social")
	ok("ach sort: Social too", got == Want("social", SpokenWindDB.ach.done)
		and got:find("^everywind fame cult heard around packed ") ~= nil, got)
	SpokenWindDB.ach.done = save
end)()
;(function()   -- a Social id, window already open on Classic; the dev show path (nothing saved)
	ns.AchOpen("classic")
	local b0 = #prints
	ns.Toast(ns.AchRow("fame"))
	ok("toast: a row with no reward = no command", T.shown and TR.cmd.text == "" and TR.name.text:find("Wind of Fame", 1, true)
		and TR.rule.text == "Heard 500", TR.cmd.text)
	T.scripts.OnMouseUp(T, "LeftButton")
	local W = Id.W()
	local g = Id.tile("fame")
	ok("toast click: a Social id switches to Social, its tile glows (epic color)", W.root.shown
		and SY.State(W.tabSocial) == "sel" and SY.State(W.tabClassic) ~= "sel" and Id.glow(g)
		and Near(g.cell._swGlow.vc, 0xa3, 0x35, 0xee)
		and LogHas("TOAST click id=fame tab=social glow=1") and not T.shown, LastLog())
	ok("toast click: nothing saved, no chat line", Done().fame == nil and #prints == b0, prints[#prints])
	ns.Toast(ns.AchRow("first"))
	T.scripts.OnMouseUp(T, "RightButton")
	ok("toast: a right click only hides it (no open, no click line)", not T.shown and not LogHas("TOAST click id=first")
		and W.root.shown and SY.State(W.tabSocial) == "sel", LastLog())
	W.root:Hide()
end)()
;(function()   -- in combat: no window, one short line, nothing after combat
	combat = true
	ns.Toast(ns.AchRow("legend"))
	local b0 = #prints
	T.scripts.OnMouseUp(T, "LeftButton")   -- the game gives it no mouse in combat; the script holds anyway
	ok("toast click in combat: no window, one short line", not Id.W().root.shown and #prints == b0 + 1
		and (prints[#prints] or ""):find("ach: not in combat", 1, true) ~= nil
		and LogHas("TOAST click id=legend tab=classic glow=0") and not T.shown, prints[#prints])
	combat = false
	T.scripts.OnEvent(T, "PLAYER_REGEN_ENABLED")
	ok("combat end: no auto-open, the hidden toast still takes no mouse", not Id.W().root.shown and T.mouse == false)
end)()
;(function()   -- the mouse on the toast holds the fade; off = it fades
	ns.Toast(ns.AchRow("first"))
	local function TT(dt) now = now + dt T.scripts.OnUpdate(T, dt) end
	TT(0.3)
	T.scripts.OnEnter(T)
	TT(6)
	ok("toast hover: no fade at all past 6 s", T.shown and T.alpha == 1, T.alpha)
	TT(1) TT(5)
	ok("toast hover: the fade waits (12 s, still full)", T.shown and T.alpha == 1, T.alpha)
	T.scripts.OnLeave(T)
	TT(0.25)
	ok("toast hover off: then it fades", T.shown and math.abs(T.alpha - 0.5) < 0.01, T.alpha)
	TT(0.3)
	ok("toast hover off: gone, no mouse", not T.shown and T.mouse == false)
	ns.Toast(ns.AchRow("first"))
	T.scripts.OnEnter(T)
	T.scripts.OnMouseUp(T, "RightButton")   -- hides it; the mock sends no OnLeave
	ns.Toast(ns.AchRow("first"))
	TT(6.25)
	ok("toast hover: reset when it hides (the next one fades)", T.shown and math.abs(T.alpha - 0.5) < 0.01, T.alpha)
	TT(0.3)
end)()

-- Double Trouble: two people under 1 s apart (1 s is not, one person twice is not)
Fresh()
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
now = now + 1
Emote(ANN_FART, "Ann", ANN)
ok("Double Trouble: not at 1 s", not Done().double)
now = now + 0.5
Emote(FartBy("Cid"), "Cid", "Player-1-CID")
ok("Double Trouble: 0.5 s", Done().double ~= nil)
Fresh()
SpokenWindDB.cd = 0
SY.Tiny(ns)   -- 0.1 ms sounds: the length gate lets Bob's second fart play
now = now + 100
SY.np = #plays
Emote(OTHER_FART, "Bob", BOB)
now = now + 0.2
Emote(OTHER_FART, "Bob", BOB)
ok("Double Trouble: one person twice is not", #plays == SY.np + 2 and not Done().double, #plays - SY.np)
-- Crop Duster: 5 people in 60 s
Fresh()
now = now + 100
for n = 1, 5 do Emote(FartBy("C" .. n), "C" .. n, "Player-1-C" .. n) now = now + 16 end
ok("Crop Duster: 5 people over 64 s is not", not Done().cropduster)
Fresh()
now = now + 100
for n = 1, 4 do Emote(FartBy("C" .. n), "C" .. n, "Player-1-C" .. n) now = now + 14 end
ok("Crop Duster: 4 people is not", not Done().cropduster)
Emote(FartBy("C5"), "C5", "Player-1-C5")
ok("Crop Duster: 5 people in 56 s", Done().cropduster ~= nil)
-- Pen Pals: 10 people, any time
Fresh()
for n = 1, 9 do now = now + 100 Emote(FartBy("P" .. n), "P" .. n, "Player-1-P" .. n) end
local _, pr = AchPage()
ok("Pen Pals: 9 people = 9/10", not Done().penpals and Id.row(pr, "penpals").stat == "9/10", Id.row(pr, "penpals").stat)
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("Pen Pals: 10 people", Done().penpals ~= nil)
ok("Pen Pals: people list cleared", next(SpokenWindDB.ach.people) == nil)
Fresh()
for _ = 1, 10 do now = now + 100 Emote(OTHER_FART, "Bob", BOB) end
ok("Pen Pals: one person 10 times is not", not Done().penpals)
-- Machine Gun: one person, 10 /fart in 10 s; cooldown blocks count
Fresh()
now = now + 100
plays = {}
for _ = 1, 9 do Emote(OTHER_FART, "Bob", BOB) now = now + 0.9 end
ok("Machine Gun: 9 is not", not Done().machinegun)
Emote(OTHER_FART, "Bob", BOB)
ok("Machine Gun: 10 in 8.1 s (cd blocks count)", Done().machinegun ~= nil and #plays < 10, #plays)
Fresh()
now = now + 100
for _ = 1, 10 do Emote(OTHER_FART, "Bob", BOB) now = now + 1.2 end
ok("Machine Gun: 10 in 10.8 s is not", not Done().machinegun)
Fresh()
now = now + 100
for n = 1, 10 do Emote(FartBy("M" .. n), "M" .. n, "Player-1-M" .. n) now = now + 0.1 end
ok("Machine Gun: 10 people once each is not", not Done().machinegun)
-- typed /fart (no key press hook) while your own sound plays: still counts
Fresh()
now = now + 100
plays = {}
for _ = 1, 10 do Emote(OWN_FART, ME, ME_GUID) now = now + 0.9 end
ok("Machine Gun: typed own /fart, 10 in 8.1 s, busy blocks count", Done().machinegun ~= nil and #plays < 10, #plays)
-- Call and Response: not 5.1 s after
Fresh()
now = now + 100
Emote(OWN_FART, ME, ME_GUID)
now = now + 5.1
Emote(OTHER_FART, "Bob", BOB)
ok("Call and Response: 5.1 s is not", not Done().callback)
-- Silent But Deadly: muted channel yes, a play error no
Fresh()
willPlay = false
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
willPlay = true
ok("Silent But Deadly: muted channel", Done().sbd ~= nil)
Fresh()
PlaySoundFile = function() error("boom") end
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("Silent But Deadly: not on a play error", not Done().sbd and LogHas("ERR play"))
-- Night Shift: 00:00-03:59
Fresh()
clock = os.time({ year = 2026, month = 11, day = 22, hour = 4, min = 0, sec = 0 })
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("Night Shift: not at 04:00", not Done().night)
clock = clock - 60
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("Night Shift: 03:59", Done().night ~= nil)
-- Gas Giant 100, Thousand Winds 1000 (all-time total)
Fresh()
SpokenWindDB.stats.all = 98
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
local _, gr = AchPage()
ok("Gas Giant: 99 is not", not Done().gas and Id.row(gr, "gas").stat == "99/100", Id.row(gr, "gas").stat)
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("Gas Giant: 100", Done().gas ~= nil and not Done().thousand)
SpokenWindDB.stats.all = 998
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("Thousand Winds: 999 is not", not Done().thousand)
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("Thousand Winds: 1000", Done().thousand ~= nil)
-- sound rules: straight into AchPlayed (Core's wiring is checked below)
Fresh()
ok("test clock: CLOCK0 is a Saturday", os.date("%w", CLOCK0) == "6")
local function Heard(i) ns.AchPlayed("FART", i, BOB, false, now, true) end
for i = 1, 12 do Heard(i) end
ok("Legend Has It: not before #13", not Done().legend)
ok("Tuba Tuesday: not on a Saturday", not Done().tuba)
local _, orr = AchPage()
ok("Full Orchestra: 12/14", not Done().orchestra and Id.row(orr, "orchestra").stat == "12/14",
	Id.row(orr, "orchestra").stat)
Heard(13)
ok("Legend Has It: #13", Done().legend ~= nil and not Done().super)
Heard(13)
ok("Full Orchestra: one sound twice is not", not Done().orchestra)
Heard(14)
ok("Full Orchestra: all 14", Done().orchestra ~= nil)
clock = CLOCK0 + 3 * 86400
ok("test clock: a Tuesday", os.date("%w", clock) == "2")
Heard(10)
ok("Tuba Tuesday: another sound is not", not Done().tuba)
Heard(11)
ok("Tuba Tuesday: #11 on a Tuesday", Done().tuba ~= nil)
ns.EMOTES.FART.sounds[13].super = true    -- the super legendary sound does not exist yet
Heard(13)
ns.EMOTES.FART.sounds[13].super = nil
ok("Super Legendary: the super sound", Done().super ~= nil)
-- wiring: Core hands over the played sound, key, own flag, time and play result
Fresh()
local got, seen = {}, {}
local realPlayed, realSeen = ns.AchPlayed, ns.AchSeen
ns.AchPlayed = function(...) got[#got + 1] = { ... } return realPlayed(...) end
ns.AchSeen = function(...) seen[#seen + 1] = { ... } return realSeen(...) end
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
local g = got[1]
ok("wiring: AchPlayed gets what played", g and g[1] == "FART" and g[2] == tonumber(LastPlay():match(" snd=(%d+)"))
	and g[3] == BOB and g[4] == false and g[5] == now and g[6] == true and g[7] == nil)
Emote(OTHER_FART, "Bob", BOB)
ok("wiring: cd skip -> AchSeen only", #got == 1 and #seen == 2, #got .. " " .. #seen)
Slash("self off")
Emote(OWN_FART, ME, ME_GUID)
ok("wiring: own /fart with own off -> AchSeen (self)", #seen == 3 and seen[3][1] == "self" and seen[3][2] == true
	and #got == 1)
Slash("self on")
Slash("off")
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("wiring: addon off -> nothing", #seen == 3 and #got == 1)
Slash("on")
ns.AchPlayed, ns.AchSeen = function() error("ach boom") end, realSeen
plays = {}
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("ach error: sound still plays, logged", #plays == 1 and LogHas("ERR ach"))
ns.AchPlayed = realPlayed
-- toast fails: one chat line instead, toast=0
Fresh()
ns.Toast = function() error("toast boom") end
b = #prints
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("toast error: one chat line", #prints == b + 1 and prints[b + 1]:find("First Wind", 1, true)
	and prints[b + 1]:find("|T", 1, true), prints[b + 1])
ok("toast error: logged toast=0", LogHas("ACH first toast=0") and LogHas("ERR toast"))
-- saved: dates kept over a reload; bad saves cleaned
local savedFirst = Done().first
ev, ns = Load(SpokenWindDB)
ok("ach kept over a reload", Done().first == savedFirst and LastLog():find(" done=1 ", 1, true), LastLog())
SpokenWindDB.ach = { done = { first = "x", bogus = 5, gas = CLOCK0 },
	heard = { [1] = true, ["01_squeak"] = true, ["02_rumble"] = "yes" }, people = {} }
for n = 1, 12 do SpokenWindDB.ach.people["Player-1-X" .. n] = true end
ev, ns = Load(SpokenWindDB)
local sa = SpokenWindDB.ach
local dn, pn = 0, 0
for _ in pairs(sa.done) do dn = dn + 1 end
for _ in pairs(sa.people) do pn = pn + 1 end
ok("bad save: known ids with a date only", dn == 1 and sa.done.gas == CLOCK0, dn)
ok("bad save: heard = sound names only", sa.heard["01_squeak"] == true and sa.heard[1] == nil and sa.heard["02_rumble"] == nil)
ok("bad save: people capped at 10", pn == 10, pn)
SpokenWindDB.ach = "junk"
ev, ns = Load(SpokenWindDB)
ok("junk save -> empty", type(SpokenWindDB.ach) == "table" and next(SpokenWindDB.ach.done) == nil)
SpokenWindDB.ach = { done = { penpals = CLOCK0 }, people = { a = true } }
ev, ns = Load(SpokenWindDB)
ok("Pen Pals done: people list dropped", next(SpokenWindDB.ach.people) == nil)
-- dev only: /wind ach test [n] shows a toast, earns nothing
Fresh()
b = #prints
Slash("ach test 3")
ok("public: /wind ach test = the window, no toast", #prints == b and ns.ToastFrame() == nil and not LogHas("ACH test")
	and LastLog():find("ACH open tab=classic n=15$"), LastLog())
Id.W().root:Hide()
Fresh(true)
Slash("ach test 3")
T, TR = ns.ToastFrame(), ns.ToastRefs()
ok("dev: ach test shows the toast", T and T.shown and TR.name.text == "|cffa335eeFull Orchestra|r" and TR.cmd.text == "/orchestra",
	TR and TR.name.text)
ok("dev: ach test logged", LastLog():find("ACH test orchestra toast=1", 1, true), LastLog())
Slash("ach test")
ok("dev: ach test, no number -> a random row", LastLog():find("ACH test %a+ toast=1"), LastLog())
ok("dev: ach test earns nothing", next(Done()) == nil)
-- secret row: Test Farts Don't Smell. Only the dev Test gives it (Play button or
-- /wind test); not a fart, no other row; hidden until earned; head "+1".
Fresh()
ns.Test(3)   -- public: a direct call earns nothing either
Slash("test 3")
ok("secret: public has no path", next(Done()) == nil and not SY.Opt().opt.testR.shown
	and not LogHas("ACH testsmell"))
local sh, sr = AchPage()
ok("secret: public window hides it", sh == "Classic 0/15" and #sr == 15, sh)
Fresh(true)
plays = {}
SY.Click(SY.Opt().opt.testPlay)
ok("secret: Play on Test earns it", Done().testsmell == clock and LogHas("ACH testsmell toast=1"), LastLog())
ok("secret: only this row", next(Done(), "testsmell") == nil and next(Done()) == "testsmell")
ok("secret: not a fart", #SpokenWindDB.farts == 0 and SpokenWindDB.stats.all == 0 and #plays == 1, #SpokenWindDB.farts)
T, TR = ns.ToastFrame(), ns.ToastRefs()
ok("secret: toast white, ? icon, no reward command", T and T.shown and TR.name.text == "|cffffffffTest Farts Don't Smell|r"
	and TR.icon.path == "Interface\\Icons\\INV_Misc_QuestionMark" and TR.cmd.text == "", TR and TR.name.text)
sh, sr = AchPage()
ok("secret: shown once earned, head +1", sh == "Classic 0/15 +1" and #sr == 16, sh)
local s16 = Id.row(sr, "testsmell")
ok("ach sort: an earned secret row joins the earned group (spot 1)", select(2, Id.row(sr, "testsmell")) == 1)
ok("secret: row 16", s16.name == "|cffffffffTest Farts Don't Smell|r" and s16.rule == "Press Play on Test"
	and s16.stat == "Done " .. os.date("%m-%d", clock) and s16.grey == false and s16.icon == "Interface\\Icons\\INV_Misc_QuestionMark",
	s16.name)
;(function()   -- 17 tiles (the earned dev secret first, the ??? for Shart last): a 9th row, no scroll bar
	ns.AchOpen("classic")
	local TL = Id.tiles()
	local _, B = Id.W()
	ok("secret: 17 tiles = 9 rows", #TL == 17 and #B._swRows == 9 and TL[17].line.place and B._swList.hidden == 0,
		#TL .. " " .. tostring(B._swList.hidden))
	ok("secret: tile = ? icon, white name, base state", TL[1].line.id == "testsmell"
		and TL[1].icon.path == "Interface\\Icons\\INV_Misc_QuestionMark" and SY.State(TL[1].cell) == "base"
		and TL[1].name.text == "|cffffffffTest Farts Don't Smell|r", TL[1].name.text)
	ok("secret: the tag counts it", B.secretText.text == "Secret 1/2" and SY.State(B.secret) == "good", B.secretText.text)
	ok("secret: an earned secret tile can glow", ns.AchGlow("testsmell") == true and Id.glow(TL[1]))
	ok("secret: the ??? tile never glows", ns.AchGlow(TL[17].line.id) == false and not Id.glow(TL[17]),
		TL[17].line.id)
	Id.W().root:Hide()
end)()
plays = {}
Slash("test 4")
local nAch = 0
for _, l in ipairs(SpokenWindDB.log) do if l:find("ACH testsmell", 1, true) then nAch = nAch + 1 end end
ok("secret: once", nAch == 1 and #plays == 1, nAch)
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
sh = AchPage()
ok("secret: other rules unchanged", Done().first ~= nil and sh == "Classic 1/15 +1", sh)
ev, ns = Load(SpokenWindDB)
sh, sr = AchPage()
ok("secret: kept over a reload, public too", sh == "Classic 1/15 +1" and #sr == 16 and LastLog():find(" done=1 ", 1, true),
	LastLog())
-- the game's friend toast: only read, never called or written
local bnTouched = 0
for _, x in ipairs(forbidden) do if x:find("BNToastFrame", 1, true) then bnTouched = bnTouched + 1 end end
ok("BNToastFrame never called or written", bnTouched == 0, forbidden[1])
Fresh()

-- slash clash: a game emote that uses our slash word shows in BOOT
EMOTE99_TOKEN, EMOTE99_CMD2 = "WINDY", "/wind"
Load(SpokenWindDB)
ok("boot clash=1", LastLog():find("slash=/wind clash=1", 1, true), LastLog())
EMOTE99_TOKEN, EMOTE99_CMD2 = nil, nil

-- a new emote row works with no code change (test-only row and folder)
ev, ns = Load(SpokenWindDB)
SpokenWindDB.self = true
ns.EMOTES.CHEER = { folder = "cheer", stems = { enUS = { "%f[%a]cheers?%f[%A]" } },
	sounds = { { file = "01_a", name = "A" }, { file = "02_b", name = "B" } } }
ns.LEN["01_a"], ns.LEN["02_b"] = 1, 1   -- a new row's files need lengths too (tools/oglen.py makes them)
ok("new row src guess", ns.SetLocale("enUS").CHEER == "guess")
plays = {}
now = now + 100
Emote("Bob cheers at you.", "Bob", "C0")
ok("new row plays its folder", plays[1] and plays[1].path:find("^Interface\\AddOns\\Spoken_Wind\\Media\\cheer\\0[12]_[ab]%.ogg$"),
	plays[1] and plays[1].path)
ok("new row logged", LastPlay():find("PLAY emo=CHEER who=other", 1, true), LastPlay())
SpokenWindDB.cd = 0
local cheerPaths = {}
for _ = 1, 40 do now = now + 1 Emote("Bob cheers.", "Bob", "C0") cheerPaths[#cheerPaths + 1] = plays[#plays].path end
local alt = true
for n = 2, #cheerPaths do if cheerPaths[n] == cheerPaths[n - 1] then alt = false end end
ok("new row: own picker, never twice in a row", alt)
now = now + 1
Emote(OTHER_FART, "Bob", "F1")
ok("fart still plays fart folder", plays[#plays].path:find("\\Media\\fart\\", 1, true) ~= nil, plays[#plays].path)
ok("fart still logged FART", LastPlay():find("PLAY emo=FART", 1, true), LastPlay())
ok("status lists both sets", (function()
	local n = #prints Slash("") return prints[n + 1] and prints[n + 1]:find("cheer 2 · fart 1351", 1, true)
end)(), prints[#prints - 1])
ns.EMOTES.CHEER = nil

do   -- rewards: own block (keeps the chunk under the 200-locals limit)
-- ---------------------------------------------------------------- rewards (0.5.0)
local function RwSlash(cmd)   -- a typed slash = a key press (hardware event)
	local f = SlashCmdList["SPOKENWIND_" .. cmd:sub(2):upper()]
	hw = true
	if f then f("") end
	hw = false
	return f ~= nil
end
local function Click(f, button)   -- a mouse click (hardware event)
	hw = true
	if f.scripts.OnMouseDown then f.scripts.OnMouseDown(f, button or "LeftButton") end
	f.scripts.OnMouseUp(f, button or "LeftButton")
	hw = false
end
local function EmoteLine(text, sender, guid)
	ev.scripts.OnEvent(ev, "CHAT_MSG_EMOTE", text, sender, "", "", "", "", 0, 0, "", 0, 123, guid)
end
local function Unlock(id) SpokenWindDB.ach.done[id] = clock end
local TUBA = "plays the tuba. It is not a tuba."

-- data: 15 rows in achievement order, the texts as approved, sounds by name
Fresh()
local RW = ns.REWARDS
local DRAFT = {
	{ "super", "/superfart", "unleashes a super legendary fart. Reality bends.", "Legend" },
	{ "legend", "/legend", "lets one rip that bards will sing about.", "Legend" },
	{ "orchestra", "/orchestra", "conducts a full fart orchestra.", "Trumpet" },
	{ "thousand", "/gale", "summons a gale from behind.", "Rumble" },
	{ "gas", "/gasgiant", "swells up like a gas giant.", "Balloon" },
	{ "penpals", "/penpal", "sends a scented letter.", "Quack" },
	{ "cropduster", "/cropdust", "dusts the crops on the way past.", "Sputter" },
	{ "double", "/double", "fires both barrels.", "Triple" },
	{ "callback", "/pfftback", "answers the call of nature.", "Question" },
	{ "machinegun", "/brrrt", "opens fire. Brrrrrt.", "Brrt" },
	{ "sbd", "/sbd", "lets one slip. Nobody heard a thing.", "Pfft" },
	{ "night", "/moontoot", "toots softly at the moon.", "Slow squeak" },
	{ "tuba", "/tuba", TUBA, "Tuba" },
	{ "selfstarter", "/kickstart", "kick-starts the engine.", "Wet" },
	{ "first", "/firstwind", "squeaks out a first little toot.", "Squeak" },
}
ok("rw: 15 rows", #RW == 15, #RW)
local SND = ns.EMOTES.FART.sounds
for i, d in ipairs(DRAFT) do
	local r = RW[i] or {}
	ok("rw " .. i .. " = achievement " .. d[1], r.ach == d[1] and ns.ACH[i].id == d[1], r.ach)
	ok("rw " .. i .. " command " .. d[2], r.cmd == d[2], r.cmd)
	ok("rw " .. i .. " text as approved", r.text == d[3], r.text)
	ok("rw " .. i .. " sound " .. d[4], r.snd and SND[r.snd] and SND[r.snd].name == d[4], r.snd)
end
local seenCmd, seenText = {}, {}
for i, r in ipairs(RW) do
	ok("rw cmd lower, one word " .. i, r.cmd:match("^/%l+$") ~= nil, r.cmd)
	ok("rw cmd unique " .. i, not seenCmd[r.cmd])
	ok("rw text unique " .. i, not seenText[r.text])
	seenCmd[r.cmd], seenText[r.text] = true, true
	ok("rw text short, no name " .. i, #r.text <= 120 and r.text:match("^%l") ~= nil, r.text)
	ok("rw by exact text " .. i, ns.RewardByText(r.text) == i)
end
ok("rw not /moon (a game emote)", not seenCmd["/moon"])

-- commands: made at login, one per row
local made = 0
for _, r in ipairs(RW) do
	local key = "SPOKENWIND_" .. r.cmd:sub(2):upper()
	if _G["SLASH_" .. key .. "1"] == r.cmd and type(SlashCmdList[key]) == "function" then made = made + 1 end
end
ok("rw: 15 commands made", made == 15, made)
ok("rw: BOOT rw=15 btn=1", LastLog():find(" rw=15 btn=1 ", 1, true), LastLog())
ok("rw: the bar (default on)", ns.BarRefs() ~= nil and (ns.BarRefs()).root.shown)

-- clash: a word the game or another addon owns is skipped, never overwritten
local otherFn, hashFn = function() end, function() end
preLogin = function()
	SlashCmdList.OTHERADDON, SLASH_OTHERADDON1, SLASH_OTHERADDON2 = otherFn, "/other", "/TUBA"
	SecureCmdList, SLASH_SECUREX1 = { SECUREX = function() end }, "/double"
	ChatTypeInfo, SLASH_YELLX1, SLASH_YELLX2 = { YELLX = {} }, "/yx", "/penpal"
	hash_SlashCmdList = { ["/GALE"] = hashFn }
	EMOTE120_TOKEN, EMOTE120_CMD3 = "SBDX", "/sbd"
end
ev, ns = Load(nil)
preLogin = nil
ok("clash: other addon kept", SlashCmdList.OTHERADDON == otherFn and SLASH_OTHERADDON2 == "/TUBA")
ok("clash: /tuba skipped (any case)", SlashCmdList.SPOKENWIND_TUBA == nil)
ok("clash: /double skipped (secure list)", SlashCmdList.SPOKENWIND_DOUBLE == nil)
ok("clash: /penpal skipped (chat type, 2nd word)", SlashCmdList.SPOKENWIND_PENPAL == nil)
ok("clash: /gale skipped (game cache)", SlashCmdList.SPOKENWIND_GALE == nil and hash_SlashCmdList["/GALE"] == hashFn)
ok("clash: /sbd skipped (game emote)", SlashCmdList.SPOKENWIND_SBD == nil)
ok("clash: the rest made", type(SlashCmdList.SPOKENWIND_LEGEND) == "function"
	and type(SlashCmdList.SPOKENWIND_FIRSTWIND) == "function")
ok("clash: logged", LogHas("REWARD skip /gale,/penpal,/double,/sbd,/tuba"))
ok("clash: BOOT rw=10", LastLog():find(" rw=10 ", 1, true), LastLog())
SLASH_OTHERADDON1, SLASH_OTHERADDON2, SLASH_SECUREX1, SLASH_YELLX1, SLASH_YELLX2 = nil, nil, nil, nil, nil
EMOTE120_TOKEN, EMOTE120_CMD3 = nil, nil

-- use: locked = one local line; unlocked = one EMOTE line + its sound
Fresh()
local nPrint = #prints
plays = {}
RwSlash("/tuba")
ok("locked: no chat line", #sent == 0, #sent)
ok("locked: no sound", #plays == 0, #plays)
ok("locked: one local line", #prints == nPrint + 1 and prints[#prints]:find("locked: Tuba Tuesday$"), prints[#prints])
ok("locked: logged", LastLog():find("REWARD id=13 by=slash locked", 1, true), LastLog())
Unlock("tuba")
now = now + 10
nPrint = #prints
RwSlash("/tuba")
ok("use: one EMOTE line", #sent == 1 and sent[1].chan == "EMOTE" and sent[1].text == TUBA, sent[1] and sent[1].text)
ok("use: its sound", #plays == 1 and plays[1].path:find("\\11_tuba.ogg", 1, true) and plays[1].ch == "SFX",
	plays[1] and plays[1].path)
ok("use: no print", #prints == nPrint, prints[#prints])
ok("use: logged", LastLog():find("REWARD id=13 by=slash sent=1", 1, true), LastLog())
ok("use: not a fart (no fart log, no achievement)", #SpokenWindDB.farts == 0 and Done().first == nil
	and Done().selfstarter == nil)
now = now + 0.5
RwSlash("/tuba")
ok("use: 0.5 s later = no second line", #sent == 1 and #plays == 1, #sent)
ok("use: fast skip logged", LastLog():find("REWARD id=13 by=slash skip=fast", 1, true), LastLog())
now = now + 0.51
RwSlash("/tuba")
ok("use: 1 s later = next line", #sent == 2 and #plays == 2, #sent)
SpokenWindDB.on = false
now = now + 2
RwSlash("/tuba")
ok("off: line still out (you asked), no sound", #sent == 3 and #plays == 2, #plays)
SpokenWindDB.on = true
local cSent = {}
C_ChatInfo = { SendChatMessage = function(t, c)
	cSent[#cSent + 1] = { t, c }
	if not hw then forbidden[#forbidden + 1] = "C_ChatInfo send outside a click or slash" end
end }
now = now + 2
RwSlash("/tuba")
ok("newer client: C_ChatInfo.SendChatMessage", #cSent == 1 and cSent[1][1] == TUBA and cSent[1][2] == "EMOTE"
	and #sent == 3, #cSent)
C_ChatInfo = nil
SendChatMessage = function() error("chat off") end
now = now + 2
RwSlash("/tuba")
ok("send error: no crash, sent=0", LastLog():find("REWARD id=13 by=slash sent=0", 1, true) and LogHas("ERR send"),
	LastLog())

-- receive: exact text, same per-person cooldown as /fart, no chat, no print
Fresh()
plays = {}
now = now + 10
nPrint = #prints
EmoteLine(TUBA, "Bob", BOB)
ok("heard: its sound", #plays == 1 and plays[1].path:find("\\11_tuba.ogg", 1, true), plays[1] and plays[1].path)
ok("heard: logged", LastLog():find("REWARD heard id=13 who=other", 1, true), LastLog())
ok("heard: plays though locked for me", Done().tuba == nil)
ok("heard: no chat, no print", #sent == 0 and #prints == nPrint)
ok("heard: not a fart", #SpokenWindDB.farts == 0 and Done().first == nil)
now = now + 0.5
EmoteLine(TUBA, "Bob", BOB)
ok("heard: same person busy = skip", #plays == 1 and LastLog():find("SKIP busy rw=13 who=other left=0.8", 1, true), LastLog())
Emote(OTHER_FART, "Bob", BOB)
ok("heard: shares the /fart cooldown", #plays == 1, #plays)
EmoteLine("opens fire. Brrrrrt.", "Ann", ANN)
ok("heard: other person plays", #plays == 2 and plays[2].path:find("\\07_brrt.ogg", 1, true), #plays)
now = now + 1.01
EmoteLine(TUBA, "Bob", BOB)
ok("heard: after 1 s plays", #plays == 3, #plays)
now = now + 10
EmoteLine("plays the tuba. It is not a tuba!", "Cat", "Player-1-CAT")
EmoteLine("Plays the tuba. It is not a tuba.", "Cat", "Player-1-CAT")
EmoteLine(TUBA .. " ", "Cat", "Player-1-CAT")
EmoteLine("waves.", "Cat", "Player-1-CAT")
ok("heard: exact text only", #plays == 3, #plays)
EmoteLine(TUBA, ME, ME_GUID)
ok("heard: own echo = no second sound", #plays == 3, #plays)
SpokenWindDB.on = false
EmoteLine(TUBA, "Dan", "Player-1-DAN")
ok("heard: off = silent", #plays == 3 and LastLog():find("SKIP off rw=13", 1, true), LastLog())
SpokenWindDB.on = true
issecretvalue = function(v) return v == TUBA end
EmoteLine(TUBA, "Eve", "Player-1-EVE")
ok("heard: secret text = no sound, no error", #plays == 3 and not LogHas("ERR rw"), #plays)
issecretvalue = nil
EmoteLine(TUBA, "Fay", nil)
ok("heard: no guid = name key", #plays == 4, #plays)

-- The bar (0.8.0): Options checkbox "Rewards button" (default on), made at login.
-- Achievements button: left click = the achievements window, right click = the rewards popup. Fart button, Heard tag.
Fresh()
local bar = ns.BarRefs()
ok("bar: made at login (default on), the named own frame", bar ~= nil and bar.root == _G.SpokenWindButtons and bar.root.shown
	and SY.own[bar.root] ~= nil, #frames)
ok("bar: movable, drag on the bar and on both buttons", bar.root.movable and bar.root.drag == "LeftButton" and bar.ach.drag == "LeftButton"
	and bar.fart.drag == "LeftButton")
ok("bar: mouse out of combat, no keys", bar.root.mouse == true and bar.ach.mouse == true and bar.fart.mouse == true
	and bar.root.kb == nil and bar.ach.kb == nil and bar.fart.kb == nil)
ok("bar: combat + target events on the bar", bar.root.events.PLAYER_REGEN_DISABLED == true
	and bar.root.events.PLAYER_REGEN_ENABLED == true and bar.root.events.PLAYER_TARGET_CHANGED == true)
ok("bar: default spot left middle", bar.root.point and bar.root.point[1] == "LEFT" and bar.root.point[4] == 40)
ok("bar: First Wind icon, done/main count", bar.achIcon.path == ns.AchIcon(ns.ACH[15]) and bar.achN.text:find("^0/%d+$") ~= nil, bar.achN.text)
ok("bar: Fart label, no Heard tag", bar.fartL.text == "Fart" and not bar.heardBy.shown)
reg.byVar.SpokenWind_rwbtn:SetValue(false)
ok("bar: off = hidden", bar.root.shown == false)
ok("bar: OPT logged", LogHas("OPT rwbtn=false by=panel"))
local nF = #frames
reg.byVar.SpokenWind_rwbtn:SetValue(true)
ok("bar: on again = same frames", bar.root.shown and #frames == nF and ns.BarRefs() == bar, #frames - nF)

-- the rewards popup: 15 commands in pairs, earned first (list order), locked dimmed with its progress
Unlock("first") Unlock("tuba")
SY.Click(bar.ach, "RightButton")
local _, pop = ns.BarRefs()
ok("popup: opens on a right click, the named own frame", pop and pop.root.shown and pop.root == _G.SpokenWindRewards)
ok("popup: right click opens no window", ns.AchRefs() == nil)
local rows = pop._swRows
local function CellOf(i)   -- the cell of reward i
	for _, r in ipairs(pop._swRows) do
		if r._swA == i then return r.cellA, r end
		if r._swB == i then return r.cellB, r end
	end
end
ok("popup: 8 rows of 2, the last half hidden", #rows == 8 and rows[8]._swA == 14 and rows[8]._swB == nil and not rows[8].cellB.shown
	and rows[8].cellA.shown, #rows)
ok("popup: earned first (list order), then locked (list order)", rows[1]._swA == 13 and rows[1]._swB == 15 and rows[2]._swA == 1
	and rows[2]._swB == 2 and rows[7]._swB == 12)
ok("popup: count earned/15", pop.count.text == "2/15", pop.count.text)
local r1, r2 = rows[1], rows[2]
ok("popup: earned = command, its icon, no progress, base look", r1.cmdA.text == "/tuba" and r1.iconA.path == ns.AchIcon(ns.ACH[13])
	and r1.nA.text == "" and SY.State(r1.cellA) == "base")
ok("popup: locked = dimmed (off) + its progress", SY.State(r2.cellA) == "off" and r2.cmdA.text == "/superfart"
	and r2.nA.text == ns.AchStat("super"), tostring(r2.nA.text))
ok("popup: above the bar, 4 px", pop.root.point[1] == "BOTTOMLEFT" and pop.root.point[2] == bar.root and pop.root.point[3] == "TOPLEFT"
	and pop.root.point[5] == 4)
ok("popup: no keys; click-outside watch on", pop.root.kb == nil and pop.root.events.GLOBAL_MOUSE_DOWN == true)
ok("popup: TOOLTIP strata, clamped", pop.root.strata == "TOOLTIP" and pop.root.clamped == true)
ok("popup: the x glyph", (function()
	for _, rg in ipairs({ pop.close:GetRegions() }) do if rg.text == "\195\151" then return true end end
	return false
end)())
-- hover a reward: its tip (Rule / Progress / Reward)
local function TipText(r) local tt = {} for i, x in ipairs(r and r._swRows or {}) do tt[i] = x[1] .. "=" .. x[2] end return table.concat(tt, "|") end
r2.cellA.scripts.OnEnter(r2.cellA)
local _, _, _, tipR = ns.BarRefs()
ok("tip: a reward: its name, rule, reward", tipR and tipR.root.shown and tipR.titleText.text == "Super Legendary"
	and TipText(tipR):find("Rule=" .. ns.AchRow("super").rule, 1, true) == 1 and TipText(tipR):find("|Reward=", 1, true) ~= nil
	and TipText(tipR):find("/superfart", 1, true) ~= nil, TipText(tipR))
ok("tip: beside the cell, TOOLTIP", tipR.root.point[2] == r2.cellA and tipR.root.strata == "TOOLTIP")
r2.cellA.scripts.OnLeave(r2.cellA)
ok("tip: leave = hidden", not tipR.root.shown)
-- every locked cell shows its progress; a locked reward with progress: its tip has the Progress row, the command dimmed
do
	local good, cell, id, rd = true, nil, nil, nil
	for _, r in ipairs(pop._swRows) do
		for _, side in ipairs({ "A", "B" }) do
			local i = r["_sw" .. side]
			if i and not ns.AchHas(ns.REWARDS[i].ach) then
				local st = ns.AchStat(ns.REWARDS[i].ach)
				if r["n" .. side].text ~= st then good = false end
				if st ~= "" and not cell then cell, id, rd = r["cell" .. side], i, ns.REWARDS[i] end
			end
		end
	end
	ok("popup: each locked cell = its progress; one has some", good and cell ~= nil)
	cell.scripts.OnEnter(cell)
	local L = ns.Look
	ok("tip: a locked reward: Progress row, the command dimmed", TipText(tipR):find("|Progress=" .. ns.AchStat(rd.ach) .. "|", 1, true) ~= nil
		and tipR._swRows[#tipR._swRows][2] == L.Run({ { rd.cmd, "dim" } }) and L.Run({ { rd.cmd, "dim" } }) ~= L.Run({ { rd.cmd, "gold" } }),
		TipText(tipR))
	cell.scripts.OnLeave(cell)
end
local nSent = #sent
SY.Click(r2.cellA)
ok("cell locked: no chat, popup stays, local line", #sent == nSent and pop.root.shown
	and prints[#prints]:find("locked: Super Legendary$"), prints[#prints])
ok("cell locked: logged", LastLog():find("REWARD id=1 by=button locked", 1, true), LastLog())
now = now + 10
SY.Click(r1.cellA, "RightButton")
ok("cell: a right click sends nothing", #sent == nSent and pop.root.shown)
SY.Click(r1.cellA)
ok("cell: one line, popup closes", #sent == nSent + 1 and sent[#sent].text == TUBA and not pop.root.shown)
ok("cell: logged", LastLog():find("REWARD id=13 by=button sent=1", 1, true), LastLog())
ok("cell: closed = no click watch", not pop.root.events.GLOBAL_MOUSE_DOWN)
SY.Click(bar.ach, "RightButton")
ok("popup: opens again", pop.root.shown)
SY.Click(pop.close)
ok("popup: the x closes it", not pop.root.shown)
SY.Click(bar.ach, "RightButton")
pop.root.over, bar.root.over = true, false
pop.root.scripts.OnEvent(pop.root, "GLOBAL_MOUSE_DOWN")
ok("click inside: stays", pop.root.shown)
pop.root.over, bar.root.over = false, true
pop.root.scripts.OnEvent(pop.root, "GLOBAL_MOUSE_DOWN")
ok("click on the bar: stays (the button toggles)", pop.root.shown)
pop.root.over, bar.root.over = false, false
pop.root.scripts.OnEvent(pop.root, "GLOBAL_MOUSE_DOWN")
ok("click outside: closes", not pop.root.shown)
SY.Click(bar.ach, "RightButton") SY.Click(bar.ach, "RightButton")
ok("button again: closes", not pop.root.shown)
-- earn while open: the cell turns to color at once, the counts follow
SY.Click(bar.ach, "RightButton")
now = now + 100
Emote(OWN_FART, ME, ME_GUID)
local nR = 0
for _, r in ipairs(ns.REWARDS) do if Done()[r.ach] then nR = nR + 1 end end
ok("earn while open: earned at once", Done().selfstarter ~= nil and nR >= 3 and pop.count.text == ("%d/15"):format(nR)
	and SY.State((CellOf(14))) == "base"
	and bar.achN.text:find("^" .. ns.AchDone() .. "/") ~= nil, pop.count.text .. " " .. bar.achN.text)
-- combat: popup shut, no mouse, the Fart button says so
combat = true
bar.root.scripts.OnEvent(bar.root, "PLAYER_REGEN_DISABLED")
ok("combat: popup shut, no mouse, Fart = Combat (off)", not pop.root.shown and bar.root.mouse == false and bar.ach.mouse == false
	and bar.fart.mouse == false and bar.fartL.text == "Combat" and SY.State(bar.fart) == "off")
SY.Click(bar.ach, "RightButton")
SY.Click(bar.ach)
ok("combat: a click opens nothing", not pop.root.shown and ns.AchRefs() == nil)
ok("combat: RewardsToggle (the window's Rewards button) opens nothing", ns.RewardsToggle() == false and not pop.root.shown)
bar.ach.scripts.OnEnter(bar.ach)
ok("combat: no tip", select(3, ns.BarRefs()) == nil or not select(3, ns.BarRefs()).root.shown)
bar.ach.scripts.OnMouseDown(bar.ach, "LeftButton")
bar.ach.scripts.OnDragStart(bar.ach)
ok("combat: no drag", not bar.root.moving)
combat = false
bar.root.scripts.OnEvent(bar.root, "PLAYER_REGEN_ENABLED")
ok("after combat: mouse back, Fart", bar.root.mouse == true and bar.ach.mouse == true and bar.fart.mouse == true and bar.fartL.text == "Fart"
	and SY.State(bar.fart) == "base")
-- drag the bar itself: the spot is saved through Look's moved hook
bar.root.scripts.OnDragStart(bar.root)
bar.root.left, bar.root.bottom = 120.2, 80.7
bar.root.scripts.OnDragStop(bar.root)
ok("drag the bar: spot saved (moved hook), placed there", SpokenWindDB.rwpos and SpokenWindDB.rwpos.x == 120 and SpokenWindDB.rwpos.y == 81
	and bar.root.point[1] == "BOTTOMLEFT" and bar.root.point[4] == 120)
-- drag a button: the bar moves, no click after it
bar.ach.scripts.OnMouseDown(bar.ach, "LeftButton")
bar.ach.scripts.OnDragStart(bar.ach)
ok("drag a button: the bar moves", bar.root.moving == true)
bar.root.left, bar.root.bottom = 300.4, 500.6
bar.ach.scripts.OnDragStop(bar.ach)
hw = true bar.ach.scripts.OnClick(bar.ach, "LeftButton", false) hw = false
ok("drag: no window, no popup after a drag", not pop.root.shown and ns.AchRefs() == nil)
ok("drag: spot saved", SpokenWindDB.rwpos and SpokenWindDB.rwpos.x == 300 and SpokenWindDB.rwpos.y == 501)
ok("drag: placed at the spot", bar.root.point[1] == "BOTTOMLEFT" and bar.root.point[4] == 300 and bar.root.point[5] == 501)
bar.root.left, bar.root.bottom = nil, nil
SY.Click(bar.ach, "RightButton")
ok("click after a drag opens", pop.root.shown)
SY.Click(bar.ach, "RightButton")
SY.Click(bar.ach)
ok("left click: the window, not the popup", not pop.root.shown and ns.AchRefs() and ns.AchRefs().root.shown)
SY.Click(bar.ach)
ok("left click again: the window closes", not ns.AchRefs().root.shown)
-- the Fart button: left = the whisper, right = the /say, any other button (a /click macro) = nothing
do
	local bc, bs, nC, nS = ns.BtnClick, ns.BtnSay, 0, 0
	ns.BtnClick = function() nC = nC + 1 end
	ns.BtnSay = function() nS = nS + 1 end
	bar.fart.scripts.OnClick(bar.fart, "MiddleButton", false)
	bar.fart.scripts.OnClick(bar.fart, "Button4", false)
	local mid = nC .. "/" .. nS
	bar.fart.scripts.OnClick(bar.fart, "LeftButton", false)
	bar.fart.scripts.OnClick(bar.fart, "RightButton", false)
	ns.BtnClick, ns.BtnSay = bc, bs
	ok("fart: a middle click = nothing (left = 1 click, right = 1 say)", mid == "0/0" and nC == 1 and nS == 1,
		mid .. " then " .. nC .. "/" .. nS)
end
-- the Fart button drags the bar too; its click after a drag does nothing
local ne0 = #SY.emotes
bar.fart.scripts.OnMouseDown(bar.fart, "LeftButton")
bar.fart.scripts.OnDragStart(bar.fart)
bar.fart.scripts.OnDragStop(bar.fart)
hw = true bar.fart.scripts.OnClick(bar.fart, "LeftButton", false) hw = false
ok("drag the Fart button: the bar moves, no fart", bar.root.moving ~= nil and #SY.emotes == ne0, #SY.emotes - ne0)
-- a drag with no click after it: the next press clears the flag, its click works
bar.ach.scripts.OnMouseDown(bar.ach, "LeftButton")
bar.ach.scripts.OnDragStart(bar.ach)
bar.ach.scripts.OnDragStop(bar.ach)
SY.Click(bar.ach, "RightButton")
ok("drag with no click: the next click works", pop.root.shown)
SY.Click(bar.ach, "RightButton")

-- reload: on + spot kept; bad spot dropped; near the top = popup below
ev, ns = Load(SpokenWindDB)
local bar2 = ns.BarRefs()
ok("reload: bar back at its spot", bar2 and bar2.root.shown and bar2.root.point[1] == "BOTTOMLEFT" and bar2.root.point[4] == 300)
ok("reload: BOOT btn=1", LastLog():find(" rw=15 btn=1 ", 1, true), LastLog())
ok("reload: no hello note again", select(5, ns.BarRefs()) == nil)
bar2.root.top = 760
SY.Click(bar2.ach, "RightButton")
local _, pop2 = ns.BarRefs()
ok("popup: below the bar near the top", pop2.root.point[1] == "TOPLEFT" and pop2.root.point[3] == "BOTTOMLEFT" and pop2.root.point[5] == -4)
SY.Click(bar2.ach, "RightButton")
SpokenWindDB.rwpos = { x = "a", y = 1 }
ev, ns = Load(SpokenWindDB)
bar2 = ns.BarRefs()
ok("bad spot dropped -> default", SpokenWindDB.rwpos == nil and bar2.root.point[1] == "LEFT")
SpokenWindDB.rwpos = { x = 0 / 0, y = 1 }
ev, ns = Load(SpokenWindDB)
ok("NaN spot dropped", SpokenWindDB.rwpos == nil)
Slash("reset")
bar2 = ns.BarRefs()
ok("reset: bar back to on (the default)", SpokenWindDB.rwbtn == true and bar2.root.shown == true)
SpokenWindDB.rwbtn = true
ev, ns = Load(SpokenWindDB, "canvas")
local bar3 = ns.BarRefs()
ok("old page: bar from the save", bar3 and bar3.root.shown)
SpokenWindDB.rwbtn = false
ev, ns = Load(SpokenWindDB, "canvas")
ok("old page: off in the save = no bar", ns.BarRefs() == nil and SpokenWindDB.rwbtn == false)
Slash("reset")
ok("old page: reset = on", SpokenWindDB.rwbtn == true and ns.BarRefs() and ns.BarRefs().root.shown)

-- the hello note (first run): once per account at login, under the bar; the Random switch; again from ns.HelloShow (the "?" button)
do
	Fresh()
	local hb, _, _, _, hl = ns.BarRefs()
	ok("hello: shown at the first login, under the bar", hl and hl.root.shown and hl.root == _G.SpokenWindHello
		and hl.root.point[1] == "TOPLEFT" and hl.root.point[2] == hb.root and hl.root.point[3] == "BOTTOMLEFT"
		and SpokenWindDB.hello == true and LogHas("HELLO by=first"))
	ok("hello: the random line + Random off (random on)", hl.v5.text == "On · 45-75 min" and hl.randOff.shown
		and SY.Tx(hl.randOffText) == "Random off", tostring(hl.v5.text) .. " " .. SY.Tx(hl.randOffText))
	ok("hello: no keys, TOOLTIP strata", hl.root.kb == nil and hl.root.strata == "TOOLTIP")
	local OPg = ns.OptRefs()
	SY.ShowPage(OPg.fo)   -- the Options page open: it follows the switch
	local RV = reg.byVar["SpokenWind_random"]
	SY.Click(hl.randOff)
	ok("hello: Random off = the setting off, logged by=hello", SpokenWindDB.random == false and LogHas("OPT random=false by=hello")
		and hl.v5.text == "Off", LastLog())
	ok("hello switch: still shown when off, text Random on", hl.randOff.shown and SY.Tx(hl.randOffText) == "Random on",
		SY.Tx(hl.randOffText))
	ok("hello switch off: the Options page follows (Off)", RV:GetValue() == false and SY.Tx(OPg.opt.random) == "Off"
		and SY.State(OPg.opt.random) == "base", SY.Tx(OPg.opt.random) .. " " .. tostring(SY.State(OPg.opt.random)))
	local rowW = hl.root:GetWidth() - 2 * 0.635 - 20
	local used = hl.sp5:GetWidth() + hl.k5:GetWidth() + 3 * 8 + hl.v5:GetStringWidth() + hl.randOff:GetWidth()
	ok("hello switch: the row fits (icon + key + value + button)", used <= rowW, used .. " of " .. rowW)
	local nOpt = #SpokenWindDB.log
	combat = true
	SY.Click(hl.randOff)
	ok("hello switch: in combat a click does nothing", SpokenWindDB.random == false and #SpokenWindDB.log == nOpt
		and SY.Tx(hl.randOffText) == "Random on", LastLog())
	combat = false
	SY.Click(hl.randOff)
	ok("hello switch: Random on = the setting on, logged by=hello", SpokenWindDB.random == true
		and LastLog():find("OPT random=true by=hello", 1, true) ~= nil and hl.v5.text == "On · 45-75 min"
		and SY.Tx(hl.randOffText) == "Random off", LastLog())
	ok("hello switch on: the Options page follows (On)", RV:GetValue() == true and SY.Tx(OPg.opt.random) == "On"
		and SY.State(OPg.opt.random) == "on", SY.Tx(OPg.opt.random))
	used = hl.sp5:GetWidth() + hl.k5:GetWidth() + 3 * 8 + hl.v5:GetStringWidth() + hl.randOff:GetWidth()
	ok("hello switch: the row fits (random on)", used <= rowW, used .. " of " .. rowW)
	SY.Click(hl.randOff)   -- off again: the next tests start from random off
	SY.HidePage(OPg.fo)
	ok("hello switch: off again", SpokenWindDB.random == false and SY.Tx(hl.randOffText) == "Random on")
	SY.Click(hl.ok)
	ok("hello: OK closes", not hl.root.shown)
	ev, ns = Load(SpokenWindDB)
	ok("hello: not at the next login", select(5, ns.BarRefs()) == nil and SpokenWindDB.hello == true)
	ok("hello: ns.HelloShow (the ? button) shows it again", ns.HelloShow("help") == true and select(5, ns.BarRefs()).root.shown
		and LogHas("HELLO by=help"))
	hl = select(5, ns.BarRefs())
	ok("hello: shown again with random off: the switch says Random on", hl.v5.text == "Off" and hl.randOff.shown
		and SY.Tx(hl.randOffText) == "Random on", tostring(hl.v5.text))
	SY.Click(hl.close)
	ok("hello: the x closes", not hl.root.shown)
	combat = true
	ok("hello: never in combat", ns.HelloShow("help") == false and not hl.root.shown)
	combat = false
	ns.HelloShow("help")
	combat = true
	ns.BarRefs().root.scripts.OnEvent(ns.BarRefs().root, "PLAYER_REGEN_DISABLED")
	ok("hello: combat closes it", not hl.root.shown)
	combat = false
	SpokenWindDB.hello = "x"
	ev, ns = Load(SpokenWindDB)
	ok("hello: a bad flag = shown once more, then true", SpokenWindDB.hello == true and select(5, ns.BarRefs()).root.shown)
	SpokenWindDB.rwbtn, SpokenWindDB.hello = false, nil
	ev, ns = Load(SpokenWindDB)
	local nb, _, _, _, nh = ns.BarRefs()
	ok("hello: bar off = in the middle of the screen", nb == nil and nh and nh.root.shown and nh.root.point[1] == "CENTER")
	SpokenWindDB.rwbtn = true
end
SpokenWindDB.rwbtn, SpokenWindDB.rwbtnMove = false, nil
ev, ns = Load(SpokenWindDB)
ok("move: old save off -> on once, logged", SpokenWindDB.rwbtn == true and SpokenWindDB.rwbtnMove == true
	and LogHas("RWBTN move off->on") and ns.BarRefs() and ns.BarRefs().root.shown, LastLog())
reg.byVar.SpokenWind_rwbtn:SetValue(false)
local nMove = 0
for _, l in ipairs(SpokenWindDB.log) do if l:find("RWBTN move", 1, true) then nMove = nMove + 1 end end
ev, ns = Load(SpokenWindDB)
ok("move: a later off stays off", SpokenWindDB.rwbtn == false and ns.BarRefs() == nil and LastLog():find(" btn=0 ", 1, true)
	and (function()
		local k = 0
		for _, l in ipairs(SpokenWindDB.log) do if l:find("RWBTN move", 1, true) then k = k + 1 end end
		return k == nMove
	end)(), LastLog())
SpokenWindDB.rwbtn, SpokenWindDB.rwbtnMove = true, nil
ev, ns = Load(SpokenWindDB)
ok("move: old save on -> flag set, no line", SpokenWindDB.rwbtn == true and SpokenWindDB.rwbtnMove == true)
Fresh()
ok("move: new install: flag set, no line", SpokenWindDB.rwbtnMove == true and not LogHas("RWBTN move"))
ok("rewards: no chat line outside a click or slash", (function()
	for _, x in ipairs(forbidden) do if x:find("outside a click", 1, true) then return false end end
	return true
end)())
Fresh()
end

do   -- same fart for everyone (0.6.0): own block (keeps the chunk under the 200-locals limit)
local SGUID, PGUID, XGUID, DGUID = "Player-1-0000EEEE", "Player-1-0000FFFF", "Player-2-00001111", "Player-1-0000DDDD"
local MINE = ME_GUID
local STEP0 = math.floor(CLOCK0 / 10) * 10   -- server s at a step start
-- A fake client: its own load of every file (own Sync state), cooldown 0 so every fart plays.
local function Client()
	local e, n = Load(nil)
	local c = { ev = e, ns = n, db = SpokenWindDB, hooks = SY.hooks }
	c.db.cd = 0
	SY.Tiny(n)
	return c
end
local function SndOf(path) return tonumber(path and path:match("\\(%d%d)_[^\\]*%.ogg$")) end
local function Played(np) return #plays > np and SndOf(plays[#plays].path) or nil end
-- One fart line from guid reaches client c. Returns the sound played now (nil = none yet).
local function Hear(c, guid, name, text)
	local np = #plays
	c.ev.scripts.OnEvent(c.ev, "CHAT_MSG_TEXT_EMOTE", text or FartBy(name or "Zed"), name or "Zed", "", "", "", "", 0, 0,
		"", 0, 123, guid)
	return Played(np)
end
local function Msg(c, text, ch, name, prefix)
	local np = #plays
	c.ev.scripts.OnEvent(c.ev, "CHAT_MSG_ADDON", prefix or "SpWind", text, ch or "PARTY", name or "Zed")
	return Played(np)
end
local function RunTimers()
	local np = #plays
	local i = 1
	while i <= #SY.timers do
		local t = SY.timers[i]
		if t.at <= now + 1e-9 then table.remove(SY.timers, i) t.fn() else i = i + 1 end
	end
	return Played(np)
end
local function Press(c, token, both)   -- a key press: the game's emote call runs, then our post-hooks
	hw = true
	if c.hooks.DoEmote then c.hooks.DoEmote(token) end
	if both and c.hooks.PerformEmote then c.hooks.PerformEmote(token) end
	hw = false
end
local function M(guid, snd, n, pool) return ("F:1:FART:%s:%d:%d:%d"):format(guid, snd, pool or 0, n or 1) end
local function SLast(c)   -- the last line that is not a HEARD line (0.6.2 adds those after a play)
	for i = #c.db.sync, 1, -1 do
		if not c.db.sync[i]:find(" HEARD ", 1, true) then return c.db.sync[i] end
	end
	return ""
end
SY.Waits = function()   -- the sync wait timers only (Heard adds 3 s and 5 s ones)
	local w = {}
	for _, t in ipairs(SY.timers) do if t.s and t.s < 1 then w[#w + 1] = t end end
	return w
end
local function SCount(c, s)
	local k = 0
	for _, l in ipairs(c.db.sync) do if l:find(s, 1, true) then k = k + 1 end end
	return k
end

-- ---- boot + seed math
local A = Client()
ok("sync: BOOT sync=1/2 wait=150", LastLog():find(" rw=15 btn=1 sync=1/2 wait=150 tm=1 on=1 ", 1, true), LastLog())
ok("sync: prefix + the 2 emote hooks", SY.prefix == "SpWind" and A.hooks.DoEmote and A.hooks.PerformEmote
	and A.ns.syncPrefix == 1 and A.ns.syncHooks == 2)
local H = A.ns.SeedHash
ok("sync: hash = its Python twin (exact whole numbers)", H("") == 1886283521 and H("FART:Player-1-0000BBBB:100:0") == 1528189839
	and H("FART:Player-4395-0A1B2C3D:178000000:7") == 2016599633 and H(("x"):rep(300)) == 347233935, H(""))
local SP = A.ns.SeedPick
local hits, inRange, avoidOk = {}, true, true
for i = 1, 2800 do
	local s = SP("FART", "Player-1-" .. i, 178000000 + i % 7, i % 5, 14)
	if s < 1 or s > 14 or s % 1 ~= 0 then inRange = false end
	hits[s] = (hits[s] or 0) + 1
	local av = i % 14 + 1
	if SP("FART", "Player-1-" .. i, 178000000, 1, 14, av) == av then avoidOk = false end
end
local minHit = math.huge
for s = 1, 14 do minHit = math.min(minHit, hits[s] or 0) end
ok("sync: seed pick 1-14", inRange)
ok("sync: seed spread (every sound, ~200 each)", minHit >= 120, minHit)
ok("sync: seed never the one before", avoidOk)
ok("sync: one sound = 1", SP("FART", "g", 1, 0, 1) == 1 and SP("FART", "g", 1, 0, 1, 1) == 1)
ok("sync: step = server s / 10", A.ns.SyncStep() == math.floor(CLOCK0 / 10), A.ns.SyncStep())
local pcTime = time
time = function() return 0 end   -- the PC clock: never used for the step
ok("sync: step from the server clock", A.ns.SyncStep() == math.floor(CLOCK0 / 10), A.ns.SyncStep())
time = pcTime
ok("sync: addon message event on", A.ev.events.CHAT_MSG_ADDON == true)
ok("sync: pool 0 = the 14 sounds", select(1, A.ns.PoolFor("FART", "g")) == 0 and select(2, A.ns.PoolFor("FART", "g")) == 14)

-- ---- 2 clients, a farter with no addon: 3 farts in one step, all pairs match
local B
A, B = Client(), Client()
clock = STEP0 + 3
local a, b = {}, {}
for i = 1, 3 do
	now = now + 0.6
	a[i], b[i] = Hear(A, DGUID, "Dee"), Hear(B, DGUID, "Dee")
end
ok("sync: 3 farts, 3 sounds each", a[1] and a[2] and a[3] and b[1] and b[2] and b[3])
ok("sync: 3 farts, all pairs match", a[1] == b[1] and a[2] == b[2] and a[3] == b[3],
	table.concat(a, ",") .. " / " .. table.concat(b, ","))
ok("sync: never twice in a row (in a step)", a[1] ~= a[2] and a[2] ~= a[3], table.concat(a, ","))
ok("sync: log by=seed step= k=", SLast(A):find(("SYNC by=seed why=stranger gap=- who=stranger g=00DDDD step=%d k=2 snd=%d seed=%d")
	:format(math.floor(clock / 10), a[3], a[3]), 1, true), SLast(A))
ok("sync: main log has no SYNC lines", not LogHas("SYNC"))
-- next step: k starts at 0 again, still the same on both
clock = STEP0 + 13
now = now + 0.6
local a4, b4 = Hear(A, DGUID, "Dee"), Hear(B, DGUID, "Dee")
ok("sync: next step: k=0, match", a4 == b4 and SLast(A):find(" k=0 ", 1, true), SLast(A))
-- k counts before the cooldown and while off: B blocks 1 (cd 1 s), A is off for 1; the next ones match
B.db.cd = 1
A.db.on = false
now = now + 1.5
local a5, b5 = Hear(A, DGUID, "Dee"), Hear(B, DGUID, "Dee")
now = now + 0.4
local a6, b6 = Hear(A, DGUID, "Dee"), Hear(B, DGUID, "Dee")   -- 0.4 s: B's cooldown blocks it
A.db.on = true
now = now + 0.7
local a7, b7 = Hear(A, DGUID, "Dee"), Hear(B, DGUID, "Dee")
ok("sync: off = no sound (counted)", a5 == nil and a6 == nil and b5 ~= nil)
ok("sync: cooldown = no sound (counted)", b6 == nil)
ok("sync: after off + cooldown: still the same", a7 ~= nil and a7 == b7, tostring(a7) .. "/" .. tostring(b7))

-- ---- 2 clients, a fart near a step edge, arrival 0.2 s apart: how often they miss
A, B = Client(), Client()
local miss, missMsg, N = 0, 0, 1000
local nPrints = #prints
for i = 0, N - 1 do
	local T = STEP0 + 100 + i * 0.01   -- the fart on the server clock: sweeps one whole step
	local g = ("Player-1-E%05d"):format(i)
	now = now + 1
	clock = math.floor(T + 0.05) local sa = Hear(A, g, "Eve")
	clock = math.floor(T + 0.25) local sb = Hear(B, g, "Eve")
	if sa ~= sb then miss = miss + 1 end
	-- the same with the sender's message first (its own step): both play the sender's pick
	local g2 = g .. "M"
	local pick = A.ns.SeedPick("FART", g2, math.floor(math.floor(T) / 10), 0, 14)
	Msg(A, M(g2, pick, i % 999 + 1), "PARTY", "Max") Msg(B, M(g2, pick, i % 999 + 1), "PARTY", "Max")
	clock = math.floor(T + 0.05) sa = Hear(A, g2, "Max")
	clock = math.floor(T + 0.25) sb = Hear(B, g2, "Max")
	if sa ~= sb or sa ~= pick then missMsg = missMsg + 1 end
end
out(("sync edge sim: arrival 0.2 s apart, %d farts over one step: seed only %d miss (%.1f%%), message first %d miss")
	:format(N, miss, 100 * miss / N, missMsg))
ok("sync: edge, seed only: ~2% miss", miss >= 1 and miss <= 30, miss)
ok("sync: edge, message first: 0 miss", missMsg == 0, missMsg)
ok("sync: no prints from farts or messages", #prints == nPrints, prints[#prints])

-- ---- wait rule on one client
A = Client()
clock = STEP0 + 3
IsInGroup = function() return true end
now = now + 5
local s0 = Hear(A, PGUID, "Pat")
ok("sync: stranger: at once, 0 wait", s0 ~= nil and #SY.Waits() == 0
	and SLast(A):find("SYNC by=seed why=stranger gap=- who=stranger", 1, true), SLast(A))
now = now + 5
Msg(A, M(PGUID, 5, 1), "PARTY", "Pat")
now = now + 0.04
ok("sync: message first: its sound at once", Hear(A, PGUID, "Pat") == 5 and #SY.Waits() == 0
	and SLast(A):find("SYNC by=msg why=- gap=-40ms who=party", 1, true), SLast(A))
now = now + 5
ok("sync: known + emote first: waits", Hear(A, PGUID, "Pat") == nil and #SY.Waits() == 1
	and math.abs(SY.Waits()[1].s - 0.15) < 1e-9, #SY.Waits())
now = now + 0.08
ok("sync: message in the wait: plays it", Msg(A, M(PGUID, 9, 2), "PARTY", "Pat") == 9
	and SLast(A):find("SYNC by=msg why=- gap=+80ms who=party", 1, true), SLast(A))
now = now + 0.2
ok("sync: then the timer does nothing", RunTimers() == nil)
now = now + 5
Hear(A, PGUID, "Pat")
now = now + 0.149
ok("sync: not before the cap", RunTimers() == nil)
now = now + 0.001
local s4 = RunTimers()
ok("sync: no message: the seed at the cap", s4 ~= nil and SLast(A):find("SYNC by=seed why=timeout gap=- who=party", 1, true),
	SLast(A))
now = now + 0.3
ok("sync: late message: no second sound", Msg(A, M(PGUID, s4 % 14 + 1, 3), "PARTY", "Pat") == nil
	and SLast(A):find("SYNC by=late gap=+450ms who=party g=00FFFF snd=" .. (s4 % 14 + 1) .. " seed=" .. s4 .. " match=0", 1, true),
	SLast(A))
now = now + 0.1
ok("sync: late = used up (next emote: no old message)", Hear(A, PGUID, "Pat") == nil and #SY.Waits() == 1)
now = now + 0.15 RunTimers()
now = now + 1.2
Msg(A, M(PGUID, 6, 4), "PARTY", "Pat")
now = now + 0.02
ok("sync: message > 1 s after an emote: the next fart's", Hear(A, PGUID, "Pat") == 6, SLast(A))
-- the cap: slider 0-300 ms, step 10
Slash("wait 999")
ok("sync: wait capped at 300", A.db.wait == 300 and prints[#prints]:find("wait 300ms", 1, true), prints[#prints])
now = now + 5
Hear(A, PGUID, "Pat")
ok("sync: wait 300 = 0.3 s", #SY.Waits() == 1 and math.abs(SY.Waits()[1].s - 0.3) < 1e-9)
now = now + 0.3 RunTimers()
Slash("wait 0")
now = now + 5
ok("sync: wait 0: at once", Hear(A, PGUID, "Pat") ~= nil and #SY.Waits() == 0 and SLast(A):find("why=nowait", 1, true), SLast(A))
Slash("wait 155")
ok("sync: wait rounds to 10", A.db.wait == 160, A.db.wait)
Slash("wait x")
ok("sync: wait bad arg: help, no change", A.db.wait == 160 and prints[#prints]:find("wait 0-300", 1, true), prints[#prints])
Slash("wait -5")
ok("sync: wait < 0: no change", A.db.wait == 160)
ok("sync: status shows wait", (function() Slash("") return prints[#prints - 1]:find("wait 160ms", 1, true) end)(), prints[#prints - 1])
IsInGroup = function() return false end
now = now + 5
ok("sync: left the group: at once", Hear(A, PGUID, "Pat") ~= nil and #SY.Waits() == 0 and SLast(A):find("why=left", 1, true), SLast(A))
-- guild members wait too (while in the guild); seen only on SAY: no wait
IsInGuild = function() return true end
local GG, YY = "Player-1-0000GGGG", "Player-1-0000YYYY"
now = now + 5
Msg(A, M(GG, 3, 1), "GUILD", "Gus")
now = now + 0.01
ok("sync: guild message first", Hear(A, GG, "Gus") == 3 and SLast(A):find("who=guild", 1, true), SLast(A))
now = now + 5
ok("sync: guild member: waits", Hear(A, GG, "Gus") == nil and #SY.Waits() == 1)
now = now + 0.2 RunTimers()
Msg(A, M(YY, 3, 1), "SAY", "Yan")
now = now + 0.01 Hear(A, YY, "Yan")
now = now + 5
ok("sync: seen on SAY only: no wait", Hear(A, YY, "Yan") ~= nil and #SY.Waits() == 0 and SLast(A):find("why=say", 1, true), SLast(A))
-- a message waits 3 s for its emote, then it is gone
IsInGuild = function() return false end
now = now + 5
Msg(A, M(PGUID, 7, 10), "PARTY", "Pat")
now = now + 3.5
ok("sync: message > 3 s old: dropped", Hear(A, PGUID, "Pat") ~= nil and SLast(A):find("SYNC by=seed", 1, true), SLast(A))
-- one fart on 2 channels: one message
now = now + 5
Msg(A, M(PGUID, 4, 11), "PARTY", "Pat") Msg(A, M(PGUID, 4, 11), "GUILD", "Pat")
now = now + 0.02
ok("sync: 2 channels = 1 message", Hear(A, PGUID, "Pat") == 4)
now = now + 1.5
ok("sync: no copy left for the next fart", Hear(A, PGUID, "Pat") ~= nil and SLast(A):find("SYNC by=seed", 1, true), SLast(A))
-- bad messages: ignored, the next fart is the seed
issecretvalue = function(v) return v == "SECRET" end
local bad = {
	{ "SpWind", M(PGUID, 4, 20), "WHISPER" },
	{ "SpWind", M(PGUID, 15, 21), "PARTY" },   -- no sound 15
	{ "SpWind", M(PGUID, 0, 22), "PARTY" },
	{ "SpWind", M(PGUID, 4, 23, 2), "PARTY" }, -- a pool this build does not have (0.7.0: pool 1 = the race set)
	{ "SpWind", "F:2:FART:" .. PGUID .. ":4:0:24", "PARTY" },
	{ "SpWind", "F:1:DANCE:" .. PGUID .. ":4:0:25", "PARTY" },
	{ "SpWind", "F:1:FART:" .. PGUID .. ":4:0:26;x", "PARTY" },   -- not a ":" field list
	{ "Other", M(PGUID, 4, 27), "PARTY" },
	{ "SpWind", "SECRET", "PARTY" },
	{ "SpWind", M(PGUID, 4, 28), "BATTLEGROUND" },
}
for i, x in ipairs(bad) do
	now = now + 5
	Msg(A, x[2], x[3], "Pat", x[1])
	now = now + 0.02
	Hear(A, PGUID, "Pat")
	ok("sync: bad message " .. i .. " ignored", SLast(A):find("SYNC by=seed", 1, true), SLast(A))
end
-- a later build's F: unknown extra fields are ignored, the message still counts; S messages (0.6.4) are ignored
now = now + 5
Msg(A, M(PGUID, 4, 30) .. ":x:y", "PARTY", "Pat")
now = now + 0.02
ok("sync: F with 2 unknown fields plays its sound", Hear(A, PGUID, "Pat") == 4 and SLast(A):find("SYNC by=msg", 1, true), SLast(A))
now = now + 5
Msg(A, "S:1:" .. PGUID:sub(-6) .. ".1.2.3", "PARTY", "Pat")
now = now + 0.02
ok("sync: an S message is ignored, no error", Hear(A, PGUID, "Pat") ~= nil and SLast(A):find("SYNC by=seed", 1, true)
	and SCount(A, "ERR") == 0, SLast(A))
now = now + 5
Msg(A, M(MINE, 4, 29), "PARTY", ME)   -- own echo of a message: not held, not known
now = now + 0.02
Hear(A, MINE, ME, OWN_FART)
ok("sync: own message echo ignored", SLast(A):find("SYNC by=seed why=nohook gap=- who=self", 1, true), SLast(A))
now = now + 5
ok("sync: secret guid: random", Hear(A, "SECRET", "Sec") ~= nil and SLast(A):find("SYNC by=rand why=noguid", 1, true), SLast(A))
issecretvalue = nil
now = now + 5
ok("sync: no guid: random", Hear(A, nil, "Nog") ~= nil and SLast(A):find("SYNC by=rand why=noguid", 1, true), SLast(A))
local prevR, twiceR = nil, false
for _ = 1, 40 do
	now = now + 1
	local x = Hear(A, nil, "Nog")
	if x == nil or x == prevR then twiceR = true end
	prevR = x
end
ok("sync: no guid: random, never twice in a row", not twiceR)

-- ---- the other faction: no addon message can cross, so the seed at once
A = Client()
IsInGroup = function() return true end
UnitFactionGroup = function(u) return u == "player" and "Alliance" or nil end
GetPlayerInfoByGUID = function(g)
	if g == XGUID then return "Warrior", "WARRIOR", "Orc", "Orc" end
	if g == "Player-1-SKY" then return "Mage", "MAGE", "Skyborne", "Skyborne" end
	if g == "Player-1-WEIRD" then return "Mage", "MAGE", "Weird", "Weird" end
	if g == "Player-1-ERR" then error("boom") end
	return "Mage", "MAGE", "Human", "Human"
end
now = now + 5
ok("sync: other faction: seed at once", Hear(A, XGUID, "Orcy") ~= nil and #SY.Waits() == 0
	and SLast(A):find("SYNC by=seed why=xfaction gap=- who=stranger", 1, true), SLast(A))
now = now + 5
Hear(A, XGUID, "Orcy")
ok("sync: SEEN xfaction once per farter", SCount(A, "SEEN xfaction race=Orc g=001111") == 1, SCount(A, "SEEN xfaction"))
C_CreatureInfo = {
	GetRaceInfo = function(id) if id == 77 then return { clientFileString = "Skyborne" } end return nil end,
	GetFactionInfo = function(id) return id == 77 and { groupTag = "Horde" } or nil end,
}
now = now + 5
ok("sync: the game's race table first", Hear(A, "Player-1-SKY", "Sky") ~= nil and SLast(A):find("why=xfaction", 1, true), SLast(A))
now = now + 5
ok("sync: unknown race = unknown sender", Hear(A, "Player-1-WEIRD", "Wei") ~= nil and SLast(A):find("why=stranger", 1, true), SLast(A))
now = now + 5
ok("sync: race lookup error = unknown sender", Hear(A, "Player-1-ERR", "Err") ~= nil and SLast(A):find("why=stranger", 1, true), SLast(A))
now = now + 5
ok("sync: same faction = normal", Hear(A, "Player-1-HUM", "Hum") ~= nil and SLast(A):find("why=stranger", 1, true)
	and SCount(A, "SEEN") == 2, SLast(A))

-- ---- own /fart: one message from the key press
A = Client()
IsInRaid, IsInGroup = function() return true end, function() return true end
IsInGuild, IsInInstance = function() return true end, function() return true end
now = now + 5
SY.asent = {}
Press(A, "FART", true)   -- DoEmote + PerformEmote in one press = one fart
local chs = {}
for _, x in ipairs(SY.asent) do if x.m:sub(1, 4) == "F:1:" then chs[#chs + 1] = x.ch end end
ok("sync: own press: RAID, GUILD, SAY (instance), once", table.concat(chs, ",") == "RAID,GUILD,SAY", table.concat(chs, ","))
local m1 = SY.asent[1] and SY.asent[1].m or ""
local sndSent = tonumber(m1:match("^F:1:FART:Player%-1%-0000AAAA:(%d+):0:1::0%.0%.0$"))
ok("sync: message = pick, pool 0, number 1", sndSent ~= nil, m1)
ok("sync: message short", #m1 + #SY.asent[1].p <= 254 and SY.asent[1].p == "SpWind", #m1)
ok("sync: all copies the same", SY.asent[2].m == m1 and SY.asent[3].m == m1)
local o1 = Hear(A, MINE, ME, OWN_FART)
ok("sync: own echo plays the sent pick", o1 == sndSent and SLast(A):find("SYNC by=own why=- gap=- who=self", 1, true), SLast(A))
now = now + 0.1
Hear(A, MINE, ME, OWN_FART)   -- an echo with no press: nothing spare from the 2 hooks
ok("sync: 2 hooks in one press = 1 pick", SLast(A):find("SYNC by=seed why=nohook", 1, true), SLast(A))
now = now + 0.4
SY.asent = {}
Press(A, "fart")
ok("sync: 1 s send gap", #SY.asent == 0)
local o2 = Hear(A, MINE, ME, OWN_FART)
ok("sync: fast own fart: own pick, not the same", o2 ~= nil and o2 ~= o1 and SLast(A):find("by=own", 1, true), SLast(A))
now = now + 0.5
IsInInstance = function() return false end
Press(A, "FART")
ok("sync: after 1 s: sends again, number 2 (no S: 2 s gap)", #SY.asent == 2 and SY.asent[1].m:find(":0:2::3%.0%.0$"), SY.asent[1] and SY.asent[1].m)
ok("sync: no SAY outside an instance", SY.asent[2] and SY.asent[2].ch == "GUILD", SY.asent[2] and SY.asent[2].ch)
IsInInstance = function() return true end
Hear(A, MINE, ME, OWN_FART)
SY.asent = {}
now = now + 2
Press(A, "DANCE") Press(A, "") Press(A, nil) Press(A, 5)
ok("sync: other emotes send nothing", #SY.asent == 0)
ok("sync: no ownQ leak (no echo = dropped after 3 s)", (function()
	now = now + 2 Press(A, "FART") now = now + 4
	return Hear(A, MINE, ME, OWN_FART) ~= nil and SLast(A):find("why=nohook", 1, true)
end)(), SLast(A))
-- send results: a refused send is logged once per channel
SY.sendRes = 9
now = now + 5 Press(A, "FART")
now = now + 5 Press(A, "FART")
ok("sync: refused send: logged once", SCount(A, "SYNC send ch=RAID ok=0 res=9") == 1 and SCount(A, "SYNC send ch=GUILD ok=0 res=9") == 1,
	SCount(A, "ok=0"))
SY.sendRes = nil
ok("sync: ok send: logged once", SCount(A, "SYNC send ch=RAID ok=1 res=nil") == 1, SCount(A, "ok=1"))
C_ChatInfo.SendAddonMessage = function() error("x") end
now = now + 5
Press(A, "FART")
ok("sync: send error: caught (counted, not logged twice)", SCount(A, "SYNC send ch=RAID ok=0") == 1 and not LogHas("ERR"),
	SCount(A, "ok=0"))
C_ChatInfo, SendAddonMessage = nil, nil
now = now + 5
Press(A, "FART")
ok("sync: no send API: no error", not LogHas("ERR"))
A.ev.scripts.OnEvent(A.ev, "PLAYER_LOGOUT")
ok("sync: SUM at logout", SLast(A):find(" SYNC SUM msg=0 seed=2 late=0 own=3 rand=0 waited=0 sent=14 bad=9 xf=0 sTimer=0 sCapped=0 btn=0.0.0.0 rfart=0 rsec=0 classic=0$"), SLast(A))
for i = 1, 350 do A.ns.SyncLog("x" .. i) end
ok("sync: ring keeps 300", #A.db.sync == 300 and A.db.sync[300]:find(" x350$"), #A.db.sync)

-- ---- end to end: sender S (a real client) -> receiver R
local S, R = Client(), Client()
IsInGroup = function() return true end
local function SPress()   -- S's own key press + its own echo (S's player GUID)
	ME_GUID = SGUID
	SY.asent = {}
	Press(S, "FART")
	local snd = Hear(S, SGUID, ME, OWN_FART)
	ME_GUID = MINE
	return snd, SY.asent[1] and SY.asent[1].m
end
clock = STEP0 + 4
now = now + 5
local e1, t1 = SPress()
Msg(R, t1, "PARTY", "Sam")
now = now + 0.03
ok("sync: end to end: message first = same sound", e1 ~= nil and Hear(R, SGUID, "Sam") == e1)
clock = STEP0 + 9   -- the last second of a step on S
now = now + 5
local e2, t2 = SPress()
clock = STEP0 + 10  -- the next step on R
local rSeed = R.ns.SeedPick("FART", SGUID, math.floor(clock / 10), 0, 14)
ok("sync: end to end: step edge, emote first: R waits", Hear(R, SGUID, "Sam") == nil and #SY.Waits() == 1)
now = now + 0.06
ok("sync: end to end: R plays S's pick, not its own seed", Msg(R, t2, "PARTY", "Sam") == e2
	and SLast(R):find(" seed=" .. rSeed, 1, true), SLast(R))
now = now + 0.2 RunTimers()
-- a client with no hook (old client): its own fart = the seed, like everyone else
A, B = Client(), Client()
A.hooks.DoEmote, A.hooks.PerformEmote = nil, nil
clock = STEP0 + 4
now = now + 5
local own = Hear(A, MINE, ME, OWN_FART)
ME_GUID = "Player-1-0000ZZZZ"
local other = Hear(B, MINE, "Ann")
ME_GUID = MINE
ok("sync: no hook: own = seed = what others hear", own ~= nil and own == other
	and SLast(A):find("SYNC by=seed why=nohook", 1, true), SLast(A))
ok("sync: no chat line from sync", #sent == 0, #sent)
IsInGroup, IsInRaid, IsInGuild, IsInInstance = nil, nil, nil, nil
GetPlayerInfoByGUID, UnitFactionGroup, C_CreatureInfo = nil, nil, nil
end

do   -- sync: missing APIs and a bad saved wait
	SpokenWindDB = nil
	local e, n = Load({ wait = 1e9 })
	ok("sync: wait too big -> 150", SpokenWindDB.wait == 150)
	Load({ wait = 0 / 0 })
	ok("sync: wait NaN -> 150", SpokenWindDB.wait == 150)
	Load({ wait = -1 })
	ok("sync: wait < 0 -> 150", SpokenWindDB.wait == 150)
	Load({ wait = "x" })
	ok("sync: wait not a number -> 150", SpokenWindDB.wait == 150)
	Load({ wait = 300 })
	ok("sync: wait 300 kept", SpokenWindDB.wait == 300 and LastLog():find(" wait=300 ", 1, true), LastLog())
	SY.noApi = true
	e, n = Load(nil)
	SY.noApi = nil
	ok("sync: no API: BOOT sync=-1/0", LastLog():find(" sync=-1/0 wait=150 ", 1, true), LastLog())
	now = now + 5
	e.scripts.OnEvent(e, "CHAT_MSG_TEXT_EMOTE", FartBy("Bob"), "Bob", "", "", "", "", 0, 0, "", 0, 123, BOB)
	ok("sync: no API: the seed still plays", LastPlay():find("PLAY emo=FART who=other", 1, true) and not LogHas("ERR"), LastPlay())
	SY.prefixRes = false
	Load(nil)
	SY.prefixRes = nil
	ok("sync: prefix refused: BOOT sync=0/2", LastLog():find(" sync=0/2 ", 1, true), LastLog())
end

;(function()   -- 0.6.1: dev tools (/wind dev, dev folder only), toast art fallback, toast sound rules
	-- public copy: no dev tool in any public file; /wind dev there = the status
	local ptoc = assert(io.open(ADDON_DIR .. "/Spoken_Wind.toc", "rb")):read("*a")
	local hits = {}
	for line in ptoc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line:match("%S") then
			local src = assert(io.open(ADDON_DIR .. "/" .. (line:match("^%s*(.-)%s*$"):gsub("\\", "/")), "rb")):read("*a")
			for _, w in ipairs({ "DEV ach", "real restore", "ach fire", "stats reset", "dev ach" }) do
				if src:find(w, 1, true) then hits[#hits + 1] = line .. ":" .. w end
			end
		end
	end
	ok("public: no dev tool in any file", #hits == 0, table.concat(hits, ","))
	ev, ns = Load(nil, "vertical")
	local b = #prints
	Slash("dev ach list")
	ok("public: /wind dev = status", #prints == b + 2 and not LogHas("DEV"), prints[b + 1])

	-- toast: sound rules (0.8.0: no game art any more)
	ev, ns = Load(nil, "vertical")
	local R = ns.ACH
	ns.Toast(R[1])
	local T = ns.ToastFrame()
	now = now + 0.3 T.scripts.OnUpdate(T, 0.3)
	ok("toast: slides in, no game art", T.alpha == 1 and not LogHas("TOAST art="), T.alpha)
	T.scripts.OnMouseUp(T)
	SpokenWindDB.on = false
	now = now + 5
	ns.Toast(R[2])
	ok("toast: Sound Off = no sound", #TS.snd == 1 and LogHas("TOAST id=legend sound=0") and T.shown, #TS.snd)
	SpokenWindDB.on = true
	T.scripts.OnMouseUp(T)
	SOUNDKIT = { UI_BNET_TOAST = 4321 }
	now = now + 5
	ns.Toast(R[3])
	ok("toast: SOUNDKIT constant wins", #TS.snd == 2 and TS.snd[2].kit == 4321 and TS.snd[2].ch == "SFX")
	T.scripts.OnMouseUp(T)
	now = now + 0.5
	ns.Toast(R[4])
	ok("toast: 2 toasts within 1 s = 1 sound", #TS.snd == 2 and LogHas("TOAST id=thousand sound=0"), #TS.snd)
	T.scripts.OnMouseUp(T)
	TS.sndErr = true
	now = now + 5
	ns.Toast(R[5])
	ok("toast: sound error = toast, sound=0", T.shown and LogHas("TOAST id=gas sound=0") and not LogHas("ERR"))
	TS.sndErr, SOUNDKIT = nil, nil
	T.scripts.OnMouseUp(T)

	if not HAVE_DEV then return end
	-- ---- dev tools
	ev, ns = Load(nil, "vertical", true)
	local function Done() return SpokenWindDB.ach.done end
	local function Said(s)
		for i = #prints, math.max(1, #prints - 40), -1 do if tostring(prints[i]):find(s, 1, true) then return true end end
		return false
	end
	local function Clear() local t = ns.ToastFrame() while t and t.shown do t.scripts.OnMouseUp(t) end end
	clock = os.time({ year = 2026, month = 11, day = 21, hour = 12, min = 0, sec = 0 })
	now = now + 100
	Emote(OTHER_FART, "Bob", BOB)
	local first = Done().first
	ok("dev: a real earn first", first == clock and SpokenWindDB.stats.all == 1 and SpokenWindDB.dev == nil)
	Clear()
	b = #prints
	Slash("dev help")
	ok("dev: help", prints[b + 1] and prints[b + 1]:find("dev ach list|reset [id]|fire <id>|show <id|all>|undo|real · dev stats reset", 1, true)
		and prints[b + 1]:find("dev win", 1, true),
		prints[b + 1])
	b = #prints
	Slash("dev ach list")
	ok("dev: list: head + 39 rows", #prints == b + 1 + #ns.ACH and #ns.ACH == 39 and prints[b + 1]:find("ach 1/39$")
		and Said("15 first · First Wind · 11-21"), prints[b + 1])
	now = now + 5
	Slash("dev ach fire gas")
	local d = SpokenWindDB.dev
	ok("dev: fire = the real earn path", Done().gas == clock and LogHas("ACH gas toast=1") and LogHas("DEV ach fire id=gas")
		and ns.AchHas("gas"))
	ok("dev: fire: real snapshot first + test flag", d and d.real and d.real.ach.done.first == first and d.real.ach.done.gas == nil
		and d.test.gas == true and LogHas("DEV real saved") and d.real.stats.all == 1)
	ok("dev: fire: toast + sound", ns.ToastFrame().shown and ns.ToastRefs().name.text:find("Gas Giant", 1, true)
		and LogHas("TOAST id=gas sound=1"))
	Clear()
	b = #prints
	Slash("dev ach fire gas")
	ok("dev: fire twice = has it", prints[b + 1] and prints[b + 1]:find("has gas$"), prints[b + 1])
	Slash("dev ach fire zzz")
	ok("dev: unknown id", prints[#prints]:find("no id zzz$"), prints[#prints])
	b = #prints
	Slash("dev ach list")
	ok("dev: list: real saved + test mark", prints[b + 1]:find("ach 2/39 · real saved$") and Said("5 gas · Gas Giant · 11-21 test"),
		prints[b + 1])
	Slash("dev ach reset")
	ok("dev: reset all", next(Done()) == nil and LogHas("DEV ach reset id=all") and not ns.AchHas("first")
		and SpokenWindDB.dev.real.ach.done.first == first)
	Slash("dev ach undo")
	ok("dev: undo = back one step", Done().first == first and Done().gas == clock and SpokenWindDB.dev.test.gas
		and LogHas("DEV ach undo id=reset all") and SpokenWindDB.dev.undo == nil)
	b = #prints
	Slash("dev ach undo")
	ok("dev: undo once only", prints[b + 1]:find("no undo$"), prints[b + 1])
	ok("dev: sounds heard so far", next(SpokenWindDB.ach.heard) ~= nil)
	Slash("dev ach reset orchestra")
	ok("dev: reset one: its progress too", next(SpokenWindDB.ach.heard) == nil and LogHas("DEV ach reset id=orchestra"))
	Slash("dev ach reset 15")
	ok("dev: reset one by number", Done().first == nil and Done().gas ~= nil and LogHas("DEV ach reset id=first"))
	-- real farts while testing: own /fart at night = real earns (first again, night, selfstarter)
	clock = os.time({ year = 2026, month = 11, day = 22, hour = 2, min = 0, sec = 0 })
	now = now + 100
	Emote(OWN_FART, ME, ME_GUID)
	ok("dev: real earns while testing", Done().first == clock and Done().night and Done().selfstarter
		and SpokenWindDB.stats.all == 2, SpokenWindDB.stats.all)
	Clear()
	SpokenWindDB.stats.best = 4   -- a real best while testing
	Slash("dev stats reset")
	ok("dev: stats reset", SpokenWindDB.stats.best == 0 and SpokenWindDB.stats.all == 0 and SpokenWindDB.stats.today == 0 and LogHas("DEV stats reset"))
	now = now + 100
	Emote(OTHER_FART, "Bob", BOB)
	Clear()
	ok("dev: counts on after the reset", SpokenWindDB.stats.all == 1)
	SpokenWindDB.stats.best = 2   -- a real best after the reset, lower than before
	Slash("dev stats undo")
	ok("dev: undo stats reset keeps the fart since", SpokenWindDB.stats.all == 3 and Done().night ~= nil, SpokenWindDB.stats.all)
	ok("dev: undo: best is a max, not a sum", SpokenWindDB.stats.best == 4, SpokenWindDB.stats.best)
	now = now + 5
	b = #prints
	Slash("dev ach show 3")
	local t = ns.ToastFrame()
	ok("dev: show = toast + sound only", t.shown and ns.ToastRefs().name.text:find("Full Orchestra", 1, true) and Done().orchestra == nil
		and LogHas("DEV ach show id=orchestra") and LogHas("TOAST id=orchestra sound=1"))
	Clear()
	Slash("dev ach show all")
	local n = 0
	while t.shown and n < 50 do n = n + 1 t.scripts.OnMouseUp(t) end
	ok("dev: show all = 39 toasts, nothing saved", n == 39 and Done().orchestra == nil and Done().super == nil, n)
	-- a reload keeps the dev state and the totals
	ev, ns = Load(SpokenWindDB, "vertical", true)
	ok("dev: reload keeps snapshot, test flag, total", SpokenWindDB.dev.real and SpokenWindDB.dev.test.gas
		and SpokenWindDB.stats.all == 3, SpokenWindDB.stats.all)
	Slash("dev ach real")
	local dn = Done()
	local rn, rk = LastLog():match("DEV real restore n=(%d+) kept=(%d+)$")
	ok("dev: real = snapshot + real earns, no test earns", dn.first == first and dn.night and dn.selfstarter and dn.gas == nil
		and tonumber(rk) >= 2 and tonumber(rn) == tonumber(rk) + 1 and SpokenWindDB.dev == nil and not ns.AchHas("gas") and ns.AchHas("night"),
		(function() local k = {} for id in pairs(dn) do k[#k + 1] = id end return table.concat(k, ",") end)())
	ok("dev: real: farts while testing kept", SpokenWindDB.stats.all == 3, SpokenWindDB.stats.all)
	ok("dev: real: best = the larger one", SpokenWindDB.stats.best == 4, SpokenWindDB.stats.best)
	b = #prints
	Slash("dev ach real")
	ok("dev: real once", prints[b + 1]:find("no real saved$"), prints[b + 1])
	Slash("dev ach fire tuba")
	ok("dev: next change = a fresh snapshot", SpokenWindDB.dev.real.ach.done.night and SpokenWindDB.dev.test.tuba)
	Slash("dev ach real")
	ok("dev: real again: tuba gone", Done().tuba == nil and Done().night ~= nil and not ns.AchHas("tuba"))
	Clear()
	ok("dev: nothing sent", #sent == 0)
end)()

;(function()   -- dev 1.5.0: the test window = the sw-dev screen (own function: the main chunk is near 200 locals)
	if not HAVE_DEV then return end
	local forb0 = #forbidden
	local MEDIA = "Interface\\AddOns\\Spoken_Wind\\Media\\"
	local function Win() return (SY.dns.DevRefs()) end
	local function Clear() local t = ns.ToastFrame() while t and t.shown do t.scripts.OnMouseUp(t) end end
	local function Under(f, root)
		while f do if f == root then return true end f = f.parent end
		return false
	end
	local function Cells(w)   -- the shown grid cells, in list order
		local t = {}
		for _, f in ipairs(frames) do if f._devRow and f.shown and Under(f, w.grid) then t[#t + 1] = f end end
		return t
	end
	local function Cell(w, id)
		for _, c in ipairs(Cells(w)) do if c._devRow.id == id then return c end end
		error("no cell " .. id)
	end
	local function CL(w, id, btn) SY.Click(Cell(w, id), btn) end
	local function HasTex(c, p)
		for _, t in ipairs(c.textures or {}) do if t.path == p then return true end end
		return false
	end
	local function Raw(n) return (n._lookText or n).text or "" end
	local function Pk(w) return SY.Tx(w.pickN) end
	local function Lines(w)
		local t = {}
		for _, r in ipairs(SY.ListRows(w.log)) do t[#t + 1] = r[1] end
		return t
	end
	local function Count(s)
		local n = 0
		for _, l in ipairs(SpokenWindDB.log) do if l:find(s, 1, true) then n = n + 1 end end
		return n
	end
	local function Fresh()
		ev, ns = Load(nil, "vertical", true)
		clock = os.time({ year = 2026, month = 11, day = 21, hour = 12, min = 0, sec = 0 })
		now = now + 100
	end

	-- the source: no keys, no Esc, no game tooltip or game colour table, no ticker
	local src = assert(io.open(DEV_DIR .. "/Dev.lua", "rb")):read("*a")
	ok("devwin src: no Esc hook, no tooltip, no game colours, no sample text", not src:find("hooks.esc", 1, true)
		and not src:find("GameTooltip", 1, true) and not src:find("ITEM_QUALITY_COLORS", 1, true)
		and not src:find(".sample(", 1, true) and not src:find("OnKeyDown", 1, true))

	-- open / close / toggle
	Fresh()
	local b = #prints
	Slash("dev")
	local w = Win()
	ok("devwin: /wind dev opens", w and w.root.shown and Count("DEVWIN open") == 1 and #prints == b)
	Slash("dev")
	ok("devwin: /wind dev again closes", not w.root.shown and Count("DEVWIN close") == 1)
	Slash("dev win")
	ok("devwin: /wind dev win opens", w.root.shown and Count("DEVWIN open") == 2 and Win() == w)
	Slash("dev win")
	ok("devwin: /wind dev win closes", not w.root.shown and Count("DEVWIN close") == 2)
	b = #prints
	Slash("dev help")
	ok("devwin: dev help prints the help", #prints == b + 1 and prints[b + 1]:find("dev win", 1, true)
		and prints[b + 1]:find("dev ach list|reset [id]|fire <id>|show <id|all>|undo|real", 1, true), prints[b + 1])
	b = #prints
	Slash("dev zzz")
	ok("devwin: unknown word prints the help", #prints == b + 1 and prints[b + 1]:find("dev win", 1, true) and not w.root.shown)
	Slash("dev")
	ok("devwin: window did not write the help or error", not LogHas("ERR"))

	-- the screen: sw-dev on Dev's own Look copy, own frames only
	local dL = SY.dns.Look
	ok("devwin: the sw-dev screen on Dev's Look copy, named, DIALOG", dL ~= ns.Look and _G.SpokenWindDev == w.root
		and w.root.parent == UIParent and w.root.strata == "DIALOG" and w.root.toplevel == true)
	ok("devwin: drag by the head, starts at the top centre", w.root.movable and w.head.drag == "LeftButton"
		and w.head.scripts.OnDragStart and w.root.point and w.root.point[1] == "TOP" and w.root.point[2] == UIParent
		and w.root.point[5] == -120, w.root.point and w.root.point[1])
	w.head.scripts.OnDragStart(w.head)
	ok("devwin: drag starts moving", w.root.moving == true)
	w.head.scripts.OnDragStop(w.head)
	ok("devwin: drag stops moving, no saved spot", w.root.moving == false and dL.store == nil)
	local kb, nf = false, 0
	for _, f in ipairs(frames) do
		if Under(f, w.root) then
			nf = nf + 1
			if f.kb ~= nil or f.prop ~= nil then kb = true end
		end
	end
	ok("devwin: no keyboard, no Esc hook, no Esc table", nf > 40 and not kb and dL.hooks.esc == nil and UISpecialFrames == nil, nf)
	ok("devwin: fixed width 320", w.root:GetWidth() == 320, w.root:GetWidth())
	local glyph = false
	for _, rg in ipairs({ w.close:GetRegions() }) do if rg.text == "\195\151" then glyph = true end end
	ok("devwin: x glyph + labels, empty name line", glyph and SY.Tx(w.msgsText) == "Msgs" and SY.Tx(w.pickL) == "L toast"
		and SY.Tx(w.pickR) == "R earn" and SY.Tx(w.resetAchText) == "Reset ach" and SY.State(w.resetAch) == "base"
		and Pk(w) == "", SY.Tx(w.resetAchText))

	-- the grid: one cell per row, 10 a line, off = not earned
	local cells = Cells(w)
	local order, st = true, true
	for i, row in ipairs(ns.ACH) do
		local c = cells[i]
		if not c or c._devRow ~= row then order = false end
		if c and SY.State(c) ~= (SpokenWindDB.ach.done[row.id] ~= nil and "base" or "off") then st = false end
	end
	ok("devwin: one cell per row, 39 rows, list order", #cells == #ns.ACH and #ns.ACH == 39 and order, #cells)
	ok("devwin: off = not earned", st)
	local empty, lines = 0, {}
	for _, f in ipairs(frames) do
		if f.otype == "Button" and Under(f, w.grid) and f.parent.shown then
			lines[f.parent] = true
			if not f.shown then empty = empty + 1 end
		end
	end
	local nl = 0
	for _ in pairs(lines) do nl = nl + 1 end
	ok("devwin: 4 lines, the last hides its 1 empty cell", nl == 4 and empty == 1, nl .. " " .. empty)
	ok("devwin: cell icon = the ach art, logo = First Wind", HasTex(Cell(w, "gas"), MEDIA .. "ach\\gas")
		and w.logo.path == MEDIA .. "ach\\first", w.logo.path)

	-- hover = the name line (quality colour, has / no)
	local gas = Cell(w, "gas")
	gas.scripts.OnEnter(gas)
	ok("devwin: hover = the name line", Pk(w) == "Gas Giant\194\160\194\183 no"
		and Raw(w.pickN):find(dL.Hex(dL.palette.epic) .. "Gas Giant|r", 1, true) ~= nil, Raw(w.pickN))

	-- left click = toast only, right click = real earn
	local nd0 = 0
	for _ in pairs(SpokenWindDB.ach.done) do nd0 = nd0 + 1 end
	now = now + 5
	CL(w, "tuba")
	local nd = 0
	for _ in pairs(SpokenWindDB.ach.done) do nd = nd + 1 end
	ok("devwin: left click = toast", ns.ToastFrame().shown and ns.ToastRefs().name.text:find("Tuba Tuesday", 1, true)
		and LogHas("DEV ach show id=tuba") and LogHas("DEVWIN click btn=toast:tuba"))
	ok("devwin: left click saves nothing, names the cell", nd == nd0 and SpokenWindDB.ach.done.tuba == nil
		and (SpokenWindDB.dev == nil or SpokenWindDB.dev.real == nil) and Pk(w) == "Tuba Tuesday\194\160\194\183 no"
		and Raw(w.pickN):find(dL.Hex(dL.palette.uncommon) .. "Tuba Tuesday|r", 1, true) ~= nil, Raw(w.pickN))
	Clear()
	now = now + 5
	CL(w, "gas", "RightButton")
	ok("devwin: right click = real earn", SpokenWindDB.ach.done.gas == clock and LogHas("ACH gas toast=1") and LogHas("DEV ach fire id=gas")
		and LogHas("DEVWIN click btn=fire:gas") and SpokenWindDB.dev and SpokenWindDB.dev.test.gas)
	ok("devwin: earned = base, the name line says has", SY.State(Cell(w, "gas")) == "base" and SY.State(Cell(w, "tuba")) == "off"
		and Pk(w) == "Gas Giant\194\160\194\183 has", Pk(w))
	Clear()
	CL(w, "gas", "MiddleButton")
	ok("devwin: other button does nothing", Count("DEVWIN click btn=") == 2)

	-- undo / real
	now = now + 5
	SY.Click(w.undo)
	ok("devwin: Undo button", SpokenWindDB.ach.done.gas == nil and LogHas("DEV ach undo id=fire gas") and LogHas("DEVWIN click btn=undo")
		and SY.State(Cell(w, "gas")) == "off" and Pk(w) == "Gas Giant\194\160\194\183 no")
	Clear()
	now = now + 5
	CL(w, "tuba", "RightButton")
	Clear()
	SY.Click(w.real)
	ok("devwin: Real button", SpokenWindDB.dev == nil and SpokenWindDB.ach.done.tuba == nil and LogHas("DEV real restore")
		and LogHas("DEVWIN click btn=real"))

	-- reset needs two clicks inside 3 s: "Sure? 3", counts down, goes back
	Slash("dev")   -- close
	Slash("dev")   -- open
	now = now + 5
	CL(w, "gas", "RightButton")
	Clear()
	local st0 = SpokenWindDB.stats.all
	SpokenWindDB.stats.all = 5
	SpokenWindDB.stats.best = 3
	local nTimers = #SY.timers
	SY.Click(w.resetAch)
	local tm = {}
	for i = nTimers + 1, #SY.timers do tm[#tm + 1] = SY.timers[i].s end
	ok("devwin: 1st reset click only arms: warn, Sure? 3", SpokenWindDB.ach.done.gas ~= nil and SY.Tx(w.resetAchText) == "Sure? 3"
		and SY.State(w.resetAch) == "warn" and Count("DEV ach reset id=all") == 0 and LogHas("DEVWIN click btn=arm:resetach"),
		SY.Tx(w.resetAchText))
	ok("devwin: 3 redraws at 1 s, 2 s, 3.1 s", #tm == 3 and tm[1] == 1 and tm[2] == 2 and math.abs(tm[3] - 3.1) < 1e-6,
		table.concat(tm, ","))
	now = now + 1
	SY.timers[nTimers + 1].fn()
	ok("devwin: Sure? counts down", SY.Tx(w.resetAchText) == "Sure? 2" and SY.State(w.resetAch) == "warn", SY.Tx(w.resetAchText))
	SY.Click(w.resetAch)
	ok("devwin: 2nd click within 3 s resets", SpokenWindDB.ach.done.gas == nil and Count("DEV ach reset id=all") == 1
		and LogHas("DEVWIN click btn=resetach") and SY.Tx(w.resetAchText) == "Reset ach" and SY.State(w.resetAch) == "base")
	now = now + 5
	CL(w, "gas", "RightButton")
	Clear()
	SY.Click(w.resetAch)
	now = now + 3.1
	SY.Click(w.resetAch)
	ok("devwin: 2nd click after 3.1 s only arms again", SpokenWindDB.ach.done.gas ~= nil and Count("DEV ach reset id=all") == 1
		and SY.Tx(w.resetAchText) == "Sure? 3")
	now = now + 3.2
	for i = #SY.timers, 1, -1 do if math.abs(SY.timers[i].s - 3.1) < 1e-6 then SY.timers[i].fn() end end
	ok("devwin: Sure? goes back after 3 s", SY.Tx(w.resetAchText) == "Reset ach" and SY.State(w.resetAch) == "base")
	SY.Click(w.resetAch)
	ok("devwin: reset click after the label went back arms", SpokenWindDB.ach.done.gas ~= nil and SY.Tx(w.resetAchText) == "Sure? 3")
	ok("devwin: reset ach does not arm stats", SY.Tx(w.resetStatsText) == "Reset stats" and SY.State(w.resetStats) == "base")
	SY.Click(w.resetStats)
	ok("devwin: stats 1st click: nothing changed", SpokenWindDB.stats.all == 5 and SY.Tx(w.resetStatsText) == "Sure? 3"
		and SY.State(w.resetStats) == "warn" and LogHas("DEVWIN click btn=arm:resetstats"))
	now = now + 1
	SY.Click(w.resetStats)
	ok("devwin: stats 2nd click resets", SpokenWindDB.stats.all == 0 and SpokenWindDB.stats.best == 0 and LogHas("DEV stats reset")
		and LogHas("DEVWIN click btn=resetstats"))
	SpokenWindDB.stats.all = st0

	-- pair on/off + tabs + Thanks
	local calls, orig = {}, SlashCmdList.SPOKENWIND
	SlashCmdList.SPOKENWIND = function(m) calls[#calls + 1] = m return orig(m) end
	SY.Click(w.pairOn)
	SY.Click(w.pairOff)
	SY.Click(w.tClassic)
	SY.Click(w.tSocial)
	SY.Click(w.tColl)
	SlashCmdList.SPOKENWIND = orig
	ok("devwin: pair + tab buttons call the public slash", calls[1] == "pair" and calls[2] == "pair off" and calls[3] == "ach classic"
		and calls[4] == "ach social" and calls[5] == "ach collection" and #calls == 5, table.concat(calls, "|"))
	ok("devwin: Collection tab shown", w.tColl.shown and not LogHas("ERR devwin"))
	for _, n in ipairs({ "pairon", "pairoff", "tab:classic", "tab:social", "tab:collection" }) do
		if not LogHas("DEVWIN click btn=" .. n) then ok("devwin: click logged " .. n, false) end
	end
	local na, ns0, th = #SY.asent, #sent, Count("DEV thanks ok=")
	SY.Click(w.thanks)
	ok("devwin: Thanks once per click", Count("DEV thanks ok=") == th + 1 and LogHas("DEVWIN click btn=thanks"))
	SY.Click(w.thanks)
	ok("devwin: Thanks twice = 2", Count("DEV thanks ok=") == th + 2)
	ok("devwin: Thanks unpaired sends nothing", #SY.asent == na and #sent == ns0)

	-- an error inside a click: ERR devwin, the window still draws, nothing thrown
	SlashCmdList.SPOKENWIND = function() error("slash boom") end
	local cok = pcall(SY.Click, w.pairOn)
	SlashCmdList.SPOKENWIND = orig
	ok("devwin: click error = ERR devwin, no throw", cok and LogHas("ERR devwin") and LogHas("slash boom")
		and Lines(w)[1]:find("slash boom", 1, true) ~= nil, Lines(w)[1])

	-- Fart: one local sound, nothing else
	local rnd = math.random
	local files = {}   -- the dev window keeps its own list of the old 14
	for i = 1, ns.BASE_N do files[i] = ns.EMOTES.FART.sounds[i] end
	local bad = {}
	local farts0, stats0, heard0 = #SpokenWindDB.farts, SpokenWindDB.stats.all, 0
	for _ in pairs(SpokenWindDB.ach.heard) do heard0 = heard0 + 1 end
	na, ns0 = #SY.asent, #sent
	for i = 1, #files do
		math.random = function() return i end
		local np = #plays
		SY.Click(w.fart)
		local p = plays[np + 1]
		local want = MEDIA .. "fart\\" .. files[i].file .. ".ogg"
		if #plays ~= np + 1 or not p or p.path ~= want or p.ch ~= "SFX" then bad[#bad + 1] = i end
		if not LogHas("DEVWIN fart key=" .. files[i].file) then bad[#bad + 1] = "log" .. i end
	end
	math.random = rnd
	ok("devwin: Fart plays each of the 14 files once", #bad == 0 and #files == 14, table.concat(bad, ","))
	local heard1 = 0
	for _ in pairs(SpokenWindDB.ach.heard) do heard1 = heard1 + 1 end
	ok("devwin: Fart: no log entry, no count, no dex, no message", #SpokenWindDB.farts == farts0 and SpokenWindDB.stats.all == stats0
		and heard1 == heard0 and #SY.asent == na and #sent == ns0 and Count("DEVWIN click btn=fart") == 14)
	SpokenWindDB.ch = "Master"
	local np = #plays
	SY.Click(w.fart)
	ok("devwin: Fart uses the sound channel", plays[np + 1] and plays[np + 1].ch == "Master")
	SpokenWindDB.ch = nil
	np = #plays
	SY.Click(w.fart)
	ok("devwin: Fart without a channel = SFX", plays[np + 1] and plays[np + 1].ch == "SFX")
	local pf = PlaySoundFile
	PlaySoundFile = function() error("snd boom") end
	SY.Click(w.fart)
	PlaySoundFile = pf
	ok("devwin: sound error = ERR devwin, no throw", LogHas("ERR devwin") and LogHas("snd boom"))

	-- status + the 5 newest log lines
	table.insert(SpokenWindDB.log, "11-21 12:00:00 BOOT v=0.6.2.1 farts=7 heard=3 dex=5 dev=1")
	table.insert(SpokenWindDB.log, "11-21 12:00:01 ERR x")
	table.insert(SpokenWindDB.sync, "11-21 12:00:02 ERR y")
	SY.Click(w.close)
	ok("devwin: x closes", not w.root.shown and LogHas("DEVWIN click btn=close") and LogHas("DEVWIN close"))
	local errs = 0
	for _, l in ipairs(SpokenWindDB.log) do if l:find("ERR", 1, true) then errs = errs + 1 end end
	errs = errs + 1
	Slash("dev")
	local text = SY.Tx(w.status)
	ok("devwin: status without len", text:find("^v0.6.2.1 · farts 7 · heard 3 · dex 5 · ERR " .. errs .. "$") and not text:find("len", 1, true), text)
	ok("devwin: ERR > 0 = red", Raw(w.status):find(dL.Hex(dL.palette.bad) .. "ERR " .. errs .. "|r", 1, true) ~= nil, Raw(w.status))
	local last = {}
	for i = #SpokenWindDB.log, #SpokenWindDB.log - 4, -1 do last[#last + 1] = (SpokenWindDB.log[i]:gsub("^%d%d%-%d%d ", "")) end
	local got = Lines(w)
	local same = #got == 5
	for i = 1, 5 do if got[i] ~= last[i] then same = false end end
	ok("devwin: 5 newest log lines, newest on top, no date", same and got[1] == "12:00:00 DEVWIN open", got[1])
	table.insert(SpokenWindDB.log, "11-21 12:00:03 BOOT v=0.6.3 farts=9 heard=4 dex=6 len=13/14 dev=1")
	CL(w, "gas")
	Clear()
	text = SY.Tx(w.status)
	ok("devwin: status with len, refreshed after a click", text:find("^v0.6.3 · farts 9 · heard 4 · dex 6 · len 13/14 · ERR ") ~= nil, text)
	Slash("dev")

	-- a live 0.6.2.1 shape: no Collection rows; no BOOT at all
	Fresh()
	for i = #ns.ACH, 1, -1 do if ns.ACH[i].tab == "collection" then table.remove(ns.ACH, i) end end
	SpokenWindDB.log = {}
	Slash("dev")
	local w2 = Win()
	local dL2 = SY.dns.Look
	ok("devwin: rows from api.ACH, no fixed count", #Cells(w2) == #ns.ACH and #ns.ACH < 38 and w2 ~= w, #Cells(w2))
	ok("devwin: no Collection button without Collection rows", not w2.tColl.shown and w2.tClassic.shown and w2.tSocial.shown)
	ok("devwin: no BOOT line = no error, ERR 0 green", SY.Tx(w2.status) == "no BOOT · ERR 0"
		and Raw(w2.status):find(dL2.Hex(dL2.palette.good) .. "ERR 0|r", 1, true) ~= nil and not LogHas("ERR"), SY.Tx(w2.status))
	Slash("dev")
	ok("devwin: nothing sent", #sent == 0)
	ok("devwin: nothing forbidden", #forbidden == forb0, forbidden[forb0 + 1])
end)()

;(function()   -- dev 1.4.0: the Msgs view (own function: the main chunk is near 200 locals)
	if not HAVE_DEV then return end
	local forb0 = #forbidden
	local function Win() return (SY.dns.DevRefs()) end
	local function Mv() return select(2, SY.dns.DevRefs()) end   -- the sw-dev-msgs refs (nil before the first Msgs click)
	local function Row(i, raw) return SY.ListRows(Mv().msgs, raw)[i] end   -- t dir ch kind msg
	local function Count(s)
		local n = 0
		for _, l in ipairs(SpokenWindDB.log) do if l:find(s, 1, true) then n = n + 1 end end
		return n
	end
	local function Lis()   -- the dev listener: an own frame with CHAT_MSG_ADDON (not Spoken Wind's)
		for _, f in ipairs(frames) do if f ~= ev and f.events.CHAT_MSG_ADDON then return f end end
	end
	local function In(text, ch, name, prefix)   -- one CHAT_MSG_ADDON to the dev listener
		local l = Lis()
		l.scripts.OnEvent(l, "CHAT_MSG_ADDON", prefix or "SpWind", text, ch or "PARTY", name or "Pat-Realm", "Pat", 0, "", 0, "", 0, 0)
	end
	local function Out(m, ch, tgt, prefix)   -- one addon send through the hooked API (as inside a key press)
		hw = true
		local r = C_ChatInfo.SendAddonMessage(prefix or "SpWind", m, ch, tgt)
		hw = false
		return r
	end
	local function Ring() return type(SpokenWindDB.dev) == "table" and SpokenWindDB.dev.msgs or {} end
	local function RL(i) local r = Ring() return r[#r + 1 - (i or 1)] or "" end   -- i = 1: the newest
	local function Body(l) return (l:gsub("^%d%d%-%d%d %d%d:%d%d:%d%d ", "")) end
	local K4 = { ["F:1:"] = "fart", ["H:1:"] = "heard", ["S:1:"] = "board", ["T:1:"] = "pair" }
	local function Kind(m) return (m == "P:1" or m == "Q:1") and "ping" or K4[m:sub(1, 4)] or "other" end
	local function Boot(db)
		ev, ns = Load(db, "vertical", true)
		IsInGroup = function() return true end
		IsInGuild = function() return true end
		IsInRaid = function() return false end
		SpokenWindDB.cd = 0
		SY.Tiny(ns)
		willPlay = true
	end

	-- login: one hook, one listener, one log line
	Boot(nil)
	local l = Lis()
	local nev = 0
	if l then for _ in pairs(l.events) do nev = nev + 1 end end
	ok("devmsg: login = the post-hook + an own listener, one line", Count("DEVMSG on hook=1 listen=1") == 1
		and type(SY.hooks.SendAddonMessage) == "function" and l ~= nil and nev == 1 and l.parent == nil
		and l.scripts.OnEvent ~= nil, LastLog())
	ok("devmsg: no ring before a message", SpokenWindDB.dev == nil or SpokenWindDB.dev.msgs == nil)
	local src = assert(io.open(DEV_DIR .. "/Dev.lua", "rb")):read("*a")
	local _, nHook = src:gsub("hooksecurefunc", "")
	ok("devmsg src: post-hook only: never sets, never calls the send", not src:find("SendAddonMessage%s*=")
		and not src:find("SendAddonMessage%(") and not src:find("SendChatMessage", 1, true)
		and src:find('pcall(hooksecurefunc, C_ChatInfo, "SendAddonMessage", Hook)', 1, true) ~= nil
		and src:find('RegisterEvent("CHAT_MSG_ADDON")', 1, true) ~= nil, nHook)
	ok("devmsg src: no timer, no Blizzard tables, no keys", not src:find("NewTicker", 1, true) and not src:find("OnUpdate", 1, true)
		and not src:find("UISpecialFrames", 1, true) and not src:find("SetCVar", 1, true) and not src:find("EnableKeyboard", 1, true)
		and not src:find("ScrollFrame", 1, true))

	-- out: Spoken Wind's own fart, to the group and the guild
	local na = #SY.asent
	hw = true SY.hooks.DoEmote("FART") hw = false
	Emote(OWN_FART, ME, ME_GUID)
	local fs, good, nF, nS = {}, true, {}, 0
	for i = na + 1, #SY.asent do fs[#fs + 1] = SY.asent[i] end
	local r = Ring()
	for i, x in ipairs(fs) do
		local want = ("out %s %s - %s"):format(x.ch == "WHISPER" and "WHSP" or x.ch, Kind(x.m), x.m)
		if Body(r[#r - #fs + i] or "") ~= want then good = false end
		if Kind(x.m) == "fart" then nF[#nF + 1] = x.ch end
		if Kind(x.m) == "board" then nS = nS + 1 end
	end
	ok("devmsg: own fart = one out line per send (the send still runs)", #fs >= 2 and #r == #fs and good
		and table.concat(nF, ",") == "PARTY,GUILD" and #fs == 2 + nS
		and r[1]:find("^%d%d%-%d%d %d%d:%d%d:%d%d out PARTY fart %- F:1:FART:"), table.concat(r, " / "))

	-- in, echo, kinds, channels, names
	In("F:1:FART:Player-1-0000BBBB:9:0:1", "PARTY", "Pat-Realm")
	ok("devmsg: in = sender name, no realm", Body(RL(1)) == "in PARTY fart Pat F:1:FART:Player-1-0000BBBB:9:0:1", RL(1))
	In("F:1:FART:Player-1-0000AAAA:9:0:1", "PARTY", ME .. "-Realm")
	In("F:1:FART:Player-1-0000AAAA:9:0:1", "GUILD", ME)
	ok("devmsg: own echo = echo (with or without realm)", Body(RL(2)) == "echo PARTY fart " .. ME .. " F:1:FART:Player-1-0000AAAA:9:0:1"
		and Body(RL(1)) == "echo GUILD fart " .. ME .. " F:1:FART:Player-1-0000AAAA:9:0:1", RL(1))
	In("F:1:FART:Player-1-0000CCCC:9:0:1", "PARTY", ME .. "x")
	ok("devmsg: a longer name is not me", Body(RL(1)):sub(1, 9) == "in PARTY ", RL(1))
	local KN = {
		{ "H:1:Player-1-0000AAAA:3:Pat", "RAID", "heard", "RAID" },
		{ "S:1:abc", "GUILD", "board", "GUILD" },
		{ "S:1:abc", "INSTANCE_CHAT", "board", "INST" },
		{ "T:1:x", "WHISPER", "pair", "WHSP" },
		{ "P:1", "WHISPER", "ping", "WHSP" },
		{ "Q:1", "WHISPER", "ping", "WHSP" },
		{ "P:1:", "WHISPER", "other", "WHSP" },
		{ "F:2:x", "SAY", "other", "SAY" },
		{ "Z", "CHANNEL", "other", "CHANN" },
	}
	local bad
	for _, k in ipairs(KN) do
		In(k[1], k[2], "Bobbybobbybob-Realm")
		if Body(RL(1)) ~= ("in %s %s Bobbybobby %s"):format(k[4], k[3], k[1]) then bad = RL(1) end
	end
	ok("devmsg: kinds + channels + names cut to 10", bad == nil, bad)
	In("H:1:x", "PARTY", "")
	ok("devmsg: no sender = -", Body(RL(1)) == "in PARTY heard - H:1:x", RL(1))
	local n0 = #Ring()
	In("F:1:FART:x:1:0:1", "PARTY", "Pat", "OtherAddon")
	Out("F:1:FART:x:1:0:1", "PARTY", nil, "OtherAddon")
	In(nil, "PARTY", "Pat")
	In(5, "PARTY", "Pat")
	ok("devmsg: other prefix or no text = no line", #Ring() == n0, RL(1))
	issecretvalue = function(v) return v == "SECRET" end
	In("SECRET", "PARTY", "Pat")
	In("F:1:FART:x:1:0:1", "PARTY", "Pat", "SECRET")
	Out("SECRET", "PARTY")
	local n1 = #Ring()
	In("H:1:y", "SECRET", "SECRET")
	issecretvalue = nil
	ok("devmsg: hidden values never read", n1 == n0 and #Ring() == n0 + 1 and Body(RL(1)) == "in ? heard - H:1:y"
		and not LogHas("ERR"), RL(1))
	Out("P:1", "WHISPER", "Bob-Other")
	ok("devmsg: out whisper = the target name", Body(RL(1)) == "out WHSP ping Bob P:1", RL(1))
	In(("x"):rep(300), "PARTY", "Pat")
	ok("devmsg: payload cut to 120", Body(RL(1)) == "in PARTY other Pat " .. ("x"):rep(120), #RL(1))

	-- the window: Msgs button, the sw-dev-msgs panel under it, counts, 12 newest on top
	UISpecialFrames = nil
	local nsent, nasent = #sent, #SY.asent
	Slash("dev")
	local w = Win()
	local dL = SY.dns.Look
	local function H(c) return dL.Hex(dL.palette[c]) end
	local h0 = w.root:GetHeight()
	ok("devmsg: Msgs button in the title row, no panel yet", w.msgs and SY.Tx(w.msgsText) == "Msgs" and Mv() == nil
		and (SY.State(w.msgs) or "base") == "base")   -- nil = no state call yet = the base look
	SY.Click(w.msgs)
	local m = Mv()
	ok("devmsg: Msgs on = the panel under the window, logged", m and m.root.shown and _G.SpokenWindDevMsgs == m.root
		and m.root.parent == w.root and m.root.point and m.root.point[1] == "TOPLEFT" and m.root.point[2] == w.root
		and m.root.point[3] == "BOTTOMLEFT" and m.root.point[4] == 0 and m.root.point[5] == -2 and SY.State(w.msgs) == "on"
		and Count("DEVWIN click btn=msgs") == 1 and Count("DEVWIN msgs on") == 1, m and m.root.point and m.root.point[1])
	ok("devmsg: the window keeps its size, same width", w.root:GetHeight() == h0 and w.root:GetWidth() == 320
		and m.root:GetWidth() == 320, w.root:GetHeight())
	ok("devmsg: no keyboard, no Esc table, 12 rows", m.root.kb == nil and UISpecialFrames == nil and #SY.ListRows(m.msgs) == 12)
	-- in: fart 2 (Pat, Testerx), heard 3, board 2, pair 1, ping 2, other 4; out: the own fart + 1 ping
	ok("devmsg: counts this session", SY.Tx(m.c1) == ("out %d · in 14 · echo 2 · ring %d"):format(#fs + 1, #Ring())
		and SY.Tx(m.c2) == ("o/i fart 2/2 · heard 0/3 · board %d/2"):format(nS)
		and SY.Tx(m.c3) == "o/i pair 0/1 · ping 1/2 · other 0/4", SY.Tx(m.c1) .. " | " .. SY.Tx(m.c2) .. " | " .. SY.Tx(m.c3))
	local top = true
	for i = 1, 12 do
		local r = Row(i)
		local hm, dir, ch, kind, who, msg = RL(i):match("^%S+ (%S+) (%S+) (%S+) (%S+) (%S+) ?(.*)$")
		local you = dir == "echo" or (dir == "out" and who == "-")
		if not r or r[1] ~= hm or r[2] ~= dir or r[3] ~= ch or r[4] ~= kind or r[5] ~= (you and "you" or who) .. "\194\160" .. msg then
			top = false
		end
	end
	ok("devmsg: 12 newest on top: time, dir, channel, kind, who + message", top and Row(1)[1] == "12:00:00", table.concat(Row(1), "|"))
	In("Z:1:|cffff0000red|r|Hx|h", "PARTY", "Pat")
	ok("devmsg: a new line shows at once (no timer), | escaped", Row(1, true)[5]:find("Z:1:||cffff0000red||r||Hx||h", 1, true)
		and SY.Tx(m.c1):find(" in 15 ", 1, true) and Row(2)[5]:find("x", 1, true), Row(1, true)[5])
	Out("P:1", "WHISPER", "Bob")
	In("F:1:FART:Player-1-0000AAAA:9:0:1", "PARTY", ME)
	ok("devmsg: colours: out green, in white, echo dim, you gold", Row(1, true)[2] == H("dim") .. "echo|r"
		and Row(2, true)[2] == H("good") .. "out|r" and Row(3, true)[2] == H("text") .. "in|r"
		and Row(1, true)[5]:sub(1, 13) == H("gold") .. "you" and Row(2)[5] == "Bob\194\160P:1" and Row(2)[3] == "WHSP", Row(2, true)[2])
	SY.Click(w.msgs)
	ok("devmsg: Msgs off = the panel hides, the window keeps its size", not m.root.shown and w.root:GetHeight() == h0
		and SY.State(w.msgs) == "base" and Count("DEVWIN msgs off") == 1)
	In("H:1:z", "PARTY", "Pat")
	ok("devmsg: hidden view = still counted + saved", Body(RL(1)) == "in PARTY heard Pat H:1:z")
	SY.Click(w.msgs)
	Slash("dev")   -- close with the view on
	In("H:1:closed", "PARTY", "Pat")
	Slash("dev")   -- open again
	ok("devmsg: open again = the panel is up to date", m.root.shown and Mv() == m and Row(1)[5] == "Pat\194\160H:1:closed"
		and SY.Tx(m.c1):find(" in 17 ", 1, true), SY.Tx(m.c1))
	SY.Click(w.msgs)
	Slash("dev")
	ok("devmsg: the window sends nothing", #sent == nsent and #SY.asent == nasent + 1)

	-- the ring: max 200, newest last
	for i = 1, 250 do In("S:1:n" .. i, "GUILD", "Pat") end
	ok("devmsg: ring max 200", #Ring() == 200 and Body(Ring()[1]) == "in GUILD board Pat S:1:n51"
		and Body(RL(1)) == "in GUILD board Pat S:1:n250", #Ring())

	-- a /reload: the ring stays, the counts start again
	local db = SpokenWindDB
	Boot(db)
	ok("devmsg: reload keeps the ring", #Ring() == 200 and Body(RL(1)) == "in GUILD board Pat S:1:n250"
		and Count("DEVMSG on hook=1 listen=1") >= 1)
	Slash("dev")
	w = Win()
	SY.Click(w.msgs)
	m = Mv()
	ok("devmsg: reload = new session counts", SY.Tx(m.c1) == "out 0 · in 0 · echo 0 · ring 200"
		and Row(1)[5]:find("S:1:n250", 1, true), SY.Tx(m.c1))
	Slash("dev")

	-- Real keeps the ring
	Slash("dev ach fire gas")
	ok("devmsg: a dev change keeps the ring", SpokenWindDB.dev.real and #Ring() == 200)
	Slash("dev ach real")
	local keys = {}
	for k in pairs(SpokenWindDB.dev or {}) do keys[#keys + 1] = k end
	ok("devmsg: Real = only the ring left", #keys == 1 and keys[1] == "msgs" and #Ring() == 200 and LogHas("DEV real restore"),
		table.concat(keys, ","))

	-- a guard: an error inside the hook or the listener never reaches Spoken Wind
	SpokenWindDB.dev.msgs = setmetatable({}, { __newindex = function() error("boom") end })
	now = now + 5
	na = #SY.asent
	hw = true SY.hooks.DoEmote("FART") hw = false
	Emote(OWN_FART, ME, ME_GUID)
	In("F:1:FART:Player-1-0000BBBB:9:0:2", "PARTY", "Pat")
	local se = 0
	for _, x in ipairs(SpokenWindDB.sync) do if x:find("ERR", 1, true) and not x:find("devmsg", 1, true) then se = se + 1 end end
	local nf = 0
	for i = na + 1, #SY.asent do if Kind(SY.asent[i].m) == "fart" then nf = nf + 1 end end
	ok("devmsg: hook error = ERR devmsg, the send still ran", nf == 2 and LogHas("ERR devmsg") and se == 0, nf)
	-- the hook's own guard: a direct send never throws back to the caller (Spoken Wind may swallow it, other addons not)
	hw = true
	local dok, derr = pcall(C_ChatInfo.SendAddonMessage, "SpWind", "F:1:FART:x:1:0:1", "PARTY")
	hw = false
	ok("devmsg: a hook error never reaches the caller", dok and derr == nil, tostring(derr))
	SpokenWindDB.dev.msgs = {}

	-- a fresh save: the view is empty
	Boot(nil)
	Slash("dev")
	w = Win()
	SY.Click(w.msgs)
	m = Mv()
	local rows = SY.ListRows(m.msgs)
	ok("devmsg: empty view = one '-' row + zeros", #rows == 1 and rows[1][1] == "-" and rows[1][5] == ""
		and SY.Tx(m.c1) == "out 0 · in 0 · echo 0 · ring 0"
		and SY.Tx(m.c2) == "o/i fart 0/0 · heard 0/0 · board 0/0", SY.Tx(m.c1))
	Slash("dev")

	-- no frame for the listener: listen=0, nothing else breaks (only a plain frame made by Dev.lua fails;
	-- Spoken Wind's option pages are plain frames too)
	preLogin = function()
		local cf = CreateFrame
		CreateFrame = function(kind, name, parent, tmpl)
			if parent == nil then
				for lv = 2, 5 do
					local i = debug.getinfo(lv, "S")
					if i and tostring(i.source):find("Dev%.lua$") then error("no frame") end
				end
			end
			return cf(kind, name, parent, tmpl)
		end
	end
	Boot(nil)
	preLogin = nil
	ok("devmsg: no listener frame = listen=0, no error", Count("DEVMSG on hook=1 listen=0") == 1 and not LogHas("ERR")
		and Lis() == nil, LastLog())

	-- no API: no hook, still a listener, no error
	SY.noApi = true
	Boot(nil)
	SY.noApi = nil
	ok("devmsg: no API = hook=0, no error", Count("DEVMSG on hook=0 listen=1") == 1 and not LogHas("ERR"), LastLog())
	IsInGroup, IsInGuild, IsInRaid = nil, nil, nil
	ok("devmsg: nothing forbidden in the block", #forbidden == forb0, forbidden[#forbidden])
end)()

;(function()   -- Heard reply + stats + Legend (0.6.2): own function (the main chunk is near 200 locals)
local PG, QG, RG, DG = "Player-1-0000FFFF", "Player-1-0000BBBB", "Player-1-0000CCCC", "Player-1-0000DDDD"
local ICON = "|TInterface\\Common\\VoiceChat-Speaker:14|t "
local function Boot(db)
	ev, ns = Load(db)
	IsInGroup = function() return true end
	IsInGuild = function() return true end
	SpokenWindDB.cd = 0
	SY.Tiny(ns)
	willPlay = true
	return ns
end
local function St() return SpokenWindDB.stats end
local function SN(s)   -- sync ring lines with s
	local k = 0
	for _, l in ipairs(SpokenWindDB.sync) do if l:find(s, 1, true) then k = k + 1 end end
	return k
end
local function Hs()   -- H messages sent (m = without the 0.6.4 tail, full = as sent)
	local h = {}
	for _, x in ipairs(SY.asent) do
		if tostring(x.m):sub(1, 4) == "H:1:" then
			h[#h + 1] = { m = x.m:match("^(H:1:[^:]+:%d+:[^:]+)"), full = x.m, ch = x.ch, hw = x.hw, p = x.p, tgt = x.tgt }
		end
	end
	return h
end
local function Msg(text, ch, name)
	ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", text, ch or "PARTY", name or "Pat")
end
local function F(guid, snd, n) return ("F:1:FART:%s:%d:0:%d"):format(guid, snd, n) end
local function H(g, n, from) return ("H:1:%s:%d:%s"):format(g, n, from) end
local function Fart(guid, name)   -- true = a sound played
	local np = #plays
	ev.scripts.OnEvent(ev, "CHAT_MSG_TEXT_EMOTE", FartBy(name), name, "", "", "", "", 0, 0, "", 0, 123, guid)
	return #plays > np
end
local function Heard(guid, name, snd, n)   -- the F message first, the emote 40 ms later
	Msg(F(guid, snd, n), "PARTY", name)
	now = now + 0.04
	return Fart(guid, name)
end
local function Run()
	local i = 1
	while i <= #SY.timers do
		local t = SY.timers[i]
		if t.at <= now + 1e-9 then table.remove(SY.timers, i) t.fn() else i = i + 1 end
	end
end
local function Own()   -- a key press + its emote line: the F message's snd and n
	local na = #SY.asent
	hw = true
	SY.hooks.DoEmote("FART")
	hw = false
	Emote(OWN_FART, ME, ME_GUID)
	local m = SY.asent[na + 1] and SY.asent[na + 1].m or ""
	local snd, n = m:match("^F:1:FART:[^:]+:(%d+):%d+:(%d+)")
	return tonumber(snd), tonumber(n)
end
-- the bar's "Heard by" tag (Bar.lua, 0.8.0): its text (nil = hidden, or no bar) and its state
local function Lines()
	local b = ns.BarRefs()
	if b and b.root.shown and b.heardBy.shown then return b.heardByText.text end
end
local function TagSt() local b = ns.BarRefs() return b and SY.State(b.heardBy) end
local function Words()   -- words in the tag (dots left out)
	local k = 0
	for _ in (Lines() or ""):gsub("·", ""):gmatch("%S+") do k = k + 1 end
	return k
end

-- ---- reply: one per fart, on the F's channel, no key press
Boot(nil)
local nSent = #sent
now = now + 5
ok("heard: msg first: played", Heard(PG, "Pat", 5, 1))
local h = Hs()
ok("heard: 1 reply: farter + n + own GUID, F's channel, no key press", #h == 1 and h[1].m == H(PG, 1, ME_GUID)
	and h[1].ch == "PARTY" and h[1].hw == false and h[1].p == "SpWind" and h[1].tgt == nil, h[1] and h[1].m)
ok("heard: reply under 254 bytes", h[1] and #h[1].m + #h[1].p <= 254)
ok("heard: send logged", SN("HEARD send ch=PARTY g=00FFFF n=1 ok=1") == 1, SpokenWindDB.sync[#SpokenWindDB.sync])
Msg(F(PG, 5, 1), "GUILD", "Pat")
ok("heard: PARTY + GUILD copy of the F: still 1 reply", #Hs() == 1)
-- max 1 reply per s
now = now + 0.5
ok("heard: 2nd farter in the same s: played", Heard(QG, "Quin", 3, 1))
ok("heard: max 1 reply per s", #Hs() == 1 and SN("HEARD skip why=gap g=00BBBB n=1") == 1)
now = now + 1
Heard(QG, "Quin", 4, 2)
ok("heard: 1 s later: replies again", #Hs() == 2 and Hs()[2].m == H(QG, 2, ME_GUID), Hs()[2] and Hs()[2].m)
now = now + 1.5
Msg(F(RG, 2, 1), "GUILD", "Rae")
now = now + 0.04
Fart(RG, "Rae")
ok("heard: guild F: reply on GUILD", #Hs() == 3 and Hs()[3].ch == "GUILD", Hs()[3] and Hs()[3].ch)
-- no reply: Sound Off, cooldown, not played, no F message
now = now + 2
SpokenWindDB.on = false
ok("heard: Sound Off: no sound", not Heard(PG, "Pat", 6, 2))
ok("heard: Sound Off: no reply", #Hs() == 3)
SpokenWindDB.on = true
now = now + 2
SpokenWindDB.cd = 5
ok("heard: cooldown: 1st plays", Heard(PG, "Pat", 6, 3))
now = now + 1.5
ok("heard: cooldown: 2nd blocked", not Heard(PG, "Pat", 7, 4))
ok("heard: cooldown: 1 reply only", #Hs() == 4 and Hs()[4].m == H(PG, 3, ME_GUID), #Hs())
SpokenWindDB.cd = 0
now = now + 4   -- the hold from cd 5 (set at its play) has ended
willPlay = false
Heard(PG, "Pat", 8, 5)
ok("heard: game did not play it: no reply", #Hs() == 4 and LastPlay():find(" ok=0", 1, true), LastPlay())
willPlay = true
now = now + 2
ok("heard: no F message (stranger): the seed plays", Fart(DG, "Dax"))
ok("heard: no F message: no reply", #Hs() == 4)
-- the seed played, then the F came late: still heard
now = now + 2
ok("heard: known + emote first: waits", not Fart(PG, "Pat"))
now = now + 0.15 Run()
ok("heard: seed at the cap", SN("SYNC by=seed why=timeout") >= 1)
now = now + 0.1
Msg(F(PG, 9, 6), "PARTY", "Pat")
ok("heard: late F after the seed played: 1 reply", #Hs() == 5 and Hs()[5].m == H(PG, 6, ME_GUID), #Hs())
now = now + 2
ok("heard: emote first, waits", not Fart(PG, "Pat"))
now = now + 0.08
Msg(F(PG, 9, 7), "PARTY", "Pat")
ok("heard: F inside the wait: plays + 1 reply", #Hs() == 6 and Hs()[6].m == H(PG, 7, ME_GUID), #Hs())
now = now + 0.2 Run()
now = now + 2
SpokenWindDB.on = false
Fart(PG, "Pat")
now = now + 0.2
Msg(F(PG, 9, 8), "PARTY", "Pat")
ok("heard: Sound Off + late F: no reply", #Hs() == 6)
SpokenWindDB.on = true
now = now + 2
willPlay = false
ok("heard: emote first (the game will not play it)", not Fart(PG, "Pat"))
now = now + 0.15 Run()
willPlay = true
now = now + 0.1
Msg(F(PG, 9, 9), "PARTY", "Pat")
ok("heard: seed not played + late F: no reply", #Hs() == 6 and SN("SYNC by=late") >= 2, #Hs())
-- never to strangers by whisper, never on other channels, never to yourself
ok("heard: whisper only to the test partner", ns.HeardReply(PG, 50, "WHISPER", "Pat", "party") == false)
ok("heard: no reply on other channels", ns.HeardReply(PG, 51, "CHANNEL", "Pat", "party") == false
	and ns.HeardReply(PG, 52, "OFFICER", "Pat", "party") == false and #Hs() == 6)
now = now + 2
ok("heard: one reply per fart id", ns.HeardReply(PG, 53, "PARTY", "Pat", "party") == true)
now = now + 1.5
ok("heard: same fart id again: no", ns.HeardReply(PG, 53, "PARTY", "Pat", "party") == false and #Hs() == 7, #Hs())
now = now + 5
local own0 = St().own
local _, myN = Own()
ok("heard: own fart: F out, no reply to it", myN ~= nil and #Hs() == 7, myN)
ok("heard: own GUID: HeardReply refuses", ns.HeardReply(ME_GUID, 1, "PARTY", ME, "party") == false and #Hs() == 7)
ok("stats: own press = Farts + 1", St().own == own0 + 1, St().own)
reg.byVar.SpokenWind_rwbtn:SetValue(false)   -- on by default (0.6.2)
ok("show: bar off: no Heard tag", Lines() == nil)
now = now + 3.01 Run()
ok("count: own fart, 0 replies: sum count=0", SN(("HEARD sum g=00AAAA n=%d count=0"):format(myN)) == 1)

-- ---- show: the bar's "Heard by" tag
reg.byVar.SpokenWind_rwbtn:SetValue(true)
local bar = ns.BarRefs()
now = now + 5
own0 = St().own
_, myN = Own()
ok("show: own fart: Heard by 0, base look", Lines() == "Heard by 0" and TagSt() == "base", Lines())
ok("show: the totals count it (the bar tip rows)", ns.HeardTipRows()[1][1] == "Farts" and ns.HeardTipRows()[1][2] == tostring(own0 + 1)
	and ns.HeardTipRows()[2][2] == "0" and ns.HeardTipRows()[3][2] == "0")
ok("show: the tag is a part of the bar (no own frame)", bar.heardBy.parent ~= UIParent and SY.own[bar.root] ~= nil)
Msg(H(ME_GUID, myN, QG), "PARTY", "Quin")
ok("count: 1 reply: Heard by 1, green", Lines() == "Heard by 1" and TagSt() == "good"
	and SN(("HEARD got from=00BBBB g=00AAAA n=%d count=1"):format(myN)) == 1, Lines())
Msg(H(ME_GUID, myN, QG), "GUILD", "Quin")
ok("count: same replier on GUILD: still 1", Lines() == "Heard by 1", Lines())
Msg(H(ME_GUID, myN, DG), "PARTY", "Quin")
ok("count: same sender, other GUID: still 1", Lines() == "Heard by 1", Lines())
Msg(H(ME_GUID, myN, PG), "RAID", "Pat")
ok("count: 2nd person: Heard by 2", Lines() == "Heard by 2" and ns.HeardTipRows()[2][2] == "2" and ns.HeardTipRows()[3][2] == "2", Lines())
ok("stats: heard, people (a set), best", St().heard == 2 and St().best == 2 and St().people[QG] == true
	and St().people[PG] == true and St().people[DG] == nil)
ok("show: max 4 words in the tag", Words() <= 4, Lines())
now = now + 3.01 Run()
ok("count: window closed: sum logged", SN(("HEARD sum g=00AAAA n=%d count=2"):format(myN)) == 1)
Msg(H(ME_GUID, myN, RG), "PARTY", "Rae")
ok("count: reply after 3 s: dropped, tag still up", St().heard == 2 and Lines() == "Heard by 2")
now = now + 2 Run()
ok("show: gone after 5 s", Lines() == nil)
-- count 0 shown dimmed, best kept
now = now + 5
local _, n2 = Own()
ok("count 0: shown, base look", Lines() == "Heard by 0" and TagSt() == "base", Lines())
now = now + 3.01 Run()
ok("count 0: sum count=0, best kept", SN(("HEARD sum g=00AAAA n=%d count=0"):format(n2)) == 1 and St().best == 2)
now = now + 2 Run()
-- someone else's fart: "<name> · Heard N" once N >= 1; your own reply never counts
now = now + 5
Heard(PG, "Pat", 5, 20)
ok("others: our reply went out", #Hs() == 8 and Hs()[8].m == H(PG, 20, ME_GUID))
ok("others: 0 replies: nothing shown", Lines() == nil)
Msg(H(PG, 20, ME_GUID), "PARTY", ME)
ok("others: own reply echo: not counted", Lines() == nil)
Msg(H(PG, 20, PG), "PARTY", "Pat")
ok("others: the farter's own H: not counted", Lines() == nil)
Msg(H(PG, 20, RG), "PARTY", "Rae")
ok("others: name · Heard by 1", Lines() == "Pat · Heard by 1" and TagSt() == "good" and St().heard == 2, Lines())
ok("others: max 4 words in the tag", Words() <= 4, Lines())
now = now + 6 Run()
-- your own fart wins while it shows
local _, n3 = Own()
now = now + 1.1
Heard(QG, "Quin", 3, 30)
Msg(H(QG, 30, RG), "PARTY", "Rae")
ok("others: own tag wins while shown", Lines() == "Heard by 0", Lines())
Msg(H(ME_GUID, n3, PG), "PARTY", "Pat")
ok("others: 2 farts tracked at once: own still counts", Lines() == "Heard by 1", Lines())
now = now + 6 Run()
ok("show: hidden after", Lines() == nil)
-- hover: the bar tip = the clicks + the totals
bar.ach.scripts.OnEnter(bar.ach)
local tipB = select(3, ns.BarRefs())
local function TipText(r) local tt = {} for i, x in ipairs(r and r._swRows or {}) do tt[i] = x[1] .. "=" .. x[2] end return table.concat(tt, "|") end
local hn = ns.HeardNums()
ok("hover: the bar tip: the clicks + the totals", tipB and tipB.root.shown and tipB.titleText.text == "Spoken Wind"
	and TipText(tipB) == ("Left=Achievements|Right=Rewards|Fart=/fart at target|Right-click=/say|Farts=%d|Heard=%d|People=%d|Best=%d|Legend=%d|Legend heard=%d")
		:format(hn.own, hn.heard, hn.people, hn.best, hn.legend, hn.legendHeard) and hn.people == 2 and SY.HasText("Legend heard"), TipText(tipB))
ok("hover: the tip beside the bar, TOOLTIP", tipB.root.point and tipB.root.point[2] == bar.root and tipB.root.strata == "TOOLTIP")
now = now + 5
Own()
ok("hover: an open tip shows the new Farts count", tipB.root.shown and TipText(tipB):find("|Farts=" .. St().own .. "|", 1, true) ~= nil
	and St().own == hn.own + 1, TipText(tipB))
bar.ach.scripts.OnLeave(bar.ach)
ok("hover: leave = hidden", not tipB.root.shown)
bar.fart.scripts.OnEnter(bar.fart)
ok("hover: the Fart button shows the same tip", tipB.root.shown)
bar.fart.scripts.OnLeave(bar.fart)
ok("hover: leave the Fart button = hidden", not tipB.root.shown)
now = now + 5
_, n3 = Own()
ok("bar on: tag shown", Lines() ~= nil)
reg.byVar.SpokenWind_rwbtn:SetValue(false)
ok("bar off while shown: hidden", Lines() == nil)
now = now + 6 Run()
local own1 = St().own
Own()
ok("bar off: no tag, still counts", Lines() == nil and St().own == own1 + 1)
ok("bar off: the rewards popup does not open", ns.RewardsToggle() == false and not (select(2, ns.BarRefs()) or { root = {} }).root.shown)
now = now + 6 Run()
reg.byVar.SpokenWind_rwbtn:SetValue(true)
-- not in a group (no F sent): no line
IsInGroup, IsInGuild = function() return false end, function() return false end
now = now + 5
own1 = St().own
Own()
ok("solo: no F = no Heard tag, still counts", Lines() == nil and St().own == own1 + 1)
IsInGroup, IsInGuild = function() return true end, function() return true end
now = now + 6 Run()
-- test mode: a late own F (sent by a timer) is tracked too
local realM = ns.TestOwnMode
ns.TestOwnMode = function() return "late", 0.4 end
now = now + 5
local na, heard0 = #SY.asent, St().heard
hw = true SY.hooks.DoEmote("FART") hw = false
Emote(OWN_FART, ME, ME_GUID)
ns.TestOwnMode = realM
ok("late own F: not sent yet, tag up", #SY.asent == na and Lines() ~= nil, #SY.asent - na)
now = now + 0.4
hw = true Run() hw = false   -- the key press's own timer (the bus fake marks these; this one does not)
local lateN = tonumber((SY.asent[na + 1] and SY.asent[na + 1].m or ""):match("^F:1:FART:[^:]+:%d+:%d+:(%d+)"))
ok("late own F: sent by the timer", lateN ~= nil)
Msg(H(ME_GUID, lateN or 0, QG), "PARTY", "Quin")
ok("late own F: its reply counts", St().heard == heard0 + 1 and Lines() == "Heard by 1", Lines())
now = now + 6 Run()
-- Sound Off: your /fart press still counts
SpokenWindDB.on = false
own1 = St().own
now = now + 5
Own()
ok("stats: Sound Off press counts", St().own == own1 + 1)
SpokenWindDB.on = true
now = now + 6 Run()

-- ---- Legend
now = now + 5
local lh = St().legendHeard
Heard(RG, "Rae", 13, 40)
ok("legend heard: someone's legendary played = + 1", St().legendHeard == lh + 1, St().legendHeard)
now = now + 5
willPlay = false
Heard(RG, "Rae", 13, 41)
ok("legend heard: not played = no count", St().legendHeard == lh + 1)
willPlay = true
now = now + 5
Heard(RG, "Rae", 12, 42)
ok("legend heard: other sound = no count", St().legendHeard == lh + 1)
now = now + 5
local np = #plays
ev.scripts.OnEvent(ev, "CHAT_MSG_EMOTE", "unleashes a super legendary fart. Reality bends.", "Rae", "", "", "", "", 0, 0, "", 0, 123, RG)
ok("legend heard: /superfart line = no count", #plays == np + 1 and St().legendHeard == lh + 1, #plays - np)
local lg, tries, hit, wrong, lh3 = St().legend, 0, false, false, St().legendHeard
while tries < 300 and not hit do
	tries = tries + 1
	clock = clock + 10
	now = now + 6
	local s = Own()
	Run()
	if s == 13 then hit = true elseif St().legend ~= lg then wrong = true end
end
ok("legend: own roll 13 = + 1, other rolls 0", hit and not wrong and St().legend == lg + 1, tries)
ok("legend: own legendary is not a heard one", St().legendHeard == lh3)
ok("legend: in the bar tip rows", ns.HeardTipRows()[5][1] == "Legend" and ns.HeardTipRows()[5][2] == tostring(St().legend)
	and ns.HeardTipRows()[6][1] == "Legend heard" and ns.HeardTipRows()[6][2] == tostring(St().legendHeard))

-- ---- bad H messages: dropped without a word
now = now + 6 Run()
local _, n4 = Own()
local base = SN("HEARD got")
for _, m in ipairs({ H(ME_GUID, 0, QG), H(ME_GUID, 1000, QG), ("H:1:%s:%d"):format(ME_GUID, n4),
	("H:1:%s:%d:%s;x"):format(ME_GUID, n4, QG), ("H:1:%s:x:%s"):format(ME_GUID, QG), ("H:1:a b:%d:%s"):format(n4, QG),
	("H:1:%s:%d:Q;G"):format(ME_GUID, n4), H(ME_GUID, n4 + 1, QG), H("Player-1-00009999", n4, QG), "H:1:", "H:1:::",
	H(ME_GUID, n4, ME_GUID) }) do
	Msg(m, "PARTY", "Quin")
end
Msg(H(ME_GUID, n4, QG), "WHISPER", "Quin")   -- a whisper, not the test partner
Msg(H(ME_GUID, n4, QG), "CHANNEL", "Quin")
Msg(H(ME_GUID, n4, QG), "OFFICER", "Quin")
ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "Other", H(ME_GUID, n4, QG), "PARTY", "Quin")
Msg(H(ME_GUID, n4, QG), "PARTY", "")
ok("bad H: all dropped, no error", SN("HEARD got") == base and Lines() == "Heard by 0" and not LogHas("ERR"), Lines())
Msg(H(ME_GUID, n4, QG), "PARTY", "Quin")
ok("bad H: then a good one counts", SN("HEARD got") == base + 1 and Lines() == "Heard by 1", Lines())
ok("heard: no chat line, no print", #sent == nSent and #prints == 0, prints[1])
ok("heard: H only out of a key press", (function()
	for _, x in ipairs(SY.asent) do if not x.hw and x.m:sub(1, 4) ~= "H:1:" then return false end end
	return true
end)())
now = now + 6 Run()

-- ---- saved: lifetime + best + people; BOOT; old saves
local own2, heard2, lg2, lh2 = St().own, St().heard, St().legend, St().legendHeard
Boot(SpokenWindDB)
ok("saved: totals kept", St().own == own2 and St().heard == heard2 and heard2 == 5 and St().best == 2
	and St().people[QG] == true and St().people[PG] == true and St().legend == lg2 and St().legendHeard == lh2)
ok("BOOT: own heard people best legend legendHeard reply=1", LogHas(("own=%d heard=5 people=2 best=2 legend=%d legendHeard=%d reply=1 char=")
	:format(own2, lg2, lh2)), LastLog())
Boot({ farts = { { t = CLOCK0, e = "FART", who = "you", snd = 3 }, { t = CLOCK0, e = "FART", who = "Bob", snd = 4 },
	{ t = CLOCK0, e = "FART", who = "you", snd = 13 } }, stats = { all = 9, today = 1, day = "x" } })
ok("old save: Farts = own fart log rows, the rest 0", St().own == 2 and St().heard == 0 and St().best == 0
	and St().legend == 0 and St().legendHeard == 0 and next(St().people) == nil and St().all == 9)
ok("old save: BOOT", LogHas("own=2 heard=0 people=0 best=0 legend=0 legendHeard=0 reply=1"), LastLog())
Boot({ stats = { own = -3, heard = "x", best = 1 / 0, legend = 2.7, legendHeard = 4, people = { [QG] = true, [5] = true, bad = 1 } } })
ok("bad save: cleaned", St().own == 0 and St().heard == 0 and St().best == 0 and St().legend == 2 and St().legendHeard == 4
	and St().people[QG] == true and St().people[5] == nil and St().people.bad == nil)
Boot({ stats = { own = 0, people = "x" } })
ok("bad save: saved 0 stays 0, people a set", St().own == 0 and type(St().people) == "table")

-- ---- a Heard error never breaks the sound or the sync
Boot(nil)
now = now + 5
local realR, realT, realO, realG = ns.HeardReply, ns.HeardTrack, ns.HeardOwnSent, ns.HeardGot
ns.HeardReply = function() error("boom") end
ok("errors: reply error: the synced sound still plays", Heard(PG, "Pat", 5, 1) and LastPlay():find(" snd=5 ", 1, true), LastPlay())
ok("errors: reply error logged", SN("ERR heard") == 1, SN("ERR heard"))
ns.HeardReply = realR
ns.HeardTrack = function() error("boom") end
now = now + 5
ok("errors: track error: the F still syncs", Heard(PG, "Pat", 6, 2) and LastPlay():find(" snd=6 ", 1, true)
	and SN("ERR heard") == 2, LastPlay())
ns.HeardTrack = realT
ns.HeardOwnSent = function() error("boom") end
now = now + 5
local np = #plays
ok("errors: own-sent error: the F still goes out, the fart plays", Own() ~= nil and #plays == np + 1 and SN("ERR heard") == 3,
	SN("ERR heard"))
ns.HeardOwnSent = realO
ns.HeardGot = function() error("boom") end
Msg(H(PG, 2, QG), "PARTY", "Quin")
ok("errors: got error: logged", SN("ERR heard") == 4)
ns.HeardGot = realG
local realS = C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage = function(pf, m, ...)
	if tostring(m):sub(1, 4) == "H:1:" then error("send boom") end
	return realS(pf, m, ...)
end
now = now + 5
Heard(QG, "Quin", 3, 1)
ok("errors: send error: caught, logged ok=0", SN("HEARD send ch=PARTY g=00BBBB n=1 ok=0") == 1 and SN("ERR heard") == 4)
C_ChatInfo.SendAddonMessage = realS
SY.sendRes = false
now = now + 5
Heard(QG, "Quin", 4, 2)
ok("errors: send refused: ok=0", SN("HEARD send ch=PARTY g=00BBBB n=2 ok=0") == 1)
SY.sendRes = nil
St().own = "x"
now = now + 5
np = #plays
Own()
ok("errors: stats error: logged, the own fart still plays", #plays == np + 1 and LogHas("ERR heard"), LastLog())
St().own = 0
-- one sound per person: a fart that does not play sends no H and adds no dex count
do
	Boot(nil)
	SY.ShortLen(3000)
	local function DexN() local k = 0 for _, d in pairs(SpokenWindDB.dex) do k = k + d.n end return k end
	now = now + 5 Run()
	local h0 = #Hs()
	local p1 = Heard(QG, "Quin", 3, 1)
	now = now + 1 Run()
	ok("busy: a played fart sends its H", p1 and #Hs() == h0 + 1, #Hs() - h0)
	local d0 = DexN()
	local p2 = Heard(QG, "Quin", 4, 2)   -- 1.04 s after: its 3 s sound still plays
	now = now + 1 Run()
	ok("busy: a gated fart: no sound, no H, no dex count", not p2 and #Hs() == h0 + 1 and DexN() == d0
		and LogHas("SKIP busy emo=FART who=other left=2.0"), #Hs() - h0)
	now = now + 1.5 Run()
	local p3 = Heard(QG, "Quin", 5, 3)
	now = now + 1 Run()
	ok("busy: after its sound ended: plays, H, dex count", p3 and #Hs() == h0 + 2 and DexN() == d0 + 1, #Hs() - h0)
	-- your own press while your own sound plays: the emote goes, no F message, no sound
	now = now + 10 Run()
	local s1 = Own()
	ok("busy: own press: F sent", s1 ~= nil)
	now = now + 1.5 Run()   -- past the 1 s send gap; your 3 s sound still plays
	local na, np2, own0 = #SY.asent, #plays, St().own
	local s2 = Own()
	ok("busy: own press while your sound plays: no F, no sound", s2 == nil and #SY.asent == na and #plays == np2
		and LogHas("SKIP busy emo=FART who=self left=1.5"), #SY.asent - na)
	ok("busy: own press still counts as a fart press", St().own == own0 + 1, St().own - own0)
	now = now + 1.6 Run()
	ok("busy: own press after your sound ended: F again", Own() ~= nil)
	SY.ShortLen()
	-- cd 0 + the sync wait: the person is held while their emote waits for its message
	now = now + 10 Run()
	Heard(QG, "Quin", 3, 4)   -- Quin is known now (sent F)
	now = now + 5 Run()
	local np3 = #plays
	ok("busy: emote waits for its message", not Fart(QG, "Quin") and #SY.Waits() == 1, #SY.Waits())
	now = now + 0.05
	ok("busy: a second emote inside the wait is blocked", not Fart(QG, "Quin")
		and LogHas("SKIP busy emo=FART who=other left=0.1"), LastLog())
	now = now + 0.2 Run()
	ok("busy: the first plays after the wait, once", #plays == np3 + 1, #plays - np3)
end
IsInGroup, IsInGuild = nil, nil
end)()

;(function()   -- Social rows + author flags + the collection save (0.6.2): own function (the main chunk is near 200 locals)
local PG, QG, RG = "Player-1-0000FFFF", "Player-1-0000BBBB", "Player-1-0000CCCC"
local function Boot(db, dev)
	ev, ns = Load(db, "vertical", dev)
	IsInGroup = function() return true end
	IsInGuild = function() return true end
	SpokenWindDB.cd = 0
	willPlay = true
	return ns
end
local function St() return SpokenWindDB.stats end
local function Msg(text, ch, name)
	ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", text, ch or "PARTY", name or "Pat")
end
local function F(guid, snd, n, a) return ("F:1:FART:%s:%d:0:%d%s"):format(guid, snd, n, a or "") end
local function H(g, n, from, a) return ("H:1:%s:%d:%s%s"):format(g, n, from, a or "") end
local function Heard(guid, name, snd, n, a)   -- the F message first, the emote 40 ms later; true = a sound played
	Msg(F(guid, snd, n, a), "PARTY", name)
	now = now + 0.04
	local np = #plays
	ev.scripts.OnEvent(ev, "CHAT_MSG_TEXT_EMOTE", FartBy(name), name, "", "", "", "", 0, 0, "", 0, 123, guid)
	return #plays > np
end
local function Run()
	local i = 1
	while i <= #SY.timers do
		local t = SY.timers[i]
		if t.at <= now + 1e-9 then table.remove(SY.timers, i) t.fn() else i = i + 1 end
	end
end
local function Own()   -- a key press + its emote line: the F message's n, the message
	local na = #SY.asent
	hw = true
	SY.hooks.DoEmote("FART")
	hw = false
	Emote(OWN_FART, ME, ME_GUID)
	local m = SY.asent[na + 1] and SY.asent[na + 1].m or ""
	return tonumber(m:match("^F:1:FART:[^:]+:%d+:%d+:(%d+)")), m
end
local function Count(s)
	local k = 0
	for _, l in ipairs(SpokenWindDB.log) do if l:find(s, 1, true) then k = k + 1 end end
	return k
end
local function Stat(id)   -- the social tile's stat text
	for _, t in ipairs(ns.AchLines("social").tiles) do if t.id == id then return t.stat end end
end

-- ---- best (one fart heard by N), people, Fan Club: real H replies
Boot(nil)
now = now + 10
local n1 = Own()
while ns.ToastFrame() and ns.ToastFrame().shown do ns.ToastFrame().scripts.OnMouseUp(ns.ToastFrame()) end
ok("social: nothing before a reply", Done().selfstarter ~= nil and Done().heard == nil and n1 ~= nil, n1)
Msg(H(ME_GUID, n1, QG), "PARTY", "Quin")
ok("Someone Heard That: 1 reply", Done().heard ~= nil and LogHas("ACH heard toast=1") and St().best == 1, LastLog())
local T = ns.ToastFrame()
local TRs = ns.ToastRefs()
ok("social toast: green name", T and T.shown and TRs.name.text == "|cff1eff00Someone Heard That|r", TRs and TRs.name.text)
for k = 1, 3 do Msg(H(ME_GUID, n1, "Player-1-0000B00" .. k), "PARTY", "P" .. k) end
ok("Packed House: 4 is not", Done().packed == nil and St().best == 4 and Stat("packed") == "4/5", Stat("packed"))
ok("Fan Club: 4 people is not", Done().fanclub == nil and Stat("fanclub") == "4/5", Stat("fanclub"))
Msg(H(ME_GUID, n1, "Player-1-0000B004"), "PARTY", "P4")
ok("Packed House: one fart heard by 5", Done().packed ~= nil and St().best == 5, St().best)
ok("Fan Club: 5 people", Done().fanclub ~= nil)
ok("social: done tile says the date", Stat("heard") == "Done " .. os.date("%m-%d", clock), Stat("heard"))
-- ---- the bigger goals: straight from the counts (Heard.lua calls AchStats)
St().best = 9 ns.AchStats()
ok("Standing Ovation: 9 is not", Done().ovation == nil and Stat("ovation") == "9/10", Stat("ovation"))
St().best = 10 ns.AchStats()
ok("Standing Ovation: 10", Done().ovation ~= nil)
;(function()
	local tx = Mock():CreateTexture()
	ns.AchRingPaint(tx, 4, true)
	local epic = tx.path == ns.ACH_RING and Near(tx.vc, 0xa3, 0x35, 0xee)
	ns.AchRingPaint(tx, 5, false)
	local locked = Near(tx.vc, 0x9d, 0x9d, 0x9d)
	ITEM_QUALITY_COLORS = { [5] = { r = 0.5, g = 0.25, b = 0 } }
	ns.AchRingPaint(tx, 5, true)
	local game = tx.vc[1] == 0.5 and tx.vc[2] == 0.25 and tx.vc[3] == 0
	ITEM_QUALITY_COLORS = nil
	ok("ring: epic purple, locked grey, the game's color first", epic and locked and game)
end)()
St().heard = 24 ns.AchStats()
ok("Word Gets Around: 24 is not", Done().around == nil and Stat("around") == "24/25", Stat("around"))
St().heard = 25 ns.AchStats()
ok("Word Gets Around: 25", Done().around ~= nil and Done().town == nil)
St().heard = 99 ns.AchStats()
ok("Talk of the Town: 99 is not", Done().town == nil and Stat("town") == "99/100", Stat("town"))
St().heard = 100 ns.AchStats()
ok("Talk of the Town: 100", Done().town ~= nil and Done().fame == nil and Stat("fame") == "100/500", Stat("fame"))
St().heard = 500 ns.AchStats()
ok("Wind of Fame: 500", Done().fame ~= nil)
for k = 1, 19 do St().people["Player-1-0000C" .. ("%03d"):format(k)] = true end
ns.AchStats()
ok("Cult Following: 24 people is not", Done().cult == nil and Stat("cult") == "24/25", Stat("cult"))
St().people["Player-1-0000C999"] = true
ns.AchStats()
ok("Cult Following: 25 people", Done().cult ~= nil and Done().household == nil and Stat("household") == "25/100",
	Stat("household"))
for k = 20, 94 do St().people["Player-1-0000D" .. ("%03d"):format(k)] = true end
ns.AchStats()
ok("Household Name: 100 people", Done().household ~= nil)
St().own = 248
now = now + 5 Run()
Own()
ok("Windbag: 249 own is not", Done().windbag == nil and Stat("windbag") == "249/250", Stat("windbag"))
now = now + 5 Run()
Own()
ok("Windbag: 250 own /fart", Done().windbag ~= nil and St().own == 250, St().own)
local nEarn = Count("ACH ")
ns.AchStats()
ok("social: an earned row is never earned twice", Count("ACH ") == nEarn)
ok("social: legend rows stay locked with no legend sound", Done().born == nil and Done().witness == nil
	and Done().everywind == nil and Stat("born") == "" and Stat("everywind") == "0/9", Stat("everywind"))
ok("social: tab head", ns.AchTabText("social") == "Social 10/14", ns.AchTabText("social"))
ok("social: rows earned, no reward cell", (function()
	local b = ns.BarRefs()
	SY.Click(b.ach, "RightButton")
	local _, pop = ns.BarRefs()
	local nR = 0
	for _, r in ipairs(ns.REWARDS) do if Done()[r.ach] then nR = nR + 1 end end
	local good = pop and pop.root.shown and pop.count.text == ("%d/15"):format(nR) and nR >= 2
		and ns.AchDone() >= nR + 10   -- the 10 social rows are not rewards
	SY.Click(b.ach, "RightButton")
	return good
end)(), select(2, ns.BarRefs()) and select(2, ns.BarRefs()).count.text)

-- ---- In Sync: group or guild farts that played from their message
Boot(nil)
for k = 1, 9 do now = now + 5 Run() Heard(PG, "Pat", (k % 12) + 1, k) end
ok("In Sync: 9 is not", Done().insync == nil and SpokenWindDB.ach.sync == 9 and Stat("insync") == "9/10",
	SpokenWindDB.ach.sync)
now = now + 5 Run()
Emote(FartBy("Bob"), "Bob", BOB)
now = now + 0.3 Run()
ok("In Sync: an emote with no message is not", SpokenWindDB.ach.sync == 9, SpokenWindDB.ach.sync)
ns.AchInSync("pair")
ok("In Sync: the pair test is not", SpokenWindDB.ach.sync == 9)
now = now + 5 Run()
ok("In Sync: the 10th", Heard(PG, "Pat", 3, 10) and Done().insync ~= nil and SpokenWindDB.ach.sync == 10)
now = now + 5 Run()
Heard(PG, "Pat", 4, 11)
ok("In Sync: no count once done", SpokenWindDB.ach.sync == 10)
Boot(SpokenWindDB)
ok("In Sync: kept over a reload", SpokenWindDB.ach.sync == 10 and Done().insync ~= nil)
SpokenWindDB.ach.sync, SpokenWindDB.ach.done.insync = "x", nil
Boot(SpokenWindDB)
ok("In Sync: bad save -> 0", SpokenWindDB.ach.sync == 0)
SpokenWindDB.ach.sync = 2.7
Boot(SpokenWindDB)
ok("In Sync: whole numbers", SpokenWindDB.ach.sync == 2)

-- the stats strip: each number in its place
;(function()
	local s = St()
	local o, h, l, p = s.own, s.heard, s.legend, s.people
	s.own, s.heard, s.legend, s.people = 7, 5, 2, { a = true, b = true, c = true }
	ok("stats strip: each number in its place", ns.AchStatsText() == "Farts 7 · Heard 5 · People 3 · Legend 2",
		ns.AchStatsText())
	s.own, s.heard, s.legend, s.people = o, h, l, p
end)()
-- ---- author flags: the dev addon adds ":a" to F and H (secret rows)
Boot(nil)
now = now + 5 Run()
local _, m0 = Own()
ok("author: public F has no flag", m0:find("^F:1:FART:[^:]+:%d+:%d+:%d+::%w+%.%w+%.%w+$") ~= nil, m0)
now = now + 5 Run()
ok("Straight From the Source: an author fart played", Heard(RG, "Rae", 4, 1, ":a") and Done().source ~= nil
	and LogHas("ACH source toast=1"), LastLog())
;(function()   -- the emote first: it waits, the author's message plays it
	now = now + 5 Run()
	Done().source = nil
	local np = #plays
	ev.scripts.OnEvent(ev, "CHAT_MSG_TEXT_EMOTE", FartBy("Rae"), "Rae", "", "", "", "", 0, 0, "", 0, 123, RG)
	local np1 = #plays
	now = now + 0.05
	Msg(F(RG, 4, 2, ":a"), "PARTY", "Rae")
	ok("Straight From the Source: the emote waits, the author's message plays it", np1 == np and #plays == np + 1
		and Done().source ~= nil, #plays - np)
	-- a stranger: the seed plays at once, the author's message comes late
	now = now + 5 Run()
	Done().source = nil
	local LG = "Player-1-0000EEEE"
	np = #plays
	ev.scripts.OnEvent(ev, "CHAT_MSG_TEXT_EMOTE", FartBy("Lou"), "Lou", "", "", "", "", 0, 0, "", 0, 123, LG)
	np1 = #plays
	now = now + 0.2
	Msg(F(LG, 4, 1, ":a"), "PARTY", "Lou")
	ok("Straight From the Source: the seed played, the author's message late", np1 == np + 1 and #plays == np + 1
		and Done().source ~= nil, np1 - np)
end)()
Boot(nil)
SpokenWindDB.on = false
now = now + 5 Run()
Heard(RG, "Rae", 4, 2, ":a")
now = now + 0.3 Run()
ok("Straight From the Source: not when nothing played", Done().source == nil)
SpokenWindDB.on = true
now = now + 5 Run()
local np0 = #plays
Heard(RG, "Rae", 5, 3, ";x")
now = now + 0.3 Run()
ok("author: a bad field list: the message is dropped (no sync, no row), the emote still plays", #plays == np0 + 1
	and Done().source == nil and SpokenWindDB.ach.sync == 0, SpokenWindDB.ach.sync)
now = now + 5 Run()
local n2 = Own()
Msg(H(ME_GUID, n2, QG, ";b"), "PARTY", "Quin")
ok("author: a bad H field list is dropped", Done().authornote == nil and Done().heard == nil)
Msg(H(ME_GUID, n2, QG, ":a"), "PARTY", "Quin")
ok("Author's Note: the author heard your fart", Done().authornote ~= nil and Done().heard ~= nil
	and LogHas("ACH authornote toast=1"))
ok("author: secret rows show once earned, head +N", ns.AchTabText("social") == "Social 1/14 +1"
	and #ns.AchLines("social").tiles == 15, ns.AchTabText("social"))
-- a later build's fields after the flag: ignored, the flag still counts; an unknown first field = not the author
now = now + 5 Run()
Done().source = nil
ok("author: F ':x:a' (2 unknown fields) plays, not the author", Heard(RG, "Rae", 6, 7, ":x:a") and Done().source == nil
	and SpokenWindDB.ach.sync == 1, SpokenWindDB.ach.sync)
now = now + 5 Run()
ok("author: F ':a:x:y' = the author's fart", Heard(RG, "Rae", 5, 8, ":a:x:y") and Done().source ~= nil, LastLog())
now = now + 5 Run()
local n3 = Own()
local h3 = SpokenWindDB.stats.heard
Msg(H(ME_GUID, n3, PG, ":x:y"), "PARTY", "Pat")
ok("H with 2 unknown fields counts", SpokenWindDB.stats.heard == h3 + 1, SpokenWindDB.stats.heard - h3)
-- the dev client sends the flag (own F + its H replies)
Boot(nil, true)
now = now + 5 Run()
local _, md = Own()
ok("author: dev F has :a", md:find("^F:1:FART:[^:]+:%d+:%d+:%d+:a:%w+%.%w+%.%w+$") ~= nil, md)
now = now + 5 Run()
local nh = #SY.asent
Heard(PG, "Pat", 6, 1)
now = now + 1 Run()
local hm
for k = nh + 1, #SY.asent do if SY.asent[k].m:sub(1, 4) == "H:1:" then hm = SY.asent[k].m end end
ok("author: dev H reply has :a", hm and hm:find("^H:1:[^:]+:1:[^:]+:a:%w+%.%w+%.%w+$") ~= nil, hm)
if HAVE_DEV then
	b = #prints
	hw = true
	Slash("dev thanks")
	hw = false
	ok("dev thanks: no pair -> one line, logged ok=0", #prints == b + 1 and prints[b + 1]:find("no pair$")
		and LastLog():find("DEV thanks ok=0", 1, true), prints[b + 1])
	-- dev "real": a count in the ach save (In Sync) keeps the larger one
	SpokenWindDB.ach.sync = 3
	Slash("dev ach fire gas")
	ns.AchInSync("party") ns.AchInSync("party")
	Slash("dev ach real")
	ok("dev real: In Sync count = the larger one", SpokenWindDB.ach.sync == 5 and Done().gas == nil, SpokenWindDB.ach.sync)
	SpokenWindDB.ach.sync = 4
	Slash("dev ach fire gas")
	SpokenWindDB.ach.sync = 1
	Slash("dev ach real")
	ok("dev real: a smaller test count never lowers the saved one", SpokenWindDB.ach.sync == 4, SpokenWindDB.ach.sync)
end

-- ---- the collection save (no page yet): farts that PLAYED, by sound file
Boot(nil)
ok("dex: empty at first, BOOT dex=0", next(SpokenWindDB.dex) == nil and ns.DexCount() == 0
	and LastLog():find(" n=1351 len=1351/1351 dex=0 own=", 1, true), LastLog())
now = now + 5 Run()
Own()
local f1 = LastPlay():match(" snd=(%d+)")
local s1 = ns.EMOTES.FART.sounds[tonumber(f1)].file
local e1 = SpokenWindDB.dex[s1]
ok("dex: own fart: n=1, own=1, first time", e1 and e1.n == 1 and e1.own == 1 and e1.t == clock, s1)
ok("dex: logged once per new sound", LogHas(("DEX add key=%s num=%s src=own"):format(s1, f1)), LastLog())
local nAdd = Count("DEX add")
ns.DexAdd("FART", tonumber(f1), "emote")
ok("dex: same sound again: n+1, own same, no new line", e1.n == 2 and e1.own == 1 and Count("DEX add") == nAdd)
now = now + 5 Run()
Heard(PG, "Pat", 7, 1)
local s7 = ns.EMOTES.FART.sounds[7].file
ok("dex: a message fart = src=msg", SpokenWindDB.dex[s7] and SpokenWindDB.dex[s7].own == 0
	and LogHas(("DEX add key=%s num=7 src=msg"):format(s7)), LastLog())
now = now + 5 Run()
local nd = ns.DexCount()
Emote(FartBy("Bob"), "Bob", BOB)
now = now + 0.3 Run()
local fe = tonumber(LastPlay():match(" snd=(%d+)"))
ok("dex: an emote fart = src=emote", SpokenWindDB.dex[ns.EMOTES.FART.sounds[fe].file] ~= nil
	and (ns.DexCount() == nd + 1 and LogHas(("num=%d src=emote"):format(fe)) or ns.DexCount() == nd))
willPlay = false
now = now + 5 Run()
local before = {}
for k, e in pairs(SpokenWindDB.dex) do before[k] = e.n end
Emote(FartBy("Cid"), "Cid", "Player-1-CID")
now = now + 0.3 Run()
willPlay = true
ok("dex: muted channel = not heard, no count", (function()
	for k, e in pairs(SpokenWindDB.dex) do if before[k] ~= e.n then return false end end
	return true
end)())
SpokenWindDB.on = false
now = now + 5 Run()
Emote(FartBy("Dee"), "Dee", "Player-1-DEE")
now = now + 0.3 Run()
SpokenWindDB.on = true
ok("dex: off = no count", (function()
	for k, e in pairs(SpokenWindDB.dex) do if before[k] ~= e.n then return false end end
	return true
end)())
now = now + 5 Run()
local np = #plays
ev.scripts.OnEvent(ev, "CHAT_MSG_EMOTE", "plays the tuba. It is not a tuba.", "Eve", "", "", "", "", 0, 0, "", 0, 123,
	"Player-1-EVE")
now = now + 0.3 Run()
ok("dex: a reward line plays but never counts", #plays == np + 1 and (function()
	for k, e in pairs(SpokenWindDB.dex) do if before[k] ~= e.n then return false end end
	return true
end)())
ns.DexAdd("CHEER", 1, "own")
ns.DexAdd("FART", 9999, "own")
ns.DexAdd("FART", 0, "own")
ok("dex: other sets and bad numbers: nothing", (function()
	for k, e in pairs(SpokenWindDB.dex) do if before[k] ~= e.n then return false end end
	return true
end)())
ns.EMOTES.ZZTEST = { folder = "zz", sounds = { { file = "01_zz", name = "Zz" } } }
ns.DexAdd("ZZTEST", 1, "own")
ns.EMOTES.ZZTEST = nil
ok("dex: a sound of another set never counts", SpokenWindDB.dex["01_zz"] == nil)
ok("dex: no player names in the save", (function()
	for k, e in pairs(SpokenWindDB.dex) do
		local known = false
		for _, s in ipairs(ns.EMOTES.FART.sounds) do if s.file == k then known = true end end
		if not known or not k:match("^[%w_]+$") then return false end
		for f in pairs(e) do if f ~= "n" and f ~= "t" and f ~= "own" then return false end end
	end
	return true
end)())
local nk = ns.DexCount()
Boot(SpokenWindDB)
ok("dex: kept over a reload, BOOT dex=N", ns.DexCount() == nk and LastLog():find((" dex=%d "):format(nk), 1, true), LastLog())
SpokenWindDB.dex = { ["01_squeak"] = { n = 3, t = 5, own = 9 }, ["bad key!"] = { n = 1 }, ["02_rumble"] = { n = 0 },
	["03_x"] = "junk", [5] = { n = 1 }, ["04_y"] = { n = 2.5, t = "x" } }
Boot(SpokenWindDB)
local dx = SpokenWindDB.dex
ok("dex: bad save cleaned", dx["01_squeak"] and dx["01_squeak"].n == 3 and dx["01_squeak"].own == 3 and dx["01_squeak"].t == 5
	and dx["bad key!"] == nil and dx["02_rumble"] == nil and dx["03_x"] == nil and dx[5] == nil
	and dx["04_y"] and dx["04_y"].n == 2 and dx["04_y"].t == 0 and ns.DexCount() == 2, ns.DexCount())
SpokenWindDB.dex = "junk"
Boot(SpokenWindDB)
ok("dex: junk save -> empty", type(SpokenWindDB.dex) == "table" and next(SpokenWindDB.dex) == nil)
local realD = ns.DexAdd
ns.DexAdd = function() error("dex boom") end
np = #plays
now = now + 5 Run()
Emote(FartBy("Fay"), "Fay", "Player-1-FAY")
now = now + 0.3 Run()
ok("dex: an error never breaks the sound", #plays == np + 1 and LogHas("ERR dex"))
ns.DexAdd = realD
IsInGroup, IsInGuild = nil, nil
end)()

;(function()   -- the Collection tab + rows 18-22 (0.6.3): own function (the main chunk is near 200 locals)
local function Boot(db)
	ev, ns = Load(db, "vertical")
	SpokenWindDB.cd = 0
	willPlay = true
	return ns
end
local function Done() return SpokenWindDB.ach.done end
local function Row(id, pg)   -- the Collection tab tile of a row
	for _, t in ipairs(ns.AchLines("collection", pg).tiles) do if t.id == id then return t end end
end
local function Count(s)
	local k = 0
	for _, l in ipairs(SpokenWindDB.log) do if l:find(s, 1, true) then k = k + 1 end end
	return k
end
local function Run()
	local i = 1
	while i <= #SY.timers do
		local t = SY.timers[i]
		if t.at <= now + 1e-9 then table.remove(SY.timers, i) t.fn() else i = i + 1 end
	end
end
local function Toasts()   -- click the toasts away
	while ns.ToastFrame() and ns.ToastFrame().shown do ns.ToastFrame().scripts.OnMouseUp(ns.ToastFrame()) end
end
local function Pool(n, name, voice)   -- a fake pool page of n sounds (keys k001...)
	local p = { name = name or "Big", voice = voice, tiles = {} }
	for i = 1, n do p.tiles[i] = { key = ("k%03d"):format(i), num = i, name = "K" .. i, q = 1, token = "FART", i = 1 } end
	return p
end
local function Hear(a, b) for i = a, b do SpokenWindDB.dex[("k%03d"):format(i)] = { n = 1, t = clock, own = 0 } end end
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t"
local GOLD, GREY = "|cffffd100", "|cff9d9d9d"

SY.noPacks = true   -- this block: the packs do not load = the old 14 (the 0.6.3 page tests); the set: 0.7.0 block
Boot(nil)
local L = ns.AchLines("collection")
ok("collection: tab head 0/5, the 5 rows in order", ns.AchTabText("collection") == "Collection 0/5" and #L.tiles == 5
	and L.tiles[1].id == "starter" and L.tiles[5].id == "complete", ns.AchTabText("collection"))
ok("collection: top line = heard / pool + own", L.stats == "Heard 0/14 · " .. STAR .. " Own 0", L.stats)
ok("collection: one page today, the live 14", L.pages == 1 and L.page == 1 and L.pageHead == "Original 0/14"
	and #L.sounds == 14 and L.have == 0 and L.all == 14, L.pageHead)
ok("collection: Starter Pack counts, the rest Soon (the pool has 14)", Row("starter").stat == "0/10"
	and Row("collector").stat == "Soon" and Row("gasologist").stat == "Soon" and Row("pitch").stat == "Soon"
	and Row("complete").stat == "Soon", Row("starter").stat)
local u = L.sounds[1]
ok("collection: not heard = dim #1 ???, cannot play", u.text == GREY .. "#1 ???|r" and u.name == "#1 ???"
	and u.rule == "Not heard yet" and u.stat == "" and not u.heard and not u.star and u.token == nil and u.gold == nil, u.text)
ok("collection: the other tabs keep their own strip, no sounds", ns.AchLines("classic").sounds == nil
	and ns.AchLines("social").stats == ns.AchStatsText() and ns.AchLines("social").sounds == nil)
-- 10 different sounds (Collection.lua calls AchDex on every played fart)
for i = 1, 9 do ns.DexAdd("FART", i, "emote") end
ns.DexAdd("FART", 3, "own")
ok("Starter Pack: 9 different (one twice) is not", Done().starter == nil and Row("starter").stat == "9/10", Row("starter").stat)
ns.DexAdd("FART", 10, "own")
ok("Starter Pack: the 10th different sound", Done().starter ~= nil and LogHas("ACH starter toast=1"), LastLog())
local T = ns.ToastFrame()
ok("Starter Pack: toast with the game's bag icon", T and T.shown and ns.ToastRefs().icon.path == "Interface\\Icons\\INV_Misc_Bag_10",
	ns.ToastRefs().icon.path)
Toasts()
ok("collection: nothing else earned", Done().collector == nil and Done().gasologist == nil and Done().pitch == nil
	and Done().complete == nil)
L = ns.AchLines("collection")
local s3 = L.sounds[3]
ok("collection: heard tile = grey #, the name in its color, star for an own roll", s3.heard and s3.star and s3.done
	and s3.text == GREY .. "#3|r " .. ns.AchColor(1) .. "Wet|r" and s3.name == "#3 Wet" and s3.token == "FART" and s3.i == 3,
	s3.text)
ok("collection: tip lines: heard + own, first date, click", s3.rule == "Heard 2 · Own 1"
	and s3.stat == "First " .. os.date("%m-%d", clock) and s3.gold == "Click = play", s3.rule)
ok("collection: heard from others only = no star", L.sounds[1].heard and not L.sounds[1].star and not L.sounds[11].heard)
ok("collection: top line + page head count", L.stats == "Heard 10/14 · " .. STAR .. " Own 2" and L.pageHead == "Original 10/14"
	and ns.AchTabText("collection") == "Collection 1/5", L.stats)

;(function()   -- the window on the Collection tab: strip, 5 tiles, voice chips, the sound list (pages of 4 a row)
	local b, nc, na = #prints, #sent, #SY.asent
	local NB, ST = "\194\160", "|TInterface\\AddOns\\Spoken_Wind\\Media\\star.tga:0:0:0:0:64:64:0:64:0:64:255:209:0|t"
	local function Snd()   -- the shown sound slots, in order: { s, n, star, line }
		local out = {}
		local _, bb, _, lineOf = Id.W()
		for _, r in ipairs(bb._swRows or {}) do
			for _, X in ipairs({ "A", "B", "C", "D" }) do
				local s = r["s" .. X]
				if s and s.shown then out[#out + 1] = { s = s, n = r["n" .. X], star = r["star" .. X], line = lineOf[s] } end
			end
		end
		return out
	end
	local function Chips()   -- the shown chips: "label=state,..."
		local _, bb = Id.W()
		local t = {}
		for k = 1, 20 do
			local c = bb["v" .. k]
			if c.shown then t[#t + 1] = bb["v" .. k .. "Text"].text .. "=" .. SY.State(c) end
		end
		return table.concat(t, ",")
	end
	local function Pg(B) return (B.page._lookText or B.page).text end
	ok("collection window: /wind ach collection opens it, DEX show logged", (function()
		Slash("ach collection")
		return LogHas("ACH open tab=collection n=5") and LastLog():find("DEX show n=10/14 page=1/1$") ~= nil
	end)(), LastLog())
	local W, B = Id.W()
	local R = W.root
	ok("collection window: Collection tab selected, its count", SY.State(W.tabColl) == "sel" and SY.State(W.tabClassic) ~= "sel"
		and W.tabCollText.text == "Collection 1/5" and W.tabClassicText.text == "Classic 0/15", W.tabCollText.text)
	ok("collection window: strip = heard/all, star + own", B.sounds.text == "10/14" and B.ownG.text == ST and B.own.text == "2",
		B.sounds.text .. " " .. B.own.text)
	ok("star: a texture in the text, no font glyph (never a box)", B.ownG.text:sub(1, 2) == "|T" and B.ownG.text:sub(-2) == "|t"
		and not B.ownG.text:find("\226\152\133", 1, true), B.ownG.text)
	do   -- the star file: the path in the text is a real file, 64x64, 32 bit, white, a star (solid middle, clear corners)
		local p = B.ownG.text:match("^|T(.-):")
		local rel = p and p:match("^Interface\\AddOns\\Spoken_Wind\\(.+)$")
		local fh = rel and io.open(ADDON_DIR .. "/" .. rel:gsub("\\", "/"), "rb")
		local d = fh and fh:read("*a")
		if fh then fh:close() end
		local good = d and #d == 18 + 64 * 64 * 4 and d:byte(3) == 2 and d:byte(13) + 256 * d:byte(14) == 64
			and d:byte(15) + 256 * d:byte(16) == 64 and d:byte(17) == 32 and d:byte(18) == 8
		local white, mid, corner = true, nil, nil
		if good then
			for i = 19, #d, 4 do
				if d:byte(i + 3) > 0 and not (d:byte(i) == 255 and d:byte(i + 1) == 255 and d:byte(i + 2) == 255) then white = false end
			end
			local function A(x, y) return d:byte(19 + ((63 - y) * 64 + x) * 4 + 3) end   -- y = 0 at the top (file: bottom row first)
			mid, corner = A(32, 33), math.max(A(0, 0), A(63, 0), A(0, 63), A(63, 63))
		end
		ok("star: Media/star.tga = 64x64 32 bit, white, solid middle, clear corners", good and white and mid == 255 and corner == 0,
			tostring(p) .. " " .. tostring(d and #d) .. " " .. tostring(mid) .. " " .. tostring(corner))
		local g = ns.Looks["sw-ach-collection"].palette.gold
		local tint = B.ownG.text:match(":(%d+):(%d+):(%d+)|t$")
		local r1, g1, b1 = B.ownG.text:match(":(%d+):(%d+):(%d+)|t$")
		ok("star: tinted with the design gold", tint ~= nil and tonumber(r1) == math.floor(g[1] * 255 + 0.5)
			and tonumber(g1) == math.floor(g[2] * 255 + 0.5) and tonumber(b1) == math.floor(g[3] * 255 + 0.5), B.ownG.text)
	end
	local TL = Id.tiles()
	ok("collection window: the 5 rows as tiles, earned first", #TL == 5 and TL[1].line.id == "starter"
		and TL[1].icon.path == "Interface\\Icons\\INV_Misc_Bag_10" and TL[1].icon.desat == false and SY.State(TL[1].cell) == "base"
		and TL[1].name.text == ns.AchColor(2) .. "Starter Pack|r" and TL[2].icon.desat == true and SY.State(TL[2].cell) == "off",
		#TL .. " " .. tostring(TL[1] and TL[1].name.text))
	ok("collection window: one voice chip (the pool has one page), selected", Chips() == "Orig 10=sel", Chips())
	ok("collection window: page head = name + heard/all", B.pageHeadText.text == "Original" and B.pageHave.text == "10/14",
		B.pageHeadText.text .. " " .. B.pageHave.text)
	local Sd = Snd()
	ok("collection window: 14 sound slots, 4 a row", #Sd == 14 and #B._swRows == 4, #Sd)
	ok("collection window: heard slot = dim #, the name in its color, the star for an own roll", Sd[3].line.key == "03_wet"
		and Sd[3].n.text == GREY .. "#3" .. NB .. "|r" .. ns.AchColor(1) .. "Wet|r" and Sd[3].star.text == ST
		and Sd[3].star.alpha == 1 and Sd[1].star.alpha == 0 and SY.State(Sd[3].s) == "base", Sd[3].n.text)
	ok("star: every sound slot has the star texture (alpha shows / hides it)", (function()
		for _, x in ipairs(Sd) do
			if x.star.text ~= ST or x.star.alpha ~= (x.line.star and 1 or 0) then return false end
		end
		return true
	end)())
	ok("collection window: not heard = dim #11 ???, off", Sd[11].n.text == GREY .. "#11" .. NB .. "???|r"
		and SY.State(Sd[11].s) == "off" and Sd[11].star.alpha == 0, Sd[11].n.text)
	ok("collection window: one page of sounds = 1/1, both arrows dim", Pg(B) == "1/1" and B.prev.alpha < 1 and B.next.alpha < 1,
		Pg(B))
	ok("collection window: no chat line", #prints == b and #sent == nc and #SY.asent == na)
	-- the tips
	Id.on(Sd[3].s)
	local sh, title, rows = Id.tip()
	ok("collection tip: #, name, tier, heard, own, first, click play", sh and title == GREY .. "#3 |r" .. ns.AchColor(1) .. "Wet|r"
		and rows:find("^Tier=|c%x+%a[%a ]*|r|Heard=2|Own=1|First=" .. (os.date("%m-%d", clock):gsub("%-", "%%-"))
			.. "|Click=|c%x+Play|r$") ~= nil, tostring(title) .. " " .. rows)
	Id.on(Sd[11].s)
	sh, title, rows = Id.tip()
	ok("collection tip: not heard = Heard 0", title == GREY .. "#11 ???|r" and rows == "Heard=0", tostring(title) .. " " .. rows)
	Id.on(TL[1].cell)
	sh, title, rows = Id.tip()
	ok("collection tip: a tile = the row tip", title == ns.AchColor(2) .. "Starter Pack|r"
		and rows:find("^Rule=Hear 10 sounds|Tier=|c%x+%a[%a ]*|r|Done=") ~= nil, rows)
	Id.off(TL[1].cell)
	ok("collection tip: leave closes it", not (Id.tip()))
	local ut, nUt = ns.UITip, 0
	ns.UITip = function(...) nUt = nUt + 1 return ut(...) end
	combat = true
	Id.on(TL[1].cell)
	combat = false
	ok("collection tip: never in combat (no tip call)", not (Id.tip()) and nUt == 0, nUt)
	Id.off(TL[1].cell)
	ns.AchRedraw() ns.AchRedraw() ns.AchRedraw()
	Id.on(TL[1].cell)
	ns.UITip = ut
	Id.off(TL[1].cell)
	ok("collection tip: hooked once (3 redraws, 1 hover = 1 tip)", nUt == 1, nUt)
	-- ns.UITip itself: no tip in combat; ns.UITipHide(owner) hides only the tip of that owner
	local ROWS, other = { { "a", "b" } }, {}
	combat = true
	local okC = ns.UITip(TL[1].cell, "T", ROWS)
	combat = false
	ok("ui tip: in combat = false, no tip", okC == false and not (Id.tip()), tostring(okC))
	ok("ui tip: out of combat = shown", ns.UITip(TL[1].cell, "T", ROWS) == true and (Id.tip()))
	ns.UITipHide(other)
	ok("ui tip: hide for an other owner keeps it", (Id.tip()))
	ns.UITipHide(TL[1].cell)
	ok("ui tip: hide for its owner hides it", not (Id.tip()))
	ns.UITip(TL[1].cell, "T", ROWS)
	ns.UITipHide()
	ok("ui tip: hide with no owner hides any tip", not (Id.tip()))
	-- a click plays a heard sound here only
	local function Play(k, btn) SY.Click(Sd[k].s, btn) end
	local np, nfl = #plays, #SpokenWindDB.farts
	local n3 = SpokenWindDB.dex["03_wet"].n
	Play(11)
	ok("collection click: a sound not heard yet = nothing", #plays == np)
	local dp, nDp = ns.DexPlay, 0
	ns.DexPlay = function(...) nDp = nDp + 1 return dp(...) end
	Play(11)
	ns.DexPlay = dp
	ok("collection click: a sound not heard yet: no play call", nDp == 0, nDp)
	Play(3, "RightButton")
	ok("collection click: right click = nothing", #plays == np)
	Play(3)
	ok("collection click: plays it here, logged", #plays == np + 1 and plays[#plays].path == ns.MEDIA .. "fart\\03_wet.ogg"
		and plays[#plays].ch == SpokenWindDB.ch and LastLog():find("DEX play key=03_wet ok=1$") ~= nil, LastLog())
	ok("collection click: no count, no fart log, no emote, no chat", SpokenWindDB.dex["03_wet"].n == n3
		and #SpokenWindDB.farts == nfl and #prints == b and #sent == nc and #SY.asent == na and Done().first == nil)
	now = now + 0.5
	Play(1)
	ok("collection click: max 1 per second", #plays == np + 1)
	now = now + 0.5
	Play(1)
	ok("collection click: one preview at a time (Wet still plays): ignored, logged", #plays == np + 1
		and LastLog():find("DEX busy key=01_squeak left=0.8", 1, true) ~= nil, LastLog())
	now = now + 0.78
	Play(1)
	ok("collection click: after the preview ends it plays", #plays == np + 2
		and plays[#plays].path == ns.MEDIA .. "fart\\01_squeak.ogg" and LastLog():find("DEX play key=01_squeak ok=1$") ~= nil,
		LastLog())
	now = now + 2
	combat = true
	Play(1)
	combat = false
	ok("collection click: never in combat", #plays == np + 2)
	now = now + 2
	willPlay = false
	Play(1)
	willPlay = true
	ok("collection click: sound off = logged ok=0", LastLog():find("DEX play key=01_squeak ok=0$") ~= nil, LastLog())
	now = now + 1.1
	Play(3)
	ok("collection click: a sound that did not play holds nothing", #plays == np + 4, #plays - np)
	-- a client with StopSound: the old preview stops, the new one plays
	local stopped = {}
	StopSound = function(h) stopped[#stopped + 1] = h end
	now = now + 1.1
	Play(1)
	StopSound = nil
	ok("collection click: StopSound: the old preview stops, the new one plays", #plays == np + 5 and #stopped == 1
		and stopped[1] == 77 and LastLog():find("DEX play key=01_squeak ok=1 stop=1$") ~= nil, LastLog())
	-- StopSound + a new preview that did not play: nothing is held after it
	local wetLen = ns.LEN["03_wet"]
	ns.LEN["03_wet"] = 3000
	stopped = {}
	StopSound = function(h) stopped[#stopped + 1] = h end
	now = now + 5
	Play(3)
	now = now + 1.1
	willPlay = false
	Play(1)
	willPlay = true
	now = now + 1.1
	Play(1)
	StopSound = nil
	ns.LEN["03_wet"] = wetLen
	ok("collection click: StopSound + a preview that did not play: nothing held after it", #stopped == 1
		and LastLog():find("DEX play key=01_squeak ok=1$") ~= nil, #stopped .. " " .. LastLog())
	-- a short preview (0.2 s): the 1 s gap still holds on its own
	ns.LEN["03_wet"] = 200
	now = now + 5
	Play(3)
	local npg = #plays
	now = now + 0.6
	Play(1)
	ok("collection click: a short preview: 0.6 s later the 1 s gap blocks", #plays == npg
		and LastLog():find("DEX play key=03_wet ok=1$") ~= nil, LastLog())
	now = now + 0.41
	Play(1)
	ok("collection click: a short preview: 1.01 s later it plays", #plays == npg + 1, #plays - npg)
	ns.LEN["03_wet"] = wetLen
	ok("collection click: no bad tile, no play", ns.DexPlay(nil) == false and ns.DexPlay({ key = "x" }) == false)
	-- tabs
	Id.tab("Classic")
	local _, BC = Id.W()
	ok("collection -> Classic: the Collection body hidden, 16 Classic tiles", not B.root.shown and BC.root.shown
		and #Id.tiles() == 16, #Id.tiles())
	local nShow = Count("DEX show")
	Id.tab("Coll")
	ok("collection tab: back = sounds again, DEX show logged", B.root.shown and not BC.root.shown and #Snd() == 14
		and Count("DEX show") == nShow + 1, Count("DEX show"))
	Id.tab("Social")
	ok("collection -> Social: no DEX show", Count("DEX show") == nShow + 1)
	-- a toast click on a Collection row = the Collection tab, its tile glows
	local t0 = now   -- the glow steps move the clock; put it back after
	Id.tab("Classic")
	local tab, glow = ns.AchShow("starter")
	local g = Id.tile("starter")
	local G = g and g.cell._swGlow
	ok("collection glow: a Collection row = the Collection tab, its tile glows (one)", tab == "collection" and glow == true
		and SY.State(W.tabColl) == "sel" and #Snd() == 14 and Id.glow(g) and Id.nglow() == 1 and Near(G.vc, 0x1e, 0xff, 0x00),
		tostring(tab))
	ok("collection glow: sized for its icon (1.7 x)", math.abs(G.w - g.icon:GetWidth() * 1.7) < 0.01 and G.w == G.h, G.w)
	now = now + 5.1 R.scripts.OnUpdate(R, 5.1)
	ok("collection glow: off after 5 s", not G.shown and R.scripts.OnUpdate == nil)
	local g2 = ns.AchGlow("starter")
	Id.on(g.cell)
	ok("collection glow: the mouse on it ends it", g2 and not G.shown and R.scripts.OnUpdate == nil)
	Id.off(g.cell)
	-- the tiles sort like the other tabs: earned first, rarest first, then the locked ones in list order
	Done().pitch, Done().collector = clock, clock
	ns.AchOpen("collection")
	local ids = {}
	for i, t in ipairs(Id.tiles()) do ids[i] = t.line.id end
	ok("collection sort: earned rarest first (Epic, Rare, Uncommon), then locked in list order",
		table.concat(ids, ",") == "pitch,collector,starter,gasologist,complete", table.concat(ids, ","))
	ok("collection sort: the glow lands on the row's new spot", ns.AchGlow("starter") and Id.glow(Id.tiles()[3])
		and not Id.glow(Id.tiles()[1]))
	Done().pitch, Done().collector = nil, nil
	ns.AchOpen("collection")
	ok("collection sort: back to the list order, the glow follows", Id.tiles()[1].line.id == "starter"
		and Id.tiles()[2].line.id == "collector" and Id.glow(Id.tiles()[1]) and not Id.glow(Id.tiles()[3]), Id.tiles()[1].line.id)
	ns.AchGlow("none")   -- stops the glow
	now = t0
	-- voice pages (the 1337 set adds them as data): one chip a page, a click shows it
	local realP = ns.DexPages
	ns.DexPages = function()
		local v = { name = "Troll m", voice = true, tiles = {} }
		for i = 1, 4 do
			v.tiles[i] = { key = ("t_m_%02d"):format(i), num = 100 + i, name = "T" .. i, q = 3, token = "FART", i = i }
		end
		return { realP()[1], v }
	end
	local twoP = ns.DexPages
	ns.AchOpen("collection")
	ok("chips: 2 pages = 2 chips, the voice page with no sound heard = off", Chips() == "Orig 10=sel,Tr M 0=off", Chips())
	Id.tab("Classic")
	Id.tab("Coll")
	ok("pages: Perfect Pitch counts once a voice page is there", Row("pitch").stat == "0/4"
		and Row("collector").stat == "Soon", Row("pitch").stat)
	local pT = Id.tiles()[1].cell   -- a pinned tip: a chip click unpins it
	Id.on(pT)
	SY.Click(pT)
	Id.off(pT)
	ok("chips: a tile tip pinned", select(5, Id.W()) == pT)
	b = #prints
	SY.Click(B.v2)
	Sd = Snd()
	ok("chips: a click = that page, its 4 sounds only, DEX show logged", B.pageHeadText.text == "Troll m"
		and B.pageHave.text == "0/4" and #Sd == 4 and Sd[1].n.text == GREY .. "#101" .. NB .. "???|r"
		and LastLog():find("DEX show n=10/18 page=2/2$") ~= nil and #prints == b, B.pageHeadText.text .. " " .. LastLog())
	ok("chips: a chip click unpins the tip", select(5, Id.W()) == nil and not (Id.tip()))
	ok("chips: the selected chip moves", Chips() == "Orig 10=base,Tr M 0=sel", Chips())
	local nShow2 = Count("DEX show")
	SY.Click(B.v2)
	SY.Click(B.v2, "RightButton")
	ok("chips: the shown page again = nothing", Count("DEX show") == nShow2 and Chips() == "Orig 10=base,Tr M 0=sel")
	for i = 1, 3 do SpokenWindDB.dex[("t_m_%02d"):format(i)] = { n = 1, t = clock, own = 0 } end
	ns.AchDex()
	ok("Perfect Pitch: 3 of 4 is not", Done().pitch == nil and Row("pitch").stat == "3/4", Row("pitch").stat)
	SpokenWindDB.dex.t_m_04 = { n = 1, t = clock, own = 1 }
	ns.AchDex()
	ok("Perfect Pitch: every sound of one voice", Done().pitch ~= nil and LogHas("ACH pitch toast=1"))
	Sd = Snd()
	ok("pages: the open window redraws at once", B.pageHave.text == "4/4" and Sd[4].star.alpha == 1
		and Chips() == "Orig 10=base,Tr M 4=sel", B.pageHave.text .. " " .. Chips())
	SY.Click(B.v1)
	ok("chips: a full page = good", Chips() == "Orig 10=sel,Tr M 4=good", Chips())
	Toasts()
	ok("pages: the page number clamps", ns.AchLines("collection", 9).page == 2 and ns.AchLines("collection", 0).page == 1
		and ns.AchLines("collection", "x").page == 1 and ns.AchLines("collection", 1.5).page == 1)
	ns.DexPages = function()   -- the best voice page shows the Perfect Pitch progress
		local a, c = Pool(4, "Gnome f", true), Pool(6, "Orc m", true)
		for i = 1, 6 do c.tiles[i].key = ("o%03d"):format(i) end
		return { a, c }
	end
	Done().pitch = nil
	Hear(1, 2)
	for i = 1, 3 do SpokenWindDB.dex[("o%03d"):format(i)] = { n = 1, t = clock, own = 0 } end
	ok("Perfect Pitch: progress = the voice with the most heard", Row("pitch").stat == "3/6", Row("pitch").stat)
	SpokenWindDB.dex.o003 = nil
	ok("Perfect Pitch: a tie keeps the first voice", Row("pitch").stat == "2/4", Row("pitch").stat)
	SpokenWindDB.dex.o001, SpokenWindDB.dex.o002 = nil, nil
	Hear(3, 4)
	ns.AchDex()
	ok("Perfect Pitch: a small voice page full counts too", Done().pitch ~= nil)
	Toasts()
	ns.AchOpen("collection")
	ok("chips: Gnome f + Orc m = short race + sex", Chips() == "Gn F 4=sel,Or M 0=off", Chips())
	ns.DexPages = twoP
	SY.Click(B.v2)
	ns.DexPages = realP
	for _, k in ipairs({ "t_m_01", "t_m_02", "t_m_03", "t_m_04", "k001", "k002", "k003", "k004" }) do SpokenWindDB.dex[k] = nil end
	ns.AchOpen("collection")
	ok("pages: back to one page: the page clamps, one chip", Chips() == "Orig 10=sel" and B.pageHeadText.text == "Original"
		and #Snd() == 14, Chips())
	do   -- 0.8.4 chip wrap: the shown chips flow left to right, a chip that does not fit starts the next line (min 2 = the design)
		local E = 0.001
		local function Due()   -- the due timers (After(0) = now)
			local i = 1
			while i <= #SY.timers do
				local x = SY.timers[i]
				if x.at <= now + 1e-9 then table.remove(SY.timers, i) x.fn() else i = i + 1 end
			end
		end
		local function Lay()   -- the shown chips in order { c, l, r, t, b, w } + the number of lines
			local out, tops, n = {}, {}, 0
			for k = 1, 20 do
				local c = B["v" .. k]
				if c.shown then
					out[#out + 1] = { c = c, l = c:GetLeft(), r = c:GetRight(), t = c:GetTop(), b = c:GetBottom(), w = c:GetWidth() }
					local key = ("%.3f"):format(c:GetTop())
					if not tops[key] then tops[key] = true; n = n + 1 end
				end
			end
			return out, n
		end
		local function SndPt(name)   -- the sound list's point: y, rel
			for _, p in ipairs(B.sndList.points) do if p[1] == name then return p[5], p[2] end end
		end
		local RL, RR = B.root:GetLeft() + 10, B.root:GetRight() - 10   -- the chip row: the tab body less 10 a side (the design)
		local ch, nl = Lay()
		local y0, rel0 = SndPt("TOPLEFT")
		ok("chip wrap: 1 chip = the design: box 70.635 high, the chip at 10 / -4, the sound list at -276.635 (bottom unchanged)",
			#ch == 1 and nl == 1 and math.abs(B.voices:GetHeight() - 70.635) < E and math.abs(ch[1].l - RL) < E
			and math.abs(ch[1].t - (B.voices:GetTop() - 4)) < E and rel0 == B.root and math.abs(y0 + 276.635) < E
			and #B.sndList.points == 2 and SndPt("BOTTOMRIGHT") == 34, B.voices:GetHeight() .. " " .. tostring(y0))
		-- 20 pages with wide labels ("Voice02 M 0"): far more than 2 lines of the design hold
		ns.DexPages = function()
			local t = { realP()[1] }
			for i = 2, 20 do t[i] = Pool(4, ("Voice%02d %s"):format(i, i % 2 == 0 and "m" or "f"), true) end
			return t
		end
		ns.AchOpen("collection")
		ch, nl = Lay()
		local inside, order, full, gap = true, true, true, true
		for i, e in ipairs(ch) do
			if e.l < RL - E or e.r > RR + E then inside = false end
			local p = ch[i - 1]
			if p then
				if math.abs(e.t - p.t) < E then
					if math.abs(e.l - (p.r + 4)) > E then gap = false end
				elseif not (e.t < p.t - E and math.abs(e.l - RL) < E and math.abs(p.t - e.t - 32) < E) then order = false
				elseif p.r + 4 + e.w <= RR + E then full = false end   -- it went down though it fit on the line before
			end
		end
		ok("chip wrap: 20 wide chips: all 20 shown, in page order", #ch == 20 and Chips():match("^Orig 10=sel,Voice02 M 0=off,")
			and Chips():match(",Voice20 M 0=off$"), Chips())
		ok("chip wrap: every chip whole inside the row (10 px in from each side)", inside, ch[#ch] and ch[#ch].r .. " " .. RR)
		ok("chip wrap: 4 px between chips on a line; a new line starts at the row left, 32 px lower", gap and order)
		ok("chip wrap: a line holds every chip that fits (the first chip of a line did not fit on the line before)", full)
		local h3 = nl * 32 + 6.635
		y0 = SndPt("TOPLEFT")
		ok("chip wrap: 3 lines: the box grows to 102.635, the sound list starts at -308.635, the last line inside the box",
			nl == 3 and math.abs(B.voices:GetHeight() - h3) < E and math.abs(y0 + 206 + h3) < E and SndPt("BOTTOMRIGHT") == 34
			and ch[20].b >= B.voices:GetBottom() - E, nl .. " " .. B.voices:GetHeight() .. " " .. tostring(y0))
		-- a chip gets wider later (a font loads: Look.Refit): one wrap next frame; same lines = no redraw
		local nR, realR = 0, ns.AchRedraw
		ns.AchRedraw = function() nR = nR + 1 return realR() end
		local nT = #SY.timers
		B.v2:SetWidth(B.v2:GetWidth() + 30)
		for _ = 1, 3 do B.v2.scripts.OnSizeChanged(B.v2) end
		B.v3.scripts.OnSizeChanged(B.v3)
		local before = math.abs(B.v3:GetLeft() - (B.v2:GetRight() + 4)) > E
		ok("chip wrap: 4 size events = ONE wrap next frame (nothing moves before it)", #SY.timers == nT + 1 and SY.timers[#SY.timers].s == 0
			and before, #SY.timers - nT)
		Due()
		ch, nl = Lay()
		inside = true
		for _, e in ipairs(ch) do if e.l < RL - E or e.r > RR + E then inside = false end end
		ok("chip wrap: after it: the next chip moves along, all inside, same lines = no redraw",
			math.abs(B.v3:GetLeft() - (B.v2:GetRight() + 4)) < E and inside and nl == 3 and nR == 0, nl .. " " .. nR)
		-- every chip narrow (a smaller font): fewer lines = one redraw (the sound pages fit the new box)
		nT = #SY.timers
		for k = 1, 20 do B["v" .. k]:SetWidth(20); B["v" .. k].scripts.OnSizeChanged(B["v" .. k]) end
		ok("chip wrap: 20 size events = ONE wrap", #SY.timers == nT + 1)
		Due()
		ch, nl = Lay()
		ok("chip wrap: the line count changed = ONE redraw (it sizes the chips from their text again: 3 lines)", nR == 1 and nl == 3
			and math.abs(B.voices:GetHeight() - h3) < E, nR .. " " .. nl)
		-- the row width. The fake row frame has no size (0), like the game before the first layout: the tab body less 10 a
		-- side (606.73). 4 chips of 151 + 3 gaps = 616: too wide for it, so 3 a line. A redraw would size the chips from their
		-- text again: off here.
		ns.AchRedraw = function() end
		for k = 1, 20 do B["v" .. k]:SetWidth(151); B["v" .. k].scripts.OnSizeChanged(B["v" .. k]) end
		Due()
		ch, nl = Lay()
		inside = true
		for _, e in ipairs(ch) do if e.r > RR + E then inside = false end end
		ok("chip wrap: the row has no width yet: the tab body less 10 a side (3 chips of 151 a line, all inside)",
			B.vrow1:GetWidth() == 0 and inside and nl == 7, nl .. " " .. tostring(ch[4] and ch[4].r) .. " " .. RR)
		-- the row frame has a width (the game): that width. 2 chips of 151 + a gap = 306 fit in 400, 3 (461) do not
		B.vrow1.width = 400
		B.v1.scripts.OnSizeChanged(B.v1)
		Due()
		ch, nl = Lay()
		inside = true
		for _, e in ipairs(ch) do if e.r > RL + 400 + E then inside = false end end
		ok("chip wrap: the row frame's width when it has one (2 chips of 151 a line in 400)", inside and nl == 10, nl)
		B.vrow1.width = nil
		ns.AchRedraw = realR
		ns.DexPages = realP
		ns.AchOpen("collection")
		ch, nl = Lay()
		y0 = SndPt("TOPLEFT")
		ok("chip wrap: back to 1 page = the design again (70.635, the chip at the row left, the list at -276.635)",
			#ch == 1 and math.abs(B.voices:GetHeight() - 70.635) < E and math.abs(ch[1].l - RL) < E and math.abs(y0 + 276.635) < E,
			B.voices:GetHeight() .. " " .. tostring(y0))
	end
	-- a big page (74 sounds): 10 rows a page, the arrows turn it
	ns.DexPages = function() return { Pool(74, "Big"), Pool(4, "Small") } end
	Hear(41, 41)
	ns.AchOpen("collection")
	Sd = Snd()
	ok("sound pages: 74 sounds = 40 a page, page 1/2, < dim, > on", #Sd == 40 and #B._swRows == 10 and Pg(B) == "1/2"
		and B.prev.alpha < 1 and B.next.alpha == 1 and Sd[1].line.num == 1, #Sd .. " " .. Pg(B))
	local nf = #frames
	Id.on(Sd[1].s)
	SY.Click(Sd[1].s)
	SY.Click(B.next)
	Sd = Snd()
	ok("sound pages: > = page 2: the rest, from #41; the tip unpinned", Pg(B) == "2/2" and #Sd == 34 and Sd[1].line.num == 41
		and Sd[1].line.heard and B.prev.alpha == 1 and B.next.alpha < 1 and not (Id.tip()) and select(5, Id.W()) == nil,
		Pg(B) .. " " .. #Sd)
	SY.Click(B.next)
	ok("sound pages: > on the last page = nothing", Pg(B) == "2/2")
	ns.AchRedraw()
	ok("sound pages: a redraw keeps the page", Pg(B) == "2/2" and Snd()[1].line.num == 41)
	ns.Look.Relayout(B)
	ok("sound pages: a list refresh (same page) = the slots once", B._lists ~= nil and Pg(B) == "2/2" and #Snd() == 34, #Snd())
	local pos = SpokenWindDB.achpos
	W.head.scripts.OnDragStart(W.head)
	W.head.scripts.OnDragStop(W.head)
	SpokenWindDB.achpos = pos
	ok("sound pages: a drag (relayout) keeps the page, the slots once", Pg(B) == "2/2" and #Snd() == 34, Pg(B) .. " " .. #Snd())
	SY.Click(B.v2)
	ok("sound pages: an other chip = its page from 1", Pg(B) == "1/1" and #Snd() == 4 and B.pageHeadText.text == "Small", Pg(B))
	SY.Click(B.v1)
	ok("sound pages: back = page 1 again", Pg(B) == "1/2" and Snd()[1].line.num == 1, Pg(B))
	SY.Click(B.next)
	SY.Click(B.prev)
	ok("sound pages: < = back", Pg(B) == "1/2")
	ns.DexPages = function() return { Pool(74, "Big"), Pool(60, "Big2") } end
	ns.AchOpen("collection")
	SY.Click(B.next)
	local pgA = Pg(B)
	combat = true
	SY.Click(B.v2)
	combat = false
	ok("chips: a click in combat = nothing", pgA == "2/2" and B.pageHeadText.text == "Big" and Pg(B) == "2/2",
		B.pageHeadText.text .. " " .. Pg(B))
	SY.Click(B.v2)
	ok("sound pages: an other chip with 2 pages = its page 1", B.pageHeadText.text == "Big2" and Pg(B) == "1/2",
		B.pageHeadText.text .. " " .. Pg(B))
	SY.Click(B.v1)
	ns.AchOpen("collection")
	ok("collection window: chips, pages + reopen make no new frames", #frames == nf, #frames - nf)
	ns.DexPages = realP
	SpokenWindDB.dex.k041 = nil
	ns.AchOpen("collection")
	ok("collection window: never takes keys", R.kb == nil and R.prop == nil and R.scripts.OnKeyDown == nil)
	SY.Click(W.close)
	ok("collection window: X closes", not R.shown)
end)()

-- an old key (the 1337 set) adds onto its pool sound
ns.DEX_ALIAS.old_squeak = "01_squeak"
ns.DEX_ALIAS.old_rumble = "02_rumble"
ns.DEX_ALIAS.old_slow = "05_slowsqueak"
local e01 = SpokenWindDB.dex["01_squeak"]
SpokenWindDB.dex.old_squeak = { n = 5, t = 1, own = 2 }
SpokenWindDB.dex.old_rumble = { n = 1, t = 0, own = 0 }
SpokenWindDB.dex["05_slowsqueak"].t = 0
SpokenWindDB.dex.old_slow = { n = 1, t = 7, own = 0 }
SpokenWindDB.dex["06_triple"].t = 0
SpokenWindDB.dex.zz_gone = { n = 3, t = 1, own = 3 }
L = ns.AchLines("collection")
ok("alias: an old key adds onto its pool sound (count, own, first time)", L.have == 10 and L.sounds[1].star
	and L.sounds[1].rule == ("Heard %d · Own %d"):format(e01.n + 5, e01.own + 2)
	and L.sounds[1].stat == "First " .. os.date("%m-%d", 1), L.sounds[1].rule)
ok("alias: first time = the older one; 0 = not known", L.sounds[2].stat == "First " .. os.date("%m-%d", clock)
	and L.sounds[5].stat == "First " .. os.date("%m-%d", 7) and L.sounds[6].stat == "", L.sounds[5].stat)
ok("alias: a key not in the pool never counts", L.all == 14 and L.stats == "Heard 10/14 · " .. STAR .. " Own 3", L.stats)
ns.DEX_ALIAS.old_squeak, ns.DEX_ALIAS.old_rumble, ns.DEX_ALIAS.old_slow = nil, nil, nil
SpokenWindDB.dex.old_squeak, SpokenWindDB.dex.old_rumble, SpokenWindDB.dex.old_slow = nil, nil, nil
SpokenWindDB.dex.zz_gone = nil

-- the count rows (the 1337 set): Soon until the pool is big enough
local realP = ns.DexPages
ns.DexPages = function() return { Pool(500) } end
Done().pitch = nil
Hear(1, 99)
ns.AchDex()
ok("Collector: 99 is not; Gasologist counts now (pool 500); Complete Works still Soon", Done().collector == nil
	and Row("collector").stat == "99/100" and Row("gasologist").stat == "99/500" and Row("complete").stat == "Soon"
	and Row("pitch").stat == "Soon", Row("gasologist").stat)
local st = Done().starter
Done().starter = nil
ok("Starter Pack: progress stops at the goal (99 heard = 10/10)", Row("starter").stat == "10/10", Row("starter").stat)
Done().starter = st
Hear(100, 100)
ns.AchDex()
ok("Collector: 100 different sounds", Done().collector ~= nil and Done().gasologist == nil and LogHas("ACH collector toast=1"))
Toasts()
Hear(101, 499)
ns.AchDex()
ok("Gasologist: 499 is not", Done().gasologist == nil)
Hear(500, 500)
ns.AchDex()
ok("Gasologist: 500", Done().gasologist ~= nil and Done().complete == nil)
Toasts()
ns.DexPages = function() return { Pool(1337, "All") } end
ok("The Complete Works: 1337 sounds outside the set = Soon", Row("complete").stat == "Soon", Row("complete").stat)
ns.DexPages = function()
	local p = Pool(1337, "All")
	p.set = true   -- a race set page (Voices.lua)
	for i = 1000, 1337 do p.tiles[i].key = ("k%04d"):format(i) end
	return { p }
end
ok("The Complete Works: counts once the pool has 1337", Row("complete").stat == "500/1337", Row("complete").stat)
Hear(501, 999)
for i = 1000, 1336 do SpokenWindDB.dex[("k%04d"):format(i)] = { n = 1, t = clock, own = 0 } end
ns.AchDex()
ok("The Complete Works: 1336 is not", Done().complete == nil and Row("complete").stat == "1336/1337", Row("complete").stat)
SpokenWindDB.dex.k1337 = { n = 1, t = clock, own = 0 }
ns.AchDex()
ok("The Complete Works: all 1337", Done().complete ~= nil and LogHas("ACH complete toast=1"))
ok("collection: tab head = the done rows (Perfect Pitch reset)", ns.AchTabText("collection") == "Collection 4/5",
	ns.AchTabText("collection"))
Toasts()
ns.DexPages = function() return { Pool(0, "Empty", true) } end
ns.AchDex()
ok("Perfect Pitch: an empty voice page is never full", Done().pitch == nil and not ns.DexNums().full, Done().pitch)
ns.DexPages = realP
for k in pairs(SpokenWindDB.dex) do if k:match("^k%d+$") then SpokenWindDB.dex[k] = nil end end
ok("collection: back to the live pool", ns.AchLines("collection").all == 14 and ns.DexCount() == 10, ns.DexCount())

-- a save with 10 sounds and no row yet (0.6.2): the next played fart earns it
for _, id in ipairs({ "starter", "collector", "gasologist", "pitch", "complete" }) do Done()[id] = nil end
Boot(SpokenWindDB)
ok("old save: nothing at boot, no toast", Done().starter == nil and ns.ToastFrame() == nil and ns.DexCount() == 10)
now = now + 5
Emote(FartBy("Bob"), "Bob", "Player-1-0000B0B0")
now = now + 0.3 Run()
ok("old save: the next played fart earns Starter Pack", Done().starter ~= nil and Done().collector == nil, LastLog())
Toasts()
Boot(SpokenWindDB)
ok("collection: earned rows kept over a reload", Done().starter ~= nil and ns.AchTabText("collection") == "Collection 1/5")
local realA = ns.AchDex
ns.AchDex = function() error("ach dex boom") end
local np = #plays
now = now + 5
Emote(FartBy("Cid"), "Cid", "Player-1-0000C1D0")
now = now + 0.3 Run()
ok("collection: an error never breaks the sound", #plays == np + 1 and LogHas("ERR dex"))
ns.AchDex = realA
SY.noPacks = nil
end)()

;(function()   -- the live 0.6.1 gets 0.6.2 messages + a 0.6.2 save (tests/compat/0.6.1 = the 0.6.1 stage bytes)
local keep = ADDON_DIR
ADDON_DIR = ROOT .. "/tests/compat/0.6.1"
local RG, QG = "Player-1-0000CCCC", "Player-1-0000BBBB"
local function Msg(text, name) ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", text, "PARTY", name) end
local function F(snd, n, a) return ("F:1:FART:%s:%d:0:%d%s"):format(RG, snd, n, a or "") end
local function Run()
	local i = 1
	while i <= #SY.timers do
		local t = SY.timers[i]
		if t.at <= now + 1e-9 then table.remove(SY.timers, i) t.fn() else i = i + 1 end
	end
end
local function SyncN(s)
	local k = 0
	for _, l in ipairs(SpokenWindDB.sync or {}) do if l:find(s, 1, true) then k = k + 1 end end
	return k
end
local function NoErr()
	for _, t in ipairs({ SpokenWindDB.log or {}, SpokenWindDB.sync or {} }) do
		for _, l in ipairs(t) do if l:find("ERR", 1, true) then return false, l end end
	end
	return true
end
local function Boot(db)
	ev, ns = Load(db, "vertical")
	IsInGroup = function() return true end
	IsInGuild = function() return true end
	SpokenWindDB.cd = 0
	willPlay = true
end
local okAll, err = pcall(function()
	Boot(nil)
	ok("0.6.1 compat: the old build loads", LastLog():find("BOOT v=0.6.1 ", 1, true) ~= nil, LastLog())
	-- control: a plain F, then its emote = played from the message
	now = now + 5 Run()
	local np = #plays
	Msg(F(4, 1), "Rae")
	now = now + 0.04
	Emote(FartBy("Rae"), "Rae", RG)
	ok("0.6.1 compat: a plain F plays from the message", #plays == np + 1 and SyncN("SYNC by=msg") == 1, SyncN("SYNC by=msg"))
	-- the author flag: the old pattern ends at the count, so the F is dropped; the emote still plays (seed)
	now = now + 5 Run()
	np = #plays
	Msg(F(5, 2, ":a"), "Rae")
	now = now + 0.04
	Emote(FartBy("Rae"), "Rae", RG)
	now = now + 0.3 Run()
	ok("0.6.1 compat: an F with :a is dropped, the emote still plays (seed), no error", #plays == np + 1
		and SyncN("SYNC by=msg") == 1 and SyncN("SYNC by=seed") == 1 and NoErr(), select(2, NoErr()))
	-- H (new in 0.6.2): an unknown kind there, plain or with :a
	np = #plays
	local ns0 = #SY.asent
	Msg(("H:1:%s:1:%s"):format(ME_GUID, QG), "Quin")
	Msg(("H:1:%s:1:%s:a"):format(ME_GUID, QG), "Quin")
	ok("0.6.1 compat: H replies (plain, :a) are dropped: no sound, no send, no error", #plays == np and #SY.asent == ns0
		and NoErr(), select(2, NoErr()))
	-- undo: a 0.6.2 save under 0.6.1
	Boot({ on = true, rwbtn = true, rwbtnMove = true, achpos = { x = 5, y = 600 },
		dex = { ["04_trumpet"] = { n = 2, t = 1, own = 1 } },
		stats = { own = 3, heard = 2, people = { [QG] = true }, best = 1, legend = 1, legendHeard = 0 },
		ach = { done = { first = 1, heard = 2, source = 3 }, heard = {}, people = {}, sync = 4 } })
	ok("0.6.1 compat: a 0.6.2 save loads, no error, the classic row kept", LastLog():find("BOOT v=0.6.1 ", 1, true)
		and NoErr() and SpokenWindDB.ach.done.first == 1 and SpokenWindDB.rwbtn == true, LastLog())
	ok("0.6.1 compat: a 0.6.2 save keeps its stats + dex (0.6.1 does not read them)",
		SpokenWindDB.stats and SpokenWindDB.stats.heard == 2 and SpokenWindDB.dex and SpokenWindDB.dex["04_trumpet"].n == 2)
	ok("0.6.1 compat: undo drops the Social rows + the In Sync count (0.6.1 does not know them)",
		SpokenWindDB.ach.done.heard == nil and SpokenWindDB.ach.done.source == nil and SpokenWindDB.ach.sync == nil,
		tostring(SpokenWindDB.ach.sync))
end)
ADDON_DIR = keep
ok("0.6.1 compat: ran without a Lua error", okAll, err)
end)()
;(function()   -- undo: the live 0.6.2 loads a 0.6.3 save (tests/compat/0.6.2 = the live 0.6.2 bytes)
local keep = ADDON_DIR
ADDON_DIR = ROOT .. "/tests/compat/0.6.2"
local function NoErr()
	for _, t in ipairs({ SpokenWindDB.log or {}, SpokenWindDB.sync or {} }) do
		for _, l in ipairs(t) do if l:find("ERR", 1, true) then return false, l end end
	end
	return true
end
local okAll, err = pcall(function()
	local dex = {}
	for i, f in ipairs({ "01_squeak", "02_rumble", "03_wet", "04_trumpet", "05_slowsqueak", "06_triple", "07_brrt",
		"08_quack", "09_balloon", "10_sputter" }) do
		dex[f] = { n = i, t = 1, own = i % 2 }
	end
	ev, ns = Load({ on = true, rwbtn = true, rwbtnMove = true, achpos = { x = 5, y = 600 }, dex = dex,
		stats = { own = 3, heard = 2, people = {}, best = 1, legend = 0, legendHeard = 0 },
		ach = { done = { first = 1, heard = 2, starter = 3, collector = 4 }, heard = {}, people = {}, sync = 1 } }, "vertical")
	local d = SpokenWindDB.ach.done
	ok("0.6.2 compat: a 0.6.3 save loads, no error", LastLog():find("BOOT v=0.6.2 ", 1, true) ~= nil and NoErr()
		and LastLog():find(" dex=10 ", 1, true) ~= nil, LastLog())
	ok("0.6.2 compat: classic + social rows, stats + dex kept", d.first == 1 and d.heard == 2 and SpokenWindDB.ach.sync == 1
		and SpokenWindDB.stats.heard == 2 and SpokenWindDB.dex["04_trumpet"].n == 4)
	ok("0.6.2 compat: undo drops the Collection rows (0.6.2 does not know them)", d.starter == nil and d.collector == nil)
	ok("0.6.2 compat: the window opens; a collection tab name = the classic tab", ns.AchOpen("collection") == true
		and LastLog():find("ACH open tab=classic ", 1, true) ~= nil and NoErr(), LastLog())
end)
ADDON_DIR = keep
ok("0.6.2 compat: ran without a Lua error", okAll, err)
end)()
;(function()   -- test mode (0.6.1): own function (the main chunk is near 200 locals); 2 real clients on a fake bus
local STEP0 = math.floor(CLOCK0 / 10) * 10
local R0 = STEP0 - 1000 + 0.37   -- real server time = R0 + now (now = 1000 after a load)
local FRAME, REALM = 1 / 60, "Nowhere"
local P = { clients = {}, q = {}, log = {}, lat = 0.05, elat = 0.08 }
local CUR
local function Be(c) CUR = c ME, ME_GUID = c.name, c.guid end
local function TClient(name, guid, fac)
	ME, ME_GUID = name, guid
	local e, n = Load(nil)
	local c = { name = name, guid = guid, fac = fac, ev = e, ns = n, db = SpokenWindDB, hooks = SY.hooks,
		slash = SlashCmdList.SPOKENWIND, up = 0, skew = 0 }
	c.db.cd = 0
	SY.Tiny(n)
	P.clients[#P.clients + 1] = c
	return c
end
local function Unit(c, u)   -- unit -> client
	if u == "player" then return c end
	if u == "target" then return c.target end
	if u == "party1" then return c.party end
	return nil
end
local function Reaches(from, to, ch, tgt)
	if from.fac ~= to.fac then return false end   -- no addon message crosses factions
	if ch == "WHISPER" then return type(tgt) == "string" and (tgt:match("^[^%s%-]+") or ""):lower() == to.name:lower() end
	if ch == "PARTY" or ch == "RAID" then return from.party == to end
	return false
end
local function BusSend(p, m, ch, tgt)
	local from = CUR
	m = tostring(m)
	P.log[#P.log + 1] = { from = from, m = m, ch = ch, tgt = tgt, hw = hw, t = now }
	if #tostring(p) + #m > 254 then forbidden[#forbidden + 1] = "addon message too long" end
	if m:sub(1, 4) == "T:1:" then   -- test messages: by WHISPER to the partner, or by PARTY when the partner is in it
		local T = from.ns.TestState()
		local okW = ch == "WHISPER" and T and T.on and tgt == T.partner
		local okG = ch == "PARTY" and tgt == nil and T and T.on and from.party ~= nil and from.ns.TestSameName(from.party.name, T.partner)
		if not (okW or okG) then forbidden[#forbidden + 1] = "T message not to the partner " .. m end
	elseif m:sub(1, 4) == "H:1:" then   -- a Heard reply: any time; by WHISPER only to the test partner
		local T = from.ns.TestState()
		if ch == "WHISPER" and not (T and T.on and tgt == T.partner) then forbidden[#forbidden + 1] = "H message whispered " .. m end
	elseif not hw and not (P.inTimer and P.inTimer.hwMade) then   -- a fart message: only from a key press
		forbidden[#forbidden + 1] = "F message outside a key press"
	end
	for _, to in ipairs(P.clients) do
		if to ~= from and Reaches(from, to, ch, tgt) then
			P.q[#P.q + 1] = { at = now + P.lat, to = to, p = p, m = m, ch = ch,
				sender = from.name .. (from.sur and (" " .. from.sur) or "") .. "-" .. REALM }
		end
	end
end
local function Install()   -- after every Load: the bus + per-client clocks and units
	GetTime = function() return now + (CUR and CUR.up or 0) end
	GetServerTime = function()   -- P.freeze: a server second that never ticks
		if P.freeze then return P.freeze end
		return math.floor(R0 + now + (CUR and CUR.skew or 0))
	end
	time = function() return math.floor(R0 + now) end
	UnitGUID = function(u) local x = CUR and Unit(CUR, u) return x and x.guid or nil end
	UnitName = function(u) local x = CUR and Unit(CUR, u) if x then return x.name, x.sur end return nil end
	UnitFactionGroup = function(u) local x = CUR and Unit(CUR, u) return x and x.fac or nil end
	UnitIsPlayer = function(u) return CUR ~= nil and Unit(CUR, u) ~= nil end
	UnitIsUnit = function(a, b) return CUR ~= nil and Unit(CUR, a) ~= nil and Unit(CUR, a) == Unit(CUR, b) end
	GetNumGroupMembers = function() return CUR and CUR.party and 2 or 0 end
	IsInGroup = function() return CUR ~= nil and CUR.party ~= nil end
	IsInRaid = function() return false end
	C_Timer = { After = function(s, fn) SY.timers[#SY.timers + 1] = { at = now + s, fn = fn, owner = CUR, hwMade = hw } end }
	C_ChatInfo.SendAddonMessage = BusSend
end
local function Due(list)   -- the earliest due item (time order), removed
	local bi
	for i, x in ipairs(list) do
		if x.at <= now + 1e-9 and (not bi or x.at < list[bi].at) then bi = i end
	end
	return bi and table.remove(list, bi) or nil
end
-- Frames of 1/60 s: each shown window's OnUpdate, then messages, emotes and timers in time order.
local function Tick(sec)
	local stop = now + sec - 1e-9
	while now < stop do
		now = now + FRAME
		for _, c in ipairs(P.clients) do
			local w = c.ns.TestFrame()
			if w and w.shown and w.scripts.OnUpdate then Be(c) w.scripts.OnUpdate(w, FRAME) end
		end
		while true do
			local m, t = Due(P.q), nil
			if m then table.insert(P.q, 1, m) end
			t = Due(SY.timers)
			if t then table.insert(SY.timers, 1, t) end
			if not m and not t then break end
			if m and (not t or m.at <= t.at) then
				table.remove(P.q, 1)
				Be(m.to)
				if m.emote then
					m.to.ev.scripts.OnEvent(m.to.ev, "CHAT_MSG_TEXT_EMOTE", m.emote, m.sender, "", "", "", "", 0, 0, "", 0, 123, m.guid)
				else
					m.to.ev.scripts.OnEvent(m.to.ev, "CHAT_MSG_ADDON", m.p, m.m, m.ch, m.sender)
				end
			else
				table.remove(SY.timers, 1)
				if t.owner then Be(t.owner) end
				P.inTimer = t
				t.fn()
				P.inTimer = nil
			end
		end
	end
end
-- A key press: the game's emote call (our post-hook), the own echo, the line in range of the others.
local function Fart(c)
	Be(c)
	hw = true
	c.hooks.DoEmote("FART")
	hw = false
	c.ev.scripts.OnEvent(c.ev, "CHAT_MSG_TEXT_EMOTE", OWN_FART, c.name, "", "", "", "", 0, 0, "", 0, 123, c.guid)
	for _, o in ipairs(P.clients) do
		if o ~= c and not o.away then P.q[#P.q + 1] = { at = now + P.elat, to = o, emote = FartBy(c.name), sender = c.name, guid = c.guid } end
	end
end
local function Stranger(guid)   -- a player without the addon: no key press here, only the line
	for _, o in ipairs(P.clients) do
		if not o.away then P.q[#P.q + 1] = { at = now + P.elat, to = o, emote = FartBy("Zed"), sender = "Zed", guid = guid } end
	end
end
local function Cmd(c, s) Be(c) hw = true c.slash(s) hw = false end
local function Click(c, b) Be(c) hw = true b.scripts.OnMouseUp(b, "LeftButton") hw = false end
local function St(c) return c.ns.TestState() end
local function Win(c) return c.ns.TestFrame() end
local function Text(c)
	local w, o = Win(c), {}
	for _, fs in ipairs(w and w.lines or {}) do if fs.shown then o[#o + 1] = fs.text end end
	return table.concat(o, "|")
end
local function TN(c, s)   -- test lines with s
	local k = 0
	for _, l in ipairs(St(c).lines) do if l:find(s, 1, true) then k = k + 1 end end
	return k
end
local function Sent(c, pre, ch)   -- addon messages c sent (prefix of the text, channel)
	local o = {}
	for _, x in ipairs(P.log) do
		if x.from == c and x.m:sub(1, #pre) == pre and (not ch or x.ch == ch) then o[#o + 1] = x end
	end
	return o
end
local function Recs(c, g, by, st)
	local k = 0
	for _, r in ipairs(St(c).recs) do
		if (not g or r.g == g) and (not by or r.by == by) and (not st or r.st == st) then k = k + 1 end
	end
	return k
end
local function Safe()   -- the flow test wants no step-edge miss: fart away from a step edge (skew 0.3 s)
	while (R0 + now) % 10 > 8.5 or (R0 + now) % 10 < 0.5 do Tick(0.1) end
end
local function Steps(c, n) for _ = 1, n do Safe() Fart(c) Tick(1.2) end end

local A = TClient("Ann", "Player-1-0000A001", "Alliance")
local B = TClient("Bo", "Player-1-0000B002", "Alliance")
B.up, B.skew = 5000, 0.3   -- B: other uptime, its server second ticks 300 ms early
local GA, GB, GZ = "0000A001", "0000B002", "0000C0DE"
Install()
ok("test: BOOT tm=1", A.db.log[#A.db.log]:find(" tm=1 on=1 ", 1, true), A.db.log[#A.db.log])
ok("test: off by default", St(A).on == false and St(B).on == false and Win(A) == nil and Win(B) == nil)
Tick(0.5)
-- ---- pair: A names B; B (off) ignores it; B pairs by its target
Cmd(A, "pair Bo")
local TA = St(A)
ok("test: start: on, wait", TA.on and TA.partner == "Bo" and not TA.paired and TA.stage == 1 and TA.n == 1)
hw = true
ok("thanks: nothing before the pair", A.ns.TestThanks() == false and #Sent(A, "T:1:TY") == 0)
hw = false
local wa = Win(A)
ok("test: window at the top, 300 wide", wa.shown and wa.point[1] == "TOP" and wa.point[3] == "TOP" and wa.point[5] == -150
	and wa.w == 300 and wa.strata == "DIALOG")
ok("test: window: wait + how to pair (no own name)", Text(A) == "Wind test · Bo · wait|seed ? · clock ?|partner: target me + /wind pair",
	Text(A))
ok("test: HI by whisper", #Sent(A, "T:1:HI:Player-1-0000A001:0.8.4:Alliance:", "WHISPER") == 1)
Tick(1.5)
ok("test: clock tick found", TN(A, "CLOCK tick ok") == 1 and not St(B).on and #St(B).lines == 0)
B.target = A
Cmd(B, "pair")
B.target = nil
local TB = St(B)
ok("test: pair by target", TB.on and TB.partner == "Ann")
Tick(4)
ok("test: paired both ways", TA.paired and TB.paired and TA.partner == "Bo-Nowhere" and TB.partner == "Ann-Nowhere"
	and TA.side == 1 and TB.side == 2 and TA.id == TB.id, tostring(TA.side) .. tostring(TB.side))
ok("test: paired: no HI again (A at 0 s, B at 1.5 s, now 5.5 s)", #Sent(A, "T:1:HI:") == 1 and #Sent(B, "T:1:HI:") == 1,
	#Sent(A, "T:1:HI:") .. "/" .. #Sent(B, "T:1:HI:"))
ok("test: seed match", TA.seed == "match" and TB.seed == "match"
	and TN(A, "PAIR ok side=1 seed=match ver=0.8.4 pver=0.8.4 pg=" .. GB) == 1 and TN(B, "PAIR ok side=2 seed=match") == 1)
local _, SA = St(A)
ok("test: clock: no tick on B yet = retry", SA.retry == 1, SA.retry)
ok("test: clock: 3 pings each", TN(A, "CLOCK ping=") == 3 and TN(B, "CLOCK ping=") == 3, TN(A, "CLOCK ping="))
ok("test: clock: offset = the 300 ms skew", TA.clock and TB.clock and math.abs(TA.clock.off - 300) <= 40
	and math.abs(TB.clock.off + 300) <= 40, TA.clock and (TA.clock.off .. "/" .. TB.clock.off))
ok("test: clock: rtt = 2 x 50 ms", math.abs(TA.clock.rtt - 100) <= 40 and math.abs(TB.clock.rtt - 100) <= 40, TA.clock.rtt)
ok("test: window: seed + clock + step", Text(A):find("^Wind test · Bo|seed match · clock %+%d+ms · rtt %d+ms · edge~3%.%d%%|Step 1 · you /fart 0/5$")
	and Text(B):find("|seed match · clock %-%d+ms · rtt %d+ms · edge~3%.%d%%|Step 1 · Ann /fart 0/5$"), Text(A) .. " // " .. Text(B))
ok("test: buttons: Skip Send End", wa.skip.shown and wa.send.shown and wa.stop.shown and wa.skip.point[5] == wa.stop.point[5]
	and wa.h == 10 + 3 * 14 + 6 + 20 + 10, wa.h)
-- ---- guided steps
local nF = #Sent(A, "F:1:")
Steps(A, 5)
ok("test: step 1: 5 own farts move both to step 2", TA.stage == 2 and TB.stage == 2 and TA.cnt == 0
	and Text(A):find("Step 2 · you /fart 0/5 · nomsg", 1, true) and Text(B):find("Step 2 · Ann /fart 0/5 · nomsg", 1, true), Text(B))
ok("test: step 1: 1 F per fart, whisper to the partner (no group)", #Sent(A, "F:1:") - nF == 5
	and #Sent(A, "F:1:", "WHISPER") == 5 and Sent(A, "F:1:")[5].tgt == "Bo-Nowhere")
ok("test: step 1: B played A's pick 5x, all in step 1", Recs(B, GA, "msg", 1) == 5 and Recs(A, GA, "own", 1) == 5)
Be(A)
local am, ad = A.ns.TestOwnMode()
Be(B)
ok("test: own mode: only the farter of the step", am == "nomsg" and ad == nil and B.ns.TestOwnMode() == nil)
nF = #Sent(A, "F:1:")
Steps(A, 5)
ok("test: step 2 nomsg: no F at all", #Sent(A, "F:1:") == nF and Recs(A, GA, "own", 2) == 5 and TA.stage == 3)
ok("test: step 2: B waits, then the seed", Recs(B, GA, "seed") == 5 and B.db.sync[#B.db.sync]:find("by=seed why=timeout", 1, true))
local own2 = TA.recs[#TA.recs]
ok("test: step 2: own record: mode nomsg, sent 0", own2.mode == "nomsg" and own2.sent == 0 and own2.by == "own")
ok("test: step 3a: B's turn", Text(B):find("Step 3a · you /fart 0/5", 1, true) and Text(A):find("Step 3a · Bo /fart", 1, true), Text(A))
Steps(B, 5)
Steps(B, 5)
ok("test: step 3: B 5 + 5 nomsg", Recs(B, GB, "own", 3) == 5 and Recs(B, GB, "own", 4) == 5 and #Sent(B, "F:1:") == 5
	and Recs(A, GB, "msg") == 5 and Recs(A, GB, "seed") == 5 and TA.stage == 5)
ok("test: B's farts move A on", Text(A):find("Step 4a · you /fart 0/3 · +100ms", 1, true), Text(A))
Be(A)
am, ad = A.ns.TestOwnMode()
ok("test: own mode 4a: 100 ms late", am == "+100ms" and ad == 0.1)
nF = #Sent(A, "F:1:")
Steps(A, 3)
local late = Sent(A, "F:1:")
ok("test: step 4a: F 100 ms after the key press (its own timer)", #late - nF == 3 and late[#late].hw == false)
local gaps = 0
for _, r in ipairs(TB.recs) do if r.g == GA and r.st == 5 and r.by == "msg" and r.gap > 40 and r.gap < 110 then gaps = gaps + 1 end end
ok("test: step 4a: B waited and got it", gaps == 3, gaps)
ok("test: step 4a: own record: sent after the timer", TA.recs[#TA.recs].sent == 1 and TA.recs[#TA.recs].mode == "+100ms")
Steps(A, 3)
ok("test: step 4b: B used the seed, the message came late", Recs(B, GA, "seed", 6) == 3
	and TN(B, "TEST late g=" .. GA) == 3 and TN(B, "match=1") == 3, TN(B, "TEST late"))
ok("test: step 5: stranger", Text(A):find("Step 5 · stranger /fart 0/3", 1, true) and TB.stage == 7, Text(A))
for _ = 1, 3 do Safe() Stranger("Player-1-" .. GZ) Tick(1.2) end
ok("test: step 5: both log the stranger, then done", Recs(A, GZ, "seed") == 3 and Recs(B, GZ, "seed") == 3
	and TA.stage == 8 and TB.stage == 8 and Text(A):find("|Done · Send$"), Text(A))
ok("test: done: no Skip", not wa.skip.shown and wa.send.shown and wa.stop.shown)
ok("test: log line per fart", TN(A, "TEST id=") == 29 and TN(B, "TEST id=") == 29, TN(A, "TEST id="))
ok("test: never an emote, never a chat line", #sent == 0)
-- ---- bad T messages: not from the partner, not by whisper
local st0, nSync = TA.stage, #A.db.sync
Be(A)
A.ev.scripts.OnEvent(A.ev, "CHAT_MSG_ADDON", "SpWind", "T:1:BY", "PARTY", "Bo-Nowhere")
A.ev.scripts.OnEvent(A.ev, "CHAT_MSG_ADDON", "SpWind", "T:1:BY", "WHISPER", "Eve-Nowhere")
A.ev.scripts.OnEvent(A.ev, "CHAT_MSG_ADDON", "SpWind", "T:1:ST:2", "GUILD", "Bo")
A.ev.scripts.OnEvent(A.ev, "CHAT_MSG_ADDON", "SpWind", "T:1:RS:1:0:0:", "WHISPER", "Bo")
A.ev.scripts.OnEvent(A.ev, "CHAT_MSG_ADDON", "SpWind", "T:1:RS:1:5:3:1,x", "WHISPER", "Bo")
ok("test: T only from the partner by whisper", TA.on and TA.stage == st0 and TA.result == nil and #A.db.sync == nSync)
-- ---- results
local hBefore = wa.h
Click(A, wa.send)
ok("test: Send: sending", Text(A):find("Done · Send · sending %d") ~= nil, Text(A))
Tick(20)
local rsA, rsB = Sent(A, "T:1:RS:1:"), Sent(B, "T:1:RS:1:")
local paced = #rsA >= 3 and #rsB >= 3
for i = 2, #rsA do if rsA[i].t - rsA[i - 1].t < 1 - 1e-6 then paced = false end end
for i = 2, #rsB do if rsB[i].t - rsB[i - 1].t < 1 - 1e-6 then paced = false end end
ok("test: results: chunks, 1 per s, both ways", paced, #rsA .. "/" .. #rsB)
ok("test: results: whisper to the partner only", #Sent(A, "T:1:RS:", "WHISPER") == #rsA and rsA[1].tgt == "Bo-Nowhere"
	and rsB[1].tgt == "Ann-Nowhere")
local RA, RB = TA.result, TB.result
ok("test: results: 29/29 on both", RA and RB and RA.n == 29 and RA.m == 29 and RA.one == 0 and RB.n == 29 and RB.m == 29
	and RB.one == 0 and #RA.misses == 0, RA and (RA.n .. "/" .. RA.m .. " one=" .. RA.one))
ok("test: results: same gap both", RA.gap == RB.gap and RA.gap > 40 and RA.gap < 110, RA.gap)
local same = #RA.lines == #RB.lines and #RA.lines == 8
for i = 1, #RA.lines do
	if RA.lines[i]:gsub("^%S+ [^·]*", "") ~= RB.lines[i]:gsub("^%S+ [^·]*", "") then same = false end
end
ok("test: results: one table on both", same, table.concat(RA.lines, "|") .. " // " .. table.concat(RB.lines, "|"))
ok("test: results: rows", table.concat(RA.lines, "|"):find("^1 you · 5/5|2 you nomsg · 5/5|3a Bo · 5/5|3b Bo nomsg · 5/5|"
	.. "4a you %+100ms · 3/3|4b you %+400ms · 3/3|5 stranger · 3/3|all 29/29 · 1 side 0 · gap %+%d+ms$"), table.concat(RA.lines, "|"))
ok("test: results: in the window, grows down", Text(A):find("|all 29/29 · 1 side 0 · gap", 1, true) and wa.h > hBefore
	and wa.h == 10 + 11 * 14 + 6 + 20 + 10 and wa.w == 300 and wa.point[5] == -150, wa.h)
ok("test: results: saved", A.db.test == TA and A.db.test.result.seed == "match" and A.db.test.result.clock == TA.clock
	and TN(A, "RESULT all 29/29") == 1 and TN(B, "GOT round=1") == 1 and TN(A, "GOT round=1") == 1)
-- ---- the author's thanks (0.6.2, dev addon only): one TY whisper to the partner = Lab Partner there
;(function()
	Be(A)
	local nTY = #Sent(A, "T:1:TY")
	hw = true
	local okTY = A.ns.TestThanks()
	hw = false
	Tick(0.5)
	local ty = Sent(A, "T:1:TY")
	ok("thanks: one TY whisper to the partner only", okTY == true and #ty == nTY + 1 and ty[#ty].ch == "WHISPER"
		and ty[#ty].tgt == "Bo-Nowhere" and ty[#ty].m == "T:1:TY", #ty)
	ok("thanks: Lab Partner on the partner, not on the sender", B.db.ach.done.labpartner ~= nil and TN(B, "TY got") == 1
		and A.db.ach.done.labpartner == nil, TN(B, "TY got"))
end)()
-- ---- unit: the reason of a miss
local C = A.ns.TestCompare
local function R(st, g, ts, step, k, snd, by, x)
	local r = { st = st, g = g, ts = ts, step = step, k = k, snd = snd, by = by }
	for key, v in pairs(x or {}) do r[key] = v end
	return r
end
local res = C({ R(1, "g", 100, 10, 0, 3, "own", { sent = 1 }) }, { R(1, "g", 100, 10, 0, 3, "msg", { gap = -30 }) })
ok("compare: same sound", res.n == 1 and res.m == 1 and res.one == 0 and res.gap == -30 and res.rows[1].n == 1)
res = C({ R(2, "g", 100, 10, 0, 3, "own", { sent = 0 }) }, { R(2, "g", 101, 11, 0, 5, "seed") })
ok("compare: other step = edge", res.n == 0 and res.m == 1 and res.rows[2].why.edge == 1
	and res.misses[1] == "st=2 g=g snd=3/5 step=10/11 k=0/0 by=own/seed why=edge", res.misses[1])
res = C({ R(2, "g", 100, 10, 0, 3, "own", { sent = 0 }) }, { R(2, "g", 100, 10, 1, 5, "seed") })
ok("compare: other k = kdrift", res.rows[2].why.kdrift == 1)
res = C({ R(6, "g", 100, 10, 0, 3, "own", { sent = 1 }) }, { R(6, "g", 100, 10, 0, 5, "seed", { late = 3 }) })
ok("compare: message after the seed = late", res.rows[6].why.late == 1)
res = C({ R(1, "g", 100, 10, 0, 3, "own", { sent = 1 }) }, { R(1, "g", 100, 10, 0, 5, "seed") })
ok("compare: message sent, not got = lost", res.rows[1].why.lost == 1)
res = C({ R(1, "g", 100, 10, 0, 3, "seed") }, { R(1, "g", 100, 10, 0, 5, "msg") })
ok("compare: a 3rd client got it, this one not = lost", res.rows[1].why.lost == 1)
res = C({ R(2, "g", 100, 10, 0, 3, "own", { sent = 0 }) }, { R(2, "g", 100, 10, 0, 5, "seed") })
ok("compare: same inputs, other sound = hash", res.rows[2].why.hash == 1)
res = C({ R(1, "g", 100, 10, 0, 3, "own") }, {})
ok("compare: heard by one side", res.one == 1 and res.m == 0)
res = C({ R(1, "g", 100, 10, 0, 3, "own") }, { R(1, "g", 103, 10, 0, 3, "msg") })
ok("compare: 3 s apart = not the same fart", res.one == 2 and res.m == 0)
res = C({ R(1, "g", 100, 10, 0, 3, "own") }, { R(1, "g", 102, 10, 0, 3, "msg") })
ok("compare: 2 s apart = the same fart", res.one == 0 and res.m == 1)
res = C({ R(3, "g", 100, 10, 0, 3, "msg"), R(3, "g", 101, 10, 1, 4, "msg") }, { R(3, "g", 100, 10, 0, 3, "own"), R(4, "g", 101, 10, 1, 4, "own") })
ok("compare: in order, the farter's step", res.n == 2 and res.rows[3].m == 1 and res.rows[4].m == 1)
res = C({ R(5, "g", 100, 10, 0, 3, "seed"), R(5, "h", 100, 10, 0, 3, "seed") }, { R(5, "h", 100, 10, 0, 3, "seed") })
ok("compare: per farter", res.m == 1 and res.n == 1 and res.one == 1)
res = C({ R(1, "g", 100, 10, 0, 3, "msg", { gap = 20 }) }, { R(1, "g", 100, 10, 0, 3, "msg", { gap = 90 }) })
ok("compare: gap = the largest", res.gap == 90)
local big = {}
for i = 1, 60 do big[i] = R(1, "g", 100 + i * 3, 10, 0, 1, "own") end
local big2 = {}
for i = 1, 60 do big2[i] = R(1, "g", 100 + i * 3, 11, 0, 2, "seed") end
res = C(big, big2)
ok("compare: max 40 miss lines", res.m == 60 and #res.misses == 40)
local r0 = { st = 4, g = GA, ts = TA.id + 12, step = math.floor(TA.id / 10) + 1, k = 2, snd = 14, by = "msg", gap = -35, late = 7, skip = "cd" }
local packed = A.ns.TestPack(r0)
local u = A.ns.TestUnpack(packed)
ok("pack: round trip", u and u.st == 4 and u.g == GA and u.ts == r0.ts and u.step == r0.step and u.k == 2 and u.snd == 14
	and u.by == "msg" and u.gap == -35 and u.sent == nil and u.late == 7 and u.skip == true and #packed <= 32, packed)
u = A.ns.TestUnpack(A.ns.TestPack({ st = 1, g = GA, ts = TA.id, step = math.floor(TA.id / 10), k = 0, snd = 1, by = "own", sent = 2 }))
ok("pack: empty fields", u and u.gap == nil and u.sent == 2 and u.late == nil and u.skip == nil and u.by == "own")
ok("unpack: bad = nil", A.ns.TestUnpack("") == nil and A.ns.TestUnpack("1,2") == nil and A.ns.TestUnpack(packed .. ",9") == nil)
local SN = A.ns.TestSameName
ok("same name", SN("Bo", "bo-Nowhere") and SN("Bo-Nowhere", "Bo") and SN("Bo Bo", "BoBo") and not SN("Bo-A", "Bo-B")
	and not SN("Bo", "Bob") and not SN("", "Bo") and not SN(nil, "Bo"))
-- Forever (live 2026-11-23): the sender is "First Surname", the unit name "First-Surname"; own name has no surname
ok("same name: Forever surname forms", SN("Penny Picklebottom", "Penny-Picklebottom") and SN("Penny-Picklebottom", "Penny Picklebottom")
	and SN("Penny Picklebottom-Nowhere", "Penny-Picklebottom") and SN("Penny Picklebottom-Nowhere", "Penny Picklebottom")
	and SN("Tomo", "Tomo Brightpot") and SN("Tomo Brightpot", "tomo") and SN("Tomo-Nowhere", "Tomo")
	and SN("penny picklebottom", "PENNY-PICKLEBOTTOM"))
ok("same name: other players stay apart", not SN("Penny Picklebottom", "Penny Other") and not SN("Penny-Picklebottom", "Penny-Other")
	and not SN("Tomo-Nowhere", "Tomo Brightpot") and not SN("Pen", "Penny Picklebottom") and not SN("Penny Picklebottom", "Picklebottom")
	and not SN("-", "Bo") and not SN(" ", " ") and SN == A.ns.TestSameName and A.ns.SameName("Bo Bo", "bo-bo"))
issecretvalue = function(v) return v == "SECRET" end
ok("same name: a secret or a non-string name is no name", not SN("SECRET", "SECRET") and not SN("Bo", "SECRET")
	and not SN("SECRET", "Bo") and not SN(5, "5") and not SN("Bo", {}))
issecretvalue = nil
local seed1 = A.ns.TestSeedSum()
ok("seed sum: fixed number", seed1 == B.ns.TestSeedSum() and seed1 == 1919291286, seed1)
-- ---- End: the partner stops too
Click(A, wa.stop)
Tick(0.5)
ok("test: End: both off", not TA.on and TA.ended == "end" and not TB.on and TB.ended == "partner" and not wa.shown
	and #Sent(A, "T:1:BY") == 1 and Text(B):find("^Wind test · Ann · end"), Text(B))
local nT, nRecA = #P.log, #TA.recs
Steps(B, 1)
ok("test: off: no T message, no whisper, no record", #P.log == nT and #TA.recs == nRecA, #P.log - nT)
-- ---- in a group: pair by party1, F by PARTY only; Skip; step edge + k drift
P.nTW = #Sent(A, "T:1:", "WHISPER")
A.party, B.party = B, A
Cmd(A, "pair")
Cmd(B, "pair")
Tick(4)
TA, TB = St(A), St(B)
ok("test: group: pair by party1", TA.paired and TB.paired and TA.n == 2 and TA.prev and #TA.prev.recs == 29 and TA.prev.prev == nil)
Be(A)
ok("test: group: whisper only off-group", A.ns.TestWhisper() == nil)
ok("test: group: T messages by PARTY, none by WHISPER", #Sent(A, "T:1:", "WHISPER") == P.nTW and #Sent(A, "T:1:HI:", "PARTY") == 1
	and #Sent(A, "T:1:PI:", "PARTY") >= 1 and #Sent(B, "T:1:OK:", "PARTY") + #Sent(B, "T:1:HI:", "PARTY") >= 1, #Sent(A, "T:1:", "WHISPER") - P.nTW)
Be(B)
B.ns.TestMessage("T:1:BY", "GUILD", "Ann-Nowhere")
B.ns.TestMessage("T:1:BY", "PARTY", "Zed-Nowhere")
B.ns.TestMessage("T:1:BY", "SAY", "Ann-Nowhere")
ok("test: group: a T from the partner on GUILD or SAY, or from another on PARTY = ignored", TB.on and TB.paired)
nF = #Sent(A, "F:1:")
Steps(A, 1)
ok("test: group: own F by PARTY only", #Sent(A, "F:1:") - nF == 1 and Sent(A, "F:1:")[#Sent(A, "F:1:")].ch == "PARTY"
	and Recs(B, GA, "msg") == 1)
Click(A, Win(A).skip)
Tick(0.3)
ok("test: Skip: both on step 2", TA.stage == 2 and TB.stage == 2 and TA.cnt == 0)
local _, SB = St(B)
ok("test: Skip: flagged, B owes no farts", SB.owe == nil and #Sent(A, "T:1:ST:2:s") == 1 and TN(A, "STEP 2 s") == 1
	and TN(B, "STEP 2") == 1)
while (R0 + now) % 10 < 9.75 do Tick(FRAME) end   -- A farts 0.2 s before the edge; B (+0.3 s) hears it in the next step
Fart(A)
Tick(1.2)
while not ((R0 + now) % 10 >= 0.4 and (R0 + now) % 10 <= 1.5) do Tick(0.1) end   -- next step: A k=0, B k=1
Fart(A)
Tick(1.2)
local a1, a2, b1, b2 = TA.recs[#TA.recs - 1], TA.recs[#TA.recs], TB.recs[#TB.recs - 1], TB.recs[#TB.recs]
ok("test: edge: B one step on", b1.step == a1.step + 1 and a2.step == b2.step and a2.k == 0 and b2.k == 1,
	a1.step .. "/" .. b1.step .. " k " .. a2.k .. "/" .. b2.k)
Click(B, Win(B).send)
Tick(6)
local want = { "edge", "kdrift" }
local miss = {}
for i, pair in ipairs({ { a1, b1 }, { a2, b2 } }) do
	if pair[1].snd ~= pair[2].snd then miss[#miss + 1] = want[i] end
end
local RA2 = TA.result
local okMiss = RA2 and RA2.m == 3 and RA2.n == 3 - #miss and #RA2.misses == #miss
for i, w in ipairs(miss) do okMiss = okMiss and RA2.misses[i]:find("why=" .. w .. "$") ~= nil end
ok("test: edge + k drift misses named", okMiss and #miss >= 1, RA2 and table.concat(RA2.misses, " ; "))
out(("test mode sim: flow %d/%d, clock off %+d ms rtt %d ms (skew 300, 50 ms each way), edge test: %s"):format(
	TA.prev.result.n, TA.prev.result.m, TA.prev.result.clock.off, TA.prev.result.clock.rtt,
	RA2 and table.concat(RA2.misses, " ; ") or "-"))
ok("heard: pair: H by whisper to the partner, counted there", #Sent(B, "H:1:Player-1-0000A001:", "WHISPER") >= 1
	and #Sent(B, "H:1:", "WHISPER") + #Sent(B, "H:1:", "PARTY") == #Sent(B, "H:1:") and A.db.stats.heard >= 1 and A.db.stats.people["Player-1-0000B002"] == true
	and B.db.stats.heard >= 1, #Sent(B, "H:1:") .. "/" .. tostring(A.db.stats.heard))
ok("test: Send from side 2: same table", TB.result and TB.result.n == RA2.n and TB.result.m == RA2.m
	and table.concat(TB.result.misses, ";") == table.concat(RA2.misses, ";"))
-- ---- 200 records: chunks under 255 bytes, 1 per s, all arrive
for i = #TA.recs + 1, 200 do
	TA.recs[i] = { st = 7, g = GZ, ts = TA.id + i, step = math.floor((TA.id + i) / 10), k = i % 5, snd = i % 14 + 1, by = "seed", gap = 150 }
end
local nRS = #Sent(A, "T:1:RS:2:")
Click(A, Win(A).send)
Tick(60)
local rs2 = Sent(A, "T:1:RS:2:")
local long, gapOk = 0, true
for i, x in ipairs(rs2) do
	long = math.max(long, #x.m + 6)
	if i > 1 and x.t - rs2[i - 1].t < 1 - 1e-6 then gapOk = false end
end
ok("test: 200 records: paced chunks under 255 bytes", nRS == 0 and #rs2 >= 20 and gapOk and long <= 254, #rs2 .. " " .. long)
ok("test: 200 records: all arrive", TN(B, "GOT round=2 msgs=" .. #rs2 .. " recs=200") == 1 and TB.result.round == 2, #rs2)
B.db.on = false
Safe() Fart(A) Tick(1.2)
B.db.on = true
ok("test: a skipped fart is still logged", TN(B, "skip=off") == 1 and TB.recs[#TB.recs].skip == "off" and TB.recs[#TB.recs].g == GA)
local cA, cB, nLA = TA.cnt, TB.cnt, TN(A, "TEST id=")
Safe() Fart(B) Tick(1.2)
Safe() Stranger("Player-1-" .. GZ) Tick(1.2)
ok("test: step 2: B's fart and a stranger's are heard, not counted", TA.cnt == cA and TB.cnt == cB and cA > 0
	and TA.stage == 2 and TB.stage == 2 and #TA.recs == 200, TA.cnt .. "/" .. cA .. " " .. #TA.recs)
Cmd(A, "pair off")
Tick(0.3)
ok("test: pair off: both off", not TA.on and TA.ended == "off" and not TB.on and not Win(A).shown)
ok("test: group: BY by PARTY", #Sent(A, "T:1:BY", "PARTY") == 1 and #Sent(A, "T:1:", "WHISPER") == P.nTW)
A.party, B.party = nil, nil
-- ---- other faction: no message can cross
local X = TClient("Hor", "Player-1-0000D003", "Horde")
X.away = true
Install()
local nLog = #P.log
A.target = X
Cmd(A, "pair")
A.target = nil
TA = St(A)
ok("test: other faction target: stops at once", not TA.on and TA.xf and TN(A, "PAIR xfaction: no msgs") == 1
	and Text(A) == "Wind test · Hor · xfaction: no msgs" and #P.log == nLog and not Win(A).skip.shown, Text(A))
ok("test: xfaction start keeps the last real test", TA.prev and TA.prev.n == 2 and #TA.prev.recs == 200)
Cmd(A, "pair Hor")
TA = St(A)
Be(A)
A.ns.TestMessage(("T:1:HI:%s:0.6.1:Horde:1:14:%.0f"):format(X.guid, TA.id), "WHISPER", "Hor")
ok("test: other faction HI: stop", not TA.on and TA.xf and TN(A, "PAIR end why=xfaction") == 1)
-- ---- Forever names (live 2026-11-23): B is "Bo" + "Picklebottom"; A types "bo picklebottom" with B targeted
do
	B.sur = "Picklebottom"
	A.target = B
	local h0 = #Sent(A, "T:1:HI:")
	Cmd(A, "pair bo picklebottom")
	A.target = nil
	TA = St(A)
	ok("pair: a typed name = the unit's full name", TA.on and TA.partner == "Bo-Picklebottom" and Sent(A, "T:1:HI:")[h0 + 1].tgt == "Bo-Picklebottom",
		TA.partner)
	Tick(2.9)
	ok("pair: no answer: one HI before 3 s", #Sent(A, "T:1:HI:") == h0 + 1, #Sent(A, "T:1:HI:") - h0)
	Tick(0.2)
	ok("pair: no answer: HI again at 3 s", #Sent(A, "T:1:HI:") == h0 + 2, #Sent(A, "T:1:HI:") - h0)
	Tick(54)
	ok("pair: HI every 3 s to 57 s (20 in all), whisper to the partner", #Sent(A, "T:1:HI:") == h0 + 20 and TN(A, "PAIR nohello") == 0
		and Sent(A, "T:1:HI:")[h0 + 20].tgt == "Bo-Picklebottom" and Sent(A, "T:1:HI:")[h0 + 20].ch == "WHISPER", #Sent(A, "T:1:HI:") - h0)
	ok("pair: window waits", Text(A):find("^Wind test · Bo · wait|") ~= nil, Text(A))
	Tick(3)
	ok("pair: 60 s, no answer = PAIR nohello, shown, no more HI", TN(A, "PAIR nohello") == 1 and #Sent(A, "T:1:HI:") == h0 + 20
		and TA.on and not TA.paired and Text(A):find("^Wind test · Bo · no hello|") ~= nil, Text(A))
	Tick(9)
	ok("pair: no hello once, no HI after", TN(A, "PAIR nohello") == 1 and #Sent(A, "T:1:HI:") == h0 + 20)
	-- the partner starts late: its HI comes from "Bo Picklebottom-Nowhere" (Forever form): still pairs, the note goes
	B.target = A
	Cmd(B, "pair")
	B.target = nil
	Tick(1)
	ok("pair: a late partner 'First Surname-Realm' still pairs", TA.paired and St(B).paired and TA.partner == "Bo Picklebottom-Nowhere"
		and not Text(A):find("no hello", 1, true) and TA.nohello == nil, Text(A))
	Cmd(A, "pair off")
	Tick(0.3)
	ok("pair: off both", not TA.on and not St(B).on)
	B.sur = nil
end
-- ---- seed DIFF, no tick, bad pair command
Cmd(A, "pair Bo")
TA = St(A)
P.freeze = math.floor(R0 + now)
Install()
Be(A)
local id0 = TA.id
A.ns.TestMessage(("T:1:HI:%s:0.6.0:Alliance:12345:14:%.0f"):format(B.guid, id0 - 5), "WHISPER", "Bo")
Tick(3)
ok("test: seed DIFF, the lower test id", TA.paired and TA.seed == "DIFF" and TA.id == id0 - 5 and TA.side == 1, TA.seed)
ok("test: window: seed DIFF, old partner build", Text(A):find("seed DIFF · clock ?", 1, true) and TN(A, "pver=0.6.0") == 1, Text(A))
ok("test: no server tick: clock none", TN(A, "CLOCK tick none") == 1 and TN(A, "CLOCK ping=") == 0)
P.freeze = nil
Install()
local np = #prints
A.target, A.party = nil, nil
Cmd(A, "pair off")
Cmd(A, "pair")
ok("test: pair with no name: tells how", #prints == np + 1 and prints[#prints]:find("pair <name>", 1, true) and not St(A).on, prints[#prints])
-- ---- logout + load: off, the save kept
Cmd(A, "pair Bo")
Be(A)
A.ev.scripts.OnEvent(A.ev, "PLAYER_LOGOUT")
ok("test: off at logout", not St(A).on and St(A).ended == "logout")
local saved = A.db
ME, ME_GUID = A.name, A.guid
local _, n2 = Load(saved)
local T2 = n2.TestState()
ok("test: after a load: off, the last test kept", T2.on == false and T2.paired == false and n2.TestFrame() == nil
	and T2.prev and #T2.prev.recs == 200 and T2.prev.result and T2.prev.result.round == 2)
ok("test: no chat line in the whole test", #sent == 0)
local _, n3 = Load({ test = { on = true, paired = true, partner = "Bo", recs = {}, lines = {} } })
ok("test: a save from a crash (on) loads off", n3.TestState().on == false and n3.TestState().paired == false)
GetNumGroupMembers, UnitIsPlayer, UnitIsUnit = nil, nil, nil
end)()

;(function()   -- 0.6.4 board: per-character counters, F/H tails, ONE S after F, S receive (own function: near 200 locals)
local RG, QG, ALT = "Player-1-0000CCCC", "Player-1-0000BBBB", "Player-1-0000A1A1"
local ME0, MEG0 = ME, ME_GUID   -- the test mode block left its own client here
ME, ME_GUID = "Tester", "Player-1-0000AAAA"
local function Boot(db)
	ev, ns = Load(db)
	IsInGroup = function() return true end
	IsInGuild = function() return true end
	IsInRaid, IsInInstance = nil, nil
	SpokenWindDB.cd = 0
	SY.Tiny(ns)
	willPlay = true
	return ns
end
local function Run()
	local i = 1
	while i <= #SY.timers do
		local t = SY.timers[i]
		if t.at <= now + 1e-9 then table.remove(SY.timers, i) t.fn() else i = i + 1 end
	end
end
local function Msg(text, ch, name) ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", text, ch or "PARTY", name or "Rae-Nowhere") end
local function Press()   -- a key press + the own emote line: the messages it sent
	local na = #SY.asent
	hw = true SY.hooks.DoEmote("FART") hw = false
	Emote(OWN_FART, ME, ME_GUID)
	local out = {}
	for i = na + 1, #SY.asent do out[#out + 1] = SY.asent[i] end
	return out
end
local function Kinds(list)
	local t = {}
	for _, x in ipairs(list) do t[#t + 1] = x.m:sub(1, 1) .. "@" .. x.ch end
	return table.concat(t, ",")
end
local function SN(s)
	local k = 0
	for _, l in ipairs(SpokenWindDB.sync or {}) do if l:find(s, 1, true) then k = k + 1 end end
	return k
end
local function NoErr()
	for _, t in ipairs({ SpokenWindDB.log or {}, SpokenWindDB.sync or {} }) do
		for _, l in ipairs(t) do if l:find("ERR", 1, true) then return false, l end end
	end
	return true
end
local function C() return SpokenWindDB.chars[ME_GUID] end
local function Slash(s) SlashCmdList.SPOKENWIND(s) return prints[#prints] end

Boot({ stats = { own = 50, heard = 20, people = {}, best = 1, legend = 0, legendHeard = 0 },
	dex = { ["04_trumpet"] = { n = 3, t = 1, own = 1 } } })
ok("board: TIERS seed from the dex at login", LogHas("TIERS seed from=dex n=0"), LastLog())
ok("board: a new char starts at 0 (not the account totals)", C() and C().f == 0 and C().h == 0 and C().l == 0
	and C().n == ME and SpokenWindDB.stats.own == 50)
ok("board: BOOT char + all + board", LogHas(" char=0/0/0 all=0/0/1 tiers=0.0.0.0.0.0.0 alltiers=0.0.0.0.0.0.0 board=0 hide=0 seen=? win=0 rnd=1 tgt=0 aur=0 rev=12 dev=0"), LastLog())
-- own press: F then ONE S, same channels, in the key press
now = now + 5
local out = Press()
ok("board: own press = F + S on each channel", Kinds(out) == "F@PARTY,F@GUILD,S@PARTY,S@GUILD", Kinds(out))
ok("board: F carries this char's numbers", out[1] and out[1].m:find(":%d+::0%.0%.0$") ~= nil, out[1] and out[1].m)
ok("board: S = own entry first (counts before this press)", out[3] and out[3].m == "S:1:1-0000AAAA,Tester,0,0,0,00", out[3] and out[3].m)
ok("board: S in the key press", out[3] and out[3].hw == true and out[4].hw == true)
ok("board: SYNC send line", SN("SYNC send n=1 bytes=30 ch=2") == 1, SpokenWindDB.sync[#SpokenWindDB.sync])
ok("board: press counted, own fart not listened", C().f == 1 and C().l == 0, C().l)
now = now + 1.2
out = Press()
ok("board: S max 1 per 2 s (F as before)", Kinds(out) == "F@PARTY,F@GUILD", Kinds(out))
ok("board: F numbers go up", out[1] and out[1].m:find("::1%.0%.0$") ~= nil, out[1] and out[1].m)
now = now + 1
out = Press()
ok("board: after 2 s: S again", Kinds(out) == "F@PARTY,F@GUILD,S@PARTY,S@GUILD", Kinds(out))
combat = true
now = now + 5
out = Press()
ok("board: no S in combat (F as today)", Kinds(out) == "F@PARTY,F@GUILD", Kinds(out))
combat = false
local realM = ns.TestOwnMode
ns.TestOwnMode = function() return "nomsg" end
now = now + 5
ok("board: no F = no S", #Press() == 0)
ns.TestOwnMode = function() return "late", 0.4 end
now = now + 5
local na = #SY.asent
out = Press()
now = now + 0.4
hw = true Run() hw = false
local late = {}
for i = na + 1, #SY.asent do late[#late + 1] = SY.asent[i] end
ok("board: a late F (test delay) = no S", #out == 0 and Kinds(late) == "F@PARTY,F@GUILD", Kinds(late))
ns.TestOwnMode = realM
IsInGroup, IsInGuild = function() return false end, function() return false end
now = now + 5
local nSend = SN("SYNC send n=")
ok("board: solo = no F, no S", #Press() == 0 and SN("SYNC send n=") == nSend)
IsInGroup, IsInGuild = function() return true end, function() return true end
-- tiered sounds (none live yet): this char counts them, F carries them, Mine = dex n x tier
for _, s in ipairs(ns.EMOTES.FART.sounds) do s.tier = 5 end
local t0 = C().t[5]
now = now + 5
Press()
ok("board: a tiered own fart counts its tier", C().t[5] == t0 + 1, C().t[5])
now = now + 5
out = Press()
ok("board: F carries the tiers", out[1] and out[1].m:find(":0%.0%.0%.0%.1%.0%.0$") ~= nil, out[1] and out[1].m)
local dexN = 0
for _, e in pairs(SpokenWindDB.dex) do dexN = dexN + e.n end
local mine, mn = ns.TiersMine()
ok("board: Mine tiers = dex n x tier", mn == dexN and mine[5] == dexN and dexN > 0, mn .. "/" .. dexN)
for _, s in ipairs(ns.EMOTES.FART.sounds) do s.tier = nil end
C().t[5] = t0   -- later tests expect no tiers
-- receive S: merged only, never answered or relayed
now = now + 5
local nA, np = #SY.asent, #plays
local S1 = "S:1:1-0000CCCC,Fake,5,1,2,00;1-0000BBBB,Quin,3,0,1,00"
Msg(S1, "PARTY", "Rae-Nowhere")
local b = SpokenWindDB.board
ok("board: got S: first hand name = the sender", b[RG] and b[RG].n == "Rae" and b[RG].r == "Nowhere" and b[RG].fh == 1 and b[RG].f == 5)
ok("board: got S: second hand entry", b[QG] and b[QG].n == "Quin" and b[QG].fh == nil and b[QG].l == 1)
ok("board: got S: nothing sent, no sound", #SY.asent == nA and #plays == np)
ok("board: got S: SYNC recv line", SN("SYNC recv n=2 new=2 up=0 drop=0") == 1)
Msg(S1, "GUILD", "Rae-Nowhere")
ok("board: same S on GUILD = once", SN("SYNC recv") == 1)
Msg("S:1:1-0000DDDD,Dee,1,1,1,00", "WHISPER", "Dee-Nowhere")
Msg("S:1:1-0000DDDD,Dee,1,1,1,00", "CHANNEL", "Dee-Nowhere")
ok("board: S from outside the group/guild = ignored", b["Player-1-0000DDDD"] == nil and SN("SYNC recv") == 1)
Msg("S:1:1-0000AAAA,Tester,99,9,9,00", "PARTY", ME .. "-Nowhere")
ok("board: own S echo ignored", SN("SYNC recv") == 1 and C().f < 99 and b[ME_GUID] == nil)
Msg("S:1:garbage", "PARTY", "Zed-Nowhere")
ok("board: junk S = nothing, no error", SN("SYNC recv") == 1 and NoErr(), select(2, NoErr()))
Msg("S:1:1-0000EEEE,Eve,1,1,1,00;garbage", "PARTY", "Eve-Nowhere")
ok("board: a bad entry = drop count", SN("SYNC recv n=2 new=1 up=0 drop=1") == 1, SpokenWindDB.sync[#SpokenWindDB.sync])
-- F tail: first-hand numbers; the same F on 2 channels = listened +1
now = now + 5
local l0 = C().l
Msg(("F:1:FART:%s:3:0:7::7.2.3"):format(RG), "PARTY", "Rae-Nowhere")
Msg(("F:1:FART:%s:3:0:7::7.2.3"):format(RG), "GUILD", "Rae-Nowhere")
now = now + 0.04
np = #plays
Emote(FartBy("Rae"), "Rae", RG)
ok("board: F with numbers plays from the message", #plays == np + 1 and SN("SYNC by=msg") >= 1)
ok("board: F numbers merged (max)", b[RG].f == 7 and b[RG].h == 2 and b[RG].l == 3, b[RG].f)
ok("board: same F on 2 channels = listened +1", C().l == l0 + 1, C().l - l0)
ok("board: ALL upd line", SN("ALL upd g=00CCCC farts=7 heard=3") == 1)
now = now + 5
Msg(("F:1:FART:%s:4:0:8:a:7.2.3:1.0.0.0.0.0.2"):format(RG), "PARTY", "Rae-Nowhere")
ok("board: F with author flag + tiers", b[RG].t and b[RG].t[7] == 2 and b[RG].t[1] == 1)
now = now + 0.04
Emote(FartBy("Rae"), "Rae", RG)
now = now + 5
Msg(("F:1:FART:%s:4:0:9::"):format(RG), "PARTY", "Rae-Nowhere")
ok("board: F hidden (empty numbers) = no change", b[RG].f == 7)
now = now + 0.04
Emote(FartBy("Rae"), "Rae", RG)
-- H tail: the replier's numbers; own heard +1
now = now + 5
local h0 = C().h
out = Press()
local n = tonumber(out[1].m:match("^F:1:FART:[^:]+:%d+:%d+:(%d+)"))
Msg(("H:1:%s:%d:%s::4.5.6"):format(ME_GUID, n, QG), "PARTY", "Quin-Nowhere")
ok("board: H counts for this char", C().h == h0 + 1, C().h - h0)
ok("board: H numbers merged, first hand name", b[QG].f == 4 and b[QG].h == 5 and b[QG].l == 6 and b[QG].n == "Quin" and b[QG].fh == 1)
-- the H this char sends carries its numbers
now = now + 5
Msg(("F:1:FART:%s:3:0:20"):format(QG), "PARTY", "Quin-Nowhere")
now = now + 0.04
Emote(FartBy("Quin"), "Quin", QG)
local hm = SY.asent[#SY.asent].m
local pre = ("H:1:%s:20:%s::"):format(QG, ME_GUID)
ok("board: own H has the numbers", hm:sub(1, #pre) == pre and hm:sub(#pre + 1):find("^%w+%.%w+%.%w+$") ~= nil, hm)
-- /wind board off | on | status
local say = Slash("board")
ok("board: status line", say and say:find("board on · %d+ players · Seen %?$") ~= nil, say)
say = Slash("board off")
ok("board: off", say and say:find("board off · ") ~= nil and SpokenWindDB.boardOff == true and C().hide == 1 and C().hs == 1, say)
now = now + 5
out = Press()
ok("board: off: F without numbers (the 0.6.2 form)", out[1] and out[1].m:find("^F:1:FART:[^:]+:%d+:0:%d+$") ~= nil, out[1] and out[1].m)
ok("board: off: S own entry = zeros + flag", out[3] and out[3].m:find("^S:1:1%-0000AAAA,Tester,0,0,0,11") ~= nil, out[3] and out[3].m)
say = Slash("board on")
ok("board: on", say and say:find("^.-board on") ~= nil and SpokenWindDB.boardOff == false and C().hide == 0 and C().hs == 2, say)
ok("board: one line per command, no other print", #prints == 3, #prints)
ok("board: no ERR so far", NoErr(), select(2, NoErr()))
-- per character: an alt on the same account = its own counters, its own S
local saved = SpokenWindDB
local f1 = C().f
ME, ME_GUID = "Alty", ALT
Boot(saved)
ok("board: alt: own counters at 0", C() and C().f == 0 and SpokenWindDB.chars["Player-1-0000AAAA"].f == f1)
local boardF = 0
for _, e in pairs(SpokenWindDB.board) do if e.hide ~= 1 then boardF = boardF + e.f end end
local all = ns.B.All(SpokenWindDB)
ok("board: All = both chars + board (no account totals, no double)", all.f == f1 + boardF and all.f < SpokenWindDB.stats.own + boardF
	and LogHas((" all=%d/"):format(all.f)), all.f)
now = now + 5
out = Press()
ok("board: alt: S has only the alt", out[3] and out[3].m:find("^S:1:1%-0000A1A1,Alty,0,0,0,00") ~= nil
	and not out[3].m:find("0000AAAA", 1, true), out[3] and out[3].m)
ok("board: alt: F numbers = the alt's", out[1] and out[1].m:find("::0%.0%.0$") ~= nil, out[1] and out[1].m)
ME, ME_GUID = "Tester", "Player-1-0000AAAA"
Boot(saved)
ok("board: back on the main: counters kept", C().f == f1 and LogHas((" char=%d/"):format(f1)))
ok("board: no ERR in the whole run", NoErr(), select(2, NoErr()))
-- the Board tab (0.8.0 window): strip, tiers, two lists, your rows under them, tips, pin, logs, no new frames
local saved2 = SpokenWindDB
do
local function Cm(n)   -- "4,210"
	local s = tostring(math.floor(n or 0))
	local k
	repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end
local function Esc(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local function Ago(at)
	local d = math.floor((clock - at) / 86400)
	return d <= 0 and "Today" or ("%d d ago"):format(d)
end
local function FindMe(col) for _, l in ipairs(col.rows) do if l.me then return l end end return col.own end
local function Halves()   -- the shown halves of the two lists: { {A...}, {B...} }, each { h, rk, nm, n, line }
	local _, bb, _, lineOf = Id.W()
	local out = { {}, {} }
	for _, r in ipairs(bb._swRows or {}) do
		for k, X in ipairs({ "A", "B" }) do
			local h = r["h" .. X]
			if h.shown then
				out[k][#out[k] + 1] = { h = h, rk = r["rk" .. X], nm = r["nm" .. X], n = r["n" .. X], line = lineOf[h] }
			end
		end
	end
	return out
end
local function TipOf(f)   -- the mouse on f, then off: "title|label=value|..."
	Id.on(f)
	local sh, title, rows = Id.tip()
	Id.off(f)
	return sh and (title .. "|" .. rows) or ""
end
local function MeHalf(H, B)
	for _, c in ipairs(H[1]) do if c.line and c.line.me then return c.h end end
	return B.ownA
end
ok("board tab: opens", ns.AchOpen("board") == true)
local W, B = Id.W()
local L = ns.AchLines("board")
local A4 = ns.B.All(SpokenWindDB)
ok("board tab: Board tab selected", SY.State(W.tabBoard) == "sel" and W.tabBoardText.text == "Board"
	and SY.State(W.tabClassic) ~= "sel", W.tabBoardText.text)
ok("board tab: strip = all farts, listened, players (commas)", B.farts.text == Cm(A4.f) and B.listened.text == Cm(A4.l)
	and B.players.text == Cm(A4.p), B.farts.text .. " " .. B.listened.text .. " " .. B.players.text)
local nT = 0
for i = 1, 7 do if (A4.t[i] or 0) > 0 then nT = nT + 1 end end
ok("board tab: strip tiers = the tiers with a count (letter + count)", nT > 0
	and select(2, B.tiers.text:gsub("|c%x+[PCURELS]%d+|r", "")) == nT, B.tiers.text)
ok("board tab: logs", LogHas("BOARD show n=" .. A4.p .. " ") and LogHas("BOARD seen est="))
local H = Halves()
local okRows, why = true, ""
for k, col in ipairs(L.cols) do
	local src = k == 1 and L.board.heard or L.board.listen
	if #H[k] ~= #col.rows then okRows, why = false, "count " .. k .. " " .. #H[k] .. "/" .. #col.rows end
	for i, l in ipairs(col.rows) do
		local c = H[k][i]
		local nm = c and c.nm.text or ""
		if not (c and c.line and c.line.short == l.short and c.rk.text == tostring(l.rank) and c.n.text == Cm(l.num)
			and (nm == l.short or (l.own and not l.me and nm:find("^|c%x+" .. Esc(l.short) .. "|r$")))) then
			okRows, why = false, "row " .. k .. "/" .. i .. " " .. nm
		end
		if nm:find("Player-", 1, true) or (c and c.line and (c.line.name or ""):find("Player-", 1, true)) then
			okRows, why = false, "guid"
		end
	end
	for i = 2, #src do if src[i].v > src[i - 1].v then okRows, why = false, "order" end end
	for _, r in ipairs(src) do if not r.own and r.hide == 1 then okRows, why = false, "hidden shown" end end
end
ok("board tab: rows = the lists, best first, no hidden, no GUID", okRows and #L.cols[2].rows > 0, why)
local okOwn = true
for k, X in ipairs({ "A", "B" }) do
	local o, l = B["own" .. X], L.cols[k].own
	if l then
		okOwn = okOwn and o.shown and B["ownNm" .. X].text == l.short and B["ownRk" .. X].text == tostring(l.rank)
			and B["ownN" .. X].text == Cm(l.num)
	else
		okOwn = okOwn and not o.shown
	end
end
ok("board tab: your row under a list only when not in its top 10", okOwn
	and B.ownRow.shown == (L.cols[1].own ~= nil or L.cols[2].own ~= nil))
local m1 = FindMe(L.cols[1])
local meH = MeHalf(H, B)
local t1 = TipOf(meH)
ok("board tab: own character in Most heard (top or under it): sel, tip Char This", m1 and m1.short == "Tester"
	and (meH == B.ownA or SY.State(meH) == "sel")
	and t1:find("|Farts=[%d,]+|Heard=[%d,]+|Listened=[%d,]+|Char=This|Click=") ~= nil, t1)
local rae
for k = 1, 2 do for _, c in ipairs(H[k]) do if c.line and c.line.short == "Rae" and not rae then rae = c end end end
local e = SpokenWindDB.board[RG]
local tR = rae and TipOf(rae.h) or ""
ok("board tab: Rae listed, row tip = name-realm, numbers, seen, click pin", rae and SY.State(rae.h) == "base"
	and tR:find("^|c%x+Rae%-Nowhere|r|Farts=" .. Esc(Cm(e.f)) .. "|Heard=" .. Esc(Cm(e.h)) .. "|Listened=" .. Esc(Cm(e.l))
		.. "|Seen=" .. Esc(Ago(e.at)) .. "|Click=|c%x+Pin|r$") ~= nil, tR)
Id.on(rae.h)
SY.Click(rae.h)
Id.off(rae.h)
local sh, _, rows = Id.tip()
ok("board tab: a click pins the tip (it stays, Unpin)", sh and select(5, Id.W()) == rae.h and rows:find("|Click=|c%x+Unpin|r$") ~= nil,
	rows)
Id.on(rae.h)
SY.Click(rae.h)
Id.off(rae.h)
ok("board tab: a 2nd click unpins, leave hides it", select(5, Id.W()) == nil and not (Id.tip()))
local bl = L.board
local tA = TipOf(B.allL._swHit)
ok("board tab: All tip = players, oldest, seen, top 10 age", tA:find("^|c%x+All players|r|Players=" .. Esc(Cm(A4.p))
	.. (A4.oldest and ("|Oldest=" .. Esc(os.date("%m-%d", A4.oldest))) or "")
	.. "|Seen=|c%x+" .. Esc((bl.seen:gsub("^Seen ", ""))) .. "|r"
	.. (bl.age and ("|Top 10=" .. bl.age .. " d") or "") .. "$") ~= nil, tA)
local tT = TipOf(B.tiers._swHit)
ok("board tab: tier tip = Tiers All + 7 named tiers", tT:find("^|c%x+Tiers All|r|") ~= nil
	and select(2, tT:gsub("|c%x+%a+|r=[%d,]+", "")) == 7 and tT:find("Shartifact|r=" .. Cm(A4.t[7]), 1, true) ~= nil, tT)
Id.tab("Classic")
ok("board tab: Classic: the Board body hidden, tiles there", not B.root.shown and #Id.tiles() > 0)
Id.tab("Coll")
local _, BC = Id.W()
local tm, nm = ns.TiersMine(), 0
for i = 1, 7 do if (tm[i] or 0) > 0 then nm = nm + 1 end end
ok("board tab: Collection: Mine tiers there", not B.root.shown and select(2, BC.tiers.text:gsub("|c%x+[PCURELA]%d+|r", "")) == nm,
	BC.tiers.text)
Id.tab("Social")
Id.tab("Board")
local nF = #frames   -- every tab drawn once: from here on, no new frames
for _, k in ipairs({ "Classic", "Social", "Coll", "Board", "Coll", "Board" }) do Id.tab(k) end
ok("board tab: tab switches make no new frames", #frames == nF and B.root.shown and #Halves()[1] == #L.cols[1].rows, #frames - nF)
local pos = SpokenWindDB.achpos
W.head.scripts.OnDragStart(W.head)
W.head.scripts.OnDragStop(W.head)
SpokenWindDB.achpos = pos
ok("board tab: a drag (relayout) keeps the rows once", #Halves()[1] == #L.cols[1].rows, #Halves()[1])
Slash("board off")
L = ns.AchLines("board")
local m2 = FindMe(L.cols[1])
ok("board tab: off = own row grey + hint", m2 and m2.color == "|cff9d9d9d" and m2.gold == "Hidden · /wind board on", m2 and m2.gold)
ns.AchOpen("board")
local t2 = TipOf(MeHalf(Halves(), B))
ok("board tab: off: the tip says Hidden + how to show it", t2:find("|Char=This|Hidden=|c%x+/wind board on|r|Click=") ~= nil, t2)
Slash("board on")
Id.W().root:Hide()
-- empty state: a fresh save = your row under each list
ME, ME_GUID = "Newb", "Player-1-0000DDDD"
Boot({})
ns.AchOpen("board")
W, B = Id.W()
L = ns.AchLines("board")
H = Halves()
ok("board tab: empty: no list rows, your row under each list, rank 1, 0", L.cols[1].own and L.cols[1].own.short == "Newb"
	and #H[1] == 0 and #H[2] == 0 and B.ownRow.shown and B.ownA.shown and B.ownB.shown and B.ownNmA.text == "Newb"
	and B.ownRkA.text == "1" and B.ownNA.text == "0", #H[1] .. " " .. tostring(B.ownNmA.text))
local tE = TipOf(B.allL._swHit)
ok("board tab: empty: strip 0 / 0 / 1, Seen ? in the All tip", B.farts.text == "0" and B.listened.text == "0"
	and B.players.text == "1" and tE:find("|Seen=|c%x+%?|r$") ~= nil, tE)
ok("board tab: empty: no ERR", NoErr(), select(2, NoErr()))
-- big numbers get commas (the classic strip)
local realHN = ns.HeardNums
ns.HeardNums = function() return { own = 1234567, heard = 5, people = 4, best = 3, legend = 2, legendHeard = 7 } end
Id.tab("Classic")
local _, BCl = Id.W()
ok("ach window: big numbers get commas", BCl.farts.text == "1,234,567", BCl.farts.text)
Id.tab("Social")
local _, BSo = Id.W()
ok("ach window: social strip = each its own number", BSo.heard.text == "5" and BSo.people.text == "4" and BSo.best.text == "3"
	and BSo.born.text == "2" and BSo.wit.text == "7", BSo.born.text .. " " .. BSo.wit.text)
ns.HeardNums = realHN
-- an own alt with heard + a listener only: Top listener is the longer list (it sets the rows), the alt tip = Yours
SpokenWindDB.chars["Player-1-0000EEEE"] = { f = 3, h = 2, l = 1, t = { 0, 0, 0, 0, 0, 0, 0 }, hide = 0, hs = 0,
	n = "Eve", r = "Nowhere" }
SpokenWindDB.board["Player-1-0000FFF1"] = { n = "Lis", r = "Nowhere", f = 0, h = 0, l = 5, at = clock, hide = 0,
	t = { 0, 0, 0, 0, 0, 0, 0 } }
Id.tab("Board")
L = ns.AchLines("board")
H = Halves()
ok("board tab: the longer list sets the rows (Most heard 1, Top listener 2)", #L.cols[1].rows == 1 and #L.cols[2].rows == 2
	and #H[1] == 1 and #H[2] == 2 and H[2][1].line and H[2][1].line.short == L.cols[2].rows[1].short, #H[1] .. "/" .. #H[2])
local eve = H[1][1]
local tY = eve and TipOf(eve.h) or ""
ok("board tab: an own alt: gold name, tip Char Yours", eve and eve.line.own and not eve.line.me
	and eve.nm.text:find("^|c%x+" .. Esc(eve.line.short) .. "|r$") ~= nil and tY:find("|Char=Yours|", 1, true) ~= nil, tY)
ok("board tab: alt + listener: no ERR", NoErr(), select(2, NoErr()))
for i = 1, 11 do   -- 11 players above you: your row under the list = your real rank
	SpokenWindDB.board[("Player-1-0000B%03d"):format(i)] = { n = "Top" .. i, r = "Nowhere", f = 0, h = 10 + i, l = 10 + i,
		at = clock, hide = 0, t = { 0, 0, 0, 0, 0, 0, 0 } }
end
ns.AchRedraw()
L = ns.AchLines("board")
local ownA = L.cols[1].own
ok("board tab: your row = your real rank (12+), not 1", ownA ~= nil and ownA.rank > 10 and B.ownRow.shown
	and B.ownRkA.text == tostring(ownA.rank), B.ownRkA.text)
Id.W().root:Hide()
end
ME, ME_GUID = "Tester", "Player-1-0000AAAA"
Boot(saved2)
-- an error in the board never breaks the sync
local realG = ns.BoardGotS
ns.BoardGotS = function() error("board boom") end
Msg("S:1:1-0000FFFF,Fay,1,1,1,00", "PARTY", "Fay-Nowhere")
ns.BoardGotS = realG
ok("board: error = ERR board line, no break", SN("ERR board") == 1)
ME, ME_GUID = ME0, MEG0
end)()

;(function()   -- 0.6.4 timer S: one S per 300 s + 0-60 s, guild / group, from the 15 s ticker
local ME0, MEG0 = ME, ME_GUID
ME, ME_GUID = "Tester", "Player-1-0000AAAA"
local T0
local function Boot(db)
	preLogin = function() T0 = clock end
	if db.random == nil then db.random = false end   -- the random fart has its own tests (0.6.6)
	ev, ns = Load(db)
	preLogin = nil
	IsInGroup = function() return true end
	IsInGuild = function() return true end
	IsInRaid, IsInInstance = nil, nil
	SpokenWindDB.cd = 0
	SY.Tiny(ns)
	willPlay = true
	return ns
end
local function SN(s)
	local k = 0
	for _, l in ipairs(SpokenWindDB.sync or {}) do if l:find(s, 1, true) then k = k + 1 end end
	return k
end
local function SFind(s)
	for i = #(SpokenWindDB.sync or {}), 1, -1 do
		local l = SpokenWindDB.sync[i]
		if l:find(s, 1, true) then return l end
	end
	return ""
end
local function Tick(sec)   -- move both clocks in 15 s ticks; the messages the ticker sent
	local out = {}
	for _ = 1, math.floor(sec / 15) do
		clock, now = clock + 15, now + 15
		local na = #SY.asent
		SY.inTick = true
		for _, tk in ipairs(SY.tickers) do if not tk.dead then tk.fn() end end
		SY.inTick = false
		for i = na + 1, #SY.asent do
			local x = SY.asent[i]
			out[#out + 1] = { m = x.m, ch = x.ch, tgt = x.tgt, at = clock - T0 }
		end
	end
	return out
end
local function Chans(list)
	local t = {}
	for _, x in ipairs(list) do t[#t + 1] = x.ch end
	return table.concat(t, ",")
end
local function Press()
	local na = #SY.asent
	hw = true SY.hooks.DoEmote("FART") hw = false
	Emote(OWN_FART, ME, ME_GUID)
	local out = {}
	for i = na + 1, #SY.asent do out[#out + 1] = SY.asent[i] end
	return out
end

Boot({})
ok("timer: one 15 s ticker from login (+ the random fart's)", #SY.tickers == 2 and SY.tickers[1].s == 15 and ns.SYNC.timer.wait == 300
	and ns.SYNC.timer.jit == 60 and ns.SYNC.timer.login == 60, #SY.tickers)
ok("timer: starts once", ns.SyncTimerStart() == false and #SY.tickers == 2 and SN("S timer on") == 1)
local due = tonumber(SFind("S timer on due="):match("due=(%d+)"))
ok("timer: first due 60-120 s after login", due and due >= 60 and due <= 120, SFind("S timer on"))
ok("timer: nothing in the first 45 s", #Tick(45) == 0)
local first = Tick(90)
ok("timer: ONE S by 135 s, after 60 s", #first == 1 and first[1].at >= 60 and first[1].at >= due and first[1].at <= due + 15,
	first[1] and first[1].at)
ok("timer: the S text, no target", first[1] and first[1].m:sub(1, 4) == "S:1:" and first[1].tgt == nil and first[1].m:find("AAAA", 1, true))
ok("timer: guild + group: GUILD first", first[1] and first[1].ch == "GUILD", first[1] and first[1].ch)
ok("timer: sLast = the send time", first[1] and SpokenWindDB.sLast == T0 + first[1].at, SpokenWindDB.sLast)
ok("timer: log line", SN("S timer ch=GUILD n=1 b=") == 1, SFind("S timer ch="))
-- the next ones: 300-375 s apart, one channel each, alternate
local more = Tick(3000)
local gapOk, prev = true, first[1].at
for _, x in ipairs(more) do
	if x.at - prev < 300 or x.at - prev > 375 then gapOk = false end
	prev = x.at
end
ok("timer: 300-375 s apart", #more >= 7 and #more <= 10 and gapOk, #more)
local alt = true
for i, x in ipairs(more) do if x.ch ~= (i % 2 == 1 and "PARTY" or "GUILD") then alt = false end end
ok("timer: alternate PARTY / GUILD, one per send", alt, Chans(more))
ok("timer: only S", (function() for _, x in ipairs(more) do if x.m:sub(1, 4) ~= "S:1:" then return false end end return true end)())
-- a press S resets the wait
Tick(150)
local p = Press()
local pAt = clock - T0
ok("timer: press sends F + S", #p >= 2 and p[#p].m:sub(1, 4) == "S:1:", #p)
ok("timer: press S = sLast", SpokenWindDB.sLast == clock)
local after = Tick(400)
ok("timer: after a press, wait 300-375 s", #after == 1 and after[1].at - pAt >= 300 and after[1].at - pAt <= 375,
	after[1] and after[1].at - pAt)
-- blocked: combat, the game's combat flag, board off, addon off, no guild + no group
combat = true
ok("timer: none in combat", #Tick(450) == 0)
combat = false
ok("timer: resumes after combat (next tick)", #Tick(15) == 1)
UnitAffectingCombat = function(u) return u == "player" end
ok("timer: none while UnitAffectingCombat", #Tick(450) == 0)
UnitAffectingCombat = nil
ok("timer: resumes", #Tick(15) == 1)
Slash("board off")
ok("timer: none with the board off", #Tick(450) == 0)
Slash("board on")
ok("timer: board on = resumes", #Tick(15) == 1)
SpokenWindDB.on = false
ok("timer: none with the addon off", #Tick(450) == 0)
SpokenWindDB.on = true
ok("timer: addon on = resumes", #Tick(15) == 1)
IsInGroup = function() return false end
IsInGuild = function() return false end
local tw = ns.TestWhisper
ns.TestWhisper = function() return "Bo-Nowhere" end
ok("timer: no guild + no group = none, never a whisper", #Tick(900) == 0)
IsInGuild = function() return true end
local g = Tick(900)
ok("timer: guild only = GUILD, never a whisper", #g >= 2 and Chans(g):gsub("GUILD", ""):gsub(",", "") == "", Chans(g))
ns.TestWhisper = tw
IsInGuild = function() return false end
IsInGroup = function() return true end
IsInRaid = function() return true end
local r = Tick(450)
ok("timer: raid = RAID", #r >= 1 and Chans(r):gsub("RAID", ""):gsub(",", "") == "", Chans(r))
IsInRaid = nil
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
IsInGroup = function(c) return c == nil or c == 2 end
local inst = Tick(450)
ok("timer: instance group = INSTANCE_CHAT", #inst >= 1 and Chans(inst):gsub("INSTANCE_CHAT", ""):gsub(",", "") == "", Chans(inst))
IsInGroup = function(c) return c == nil or c == 1 end
local home = Tick(450)
ok("timer: home group = PARTY", #home >= 1 and Chans(home):gsub("PARTY", ""):gsub(",", "") == "", Chans(home))
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = nil, nil
IsInGroup = function() return true end
IsInGuild = function() return true end
-- receive: never a send
local na = #SY.asent
ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", "S:1:1-0000FFFF,Fay,1,1,1,00", "PARTY", "Fay-Nowhere")
ok("timer: a received S sends nothing", #SY.asent == na)
-- a board error: ERR line, no send, waits again
local realS = ns.BoardS
ns.BoardS = function() error("board boom") end
local e, k = {}, 0
while SN("ERR board") == 0 and k < 30 do
	for _, x in ipairs(Tick(15)) do e[#e + 1] = x end
	k = k + 1
end
for _, x in ipairs(Tick(285)) do e[#e + 1] = x end
ns.BoardS = realS
ok("timer: board error = ERR line, no send, waits 300 s again", #e == 0 and SN("ERR board") == 1, SN("ERR board"))
-- log cap 30 lines; SUM sTimer at logout
local lots = Tick(12000)
local total = 0
for _, x in ipairs(SY.asent) do if x.tick and x.m:sub(1, 4) == "S:1:" then total = total + 1 end end
ok("timer: log cap 30 lines", total > 30 and SN("S timer ch=") <= 30 and SN("S timer ch=") >= 29, SN("S timer ch="))
ev.scripts.OnEvent(ev, "PLAYER_LOGOUT")
ok("timer: SUM sTimer at logout", SFind(" SYNC SUM "):find(" sTimer=" .. total .. " sCapped=0 btn=0.0.0.0 rfart=0 rsec=0 classic=0$"), SFind(" SYNC SUM "))
ok("timer: no ERR but the board test", SN("ERR") == 1)
-- /reload: the wait survives (db.sLast); a clock that went back waits from now
local saved = SpokenWindDB
saved.sLast = CLOCK0 - 30   -- the last S 30 s before this login
Boot(saved)
local due2 = tonumber(SFind("S timer on due="):match("due=(%d+)"))
ok("timer: reload: due 270-330 s", due2 and due2 >= 270 and due2 <= 330, due2)
ok("timer: reload: nothing before due", #Tick(255) == 0)
local rl = Tick(120)
ok("timer: reload: one S after the wait", #rl == 1 and rl[1].at >= due2, rl[1] and rl[1].at)
saved.sLast = CLOCK0 + 9999   -- a clock that went back
Boot(saved)
local due3 = tonumber(SFind("S timer on due="):match("due=(%d+)"))
ok("timer: clock went back: due 300-360 s", due3 and due3 >= 300 and due3 <= 360, due3)
saved.sLast = CLOCK0 - 4000   -- long ago: the login wait only
Boot(saved)
local due4 = tonumber(SFind("S timer on due="):match("due=(%d+)"))
ok("timer: old sLast: due 60-120 s", due4 and due4 >= 60 and due4 <= 120, due4)
-- no NewTicker (old client API): no timer, no error
local keepT = SY.noTicker
SY.noTicker = true
Boot({})
SY.noTicker = keepT
ok("timer: no NewTicker = no timer, no line", #SY.tickers == 0 and SN("S timer on") == 0 and SN("ERR") == 0)
ME, ME_GUID = ME0, MEG0
end)()

;(function()   -- 0.6.5 Fart button: one emote per click, the silent check, the 2-click whisper, the answer
local BG, NG = "Player-1-0000B0B0", "Player-1-00000E0E"   -- BG: on the board; NG: sends an F (Sync knows it)
local tgt
local function Unit(u) return u == "target" and tgt or nil end
local function Targets()
	UnitExists = function(u) return u == "player" or Unit(u) ~= nil end
	UnitGUID = function(u) if u == "player" then return ME_GUID end local t = Unit(u) return t and t.g end
	UnitName = function(u) if u == "player" then return ME end local t = Unit(u) if t then return t.n, t.r end end
	UnitIsUnit = function(a, b) local t = Unit(a) return b == "player" and t ~= nil and t.self == true end
	UnitIsPlayer = function(u) if u == "player" then return true end local t = Unit(u) return t ~= nil and not t.npc end
	UnitIsConnected = function(u) if u == "player" then return true end local t = Unit(u) return t ~= nil and not t.off end
	UnitFactionGroup = function(u)
		if u == "player" then return "Alliance" end
		local t = Unit(u)
		if t and not t.nofac then return t.fac or "Alliance" end
	end
	CheckInteractDistance = function(u, i)
		SY.cid = i
		local t = Unit(u)
		if t and t.cidErr then error("cid boom") end
		return t ~= nil and not t.far
	end
end
local function Boot(dev)
	ev, ns = Load({ on = true, rwbtn = true, ch = "SFX", self = true, cd = 0, wait = 150,
		board = { [BG] = { n = "Bea", f = 5, h = 1, l = 2, at = 1, sent = 1, hide = 0, hs = 0, bt = 1, b0 = 8 } }, boardN = 1 },
		"vertical", dev)
	Targets()
	tgt = nil
	willPlay = true
	return (ns.BarRefs())
end
local function Run()
	local i = 1
	while i <= #SY.timers do
		local t = SY.timers[i]
		if t.at <= now + 1e-9 then table.remove(SY.timers, i) t.fn() else i = i + 1 end
	end
end
local function Wait(s) now = now + s Run() end
local function Since(na) local t = {} for i = na + 1, #SY.asent do t[#t + 1] = SY.asent[i] end return t end
local function Press(button)   -- one click on the Fart button: emotes, addon messages and chat lines it made
	local ne, na, nc = #SY.emotes, #SY.asent, #sent
	SY.clickN = 0
	SY.Click((ns.BarRefs()).fart, button)   -- a mouse click (hardware event)
	SY.clickN = nil
	local cl = {}
	for i = nc + 1, #sent do cl[#cl + 1] = sent[i] end
	return #SY.emotes - ne, Since(na), cl
end
local function Pings(list, m)
	local out = {}
	for _, x in ipairs(list) do if x.m == (m or "P:1") then out[#out + 1] = x end end
	return out
end
local function BN(s)
	local k = 0
	for _, l in ipairs(SpokenWindDB.log) do if l:find(s, 1, true) then k = k + 1 end end
	return k
end
local function Got(text, sender, ch) ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", text, ch or "WHISPER", sender) end
local function Target(t)
	tgt = t
	local f = (ns.BarRefs()).root
	f.scripts.OnEvent(f, "PLAYER_TARGET_CHANGED")
end
local function P(n, extra)   -- a player target (made-up names)
	local t = { g = ("Player-1-0000%04X"):format(n), n = "Nim" .. string.char(96 + n % 26) .. n }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end
local function Icon() return (ns.BarRefs()).fartIcon.path end
local function NoNames(tag)   -- BTN lines: no names, no GUIDs
	local bad
	for _, l in ipairs(SpokenWindDB.log) do
		if l:find("BTN", 1, true) and (l:find("Nim", 1, true) or l:find("Bea", 1, true) or l:find("Zed", 1, true)
			or l:find("Player-", 1, true) or l:find("Creature-", 1, true) or l:find("0000", 1, true)) then bad = l end
	end
	ok("fbtn logs: no names, no GUIDs (" .. tag .. ")", bad == nil, bad)
end

-- the Fart button: in the bar (0.8.0), shown and hidden with it
local fb = Boot()
ok("fbtn: made at login, in the bar", fb ~= nil and fb.fart ~= nil and fb.root.shown and fb.fart.shown, #frames)
ok("fbtn: wind icon, label Fart, base look, mouse on, no keys", Icon() == ns.BTN.icon and fb.fartL.text == "Fart"
	and SY.State(fb.fart) == "base" and fb.fart.mouse == true and fb.fart.kb == nil)
reg.byVar.SpokenWind_rwbtn:SetValue(false)
ok("fbtn: bar off = hidden too", fb.root.shown == false)
local nF = #frames
reg.byVar.SpokenWind_rwbtn:SetValue(true)
ok("fbtn: on again = same frames, shown", fb.root.shown and ns.BarRefs() == fb and #frames == nF, #frames - nF)

-- no target: ONE plain emote; the Sync hook sends F as for a key press
IsInGroup = function() return true end
local ne, aw, cl = Press()
local e = SY.emotes[#SY.emotes]
ok("fbtn: no target = ONE FART emote, in the click", ne == 1 and e.token == "FART" and e.unit == nil and e.hw == true, ne)
local nF1 = 0
for _, x in ipairs(aw) do if tostring(x.m):find("^F:1:FART:") and x.ch == "PARTY" and x.hw then nF1 = nF1 + 1 end end
ok("fbtn: the F goes out as for a key press (Sync hook, same click)", nF1 == 1, #aw)
ok("fbtn: no target: no check, no chat line", #Pings(aw) == 0 and #cl == 0 and LogHas("BTN fart tgt=0 has=?"))

-- every why: the fart still happens, no check is sent, no whisper icon
local function Why(t, why, has)
	Target(t)
	local nw, nh = BN("BTN whisper skip why=" .. why), BN("BTN fart tgt=1 has=" .. (has or "?"))
	local n2, a2, c2 = Press()
	ok("fbtn: why=" .. why .. ": the fart, no check, no chat line", n2 == 1 and #Pings(a2) == 0 and #c2 == 0, n2)
	ok("fbtn: why=" .. why .. " logged (has=" .. (has or "?") .. ")", BN("BTN whisper skip why=" .. why) == nw + 1
		and BN("BTN fart tgt=1 has=" .. (has or "?")) == nh + 1, LastLog())
	ok("fbtn: why=" .. why .. ": no whisper icon", Icon() == ns.BTN.icon)
end
Why({ g = "Creature-0-1-2-3-299-0000ABCD", n = "Boar", npc = true }, "npc")
Why(P(1, { self = true, g = ME_GUID, n = ME }), "self")
Why(P(2, { off = true }), "offline")
Why(P(3, { fac = "Horde" }), "faction")
Why(P(57, { nofac = true }), "faction")
Why(P(4, { far = true }), "range")
ok("fbtn: range = CheckInteractDistance index 4 (about 28 yd)", SY.cid == 4, SY.cid)
Why(P(5, { cidErr = true }), "range")
local keep = CheckInteractDistance
CheckInteractDistance = nil
Why(P(6), "range")
CheckInteractDistance = keep
NoNames("why")
fb = Boot()
Why({ g = BG, n = "Bea" }, "has", "y")
Got(("F:1:FART:%s:4:0:1"):format(NG), "Kip-Nowhere", "PARTY")
Why({ g = NG, n = "Kip" }, "has", "y")

-- a clean player: the check, no answer in 2 s, the icon, click 2 = the whisper
local A = P(7)
Target(A)
local n3, a3, c3 = Press()
local pp = Pings(a3)
ok("fbtn: clean target: the fart + ONE P:1 by WHISPER to the name, in the click", n3 == 1 and #pp == 1
	and pp[1].ch == "WHISPER" and pp[1].tgt == A.n and pp[1].hw == true and pp[1].p == "SpWind" and #c3 == 0, #pp)
Wait(1.9)
ok("fbtn: no icon before 2 s", Icon() == ns.BTN.icon)
local n3b, a3b = Press()
ok("fbtn: a click while waiting = a fart, no second check", n3b == 1 and #Pings(a3b) == 0, #Pings(a3b))
Wait(0.2)
ok("fbtn: no answer in 2 s = the whisper icon", Icon() == ns.BTN.iconW and LogHas("BTN fart tgt=1 has=n") and LogHas("BTN whisper icon"))
ok("fbtn: ready = warn look, Tell? 10", SY.State(fb.fart) == "warn" and fb.fartL.text == "Tell? 10", fb.fartL.text)
local n4, a4, c4 = Press()
ok("fbtn: click 2 = ONE chat line, no emote, no addon message", n4 == 0 and #a4 == 0 and #c4 == 1, n4 .. "/" .. #c4)
ok("fbtn: the whisper = the public text, WHISPER, the name", c4[1] and c4[1].text == ns.BTN.text and c4[1].chan == "WHISPER"
	and c4[1].tgt == A.n)
ok("fbtn: whisper logged n=1, icon back", LogHas("BTN whisper sent n=1") and Icon() == ns.BTN.icon)
local n5, a5, c5 = Press()
ok("fbtn: click 3 = a fart, once per player: no check, no whisper", n5 == 1 and #Pings(a5) == 0 and #c5 == 0
	and LastLog():find("why=once", 1, true) ~= nil, LastLog())
-- another realm: the whisper name has the realm
local R = P(8, { r = "Elsewhere" })
Target(R) Press() Wait(2.1)
local _, _, cR = Press()
ok("fbtn: another realm = Name-Realm", cR[1] and cR[1].tgt == R.n .. "-Elsewhere", cR[1] and cR[1].tgt)

NoNames("whisper")
fb = Boot()
-- an answer in 2 s = a user: no icon, known for the session
local B = P(9)
Target(B)
local _, a6 = Press()
Got("Q:1", B.n .. "-Nowhere")
Wait(2.1)
ok("fbtn: Q:1 in 2 s = has=y, no icon", #Pings(a6) == 1 and Icon() == ns.BTN.icon and LogHas("BTN fart tgt=1 has=y"))
local n7, a7 = Press()
ok("fbtn: an answering player is known: no new check", n7 == 1 and #Pings(a7) == 0 and LastLog():find("why=has", 1, true) ~= nil)
-- a Q:1 not by whisper or from someone else is no answer
local C = P(10)
Target(C) Press()
Got("Q:1", C.n .. "-Nowhere", "PARTY")
Got("Q:1", "Other-Nowhere")
Wait(2.1)
ok("fbtn: Q:1 by PARTY or from another player = no answer", Icon() == ns.BTN.iconW)
Wait(9.9)
ok("fbtn: the icon stays 10 s, Tell? counts down", Icon() == ns.BTN.iconW and fb.fartL.text == "Tell? 1", fb.fartL.text)
Wait(0.2)
ok("fbtn: after 10 s the icon goes", Icon() == ns.BTN.icon and LogHas("BTN whisper icon off") and fb.fartL.text == "Fart"
	and SY.State(fb.fart) == "base")
local n8, a8, c8 = Press()
ok("fbtn: a click after 10 s = a plain click (fart + a new check)", n8 == 1 and #c8 == 0 and #Pings(a8) == 1)
-- another realm: a Q:1 from the same name on a third realm is no answer; a late Q:1 (icon shown) still counts
local R2 = P(60, { r = "Elsewhere" })
Target(R2) Press()
Got("Q:1", R2.n .. "-Other")
Wait(2.1)
ok("fbtn: Q:1 from the same name, other realm = no answer", Icon() == ns.BTN.iconW)
local nk = BN("BTN whisper skip why=has")
Got("Q:1", R2.n .. "-Elsewhere")
ok("fbtn: a late Q:1 = the icon goes, why=has", Icon() == ns.BTN.icon and BN("BTN whisper skip why=has") == nk + 1)
local nL, aL, cL = Press()
ok("fbtn: then a click = a fart, known: no check, no whisper", nL == 1 and #Pings(aL) == 0 and #cL == 0)
-- Forever (live 2026-11-23): UnitName = "First", "Surname"; the addon sender is "First Surname" (maybe + "-Realm")
for i, tail in ipairs({ " Picklebottom", " Picklebottom-Nowhere", " picklebottom" }) do
	local FS = P(60 + i, { r = "Picklebottom" })
	local ny = BN("BTN fart tgt=1 has=y")
	Target(FS)
	local _, aF = Press()
	local pF = Pings(aF)
	Got("Q:1", FS.n .. tail)
	Wait(2.1)
	ok("fbtn: Forever: Q:1 from 'First Surname" .. tail:sub(9) .. "' = has=y, no icon", #pF == 1 and pF[1].tgt == FS.n .. "-Picklebottom"
		and Icon() == ns.BTN.icon and BN("BTN fart tgt=1 has=y") == ny + 1, pF[1] and pF[1].tgt)
end
local FX = P(64, { r = "Picklebottom" })
Target(FX) Press()
Got("Q:1", FX.n .. " Other")
Wait(2.1)
ok("fbtn: Forever: same first name, other surname = no answer", Icon() == ns.BTN.iconW)
Wait(10.1)
-- a new target ends the check
Target(P(11))
Wait(2.1)
ok("fbtn: a new target while waiting = no icon", Icon() == ns.BTN.icon)
local D = P(12)
Target(D) Press() Wait(2.1)
Target(P(13))
ok("fbtn: a new target ends the icon", Icon() == ns.BTN.icon)
local n9, a9, c9 = Press()
ok("fbtn: then a click = a fart + a check for the new target", n9 == 1 and #c9 == 0 and #Pings(a9) == 1 and Pings(a9)[1].tgt ~= D.n)
NoNames("answer")
fb = Boot()
-- click 2: every check again; a fail = a plain fart click, no whisper
for _, why in ipairs({ "range", "offline", "faction" }) do
	local E = P(14 + #why)
	Target(E) Press() Wait(2.1)
	if why == "range" then E.far = true elseif why == "offline" then E.off = true else E.fac = "Horde" end
	local nw = BN("BTN whisper skip why=" .. why)
	local nE, aE, cE = Press()
	ok("fbtn: click 2, now " .. why .. " = the fart, no whisper", nE == 1 and #cE == 0 and #Pings(aE) == 0
		and BN("BTN whisper skip why=" .. why) == nw + 1 and Icon() == ns.BTN.icon, nE .. "/" .. #cE)
end
local G = P(30)
Target(G) Press() Wait(2.1)
Got(("F:1:FART:%s:4:0:1"):format(G.g), G.n .. "-Nowhere", "PARTY")   -- it farts with the addon meanwhile
local nG, _, cG = Press()
ok("fbtn: click 2, now a known user = the fart, no whisper", nG == 1 and #cG == 0 and LastLog():find("why=has", 1, true) ~= nil)
-- a failed ping send = no icon
SY.sendRes = false
Target(P(31))
local _, aS = Press()
SY.sendRes = nil
Wait(2.1)
ok("fbtn: the ping send fails = why=send, no icon", #Pings(aS) == 1 and LogHas("BTN whisper skip why=send") and Icon() == ns.BTN.icon)
NoNames("click 2")
fb = Boot()
-- click 2 guards without the events: another target (event missed) or over 10 s (timer missed) = a plain fart click
Target(P(33)) Press() Wait(2.1)
tgt = P(34)
local nH, aH, cH = Press()
ok("fbtn: click 2 on another target (no event) = the fart + its own check, no whisper", nH == 1 and #cH == 0
	and #Pings(aH) == 1 and Pings(aH)[1].tgt == tgt.n)
Wait(2.1)
now = now + 10.5
local nT, _, cT = Press()
ok("fbtn: click 2 after 10 s (no timer) = a fart, no whisper", nT == 1 and #cT == 0 and Icon() == ns.BTN.icon)
Run()
-- combat: no mouse, the check ends, a click does nothing
Target(P(32)) Press() Wait(2.1)
combat = true
fb.root.scripts.OnEvent(fb.root, "PLAYER_REGEN_DISABLED")
ok("fbtn: combat = no mouse, the check ends, Combat", fb.fart.mouse == false and Icon() == ns.BTN.icon and fb.fartL.text == "Combat"
	and SY.State(fb.fart) == "off")
local nC, aC, cC = Press()
ok("fbtn: a click in combat does nothing", nC == 0 and #aC == 0 and #cC == 0)
combat = false
fb.root.scripts.OnEvent(fb.root, "PLAYER_REGEN_ENABLED")
ok("fbtn: after combat: mouse on, Fart", fb.fart.mouse == true and fb.fartL.text == "Fart")
-- the emote call fails: a log line, no Lua error out of the click
SY.emoteErr = true
Target(nil)
local sums = ns.BtnSums()
local okE = pcall(Press)
SY.emoteErr = nil
ok("fbtn: the emote call fails = ERR btn line, no error out, not counted", okE and LogHas("ERR btn") and ns.BtnSums() == sums, ns.BtnSums())
-- the bar hides during a check: the check ends
Target(P(35)) Press() Wait(2.1)
reg.byVar.SpokenWind_rwbtn:SetValue(false)
reg.byVar.SpokenWind_rwbtn:SetValue(true)
ok("fbtn: hidden during a check = the check ends", Icon() == ns.BTN.icon)
local nV, _, cV = Press()
ok("fbtn: then a click = a fart, no whisper", nV == 1 and #cV == 0)
NoNames("flow")

-- the cap: 10 whispers per 10 min. The count (bottom right): whispers left, or the red time to the next free one.
fb = Boot()
local function Whisp(t)
	Target(t) Press() Wait(2.1)
	local _, _, c = Press()
	return #c == 1
end
local function Cnt() return fb.fartW.text end
local RD = "|cffff2020"
local function Soon(s)   -- timers due in the next s seconds
	local k = 0
	for _, x in ipairs(SY.timers) do if x.at > now and x.at <= now + s then k = k + 1 end end
	return k
end
ok("fbtn count: the corner text of the Fart button, 10 at start", Cnt() == "10", Cnt())
local okW, cnts = true, {}
for i = 1, 10 do
	if not Whisp(P(40 + i)) then okW = false end
	cnts[#cnts + 1] = Cnt()
end
ok("fbtn: 10 whispers in 10 min", okW and LogHas("BTN whisper sent n=10"))
ok("fbtn count: one less each whisper, then the red time", table.concat(cnts, ",") == "9,8,7,6,5,4,3,2,1," .. RD .. "10m|r",
	table.concat(cnts, ","))
Target(P(51))
local nS = #sent
local nX, aX = Press()
ok("fbtn: the 11th in 10 min = the fart, no check (why=cap)", nX == 1 and #Pings(aX) == 0 and LastLog():find("why=cap", 1, true) ~= nil)
ok("fbtn count: the 11th click keeps the red time", Cnt() == RD .. "10m|r", Cnt())
-- the whispers went out 2.1 s apart: the first one 18.9 s before the 10th
Wait(522)   -- 540.9 s after the first = 59.1 s left
ok("fbtn count: 60 s left = 1m", Cnt() == RD .. "1m|r", Cnt())
Wait(1)
ok("fbtn count: under a minute = seconds, a redraw each second", Cnt() == RD .. "59|r", Cnt())
Wait(58)
ok("fbtn count: last second = 1, red", Cnt() == RD .. "1|r", Cnt())
Wait(1)
ok("fbtn count: the first one free = 1, white", Cnt() == "1", Cnt())
ok("fbtn count: one redraw timer (old ones do nothing)", Soon(1.3) == 1, Soon(1.3))
Wait(1.3)
ok("fbtn count: the next one free = 2, no click", Cnt() == "2", Cnt())
reg.byVar.SpokenWind_rwbtn:SetValue(false)
Wait(10)
ok("fbtn count: hidden = no redraw", not fb.root.shown and Cnt() == "2", Cnt())
reg.byVar.SpokenWind_rwbtn:SetValue(true)
ok("fbtn count: shown again = fresh", fb.root.shown and Cnt() == "6", Cnt())
ok("fbtn count: its timers never send (no chat line, no whisper)", #sent == nS, #sent - nS)
Wait(600)
ok("fbtn count: all free again = 10", Cnt() == "10", Cnt())
ok("fbtn: 10 min later a whisper works again", Whisp(P(52)) and LogHas("BTN whisper sent n=11") and Cnt() == "9", Cnt())
-- the log cap: max 40 BTN lines per session; the SUM line counts all (farts.pings.whispers.pongs)
Target(nil)
for _ = 1, 50 do Press() end
ok("fbtn: max 40 BTN log lines per session", BN("BTN ") == 40, BN("BTN "))
ok("fbtn: session sums count past the cap", ns.BtnSums() == "62.11.11.0", ns.BtnSums())
ns.SyncSum()
ok("fbtn: SUM line btn=", (SpokenWindDB.sync[#SpokenWindDB.sync] or ""):find(" btn=62.11.11.0 rfart=0 rsec=0 classic=0$") ~= nil, SpokenWindDB.sync[#SpokenWindDB.sync])
NoNames("cap")

-- the answer (pong): a WHISPER P:1 = ONE Q:1; 1 per sender per 30 s; 10 per minute; whisper only
fb = Boot()
local na = #SY.asent
Got("P:1", "Zed-Nowhere")
local q = Pings(Since(na), "Q:1")
ok("pong: a WHISPER P:1 = ONE Q:1 back by WHISPER, outside a click", #q == 1 and q[1].ch == "WHISPER"
	and q[1].tgt == "Zed-Nowhere" and q[1].hw == false and LogHas("BTN pong n=1"), #q)
na = #SY.asent
Got("P:1", "Zed-Nowhere")
Wait(29)
Got("P:1", "Zed-Nowhere")
ok("pong: max 1 per sender per 30 s", #Since(na) == 0, #Since(na))
Wait(1)
Got("P:1", "Zed-Nowhere")
ok("pong: after 30 s again", #Pings(Since(na), "Q:1") == 1)
na = #SY.asent
for _, ch in ipairs({ "PARTY", "RAID", "GUILD", "SAY", "INSTANCE_CHAT" }) do Got("P:1", "Yan-Nowhere", ch) end
Got("P:2", "Yan-Nowhere")
Got("Q:1", "Yan-Nowhere")
ok("pong: P:1 not by whisper, P:2, a stray Q:1 = no answer", #Since(na) == 0, #Since(na))
ns.BtnGot("X:1", "Xan-Nowhere")
ns.BtnGot("P:1", "")
ns.BtnGot("P:1", nil)
ok("pong: BtnGot answers only P:1 from a name", #Since(na) == 0, #Since(na))
ok("sync: SyncWhisper sends only P:1 or Q:1, only to a name", ns.SyncWhisper("F:1:FART:x", "Zed-Nowhere") == false
	and ns.SyncWhisper("P:1", "") == false and ns.SyncWhisper("Q:1", nil) == false and #Since(na) == 0, #Since(na))
fb = Boot()
na = #SY.asent
for i = 1, 12 do Got("P:1", "Pp" .. string.char(96 + i) .. "-Nowhere") end
ok("pong: max 10 per minute", #Pings(Since(na), "Q:1") == 10, #Pings(Since(na), "Q:1"))
Wait(61)
na = #SY.asent
Got("P:1", "Ppz-Nowhere")
ok("pong: a minute later again", #Pings(Since(na), "Q:1") == 1)
NoNames("pong")

-- right-click: ONE /say line (the same text), 1 per 5 min (own count, apart from the whispers), the wait red top left
fb = Boot()
do
	local function SayCell() return fb.fartS and fb.fartS.text end
	ok("fbtn say: cell top left of the Fart icon, the UI font, empty at start", SayCell() == "" and fb.fartS.pt
		and fb.fartS.pt[1] == "TOPLEFT" and fb.fartS.pt[2] == fb.fartIcon and fb.fartS.pt[3] == "TOPLEFT"
		and tostring(fb.fartS.fontPath):find("Lato.ttf", 1, true) ~= nil, SayCell())
	Target(P(70)) Press() Wait(2.1)
	local nR, aR, cR = Press("RightButton")
	ok("fbtn say: right click = ONE /say line, the public text, no emote, no addon message", nR == 0 and #aR == 0 and #cR == 1
		and cR[1].chan == "SAY" and cR[1].text == ns.BTN.text and cR[1].tgt == nil and BN("BTN say sent n=1") == 1, #cR)
	ok("fbtn say: the whisper icon + count stay", Icon() == ns.BTN.iconW and Cnt() == "10", Cnt())
	ok("fbtn say: the wait, red, top left", SayCell() == RD .. "5m|r", SayCell())
	local _, _, cW = Press()
	ok("fbtn say: then a left click = the whisper, as before", #cW == 1 and cW[1].chan == "WHISPER" and Cnt() == "9", Cnt())
	local nR2, aR2, cR2 = Press("RightButton")
	ok("fbtn say: a second right click in 5 min = nothing, why=cap", nR2 == 0 and #aR2 == 0 and #cR2 == 0
		and BN("BTN say skip why=cap") == 1 and BN("BTN say sent") == 1)
	Target(nil)
	Wait(60.5)   -- 239.5 s left
	ok("fbtn say: 4m", SayCell() == RD .. "4m|r", SayCell())
	reg.byVar.SpokenWind_rwbtn:SetValue(false)
	Wait(60)     -- 179.5 s left, the bar hidden: no redraw
	reg.byVar.SpokenWind_rwbtn:SetValue(true)
	ok("fbtn say: bar shown again = the wait of now", fb.root.shown and SayCell() == RD .. "3m|r", SayCell())
	Wait(121)    -- 58.5 s left
	ok("fbtn say: under a minute = seconds", SayCell() == RD .. "59|r", SayCell())
	Wait(58)
	ok("fbtn say: last second", SayCell() == RD .. "1|r", SayCell())
	Wait(1)
	ok("fbtn say: 5 min later = free, the cell empty", SayCell() == "", SayCell())
	local nR3, _, cR3 = Press("RightButton")
	ok("fbtn say: then a /say again, no target", nR3 == 0 and #cR3 == 1 and cR3[1].chan == "SAY" and BN("BTN say sent n=2") == 1)
	combat = true
	fb.root.scripts.OnEvent(fb.root, "PLAYER_REGEN_DISABLED")
	Wait(301)
	local nRC, aRC, cRC = Press("RightButton")
	ok("fbtn say: in combat = nothing", nRC == 0 and #aRC == 0 and #cRC == 0 and BN("BTN say sent n=3") == 0)
	combat = false
	fb.root.scripts.OnEvent(fb.root, "PLAYER_REGEN_ENABLED")
	ok("fbtn say: free = the cell stays empty", SayCell() == "", SayCell())
	SY.chatErr = true
	Press("RightButton")
	SY.chatErr = nil
	ok("fbtn say: a chat error = ERR btn, not counted, no wait", LogHas("ERR btn") and BN("BTN say sent n=3") == 0 and SayCell() == "")
	local _, _, cE2 = Press("RightButton")
	ok("fbtn say: after the error a /say works", #cE2 == 1 and BN("BTN say sent n=3") == 1)
	Wait(301)
	NoNames("say")
end

-- the texts: one chat line each, only what this build has; the creator line only with the dev addon
local T1, T2 = ns.BTN.text, ns.BTN.textDev
ok(("fbtn: texts fit one chat line (%d and %d of 255 bytes)"):format(#T1, #T2), #T1 <= 255 and #T2 <= 255)
ok("fbtn: public text: no creator line; dev text = I made", not T1:find("I made", 1, true)
	and (T2:gsub("I made Spoken Wind:", "Spoken Wind:")) == T1)
local both = (T1 .. T2):lower()
ok("fbtn: text B, word for word (approved 2026-11-23)", T1 == "Wish you heard that fart? Now you can! Spoken Wind: 1337 synced "
	.. "farts. Girl farts sound different from boy farts, and every race has its own. Leaderboard and achievements. Inspired by "
	.. "Spoken (voiced NPCs, check it out). Get it on CurseForge.", T1)
ok("fbtn: texts claim only this build: 1337 = the full set here", both:find("1337 synced farts", 1, true)
	and ns.AchRow("complete") and ns.AchRow("complete").dex == 1337 and not both:find("rewards", 1, true))
ok("fbtn: texts name Spoken Wind, Spoken, CurseForge", T1:find("Spoken Wind:", 1, true) and T1:find("Inspired by Spoken ", 1, true)
	and T1:find("CurseForge", 1, true))
fb = Boot(true)
Target(P(50)) Press() Wait(2.1)
local _, _, cD = Press()
ok("fbtn: dev addon = the creator text", cD[1] and cD[1].text == T2, cD[1] and cD[1].text)
local _, _, cDS = Press("RightButton")
ok("fbtn say: dev addon = the creator text on /say too", cDS[1] and cDS[1].chan == "SAY" and cDS[1].text == T2, cDS[1] and cDS[1].text)
Wait(301)   -- the /say cell ends its timer

-- the source: one emote call, one chat send, no Blizzard writes, no hooks, no keys
local src = assert(io.open(ADDON_DIR .. "/Button.lua", "rb")):read("*a")
local code = src:gsub("%-%-[^\n]*", "")
local function Cnt(s) local k = 0 for _ in code:gmatch(s) do k = k + 1 end return k end
ok("fbtn src: DoEmote once (in the click)", Cnt("DoEmote") == 1 and Cnt('pcall%(DoEmote, "FART"%)') == 1)
ok("fbtn src: one chat send (Chat), WHISPER + SAY", Cnt("SendChatMessage") == 2 and Cnt('"WHISPER"') == 1 and Cnt('"SAY"') == 1
	and Cnt("local send = C_ChatInfo and C_ChatInfo%.SendChatMessage or SendChatMessage") == 1 and Cnt("pcall%(send,") == 1)
ok("fbtn src: addon messages only by Sync (P:1, Q:1)", Cnt("SendAddonMessage") == 0 and Cnt('SyncWhisper%("P:1"') == 1
	and Cnt('SyncWhisper%("Q:1"') == 1)
local badSrc
for _, w in ipairs({ "SetCVar", "hooksecurefunc", "UISpecialFrames", "SetPropagateKeyboardInput", "SetBinding", "NewTicker",
	"EnableKeyboard", "EnableGamePad", "RunMacro", "setglobal", "SetOverride", "OnUpdate", "OnKeyDown" }) do
	if code:find(w, 1, true) then badSrc = w end
end
if code:find("[^%w_]_G[^%w_]") then badSrc = "_G" end
ok("fbtn src: no CVar, hooks, Blizzard tables, keys, tickers", badSrc == nil, badSrc)
UnitExists, UnitIsUnit, UnitIsPlayer, UnitIsConnected, CheckInteractDistance, IsInGroup = nil, nil, nil, nil, nil, nil
end)()

;(function()   -- old clients get 0.6.4+ messages + a 0.6.6 save: 0.6.2 to 0.6.5 (tests/compat/<v> = that stage's Lua + toc)
local keep = ADDON_DIR
local RG = "Player-1-0000CCCC"
local function Msg(text, name) ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", text, "PARTY", name) end
local function Run()
	local i = 1
	while i <= #SY.timers do
		local t = SY.timers[i]
		if t.at <= now + 1e-9 then table.remove(SY.timers, i) t.fn() else i = i + 1 end
	end
end
local function SyncN(s)
	local k = 0
	for _, l in ipairs(SpokenWindDB.sync or {}) do if l:find(s, 1, true) then k = k + 1 end end
	return k
end
local function NoErr()
	for _, t in ipairs({ SpokenWindDB.log or {}, SpokenWindDB.sync or {} }) do
		for _, l in ipairs(t) do if l:find("ERR", 1, true) then return false, l end end
	end
	return true
end
local function Save() return { on = true, chars = { [ME_GUID] = { f = 3, h = 1, l = 2, t = { 0, 0, 0, 0, 0, 0, 1 }, hide = 0, hs = 0, n = ME, r = "" } },
	board = { [RG] = { n = "Rae", f = 5, h = 1, l = 2, at = 1, sent = 1, hide = 0, hs = 0, bt = 1, b0 = 8 } }, boardN = 1, seenWin = { 1, 0 },
	boardOff = false, sLast = 1, stats = { own = 3, heard = 1, people = {}, best = 1, legend = 0, legendHeard = 0 },
	random = false, randTgt = true } end   -- + the 0.6.6 keys
for _, v in ipairs({ "0.6.2", "0.6.3", "0.6.4", "0.6.5" }) do
	ADDON_DIR = ROOT .. "/tests/compat/" .. v
	local okAll, err = pcall(function()
		ev, ns = Load(Save(), "vertical")
		IsInGroup = function() return true end
		IsInGuild = function() return true end
		SpokenWindDB.cd = 0
		willPlay = true
		ok(v .. " compat: a 0.6.6 save loads, no error", LastLog():find("BOOT v=" .. v .. " ", 1, true) ~= nil and NoErr(), LastLog())
		now = now + 5 Run()
		local np, ns0 = #plays, #SY.asent
		Msg("S:1:1-0000CCCC,Rae,5,1,2,00;1-0000BBBB,Quin,3,0,1,00", "Rae-Nowhere")
		ok(v .. ((v == "0.6.4" or v == "0.6.5") and " compat: S merged" or " compat: S ignored") .. ": no sound, no send, no error", #plays == np and #SY.asent == ns0 and NoErr(), select(2, NoErr()))
		ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", "P:1", "WHISPER", "Rae-Nowhere")
		ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", "Q:1", "WHISPER", "Rae-Nowhere")
		if v == "0.6.5" then   -- 0.6.5 has the Fart button: P:1 = its one Q:1 pong
			local last = SY.asent[#SY.asent]
			ok(v .. " compat: Fart button check: one Q:1 pong by WHISPER, no sound, no error", #plays == np and #SY.asent == ns0 + 1
				and last.m == "Q:1" and last.ch == "WHISPER" and NoErr(), select(2, NoErr()))
			ns0 = #SY.asent
		else
			ok(v .. " compat: Fart button check (P:1, Q:1) ignored: no sound, no send, no error", #plays == np and #SY.asent == ns0
				and NoErr(), select(2, NoErr()))
		end
		np = #plays
		Msg(("F:1:FART:%s:4:0:1::7.2.3:1.0.0.0.0.0.2"):format(RG), "Rae-Nowhere")
		now = now + 0.04
		Emote(FartBy("Rae"), "Rae", RG)
		now = now + 0.3 Run()
		if v == "0.6.2" then
			ok(v .. " compat: F with numbers dropped, the emote still plays (seed), no error", #plays == np + 1
				and SyncN("SYNC by=seed") == 1 and NoErr(), select(2, NoErr()))
		else
			ok(v .. " compat: F with numbers plays from the message (extra fields ignored)", #plays == np + 1
				and SyncN("SYNC by=msg") == 1 and NoErr(), select(2, NoErr()))
		end
		ns0 = #SY.asent
		Msg(("H:1:%s:1:%s::4.5.6"):format(ME_GUID, "Player-1-0000BBBB"), "Quin-Nowhere")
		ok(v .. " compat: H with numbers: no send, no error", #SY.asent == ns0 and NoErr(), select(2, NoErr()))
		ok(v .. " compat: the 0.6.4 rows stay in the save", SpokenWindDB.chars and SpokenWindDB.chars[ME_GUID].f == 3
			and SpokenWindDB.board[RG].n == "Rae")
		ok(v .. " compat: the 0.6.6 keys stay in the save (random, randTgt)", SpokenWindDB.random == false
			and SpokenWindDB.randTgt == true)
	end)
	ok(v .. " compat (0.6.6): ran without a Lua error", okAll, err)
end
ADDON_DIR = keep
end)()

;(function()   -- 0.6.6 random farts: one /fart every 45-75 min at no one, the guards, the wake-up fart, the fart attack
local ME0, MEG0 = ME, ME_GUID
ME, ME_GUID = "Tester", "Player-1-0000AAAA"
local OWN = "You fart loudly. Phew...what stinks?"
local AT_BOB = "You brush up against Bob and fart loudly."
local st = {}   -- the game's answers for the player
local function Stubs()
	UnitIsAFK = function(u) if u == "player" then return st.afk or false end return false end
	UnitIsDeadOrGhost = function(u) return u == "player" and st.dead or false end
	UnitIsFeignDeath = function(u) return u == "player" and st.fd or false end
	UnitAffectingCombat = function(u) return u == "player" and st.ucombat or false end
	IsStealthed = function() return st.stealth or false end
	UnitCastingInfo = function(u) if u == "player" and st.cast then return "Craft" end return nil end
	UnitChannelInfo = function(u) if u == "player" and st.chan then return "Chan" end return nil end
	InCinematic = function() return st.incine or false end
	IsInCinematicScene = function() return st.scene or false end
	UnitExists = function(u) return u == "target" and st.tgt ~= nil end
	UnitName = function(u)
		if u == "player" then return ME end
		if u == "target" then return st.tgt end
		return nil
	end
	UnitRace = function(u) if u == "player" then return "Race", st.race or "Dwarf", 3 end return nil end
	C_UnitAuras = { GetPlayerAuraBySpellID = function(id)   -- st.aura[id]: true = on, "SECRET" = a hidden answer
		local a = st.aura and st.aura[id]
		if a == "SECRET" then return "SECRET" end
		if a then return { spellId = id, name = "Aura" .. id } end
		return nil
	end }
	C_Secrets = { ShouldAurasBeSecret = function() return st.hide == true end }
end
local realRandom = math.random
math.random = function(a, b)   -- st.rig["a-b"] = a fixed answer for that range (the wake-up tests)
	local r = st.rig and a and b and st.rig[a .. "-" .. b]
	if r then return r end
	if a == nil then return realRandom() elseif b == nil then return realRandom(a) end
	return realRandom(a, b)
end
local spy = {}
local function Spy(n, name)
	local real = n[name]
	n[name] = function(...) spy[name] = (spy[name] or 0) + 1 return real(...) end
end
local tphase = 0   -- RunT: s since the boot (the ticker ticks each 15 s)
local function Boot(db, pre, mode)
	st = {}
	Stubs()   -- the aura and race answers at login too
	preLogin = pre
	ev, ns = Load(db or {}, mode)
	preLogin = nil
	IsInGroup = function() return true end
	IsInGuild = function() return true end
	IsInRaid, IsInInstance = nil, nil
	SpokenWindDB.cd = 0
	SY.Tiny(ns)
	willPlay = true
	spy, tphase = {}, 0
	Stubs()
	for _, name in ipairs({ "HeardSelf", "AchSeen", "AchPlayed", "FartLogAdd", "DexAdd" }) do Spy(ns, name) end
	return ns
end
local function Lines(s)
	local out = {}
	for _, l in ipairs(SpokenWindDB.sync or {}) do if l:find(s, 1, true) then out[#out + 1] = l end end
	return out
end
local function RN(s) return #Lines(s) end
local function RLast(s) local t = Lines(s) return t[#t] or "" end
local function Due() return tonumber(RLast("RAND on due="):match("due=(%d+)")) end
local function Rands()   -- DoEmote calls from a tick (the random fart)
	local k = 0
	for _, x in ipairs(SY.emotes) do if x.tick and not x.hw and x.token == "FART" then k = k + 1 end end
	return k
end
local BAG, CAMP = 429960, 1229739
local function RunT(sec)   -- 1 s steps: the 15 s ticker ticks and the due timers (wake-up steps), no key press
	for _ = 1, sec do
		clock, now, tphase = clock + 1, now + 1, tphase + 1
		SY.inTick = true
		if tphase % 15 == 0 then for _, tk in ipairs(SY.tickers) do if not tk.dead then tk.fn() end end end
		local i = 1
		while i <= #SY.timers do
			local t = SY.timers[i]
			if t.at <= now + 1e-9 then table.remove(SY.timers, i) t.fn() else i = i + 1 end
		end
		SY.inTick = false
	end
end
local function SetAura(id, on)   -- the game: an aura on / off, then UNIT_AURA for the player
	st.aura = st.aura or {}
	st.aura[id] = on or nil
	ev.scripts.OnEvent(ev, "UNIT_AURA", "player", {})
end
local function Bag(on) SetAura(BAG, on) end
local function Farts()   -- FART calls not from a key press (hourly, wake-up, attack; blocked tries too)
	local k = 0
	for _, x in ipairs(SY.emotes) do if x.token == "FART" and not x.hw then k = k + 1 end end
	return k
end
local function Sighs()
	local k = 0
	for _, x in ipairs(SY.emotes) do if x.token == "SIGH" then k = k + 1 end end
	return k
end
local function Tick(sec)
	for _ = 1, math.floor(sec / 15) do
		clock, now = clock + 15, now + 15
		SY.inTick = true
		for _, tk in ipairs(SY.tickers) do if not tk.dead then tk.fn() end end
		SY.inTick = false
	end
end
local function TickUntil(max)   -- ticks until one random fart (or max s); returns the s it took
	local n0, t = Rands(), 0
	while Rands() == n0 and t < max do Tick(15) t = t + 15 end
	return t
end
local function LastF()
	for i = #SY.asent, 1, -1 do
		local m = SY.asent[i].m
		if tostring(m):sub(1, 4) == "F:1:" then return m, SY.asent[i] end
	end
end
local function Fs(from)
	local out = {}
	for i = from + 1, #SY.asent do if tostring(SY.asent[i].m):sub(1, 4) == "F:1:" then out[#out + 1] = SY.asent[i] end end
	return out
end
local function Press()   -- a key press: the hook, then the game's own line
	hw = true SY.hooks.DoEmote("FART") hw = false
	Emote(OWN, ME, ME_GUID)
end
local function Counts()
	local n = ns.HeardNums()
	local f = 0
	for _, c in pairs(SpokenWindDB.chars or {}) do f = f + (c.f or 0) end
	return ("own=%d heard=%d people=%d best=%d f=%d flog=%d dex=%d ach=%d"):format(n.own, n.heard, n.people, n.best, f,
		#SpokenWindDB.farts, ns.DexCount(), ns.AchDone())
end
local forb0 = #forbidden

-- the numbers, the default, the boot
Boot()
ok("rand: numbers 2700 + 0-1800 s, 15 s ticks, 60 s login, 60 log lines", ns.RAND.min == 2700 and ns.RAND.span == 1800
	and ns.RAND.tick == 15 and ns.RAND.login == 60 and ns.RAND.logMax == 60)
ok("rand: on by default", SpokenWindDB.random == true and ns.DEFAULTS.random == true)
ok("rand: BOOT rnd=1 tgt=0 aur=1 rev=12", LogHas(" rnd=1 tgt=0 aur=1 rev=12 dev="), LastLog())
ok("rand: own 15 s ticker (after the timer S one)", #SY.tickers == 2 and SY.tickers[2].s == 15)
local d = Due()
ok("rand: first wait 45-75 min after login", d and d >= 2700 and d <= 4500, d)
ok("rand: a second login event = no second ticker, no second line", (function()
	ev.scripts.OnEvent(ev, "PLAYER_LOGIN")
	return #SY.tickers == 2 and RN("RAND on") == 1
end)())

-- nothing before the due time, then exactly one fart at no one
local c0 = Counts()
Tick(d - 15)
ok("rand: nothing before the due time", Rands() == 0 and RN("RAND fart") == 0, Rands())
local na = #SY.asent
local w = TickUntil(30)
local e = SY.emotes[#SY.emotes]
ok("rand: one fart on the first tick at or after the due time", Rands() == 1 and w <= 30 and RN("RAND fart n=1") == 1, Rands())
ok("rand: FART at no one (unit none), from the tick, not a click", e and e.token == "FART" and e.unit == "none" and e.tick and not e.hw)
local fs = Fs(na)
ok("rand: F like a key press (party + guild)", #fs == 2 and fs[1].ch == "PARTY" and fs[2].ch == "GUILD"
	and fs[1].m:match("^F:1:FART:" .. ME_GUID:gsub("%-", "%%-") .. ":%d+:0:%d+") ~= nil, fs[1] and fs[1].m)
ok("rand: nothing forbidden", #forbidden == forb0, forbidden[#forbidden])
-- the game's own line comes back: it plays, never counts for you
local p0 = #plays
Emote(OWN, ME, ME_GUID)
ok("rand: its line plays", #plays == p0 + 1 and LastPlay():find("who=self", 1, true) ~= nil, LastPlay())
ok("rand: counts like your own /fart (Farts, board, fart log, collection)", Counts() ~= c0 and ns.HeardNums().own == 1
	and Counts():find(" f=1 flog=1 dex=1 ", 1, true) ~= nil, Counts() .. " / " .. c0)
ok("rand: the own-fart calls ran once each (HeardSelf, AchSeen, AchPlayed, FartLogAdd, DexAdd)", spy.HeardSelf == 1
	and spy.AchSeen == 1 and spy.AchPlayed == 1 and spy.FartLogAdd == 1 and spy.DexAdd == 1)
ok("rand: echo line: tgt=0 had=0", RN("RAND echo tgt=0 had=0") == 1, RLast("RAND echo"))
-- a manual /fart still counts
now = now + 5
Press()
ok("rand: a manual /fart counts", ns.HeardNums().own == 2 and spy.HeardSelf == 2 and spy.FartLogAdd == 2, Counts())
-- max one per wait: the next one 45-75 min after the last own fart (the press just now)
w = TickUntil(4800)
ok("rand: next one 45-75 min later (the press reset the wait)", w >= 2700 and w <= 4515 and Rands() == 2, w)
Emote(OWN, ME, ME_GUID)
ok("rand: second echo taken too", RN("RAND echo") == 2 and ns.HeardNums().own == 3)
Slash("random status")
local say = prints[#prints]
ok("rand: status = on + minutes left (45-75)", say:find("random on · %d+ min") ~= nil
	and tonumber(say:match("(%d+) min")) >= 45 and tonumber(say:match("(%d+) min")) <= 75, say)
ev.scripts.OnEvent(ev, "PLAYER_LOGOUT")
ok("rand: SUM rfart=2", RLast(" SYNC SUM "):find(" rfart=2 rsec=0 classic=0$") ~= nil, RLast(" SYNC SUM "))

-- a manual /fart before the due time: a new wait from the press
Boot()
d = Due()
Tick(d - 30)
Press()
Tick(60)
ok("rand: a manual /fart moves the wait (no fart at the old due time)", Rands() == 0)
w = TickUntil(4800)
ok("rand: then 45-75 min after the press", w + 60 >= 2700 and w + 60 <= 4530 and Rands() == 1, w)
-- someone else's /fart: never moves your wait, never taken as yours
Boot()
d = Due()
Tick(d - 30)
Emote("Bob farts loudly.", "Bob", BOB)
Tick(60)
ok("rand: another player's /fart does not move the wait", Rands() == 1 and RN("RAND echo") == 0, Rands())

-- the guards: each one skips (logged once), the first clear tick fires
local function Guard2(name, set, clear, why)
	Boot()
	set()
	Tick(4800)
	local skipped = Rands() == 0
	local once = RN("RAND skip why=" .. why) == 1
	clear()
	Tick(15)
	ok("rand guard " .. name .. ": skips, logged once, fires when clear", skipped and once and Rands() == 1,
		("%s %s %d %s"):format(tostring(skipped), tostring(once), Rands(), RLast("RAND skip")))
end
Guard2("campfire", function() SetAura(CAMP, true) end, function() SetAura(CAMP, false) end, "camp")
Guard2("dead", function() st.dead = true end, function() st.dead = false end, "dead")
Guard2("feign death", function() st.fd = true end, function() st.fd = false end, "dead")
Guard2("afk", function() st.afk = true end, function() st.afk = false end, "afk")
Guard2("stealth", function() st.stealth = true end, function() st.stealth = false end, "stealth")
Guard2("casting", function() st.cast = true end, function() st.cast = false end, "cast")
Guard2("channeling", function() st.chan = true end, function() st.chan = false end, "cast")
Guard2("InCinematic", function() st.incine = true end, function() st.incine = false end, "cine")
Guard2("cinematic scene", function() st.scene = true end, function() st.scene = false end, "cine")
for _, pair in ipairs({ { "CINEMATIC_START", "CINEMATIC_STOP" }, { "PLAY_MOVIE", "STOP_MOVIE" },
	{ "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED" } }) do
	Guard2(pair[1], function() ev.scripts.OnEvent(ev, pair[1]) end, function() ev.scripts.OnEvent(ev, pair[2]) end, "cine")
end
Guard2("Sound Off", function() Slash("off") end, function() Slash("on") end, "off")
Guard2("a secret answer = yes (afk)", function() issecretvalue = function(v) return v == "SECRET" end st.afk = "SECRET" end,
	function() st.afk = false issecretvalue = nil end, "afk")
-- a change of reason logs again; the same reason does not
Boot()
st.afk = true
Tick(4800)
st.dead = true
Tick(60)
st.dead = false
Tick(60)
ok("rand: one line per reason change", RN("RAND skip why=afk") == 2 and RN("RAND skip why=dead") == 1 and Rands() == 0,
	RN("RAND skip why=afk") .. " " .. RN("RAND skip why=dead"))
st.afk = false
-- the login guard (a 0 s wait in this test only)
Boot(nil, function(n) n.RAND.min, n.RAND.span = 0, 0 end)
Tick(45)
ok("rand: never in the first 60 s after login", Rands() == 0 and RN("RAND skip why=login") == 1)
Tick(15)
ok("rand: at 60 s it may", Rands() == 1)
-- each wait is a new random draw (not one fixed number)
Boot()
local dues, nd, inRange = {}, 0, true
for _ = 1, 6 do
	Slash("random off")
	Slash("random on")
	local x = Due()
	if not (x and x >= 2700 and x <= 4500) then inRange = false end
	if x and not dues[x] then dues[x], nd = true, nd + 1 end
end
ok("rand: 6 waits: 2+ different values, all 45-75 min", nd >= 2 and inRange, nd)

-- the off switch: /wind random off|on|status and the Options checkbox
Boot()
Slash("random off")
ok("rand: /wind random off", SpokenWindDB.random == false and prints[#prints]:find("random off$") ~= nil
	and RN("RAND skip why=off") == 1 and LogHas("OPT random=false by=slash"), prints[#prints])
Tick(9000)
ok("rand: off = no random farts at all", Rands() == 0)
Slash("random on")
d = Due()
ok("rand: /wind random on = a new wait from now", SpokenWindDB.random == true and RN("RAND on") == 2 and d >= 2700 and d <= 4500
	and prints[#prints]:find("random on · %d+ min") ~= nil, prints[#prints])
Slash("random")
ok("rand: /wind random = status", prints[#prints]:find("random on · ") ~= nil, prints[#prints])
Slash("random maybe")
ok("rand: a bad word = the command list", prints[#prints]:find("random on|off|status", 1, true) ~= nil, prints[#prints])
local s = reg.byVar["SpokenWind_random"]
ok("rand: Options toggle Random farts", SY.Opt().opt.random ~= nil and ns.DEFAULTS.random == true)
s:SetValue(false)
ok("rand: checkbox off", SpokenWindDB.random == false and LogHas("OPT random=false by=panel") and RN("RAND skip why=off") == 2)
Tick(9000)
ok("rand: checkbox off = none", Rands() == 0)
s:SetValue(true)
ok("rand: checkbox on", SpokenWindDB.random == true and RN("RAND on") == 3)
Slash("random off")
Slash("reset")
ok("rand: reset = on again", SpokenWindDB.random == true and RN("RAND on") == 4)
ok("rand: the note by the toggle", SY.Tx(SY.Opt().opt.randomN) == "1/h \194\183 on wake", SY.Tx(SY.Opt().opt.randomN))
-- saved off: no wait at login
Boot({ random = false })
ok("rand: saved off: no wait, one off line", RN("RAND on") == 0 and RN("RAND skip why=off") == 1
	and LogHas(" rnd=0 tgt=0 aur=1 rev=12 "), LastLog())
Tick(9000)
ok("rand: saved off: none", Rands() == 0)
-- no options page (an old client): /wind random still works
Boot(nil, nil, "old")
ok("rand: no page: no page controls", ns.OptRefs().opt == nil)
Slash("random off")
ok("rand: no page: /wind random off", SpokenWindDB.random == false and RN("RAND skip why=off") == 1
	and LogHas("OPT random=false by=slash"), prints[#prints])
Tick(9000)
ok("rand: no page: off = none", Rands() == 0)
Slash("random on")
ok("rand: no page: /wind random on = a new wait", SpokenWindDB.random == true and RN("RAND on") == 2)

-- at no one: a target is never the emote's unit; an echo that names the target = no fart while one is targeted
Boot()
st.tgt = "Bob"
TickUntil(4800)
e = SY.emotes[#SY.emotes]
ok("rand: with a target: still unit none", Rands() == 1 and e.unit == "none")
Emote(OWN, ME, ME_GUID)
ok("rand: echo at no one: tgt=0 had=1, nothing saved", RN("RAND echo tgt=0 had=1") == 1 and SpokenWindDB.randTgt == nil)
w = TickUntil(4800)
Emote(AT_BOB, ME, ME_GUID)   -- this client put it at the target after all
ok("rand: echo named the target: tgt=1, saved", RN("RAND echo tgt=1 had=1") == 1 and SpokenWindDB.randTgt == true)
ok("rand: the echo line has no name", not RLast("RAND echo"):find("Bob", 1, true))
Tick(9000)
ok("rand: then no fart while a target exists", Rands() == 2 and RN("RAND skip why=target") == 1)
st.tgt = nil
Tick(15)
ok("rand: no target = it fires", Rands() == 3)
local saved = SpokenWindDB
Boot(saved)
ok("rand: tgt=1 kept over a reload (BOOT)", LogHas(" rnd=1 tgt=1 aur=1 rev=12 ") and SpokenWindDB.randTgt == true, LastLog())
saved.randTgt = "yes"
Boot(saved)
ok("rand: a bad randTgt is dropped", SpokenWindDB.randTgt == nil)

-- no hook ran (the line alone): a line within 3 s of the random fart is it, a later one is yours
Boot()
SY.hooks.DoEmote = nil
TickUntil(4800)
ok("rand: no hook: fired", Rands() == 1)
now = now + 1
Emote(OWN, ME, ME_GUID)
ok("rand: no hook: a line within 3 s = the random fart (counted, echo)", ns.HeardNums().own == 1 and RN("RAND echo") == 1)
now = now + 1
Emote(OWN, ME, ME_GUID)
ok("rand: no hook: the next line = yours", ns.HeardNums().own == 2 and RN("RAND echo") == 1)
TickUntil(4800)
now = now + 4
Emote(OWN, ME, ME_GUID)
ok("rand: no hook: a line 4 s later = yours", ns.HeardNums().own == 3 and RN("RAND echo") == 1)
-- no sync record (Sync broke): the line within 3 s is the random one: it plays and counts
Boot()
ns.SyncHeard = nil
TickUntil(4800)
local c1, p1 = Counts(), #plays
Emote(OWN, ME, ME_GUID)
ok("rand: no sync: plays and counts", #plays == p1 + 1 and Counts() ~= c1 and RN("RAND echo") == 1
	and spy.FartLogAdd == 1 and spy.DexAdd == 1 and spy.AchPlayed == 1 and spy.AchSeen == 1 and spy.HeardSelf == 1,
	Counts() .. " / " .. c1)

-- replies to a random fart count like the ones to a manual fart
Boot()
TickUntil(4800)
local m = LastF()
local mRand = m
local n = tonumber(m:match("^F:1:%u+:[%w%-]+:%d+:%d+:(%d+)"))
ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", ("H:1:%s:%d:%s"):format(ME_GUID, n, BOB), "PARTY", "Bob")
local nums = ns.HeardNums()
ok("rand: a reply to it counts (Heard totals)", RN("HEARD got from=") == 1 and nums.heard == 1 and nums.people == 1 and nums.best == 1,
	("%d %d %d"):format(RN("HEARD got from="), nums.heard, nums.people))
now = now + 10
Press()
m = LastF()
n = tonumber(m:match("^F:1:%u+:[%w%-]+:%d+:%d+:(%d+)"))
ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", ("H:1:%s:%d:%s"):format(ME_GUID, n, BOB), "PARTY", "Bob")
nums = ns.HeardNums()
ok("rand: a reply to a manual fart counts", nums.heard == 2 and nums.people == 1 and nums.best == 1, nums.heard)
-- test mode (dev addon): a late F, sent by a timer; a reply to it counts too
Boot()
local realM = ns.TestOwnMode
ns.TestOwnMode = function() return "late", 0.4 end
local naL = #SY.asent
TickUntil(4800)
ns.TestOwnMode = realM
Emote(OWN, ME, ME_GUID)
local lateNow = #Fs(naL) == 0   -- no F yet (the slow S timer may send)
now = now + 0.4
hw = true   -- the test-mode timer of this emote (as for a key press)
local ti = 1
while ti <= #SY.timers do
	local t = SY.timers[ti]
	if t.at <= now + 1e-9 then table.remove(SY.timers, ti) t.fn() else ti = ti + 1 end
end
hw = false
m = LastF()
n = m and tonumber(m:match("^F:1:%u+:[%w%-]+:%d+:%d+:(%d+)"))
ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", ("H:1:%s:%d:%s"):format(ME_GUID, n or 0, BOB), "PARTY", "Bob")
nums = ns.HeardNums()
ok("rand: test mode late F: sent by the timer, a reply counts", lateNow and n ~= nil and RN("HEARD got from=") == 1
	and nums.heard == 1 and nums.own == 1, ("%s %s %d %d"):format(tostring(lateNow), tostring(n), RN("HEARD got from="), nums.heard))

-- others: the random fart's F is a normal F, same fields as a key press (old clients and 0.6.6 count it heard as usual)
ok("rand: its F = a key press F (same fields)", select(2, mRand:gsub(":", "")) == select(2, m:gsub(":", ""))
	and mRand:match("^F:1:FART:[%w%-]+:%d+:0:%d+") ~= nil, mRand .. " / " .. m)

-- Own /fart off: the random one does not play here, still counts
Boot()
Slash("self off")
TickUntil(4800)
p0 = #plays
Emote(OWN, ME, ME_GUID)
ok("rand: Own /fart off: fired, not played here, counted", Rands() == 1 and #plays == p0 and ns.HeardNums().own == 1
	and LogHas("SKIP self"))

-- the client blocks it: stop for the session, never a second way
Boot()
SY.emoteErr = true
Tick(4800)
SY.emoteErr = nil
ok("rand: an error = blocked, logged", RN("RAND skip why=block") == 1 and RN("ERR rand") == 1 and RN("RAND fart") == 0)
local tries = #SY.emotes
Tick(9000)
ok("rand: blocked = no more tries this session", #SY.emotes == tries)
Slash("random status")
ok("rand: status = blocked", prints[#prints]:find("random blocked$") ~= nil, prints[#prints])
Slash("random on")
Tick(9000)
ok("rand: blocked: on again does not restart it", #SY.emotes == tries)
Boot()
ok("rand: a new login = a new try", RN("RAND on") == 1)
SY.emoteHook = function() ev.scripts.OnEvent(ev, "ADDON_ACTION_BLOCKED", "Spoken_Wind", "DoEmote()") end
TickUntil(4800)
SY.emoteHook = nil
ok("rand: block event during the call = stop, not counted", RN("RAND skip why=block") == 1 and RN("RAND fart") == 0)
Emote(OWN, ME, ME_GUID)   -- a line that still comes after the block: the random one (no new wait)
ok("rand: block: a line that still comes = the random one (echo)", ns.HeardNums().own == 1 and RN("RAND echo") == 1, Counts())
Tick(9000)
ok("rand: block: no more tries", Rands() == 1, Rands())
Boot()
TickUntil(4800)
now = now + 2
ev.scripts.OnEvent(ev, "ADDON_ACTION_FORBIDDEN", "Spoken_Wind", "UNKNOWN()")
ok("rand: forbidden event 2 s after = stop", RN("RAND fart n=1") == 1 and RN("RAND skip why=block") == 1)
Boot()
ev.scripts.OnEvent(ev, "ADDON_ACTION_BLOCKED", "OtherAddon", "DoEmote()")
ev.scripts.OnEvent(ev, "ADDON_ACTION_BLOCKED", "Spoken_Wind", "CastSpellByName()")
ok("rand: another addon's block or another call long after = no stop", RN("RAND skip why=block") == 0)
ev.scripts.OnEvent(ev, "ADDON_ACTION_BLOCKED", "Spoken_Wind", "DoEmote()")
ok("rand: our DoEmote blocked any time = stop", RN("RAND skip why=block") == 1)
-- an error inside the check (a broken game function): stop, never a Lua error popup every 15 s
Boot()
UnitIsAFK = function() error("afk boom") end
Tick(4800)
ok("rand: an error in the tick = stop + ERR, no throw", RN("RAND skip why=err") == 1 and RN("ERR rand") == 1 and Rands() == 0)
Stubs()
-- no DoEmote / no NewTicker (an old client): never starts
Boot(nil, function() DoEmote = nil end)
ok("rand: no DoEmote = noapi, no ticker", RN("RAND skip why=noapi") == 1 and #SY.tickers == 1, #SY.tickers)
local keepT = SY.noTicker
SY.noTicker = true
Boot()
SY.noTicker = keepT
ok("rand: no NewTicker = noapi", RN("RAND skip why=noapi") == 1 and #SY.tickers == 0)

-- ---------------------------------------------- 0.6.6 rules 2: bag, campfire, logout, wake-up, fart attack, probe
do   -- the numbers, the events
	Boot()
	local RR = ns.RAND
	ok("rand: wake-up 5-50 s, try again each 1 s until 60 s", RR.wakeMin == 5 and RR.wakeMax == 50 and RR.retry == 1
		and RR.wakeEnd == 60)
	ok("rand: attack 5 %, 3-6 farts 2-5 s apart, 3-8 s after the rumble, sigh 2-4 s after", RR.atkP == 5 and RR.atkMin == 3
		and RR.atkMax == 6 and RR.gapMin == 2 and RR.gapMax == 5 and RR.leadMin == 3 and RR.leadMax == 8
		and RR.sighMin == 2 and RR.sighMax == 4)
	ok("rand: bag 429960, campfire 1229739 + 10 s, logout 30 s, probe 30", RR.bag == 429960 and RR.camp == 1229739
		and RR.campGrace == 10 and RR.logoutMax == 30 and RR.probeMax == 30)
	ok("rand: UNIT_AURA for the player only + the logout events", ev.units and ev.units.UNIT_AURA == "player"
		and ev.events.PLAYER_CAMPING and ev.events.PLAYER_QUITING and ev.events.LOGOUT_CANCEL and ev.events.UNIT_AURA)
	-- the rumble lines: the 9 races + a plain one; short, gender neutral, no "you"
	local races, bad, nR = { "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Scourge", "Tauren", "Troll", "Skyborne" }, nil, 0
	local seen = {}
	for _, r in ipairs(races) do
		local t = RR.rumble[r]
		if type(t) ~= "string" or seen[t] or #t > 120 or not t:find("^feels a sudden rumble in ") or not t:find(" their ")
			or t:lower():find("you") or t:find(" his ") or t:find(" her ") then bad = r end
		if t then seen[t], nR = true, nR + 1 end
	end
	ok("rand: 9 race rumble lines: own text each, short, 'their', no 'you'", nR == 9 and bad == nil, bad)
	ok("rand: the plain rumble line", RR.rumble.other == "feels a sudden rumble in their tummy.")
	local nk = 0
	for _ in pairs(RR.rumble) do nk = nk + 1 end
	ok("rand: no other rumble lines", nk == 10, nk)
end

do   -- hourly: combat is OK now
	Boot()
	combat, st.ucombat = true, true
	TickUntil(4800)
	ok("rand: combat is OK (the hourly fart fires in combat)", Rands() == 1 and RN("RAND skip") == 0, RLast("RAND skip"))
	combat = false
end

do   -- hourly: the logout timer ends after 30 s even with no cancel
	Boot(nil, function(n) n.RAND.min, n.RAND.span = 100, 0 end)
	RunT(90)
	ev.scripts.OnEvent(ev, "PLAYER_CAMPING")
	RunT(15)
	local sk = Farts() == 0 and RN("RAND skip why=logout") == 1
	RunT(14)
	local sk2 = Farts() == 0
	RunT(1)
	ok("rand: the logout timer: skip for 30 s, then it may", sk and sk2 and Farts() == 1, Farts())
	for _, e in ipairs({ "PLAYER_CAMPING", "PLAYER_QUITING" }) do
		Boot(nil, function(n) n.RAND.min, n.RAND.span = 100, 0 end)
		RunT(95)
		ev.scripts.OnEvent(ev, e)
		RunT(10)
		sk = Farts() == 0 and RN("RAND skip why=logout") == 1
		ev.scripts.OnEvent(ev, "LOGOUT_CANCEL")
		RunT(15)
		ok("rand: " .. e .. ": skip; LOGOUT_CANCEL = it may", sk and Farts() == 1, Farts())
	end
end

do   -- hourly: in the sleeping bag
	Boot()
	Bag(true)
	Tick(4800)
	ok("rand: in the bag: no hourly fart, logged once", Rands() == 0 and RN("RAND skip why=bag") == 1, RLast("RAND skip"))
end

do   -- hourly: the campfire, its 10 s grace (the gap between two minutes)
	local function Camp(gone)   -- the aura goes at tphase 'gone'; the ticks at 120 and 135
		Boot(nil, function(n) n.RAND.min, n.RAND.span = 100, 0 end)
		RunT(60)
		SetAura(CAMP, true)
		RunT(45)   -- tick at 105: due, at the fire
		local cs = Farts() == 0 and RN("RAND skip why=camp") == 1
		RunT(gone - 105)
		SetAura(CAMP, false)
		RunT(120 - gone)
		return cs, Farts()
	end
	local cs, f1 = Camp(115)   -- the tick at 120: 5 s after
	RunT(15)
	ok("rand: campfire: skip, still 5 s after its aura goes, then the fart", cs and f1 == 0 and Farts() == 1, f1)
	cs, f1 = Camp(110)   -- the tick at 120: 10 s after = may
	ok("rand: campfire: 10 s after its aura goes it may", cs and f1 == 1, f1)
	cs, f1 = Camp(111)   -- the tick at 120: 9 s after = not yet
	ok("rand: campfire: 9 s after = not yet", cs and f1 == 0, f1)
	-- no aura event: the 15 s tick sees it
	Boot(nil, function(n) n.RAND.min, n.RAND.span = 100, 0 end)
	RunT(60)
	st.aura = { [CAMP] = true }
	RunT(45)
	cs = Farts() == 0 and RN("RAND skip why=camp") == 1
	st.aura = {}
	RunT(15)   -- the tick at 120 sees it gone: the 10 s start there
	f1 = Farts()
	RunT(15)
	ok("rand: campfire seen by the tick, no event", cs and f1 == 0 and Farts() == 1, f1)
end

-- one wake-up: in the bag, before(), out of the bag, at(), then 10 s (rig: due 10 s, no attack)
local function Wake1(before, at, rig)
	Boot()
	RunT(60)
	st.rig = rig or { ["1-100"] = 100, ["5-50"] = 10 }
	Bag(true)
	if before then before() end
	Bag(false)
	if at then at() end
	RunT(10)
end

do   -- the wake-up fart
	Boot()
	RunT(60)
	st.rig = { ["1-100"] = 100, ["5-50"] = 10 }
	Bag(true)
	RunT(30)
	ok("rand wake: in the bag: nothing", Farts() == 0 and RN("RAND wake") == 0)
	Bag(false)
	ok("rand wake: out of the bag: due 10 s", RN("RAND wake due=10") == 1, RLast("RAND wake"))
	RunT(9)
	ok("rand wake: nothing before the due time", Farts() == 0)
	RunT(1)
	local ew = SY.emotes[#SY.emotes]
	ok("rand wake: the wake-up fart: FART at none, from a timer, not a click", Farts() == 1 and ew.token == "FART"
		and ew.unit == "none" and ew.tick and not ew.hw and RN("RAND wake fart n=1") == 1 and RN("RAND fart n=") == 0)
	ok("rand wake: it sends its F (party + guild)", #Fs(0) == 2, #Fs(0))
	Emote(OWN, ME, ME_GUID)
	ok("rand wake: it counts like yours", ns.HeardNums().own == 1 and RN("RAND echo") == 1 and spy.FartLogAdd == 1)
	Slash("random")
	local mins = tonumber(prints[#prints]:match("(%d+) min"))
	ok("rand wake: a new 45-75 min wait from the wake-up fart", mins and mins >= 45 and mins <= 75, prints[#prints])
	RunT(300)
	ok("rand wake: one fart per wake-up", Farts() == 1, Farts())
	-- the wake-up time: a random 5-50 s
	Boot()
	RunT(60)
	local dues, nd, inR = {}, 0, true
	for _ = 1, 8 do
		Bag(true) Bag(false)
		local x = tonumber(RLast("RAND wake due="):match("due=(%d+)"))
		if not (x and x >= 5 and x <= 50) then inR = false end
		if x and not dues[x] then dues[x], nd = true, nd + 1 end
	end
	ok("rand wake: 8 wake-ups: 2+ different times, all 5-50 s", inR and nd >= 2, nd)
end

do   -- the wake-up: when you leave the bag
	for _, c in ipairs({
		{ "dead", function() st.dead = true end },
		{ "feign death", function() st.fd = true end, "dead" },
		{ "logout", function() ev.scripts.OnEvent(ev, "PLAYER_CAMPING") end },
		{ "quit", function() ev.scripts.OnEvent(ev, "PLAYER_QUITING") end, "logout" },
		{ "cine", function() ev.scripts.OnEvent(ev, "LOADING_SCREEN_ENABLED") end },
		{ "Sound Off", function() Slash("off") end, "off" },
	}) do
		Wake1(c[2])
		RunT(60)
		ok("rand wake: leave the bag " .. c[1] .. " = no wake-up, logged", RN("RAND wake due") == 0 and Farts() == 0
			and RN("RAND skip why=" .. (c[3] or c[1])) == 1, RLast("RAND skip"))
	end
	Wake1(function() Slash("random off") end)
	RunT(60)
	ok("rand wake: leave the bag with random off = no wake-up", RN("RAND wake due") == 0 and Farts() == 0
		and RN("RAND skip why=off") == 2, RN("RAND skip why=off"))
	-- the logout timer cancelled = the wake-up comes
	Wake1(function() ev.scripts.OnEvent(ev, "PLAYER_CAMPING") ev.scripts.OnEvent(ev, "LOGOUT_CANCEL") end)
	ok("rand wake: logout cancelled = the wake-up fart", Farts() == 1)
	-- another unit's aura event: not you
	Boot()
	RunT(60)
	Bag(true)
	st.aura[BAG] = nil
	ev.scripts.OnEvent(ev, "UNIT_AURA", "target", {})
	ok("rand wake: another unit's aura event = nothing", RN("RAND wake due") == 0)
	RunT(15)   -- the next tick sees the bag gone
	ok("rand wake: the tick sees the bag gone", RN("RAND wake due") == 1)
	-- after a block: no wake-up
	Boot()
	SY.emoteErr = true
	TickUntil(4800)   -- the hourly fart: blocked
	SY.emoteErr = nil
	local nE = #SY.emotes
	st.rig = { ["1-100"] = 100, ["5-50"] = 10 }
	Bag(true) Bag(false)
	RunT(60)
	ok("rand wake: blocked before = no wake-up", RN("RAND skip why=block") == 1 and RN("RAND wake due") == 0
		and #SY.emotes == nE)
end

do   -- the wake-up: a hard reason before the due time ends it
	for _, c in ipairs({
		{ "dead", function() st.dead = true end },
		{ "logout", function() ev.scripts.OnEvent(ev, "PLAYER_CAMPING") end },
		{ "cine", function() ev.scripts.OnEvent(ev, "CINEMATIC_START") end },
		{ "Sound Off", function() Slash("off") end, "off" },
		{ "bag", function() Bag(true) end },
	}) do
		Wake1(nil, c[2])
		RunT(60)
		ok("rand wake: " .. c[1] .. " before the due time = no fart, logged", RN("RAND wake due=10") == 1 and Farts() == 0
			and RN("RAND skip why=" .. (c[3] or c[1])) == 1, RLast("RAND skip"))
	end
	-- back in the bag and out again: a new wake-up, one fart
	Wake1(nil, function() Bag(true) Bag(false) end)
	RunT(60)
	ok("rand wake: back in and out again = a new wake-up, one fart", RN("RAND wake due=10") == 2 and Farts() == 1, Farts())
end

do   -- the wake-up: a soft reason = try again each 1 s, until 60 s after the wake-up
	for _, c in ipairs({
		{ "afk", function(v) st.afk = v end },
		{ "stealth", function(v) st.stealth = v end },
		{ "cast", function(v) st.cast = v end },
		{ "target", function(v) SpokenWindDB.randTgt = v or nil st.tgt = v and "Bob" or nil end },
	}) do
		Wake1(nil, function() c[2](true) end)
		local waited = Farts() == 0 and RN("RAND wake wait why=" .. c[1]) == 1
		RunT(5)
		c[2](false)
		RunT(1)
		ok("rand wake: " .. c[1] .. " at the due time = wait (logged once), then the fart", waited and Farts() == 1
			and RN("RAND wake wait why=" .. c[1]) == 1, Farts())
		Wake1(nil, function() c[2](true) end)
		RunT(49)
		local still = Farts() == 0 and RN("RAND skip why=" .. c[1]) == 0
		RunT(1)
		c[2](false)
		RunT(10)
		ok("rand wake: " .. c[1] .. " until 60 s after = dropped, logged", still and Farts() == 0
			and RN("RAND skip why=" .. c[1]) == 1, RLast("RAND skip"))
	end
	-- a change of reason logs again
	Wake1(nil, function() st.afk = true end)
	st.afk, st.cast = false, true
	RunT(2)
	st.cast = false
	RunT(1)
	ok("rand wake: a new reason = a new wait line", RN("RAND wake wait why=afk") == 1 and RN("RAND wake wait why=cast") == 1
		and Farts() == 1)
	-- the login 60 s: wait, then the fart
	Boot()
	st.rig = { ["1-100"] = 100, ["5-50"] = 5 }
	RunT(10)
	Bag(true) Bag(false)
	RunT(5)
	local wl = Farts() == 0 and RN("RAND wake wait why=login") == 1
	RunT(44)
	local wl2 = Farts() == 0
	RunT(1)
	ok("rand wake: the login 60 s = wait, then the fart", wl and wl2 and Farts() == 1, Farts())
	-- the campfire does not stop it; combat is OK
	Wake1(function() SetAura(CAMP, true) combat, st.ucombat = true, true end)
	ok("rand wake: at a campfire, in combat = still the wake-up fart", Farts() == 1, RLast("RAND skip"))
	combat = false
	-- an error in a step: stop + ERR, no throw
	Wake1(nil, function() UnitIsAFK = function() error("afk boom") end end)
	ok("rand wake: an error in a step = stop + ERR", RN("RAND skip why=err") == 1 and RN("ERR rand") == 1 and Farts() == 0)
	Stubs()
	-- the fart blocked
	Wake1(nil, function() SY.emoteErr = true end)
	SY.emoteErr = nil
	ok("rand wake: the fart blocked = stop", RN("RAND skip why=block") == 1 and RN("RAND wake fart") == 0)
end

do   -- the hourly waits while a wake-up runs
	Boot(nil, function(n) n.RAND.min, n.RAND.span = 100, 0 end)
	st.rig = { ["1-100"] = 100, ["5-50"] = 50 }
	RunT(70)
	Bag(true) Bag(false)
	RunT(49)
	ok("rand: the hourly waits while a wake-up runs", Farts() == 0 and RN("RAND skip why=wake") == 1, RLast("RAND skip"))
	RunT(1)
	ok("rand: then only the wake-up fart (a new hourly wait)", Farts() == 1 and RN("RAND wake fart") == 1)
	RunT(99)
	ok("rand: the next hourly 100 s after the wake-up fart", Farts() == 1)
	RunT(15)
	ok("rand: ... and then it fires", Farts() == 2, Farts())
end

do   -- hidden aura answers keep the last state
	Boot()
	RunT(60)
	st.rig = { ["1-100"] = 100, ["5-50"] = 10 }
	Bag(true)
	st.hide = true
	Bag(false)
	RunT(30)
	local h1 = Farts() == 0 and RN("RAND wake due") == 0
	st.hide = false
	SetAura(CAMP, false)
	RunT(10)
	ok("rand: auras hidden (C_Secrets) = keep the last state; shown again = the wake-up", h1 and RN("RAND wake due=10") == 1
		and Farts() == 1)
	Boot()
	RunT(60)
	st.rig = { ["1-100"] = 100, ["5-50"] = 10 }
	issecretvalue = function(v) return v == "SECRET" end
	Bag(true)
	SetAura(BAG, "SECRET")
	RunT(30)
	h1 = Farts() == 0 and RN("RAND wake due") == 0
	Bag(false)
	RunT(10)
	issecretvalue = nil
	ok("rand: a secret aura answer = keep the last state", h1 and Farts() == 1)
	-- an error from the aura call = no aura (never a stop)
	Boot()
	RunT(60)
	C_UnitAuras.GetPlayerAuraBySpellID = function() error("aura boom") end
	RunT(15)
	ok("rand: an aura call error = no aura, no stop", RN("RAND skip why=err") == 0 and RN("ERR rand") == 0)
	-- no aura API at all: BOOT aur=0, no bag or campfire rules
	Boot(nil, function() C_UnitAuras = nil end)
	ok("rand: no aura API at login: BOOT aur=0", LogHas(" aur=0 rev=12 "), LastLog())
	C_UnitAuras = nil
	st.aura = { [BAG] = true, [CAMP] = true }
	TickUntil(4800)
	ok("rand: no aura API: the hourly fart as before", Rands() == 1)
	-- the old global GetPlayerAuraBySpellID
	Boot()
	C_UnitAuras = nil
	GetPlayerAuraBySpellID = function(id) return st.aura and st.aura[id] and {} or nil end
	RunT(60)
	st.rig = { ["1-100"] = 100, ["5-50"] = 10 }
	Bag(true) Bag(false)
	RunT(10)
	ok("rand: the old GetPlayerAuraBySpellID works too", Farts() == 1)
	GetPlayerAuraBySpellID = nil
end

local ATK = { ["1-100"] = 5, ["5-50"] = 5, ["3-6"] = 4, ["3-8"] = 3, ["2-5"] = 2, ["2-4"] = 2 }
local function Attack(rig, before)
	Boot()
	RunT(60)
	st.rig = rig or ATK
	if before then before() end
	Bag(true) Bag(false)
end

do   -- the fart attack: rumble, 4 farts 2 s apart, sigh
	Attack()
	local na0, ns0 = #SY.asent, #sent
	RunT(4)
	ok("rand attack: nothing before the wake-up time", Farts() == 0 and #sent == ns0)
	RunT(1)
	local rl = sent[#sent]
	ok("rand attack: the 5 % roll: one rumble line, EMOTE, from a timer, the race text", #sent == ns0 + 1
		and rl.chan == "EMOTE" and rl.tick and rl.text == ns.RAND.rumble.Dwarf and RN("RAND attack n=4") == 1
		and RN("RAND rumble race=Dwarf") == 1 and Farts() == 0, rl and rl.text)
	RunT(2)
	ok("rand attack: no fart in the first 2 s after the rumble", Farts() == 0)
	RunT(1)
	ok("rand attack: fart 1, 3 s after the rumble", Farts() == 1)
	Emote(OWN, ME, ME_GUID)
	RunT(1)
	ok("rand attack: not 1 s later", Farts() == 1)
	RunT(1) Emote(OWN, ME, ME_GUID)
	RunT(2) Emote(OWN, ME, ME_GUID)
	RunT(2) Emote(OWN, ME, ME_GUID)
	ok("rand attack: 4 farts 2 s apart, each one counts", Farts() == 4 and RN("RAND fart n=") == 4
		and ns.HeardNums().own == 4 and RN("RAND echo") == 4, Farts())
	ok("rand attack: each fart sends its F (party + guild)", #Fs(na0) == 8, #Fs(na0))
	RunT(1)
	ok("rand attack: no sigh 1 s after the last fart", Sighs() == 0)
	RunT(1)
	local es = SY.emotes[#SY.emotes]
	ok("rand attack: the sigh 2 s after the last fart: SIGH at none, from a timer", Sighs() == 1 and es.token == "SIGH"
		and es.unit == "none" and es.tick and not es.hw and RN("RAND sigh") == 1)
	RunT(120)
	ok("rand attack: then nothing more (one rumble, one sigh)", Farts() == 4 and Sighs() == 1 and #sent == ns0 + 1)
	ok("rand attack: nothing forbidden", #forbidden == forb0, forbidden[#forbidden])
	-- 6 farts, other gaps
	Attack({ ["1-100"] = 1, ["5-50"] = 5, ["3-6"] = 6, ["3-8"] = 8, ["2-5"] = 5, ["2-4"] = 4 })
	RunT(12)
	local a1 = Farts() == 0
	RunT(1)   -- +13
	local a2 = Farts() == 1
	RunT(24)  -- +37: farts at +18 +23 +28 +33
	local a3 = Farts() == 5
	RunT(1)   -- +38
	local a4 = Farts() == 6 and Sighs() == 0
	RunT(3)
	local a5 = Sighs() == 0
	RunT(1)   -- +42
	ok("rand attack: 6 farts 5 s apart, 8 s after the rumble, sigh 4 s after", a1 and a2 and a3 and a4 and a5
		and Sighs() == 1 and RN("RAND attack n=6") == 1)
	-- the roll misses: one plain wake-up fart
	Attack({ ["1-100"] = 6, ["5-50"] = 5 })
	RunT(60)
	ok("rand attack: roll 6 of 100 = no attack, one wake-up fart", Farts() == 1 and RN("RAND attack") == 0
		and RN("RAND rumble") == 0 and Sighs() == 0)
	-- default 5 %: some of 400 wake-ups
	Boot()
	RunT(60)
	local nA = 0
	for _ = 1, 400 do
		Bag(true) Bag(false)
		RunT(60)
	end
	for _, x in ipairs(sent) do if x.chan == "EMOTE" then nA = nA + 1 end end   -- one rumble per attack (the log is capped)
	ok("rand attack: about 5 % of wake-ups (400 tries: 5-45)", nA >= 5 and nA <= 45, nA)
end

do   -- the rumble line per race
	for _, r in ipairs({ "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Scourge", "Tauren", "Troll", "Skyborne" }) do
		Attack(nil, function() st.race = r end)
		RunT(5)
		ok("rand attack: rumble " .. r, sent[#sent].text == ns.RAND.rumble[r] and RN("RAND rumble race=" .. r) == 1, sent[#sent].text)
	end
	Attack(nil, function() st.race = "Pandaren" end)
	RunT(5)
	ok("rand attack: another race = the plain line", sent[#sent].text == ns.RAND.rumble.other
		and RN("RAND rumble race=other") == 1)
	Attack(nil, function() st.race = "SECRET" issecretvalue = function(v) return v == "SECRET" end end)
	RunT(5)
	issecretvalue = nil
	ok("rand attack: a secret race = the plain line", sent[#sent].text == ns.RAND.rumble.other)
	Attack(nil, function() UnitRace = nil end)
	RunT(5)
	ok("rand attack: no UnitRace = the plain line", sent[#sent].text == ns.RAND.rumble.other)
	Attack(nil, function() C_ChatInfo.SendChatMessage = function(t, c) SY.cci = { t = t, c = c } end end)
	RunT(5)
	ok("rand attack: C_ChatInfo.SendChatMessage first when the client has it", SY.cci and SY.cci.c == "EMOTE"
		and SY.cci.t == ns.RAND.rumble.Dwarf)
	SY.cci = nil
end

do   -- the fart attack stops: no more farts, no sigh
	for _, c in ipairs({
		{ "afk", function() st.afk = true end },
		{ "dead", function() st.dead = true end },
		{ "cine", function() ev.scripts.OnEvent(ev, "PLAY_MOVIE") end },
		{ "logout", function() ev.scripts.OnEvent(ev, "PLAYER_CAMPING") end },
		{ "bag", function() Bag(true) end },
		{ "Sound Off", function() Slash("off") end, "off" },
		{ "cast", function() st.cast = true end },
		{ "stealth", function() st.stealth = true end },
	}) do
		local why = "RAND skip why=" .. (c[3] or c[1])
		Attack()
		RunT(5)
		c[2]()
		RunT(60)
		ok("rand attack: " .. c[1] .. " after the rumble = no fart, no sigh", RN("RAND rumble") == 1 and Farts() == 0
			and Sighs() == 0 and RN(why) == 1, RLast("RAND skip"))
		Attack()
		RunT(8)
		c[2]()
		RunT(60)
		ok("rand attack: " .. c[1] .. " after fart 1 = no more, no sigh", Farts() == 1 and Sighs() == 0 and RN(why) == 1)
		Attack()
		RunT(14)
		c[2]()
		RunT(60)
		ok("rand attack: " .. c[1] .. " after the last fart = no sigh", Farts() == 4 and Sighs() == 0 and RN(why) == 1)
	end
	Attack()
	RunT(5)
	Slash("random off")
	RunT(60)
	ok("rand attack: random off = no fart, no sigh", Farts() == 0 and Sighs() == 0)
end

do   -- the fart attack: blocks
	Attack()
	SY.chatErr = true
	RunT(5)
	SY.chatErr = nil
	RunT(60)
	ok("rand attack: the rumble blocked (error) = stop for the session, no fart", RN("RAND skip why=block") == 1
		and RN("ERR rand") == 1 and Farts() == 0 and Sighs() == 0 and RN("RAND rumble") == 0)
	Slash("random")
	ok("rand attack: then status blocked", prints[#prints]:find("random blocked$") ~= nil, prints[#prints])
	Bag(true) Bag(false)
	RunT(60)
	ok("rand attack: blocked = no new wake-up", RN("RAND wake due") == 1 and Farts() == 0)
	Attack()
	SY.chatHook = function() ev.scripts.OnEvent(ev, "ADDON_ACTION_BLOCKED", "Spoken_Wind", "SendChatMessage()") end
	RunT(5)
	SY.chatHook = nil
	RunT(60)
	ok("rand attack: a block event during the rumble = stop, no fart", RN("RAND skip why=block") == 1 and Farts() == 0
		and RN("RAND rumble") == 0)
	Attack()
	RunT(15)
	SY.emoteErr = true
	RunT(1)
	SY.emoteErr = nil
	ok("rand attack: the sigh blocked = stop, logged", Farts() == 4 and RN("RAND sigh") == 0 and RN("RAND skip why=block") == 1)
	Attack()
	RunT(9)
	SY.emoteErr = true
	RunT(1)
	SY.emoteErr = nil
	RunT(60)
	ok("rand attack: fart 2 blocked = stop, no more, no sigh", Farts() == 2 and RN("RAND fart n=") == 1 and Sighs() == 0
		and RN("RAND skip why=block") == 1)
	-- no chat API: no attack (noapi), random farts go on
	Attack(nil, function() SendChatMessage = nil end)
	RunT(60)
	Slash("random")
	ok("rand attack: no chat API = the attack ends (noapi), not blocked", Farts() == 0 and RN("RAND skip why=noapi") == 1
		and prints[#prints]:find("random on · ") ~= nil, prints[#prints])
end

do   -- the aura probe (log only): bag, campfire and rest auras, spell ID + name
	Boot()
	local function AuraEv(unit, info) ev.scripts.OnEvent(ev, "UNIT_AURA", unit, info) end
	AuraEv("player", { addedAuras = { { spellId = BAG, name = "Cozy Sleeping Bag", auraInstanceID = 7 },
		{ spellId = 1243, name = "Power Word: Fortitude", auraInstanceID = 8 },
		{ spellId = 5555, name = "Warm Campfire Glow", auraInstanceID = 9 } } })
	ok("rand probe: the bag ID + named auras: ID + name; others not", RN("RAND aura +429960 Cozy Sleeping Bag") == 1
		and RN("RAND aura +5555 Warm Campfire Glow") == 1 and RN("RAND aura +1243") == 0)
	AuraEv("player", { addedAuras = { { spellId = BAG, name = "Cozy Sleeping Bag", auraInstanceID = 10 } } })
	ok("rand probe: the same ID again = no line", RN("RAND aura +429960") == 1)
	AuraEv("player", { removedAuraInstanceIDs = { 7, 8 } })
	ok("rand probe: removed: its ID", RN("RAND aura -429960") == 1 and RN("RAND aura -1243") == 0)
	AuraEv("player", { removedAuraInstanceIDs = { 10, 99 } })
	ok("rand probe: removed again = no second line", RN("RAND aura -429960") == 1)
	AuraEv("target", { addedAuras = { { spellId = 429959, name = "Well Rested", auraInstanceID = 11 } } })
	ok("rand probe: another unit = nothing", RN("RAND aura +429959") == 0)
	AuraEv("player", { addedAuras = { { spellId = 429959, name = "X", auraInstanceID = 12 },
		{ spellId = 429961, name = "Y", auraInstanceID = 13 }, { spellId = CAMP, name = "Z", auraInstanceID = 14 } } })
	ok("rand probe: the 4 IDs by number", RN("RAND aura +429959 X") == 1 and RN("RAND aura +429961 Y") == 1
		and RN("RAND aura +1229739 Z") == 1)
	for i, word in ipairs({ "Camp", "fIRE", "Bag", "Sleep", "Rest", "Cozy" }) do
		AuraEv("player", { addedAuras = { { spellId = 7000 + i, name = "A " .. word .. " b", auraInstanceID = 100 + i } } })
	end
	ok("rand probe: each word: camp fire bag sleep rest cozy (any case)", RN("RAND aura +700") == 6, RN("RAND aura +700"))
	issecretvalue = function(v) return v == "SECRET" or v == 7101 end
	AuraEv("player", { addedAuras = { { spellId = 7101, name = "Rest", auraInstanceID = 200 },
		{ spellId = 7102, name = "SECRET", auraInstanceID = 201 }, { spellId = 7103, name = "Rest", auraInstanceID = "SECRET" } } })
	AuraEv("player", "SECRET")
	issecretvalue = nil
	ok("rand probe: a secret ID, name or instance = skipped", RN("RAND aura +710") == 0)
	AuraEv("player", { addedAuras = { "x", { spellId = 7200, name = string.rep("r", 60) .. "rest", auraInstanceID = 300 },
		{ spellId = 7201, auraInstanceID = 301 }, { spellId = "7202", name = "rest", auraInstanceID = 302 } } })
	ok("rand probe: name cut at 40; a bad entry skipped", RLast("RAND aura +7200"):match("RAND aura %+7200 (.*)$")
		== string.rep("r", 40) and RN("RAND aura +7201") == 0 and RN("RAND aura +7202") == 0)
	AuraEv("player", nil)
	AuraEv("player", { addedAuras = "x", removedAuraInstanceIDs = "y" })
	ok("rand probe: no info or bad lists = nothing, no error", RN("ERR rand") == 0)
	-- cap 30 per session (own cap: the RAND lines still log)
	for i = 1, 40 do AuraEv("player", { addedAuras = { { spellId = 9000 + i, name = "rest", auraInstanceID = 400 + i } } }) end
	AuraEv("player", { removedAuraInstanceIDs = { 401, 402 } })
	ok("rand probe: max 30 lines per session", RN("RAND aura +") + RN("RAND aura -") == 30, RN("RAND aura "))
	Slash("random off")
	ok("rand probe: its own cap (RAND lines still log)", RN("RAND skip why=off") == 1)
	-- random off: the probe still logs
	Boot({ random = false })
	ev.scripts.OnEvent(ev, "UNIT_AURA", "player", { addedAuras = { { spellId = BAG, name = "Bag", auraInstanceID = 1 } } })
	ok("rand probe: random off: still logs", RN("RAND aura +429960") == 1)
end

do   -- edges: login in the bag, old timers, steps read the auras, after the sigh, a secret race, the probe's
	-- own cap, aura errors, missing guard APIs, no C_Timer.After, secret aura answers
	-- in the bag at login, out before the first tick: the wake-up (waits for the login 60 s)
	Boot(nil, function() st.aura = { [BAG] = true } end)
	st.rig = { ["1-100"] = 100, ["5-50"] = 5 }
	RunT(5)
	Bag(false)
	RunT(60)
	ok("rand: in the bag at login, out at +5 s = the wake-up fart after the login 60 s", RN("RAND wake due=5") == 1
		and RN("RAND wake wait why=login") == 1 and Farts() == 1)
	-- an old wake-up's timer does nothing; back in the bag = logged at once
	Boot()
	RunT(60)
	st.rig = { ["1-100"] = 100, ["5-50"] = 20 }
	Bag(true) Bag(false)   -- due 20
	RunT(2)
	Bag(true)
	local b1 = RN("RAND skip why=bag") == 1
	st.rig["5-50"] = 40
	Bag(false)             -- due 40 (from +2)
	RunT(30)               -- +32: the old timer (+20) did nothing
	local o1 = Farts() == 0
	RunT(10)               -- +42
	ok("rand: back in the bag = logged at once", b1)
	ok("rand: an old wake-up timer does nothing", o1 and Farts() == 1 and RN("RAND wake due=20") == 1
		and RN("RAND wake due=40") == 1)
	-- each attack step reads the bag itself (an aura change with no event)
	Attack()
	RunT(8)                -- the rumble (+5), fart 1 (+8)
	st.aura[BAG] = true    -- no UNIT_AURA
	RunT(60)
	ok("rand attack: a step reads the bag itself (no event) = no more", Farts() == 1 and Sighs() == 0
		and RN("RAND skip why=bag") == 1)
	-- after the sigh: the hourly fart comes again
	Attack()
	RunT(16)
	local s1 = Sighs() == 1
	ok("rand attack: after the sigh the hourly fart comes again", s1 and TickUntil(4800) < 4800 and RN("RAND skip why=wake") == 0)
	-- a secret race token (a real race) = the plain line
	Attack(nil, function() st.race = "Orc" issecretvalue = function(v) return v == "Orc" end end)
	RunT(5)
	issecretvalue = nil
	ok("rand attack: a secret race token = the plain line", sent[#sent].text == ns.RAND.rumble.other
		and RN("RAND rumble race=other") == 1)
	-- the probe has its own cap: a full RAND log (60) still gets the probe lines
	Boot()
	for _ = 1, 40 do Slash("random off") Slash("random on") end
	ev.scripts.OnEvent(ev, "UNIT_AURA", "player", { addedAuras = { { spellId = BAG, name = "Bag", auraInstanceID = 1 } } })
	ok("rand probe: the RAND log full = the probe still logs", RN("RAND on due") + RN("RAND skip why=off") == 60
		and RN("RAND aura +429960") == 1, RN("RAND on due") + RN("RAND skip why=off"))
	-- an aura call error = no aura: the hourly fart still comes
	Boot()
	C_UnitAuras.GetPlayerAuraBySpellID = function() error("aura boom") end
	ok("rand: an aura call error: the hourly fart still comes", TickUntil(4800) < 4800)
	-- a missing guard API (an old client) = no reason
	Boot()
	InCinematic, IsInCinematicScene, UnitIsFeignDeath, IsStealthed = nil, nil, nil, nil
	ok("rand: missing guard APIs (old client) = the hourly fart comes", TickUntil(4800) < 4800)
	Stubs()
	-- no C_Timer.After (an old client) = noapi
	Boot(nil, function() C_Timer.After = nil end)
	ok("rand: no C_Timer.After = noapi", RN("RAND skip why=noapi") == 1)
	-- the probe: a secret info table; a number entry
	Boot()
	local sec = { addedAuras = { { spellId = BAG, name = "Bag", auraInstanceID = 1 } } }
	issecretvalue = function(v) return v == sec end
	ev.scripts.OnEvent(ev, "UNIT_AURA", "player", sec)
	issecretvalue = nil
	ok("rand probe: a secret info table = nothing", RN("RAND aura +") == 0)
	ev.scripts.OnEvent(ev, "UNIT_AURA", "player", { addedAuras = { 7, { spellId = CAMP, name = "Camp", auraInstanceID = 2 } } })
	ok("rand probe: a number entry = skipped, no error", RN("ERR rand") == 0 and RN("RAND aura +1229739") == 1)
	-- a secret aura answer when out of the bag = still out (no wake-up)
	Boot()
	RunT(60)
	st.rig = { ["1-100"] = 100, ["5-50"] = 5 }
	issecretvalue = function(v) return v == "SECRET" end
	SetAura(BAG, "SECRET")
	issecretvalue = nil
	Bag(false)
	RunT(60)
	ok("rand: a secret aura answer when out of the bag = still out", RN("RAND wake due") == 0 and Farts() == 0)
end

do   -- 0.7.1: hidden (secret) aura lists in UNIT_AURA (client 1.60.1: 157 x "ERR rand Random.lua:283 / :302 ...
	-- bad argument #1 to 'ipairs' (table expected, got secret)"). Fake secrets: type() = "table", ipairs refuses them.
	local SA, SR, SI = { "x" }, { 1 }, { addedAuras = {} }
	local SE = setmetatable({}, { __index = function() error("attempt to index a secret value") end })
	local realIpairs = ipairs
	ipairs = function(t, ...)
		if issecretvalue and issecretvalue(t) then error("bad argument #1 to 'ipairs' (table expected, got secret)") end
		return realIpairs(t, ...)
	end
	local function MainN(s)
		local k = 0
		for _, l in realIpairs(SpokenWindDB.log) do if l:find(s, 1, true) then k = k + 1 end end
		return k
	end
	Boot()
	RunT(60)
	st.rig = { ["1-100"] = 100, ["5-50"] = 10 }
	Bag(true)
	st.aura[BAG] = nil   -- out of the bag now, but the event data is hidden
	issecretvalue = function(v) return v == SA or v == SR or v == SI or v == SE end
	ev.scripts.OnEvent(ev, "UNIT_AURA", "player", { addedAuras = SA })              -- 0.7.0: Random.lua:283
	ev.scripts.OnEvent(ev, "UNIT_AURA", "player", { removedAuraInstanceIDs = SR })  -- 0.7.0: Random.lua:302
	for _ = 1, 20 do ev.scripts.OnEvent(ev, "UNIT_AURA", "player", { addedAuras = SA, removedAuraInstanceIDs = SR }) end
	ev.scripts.OnEvent(ev, "UNIT_AURA", "player", SI)                               -- the whole info hidden
	ok("rand 0.7.1: secret aura lists (added, removed, both, all) = no ERR, one RAND aura secret line",
		MainN("ERR") == 0 and RN("ERR") == 0 and RN("RAND aura secret") == 1, MainN("ERR") .. " " .. RN("RAND aura secret"))
	ok("rand 0.7.1: a hidden aura event = no aura check (state unknown: no wake-up, no fart)",
		RN("RAND wake due") == 0 and Farts() == 0, RLast("RAND wake"))
	ev.scripts.OnEvent(ev, "UNIT_AURA", "player", { addedAuras = { SE, { spellId = CAMP, name = "Camp", auraInstanceID = 3 } } })
	ok("rand 0.7.1: a secret entry in a shown list = skipped, the rest read, no error", MainN("ERR") == 0
		and RN("RAND aura +1229739 Camp") == 1, MainN("ERR"))
	issecretvalue = nil
	RunT(15)   -- the tick: the aura answer is shown again
	ok("rand 0.7.1: the next shown answer = the wake-up as before", RN("RAND wake due=10") == 1, RLast("RAND wake"))
	ev.scripts.OnEvent(ev, "PLAYER_LOGOUT")
	ok("rand 0.7.1: SYNC SUM rsec = the hidden events (23); SUM err=0", RLast(" SYNC SUM "):find(" rsec=23 ", 1, true) ~= nil
		and MainN(" SUM ") == 1 and MainN(" err=0 ") == 1, RLast(" SYNC SUM "))
	ipairs = realIpairs
end


do   -- the RAND lines of a wake-up + an attack with a target named Bob: no names, no GUIDs
	Attack(nil, function() st.tgt = "Bob" end)
	RunT(60)
	ev.scripts.OnEvent(ev, "UNIT_AURA", "player", { addedAuras = { { spellId = BAG, name = "Cozy Sleeping Bag",
		auraInstanceID = 1 } } })
	local leak, nRL = nil, 0
	for _, l in ipairs(SpokenWindDB.sync) do
		if l:find("RAND", 1, true) then
			nRL = nRL + 1
			if l:find(ME, 1, true) or l:find("Bob", 1, true) or l:find("Player-", 1, true) then leak = l end
		end
	end
	ok("rand attack: no names or GUIDs in the RAND lines", leak == nil and nRL >= 8, leak or nRL)
	st.tgt = nil
end

-- log: no names, no GUIDs (a random fart with a target named Bob, its line names Bob)
Boot()
st.tgt = "Bob"
TickUntil(4800)
Emote(AT_BOB, ME, ME_GUID)
st.tgt = nil
local leak, nRL = nil, 0
for _, l in ipairs(SpokenWindDB.sync) do
	if l:find("RAND", 1, true) then
		nRL = nRL + 1
		if l:find(ME, 1, true) or l:find("Bob", 1, true) or l:find("Player-", 1, true) then leak = l end
	end
end
ok("rand: no names or GUIDs in RAND lines", leak == nil and nRL >= 3, leak or nRL)
-- log: max 60 RAND lines per session
Boot()
for _ = 1, 40 do Slash("random off") Slash("random on") end
local nr = 0
for _, l in ipairs(SpokenWindDB.sync) do if l:find(" RAND ", 1, true) or l:find(" ERR rand", 1, true) then nr = nr + 1 end end
ok("rand: max 60 lines per session", nr == 60, nr)

-- source: two emote calls (FART, SIGH) at no one, one chat line kind (the rumble EMOTE), no hooks, no CVars,
-- no Blizzard tables
local src = assert(io.open(ADDON_DIR .. "/Random.lua", "rb")):read("*a"):gsub("%-%-[^\r\n]*", "")   -- code only
local _, nEmote = src:gsub("DoEmote", "")
ok("rand src: DoEmote: FART and SIGH at none only", nEmote == 3 and src:find('Call(now, DoEmote, "FART", "none")', 1, true) ~= nil
	and src:find('Call(now, DoEmote, "SIGH", "none")', 1, true) ~= nil and src:find("type(DoEmote)", 1, true) ~= nil, nEmote)
local _, nChat = src:gsub("SendChatMessage", "")
ok("rand src: one chat line: the rumble, EMOTE", nChat == 2 and src:find('Call(now, send, RUMBLE[race], "EMOTE")', 1, true) ~= nil, nChat)
local badSrc
for _, word in ipairs({ "SetCVar", "hooksecurefunc", "UISpecialFrames", "SendAddonMessage", "PerformEmote",
	"CreateFrame", "SetPropagateKeyboardInput", "SetBinding", "RunMacroText", "_G%[", "WHISPER", '"SAY"', "YELL", "CHANNEL",
	"PARTY", "GUILD", "RAID", "UnitName%(\"player\"%)", "UnitGUID" }) do
	if src:find(word) then badSrc = word end
end
ok("rand src: no other chat, no hooks, no frames, no CVars, no Blizzard tables, no own name", badSrc == nil, badSrc)
ok("rand: nothing forbidden in the whole block", #forbidden == forb0, forbidden[#forbidden])

UnitIsAFK, UnitIsDeadOrGhost, UnitIsFeignDeath, UnitAffectingCombat, IsStealthed = nil, nil, nil, nil, nil
UnitCastingInfo, UnitChannelInfo, InCinematic, IsInCinematicScene, UnitExists = nil, nil, nil, nil, nil
UnitRace, C_UnitAuras, C_Secrets, GetPlayerAuraBySpellID = nil, nil, nil, nil
math.random = realRandom
ME, ME_GUID = ME0, MEG0
end)()

;(function()   -- 0.7.0 helpers for the 0.7.0 blocks (in SY: the main chunk is near 200 locals)
local V = { R = {} }
SY.V7 = V
-- the game's GUID answer: V.R[guid] = { race token, sex } or "boom" (an error)
function V.Info(g)
	local r = V.R[g]
	if r == "boom" then error("info boom") end
	if r then return "Warrior", "WARRIOR", "Race", r[1], r[2], "Name", "" end
end
function V.SyncHas(s)
	local k = 0
	for _, l in ipairs(SpokenWindDB.sync or {}) do if l:find(s, 1, true) then k = k + 1 end end
	return k
end
function V.NoErr()
	for _, t in ipairs({ SpokenWindDB.log or {}, SpokenWindDB.sync or {} }) do
		for _, l in ipairs(t) do if l:find("ERR", 1, true) then return false, l end end
	end
	return true
end
function V.Run()
	local i = 1
	while i <= #SY.timers do
		local t = SY.timers[i]
		if t.at <= now + 1e-9 then table.remove(SY.timers, i) t.fn() else i = i + 1 end
	end
end
function V.Wait(s) now = now + s V.Run() end
function V.Msg(text, name) ev.scripts.OnEvent(ev, "CHAT_MSG_ADDON", "SpWind", text, "PARTY", name or "Pat") end
function V.F(guid, num, pool, n) return ("F:1:FART:%s:%d:%d:%d"):format(guid, num, pool, n) end
function V.Idx(path)   -- the sound i of a played path
	local f = path and path:match("\\([%w_]+)%.ogg$")
	for k, s in ipairs(ns.EMOTES.FART.sounds) do if s.file == f then return k end end
end
-- a fresh client: groups + guild, cooldown 0, the GUID answers, SY.force for the pick
-- (SY.force: "art" = the first Artifact, "leg" = the voice legend, a number = that sound)
function V.Boot(db)
	ev, ns = Load(db)
	IsInGroup = function() return true end
	IsInGuild = function() return true end
	GetPlayerInfoByGUID = V.Info
	SpokenWindDB.cd = 0
	willPlay = true
	local real = ns.VoicePick
	V.realVP = real
	ns.VoicePick = function(v, h, avoid)
		local f = SY.force
		if f == "art" then return ns.VOX.art[1] elseif f == "leg" then return v.tiers[6][1] elseif type(f) == "number" then return f end
		return real(v, h, avoid)
	end
	return ns
end
-- own key press + its emote line: pool + num of its F, the sound played (i) or nil
function V.Own()
	local na, np = #SY.asent, #plays
	hw = true
	SY.hooks.DoEmote("FART")
	hw = false
	Emote(OWN_FART, ME, ME_GUID)
	local m = SY.asent[na + 1] and SY.asent[na + 1].m or ""
	local num, pool = m:match("^F:1:FART:[^:]+:(%d+):(%d+):%d+")
	return tonumber(pool), tonumber(num), #plays > np and V.Idx(plays[#plays].path) or nil
end
-- another player's fart line: the sound played now or after the wait (nil = none)
function V.Other(guid, name, msg)
	local np = #plays
	if msg then V.Msg(msg, name) now = now + 0.04 end
	ev.scripts.OnEvent(ev, "CHAT_MSG_TEXT_EMOTE", FartBy(name), name, "", "", "", "", 0, 0, "", 0, 123, guid)
	V.Wait(0.3)
	return #plays > np and V.Idx(plays[#plays].path) or nil
end
function V.Copy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[V.Copy(k)] = V.Copy(v) end
	return c
end
end)()

;(function()   -- 0.7.0 the race set (Voices.lua): build, holes, the tier pick, the pools, the voice, the load cost
local V = SY.V7
local forb0 = #forbidden
local PACKF = { "human", "dwarf", "nightelf", "gnome", "orc", "scourge", "tauren", "troll", "skyborne", "artifact" }
ev, ns = Load(nil)
local VOX, snd = ns.VOX, ns.EMOTES.FART.sounds
ok("vox: the set = the old 14 + 1337", VOX.ok and VOX.set == 1337 and #snd == 1351 and ns.BASE_N == 14 and VOX.bad == 0
	and VOX.err == nil, VOX.set)
ok("vox: no sound at /reload (a sound loads on play)", #plays == 0, #plays)
ok("vox: the old 14 keep their numbers, no pack dir", snd[11].file == "11_tuba" and snd[13].file == "13_legend"
	and snd[14].dir == nil and snd[15].dir == "human")
local s1 = snd[15]
ok("vox: sound 15 = #1 (Human M, rare)", s1.file == "human_m_laugh" and s1.num == 1 and s1.tier == 4 and s1.q == 3
	and s1.race == "Human" and s1.body == "m" and s1.name == "Polite Laugh" and s1.page == nil and not s1.shart, s1.file)
ok("vox: the pack tables go after the build", ns.SW1337_HUMAN == nil and ns.SW1337_TROLL == nil and ns.SW1337_ARTIFACT == nil)
ok("vox: lengths join the length table (ms)", ns.LEN.human_m_laugh == 1725 and ns.SoundLen("FART", 15) == 1.725
	and ns.LEN.artifact_never_trust_it == 4970, ns.LEN.human_m_laugh)
local ART_ORDER = { "Never Trust It", "Surprise Splat", "The Final Sputter", "Floodgate", "The Stutter" }
local artOk = #VOX.art == 5
for k, i in ipairs(VOX.art) do
	local s = snd[i]
	if i ~= 14 + 1332 + k or s.num ~= 1332 + k or s.tier ~= 7 or s.q ~= 6 or not s.shart or s.slot ~= ART_ORDER[k]
		or ns.ArtSlot(i) ~= ART_ORDER[k] or s.dir ~= "artifact" or s.race ~= nil then artOk = false end
end
ok("vox: Artifact = #1333-#1337, tier 7, slot names", artOk and ns.ArtSlot(14 + 1332) == nil and ns.ArtSlot(13) == nil)
local names, badV = {}, nil
for _, v in ipairs(VOX.order) do
	names[#names + 1] = v.name
	local k = 0
	for t = 1, 7 do k = k + (v.tiers[t] and #v.tiers[t] or 0) end
	if #v.all ~= 74 or k ~= 74 or v.w ~= 100 or v.tiers[7] or not (v.tiers[6] and #v.tiers[6] == 1) then badV = v.key end
	for t = 1, 5 do if not v.tiers[t] then badV = v.key .. " no tier " .. t end end
	for _, i in ipairs(v.all) do if snd[i].race .. "_" .. snd[i].body ~= v.key then badV = v.key .. " mixed" end end
end
ok("vox: 18 voices of 74: 5 tiers (weights 100) + 1 legend", #VOX.order == 18 and badV == nil, badV or #VOX.order)
ok("vox: voice pages in pack order, M then F", table.concat(names, ",") == "Human M,Human F,Dwarf M,Dwarf F,Night Elf M,"
	.. "Night Elf F,Gnome M,Gnome F,Orc M,Orc F,Undead M,Undead F,Tauren M,Tauren F,Troll M,Troll F,Skyborne M,Skyborne F",
	table.concat(names, ","))
ok("vox: voice keys = the game's race tokens + body", VOX.voices.NightElf_f and VOX.voices.Scourge_m and VOX.voices.Troll_f
	and VOX.voices.Skyborne_m and VOX.voices.Human_m.name == "Human M" and VOX.voices.Scourge_f.name == "Undead F")

-- holes: any bad row, a missing pack, final = false, a pending row = no pool 1 at all (the old 14)
local function VoxLoad(fix)
	local n = {}
	for _, f in ipairs({ "Emotes.lua", "Lengths.lua" }) do assert(loadfile(ADDON_DIR .. "/" .. f))("Spoken_Wind", n) end
	for _, p in ipairs(PACKF) do assert(loadfile(ADDON_DIR .. "/Packs/" .. p .. ".lua"))("Spoken_Wind", n) end
	if fix then fix(n) end
	assert(loadfile(ADDON_DIR .. "/Voices.lua"))("Spoken_Wind", n)
	return n
end
local n0 = VoxLoad()
ok("vox: a 2nd load = the same set", n0.VOX.ok and n0.VOX.set == 1337 and #n0.EMOTES.FART.sounds == 1351)
ok("vox: a pack with no final field loads (troll.lua has none)", n0.VOX.voices.Troll_m and #n0.VOX.voices.Troll_f.all == 74
	and VoxLoad(function(n) n.SW1337_HUMAN.final = nil end).VOX.ok)
local HOLES = {
	{ "a bad tier", function(n) n.SW1337_HUMAN.rows[5].tier = "mythic" end, 1 },
	{ "a num twice", function(n) n.SW1337_DWARF.rows[6].num = n.SW1337_DWARF.rows[5].num end, 1 },
	{ "a bad key", function(n) n.SW1337_GNOME.rows[7].key = "bad key" end, 1 },
	{ "no length", function(n) n.SW1337_ORC.rows[2].ms = 0 end, 1 },
	{ "a bad body", function(n) n.SW1337_TAUREN.rows[3].body = "x" end, 1 },
	{ "an Artifact row in a race pack", function(n) n.SW1337_SCOURGE.rows[4].tier = "artifact" end, 1 },
	{ "a race tier in the Artifact pack", function(n) n.SW1337_ARTIFACT.rows[1].tier = "legendary" end, 1 },
	{ "an Artifact row with no slot", function(n) n.SW1337_ARTIFACT.rows[2].slot = nil end, 1 },
	{ "a num past 1337", function(n) n.SW1337_SKYBORNE.rows[1].num = 1338 end, 1 },
	{ "a pending row (no file)", function(n) n.SW1337_HUMAN.rows[74].pending = true end, 1 },
	{ "a pack missing", function(n) n.SW1337_TROLL = nil end, 0 },
	{ "a pack with final = false", function(n) n.SW1337_NIGHTELF.final = false end, 0 },
	{ "4 Artifact sounds in 1337 rows", function(n)
		local a = table.remove(n.SW1337_ARTIFACT.rows, 1)
		local r = n.SW1337_HUMAN.rows
		r[#r + 1] = { key = "human_m_extra", num = a.num, name = "X", race = "Human", body = "m", tier = "rare", ms = 100 }
	end, 0 },
}
GetPlayerInfoByGUID = function() return "Warrior", "WARRIOR", "Human", "Human", 2, "Name", "" end
for _, h in ipairs(HOLES) do
	local n = VoxLoad(h[2])
	local miss = 0
	n.SyncLog = function(s) if s:find("VOX miss", 1, true) then miss = miss + 1 end end
	ok("vox hole: " .. h[1] .. " = the old 14 only", not n.VOX.ok and n.VOX.set == 0 and #n.EMOTES.FART.sounds == 14
		and n.PoolSize(1) == nil and n.PoolSize(0) == 14 and #n.VoxPages() == 0 and n.VoiceOf("Player-1-0000ABCD") == nil
		and miss == 0 and n.VOX.err == nil and #n.VOX.art == 0 and n.ArtSlot(14 + 1333) == nil and n.VOX.bad == h[3] and n.VoxBoot():find("^set=0 ")
		and n.SW1337_HUMAN == nil, h[1] .. " bad=" .. n.VOX.bad .. " " .. n.VoxBoot())
end
local nW = VoxLoad(function(n)
	for _, r in ipairs(n.SW1337_HUMAN.rows) do if r.body == "m" and r.tier == "poor" then r.tier = "common" end end
end)
local hm = nW.VOX.voices.Human_m
ok("vox: a voice with no poor sound = weight 75 (no poor tier), the others 100", nW.VOX.ok and hm and hm.tiers[1] == nil
	and hm.w == 75 and nW.VOX.voices.Human_f.w == 100, hm and hm.w)
local nE = VoxLoad(function(n)
	n.SW1337_HUMAN.rows[1] = setmetatable({}, { __index = function() error("row boom", 0) end })
end)
local vb = nE.VoxBoot()
ok("vox: a Lua error in the build = the old 14 + verr in BOOT (one word)", not nE.VOX.ok and #nE.EMOTES.FART.sounds == 14
	and vb:find(" verr=row_boom$") ~= nil, vb)
GetPlayerInfoByGUID = nil

-- the tier pick: whole numbers, the page odds
local VH = VOX.voices.Human_m
ok("pick: same hash = same sound (every client)", ns.VoicePick(VH, 123456789) == ns.VoicePick(VH, 123456789))
local N, art, leg, cls, tierN, seen, nSeen = 200000, 0, 0, 0, { 0, 0, 0, 0, 0 }, {}, 0
for h = 0, N - 1 do
	local i = ns.VoicePick(VH, h)
	local s = snd[i]
	if i <= 14 then cls = cls + 1
	elseif s.tier == 7 then art = art + 1 elseif s.tier == 6 then leg = leg + 1 else tierN[s.tier] = tierN[s.tier] + 1 end
	if not seen[i] then seen[i], nSeen = true, nSeen + 1 end
end
ok("pick: Artifact exactly 1 in 5000, the legend 1 in 500, Classic 1 in 200", art == 40 and leg == 400 and cls == 1000,
	art .. " " .. leg .. " " .. cls)
local rest, far = N - art - leg - cls, nil
for t, w in ipairs({ 25, 35, 22, 13, 5 }) do
	local pct = tierN[t] / rest * 100
	if math.abs(pct - w) > 0.5 then far = ("tier %d: %.2f%%"):format(t, pct) end
end
ok("pick: the tiers by weight (poor 25, common 35, uncommon 22, rare 13, epic 5)", far == nil, far)
ok("pick: every sound of the voice + the 5 Artifacts + the 14 Classic can come", nSeen == 74 + 5 + 14, nSeen)
local L1 = VH.tiers[6][1]
local t720 = snd[ns.VoicePick(VH, 720)].tier
ok("pick: hash % 100000: 0-19 Artifact, 20-219 the legend, 220-719 Classic, 720+ a tier", snd[ns.VoicePick(VH, 0)].tier == 7
	and snd[ns.VoicePick(VH, 19)].tier == 7 and snd[ns.VoicePick(VH, 100019)].tier == 7 and ns.VoicePick(VH, 20) == L1
	and ns.VoicePick(VH, 219) == L1 and ns.VoicePick(VH, 220) <= 14 and ns.VoicePick(VH, 719) <= 14
	and ns.VoicePick(VH, 100220) <= 14 and t720 ~= nil and t720 <= 5, t720)
do   -- Classic: each of the old 14 the same odds (as in 0.6.x: 1 in 14), never the one before it
	local cN, cBad, cFar, cSame = {}, nil, nil, nil
	for k = 0, 39 do
		for u = 220, 719 do
			local i = ns.VoicePick(VH, k * 100000 + u)
			if i > 14 then cBad = k * 100000 + u end
			cN[i] = (cN[i] or 0) + 1
		end
	end
	for i = 1, 14 do
		if not cN[i] or math.abs(cN[i] - 20000 / 14) > 20000 / 14 * 0.1 then cFar = i .. ": " .. tostring(cN[i]) end
	end
	ok("pick: Classic = the old 14, each about 1 in 14 (the 0.6.x odds)", cBad == nil and cFar == nil, cBad or cFar)
	for u = 220, 719 do
		local a = ns.VoicePick(VH, u)
		local b = ns.VoicePick(VH, u, a)
		if b == a or b > 14 then cSame = u end
	end
	ok("pick: Classic twice in a step = another of the 14, never the one before it", cSame == nil, cSame)
end
ok("pick: the legend twice in a step = a normal tier", snd[ns.VoicePick(VH, 20, L1)].tier <= 5)
local a0 = ns.VoicePick(VH, 0)
local a1 = ns.VoicePick(VH, 0, a0)
ok("pick: an Artifact twice in a step = another Artifact", snd[a1].tier == 7 and a1 ~= a0)
local same
for h = 1000, 30000 do
	local a = ns.VoicePick(VH, h)
	if ns.VoicePick(VH, h, a) == a then same = h end
end
ok("pick: never the sound before it", same == nil, same)
local FV = { tiers = { [1] = { 15 }, [2] = { 16, 17 }, [5] = { 18 } }, w = 25 + 35 + 5 }
local hT1, hT5
for h = 720, 100000 do   -- hash % 100000 >= 720: no Artifact, no legend, no Classic
	local x = (h * 48271 % 2147483647) % 65
	if not hT1 and x < 25 then hT1 = h end
	if not hT5 and x >= 60 then hT5 = h end
end
ok("pick: a voice with gaps: weights of its own tiers", ns.VoicePick(FV, hT1) == 15 and ns.VoicePick(FV, hT5) == 18)
local p1 = ns.VoicePick(FV, hT1, 15)
ok("pick: a 1-sound tier twice = the next tier (fixed order)", p1 == 16 or p1 == 17, p1)
ok("pick: the last tier wraps to the first", ns.VoicePick(FV, hT5, 18) == 15)
local f20, f219, f220 = ns.VoicePick(FV, 20), ns.VoicePick(FV, 219), ns.VoicePick(FV, 220)
ok("pick: a voice with no legend: 20-219 = a normal tier, 220-719 still Classic (1 in 200 for every voice)",
	f20 >= 15 and f20 <= 18 and f219 >= 15 and f219 <= 18 and f220 <= 14, f20 .. " " .. f219 .. " " .. f220)

-- pools on the wire
ns.EMOTES.CHEER = { folder = "cheer", sounds = { { file = "01_a" }, { file = "02_b" } } }
ok("pools: 0 = the old sounds, 1 = the set (FART only), others none", ns.PoolSize(0) == 14 and ns.PoolSize(0, "FART") == 14
	and ns.PoolSize(1) == 1337 and ns.PoolSize(1, "FART") == 1337 and ns.PoolSize(1, "CHEER") == nil and ns.PoolSize(2) == nil
	and ns.PoolSize(0, "CHEER") == 2 and ns.OldN("FART") == 14 and ns.OldN("CHEER") == 2 and ns.OldN("NOPE") == 0)
local w1, w2 = ns.PoolWire(15)
local w3, w4 = ns.PoolWire(14)
local w5, w6 = ns.PoolWire(1351)
ok("pools: sound i <-> (pool, num)", w1 == 1 and w2 == 1 and w3 == 0 and w4 == 14 and w5 == 1 and w6 == 1337
	and ns.PoolIndex(1, 1) == 15 and ns.PoolIndex(1, 1337) == 1351 and ns.PoolIndex(0, 7) == 7)

-- the voice of a GUID
local GA = "Player-1-0000ABCD"
V.R = {}
GetPlayerInfoByGUID = V.Info
ok("voice: no answer = none", ns.VoiceOf(GA) == nil)
V.R[GA] = { "Troll", 2 }
ok("voice: Troll + 2 = Troll M", ns.VoiceOf(GA) == VOX.voices.Troll_m)
V.R[GA] = { "Troll", 3 }
ok("voice: Troll + 3 = Troll F", ns.VoiceOf(GA) == VOX.voices.Troll_f)
V.R[GA] = { "Scourge", 3 }
ok("voice: Scourge = the Undead pack", ns.VoiceOf(GA) == VOX.voices.Scourge_f and ns.VoiceOf(GA).name == "Undead F")
V.R[GA] = { "Troll", 1 }
ok("voice: sex 1 (not known) = none, one VOX miss line", ns.VoiceOf(GA) == nil and V.SyncHas("VOX miss race=Troll sex=1") == 1)
ns.VoiceOf(GA)
ok("voice: the same miss logs once", V.SyncHas("VOX miss race=Troll sex=1") == 1)
V.R[GA] = { "BloodElf", 2 }
ok("voice: a race with no pack = none (the old 14)", ns.VoiceOf(GA) == nil and V.SyncHas("VOX miss race=BloodElf sex=2") == 1)
for k = 1, 20 do V.R[GA] = { "Race" .. k, 2 } ns.VoiceOf(GA) end
ok("voice: max 10 miss lines a session", V.SyncHas("VOX miss") == 10, V.SyncHas("VOX miss"))
local leak
for _, l in ipairs(SpokenWindDB.sync) do
	if l:find("VOX", 1, true) and (l:find("Player-", 1, true) or l:find("Name", 1, true)) then leak = l end
end
ok("voice: no GUID, no name in the log", leak == nil, leak)
V.R[GA] = { "Human", 2 }
issecretvalue = function(v) return v == "Human" end
ok("voice: a hidden race = none", ns.VoiceOf(GA) == nil)
issecretvalue = function(v) return v == 2 end
ok("voice: a hidden sex = none", ns.VoiceOf(GA) == nil)
issecretvalue = function(v) return v == GA end
ok("voice: a hidden GUID = none", ns.VoiceOf(GA) == nil)
issecretvalue = nil
V.R[GA] = "boom"
ok("voice: an error in the game call = none, no ERR", ns.VoiceOf(GA) == nil and V.NoErr())
ok("voice: no GUID = none", ns.VoiceOf(nil) == nil and ns.VoiceOf("") == nil)
V.R[GA] = { "Human", 2 }
local pA, nA, vA = ns.PoolFor("FART", GA)
local pB, nB, vB = ns.PoolFor("FART", "Player-1-0000FFFF")
local pC, nC = ns.PoolFor("CHEER", GA)
ok("voice: pool 1 with a voice, 0 without, another emote 0", pA == 1 and nA == 1337 and vA == VOX.voices.Human_m and pB == 0
	and nB == 14 and vB == nil and pC == 0 and nC == 2)
GetPlayerInfoByGUID = nil
ns.EMOTES.CHEER = nil
preLogin = function() GetPlayerInfoByGUID = function(g) if g == ME_GUID then return "W", "WARRIOR", "D", "Dwarf", 3, "N", "" end end end
ev, ns = Load(nil)
preLogin = nil
ok("voice: BOOT has the own voice (race token + body only)", LastLog():find(" set=1337 vms=0 vox=Dwarf_f vbad=0 art=5 apk=0", 1, true)
	and not LastLog():find("Player-", 1, true), LastLog())
GetPlayerInfoByGUID = nil

-- the load cost (LuaJIT here; the game's Lua is slower + 64-bit values: see the stage note)
local function Median(t) table.sort(t) return t[math.ceil(#t / 2)] end
local msT, kbT, keep = {}, {}, nil
for r = 1, 5 do
	keep = nil
	local base = {}
	for _, f in ipairs({ "Emotes.lua", "Lengths.lua" }) do assert(loadfile(ADDON_DIR .. "/" .. f))("Spoken_Wind", base) end
	collectgarbage("collect") collectgarbage("collect")
	local kb0, t0 = collectgarbage("count"), os.clock()
	for _, p in ipairs(PACKF) do assert(loadfile(ADDON_DIR .. "/Packs/" .. p .. ".lua"))("Spoken_Wind", base) end
	assert(loadfile(ADDON_DIR .. "/Voices.lua"))("Spoken_Wind", base)
	msT[r] = (os.clock() - t0) * 1000
	collectgarbage("collect") collectgarbage("collect")
	kbT[r] = collectgarbage("count") - kb0
	keep = base
end
local ms, kb = Median(msT), Median(kbT)
local function LoadKB(noPacks)
	SY.noPacks = noPacks
	collectgarbage("collect") collectgarbage("collect")
	local kb0, t0 = collectgarbage("count"), os.clock()
	ev, ns = Load(nil)
	local t = (os.clock() - t0) * 1000
	collectgarbage("collect") collectgarbage("collect")
	SY.noPacks = nil
	return collectgarbage("count") - kb0, t
end
LoadKB(true)   -- a settle load: frees what the blocks before left
-- the set's cost = a packs load less the no-packs load right before it, median of 5 pairs. One load keeps its
-- fake UI frames reachable here (0.8.0, ~3.7 MB; a /reload in the game frees all), and a load may free or keep
-- an older one by the address order of the frame tables: one pair can be off by that much, the median is not.
local adds, keeps, msS, msO, seq = {}, {}, {}, {}, {}
for i = 1, 5 do
	local kT, tT = LoadKB(true)
	local kF, tF = LoadKB(false)
	adds[i], keeps[i], msS[i], msO[i] = kF - kT, kT, tF, tT
	seq[i] = ("%.0f/%.0f"):format(kT, kF)
end
local addKB, keepKB, msSet, msOld = Median(adds), Median(keeps), Median(msS), Median(msO)
out(("LOADCOST rows=%.1fms/%.0fKB addon=+%.0fKB keep=%.0fKB load=%.1fms old=%.1fms (LuaJIT, median of 5) pairs=%s"):format(ms,
	kb, addKB, keepKB, msSet, msOld, table.concat(seq, " ")))
ok("vox: the set loads in 50 ms + 2 MB (packs + build, LuaJIT)", ms <= 50 and kb <= 2048, ("%.1f ms %.0f KB"):format(ms, kb))
ok("vox: the whole addon: +2 MB max, +50 ms max for the set", addKB <= 2048 and msSet - msOld <= 50,
	("%.0f KB %.1f ms"):format(addKB, msSet - msOld))
ok("vox: nothing forbidden in the block", #forbidden == forb0, forbidden[#forbidden])
end)()

;(function()   -- 0.7.0 on the wire (pool 1) + the seed path with a voice
local V = SY.V7
local forb0 = #forbidden
local PG, QG, XG = "Player-1-0000FFFF", "Player-1-0000BBBB", "Player-1-0000EEEE"
V.R = { [ME_GUID] = { "Human", 2 }, [PG] = { "Orc", 3 }, [QG] = { "Gnome", 2 } }
V.Boot(nil)
local snd = ns.EMOTES.FART.sounds
local pool, num, i = V.Own()
ok("wire: own fart with a voice = F pool 1 + the set number, the same sound here", pool == 1 and num and i == 14 + num,
	tostring(pool) .. " " .. tostring(num) .. " " .. tostring(i))
local s = i and snd[i] or {}
ok("wire: the own voice (Human M) from Media\\human", s.race == "Human" and s.body == "m"
	and plays[#plays].path == ns.MEDIA .. "human\\" .. tostring(s.file) .. ".ogg", plays[#plays] and plays[#plays].path)
ok("wire: the fart log shows the set number + name + voice", ns.FartLogRows()[1].num == num and ns.FartLogRows()[1].name == s.name
	and ns.FartLogRows()[1].voice == "Human M", tostring(ns.FartLogRows()[1].name))
V.Wait(12)
V.R[ME_GUID] = nil
pool, num, i = V.Own()
ok("wire: own fart with no voice = pool 0, the old 14", pool == 0 and num and num <= 14 and i == num, tostring(pool) .. " " .. tostring(num))
V.Wait(12)
local nAP = V.SyncHas("ART pick")
i = V.Other(PG, "Pat", V.F(PG, 1335, 1, 1))
ok("wire: F pool 1 #1335 = that sound (by msg), exactly", i == 14 + 1335 and V.SyncHas("by=msg") >= 1, i)
ok("wire: a heard shart: no swap, no line", V.SyncHas("ART pick") == nAP and #SY.artSent == 0)
V.Wait(12)
ok("wire: a heard shart: still no line after its length", #SY.artSent == 0, #SY.artSent)
for k, bad in ipairs({ V.F(PG, 0, 1, 2), V.F(PG, 1338, 1, 3), V.F(PG, 3, 2, 4), V.F(PG, 15, 0, 5) }) do
	local np = #plays
	i = V.Other(PG, "Pat", bad)
	local ps = i and snd[i] or {}
	ok("wire: a bad pool / number is dropped, the emote plays the seed (Orc F) " .. k, i and ps.race == "Orc" and ps.body == "f"
		and #plays == np + 1 and V.NoErr(), tostring(i))
	V.Wait(12)
end
-- the seed path with a voice: the same hash input as the old pick, tier first (every client the same)
local step = ns.SyncStep()
local want = V.realVP(ns.VOX.voices.Gnome_m, ns.SeedHash(("FART:%s:%d:%d"):format(QG, step, 0)), nil)
i = V.Other(QG, "Quin")
ok("wire: seed path with a voice = VoicePick(seed hash) (Gnome M)", i == want and snd[i].race == "Gnome", tostring(i) .. " " .. want)
V.Wait(12)
local np = #plays
i = V.Other(XG, "Xan")
ok("wire: seed path, no voice = the old 14", i and i <= 14, i)
ok("wire: no forbidden call", #forbidden == forb0, forbidden[#forbidden])
-- a client where the set did not load: pool 1 is dropped (seed), the old 14 only
SY.noPacks = true
V.Boot(nil)
SY.noPacks = nil
V.R[PG] = { "Orc", 3 }
i = V.Other(PG, "Pat", V.F(PG, 20, 1, 9))
ok("wire: no set here: F pool 1 dropped, the seed plays an old sound", i and i <= 14 and V.NoErr(), i)
V.Wait(12)
local pl, nl = V.Own()
ok("wire: no set here: own F = pool 0", pl == 0 and nl and nl <= 14, tostring(pl))
ok("wire: nothing forbidden in the block", #forbidden == forb0, forbidden[#forbidden])
end)()

;(function()   -- 0.7.0 Rule 1 (the Artifact the account heard least) + Rule 2 (the approved line)
local V = SY.V7
local forb0 = #forbidden
local PG = "Player-1-0000FFFF"
V.R = { [ME_GUID] = { "Human", 2 }, [PG] = { "Human", 3 } }
V.Boot(nil)
local snd, A = ns.EMOTES.FART.sounds, ns.VOX.art
-- the texts: exactly the 5 approved, one per slot, one chat line each
local okT = #ns.ART.lines == 5
local nTxt = 0
for _ in pairs(SY.ART_TEXT) do nTxt = nTxt + 1 end
for _, l in ipairs(ns.ART.lines) do if SY.ART_TEXT[l.text] ~= l.slot or #l.text > 255 then okT = false end end
for _, i in ipairs(A) do
	local has = false
	for _, l in ipairs(ns.ART.lines) do if l.slot == ns.ArtSlot(i) then has = true end end
	if not has then okT = false end
end
ok("rule 2: the 5 approved texts, keyed by slot name, 255 bytes max", okT and nTxt == 5)
-- Rule 1 + 2 on own farts: 5 sharts = the 5 slots, each its own line, 1 s after the sound
SY.force = "art"
local nums, played, okW = {}, {}, true
for k = 1, 5 do
	local pool, num, i = V.Own()
	if pool ~= 1 or i ~= 14 + (num or 0) or not ns.ArtSlot(i) then okW = false end
	nums[k], played[k] = num, i
	if k == 1 then
		local len = ns.SoundLen("FART", i)
		V.Wait(len + 1 - 0.01)
		ok("rule 2: no line before the sound ends + 1 s", #SY.artSent == 0, #SY.artSent)
		V.Wait(0.01)
		ok("rule 2: the line at the sound end + 1 s", #SY.artSent == 1, #SY.artSent)
		V.Wait(10)
	else
		V.Wait(12)
	end
end
SY.force = nil
local set = {}
for _, n in ipairs(nums) do set[n] = true end
ok("rule 1: 5 own sharts (empty collection) = 5 different", set[1333] and set[1334] and set[1335] and set[1336] and set[1337]
	and okW, table.concat(nums, ","))
local okPool = true
for k = 1, 5 do if V.SyncHas(("ART pick snd=%d least=0 pool=%d"):format(nums[k], 6 - k)) ~= 1 then okPool = false end end
ok("rule 1: the log: snd, least, ties", okPool, SpokenWindDB.sync[#SpokenWindDB.sync])
local pk = SpokenWindDB.artPick
ok("rule 1: own picks counted by slot name", pk["Never Trust It"] == 1 and pk["Surprise Splat"] == 1 and pk["The Final Sputter"] == 1
	and pk.Floodgate == 1 and pk["The Stutter"] == 1)
local okL = #SY.artSent == 5
for k = 1, 5 do
	local a = SY.artSent[k]
	if not a or SY.ART_TEXT[a.text] ~= ns.ArtSlot(played[k]) then okL = false end
end
ok("rule 2: each shart = the line of its own slot", okL, #SY.artSent)
local okS = true
for k = 1, 5 do if not sent[k] or sent[k].chan ~= "EMOTE" or sent[k].lang ~= nil or sent[k].tgt ~= nil then okS = false end end
ok("rule 2: EMOTE, no language, no target; nothing else said", okS and #sent == 5, #sent)
local okLog = true
for n = 1, 5 do if V.SyncHas("ART line slot=" .. n) ~= 1 then okLog = false end end
ok("rule 2: the log: ART line slot=1-5", okLog)
SY.force = "art"
local _, num6 = V.Own()
SY.force = nil
ok("rule 1: the 6th = a new round (least 1, 5 ties)", num6 and num6 >= 1333 and V.SyncHas(("ART pick snd=%d least=1 pool=5"):format(num6)) == 1, num6)
V.Wait(12)
-- heard sharts never swap (the seed path keeps the pure seed), never a line
local pk0, nLine = V.Copy(SpokenWindDB.artPick), #SY.artSent
SY.force = "art"
local hi = V.Other(PG, "Pat")
SY.force = nil
ok("rule 1: a heard shart (seed path) = the seed's Artifact, no swap, not counted", hi == A[1]
	and V.SyncHas("ART pick") == 6 and SpokenWindDB.artPick["Never Trust It"] == pk0["Never Trust It"], hi)
V.Wait(12)
ok("rule 2: a heard shart = no line", #SY.artSent == nLine, #SY.artSent)

-- Rule 1 counts: heard from others (collection n - own) + own picks; ties random
V.Boot(nil)
local dex = SpokenWindDB.dex
dex[snd[A[1]].file] = { n = 5, t = clock, own = 5 }   -- own plays only: 0 from others
dex[snd[A[2]].file] = { n = 2, t = clock, own = 0 }
dex[snd[A[3]].file] = { n = 1, t = clock, own = 0 }
SpokenWindDB.artPick[snd[A[4]].slot] = 1
local realRandom = math.random
math.random = function(a, b) return b end   -- ties: the last one
ok("rule 1: least heard by others + own picks; ties random", ns.ArtSwap(A[3]) == A[5]
	and SpokenWindDB.artPick["The Stutter"] == 1 and V.SyncHas("ART pick snd=1337 least=0 pool=2") == 1)
ok("rule 1: then the only least one", ns.ArtSwap(A[5]) == A[1] and V.SyncHas("ART pick snd=1333 least=0 pool=1") == 1)
math.random = realRandom
local np0 = V.SyncHas("ART pick")
ok("rule 1: not an Artifact = unchanged, not counted", ns.ArtSwap(15) == 15 and ns.ArtSwap(13) == 13 and ns.ArtSwap(1346) == 1346
	and V.SyncHas("ART pick") == np0 and SpokenWindDB.artPick["Surprise Splat"] == nil)
for _ = 1, 30 do ns.ArtSwap(A[1]) end
ok("rule 1: max 20 ART log lines a session", V.SyncHas(" ART pick") + V.SyncHas(" ART line") == 20, V.SyncHas(" ART pick"))

-- the own pick counts are checked at load
V.Boot({ artPick = { ["Never Trust It"] = 2.7, Floodgate = -1, Bogus = 3, [5] = 1, ["The Stutter"] = "x",
	["Surprise Splat"] = 1e12 } })
local ap = SpokenWindDB.artPick
ok("rule 1: bad saved picks are dropped", ap["Never Trust It"] == 2 and next(ap, "Never Trust It") == nil
	and next(ap) == "Never Trust It", next(ap))
ok("rule 1: BOOT apk = the own picks", LastLog():find(" art=5 apk=2", 1, true) ~= nil, LastLog())
V.Boot({ artPick = "junk" })
ok("rule 1: a junk save = no picks", type(SpokenWindDB.artPick) == "table" and next(SpokenWindDB.artPick) == nil)

-- Own /fart off: the others hear it, so the line goes; addon off = no line
V.Boot(nil)
SpokenWindDB.self = false
SY.force = "art"
local np = #plays
local pOff, nOff, iOff = V.Own()
V.Wait(12)
ok("rule 2: Own /fart off: no sound here, F sent, the line of the sent slot", pOff == 1 and iOff == nil and #plays == np
	and #SY.artSent == 1 and SY.ART_TEXT[SY.artSent[1].text] == ns.ArtSlot(14 + nOff), #SY.artSent)
SpokenWindDB.self = true
SpokenWindDB.on = false
V.Own()
V.Wait(12)
ok("rule 2: addon off = no line", #SY.artSent == 1, #SY.artSent)
SpokenWindDB.on = true
SY.force = nil

-- skips: dead, AFK, a cinematic, the logout timer (then lines go again)
local st = {}
UnitIsDeadOrGhost = function(u) return u == "player" and st.dead or false end
UnitIsAFK = function(u) return u == "player" and st.afk or false end
InCinematic = function() return st.cine or false end
local function Shart(set)
	SY.force = "art"
	V.Own()
	SY.force = nil
	if set then set() end
	V.Wait(12)
end
for _, g in ipairs({ { "dead", function() st.dead = true end }, { "afk", function() st.afk = true end },
	{ "cine", function() st.cine = true end },
	{ "logout", function() ev.scripts.OnEvent(ev, "PLAYER_CAMPING") end } }) do
	local n0 = #SY.artSent
	Shart(g[2])
	ok("rule 2: skip why=" .. g[1], #SY.artSent == n0 and V.SyncHas("ART line skip why=" .. g[1]) == 1, #SY.artSent)
	st = {}
	if g[1] == "logout" then ev.scripts.OnEvent(ev, "LOGOUT_CANCEL") end
end
local n1 = #SY.artSent
Shart()
ok("rule 2: a skip is not a stop: the next shart has its line", #SY.artSent == n1 + 1, #SY.artSent)

-- blocked: an error or the block event = no more lines this session, no 2nd way
V.Wait(5)   -- the last line is 5 s old
ev.scripts.OnEvent(ev, "ADDON_ACTION_BLOCKED", "OtherAddon", "SendChatMessage()")
ev.scripts.OnEvent(ev, "ADDON_ACTION_BLOCKED", "Spoken_Wind", "DoEmote()")   -- not near a line
Shart()
ok("rule 2: another addon's block / our DoEmote block long after a line = lines go on", #SY.artSent == n1 + 2, #SY.artSent)
SY.chatErr = true
Shart()
SY.chatErr = nil
ok("rule 2: a chat error = block + ERR art in the log", V.SyncHas("ART line skip why=block") == 1 and V.SyncHas("ERR art ") == 1
	and #SY.artSent == n1 + 3, #SY.artSent)
Shart()
ok("rule 2: after a block: no more lines (no chat call at all)", #SY.artSent == n1 + 3 and V.SyncHas("ART line skip why=block") == 1,
	#SY.artSent)
V.Boot(nil)
SY.chatHook = function() ev.scripts.OnEvent(ev, "ADDON_ACTION_BLOCKED", "Spoken_Wind", "SendChatMessage()") end
Shart()
SY.chatHook = nil
ok("rule 2: the block event during the line = stop, not logged as sent", #SY.artSent == 1 and V.SyncHas("ART line skip why=block") == 1
	and V.SyncHas("ART line slot=") == 0, #SY.artSent)
Shart()
ok("rule 2: after the block event: no more lines", #SY.artSent == 1)
V.Boot(nil)
ev.scripts.OnEvent(ev, "ADDON_ACTION_BLOCKED", "Spoken_Wind", "SendChatMessage()")
Shart()
ok("rule 2: our SendChatMessage blocked any time = stop", #SY.artSent == 0 and V.SyncHas("ART line skip why=block") == 1)
-- the window: our block of any call up to 1 s after a line = stop
V.Boot(nil)
SY.force = "art"
local _, _, iw = V.Own()
SY.force = nil
V.Wait(ns.SoundLen("FART", iw) + 1)
local nw = #SY.artSent
V.Wait(0.5)
ev.scripts.OnEvent(ev, "ADDON_ACTION_BLOCKED", "Spoken_Wind", "DoEmote()")
ok("rule 2: our block (not chat) 0.5 s after a line = stop", nw == 1 and V.SyncHas("ART line skip why=block") == 1, nw)
V.Wait(12)
ok("rule 2: once stopped, no line waits for the next shart", ns.ArtPlayed(A[1]) == false)
ns.ArtInit(SpokenWindDB)
ok("rule 2: ArtInit (a new load) = a fresh session, a line may wait again", ns.ArtPlayed(A[2]) == true)
V.Wait(12)
-- a line waits, then our chat call is blocked = that line never calls chat
V.Boot(nil)
Shart(function() ev.scripts.OnEvent(ev, "ADDON_ACTION_BLOCKED", "Spoken_Wind", "SendChatMessage()") end)
ok("rule 2: a block while a line waits = no chat call for it", #SY.artSent == 0 and #sent == 0, #SY.artSent)
-- no chat API at line time = skip, not a stop
V.Boot(nil)
local keepSCM = SendChatMessage
Shart(function() SendChatMessage = nil end)
SendChatMessage = keepSCM
ok("rule 2: no chat API at line time = skip why=noapi, no ERR", #SY.artSent == 0 and V.SyncHas("ART line skip why=noapi") == 1
	and V.NoErr(), select(2, V.NoErr()))
Shart()
ok("rule 2: noapi is not a stop: the next line goes", #SY.artSent == 1, #SY.artSent)
-- the seed path: the 2nd fart of one farter in a step never repeats the 1st
V.Boot(nil)
local got, wrap = {}, ns.VoicePick
ns.VoicePick = function(v, h, avoid)
	local i = wrap(v, h, avoid)
	got[#got + 1] = { avoid = avoid, i = i }
	return i
end
V.Other(PG, "Pat")
V.Other(PG, "Pat")
ns.VoicePick = wrap
ok("seed path: the 2nd pick in a step gets avoid = the 1st", #got == 2 and got[1].avoid == nil and got[2].avoid == got[1].i, #got)
V.Wait(12)
UnitIsDeadOrGhost, UnitIsAFK, InCinematic = nil, nil, nil
ok("rule 1 + 2: nothing forbidden in the block", #forbidden == forb0, forbidden[#forbidden])
end)()

;(function()   -- 0.7.0 the hidden row, legends, Orchestra, the Collection pages of the set
local V = SY.V7
local forb0 = #forbidden
local PG, QG = "Player-1-0000FFFF", "Player-1-0000BBBB"
V.R = { [ME_GUID] = { "Human", 2 }, [PG] = { "Orc", 3 }, [QG] = { "Troll", 2 } }
V.Boot(nil)
local snd, A = ns.EMOTES.FART.sounds, ns.VOX.art
local function Tiles(tab)
	local t = {}
	for _, x in ipairs(ns.AchLines(tab).tiles) do t[x.id] = x end
	return t
end
ok("shart row: hidden until earned", Tiles("classic").shart == nil and SpokenWindDB.ach.done.shart == nil)
local i = V.Other(PG, "Pat")
ok("shart row: a race sound does not earn it", i and snd[i].race == "Orc" and SpokenWindDB.ach.done.shart == nil)
ok("Orchestra: the race set is not counted (the old 14 only)", SpokenWindDB.ach.heard[snd[i].file] == nil)
V.Wait(12)
i = V.Other(PG, "Pat", V.F(PG, 1336, 1, 2))
ok("shart row: a heard Artifact earns it (toast)", i == 14 + 1336 and SpokenWindDB.ach.done.shart ~= nil
	and LogHas("ACH shart toast=1"), LastLog())
local t = Tiles("classic").shart
ok("shart row: shown once earned, ? icon, epic", t and t.done and t.q == 5 and t.name == "That wasn't a fart"
	and t.icon == "Interface\\Icons\\INV_Misc_QuestionMark", t and t.icon)
V.Wait(12)
V.Boot(nil)
SY.force = "art"
V.Own()
SY.force = nil
ok("shart row: an own Artifact earns it too", SpokenWindDB.ach.done.shart ~= nil)
ok("shart row: rule = Hear a Shartifact, name = the approved line", ns.AchRow("shart").rule == "Hear a Shartifact"
	and ns.AchRow("shart").name == "That wasn't a fart", ns.AchRow("shart").rule)
V.Wait(12)
-- a voice legend counts as a legend (stats), not as Legend Has It (#13 only)
local st0 = SpokenWindDB.stats
local l0, h0 = st0.legend, st0.legendHeard
SY.force = "leg"
local _, _, il = V.Own()
V.Wait(12)
local ih = V.Other(QG, "Quin")
SY.force = nil
ok("legend: own voice legend = Legend +1", il and snd[il].tier == 6 and SpokenWindDB.stats.legend == l0 + 1, SpokenWindDB.stats.legend)
ok("legend: heard voice legend = Heard legend +1", ih and snd[ih].tier == 6 and SpokenWindDB.stats.legendHeard == h0 + 1)
ok("legend: Legend Has It stays #13", SpokenWindDB.ach.done.legend == nil)
V.Wait(12)

-- the Collection with the set: 20 pages, the rows count
V.Boot(nil)
local function Row(id) for _, x in ipairs(ns.AchLines("collection").tiles) do if x.id == id then return x end end end
local L = ns.AchLines("collection")
ok("set pages: 20 = Original + 18 voices + Artifact", L.pages == 20 and L.pageHead == "Original 0/14" and #L.sounds == 14, L.pages)
local L2, L20 = ns.AchLines("collection", 2), ns.AchLines("collection", 20)
ok("set pages: Human M 0/74, Shartifact 0/5", L2.pageHead == "Human M 0/74" and #L2.sounds == 74 and L20.pageHead == "Shartifact 0/5"
	and #L20.sounds == 5, L2.pageHead .. " " .. L20.pageHead)
ok("set pages: tiles show the set number", L2.sounds[1].name == "#1 ???" and L20.sounds[1].name == "#1333 ???",
	L20.sounds[1].name)
ok("set rows: every Collection row counts (none Soon)", Row("starter").stat == "0/10" and Row("collector").stat == "0/100"
	and Row("gasologist").stat == "0/500" and Row("pitch").stat == "0/74" and Row("complete").stat == "0/1337",
	Row("collector").stat .. " " .. Row("pitch").stat .. " " .. Row("complete").stat)
V.Other(PG, "Pat", V.F(PG, 1335, 1, 1))
L20 = ns.AchLines("collection", 20)
local heard
for _, x in ipairs(L20.sounds) do if x.heard then heard = x end end
ok("set pages: a heard Shartifact: Shartifact 1/5, its name", L20.pageHead == "Shartifact 1/5" and heard
	and heard.name == "#1335 The Final Sputter" and Row("complete").stat == "1/1337", heard and heard.name)
ok("set pages: fit = the label once heard, also when not heard", L2.sounds[1].fit == "#1 " .. snd[15].name
	and heard.fit == heard.name and L20.sounds[1].fit == "#1333 Never Trust It", L2.sounds[1].fit)
V.Wait(12)
Slash("ach collection")
do   -- the window on the set: 20 voice chips, the pager inside a voice
	local W, B = Id.W()
	local function Lab(k) return B["v" .. k .. "Text"].text end
	local nShown, uniq, okLab, bad = 0, {}, true, ""
	for k = 1, 20 do
		if B["v" .. k].shown then nShown = nShown + 1 end
		local s = Lab(k)
		if uniq[s] or not s:find("^%a+ ?[MF]? %d+$") or #s > 8 then okLab, bad = false, s end
		uniq[s] = true
	end
	ok("set window: 20 chips (Original, 18 voices, Shartifact), short labels (8 chars max), all different", nShown == 20 and okLab
		and Lab(1) == "Orig 0" and Lab(2) == "Hu M 0" and Lab(20) == "Shart 1", bad .. " / " .. Lab(1) .. " " .. Lab(2) .. " " .. Lab(20))
	ok("set window: chip states: Original sel, a voice with none heard off, Artifact 1/5 base", SY.State(B.v1) == "sel"
		and SY.State(B.v2) == "off" and SY.State(B.v20) == "base", SY.State(B.v20))
	local function Pg() return (B.page._lookText or B.page).text end
	local function Slots()
		local out = {}
		for _, r in ipairs(B._swRows or {}) do
			for _, X in ipairs({ "A", "B", "C", "D" }) do
				if r["s" .. X].shown then out[#out + 1] = r["n" .. X].text end
			end
		end
		return out
	end
	ok("set window: page 1 = Original 0/14, one page of sounds", B.pageHeadText.text == "Original" and B.pageHave.text == "0/14"
		and #Slots() == 14 and Pg() == "1/1", B.pageHeadText.text)
	SY.Click(B.v2)
	local sl = Slots()
	ok("set window: Hu M = Human M 0/74: 40 a page, 1/2, DEX show logged", B.pageHeadText.text == "Human M"
		and B.pageHave.text == "0/74" and #sl == 40 and Pg() == "1/2" and sl[1] == "|cff9d9d9d#1\194\160???|r"
		and LastLog():find("DEX show n=1/1351 page=2/20$") ~= nil, B.pageHeadText.text .. " " .. #sl .. " " .. LastLog())
	SY.Click(B.next)
	sl = Slots()
	ok("set window: > = the other 34, from #41", Pg() == "2/2" and #sl == 34 and sl[1] == "|cff9d9d9d#41\194\160???|r", sl[1])
	SY.Click(B.v20)
	sl = Slots()
	ok("set window: Shart = Shartifact 1/5: 5 sounds, page 1/1, the heard one by name", B.pageHeadText.text == "Shartifact"
		and B.pageHave.text == "1/5" and #sl == 5 and Pg() == "1/1" and sl[1] == "|cff9d9d9d#1333\194\160???|r"
		and sl[3]:find("#1335\194\160|r|c%x+The Final Sputter|r$") ~= nil, tostring(sl[3]))
	W.root:Hide()
end
-- The Complete Works: the 1337 set only (the old 14 do not count)
local save = { dex = {} }
for k = 1, 14 do save.dex[snd[k].file] = { n = 1, t = 1, own = 0 } end
for k = 29, 14 + 1337 do save.dex[snd[k].file] = { n = 1, t = 1, own = 0 } end   -- 1323 of the set
V.Boot(save)
ns.AchDex()
ok("Complete Works: 14 old + 1323 set = 1323/1337, not earned", SpokenWindDB.ach.done.complete == nil
	and Row("complete").stat == "1323/1337", Row("complete").stat)
do   -- the row total = the pack sounds only: 18 x 74 + 5 = 1337 (the 14 Original are not in it)
	local d, nSet, nOrig, origSet = ns.DexNums(), 0, 0, false
	for _, p in ipairs(d.pages) do
		if p.set then nSet = nSet + #p.tiles end
		if p.name == "Original" then nOrig, origSet = #p.tiles, p.set and true or false end
	end
	local cw
	for _, r in ipairs(ns.ACH) do if r.id == "complete" then cw = r end end
	ok("Complete Works: total 1337 = 18 x 74 + 5 pack sounds, Original (14) not in it", d.setAll == 1337
		and nSet == 18 * 74 + 5 and d.all == 1337 + 14 and nOrig == 14 and not origSet and cw.dex == 1337
		and cw.rule == "Hear all 1337", d.setAll .. " " .. d.all .. " " .. nOrig)
end
V.Boot(nil)
ok("set: nothing forbidden in the block, no chat line", #forbidden == forb0 and #sent == 0, forbidden[#forbidden])
end)()

;(function()   -- 0.7.0 the 3 legend rows (voice legend tier only) + the sound label fit (no cut text)
local V = SY.V7
local forb0 = #forbidden
local PG, QG = "Player-1-0000FFFF", "Player-1-0000BBBB"
V.R = { [ME_GUID] = { "Human", 2 }, [PG] = { "Orc", 3 }, [QG] = { "Troll", 2 } }
local function D() return SpokenWindDB.ach.done end
local function Stat(id) for _, x in ipairs(ns.AchLines("social").tiles) do if x.id == id then return x.stat end end end
V.Boot(nil)
local snd, A = ns.EMOTES.FART.sounds, ns.VOX.art
ok("legend rows: with the set: not Soon, Every Wind 0/9", Stat("born") == "" and Stat("witness") == ""
	and Stat("everywind") == "0/9", Stat("born") .. " " .. Stat("everywind"))
SY.force = "leg"
local _, _, il = V.Own()
SY.force = nil
ok("legend rows: own voice legend = Born Legendary only", il and snd[il].tier == 6 and D().born ~= nil and D().witness == nil
	and D().everywind == nil and LogHas("ACH born toast=1"), il)
V.Wait(12)
V.Boot(nil)
SY.force = "leg"
local ih = V.Other(QG, "Quin")
SY.force = nil
ok("legend rows: heard voice legend = Witness only", ih and snd[ih].tier == 6 and snd[ih].race == "Troll" and D().witness ~= nil
	and D().born == nil and D().everywind == nil, ih)
V.Wait(12)
V.Boot(nil)
SY.force = "art"
V.Own()
SY.force = nil
V.Wait(12)
V.Other(PG, "Pat", V.F(PG, 1336, 1, 1))
V.Wait(12)
ns.AchPlayed("FART", 13, "k13", false, now, true)
ns.AchPlayed("FART", 13, "k13", true, now, true)
ok("legend rows: an Artifact (own + heard) and #13 Legend earn none", D().shart ~= nil and D().legend ~= nil
	and D().born == nil and D().witness == nil and D().everywind == nil)
-- Every Wind That Blows: a voice legend of all 9 races, heard or own (both bodies of one race = 1)
V.Boot(nil)
local legs = {}
for _, v in ipairs(ns.VOX.order) do legs[v.key] = v.tiers[6][1] end
local function P(i, mine)   -- a played fart as Core feeds it: AchPlayed, then the collection
	ns.AchPlayed("FART", i, "k" .. i, mine, now, true)
	ns.DexAdd("FART", i, mine and "own" or "msg")
end
P(legs.Human_m) P(legs.Human_f) P(A[1])
ok("everywind: Human M + Human F + an Artifact = 1/9", Stat("everywind") == "1/9" and D().everywind == nil, Stat("everywind"))
for _, k in ipairs({ "Dwarf_f", "NightElf_m", "Gnome_f", "Orc_m", "Scourge_f", "Tauren_m", "Skyborne_f" }) do P(legs[k]) end
ok("everywind: 8 races = 8/9, not yet", Stat("everywind") == "8/9" and D().everywind == nil, Stat("everywind"))
P(legs.Troll_m, true)
ok("everywind: the 9th race (own) = earned + Born Legendary", D().everywind ~= nil and D().born ~= nil
	and LogHas("ACH everywind toast=1") and Stat("everywind"):find("^Done ") ~= nil, Stat("everywind"))
V.Wait(12)
SY.noPacks = true
V.Boot(nil)
ns.AchPlayed("FART", 13, "k13", true, now, true)
ok("legend rows: no race set = Soon, #13 does not earn them", Stat("born") == "Soon" and Stat("witness") == "Soon"
	and Stat("everywind") == "Soon" and D().born == nil, Stat("born"))
SY.noPacks = nil

-- the sound labels: one line each (the design); the addon never shortens a name, the tip has it in full
V.Boot(nil)
do
	local pg = ns.DexNums().pages[2]
	local li = 1
	for i = 1, 40 do if #pg.tiles[i].name > #pg.tiles[li].name then li = i end end
	local lt = pg.tiles[li]
	SpokenWindDB.dex[lt.key] = { n = 1, t = clock, own = 0 }
	Slash("ach collection")
	local W, B, _, lineOf = Id.W()
	SY.Click(B.v2)
	local slot
	for _, r in ipairs(B._swRows) do
		for _, X in ipairs({ "A", "B", "C", "D" }) do
			local l = lineOf[r["s" .. X]]
			if r["s" .. X].shown and l and l.num == lt.num then slot = { s = r["s" .. X], n = r["n" .. X] } end
		end
	end
	ok("labels: the longest name of the page is set in full", slot and #lt.name >= 20
		and slot.n.text:find("#" .. lt.num .. "\194\160|r", 1, true) ~= nil and slot.n.text:find(lt.name .. "|r", 1, true) ~= nil,
		slot and slot.n.text)
	Id.on(slot.s)
	local _, title = Id.tip()
	Id.off(slot.s)
	ok("labels: the tip has the full name too", title and title:find(lt.name .. "|r", 1, true) ~= nil, title)
	W.root:Hide()
end
ok("legend rows + fit: nothing forbidden, no chat line", #forbidden == forb0 and #sent == 0, forbidden[#forbidden])
V.Wait(12)
end)()

;(function()   -- 0.7.1: the Classic tier (the old 14 for every voice, 1 in 200): wire, seed, counts, log;
-- 0.7.1 -> old clients (undo); ERR dedupe (one line per site + a count)
local V = SY.V7
local QG2, RG = "Player-1-0000D1D1", "Player-1-0000D2D2"
local function SLine(s)
	for k = #SpokenWindDB.sync, 1, -1 do
		local l = SpokenWindDB.sync[k]
		if l:find(s, 1, true) then return l end
	end
	return ""
end
local function LN(s)
	local k = 0
	for _, l in ipairs(SpokenWindDB.log) do if l:find(s, 1, true) then k = k + 1 end end
	return k
end
local function LL(s)
	for k = #SpokenWindDB.log, 1, -1 do
		local l = SpokenWindDB.log[k]
		if l:find(s, 1, true) then return l end
	end
	return ""
end
V.R = { [ME_GUID] = { "Human", 2 }, [QG2] = { "Gnome", 2 }, [RG] = { "Orc", 3 } }
V.Boot(nil)
local snd = ns.EMOTES.FART.sounds
SY.force = 13
local pool, num, i = V.Own()
ok("classic: own Classic pick (#13) = F pool 0 + the old number, plays it", pool == 0 and num == 13 and i == 13,
	tostring(pool) .. " " .. tostring(num) .. " " .. tostring(i))
local cl = SLine("CLASSIC pick")
ok("classic: a CLASSIC pick line (own=1), no names, no GUIDs", cl:find(" CLASSIC pick snd=13 own=1$") ~= nil
	and not cl:find("Player-", 1, true) and not cl:find(ME, 1, true), cl)
ok("classic: #13 from a voice = Legend Has It", ns.AchHas("legend") == true)
V.Wait(12)
SY.force = 5
i = V.Other(QG2, "Quin")
ok("classic: seed path (a voice, no addon) = the Classic sound + its line (own=0)", i == 5
	and V.SyncHas("CLASSIC pick snd=5 own=0") == 1, tostring(i))
V.Wait(12)
SY.force = nil
i = V.Other(RG, "Rae", V.F(RG, 9, 0, 1))
ok("classic: F pool 0 #9 from a voice (a 0.7.1 Classic) = that old sound", i == 9, tostring(i))
V.Wait(12)
local nCl = V.SyncHas("CLASSIC pick")
SY.force = 20
pool, num, i = V.Own()
SY.force = nil
ok("classic: a pack sound = pool 1, no CLASSIC line", pool == 1 and num == 6 and i == 20 and V.SyncHas("CLASSIC pick") == nCl,
	tostring(pool) .. " " .. tostring(num) .. " " .. V.SyncHas("CLASSIC pick"))
V.Wait(12)
for k = 1, 14 do SY.force = k V.Own() V.Wait(12) end
SY.force = nil
local dexAll = true
for k = 1, 14 do if not SpokenWindDB.dex[snd[k].file] then dexAll = false end end
ok("classic: the 14 by Classic picks = Full Orchestra + all 14 in the Collection", ns.AchHas("orchestra") == true and dexAll
	and V.NoErr(), select(2, V.NoErr()))
local SAVE = V.Copy(SpokenWindDB)   -- a 0.7.1 save (Classic plays), for the undo test below
local n0 = V.SyncHas("CLASSIC pick")
SY.force = 3
for _ = 1, 25 do ns.SyncCount("FART", QG2) end
SY.force = nil
ev.scripts.OnEvent(ev, "PLAYER_LOGOUT")
ok("classic: max 20 CLASSIC lines per session; SYNC SUM classic = all Classic picks", n0 < 20
	and V.SyncHas("CLASSIC pick") == 20 and SLine(" SYNC SUM "):find(" classic=" .. (n0 + 25) .. "$") ~= nil,
	n0 .. " " .. SLine(" SYNC SUM "))

-- 0.7.1 -> old clients (undo): the save loads; a Classic F (pool 0 #13 from a voice) = #13 Legend
local keep = ADDON_DIR
for _, v in ipairs({ "0.6.2", "0.6.3", "0.6.4", "0.6.5", "0.6.6", "0.7.0" }) do
	ADDON_DIR = ROOT .. "/tests/compat/" .. v
	local okAll, err = pcall(function()
		ev, ns = Load(V.Copy(SAVE), "vertical")
		IsInGroup = function() return true end
		IsInGuild = function() return true end
		GetPlayerInfoByGUID = V.Info
		SpokenWindDB.cd = 0
		willPlay = true
		ok(v .. " compat 0.7.1: a 0.7.1 save loads, no error", LastLog():find("BOOT v=" .. v .. " ", 1, true) ~= nil
			and V.NoErr(), select(2, V.NoErr()))
		V.Wait(5)
		local np = #plays
		local got = V.Other(RG, "Rae", V.F(RG, 13, 0, 7))
		ok(v .. " compat 0.7.1: F pool 0 #13 from a voice (a Classic pick) = #13 Legend, no error", got == 13
			and #plays == np + 1 and plays[#plays].path:find("\\13_legend%.ogg$") ~= nil and V.NoErr(), tostring(got))
	end)
	ok(v .. " compat 0.7.1: ran without a Lua error", okAll, err)
end
ADDON_DIR = keep

-- ERR dedupe: one line per site (kind + file:line) + a count; one bug cannot flush the log
V.Boot(nil)
for k = 1, 5 do ns.Log("BTN fart tgt=0 has=? " .. k) end
local E1 = "ERR rand Interface/AddOns/Spoken_Wind/Random.lua:283: bad argument #1 to 'ipairs' (table expected, got secret)"
local E2 = "ERR rand Interface/AddOns/Spoken_Wind/Random.lua:302: bad argument #1 to 'ipairs' (table expected, got secret)"
for _ = 1, 157 do ns.Log(E1) end
for _ = 1, 3 do ns.Log(E2) end
ok("errdup: 157 x one ERR = one line + x157; another site = its own line + x3", LN("Random.lua:283") == 1
	and LL("Random.lua:283"):sub(-5) == " x157" and LN("Random.lua:302") == 1 and LL("Random.lua:302"):sub(-3) == " x3",
	LL("Random.lua:283"))
ok("errdup: the 5 BTN lines stay (the flood does not push them out)", LN("BTN fart tgt=0") == 5, LN("BTN fart tgt=0"))
ns.Log("ERR rand Interface/AddOns/Spoken_Wind/Random.lua:283: other text")
ok("errdup: same kind + file:line, other text = the same site", LN("Random.lua:283") == 1
	and LL("Random.lua:283"):sub(-5) == " x158", LL("Random.lua:283"))
ns.Log("ERR art Interface/AddOns/Spoken_Wind/Random.lua:283: x")
ok("errdup: another kind, same file:line = its own line", LN("Random.lua:283") == 2 and LL("ERR art "):sub(-3) == ": x",
	LL("ERR art "))
ns.Log("ERR play boom") ns.Log("ERR play boom") ns.Log("ERR play bang")
ok("errdup: no file:line = the text is the site", LN("ERR play boom") == 1 and LL("ERR play boom"):sub(-3) == " x2"
	and LN("ERR play bang") == 1 and LL("ERR play bang"):sub(-9) == "play bang", LL("ERR play boom"))
for k = 1, 60 do ns.Log("PLAY filler " .. k) end
ns.Log("ERR play boom")
ok("errdup: first line out of the ring = one new line with the count", LN("ERR play boom") == 1
	and LL("ERR play boom"):sub(-3) == " x3" and #SpokenWindDB.log == 60, LL("ERR play boom"))
ns.Log("ERR play boom")
ok("errdup: that new line counts on", LN("ERR play boom") == 1 and LL("ERR play boom"):sub(-3) == " x4", LL("ERR play boom"))
for _ = 1, 50 do ns.SyncLog("ERR art Interface/AddOns/Spoken_Wind/Shart.lua:86: boom") end
ok("errdup: the sync ring too", V.SyncHas("Shart.lua:86") == 1 and SLine("Shart.lua:86"):sub(-4) == " x50", SLine("Shart.lua:86"))
ns.Log("ERR heard Interface/AddOns/Spoken_Wind/Heard.lua:9: both")
ns.SyncLog("ERR heard Interface/AddOns/Spoken_Wind/Heard.lua:9: both")
ok("errdup: one ERR in both logs = its first line in each (no count)", LN("Heard.lua:9") == 1
	and LL("Heard.lua:9"):sub(-4) == "both" and V.SyncHas("Heard.lua:9") == 1 and SLine("Heard.lua:9"):sub(-4) == "both",
	SLine("Heard.lua:9"))
V.Boot(nil)
for k = 1, 25 do for _ = 1, 2 do ns.Log(("ERR s%d a.lua:%d: x"):format(k, k)) end end
local c1, c2 = 0, 0
for k = 1, 25 do
	local key = ("ERR s%d a.lua:%d:"):format(k, k)
	if k <= 20 and LN(key) == 1 and LL(key):sub(-3) == " x2" then c1 = c1 + 1 end
	if k > 20 and LN(key) == 2 then c2 = c2 + 1 end
end
ok("errdup: 20 sites with a count per log, then plain lines (bounded)", c1 == 20 and c2 == 5, c1 .. " " .. c2)
V.R = {}
GetPlayerInfoByGUID, IsInGroup, IsInGuild = nil, nil, nil
SY.force = nil
end)()


;(function()   -- 0.7.0 -> old clients (undo): pack F messages + a 0.7.0 save on 0.6.2-0.6.6 (tests/compat/<v>)
local V = SY.V7
local keep = ADDON_DIR
local PG, RG, RG2, RG3 = "Player-1-0000FFFF", "Player-1-0000CCCC", "Player-1-0000C2C2", "Player-1-0000C3C3"
-- a 0.7.0 save: own race sounds + an own shart (collection, fart log, picks, tiers), a heard shart (the row)
V.R = { [ME_GUID] = { "Human", 2 }, [PG] = { "Orc", 3 } }
V.Boot(nil)
V.Own() V.Wait(12)
SY.force = "art" V.Own() SY.force = nil V.Wait(12)
V.Other(PG, "Pat", V.F(PG, 1336, 1, 1)) V.Wait(12)
local SAVE = V.Copy(SpokenWindDB)
local packKey
for k in pairs(SAVE.dex) do if k:find("^human_m_") then packKey = k end end
ok("compat 0.7.0: the save has the 0.7.0 rows", packKey and SAVE.dex.artifact_floodgate and next(SAVE.artPick)
	and SAVE.ach.done.shart and SAVE.farts[#SAVE.farts].snd > 14 and V.NoErr(), select(2, V.NoErr()))
for _, v in ipairs({ "0.6.2", "0.6.3", "0.6.4", "0.6.5", "0.6.6" }) do
	ADDON_DIR = ROOT .. "/tests/compat/" .. v
	local okAll, err = pcall(function()
		ev, ns = Load(V.Copy(SAVE), "vertical")
		IsInGroup = function() return true end
		IsInGuild = function() return true end
		GetPlayerInfoByGUID = V.Info
		V.R = { [ME_GUID] = { "Human", 2 }, [RG] = { "Human", 2 }, [RG2] = { "Orc", 3 }, [RG3] = { "Troll", 2 } }
		SpokenWindDB.cd = 0
		willPlay = true
		ok(v .. " compat 0.7.0: a 0.7.0 save loads, no error", LastLog():find("BOOT v=" .. v .. " ", 1, true) ~= nil and V.NoErr(),
			select(2, V.NoErr()))
		V.Wait(5)
		for k, c in ipairs({ { RG, "Rae", 500, 1 }, { RG2, "Oza", 20, 0 }, { RG3, "Tik", 1337, 1 } }) do
			local np, na, nc = #plays, #SY.asent, #sent
			V.Msg(V.F(c[1], c[3], c[4], k), c[2])
			now = now + 0.04
			ev.scripts.OnEvent(ev, "CHAT_MSG_TEXT_EMOTE", FartBy(c[2]), c[2], "", "", "", "", 0, 0, "", 0, 123, c[1])
			V.Wait(0.3)
			local path = plays[#plays] and plays[#plays].path or ""
			ok(("%s compat 0.7.0: F pool %d #%d dropped, the emote plays an old sound (seed)"):format(v, c[4], c[3]),
				#plays == np + 1 and path:find("\\%d%d_[^\\]*%.ogg$") ~= nil and V.NoErr(), path)
			V.Wait(12)
			ok(("%s compat 0.7.0: F pool %d #%d: no send, no error"):format(v, c[4], c[3]), #SY.asent == na and #sent == nc
				and V.NoErr(), select(2, V.NoErr()))
		end
		local okF = pcall(ns.FartLogLines, 10)
		local okA = not ns.AchLines or (pcall(ns.AchLines, "collection") and pcall(ns.AchLines, "classic"))
		ok(v .. " compat 0.7.0: fart log + achievements read the 0.7.0 rows", okF and okA and V.NoErr(), select(2, V.NoErr()))
		ok(v .. " compat 0.7.0: undo keeps the 0.7.0 keys (picks, pack collection keys)", type(SpokenWindDB.artPick) == "table"
			and next(SpokenWindDB.artPick) ~= nil and SpokenWindDB.dex[packKey] ~= nil and SpokenWindDB.dex.artifact_floodgate ~= nil)
		if not (SpokenWindDB.ach and SpokenWindDB.ach.done and SpokenWindDB.ach.done.shart) then
			out(v .. " compat 0.7.0: note: the hidden row is dropped by this build (earned again on the next shart)")
		end
	end)
	ok(v .. " compat 0.7.0: ran without a Lua error", okAll, err)
end
ADDON_DIR = keep
V.R = {}
GetPlayerInfoByGUID, IsInGroup, IsInGuild, issecretvalue = nil, nil, nil, nil
SY.force, SY.V7 = nil, nil
end)()

-- nothing forbidden, no stray globals
ok("no forbidden calls", #forbidden == 0, forbidden[1])
local stray = {}
for key in pairs(_G) do
	if not BASE[key] and not key:match("^SLASH_SPOKENWIND_%u+1$") and not (key:match("^SpokenWind%u%a*$") and SY.own[_G[key]])
		and not ({ SpokenWindDB = 1, SLASH_SPOKENWIND1 = 1, SLASH_SPOKENWIND2 = 1, SlashCmdList = 1,
		CreateFrame = 1, GetTime = 1, date = 1, time = 1, PlaySoundFile = 1, UnitGUID = 1, UnitName = 1, GetLocale = 1,
		EMOTE41_TOKEN = 1, EMOTE41_CMD1 = 1, SetCVar = 1, hooksecurefunc = 1, SendChatMessage = 1, DoEmote = 1,
		RunMacroText = 1, CastSpellByName = 1, UseAction = 1, SetBinding = 1, Settings = 1,
		MinimalSliderWithSteppersMixin = 1, CreateSettingsButtonInitializer = 1, InterfaceOptions_AddCategory = 1,
		CreateSettingsListSectionHeaderInitializer = 1, UIParent = 1, BackdropTemplateMixin = 1, BNToastFrame = 1,
		ChatFrame1 = 1, InCombatLockdown = 1, IsLoggedIn = 1, ITEM_QUALITY_COLORS = 1, BACKDROP_TOAST_12_12 = 1, SetBindingClick = 1,
		SetOverrideBinding = 1, SetOverrideBindingClick = 1,
		GetServerTime = 1, C_Timer = 1, C_ChatInfo = 1, IsInGroup = 1, IsInRaid = 1, IsInGuild = 1, IsInInstance = 1,
		GetPlayerInfoByGUID = 1, UnitFactionGroup = 1, C_CreatureInfo = 1, RegisterAddonMessagePrefix = 1,
		SendAddonMessage = 1, issecretvalue = 1, PlaySound = 1, SOUNDKIT = 1,
	})[key] then
		stray[#stray + 1] = key
	end
end
ok("no stray globals", #stray == 0, table.concat(stray, ","))

print = out
print(("core: %d pass, %d fail (dev folder: %s)"):format(pass, fail, HAVE_DEV and "yes" or "no"))
if fail > 0 then error("core tests failed") end
