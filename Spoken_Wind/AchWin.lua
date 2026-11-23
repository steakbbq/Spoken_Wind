-- Spoken Wind: the achievements window (0.8.0 UI). OUR OWN frame SpokenWindAch, from the generated UI files:
--   sw-ach             the window: logo, "Spoken Wind", N/M done, Options, Rewards, ?, x, 4 tabs
--   sw-ach-classic     Farts, Rewards N/M, Secret N/M tag, the tiles (2 a row)
--   sw-ach-social      Heard by, People, Best, Born, Witness, "SW players met N" tag, the tiles
--   sw-ach-collection  Sounds N/M, own, tiers; the 5 Collection tiles; voice chips; the sounds of one voice (4 a row, pages)
--   sw-ach-board       All: Farts, Listened, Players, tiers; Most heard + Top listener (top 10), your rows under them
-- Made on the first open. Opened by the bar (left click), /wind ach, the Options button and a toast click.
-- A tile: icon, name in its quality color (dim until earned), rule, date or progress, a bar. A secret row not
-- earned yet is a "???" tile (not the dev-only Test row). Hover = the tip box (sw-tip); a click pins it.
-- A heard sound: click = play it here (ns.DexPlay). A toast click: the row's tab, its tile glows GLOW_S s.
-- Place: SpokenWindDB.achpos = its top left (drag the head). Combat closes it.
-- Rules: own frames only. No keyboard, no ESC close (no esc hook), no Blizzard writes.
local _, ns = ...
local Look, Looks = ns.Look, ns.Looks

local TABS = { "classic", "social", "collection", "board" }
local BODY = { classic = "sw-ach-classic", social = "sw-ach-social", collection = "sw-ach-collection", board = "sw-ach-board" }
local TAB_OF = {}
for k, v in pairs(BODY) do TAB_OF[v] = k end
local BTN = { classic = "tabClassicText", social = "tabSocialText", collection = "tabCollText", board = "tabBoardText" }
-- item quality (0-6) -> palette color
local Q = { [0] = "poor", "common", "uncommon", "rare", "epic", "legend", "artifact" }
local TIER_L = { "P", "C", "U", "R", "E", "L", "S" }
-- voice chip labels: "Hu M 12"
local SHORT = { Original = "Orig", Shartifact = "Shart", Human = "Hu", Dwarf = "Dw", ["Night Elf"] = "NE", Gnome = "Gn", Orc = "Or",
	Undead = "Ud", Tauren = "Ta", Troll = "Tr", Skyborne = "Sk" }
local QMARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local NO_PLACE = { testsmell = true }   -- secret rows with no "???" tile (dev only)
local BAR_W = 76                         -- px of a tile's progress bar
-- The own-roll star (sound rows + the Own count): our flat star texture (Media/star.tga, white), inline, tinted with the
-- design gold (palette gold 1, 0.82, 0 = 255, 209, 0). No font glyph, so never a box when a font is refused.
local STAR = "|T" .. ns.MEDIA .. "star.tga:0:0:0:0:64:64:0:64:0:64:255:209:0|t"
local NBSP = "\194\160"
local GLOW_S, GLOW_P = 5, 1.2            -- toast click: the tile glows 5 s, one pulse per 1.2 s
local GLOW_TEX = "Interface\\Buttons\\UI-ActionButton-Border"
local CHIPS, PER_ROW = 20, 4             -- voice chips, sounds a row
local TOP_Y = -120                       -- no saved place: this far below the screen top

local db
local w, T                   -- sw-ach refs, Look.Tabs
local bodies = {}            -- body id -> refs
local cur = "classic"
local vpage = 1              -- Collection: the voice page (chip)
local quiet                  -- a Select from the code: no draw, no log
local expand = {}            -- body id -> true: a fold click showed every row (till the window hides)
local lineOf = setmetatable({}, { __mode = "k" })    -- node -> its line now
local tabOf = setmetatable({}, { __mode = "k" })     -- tile node -> its tab
local hooked = setmetatable({}, { __mode = "k" })
local sounds = {}            -- the sound lines of the voice page shown
local pinned, over
local glowId, glowT0

