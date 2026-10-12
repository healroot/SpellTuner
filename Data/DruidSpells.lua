-- The druid casts that are NOT heals (docs/SPEC-v0.10.md §2). The healing
-- model in Data/SpellData.lua prices what a plan may choose; this names what
-- the healer did with the rest of their mana, which on a five-man healer who
-- assists the damage dealers and roots things is a third of it.
--
-- Nothing here is a heal value or a formula. A row says only "this id is that
-- spell, and it is damage / crowd control / utility", so a wrong row costs a
-- label and a category, never a number: the cast's own mana cost comes from the
-- recording either way.
--
-- Seeded from the TBC database on 2026-09-07 and corroborated against the
-- author's own recordings -- four of the five ids reproduce their recorded cost
-- exactly, three of them only after Moonglow's -9%, which is a stronger check
-- than the lookup on its own. Every row is VERIFY until a recording has carried
-- it. The addon does not need this table to be complete: ST:ClassifyCast falls
-- back to the spell's NAME from the client and writes what it learns into
-- cdb.spellbook, so the map grows from the game rather than from a website.
local _, ST = ...

local DS = {}
ST.DruidSpells = DS

-- [spellID] = { family, kind }   kind: "damage" | "cc" | "utility"
DS.byID = {
    [26987] = { "Moonfire", "damage" },         -- r11, 430 base; recorded 391 = x0.91 Moonglow 3
    [25298] = { "Starfire", "damage" },         -- 340 base; recorded 309 = x0.91
    [24977] = { "Insect Swarm", "damage" },     -- 155; Moonglow does not touch it, recorded 155
    [9853]  = { "Entangling Roots", "cc" },     -- 125; recorded 125
    [17329] = { "Nature's Grasp", "cc" },       -- free; recorded 0
    [33786] = { "Cyclone", "cc" },              -- VERIFY: 8% of base mana, not yet in a recording
    [24858] = { "Moonkin Form", "shift" },      -- 22% of base mana; recorded 260 twice
}

-- Fallback by family NAME (enUS, like the drink buffs in UI/Advisor.lua). The
-- client names any spell, so this covers every rank of everything without a
-- table of ids -- and it is what teaches cdb.spellbook.
DS.byName = {
    ["Moonfire"] = "damage", ["Starfire"] = "damage", ["Wrath"] = "damage",
    ["Insect Swarm"] = "damage", ["Hurricane"] = "damage", ["Faerie Fire"] = "damage",
    ["Faerie Fire (Feral)"] = "damage",
    ["Entangling Roots"] = "cc", ["Nature's Grasp"] = "cc", ["Cyclone"] = "cc",
    ["Hibernate"] = "cc", ["Soothe Animal"] = "cc", ["Bash"] = "cc", ["Maim"] = "cc",
    ["Mark of the Wild"] = "utility", ["Gift of the Wild"] = "utility", ["Thorns"] = "utility",
    ["Innervate"] = "utility", ["Rebirth"] = "utility", ["Remove Curse"] = "utility",
    ["Abolish Poison"] = "utility", ["Cure Poison"] = "utility", ["Barkskin"] = "utility",
    ["Nature's Swiftness"] = "utility", ["Tranquility"] = "utility",
    -- Shapeshifts are their own kind: the mana is real and it is not a choice a
    -- healing plan gets to make, but neither is it damage, control or a buff.
    -- The fight summary has counted "shifts" separately since v0.7.0.
    ["Moonkin Form"] = "shift", ["Bear Form"] = "shift", ["Dire Bear Form"] = "shift",
    ["Cat Form"] = "shift", ["Travel Form"] = "shift", ["Aquatic Form"] = "shift",
    ["Flight Form"] = "shift", ["Swift Flight Form"] = "shift", ["Tree of Life"] = "shift",
}

DS.KINDS = { damage = true, cc = true, utility = true, shift = true }

--------------------------------------------------------------------------------
-- What was that cast? Returns family, kind.
--   "heal"    -- the healing model prices it and a plan may choose it
--   "damage" / "cc" / "utility" / "shift"
--   "unknown" -- nobody can say, which is a hole the coverage gate must notice
--
-- Whatever is resolved is written into cdb.spellbook so the offline tools, and
-- a later session, inherit it without asking the client again.
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- T130b (review M1): a TBC class that reads its own book (RankMath:IsClassBook,
-- the priest, shaman and paladin) is asked about its OWN spells: its book's
-- heals, its profile's `unmodelled` heals (a shape the rank math has none
-- for: an absorb, a totem, a next-cast modifier -- replayed as cast, so
-- "utility"), its `damage` families, and its profile's `castKinds` (name ->
-- kind, every row VERIFY like DS.byName above). Before this every such cast
-- was "unknown" and a priest's Power Word: Shield failed the spend-coverage
-- gate. Labels only: no heal value and no formula. Nil for the druid.
--------------------------------------------------------------------------------
local function IsClassBook()
    local RM = ST.RankMath
    return RM ~= nil and type(RM.IsClassBook) == "function" and RM:IsClassBook() == true
