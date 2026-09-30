-- The spell kit's shape, in one place (T63, P19 of docs/PLAN-refactor-ux.md,
-- review A12 and the first step of A11).
--
-- A kit is what the simulator heals with: every known rank of every modelled
-- family, flattened into plain numbers once per form, so the engine never runs
-- the rank math inside its loop (docs/SPEC-v0.7.md 3.1). Two builders make one
-- -- Engine/RankMath.lua's RankMath:SpellKit (TBC, from Data/SpellData.lua) and
-- Modules/SpellTuner_Replay/Kit_Forever.lua's (Forever, from the spellbook) --
-- and until this file its shape lived in a comment above the first of them,
-- which is how `castBase` came to be remembered in one builder and not the
-- other. Kit.FIELDS is that comment as a table, Kit.Validate checks a kit
-- against it, and both builders end with Kit.Check, so a field one of them
-- forgets or misspells fails at the boundary instead of healing for 0 inside a
-- search. Kit.Snapshot / Kit.Restore (the kit as plain data for SavedVariables
-- and back) moved here from Engine/SimModel.lua and Kit_Forever.lua; the old
-- names (SM.KitSnapshot, RankMath.KitSnapshot, RankMath.KitRestore) stay as
-- aliases.
--
-- Pure: no client call, no frame. Listed by SpellTuner_TBC.toc before
-- Engine/RankMath.lua and by the Replay module before Kit_Forever.lua (both
-- before Engine/SimModel.lua, which aliases Kit.Snapshot at load).
local _, MD = ...

MD.Kit = MD.Kit or {}
local Kit = MD.Kit

-- The forms a kit carries an entry list for. Forever has no Tree of Life, so
-- its builder leaves `tree` empty; it is still a table.
Kit.FORMS = { "caster", "tree" }

--------------------------------------------------------------------------------
-- Kit.FIELDS: every field a kit entry may carry, with its Lua type.
--
--   kit.caster[spellID] / kit.tree[spellID] = {
--     family, rank, type, cost, cast, castBase, gcd,
--     direct, directCrit,                  -- direct / hybrid; NEVER crit-loaded
--     tick, ticks, tickPeriod, duration,   -- hot / hybrid / lifebloom
--     bloom,                               -- lifebloom
--     swiftmendRejuv, swiftmendRegrowth,   -- instant (Swiftmend)
--     channelTick, channelTicks,           -- channel (Tranquility)
--     dataMissing }                        -- a value the source could not give
--
-- A field not in this table is refused by Kit.Validate: a new field is
-- declared here first, which is what makes this file the shape's owner.
--------------------------------------------------------------------------------
Kit.FIELDS = {
    family = "string", rank = "number", type = "string", gcd = "number",
    cost = "number", cast = "number",
    -- the cast bar a player actually waits through (Engine/Practice.lua reads
    -- it for "direct" and "hybrid"); `cast` averages Nature's Grace in
    castBase = "number",
    direct = "number", directCrit = "number",
    tick = "number", ticks = "number", tickPeriod = "number", duration = "number",
    bloom = "number",
    swiftmendRejuv = "number", swiftmendRegrowth = "number",
    channelTick = "number", channelTicks = "number",
    dataMissing = "boolean",
}

-- Required on every entry, whatever else it lacks.
Kit.ALWAYS = { "family", "rank", "type", "gcd" }

