-- T111 (docs/SPEC-next.md 4.2 P5, decision 8 (b)): a TBC priest's, shaman's
-- or paladin's healing ranks, read from the client -- the source the TBC rank
-- table and the spell tooltip read for a class Data/SpellData.lua does not
-- cover (that table is the druid's and stays the druid's source).
--
-- No number is typed in here. The spellbook is walked through MD.API
-- (Client/API_TBC.lua); each rank's own description is read by Spells/Parse.lua
-- (the TBC client prints every rank's base heal in its tooltip, without the
-- player's +healing or talents), its cost and cast time from the client (both
-- already carry the player's talents), its learn level from the client, its
-- cooldown from the client or its tooltip's own line. Every read falls back to
-- the spell's tooltip lines (MD.API.SpellTooltipLines) and a rank no read can
-- price is REFUSED with its reason (`source.refused[id]`), never guessed --
-- a rank with no description, no heal of its family's shape, no cast time or
-- no learn level.
--
-- The rules on top -- coefficients by shape, the downrank penalty, the class
-- talents -- are Engine/RankMath.lua's (RankMath.CLASS_RULES); this file only
-- reads. The shape a family is read as is the class profile's kit type
-- (Data/Profile_<Class>_TBC.lua): a direct, group, chain or selfAndTarget
-- family needs a heal range, a hot family an amount over a duration, and
-- Holy Shock's either-or sentence gives its heal half.
--
-- The source has Data/SpellData.lua's shape (families, familyOrder, spells,
-- all, known, knownSet, maxRank, GetCost, StaticCost, Relic, Resolve, and --
-- T123 -- LiveCost, IsMaxKnownRank), so the
-- rank math and the TBC book (Spells/Book_Model.lua) read either one the
-- same way. Only the
-- ranks the spellbook lists are in it (TBC's book lists every rank the player
-- knows; an untrained rank is not listed and so not on the table).
--
-- Built at MD_READY and whenever the spellbook or the level changes, for a
-- logged-in class whose profile grants the rank table and is not the class
-- Data/SpellData.lua is written for; SPELLS_REBUILT is fired after each build
-- so the TBC book (Spells/Book_Model.lua) and the spell list follow.
--
-- T118: B.WalkAll() (every spell of the book) and B.Read(id) (one rank's
-- text and reads) are every caller's, cached until SPELLS_CHANGED /
-- LEARNED_SPELL_IN_TAB or the next build. T123: the priest's, shaman's and
-- paladin's TBC profiles grant the rank table, so a logged-in priest, shaman
-- or paladin builds here (the spend tracker, the fight summary and /md
-- profile read it through RankMath:Source() as the rank math does). TBC TOC
-- only, after Spells/Parse.lua.
local _, MD = ...

local B = {}
MD.BookTBC = B

-- Data/SpellData.lua's class: that class reads the static table, never this.
B.TABLE_CLASS = "DRUID"

B._src = nil

--------------------------------------------------------------------------------
-- The client, through the adapter only.
--------------------------------------------------------------------------------
local function Call(name, ...)
    local fn = MD.API and MD.API[name]
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

local function Lines(id)
    local lines = Call("SpellTooltipLines", id)
    if type(lines) ~= "table" then return nil end
    return lines
end

--------------------------------------------------------------------------------
-- TBC's own reach sentences. Spells/Parse.lua's Parse.Targets reads Forever's
-- wording; where it refuses, these read the TBC tooltips' (the fixture in
-- tools/tbcclasscheck.lua). Words only: the numbers are the text's.
--   Chain Heal  "... Each jump reduces the effectiveness of the heal by 50%.
--                Heals 3 total targets."
--   Prayer of Healing  "... heals party members within 30 yards ..."
--   Circle of Healing  "... that target's party members within 15 yards of the
--                target ..."
--------------------------------------------------------------------------------
local function Reach(text)
    local P = MD.Parse
    local t = (P and P.Clean) and P.Clean(text) or text
    local total = tonumber(t:match("[Hh]eals (%d+) total targets"))
    local cut = tonumber(t:match("reduces the effectiveness of the heal by (%d+)%%"))
    if total and cut and total >= 1 and cut >= 0 and cut < 100 then
        return { targets = "chain", count = total, jumps = total - 1, falloff = 1 - cut / 100 }
    end
    local around = tonumber(t:match("that target's party members within (%d+) yards"))
    if around then return { targets = "party", from = "target", range = around } end
    local yards = tonumber(t:match("party members within (%d+) yards"))
    if yards then return { targets = "party", from = "caster", range = yards } end
    if P and P.Targets then
        local r = P.Targets(t)
        if type(r) == "table" then return r end
    end
    return nil
end
B.Reach = Reach

