-- T145b (docs/SPEC-clock-v3.md 1.3-1.5, 2.1; docs/tasks/T145b-clock-store.md):
-- the clock's look, STORED. db.clockLook is dense and versioned (decision
-- D2): { v = 3, every field }, and this file is its one writer.
--
--   ClockStore.DEFAULTS          the v3 look (the SpellTuner preset)
--   ClockStore.Normalize(raw)    -> look, notes: a dense, valid copy; every
--                                missing or invalid field put back from the
--                                default and named in `notes` (strings)
--   ClockStore.Migrate(raw)      -> look, notes, from: any older store (v1
--                                0.16.6 keys, v2 T142's sparse `over`, none,
--                                garbage) as a v3 look; pure and idempotent
--                                (a v3 store is only normalized)
--   ClockStore.MigrateStored(force)  db.clockLook rewritten as v3 once a
--                                session; the notes kept for the dump
--   ClockStore.Look()            -> look: a validated copy of what is stored
--                                (an older store migrated on the copy only)
--   ClockStore.Get(path)         one field of Look() ("texts.mana.size")
--   ClockStore.Set(key, value)   one field ("width", "texts.mana.size"),
--   ClockStore.SetText(kind, field, value)
--   ClockStore.ApplyPreset(key, opts) / Undo() / Reset()
--                                each ONE write and ONE CLOCK_LOOK; a refused
--                                value writes nothing and fires nothing
--   ClockStore.PRESETS           SpellTuner and EllesmereUI (1.4); none may
--                                turn off the time or the 5SR line (P2)
--   ClockStore.DumpLine()        the `clock:` line for /st dump
--
-- PURE but for ST.db (the store) and ST:Fire / ST:AddDumpLine: no frame, no
-- client call, no style token (a colour is the user's hex). T145b: nothing
-- reads it yet and db.clockLook is not rewritten at login -- MigrateStored is
-- called by the tests only until T145c wires it at MD_READY and deletes
-- UI/ClockView.lua (whose v1 rules, CV.Migrate and CV.ResetBarLook, are
-- COPIED below, not shared, so they leave with that file).
local _, ST = ...

ST.ClockStore = ST.ClockStore or {}
local Store = ST.ClockStore

Store.VERSION = 3

--------------------------------------------------------------------------------
-- The schema
--------------------------------------------------------------------------------
-- The texts, in drawing order (Engine/ClockWords.lua's kinds), and each one's
-- fields.
Store.KINDS = { "time", "mana", "manaMax", "pct", "mp5", "fsr", "rest" }
Store.TEXT_FIELDS = { "on", "place", "align", "x", "y", "size", "colour", "outline" }
Store.NAMES = { time = "Time", mana = "Mana", manaMax = "Mana / max", pct = "Mana %", mp5 = "Regen",
    fsr = "5SR", rest = "Rest" }
-- The bar's fields, in the order the dump and the notes walk them.
Store.FIELDS = { "width", "height", "shape", "frame", "texture", "font", "fill", "back", "backAlpha",
    "line", "timeFmt", "warn" }

Store.VALUES = {
    shape = { "rect", "round", "pill" },
    frame = { "none", "border", "game" },
    font = { "eui", "st" },
    timeFmt = { "mss", "sec" },
    place = { "inside", "above", "below" },
    align = { "left", "center", "right" },
    outline = { "none", "outline", "thick", "shadow" },
}
-- SpellTuner's own bar textures (Media/, the game's two); "gradient" is gone
-- (it alone used Fill end). "eui:<key>" and "lsm:<name>" name a host's.
Store.TEXTURES = { "soft", "flat", "smooth", "gloss", "striped", "minimal", "statusbar", "raid" }
Store.EUI_PREFIX = "eui:"
Store.LSM_PREFIX = "lsm:"
Store.RANGES = {
    width = { 100, 400 }, height = { 3, 30 }, backAlpha = { 0, 1 },
    x = { -40, 40 }, y = { -20, 20 }, size = { 6, 32 },
}
-- Fill: "mana" is the Mana blue below, "class" the player's class colour,
-- else six hex digits.
Store.MANA_BLUE = "396DA7"

local function T(on, place, align, x, y, size, colour, outline)
    return { on = on, place = place, align = align, x = x, y = y, size = size, colour = colour, outline = outline }
end

-- The SpellTuner preset is the default: the author's T142 pick (the mockup's
-- `spelltuner`). Pixels Dark draws Soft without EllesmereUI (the renderer's
-- fallback, named beside the control); the store keeps the choice.
Store.DEFAULTS = {
    v = 3,
    width = 200, height = 8, shape = "round", frame = "game", texture = "eui:pixels-dark", font = "eui",
    fill = "mana", back = "0A0A0A", backAlpha = 1, line = true, timeFmt = "mss", warn = true,
    texts = {
        time = T(true, "below", "left", 0, -1, 11, "E4E1DC", "none"),
        mana = T(true, "inside", "center", 0, 0, 11, "E4E1DC", "none"),
        manaMax = T(false, "inside", "center", 0, 0, 11, "E4E1DC", "none"),
        pct = T(false, "above", "right", 0, 1, 11, "E4E1DC", "none"),
        mp5 = T(true, "below", "right", 0, -1, 11, "9FD7A9", "none"),
        fsr = T(false, "above", "left", 0, 1, 11, "FFAB33", "none"),
        rest = T(false, "below", "right", 0, -1, 11, "8F8A83", "none"),
    },
}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------
local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x) end
    return out
