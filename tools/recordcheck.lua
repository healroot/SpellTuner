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

local timerCursor = 0
local function FlushTimers()
    for i = timerCursor + 1, #(S.timers or {}) do S.timers[i]() end
    timerCursor = #(S.timers or {})
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
At(28)
S.units.party1, S.units.party2 = S.units.party2, S.units.party1
S.Fire("GROUP_ROSTER_UPDATE")
S.Combat("party1", "WOUND", 111) -- party1 is now Mage (idx 3)

-- A death at 30s: whoever now sits at party2 (Tank, idx 2).
At(37.5)
S.units.party2.dead = true
At(38)

-- The pull ends at 40s.
At(48)
S.inCombat = false
S.Fire("PLAYER_REGEN_ENABLED")
S.meter.sources = {
    { sourceGUID = S.units.player.guid, isLocalPlayer = true, totalAmount = 400, name = "Healroot" },
    { sourceGUID = "Other-1", isLocalPlayer = false, totalAmount = 120, name = "Someone" },
}
FlushTimers()

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
--    once combat is over
--------------------------------------------------------------------------------
check("a pull starts at combat and ends after it, and the damage meter is read once combat is over",
    rec ~= nil and math.abs((rec.dur or -1) - 40) < 0.001 and rec.meter and rec.meter.read == "current",
    string.format("rec=%s dur=%s meter.read=%s", tostring(rec), tostring(rec and rec.dur),
        tostring(rec and rec.meter and rec.meter.read)))

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

    check("own HoTs on the party are read before the pull, never in combat",
        rec ~= nil and #rec.initial.auras == 1 and rec.initial.auras[1].spellId == 774
        and rec.initial.auras[1].token == "party1" and math.abs((rec.initial.auras[1].remaining or -1) - 900) < 0.001
        and blocked,
        string.format("auras=%s auraCalls before=%s after=%s", tostring(rec and #rec.initial.auras),
            tostring(before), tostring(afterCombat)))
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
    FlushTimers()
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
    FlushTimers()
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

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
