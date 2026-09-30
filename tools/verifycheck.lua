-- tools/run.sh tools/verifycheck.lua [--print | --golden]
--
-- T56 (P12, review A2): a golden transcript of the TBC diagnostic and review
-- commands under the stub. Verify.lua was split into Diagnostics_TBC.lua,
-- Engine/RegenMeasure.lua, Engine/SimSelfTest.lua and Engine/ReviewCommands.lua
-- as a pure move; this suite is what proves the move changed nothing a user
-- sees. The golden at the bottom was captured on the parent commit (fecaad4),
-- before the first edit, with `--golden`, and each command's chat output must
-- equal it line for line. `--print` shows the transcript as chat would.
--
-- The scene: the shared scripted pull (tools/fakepull.lua) in the ring of 8,
-- then a run of two pulls, so /md coach 1, /md simreplay 1 and /md coachrun 1
-- have something to say. The harness loads no UI, so MD.ShowCopyPopup is
-- absent and /md profile, /md export and a long coach card print to chat --
-- which is what makes them comparable here. /md fsrtest and /md spamtest are
-- driven through a short scripted mana stream (their event handlers moved
-- too); /md regentest has its own suite (tools/regencheck.lua).
--
-- What the suite sets so the golden holds on any machine: the stub's date()
-- is read in UTC (the export's header and the coach card carry a time), and
-- GetBuildInfo, which the TBC stub lacks, answers a fixed build. What is
-- replaced before comparing: the addon's version string by {version}, so a
-- version bump is not a failure. Nothing else.
local here = arg[0]:match("^(.*)/[^/]+$")
local mode = "check"
for i = 2, #arg do
    if arg[i] == "--print" then mode = "print" elseif arg[i] == "--golden" then mode = "golden" end
end

HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB

-- The TBC stub has no GetBuildInfo, which /md profile's first line reads; the
-- client always has it. A fixed answer, so the line is the same everywhere.
if _G.GetBuildInfo == nil then
    _G.GetBuildInfo = function() return "2.5.5", "65000", "Sep 1 2026", 20506 end
end
-- The stub's date() reads the machine's zone. UTC instead.
do
    local stubDate = _G.date
    _G.date = function(fmt, t)
        if type(fmt) == "string" and fmt:sub(1, 1) ~= "!" then fmt = "!" .. fmt end
        return stubDate(fmt, t)
    end
end

local out = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) out[#out + 1] = m end }

--------------------------------------------------------------------------------
-- The scene
--------------------------------------------------------------------------------
dofile(here .. "/fakepull.lua")(MD, S)
MD.db.debug.enabled = false
function MD:DebugLog() end

local SD = MD.SpellData
local RR = MD.RunRecorder
local PLAYER = "Player-1"
local rejuv, regrowth = SD.maxRank.Rejuvenation, SD.maxRank.Regrowth
local function ev(sub, src, dst, dstName, ...)
    S.Combat(0, sub, false, src, "src", 0, 0, dst, dstName, 0, 0, ...)
end
local function power(v)
    S.mana = v
    S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
end
local function cast(spellID, dst, dstName)
    ev("SPELL_CAST_SUCCESS", PLAYER, dst, dstName, spellID, "S", 8)
    S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, spellID)
    power(S.mana - (SD:GetCost(spellID) or 0))
end
local function swing(dst, dstName, amount)
    ev("SWING_DAMAGE", "Mob-1", dst, dstName, amount, 0, 1, 0, 0, 0, false)
