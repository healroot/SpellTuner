-- SpellTuner: mana dynamics, time-to-OOM prediction and healing rank analysis
-- for TBC healers. The TBC addon's own core: defaults, the Simulate table,
-- buffs and Tree of Life, talents, the profile snapshot, gear/talent events,
-- and its slash verbs (on Core.lua's MD:AddCommand since T61). Everything
-- shared with Forever (namespace, event dispatch, the ticker, Print/Alert/
-- Debug, player identity, SavedVariables init, the login sequence, the slash
-- dispatcher and command registry) is in Core.lua; this file hangs off it via
-- CORE_LOGIN/CORE_READY and MD:AddCommand (T1b of docs/ROADMAP-FOREVER.md).
-- This file is on the TBC TOC only, so it keeps its direct client calls.
local ADDON_NAME, MD = ...

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
    simFullHp = 0.85,     -- a target at or above this fraction of health counts as "full" for the
                          -- cast labels and the replay engine (docs/SPEC-v0.7.md §2.2)
    simFloor = 0.30,      -- below this fraction of health a tracked target is "in danger": the
                          -- seconds spent there are what a plan is scored on first. Used for
                          -- SYNTHETIC scenarios only since v0.10.3 -- a recording measures its
                          -- own line (see simDangerHits)
    simDangerHits = 1,    -- "in danger" is this many of the biggest hits the target actually took
                          -- in that fight away from death. 1 = one more hit kills. A flat 30% says
                          -- the same thing about a quest mob hitting for 7% and a boss hitting for
                          -- a third of the tank, which is why it stopped being the line
    simReaction = 0.5,    -- seconds a simulated healer takes to start casting after idling.
                          -- Only after a wait: BF-1's inter-cast gaps (p10/p25 1.50/1.52s) show
                          -- chained casts go out at the GCD with no delay at all
    simMinActivity = 0,   -- minimum fraction of the fight a plan must spend casting (0 = off;
                          -- waiting is a legitimate action for a 5-man healer)
    recordFights = true,  -- keep the full event stream of the last 8 interesting pulls so they
                          -- can be replayed (Engine/FightRecorder.lua). Summaries run regardless
    recordThreat = true,  -- record the two things a healer can see coming: aggro on each tracked
                          -- target, and a hostile cast aimed at one (docs/SPEC-v0.12.md). A few
                          -- dozen events a pull; off for anyone who does not want the bytes
    recordRuns = true,    -- allow /md run start: a whole dungeon as one recording, every pull plus
                          -- the gaps (Engine/RunRecorder.lua). Two runs kept, one pinnable
    runMaxMinutes = 90,   -- a recording run stops itself at this age (0 = no ceiling)
    runAutoStart = false, -- RESERVED (docs/SPEC-v0.9.md 1.1): start a run on entering a 5-man.
                          -- Runs are manual; the recorder already takes a reason so this is one
                          -- `if` away when the author asks for it
    -- Replay validation gates (docs/SPEC-v0.7.md §7). A recording earns the right to be
    -- coached from; each threshold's provenance is printed with its result in Engine/SimModel.lua.
    simGateManaMean = 0.02,   -- mean |delta| on the mana curve, as a fraction of the pool
    simGateManaMax = 0.05,    -- worst single mana sample
    simGateHpMean = 0.05,     -- mean |delta| on one target's health, fraction of its max
    simGateHpMax = 0.15,      -- worst single health snapshot
    simForeignShare = 0.25,   -- above this share of foreign healing, replay is fiction
    simAllowRebinds = false,  -- let the search change which RANKS you bind, not just the thresholds
    replaySpeed = 1,          -- the replay window's last playback speed (1, 2 or 4)
    replayTicks = true,       -- draw the recorder's real HP snapshots over the left bars
    replayNextPull = true,    -- inside a run, playing a pull to the end opens the next one
    replayAutoCoach = true,   -- opening a replay with no plan coaches it (v0.13.9): validate,
                              -- coach and play were three commands to answer one question
    simBigHit = 0.15,         -- a single hit worth this much of a target's max health is a "big hit"
                              -- when a preset is derived from recordings (v0.7.7)
    simUtilityPerFight = nil, -- derived: median utility mana per fight, applied as a lump in
                              -- synthetic scenarios. nil until 5 summaries exist
    healAmountGross = nil, -- latched from the combat log: does SPELL_HEAL's "amount" include the overheal?
    firstRun = true,
    minimap = { hide = false, angle = 220 },
    debug = {
        enabled = false,  -- MD:Debug() is a no-op unless this is on
        maxLines = 1000,  -- memory ring size (Debug Console "keep lines")
        categories = { regen = true, mana = true, spend = true, tto = true,
                       heal = true, cast = true, calib = true, combat = true, chat = true,
                       sim = true, other = true },
    },
    optionsPos = false,   -- v0.11.2: settings are a group of the one window, which remembers its
                          -- own position. Kept so an old database does not grow a stray key back
    char = {},
}
MD.DEFAULTS = DEFAULTS

