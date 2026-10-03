-- T117 (docs/SPEC-one-ui.md 3.1; docs/tasks/T117-book-contract.md): the book
-- contract, the way Engine/Kit.lua holds the kit's. Both lines' books -- the
-- Forever spellbook (Spells/Book.lua) and, from T118, TBC's -- answer the
-- same questions in the same shape, so the Spells pane and the tooltip block
-- can be one file each (T120 / T121). This file writes the shape down:
--
--   BS.TOP      the table Book:Get() returns
--   BS.FAMILY   a family (book.families[key])
--   BS.ENTRY    an entry (book.spells[id], a family's ranks, a Half's copies)
--   BS.VARIANT  a row hanging off a rank (TBC's Lifebloom rolled x2 / x3)
--   BS.METHODS  the methods every book has
--
-- A field type is a type name ("number", "string", "boolean", "table") or
-- several joined by "|" ("number|string"); a field marked `required` must be
-- present. A field not declared is a problem: the list is complete by
-- construction (tools/bookshapecheck.lua fails on an undeclared one).
--
-- BS.Validate(book) -> true | false, problems (ASCII strings, each naming the
-- family key or spell id and the field); BS.Check(book, who) raises with
-- `who` and the first five problems; BS.CheckMethods(Book, who) raises
-- naming a missing method.
--
-- Pure: Lua's library only. No client call, no MD.db, no frame. Every main
-- TOC (TBC after Spells/Book_TBC.lua, Forever before Spells/Book.lua).
local _, MD = ...

MD.BookShape = MD.BookShape or {}
local BS = MD.BookShape

local function R(t) return { type = t, required = true } end
local function O(t) return { type = t } end

-- What Book:Get() returns. `read` is Forever's walk counts (via, slots,
-- spells, secret, errors); TBC's book has none.
BS.TOP = {
    families   = R("table"),
    order      = R("table"),
    spells     = R("table"),
    read       = O("table"),
    generation = R("number"),
}

-- A family. `shape`: "direct", "hot", "hybrid", "none", and for TBC
-- "bloom" (Lifebloom) and "channel" (Tranquility, Hurricane). `kind` nil is
-- Other. `half` / `of` are on a Book:Half view only (the damage half of an
-- either-or heal family, `of` the family it came from).
BS.FAMILY = {
    key       = R("string"),
    name      = R("string"),
    kind      = O("string"),
    altKind   = O("string"),
    shape     = O("string"),
    ranks     = R("table"),
    ids       = R("table"),
    maxKnown  = O("table"),
    suggested = O("table"),
    gaps      = O("table"),
    school    = O("string"),
    noSeed    = O("boolean"),
    half      = O("string"),
    of        = O("table"),
}

BS.SHAPES = { direct = true, hot = true, hybrid = true, bloom = true, channel = true, none = true }

