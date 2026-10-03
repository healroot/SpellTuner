-- Diagnostics (TBC TOC only): in-game verification (/md verify) -- diff the
-- static SpellData table against whatever the live client exposes, and dump
-- the regen/healing inputs so formulas can be checked by hand before any
-- number is trusted -- plus the input snapshot, /md profile, /md export and
-- /md calibrate.
--
-- T56 (P12, review A2): moved out of Verify.lua unchanged. The instruments
-- (/md fsrtest, /md regentest, /md spamtest) are Engine/RegenMeasure.lua, the
-- engine's shipped self-tests (/md simrun, /md simreplay) Engine/SimSelfTest.lua,
-- and the review commands (/md coach, /md coachrun, the validation report)
-- Engine/ReviewCommands.lua.
local _, MD = ...

function MD:RunVerify()
    local SD = MD.SpellData
    MD:Print("-- verify: static data vs live client --")
    local mismatches, checkedCost, checkedCast = 0, 0, 0

    local ids = {}
    for id in pairs(SD.spells) do ids[#ids + 1] = id end
    table.sort(ids)

    for _, id in ipairs(ids) do
        local s = SD.spells[id]
        local name, _, _, castMs = GetSpellInfo(id)
        local label = string.format("%s R%d (%d)", s.family, s.rank, id)

        if not name then
            mismatches = mismatches + 1
            MD:Print("|cffff4444MISSING|r " .. label .. " - spellID unknown to this client")
        else
            -- cast time (GetSpellInfo returns milliseconds)
            if s.cast and castMs and castMs > 0 then
                checkedCast = checkedCast + 1
                -- Compare against what the model expects, not the raw table:
                -- Naturalist and a cast-time idol are known. (The first
                -- regression log reported 13 "mismatches", all Naturalist.)
                -- The live value may sit UNDER the 1.5s GCD floor the model
                -- applies (HT R1 reads 1.0s with Naturalist 5); that is fine.
                local expect = s.cast
                if s.family == "HealingTouch" then
                    expect = expect - 0.1 * MD:TalentRank("Naturalist")
                    local relic = SD:Relic()
                    if relic and relic.castReduce and relic.family == s.family then
                        expect = expect - relic.castReduce
                    end
                end
                if math.abs(castMs / 1000 - expect) > 0.01 then
                    mismatches = mismatches + 1
                    MD:Print(string.format("|cffffaa33CAST|r %s: table %.1fs%s, live %.1fs",
                        label, s.cast, expect ~= s.cast and string.format(" (model %.1fs)", expect) or "",
                        castMs / 1000))
                end
            end
            -- mana cost: the live value is what the model uses; the static
            -- table (with talent modifiers) should agree with it.
            local live = SD:LiveCost(id)
            local static = SD:StaticCost(id)
            if live ~= nil and static ~= nil then
                checkedCost = checkedCost + 1
                if live ~= static then
                    mismatches = mismatches + 1
                    MD:Print(string.format("|cffffaa33COST|r %s: static %d (base %d), live %d (used)",
                        label, static, s.cost, live))
                end
            end
        end
    end

    if checkedCost == 0 then
        MD:Print("|cffffaa33GetSpellPowerCost unavailable|r - the static table is in use; costs must be verified " ..
            "by hand (cast each rank at full idle mana and read the drop; compare to the table).")
    end
    MD:Print(string.format("checked %d cast times, %d costs - %d mismatch(es).",
        checkedCast, checkedCost, mismatches))

    -- Spells outside the healing model, by what they were for (v0.10.1). The
    -- ones that come back "unknown" are the author's list to correct: a wrong
    -- or missing row in Data/DruidSpells.lua costs a label, never a number.
    local unknown = {}
    for id in pairs(MD.Spend.unknown) do unknown[#unknown + 1] = id end
    if #unknown > 0 then
        table.sort(unknown)
        local by = { damage = {}, cc = {}, utility = {}, shift = {}, unknown = {} }
        for _, id in ipairs(unknown) do
            local family, kind = MD:ClassifyCast(id)
            local list = by[kind] or by.unknown
            list[#list + 1] = (family or GetSpellInfo(id) or "?") .. " (" .. id .. ")"
        end
        for _, kind in ipairs({ "damage", "cc", "utility", "shift", "unknown" }) do
            if #by[kind] > 0 then
                MD:Print(string.format("%s spells outside the healing model: %s",
                    kind == "unknown" and "|cffff9966unclassified|r" or kind,
                    table.concat(by[kind], ", ")))
            end
        end
    end

    MD:Print("-- input snapshot --")
    for _, line in ipairs(MD:Snapshot()) do MD:Print(line) end
    MD:Print("For the FSR anchor: stand idle at partial mana, run /md fsrtest, cast ONE " ..
        "Healing Touch, and watch which tick sizes appear when. For Dreamstate: /md regentest.")
end

--------------------------------------------------------------------------------
-- Every model input in one block. /md verify prints it, /md profile copies it,
-- and both therefore always agree. Returns an array of plain strings (no
-- colour escapes, so it survives a paste).
--------------------------------------------------------------------------------
function MD:Snapshot()
    local SD = MD.SpellData
    local RM = MD.Regen
    local out = {}
    local function add(fmt, ...)
        out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    end

    if GetManaRegen then
        add("GetManaRegen: base %.2f/s, casting %.2f/s (x5 = %d / %d mp5)",
            RM.apiBase, RM.apiCasting, RM.apiBase * 5 + 0.5, RM.apiCasting * 5 + 0.5)
        if RM.unreported > 0 then
            add("model adds %.2f/s the API omits (%d mp5: Dreamstate %d, measured %d) -> base %.2f/s, casting %.2f/s",
                RM.unreported, RM.unreported * 5 + 0.5, RM.dreamstate * 5 + 0.5, RM.measured * 5 + 0.5,
                RM.base, RM.casting)
        end
        local m = MD.cdb and MD.cdb.mp5
        if m then
            add("measured mp5: %d (%.2f/s) from %s on %s, %d beat(s)%s", m.mp5 or 0, m.perSec or 0,
                m.source or "?", date("%Y-%m-%d %H:%M", m.at or 0), m.ticks or 0,
                m.hint and (" at " .. m.hint) or "")
        else
            add("measured mp5: none - run /md regentest solo to measure the beat the API omits")
        end
        local drinking = MD:HasBuff("Drink") or MD:HasBuff("Refreshment") or MD:HasBuff("Food & Drink")
        add("drink buff up: %s; observed OOC fill %.2f/s (FSR duty %d%%)",
            drinking and "yes" or "no", RM:ObservedFill(), RM:Duty() * 100)
    end

    local spirit = UnitStat("player", 5) or 0
    local intellect = UnitStat("player", 4) or 0
    local spiritPerSec, mp5Gear, inFSRFrac = RM:Components()
    add("spirit %d, int %d -> spirit share %.2f/s (%d mp5), gear/buffs ~%d mp5, in-5SR fraction %d%%",
        spirit, intellect, spiritPerSec, spiritPerSec * 5 + 0.5, mp5Gear, inFSRFrac * 100)

    if GetSpellBonusHealing then
        local ok, v = pcall(GetSpellBonusHealing)
        add("+healing: " .. (ok and tostring(v) or "unavailable") ..
            (MD:InTreeForm() and string.format(" (Tree of Life form: +%d aura on party targets = 25%% of %d spirit%s)",
                0.25 * spirit, spirit, (MD.db.treeAura == false) and ", NOT counted (setting off)" or "")
             or " (not in Tree form)"))
    end
    if GetSpellCritChance then
        local ok, v = pcall(GetSpellCritChance, 4)
        add("nature crit: %s%%", ok and string.format("%.1f", v) or "unavailable")
    end
    add("talents: " .. MD:TalentSummary())

    local relic, relicID, relicName = SD:Relic()
    if relicID then
        if relic then
            local what = relic.flat and string.format("+%d %s", relic.flat, relic.family)
                or relic.perTick and string.format("+%d per %s tick", relic.perTick, relic.family)
                or relic.castReduce and string.format("-%.2fs %s cast", relic.castReduce, relic.family)
                or relic.cost and string.format("-%d mana on %s (live cost already includes it)", relic.cost, relic.family)
                or relic.aura and string.format("+%d Tree of Life aura", relic.aura) or "?"
            add("relic: %s (%d) - %s%s", relic.name, relicID, what,
                relic.verify and " [value from a database tooltip, not yet measured - calibration will say]" or " [measured]")
        else
            add("relic: %s (%d) - NOT in the relic table (tell the author what it does)", relicName or "?", relicID)
        end
    else
        add("relic: none equipped")
    end

    if MD.Overheal then
        local oh = MD.Overheal:Summary()
        if #oh > 0 then
            add("overheal (combat log, per character):")
            for _, line in ipairs(oh) do add("  " .. line) end
        else
            add("overheal: no samples yet")
        end
        add("combat log 'amount' convention: %s", MD.db.healAmountGross == nil and "not yet latched"
            or (MD.db.healAmountGross and "GROSS (includes overheal)" or "NET (excludes overheal)"))
    end

    if MD.Calibration then
        add("calibration (observed / model, non-crit events):")
        for _, line in ipairs(MD.Calibration:Report()) do add("  " .. line) end
    end

    local hist = MD.fightHistory or {}
    add("recorded fights: %d", #hist)
    for i = math.max(1, #hist - 4), #hist do
        local f = hist[i]
        add("  [%s] %s", f.zone or "?", (f.summary or "-"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end
    return out
end

--------------------------------------------------------------------------------
-- /md profile: every model input in one copyable block. This is the bug report
-- -- chat-spamming forty lines is not one, a Ctrl+C box is, so it goes straight
-- into the debug console's copy popup.
--------------------------------------------------------------------------------
function MD:Profile()
    local SD = MD.SpellData
    local out = {}
    local function add(fmt, ...)
        out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    end

    local _, build, _, iface = GetBuildInfo()
    add("=== SpellTuner v%s profile ===", MD.version)
    add("client build %s, interface %s, ElvUI %s", tostring(build), tostring(iface),
        ElvUI and "present" or "absent")
    add("%s, %s level %d, form: %s, mana %d/%d", MD.player.charKey, MD.player.class,
        MD.player.level, MD:InTreeForm() and "Tree of Life" or "caster / other",
        UnitPower("player", 0) or 0, UnitPowerMax("player", 0) or 0)

    add("")
    add("--- inputs ---")
    for _, line in ipairs(MD:Snapshot()) do add(line) end

    add("")
    add("--- costs of known max ranks ---")
    -- T99 (docs/SPEC-next.md 4.4): the max ranks are the rank table's, the
    -- class profile's `rankTable` capability. T123: read through
    -- RankMath:Source() -- Data/SpellData.lua for the druid, the class's book
    -- (Spells/Book_TBC.lua) for a priest, shaman or paladin, whose read cost
    -- is its static one; `--` where a source has none
    local canRank, why = MD.ClassProfile:Can("rankTable")
    if canRank then
        local RSD = MD.RankMath and MD.RankMath:Source() or SD
        for _, family in ipairs(RSD.familyOrder) do
            local id = RSD.maxRank[family]
            if id then
                local spell = RSD.spells[id]
                local live = RSD:LiveCost(id)
                local static = RSD:StaticCost(id)
                add("%s R%d (%d): live %s, static %s, cast %.1fs",
                    family, spell.rank, id, tostring(live), static ~= nil and tostring(static) or "--",
                    spell.cast or 1.5)
            end
        end
    else
        add("(%s)", MD.Profiles.Refusal("rankTable", why, "rank table"))
    end

    add("")
    add("--- clock ---")
    local st = MD:GetManaState()
    if st then
        add("mode %s, tto %s, ttf %s, rest %s, shown \"%s\"", st.mode,
            st.tto and string.format("%.0fs", st.tto) or "-",
            st.ttf and string.format("%.0fs", st.ttf) or "-",
            st.rest and string.format("%.0fs", st.rest) or "-",
            (MD:GetDisplayString():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
        add("spend %.2f +- %.2f mana/s (%d casts, cv %.2f, half-life %ds), regen %.2f/s (duty %d%%)",
            st.spend, st.sigma, st.casts, st.cv, MD.db.halfLife or 15, st.regen, st.duty * 100)
        if st.cd then
            add("mana cooldown: %s worth %d mana%s", st.cd.name, st.cd.delta,
                st.cd.tto and string.format(" -> OOM %.0fs", st.cd.tto) or "")
        end
    else
        add("(no state yet)")
    end
    local unknown = {}
    for id in pairs(MD.Spend.unknown) do unknown[#unknown + 1] = id end
    if #unknown > 0 then
        table.sort(unknown)
        local names = {}
        for _, id in ipairs(unknown) do
            names[#names + 1] = (GetSpellInfo(id) or "?") .. " (" .. id .. ")"
        end
        add("unpriced spells this session: %s", table.concat(names, ", "))
    end

    add("")
    add("--- settings ---")
    local keys = {}
    for k, v in pairs(MD.db) do
        if k ~= "char" and k ~= "pos" and k ~= "optionsPos" and k ~= "debug" and type(v) ~= "table" then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = k .. "=" .. tostring(MD.db[k])
    end
    add(table.concat(parts, "  "))
    local cats = {}
    for k, v in pairs(MD.db.debug.categories) do
        if v then cats[#cats + 1] = k end
    end
    table.sort(cats)
    add("debug: enabled=%s, keep %d lines, categories: %s",
        tostring(MD.db.debug.enabled), MD.db.debug.maxLines or 1000, table.concat(cats, " "))
    if MD.sim and next(MD.sim) then
        local sim = {}
        for k, v in pairs(MD.sim) do sim[#sim + 1] = k .. "=" .. tostring(v) end
        table.sort(sim)
        add("SIMULATION ACTIVE: %s", table.concat(sim, " "))
    end

    return out
end

function MD:RunProfile()
    local lines = MD:Profile()
    if MD.ShowCopyPopup then
        MD:ShowCopyPopup("SpellTuner profile", table.concat(lines, "\n"))
        MD:Print("profile ready - Ctrl+C in the box to copy it.")
    else
        for _, line in ipairs(lines) do MD:Print(line) end
    end
    MD:Debug("other", "profile dumped (%d lines)", #lines)
end

--------------------------------------------------------------------------------
-- /md export: machine-readable TSV for analysis (fights, overheal buckets,
-- roster, calibration when present). Tabs, no quoting: the first dungeon log
-- was analysed by regexing prose, which is how the analyst wants to stop.
--------------------------------------------------------------------------------
-- One recorded stream, dumped verbatim: the parallel arrays as they are, one
-- event per row. This is the raw material for offline replay, so it is not
-- summarised -- a summary of a stream is what the Review tab is for. Shared by
-- the ring of 8 and (v0.9.1) by every pull of a run, which passes `extra` to
-- say which run and which pull the stream belongs to.
local function DumpRecording(add, r, n, extra)
    add("# recording " .. n, r.id or "", r.zone or "",
        string.format("%.1f", r.dur or 0), "pool " .. (r.pool or 0),
        (r.ownCasts or 0) .. " casts", (r.spent or 0) .. " mana",
        string.format("foreign %.0f%%", (r.foreignShare or 0) * 100),
        r.truncated and "TRUNCATED" or "", r.pinned and "pinned" or "",
        (r.auraN or 0) .. " auras" .. (r.auraTruncated and " (debuffs truncated)" or ""),
        extra or "")
    add("# roster")
    add("idx", "name", "class", "role", "roleSource", "maxHP", "tracked")
    local trackedSet = {}
    for _, idx in ipairs(r.tracked or {}) do trackedSet[idx] = true end
    for i, e in ipairs(r.roster or {}) do
        add(i, e.name or "", e.class or "", e.role or "", e.roleSource or "",
            e.maxHP or -1, trackedSet[i] and "y" or "")
    end
    local init = r.initial or {}
    add("# initial", "mana " .. (init.mana or 0), "base " .. (init.apiBase or 0),
        "casting " .. (init.apiCasting or 0), init.form or "?")
    for _, a in ipairs(init.auras or {}) do
        add("aura", a.target, a.spellID, a.stacks, string.format("%.1f", a.remaining or 0))
    end
    for _, b in ipairs(init.buffs or {}) do
        add("buff", b.spellID or 0, b.name or "", string.format("%.1f", b.remaining or 0))
    end
    add("# precasts")
    add("t", "spellID", "cost", "tgt", "hpAtCast", "form")
    for _, c in ipairs(r.precasts or {}) do
        add(string.format("%.2f", c[1]), c[2], c[3], c[4],
            string.format("%.3f", c[5] or -1), c[6])
    end
    add("# ev")
    add("t", "kind", "tgt", "amt", "x")
    local ev = r.ev or {}
    for i = 1, #(ev.t or {}) do
        add(string.format("%.2f", ev.t[i]), ev.kind[i], ev.tgt[i],
            string.format("%.0f", ev.amt[i] or 0), ev.x[i])
    end
    add("# hp")
    local hp = r.hp or {}
    local head = { "t" }
    for _, idx in ipairs(r.tracked or {}) do head[#head + 1] = "hp" .. idx end
    for _, idx in ipairs(r.tracked or {}) do head[#head + 1] = "max" .. idx end
    add(unpack(head))
    for i = 1, #(hp.t or {}) do
        local row = { string.format("%.1f", hp.t[i]) }
        for _, idx in ipairs(r.tracked or {}) do row[#row + 1] = hp.hp[idx][i] or -1 end
        for _, idx in ipairs(r.tracked or {}) do row[#row + 1] = hp.max[idx][i] or -1 end
        add(unpack(row))
    end
    add("# mana")
    add("t", "v", "base", "cast")
    local mn = r.mana or {}
    for i = 1, #(mn.t or {}) do
        add(string.format("%.1f", mn.t[i]), mn.v[i],
            string.format("%.2f", mn.base[i] or 0), string.format("%.2f", mn.cast[i] or 0))
    end
end

function MD:Export()
    local out = {}
    local function add(...) out[#out + 1] = table.concat({ ... }, "\t") end
    add("# manademon " .. MD.version, MD.player.charKey, MD.player.class .. " " .. MD.player.level,
        date("%Y-%m-%d %H:%M"), MD.db.healAmountGross == nil and "amount:unknown"
            or (MD.db.healAmountGross and "amount:gross" or "amount:net"))

    add("# fights")
    add("t", "zone", "dur", "spent", "netMp5", "healed", "overhealed", "oomAt")
    for _, f in ipairs(MD.fightHistory or {}) do
        add(f.t or "", f.zone or "", string.format("%.1f", f.duration or 0),
            string.format("%.0f", (f.avgSpendRate or 0) * (f.duration or 0)),
            string.format("%.0f", f.netMp5 or 0), f.healed or "", f.overhealed or "",
            f.oomAt and string.format("%.1f", f.oomAt) or "")
    end

    if MD.Overheal and MD.Overheal.stats then
        add("# overheal")
        add("key", "n", "healed", "overhealed")
        local keys = {}
        for k in pairs(MD.Overheal.stats) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local st = MD.Overheal.stats[k]
            add(k, st.n, string.format("%.0f", st.h), string.format("%.0f", st.o))
        end
    end

    if MD.Targets then
        add("# roster")
        add("name", "class", "role", "roleSource", "kind")
        for _, row in ipairs(MD.Targets:ExportRows()) do out[#out + 1] = row end
    end

    -- Recorded streams (v0.7.2), the ring of 8.
    if MD.FightRecorder then
        for n, r in ipairs(MD.FightRecorder:List()) do DumpRecording(add, r, n) end
    end

    -- Runs (v0.9.1): the container, then every pull it kept. The run's own
    -- arrays are the GAPS -- mana across the whole run, the drinks with the mana
    -- either side of them, deaths, zone changes -- which is the half a single
    -- fight's stream cannot hold.
    if MD.RunRecorder then
        local RR = MD.RunRecorder
        for n, run in ipairs(RR:List()) do
            local st = run.stats or {}
            add("# run " .. n, run.id or "", run.name or "", run.zone or "",
                string.format("%.1f", run.dur or 0), "pool " .. (run.pool or 0),
                (st.pulls or 0) .. " pulls", (st.recorded or 0) .. " recorded",
                string.format("combat %.0f%%", (st.combatPct or 0) * 100),
                (st.drinks or 0) .. " drinks", st.drinkRate and string.format("%.1f mana/s", st.drinkRate) or "no rate",
                (st.deaths or 0) .. " deaths", (st.spent or 0) .. " mana",
                run.truncated and "TRUNCATED" or "", run.pinned and "pinned" or "",
                run.stopReason or "")
            add("# run ev")
            add("t", "kind", "name", "a", "b")
            local ev = run.ev or {}
            for i = 1, #(ev.t or {}) do
                add(string.format("%.1f", ev.t[i]), ev.kind[i],
                    RR.KIND_NAMES[ev.kind[i]] or "?", string.format("%.0f", ev.a[i] or 0),
                    string.format("%.3f", ev.b[i] or 0))
            end
            add("# run mana")
            add("t", "v")
            local mn = run.mana or {}
            for i = 1, #(mn.t or {}) do add(string.format("%.1f", mn.t[i]), mn.v[i]) end
            for k, pull in ipairs(run.pulls or {}) do
                DumpRecording(add, pull, k, string.format("run %s pull %d%s", tostring(run.id), k,
                    pull.short and " short" or ""))
            end
        end
    end

    if MD.Calibration and MD.Calibration.ExportRows then
        add("# calibration")
        add("spellID", "kind", "n", "obs", "pred")
        for _, row in ipairs(MD.Calibration:ExportRows()) do out[#out + 1] = row end
    end
    return out
end

function MD:RunCalibrate()
    if not MD.Calibration then return end
    local lines = MD.Calibration:Report()
    if MD.ShowCopyPopup then
        MD:ShowCopyPopup("SpellTuner calibration: model vs your heals", table.concat(lines, "\n"))
        MD:Print("calibration table ready - a ratio of 1.000 means the model matched the server exactly.")
    else
        for _, line in ipairs(lines) do MD:Print(line) end
    end
end

function MD:RunExport()
    local lines = MD:Export()
    if MD.ShowCopyPopup then
        MD:ShowCopyPopup("SpellTuner export (TSV)", table.concat(lines, "\n"))
        MD:Print(string.format("export ready (%d lines) - Ctrl+C in the box.", #lines))
    else
        for _, line in ipairs(lines) do MD:Print(line) end
    end
end