-- What-if overrides for the rank dashboard (never saved): heal, crit (%),
-- casting / base (mp5), mana. nil = live. See UI/Dashboard.lua "Simulate".
MD.sim = {}

-- Buff scan by name; tolerates both the classic UnitBuff API and C_UnitAuras.
function MD:HasBuff(matchName)
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
function MD:InTreeForm()
    if not MD.player.isDruid then return false end
    if GetShapeshiftFormID then
        local ok, id = pcall(GetShapeshiftFormID)
        if ok then return id == TREE_FORM_ID end
    end
    return MD:HasBuff(TREE_OF_LIFE)
end

-- Fired (as "FORM_CHANGED", inTree) when the shapeshift form changes.
local lastTree = nil
local function CheckForm()
    if not MD.db then return end
    local inTree = MD:InTreeForm()
    if inTree ~= lastTree then
        lastTree = inTree
        MD:Debug("other", "form: %s", inTree and "Tree of Life" or "caster / other")
        MD:Fire("FORM_CHANGED", inTree)
    end
end
MD:On("UPDATE_SHAPESHIFT_FORM", CheckForm)
MD:On("UPDATE_SHAPESHIFT_FORMS", CheckForm)
MD:RegisterCallback("MD_READY", function() lastTree = MD:InTreeForm() end)

--------------------------------------------------------------------------------
-- Talents: scanned by NAME across all tabs so positional index shifts between
-- client builds can't silently return the wrong talent.
--------------------------------------------------------------------------------
MD.talents = {}

-- Talents the model reads or that the verification output should show.
MD.RELEVANT_TALENTS = {
    "Intensity", "Dreamstate", "Living Spirit", "Lunar Guidance",
    "Moonglow", "Tranquil Spirit", "Gift of Nature", "Improved Rejuvenation",
    "Empowered Rejuvenation", "Empowered Touch", "Improved Regrowth",
    "Naturalist", "Natural Perfection", "Nature's Grace", "Tree of Life",
}

-- T52 (P8, review Q15): the offline tools' seam. MD:SetTalents(tbl) makes the
-- ranks `tbl` -- held, not copied, so a tool that edits it later changes the
-- ranks -- and every scan takes it instead of the client, until
-- MD:SetTalents(nil) hands the scan back to the client. Called before login it
-- is what the login scan finds; after login it rescans at once (firing
-- TALENTS_CHANGED as a scan does). tools/harness.lua uses it instead of
-- replacing MD:TalentRank, so the real TalentRank is what the suites run.
-- Nothing in the game calls it.
local fixedTalents = nil
function MD:SetTalents(tbl)
    if tbl == nil and fixedTalents ~= nil then MD.talents = {} end -- never wipe the tool's table
    fixedTalents = tbl
    if MD.db then MD:ScanTalents() end
end

function MD:ScanTalents()
    if fixedTalents then
        MD.talents = fixedTalents
    else
        wipe(MD.talents)
        if not GetNumTalentTabs then return end
        for tab = 1, GetNumTalentTabs() do
            for i = 1, GetNumTalents(tab) do
                local name, _, _, _, rank = GetTalentInfo(tab, i)
                if name then
                    MD.talents[name] = rank or 0
                end
            end
        end
    end
    MD:Debug("other", "talents scanned: %s", MD:TalentSummary())
    MD:Fire("TALENTS_CHANGED")
