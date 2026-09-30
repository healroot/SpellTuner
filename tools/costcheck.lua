-- tools/run.sh tools/costcheck.lua
--
-- T45 (P1, review Q15): the live-cost branch. The TBC stub answers
-- GetSpellPowerCost with nil for every druid heal (S.liveCosts), so
-- Data/SpellData.lua's static table is what every other suite prices with --
-- and SD:GetCost's live branch, the one the anniversary client actually takes
-- (verified 2026-09-03), never ran offline. This sets a live cost for one druid
-- heal and holds the three things that depend on it: GetCost prefers the live
-- value, falls back to the static table when the client says nothing, and
-- /md verify prints a COST line when the two disagree.
HARNESS_FLAVOUR = "tbc"

local here = arg[0]:match("^(.*)/[^/]+$")
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB
local SD = MD.SpellData

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-66s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

-- Healing Touch rank 1: a row in the static table (base cost 25), and not one
-- of the ids the stub already answers live.
local ID = 5185
local static = SD:StaticCost(ID)
local LIVE = (static or 0) + 7 -- a value the static maths cannot produce

-- 1: the live branch. The client's answer wins, and GetCost says where it came from.
do
    S.liveCosts[ID] = LIVE
    local cost, src = SD:GetCost(ID)
    check("a live cost for a druid heal is what GetCost answers (api)",
        cost == LIVE and src == "api" and static ~= nil and LIVE ~= static,
        string.format("cost=%s src=%s live=%s static=%s", tostring(cost), tostring(src),
            tostring(LIVE), tostring(static)))
end

-- 2: the fallback. With no live answer the static table (talent maths applied) is used.
do
    S.liveCosts[ID] = nil
    local cost, src = SD:GetCost(ID)
    check("with no live cost GetCost falls back to the static table",
        cost == static and src == "table",
        string.format("cost=%s src=%s static=%s", tostring(cost), tostring(src), tostring(static)))
end

-- 3: /md verify's diff line. Live and static disagree for this rank: one COST
-- line naming it, the static figure, its base and the live one marked used.
do
    S.liveCosts[ID] = LIVE
    local lines = {}
    local origPrint = MD.Print
    MD.Print = function(self, msg) lines[#lines + 1] = tostring(msg) end
    local okRun, err = pcall(MD.RunVerify, MD)
    MD.Print = origPrint
    S.liveCosts[ID] = nil
    local want = string.format("COST|r HealingTouch R1 (%d): static %d (base %d), live %d (used)",
        ID, static or -1, SD.spells[ID].cost, LIVE)
    local hits = 0
    for _, l in ipairs(lines) do
        if l:find(want, 1, true) then hits = hits + 1 end
    end
    check("/md verify prints the COST line for a live cost that disagrees",
        okRun and hits == 1,
        (not okRun) and tostring(err) or string.format("hits=%d of %d lines, want %q", hits, #lines, want))
end

print("")
print(string.format("%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
