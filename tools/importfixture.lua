-- tools/run.sh tools/importfixture.lua [out]
--
-- Builds the Forever SavedVariables fixture tools/import.lua is tested on
-- (tools/data/import-forever-sv.lua, or [out]): the real addon under the
-- stub's forever profile, with the three modules on, a level 10 druid's book
-- (Healing Touch R1-R2, Rejuvenation R1-R2 -- R2 of Healing Touch is NOT in
-- the stub's default book, so a tool that replays this file with the stub's
-- spells instead of the recorded kit cannot price the fight), then
--   * two practice sessions (Party) played through Engine/Practice.lua
--     against a fake clock: p1, 48 s -- HoTs and Healing Touch on the tank,
--     and a twelve-second window of no casting to regenerate in the middle,
--     the shape the author's own p1 has -- and p2, 30 s, stored without its
--     kit, as 0.16.1 stored every practice fight;
--   * one real pull through Modules/SpellTuner_Recorder/Recorder_Forever.lua's
--     own events (UNIT_COMBAT, the cast events, the damage meter), 30 s,
--     six own casts -- a v3 stream;
-- and writes SpellTunerDB the way the client writes a SavedVariables file
-- (tools/svwrite.lua, sorted keys, so the same code writes the same bytes).
-- tools/importcheck.lua rebuilds it and fails when the committed fixture is
-- no longer what the code writes: regenerate it with this script then.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")
local out = arg[2] or (here .. "/data/import-forever-sv.lua")

-- The stub's date() is the machine's local time; a fixture must not depend
-- on the time zone it was built in.
local FIXED_TIME = 1790704800   -- 2026-09-29 18:00 UTC, the day the author's p1 was played
_G.SpellTunerDB, _G.ManaDemonDB = nil, nil

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB
function date(fmt, t)
    fmt = fmt or "%c"
    if fmt:sub(1, 1) ~= "!" then fmt = "!" .. fmt end
    return os.date(fmt, t or FIXED_TIME)
end
function time() return FIXED_TIME end

-- A level 10 druid on the beta: 364 mana, the author's own p1 pool.
S.level = 10
MD.player.level = 10
S.mana, S.manaMax = 364, 364
S.crit[4] = 5
-- ...regenerating like one: 5.5 mana a second outside the five-second rule,
-- nothing inside it (no mp5 at level 10). The stub's own GetManaRegen answers
-- a level 64's 69/28, and the adapter has already cached that function, so
-- the adapter's binding is replaced instead (plain out of combat, secret in
-- it, as the client answers).
MD.API.ManaRegen = function()
    if S.inCombat then return nil, "secret" end
    return 5.5, 0
end
-- Healing Touch R2 at level 8, the rank the author's p1 cast (5186; its
-- description in probe report 70009: "90 to 115"; the stub's 5185 is R1).
S.AddSpell(5186, "Healing Touch", "Rank 2",
    function() return "Heals a friendly target for 90 to 115." end,
    { cast = 2000, cost = 55, level = 8, base = 5185 })

-- the party the recorded pull is healed in
S.units.player.name = "Healroot"
S.units.player.hpMax, S.units.player.hp = 280, 280
S.AddUnit("party1", { guid = "Party-1-guid", name = "Tank", class = "WARRIOR", role = "TANK",
                       hp = 420, hpMax = 420 })
S.AddUnit("party2", { guid = "Party-2-guid", name = "Mage", class = "MAGE", role = "DAMAGER",
                       hp = 240, hpMax = 240 })
S.units.player.auras = {}

MD:SetModule("SpellTuner_Practice", true)   -- Recorder, Replay (the kit) and Practice
assert(MD.Practice and MD.RankMath and MD.RankMath.KitSnapshot, "the modules did not load")
MD.RankMath:SpellKit()   -- the book read once, as opening the window would

--------------------------------------------------------------------------------
-- 1: a practice session, played
--------------------------------------------------------------------------------
local PR, SD = MD.Practice, MD.SpellData
local HT2, HT1, RJ2 = 5186, 5185, 1058
assert(SD.spells[HT2] and SD.spells[RJ2], "the kit has no Healing Touch R2 / Rejuvenation R2")

local function Play(dur, seed, presses)
    local setup = PR.DefaultSetup("5", 10)
    setup.dur, setup.fixedSeed = dur, seed
    -- a level 10 party's damage: the tank hit steadily, a spike now and then
    -- on everybody -- light enough that 364 mana can hold it, as the author's did
    PR.ApplyRole(setup, "TANK", { dps = 0.02, spike = 0.12, spikeEvery = 20 })
    for _, kind in ipairs({ "HEALER", "MELEE", "RANGED" }) do
        PR.ApplyRole(setup, kind, { spike = 0.10, spikeEvery = 30 })
    end
    MD.cdb.practiceSetup = PR.CopySetup(setup)
    local session = PR.New(PR.CopySetup(setup), { seed = setup.fixedSeed })
    session:Start()
    -- presses: { at, spell, target }. A press refused because a cast or the
    -- GCD is running is pressed again, as a player would, for up to a second.
    local nextI = 1
    while session.state == "running" do
        local p = presses[nextI]
        if p and session.clock >= p[1] - 1e-9 then
            if session:Cast(p[2], p[3]) or session.clock > p[1] + 1 then nextI = nextI + 1 end
        end
        session:Update(0.05)
    end
    assert(session.state == "done" and session.rec and session.rec.kit, "the practice session did not record")
    return session.rec