end

function MD:TalentRank(name)
    return MD.talents[name] or 0
end

-- "Intensity 3, Moonglow 3, ..." for the relevant talents, or "none relevant".
function MD:TalentSummary()
    local list = {}
    for _, t in ipairs(MD.RELEVANT_TALENTS) do
        local r = MD:TalentRank(t)
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
function MD:WriteProfile()
    if not MD.cdb then return end
    local function pcallv(fn, ...)
        if not fn then return nil end
        local ok, v = pcall(fn, ...)
        if ok then return v end
        return nil
    end
    local talents = {}
    for _, name in ipairs(MD.RELEVANT_TALENTS) do talents[name] = MD:TalentRank(name) end
    local _, relicID = nil, nil
    if MD.SpellData and MD.SpellData.Relic then
        local _, id = MD.SpellData:Relic()
        relicID = id
    end
    MD.cdb.profile = {
        v = 1, at = time(), charKey = MD.player.charKey,
        class = MD.player.class, level = UnitLevel("player") or MD.player.level or 0,
        healing = pcallv(GetSpellBonusHealing) or 0,
        crit = pcallv(GetSpellCritChance, 4) or 0,
        spirit = UnitStat("player", 5) or 0,
        intellect = UnitStat("player", 4) or 0,
        manaMax = UnitPowerMax("player", 0) or 0,
        apiBase = MD.Regen and MD.Regen.apiBase or 0,
        apiCasting = MD.Regen and MD.Regen.apiCasting or 0,
        talents = talents,
        relic = relicID,
        form = MD:InTreeForm() and "tree" or "caster",
    }
    MD:Debug("other", "profile written: level %d, +%d healing, %.1f%% crit, %d spirit, %d int, relic %s",
        MD.cdb.profile.level, MD.cdb.profile.healing, MD.cdb.profile.crit,
        MD.cdb.profile.spirit, MD.cdb.profile.intellect, tostring(relicID))
end

-- Seam 1: the kernel's login sequence fires CORE_LOGIN once the profile and
-- SavedVariables exist but before MD_READY -- this is TBC's own talent scan.
MD:RegisterCallback("CORE_LOGIN", function() MD:ScanTalents() end)

-- Seam 2: CORE_READY is "everything the kernel does is done" -- today's tail
-- of the login handler, verbatim: the profile snapshot (once now, once after
-- the client settles), the first-run message.
MD:RegisterCallback("CORE_READY", function()
    -- once now, and again once the client has settled: at PLAYER_LOGIN the
    -- stat APIs can still read zero.
    MD:WriteProfile()
    if C_Timer and C_Timer.After then C_Timer.After(5, function() MD:WriteProfile() end) end

    if MD.db.firstRun then
        MD.db.firstRun = false
        MD:Print("first run - the widget is unlocked for 60s so you can drag it. |cffffff00/md lock|r when done, |cffffff00/md help|r for commands.")
        if MD.ForceWidgetPreview then MD:ForceWidgetPreview(60) end
    end
end)

MD:On("CHARACTER_POINTS_CHANGED", function() MD:ScanTalents(); MD:WriteProfile() end)
MD:On("PLAYER_TALENT_UPDATE", function() MD:ScanTalents(); MD:WriteProfile() end)

