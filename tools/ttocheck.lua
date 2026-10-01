-- tools/run.sh tools/ttocheck.lua
--
-- T58 (P14, review A28): the TBC mana clock (Engine/TTO.lua) through a
-- scripted spend and regen stream -- the most log-debugged code in the
-- project, verified until now only in-game, because the TBC stub answered
-- UnitAffectingCombat with false always and the TTO polled it, so every suite
-- that drove a fight had the clock believe it was out of combat.
--
-- What is held, in order:
--   1. the stub's combat state answers the regen events (and the kernel's
--      MD.inCombat with it);
--   2. out of combat at full: FULL, no rest segment, the widget hidden;
--   3. a /reload mid-fight: the kernel's flag seeded true with no regen event
--      and the poll left saying no -- the clock, the widget, the pull budget,
--      the Advisor's two checks and the gear reminder all read the flag;
--   4. the pull budget's median (the lower middle, never the caller's order);
--   5. warmup -> oom after three priced casts, "~" until the estimate is
--      stable, the rest segment's 25% rule and its value, the arrow while
--      casting;
--   6. the confidence gate: the bound at once, the digits back only after
--      two confident ticks;
--   7. casting stops: "^", and rest = deficit / base out of the FSR;
--   8. hold, 9. full (never a rest segment next to FULL), 10. bad news at
--      once; 11. leaving combat: FULL with the time to full.
-- The stream is real events -- UNIT_SPELLCAST_SUCCEEDED priced by
-- Data/SpellData.lua, UNIT_POWER_UPDATE, the regen events -- and a scripted
-- GetManaRegen; nothing in the model is replaced.
local here = arg[0]:match("^(.*)/[^/]+$")
HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-66s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local chat = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
local function Said(pat, from)
    local n = 0
    for i = (from or 1), #chat do if chat[i]:find(pat) then n = n + 1 end end
    return n
end

