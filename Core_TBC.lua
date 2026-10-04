-- SpellTuner: mana dynamics, time-to-OOM prediction and healing rank analysis
-- for TBC healers. The TBC addon's own core: defaults, the Simulate table,
-- buffs and Tree of Life, talents, the profile snapshot, gear/talent events,
-- and its slash verbs (on Core.lua's ST:AddCommand since T61). Everything
-- shared with Forever (namespace, event dispatch, the ticker, Print/Alert/
-- Debug, player identity, SavedVariables init, the login sequence, the slash
-- dispatcher and command registry) is in Core.lua; this file hangs off it via
-- CORE_LOGIN/CORE_READY and ST:AddCommand (T1b of docs/ROADMAP-FOREVER.md).
-- This file is on the TBC TOC only, so it keeps its direct client calls.
local ADDON_NAME, ST = ...

local DEFAULTS = {
    pos = { "CENTER", "CENTER", 0, -140 }, -- point, relativePoint, x, y
    locked = true,
    muted = false,
    halfLife = 15,        -- seconds; half-life of the spend-rate EWMA
    drinkReminder = true,
    showRest = true,      -- "rest 2:10" segment: time to full if you stop casting
    widgetTooltip = true, -- hover tooltip on the FLOATING WIDGET only (it needs mouse input on the
                          -- frame, so off also stops it swallowing clicks). The minimap button and the
                          -- ElvUI datatexts are not gated by it and must not be: they are surfaces you
                          -- go to on purpose, and the clock is one you park somewhere and stop looking at
    spellTooltipDamage = true, -- v0.15.3: the same, for Wrath, Starfire, Moonfire, Insect Swarm and Hurricane
    spellTooltip = true,  -- v0.14.9: this rank's tick / HoT total / direct range / bloom on the game's own
                          -- spell tooltip (action bars, spellbook, chat links); Shift adds the derivation
    showCooldown = true,  -- "inn 2:10" segment: the clock if you press your mana cooldown now
    oomConfidence = 0.7,  -- print OOM digits only while sigma/net <= this; above it show the bound.
                          -- Derived from one level-61 dungeon (docs/DESIGN-v0.6.md §3b): re-derive on raid logs.
    treeAura = true,      -- count the Tree of Life aura (+25% Spirit as healing received by the party) in heal values
    naturesGrace = true,  -- average Nature's Grace into the dashboard's cast times
    effectiveMode = false, -- dashboard shows overheal-adjusted heal/HPM/HPS
    calibAlerts = true,   -- chat line when a spell drifts >3% from the model over 30+ events
    -- The engine's, the planner's and the replay window's settings (sim*,
    -- replay*, the gate thresholds) are declared by Engine/SimModel.lua with
    -- ST:RegisterDefaults since T64 (P20, review A3): same values, one place.
    recordFights = true,  -- keep the full event stream of the last 8 interesting pulls so they
                          -- can be replayed (Engine/FightRecorder.lua). Summaries run regardless
    recordThreat = true,  -- record the two things a healer can see coming: aggro on each tracked
                          -- target, and a hostile cast aimed at one (docs/SPEC-v0.12.md). A few
                          -- dozen events a pull; off for anyone who does not want the bytes
    recordRuns = true,    -- allow /st run start: a whole dungeon as one recording, every pull plus
                          -- the gaps (Engine/RunRecorder.lua). Two runs kept, one pinnable
    runMaxMinutes = 90,   -- a recording run stops itself at this age (0 = no ceiling)
    runAutoStart = false, -- RESERVED (docs/SPEC-v0.9.md 1.1): start a run on entering a 5-man.
                          -- Runs are manual; the recorder already takes a reason so this is one
                          -- `if` away when the author asks for it
    simUtilityPerFight = nil, -- derived: median utility mana per fight, applied as a lump in
                              -- synthetic scenarios. nil until 5 summaries exist
    healAmountGross = nil, -- latched from the combat log: does SPELL_HEAL's "amount" include the overheal?
    firstRun = true,
    -- minimap: UI/MinimapButton.lua registers it (T79, P36: one file, both lines)
    debug = {
        enabled = false,  -- ST:Debug() is a no-op unless this is on
        maxLines = 1000,  -- memory ring size (Debug Console "keep lines")
        categories = { regen = true, mana = true, spend = true, tto = true,
                       heal = true, cast = true, calib = true, combat = true, chat = true,
                       sim = true, other = true },
    },
    optionsPos = false,   -- v0.11.2: settings are a group of the one window, which remembers its
                          -- own position. Kept so an old database does not grow a stray key back
    char = {},
}
ST.DEFAULTS = DEFAULTS

