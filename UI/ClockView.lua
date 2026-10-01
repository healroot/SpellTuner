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
-- value re-anchored ONLY when that width changed (a font offset, a font that
-- loaded late), never because the words did.
--
-- T98 (docs/SPEC-next.md 7.2-7.3, K3 of R-clock.md; decisions 13 and 15): the
-- LAYOUTS, the look and the bar.
--   * Layouts (all draw the same face): "line" (L1 above, the default and
--     T93's regions exactly), "compact" (L2: the label small over one big
--     number, no secondary, no bar unless asked) and "bar" (L3: a bar the
--     width of the clock with the label and the time on it). The ring (L4) is
--     T104's; CV.SourceOK already holds its rule. Each layout's regions are
--     built the first time it is drawn and kept (one pool per frame), so a
--     switch leaks nothing; the bar, its backing and the spark are shared.
--   * The look, sparse (7.3): db.clockLook = { layout = "line", over = {} }
--     (registered here, both TOCs). CV.Resolve gives the RESOLVED look:
--         the layout's defaults  <-  the active style's `clock` role  <-  over
--     The role (each style file defines its own; Flat's in UI/Theme_Flat.lua)
--     is read for: kind / fill / edge (the panel: UI.Skin(frame, "clock",
--     fill, edge)), bar (the bar's backing colour), barFill (optional: the
--     bar's colour instead of the source's own) and ring (T104's). `over`
--     holds only what the user set (CV.OVER lists the keys); "Reset to
--     style" (CV.ResetToStyle) wipes it. Nothing reads db.clockLook.over but
--     this file. The line's own switches (TBC db.showRest / showCooldown,
--     Forever db.clock.showRest) stay where they are and reach the look as
--     `show` (phase 1, 7.3).
--   * The bar's SOURCE (7.2): "pool" (the real mana: TBC reads it, Forever
--     hands it to the bar through MD.API.DrawUnitPower and never reads it --
--     no ring may use it there), "model" (Forever's modelled pool, the face's
--     pct; TBC has none), "time" (the time to OOM over `horizon`, 180 s),
--     "fsr" (the five-second rule: TBC's today, Forever's from the model's
--     last priced spend) or "none" (no bar). The default is the line's own
--     meaning (decision 15 (a): the 5SR on TBC, the pool on Forever) for
--     "line" and "bar", none for "compact". The colour is the source's own
--     ("source": the 5SR amber then green, the pool and the model the mana
--     blue, time its tone), or "tone" (the face's -- on Forever's pool the
--     MODELLED tone: the colour says what the model thinks, the fill what the
--     game has), "class", or a colour.
--   * The SPARK (`bar.spark = "fsr"`, ElvUI's oUF_EnergyManaRegen): a 2-px
--     yellow mark sweeping the bar over the five seconds after a spend, on
--     whatever source is drawn. Neither line knows the 2-s regen tick yet, so
--     after the rule the spark is hidden (no white tick sweep).
--   * Fits by construction: "compact" and "bar" size their frame from the
--     widest value they can draw (CV.VALUE_SAMPLE) measured in their own
--     fonts, at each paint, resized only when a measure changed (a font
--     offset); "line" keeps 180 x 30 (taller only for a bar over 4 px).
--   * The dump line (`clock: layout <key>, <n> overrides (<keys>)`) through
--     MD:AddDumpLine, added the first time the look is not the default one,
--     so the dump of a player who never touched the clock is what it was.
--
-- What it never does: Show / Hide the frame it draws into (each line keeps
-- the single visibility owner, CLAUDE.md; a layout switch rebuilds regions
-- INSIDE the frame), read a client value (the face is plain; the bar's pool
-- and five-second rule come from the line's `draw` callbacks), or read MD.db
-- outside CV.Look / CV.SetLayout / CV.Set / CV.ResetToStyle.
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
-- ("~0:00 vv" is never drawn, but nothing drawn is wider).
CV.VALUE_SAMPLE = ">0:00 vv"

CV.SOURCES = { "pool", "model", "time", "fsr", "none" }
local SOURCE_SET = { pool = true, model = true, time = true, fsr = true, none = true }

-- The layouts this file draws, in the order a picker lists them. T104 adds
-- the ring to CV.LAYOUT and here.
CV.LAYOUTS = { "line", "compact", "bar" }
CV.LAYOUT = {
    -- L1: T82's panel, T93's segments, the line's own bar (decision 15 (a))
    line = { name = "Line", width = 180, height = 30, second = true,
        bar = { source = "line", spark = "none", height = 4, horizon = 180, color = "source" } },
    -- L2: one big number; the rest segment lives in the hover
    compact = { name = "Compact", width = 72, height = 36, second = false, inset = 6, valueSize = 22,
        bar = { source = "none", spark = "none", height = 2, horizon = 180, color = "source" } },
    -- L3: a bar with the time on it
    bar = { name = "Bar", width = 200, height = 18, second = false, inset = 6,
        bar = { source = "line", spark = "none", height = 14, horizon = 180, color = "source" } },
}

-- The colours a source draws in when the look says "source" (decision 15:
-- each line keeps its meaning): the five-second rule's amber while it fills
-- and green once spirit regen runs (UI/Widget.lua's since v0.1), the pool's
-- and the model's mana blue (UI/Clock_Forever.lua's since T11).
CV.FSR_COLOR   = { 1, 0.67, 0.2 }
CV.REGEN_COLOR = { 0.2, 1, 0.4 }
CV.MANA_COLOR  = { 0.3, 0.6, 1 }
CV.SPARK_COLOR = { 1, 1, 0 }        -- ElvUI's five-second-rule spark
CV.SPARK_WIDTH = 2

--------------------------------------------------------------------------------
-- Sources: what a layout may draw from, on which line.
--------------------------------------------------------------------------------
-- CV.SourceOK(layout, source, facts) -> true | false, why. `facts` is the
-- line's: poolPlain (TBC: the pool can be read), model (Forever: there is a
-- modelled pool). The ring (T104) cannot draw the real pool where it is only
-- ever handed to a status bar unread.
function CV.SourceOK(layout, source, facts)
    facts = facts or {}
    if not SOURCE_SET[source] then return false, "unknown source '" .. tostring(source) .. "'" end
    if source == "model" and not facts.model then
        return false, "no modelled pool on this line: it reads the real one"
    end
    if source == "pool" and layout == "ring" and not facts.poolPlain then
        return false, "the real pool is drawn by the game, never read: a ring cannot show it here"
    end
    return true
end

--------------------------------------------------------------------------------
-- The overrides (`over`), each with what it accepts. A control (T102) writes
-- one through CV.Set; a value this table refuses is never stored.
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
local function OneOf(...)
    local set = {}
    for _, k in ipairs({ ... }) do set[k] = true end
    return function(v) return set[v] == true end
end
local function Hex(v) return type(v) == "string" and v:match("^%x%x%x%x%x%x$") ~= nil end

CV.OVER = {
    ["panel.fill"] = IsColour,
    ["panel.edge"] = IsColour,
    ["bar.source"] = function(v) return SOURCE_SET[v] == true end,
    ["bar.spark"] = OneOf("none", "fsr"),
    ["bar.height"] = Range(2, 24),
    ["bar.horizon"] = Range(60, 600),
    ["bar.color"] = function(v) return v == "source" or v == "tone" or v == "class" or IsColour(v) end,
    ["bar.back"] = IsColour,
    ["colors.crit"] = Hex, ["colors.warn"] = Hex, ["colors.normal"] = Hex,
    ["colors.good"] = Hex, ["colors.muted"] = Hex, ["colors.mana"] = Hex,
}

local function Get(t, dotted)
    local a, b = dotted:match("^([^.]+)%.(.+)$")
    if not a then return type(t) == "table" and t[dotted] or nil end
    local sub = type(t) == "table" and t[a]
    return type(sub) == "table" and sub[b] or nil
end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x) end
    return out