end
Store.Copy = Copy

local function Plain(x) return type(x) == "number" and x == x end
local function Hex(v) return type(v) == "string" and v:match("^%x%x%x%x%x%x$") ~= nil end
local function OneOf(list)
    local set = {}
    for _, k in ipairs(list) do set[k] = true end
    return function(v) return set[v] == true end
end
local function Range(lo, hi) return function(v) return Plain(v) and v >= lo and v <= hi end end
local function IntRange(lo, hi)
    return function(v) return Plain(v) and v >= lo and v <= hi and math.floor(v) == v end
end
local function Bool(v) return type(v) == "boolean" end
local function Prefixed(v, pre) return type(v) == "string" and #v > #pre and v:sub(1, #pre) == pre end

local OwnTexture = OneOf(Store.TEXTURES)
local R = Store.RANGES

-- What each field accepts.
Store.OK = {
    width = Range(R.width[1], R.width[2]),
    height = IntRange(R.height[1], R.height[2]),
    shape = OneOf(Store.VALUES.shape),
    frame = OneOf(Store.VALUES.frame),
    texture = function(v) return OwnTexture(v) or Prefixed(v, Store.EUI_PREFIX) or Prefixed(v, Store.LSM_PREFIX) end,
    font = OneOf(Store.VALUES.font),
    fill = function(v) return v == "mana" or v == "class" or Hex(v) end,
    back = Hex,
    backAlpha = Range(R.backAlpha[1], R.backAlpha[2]),
    line = Bool,
    timeFmt = OneOf(Store.VALUES.timeFmt),
    warn = Bool,
}
Store.TEXT_OK = {
    on = Bool,
    place = OneOf(Store.VALUES.place), align = OneOf(Store.VALUES.align),
    x = IntRange(R.x[1], R.x[2]), y = IntRange(R.y[1], R.y[2]),
    size = IntRange(R.size[1], R.size[2]),
    colour = Hex,
    outline = OneOf(Store.VALUES.outline),
}

