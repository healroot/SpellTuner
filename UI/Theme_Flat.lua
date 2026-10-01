-- T29 (docs/SPEC-forever-ui.md 4.1-4.3): the flat theme (UI/Theme_Forever.lua
-- until T80). T80 (C1 of docs/PLAN-refactor-ux.md, decision 10, the author's
-- answer 1): listed by every main TOC -- TBC's included -- right after
-- UI/Style.lua; at load, before any window is built, it writes the flat
-- palette into UI.PALETTE, the text colours into UI.TEXT, builds the new
-- fonts, and switches on the kit's pixel-snapped edges (UI.PIXEL) and the
-- dropdown lists' strata (UI.LIST_STRATA), and sets UI.THEMED (T69, P25), the
-- one switch every flat-look branch asks. Without it (a suite that loads
-- UI/Style.lua alone) UI.THEMED stays false and UI.TEXT / UI.PALETTE hold
-- Style.lua's old TBC values.
--
-- T94 (docs/SPEC-next.md 2.2, 5.1, S2): Flat is a STYLE now -- the data table
-- UI.FLAT below, which UI/Styles.lua (listed right after this file) registers
-- as "flat" -- and this file keeps the appliers every style goes through:
-- UI.ApplyStyleTokens (the palette and the tokens, written IN PLACE, the
-- `{ ref = "accent" }` fills resolved against the style's accent) and
-- UI.ReFaceFonts (the faces, flags and shadow; sizes never). At load it applies
-- Flat itself, exactly what it wrote before, so nothing changes while no other
-- style is chosen; UI/Styles.lua applies the saved style at CORE_LOGIN.
--
-- It owns db.ui.fontOffset (T80: declared here with MD:RegisterDefaults) and
-- UI.SetFontOffset, which both Settings panes call.
--
-- No client data is read here: the accent is Style.lua's (UnitClass through
-- the adapter, RAID_CLASS_COLORS), the font face is GameFontNormal's.
local _, MD = ...
local UI = MD.UI

