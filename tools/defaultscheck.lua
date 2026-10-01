-- tools/run.sh [--flavour tbc|forever] tools/defaultscheck.lua
--
-- T64 (P20, review A3): the engine's settings are declared once, by the file
-- that owns the rule. Engine/SimModel.lua registers every sim* / replay* key
-- it, the planner and the replay window read, and the five v2 gate
-- thresholds; Modules/SpellTuner_Replay/Gates_Forever.lua registers its two.
-- Core_TBC.lua's DEFAULTS no longer carries them and Core_Forever.lua's never
-- did. What this suite holds, under both flavours:
--
--   1. every registered default equals the literal it replaced (the values
--      were Core_TBC.lua's DEFAULTS, Commands_Forever.lua's REPLAY_DEFAULTS
--      and the inline `or 0.85` fallbacks -- the table OLD below, copied from
--      the parent commit 3261856), in MD.DEFAULTS, in a fresh MD.db and
--      through MD:Setting with the key absent from the db;
--   2. a gate keeps its setting name and provenance and its `default` is read
--      from the registry, not kept as a second copy;
--   3. each key is declared in exactly one file on the flavour's TOCs -- its
--      owner; since wave 8's merge Commands_Forever.lua (whose REPLAY_DEFAULTS
--      once repeated them) declares none of them;
--   4. every setting a file on the flavour's TOCs reads -- MD.db.<key>,
--      MD.db["<key>"], MD:Setting("<key>"), a gate's setting name -- found by
--      scanning the sources, has a default once every module has loaded (the
--      few that have none by design are listed in NO_DEFAULT with the reason);
--   5. TBC: on a fresh database the Options sliders show 85 and 30, and still
--      do with the two keys absent from the db (they read MD:Setting).
--   T80 (C1): TBC: every db.ui key (fontOffset, scale, combat, escStack, win)
--      has a default, declared by the theme, the ESC stack and the manager.
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB
local T = dofile(here .. "/lib/t.lua")
local check = T.check
local flavour = S.flavour
local root = S.root or "."

--------------------------------------------------------------------------------
-- The literals the registry replaced (parent commit 3261856).
--------------------------------------------------------------------------------
local OLD = {
    simFullHp = 0.85, simFloor = 0.30, simDangerHits = 1, simReaction = 0.5,
    simMinActivity = 0, simAllowRebinds = false, simBigHit = 0.15,
    replaySpeed = 1, replayTicks = true, replayNextPull = true, replayAutoCoach = true,
    simGateManaMean = 0.02, simGateManaMax = 0.05, simGateHpMean = 0.05,
    simGateHpMax = 0.15, simForeignShare = 0.25,
}
local FOREVER_ONLY = { simGateMeter = 0.10, simGateAttrib = 0.10 }
if flavour == "forever" then
    for k, v in pairs(FOREVER_ONLY) do OLD[k] = v end
end
local SIMMODEL = "Engine/SimModel.lua"
local GATES_FOREVER = "Modules/SpellTuner_Replay/Gates_Forever.lua"
local REPLAY_DEFAULTS_FILE = "Modules/SpellTuner_Replay/Commands_Forever.lua"
local OWNER = setmetatable({ simGateMeter = GATES_FOREVER, simGateAttrib = GATES_FOREVER },
    { __index = function() return SIMMODEL end })

local GATE_OLD = { manaMean = 0.02, manaMax = 0.05, hpMean = 0.05, hpMax = 0.15, foreign = 0.25 }
local GATE_SETTING = { manaMean = "simGateManaMean", manaMax = "simGateManaMax",
    hpMean = "simGateHpMean", hpMax = "simGateHpMax", foreign = "simForeignShare" }
if flavour == "forever" then
    GATE_OLD.meterOwn, GATE_SETTING.meterOwn = 0.10, "simGateMeter"
    GATE_OLD.attributed, GATE_SETTING.attributed = 0.10, "simGateAttrib"
end

-- Settings a file reads that have no default by design. Each one says why;
-- anything else read without a default fails section 4.
local NO_DEFAULT = {
    replayPos = "the replay window's pre-T31 position, adopted once by the window manager and removed",
    healAmountGross = "latched from the combat log; nil means not latched yet",
    simUtilityPerFight = "derived from the fight summaries; nil until five exist",
    uiPath = "the navigation's remembered path; nil opens on the first group",
    modules = "the module switches: Core_Forever.lua's DEFAULTS carries them; TBC declares no module "
        .. "and Core.lua's registry reads them behind a guard",
}