--------------------------------------------------------------------------------
-- One rank's reads.
--------------------------------------------------------------------------------
local function DescriptionOf(id, lines)
    local P = MD.Parse
    local text = Call("SpellDescription", id)
    if type(text) == "string" and text ~= "" then
        local d = P.Description(text)
        if type(d) == "table" and d.heal then return text, d, "api" end
    end
    -- the tooltip's description is its last line that reads as one
    if lines then
        for i = #lines, 1, -1 do
            local l = lines[i].l
            if type(l) == "string" then
                local d = P.Description(l)
                if type(d) == "table" and d.heal then return l, d, "tooltip" end
            end
        end
    end
    return (type(text) == "string" and text ~= "") and text or nil, nil, nil
end

local function CostOf(id, lines)
    local list = Call("SpellPowerCost", id)
    if type(list) == "table" then
        for _, c in ipairs(list) do
            if type(c) == "table" and c.type == 0 and type(c.cost) == "number" then return c.cost, "api" end
        end
    end
    if lines then
        for _, ln in ipairs(lines) do
            for _, side in ipairs({ ln.l, ln.r }) do
                if type(side) == "string" then
                    local c = MD.Parse.Cost(side)
                    if type(c) == "table" and c.power == "Mana" and type(c.amount) == "number" then
                        return c.amount, "tooltip"
                    end
                end
            end
        end
    end
    return nil
end

local function CastOf(id, lines)
    local _, _, _, ms = Call("SpellInfoList", id)
    if type(ms) == "number" and ms >= 0 then return ms / 1000, "api" end
    if lines then
        for _, ln in ipairs(lines) do
            for _, side in ipairs({ ln.l, ln.r }) do
                if type(side) == "string" then
                    local s = MD.Parse.Cast(side)
                    if type(s) == "number" then return s, "tooltip" end
                end
            end
        end
    end
    return nil
end

local function LevelOf(id, lines)
    local lvl = Call("SpellLevelLearned", id)
    if type(lvl) == "number" and lvl > 0 then return lvl, "api" end
    if lines then
        for _, ln in ipairs(lines) do
            local n = type(ln.l) == "string" and tonumber(ln.l:match("^Requires [Ll]evel (%d+)"))
            if n then return n, "tooltip" end
        end
    end
    return nil
end

local function CooldownOf(id, lines)
    local ms = Call("BaseCooldown", id)
    if type(ms) == "number" and ms > 0 then return ms / 1000, "api" end
    if lines then
        for _, ln in ipairs(lines) do
            for _, side in ipairs({ ln.r, ln.l }) do
                if type(side) == "string" then
                    local s = MD.Parse.Cooldown(side)
                    if type(s) == "number" and s > 0 then return s, "tooltip" end
                end
            end
        end
    end
    return nil
end

-- What a profile kit type needs from the description; nil plus why it is
-- refused otherwise.
local NEEDS_RANGE = { direct = true, group = true, chain = true, selfAndTarget = true }
local function Shape(kitType, d, text)
    local h = d and d.heal
    if NEEDS_RANGE[kitType] then
        if type(h) == "table" and type(h.min) == "number" and type(h.max) == "number" and h.max >= h.min then
            return { healMin = h.min, healMax = h.max }
        end
        return nil, "no heal range in its text"
    elseif kitType == "hot" then
        if type(h) == "table" and type(h.over) == "number" and type(h.dur) == "number" and h.dur > 0 then
            return { hotTotal = h.over, hotDuration = h.dur }
        end
        return nil, "no amount over a duration in its text"
    end
    return nil, "kit type " .. tostring(kitType) .. " is not read on this line"
end

--------------------------------------------------------------------------------
-- T118 (docs/tasks/T118-tbc-book.md): one rank's text and reads, without the
-- family rules, for every caller -- the class book below and the TBC book
-- (Spells/Book_Model.lua), which reads every spell the walk lists.
--------------------------------------------------------------------------------

-- The lines a description is never: the rank's own header lines.
local function NotDescription(l)
    local P = MD.Parse
    if l:match("^Requires ") then return true end
    if type(P.Cost(l)) == "table" or type(P.Cast(l)) == "number" then return true end
    if type(P.Cooldown(l)) == "number" then return true end
    if l:match("yd range$") or l == "Instant" or l == "Channeled" then return true end
    return false
end

-- The heal's text (DescriptionOf's rule), else the client's description,
-- else the tooltip's last line from the second on that is not a header line.
local function TextOf(id, lines)
    local text, d = DescriptionOf(id, lines)
    if text then return text, d end
    if lines then
        for i = #lines, 2, -1 do
            local l = lines[i].l
            if type(l) == "string" and l ~= "" and not NotDescription(l) then return l, nil end
        end
    end
    return nil, nil
end

B._read = {}