-- An entry: every field Spells/Book.lua writes (BuildEntry, Numbers, Rows,
-- DamageHalf, ReadSpell), then the five the contract adds.
BS.ENTRY = {
    -- BuildEntry / ReadSpell
    id           = R("number"),
    slot         = O("number"),
    passive      = O("boolean"),
    skillLine    = O("number"),
    name         = O("string"),
    rankText     = O("string"),
    rank         = O("number"),
    known        = O("boolean"),
    lowRank      = O("boolean"),
    desc         = O("string"),
    parsed       = O("table"),
    descState    = O("string"),
    stale        = O("boolean"),
    level        = O("number"),
    icon         = O("number|string"),
    cast         = O("number"),
    castKind     = O("string"),
    cost         = O("table"),
    costState    = O("string"),
    cooldown     = O("number"),
    cooldownFrom = O("string"),
    targets      = O("string"),
    reach        = O("table"),
    targetsWhy   = O("string"),
    lockout      = O("number"),
    kind         = O("string"),   -- ReadSpell's own entries and a Half's copies
    -- Numbers
    value        = O("number"),
    min          = O("number"),
    max          = O("number"),
    over         = O("number"),
    dur          = O("number"),
    interval     = O("number"),
    intervalBy   = O("string"),
    perMana      = O("number"),
    perSec       = O("number"),
    alt          = O("table"),
    -- Rows
    casts        = O("number"),
    suggested    = O("boolean"),
    dominated    = O("boolean"),
    dominatedBy  = O("number"),
    -- DamageHalf
    half         = O("string"),
    of           = O("table"),
    -- T117: the contract's own
    family        = R("string"),
    variants      = O("table"),
    bonus         = O("table"),
    calc          = O("table"),
    afterOverheal = O("table"),
    -- T118 (docs/tasks/T118-tbc-book.md): the crit chance `value` averages
    -- in (TBC's rows; nil: no crit in it), what the cast time assumes
    -- ("Nature's Grace averaged"), a damage entry's school name
    crit          = O("number"),
    castNote      = O("string"),
    school        = O("string"),
}

-- A row a rank draws under it, never a rank of its own: not in `spells`,
-- not in `ids`, not in Pareto, not in CastsFor.
BS.VARIANT = {
    variant       = R("number"),
    variantLabel  = R("string"),
    value         = O("number"),
    perMana       = O("number"),
    perSec        = O("number"),
    casts         = O("number"),
    cost          = O("table|number"),
    cast          = O("number"),
    afterOverheal = O("table"),
}

-- entry.bonus: the share of +healing (or +damage) the rank gets.
BS.BONUS = {
    counts = R("number"),
    from   = R("string"),
    amount = O("number"),
    of     = O("number"),
    why    = O("string"),
    at     = O("number"),
}
BS.BONUS_FROM = { model = true, measured = true, estimated = true }

-- entry.afterOverheal: the numbers after the measured overheal.
BS.AFTER_OVERHEAL = {
    value   = O("number"),
    perMana = O("number"),
    perSec  = O("number"),
    frac    = O("number"),
    scope   = O("string"),
}
BS.SCOPES = { rank = true, family = true, kind = true }

-- The methods every book has (GCD is a number, the rest functions).
BS.METHODS = { "Get", "Entry", "ReadSpell", "Rows", "CastsFor", "Compare", "DefaultPool",
               "Half", "HalfOf", "GCD", "IntervalFor", "Pool", "Bonus" }
BS.METHOD_TYPES = { GCD = "number" }

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

local function TypeOK(v, want)
    local t = type(v)
    for name in string.gmatch(want, "[^|]+") do
        if t == name then
            if t == "number" and (v ~= v or v == math.huge or v == -math.huge) then
                -- casts to OOM is inf when regen keeps up (RankRules.CastsToOOM)
                return v == math.huge
            end
            return true
        end
    end
    return false
end

local function Ascii(s)
    return type(s) == "string" and not s:find("[^\32-\126]") and not s:find("|", 1, true)
end

local function Fields(where, t, schema, problems, extra)
    for k, v in pairs(t) do
        local f = schema[k]
        if not f and extra and extra[k] then
            -- a field the book's own talent seam added (Spells/Book.lua's
            -- Book.adjust): the seam's, not the contract's
        elseif not f then
            problems[#problems + 1] = where .. ": undeclared field " .. tostring(k)
        elseif not TypeOK(v, f.type) then
            problems[#problems + 1] = string.format("%s: field %s is %s, want %s", where, tostring(k), type(v), f.type)
        end
    end
    for k, f in pairs(schema) do
        if f.required and t[k] == nil then
            problems[#problems + 1] = where .. ": missing field " .. k
        end
    end
end

local function Entry(where, e, families, problems, extra)
    Fields(where, e, BS.ENTRY, problems, extra)
    if type(e.family) == "string" and type(families) == "table" and families[e.family] == nil then
        problems[#problems + 1] = where .. ": field family names no family (" .. e.family .. ")"
    end
    if type(e.bonus) == "table" then
        Fields(where .. " bonus", e.bonus, BS.BONUS, problems)
        if e.bonus.from ~= nil and not BS.BONUS_FROM[e.bonus.from] then
            problems[#problems + 1] = where .. ": field bonus.from is " .. tostring(e.bonus.from)
        end
        if e.bonus.why ~= nil and not Ascii(e.bonus.why) then
            problems[#problems + 1] = where .. ": field bonus.why is not plain ASCII"
        end
    end
    if type(e.calc) == "table" then
        for i, line in ipairs(e.calc) do
            if not Ascii(line) then
                problems[#problems + 1] = where .. ": field calc[" .. i .. "] is not plain ASCII"
            end
        end
    end
    if type(e.afterOverheal) == "table" then
        Fields(where .. " afterOverheal", e.afterOverheal, BS.AFTER_OVERHEAL, problems)
        local s = e.afterOverheal.scope
        if s ~= nil and not BS.SCOPES[s] then
            problems[#problems + 1] = where .. ": field afterOverheal.scope is " .. tostring(s)
        end
    end
    if type(e.variants) == "table" then
        for i, row in ipairs(e.variants) do
            if type(row) ~= "table" then
                problems[#problems + 1] = where .. ": field variants[" .. i .. "] is not a table"
            else
                Fields(where .. " variants[" .. i .. "]", row, BS.VARIANT, problems)
            end
        end
    end
end

-- `extra` (optional): entry field names to let pass whatever they hold -- the
-- fields a book's talent seam added this scan (Spells/Book.lua passes its
-- Book._seamFields). Never declared here: a seam adds to an entry, the
-- contract stays what every reader may rely on.
function BS.Validate(book, extra)
    local problems = {}
    if type(book) ~= "table" then return false, { "the book is not a table" } end
    Fields("book", book, BS.TOP, problems)
    local families, spells, order = book.families, book.spells, book.order
    if type(families) ~= "table" or type(spells) ~= "table" or type(order) ~= "table" then
        return false, problems
    end

    -- every variant row, by identity: none of them may be in spells
    local variantRows = {}
    for id, e in pairs(spells) do
        if type(e) == "table" and type(e.variants) == "table" then
            for _, row in ipairs(e.variants) do
                if type(row) == "table" then variantRows[row] = id end
            end
        end
    end

    for id, e in pairs(spells) do
        local where = "spell " .. tostring(id)
        if type(e) ~= "table" then
            problems[#problems + 1] = where .. ": not a table"
        elseif variantRows[e] then
            problems[#problems + 1] = where .. ": a variant row of spell " .. tostring(variantRows[e])
                .. " is in spells (field variant)"
        else
            if e.id ~= id then
                problems[#problems + 1] = where .. ": field id is " .. tostring(e.id)
            end
            Entry(where, e, families, problems, extra)
        end
    end

    local listed = {}
    for i, key in ipairs(order) do
        if listed[key] then
            problems[#problems + 1] = "order: family " .. tostring(key) .. " listed twice"
        elseif families[key] == nil then
            problems[#problems + 1] = "order[" .. i .. "]: " .. tostring(key) .. " is no family"
        end
        listed[key] = true
    end

    for key, fam in pairs(families) do
        local where = "family " .. tostring(key)
        if type(fam) ~= "table" then
            problems[#problems + 1] = where .. ": not a table"
        else
            if not listed[key] then problems[#problems + 1] = where .. ": not in order" end
            Fields(where, fam, BS.FAMILY, problems)
            if fam.key ~= key then
                problems[#problems + 1] = where .. ": field key is " .. tostring(fam.key)
            end
            if fam.shape ~= nil and not BS.SHAPES[fam.shape] then
                problems[#problems + 1] = where .. ": field shape is " .. tostring(fam.shape)
            end
            if type(fam.ids) == "table" then
                for _, id in ipairs(fam.ids) do
                    if spells[id] == nil then
                        problems[#problems + 1] = where .. ": field ids lists " .. tostring(id)
                            .. ", which is not in spells"
                    end
                end
            end
            if type(fam.ranks) == "table" and fam.half == nil then
                for i, e in ipairs(fam.ranks) do
                    if type(e) ~= "table" then
                        problems[#problems + 1] = where .. ": field ranks[" .. i .. "] is not a table"
                    elseif e.family ~= key then
                        problems[#problems + 1] = where .. ": spell " .. tostring(e.id)
                            .. " field family is " .. tostring(e.family)
                    end
                end
            end
        end
    end

    if #problems > 0 then return false, problems end
    return true
end

function BS.Check(book, who, extra)
    local ok, problems = BS.Validate(book, extra)
    if ok then return true end
    local shown = {}
    for i = 1, math.min(5, #problems) do shown[i] = problems[i] end
    local more = (#problems > 5) and string.format(" (and %d more)", #problems - 5) or ""
    error(string.format("%s: the book does not keep its contract: %s%s",
        tostring(who or "?"), table.concat(shown, "; "), more), 2)
end

function BS.CheckMethods(Book, who)
    local missing = {}
    for _, name in ipairs(BS.METHODS) do
        local want = BS.METHOD_TYPES[name] or "function"
        if type(Book) ~= "table" or type(Book[name]) ~= want then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        error(string.format("%s: the book lacks %s", tostring(who or "?"), table.concat(missing, ", ")), 2)
    end
    return true
end
