-- Spells/WhatIf.lua (T122, docs/SPEC-one-ui.md 4, docs/tasks/T122-what-if.md;
-- mockup M2): the What if's session values and the arithmetic both lines
-- share. Every main TOC.
--
-- "What would this change for my ranks?" -- a gear swap, a talent or form, a
-- long fight. A lens on the Spells pane ONLY: the clock, the advisor, the
-- tooltip block, the kit, the coach and practice keep the live numbers, and
-- nothing here is saved (not in db or cdb; a /reload clears it).
--
-- MD.WhatIf:
--   WI.STATS               the STATS rows, in order (both lines)
--   WI:Get(key) / Set(key, v)
--                          v nil, "" or "live" clears; a number is clamped
--                          to >= 0 (crit 0..100, a class row to its own
--                          min..max); WHATIF_CHANGED fires through MD:Fire
--                          only when the value moved (Set answers false on
--                          an equal write)
--   WI:Clear()             every key, one WHATIF_CHANGED (none when nothing
--                          was set)
--   WI:Active() / Values() any key set / a copy
--   WI:Summary()           "+150 healing, +500 mana" -- the RANKS note
--   WI:Delta(key)          "+150" beside a typed box, "" for none
--   WI.serial              bumped by every change (the pane's signature)
--   WI.provider            the line's (Spells/WhatIf_TBC.lua,
--                          Spells/WhatIf_Forever.lua): Live(), Book(),
--                          Pool(livePool), classRows, classTitle, classNote,
--                          ranksNote(fam) -- each a value or a function
--   WI:Live() / Book() / Pool(livePool) / ClassRows() / ClassTitle() /
--   ClassNote()            the provider's answers, nil without one
--   WI.Changes(liveFam, whatFam)   the pane's footer, pure
--   WI.Diff(a, b, aCasts, bCasts)  the cells that changed, pure
local _, MD = ...

local WI = MD.WhatIf or {}
MD.WhatIf = WI

WI.STATS = {
    { key = "heal",    label = "+Healing",            step = 25,  bigStep = 100 },
    { key = "crit",    label = "Crit %",              decimals = 1, max = 100 },
    { key = "mana",    label = "Mana",                step = 250, bigStep = 1000 },
    { key = "casting", label = "Regen while casting", unit = "mp5" },
    { key = "base",    label = "Regen resting",       unit = "mp5" },
}
local STAT_BY = {}
for _, s in ipairs(WI.STATS) do STAT_BY[s.key] = s end
WI.STAT_BY = STAT_BY

local values = {}
WI.serial = WI.serial or 0

local function Num(v, decimals)
    if MD.Words then return MD.Words.Num(v, decimals) end
    if type(v) ~= "number" or v ~= v then return "-" end
    if decimals then return string.format("%." .. decimals .. "f", v) end
    return tostring(math.floor(v + 0.5))
end

local function Call(field, ...)
    local p = WI.provider
    if type(p) ~= "table" then return nil end
    local v = p[field]
    if type(v) == "function" then return v(...) end
    return v
end

-- The provider's class rows, or nil.
function WI:ClassRows()
    local rows = Call("classRows")
    if type(rows) == "table" and #rows > 0 then return rows end
    return nil
end
function WI:ClassTitle()
    if not WI:ClassRows() then return nil end
    local t = Call("classTitle")
    return (type(t) == "string" and t ~= "") and t or nil
end
function WI:ClassNote()
    local t = Call("classNote")
    return (type(t) == "string" and t ~= "") and t or nil
end

local function ClassRow(key)
    for _, r in ipairs(WI:ClassRows() or {}) do
        if r.key == key then return r end
    end
    return nil
end

-- The value a key may hold, or nil (cleared), or false (refused).
local function Clean(key, v)
    if v == nil or v == "" or v == "live" then return nil end
    local stat = STAT_BY[key]
    if stat then
        v = tonumber(v)
        if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return false end
        if v < 0 then v = 0 end
        if stat.max and v > stat.max then v = stat.max end
        return v
    end
    local row = ClassRow(key)
    if not row then return false end
    if row.kind == "choice" then
        for _, c in ipairs(row.choices or {}) do
            if c.id == v then return v end
        end
        return false
    end
    v = tonumber(v)
    if type(v) ~= "number" or v ~= v then return false end
    v = math.floor(v)
    if type(row.min) == "number" and v < row.min then v = row.min end
    if type(row.max) == "number" and v > row.max then v = row.max end
    return v
end

local function Changed()
    WI.serial = WI.serial + 1
    MD:Fire("WHATIF_CHANGED")
end

function WI:Get(key)
    return values[key]
end

-- true when the value moved, false on an equal write or a value refused.
function WI:Set(key, v)
    local clean = Clean(key, v)
    if clean == false then return false end
    if values[key] == clean then return false end
    values[key] = clean
    Changed()
    return true
end

function WI:Clear()
    if next(values) == nil then return false end
    wipe(values)
    Changed()
    return true
end

function WI:Active()
    return next(values) ~= nil
end

function WI:Values()
    local out = {}
    for k, v in pairs(values) do out[k] = v end
    return out
end

function WI:Live()
    local live = Call("Live")
    return (type(live) == "table") and live or {}
end

function WI:Book()
    return Call("Book")
end