-- The entry types Engine/SimModel.lua switches on, each with the fields it
-- needs. An entry marked `dataMissing` owes only Kit.ALWAYS (its source could
-- not give a value; Engine/Practice.lua refuses to cast it, "Not modelled
-- yet"); any field it does carry is still type-checked. Swiftmend's two
-- values and Tranquility's are optional: Swiftmend is worth nothing when
-- neither HoT is known, and TBC carries Tranquility with dataMissing.
Kit.TYPES = {
    direct    = { "cost", "cast", "castBase", "direct", "directCrit" },
    hybrid    = { "cost", "cast", "castBase", "direct", "directCrit",
                  "tick", "ticks", "tickPeriod", "duration" },
    hot       = { "cost", "cast", "tick", "ticks", "tickPeriod", "duration" },
    lifebloom = { "cost", "cast", "tick", "ticks", "tickPeriod", "duration", "bloom" },
    instant   = { "cost", "cast" },
    channel   = { "cost", "cast" },
}

-- Families a kit carries for their mana and cast only, with no heal value:
-- Innervate, which Data/SpellData.lua lists so it is never "unknown" and which
-- the TBC builder therefore prices (a recorded Innervate spends its mana and
-- its global cooldown in a replay) under the builder's default type,
-- "direct", healing 0. They owe Kit.ALWAYS and these, whatever their type.
Kit.UNPRICED = { Innervate = true }
Kit.UNPRICED_NEEDS = { "cost", "cast" }

-- The kit's own fields (a snapshot adds `at` and `level`).
Kit.TOP = {
    caster = "table", tree = "table", crit = "number", critMissing = "boolean",
    at = "number", level = "number",
}

local function Finite(v)
    return v == v and v ~= math.huge and v ~= -math.huge
end

local function Say(problems, fmt, ...)
    problems[#problems + 1] = string.format(fmt, ...)
end

--------------------------------------------------------------------------------
-- Kit.Validate(kit) -> true | false, problems
--
-- problems is a list of ASCII sentences, each naming the form, the spell id and
-- the field. Checks: the kit is a table whose own fields are declared in
-- Kit.TOP with their types, `caster` and `tree` are tables, `crit` is a
-- fraction in [0, 1]; every entry is keyed by a number, carries only declared
-- fields of their declared types (numbers finite), a known `type`, Kit.ALWAYS,
-- and -- unless dataMissing -- every field its type needs.
--------------------------------------------------------------------------------
function Kit.Validate(kit)
    local problems = {}
    if type(kit) ~= "table" then
        Say(problems, "the kit is a %s, not a table", type(kit))
        return false, problems
    end
    for k, v in pairs(kit) do
        local want = Kit.TOP[k]
        if want == nil then
            Say(problems, "kit.%s is not a kit field (declare it in Kit.TOP)", tostring(k))
        elseif type(v) ~= want then
            Say(problems, "kit.%s is a %s, not a %s", tostring(k), type(v), want)
        end
    end
    for _, form in ipairs(Kit.FORMS) do
        if type(kit[form]) ~= "table" then Say(problems, "kit.%s is missing", form) end
    end
    if type(kit.crit) ~= "number" then
        Say(problems, "kit.crit is missing")
    elseif not Finite(kit.crit) or kit.crit < 0 or kit.crit > 1 then
        Say(problems, "kit.crit is %s, not a fraction in [0, 1]", tostring(kit.crit))
    end

    for _, form in ipairs(Kit.FORMS) do
        local list = kit[form]
        if type(list) == "table" then
            for id, e in pairs(list) do
                local where = form .. "[" .. tostring(id) .. "]"
                if type(id) ~= "number" then
                    Say(problems, "%s: the key is a %s, not a spell id", where, type(id))
                end
                if type(e) ~= "table" then
                    Say(problems, "%s is a %s, not an entry", where, type(e))
                else
                    for k, v in pairs(e) do
                        local want = Kit.FIELDS[k]
                        if want == nil then
                            Say(problems, "%s.%s is not a kit field (declare it in Kit.FIELDS)", where, tostring(k))
                        elseif type(v) ~= want then
                            Say(problems, "%s.%s is a %s, not a %s", where, tostring(k), type(v), want)
                        elseif want == "number" and not Finite(v) then
                            Say(problems, "%s.%s is %s", where, tostring(k), tostring(v))
                        end
                    end
                    for _, k in ipairs(Kit.ALWAYS) do
                        if e[k] == nil then Say(problems, "%s has no %s", where, k) end
                    end
                    local needs = e.type ~= nil and Kit.TYPES[e.type]
                    if needs and Kit.UNPRICED[e.family] then needs = Kit.UNPRICED_NEEDS end
                    if e.type ~= nil and not needs then
                        Say(problems, "%s.type %s is not a kit type", where, tostring(e.type))
                    elseif needs and e.dataMissing ~= true then
                        for _, k in ipairs(needs) do
                            if e[k] == nil then
                                Say(problems, "%s (%s) has no %s", where, tostring(e.type), k)
                            end
                        end
                    end
                end
            end
        end
    end
    return #problems == 0, (#problems > 0) and problems or nil
end

-- What a builder ends with: the kit itself when it validates, else an error
-- naming the builder and the first problems. A kit that fails is a builder's
-- bug (a value the source could not give is `dataMissing`, which validates),
-- and it is never handed to the engine.
local SHOWN = 3
function Kit.Check(kit, who)
    local ok, problems = Kit.Validate(kit)
    if ok then return kit end
    local shown = {}
    for i = 1, math.min(SHOWN, #problems) do shown[i] = problems[i] end
    local more = (#problems > SHOWN) and string.format(" (and %d more)", #problems - SHOWN) or ""
    error(string.format("%s: the kit fails Kit.Validate: %s%s",
        tostring(who or "a kit builder"), table.concat(shown, "; "), more), 2)
end

--------------------------------------------------------------------------------
-- Kit.Snapshot(kit): the kit a fight was played with, as plain data for
-- SavedVariables (2026-09-29, the one mechanism for both clients): every form's
-- entries with their number, string and boolean fields, the crit, the time and
-- the character's level. It IS a kit -- `SM.ScenarioFromRecording(rec,
-- rec.kit)` replays with it as it stands -- and it holds nothing a replay does
-- not read: no MD.SpellData index (on TBC that table is static; on Forever it
-- is rebuilt from these entries by Kit.Restore) and no unlearned rank. Stored
-- on every practice fight (Engine/Practice.lua), every Forever pull
-- (Recorder_Forever.lua) and as the character's last kit (cdb.kit, Forever).
-- Pure copies; nothing here reads the client. Moved unchanged from
-- Engine/SimModel.lua (SM.KitSnapshot is its alias).
--------------------------------------------------------------------------------
function Kit.Snapshot(kit)
    if type(kit) ~= "table" then return nil end
    local snap = { crit = kit.crit, critMissing = kit.critMissing or nil,
                   at = time and time() or nil, level = MD.player and MD.player.level or nil }
    for form, list in pairs(kit) do
        if type(list) == "table" then
            local out = {}
            for id, e in pairs(list) do
                if type(e) == "table" then
                    local c = {}
                    for k, v in pairs(e) do
                        local tv = type(v)
                        if tv == "number" or tv == "string" or tv == "boolean" then c[k] = v end
                    end
                    out[id] = c
                end
            end
            snap[form] = out
        end
    end
    return snap
end

--------------------------------------------------------------------------------
-- Kit.Restore(snap, policy) -> kit, index
--
-- A snapshot back into a kit AND the MD.SpellData index the engine reads names,
-- families and ranks from, rebuilt from the kit's own entries (family, rank,
-- cost, cast). Every rank in it is a known one (a kit holds nothing else), so
-- `all` is `known`; the unlearned ranks and the skipped families a replay never
-- reads are not there. The kit is a fresh copy (the engine never writes into
-- the snapshot); the index is returned, not installed -- the caller decides
-- whether it becomes MD.SpellData (Kit_Forever.lua's RankMath.KitRestore does).
-- Not validated: a snapshot is replayed as it was recorded.
--
-- policy (the flavour's, all optional):
--   types        family key -> entry type; a family not in it stays in the kit
--                but out of the index (absent: every entry's own `type`)
--   labels       family key -> the label the index carries (absent: the key)
--   exclude      family key -> true for a family kept out of the plans
--   familyOrder  the dashboard order, copied into the index
-- Moved from Kit_Forever.lua (RankMath.KitRestore), whose policy is Forever's.
--------------------------------------------------------------------------------
local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

function Kit.Restore(snap, policy)
    policy = policy or {}
    snap = snap or {}
    local types, labels, exclude = policy.types, policy.labels or {}, policy.exclude or {}
    local kit = { crit = snap.crit or 0, critMissing = snap.critMissing or nil,
                  caster = Copy(snap.caster or {}), tree = Copy(snap.tree or {}) }
    local spells, families, known, maxRank = {}, {}, {}, {}
    for id, e in pairs(kit.caster) do
        local key = e.family
        local ftype
        if key then
            if types then ftype = types[key] else ftype = e.type end
        end
        if ftype then
            spells[id] = { family = key, rank = e.rank, cost = e.cost, cast = e.cast }
            families[key] = families[key]
                or { type = ftype, label = labels[key] or key, exclude = exclude[key] or nil }
            known[key] = known[key] or {}
            known[key][#known[key] + 1] = id
        end
    end
    local all = {}
    for key, ids in pairs(known) do
        table.sort(ids, function(a, b) return (spells[a].rank or 0) < (spells[b].rank or 0) end)
        maxRank[key] = ids[#ids]
        all[key] = Copy(ids)
    end
    local index = {
        spells = spells, families = families, known = known, all = all, maxRank = maxRank,
        skipped = {}, familyOrder = policy.familyOrder and Copy(policy.familyOrder) or nil,
    }
    return kit, index
end