-- The TBC harness loads no UI file but UI/Summary.lua; the widget and the
-- Advisor are loaded here, after login, and handed the MD_READY they missed
-- (only their own handlers, captured as they register -- re-firing MD_READY
-- would re-run every other module's).
do
    local ready, realReg = {}, MD.RegisterCallback
    MD.RegisterCallback = function(self, name, fn)
        if name == "MD_READY" then ready[#ready + 1] = fn end
        return realReg(self, name, fn)
    end
    -- T68 (P24): UI/Visibility.lua holds the widget's show/hide rule, so it
    -- loads before UI/Widget.lua, as in SpellTuner_TBC.toc.
    S.Load({ "UI/Style.lua", "UI/Tip.lua", "UI/Tip_TBC.lua", "UI/Visibility.lua", "UI/Widget.lua", "UI/Advisor.lua" },
        "SpellTuner", MD)
    MD.RegisterCallback = realReg
    for _, fn in ipairs(ready) do fn() end
end
local W = _G.SpellTunerWidget

-- A scripted regen: RM:Refresh reads GetManaRegen on every tick. Low, so the
-- casts below drain faster than it refills (net ~50/s: a clock of a minute
-- or two, the range the display layer was tuned on).
local regenBase, regenCast = 10, 5
function GetManaRegen() return regenBase, regenCast end

local SD = MD.SpellData
local HT5 = 5189 -- Healing Touch rank 5: 219 mana after the harness's talents
local function Cast(id)
    S.mana = S.mana - SD:GetCost(id)
    S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", id)
    S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
end
local function Plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Shown() return Plain(MD:GetDisplayString()) end
local function State() return MD:GetManaState() end
local function Ticks(n) for _ = 1, n do S.Tick(0.5) end end
-- "1:15" -> 75, "50s" -> 50, ">10m" -> nil
local function Secs(txt)
    if not txt then return nil end
    local m, s = txt:match("^(%d+):(%d%d)$")
    if m then return tonumber(m) * 60 + tonumber(s) end
    return tonumber(txt:match("^(%d+)s$"))
end
-- TTO.lua's own rendering of a rest value (Quantize, then FmtTime)
local function RestText(r)
    local step = r < 30 and 1 or 5
    local q = step * math.floor(r / step + 0.5)
    if q >= 60 then return string.format("%d:%02d", math.floor(q / 60), math.floor(q % 60)) end
    return string.format("%ds", math.floor(q))
end

Ticks(4)

--------------------------------------------------------------------------------
-- 1. the stub answers the regen events, and the kernel's flag follows them
--------------------------------------------------------------------------------
check("stub: out of combat before any regen event",
    UnitAffectingCombat("player") == false and InCombatLockdown() == false and MD.inCombat == false)
S.Fire("PLAYER_REGEN_DISABLED")
check("stub: PLAYER_REGEN_DISABLED -> UnitAffectingCombat, InCombatLockdown true",
    UnitAffectingCombat("player") == true and InCombatLockdown() == true)
check("kernel: MD.inCombat true on PLAYER_REGEN_DISABLED", MD.inCombat == true)
S.Fire("PLAYER_REGEN_ENABLED")
check("stub: PLAYER_REGEN_ENABLED -> both false again, MD.inCombat false",
    UnitAffectingCombat("player") == false and InCombatLockdown() == false and MD.inCombat == false)
Ticks(2)

--------------------------------------------------------------------------------
-- 2. out of combat at full mana
--------------------------------------------------------------------------------
check("full, out of combat: mode fullnow, shown FULL, no rest segment",
    State().mode == "fullnow" and Shown() == "FULL" and State().inCombat == false, Shown())
check("widget: locked, out of combat, full mana -> hidden", W and not W:IsShown())

--------------------------------------------------------------------------------
-- 3. a /reload mid-fight. PLAYER_REGEN_DISABLED already fired before the
-- reload; Core.lua seeds MD.inCombat at MD_READY through the adapter. The
-- flag is set here the way that seed sets it, and the stub's own poll is left
-- saying "out of combat", so only a reader of the kernel's flag passes.
--------------------------------------------------------------------------------
local realHist = MD.fightHistory
MD.fightHistory = {
    { avgSpendRate = 10, duration = 30 }, { avgSpendRate = 20, duration = 30 },
    { avgSpendRate = 5, duration = 30 },  { avgSpendRate = 40, duration = 30 },
}
check("pull budget out of combat: tooltip lines", #MD.PullBudget:Lines() > 0)
-- 4. the median: 300, 600, 150, 1200 -> the lower middle of 150 300 600 1200
local e = MD.PullBudget:Estimate()
check("pull budget: median of an even count is the lower middle (300)",
    e and e.perPull == 300 and e.n == 4, e and string.format("%s of %d", tostring(e.perPull), e.n))
check("pull budget: the history's own order is untouched",
    MD.fightHistory[1].avgSpendRate == 10 and MD.fightHistory[3].avgSpendRate == 5)

MD.inCombat = true
Ticks(1)
check("reload mid-fight: the poll says no, the kernel's flag says yes",
    UnitAffectingCombat("player") == false and MD.inCombat == true)
check("reload mid-fight: the clock projects in combat at once (warmup)",
    State().inCombat == true and State().mode == "warmup" and Shown():find("^OOM %.%.%.") ~= nil, Shown())
check("reload mid-fight: the widget shows at full mana", W and W:IsShown())
check("reload mid-fight: no pull-budget lines in combat", #MD.PullBudget:Lines() == 0)

local mark = #chat + 1
MD.cdb.mp5 = { at = 1700000000, mp5 = 12 }
S.Fire("PLAYER_EQUIPMENT_CHANGED")
check("reload mid-fight: no gear reminder in combat", Said("item mp5 was measured", mark) == 0)

-- The Advisor: Innervate known, the deficit swallows it -> the alert; low
-- mana while in combat is not a drink moment.
S.known[29166] = true
S.mana = 1000
local plays = W and W.pulse and W.pulse.plays or 0
Ticks(12)
check("reload mid-fight: the Advisor calls Innervate", Said("Innervate now", mark) == 1,
    tostring(Said("Innervate now", mark)))
check("...and that alert, the only one, pulses the widget",
    Said("Innervate now", mark) == 1 and W and W.pulse and W.pulse.plays == plays + 1)
check("reload mid-fight: no drink reminder in combat", Said("Drink", mark) == 0)

MD.inCombat = false
Ticks(1)
check("out of combat again: the clock leaves combat", State().inCombat == false and State().mode ~= "warmup",
    State().mode)
S.Fire("PLAYER_EQUIPMENT_CHANGED")
check("out of combat: the gear reminder, once", Said("item mp5 was measured", mark) == 1)
Ticks(12)
check("out of combat, 14% mana, standing still: the drink reminder", Said("Drink", mark) == 1,
    tostring(Said("Drink", mark)))
check("pull budget out of combat again: tooltip lines", #MD.PullBudget:Lines() > 0)

MD.fightHistory = realHist
S.known[29166] = nil
S.mana = S.manaMax
S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
Ticks(12) -- past the five-second rule the drain above never started (no power event)
check("back at full: FULL, widget hidden", Shown() == "FULL" and W and not W:IsShown(), Shown())

--------------------------------------------------------------------------------
-- 5. warmup -> oom through a steady stream: one Healing Touch every 3.5 s
--------------------------------------------------------------------------------
S.Fire("PLAYER_REGEN_DISABLED")
Ticks(1)
check("pull: warmup, shown 'OOM ...'", State().mode == "warmup" and Shown():find("^OOM %.%.%.") ~= nil, Shown())
check("warmup: the rest segment is shown (nothing to compare against)", Shown():find("  rest ") ~= nil, Shown())

local log = {}       -- every tick: { t, mode, shown, state }
local modeAfter = {} -- cast number -> mode on the tick after it
local casts = 0
local function Step(castNow)
    if castNow then Cast(HT5); casts = casts + 1 end
    S.Tick(0.5)
    local st = State()
    log[#log + 1] = { t = S.now, mode = st.mode, shown = Shown(), st = st, casting = true }
    if castNow then modeAfter[casts] = st.mode end
end
for i = 1, 100 do Step(i % 7 == 1) end

check("warmup holds through two priced casts", modeAfter[1] == "warmup" and modeAfter[2] == "warmup",
    tostring(modeAfter[1]) .. ", " .. tostring(modeAfter[2]))
check("the third priced cast: oom at once", modeAfter[3] == "oom", tostring(modeAfter[3]))

local firstOom, stableClean, tilde, restHidden, restOk, restBad = nil, false, false, false, 0, nil
local up, down = 0, 0
for _, r in ipairs(log) do
    if r.mode == "oom" then
        firstOom = firstOom or r
        local num = r.shown:match("^OOM (~?[%d:s]+)")
        if num and num:sub(1, 1) == "~" then tilde = true end
        if r.st.stable and num and num:sub(1, 1) ~= "~" then stableClean = true end
        if r.shown:find(" %^") then up = up + 1 end
        if r.shown:find(" v") then down = down + 1 end
        local v = Secs(num and num:gsub("^~", ""))
        local seg = r.shown:match("  rest (%S+)$")
        if v and r.st.rest then
            local far = math.abs(r.st.rest - v) / math.max(v, 1) >= 0.25
            if not far and not seg then restHidden = true end
            if far and seg == RestText(r.st.rest) then restOk = restOk + 1
            elseif far or seg then restBad = restBad or r.shown end
        end
    end
end
check("oom: digits with '~' while the estimate is not stable", firstOom and not firstOom.st.stable
    and firstOom.shown:find("^OOM ~%d") ~= nil and tilde, firstOom and firstOom.shown)
check("oom: once stable, the digits lose the '~'", stableClean)
check("rest: hidden within 25% of the clock", restHidden)
check("rest: shown beyond 25%, as the quantized time to full", restOk > 0 and restBad == nil,
    restBad or tostring(restOk))
check("arrow while casting steadily: 'v' seen, never '^'", down > 0 and up == 0,
    string.format("v %d, ^ %d", down, up))

--------------------------------------------------------------------------------
-- 6. the confidence gate (db.oomConfidence): the bound at once, the digits
-- back only after two confident ticks
--------------------------------------------------------------------------------
local rel = State().rel
MD.db.oomConfidence = rel / 2
Ticks(1)
check("rel above the gate: not confident, the bound at once",
    State().confident == false and Shown():find("^OOM >[%d:s]+ =") ~= nil, Shown())
Ticks(2)
check("...and it stays the bound", Shown():find("^OOM >") ~= nil, Shown())
MD.db.oomConfidence = 0.7
Ticks(1)
check("gate restored: one confident tick still shows the bound",
    State().confident == true and Shown():find("^OOM >") ~= nil, Shown())
Ticks(1)
check("the second confident tick brings the digits back", Shown():find("^OOM %d") ~= nil, Shown())

--------------------------------------------------------------------------------
-- 7. casting stops: the clock climbs, and rest is the plain time to full
--------------------------------------------------------------------------------
local stopShown, sawUp = Shown(), false
for _ = 1, 30 do
    S.Tick(0.5)
    if Shown():find(" %^") then sawUp = true end
end
check("casting stops: '^' within 15 s", sawUp, stopShown .. " -> " .. Shown())
local st = State()
local want = (S.manaMax - S.mana) / MD.Regen.base
check("out of the five-second rule: rest = deficit / base regen",
    st.rest and math.abs(st.rest - want) < 1e-6 and MD.Regen:FSRRemaining() == 0,
    string.format("%s vs %.1f", tostring(st.rest), want))

--------------------------------------------------------------------------------
-- 8. hold: regen matched to spend + one sigma, so |net| <= sigma
--------------------------------------------------------------------------------
local rate, sigma = MD.Spend:Estimate()
regenBase, regenCast = rate + sigma, rate + sigma
Ticks(1)
check("hold is better news: the first tick keeps oom", State().mode == "hold" and Shown():find("^OOM ") ~= nil
    and Shown():find("^OOM >") == nil, Shown())
Ticks(1)
check("hold on the second tick: 'OOM >bound ='", State().mode == "hold" and Shown():find("^OOM >[%d:sm]+ =") ~= nil,
    Shown())

--------------------------------------------------------------------------------
-- 9. full: regen well above spend
--------------------------------------------------------------------------------
regenBase, regenCast = 3 * (rate + sigma), 3 * (rate + sigma)
Ticks(2)
check("full in combat: 'FULL <time>', no rest segment beside it",
    State().mode == "full" and Shown():find("^FULL [%d:s]+$") ~= nil, Shown())

--------------------------------------------------------------------------------
-- 10. bad news applies at once
--------------------------------------------------------------------------------
regenBase, regenCast = 10, 5
Ticks(1)
check("regen falls back: oom on the very next tick", State().mode == "oom" and Shown():find("^OOM ") ~= nil, Shown())

--------------------------------------------------------------------------------
-- 11. leaving combat
--------------------------------------------------------------------------------
S.Fire("PLAYER_REGEN_ENABLED")
Ticks(1)
st = State()
check("combat ends: out of combat, 'FULL <time to full>', no rest segment",
    st.inCombat == false and st.mode == "ooc" and Shown():find("^FULL [%d:s]+$") ~= nil, Shown())
check("...the time to full is the deficit over the base rate",
    st.ttf and math.abs(st.ttf - (S.manaMax - S.mana) / MD.Regen.base) < 1e-6,
    string.format("%s", tostring(st.ttf)))
check("widget: below 90% out of combat -> still shown", W and W:IsShown())

-- every rendered string: ASCII, no bare pipe
local bad
for _, r in ipairs(log) do
    local raw = r.shown
    if raw:find("[\128-\255]") or raw:find("|", 1, true) then bad = raw break end
end
check("every shown string ASCII with no bare pipe", bad == nil, bad)

print(string.format("\n%d ok, %d failed", ok, #fails))
if #fails > 0 then os.exit(1) end
