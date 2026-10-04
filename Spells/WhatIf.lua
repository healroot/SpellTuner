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
    { key = "damage",  label = "+Spell damage",       step = 25,  bigStep = 100 },
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
    damage = function(v) return "spell damage" end,
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
            if s.key == "heal" or s.key == "damage" or s.key == "mana" then
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

-- T124: the school +Spell damage reads live -- the damage family on screen
-- (MD.SpellsPane's family view, a preview included), else the book's first damage
-- family in its order; nil when the book has none. A school is a name
-- ("Nature") or an id; both books' Bonus("damage", school) take either.
function WI.DamageSchool(book)
    if type(book) ~= "table" or type(book.families) ~= "table" then return nil end
    local P = MD.SpellsPane
    local f = P and P.family    if type(f) == "table" and f.key ~= nil and (not f.IsShown or f:IsShown()) then
        local fam = book.families[f.key]
        if type(fam) == "table" and fam.kind == "damage" and fam.school ~= nil then return fam.school end
    end
    for _, key in ipairs(book.order or {}) do
        local fam = book.families[key]
        if type(fam) == "table" and fam.kind == "damage" and fam.school ~= nil then return fam.school end
    end
    return nil
end

-- T124: the live +Spell damage of WI.DamageSchool's school, through the
-- line's Book:Bonus; nil when there is no damage family or no reading.
function WI.LiveDamage(Book)
    if not (Book and Book.Get and Book.Bonus) then return nil end
    local school = WI.DamageSchool(Book:Get())
    if school == nil then return nil end
    local v = Book:Bonus("damage", school)    if type(v) == "number" then return v end
    return nil
end

local function ById(fam, id)
    for _, e in ipairs(fam and fam.ranks or {}) do
        if e.id == id then return e end
    end
    return nil
end

-- The footer (T124: like with like). When the suggestion moved: "Suggested:
-- Rank 12 -> Rank 6. With these stats Rank 6 gives 7.40 per mana, Rank 12
-- 6.83 (+8%)." -- both numbers the what-if book's; `liveFam` gives only which
-- rank was suggested live. When the new rank gives less per mana, the reason
-- follows (beaten, else under the floor). Else "No change to the suggestion."
function WI.Changes(liveFam, whatFam)
    local same = "No change to the suggestion."
    if type(liveFam) ~= "table" or type(whatFam) ~= "table" then return same end
    local ls, ws = liveFam.suggested, whatFam.suggested
    if not ls or not ws or ls.id == ws.id then return same end
    local old = ById(whatFam, ls.id)
    local new = ById(whatFam, ws.id) or ws
    if not old then
        return "Suggested: Rank " .. tostring(ls.rank or "-") .. " -> Rank " .. tostring(ws.rank or "-") .. "."
    end
    local beaten
    if old.dominatedBy ~= nil then
        local b = ById(whatFam, old.dominatedBy)
        if b then beaten = b.rank end
    end
    local top = whatFam.maxKnown and whatFam.maxKnown.rank
    local kind = (whatFam.kind == "damage") and "damage" or "heal"
    if MD.Words and MD.Words.SuggestionMoved then
        return MD.Words.SuggestionMoved(old, new, beaten, top, kind)
    end
    return "Suggested: Rank " .. tostring(old.rank or "-") .. " -> Rank " .. tostring(new.rank or "-") .. "."
end
