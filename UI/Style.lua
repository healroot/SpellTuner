-- Widget kit in the style of Cell's options UI (flat 0.115-grey panels with a
-- 1px black border, class-colour accent, 13px widget font, tab buttons that
-- sit on the top edge of the frame). Written from scratch for SpellTuner: no
-- libraries, no pixel-perfect layer, plain sizes. Exposed on MD.UI and used
-- by the options frame, the debug console and the dashboard.
local _, MD = ...

local UI = {}
MD.UI = UI

--------------------------------------------------------------------------------
-- T77 (P33 of docs/PLAN-refactor-ux.md, review A31): the kit's two events,
-- through the kernel's pub/sub (MD:RegisterCallback / MD:Fire), so a pane and
-- the window manager subscribe instead of wrapping a kit function or
-- assigning a kit hook.
--
--   "UI_POPUP" (list, shown)  a popup list (a dropdown's list, a tree's
--       second list, a right-click menu) was shown (true) or hidden (false).
--       UI.Popup(list, shown) announces one; UI.OnPopup is the same function,
--       kept under its old name for the callers that announce through it
--       (UI/ContextMenu.lua). Nobody assigns it any more.
--   "FONTS_CHANGED" (offset)  UI.ApplyFonts ran: every kit font is re-sized
--       to the offset it answers. ApplyFonts is the theme's (UI/Theme_
--       Forever.lua, Forever only); whatever function is installed under that
--       name is kept as the sizer and called through the kit's own, which
--       fires the event once the fonts are re-sized and answers the sizer's
--       answer. With no sizer installed (TBC) UI.ApplyFonts is nil, as before.
--------------------------------------------------------------------------------
function UI.Popup(list, shown)
    MD:Fire("UI_POPUP", list, shown)
end
UI.OnPopup = UI.Popup

local fontSizer
local function ApplyFontsAndAnnounce(...)
    local offset = fontSizer(...)
    MD:Fire("FONTS_CHANGED", offset)
    return offset
end
setmetatable(UI, {
    __index = function(_, k)
        if k == "ApplyFonts" and fontSizer then return ApplyFontsAndAnnounce end
        return nil
    end,
    __newindex = function(t, k, v)
        if k == "ApplyFonts" then fontSizer = v; return end
        rawset(t, k, v)
    end,
})

local WHITE = "Interface\\Buttons\\WHITE8x8"
UI.whiteTexture = WHITE

