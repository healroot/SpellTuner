-- tools/run.sh tools/simcheck.lua [--curve]
--
-- Runs the simulation engine's self-tests and the BF-1 fixture replay outside
-- the game. --curve additionally prints the simulated mana curve next to the
-- one the log recorded, which is how the sample-ordering bug in the first cut
-- of Engine/SimModel.lua was found.
--
-- T47 (Q3): the self-tests' and the fixture's verdicts are read back, the
-- standard footer is printed last, and the exit code is 1 on any failure (it
-- was 0 whatever the engine said).
local here = arg[0]:match("^(.*)/[^/]+$")
local root = arg[1] or "."
local curve = false
for i = 1, #arg do if arg[i] == "--curve" then curve = true end end

HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]
arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

print("== /md simrun ==")
local tests, simFails = MD:RunSimRun()
print("== /md simreplay fixture ==")
local replayPass = MD:RunSimReplay("fixture")

if curve then
    local fx = MD.SimFixtures.BF1
    local SM, RM = MD.SimModel, MD.RankMath
    local sampleT, sampleM = {}, {}
    for i, m in ipairs(fx.mana) do sampleT[i], sampleM[i] = m[1], m[2] end
    local targets = {}
    for i, r in ipairs(fx.roster) do
        targets[i] = { name = r.name, maxHP = 10000, hp0 = 10000, tracked = false }
    end
    local sc = { dur = fx.dur, pool = fx.pool, initial = fx.initial, targets = targets,
                 forms = fx.forms, sampleT = sampleT, kit = RM:SpellKit() }
    local r = SM:Run(sc, SM.ScriptPlan(fx.casts))
    print(string.format("%6s %8s %8s %8s", "t", "log", "sim", "delta"))
    for i = 1, #sampleT do
        print(string.format("%6.2f %8d %8.0f %+8.0f", sampleT[i], sampleM[i],
            r.manaCurve[i] or -1, (r.manaCurve[i] or 0) - sampleM[i]))
    end
end

-- T47 (Q3): the footer, last. Each simrun test is one assertion and the
-- fixture replay one more; no test at all is a failure, not a pass.
tests, simFails = tests or 0, simFails or 0
local okCount = (tests - simFails) + (replayPass and 1 or 0)
local failCount = simFails + (replayPass and 0 or 1) + (tests == 0 and 1 or 0)
print(string.format("\n%d ok, %d failed", okCount, failCount))
if simFails > 0 then print("FAIL: " .. simFails .. " engine self-test(s)") end
if tests == 0 then print("FAIL: no engine self-test ran") end
if not replayPass then print("FAIL: the BF-1 fixture replay") end
os.exit(failCount == 0 and 0 or 1)
