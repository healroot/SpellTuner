-- tools/reportlines.lua -- the `report N|pN` command of tools/import.lua, both
-- clients (2026-09-30; it was tools/practicereport.lua's, folded in when the
-- two report tools became one). Not run on its own:
--
--   local Report = dofile(here .. "/reportlines.lua")
--   for _, line in ipairs(Report(MD, rec, kit)) do print(line) end
--
-- The fight replayed through the engine (what you played) beside every
-- strategy in SP.STRATEGY_SET on the same fight, all at expected crits: mana
-- spent, regenerated, USED (what left the pool -- the score's mana term), at
-- the end, still owed (the health left missing, priced at the best heal per
-- mana the plan's binds buy), deaths, seconds one hit from death, the lowest
-- health, casts and the lowest mana. `kit` is the one the fight is replayed
-- with; import.lua has already chosen it and printed which.
return function(MD, rec, kit)
    local SM, SP = MD.SimModel, MD.SimPlanner
    local lines = {}
    local function Add(fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
    local function Strip(s)
        return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "|"))
    end

    local v = SM:Validate(rec, kit)
    Add("gates: %s", v and (v.ok and "PASS" or "FAIL") or "?")
    for _, g in ipairs(v and v.gates or {}) do
        if not g.ok then Add("  %s: %s", g.name, Strip(g.text or "")) end
    end
    local sc = SM.ScenarioFromRecording(rec, kit)
    local function Row(name, r, plan)
        local owed = plan and SP.ManaOwed(r, plan) or 0
        Add("%-34s %5.0f %5.0f %5.0f %5.0f %5.0f %2d %5.1f %4.0f%% %3d %4.0f",
            name, r.manaSpent or 0, r.regenGained or 0, SP.ManaUsed(r), r.manaEnd or 0, owed,
            r.deaths and r.deaths.n or 0, r.floorSeconds or 0, (r.lowest and r.lowest.hp or 1) * 100,
            r.casts or 0, r.lowestMana or 0)
    end
    Add("%-34s %5s %5s %5s %5s %5s %2s %5s %5s %3s %4s", "", "spent", "regen", "used",
        "end", "owed", "dd", "floor", "low", "cst", "lowM")
    local binds = SP.MaxRankBinds(rec.initial and rec.initial.known)
    -- what you still owe is priced like every row's: at the best heal per mana
    -- the same binds buy (SP.ManaOwed)
    Row("you (the replay)", SM:Run(sc, nil, { critMode = "ev" }), SP.NewPlan(binds, {}, kit))
    for _, entry in ipairs(SP.STRATEGY_SET) do
        local plan = SP.MakeStrategy(entry, binds, kit, { scenario = sc, seed = rec.id or 1 })
        if plan then Row(entry.label, SP.RunPlan(sc, plan, { critMode = "ev" }), plan) end
    end
    Add("pool %d; used = what left the pool (start - end, plus the regen a rule still running at the end " ..
        "has yet to cost)", sc.pool or 0)
    return lines
end