-- Gear changes move both the profile and the measured mp5. The profile is
-- rewritten (it is free); the measurement is NOT invalidated -- an old
-- measurement is still a measurement -- but the author is reminded once per
-- session, out of combat, that it predates the gear they are wearing.
local gearReminded = false
MD:On("PLAYER_EQUIPMENT_CHANGED", function()
    if not MD.cdb then return end
    MD:WriteProfile()
    if gearReminded or MD.inCombat then return end -- T58 (P14, A28): the kernel's flag
    local m = MD.cdb.mp5
    if not m or not m.at then return end
    gearReminded = true
    MD:Print(string.format("item mp5 was measured on %s (%d mp5); gear changed since - |cffffff00/md regentest|r " ..
        "solo to re-measure.", date("%d %b", m.at), m.mp5 or 0))
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------
-- T61 (P17, review A1): every TBC verb registered on the kernel's one registry
-- (Core.lua's MD:AddCommand), here where the old MD.COMMANDS list and
-- MD.SlashFallback if-chain were -- no verb moved file; each moves next to its
-- owner when that file is next touched. Registered in the old list's order, so
-- the help and the About tab (MD:Commands()) print what they printed; the
-- verbs the list never had a row for (help, unlock) are hidden, and the second
-- spellings are aliases. tools/slashcheck.lua's golden transcript, captured
-- before the move, holds every verb's output line for line.
MD.COMMAND_USAGE_COLOR = "ffffff00"

MD:AddCommand("", function()
    if MD.ToggleDashboard then MD:ToggleDashboard() end
end, "/st", "toggle the rank dashboard")

MD:AddCommand("options", function()
    if MD.ShowOptionsFrame then MD:ShowOptionsFrame() end
end, "/st options", "open the settings window")
MD:AddAlias("config", "options")
MD:AddAlias("settings", "options")

MD:AddCommand("lock", function()
    MD.db.locked = true
    if MD.UpdateVisibility then MD:UpdateVisibility() end
    MD:Print("widget locked.")
end, "/st lock, unlock", "lock / unlock (drag) the OOM widget")
MD:AddCommand("unlock", function()
    MD.db.locked = false
    if MD.UpdateVisibility then MD:UpdateVisibility() end
    MD:Print("widget unlocked - drag it, then /md lock.")
end, nil, nil, true) -- listed on lock's row

MD:AddCommand("reset", function()
    MD.db.pos = { DEFAULTS.pos[1], DEFAULTS.pos[2], DEFAULTS.pos[3], DEFAULTS.pos[4] }
    if MD.ApplyWidgetPosition then MD:ApplyWidgetPosition() end
    MD:Print("widget position reset.")
end, "/st reset", "reset the widget position")

MD:AddCommand("mute", function()
    MD.db.muted = not MD.db.muted
    MD:Print("alerts " .. (MD.db.muted and "muted." or "unmuted."))
end, "/st mute", "toggle alert messages")

MD:AddCommand("drink", function()
    MD.db.drinkReminder = not MD.db.drinkReminder
    MD:Print("drink reminder " .. (MD.db.drinkReminder and "on." or "off."))
end, "/st drink", "toggle the drink reminder")

MD:AddCommand("rest", function()
    MD.db.showRest = not MD.db.showRest
    MD:Print("rest segment " .. (MD.db.showRest and "on." or "off."))
end, "/st rest", "toggle the 'rest' segment (time to full if you stop casting)")

MD:AddCommand("tooltip", function()
    MD.db.widgetTooltip = (MD.db.widgetTooltip == false)
    if MD.UpdateVisibility then MD:UpdateVisibility() end
    MD:Print(MD.db.widgetTooltip
        and "floating clock: tooltip on - hovering shows the breakdown, left-click opens the dashboard."
        or "floating clock: tooltip off - it takes no mouse input at all now, so it neither pops a tooltip "
           .. "nor swallows clicks in its rectangle, and it is still draggable while unlocked. The minimap "
           .. "button and the ElvUI datatexts keep theirs.")
end, "/st tooltip", "hover tooltip on the FLOATING clock only (off also stops it swallowing clicks)")
MD:AddAlias("tip", "tooltip")

MD:AddCommand("binds", function()
    if MD.ToggleBindings then MD:ToggleBindings() end
end, "/st binds", "what each key and mouse button casts in practice; import from Cell or Clique")
MD:AddAlias("bindings", "binds")

MD:AddCommand("practice", function(arg)
    -- v0.15.0: Simulate -> Practice; "/md practice start" plays the saved setup at once
    if arg == "start" and MD.OpenPractice and MD.Practice then
        MD.cdb.practiceSetup = MD.cdb.practiceSetup or MD.Practice.DefaultSetup("5")
        MD:OpenPractice(MD.Practice.CopySetup(MD.cdb.practiceSetup), MD.cdb.practiceSetup.fixedSeed)
    elseif MD.SelectView then
        if MD.ShowDashboard then MD:ShowDashboard() end
        MD:SelectView("simulate", "practice")
    end
end, "/st practice", "heal a fight you play and get it back as a recording (start: play the saved setup now)")

MD:AddCommand("spelltip", function()
    MD.db.spellTooltip = (MD.db.spellTooltip == false)
    MD:Print(MD.db.spellTooltip
        and "spell tooltips: on - hover a heal on your bars or in the spellbook; hold Shift for the maths."
        or "spell tooltips: off.")
end, "/st spelltip", "heal values on the game's spell tooltips (bars, spellbook); Shift for the maths")

MD:AddCommand("window", function(arg)
    local n = tonumber(arg)
    if n and n >= 5 and n <= 60 then
        MD.db.halfLife = n
        MD:Print("spend half-life set to " .. n .. "s.")
    else
        MD:Print("usage: /md window N (5-60 seconds)")
    end
end, "/st window N", "spend estimator half-life in seconds (5-60, default 15)")

MD:AddCommand("verify", function()
    if MD.RunVerify then MD:RunVerify() end
end, "/st verify", "check static spell data against the live client")

MD:AddCommand("profile", function()
    if MD.RunProfile then MD:RunProfile() end
end, "/st profile", "copyable dump of every model input - use this for bug reports")

MD:AddCommand("export", function()
    if MD.RunExport then MD:RunExport() end
end, "/st export", "fights, overheal and roster as tab-separated text, for analysis")

MD:AddCommand("calibrate", function()
    if MD.RunCalibrate then MD:RunCalibrate() end
end, "/st calibrate", "the model against every heal you landed: ratio per spell and event kind")
MD:AddAlias("calib", "calibrate")

MD:AddCommand("fsrtest", function()
    if MD.RunFSRTest then MD:RunFSRTest() end
end, "/st fsrtest", "log mana ticks for 15s (five-second-rule anchor test)")

MD:AddCommand("regentest", function(arg)
    if MD.RunRegenTest then MD:RunRegenTest(arg ~= "" and arg or nil) end
end, "/st regentest [N or clear]",
"idle regen check: observed mana gain vs GetManaRegen (N s, default 30; clear forgets the measurement)")

MD:AddCommand("spamtest", function()
    if MD.RunSpamTest then MD:RunSpamTest() end
end, "/st spamtest", "arm, then chain-cast one spell to OOM: checks the dashboard's To OOM column")

MD:AddCommand("simrun", function()
    if MD.RunSimRun then MD:RunSimRun() end
end, "/st simrun", "self-tests for the simulation engine (heals, HoT refresh, GCD, 5SR)")

MD:AddCommand("simreplay", function(arg)
    if MD.RunSimReplay then MD:RunSimReplay(arg) end
end, "/st simreplay [n]", "replay recorded fight n (or the BF-1 fixture) and score it against the log")

MD:AddCommand("coach", function(arg)
    if MD.RunCoach then MD:RunCoach(arg) end
end, "/st coach [n]", "search for a better plan on recorded fight n and show the card (cancel stops it)")

MD:AddCommand("sim", function()
    if MD.ToggleSimWindow then MD:ToggleSimWindow() end
end, "/st sim", "simulation window: build a fight and find the cheapest plan that holds it")

MD:AddCommand("replay", function(arg)
    if MD.ToggleReplay then MD:ToggleReplay(arg) end
end, "/st replay [n] [force]",
"play recorded fight n (or run:pull, or 'run N') as unit frames; force: draw the suggested column on a fight that does not replay")

MD:AddCommand("run", function(_, rawArg)
    if MD.RunCommand then MD:RunCommand(rawArg) end
end, "/st run start / stop / status", "record a whole dungeon: every pull and the gaps between them")

MD:AddCommand("coachrun", function(arg)
    if MD.RunCoachRun then MD:RunCoachRun(arg) end
end, "/st coachrun [n]", "coach a recorded RUN: one plan and a drink policy for the whole dungeon")

MD:AddCommand("debug", function()
    if MD.ToggleDebugConsole then MD:ToggleDebugConsole() end
end, "/st debug", "toggle the debug console (enable logging there, Copy to export)")

-- The list itself, not a row of it (an unknown verb prints it too: Core.lua).
MD:AddCommand("help", function() MD:ShowCommands() end, nil, nil, true)