local function Sorted(set)
    local list = {}
    for k in pairs(set) do list[#list + 1] = k end
    table.sort(list)
    return list
end

--------------------------------------------------------------------------------
-- Every file on the flavour's TOCs (the files the harness skipped included),
-- then everything loaded: TBC's UI/ files (not Integrations/, which needs
-- ElvUI), Forever's three modules.
--------------------------------------------------------------------------------
local function Exists(rel)
    local f = io.open(root .. "/" .. rel, "r")
    if f then f:close() return true end
    return false
end

local tocFiles = {}
if flavour == "tbc" then
    for _, rel in ipairs(S.TocFiles("SpellTuner_TBC.toc")) do tocFiles[#tocFiles + 1] = rel end
else
    for _, rel in ipairs(S.TocFiles("SpellTuner_Mainline.toc")) do tocFiles[#tocFiles + 1] = rel end
    for _, name in ipairs({ "SpellTuner_Recorder", "SpellTuner_Replay", "SpellTuner_Practice" }) do
        local dir = "Modules/" .. name
        for _, rel in ipairs(S.TocFiles(dir .. "/" .. name .. "_Mainline.toc")) do
            -- a module entry is the module's own file, else the repository's
            -- (T13c: release.sh, the stub and apicheck resolve it the same way)
            tocFiles[#tocFiles + 1] = Exists(dir .. "/" .. rel) and (dir .. "/" .. rel) or rel
        end
    end
end

local sliders = {}
if flavour == "tbc" then
    local loaded = {}
    for _, rel in ipairs(S.loadedFiles) do loaded[rel] = true end
    local rest, uiStyle = {}, false
    for _, rel in ipairs(tocFiles) do
        if not loaded[rel] and rel:sub(1, 13) ~= "Integrations/" then rest[#rest + 1] = rel end
    end
    -- UI/Style.lua first, so its slider constructor can be watched
    S.Load({ rest[1] }, "SpellTuner", MD)
    uiStyle = rest[1] == "UI/Style.lua"
    local Create = MD.UI.CreateSlider
    MD.UI.CreateSlider = function(name, ...)
        local s = Create(name, ...)
        sliders[name] = s
        return s
    end
    local others = {}
    for i = 2, #rest do others[#others + 1] = rest[i] end
    local ran, err = pcall(S.Load, others, "SpellTuner", MD)
    check("tbc: every UI/ file on the TOC loads under the stub", ran and uiStyle, err)
else
    local ran, err = pcall(MD.SetModule, MD, "SpellTuner_Practice", true)
    check("forever: the three modules load", ran and MD.SimModel ~= nil and MD.SimModel.GATES.meterOwn ~= nil, err)
end
local SM = MD.SimModel

--------------------------------------------------------------------------------
T.section("1. every registered default equals the literal it replaced")
--------------------------------------------------------------------------------
for _, k in ipairs(Sorted(OLD)) do
    local old = OLD[k]
    local reg = MD.DEFAULTS and MD.DEFAULTS[k]
    local fresh = MD.db[k]
    local saved = MD.db[k]
    MD.db[k] = nil
    local viaSetting = MD:Setting(k)
    MD.db[k] = saved
    check(k .. " = " .. tostring(old) .. " (registered, fresh db, MD:Setting)",
        reg == old and fresh == old and viaSetting == old,
        string.format("registered %s, fresh db %s, MD:Setting with the key absent %s",
            tostring(reg), tostring(fresh), tostring(viaSetting)))
end
do
    -- one owner: a second declaration with another value is refused
    local ran = pcall(MD.RegisterDefaults, MD, { simFullHp = 0.9 })
    check("a second default for simFullHp (0.9) is refused", not ran and MD:Setting("simFullHp") == 0.85)
    local same = pcall(MD.RegisterDefaults, MD, { simFloor = 0.30 })
    check("the same default declared again is accepted", same)
end

--------------------------------------------------------------------------------
T.section("2. the gates read their defaults from the registry")
--------------------------------------------------------------------------------
for _, name in ipairs(Sorted(GATE_OLD)) do
    local g = SM.GATES[name]
    check("gate " .. name .. ": setting " .. GATE_SETTING[name] .. ", default "
            .. tostring(GATE_OLD[name]) .. ", no second copy",
        g ~= nil and g.setting == GATE_SETTING[name] and g.default == GATE_OLD[name]
            and rawget(g, "default") == nil and type(g.why) == "string" and g.why ~= "",
        g and string.format("setting %s, default %s, stored copy %s",
            tostring(g.setting), tostring(g.default), tostring(rawget(g, "default"))) or "no such gate")
end
do
    -- the gate's default follows the registry, not a literal of its own
    local g = SM.GATES.manaMean
    local keep = MD.DEFAULTS.simGateManaMean
    MD.DEFAULTS.simGateManaMean = 0.03
    local followed = g.default == 0.03
    MD.DEFAULTS.simGateManaMean = keep
    check("gate manaMean's default is the registry's value", followed and g.default == keep)
end

--------------------------------------------------------------------------------
T.section("3. each key is declared once, by its owner")
--------------------------------------------------------------------------------
local sources = {}
local function Source(rel)
    if sources[rel] == nil then
        local f = io.open(root .. "/" .. rel, "r")
        local text = f and f:read("*a") or ""
        if f then f:close() end
        sources[rel] = text
    end
    return sources[rel]
end
-- Lines with their comments removed (a "--" inside a string is rare enough
-- in these files not to matter: nothing here reads settings from a string).
local function CodeLines(rel)
    local lines = {}
    for line in (Source(rel) .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = (line:gsub("%-%-.*$", ""))
    end
    return lines
end

local declaredIn = {}   -- key -> { file = true }
local replayDeclared = {}
for _, rel in ipairs(tocFiles) do
    for _, line in ipairs(CodeLines(rel)) do
        for key in (" " .. line):gmatch("[%s{,]([%a_][%w_]*)%s*=[^=]") do
            if OLD[key] ~= nil or FOREVER_ONLY[key] ~= nil then
                if rel == REPLAY_DEFAULTS_FILE then
                    replayDeclared[key] = true
                else
                    declaredIn[key] = declaredIn[key] or {}
                    declaredIn[key][rel] = true
                end
            end
        end
    end
end
for _, k in ipairs(Sorted(OLD)) do
    local files = Sorted(declaredIn[k] or {})
    check(k .. " is declared in " .. OWNER[k] .. " only",
        #files == 1 and files[1] == OWNER[k],
        #files == 0 and "declared nowhere" or ("declared in " .. table.concat(files, ", ")))
end
if flavour == "tbc" then
    check("Core_TBC.lua's DEFAULTS carries none of them", (function()
        for k in pairs(OLD) do if declaredIn[k] and declaredIn[k]["Core_TBC.lua"] then return false end end
        return true
    end)())
else
    -- REPLAY_DEFAULTS is gone (wave 8's merge of P20 and P21): the Replay
    -- module's Commands_Forever.lua declares none of these keys any more --
    -- Engine/SimModel.lua owns them, and a copy left behind would be a second
    -- place for a value to drift
    local n, off = 0, {}
    for _, k in ipairs(Sorted(replayDeclared)) do
        n = n + 1; off[#off + 1] = k
    end
    check("Commands_Forever.lua declares none of the engine's defaults", n == 0,
        n .. " keys" .. (#off > 0 and (": " .. table.concat(off, ", ")) or ""))
end

--------------------------------------------------------------------------------
T.section("4. every setting read has a default after all modules load")
--------------------------------------------------------------------------------
local readIn = {}  -- key -> first file:line
local function Read(key, rel, i)
    if not readIn[key] then readIn[key] = rel .. ":" .. i end
end
for _, rel in ipairs(tocFiles) do
    for i, line in ipairs(CodeLines(rel)) do
        -- MD.db.<key>, except where it is the target of a plain assignment
        local pos = 1
        while true do
            local a, b, key = line:find("MD%.db%.([%a_][%w_]*)", pos)
            if not a then break end
            local after = line:sub(b + 1)
            if not after:match("^%s*=[^=]") and not after:match("^%s*=$") then Read(key, rel, i) end
            pos = b + 1
        end
        for key in line:gmatch('MD%.db%[%s*"([%w_]+)"%s*%]') do Read(key, rel, i) end
        for key in line:gmatch('MD:Setting%(%s*"([%w_]+)"%s*%)') do Read(key, rel, i) end
        for key in line:gmatch('SM%.Gate%(%s*"([%w_]+)"') do Read(key, rel, i) end
        for key in line:gmatch('setting%s*=%s*"([%w_]+)"') do Read(key, rel, i) end
    end
end
local missing, counted = {}, 0
for _, k in ipairs(Sorted(readIn)) do
    counted = counted + 1
    local saved = MD.db[k]
    MD.db[k] = nil
    local d = MD:Setting(k)
    MD.db[k] = saved
    if d == nil and not replayDeclared[k] and not NO_DEFAULT[k] then
        missing[#missing + 1] = k .. " (" .. readIn[k] .. ")"
    end
end
check(string.format("every setting read on the %s TOCs has a default (%d read)", flavour, counted),
    #missing == 0 and counted > 0, table.concat(missing, ", "))
do
    -- the scan sees the registered keys (it would pass vacuously otherwise);
    -- simMinActivity is declared and shown in /md profile but read by no rule today
    local unseen = {}
    for _, k in ipairs(Sorted(OLD)) do
        if not readIn[k] and k ~= "simMinActivity" then unseen[#unseen + 1] = k end
    end
    check("the scan finds a reader for every registered key", #unseen == 0, table.concat(unseen, ", "))
end
do
    -- no inline fallback literal is left where a registered key is read
    local left = {}
    for _, rel in ipairs(tocFiles) do
        for i, line in ipairs(CodeLines(rel)) do
            for key in line:gmatch("MD%.db%.([%a_][%w_]*)[%)%s]*or%s+[%d%.]+") do
                if OLD[key] ~= nil then left[#left + 1] = rel .. ":" .. i .. " " .. key end
            end
        end
    end
    local owned = { [SIMMODEL] = true, ["Engine/SimPlanner.lua"] = true, ["UI/ReplayWindow.lua"] = true,
        ["UI/Options_General.lua"] = true, [GATES_FOREVER] = true }
    local inOwned = {}
    for _, l in ipairs(left) do
        if owned[l:match("^(%S+):")] then inOwned[#inOwned + 1] = l end
    end
    check("no `MD.db.<key> or <literal>` left in the engine, planner, window, gates or options",
        #inOwned == 0, table.concat(inOwned, "; "))
end

--------------------------------------------------------------------------------
-- T80 (C1 of docs/PLAN-refactor-ux.md): the TBC TOC lists the theme and the
-- window manager, and db.ui left Core_Forever.lua's DEFAULTS for the files
-- that read it -- UI/Theme_Flat.lua (fontOffset), UI/EscStack.lua (escStack),
-- UI/Windows.lua (scale, combat, win) -- so TBC has every key of it.
--------------------------------------------------------------------------------
if flavour == "tbc" then
    local u = MD.db.ui
    local d = MD.DEFAULTS and MD.DEFAULTS.ui
    local function has(t)
        return type(t) == "table" and t.fontOffset == 0 and t.scale == 1 and t.combat == "hide"
            and t.escStack == true and type(t.win) == "table"
    end
    local owners = {}
    for _, rel in ipairs(tocFiles) do
        for _, line in ipairs(CodeLines(rel)) do
            if line:find("RegisterDefaults%(%s*{%s*ui%s*=") then owners[#owners + 1] = rel end
        end
    end
    table.sort(owners)
    check("tbc: every db.ui key has a default (fontOffset, scale, combat, escStack, win), declared by "
            .. "the theme, the ESC stack and the manager",
        has(u) and has(d) and table.concat(owners, " ") == "UI/EscStack.lua UI/Theme_Flat.lua UI/Windows.lua",
        string.format("db %s, defaults %s, declared in %s", tostring(has(u)), tostring(has(d)),
            table.concat(owners, ", ")))
end

--------------------------------------------------------------------------------
T.section("5. the Options sliders on a fresh database (TBC)")
--------------------------------------------------------------------------------
if flavour == "tbc" then
    -- the pane is built on its first showing, so the sliders are looked up after
    local function Show()
        MD:Fire("ShowOptionsTab", "general")
        local full, floor = sliders["Full health is above (%)"], sliders["Danger line for built fights (%)"]
        return full and full:GetValue(), floor and floor:GetValue()
    end
    local f1, d1 = Show()
    check("fresh db: Full health shows 85, Danger 30", f1 == 85 and d1 == 30,
        tostring(f1) .. ", " .. tostring(d1))
    local sf, sd = MD.db.simFullHp, MD.db.simFloor
    MD.db.simFullHp, MD.db.simFloor = nil, nil
    local f2, d2 = Show()
    check("the two keys absent from the db: still 85 and 30", f2 == 85 and d2 == 30,
        tostring(f2) .. ", " .. tostring(d2))
    MD.db.simFullHp, MD.db.simFloor = 0.9, 0.25
    local f3, d3 = Show()
    check("a stored value wins: 90 and 25", f3 == 90 and d3 == 25, tostring(f3) .. ", " .. tostring(d3))
    MD.db.simFullHp, MD.db.simFloor = sf, sd
else
    check("forever: no Options_General on this TOC (the sliders are TBC's)", (function()
        for _, rel in ipairs(tocFiles) do if rel == "UI/Options_General.lua" then return false end end
        return true
    end)())
end

T.done()
