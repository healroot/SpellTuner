-- tools/run.sh tools/recordcheck.lua
--
-- T13 (docs/tasks/T13-recorder-v3.md): the Forever recorder
-- (Modules/SpellTuner_Recorder/Recorder_Forever.lua) -- a v3 stream of one
-- pull from UNIT_COMBAT, own casts and the damage meter. Forever only.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-90s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local function NewSession()
    _G.SpellTunerDB = nil
    _G.ManaDemonDB = nil
    local a0 = arg[0]; arg[0] = here .. "/harness.lua"
    local MD = dofile(here .. "/harness.lua")
    arg[0] = a0
    return MD, _G.STUB
end

local function CapturedChat(body)
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    body()
    frame.AddMessage = orig
    return lines
end

-- T54 (P10, review Q8): the recorder finishes a pull one second after the
-- combat flag drops (MD.API.After(1, ...): the death re-poll, the meter read,
-- the store), and the stub now fires a timer when its clock reaches it. So a
-- pull's end is the clock ticked one second on -- never a hand flush -- and
-- whatever is still pending after that is noted here; one check at the end
-- says nothing ever was. A chain pull (R11) is back in combat by then and
-- has queued its own timers (the probe's 2 s snapshot), so only a pull that
-- ended out of combat is held to it.
local leftovers = {}
local function Settle(St, label)
    local t = St.now + 1
    while St.now < t - 1e-6 do St.Tick(0.5) end
    local n = St.Pending and St.Pending() or #(St.timers or {})
    if n ~= 0 and not St.inCombat then
        leftovers[#leftovers + 1] = string.format("%s: %d pending", label, n)
    end
end

local function CountAttempts(S, event)
    local n = 0
    for _, f in ipairs(S.allFrames) do
        for _, e in ipairs(f.attempts or {}) do
            if e == event then n = n + 1 end
        end
    end
    return n
end

--------------------------------------------------------------------------------
-- 1: the recorder registers nothing until its module is on
--------------------------------------------------------------------------------
do
    local MD, S = NewSession()
    -- UNIT_SPELLCAST_INTERRUPTED is the recorder's own: Client/Probe.lua
    -- already registers UNIT_COMBAT and the rest of the recorder's events at
    -- load (its own capability probe, Client/Probe.lua:1860), so this is the
    -- one event nothing else in the Forever core registers.
    local before = CountAttempts(S, "UNIT_SPELLCAST_INTERRUPTED")
    MD:SetModule("SpellTuner_Recorder", true)
    local after = CountAttempts(S, "UNIT_SPELLCAST_INTERRUPTED")
    check("the recorder registers nothing until its module is on",
        before == 0 and after > 0, string.format("before=%d after=%d", before, after))
end

--------------------------------------------------------------------------------
-- The fixture pull, driven through the real events. Kept in its own session
-- so the ring starts empty.
--------------------------------------------------------------------------------
local MD, S = NewSession()

-- Player: Healroot, plain max health 375.
S.units.player.name = "Healroot"
S.units.player.hpMax = 375

-- party1 = Tank (WARRIOR/TANK), party2 = Mage (MAGE/DAMAGER).
S.AddUnit("party1", { guid = "Party-1-guid", name = "Tank", class = "WARRIOR", role = "TANK",
                       hp = 9000, hpMax = 9000 })
S.AddUnit("party2", { guid = "Party-2-guid", name = "Mage", class = "MAGE", role = "DAMAGER",
                       hp = 4000, hpMax = 4000 })

-- Tank (currently at party1) has a Rejuvenation rolling before the pull.
S.units.party1.auras = { [1] = { name = "Rejuvenation", spellId = 774, expirationTime = 908, applications = 0 } }
-- an empty table suppresses the stub's own default "Mark of the Wild" row
-- (only there for suites that never set up a fixture of their own).
S.units.player.auras = {}

MD:SetModule("SpellTuner_Recorder", true) -- loads the file; R:Refresh() runs now: player=1, Tank=2, Mage=3

local function At(t)
    while S.now < t - 1e-6 do
        S.Tick(0.5)
    end
end


-- Lead review 1: whether UNIT_SPELLCAST_STOP fires before or after
-- UNIT_SPELLCAST_SUCCEEDED is UNKNOWN -- every successful cast below fires
-- STOP too, alternating the order, so a fixed order in the recorder's own
-- logic cannot pass by accident.
local function Cast(castGUID, spellID, targetName, stopFirst)
    S.Fire("UNIT_SPELLCAST_SENT", "player", targetName, castGUID, spellID)
    S.Fire("UNIT_SPELLCAST_START", "player", castGUID, spellID)
    if stopFirst then
        S.Fire("UNIT_SPELLCAST_STOP", "player", castGUID, spellID)
        S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", castGUID, spellID)
    else
        S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", castGUID, spellID)
        S.Fire("UNIT_SPELLCAST_STOP", "player", castGUID, spellID)
    end
end
local function CancelCast(castGUID, spellID, targetName)
    S.Fire("UNIT_SPELLCAST_SENT", "player", targetName, castGUID, spellID)
    S.Fire("UNIT_SPELLCAST_START", "player", castGUID, spellID)
    S.Fire("UNIT_SPELLCAST_STOP", "player", castGUID, spellID)
end

-- Out-of-combat aura scan, 2s ticks -- primes R.lastAuras before the pull.
At(8)
-- T13f: the last scan lands here (t=8, a %4 tick boundary); two more
-- half-second ticks put the pull's own start a full second later without
-- crossing another scan boundary, so assertion 10 can tell "remaining at
-- scan time" (900) from "remaining at t0" (899) apart.
S.Tick(0.5)
S.Tick(0.5)

-- The pull starts.
S.inCombat = true
S.Fire("PLAYER_REGEN_DISABLED")

-- Damage and heals, per tracked token, plus mirrors under untracked tokens.
S.Combat("party1", "WOUND", 500)   -- Tank, idx 2
S.Combat("party2", "WOUND", 300)   -- Mage, idx 3
S.Combat("player", "HEAL", 200)    -- idx 1
S.Combat("target", "HEAL", 200)    -- mirror: ignored, untracked token
S.Combat("nameplate1", "HEAL", 200) -- mirror: ignored, untracked token
S.Combat("party1", "WOUND", S.Secret()) -- a secret amount: counted, never stored

-- Six own casts with SENT names, plus one unfinished (a cancel). STOP fires
-- before SUCCEEDED for some, after for others (order is UNKNOWN, Lead review 1).
Cast("cg1", 774, "Tank", true)        -- Rejuvenation r1 -> Tank, STOP before SUCCEEDED
Cast("cg2", 774, "Mage", false)       -- Rejuvenation r1 -> Mage, STOP after SUCCEEDED
Cast("cg3", 5185, "Tank", true)       -- Healing Touch r1 -> Tank, STOP before
Cast("cg4", 5185, "Healroot", false)  -- Healing Touch r1 -> self, STOP after
Cast("cg5", 1058, "Tank", true)       -- Rejuvenation r2 -> Tank, STOP before
Cast("cg6", 5185, "Mage", false)      -- Healing Touch r1 -> Mage, STOP after
CancelCast("cg7", 5185, "Tank") -- started, never finished

-- An add-on restriction bracket.
S.Fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)

-- A roster swap at 20s: Tank and Mage trade tokens.
At(29)
S.units.party1, S.units.party2 = S.units.party2, S.units.party1
S.Fire("GROUP_ROSTER_UPDATE")
S.Combat("party1", "WOUND", 111) -- party1 is now Mage (idx 3)

-- A death at 30s: whoever now sits at party2 (Tank, idx 2).
At(38.5)
S.units.party2.dead = true
At(39)

-- The pull ends at 40s.
At(49)
S.inCombat = false
S.Fire("PLAYER_REGEN_ENABLED")
S.meter.sources = {
    { sourceGUID = S.units.player.guid, isLocalPlayer = true, totalAmount = 400, name = "Healroot" },
    { sourceGUID = "Other-1", isLocalPlayer = false, totalAmount = 120, name = "Someone" },
}
Settle(S, "fixture") -- T54 (P10): one second on, not a flush

local rec = MD.FightRecorder:Get(1)
local K = { DMG = 1, OWNCAST = 3, CASTSTART = 6, CANCEL = 7, DIED = 9, HEAL = 15 }

local function CountKind(s, kind)
    local n = 0
    for i = 1, s.n do if s.ev.kind[i] == kind then n = n + 1 end end
    return n
end
local function FindEvent(s, kind, pred)
    for i = 1, s.n do
        if s.ev.kind[i] == kind then
            local row = { t = s.ev.t[i], tgt = s.ev.tgt[i], amt = s.ev.amt[i], x = s.ev.x[i] }
            if not pred or pred(row) then return row end
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- 2: a pull starts at combat and ends after it, and the damage meter is read
--    once combat is over; the shared readers' three summary numbers are
--    stamped (T13f Facts: ownCasts, spent, foreignShare)
--------------------------------------------------------------------------------
check("a pull starts at combat and ends after it, and the damage meter is read once combat is over",
    rec ~= nil and math.abs((rec.dur or -1) - 40) < 0.001 and rec.meter and rec.meter.read == "current"
    and rec.ownCasts == 6 and rec.spent == 165 and math.abs((rec.foreignShare or -1) - 120 / 520) < 0.0001,
    string.format("rec=%s dur=%s meter.read=%s ownCasts=%s spent=%s foreignShare=%s",
        tostring(rec), tostring(rec and rec.dur), tostring(rec and rec.meter and rec.meter.read),
        tostring(rec and rec.ownCasts), tostring(rec and rec.spent), tostring(rec and rec.foreignShare)))

--------------------------------------------------------------------------------
-- 3: damage and heals are kept per tracked token, once each; other tokens
--    are ignored
--------------------------------------------------------------------------------
check("damage and heals are kept per tracked token, once each; other tokens are ignored",
    rec ~= nil and CountKind(rec, K.DMG) == 3 and CountKind(rec, K.HEAL) == 1,
    string.format("dmg=%s heal=%s", tostring(rec and CountKind(rec, K.DMG)), tostring(rec and CountKind(rec, K.HEAL))))

--------------------------------------------------------------------------------
-- 4: own casts carry their spell, cost and the target named when they were
--    sent; an unfinished cast is a cancel
--------------------------------------------------------------------------------
do
    local cast1 = rec and FindEvent(rec, K.OWNCAST, function(r) return r.x == 774 and r.tgt == 2 end)
    local castSelf = rec and FindEvent(rec, K.OWNCAST, function(r) return r.x == 5185 and r.tgt == 1 end)
    local castR2 = rec and FindEvent(rec, K.OWNCAST, function(r) return r.x == 1058 and r.tgt == 2 end)
    local cancel = rec and FindEvent(rec, K.CANCEL, function(r) return r.x == 5185 end)
    check("own casts carry their spell, cost and the target named when they were sent; an unfinished cast is a cancel",
        rec ~= nil and CountKind(rec, K.CASTSTART) == 7 and CountKind(rec, K.OWNCAST) == 6
        and CountKind(rec, K.CANCEL) == 1
        and cast1 and cast1.amt == 25 and castSelf and castSelf.amt == 25
        and castR2 and castR2.amt == 40
        and cancel and cancel.tgt == -1 and cancel.amt >= 0,
        string.format("caststart=%s owncast=%s cancel=%s cast1.amt=%s castR2.amt=%s cancel.amt=%s",
            tostring(rec and CountKind(rec, K.CASTSTART)), tostring(rec and CountKind(rec, K.OWNCAST)),
            tostring(rec and CountKind(rec, K.CANCEL)), tostring(cast1 and cast1.amt), tostring(castR2 and castR2.amt),
            tostring(cancel and cancel.amt)))
end

--------------------------------------------------------------------------------
-- 5: the party keeps its indices across a roster change mid-pull
--------------------------------------------------------------------------------
do
    local swapped = rec and FindEvent(rec, K.DMG, function(r) return r.amt == 111 end)
    check("the party keeps its indices across a roster change mid-pull",
        swapped ~= nil and swapped.tgt == 3, string.format("tgt=%s", tostring(swapped and swapped.tgt)))
end

--------------------------------------------------------------------------------
-- 6: a party member's max health is recorded unknown, the player's as read
--------------------------------------------------------------------------------
check("a party member's max health is recorded unknown, the player's as read",
    rec ~= nil and rec.roster[1].maxHP == 375 and rec.roster[1].maxSecret == false
    and rec.roster[2].maxHP == -1 and rec.roster[2].maxSecret == true
    and rec.roster[3].maxHP == -1 and rec.roster[3].maxSecret == true,
    string.format("p1=%s,%s p2=%s,%s p3=%s,%s",
        tostring(rec and rec.roster[1].maxHP), tostring(rec and rec.roster[1].maxSecret),
        tostring(rec and rec.roster[2].maxHP), tostring(rec and rec.roster[2].maxSecret),
        tostring(rec and rec.roster[3].maxHP), tostring(rec and rec.roster[3].maxSecret)))

--------------------------------------------------------------------------------
-- 7: mana is the clock's modelled pool every two seconds, marked modelled
--------------------------------------------------------------------------------
check("mana is the clock's modelled pool every two seconds, marked modelled",
    rec ~= nil and rec.manaModelled == true and #rec.mana.t >= 2
    and math.abs(rec.mana.t[2] - rec.mana.t[1] - 2) < 0.001
    and type(rec.mana.v[1]) == "number",
    string.format("manaModelled=%s samples=%s", tostring(rec and rec.manaModelled), tostring(rec and #rec.mana.t)))

--------------------------------------------------------------------------------
-- 8: a death is recorded once, from UnitIsDeadOrGhost
--------------------------------------------------------------------------------
check("a death is recorded once, from UnitIsDeadOrGhost",
    rec ~= nil and #rec.deaths == 1 and rec.deaths[1][2] == 2 and CountKind(rec, K.DIED) == 1,
    string.format("deaths=%s died=%s", tostring(rec and #rec.deaths), tostring(rec and CountKind(rec, K.DIED))))

--------------------------------------------------------------------------------
-- 9: a secret argument is counted and never stored
--------------------------------------------------------------------------------
check("a secret argument is counted and never stored",
    rec ~= nil and rec.unreadable >= 1 and CountKind(rec, K.DMG) == 3,
    string.format("unreadable=%s dmg=%s", tostring(rec and rec.unreadable), tostring(rec and CountKind(rec, K.DMG))))

--------------------------------------------------------------------------------
-- 10: own HoTs on the party are read before the pull, never in combat
--------------------------------------------------------------------------------
do
    -- Lead review 1: the module could be switched on, or loaded at login,
    -- while the player is already in combat with no pull started -- the
    -- out-of-combat branch of the ticker must not read auras then either.
    -- Four half-second ticks guarantee at least one lands on the scanner's
    -- own %4 boundary regardless of phase. S.auraCalls counts the stub call
    -- itself (raised or not), so this proves the scan was skipped, not just
    -- that a raise was swallowed by the pcall wrapper.
    local before = S.auraCalls
    S.inCombat = true
    for i = 1, 4 do S.Tick(0.5) end
    local afterCombat = S.auraCalls
    S.inCombat = false
    local blocked = afterCombat == before

    -- T13d hand-out amendment: each aura entry also carries `tgt`, the
    -- roster index -- party1 is the tank, roster index 2.
    -- T13f Facts: the last scan (t=8) reads a remaining of 900 (908 - 8), but
    -- the pull starts a full second later (t0=9) -- the stored remaining must
    -- be the time left AT THE PULL (908 - 9 = 899), not the stale scan value.
    check("own HoTs on the party are read before the pull, never in combat",
        rec ~= nil and #rec.initial.auras == 1 and rec.initial.auras[1].spellId == 774
        and rec.initial.auras[1].token == "party1" and math.abs((rec.initial.auras[1].remaining or -1) - 899) < 0.001
        and rec.initial.auras[1].tgt == 2
        and blocked,
        string.format("auras=%s auraCalls before=%s after=%s tgt=%s remaining=%s",
            tostring(rec and #rec.initial.auras), tostring(before), tostring(afterCombat),
            tostring(rec and rec.initial.auras[1] and rec.initial.auras[1].tgt),
            tostring(rec and rec.initial.auras[1] and rec.initial.auras[1].remaining)))
end

--------------------------------------------------------------------------------
-- 11: a short pull is dropped, a kept one enters a ring of eight
--------------------------------------------------------------------------------
do
    local before = #MD.FightRecorder:List()
    At(60)
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    Cast("sg1", 774, "Tank")
    Cast("sg2", 774, "Tank")
    At(65)
    S.inCombat = false
    S.Fire("PLAYER_REGEN_ENABLED")
    Settle(S, "fixture") -- T54 (P10): one second on, not a flush
    local after = #MD.FightRecorder:List()
    check("a short pull is dropped, a kept one enters a ring of eight",
        before == 1 and after == 1,
        string.format("before=%d after=%d", before, after))
end

--------------------------------------------------------------------------------
-- 12: the stream holds only numbers, strings, booleans and tables of them,
--     nothing secret
--------------------------------------------------------------------------------
do
    local function Walk(v, seen)
        local t = type(v)
        if t == "number" or t == "string" or t == "boolean" or t == "nil" then return true end
        if t ~= "table" then return false end
        if MD.API.IsSecret(v) then return false end
        seen = seen or {}
        if seen[v] then return true end
        seen[v] = true
        for k, val in pairs(v) do
            if MD.API.IsSecret(k) or not Walk(k, seen) then return false end
            if MD.API.IsSecret(val) or not Walk(val, seen) then return false end
        end
        return true
    end
    check("the stream holds only numbers, strings, booleans and tables of them, nothing secret",
        rec ~= nil and Walk(rec))
end

--------------------------------------------------------------------------------
-- Lead review 1: a zone name with a pipe and a non-ASCII byte -- a second
-- kept pull, S.zoneText set for the moment the pull starts (the only moment
-- the recorder reads it; MD.API.Has caches the resolved function per dotted
-- name, so swapping the global GetRealZoneText after the first call would
-- have no effect) and cleared right after.
--------------------------------------------------------------------------------
do
    At(90)
    S.inCombat = true
    S.zoneText = "Zone|Caf\195\169" -- a bare pipe + a UTF-8 non-ASCII byte
    S.Fire("PLAYER_REGEN_DISABLED")
    S.zoneText = nil
    Cast("zg1", 774, "Tank")
    Cast("zg2", 774, "Tank")
    Cast("zg3", 774, "Tank")
    Cast("zg4", 774, "Tank")
    Cast("zg5", 774, "Tank")
    At(115)
    S.inCombat = false
    S.Fire("PLAYER_REGEN_ENABLED")
    Settle(S, "fixture") -- T54 (P10): one second on, not a flush
end

--------------------------------------------------------------------------------
-- 13: the list command prints one ASCII line per recording
--------------------------------------------------------------------------------
do
    local lines = CapturedChat(function() SlashCmdList.SPELLTUNER("rec") end)
    local dataLines = {}
    for _, l in ipairs(lines) do
        if l:match("^|c%x%x%x%x%x%x%x%xSpellTuner:|r %d%.") then dataLines[#dataLines + 1] = l end
    end
    local ascii = true
    for _, l in ipairs(dataLines) do
        for i = 1, #l do
            if l:byte(i) > 126 then ascii = false end
        end
        local stripped = l:gsub("||", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if stripped:find("|") then ascii = false end
    end
    check("the list command prints one ASCII line per recording",
        #dataLines == #MD.FightRecorder:List() and ascii,
        string.format("lines=%d list=%d ascii=%s", #dataLines, #MD.FightRecorder:List(), tostring(ascii)))
end

--------------------------------------------------------------------------------
-- 14: the recorder answers the list, get, pin and address calls the replay
--     window and Review use
--------------------------------------------------------------------------------
do
    local list = MD.FightRecorder:List()
    local got = MD.FightRecorder:Get(1)
    local pinnedOn = MD.FightRecorder:Pin(1, true)
    local stillPinned = got.pinned == true
    local pinnedOff = MD.FightRecorder:Pin(1, false)
    local viaSpec, label = MD:GetRecording("1")
    local runSpec, runLabel = MD:GetRecording("2:3")
    check("the recorder answers the list, get, pin and address calls the replay window and Review use",
        #list >= 1 and got == list[1] and pinnedOn == true and stillPinned and pinnedOff == true
        and got.pinned == false and viaSpec == got and label == "1" and runSpec == nil and runLabel == "2:3")
end

--------------------------------------------------------------------------------
-- T17c: with the adapter's status-bar readback on and a bar that reads back
-- plain, a party member's max is recorded plain. A fresh session, so the
-- assertions above (constant off) are untouched; the constant and the bar's
-- getter are restored at the end.
--------------------------------------------------------------------------------
do
    local MD2, S2 = NewSession()
    S2.units.player.name = "Healroot"
    S2.units.player.hpMax = 375
    S2.AddUnit("party1", { guid = "Party-1-guid", name = "Tank", class = "WARRIOR", role = "TANK",
                            hp = 9000, hpMax = 9000 })
    S2.units.player.auras = {}
    local tankMax = S2.units.party1.hpMax
    local barMT = getmetatable(_G.UIParent)
    local origGet = barMT.GetMinMaxValues
    local origFlag = MD2.API.BAR_READS_MAX
    MD2.API.BAR_READS_MAX = true
    barMT.GetMinMaxValues = function() return 0, tankMax end

    MD2:SetModule("SpellTuner_Recorder", true)
    local function Flush() Settle(S2, "bar") end -- T54 (P10)
    S2.inCombat = true
    S2.Fire("PLAYER_REGEN_DISABLED")
    for i = 1, 5 do
        local g = "bg" .. i
        S2.Fire("UNIT_SPELLCAST_SENT", "player", "Tank", g, 774)
        S2.Fire("UNIT_SPELLCAST_START", "player", g, 774)
        S2.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", g, 774)
        S2.Fire("UNIT_SPELLCAST_STOP", "player", g, 774)
    end
    S2.Combat("party1", "WOUND", 500)
    while S2.now < 30 do S2.Tick(0.5) end
    S2.inCombat = false
    S2.Fire("PLAYER_REGEN_ENABLED")
    Flush()
    local rec2 = MD2.FightRecorder:Get(1)

    barMT.GetMinMaxValues = origGet
    MD2.API.BAR_READS_MAX = origFlag
    local e = rec2 and rec2.roster and rec2.roster[2]
    check("with the readback on and a bar that reads back plain, a party member's max is recorded plain",
        rec2 ~= nil and e ~= nil and e.name == "Tank" and e.maxHP == tankMax and e.maxSecret == false
        and e.maxVia == "bar" and rec2.roster[1].maxHP == 375 and rec2.roster[1].maxVia == nil
        and origFlag == false,
        string.format("rec=%s tank=%s,%s,%s", tostring(rec2), tostring(e and e.maxHP), tostring(e and e.maxSecret), tostring(e and e.maxVia)))
end

--------------------------------------------------------------------------------
-- Review 2026-09-29 (docs/review/2026-09-29-forever-review.md), R7 R8 R9 R10
-- R11 R24 R25: each in a fresh session, so the fixture pull above is
-- untouched. Fresh() sets up the player plus the named party, switches the
-- recorder on and hands back the helpers every block below drives it with.
--------------------------------------------------------------------------------
local function Fresh(party)
    local M, St = NewSession()
    St.units.player.name = "Healroot"
    St.units.player.hpMax = 375
    St.units.player.auras = {}
    for i, u in ipairs(party or {}) do
        u.auras = u.auras or {}
        St.AddUnit("party" .. i, u)
    end
    M:SetModule("SpellTuner_Recorder", true)
    local env = { MD = M, S = St }
    function env.Flush() Settle(St, "fresh") end -- T54 (P10)
    function env.At(t) while St.now < t - 1e-6 do St.Tick(0.5) end end
    function env.Cast(g, id, name)
        St.Fire("UNIT_SPELLCAST_SENT", "player", name, g, id)
        St.Fire("UNIT_SPELLCAST_START", "player", g, id)
        St.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", g, id)
        St.Fire("UNIT_SPELLCAST_STOP", "player", g, id)
    end
    function env.Start()
        St.inCombat = true
        St.Fire("PLAYER_REGEN_DISABLED")
    end
    function env.Five(prefix, name)
        for i = 1, 5 do env.Cast(prefix .. i, 774, name) end
    end
    function env.Stop()
        St.inCombat = false
        St.Fire("PLAYER_REGEN_ENABLED")
    end
    -- the newest stored stream (every stream shares one id under the stub's
    -- fixed time(), so List's sort cannot tell them apart)
    function env.Last()
        local list = M.cdb.recordings or {}
        return list[#list], #list
    end
    return env
end

local function Unit(guid, name, class, role, extra)
    local u = { guid = guid, name = name, class = class, role = role, hp = 5000, hpMax = 5000 }
    for k, v in pairs(extra or {}) do u[k] = v end
    return u
end

-- R7: a party member already dead (or a ghost running back) at the pull did
-- not die in it; a res and a real death in the pull is still one death.
do
    local E = Fresh({ Unit("G-A", "Tank", "WARRIOR", "TANK"),
                      Unit("G-B", "Mage", "MAGE", "DAMAGER", { dead = true }) })
    E.At(4)
    E.Start()
    E.Five("r7-", "Tank")
    E.At(12)
    E.S.units.party2.dead = false -- resurrected
    E.At(18)
    E.S.units.party2.dead = true  -- and dies for real
    E.At(30)
    E.Stop()
    E.Flush()
    local rec = E.Last()
    check("R7: a member already dead at the pull is not a death in it; a real one after a res still is",
        rec ~= nil and #rec.deaths == 1 and rec.deaths[1][2] == 3 and rec.deaths[1][1] > 13
        and CountKind(rec, K.DIED) == 1,
        string.format("deaths=%s first=%s at %s", tostring(rec and #rec.deaths),
            tostring(rec and rec.deaths[1] and rec.deaths[1][2]), tostring(rec and rec.deaths[1] and rec.deaths[1][1])))
end

-- R8: the pull's opener. (a) An instant that succeeds the moment before the
-- combat flag is the pull's first cast at t = 0, its target resolved, counted
-- and priced, the starting mana lifted by what the clock already charged;
-- (b) a cast-time opener SENT before the flag keeps its target.
do
    local E = Fresh({ Unit("G-A", "Tank", "WARRIOR", "TANK") })
    E.At(6)
    E.Cast("op1", 774, "Tank") -- out of combat: no pull yet
    local clockMana = E.MD.Clock and E.MD.Clock.model and E.MD.Clock.model.mana
    E.S.Fire("UNIT_SPELLCAST_SENT", "player", "Tank", "op2", 5185) -- out of combat too
    E.S.Fire("UNIT_SPELLCAST_START", "player", "op2", 5185)
    E.Start()                  -- same frame
    E.S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "op2", 5185)   -- inside the pull
    E.Five("r8-", "Tank")
    E.At(32)
    E.Stop()
    E.Flush()
    local rec = E.Last()
    local first = rec and FindEvent(rec, K.OWNCAST)
    check("R8: an opener that succeeds just before the combat flag is recorded at t = 0, priced, its mana given back",
        rec ~= nil and first ~= nil and first.t == 0 and first.x == 774 and first.tgt == 2 and first.amt == 25
        and rec.ownCasts == 7 and rec.spent == 25 * 6 + 25
        and type(clockMana) == "number" and math.abs((rec.initial.mana or -1) - (clockMana + 25)) < 1e-6,
        string.format("first=%s t=%s tgt=%s amt=%s ownCasts=%s spent=%s mana=%s clock=%s",
            tostring(first and first.x), tostring(first and first.t), tostring(first and first.tgt),
            tostring(first and first.amt), tostring(rec and rec.ownCasts), tostring(rec and rec.spent),
            tostring(rec and rec.initial.mana), tostring(clockMana)))

    local sentBefore = rec and FindEvent(rec, K.OWNCAST, function(r) return r.x == 5185 end)
    check("R8: a cast-time opener SENT before the combat flag keeps its target",
        sentBefore ~= nil and sentBefore.tgt == 2,
        string.format("tgt=%s", tostring(sentBefore and sentBefore.tgt)))
end

-- R8 (c): a HoT that lands out of combat between two 2 s scans is in the
-- pull's initial auras (UNIT_AURA reads it at once), aged to the pull, and
-- not recorded a second time as a cast.
do
    local E = Fresh({ Unit("G-A", "Tank", "WARRIOR", "TANK") })
    E.At(8) -- a scan lands here; nothing on the tank yet
    E.S.Tick(0.5)
    E.Cast("pre1", 774, "Tank")
    E.S.units.party1.auras = { [1] = { name = "Rejuvenation", spellId = 774,
                                       expirationTime = E.S.now + 12, applications = 0 } }
    E.S.Fire("UNIT_AURA", "party1")
    E.S.now = E.S.now + 1 -- a second later, no tick in between (no 2 s scan)
    E.Start()
    E.Five("r8c-", "Tank")
    E.At(36)
    E.Stop()
    E.Flush()
    local rec = E.Last()
    local a = rec and rec.initial.auras[1]
    check("R8: a HoT pre-cast between two scans is in the pull's initial auras, aged, and not a cast too",
        rec ~= nil and #rec.initial.auras == 1 and a.spellId == 774 and a.tgt == 2
        and math.abs((a.remaining or -1) - 11) < 1e-6 and rec.ownCasts == 5,
        string.format("auras=%s tgt=%s remaining=%s ownCasts=%s", tostring(rec and #rec.initial.auras),
            tostring(a and a.tgt), tostring(a and a.remaining), tostring(rec and rec.ownCasts)))
end

-- R9: a meter session with no sources, or with no row for the player, is not
-- a reading of the pull.
do
    local E = Fresh({ Unit("G-A", "Tank", "WARRIOR", "TANK") })
    local function PullWith(sources, t)
        E.At(t)
        E.Start()
        E.Five("r9-" .. t .. "-", "Tank")
        E.At(t + 25)
        E.Stop()
        E.S.meter.sources = sources
        E.Flush()
        return E.Last()
    end
    local empty = PullWith({}, 4)
    local foreignOnly = PullWith({ { sourceGUID = "Other-1", isLocalPlayer = false, totalAmount = 300, name = "Someone" } }, 40)
    local partial = PullWith({ { sourceGUID = E.S.units.player.guid, isLocalPlayer = true, totalAmount = 400 },
                               { sourceGUID = "Other-1", isLocalPlayer = false, name = "Someone" } }, 80)
    local function None(r) return r ~= nil and r.meter and r.meter.read == "none" and r.foreignShare == nil end
    check("R9: an empty meter session, one with no own row, or one with an unreadable row is no reading",
        None(empty) and None(foreignOnly) and None(partial),
        string.format("empty=%s/%s foreignOnly=%s/%s partial=%s/%s",
            tostring(empty and empty.meter and empty.meter.read), tostring(empty and empty.foreignShare),
            tostring(foreignOnly and foreignOnly.meter and foreignOnly.meter.read), tostring(foreignOnly and foreignOnly.foreignShare),
            tostring(partial and partial.meter and partial.meter.read), tostring(partial and partial.foreignShare)))
end

-- R10: the healer's own death ends combat in the same frame. (a) Polled as
-- the pull ends; (b) the dead flag trailing the combat flag, seen while the
-- ended pull waits for its meter.
do
    local E = Fresh({ Unit("G-A", "Tank", "WARRIOR", "TANK") })
    E.At(4)
    E.Start()
    E.Five("r10a-", "Tank")
    E.At(27)
    E.S.units.player.dead = true -- no tick between the death and the flag
    E.Stop()
    E.Flush()
    local recA = E.Last()
    E.S.units.player.dead = false

    E.At(40)
    E.Start()
    E.Five("r10b-", "Tank")
    E.At(63)
    -- T54 (P10, review Q8): the re-poll is MD.API.After(1, ...) and its point
    -- is WHEN it runs -- a dead flag trailing the combat flag by half a second
    -- is still seen, because the poll waits a second. Driven by the clock:
    -- nothing is stored at +0.5 s, the pull is stored with the death at +1 s.
    local _, nStop = E.Last()
    E.Stop()                      -- the combat flag first ...
    E.S.Tick(0.5)
    local _, nHalf = E.Last()
    E.S.units.player.dead = true  -- ... the dead flag half a second after it
    E.S.Tick(0.5)
    local recB, nOne = E.Last()
    local pendingB = E.S.Pending and E.S.Pending() or #(E.S.timers or {})
    E.S.units.player.dead = false
    check("R10 (review Q8): the death re-poll runs at +1 s on the clock: nothing stored at +0.5 s, the death seen at +1 s",
        nHalf == nStop and nOne == nStop + 1 and recB ~= nil and #recB.deaths == 1 and pendingB == 0,
        string.format("stored at stop/+0.5/+1 = %s/%s/%s deaths=%s pending=%s", tostring(nStop), tostring(nHalf),
            tostring(nOne), tostring(recB and #recB.deaths), tostring(pendingB)))
    check("R10: the healer's own death is recorded when it ends the pull, whichever event comes first",
        recA ~= nil and #recA.deaths == 1 and recA.deaths[1][2] == 1
        and recB ~= nil and recB ~= recA and #recB.deaths == 1 and recB.deaths[1][2] == 1,
        string.format("a=%s b=%s", tostring(recA and #recA.deaths), tostring(recB and recB ~= recA and #recB.deaths)))
end

-- R11: a chain pull -- combat starts again inside the second before the meter
-- is read. The ended pull's reading is missing, not the new fight's totals,
-- even when the meter would answer in combat.
do
    local E = Fresh({ Unit("G-A", "Tank", "WARRIOR", "TANK") })
    E.S.meterSecretInCombat = false
    E.At(4)
    E.Start()
    E.Five("r11a-", "Tank")
    E.At(28)
    E.Stop()
    E.S.Tick(0.5)
    E.Start() -- the next pack, inside the second
    E.S.meter.sources = { { sourceGUID = E.S.units.player.guid, isLocalPlayer = true, totalAmount = 7 } }
    E.Flush()
    local recA = E.Last()
    E.S.meterSecretInCombat = nil
    E.Five("r11b-", "Tank")
    E.At(60)
    E.Stop()
    E.Flush()
    check("R11: a meter read that finds combat again is stored as no reading, not the next fight's totals",
        recA ~= nil and recA.meter and recA.meter.read == "none" and recA.meter.why == "combat"
        and recA.foreignShare == nil,
        string.format("read=%s why=%s own=%s", tostring(recA and recA.meter and recA.meter.read),
            tostring(recA and recA.meter and recA.meter.why), tostring(recA and recA.meter and recA.meter.own)))
end

-- R25: a member who left keeps their index but not their token -- the aura
-- scan does not read the member now on that token a second time.
-- R24: nor does the death poll, when the member leaves mid-pull.
do
    local rejuv = { [1] = { name = "Rejuvenation", spellId = 774, expirationTime = 900, applications = 0 } }
    local E = Fresh({ Unit("G-A", "Tank", "WARRIOR", "TANK"),
                      Unit("G-B", "Mage", "MAGE", "DAMAGER"),
                      Unit("G-C", "Rogue", "ROGUE", "DAMAGER", { auras = rejuv }) })
    -- roster: player 1, Tank 2, Mage 3, Rogue 4. The Mage leaves; the
    -- Rogue's token moves from party3 to party2.
    E.S.units.party2, E.S.units.party3 = E.S.units.party3, nil
    E.S.Fire("GROUP_ROSTER_UPDATE")
    E.At(8) -- out-of-combat scans
    E.Start()
    local rec0 = nil
    E.Five("r25-", "Tank")
    E.At(30)
    E.Stop()
    E.Flush()
    rec0 = E.Last()
    local tgts = {}
    for _, a in ipairs(rec0 and rec0.initial.auras or {}) do tgts[#tgts + 1] = tostring(a.tgt) end
    check("R25: a departed member's stale token is not read by the aura scan",
        rec0 ~= nil and #rec0.initial.auras == 1 and rec0.initial.auras[1].tgt == 4,
        string.format("auras on %s", table.concat(tgts, ",")))

    -- R24: the Tank leaves mid-pull (the Rogue moves to party1), then the
    -- Rogue dies: one death, the Rogue's.
    E.At(40)
    E.Start()
    E.Five("r24-", "Tank")
    E.At(45)
    E.S.units.party1, E.S.units.party2 = E.S.units.party2, nil
    E.S.Fire("GROUP_ROSTER_UPDATE")
    E.At(50)
    E.S.units.party1.dead = true
    E.At(66)
    E.Stop()
    E.Flush()
    local rec = E.Last()
    local who = {}
    for _, d in ipairs(rec and rec.deaths or {}) do who[#who + 1] = tostring(d[2]) end
    check("R24: a member who leaves mid-pull is not polled through a token that now names another",
        rec ~= nil and rec ~= rec0 and #rec.deaths == 1 and rec.deaths[1][2] == 4,
        string.format("deaths on %s", table.concat(who, ",")))
end

--------------------------------------------------------------------------------
-- T49 (P5), B14: every stored stream pinned (as the Review tab's old direct
-- toggle, or an old SavedVariables file, could leave them) -- the ninth pull is
-- still stored. Only the first MAX_PINNED pins protect, as TBC's recorder does.
--------------------------------------------------------------------------------
do
    local E = Fresh({ Unit("G-A", "Tank", "WARRIOR", "TANK") })
    local t = 4
    for p = 1, 8 do
        E.At(t)
        E.Start()
        E.Five("b14-" .. p .. "-", "Tank")
        E.At(t + 25)
        E.Stop()
        E.Flush()
        t = t + 40
    end
    local list = E.MD.cdb.recordings or {}
    local before = {}
    for i, r in ipairs(list) do r.pinned = true; before[r] = i end
    local eight = #list
    E.At(t)
    E.Start()
    E.Five("b14-9-", "Tank")
    E.At(t + 25)
    E.Stop()
    E.Flush()
    list = E.MD.cdb.recordings or {}
    local ninth, firstTwoKept = nil, true
    for _, r in ipairs(list) do if not before[r] then ninth = r end end
    for r, i in pairs(before) do
        if i <= 2 then
            local still = false
            for _, x in ipairs(list) do if x == r then still = true end end
            firstTwoKept = firstTwoKept and still
        end
    end
    check("B14: with all eight stored streams pinned the ninth pull is still stored (the first two pins kept)",
        eight == 8 and #list == 8 and ninth ~= nil and firstTwoKept,
        string.format("before=%d after=%d ninth=%s firstTwoKept=%s", eight, #list, tostring(ninth ~= nil),
            tostring(firstTwoKept)))
end

--------------------------------------------------------------------------------
-- T49 (P5), B15: a cross-realm member. UNIT_SPELLCAST_SENT names them
-- "Name-Realm" (the retail convention, unverified on the beta); the roster
-- keeps the bare name (what other recordings are matched on) and the realm
-- beside it, and a cast at them is theirs, not foreign.
--------------------------------------------------------------------------------
do
    local E = Fresh({ Unit("G-H", "Healer", "PRIEST", "HEALER", { realm = "OtherRealm" }),
                      Unit("G-T1", "Tank", "WARRIOR", "TANK", { realm = "RealmA" }),
                      Unit("G-T2", "Tank", "PALADIN", "TANK", { realm = "RealmB" }) })
    E.At(4)
    E.Start()
    E.Cast("xr-h", 774, "Healer-OtherRealm")
    E.Cast("xr-b", 5185, "Tank-RealmB")
    E.Cast("xr-a", 8936, "Tank-RealmA")
    E.Five("xr-", "Healer-OtherRealm")
    E.At(30)
    E.Stop()
    E.Flush()
    local rec = E.Last()
    local h = rec and FindEvent(rec, K.OWNCAST, function(r) return r.x == 774 end)
    local b = rec and FindEvent(rec, K.OWNCAST, function(r) return r.x == 5185 end)
    local a = rec and FindEvent(rec, K.OWNCAST, function(r) return r.x == 8936 end)
    check("B15: a cross-realm member's Name-Realm target resolves to their roster index",
        h ~= nil and h.tgt == 2, string.format("tgt=%s", tostring(h and h.tgt)))
    check("B15: two same-name members on different realms are told apart by the full name",
        a ~= nil and b ~= nil and a.tgt == 3 and b.tgt == 4,
        string.format("RealmA=%s RealmB=%s", tostring(a and a.tgt), tostring(b and b.tgt)))
    local e = rec and rec.roster and rec.roster[2]
    check("B15: the stored roster name stays bare, the realm beside it",
        e ~= nil and e.name == "Healer" and e.realm == "OtherRealm" and rec.roster[1].realm == nil,
        string.format("name=%s realm=%s player realm=%s", tostring(e and e.name), tostring(e and e.realm),
            tostring(rec and rec.roster[1] and rec.roster[1].realm)))
end

-- T49 (P5), B15 (review): a member whose name reads secret. The adapter
-- answers a failed read with nil and its status word ("secret" / "absent" /
-- "error"), so the second value is not a realm and must not be stored as one.
do
    local E = Fresh({ Unit("G-S", "Hidden", "WARRIOR", "TANK", { realm = "RealmA" }) })
    E.S.units.party1.name = E.S.Secret()
    E.At(4)
    E.Start()
    E.Five("sr-", "Healroot")
    E.At(30)
    E.Stop()
    E.Flush()
    local rec = E.Last()
    local e = rec and rec.roster and rec.roster[2]
    check("B15: a member whose name reads secret is stored with no realm (the status word is not one)",
        e ~= nil and e.name == nil and e.realm == nil,
        string.format("roster[2]=%s name=%s realm=%s", tostring(e ~= nil), tostring(e and e.name), tostring(e and e.realm)))
end

-- T54 (P10, review Q8): every pull above ended on the clock; nothing its end
-- queued was left pending one second on.
check("review Q8: one second after every pull, no timer is left pending (the clock ran them, not a flush)",
    #leftovers == 0, #leftovers > 0 and table.concat(leftovers, "; ") or nil)

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
