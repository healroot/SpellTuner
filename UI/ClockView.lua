-- T93 (docs/SPEC-next.md 2.4 and 7.1, K2 of docs/research/next/R-clock.md):
-- the clock's RENDERER, on both lines. Engine/ClockFace.lua says what the clock
-- says (a pure face, cut into pieces by ClockFace.Segments); this file draws a
-- face into a frame the line owns -- the TBC widget (UI/Widget.lua) and the
-- Forever clock (UI/Clock_Forever.lua) each build one view inside their own
-- frame and hand it a face every paint.
--
-- What it draws in the layout "line" (L1, T93):
--   * three font strings at FIXED places (F2, decision 14; DECISIONS "Widget
--     text left-anchored ... centred text slides when the digit count
--     changes"): the label from the left edge in the kit's font, the value
--     and its arrow at a fixed x in the kit's number font, the secondary
--     segment right-aligned to the right edge -- so when "OOM 59s" becomes
--     "OOM 1:00" or "OOM >10m" only the value's own digits move;
--   * each piece in its tone's colour (F1, decision 16: TBC's literals,
--     ClockFace.HEX, on both lines; a look's `colors` may re-tint them), the
--     arrow in its own tone where it differs;
--   * a message line (the unlock / "Show now" preview's words), centred where
--     T82 put the one string, drawn instead of the pieces;
--   * the pulse (F5): one animation, ST:Alert's and the once-per-fight flash
--     under 30 s, played by whichever line owns the frame.
-- The value's fixed x is the label slot's width: the widest label the line
-- draws (`look.labelSample`, "FULL" on TBC, "~FULL" on Forever) measured in the
-- label's own font, plus a gap. It is measured again at each paint and the
-- pieces re-anchored ONLY when a measure changed (a font offset, a font that
-- loaded late), never because the words did.
--
-- T98 (docs/SPEC-next.md 7.2-7.3, K3 of R-clock.md; decision 13): the
-- LAYOUTS and the look.
--   * Layouts (all draw the same face): "line" (L1 above; the default until T131, now "bar"),
--     "compact" (L2: the label small over one big number, no secondary) and
--     "bar" (L3: a bar the width of the clock with the label and the time on
--     it). The ring (L4) is T104's; CV.BarsOK already holds its rule. Each
--     layout's text regions are built the first time it is drawn and kept
--     (one pool per frame), so a switch leaks nothing; the bars are shared.
--   * The look, sparse (7.3): db.clockLook = { layout = "bar", over = {} }
--     (registered here, both TOCs). CV.Resolve gives the RESOLVED look:
--         the layout's defaults  <-  the active style's `clock` role  <-  over
--     The role (each style file defines its own; Flat's in UI/Theme_Flat.lua)
--     is read for: kind / fill / edge (the panel: UI.Skin(frame, "clock",
--     fill, edge)), bar (the bars' backing colour), barFill (optional: the
--     MANA bar's colour) and ring (T104's). `over` holds only what the user
--     set (CV.OVER lists the keys); "Reset to style" (CV.ResetToStyle) wipes
--     it. Nothing reads db.clockLook.over but this file. The line's own
--     switches (TBC db.showRest / showCooldown, Forever db.clock.showRest)
--     stay where they are and reach the look as `show` (phase 1, 7.3).
--   * The dump line (`clock: layout <key>, <n> overrides (<keys>)`) through
--     ST:AddDumpLine, added the first time the look is not the default one,
--     so the dump of a player who never touched the clock is what it was.
--
-- T115 (clock v2, docs/tasks/T115-clock-bars-frame.md, docs/mockups/
-- clock-v2.html C2-C4, C6; the author's answers: "We can do all 3, and let
-- user decide / And those that are recomended become default"):
--   * Mana AND the five-second rule, on every layout and both lines (this
--     replaces decision 15 (a)), per layout under bars.<layout>: `show` (both
--     / mana / fsr / none), `join` -- the three designs: "stacked" (A, the
--     default: the mana bar over a 3-px strip, a 1-px gap between), "veil"
--     (B: one mana bar, an amber veil over its right part while the rule
--     runs, a 1-px green line along its top after -- flat amber at 0.45
--     alpha with a 1-px edge: the kit ships no hatch art) and "chip" (C: a
--     square left of the label holding a Cooldown frame's swipe, SetCooldown
--     once per spend; the client animates it); T135 a fourth, "sweep" (one
--     mana bar in its own colour, an amber line with a dark edge crossing it
--     left to right over the five seconds; after, the green top line, or
--     with `after` tick the white line at the regen tick) --, `order` (manaOver /
--     fsrOver), `mana` (game / model: Forever's modelled pool from the face's
--     plain pct, at 0.6 alpha), `fsr` (the strip's thickness, 1-8), `after`
--     (green / empty / tick: TBC's 2-s regen tick from ST.Regen:RegenTick, a
--     white mark sweeping the green strip) and `texture` (flat; TBC also the
--     client's two bar textures). CV.BarsOK says what this line may draw;
--     a refusal falls back to the default and is named in look.refused.
--   * Every 5SR mark is placed by TIME alone (the line's draw.fsr / spend):
--     on Forever the mana fill is the game's, drawn from a secret, and
--     nothing is placed at its edge.
--   * The frame per layout: frame.<layout>.w / h within the layout's range,
--     never under the measured minimum (View:Minimum, in the clock's own
--     fonts; a size under it stops there and is named), Height's pixels to
--     the mana bar (the text unmoved, the strip keeping its thickness), and
--     frame.<layout>.scale (50-200 %), which the LINE applies with SetScale,
--     keeping the clock's centre (CV.KeepCentre).
--   * F1's step (one function per view, an OnUpdate on the strip, or on the
--     mana bar for the veil) drives the strip's value, the veil's width and
--     the tick mark every frame while the rule runs or a tick is known; it
--     is gone at the rule's end, on a new look and under FillBar.
--   * colors.manaBar (mana / tone / class / a colour) tints the mana bar; a
--     style's barFill too; the strip, the veil and the chip keep amber and
--     green under every look, so their meaning never changes.
--   * CV.Migrate reads 0.16.6's bar.source / color / spark / horizon /
--     height once (clock-v2.html C4's table) and names what it dropped in a
--     lazy dump line. The spark and the "time" source are gone.
--
-- T139 (docs/tasks/T139-clock-bar-look.md; the author's mockup, 2026-11-08, and
-- "I want make this what I've set on screen as default"): the bar's look, per
-- layout under bars.<layout> -- `shape` (rect / round / pill / thin: Rounded
-- and Pill clip every bar texture with Media's masks, CLAMPTOWHITE, one pair
-- per region; a client with no masks draws a rectangle and says so; Thin is a
-- rectangle the settings pair with a low bar and the text outside), `texture`
-- (SpellTuner's Media art, the game's two bars, Gradient -- the fill-end colour
-- on the left to the fill on the right through ST.API.SetGradient -- or
-- "lsm:<name>", a host's LibSharedMedia bar through ST.Media; one that cannot
-- be found draws Flat and says so), `border` (0-3 physical pixels of the edge
-- colour round each bar, under the background), `height` (the Bar layout's
-- bar, 3-30) and `text` (the Bar layout's words inside the bar, above it,
-- below it, or off). Colours beside colors.manaBar and bar.back:
-- colors.fillEnd, colors.edge, colors.fsrLine (the rule's amber: strip, veil,
-- line, chip) and colors.after (the green after it). The defaults are the
-- author's: a 6-px pill, Soft, the words below, 396DA7 / 1D4EA6 / 0A0A0A on a
-- black edge, the moving line, and no panel behind the Bar layout.
--
-- T142 (docs/tasks/T142-bar-texts-game-frame.md; the mockup
-- tools/.cache/clockbar2/index.html; "override my ingame setting"):
--   * The Bar layout's texts are ITEMS, one per kind (CV.ITEM_KINDS: label,
--     time, mana, manaMax, pct, mp5, fsr, rest), each with on / place
--     (inside, above, below) / align / x / y / size / colour / outline, kept
--     sparse as text.bar.items.<kind>.<field> (CV.ITEMS_DEFAULT the author's
--     pick; CV.ResolveItems validates, look.items). They replace its Left /
--     Centre / Right slots and bars.bar.text; Line and Compact keep theirs.
--   * THE FRAME IS THE BAR: bars.bar.height high, frame.bar.w wide; an
--     outside text hangs from the bar's edge and never changes the frame's
--     size (only the texts inside ask for width).
--   * bars.bar.frame: none / border / game -- EllesmereUI's Blizzard-style
--     art, mask and bevel (View:PlaceGame), the atlases asked through
--     ST.API.HasAtlas; without them the border, named in look.refused.
--   * bars.bar.font: eui (UI.Ellesmere.FontPath, live) / st; without
--     EllesmereUI the kit's font, named.
--   * The Bar layout's defaults are its own (CV.BarsDefault): the game frame,
--     rounded, 8 px, Pixels Dark (Soft without EllesmereUI, silently).
--   * db.clockLook.v 2: CV.ResetBarLook clears the Bar layout's look and the
--     bar colours once (MigrateStored; a dump line names what).
--
-- T116 (clock v2, C1; docs/tasks/T116-clock-text-tab.md): the slots drawn.
--   * text.<layout>.<key> in `over`: T114's slots and words (ClockFace's
--     TEXT_OPTIONS / TEXT_WORDS, judged by CF.ResolveText) and the renderer's
--     own -- size (8-32; unset: the kit's fonts, following the window text
--     size; set: that size, Compact's small slots at half of it), outline
--     (none / outline / thick / mono), shadow (true / false) and numbers
--     (number: the kit's number face in the time's home; labels: the labels'
--     face). Nothing registered: `over` stays sparse.
--   * look.text is the layout on screen's resolved text, look.texts every
--     layout's (the feeds and brokers read look.texts.line).
--   * Each slot is one font string at a fixed place (decision 14): Line's
--     Left from the left edge, Main at the left slot's measured width + the
--     gap, Right right-aligned, Right2 right-aligned left of Right two spaces
--     away; Compact's Top, Main and Bottom (Bottom adds its row to the
--     minimum); Bar's Left and Right on the bar. Line's second Right and
--     Compact's Bottom are made the first time one is drawn.
--   * The minimum is measured from the slots set, in the fonts they use.
--     Right2 is drawn only where the frame is wide enough (View:FitsRight2;
--     else look.refused["text.line.right2"] names the width it needs).
--   * A pct / mana slot asks the line's draw.powerText(fs, kind) first
--     (Forever: off until probe Q-clock-2 -- ST.API.POWER_TEXT_READS); on
--     false the slot draws the face's words (the model's "~" on Forever).
--
-- What it never does: Show / Hide the frame it draws into (each line keeps
-- the single visibility owner, CLAUDE.md; a layout switch rebuilds regions
-- INSIDE the frame), read a client value (the face is plain; the mana pool
-- and the five-second rule come from the line's `draw` callbacks), read the
-- mana bar back, or read ST.db outside the store's functions below.
local _, ST = ...
local UI = ST.UI

ST.ClockView = ST.ClockView or {}
local CV = ST.ClockView

CV.INSET = 8      -- the label's and the secondary's distance from the frame's edges
CV.TOP = -4       -- the text row, from the frame's top (T82's)
CV.GAP = 6        -- between the label slot and the value

-- T98: the look's store, sparse (docs/SPEC-next.md 7.3). A registered default
-- fills every leaf, so only the layout and an empty override table are
-- declared; what "follows the style" is resolved, never stored.
-- T131: the layout a fresh store, an unknown saved layout and the dump's
-- "non-default" test all read (a saved "line" is the player's and is kept).
CV.DEFAULT_LAYOUT = "bar"
ST:RegisterDefaults({ clockLook = { layout = CV.DEFAULT_LAYOUT, over = {} } })

-- The widest value a layout must hold: a prefix, four digits, an arrow of two
-- ("~0:00 vv" is never drawn, but nothing drawn is wider); the widest
-- secondary segment the line draws.
CV.VALUE_SAMPLE = ">0:00 vv"
CV.SECOND_SAMPLE = "rest 10:00"

-- The layouts this file draws, in the order a picker lists them. T104 adds
-- the ring to CV.LAYOUT and here. T115: each layout's default frame and the
-- ranges its Width and Height take.
CV.LAYOUTS = { "line", "compact", "bar" }
CV.LAYOUT = {
    -- L1: T82's panel, T93's segments; mana 4 over a 3-px strip
    line = { name = "Line", width = 180, height = 32, wRange = { 100, 400 }, hRange = { 26, 80 }, second = true },
    -- L2: one big number; the rest segment lives in the hover
    compact = { name = "Compact", width = 72, height = 46, wRange = { 60, 300 }, hRange = { 36, 120 },
        second = false, inset = 6, valueSize = 22 },
    -- L3: a bar with the time on it
    bar = { name = "Bar", width = 200, height = 22, wRange = { 100, 400 }, hRange = { 16, 60 },
        second = false, inset = 6,
        -- T139: no panel behind the Bar layout unless the Frame tab sets one;
        -- the author's background (0A0A0A) and fill (396DA7) under every style
        -- (a style's clock role bar / barFill are the other layouts')
        panel = { fill = { 0, 0, 0, 0 }, edge = { 0, 0, 0, 0 } },
        back = { 0x0A / 255, 0x0A / 255, 0x0A / 255, 1 }, ownFill = true,
        -- T142: the author's pick (the mockup's screenshot): the game's bar
        -- frame, rounded, 8 px, EllesmereUI's Pixels Dark (Soft without it) in
        -- EllesmereUI's font; the frame is the bar (its texts hang outside it)
        bars = { frame = "game", font = "eui", shape = "round", texture = "eui:pixels-dark", height = 8 },
        textureFallback = "soft" },
}

-- T115: the bars' defaults (both lines, every layout; answers 1, 2 and 5).
CV.BARS_DEFAULT = { show = "both", join = "sweep", order = "manaOver", mana = "game", fsr = 3,
    after = "green", texture = "soft", shape = "pill", border = 1 }
-- T139 / T142: the Bar layout's bar height when nothing sets it (the frame is
-- the bar: its texts never make it taller)
CV.BAR_HEIGHT = 8

-- T142: a layout's bars defaults -- CV.BARS_DEFAULT with the layout's own
-- (the Bar layout's frame, font, shape, texture and height) over it. A copy.
function CV.BarsDefault(layout)
    local out = {}
    for k, v in pairs(CV.BARS_DEFAULT) do out[k] = v end
    local d = CV.LAYOUT[layout]
    for k, v in pairs(d and d.bars or {}) do out[k] = v end
    return out
end

-- What each bars field accepts (the lists a picker offers, before the line's
-- facts take some out).
CV.BARS_VALUES = {
    show = { "both", "mana", "fsr", "none" },
    join = { "stacked", "veil", "chip", "sweep" },
    order = { "manaOver", "fsrOver" },
    mana = { "game", "model" },
    after = { "green", "empty", "tick" },
    texture = { "soft", "flat", "smooth", "gradient", "gloss", "striped", "minimal", "statusbar", "raid" },
    shape = { "rect", "round", "pill", "thin" },
    frame = { "none", "border", "game" }, -- T142: the Bar layout's
    font = { "eui", "st" },               -- T142: the Bar layout's
}
CV.FSR_RANGE = { 1, 8 }
CV.BORDER_RANGE = { 0, 3 }
CV.HEIGHT_RANGE = { 3, 30 }
CV.SCALE_RANGE = { 50, 200 }

-- The bar textures: flat (the kit's), SpellTuner's art (tools/buildmedia.py),
-- Gradient (flat, shaded by SetGradient), the client's two bars; "lsm:<name>"
-- a host's (Integrations/Media_LSM.lua).
CV.MEDIA = "Interface\\AddOns\\SpellTuner\\Media\\"
CV.TEXTURES = {
    flat = UI.whiteTexture,
    gradient = UI.whiteTexture,
    soft = CV.MEDIA .. "Soft", smooth = CV.MEDIA .. "Smooth", gloss = CV.MEDIA .. "Gloss",
    striped = CV.MEDIA .. "Striped", minimal = CV.MEDIA .. "Minimal",
    statusbar = "Interface\\TargetingFrame\\UI-StatusBar",
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
CV.TEXTURE_NAMES = {
    soft = "Soft", flat = "Flat", smooth = "Smooth", gradient = "Gradient", gloss = "Gloss",
    striped = "Striped", minimal = "Minimal", statusbar = "Status bar (game)", raid = "Raid health (game)",
}
CV.LSM_PREFIX = "lsm:"
-- T140: "eui:<key>", one of EllesmereUI's own bar textures, read from its
-- catalogue (Integrations/Media_LSM.lua); without EllesmereUI, Flat and why
CV.EUI_PREFIX = "eui:"
CV.EUI_MISSING = "EllesmereUI is not loaded: drawn Flat"
CV.MASKS = { round = "Round", pill = "Pill" }
CV.LSM_MISSING = "that texture's addon is not loaded: drawn Flat"
CV.MASK_REFUSED = "this client has no mask textures: drawn as a rectangle"

-- CV.TexturePath(key) -> path, why: a key's file; a host's missing one is Flat
-- with the reason.
function CV.TexturePath(key)
    if type(key) == "string" and key:sub(1, #CV.EUI_PREFIX) == CV.EUI_PREFIX then
        local path = ST.Media and ST.Media.FetchEllesmere and ST.Media.FetchEllesmere(key:sub(#CV.EUI_PREFIX + 1))
        if path then return path end
        return CV.TEXTURES.flat, CV.EUI_MISSING
    end
    if type(key) == "string" and key:sub(1, #CV.LSM_PREFIX) == CV.LSM_PREFIX then
        local path = ST.Media and ST.Media.Fetch and ST.Media.Fetch(key:sub(#CV.LSM_PREFIX + 1))
        if path then return path end
        return CV.TEXTURES.flat, CV.LSM_MISSING
    end
    return CV.TEXTURES[key] or CV.TEXTURES.flat
end

-- The five-second rule's amber while it runs and green once spirit regen
-- runs (UI/Widget.lua's since v0.1), the mana blue (UI/Clock_Forever.lua's
-- since T11), the veil's alpha, the model's alpha, the tick mark.
CV.FSR_COLOR   = { 1, 0.67, 0.2 }
CV.REGEN_COLOR = { 0x5C / 255, 0xCB / 255, 0x6E / 255 } -- T139: the author's 5CCB6E
CV.MANA_COLOR  = { 0x39 / 255, 0x6D / 255, 0xA7 / 255 } -- T139: the author's 396DA7
CV.FILL_END_COLOR = { 0x1D / 255, 0x4E / 255, 0xA6 / 255 } -- T139: Gradient's left end
CV.EDGE_COLOR  = { 0, 0, 0 }
CV.TICK_COLOR  = { 1, 1, 1 }
CV.VEIL_ALPHA = 0.45
CV.MODEL_ALPHA = 0.6
CV.TICK_WIDTH = 2
CV.SWEEP_WIDTH = 2 -- T135: the moving line, with a 1-px dark edge each side

CV.TICK_REFUSED = "Forever cannot read your mana, so the 2-second regen tick cannot be learned: the strip stays green."
CV.MODEL_REFUSED = "no modelled pool on this line: it reads the real one"
CV.TEXTURE_REFUSED = "this line draws its bars flat only"
CV.RING_REFUSED = "the real pool is drawn by the game, never read: a ring cannot show it here"

-- T142 (docs/tasks/T142-bar-texts-game-frame.md): the Bar layout's texts, one
-- item per kind, each placed on its own (inside the bar, above or below it),
-- in this drawing order. Fields: on, place, align, x, y, size, colour (six
-- hex digits: the player's own value, never a token), outline.
CV.ITEM_KINDS = { "label", "time", "mana", "manaMax", "pct", "mp5", "fsr", "rest" }
CV.ITEM_FIELDS = { "on", "place", "align", "x", "y", "size", "colour", "outline" }
CV.ITEM_NAMES = { label = "Label", time = "Time", mana = "Mana", manaMax = "Mana / max", pct = "Mana %",
    mp5 = "Regen", fsr = "5SR", rest = "Rest" }
CV.ITEM_WORDS = { label = "OOM", time = "1:20 v", mana = "1020", manaMax = "1020/2400", pct = "42%",
    mp5 = "92 mp5", fsr = "5SR 3.0", rest = "rest 2:10" }
CV.ITEM_VALUES = {
    place = { "inside", "above", "below" },
    align = { "left", "center", "right" },
    outline = { "none", "outline", "thick", "shadow" },
}
CV.ITEM_X, CV.ITEM_Y, CV.ITEM_SIZE = { -40, 40 }, { -20, 20 }, { 6, 32 }
CV.ITEM_PAD = 2      -- an inside text that is not centred, from its edge
CV.ITEM_GAP = 1      -- an outside text, from the bar's edge
local function It(on, place, align, x, y, size, colour, outline)
    return { on = on, place = place, align = align, x = x, y = y, size = size, colour = colour, outline = outline }
end
-- the author's pick (the mockup's "mine"): the time below left, the mana in
-- the middle, the regen below right; every other kind off with its own place
CV.ITEMS_DEFAULT = {
    label = It(false, "below", "left", 0, -1, 11, "E4E1DC", "none"),
    time = It(true, "below", "left", 0, -1, 11, "E4E1DC", "none"),
    mana = It(true, "inside", "center", 0, 0, 11, "E4E1DC", "none"),
    manaMax = It(false, "inside", "center", 0, 0, 11, "E4E1DC", "none"),
    pct = It(false, "above", "right", 0, 1, 11, "E4E1DC", "none"),
    mp5 = It(true, "below", "right", 0, -1, 11, "9FD7A9", "none"),
    fsr = It(false, "above", "left", 0, 1, 11, "FFAB33", "none"),
    rest = It(false, "below", "right", 0, -1, 11, "8F8A83", "none"),
}
CV.ITEM_OUTLINE = { outline = "OUTLINE", thick = "THICKOUTLINE" }

-- T142: the game's bar art (EllesmereUI's "Blizzard style", read from
-- EUI_ResourceBars_Style.lua / _Groups.lua): the frame atlas round the bar,
-- the mask atlas on the fill and the background, four bevel strips.
CV.GAME_ATLAS = { frame = "UI-HUD-CoolDownManager-Bar-BG", mask = "UI-HUD-CoolDownManager-Bar" }
CV.GAME_REACH = { left = -2, top = 3, right = 6, bottom = -7 }
CV.GAME_REFUSED = "this client has no game bar art: drawn with a border"
CV.FONT_EUI_MISSING = "EllesmereUI is not loaded: SpellTuner's font"
CV.LOOK_VERSION = 2  -- db.clockLook.v: T142 reset the Bar layout's look once

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------
local function IsColour(v)
    if type(v) == "string" then return UI.PALETTE and UI.PALETTE[v] ~= nil end
    if type(v) ~= "table" then return false end
    if v.ref ~= nil then return v.ref == "accent" end
    for i = 1, 3 do
        if type(v[i]) ~= "number" or v[i] < 0 or v[i] > 1 then return false end
    end
    return v[4] == nil or (type(v[4]) == "number" and v[4] >= 0 and v[4] <= 1)
end
local function Range(lo, hi)
    return function(v) return type(v) == "number" and v >= lo and v <= hi end
end
local function IntRange(lo, hi)
    return function(v) return type(v) == "number" and v >= lo and v <= hi and math.floor(v) == v end
end
local function OneOf(list)
    local set = {}
    for _, k in ipairs(list) do set[k] = true end
    return function(v) return set[v] == true end
end
local function Hex(v) return type(v) == "string" and v:match("^%x%x%x%x%x%x$") ~= nil end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x) end
    return out
end

-- A dotted path into a table, any depth (a colour table is a leaf).
local function Get(t, dotted)
    for part in dotted:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

-- Write a dotted path (a copy of the value); nil removes it and prunes every
-- table it leaves empty.
local function PutPath(t, dotted, value)
    local parts = {}
    for p in dotted:gmatch("[^.]+") do parts[#parts + 1] = p end
    local chain, cur = { t }, t
    for i = 1, #parts - 1 do
        if type(cur[parts[i]]) ~= "table" then
            if value == nil then return end
            cur[parts[i]] = {}
        end
        cur = cur[parts[i]]
        chain[#chain + 1] = cur
    end
    cur[parts[#parts]] = Copy(value)
    if value == nil then
        for i = #parts - 1, 1, -1 do
            if next(chain[i + 1]) == nil then chain[i][parts[i]] = nil else break end
        end
    end
end
CV.Get, CV.PutPath = Get, PutPath

--------------------------------------------------------------------------------
-- The overrides (`over`), each with what it accepts. A control writes one
-- through CV.Set; a value this table refuses is never stored.
--------------------------------------------------------------------------------
local OwnTexture = OneOf(CV.BARS_VALUES.texture)
local BARS_OK = {
    show = OneOf(CV.BARS_VALUES.show), join = OneOf(CV.BARS_VALUES.join),
    order = OneOf(CV.BARS_VALUES.order), mana = OneOf(CV.BARS_VALUES.mana),
    after = OneOf(CV.BARS_VALUES.after),
    texture = function(v)
        if OwnTexture(v) then return true end
        if type(v) ~= "string" then return false end
        for _, pre in ipairs({ CV.LSM_PREFIX, CV.EUI_PREFIX }) do
            if #v > #pre and v:sub(1, #pre) == pre then return true end
        end
        return false
    end,
    fsr = IntRange(CV.FSR_RANGE[1], CV.FSR_RANGE[2]),
    shape = OneOf(CV.BARS_VALUES.shape),
    border = IntRange(CV.BORDER_RANGE[1], CV.BORDER_RANGE[2]),
    height = IntRange(CV.HEIGHT_RANGE[1], CV.HEIGHT_RANGE[2]),
    frame = OneOf(CV.BARS_VALUES.frame), font = OneOf(CV.BARS_VALUES.font),
}
local BARS_ORDER = { "show", "join", "order", "mana", "fsr", "after", "texture", "shape", "border", "height",
    "frame", "font" }
-- T142: frame and font are the Bar layout's only
local BARS_BAR_ONLY = { frame = true, font = true }

CV.OVER = {
    ["panel.fill"] = IsColour,
    ["panel.edge"] = IsColour,
    ["bar.back"] = IsColour,
    ["colors.crit"] = Hex, ["colors.warn"] = Hex, ["colors.normal"] = Hex,
    ["colors.good"] = Hex, ["colors.muted"] = Hex, ["colors.mana"] = Hex,
    ["colors.manaBar"] = function(v) return v == "mana" or v == "tone" or v == "class" or IsColour(v) end,
    -- T139
    ["colors.fillEnd"] = IsColour, ["colors.edge"] = IsColour,
    ["colors.fsrLine"] = IsColour, ["colors.after"] = IsColour,
}
-- T116: the text's renderer options (beside T114's slot and word keys).
CV.OUTLINES = { "none", "outline", "thick", "mono" }
CV.OUTLINE_FLAGS = { outline = "OUTLINE", thick = "THICKOUTLINE", mono = "MONOCHROME" }
CV.NUMBERS = { "number", "labels" }
CV.TEXT_SIZE = { 8, 32 }
local TEXT_OK = {
    size = IntRange(CV.TEXT_SIZE[1], CV.TEXT_SIZE[2]),
    outline = OneOf(CV.OUTLINES),
    shadow = function(v) return type(v) == "boolean" end,
    numbers = OneOf(CV.NUMBERS),
}
local function Bool(v) return type(v) == "boolean" end

-- T142: what each item field accepts
local ITEM_OK = {
    on = Bool,
    place = OneOf(CV.ITEM_VALUES.place), align = OneOf(CV.ITEM_VALUES.align),
    x = IntRange(CV.ITEM_X[1], CV.ITEM_X[2]), y = IntRange(CV.ITEM_Y[1], CV.ITEM_Y[2]),
    size = IntRange(CV.ITEM_SIZE[1], CV.ITEM_SIZE[2]),
    colour = Hex,
    outline = OneOf(CV.ITEM_VALUES.outline),
}
CV.ITEM_OK = ITEM_OK

for _, L in ipairs(CV.LAYOUTS) do
    local d = CV.LAYOUT[L]
    local CF = ST.ClockFace
    -- T142: the Bar layout's texts are items (text.bar.items.<kind>.<field>);
    -- its word options (labels, time) stay; its slots and their size,
    -- outline, shadow, numbers and ofMax are gone
    if L == "bar" then
        for _, kind in ipairs(CV.ITEM_KINDS) do
            for _, f in ipairs(CV.ITEM_FIELDS) do CV.OVER["text.bar.items." .. kind .. "." .. f] = ITEM_OK[f] end
        end
    else
        for _, slot in ipairs(CF.TEXT_SLOTS[L]) do
            CV.OVER["text." .. L .. "." .. slot] = OneOf(CF.TEXT_OPTIONS[L][slot])
        end
        CV.OVER["text." .. L .. ".ofMax"] = Bool
        for k, ok in pairs(TEXT_OK) do CV.OVER["text." .. L .. "." .. k] = ok end
    end
    CV.OVER["text." .. L .. ".labels"] = OneOf(CF.TEXT_WORDS.labels)
    CV.OVER["text." .. L .. ".time"] = OneOf(CF.TEXT_WORDS.time)
    for _, f in ipairs(BARS_ORDER) do
        if L == "bar" or not BARS_BAR_ONLY[f] then CV.OVER["bars." .. L .. "." .. f] = BARS_OK[f] end
    end
    CV.OVER["frame." .. L .. ".w"] = Range(d.wRange[1], d.wRange[2])
    CV.OVER["frame." .. L .. ".h"] = Range(d.hRange[1], d.hRange[2])
    CV.OVER["frame." .. L .. ".scale"] = Range(CV.SCALE_RANGE[1], CV.SCALE_RANGE[2])
end

--------------------------------------------------------------------------------
-- What a line may draw: CV.BarsOK(layout, bars, facts) -> true | false, why,
-- field. Only the fields present are judged. `facts` is the line's:
-- poolPlain (TBC: the pool can be read), model (Forever: a modelled pool),
-- tick (TBC: the regen tick can be learned), textures (TBC: the client's
-- bar textures). The ring (T104) cannot draw the real pool where it is only
-- ever handed to a status bar unread.
--------------------------------------------------------------------------------
function CV.BarsOK(layout, bars, facts)
    facts = type(facts) == "table" and facts or {}
    bars = type(bars) == "table" and bars or {}
    for _, f in ipairs(BARS_ORDER) do
        local v = bars[f]
        if v ~= nil and not BARS_OK[f](v) then return false, "not accepted: " .. tostring(v), f end
    end
    if bars.mana == "model" and not facts.model then return false, CV.MODEL_REFUSED, "mana" end
    if bars.after == "tick" and not facts.tick then return false, CV.TICK_REFUSED, "after" end
    if bars.texture ~= nil and bars.texture ~= "flat" and not facts.textures then
        return false, CV.TEXTURE_REFUSED, "texture"
    end
    if layout == "ring" and (bars.mana == nil or bars.mana == "game")
        and (bars.show == "both" or bars.show == "mana") and not facts.poolPlain then
        return false, CV.RING_REFUSED, "show"
    end
    return true
end

--------------------------------------------------------------------------------
-- The resolver: layout defaults <- the style's clock role <- over.
--------------------------------------------------------------------------------
local function Renderable(key)
    return type(key) == "string" and CV.LAYOUT[key] ~= nil
end

-- CV.Resolve(stored, role, facts) -> look. Pure: `stored` is db.clockLook's
-- shape ({ layout, over }), `role` the style's clock recipe, `facts` the
-- line's (poolPlain, model, tick, textures, labelSample, show). A layout
-- nobody draws (yet) is CV.DEFAULT_LAYOUT; an override this file does not accept is
-- ignored; bars.* and frame.* are read for the layout drawn; a bars choice
-- this line may not draw falls back to the default (look.refused names what
-- was refused and why). Everything is a copy: the store is never touched.
function CV.Resolve(stored, role, facts)
    stored = type(stored) == "table" and stored or {}
    role = type(role) == "table" and role or {}
    facts = type(facts) == "table" and facts or {}
    local over = type(stored.over) == "table" and stored.over or {}
    local key = Renderable(stored.layout) and stored.layout or CV.DEFAULT_LAYOUT
    local d = CV.LAYOUT[key]

    local look = {
        layout = key, width = d.width, height = d.height, second = d.second,
        inset = d.inset, valueSize = d.valueSize,
        labelSample = facts.labelSample or "FULL",
        show = Copy(facts.show) or {},
        panel = d.panel and Copy(d.panel) or { fill = role.fill or "bg", edge = role.edge or "border" },
        bar = { back = d.back and Copy(d.back)
            or ((role.bar ~= nil and IsColour(role.bar)) and Copy(role.bar) or { 0, 0, 0, 1 }) },
        bars = CV.BarsDefault(key),
        frame = { w = d.width, h = d.height, scale = 100 },
        colors = {},
        refused = {},
    }
    if role.barFill ~= nil and IsColour(role.barFill) and not d.ownFill then look.bars.fill = Copy(role.barFill) end
    if role.ring ~= nil then look.ring = Copy(role.ring) end

    for k, ok in pairs(CV.OVER) do
        local v = nil -- the text: below
        if k:sub(1, 5) ~= "text." then v = Get(over, k) end
        if v ~= nil then
            local a, L, f = k:match("^([^.]+)%.([^.]+)%.([^.]+)$")
            if a then
                if L == key then
                    if ok(v) then look[a][f] = Copy(v) else look.refused[k] = "not accepted: " .. tostring(v) end
                end
            else
                local a2, b2 = k:match("^([^.]+)%.(.+)$")
                if ok(v) then look[a2][b2] = Copy(v) else look.refused[k] = "not accepted: " .. tostring(v) end
            end
        end
    end

    -- what this line may draw; a refused field back to its default (the
    -- ring's pool to the five-second rule)
    for _ = 1, 8 do
        local okB, why, field = CV.BarsOK(key, look.bars, facts)
        if okB then break end
        field = field or "show"
        look.refused["bars." .. key .. "." .. field] = why
        look.bars[field] = (field == "show") and "fsr" or CV.BarsDefault(key)[field]
    end
    -- T142: the layout's own default texture has a fallback of its own (the
    -- Bar's EllesmereUI texture draws Soft without EllesmereUI, silently: it
    -- is the default, not the player's pick)
    if d.textureFallback and Get(over, "bars." .. key .. ".texture") == nil then
        look.textureFallback = d.textureFallback
    end

    -- T116: every layout's text (the feeds read Line's whatever is on
    -- screen), the one on screen as look.text
    look.texts = {}
    local overText = type(over.text) == "table" and over.text or {}
    for _, L in ipairs(CV.LAYOUTS) do
        local raw = type(overText[L]) == "table" and overText[L] or {}
        local t, ref = ST.ClockFace.ResolveText(raw, L, { cd = facts.cd })
        for k2, why in pairs(ref or {}) do look.refused[k2] = why end
        local function Own(field, default)
            local v = raw[field]
            if v == nil then return default end
            if TEXT_OK[field](v) then return v end
            look.refused["text." .. L .. "." .. field] = "not accepted: " .. tostring(v)
            return default
        end
        if L ~= "bar" then
            t.size = Own("size", nil)
            t.outline = Own("outline", "none")
            t.shadow = Own("shadow", true)
            t.numbers = Own("numbers", "number")
        end
        look.texts[L] = t
    end
    look.text = look.texts[key]
    look.items = CV.ResolveItems(type(overText.bar) == "table" and overText.bar.items or nil, look.refused)
    return look
end

-- T142: CV.ResolveItems(stored, refused) -> items: every kind with every
-- field, the stored value where it is accepted, else the default (a refused
-- one named in `refused` as text.bar.items.<kind>.<field>). Copies.
function CV.ResolveItems(stored, refused)
    stored = type(stored) == "table" and stored or {}
    local out = {}
    for _, kind in ipairs(CV.ITEM_KINDS) do
        local d = CV.ITEMS_DEFAULT[kind]
        local s = type(stored[kind]) == "table" and stored[kind] or {}
        local it = {}
        for _, f in ipairs(CV.ITEM_FIELDS) do
            local v = s[f]
            if v == nil then
                it[f] = d[f]
            elseif ITEM_OK[f](v) then
                it[f] = v
            else
                it[f] = d[f]
                if refused then refused["text.bar.items." .. kind .. "." .. f] = "not accepted: " .. tostring(v) end
            end
        end
        out[kind] = it
    end
    return out
end

-- The active style's clock role (Flat's while no registry is loaded).
function CV.Role()
    local S = UI.Styles
    local r = S and S.Recipe and S.Recipe("clock")
    if r then return r end
    return UI.FLAT and UI.FLAT.roles and UI.FLAT.roles.clock or {}
end

--------------------------------------------------------------------------------
-- T115: 0.16.6's keys, read once (clock-v2.html C4's table).
--------------------------------------------------------------------------------
local OLD_SOURCE_SHOW = { pool = "mana", model = "mana", fsr = "fsr", none = "none" }

-- CV.Migrate(stored, facts) -> changed, dropped (a sorted list of the old
-- keys it could not read). bar.source becomes bars.<every layout>.show (the
-- model, where the line has one, also bars.<layout>.mana); bar.color becomes
-- colors.manaBar; the spark, the horizon, the height, source "time" and colour
-- "source" are dropped. A key already in the new shape is never overwritten;
-- bar.back stays. Idempotent: a second run changes nothing.
function CV.Migrate(stored, facts)
    facts = type(facts) == "table" and facts or {}
    if type(stored) ~= "table" or type(stored.over) ~= "table" then return false, {} end
    local over = stored.over
    local old = over.bar
    if type(old) ~= "table" then return false, {} end
    local changed, dropped = false, {}
    local function Each(field, value)
        for _, L in ipairs(CV.LAYOUTS) do
            local k = "bars." .. L .. "." .. field
            if Get(over, k) == nil then PutPath(over, k, value) end
        end
    end
    if old.source ~= nil then
        local show = OLD_SOURCE_SHOW[old.source]
        if show then
            Each("show", show)
            if old.source == "model" and facts.model then Each("mana", "model") end
        else
            dropped[#dropped + 1] = "bar.source"
        end
        old.source = nil
        changed = true
    end
    if old.color ~= nil then
        local c = old.color
        if c == "tone" or c == "class" or (c ~= "source" and IsColour(c)) then
            if Get(over, "colors.manaBar") == nil then PutPath(over, "colors.manaBar", c) end
        else
            dropped[#dropped + 1] = "bar.color"
        end
        old.color = nil
        changed = true
    end
    for _, k in ipairs({ "spark", "horizon", "height" }) do
        if old[k] ~= nil then
            dropped[#dropped + 1] = "bar." .. k
            old[k] = nil
            changed = true
        end
    end
    if next(old) == nil then over.bar = nil end
    table.sort(dropped)
    return changed, dropped
end

-- T142: the Bar layout's look before db.clockLook.v 2, reset once (the
-- author's ruling, "override my ingame setting"): bars.bar, text.bar,
-- frame.bar and the bar colours cleared; Line and Compact's overrides and the
-- layout kept. CV.ResetBarLook(stored) -> changed, reset (a sorted list of
-- the override keys cleared). A store at v 2 or above is left alone, so a
-- second read changes nothing.
CV.RESET_COLOURS = { "colors.manaBar", "bar.back", "colors.fillEnd", "colors.edge", "colors.fsrLine", "colors.after" }
function CV.ResetBarLook(stored)
    if type(stored) ~= "table" then return false, {} end
    local v = stored.v
    if type(v) == "number" and v >= CV.LOOK_VERSION then return false, {} end
    local over = type(stored.over) == "table" and stored.over or nil
    local reset = {}
    if over then
        local function Walk(t, prefix)
            for k, x in pairs(t) do
                local key = prefix .. "." .. tostring(k)
                if type(x) == "table" and not IsColour(x) then Walk(x, key) else reset[#reset + 1] = key end
            end
        end
        for _, area in ipairs({ "bars", "text", "frame" }) do
            local t = type(over[area]) == "table" and over[area].bar or nil
            if type(t) == "table" then Walk(t, area .. ".bar") end
            if t ~= nil then PutPath(over, area .. ".bar", nil) end
        end
        for _, k in ipairs(CV.RESET_COLOURS) do
            if Get(over, k) ~= nil then
                reset[#reset + 1] = k
                PutPath(over, k, nil)
            end
        end
    end
    stored.v = CV.LOOK_VERSION
    table.sort(reset)
    return true, reset
end

--------------------------------------------------------------------------------
-- The store: db.clockLook, written only here.
--------------------------------------------------------------------------------
local dumpAdded = false
local migrated = false

local function StoredRaw()
    local db = ST.db
    if type(db) ~= "table" then return nil end
    if type(db.clockLook) ~= "table" then db.clockLook = { layout = CV.DEFAULT_LAYOUT, over = {}, v = CV.LOOK_VERSION } end
    if type(db.clockLook.over) ~= "table" then db.clockLook.over = {} end
    return db.clockLook
end

-- CV.MigrateStored(facts, force): db.clockLook migrated once a session (at
-- MD_READY, or at the first read before it); `force` runs it again. What was
-- dropped is named by a dump line.
function CV.MigrateStored(facts, force)
    if migrated and not force then return false, {} end
    local s = StoredRaw()
    if not s then return false, {} end
    migrated = true
    local changed, dropped = CV.Migrate(s, facts or CV.lineFacts or {})
    if #dropped > 0 then
        local text = string.format("clock: %d old clock key%s dropped (%s)", #dropped, #dropped == 1 and "" or "s",
            table.concat(dropped, ", "))
        ST:AddDumpLine("clockOld", function() return text end)
    end
    -- T142: the Bar layout's look reset once, named by its own dump line
    local _, reset = CV.ResetBarLook(s)
    if #reset > 0 then
        local text = string.format("clock: T142 reset the Bar look, %d override%s (%s)", #reset,
            #reset == 1 and "" or "s", table.concat(reset, ", "))
        ST:AddDumpLine("clockReset", function() return text end)
        changed = true
    end
    return changed, dropped
end

local function Stored()
    local s = StoredRaw()
    if not s then return { layout = CV.DEFAULT_LAYOUT, over = {} } end
    if not migrated then CV.MigrateStored(CV.lineFacts) end
    return s
end

ST:RegisterCallback("MD_READY", function() CV.MigrateStored(CV.lineFacts) end)

local function OverKeys(over)
    local keys = {}
    for k in pairs(CV.OVER) do
        if Get(over, k) ~= nil then keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

-- `clock: layout bar, 2 overrides (bars.line.join, frame.line.h)` -- /st dump's line.
function CV.DumpLine()
    local s = Stored()
    local keys = OverKeys(s.over)
    local layout = Renderable(s.layout) and s.layout or (CV.DEFAULT_LAYOUT .. " (saved " .. tostring(s.layout) .. ")")
    return string.format("clock: layout %s, %d override%s%s", layout, #keys, #keys == 1 and "" or "s",
        #keys > 0 and (" (" .. table.concat(keys, ", ") .. ")") or "")
end

local function Note(s)
    if dumpAdded then return end
    if s.layout ~= CV.DEFAULT_LAYOUT or #OverKeys(s.over) > 0 then
        dumpAdded = true
        ST:AddDumpLine("clock", CV.DumpLine)
    end
end

-- CV.Look(facts): the resolved look for a line, from the saved store and the
-- active style.
function CV.Look(facts)
    local s = Stored()
    Note(s)
    return CV.Resolve(s, CV.Role(), facts)
end

local function Changed()
    ST:Fire("CLOCK_LOOK")
end

-- CV.SetLayout(key) -> true | false, why. Saved, CLOCK_LOOK fired.
function CV.SetLayout(key)
    if type(key) == "string" then key = key:lower() end
    if not Renderable(key) then
        return false, string.format("unknown layout '%s' (layouts: %s)", tostring(key), table.concat(CV.LAYOUTS, ", "))
    end
    Stored().layout = key
    Changed()
    return true
end

-- CV.Set(key, value) -> true | false, why. One override (CV.OVER's keys,
-- dotted, any depth); nil removes it. Saved, CLOCK_LOOK fired.
function CV.Set(key, value)
    local ok = CV.OVER[key]
    if not ok then return false, "not a clock look setting: " .. tostring(key) end
    if value ~= nil and not ok(value) then return false, key .. ": not accepted: " .. tostring(value) end
    PutPath(Stored().over, key, value)
    Changed()
    return true
end

-- T142: CV.SetMany(list) -> true | false, why: several overrides ({ key,
-- value } pairs, nil removes) judged first, then written together with one
-- CLOCK_LOOK (a preset); one refused writes none.
function CV.SetMany(list)
    for _, kv in ipairs(list or {}) do
        local ok = CV.OVER[kv[1]]
        if not ok then return false, "not a clock look setting: " .. tostring(kv[1]) end
        if kv[2] ~= nil and not ok(kv[2]) then return false, kv[1] .. ": not accepted: " .. tostring(kv[2]) end
    end
    local over = Stored().over
    for _, kv in ipairs(list or {}) do PutPath(over, kv[1], kv[2]) end
    Changed()
    return true
end

-- CV.Stored(key): what the store holds for one override (nil: not set).
function CV.Stored(key)
    return Copy(Get(Stored().over, key))
end

-- "Reset to style" (7.3): every override gone, the layout kept.
function CV.ResetToStyle()
    Stored().over = {}
    Changed()
    return true
end

-- T115: where a frame's point goes so its CENTRE stays put when its scale
-- (and size) change: `p` the frame's own point, x / y its offsets at scale
-- s0 and size w0 x h0; the offsets at s1, w1 x h1. The anchor is on the
-- parent (UIParent), whose scale does not move.
function CV.KeepCentre(p, x, y, s0, s1, w0, h0, w1, h1)
    p = type(p) == "string" and p or "CENTER"
    local function CX(w) if p:find("LEFT") then return w / 2 elseif p:find("RIGHT") then return -w / 2 end return 0 end
    local function CY(h) if p:find("TOP") then return -h / 2 elseif p:find("BOTTOM") then return h / 2 end return 0 end
    x, y = x or 0, y or 0
    local x1 = (x * s0 + CX(w0) * s0 - CX(w1) * s1) / s1
    local y1 = (y * s0 + CY(h0) * s0 - CY(h1) * s1) / s1
    return x1, y1
end

--------------------------------------------------------------------------------
-- The view
--------------------------------------------------------------------------------
local View = {}
View.__index = View

local function FontObj(name)
    return (UI.fontObjects and UI.fontObjects[name]) or _G[name]
end

-- A font object's size (0 when it answers none).
local function FontSize(name)
    local obj = FontObj(name)
    if obj and obj.GetFont then
        local _, s = obj:GetFont()
        if type(s) == "number" then return s end
    end
    return 0
end

-- A font string in a kit font: the template (what the client inherits), and
-- the object itself, so it follows UI.ApplyFonts wherever the template did not.
local function NewText(host, font)
    local fs = host:CreateFontString(nil, "OVERLAY", font)
    local obj = FontObj(font)
    if obj then fs:SetFontObject(obj) end
    return fs
end

local function Measure(fs, text)
    fs:SetText(text)
    local w = fs:GetStringWidth()
    if type(w) ~= "number" or w ~= w then w = 0 end
    return math.ceil(w)
end
local function MeasureH(fs, text)
    fs:SetText(text)
    local h = fs:GetStringHeight()
    if type(h) ~= "number" or h ~= h or h <= 0 then h = 12 end
    return math.ceil(h)
end

-- The measuring font strings, never shown: one in a kit font object (the
-- label slot, T93's), one given an explicit font (a layout's own size).
function View:Probe()
    if not self.probe then
        self.probe = self.parent:CreateFontString(nil, "OVERLAY", UI.FONT)
        self.probe:Hide()
    end
    return self.probe
end
function View:ProbeIn(font)
    local p = self:Probe()
    local obj = FontObj(font)
    if obj then p:SetFontObject(obj) end
    return p
end
function View:SizedProbe()
    if not self.probe2 then
        self.probe2 = self.parent:CreateFontString(nil, "OVERLAY", UI.FONT_NUM or UI.FONT)
        self.probe2:Hide()
    end
    return self.probe2
end

-- The number face at a layout's own size (follows the style's num face and
-- the font offset).
local function NumFont(size)
    local obj = FontObj(UI.FONT_NUM or UI.FONT)
    local face, _, flags = "Fonts\\ARIALN.TTF", nil, ""
    if obj and obj.GetFont then
        local f, _, fl = obj:GetFont()
        if type(f) == "string" then face = f end
        if type(fl) == "string" then flags = fl end
    end
    return face, size + (UI.fontOffset or 0), flags
end

-- Each layout's own text regions, built on first use.
local BUILD = {}

BUILD.line = function(v)
    local p = v.parent
    local set = {}
    set.label = NewText(p, UI.FONT)
    set.label:SetJustifyH("LEFT")
    -- the label slot is measured on a font string of the label's font that is
    -- never shown, so a measure never flashes on screen
    v:Probe()
    set.value = NewText(p, UI.FONT_NUM or UI.FONT)
    set.value:SetJustifyH("LEFT")
    set.second = NewText(p, UI.FONT)
    set.second:SetJustifyH("RIGHT")
    set.msg = NewText(p, UI.FONT)
    set.msg:SetText("")
    set.msg:Hide()
    return set
end

BUILD.compact = function(v)
    local p = v.parent
    local set = {}
    set.label = NewText(p, UI.FONT_SMALL or UI.FONT)
    set.label:SetJustifyH("LEFT")
    set.value = p:CreateFontString(nil, "OVERLAY", UI.FONT_NUM or UI.FONT)
    set.value:SetJustifyH("LEFT")
    set.msg = NewText(p, UI.FONT_SMALL or UI.FONT)
    set.msg:SetText("")
    set.msg:Hide()
    v:SizedProbe()
    return set
end

BUILD.bar = function(v)
    local p = v.parent
    -- the text sits on a frame above the bars (the bars are child frames and
    -- draw over the parent's own regions), placed over the mana bar
    local holder = CreateFrame("Frame", nil, p)
    -- T142: one font string per text kind, made the first time it is drawn;
    -- the label's and the time's are the view's label / value
    local set = { holder = holder, items = {} }
    for _, kind in ipairs({ "label", "time" }) do
        local fs = NewText(holder, UI.FONT)
        fs:SetText("")
        fs:Hide()
        set.items[kind] = fs
    end
    set.label, set.value = set.items.label, set.items.time
    set.msg = NewText(holder, UI.FONT)
    set.msg:SetText("")
    set.msg:Hide()
    return set
end

local function Pieces(set)
    local out = {}
    for _, k in ipairs({ "label", "value", "second", "right2", "msg" }) do
        if set[k] then out[#out + 1] = set[k] end
    end
    for _, kind in ipairs(CV.ITEM_KINDS) do
        local fs = set.items and set.items[kind]
        if fs and fs ~= set.label and fs ~= set.value then out[#out + 1] = fs end
    end
    return out
end

-- T116: a slot region made the first time it is drawn (Line's second Right,
-- Compact's Bottom), so a clock that never draws one keeps T115's regions.
local function MakeRegion(host, key)
    local fs = NewText(host, key == "second" and (UI.FONT_SMALL or UI.FONT) or UI.FONT)
    fs:SetJustifyH(key == "right2" and "RIGHT" or "LEFT")
    fs:SetText("")
    fs:Hide()
    return fs
end

function View:Set(key)
    self.sets = self.sets or {}
    if not self.sets[key] then self.sets[key] = BUILD[key](self) end
    return self.sets[key]
end

-- Which bars a look draws: manaOn (the mana bar), and the five-second rule's
-- element -- "strip" (stacked under / over the mana bar), "solo" (the strip in
-- the mana bar's place, show = fsr), "veil", "chip", "sweep", or nil.
local function Element(bars)
    local show = bars.show
    if show == "none" then return false, nil end
    if show == "mana" then return true, nil end
    if show == "fsr" then return false, "solo" end
    local j = bars.join
    if j == "veil" then return true, "veil" end
    if j == "chip" then return true, "chip" end
    if j == "sweep" then return true, "sweep" end
    return true, "strip"
end

-- The frame's size: the look's, never under the measured minimum (a size
-- under it stops there and is named in look.refused).
local function Fit(look, minW, minH)
    local fr = look.frame or {}
    local w, h = fr.w or look.width, fr.h or look.height
    local L = look.layout
    look.refused = look.refused or {}
    local kw, kh = "frame." .. L .. ".w", "frame." .. L .. ".h"
    if w < minW then
        look.refused[kw] = "under this layout's minimum (" .. minW .. ")"
        w = minW
    elseif look.refused[kw] and look.refused[kw]:find("^under") then
        look.refused[kw] = nil
    end
    if h < minH then
        look.refused[kh] = "under this layout's minimum (" .. minH .. ")"
        h = minH
    elseif look.refused[kh] and look.refused[kh]:find("^under") then
        look.refused[kh] = nil
    end
    return w, h
end

-- The layout's metrics: the frame's size, its minimum, where each piece and
-- each bar goes, from measures in the layout's own fonts. A table compared
-- field by field, so a paint re-anchors only when something moved. Bars are
-- { x, y, w, h } from the frame's BOTTOMLEFT.
local METRICS = {}

-- CV.HasSecondary(look) -> whether the line layout can draw a secondary
-- segment: false only when the look's switches drop both the rest and the
-- cooldown segment (ClockFace.Segments' look.show; an absent switch keeps it).
function CV.HasSecondary(look)
    local sh = type(look) == "table" and look.show
    if type(sh) ~= "table" then return true end
    return not (sh.rest == false and sh.cd == false)
end

-- T116: which region draws each slot of a layout (Line's second Right and
-- Compact's Bottom are made the first time one is drawn).
CV.REGION = {
    line = { left = "label", main = "value", right = "second", right2 = "right2" },
    compact = { top = "label", main = "value", bottom = "second" },
    -- T142: the Bar layout draws items (CV.ITEM_KINDS), not slots
}

-- The widest word each kind draws (the slot's room, so only a value's own
-- digits move): the time per word option, then the others. A rest / cd slot
-- takes no room while the line's switches drop that segment.
CV.TIME_SAMPLE = { line = CV.VALUE_SAMPLE, sec = ">600s vv", msec = ">9m59 vv" }
CV.KIND_SAMPLE = { pct = "~100%", mana = "~99999", manaOfMax = "~99999/99999", mp5 = "~999 mp5", fsr = "5SR 5.0" }

-- A look's resolved text for its layout (a look built before T116's resolver
-- -- or by hand -- reads the layout's defaults).
local function TextOf(look, layout)
    local t = look.text
    if type(t) == "table" and t.timeAt then return t end
    local r = ST.ClockFace.ResolveText(type(t) == "table" and t or nil, layout)
    if type(t) == "table" then
        r.size, r.outline, r.shadow, r.numbers = t.size, t.outline, t.shadow, t.numbers
    end
    return r
end

-- A font object's face, size, flags and shadow offset.
local function ObjFont(name)
    local obj = FontObj(name)
    local face, size, flags
    if obj and obj.GetFont then face, size, flags = obj:GetFont() end
    if type(face) ~= "string" then face = "Fonts\\FRIZQT__.TTF" end
    if type(size) ~= "number" then size = 12 end
    if type(flags) ~= "string" then flags = "" end
    local sx, sy
    if obj and obj.GetShadowOffset then sx, sy = obj:GetShadowOffset() end
    if type(sx) ~= "number" or type(sy) ~= "number" then sx, sy = 1, -1 end
    return face, size, flags, sx, sy
end

-- The font a slot draws in: { face, size, flags, shadowX, shadowY }. Unset
-- Size: the kit's fonts as before T116 (Line and Bar 13, Compact's main 22
-- and its small slots FONT_SMALL), each following the window text size; a
-- set Size exactly (Compact's small slots at half of it). The time's home
-- in the number face unless `numbers` is "labels".
local function SlotFont(layout, slot, t)
    local home = ST.ClockFace.TEXT_HOME[layout]
    local small = layout == "compact" and slot ~= "main"
    local face, size, flags, sx, sy = ObjFont(small and (UI.FONT_SMALL or UI.FONT) or UI.FONT)
    if slot == home then
        local nface, nsize, nflags, nsx, nsy = ObjFont(UI.FONT_NUM or UI.FONT)
        size, flags, sx, sy = nsize, nflags, nsx, nsy
        if layout == "compact" then size = (CV.LAYOUT.compact.valueSize or 22) + (UI.fontOffset or 0) end
        if t.numbers ~= "labels" then face = nface end
    end
    if type(t.size) == "number" then
        size = small and math.max(6, math.floor(t.size / 2 + 0.5)) or t.size
    end
    if t.outline and t.outline ~= "none" then flags = CV.OUTLINE_FLAGS[t.outline] or flags end
    if t.shadow == false then sx, sy = 0, 0 end
    return { face, size, flags, sx, sy }
end

-- A word's width and height in a slot's font (0, 0 for no word).
local function MeasureIn(v, font, text)
    if text == nil or text == "" then return 0, 0 end
    local p = v:Probe()
    p:SetFont(font[1], font[2], font[3])
    local w = Measure(p, text)
    local h = MeasureH(p, text)
    return w, math.max(h, math.ceil(font[2]))
end

-- The widest word a slot holds, or nil for none.
local function SlotSample(look, t, layout, slot)
    local kind = t[slot]
    local label = look.labelSample or "FULL"
    if slot == t.timeAt then
        local s = CV.TIME_SAMPLE[t.time] or CV.VALUE_SAMPLE
        if t.timeLabel then return label .. " " .. s end
        -- the label drawn nowhere: Forever's "~" stays on the time
        if t[ST.ClockFace.TEXT_LABEL[layout]] ~= "label" and label:sub(1, 1) == "~" then s = "~" .. s end
        return s
    end
    if kind == "label" then return label end
    if kind == "pct" or kind == "mp5" or kind == "fsr" then return CV.KIND_SAMPLE[kind] end
    if kind == "mana" then return t.ofMax and CV.KIND_SAMPLE.manaOfMax or CV.KIND_SAMPLE.mana end
    if kind == "rest" then return CV.HasSecondary(look) and CV.SECOND_SAMPLE or nil end
    if kind == "cd" then
        local sh = look.show
        if type(sh) == "table" and sh.cd == false then return nil end
        return CV.SECOND_SAMPLE
    end
    return nil
end

-- Every slot of a layout measured: fonts, widths, heights.
local function Slots(v, look, layout, t)
    local fonts, w, h = {}, {}, {}
    for _, slot in ipairs(ST.ClockFace.TEXT_SLOTS[layout]) do
        fonts[slot] = SlotFont(layout, slot, t)
        w[slot], h[slot] = MeasureIn(v, fonts[slot], SlotSample(look, t, layout, slot))
    end
    return fonts, w, h
end

-- The tallest drawn slot (the home's font size when nothing is drawn).
local function RowH(fonts, w, h, slots, home)
    local row = 0
    for _, slot in ipairs(slots) do
        if w[slot] > 0 and h[slot] > row then row = h[slot] end
    end
    if row == 0 then row = math.ceil(fonts[home][2]) end
    return math.ceil(row)
end

METRICS.line = function(v, look)
    local b = look.bars
    local manaOn, el = Element(b)
    local s = b.fsr or 3
    local inset = CV.INSET
    local chipOff = el == "chip" and 13 or 0
    local t = TextOf(look, "line")
    local fonts, w, h = Slots(v, look, "line", t)
    local leftW, mainW, rightW = w.left, w.main, w.right
    -- the minimum without Right2: Left, the gap, Main, then (C2: 100 x 30
    -- with no secondary) the gap and Right only while Right draws something
    local minBase = math.ceil(inset + chipOff + leftW + (leftW > 0 and CV.GAP or 0) + mainW
        + (rightW > 0 and (CV.GAP + rightW) or 0) + inset)
    -- Right2 (answer 3): offered only where the frame holds its widest word,
    -- two spaces left of Right
    local gap2 = MeasureIn(v, fonts.right2, "  ")
    local widest = 0
    for _, k in ipairs({ "pct", "mp5", "fsr" }) do
        widest = math.max(widest, (MeasureIn(v, fonts.right2, CV.KIND_SAMPLE[k])))
    end
    widest = math.max(widest, (MeasureIn(v, fonts.right2, t.ofMax and CV.KIND_SAMPLE.manaOfMax or CV.KIND_SAMPLE.mana)),
        (MeasureIn(v, fonts.right2, CV.SECOND_SAMPLE)))
    local need = math.ceil(minBase + (rightW > 0 and gap2 or CV.GAP) + widest)
    local rowH = RowH(fonts, w, h, { "left", "main", "right", "right2" }, "main")
    local top = 4 + rowH + 2
    local anyBar = manaOn or el ~= nil
    local minH = anyBar and (top + 5 + s + 1 + 2) or (rowH + 8)
    local now = Fit(look, minBase, minH)
    local fits = now >= need
    local wantR2 = t.right2 ~= nil and t.right2 ~= "none"
    local drawR2 = wantR2 and fits and w.right2 > 0
    look.refused = look.refused or {}
    if wantR2 and not fits then
        look.refused["text.line.right2"] = string.format("needs %d px of width (now %d)", need, now)
    elseif look.refused["text.line.right2"] and look.refused["text.line.right2"]:find("^needs") then
        look.refused["text.line.right2"] = nil
    end
    local minW = drawR2 and need or minBase
    local fw, fh = Fit(look, minW, minH)
    local barW = fw - 20
    local manaH = fh - top - 5 - s - 1
    local m = { w = fw, h = fh, minW = minW, minH = minH, manaOn = manaOn, el = el,
        fits2 = fits, need2 = need, now2 = now,
        fonts = { label = fonts.left, value = fonts.main, second = fonts.right },
        label = { "TOPLEFT", inset + chipOff, CV.TOP },
        value = { "TOPLEFT", inset + chipOff + (leftW > 0 and (leftW + CV.GAP) or 0), CV.TOP },
        second = { "TOPRIGHT", -inset, CV.TOP },
        msg = { "TOP", 0, CV.TOP } }
    if drawR2 then
        m.fonts.right2 = fonts.right2
        m.right2 = { "TOPRIGHT", -(inset + (rightW > 0 and (rightW + gap2) or 0)), CV.TOP }
    end
    if manaOn and el == "strip" then
        if b.order == "fsrOver" then
            m.bar = { 10, 5, barW, manaH }
            m.strip = { 10, 5 + manaH + 1, barW, s }
        else
            m.strip = { 10, 5, barW, s }
            m.bar = { 10, 5 + s + 1, barW, manaH }
        end
    elseif manaOn then
        m.bar = { 10, 5, barW, manaH }
    elseif el == "solo" then
        m.strip = { 10, 5, barW, manaH }
    end
    if el == "chip" then m.chip = { "TOPLEFT", inset, -(4 + (rowH - 10) / 2), 10 } end
    return m
end

METRICS.compact = function(v, look)
    local b = look.bars
    local manaOn, el = Element(b)
    local s = b.fsr or 3
    local inset = look.inset or 6
    local chipOff = el == "chip" and 12 or 0
    local t = TextOf(look, "compact")
    local fonts, w, h = Slots(v, look, "compact", t)
    local topW, topH = w.top, w.top > 0 and h.top or 0
    local mainW, mainH = w.main, math.max(h.main, math.ceil(fonts.main[2]))
    -- Bottom (C2): its row and one pixel under Main, only while it draws
    local botW, botH = w.bottom, w.bottom > 0 and (h.bottom + 1) or 0
    local textBottom = 3 + topH + mainH + botH
    local anyBar = manaOn or el ~= nil
    local minW = math.ceil(2 * inset + math.max(chipOff + topW, mainW, botW))
    local minH = anyBar and (textBottom + 6 + s) or (textBottom + 4)
    local fw, fh = Fit(look, minW, minH)
    local barW = fw - 2 * inset
    local manaH = fh - textBottom - 4 - s
    local m = { w = fw, h = fh, minW = minW, minH = minH, manaOn = manaOn, el = el,
        fonts = { label = fonts.top, value = fonts.main },
        label = { "TOPLEFT", inset + chipOff, -3 },
        value = { "TOPLEFT", inset, -(3 + topH) },
        msg = { "CENTER", 0, 0 }, msgW = fw - 4 }
    if botW > 0 then
        m.fonts.second = fonts.bottom
        m.second = { "TOPLEFT", inset, -(3 + topH + mainH + 1) }
    end
    if manaOn and el == "strip" then
        if b.order == "fsrOver" then
            m.bar = { inset, 2, barW, manaH }
            m.strip = { inset, 2 + manaH + 1, barW, s }
        else
            m.strip = { inset, 2, barW, s }
            m.bar = { inset, 2 + s + 1, barW, manaH }
        end
    elseif manaOn then
        m.bar = { inset, 2, barW, manaH }
    elseif el == "solo" then
        m.strip = { inset, 2, barW, manaH }
    end
    local chipRow = topH > 0 and topH or 9
    if el == "chip" then m.chip = { "TOPLEFT", inset, -3 - (chipRow - 9) / 2, 9 } end
    return m
end

-- T140: the width the Bar layout's words need: Left and Right with a gap
-- between; with a Centre, each side as wide as the wider of the two so the
-- centre stays in the middle.
function CV.BarWordsW(leftW, rightW, centerW)
    centerW = centerW or 0
    if centerW > 0 then
        local side = math.max(leftW, rightW)
        return 2 * side + centerW + ((side > 0) and 2 * CV.GAP or 0)
    end
    return leftW + ((leftW > 0 and rightW > 0) and 2 * CV.GAP or 0) + rightW
end

-- T142: the font the Bar layout's texts draw in: EllesmereUI's, read live
-- through the Ellesmere style's own path (UI/Style_Ellesmere.lua E.FontPath),
-- or the kit's. CV.BarFont(look) -> face, why (why: eui asked, not there).
function CV.BarFont(look)
    local b = type(look) == "table" and look.bars or {}
    local why
    if b.font == "eui" then
        local E = UI.Ellesmere
        local path = E and E.FontPath and E.FontPath()
        if type(path) == "string" and path ~= "" then return path end
        why = CV.FONT_EUI_MISSING
    end
    local obj = FontObj(UI.FONT)
    local face
    if obj and obj.GetFont then face = obj:GetFont() end
    if type(face) ~= "string" then face = "Fonts\\ARIALN.TTF" end
    return face, why
end

-- An item's font: { face, size, flags, shadowX, shadowY }; its own outline
-- always applies (shadow: a 1-px drop shadow, the others none).
local function ItemFont(face, it)
    local flags = CV.ITEM_OUTLINE[it.outline] or ""
    local sx, sy = 0, 0
    if it.outline == "shadow" then sx, sy = 1, -1 end
    return { face, it.size, flags, sx, sy }
end

local SUFFIX = { left = "LEFT", center = "", right = "RIGHT" }

-- T142: the Bar layout -- THE FRAME IS THE BAR (its width the frame's, its
-- height bars.bar.height); every text an item at its own place: inside (from
-- the bar's left edge, centre or right edge, 2 px in when not centred), or
-- above / below, hanging outside the frame from its top / bottom edge, so a
-- text never makes the bar or the frame taller. T144: no text sets the width
-- either -- the frame's width is frame.bar.w (and its height the bar's), at any
-- size, place or offset; an inside text wider than the bar runs over its ends.
METRICS.bar = function(v, look)
    local b = look.bars
    local manaOn, el = Element(b)
    local s = b.fsr or 3
    local barH = b.height or CV.BAR_HEIGHT
    local items = look.items or CV.ResolveItems(nil)
    look.refused = look.refused or {}
    -- the face read once per look (View:SetLook), not at every paint
    local face, whyF = v.barFace, v.barFaceWhy
    if not face then face, whyF = CV.BarFont(look) end
    if whyF then look.refused["bars.bar.font"] = whyF else look.refused["bars.bar.font"] = nil end
    local fonts, specs = {}, {}
    for _, kind in ipairs(CV.ITEM_KINDS) do
        local it = items[kind]
        if it and it.on then fonts[kind] = ItemFont(face, it) end
    end
    local chipExtra = el == "chip" and (barH + 2) or 0
    -- T144: the minimum is the bar's own (a chip and 20 px of bar), never a
    -- text's measure: no text, at any size or place, changes the frame's size
    local minW = chipExtra + 20
    local fw = Fit(look, minW, 0)
    local fh = barH
    local barX, barW = chipExtra, fw - chipExtra
    local m = { w = fw, h = fh, minW = minW, minH = fh, manaOn = manaOn, el = el,
        items = specs, itemFonts = fonts, msg = { "CENTER", 0, 0 } }
    if manaOn and el == "strip" then
        local manaH = math.max(1, barH - s - 1)
        if b.order == "fsrOver" then
            m.bar = { barX, 0, barW, manaH }
            m.strip = { barX, manaH + 1, barW, s }
        else
            m.strip = { barX, 0, barW, s }
            m.bar = { barX, s + 1, barW, manaH }
        end
    elseif manaOn then
        m.bar = { barX, 0, barW, barH }
    elseif el == "solo" then
        m.strip = { barX, 0, barW, barH }
    end
    if el == "chip" then m.chip = { "BOTTOMLEFT", 0, 0, barH } end
    -- the texts' anchor: the bar's own rect (right of a chip)
    m.holder = { barX, 0, barW, fh }
    local gap = CV.ITEM_GAP
    if b.frame == "border" then gap = gap + (b.border or 0) end
    for _, kind in ipairs(CV.ITEM_KINDS) do
        local it = items[kind]
        if it and it.on then
            local suf = SUFFIX[it.align] or ""
            if it.place == "inside" then
                local p = (suf == "") and "CENTER" or suf
                local pad = (suf == "LEFT" and CV.ITEM_PAD) or (suf == "RIGHT" and -CV.ITEM_PAD) or 0
                specs[kind] = { p, p, pad + it.x, it.y }
            elseif it.place == "above" then
                specs[kind] = { "BOTTOM" .. suf, "TOP" .. suf, it.x, gap + it.y }
            else
                specs[kind] = { "TOP" .. suf, "BOTTOM" .. suf, it.x, -gap + it.y }
            end
        end
    end
    return m
end


local function SameMetrics(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, x in pairs(a) do
        local y = b[k]
        if type(x) == "table" then
            if not SameMetrics(x, y) then return false end
        elseif y ~= x then
            return false
        end
    end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function Anchor(r, spec, rel)
    r:ClearAllPoints()
    r:SetPoint(spec[1], rel, spec[1], spec[2], spec[3])
end
local function PlaceRect(r, rect, rel)
    r:ClearAllPoints()
    r:SetPoint("BOTTOMLEFT", rel, "BOTTOMLEFT", rect[1], rect[2])
    r:SetSize(rect[3], rect[4])
end
local function ShowIf(r, on)
    if on then r:Show() else r:Hide() end
end

-- T139: each bar's background its own size, its edge `border` physical
-- pixels wider on every side (T41's one pixel was the background's), and the
-- shape's masks a square of their region's height at each end.
local function SizeMasks(pair, region, h)
    if not pair or not region then return end
    local l, r = pair[1], pair[2]
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0)
    l:SetSize(h, h)
    r:ClearAllPoints()
    r:SetPoint("TOPRIGHT", region, "TOPRIGHT", 0, 0)
    r:SetSize(h, h)
end

function View:SizeBack()
    local e = UI.px and UI.px(1, self.parent) or 1
    local m = self.metrics or {}
    local bd = ((self.look and self.look.bars and self.look.bars.border) or 1) * e
    -- T142: the Bar layout's frame: None and the game's art draw no border
    if self.frameMode == "none" or self.frameMode == "game" then bd = 0 end
    local mk = self.masks or {}
    if m.bar then
        self.barBack:SetSize(m.bar[3], m.bar[4])
        self.barEdge:SetSize(m.bar[3] + 2 * bd, m.bar[4] + 2 * bd)
        SizeMasks(mk.bar, self.bar, m.bar[4])
        SizeMasks(mk.barBack, self.barBack, m.bar[4])
        SizeMasks(mk.barEdge, self.barEdge, m.bar[4] + 2 * bd)
    end
    if m.strip then
        self.stripBack:SetSize(m.strip[3], m.strip[4])
        self.stripEdge:SetSize(m.strip[3] + 2 * bd, m.strip[4] + 2 * bd)
        SizeMasks(mk.strip, self.strip, m.strip[4])
        SizeMasks(mk.stripBack, self.stripBack, m.strip[4])
        SizeMasks(mk.stripEdge, self.stripEdge, m.strip[4] + 2 * bd)
    end
    ShowIf(self.barEdge, m.bar ~= nil and bd > 0)
    ShowIf(self.stripEdge, m.strip ~= nil and bd > 0)
    self.snappedPx = e
    self:PlaceGame()
end

--------------------------------------------------------------------------------
-- T142: the game's bar frame (EllesmereUI's "Blizzard style", read from its
-- ERB_ApplyBlizzBarChrome / ERB_BlizzBarShadow): the frame atlas on a
-- BACKGROUND -2 texture from (-2, 3) to (6, -7) round the bar (most of that
-- reach is the art's own shadow; its rim is about 1 px), the mask atlas on
-- the mana bar's fill and background, and four black bevel strips at OVERLAY
-- -3 on the mana bar, each masked too -- top max(2, h * 0.2) at 0.55, bottom
-- max(1, h * 0.1) at 0.30, each end max(2, w * 0.15) at 0.35, fading to 0.
-- The moving 5SR line (OVERLAY 1-2) stays above the bevel. Built the first
-- time the game frame is drawn; off, the masks clip nothing.
--------------------------------------------------------------------------------
-- CV.GameFrameOK() -> true, or false and why: the client has both atlases
-- (asked through ST.API; ClockView reads no client value itself).
function CV.GameFrameOK()
    local A = ST.API
    if not (A and A.HasAtlas) then return false, CV.GAME_REFUSED end
    if A.HasAtlas(CV.GAME_ATLAS.frame) and A.HasAtlas(CV.GAME_ATLAS.mask) then return true end
    return false, CV.GAME_REFUSED
end

local function NoSnap(tex)
    if tex.SetSnapToPixelGrid then pcall(tex.SetSnapToPixelGrid, tex, false) end
    if tex.SetTexelSnappingBias then pcall(tex.SetTexelSnappingBias, tex, 0) end
end

function View:BuildGame()
    if self.game then return self.game end
    local p, bar = self.parent, self.bar
    local g = { on = {} }
    g.art = p:CreateTexture(nil, "BACKGROUND", nil, -2)
    NoSnap(g.art)
    g.art:Hide()
    g.mask = bar:CreateMaskTexture()
    g.mask:SetAllPoints(bar)
    g.backMask = p:CreateMaskTexture()
    g.backMask:SetAllPoints(self.barBack)
    self.barBack:AddMaskTexture(g.backMask)
    g.bevel = {}
    for _, k in ipairs({ "top", "bottom", "left", "right" }) do
        local t = bar:CreateTexture(nil, "OVERLAY", nil, -3)
        t:SetTexture(UI.whiteTexture)
        t:AddMaskTexture(g.mask)
        NoSnap(t)
        t:Hide()
        g.bevel[k] = t
    end
    self.game = g
    return g
end

-- The fill texture clipped by the game mask (SetStatusBarTexture may hand
-- back a new one).
local function GameClip(g, tex)
    if type(tex) ~= "table" or type(tex.AddMaskTexture) ~= "function" or g.on[tex] then return end
    g.on[tex] = true
    tex:AddMaskTexture(g.mask)
end

function View:PlaceGame()
    local m = self.metrics or {}
    local on = self.frameMode == "game" and m.bar ~= nil
    if not on then
        local g = self.game
        if g then
            g.art:Hide()
            for _, t in pairs(g.bevel) do t:Hide() end
            -- off: the masks clip nothing
            pcall(g.mask.SetTexture, g.mask, UI.whiteTexture, "CLAMPTOWHITE", "CLAMPTOWHITE")
            pcall(g.backMask.SetTexture, g.backMask, UI.whiteTexture, "CLAMPTOWHITE", "CLAMPTOWHITE")
        end
        return
    end
    local g = self:BuildGame()
    local p, bar = self.parent, self.bar
    local A = CV.GAME_ATLAS
    g.art:SetAtlas(A.frame)
    g.mask:SetAtlas(A.mask)
    g.backMask:SetAtlas(A.mask)
    GameClip(g, bar.GetStatusBarTexture and bar:GetStatusBarTexture())
    -- round the whole bar (the strip too, when stacked)
    local x0, w, h = m.holder and m.holder[1] or 0, m.holder and m.holder[3] or m.w, m.h
    local R = CV.GAME_REACH
    g.art:ClearAllPoints()
    g.art:SetPoint("TOPLEFT", p, "BOTTOMLEFT", x0 + R.left, h + R.top)
    g.art:SetPoint("BOTTOMRIGHT", p, "BOTTOMLEFT", x0 + w + R.right, R.bottom)
    g.art:Show()
    local bw, bh = m.bar[3], m.bar[4]
    local top = math.max(2, math.floor(bh * 0.2))
    local bottom = math.max(1, math.floor(bh * 0.1))
    local side = math.max(2, math.floor(bw * 0.15))
    local B = g.bevel
    B.top:ClearAllPoints()
    B.top:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    B.top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    B.top:SetHeight(top)
    ST.API.SetGradient(B.top, 0, 0, 0, 0, 0, 0, 0, 0.55, "VERTICAL")
    B.bottom:ClearAllPoints()
    B.bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    B.bottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    B.bottom:SetHeight(bottom)
    ST.API.SetGradient(B.bottom, 0, 0, 0, 0.30, 0, 0, 0, 0, "VERTICAL")
    B.left:ClearAllPoints()
    B.left:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    B.left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    B.left:SetWidth(side)
    ST.API.SetGradient(B.left, 0, 0, 0, 0.35, 0, 0, 0, 0)
    B.right:ClearAllPoints()
    B.right:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    B.right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    B.right:SetWidth(side)
    ST.API.SetGradient(B.right, 0, 0, 0, 0, 0, 0, 0, 0.35)
    for _, t in pairs(B) do t:Show() end
end

-- T139: a pair of masks on `owner` (nil where the client has none), and the
-- textures each clips -- added once, the shape changes only their files.
local function MaskPair(owner)
    if type(owner.CreateMaskTexture) ~= "function" then return nil end
    local ok1, l = pcall(owner.CreateMaskTexture, owner)
    local ok2, r = pcall(owner.CreateMaskTexture, owner)
    if not (ok1 and ok2 and type(l) == "table" and type(r) == "table") then return nil end
    return { l, r, on = {} }
end
local function Clip(pair, tex)
    if not pair or type(tex) ~= "table" or type(tex.AddMaskTexture) ~= "function" or pair.on[tex] then return end
    pair.on[tex] = true
    tex:AddMaskTexture(pair[1])
    tex:AddMaskTexture(pair[2])
end

-- The shape's files into every pair (a rectangle: the white texture, which
-- clips nothing); the bars' fill textures clipped (SetStatusBarTexture may
-- hand back a new one). A shape the client cannot mask is named in refused.
function View:ApplyShape()
    local look = self.look
    local base = CV.MASKS[look.bars.shape]
    local mk = self.masks
    if base and not mk then
        look.refused = look.refused or {}
        look.refused["bars." .. look.layout .. ".shape"] = CV.MASK_REFUSED
        return
    end
    if not mk then return end
    Clip(mk.bar, self.bar.GetStatusBarTexture and self.bar:GetStatusBarTexture())
    Clip(mk.strip, self.strip.GetStatusBarTexture and self.strip:GetStatusBarTexture())
    for _, pair in pairs(mk) do
        local l = base and (CV.MEDIA .. base .. "L") or UI.whiteTexture
        local r = base and (CV.MEDIA .. base .. "R") or UI.whiteTexture
        pcall(pair[1].SetTexture, pair[1], l, "CLAMPTOWHITE", "CLAMPTOWHITE")
        pcall(pair[2].SetTexture, pair[2], r, "CLAMPTOWHITE", "CLAMPTOWHITE")
    end
    self.maskFile = base
end

-- T139: the look's colour for a bar part, as r, g, b, a.
local COLOUR_DEFAULT = { fsrLine = "FSR_COLOR", after = "REGEN_COLOR", fillEnd = "FILL_END_COLOR", edge = "EDGE_COLOR" }
function View:Col(key)
    local c = self.look and self.look.colors and self.look.colors[key]
    if c ~= nil then
        local rgba = UI.SkinColour and UI.SkinColour(c) or c
        if type(rgba) == "table" then return rgba[1], rgba[2], rgba[3], rgba[4] or 1 end
    end
    local d = CV[COLOUR_DEFAULT[key]]
    return d[1], d[2], d[3], 1
end

-- The parts painted once per look in their colours (the rule's marks are
-- painted again by PaintFSR from self.cF / self.cG).
function View:ApplyColours()
    local F, G = { self:Col("fsrLine") }, { self:Col("after") }
    self.cF, self.cG = F, G
    local er, eg, eb, ea = self:Col("edge")
    self.barEdge:SetColorTexture(er, eg, eb, ea)
    self.stripEdge:SetColorTexture(er, eg, eb, ea)
    self.veil:SetColorTexture(F[1], F[2], F[3], CV.VEIL_ALPHA)
    self.veilEdge:SetColorTexture(F[1], F[2], F[3], 1)
    self.greenLine:SetColorTexture(G[1], G[2], G[3], 1)
    self.sweep:SetColorTexture(F[1], F[2], F[3], 1)
end

-- Gradient's two colours on a bar's fill (after its colour, which they replace).
function View:Gradient(bar, r, g, b)
    if self.look.bars.texture ~= "gradient" or not bar.GetStatusBarTexture then return end
    local er, eg, eb = self:Col("fillEnd")
    ST.API.SetGradient(bar:GetStatusBarTexture(), er, eg, eb, 1, r, g, b, 1)
end

-- Apply a layout's metrics: the frame's size, the pieces, the bars. Never the
-- frame's Show / Hide.
function View:Place(m)
    local p = self.parent
    local set = self.active
    p:SetSize(m.w, m.h)
    self.metrics = m
    self.manaOn, self.el = m.manaOn, m.el

    -- the text
    local rel = p
    if set.holder then
        PlaceRect(set.holder, m.holder, p)
        set.holder:SetFrameLevel((self.bar:GetFrameLevel() or 1) + 2)
        rel = set.holder
    end
    -- T142: the Bar layout's items, each in its font at its place (a kind
    -- made the first time it is drawn), the others emptied
    if m.items then
        for _, kind in ipairs(CV.ITEM_KINDS) do
            local spec, font = m.items[kind], m.itemFonts and m.itemFonts[kind]
            local fs = set.items[kind]
            if spec and not fs then
                fs = NewText(rel, UI.FONT)
                set.items[kind] = fs
            end
            if fs then
                if spec then
                    fs:SetFont(font[1], font[2], font[3])
                    -- T144: one line at any size, running over the bar's ends
                    -- (one anchor point and no width, so never wrapped or cut)
                    if fs.SetWordWrap then fs:SetWordWrap(false) end
                    fs:SetShadowOffset(font[4], font[5])
                    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
                    local p = spec[1]
                    fs:SetJustifyH((p:find("LEFT") and "LEFT") or (p:find("RIGHT") and "RIGHT") or "CENTER")
                    fs:ClearAllPoints()
                    fs:SetPoint(spec[1], rel, spec[2], spec[3], spec[4])
                else
                    fs:SetText("")
                    fs:Hide()
                end
            end
        end
    end
    -- T116: each slot's region in its font, at its place; a region the
    -- metrics leave out is emptied
    for _, k in ipairs(m.items and {} or { "label", "value", "second", "right2" }) do
        local spec, font = m[k], m.fonts and m.fonts[k]
        if spec and not set[k] then set[k] = MakeRegion(rel, k) end
        local fs = set[k]
        if fs then
            if spec then
                if font then
                    fs:SetFont(font[1], font[2], font[3])
                    fs:SetShadowOffset(font[4], font[5])
                end
                Anchor(fs, spec, rel)
            else
                fs:SetText("")
                fs:Hide()
            end
        end
    end
    self.label, self.value, self.second, self.right2 = set.label, set.value, set.second, set.right2
    Anchor(set.msg, m.msg, rel)
    if m.msgW then set.msg:SetWidth(m.msgW) end

    -- the bars and their backings
    if m.bar then PlaceRect(self.bar, m.bar, p) end
    ShowIf(self.bar, m.bar ~= nil)
    ShowIf(self.barBack, m.bar ~= nil)
    if m.strip then PlaceRect(self.strip, m.strip, p) end
    ShowIf(self.strip, m.strip ~= nil)
    ShowIf(self.stripBack, m.strip ~= nil)
    self.barW = m.bar and m.bar[3] or 0
    self.barH = m.bar and m.bar[4] or 0
    self.stripW = m.strip and m.strip[3] or 0
    self.stripH = m.strip and m.strip[4] or 0

    -- the chip
    if m.chip then
        local c = m.chip
        self.chip:ClearAllPoints()
        self.chip:SetPoint(c[1], p, c[1], c[2], c[3])
        self.chip:SetSize(c[4], c[4])
        self.chip:SetFrameLevel((self.bar:GetFrameLevel() or 1) + 1)
    end
    ShowIf(self.chip, m.chip ~= nil)

    -- the veil, its edge and the green line: on the mana bar
    self.veil:ClearAllPoints()
    self.veil:SetPoint("RIGHT", self.bar, "RIGHT", 0, 0)
    self.veil:SetHeight(self.barH > 0 and self.barH or 1)
    self.veilEdge:ClearAllPoints()
    self.veilEdge:SetPoint("TOPRIGHT", self.veil, "TOPLEFT", 0, 0)
    self.veilEdge:SetPoint("BOTTOMRIGHT", self.veil, "BOTTOMLEFT", 0, 0)
    self.veilEdge:SetWidth(UI.px and UI.px(1, p) or 1)
    self.greenLine:ClearAllPoints()
    self.greenLine:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 0, 0)
    self.greenLine:SetPoint("TOPRIGHT", self.bar, "TOPRIGHT", 0, 0)
    self.greenLine:SetHeight(1)
    -- T135: the moving line, as tall as the mana bar
    local px = UI.px and UI.px(1, p) or 1
    local sw = UI.px and UI.px(CV.SWEEP_WIDTH, p) or CV.SWEEP_WIDTH
    self.sweep:SetSize(sw, self.barH > 0 and self.barH or 1)
    self.sweepBack:SetSize(sw + 2 * px, self.barH > 0 and self.barH or 1)
    if m.el ~= "veil" and m.el ~= "sweep" then self.greenLine:Hide() end
    if m.el ~= "veil" then
        self.veil:Hide()
        self.veilEdge:Hide()
    end
    if m.el ~= "sweep" then
        self.sweep:Hide()
        self.sweepBack:Hide()
    end
    -- the tick mark: on the strip
    self.tickMark:SetSize(UI.px and UI.px(CV.TICK_WIDTH, p) or CV.TICK_WIDTH, self.stripH > 0 and self.stripH or 1)
    if not m.strip then self.tickMark:Hide() end
    self:SizeBack()
end

-- view:Minimum() -> w, h: the layout's measured minimum (what Settings marks).
function View:Minimum()
    local m = self.metrics
    if not m then return nil end
    return m.minW, m.minH
end

-- view:FitsRight2() -> fits, need, now (T116, answer 3): whether the Line
-- frame is wide enough for a second Right slot at its widest word, the width
-- that needs and the frame's width now; nil off the Line layout.
function View:FitsRight2()
    local m = self.metrics
    if not m or not self.look or self.look.layout ~= "line" or m.need2 == nil then return nil end
    return m.fits2, m.need2, m.now2
end

-- view:Scale() -> the frame's scale this look asks for (the line applies it).
function View:Scale()
    local fr = self.look and self.look.frame
    return ((fr and fr.scale) or 100) / 100
end

-- One function per view: the step clears both hosts.
function View:StepOff()
    self.strip:SetScript("OnUpdate", nil)
    self.bar:SetScript("OnUpdate", nil)
    self.stepping = false
end

-- view:SetLook(look): a new resolved look (a layout switch, an override, a
-- style). The layout's regions are made the first time, the others' hidden;
-- the panel is skinned; the bars' backing, texture and places follow; the
-- step is removed. Nothing is painted from a face here: the line's next paint
-- does that.
function View:SetLook(look)
    self.look = look or self.look
    look = self.look
    local key = CV.LAYOUT[look.layout] and look.layout or CV.DEFAULT_LAYOUT
    look.layout = key
    local set = self:Set(key)
    if self.active and self.active ~= set then
        for _, fs in ipairs(Pieces(self.active)) do
            fs:SetText("")
            fs:Hide()
        end
        if self.active.holder then self.active.holder:Hide() end
    end
    if set.holder then set.holder:Show() end
    self.active = set
    self.label, self.value, self.second, self.right2, self.msg = set.label, set.value, set.second, set.right2, set.msg

    local back = (UI.SkinColour and UI.SkinColour(look.bar.back)) or { 0, 0, 0, 1 }
    self.barBack:SetColorTexture(back[1], back[2], back[3], back[4] or 1)
    self.stripBack:SetColorTexture(back[1], back[2], back[3], back[4] or 1)
    local tex, why = CV.TexturePath(look.bars.texture)
    if why and look.textureFallback then
        -- T142: the layout's own default, not there: its fallback, silently
        tex, why = CV.TexturePath(look.textureFallback)
    end
    if why then
        look.refused = look.refused or {}
        look.refused["bars." .. key .. ".texture"] = why
    end
    -- T142: the Bar layout's frame (the other layouts: their border, as
    -- before); the game's art where the client has it, else the border
    local mode = (key == "bar") and look.bars.frame or "border"
    if mode == "game" then
        local okG, whyG = CV.GameFrameOK()
        if not okG or not self.masks then
            look.refused = look.refused or {}
            look.refused["bars.bar.frame"] = whyG or CV.GAME_REFUSED
            mode = "border"
        end
    end
    self.frameMode = mode
    -- T142: the Bar layout's font, read once per look (EllesmereUI's getter
    -- is not asked at every paint)
    self.barFace, self.barFaceWhy = nil, nil
    if key == "bar" then self.barFace, self.barFaceWhy = CV.BarFont(look) end
    self.bar:SetStatusBarTexture(tex)
    self.strip:SetStatusBarTexture(tex)
    self.texturePath = tex
    self:ApplyShape()
    self:ApplyColours()
    self:StepOff()
    self.metrics = nil
    self:Place(METRICS[key](self, look))
    self:Snap()
end

-- view:Snap(): the panel (UI.Skin(frame, "clock"), the look's fill and edge)
-- and the backings at the current physical pixel -- the line calls it when
-- UI.px(1) has moved (the window manager never touches a clock, T41).
function View:Snap()
    local panel = self.look.panel or {}
    UI.Skin(self.parent, "clock", panel.fill or "bg", panel.edge or "border")
    self:SizeBack()
end

-- ST.ClockView.Build(parent, look, draw) -> view. `parent` is the line's
-- frame; `look` a resolved look (CV.Look) -- or T93's shape (labelSample,
-- colors, show), which reads as the line layout with no bars; `draw`
-- (optional) the line's sources: pool(bar) draws the real pool into the mana
-- bar, fsr(now) answers the seconds left in the five-second rule, spend(now)
-- the time of the spend that started it (the chip), tick(now) the last regen
-- tick and its period (TBC).
function CV.Build(parent, look, draw)
    look = look or {}
    if look.layout == nil then
        local resolved = CV.Resolve({ layout = CV.DEFAULT_LAYOUT, over = {} }, CV.Role(), {
            labelSample = look.labelSample, show = look.show })
        resolved.colors = look.colors or resolved.colors
        resolved.bars.show = "none"
        look = resolved
    end
    local v = setmetatable({ parent = parent, look = look, draw = draw or {} }, View)
    v:Set(CV.LAYOUT[look.layout] and look.layout or CV.DEFAULT_LAYOUT)

    -- the pulse: four quarter-second fades (UI/Widget.lua's since v0.1)
    local pulse = parent:CreateAnimationGroup()
    for i, dir in ipairs({ 1, -1, 1, -1 }) do
        local a = pulse:CreateAnimation("Alpha")
        a:SetFromAlpha(dir > 0 and 1 or 0.2)
        a:SetToAlpha(dir > 0 and 0.2 or 1)
        a:SetDuration(0.25)
        a:SetOrder(i)
    end
    v.pulse = pulse

    -- the mana bar and the five-second-rule strip, each with its black
    -- backing, a texture of the frame: the bars are child frames and draw
    -- above it, the backdrop beneath it
    v.bar = CreateFrame("StatusBar", nil, parent)
    v.bar:SetStatusBarTexture(UI.whiteTexture)
    v.barBack = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    v.barBack:SetPoint("CENTER", v.bar, "CENTER", 0, 0)
    -- T139: the edge under the background, `border` pixels wider each side
    v.barEdge = parent:CreateTexture(nil, "ARTWORK", nil, 0)
    v.barEdge:SetPoint("CENTER", v.bar, "CENTER", 0, 0)
    v.strip = CreateFrame("StatusBar", nil, parent)
    v.strip:SetStatusBarTexture(UI.whiteTexture)
    v.strip:SetMinMaxValues(0, 5)
    v.stripBack = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    v.stripBack:SetPoint("CENTER", v.strip, "CENTER", 0, 0)
    v.stripEdge = parent:CreateTexture(nil, "ARTWORK", nil, 0)
    v.stripEdge:SetPoint("CENTER", v.strip, "CENTER", 0, 0)
    -- B: the veil over the mana bar's right part (flat amber: no hatch art in
    -- the kit), its 1-px left edge, and the green line after the rule
    v.veil = v.bar:CreateTexture(nil, "OVERLAY")
    v.veil:SetColorTexture(CV.FSR_COLOR[1], CV.FSR_COLOR[2], CV.FSR_COLOR[3], CV.VEIL_ALPHA)
    v.veil:Hide()
    v.veilEdge = v.bar:CreateTexture(nil, "OVERLAY")
    v.veilEdge:SetColorTexture(CV.FSR_COLOR[1], CV.FSR_COLOR[2], CV.FSR_COLOR[3], 1)
    v.veilEdge:Hide()
    v.greenLine = v.bar:CreateTexture(nil, "OVERLAY")
    v.greenLine:SetColorTexture(CV.REGEN_COLOR[1], CV.REGEN_COLOR[2], CV.REGEN_COLOR[3], 1)
    v.greenLine:Hide()
    -- T135: the moving line over the mana bar, on a dark edge so it reads on any colour
    v.sweepBack = v.bar:CreateTexture(nil, "OVERLAY", nil, 1)
    v.sweepBack:SetColorTexture(0, 0, 0, 0.85)
    v.sweepBack:Hide()
    v.sweep = v.bar:CreateTexture(nil, "OVERLAY", nil, 2)
    v.sweep:SetColorTexture(CV.FSR_COLOR[1], CV.FSR_COLOR[2], CV.FSR_COLOR[3], 1)
    v.sweep:Hide()
    -- C: the chip, a square holding a Cooldown frame's swipe
    v.chip = CreateFrame("Frame", nil, parent)
    v.chipBg = v.chip:CreateTexture(nil, "BACKGROUND")
    v.chipBg:SetAllPoints(v.chip)
    v.chipBg:SetColorTexture(CV.REGEN_COLOR[1], CV.REGEN_COLOR[2], CV.REGEN_COLOR[3], 1)
    v.cd = CreateFrame("Cooldown", nil, v.chip, "CooldownFrameTemplate")
    v.cd:SetAllPoints(v.chip)
    if v.cd.SetDrawEdge then v.cd:SetDrawEdge(false) end
    if v.cd.SetHideCountdownNumbers then v.cd:SetHideCountdownNumbers(true) end
    v.chip:Hide()
    -- the regen tick's white mark on the strip (TBC)
    v.tickMark = v.strip:CreateTexture(nil, "OVERLAY")
    v.tickMark:SetColorTexture(CV.TICK_COLOR[1], CV.TICK_COLOR[2], CV.TICK_COLOR[3], 1)
    v.tickMark:Hide()
    -- T139: the shape's masks, one pair per region (none where the client has none)
    local barM = MaskPair(v.bar)
    if barM then
        v.masks = { bar = barM, barBack = MaskPair(parent), barEdge = MaskPair(parent),
            strip = MaskPair(v.strip), stripBack = MaskPair(parent), stripEdge = MaskPair(parent) }
        for _, t in ipairs({ v.veil, v.veilEdge, v.greenLine, v.sweep, v.sweepBack }) do Clip(v.masks.bar, t) end
        Clip(v.masks.barBack, v.barBack)
        Clip(v.masks.barEdge, v.barEdge)
        Clip(v.masks.strip, v.tickMark)
        Clip(v.masks.stripBack, v.stripBack)
        Clip(v.masks.stripEdge, v.stripEdge)
    end
    -- F1: the per-frame step, made once per view (installing it again
    -- allocates nothing)
    v.step = function() v:Step(GetTime()) end

    v:SetLook(look)
    return v
end

-- The pieces' places again, only when a measure moved (a font offset).
function View:Layout()
    local m = METRICS[self.look.layout](self, self.look)
    if SameMetrics(m, self.metrics) then return end
    self:Place(m)
end

local function Put(fs, text, tone, colors)
    if not fs then return end
    if text == nil or text == "" then
        fs:SetText("")
        fs:Hide()
        return
    end
    fs:SetText(text)
    fs:SetTextColor(ST.ClockFace.ToneRGB(tone, colors))
    fs:Show()
end

-- A piece's words with its colour codes: a label riding with the time keeps
-- its own tone ("OOM" muted before "1:20"), the arrow its own.
local function PieceText(piece, colors)
    local CF = ST.ClockFace
    local text = piece.text
    if piece.labelText and piece.valueText and piece.labelTone and piece.labelTone ~= piece.tone then
        text = CF.ToneHex(piece.labelTone, colors) .. piece.labelText .. "|r " .. piece.valueText
    end
    if piece.arrow then
        if piece.arrowTone and piece.arrowTone ~= piece.tone then
            text = text .. " " .. CF.ToneHex(piece.arrowTone, colors) .. piece.arrow .. "|r"
        else
            text = text .. " " .. piece.arrow
        end
    end
    return text
end

local WARMUP_FACE = { mode = "warmup", label = "OOM", known = "pending", tone = "muted" }

-- view:Paint(face, look): the face's slots (ClockFace.Slots in the look's
-- text), each in its region and tone. `look` replaces the build's (the
-- line's switches may have changed); nil keeps it. A face that is not a
-- table draws the warm-up's "OOM ..." -- the TBC widget's words before its
-- first state. The face is kept for PaintBar. A pct / mana slot (not the
-- time's) asks the line's draw.powerText(fs, kind) first: true means the
-- line put its own number into the font string, unread (it is left out of
-- view:Text()); otherwise the face's words. view.modelledWords is the first
-- modelled ("~") mana number drawn, for the line's hover.
function View:Paint(face, look)
    if look then self.look = look end
    local CF = ST.ClockFace
    local key = CV.LAYOUT[self.look.layout] and self.look.layout or CV.DEFAULT_LAYOUT
    local f = type(face) == "table" and face or WARMUP_FACE
    self.face = type(face) == "table" and face or nil
    self:Layout()
    self.msg:SetText("")
    self.msg:Hide()
    self.itemSegs = nil
    self.powerFs = nil
    if self.metrics and self.metrics.items then return self:PaintItems(f) end

    local t = TextOf(self.look, key)
    local pieces = CF.Slots(f, t, key, self.look) or {}
    local colors = self.look.colors
    local m = self.metrics or {}
    local segs, modelled = {}, nil
    local powerText = type(self.draw) == "table" and self.draw.powerText or nil
    local own = {}
    for _, slot in ipairs(CF.TEXT_SLOTS[key]) do
        local region = CV.REGION[key][slot]
        local fs = self[region]
        local piece = m[region] and pieces[slot] or nil
        local kind = t[slot]
        if fs then
            local drawn = false
            if piece and (kind == "pct" or kind == "mana") and slot ~= t.timeAt and type(powerText) == "function" then
                -- T144: a Mana slot of max asks for the game's "cur/max"
                local pk = (kind == "mana" and t.ofMax) and "manaMax" or kind
                local okP, res = pcall(powerText, fs, pk)
                if okP and res == true then
                    fs:SetTextColor(CF.ToneRGB(piece.tone, colors))
                    fs:Show()
                    drawn = true
                    own[#own + 1] = { fs, pk }
                end
            end
            if not drawn then
                if piece then
                    Put(fs, PieceText(piece, colors), piece.tone, colors)
                    segs[region] = piece
                    if not modelled and (kind == "pct" or kind == "mana") and slot ~= t.timeAt
                        and piece.text:sub(1, 1) == "~" then
                        modelled = piece.text
                    end
                else
                    Put(fs, nil)
                end
            end
        end
    end
    self.modelledWords = modelled
    self.segs = segs
    self.powerFs = own
end

local function HexRGB(h)
    return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
CV.HexRGB = HexRGB

-- T142: the Bar layout's items, each with ClockFace's words for its kind
-- (CF.ItemPieces: the "~", the arrows, a label drawn nowhere riding on the
-- time as CF.Slots does) in its own colour; a label or an arrow in a tone of
-- its own keeps its colour code. Mana, Mana / max and Mana % ask the line's
-- draw.powerText(fs, kind) first, as the slots do (T144: manaMax too); the
-- font strings it took are kept for View:PaintPowerTexts.
function View:PaintItems(f)
    local CF = ST.ClockFace
    local look = self.look
    local items = look.items or CV.ResolveItems(nil)
    local t = TextOf(look, "bar")
    local pieces = CF.ItemPieces(f, t, look, items.label and items.label.on) or {}
    local colors = look.colors
    local m = self.metrics or {}
    local set = self.active or {}
    local powerText = type(self.draw) == "table" and self.draw.powerText or nil
    local segs, modelled, own = {}, nil, {}
    for _, kind in ipairs(CV.ITEM_KINDS) do
        local fs = set.items and set.items[kind]
        local it = items[kind]
        local piece = (m.items and m.items[kind]) and pieces[kind] or nil
        if fs then
            local r, g, b = HexRGB(it.colour)
            local drawn = false
            if piece and (kind == "mana" or kind == "pct" or kind == "manaMax") and type(powerText) == "function" then
                local okP, res = pcall(powerText, fs, kind)
                if okP and res == true then
                    fs:SetTextColor(r, g, b)
                    fs:Show()
                    drawn = true
                    own[#own + 1] = { fs, kind }
                end
            end
            if not drawn then
                if piece then
                    fs:SetText(PieceText(piece, colors))
                    fs:SetTextColor(r, g, b)
                    fs:Show()
                    segs[#segs + 1] = { kind = kind, piece = piece }
                    -- T144 review S1: the Bar's words carry no "~", so the
                    -- face's own flags say the number is the model's
                    if not modelled and type(f) == "table"
                        and ((kind == "pct" and f.pctModelled)
                            or ((kind == "mana" or kind == "manaMax") and f.manaModelled)) then
                        modelled = piece.text
                    end
                else
                    fs:SetText("")
                    fs:Hide()
                end
            end
        end
    end
    self.modelledWords = modelled
    self.segs = nil
    self.itemSegs = segs
    self.powerFs = own
end

-- T144: the game's own mana texts again, between ticks (the line's
-- UNIT_POWER_FREQUENT): only the font strings the last paint gave to
-- draw.powerText, each asked again -- no layout, no words, no measuring. A
-- refusal now (the flag off, an error) leaves the text as it was until the
-- next paint. Nothing here reads what the line put in.
function View:PaintPowerTexts()
    local list = self.powerFs
    local powerText = type(self.draw) == "table" and self.draw.powerText or nil
    if type(list) ~= "table" or type(powerText) ~= "function" then return 0 end
    local n = 0
    for _, e in ipairs(list) do
        local okP, res = pcall(powerText, e[1], e[2])
        if okP and res == true then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------------------
-- The bars
--------------------------------------------------------------------------------
local function Clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

-- The mana bar's colour this paint: colors.manaBar, else a style's barFill,
-- else the mana blue.
function View:ManaColour()
    local look = self.look
    local c = look.colors and look.colors.manaBar
    if c == "tone" then
        local face = self.face
        return ST.ClockFace.ToneRGB(face and face.tone or "muted", look.colors)
    elseif c == "class" then
        local a = UI.classAccent or UI.accent or { 1, 1, 1 }
        return a[1], a[2], a[3]
    elseif c ~= nil and c ~= "mana" then
        local rgba = UI.SkinColour and UI.SkinColour(c) or c
        if type(rgba) == "table" then return rgba[1], rgba[2], rgba[3] end
    elseif c == nil and look.bars.fill ~= nil then
        local rgba = UI.SkinColour and UI.SkinColour(look.bars.fill) or look.bars.fill
        if type(rgba) == "table" then return rgba[1], rgba[2], rgba[3] end
    end
    return CV.MANA_COLOR[1], CV.MANA_COLOR[2], CV.MANA_COLOR[3]
end

-- The seconds left in the five-second rule, from the line (nil: not known).
function View:FSR(now)
    local fn = self.draw.fsr
    if type(fn) ~= "function" then return nil end
    local r = fn(now)
    if type(r) ~= "number" then return nil end
    if r < 0 then r = 0 end
    if r > 5 then r = 5 end
    return r
end

-- The mana bar: the game's pool (the line draws it: TBC reads it, Forever
-- hands it to the bar through ST.API.DrawUnitPower and never reads it), or
-- the model's from the face's plain pct at 0.6 alpha. Nothing here reads
-- the bar back.
function View:PaintMana()
    if not self.manaOn then return end
    local bar = self.bar
    if self.look.bars.mana == "model" then
        local face = self.face
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(face and type(face.pct) == "number" and Clamp01(face.pct) or 0)
        self.manaAlpha = CV.MODEL_ALPHA
    else
        if type(self.draw.pool) == "function" then self.draw.pool(bar) end
        self.manaAlpha = 1
    end
    bar:SetAlpha(self.manaAlpha)
    local r, g, b = self:ManaColour()
    bar:SetStatusBarColor(r, g, b)
    self:Gradient(bar, r, g, b)
end

-- The five-second rule's element at `now`, by time alone: the strip's value,
-- the veil's width, the chip's swipe, the tick mark; the step on while the
-- rule runs (or a tick sweeps), off otherwise.
function View:PaintFSR(now)
    local el = self.el
    local after = self.look.bars.after
    local rem = self:FSR(now)
    local running = rem ~= nil and rem > 0
    local step, host = false, nil
    local F, G = self.cF or CV.FSR_COLOR, self.cG or CV.REGEN_COLOR

    if el == "strip" or el == "solo" then
        local strip = self.strip
        host = strip
        if running then
            strip:SetValue(5 - rem)
            strip:SetStatusBarColor(F[1], F[2], F[3])
            step = true
        else
            strip:SetValue(after == "empty" and 0 or 5)
            strip:SetStatusBarColor(G[1], G[2], G[3])
        end
        local tickOn = false
        if not running and after == "tick" and type(self.draw.tick) == "function" then
            local t, period = self.draw.tick(now)
            if type(t) == "number" and type(period) == "number" and period > 0 then
                local x = ((now - t) % period) / period * self.stripW
                self.tickMark:ClearAllPoints()
                self.tickMark:SetPoint("LEFT", strip, "LEFT", x, 0)
                self.tickMark:Show()
                tickOn, step = true, true
            end
        end
        if not tickOn then self.tickMark:Hide() end
    elseif el == "veil" then
        host = self.bar
        if running then
            self.veil:SetWidth(self.barW * rem / 5)
            self.veil:Show()
            self.veilEdge:Show()
            self.greenLine:Hide()
            step = true
        else
            self.veil:Hide()
            self.veilEdge:Hide()
            ShowIf(self.greenLine, after ~= "empty")
        end
    elseif el == "sweep" then
        -- T135: the line at the share of the five seconds gone, left to right
        host = self.bar
        local x
        if running then
            x = self.barW * (5 - rem) / 5
            self.sweep:SetColorTexture(F[1], F[2], F[3], 1)
            self.greenLine:Hide()
            step = true
        else
            if after == "tick" and type(self.draw.tick) == "function" then
                local t, period = self.draw.tick(now)
                if type(t) == "number" and type(period) == "number" and period > 0 then
                    x = ((now - t) % period) / period * self.barW
                    local T = CV.TICK_COLOR
                    self.sweep:SetColorTexture(T[1], T[2], T[3], 1)
                    step = true
                end
            end
            ShowIf(self.greenLine, after == "green")
        end
        if x then
            self.sweep:ClearAllPoints()
            self.sweep:SetPoint("CENTER", self.bar, "LEFT", x, 0)
            self.sweepBack:ClearAllPoints()
            self.sweepBack:SetPoint("CENTER", self.bar, "LEFT", x, 0)
            self.sweep:Show()
            self.sweepBack:Show()
        else
            self.sweep:Hide()
            self.sweepBack:Hide()
        end
    elseif el == "chip" then
        if running then
            local spend = type(self.draw.spend) == "function" and self.draw.spend(now) or nil
            if type(spend) == "number" and spend ~= self.cdSpend then
                self.cdSpend = spend
                self.cd:SetCooldown(spend, 5)
            end
            self.chipBg:SetColorTexture(F[1], F[2], F[3], 1)
        elseif after == "empty" then
            local back = (UI.SkinColour and UI.SkinColour(self.look.bar.back)) or { 0, 0, 0, 1 }
            self.chipBg:SetColorTexture(back[1], back[2], back[3], back[4] or 1)
        else
            self.chipBg:SetColorTexture(G[1], G[2], G[3], 1)
        end
    end

    if step and host then
        if self.stepHost ~= host and self.stepHost then self.stepHost:SetScript("OnUpdate", nil) end
        self.stepHost = host
        if not self.stepping then
            host:SetScript("OnUpdate", self.step)
            self.stepping = true
        end
    elseif self.stepping then
        self:StepOff()
    end
end

-- view:PaintBar(now): the mana bar and the five-second rule.
function View:PaintBar(now)
    self:PaintMana()
    self:PaintFSR(now)
end

--------------------------------------------------------------------------------
-- F1 / C6: the five-second rule, every frame. The line paints at its own pace
-- (TBC 10 a second, Forever on the 0.5 s tick); while the rule runs (or a
-- regen tick sweeps), an OnUpdate on the strip -- on the mana bar for the
-- veil -- moves only the rule's marks from the line's draw.fsr(now): nothing
-- else repainted, no Show / Hide of the frame, nothing allocated per frame.
-- It removes itself when the rule ends, and is removed by a new look and by
-- the preview's FillBar.
--------------------------------------------------------------------------------
function View:Step(now)
    self:PaintFSR(now)
end

-- view:FillBar(r, g, b): the preview's full bar in one colour (TBC's unlock):
-- the mana bar full in that colour, the strip and the chip green.
function View:FillBar(r, g, b)
    local G = self.cG or CV.REGEN_COLOR
    self:StepOff()
    if self.manaOn then
        self.bar:SetMinMaxValues(0, 1)
        self.bar:SetValue(1)
        self.bar:SetAlpha(1)
        self.bar:SetStatusBarColor(r, g, b)
        self:Gradient(self.bar, r, g, b)
    end
    self.strip:SetMinMaxValues(0, 5)
    self.strip:SetValue(5)
    if self.el == "solo" then
        self.strip:SetStatusBarColor(r, g, b)
    else
        self.strip:SetStatusBarColor(G[1], G[2], G[3])
    end
    self.chipBg:SetColorTexture(G[1], G[2], G[3], 1)
    self.veil:Hide()
    self.veilEdge:Hide()
    self.sweep:Hide()
    self.sweepBack:Hide()
    self.tickMark:Hide()
    ShowIf(self.greenLine, self.el == "veil" or self.el == "sweep")
end

-- view:Message(text, r, g, b): one centred line instead of the pieces (the
-- preview's "SpellTuner - drag me", in the colour the line passes).
function View:Message(text, r, g, b)
    for _, fs in ipairs({ self.label or false, self.value or false, self.second or false, self.right2 or false }) do
        if fs then
            fs:SetText("")
            fs:Hide()
        end
    end
    for _, fs in pairs(self.active and self.active.items or {}) do
        fs:SetText("")
        fs:Hide()
    end
    self.msg:SetText(text or "")
    if r then self.msg:SetTextColor(r, g, b) end
    self.msg:Show()
    self.segs = nil
    self.itemSegs = nil
end

-- view:Text(): the words as drawn, plain -- the message, or the pieces joined
-- as ClockFace.JoinSegments joins them (T142, the Bar layout: its items in
-- drawing order, the time one space after the label, two spaces between the
-- others).
function View:Text()
    if self.msg:IsShown() then return self.msg:GetText() or "" end
    if self.itemSegs then
        local out, prev = "", nil
        for _, s in ipairs(self.itemSegs) do
            local sep = (prev == "label" and s.kind == "time") and " " or "  "
            out = (out ~= "" and (out .. sep) or "") .. ST.ClockFace.ValueText(s.piece)
            prev = s.kind
        end
        return out
    end
    return ST.ClockFace.JoinSegments(self.segs)
end

function View:Pulse()
    self.pulse:Play()
end
