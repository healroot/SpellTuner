-- UI/Tip.lua (T76, P32 of docs/PLAN-refactor-ux.md; review A21, U2, U13, U28,
-- U10's mechanism): the one tooltip line model and the one renderer, on both
-- main TOCs. Until T76 this lived in UI/Tooltip.lua, which the Forever main
-- TOC did not list (only the Replay module did) and which was mostly TBC
-- content; the RankMath-bound builders (Mana, Fights, Row, Spell, Damage,
-- Columns, Clock) are now UI/Tip_TBC.lua's, on the TBC TOC only.
--
-- A line is a plain table:
--   { l = "left", r = "right", c = colour, rc = colour, wrap = bool }
-- l alone -> AddLine, l+r -> AddDoubleLine, {} -> a blank spacer. A colour is
-- an {r, g, b} array or a token name ("label", "muted", "mana": UI.TEXT's,
-- read at render time, so the theme's values are the ones painted); nil is
-- white. Both GameTooltip and ElvUI's DT.tooltip take exactly those two calls,
-- which is why the pair is the abstraction.
--
-- Where a tooltip goes (per call):
--   Tip:Show(owner, lines, { anchor = "beside" | "cursor" | "ANCHOR_*", x, y })
--     "beside": TOPLEFT at the owner's TOPRIGHT + GAP, or, when that runs off
--       the screen's right edge, TOPRIGHT at its TOPLEFT - GAP (docs/SPEC-
--       forever-ui.md 3.5; moved here from UI/SpellsPane_Forever.lua's Place).
--     "cursor": the same beside the pointer for an owner wider than WIDE (a
--       Review row: beside its far edge was off the screen, U28), beside the
--       owner otherwise.
--     "ANCHOR_*": the game's own anchor, through SetOwner.
--   Tip:Show(owner, anchor, lines, ...) -- the old shape, kept for its
--     callers: on TBC exactly what it always did; under UI.THEMED an
--     ANCHOR_RIGHT / ANCHOR_CURSOR is placed "cursor".
--
-- One skin (U2). Tip:Show renders into GameTooltip on both lines -- the
-- game's own spell tooltip on a rank row needs GameTooltip (whether the Spell
-- post-call fires for SetSpellByID on another tooltip is not verified on
-- Forever), and so does every hover a suite reads. Under UI.THEMED the
-- GameTooltip SpellTuner owns is drawn in the kit tooltip's skin (Tip:Skin:
-- a flat fill and 1-px edges over the game's NineSlice), taken off again when
-- it hides or another owner clears it. The kit tooltip itself (UI.tooltip,
-- SpellTunerTooltip: UI.SetTooltips, the Spells pane's gap rows) is Tip:Kit,
-- in the same skin. On TBC nothing is skinned: GameTooltip keeps its look.
--
-- ASCII only in every string here (default WoW fonts lack arrow/infinity
-- glyphs) and never a bare "|" (it opens a colour escape).
local _, MD = ...
local UI = MD.UI

local Tip = MD.Tip or {}
MD.Tip = Tip

Tip.GAP = 6     -- a placed tooltip's distance from its owner (3.5's +6)
Tip.WIDE = 300  -- an owner wider than this is placed beside the pointer

local WHITE = { 1, 1, 1 }

-- A colour: an {r, g, b} array as it is, a token name through UI.RGB, nil nil.
function Tip.Color(c)
    if type(c) == "string" then return { UI.RGB(c) } end
    if type(c) == "table" then return c end
    return nil
end
local Color = Tip.Color

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------
-- Pushes lines into any tooltip object exposing AddLine / AddDoubleLine.
-- A bare string is a line of its own.
function Tip:Render(tt, lines)
    if not tt or not lines then return end
    for i = 1, #lines do
        local ln = lines[i]
        if type(ln) == "string" then ln = { l = ln } end
        if type(ln) ~= "table" or (ln.l == nil and ln.r == nil) then
            tt:AddLine(" ")
        elseif ln.r ~= nil then
            local c = Color(ln.c) or WHITE
            local rc = Color(ln.rc) or Color(ln.c) or WHITE
            tt:AddDoubleLine(ln.l or "", ln.r, c[1], c[2], c[3], rc[1], rc[2], rc[3])
        else
            local c = Color(ln.c) or WHITE
            tt:AddLine(ln.l, c[1], c[2], c[3], ln.wrap)
        end
    end
end

-- The kit tooltip's shape from a title and its lines (UI.SetTooltips' and the
-- Spells pane's): the title in `text`, every string after it in `text2`,
-- wrapped; a table after it is a line of its own (a muted hint, a pair), so a
-- caller is no longer limited to white (U13). A nil is skipped.
function Tip.Simple(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for i = 1, #list do
        local v = list[i]
        if type(v) == "table" then
            out[#out + 1] = v
        elseif v ~= nil then
            if i == 1 then
                out[#out + 1] = { l = tostring(v), c = "text" }
            else
                out[#out + 1] = { l = tostring(v), c = "text2", wrap = true }
            end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Placement
--------------------------------------------------------------------------------
local function Num(v) return type(v) == "number" end

local function Scale(frame)
    if frame and frame.GetEffectiveScale then
        local ok, s = pcall(frame.GetEffectiveScale, frame)
        if ok and Num(s) and s > 0 then return s end
    end
    return 1
end

-- The pointer's x in the owner's own units from the owner's left edge, or nil
-- (no pointer reading, no left edge).
local function CursorX(owner)
    if type(GetCursorPosition) ~= "function" then return nil end
    local cx = GetCursorPosition()
    local left = owner.GetLeft and owner:GetLeft()
    if not (Num(cx) and Num(left)) then return nil end
    local x = cx / Scale(owner) - left
    local w = owner.GetWidth and owner:GetWidth()
    if x < 0 then x = 0 end
    if Num(w) and x > w then x = w end
    return x, cx
end

-- Tip:Place(tt, owner, anchor): "beside" or "cursor" (above). The tooltip's
-- own width decides the flip, so call it after the lines are in and the
-- tooltip is shown.
function Tip:Place(tt, owner, anchor)
    tt:ClearAllPoints()
    local gap = Tip.GAP
    local screen, w = UIParent:GetRight(), tt:GetWidth()
    local rs, us, ts = Scale(owner), Scale(UIParent), Scale(tt)
    if anchor == "cursor" then
        local ow = owner.GetWidth and owner:GetWidth()
        if Num(ow) and ow > Tip.WIDE then
            local x, cx = CursorX(owner)
            if x then
                local flip = false
                if Num(screen) and Num(w) then
                    flip = cx + gap * rs + w * ts > screen * us
                end
                -- A point's offset is in the tooltip's own units, the
                -- pointer's x in the owner's: they differ whenever the owner
                -- carries a scale the tooltip does not (the main window at
                -- db.ui.scale, GameTooltip at the UI's).
                local off = x * rs / ts
                if flip then
                    tt:SetPoint("TOPRIGHT", owner, "TOPLEFT", off - gap, 0)
                else
                    tt:SetPoint("TOPLEFT", owner, "TOPLEFT", off + gap, 0)
                end
                return "cursor", flip
            end
        end
    end
    local flip = false
    local right = owner:GetRight()
    if Num(right) and Num(screen) and Num(w) then
        flip = (right + gap) * rs + w * ts > screen * us
    end
    if flip then
        tt:SetPoint("TOPRIGHT", owner, "TOPLEFT", -gap, 0)
    else
        tt:SetPoint("TOPLEFT", owner, "TOPRIGHT", gap, 0)
    end
    return "beside", flip
end

local function Placed(anchor) return anchor == "beside" or anchor == "cursor" end

--------------------------------------------------------------------------------
-- The skin (U2): the kit tooltip's flat fill and 1-px edges on a game tooltip
-- SpellTuner owns, under UI.THEMED only. Textures on the tooltip itself, in
-- its BACKGROUND layer, under its text; the game's NineSlice faded out while
-- the skin is on and given back its alpha when it comes off.
--------------------------------------------------------------------------------
local function LayoutSkin(tt, s)
    local e = UI.px and UI.px(1, tt) or 1
    local t, b, l, r = s.edges[1], s.edges[2], s.edges[3], s.edges[4]
    t:ClearAllPoints(); t:SetPoint("TOPLEFT", tt, "TOPLEFT", 0, 0); t:SetPoint("TOPRIGHT", tt, "TOPRIGHT", 0, 0)
    t:SetHeight(e)
    b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", tt, "BOTTOMLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", tt, "BOTTOMRIGHT", 0, 0)
    b:SetHeight(e)
    l:ClearAllPoints(); l:SetPoint("TOPLEFT", tt, "TOPLEFT", 0, 0); l:SetPoint("BOTTOMLEFT", tt, "BOTTOMLEFT", 0, 0)
    l:SetWidth(e)
    r:ClearAllPoints(); r:SetPoint("TOPRIGHT", tt, "TOPRIGHT", 0, 0); r:SetPoint("BOTTOMRIGHT", tt, "BOTTOMRIGHT", 0, 0)
    r:SetWidth(e)
end

local function EnsureSkin(tt)
    local s = tt._stSkin
    if s then return s end
    s = { on = false, edges = {} }
    s.bg = tt:CreateTexture(nil, "BACKGROUND", nil, -8)
    s.bg:SetAllPoints(tt)
    for i = 1, 4 do s.edges[i] = tt:CreateTexture(nil, "BACKGROUND", nil, -7) end
    tt._stSkin = s
    if tt.HookScript then
        tt:HookScript("OnHide", function(self) Tip:Unskin(self) end)
        -- another owner's showing clears the tooltip first: the skin comes
        -- off unless the clear is SpellTuner's own refresh of the same owner
        tt:HookScript("OnTooltipCleared", function(self)
            local sk = self._stSkin
            if not (sk and sk.on) then return end
            local owner = self.GetOwner and self:GetOwner()
            if owner == nil or owner ~= sk.owner then Tip:Unskin(self) end
        end)
    end
    return s
end

-- Tip:Skin(tt, owner): the kit skin on `tt` while `owner` has it. Under
-- UI.THEMED only; answers whether it is on.
function Tip:Skin(tt, owner)
    if not (UI.THEMED and tt and tt.CreateTexture) then return false end
    local ok = pcall(function()
        local s = EnsureSkin(tt)
        s.bg:SetColorTexture(UI.Fill("tip"))
        local br, bgc, bb, ba = UI.Fill("border")
        for _, e in ipairs(s.edges) do e:SetColorTexture(br, bgc, bb, ba) end
        LayoutSkin(tt, s)
        s.bg:Show()
        for _, e in ipairs(s.edges) do e:Show() end
        if type(tt.NineSlice) == "table" and not s.on then
            s.nineAlpha = tt.NineSlice:GetAlpha()
            tt.NineSlice:SetAlpha(0)
        end
        s.owner, s.on = owner, true
    end)
    return ok and tt._stSkin ~= nil and tt._stSkin.on == true
end

function Tip:Unskin(tt)
    local s = tt and tt._stSkin
    if not (s and s.on) then return end
    s.on, s.owner = false, nil
    pcall(function()
        s.bg:Hide()
        for _, e in ipairs(s.edges) do e:Hide() end
        if type(tt.NineSlice) == "table" then tt.NineSlice:SetAlpha(Num(s.nineAlpha) and s.nineAlpha or 1) end
    end)
end

function Tip:Skinned(tt)
    local s = tt and tt._stSkin
    return s ~= nil and s.on == true
end

--------------------------------------------------------------------------------
-- Show
--------------------------------------------------------------------------------
-- The old shape: Tip:Show(frame, "ANCHOR_LEFT", lines, lines2, ...).
local function ShowLegacy(owner, anchor, ...)
    local tt = GameTooltip
    if UI.THEMED and (anchor == nil or anchor == "ANCHOR_RIGHT" or anchor == "ANCHOR_CURSOR") then
        tt:SetOwner(owner, "ANCHOR_NONE")
        tt:ClearLines()
        for i = 1, select("#", ...) do
            Tip:Render(tt, (select(i, ...)))
        end
        Tip:Skin(tt, owner)
        tt:Show()
        Tip:Place(tt, owner, "cursor")
        return
    end
    tt:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    tt:ClearLines()
    for i = 1, select("#", ...) do
        Tip:Render(tt, (select(i, ...)))
    end
    Tip:Skin(tt, owner)
    tt:Show()
end

-- Tip:Show(owner, lines, opts) -- opts.anchor ("beside" by default), opts.x /
-- opts.y for a game anchor's offset. Answers the tooltip it rendered into.
function Tip:Show(owner, lines, ...)
    if type(lines) ~= "table" then
        ShowLegacy(owner, lines, ...)
        return GameTooltip
    end
    local opts = (...)
    if type(opts) ~= "table" then opts = {} end
    local anchor = opts.anchor or "beside"
    local tt = GameTooltip
    if Placed(anchor) then
        tt:SetOwner(owner, "ANCHOR_NONE")
    else
        tt:SetOwner(owner, anchor, opts.x or 0, opts.y or 0)
    end
    tt:ClearLines()
    Tip:Render(tt, lines)
    Tip:Skin(tt, owner)
    tt:Show()
    if Placed(anchor) then Tip:Place(tt, owner, anchor) end
    return tt
end

-- Pinned to a frame instead of following the owner: the dashboard's rows are
-- narrow and centred, so ANCHOR_RIGHT would run off the screen edge.
function Tip:ShowAt(owner, point, relFrame, relPoint, x, y, ...)
    local tt = GameTooltip
    tt:SetOwner(owner, "ANCHOR_NONE")
    tt:ClearAllPoints()
    tt:SetPoint(point, relFrame, relPoint, x, y)
    tt:ClearLines()
    for i = 1, select("#", ...) do
        Tip:Render(tt, (select(i, ...)))
    end
    Tip:Skin(tt, owner)
    tt:Show()
end

function Tip:Hide()
    GameTooltip:Hide()
end

-- The kit tooltip (UI.tooltip): the same lines, placed the same ways, for the
-- kit's own controls (UI.SetTooltips) and the Spells pane's reasons. opts as
-- Tip:Show's; anchor "ANCHOR_TOP" by default. Answers the tooltip, or nil.
function Tip:Kit(owner, lines, opts)
    local tt = UI.tooltip
    if not tt then return nil end
    opts = opts or {}
    local anchor = opts.anchor or "ANCHOR_TOP"
    if Placed(anchor) then
        tt:SetOwner(owner, "ANCHOR_NONE")
    else
        tt:SetOwner(owner, anchor, opts.x or 0, opts.y or 0)
    end
    Tip:Render(tt, lines)
    tt:Show()
    if Placed(anchor) then Tip:Place(tt, owner, anchor) end
    return tt
end