end

--------------------------------------------------------------------------------
-- The resolver: layout defaults <- the style's clock role <- over.
--------------------------------------------------------------------------------
local function Renderable(key)
    return type(key) == "string" and CV.LAYOUT[key] ~= nil
end

-- CV.Resolve(stored, role, facts) -> look. Pure: `stored` is db.clockLook's
-- shape ({ layout, over }), `role` the style's clock recipe, `facts` the
-- line's (source = its own bar meaning, poolPlain, model, labelSample, show).
-- A layout nobody draws (yet) is "line"; an override this file does not
-- accept is ignored; a source the layout may not draw on this line falls
-- back to the line's own (look.refused names what was refused and why).
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
        bar = {
            source = d.bar.source == "line" and (facts.source or "none") or d.bar.source,
            spark = d.bar.spark, height = d.bar.height, horizon = d.bar.horizon, color = d.bar.color,
            back = (role.bar ~= nil and IsColour(role.bar)) and Copy(role.bar) or { 0, 0, 0, 1 },
        },
        colors = {},
        refused = {},
    }
    if role.barFill ~= nil and IsColour(role.barFill) then look.bar.color = Copy(role.barFill) end
    if role.ring ~= nil then look.ring = Copy(role.ring) end

    for k, ok in pairs(CV.OVER) do
        local v = Get(over, k)
        if v ~= nil then
            if ok(v) then
                local a, b = k:match("^([^.]+)%.(.+)$")
                look[a][b] = Copy(v)
            else
                look.refused[k] = "not accepted: " .. tostring(v)
            end
        end
    end

    local src = look.bar.source
    local okS, why = CV.SourceOK(key, src, facts)
    if not okS then
        look.refused["bar.source"] = why
        local own = facts.source or "none"
        look.bar.source = CV.SourceOK(key, own, facts) and own or "none"
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
-- The store: db.clockLook, written only here.
--------------------------------------------------------------------------------
local dumpAdded = false