-- The pool the what-if counts casts from: the typed Mana and casting regen
-- (mp5) over the live pool's.
function WI:Pool(livePool)
    livePool = (type(livePool) == "table") and livePool or {}
    local custom = Call("Pool", livePool)
    if type(custom) == "table" then return custom end
    local mana, casting = values.mana, values.casting
    return {
        max = mana or livePool.max,
        mana = mana or livePool.mana,
        regenCasting = casting and (casting / 5) or livePool.regenCasting,
        modelled = livePool.modelled and mana == nil,
    }
end

-- "+150", "-200", "" -- a typed value against its live one.
function WI:Delta(key)
    local v = values[key]
    if type(v) ~= "number" then return "" end
    local live = WI:Live()[key]
    if type(live) ~= "number" then return "" end
    local stat = STAT_BY[key]
    local d = v - live
    local text = Num(math.abs(d), stat and stat.decimals or nil)
    if text == Num(0, stat and stat.decimals or nil) then return "0" end
    return ((d > 0) and "+" or "-") .. text
end

local SUMMARY = {
    heal = function(v) return "healing" end,
    mana = function(v) return "mana" end,
}

-- "+150 healing, 30% crit, +500 mana, 142 mp5 casting, 346 mp5 resting,
-- Tree of Life, Moonglow 2" -- only the keys set, in the rows' order.
function WI:Summary()
    local out = {}
    local live = WI:Live()
    for _, s in ipairs(WI.STATS) do
        local v = values[s.key]
        if type(v) == "number" then
            if s.key == "heal" or s.key == "mana" then
                local word = SUMMARY[s.key](v)
                if type(live[s.key]) == "number" then
                    local d = WI:Delta(s.key)
                    out[#out + 1] = d .. " " .. word
                else
                    out[#out + 1] = Num(v) .. " " .. word
                end
            elseif s.key == "crit" then
                out[#out + 1] = Num(v) .. "% crit"
            elseif s.key == "casting" then
                out[#out + 1] = Num(v) .. " mp5 casting"
            elseif s.key == "base" then
                out[#out + 1] = Num(v) .. " mp5 resting"
            end
        end
    end
    for _, r in ipairs(WI:ClassRows() or {}) do
        local v = values[r.key]
        if v ~= nil then
            if r.kind == "choice" then
                for _, c in ipairs(r.choices or {}) do
                    if c.id == v then out[#out + 1] = c.text end
                end
            else
                out[#out + 1] = (r.label or r.key) .. " " .. tostring(v)
            end
        end
    end
    return table.concat(out, ", ")
end

--------------------------------------------------------------------------------
-- The shared arithmetic (pure)
--------------------------------------------------------------------------------

-- The cells a row shows, as the pane rounds them (Spells/Words.lua's cell
-- words), so a change below the shown digit is not drawn as one.
local function CellWords(e, casts)
    local W = MD.Words
    local out = {
        value = Num(e.value),
        perMana = Num(e.perMana, 2),
        perSec = Num(e.perSec, 1),
        casts = (casts == math.huge) and "inf" or Num(casts, 0),
    }
    if W then
        out.cost = W.Cost(e, "cell")
        out.cast = W.Cast(e, "cell")
    else
        out.cost = Num(e.cost and e.cost.amount)
        out.cast = Num(e.cast, 1)
    end
    return out
end
WI.CellWords = CellWords

-- { field = true } for every cell that changed between the live entry `a`
-- and the what-if entry `b` (value, perMana, perSec, casts, cost, cast).
function WI.Diff(a, b, aCasts, bCasts)
    local out = {}
    if type(a) ~= "table" or type(b) ~= "table" then return out end
    local x, y = CellWords(a, aCasts), CellWords(b, bCasts)
    for k, v in pairs(x) do
        if y[k] ~= v then out[k] = true end
    end
    return out
end

local function ById(fam, id)
    for _, e in ipairs(fam and fam.ranks or {}) do
        if e.id == id then return e end
    end
    return nil
end

-- The footer: "Suggested: Rank 12 -> Rank 6." when the suggestion moved,
-- else "No change to the suggestion.", then the live suggested rank's per
-- mana when its shown number moved: " Rank 12 per mana 6.09 -> 6.41 (+5%)."
function WI.Changes(liveFam, whatFam)
    if type(liveFam) ~= "table" or type(whatFam) ~= "table" then return "No change to the suggestion." end
    local ls, ws = liveFam.suggested, whatFam.suggested
    local text
    if ls and ws and ls.id ~= ws.id then
        text = "Suggested: Rank " .. tostring(ls.rank or "-") .. " -> Rank " .. tostring(ws.rank or "-") .. "."
    else
        text = "No change to the suggestion."
    end
    if ls then
        local w = ById(whatFam, ls.id)
        local a, b = ls.perMana, w and w.perMana
        if type(a) == "number" and type(b) == "number" and Num(a, 2) ~= Num(b, 2) then
            local pct = (a > 0) and ((b / a - 1) * 100) or nil
            local signed = (MD.Words and pct) and MD.Words.Signed(pct) or nil
            text = text .. " Rank " .. tostring(ls.rank or "-") .. " per mana " .. Num(a, 2) .. " -> " .. Num(b, 2)
                .. (signed and (" (" .. signed .. ")") or "") .. "."
        end
    end
    return text
end