--- B.Read(id) -> { desc, parsed (the heal's Parse.Description, when the text
--- heals), lines, cost, costFrom, cast, castFrom, level, levelFrom, cooldown,
--- targets, reach, targetsWhy, lockout }. Cached per id until B.Forget().
function B.Read(id)
    if type(id) ~= "number" then return nil end
    local hit = B._read[id]
    if hit then return hit end
    local P = MD.Parse
    local lines = Lines(id)
    local r = { lines = lines }
    if P then
        r.desc, r.parsed = TextOf(id, lines)
        r.cost, r.costFrom = CostOf(id, lines)
        r.cast, r.castFrom = CastOf(id, lines)
        r.level, r.levelFrom = LevelOf(id, lines)
        r.cooldown = CooldownOf(id, lines)
        local text = r.desc
        if type(text) == "string" and text ~= "" then
            r.lockout = P.Lockout(text)
            local d = P.Description(text)
            if type(d) == "table" and (d.heal ~= nil or d.absorb ~= nil) then
                local reach = Reach(text)
                if type(reach) == "table" then
                    r.targets, r.reach = reach.targets, reach
                else
                    local _, why = P.Targets(P.Clean and P.Clean(text) or text)
                    r.targetsWhy = type(why) == "string" and why or nil
                end
            end
        end
    end
    B._read[id] = r
    return r
end

--- B.Forget(): the reads and the walk forgotten (a trained rank is a new id;
--- the TBC text itself is static).
function B.Forget()
    B._read = {}
    B._walk = nil
end

--- B.ReadRank(id, family, def) -> spell row, or nil plus why. Public for the
--- suite; `def` is the profile's family definition.
function B.ReadRank(id, family, def, rankText)
    local read = B.Read(id)
    local lines = read.lines
    local text, d = read.desc, read.parsed
    if not text then return nil, "no description" end
    local s, why = Shape(def.kit, d, text)
    if not s then return nil, why end
    s.family = family
    s.text = text
    s.rank = (rankText and MD.Parse.Rank(rankText)) or nil
    if not s.rank and lines and lines[1] then
        s.rank = MD.Parse.Rank(lines[1].r or "") or nil
    end
    s.cost, s.costFrom = read.cost, read.costFrom
    s.cast, s.castFrom = read.cast, read.castFrom
    s.level, s.levelFrom = read.level, read.levelFrom
    s.cooldown = read.cooldown
    if s.cast == nil then return nil, "no cast time" end
    -- the downrank penalty needs the learn level, and the rank table prints it
    if s.level == nil then return nil, "no learn level" end
    if def.kit == "chain" or def.kit == "group" then
        local r = Reach(text)
        if def.kit == "chain" then
            if not (r and r.targets == "chain" and r.jumps and r.falloff) then
                return nil, "chain without its count or falloff"
            end
            s.count, s.jumps, s.falloff = r.count, r.jumps, r.falloff
        end
        s.reach = r
    end
    return s
end

--------------------------------------------------------------------------------
-- The walk.
--------------------------------------------------------------------------------
local function Profile()
    local p = MD.ClassProfile
    if type(p) ~= "table" or type(p.Can) ~= "function" then return nil end
    if p.class == B.TABLE_CLASS or not p:Can("rankTable") then return nil end
    if type(p.families) ~= "table" or next(p.families) == nil then return nil end
    return p
end

