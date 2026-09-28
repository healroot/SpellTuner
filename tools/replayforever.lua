-- tools/run.sh tools/replayforever.lua
--
-- T16a (docs/tasks/T16a-replay-window.md): the replay window plays a Forever
-- (v3) recording -- the window's three commands (/st replay, /st coach,
-- /st validate), the actual column against T13d's health reconstruction
-- (Modules/SpellTuner_Replay/Scenario_Forever.lua's SM.RecordedHp, T16a),
-- the ticks it draws, the reconstructed/estimated line, the suggested
-- column once the search finishes, seeking, ASCII/no-bare-pipe on every
-- painted or printed string, and the in-combat refusal. Forever only, on
-- two tools/foreverfixture.lua streams.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-95s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB
S.crit[4] = 0 -- zero Nature crit: the own-heal amounts the fixture records are the engine's own exact figures

local function CapturedChat(body)
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    body()
    frame.AddMessage = orig
    return lines
end

--------------------------------------------------------------------------------
-- 1: the replay commands exist only with the Replay module on
--------------------------------------------------------------------------------
-- ToggleReplay (UI/ReplayWindow.lua) is nil until the module loads; the
-- fallback dispatch must not raise on "/st replay 1" before that either.
local beforeIsNil = (MD.ToggleReplay == nil)
CapturedChat(function() SlashCmdList.SPELLTUNER("replay 1") end) -- would have raised, unguarded, if a command existed early

MD:SetModule("SpellTuner_Replay", true) -- loads Recorder (a dependency), Kit/Scenario/Gates, the engine chain, the window and this module's own commands

check("the replay commands exist only with the Replay module on",
    beforeIsNil and type(MD.ToggleReplay) == "function" and MD.SimPlanner ~= nil,
    "beforeIsNil=" .. tostring(beforeIsNil) .. " afterToggle=" .. tostring(MD.ToggleReplay))

local buildFixture = dofile(here .. "/foreverfixture.lua")
local SM, SP = MD.SimModel, MD.SimPlanner
local kit = MD.RankMath:SpellKit()

-- Recording 1 ("good"): the default fixture, own-heal amounts placed at the
-- engine's own exact figures (crit forced to 0), its own meter reading.
local recGood = buildFixture()
recGood.id = 2000000000
-- Recording 2 ("bad"): no damage meter reading at all -- fails foreign
-- healing / model calibrated / heals attributed outright (Gates_Forever.lua).
local recBad = buildFixture({ meterOverridden = true })
recBad.id = 1000000000
MD.cdb.recordings = { recGood, recBad }

--------------------------------------------------------------------------------
-- 2: /st replay opens a v3 recording with one row per tracked target
--------------------------------------------------------------------------------
SlashCmdList.SPELLTUNER("replay 1")
local W = MD.Replay._state()
check("/st replay opens a v3 recording with one row per tracked target",
    W.frame and W.frame:IsShown() and #W.rows == 2, tostring(W.frame and W.frame:IsShown()) .. " " .. tostring(#W.rows))

--------------------------------------------------------------------------------
-- 3: the actual column plays to the end and its bars follow the
--    reconstructed health
--------------------------------------------------------------------------------
local recon = SM.RecordedHp(recGood)
local lastIdx = #recon.hp[2]
local wantFrac = recon.max[2][lastIdx] > 0 and (recon.hp[2][lastIdx] / recon.max[2][lastIdx]) or 0

MD.Replay._setPlaying(true)
local frames = 0
while MD.Replay._state().playing and frames < 4000 do S.Tick(0.1); frames = frames + 1 end
local tankFrac = W.left.frames[2].bar:GetValue()
check("the actual column plays to the end and its bars follow the reconstructed health",
    not MD.Replay._state().playing and math.abs(tankFrac - wantFrac) <= 0.02,
    string.format("played=%s bar=%.3f recon=%.3f", tostring(not MD.Replay._state().playing), tankFrac, wantFrac))

--------------------------------------------------------------------------------
-- 4: the reconstructed health is drawn as the left column's ticks
--------------------------------------------------------------------------------
local ticks = W.rp.ticks
local tickCol = ticks and ticks.hp[2]
local wantTick = recon.hp[2][lastIdx] / recon.max[2][lastIdx]
check("the reconstructed health is drawn as the left column's ticks",
    type(tickCol) == "table" and #tickCol == #recon.t and math.abs(tickCol[lastIdx] - wantTick) < 1e-6,
    string.format("tickCol=%s", tostring(tickCol and tickCol[lastIdx])))

--------------------------------------------------------------------------------
-- 5: the window says the health is reconstructed and a party max is
--    estimated (the tank's is secret in the fixture)
--------------------------------------------------------------------------------
local reconText = W.reconFS and W.reconFS:GetText() or ""
check("the window says the health is reconstructed and a party max is estimated",
    reconText:find("reconstructed", 1, true) ~= nil and reconText:find("estimated", 1, true) ~= nil,
    reconText)

--------------------------------------------------------------------------------
-- 6: the suggested column fills in when the coach's search finishes
--------------------------------------------------------------------------------
assert(W.right.state == nil, "expected no suggested column before coaching")
SlashCmdList.SPELLTUNER("coach 1 force")
local cframes = 0
while MD.coachSearch and cframes < 20000 do S.Tick(0.016); cframes = cframes + 1 end
assert(MD.coachSearch == nil, "coach search never finished (" .. cframes .. " frames)")
SlashCmdList.SPELLTUNER("replay 1")
W = MD.Replay._state()
check("the suggested column fills in when the coach's search finishes",
    W.right ~= nil and W.right.state ~= nil and W.rp.right ~= nil)

--------------------------------------------------------------------------------
-- 7: seeking gives the same picture as playing to that moment
--------------------------------------------------------------------------------
local dur = W.left.state.dur
local seekT = math.max(0, dur - 4)
MD.Replay._seek(seekT)
local seekFrac = W.left.frames[2].bar:GetValue()
SlashCmdList.SPELLTUNER("replay 1")
W = MD.Replay._state()
MD.Replay._setPlaying(true)
local pframes = 0
while MD.Replay._state().playing and W.left.state.t < seekT - 1e-6 and pframes < 4000 do
    S.Tick(0.1); pframes = pframes + 1
end
MD.Replay._setPlaying(false)
local playedFrac = W.left.frames[2].bar:GetValue()
check("seeking gives the same picture as playing to that moment",
    math.abs(seekFrac - playedFrac) < 0.02,
    string.format("seek=%.3f played=%.3f", seekFrac, playedFrac))

--------------------------------------------------------------------------------
-- 8: /st validate prints the Forever gates and /st coach refuses a failing
--    fight unless forced
--------------------------------------------------------------------------------
local vlines = CapturedChat(function() SlashCmdList.SPELLTUNER("validate 2") end)
local sawVerdict, sawGate = false, false
for _, l in ipairs(vlines) do
    if l:find("verdict:", 1, true) then sawVerdict = true end
    if l:find("foreign healing", 1, true) or l:find("model calibrated", 1, true) then sawGate = true end
end
local clines = CapturedChat(function() SlashCmdList.SPELLTUNER("coach 2") end)
local refused = false
for _, l in ipairs(clines) do
    if l:find("does not replay", 1, true) or l:find("nothing to suggest", 1, true) then refused = true end
end
check("/st validate prints the Forever gates and /st coach refuses a failing fight unless forced",
    sawVerdict and sawGate and refused,
    "validate: " .. table.concat(vlines, " / ") .. "   coach: " .. table.concat(clines, " / "))

--------------------------------------------------------------------------------
-- 9: every string the window paints is ASCII with no bare pipe -- a fixture
--    target named with a non-ASCII byte and a "|" (T14 review)
--------------------------------------------------------------------------------
local recBadName = buildFixture()
recBadName.id = 3000000000
recBadName.roster[2].name = "Tank\195\169|boss" -- an EU-style byte plus a bare pipe
MD.cdb.recordings = { recBadName, recGood, recBad }
SlashCmdList.SPELLTUNER("replay 1")
W = MD.Replay._state()
MD.Replay._setPlaying(true)
local aframes = 0
while MD.Replay._state().playing and aframes < 4000 do S.Tick(0.1); aframes = aframes + 1 end

local function Pipes(s)
    -- a color code, a reset, and Esc's own "||" (a literal pipe, doubled so
    -- the client renders one rather than eating what follows) are all safe;
    -- anything left over is a BARE pipe.
    local stripped = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "")
    return stripped:find("|", 1, true) ~= nil
end
local function NonAscii(s)
    return s:find("[^ -~]") ~= nil
end
local bad = {}
local function Scan(label, s)
    if type(s) ~= "string" then return end
    if Pipes(s) then bad[#bad + 1] = label .. " has a bare pipe: " .. s end
    if NonAscii(s) then bad[#bad + 1] = label .. " is not ASCII: " .. s end
end
for _, col in ipairs({ W.left, W.right }) do
    if col then
        for ti, f in pairs(col.frames) do
            Scan("name " .. tostring(ti), f.name:GetText())
            Scan("cast " .. tostring(ti), f.cast:GetText())
            Scan("pct " .. tostring(ti), f.pct:GetText())
        end
        if col.strip then
            Scan("score", col.strip.score:GetText())
            Scan("castbar", col.strip.castFS:GetText())
        end
    end
end
Scan("header", W.headerFS:GetText())
Scan("recon", W.reconFS and W.reconFS:GetText())
Scan("hint", W.hint and W.hint:GetText())
for _, l in ipairs(vlines) do Scan("validate line", l) end
for _, l in ipairs(clines) do Scan("coach line", l) end
check("every string the window paints is ASCII with no bare pipe", #bad == 0, bad[1])

--------------------------------------------------------------------------------
-- 10: the window will not open in combat
--------------------------------------------------------------------------------
if W.frame then W.frame:Hide() end
S.inCombat = true
local combatLines = CapturedChat(function() SlashCmdList.SPELLTUNER("replay 1") end)
local refusedCombat = false
for _, l in ipairs(combatLines) do
    if l:find("not in combat", 1, true) then refusedCombat = true end
end
check("the window will not open in combat",
    refusedCombat and not (MD.Replay._state().frame and MD.Replay._state().frame:IsShown()))
S.inCombat = false

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
