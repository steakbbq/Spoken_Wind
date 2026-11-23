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

local function Mock()
	local f = { scripts = {}, events = {}, strings = {}, textures = {}, visible = false, shown = true }
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
		return t
	end
	function f:GetHeight() return self.height or 0 end
	function f:GetWidth() return self.width or 0 end
	function f:IsVisible() return self.visible end
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
		return fs
	end
	return f
end

-- The game's Settings API, as far as Options.lua uses it.
-- mode: "vertical" (this client), "error" (vertical API breaks), "canvas" (no
-- vertical API), "old" (no Settings, InterfaceOptions only), "none" (nothing).
local function MockSettings(mode)
	reg = { list = {}, byVar = {}, controls = {}, buttons = {}, cats = {}, canvas = {}, subs = {} }
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
			return { frame = f, name = name }
		end,
		RegisterAddOnCategory = function(c) reg.cats[#reg.cats + 1] = c end,
	}
	if mode == "canvas" then return end
	if mode ~= "nosub" then
		Settings.RegisterCanvasLayoutSubcategory = function(parent, f, name)
			local c = { parent = parent, frame = f, name = name }
			reg.subs[#reg.subs + 1] = c
			return c
		end
	end
	Settings.RegisterVerticalLayoutCategory = function(name)
		local layout = { inits = {} }
		function layout:AddInitializer(i) self.inits[#self.inits + 1] = i end
		reg.cat, reg.layout = { name = name }, layout
		return reg.cat, layout
	end
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
local devProbe = io.open(DEV_DIR .. "/Dev.lua", "rb")
local HAVE_DEV = devProbe ~= nil
if devProbe then devProbe:close() end

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
local function Load(db, mode, dev)
	now, plays, prints, frames = 1000, {}, {}, {}
	forbidden = forbidden or {}   -- kept over every load: checked once at the end
	clock = CLOCK0
	SPOKEN_WIND_DEV, SPOKEN_WIND_DEV_TOOLS = nil, nil
	SpokenWindDB = db
	SLASH_SPOKENWIND1, SLASH_SPOKENWIND2, SlashCmdList = nil, nil, {}
	CreateFrame = function(kind, name, parent, tmpl)
		if name then forbidden[#forbidden + 1] = "CreateFrame named" end
		local own = false   -- a child of one of our own frames is OK
		for _, x in ipairs(frames) do if x == parent then own = true end end
		if parent ~= nil and parent ~= UIParent and not own then forbidden[#forbidden + 1] = "CreateFrame parented" end
		if tmpl ~= nil and tmpl ~= "BackdropTemplate" then forbidden[#forbidden + 1] = "CreateFrame " .. tostring(tmpl) end
		if kind ~= "Frame" then forbidden[#forbidden + 1] = "CreateFrame " .. tostring(kind) end   -- no ScrollFrame
		local f = Mock() f.parent, f.tmpl = parent, tmpl frames[#frames + 1] = f return f
	end
	UIParent = { GetEffectiveScale = function() return 1 end, GetWidth = function() return 1365 end,
		GetHeight = function() return 768 end }
	BackdropTemplateMixin = {}
	BNToastFrame, bnState = BNMock()
	ChatFrame1 = { GetLeft = function() return 32 end, GetTop = function() return 300 end,
		GetEffectiveScale = function() return 1 end }
	combat = false
	InCombatLockdown = function() return combat end
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
	hooksecurefunc = function(a, b, c)   -- only the game's 2 emote calls: never a frame, never anything else
		if a == "DoEmote" and type(b) == "function" and c == nil and not SY.hooks.DoEmote then SY.hooks.DoEmote = b
		elseif a ~= nil and a == C_ChatInfo and b == "PerformEmote" and type(c) == "function" and not SY.hooks.PerformEmote then
			SY.hooks.PerformEmote = c
		else forbidden[#forbidden + 1] = "hooksecurefunc " .. tostring(a) .. " " .. tostring(b) end
	end
	if SY.noApi then C_ChatInfo, hooksecurefunc = nil, nil end
	MockSettings(mode or "vertical")
	local ns = {}
	local toc = assert(io.open(ADDON_DIR .. "/Spoken_Wind.toc", "rb")):read("*a")
	local files = {}
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line:match("%S") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
	end
	for _, file in ipairs(files) do   -- SY.noPacks: the race packs do not load (= the old 14 only)
		if not (SY.noPacks and file:find("^Packs[\\/]")) then assert(loadfile(ADDON_DIR .. "/" .. file))("Spoken_Wind", ns) end
	end
	local ev = frames[1]
	ev.scripts.OnEvent(ev, "ADDON_LOADED", "SomethingElse")
	ev.scripts.OnEvent(ev, "ADDON_LOADED", "Spoken_Wind")
	if dev then
		if HAVE_DEV then assert(loadfile(DEV_DIR .. "/Dev.lua"))("Spoken_Wind_Dev", {}) else SPOKEN_WIND_DEV = true end
	end
	if preLogin then preLogin(ns) end   -- other addons (loaded before login)
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
	"Emotes.lua,Lengths.lua,Packs\\human.lua,Packs\\dwarf.lua,Packs\\nightelf.lua,Packs\\gnome.lua,Packs\\orc.lua,"
		.. "Packs\\scourge.lua,Packs\\tauren.lua,Packs\\troll.lua,Packs\\skyborne.lua,Packs\\artifact.lua,Voices.lua,"
		.. "Match.lua,Pick.lua,Changelog.lua,FartLog.lua,Achievements.lua,Toast.lua,Rewards.lua,Button.lua,Random.lua,Shart.lua,Sync.lua,Heard.lua,Board.lua,Collection.lua,TestMode.lua,Core.lua,Options.lua",
	table.concat(files, ","))
ok("toc title", toc:find("## Title: Spoken Wind\r?\n") ~= nil)
ok("toc version 0.7.0", toc:find("## Version: 0.7.0\r?\n") ~= nil)
ok("toc no X- keys", not toc:find("##%s*[Xx]%-"))
local ALLOWED = { Interface = 1, Title = 1, Notes = 1, Version = 1, SavedVariables = 1 }
local keys = 0
for line in toc:gmatch("[^\r\n]+") do
	if line:match("^##") then
		keys = keys + 1
		local key = line:match("^##%s*([^:]+):")
		ok("toc key allowed: " .. tostring(key), key and ALLOWED[key], line)
	end
end
ok("toc 5 keys", keys == 5, keys)
ok("toc no deps", not toc:find("Dep") and not toc:find("Spoken_%u") and not toc:find("Spoken%u%l+Audio"))
ok("toc no dev file", not toc:find("Dev"))
ok("five frames (events + fart log + changelog + Rewards button + Fart button)", #frames == 5 and frames[1].scripts.OnEvent ~= nil
	and frames[4] == ns.RewardFrames() and frames[5] == ns.BtnFrame(), #frames)
ok("chat event on", ev.events.CHAT_MSG_TEXT_EMOTE == true)
ok("reward event on", ev.events.CHAT_MSG_EMOTE == true)
ok("addon_loaded off after load", ev.events.ADDON_LOADED == nil)
ok("defaults", SpokenWindDB.on == true and SpokenWindDB.ch == "SFX" and SpokenWindDB.self == true
	and SpokenWindDB.cd == 1 and SpokenWindDB.wait == 150)
ok("new install: cd 1, move flag set, no move line", SpokenWindDB.cdMove == true and not LogHas("CD move"))
ok("slash", SLASH_SPOKENWIND1 == "/wind" and SLASH_SPOKENWIND2 == "/spokenwind"
	and type(SlashCmdList.SPOKENWIND) == "function")
ok("boot line", LogHas("BOOT v=0.7.0 loc=enUS emotes=FART:checked:/fart slash=/wind clash=0 panel=vertical log=page flog=page farts=0 ach=button done=0 rw=15 btn=1 sync=1/2 wait=150 tm=1 on=1 ch=SFX self=1 cd=1 n=1351 len=1351/1351 dex=0 own=0 heard=0 people=0 best=0 legend=0 legendHeard=0 reply=1 char=0/0/0 all=0/0/1 tiers=0.0.0.0.0.0.0 alltiers=0.0.0.0.0.0.0 board=0 hide=0 seen=? win=0 rnd=1 tgt=0 aur=0 rev=12 dev=0 set=1337 vms=0 vox=- vbad=0 art=5 apk=0"),
	LastLog())
ok("no prints at load", #prints == 0, prints[1])
ok("public: no dev flag", SPOKEN_WIND_DEV == nil)
ev.scripts.OnEvent(ev, "PLAYER_LOGIN")   -- a second login event never builds a second page
ok("page built once", #reg.cats == 1 and #reg.subs == 2 and #frames == 5, #reg.cats)

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

-- ---------------------------------------------------------------- options page
ok("page registered", reg.cats[1] == reg.cat and reg.cat.name == "Spoken Wind")
ok("7 settings", #reg.list == 7, #reg.list)
for key, def in pairs(DEF) do
	local s = reg.byVar["SpokenWind_" .. key]
	ok("setting " .. key .. " exists", s ~= nil)
	if s then
		ok("setting " .. key .. " writes db key " .. key, s.key == key and s.tbl == SpokenWindDB, tostring(s.key))
		ok("setting " .. key .. " default", s.default == def and s.vtype == type(def), tostring(s.default))
		ok("setting " .. key .. " = db", s:GetValue() == SpokenWindDB[key])
	end
end
local kinds = {}
for _, c in ipairs(reg.controls) do kinds[#kinds + 1] = c.kind .. ":" .. c.s.key end
ok("controls", table.concat(kinds, ",") == "check:on,check:rwbtn,list:ch,check:self,check:random,slider:cd,slider:wait", table.concat(kinds, ","))
local slider = reg.controls[6]
ok("slider 0-30 step 0.5", slider and slider.o.min == 0 and slider.o.max == 30 and slider.o.step == 0.5)
ok("slider label", slider and slider.o.fmt and slider.o.fmt(2) == "2s" and slider.o.fmt(1.5) == "1.5s")
local wslider = reg.controls[7]
ok("wait slider 0-300 step 10", wslider and wslider.o.min == 0 and wslider.o.max == 300 and wslider.o.step == 10)
ok("wait slider label", wslider and wslider.o.fmt and wslider.o.fmt(150) == "150 ms", wslider and wslider.o.fmt and wslider.o.fmt(150))
local list = reg.controls[3]
local vals = {}
for _, d in ipairs(list and list.opts() or {}) do vals[#vals + 1] = d.value .. "=" .. d.label end
ok("channel list", table.concat(vals, ",") == "Master=Master,SFX=SFX,Dialog=Dialog", table.concat(vals, ","))
local names = {}
for _, s in ipairs(reg.list) do
	names[#names + 1] = s.name
	ok("label short " .. s.name, #s.name <= 20)
end
ok("labels", table.concat(names, ",") == "On,Rewards button,Channel,Own /fart,Random farts,Cooldown per person,Sync wait", table.concat(names, ","))
for _, c in ipairs(reg.controls) do
	ok("tip terse " .. c.s.key, type(c.tip) == "string" and #c.tip <= 40 and not c.tip:find("%.$"), c.tip)
end
ok("public: one button = Achievements, no Test", #reg.buttons == 1 and reg.buttons[1].name == "Achievements"
	and reg.buttons[1].text == "Open" and reg.buttons[1].tags == false and #reg.buttons[1].tip <= 40
	and #reg.layout.inits == 1 and reg.layout.inits[1] == reg.buttons[1], #reg.buttons)
ok("public: no achievements sub-page", (function()
	for _, c in ipairs(reg.subs) do if c.name == "Achievements" then return false end end
	return true
end)())
ok("no prints from page build", #prints == 0)

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
ok("changelog 0.7.0", CL[1].v == "0.7.0" and table.concat(CL[1], ",") == "Race voices: 74 per race and body,Collection pages per voice", table.concat(CL[1], ","))
ok("changelog 0.6.6", CL[2].v == "0.6.6" and table.concat(CL[2], ",") == "Random farts: 1 per hour,Wake-up fart,/wind random off", table.concat(CL[2], ","))
ok("changelog 0.6.5", CL[3].v == "0.6.5" and table.concat(CL[3], ",") == "Fart button", table.concat(CL[3], ","))
ok("changelog 0.6.4", CL[4].v == "0.6.4" and table.concat(CL[4], ",") == "Board tab,All players,Rarity rows,/wind board off", table.concat(CL[4], ","))
ok("changelog 0.6.3", CL[5].v == "0.6.3" and table.concat(CL[5], ",") == "Collection tab,5 new achievements,Click a sound = play,One sound per person")
ok("changelog 0.6.2.1", CL[6] and CL[6].v == "0.6.2.1" and table.concat(CL[6], ",") == "Toast text centered,Toast click = window,Earned first by rarity",
	table.concat(CL[5], ","))
ok("changelog 0.6.2", CL[7] and CL[7].v == "0.6.2" and table.concat(CL[7], ",") == "Heard count,Farts · Heard · People,Achievements window,17 Social achievements")
ok("changelog 0.6.1", CL[8] and CL[8].v == "0.6.1" and table.concat(CL[8], ",") == "Pair test: /wind pair,Bigger toast + sound")
ok("changelog 0.6.0", CL[9] and CL[9].v == "0.6.0" and table.concat(CL[9], ",") == "Same fart for all,Sync wait 0-300ms")
ok("changelog 0.5.0", CL[10] and CL[10].v == "0.5.0" and table.concat(CL[10], ",") == "15 reward emotes,Rewards button")
ok("changelog 0.4.1", CL[11] and CL[11].v == "0.4.1" and table.concat(CL[11], ",") == "Bigger icons,Clearer Machine Gun,Cooldown 1s,Dev: 1 secret")
ok("changelog 0.4.0", CL[12] and CL[12].v == "0.4.0" and table.concat(CL[12], ",") == "15 achievements,Toasts,Icons by the author")
ok("changelog 0.3.0", CL[13] and CL[13].v == "0.3.0" and table.concat(CL[13], ",") == "Fart log")
ok("changelog 0.2.1", CL[14] and CL[14].v == "0.2.1" and table.concat(CL[14], ",") == "Test: dev only")
ok("changelog 0.2.0", CL[15] and CL[15].v == "0.2.0" and table.concat(CL[15], ",") == "Cooldown per person,Options page,Changelog")
ok("changelog 0.1.0", CL[16] and CL[16].v == "0.1.0" and table.concat(CL[16], ",") == "First release,14 toots,/wind commands")
local sub = reg.subs[2]
ok("changelog sub-page last", #reg.subs == 2 and sub.parent == reg.cat and sub.name == "Changelog")
local texts, lowest = {}, 0
for _, fs in ipairs(sub and sub.frame.strings or {}) do
	texts[#texts + 1] = fs.text
	if fs.y then lowest = math.min(lowest, fs.y) end
end
ok("changelog page text", table.concat(texts, "|") ==
	"Changelog|0.7.0|· Race voices: 74 per race and body|· Collection pages per voice|0.6.6|· Random farts: 1 per hour|· Wake-up fart|· /wind random off|0.6.5|· Fart button|0.6.4|· Board tab|· All players|· Rarity rows|· /wind board off|0.6.3|· Collection tab|· 5 new achievements|· Click a sound = play|· One sound per person|0.6.2.1|· Toast text centered|· Toast click = window|· Earned first by rarity|+10 older",
	table.concat(texts, "|"))
ok("changelog version gold, lines white", sub and sub.frame.strings[2].font == "GameFontNormal"
	and sub.frame.strings[3].font == "GameFontHighlight")
ok("changelog lines indented", sub and sub.frame.strings[3].x > sub.frame.strings[2].x)
ok("changelog fits (no scroll)", lowest >= -472, lowest)
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

-- page fallbacks: vertical API breaks / missing / old client / nothing
for _, case in ipairs({ { "error", "canvas" }, { "canvas", "canvas" }, { "old", "canvas" }, { "none", "none" } }) do
	ev, ns = Load(SpokenWindDB, case[1])
	ok("fallback " .. case[1] .. " -> panel=" .. case[2], LastLog():find("panel=" .. case[2] .. " ", 1, true), LastLog())
	ok("fallback " .. case[1] .. " no ERR", not LastLog():find("ERR", 1, true))
	ok("fallback " .. case[1] .. " flog=none", LastLog():find(" flog=none ", 1, true), LastLog())
	ok("fallback " .. case[1] .. " ach=none", LastLog():find(" ach=none ", 1, true), LastLog())
	ok("fallback " .. case[1] .. " no page settings", ns.panelSettings == nil)
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
	else
		ok("fallback none log=none", LastLog():find(" log=none ", 1, true), LastLog())
	end
	Slash("cd 4")
	ok("fallback " .. case[1] .. " /wind still sets", SpokenWindDB.cd == 4 and LastLog():find("OPT cd=4 by=slash", 1, true))
	plays = {}
	now = now + 10
	Emote(OTHER_FART, "Bob", BOB)
	ok("fallback " .. case[1] .. " still plays", #plays == 1)
	Slash("cd 2")
end

-- no sub-page API: changelog as section rows at the bottom of the main page
ev, ns = Load(SpokenWindDB, "nosub")
ok("nosub: panel=vertical log=section", LastLog():find("panel=vertical log=section ", 1, true), LastLog())
local heads = {}
for _, i in ipairs(reg.layout.inits) do if i.header then heads[#heads + 1] = i.header end end
ok("nosub: changelog rows", table.concat(heads, "|") ==
	"Changelog|0.7.0|· Race voices: 74 per race and body|· Collection pages per voice|0.6.6|· Random farts: 1 per hour|· Wake-up fart|· /wind random off|0.6.5|· Fart button|0.6.4|· Board tab|· All players|· Rarity rows|· /wind board off|0.6.3|· Collection tab|· 5 new achievements|· Click a sound = play|· One sound per person|0.6.2.1|· Toast text centered|· Toast click = window|· Earned first by rarity|+10 older",
	table.concat(heads, "|"))
ok("nosub: changelog rows + the Achievements button (public)", #reg.buttons == 1 and reg.buttons[1].name == "Achievements"
	and #reg.layout.inits == 26, #reg.layout.inits)
ok("nosub: no fart log page", #reg.subs == 0 and LastLog():find(" flog=none ", 1, true), LastLog())
ok("nosub: Achievements button", LastLog():find(" ach=button done=", 1, true), LastLog())
ok("nosub: settings still work", ns.panelSettings and ns.panelSettings.cd ~= nil)

-- ---------------------------------------------------------------- dev folder (never shipped)
-- Spoken_Wind_Dev sets SPOKEN_WIND_DEV after Spoken Wind's ADDON_LOADED. Only
-- then: the Test button on the page, /wind test, "test" in the help line.
if HAVE_DEV then
	local dtoc = assert(io.open(DEV_DIR .. "/Spoken_Wind_Dev.toc", "rb")):read("*a")
	local dfiles = {}
	for line in dtoc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line:match("%S") then dfiles[#dfiles + 1] = line:match("^%s*(.-)%s*$") end
	end
	ok("dev toc: one file Dev.lua", table.concat(dfiles, ",") == "Dev.lua", table.concat(dfiles, ","))
	ok("dev toc: loads after Spoken_Wind", dtoc:find("## Dependencies: Spoken_Wind\r?\n") ~= nil)
	ok("dev toc: same Interface", dtoc:match("## Interface: ([^\r\n]+)") == toc:match("## Interface: ([^\r\n]+)"))
	ok("dev toc: no saves", not dtoc:find("SavedVariables"))
end
ev, ns = Load(SpokenWindDB, "vertical", true)
ok("dev: BOOT dev=1", LastLog():find(" dev=1 set=%d+ "), LastLog())
local btn = reg.buttons[2]
ok("dev: test button after Achievements", #reg.buttons == 2 and btn.name == "Test" and btn.text == "Play"
	and reg.layout.inits[2] == btn and reg.buttons[1].name == "Achievements" and reg.layout.inits[1] == reg.buttons[1])
ok("dev: test button no search tags", btn and btn.tags == false)
ok("dev: still 7 settings", #reg.list == 7, #reg.list)
-- Test button: plays (even when off), logs, one line
Slash("off")
plays, b = {}, #prints
local nf = #SpokenWindDB.farts
if btn then btn.fn() end
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
-- Every fart that got a sound: newest first, totals today / all, 200 kept,
-- the page shows what fits then "+N older", no scroll bar, names without realm.
ev, ns = Load(nil)
local FL
for _, c in ipairs(reg.subs) do if c.name == "Fart log" then FL = c end end
ok("fart log sub-page first", FL and FL.parent == reg.cat and reg.subs[1] == FL and reg.subs[2].name == "Changelog")
ok("fart log BOOT", LastLog():find(" log=page flog=page farts=0 ", 1, true), LastLog())
local function Page()   -- shown text on the fart log page, title first
	local t = {}
	for _, fs in ipairs(FL and FL.frame.strings or {}) do if fs.shown and fs.text ~= "" then t[#t + 1] = fs.text end end
	return t
end
local function Low()    -- y of the lowest shown line
	local y = 0
	for _, fs in ipairs(FL and FL.frame.strings or {}) do if fs.shown and fs.text ~= "" then y = math.min(y, fs.y) end end
	return y
end
local function Show() if FL then FL.frame.scripts.OnShow(FL.frame) end end
local function Nm(r) return ns.EMOTES.FART.sounds[r.snd].name end
Show()
ok("fart log empty", table.concat(Page(), "|") == "Fart log|Today 0 · All 0|None yet", table.concat(Page(), "|"))
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
local hm = os.date("%H:%M", clock)
ok("fart log page", table.concat(Page(), "|") == "Fart log|Today 2 · All 2|" .. hm .. " · you · #" .. F[2].snd .. " "
	.. Nm(F[2]) .. "|" .. hm .. " · Bob · #" .. F[1].snd .. " " .. Nm(F[1]), table.concat(Page(), "|"))
ok("fart log fonts", FL and FL.frame.strings[2].font == "GameFontNormal" and FL.frame.strings[3].font == "GameFontHighlight")
-- open page: a new fart shows at once
FL.frame.visible = true
now = now + 10
Emote(ANN_FART, "Ann", ANN)
ok("fart log live", Page()[3] and Page()[3]:find(" · Ann · #", 1, true) and Page()[2] == "Today 3 · All 3", Page()[3])
FL.frame.visible = false
-- next day: today starts at 0, older rows show the date
clock = clock + 86400
Show()
ok("new day: today 0", Page()[2] == "Today 0 · All 3", Page()[2])
ok("new day: old rows dated", Page()[3] == os.date("%m-%d %H:%M", CLOCK0) .. " · Ann · #" .. F[3].snd .. " " .. Nm(F[3]),
	Page()[3])
now = now + 10
Emote(ANN_FART, "Ann", ANN)
Show()
ok("new day: counts", Page()[2] == "Today 1 · All 4", Page()[2])
ok("new day: new row time only", Page()[3]:find("^%d%d:%d%d · Ann · #"), Page()[3])
-- secret sender name (newer clients): logged as ?
issecretvalue = function(v) return v == "SECRET" end
now = now + 10
Emote(OTHER_FART, "SECRET", "Player-1-S1")
ok("secret name -> ?", F[#F].who == "?", F[#F].who)
issecretvalue = nil
-- 250 more: 200 kept, all counted, page = 26 rows + "+N older", fits, no new frames
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
local pg = Page()
ok("fart log page: 26 rows + older", #pg == 29 and pg[#pg] == "+174 older", #pg .. " " .. tostring(pg[#pg]))
ok("fart log page: newest first", pg[3]:find(" · Bob · #", 1, true) and SpokenWindDB.farts[200].who == "Bob")
ok("fart log page fits", Low() >= -472, Low())
ok("fart log: font strings reused", #FL.frame.strings <= 29, #FL.frame.strings)
ok("fart log: no new frames", #frames == 6, #frames)   -- events + 2 pages + the Rewards + Fart buttons + the toast
-- a short page: fewer rows, still no scroll bar
FL.frame.height = 300
Show()
pg = Page()
ok("short page: fits 300 px", Low() - 16 >= -300 and pg[#pg]:find("^%+%d+ older$"), Low())
ok("short page: rows hidden, not left over", #pg == 17, #pg)   -- title + totals + 14 rows + older
FL.frame.height = nil
Show()
ok("tall again", #Page() == 29, #Page())
-- room for race voices later: a row with race shows it last
SpokenWindDB.farts[200].race = "Orc"
Show()
ok("fart log race slot", Page()[3]:find(" · Orc$"), Page()[3])
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
function Id.tile(id)   -- the shown window tile of row id, and its spot
	for i, c in ipairs(select(3, ns.AchFrames()) or {}) do
		if c.shown and c.line and c.line.id == id then return c, i end
	end
end
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
;(function()   -- the window: own frame, tabs, 92 px tiles, no scroll bar, grows down
	ok("ach window: not built at load", ns.AchFrames() == nil)
	b = #prints
	reg.buttons[1].fn()   -- the Options button
	local W, TB, TL, TIP, ST = ns.AchFrames()
	ok("ach window: the Options button opens it", W ~= nil and W.shown and LastLog():find("ACH open tab=classic n=15$"), LastLog())
	ok("ach window: no chat line", #prints == b, prints[#prints])
	ok("ach window: own frame on UIParent, backdrop, over other frames, clamped", W.parent == UIParent
		and W.tmpl == "BackdropTemplate" and W.strata == "FULLSCREEN_DIALOG" and W.clamped == true and W.mouse == true)
	local AW = ns.ACH_WIN
	ok("ach window: 5 columns of 112 px, 612 wide", AW.cols == 5 and AW.cellW == 112 and W.w == 612 and AW.w == 612, W.w)
	ok("ach window: 15 tiles = 3 rows + the stats strip", W.h == ns.AchWinH(15, true)
		and W.h == 14 + 24 + 18 + 3 * 124 + 2 * 6 + 14, W.h)
	ok("ach window: default spot: top center", W.point[1] == "TOP" and W.point[2] == UIParent and W.point[5] == -120)
	ok("ach window: 15 tiles", #TL == 15, #TL)
	local fit, grey, big = true, true, true
	for i, c in ipairs(TL) do
		local x, y = c.point[4], c.point[5]
		if c.point[1] ~= "TOPLEFT" or c.point[2] ~= W or x < AW.pad or x + c.w > W.w - AW.pad or y - c.h < -(W.h - AW.pad) then
			fit = false
		end
		if c.icon.w ~= 92 or c.icon.h ~= 92 or c.ring.w ~= 92 or c.ring.h ~= 92 or c.w ~= 112 or c.h ~= 124 then big = false end
		if not c.icon.desat or not Near(c.ring.vc, 0x9d, 0x9d, 0x9d) or c.ring.path ~= ns.ACH_RING
			or c.name.text ~= "|cff9d9d9d" .. A[i].name .. "|r" or c.icon.path ~= ns.AchIcon(A[i]) then
			grey = false
		end
	end
	ok("ach window: tiles inside the window (no scroll bar)", fit)
	ok("ach window: icon + ring 92 px, cell 112 x 124", big, TL[1].icon.w)
	ok("ach window: locked = grey icon, grey ring, grey name", grey, TL[1].name.text)
	ok("ach window: 5 per row, the next row lower", TL[5].point[5] == TL[1].point[5] and TL[6].point[4] == TL[1].point[4]
		and TL[6].point[5] == TL[1].point[5] - (AW.cellH + AW.gap) and TL[2].point[4] == TL[1].point[4] + AW.cellW + AW.gap)
	ok("ach window: name under the icon", TL[1].name.y == -(92 + 4) and TL[1].name.width == 112 and TL[1].name.wrap == true)
	ok("ach window: tabs: Classic gold + line, Social grey", TB[1].text.text == "|cffffd100Classic 0/15|r"
		and TB[1].line.shown and TB[2].text.text == "|cff9d9d9dSocial 0/14|r" and not TB[2].line.shown, TB[2].text.text)
	ok("ach window: stats strip", ST.text == "Farts 0 · Heard 0 · People 0 · Legend 0", ST.text)
	ok("ach window: a tile click does nothing (never an emote)", TL[1].scripts.OnMouseUp == nil
		and TL[1].scripts.OnMouseDown == nil and TL[1].scripts.OnClick == nil)
	-- hover: own tip (name, rule, progress, reward)
	TL[1].scripts.OnEnter(TL[1])
	TIP = select(4, ns.AchFrames())
	local function Tip()
		local t = {}
		for _, fs in ipairs(TIP.lines) do if fs.shown then t[#t + 1] = fs.text end end
		return table.concat(t, "|")
	end
	ok("ach tip: name grey, rule, reward", TIP.shown and Tip() == "|cff9d9d9dSuper Legendary|r|Hear the super legendary fart|"
		.. "|cffffd100Reward /superfart|r", Tip())
	ok("ach tip: own frame, tooltip strata, fits its lines", TIP.parent == UIParent and TIP.strata == "TOOLTIP"
		and TIP.h == 16 + 3 * 14 and TIP.point[1] == "TOPLEFT" and TIP.point[2] == TL[1], TIP.h)
	TL[3].scripts.OnEnter(TL[3])
	ok("ach tip: progress line", Tip() == "|cff9d9d9dFull Orchestra|r|Hear all 14 sounds|0/14|"
		.. "|cffffd100Reward /orchestra|r" and TIP.h == 16 + 4 * 14, Tip())
	TL[3].scripts.OnLeave(TL[3])
	ok("ach tip: hides on leave", not TIP.shown)
	-- tabs
	TL[1].scripts.OnEnter(TL[1])
	TB[2].scripts.OnMouseUp(TB[2], "RightButton")
	ok("ach tab: right click does nothing", TB[1].line.shown and TIP.shown)
	TB[2].scripts.OnMouseUp(TB[2], "LeftButton")
	ok("ach tab: Social: 14 tiles, the rest hidden, tip closed", TL[14].shown and not TL[15].shown and not TIP.shown
		and TL[1].icon.path == ns.AchIcon(ns.AchRow("heard")) and TB[2].line.shown and not TB[1].line.shown
		and TB[2].text.text == "|cffffd100Social 0/14|r", TB[2].text.text)
	ok("ach tab: Social: same width, 3 rows", W.w == 612 and W.h == ns.AchWinH(14, true), W.h)
	ok("ach window: no stats strip = 18 px less", ns.AchWinH(15, false) == 436
		and ns.AchWinH(14, false) == ns.AchWinH(14, true) - AW.stat, ns.AchWinH(15, false))
	TL[11].scripts.OnEnter(TL[11])
	ok("ach tip: legend row, no reward, not Soon", Tip() == "|cff9d9d9dBorn Legendary|r|Roll your own legendary fart", Tip())
	TL[11].scripts.OnLeave(TL[11])
	local nT = #frames
	TB[1].scripts.OnMouseUp(TB[1], "LeftButton")
	TB[2].scripts.OnMouseUp(TB[2], "LeftButton")
	ns.AchOpen()
	ok("ach window: tabs + reopen make no new frames", #frames == nT, #frames - nT)
	-- no keys at all (gamepad play): never a key script, never a keyboard call
	ok("ach window: never takes keys", W.scripts.OnKeyDown == nil and W.scripts.OnKeyUp == nil
		and W.scripts.OnGamePadButtonDown == nil and W.kb == nil and W.prop == nil)
	TL[1].scripts.OnEnter(TL[1])
	W.close.scripts.OnMouseUp(W.close, "LeftButton")
	ok("ach window: X closes, the tip closes too", not W.shown and not TIP.shown)
	-- /wind ach [tab]: the last tab kept
	b = #prints
	Slash("ach")
	ok("/wind ach: opens the last tab", W.shown and LastLog():find("ACH open tab=social n=14$") and #prints == b, LastLog())
	Slash("ach classic")
	ok("/wind ach classic", W.shown and TB[1].line.shown and LastLog():find("ACH open tab=classic n=15$"), LastLog())
	W.close.scripts.OnMouseUp(W.close, "LeftButton")
	ok("ach window: X closes", not W.shown)
	-- the Rewards button: left = the window, right = the reward grid
	local RB = ns.RewardFrames()
	RB.scripts.OnMouseDown(RB, "LeftButton")
	RB.scripts.OnMouseUp(RB, "LeftButton")
	ok("Rewards button: left click opens the window", W.shown)
	RB.scripts.OnMouseDown(RB, "LeftButton")
	RB.scripts.OnMouseUp(RB, "LeftButton")
	ok("Rewards button: left click again closes it", not W.shown)
	RB.scripts.OnMouseDown(RB, "RightButton")
	RB.scripts.OnMouseUp(RB, "RightButton")
	local _, POP = ns.RewardFrames()
	ok("Rewards button: right click = the reward grid, not the window", POP and POP.shown and not W.shown)
	RB.scripts.OnMouseDown(RB, "RightButton")
	RB.scripts.OnMouseUp(RB, "RightButton")
	ok("Rewards button: right click again closes the grid", POP and not POP.shown)
	-- combat: closes it; no open, no keys, no drag in combat
	ns.AchOpen()
	W.scripts.OnEvent(W, "PLAYER_REGEN_DISABLED")
	ok("ach combat: closes the window", not W.shown and W.events.PLAYER_REGEN_DISABLED == true)
	combat = true
	b = #prints
	ok("ach combat: no open", ns.AchOpen() == false and not W.shown)
	Slash("ach")
	ok("/wind ach in combat: one line, no window", not W.shown and #prints == b + 1
		and prints[b + 1]:find("not in combat", 1, true), prints[b + 1])
	W:Show()
	W.left, W.top = 50, 60
	W.scripts.OnDragStart(W)
	ok("ach combat: no drag", not W.moving)
	combat = false
	W:Hide()
	-- drag: moves, the spot is saved (its top left), kept over a reload
	ns.AchOpen()
	W.scripts.OnDragStart(W)
	ok("ach drag: moves", W.moving == true and W.movable == true and W.drag == "LeftButton")
	W.left, W.top = 300.4, 700.6
	W.scripts.OnDragStop(W)
	ok("ach drag: spot saved", not W.moving and SpokenWindDB.achpos.x == 300 and SpokenWindDB.achpos.y == 701
		and W.point[1] == "TOPLEFT" and W.point[2] == UIParent and W.point[3] == "BOTTOMLEFT" and W.point[4] == 300
		and W.point[5] == 701)
	W:Hide()
	ev, ns = Load(SpokenWindDB)
	ns.AchOpen()
	W = ns.AchFrames()
	ok("ach drag: spot kept over a reload", W.point[1] == "TOPLEFT" and W.point[4] == 300 and W.point[5] == 701, W.point[4])
	W:Hide()
	SpokenWindDB.achpos = { x = "a", y = 5 }
	ev, ns = Load(SpokenWindDB)
	ns.AchOpen()
	W = ns.AchFrames()
	ok("ach drag: bad spot -> default", SpokenWindDB.achpos == nil and W.point[1] == "TOP", W.point[1])
	W:Hide()
	ok("ach window: Toggle", ns.AchToggle() == true and W.shown and ns.AchToggle() == false and not W.shown)
end)()
Fresh()
ok("ach: 5 frames, no toast yet", #frames == 5 and ns.ToastFrame() == nil, #frames)

-- first fart: First Wind, own toast at the game toast's spot
plays, b = {}, #prints
now = now + 100
Emote(OTHER_FART, "Bob", BOB)
ok("first fart -> First Wind", Done().first == clock and LogHas("ACH first toast=1"), LastLog())
local T = ns.ToastFrame()
ok("toast: own frame, made on the first earn", T and #frames == 6 and frames[6] == T, #frames)
ok("toast: on UIParent, backdrop template", T and T.parent == UIParent and T.tmpl == "BackdropTemplate")
local AF = "Interface\\AchievementFrame\\"
ok("toast: 360 x 100, the game's alert art, no friend backdrop", T and T.w == 360 and T.h == 100 and T.backdrop == nil
	and T.bg.path == AF .. "UI-Achievement-Alert-Background" and T.bg.all == T and T.bg.shown and T.bg.coord[2] == 0.605)
ok("toast: icon 48 in the game's icon frame", T and T.icon.path == ns.AchIcon(A[15]) and T.icon.w == 48
	and T.iconFrame.path == AF .. "UI-Achievement-IconFrame" and T.iconFrame.w == 70 and T.iconFrame.shown)
ok("toast: glow + shine, additive", T and T.glow.blend == "ADD" and T.shine.blend == "ADD"
	and T.glow.path == AF .. "UI-Achievement-Alert-Glow" and T.shine.coord[1] == 0.78125 and T.glow.w == 480)
ok("toast: quality ring over the icon", T and T.ring.path == ns.ACH_RING and T.ring.w == 48 and T.ring.point == nil
	and T.ring.x == T.icon.x and Near(T.ring.vc, 0x1e, 0xff, 0x00), T and T.ring.path)
ok("toast: art logged", LogHas("TOAST art=1 icon=1 glow=1"))
ok("toast: dialog strata, clamped", T and T.strata == "DIALOG" and T.clamped == true)
ok("toast: small gold head, big name", T and T.top.text == "Achievement" and T.top.font == "GameFontNormalSmall"
	and T.strings[2] == T.name and T.name.text == "|cff1eff00First Wind|r" and T.name.font == "GameFontHighlightLarge"
	and T.name.wrap == false, T and T.name.text)
;(function()   -- toast text: both strings on the art's plate (from its texcoords), centered on it
	local U, V = T.bg.coord[2], T.bg.coord[4]        -- the part of the art the toast shows
	local L, R = 0.117 / U * T.w, 0.583 / U * T.w    -- the plate's inner rect, in toast units
	local TP, BT = 0.169 / V * T.h, 0.531 / V * T.h
	local MID = (L + R) / 2
	local function In(fs, half)   -- CENTER on the toast's TOPLEFT; the text box inside the plate; centered +-2
		local p = fs.pt or {}
		local x, y = p[4] or -999, -(p[5] or 999)
		return p[1] == "CENTER" and p[2] == T and p[3] == "TOPLEFT" and math.abs(x - MID) <= 2
			and x - fs.width / 2 >= L and x + fs.width / 2 <= R and y - half >= TP and y + half <= BT, x .. "," .. y
	end
	local okT, dT = In(T.top, 6)
	ok("toast text: 'Achievement' in the plate's top strip, under the border, centered +-2", okT
		and math.abs(-T.top.pt[5] - 0.232 / V * T.h) <= 2, dT)
	local okN, dN = In(T.name, 9)
	ok("toast text: the name on the plate's dark band, centered +-2, right of the icon", okN
		and math.abs(-T.name.pt[5] - 0.343 / V * T.h) <= 2 and -T.name.pt[5] > -T.top.pt[5]
		and T.name.pt[4] - T.name.width / 2 >= T.icon.x + T.icon.w / 2, dN)
end)()
ok("toast: starts 24 px low + clear", T and T.shown and T.alpha == 0 and T.point[5] == 176, T and T.point[5])
ok("toast: the game's toast sound, SFX, once", #TS.snd == 1 and TS.snd[1].kit == 18019 and TS.snd[1].ch == "SFX"
	and LogHas("TOAST id=first sound=1"), #TS.snd)
local function Tick(dt) now = now + (dt or 0) T.scripts.OnUpdate(T, dt or 0) end
Tick(0.125)
ok("toast: slides + fades in", math.abs(T.alpha - 0.5) < 0.01 and T.point[5] == 188 and T.glow.shown and T.glow.alpha > 0.5
	and T.shine.shown and T.shine.alpha > 0, T.alpha .. " " .. T.point[5])
Tick(0.15)
ok("toast: at the game toast's spot", T.point[1] == "BOTTOMLEFT" and T.point[2] == UIParent and T.point[4] == 30
	and T.point[5] == 200 and T.alpha == 1, T.point[5])
ok("toast: mouse on (out of combat)", T.mouse == true)
ok("toast: no chat line", #prints == b, prints[#prints])
ok("toast: no key or pad scripts", T.scripts.OnKeyDown == nil and T.scripts.OnGamePadButtonDown == nil)
Tick(0.5)
ok("toast: glow done, shine crossing", not T.glow.shown and T.shine.shown and T.shine.x > 200, T.shine.x)
Tick(0.3)
ok("toast: shine done", not T.shine.shown and T.alpha == 1)
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
;(function()   -- the window shows it: color icon, green ring, green name
	ns.AchOpen("classic")
	local W, _, TL = ns.AchFrames()
	local c = TL[1]
	ok("ach window: done tile = color icon, quality ring, color name", c.line.id == "first" and c.icon.desat == false
		and c.ring.path == ns.ACH_RING and Near(c.ring.vc, 0x1e, 0xff, 0x00) and c.name.text == "|cff1eff00First Wind|r"
		and TL[2].icon.desat == true and TL[15].icon.desat == true, c.name.text)
	W:Hide()
end)()

-- two at once (own /fart at night): a queue; a click shows the next one
clock = os.time({ year = 2026, month = 11, day = 22, hour = 2, min = 0, sec = 0 })
ns.AchOpen("classic")
Id.nightAt = select(2, Id.tile("night"))
now = now + 10
Emote(OWN_FART, ME, ME_GUID)
ok("night + own fart: 2 earned", Done().night and Done().selfstarter)
ok("own fart alone: no Call and Response", not Done().callback)
ok("ach window: redraws at once when open", select(2, ns.AchFrames())[1].text.text == "|cffffd100Classic 3/15|r"
	and select(3, ns.AchFrames())[1].icon.desat == false, select(2, ns.AchFrames())[1].text.text)
ok("ach sort: a fresh earn moves the tile up (13 -> 1); same rarity = list order", Id.nightAt == 13
	and select(2, Id.tile("night")) == 1 and select(2, Id.tile("selfstarter")) == 2 and select(2, Id.tile("first")) == 3, Id.nightAt)
ns.AchFrames():Hide()
ok("toast queue: first one shows", T.shown and T.strings[2].text == "|cff1eff00Night Shift|r", T.strings[2].text)
T.scripts.OnMouseUp(T, "LeftButton")
ok("toast click: next one", T.shown and T.strings[2].text == "|cff1eff00Self-Starter|r", T.strings[2].text)
ok("toast: 2 back to back = 1 sound", LogHas("TOAST id=night sound=1") and LogHas("TOAST id=selfstarter sound=0"))
T.scripts.OnMouseUp(T, "LeftButton")
ok("toast click: hides at the end", not T.shown)
;(function()   -- a left click: the window on the row's tab, its tile glowing (a Classic id)
	local t0 = now   -- the glow steps move the clock; put it back for Call and Response
	local W, TB, TL = ns.AchFrames()
	local g = Id.tile("selfstarter")
	local n = 0
	for _, c in ipairs(TL) do if c.glow.shown then n = n + 1 end end
	ok("toast click: opens Classic, the clicked row glows (one tile)", W.shown and TB[1].line.shown
		and LogHas("TOAST click id=night tab=classic glow=1") and LogHas("TOAST click id=selfstarter tab=classic glow=1")
		and g and g.glow.shown and n == 1, LastLog())
	ok("toast glow: quality color, additive, on the icon, bigger than it", g and Near(g.glow.vc, 0x1e, 0xff, 0x00)
		and g.glow.blend == "ADD" and g.glow.path == "Interface\\Buttons\\UI-ActionButton-Border" and g.glow.w > 92
		and g.glow.x == 0 and g.glow.y == 0)
	now = now + 0.6 W.scripts.OnUpdate(W, 0.6)
	local dim = g.glow.alpha
	now = now + 0.6 W.scripts.OnUpdate(W, 0.6)
	ok("toast glow: pulses (dim, bright)", math.abs(dim - 0.4) < 0.01 and math.abs(g.glow.alpha - 1) < 0.01
		and g.glow.shown, dim)
	now = now + 3.6 W.scripts.OnUpdate(W, 3.6)
	ok("toast glow: still on before 5 s", g.glow.shown and W.scripts.OnUpdate ~= nil)
	now = now + 0.3 W.scripts.OnUpdate(W, 0.3)
	ok("toast glow: off after 5 s, no OnUpdate left", not g.glow.shown and W.scripts.OnUpdate == nil)
	ok("glow: a locked tile glows too", ns.AchGlow("super") == true and Id.tile("super").glow.shown)
	ok("glow: one tile at a time", ns.AchGlow("first") == true and not Id.tile("super").glow.shown
		and Id.tile("first").glow.shown)
	Id.tile("night").scripts.OnEnter(Id.tile("night"))
	ok("glow: the mouse on an other tile keeps it", Id.tile("first").glow.shown)
	Id.tile("first").scripts.OnEnter(Id.tile("first"))
	ok("glow: the mouse on the glowing tile ends it, the tip shows", not Id.tile("first").glow.shown
		and W.scripts.OnUpdate == nil and select(4, ns.AchFrames()).shown)
	Id.tile("first").scripts.OnLeave(Id.tile("first"))
	ns.AchGlow("first")
	ok("glow: a row with no tile on this tab = no glow; the old glow stops", ns.AchGlow("fame") == false
		and not Id.tile("first").glow.shown and W.scripts.OnUpdate == nil)
	ns.AchOpen("social")
	local old = TL[15] and not TL[15].shown and TL[15].line and TL[15].line.id
	ok("glow: a hidden tile (old line) never glows", old and ns.AchGlow(old) == false and not TL[15].glow.shown, old)
	ns.AchOpen("classic")
	ns.AchGlow("first")
	W:Hide()
	n = 0
	for _, c in ipairs(TL) do if c.glow.shown then n = n + 1 end end
	ok("glow: the window closes = off", n == 0 and W.scripts.OnUpdate == nil and ns.AchGlow("first") == false)
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
	local TL = select(3, ns.AchFrames())
	local g, at = Id.tile("first")
	local n = 0
	for _, c in ipairs(TL) do if c.shown and c.glow.shown then n = n + 1 end end
	ok("ach sort: an earn while open moves rows; the glow lands on its row's new spot", Id.first0 == 3 and at and at > 3
		and select(2, Id.tile("callback")) < at and g.glow.shown and n == 1 and not TL[3].glow.shown, at)
	ns.AchFrames():Hide()
end)()
while T.shown do T.scripts.OnMouseUp(T) end   -- the seed pick may earn one more: clear the queue

-- spot: above the game toast while it is up, its scale, else above the chat, else fixed
local function Pop(i) ns.Toast(A[i]) Tick(0.3) local pt = T.point T.scripts.OnMouseUp(T) return pt end
bnState.shown = true
local pt = Pop(1)
ok("toast: above the shown game toast", pt[4] == 30 and pt[5] == 264, pt[5])
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
	T.scripts.OnMouseUp(T, "LeftButton")
	local W, TB = ns.AchFrames()
	local g = Id.tile("fame")
	ok("toast click: a Social id switches to Social, its tile glows (epic color)", W.shown and TB[2].line.shown
		and not TB[1].line.shown and g and g.glow.shown and Near(g.glow.vc, 0xa3, 0x35, 0xee)
		and LogHas("TOAST click id=fame tab=social glow=1") and not T.shown, LastLog())
	ok("toast click: nothing saved, no chat line", Done().fame == nil and #prints == b0, prints[#prints])
	ns.Toast(ns.AchRow("first"))
	T.scripts.OnMouseUp(T, "RightButton")
	ok("toast: a right click only hides it (no open, no click line)", not T.shown and not LogHas("TOAST click id=first")
		and W.shown and TB[2].line.shown, LastLog())
	W:Hide()
end)()
;(function()   -- in combat: no window, one short line, nothing after combat
	combat = true
	ns.Toast(ns.AchRow("legend"))
	local b0 = #prints
	T.scripts.OnMouseUp(T, "LeftButton")   -- the game gives it no mouse in combat; the script holds anyway
	ok("toast click in combat: no window, one short line", not ns.AchFrames().shown and #prints == b0 + 1
		and (prints[#prints] or ""):find("ach: not in combat", 1, true) ~= nil
		and LogHas("TOAST click id=legend tab=classic glow=0") and not T.shown, prints[#prints])
	combat = false
	T.scripts.OnEvent(T, "PLAYER_REGEN_ENABLED")
	ok("combat end: no auto-open, the hidden toast still takes no mouse", not ns.AchFrames().shown and T.mouse == false)
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
ns.AchFrames():Hide()
Fresh(true)
Slash("ach test 3")
T = ns.ToastFrame()
ok("dev: ach test shows the toast", T and T.shown and T.strings[2].text == "|cffa335eeFull Orchestra|r", T and T.strings[2].text)
ok("dev: ach test logged", LastLog():find("ACH test orchestra toast=1", 1, true), LastLog())
Slash("ach test")
ok("dev: ach test, no number -> a random row", LastLog():find("ACH test %a+ toast=1"), LastLog())
ok("dev: ach test earns nothing", next(Done()) == nil)
-- secret row: Test Farts Don't Smell. Only the dev Test gives it (Play button or
-- /wind test); not a fart, no other row; hidden until earned; head "+1".
Fresh()
ns.Test(3)   -- public: a direct call earns nothing either
Slash("test 3")
ok("secret: public has no path", next(Done()) == nil and #reg.buttons == 1 and reg.buttons[1].name == "Achievements"
	and not LogHas("ACH testsmell"))
local sh, sr = AchPage()
ok("secret: public window hides it", sh == "Classic 0/15" and #sr == 15, sh)
Fresh(true)
plays = {}
reg.buttons[2].fn()
ok("secret: Play on Test earns it", Done().testsmell == clock and LogHas("ACH testsmell toast=1"), LastLog())
ok("secret: only this row", next(Done(), "testsmell") == nil and next(Done()) == "testsmell")
ok("secret: not a fart", #SpokenWindDB.farts == 0 and SpokenWindDB.stats.all == 0 and #plays == 1, #SpokenWindDB.farts)
T = ns.ToastFrame()
ok("secret: toast white, ? icon", T and T.shown and T.strings[2].text == "|cffffffffTest Farts Don't Smell|r"
	and T.icon.path == "Interface\\Icons\\INV_Misc_QuestionMark", T and T.strings[2].text)
sh, sr = AchPage()
ok("secret: shown once earned, head +1", sh == "Classic 0/15 +1" and #sr == 16, sh)
local s16 = Id.row(sr, "testsmell")
ok("ach sort: an earned secret row joins the earned group (spot 1)", select(2, Id.row(sr, "testsmell")) == 1)
ok("secret: row 16", s16.name == "|cffffffffTest Farts Don't Smell|r" and s16.rule == "Press Play on Test"
	and s16.stat == "Done " .. os.date("%m-%d", clock) and s16.grey == false and s16.icon == "Interface\\Icons\\INV_Misc_QuestionMark",
	s16.name)
;(function()   -- 16 tiles: a 4th row, the window grows down (no scroll bar)
	ns.AchOpen("classic")
	local W, _, TL = ns.AchFrames()
	local AW = ns.ACH_WIN
	ok("secret: 16 tiles = 4 rows, window grows down", TL[16] and TL[16].shown and TL[16].point[4] == AW.pad
		and TL[16].point[5] == TL[1].point[5] - 3 * (AW.cellH + AW.gap) and W.h == ns.AchWinH(16, true) and W.w == AW.w
		and W.point[1] == "TOP", W.h)
	ok("secret: tile = ? icon, white ring, white name", TL[1].line.id == "testsmell"
		and TL[1].icon.path == "Interface\\Icons\\INV_Misc_QuestionMark"
		and Near(TL[1].ring.vc, 0xff, 0xff, 0xff) and TL[1].name.text == "|cffffffffTest Farts Don't Smell|r")
	ok("secret: an earned secret tile can glow", ns.AchGlow("testsmell") == true and TL[1].glow.shown)
	W:Hide()
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
ok("rw: the button frame (default on)", #frames == 5 and frames[4] == ns.RewardFrames() and frames[5] == ns.BtnFrame(), #frames)

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

-- Rewards button: Options checkbox (under On), default on (0.6.2), made at login.
-- Left click = the achievements window, right click = the reward grid.
Fresh()
local btn = ns.RewardFrames()
ok("btn: made at login (default on)", btn ~= nil and frames[4] == btn and #frames == 5 and btn.parent == UIParent, #frames)
ok("btn: shown, 32 px, movable", btn and btn.shown and btn.w == 32 and btn.movable and btn.drag == "LeftButton")
ok("btn: mouse out of combat, no keys", btn.mouse == true and btn.kb == nil)
ok("btn: default spot left middle", btn.point and btn.point[1] == "LEFT" and btn.point[4] == 40)
ok("btn: First Wind icon", btn.textures[1].path == ns.AchIcon(ns.ACH[15]))
reg.byVar.SpokenWind_rwbtn:SetValue(false)
ok("btn: off = hidden", btn.shown == false)
ok("btn: OPT logged", LogHas("OPT rwbtn=false by=panel"))
local nF = #frames
reg.byVar.SpokenWind_rwbtn:SetValue(true)
ok("btn: on again = same frame", btn.shown and #frames == nF, #frames)

-- grid: 5x3 icons, no scroll bar, own frames
Unlock("first") Unlock("tuba")
Click(btn, "RightButton")
local _, pop, cells, hover = ns.RewardFrames()
ok("grid: opens on a right click", pop and pop.shown)
ok("grid: right click opens no window", ns.AchFrames() == nil)
ok("grid: own frames only", pop.parent == UIParent and cells[1] and cells[1].parent == pop)
ok("grid: 15 cells", #cells == 15, #cells)
local P = ns.REWARD_POP
local okPos = true
for i, c in ipairs(cells) do
	local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
	local x, y = c.point[4], c.point[5]
	if c.w ~= 40 or c.h ~= 40 or x ~= 10 + col * 46 or y ~= -10 - row * 46 then okPos = false end
	if x + c.w > P.w - 10 or -y + c.h > P.h then okPos = false end
end
ok("grid: 5 x 3, 40 px, all inside the box", okPos)
ok("grid: box 244 wide", pop.w == 244 and pop.h == P.h, pop.w)
ok("grid: hover line under the cells, inside", hover.y == -148 and -hover.y + 42 <= P.h, hover.y)
ok("grid: locked grey, unlocked color", cells[1].textures[1].desat == true and cells[13].textures[1].desat == false
	and cells[15].textures[1].desat == false)
ok("grid: quality ring: grey locked, color unlocked", cells[1].ring.path == ns.ACH_RING and cells[1].ring.w == 40
	and Near(cells[1].ring.vc, 0x9d, 0x9d, 0x9d) and Near(cells[13].ring.vc, 0x1e, 0xff, 0x00)
	and Near(cells[15].ring.vc, 0x1e, 0xff, 0x00) and cells[1].textures[2] == cells[1].ring)
ok("grid: achievement icons", cells[13].textures[1].path == ns.AchIcon(ns.ACH[13]))
ok("grid: head (rewards earned only)", hover.text == "Rewards 2/15 · Farts 0\nHeard 0 · People 0 · Best 0\nLegend 0 · Heard 0", hover.text)
ok("grid: above the button", pop.point[1] == "BOTTOMLEFT" and pop.point[2] == btn and pop.point[3] == "TOPLEFT")
ok("grid: Esc key on, other keys go on", pop.kb == true and pop.prop == true)
ok("grid: click-outside watch on", pop.events.GLOBAL_MOUSE_DOWN == true)
ok("grid: DIALOG, clamped", pop.strata == "DIALOG" and pop.clamped == true)
cells[1].scripts.OnEnter(cells[1])
ok("hover: locked = grey name + rule", hover.text:find("Super Legendary · Hear the super legendary fart", 1, true)
	and hover.text:find("^|cff9d9d9d"), hover.text)
cells[13].scripts.OnEnter(cells[13])
ok("hover: unlocked = command + name", hover.text:find("/tuba|r · Tuba Tuesday", 1, true), hover.text)
cells[13].scripts.OnLeave(cells[13])
ok("hover: leave = head", hover.text == "Rewards 2/15" .. ns.HeardHead(), hover.text)
local nSent = #sent
Click(cells[1])
ok("cell locked: no chat, grid stays, local line", #sent == nSent and pop.shown
	and prints[#prints]:find("locked: Super Legendary$"), prints[#prints])
ok("cell locked: logged", LastLog():find("REWARD id=1 by=button locked", 1, true), LastLog())
now = now + 10
Click(cells[13])
ok("cell: one line, grid closes", #sent == nSent + 1 and sent[#sent].text == TUBA and not pop.shown)
ok("cell: logged", LastLog():find("REWARD id=13 by=button sent=1", 1, true), LastLog())
ok("cell: closed = no keys, no click watch", pop.kb == false and not pop.events.GLOBAL_MOUSE_DOWN)
Click(btn, "RightButton")
ok("grid: opens again", pop.shown)
pop.scripts.OnKeyDown(pop, "W")
ok("key W goes on to the game, grid stays", pop.prop == true and pop.shown)
pop.scripts.OnKeyDown(pop, "ESCAPE")
ok("Esc closes, kept from the game menu", not pop.shown and pop.prop == false)
Click(btn, "RightButton")
pop.over, btn.over = true, false
pop.scripts.OnEvent(pop, "GLOBAL_MOUSE_DOWN")
ok("click inside: stays", pop.shown)
pop.over, btn.over = false, true
pop.scripts.OnEvent(pop, "GLOBAL_MOUSE_DOWN")
ok("click on the button: stays (the button toggles)", pop.shown)
pop.over, btn.over = false, false
pop.scripts.OnEvent(pop, "GLOBAL_MOUSE_DOWN")
ok("click outside: closes", not pop.shown)
Click(btn, "RightButton") Click(btn, "RightButton")
ok("button again: closes", not pop.shown)
-- earn while open: the cell turns to color at once
Click(btn, "RightButton")
now = now + 100
Emote(OWN_FART, ME, ME_GUID)
ok("earn while open: color at once", Done().selfstarter ~= nil and cells[14].textures[1].desat == false
	and Near(cells[14].ring.vc, 0x1e, 0xff, 0x00)
	and hover.text == ("Rewards %d/15"):format((ns.AchDone())) .. ns.HeardHead()
	and hover.text:find(" · Farts 1\n", 1, true), hover.text)
-- a key in the gap before the combat event: no keyboard call
do
	combat = true
	local nF = #forbidden
	pop.prop = "none"   -- marks any keyboard call
	pop.scripts.OnKeyDown(pop, "W")
	ok("key in combat: no keyboard call", #forbidden == nF and pop.prop == "none" and pop.shown, #forbidden - nF)
	for i = #forbidden, nF + 1, -1 do forbidden[i] = nil end   -- keep the final check about this test only
end
-- combat: grid shut, no mouse, no keys
combat = true
btn.scripts.OnEvent(btn, "PLAYER_REGEN_DISABLED")
ok("combat: grid shut, button no mouse", not pop.shown and btn.mouse == false)
Click(btn, "RightButton")
ok("combat: a click opens nothing", not pop.shown)
pop.scripts.OnKeyDown(pop, "ESCAPE")
btn.scripts.OnMouseDown(btn, "LeftButton")
btn.scripts.OnDragStart(btn)
ok("combat: no drag", not btn.moving)
combat = false
btn.scripts.OnEvent(btn, "PLAYER_REGEN_ENABLED")
ok("after combat: mouse back", btn.mouse == true)
-- drag: moves, no click, spot saved
btn.scripts.OnMouseDown(btn, "LeftButton")
btn.scripts.OnDragStart(btn)
ok("drag: moving", btn.moving == true)
btn.left, btn.bottom = 300.4, 500.6
btn.scripts.OnDragStop(btn)
hw = true btn.scripts.OnMouseUp(btn, "LeftButton") hw = false
ok("drag: no window, no grid after a drag", not pop.shown and ns.AchFrames() == nil)
ok("drag: spot saved", SpokenWindDB.rwpos and SpokenWindDB.rwpos.x == 300 and SpokenWindDB.rwpos.y == 501)
ok("drag: placed at the spot", btn.point[1] == "BOTTOMLEFT" and btn.point[4] == 300 and btn.point[5] == 501)
Click(btn, "RightButton")
ok("click after a drag opens", pop.shown)
Click(btn, "RightButton")
Click(btn)
ok("left click: the window, not the grid", not pop.shown and ns.AchFrames() and ns.AchFrames().shown)
Click(btn)
ok("left click again: the window closes", not ns.AchFrames().shown)

-- reload: on + spot kept; bad spot dropped; near the top = grid below
ev, ns = Load(SpokenWindDB)
local btn2 = ns.RewardFrames()
ok("reload: button back at its spot", btn2 and btn2.shown and btn2.point[1] == "BOTTOMLEFT" and btn2.point[4] == 300)
ok("reload: BOOT btn=1", LastLog():find(" rw=15 btn=1 ", 1, true), LastLog())
btn2.top = 760
Click(btn2, "RightButton")
local _, pop2 = ns.RewardFrames()
ok("grid: below the button near the top", pop2.point[1] == "TOPLEFT" and pop2.point[3] == "BOTTOMLEFT")
Click(btn2, "RightButton")
SpokenWindDB.rwpos = { x = "a", y = 1 }
ev, ns = Load(SpokenWindDB)
btn2 = ns.RewardFrames()
ok("bad spot dropped -> default", SpokenWindDB.rwpos == nil and btn2.point[1] == "LEFT")
SpokenWindDB.rwpos = { x = 0 / 0, y = 1 }
ev, ns = Load(SpokenWindDB)
ok("NaN spot dropped", SpokenWindDB.rwpos == nil)
Slash("reset")
btn2 = ns.RewardFrames()
ok("reset: button back to on (the default)", SpokenWindDB.rwbtn == true and btn2.shown == true)
SpokenWindDB.rwbtn = true
ev, ns = Load(SpokenWindDB, "canvas")
local btn3 = ns.RewardFrames()
ok("old page: button from the save", btn3 and btn3.shown)
SpokenWindDB.rwbtn = false
ev, ns = Load(SpokenWindDB, "canvas")
ok("old page: off in the save = no button", ns.RewardFrames() == nil and SpokenWindDB.rwbtn == false)
Slash("reset")
ok("old page: reset = on", SpokenWindDB.rwbtn == true and ns.RewardFrames() and ns.RewardFrames().shown)
SpokenWindDB.rwbtn, SpokenWindDB.rwbtnMove = false, nil
ev, ns = Load(SpokenWindDB)
ok("move: old save off -> on once, logged", SpokenWindDB.rwbtn == true and SpokenWindDB.rwbtnMove == true
	and LogHas("RWBTN move off->on") and ns.RewardFrames() and ns.RewardFrames().shown, LastLog())
reg.byVar.SpokenWind_rwbtn:SetValue(false)
local nMove = 0
for _, l in ipairs(SpokenWindDB.log) do if l:find("RWBTN move", 1, true) then nMove = nMove + 1 end end
ev, ns = Load(SpokenWindDB)
ok("move: a later off stays off", SpokenWindDB.rwbtn == false and ns.RewardFrames() == nil and LastLog():find(" btn=0 ", 1, true)
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
ok("sync: SUM at logout", SLast(A):find(" SYNC SUM msg=0 seed=2 late=0 own=3 rand=0 waited=0 sent=14 bad=9 xf=0 sTimer=0 sCapped=0 btn=0.0.0.0 rfart=0$"), SLast(A))
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
			local src = assert(io.open(ADDON_DIR .. "/" .. line:match("^%s*(.-)%s*$"), "rb")):read("*a")
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

	-- toast: art missing on this client = friend backdrop; sound rules
	TS.missing["Interface\\AchievementFrame\\" .. "UI-Achievement-Alert-Background"] = true
	TS.missing["Interface\\AchievementFrame\\" .. "UI-Achievement-Alert-Glow"] = true
	ev, ns = Load(nil, "vertical")
	local R = ns.ACH
	ns.Toast(R[1])
	local T = ns.ToastFrame()
	ok("toast: no alert art -> friend backdrop", T.backdrop and T.backdrop.bgFile == "Interface\\FriendsFrame\\UI-Toast-Background"
		and T.bg.shown == false and T.glow.shown == false and T.shine.shown == false and T.iconFrame.shown)
	ok("toast: art=0 logged", LogHas("TOAST art=0 icon=1 glow=0"))
	now = now + 0.3 T.scripts.OnUpdate(T, 0.3)
	ok("toast: no art, still slides in", T.alpha == 1 and T.point[5] == 200 and not T.glow.shown, T.point[5])
	TS.missing = {}
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
	ok("dev: fire: toast + sound", ns.ToastFrame().shown and ns.ToastFrame().name.text:find("Gas Giant", 1, true)
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
	ok("dev: show = toast + sound only", t.shown and t.name.text:find("Full Orchestra", 1, true) and Done().orchestra == nil
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

;(function()   -- dev 1.3.0: the test window (own function: the main chunk is near 200 locals)
	if not HAVE_DEV then return end
	local HEX = { [5] = "ff8000", [4] = "a335ee", [3] = "0070dd", [2] = "1eff00", [1] = "ffffff", [0] = "9d9d9d" }
	local function Win()
		for _, f in ipairs(frames) do if f.btn then return f end end
	end
	local function Clear() local t = ns.ToastFrame() while t and t.shown do t.scripts.OnMouseUp(t) end end
	local function Click(w, name, button)
		local b = w.btn[name]
		assert(b, "no button " .. name)
		b.scripts.OnMouseUp(b, button or "LeftButton")
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

	-- open / close / toggle
	Fresh()
	local b = #prints
	Slash("dev")
	local w = Win()
	ok("devwin: /wind dev opens", w and w.shown and Count("DEVWIN open") == 1 and #prints == b)
	Slash("dev")
	ok("devwin: /wind dev again closes", not w.shown and Count("DEVWIN close") == 1)
	Slash("dev win")
	ok("devwin: /wind dev win opens", w.shown and Count("DEVWIN open") == 2 and Win() == w)
	Slash("dev win")
	ok("devwin: /wind dev win closes", not w.shown and Count("DEVWIN close") == 2)
	b = #prints
	Slash("dev help")
	ok("devwin: dev help prints the help", #prints == b + 1 and prints[b + 1]:find("dev win", 1, true)
		and prints[b + 1]:find("dev ach list|reset [id]|fire <id>|show <id|all>|undo|real", 1, true), prints[b + 1])
	b = #prints
	Slash("dev zzz")
	ok("devwin: unknown word prints the help", #prints == b + 1 and prints[b + 1]:find("dev win", 1, true) and not w.shown)
	Slash("dev")
	ok("devwin: window did not write the help or error", not LogHas("ERR"))

	-- frame rules
	ok("devwin: own frame on UIParent, movable by drag", w.parent == UIParent and w.movable and w.drag == "LeftButton"
		and w.scripts.OnDragStart and w.scripts.OnDragStop)
	w.scripts.OnDragStart(w)
	ok("devwin: drag starts moving", w.moving == true)
	w.scripts.OnDragStop(w)
	ok("devwin: drag stops moving", w.moving == false)
	local kb, scroll = false, false
	for _, f in ipairs(frames) do
		if f.kb ~= nil or f.prop ~= nil then kb = true end
		if f.ScrollFrame or f.scrollbar then scroll = true end
	end
	ok("devwin: no keyboard, no propagate, no scroll", not kb and not scroll and UISpecialFrames == nil)
	ok("devwin: fixed width", w.w == 300, w.w)

	-- one icon button per row + ring colour
	local nIcons, wrong = 0, {}
	for _, row in ipairs(ns.ACH) do
		local ib = w.btn["toast:" .. row.id]
		if ib then
			nIcons = nIcons + 1
			local hex = HEX[row.q]
			local vc = ib.ring.vc
			local want = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
			if not (vc and math.abs(vc[1] - want[1]) < 1e-6 and math.abs(vc[2] - want[2]) < 1e-6 and math.abs(vc[3] - want[3]) < 1e-6) then
				wrong[#wrong + 1] = row.id
			end
		end
	end
	ok("devwin: one icon per row, 39 rows", nIcons == #ns.ACH and nIcons == 39, nIcons)
	ok("devwin: ring colour = quality colour", #wrong == 0, table.concat(wrong, ","))
	ok("devwin: icon + ring art", w.btn["toast:gas"].icon.path:find("ach\\", 1, true) and w.btn["toast:gas"].ring.path:find("ach\\ring", 1, true))

	-- tooltip on hover
	local tip = {}
	GameTooltip = { SetOwner = function(_, o) tip.owner = o end, SetText = function(_, t) tip.text = t end,
		Show = function() tip.shown = true end, Hide = function() tip.shown = false end }
	local gb = w.btn["toast:gas"]
	gb.scripts.OnEnter(gb)
	ok("devwin: tooltip = name", tip.text == "Gas Giant" and tip.owner == gb and tip.shown, tip.text)
	gb.scripts.OnLeave(gb)
	ok("devwin: tooltip hides", tip.shown == false)
	GameTooltip = nil

	-- left click = toast only, right click = real earn
	local done0 = {}
	for k, v in pairs(SpokenWindDB.ach.done) do done0[k] = v end
	now = now + 5
	Click(w, "toast:gas")
	local nd = 0
	for _ in pairs(SpokenWindDB.ach.done) do nd = nd + 1 end
	local nd0 = 0
	for _ in pairs(done0) do nd0 = nd0 + 1 end
	ok("devwin: left click = toast", ns.ToastFrame().shown and ns.ToastFrame().name.text:find("Gas Giant", 1, true)
		and LogHas("DEV ach show id=gas") and LogHas("DEVWIN click btn=toast:gas"))
	ok("devwin: left click saves nothing", nd == nd0 and SpokenWindDB.ach.done.gas == nil and (SpokenWindDB.dev == nil or SpokenWindDB.dev.real == nil))
	Clear()
	now = now + 5
	Click(w, "toast:gas", "RightButton")
	ok("devwin: right click = real earn", SpokenWindDB.ach.done.gas == clock and LogHas("ACH gas toast=1") and LogHas("DEV ach fire id=gas")
		and LogHas("DEVWIN click btn=fire:gas") and SpokenWindDB.dev and SpokenWindDB.dev.test.gas)
	Clear()
	Click(w, "toast:gas", "MiddleButton")
	ok("devwin: other button does nothing", Count("DEVWIN click btn=") == 2)

	-- undo / real
	now = now + 5
	Click(w, "undo")
	ok("devwin: Undo button", SpokenWindDB.ach.done.gas == nil and LogHas("DEV ach undo id=fire gas") and LogHas("DEVWIN click btn=undo"))
	Clear()
	now = now + 5
	Click(w, "toast:tuba", "RightButton")
	Clear()
	Click(w, "real")
	ok("devwin: Real button", SpokenWindDB.dev == nil and SpokenWindDB.ach.done.tuba == nil and LogHas("DEV real restore")
		and LogHas("DEVWIN click btn=real"))

	-- reset needs two clicks inside 3 s
	Slash("dev")   -- close
	Slash("dev")   -- open
	now = now + 5
	Click(w, "toast:gas", "RightButton")
	Clear()
	local st0 = SpokenWindDB.stats.all
	SpokenWindDB.stats.all = 5
	SpokenWindDB.stats.best = 3
	local nTimers = #SY.timers
	local rb = w.btn.resetach
	Click(w, "resetach")
	ok("devwin: 1st reset click only arms", SpokenWindDB.ach.done.gas ~= nil and rb.text.text == "Sure?" and Count("DEV ach reset id=all") == 0
		and LogHas("DEVWIN click btn=arm:resetach") and #SY.timers == nTimers + 1 and math.abs(SY.timers[#SY.timers].s - 3.1) < 1e-6)
	now = now + 1
	Click(w, "resetach")
	ok("devwin: 2nd click within 3 s resets", SpokenWindDB.ach.done.gas == nil and Count("DEV ach reset id=all") == 1
		and LogHas("DEVWIN click btn=resetach") and rb.text.text == "Reset ach")
	now = now + 5
	Click(w, "toast:gas", "RightButton")
	Clear()
	Click(w, "resetach")
	now = now + 3.1
	Click(w, "resetach")
	ok("devwin: 2nd click after 3.1 s only arms again", SpokenWindDB.ach.done.gas ~= nil and Count("DEV ach reset id=all") == 1
		and rb.text.text == "Sure?")
	now = now + 3.2
	for i = #SY.timers, 1, -1 do if math.abs(SY.timers[i].s - 3.1) < 1e-6 then SY.timers[i].fn() end end
	ok("devwin: Sure? goes back after 3 s", rb.text.text == "Reset ach")
	Click(w, "resetach")
	ok("devwin: reset click after the label went back arms", SpokenWindDB.ach.done.gas ~= nil and rb.text.text == "Sure?")
	ok("devwin: reset ach does not arm stats", w.btn.resetstats.text.text == "Reset stats")
	Click(w, "resetstats")
	ok("devwin: stats 1st click: nothing changed", SpokenWindDB.stats.all == 5 and w.btn.resetstats.text.text == "Sure?"
		and LogHas("DEVWIN click btn=arm:resetstats"))
	now = now + 1
	Click(w, "resetstats")
	ok("devwin: stats 2nd click resets", SpokenWindDB.stats.all == 0 and SpokenWindDB.stats.best == 0 and LogHas("DEV stats reset")
		and LogHas("DEVWIN click btn=resetstats"))
	SpokenWindDB.stats.all = st0

	-- pair on/off + Thanks
	local calls, orig = {}, SlashCmdList.SPOKENWIND
	SlashCmdList.SPOKENWIND = function(m) calls[#calls + 1] = m return orig(m) end
	Click(w, "pairon")
	Click(w, "pairoff")
	Click(w, "tab:classic")
	Click(w, "tab:social")
	Click(w, "tab:collection")
	SlashCmdList.SPOKENWIND = orig
	ok("devwin: pair + tab buttons call the public slash", calls[1] == "pair" and calls[2] == "pair off" and calls[3] == "ach classic"
		and calls[4] == "ach social" and calls[5] == "ach collection" and #calls == 5, table.concat(calls, "|"))
	ok("devwin: Collection tab shown (0.6.3)", w.btn["tab:collection"] ~= nil and not LogHas("ERR devwin"))
	for _, n in ipairs({ "pairon", "pairoff", "tab:classic", "tab:social", "tab:collection" }) do
		if not LogHas("DEVWIN click btn=" .. n) then ok("devwin: click logged " .. n, false) end
	end
	local na, ns0, th = #SY.asent, #sent, Count("DEV thanks ok=")
	Click(w, "thanks")
	ok("devwin: Thanks once per click", Count("DEV thanks ok=") == th + 1 and LogHas("DEVWIN click btn=thanks"))
	Click(w, "thanks")
	ok("devwin: Thanks twice = 2", Count("DEV thanks ok=") == th + 2)
	ok("devwin: Thanks unpaired sends nothing", #SY.asent == na and #sent == ns0)

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
		Click(w, "fart")
		local p = plays[np + 1]
		local want = "Interface\\AddOns\\Spoken_Wind\\Media\\fart\\" .. files[i].file .. ".ogg"
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
	Click(w, "fart")
	ok("devwin: Fart uses the sound channel", plays[np + 1] and plays[np + 1].ch == "Master")
	SpokenWindDB.ch = nil
	np = #plays
	Click(w, "fart")
	ok("devwin: Fart without a channel = SFX", plays[np + 1] and plays[np + 1].ch == "SFX")
	local pf = PlaySoundFile
	PlaySoundFile = function() error("snd boom") end
	Click(w, "fart")
	PlaySoundFile = pf
	ok("devwin: sound error = ERR devwin, no throw", LogHas("ERR devwin") and LogHas("snd boom"))

	-- status
	table.insert(SpokenWindDB.log, "11-21 12:00:00 BOOT v=0.6.2.1 farts=7 heard=3 dex=5 dev=1")
	table.insert(SpokenWindDB.log, "11-21 12:00:01 ERR x")
	table.insert(SpokenWindDB.sync, "11-21 12:00:02 ERR y")
	Click(w, "close")
	ok("devwin: x closes", not w.shown and LogHas("DEVWIN click btn=close") and LogHas("DEVWIN close"))
	local errs = 0
	for _, l in ipairs(SpokenWindDB.log) do if l:find("ERR", 1, true) then errs = errs + 1 end end
	errs = errs + 1
	Slash("dev")
	local text = w.status.text
	ok("devwin: status without len", text:find("^v0.6.2.1 · farts 7 · heard 3 · dex 5 · ERR " .. errs .. "$") and not text:find("len", 1, true), text)
	local last = {}
	for i = #SpokenWindDB.log - 4, #SpokenWindDB.log do last[#last + 1] = SpokenWindDB.log[i]:gsub("^%d%d%-%d%d ", "") end
	local same = true
	for i = 1, 5 do if w.logs[i].text ~= last[i] then same = false end end
	ok("devwin: last 5 log lines", same and #w.logs == 5, w.logs[5].text)
	table.insert(SpokenWindDB.log, "11-21 12:00:03 BOOT v=0.6.3 farts=9 heard=4 dex=6 len=13/14 dev=1")
	Click(w, "toast:gas")
	Clear()
	text = w.status.text
	ok("devwin: status with len, refreshed after a click", text:find("^v0.6.3 · farts 9 · heard 4 · dex 6 · len 13/14 · ERR ") ~= nil, text)
	Slash("dev")

	-- a live 0.6.2.1 shape: no Collection rows; real colours; no BOOT at all
	Fresh()
	for i = #ns.ACH, 1, -1 do if ns.ACH[i].tab == "collection" then table.remove(ns.ACH, i) end end
	ITEM_QUALITY_COLORS = { [4] = { r = 0.1, g = 0.2, b = 0.3 } }
	SpokenWindDB.log = {}
	Slash("dev")
	ITEM_QUALITY_COLORS = nil
	local w2 = Win()
	local n2, epic = 0, true
	for _, row in ipairs(ns.ACH) do
		local ib = w2.btn["toast:" .. row.id]
		if ib then n2 = n2 + 1 end
		if ib and row.q == 4 and not (ib.ring.vc and ib.ring.vc[1] == 0.1 and ib.ring.vc[2] == 0.2 and ib.ring.vc[3] == 0.3) then epic = false end
	end
	ok("devwin: rows from api.ACH, no fixed count", n2 == #ns.ACH and n2 < 38 and w2 ~= w, n2)
	ok("devwin: no Collection button without Collection rows", w2.btn["tab:collection"] == nil and w2.btn["tab:classic"] and w2.btn["tab:social"])
	ok("devwin: game quality colours win", epic)
	ok("devwin: no BOOT line = no error", w2.status.text:find("^no BOOT · ERR 0$") and not LogHas("ERR"), w2.status.text)
	Slash("dev")
	ok("devwin: nothing sent", #sent == 0)
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
local function Panel() for _, f in ipairs(frames) do if f.lines then return f end end end
local function Lines()
	local p, t = Panel(), {}
	for i, fs in ipairs(p and p.lines or {}) do t[i] = fs.text or "" end
	return table.concat(t, "|")
end
local function Words()   -- most words in one shown line (icon, colors and dots left out)
	local most = 0
	for _, fs in ipairs(Panel().lines) do
		local t = (fs.text or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("·", "")
		local k = 0
		for _ in t:gmatch("%S+") do k = k + 1 end
		most = math.max(most, k)
	end
	return most
end
local DIM0 = ICON .. "|cff808080Heard 0|r"

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
ok("show: button off: no Heard text", Panel() == nil or not Panel().shown)
now = now + 3.01 Run()
ok("count: own fart, 0 replies: sum count=0", SN(("HEARD sum g=00AAAA n=%d count=0"):format(myN)) == 1)

-- ---- show: beside the Rewards button
reg.byVar.SpokenWind_rwbtn:SetValue(true)
local btn = ns.RewardFrames()
now = now + 5
own0 = St().own
_, myN = Own()
local pn = Panel()
ok("show: own fart: Heard 0 dimmed, ear icon", pn and pn.shown and pn.lines[1].text == DIM0, Lines())
ok("show: totals under it", pn.lines[2].text == ("Farts %d"):format(own0 + 1) and pn.lines[3].text == "Heard 0 · People 0"
	and pn.lines[4].text == ("Legend %d · Heard %d"):format(St().legend, St().legendHeard), Lines())
ok("show: right of the button (left half), left-aligned", pn.point[1] == "LEFT" and pn.point[2] == btn
	and pn.point[3] == "RIGHT" and pn.point[4] == 6 and pn.lines[1].justify == "LEFT")
ok("show: own frame on UIParent, no mouse, MEDIUM", pn.parent == UIParent and pn.mouse == nil and pn.strata == "MEDIUM")
Msg(H(ME_GUID, myN, QG), "PARTY", "Quin")
ok("count: 1 reply: Heard 1", pn.lines[1].text == ICON .. "Heard 1"
	and SN(("HEARD got from=00BBBB g=00AAAA n=%d count=1"):format(myN)) == 1, Lines())
Msg(H(ME_GUID, myN, QG), "GUILD", "Quin")
ok("count: same replier on GUILD: still 1", pn.lines[1].text == ICON .. "Heard 1", Lines())
Msg(H(ME_GUID, myN, DG), "PARTY", "Quin")
ok("count: same sender, other GUID: still 1", pn.lines[1].text == ICON .. "Heard 1", Lines())
Msg(H(ME_GUID, myN, PG), "RAID", "Pat")
ok("count: 2nd person: Heard 2", pn.lines[1].text == ICON .. "Heard 2" and pn.lines[3].text == "Heard 2 · People 2", Lines())
ok("stats: heard, people (a set), best", St().heard == 2 and St().best == 2 and St().people[QG] == true
	and St().people[PG] == true and St().people[DG] == nil)
ok("show: max 4 words a line", Words() <= 4, Lines())
now = now + 3.01 Run()
ok("count: window closed: sum logged", SN(("HEARD sum g=00AAAA n=%d count=2"):format(myN)) == 1)
Msg(H(ME_GUID, myN, RG), "PARTY", "Rae")
ok("count: reply after 3 s: dropped, line still up", St().heard == 2 and pn.shown and pn.lines[1].text == ICON .. "Heard 2")
now = now + 2 Run()
ok("show: gone after 5 s", not pn.shown)
-- count 0 shown dimmed, best kept
now = now + 5
local _, n2 = Own()
ok("count 0: shown dimmed", pn.shown and pn.lines[1].text == DIM0, Lines())
now = now + 3.01 Run()
ok("count 0: sum count=0, best kept", SN(("HEARD sum g=00AAAA n=%d count=0"):format(n2)) == 1 and St().best == 2)
now = now + 2 Run()
-- someone else's fart: "<name> · Heard N" once N >= 1; your own reply never counts
now = now + 5
Heard(PG, "Pat", 5, 20)
ok("others: our reply went out", #Hs() == 8 and Hs()[8].m == H(PG, 20, ME_GUID))
ok("others: 0 replies: nothing shown", not pn.shown)
Msg(H(PG, 20, ME_GUID), "PARTY", ME)
ok("others: own reply echo: not counted", not pn.shown)
Msg(H(PG, 20, PG), "PARTY", "Pat")
ok("others: the farter's own H: not counted", not pn.shown)
Msg(H(PG, 20, RG), "PARTY", "Rae")
ok("others: name · Heard 1", pn.shown and pn.lines[1].text == ICON .. "Pat · Heard 1" and St().heard == 2, Lines())
ok("others: max 4 words a line", Words() <= 4, Lines())
now = now + 6 Run()
-- your own fart wins while it shows
local _, n3 = Own()
now = now + 1.1
Heard(QG, "Quin", 3, 30)
Msg(H(QG, 30, RG), "PARTY", "Rae")
ok("others: own line wins while shown", pn.lines[1].text == DIM0, Lines())
Msg(H(ME_GUID, n3, PG), "PARTY", "Pat")
ok("others: 2 farts tracked at once: own still counts", pn.lines[1].text == ICON .. "Heard 1", Lines())
now = now + 6 Run()
ok("show: hidden after", not pn.shown)
-- hover: the totals; side by screen edge; button off = no text
btn.scripts.OnEnter(btn)
ok("hover: totals only", pn.shown and pn.lines[1].text == ("Farts %d"):format(St().own) and pn.lines[4].text == "", Lines())
btn.scripts.OnLeave(btn)
ok("hover: leave = hidden", not pn.shown)
btn.left = 1300
btn.scripts.OnEnter(btn)
ok("side: button on the right half: text on its left, right-aligned", pn.point[1] == "RIGHT" and pn.point[3] == "LEFT"
	and pn.point[4] == -6 and pn.lines[1].justify == "RIGHT")
btn.scripts.OnLeave(btn)
btn.left = nil
now = now + 5
_, n3 = Own()
ok("button on: line shown", pn.shown)
reg.byVar.SpokenWind_rwbtn:SetValue(false)
ok("button off while shown: hidden", not pn.shown)
now = now + 6 Run()
local own1 = St().own
Own()
ok("button off: no text, still counts", not pn.shown and St().own == own1 + 1)
now = now + 6 Run()
reg.byVar.SpokenWind_rwbtn:SetValue(true)
-- not in a group (no F sent): no line
IsInGroup, IsInGuild = function() return false end, function() return false end
now = now + 5
own1 = St().own
Own()
ok("solo: no F = no Heard line, still counts", not pn.shown and St().own == own1 + 1)
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
ok("late own F: not sent yet, line up", #SY.asent == na and pn.shown, #SY.asent - na)
now = now + 0.4
hw = true Run() hw = false   -- the key press's own timer (the bus fake marks these; this one does not)
local lateN = tonumber((SY.asent[na + 1] and SY.asent[na + 1].m or ""):match("^F:1:FART:[^:]+:%d+:%d+:(%d+)"))
ok("late own F: sent by the timer", lateN ~= nil)
Msg(H(ME_GUID, lateN or 0, QG), "PARTY", "Quin")
ok("late own F: its reply counts", St().heard == heard0 + 1 and pn.lines[1].text == ICON .. "Heard 1", Lines())
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
ok("legend: shown in the grid head", ns.HeardHead():find(("\nLegend %d · Heard %d$"):format(St().legend, St().legendHeard)), ns.HeardHead())

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
ok("bad H: all dropped, no error", SN("HEARD got") == base and pn.lines[1].text == DIM0 and not LogHas("ERR"), Lines())
Msg(H(ME_GUID, n4, QG), "PARTY", "Quin")
ok("bad H: then a good one counts", SN("HEARD got") == base + 1 and pn.lines[1].text == ICON .. "Heard 1", Lines())
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
ok("social toast: green name + green ring", T and T.shown and T.name.text == "|cff1eff00Someone Heard That|r"
	and Near(T.ring.vc, 0x1e, 0xff, 0x00) and T.ring.path == ns.ACH_RING, T and T.name.text)
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
	local _, pop = ns.RewardFrames()
	local btn = ns.RewardFrames()
	btn.scripts.OnMouseDown(btn, "RightButton")
	btn.scripts.OnMouseUp(btn, "RightButton")
	_, pop = ns.RewardFrames()
	local hv = select(4, ns.RewardFrames())
	local nR = 0
	for _, r in ipairs(ns.REWARDS) do if Done()[r.ach] then nR = nR + 1 end end
	local good = pop and pop.shown and hv.text:find(("^Rewards %d/15"):format(nR)) ~= nil and nR >= 2
		and ns.AchDone() >= nR + 10   -- the 10 social rows are not rewards
	btn.scripts.OnMouseDown(btn, "RightButton")
	btn.scripts.OnMouseUp(btn, "RightButton")
	return good
end)(), select(4, ns.RewardFrames()) and select(4, ns.RewardFrames()).text)

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
ok("Starter Pack: toast with the game's bag icon", T and T.shown and T.icon.path == "Interface\\Icons\\INV_Misc_Bag_10",
	T and T.icon.path)
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

;(function()   -- the window on the Collection tab
	local b, nc, na = #prints, #sent, #SY.asent
	ok("collection window: /wind ach collection opens it, DEX show logged", (function()
		Slash("ach collection")
		return LogHas("ACH open tab=collection n=5") and LastLog():find("DEX show n=10/14 page=1/1$") ~= nil
	end)(), LastLog())
	local W, TB, TL, TIP, ST, SP, SN, PG = ns.AchFrames()
	ok("collection window: Collection tab gold + line", TB[3].text.text == GOLD .. "Collection 1/5|r" and TB[3].line.shown
		and not TB[1].line.shown and TB[1].text.text == GREY .. "Classic 0/15|r", TB[3].text.text)
	ok("collection window: strip = the 5 rows as small tiles (48 px, cell 80)", #SP == 5 and SP[1].icon.w == 48
		and SP[1].ring.w == 48 and SP[1].cellH == 80 and SP[5].shown and SP[1].icon.path == "Interface\\Icons\\INV_Misc_Bag_10"
		and SP[1].icon.desat == false and SP[2].icon.desat == true and SP[1].name.y == -(48 + 4)
		and SP[5].point[4] == 14 + 4 * 118 and SP[1].point[5] == -(14 + 24 + 18), SP[1].icon.w)
	ok("collection window: no big tiles", #TL == 0)
	ok("collection window: 14 sound tiles, the text, the star", #SN == 14 and SN[14].shown and SN[3].text.text == s3.text
		and SN[3].star.shown and not SN[1].star.shown and SN[11].text.text == GREY .. "#11 ???|r"
		and SN[3].star.path == ns.DEX_STAR, SN[3].text.text)
	ok("collection window: heard plate brighter than not heard", SN[3].bg.color[4] == 0.08 and SN[11].bg.color[4] == 0.03)
	ok("collection window: label wraps, room for the star, short names = one 22 px row", SN[1].text.wrap == true
		and SN[1].text.width == 112 - 22 and SN[1].w == 112 and SN[1].h == 22)
	ok("collection window: one page = no page head", not PG.text.shown and not PG.prev.shown and not PG.nxt.shown)
	local top = -(14 + 24 + 18 + 80 + 6)
	ok("collection window: 5 a row under the strip", SN[1].point[4] == 14 and SN[1].point[5] == top
		and SN[5].point[4] == 14 + 4 * 118 and SN[6].point[5] == top - 26 and SN[6].point[4] == 14, SN[1].point[5])
	ok("collection window: the height fits the rows (230 px, no scroll bar)", W.h == 230 and W.h == ns.DexWinH(5, 14, 1)
		and W.w == 612 and -(SN[14].point[5]) + 22 + 14 == W.h, W.h)
	ok("collection window: DexWinH: a 2nd strip row, a 2nd page", ns.DexWinH(6, 14, 1) == 230 + 80 + 6
		and ns.DexWinH(5, 74, 1) == 230 - 74 + 15 * 22 + 14 * 4 and ns.DexWinH(5, 14) == 230 and ns.DexWinH(5, 14, 3) == 250)
	ok("collection window: no chat line", #prints == b and #sent == nc and #SY.asent == na)
	-- the tip
	SN[3].scripts.OnEnter(SN[3])
	TIP = select(4, ns.AchFrames())
	ok("collection tip: name, heard + own, first, click", TIP.shown and TIP.lines[1].text == ns.AchColor(1) .. "#3 Wet|r"
		and TIP.lines[2].text == "Heard 2 · Own 1" and TIP.lines[3].text == "First " .. os.date("%m-%d", clock)
		and TIP.lines[4].text == GOLD .. "Click = play|r", TIP.lines[1].text)
	SN[11].scripts.OnEnter(SN[11])
	ok("collection tip: not heard = 2 lines", TIP.lines[1].text == GREY .. "#11 ???|r" and TIP.lines[2].text == "Not heard yet"
		and not TIP.lines[3].shown and not TIP.lines[4].shown, TIP.lines[1].text)
	SP[1].scripts.OnEnter(SP[1])
	ok("collection tip: a strip tile = the row tip", TIP.lines[1].text == ns.AchColor(2) .. "Starter Pack|r"
		and TIP.lines[2].text == "Hear 10 sounds" and TIP.lines[3].text == "Done " .. os.date("%m-%d", clock)
		and not TIP.lines[4].shown, TIP.lines[1].text)
	SN[11].scripts.OnLeave(SN[11])
	ok("collection tip: leave closes it", not TIP.shown)
	-- a click plays a heard sound here only
	local np, nfl = #plays, #SpokenWindDB.farts
	local n3 = SpokenWindDB.dex["03_wet"].n
	SN[11].scripts.OnMouseUp(SN[11], "LeftButton")
	ok("collection click: a sound not heard yet = nothing", #plays == np)
	SN[3].scripts.OnMouseUp(SN[3], "RightButton")
	ok("collection click: right click = nothing", #plays == np)
	SN[3].scripts.OnMouseUp(SN[3], "LeftButton")
	ok("collection click: plays it here, logged", #plays == np + 1 and plays[#plays].path == ns.MEDIA .. "fart\\03_wet.ogg"
		and plays[#plays].ch == SpokenWindDB.ch and LastLog():find("DEX play key=03_wet ok=1$") ~= nil, LastLog())
	ok("collection click: no count, no fart log, no emote, no chat", SpokenWindDB.dex["03_wet"].n == n3
		and #SpokenWindDB.farts == nfl and #prints == b and #sent == nc and #SY.asent == na and Done().first == nil)
	now = now + 0.5
	SN[1].scripts.OnMouseUp(SN[1], "LeftButton")
	ok("collection click: max 1 per second", #plays == np + 1)
	now = now + 0.5
	SN[1].scripts.OnMouseUp(SN[1], "LeftButton")
	ok("collection click: one preview at a time (Wet still plays): ignored, logged", #plays == np + 1
		and LastLog():find("DEX busy key=01_squeak left=0.8", 1, true) ~= nil, LastLog())
	now = now + 0.78
	SN[1].scripts.OnMouseUp(SN[1], "LeftButton")
	ok("collection click: after the preview ends it plays", #plays == np + 2
		and plays[#plays].path == ns.MEDIA .. "fart\\01_squeak.ogg" and LastLog():find("DEX play key=01_squeak ok=1$") ~= nil,
		LastLog())
	now = now + 2
	combat = true
	SN[1].scripts.OnMouseUp(SN[1], "LeftButton")
	combat = false
	ok("collection click: never in combat", #plays == np + 2)
	now = now + 2
	willPlay = false
	SN[1].scripts.OnMouseUp(SN[1], "LeftButton")
	willPlay = true
	ok("collection click: sound off = logged ok=0", LastLog():find("DEX play key=01_squeak ok=0$") ~= nil, LastLog())
	now = now + 1.1
	SN[3].scripts.OnMouseUp(SN[3], "LeftButton")
	ok("collection click: a sound that did not play holds nothing", #plays == np + 4, #plays - np)
	-- a client with StopSound: the old preview stops, the new one plays
	local stopped = {}
	StopSound = function(h) stopped[#stopped + 1] = h end
	now = now + 1.1
	SN[1].scripts.OnMouseUp(SN[1], "LeftButton")
	StopSound = nil
	ok("collection click: StopSound: the old preview stops, the new one plays", #plays == np + 5 and #stopped == 1
		and stopped[1] == 77 and LastLog():find("DEX play key=01_squeak ok=1 stop=1$") ~= nil, LastLog())
	-- StopSound + a new preview that did not play: nothing is held after it
	local wetLen = ns.LEN["03_wet"]
	ns.LEN["03_wet"] = 3000
	stopped = {}
	StopSound = function(h) stopped[#stopped + 1] = h end
	now = now + 5
	SN[3].scripts.OnMouseUp(SN[3], "LeftButton")
	now = now + 1.1
	willPlay = false
	SN[1].scripts.OnMouseUp(SN[1], "LeftButton")
	willPlay = true
	now = now + 1.1
	SN[1].scripts.OnMouseUp(SN[1], "LeftButton")
	StopSound = nil
	ns.LEN["03_wet"] = wetLen
	ok("collection click: StopSound + a preview that did not play: nothing held after it", #stopped == 1
		and LastLog():find("DEX play key=01_squeak ok=1$") ~= nil, #stopped .. " " .. LastLog())
	-- a short preview (0.2 s): the 1 s gap still holds on its own
	ns.LEN["03_wet"] = 200
	now = now + 5
	SN[3].scripts.OnMouseUp(SN[3], "LeftButton")
	local npg = #plays
	now = now + 0.6
	SN[1].scripts.OnMouseUp(SN[1], "LeftButton")
	ok("collection click: a short preview: 0.6 s later the 1 s gap blocks", #plays == npg
		and LastLog():find("DEX play key=03_wet ok=1$") ~= nil, LastLog())
	now = now + 0.41
	SN[1].scripts.OnMouseUp(SN[1], "LeftButton")
	ok("collection click: a short preview: 1.01 s later it plays", #plays == npg + 1, #plays - npg)
	ns.LEN["03_wet"] = wetLen
	ok("collection click: no bad tile, no play", ns.DexPlay(nil) == false and ns.DexPlay({ key = "x" }) == false)
	-- tabs
	TB[1].scripts.OnMouseUp(TB[1], "LeftButton")
	local hid = true
	for _, c in ipairs(SN) do if c.shown then hid = false end end
	for _, c in ipairs(SP) do if c.shown then hid = false end end
	TL = select(3, ns.AchFrames())
	ok("collection -> Classic: sounds + strip hidden, 15 big tiles", hid and #TL == 15 and TL[15].shown
		and W.h == ns.AchWinH(15, true) and ST.text == ns.AchStatsText() and not PG.text.shown, W.h)
	local nShow = Count("DEX show")
	TB[3].scripts.OnMouseUp(TB[3], "LeftButton")
	ok("collection tab: back = sounds again, DEX show logged, big tiles hidden", SN[1].shown and SP[1].shown
		and not TL[1].shown and Count("DEX show") == nShow + 1 and W.h == 230 and ST.text == L.stats, Count("DEX show"))
	TB[2].scripts.OnMouseUp(TB[2], "LeftButton")
	ok("collection -> Social: no DEX show", Count("DEX show") == nShow + 1)
	TB[3].scripts.OnMouseUp(TB[3], "LeftButton")
	-- 0.6.2.1 merged: a toast click on a Collection row = the Collection tab, its strip tile glows
	local t0 = now   -- the glow steps move the clock; put it back after
	TB[1].scripts.OnMouseUp(TB[1], "LeftButton")
	local tab, glow = ns.AchShow("starter")
	local ng = 0
	for _, c in ipairs(SP) do if c.glow.shown then ng = ng + 1 end end
	ok("collection glow: a Collection row = the Collection tab, its strip tile glows (one)", tab == "collection"
		and glow == true and TB[3].line.shown and SN[1].shown and SP[1].line.id == "starter" and SP[1].glow.shown and ng == 1
		and Near(SP[1].glow.vc, 0x1e, 0xff, 0x00), tostring(tab))
	ok("collection glow: sized for the small tile (48 x 1.7)", math.abs(SP[1].glow.w - 48 * 1.7) < 0.01
		and math.abs(SP[1].glow.h - 48 * 1.7) < 0.01, SP[1].glow.w)
	now = now + 5.1 W.scripts.OnUpdate(W, 5.1)
	ok("collection glow: off after 5 s on the strip too", not SP[1].glow.shown and W.scripts.OnUpdate == nil)
	local g2 = ns.AchGlow("starter")
	SP[1].scripts.OnEnter(SP[1])
	ok("collection glow: the mouse on it ends it", g2 and not SP[1].glow.shown and W.scripts.OnUpdate == nil)
	SP[1].scripts.OnLeave(SP[1])
	-- the strip sorts like the other tabs: earned first, rarest first, then the locked ones in list order
	Done().pitch, Done().collector = clock, clock
	ns.AchOpen("collection")
	local ids = {}
	for i = 1, 5 do ids[i] = SP[i].line.id end
	ok("collection sort: earned rarest first (Epic, Rare, Uncommon), then locked in list order",
		table.concat(ids, ",") == "pitch,collector,starter,gasologist,complete", table.concat(ids, ","))
	ok("collection sort: the glow lands on the row's new spot", ns.AchGlow("starter") and SP[3].glow.shown
		and not SP[1].glow.shown)
	Done().pitch, Done().collector = nil, nil
	ns.AchOpen("collection")
	ok("collection sort: back to the list order, the glow follows", SP[1].line.id == "starter"
		and SP[2].line.id == "collector" and SP[1].glow.shown and not SP[3].glow.shown, SP[1].line.id)
	ns.AchGlow("none")   -- stops the glow
	now = t0
	local nf = #frames
	-- pages (the 1337 set adds them as data): arrows, wrap around
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
	ok("pages: 2 pages = the page head with arrows", PG.text.shown and PG.prev.shown and PG.nxt.shown
		and PG.text.text == "Original 10/14" and W.h == ns.DexWinH(5, 14, 2) and W.h == 250
		and SN[1].point[5] == top - 20 and PG.text.y == top - 3 and PG.nxt.point[4] == 612 - 14 - 20, PG.text.text)
	TB[1].scripts.OnMouseUp(TB[1], "LeftButton")
	ok("pages: Classic tab hides the page head + arrows", not PG.text.shown and not PG.prev.shown and not PG.nxt.shown)
	TB[3].scripts.OnMouseUp(TB[3], "LeftButton")
	ok("pages: Perfect Pitch counts once a voice page is there", Row("pitch").stat == "0/4"
		and Row("collector").stat == "Soon", Row("pitch").stat)
	PG.nxt.scripts.OnMouseUp(PG.nxt, "LeftButton")
	ok("pages: > = the voice page, its 4 tiles only", PG.text.text == "Troll m 0/4" and SN[4].shown and not SN[5].shown
		and SN[1].text.text == GREY .. "#101 ???|r" and W.h == ns.DexWinH(5, 4, 2), PG.text.text)
	PG.nxt.scripts.OnMouseUp(PG.nxt, "LeftButton")
	ok("pages: > on the last page = the first", PG.text.text == "Original 10/14" and SN[14].shown)
	PG.prev.scripts.OnMouseUp(PG.prev, "LeftButton")
	ok("pages: < on the first page = the last", PG.text.text == "Troll m 0/4")
	PG.prev.scripts.OnMouseUp(PG.prev, "RightButton")
	ok("pages: right click = nothing", PG.text.text == "Troll m 0/4")
	for i = 1, 3 do SpokenWindDB.dex[("t_m_%02d"):format(i)] = { n = 1, t = clock, own = 0 } end
	ns.AchDex()
	ok("Perfect Pitch: 3 of 4 is not", Done().pitch == nil and Row("pitch").stat == "3/4", Row("pitch").stat)
	SpokenWindDB.dex.t_m_04 = { n = 1, t = clock, own = 1 }
	ns.AchDex()
	ok("Perfect Pitch: every sound of one voice", Done().pitch ~= nil and LogHas("ACH pitch toast=1"))
	ok("pages: the open window redraws at once", PG.text.text == "Troll m 4/4" and SN[4].star.shown, PG.text.text)
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
	ns.DexPages = realP
	for _, k in ipairs({ "t_m_01", "t_m_02", "t_m_03", "t_m_04", "k001", "k002", "k003", "k004" }) do SpokenWindDB.dex[k] = nil end
	ns.AchOpen("collection")
	ok("pages: back to one page: page 1, no head", not PG.text.shown and not PG.prev.shown and W.h == 230
		and SN[14].shown and SN[1].point[5] == top, W.h)
	ns.DexPages = twoP
	ns.AchOpen("collection")
	ok("pages: the page resets once the pool shrinks", PG.text.text == "Original 10/14", PG.text.text)
	ns.DexPages = realP
	ns.AchOpen("collection")
	ok("collection window: pages + reopen make no new frames", #frames == nf, #frames - nf)
	ok("collection window: never takes keys", W.kb == nil and W.prop == nil and W.scripts.OnKeyDown == nil)
	W.close.scripts.OnMouseUp(W.close, "LeftButton")
	ok("collection window: X closes", not W.shown)
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
	if ch == "WHISPER" then return type(tgt) == "string" and (tgt:match("^[^%-]+") or ""):lower() == to.name:lower() end
	if ch == "PARTY" or ch == "RAID" then return from.party == to end
	return false
end
local function BusSend(p, m, ch, tgt)
	local from = CUR
	m = tostring(m)
	P.log[#P.log + 1] = { from = from, m = m, ch = ch, tgt = tgt, hw = hw, t = now }
	if #tostring(p) + #m > 254 then forbidden[#forbidden + 1] = "addon message too long" end
	if m:sub(1, 4) == "T:1:" then   -- test messages: by WHISPER to the partner only
		local T = from.ns.TestState()
		if ch ~= "WHISPER" or not (T and T.on and tgt == T.partner) then forbidden[#forbidden + 1] = "T message not to the partner " .. m end
	elseif m:sub(1, 4) == "H:1:" then   -- a Heard reply: any time; by WHISPER only to the test partner
		local T = from.ns.TestState()
		if ch == "WHISPER" and not (T and T.on and tgt == T.partner) then forbidden[#forbidden + 1] = "H message whispered " .. m end
	elseif not hw and not (P.inTimer and P.inTimer.hwMade) then   -- a fart message: only from a key press
		forbidden[#forbidden + 1] = "F message outside a key press"
	end
	for _, to in ipairs(P.clients) do
		if to ~= from and Reaches(from, to, ch, tgt) then
			P.q[#P.q + 1] = { at = now + P.lat, to = to, p = p, m = m, ch = ch, sender = from.name .. "-" .. REALM }
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
	UnitName = function(u) local x = CUR and Unit(CUR, u) return x and x.name or nil end
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
ok("test: window: wait + how to pair", Text(A) == "Wind test · Bo · wait|seed ? · clock ?|partner: /wind pair Ann", Text(A))
ok("test: HI by whisper", #Sent(A, "T:1:HI:Player-1-0000A001:0.7.0:Alliance:", "WHISPER") == 1)
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
ok("test: seed match", TA.seed == "match" and TB.seed == "match"
	and TN(A, "PAIR ok side=1 seed=match ver=0.7.0 pver=0.7.0 pg=" .. GB) == 1 and TN(B, "PAIR ok side=2 seed=match") == 1)
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
A.party, B.party = B, A
Cmd(A, "pair")
Cmd(B, "pair")
Tick(4)
TA, TB = St(A), St(B)
ok("test: group: pair by party1", TA.paired and TB.paired and TA.n == 2 and TA.prev and #TA.prev.recs == 29 and TA.prev.prev == nil)
Be(A)
ok("test: group: whisper only off-group", A.ns.TestWhisper() == nil)
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
-- the Board tab (0.6.4 UI): lists, own row, All strip, tiers, Seen ?, tips, logs, no new frames
local function TipOf(f)
	f.scripts.OnEnter(f)
	local TIP = select(4, ns.AchFrames())
	local t = {}
	for _, fs in ipairs(TIP.lines) do if fs.shown then t[#t + 1] = fs.text end end
	f.scripts.OnLeave(f)
	return table.concat(t, "|")
end
local function TierStr(t)
	local p = {}
	for i = 1, 7 do p[i] = "|cff" .. ns.B.TIER_HEX[i] .. t[i] .. "|r" end
	return table.concat(p, "  ")
end
local function Ago(at)
	local d = math.floor((clock - at) / 86400)
	return d <= 0 and "Seen today" or ("Seen %d d ago"):format(d)
end
local function AgeTxt(L) return L.board.age and ("Top 10 oldest %d d"):format(L.board.age) or "Top 10 empty" end
local function FindMe(col) for _, l in ipairs(col.rows) do if l.me then return l end end return col.own end
ok("board tab: opens", ns.AchOpen("board") == true)
local W, TB, TL, _, ST = ns.AchFrames()
local BD = select(9, ns.AchFrames())
local L = ns.AchLines("board")
local A4 = ns.B.All(SpokenWindDB)
ok("board tab: 4 tabs, Board gold + line", #TB == 4 and TB[4].text.text == "|cffffd100Board|r" and TB[4].line.shown
	and not TB[1].line.shown, TB[4] and TB[4].text.text)
ok("board tab: no tiles", (function() for _, c in ipairs(TL) do if c.shown then return false end end return true end)())
ok("board tab: All strip", ST.text == ("All · Farts %d · Heard %d · Players %d"):format(A4.f, A4.l, A4.p), ST.text)
ok("board tab: All tiers at the strip end", BD.tier.shown and BD.tier.text == TierStr(A4.t), BD.tier.text)
ok("board tab: list heads + Seen ?", BD.heads[1].shown and BD.heads[1].text == "Most heard" and BD.heads[2].text == "Top listener"
	and BD.seen.shown and BD.seen.text == "Seen ?", BD.seen.text)
ok("board tab: logs", LogHas("BOARD show n=" .. A4.p .. " ") and LogHas("BOARD seen est="))
local okRows, why = true, ""
for k, col in ipairs(L.cols) do
	local src = k == 1 and L.board.heard or L.board.listen
	local pool = BD.rows[k]
	local n = #col.rows + (col.own and 1 or 0)
	for i = 1, n do
		local c, l = pool[i], i <= #col.rows and col.rows[i] or col.own
		if not (c and c.shown and c.line.short == l.short and c.num.text == tostring(l.num)
			and c.rank.text == "|cff9d9d9d" .. l.rank .. "|r" and c.name.text == l.color .. l.short .. "|r") then
			okRows, why = false, "row " .. k .. "/" .. i
		end
		if c and (c.name.text:find("Player-", 1, true) or (c.line.name or ""):find("Player-", 1, true)) then okRows, why = false, "guid" end
	end
	for i = 2, #src do if src[i].v > src[i - 1].v then okRows, why = false, "order" end end
	for _, r in ipairs(src) do if not r.own and r.hide == 1 then okRows, why = false, "hidden shown" end end
	if pool[n + 1] and pool[n + 1].shown then okRows, why = false, "extra row" end
end
ok("board tab: rows = the lists, best first, no hidden, no GUID", okRows and #L.cols[2].rows > 0, why)
ok("board tab: height fits the rows (no scroll)", W.h == ns.BoardWinH(#L.cols[1].rows, L.cols[1].own ~= nil,
	#L.cols[2].rows, L.cols[2].own ~= nil) and W.w == 612, W.h)
local m1 = FindMe(L.cols[1])
ok("board tab: own character in Most heard (top or under it), gold", m1 and m1.short == "Tester" and m1.color == "|cffffd100"
	and m1.rule:find("^Farts %d+ · Heard %d+ · Listened %d+$") and TipOf(BD.rows[1][m1.rank <= #L.cols[1].rows and m1.rank
	or #L.cols[1].rows + 1]):find("|This character", 1, true), m1 and m1.short)
local rae
for k, col in ipairs(L.cols) do for i, l in ipairs(col.rows) do if l.short == "Rae" and not rae then rae = { k = k, i = i } end end end
local e = SpokenWindDB.board[RG]
ok("board tab: Rae listed, row tip = name-realm, numbers, seen", rae and TipOf(BD.rows[rae.k][rae.i])
	== ("|cffffffffRae-Nowhere|r|Farts %d · Heard %d · Listened %d|%s"):format(e.f, e.h, e.l, Ago(e.at)),
	rae and TipOf(BD.rows[rae.k][rae.i]))
ok("board tab: Seen tip = top 10 age", TipOf(BD.seenHit) == "|cffffd100Seen ?|r|" .. AgeTxt(L), TipOf(BD.seenHit))
ok("board tab: All tip", TipOf(BD.allHit) == "|cffffd100All players|r|Players you met with the addon|Oldest "
	.. os.date("%m-%d", A4.oldest) .. "|" .. "|cffffd100Seen ? · " .. AgeTxt(L) .. "|r", TipOf(BD.allHit))
local tierT = TipOf(BD.tierHit)
ok("board tab: tier tip = All + 7 named tiers", tierT:find("|cffffd100All|r||cff9d9d9dPoor|r ", 1, true) == 1
	and select(2, tierT:gsub("|cff%x+%a+|r %d+", "")) == 7 and tierT:find("Artifact|r " .. A4.t[7], 1, true) ~= nil, tierT)
local nF = #frames
TB[1].scripts.OnMouseUp(TB[1], "LeftButton")
ok("board tab: Classic: rows, heads, Seen hidden; Mine tiers; same height", not BD.rows[1][1].shown and not BD.heads[1].shown
	and not BD.seen.shown and not BD.allHit.shown and BD.tier.text == TierStr((ns.TiersMine()))
	and W.h == ns.AchWinH(#ns.AchLines("classic").tiles, true), W.h)
ok("board tab: Mine tier tip", TipOf(BD.tierHit):find("^|cffffd100Mine|r|") ~= nil)
TB[4].scripts.OnMouseUp(TB[4], "LeftButton")
TB[3].scripts.OnMouseUp(TB[3], "LeftButton")
ok("board tab: Collection: Mine tiers too, no rows", BD.tier.shown and BD.tier.text == TierStr((ns.TiersMine())) and not BD.rows[1][1].shown)
TB[4].scripts.OnMouseUp(TB[4], "LeftButton")
nF = #frames   -- every tab drawn once: from here on, no new frames
for _, k in ipairs({ 1, 2, 3, 4, 3, 4 }) do TB[k].scripts.OnMouseUp(TB[k], "LeftButton") end
ok("board tab: tab switches make no new frames", #frames == nF and BD.rows[1][1].shown, #frames - nF)
Slash("board off")
L = ns.AchLines("board")
m1 = FindMe(L.cols[1])
ok("board tab: off = own row grey + hint", m1 and m1.color == "|cff9d9d9d" and m1.gold == "Hidden · /wind board on", m1 and m1.gold)
Slash("board on")
ns.AchFrames():Hide()
-- empty state: a fresh save = your row under each list + Seen ?
local saved2 = SpokenWindDB
ME, ME_GUID = "Newb", "Player-1-0000DDDD"
Boot({})
ns.AchOpen("board")
W, BD, L = ns.AchFrames(), select(9, ns.AchFrames()), ns.AchLines("board")
ok("board tab: empty: own row under each list, rank 1, 0", L.cols[1].own and L.cols[1].own.short == "Newb" and L.cols[1].own.rank == 1
	and L.cols[1].own.num == 0 and #L.cols[1].rows == 0 and L.cols[2].own and #L.cols[2].rows == 0 and BD.rows[1][1].shown
	and BD.rows[2][1].shown and not BD.rows[1][2])
ok("board tab: empty: Seen ?, Top 10 empty, strip", BD.seen.text == "Seen ?" and TipOf(BD.seenHit) == "|cffffd100Seen ?|r|Top 10 empty"
	and select(5, ns.AchFrames()).text == "All · Farts 0 · Heard 0 · Players 1", select(5, ns.AchFrames()).text)
ok("board tab: empty: own row under the list head + the gap", BD.rows[1][1].point[5] == -(14 + 24 + 18) - 20 - 6
	and BD.rows[2][1].point[4] == 14 + ns.ACH_WIN.colW + ns.ACH_WIN.colGap and BD.rows[1][1].point[4] == 14, BD.rows[1][1].point[5])
ok("board tab: empty: height = one row + the gap", W.h == ns.BoardWinH(0, true, 0, true)
	and W.h == 14 + 24 + 18 + 20 + 6 + 18 + 14, W.h)
ok("board tab: empty: no ERR", NoErr(), select(2, NoErr()))
ns.AchFrames():Hide()
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
ok("timer: SUM sTimer at logout", SFind(" SYNC SUM "):find(" sTimer=" .. total .. " sCapped=0 btn=0.0.0.0 rfart=0$"), SFind(" SYNC SUM "))
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
	return ns.BtnFrame()
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
	local f = ns.BtnFrame()
	hw = true   -- a mouse click (hardware event)
	if f.scripts.OnMouseDown then f.scripts.OnMouseDown(f, button or "LeftButton") end
	f.scripts.OnMouseUp(f, button or "LeftButton")
	hw = false
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
	local f = ns.BtnFrame()
	f.scripts.OnEvent(f, "PLAYER_TARGET_CHANGED")
end
local function P(n, extra)   -- a player target (made-up names)
	local t = { g = ("Player-1-0000%04X"):format(n), n = "Nim" .. string.char(96 + n % 26) .. n }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end
local function Icon() return ns.BtnFrame().textures[1].path end
local function NoNames(tag)   -- BTN lines: no names, no GUIDs
	local bad
	for _, l in ipairs(SpokenWindDB.log) do
		if l:find("BTN", 1, true) and (l:find("Nim", 1, true) or l:find("Bea", 1, true) or l:find("Zed", 1, true)
			or l:find("Player-", 1, true) or l:find("Creature-", 1, true) or l:find("0000", 1, true)) then bad = l end
	end
	ok("fbtn logs: no names, no GUIDs (" .. tag .. ")", bad == nil, bad)
end

-- the frame: right of the Rewards button, shown and hidden with it
local fb = Boot()
local rb = ns.RewardFrames()
ok("fbtn: made at login, own frame", fb ~= nil and frames[5] == fb and fb.parent == UIParent, #frames)
ok("fbtn: right of the Rewards button", fb.shown and fb.point and fb.point[1] == "LEFT" and fb.point[2] == rb
	and fb.point[3] == "RIGHT" and fb.point[4] == 4 and fb.point[5] == 0)
ok("fbtn: 32 px, wind icon, mouse on, no keys, no drag", fb.w == 32 and fb.h == 32 and Icon() == ns.BTN.icon
	and fb.mouse == true and fb.kb == nil and not fb.movable and fb.drag == nil)
reg.byVar.SpokenWind_rwbtn:SetValue(false)
ok("fbtn: Rewards button off = hidden too", fb.shown == false and rb.shown == false)
local nF = #frames
reg.byVar.SpokenWind_rwbtn:SetValue(true)
ok("fbtn: on again = same frame, shown", fb.shown and ns.BtnFrame() == fb and #frames == nF, #frames - nF)

-- no target: ONE plain emote; the Sync hook sends F as for a key press
IsInGroup = function() return true end
local ne, aw, cl = Press()
local e = SY.emotes[#SY.emotes]
ok("fbtn: no target = ONE FART emote, in the click", ne == 1 and e.token == "FART" and e.unit == nil and e.hw == true, ne)
local nF1 = 0
for _, x in ipairs(aw) do if tostring(x.m):find("^F:1:FART:") and x.ch == "PARTY" and x.hw then nF1 = nF1 + 1 end end
ok("fbtn: the F goes out as for a key press (Sync hook, same click)", nF1 == 1, #aw)
ok("fbtn: no target: no check, no chat line", #Pings(aw) == 0 and #cl == 0 and LogHas("BTN fart tgt=0 has=?"))
local neR, awR, clR = Press("RightButton")
ok("fbtn: a right click does nothing", neR == 0 and #awR == 0 and #clR == 0)

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
ok("fbtn: the icon stays 10 s", Icon() == ns.BTN.iconW)
Wait(0.2)
ok("fbtn: after 10 s the icon goes", Icon() == ns.BTN.icon and LogHas("BTN whisper icon off"))
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
fb.scripts.OnEvent(fb, "PLAYER_REGEN_DISABLED")
ok("fbtn: combat = no mouse, the check ends", fb.mouse == false and Icon() == ns.BTN.icon)
local nC, aC, cC = Press()
ok("fbtn: a click in combat does nothing", nC == 0 and #aC == 0 and #cC == 0)
combat = false
fb.scripts.OnEvent(fb, "PLAYER_REGEN_ENABLED")
ok("fbtn: after combat: mouse on", fb.mouse == true)
-- the emote call fails: a log line, no Lua error out of the click
SY.emoteErr = true
Target(nil)
local sums = ns.BtnSums()
local okE = pcall(Press)
SY.emoteErr = nil
ok("fbtn: the emote call fails = ERR btn line, no error out, not counted", okE and LogHas("ERR btn") and ns.BtnSums() == sums, ns.BtnSums())
-- the Rewards button hides during a check: the check ends
Target(P(35)) Press() Wait(2.1)
reg.byVar.SpokenWind_rwbtn:SetValue(false)
reg.byVar.SpokenWind_rwbtn:SetValue(true)
ok("fbtn: hidden during a check = the check ends", Icon() == ns.BTN.icon)
local nV, _, cV = Press()
ok("fbtn: then a click = a fart, no whisper", nV == 1 and #cV == 0)
NoNames("flow")

-- the cap: 5 whispers per 10 min
fb = Boot()
local function Whisp(t)
	Target(t) Press() Wait(2.1)
	local _, _, c = Press()
	return #c == 1
end
local okW = true
for i = 1, 5 do if not Whisp(P(40 + i)) then okW = false end end
ok("fbtn: 5 whispers in 10 min", okW and LogHas("BTN whisper sent n=5"))
Target(P(46))
local nX, aX = Press()
ok("fbtn: the 6th in 10 min = the fart, no check (why=cap)", nX == 1 and #Pings(aX) == 0 and LastLog():find("why=cap", 1, true) ~= nil)
Wait(600)
ok("fbtn: 10 min later a whisper works again", Whisp(P(47)) and LogHas("BTN whisper sent n=6"))
-- the log cap: max 20 BTN lines per session; the SUM line counts all (farts.pings.whispers.pongs)
Target(nil)
for _ = 1, 50 do Press() end
ok("fbtn: max 20 BTN log lines per session", BN("BTN ") == 20, BN("BTN "))
ok("fbtn: session sums count past the cap", ns.BtnSums() == "57.6.6.0", ns.BtnSums())
ns.SyncSum()
ok("fbtn: SUM line btn=", (SpokenWindDB.sync[#SpokenWindDB.sync] or ""):find(" btn=57.6.6.0 rfart=0$") ~= nil, SpokenWindDB.sync[#SpokenWindDB.sync])
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

-- the texts: one chat line each, only what this build has; the creator line only with the dev addon
local T1, T2 = ns.BTN.text, ns.BTN.textDev
ok(("fbtn: texts fit one chat line (%d and %d of 255 bytes)"):format(#T1, #T2), #T1 <= 255 and #T2 <= 255)
ok("fbtn: public text: no creator line; dev text = I made", not T1:find("I made", 1, true)
	and (T2:gsub("I made Spoken Wind:", "Spoken Wind:")) == T1)
local both = (T1 .. T2):lower()
ok("fbtn: texts claim only this build: no 1337, no race or gender packs", not both:find("1337", 1, true)
	and not both:find("race", 1, true) and not both:find("gender", 1, true))
ok("fbtn: texts name Spoken Wind, Spoken, CurseForge", T1:find("Spoken Wind:", 1, true) and T1:find("Inspired by Spoken ", 1, true)
	and T1:find("CurseForge", 1, true))
fb = Boot(true)
Target(P(50)) Press() Wait(2.1)
local _, _, cD = Press()
ok("fbtn: dev addon = the creator text", cD[1] and cD[1].text == T2, cD[1] and cD[1].text)

-- the source: one emote call, one chat send, no Blizzard writes, no hooks, no keys
local src = assert(io.open(ADDON_DIR .. "/Button.lua", "rb")):read("*a")
local code = src:gsub("%-%-[^\n]*", "")
local function Cnt(s) local k = 0 for _ in code:gmatch(s) do k = k + 1 end return k end
ok("fbtn src: DoEmote once (in the click)", Cnt("DoEmote") == 1 and Cnt('pcall%(DoEmote, "FART"%)') == 1)
ok("fbtn src: one chat send, WHISPER only", Cnt("SendChatMessage") == 2 and Cnt('"WHISPER"') == 1
	and Cnt("local send = C_ChatInfo and C_ChatInfo%.SendChatMessage or SendChatMessage") == 1)
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
ok("rand: SUM rfart=2", RLast(" SYNC SUM "):find(" rfart=2$") ~= nil, RLast(" SYNC SUM "))

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
ok("rand: Options checkbox Random farts", s ~= nil and s.name == "Random farts" and s.default == true)
s:SetValue(false)
ok("rand: checkbox off", SpokenWindDB.random == false and LogHas("OPT random=false by=panel") and RN("RAND skip why=off") == 2)
Tick(9000)
ok("rand: checkbox off = none", Rands() == 0)
s:SetValue(true)
ok("rand: checkbox on", SpokenWindDB.random == true and RN("RAND on") == 3)
Slash("random off")
Slash("reset")
ok("rand: reset = on again", SpokenWindDB.random == true and RN("RAND on") == 4)
for _, c in ipairs(reg.controls) do
	if c.s.key == "random" then ok("rand: tip terse", c.tip == "1 /fart per hour + on waking", c.tip) end
end
-- saved off: no wait at login
Boot({ random = false })
ok("rand: saved off: no wait, one off line", RN("RAND on") == 0 and RN("RAND skip why=off") == 1
	and LogHas(" rnd=0 tgt=0 aur=1 rev=12 "), LastLog())
Tick(9000)
ok("rand: saved off: none", Rands() == 0)
-- no options page (an old client): /wind random still works
Boot(nil, nil, "old")
ok("rand: no page: no page settings", ns.panelSettings == nil)
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
	ok("rand probe: max 30 lines per session", RN("RAND aura ") == 30, RN("RAND aura "))
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
local N, art, leg, tierN, seen, nSeen = 200000, 0, 0, { 0, 0, 0, 0, 0 }, {}, 0
for h = 0, N - 1 do
	local i = ns.VoicePick(VH, h)
	local s = snd[i]
	if s.tier == 7 then art = art + 1 elseif s.tier == 6 then leg = leg + 1 else tierN[s.tier] = tierN[s.tier] + 1 end
	if not seen[i] then seen[i], nSeen = true, nSeen + 1 end
end
ok("pick: Artifact exactly 1 in 5000, the legend 1 in 500", art == 40 and leg == 400, art .. " " .. leg)
local rest, far = N - art - leg, nil
for t, w in ipairs({ 25, 35, 22, 13, 5 }) do
	local pct = tierN[t] / rest * 100
	if math.abs(pct - w) > 0.5 then far = ("tier %d: %.2f%%"):format(t, pct) end
end
ok("pick: the tiers by weight (poor 25, common 35, uncommon 22, rare 13, epic 5)", far == nil, far)
ok("pick: every sound of the voice + the 5 Artifacts can come", nSeen == 74 + 5, nSeen)
local L1 = VH.tiers[6][1]
ok("pick: hash % 100000: 0-19 Artifact, 20-219 the legend, 220+ a tier", snd[ns.VoicePick(VH, 0)].tier == 7
	and snd[ns.VoicePick(VH, 19)].tier == 7 and snd[ns.VoicePick(VH, 100019)].tier == 7 and ns.VoicePick(VH, 20) == L1
	and ns.VoicePick(VH, 219) == L1 and snd[ns.VoicePick(VH, 220)].tier <= 5)
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
for h = 300, 100000 do   -- hash % 100000 >= 220: no Artifact, no legend
	local x = (h * 48271 % 2147483647) % 65
	if not hT1 and x < 25 then hT1 = h end
	if not hT5 and x >= 60 then hT5 = h end
end
ok("pick: a voice with gaps: weights of its own tiers", ns.VoicePick(FV, hT1) == 15 and ns.VoicePick(FV, hT5) == 18)
local p1 = ns.VoicePick(FV, hT1, 15)
ok("pick: a 1-sound tier twice = the next tier (fixed order)", p1 == 16 or p1 == 17, p1)
ok("pick: the last tier wraps to the first", ns.VoicePick(FV, hT5, 18) == 15)

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
LoadKB(true)   -- 2 settle loads: the first frees what the blocks before left
LoadKB(true)
local addKB, msSet = LoadKB(false)   -- before: the old 14; after: the set (the old load is freed)
local _, msOld = LoadKB(true)
out(("LOADCOST rows=%.1fms/%.0fKB addon=+%.0fKB load=%.1fms old=%.1fms (LuaJIT, median of 5)"):format(ms, kb, addKB,
	msSet, msOld))
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
ok("wire: the fart log shows the set number + name", ns.FartLogLines(3)[2][1]:find(" · #" .. tostring(num) .. " "
	.. tostring(s.name), 1, true) ~= nil, ns.FartLogLines(3)[2][1])
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
ok("set pages: Human M 0/74, Artifact 0/5", L2.pageHead == "Human M 0/74" and #L2.sounds == 74 and L20.pageHead == "Artifact 0/5"
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
ok("set pages: a heard Artifact: Artifact 1/5, its name", L20.pageHead == "Artifact 1/5" and heard
	and heard.name == "#1335 The Final Sputter" and Row("complete").stat == "1/1337", heard and heard.name)
ok("set pages: fit = the label once heard, also when not heard", L2.sounds[1].fit == "#1 " .. snd[15].name
	and heard.fit == heard.name and L20.sounds[1].fit == "#1333 Never Trust It", L2.sounds[1].fit)
V.Wait(12)
Slash("ach collection")
local W, TB, TL, TIP, ST, SP, SN, PG2 = ns.AchFrames()
ok("set window: page 1 = Original, the height fits", PG2.text.text == "Original 0/14" and W.h == ns.DexWinH(5, 14, 20), W.h)
PG2.nxt.scripts.OnMouseUp(PG2.nxt, "LeftButton")
ok("set window: > = Human M, 74 tiles, 2-line rows (30 px), no scroll bar, on the screen", PG2.text.text == "Human M 0/74"
	and SN[74].shown and SN[1].h == 30 and SN[74].h == 30 and W.h == ns.DexWinH(5, 74, 20, 30) and W.h < 768, W.h)
PG2.prev.scripts.OnMouseUp(PG2.prev, "LeftButton")
PG2.prev.scripts.OnMouseUp(PG2.prev, "LeftButton")
ok("set window: < from page 1 = Artifact", PG2.text.text == "Artifact 1/5" and SN[5].shown and not SN[6].shown
	and W.h == ns.DexWinH(5, 5, 20, SN[1].h), PG2.text.text)
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

-- the sound labels: wrap; a row fits its tallest label (fake font: 5.5 px a char, 12 px a line; label 90 px)
local function Find(p) for _, l in ipairs(SpokenWindDB.log or {}) do if l:find(p, 1, true) then return l end end end
local function Cnt(p)
	local k = 0
	for _, l in ipairs(SpokenWindDB.log or {}) do if l:find(p, 1, true) then k = k + 1 end end
	return k
end
V.Boot(nil)
Slash("ach collection")
local W, _, _, _, _, _, SN, PG2 = ns.AchFrames()
local AW = ns.ACH_WIN
ok("fit: Original: short names = one 22 px row, the label wraps", SN[1].h == 22 and SN[1].text.wrap == true
	and SN[1].text.width == AW.sndTW and AW.sndTW == 90 and W.h == -(SN[14].point[5]) + 22 + 14, W.h)
PG2.nxt.scripts.OnMouseUp(PG2.nxt, "LeftButton")
ok("fit: Human M: 2-line labels = 30 px rows, the window ends under the last row", SN[1].h == 30 and SN[74].h == 30
	and SN[6].point[5] == SN[1].point[5] - 34 and W.h == -(SN[74].point[5]) + 30 + 14 and W.h < 768, W.h)
for _ = 1, 19 do PG2.nxt.scripts.OnMouseUp(PG2.nxt, "LeftButton") end
PG2.prev.scripts.OnMouseUp(PG2.prev, "LeftButton")
ok("fit: Artifact: '#1333 Never Trust It' (110 px) wraps = 30 px rows", PG2.text.text == "Artifact 0/5" and SN[1].h == 30
	and SN[5].h == 30 and W.h == -(SN[5].point[5]) + 30 + 14, PG2.text.text .. " " .. tostring(SN[1].h))
local fl = Find("DEX fit ") or ""
out("fit audit (fake font): " .. fl)
ok("fit: one audit line a session (20 pages drawn)", Cnt("DEX fit ") == 1, Cnt("DEX fit "))
ok("fit: the audit: 1351 labels, nothing cut, the tallest page fits the screen", fl:sub(-77) == "DEX fit labels=1351 rowH=22-30 line=12 lines=2 trunc=0 est=0 winH=682 scr=768", fl)
TS.fontH0 = true
V.Boot(nil)
Slash("ach collection")
W, _, _, _, _, _, SN, PG2 = ns.AchFrames()
PG2.nxt.scripts.OnMouseUp(PG2.nxt, "LeftButton")
fl = Find("DEX fit ") or ""
ok("fit: no height from the game = a safe guess (6 px a char, 12 a line), est in the audit", SN[1].h == 30
	and fl:find(" line=0 lines=0 trunc=0 est=1351 ", 1, true) ~= nil, fl)
TS.fontH0 = nil
TS.fontCut = true
V.Boot(nil)
Slash("ach collection")
fl = Find("DEX fit ") or ""
ok("fit: a label the game cuts = counted (trunc)", fl:find(" trunc=1351 ", 1, true) ~= nil, fl)
TS.fontCut, TS.noCut = nil, true
V.Boot(nil)
Slash("ach collection")
fl = Find("DEX fit ") or ""
ok("fit: no IsTruncated in this client = trunc=?", fl:find(" trunc=? ", 1, true) ~= nil, fl)
TS.noCut = nil
-- A narrower font (4.5 px a char): on the Artifact page '#1334 The Final Sputter' = 103.5 px (2 lines at the
-- 90 px label, 1 line at the 112 px cell) and the LAST label '#1337 The Stutter' = 76.5 px (1 line).
-- The row must fit the tallest label (not the last one), measured at the label width (not the cell width).
TS.fontW = 4.5
V.Boot(nil)
Slash("ach collection")
W, _, _, _, _, _, SN, PG2 = ns.AchFrames()
local h1 = SN[1].h
PG2.prev.scripts.OnMouseUp(PG2.prev, "LeftButton")
ok("fit: the row fits the tallest label, measured at the label width (not the last one, not the cell)",
	h1 == 22 and PG2.text.text == "Artifact 0/5" and SN[1].h == 30 and SN[5].h == 30
	and W.h == -(SN[5].point[5]) + 30 + 14, PG2.text.text .. " " .. tostring(h1) .. " " .. tostring(SN[1].h))
TS.fontW = nil
ok("legend rows + fit: nothing forbidden, no chat line", #forbidden == forb0 and #sent == 0, forbidden[#forbidden])
V.Wait(12)
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
	if not BASE[key] and not key:match("^SLASH_SPOKENWIND_%u+1$") and not ({ SpokenWindDB = 1, SLASH_SPOKENWIND1 = 1, SLASH_SPOKENWIND2 = 1, SlashCmdList = 1,
		CreateFrame = 1, GetTime = 1, date = 1, time = 1, PlaySoundFile = 1, UnitGUID = 1, UnitName = 1, GetLocale = 1,
		EMOTE41_TOKEN = 1, EMOTE41_CMD1 = 1, SetCVar = 1, hooksecurefunc = 1, SendChatMessage = 1, DoEmote = 1,
		RunMacroText = 1, CastSpellByName = 1, UseAction = 1, SetBinding = 1, Settings = 1,
		MinimalSliderWithSteppersMixin = 1, CreateSettingsButtonInitializer = 1, InterfaceOptions_AddCategory = 1,
		CreateSettingsListSectionHeaderInitializer = 1, UIParent = 1, BackdropTemplateMixin = 1, BNToastFrame = 1,
		ChatFrame1 = 1, InCombatLockdown = 1, ITEM_QUALITY_COLORS = 1, BACKDROP_TOAST_12_12 = 1, SetBindingClick = 1,
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