--- B.WalkAll() -> { { id, name, sub, slot, passive }, ... }: every spell of
--- every tab, in slot order (T118). `passive` from the adapter's
--- SpellIsPassive when a TOC binds it, else the rank text the client prints
--- for a passive ("Passive"). Cached until B.Forget().
B._walk = nil
function B.WalkAll()
    if B._walk then return B._walk end
    local found = {}
    local tabs = Call("SpellTabCount")
    if type(tabs) == "number" then
        for tab = 1, tabs do
            local _, _, offset, count = Call("SpellTabInfo", tab)
            if type(offset) == "number" and type(count) == "number" then
                for slot = offset + 1, offset + count do
                    local name, sub, id = Call("SpellBookItemName", slot, "spell")
                    if type(id) ~= "number" then
                        local kind, id2 = Call("SpellBookItemKind", slot, "spell")
                        if kind == "SPELL" and type(id2) == "number" then id = id2 end
                    end
                    if type(name) == "string" and type(id) == "number" then
                        sub = type(sub) == "string" and sub or nil
                        local passive = Call("SpellIsPassive", slot, "spell")
                        if type(passive) ~= "boolean" then
                            passive = (sub ~= nil and sub:find("Passive", 1, true) ~= nil) or nil
                        end
                        found[#found + 1] = { id = id, name = name, sub = sub, slot = slot, passive = passive }
                    end
                end
            end
        end
    end
    B._walk = found
    return found
end

-- { id, name, sub } of the spellbook's spells whose name the profile keys.
local function Walk(keyOf)
    local found = {}
    for _, hit in ipairs(B.WalkAll()) do
        if keyOf[hit.name] then found[#found + 1] = { id = hit.id, name = hit.name, sub = hit.sub } end
    end
    return found
end

local function Empty(p)
    return { class = p and p.class, families = {}, familyOrder = {}, spells = {}, all = {}, known = {},
             knownSet = {}, maxRank = {}, refused = {} }
end

--- B:Build() -> source (or nil when the logged-in class reads SpellData).
function B:Build()
    B.Forget()
    local p = Profile()
    if not p or not MD.Parse then return nil end
    local src = Empty(p)
    local keyOf = p:FamilyKeys()
    for _, hit in ipairs(Walk(keyOf)) do
        local key = keyOf[hit.name]
        local def = p.families[key]
        if not src.spells[hit.id] and not src.refused[hit.id] then
            local s, why = B.ReadRank(hit.id, key, def, hit.sub)
            if s then
                src.spells[hit.id] = s
                src.all[key] = src.all[key] or {}
                table.insert(src.all[key], hit.id)
            else
                src.refused[hit.id] = hit.name .. ": " .. tostring(why)
            end
        end
    end
    for key, list in pairs(src.all) do
        -- lowest rank first; a rank the text did not name sorts by its base
        table.sort(list, function(a, b)
            local sa, sb = src.spells[a], src.spells[b]
            local ra, rb = sa.rank or 0, sb.rank or 0
            if ra ~= rb then return ra < rb end
            return (sa.healMax or sa.hotTotal or 0) < (sb.healMax or sb.hotTotal or 0)
        end)
        local def = p.families[key]
        src.families[key] = { type = def.kit, label = def.names and def.names[1] or key, exclude = def.exclude }
        src.known[key] = {}
        for i, id in ipairs(list) do
            local s = src.spells[id]
            if not s.rank then s.rank = i end
            src.known[key][i] = id
            src.knownSet[id] = true
        end
        src.maxRank[key] = list[#list]
    end
    for _, key in ipairs(p.order or {}) do
        if src.families[key] then src.familyOrder[#src.familyOrder + 1] = key end
    end
    for key in pairs(src.families) do
        local listed = false
        for _, k in ipairs(src.familyOrder) do if k == key then listed = true end end
        if not listed then src.familyOrder[#src.familyOrder + 1] = key end
    end
    return setmetatable(src, { __index = B.SourceMethods })
end

--------------------------------------------------------------------------------
-- The SpellData-shaped methods the rank math calls.
--------------------------------------------------------------------------------
B.SourceMethods = {}
local M = B.SourceMethods
-- The client's cost carries the talents; read again live, else the read one.
function M:GetCost(id)
    local list = Call("SpellPowerCost", id)
    if type(list) == "table" then
        for _, c in ipairs(list) do
            if type(c) == "table" and c.type == 0 and type(c.cost) == "number" then return c.cost, "live" end
        end
    end
    local s = self.spells[id]
    if s and s.cost then return s.cost, s.costFrom == "api" and "live (at login)" or "tooltip" end
    return nil, "unknown"
end
function M:StaticCost(id)
    local s = self.spells[id]
    return s and s.cost or nil
end
function M:Relic() return nil end
function M:Resolve(id) return id end
-- T123: SD:LiveCost's answer through the adapter -- the client's mana cost,
-- 0 for a cost list with no mana (free for our purposes), nil without one.
function M:LiveCost(id)
    local list = Call("SpellPowerCost", id)
    if type(list) ~= "table" then return nil end
    for _, c in ipairs(list) do
        if type(c) == "table" and c.type == 0 and type(c.cost) == "number" then return c.cost end
    end
    return 0
end
-- T123: SD:IsMaxKnownRank -- the highest rank of its family the book lists.
function M:IsMaxKnownRank(id)
    local s = self.spells[id]
    return s ~= nil and self.maxRank[s.family] == id
end

--- B:Source() -> the built source, or nil (the druid, a class without a
--- profile, or not built yet).
function B:Source()
    return B._src
end

function B:Rebuild()
    B._src = B:Build()
    if B._src then MD:Fire("SPELLS_REBUILT") end
    return B._src
end

local function OnBook() B:Rebuild() end
MD:RegisterCallback("MD_READY", OnBook)
MD:On("SPELLS_CHANGED", OnBook)
MD:On("LEARNED_SPELL_IN_TAB", OnBook)
MD:On("PLAYER_LEVEL_UP", OnBook)
-- T118: B:Build forgets the reads and the walk; these two forget them for a
-- class that builds nothing (the druid, whose TBC book still walks)
MD:On("SPELLS_CHANGED", B.Forget)
MD:On("LEARNED_SPELL_IN_TAB", B.Forget)