local function Stored()
    local db = MD.db
    if type(db) ~= "table" then return { layout = "line", over = {} } end
    if type(db.clockLook) ~= "table" then db.clockLook = { layout = "line", over = {} } end
    if type(MD.db.clockLook.over) ~= "table" then MD.db.clockLook.over = {} end
    return MD.db.clockLook
end

local function OverKeys(over)
    local keys = {}
    for k in pairs(CV.OVER) do
        if Get(over, k) ~= nil then keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

-- `clock: layout bar, 2 overrides (bar.source, colors.crit)` -- /st dump's line.
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
-- dotted); nil removes it. Saved, CLOCK_LOOK fired.
function CV.Set(key, value)
    local ok = CV.OVER[key]
    if not ok then return false, "not a clock look setting: " .. tostring(key) end
    if value ~= nil and not ok(value) then return false, key .. ": not accepted: " .. tostring(value) end
    local over = Stored().over
    local a, b = key:match("^([^.]+)%.(.+)$")
    if type(over[a]) ~= "table" then over[a] = {} end
    over[a][b] = Copy(value)
    if next(over[a]) == nil then over[a] = nil end
    Changed()
    return true
end

-- "Reset to style" (7.3): every override gone, the layout kept.
function CV.ResetToStyle()
    Stored().over = {}
    Changed()
    return true
end

--------------------------------------------------------------------------------
-- The view
--------------------------------------------------------------------------------
local View = {}
View.__index = View

local function FontObj(name)
    return (UI.fontObjects and UI.fontObjects[name]) or _G[name]
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

-- Each layout's own regions, built on first use.
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
    return set
end