--------------------------------------------------------------------------------
-- Flat, as data (5.1's first table). Every key a style may set is here: a
-- style that leaves one out takes Flat's, so Flat restores whatever another
-- style changed. Fills are r, g, b, a or { ref = "accent", a = n }; text
-- tokens a six-digit hex or { ref = "accent" }.
--------------------------------------------------------------------------------
local function Grey(byte, a) local v = byte / 255; return { v, v, v, a } end
local function Accent(a) return { ref = "accent", a = a } end

UI.FLAT = {
    name = "Flat",
    hint = "SpellTuner's own look: flat panels, 1-px edges, your class colour.",
    accent = "class",
    palette = {
        -- 4.1: the theme's fills
        bg        = Grey(0x16, 0.96),             -- window body: near-opaque
        pane      = Grey(0x1C, 1),                -- rail, chip, cards, sheets
        nav       = { 0.115, 0.115, 0.115, 1 },   -- #1D1D1D, Cell's 0.115: header, nav, buttons
        border    = { 0, 0, 0, 1 },               -- 1-px edges (UI.px)
        rule      = Accent(0.6),                  -- the line under a pane title
        line      = Grey(0x2A, 1),                -- table header rule, rail separators
        rowAlt    = { 1, 1, 1, 0.03 },            -- zebra on even rows
        hover     = Accent(0.12),                 -- row and list hover
        selected  = Accent(0.28),                 -- selected rail row / rank (+ a 2-px bar)
        suggested = Accent(0.10),                 -- the suggested rank's row (+ a 2-px bar)
        mask      = Grey(0x26, 0.7),              -- behind a sheet
        close     = { 0.6, 0.1, 0.1, 0.6 },       -- the x button, as in Cell
        closeHover = { 0.6, 0.1, 0.1, 1 },
        -- the kit's own fills (UI/Style.lua's literals, which the theme kept)
        button      = { 0.115, 0.115, 0.115, 1 },
        buttonHover = { 0.23, 0.23, 0.23, 1 },
        field       = { 0.115, 0.115, 0.115, 0.9 },
        well        = { 0.15, 0.15, 0.15, 0.9 },
        track       = { 0.1, 0.1, 0.1, 0.8 },
        thumb       = Accent(0.8),
        check       = Accent(0.7),
        checkHover  = Accent(0.1),
        accentFill  = Accent(0.3),
        accentHover = Accent(0.6),
        go          = { 0.1, 0.6, 0.1, 0.6 },
        goHover     = { 0.1, 0.6, 0.1, 1 },
        info        = { 0, 0.5, 0.8, 1 },
        warn        = { 0.7, 0.7, 0, 1 },
        clear       = { 0, 0, 0, 0 },
        tip         = { 0.1, 0.1, 0.1, 0.9 },
    },
    -- 4.1's text colours. No Blizzard gold here: the accent is the class
    -- colour (decision 2: "no gold" is this style's rule).
    text = {
        accent   = { ref = "accent" },  -- titles, rules, selection
        text     = "FFFFFF",   -- values
        -- T78 (P34, review U7; mockup M5): text2 (B3B3B3) and label (9D9D9D)
        -- could not be told apart through the shadow, so they are one grey
        -- now, the lighter of the two; `text2` is an alias (UI.STYLE_ALIASES)
        label    = "B3B3B3",   -- labels, headers, tags, secondary lines, spell text
        muted    = "7A7A7A",   -- explanations, hints, footers
        disabled = "4D4D4D",   -- inert controls; the numbers of a rank you do not have
        mana     = "4D99FF",   -- modelled mana figures (the clock bar's 0.3/0.6/1)
        good     = "5CCB6E",   -- measure verdicts
        bad      = "E0605A",   -- measure verdicts, the stale warning
        dimmed   = "666666",   -- T74: the kit's disabled controls (Style.lua's, kept)
    },
    -- 4.2: Friz (GameFontNormal's face) for text, Arial Narrow for numbers,
    -- no outline, a black shadow at (1, -1)
    fonts = { face = "FRIZ", num = "Fonts\\ARIALN.TTF", flags = "", shadow = { 1, -1 } },
    -- one recipe per role (docs/SPEC-next.md 2.2): the painter, and the fill
    -- and edge UI.Skin takes when its caller names none. The clock's is the
    -- clocks' own panel (T82, M6): the `bg` fill and a 1-px `border` edge; its
    -- 160 x 4 bar sits on black (the layouts, T98, read `bar`).
    roles = {
        window    = { kind = "pixel", fill = "bg",     edge = "border" },
        header    = { kind = "pixel", fill = "nav",    edge = "border" },
        nav       = { kind = "pixel", fill = "nav",    edge = "border" },
        pane      = { kind = "pixel", fill = "pane",   edge = "border" },
        button    = { kind = "pixel", fill = "button", edge = "border" },
        tab       = { kind = "pixel", fill = "button", edge = "border" },
        field     = { kind = "pixel", fill = "field",  edge = "border" },
        list      = { kind = "pixel", fill = "nav",    edge = "border" },
        scroll    = { kind = "pixel", fill = "track",  edge = "border" },
        tooltip   = { kind = "pixel", fill = "tip",    edge = "border" },
        clock     = { kind = "pixel", fill = "bg",     edge = "border", bar = { 0, 0, 0, 1 } },
        statusbar = { kind = "pixel", fill = "track",  edge = "border" },
        rule      = { kind = "pixel", fill = "line",   edge = "border" },
    },
    needs = {},
}

-- Names that are one table under two keys: the kit's old keys follow the
-- theme's (frame = bg, header = nav), and the legacy tokens read 4.1's
-- (text2, dominated, note, tipGold; T78). Structure, not a style's to set.
UI.STYLE_ALIASES = {
    palette = { frame = "bg", header = "nav" },
    text = { text2 = "label", dominated = "text", note = "label", tipGold = "accent" },
}

--------------------------------------------------------------------------------
-- The appliers
--------------------------------------------------------------------------------
local FRIZ = (GameFontNormal:GetFont())

-- UI.StyleAccent(style) -> r, g, b, hex ("rrggbb", lower case), and whether
-- it is the class colour. "class" (and "follow" until the Ellesmere style
-- answers it, T100) is the class colour as Style.lua read it; "gold" is
-- NORMAL_FONT_COLOR's; a table is that colour.
function UI.StyleAccent(style)
    local a = style and style.accent
    if a == "gold" then return 1, 0.82, 0, "ffd100", false end
    if type(a) == "table" then
        local r, g, b = a[1], a[2], a[3]
        return r, g, b, string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5)), false
    end
    local C = UI.classAccent or UI.accent
    local hex = type(UI.classAccentHex) == "string" and UI.classAccentHex:match("^|c[fF][fF](%x%x%x%x%x%x)$")
    if not hex then
        hex = string.format("%02x%02x%02x", math.floor(C[1] * 255 + 0.5), math.floor(C[2] * 255 + 0.5),
            math.floor(C[3] * 255 + 0.5))
    end
    return C[1], C[2], C[3], hex:lower(), true