-- A value as a note says it: a colour table as hex, a string as it is.
local function Say(v)
    if type(v) == "table" then
        local n = {}
        for i = 1, 4 do if Plain(v[i]) then n[#n + 1] = string.format("%.2f", v[i]) end end
        if v.ref ~= nil then return "{ref " .. tostring(v.ref) .. "}" end
        return "{" .. table.concat(n, ",") .. "}"
    end
    return tostring(v)
end

local function Index(list)
    local out = {}
    for i, k in ipairs(list) do out[k] = i end
    return out
end
local KIND_INDEX = Index(Store.KINDS)
local FIELD_INDEX = Index(Store.FIELDS)
local TEXT_FIELD_INDEX = Index(Store.TEXT_FIELDS)

--------------------------------------------------------------------------------
-- Normalize
--------------------------------------------------------------------------------
-- Store.Normalize(raw) -> look, notes. `raw` is any value; the answer is a new
-- dense v3 table (never `raw` itself) and the notes name, in a fixed order,
-- every field put back (missing, not accepted) and every key dropped (not a
-- v3 field). Idempotent: Normalize of a Normalize gives no notes.
function Store.Normalize(raw)
    local notes = {}
    local look = Copy(Store.DEFAULTS)
    if type(raw) ~= "table" then
        notes[1] = "the store was not a table (" .. type(raw) .. "): the defaults"
        return look, notes
    end
    if raw.v ~= Store.VERSION then notes[#notes + 1] = "v " .. Say(raw.v) .. " -> " .. Store.VERSION end
    for _, f in ipairs(Store.FIELDS) do
        local v = raw[f]
        if v == nil then
            notes[#notes + 1] = f .. " missing: " .. Say(look[f])
        elseif Store.OK[f](v) then
            look[f] = v
        else
            notes[#notes + 1] = f .. " " .. Say(v) .. " not accepted: " .. Say(look[f])
        end
    end
    local texts = raw.texts
    if type(texts) ~= "table" then
        notes[#notes + 1] = "texts missing: the defaults"
    else
        for _, kind in ipairs(Store.KINDS) do
            local t = texts[kind]
            if type(t) ~= "table" then
                notes[#notes + 1] = "texts." .. kind .. " missing: the default"
            else
                for _, f in ipairs(Store.TEXT_FIELDS) do
                    local v = t[f]
                    local key = "texts." .. kind .. "." .. f
                    if v == nil then
                        notes[#notes + 1] = key .. " missing: " .. Say(look.texts[kind][f])
                    elseif Store.TEXT_OK[f](v) then
                        look.texts[kind][f] = v
                    else
                        notes[#notes + 1] = key .. " " .. Say(v) .. " not accepted: " .. Say(look.texts[kind][f])
                    end
                end
                local extra = {}
                for k in pairs(t) do
                    if not TEXT_FIELD_INDEX[k] then extra[#extra + 1] = tostring(k) end
                end
                table.sort(extra)
                for _, k in ipairs(extra) do notes[#notes + 1] = "texts." .. kind .. "." .. k .. " dropped: not a v3 field" end
            end
        end
        local extra = {}
        for k in pairs(texts) do
            if not KIND_INDEX[k] then extra[#extra + 1] = tostring(k) end
        end
        table.sort(extra)
        for _, k in ipairs(extra) do notes[#notes + 1] = "texts." .. k .. " dropped: not a v3 text" end
    end
    local extra = {}
    for k in pairs(raw) do
        if k ~= "v" and k ~= "texts" and not FIELD_INDEX[k] then extra[#extra + 1] = tostring(k) end
    end
    table.sort(extra)
    for _, k in ipairs(extra) do notes[#notes + 1] = k .. " dropped: not a v3 field" end
    return look, notes
end

-- Store.Valid(look) -> true when Normalize would change nothing.
function Store.Valid(look)
    local _, notes = Store.Normalize(look)
    return #notes == 0, notes[1]
end

--------------------------------------------------------------------------------
-- v1: 0.16.6's keys (UI/ClockView.lua's CV.Migrate and CV.ResetBarLook,
-- copied as they are; ClockView's IsColour also took a palette name, which
-- this pure file cannot judge, so such a colour is dropped and named)
--------------------------------------------------------------------------------
local V1_LAYOUTS = { "line", "compact", "bar" }
local OLD_SOURCE_SHOW = { pool = "mana", model = "mana", fsr = "fsr", none = "none" }

local function IsColour(v)
    if type(v) ~= "table" then return false end
    if v.ref ~= nil then return v.ref == "accent" end
    for i = 1, 3 do
        if type(v[i]) ~= "number" or v[i] < 0 or v[i] > 1 then return false end
    end
    return v[4] == nil or (type(v[4]) == "number" and v[4] >= 0 and v[4] <= 1)
end

local function Get(t, dotted)
    for part in dotted:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

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

-- CV.Migrate: bar.source / color / spark / horizon / height. -> changed, dropped
local function MigrateV1(stored, facts)
    facts = type(facts) == "table" and facts or {}
    if type(stored) ~= "table" or type(stored.over) ~= "table" then return false, {} end
    local over = stored.over
    local old = over.bar
    if type(old) ~= "table" then return false, {} end
    local changed, dropped = false, {}
    local function Each(field, value)
        for _, L in ipairs(V1_LAYOUTS) do
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

-- CV.ResetBarLook: before v 2 the Bar layout's look was reset once (T142, the
-- author's "override my ingame setting"). -> reset (sorted keys)
local RESET_COLOURS = { "colors.manaBar", "bar.back", "colors.fillEnd", "colors.edge", "colors.fsrLine", "colors.after" }
local function ResetBarLookV1(stored)
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
        for _, k in ipairs(RESET_COLOURS) do
            if Get(over, k) ~= nil then
                reset[#reset + 1] = k
                PutPath(over, k, nil)
            end
        end
    end
    table.sort(reset)
    return reset
end

--------------------------------------------------------------------------------
-- v2 -> v3 (1.5)
--------------------------------------------------------------------------------
-- The T142 defaults of each Bar text (UI/ClockView.lua's CV.ITEMS_DEFAULT): a
-- v2 item is sparse over these, as CV.ResolveItems read it. `label` is the
-- kind v3 drops (its word is now part of the time).
local V2_ITEMS = {
    label = T(false, "below", "left", 0, -1, 11, "E4E1DC", "none"),
}
for _, kind in ipairs(Store.KINDS) do V2_ITEMS[kind] = Copy(Store.DEFAULTS.texts[kind]) end

local function Hex2(x)
    local n = math.floor(x * 255 + 0.5)
    if n < 0 then n = 0 elseif n > 255 then n = 255 end
    return string.format("%02X", n)
end
-- A v2 colour table { r, g, b [, a] } (0..1) -> "RRGGBB", alpha; else nil.
local function ColourHex(v)
    if type(v) ~= "table" or v.ref ~= nil then return nil end
    for i = 1, 3 do
        if not Plain(v[i]) or v[i] < 0 or v[i] > 1 then return nil end
    end
    local a = v[4]
    if a ~= nil and not (Plain(a) and a >= 0 and a <= 1) then return nil end
    return Hex2(v[1]) .. Hex2(v[2]) .. Hex2(v[3]), a or 1
end

-- Every leaf of a v2 `over` (a colour table is a leaf), as sorted dotted keys.
local function Leaves(over)
    local keys = {}
    local function Walk(t, prefix)
        for k, x in pairs(t) do
            local key = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
            if type(x) == "table" and next(x) == nil then
                -- an empty table holds nothing to keep or to name
            elseif type(x) == "table" and ColourHex(x) == nil and x.ref == nil then
                Walk(x, key)
            else
                keys[#keys + 1] = key
            end
        end
    end
    Walk(over, "")
    table.sort(keys)
    return keys
end

-- Why each Bar key with no v3 home is dropped (1.3's table).
local DROP_WHY = {
    ["bars.bar.join"] = "the moving line only",
    ["bars.bar.order"] = "only the stacked strip used it",
    ["bars.bar.fsr"] = "only the stacked strip used it",
    ["bars.bar.after"] = "the line simply ends with the rule",
    ["bars.bar.mana"] = "always the game's pool",
    ["bars.bar.border"] = "Frame = Border draws 1 px",
    ["frame.bar.h"] = "the bar's height is Height",
    ["frame.bar.scale"] = "Width, Height and each text's size cover it",
    ["text.bar.labels"] = "one word left (FULL)",
    ["colors.fillEnd"] = "only Gradient used it",
    ["colors.edge"] = "black",
    ["colors.fsrLine"] = "amber, fixed",
    ["colors.after"] = "the line simply ends with the rule",
}
local function DropWhy(key)
    if DROP_WHY[key] then return DROP_WHY[key] end
    local area, L = key:match("^([^.]+)%.([^.]+)")
    if (L == "line" or L == "compact") and (area == "bars" or area == "text" or area == "frame") then
        return "Line and Compact are gone"
    end
    if area == "panel" then return "the Bar has no panel" end
    if area == "colors" then return "the Bar paints each text in its own colour" end
    return "not a v3 setting"
end

-- One text's v2 fields read over V2_ITEMS[kind] (CV.ResolveItems' rule): an
-- accepted value kept, else the default and a note.
local function ItemOver(kind, item, notes)
    local out = Copy(V2_ITEMS[kind])
    if type(item) ~= "table" then return out end
    for _, f in ipairs(Store.TEXT_FIELDS) do
        local v = item[f]
        if v ~= nil then
            if Store.TEXT_OK[f](v) then
                out[f] = v
            else
                notes[#notes + 1] = "dropped text.bar.items." .. kind .. "." .. f .. " = " .. Say(v) .. ": not accepted"
            end
        end
    end
    return out
end

local function MigrateV2(s, notes)
    local look = Copy(Store.DEFAULTS)
    local over = type(s.over) == "table" and s.over or {}
    local layout = s.layout
    if layout == "line" or layout == "compact" then
        notes[#notes + 1] = "changed layout = " .. layout .. " -> the Bar (Line and Compact are gone)"
    elseif layout ~= nil and layout ~= "bar" then
        notes[#notes + 1] = "dropped layout = " .. Say(layout) .. ": not a layout"
    end

    local barsBar = type(over.bars) == "table" and type(over.bars.bar) == "table" and over.bars.bar or {}
    local doneItems = false
    for _, key in ipairs(Leaves(over)) do
        local v = Get(over, key)
        local item = key:match("^text%.bar%.items%.([^.]+)")
        if item then
            if not doneItems then
                doneItems = true
                local items = over.text.bar.items
                for _, kind in ipairs(Store.KINDS) do
                    if items[kind] ~= nil then look.texts[kind] = ItemOver(kind, items[kind], notes) end
                end
                local extra = {}
                for k in pairs(items) do if not KIND_INDEX[k] then extra[#extra + 1] = tostring(k) end end
                table.sort(extra)
                for _, k in ipairs(extra) do
                    if k == "label" then
                        local l = ItemOver("label", items.label, {})
                        notes[#notes + 1] = string.format("dropped text.bar.items.label (%s %s, %d/%d, %d): its word is now part of the time",
                            l.place, l.align, l.x, l.y, l.size)
                    else
                        notes[#notes + 1] = "dropped text.bar.items." .. k .. ": not a v3 text"
                    end
                end
            end
        elseif key == "frame.bar.w" then
            if Store.OK.width(v) then look.width = v
            else notes[#notes + 1] = "dropped frame.bar.w = " .. Say(v) .. ": not accepted" end
        elseif key == "bars.bar.height" then
            if Store.OK.height(v) then look.height = v
            else notes[#notes + 1] = "dropped bars.bar.height = " .. Say(v) .. ": not accepted" end
        elseif key == "bars.bar.shape" then
            if v == "thin" then
                look.shape = "rect"
                if barsBar.height == nil then look.height = 4 end
                notes[#notes + 1] = "changed bars.bar.shape = thin -> rect" .. (barsBar.height == nil and ", height 4" or "")
            elseif Store.OK.shape(v) then
                look.shape = v
            else
                notes[#notes + 1] = "dropped bars.bar.shape = " .. Say(v) .. ": not accepted"
            end
        elseif key == "bars.bar.frame" or key == "bars.bar.font" then
            local f = key:match("([^.]+)$")
            if Store.OK[f](v) then look[f] = v
            else notes[#notes + 1] = "dropped " .. key .. " = " .. Say(v) .. ": not accepted" end
        elseif key == "bars.bar.texture" then
            if v == "gradient" then
                look.texture = "flat"
                notes[#notes + 1] = "changed bars.bar.texture = gradient -> flat"
            elseif Store.OK.texture(v) then
                look.texture = v
            else
                notes[#notes + 1] = "dropped bars.bar.texture = " .. Say(v) .. ": not accepted"
            end
        elseif key == "bars.bar.show" then
            -- D3: the moving line is on, whatever the old store said
            if v == "both" then
                notes[#notes + 1] = "dropped bars.bar.show = both: the bar and the 5SR line, as before"
            elseif v == "mana" then
                notes[#notes + 1] = "changed bars.bar.show = mana -> the 5SR line on"
            else
                notes[#notes + 1] = "changed bars.bar.show = " .. Say(v) .. " -> the mana bar and the 5SR line"
            end
        elseif key == "colors.manaBar" then
            if v == "mana" or v == "class" then
                look.fill = v
            elseif v == "tone" then
                look.fill = "mana"
                notes[#notes + 1] = "changed colors.manaBar = tone -> mana blue (the time's Warn colours say urgency)"
            else
                local hex = ColourHex(v)
                if hex then look.fill = hex
                else notes[#notes + 1] = "dropped colors.manaBar = " .. Say(v) .. ": not a colour" end
            end
        elseif key == "bar.back" then
            local hex, a = ColourHex(v)
            if hex then look.back, look.backAlpha = hex, a
            else notes[#notes + 1] = "dropped bar.back = " .. Say(v) .. ": not a colour" end
        elseif key == "text.bar.time" then
            if v == "sec" or v == "msec" then
                look.timeFmt = "sec"
                if v == "msec" then notes[#notes + 1] = "changed text.bar.time = msec -> 80s" end
            elseif v ~= "line" then
                notes[#notes + 1] = "dropped text.bar.time = " .. Say(v) .. ": not accepted"
            end
        else
            notes[#notes + 1] = "dropped " .. key .. " = " .. Say(v) .. ": " .. DropWhy(key)
        end
    end
    look.line = true -- D3
    return look
end

-- Store.Migrate(raw) -> look, notes, from. Pure: `raw` is never changed.
-- `from` is "v3" | "v2" | "v1" | "none" | "garbage". A v3 store is only
-- normalized; v1 (no v, or v under 2) runs CV.Migrate's rules and T142's Bar
-- reset first, as the T142 build did at login, and is then read as v2.
function Store.Migrate(raw)
    if raw == nil then return Copy(Store.DEFAULTS), {}, "none" end
    if type(raw) ~= "table" then
        return Copy(Store.DEFAULTS), { "dropped the store: not a table (" .. type(raw) .. "), the defaults" }, "garbage"
    end
    if raw.v == Store.VERSION then
        local look, notes = Store.Normalize(raw)
        return look, notes, "v3"
    end
    local notes = {}
    local s = Copy(raw)
    if s.over ~= nil and type(s.over) ~= "table" then
        notes[#notes + 1] = "dropped over = " .. Say(s.over) .. ": not a table"
        s.over = nil
    end
    if s.layout ~= nil and type(s.layout) ~= "string" then
        notes[#notes + 1] = "dropped layout = " .. Say(s.layout) .. ": not a layout"
        s.layout = nil
    end
    local from = "v2"
    local v = s.v
    if not (type(v) == "number" and v >= 2) then
        from = "v1"
        if next(s) == nil then return Copy(Store.DEFAULTS), notes, "none" end
        local _, dropped = MigrateV1(s, {})
        for _, k in ipairs(dropped) do notes[#notes + 1] = "dropped " .. k .. ": 0.16.6's, not read since T115" end
        for _, k in ipairs(ResetBarLookV1(s)) do
            notes[#notes + 1] = "dropped " .. k .. ": the T142 reset of the Bar look"
        end
    end
    for k in pairs(s) do
        if k ~= "v" and k ~= "layout" and k ~= "over" then
            notes[#notes + 1] = "dropped " .. tostring(k) .. ": not a clock look setting"
        end
    end
    local look = MigrateV2(s, notes)
    return look, notes, from
end

--------------------------------------------------------------------------------
-- The presets (1.4): each replaces the whole look; none turns off the time or
-- the 5SR line (P2, ApplyPreset refuses one that would).
--------------------------------------------------------------------------------
Store.PRESETS = {
    { key = "spelltuner", name = "SpellTuner",
      tip = "The game frame, rounded, 200 x 8, the time below left, the mana inside, the regen below right",
      look = Copy(Store.DEFAULTS) },
    -- EllesmereUI's resource bar; `hostFill`: the pane passes EllesmereUI's
    -- live mana colour (Integrations/Media_LSM.lua) as opts.fill, else 008CFF
    { key = "ellesmere", name = "EllesmereUI", hostFill = true,
      tip = "EllesmereUI's resource bar, 260 x 8, its mana colour, the mana inside, the time below right, the 5SR line on",
      look = {
          v = 3,
          width = 260, height = 8, shape = "round", frame = "game", texture = "eui:pixels-dark", font = "eui",
          fill = "008CFF", back = "111111", backAlpha = 0.75, line = true, timeFmt = "mss", warn = true,
          texts = {
              time = T(true, "below", "right", 0, -1, 11, "E3E3E3", "outline"),
              mana = T(true, "inside", "center", 0, 2, 15, "E3E3E3", "outline"),
              manaMax = T(false, "inside", "center", 0, 0, 12, "E3E3E3", "outline"),
              pct = T(false, "inside", "right", -4, 0, 10, "E3E3E3", "outline"),
              mp5 = T(false, "below", "right", 0, -1, 10, "9FD7A9", "outline"),
              fsr = T(false, "below", "left", 0, -1, 10, "FFAB33", "outline"),
              rest = T(false, "below", "right", 0, -1, 10, "8F8A83", "outline"),
          },
      } },
}

function Store.Preset(key)
    for _, p in ipairs(Store.PRESETS) do if p.key == key then return p end end
    return nil
end

-- P2: a look a preset may write -- valid, the time on and the line on.
function Store.PresetOK(look)
    if type(look) ~= "table" then return false, "not a look" end
    if look.line ~= true then return false, "a preset may not turn off the 5SR line" end
    if not (type(look.texts) == "table" and type(look.texts.time) == "table" and look.texts.time.on == true) then
        return false, "a preset may not turn off the time"
    end
    local ok, why = Store.Valid(look)
    if not ok then return false, why end
    return true
end

--------------------------------------------------------------------------------
-- The store: db.clockLook, written only here
--------------------------------------------------------------------------------
local migrated = false
local migrationNotes, migratedFrom = nil, nil
local undo = nil -- session only: the look before the last preset

local function Changed()
    ST:Fire("CLOCK_LOOK")
end

-- Store.MigrateStored(force) -> changed, notes: db.clockLook rewritten as v3
-- (a new table holding only v3 fields), once a session unless `force`; the
-- notes kept for the dump line. T145b: called by the tests only.
function Store.MigrateStored(force)
    if migrated and not force then return false, migrationNotes or {} end
    local db = ST.db
    if type(db) ~= "table" then return false, {} end
    migrated = true
    local look, notes, from = Store.Migrate(db.clockLook)
    db.clockLook = look
    migrationNotes, migratedFrom = notes, from
    ST:AddDumpLine("clock", Store.DumpLine)
    return true, notes
end

-- The stored v3 table, made v3 and valid first (one write before the
-- caller's own, no event: the caller fires the one CLOCK_LOOK).
local function Stored()
    local db = ST.db
    if type(db) ~= "table" then return nil end
    local raw = db.clockLook
    if type(raw) ~= "table" or raw.v ~= Store.VERSION then
        Store.MigrateStored(true)
    else
        local look, notes = Store.Normalize(raw)
        if #notes > 0 then db.clockLook = look end
    end
    return db.clockLook
end

-- Store.Look() -> a validated, dense copy of the stored look (an older store
-- read through Migrate on the copy; nothing written).
function Store.Look()
    local db = ST.db
    local raw = type(db) == "table" and db.clockLook or nil
    local look = Store.Migrate(raw)
    return look
end

-- Store.Get(path) -> one field of Look(): "width", "texts.mana.size".
function Store.Get(path)
    if type(path) ~= "string" then return nil end
    return Copy(Get(Store.Look(), path))
end

-- Store.SetText(kind, field, value) -> true | false, why.
function Store.SetText(kind, field, value)
    if not KIND_INDEX[kind] then return false, "not a clock text: " .. tostring(kind) end
    local ok = Store.TEXT_OK[field]
    if not ok then return false, "not a text field: " .. tostring(field) end
    if not ok(value) then return false, "texts." .. kind .. "." .. field .. ": not accepted: " .. Say(value) end
    local s = Stored()
    if not s then return false, "no saved variables yet" end
    s.texts[kind][field] = value
    undo = nil
    Changed()
    return true
end

-- Store.Set(key, value) -> true | false, why. A bar field ("width") or a
-- text's ("texts.mana.size").
function Store.Set(key, value)
    if type(key) ~= "string" then return false, "not a clock look setting: " .. tostring(key) end
    local kind, field = key:match("^texts%.([^.]+)%.([^.]+)$")
    if kind then return Store.SetText(kind, field, value) end
    local ok = Store.OK[key]
    if not ok then return false, "not a clock look setting: " .. key end
    if not ok(value) then return false, key .. ": not accepted: " .. Say(value) end
    local s = Stored()
    if not s then return false, "no saved variables yet" end
    s[key] = value
    undo = nil
    Changed()
    return true
end

-- Store.ApplyPreset(key, opts) -> true | false, why. The whole look replaced,
-- the previous one kept for Undo (this session). opts.fill: a host's colour
-- for a preset that takes one (EllesmereUI's mana colour), six hex digits.
function Store.ApplyPreset(key, opts)
    local p = Store.Preset(key)
    if not p then return false, "no such preset: " .. tostring(key) end
    local look = Copy(p.look)
    if p.hostFill and type(opts) == "table" and Hex(opts.fill) then look.fill = opts.fill:upper() end
    local ok, why = Store.PresetOK(look)
    if not ok then return false, why end
    local s = Stored()
    if not s then return false, "no saved variables yet" end
    undo = Copy(s)
    ST.db.clockLook = look
    Changed()
    return true
end

-- Store.HasUndo() -> true while a preset's previous look is held.
function Store.HasUndo() return undo ~= nil end

-- Store.Undo() -> true | false, why: the look before the last preset back.
function Store.Undo()
    if undo == nil then return false, "nothing to undo" end
    if type(ST.db) ~= "table" then return false, "no saved variables yet" end
    ST.db.clockLook = undo
    undo = nil
    Changed()
    return true
end

-- Store.Reset() -> true: the defaults (the SpellTuner preset), no undo kept.
function Store.Reset()
    if type(ST.db) ~= "table" then return false, "no saved variables yet" end
    ST.db.clockLook = Copy(Store.DEFAULTS)
    undo = nil
    Changed()
    return true
end

--------------------------------------------------------------------------------
-- The dump line
--------------------------------------------------------------------------------
-- The fields that differ from the defaults, as dotted keys in schema order.
function Store.Differs(look)
    local out = {}
    look = type(look) == "table" and look or Store.Look()
    for _, f in ipairs(Store.FIELDS) do
        if look[f] ~= Store.DEFAULTS[f] then out[#out + 1] = f end
    end
    for _, kind in ipairs(Store.KINDS) do
        for _, f in ipairs(Store.TEXT_FIELDS) do
            if look.texts[kind][f] ~= Store.DEFAULTS.texts[kind][f] then out[#out + 1] = "texts." .. kind .. "." .. f end
        end
    end
    return out
end

-- `clock: v3, 2 fields set (width, texts.mana.size); migrated from v2: <notes>`
-- ASCII, one line (ST:AddDumpLine escapes it again).
function Store.DumpLine()
    local keys = Store.Differs()
    local line = string.format("clock: v3, %d field%s set%s", #keys, #keys == 1 and "" or "s",
        #keys > 0 and (" (" .. table.concat(keys, ", ") .. ")") or "")
    if migratedFrom and migratedFrom ~= "v3" then
        local notes = migrationNotes or {}
        line = line .. string.format("; migrated from %s, %d note%s%s", migratedFrom, #notes,
            #notes == 1 and "" or "s", #notes > 0 and (": " .. table.concat(notes, "; ")) or "")
    end
    return line
end

-- The notes of this session's migration (a copy), and where it came from.
function Store.MigrationNotes()
    return Copy(migrationNotes or {}), migratedFrom
end