local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- "4,210"
local function Comma(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local k
	repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
	return s
end

local function TierRun(t)
	local p = {}
	for i = 1, #TIER_L do
		if (t[i] or 0) > 0 then
			if #p > 0 then p[#p + 1] = { NBSP, "dim" } end
			p[#p + 1] = { TIER_L[i] .. (t[i] or 0), Q[i - 1] }
		end
	end
	return #p > 0 and Look.Run(p) or ""
end

local function TierName(q)
	local n = ns.B and ns.B.TIER_NAMES and ns.B.TIER_NAMES[(q or 0) + 1]
	return n and Look.Run({ { n, Q[q] or "common" } }) or ""
end

-- ------------------------------------------------------------ tips
local TipOf, StopGlow   -- node -> title, rows; the glow off (below)

local function TipShow(node)
	if not node or InCombat() or not ns.UITip then return end
	local title, rows = TipOf(node)
	if title then ns.UITip(node, title, rows) end
end

local function TipHide()
	if ns.UITipHide then ns.UITipHide() end
end

local function Enter(node)
	over = node
	if glowId and lineOf[node] and lineOf[node].id == glowId then StopGlow() end   -- the mouse on the glowing tile ends it
	TipShow(node)
end

local function Leave(node)
	if over == node then over = nil end
	if pinned and pinned ~= node and pinned:IsVisible() then TipShow(pinned)
	elseif pinned ~= node then TipHide() end
end

local function Pin(node)
	if InCombat() then return end
	if pinned == node then pinned = nil else pinned = node end
	TipShow(node)
end

local function Unpin()
	pinned, over = nil, nil
	TipHide()
end

TipOf = function(node)
	local l = lineOf[node]
	if not l then return nil end
	local click = { "Click", Look.Run({ { pinned == node and "Unpin" or "Pin", "dim" } }) }
	if l.kind == "tier" then
		local rows = {}
		for i, name in ipairs(ns.B and ns.B.TIER_NAMES or {}) do rows[i] = { Look.Run({ { name, Q[i - 1] } }), Comma(l.t[i] or 0) } end
		return Look.Run({ { "Tiers " .. l.head, "gold" } }), rows
	elseif l.kind == "all" then
		local rows = { { "Players", Comma(l.all.p) } }
		if l.all.oldest then rows[#rows + 1] = { "Oldest", date("%m-%d", l.all.oldest) } end
		rows[#rows + 1] = { "Seen", Look.Run({ { (l.seen:gsub("^Seen ", "")), "gold" } }) }
		if l.age then rows[#rows + 1] = { "Top 10", ("%d d"):format(l.age) } end
		return Look.Run({ { "All players", "gold" } }), rows
	elseif l.kind == "board" then
		local rows = { { "Farts", Comma(l.f) }, { "Heard", Comma(l.h) }, { "Listened", Comma(l.l) } }
		if l.me then rows[#rows + 1] = { "Char", "This" }
		elseif l.own then rows[#rows + 1] = { "Char", "Yours" }
		elseif l.at then
			local d = math.floor((time() - l.at) / 86400)
			rows[#rows + 1] = { "Seen", d <= 0 and "Today" or ("%d d ago"):format(d) }
		end
		if l.hidden then rows[#rows + 1] = { "Hidden", Look.Run({ { "/wind board on", "gold" } }) } end
		rows[#rows + 1] = click
		return Look.Run({ { l.name, l.hidden and "dim" or (l.own and "gold" or "text") } }), rows
	elseif l.kind == "sound" then
		if not l.heard then return Look.Run({ { l.name, "dim" } }), { { "Heard", "0" } } end
		local rows = { { "Tier", TierName(l.q) }, { "Heard", Comma(l.n) }, { "Own", Comma(l.own) } }
		if (l.t or 0) > 0 then rows[#rows + 1] = { "First", date("%m-%d", l.t) } end
		rows[#rows + 1] = { "Click", Look.Run({ { "Play", "gold" } }) }
		return Look.Run({ { "#" .. l.num .. " ", "dim" }, { l.sname, Q[l.q] or "common" } }), rows
	end
	if l.place then return Look.Run({ { "???", "dim" } }), { { "Rule", "Secret" }, click } end
	local rows = { { "Rule", l.rule or "" }, { "Tier", TierName(l.q) } }
	if l.done then rows[#rows + 1] = { "Done", date("%m-%d", l.t) }
	elseif l.stat and l.stat ~= "" then rows[#rows + 1] = { "Progress", l.stat } end
	if l.cmd then rows[#rows + 1] = { "Reward", Look.Run({ { l.cmd, l.done and "gold" or "dim" } }) } end
	rows[#rows + 1] = click
	return Look.Run({ { l.name, l.done and (Q[l.q] or "common") or "dim" } }), rows
end

-- Hover + click hooks, once per node; they read lineOf[node] now.
local function Hook(node, click)
	if hooked[node] then return end
	hooked[node] = true
	node:HookScript("OnEnter", Enter)
	node:HookScript("OnLeave", Leave)
	if click and node.RegisterForClicks then
		node:HookScript("OnClick", function(self, button)
			if button and button ~= "LeftButton" then return end
			click(self)
		end)
	end
end

-- A mouse spot over a text (a strip number): own frame, no keys.
local function Hit(fs, line)
	local f = fs._swHit
	if not f then
		f = CreateFrame("Frame", nil, fs:GetParent())
		f:SetAllPoints(fs)
		f:EnableMouse(true)
		f:SetScript("OnEnter", Enter)
		f:SetScript("OnLeave", Leave)
		fs._swHit = f
	end
	lineOf[f] = line
	if line then f:Show() else f:Hide() end
	return f
end

-- ------------------------------------------------------------ glow
local function GlowOf(c, q)
	local g = c._swGlow
	if not g then
		local icon = c._swIcon or c
		local s = (icon.GetWidth and icon:GetWidth() or 0) * 1.7
		if s <= 0 then s = 68 end
		g = c:CreateTexture(nil, "OVERLAY")
		g:SetTexture(GLOW_TEX)
		g:SetBlendMode("ADD")
		g:SetSize(s, s)
		g:SetPoint("CENTER", icon, "CENTER", 0, 0)
		c._swGlow = g
	end
	local col = Look.C(Q[q] or "common")
	g:SetVertexColor(col[1], col[2], col[3])
	return g
end

StopGlow = function()
	glowId = nil
	for c in pairs(tabOf) do if c._swGlow then c._swGlow:Hide() end end
	if w then w.root:SetScript("OnUpdate", nil) end
end

-- The tile that shows row id now (its tab shown), or nil.
local function TileOf(id)
	for c, tab in pairs(tabOf) do
		local l = lineOf[c]
		if tab == cur and l and l.id == id and not l.place and c:IsShown() then return c end
	end
end

local function GlowTick()
	local dt = GetTime() - glowT0
	if not glowId or dt >= GLOW_S then StopGlow() return end
	local a = 0.4 + 0.6 * (0.5 + 0.5 * math.cos(2 * math.pi * dt / GLOW_P))
	local c = TileOf(glowId)
	for x in pairs(tabOf) do
		if x._swGlow and x ~= c then x._swGlow:Hide() end
	end
	if c then
		local g = GlowOf(c, lineOf[c].q)
		g:SetAlpha(a)
		g:Show()
	end
end

-- Tests + the glow: the rows of the last fill pass only. A page turn or a relayout fills again (maybe the
-- same ls): a new pass = a new ls, a new page, or the row index starts again.
local function Rec(b, r, i, ls)
	if b._swLs ~= ls or b._swPg ~= ls.page or i <= (b._swI or 0) then b._swLs, b._swPg, b._swRows = ls, ls.page, {} end
	b._swI = i
	b._swRows[#b._swRows + 1] = r
end

-- ------------------------------------------------------------ tiles
-- A tile on: state (base = earned, off = not), icon, name, rule, date or progress, bar.
local function Paint(tab, cell, icon, name, rule, stat, fill, l)
	lineOf[cell], tabOf[cell] = l, tab
	cell._swIcon = icon
	Look.State(cell, not l.done and "off" or nil)   -- state first: it recolors the runs of the text there now
	icon:SetTexture(l.icon)
	if icon.SetVertexColor then icon:SetVertexColor(1, 1, 1) end
	icon:SetDesaturated(not l.done)
	Look.SetText(name, Look.Run({ { l.name, l.done and (Q[l.q] or "common") or "dim" } }))
	Look.SetText(rule, l.rule or "")
	local s = l.done and date("%m-%d", l.t) or l.stat or ""
	Look.SetText(stat, s ~= "" and Look.Run({ { s, l.done and "good" or "dim" } }) or "")
	local f = l.done and 1 or ((l.goal or 0) > 0 and (l.have or 0) / l.goal) or 0
	if f > 0 then
		fill:SetWidth(math.max(1, BAR_W * math.min(f, 1)))
		fill:Show()
	else
		fill:Hide()
	end
	cell:Show()
	Hook(cell, Pin)
end

-- The tiles of a tab: AchLines (earned first) + a "???" tile per secret row not earned (end of the list).
local function Tiles(lines)
	local list = {}
	for i, l in ipairs(lines.tiles) do list[i] = l end
	for _, row in ipairs(ns.ACH) do
		if row.tab == lines.tab and row.secret and not NO_PLACE[row.id] and not ns.AchHas(row.id) then
			list[#list + 1] = { id = row.id, place = true, icon = QMARK, name = "???", q = row.q, done = false,
				rule = "Secret", stat = "?" }
		end
	end
	return list
end

-- Classic / Social: the tiles 2 a row (GrowList, folds at the body bottom).
local function PairList(tab, b, list)
	local id = BODY[tab]
	local function Side(r, X, l)
		local cell = r["cell" .. X]
		if not l then
			cell:Hide()
			lineOf[cell] = nil
			return
		end
		Paint(tab, cell, r["icon" .. X], r["name" .. X], r["rule" .. X], r["stat" .. X], r["fill" .. X], l)
	end
	b._swRows, b._swLs, b._swI = {}, nil, nil
	b._swList = Look.GrowList(b, Looks[id].lists[1], math.ceil(#list / 2), function(r, i, ls)
		Rec(b, r, i, ls)
		Side(r, "A", list[2 * i - 1])
		Side(r, "B", list[2 * i])
	end, { free = expand[id] and math.huge or nil, onFold = function()
		expand[id] = true
		ns.AchRedraw()
	end })
end

-- ------------------------------------------------------------ tab bodies
local DRAW = {}

DRAW.classic = function(b, lines)
	local s = ns.HeardNums and ns.HeardNums() or { own = 0 }
	Look.SetText(b.farts, Comma(s.own))
	local n = 0
	for _, r in ipairs(ns.REWARDS or {}) do if ns.AchHas(r.ach) then n = n + 1 end end
	Look.SetText(b.rew, ("%d/%d"):format(n, #(ns.REWARDS or {})))
	local got, all = 0, 0
	for _, row in ipairs(ns.ACH) do
		if row.tab == "classic" and row.secret then
			local has = ns.AchHas(row.id)
			if has then got = got + 1 end
			if has or not NO_PLACE[row.id] then all = all + 1 end
		end
	end
	Look.State(b.secret, got > 0 and "good" or nil)
	Look.Tag(b.secret, ("Secret %d/%d"):format(got, all))
	PairList("classic", b, Tiles(lines))
end

DRAW.social = function(b, lines)
	local s = ns.HeardNums and ns.HeardNums() or {}
	Look.SetText(b.heard, Comma(s.heard))
	Look.SetText(b.people, Comma(s.people))
	Look.SetText(b.best, Comma(s.best))
	Look.SetText(b.born, Comma(s.legend))
	Look.SetText(b.wit, Comma(s.legendHeard))
	local bl = ns.BoardLines and ns.BoardLines() or nil
	local p = bl and bl.all.pb or 0   -- other players only (all.p has your own characters too)
	Look.State(b.swn, p > 0 and "good" or nil)
	Look.Tag(b.swn, "SW players met " .. Comma(p))
	PairList("social", b, Tiles(lines))
end

-- One sound slot (A-D) of a sound row.
local function Slot(r, X, l)
	local s = r["s" .. X]
	lineOf[s] = l
	if not l then s:Hide() return end
	Look.State(s, not l.heard and "off" or nil)
	if l.heard then
		Look.SetText(r["n" .. X], Look.Run({ { "#" .. l.num .. NBSP, "dim" }, { l.sname, Q[l.q] or "common" } }))
	else
		Look.SetText(r["n" .. X], Look.Run({ { "#" .. l.num .. NBSP .. "???", "dim" } }))
	end
	Look.SetText(r["star" .. X], STAR)
	r["star" .. X]:SetAlpha(l.star and 1 or 0)
	s:Show()
	Hook(s, function(self)
		local x = lineOf[self]
		if x and x.heard and ns.DexPlay then ns.DexPlay(x) end
	end)
end

-- Voice chips wrap (0.8.4). The design has 2 rows of 10 chips, and a row does not wrap by itself. Real text can be wider
-- (the real fonts, 2-digit counts), so the last chip of a row ran past the window edge. Now the shown chips flow left to
-- right and a chip that does not fit starts the next line. Min 2 lines (the design look), more when needed. The voice box
-- grows and the sound list below starts lower (its pages hold fewer rows). Every chip stays whole: no scroll, none hidden.
local CHIP_X, CHIP_Y, CHIP_GAP, CHIP_LINE = 10, 4, 4, 32   -- design: row inset, top gap, gap between chips, line step (28 + 4)
local VOICE_Y, VOICE_PAD = 206, 6.635                       -- design: the voice box top in the tab body, space under the last line
local chipLines = setmetatable({}, { __mode = "k" })        -- body refs -> lines used now

-- Places the shown chips; true = the number of lines changed.
local function ChipWrap(b)
	local W = b.vrow1:GetWidth()
	if type(W) ~= "number" or W < 1 then W = b.root:GetWidth() - 2 * CHIP_X end
	local x, line = 0, 0
	for k = 1, CHIPS do
		local c = b["v" .. k]
		if c:IsShown() then
			local cw = c:GetWidth()
			if x > 0 and x + cw > W + 0.01 then line, x = line + 1, 0 end
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", b.voices, "TOPLEFT", CHIP_X + x, -(CHIP_Y + line * CHIP_LINE))
			x = x + cw + CHIP_GAP
		end
	end
	local lines = math.max(2, line + 1)
	local h = lines * CHIP_LINE + VOICE_PAD                    -- 2 lines = 70.635 (the design)
	b.voices:SetHeight(h)
	b.sndList:SetPoint("TOPLEFT", b.root, "TOPLEFT", 0, -(VOICE_Y + h))
	local was = chipLines[b]
	chipLines[b] = lines
	return was ~= nil and was ~= lines
end

-- A chip changed width after the draw (a font loaded: Look.Refit): wrap again next frame; new line count = draw again.
local wrapDue
local function ChipSized()
	if wrapDue then return end
	wrapDue = true
	C_Timer.After(0, function()
		wrapDue = nil
		local b = bodies[BODY.collection]
		if b and ChipWrap(b) then ns.AchRedraw() end
	end)
end

DRAW.collection = function(b, lines)
	Look.SetText(b.sounds, ("%s/%s"):format(Comma(lines.have or 0), Comma(lines.all or 0)))
	Look.SetText(b.ownG, STAR)
	local d = ns.DexNums and ns.DexNums() or { own = 0 }
	Look.SetText(b.own, Comma(d.own))
	local okT, t = pcall(function() return ns.TiersMine and (ns.TiersMine()) end)
	t = okT and t or nil
	Look.SetText(b.tiers, t and TierRun(t) or "")
	Hit(b.tiers, t and { kind = "tier", head = "Mine", t = t } or nil)
	-- the 5 Collection tiles (cell1 has no state table in the design: it takes cell2's)
	if not b._swCell1 then
		b._swCell1 = true
		Look.StBind(b.cell1, nil, Looks["sw-ach-collection"], "cell2", 1, 1)
	end
	for k = 1, 5 do
		local l = lines.tiles[k]
		local cell = b["cell" .. k]
		if l then
			Paint("collection", cell, b["icon" .. k], b["name" .. k], b["rule" .. k], b["stat" .. k], b["fill" .. k], l)
		else
			cell:Hide()
			lineOf[cell] = nil
		end
	end
	-- voice chips: "Hu M 12"; the page shown = sel, none heard = off, all heard = good
	local pages = d.pages or {}
	for k = 1, CHIPS do
		local c, p = b["v" .. k], pages[k]
		if p then
			local base, sex = p.name:match("^(.-) ([MmFf])$")
			local label = base and ((SHORT[base] or base) .. " " .. sex:upper()) or (SHORT[p.name] or p.name)
			Look.SetText(b["v" .. k .. "Text"], label .. " " .. (p.have or 0))
			Look.FitW(c)   -- its width from the new text now: the wrap below needs it
			Look.State(c, k == vpage and "sel" or (p.have or 0) == 0 and "off"
				or (p.have == #p.tiles and "good") or nil)
			c._swPage = k
			c:Show()
			if not hooked[c] then
				hooked[c] = true
				c:HookScript("OnSizeChanged", ChipSized)
				c:HookScript("OnClick", function(self)
					if InCombat() or vpage == self._swPage then return end
					vpage = self._swPage
					expand[BODY.collection] = "reset"
					Unpin()
					ns.AchRedraw()
					if w and w.root:IsShown() and cur == "collection" then
						local l2 = ns.AchLines("collection", vpage)
						ns.Log(("DEX show n=%d/%d page=%d/%d"):format(l2.have, l2.all, l2.page, l2.pages))
					end
				end)
			end
		else
			c:Hide()
		end
	end
	ChipWrap(b)   -- before the sound pages: they fit the list box under the chips
	Look.SetText(b.pageHeadText, lines.pageName or "")
	Look.SetText(b.pageHave, ("%d/%d"):format(lines.pageHave or 0, lines.pageAll or 0))
	sounds = lines.sounds or {}
	local reset = expand[BODY.collection] == "reset"
	expand[BODY.collection] = nil
	b._swRows, b._swLs, b._swI = {}, nil, nil
	b._swList = Look.Pages(b, Looks["sw-ach-collection"].lists[1], math.ceil(#sounds / PER_ROW), function(r, i, ls)
		Rec(b, r, i, ls)
		for k, X in ipairs({ "A", "B", "C", "D" }) do Slot(r, X, sounds[(i - 1) * PER_ROW + k]) end
	end, { reset = reset or nil, onPage = function() Unpin() end })
	Look.Refit(b.root)
end

-- One half of a Board row (A = Most heard, B = Top listener): me = sel, hidden = off.
local function Half(r, X, l)
	local h = r["h" .. X]
	lineOf[h] = l
	if not l then h:Hide() return end
	Look.State(h, l.me and "sel" or l.hidden and "off" or nil)
	Look.SetText(r["rk" .. X], tostring(l.rank))
	Look.SetText(r["nm" .. X], (l.own and not l.me and not l.hidden) and Look.Run({ { l.short, "gold" } }) or l.short)
	Look.SetText(r["n" .. X], Comma(l.num))
	h:Show()
	Hook(h, Pin)
end

DRAW.board = function(b, lines)
	local bl = lines.board
	if not bl then return end
	Look.SetText(b.farts, Comma(bl.all.f))
	Look.SetText(b.listened, Comma(bl.all.l))
	Look.SetText(b.players, Comma(bl.all.p))
	Look.SetText(b.tiers, TierRun(bl.all.t or {}))
	Hit(b.tiers, { kind = "tier", head = "All", t = bl.all.t or {} })
	Hit(b.allL, { kind = "all", all = bl.all, seen = bl.seen, age = bl.age })
	local A, B = lines.cols[1], lines.cols[2]
	local L = Looks["sw-ach-board"]
	b._swRows, b._swLs, b._swI = {}, nil, nil
	Look.GrowList(b, L.lists[1], math.max(#A.rows, #B.rows), function(r, i, ls)
		Rec(b, r, i, ls)
		if not r._swB then   -- the design's states cover the A half only: B gets its own unit with the same table
			r._swB = true
			Look.StBind(r.hB, nil, L, "r", 2, 5)
			Look.StMap(r.nmB, r.hB, 4)
			Look.StMap(r.nB, r.hB, 5)
		end
		Half(r, "A", A.rows[i])
		Half(r, "B", B.rows[i])
	end)
	-- your rows under the lists (not in a top 10)
	for X, col in pairs({ A = A, B = B }) do
		local o, l = b["own" .. X], col.own
		lineOf[o] = l
		if l then
			Look.SetText(b["ownRk" .. X], tostring(l.rank))
			Look.SetText(b["ownNm" .. X], l.short)
			Look.SetText(b["ownN" .. X], Comma(l.num))
			o:Show()
			Hook(o, Pin)
		else
			o:Hide()
		end
	end
	if A.own or B.own then b.ownRow:Show() else b.ownRow:Hide() end
	Look.Refit(b.root)
end

-- ------------------------------------------------------------ the window
local function ShowLog(lines)
	local b = lines.board
	if b then
		ns.Log(("BOARD show n=%d heard=%d listen=%d off=%d"):format(b.all.p, #b.heard, #b.listen, b.off and 1 or 0))
		ns.Log(("BOARD seen est=%s win=%d hits=%d"):format(b.est and tostring(b.est) or "?", b.win or 0, b.hits or 0))
	end
	if lines.sounds then
		ns.Log(("DEX show n=%d/%d page=%d/%d"):format(lines.have, lines.all, lines.page, lines.pages))
	end
end

local function Draw()
	local lines = ns.AchLines(cur, vpage)
	vpage = lines.page or vpage
	local all = 0
	for _, n in pairs(ns.ACH_MAIN or {}) do all = all + n end
	Look.SetText(w.total, ("%d/%d"):format(ns.AchDone and (ns.AchDone()) or 0, all))
	for _, tab in ipairs(TABS) do Look.SetText(w[BTN[tab]], ns.AchTabText(tab)) end
	if ns.BarShown and ns.BarShown() then w.rewards:Show() else w.rewards:Hide() end
	local b = bodies[BODY[cur]]
	if b then DRAW[cur](b, lines) end
	Look.Refit(w.root)
	if glowId then GlowTick() end
	return lines
end

local function Place()
	local f = w.root
	f:ClearAllPoints()
	local p = db and db.achpos
	if p then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
	else f:SetPoint("TOP", UIParent, "TOP", 0, TOP_Y) end
end

local function Moved(f)
	local l, t = f:GetLeft(), f:GetTop()
	if l and t and db then db.achpos = { x = math.floor(l + 0.5), y = math.floor(t + 0.5) } end
	Place()
end

local function Build()
	local L = Looks["sw-ach"]
	w = L.build(UIParent, Look.D(L.tokens))
	w.root:Hide()
	L.open(w)   -- the shell: HIGH strata, clamped, drag by the head (no esc hook: no ESC close)
	ns.UILogo(w.logo)
	ns.UIGlyph(w.help, "?")
	ns.UIGlyph(w.close, "\195\151")
	-- the drag: never in combat (the head is the handle)
	local head = w.head
	local start = head:GetScript("OnDragStart")
	head:SetScript("OnDragStart", function(...)
		if InCombat() then return end
		Unpin()
		if start then start(...) end
	end)
	if ns.UIOnMove then ns.UIOnMove(w.root, Moved) end
	quiet = true
	T = Look.Tabs(w, L, bodies, { lazy = true, onSelect = function(id)
		local tab = TAB_OF[id]
		if quiet or not tab then return end
		cur = tab
		Unpin()
		ShowLog(Draw())
	end })
	quiet = false
	w.close:HookScript("OnClick", function() w.root:Hide() end)
	w.help:HookScript("OnClick", function() if ns.HelloShow then ns.HelloShow("ach") end end)
	w.options:HookScript("OnClick", function() if ns.OptOpen then ns.OptOpen("ach") end end)
	w.rewards:HookScript("OnClick", function() if ns.RewardsToggle then ns.RewardsToggle() end end)
	-- combat closes it (never in the way)
	w.root:RegisterEvent("PLAYER_REGEN_DISABLED")
	w.root:SetScript("OnEvent", function(self) self:Hide() end)
	w.root:HookScript("OnHide", function()
		Unpin()
		StopGlow()
		for k in pairs(expand) do expand[k] = nil end
	end)
end

-- Opens the window (tab: "classic" / "social" / "collection" / "board", else the last one). false in combat
-- or before the save is read.
function ns.AchOpen(tab)
	if InCombat() or not db or not (Look and Looks and Looks["sw-ach"]) then return false end
	if not w then Build() end
	if BODY[tab] then cur = tab end
	Place()
	quiet = true
	T.Select(BODY[cur])
	quiet = false
	w.root:Show()
	local lines = Draw()
	ns.Log(("ACH open tab=%s n=%d"):format(cur, #lines.tiles))
	ShowLog(lines)
	return true
end

-- The bar (left click): open, or close when it is open.
function ns.AchToggle()
	if w and w.root:IsShown() then w.root:Hide() return false end
	return ns.AchOpen()
end

-- An earn, a reload of the save: the open window shows it.
function ns.AchRedraw()
	if w and w.root:IsShown() then Draw() end
end

-- Glows the tile of row id when the window shows it. true = a tile glows.
function ns.AchGlow(id)
	if not (w and w.root:IsShown()) then return false end
	StopGlow()
	if not TileOf(id) then return false end
	glowId, glowT0 = id, GetTime()
	w.root:SetScript("OnUpdate", GlowTick)
	GlowTick()
	return true
end

-- Toast click: the window on the row's tab, its tile glowing. Returns tab, glow.
-- In combat: no window, one short line (as /wind ach).
function ns.AchShow(id)
	local row = ns.AchRow(id)
	local tab = row and row.tab or cur
	if not ns.AchOpen(tab) then
		ns.Say("ach: not in combat")
		return tab, false
	end
	return tab, ns.AchGlow(id)
end

-- Achievements.lua at ADDON_LOADED: the save (achpos).
function ns.AchWinInit(saved) db = saved end

-- Tests: the refs (nil = not made yet), the tab bodies, the line of a node, the pinned node, the glow.
function ns.AchRefs() return w, bodies, T, lineOf, pinned, glowId end