end

-- p2: an earlier, shorter fight, stored as 0.16.1 stored it -- before
-- practice fights carried their kit -- so the tool has to read the kit back
-- off the fight's own heals
function time() return FIXED_TIME - 300 end
local older = Play(30, 3, {
    { 0.5, HT2, 1 }, { 3.0, RJ2, 1 }, { 5.0, HT2, 1 }, { 12.0, HT2, 1 }, { 20.0, HT2, 4 }, { 24.0, RJ2, 1 },
})
-- 0.16.1 stored none of what a report now reads off a practice fight
older.kit, older.client, older.level, older.version, older.build = nil, nil, nil, nil, nil

-- p1: the author's shape -- HoTs and Healing Touch on the tank, then a
-- twelve-second window of no casting to regenerate in, then more of the same
function time() return FIXED_TIME end
Play(48, 7, {
    { 0.5, RJ2, 1 }, { 1.8, HT2, 1 }, { 4.2, HT2, 1 }, { 7.0, RJ2, 3 },
    -- 9 s to 21 s: nothing cast, the pool regenerating outside the 5SR
    { 21.0, HT2, 1 }, { 23.5, RJ2, 1 }, { 25.2, HT2, 1 }, { 30.0, HT1, 3 },
    { 36.0, HT2, 1 }, { 40.0, RJ2, 1 }, { 42.0, HT2, 1 },
})

--------------------------------------------------------------------------------
-- 2: a real pull, through the recorder's own events
--------------------------------------------------------------------------------
function time() return FIXED_TIME + 600 end
local function At(t) while S.now < t - 1e-6 do S.Tick(0.5) end end
local function Cast(guid, id, target)
    S.Fire("UNIT_SPELLCAST_SENT", "player", target, guid, id)
    S.Fire("UNIT_SPELLCAST_START", "player", guid, id)
    S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, id)
    S.Fire("UNIT_SPELLCAST_STOP", "player", guid, id)
end
S.zoneText = "The Barrens"
At(S.now + 10)
local t0 = S.now
S.inCombat = true
S.Fire("PLAYER_REGEN_DISABLED")
local script = {
    { 0.5, "dmg", "party1", 60 }, { 1.0, "cast", "c1", RJ2, "Tank" },
    { 2.5, "dmg", "party1", 55 }, { 3.0, "cast", "c2", HT2, "Tank" }, { 3.0, "heal", "party1", 102 },
    { 4.0, "heal", "party1", 14 }, { 5.0, "dmg", "party2", 70 }, { 6.5, "dmg", "party1", 58 },
    { 7.0, "heal", "party1", 14 }, { 8.0, "cast", "c3", RJ2, "Mage" }, { 10.0, "heal", "party1", 14 },
    { 10.5, "dmg", "party1", 62 }, { 11.0, "heal", "party2", 14 }, { 13.0, "heal", "party1", 14 },
    { 14.0, "heal", "party2", 14 }, { 14.5, "dmg", "party1", 57 }, { 17.0, "heal", "party2", 14 },
    { 18.0, "dmg", "party1", 61 }, { 19.0, "cast", "c4", HT2, "Tank" }, { 19.0, "heal", "party1", 101 },
    { 20.0, "heal", "party2", 14 }, { 21.5, "dmg", "party1", 59 }, { 23.0, "heal", "party2", 14 },
    { 24.0, "cast", "c5", HT1, "Healroot" }, { 24.0, "heal", "player", 47 }, { 25.0, "dmg", "party1", 60 },
    { 27.0, "cast", "c6", RJ2, "Tank" }, { 28.5, "dmg", "party1", 56 }, { 30.0, "heal", "party1", 14 },
}
for _, e in ipairs(script) do
    At(t0 + e[1])
    if e[2] == "dmg" then S.Combat(e[3], "WOUND", e[4])
    elseif e[2] == "heal" then S.Combat(e[3], "HEAL", e[4])
    else Cast(e[3], e[4], e[5]) end
end
At(t0 + 31)
S.inCombat = false
S.Fire("PLAYER_REGEN_ENABLED")
S.meter.sources = {
    { sourceGUID = S.units.player.guid, isLocalPlayer = true, totalAmount = 450, name = "Healroot" },
}
for _, fn in ipairs(S.timers or {}) do fn() end
local recs = MD.cdb.recordings or {}
assert(#recs == 1 and recs[1].v == 3 and recs[1].kit, "the recorder kept no v3 stream with its kit")

--------------------------------------------------------------------------------
-- The file. What the client would write, less what is this build's and this
-- machine's rather than the fixture's: the probe's report and the debug
-- settings are left as they are; the session stamp is fixed by date() above.
--------------------------------------------------------------------------------
local db = _G.SpellTunerDB
-- stamped at ADDON_LOADED, before date() above was fixed
local stamp = date("%Y-%m-%d %H:%M:%S")
db.session = { stamp = stamp, count = 3 }
if db.probe then db.probe.stamp = stamp end
-- the character as the beta names it (the stub logged in as Penek-Anniversary)
local CHAR = "Healroot-Classic Beta PvP"
db.char[CHAR], db.char[MD.player.charKey] = db.char[MD.player.charKey], nil

local W = dofile(here .. "/svwrite.lua")
W.Write(out, { SpellTunerDB = db })
print(string.format("wrote %s: %s, %d practice, %d recording(s)", out, CHAR,
    #(db.char[CHAR].practice or {}), #recs))