end

function DS.ClassKind(name)
    if type(name) ~= "string" or not IsClassBook() then return nil end
    local p = ST.ClassProfile
    if type(p) ~= "table" then return nil end
    for _, def in pairs(p.families or {}) do
        for _, n in ipairs(def.names or {}) do if n == name then return "heal" end end
    end
    for _, n in ipairs(p.unmodelled or {}) do if n == name then return "utility" end end
    for key, def in pairs(p.damage or {}) do
        if key == name then return "damage" end
        for _, n in ipairs(def.names or {}) do if n == name then return "damage" end end
    end
    local kind = p.castKinds and p.castKinds[name]
    if DS.KINDS[kind] then return kind end
    return nil
end

local function ClassBookSpell(spellID)
    if not IsClassBook() then return nil end
    local src = ST.RankMath:Source()
    local s = src and src.spells and src.spells[spellID]
    if s then return s.family end
    return nil
end

function ST:ClassifyCast(spellID)
    if type(spellID) ~= "number" then return nil, "unknown" end
    local SD = ST.SpellData
    local s = SD and SD.spells[spellID]
    if s then return s.family, "heal" end

    local classBook = IsClassBook()
    if classBook then
        local fam = ClassBookSpell(spellID)
        if fam then return fam, "heal" end
    end

    local row = DS.byID[spellID]
    if row then
        ST:LearnSpell(spellID, row[1], row[2])
        return row[1], row[2]
    end

    local known = ST.cdb and ST.cdb.spellbook and ST.cdb.spellbook[spellID]
    -- a class book asks again about what an earlier session could not name
    if known and not (classBook and known.kind == "unknown") then return known.family, known.kind end

    local name = GetSpellInfo and GetSpellInfo(spellID) or nil
    if name then
        local kind = DS.ClassKind(name) or DS.byName[name]
        if kind then
            ST:LearnSpell(spellID, name, kind)
            return name, kind
        end
        ST:LearnSpell(spellID, name, "unknown")
        return name, "unknown"
    end
    return nil, "unknown"
end

function ST:LearnSpell(spellID, family, kind)
    if not ST.cdb then return end
    ST.cdb.spellbook = ST.cdb.spellbook or {}
    local was = ST.cdb.spellbook[spellID]
    if was and was.kind == kind and was.family == family then return end
    ST.cdb.spellbook[spellID] = { family = family, kind = kind, at = time() }
    ST:Debug("cast", "learned %s (%d) is %s", tostring(family), spellID, kind)
end

-- Every non-healing cast in a recording, grouped by kind. The offline tools use
-- the stream's own name map (v0.10.1) so they can read it without a client.
function DS.Summarise(rec)
    local out = { damage = { mana = 0, casts = 0 }, cc = { mana = 0, casts = 0 },
                  utility = { mana = 0, casts = 0 }, unknown = { mana = 0, casts = 0 },
                  shift = { mana = 0, casts = 0 }, heal = { mana = 0, casts = 0 }, byName = {} }
    local K = ST.SimModel and ST.SimModel.K
    if not (rec and K) then return out end
    for i = 1, (rec.n or 0) do
        if rec.ev.kind[i] == K.OWNCAST then
            local id, cost = rec.ev.x[i], rec.ev.amt[i] or 0
            if cost < 0 then cost = 0 end
            local family, kind = ST:ClassifyCast(id)
            if kind == "unknown" and rec.names and rec.names[id] then
                family = rec.names[id]
                local bare = family:gsub(" r%d+$", "")
                local byName = DS.ClassKind(bare) or DS.byName[bare]
                if byName then kind = byName end
            end
            local b = out[kind] or out.unknown
            b.mana, b.casts = b.mana + cost, b.casts + 1
            local label = family or ("spell " .. id)
            out.byName[label] = out.byName[label] or { mana = 0, casts = 0, kind = kind, id = id }
            out.byName[label].mana = out.byName[label].mana + cost
            out.byName[label].casts = out.byName[label].casts + 1
        end
    end
    return out
end