end

-- UI.ApplyStyleTokens(style): the accent (UI.accent rewritten in place,
-- UI.accentHex), every fill into UI.PALETTE and every token into UI.TEXT IN
-- PLACE -- a pane that captured a table keeps reading the style -- each key
-- the style leaves out taken from Flat, then the aliases.
function UI.ApplyStyleTokens(style)
    local flat = UI.FLAT
    local r, g, b, hex, isClass = UI.StyleAccent(style)
    local A = UI.accent
    A[1], A[2], A[3] = r, g, b
    UI.accentHex = isClass and UI.classAccentHex or ("|cff" .. hex)

    local P = UI.PALETTE
    for key, base in pairs(flat.palette) do
        local spec = style.palette and style.palette[key]
        if spec == nil then spec = base end
        local c1, c2, c3, c4
        if spec.ref == "accent" then
            c1, c2, c3, c4 = r, g, b, spec.a or 1
        else
            c1, c2, c3, c4 = spec[1], spec[2], spec[3], spec[4]
        end
        local t = rawget(P, key)
        if type(t) ~= "table" then t = {}; P[key] = t end
        t[1], t[2], t[3], t[4] = c1, c2, c3, c4
    end
    for alias, to in pairs(UI.STYLE_ALIASES.palette) do P[alias] = P[to] end

    local T = UI.TEXT
    for key, base in pairs(flat.text) do
        local spec = style.text and style.text[key]
        if spec == nil then spec = base end
        local tok
        if type(spec) == "table" and spec.ref == "accent" then
            tok = UI.Token(hex, r, g, b)
        else
            tok = UI.Token(spec)
        end
        local t = rawget(T, key)
        if type(t) ~= "table" then t = {}; T[key] = t end
        t[1], t[2], t[3], t.hex = tok[1], tok[2], tok[3], tok.hex
    end
    for alias, to in pairs(UI.STYLE_ALIASES.text) do T[alias] = T[to] end
end

-- The faces the fonts are drawn in now: the active style's (Flat's at load).
local faces = { text = FRIZ, num = "Fonts\\ARIALN.TTF", flags = "", shadow = { 1, -1 } }
local function FaceOf(name)
    if name == nil or name == "FRIZ" then return FRIZ end
    return name
end

-- UI.THEMED: the one switch every flat-look branch asks (docs/PLAN-refactor-ux.md 2)
UI.THEMED = true

-- Flat, applied at load: the same palette, tokens and aliases this file wrote
-- before T94.
UI.ApplyStyleTokens(UI.FLAT)

--------------------------------------------------------------------------------
-- 4.2 Fonts: no outline, a black shadow at (1, -1). Friz (GameFontNormal's
-- face) for text, Arial Narrow for numbers (narrow, even-width digits).
--------------------------------------------------------------------------------
local function MakeFont(name, face, size)
    local f = UI.fontObjects[name] or _G[name] or CreateFont(name)
    UI.fontObjects[name] = f
    f:SetFont(face, size, "")
    f:SetTextColor(1, 1, 1, 1)
    f:SetShadowColor(0, 0, 0)
    f:SetShadowOffset(1, -1)
    f:SetJustifyH("CENTER")
    return f
end

local NUM = faces.num
UI.FONT_HEAD = "MANADEMON_FONT_HEAD";           MakeFont(UI.FONT_HEAD, FRIZ, 16)
UI.FONT_BIG = "MANADEMON_FONT_BIG";             MakeFont(UI.FONT_BIG, FRIZ, 18)
UI.FONT_NUM = "MANADEMON_FONT_NUM";             MakeFont(UI.FONT_NUM, NUM, 13)
UI.FONT_NUM_SMALL = "MANADEMON_FONT_NUM_SMALL"; MakeFont(UI.FONT_NUM_SMALL, NUM, 11)

-- Every font the kit and the theme build, at offset 0 (Style.lua's sizes for
-- its own eight), with the face it takes from the style: "text" or "num".
-- UI.ApplyFonts re-sizes these objects in place, so every FontString built
-- from one follows at once.
local BASE = {
    { UI.FONT_TITLE, "text", 14 }, { UI.FONT_TITLE_DISABLE, "text", 14 },
    { UI.FONT, "text", 13 }, { UI.FONT_DISABLE, "text", 13 },
    { UI.FONT_SMALL, "text", 11 }, { UI.FONT_SPECIAL, "text", 12 },
    { UI.FONT_CLASS_TITLE, "text", 14 }, { UI.FONT_CLASS, "text", 13 },
    { UI.FONT_HEAD, "text", 16 }, { UI.FONT_BIG, "text", 18 },
    { UI.FONT_NUM, "num", 13 }, { UI.FONT_NUM_SMALL, "num", 11 },
}