end
-- /md fsrtest ends on a C_Timer.After(15). The stub's After only collects its
-- callbacks (and wave 4's P10 may change that), so the global is replaced here
-- by a scheduler this suite fires itself, on the stub's clock. Only calls made
-- through the global after this line see it -- fsrtest's is one.
local timers = {}
_G.C_Timer.After = function(delay, fn) timers[#timers + 1] = { at = S.now + (delay or 0), fn = fn } end
local function FireTimers()
    local i = 1
    while i <= #timers do
        local tm = timers[i]
        if tm.at <= S.now + 1e-9 then table.remove(timers, i); tm.fn() else i = i + 1 end
    end
end
local function advance(sec)
    for _ = 1, math.floor(sec / 0.5 + 0.5) do S.Tick(0.5); FireTimers() end
end
local function pull(dur, casts)
    power(S.manaMax)
    S.units.party1.hp = 5000
    S.Fire("PLAYER_REGEN_DISABLED")
    swing("Tank-1", "Destroyka", 1500)
    local gap = dur / (casts + 1)
    for i = 1, casts do
        advance(gap)
        cast(i % 2 == 0 and regrowth or rejuv, "Tank-1", "Destroyka")
    end
    advance(gap)
    S.Fire("PLAYER_REGEN_ENABLED")
end

advance(10)
S.inInstance = true
RR:Start("manual", "Verify test")
pull(40, 8)
advance(10)
pull(35, 7)
advance(4)
RR:Stop("manual")
advance(2)
power(5000)
advance(6)

--------------------------------------------------------------------------------
-- The transcript: each command, its chat lines. A coach runs frame-sliced, so
-- the stub's frames are pumped until the search has answered; fsrtest and
-- spamtest get a scripted stream after they are armed.
--------------------------------------------------------------------------------
local function Pump(field)
    local frames = 0
    while MD[field] and frames < 40000 do S.Tick(0.016); frames = frames + 1 end
end

local function FsrStream()
    advance(1)
    cast(rejuv, "Tank-1", "Destroyka")
    advance(2); power(S.mana + 11)
    advance(2); power(S.mana + 11)
    advance(2); power(S.mana + 60)
    advance(2); power(S.mana + 60)
    advance(10)
    power(2000)          -- after fsrtest has stopped listening: spamtest arms at 2000
    advance(1)
end

-- Rejuvenation chained to OOM with one Regrowth mixed in (the NOTE line) and
-- a small regen tick after each cast.
local function SpamStream()
    advance(1)
    for i = 1, 6 do
        cast(i == 3 and regrowth or rejuv, "Tank-1", "Destroyka")
        advance(1.5)
        power(S.mana + 20)
    end
    advance(12)
end

local COMMANDS = {
    { "verify" },
    { "profile" },
    { "export" },
    { "calibrate" },
    { "fsrtest", nil, FsrStream },
    { "spamtest", nil, SpamStream },
    { "simrun" },
    { "simreplay fixture" },
    { "simreplay 1" },
    { "coach 1", "coachSearch" },
    { "coach 1 force", "coachSearch" },
    { "coachrun 1", "runSearch" },
}

local version = MD.version or "dev"
local function Plain(s, find, repl)
    local i, j = s:find(find, 1, true)
    while i do
        s = s:sub(1, i - 1) .. repl .. s:sub(j + 1)
        i, j = s:find(find, i + #repl, true)
    end
    return s
end

local transcript = {}
for _, c in ipairs(COMMANDS) do
    out = {}
    SlashCmdList.SPELLTUNER(c[1])
    if c[2] then Pump(c[2]) end
    if c[3] then c[3]() end
    local lines = {}
    for i, l in ipairs(out) do lines[i] = Plain(l, version, "{version}") end
    transcript[#transcript + 1] = { cmd = c[1], lines = lines }
end

if mode == "print" then
    for _, t in ipairs(transcript) do
        print("== /md " .. t.cmd .. " (" .. #t.lines .. ")")
        for _, l in ipairs(t.lines) do print(l) end
    end
    os.exit(0)
end

-- A line as Lua source: quotes, backslashes, tabs and every other control or
-- high byte escaped, so an editor cannot eat a tab or a trailing space.
local function Quote(s)
    return '"' .. s:gsub('[%c"\\\128-\255]', function(ch)
        if ch == "\t" then return "\\t" end
        if ch == '"' or ch == "\\" then return "\\" .. ch end
        return string.format("\\%03d", ch:byte())
    end) .. '"'
end

if mode == "golden" then
    print("local GOLDEN = {")
    for _, t in ipairs(transcript) do
        print("    { cmd = " .. Quote(t.cmd) .. ", lines = {")
        for _, l in ipairs(t.lines) do print("        " .. Quote(l) .. ",") end
        print("    } },")
    end
    print("}")
    os.exit(0)
end

--------------------------------------------------------------------------------
-- Compare
--------------------------------------------------------------------------------
local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-44s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local function Compare(GOLDEN)
    check("the golden has every command", #GOLDEN == #transcript,
        string.format("%d commands, golden %d", #transcript, #GOLDEN))
    for i, t in ipairs(transcript) do
        local g = GOLDEN[i] or { cmd = "?", lines = {} }
        local detail
        if g.cmd ~= t.cmd then
            detail = "golden is for /md " .. g.cmd
        else
            for k = 1, math.max(#g.lines, #t.lines) do
                if g.lines[k] ~= t.lines[k] then
                    detail = string.format("line %d of %d (golden %d):\n      now:    %s\n      golden: %s",
                        k, #t.lines, #g.lines, t.lines[k] and Quote(t.lines[k]) or "(none)",
                        g.lines[k] and Quote(g.lines[k]) or "(none)")
                    break
                end
            end
        end
        check("/md " .. t.cmd .. " as on the parent", detail == nil and #t.lines > 0,
            detail or (#t.lines == 0 and "no output" or string.format("%d lines", #t.lines)))
    end
end

local function Footer()
    print(string.format("\n%d ok, %d failed", ok, #fails))
    if #fails > 0 then for _, m in ipairs(fails) do print("  FAIL " .. m) end; os.exit(1) end
end

--------------------------------------------------------------------------------
-- T65 (P21, review A1): the review commands are shared with Forever and print
-- every line through MD:PrintSafe -- the one TBC change. A zone name with a
-- pipe and a non-ASCII byte reaches the coach card's header escaped (the
-- pipe doubled, the byte as \ddd), the card's own colour codes kept. Run
-- after the transcript, so the golden above is untouched by it.
--------------------------------------------------------------------------------
local PIPE_ZONE = "Blood|Furnace\195\169"
local PIPE_ZONE_PRINTED = "Blood||Furnace\\195\\169"
local function PipeZoneCheck()
    local rec = MD:GetRecording("1")
    local savedZone = rec and rec.zone
    if rec then rec.zone = PIPE_ZONE end
    out = {}
    SlashCmdList.SPELLTUNER("coach 1 force")
    Pump("coachSearch")
    if rec then rec.zone = savedZone end
    local saw, bad = false, nil
    for _, l in ipairs(out) do
        if l:find(PIPE_ZONE_PRINTED, 1, true) then saw = true end
        local stripped = l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "")
        if stripped:find("|", 1, true) then bad = bad or ("bare pipe: " .. Quote(l)) end
        if l:find("[^ -~]") then bad = bad or ("not ASCII: " .. Quote(l)) end
    end
    check("/md coach: a zone with a pipe prints escaped (T65)", rec ~= nil and saw and bad == nil,
        bad or string.format("%d lines, zone printed escaped: %s", #out, tostring(saw)))
end

--------------------------------------------------------------------------------
-- The golden: `tools/run.sh tools/verifycheck.lua --golden` on fecaad4, pasted.
--------------------------------------------------------------------------------
local GOLDEN = {
    { cmd = "verify", lines = {
        "|cff9966ffSpellTuner:|r -- verify: static data vs live client --",
        "|cff9966ffSpellTuner:|r |cffffaa33GetSpellPowerCost unavailable|r - the static table is in use; costs must be verified by hand (cast each rank at full idle mana and read the drop; compare to the table).",
        "|cff9966ffSpellTuner:|r checked 0 cast times, 0 costs - 0 mismatch(es).",
        "|cff9966ffSpellTuner:|r -- input snapshot --",
        "|cff9966ffSpellTuner:|r GetManaRegen: base 69.24/s, casting 28.33/s (x5 = 346 / 142 mp5)",
        "|cff9966ffSpellTuner:|r measured mp5: none - run /md regentest solo to measure the beat the API omits",
        "|cff9966ffSpellTuner:|r drink buff up: no; observed OOC fill 0.00/s (FSR duty 62%)",
        "|cff9966ffSpellTuner:|r spirit 380, int 425 -> spirit share 58.44/s (292 mp5), gear/buffs ~53 mp5, in-5SR fraction 30%",
        "|cff9966ffSpellTuner:|r +healing: 450 (not in Tree form)",
        "|cff9966ffSpellTuner:|r nature crit: 15.0%",
        "|cff9966ffSpellTuner:|r talents: Intensity 3, Moonglow 3, Tranquil Spirit 5, Gift of Nature 5, Improved Rejuvenation 3, Empowered Rejuvenation 5, Empowered Touch 2, Improved Regrowth 5, Naturalist 5, Nature's Grace 1",
        "|cff9966ffSpellTuner:|r relic: none equipped",
        "|cff9966ffSpellTuner:|r overheal (combat log, per character):",
        "|cff9966ffSpellTuner:|r   c:WARRIOR: overheal 68% over 5 events (needs 40)",
        "|cff9966ffSpellTuner:|r   f:Lifebloom: overheal 100% over 4 events (needs 40)",
        "|cff9966ffSpellTuner:|r   f:Rejuvenation: overheal 38% over 1 events (needs 40)",
        "|cff9966ffSpellTuner:|r   Rejuvenation r12 (26981) tick: overheal 38% over 1 events (needs 40)",
        "|cff9966ffSpellTuner:|r   Lifebloom r1 (33763) tick: overheal 100% over 4 events (needs 40)",
        "|cff9966ffSpellTuner:|r   r:TANK: overheal 68% over 5 events (needs 40)",
        "|cff9966ffSpellTuner:|r   Rejuvenation r12 (26981): overheal 38% over 1 events (needs 40)",
        "|cff9966ffSpellTuner:|r   Lifebloom r1 (33763): overheal 100% over 4 events (needs 40)",
        "|cff9966ffSpellTuner:|r   wasted this session: 4 events healed nothing, ~126 mana",
        "|cff9966ffSpellTuner:|r combat log 'amount' convention: GROSS (includes overheal)",
        "|cff9966ffSpellTuner:|r calibration (observed / model, non-crit events):",
        "|cff9966ffSpellTuner:|r   spell                  kind        n  observed     model  ratio  verdict",
        "|cff9966ffSpellTuner:|r   Lifebloom r1 R1        tick        4         -         -      -  too few",
        "|cff9966ffSpellTuner:|r   Rejuvenation r12 R12   tick        1         -         -      -  too few",
        "|cff9966ffSpellTuner:|r recorded fights: 3",
        "|cff9966ffSpellTuner:|r   [Blood Furnace] 0:26 || net -414 mp5 || spent 2.2k (RJ 46%, RG 24%, other 20%, LB 10%) || overheal 37% || spirit regen realized 100% || max-rank casts 83%",
        "|cff9966ffSpellTuner:|r   [Blood Furnace] 0:40 || net -424 mp5 || spent 3.4k (RG 61%, RJ 39%) || spirit regen realized 37% || max-rank casts 100%",
        "|cff9966ffSpellTuner:|r   [Blood Furnace] 0:36 || net -405 mp5 || spent 2.9k (RG 54%, RJ 46%) || spirit regen realized 38% || max-rank casts 100%",
        "|cff9966ffSpellTuner:|r For the FSR anchor: stand idle at partial mana, run /md fsrtest, cast ONE Healing Touch, and watch which tick sizes appear when. For Dreamstate: /md regentest.",
    } },
    { cmd = "profile", lines = {
        "|cff9966ffSpellTuner:|r === SpellTuner v{version} profile ===",
        "|cff9966ffSpellTuner:|r client build 65000, interface 20506, ElvUI absent",
        "|cff9966ffSpellTuner:|r Penek-Anniversary, DRUID level 64, form: caster / other, mana 5000/7009",
        "|cff9966ffSpellTuner:|r ",
        "|cff9966ffSpellTuner:|r --- inputs ---",
        "|cff9966ffSpellTuner:|r GetManaRegen: base 69.24/s, casting 28.33/s (x5 = 346 / 142 mp5)",
        "|cff9966ffSpellTuner:|r measured mp5: none - run /md regentest solo to measure the beat the API omits",
        "|cff9966ffSpellTuner:|r drink buff up: no; observed OOC fill 0.00/s (FSR duty 62%)",
        "|cff9966ffSpellTuner:|r spirit 380, int 425 -> spirit share 58.44/s (292 mp5), gear/buffs ~53 mp5, in-5SR fraction 30%",
        "|cff9966ffSpellTuner:|r +healing: 450 (not in Tree form)",
        "|cff9966ffSpellTuner:|r nature crit: 15.0%",
        "|cff9966ffSpellTuner:|r talents: Intensity 3, Moonglow 3, Tranquil Spirit 5, Gift of Nature 5, Improved Rejuvenation 3, Empowered Rejuvenation 5, Empowered Touch 2, Improved Regrowth 5, Naturalist 5, Nature's Grace 1",
        "|cff9966ffSpellTuner:|r relic: none equipped",
        "|cff9966ffSpellTuner:|r overheal (combat log, per character):",
        "|cff9966ffSpellTuner:|r   c:WARRIOR: overheal 68% over 5 events (needs 40)",
        "|cff9966ffSpellTuner:|r   f:Lifebloom: overheal 100% over 4 events (needs 40)",
        "|cff9966ffSpellTuner:|r   f:Rejuvenation: overheal 38% over 1 events (needs 40)",
        "|cff9966ffSpellTuner:|r   Rejuvenation r12 (26981) tick: overheal 38% over 1 events (needs 40)",
        "|cff9966ffSpellTuner:|r   Lifebloom r1 (33763) tick: overheal 100% over 4 events (needs 40)",
        "|cff9966ffSpellTuner:|r   r:TANK: overheal 68% over 5 events (needs 40)",
        "|cff9966ffSpellTuner:|r   Rejuvenation r12 (26981): overheal 38% over 1 events (needs 40)",
        "|cff9966ffSpellTuner:|r   Lifebloom r1 (33763): overheal 100% over 4 events (needs 40)",
        "|cff9966ffSpellTuner:|r   wasted this session: 4 events healed nothing, ~126 mana",
        "|cff9966ffSpellTuner:|r combat log 'amount' convention: GROSS (includes overheal)",
        "|cff9966ffSpellTuner:|r calibration (observed / model, non-crit events):",
        "|cff9966ffSpellTuner:|r   spell                  kind        n  observed     model  ratio  verdict",
        "|cff9966ffSpellTuner:|r   Lifebloom r1 R1        tick        4         -         -      -  too few",
        "|cff9966ffSpellTuner:|r   Rejuvenation r12 R12   tick        1         -         -      -  too few",
        "|cff9966ffSpellTuner:|r recorded fights: 3",
        "|cff9966ffSpellTuner:|r   [Blood Furnace] 0:26 || net -414 mp5 || spent 2.2k (RJ 46%, RG 24%, other 20%, LB 10%) || overheal 37% || spirit regen realized 100% || max-rank casts 83%",
        "|cff9966ffSpellTuner:|r   [Blood Furnace] 0:40 || net -424 mp5 || spent 3.4k (RG 61%, RJ 39%) || spirit regen realized 37% || max-rank casts 100%",
        "|cff9966ffSpellTuner:|r   [Blood Furnace] 0:36 || net -405 mp5 || spent 2.9k (RG 54%, RJ 46%) || spirit regen realized 38% || max-rank casts 100%",
        "|cff9966ffSpellTuner:|r ",
        "|cff9966ffSpellTuner:|r --- costs of known max ranks ---",
        "|cff9966ffSpellTuner:|r HealingTouch R12 (26978): live nil, static 664, cast 3.5s",
        "|cff9966ffSpellTuner:|r Lifebloom R1 (33763): live nil, static 220, cast 1.5s",
        "|cff9966ffSpellTuner:|r Rejuvenation R12 (26981): live nil, static 337, cast 1.5s",
        "|cff9966ffSpellTuner:|r Regrowth R9 (9858): live nil, static 523, cast 2.0s",
        "|cff9966ffSpellTuner:|r ",
        "|cff9966ffSpellTuner:|r --- clock ---",
        "|cff9966ffSpellTuner:|r mode ooc, tto -, ttf 29s, rest 29s, shown \"FULL 29s\"",
        "|cff9966ffSpellTuner:|r spend 39.90 +- 15.16 mana/s (3 casts, cv 0.38, half-life 15s), regen 43.56/s (duty 62%)",
        "|cff9966ffSpellTuner:|r ",
        "|cff9966ffSpellTuner:|r --- settings ---",
        "|cff9966ffSpellTuner:|r calibAlerts=true  drinkReminder=true  effectiveMode=false  firstRun=false  halfLife=15  healAmountGross=true  locked=true  muted=false  naturesGrace=true  oomConfidence=0.7  recordFights=true  recordRuns=true  recordThreat=true  replayAutoCoach=true  replayNextPull=true  replaySpeed=1  replayTicks=true  runAutoStart=false  runMaxMinutes=90  showCooldown=true  showRest=true  simAllowRebinds=false  simBigHit=0.15  simDangerHits=1  simFloor=0.3  simForeignShare=0.25  simFullHp=0.85  simGateHpMax=0.15  simGateHpMean=0.05  simGateManaMax=0.05  simGateManaMean=0.02  simMinActivity=0  simReaction=0.5  spellTooltip=true  spellTooltipDamage=true  treeAura=true  widgetTooltip=true",
        "|cff9966ffSpellTuner:|r debug: enabled=false, keep 1000 lines, categories: calib cast chat combat heal mana other regen sim spend tto",
    } },
    { cmd = "export", lines = {
        "|cff9966ffSpellTuner:|r # manademon {version}\tPenek-Anniversary\tDRUID 64\t2025-09-04 15:33\tamount:gross",
        "|cff9966ffSpellTuner:|r # fights",
        "|cff9966ffSpellTuner:|r t\tzone\tdur\tspent\tnetMp5\thealed\toverhealed\toomAt",
        "|cff9966ffSpellTuner:|r 1757000000\tBlood Furnace\t26.5\t2199\t-415\t250\t150\t",
        "|cff9966ffSpellTuner:|r 1757000000\tBlood Furnace\t40.5\t3440\t-425\t0\t0\t",
        "|cff9966ffSpellTuner:|r 1757000000\tBlood Furnace\t36.0\t2917\t-405\t0\t0\t",
        "|cff9966ffSpellTuner:|r # overheal",
        "|cff9966ffSpellTuner:|r key\tn\thealed\toverhealed",
        "|cff9966ffSpellTuner:|r c:WARRIOR\t5\t250\t541",
        "|cff9966ffSpellTuner:|r f:Lifebloom\t4\t0\t393",
        "|cff9966ffSpellTuner:|r f:Rejuvenation\t1\t250\t150",
        "|cff9966ffSpellTuner:|r k:26981:tick\t1\t250\t150",
        "|cff9966ffSpellTuner:|r k:33763:tick\t4\t0\t393",
        "|cff9966ffSpellTuner:|r r:TANK\t5\t250\t541",
        "|cff9966ffSpellTuner:|r s:26981\t1\t250\t150",
        "|cff9966ffSpellTuner:|r s:33763\t4\t0\t393",
        "|cff9966ffSpellTuner:|r # roster",
        "|cff9966ffSpellTuner:|r name\tclass\trole\troleSource\tkind",
        "|cff9966ffSpellTuner:|r Abufaisall\tWARLOCK\tDAMAGER\tassigned\tplayer",
        "|cff9966ffSpellTuner:|r Alkandari\tMAGE\tDAMAGER\tassigned\tplayer",
        "|cff9966ffSpellTuner:|r Destroyka\tWARRIOR\tTANK\tassigned\tplayer",
        "|cff9966ffSpellTuner:|r Penek\tDRUID\tHEALER\tassigned\tplayer",
        "|cff9966ffSpellTuner:|r Trecoda\tPALADIN\tDAMAGER\tassigned\tplayer",
        "|cff9966ffSpellTuner:|r # recording 1\t1757000000\tBlood Furnace\t26.5\tpool 7009\t6 casts\t2199 mana\tforeign 69%\t\t\t1 auras\t",
        "|cff9966ffSpellTuner:|r # roster",
        "|cff9966ffSpellTuner:|r idx\tname\tclass\trole\troleSource\tmaxHP\ttracked",
        "|cff9966ffSpellTuner:|r 1\tDestroyka\tWARRIOR\tTANK\tassigned\t8000\ty",
        "|cff9966ffSpellTuner:|r 2\tAbufaisall\tWARLOCK\tDAMAGER\tassigned\t4200\ty",
        "|cff9966ffSpellTuner:|r 3\tTrecoda\tPALADIN\tDAMAGER\tassigned\t5200\ty",
        "|cff9966ffSpellTuner:|r 4\tPenek\tDRUID\tHEALER\tassigned\t5000\ty",
        "|cff9966ffSpellTuner:|r 5\tAlkandari\tMAGE\tDAMAGER\tassigned\t4000\ty",
        "|cff9966ffSpellTuner:|r # initial\tmana 7009\tbase 69.24\tcasting 28.33\tcaster",
        "|cff9966ffSpellTuner:|r # precasts",
        "|cff9966ffSpellTuner:|r t\tspellID\tcost\ttgt\thpAtCast\tform",
        "|cff9966ffSpellTuner:|r -4.00\t33763\t220\t1\t1.000\t0",
        "|cff9966ffSpellTuner:|r # ev",
        "|cff9966ffSpellTuner:|r t\tkind\ttgt\tamt\tx",
        "|cff9966ffSpellTuner:|r 0.00\t1\t1\t5000\t0",
        "|cff9966ffSpellTuner:|r 1.00\t12\t1\t1\t1000871",
        "|cff9966ffSpellTuner:|r 1.50\t6\t1\t0\t9858",
        "|cff9966ffSpellTuner:|r 3.50\t3\t1\t523\t9858",
        "|cff9966ffSpellTuner:|r 5.00\t3\t1\t337\t26981",
        "|cff9966ffSpellTuner:|r 6.50\t3\t4\t445\t9885",
        "|cff9966ffSpellTuner:|r 9.50\t5\t1\t400\t26981",
        "|cff9966ffSpellTuner:|r 9.50\t1\t5\t3000\t0",
        "|cff9966ffSpellTuner:|r 9.50\t12\t5\t1\t55555",
        "|cff9966ffSpellTuner:|r 9.50\t2\t5\t900\t635",
        "|cff9966ffSpellTuner:|r 11.50\t3\t5\t337\t26981",
        "|cff9966ffSpellTuner:|r 11.50\t14\t1\t0\t12471",
        "|cff9966ffSpellTuner:|r 11.50\t14\t5\t0\t12472",
        "|cff9966ffSpellTuner:|r 14.50\t1\t1\t900\t12471",
        "|cff9966ffSpellTuner:|r 14.50\t3\t5\t337\t26981",
        "|cff9966ffSpellTuner:|r 14.50\t12\t5\t2\t55555",
        "|cff9966ffSpellTuner:|r 14.50\t12\t1\t-1\t1000871",
        "|cff9966ffSpellTuner:|r 16.50\t3\t3\t220\t33763",
        "|cff9966ffSpellTuner:|r 16.50\t9\t2\t0\t0",
        "|cff9966ffSpellTuner:|r # hp",
        "|cff9966ffSpellTuner:|r t\thp1\thp2\thp3\thp4\thp5\tmax1\tmax2\tmax3\tmax4\tmax5",
        "|cff9966ffSpellTuner:|r 0.0\t8000\t4200\t5200\t5000\t4000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 0.5\t3000\t4200\t5200\t5000\t4000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 5.5\t3000\t4200\t5200\t5000\t4000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 10.5\t3000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 15.5\t3000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 20.5\t3000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 25.5\t3000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r # mana",
        "|cff9966ffSpellTuner:|r t\tv\tbase\tcast",
        "|cff9966ffSpellTuner:|r 2.0\t7009\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 4.0\t6486\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 6.0\t6149\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 8.0\t5704\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 10.0\t5704\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 12.0\t5367\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 14.0\t5367\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 16.0\t5030\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 18.0\t4810\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 20.0\t4810\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 22.0\t4810\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 24.0\t4810\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 26.0\t4810\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r # run 1\t1757000000\tVerify test\tBlood Furnace\t90.5\tpool 7009\t2 pulls\t2 recorded\tcombat 85%\t0 drinks\tno rate\t0 deaths\t6357 mana\t\t\tmanual",
        "|cff9966ffSpellTuner:|r # run ev",
        "|cff9966ffSpellTuner:|r t\tkind\tname\ta\tb",
        "|cff9966ffSpellTuner:|r 0.0\t1\tpull\t7009\t1.000",
        "|cff9966ffSpellTuner:|r 40.5\t2\tpull end\t1\t40.500",
        "|cff9966ffSpellTuner:|r 50.5\t1\tpull\t7009\t1.000",
        "|cff9966ffSpellTuner:|r 86.5\t2\tpull end\t2\t36.000",
        "|cff9966ffSpellTuner:|r # run mana",
        "|cff9966ffSpellTuner:|r t\tv",
        "|cff9966ffSpellTuner:|r 0.5\t7009",
        "|cff9966ffSpellTuner:|r 2.5\t7009",
        "|cff9966ffSpellTuner:|r 4.5\t7009",
        "|cff9966ffSpellTuner:|r 6.5\t6672",
        "|cff9966ffSpellTuner:|r 8.5\t6672",
        "|cff9966ffSpellTuner:|r 10.5\t6149",
        "|cff9966ffSpellTuner:|r 12.5\t6149",
        "|cff9966ffSpellTuner:|r 14.5\t5812",
        "|cff9966ffSpellTuner:|r 16.5\t5812",
        "|cff9966ffSpellTuner:|r 18.5\t5289",
        "|cff9966ffSpellTuner:|r 20.5\t5289",
        "|cff9966ffSpellTuner:|r 22.5\t5289",
        "|cff9966ffSpellTuner:|r 24.5\t4952",
        "|cff9966ffSpellTuner:|r 26.5\t4952",
        "|cff9966ffSpellTuner:|r 28.5\t4429",
        "|cff9966ffSpellTuner:|r 30.5\t4429",
        "|cff9966ffSpellTuner:|r 32.5\t4092",
        "|cff9966ffSpellTuner:|r 34.5\t4092",
        "|cff9966ffSpellTuner:|r 36.5\t3569",
        "|cff9966ffSpellTuner:|r 38.5\t3569",
        "|cff9966ffSpellTuner:|r 40.5\t3569",
        "|cff9966ffSpellTuner:|r 42.5\t3569",
        "|cff9966ffSpellTuner:|r 44.5\t3569",
        "|cff9966ffSpellTuner:|r 46.5\t3569",
        "|cff9966ffSpellTuner:|r 48.5\t3569",
        "|cff9966ffSpellTuner:|r 50.5\t3569",
        "|cff9966ffSpellTuner:|r 52.5\t7009",
        "|cff9966ffSpellTuner:|r 54.5\t7009",
        "|cff9966ffSpellTuner:|r 56.5\t6672",
        "|cff9966ffSpellTuner:|r 58.5\t6672",
        "|cff9966ffSpellTuner:|r 60.5\t6149",
        "|cff9966ffSpellTuner:|r 62.5\t6149",
        "|cff9966ffSpellTuner:|r 64.5\t5812",
        "|cff9966ffSpellTuner:|r 66.5\t5812",
        "|cff9966ffSpellTuner:|r 68.5\t5812",
        "|cff9966ffSpellTuner:|r 70.5\t5289",
        "|cff9966ffSpellTuner:|r 72.5\t5289",
        "|cff9966ffSpellTuner:|r 74.5\t4952",
        "|cff9966ffSpellTuner:|r 76.5\t4952",
        "|cff9966ffSpellTuner:|r 78.5\t4429",
        "|cff9966ffSpellTuner:|r 80.5\t4429",
        "|cff9966ffSpellTuner:|r 82.5\t4092",
        "|cff9966ffSpellTuner:|r 84.5\t4092",
        "|cff9966ffSpellTuner:|r 86.5\t4092",
        "|cff9966ffSpellTuner:|r 88.5\t4092",
        "|cff9966ffSpellTuner:|r 90.5\t4092",
        "|cff9966ffSpellTuner:|r # recording 1\t1757000000\tBlood Furnace\t40.5\tpool 7009\t8 casts\t3440 mana\tforeign 0%\t\t\t0 auras\trun 1757000000 pull 1",
        "|cff9966ffSpellTuner:|r # roster",
        "|cff9966ffSpellTuner:|r idx\tname\tclass\trole\troleSource\tmaxHP\ttracked",
        "|cff9966ffSpellTuner:|r 1\tDestroyka\tWARRIOR\tTANK\tassigned\t8000\ty",
        "|cff9966ffSpellTuner:|r 2\tAbufaisall\tWARLOCK\tDAMAGER\tassigned\t4200\ty",
        "|cff9966ffSpellTuner:|r 3\tTrecoda\tPALADIN\tDAMAGER\tassigned\t5200\ty",
        "|cff9966ffSpellTuner:|r 4\tPenek\tDRUID\tHEALER\tassigned\t5000\ty",
        "|cff9966ffSpellTuner:|r 5\tAlkandari\tMAGE\tDAMAGER\tassigned\t4000\ty",
        "|cff9966ffSpellTuner:|r # initial\tmana 7009\tbase 69.24\tcasting 28.33\tcaster",
        "|cff9966ffSpellTuner:|r # precasts",
        "|cff9966ffSpellTuner:|r t\tspellID\tcost\ttgt\thpAtCast\tform",
        "|cff9966ffSpellTuner:|r -33.00\t9858\t523\t1\t0.375\t0",
        "|cff9966ffSpellTuner:|r -31.50\t26981\t337\t1\t0.375\t0",
        "|cff9966ffSpellTuner:|r -30.00\t9885\t445\t4\t1.000\t0",
        "|cff9966ffSpellTuner:|r -25.00\t26981\t337\t5\t0.250\t0",
        "|cff9966ffSpellTuner:|r -22.00\t26981\t337\t5\t0.250\t0",
        "|cff9966ffSpellTuner:|r -20.00\t33763\t220\t3\t1.000\t0",
        "|cff9966ffSpellTuner:|r # ev",
        "|cff9966ffSpellTuner:|r t\tkind\ttgt\tamt\tx",
        "|cff9966ffSpellTuner:|r 0.00\t1\t1\t1500\t0",
        "|cff9966ffSpellTuner:|r 4.50\t3\t1\t337\t26981",
        "|cff9966ffSpellTuner:|r 9.00\t3\t1\t523\t9858",
        "|cff9966ffSpellTuner:|r 13.50\t3\t1\t337\t26981",
        "|cff9966ffSpellTuner:|r 18.00\t3\t1\t523\t9858",
        "|cff9966ffSpellTuner:|r 22.50\t3\t1\t337\t26981",
        "|cff9966ffSpellTuner:|r 27.00\t3\t1\t523\t9858",
        "|cff9966ffSpellTuner:|r 31.50\t3\t1\t337\t26981",
        "|cff9966ffSpellTuner:|r 36.00\t3\t1\t523\t9858",
        "|cff9966ffSpellTuner:|r # hp",
        "|cff9966ffSpellTuner:|r t\thp1\thp2\thp3\thp4\thp5\tmax1\tmax2\tmax3\tmax4\tmax5",
        "|cff9966ffSpellTuner:|r 0.0\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 0.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 5.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 10.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 15.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 20.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 25.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 30.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 35.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 40.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r # mana",
        "|cff9966ffSpellTuner:|r t\tv\tbase\tcast",
        "|cff9966ffSpellTuner:|r 2.0\t7009\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 4.0\t7009\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 6.0\t6672\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 8.0\t6672\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 10.0\t6149\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 12.0\t6149\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 14.0\t5812\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 16.0\t5812\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 18.0\t5812\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 20.0\t5289\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 22.0\t5289\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 24.0\t4952\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 26.0\t4952\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 28.0\t4429\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 30.0\t4429\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 32.0\t4092\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 34.0\t4092\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 36.0\t4092\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 38.0\t3569\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 40.0\t3569\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r # recording 2\t1757000000\tBlood Furnace\t36.0\tpool 7009\t7 casts\t2917 mana\tforeign 0%\t\t\t0 auras\trun 1757000000 pull 2",
        "|cff9966ffSpellTuner:|r # roster",
        "|cff9966ffSpellTuner:|r idx\tname\tclass\trole\troleSource\tmaxHP\ttracked",
        "|cff9966ffSpellTuner:|r 1\tDestroyka\tWARRIOR\tTANK\tassigned\t8000\ty",
        "|cff9966ffSpellTuner:|r 2\tAbufaisall\tWARLOCK\tDAMAGER\tassigned\t4200\ty",
        "|cff9966ffSpellTuner:|r 3\tTrecoda\tPALADIN\tDAMAGER\tassigned\t5200\ty",
        "|cff9966ffSpellTuner:|r 4\tPenek\tDRUID\tHEALER\tassigned\t5000\ty",
        "|cff9966ffSpellTuner:|r 5\tAlkandari\tMAGE\tDAMAGER\tassigned\t4000\ty",
        "|cff9966ffSpellTuner:|r # initial\tmana 7009\tbase 69.24\tcasting 28.33\tcaster",
        "|cff9966ffSpellTuner:|r # precasts",
        "|cff9966ffSpellTuner:|r t\tspellID\tcost\ttgt\thpAtCast\tform",
        "|cff9966ffSpellTuner:|r -32.50\t9858\t523\t1\t0.625\t0",
        "|cff9966ffSpellTuner:|r -28.00\t26981\t337\t1\t0.625\t0",
        "|cff9966ffSpellTuner:|r -23.50\t9858\t523\t1\t0.625\t0",
        "|cff9966ffSpellTuner:|r -19.00\t26981\t337\t1\t0.625\t0",
        "|cff9966ffSpellTuner:|r -14.50\t9858\t523\t1\t0.625\t0",
        "|cff9966ffSpellTuner:|r # ev",
        "|cff9966ffSpellTuner:|r t\tkind\ttgt\tamt\tx",
        "|cff9966ffSpellTuner:|r 0.00\t1\t1\t1500\t0",
        "|cff9966ffSpellTuner:|r 4.50\t3\t1\t337\t26981",
        "|cff9966ffSpellTuner:|r 9.00\t3\t1\t523\t9858",
        "|cff9966ffSpellTuner:|r 13.50\t3\t1\t337\t26981",
        "|cff9966ffSpellTuner:|r 18.00\t3\t1\t523\t9858",
        "|cff9966ffSpellTuner:|r 22.50\t3\t1\t337\t26981",
        "|cff9966ffSpellTuner:|r 27.00\t3\t1\t523\t9858",
        "|cff9966ffSpellTuner:|r 31.50\t3\t1\t337\t26981",
        "|cff9966ffSpellTuner:|r # hp",
        "|cff9966ffSpellTuner:|r t\thp1\thp2\thp3\thp4\thp5\tmax1\tmax2\tmax3\tmax4\tmax5",
        "|cff9966ffSpellTuner:|r 0.0\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 0.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 5.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 10.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 15.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 20.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 25.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 30.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r 35.5\t5000\t4200\t5200\t5000\t1000\t8000\t4200\t5200\t5000\t4000",
        "|cff9966ffSpellTuner:|r # mana",
        "|cff9966ffSpellTuner:|r t\tv\tbase\tcast",
        "|cff9966ffSpellTuner:|r 2.0\t7009\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 4.0\t7009\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 6.0\t6672\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 8.0\t6672\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 10.0\t6149\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 12.0\t6149\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 14.0\t5812\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 16.0\t5812\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 18.0\t5812\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 20.0\t5289\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 22.0\t5289\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 24.0\t4952\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 26.0\t4952\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 28.0\t4429\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 30.0\t4429\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 32.0\t4092\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 34.0\t4092\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r 36.0\t4092\t69.24\t28.33",
        "|cff9966ffSpellTuner:|r # calibration",
        "|cff9966ffSpellTuner:|r spellID\tkind\tn\tobs\tpred",
        "|cff9966ffSpellTuner:|r 26981\ttick\t1\t400\t431",
        "|cff9966ffSpellTuner:|r 33763\ttick\t4\t396\t348",
    } },
    { cmd = "calibrate", lines = {
        "|cff9966ffSpellTuner:|r spell                  kind        n  observed     model  ratio  verdict",
        "|cff9966ffSpellTuner:|r Lifebloom r1 R1        tick        4         -         -      -  too few",
        "|cff9966ffSpellTuner:|r Rejuvenation r12 R12   tick        1         -         -      -  too few",
    } },
    { cmd = "fsrtest", lines = {
        "|cff9966ffSpellTuner:|r fsrtest: logging mana changes for 15s - cast one spell now.",
        "|cff9966ffSpellTuner:|r   t+ 1.00s  -337  (-> 4663)",
        "|cff9966ffSpellTuner:|r   t+ 3.00s  +11  (-> 4674)",
        "|cff9966ffSpellTuner:|r   t+ 5.00s  +11  (-> 4685)",
        "|cff9966ffSpellTuner:|r   t+ 7.00s  +60  (-> 4745)",
        "|cff9966ffSpellTuner:|r   t+ 9.00s  +60  (-> 4805)",
        "|cff9966ffSpellTuner:|r fsrtest: done.",
    } },
    { cmd = "spamtest", lines = {
        "|cff9966ffSpellTuner:|r spamtest: armed at 2000 mana (casting regen 28.33/s). Chain-cast ONE spell now until OOM; the dashboard's To OOM column for it should match.",
        "|cff9966ffSpellTuner:|r spamtest: counting Rejuvenation r12 (live cost 337, 1.5s interval) - keep casting until OOM.",
        "|cff9966ffSpellTuner:|r spamtest (OOM): 4 casts of Rejuvenation r12 (26981) in 6.0s (2.00s apart) - 1871 mana spent (467.8 per cast, live cost 337), 80 regained; mana 2000 -> 209.",
        "|cff9966ffSpellTuner:|r prediction from 2000 mana: 6 casts (live cost 337, 1.5s interval, casting regen 28.33/s); with the MEASURED drop and regen it would be 4. Observed regen during the spam: 13.33/s.",
        "|cff9966ffSpellTuner:|r |cffffaa33NOTE|r the real drop per cast (467.8) differs from the live cost (337) - that is the column's error source.",
        "|cff9966ffSpellTuner:|r |cffffaa33NOTE|r 1 cast(s) of other spells were mixed in and counted in the mana spent.",
    } },
    { cmd = "simrun", lines = {
        "|cff9966ffSpellTuner:|r simrun: 12 test(s), all ok",
        "|cff9966ffSpellTuner:|r   1 rejuv total heal           ok - sim 1725.5 vs row 1725.5",
        "|cff9966ffSpellTuner:|r   1 rejuv mana                 ok - spent 337 vs cost 337",
        "|cff9966ffSpellTuner:|r   2 chain casts to OOM         ok - sim 16 vs closed form 16",
        "|cff9966ffSpellTuner:|r   3 refresh loses ticks        ok - 6 ticks, expected 6",
        "|cff9966ffSpellTuner:|r   4 lifebloom blooms once      ok - 1 bloom(s)",
        "|cff9966ffSpellTuner:|r   4c a refresh does not delay the next tick ok - 11 ticks over 11.5s of 1s-period Lifebloom, expected 11",
        "|cff9966ffSpellTuner:|r   4b the bloom is one application's, not the stack's ok - a 3-stack Lifebloom bloomed for 863; one application is 863, the whole stack would be 2590",
        "|cff9966ffSpellTuner:|r   5 swiftmend eats regrowth    ok - 1360 vs regrowth 1360 / rejuv 1725",
        "|cff9966ffSpellTuner:|r   6 no heals on a corpse       ok - healed 0, deaths 1",
        "|cff9966ffSpellTuner:|r   7 5SR rate switch            ok - 39713/39913 vs 39713/39913",
        "|cff9966ffSpellTuner:|r   8 gcd 1.5s                   ok - 1.4s -> 1, 1.6s -> 2",
        "|cff9966ffSpellTuner:|r   9 run cost is flat           ok - 3.51 KB/run with 1500 events, 3.51 KB/run with none",
    } },
    { cmd = "simreplay fixture", lines = {
        "|cff9966ffSpellTuner:|r fixture BF-1 hard pull: 19 casts, 40.3s, pool 7009",
        "|cff9966ffSpellTuner:|r   spend    sim 6169 vs recorded 6169  (exact)",
        "|cff9966ffSpellTuner:|r   modelled mean 6.3%  max 12.1% at 35.0s   (GetManaRegen only)",
        "|cff9966ffSpellTuner:|r   measured mean 1.3%  max 2.8% at 23.0s   (+ 23.1 mana/s energize) -> PASS",
    } },
    { cmd = "simreplay 1", lines = {
        "|cff9966ffSpellTuner:|r recording 1: Blood Furnace, 26s, 6 casts, 2199 mana",
        "|cff9966ffSpellTuner:|r   verdict: does NOT replay - nothing will be suggested from this fight",
        "|cff9966ffSpellTuner:|r   mana mean          FAIL mean off by 4.6% of pool (limit 2%)",
        "|cff9966ffSpellTuner:|r   mana max           FAIL worst sample off by 11.7% of pool (limit 5%)",
        "|cff9966ffSpellTuner:|r   health curves      FAIL no target reproduced within 5% mean / 15% worst",
        "|cff9966ffSpellTuner:|r   no tracked death   FAIL 1 death(s): damage after one is truncated in the log",
        "|cff9966ffSpellTuner:|r   foreign healing    FAIL 69% of healing on your group was somebody else's (limit 25%)",
        "|cff9966ffSpellTuner:|r   model calibrated   ok   not yet calibrated: Rejuvenation r12, Lifebloom r1, Regrowth r9",
        "|cff9966ffSpellTuner:|r   spend coverage     ok   100% of the mana is accounted for (80% healing, 20% replayed as cast)",
        "|cff9966ffSpellTuner:|r   excluded: Destroyka - mean 36% / worst 62% of max health",
        "|cff9966ffSpellTuner:|r   excluded: Abufaisall - took no damage",
        "|cff9966ffSpellTuner:|r   excluded: Trecoda - took no damage",
        "|cff9966ffSpellTuner:|r   excluded: Penek - took no damage",
        "|cff9966ffSpellTuner:|r   excluded: Alkandari - mean 25% / worst 66% of max health",
        "|cff9966ffSpellTuner:|r   why mana mean is 0.02: judge; server regen ticks quantise samples by ~2% of pool",
        "|cff9966ffSpellTuner:|r   why mana max is 0.05: judge; same quantisation, worst single sample",
        "|cff9966ffSpellTuner:|r   why health curves is 0.05: B; health is reconstructed through pets, absorbs and range",
        "|cff9966ffSpellTuner:|r   why no tracked death is set where it is: post-death damage truncation",
        "|cff9966ffSpellTuner:|r   why foreign healing is 0.25: A's number; BF-1 measured 0%; a prior, not a measurement",
    } },
    { cmd = "coach 1", lines = {
        "|cff9966ffSpellTuner:|r coach: this fight does not replay, so there is nothing to suggest.",
        "|cff9966ffSpellTuner:|r   mana mean: mean off by 4.6% of pool (limit 2%)",
        "|cff9966ffSpellTuner:|r   mana max: worst sample off by 11.7% of pool (limit 5%)",
        "|cff9966ffSpellTuner:|r   health curves: no target reproduced within 5% mean / 15% worst",
        "|cff9966ffSpellTuner:|r   no tracked death: 1 death(s): damage after one is truncated in the log",
        "|cff9966ffSpellTuner:|r   foreign healing: 69% of healing on your group was somebody else's (limit 25%)",
        "|cff9966ffSpellTuner:|r   /md simreplay for the full report; /md coach 1 force to see a card anyway.",
    } },
    { cmd = "coach 1 force", lines = {
        "|cff9966ffSpellTuner:|r coach: searching (this runs across frames; /md coach cancel stops it)...",
        "|cff9966ffSpellTuner:|r Blood Furnace, 15:33 (0:26, 5 targets)   used: you 1.3k   best 1.6k   diff 250",
        "|cff9966ffSpellTuner:|r   you had 2.3k headroom - nothing here needed to change",
        "|cff9966ffSpellTuner:|r   Bind: Lifebloom R1, Rejuvenation R12, Regrowth R9, Healing Touch R12, Swiftmend R1",
        "|cff9966ffSpellTuner:|r   1. Anyone under 30% with a HoT: Swiftmend",
        "|cff9966ffSpellTuner:|r   2. Anyone under 55%: Regrowth R9",
        "|cff9966ffSpellTuner:|r   3. Keep Lifebloom x1 rolling on the tank",
        "|cff9966ffSpellTuner:|r   4. Anyone under 60%: the HoT whose whole heal fits the deficit (Lifebloom R1 or Rejuvenation R12)",
        "|cff9966ffSpellTuner:|r   5. Otherwise wait - 53% of the fight, longest gap 4s",
        "|cff9966ffSpellTuner:|r   you             1.3k used (2.2k spent)   lowest  25%   overheal 16%",
        "|cff9966ffSpellTuner:|r   max rank        2.1k used (2.8k spent)   lowest  25%",
        "|cff9966ffSpellTuner:|r   HoTs only       1.8k used (2.7k spent)   lowest  25%",
        "|cff9966ffSpellTuner:|r   your binds      2.1k used (2.8k spent)   lowest  25%",
        "|cff9966ffSpellTuner:|r   best (search)    1.6k used (2.4k spent)   lowest  25%",
        "|cff9966ffSpellTuner:|r   best            1.6k used (2.4k spent)   lowest  25%   held on 0 of 0",
        "|cff9966ffSpellTuner:|r   strategies (one search, four ways of reading it)",
        "|cff9966ffSpellTuner:|r     Safest = Highest health              1.9k mana   floor  25%    2.2s in danger   ends whole",
        "|cff9966ffSpellTuner:|r     Least mana = Most mana left          1.6k mana   floor  25%    2.2s in danger   ends whole",
        "|cff9966ffSpellTuner:|r     |cff888888/md coach 1 safe / health / cheap / regen plays that one in the replay|r",
        "|cff9966ffSpellTuner:|r   control, buffs and shifts: 1 for 445 mana + 61 regen = 506, kept as they were in both columns",
        "|cff9966ffSpellTuner:|r   danger line: 75% of health on Alkandari - the biggest hit they took. Seconds below it are",
        "|cff9966ffSpellTuner:|r   what a plan is scored on first, ahead of mana.",
        "|cff9966ffSpellTuner:|r   early        1 casts 337",
        "|cff9966ffSpellTuner:|r   spell        2 casts 674",
        "|cff9966ffSpellTuner:|r   idle         1 moment(s) the plan would have cast and you did not",
        "|cff9966ffSpellTuner:|r   utility 445  shifts 0  (outside the healing denominator)",
        "|cff9966ffSpellTuner:|r   why, at 5s - the first cast the plan would not have made:",
        "|cff9966ffSpellTuner:|r     you    Rejuvenation R12 -> Destroyka",
        "|cff9966ffSpellTuner:|r            |cff888888spell: 3.3k missing: the plan wanted Lifebloom on them at that moment|r",
        "|cff9966ffSpellTuner:|r     plan   Lifebloom R1 -> Destroyka",
        "|cff9966ffSpellTuner:|r            |cff888888building the Lifebloom stack: 0 of 1|r",
        "|cff9966ffSpellTuner:|r   caveat: EV crit; other healers as recorded; threat and kill speed not modelled; gates failed: mana mean, mana max, health curves, no tracked death, foreign healing; late and idle come from running the plan alone, the rest from lockstep",
        "|cff9966ffSpellTuner:|r   search: 44 plans evaluated",
    } },
    { cmd = "coachrun 1", lines = {
        "|cff9966ffSpellTuner:|r coachrun: Verify test - 2 pull(s) through the engine, this may take a moment.",
        "|cff9966ffSpellTuner:|r Run: Verify test -- 2 pull(s), 1:30 (combat 85%)",
        "|cff9966ffSpellTuner:|r   you       no drink               never forced       2.0k used   lowest 44% (pull 1)",
        "|cff9966ffSpellTuner:|r   best      no drink               never forced          0 used   lowest 44% (pull 1)",
        "|cff9966ffSpellTuner:|r   the plan: Swiftmend <30%, direct <45%, HoT <80%, roll 0 stack(s)",
        "|cff9966ffSpellTuner:|r   binds: Lifebloom R1, Rejuvenation R12, Regrowth R9, Healing Touch R12, Swiftmend R1",
        "|cff9966ffSpellTuner:|r   drink policy: under 60%, up to 95%   (rate unknown - no drink in the run and none observed this session)",
        "|cff9966ffSpellTuner:|r   where it differs: pull 1 saves 2.4k, pull 2 saves 2.0k (Play one to see it: /md replay <run>:<pull>)",
        "|cff9966ffSpellTuner:|r   pulls that do not replay: 2 of 2 (mana mean 2). Their mana still counts -- that is what a run is",
        "|cff9966ffSpellTuner:|r   scored on -- but their health curves are the engine's reconstruction, not the log's.",
        "|cff9966ffSpellTuner:|r   caveat: EV crit; gap lengths, damage and other healers as recorded; drink rate unknown - no drink in the run and none observed this session.",
        "|cff9966ffSpellTuner:|r   searched 57 plan/policy combination(s).",
    } },
}

Compare(GOLDEN)
PipeZoneCheck()
Footer()