--------------------------------------------------------------------------------
-- Colours: accent = class colour (Cell convention)
--------------------------------------------------------------------------------
local accent = { 0.7, 0.7, 0.7 }
local accentHex = "|cffb2b2b2"
do
    -- Client call, through the adapter (T2): UnitClass returns localized,
    -- token (or nil, "<reason>" on failure) -- the token is the SECOND
    -- value, and it is only meaningful when the first came back at all
    -- (same rule as Core.lua's DetectProfile, T1b Review re-issue 2).
    local loc, class = MD.API.UnitClass("player")
    if not loc then class = nil end
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        accent = { c.r, c.g, c.b }
        accentHex = c.colorStr and ("|c" .. c.colorStr)
            or string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
end
UI.accent = accent
UI.accentHex = accentHex
-- T94: the class colour as it was read, kept apart from UI.accent (which a
-- style rewrites in place: UI/Styles.lua), so "class" can be restored exactly.
UI.classAccent = { accent[1], accent[2], accent[3] }
UI.classAccentHex = accentHex
UI.grey = { 0.7, 0.7, 0.7 }
function UI.GetAccentColorRGB() return accent[1], accent[2], accent[3] end

--------------------------------------------------------------------------------
-- T69 (P25, docs/PLAN-refactor-ux.md, review A20): one theme flag, colour
-- tokens always present.
--
-- UI.THEMED is the only "is the Forever look on" test: false here, true once
-- UI/Theme_Forever.lua has run (the Forever TOCs list it right after this
-- file; TBC's does not). A branch that changes a font, a size, a layout or a
-- behaviour asks UI.THEMED; a colour is a token read and never a gate.
--
-- UI.TEXT.<token> = { r, g, b, hex = "|cffrrggbb" }. These are TBC's values:
-- each is the literal the shared files carried before the tokens existed, so
-- TBC paints exactly what it painted. The theme overwrites every key. Tokens
-- no TBC file reads (text2, label, mana, good, bad) carry 4.1's values.
-- Where TBC's files disagreed on one role the extra value is a named legacy
-- token, which the theme maps onto its 4.1 token; unifying them is P34's
-- question to the author:
--   dominated  8a8a8a  the rank table's dominated row (muted is 888888)
--   note       ffcc00  the bindings import's notes, practice's "every <role>" rows
--   tipGold    ffd100  MD.Tip's suggested rank ({1, 0.82, 0}; accent is ffcc00)
-- T74 (P30): one more, the kit's own -- not a legacy token: the theme leaves
-- it, so a disabled control is 0.4 grey on both lines, as it was (4.1's
-- disabled, 4D4D4D, for the kit's controls too is P34's question):
--   dimmed     666666  a disabled check box, slider or edit box (FONT_DISABLE's 0.4)
--------------------------------------------------------------------------------
UI.THEMED = false

local function Token(hex, r, g, b)
    if not r then
        r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
            tonumber(hex:sub(5, 6), 16) / 255
    end
    return { r, g, b, hex = "|cff" .. hex:lower() }
end
UI.Token = Token

UI.TEXT = {
    accent    = Token("ffcc00", 1, 0.8, 0),   -- highlighted words (Review's run line, the replay's header)
    text      = Token("ffffff"),
    text2     = Token("b3b3b3"),              -- no TBC reader: 4.1's value
    label     = Token("9d9d9d"),              -- no TBC reader: 4.1's value
    muted     = Token("888888"),              -- table headers, hints
    disabled  = Token("555555"),              -- a rank not learned
    mana      = Token("4d99ff"),              -- no TBC reader: 4.1's value
    good      = Token("5ccb6e"),              -- no TBC reader: 4.1's value
    bad       = Token("e0605a"),              -- no TBC reader: 4.1's value
    dominated = Token("8a8a8a"),              -- legacy (see above)
    note      = Token("ffcc00", 1, 0.8, 0),   -- legacy
    tipGold   = Token("ffd100", 1, 0.82, 0),  -- legacy
    dimmed    = Token("666666", 0.4, 0.4, 0.4), -- T74: the kit's disabled controls
}

-- A token's colour code, its r, g, b, and a palette fill's r, g, b, a. An
-- unknown name paints white rather than raising into a paint (tools/
-- themecheck.lua scans the tree for names neither table carries).
function UI.Hex(token)
    local t = UI.TEXT[token]
    return t and t.hex or "|cffffffff"
end
function UI.RGB(token)
    local t = UI.TEXT[token]
    if t then return t[1], t[2], t[3] end
    return 1, 1, 1
end
function UI.Fill(key)
    local c = UI.PALETTE[key]
    if c then return c[1], c[2], c[3], c[4] end
    return 1, 1, 1, 1
end

--------------------------------------------------------------------------------
-- T107 (docs/SPEC-next.md 2.2 and section 11's T107 row; R-styles.md 1.3, 6):
-- the live restyle. A style is applied in place (UI/Styles.lua: the palette
-- and the tokens rewritten, every UI.skinned region repainted, STYLE_CHANGED);
-- what that did not reach was a colour COPIED out of a token when a region was
-- made. Two ways now carry a switch to those regions, both on STYLE_CHANGED
-- (registered at the bottom of this file, before any other file's handler):
--
-- 1. UI.Tint(region, how, name, alpha): a region whose colour is a NAME --
--    "accent" (UI.accent), a UI.PALETTE fill or a UI.TEXT token -- is painted
--    through here, which records the name and the setter (weak-keyed: the
--    registry never keeps a region alive) and paints it now; UI.RepaintTints
--    paints every recorded region from its name in the new style. The tint IS
--    the setter: a region whose colour changes later is tinted again (the
--    record follows the last call), and UI.Untint(region) forgets one a caller
--    paints by hand from then on. how / setter:
--      "text"     SetTextColor             "texture"  SetColorTexture
--      "vertex"   SetVertexColor           "border"   SetBackdropBorderColor
--      "backdrop" SetBackdropColor         "bar"      SetStatusBarColor
--    alpha nil passes what the call it replaces passed: a fill's own alpha;
--    for a token or the accent nothing (r, g, b only); a number is passed as
--    the fourth argument.
-- 2. The follow (UI.FollowTokens): every font string under a SpellTuner window
--    (the top frame of every UI.skinned region) that is NOT tinted and whose
--    text colour is a token's colour in the style just left is given that
--    token's colour in the new one; every colour code of such a token inside
--    its text is swapped the same way. A colour two tokens shared that now
--    differ is left alone (which one it was cannot be told), and a subtree
--    marked `restyleExempt` is never entered (the replay's unit frames, the
--    debug console's legend: colours that mean the same under every style,
--    R-styles.md 1.3). This is what reaches the font strings of the panes
--    T107 does not own (Settings, Review's notes, Waste, the Sim window).
--
-- What neither reaches -- a fill copied into a texture, or a code captured in
-- a local, in a file T107 does not own -- is UI.Restyle.LEFT, which the
-- Settings line "finish changing after a reload" counts (UI.Restyle.Left /
-- UI.Restyle.Line); tools/restylecheck.lua measures every entry as left and
-- finds nothing else.
--------------------------------------------------------------------------------
UI.tinted = setmetatable({}, { __mode = "k" })

local TINT_SETTER = {
    text = "SetTextColor", texture = "SetColorTexture", vertex = "SetVertexColor",
    border = "SetBackdropBorderColor", backdrop = "SetBackdropColor", bar = "SetStatusBarColor",
}
UI.TINT_SETTERS = TINT_SETTER

-- A name's colour now: r, g, b and a fill's own alpha (nil for a token or the
-- accent). An unknown name is white, as UI.RGB answers.
local function TintColour(name)
    if name == "accent" then return accent[1], accent[2], accent[3], nil end
    local c = UI.PALETTE and UI.PALETTE[name]
    if c then return c[1], c[2], c[3], c[4] end
    local t = UI.TEXT[name]
    if t then return t[1], t[2], t[3], nil end
    return 1, 1, 1, nil
end
UI.TintColour = TintColour

local function PaintTint(region, how, rec)
    local fn = region[TINT_SETTER[how]]
    if type(fn) ~= "function" then return false end
    local r, g, b, a = TintColour(rec.name)
    if rec.alpha ~= nil then a = rec.alpha elseif how == "text" then a = nil end
    if a == nil then fn(region, r, g, b) else fn(region, r, g, b, a) end
    rec.r, rec.g, rec.b = r, g, b
    return true
end

-- UI.Tint(region, how, name, alpha): paint now, and again on every switch.
function UI.Tint(region, how, name, alpha)
    if region == nil or TINT_SETTER[how] == nil then return end
    local recs = UI.tinted[region]
    if not recs then recs = {}; UI.tinted[region] = recs end
    local rec = { name = name, alpha = alpha }
    recs[how] = rec
    PaintTint(region, how, rec)
end

-- UI.Untint(region, how): forget one setter's name (how nil: every one).
function UI.Untint(region, how)
    if region == nil then return end
    if how == nil then UI.tinted[region] = nil; return end
    local recs = UI.tinted[region]
    if recs then recs[how] = nil end
end

-- UI.RepaintTints() -> how many it painted. A text tint whose font string now
-- shows a colour it did not paint (painted by hand since) is forgotten, not
-- repainted; a texture's colour cannot be read back, so its record is trusted.
local function Far(x, y) return type(x) ~= "number" or type(y) ~= "number" or math.abs(x - y) > 0.002 end
function UI.RepaintTints()
    local n = 0
    for region, recs in pairs(UI.tinted) do
        for how, rec in pairs(recs) do
            local keep = true
            if how == "text" and rec.r and type(region.GetTextColor) == "function" then
                local okC, r, g, b = pcall(region.GetTextColor, region)
                if okC and type(r) == "number" and (Far(r, rec.r) or Far(g, rec.g) or Far(b, rec.b)) then
                    keep = false
                end
            end
            if not keep then
                recs[how] = nil
            elseif pcall(PaintTint, region, how, rec) then
                n = n + 1
            end
        end
    end
    return n
end

-- The follow. `painted` is UI.TEXT as the windows were last painted in, taken
-- at each STYLE_CHANGED (the first, at CORE_LOGIN, comes before any window is
-- built, so it only takes the snapshot).
local painted
local function Snapshot()
    local s = {}
    for k, t in pairs(UI.TEXT) do
        s[k] = { t[1], t[2], t[3], hex = type(t.hex) == "string" and t.hex:lower() or nil }
    end
    return s
end
local function Key3(r, g, b) return string.format("%.3f %.3f %.3f", r, g, b) end

-- old colour -> new colour and old code -> new code for every token that
-- changed; a colour (or a code) two tokens shared that now differ is dropped.
local function Maps(old, new)
    local rgb, hex, clash, clashHex = {}, {}, {}, {}
    for k, o in pairs(old) do
        local nw = new[k]
        if nw then
            local ok, nk = Key3(o[1], o[2], o[3]), Key3(nw[1], nw[2], nw[3])
            local prev = rgb[ok]
            if prev == nil then rgb[ok] = { nw[1], nw[2], nw[3], key = nk }
            elseif prev.key ~= nk then clash[ok] = true end
            if o.hex and nw.hex then
                local ph = hex[o.hex]
                if ph == nil then hex[o.hex] = nw.hex
                elseif ph ~= nw.hex then clashHex[o.hex] = true end
            end
        end
    end
    for k in pairs(clash) do rgb[k] = nil end
    for k in pairs(clashHex) do hex[k] = nil end
    for k, v in pairs(rgb) do if v.key == k then rgb[k] = nil end end
    for k, v in pairs(hex) do if v == k then hex[k] = nil end end
    return rgb, hex
end

-- Every colour code the map names, swapped; an escaped pipe (||c...) is text.
local function SwapCodes(text, hex)
    local changed = false
    local out = text:gsub("(|+)c(%x%x%x%x%x%x%x%x)", function(pipes, code)
        if #pipes % 2 == 0 then return nil end
        local to = hex["|c" .. code:lower()]
        if not to then return nil end
        changed = true
        return pipes:sub(2) .. to
    end)
    return changed and out or nil
end
UI.SwapCodes = SwapCodes

local function IsFontString(r)
    if type(r) ~= "table" or type(r.GetObjectType) ~= "function" then return false end
    local okT, kind = pcall(r.GetObjectType, r)
    return okT and kind == "FontString"
end

local function FollowOne(fs, rgb, hex)
    local moved = false
    local recs = UI.tinted[fs]
    if not (recs and recs.text) and next(rgb) ~= nil and type(fs.GetTextColor) == "function" then
        local okC, r, g, b = pcall(fs.GetTextColor, fs)
        if okC and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            local to = rgb[Key3(r, g, b)]
            if to then fs:SetTextColor(to[1], to[2], to[3]); moved = true end
        end
    end
    if next(hex) ~= nil and type(fs.GetText) == "function" then
        local okT, text = pcall(fs.GetText, fs)
        if okT and not MD.API.IsSecret(text) and type(text) == "string" and text:find("|c", 1, true) then
            local out = SwapCodes(text, hex)
            if out then fs:SetText(out); moved = true end
        end
    end
    return moved
end

local function TopOf(f)
    for _ = 1, 60 do
        local okP, p = pcall(f.GetParent, f)
        if not okP or type(p) ~= "table" or p == UIParent then return f end
        f = p
    end
    return f
end

local function Walk(f, seen, fn)
    if seen[f] or rawget(f, "restyleExempt") then return end
    seen[f] = true
    if type(f.GetRegions) == "function" then
        local okR, regions = pcall(function() return { f:GetRegions() } end)
        if okR then for _, r in ipairs(regions) do fn(r) end end
    end
    if type(f.GetChildren) == "function" then
        local okC, children = pcall(function() return { f:GetChildren() } end)
        if okC then
            for _, c in ipairs(children) do
                if type(c) == "table" then Walk(c, seen, fn) end
            end
        end
    end
end

-- UI.FollowTokens() -> how many font strings it moved.
function UI.FollowTokens()
    local now = Snapshot()
    local old = painted
    painted = now
    if not old then return 0 end
    local rgb, hex = Maps(old, now)
    if next(rgb) == nil and next(hex) == nil then return 0 end
    local tops, seen, n = {}, {}, 0
    for region in pairs(UI.skinned) do
        if type(region) == "table" and type(region.GetParent) == "function" then tops[TopOf(region)] = true end
    end
    for top in pairs(tops) do
        Walk(top, seen, function(r)
            if not seen[r] and IsFontString(r) then
                seen[r] = true
                local okF, moved = pcall(FollowOne, r, rgb, hex)
                if okF and moved then n = n + 1 end
            end
        end)
    end
    return n
end

--------------------------------------------------------------------------------
-- UI.Restyle: what finishes changing only after a reload.
--   UI.Restyle.LEFT  { { pane, label, file, what, sites = { "file:line" } } }:
--       the regions neither way above reaches, by the line that makes them
--       (tools/restylecheck.lua measures each as left, and finds no other)
--   UI.Restyle.Left() -> n, labels      one label per entry, in order
--   UI.Restyle.Line() -> "N windows finish changing after a reload: A, B"
--       for Settings' line beside its Reload button, or nil when n is 0
--------------------------------------------------------------------------------
UI.Restyle = {
    -- T107: nothing is left since the wave N4 integration (Review's rule and
    -- Practice's grey words, the two entries T107 left in files outside its row,
    -- became a tint and reads at paint); a region added here is one a reload finishes
    LEFT = {},
}
function UI.Restyle.Left()
    local labels = {}
    for i, e in ipairs(UI.Restyle.LEFT) do labels[i] = e.label end
    return #labels, labels
end
function UI.Restyle.Line()
    local n, labels = UI.Restyle.Left()
    if n == 0 then return nil end
    return string.format("%d %s finish changing after a reload: %s", n, n == 1 and "window" or "windows",
        table.concat(labels, ", "))
end

--------------------------------------------------------------------------------
-- UI.PALETTE: fills (r, g, b, a). Defined here, before the primitives that read
-- it (T74, P30: it used to sit with the navigation, after them). The theme
-- (UI/Theme_Forever.lua) writes 4.1's fills over these keys in place.
--------------------------------------------------------------------------------
UI.PALETTE = {
    frame  = { 0.1, 0.1, 0.1, 0.9 },      -- the window itself (UI.StylizeFrame's default)
    header = { 0.115, 0.115, 0.115, 1 },  -- the title bar and the nav columns
    pane   = { 0.13, 0.13, 0.13, 1 },     -- a box drawn inside the content area
    border = { 0, 0, 0, 1 },
    -- T69 (P25): the rank table's option fills (UI/Dashboard_Rows.lua), the
    -- literals that file carried; the theme overwrites them with 4.1's.
    rowAlt    = { 1, 1, 1, 0.03 },
    hover     = { accent[1], accent[2], accent[3], 0.12 },
    selected  = { accent[1], accent[2], accent[3], 0.28 },
    suggested = { accent[1], accent[2], accent[3], 0.10 },
    line      = { 0x2A / 255, 0x2A / 255, 0x2A / 255, 1 },
    -- T74 (P30, review A20): the primitives' fills (CreateButton, the check
    -- box, the edit box, the slider, the scroll frame, the movable frame's
    -- header). Each holds the literal the primitive carried, so TBC paints what
    -- it painted; the theme leaves them (its close / closeHover are the same
    -- values, and its nav, which the header follows, is this 0.115), so Forever
    -- does too. Mapping them onto 4.1's fills is the theme's to do (P34).
    button      = { 0.115, 0.115, 0.115, 1 },               -- a kit button, a slider's track
    buttonHover = { 0.23, 0.23, 0.23, 1 },                  -- a plain button's hover
    field       = { 0.115, 0.115, 0.115, 0.9 },             -- an edit box, a check box
    well        = { 0.15, 0.15, 0.15, 0.9 },                -- the copy box's scroll area
    track       = { 0.1, 0.1, 0.1, 0.8 },                   -- a scroll bar
    thumb       = { accent[1], accent[2], accent[3], 0.8 }, -- its thumb
    check       = { accent[1], accent[2], accent[3], 0.7 }, -- a ticked box, a slider's thumb
    checkHover  = { accent[1], accent[2], accent[3], 0.1 }, -- a check box under the pointer
    accentFill  = { accent[1], accent[2], accent[3], 0.3 }, -- "accent" buttons
    accentHover = { accent[1], accent[2], accent[3], 0.6 }, -- "accent-hover" buttons' hover
    close       = { 0.6, 0.1, 0.1, 0.6 },                   -- "red" (the x), as in Cell
    closeHover  = { 0.6, 0.1, 0.1, 1 },
    go          = { 0.1, 0.6, 0.1, 0.6 },                   -- "green"
    goHover     = { 0.1, 0.6, 0.1, 1 },
    info        = { 0, 0.5, 0.8, 1 },                       -- "blue-hover"'s hover
    warn        = { 0.7, 0.7, 0, 1 },                       -- "yellow-hover"'s hover
    clear       = { 0, 0, 0, 0 },                           -- "transparent" / "none"
    -- T76 (P32, review U2): the tooltip's fill -- the kit tooltip's literal,
    -- which UI/Tip.lua's skin also lays on a game tooltip SpellTuner owns
    -- under the theme (its edge is `border` there, the accent on TBC).
    tip         = { 0.1, 0.1, 0.1, 0.9 },
}

--------------------------------------------------------------------------------
-- Fonts (global font objects, like Cell's CELL_FONT_*)
--------------------------------------------------------------------------------
-- T29: every font object the kit builds, by name, so UI/Theme_Forever.lua's
-- UI.ApplyFonts can resize them in place. Nothing on TBC reads it.
UI.fontObjects = {}
local function MakeFont(name, size, r, g, b, face)
    local f = _G[name] or CreateFont(name)
    UI.fontObjects[name] = f
    f:SetFont(face or GameFontNormal:GetFont(), size, "")
    f:SetTextColor(r, g, b, 1)
    f:SetShadowColor(0, 0, 0)
    f:SetShadowOffset(1, -1)
    f:SetJustifyH("CENTER")
    return f
end
UI.FONT_TITLE = "MANADEMON_FONT_TITLE";                 MakeFont(UI.FONT_TITLE, 14, 1, 1, 1)
UI.FONT_TITLE_DISABLE = "MANADEMON_FONT_TITLE_DISABLE"; MakeFont(UI.FONT_TITLE_DISABLE, 14, 0.4, 0.4, 0.4)
UI.FONT = "MANADEMON_FONT";                             MakeFont(UI.FONT, 13, 1, 1, 1)
UI.FONT_DISABLE = "MANADEMON_FONT_DISABLE";             MakeFont(UI.FONT_DISABLE, 13, 0.4, 0.4, 0.4)
UI.FONT_SMALL = "MANADEMON_FONT_SMALL";                 MakeFont(UI.FONT_SMALL, 11, 1, 1, 1)
UI.FONT_SPECIAL = "MANADEMON_FONT_SPECIAL";             MakeFont(UI.FONT_SPECIAL, 12, 1, 1, 1)
UI.FONT_CLASS_TITLE = "MANADEMON_FONT_CLASS_TITLE";     MakeFont(UI.FONT_CLASS_TITLE, 14, accent[1], accent[2], accent[3])
UI.FONT_CLASS = "MANADEMON_FONT_CLASS";                 MakeFont(UI.FONT_CLASS, 13, accent[1], accent[2], accent[3])
-- T75 (P31, review U26): the two number fonts (Arial Narrow: narrow,
-- even-width digits) are the kit's, not the theme's -- they carry no colour,
-- so both lines have them. Additive: every shared caller asks for them behind
-- the theme (`UI.FONT_NUM_SMALL or UI.FONT_SMALL` under UI.THEMED), and a pane
-- adopts them when it is next touched. UI/Theme_Forever.lua re-makes them at
-- the same face and size and resizes them with the offset.
UI.FONT_NUM = "MANADEMON_FONT_NUM";                     MakeFont(UI.FONT_NUM, 13, 1, 1, 1, "Fonts\\ARIALN.TTF")
UI.FONT_NUM_SMALL = "MANADEMON_FONT_NUM_SMALL";         MakeFont(UI.FONT_NUM_SMALL, 11, 1, 1, 1, "Fonts\\ARIALN.TTF")

-- T75 (P31, review U26): one size scale for controls -- a button, a small
-- button, a row and a toolbar (the nav's groups and, under the theme, its
-- view tabs). Additive: a pane adopts these when it is next touched; nothing
-- reads them on TBC.
UI.H = { button = 20, small = 18, row = 20, toolbar = 22 }

-- T75 (P31, review U30): the width a text takes in a font. A button's own font
-- string is measured when it holds that text (the client's), else one hidden
-- measuring string set to the font -- so a width follows the font offset
-- whenever it is asked again, never a character count.
-- A font string anchored inside a button may be cut to the button's width,
-- so its unbounded width is asked first where the client has it.
local measure
local function Natural(fs)
    local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
    if type(w) == "number" and w > 0 then return w end
    w = fs:GetStringWidth()
    if type(w) == "number" and w > 0 then return w end
    return nil
end
function UI.TextWidth(text, font, fs)
    text = text or ""
    if fs and fs.GetText and fs.GetStringWidth and fs:GetText() == text then
        local w = Natural(fs)
        if w then return w end
    end
    if not measure then
        measure = UIParent:CreateFontString(nil, "OVERLAY", font or UI.FONT)
        measure:Hide()
    end
    measure:SetFontObject(font or UI.FONT)
    measure:SetText(text)
    return Natural(measure) or 0
end

--------------------------------------------------------------------------------
-- Tooltip: a private GameTooltip with the flat backdrop. The 2.5.x tooltip
-- template draws a NineSlice and may lack the backdrop mixin, so both are
-- handled defensively; on any failure the stock look is kept.
--------------------------------------------------------------------------------
local tooltip = CreateFrame("GameTooltip", "SpellTunerTooltip", UIParent, "GameTooltipTemplate")
UI.tooltip = tooltip

-- T76 (P32, review U2): under UI.THEMED the kit tooltip wears the skin
-- UI/Tip.lua lays on a game tooltip SpellTuner owns -- the `tip` fill and a
-- 1-px `border` edge at the physical pixel -- so the two read as one; TBC
-- keeps the accent edge it always had. Asked at every showing: this file
-- loads before the theme.
local function StyleTooltip()
    if tooltip.NineSlice then tooltip.NineSlice:SetAlpha(0) end
    if not tooltip.SetBackdrop and BackdropTemplateMixin then
        Mixin(tooltip, BackdropTemplateMixin)
        tooltip:HookScript("OnSizeChanged", tooltip.OnBackdropSizeChanged)
    end
    if tooltip.SetBackdrop then
        if UI.THEMED then
            local e = UI.px(1, tooltip)
            tooltip:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = e,
                insets = { left = e, right = e, top = e, bottom = e } })
            UI.Tint(tooltip, "backdrop", "tip") -- T107
            UI.Tint(tooltip, "border", "border")
            return
        end
        tooltip:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        tooltip:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        UI.Tint(tooltip, "border", "accent", 1) -- T107
    end
end
pcall(StyleTooltip)
tooltip:SetOwner(UIParent, "ANCHOR_NONE")
tooltip:HookScript("OnShow", function() pcall(StyleTooltip) end)
tooltip:HookScript("OnHide", function() tooltip:ClearLines() end)

-- T76 (P32, review U13): under UI.THEMED a widget's tooltip is sugar over
-- UI/Tip.lua's renderer (MD.Tip:Kit) -- the title in `text`, each later
-- string in `text2` and wrapped, a later TABLE a line of its own (a muted
-- hint, a pair: Tip's line model), and the anchor the LATEST UI.SetTooltips
-- call gave (it was frozen at the first). TBC keeps its own path below,
-- byte for byte.
local function ShowTooltips(widget, anchor, x, y, lines)
    if type(lines) ~= "table" or #lines == 0 then
        tooltip:Hide()
        return
    end
    if UI.THEMED and MD.Tip and MD.Tip.Kit then
        local a = widget._tipAnchor
        if a then anchor, x, y = a[1], a[2], a[3] end
        MD.Tip:Kit(widget, MD.Tip.Simple(lines), { anchor = anchor or "ANCHOR_TOP", x = x or 0, y = y or 0 })
        return
    end
    tooltip:SetOwner(widget, anchor or "ANCHOR_TOP", x or 0, y or 0)
    tooltip:AddLine(lines[1])
    for i = 2, #lines do
        local v = lines[i]
        -- T77 (P33): a line table (the rail's hint) gives its text; no TBC
        -- caller passes one
        if type(v) == "table" then v = v.r and ((v.l or "") .. "  " .. v.r) or v.l end
        if v then tooltip:AddLine("|cffffffff" .. v) end
    end
    tooltip:Show()
end

-- UI.SetTooltips(widget, anchor, x, y, title, line2, line3, ...)
function UI.SetTooltips(widget, anchor, x, y, ...)
    if select("#", ...) == 0 or select(1, ...) == nil then return end
    widget._tipAnchor = { anchor, x, y } -- T76: read under the theme only
    if not widget._tooltipsInited then
        widget._tooltipsInited = true
        widget:HookScript("OnEnter", function() ShowTooltips(widget, anchor, x, y, widget.tooltips) end)
        widget:HookScript("OnLeave", function() tooltip:Hide() end)
    end
    widget.tooltips = { ... }
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- T29 (docs/SPEC-forever-ui.md 4.3): pixel-perfect edges, additive. UI.PIXEL is
-- nil unless the theme (UI/Theme_Flat.lua, every main TOC since T80) sets it;
-- a suite that loads this file alone gets the backdrop StylizeFrame always drew.
--
-- UI.px(n, frame): n physical pixels in the frame's own units --
-- n * (768 / physicalHeight) / frame:GetEffectiveScale(). The physical height
-- comes through the adapter (MD.API.PhysicalScreenSize, Forever's binding); with
-- no usable answer (TBC, absent, secret, zero) n is returned unchanged.
--------------------------------------------------------------------------------
function UI.px(n, frame)
    local h
    if MD.API.PhysicalScreenSize then
        -- explicit locals: the adapter answers (w, h) or (nil, "<reason>")
        local w, hh = MD.API.PhysicalScreenSize()
        if type(w) == "number" and type(hh) == "number" and hh > 0 then h = hh end
    end
    if not h then return n end
    frame = frame or UIParent
    local s
    if frame and frame.GetEffectiveScale then
        local ok, v = pcall(frame.GetEffectiveScale, frame)
        if ok and type(v) == "number" and v > 0 then s = v end
    end
    return n * (768 / h) / (s or 1)
end

--------------------------------------------------------------------------------
-- T94 (docs/SPEC-next.md 2.2, S2; R-styles.md 3.3-3.4): the skin registry.
-- A styled region is recorded by its ROLE and the names of what it shows --
-- UI.skinned[region] = { role, fill, edge, kind } -- not by the colours it
-- was given (UI.pixelFrames held those until T94; the name is kept for its
-- readers). `fill` and `edge` are UI.PALETTE keys where the caller handed a
-- palette table (mapped back by UI.PaletteKey), else the literal it handed.
-- Weak-keyed, so the registry never keeps a frame alive (ElvUI's E.frames).
--
-- A role's recipe (its painter, and the fill and edge UI.Skin uses when the
-- caller names none) is the active style's (UI.Styles.Recipe, UI/Styles.lua);
-- with no registry loaded, the pixel painter. A style changes paint only:
-- never a size, an anchor or an inset of the content.
--------------------------------------------------------------------------------
UI.skinned = setmetatable({}, { __mode = "k" })
UI.pixelFrames = UI.skinned -- the old name (T29), the same table

-- T74 (P30, review U3): what is not a backdrop -- a rule, a selection bar, a
-- texture inset inside a px edge, an anchor that overlaps a px edge -- is laid
-- out by a function that reads UI.px, registered here (weak-keyed by the
-- region it lays out) and run again by UI.RestylePixels. Only under
-- UI.PIXEL: on TBC nothing is registered and every size stays the literal.
UI.pixelLayouts = setmetatable({}, { __mode = "k" })

-- UI.PixelLayout(region, fn): run fn(region) now and on every restyle when
-- UI.PIXEL is on; returns nothing. Off, it does nothing at all -- the caller
-- keeps its literal layout.
function UI.PixelLayout(region, fn)
    if not UI.PIXEL then return end
    UI.pixelLayouts[region] = fn
    fn(region)
end

local function PixelBackdrop(frame)
    local e = UI.px(1, frame)
    return { bgFile = WHITE, edgeFile = WHITE, edgeSize = e,
             insets = { left = e, right = e, top = e, bottom = e } }
end

-- The roles a style paints (docs/SPEC-next.md 2.2), and the one a fill implies
-- when a caller does not name one (UI.StylizeFrame's callers).
UI.SKIN_ROLES = { "window", "header", "nav", "pane", "button", "tab", "field", "list", "scroll",
                  "tooltip", "clock", "statusbar", "rule" }
local FILL_ROLE = {
    frame = "window", bg = "window", header = "header", nav = "header", pane = "pane",
    button = "button", buttonHover = "button", accentFill = "button", close = "button", clear = "button",
    field = "field", well = "field", track = "scroll", thumb = "scroll", tip = "tooltip",
}
local DEFAULT_RECIPE = { kind = "pixel", fill = "pane", edge = "border" }

-- UI.PaletteKey(t): the UI.PALETTE key whose table t IS (a caller passed
-- UI.PALETTE.pane), else nil. An alias (frame / bg) answers either name; both
-- name one table.
function UI.PaletteKey(t)
    if type(t) ~= "table" then return nil end
    for k, v in pairs(UI.PALETTE) do
        if rawequal(v, t) then return k end
    end
    return nil
end

-- A colour spec -> an rgba table: a palette key (its table), { ref =
-- "accent", a = n } (the accent at that alpha), or an rgba literal (itself).
local function Colour(spec)
    if type(spec) == "string" then return UI.PALETTE[spec] end
    if type(spec) == "table" and spec.ref == "accent" then
        return { accent[1], accent[2], accent[3], spec.a or 1 }
    end
    if type(spec) == "table" then return spec end
    return nil
end
UI.SkinColour = Colour
-- T107: the accent at an alpha as a colour SPEC (UI.StylizeFrame / UI.Skin
-- keep it as a name, so the skin repaints it in a new style's accent)
function UI.AccentSpec(a) return { ref = "accent", a = a or 1 } end

local function Recipe(role)
    local S = UI.Styles
    local r = S and S.Recipe and S.Recipe(role)
    return r or DEFAULT_RECIPE
end

local function HideStrips(region)
    for _, s in ipairs(region._skinStrips or {}) do s:Hide() end
end

-- The painters (docs/SPEC-next.md 5.2): painter(region, fill, edge), rgba
-- tables. `pixel` is the backdrop StylizeFrame always drew under UI.PIXEL;
-- `strips` lays the fill as a backdrop and the edge as four 1-px textures
-- over it, so the edge's alpha is its own (UI/Tip.lua's skin, EllesmereUI's
-- PP.CreateBorder). A later style adds its painters here by kind.
local function PaintPixel(region, fill, edge)
    HideStrips(region)
    region:SetBackdrop(PixelBackdrop(region))
    region:SetBackdropColor(unpack(fill))
    region:SetBackdropBorderColor(unpack(edge))
end

local function PaintStrips(region, fill, edge)
    region:SetBackdrop({ bgFile = WHITE })
    region:SetBackdropColor(unpack(fill))
    local s = region._skinStrips
    if not s then
        s = {}
        for i = 1, 4 do s[i] = region:CreateTexture(nil, "BORDER", nil, 7) end
        region._skinStrips = s
    end
    local e = UI.px(1, region)
    local top, bottom, left, right = s[1], s[2], s[3], s[4]
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", region, "TOPRIGHT", 0, 0)
    top:SetHeight(e)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(e)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", region, "TOPLEFT", 0, -e)
    left:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", 0, e)
    left:SetWidth(e)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", region, "TOPRIGHT", 0, -e)
    right:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, e)
    right:SetWidth(e)
    for _, t in ipairs(s) do
        t:SetColorTexture(edge[1], edge[2], edge[3], edge[4] or 1)
        t:Show()
    end
end

UI.PAINTERS = { pixel = PaintPixel, strips = PaintStrips }

-- Paint one registered region with its role's recipe. fillSpec / edgeSpec
-- are what it is to show (keys or literals). A recipe's edgeColor replaces
-- the edge while that style is on; rec.edgeByRecipe remembers it, so the
-- next style starts from the region's own edge again.
local function Paint(region, rec, fillSpec, edgeSpec)
    local recipe = Recipe(rec.role)
    local kind = UI.PAINTERS[recipe.kind] and recipe.kind or "pixel"
    local fill = Colour(fillSpec) or Colour(rec.fill) or { 0.1, 0.1, 0.1, 0.9 }
    local edge
    if recipe.edgeColor ~= nil then
        edge = Colour(recipe.edgeColor) or { 0, 0, 0, 1 }
        rec.edgeByRecipe = true
    else
        edge = Colour(edgeSpec) or Colour(rec.edge) or { 0, 0, 0, 1 }
        rec.edgeByRecipe = nil
    end
    rec.kind = kind
    UI.PAINTERS[kind](region, fill, edge)
end

-- A spec as it is stored: a palette table becomes its key.
local function Spec(v)
    if type(v) == "table" and v.ref == nil then return UI.PaletteKey(v) or v end
    return v
end

-- UI.Skin(region, role, fill, edge): register a region by its role and paint
-- it with the active style's recipe for that role. fill / edge are palette
-- keys or tables (a palette table is mapped back to its key; anything else is
-- a literal kept as given); nil takes the recipe's own (`fill` / `edge`).
-- Without UI.PIXEL (the kit loaded without the theme) the old 1-unit
-- backdrop, nothing registered.
function UI.Skin(region, role, fill, edge)
    role = role or "pane"
    local recipe = Recipe(role)
    fill = Spec(fill) or recipe.fill or DEFAULT_RECIPE.fill
    edge = Spec(edge) or recipe.edge or DEFAULT_RECIPE.edge
    if not UI.PIXEL then
        region:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        region:SetBackdropColor(unpack(Colour(fill) or { 0.1, 0.1, 0.1, 0.9 }))
        region:SetBackdropBorderColor(unpack(Colour(edge) or { 0, 0, 0, 1 }))
        return
    end
    local rec = { role = role, fill = fill, edge = edge }
    UI.skinned[region] = rec
    Paint(region, rec, fill, edge)
end

-- T94: StylizeFrame keeps its signature (13 callers outside the kit) and
-- registers by role -- the role its fill implies (a literal fill: a pane).
function UI.StylizeFrame(frame, color, borderColor)
    if UI.PIXEL then
        local fill = color and Spec(color) or { 0.1, 0.1, 0.1, 0.9 }
        local edge = borderColor and Spec(borderColor) or "border"
        UI.Skin(frame, type(fill) == "string" and FILL_ROLE[fill] or "pane", fill, edge)
        return
    end
    color = Colour(color) or { 0.1, 0.1, 0.1, 0.9 }
    borderColor = Colour(borderColor) or { 0, 0, 0, 1 } -- T107: a spec ({ ref = "accent" }) resolved
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(unpack(color))
    frame:SetBackdropBorderColor(unpack(borderColor))
end

-- What a registered region shows now, by name: its fill as the key it was
-- given, or the key of its hover colour, or `selected` (a button group's
-- active button) when it shows one of those, else the literal it shows (a
-- colour set by hand); its edge likewise against its own edge. Read BEFORE
-- the palette is rewritten, so the next style paints the same names.
local function Same(c, r, g, b, a)
    if type(c) ~= "table" or type(r) ~= "number" then return false end
    local function eq(x, y) return math.abs((x or 1) - (y or 1)) < 1e-6 end
    return eq(c[1], r) and eq(c[2], g) and eq(c[3], b) and eq(c[4], a)
end
local function Showing(region, rec)
    local fill, edge = rec.fill, rec.edge
    local r, g, b, a
    if region.GetBackdropColor then r, g, b, a = region:GetBackdropColor() end
    if type(r) == "number" then
        fill = nil
        local cands = { rec.fill, region.hoverColor and UI.PaletteKey(region.hoverColor) or false, "selected" }
        for i = 1, 3 do
            local c = cands[i]
            if c and Same(Colour(c), r, g, b, a) then fill = c; break end
        end
        fill = fill or { r, g, b, a }
    end
    if not rec.edgeByRecipe and rec.kind == "pixel" and region.GetBackdropBorderColor then
        local er, eg, eb, ea = region:GetBackdropBorderColor()
        if type(er) == "number" and not Same(Colour(rec.edge), er, eg, eb, ea) then
            edge = { er, eg, eb, ea }
        end
    end
    return fill, edge
end

-- UI.CaptureSkins() -> what every registered region shows, by name.
-- UI.RepaintSkins(captured) paints each region with its role's recipe in the
-- style now active (captured nil: its own fill and edge), then re-runs every
-- pixel layout; answers how many regions and layouts it painted. UI.SetStyle
-- (UI/Styles.lua) captures, rewrites the palette, repaints.
function UI.CaptureSkins()
    local out = {}
    for region, rec in pairs(UI.skinned) do
        local okS, fill, edge = pcall(Showing, region, rec)
        if okS then out[region] = { fill = fill, edge = edge } end
    end
    return out
end

function UI.RepaintSkins(captured)
    local n = 0
    for region, rec in pairs(UI.skinned) do
        local c = captured and captured[region]
        if pcall(Paint, region, rec, c and c.fill or rec.fill, c and c.edge or rec.edge) then n = n + 1 end
    end
    for region, fn in pairs(UI.pixelLayouts) do -- T74 (P30)
        if pcall(fn, region) then n = n + 1 end
    end
    return n
end

-- UI.px is evaluated when a frame is styled, so a UI scale or display change
-- leaves stale edges: re-apply the edge and insets to every registered frame,
-- keeping the colours it shows now (a hover may have changed them since). The
-- window manager calls it on UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED and after
-- db.ui.scale changes. Returns how many frames it restyled, plus (T74) how
-- many registered layouts it re-ran. T94: the registry's repaint, each region
-- with what it shows now.
function UI.RestylePixels()
    return UI.RepaintSkins(UI.CaptureSkins())
end

function UI.CreateFrame(name, parent, width, height, isTransparent)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:Hide()
    if not isTransparent then UI.StylizeFrame(f) end
    f:EnableMouse(true)
    if width and height then f:SetSize(width, height) end
    return f
end

-- T75 (P31, review U14): the flat resize grip, under the theme -- three 1-px
-- diagonal lines in the corner of the 16x16 hit area (the mockups' grip),
-- each from (-d - 2, 2) to (-2, d + 2) off the grip's bottom-right corner for
-- d = 4, 8, 12; the `muted` grey, the accent under the pointer. A line is the
-- client's Line region (CreateLine: start, end, a UI.px(1) thickness) where
-- the frame makes one, else a texture one pixel high turned 45 degrees about
-- the same centre. Re-laid by UI.RestylePixels. grip.lines holds them.
local GRIP_STEPS = { 4, 8, 12 }
local function GripLine(grip, d)
    local line = grip.CreateLine and grip:CreateLine(nil, "OVERLAY")
    local Lay
    if line and line.SetStartPoint and line.SetEndPoint then
        line.kind = "line"
        Lay = function(l)
            if l.SetThickness then l:SetThickness(UI.px(1, grip)) end
            l:SetStartPoint("BOTTOMRIGHT", grip, -l.step - 2, 2)
            l:SetEndPoint("BOTTOMRIGHT", grip, -2, l.step + 2)
        end
    else
        line = grip:CreateTexture(nil, "OVERLAY")
        line.kind = "texture"
        Lay = function(t)
            t:SetSize(t.step * 1.41421356, UI.px(1, grip))
            t:ClearAllPoints()
            t:SetPoint("CENTER", grip, "BOTTOMRIGHT", -t.step / 2 - 2, t.step / 2 + 2)
            if t.SetRotation then t:SetRotation(math.pi / 4) end
        end
    end
    line.step = d
    return line, Lay
end
function UI.FlatGrip(grip)
    grip.lines = {}
    for i, d in ipairs(GRIP_STEPS) do
        local line, Lay = GripLine(grip, d)
        UI.Tint(line, "texture", "muted", 1) -- T107: the token, not its colour now
        grip.lines[i] = line
        Lay(line)
        UI.PixelLayout(line, Lay)
    end
    local function Tint(token)
        for _, t in ipairs(grip.lines) do UI.Tint(t, "texture", token, 1) end
    end
    grip:SetScript("OnEnter", function() Tint("accent") end)
    grip:SetScript("OnLeave", function() Tint("muted") end)
end

-- Frame with a 20px header bar above it (title in class colour, red x).
-- T32: opts (additive; TBC never passes it) -- opts.resizable adds a 16x16 grip
-- at the bottom-right corner (SetResizable, StartSizing); its mouse-up calls
-- f:OnResized() when set, as a drag's end calls f:OnMoved(). The bounds are the
-- caller's (the window manager sets each group's minimum).
function UI.CreateMovableFrame(title, name, width, height, strata, level, notUserPlaced, opts)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetUserPlaced(not notUserPlaced)
    f:SetFrameStrata(strata or "HIGH")
    f:SetFrameLevel(level or 1)
    f:SetClampedToScreen(true)
    f:SetClampRectInsets(0, 0, 20, 0)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:Hide()
    UI.StylizeFrame(f)

    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.header = header
    header:EnableMouse(true)
    header:SetClampedToScreen(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        f:StartMoving()
        if notUserPlaced then f:SetUserPlaced(false) end
    end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if f.OnMoved then f:OnMoved() end
    end)
    header:SetPoint("LEFT")
    header:SetPoint("RIGHT")
    header:SetPoint("BOTTOM", f, "TOP", 0, -1)
    -- T74 (P30): the header overlaps the window's edge by one pixel, not one unit
    UI.PixelLayout(header, function(h) h:SetPoint("BOTTOM", f, "TOP", 0, -UI.px(1, h)) end)
    header:SetHeight(20)
    UI.Skin(header, "header", UI.PALETTE.header, "border") -- T74: the token (0.115 on both lines); T94: by role

    header.text = header:CreateFontString(nil, "OVERLAY", UI.FONT_CLASS_TITLE)
    header.text:SetText(title)
    header.text:SetPoint("CENTER", header)

    header.closeBtn = UI.CreateButton(header, "x", "red", { 20, 20 }, false, false, UI.FONT_SPECIAL, UI.FONT_SPECIAL)
    header.closeBtn:SetPoint("TOPRIGHT")
    header.closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- T34 (docs/SPEC-forever-ui.md 6.3): opts.back (a label, or true for
    -- "< Back") adds a back button at the header's left, 84x20, hidden until
    -- the window manager shows it; a click calls f:OnBack() when set.
    if opts and opts.back then
        local label = type(opts.back) == "string" and opts.back or "< Back"
        header.backBtn = UI.CreateButton(header, label, "accent-hover", { 84, 20 })
        header.backBtn:SetPoint("TOPLEFT")
        header.backBtn:SetScript("OnClick", function() if f.OnBack then f:OnBack() end end)
        header.backBtn:Hide()
    end

    -- T75 (P31, review U31): under the theme the title sits between the back
    -- button and the x -- centred on the header while there is no back button
    -- (the same 20 + 4 kept clear on each side), centred on what is left once
    -- the back button shows, never under either; one line, cut rather than
    -- wrapped. TBC keeps the title centred on the whole header.
    if UI.THEMED then
        local fs = header.text
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        local function LayTitle()
            local back = header.backBtn
            local left = (back and back:IsShown()) and back:GetWidth() or header.closeBtn:GetWidth()
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", header, "LEFT", left + 4, 0)
            fs:SetPoint("RIGHT", header.closeBtn, "LEFT", -4, 0)
        end
        header.LayTitle = LayTitle
        LayTitle()
        if header.backBtn then
            header.backBtn:HookScript("OnShow", LayTitle)
            header.backBtn:HookScript("OnHide", LayTitle)
        end
    end

    if opts and opts.resizable then -- T32
        f:SetResizable(true)
        local grip = CreateFrame("Button", nil, f)
        f.resizeGrip = grip
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        grip:SetFrameLevel(f:GetFrameLevel() + 20)
        if UI.THEMED then
            UI.FlatGrip(grip)
        else
            grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
            grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
            grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        end
        grip:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            f:StartSizing("BOTTOMRIGHT")
            if notUserPlaced then f:SetUserPlaced(false) end
        end)
        grip:SetScript("OnMouseUp", function()
            f:StopMovingOrSizing()
            if notUserPlaced then f:SetUserPlaced(false) end
            if f.OnResized then f:OnResized() end
        end)
    end

    return f
end

-- T107: with no colour given, the accent as a name (it follows a style)
function UI.CreateSeparator(text, parent, width, color)
    width = width or parent:GetWidth() - 10

    local fs = parent:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    fs:SetJustifyH("LEFT")
    if color then fs:SetTextColor(color[1], color[2], color[3]) else UI.Tint(fs, "text", "accent") end
    fs:SetText(text)

    local line = parent:CreateTexture()
    line:SetSize(width, 1)
    if color then line:SetColorTexture(unpack(color)) else UI.Tint(line, "texture", "accent", 0.777) end
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
    local shadow = parent:CreateTexture()
    shadow:SetSize(width, 1)
    UI.Tint(shadow, "texture", "border")
    shadow:SetPoint("TOPLEFT", line, "TOPLEFT", 1, -1)
    -- T74 (P30, review U3): the rule and its shadow one pixel thick
    UI.PixelLayout(line, function(l) l:SetHeight(UI.px(1, l)) end)
    UI.PixelLayout(shadow, function(sh)
        local e = UI.px(1, sh)
        sh:SetHeight(e)
        sh:SetPoint("TOPLEFT", line, "TOPLEFT", e, -e)
    end)
    return fs
end

-- Titled pane: accent title, underline at y = -17, content below.
function UI.CreateTitledPane(parent, text, width, height)
    local pane = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pane:SetSize(width, height)

    local line = pane:CreateTexture()
    pane.line = line
    line:SetHeight(1)
    UI.Tint(line, "texture", "accent", 0.777) -- T107
    line:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -17)
    line:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -17)

    local shadow = pane:CreateTexture()
    shadow:SetHeight(1)
    UI.Tint(shadow, "texture", "border")
    shadow:SetPoint("TOPLEFT", line, "TOPLEFT", 1, -1)
    shadow:SetPoint("TOPRIGHT", line, "TOPRIGHT", 1, -1)
    -- T74 (P30, review U3): the rule and its shadow one pixel thick
    UI.PixelLayout(line, function(l) l:SetHeight(UI.px(1, l)) end)
    UI.PixelLayout(shadow, function(sh)
        local e = UI.px(1, sh)
        sh:SetHeight(e)
        sh:SetPoint("TOPLEFT", line, "TOPLEFT", e, -e)
        sh:SetPoint("TOPRIGHT", line, "TOPRIGHT", e, -e)
    end)

    local title = pane:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    pane.title = title
    title:SetJustifyH("LEFT")
    UI.Tint(title, "text", "accent")
    title:SetText(text)
    title:SetPoint("BOTTOMLEFT", line, "TOPLEFT", 0, 2)

    function pane:SetTitle(t) title:SetText(t) end
    return pane
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------
-- T74 (P30, review A20): a colour name is a pair of UI.PALETTE keys, read when
-- the button is made -- no longer tables frozen when this file loaded, so the
-- theme (which runs before any window is built) reaches them. The keys hold
-- the literals this table carried, so every button paints what it painted.
local BUTTON_COLORS = {
    ["red"]          = { "close",      "closeHover" },
    ["red-hover"]    = { "button",     "closeHover" },
    ["green"]        = { "go",         "goHover" },
    ["green-hover"]  = { "button",     "goHover" },
    ["blue-hover"]   = { "button",     "info" },
    ["yellow-hover"] = { "button",     "warn" },
    ["accent"]       = { "accentFill", "accentHover" },
    ["accent-hover"] = { "button",     "accentHover" },
    ["transparent"]  = { "clear",      "accentHover" },
    ["none"]         = { "clear",      nil },
}
local DEFAULT_BUTTON_COLORS = { "button", "buttonHover" }

-- UI.ButtonColors(name) -> fill, hover: the palette's tables for a colour name
-- (an unknown name is the plain grey pair); hover is nil for "none".
function UI.ButtonColors(name)
    local pair = BUTTON_COLORS[name] or DEFAULT_BUTTON_COLORS
    return UI.PALETTE[pair[1]], pair[2] and UI.PALETTE[pair[2]] or nil
end

-- T74 (P30, review U3): a kit control's 1-px edge and insets. Under UI.PIXEL
-- they are UI.px(1) and the control is registered with StylizeFrame's (so
-- UI.RestylePixels re-applies them, keeping the colours it shows); without it,
-- the backdrop each control always had. `insets` false = no insets (the check
-- box's old backdrop carried none). T94: registered by role (`button`, or
-- `field` for the check box) through UI.Skin, which paints the fill and the
-- `border` edge; the caller's colours follow as before.
local function ControlBackdrop(frame, fill, insets, role)
    if UI.PIXEL then
        UI.Skin(frame, role or "button", fill, "border")
    elseif insets == false then
        frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    else
        frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    end
end

-- UI.CreateButton(parent, text, colorName, {w, h}, noBorder, noBackground, fontNormal, fontDisable, tooltip...)
function UI.CreateButton(parent, text, buttonColor, size, noBorder, noBackground, fontNormal, fontDisable, ...)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    if parent then b:SetFrameLevel(parent:GetFrameLevel() + 1) end
    b:SetText(text or "")
    b:SetSize(size[1], size[2])
    -- T75 (P31, review U31): a sheet's title row keeps its x at the right; a
    -- button anchored by its TOPRIGHT to the sheet's TOPRIGHT (a caller's own
    -- title-row control: the bindings sheet's Done) is laid left of the x
    -- instead, at the same offsets. Only on a sheet that has the x (the theme).
    if parent and parent.isSheet and parent.closeBtn then
        local setPoint = b.SetPoint
        function b:SetPoint(p, rel, rp, x, y, ...)
            if p == "TOPRIGHT" and rel == parent and rp == "TOPRIGHT" then
                return setPoint(self, "TOPRIGHT", parent.closeBtn, "TOPLEFT", x or 0, y or 0)
            end
            return setPoint(self, p, rel, rp, x, y, ...)
        end
    end

    b.color, b.hoverColor = UI.ButtonColors(buttonColor)

    local s = b:GetFontString()
    b.fs = s
    if s then
        s:SetWordWrap(false)
        s:SetPoint("LEFT")
        s:SetPoint("RIGHT")
        function b:SetTextColor(...) s:SetTextColor(...) end
    end

    if noBorder then
        b:SetBackdrop({ bgFile = WHITE })
    else
        ControlBackdrop(b, b.color)
    end

    if buttonColor == "transparent" then
        if s then
            s:SetJustifyH("LEFT")
            s:SetPoint("LEFT", 5, 0)
            s:SetPoint("RIGHT", -5, 0)
        end
        b:SetBackdropBorderColor(1, 1, 1, 0)
        b:SetPushedTextOffset(0, 0)
    else
        if not noBackground then
            local bg = b:CreateTexture()
            bg:SetDrawLayer("BACKGROUND", -8)
            b.bg = bg
            bg:SetAllPoints(b)
            UI.Tint(bg, "texture", "button") -- T107
        end
        -- T107: under UI.PIXEL the skin painted the role's edge (a style's
        -- edgeColor included); the border fill only where nothing else does
        if noBorder or not UI.PIXEL then UI.Tint(b, "border", "border") end
        b:SetPushedTextOffset(0, -1)
    end

    b:SetBackdropColor(unpack(b.color))
    b:SetDisabledFontObject(fontDisable or UI.FONT_DISABLE)
    b:SetNormalFontObject(fontNormal or UI.FONT)
    b:SetHighlightFontObject(fontNormal or UI.FONT)

    -- T76 (P32, review U13): under UI.THEMED a disabled button still takes
    -- the pointer, so its tooltip can say why it is disabled (a Coach on a
    -- fight that does not replay, a Start with nothing bound); its hover
    -- colour stays off while it is disabled. TBC's disabled buttons stay
    -- silent, as they always were.
    local themed = UI.THEMED
    if themed and b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    if b.hoverColor then
        if themed then
            b:SetScript("OnEnter", function(self)
                if self.IsEnabled and self:IsEnabled() == false then return end
                self:SetBackdropColor(unpack(self.hoverColor))
            end)
        else
            b:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(self.hoverColor)) end)
        end
        b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(self.color)) end)
    end
    b:SetScript("PostClick", function()
        if SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
    end)

    UI.SetTooltips(b, "ANCHOR_TOPLEFT", 0, 3, ...)
    return b
