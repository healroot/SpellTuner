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
--   * the pulse (F5): one animation, MD:Alert's and the once-per-fight flash
--     under 30 s, played by whichever line owns the frame.
-- The value's fixed x is the label slot's width: the widest label the line
-- draws (`look.labelSample`, "FULL" on TBC, "~FULL" on Forever) measured in the
-- label's own font, plus a gap. It is measured again at each paint and the
-- pieces re-anchored ONLY when a measure changed (a font offset, a font that
-- loaded late), never because the words did.
--
-- T98 (docs/SPEC-next.md 7.2-7.3, K3 of R-clock.md; decision 13): the
-- LAYOUTS and the look.
--   * Layouts (all draw the same face): "line" (L1 above, the default),
--     "compact" (L2: the label small over one big number, no secondary) and
--     "bar" (L3: a bar the width of the clock with the label and the time on
--     it). The ring (L4) is T104's; CV.BarsOK already holds its rule. Each
--     layout's text regions are built the first time it is drawn and kept
--     (one pool per frame), so a switch leaks nothing; the bars are shared.
--   * The look, sparse (7.3): db.clockLook = { layout = "line", over = {} }
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
--     MD:AddDumpLine, added the first time the look is not the default one,
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
--     once per spend; the client animates it) --, `order` (manaOver /
--     fsrOver), `mana` (game / model: Forever's modelled pool from the face's
--     plain pct, at 0.6 alpha), `fsr` (the strip's thickness, 1-8), `after`
--     (green / empty / tick: TBC's 2-s regen tick from MD.Regen:RegenTick, a
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
-- What it never does: Show / Hide the frame it draws into (each line keeps
-- the single visibility owner, CLAUDE.md; a layout switch rebuilds regions
-- INSIDE the frame), read a client value (the face is plain; the mana pool
-- and the five-second rule come from the line's `draw` callbacks), read the
-- mana bar back, or read MD.db outside the store's functions below.
local _, MD = ...
local UI = MD.UI

MD.ClockView = MD.ClockView or {}
local CV = MD.ClockView

CV.INSET = 8      -- the label's and the secondary's distance from the frame's edges
CV.TOP = -4       -- the text row, from the frame's top (T82's)
CV.GAP = 6        -- between the label slot and the value

-- T98: the look's store, sparse (docs/SPEC-next.md 7.3). A registered default
-- fills every leaf, so only the layout and an empty override table are
-- declared; what "follows the style" is resolved, never stored.
MD:RegisterDefaults({ clockLook = { layout = "line", over = {} } })

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
        second = false, inset = 6 },
}

-- T115: the bars' defaults (both lines, every layout; answers 1, 2 and 5).
CV.BARS_DEFAULT = { show = "both", join = "stacked", order = "manaOver", mana = "game", fsr = 3,
    after = "green", texture = "flat" }

-- What each bars field accepts (the lists a picker offers, before the line's
-- facts take some out).
CV.BARS_VALUES = {
    show = { "both", "mana", "fsr", "none" },
    join = { "stacked", "veil", "chip" },
    order = { "manaOver", "fsrOver" },
    mana = { "game", "model" },
    after = { "green", "empty", "tick" },
    texture = { "flat", "statusbar", "raid" },
}
CV.FSR_RANGE = { 1, 8 }
CV.SCALE_RANGE = { 50, 200 }

