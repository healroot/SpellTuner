-- tools/run.sh tools/wclcheckkit.lua [recordsFile] [observedFile] [--fit]
--
-- What our model says each spell heals, against what the log says it DID.
-- The kit is built from the profile the importer inferred (stats from the
-- combatant info, talents from the tree split); the observed medians come from
-- the raw report. A row that is off by more than the crit spread is a number in
-- Data/SpellData.lua to go and fix, not noise.
--
-- v0.14.7, --fit: the other direction. Instead of trusting the profile's
-- +healing and grading the spell data, solve for the +healing that makes the
-- model reproduce the log, ONE ROW AT A TIME. Four independent families -- a
-- Rejuvenation tick, a Regrowth tick, a Lifebloom tick and its bloom -- land on
-- the same number to within a few percent on every parse in the corpus, which
-- is what says the heal values and the coefficients are right and the PROFILE
-- was wrong: the log's `spellPower` is spell damage, not +healing (see
-- SPELLPOWER_TO_HEALING in tools/wclconvert.py). Regrowth's DIRECT is the one
-- row that does not join them -- it asks for ~28% more +healing than the other
-- four on every parse that has it, i.e. the model's Regrowth direct is ~13%
-- low. That is a measurement, not yet a mechanism, so nothing was changed for
-- it; docs/SPEC-v0.14.md 4c carries it.
local here = arg[0]:match("^(.*)/[^/]+$")
-- tools/run.sh passes the checkout root as arg[1]; ours start at 2
local fit = false
local pos = {}
for i = 2, #arg do
    if arg[i] == "--fit" then fit = true else pos[#pos + 1] = arg[i] end
end
-- T57 (P13, review Q15): the two default files are gitignored; without them
-- it prints its usage line instead of a traceback.
local USAGE = "usage: tools/run.sh tools/wclcheckkit.lua [records.lua] [observed.lua] [--fit]"
    .. "  (defaults .logs/wcl-records.lua and .logs/wcl-observed.lua, written by tools/wclconvert.py)"
local function exists(p) local f = p and io.open(p, "r"); if f then f:close(); return true end end
local file = pos[1] or ".logs/wcl-records.lua"
local obsFile = pos[2] or ".logs/wcl-observed.lua"
for _, f in ipairs({ file, obsFile }) do
    if not exists(f) then print("wclcheckkit: no " .. f); print(USAGE); os.exit(2) end
end
dofile(file)
local realDB = _G.SpellTunerDB or _G.ManaDemonDB   -- files written before the rename
local pre = {}
for k, c in pairs(realDB.char) do pre[k] = c.profile end
HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB

-- observed medians, gross, non-crit: written next to the records by the converter
local OBS = dofile(obsFile)

local ratios = {}
local classKeys = {}
for key, p in pairs(pre) do
    local o = OBS[key]
    -- T111: a priest, shaman or paladin is held after every druid (below)
    if o and p.class and p.class ~= "DRUID" then classKeys[#classKeys + 1] = key; o = nil end
    if o then
        S.level = p.level; S.manaMax = p.manaMax; S.mana = p.manaMax
        if (p.intellect or 0) > 0 then S.stats[4] = p.intellect end
        if (p.spirit or 0) > 0 then S.stats[5] = p.spirit end
        local healing, crit = p.healing, p.crit
        _G.GetSpellBonusHealing = function() return healing end
        _G.GetSpellCritChance = function() return crit end
        local tal = p.talents or {}
        function MD:TalentRank(n) return tal[n] or 0 end
        MD.player.class = "DRUID"; MD.player.isDruid = true; MD.player.level = p.level
        function MD:InTreeForm() return false end
        _G.IsSpellKnown = function(id)
            local sd = MD.SpellData.spells[id]
            return sd ~= nil and (sd.level or 0) <= p.level
        end
        _G.IsPlayerSpell = _G.IsSpellKnown
        MD.SpellData:BuildKnown(); MD.Regen:Refresh()

        -- one row's model value at a given +healing
        local function modelAt(H, row)
            _G.GetSpellBonusHealing = function() return H end
            local kit = MD.RankMath:SpellKit({ live = true }).caster
            -- v0.14.4: a heal can arrive under a different spell id from the
            -- one cast -- Lifebloom's bloom is 33778, its HoT 33763 -- and the
            -- kit is keyed by the cast. Without the alias the bloom row silently
            -- matched nothing and the bloom was never compared at all.
            local e = kit[MD.SpellData:Resolve(row.id)]
            if not e then return nil end
            if row.what == "tick" then return (e.tick or 0) * (row.stacks or 1) end
            return (e.direct or 0) + (e.bloom or 0)
        end

        print(string.format("== %s   +%d healing%s, %.1f%% crit, talents %s",
            key, healing,
            (p.spellPower or 0) > 0 and string.format(" (log spellPower %d)", p.spellPower) or "",
            crit, next(tal) and "deep resto (inferred)" or "none"))
        if not fit then
            print(string.format("   %-22s %10s %10s %8s", "", "model", "log", "ratio"))
            for _, row in ipairs(o) do
                local model = modelAt(healing, row)
                if model and model > 0 then
                    print(string.format("   %-22s %10.0f %10.0f %8.2f",
                        row.label, model, row.median, row.median / model))
                end
            end
        else
            -- the +healing each row alone asks for
            print(string.format("   %-22s %10s %10s %8s", "", "model", "log", "implies"))
            local implied = {}
            for _, row in ipairs(o) do
                local m0 = modelAt(healing, row)
                if m0 and m0 > 0 then
                    local best, bestH
                    for H = 0, 6000, 5 do
                        local m = modelAt(H, row)
                        local l = math.log(row.median / m)
                        if not best or l * l < best then best, bestH = l * l, H end
                    end
                    implied[#implied + 1] = bestH
                    print(string.format("   %-22s %10.0f %10.0f %8d",
                        row.label, m0, row.median, bestH))
                end
            end
            table.sort(implied)
            if #implied > 0 then
                local med = implied[math.ceil(#implied / 2)]
                print(string.format("   %-22s %10s %10s %8d   x%.2f of the log's spellPower",
                    "median of the rows", "", "", med,
                    (p.spellPower or 0) > 0 and med / p.spellPower or 0))
                if (p.spellPower or 0) > 0 then ratios[#ratios + 1] = med / p.spellPower end
            end
        end
        print("")
    end
end
--------------------------------------------------------------------------------
-- T111 (docs/SPEC-next.md 4.2 P5): a TBC priest, shaman or paladin. The kit
-- is the one Engine/RankMath.lua builds from the class's book
-- (RankMath.ClassKit over Spells/Book_TBC.lua's source; the class's
-- `rankTable` is granted here, as tools/tbcclasscheck.lua does, since the
-- shipped profiles wait for the TBC panes), and the book is
-- tools/tbcclasscheck.lua's fixture --
-- the client's own tooltip texts -- installed in the stub's client. Each row
-- is held against its rank's kit entry (a direct heal's `direct`, a HoT's
-- `tick`, a chain heal's first target); --fit solves each row alone for the
-- +healing and says how far the families' answers lie apart. A row whose
-- spell the kit does not price (Prayer of Mending, Power Word: Shield,
-- Earth Shield: unmodelled by the profiles) is listed and skipped.
--------------------------------------------------------------------------------
table.sort(classKeys)
local classSpread = {}
if #classKeys > 0 then
    TBCCLASS_LIBRARY = true
    local lib = dofile(here .. "/tbcclasscheck.lua")
    local files = {}
    if not MD.Profiles.byClass.PRIEST then
        for _, f in ipairs({ "Data/Profile_Priest_TBC.lua", "Data/Profile_Shaman_TBC.lua",
                             "Data/Profile_Paladin_TBC.lua" }) do files[#files + 1] = f end
    end
    if not MD.Parse then files[#files + 1] = "Spells/Parse.lua" end
    if not MD.BookTBC then files[#files + 1] = "Spells/Book_TBC.lua" end
    if #files > 0 then S.Load(files, "SpellTuner", MD) end
    for _, c in ipairs({ "PRIEST", "SHAMAN", "PALADIN" }) do
        local caps = MD.Profiles.byClass[c].caps
        caps.rankTable, caps.tooltip = true, true
    end

    for _, key in ipairs(classKeys) do
        local p, o = pre[key], OBS[key]
        S.level = p.level or 70; S.manaMax = p.manaMax; S.mana = p.manaMax
        if (p.intellect or 0) > 0 then S.stats[4] = p.intellect end
        if (p.spirit or 0) > 0 then S.stats[5] = p.spirit end
        local healing, crit = p.healing, p.crit
        _G.GetSpellBonusHealing = function() return healing end
        _G.GetSpellCritChance = function() return crit end
        MD.API.Invalidate("GetSpellCritChance")
        local tal = p.talents or {}
        function MD:TalentRank(n) return tal[n] or 0 end
        local _, Restore = lib.Install(S, MD, p.class)
        S.units.player.class = p.class
        MD:DetectProfile()
        MD:Fire("CORE_LOGIN")
        local src = MD.BookTBC:Rebuild()
        local function Kit() return MD.RankMath.ClassKit({ live = true }, src) end
        -- the row's name is the class book's family label (the log's ability
        -- name can differ: 2060, Greater Heal rank 1, is "Heal" there)
        local function Label(row)
            local s = src and src.spells[row.id]
            local f = s and src.families[s.family]
            return (f and f.label or row.label) .. " #" .. row.id
        end

        local function modelAt(H, row)
            _G.GetSpellBonusHealing = function() return H end
            local e = Kit().caster[row.id]
            if not e or e.dataMissing then return nil end
            if row.what == "tick" then return e.tick and e.tick * (row.stacks or 1) or nil end
            return e.direct
        end

        local names = {}
        for t, r in pairs(tal) do names[#names + 1] = t .. " " .. r end
        table.sort(names)
        print(string.format("== %s   %s, +%d healing%s, %.1f%% crit, talents %s",
            key, p.class, healing,
            (p.spellPower or 0) > 0 and string.format(" (log spellPower %d)", p.spellPower) or "",
            crit, #names > 0 and table.concat(names, ", ") .. " (inferred)" or "none"))
        local skipped = {}
        if not fit then
            print(string.format("   %-26s %10s %10s %8s", "", "model", "log", "ratio"))
            for _, row in ipairs(o) do
                local model = modelAt(healing, row)
                if model and model > 0 then
                    print(string.format("   %-26s %10.0f %10.0f %8.2f",
                        Label(row), model, row.median, row.median / model))
                else
                    skipped[#skipped + 1] = row.label
                end
            end
        else
            print(string.format("   %-26s %10s %10s %8s %5s", "", "model", "log", "implies", "n"))
            local implied, byFamily = {}, {}
            for _, row in ipairs(o) do
                local m0 = modelAt(healing, row)
                if m0 and m0 > 0 then
                    local best, bestH
                    for H = 0, 6000, 5 do
                        local m = modelAt(H, row)
                        local l = math.log(row.median / m)
                        if not best or l * l < best then best, bestH = l * l, H end
                    end
                    implied[#implied + 1] = bestH
                    -- the family is the kit's (Label, above); a family's
                    -- answer is its best-sampled row's
                    local ke = Kit().caster[row.id]
                    local fam = ke and ke.family or row.label
                    if not byFamily[fam] or (row.n or 0) > byFamily[fam].n then
                        byFamily[fam] = { H = bestH, n = row.n or 0 }
                    end
                    print(string.format("   %-26s %10.0f %10.0f %8d %5s",
                        Label(row), m0, row.median, bestH, tostring(row.n or "")))
                else
                    skipped[#skipped + 1] = row.label
                end
            end
            table.sort(implied)
            local fams = {}
            for fam, x in pairs(byFamily) do fams[#fams + 1] = { fam = fam, H = x.H } end
            table.sort(fams, function(a, b) return a.H < b.H end)
            if #fams > 0 then
                local lo, hi = fams[1].H, fams[#fams].H
                local mid = (lo + hi) / 2
                local spread = mid > 0 and (hi - lo) / mid or 0
                local parts = {}
                for _, x in ipairs(fams) do parts[#parts + 1] = x.fam .. " " .. x.H end
                print(string.format("   %d families: %s -- spread %.0f%% of their middle",
                    #fams, table.concat(parts, ", "), spread * 100))
                classSpread[#classSpread + 1] = { key = key, n = #fams, spread = spread }
            end
            if #implied > 0 then
                local med = implied[math.ceil(#implied / 2)]
                print(string.format("   %-26s %10s %10s %8d   x%.2f of the log's spellPower",
                    "median of the rows", "", "", med,
                    (p.spellPower or 0) > 0 and med / p.spellPower or 0))
            end
        end
        if #skipped > 0 then print("   not priced by the kit: " .. table.concat(skipped, ", ")) end
        print("")
        Restore()
    end
    -- back to the druid the harness logged in
    S.units.player.class = "DRUID"; S.level = 70
    MD:DetectProfile(); MD:Fire("CORE_LOGIN")
end
if fit and #classSpread > 0 then
    local three = 0
    for _, x in ipairs(classSpread) do if x.n >= 3 then three = three + 1 end end
    print(string.format("%d class parses (%d with three families or more):", #classSpread, three))
    for _, x in ipairs(classSpread) do
        print(string.format("   %-34s %d families, spread %.0f%%", x.key, x.n, x.spread * 100))
    end
end
if fit and #ratios > 0 then
    table.sort(ratios)
    print(string.format("%d parses; implied +healing / the log's spellPower: min %.2f, median %.2f, max %.2f",
        #ratios, ratios[1], ratios[math.ceil(#ratios / 2)], ratios[#ratios]))
end