end

-- Radio-style group. Each button needs an .id; onClick(id, button) fires on
-- click. Returns Highlight(id).
--
-- Without the theme (TBC) the active button keeps its hover colour and loses
-- its hover scripts, as it always did.
--
-- T74 (P30, review U1; docs/SPEC-forever-ui.md 4.3, the approved mockup's
-- .nb.on / .vt.on / .btn.act): under UI.THEMED the active button is the
-- `selected` fill plus a 2-px accent bar -- opts.bar = "left" (the nav's
-- groups) or "bottom" (the default: view tabs and every other group) -- and
-- hover is the `hover` fill laid over whatever the button shows, the active
-- one included, so moving down the nav no longer lights a button like the
-- selected one.
local function SelectionParts(b, side)
    if not b.selBar then
        local hov = b:CreateTexture(nil, "BORDER")
        UI.Tint(hov, "texture", "hover") -- T107
        hov:Hide()
        local bar = b:CreateTexture(nil, "ARTWORK")
        UI.Tint(bar, "texture", "accent")
        bar:Hide()
        b.selHover, b.selBar = hov, bar
    end
    local hov, bar = b.selHover, b.selBar
    bar.side = side
    local function Lay()
        local e = UI.px(1, b)
        hov:ClearAllPoints()
        hov:SetPoint("TOPLEFT", b, "TOPLEFT", e, -e)
        hov:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -e, e)
        bar:ClearAllPoints()
        if bar.side == "left" then
            bar:SetPoint("TOPLEFT", b, "TOPLEFT", e, -e)
            bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", e, e)
            bar:SetWidth(UI.px(2, b))
        else
            bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", e, e)
            bar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -e, e)
            bar:SetHeight(UI.px(2, b))
        end
    end
    Lay()
    if UI.PIXEL then UI.pixelLayouts[bar] = Lay end