BUILD.bar = function(v)
    local p = v.parent
    -- the text sits on a frame above the bar (the bar is a child frame and
    -- draws over the parent's own regions)
    local over = CreateFrame("Frame", nil, p)
    over:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    over:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    local set = { holder = over }
    set.label = NewText(over, UI.FONT)
    set.label:SetJustifyH("LEFT")
    set.value = NewText(over, UI.FONT_NUM or UI.FONT)
    set.value:SetJustifyH("RIGHT")
    set.msg = NewText(over, UI.FONT)
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

-- The layout's metrics: the frame's size and where each piece goes, from
-- measures in the layout's own fonts. A table compared field by field, so a
-- paint re-anchors only when something moved.
local METRICS = {}

METRICS.line = function(v, look)
    local labelW = Measure(v:ProbeIn(UI.FONT), look.labelSample or "FULL")
    local barH = look.bar.source ~= "none" and look.bar.height or 4
    return {
        w = look.width, h = look.height + math.max(0, barH - 4),
        valueX = CV.INSET + labelW + CV.GAP,
        barW = look.width - 20, barH = barH,
    }
end

METRICS.compact = function(v, look)
    local inset = look.inset or 6
    local probe = v:ProbeIn(UI.FONT_SMALL or UI.FONT)
    local labelW = Measure(probe, look.labelSample or "FULL")
    local labelH = MeasureH(probe, look.labelSample or "FULL")
    local face, size, flags = NumFont(look.valueSize or 22)
    local sp = v:SizedProbe()
    sp:SetFont(face, size, flags)
    local valueW = Measure(sp, CV.VALUE_SAMPLE)
    local valueH = MeasureH(sp, CV.VALUE_SAMPLE)
    local barOn = look.bar.source ~= "none"
    local barH = barOn and look.bar.height or 0
    local w = math.max(look.width, 2 * inset + math.max(labelW, valueW))
    local h = 4 + labelH + 1 + valueH + 4 + (barOn and (barH + 3) or 0)
    return {
        w = w, h = math.max(look.height, h), inset = inset,
        valueY = -(4 + labelH + 1), face = face, size = size, flags = flags,
        barW = w - 2 * inset, barH = barH,
    }
end

METRICS.bar = function(v, look)
    local inset = look.inset or 6
    local probe = v:ProbeIn(UI.FONT)
    local labelW = Measure(probe, look.labelSample or "FULL")
    local labelH = MeasureH(probe, look.labelSample or "FULL")
    local vprobe = v:ProbeIn(UI.FONT_NUM or UI.FONT)
    local valueW = Measure(vprobe, CV.VALUE_SAMPLE)
    local valueH = MeasureH(vprobe, CV.VALUE_SAMPLE)
    v:ProbeIn(UI.FONT) -- the probe back in the label's font (the line's slot measure)
    local w = math.max(look.width, 2 * inset + labelW + 2 * CV.GAP + valueW)
    local h = math.max(look.height, math.max(labelH, valueH) + 6)
    return { w = w, h = h, inset = inset, barW = w - 4, barH = h - 4 }
end