-- What-if overrides for the rank dashboard (never saved): heal, crit (%),
-- casting / base (mp5), mana. nil = live. See UI/Dashboard.lua "Simulate".
ST.sim = {}

-- Buff scan by name; tolerates both the classic UnitBuff API and C_UnitAuras.
function ST:HasBuff(matchName)
    if not matchName then return false end
    if UnitBuff then
        for i = 1, 40 do
            local name = UnitBuff("player", i)
            if not name then break end
            if name == matchName then return true end
        end
    elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            if aura.name == matchName then return true end
        end
    end
    return false
end

-- Tree of Life form: the shapeshift form ID when the client exposes it
-- (FrameXML TREE_FORM = 2), the form buff by name as fallback.
-- T52 (P8, review B2; docs/DECISIONS.md "Tree form: the buff scan is a
-- fallback for a missing API only"): GetShapeshiftFormID answering nil is an
-- answer -- caster form -- not a missing API. The buff scan ran on that nil
-- and found ANOTHER resto druid's Tree of Life aura (34123, the same name), so
-- the model, the recorder and the labels thought YOU were in Tree form. It now
-- runs only when the function is absent or raised.
local TREE_OF_LIFE = GetSpellInfo(33891)
local TREE_FORM_ID = _G.TREE_FORM or 2
function ST:InTreeForm()
    -- Druid by design (docs/SPEC-next.md 4.4, T99): Tree of Life is a druid
    -- form, a fact about the class rather than a capability a profile grants,
    -- so this read stays on ST.player and never becomes ST.ClassProfile:Can.
    if not ST.player.isDruid then return false end
    if GetShapeshiftFormID then
        local ok, id = pcall(GetShapeshiftFormID)
        if ok then return id == TREE_FORM_ID end
    end
    return ST:HasBuff(TREE_OF_LIFE)
end

-- Fired (as "FORM_CHANGED", inTree) when the shapeshift form changes.
local lastTree = nil
local function CheckForm()
    if not ST.db then return end
    local inTree = ST:InTreeForm()
    if inTree ~= lastTree then
        lastTree = inTree
        ST:Debug("other", "form: %s", inTree and "Tree of Life" or "caster / other")
        ST:Fire("FORM_CHANGED", inTree)
    end
end
ST:On("UPDATE_SHAPESHIFT_FORM", CheckForm)
ST:On("UPDATE_SHAPESHIFT_FORMS", CheckForm)
ST:RegisterCallback("MD_READY", function() lastTree = ST:InTreeForm() end)

--------------------------------------------------------------------------------
-- Talents: scanned by NAME across all tabs so positional index shifts between
-- client builds can't silently return the wrong talent.
--------------------------------------------------------------------------------
ST.talents = {}

-- Talents the model reads or that the verification output should show.
ST.RELEVANT_TALENTS = {
    "Intensity", "Dreamstate", "Living Spirit", "Lunar Guidance",
    "Moonglow", "Tranquil Spirit", "Gift of Nature", "Improved Rejuvenation",
    "Empowered Rejuvenation", "Empowered Touch", "Improved Regrowth",
    "Naturalist", "Natural Perfection", "Nature's Grace", "Tree of Life",
}

-- T52 (P8, review Q15): the offline tools' seam. ST:SetTalents(tbl) makes the
-- ranks `tbl` -- held, not copied, so a tool that edits it later changes the
-- ranks -- and every scan takes it instead of the client, until
-- ST:SetTalents(nil) hands the scan back to the client. Called before login it
-- is what the login scan finds; after login it rescans at once (firing
-- TALENTS_CHANGED as a scan does). tools/harness.lua uses it instead of
-- replacing ST:TalentRank, so the real TalentRank is what the suites run.
-- Nothing in the game calls it.
local fixedTalents = nil
function ST:SetTalents(tbl)
    if tbl == nil and fixedTalents ~= nil then ST.talents = {} end -- never wipe the tool's table
    fixedTalents = tbl
    if ST.db then ST:ScanTalents() end
end

function ST:ScanTalents()
    if fixedTalents then
        ST.talents = fixedTalents
    else
        wipe(ST.talents)
        if not GetNumTalentTabs then return end
        for tab = 1, GetNumTalentTabs() do
            for i = 1, GetNumTalents(tab) do
                local name, _, _, _, rank = GetTalentInfo(tab, i)
                if name then
                    ST.talents[name] = rank or 0
                end
            end
        end
    end
    ST:Debug("other", "talents scanned: %s", ST:TalentSummary())
    ST:Fire("TALENTS_CHANGED")
end

function ST:TalentRank(name)
    return ST.talents[name] or 0
end

-- "Intensity 3, Moonglow 3, ..." for the relevant talents, or "none relevant".
function ST:TalentSummary()
    local list = {}
    for _, t in ipairs(ST.RELEVANT_TALENTS) do
        local r = ST:TalentRank(t)
        if r > 0 then list[#list + 1] = t .. " " .. r end
    end
    return #list > 0 and table.concat(list, ", ") or "none relevant"
end

--------------------------------------------------------------------------------
-- The profile snapshot (v0.9.0, docs/SPEC-v0.9.md 2.2). Everything
-- Engine/RankMath.lua's Context() reads about this character, written into the
-- SavedVariables so the offline tools can build THIS character's spell kit
-- instead of the harness's stand-in. It is a handful of numbers, rewritten at
-- login, on a talent change and on a gear change; nothing reads it in-game --
-- in the client the live API is always better.
--------------------------------------------------------------------------------
function ST:WriteProfile()
    if not ST.cdb then return end
    local function pcallv(fn, ...)
        if not fn then return nil end
        local ok, v = pcall(fn, ...)
        if ok then return v end
        return nil
    end
    local talents = {}
    for _, name in ipairs(ST.RELEVANT_TALENTS) do talents[name] = ST:TalentRank(name) end
    local _, relicID = nil, nil
    if ST.SpellData and ST.SpellData.Relic then
        local _, id = ST.SpellData:Relic()
        relicID = id
    end
    ST.cdb.profile = {
        v = 1, at = time(), charKey = ST.player.charKey,
        class = ST.player.class, level = UnitLevel("player") or ST.player.level or 0,
        healing = pcallv(GetSpellBonusHealing) or 0,
        crit = pcallv(GetSpellCritChance, 4) or 0,
        spirit = UnitStat("player", 5) or 0,
        intellect = UnitStat("player", 4) or 0,
        manaMax = UnitPowerMax("player", 0) or 0,
        apiBase = ST.Regen and ST.Regen.apiBase or 0,
        apiCasting = ST.Regen and ST.Regen.apiCasting or 0,
        talents = talents,
        relic = relicID,
        form = ST:InTreeForm() and "tree" or "caster",
    }
    ST:Debug("other", "profile written: level %d, +%d healing, %.1f%% crit, %d spirit, %d int, relic %s",
        ST.cdb.profile.level, ST.cdb.profile.healing, ST.cdb.profile.crit,
        ST.cdb.profile.spirit, ST.cdb.profile.intellect, tostring(relicID))
end

-- Seam 1: the kernel's login sequence fires CORE_LOGIN once the profile and
-- SavedVariables exist but before MD_READY -- this is TBC's own talent scan.
ST:RegisterCallback("CORE_LOGIN", function() ST:ScanTalents() end)

-- Seam 2: CORE_READY is "everything the kernel does is done" -- today's tail
-- of the login handler, verbatim: the profile snapshot (once now, once after
-- the client settles), the first-run message.
ST:RegisterCallback("CORE_READY", function()
    -- once now, and again once the client has settled: at PLAYER_LOGIN the
    -- stat APIs can still read zero.
    ST:WriteProfile()
    if C_Timer and C_Timer.After then C_Timer.After(5, function() ST:WriteProfile() end) end

    if ST.db.firstRun then
        ST.db.firstRun = false
        ST:Print("first run - the widget is unlocked for 60s so you can drag it. |cffffff00/st lock|r when done, |cffffff00/st help|r for commands.")
        if ST.ForceWidgetPreview then ST:ForceWidgetPreview(60) end
    end
end)

ST:On("CHARACTER_POINTS_CHANGED", function() ST:ScanTalents(); ST:WriteProfile() end)
ST:On("PLAYER_TALENT_UPDATE", function() ST:ScanTalents(); ST:WriteProfile() end)

-- Gear changes move both the profile and the measured mp5. The profile is
-- rewritten (it is free); the measurement is NOT invalidated -- an old
-- measurement is still a measurement -- but the author is reminded once per
-- session, out of combat, that it predates the gear they are wearing.
local gearReminded = false
ST:On("PLAYER_EQUIPMENT_CHANGED", function()
    if not ST.cdb then return end
    ST:WriteProfile()
    if gearReminded or ST.inCombat then return end -- T58 (P14, A28): the kernel's flag
    local m = ST.cdb.mp5
    if not m or not m.at then return end
    gearReminded = true
    ST:Print(string.format("item mp5 was measured on %s (%d mp5); gear changed since - |cffffff00/st regentest|r " ..
        "solo to re-measure.", date("%d %b", m.at), m.mp5 or 0))
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------
-- T61 (P17, review A1): every TBC verb registered on the kernel's one registry
-- (Core.lua's ST:AddCommand), here where the old ST.COMMANDS list and
-- ST.SlashFallback if-chain were -- no verb moved file; each moves next to its
-- owner when that file is next touched. Registered in the old list's order, so
-- the help and the About tab (ST:Commands()) print what they printed; the
-- verbs the list never had a row for (help, unlock) are hidden, and the second
-- spellings are aliases. tools/slashcheck.lua's golden transcript, captured
-- before the move, holds every verb's output line for line.
ST.COMMAND_USAGE_COLOR = "ffffff00"

ST:AddCommand("", function()
    if ST.ToggleDashboard then ST:ToggleDashboard() end
end, "/st", "toggle the rank dashboard")

ST:AddCommand("options", function()
    if ST.ShowOptionsFrame then ST:ShowOptionsFrame() end
end, "/st options", "open the settings window")
ST:AddAlias("config", "options")
ST:AddAlias("settings", "options")

ST:AddCommand("lock", function()
    ST.db.locked = true
    if ST.UpdateVisibility then ST:UpdateVisibility() end
    ST:Print("widget locked.")
end, "/st lock, unlock", "lock / unlock (drag) the OOM widget")
ST:AddCommand("unlock", function()
    ST.db.locked = false
    if ST.UpdateVisibility then ST:UpdateVisibility() end
    ST:Print("widget unlocked - drag it, then /st lock.")
end, nil, nil, true) -- listed on lock's row

ST:AddCommand("reset", function()
    ST.db.pos = { DEFAULTS.pos[1], DEFAULTS.pos[2], DEFAULTS.pos[3], DEFAULTS.pos[4] }
    if ST.ApplyWidgetPosition then ST:ApplyWidgetPosition() end
    ST:Print("widget position reset.")
end, "/st reset", "reset the widget position")

ST:AddCommand("mute", function()
    ST.db.muted = not ST.db.muted
    ST:Print("alerts " .. (ST.db.muted and "muted." or "unmuted."))
end, "/st mute", "toggle alert messages")

ST:AddCommand("drink", function()
    ST.db.drinkReminder = not ST.db.drinkReminder
    ST:Print("drink reminder " .. (ST.db.drinkReminder and "on." or "off."))
end, "/st drink", "toggle the drink reminder")

ST:AddCommand("rest", function()
    ST.db.showRest = not ST.db.showRest
    ST:Print("rest segment " .. (ST.db.showRest and "on." or "off."))
end, "/st rest", "toggle the 'rest' segment (time to full if you stop casting)")

ST:AddCommand("tooltip", function()
    ST.db.widgetTooltip = (ST.db.widgetTooltip == false)
    if ST.UpdateVisibility then ST:UpdateVisibility() end
    ST:Print(ST.db.widgetTooltip
        and "floating clock: tooltip on - hovering shows the breakdown, left-click opens the dashboard."
        or "floating clock: tooltip off - it takes no mouse input at all now, so it neither pops a tooltip "
           .. "nor swallows clicks in its rectangle, and it is still draggable while unlocked. The minimap "
           .. "button and the ElvUI datatexts keep theirs.")
end, "/st tooltip", "hover tooltip on the FLOATING clock only (off also stops it swallowing clicks)")
ST:AddAlias("tip", "tooltip")

ST:AddCommand("binds", function()
    if ST.ToggleBindings then ST:ToggleBindings() end
end, "/st binds", "what each key and mouse button casts in practice; import from Cell or Clique")
ST:AddAlias("bindings", "binds")

ST:AddCommand("practice", function(arg)
    -- v0.15.0: Simulate -> Practice; "/st practice start" plays the saved setup at once
    if arg == "start" and ST.OpenPractice and ST.Practice then
        ST.cdb.practiceSetup = ST.cdb.practiceSetup or ST.Practice.DefaultSetup("5")
        ST:OpenPractice(ST.Practice.CopySetup(ST.cdb.practiceSetup), ST.cdb.practiceSetup.fixedSeed)
    elseif ST.SelectView then
        if ST.ShowDashboard then ST:ShowDashboard() end
        ST:SelectView("simulate", "practice")
    end
end, "/st practice", "heal a fight you play and get it back as a recording (start: play the saved setup now)")

ST:AddCommand("spelltip", function()
    ST.db.spellTooltip = (ST.db.spellTooltip == false)
    ST:Print(ST.db.spellTooltip
        and "spell tooltips: on - hover a heal on your bars or in the spellbook; hold Shift for the maths."
        or "spell tooltips: off.")
end, "/st spelltip", "heal values on the game's spell tooltips (bars, spellbook); Shift for the maths")

ST:AddCommand("window", function(arg)
    local n = tonumber(arg)
    if n and n >= 5 and n <= 60 then
        ST.db.halfLife = n
        ST:Print("spend half-life set to " .. n .. "s.")
    else
        ST:Print("usage: /st window N (5-60 seconds)")
    end
end, "/st window N", "spend estimator half-life in seconds (5-60, default 15)")

ST:AddCommand("verify", function()
    if ST.RunVerify then ST:RunVerify() end
end, "/st verify", "check static spell data against the live client")

ST:AddCommand("profile", function()
    if ST.RunProfile then ST:RunProfile() end
end, "/st profile", "copyable dump of every model input - use this for bug reports")

ST:AddCommand("export", function()
    if ST.RunExport then ST:RunExport() end
end, "/st export", "fights, overheal and roster as tab-separated text, for analysis")

ST:AddCommand("calibrate", function()
    if ST.RunCalibrate then ST:RunCalibrate() end
end, "/st calibrate", "the model against every heal you landed: ratio per spell and event kind")
ST:AddAlias("calib", "calibrate")

ST:AddCommand("fsrtest", function()
    if ST.RunFSRTest then ST:RunFSRTest() end
end, "/st fsrtest", "log mana ticks for 15s (five-second-rule anchor test)")

ST:AddCommand("regentest", function(arg)
    if ST.RunRegenTest then ST:RunRegenTest(arg ~= "" and arg or nil) end
end, "/st regentest [N or clear]",
"idle regen check: observed mana gain vs GetManaRegen (N s, default 30; clear forgets the measurement)")

ST:AddCommand("spamtest", function()
    if ST.RunSpamTest then ST:RunSpamTest() end
end, "/st spamtest", "arm, then chain-cast one spell to OOM: checks the dashboard's To OOM column")

ST:AddCommand("simrun", function()
    if ST.RunSimRun then ST:RunSimRun() end
end, "/st simrun", "self-tests for the simulation engine (heals, HoT refresh, GCD, 5SR)")

ST:AddCommand("simreplay", function(arg)
    if ST.RunSimReplay then ST:RunSimReplay(arg) end
end, "/st simreplay [n]", "replay recorded fight n (or the BF-1 fixture) and score it against the log")

ST:AddCommand("coach", function(arg)
    if ST.RunCoach then ST:RunCoach(arg) end
end, "/st coach [n]", "search for a better plan on recorded fight n and show the card (cancel stops it)")

ST:AddCommand("sim", function()
    if ST.ToggleSimWindow then ST:ToggleSimWindow() end
end, "/st sim", "simulation window: build a fight and find the cheapest plan that holds it")

ST:AddCommand("replay", function(arg)
    if ST.ToggleReplay then ST:ToggleReplay(arg) end
end, "/st replay [n] [force]",
"play recorded fight n (or run:pull, or 'run N') as unit frames; force: draw the suggested column on a fight that does not replay")

ST:AddCommand("run", function(_, rawArg)
    if ST.RunCommand then ST:RunCommand(rawArg) end
end, "/st run start / stop / status", "record a whole dungeon: every pull and the gaps between them")

ST:AddCommand("coachrun", function(arg)
    if ST.RunCoachRun then ST:RunCoachRun(arg) end
end, "/st coachrun [n]", "coach a recorded RUN: one plan and a drink policy for the whole dungeon")

ST:AddCommand("debug", function()
    if ST.ToggleDebugConsole then ST:ToggleDebugConsole() end
end, "/st debug", "toggle the debug console (enable logging there, Copy to export)")

-- The list itself, not a row of it (an unknown verb prints it too: Core.lua).
ST:AddCommand("help", function() ST:ShowCommands() end, nil, nil, true)