end

local function HoverOn(self) if self.selHover then self.selHover:Show() end end
local function HoverOff(self) if self.selHover then self.selHover:Hide() end end

function UI.CreateButtonGroup(buttons, onClick, onActive, onInactive, opts)
    local themed = UI.THEMED
    local side = opts and opts.bar == "left" and "left" or "bottom"
    if themed then
        for _, b in pairs(buttons) do
            SelectionParts(b, side)
            b:SetScript("OnEnter", HoverOn)
            b:SetScript("OnLeave", HoverOff)
        end
    end
    local function Highlight(id)
        for _, b in pairs(buttons) do
            if themed then
                b:SetScript("OnEnter", HoverOn)
                b:SetScript("OnLeave", HoverOff)
                if id == b.id then
                    b:SetBackdropColor(UI.Fill("selected"))
                    b.selBar:Show()
                    b.active = true
                    if onActive then onActive(b.id, b) end
                else
                    b:SetBackdropColor(unpack(b.color))
                    b.selBar:Hide()
                    b.active = false
                    if onInactive then onInactive(b.id, b) end
                end
            elseif id == b.id then
                b:SetBackdropColor(unpack(b.hoverColor))
                b:SetScript("OnEnter", nil)
                b:SetScript("OnLeave", nil)
                if onActive then onActive(b.id, b) end
            else
                b:SetBackdropColor(unpack(b.color))
                b:SetScript("OnEnter", function() b:SetBackdropColor(unpack(b.hoverColor)) end)
                b:SetScript("OnLeave", function() b:SetBackdropColor(unpack(b.color)) end)
                if onInactive then onInactive(b.id, b) end
            end
        end
    end
    for _, b in pairs(buttons) do
        b:SetScript("OnClick", function()
            Highlight(b.id)
            onClick(b.id, b)
        end)
    end
    return Highlight
end

--------------------------------------------------------------------------------
-- Navigation (docs/SPEC-v0.11.md §3): one window, groups down the left, that
-- group's views along the top, and -- where a pane needs it -- the same rule
-- again inside a bordered box.
--
-- Written once so the panes stay dumb: a pane is a frame parented to
-- nav:Content(), created LAZILY the first time its view is selected and cached
-- after. A druid who never opens Simulate never builds it.
--
-- The palette is UI.PALETTE and nothing here carries its own literals: the
-- author asked for the settings window's colours everywhere, and "everywhere"
-- only holds if there is one place to change.
--------------------------------------------------------------------------------

local NAV_W = 108        -- the left column
local NAV_TOP = 24       -- the horizontal view row
local NAV_PAD = 8
local RAIL_W = 172       -- T31: a rail group's list column (docs/SPEC-forever-ui.md 3.2)