-- The bar textures: flat (the kit's), and the client's two bars (TBC).
CV.TEXTURES = {
    flat = UI.whiteTexture,
    statusbar = "Interface\\TargetingFrame\\UI-StatusBar",
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}

-- The five-second rule's amber while it runs and green once spirit regen
-- runs (UI/Widget.lua's since v0.1), the mana blue (UI/Clock_Forever.lua's
-- since T11), the veil's alpha, the model's alpha, the tick mark.
CV.FSR_COLOR   = { 1, 0.67, 0.2 }
CV.REGEN_COLOR = { 0.2, 1, 0.4 }
CV.MANA_COLOR  = { 0.3, 0.6, 1 }
CV.TICK_COLOR  = { 1, 1, 1 }
CV.VEIL_ALPHA = 0.45
CV.MODEL_ALPHA = 0.6
CV.TICK_WIDTH = 2

CV.TICK_REFUSED = "Forever cannot read your mana, so the 2-second regen tick cannot be learned: the strip stays green."
CV.MODEL_REFUSED = "no modelled pool on this line: it reads the real one"
CV.TEXTURE_REFUSED = "this line draws its bars flat only"
CV.RING_REFUSED = "the real pool is drawn by the game, never read: a ring cannot show it here"

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
local BARS_OK = {
    show = OneOf(CV.BARS_VALUES.show), join = OneOf(CV.BARS_VALUES.join),
    order = OneOf(CV.BARS_VALUES.order), mana = OneOf(CV.BARS_VALUES.mana),
    after = OneOf(CV.BARS_VALUES.after), texture = OneOf(CV.BARS_VALUES.texture),
    fsr = IntRange(CV.FSR_RANGE[1], CV.FSR_RANGE[2]),
}
local BARS_ORDER = { "show", "join", "order", "mana", "fsr", "after", "texture" }

CV.OVER = {
    ["panel.fill"] = IsColour,
    ["panel.edge"] = IsColour,
    ["bar.back"] = IsColour,
    ["colors.crit"] = Hex, ["colors.warn"] = Hex, ["colors.normal"] = Hex,
    ["colors.good"] = Hex, ["colors.muted"] = Hex, ["colors.mana"] = Hex,
    ["colors.manaBar"] = function(v) return v == "mana" or v == "tone" or v == "class" or IsColour(v) end,
}
for _, L in ipairs(CV.LAYOUTS) do
    local d = CV.LAYOUT[L]
    for _, f in ipairs(BARS_ORDER) do CV.OVER["bars." .. L .. "." .. f] = BARS_OK[f] end
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
-- nobody draws (yet) is "line"; an override this file does not accept is
-- ignored; bars.* and frame.* are read for the layout drawn; a bars choice
-- this line may not draw falls back to the default (look.refused names what
-- was refused and why). Everything is a copy: the store is never touched.
function CV.Resolve(stored, role, facts)
    stored = type(stored) == "table" and stored or {}
    role = type(role) == "table" and role or {}
    facts = type(facts) == "table" and facts or {}
    local over = type(stored.over) == "table" and stored.over or {}
    local key = Renderable(stored.layout) and stored.layout or "line"
    local d = CV.LAYOUT[key]

    local look = {
        layout = key, width = d.width, height = d.height, second = d.second,
        inset = d.inset, valueSize = d.valueSize,
        labelSample = facts.labelSample or "FULL",
        show = Copy(facts.show) or {},
        panel = { fill = role.fill or "bg", edge = role.edge or "border" },
        bar = { back = (role.bar ~= nil and IsColour(role.bar)) and Copy(role.bar) or { 0, 0, 0, 1 } },
        bars = Copy(CV.BARS_DEFAULT),
        frame = { w = d.width, h = d.height, scale = 100 },
        colors = {},
        refused = {},
    }
    if role.barFill ~= nil and IsColour(role.barFill) then look.bars.fill = Copy(role.barFill) end
    if role.ring ~= nil then look.ring = Copy(role.ring) end

    for k, ok in pairs(CV.OVER) do
        local v = Get(over, k)
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
        look.bars[field] = (field == "show") and "fsr" or CV.BARS_DEFAULT[field]
    end
    return look
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

--------------------------------------------------------------------------------
-- The store: db.clockLook, written only here.
--------------------------------------------------------------------------------
local dumpAdded = false
local migrated = false

local function StoredRaw()
    local db = MD.db
    if type(db) ~= "table" then return nil end
    if type(db.clockLook) ~= "table" then db.clockLook = { layout = "line", over = {} } end
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
        MD:AddDumpLine("clockOld", function() return text end)
    end
    return changed, dropped
end

local function Stored()
    local s = StoredRaw()
    if not s then return { layout = "line", over = {} } end
    if not migrated then CV.MigrateStored(CV.lineFacts) end
    return s
end

MD:RegisterCallback("MD_READY", function() CV.MigrateStored(CV.lineFacts) end)

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
    local layout = Renderable(s.layout) and s.layout or ("line (saved " .. tostring(s.layout) .. ")")
    return string.format("clock: layout %s, %d override%s%s", layout, #keys, #keys == 1 and "" or "s",
        #keys > 0 and (" (" .. table.concat(keys, ", ") .. ")") or "")
end

local function Note(s)
    if dumpAdded then return end
    if s.layout ~= "line" or #OverKeys(s.over) > 0 then
        dumpAdded = true
        MD:AddDumpLine("clock", CV.DumpLine)
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
    MD:Fire("CLOCK_LOOK")
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
    local set = { holder = holder }
    set.label = NewText(holder, UI.FONT)
    set.label:SetJustifyH("LEFT")
    set.value = NewText(holder, UI.FONT_NUM or UI.FONT)
    set.value:SetJustifyH("RIGHT")
    set.msg = NewText(holder, UI.FONT)
    set.msg:SetText("")
    set.msg:Hide()
    return set
end

local function Pieces(set)
    local out = {}
    for _, k in ipairs({ "label", "value", "second", "msg" }) do
        if set[k] then out[#out + 1] = set[k] end
    end
    return out
end

function View:Set(key)
    self.sets = self.sets or {}
    if not self.sets[key] then self.sets[key] = BUILD[key](self) end
    return self.sets[key]
end

-- Which bars a look draws: manaOn (the mana bar), and the five-second rule's
-- element -- "strip" (stacked under / over the mana bar), "solo" (the strip in
-- the mana bar's place, show = fsr), "veil", "chip", or nil.
local function Element(bars)
    local show = bars.show
    if show == "none" then return false, nil end
    if show == "mana" then return true, nil end
    if show == "fsr" then return false, "solo" end
    local j = bars.join
    if j == "veil" then return true, "veil" end
    if j == "chip" then return true, "chip" end
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

METRICS.line = function(v, look)
    local b = look.bars
    local manaOn, el = Element(b)
    local s = b.fsr or 3
    local inset = CV.INSET
    local chipOff = el == "chip" and 13 or 0
    local lp = v:ProbeIn(UI.FONT)
    local labelW = Measure(lp, look.labelSample or "FULL")
    local labelH = MeasureH(lp, look.labelSample or "FULL")
    -- the secondary's room only while the line can draw one (C2: 100 x 30
    -- with no secondary): a look whose switches drop both the rest and the
    -- cooldown segment (a line with no cooldown secondary says cd = false)
    local secondW = CV.HasSecondary(look) and (CV.GAP + Measure(lp, CV.SECOND_SAMPLE)) or 0
    local np = v:ProbeIn(UI.FONT_NUM or UI.FONT)
    local valueW = Measure(np, CV.VALUE_SAMPLE)
    local valueH = MeasureH(np, CV.VALUE_SAMPLE)
    v:ProbeIn(UI.FONT)
    local rowH = math.ceil(math.max(labelH, valueH, FontSize(UI.FONT), FontSize(UI.FONT_NUM or UI.FONT)))
    local top = 4 + rowH + 2
    local anyBar = manaOn or el ~= nil
    local minW = math.ceil(inset + chipOff + labelW + CV.GAP + valueW + secondW + inset)
    local minH = anyBar and (top + 5 + s + 1 + 2) or (rowH + 8)
    local w, h = Fit(look, minW, minH)
    local barW = w - 20
    local manaH = h - top - 5 - s - 1
    local m = { w = w, h = h, minW = minW, minH = minH, manaOn = manaOn, el = el,
        label = { "TOPLEFT", inset + chipOff, CV.TOP },
        value = { "TOPLEFT", inset + chipOff + labelW + CV.GAP, CV.TOP },
        second = { "TOPRIGHT", -inset, CV.TOP },
        msg = { "TOP", 0, CV.TOP } }
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
    local probe = v:ProbeIn(UI.FONT_SMALL or UI.FONT)
    local labelW = Measure(probe, look.labelSample or "FULL")
    local labelH = math.ceil(math.max(MeasureH(probe, look.labelSample or "FULL"), FontSize(UI.FONT_SMALL or UI.FONT)))
    v:ProbeIn(UI.FONT)
    local face, size, flags = NumFont(look.valueSize or 22)
    local sp = v:SizedProbe()
    sp:SetFont(face, size, flags)
    local valueW = Measure(sp, CV.VALUE_SAMPLE)
    local valueH = math.ceil(math.max(MeasureH(sp, CV.VALUE_SAMPLE), size))
    local textBottom = 3 + labelH + valueH
    local anyBar = manaOn or el ~= nil
    local minW = math.ceil(2 * inset + math.max(chipOff + labelW, valueW))
    local minH = anyBar and (textBottom + 6 + s) or (textBottom + 4)
    local w, h = Fit(look, minW, minH)
    local barW = w - 2 * inset
    local manaH = h - textBottom - 4 - s
    local m = { w = w, h = h, minW = minW, minH = minH, manaOn = manaOn, el = el,
        face = face, size = size, flags = flags,
        label = { "TOPLEFT", inset + chipOff, -3 },
        value = { "TOPLEFT", inset, -(3 + labelH) },
        msg = { "CENTER", 0, 0 }, msgW = w - 4 }
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
    if el == "chip" then m.chip = { "TOPLEFT", inset, -3 - (labelH - 9) / 2, 9 } end
    return m
end

METRICS.bar = function(v, look)
    local b = look.bars
    local manaOn, el = Element(b)
    local s = b.fsr or 3
    local inset = look.inset or 6
    local probe = v:ProbeIn(UI.FONT)
    local labelW = Measure(probe, look.labelSample or "FULL")
    local labelH = MeasureH(probe, look.labelSample or "FULL")
    local vprobe = v:ProbeIn(UI.FONT_NUM or UI.FONT)
    local valueW = Measure(vprobe, CV.VALUE_SAMPLE)
    local valueH = MeasureH(vprobe, CV.VALUE_SAMPLE)
    v:ProbeIn(UI.FONT) -- the probe back in the label's font (the line's slot measure)
    local rowH = math.ceil(math.max(labelH, valueH, FontSize(UI.FONT), FontSize(UI.FONT_NUM or UI.FONT)))
    local anyBar = manaOn or el ~= nil
    local stacked = manaOn and el == "strip"
    local minH = anyBar and (rowH + s + 4) or (rowH + 6)
    -- the height first: the chip is as tall as the mana bar, and its width
    -- goes into the minimum width
    local _, h = Fit(look, 0, minH)
    local single = h - 4
    local chipExtra = el == "chip" and (single + 2) or 0
    local minW = math.ceil(chipExtra + 4 + 2 * inset + labelW + 2 * CV.GAP + valueW)
    local w = Fit(look, minW, minH)
    local barX = 2 + chipExtra
    local barW = w - 4 - chipExtra
    local m = { w = w, h = h, minW = minW, minH = minH, manaOn = manaOn, el = el,
        label = { "LEFT", inset, 0 }, value = { "RIGHT", -inset, 0 }, msg = { "CENTER", 0, 0 } }
    if stacked then
        local manaH = h - s - 3
        if b.order == "fsrOver" then
            m.bar = { barX, 1, barW, manaH }
            m.strip = { barX, 1 + manaH + 1, barW, s }
        else
            m.strip = { barX, 1, barW, s }
            m.bar = { barX, s + 2, barW, manaH }
        end
    elseif manaOn then
        m.bar = { barX, 2, barW, single }
    elseif el == "solo" then
        m.strip = { barX, 2, barW, single }
    end
    if el == "chip" then m.chip = { "BOTTOMLEFT", 2, 2, single } end
    -- the text holder over the mana bar, else over the strip, else the frame
    local r = m.bar or m.strip
    m.holder = r and { r[1], r[2], r[3], r[4] } or { 0, 0, w, h }
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

-- The backings one physical pixel wider than their bar on every side (T41).
function View:SizeBack()
    local e = UI.px and UI.px(1, self.parent) or 1
    local m = self.metrics or {}
    if m.bar then self.barBack:SetSize(m.bar[3] + 2 * e, m.bar[4] + 2 * e) end
    if m.strip then self.stripBack:SetSize(m.strip[3] + 2 * e, m.strip[4] + 2 * e) end
    self.snappedPx = e
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
    if m.face then set.value:SetFont(m.face, m.size, m.flags) end
    Anchor(set.label, m.label, rel)
    Anchor(set.value, m.value, rel)
    if set.second and m.second then Anchor(set.second, m.second, rel) end
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
    if m.el ~= "veil" then
        self.veil:Hide()
        self.veilEdge:Hide()
        self.greenLine:Hide()
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
    local key = CV.LAYOUT[look.layout] and look.layout or "line"
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
    self.label, self.value, self.second, self.msg = set.label, set.value, set.second, set.msg

    local back = (UI.SkinColour and UI.SkinColour(look.bar.back)) or { 0, 0, 0, 1 }
    self.barBack:SetColorTexture(back[1], back[2], back[3], back[4] or 1)
    self.stripBack:SetColorTexture(back[1], back[2], back[3], back[4] or 1)
    local tex = CV.TEXTURES[look.bars.texture] or CV.TEXTURES.flat
    self.bar:SetStatusBarTexture(tex)
    self.strip:SetStatusBarTexture(tex)
    self.texturePath = tex
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

-- MD.ClockView.Build(parent, look, draw) -> view. `parent` is the line's
-- frame; `look` a resolved look (CV.Look) -- or T93's shape (labelSample,
-- colors, show), which reads as the line layout with no bars; `draw`
-- (optional) the line's sources: pool(bar) draws the real pool into the mana
-- bar, fsr(now) answers the seconds left in the five-second rule, spend(now)
-- the time of the spend that started it (the chip), tick(now) the last regen
-- tick and its period (TBC).
function CV.Build(parent, look, draw)
    look = look or {}
    if look.layout == nil then
        local resolved = CV.Resolve({ layout = "line", over = {} }, CV.Role(), {
            labelSample = look.labelSample, show = look.show })
        resolved.colors = look.colors or resolved.colors
        resolved.bars.show = "none"
        look = resolved
    end
    local v = setmetatable({ parent = parent, look = look, draw = draw or {} }, View)
    v:Set(CV.LAYOUT[look.layout] and look.layout or "line")

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
    v.barBack = parent:CreateTexture(nil, "ARTWORK")
    v.barBack:SetPoint("CENTER", v.bar, "CENTER", 0, 0)
    v.strip = CreateFrame("StatusBar", nil, parent)
    v.strip:SetStatusBarTexture(UI.whiteTexture)
    v.strip:SetMinMaxValues(0, 5)
    v.stripBack = parent:CreateTexture(nil, "ARTWORK")
    v.stripBack:SetPoint("CENTER", v.strip, "CENTER", 0, 0)
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
    fs:SetTextColor(MD.ClockFace.ToneRGB(tone, colors))
    fs:Show()
end

-- view:Paint(face, look): the face's pieces, each in its tone. `look`
-- replaces the build's (the line's switches may have changed); nil keeps it.
-- A face that is not a table draws the warm-up's "OOM ..." -- the TBC
-- widget's words before its first state. The face is kept for PaintBar.
function View:Paint(face, look)
    if look then self.look = look end
    local CF = MD.ClockFace
    local segs = CF.Segments(face, self.look)
        or CF.Segments({ mode = "warmup", label = "OOM", known = "pending", tone = "muted" }, self.look)
    local colors = self.look.colors
    self.face = type(face) == "table" and face or nil
    self:Layout()
    self.msg:SetText("")
    self.msg:Hide()

    Put(self.label, segs.label.text, segs.label.tone, colors)
    local val = segs.value
    if val then
        local text = val.text
        if val.arrow then
            if val.arrowTone and val.arrowTone ~= val.tone then
                text = text .. " " .. CF.ToneHex(val.arrowTone, colors) .. val.arrow .. "|r"
            else
                text = text .. " " .. val.arrow
            end
        end
        Put(self.value, text, val.tone, colors)
    else
        Put(self.value, nil)
    end
    if self.second then
        if segs.second and self.look.second ~= false then
            Put(self.second, segs.second.text, segs.second.tone, colors)
        else
            Put(self.second, nil)
        end
    end
    if self.look.second == false then segs.second = nil end
    self.segs = segs
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
        return MD.ClockFace.ToneRGB(face and face.tone or "muted", look.colors)
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
-- hands it to the bar through MD.API.DrawUnitPower and never reads it), or
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
    bar:SetStatusBarColor(self:ManaColour())
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
    local F, G = CV.FSR_COLOR, CV.REGEN_COLOR

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
    local G = CV.REGEN_COLOR
    self:StepOff()
    if self.manaOn then
        self.bar:SetMinMaxValues(0, 1)
        self.bar:SetValue(1)
        self.bar:SetAlpha(1)
        self.bar:SetStatusBarColor(r, g, b)
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
    self.tickMark:Hide()
    ShowIf(self.greenLine, self.el == "veil")
end

-- view:Message(text, r, g, b): one centred line instead of the pieces (the
-- preview's "SpellTuner - drag me", in the colour the line passes).
function View:Message(text, r, g, b)
    for _, fs in ipairs({ self.label, self.value, self.second or false }) do
        if fs then
            fs:SetText("")
            fs:Hide()
        end
    end
    self.msg:SetText(text or "")
    if r then self.msg:SetTextColor(r, g, b) end
    self.msg:Show()
    self.segs = nil
end

-- view:Text(): the words as drawn, plain -- the message, or the pieces joined
-- as ClockFace.JoinSegments joins them.
function View:Text()
    if self.msg:IsShown() then return self.msg:GetText() or "" end
    return MD.ClockFace.JoinSegments(self.segs)
end

function View:Pulse()
    self.pulse:Play()
end
