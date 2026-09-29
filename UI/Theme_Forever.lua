-- T29 (docs/SPEC-forever-ui.md 4.1-4.3): the Forever theme. Listed by the
-- Forever TOCs only, right after UI/Style.lua; at load, before any window is
-- built, it writes the flat palette into UI.PALETTE, the text colours into
-- UI.TEXT, builds the new fonts, and switches on the kit's pixel-snapped edges
-- (UI.PIXEL) and the dropdown lists' strata (UI.LIST_STRATA). The TBC TOC does
-- not list it, so there UI.TEXT, UI.PIXEL and UI.LIST_STRATA stay nil and every
-- shared file keeps its old literals.
--
-- No client data is read here: the accent is Style.lua's (UnitClass through
-- the adapter, RAID_CLASS_COLORS), the font face is GameFontNormal's.
local _, MD = ...
local UI = MD.UI

--------------------------------------------------------------------------------
-- 4.1 Palette: fills (r, g, b, a) into UI.PALETTE, mutated in place so a pane
-- that captured the table keeps reading the theme.
--------------------------------------------------------------------------------
local A = UI.accent
local P = UI.PALETTE

local function Grey(byte, a) local v = byte / 255; return { v, v, v, a } end

P.bg        = Grey(0x16, 0.96)                     -- window body: near-opaque
P.pane      = Grey(0x1C, 1)                        -- rail, chip, cards, sheets
P.nav       = { 0.115, 0.115, 0.115, 1 }           -- #1D1D1D, Cell's 0.115: header, nav, buttons
P.border    = { 0, 0, 0, 1 }                       -- 1-px edges (UI.px)
P.rule      = { A[1], A[2], A[3], 0.6 }            -- the line under a pane title
P.line      = Grey(0x2A, 1)                        -- table header rule, rail separators
P.rowAlt    = { 1, 1, 1, 0.03 }                    -- zebra on even rows
P.hover     = { A[1], A[2], A[3], 0.12 }           -- row and list hover
P.selected  = { A[1], A[2], A[3], 0.28 }           -- selected rail row / rank (+ a 2-px bar)
P.suggested = { A[1], A[2], A[3], 0.10 }           -- the suggested rank's row (+ a 2-px bar)
P.mask      = Grey(0x26, 0.7)                      -- behind a sheet
P.close     = { 0.6, 0.1, 0.1, 0.6 }               -- the x button, as in Cell
P.closeHover = { 0.6, 0.1, 0.1, 1 }
-- The kit's own keys (UI.CreateNavFrame, the dropdown lists) follow the theme.
P.frame     = P.bg
P.header    = P.nav

--------------------------------------------------------------------------------
-- 4.1 Text colours: UI.TEXT.<token> = { r, g, b, hex = "|cffrrggbb" }. Shared
-- files read them behind `if UI.TEXT` and keep their literals otherwise. No
-- Blizzard gold here: the accent is the class colour.
--------------------------------------------------------------------------------
local function Tok(hex)
    local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
    return { r / 255, g / 255, b / 255, hex = "|cff" .. hex:lower() }
end

local accentHex = type(UI.accentHex) == "string" and UI.accentHex:match("^|c[fF][fF](%x%x%x%x%x%x)$")
if not accentHex then
    accentHex = string.format("%02x%02x%02x", math.floor(A[1] * 255 + 0.5),
        math.floor(A[2] * 255 + 0.5), math.floor(A[3] * 255 + 0.5))
end

UI.TEXT = {
    accent   = { A[1], A[2], A[3], hex = "|cff" .. accentHex:lower() },  -- titles, rules, selection
    text     = Tok("FFFFFF"),   -- values
    text2    = Tok("B3B3B3"),   -- secondary lines, comparison, spell text
    label    = Tok("9D9D9D"),   -- labels in cards and the tooltip block
    muted    = Tok("7A7A7A"),   -- dominated, footers, table headers, hints
    disabled = Tok("4D4D4D"),   -- gaps, not learned, disabled buttons
    mana     = Tok("4D99FF"),   -- modelled mana figures (the clock bar's 0.3/0.6/1)
    good     = Tok("5CCB6E"),   -- measure verdicts
    bad      = Tok("E0605A"),   -- measure verdicts, the stale warning
}

--------------------------------------------------------------------------------
-- 4.2 Fonts: no outline, a black shadow at (1, -1). Friz (GameFontNormal's
-- face) for text, Arial Narrow for numbers (narrow, even-width digits).
--------------------------------------------------------------------------------
local FRIZ = (GameFontNormal:GetFont())
local NUM = "Fonts\\ARIALN.TTF"

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

UI.FONT_HEAD = "MANADEMON_FONT_HEAD";           MakeFont(UI.FONT_HEAD, FRIZ, 16)
UI.FONT_BIG = "MANADEMON_FONT_BIG";             MakeFont(UI.FONT_BIG, FRIZ, 18)
UI.FONT_NUM = "MANADEMON_FONT_NUM";             MakeFont(UI.FONT_NUM, NUM, 13)
UI.FONT_NUM_SMALL = "MANADEMON_FONT_NUM_SMALL"; MakeFont(UI.FONT_NUM_SMALL, NUM, 11)

-- Every font the kit and the theme build, at offset 0 (Style.lua's sizes for
-- its own eight). UI.ApplyFonts re-sizes these objects in place, so every
-- FontString built from one follows at once.
local BASE = {
    { UI.FONT_TITLE, FRIZ, 14 }, { UI.FONT_TITLE_DISABLE, FRIZ, 14 },
    { UI.FONT, FRIZ, 13 }, { UI.FONT_DISABLE, FRIZ, 13 },
    { UI.FONT_SMALL, FRIZ, 11 }, { UI.FONT_SPECIAL, FRIZ, 12 },
    { UI.FONT_CLASS_TITLE, FRIZ, 14 }, { UI.FONT_CLASS, FRIZ, 13 },
    { UI.FONT_HEAD, FRIZ, 16 }, { UI.FONT_BIG, FRIZ, 18 },
    { UI.FONT_NUM, NUM, 13 }, { UI.FONT_NUM_SMALL, NUM, 11 },
}

UI.FONT_OFFSET_MIN, UI.FONT_OFFSET_MAX = -2, 2
UI.fontOffset = 0

-- UI.ApplyFonts(offset): clamp to -2..+2 (decision 13: the shared panes' 20-px
-- rows hold a 15-px font and no more), re-size every font, return the offset
-- applied. Anything not a number is 0.
function UI.ApplyFonts(offset)
    offset = tonumber(offset) or 0
    offset = math.floor(offset + 0.5)
    if offset < UI.FONT_OFFSET_MIN then offset = UI.FONT_OFFSET_MIN end
    if offset > UI.FONT_OFFSET_MAX then offset = UI.FONT_OFFSET_MAX end
    for _, b in ipairs(BASE) do
        local obj = UI.fontObjects[b[1]] or _G[b[1]]
        if obj then obj:SetFont(b[2], b[3] + offset, "") end
    end
    UI.fontOffset = offset
    return offset
end

-- UI.Pitch(n): a Forever-only pane's vertical pitch grows with a positive
-- offset (a negative one leaves the pitches alone); widths never change.
function UI.Pitch(n)
    local o = UI.fontOffset or 0
    if o > 0 then return n + o end
    return n
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