-- groups: { { id, text, views = { { id, text, hidden }, ... } }, ... }
--   T31 (docs/SPEC-forever-ui.md 3.1), additive: a group with layout = "rail"
--   draws no view row. Its views are the rows of a list down the content's
--   left edge (UI.CreateRail, options from group.rail; a view may also carry
--   icon / tag / new / stale / fixed / tooltip), and its panes are built into
--   the area right of that list (onCreate is handed that area as `content`).
--   The content frame is re-anchored per group: NAV_PAD below the frame's top
--   for a rail group, NAV_TOP + NAV_PAD for any other (today's, and TBC's
--   only, since TBC declares no rail group).
-- onCreate(groupID, viewID, content, nav) -> pane. Called ONCE per view, the
--   first time it is selected; the pane is cached and shown thereafter.
-- onShow(groupID, viewID, pane, nav). Called on every selection, including the
--   first. This is where a pane is refreshed -- rebuilding it instead would
--   throw away its state and its frames every time the author clicked a tab.
-- T32: opts (optional, additive) is handed to UI.CreateMovableFrame -- the
--   Forever window passes { resizable = true, notUserPlaced = true }.
function UI.CreateNavFrame(title, name, width, height, groups, onCreate, onShow, opts)
    local P = UI.PALETTE
    local f = UI.CreateMovableFrame(title, name, width, height, nil, nil, opts and opts.notUserPlaced, opts)
    UI.StylizeFrame(f, P.frame, P.border)

    local nav = { frame = f, groups = groups, buttons = {}, viewButtons = {},
                  group = nil, view = nil }

    -- the left column
    local left = CreateFrame("Frame", nil, f, "BackdropTemplate")
    left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    left:SetWidth(NAV_W)
    UI.Skin(left, "nav", P.header, P.border) -- T94: by role
    nav.left = left

    -- the content area, and the row of view buttons above it
    local content = CreateFrame("Frame", nil, f)
    nav.content = content
    function nav:Content() return content end

    -- T31: anchored per group -- a rail group has no view row above it
    local function AnchorContent(isRail)
        local top = isRail and -NAV_PAD or -(NAV_TOP + NAV_PAD)
        if nav.contentTop == top then return end
        nav.contentTop = top
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", left, "TOPRIGHT", NAV_PAD, top)
        content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -NAV_PAD, NAV_PAD)
    end
    AnchorContent(false)

    -- T31: a rail group's list and the area right of it, built the first time
    -- the group is asked for, one holder per rail group
    nav.rails = {}
    local function RailOf(group)
        if not group or group.layout ~= "rail" then return nil end
        local h = nav.rails[group.id]
        if h then return h end
        local holder = CreateFrame("Frame", nil, content)
        holder:SetAllPoints(content)
        local o = {}
        for k, v in pairs(group.rail or {}) do o[k] = v end
        local own = o.onSelect
        o.onSelect = function(id)
            nav:Select(group.id, id)
            if own then own(id) end
        end
        local rail = UI.CreateRail(holder, o.width or RAIL_W, o)
        rail.frame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        rail.frame:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
        local view = CreateFrame("Frame", nil, holder)
        view:SetPoint("TOPLEFT", rail.frame, "TOPRIGHT", NAV_PAD, 0)
        view:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
        rail:SetRows(group.views)
        h = { holder = holder, rail = rail, view = view }
        nav.rails[group.id] = h
        if nav.group ~= group.id then holder:Hide() end
        return h
    end
    local function GroupOf(groupID)
        for _, g in ipairs(groups) do if g.id == groupID then return g end end
    end
    -- nav:Rail(groupID) -> the rail (UI.CreateRail's), nav:RailView(groupID) ->
    -- the frame right of it that the group's panes live in; nil for a group
    -- without layout = "rail"
    function nav:Rail(groupID)
        local h = RailOf(GroupOf(groupID))
        return h and h.rail or nil
    end
    function nav:RailView(groupID)
        local h = RailOf(GroupOf(groupID))
        return h and h.view or nil
    end
    local function ShowRails(groupID)
        for id, h in pairs(nav.rails) do
            if id == groupID then h.holder:Show() else h.holder:Hide() end
        end
    end

    -- Hide everything that is not the selected pane, THEN show it. One frame can
    -- be registered under several views (the rank table is the pane for every
    -- spell family), and a single pass would hide it again on whichever key
    -- pairs() happened to visit last.
    local function ShowOnly(groupID, viewID)
        local keep = nav.panes and nav.panes[groupID] and nav.panes[groupID][viewID]
        for _, panes in pairs(nav.panes or {}) do
            for _, pane in pairs(panes) do
                if pane ~= keep and pane.Hide then pane:Hide() end
            end
        end
        if keep and keep.Show then keep:Show() end
    end

    -- the horizontal row for the selected group. T31: the buttons come from a
    -- pool and a hidden one is reused by index -- a rebuild used to create a
    -- fresh set every time and hide the old (Reports -> Runs leaked a row per
    -- SetViews). A reused button is put back as CreateButton left it.
    nav.viewButtonPool = {}
    local function ReleaseViews()
        for _, b in ipairs(nav.viewButtonPool) do b:Hide() end
        wipe(nav.viewButtons)
    end
    local function BuildViews(group)
        ReleaseViews()
        local prev
        local themed = UI.THEMED
        for _, v in ipairs(group.views or {}) do
            if not v.hidden then
                local i = #nav.viewButtons + 1
                local bw, bh = math.max(64, #v.text * 8 + 16), 20
                local b = nav.viewButtonPool[i]
                if b then
                    b:SetText(v.text)
                    b:SetSize(bw, bh)
                    b:ClearAllPoints()
                    b:SetBackdropColor(unpack(b.color))
                    b:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(self.hoverColor)) end)
                    b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(self.color)) end)
                    -- T74 (P30): the theme's selection parts start hidden
                    if b.selBar then b.selBar:Hide(); b.selHover:Hide() end
                    b:Show()
                else
                    b = UI.CreateButton(f, v.text, "accent-hover", { bw, bh },
                        false, false, UI.FONT_TITLE, UI.FONT_TITLE_DISABLE)
                    nav.viewButtonPool[i] = b
                end
                b.id = v.id
                if themed then
                    -- T75 (P31, review U30, U31): under the theme a tab is as
                    -- wide as its text (measured, 12 each side) and as tall as
                    -- the nav's group buttons, so the two rows line up; tabs
                    -- overlap by one pixel. TBC keeps #text * 8 + 16 by 20.
                    local fs = b.GetFontString and b:GetFontString()
                    b:SetSize(math.max(40, math.ceil(UI.TextWidth(v.text, UI.FONT_TITLE, fs)) + 24),
                        UI.H.toolbar)
                end
                if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0)
                else b:SetPoint("TOPLEFT", left, "TOPRIGHT", NAV_PAD, -2) end
                if prev then
                    local after = prev
                    UI.PixelLayout(b, function(btn)
                        btn:ClearAllPoints()
                        btn:SetPoint("LEFT", after, "RIGHT", -UI.px(1, btn), 0)
                    end)
                else
                    UI.pixelLayouts[b] = nil -- a pooled button now first: no stale neighbour
                end
                nav.viewButtons[#nav.viewButtons + 1] = b
                prev = b
            end
        end
        nav.highlightView = UI.CreateButtonGroup(nav.viewButtons, function(id) nav:Select(group.id, id) end)
    end

    function nav:Select(groupID, viewID)
        local group
        for _, g in ipairs(groups) do if g.id == groupID then group = g end end
        if not group then group = groups[1] end
        if not group then return end
        if nav.group ~= group.id then
            nav.group = group.id
            local isRail = group.layout == "rail"
            AnchorContent(isRail)
            if isRail then
                -- T31: no view row; the rail marks the selection
                ReleaseViews()
                local r = RailOf(group).rail
                nav.highlightView = function(id) r:Select(id) end
            else
                BuildViews(group)
            end
            ShowRails(group.id)
            nav.view = nil
        end
        local views = group.views or {}
        local view
        for _, v in ipairs(views) do
            if v.id == viewID and not v.hidden then view = v end
        end
        if not view then
            for _, v in ipairs(views) do if not v.hidden and not view then view = v end end
        end
        nav.view = view and view.id or nil
        if nav.highlightGroup then nav.highlightGroup(group.id) end
        if nav.highlightView and nav.view then nav.highlightView(nav.view) end
        if MD.db then MD.db.uiPath = { group.id, nav.view } end
        nav.panes = nav.panes or {}
        nav.panes[group.id] = nav.panes[group.id] or {}
        local pane = nav.view and nav.panes[group.id][nav.view] or nil
        if not pane and nav.view and onCreate then
            local h = nav.rails[group.id]   -- T31: a rail group's panes go right of its rail
            pane = onCreate(group.id, nav.view, h and h.view or content, nav)
            if pane then nav.panes[group.id][nav.view] = pane end
        end
        ShowOnly(group.id, nav.view)
        if onShow then onShow(group.id, nav.view, pane, nav) end
    end

    -- a group's views can change while the window is open (Reports/Runs)
    function nav:SetViews(groupID, views)
        for _, g in ipairs(groups) do
            if g.id == groupID then
                g.views = views
                if g.layout == "rail" then
                    -- T31: a rail group has no view row to build; its rail
                    -- (if it exists yet) takes the new rows
                    local h = nav.rails[groupID]
                    if h then h.rail:SetRows(views) end
                    if nav.group == groupID then nav:Select(groupID, nav.view) end
                    return
                end
                if nav.group == groupID then BuildViews(g); nav:Select(groupID, nav.view) end
                return
            end
        end
    end

    function nav:Selected() return nav.group, nav.view end

    -- T73 (P29, review A24): put `pane` in a view's place -- a placeholder
    -- swapped for the real pane once its module loads -- without a caller
    -- reaching into nav.panes. The old pane is hidden (nothing is destroyed:
    -- the client cannot); if the view is the one on screen it is re-selected,
    -- so the new pane is shown and onShow refreshes it. Returns the old pane.
    function nav:ReplacePane(groupID, viewID, pane)
        nav.panes = nav.panes or {}
        nav.panes[groupID] = nav.panes[groupID] or {}
        local old = nav.panes[groupID][viewID]
        nav.panes[groupID][viewID] = pane
        if old and old ~= pane and old.Hide then old:Hide() end
        if nav.group == groupID and nav.view == viewID then
            nav:Select(groupID, viewID)
        elseif pane and pane.Hide then
            pane:Hide()
        end
        return old
    end

    local prev
    for _, g in ipairs(groups) do
        local b = UI.CreateButton(left, g.text, "accent-hover", { NAV_W - 2, UI.H.toolbar }, false, false,
            UI.FONT_TITLE, UI.FONT_TITLE_DISABLE)
        b.id = g.id
        if prev then b:SetPoint("TOP", prev, "BOTTOM", 0, 1)
        else b:SetPoint("TOP", left, "TOP", 0, -2) end
        -- T75 (P31): the groups overlap by one pixel, not one unit (UI.PIXEL only)
        if prev then
            local above = prev
            UI.PixelLayout(b, function(btn)
                btn:ClearAllPoints()
                btn:SetPoint("TOP", above, "BOTTOM", 0, UI.px(1, btn))
            end)
        end
        nav.buttons[#nav.buttons + 1] = b
        prev = b
    end
    -- T74 (P30): under the theme the groups' bar is on the left (view tabs: bottom)
    nav.highlightGroup = UI.CreateButtonGroup(nav.buttons, function(id) nav:Select(id, nil) end,
        nil, nil, { bar = "left" })

    return nav
end

-- The same rule one level down, in a bordered box: for a pane that has
-- sub-categories of its own. Nothing needs it yet; it exists so that the next
-- thing that does is not a fourth window.
function UI.CreateNavBox(parent, width, height, groups, onSelect)   -- one hook: a box owns no panes
    local P = UI.PALETTE
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(width, height)
    UI.StylizeFrame(box, P.pane, P.border)
    local nav = { frame = box, groups = groups, buttons = {}, viewButtons = {} }

    local left = CreateFrame("Frame", nil, box, "BackdropTemplate")
    left:SetPoint("TOPLEFT", 1, -1)
    left:SetPoint("BOTTOMLEFT", 1, 1)
    left:SetWidth(NAV_W - 20)
    UI.Skin(left, "nav", P.header, P.border) -- T94: by role

    local content = CreateFrame("Frame", nil, box)
    content:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, -(NAV_TOP + 2))
    content:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 6)
    function nav:Content() return content end

    local function BuildViews(group)
        for _, b in ipairs(nav.viewButtons) do b:Hide() end
        wipe(nav.viewButtons)
        local prev
        for _, v in ipairs(group.views or {}) do
            local b = UI.CreateButton(box, v.text, "accent-hover", { math.max(56, #v.text * 7 + 14), 18 },
                false, false, UI.FONT_SMALL, UI.FONT_SMALL)
            if UI.THEMED then -- T75 (P31): measured, 8 each side (TBC: #text * 7 + 14)
                local fs = b.GetFontString and b:GetFontString()
                b:SetWidth(math.max(40, math.ceil(UI.TextWidth(v.text, UI.FONT_SMALL, fs)) + 16))
            end
            b.id = v.id
            if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0)
            else b:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, -2) end
            nav.viewButtons[#nav.viewButtons + 1] = b
            prev = b
        end
        nav.highlightView = UI.CreateButtonGroup(nav.viewButtons, function(id) nav:Select(group.id, id) end)
    end

    function nav:Select(groupID, viewID)
        local group
        for _, g in ipairs(groups) do if g.id == groupID then group = g end end
        group = group or groups[1]
        if not group then return end
        if nav.group ~= group.id then nav.group = group.id; BuildViews(group); nav.view = nil end
        local view
        for _, v in ipairs(group.views or {}) do if v.id == viewID then view = v end end
        view = view or (group.views or {})[1]
        nav.view = view and view.id or nil
        if nav.highlightGroup then nav.highlightGroup(group.id) end
        if nav.highlightView and nav.view then nav.highlightView(nav.view) end
        if onSelect then onSelect(group.id, nav.view, content, nav) end
    end

    local prev
    for _, g in ipairs(groups) do
        local b = UI.CreateButton(left, g.text, "accent-hover", { NAV_W - 22, 18 }, false, false,
            UI.FONT_SMALL, UI.FONT_SMALL)
        b.id = g.id
        if prev then b:SetPoint("TOP", prev, "BOTTOM", 0, 1)
        else b:SetPoint("TOP", left, "TOP", 0, -2) end
        nav.buttons[#nav.buttons + 1] = b
        prev = b
    end
    -- T74 (P30): under the theme the groups' bar is on the left (view tabs: bottom)
    nav.highlightGroup = UI.CreateButtonGroup(nav.buttons, function(id) nav:Select(id, nil) end,
        nil, nil, { bar = "left" })

    return nav
end

--------------------------------------------------------------------------------
-- T31 (docs/SPEC-forever-ui.md 3.2, 6.2, 6.4): the rail, sheets and masks.
-- Additive: nothing on TBC builds them (only a layout = "rail" nav group and
-- the Forever panes do). Colours are the theme's (UI.PALETTE / UI.TEXT, from
-- UI/Theme_Forever.lua) with the flat literals as the fallback.
-- T69 (P25): UI.TEXT is present on TBC too now, so the text colours ask
-- UI.THEMED: without the theme each call keeps its own literal, as before.
--------------------------------------------------------------------------------
local function TextRGB(token, r, g, b)
    local t = UI.THEMED and UI.TEXT[token]
    if t then return t[1], t[2], t[3] end
    return r, g, b
end
local function Fill(key, fallback)
    local c = UI.PALETTE and UI.PALETTE[key]
    return c or fallback
end
-- T107: the same two reads as tints -- the token or the fill by name where
-- the theme (TextRGB's gate) or the palette has it, else the literal as before
local function TintText(fs, token, r, g, b)
    if UI.THEMED and UI.TEXT[token] then UI.Tint(fs, "text", token)
    else UI.Untint(fs, "text"); fs:SetTextColor(r, g, b) end
end
local function TintFill(tex, key, fallback)
    if UI.PALETTE and UI.PALETTE[key] then UI.Tint(tex, "texture", key)
    else UI.Untint(tex, "texture"); tex:SetColorTexture(fallback[1], fallback[2], fallback[3], fallback[4] or 1) end
end

-- A popup list (a dropdown's, a tree's second list) opened or closed: the
-- kit's UI_POPUP event (T77, P33; the window manager subscribes, 6.5). With
-- no subscriber (TBC) nothing happens, as before.
local function Popup(list, shown)
    UI.Popup(list, shown)
end
local function WatchPopup(list)
    list:SetScript("OnShow", function(self) Popup(self, true) end)
    list:SetScript("OnHide", function(self) Popup(self, false) end)
end

--------------------------------------------------------------------------------
-- T77 (P33, review U12): lists at the screen's edge. A dropdown's list opens
-- below its button unless it would leave the bottom of the screen and fits
-- above it, then it opens upward; a tree's second list opens right of its row
-- unless it would leave the right edge and fits on the left. Both lines: a
-- list off the screen is a bug on either. Whatever cannot be read (a frame
-- with no position yet) keeps the old side.
--
-- Rectangles are compared in screen pixels (a frame's units times its
-- effective scale). Bottom and right are derived from the top / left and the
-- size, which is what the client answers too.
--------------------------------------------------------------------------------
local function Box(f)
    if not f then return nil end
    local l, t, w, h = f:GetLeft(), f:GetTop(), f:GetWidth(), f:GetHeight()
    local s = f.GetEffectiveScale and f:GetEffectiveScale()
    if type(l) ~= "number" or type(t) ~= "number" or type(w) ~= "number" or type(h) ~= "number"
        or type(s) ~= "number" or s <= 0 then
        return nil
    end
    return l * s, (t - h) * s, (l + w) * s, t * s
end
local function ScreenSize()
    local s = UIParent:GetEffectiveScale()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if type(s) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then return nil end
    return w * s, h * s
end
local function Extent(list, w, h)
    local s = list:GetEffectiveScale()
    if type(s) ~= "number" or s <= 0 then s = 1 end
    return w * s, h * s
end

-- "up" when the list under `button` would leave the screen's bottom and fits
-- above it, else "down".
function UI.ListSide(button, list)
    local _, bottom, _, top = Box(button)
    local _, screenH = ScreenSize()
    local h = list:GetHeight()
    if not bottom or not screenH or type(h) ~= "number" then return "down" end
    local _, need = Extent(list, 0, h + 1)
    if bottom - need >= 0 then return "down" end
    if top + need <= screenH then return "up" end
    return "down"
end

-- "left" when a list beside `row` would leave the screen's right edge and
-- fits on its left, else "right".
function UI.SubListSide(row, list, gap)
    local left, _, right = Box(row)
    local screenW = ScreenSize()
    local w = list:GetWidth()
    if not left or not screenW or type(w) ~= "number" then return "right" end
    local need = Extent(list, w + (gap or 0), 0)
    if right + need <= screenW then return "right" end
    if left - need >= 0 then return "left" end
    return "right"
end

--------------------------------------------------------------------------------
-- T77 (P33, review U12): chevrons. Under UI.THEMED an 8 x 8 texture pointing
-- the way its list opens (down, up, right, or left once a list flips); the
-- letter (v ^ > <) whenever the theme is off -- TBC keeps the letter it
-- always had -- or the texture cannot be set.
--
-- UI.CreateChevron(parent, dir, letterFont) -> chevron  (anchor chevron:
--   SetPoint as a region; chevron:SetDirection(dir); chevron.dir,
--   chevron.tex, chevron.letter, chevron.textured)
--------------------------------------------------------------------------------
local CHEVRON_FILE = "Interface\\Buttons\\SquareButtonTextures"
local CHEVRON_COORDS = {   -- the game's own arrows in that file (SquareButton_SetIcon)
    up    = { 0.453125, 0.640625, 0.015625, 0.203125 },
    down  = { 0.453125, 0.640625, 0.203125, 0.015625 },
    left  = { 0.234375, 0.421875, 0.015625, 0.203125 },
    right = { 0.421875, 0.234375, 0.015625, 0.203125 },
}
local CHEVRON_LETTER = { down = "v", up = "^", right = ">", left = "<" }
UI.CHEVRON_FILE, UI.CHEVRON_LETTER = CHEVRON_FILE, CHEVRON_LETTER

function UI.CreateChevron(parent, dir, letterFont)
    local c = { dir = dir or "down" }
    local letter = parent:CreateFontString(nil, "OVERLAY", letterFont or UI.FONT_SMALL)
    letter:SetTextColor(0.7, 0.7, 0.7)
    c.letter = letter
    if UI.THEMED then
        local tex = parent:CreateTexture(nil, "OVERLAY")
        tex:SetSize(8, 8)
        local set = tex:SetTexture(CHEVRON_FILE)
        if set ~= false then
            c.tex, c.textured = tex, true
            tex:SetVertexColor(0.7, 0.7, 0.7, 1)
        else
            tex:Hide()
        end
    end
    function c:SetPoint(...)
        letter:SetPoint(...)
        if c.tex then c.tex:SetPoint(...) end
    end
    function c:ClearAllPoints()
        letter:ClearAllPoints()
        if c.tex then c.tex:ClearAllPoints() end
    end
    function c:SetShown(on)
        if c.textured then
            letter:Hide()
            if on then c.tex:Show() else c.tex:Hide() end
        else
            if on then letter:Show() else letter:Hide() end
        end
        c.shown = on and true or false
    end
    function c:SetDirection(d)
        c.dir = d
        if c.textured then
            local tc = CHEVRON_COORDS[d] or CHEVRON_COORDS.down
            c.tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            letter:SetText("")
        else
            letter:SetText(CHEVRON_LETTER[d] or "v")
        end
    end
    c:SetDirection(c.dir)
    c:SetShown(true)
    return c
end

--------------------------------------------------------------------------------
-- The rail: a list you build yourself, one row per view (3.2).
--
-- UI.CreateRail(parent, w, opts) -> rail     (rail.frame is the list's frame;
--                                             the caller anchors it)
--   opts.title          the label on top ("MY SPELLS"), 11 px muted, 18 tall
--   opts.rowHeight      a row's height, 20 (a Forever pane passes UI.Pitch(20));
--                       rows overlap by 1 px, so their tops are rowHeight - 1 apart
--   opts.footerHeight   the slot pinned at the bottom (rail:Footer()), 0 if absent
--   opts.empty          the line shown when no movable row is listed
--   opts.onSelect(id)   a row clicked
--   opts.onMove(id, to) ONCE per reorder (a drag, the menu); `to` is the row's
--                       new place among the movable rows
--   opts.onRemove(id)   the hover x or the menu's Remove
--   opts.onDrop(at)     something dropped on the rail, to go in before movable
--                       row `at` (#rows + 1: at the end). The kit never reads
--                       or clears the cursor: the caller does what it likes.
--   opts.canDrop()      true when a click on the rail should drop (the cursor
--                       holds something) rather than select
-- rail:SetRows(rows)   rows = { { id, text, icon, tag, new, stale, fixed,
--                      tooltip, hidden }, ... }: fixed rows (Overview) are not
--                      movable, and a 1-px rule follows the last of them;
--                      `stale` greys the name and drops the tag; `tooltip` is a
--                      string or a list of lines (strings, or UI/Tip.lua's line
--                      tables: a pair, a muted line) under the row's name
-- rail:Select(id)      marks the row (fill + a 2-px accent bar) and scrolls it
--                      into view
-- rail:Rows()          every listed row, in order (each .id, .index, .data,
--                      .clipped when it is scrolled out of view, and hidden)
-- rail:Footer()        the bottom slot's frame
-- rail:SetRowHeight(h) a new row height (the font offset changed), rows re-laid
-- rail:OpenMenu(row)   the right-click menu (UI/ContextMenu.lua's, as Review's):
--                      the row's name, Move up / Move down / Remove
--
-- T77 (P33 of docs/PLAN-refactor-ux.md, review U8, U16; mockup M4, layout B,
-- docs/mockups/refactor-ux.html):
--   * on hover a movable row keeps its rank tag and shows ONE control, an
--     18-px x; ^ / v are gone -- a row moves by dragging or from the menu;
--   * a row hovered for half a second shows its tooltip: the name, the
--     caller's lines (the Spells pane's "Suggested  Rank 1 of 2 known", "Per
--     mana  1.90"), and for a movable row "Drag to reorder. Right-click for
--     more." in the muted tone;
--   * when the movable rows outgrow the space between the fixed rows and the
--     footer they scroll there: the footer and the fixed rows never move, a
--     5-px bar (the kit scroll bar's track and accent thumb) at the right,
--     the wheel moves 3 rows a notch, and a selected row is scrolled into
--     view. A rail that has not been laid out yet (too short to hold one row)
--     shows every row, as before.
--------------------------------------------------------------------------------
local RAIL_X = 18                 -- the hover x, as the mockup's layout B
local RAIL_TIP_DELAY = 0.5        -- seconds a row is hovered before its tooltip
local RAIL_BAR_W = 5              -- the scroll bar
local RAIL_WHEEL = 3              -- rows per wheel notch
local RAIL_HINT = "Drag to reorder. Right-click for more."
UI.RAIL_HINT, UI.RAIL_TIP_DELAY = RAIL_HINT, RAIL_TIP_DELAY

function UI.CreateRail(parent, w, opts)
    opts = opts or {}
    local rowH = opts.rowHeight or 20
    local pitch = rowH - 1
    local TITLE_H = 18
    local RULE_GAP = 8          -- 3 above the 1-px rule, 4 below
    local rail = { opts = opts, rows = {}, pool = {}, selected = nil, offset = 0 }

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetWidth(w)
    frame:EnableMouse(true)
    UI.StylizeFrame(frame, Fill("pane", { 0.11, 0.11, 0.11, 1 }), Fill("border", { 0, 0, 0, 1 }))
    rail.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    title:SetJustifyH("LEFT")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -5)
    TintText(title, "muted", 0.48, 0.48, 0.48) -- T107
    title:SetText(opts.title or "")
    rail.title = title

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    TintFill(rule, "line", { 0.165, 0.165, 0.165, 1 })
    rule:Hide()

    local emptyText = frame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetPoint("LEFT", frame, "LEFT", 8, 0)
    emptyText:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    TintText(emptyText, "muted", 0.48, 0.48, 0.48)
    emptyText:Hide()

    -- the insertion line a drag shows (2 px, accent)
    local line = frame:CreateTexture(nil, "OVERLAY")
    line:SetHeight(2)
    UI.Tint(line, "texture", "accent", 1)
    line:Hide()

    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    footer:SetHeight(opts.footerHeight or 0)
    function rail:Footer() return footer end

    -- T77: the scroll bar (hidden until the rows outgrow the rail)
    local bar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bar:SetWidth(RAIL_BAR_W)
    UI.StylizeFrame(bar, Fill("track", { 0.1, 0.1, 0.1, 0.8 }))
    bar:Hide()
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(RAIL_BAR_W)
    UI.Tint(thumb, "texture", "accent", 0.8)
    rail.bar, rail.thumb = bar, thumb

    local function Movables()
        local n = 0
        for _, r in ipairs(rail.rows) do if r.movable then n = n + 1 end end
        return n
    end

    ----------------------------------------------------------------------------
    -- painting one row: fill, bar, name, tag, dot, the x
    ----------------------------------------------------------------------------
    local function Paint(row)
        -- T107: the fill by name, so a switch repaints a row it does not touch
        if row.selected then UI.Tint(row.bg, "texture", "selected")
        elseif row.hovered then UI.Tint(row.bg, "texture", "hover")
        else UI.Untint(row.bg, "texture"); row.bg:SetColorTexture(0, 0, 0, 0) end
        if row.selected then row.bar:Show() else row.bar:Hide() end
        local d = row.data or {}
        local x = row.hovered and row.movable and opts.onRemove and true or false
        local tag = d.tag and d.tag ~= "" and not d.stale
        local dot = d.new and not d.stale and not x
        if x then row.rm:Show() else row.rm:Hide() end
        row.tag:ClearAllPoints()
        if x then row.tag:SetPoint("RIGHT", row.rm, "LEFT", -4, 0)
        else row.tag:SetPoint("RIGHT", row, "RIGHT", -6, 0) end
        if tag then row.tag:Show() else row.tag:Hide() end
        if dot then row.dot:Show() else row.dot:Hide() end
        local right
        if x then right = 3 + RAIL_X + 4 + (tag and 30 or 0)
        else right = (tag and 32 or 6) + (dot and 11 or 0) end
        -- the name is truncated before whatever sits at the right
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row, "LEFT", row.nameX or 24, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -right, 0)
    end

    -- T77: the row's tooltip, half a second after the pointer arrived
    local function TipLines(row)
        local d = row.data or {}
        local lines = { d.text or "" }
        local t = d.tooltip
        if type(t) == "string" then
            lines[#lines + 1] = t
        elseif type(t) == "table" then
            for _, l in ipairs(t) do lines[#lines + 1] = l end
        elseif d.stale then
            lines[#lines + 1] = "not in your spellbook"
        end
        if row.movable and opts.onMove then lines[#lines + 1] = { l = RAIL_HINT, c = "muted" } end
        return lines
    end
    function rail:ShowRowTip(row)
        local lines = TipLines(row)
        if #lines < 2 then return end
        ShowTooltips(row, "ANCHOR_RIGHT", 2, 0, lines)
        row.tipShown = true
    end
    local function HideRowTip(row)
        row:SetScript("OnUpdate", nil)
        if row.tipShown then
            row.tipShown = nil
            tooltip:Hide()
        end
    end
    local function TipWait(row, elapsed)
        row.tipWait = (row.tipWait or 0) + (type(elapsed) == "number" and elapsed or 0)
        if row.tipWait < RAIL_TIP_DELAY then return end
        row:SetScript("OnUpdate", nil)
        if row.hovered and not rail.drag and row:IsShown() then rail:ShowRowTip(row) end
    end

    local function Leave(row)
        if row.IsMouseOver and row:IsMouseOver() then return end   -- onto its own control
        row.hovered = nil
        HideRowTip(row)
        Paint(row)
    end

    local function DropAt(row)
        if row and row.movable then return row.index end
        if row and not row.movable then return 1 end
        return Movables() + 1
    end

    local function NewRow()
        local row = CreateFrame("Button", nil, frame)
        row:SetHeight(rowH)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:RegisterForDrag("LeftButton")

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.bg:SetColorTexture(0, 0, 0, 0)

        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetWidth(2)
        row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", -1, 0)
        row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", -1, 0)
        UI.Tint(row.bar, "texture", "accent", 1)
        row.bar:Hide()

        row.iconEdge = row:CreateTexture(nil, "ARTWORK")
        row.iconEdge:SetSize(18, 18)
        row.iconEdge:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.iconEdge:SetColorTexture(0, 0, 0, 1)
        row.icon = row:CreateTexture(nil, "OVERLAY")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.tag = row:CreateFontString(nil, "OVERLAY", UI.FONT_NUM_SMALL or UI.FONT_SMALL)
        row.tag:SetJustifyH("RIGHT")
        row.tag:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        TintText(row.tag, "muted", 0.48, 0.48, 0.48)

        row.dot = row:CreateTexture(nil, "OVERLAY")
        row.dot:SetSize(6, 6)
        UI.Tint(row.dot, "texture", "accent", 1)

        row.name = row:CreateFontString(nil, "OVERLAY", UI.FONT)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        -- the hover control: one x, 18 px, red as Cell's delete (layout B)
        row.rm = UI.CreateButton(row, "x", "red-hover", { RAIL_X, RAIL_X }, false, false,
            UI.FONT_SMALL, UI.FONT_SMALL)
        row.rm:HookScript("OnLeave", function() Leave(row) end)
        row.rm:SetPoint("RIGHT", row, "RIGHT", -3, 0)
        row.rm:Hide()
        row.rm:SetScript("OnClick", function()
            if opts.onRemove then opts.onRemove(row.id) end
        end)

        row:SetScript("OnEnter", function(self)
            self.hovered = true
            Paint(self)
            self.tipWait = 0
            self:SetScript("OnUpdate", TipWait)
        end)
        row:SetScript("OnLeave", function(self) Leave(self) end)
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if self.movable then rail:OpenMenu(self) end
                return
            end
            if opts.canDrop and opts.onDrop and opts.canDrop() then
                opts.onDrop(DropAt(self))
                return
            end
            if opts.onSelect then opts.onSelect(self.id) end
        end)
        row:SetScript("OnReceiveDrag", function(self)
            if opts.onDrop then opts.onDrop(DropAt(self)) end
        end)
        row:SetScript("OnDragStart", function(self) HideRowTip(self); rail:BeginDrag(self) end)
        row:SetScript("OnDragStop", function() rail:EndDrag() end)
        return row
    end

    ----------------------------------------------------------------------------
    -- the scroll (T77): how many movable rows fit between the fixed rows and
    -- the footer; nil when they all do, or the rail is not laid out yet
    ----------------------------------------------------------------------------
    local function Capacity(n)
        local h = frame:GetHeight()
        if type(h) ~= "number" then return nil end
        local avail = h - (opts.footerHeight or 0) - (rail.firstTop or TITLE_H) - 2
        if avail < rowH then return nil end
        local cap = math.floor((avail - rowH) / pitch) + 1
        if cap >= n then return nil end
        return cap
    end

    function rail:Layout()
        local n = Movables()
        local cap = Capacity(n)
        rail.capacity = cap
        local maxOff = cap and (n - cap) or 0
        if rail.offset > maxOff then rail.offset = maxOff end
        if rail.offset < 0 then rail.offset = 0 end
        local inset = cap and (RAIL_BAR_W + 4) or 1
        local firstTop = rail.firstTop or TITLE_H
        for _, row in ipairs(rail.rows) do
            local y, visible = row.baseTop, true
            if row.movable then
                local slot = row.index - rail.offset
                visible = (not cap) or (slot >= 1 and slot <= cap)
                y = firstTop + (slot - 1) * pitch
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -y)
            row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -y)
            row.top = y
            row.clipped = not visible
            if visible then
                row:Show()
            else
                if row.hovered then row.hovered = nil; HideRowTip(row); Paint(row) end
                row:Hide()
            end
        end
        if cap then
            local trackH = (cap - 1) * pitch + rowH
            bar:ClearAllPoints()
            bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -firstTop)
            bar:SetHeight(trackH)
            local thumbH = math.max(12, math.floor(trackH * cap / n + 0.5))
            local at = maxOff > 0 and math.floor((trackH - thumbH) * rail.offset / maxOff + 0.5) or 0
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -at)
            thumb:SetHeight(thumbH)
            rail.thumbTop = at
            bar:Show()
        else
            rail.thumbTop = nil
            bar:Hide()
        end
    end

    function rail:ScrollTo(offset)
        rail.offset = math.floor(tonumber(offset) or 0)
        rail:Layout()
    end
    function rail:Scroll(delta) rail:ScrollTo(rail.offset + (tonumber(delta) or 0)) end

    -- the movable row with this id scrolled into view (nothing when it is
    -- fixed, absent or already in view)
    function rail:ScrollIntoView(id)
        local cap = rail.capacity
        if not cap or id == nil then return end
        for _, r in ipairs(rail.rows) do
            if r.id == id and r.movable then
                if r.index <= rail.offset then rail:ScrollTo(r.index - 1)
                elseif r.index > rail.offset + cap then rail:ScrollTo(r.index - cap) end
                return
            end
        end
    end

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        if rail.capacity then rail:Scroll(-(tonumber(delta) or 0) * RAIL_WHEEL) end
    end)
    frame:SetScript("OnSizeChanged", function() rail:Layout() end)

    ----------------------------------------------------------------------------
    -- rows
    ----------------------------------------------------------------------------
    function rail:SetRows(rows)
        rail.lastRows = rows
        for _, r in ipairs(rail.pool) do r:Hide() end
        wipe(rail.rows)
        rule:Hide()
        rail.firstTop = nil
        local y = TITLE_H
        local sawFixed, sawMovable, movable = false, false, 0
        for _, d in ipairs(rows or {}) do
            if not d.hidden then
                if not d.fixed and sawFixed and not sawMovable then
                    rule:ClearAllPoints()
                    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -(y + 3))
                    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(y + 3))
                    rule:Show()
                    y = y + RULE_GAP
                end
                local i = #rail.rows + 1
                local row = rail.pool[i]
                if not row then row = NewRow(); rail.pool[i] = row end
                row.id, row.data = d.id, d
                row.movable = not d.fixed
                if row.movable then
                    movable = movable + 1
                    row.index = movable
                    sawMovable = true
                    if movable == 1 then rail.firstTop = y end
                else
                    row.index = nil
                    sawFixed = true
                end
                row.baseTop = y

                local hasIcon = d.icon ~= nil and not d.fixed
                if hasIcon then
                    row.icon:SetTexture(d.icon); row.icon:Show(); row.iconEdge:Show()
                else
                    row.icon:Hide(); row.iconEdge:Hide()
                end
                row.nameX = d.fixed and 8 or 24
                row.name:SetText(d.text or "")
                if d.stale then TintText(row.name, "disabled", 0.3, 0.3, 0.3)
                else TintText(row.name, "text", 1, 1, 1) end
                row.tag:SetText(d.tag or "")
                row.dot:ClearAllPoints()
                if d.tag and d.tag ~= "" then row.dot:SetPoint("RIGHT", row.tag, "LEFT", -5, 0)
                else row.dot:SetPoint("RIGHT", row, "RIGHT", -6, 0) end
                row.selected = (rail.selected ~= nil and rail.selected == d.id)
                row.hovered = nil
                HideRowTip(row)
                row:SetAlpha(1)
                Paint(row)
                rail.rows[i] = row
                y = y + pitch
            end
        end
        if not rail.firstTop then rail.firstTop = y end
        if movable == 0 and opts.empty then
            if sawFixed then y = y + RULE_GAP end
            emptyText:ClearAllPoints()
            emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(y + 4))
            emptyText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(y + 4))
            emptyText:SetText(opts.empty)
            emptyText:Show()
        else
            emptyText:Hide()
        end
        rail:Layout()
    end

    function rail:Rows() return rail.rows end

    function rail:SetRowHeight(h)
        if type(h) ~= "number" or h <= 1 or h == rowH then return end
        rowH, pitch = h, h - 1
        for _, r in ipairs(rail.pool) do r:SetHeight(rowH) end
        rail:SetRows(rail.lastRows)
    end

    function rail:Select(id)
        rail.selected = id
        for _, r in ipairs(rail.rows) do
            r.selected = (r.id == id)
            Paint(r)
        end
        rail:ScrollIntoView(id)
    end

    ----------------------------------------------------------------------------
    -- drag to reorder: the row lifts to alpha 0.5, a 2-px line marks the drop
    -- point, and the move is reported ONCE (OnDragStop can fire twice)
    ----------------------------------------------------------------------------
    local function SlotAtCursor()
        local _, cy = GetCursorPosition()
        local top = frame:GetTop()
        local s = frame:GetEffectiveScale()
        if type(cy) ~= "number" or type(top) ~= "number" or type(s) ~= "number" or s <= 0 then return nil end
        local rel = top - cy / s
        local n = Movables()
        local slot = math.floor((rel - (rail.firstTop or TITLE_H) + pitch / 2) / pitch) + 1 + rail.offset
        if slot < 1 then slot = 1 end
        if slot > n + 1 then slot = n + 1 end
        return slot
    end

    function rail:BeginDrag(row)
        if rail.drag or not row.movable or not opts.onMove then return end
        rail.drag = { row = row, from = row.index }
        row:SetAlpha(0.5)
        frame:SetScript("OnUpdate", function() rail:TrackDrag() end)
        rail:TrackDrag()
    end

    function rail:TrackDrag()
        local slot = rail.drag and SlotAtCursor()
        if not slot then line:Hide(); return end
        local shown = slot - rail.offset
        if shown < 1 then shown = 1 end
        if rail.capacity and shown > rail.capacity + 1 then shown = rail.capacity + 1 end
        local y = (rail.firstTop or TITLE_H) + (shown - 1) * pitch
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -(y - 1))
        line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -(y - 1))
        line:Show()
    end

    -- a drag that ends nowhere (the rail hidden under it) moves nothing
    local function StopDrag()
        local d = rail.drag
        if not d then return nil end
        rail.drag = nil
        frame:SetScript("OnUpdate", nil)
        line:Hide()
        d.row:SetAlpha(1)
        return d
    end

    function rail:EndDrag()
        local d = StopDrag()
        if not d then return end
        local slot = SlotAtCursor()
        if not slot then return end
        local to = slot
        if slot > d.from then to = slot - 1 end
        if to ~= d.from and opts.onMove then opts.onMove(d.row.id, to) end
    end

    -- a drop on the rail's own ground (below the rows) goes in at the end
    frame:SetScript("OnReceiveDrag", function()
        if opts.onDrop then opts.onDrop(Movables() + 1) end
    end)
    frame:SetScript("OnMouseUp", function()
        if opts.canDrop and opts.onDrop and opts.canDrop() then opts.onDrop(Movables() + 1) end
    end)

    ----------------------------------------------------------------------------
    -- the right-click menu (T77: UI/ContextMenu.lua's, Review's menu): the
    -- row's name, Move up / Move down (each disabled at its end) / Remove
    ----------------------------------------------------------------------------
    function rail:OpenMenu(row)
        if not (row and row.movable) or not UI.CreateContextMenu then return end
        rail.menu = rail.menu or UI.CreateContextMenu(frame, 130)
        local i, n = row.index, Movables()
        local id = row.id
        local d = row.data or {}
        HideRowTip(row)
        rail.menu:Open(row, string.upper(d.text or ""), {
            { text = "Move up", disabled = not (opts.onMove and i > 1),
              onClick = function() opts.onMove(id, i - 1) end },
            { text = "Move down", disabled = not (opts.onMove and i < n),
              onClick = function() opts.onMove(id, i + 1) end },
            { text = "Remove", disabled = not opts.onRemove,
              onClick = function() opts.onRemove(id) end },
        })
    end
    frame:SetScript("OnHide", function()
        if rail.menu then rail.menu:Close() end
        StopDrag()
        for _, r in ipairs(rail.rows) do HideRowTip(r) end
    end)

    return rail
