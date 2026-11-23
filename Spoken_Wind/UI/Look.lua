-- Spoken Wind UI runtime (Look.lua). MIT License, see LICENSE in the repo root.
-- Copyright (c) 2026 Spoken Wind authors
-------------------------------------------------------------------------------
--  Look.lua: the small generic helper that the converter output (out/look.lua) calls.
--  Lua 5.1, ASCII only. Load style:  local ADDON, ns = ...   sets ns.Look.
--  Real WoW API only: CreateFrame, CreateTexture, CreateFontString, SetColorTexture, SetPoint, ClearAllPoints, SetSize,
--  SetWidth, SetHeight, GetWidth, GetHeight, SetFont, SetText, GetStringWidth, SetJustifyH/V, SetWordWrap, SetTextColor,
--  SetShadowColor/Offset, SetAlpha, SetClipsChildren, IsShown.
--
--  API (every object that is made gets _lookId = the node id in look.ids.json; WoW ignores it):
--    Look.D(defaults, override)            -> D(sel, key): override(sel, key) if it gives a value, else defaults[sel][key]
--    Look.Frame(parent, id, kind [, name]) -> Frame ("Frame" | "Button" | "CheckButton"), child of parent; name = global frame name (a screen root)
--    Colors are ONE argument: a table { r, g, b, a } (baked in, or Look.C(name [, a]) read from the palette at run time).
--    Look.Bg(frame, id, color)             -> color texture over the whole frame (layer BACKGROUND)
--    Look.Edge(frame, id, side, w, wt, wb, color)  -> one border edge (layer BORDER); wt / wb = top / bottom widths
--    Look.Text(frame, id, font, size, color, justifyH, justifyV) -> FontString, no wrap, ellipsis by WoW
--    Look.Shadow(fs, dx, dy, color)        Look.Icon(frame, id, [color]) -> Texture   Look.Bind(frame, fs) (text of a box)
--    Look.palette  name -> { r, g, b }     the host sets it; default = L.palette of the converter output
--    Look.C(name [, a])                    -> { r, g, b, a } from Look.palette (error on an unknown name)
--    Look.sizes    role -> px              the host sets it (S / M / L); default = L.sizes of the converter output
--    Look.Size(role)                       -> px of a text role (error on an unknown role)
--    Look.L(text)                          -> the shown text of a static label; the host sets it to its LOC lookup, default = identity
--    Look.Hex(c)                           -> "|cffrrggbb" for a { r, g, b } table
--    Look.Run({ {text, color}, {text}, ... }, localize) -> one string with |c..|r codes; color = palette name or { r, g, b };
--                                          localize = true runs Look.L on every piece that is not blank
--    Look.SetText(node, s)                 node = FontString, or a box made around text; then call Look.Refit(root)
--    Look.Meta(frame, m) / Kid(frame, obj, m) / Group(frame, name) / Add(frame, obj, m, group)  (run time layout info)
--    Look.FitW(frame)  Look.Reflow(frame)  -> box as wide as its content / column that grows down to fit its rows
--    Look.Refit(frame)                     -> redo every FitW and Reflow below frame (post order). Call after text or rows change.
--    Look.FontSet(obj, path, size) -> ok   Look.Preload()   Look.fontRetry   font check + preload + retry v2 (lead block "font retry", docs\font-retry.md)
--  Meta of a frame: dir "row"|"col", l r t b (inner insets = border + padding), gap, fitW, dyn, autoH, text.
--  Kid meta: cls "S"|"L"|"C"|"R" (column x class), ml mr mt mb margins, txt (a FontString), fw (it has a fixed width).
-------------------------------------------------------------------------------
local ADDON, ns = ...
local Look = {}
ns.Look = Look

local max = math.max
-- ==== w3diag begin: feature flags the glue can test (Look.has.listBase: an open list takes its base height from the converted info.baseH, K3-5)
Look.has = Look.has or {}
Look.has.listBase = true
Look.has.listFit = true      -- k3fit (K3-8): an open list sets its base height from the rows of the call (the first min(count, opt.fit) rows) and shows a +N fold row when rows are left over
Look.has.menuCols = true     -- K3-9: a menu item row may carry 1..4 value columns (data-wow="col"); an entry gives e.cols = { "2s 09c", "71%" }; the columns line up across the rows
-- ==== w3diag end

function Look.D(defaults, override)
    return function(sel, key)
        if override then
            local v = override(sel, key)
            if v ~= nil then return v end
        end
        local t = defaults[sel]
        local v = t and t[key]
        if v == nil then error("Look.D: unknown token " .. tostring(sel) .. " / " .. tostring(key), 2) end
        return v
    end
end

local nextKind                                       -- wave3-i: Look.NextButton() makes the next Look.Frame a Button (a part copy with data-kind="button")
function Look.NextButton() nextKind = "Button" end
function Look.Frame(parent, id, kind, name)
    if nextKind then kind, nextKind = nextKind, nil end   -- wave3-i
    local f = CreateFrame(kind or "Frame", name, parent)
    f._lookId = id
    f._lookFrames = {}
    f._lookParent = parent
    local list = parent._lookFrames
    if list then list[#list + 1] = f end
    return f
end

-- ---------------------------------------------------------------- palette, sizes, labels, runs
Look.L = function(s) return s end

function Look.C(name, a)
    local pal = Look.palette
    local c = pal and pal[name]
    if not c then error("Look.C: unknown palette color " .. tostring(name), 2) end
    return { c[1], c[2], c[3], a or c[4] or 1 }
end

function Look.Size(role)
    local s = Look.sizes
    local v = s and s[role]
    if not v then error("Look.Size: unknown text role " .. tostring(role), 2) end
    return v
end

function Look.Hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

function Look.Run(pieces, localize)
    local out = {}
    for i = 1, #pieces do
        local p = pieces[i]
        local s = p[1]
        if localize and s:find("%S") then s = Look.L(s) end
        local c = p[2]
        if c then
            if type(c) == "string" then
                local pal = Look.palette
                c = pal and pal[c]
                if not c then error("Look.Run: unknown palette color " .. tostring(p[2]), 2) end
            end
            s = Look.Hex(c) .. s .. "|r"
        end
        out[#out + 1] = s
    end
    return table.concat(out)
end

function Look.Bg(f, id, c)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t._lookId = id
    t:SetColorTexture(c[1], c[2], c[3], c[4])
    t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f._lookBg = t       -- wave3-b: Look.State changes its color
    return t
end

-- top / bottom edges span the full width; left / right edges sit between them, so edges never overlap.
function Look.Edge(f, id, side, w, wt, wb, c, hair)      -- w3kit: hair = true / false / nil; a width under 1 (a CSS hair border) is sized to one screen pixel at run time
    local t = f:CreateTexture(nil, "BORDER")
    t._lookId = id
    t:SetColorTexture(c[1], c[2], c[3], c[4])
    if side == "top" then
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        t:SetHeight(w)
    elseif side == "bottom" then
        t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        t:SetHeight(w)
    elseif side == "left" then
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -wt)
        t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, wb)
        t:SetWidth(w)
    else
        t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -wt)
        t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, wb)
        t:SetWidth(w)
    end
    f._lookEdges = f._lookEdges or {}      -- wave3-b: Look.State changes the colors
    f._lookEdges[side] = t
    if Look._w3kit then Look._w3kit.edge(f, t, side, w, wt, wb, hair) end
    return t
end

function Look.Text(f, id, font, size, c, justifyH, justifyV)
    local fs = f:CreateFontString(nil, "ARTWORK")
    fs._lookId = id
    Look.FontSet(fs, font, size)          -- lead (font retry): was fs:SetFont(font, size, ""); a miss = game font now + retry chain
    fs:SetTextColor(c[1], c[2], c[3], c[4])
    fs:SetJustifyH(justifyH or "LEFT")
    fs:SetJustifyV(justifyV or "MIDDLE")
    fs:SetWordWrap(false)
    return fs
end

function Look.Shadow(fs, dx, dy, c)
    fs:SetShadowOffset(dx, dy)
    fs:SetShadowColor(c[1], c[2], c[3], c[4])
end

function Look.Icon(f, id, c)
    local t = f:CreateTexture(nil, "ARTWORK")
    t._lookId = id
    if c then t:SetColorTexture(c[1], c[2], c[3], c[4]) end
    return t
end

function Look.Bind(f, fs)
    f._lookText = fs
end

function Look.SetText(node, s)
    local fs = node._lookText or node
    fs:SetText(s)
end

-- ---------------------------------------------------------------- run time layout info
function Look.Meta(f, m)
    m.kids = m.kids or {}
    f._look = m
    if m.text then m.text = f._lookText end
end

