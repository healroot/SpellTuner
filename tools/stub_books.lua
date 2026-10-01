-- tools/stub_books.lua -- not a suite (T95, docs/SPEC-next.md 2: "stub extensions live in
-- their own files"). A priest, shaman or paladin spellbook for tools/wowstub.lua's forever
-- profile, from the committed extracts in tools/data/books/<class>_forever.lua (talentsforever's
-- export of the beta client's own texts, CC BY 4.0 -- see each file's header). Loaded only by
-- the suites that read a class book (bookcheck, tipcheck, spellsui), so no other count moves.
--
--   local Books = dofile(here .. "/stub_books.lua")
--   local data = Books.Load("paladin")                 -- the extract, as a table
--   local restore = Books.Install(data, opts)          -- the stub's client answers it
--
-- Install wraps, in place, the client functions Spells/Book.lua reads through MD.API
-- (C_SpellBook's walk, C_Spell's name / rank / text / cast / cost / level, the tooltip data and
-- GetSpellBaseCooldown): an id or slot of the class book is answered from the extract, anything
-- else by the stub's own function. opts (all optional):
--   alone         true: the book holds only the class's spells (slots 1..n, the stub's druid
--                 rows gone); default false: added beside the stub's own book from `firstSlot`
--   firstSlot     the first slot of an added book (default 300; the stub's own rows sit at 1..)
--   only          a function(row) -> boolean, the rows to take (default every row)
--   baseCooldowns { [id] = ms }: what GetSpellBaseCooldown answers for a book id (0 otherwise,
--                 the client's answer for a spell with none); with no table the function is
--                 left as the stub has it (absent)
--   MD            an addon table whose MD.API.Has cache is cleared for every wrapped name (and
--                 whose Book is marked dirty), so a book already scanned reads the new answers
-- The answers' shapes are the stub's own (tools/wowstub.lua's forever profile: retail 12.x
-- documented, NOT observed on Forever), so Book reads a class book exactly as it reads the
-- druid's. The tooltip data is the extract's lines between the name line and the description
-- -- the cost / range and the cast / cooldown pairs as the client draws them (the export's own
-- `l`); its right texts are where a cooldown is (Parse.Cooldown).
local Books = {}

local here = (arg and arg[0] or ""):match("^(.*)/[^/]+$") or "tools"

function Books.Load(class)
    local root = rawget(_G, "STUB_BOOKS_DIR") or here
    return dofile(root .. "/data/books/" .. class .. "_forever.lua")
end

-- The extract's cost line as the client's cost list (type 0 mana, 1 rage, 3 energy): the
-- first left text that names one; none -> no value at all (the stub's free spell).
local POWER_TYPE = { Rage = 1, Focus = 2, Energy = 3 }
local function CostOf(row)
    for _, l in ipairs(row.lines) do
        local left = l[1]
        local n = left:match("^([%d,]+) Mana$")
        if n then return { type = 0, cost = tonumber((n:gsub(",", ""))), costPercent = 0 } end
        local pct = left:match("^([%d.]+)%% of base mana$")
        if pct then return { type = 0, cost = 0, costPercent = tonumber(pct) } end
        local amt, word = left:match("^([%d,]+) (%a+)$")
        if amt and POWER_TYPE[word] then
            return { type = POWER_TYPE[word], cost = tonumber((amt:gsub(",", ""))), costPercent = 0 }
        end
    end
    return nil
end

-- The cast in ms: "2.5 sec cast" -> 2500; Instant, Channeled or none -> 0.
local function CastMs(row)
    for _, l in ipairs(row.lines) do
        local secs = l[1]:match("^([%d.]+) sec cast$")
        if secs then return math.floor(tonumber(secs) * 1000 + 0.5) end
    end
    return 0
end

local WRAPPED = {
    { "C_SpellBook", "GetSpellBookItemInfo" }, { "C_SpellBook", "IsSpellBookItemLowRank" },
    { "C_SpellBook", "IsSpellKnown" }, { "C_SpellBook", "GetNumSpellBookSkillLines" },
    { "C_SpellBook", "GetSpellBookSkillLineInfo" },
    { "C_Spell", "GetSpellName" }, { "C_Spell", "GetSpellSubtext" }, { "C_Spell", "GetSpellDescription" },
    { "C_Spell", "GetSpellInfo" }, { "C_Spell", "GetSpellPowerCost" }, { "C_Spell", "GetSpellLevelLearned" },
    { "C_Spell", "GetBaseSpell" },
    { "C_TooltipInfo", "GetSpellByID" },
}

function Books.Install(data, opts)
    opts = opts or {}
    local alone = opts.alone == true
    local firstSlot = alone and 1 or (opts.firstSlot or 300)

    local byId, bySlot, firstRank, maxSlot = {}, {}, {}, 0
    local slot = firstSlot
    for _, row in ipairs(data.spells) do
        if not opts.only or opts.only(row) then
            byId[row.id] = row
            bySlot[slot] = row
            maxSlot = slot
            slot = slot + 1
            if not firstRank[row.name] then firstRank[row.name] = row.id end
        end
    end

    local saved = {}
    for _, w in ipairs(WRAPPED) do
        local ns = _G[w[1]]
        saved[#saved + 1] = { ns, w[2], ns and ns[w[2]] }
    end
    local savedBase = rawget(_G, "GetSpellBaseCooldown")
    local function Orig(ns, name)
        for _, s in ipairs(saved) do
            if s[1] == ns and s[2] == name then return s[3] end
        end
    end

    local SB, SP, TI = C_SpellBook, C_Spell, C_TooltipInfo
    local o = {}
    for _, w in ipairs(WRAPPED) do o[w[2]] = Orig(_G[w[1]], w[2]) end
    local function Pass(fn, ...)
        if alone or type(fn) ~= "function" then return nil end
        return fn(...)
    end

    SB.GetSpellBookItemInfo = function(s, bank)
        local row = bySlot[s]
        if row then
            return {
                spellID = row.id, name = row.name, subName = row.rank, itemType = 1,
                isPassive = row.rank == "Passive", isOffSpec = false, skillLineIndex = 2,
                actionID = row.id, iconID = 136041,
            }
        end
        return Pass(o.GetSpellBookItemInfo, s, bank)
    end
    SB.IsSpellBookItemLowRank = function(s, bank)
        if bySlot[s] then return false end
        return Pass(o.IsSpellBookItemLowRank, s, bank)
    end
    SB.IsSpellKnown = function(id)
        if byId[id] then return true end
        return Pass(o.IsSpellKnown, id)
    end
    SB.GetNumSpellBookSkillLines = function()
        if alone then return 2 end
        return o.GetNumSpellBookSkillLines()
    end
    SB.GetSpellBookSkillLineInfo = function(i)
        if alone then
            if i == 1 then
                return { name = "General", iconID = 1, itemIndexOffset = 0, numSpellBookItems = 0,
                         isGuild = false, shouldHide = false }
            elseif i == 2 then
                return { name = data.class, iconID = 2, itemIndexOffset = 0, numSpellBookItems = maxSlot,
                         isGuild = false, shouldHide = false }
            end
            return nil
        end
        local info = o.GetSpellBookSkillLineInfo(i)
        if i == 2 and type(info) == "table" and type(info.numSpellBookItems) == "number"
            and info.numSpellBookItems < maxSlot then
            local copy = {}
            for k, v in pairs(info) do copy[k] = v end
            copy.numSpellBookItems = maxSlot
            return copy
        end
        return info
    end

    SP.GetSpellName = function(id)
        if byId[id] then return byId[id].name end
        return Pass(o.GetSpellName, id)
    end
    SP.GetSpellSubtext = function(id)
        if byId[id] then return byId[id].rank end
        return Pass(o.GetSpellSubtext, id)
    end
    SP.GetSpellDescription = function(id)
        if byId[id] then return byId[id].desc end
        return Pass(o.GetSpellDescription, id)
    end
    SP.GetSpellInfo = function(id)
        local row = byId[id]
        if row then
            return { name = row.name, iconID = 136041, originalIconID = 136041, castTime = CastMs(row),
                     minRange = 0, maxRange = 40, spellID = id }
        end
        return Pass(o.GetSpellInfo, id)
    end
    SP.GetSpellPowerCost = function(id)
        local row = byId[id]
        if row then
            local c = CostOf(row)
            if not c then return end
            return { { type = c.type, name = (c.type == 0) and "MANA" or "OTHER", cost = c.cost, minCost = c.cost,
                       costPercent = c.costPercent, costPerSec = 0, requiredAuraID = 0, hasRequiredAura = false } }
        end
        return Pass(o.GetSpellPowerCost, id)
    end
    SP.GetSpellLevelLearned = function(id)
        if byId[id] then return byId[id].level end
        return Pass(o.GetSpellLevelLearned, id)
    end
    SP.GetBaseSpell = function(id)
        if byId[id] then return firstRank[byId[id].name] end
        return Pass(o.GetBaseSpell, id)
    end

    TI.GetSpellByID = function(id)
        local row = byId[id]
        if row then
            local lines = { { leftText = row.name, rightText = row.rank } }
            for _, l in ipairs(row.lines) do lines[#lines + 1] = { leftText = l[1], rightText = l[2] } end
            lines[#lines + 1] = { leftText = row.desc }
            return { type = 1, id = id, lines = lines }
        end
        return Pass(o.GetSpellByID, id)
    end

    if type(opts.baseCooldowns) == "table" then
        local base = opts.baseCooldowns
        _G.GetSpellBaseCooldown = function(id)
            if byId[id] then return base[id] or 0, 1500 end
            if type(savedBase) == "function" then return savedBase(id) end
            return 0, 0
        end
    end

    local MD = opts.MD
    local function Forget()
        if not (MD and MD.API and MD.API.Invalidate) then return end
        for _, w in ipairs(WRAPPED) do MD.API.Invalidate(w[1] .. "." .. w[2]) end
        MD.API.Invalidate("GetSpellBaseCooldown")
        if MD.Book and MD.Book.MarkDirty then MD.Book:MarkDirty() end
    end
    Forget()

    return function()
        for _, s in ipairs(saved) do
            if s[1] then s[1][s[2]] = s[3] end
        end
        _G.GetSpellBaseCooldown = savedBase
        Forget()
    end
end

return Books