end

--------------------------------------------------------------------------------
-- Masks and sheets (6.4): an editor is a sheet inside the pane, never another
-- window. Behind it a mask covers the region the caller names and swallows
-- mouse and wheel input there (Cell's CreateMask); whatever is outside that
-- region stays live (the Spells rail while the picker is open).
--
-- UI.CreateMask(region, level, text) -> mask, hidden; at `level` (default the
--   region's +30), over the whole region. T75 (P31, review U31): an optional
--   line of text centred on it, as Cell's mask carries (mask:SetText(t) sets
--   or clears it later); no caller on TBC passes one.
-- UI.CreateSheet(pane, maskRegion, w, h, title) -> sheet, hidden; a child of
--   the pane at its level +50, the mask over maskRegion (default the pane) at
--   the pane's +30, a 20-px title row, the `pane` fill and a 1-px accent edge;
--   centred on maskRegion until the caller anchors it. sheet:Body() is the
--   area under the title. Only one sheet is open at a time: showing one hides
--   the other.
--------------------------------------------------------------------------------
function UI.CreateMask(region, level, text)
    local m = CreateFrame("Frame", nil, region)
    m:SetAllPoints(region)
    m:SetFrameLevel(level or (region:GetFrameLevel() + 30))
    m:EnableMouse(true)
    if m.EnableMouseWheel then m:EnableMouseWheel(true) end
    m:SetScript("OnMouseWheel", function() end)
    local tex = m:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(m)
    TintFill(tex, "mask", { 0.15, 0.15, 0.15, 0.7 }) -- T107
    function m:SetText(t)
        if not m.text then
            if t == nil or t == "" then return end
            local fs = m:CreateFontString(nil, "OVERLAY", UI.FONT)
            fs:SetPoint("LEFT", m, "LEFT", 8, 0)
            fs:SetPoint("RIGHT", m, "RIGHT", -8, 0)
            UI.Tint(fs, "text", "text2")
            m.text = fs
        end
        m.text:SetText(t or "")
    end
    if text then m:SetText(text) end
    m:Hide()
    return m
end

function UI.CreateSheet(pane, maskRegion, w, h, title)
    maskRegion = maskRegion or pane
    local base = pane:GetFrameLevel()
    local mask = UI.CreateMask(maskRegion, base + 30)

    local s = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    s:SetSize(w, h)
    s:SetPoint("CENTER", maskRegion, "CENTER", 0, 0)
    s:SetFrameLevel(base + 50)
    s:EnableMouse(true)
    -- T107: the accent edge as a name, so the skin repaints it in a new style
    UI.StylizeFrame(s, Fill("pane", { 0.11, 0.11, 0.11, 1 }), UI.AccentSpec(1))
    s.mask = mask

    local bar = s:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", s, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", s, "TOPRIGHT", -1, -1)
    bar:SetHeight(20)
    TintFill(bar, Fill("nav") and "nav" or "header", { 0.115, 0.115, 0.115, 1 }) -- T107
    local edge = s:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
    edge:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    edge:SetHeight(1)
    edge:SetColorTexture(0, 0, 0, 1)

    s.title = s:CreateFontString(nil, "OVERLAY", UI.FONT_CLASS)
    s.title:SetJustifyH("LEFT")
    s.title:SetPoint("LEFT", bar, "LEFT", 7, 0)
    s.title:SetText(title or "")
    function s:SetTitle(t) s.title:SetText(t or "") end

    -- T75 (P31, review U31): under the theme a sheet has the window's 20x20 x
    -- at the right of its title row (inside the 1-px edge); a click hides the
    -- sheet like Done, so the OnHide hooks (the mask, the ESC entry) run. A
    -- title-row button the caller anchors to the sheet's TOPRIGHT goes left of
    -- it (UI.CreateButton). TBC builds no sheet.
    s.isSheet = true
    if UI.THEMED then
        local x = UI.CreateButton(s, "x", "red", { 20, 20 }, false, false, UI.FONT_SPECIAL, UI.FONT_SPECIAL)
        x:SetPoint("TOPRIGHT", s, "TOPRIGHT", -1, -1)
        UI.PixelLayout(x, function(btn)
            local e = UI.px(1, btn)
            btn:ClearAllPoints()
            btn:SetPoint("TOPRIGHT", s, "TOPRIGHT", -e, -e)
        end)
        x:SetScript("OnClick", function() s:Hide() end)
        s.closeBtn = x
    end

    local body = CreateFrame("Frame", nil, s)
    body:SetPoint("TOPLEFT", s, "TOPLEFT", 1, -22)
    body:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -1, 1)
    function s:Body() return body end

    s:Hide()
    s:SetScript("OnShow", function(self)
        if UI.openSheet and UI.openSheet ~= self then UI.openSheet:Hide() end
        UI.openSheet = self
        mask:Show()
    end)
    s:SetScript("OnHide", function(self)
        mask:Hide()
        if UI.openSheet == self then UI.openSheet = nil end
    end)
    return s