function Look.Kid(f, obj, m)
    local k = f._look.kids
    k[#k + 1] = { obj = obj, m = m or {} }
end

function Look.Group(f, name)
    local k = f._look.kids
    k[#k + 1] = { group = name }
end

-- a repeated row: sits in front of its group marker (or at the end)
function Look.Add(f, obj, m, group)
    local m0 = f._look
    local k = m0.kids
    local e = { obj = obj, m = m or {} }
    for i = 1, #k do
        if k[i].group == group then
            table.insert(k, i, e)
            return
        end
    end
    k[#k + 1] = e
end

-- ---------------------------------------------------------------- fit
local function shown(obj)
    return obj:IsShown()
end

function Look.FitW(f)
    local m = f._look
    if not m then return end
    local w
    if m.text then
        w = f._lookText:GetStringWidth()
        w = w + m.l + m.r
    else
        local sum, widest, n = 0, 0, 0
        for i = 1, #m.kids do
            local e = m.kids[i]
            if e.obj and shown(e.obj) then
                local km = e.m
                local kw
                if km.txt and not km.fw then kw = e.obj:GetStringWidth(); local mx = e.obj._lookMaxW; if mx and kw > mx then kw = mx end else kw = e.obj:GetWidth() end
                kw = kw + (km.ml or 0) + (km.mr or 0)
                n = n + 1
                sum = sum + kw
                if kw > widest then widest = kw end
            end
        end
        if m.dir == "row" then
            w = sum + (n > 1 and (n - 1) * (m.gap or 0) or 0) + m.l + m.r
        else
            w = widest + m.l + m.r
        end
    end
    if Look._w3kit then w = Look._w3kit.cap(f, m, w) end      -- w3kit K3-3
    f:SetWidth(w)
end

-- a column that stacks its shown kids from the top, in order, and (autoH) grows down to fit.
function Look.Reflow(f)
    local m = f._look
    if not m or not m.dyn then return end
    local y = m.t
    local first = true
    local gap = m.gap or 0
    local ind = f._lookIndent or 0      -- k2b K2-5: Look.RowIndent moves the left edge of a column row's content
    for i = 1, #m.kids do      -- k2e K2-19: a fill kid (a pages list, km.fill) takes the height that is left, before the stack is laid out
        local e = m.kids[i]
        if e.obj and e.m.fill and shown(e.obj) then Look.K2eFill(f, m, e, gap); break end
    end
    for i = 1, #m.kids do
        local e = m.kids[i]
        local obj = e.obj
        if obj and shown(obj) then
            local km = e.m
            if not first then y = y + gap end
            first = false
            y = y + (km.mt or 0)
            obj:ClearAllPoints()
            local cls = km.cls
            if cls == "C" then
                obj:SetPoint("TOP", f, "TOP", (m.l + ind - m.r + (km.ml or 0) - (km.mr or 0)) / 2, -y)
            elseif cls == "R" then
                obj:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(m.r + (km.mr or 0)), -y)
            else
                obj:SetPoint("TOPLEFT", f, "TOPLEFT", m.l + ind + (km.ml or 0), -y)
                if cls == "S" then
                    obj:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(m.r + (km.mr or 0)), -y)
                end
            end
            y = y + obj:GetHeight() + (km.mb or 0)
        end
    end
    y = y + m.b
    if m.autoH then m.natH = y; f:SetHeight(y) end      -- k2b K2-6: natH = the height the rows need (the grip minimum of a window that follows its rows)
end

-- wave3-h (B7): weighted fill children (flex: N). A container with Meta wts = true holds two or more kids with km.wt (a whole weight). The free
-- space of the row (width) or column (height) = the inner size minus the other kids (width / height + margins) and the gaps; each fill takes
-- free * wt / sum(wt). Every fill but the last gets the size (SetWidth / SetHeight); the last one is anchored to the far chain and takes the rest.
function Look.Weights(f)
    local m = f._look
    if not (m and m.wts) then return end
    local row = m.dir == "row"
    local total = row and f:GetWidth() or f:GetHeight()
    if type(total) ~= "number" or total <= 0 then return end
    local gap = m.gap or 0
    local used = (row and (m.l + m.r) or (m.t + m.b)) + (#m.kids > 1 and (#m.kids - 1) * gap or 0)
    local sum, fills = 0, {}
    for i = 1, #m.kids do
        local e = m.kids[i]
        local km = e.m
        if e.obj then
            if km.wt then
                fills[#fills + 1] = e
                sum = sum + km.wt
                used = used + (row and ((km.ml or 0) + (km.mr or 0)) or ((km.mt or 0) + (km.mb or 0)))
            elseif row then
                local kw
                if km.txt and not km.fw then kw = e.obj:GetStringWidth(); local mx = e.obj._lookMaxW; if mx and kw > mx then kw = mx end else kw = e.obj:GetWidth() end
                used = used + kw + (km.ml or 0) + (km.mr or 0)
            else
                used = used + e.obj:GetHeight() + (km.mt or 0) + (km.mb or 0)
            end
        end
    end
    if sum <= 0 then return end
    local free = max(0, total - used)
    for i = 1, #fills - 1 do
        local sz = free * fills[i].m.wt / sum
        if row then fills[i].obj:SetWidth(sz) else fills[i].obj:SetHeight(sz) end
    end
    if not f._lookWtsHook then      -- the game resolves anchored sizes later: size the fills again when the container changes
        f._lookWtsHook = true
        pcall(function() f:HookScript("OnSizeChanged", function() Look.Weights(f) end) end)
    end
end

function Look.Refit(f)
    local list = f._lookFrames
    if list then
        for i = 1, #list do Look.Refit(list[i]) end
    end
    local m = f._look
    if m then
        if m.fitW then Look.FitW(f) end
        if m.dyn then Look.Reflow(f) end
        if m.wts then Look.Weights(f) end      -- wave3-h
    end
end

-- ================================================================ Wave 2 sections: each helper writes only inside its own pair
-- ==== wave2-a begin: window shell, popups, dialogs, dock, many windows (gap items 8 9 14 15). Docs: docs\wave2-a.md
--  L.shell = { type, frame, strata, level, rel, toplevel, clamp, movable, drag (o index), esc, owner, anchor = { POINT, OWNERPOINT, x, y },
--              dock = { frame, point, relPoint, x, y } }   (written by convert\screen_shell.py; L.open(refs, owner) calls the functions below)
--    Look.Shell(f, refs, shell)     strata / level / toplevel / clamp, drag by the handle (no keyboard, no ESC)
--    Look.Place(f, owner, shell)    sit on the owner at shell.anchor (no anchor: centered on it), strata from the shell or the owner
--    Look.Dock(f, shell)            sit beside a global frame while it shows, else back to the host's place;  Look.DockFree(f, bool)  Look.DockUpdate(f)
--    Look.Stack(f, strata, level)   strata and level of f and every Look frame below it (the children keep their level offsets)
--    Look.Scope(id) / Look.InScope(id, fn, ...)   objects made while a scope is set carry _lookScope = id;  Look.Id(obj) -> "<scope>:<_lookId>"
--  Host hooks (all optional, set on Look.hooks): moved(f, shell) after a drag
--  (save the place), undock(f, shell, why) puts f back at its saved place and returns true, docked(f, bool, why) tells the dock state.
Look.hooks = Look.hooks or {}
local pile = {}      -- kr-shell (S3): the dock pile functions, defined in section kr-shell
local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
Look.strataRank = STRATA_RANK

-- ---- scopes: many screens live in one Lua state. _lookId stays the node id (look.ids.json); _lookScope says which screen made the object.
Look.scope = nil
function Look.Scope(id)
    local old = Look.scope
    Look.scope = id
    return old
end
function Look.InScope(id, fn, ...)
    local old = Look.scope
    Look.scope = id
    local r = { pcall(fn, ...) }
    Look.scope = old
    if not r[1] then error(r[2], 0) end
    return unpack(r, 2)
end
function Look.Id(obj)
    local id = obj._lookId
    if id and obj._lookScope then return obj._lookScope .. ":" .. id end
    return id
end
for _, name in ipairs({ "Frame", "Bg", "Edge", "Text", "Icon" }) do
    local make = Look[name]
    Look[name] = function(...)
        local o = make(...)
        if Look.scope then o._lookScope = Look.scope end
        return o
    end
end

-- ---- stack: strata and level for f and its Look frames. WoW moves children with the parent; setting them again is the same value.
function Look.Stack(f, strata, level)
    local base = f:GetFrameLevel()
    local list, offs = {}, {}
    local function collect(x)
        local kids = x._lookFrames
        if not kids then return end
        for i = 1, #kids do
            local k = kids[i]
            list[#list + 1] = k
            offs[k] = k:GetFrameLevel() - base
            collect(k)
        end
    end
    collect(f)
    if strata then f:SetFrameStrata(strata) end
    if level then f:SetFrameLevel(level) end
    for i = 1, #list do
        local k = list[i]
        if strata then k:SetFrameStrata(strata) end
        if level then k:SetFrameLevel(level + offs[k]) end
    end
end

-- ---- shell
function Look.Shell(f, refs, shell)
    shell = shell or f._lookShell
    f._lookShell = shell
    if shell.strata or shell.level then Look.Stack(f, shell.strata, shell.level) end
    if shell.toplevel then f:SetToplevel(true) end
    if shell.clamp then f:SetClampedToScreen(true) end
    if shell.movable then
        local h = (shell.drag and refs and refs._o and refs._o[shell.drag]) or f
        f:SetMovable(true)
        h:EnableMouse(true)
        h:RegisterForDrag("LeftButton")
        h:SetScript("OnDragStart", function() f:StartMoving() end)
        h:SetScript("OnDragStop", function()
            f:StopMovingOrSizing()
            local d = f._lookDock
            if d then d.free = true end
            if Look.hooks.moved then Look.hooks.moved(f, shell) else Look.SavePlace(f) end      -- wave3-e: no hook = the store
            if refs and refs._lists then Look.Relayout(refs) end      -- wave3-j (J4): the screen room changed: an edge list shows more / fewer rows
        end)
    end
    Look.ShellResize(f, refs, shell)      -- wave3-e: the size grip
end

-- ---- place on an owner (panel, popup, menu, tooltip, toast, dialog)
function Look.Place(f, owner, shell)
    shell = shell or f._lookShell or {}
    owner = owner or UIParent
    local a = shell.anchor
    f:ClearAllPoints()
    if a then
        -- kr-shell (S3): a panel at a side of its owner does not sit on another panel / window of the same spot (pile.panel)
        if not (shell.type == "panel" and owner ~= UIParent and pile.panel(f, owner, a)) then f:SetPoint(a[1], owner, a[2], a[3], a[4]) end
    else f:SetPoint("CENTER", owner, "CENTER", 0, 0) end
    local level = shell.level
    if not level and shell.rel then level = owner:GetFrameLevel() + shell.rel end
    Look.Stack(f, shell.strata or owner:GetFrameStrata(), level)
end

-- ---- dock beside a global frame. Tests: it exists, shows, alpha 0.9 or more, scale like UIParent,
-- on screen, room for f on that side. The strata follows the frame when that is above HIGH and below FULLSCREEN_DIALOG (UI.StackWindow).
local function dockWhy(b, f, d)
    if not b then return "noframe" end
    if not b:IsShown() then return "hidden" end
    local a = b:GetAlpha()
    if type(a) == "number" and a < 0.9 then return "alpha" end
    local sc, pc = b:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if type(sc) ~= "number" or type(pc) ~= "number" or pc <= 0 then return "scale" end
    local k = sc / pc
    if k < 0.95 then return "scale" end
    local l, r, t, bt = b:GetLeft(), b:GetRight(), b:GetTop(), b:GetBottom()
    if not (l and r and t and bt) then return "nopos" end
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    if l * k < -1 or bt * k < -1 or t * k > uh + 1 then return "offscreen" end
    local w = f:GetWidth() or 0
    if d.relPoint:find("RIGHT", 1, true) and d.point:find("LEFT", 1, true) then
        if r * k + w + d.x > uw + 1 then return "noroom" end
    elseif d.relPoint:find("LEFT", 1, true) and d.point:find("RIGHT", 1, true) then
        if l * k - w + d.x < -1 then return "noroom" end
    end
    return nil
end

function Look.Dock(f, shell)
    shell = shell or f._lookShell
    local d = shell.dock
    local st = { free = false }
    f._lookDock = st
    local hooked = {}
    local pm = { f = f, placed = function() return st.docked end }      -- kr-shell (S3)
    local function update()
        local b = rawget(_G, d.frame)
        local why = st.free and "free" or dockWhy(b, f, d)
        local docked = (why == nil)
        local plan = docked and pile.plan(pm, b, d) or nil      -- kr-shell (S3): beside another window of the same spot
        if st.placed and docked == st.docked and why == st.why and (not docked or plan.sig == st.sig) then return end
        local wasDocked = st.docked
        st.placed, st.docked, st.why, st.sig = true, docked, why, plan and plan.sig
        local base = shell.strata or "HIGH"
        if docked then
            pile.apply(f, plan)
            local s, bs = base, b:GetFrameStrata()
            if (STRATA_RANK[bs] or 0) > STRATA_RANK[s] and STRATA_RANK[bs] < STRATA_RANK.FULLSCREEN_DIALOG then s = bs end
            Look.Stack(f, s)
        else
            Look.Stack(f, base)
            if why ~= "free" then
                local done = Look.hooks.undock and Look.hooks.undock(f, shell, why)
                if not done and not Look.StorePlace(f) then      -- wave3-e: the stored place before CENTER
                    f:ClearAllPoints()
                    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                end
            end
        end
        if Look.hooks.docked then Look.hooks.docked(f, docked, why) end
        if wasDocked ~= nil and wasDocked ~= docked then pile.after(pm, pm.seq) end      -- kr-shell (S3): the ones shown after f move
    end
    st.update = update
    pm.refresh = update
    pile.track(pm)
    local function hook()
        local b = rawget(_G, d.frame)
        if b and not hooked[b] then
            hooked[b] = true
            b:HookScript("OnShow", update)
            b:HookScript("OnHide", update)
        end
        return b
    end
    f:HookScript("OnShow", update)
    if not hook() then       -- a Blizzard frame may load later: look again when an addon loads
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("ADDON_LOADED")
        ev:SetScript("OnEvent", function(self)
            if hook() then
                self:UnregisterEvent("ADDON_LOADED")
                update()
            end
        end)
    end
    update()
    return st
end

-- the host calls this when the Blizzard frame may have moved or changed
function Look.DockUpdate(f)
    local st = f._lookDock
    if st then st.update() end
end

function Look.DockFree(f, free)
    local st = f._lookDock
    if not st then return end
    st.free = free and true or false
    st.placed = false
    st.update()
end
-- ==== wave2-a end

-- ==== wave2-b begin: menus, tooltips (gap items 10 11)
-- Look.Menu(f, L, onPick [, entries])   f = the root frame of a menu screen (L.build made it, f._lookD = its D); L = ns.Looks[<menu screen>].
--   Fills f with one row per entry from the item / sep templates of L (a pool: rows are made once and reused), stacks them from the top
--   and grows f down to fit (no scroll bar); f is at least as wide as the HTML and grows wider when an entry text does not fit. Does not anchor or show f.
--   entries default to L.entries: { key, text (a LOC key: Look.L runs on it), tick, off, sep, sub, idx }. Rows of dynamic entries get ids from the pool.
--   fs: optional 5th arg onHover(key, entry, rowFrame): item rows only, after the hover color; on leave onHover(nil, entry, rowFrame). Not for header / sep rows.
--   Click on an item that is not off: onPick(entry.key, entry). A sub item gets onPick(key, entry) too (entry.sub = the sub menu screen id).
--   L.menuLook = { text, off, tick (glyph), tickOn, tickOff } colors read from the HTML states; missing ones fall back to text / dimmed text / hidden.
--   Look.TipLines(tt, lines [, values])   tt = GameTooltip; lines = L.lines of a GameTooltip lines screen: appends AddLine / AddDoubleLine.
--   Label sides (ls / rs) run Look.L; sample sides take values[i] (a string for the right sample side, else the left one, or { l =, r =, lc =, rc = }; lc / rc = palette names for this value).
--   w1rt: when values is a table, a sample side with no value shows "-" (values nil = sample mode: the look.html texts).
local function fsOf(x) return x._lookText or x end

local function setCol(fs, c)
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- wave3-b: the colors, tick, caret and icon of one item row from its entry (also after a hover look is put back)
local function menuPaint(row, look, e)
    local refs = row.refs
    local textCol = look.text
    local tc = textCol or { 1, 1, 1, 1 }
    if e.off then
        tc = look.off or { tc[1], tc[2], tc[3], (tc[4] or 1) * 0.5 }
    end
    setCol(fsOf(refs.text), tc)
    if refs.cols then      -- K3-9: the value columns follow the row text color (an off row dims them too; a |c escape in the text wins)
        for c = 1, #refs.cols do setCol(fsOf(refs.cols[c]), tc) end
    end
    local tk = refs.tick
    if tk and look.tick then
        Look.SetText(tk, look.tick)
        local c
        if e.tick then c = look.tickOn or textCol or { 1, 1, 1, 1 } else c = look.tickOff or { 1, 1, 1, 0 } end
        setCol(fsOf(tk), c)
    end
    local cr = refs.caret
    if cr and look.caret then
        Look.SetText(cr, look.caret)
        local c
        if e.sub then c = look.caretOn or textCol or { 1, 1, 1, 1 } else c = look.caretOff or { 1, 1, 1, 0 } end
        setCol(fsOf(cr), c)
    end
    local ic = refs.icon
    if ic then
        if e.icon then
            ic:SetTexture(e.icon)
            ic:Show()
        else
            ic:Hide()
        end
    end
end

local function menuRow(f, L, pool, kind, e, n)
    local list = pool[kind]
    local row = list[n]
    if row then return row end
    local m = f._look
    pool.made = pool.made + 1
    local refs = L.templates[kind](f, f._lookD, e.idx or (pool.made + 1000))
    local k, ent = m.kids, nil
    for i = #k, 1, -1 do
        if k[i].obj == refs.root then ent = table.remove(k, i); break end
    end
    row = { refs = refs, root = refs.root, ent = ent }
    if kind == "item" then
        row.root:RegisterForClicks("LeftButtonUp", "RightButtonUp")      -- kit-misc (M4): the pager row takes the right click (previous page)
        row.root:SetScript("OnClick", function(_, btn)
            local en = row.e
            if en and en.pager then f._menuTurn(btn == "RightButton" and -1 or 1); return end
            if btn == "RightButton" then return end
            local pick = f._menuPick
            if en and pick and not en.off then pick(en.key, en) end
        end)
        -- wave3-b: the hover look of the state table (a data-row="item" data-state="hover" sample); leaving puts the row colors back
        row.root:SetScript("OnEnter", function()
            if row.root._lookSt and row.e then Look.State(row.root, "hover") end
            local oh = f._menuHover      -- fs: onHover(key, entry, rowFrame) after the hover color
            if oh and row.e and not row.e.pager then oh(row.e.key, row.e, row.root) end
        end)
        row.root:SetScript("OnLeave", function()
            if row.root._lookSt and row.e then
                Look.State(row.root, nil)
                menuPaint(row, f._menuLook or {}, row.e)
            end
            local oh = f._menuHover      -- fs: onHover(nil, entry, rowFrame) on leave
            if oh and row.e and not row.e.pager then oh(nil, row.e, row.root) end
        end)
    end
    list[n] = row
    return row
end

-- kit-misc (M4): Look.Menu(f, L, onPick, entries, onHover, opt)   opt.rows = most rows (items, headers and seps) on one page; default from the screen
--   height (the menu must fit with 0.9 x screen height, row height of the first item row). More entries than that: the rows of page 1 and one
--   pager item row "<1/3>" at the bottom (click = next page, wraps; right click = previous). Header / sep rows count. Not more than one page: as before.
--   A menu opens on page 1 (every Look.Menu call). The pager row is an item row with entry.pager = true: it never reaches onPick / onHover.
local function menuCap(f, L, pool, opt)
    if opt and opt.rows then return math.max(2, math.floor(opt.rows)) end
    local ih
    local first = pool.item[1]
    if first then ih = first.root:GetHeight() end
    if not ih or ih <= 0 then ih = 24 end
    local m = f._look or {}
    local avail = (UIParent:GetHeight() or 768) * 0.9 - (m.t or 0) - (m.b or 0)
    return math.max(2, math.floor(avail / ih))
end

local menuFill

function Look.Menu(f, L, onPick, entries, onHover, opt)      -- fs: onHover
    local m = f._look
    if not (m and m.dyn and f._lookD) then error("Look.Menu: f is not the root of a menu screen built by L.build", 2) end
    Look.ScaleFrame(f, "menu")      -- wave3-e
    entries = entries or L.entries
    local pool = f._menuPool
    f._menuPick = onPick
    f._menuHover = onHover
    f._menuTurn = nil
    if not (opt and opt.rows) and #entries > 12 then
        if not pool or not pool.item[1] then      -- measure one item row first (a pool row is made once and reused)
            menuFill(f, L, { entries[1] }, onPick, onHover)
        end
        pool = f._menuPool
    end
    local cap = (#entries > 12 or (opt and opt.rows)) and menuCap(f, L, pool or { item = {} }, opt) or nil
    if not cap or #entries <= cap then
        menuFill(f, L, entries, onPick, onHover)
        return
    end
    local per = cap - 1
    local pages = math.ceil(#entries / per)
    local page = 1
    local function show()
        local slice = {}
        for i = (page - 1) * per + 1, math.min(#entries, page * per) do slice[#slice + 1] = entries[i] end
        slice[#slice + 1] = { key = "@page", text = "\226\128\185 " .. page .. "/" .. pages .. " \226\128\186", pager = true }      -- UTF-8 single angle quotes
        menuFill(f, L, slice, onPick, onHover)
    end
    f._menuTurn = function(d)
        page = page + d
        if page > pages then page = 1 elseif page < 1 then page = pages end
        show()
    end
    f._menuPages = function() return page, pages end
    show()
end

menuFill = function(f, L, entries, onPick, onHover)
    local m = f._look
    local look = L.menuLook or {}
    local pool = f._menuPool
    if not pool then
        pool = { item = {}, sep = {}, header = {}, made = 0 }
        f._menuPool = pool
    end
    f._menuPick = onPick
    f._menuHover = onHover      -- fs
    if f._menuW0 then f:SetWidth(f._menuW0) else f._menuW0 = f:GetWidth() end   -- the HTML width is the least width
    f._menuLook = look
    for _, kind in ipairs({ "item", "sep", "header" }) do      -- wave3-b: header rows
        for i = 1, #pool[kind] do pool[kind][i].root:Hide() end
    end
    local used = { item = 0, sep = 0, header = 0 }
    local order = {}
    local textCol = look.text
    for i = 1, #entries do
        local e = entries[i]
        local kind = e.sep and "sep" or (e.header and "header" or "item")
        if not L.templates[kind] then error("Look.Menu: this menu screen has no data-row=\"" .. kind .. "\" row look", 2) end
        used[kind] = used[kind] + 1
        local row = menuRow(f, L, pool, kind, e, used[kind])
        row.e = e
        if kind == "item" then
            Look.SetText(row.refs.text, Look.L(e.text))
            local cs = row.refs.cols
            if cs then      -- K3-9: plain strings (not Look.L); a missing col, or a pager row, is blank
                for c = 1, #cs do
                    local v = e.cols and not e.pager and e.cols[c]
                    Look.SetText(cs[c], v ~= nil and v ~= false and tostring(v) or "")
                end
            end
            if row.root._lookSt then Look.State(row.root, nil) end
            menuPaint(row, look, e)
        elseif kind == "header" then      -- wave3-b: a label row, not clickable
            Look.SetText(row.refs.text, Look.L(e.text))
            if look.header then setCol(fsOf(row.refs.text), look.header) end
        end
        row.root:Show()
        order[#order + 1] = row.ent
    end
    m.kids = order
    -- K3-9: column c = the widest text of that column over the shown item rows; every fs of the column gets that width (right justified);
    -- the anchors of the template chain them from the right (left of the caret) with the row gap, and the label ends a gap left of col 1
    local ncol = 0
    for i = 1, used.item do
        local cs = pool.item[i].refs.cols
        if cs and #cs > ncol then ncol = #cs end
    end
    for c = 1, ncol do
        local w = 0
        for i = 1, used.item do
            local cs = pool.item[i].refs.cols
            if cs and cs[c] then w = max(w, fsOf(cs[c]):GetStringWidth()) end
        end
        for i = 1, used.item do
            local cs = pool.item[i].refs.cols
            if cs and cs[c] then
                local fs = fsOf(cs[c])
                fs:SetJustifyH("RIGHT")
                fs:SetWidth(max(w, 0.01))      -- not 0: a zero width means "auto" to the client
            end
        end
    end
    Look.Refit(f)
    -- a text that does not fit makes the menu wider (K3-9: the label is what is left after the columns)
    local need = 0
    for _, kind in ipairs({ "item", "header" }) do
        for i = 1, used[kind] do
            local fs = fsOf(pool[kind][i].refs.text)
            local over = fs:GetStringWidth() - fs:GetWidth()
            if over > need then need = over end
        end
    end
    if need > 0 then
        f:SetWidth(f:GetWidth() + need)
        Look.Refit(f)
    end
end

local K2A = {}      -- k2a: helpers of the k2a section at the end of this file (tip icons)
function Look.TipLines(tt, lines, values)
    for i = 1, #lines do
        local ln = lines[i]
        local l, r = ln.l, ln.r
        local lsamp = not ln.ls                       -- left / right side is a sample text (not a label)
        local rsamp = r ~= nil and not ln.rs
        if ln.ls then l = Look.L(l) end
        if r ~= nil and ln.rs then r = Look.L(r) end
        local lcn, rcn = ln.lc, ln.rc
        if values then
            -- w1rt: values given = value mode. A sample side with no value shows "-" (never the made-up look.html text).
            local v = values[i]
            local gotL, gotR = false, false
            if type(v) == "table" then
                if v.l ~= nil then l = v.l; gotL = true end
                if v.r ~= nil then r = v.r; gotR = true end
                if v.lc ~= nil then lcn = v.lc end      -- w1rt: per-value palette names
                if v.rc ~= nil then rcn = v.rc end
            elseif v ~= nil then
                if rsamp then r = v; gotR = true
                elseif lsamp then l = v; gotL = true end
            end
            if lsamp and not gotL then l = "-" end
            if rsamp and not gotR then r = "-" end
        end
        l = K2A.tipIcon(ln, values and values[i], l)      -- k2a (K2-3): an icon on the line = a texture escape before the left text
        local lc = lcn and Look.C(lcn) or { 1, 1, 1 }
        if r ~= nil then
            local rc = rcn and Look.C(rcn) or { 1, 1, 1 }
            tt:AddDoubleLine(l, r, lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
        else
            tt:AddLine(l, lc[1], lc[2], lc[3])
        end
    end
end
-- w1rt: Look.TipShow(owner, L, values [, tt]) -> tt. L = ns.Looks[<tip screen>] of a GameTooltip lines screen.
--   tt = GameTooltip by default. SetOwner(owner, "ANCHOR_NONE"), ClearAllPoints, SetPoint(L.anchor[1], owner, L.anchor[2], L.anchor[3], L.anchor[4])
--   (L.anchor = data-anchor of the screen); no L.anchor = SetOwner(owner, "ANCHOR_RIGHT") and no SetPoint. Then Look.TipLines(tt, L.lines, values), tt:Show().
--   An own tip box screen (no L.lines) is an error here: the glue anchors and fills its own frame (L.anchor is there too).
function Look.TipShow(owner, L, values, tt, opt)      -- kit-misc (M6): opt.cursor = true: ANCHOR_CURSOR_RIGHT, L.anchor is not used
    if not (L and L.lines) then error("Look.TipShow: L is not a GameTooltip lines screen (an own tip box has no L.lines)", 2) end
    tt = tt or GameTooltip
    local a = L.anchor
    if opt and opt.cursor then
        tt:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")
    elseif a then
        tt:SetOwner(owner, "ANCHOR_NONE")
        tt:ClearAllPoints()
        tt:SetPoint(a[1], owner, a[2], a[3], a[4])
    else
        tt:SetOwner(owner, "ANCHOR_RIGHT")
    end
    Look.TipLines(tt, L.lines, values)
    tt:Show()
    return tt
end
-- w1rt: Look.TipBoxShow(owner, L, refs) -> refs.root. An own tip box screen (screen.json tip mode "box", no L.lines): refs = L.build(parent, D) (once).
--   ClearAllPoints, SetPoint(L.anchor[1], owner, L.anchor[2], L.anchor[3], L.anchor[4]), strata TOOLTIP, Show. The glue fills the texts (L.sample is the HTML text) and hides it again.
function Look.TipBoxShow(owner, L, refs, opt)      -- kit-misc (M6): opt.cursor = true: the box sits at the cursor at show time (below right of it; flips left / up at a screen edge)
    local f = refs and refs.root
    if not (f and L and (L.anchor or (opt and opt.cursor))) then error("Look.TipBoxShow: needs refs.root (from L.build) and L.anchor", 2) end
    local a = L.anchor
    f:ClearAllPoints()
    if opt and opt.cursor then
        local cx, cy = GetCursorPosition()
        local s = f:GetEffectiveScale()
        if not (s and s > 0) then s = 1 end
        local x, y = cx / s, cy / s
        local sw, sh = UIParent:GetWidth() * UIParent:GetEffectiveScale() / s, UIParent:GetHeight() * UIParent:GetEffectiveScale() / s
        local w, h = f:GetWidth() or 0, f:GetHeight() or 0
        local px, py = "TOPLEFT", "BOTTOMLEFT"
        local ox, oy = x + 16, y - 8
        if ox + w > sw then px = "TOPRIGHT"; ox = x - 8 end
        if oy - h < 0 then py = "BOTTOMLEFT"; px = px:gsub("TOP", "BOTTOM"); oy = y + 8 end
        f:SetPoint(px, UIParent, "BOTTOMLEFT", ox, oy)
    else
        f:SetPoint(a[1], owner, a[2], a[3], a[4])
        -- kit-misc (M7): the box would go past a screen edge at its anchor: the other side of the owner (right <-> left, below <-> above, offsets negated).
        --   No flip when it fits (same calls as before). Only boxes: GameTooltip lines tips are clamped by the game.
        local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
        local ps = UIParent:GetEffectiveScale()
        local fs = f:GetEffectiveScale()
        if l and r and t and b and ps and fs and fs > 0 then
            local sw, sh = UIParent:GetWidth() * ps / fs, UIParent:GetHeight() * ps / fs
            local function mir(p, axis)
                if axis == "x" then return (p:gsub("LEFT", "@"):gsub("RIGHT", "LEFT"):gsub("@", "RIGHT")) end
                return (p:gsub("TOP", "@"):gsub("BOTTOM", "TOP"):gsub("@", "BOTTOM"))
            end
            local p, rp, x, y = a[1], a[2], a[3], a[4]
            local flipped = false
            if r > sw + 0.01 or l < -0.01 then p, rp, x = mir(p, "x"), mir(rp, "x"), -x; flipped = true end
            if t > sh + 0.01 or b < -0.01 then p, rp, y = mir(p, "y"), mir(rp, "y"), -y; flipped = true end
            if flipped then
                f:ClearAllPoints()
                f:SetPoint(p, owner, rp, x, y)
            end
        end
    end
    if (opt and opt.icons) or f._lookTipIcons then K2A.boxIcons(f, refs, opt and opt.icons) end      -- k2a (K2-3)
    f:SetFrameStrata("TOOLTIP")
    f:Show()
    return f
end

-- w1rt: Look.MenuPlace(host, owner, L) -> flipped (true when the menu opens on the other side). Call after Look.Menu (the menu height is final).
--   Point = L.anchor ({ point, ownerPoint, x, y } of the menu screen), default { "TOPLEFT", "BOTTOMLEFT", 0, -2 }. When the menu bottom would be below the screen
--   bottom (or its top above the screen top) the mirrored anchor is used when that overflows less (TOP <-> BOTTOM, y negated: above the owner). A right edge off the
--   screen shifts the menu left (a left edge off the screen shifts it right). Sets the points, does not show host.
local MP_FX = { LEFT = 0, CENTER = .5, RIGHT = 1, TOPLEFT = 0, TOP = .5, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOM = .5, BOTTOMRIGHT = 1 }
local MP_FY = { BOTTOM = 0, CENTER = .5, TOP = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 0, LEFT = .5, RIGHT = .5, TOPLEFT = 1, TOPRIGHT = 1 }
local function mpFlip(p)
    return (p:gsub("TOP", "@"):gsub("BOTTOM", "TOP"):gsub("@", "BOTTOM"))
end
function Look.MenuPlace(host, owner, L)
    local a = L and L.anchor or { "TOPLEFT", "BOTTOMLEFT", 0, -2 }
    local function set(p, rp, x, y)
        host:ClearAllPoints()
        host:SetPoint(p, owner, rp, x, y)
    end
    local ol, orr, ot, ob = owner:GetLeft(), owner:GetRight(), owner:GetTop(), owner:GetBottom()
    local hs, os, ps = host:GetEffectiveScale(), owner:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (ol and orr and ot and ob and hs and os and ps and hs > 0) then
        set(a[1], a[2], a[3], a[4])
        return false
    end
    local k = os / hs                                  -- owner units -> host units
    local sw, sh = UIParent:GetWidth() * ps / hs, UIParent:GetHeight() * ps / hs
    local w, h = host:GetWidth(), host:GetHeight()
    local function rect(p, rp, x, y)                   -- left, bottom of the host in host units
        local px = ol * k + MP_FX[rp] * (orr - ol) * k + x
        local py = ob * k + MP_FY[rp] * (ot - ob) * k + y
        return px - MP_FX[p] * w, py - MP_FY[p] * h
    end
    local function over(l, b)
        return math.max(0, -b) + math.max(0, b + h - sh)
    end
    local l1, b1 = rect(a[1], a[2], a[3], a[4])
    local use, flipped, l, b = { a[1], a[2], a[3], a[4] }, false, l1, b1
    if over(l1, b1) > 0 then
        local f = { mpFlip(a[1]), mpFlip(a[2]), a[3], -a[4] }
        local l2, b2 = rect(f[1], f[2], f[3], f[4])
        if over(l2, b2) < over(l1, b1) then use, flipped, l, b = f, true, l2, b2 end
    end
    local dx = 0
    if l + w > sw then dx = sw - (l + w) end
    if l + dx < 0 then dx = -l end
    set(use[1], use[2], use[3] + dx, use[4])
    return flipped
end
-- ==== wave2-b end

-- ==== wave2-c begin: tabs, shared parts (gap items 12 13)
-- Look.Tabs(refs, L, bodies [, opt]) -> tabs. refs = the built window (L.build), L = its look table with the tab map
-- L.tabs = { slot = "<refs name>", w, h, list = { { button = "<refs name>", body = "<screen id>", sel = true }, ... } }.
-- Every body look (ns.Looks[id].build) is built into the slot frame at its TOPLEFT (opt.D(id, bodyLook) gives its D, default
-- Look.D(bodyLook.tokens); opt.sample = true also runs the body's L.sample), then one body shows (the entry with sel, else the first)
-- and the others hide. A click on a tab button (HookScript OnClick) selects its body. bodies = a table id -> refs that the host already
-- built (it is used as is and filled with the new ones); pass {} or nil. opt.onSelect(id, bodyRefs) runs after every Select.
-- tabs.Select(id) -> bodyRefs, tabs.Selected() -> id, tabs.bodies[id] -> refs of a body (refs.root is its frame).
-- Shared parts: ns.LookParts.<name>(parent, D, id) -> { root, _o }, made by the converter (out/parts.lua), called by the screen looks.
function Look.Tabs(refs, L, bodies, opt)
    local map = L and L.tabs
    if not map then error("Look.Tabs: this look has no tab map", 2) end
    opt = opt or {}
    bodies = bodies or {}
    local slot = refs[map.slot]
    if not slot then error("Look.Tabs: no slot " .. tostring(map.slot) .. " in refs", 2) end
    local T = { slot = slot, map = map, bodies = bodies, hidden = {}, built = {} }      -- kr-shell: hidden (tab ids), built (ids this call built)
    refs._lookTabs = T
    local cur
    local function entry(id)      -- kr-shell
        for i = 1, #map.list do
            if map.list[i].body == id then return map.list[i], i end
        end
    end
    local function build(e, line)      -- one body: build into the slot (eager: at once, opt.lazy: on its first Select)
        local BL = ns.Looks and ns.Looks[e.body]
        if not BL then error("Look.Tabs: no look for the tab body " .. tostring(e.body), line or 2) end
        local BD = opt.D and opt.D(e.body, BL) or Look.D(BL.tokens)
        local b = BL.build(slot, BD)
        b.root:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
        if opt.sample and BL.sample then BL.sample(b) end
        bodies[e.body] = b
        T.built[#T.built + 1] = e.body
        if opt.onBuild then opt.onBuild(e.body, b) end
        return b
    end
    local function firstShown()      -- kr-shell
        for i = 1, #map.list do
            if not T.hidden[map.list[i].body] then return map.list[i].body end
        end
    end
    function T.Selected() return cur end
    function T.IsBuilt(id) return bodies[id] ~= nil end
    -- Select(id) -> bodyRefs, builtNow. A hidden tab selects the first shown one instead (nothing shown: returns nil). A lazy body is built here.
    function T.Select(id)
        local e = entry(id)
        if not (bodies[id] or e) then error("Look.Tabs: no tab body " .. tostring(id), 2) end
        if T.hidden[id] then
            id = firstShown()
            if not id then return nil, false end
            e = entry(id)
        end
        local now = false
        if not bodies[id] then
            local b = build(e, 3)
            b.root:Hide()
            now = true
        end
        cur = id
        for bid, b in pairs(bodies) do
            if bid == id then b.root:Show() else b.root:Hide() end
        end
        for i = 1, #map.list do          -- wave3-b: the sel look of the state table (selected button = "sel", the others = the base look)
            local b = refs[map.list[i].button]
            if b and b._lookSt then Look.State(b, map.list[i].body == id and "sel" or nil) end
        end
        if opt.onSelect then opt.onSelect(id, bodies[id]) end
        return bodies[id], now
    end
    -- kr-shell: hide / show one tab button; the later buttons close the gap. See Look.TabShow.
    -- Two row models (what the converter writes): chain = every button after the first is anchored to the button before it (the usual flex row);
    -- offset = all buttons share one anchor frame with their own x (or y). Anything else: the buttons are hidden but the gap stays.
    local anchors, model, axis, captured
    local function capture()
        anchors = {}
        for i = 1, #map.list do
            local b = refs[map.list[i].button]
            if not (b and b.GetPoint and b.GetNumPoints and b:GetNumPoints() == 1) then anchors = nil return end
            local pt, rel, rp, x, y = b:GetPoint(1)
            if not pt then anchors = nil return end
            anchors[i] = { pt, rel, rp, x or 0, y or 0 }
        end
        local chain, offset = true, true
        for i = 2, #anchors do
            if anchors[i][2] ~= refs[map.list[i - 1].button] then chain = false end
            if anchors[i][1] ~= anchors[1][1] or anchors[i][2] ~= anchors[1][2] or anchors[i][3] ~= anchors[1][3] then offset = false end
        end
        if chain then model = "chain" elseif offset then
            model = "offset"
            axis = 4
            for i = 2, #anchors do if anchors[i][4] ~= anchors[1][4] then axis = nil end end
            axis = axis or 5
        else anchors = nil end
    end
    local function reflow()
        if not captured then captured = true; capture() end
        if not anchors then return end
        local prev, shift = nil, 0
        for i = 1, #map.list do
            local a = anchors[i]
            local b = refs[map.list[i].button]
            if T.hidden[map.list[i].body] then
                if model == "offset" and anchors[i + 1] then shift = shift + (anchors[i + 1][axis] - a[axis]) end
            else
                b:ClearAllPoints()
                if model == "chain" then
                    if prev then b:SetPoint(a[1], prev, a[3], a[4], a[5]) else b:SetPoint(anchors[1][1], anchors[1][2], anchors[1][3], anchors[1][4], anchors[1][5]) end
                    prev = b
                else
                    b:SetPoint(a[1], a[2], a[3], axis == 4 and a[4] - shift or a[4], axis == 5 and a[5] - shift or a[5])
                end
            end
        end
    end
    function T.Show(id, shown)
        local e = entry(id)
        if not e then
            for i = 1, #map.list do
                if map.list[i].button == id then e = map.list[i] end
            end
        end
        if not e then error("Look.TabShow: no tab " .. tostring(id), 2) end
        local btn = refs[e.button]
        T.hidden[e.body] = (not shown) and true or nil
        if btn then if shown then btn:Show() else btn:Hide() end end
        reflow()
        if cur and T.hidden[cur] then T.Select(cur)
        elseif not cur and shown then T.Select(e.body) end
        return cur
    end
    for i = 1, #map.list do
        local e = map.list[i]
        if not bodies[e.body] then
            if opt.lazy then
                if not (ns.Looks and ns.Looks[e.body]) then error("Look.Tabs: no look for the tab body " .. tostring(e.body), 2) end
            else
                build(e)
            end
        end
        if bodies[e.body] then bodies[e.body].root:Hide() end
        local btn = refs[e.button]
        if not btn then error("Look.Tabs: no tab button " .. tostring(e.button) .. " in refs", 2) end
        local id = e.body
        btn:HookScript("OnClick", function() T.Select(id) end)
    end
    local first, pick
    for i = 1, #map.list do
        local e = map.list[i]
        first = first or e.body
        if e.sel then pick = e.body end
    end
    if opt.hidden then      -- kr-shell: tabs hidden from the start (their body is never built in lazy mode)
        for _, id in ipairs(opt.hidden) do
            local e = entry(id)
            if not e then error("Look.Tabs: opt.hidden has no tab " .. tostring(id), 2) end
            T.hidden[id] = true
            local btn = refs[e.button]
            if btn then btn:Hide() end
        end
        reflow()
    end
    if first then T.Select(pick or first) end
    return T
end
-- kr-shell: Look.TabShow(refs, id, shown) -> the selected tab id. id = the tab body id or its button name; refs = the window refs of Look.Tabs.
function Look.TabShow(refs, id, shown)
    local T = refs and refs._lookTabs
    if not T then error("Look.TabShow: Look.Tabs has not run on these refs", 2) end
    return T.Show(id, shown)
end
-- ==== wave2-c end

-- ================================================================ Wave 3 sections: each helper writes only inside its own pair
-- ==== kr-lists begin: rows of a list: clickable rows, input boxes in rows, entries with a kind (Look.GrowList / Look.Pages call these). Docs: docs\rollout\kit-kr-lists.md
-- Look.SetInput(box, text)   sets the text of an edit box in a list row, unless the box has focus (typing wins: a refresh of the SAME row never eats what is typed). -> true when set
-- Look.RowItem(f)            f = a row frame, or any frame / region inside a row of a list -> item number, entry, ls (nil when f is not in a list row)
-- opt.onRow(ls, i, entry, row, button)           a row whose data-row root is data-kind="button" was clicked (also Look.hooks.row)
-- opt.onInput(ls, i, entry, name, text, why)     an input box (data-kind="input", data-wow = name) in a row: why = "enter" | "lost" (also Look.hooks.input)
-- entry = the element of n for item i when n is a table (a row name, or { kind = "row name", ... }), else nil.
function Look.SetInput(box, s)
    if box.HasFocus and box:HasFocus() then return false end
    box._krEnter = nil
    box:SetText(s == nil and "" or tostring(s))
    if box.SetCursorPosition then pcall(box.SetCursorPosition, box, 0) end      -- w3diag: a text wider than the box shows its START, not its tail (Budget "1g 00s 00c" read "s 00c")
    return true
end

function Look.RowItem(f)
    while f do
        if f._krRow then return f._krRow.i, f._krRow.entry, f._krRow.st.ls end
        f = f.GetParent and f:GetParent() or nil
    end
    return nil
end

-- the input boxes of a row (named by data-wow, registered by Look.Kind in refs._kinds): { { name, box }, ... }
local function krInputs(row)
    local l = row.inputs
    if l then return l end
    l = {}
    local ks = row.refs._kinds
    if ks then
        for name, k in pairs(ks) do
            if k == "input" and row.refs[name] then l[#l + 1] = { name, row.refs[name] } end
        end
        table.sort(l, function(a, b) return a[1] < b[1] end)
    end
    row.inputs = l
    return l
end

-- the row stops showing this item (hidden, or another item takes the row): a focused edit box loses focus now (its "lost" event still sees the old item)
local function krDropFocus(row)
    local l = krInputs(row)
    for i = 1, #l do
        local b = l[i][2]
        if b.HasFocus and b:HasFocus() then b:ClearFocus() end
    end
end

local function krInput(row, name, box, why)
    local st = row.st
    local l = st.ls
    local f = (l and l.opt.onInput) or Look.hooks.input
    if not f or row.i == nil then return end
    local text = box:GetText()
    if why == "lost" and box._krEnter == text then box._krEnter = nil return end      -- Enter already reported this text
    if why == "enter" then box._krEnter = text end
    f(l, row.i, row.entry, name, text, why)
end

-- once per pooled row: the click of a button row root, the Enter / focus lost of its input boxes
local function krWire(row, st)
    if row.krWired then return end
    row.krWired = true
    row.st = st
    row.root._krRow = row
    local f = row.root
    if f.GetObjectType and f:GetObjectType() == "Button" then
        f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        f:HookScript("OnClick", function(_, btn)
            local l = st.ls
            local fn = (l and l.opt.onRow) or Look.hooks.row
            if fn and row.i ~= nil then fn(l, row.i, row.entry, row, btn) end
        end)
    end
    local ins = krInputs(row)
    for i = 1, #ins do
        local name, box = ins[i][1], ins[i][2]
        box:HookScript("OnEnterPressed", function(self) krInput(row, name, self, "enter") end)
        box:HookScript("OnEditFocusLost", function(self) krInput(row, name, self, "lost") end)
    end
end

-- kr-lists L5: a grow list in a tab body (info.bound, data-fold="edge"): the tab body keeps its fixed height, so the room for the list =
-- body height - what sits above the list - what sits below it (the stack of the later kids of every ancestor up to the body, as Look.Reflow stacks them).
-- nil = unknown (not laid out yet): no fold.
local function krBoundFree(c, root)
    local fv, fhit = Look.K2eBound(c, root)      -- k2e K2-19: a column with a fill pages list: it counts at its floor
    if fhit then return fv end
    local top, rt = c:GetTop(), root:GetTop()
    if type(top) ~= "number" or type(rt) ~= "number" then return nil end
    local below = 0
    local child = c
    while child and child ~= root do
        local p = child._lookParent
        local m = p and p._look
        if not m or not m.kids then return nil end
        local gap = m.gap or 0
        local found = false
        for i = 1, #m.kids do
            local e = m.kids[i]
            if found then
                if e.obj and e.obj:IsShown() then below = below + gap + (e.m.mt or 0) + e.obj:GetHeight() + (e.m.mb or 0) end
            elseif e.obj == child then
                found = true
                below = below + (e.m.mb or 0)
            end
        end
        if not found then return nil end
        below = below + (m.b or 0)
        child = p
    end
    return root:GetHeight() - (rt - top) - below
end
-- ==== kr-lists end

-- ==== wave3-a begin: grow lists + edge fold, pages + pager (gap items 16 17). Docs: docs\wave3-a.md
-- Lists are made by the converter (screen_lists.py): L.lists = { { wow, kind = "grow" | "pages", row, fold, empty, edge, more, clear, pager, rowH, gap, h, L } }.
-- The host calls ONE function per list with the item count n and a fill callback fill(rowRefs, i, ls) (rowRefs = the refs of one row from its
-- template, i = the 1-based item number). refs = the screen refs (L.build), info = one entry of L.lists. Rows are a pool: made once, hidden and reused.
--   ls = Look.GrowList(refs, info, n, fill [, opt])   rows stack down from the top of the list box (gap from the CSS), the box and the window grow down.
--        info.edge (data-fold="edge"): the list stops at the screen bottom; the last row is the fold row "+N" (a button).
--        n = 0 shows the empty row (info.empty) when there is one. opt.margin = UI units kept free above the screen bottom (default 0).
--        Click on the fold row: opt.onFold(ls, first, hidden) or Look.hooks.fold(ls, first, hidden); the host decides (open the rest, next page).
--   ls = Look.Pages(refs, info, n, fill [, opt])      the list box keeps its size; rows per page = floor((height + gap) / (rowH + gap)).
--        The pager (refs.prev, refs.page, refs.next of the pager part) shows the left angle quote, "<page>/<pages>", the right angle quote; at the first /
--        last page the button is dimmed (alpha 0.4) and a click does nothing. n = 0: the empty row and "1/1". opt.page = start page, opt.reset = page 1,
--        opt.onPage(ls) after a page turn. NO scroll bar and NO mouse wheel (the wheel is the buy input): nothing here enables or reads it.
-- wave3-d: a list with SEVERAL row groups (info.rows = { "cur", "mat", ... }): n is a TABLE of row names, one per item: Look.GrowList(refs, info, { "cur", "mat", "mat" }, fill).
--   fill(rowRefs, i, ls, kind) gets the row name as 4th arg. A number is for one-group lists only (a multi-group list called with a number raises). Rows keep their own height.
--   ls.Refresh() lays out again (same items / fill / page; the height is measured again); container._lookRefresh = ls.Refresh and refs._lists lists the container (Look.Relayout).
--   ls fields: n, shown (data rows shown), first / last (item numbers shown), hidden (grow: rows behind the fold), firstHidden, page, pages, perPage (pages),
--        container, info, refs, rows (pool), fold / empty (refs of those rows), Page(p) / Next() / Prev() (pages).
local LA_LQ, LA_RQ = "\226\128\185", "\226\128\186"      -- the pager glyphs: left / right single angle quote (U+2039, U+203A)
local LA_OFF = 0.4                                        -- the dimmed look of a pager button at the first / last page

local function laTop(f)
    local t = f
    while t._lookParent and t._lookParent._look do t = t._lookParent end
    return t
end

local function laList(refs, info, fnName)
    local c = refs and info and refs[info.wow]
    if not c then error("Look." .. fnName .. ": no list " .. tostring(info and info.wow) .. " in refs", 3) end
    if not (c._look and c._look.dyn and c._lookD) then error("Look." .. fnName .. ": " .. tostring(info.wow) .. " is not a list box built by L.build", 3) end
    local want = (fnName == "GrowList" or fnName == "GrowGroup") and "grow" or "pages"      -- k2b K2-10: GrowGroup is a grow call too
    if info.kind ~= want then error("Look." .. fnName .. ": the list " .. tostring(info.wow) .. " is a " .. tostring(info.kind) .. " list", 3) end
    return c
end

-- wave3-d: the row groups of a list (info.rows when a list has 2 or more, else just info.row)
local function laGroups(info)
    return info.rows or { info.row }
end

-- wave3-d: n is a number (one group) or a table of row names, one per item. -> kinds (nil = every item is info.row), item count
local function laKinds(info, n, fnName)
    local groups = laGroups(info)
    if type(n) == "number" then
        if #groups > 1 then
            error("Look." .. fnName .. ": the list " .. tostring(info.wow) .. " has " .. #groups .. " row groups (" .. table.concat(groups, ", ") ..
                "); pass a table of row names, one per item, not a number", 3)
        end
        return nil, n
    end
    if type(n) ~= "table" then error("Look." .. fnName .. ": n is a number or a table of row names, got " .. type(n), 3) end
    local ok = {}
    for _, g in ipairs(groups) do ok[g] = true end
    local names = n
    for i = 1, #n do
        local e = n[i]
        local nm = e
        if type(e) == "table" then          -- kr-lists L3: an entry is a row name, or a table with a kind field (the row name; one-group lists may leave it out)
            nm = e.kind
            if nm == nil and #groups == 1 then nm = groups[1] end
            if names == n then
                names = {}
                for j = 1, i - 1 do names[j] = n[j] end
            end
        end
        if names ~= n then names[i] = nm end
        if not ok[nm] then
            error("Look." .. fnName .. ": item " .. i .. " names the row " .. tostring(nm) .. ", which is not a row group of the list " ..
                tostring(info.wow) .. " (" .. table.concat(groups, ", ") .. "); every kind needs a sample row with that data-row in the list", 3)
        end
    end
    return names, #n
end

-- the pool of one list box: st.pool[template name] = { row, row, ... } (wave3-d: one pool per template). The sample rows that L.sample made are hidden and forgotten.
local function laPool(c, info)
    local st = c._laPool
    if st then return st end
    -- wave3-j (J6): baseH = the list box height the converter made (open lists)
    -- ==== w3diag begin (K3-5): the declared base height (info.baseH, written by the converter for an open list) wins over c:GetHeight(): the box is 0 high in the game when no L.sample ran
    -- (the sandbox got it from the sample rows), so no row fitted and the label said 0. Never 0: the row height is the last fallback.
    local bh = (type(info.baseH) == "number" and info.baseH > 0) and info.baseH or c:GetHeight()
    if type(bh) ~= "number" or bh < 1 then bh = info.rowH or 28 end
    st = { pool = {}, made = 0, baseH = bh }
    -- ==== w3diag end
    c._laPool = st
    local kids = c._look.kids
    for i = 1, #kids do
        local o = kids[i].obj
        if o then o:Hide() end
    end
    c._look.kids = {}
    return st
end

local function laRow(c, st, info, name, k)
    local list = st.pool[name]
    if not list then list = {}; st.pool[name] = list end
    local row = list[k]
    if row then return row end
    local tpl = info.L.templates[name]
    if not tpl then error("Look: no row template " .. tostring(name), 3) end
    st.made = st.made + 1
    local refs = tpl(c, c._lookD, 1000 + st.made)
    refs.root:Hide()                    -- kr-lists: a new row starts hidden (laRowH no longer hides row 1 to measure it)
    local kids, ent = c._look.kids, nil
    for i = #kids, 1, -1 do
        if kids[i].obj == refs.root then ent = table.remove(kids, i); break end
    end
    row = { refs = refs, root = refs.root, ent = ent, kind = name }
    list[k] = row
    return row
end

-- kr-lists: marks every pooled row unused; laSweep hides the rows that stay unused. A row that is used again is never hidden in between (an edit box in it keeps its focus).
local function laHideAll(st)
    for _, list in pairs(st.pool) do
        for i = 1, #list do list[i].used = false end
    end
end

local function laSweep(st)
    for _, list in pairs(st.pool) do
        for i = 1, #list do
            local row = list[i]
            if not row.used then
                if row.root:IsShown() then
                    krDropFocus(row)
                    row.root:Hide()
                end
                row.i, row.entry = nil, nil
            end
        end
    end
end

-- wave3-d: the real height of one row template (measured once per call; the frame stays hidden until a row is used)
local function laRowH(c, st, info, name, hc)
    local h = hc[name]
    if h then return h end
    local row = laRow(c, st, info, name, 1)
    h = row.root:GetHeight()
    hc[name] = h
    return h
end

-- ==== w3diag begin (K3-6): rs.h0 = the window height with every shown open list at its base height. Measured AFTER a refit (the window height is true then), never in the middle of a fill.
local function laSettle(root)
    local rs = root._lookRs
    local all = root._lookOpenAll
    if not rs or not all or root._lookSizing then return end
    local extra = 0
    for c2 in pairs(all) do
        local st2 = c2._laPool
        if st2 and c2:IsShown() then extra = extra + (c2:GetHeight() - st2.baseH - (st2.foldH or 0)) end
    end
    rs.h0 = root:GetHeight() - extra
    rs.h0Ok = true
end
-- ==== w3diag end

-- stack the rows in order: the list box (Reflow) sets the place of every row, the parents follow (Refit)
local function laStack(c, order, noRefit)
    c._look.kids = order
    if Look.ColsFit then Look.ColsFit(c) end      -- w3cols: flex table columns follow the list width and the shown texts
    if noRefit then return end      -- kr-shell (S4): opt.noRefit: the glue calls Look.Flush(refs) once after all its lists
    local top = laTop(c)
    Look.Refit(top)
    laSettle(top)      -- w3diag (K3-6)
    if top._lookRs and Look.Bounds then Look.Bounds(top) end      -- k2b K2-6: the grip minimum follows the new natural height after every refill
end

local function laNew(c, st, info, refs, n, cnt, fill, opt)
    local ls = st.ls
    if not ls then
        ls = { container = c, info = info }
        st.ls = ls
    end
    ls.rows = st.pool[info.row]
    if not ls.rows then ls.rows = {}; st.pool[info.row] = ls.rows end
    ls.refs, ls.n, ls.nArg, ls.fill, ls.opt = refs, cnt, n, fill, opt or {}
    ls.entries = type(n) == "table" and n or nil          -- kr-lists L3: the entries (row names or { kind = ... } tables) of the call
    ls.shown, ls.first, ls.last, ls.hidden, ls.fold, ls.empty, ls.firstHidden = 0, 0, 0, 0, nil, nil, nil
    ls.capFold = nil
    ls.items = {}
    return ls
end

-- wave3-d: the resize contract. container._lookRefresh = ls.Refresh and the container is listed once in refs._lists (Look.Relayout calls them).
local function laRegister(refs, c, ls)
    c._lookRefresh = ls.Refresh
    local l = refs._lists
    if not l then l = {}; refs._lists = l end
    for i = 1, #l do if l[i] == c then return end end
    l[#l + 1] = c
end

local function laFill(st, info, ls, kinds, from, to)
    local order, used = {}, {}
    for i = from, to do
        local name = kinds and kinds[i] or info.row
        used[name] = (used[name] or 0) + 1
        local row = laRow(ls.container, st, info, name, used[name])
        row.used = true
        if row.i ~= nil and row.i ~= i then krDropFocus(row) end      -- kr-lists L2: another item takes this row: focus leaves its edit boxes first
        row.i, row.entry = i, ls.entries and ls.entries[i] or nil
        krWire(row, st)
        row.root:Show()
        if ls.fill then ls.fill(row.refs, i, ls, name) end         -- wave3-d: the kind (row name) is the 4th argument
        order[#order + 1] = row.ent
        ls.items[#ls.items + 1] = row
    end
    ls.shown = to - from + 1
    if ls.shown > 0 then ls.first, ls.last = from, to end
    return order
end

local function laEmpty(c, st, info, ls, order)
    if not info.empty then return end
    local row = laRow(c, st, info, info.empty, 1)
    row.used = true
    row.root:Show()
    ls.empty = row.refs
    order[#order + 1] = row.ent
end

-- free height for the list box so that the window bottom stays on the screen: (list top above the screen bottom) - (what sits below the list in its window)
local function laEdgeFree(c, margin)
    local top = c:GetTop()
    if type(top) ~= "number" then return nil end
    local lb, rb = c:GetBottom(), laTop(c):GetBottom()
    if type(lb) ~= "number" or type(rb) ~= "number" then return nil end
    local k = UIParent:GetEffectiveScale() / c:GetEffectiveScale()
    return top - (lb - rb) - (margin or 0) * k
end

-- wave3-j (J6): an OPEN grow list (info.label = the count label "Top 3"): its box is baseH + the window's extra height (rs.dH, from the grip), up to the
-- screen edge. Rows shown = every row that fits; the "+N" fold row only when the box is stopped by the screen edge and rows are left over.
local function laOpenBox(c, st, opt, info)
    local root = laTop(c)
    local rs = root._lookRs
    -- ==== w3diag begin (K3-6): ONE extra-height budget per window, split over its SHOWN open lists (before: each list added the grip extra to its own box, so a window with 3 open lists
    -- (pm-home) came out 3 x taller than dragged). n = the shown open lists (this one included); h0 = the window height with every one of them at its base height.
    local all = root._lookOpenAll
    if not all then all = {}; root._lookOpenAll = all end
    all[c] = true
    local n, extra, me = 0, 0, false
    for c2 in pairs(all) do
        local st2 = c2._laPool
        if st2 and (c2 == c or c2:IsShown()) then
            n = n + 1
            extra = extra + (c2:GetHeight() - st2.baseH - (st2.foldH or 0))
            if c2 == c then me = true end
        end
    end
    if not me then n = n + 1; extra = extra + (c:GetHeight() - st.baseH - (st.foldH or 0)) end
    if n < 1 then n = 1 end
    root._lookOpenUsed = n
    local total = 0
    for _, x in ipairs(info and info.L and info.L.lists or {}) do if x.label then total = total + 1 end end
    if rs and not rs.h0 then rs.h0 = root:GetHeight() - extra end      -- the first fill; every refit measures it again (laSettle), the grip freezes it while dragging
    -- ==== w3diag end
    if rs then
        -- the stored size is applied once; with several open lists only after a refit measured h0 (laSettle), else the first list alone would take all of it
        if rs.wantH and (rs.h0Ok or total <= 1) then rs.dH = max(0, rs.wantH - rs.h0); rs.wantH = nil end
    end
    if st.fitBase then      -- k3fit (K3-8): the base height of this call's rows
        if rs and rs.h0 then rs.h0 = rs.h0 + (st.fitBase - st.baseH) end
        st.baseH, st.fitBase = st.fitBase, nil
    end
    root._lookOpen = c
    local H = st.baseH + ((rs and rs.dH) or 0) / n      -- w3diag (K3-6): this list's share of the dragged extra
    local atEdge = false
    local free = laEdgeFree(c, opt.margin)
    if free and H >= free - 0.5 then H, atEdge = max(free, 0), true end
    c._look.autoH = false
    return H, atEdge
end

local function laFit(c, st, info, kinds, cnt, H, gap, hc)
    local used, k = 0, 0
    for i = 1, cnt do
        local need = laRowH(c, st, info, kinds and kinds[i] or info.row, hc) + (i > 1 and gap or 0)
        if used + need <= H + 0.001 * need then used = used + need; k = k + 1 else break end
    end
    return k
end

local function laLabel(refs, info, shown)
    local node = refs._o and refs._o[info.label]
    if not node then return end
    local fs = node._lookText or node
    local t = fs.GetText and fs:GetText() or ""
    -- w3diag (K3-7): only a TRAILING number is the count ("Top 3" -> "Top 2"). A digit inside a name ("Steps Silk 7 Cloth") stays. Limit: a name that ENDS in a digit is read as the count.
    local nt = t
    if tostring(t):match("%d+$") then nt = tostring(t):gsub("(%d+)$", tostring(shown), 1) end
    if nt ~= t then Look.SetText(node, nt) end
end

function Look.GrowList(refs, info, n, fill, opt)
    local c = laList(refs, info, "GrowList")
    local grp = c._laGroup      -- k2b K2-10: a list of an edge group is filled together with the others (the call updates this member and runs the group)
    if grp and not grp.running then return grp.call(c, n, fill, opt) end
    local kinds, cnt = laKinds(info, n, "GrowList")                 -- wave3-d: n = a number or a table of row names
    opt = opt or {}
    local st = laPool(c, info)
    local ls = laNew(c, st, info, refs, n, cnt, fill, opt)
    local m = c._look
    local gap = m.gap or 0
    local hc = {}
    laHideAll(st)
    local order = {}
    local open = info.edge and info.label ~= nil      -- wave3-j (J6)
    local oH, oEdge
    if open then
        -- k3fit (K3-8): an open list fits its rows. Its base height = the first k rows of THIS call (real row heights + gaps), k = min(count, opt.fit or count); the box grows down to show them.
        -- The box height of the last call is measured first (laOpenBox reads st.foldH = the fold row it carried), then st.baseH follows the new rows.
        if not st.hideHook and laTop(c).HookScript then      -- K3-8: the cap is back when the window hides (the next show is small again)
            st.hideHook = true
            laTop(c):HookScript("OnHide", function() st.expanded = false end)
        end
        if cnt > 0 then
            local k = cnt
            if not st.expanded and type(opt.fit) == "number" and opt.fit >= 1 and opt.fit < k then k = math.floor(opt.fit) end
            local bh = 0
            for i = 1, k do bh = bh + laRowH(c, st, info, kinds and kinds[i] or info.row, hc) + (i > 1 and gap or 0) end
            bh = bh + (m.t or 0) + (m.b or 0)
            if bh > 0 then st.fitBase = bh end
        end
        oH, oEdge = laOpenBox(c, st, opt, info)
        st.foldH = 0
    end
    if cnt <= 0 then
        laEmpty(c, st, info, ls, order)
    else
        local count = cnt
        local fold
        local free = nil
        if info.edge then
            if opt.free then free = opt.free      -- k2b K2-10: the height of this list's share (set by Look.GrowGroup)
            elseif info.bound then free = krBoundFree(c, (info.pane and refs._o and refs._o[info.pane]) or refs.root) else free = laEdgeFree(c, opt.margin) end      -- kr-lists L5: a tab body bounds the list; k2b K2-12: info.pane = a split pane bounds it
        end
        if open then      -- wave3-j (J6)
            count = laFit(c, st, info, kinds, cnt, oH, gap, hc)
            if cnt > count and oEdge then
                fold = laRow(c, st, info, info.fold, 1)
                fold.root:Hide()
                count = laFit(c, st, info, kinds, cnt, oH - fold.root:GetHeight() - gap, gap, hc)
                ls.hidden = cnt - count
                ls.fold = fold.refs
            elseif cnt > count then      -- k3fit (K3-8): rows are left over and the screen edge does not stop the box: the fold row comes on top of the box
                fold = laRow(c, st, info, info.fold, 1)
                fold.root:Hide()
                ls.hidden = cnt - count
                ls.fold = fold.refs
                ls.capFold = true
                st.foldH = fold.root:GetHeight() + gap
                oH = oH + st.foldH
            else
                ls.left = cnt - count
            end
        elseif free then
            local total = 0
            for i = 1, cnt do total = total + laRowH(c, st, info, kinds and kinds[i] or info.row, hc) + (i > 1 and gap or 0) end
            if total > free + 0.001 then
                fold = laRow(c, st, info, info.fold, 1)
                fold.root:Hide()
                local used, k = fold.root:GetHeight(), 0
                for i = 1, cnt - 1 do                                -- wave3-d: rows count while they fit (room for the fold row), each with its own height
                    local h = laRowH(c, st, info, kinds and kinds[i] or info.row, hc)
                    local need = h + gap
                    if used + need <= free + 0.001 * need then used = used + need; k = k + 1 else break end
                end
                count = k
                ls.hidden = cnt - k
                ls.fold = fold.refs
            end
        end
        order = laFill(st, info, ls, kinds, 1, count)
        if open then c:SetHeight(oH) end      -- wave3-j (J6)
        if fold then
            ls.firstHidden = count + 1
            if info.more then Look.SetText(fold.refs._o[info.more], "+" .. ls.hidden) end
            for _, oi in ipairs(info.clear or {}) do Look.SetText(fold.refs._o[oi], "") end
            if not fold.wired then
                fold.wired = true
                if not info.plain then      -- k2c K2-13: a plain fold row (no data-kind) is a Frame: it takes no click
                fold.root:RegisterForClicks("LeftButtonUp")
                fold.root:SetScript("OnClick", function()
                    local l = st.ls
                    if l.hidden <= 0 then return end
                    if l.capFold then st.expanded = true; l.Refresh(); return end      -- K3-8: the cap fold = one click shows every row (the box then stops at the screen edge, where the edge fold row is today's fold)
                    local f = l.opt.onFold or Look.hooks.fold
                    if f then f(l, l.firstHidden, l.hidden) end
                end)
                end      -- k2c K2-13
            end
            fold.used = true
            fold.root:Show()
            order[#order + 1] = fold.ent
        end
    end
    if open then
        if cnt <= 0 then c:SetHeight(oH) end
        laLabel(refs, info, ls.shown)      -- wave3-j (J6): the number in the count label = rows shown
    end
    laSweep(st)                            -- kr-lists
    laStack(c, order, opt.noRefit)
    ls.Refresh = function()      -- wave3-d (kr-shell: a refresh always refits, also when the fill call had opt.noRefit)
        local o = ls.opt
        if o and o.noRefit then
            local c2 = {}
            for k, v in pairs(o) do c2[k] = v end
            c2.noRefit = nil
            o = c2
        end
        return Look.GrowList(ls.refs, ls.info, ls.nArg, ls.fill, o)
    end
    laRegister(refs, c, ls)
    return ls
end

-- kr-lists: the options of a page turn / Refresh = the options of the call (onPage, onRow, onInput ...) with the page set
local function pgOpt(opt, page)
    local o = {}
    for k, v in pairs(opt) do o[k] = v end
    o.page, o.reset = page, nil
    return o
end

function Look.Pages(refs, info, n, fill, opt)
    local c = laList(refs, info, "Pages")
    local kinds, cnt = laKinds(info, n, "Pages")                    -- wave3-d: n = a number or a table of row names
    opt = opt or {}
    local pr = info.pager
    local prev, pageT, nxt = refs[pr.prev], refs[pr.page], refs[pr.next]
    if not (prev and pageT and nxt) then error("Look.Pages: the pager nodes prev / page / next are not in refs", 2) end
    local st = laPool(c, info)
    local ls = laNew(c, st, info, refs, n, cnt, fill, opt)
    local m = c._look
    local gap = m.gap or 0
    local hc = {}
    laHideAll(st)
    local H = c:GetHeight()
    if type(H) ~= "number" or H < 1 then H = info.h or 0 end
    -- wave3-d: pages are filled greedily by the real row heights; a row that does not fit starts the next page (a row is never split, a page has one row at least)
    local starts, used, onPage = { 1 }, 0, 0
    local keepK = info.keep      -- k2b K2-9: row kinds that never start a page (they go with the row before)
    local hs = {}
    for i = 1, cnt do
        local h = laRowH(c, st, info, kinds and kinds[i] or info.row, hc)
        hs[i] = h
        if onPage > 0 and used + gap + h > H + 0.001 * (gap + h) then
            local j = i
            if keepK and kinds and keepK[kinds[i]] then      -- walk back over the rows this one is kept with
                j = i - 1
                while j > starts[#starts] and keepK[kinds[j]] do j = j - 1 end
                if j == starts[#starts] then j = nil end      -- the group is the whole page: it stays (it may run past the list box, the glue keeps pages two rows deep)
            end
            if j == nil then
                used = used + gap + h
                onPage = onPage + 1
            elseif j < i then
                starts[#starts + 1] = j
                used, onPage = 0, 0
                for q = j, i do
                    used = used + (onPage > 0 and gap or 0) + hs[q]
                    onPage = onPage + 1
                end
            else
                starts[#starts + 1] = i
                used, onPage = h, 1
            end
        else
            used = used + (onPage > 0 and gap or 0) + h
            onPage = onPage + 1
        end
    end
    local pages = math.max(1, #starts)
    local per
    if kinds == nil then
        local rh = laRowH(c, st, info, info.row, hc)
        per = math.max(1, math.floor((H + gap) / (rh + gap) + 0.001))
    else
        per = 1
        for p = 1, pages do
            local cntp = (starts[p + 1] or (cnt + 1)) - starts[p]
            if cntp > per then per = cntp end
        end
    end
    local page = st.page or 1
    if opt.page then page = opt.page end
    if opt.reset then page = 1 end
    if page > pages then page = pages end
    if page < 1 then page = 1 end
    if st.page and st.page ~= page then          -- kr-lists L2: a page change clears the focus of every edit box in the list
        for _, list in pairs(st.pool) do
            for i = 1, #list do krDropFocus(list[i]) end
        end
    end
    st.page = page
    ls.page, ls.pages, ls.perPage = page, pages, per
    local order = {}
    if cnt <= 0 then
        laEmpty(c, st, info, ls, order)
    else
        order = laFill(st, info, ls, kinds, starts[page], (starts[page + 1] or (cnt + 1)) - 1)
    end
    laSweep(st)                            -- kr-lists
    laStack(c, order)
    Look.SetText(prev, LA_LQ)
    Look.SetText(nxt, LA_RQ)
    Look.SetText(pageT, page .. "/" .. pages)
    prev:SetAlpha(page > 1 and 1 or LA_OFF)
    nxt:SetAlpha(page < pages and 1 or LA_OFF)
    if not st.wired then
        st.wired = true
        local function turnTo(p)
            local l = st.ls
            if p < 1 or p > l.pages then return end
            Look.Pages(l.refs, l.info, l.nArg, l.fill, pgOpt(l.opt, p))      -- kr-lists: the other options (onRow, onInput) stay
            if l.opt.onPage then l.opt.onPage(st.ls) end
        end
        prev:HookScript("OnClick", function() turnTo(st.page - 1) end)
        nxt:HookScript("OnClick", function() turnTo(st.page + 1) end)
        ls.Prev = function() turnTo(st.page - 1) end
        ls.Next = function() turnTo(st.page + 1) end
        ls.Page = function(p) turnTo(p) end
    end
    -- wave3-d: lay out again with the same items, fill and page; the list height is measured again (the page clamps)
    ls.Refresh = function() return Look.Pages(ls.refs, ls.info, ls.nArg, ls.fill, pgOpt(ls.opt, st.page)) end
    laRegister(refs, c, ls)
    return ls
end
-- ==== wave3-a end

-- ==== wave3-b begin: states, new widget kinds, menu caret / header / icon (gap items 18 19). Docs: docs\wave3-b.md
-- States. The converter writes L.states[key] = { base = {..}, hover = {..}, warn = {..}, ... }; each set is { [k] = { attr = value } }, k = the node's
-- place (1 = the unit root, then DOM order) inside its unit (a row template, or a group of like nodes such as the tab buttons).
-- attrs: bg (the background texture color), bl br bt bb (border edge colors), ic (an icon's color texture), tc (text color), a (alpha), text (a label),
-- rc (the colors of the color runs, in order). A color is { "palette name" [, alpha] } (read from Look.palette at run time) or { r, g, b, a }.
-- base = the base look of every attribute that some state changes. Layout never moves: a state is colors, alpha and text only.
--   Look.State(x, state)   x = a refs table of a row template, or the frame (or text) of a node of a unit; state nil or "base" = the base look.
--                          Applied to the node and everything below it; a node inside a unit has its own state, so a row can be "hover" while its
--                          grade tag is "warn". A known state with no sample in the unit = the base look. An unknown state name raises.
--   Look.GradeState(grade) "A" "B" -> "good", "C" -> "warn", "D" -> "bad", anything else ("?") -> "off" (the trust grade, rules 5.12)
local STATE_NAMES = { hover = true, sel = true, press = true, off = true, on = true, warn = true, bad = true, good = true, silver = true }

local function specColor(sp)
    if type(sp[1]) == "string" then return Look.C(sp[1], sp[2]) end
    return sp
end

function Look.StBind(obj, root, L, key, k, last)
    if not root then
        obj._lookSu = { L = L, key = key, map = {}, cur = {} }
        root = obj
    end
    local su = root._lookSu
    su.map[k] = obj
    obj._lookSt = { su = su, k = k, last = last }
end

-- wave3-g: Look.StMap(obj, root, k)  map a node into the state unit of `root` without taking its own state table (a part root inside a row unit keeps the part's table)
function Look.StMap(obj, root, k)
    root._lookSu.map[k] = obj
end

local function stPaint(obj, e)
    local c
    if e.bg then
        c = specColor(e.bg)
        local t = obj._lookBg
        if t then t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) else Look.Bg(obj, nil, { c[1], c[2], c[3], c[4] or 1 }) end
    end
    if e.ic then
        c = specColor(e.ic)
        obj:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
    local ed = obj._lookEdges
    if ed then
        for side, key in pairs({ left = "bl", right = "br", top = "bt", bottom = "bb" }) do
            if e[key] and ed[side] then
                c = specColor(e[key])
                ed[side]:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
            end
        end
    end
    local fs = obj._lookText or obj
    if e.tc then
        c = specColor(e.tc)
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
    if e.a then
        obj:SetAlpha(e.a)
        if obj._lookText then obj._lookText:SetAlpha(e.a) end
    end
    if e.text then Look.SetText(obj, Look.L(e.text)) end
    if e.rc then
        local n = 0
        local s = (fs:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", function()
            n = n + 1
            local sp = e.rc[n]
            if sp then return Look.Hex(specColor(sp)) end
        end)
        fs:SetText(s)
    end
end

-- paint the entries of `set` that lie in the scope k..last; with `base`, only the attributes that `set` has (put back what a state changed)
local function stApply(su, set, base, k, last)
    for i, e in pairs(set) do
        if i >= k and i <= last then
            local obj = su.map[i]
            if obj then
                if base then
                    local t = {}
                    for a in pairs(e) do t[a] = base[i] and base[i][a] end
                    e = t
                end
                stPaint(obj, e)
            end
        end
    end
end

function Look.State(x, state)
    local b = x._lookSt
    if not b and x.root then b = x.root._lookSt end
    if not b then error("Look.State: this node has no state table (no data-state sample in its HTML)", 2) end
    if state == "base" then state = nil end
    if state ~= nil and not STATE_NAMES[state] then error("Look.State: unknown state " .. tostring(state), 2) end
    local su, k, last = b.su, b.k, b.last
    local tbl = su.L.states[su.key]
    local prev = su.cur[k]
    if prev == nil then
        stApply(su, tbl.base, nil, k, last)              -- first call here: the whole base look (a template made from a state sample)
    elseif prev and tbl[prev] then
        stApply(su, tbl[prev], tbl.base, k, last)        -- put back what the old state changed
    end
    su.cur[k] = state or ""                              -- "" = applied, base look
    if state and tbl[state] then stApply(su, tbl[state], nil, k, last) end
end

function Look.GradeState(g)
    if g == "A" or g == "B" then return "good" end
    if g == "C" then return "warn" end
    if g == "D" then return "bad" end
    return "off"
end

-- New widget kinds. The HTML gives the look only; the behavior (focus, keys, click fence) stays in the addon's own builders.
-- Look.Kind(obj, kind [, refs, name])  marks the node (obj._lookKind) and registers it as refs._kinds[name].
-- Look.Input(f, font, size, c, justify, l, r, t, b)   f = an EditBox: font, size, text color, justify and the text insets (border + padding) from the HTML.
-- Look.Fill(f, c, l, r, t, b)  Look.Bar(f, frac)      a bar: the track is the frame's own background and border; the fill is a texture inset by the border.
-- Look.DdBind / Look.Dropdown(f, text [, onOpen])     a dropdown button: label text, and onOpen(menu screen id, f) on click (the host opens the menu).
-- Look.SegBind / Look.Seg(f, which)                   a seg of chips: which = index or chip; that chip gets state "sel", the others the base look.
-- Look.Tag(f, text [, state])                         a tag: sets the text, fits its width to it, and applies a state.
function Look.Kind(obj, kind, refs, name)
    obj._lookKind = kind
    if refs and name then
        refs._kinds = refs._kinds or {}
        refs._kinds[name] = kind
    end
end

function Look.Input(f, font, size, c, justify, l, r, t, b)
    f:SetAutoFocus(false)
    f:SetMultiLine(false)
    Look.FontSet(f, font, size)           -- lead (font retry): was f:SetFont(font, size, "")
    f:SetTextColor(c[1], c[2], c[3], c[4])
    f:SetJustifyH(justify or "LEFT")
    f:SetTextInsets(l, r, t, b)
end

function Look.Fill(f, c, l, r, t, b)
    local tx = f:CreateTexture(nil, "ARTWORK")
    tx:SetColorTexture(c[1], c[2], c[3], c[4])
    tx:SetPoint("TOPLEFT", f, "TOPLEFT", l, -t)
    tx:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", l, b)
    tx:SetWidth(1)
    tx:Hide()
    f._lookFill = { tex = tx, l = l, r = r }
end

function Look.Bar(f, frac)
    local fl = f._lookFill
    if not fl then error("Look.Bar: f is not a bar made by the converter", 2) end
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    local w = (f:GetWidth() - fl.l - fl.r) * frac
    if w > 0 then
        fl.tex:SetWidth(w)
        fl.tex:Show()
    else
        fl.tex:Hide()
    end
end

function Look.DdBind(f, text, caret, opens)
    f._lookDd = { text = text, caret = caret, opens = opens }
end

-- ==== kit-misc begin (kit round 1): M2 right click, M1 size hook, M5 dropdown clip. Docs: docs/rollout\kit-kr-misc.md
function Look.Dropdown(f, text, onOpen, maxW)
    local d = f._lookDd
    if not d then error("Look.Dropdown: f is not a dropdown made by the converter", 2) end
    if text ~= nil then
        local fs = d.text._lookText or d.text
        if f._look and f._look.fitW then
            -- a chip that follows its label: it grows up to maxW (default 1.6 x the HTML chip), then the label is clipped (the game draws the ellipsis)
            if not d.chrome then
                d.chrome = f:GetWidth() - fs:GetStringWidth()
                d.maxW = maxW or math.floor(f:GetWidth() * 1.6 + 0.5)
            elseif maxW then
                d.maxW = maxW
            end
            Look.SetText(d.text, text)
            local need = fs:GetStringWidth()
            local room = d.maxW - d.chrome
            if need > room then
                fs._lookMaxW = room
                fs:SetWidth(room)
                d.clipped = true
            else
                fs._lookMaxW = nil
                if d.clipped then fs:SetWidth(0); d.clipped = nil end
            end
            Look.Refit(f)
        else
            -- a fixed chip: a label that fills the chip already clips (two anchors); a label with one anchor is clipped at the caret
            Look.SetText(d.text, text)
            local cr = d.caret
            local cl, fl = cr and cr:GetLeft(), fs:GetLeft()
            if cl and fl and fs:GetNumPoints() == 1 then
                local room = math.max(1, cl - fl - 4)
                if fs:GetStringWidth() > room then fs:SetWidth(room); d.clipped = true
                elseif d.clipped then fs:SetWidth(0); d.clipped = nil end
            end
        end
    end
    if onOpen and not d.hooked then
        d.hooked = true
        f:HookScript("OnClick", function() onOpen(d.opens, f) end)
    end
end

-- M2: Look.RBind(f, screenId) (the converter writes it for data-ropens): f takes left and right clicks, f._lookRopens = the menu screen id.
--   Look.RClick(f, fn): fn(f, "RightButton") on a right click only. Look.LClick(f, fn): fn(f, "LeftButton") on a left click only.
--   Any other OnClick handler on f also runs for the right click: it gets the button as 2nd argument (check it).
function Look.RBind(f, id)
    f._lookRopens = id
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
end
function Look.RClick(f, fn)
    if type(fn) ~= "function" then error("Look.RClick: fn must be a function", 2) end
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:HookScript("OnClick", function(self, btn) if btn == "RightButton" then fn(self, btn) end end)
end
function Look.LClick(f, fn)
    if type(fn) ~= "function" then error("Look.LClick: fn must be a function", 2) end
    f:HookScript("OnClick", function(self, btn) if btn == nil or btn == "LeftButton" then fn(self, btn or "LeftButton") end end)
end

-- M1: the host calls Look.NotifySize(name) when the text size changes; the module's Look.On("size", fn)
--   handler runs fn(name) (errors go to the error handler, other modules still run). Look.TextSize() = the current size name "S" | "M" | "L".
function Look.NotifySize(name)
    Look.sizeName = name
    local h = Look.hooks.size
    if h then
        local ok, err = pcall(h, name)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end
function Look.TextSize()
    -- the size from Look.NotifySize, else "M"; 2nd value: a saved size exists (never here)
    return Look.sizeName or "M", false
end
-- ==== kit-misc end

function Look.SegBind(f, chips)
    f._lookSeg = chips
end

function Look.Seg(f, which)
    local chips = f._lookSeg
    if not chips then error("Look.Seg: f is not a seg made by the converter", 2) end
    local pick = which
    if type(which) == "number" then pick = chips[which] end
    for i = 1, #chips do Look.State(chips[i], chips[i] == pick and "sel" or nil) end
    return pick
end

function Look.Tag(f, text, state)
    if text ~= nil then Look.SetText(f, text) end
    if state ~= nil then Look.State(f, state) end
    if f._look and f._look.fitW then Look.FitW(f) end
end
-- ==== wave3-b end

-- ==== wave3-c begin: Lua slots, secure slots, Design Pick (gap items 20 21 22). Docs: docs\wave3-c.md
--  L.slots = { { o, wow, draws, w, h, path, keys = { line = { sel, key }, dot = ..., band = ... }, secure } }  (written by convert\screen_slots.py)
--    Look.Slots(refs, L)    for every slot: frame = refs._o[s.o]; keys = { line =, dot =, band = } read through refs._D (the token table, so Design
--                           overrides work); frame._lookSlot = s, frame._lookKeys = keys; then Look.hooks.slot(frame, draws, keys, s) when the host set it
--                           (it draws the graph / icon / model, or makes the secure button OUT OF COMBAT on the frame). Returns the list of slot frames.
--                           The converter makes NO secure frame: a secure slot is a plain Frame, no mouse, nothing drawn (an anchor for siblings).
--    Look.DesignTag(frame, path)  Design Pick: Look.hooks.designTag(frame, path) when set; else frame._lookPath = path (first one) and
--                           frame._lookPaths = { all paths }.
function Look.Slots(refs, L)
    local list = {}
    local D = refs._D or Look.D(L.tokens)
    for i = 1, #(L.slots or {}) do
        local s = L.slots[i]
        local f = refs._o[s.o]
        local keys
        if s.keys then
            keys = {}
            for k, ref in pairs(s.keys) do keys[k] = D(ref[1], ref[2]) end
        end
        f._lookSlot, f._lookKeys = s, keys
        if s.secure and f.EnableMouse then f:EnableMouse(false) end
        list[#list + 1] = f
        local h = Look.hooks.slot
        if h then h(f, s.draws, keys, s) end
    end
    return list
end

function Look.DesignTag(f, path)          -- not Look.Tag: that is the tag widget (wave3-b)
    local h = Look.hooks.designTag
    if h then
        h(f, path)
        return
    end
    f._lookPath = f._lookPath or path
    local t = f._lookPaths
    if not t then t = {}; f._lookPaths = t end
    for i = 1, #t do if t[i] == path then return end end
    t[#t + 1] = path
end
-- ==== wave3-c end

-- ==== wave3-f begin: one look for two addons (kit parts get their fonts by family). Docs: docs\wave3-f.md
--    Look.SetFonts({ Lato = "Interface\\AddOns\\X\\Media\\Fonts\\Lato.ttf", ... })   the addon sets its font files once (addon.json "fonts"); the
--                           converter writes this call into the addon's out\parts.lua. Calls add to what is there.
--    Look.Font(family)      -> the font path of a CSS family. Kit parts (kitparts.lua) call it at run time, so that file is the same bytes in every addon.
Look.fonts = Look.fonts or {}

function Look.SetFonts(map)
    for k, v in pairs(map) do Look.fonts[k] = v end
    Look.Preload()                        -- lead (font retry): each new font file once on a hidden string
end

function Look.Font(family)
    local p = Look.fonts[family]
    if not p then error("Look.Font: no font for family " .. tostring(family) .. " (Look.SetFonts)", 2) end
    return p
end
-- ==== wave3-f end

-- ==== wave3-e begin: resize for every shell window, one store (size + place), relayout, menu / tip scale. Docs: docs\wave3-e.md
-- Every window / dialog / popup / panel / toast gets a size grip from Look.Shell (L.shell.resize = false turns it off: data-resize="off").
-- Menus and tooltips get no grip: they get a scale (Look.Scale).
--   Look.SetStore(tbl)          the host passes a table inside its SavedVariables. The shell writes tbl.size[frameName] = { w, h } (after a resize),
--                               tbl.place[frameName] = { point, relPoint, x, y } (after a drag stop; relative to UIParent), and reads tbl.scale[kind].
--                               No store: nothing is saved. This file never writes a SavedVariables file itself.
--   Look.Relayout(refs)         after a size change: Look.Refit(root), c._lookRefresh() of every c in refs._lists (wave3-d lists), Look.hooks.relayout.
--   Look.Scale(kind)            kind "menu" | "tip": tbl.scale[kind] or 1.   Look.ScaleFrame(f, kind): SetScale on an OWN Look frame (never GameTooltip).
--   Look.Restore(f, refs, shell) L.open calls it last: size from the store (clamped to the bounds), place of an undocked window (clamped to the screen).
--   Look.StorePlace(f)          put f at its stored place (true when there was one); Look.SavePlace(f) writes it.
--  Host hooks: Look.hooks.grip(grip, f, shell) skins the grip (then the default textures are not set), Look.hooks.relayout(f, refs, w, h),
--  and the old moved / undock hooks win over the store.
local RS_TYPES = { window = true, dialog = true, popup = true, panel = true, toast = true }
local RS_GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"

Look.store = nil
function Look.SetStore(tbl)
    Look.store = tbl
end

local function rsPut(kind, name, v)
    local st = Look.store
    if not st or not name then return end
    local t = st[kind]
    if type(t) ~= "table" then t = {}; st[kind] = t end
    t[name] = v
end

function Look.Scale(kind)
    local st = Look.store
    local s = st and type(st.scale) == "table" and st.scale[kind]
    if type(s) == "number" and s > 0 then
        if s < 0.5 then s = 0.5 elseif s > 2 then s = 2 end
        return s
    end
    return 1
end

-- SetScale on a frame this library made (a menu root, an own tip box). GameTooltip and every Blizzard frame are never scaled.
function Look.ScaleFrame(f, kind)
    if not f or not f._lookId or f == rawget(_G, "GameTooltip") then return end
    local s = Look.Scale(kind)
    if (f._lookScale or 1) ~= s then
        f._lookScale = s
        f:SetScale(s)
        Look.HairRefresh(f)      -- w3kit K3-1
    end
end

-- the screen size in the units of f (UIParent size, in the scale of f)
local function rsScreen(f)
    local k = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
    return UIParent:GetWidth() * k, UIParent:GetHeight() * k
end

local function rsClamp(v, lo, hi)
    if v > hi then v = hi end
    if v < lo then v = lo end
    return v
end

-- min = the size the converter made, max = the screen. A window whose height follows its rows (autoH: a grow list) keeps its height.
local function rsBounds(f)
    local rs = f._lookRs
    if not rs then return end
    local sw, sh = rsScreen(f)
    local minW, minH, maxW, maxH = rs.w, rs.h, math.max(sw, rs.w), math.max(sh, rs.h)
    if f._look and f._look.autoH then
        local h = f._look.natH or f:GetHeight()      -- k2b K2-6: the natural height (what the rows need), not whatever the height is right now
        if f._lookOpen and rs.h0 then      -- wave3-j (J6): a window with an open grow list: min = the base height, it grows down to the screen
            minH, maxH = rs.h0, math.max(sh, rs.h0)
        else
            minH, maxH = h, h
        end
    end
    if f.SetResizeBounds then
        pcall(f.SetResizeBounds, f, minW, minH, maxW, maxH)
    else
        if f.SetMinResize then pcall(f.SetMinResize, f, minW, minH) end
        if f.SetMaxResize then pcall(f.SetMaxResize, f, maxW, maxH) end
    end
    rs.min, rs.max = { minW, minH }, { maxW, maxH }
end
Look.Bounds = rsBounds

function Look.Relayout(refs)
    local f = refs and refs.root
    if not f then return end
    f._lookRelaying = true      -- wave3-j (J6): our own SetHeight of an auto-height window is not a grip drag
    Look.Refit(f)
    if refs._splits then Look.SplitFit(refs) end      -- k2d: keep each data-split inside its limits before the lists measure their boxes
    local lists = refs._lists
    if lists then
        refs._relaySeq = (refs._relaySeq or 0) + 1      -- k2b K2-10: an edge group refreshes once per pass, not once per list
        for i = 1, #lists do
            local c = lists[i]
            if c._lookRefresh then c._lookRefresh() end
        end
    end
    f._lookRelaying = nil
    if f._lookRs then rsBounds(f) end
    if Look.hooks.relayout then Look.hooks.relayout(f, refs, f:GetWidth(), f:GetHeight()) end
end

-- ==== w3-1 begin: fold block (data-fold="block"): a head button and a body that hides. Docs: docs/rollout\gaps.md
--  Look.FoldInit(refs, id, block, head, body, caret, open)   called by L.build (convert\screen_fold.py): hides a closed body, hooks the head click
--  Look.Fold(refs, id, open [, onFold])   open true / false = open / close; open nil + onFold = only set the callback; both nil = toggle (the head click)
--      Shows or hides the body, sets the caret text (U+25BC open, U+25B6 closed), then Look.Relayout(refs): the block is a dyn column, so its height is
--      the head (closed) or head + body, the later siblings move up / down and an auto-height window shrinks / grows. onFold(id, open) runs on a change.
local FOLD_OPEN, FOLD_CLOSED = "\226\150\188", "\226\150\182"      -- U+25BC, U+25B6 (UTF-8)
local function foldPaint(fd)
    if fd.open then fd.body:Show() else fd.body:Hide() end
    if fd.caret then Look.SetText(fd.caret, fd.open and FOLD_OPEN or FOLD_CLOSED) end
end
function Look.FoldInit(refs, id, block, head, body, caret, open)
    local fd = { id = id, head = head, body = body, caret = caret, open = open and true or false }
    block._lookFold = fd
    foldPaint(fd)
    if head.HookScript then head:HookScript("OnClick", function() Look.Fold(refs, id) end) end
end
function Look.Fold(refs, id, open, onFold)
    local b = refs and refs[id]
    local fd = b and b._lookFold
    if not fd then error("Look.Fold: " .. tostring(id) .. " is not a fold block built by L.build", 2) end
    if onFold ~= nil then fd.cb = onFold end
    if open == nil and onFold ~= nil then return end
    if open == nil then open = not fd.open end
    open = open and true or false
    local changed = open ~= fd.open
    fd.open = open
    foldPaint(fd)
    Look.Relayout(refs)
    if changed and fd.cb then fd.cb(id, open) end
end
-- ==== w3-1 end

-- ==== kr-shell begin: one flush for several lists (S4), dock pile (S3). Tabs: lazy + hidden button are in section wave2-c (Look.Tabs, Look.TabShow). Docs: docs\rollout\kit-kr-shell.md
--  Look.Flush(refs)       ONE refit of the whole window (Look.Refit(root)) + the resize bounds. After Look.GrowList(..., { noRefit = true }) on several lists.
--  A dock pile: windows (Look.Dock) and panels (Look.Place, shell type panel) that sit at the SAME spot (same anchor frame, same POINT / RELPOINT, one
--  side: LEFT <-> RIGHT) must not overlap. The first one that shows keeps the spot. The next one shown docks beside the last shown one (its POINT on that
--  frame's RELPOINT, same x, y 0). No room beside it (its far edge would leave the screen): the screen edge of that side, same height as the spot.
--  When a window of the pile hides or undocks, the ones shown after it move up to the free place.
function Look.Flush(refs)
    local f = refs and refs.root
    if not f then return end
    local was = f._lookRelaying
    f._lookRelaying = true
    Look.Refit(f)
    f._lookRelaying = was
    -- ==== w3diag begin (K3-6): measure h0 after the refit; when the number of shown open lists changed since they were filled (a list shown after the first one) or a stored size waits,
    -- fill them again once so the shares settle
    if f._lookOpenAll and not f._lookFlushing then
        laSettle(f)
        local n = 0
        for c2 in pairs(f._lookOpenAll) do if c2._laPool and c2:IsShown() then n = n + 1 end end
        if n > 0 and ((f._lookOpenUsed and n ~= f._lookOpenUsed) or (f._lookRs and f._lookRs.wantH)) then
            f._lookFlushing = true
            for c2 in pairs(f._lookOpenAll) do
                if c2._laPool and c2:IsShown() and c2._lookRefresh then pcall(c2._lookRefresh) end
            end
            f._lookFlushing = nil
        end
    end
    -- ==== w3diag end
    if f._lookRs then Look.Bounds(f) end
end

local piles = setmetatable({}, { __mode = "k" })      -- anchor frame -> "POINT|RELPOINT" -> list of members
local pileSeq = 0

local function pileSide(d)
    local p, rp = d.point, d.relPoint
    if rp:find("RIGHT", 1, true) and p:find("LEFT", 1, true) then return "RIGHT" end
    if rp:find("LEFT", 1, true) and p:find("RIGHT", 1, true) then return "LEFT" end
end

local function pileJoin(m, b, key)
    if m.b == b and m.key == key then return end
    if m.b then
        local l = piles[m.b] and piles[m.b][m.key]
        if l then for i = #l, 1, -1 do if l[i] == m then table.remove(l, i) end end end
    end
    local g = piles[b]
    if not g then g = {}; piles[b] = g end
    local l = g[key]
    if not l then l = {}; g[key] = l end
    l[#l + 1] = m
    m.b, m.key = b, key
end

-- the member shown last before m (shown, placed, lower seq)
local function pileOcc(m)
    local l = m.seq and m.b and piles[m.b] and piles[m.b][m.key]
    if not l then return end
    local best
    for i = 1, #l do
        local o = l[i]
        if o ~= m and o.seq and o.seq < m.seq and o.f:IsShown() and o.placed() and (not best or o.seq > best.seq) then best = o end
    end
    return best
end

-- the place of m at the spot { POINT, RELPOINT, x, y } on frame b -> plan { p, rel, rp, x, y, sig }
function pile.plan(m, b, d)
    local spot = { p = d.point, rel = b, rp = d.relPoint, x = d.x, y = d.y, sig = "spot" }
    local side = pileSide(d)
    if not side then return spot end
    pileJoin(m, b, d.point .. "|" .. d.relPoint)
    local occ = pileOcc(m)
    if not occ then return spot end
    local f = m.f
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local k = occ.f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local w = f:GetWidth() or 0
    local room = true
    if side == "RIGHT" then
        local r = occ.f:GetRight()
        if r then room = r * k + w + d.x <= uw + 1 end
    else
        local l = occ.f:GetLeft()
        if l then room = l * k - w + d.x >= -1 end
    end
    if room then return { p = d.point, rel = occ.f, rp = d.relPoint, x = d.x, y = 0, sig = "next:" .. tostring(occ.f) } end
    local bt, bb = b:GetTop(), b:GetBottom()
    if not (bt and bb) then return spot end
    local kb = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local vp = d.relPoint:find("TOP", 1, true) and "TOP" or (d.relPoint:find("BOTTOM", 1, true) and "BOTTOM" or "")
    local fvp = d.point:find("TOP", 1, true) and "TOP" or (d.point:find("BOTTOM", 1, true) and "BOTTOM" or "")
    local ofs
    if vp == "TOP" then ofs = bt * kb - uh elseif vp == "BOTTOM" then ofs = bb * kb else ofs = (bt + bb) / 2 * kb - uh / 2 end
    return { p = fvp .. side, rel = UIParent, rp = vp .. side, x = 0, y = ofs + d.y, sig = "edge" }
end

function pile.apply(f, plan)
    f:ClearAllPoints()
    f:SetPoint(plan.p, plan.rel, plan.rp, plan.x, plan.y)
end

-- the members shown after seq0 (or all shown ones) look at their place again, in the order they showed
function pile.after(m, seq0)
    local l = m.b and piles[m.b] and piles[m.b][m.key]
    if not l or m.busy then return end
    local list = {}
    for i = 1, #l do
        local o = l[i]
        if o ~= m and o.seq and o.seq > (seq0 or 0) and o.f:IsShown() then list[#list + 1] = o end
    end
    table.sort(list, function(a, c) return a.seq < c.seq end)
    m.busy = true
    for i = 1, #list do list[i].refresh() end
    m.busy = nil
end

-- m = { f, placed = fn -> bool, refresh = fn, onShow = fn or nil }: counts the show order of f
function pile.track(m)
    local f = m.f
    local function shownNow()
        pileSeq = pileSeq + 1
        m.seq = pileSeq
    end
    if f:IsShown() then shownNow() end
    f:HookScript("OnShow", function()
        shownNow()
        if m.onShow then m.onShow() end
    end)
    f:HookScript("OnHide", function()
        local old = m.seq
        m.seq = nil
        if old then pile.after(m, old) end
    end)
end

-- a panel at its owner (called by Look.Place): true when the pile placed it (shell.anchor on a side of the owner)
function pile.panel(f, owner, a)
    local d = { point = a[1], relPoint = a[2], x = a[3], y = a[4] }
    if not pileSide(d) then return false end
    local m = f._lookPile
    if not m then
        m = { f = f, placed = function() return true end }
        m.refresh = function() pile.apply(f, pile.plan(m, m.owner, m.d)) end
        m.onShow = m.refresh
        f._lookPile = m
        pile.track(m)
    end
    m.owner, m.d = owner, d
    pile.apply(f, pile.plan(m, owner, d))
    return true
end
-- ==== kr-shell end

-- ---- place
function Look.SavePlace(f)
    local l, t = f:GetLeft(), f:GetTop()
    if type(l) ~= "number" or type(t) ~= "number" then return end
    rsPut("place", f:GetName(), { "TOPLEFT", "BOTTOMLEFT", l, t })
end

-- keep f on the screen by moving its first anchor
local function rsOnScreen(f)
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (l and r and t and b) then return end
    local sw, sh = rsScreen(f)
    local dx, dy = 0, 0
    if r > sw then dx = sw - r end
    if l + dx < 0 then dx = -l end
    if t > sh then dy = sh - t end
    if b + dy < 0 then dy = -b end
    if dx ~= 0 or dy ~= 0 then
        local pt, rel, rp, x, y = f:GetPoint(1)
        if pt then f:SetPoint(pt, rel, rp, (x or 0) + dx, (y or 0) + dy) end
    end
end

function Look.StorePlace(f)
    local st = Look.store
    local p = st and type(st.place) == "table" and st.place[f:GetName() or ""]
    if type(p) ~= "table" or type(p[1]) ~= "string" or type(p[2]) ~= "string" or type(p[3]) ~= "number" or type(p[4]) ~= "number" then return false end
    f:ClearAllPoints()
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    rsOnScreen(f)
    return true
end

function Look.Restore(f, refs, shell)
    local st = Look.store
    if not st then return end
    shell = shell or f._lookShell or {}
    local rs = f._lookRs
    local sz = rs and type(st.size) == "table" and st.size[f:GetName() or ""]
    if type(sz) == "table" and type(sz[1]) == "number" and type(sz[2]) == "number" then
        local sw, sh = rsScreen(f)
        local w = rsClamp(sz[1], rs.w, math.max(sw, rs.w))
        local h = f:GetHeight()
        if not (f._look and f._look.autoH) then h = rsClamp(sz[2], rs.h, math.max(sh, rs.h)) else rs.wantH = sz[2]      -- wave3-j (J6): an auto-height window keeps the stored height as dH at its next list layout
            if f._look.natH and h < f._look.natH then h = f._look.natH end      -- k2b K2-6: never below the natural height (the rows need it)
        end
        f:SetSize(w, h)
        Look.Relayout(refs or rs.refs)
    end
    if shell.type == "window" and not shell.dock then
        if Look.StorePlace(f) then rsOnScreen(f) end
    end
end

-- ---- the grip
Look.GRIP = 16      -- wave3-j: the grip size (the kit has no --kit-grip token); content keeps Look.GRIP + 4 = 20 free on the right (the shell corner)
-- sizing grows from the top left corner: a frame with another anchor gets a TOPLEFT anchor on UIParent first (a docked window is then free)
local function rsTopLeft(f)
    local pt = f:GetPoint(1)
    if f:GetNumPoints() == 1 and pt == "TOPLEFT" then return end
    local l, t = f:GetLeft(), f:GetTop()
    if type(l) ~= "number" or type(t) ~= "number" then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    local d = f._lookDock
    if d then d.free = true end
end

local function rsStop(f, grip, rs)
    if not f._lookSizing then return end
    f._lookSizing = false
    f._lookRsDirty = false
    f:StopMovingOrSizing()
    grip:SetScript("OnUpdate", nil)
    Look.Relayout(rs.refs)
    rsPut("size", f:GetName(), { f:GetWidth(), f:GetHeight() })
    local sh = f._lookShell
    if sh and sh.type == "window" and not Look.hooks.moved and not (f._lookDock and not f._lookDock.free) then Look.SavePlace(f) end
end

function Look.ShellResize(f, refs, shell)
    if not RS_TYPES[shell.type] or shell.resize == false or f._lookRs then return end
    local rs = { w = f:GetWidth(), h = f:GetHeight(), refs = refs or { root = f } }
    f._lookRs = rs
    f:SetResizable(true)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(Look.GRIP, Look.GRIP)      -- wave3-j: the grip box = proto-full grip.css .gripH (16 x 16, 2 px from the bottom right corner)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:EnableMouse(true)
    rs.grip = grip
    f._lookFrames = f._lookFrames or {}
    f._lookFrames[#f._lookFrames + 1] = grip      -- Look.Stack moves the grip with its window
    grip._lookFrames = {}
    grip._lookParent = f
    if Look.hooks.grip then
        Look.hooks.grip(grip, f, shell)
    else
        grip:SetNormalTexture(RS_GRIP .. "Up")
        grip:SetPushedTexture(RS_GRIP .. "Down")
        grip:SetHighlightTexture(RS_GRIP .. "Highlight")
    end
    grip:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        rsBounds(f)
        rsTopLeft(f)
        f._lookSizing = true
        f._lookRsDirty = false
        f:StartSizing("BOTTOMRIGHT")
        self:SetScript("OnUpdate", function()          -- once per frame while sizing
            if f._lookRsDirty then
                f._lookRsDirty = false
                Look.Relayout(rs.refs)
            end
        end)
    end)
    grip:SetScript("OnMouseUp", function(self) rsStop(f, self, rs) end)
    f:HookScript("OnSizeChanged", function()
        if f._lookSizing then
            if f._lookOpen and rs.h0 and not f._lookRelaying then rs.dH = max(0, f:GetHeight() - rs.h0) end      -- wave3-j (J6): the dragged height
            f._lookRsDirty = true
        elseif f._look and f._look.autoH then
            rsBounds(f)           -- a window that follows its rows keeps min height = max height = its height
        end
    end)
    f:HookScript("OnHide", function() rsStop(f, grip, rs) end)
    rsBounds(f)
end
-- ==== wave3-e end

-- ==== k2d begin: chart / list divider (K2-11, data-split). Docs: docs\rollout\kit-k2d.md
--  The converter writes Look.SplitBind(refs, name, t) after the three children (pane A, the divider, pane B) of a data-split box are made:
--  t = { id = screen id, root, box, a, div, b, axis = "y" (column: bar dragged up / down) | "x" (row: left / right), def = pane A px in the HTML,
--  minA, minB, defB = pane B px in the HTML, fix = the box main size minus pane A minus pane B in the HTML (bar, gaps, padding) }.
--  Pane A has a fixed main size (SetHeight / SetWidth, = px); the bar and pane B follow (a column: their top anchors move by the change, pane B stays
--  anchored to the bottom; a row: the bar hangs on pane A and pane B on the bar). The px is saved on drag stop: Look.store.split["<screen id>.<name>"].
--   Look.SplitSet(frame, name, px)  frame = the screen root (or its refs); px = pane A size, clamped (B >= minB first, then A >= minA), saved, then
--                                   Look.Relayout. px nil = the default again (and the saved value is cleared). Returns the px that was set.
--                                   0 < px < 1 = a SHARE: pane A share of (A + B), turned into px at once (or at the first SplitFit when the box is not
--                                   measurable yet), clamped, saved as px. A store value 0 < v < 1 reads the same way. nil / NaN / <= 0 = the default.
--   Look.SplitGet(frame, name)      -> px, def, minA, minB, max (the largest px the box allows now, nil while its size is unknown)
--   Look.SplitFit(refs)             called by Look.Relayout: put each split back inside its limits (a window resize keeps pane A px, then clamps),
--                                   run the slot hook for a slot in a pane whose size changed, then Look.hooks.split(name, px) when px changed.
--  Drag: OnUpdate is set on the bar ONLY while the left mouse button is down (like the shell grip); off in combat; double click = the default;
--  no wheel script. Look.On("split", fn(name, px)) fires after every move (a drag step, SplitSet, a clamp by a window resize).
--  (The public function lines start at column 0 inside the do block: tests\convertpi_test.py reads them that way.)
do
    local DBL = 0.4      -- seconds between two mouse downs = a double click

    local function spMain(sp)
        local m = sp.axis == "y" and sp.box:GetHeight() or sp.box:GetWidth()
        if type(m) ~= "number" or m <= 0 then return nil end
        return m
    end

    local function spCross(sp)
        local c = sp.axis == "y" and sp.box:GetWidth() or sp.box:GetHeight()
        return type(c) == "number" and c or 0
    end

    local function spMax(sp)
        local m = spMain(sp)
        return m and (m - sp.fix - sp.minB) or nil
    end

    local function spClamp(sp, px)
        local hi = spMax(sp) or (sp.def + sp.defB - sp.minB)      -- size not measurable yet (a screen being built): the HTML size of the box
        if px > hi then px = hi end
        if px < sp.minA then px = sp.minA end
        return px
    end

    local function spApply(sp, px)
        local d = px - sp.def
        if sp.axis == "y" then
            sp.a:SetHeight(px)
            for i = 1, #sp.base do
                local e = sp.base[i]
                e.f:ClearAllPoints()
                for j = 1, #e.pts do
                    local p = e.pts[j]
                    e.f:SetPoint(p[1], p[2], p[3], p[4], p[1]:find("TOP", 1, true) and (p[5] - d) or p[5])
                end
            end
        else
            sp.a:SetWidth(px)
        end
        sp.px = px
    end

    local function spSlots(f, out)
        if f._lookSlot then out[#out + 1] = f end
        local list = f._lookFrames
        if list then
            for i = 1, #list do spSlots(list[i], out) end
        end
    end

    local function spSlotHooks(pane)
        local h = Look.hooks.slot
        if not h then return end
        local list = {}
        spSlots(pane, list)
        for i = 1, #list do
            local f = list[i]
            h(f, f._lookSlot.draws, f._lookKeys, f._lookSlot)
        end
    end

    local function differ(a, b) return a ~= nil and b ~= nil and math.abs(a - b) > 0.01 end      -- an unknown size (nil) is no change

    -- one split: slot hooks of a pane whose size changed, then the split hook when px changed. The first call only records the sizes.
    local function spNotify(sp)
        local m = spMain(sp)
        local sig = { a = sp.px, b = m and (m - sp.fix - sp.px) or nil, c = spCross(sp) }
        local old = sp.sig
        sp.sig = sig
        if not old or sp.busy then return end
        local pxMoved = differ(old.a, sig.a)
        local aMoved = pxMoved or differ(old.c, sig.c)
        local bMoved = differ(old.b, sig.b) or differ(old.c, sig.c)
        if not (aMoved or bMoved) then return end
        sp.busy = true
        local ok, err = pcall(function()
            if aMoved then spSlotHooks(sp.a) end
            if bMoved then spSlotHooks(sp.b) end
            if pxMoved and Look.hooks.split then Look.hooks.split(sp.name, sp.px) end
        end)
        sp.busy = nil
        if not ok then error(err, 0) end
    end

function Look.SplitFit(refs)
        local l = refs and refs._splitList
        if not l then return end
        for i = 1, #l do
            local sp = l[i]
            if sp.pend then      -- a share (0 < v < 1 of A + B) waits for a measurable box
                local m = spMain(sp)
                if m then
                    local px = spClamp(sp, sp.pend * (m - sp.fix))
                    sp.pend = nil
                    spApply(sp, px)
                    rsPut("split", sp.id .. "." .. sp.name, px)
                end
            end
            local px = spClamp(sp, sp.px)
            if px ~= sp.px then spApply(sp, px) end
            spNotify(sp)
        end
    end

    local function spSet(sp, px, save)
        px = spClamp(sp, px)
        local moved = px ~= sp.px
        if moved then
            spApply(sp, px)
            sp.moved = true
        end
        if save then rsPut("split", sp.id .. "." .. sp.name, px) end
        if moved then
            if sp.refs.root then Look.Relayout(sp.refs) else spNotify(sp) end
        end
        return px
    end

    local function spFind(frame, name)
        local tbl = frame and (frame._lookSplits or frame._splits)
        local sp = tbl and tbl[name]
        if not sp then error("Look.Split*: no split " .. tostring(name) .. " in this screen (data-split)", 3) end
        return sp
    end

function Look.SplitSet(frame, name, px)
        local sp = spFind(frame, name)
        if type(px) == "number" and px == px and px > 0 and px < 1 then      -- a share of A + B: px at once, or at the first SplitFit
            local m = spMain(sp)
            if m then
                sp.pend = nil
                return spSet(sp, px * (m - sp.fix), true)
            end
            sp.pend = px
            return sp.px
        end
        if px ~= nil and not (type(px) == "number" and px == px and px > 0) then px = nil end      -- bad value = the default
        sp.pend = nil
        if px == nil then
            local st = Look.store
            if st and type(st.split) == "table" then st.split[sp.id .. "." .. sp.name] = nil end
            return spSet(sp, sp.def, false)
        end
        return spSet(sp, px, true)
    end

function Look.SplitGet(frame, name)
        local sp = spFind(frame, name)
        return sp.px, sp.def, sp.minA, sp.minB, spMax(sp)
    end

    local function spCursor(sp)
        local x, y = GetCursorPosition()
        local k = sp.box:GetEffectiveScale()
        if not k or k <= 0 then k = 1 end
        if sp.axis == "y" then return y / k end
        return x / k
    end

    local function spHover(sp, on)
        if sp.div._lookSt then Look.State(sp.div, on and "hover" or nil) end
    end

    local function spStop(sp)
        local d = sp.drag
        if not d then return end
        sp.drag = nil
        sp.div:SetScript("OnUpdate", nil)
        if sp.moved then rsPut("split", sp.id .. "." .. sp.name, sp.px) end
        sp.moved = nil
        if not (sp.div.IsMouseOver and sp.div:IsMouseOver()) then spHover(sp, false) end
    end

function Look.SplitBind(refs, name, t)
        local sp = { refs = refs, name = name, id = t.id, box = t.box, a = t.a, div = t.div, b = t.b, axis = t.axis, def = t.def,
                     minA = t.minA, minB = t.minB, fix = t.fix, defB = t.defB, px = t.def, base = {} }
        refs._splits = refs._splits or {}
        refs._splitList = refs._splitList or {}
        refs._splits[name] = sp
        refs._splitList[#refs._splitList + 1] = sp
        if t.root then t.root._lookSplits = refs._splits end
        if sp.axis == "y" then      -- the bar and pane B hang from the box top: remember their points, a move shifts the top ones
            for _, f in ipairs({ sp.div, sp.b }) do
                local e = { f = f, pts = {} }
                for i = 1, f:GetNumPoints() do
                    local pt, rel, rp, x, y = f:GetPoint(i)
                    e.pts[i] = { pt, rel, rp, x or 0, y or 0 }
                end
                sp.base[#sp.base + 1] = e
            end
        end
        local st = Look.store
        local v = st and type(st.split) == "table" and st.split[sp.id .. "." .. name]
        if type(v) == "number" and v == v and v > 0 then
            if v < 1 then      -- a share of A + B: px once the box can be measured
                if spMain(sp) then spApply(sp, spClamp(sp, v * (spMain(sp) - sp.fix))); rsPut("split", sp.id .. "." .. name, sp.px) else sp.pend = v end
            else
                spApply(sp, spClamp(sp, v))
            end
        end
        sp.sig = { a = sp.px }      -- the sizes of the panes are not known yet: the first move is measured against px only
        sp.div:EnableMouse(true)
        sp.div:HookScript("OnEnter", function() spHover(sp, true) end)
        sp.div:HookScript("OnLeave", function() if not sp.drag then spHover(sp, false) end end)
        sp.div:HookScript("OnMouseDown", function(_, btn)
            if btn ~= "LeftButton" or InCombatLockdown() then return end
            local now = GetTime()
            if sp.lastDown and now - sp.lastDown <= DBL then
                sp.lastDown = nil
                Look.SplitSet(refs, name, nil)
                return
            end
            sp.lastDown = now
            sp.drag = { c0 = spCursor(sp), a0 = sp.px }
            spHover(sp, true)
            sp.div:SetScript("OnUpdate", function()          -- once per frame while the button is down
                local d = sp.drag
                if not d then return end
                if InCombatLockdown() then spStop(sp) return end
                local c = spCursor(sp)
                spSet(sp, sp.axis == "y" and (d.a0 + d.c0 - c) or (d.a0 + c - d.c0), false)
            end)
        end)
        sp.div:HookScript("OnMouseUp", function() spStop(sp) end)
        sp.div:HookScript("OnHide", function() spStop(sp) end)
        sp.box:HookScript("OnShow", function()      -- a shown screen (a tab body shown later): the saved px inside the limits
            local px = spClamp(sp, sp.px)
            if px ~= sp.px then spApply(sp, px) end
            if sp.refs.root then Look.Relayout(sp.refs) end
        end)
        return sp
    end
end
-- ==== k2d end

-- ==== lead begin: public hooks (docs\framework-addon.md section 6). The host sets a hook with Look.On(name, fn); generated code never does.
local HOOK_NAMES = { moved = true, undock = true, docked = true, designTag = true, grip = true, relayout = true, fold = true, slot = true, size = true, row = true, input = true, split = true }
function Look.On(name, fn)
    if not HOOK_NAMES[name] then error("Look.On: unknown hook " .. tostring(name), 2) end
    if fn ~= nil and type(fn) ~= "function" then error("Look.On: fn must be a function or nil", 2) end
    Look.hooks[name] = fn
end
-- ==== lead end

-- ==== widgets begin: a list box by hand (docs\framework-widgets.md). What L.build does for a data-list box, so Look.Pages / Look.GrowList accept it.
--   Look.ListBox(f, D [, group])  f = a plain frame: clips its children, keeps the token function D for the row templates, and becomes a column that
--                                 grows down to fit (Look.Meta dyn) with one row group (default "item"). Then Look.Pages(refs, info, n, fill) works on it.
function Look.ListBox(f, D, group)
    f:SetClipsChildren(true)
    f._lookD = D
    Look.Meta(f, { dir = "col", l = 0, r = 0, t = 0, b = 0, dyn = true })
    Look.Group(f, group or "item")
end
-- ==== widgets end

-- ==== lead begin (font retry): preload + check + retry of the addon font files. Docs: docs\font-retry.md
--   Some clients refuse SetFont on a font file in some addon folders, the whole session. So a font path is tested before use.
--   v2: a path is tested on NEW strings only, and a real string never gets a path that is not proven loaded.
--   v3 (this block): a kit font path has COPIES: the same Media\Fonts\<file> in a module folder. Order: the kit path, then this
--   module's own folder (ADDON), then FALLBACK (none here). Only modules that are here (this one, or IsAddOnLoaded).
--   Real strings take the first copy that a test loads; the game font only when no copy loads.
--   Look.Preload()                  each Look.fonts path not seen yet: a test (below). A miss of the kit path starts the chain.
--                                   Look.SetFonts calls it.
--   Look.FontSet(obj, path, size)   -> true | false (Look.Text and Look.Input use it). A path with no proven copy is tested first (each
--                                   copy at most once per second). Loaded: SetFont of that copy on obj. Not loaded: obj gets the game
--                                   font (STANDARD_TEXT_FONT) so SetText never errors, obj is noted, the chain starts.
--   A test = up to 3 routes, each on a NEW string: "fresh" (a new hidden string, size 12), "object" (CreateFont object SetFont,
--   then a new hidden string), "shown" (a new string on a shown alpha-0 frame off screen).
--   The chain (one at a time; it waits for PLAYER_LOGIN): tries at TRY_AT s. A try tests, for each path still open, the copies that
--   are better than its best one, in order. A copy that loads goes on the noted objects, then Look.Refit on their root frames.
--   A menu measures its rows again when it opens. Real strings keep the copy they have (the copies are the same bytes).
--   Log lines (ns.Log, tag UI, in pcall):
--     "font file=<file> ok=<folder>|none tried=<folders>"   ONE line per AddOns font file: at once when the kit path loads at its
--        first test (ok=<folder> tried=<folder>); else when the kit path loads in the chain, or at the last try (ok = the best
--        folder that loaded, none = no copy). tried = the folders tested, in order. A file with ok=none that loads later (late
--        tries) writes its line again. Read: ok = another folder = a folder problem; none = a limit.
--     "font retry ok tries=N fixed=F via=<routes> wait=0"   or   "font retry fail tries=7 fixed=F out=<files> via=<routes|-> wait=W"
--        only when real texts waited on the game font. out = files with no copy; via = the routes that loaded a copy in this
--        chain; wait = objects still on the game font.
--   After a fail: one quiet try per LATE_EVERY s, LATE_MAX times; when all is back: "font retry late ok tries=N fixed=F via=.. wait=0".
--   v4 (scan): from try SCAN_TRY, a kit path with no copy in use gets ONE scan of the folders of the other LOADED addons (names from
--   the client at run time, in its order; none in this file): the same Media\Fonts\<file>, "fresh" route only (no Font object),
--   at most SCAN_BUDGET tests a frame, until one loads. Real client 2026-11-23: every new font path was refused, even a new
--   family name; only paths that loaded before still loaded (docs\font-retry.md v4). The file line then says ok=<that folder> and ends its tried list with ",+N" (N = folders scanned).
--   Look.fontRetry = { state, tries, fixed, out, via, wait, late, scan } (read only). state: idle | login | wait | ok | fail.
--   scan = scan tests made by this Look (all paths, whole session).
--   No saved data, no OnUpdate. Frames only when needed: one hidden host frame (first test), one shown host frame (first "shown"
--   route), one PLAYER_LOGIN frame at a miss before login. Global names: only the "object" route's Font objects (LookWarm<id>_<n>).
local TRY_AT = { 0.2, 1, 2, 4, 10, 20, 40 }          -- s after the first miss
local LATE_EVERY, LATE_MAX = 60, 10                  -- v2: after a fail, one quiet try a minute for 10 minutes
local FALLBACK = {}                                  -- v3: other module folders with the same Media\Fonts files (none here)
local SCAN_TRY, SCAN_BUDGET = 3, 20                  -- v4: the scan starts at try 3 (2 s; the kit + own copies had 3 tries); tests a frame
local FR = { state = "idle", tries = 0, fixed = 0, out = "", via = "", wait = 0, late = 0, scan = 0 }
Look.fontRetry = FR
local fontScan = {}                                   -- v4: kit path -> "run" | "done": its scan of the other loaded addons' folders
local scanQ, scanHead, scanOn = {}, 1, false          -- v4: the scan queue { kit path, folder, copy path }; a step is due
local fontUse = {}                                    -- kit path -> the path (kit or copy) that a test loaded; real strings take it
local fontBad = {}                                    -- kit path -> true: no copy loaded yet; real strings get the game font
local fontGood = {}                                   -- path (kit or copy) -> true: a test loaded it
local fontBest = {}                                   -- kit path -> the folder of the best copy that loaded (order of cands)
local fontOpen = {}                                   -- kit path -> true: its file line is not written yet (better copies are tested again)
local fontDone = {}                                   -- kit path -> true: its file line is written
local fontTried = {}                                  -- kit path -> { [folder] = true, list = { folder, ... } }: folders tested, in order
local fontPend = setmetatable({}, { __mode = "k" })  -- obj -> { kit path, size }: obj holds the game font now
local fontSeen = {}                                   -- path -> true: preloaded by this Look
local fontVia = {}                                    -- route -> true: the routes that loaded a copy in this chain
local testAt = {}                                     -- path -> GetTime() of its last test
local hostHidden, hostShown, sawLogin, chainOut
local warmN, warmId = 0, nil
local fontChain

local function fontOk(o, path, size)
    local ok, r = pcall(o.SetFont, o, path, size, "")    -- the real SetFont returns false when the file did not load
    return ok and r ~= false
end

local function fontLog(fmt, ...)      -- SW: ns.Log takes one string
    local ok, s = pcall(string.format, fmt, ...)
    if ok and type(ns.Log) == "function" then pcall(ns.Log, "UI " .. s) end
end

-- the host frame of the test strings: hidden (no parent), or shown at alpha 0 off screen
local function host(shown)
    if shown then if hostShown then return hostShown end
    elseif hostHidden then return hostHidden end
    local CF, UP = rawget(_G, "CreateFrame"), rawget(_G, "UIParent")
    if type(CF) ~= "function" then return nil end
    local ok, f = pcall(CF, "Frame", nil, shown and UP or nil)
    if not ok or type(f) ~= "table" or type(f.CreateFontString) ~= "function" then return nil end
    if shown then
        pcall(f.SetSize, f, 1, 1)
        pcall(f.SetAlpha, f, 0)
        if UP then pcall(f.SetPoint, f, "TOPLEFT", UP, "TOPLEFT", -64, 64) end
        pcall(f.Show, f)
        hostShown = f
    else
        pcall(f.Hide, f)
        hostHidden = f
    end
    return f
end

local function newString(shown)
    local f = host(shown)
    if not f then return nil end
    local ok, s = pcall(f.CreateFontString, f, nil, "OVERLAY")
    return (ok and type(s) == "table") and s or nil
end

-- a test of one path on NEW strings only. Returns the route that loaded it, or nil.
local function probe(path)
    local s = newString(false)
    if s and fontOk(s, path, 12) then return "fresh" end
    local CFo = rawget(_G, "CreateFont")
    if type(CFo) == "function" then
        warmN = warmN + 1
        warmId = warmId or (tostring(FR):gsub("[^%w]", ""))       -- one id per Look instance (two modules = two names)
        local ok, o = pcall(CFo, "LookWarm" .. warmId .. "_" .. warmN)
        if ok and type(o) == "table" and type(o.SetFont) == "function" then
            pcall(o.SetFont, o, path, 12, "")
            s = newString(false)
            if s and fontOk(s, path, 12) then return "object" end
        end
    end
    s = newString(true)
    if s and fontOk(s, path, 12) then return "shown" end
    return nil
end

-- a test from Preload / FontSet: at most one per second per path (a menu of 30 texts makes one test, not 30)
local function testNow(path)
    local T = rawget(_G, "GetTime")
    local okT, now = false, nil
    if type(T) == "function" then okT, now = pcall(T) end
    now = (okT and type(now) == "number") and now or nil
    if now and testAt[path] and now - testAt[path] < 1 then return nil end
    testAt[path] = now
    return probe(path)
end

-- v3: is module `name` here? This module always; another one when IsAddOnLoaded says so (asked each time: a module may load later)
local function addonHere(name)
    if name == ADDON then return true end
    local C = rawget(_G, "C_AddOns")
    local f = (type(C) == "table" and C.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    if type(f) ~= "function" then return false end
    local ok, r = pcall(f, name)
    return ok and r and true or false
end

-- v3: the copies of a kit path, in order: { { folder, path }, ... }; [1] = the kit path. A path outside Interface\AddOns has no copies
-- (folder "-"). A copy = the same file under another module folder: this module first, then FALLBACK; only modules that are here.
local function cands(path)
    local pre, dir, rest = path:match("^(.-[Aa][Dd][Dd][Oo][Nn][Ss][\\/])([^\\/]+)([\\/].+)$")
    local t = { { dir or "-", path } }
    if not pre then return t end
    local seen = { [dir:lower()] = true }
    local function add(name)
        if type(name) ~= "string" or seen[name:lower()] then return end
        seen[name:lower()] = true
        if addonHere(name) then t[#t + 1] = { name, pre .. name .. rest } end
    end
    add(ADDON)
    for _, n in ipairs(FALLBACK) do add(n) end
    return t
end

local function kitDir(path)
    return path:match("^.-[Aa][Dd][Dd][Oo][Nn][Ss][\\/]([^\\/]+)[\\/]") or "-"
end

local function fileName(path) return path:match("([^\\/]+)$") or path end

local function fileLine(path)
    if kitDir(path) == "-" then return end                -- a game font path: no copies, no line
    local t = fontTried[path]
    local tried = t and table.concat(t.list, ",") or "-"
    if t and t.extra then tried = tried .. ",+" .. t.extra end   -- v4: the number of other folders the scan tested
    fontLog("font file=%s ok=%s tried=%s", fileName(path), fontBest[path] or "none", tried)
end

-- the file line of path, once (a late find writes it again: see found)
local function settle(path)
    if fontDone[path] then return end
    fontOpen[path] = nil
    fontDone[path] = true
    fileLine(path)
end

-- v3: test the copies of path that are better than its best one, in order (test = probe or testNow); the first that loads is the new
-- best (real strings take the first copy that loads, and keep it). Returns route, folder of the new best; or nil.
local function better(path, test)
    for _, c in ipairs(cands(path)) do
        local dir, p = c[1], c[2]
        if dir == fontBest[path] then return nil end
        local t = fontTried[path]
        if not t then t = { list = {} }; fontTried[path] = t end
        if not t[dir] then t[dir] = true; t.list[#t.list + 1] = dir end
        local via = fontGood[p] and "good" or test(p)
        if via then
            fontGood[p] = true
            fontBest[path] = dir
            if not fontUse[path] then fontUse[path] = p end
            return via, dir
        end
    end
    return nil
end

local function after()
    local T = rawget(_G, "C_Timer")
    return (type(T) == "table" and type(T.After) == "function") and T.After or nil
end

local function loggedIn()
    if sawLogin then return true end
    local IL = rawget(_G, "IsLoggedIn")
    if type(IL) == "function" then
        local ok, r = pcall(IL)
        if ok and r then return true end
    end
    return false
end

-- the top Look frame above obj (Look.Frame links each frame to its parent)
local function rootOf(o)
    local f = o._lookFrames and o or (type(o.GetParent) == "function" and o:GetParent()) or nil
    while f and f._lookParent and f._lookParent._lookFrames do f = f._lookParent end
    return (f and f._lookFrames) and f or nil
end

-- kit paths with no copy in use (real strings on the game font)
local function outPaths()
    local t = {}
    for p in pairs(fontBad) do t[p] = true end
    for _, a in pairs(fontPend) do if not fontUse[a[1]] then t[a[1]] = true end end
    return t
end

-- kit paths the chain works on: open (file line not written), or no copy in use, or objects that wait
local function workPaths()
    local t = outPaths()
    for p in pairs(fontOpen) do t[p] = true end
    for _, a in pairs(fontPend) do t[a[1]] = true end
    return t
end

local function waitN()
    local n = 0
    for _ in pairs(fontPend) do n = n + 1 end
    return n
end

local function viaText()
    local t = {}
    for r in pairs(fontVia) do t[#t + 1] = r end
    table.sort(t)
    return #t > 0 and table.concat(t, ",") or "-"
end

-- path has a copy in use: clear bad, put it on the objects that wait for it (their root frames refit)
local function recover(path, roots)
    fontBad[path] = nil
    local use = fontUse[path]
    for o, a in pairs(fontPend) do
        if a[1] == path and fontOk(o, use, a[2]) then
            fontPend[o] = nil
            FR.fixed = FR.fixed + 1
            local r = rootOf(o)
            if r then roots[r] = true end
        end
    end
end

-- a test loaded a copy (folder dir) of path: the kit copy ends its tests (file line); a file that had no copy writes its line again
local function found(path, dir)
    if dir == kitDir(path) then
        if fontDone[path] then fileLine(path) else settle(path) end
    elseif fontDone[path] then
        fileLine(path)
    end
end

local function refit(roots)
    for r in pairs(roots) do pcall(Look.Refit, r) end
end

-- FR.out (the file names with no copy in use, sorted) + FR.wait; returns the number of those files
local function setOut()
    local out = {}
    for p in pairs(outPaths()) do out[#out + 1] = fileName(p) end
    table.sort(out)
    FR.out, FR.wait = table.concat(out, ","), waitN()
    return #out
end

-- v4: the folders of the LOADED addons, in the client's order (names from the client at run time)
local function loadedAddons()
    local C = rawget(_G, "C_AddOns")
    local num = (type(C) == "table" and C.GetNumAddOns) or rawget(_G, "GetNumAddOns")
    local info = (type(C) == "table" and C.GetAddOnInfo) or rawget(_G, "GetAddOnInfo")
    local t = {}
    if type(num) ~= "function" or type(info) ~= "function" then return t end
    local ok, n = pcall(num)
    if not ok or type(n) ~= "number" then return t end
    for i = 1, n do
        local ok2, name = pcall(info, i)
        if ok2 and type(name) == "string" and name ~= "" and addonHere(name) then t[#t + 1] = name end
    end
    return t
end

-- v4: one scan step (next frame): at most SCAN_BUDGET copy tests ("fresh" route only), then the next step if the queue has more
local scanNext
local function scanStep()
    scanOn = false
    local roots, n = {}, 0
    while scanQ[scanHead] and n < SCAN_BUDGET do
        local q = scanQ[scanHead]
        scanQ[scanHead] = nil
        scanHead = scanHead + 1
        local path, dir, p = q[1], q[2], q[3]
        if fontScan[path] == "run" and fontUse[path] then fontScan[path] = "done" end     -- a copy in use (this scan found it, or the chain): stop
        if fontScan[path] == "run" then
            n = n + 1
            FR.scan = FR.scan + 1
            local t = fontTried[path]
            if not t then t = { list = {} }; fontTried[path] = t end
            t.extra = (t.extra or 0) + 1
            local s = newString(false)
            if s and fontOk(s, p, 12) then
                fontGood[p] = true
                fontUse[path] = p
                if not fontBest[path] then fontBest[path] = dir end
                fontVia.fresh = true
                FR.via = viaText()
                recover(path, roots)
                found(path, dir)
            end
        end
    end
    refit(roots)
    setOut()
    if scanQ[scanHead] then scanNext() end
end

scanNext = function()
    if scanOn then return end
    local A = after()
    if not A then return end
    scanOn = true
    A(0, scanStep)
end

-- v4: queue the scan of kit path `path` (once per session): each loaded addon folder that is not one of its copies
local function scanStart(path)
    if fontScan[path] then return end
    fontScan[path] = "done"
    local pre, _, rest = path:match("^(.-[Aa][Dd][Dd][Oo][Nn][Ss][\\/])([^\\/]+)([\\/].+)$")
    if not pre then return end
    local seen = {}
    for _, c in ipairs(cands(path)) do seen[c[1]:lower()] = true end
    for _, name in ipairs(loadedAddons()) do
        if not seen[name:lower()] then
            seen[name:lower()] = true
            scanQ[#scanQ + 1] = { path, name, pre .. name .. rest }
            fontScan[path] = "run"
        end
    end
    if fontScan[path] == "run" then scanNext() end
end

local function fontTry(i)
    FR.tries = i
    local roots = {}
    for path in pairs(workPaths()) do
        local wasOut = not fontUse[path]
        local via, dir = better(path, probe)
        if via and via ~= "good" then fontVia[via] = true; FR.via = viaText() end
        if fontUse[path] then recover(path, roots) end
        if dir then found(path, dir) end
        if wasOut then chainOut = true end                    -- real strings had no copy at this try
        if not fontUse[path] and i >= SCAN_TRY and kitDir(path) ~= "-" then scanStart(path) end
    end
    refit(roots)
    local nOut = setOut()
    local A = after()
    if nOut == 0 and next(fontOpen) == nil then
        local late = FR.state == "fail"
        FR.state = "ok"
        if late or chainOut then
            return fontLog(late and "font retry late ok tries=%d fixed=%d via=%s wait=0" or "font retry ok tries=%d fixed=%d via=%s wait=0",
                i, FR.fixed, viaText())
        end
        return
    end
    if A and TRY_AT[i + 1] then
        A(TRY_AT[i + 1] - TRY_AT[i], function() fontTry(i + 1) end)
        return
    end
    for p in pairs(workPaths()) do settle(p) end             -- the last try: each open file writes its line (best folder, or none)
    if nOut == 0 then
        FR.state = "ok"
        if chainOut then fontLog("font retry ok tries=%d fixed=%d via=%s wait=0", i, FR.fixed, viaText()) end
        return
    end
    if FR.state ~= "fail" then
        FR.state = "fail"
        fontLog("font retry fail tries=%d fixed=%d out=%s via=%s wait=%d", i, FR.fixed, FR.out, viaText(), FR.wait)
    end
    if A and FR.late < LATE_MAX then                         -- v2: quiet late tries (the file may load later)
        FR.late = FR.late + 1
        A(LATE_EVERY, function() fontTry(i + 1) end)
    end
end

fontChain = function()
    local st = FR.state
    if st == "wait" or st == "fail" or st == "login" then return end
    local A = after()
    if not A then return end
    if not loggedIn() then
        local CF = rawget(_G, "CreateFrame")
        if type(CF) ~= "function" then return end
        local ok, ev = pcall(CF, "Frame")
        if not ok or type(ev) ~= "table" or type(ev.RegisterEvent) ~= "function" or type(ev.SetScript) ~= "function" then return end
        ev:RegisterEvent("PLAYER_LOGIN")
        ev:SetScript("OnEvent", function(self)
            if type(self.UnregisterEvent) == "function" then self:UnregisterEvent("PLAYER_LOGIN") end
            sawLogin = true
            FR.state = "idle"
            fontChain()
        end)
        FR.state = "login"
        return
    end
    FR.state, FR.tries, FR.fixed, FR.out, FR.via, FR.wait, FR.late = "wait", 0, 0, "", "", 0, 0
    chainOut = false
    for k in pairs(fontVia) do fontVia[k] = nil end
    A(TRY_AT[1], function() fontTry(1) end)
end

-- the path real strings may take for kit path `path` (the kit path or a copy), testing copies when none is proven (each copy at most
-- once per second). nil = no copy loaded: the caller uses the game font. A miss of the kit path opens the path for the chain.
local function proven(path)
    if fontUse[path] then return fontUse[path] end
    if not fontDone[path] then fontOpen[path] = true end
    local via, dir = better(path, testNow)
    if not fontUse[path] then
        fontBad[path] = true
        return nil
    end
    if fontBad[path] then                                    -- it loaded while the chain waits: the waiting objects take it now
        if via ~= "good" then fontVia[via] = true; FR.via = viaText() end
        local roots = {}
        recover(path, roots)
        refit(roots)
    end
    found(path, dir)
    return fontUse[path]
end

function Look.FontSet(o, path, size)
    local use = proven(path)
    if use and fontOk(o, use, size) then
        fontPend[o] = nil
        if fontOpen[path] then fontChain() end
        return true
    end
    local std = rawget(_G, "STANDARD_TEXT_FONT")
    if not ((type(std) == "string" and fontOk(o, std, size)) or fontOk(o, "Fonts\\FRIZQT__.TTF", size)) then
        local gfn = rawget(_G, "GameFontNormal")
        if gfn and type(o.SetFontObject) == "function" then pcall(o.SetFontObject, o, gfn) end
    end
    fontPend[o] = { path, size }
    fontChain()
    return false
end

function Look.Preload()
    for _, p in pairs(Look.fonts) do
        if type(p) == "string" and not fontSeen[p] then
            fontSeen[p] = true
            proven(p)
            if fontOpen[p] or fontBad[p] then fontChain() end
        end
    end
end
-- ==== lead end (font retry)

-- ==== k2a begin: kit round 2 group a: tip line icons (K2-3). K2-2 (silver state) = STATE_NAMES, K2-4 = converter only, K2-7 = Look.TextSize, K2-8 = dialogKeys / Look.Shell. Docs: docs/rollout\kit-k2a.md
-- K2-3  A line entry may carry icon = <texture path or fileID> (L.lines entry, or the per-value table of values[i]; the value one wins; icon = false drops it).
--   GameTooltip (Look.TipLines / Look.TipShow): the left text gets "|T<tex>:0|t " before it (height 0 = the font height).
--   Own tip box (Look.TipBoxShow, 4th arg opt.icons = { [refs name] = texture | false }): a texture the size of the text line sits left of that text
--   (RIGHT of the icon at LEFT of the text, 2 px gap; the box keeps the room for it). A show with no opt.icons hides the icons of the last show.
function K2A.tipIcon(ln, v, l)
    local ic = ln.icon
    if type(v) == "table" and v.icon ~= nil then ic = v.icon end
    if ic == nil or ic == false or ic == "" then return l end
    return "|T" .. tostring(ic) .. ":0|t " .. tostring(l)
end

function K2A.boxIcons(f, refs, icons)
    local pool = f._lookTipIcons
    if not pool then pool = {}; f._lookTipIcons = pool end
    for _, t in pairs(pool) do t:Hide() end
    if type(icons) ~= "table" then return end
    for name, tex in pairs(icons) do
        local x = refs and refs[name]
        local fs = x and (x._lookText or x)
        if fs and tex ~= false and tex ~= "" then
            local t = pool[name]
            if not t then
                local par = (fs.GetParent and fs:GetParent()) or f
                t = par:CreateTexture(nil, "OVERLAY")
                pool[name] = t
            end
            local _, sz = fs:GetFont()
            sz = (type(sz) == "number" and sz > 0) and sz or 12
            t:SetTexture(tex)
            t:SetSize(sz, sz)
            t:ClearAllPoints()
            t:SetPoint("RIGHT", fs, "LEFT", -2, 0)
            t:Show()
        end
    end
end
-- ==== k2a end


-- ==== k2b begin: kit round 2 group b: K2-1 fold under a row ancestor (converter + Look.FoldInfo), K2-5 Look.RowIndent, K2-6 natural height (Look.NaturalHeight, the grip minimum),
-- K2-9 data-keep (Look.Pages, small edit in section wave3-a), K2-10 Look.GrowGroup (small edits in wave3-a GrowList: opt.free + the group hook; wave3-e Relayout: refs._relaySeq).
-- Docs: docs\rollout\kit-k2b.md

-- K2-1: the size of a fold block now (read only): { open, head, body, block } in UI units. body = the height the body needs, also while it is closed (the glue sums these
-- for an accordion: keep one block open when the column does not fit). A closed body keeps the height its rows gave it.
function Look.FoldInfo(refs, id)
    local b = refs and refs[id]
    local fd = b and b._lookFold
    if not fd then error("Look.FoldInfo: " .. tostring(id) .. " is not a fold block built by L.build", 2) end
    return { open = fd.open, head = fd.head:GetHeight(), body = fd.body:GetHeight(), block = b:GetHeight() }
end

-- K2-5: Look.RowIndent(rowRefs, px): indent the content of a list row by px (0 = none). rowRefs = the refs of one row (the `r` of the fill callback).
-- The kids of the row root that hang on its LEFT edge move right by the change, the ones on the right edge stay, a fill text gets narrower. The row background and
-- its border edges do not move. Idempotent: the same px again changes nothing; call it in every fill (rows are reused: 0 clears an old indent).
function Look.RowIndent(rowRefs, px)
    local root = rowRefs and rowRefs.root
    if not root then error("Look.RowIndent: rowRefs is the refs of one row (it has no root)", 2) end
    px = tonumber(px) or 0
    if px < 0 then px = 0 end
    local old = root._lookIndent or 0
    if px == old then return end
    local d = px - old
    root._lookIndent = px
    if root._look and root._look.dyn then      -- a column row: Look.Reflow reads _lookIndent
        Look.Reflow(root)
        return
    end
    local skip = { [root] = true }
    if root._lookBg then skip[root._lookBg] = true end
    for _, t in pairs(root._lookEdges or {}) do skip[t] = true end
    local objs = rowRefs._o or {}
    for i = 1, #objs do
        local o = objs[i]
        if not skip[o] and o.GetNumPoints then
            local n = o:GetNumPoints()
            local pts, moved = {}, false
            for k = 1, n do
                local p, rel, rp, x, y = o:GetPoint(k)
                if rel == root and p and p:find("LEFT", 1, true) then x = (x or 0) + d; moved = true end
                pts[k] = { p, rel, rp, x, y }
            end
            if moved then
                o:ClearAllPoints()
                for k = 1, n do local q = pts[k]; o:SetPoint(q[1], q[2], q[3], q[4], q[5]) end
            end
        end
    end
end

-- K2-6: the least height a window can have: what its rows need (a window that follows its rows), else the height the converter made. Look.Restore never goes below it,
-- and the grip minimum is this value, set again after every refill of a list (Look.GrowList / Look.Pages / Look.Relayout / Look.Flush).
function Look.NaturalHeight(f)
    local m = f and f._look
    if m and m.autoH then return m.natH or f:GetHeight() end
    local rs = f and f._lookRs
    return rs and rs.h or (f and f:GetHeight())
end

-- K2-10: Look.GrowGroup(refs, items, gopt): fill SEVERAL data-fold="edge" grow lists of one window together, from ONE height budget.
--   items = { { info, n, fill, opt }, ... }  (info = L.lists[i], n / fill / opt as in Look.GrowList; opt.weight = a number, default 1)
--   gopt  = { margin = UI units kept free above the screen bottom, noRefit = true to skip the final refit (call Look.Flush yourself) }
--   returns { ls1, ls2, ... } in the order of items. The lists stack in one column; the topmost one gives the budget top.
-- Budget B = the room for all list boxes together: every list is laid out empty first (so each one counts for nothing), then B = the room from the top of the topmost
-- list to the screen bottom (laEdgeFree, or the tab body for a bound list) minus everything that sits below it. Split:
--   1. all rows fit (sum of the needs <= B): every list shows everything, no fold.
--   2. else each list first gets a floor = its fold row + one row (or its whole need, if that is smaller), in the order of items (the first item is served first);
--      a list that finds no room left still gets its fold row (the "+N" row is never dropped, so the window can run past B by that much).
--   3. the rest of B is split between the lists that still want more, by opt.weight (water filling: a list that needs less than its share takes only its need, the
--      surplus goes to the others). A list that gets less than its need folds: the rows that fit, then "+N".
-- The glue steers with the ORDER of items (floors), opt.weight (the share of the contested room) and opt.margin / gopt.margin.
-- After a group call, Look.GrowList(refs, info, ...) on a member updates that member and runs the whole group again; ls.Refresh and a window resize (Look.Relayout)
-- refresh the group once. Not for open lists (a count label) and not for lists side by side (the budget is vertical).
local function gpTop(refs, items)
    local best, bt
    for i = 1, #items do
        local c = refs[items[i].info.wow]
        local t = c:GetTop()
        if type(t) == "number" and (not bt or t > bt) then best, bt = c, t end
    end
    return best
end

local function gpRun(g)
    local refs, items = g.refs, g.items
    g.running = true
    local ok, err = pcall(function()
        local cs, sts = {}, {}
        for i = 1, #items do
            local it = items[i]
            cs[i] = laList(refs, it.info, "GrowGroup")
            sts[i] = laPool(cs[i], it.info)
            cs[i]._look.kids = {}          -- every list empty: the budget is what is left for all of them
        end
        local root = refs.root
        local top = laTop(cs[1])
        Look.Refit(top)
        local B
        local margin = g.gopt.margin or (items[1].opt and items[1].opt.margin) or 0
        local tc = gpTop(refs, items) or cs[1]
        if items[1].info.bound then B = krBoundFree(tc, (items[1].info.pane and refs._o and refs._o[items[1].info.pane]) or root) else B = laEdgeFree(tc, margin) end
        local need, floor, w, alloc, fh = {}, {}, {}, {}, {}
        for i = 1, #items do
            local it, c, st = items[i], cs[i], sts[i]
            local info = it.info
            local kinds, cnt = laKinds(info, it.n, "GrowGroup")
            local gap = c._look.gap or 0
            local hc = {}
            local total, h1 = 0, 0
            if cnt > 0 then
                for q = 1, cnt do
                    local h = laRowH(c, st, info, kinds and kinds[q] or info.row, hc)
                    if q == 1 then h1 = h end
                    total = total + h + (q > 1 and gap or 0)
                end
            elseif info.empty then
                total = laRowH(c, st, info, info.empty, hc)
            end
            need[i] = total
            fh[i] = info.fold and laRowH(c, st, info, info.fold, hc) or 0
            floor[i] = (cnt > 0) and math.min(total, fh[i] + gap + h1) or total
            w[i] = tonumber(it.opt and it.opt.weight) or 1
            if w[i] < 0 then w[i] = 0 end
        end
        if B == nil then
            for i = 1, #items do alloc[i] = nil end      -- not laid out yet: no fold (as a single list)
        else
            local sum = 0
            for i = 1, #items do sum = sum + need[i] end
            if sum <= B + 0.001 then
                for i = 1, #items do alloc[i] = need[i] end
            else
                local R = B
                for i = 1, #items do
                    local b0 = math.min(floor[i], math.max(R, 0))
                    if b0 < floor[i] then b0 = math.min(floor[i], math.max(b0, fh[i])) end
                    alloc[i] = b0
                    R = math.max(0, R - b0)
                end
                local active = {}
                for i = 1, #items do if need[i] - alloc[i] > 0.001 then active[#active + 1] = i end end
                while #active > 0 and R > 0.001 do
                    local sw = 0
                    for _, i in ipairs(active) do sw = sw + w[i] end
                    if sw <= 0 then break end
                    local took, rest = false, {}
                    for _, i in ipairs(active) do
                        local share = R * w[i] / sw
                        local want = need[i] - alloc[i]
                        if want <= share + 0.001 then
                            alloc[i] = need[i]
                            R = R - want
                            took = true
                        else
                            rest[#rest + 1] = i
                        end
                    end
                    if not took then
                        for _, i in ipairs(rest) do alloc[i] = alloc[i] + R * w[i] / sw end
                        break
                    end
                    active = rest
                end
            end
        end
        g.alloc, g.need, g.budget = alloc, need, B
        for i = 1, #items do
            local it = items[i]
            local o = {}
            for k, v in pairs(it.opt or {}) do o[k] = v end
            o.noRefit = true
            o.free = alloc[i]
            g.ls[i] = Look.GrowList(refs, it.info, it.n, it.fill, o)
        end
        for i = 1, #items do
            local c = cs[i]
            c._laGroup = g
            c._lookRefresh = g.refresh
            g.ls[i].Refresh = g.refresh
        end
        if not g.gopt.noRefit then
            Look.Refit(top)
            if top._lookRs and Look.Bounds then Look.Bounds(top) end
        end
    end)
    g.running = false
    if not ok then error(err, 0) end
    return g.ls
end

function Look.GrowGroup(refs, items, gopt)
    if type(items) ~= "table" or #items < 1 then error("Look.GrowGroup: items = { { info, n, fill, opt }, ... }", 2) end
    local g = { refs = refs, items = {}, gopt = gopt or {}, ls = {} }
    for i = 1, #items do
        local it = items[i]
        local info = it.info or it[1]
        if not info then error("Look.GrowGroup: item " .. i .. " has no info (an entry of L.lists)", 2) end
        if not info.edge then error("Look.GrowGroup: the list " .. tostring(info.wow) .. " is not a data-fold=\"edge\" list", 2) end
        if info.label ~= nil then error("Look.GrowGroup: the list " .. tostring(info.wow) .. " is an open list (count label); it grows with the window and has no share", 2) end
        local c = laList(refs, info, "GrowGroup")
        if c._laGroup and c._laGroup.refs == refs then c._laGroup = nil end      -- a new group replaces the old one
        g.items[i] = { info = info, n = it.n or it[2], fill = it.fill or it[3], opt = it.opt or it[4] or {} }
    end
    g.refresh = function()
        local seq = refs._relaySeq
        if refs.root._lookRelaying and seq and g.seq == seq then return end      -- already done in this Look.Relayout pass
        g.seq = seq
        return gpRun(g)
    end
    g.call = function(c, n, fill, opt)
        for i = 1, #g.items do
            if refs[g.items[i].info.wow] == c then
                g.items[i].n, g.items[i].fill, g.items[i].opt = n, fill, opt or {}
                g.seq = nil
                local ls = gpRun(g)
                return ls[i]
            end
        end
    end
    return gpRun(g)
end
-- ==== k2b end

-- ==== k2e begin: kit round 2 group e: K2-19 a grow list shares a column with a flex pages list (converter: screen_fillcol.py). Docs: docs/rollout\kit-k2e.md
-- Look.K2eFill(f, m, e, gap)   called by Look.Reflow for a dyn column f that holds a fill kid e (km.fill = true, km.minH = the floor): e takes the height of f
--   minus every other shown kid (height + margins), the gaps and the padding, never below minH. A new height pages the list again (its ls.Refresh), once, not inside itself.
-- Look.K2eBound(c, root)       the free height of a bound grow list c (tab body root) when some column on the way up holds a fill kid: that kid counts at its floor
--   (minH), not at the height it has now, so the grow list gets what is left after the floor of the pages list. -> value, true; nil, false = no fill kid on the way (krBoundFree goes on).
function Look.K2eFill(f, m, e, gap)
    local H = f:GetHeight()
    if type(H) ~= "number" then return end
    local used, n = (m.t or 0) + (m.b or 0), 0
    for i = 1, #m.kids do
        local k = m.kids[i]
        if k.obj and k.obj:IsShown() then
            n = n + 1
            used = used + (k.m.mt or 0) + (k.m.mb or 0)
            if k ~= e then used = used + k.obj:GetHeight() end
        end
    end
    if n > 1 then used = used + (n - 1) * gap end
    local h = H - used
    local floor = e.m.minH or 0
    if h < floor then h = floor end
    local o = e.obj
    local prev = o._k2eH
    o._k2eH = h
    o:SetHeight(h)
    if prev and math.abs(prev - h) > 0.01 and o._lookRefresh and not f._k2eBusy then
        f._k2eBusy = true
        local ok, err = pcall(o._lookRefresh)
        f._k2eBusy = nil
        if not ok then error(err, 0) end
    end
end

function Look.K2eBound(c, root)
    local above, below, any = 0, 0, false
    local child = c
    while child and child ~= root do
        local p = child._lookParent
        local m = p and p._look
        if not m or not m.kids then return nil, false end
        local gap = m.gap or 0
        local found = false
        above = above + (m.t or 0)
        below = below + (m.b or 0)
        for i = 1, #m.kids do
            local e = m.kids[i]
            local o = e.obj
            if o == child then
                found = true
                above = above + (e.m.mt or 0)
                below = below + (e.m.mb or 0)
            elseif o and o:IsShown() then
                local h
                if e.m.fill then any = true; h = e.m.minH or 0 else h = o:GetHeight() end
                local d = gap + (e.m.mt or 0) + h + (e.m.mb or 0)
                if found then below = below + d else above = above + d end
            end
        end
        if not found then return nil, false end
        child = p
    end
    if not any then return nil, false end
    return root:GetHeight() - above - below, true
end
-- ==== k2e end

-- ==== w3cols begin: flex table columns (K3-4: a wider window gives cut columns their natural width). Docs: docs\rollout\kit-w3cols.md
--  A table = a list (grow / pages) under a column head row. The converter writes L.lists[i].cols (convert\screen_cols.py): per column the head cell and the
--  row cells (o indexes), flex = true for the Item column, cols.w = the list box width in the HTML. The converted cell widths are the MINIMUM.
--  Look.ColsFit(c) runs at the end of every list fill / page turn / Look.Relayout refresh (laStack): the window is wider than cols.w by `extra`;
--    1. the flex (Item) column grows up to its natural width, 2. each other column whose text is cut grows up to its natural width, left to right,
--    3. what is left stays with the flex column (anchors do that). A narrower window gives the width back in the reverse order (each fit starts from the minimum).
--  A cell's width = cell:GetWidth(); it is set ONLY here (SetWidth, header cell and row cells of a column get the same growth). cell._wcMin = the converted width,
--  cell._wcW = the width set last. Natural width = widest text of the column (the head text incl. its sort glyph room, the shown rows) x the font factor (Look.ColsFactor) + the
--  chrome of the cell (a tag: its l + r padding; a text next to a sort glyph: the glyph room). A tag in a changed cell is fitted again (Look.Tag).
--   Look.ColsFactor([x])         the 'is it cut' factor (game text is wider than the sandbox estimate; per font: Lato 1.12, Barlow 1.06, DejaVu 1.06): x = a text -> its factor;
--                                a number 1..2 sets one factor for every font (tests); false clears it; no arg -> the current one (1.06 when per font)
--   Look.has.flexCols = true     feature flag for glue (the lists fit their columns themselves)
--   Look.ColsInfo(refs, info)    the last fit of a list: { extra, base, gItem, giv (what the flex column took), left, cols = { { head = cell, min, w, need (head), want (the growth the texts ask for), grow, cut, members } } } or nil (no cols)
local WC_OVER                                         -- a number set by Look.ColsFactor(n) wins over the per font factors
local WC_FONT = { lato = 1.12, barlow = 1.06, dejavu = 1.06 }      -- measured in the game (w3diag): game text width / sandbox estimate
local function wcFac(fs)
    if WC_OVER then return WC_OVER end
    local ok, path = pcall(fs.GetFont, fs)
    path = ok and type(path) == "string" and path:lower() or ""
    for k, v in pairs(WC_FONT) do
        if path:find(k, 1, true) then return v end
    end
    return 1.06
end
function Look.ColsFactor(x)
    if type(x) == "table" then return wcFac(x._lookText or x) end      -- a text: the factor for its font
    if x == false then WC_OVER = nil
    elseif x ~= nil then
        if type(x) ~= "number" or x < 1 or x > 2 then error("Look.ColsFactor: a number from 1 to 2, false, or a text", 2) end
        WC_OVER = x
    end
    return WC_OVER or 1.06
end
Look.has = Look.has or {}
Look.has.flexCols = true      -- glue feature flag: the lists fit their columns by themselves

local function wcIsFs(x) return x.GetObjectType and x:GetObjectType() == "FontString" end
local function wcFitMeta(f)
    local m = f._look
    return m and m.fitW and m.text and m
end

-- first sight of a cell: its converted width and the texts that decide its natural width. -> min width or nil
local function wcSee(x)
    if x._wcMin then return x._wcMin end
    local w = x:GetWidth()
    if type(w) ~= "number" or w <= 0 then return nil end
    local mem = {}
    if wcIsFs(x) then
        mem[1] = { fs = x, chrome = 0 }
    else
        if wcFitMeta(x) then mem[#mem + 1] = { tag = x } end
        local regs = x.GetRegions and { x:GetRegions() } or {}
        for i = 1, #regs do
            local r = regs[i]
            if wcIsFs(r) and r:GetNumPoints() >= 2 then      -- a text that follows the cell width (one anchor = a glyph with its own width)
                local rw = r:GetWidth()
                local ch = type(rw) == "number" and (w - rw) or 0
                mem[#mem + 1] = { fs = r, chrome = ch > 0 and ch or 0 }
            end
        end
        local kids = x._lookFrames
        if kids then
            for i = 1, #kids do
                if wcFitMeta(kids[i]) then mem[#mem + 1] = { tag = kids[i] } end
            end
        end
    end
    x._wcMin, x._wcMem = w, mem
    return w
end

-- the width the cell needs for its text now (nil: no text shown)
local function wcNeed(x)
    local mem = x._wcMem
    if not mem then return nil end
    local need
    for i = 1, #mem do
        local e = mem[i]
        local n
        if e.tag then
            local m = e.tag._look
            if m and m.text and e.tag:IsShown() then n = m.text:GetStringWidth() * wcFac(m.text) + (m.l or 0) + (m.r or 0) end
        else
            local t = e.fs:GetText()
            if t ~= nil and t ~= "" and e.fs:IsShown() then n = e.fs:GetStringWidth() * wcFac(e.fs) + e.chrome end
        end
        if n and (not need or n > need) then need = n end
    end
    return need and math.ceil(need - 0.001) or nil
end

local function wcSet(x, w)
    if (x._wcW or x._wcMin) == w then return end
    x._wcW = w
    x:SetWidth(w)
    local kids = x._lookFrames
    if kids then
        for i = 1, #kids do
            if wcFitMeta(kids[i]) then Look.Tag(kids[i]) end      -- a tag follows its cell (the cap at the cell width is in Look.FitW / Look.Tag)
        end
    end
end

function Look.ColsFit(c)
    local st = c._laPool
    local ls = st and st.ls
    local info = ls and ls.info
    local cols = info and info.cols
    local o = ls and ls.refs and ls.refs._o
    if not (cols and o) then return end
    local W = c:GetWidth()
    if type(W) ~= "number" or W <= 0 then return end
    if not st.wcBase then st.wcBase = cols.w or W end      -- no converter width: the first width seen is the base
    local extra = math.max(0, W - st.wcBase)
    local rows = {}
    for i = 1, #(ls.items or {}) do
        local row = ls.items[i]
        if row.refs and row.refs._o and row.root:IsShown() then rows[#rows + 1] = row end
    end
    -- the columns: C.head = the head cell, C.members = the row cells { cell, k (place in the column), row (index in rows) }
    local list, flexC = {}, nil
    for _, col in ipairs(cols) do
        local hc = o[col.h]
        if hc and wcSee(hc) then
            local C = { col = col, head = hc, members = {}, K = 0 }
            for ri = 1, #rows do
                local ids = col.r[rows[ri].kind]
                local ro = rows[ri].refs._o
                if ids then
                    for k = 1, #ids do
                        local cell = ro[ids[k]]
                        if cell and wcSee(cell) then
                            C.members[#C.members + 1] = { cell = cell, k = k, row = ri }
                            if k > C.K then C.K = k end
                        end
                    end
                end
            end
            if col.flex then flexC = C else list[#list + 1] = C end
        end
    end
    -- what each row / the head has grown by now (cell._wcW - min): the width of the flex cell at the minimum is its width now plus that
    local function grownRow(ri)
        local s = 0
        for _, C in ipairs(list) do
            for _, m in ipairs(C.members) do
                if m.row == ri then s = s + ((m.cell._wcW or m.cell._wcMin) - m.cell._wcMin) end
            end
        end
        return s
    end
    local grownHead = 0
    for _, C in ipairs(list) do grownHead = grownHead + ((C.head._wcW or C.head._wcMin) - C.head._wcMin) end
    -- 1. the flex column
    local gItem = 0
    if flexC then
        local nh = wcNeed(flexC.head)
        if nh then
            local bw = flexC.head:GetWidth() + grownHead - extra
            if nh - bw > gItem then gItem = nh - bw end
        end
        for _, m in ipairs(flexC.members) do
            local n = wcNeed(m.cell)
            if n then
                local bw = m.cell:GetWidth() + grownRow(m.row) - extra
                if n - bw > gItem then gItem = n - bw end
            end
        end
    end
    local left = extra
    local giv = math.min(left, math.max(0, gItem))
    left = left - giv
    -- 2. the other columns, left to right
    local state = { extra = extra, base = st.wcBase, gItem = gItem, cols = {} }
    for _, C in ipairs(list) do
        local gm = {}
        for k = 1, math.max(C.K, 1) do gm[k] = 0 end
        for _, m in ipairs(C.members) do
            local n = wcNeed(m.cell)
            if n then
                local g = n - m.cell._wcMin
                if g > gm[m.k] then gm[m.k] = g end
            end
        end
        local sum = 0
        for k = 1, #gm do sum = sum + gm[k] end
        local nh = wcNeed(C.head)
        local gh = nh and (nh - C.head._wcMin) or 0
        if gh > sum then gm[#gm] = gm[#gm] + (gh - sum); sum = gh end
        local take, tot = {}, 0
        for k = 1, #gm do
            local t = math.min(left, math.max(0, gm[k]))
            take[k] = t
            left = left - t
            tot = tot + t
        end
        C.take, C.tot = take, tot
        state.cols[#state.cols + 1] = { head = C.head, min = C.head._wcMin, w = C.head._wcMin + tot, need = nh, grow = tot, want = sum, cut = sum > 0, members = C.members }
    end
    state.left = left
    state.giv = giv
    -- apply: the same growth in the head cell and in the row cells of the column
    for _, C in ipairs(list) do
        wcSet(C.head, C.head._wcMin + C.tot)
        for _, m in ipairs(C.members) do wcSet(m.cell, m.cell._wcMin + (C.take[m.k] or 0)) end
    end
    c._wcState = state
end

function Look.ColsInfo(refs, info)
    local c = refs and info and refs[info.wow]
    return c and c._wcState or nil
end
-- ==== w3cols end
-- ==== w3kit begin: K3-1 hair edges = one screen pixel, K3-2 row close-up (RowFlow), K3-3 cap of an auto-width box at its cell. Docs: docs\rollout\kit-w3kit.md
--  Look.HairRefresh(f)   size every hair edge at or below f again (a frame whose scale changed outside the kit; the kit calls it by itself on UI_SCALE_CHANGED,
--                        DISPLAY_SIZE_CHANGED, Look.ScaleFrame and the first OnShow of a screen root)
--  Look.RowFlow(row, geo, items)   the converter's call for a flex row (see convert\screen_rowflow.py): the shown children close up, like display: none
local K3 = { hair = setmetatable({}, { __mode = "k" }) }
Look._w3kit = K3
Look.has = Look.has or {}      -- feature flags for the glue (other sections add their own)
Look.has.rowCloseUp, Look.has.hairPx, Look.has.tagCap = true, true, true

local function k3Phys()      -- physical screen height in pixels, or nil
    local fn = rawget(_G, "GetPhysicalScreenSize")
    if type(fn) == "function" then
        local ok, _, h = pcall(fn)
        if ok and type(h) == "number" and h > 0 then return h end
    end
    local get = rawget(_G, "GetCVar")
    if type(get) ~= "function" then
        local cv = rawget(_G, "C_CVar")
        get = type(cv) == "table" and cv.GetCVar or nil
    end
    if type(get) == "function" then
        local ok, win = pcall(get, "gxWindow")
        local names = (ok and win == "1") and { "gxWindowedResolution", "gxFullscreenResolution" } or { "gxFullscreenResolution", "gxWindowedResolution" }
        for i = 1, 2 do
            local ok2, v = pcall(get, names[i])
            local h = ok2 and type(v) == "string" and tonumber(v:match("%d+[xX](%d+)"))
            if h and h > 0 then return h end
        end
    end
    return nil
end

-- one screen pixel in the units of f (768 = the height of the UI at scale 1); nil = cannot tell (the converter width stays)
local function k3Pixel(f)
    local ph = k3Phys()
    if not ph then return nil end
    if not f.GetEffectiveScale then return nil end
    local ok, e = pcall(f.GetEffectiveScale, f)
    if not ok or type(e) ~= "number" or e <= 0 then return nil end
    return 768 / (ph * e)
end
K3.pixel = k3Pixel

local function k3IsHair(w) return type(w) == "number" and w > 0 and w < 1 end

local function k3Place(f, r, px)
    local w = r.hair and px or r.w
    local wt = r.wtHair and px or r.wt
    local wb = r.wbHair and px or r.wb
    local t = r.tex
    if r.side == "top" or r.side == "bottom" then
        if r.hair then t:SetHeight(w) end
        return
    end
    if r.hair then t:SetWidth(w) end
    if r.lt ~= wt or r.lb ~= wb then
        r.lt, r.lb = wt, wb
        t:ClearAllPoints()
        if r.side == "left" then
            t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -wt)
            t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, wb)
        else
            t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -wt)
            t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, wb)
        end
    end
end

local function k3Apply(f)
    local rs = f._lookHairs
    if not rs then return end
    local px = k3Pixel(f)
    if not px or f._lookHairPx == px then return end
    f._lookHairPx = px
    for i = 1, #rs do k3Place(f, rs[i], px) end
end

function Look.HairRefresh(f)
    if not f then return end
    k3Apply(f)
    local list = f._lookFrames
    if list then
        for i = 1, #list do Look.HairRefresh(list[i]) end
    end
end

local function k3All()
    for f in pairs(K3.hair) do k3Apply(f) end
end

local function k3Setup(f)
    if not K3.ev and type(CreateFrame) == "function" then
        local ok, ev = pcall(CreateFrame, "Frame")
        if ok and ev and ev.RegisterEvent then
            K3.ev = ev
            pcall(function()
                ev:RegisterEvent("UI_SCALE_CHANGED")
                ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
                ev:SetScript("OnEvent", function() k3All() end)
            end)
        end
    end
    local root = f
    while root._lookParent and root._lookParent._lookFrames do root = root._lookParent end
    if not root._lookHairHook and root.HookScript then      -- the glue may scale a window after it is built: look again when it shows
        root._lookHairHook = true
        pcall(root.HookScript, root, "OnShow", function(self) Look.HairRefresh(self) end)
    end
end

-- called by Look.Edge for every edge it makes; hair = true / false / nil (nil: a width under 1 is a hair)
function K3.edge(f, t, side, w, wt, wb, hair)
    local isHair = hair
    if isHair == nil then isHair = k3IsHair(w) end
    if not isHair and not k3IsHair(wt) and not k3IsHair(wb) then return end
    local rs = f._lookHairs
    if not rs then rs = {}; f._lookHairs = rs end
    rs[#rs + 1] = { tex = t, side = side, w = w, wt = wt, wb = wb, hair = isHair and true or false,
                    wtHair = hair ~= false and k3IsHair(wt), wbHair = hair ~= false and k3IsHair(wb), lt = wt, lb = wb }
    if not K3.hair[f] then K3.hair[f] = true; k3Setup(f) end
    f._lookHairPx = nil
    k3Apply(f)
end

-- ---------------------------------------------------------------- K3-2: row close-up
--  geo = { l, r, t, gap } (inner insets of the row, the gap); items = { { obj, side "L"|"F"|"R", ml, mr, top }, ... } in DOM order.
--  Left children chain from the left, right children from the right, the fill (F) stretches between the two groups. A child that is hidden
--  (Hide, SetShown(false)) leaves the chain with its margins and gap, like display: none. Nothing happens while every child is shown.
--  An EMPTY WRAPPER counts as hidden too: a shown frame that draws nothing itself (no bg, no edges, no text of its own) and has kids that are all hidden
--  (a margin box around a tag whose tag is hidden). The wrapper is not touched (no Hide / SetAlpha); it only leaves the chain. A wrapper with no kids stays shown.
--  A box that takes the mouse (IsMouseEnabled) is never an empty wrapper.
--  The Show / Hide / SetShown of those kids are hooked too, so a kid that comes or goes flows the row again.
local function k3Kids(o)      -- the kids of a wrapper: child frames + regions that are not its own bg / edge textures; nil when o is not a wrapper candidate
    if o._lookBg or o._lookText then return nil end
    local okg, getKids = pcall(function() return o.GetChildren end)      -- a FontString / Texture has none (a strict fake errors on the lookup)
    if not okg or not getKids then return nil end
    if o._lookEdges and next(o._lookEdges) then return nil end
    local okm, mouse = pcall(function() return o:IsMouseEnabled() end)      -- a box that takes the mouse stays: left at its old place it would catch the clicks of the neighbour that moves in
    if okm and mouse then return nil end
    local kids = {}
    local ok, res = pcall(function() return { o:GetChildren() } end)
    if not ok then return nil end
    for i = 1, #res do kids[#kids + 1] = res[i] end
    local ok2, rs = pcall(function() return { o:GetRegions() } end)
    if ok2 then for i = 1, #rs do kids[#kids + 1] = rs[i] end end
    return kids
end

local function k3Shown(o)
    if not o:IsShown() then return false end
    local kids = k3Kids(o)
    if kids and #kids > 0 then
        for i = 1, #kids do
            local ok, sh = pcall(kids[i].IsShown, kids[i])
            if not ok or sh then return true end
        end
        return false
    end
    return true
end

local function k3Flow(row)
    local fl = row._lookFlow
    if not fl or fl.busy then return end
    local items, geo = fl.items, fl.geo
    local sig = {}
    for i = 1, #items do sig[i] = k3Shown(items[i][1]) and "1" or "0" end
    sig = table.concat(sig)
    if sig == fl.sig then return end
    local lock = rawget(_G, "InCombatLockdown")
    if type(lock) == "function" and lock() then
        for i = 1, #items do
            local o = items[i][1]
            if o.IsProtected and o:IsProtected() then K3.pend = K3.pend or {}; K3.pend[row] = true; return end
        end
    end
    fl.busy = true
    fl.sig = sig
    local gap = geo.gap or 0
    local prev
    for i = 1, #items do
        local e = items[i]
        if e[2] == "L" and k3Shown(e[1]) then
            e[1]:ClearAllPoints()
            if prev then e[1]:SetPoint("TOPLEFT", prev[1], "TOPRIGHT", prev[4] + gap + e[3], -(e[5] - prev[5]))
            else e[1]:SetPoint("TOPLEFT", row, "TOPLEFT", geo.l + e[3], -(geo.t + e[5])) end
            prev = e
        end
    end
    local lastL = prev
    local nxt
    for i = #items, 1, -1 do
        local e = items[i]
        if e[2] == "R" and k3Shown(e[1]) then
            e[1]:ClearAllPoints()
            if nxt then e[1]:SetPoint("TOPRIGHT", nxt[1], "TOPLEFT", -(nxt[3] + gap + e[4]), -(e[5] - nxt[5]))
            else e[1]:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(geo.r + e[4]), -(geo.t + e[5])) end
            nxt = e
        end
    end
    local firstR = nxt
    for i = 1, #items do
        local e = items[i]
        if e[2] == "F" and k3Shown(e[1]) then
            e[1]:ClearAllPoints()
            if lastL then e[1]:SetPoint("TOPLEFT", lastL[1], "TOPRIGHT", lastL[4] + gap + e[3], -(e[5] - lastL[5]))
            else e[1]:SetPoint("TOPLEFT", row, "TOPLEFT", geo.l + e[3], -(geo.t + e[5])) end
            if firstR then e[1]:SetPoint("TOPRIGHT", firstR[1], "TOPLEFT", -(firstR[3] + gap + e[4]), -(e[5] - firstR[5]))
            else e[1]:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(geo.r + e[4]), -(geo.t + e[5])) end
        end
    end
    fl.busy = nil
end

function Look.RowFlow(row, geo, items)
    local fl = { geo = geo, items = items }
    row._lookFlow = fl
    local sig = {}
    for i = 1, #items do sig[i] = "1" end
    fl.sig = table.concat(sig)      -- the build leaves every child shown: no re-anchor until one changes
    local hook = function() k3Flow(row) end
    for i = 1, #items do
        local o = items[i][1]
        for _, name in ipairs({ "Show", "Hide", "SetShown" }) do
            if o[name] then pcall(hooksecurefunc, o, name, hook) end
        end
        local kids = k3Kids(o)
        if kids then
            for j = 1, #kids do
                for _, name in ipairs({ "Show", "Hide", "SetShown" }) do
                    if kids[j][name] then pcall(hooksecurefunc, kids[j], name, hook) end
                end
            end
        end
    end
    k3Flow(row)
    if not K3.regen and type(CreateFrame) == "function" then
        local ok, ev = pcall(CreateFrame, "Frame")
        if ok and ev and ev.RegisterEvent then
            K3.regen = ev
            pcall(function()
                ev:RegisterEvent("PLAYER_REGEN_ENABLED")
                ev:SetScript("OnEvent", function()
                    local p = K3.pend
                    K3.pend = nil
                    if p then for r in pairs(p) do k3Flow(r) end end
                end)
            end)
        end
    end
end

-- ---------------------------------------------------------------- K3-3: an auto-width box never grows past its cell
--  Called by Look.FitW for a fitW box: w = the width FitW worked out. Returns the width to use. The cell = the parent's CURRENT width (read at every call, and
--  again when the parent changes its size), minus the box's left offset and the parent's right inset. A text that does not fit is cut with "..." by the game.
local function k3Text(f, m)      -- the text that the width of f follows: its own (a text box) or the one text kid of a row; chrome = what the box adds
    if m.text then return f._lookText, m.l + m.r end
    local only
    for i = 1, #m.kids do
        local e = m.kids[i]
        if e.obj then
            if only or not (e.m.txt and not e.m.fw) then return nil end
            only = e
        end
    end
    if not only then return nil end
    return only.obj, m.l + m.r + (only.m.ml or 0) + (only.m.mr or 0)
end

local function k3Room(f, p)
    local ok, pw = pcall(p.GetWidth, p)
    if not ok or type(pw) ~= "number" or pw < 4 then return nil end
    local ox = 0
    if not f.GetPoint then return nil end
    local pt, rel, _, x = f:GetPoint(1)
    if pt == "TOPLEFT" and rel == p and type(x) == "number" then ox = x end
    local right = (p._look and p._look.r) or 0
    local room = pw - ox - right
    if room < 4 then return nil end
    return room
end

function K3.cap(f, m, w)
    local p = f._lookParent
    if not p or not p.GetWidth or (p._look and p._look.fitW) then return w end
    local fs, chrome = k3Text(f, m)
    if not fs or not fs.GetStringWidth then return w end
    if not f._lookCapHook and p.HookScript then
        f._lookCapHook = true
        pcall(p.HookScript, p, "OnSizeChanged", function() if f._look and f._look.fitW then Look.FitW(f) end end)
    end
    if fs._lookCut then fs:SetWidth(0) end      -- measure the whole text, not the cut one
    local want = fs:GetStringWidth() + chrome
    local room = k3Room(f, p)
    if room and want > room + 0.01 then
        local tw = max(1, room - chrome)
        fs._lookMaxW = tw
        fs._lookCut = true
        fs:SetWidth(tw)
        return room
    end
    if fs._lookCut then
        fs._lookCut = nil
        fs._lookMaxW = nil
        fs:SetWidth(0)
        return want
    end
    return w
end
-- ==== w3kit end

return Look