UI.FONT_OFFSET_MIN, UI.FONT_OFFSET_MAX = -2, 2
UI.fontOffset = 0

local function SetEvery(offset)
    for _, b in ipairs(BASE) do
        local obj = UI.fontObjects[b[1]] or _G[b[1]]
        if obj then obj:SetFont(faces[b[2]], b[3] + offset, faces.flags) end
    end
end

-- UI.ApplyFonts(offset): clamp to -2..+2 (decision 13: the shared panes' 20-px
-- rows hold a 15-px font and no more), re-size every font, return the offset
-- applied. Anything not a number is 0.
function UI.ApplyFonts(offset)
    offset = tonumber(offset) or 0
    offset = math.floor(offset + 0.5)
    if offset < UI.FONT_OFFSET_MIN then offset = UI.FONT_OFFSET_MIN end
    if offset > UI.FONT_OFFSET_MAX then offset = UI.FONT_OFFSET_MAX end
    SetEvery(offset)
    UI.fontOffset = offset
    return offset
end

-- T94: UI.ReFaceFonts(style): the style's faces, flags and shadow on every
-- font at the size it has now (the offset kept: a style never changes a
-- size), and the two class fonts in the accent. No FONTS_CHANGED: sizes did
-- not move; the style's own STYLE_CHANGED follows.
function UI.ReFaceFonts(style)
    local f = style and style.fonts or {}
    local flat = UI.FLAT.fonts
    faces.text = FaceOf(f.face or flat.face)
    faces.num = FaceOf(f.num or flat.num)
    faces.flags = f.flags or flat.flags
    faces.shadow = f.shadow or flat.shadow
    SetEvery(UI.fontOffset or 0)
    local A = UI.accent
    for _, b in ipairs(BASE) do
        local obj = UI.fontObjects[b[1]] or _G[b[1]]
        if obj then obj:SetShadowOffset(faces.shadow[1], faces.shadow[2]) end
    end
    for _, name in ipairs({ UI.FONT_CLASS_TITLE, UI.FONT_CLASS }) do
        local obj = UI.fontObjects[name] or _G[name]
        if obj then obj:SetTextColor(A[1], A[2], A[3], 1) end
    end
end

-- UI.Pitch(n): a flat-look pane's vertical pitch grows with a positive
-- offset (a negative one leaves the pitches alone); widths never change.
function UI.Pitch(n)
    local o = UI.fontOffset or 0
    if o > 0 then return n + o end
    return n
end

-- T80 (C1): the offset's default, declared by the file that reads it (T55's
-- MD:RegisterDefaults; it left Core_Forever.lua's DEFAULTS), so TBC has it.
-- T94: and the saved style's, "flat" -- this file is Flat's, and UI/Styles.lua
-- (which reads it) loads right after; db.ui's keys are declared by the theme,
-- the ESC stack and the window manager, as tools/defaultscheck.lua holds.
MD:RegisterDefaults({ ui = { fontOffset = 0, style = "flat" } })

-- T80 (C1): the Text size control of both Settings panes -- the offset
-- applied (through the kit's UI.ApplyFonts, which announces FONTS_CHANGED)
-- and saved; answers the offset applied.
function UI.SetFontOffset(offset)
    local applied = UI.ApplyFonts(offset)
    local db = MD.db
    if type(db) == "table" then
        if type(db.ui) ~= "table" then db.ui = {} end
        db.ui.fontOffset = applied
    end
    return applied
end

-- The saved offset, once SavedVariables are in: clamped, written back, applied.
MD:RegisterCallback("CORE_LOGIN", function()
    local u = MD.db and MD.db.ui
    if type(u) ~= "table" then return end
    u.fontOffset = UI.ApplyFonts(u.fontOffset)
end)

--------------------------------------------------------------------------------
-- 4.3 Pixel-perfect edges (UI.px / UI.StylizeFrame / UI.RestylePixels live in
-- Style.lua) and 6.2's dropdown list strata.
--------------------------------------------------------------------------------
UI.PIXEL = true
UI.LIST_STRATA = "FULLSCREEN_DIALOG"