end

--------------------------------------------------------------------------------
-- Dropdown: a button that says what is selected and drops a list under it.
--
-- The kit had button groups and nothing else, which is fine for two or three
-- short labels and wrong for four long ones -- four strategy names beside the
-- replay's column title ran off the window (v0.11.11). A dropdown costs one
-- control's width whatever the labels say.
--
-- UI.CreateDropdown(parent, width, height, onSelect) -> dd
--   dd:SetItems({ { id, text, tooltip }, ... })
--   dd:SetValue(id)   -- no callback
--   dd:Value()
--   dd:Close()
--------------------------------------------------------------------------------
function UI.CreateDropdown(parent, width, height, onSelect)
    height = height or 18
    local dd = UI.CreateButton(parent, "", "accent-hover", { width, height }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL)
    dd.items, dd.rows, dd.value = {}, {}, nil

    -- T77 (P33): the chevron -- an 8 x 8 texture under the theme, else the
    -- letter "v" (TBC's, unchanged)
    local arrow = UI.CreateChevron(dd, "down")
    arrow:SetPoint("RIGHT", dd, "RIGHT", -4, 0)
    dd.arrow = arrow

    local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -1)
    list:SetWidth(width)
    -- T31 (6.2): the lists' strata is the kit's setting; nil is today's DIALOG
    -- (TBC's), the Forever theme lifts it above the replay's
    list:SetFrameStrata(UI.LIST_STRATA or "DIALOG")
    UI.Skin(list, "list", UI.PALETTE.header, "border") -- T94: by role
    list:Hide()
    WatchPopup(list)   -- T31: UI.OnPopup told, once it exists (after the first Hide)
    dd.list = list

    local function Label(id)
        for _, it in ipairs(dd.items) do if it.id == id then return it.text end end
        return ""
    end

    function dd:Close() list:Hide() end

    function dd:SetValue(id)
        dd.value = id
        dd:SetText(Label(id))
    end

    function dd:Value() return dd.value end

    function dd:SetItems(items)
        dd.items = items or {}
        for _, r in ipairs(dd.rows) do r:Hide() end
        local prev
        for i, it in ipairs(dd.items) do
            local r = dd.rows[i]
            if not r then
                r = UI.CreateButton(list, "", "accent-hover", { width - 2, height }, true, false,
                    UI.FONT_SMALL, UI.FONT_SMALL)
                dd.rows[i] = r
            end
            r:SetText(it.text)
            r:ClearAllPoints()
            if prev then r:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1)
            else r:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -1) end
            if it.tooltip then UI.SetTooltips(r, "ANCHOR_RIGHT", 0, 0, it.text, it.tooltip) end
            r:SetScript("OnClick", function()
                dd:SetValue(it.id)
                list:Hide()
                if onSelect then onSelect(it.id) end
            end)
            r:Show()
            prev = r
        end
        list:SetHeight(math.max(height, #dd.items * (height - 1) + 3))
        if dd.value == nil and dd.items[1] then dd:SetValue(dd.items[1].id) end
    end

    -- T77 (P33, review U12): below the button, or above it when below would
    -- leave the screen (UI.ListSide); the chevron points the way it opened
    function dd:PlaceList()
        local side = UI.ListSide(dd, list)
        list:ClearAllPoints()
        if side == "up" then list:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 0, 1)
        else list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -1) end
        if UI.THEMED then arrow:SetDirection(side) end
        dd.side = side
        return side
    end

    dd:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() else dd:PlaceList(); list:Show() end
    end)
    dd:SetScript("OnHide", function() list:Hide() end)

    return dd
end

--------------------------------------------------------------------------------
-- Tree dropdown (v0.15.2): the same button and list, one level deeper. An item
-- with `children` opens them in a second list beside it on hover, and clicking
-- the parent itself picks the parent.
--
-- It exists because a flat list of every rank of every spell is 40 rows long:
-- it ran off the bottom of the bindings window, and picking Rejuvenation Rank 5
-- meant reading past nine Lifeblooms. Five families, hover one, see its ranks.
--------------------------------------------------------------------------------
function UI.CreateTreeDropdown(parent, width, height, onSelect)
    height = height or 18
    local dd = UI.CreateButton(parent, "", "accent-hover", { width, height }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL)
    dd.items, dd.rows, dd.subRows, dd.value = {}, {}, {}, nil

    -- T77 (P33): as the flat dropdown's
    local arrow = UI.CreateChevron(dd, "down")
    arrow:SetPoint("RIGHT", dd, "RIGHT", -4, 0)
    dd.arrow = arrow

    local function Panel(strata)
        local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        f:SetFrameStrata(strata)
        UI.Skin(f, "list", UI.PALETTE.header, "border") -- T94: by role
        f:Hide()
        return f
    end
    -- T31 (6.2): the first list in the kit's list strata (nil: today's DIALOG),
    -- the second in FULLSCREEN_DIALOG as before and always above the first by
    -- level too -- once the theme puts both in one strata, only the level
    -- keeps the second on top
    local list = Panel(UI.LIST_STRATA or "DIALOG")
    list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -1)
    list:SetWidth(width)
    local sub = Panel("FULLSCREEN_DIALOG")
    sub:SetWidth(width)
    sub:SetFrameLevel(list:GetFrameLevel() + 10)
    dd.list, dd.sub = list, sub
    WatchPopup(list)
    list:HookScript("OnHide", function() sub:Hide() end)   -- the second list goes with the first

    local function Label(id)
        for _, it in ipairs(dd.items) do
            if it.id == id then return it.text end
            for _, c in ipairs(it.children or {}) do
                if c.id == id then return c.text end
            end
        end
        return ""
    end

    function dd:Close() sub:Hide(); list:Hide() end
    function dd:SetValue(id) dd.value = id; dd:SetText(Label(id)) end
    function dd:Value() return dd.value end

    local function Pick(id)
        dd:SetValue(id)
        dd:Close()
        if onSelect then onSelect(id) end
    end

    -- the children of one parent row, beside it
    local function ShowChildren(row, children)
        for _, r in ipairs(dd.subRows) do r:Hide() end
        if not children or #children == 0 then sub:Hide(); return end
        local prev
        for i, c in ipairs(children) do
            local r = dd.subRows[i]
            if not r then
                r = UI.CreateButton(sub, "", "accent-hover", { width - 2, height }, true, false,
                    UI.FONT_SMALL, UI.FONT_SMALL)
                dd.subRows[i] = r
            end
            r:SetText(c.text)
            r:ClearAllPoints()
            if prev then r:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1)
            else r:SetPoint("TOPLEFT", sub, "TOPLEFT", 1, -1) end
            r:SetScript("OnClick", function() Pick(c.id) end)
            r:Show()
            prev = r
        end
        sub:SetHeight(math.max(height, #children * (height - 1) + 3))
        sub:SetFrameLevel(list:GetFrameLevel() + 10)   -- T31
        sub:ClearAllPoints()
        -- T77 (P33, review U12): right of the row, or left of it when the
        -- right would leave the screen (UI.SubListSide)
        local side = UI.SubListSide(row, sub, 2)
        if side == "left" then sub:SetPoint("TOPRIGHT", row, "TOPLEFT", -2, 1)
        else sub:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 1) end
        dd.subSide = side
        if row.chevron then row.chevron:SetDirection(side) end
        sub:Show()
    end

    function dd:SetItems(items)
        dd.items = items or {}
        for _, r in ipairs(dd.rows) do r:Hide() end
        sub:Hide()
        local prev
        for i, it in ipairs(dd.items) do
            local r = dd.rows[i]
            if not r then
                r = UI.CreateButton(list, "", "accent-hover", { width - 2, height }, true, false,
                    UI.FONT_SMALL, UI.FONT_SMALL)
                dd.rows[i] = r
            end
            -- T77 (P33): under the theme a parent row's chevron is a texture at
            -- its right edge; TBC keeps the grey ">" in the text
            local parentRow = it.children and #it.children > 0
            if UI.THEMED then
                r:SetText(it.text)
                if parentRow and not r.chevron then
                    r.chevron = UI.CreateChevron(r, "right")
                    r.chevron:SetPoint("RIGHT", r, "RIGHT", -6, 0)
                end
                if r.chevron then
                    r.chevron:SetDirection("right")
                    r.chevron:SetShown(parentRow)
                end
            else
                r:SetText(it.text .. (parentRow and "   |cff777777>|r" or ""))
            end
            r.item = it
            r:ClearAllPoints()
            if prev then r:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1)
            else r:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -1) end
            if it.tooltip then UI.SetTooltips(r, "ANCHOR_RIGHT", 0, 0, it.text, it.tooltip) end
            r:SetScript("OnClick", function() Pick(it.id) end)
            -- the button's own hover (and its tooltip, if it has one) is kept and
            -- called first: a hook would be a second handler on some clients and
            -- a replacement on others, and this has to be neither
            r.baseEnter = r.baseEnter or r:GetScript("OnEnter")
            local kids = it.children
            r:SetScript("OnEnter", function(self, ...)
                if r.baseEnter then r.baseEnter(self, ...) end
                ShowChildren(self, kids)
            end)
            r:Show()
            prev = r
        end
        list:SetHeight(math.max(height, #dd.items * (height - 1) + 3))
        if dd.value == nil and dd.items[1] then dd:SetValue(dd.items[1].id) end
    end

    -- T77 (P33): as the flat dropdown's
    function dd:PlaceList()
        local side = UI.ListSide(dd, list)
        list:ClearAllPoints()
        if side == "up" then list:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 0, 1)
        else list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -1) end
        if UI.THEMED then arrow:SetDirection(side) end
        dd.side = side
        return side
    end

    dd:SetScript("OnClick", function()
        if list:IsShown() then dd:Close() else dd:PlaceList(); list:Show() end
    end)
    dd:SetScript("OnHide", function() dd:Close() end)
    return dd
end