local function SameMetrics(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, x in pairs(a) do if b[k] ~= x then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- Where each layout puts its pieces and the bar.
local PLACE = {}

PLACE.line = function(v, set, m)
    local p = v.parent
    set.label:ClearAllPoints()
    set.label:SetPoint("TOPLEFT", p, "TOPLEFT", CV.INSET, CV.TOP)
    set.value:ClearAllPoints()
    set.value:SetPoint("TOPLEFT", p, "TOPLEFT", m.valueX, CV.TOP)
    set.second:ClearAllPoints()
    set.second:SetPoint("TOPRIGHT", p, "TOPRIGHT", -CV.INSET, CV.TOP)
    set.msg:ClearAllPoints()
    set.msg:SetPoint("TOP", p, "TOP", 0, CV.TOP)
    v.bar:ClearAllPoints()
    v.bar:SetPoint("BOTTOM", p, "BOTTOM", 0, 5)
end

PLACE.compact = function(v, set, m)
    local p = v.parent
    set.value:SetFont(m.face, m.size, m.flags)
    set.label:ClearAllPoints()
    set.label:SetPoint("TOPLEFT", p, "TOPLEFT", m.inset, CV.TOP)
    set.value:ClearAllPoints()
    set.value:SetPoint("TOPLEFT", p, "TOPLEFT", m.inset, m.valueY)
    set.msg:ClearAllPoints()
    set.msg:SetPoint("CENTER", p, "CENTER", 0, 0)
    set.msg:SetWidth(m.w - 4) -- the preview's words wrap inside a narrow clock
    v.bar:ClearAllPoints()
    v.bar:SetPoint("BOTTOM", p, "BOTTOM", 0, 4)
end

PLACE.bar = function(v, set, m)
    local p = v.parent
    set.label:ClearAllPoints()
    set.label:SetPoint("LEFT", set.holder, "LEFT", m.inset, 0)
    set.value:ClearAllPoints()
    set.value:SetPoint("RIGHT", set.holder, "RIGHT", -m.inset, 0)
    set.msg:ClearAllPoints()
    set.msg:SetPoint("CENTER", set.holder, "CENTER", 0, 0)
    v.bar:ClearAllPoints()
    v.bar:SetPoint("CENTER", p, "CENTER", 0, 0)
    set.holder:SetFrameLevel((v.bar:GetFrameLevel() or 1) + 1)
end

-- The backing one physical pixel wider than the bar on every side (T41).
function View:SizeBack()
    local e = UI.px and UI.px(1, self.parent) or 1
    self.barBack:SetSize(self.barW + 2 * e, self.barH + 2 * e)
    self.snappedPx = e
end

-- Apply a layout's metrics: the frame's size, the pieces, the bar. Never the
-- frame's Show / Hide.
function View:Place(m)
    local key = self.look.layout
    self.parent:SetSize(m.w, m.h)
    self.barW, self.barH = m.barW, m.barH
    self.bar:SetSize(m.barW, m.barH)
    PLACE[key](self, self.active, m)
    self:SizeBack()
    self.metrics = m
end

-- view:SetLook(look): a new resolved look (a layout switch, an override, a
-- style). The layout's regions are made the first time, the others' hidden;
-- the panel is skinned; the bar's backing and shape follow. Nothing is
-- painted from a face here: the line's next paint does that.
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
    if self.bar then
        local back = (UI.SkinColour and UI.SkinColour(look.bar.back)) or { 0, 0, 0, 1 }
        self.barBack:SetColorTexture(back[1], back[2], back[3], back[4] or 1)
        self:ShowBar(look.bar.source ~= "none")
        self:Place(METRICS[key](self, look))
        self:Snap()
    end
end

function View:ShowBar(on)
    if on then
        self.bar:Show()
        self.barBack:Show()
    else
        self.bar:Hide()
        self.barBack:Hide()
        if self.spark then self.spark:Hide() end
    end
    self.barOn = on and true or false
end

-- view:Snap(): the panel (UI.Skin(frame, "clock"), the look's fill and edge)
-- and the backing at the current physical pixel -- the line calls it when
-- UI.px(1) has moved (the window manager never touches a clock, T41).
function View:Snap()
    local panel = self.look.panel or {}
    UI.Skin(self.parent, "clock", panel.fill or "bg", panel.edge or "border")
    if self.bar then self:SizeBack() end
end

-- MD.ClockView.Build(parent, look, draw) -> view. `parent` is the line's
-- frame; `look` a resolved look (CV.Look) -- or T93's shape (labelSample,
-- colors, show), which reads as the line layout with no bar source;
-- `draw` (optional) the line's bar sources: pool(bar) draws the real pool
-- into the bar, fsr(now) answers the seconds left in the five-second rule.
function CV.Build(parent, look, draw)
    look = look or {}
    if look.layout == nil then
        local resolved = CV.Resolve({ layout = "line", over = {} }, CV.Role(), {
            labelSample = look.labelSample, show = look.show, source = "none" })
        resolved.colors = look.colors or resolved.colors
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

    -- the bar (T41's 160 x 4 slot under the line layout) and its black
    -- backing, a texture of the frame: the bar is a child frame and draws
    -- above it, the backdrop beneath it
    v.bar = CreateFrame("StatusBar", nil, parent)
    v.bar:SetStatusBarTexture(UI.whiteTexture)
    v.barBack = parent:CreateTexture(nil, "ARTWORK")
    v.barBack:SetPoint("CENTER", v.bar, "CENTER", 0, 0)

    v:SetLook(look)
    return v
end

-- The pieces' places again, only when a measure moved (a font offset).
function View:Layout()
    local key = self.look.layout
    local m = METRICS[key](self, self.look)
    if SameMetrics(m, self.metrics) then return end
    local old = self.metrics
    if key == "line" and old and old.w == m.w and old.h == m.h and old.barW == m.barW and old.barH == m.barH then
        -- T93: only the value moves when the label slot's width did
        self.value:ClearAllPoints()
        self.value:SetPoint("TOPLEFT", self.parent, "TOPLEFT", m.valueX, CV.TOP)
        self.metrics = m
        return
    end
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
-- The bar
--------------------------------------------------------------------------------
local function Clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

-- The colour a look's bar takes this paint.
function View:BarColour(kind, remaining)
    local c = self.look.bar.color
    if c == "tone" then
        local face = self.face
        return MD.ClockFace.ToneRGB(face and face.tone or "muted", self.look.colors)
    elseif c == "class" then
        local a = UI.classAccent or UI.accent or { 1, 1, 1 }
        return a[1], a[2], a[3]
    elseif c ~= "source" and c ~= nil then
        local rgba = UI.SkinColour and UI.SkinColour(c) or c
        if type(rgba) == "table" then return rgba[1], rgba[2], rgba[3] end
    end
    if kind == "fsr" then
        local s = (remaining or 0) > 0 and CV.FSR_COLOR or CV.REGEN_COLOR
        return s[1], s[2], s[3]
    elseif kind == "time" then
        local face = self.face
        return MD.ClockFace.ToneRGB(face and face.tone or "muted", self.look.colors)
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

-- view:PaintBar(now): the bar from its source, its colour, the spark. The
-- pool is the line's to draw (draw.pool: TBC reads it, Forever hands it to
-- the bar through MD.API.DrawUnitPower); nothing here reads the bar back.
function View:PaintBar(now)
    if not self.bar then return end
    local b = self.look.bar
    local src = b.source
    if src == "none" or not self.barOn then
        if self.spark then self.spark:Hide() end
        return
    end
    local bar = self.bar
    local remaining = self:FSR(now)
    if src == "pool" then
        if type(self.draw.pool) == "function" then self.draw.pool(bar) end
    elseif src == "fsr" then
        bar:SetMinMaxValues(0, 5)
        bar:SetValue(5 - (remaining or 0))
    elseif src == "model" then
        local face = self.face
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(face and type(face.pct) == "number" and Clamp01(face.pct) or 0)
    elseif src == "time" then
        local face, frac = self.face, 0
        if face then
            local full = face.mode == "full" or face.mode == "ooc" or face.mode == "fullnow"
            if full then
                frac = 1
            elseif (face.known == "point" or face.known == "bound") and type(face.value) == "number" then
                frac = Clamp01(face.value / (b.horizon or 180))
            end
        end
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(frac)
    end
    bar:SetStatusBarColor(self:BarColour(src, remaining))
    self:PaintSpark(remaining)
end

-- The spark: yellow, sweeping the bar over the five seconds after a spend.
function View:PaintSpark(remaining)
    if self.look.bar.spark ~= "fsr" or not self.barOn then
        if self.spark then self.spark:Hide() end
        return
    end
    if not self.spark then
        self.spark = self.bar:CreateTexture(nil, "OVERLAY")
        self.spark:SetColorTexture(CV.SPARK_COLOR[1], CV.SPARK_COLOR[2], CV.SPARK_COLOR[3], 1)
        if self.spark.SetBlendMode then self.spark:SetBlendMode("ADD") end
    end
    local s = self.spark
    if type(remaining) ~= "number" or remaining <= 0 then
        s:Hide()
        return
    end
    local w = UI.px and UI.px(CV.SPARK_WIDTH, self.parent) or CV.SPARK_WIDTH
    s:SetSize(w, self.barH)
    s:ClearAllPoints()
    s:SetPoint("CENTER", self.bar, "LEFT", (5 - remaining) / 5 * self.barW, 0)
    s:Show()
end

-- view:FillBar(r, g, b): the preview's full bar in one colour (TBC's unlock).
function View:FillBar(r, g, b)
    if not (self.bar and self.barOn) then return end
    self.bar:SetMinMaxValues(0, 5)
    self.bar:SetValue(5)
    self.bar:SetStatusBarColor(r, g, b)
    if self.spark then self.spark:Hide() end
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
