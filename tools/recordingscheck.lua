-- tools/run.sh --flavour tbc tools/recordingscheck.lua
-- tools/run.sh --flavour forever tools/recordingscheck.lua
--
-- T62 (P18, review A5, B16's root): one recordings router, Engine/Recordings.lua,
-- on both lines. Every address a command, the Review tab or the replay window
-- hands MD:GetRecording goes through one grammar -- "" / nil the newest fight,
-- "N" a fight, "pN" a practice fight, "a:b" a run's pull -- answered by the
-- provider its shape names: Engine/FightRecorder.lua (tbc) or
-- Recorder_Forever.lua (forever) for bare N, Engine/Practice.lua for pN,
-- Engine/RunRecorder.lua for a:b (tbc only: Forever records no runs).
--
-- What is asserted, under each flavour:
--   * the router is there and each flavour's providers registered their shape
--     (and only those), a second provider for a shape raising;
--   * the grammar table: each address against the seeded fights, practice
--     fights and runs -- the rows the plan names ("", 1, 3, p2, 2:7, foo, 2x,
--     p, :7) and the edges around them (nil, a number, P2, padding, a fight
--     that is not there). An address neither shape reads is REFUSED (nil):
--     it used to mean recording 1 (`tonumber(spec) or 1`), which is how B16
--     printed a card for the wrong fight;
--   * the pin cap, shared: two fights pinned, a third refused with a line --
--     through the router and through the recorder's own Pin -- and a pull or
--     an unreadable address never pinned;
--   * both recorders keep a pull by MD.Util.RECORD_GATE, not a copy of it.
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local T = dofile(here .. "/lib/t.lua")
local check = T.check

local function NewSession()
    _G.SpellTunerDB = nil
    _G.ManaDemonDB = nil
    local a0 = arg[0]; arg[0] = here .. "/harness.lua"
    local MD = dofile(here .. "/harness.lua")
    arg[0] = a0
    return MD, _G.STUB
end

local MD, S = NewSession()
local FOREVER = S.flavour == "forever"
if FOREVER then
    -- Practice needs Replay, which needs Recorder: all three providers' files
    MD:SetModule("SpellTuner_Practice", true)
end
local REC = MD.Recordings

--------------------------------------------------------------------------------
T.section("the router and its providers (" .. S.flavour .. ")")
--------------------------------------------------------------------------------
check("Engine/Recordings.lua is loaded: MD.Recordings with Register, Get, List, Pin",
    type(REC) == "table" and type(REC.Register) == "function" and type(REC.Get) == "function"
    and type(REC.List) == "function" and type(REC.Pin) == "function",
    type(REC))
-- Without the router (the parent commit) the grammar table below still runs
-- through MD:GetRecording, so what the old parsers answer is on record; the
-- rest needs the router and is not reached.
local HAVE = type(REC) == "table"

if HAVE then
local shapes = {}
for _, p in ipairs({ "", "p", ":" }) do shapes[#shapes + 1] = (REC.Provider(p) and "+" or "-") .. "'" .. p .. "'" end
local want = FOREVER and "+'' +'p' -':'" or "+'' +'p' +':'"
check("each flavour's providers registered their shape: fights, practice" .. (FOREVER and "" or ", runs"),
    table.concat(shapes, " ") == want, table.concat(shapes, " "))

local okDup, errDup = pcall(REC.Register, "", { Get = function() end, List = function() return {} end })
check("a second provider for a shape raises, naming it",
    not okDup and tostring(errDup):find("second provider", 1, true) ~= nil, tostring(errDup))
end

--------------------------------------------------------------------------------
T.section("the grammar")
--------------------------------------------------------------------------------
-- Seeded out of order: every List is newest first by id.
local f101, f102, f103 = { id = 101 }, { id = 102 }, { id = 103 }
MD.cdb.recordings = { f101, f103, f102 }
local p201, p202 = { id = 201 }, { id = 202 }
MD.cdb.practice = { p202, p201 }
local pullA = { id = 301 }
local older = { id = 1000, pulls = {} }
for k = 1, 7 do older.pulls[k] = (k == 7) and pullA or { id = 300 + k * 10 } end
local newer = { id = 2000, pulls = { { id = 401 } } }
MD.cdb.runs = { older, newer }

-- spec -> { rec, label, run, pull } (run and pull only for a run's pull)
local ROWS = {
    { spec = nil,   rec = f103, label = "1" },
    { spec = "",    rec = f103, label = "1" },
    { spec = "  ",  rec = f103, label = "1" },
    { spec = "1",   rec = f103, label = "1" },
    { spec = 1,     rec = f103, label = "1" },
    { spec = "3",   rec = f101, label = "3" },
    { spec = " 3 ", rec = f101, label = "3" },
    { spec = "03",  rec = f101, label = "3" },
    { spec = "9",   rec = nil,  label = "9" },
    { spec = "p2",  rec = p201, label = "p2" },
    { spec = "P2",  rec = p201, label = "p2" },
    { spec = "p9",  rec = nil,  label = "p9" },
    { spec = "2:7", rec = (not FOREVER) and pullA or nil, label = "2:7",
      run = (not FOREVER) and older or nil, pull = (not FOREVER) and 7 or nil },
    { spec = "1:1", rec = (not FOREVER) and newer.pulls[1] or nil, label = "1:1",
      run = (not FOREVER) and newer or nil, pull = (not FOREVER) and 1 or nil },
    { spec = "foo", rec = nil, label = "foo" },
    { spec = "2x",  rec = nil, label = "2x" },
    { spec = "p",   rec = nil, label = "p" },
    { spec = ":7",  rec = nil, label = ":7" },
    { spec = "1.5", rec = nil, label = "1.5" },
    { spec = "0x2", rec = nil, label = "0x2" },
    { spec = "-1",  rec = nil, label = "-1" },
}
local function Name(r)
    if r == nil then return "nil" end
    return "#" .. tostring(r.id)
end
for _, row in ipairs(ROWS) do
    local rec, label, run, pull = MD:GetRecording(row.spec)
    local rec2 = HAVE and REC.Get(row.spec) or rec
    local shown = row.spec == nil and "nil" or (type(row.spec) == "number" and tostring(row.spec) .. " (a number)")
        or ('"' .. row.spec .. '"')
    check(string.format("%-14s -> %s", shown, row.rec and (Name(row.rec) .. " as " .. row.label) or "refused"),
        rec == row.rec and label == row.label and run == row.run and pull == row.pull and rec2 == rec,
        string.format("got %s label=%s run=%s pull=%s", Name(rec), tostring(label), Name(run), tostring(pull)))
end

if not HAVE then T.done() end

check("List answers each shape's recordings newest first",
    REC.List("")[1] == f103 and REC.List("")[3] == f101 and REC.List("p")[1] == p202
    and #REC.List("x") == 0,
    string.format("%s %s", Name(REC.List("")[1]), Name(REC.List("p")[1])))

--------------------------------------------------------------------------------
T.section("the pin cap")
--------------------------------------------------------------------------------
local ok1 = REC.Pin("1", true)
local ok2 = REC.Pin("2", true)
local ok3, why3 = REC.Pin("3", true)
check("two fights pin, a third is refused with a line",
    ok1 == true and ok2 == true and ok3 == false and f101.pinned ~= true
    and why3 == "at most " .. REC.MAX_PINNED .. " fights can be pinned - unpin one first.",
    tostring(why3))
local okFR, whyFR = MD.FightRecorder:Pin(3, true)
check("...and the recorder's own Pin (what the Review tab calls) refuses it the same way",
    okFR == false and whyFR == why3 and f101.pinned ~= true, tostring(whyFR))
local okAgain = REC.Pin("1", true)
check("pinning a fight already pinned is not a third pin", okAgain == true and f103.pinned == true)
local okOff = MD.FightRecorder:Pin(1, false)
local okNow = REC.Pin("3", true)
check("unpin one and the third pins", okOff == true and f103.pinned == false and okNow == true
    and f101.pinned == true)
local okFoo, whyFoo = REC.Pin("foo", true)
local okPull, whyPull = REC.Pin("2:7", true)
check("an unreadable address and a run's pull are never pinned",
    okFoo == false and whyFoo ~= nil and okPull == false and whyPull ~= nil and pullA.pinned ~= true,
    tostring(whyFoo) .. " / " .. tostring(whyPull))
local okP = REC.Pin("p1", true)
check("a practice fight pins through the router, under practice's own cap",
    okP == true and p202.pinned == true and REC.Provider("p").pinCap == MD.Practice.MAX_PINNED)
for _, r in ipairs({ f101, f102, f103, p201, p202 }) do r.pinned = false end

--------------------------------------------------------------------------------
T.section("the recording gate")
--------------------------------------------------------------------------------
-- One pull of 10 s with 3 own casts: under the shipped gate (20 s / 5 casts)
-- it is not kept; with MD.Util.RECORD_GATE lowered it is. A recorder that
-- kept its own 20 / 5 would drop it both times.
local function OnePull(M, St)
    if FOREVER then
        local g = St.now
        St.inCombat = true
        St.Fire("PLAYER_REGEN_DISABLED")
        for i = 1, 3 do
            local id = "gate-" .. tostring(g) .. "-" .. i
            St.Fire("UNIT_SPELLCAST_SENT", "player", "Healroot", id, 774)
            St.Fire("UNIT_SPELLCAST_START", "player", id, 774)
            St.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", id, 774)
            St.Fire("UNIT_SPELLCAST_STOP", "player", id, 774)
        end
        local t = St.now + 10
        while St.now < t - 1e-6 do St.Tick(0.5) end
        St.inCombat = false
        St.Fire("PLAYER_REGEN_ENABLED")
        t = St.now + 1.5
        while St.now < t - 1e-6 do St.Tick(0.5) end
    else
        local FR = M.FightRecorder
        FR:Start(GetTime())
        if FR.active then FR.active.ownCasts = 3 end
        FR:Finish(10, {})
    end
    return #(M.cdb.recordings or {})
end
do
    local M, St = NewSession()
    if FOREVER then
        St.units.player.name = "Healroot"
        St.units.player.auras = {}
        M:SetModule("SpellTuner_Recorder", true)
    end
    M.cdb.recordings = {}
    local shipped = M.Util.RECORD_GATE
    local keptShipped = OnePull(M, St)
    M.Util.RECORD_GATE = { sec = 5, casts = 2 }
    local keptLowered = OnePull(M, St)
    M.Util.RECORD_GATE = shipped
    check("the " .. (FOREVER and "Forever" or "TBC") .. " recorder keeps a pull by MD.Util.RECORD_GATE",
        shipped.sec == 20 and shipped.casts == 5 and keptShipped == 0 and keptLowered == 1,
        string.format("shipped gate: %d kept, lowered: %d kept", keptShipped, keptLowered))
end

T.done()