--------------------------------------------------------------------------------
-- Check button
--------------------------------------------------------------------------------
-- UI.CreateCheckButton(parent, label, onClick(checked, cb), tooltip...)
function UI.CreateCheckButton(parent, label, onClick, ...)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb.onClick = onClick
    cb:SetScript("OnClick", function(self)
        if SOUNDKIT then
            PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end
        if cb.onClick then cb.onClick(self:GetChecked() and true or false, self) end
    end)

    cb.label = cb:CreateFontString(nil, "OVERLAY", UI.FONT)
    cb.label:SetText(label or "")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 5, 0)

    cb:SetSize(14, 14)
    if label and strtrim(label) ~= "" then
        cb:SetHitRectInsets(0, -cb.label:GetStringWidth() - 5, 0, 0)
    end
    -- T75 (P31, review U30): under the theme the click area is measured from
    -- the label again whenever the box shows (the font offset may have moved
    -- since it was made) and by cb:Measure(); TBC measures once, as before.
    if UI.THEMED then
        function cb:Measure()
            local t = cb.label:GetText()
            if t and strtrim(t) ~= "" then
                cb:SetHitRectInsets(0, -UI.TextWidth(t, UI.FONT, cb.label) - 5, 0, 0)
            else
                cb:SetHitRectInsets(0, 0, 0, 0)
            end
        end
        cb:HookScript("OnShow", function() cb:Measure() end)
    end

    -- T74 (P30): the colours are tokens, the edge one pixel under UI.PIXEL
    -- T107: under UI.PIXEL the skin painted these two (a style's edge
    -- included); the tokens by hand only where nothing else does
    ControlBackdrop(cb, UI.PALETTE.field, false, "field")
    if not UI.PIXEL then
        UI.Tint(cb, "backdrop", "field")
        UI.Tint(cb, "border", "border")
    end

    local checkedTexture = cb:CreateTexture(nil, "ARTWORK")
    UI.Tint(checkedTexture, "texture", "check")
    checkedTexture:SetPoint("TOPLEFT", 1, -1)
    checkedTexture:SetPoint("BOTTOMRIGHT", -1, 1)

    local highlightTexture = cb:CreateTexture(nil, "ARTWORK")
    UI.Tint(highlightTexture, "texture", "checkHover")
    highlightTexture:SetPoint("TOPLEFT", 1, -1)
    highlightTexture:SetPoint("BOTTOMRIGHT", -1, 1)

    -- T74 (P30, review U3): the tick and the hover inside a one-pixel edge
    local function Inset(t)
        local e = UI.px(1, cb)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", e, -e)
        t:SetPoint("BOTTOMRIGHT", -e, e)
    end
    UI.PixelLayout(checkedTexture, Inset)
    UI.PixelLayout(highlightTexture, Inset)

    cb:SetCheckedTexture(checkedTexture)
    cb:SetHighlightTexture(highlightTexture, "ADD")

    cb:SetScript("OnEnable", function()
        UI.Tint(cb.label, "text", "text")
        UI.Tint(checkedTexture, "texture", "check")
        -- T107: the role's own edge again (the skin), else the token
        if UI.PIXEL then UI.Skin(cb, "field", UI.PALETTE.field, "border")
        else UI.Tint(cb, "border", "border") end
    end)
    cb:SetScript("OnDisable", function()
        UI.Tint(cb.label, "text", "dimmed")
        UI.Tint(checkedTexture, "texture", "dimmed")
        UI.Untint(cb, "border")
        local r, g, b = UI.Fill("border")
        cb:SetBackdropBorderColor(r, g, b, 0.4)
    end)

    function cb:SetText(text)
        cb.label:SetText(text)
        if strtrim(text) ~= "" then
            cb:SetHitRectInsets(0, -cb.label:GetStringWidth() - 5, 0, 0)
        else
            cb:SetHitRectInsets(0, 0, 0, 0)
        end
    end

    UI.SetTooltips(cb, "ANCHOR_TOPLEFT", 0, 3, ...)
    return cb
end

--------------------------------------------------------------------------------
-- Edit boxes
--------------------------------------------------------------------------------
function UI.CreateEditBox(parent, width, height, isTransparent, isMultiLine, isNumeric, font)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    if not isTransparent then UI.Skin(eb, "field", UI.PALETTE.field, "border") end -- T74: the token; T94: by role
    eb:SetFontObject(font or UI.FONT)
    eb:SetMultiLine(isMultiLine)
    eb:SetMaxLetters(0)
    eb:SetJustifyH("LEFT")
    eb:SetJustifyV("MIDDLE")
    eb:SetWidth(width or 0)
    eb:SetHeight(height or 0)
    eb:SetTextInsets(5, 5, 0, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(isNumeric)
    eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function() eb:HighlightText() end)
    eb:SetScript("OnEditFocusLost", function() eb:HighlightText(0, 0) end)
    eb:SetScript("OnDisable", function()
        UI.Tint(eb, "text", "dimmed", 1) -- T107
    end)
    eb:SetScript("OnEnable", function()
        UI.Tint(eb, "text", "text", 1)
    end)
    return eb
end

--------------------------------------------------------------------------------
-- Scroll frame with a 5px accent scrollbar (mouse wheel + draggable thumb)
--------------------------------------------------------------------------------
function UI.CreateScrollFrame(parent, top, bottom, color, border)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "BackdropTemplate")
    parent.scrollFrame = scrollFrame
    top = top or 0
    bottom = bottom or 0
    scrollFrame:SetPoint("TOPLEFT", 0, top)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, bottom)
    if color then UI.StylizeFrame(scrollFrame, color, border) end

    function scrollFrame:Resize(newTop, newBottom)
        top, bottom = newTop, newBottom
        scrollFrame:SetPoint("TOPLEFT", 0, top)
        scrollFrame:SetPoint("BOTTOMRIGHT", 0, bottom)
    end

    local content = CreateFrame("Frame", nil, scrollFrame, "BackdropTemplate")
    content:SetSize(scrollFrame:GetWidth(), 2)
    scrollFrame:SetScrollChild(content)
    scrollFrame.content = content

    local scrollbar = CreateFrame("Frame", nil, scrollFrame, "BackdropTemplate")
    scrollbar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 2, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", scrollFrame, 7, 0)
    scrollbar:Hide()
    UI.StylizeFrame(scrollbar, UI.PALETTE.track) -- T74: the token
    scrollFrame.scrollbar = scrollbar

    local scrollThumb = CreateFrame("Frame", nil, scrollbar, "BackdropTemplate")
    scrollThumb:SetWidth(5)
    scrollThumb:SetHeight(scrollbar:GetHeight())
    scrollThumb:SetPoint("TOP")
    UI.StylizeFrame(scrollThumb, UI.PALETTE.thumb)
    scrollThumb:EnableMouse(true)
    scrollThumb:SetMovable(true)
    scrollThumb:SetHitRectInsets(-5, -5, 0, 0)
    scrollFrame.scrollThumb = scrollThumb

    function scrollFrame:ResetHeight() content:SetHeight(2) end

    function scrollFrame:ResetScroll()
        scrollFrame:SetVerticalScroll(0)
        scrollThumb:SetPoint("TOP")
    end

    function scrollFrame:GetVerticalScrollRange()
        local range = content:GetHeight() - scrollFrame:GetHeight()
        return range > 0 and range or 0
    end

    function scrollFrame:VerticalScroll(step)
        local scroll = scrollFrame:GetVerticalScroll() + step
        if scroll <= 0 then
            scrollFrame:SetVerticalScroll(0)
        elseif scroll >= scrollFrame:GetVerticalScrollRange() then
            scrollFrame:SetVerticalScroll(scrollFrame:GetVerticalScrollRange())
        else
            scrollFrame:SetVerticalScroll(scroll)
        end
    end

    function scrollFrame:ScrollToBottom()
        scrollFrame:SetVerticalScroll(scrollFrame:GetVerticalScrollRange())
    end

    function scrollFrame:SetContentHeight(height, num, spacing)
        if num and spacing then
            content:SetHeight(num * height + (num - 1) * spacing)
        else
            content:SetHeight(height)
        end
    end

    scrollFrame:SetScript("OnSizeChanged", function()
        content:SetWidth(scrollFrame:GetWidth())
    end)

    content:SetScript("OnSizeChanged", function()
        local p = scrollFrame:GetHeight() / math.max(content:GetHeight(), 1)
        p = tonumber(string.format("%.3f", p))
        if p < 1 then
            scrollThumb:SetHeight(scrollbar:GetHeight() * p)
            scrollFrame:SetPoint("BOTTOMRIGHT", parent, -7, bottom)
            scrollbar:Show()
        else
            scrollFrame:SetPoint("BOTTOMRIGHT", parent, 0, bottom)
            scrollbar:Hide()
            if scrollFrame:GetVerticalScroll() > 0 then scrollFrame:SetVerticalScroll(0) end
        end
    end)

    scrollThumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local offsetY = select(5, scrollThumb:GetPoint(1)) or 0
        local mouseY = select(2, GetCursorPosition())
        local uiScale = UIParent:GetEffectiveScale()
        self:SetScript("OnUpdate", function()
            local newOffsetY = offsetY + (select(2, GetCursorPosition()) - mouseY) / uiScale
            if newOffsetY >= 0 then
                scrollThumb:SetPoint("TOP")
                newOffsetY = 0
            elseif (-newOffsetY) + scrollThumb:GetHeight() >= scrollbar:GetHeight() then
                scrollThumb:SetPoint("TOP", 0, -(scrollbar:GetHeight() - scrollThumb:GetHeight()))
                newOffsetY = -(scrollbar:GetHeight() - scrollThumb:GetHeight())
            else
                scrollThumb:SetPoint("TOP", 0, newOffsetY)
            end
            local track = scrollbar:GetHeight() - scrollThumb:GetHeight()
            if track > 0 then
                scrollFrame:SetVerticalScroll((-newOffsetY / track) * scrollFrame:GetVerticalScrollRange())
            end
        end)
    end)
    scrollThumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)

    scrollFrame:SetScript("OnVerticalScroll", function()
        local range = scrollFrame:GetVerticalScrollRange()
        if range ~= 0 then
            local scrollP = scrollFrame:GetVerticalScroll() / range
            scrollThumb:SetPoint("TOP", 0, -((scrollbar:GetHeight() - scrollThumb:GetHeight()) * scrollP))
        end
    end)

    local step = 25
    function scrollFrame:SetScrollStep(s) step = s end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        if delta == 1 then
            scrollFrame:VerticalScroll(-step)
        elseif delta == -1 then
            scrollFrame:VerticalScroll(step)
        end
    end)

    return scrollFrame
end

-- Multi-line edit box inside a scroll frame (used by the copy popup).
function UI.CreateScrollEditBox(parent, onTextChanged, scrollStep)
    scrollStep = scrollStep or 1
    local frame = CreateFrame("Frame", nil, parent)
    UI.CreateScrollFrame(frame)
    UI.StylizeFrame(frame.scrollFrame, UI.PALETTE.well) -- T74: the token

    frame.eb = UI.CreateEditBox(frame.scrollFrame.content, 10, 20, true, true)
    frame.eb:SetPoint("TOPLEFT")
    frame.eb:SetPoint("RIGHT")
    frame.eb:SetTextInsets(2, 2, 2, 2)
    frame.eb:SetScript("OnEditFocusGained", nil)
    frame.eb:SetScript("OnEditFocusLost", nil)
    frame.eb:SetScript("OnEnterPressed", function(self) self:Insert("\n") end)

    frame.eb:SetScript("OnCursorChanged", function(self, _, y, cursorWidth, lineHeight)
        frame.scrollFrame:SetScrollStep((lineHeight + frame.eb:GetSpacing()) * scrollStep)
        local vs = frame.scrollFrame:GetVerticalScroll()
        local h = frame.scrollFrame:GetHeight()
        local cursorHeight = lineHeight - y
        if vs + y > 0 then
            frame.scrollFrame:SetVerticalScroll(-y)
        elseif cursorHeight > h + vs then
            frame.scrollFrame:SetVerticalScroll(-y - h + lineHeight + (cursorWidth or 0))
        end
        if frame.scrollFrame:GetVerticalScroll() > frame.scrollFrame:GetVerticalScrollRange() then
            frame.scrollFrame:ScrollToBottom()
        end
    end)

    frame.eb:SetScript("OnTextChanged", function(self, userChanged)
        frame.scrollFrame:SetContentHeight(self:GetHeight())
        if onTextChanged then onTextChanged(self, userChanged) end
    end)

    frame.scrollFrame:SetScript("OnMouseDown", function() frame.eb:SetFocus(true) end)

    function frame:SetText(text)
        frame.eb:SetText(text)
        frame.scrollFrame:ResetScroll()
        frame.eb:SetCursorPosition(0)
    end
    function frame:GetText() return frame.eb:GetText() end
    function frame:SetEnabled(enabled) frame.eb:SetEnabled(enabled) end
    return frame
end

--------------------------------------------------------------------------------
-- Slider: label above, value edit box below the middle, low/high captions
--------------------------------------------------------------------------------
-- UI.CreateSlider(name, parent, low, high, width, step, onValueChanged, afterValueChanged, isPercentage, tooltip...)
function UI.CreateSlider(name, parent, low, high, width, step, onValueChangedFn, afterValueChangedFn, isPercentage, ...)
    local tooltips = { ... }
    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(width, 10)
    local unit = isPercentage and "%" or ""
    UI.StylizeFrame(slider, UI.PALETTE.button) -- T74: the token

    local label = slider:CreateFontString(nil, "OVERLAY", UI.FONT)
    label:SetText(name)
    label:SetPoint("BOTTOM", slider, "TOP", 0, 2)
    function slider:SetLabel(n) label:SetText(n) end

    local currentEditBox = UI.CreateEditBox(slider, 48, 14)
    slider.currentEditBox = currentEditBox
    currentEditBox:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", math.ceil(width / 2 - 24), -1)
    currentEditBox:SetJustifyH("CENTER")
    currentEditBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    currentEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local value = tonumber(self:GetText())
        if value == self.oldValue then return end
        if value then
            if value < slider.low then value = slider.low end
            if value > slider.high then value = slider.high end
            self:SetText(value)
            slider:SetValue(value)
            if slider.onValueChangedFn then slider.onValueChangedFn(value) end
            if slider.afterValueChangedFn then slider.afterValueChangedFn(value) end
        else
            self:SetText(self.oldValue)
        end
    end)
    currentEditBox:SetScript("OnShow", function(self)
        if self.oldValue then self:SetText(self.oldValue) end
    end)

    local lowText = slider:CreateFontString(nil, "OVERLAY", UI.FONT)
    slider.lowText = lowText
    lowText:SetTextColor(unpack(UI.grey))
    lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -1)
    lowText:SetPoint("BOTTOM", currentEditBox)

    local highText = slider:CreateFontString(nil, "OVERLAY", UI.FONT)
    slider.highText = highText
    highText:SetTextColor(unpack(UI.grey))
    highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -1)
    highText:SetPoint("BOTTOM", currentEditBox)

    local tex = slider:CreateTexture(nil, "ARTWORK")
    UI.Tint(tex, "texture", "check") -- T107
    tex:SetSize(8, 8)
    slider:SetThumbTexture(tex)

    local valueBeforeClick
    slider.onEnter = function()
        UI.Tint(tex, "texture", "check", 1)
        valueBeforeClick = slider:GetValue()
        if #tooltips > 0 then ShowTooltips(slider, "ANCHOR_TOPLEFT", 0, 3, tooltips) end
    end
    slider:SetScript("OnEnter", slider.onEnter)
    slider.onLeave = function()
        UI.Tint(tex, "texture", "check")
        tooltip:Hide()
    end
    slider:SetScript("OnLeave", slider.onLeave)

    slider.onValueChangedFn = onValueChangedFn
    slider.afterValueChangedFn = afterValueChangedFn

    local oldValue
    slider:SetScript("OnValueChanged", function(_, value, userChanged)
        if oldValue == value then return end
        oldValue = value
        if math.floor(value) < value then value = tonumber(string.format("%.2f", value)) end
        currentEditBox:SetText(value)
        currentEditBox.oldValue = value
        if userChanged and slider.onValueChangedFn then slider.onValueChangedFn(value) end
    end)

    slider:SetScript("OnMouseUp", function()
        if not slider:IsEnabled() then return end
        if valueBeforeClick ~= oldValue and slider.afterValueChangedFn then
            valueBeforeClick = oldValue
            local value = slider:GetValue()
            if math.floor(value) < value then value = tonumber(string.format("%.2f", value)) end
            slider.afterValueChangedFn(value)
        end
    end)

    slider:SetValue(low)

    slider:SetScript("OnDisable", function()
        UI.Tint(label, "text", "dimmed")
        currentEditBox:SetEnabled(false)
        slider:SetScript("OnEnter", nil)
        slider:SetScript("OnLeave", nil)
        UI.Tint(tex, "texture", "dimmed", 0.7)
        UI.Tint(lowText, "text", "dimmed")
        UI.Tint(highText, "text", "dimmed")
    end)
    slider:SetScript("OnEnable", function()
        UI.Tint(label, "text", "text")
        currentEditBox:SetEnabled(true)
        slider:SetScript("OnEnter", slider.onEnter)
        slider:SetScript("OnLeave", slider.onLeave)
        UI.Tint(tex, "texture", "check")
        UI.Untint(lowText); UI.Untint(highText) -- the kit's literal grey, not a token
        lowText:SetTextColor(unpack(UI.grey))
        highText:SetTextColor(unpack(UI.grey))
    end)

    function slider:UpdateMinMaxValues(minV, maxV)
        slider:SetMinMaxValues(minV, maxV)
        slider.low, slider.high = minV, maxV
        lowText:SetText(minV .. unit)
        highText:SetText(maxV .. unit)
    end
    slider:UpdateMinMaxValues(low, high)

    return slider
end

--------------------------------------------------------------------------------
-- T107: a switch reaches the tinted regions, then the font strings the follow
-- finds -- registered here, as this file loads, so it runs before any pane's
-- own STYLE_CHANGED re-render (the clocks' NewLook, the Spells pane).
--------------------------------------------------------------------------------
MD:RegisterCallback("STYLE_CHANGED", function()
    UI.RepaintTints()
    UI.FollowTokens()
end)
