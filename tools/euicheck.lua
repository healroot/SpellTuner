-- tools/run.sh tools/euicheck.lua [--print]
--
-- T97 (docs/SPEC-next.md 6.2-6.3, section 11 row T97; R-ellesmere.md 4.2):
-- the LibDataBroker surface (Integrations/Surface_LDB.lua) and EllesmereUI's
-- entry points (Integrations/EllesmereUI_Forever.lua) on the Forever line,
-- over tools/stub_hosts.lua's fake EllesmereUI 9.3.4, LibStub and
-- LibDataBroker-1.1. Each block is a fresh session (the harness dofile'd
-- again) with the hosts installed BEFORE the TOC loads, as EllesmereUI's
-- parent loads before SpellTuner ("## OptionalDeps: EllesmereUI").
--
-- R-ellesmere.md 4.2's fourteen checks, then the spec's four:
--    1. absent host: nothing raises, nothing is published, no global written,
--       no dump line -- and the Forever TOCs list both files (after
--       UI/MinimapButton.lua) and carry OptionalDeps: EllesmereUI;
--    2. a half install (LibStub without LibDataBroker, a bare EllesmereUI
--       table): quiet, nothing published, no mover, nothing called;
--    3. two objects, data sources with the minimap button's icon;
--    4. one string: over a scripted fight the SpellTuner object's text is the
--       clock's words (the drawn segments) on every tick;
--    5. ASCII only, no colour code, no bare pipe, in every text, label,
--       tooltip and integrations line;
--    6. equal writes fire nothing; one spend fires exactly one text change;
--    7. the tint per tone;
--    8. the regen object in and out of combat, in the five-second rule, and
--       "Regen --" without a reading;
--    9. clicks: left the window, right Settings, both refused in combat;
--   10. the tooltip: the feed's lines and the hints, shown by the display;
--   11. a late reader finds the objects by name (no second NewDataObject);
--       a host that loads after MD_READY gets them on its ADDON_LOADED;
--   12. the mover saves, loads, applies, clears, hides with the clock and
--       waits out a fight; its listener previews while /unlock is open;
--   13. settings off (db.feeds.ldb, db.eui.unlock) publish and register
--       nothing;
--   14. RegisterSkin is called once, with "SpellTuner";
--   15. MakeUnlockElement keeps only its whitelist (the fake drops the rest,
--       as EllesmereUI does): every field passed is on it, and the mover still
--       saves and applies through what survived;
--   16. an EllesmereUI other than 9.3.4 runs, and the lines say
--       "(tested 9.3.4)";
--   17. a facade with apiVersion 3 is stored but no getter is read and
--       nothing is hooked: "skin apiVersion 3: not followed";
--   18. EUI_SKIN_READY fires once, whichever addon's PLAYER_LOGIN comes
--       first; apiVersion 2's OnLooksChanged fires EUI_LOOKS_CHANGED.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")
local PRINT = false
for _, a in ipairs(arg) do if a == "--print" then PRINT = true end end

local T = dofile(here .. "/lib/t.lua")
local H = dofile(here .. "/stub_hosts.lua")
local check = T.check

local LDB_FILE, EUI_FILE = "Integrations/Surface_LDB.lua", "Integrations/EllesmereUI_Forever.lua"
local NAME, REGEN = "SpellTuner", "SpellTuner Regen"
local ICON = "Interface\\Icons\\Spell_Shadow_Manaburn"

-- A block that raises (on the parent: no surface) is one FAIL, not the end.
local function Guarded(name, fn)
    local okRun, err = pcall(fn)
    if not okRun then check(name, false, "raised: " .. tostring(err)) end
end

local function Loaded(S, rel)
    for _, r in ipairs(S.loadedFiles or {}) do if r == rel then return true end end
    return false
end

-- Loads files after login and hands them the MD_READY they missed (their own
-- handlers, captured as they register: tools/minimapcheck.lua's way).
local function LoadByHand(MD, S, files)
    local ready, realReg = {}, MD.RegisterCallback
    MD.RegisterCallback = function(self, name, fn)
        if name == "MD_READY" then ready[#ready + 1] = fn end
        return realReg(self, name, fn)
    end
    local okLoad, err = pcall(S.Load, files, "SpellTuner", MD)
    MD.RegisterCallback = realReg
    if not okLoad then return false, err end
    for _, fn in ipairs(ready) do
        local okRun, e = pcall(fn)
        if not okRun then return false, e end
    end
    return true
end

-- A fresh session. `setup` runs with no host and no saved variables, before
-- the TOC loads (it installs hosts, presets SpellTunerDB). A tree whose TOC
-- does not list the two files yet has them loaded by hand, so the rest of the
-- suite still says something, and check 1 fails.
local function Session(setup)
    H.Remove()
    _G.SpellTunerDB, _G.ManaDemonDB = nil, nil
    if setup then setup() end
    local a0 = arg[0]; arg[0] = here .. "/harness.lua"
    local MD = dofile(here .. "/harness.lua")
    arg[0] = a0
    local S = _G.STUB
    local byToc = Loaded(S, LDB_FILE) and Loaded(S, EUI_FILE)
    local loadErr
    if not byToc then
        local files = {}
        for _, rel in ipairs({ LDB_FILE, EUI_FILE }) do
            local f = io.open((S.root or ".") .. "/" .. rel, "r")
            if f then f:close(); if not Loaded(S, rel) then files[#files + 1] = rel end end
        end
        if #files > 0 then
            local okL, e = LoadByHand(MD, S, files)
            if not okL then loadErr = e; print("load: " .. tostring(e)) end
        end
    end
    return MD, S, byToc, loadErr
end

local function Ticks(S, n) for _ = 1, n do S.Tick(0.5) end end

local function HasDumpLine(MD, key)
    for _, d in ipairs(MD.DumpLines and MD:DumpLines() or {}) do
        if d.key == key then return true, d.fn end
    end
    return false
end

local function DumpLine(MD)
    local _, fn = HasDumpLine(MD, "integrations")
    if not fn then return nil end
    local okD, line = pcall(fn)
    return okD and line or ("raised: " .. tostring(line))
end

-- The clock's words as drawn (UI/ClockView.lua's three segments), colour
-- codes removed: tools/clockcheck.lua's ClockText.
local function StripCodes(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function ClockText(MD)
    local v = MD.Clock and MD.Clock.view
    if not v then return nil end
    if v.msg and v.msg:IsShown() then return nil end -- the preview's message, not a face
    local function Seg(fs)
        if not fs or not fs:IsShown() then return nil end
        local t = fs:GetText()
        if t == nil or t == "" then return nil end
        return StripCodes(t)
    end
    local l, val, s = Seg(v.label), Seg(v.value), Seg(v.second)
    local out = l or ""
    if val then out = out .. " " .. val end
    if s then out = out .. "  " .. s end
    return out
end

local function TextChanges(lib, name)
    local n = 0
    for _, f in ipairs(lib.fired) do
        if f.event == "LibDataBroker_AttributeChanged" and f[1] == name and f[2] == "text" then n = n + 1 end
    end
    return n
end

local function AnyChanges(lib, name)
    local n = 0
    for _, f in ipairs(lib.fired) do
        if f.event == "LibDataBroker_AttributeChanged" and f[1] == name then n = n + 1 end
    end
    return n
end

local function Created(lib, name)
    local n = 0
    for _, f in ipairs(lib.fired) do
        if f.event == "LibDataBroker_DataObjectCreated" and f[1] == name then n = n + 1 end
    end
    return n
end

local function ReadTOC(root, toc)
    local f = io.open(root .. "/" .. toc, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

-- Every string the user could see from the integration, for check 5.
local seen = {}
local function Seen(s) if type(s) == "string" then seen[#seen + 1] = s end end

--------------------------------------------------------------------------------
-- 1. absent host
--------------------------------------------------------------------------------
T.section("1. absent host")
Guarded("1. absent host: quiet, nothing published, no global, no dump line; both files in the TOCs", function()
    local MD, S, byToc, loadErr = Session(nil)
    Ticks(S, 20)
    local root = S.root or "."
    local tocsOk, tocWhy = true, {}
    for _, toc in ipairs({ "SpellTuner_Mainline.toc", "SpellTuner.toc" }) do
        local files = S.TocFiles(toc)
        local at = {}
        for i, rel in ipairs(files) do at[rel] = i end
        local src = ReadTOC(root, toc) or ""
        local okThis = at["UI/MinimapButton.lua"] and at[LDB_FILE] and at[EUI_FILE]
            and at[LDB_FILE] > at["UI/MinimapButton.lua"] and at[EUI_FILE] > at[LDB_FILE]
            and src:find("\n## OptionalDeps: EllesmereUI\r?\n") ~= nil
        if not okThis then tocsOk = false; tocWhy[#tocWhy + 1] = toc end
    end
    local quiet = rawget(_G, "LibStub") == nil and rawget(_G, "EllesmereUI") == nil
        and MD.Surfaces and MD.Surfaces.ldb == nil and MD.Surfaces.eui == nil and MD.EUISkin == nil
        and MD.SurfaceLDB and MD.SurfaceLDB.Object("clock") == nil
    local noLine = not HasDumpLine(MD, "integrations")
    local dump = MD.BuildDump and MD:BuildDump() or ""
    check("1. absent host: quiet, nothing published, no global, no dump line; both files in the TOCs",
        byToc and tocsOk and quiet and noLine and not dump:find("integrations:", 1, true) and loadErr == nil,
        string.format("byToc=%s tocs=%s (%s) quiet=%s noLine=%s load=%s", tostring(byToc), tostring(tocsOk),
            table.concat(tocWhy, ","), tostring(quiet), tostring(noLine), tostring(loadErr)))
end)

--------------------------------------------------------------------------------
-- 2 and 11b. a half install, then a host that arrives late
--------------------------------------------------------------------------------
T.section("2. a half install; 11b. a late host")
Guarded("2. half install", function()
    local E
    local MD, S = Session(function()
        H.InstallLibStub()                      -- LibStub, no LibDataBroker
        E = H.InstallEllesmere({ bare = true }) -- EllesmereUI with none of its entry points
    end)
    Ticks(S, 20)
    local LDBS, EUI = MD.SurfaceLDB, MD.EUI
    local nothing = LDBS and LDBS.Object("clock") == nil and LDBS.Object("regen") == nil
        and MD.Surfaces.ldb == nil and MD.EUISkin == nil
    local mover = EUI and EUI.mover == nil and EUI.moverWhy == "not offered by this EllesmereUI"
    local line = DumpLine(MD)
    Seen(line)
    check("2. half install (LibStub without LDB, a bare EllesmereUI): quiet, nothing published, no mover",
        nothing and mover and EUI.skinRegistered == false
        and line == "integrations: EllesmereUI ? (tested 9.3.4), skin: not handed over, "
            .. "brokers: no broker library, mover: not offered by this EllesmereUI",
        string.format("nothing=%s mover=%s line=%s", tostring(nothing), tostring(mover), tostring(line)))

    -- 11b: LibDataBroker arrives after MD_READY (a host loaded on demand)
    local lib = H.InstallLDB()
    S.Fire("ADDON_LOADED", "SomeBrokerHost")
    local obj = LDBS.Object("clock")
    check("11b. a host loaded after MD_READY gets both objects on its ADDON_LOADED",
        obj ~= nil and lib:GetDataObjectByName(NAME) == obj and LDBS.Object("regen") ~= nil
        and Created(lib, NAME) == 1 and Created(lib, REGEN) == 1,
        "objects: " .. tostring(obj ~= nil))
end)

--------------------------------------------------------------------------------
-- The main session: EllesmereUI 9.3.4, LibDataBroker, the skin facade handed
-- over at EllesmereUI's PLAYER_LOGIN after ours.
--------------------------------------------------------------------------------
local E, lib
local MD, S = Session(function()
    lib = H.InstallLDB()
    E = H.InstallEllesmere()
end)
local LDBS, EUI = MD.SurfaceLDB or {}, MD.EUI or {}
H.AddOnMeta(MD, { EllesmereUI = { Version = "9.3.4" } })
local skinReady, looksChanged = {}, 0
MD:RegisterCallback("EUI_SKIN_READY", function(s) skinReady[#skinReady + 1] = s end)
MD:RegisterCallback("EUI_LOOKS_CHANGED", function() looksChanged = looksChanged + 1 end)
local S2 = H.SkinFacade()
E._DispatchSkins(S2) -- BlizzardSkin's PLAYER_LOGIN, after SpellTuner's MD_READY
Ticks(S, 4)

local function Obj(name) return lib:GetDataObjectByName(name) end

T.section("3-11. the brokers")
Guarded("3. two objects", function()
    local c, r = Obj(NAME), Obj(REGEN)
    local function Shape(o, name)
        return o ~= nil and o.type == "data source" and o.label == name and o.icon == ICON
            and type(o.OnClick) == "function" and type(o.OnTooltipShow) == "function" and o.OnEnter == nil
    end
    local n = 0
    for _ in lib:DataObjectIterator() do n = n + 1 end
    check("3. two objects, SpellTuner and SpellTuner Regen: data sources, the button's icon",
        n == 2 and Shape(c, NAME) and Shape(r, REGEN) and c == LDBS.Object("clock") and r == LDBS.Object("regen")
        and MD.Surfaces.ldb and MD.Surfaces.ldb.objects[1] == NAME and MD.Surfaces.ldb.objects[2] == REGEN,
        "objects " .. n)
end)

-- The scripted fight check 4 walks, recording every tick.
local fightTexts, fightMismatch, fightTicks, distinct = {}, {}, 0, {}
local function Compare(tag)
    local clock = ClockText(MD)
    local block = H.LdbBlockText(Obj(NAME))
    fightTicks = fightTicks + 1
    Seen(block)
    if clock ~= block then
        fightMismatch[#fightMismatch + 1] = tag .. ": clock [" .. tostring(clock) .. "] broker [" .. tostring(block) .. "]"
    end
    if block and not distinct[block] then
        distinct[block] = true
        fightTexts[#fightTexts + 1] = block
    end
end

Guarded("4. one string", function()
    local model = MD.Pool.model
    model.mana = model.max
    for i = 1, 6 do S.Tick(0.5); Compare("rest" .. i) end
    -- out of combat, a little spent: FULL in t
    for i = 1, 4 do S.Cast(5185); S.Tick(0.5); Compare("ooc" .. i) end
    for i = 1, 6 do S.Tick(0.5); Compare("ooc-wait" .. i) end
    -- a fight: warm-up, then out of mana with a rest segment
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    for i = 1, 60 do
        S.Cast(5185)
        model:Spend(120, GetTime()) -- a costly heal each half second: spend outruns regen
        S.Tick(0.5)
        Compare("fight" .. i)
    end
    -- stop casting: regen wins
    for i = 1, 30 do S.Tick(0.5); Compare("hold" .. i) end
    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false
    for i = 1, 6 do S.Tick(0.5); Compare("after" .. i) end
    local has = { full = false, fullT = false, warm = false, oomT = false, rest = false }
    for _, t in ipairs(fightTexts) do
        if t == "~FULL" then has.full = true end
        if t:find("^~FULL %d+:%d%d$") then has.fullT = true end
        if t == "~OOM ..." or t:find("^~OOM %.%.%.  rest ") then has.warm = true end
        if t:find("^~OOM %d+:%d%d") then has.oomT = true end
        if t:find("  rest %d+:%d%d$") then has.rest = true end
    end
    if PRINT then for _, t in ipairs(fightTexts) do print("  seen: " .. t) end end
    check("4. one string: the SpellTuner block equals the clock's words on every tick",
        #fightMismatch == 0 and fightTicks > 100 and has.full and has.fullT and has.warm and has.oomT and has.rest,
        string.format("%d mismatches of %d ticks%s; full=%s fullT=%s warm=%s oomT=%s rest=%s", #fightMismatch,
            fightTicks, fightMismatch[1] and (" first " .. fightMismatch[1]) or "", tostring(has.full),
            tostring(has.fullT), tostring(has.warm), tostring(has.oomT), tostring(has.rest)))
end)

Guarded("6. equal writes", function()
    local model = MD.Pool.model
    model.mana = model.max
    Ticks(S, 30) -- settle at full, out of combat
    local before = AnyChanges(lib, NAME) + AnyChanges(lib, REGEN)
    Ticks(S, 10)
    local quiet = AnyChanges(lib, NAME) + AnyChanges(lib, REGEN) - before
    local t0 = TextChanges(lib, NAME)
    S.Cast(5185)
    S.Tick(0.5)
    local one = TextChanges(lib, NAME) - t0
    check("6. ten quiet ticks fire nothing; one spend fires exactly one text change",
        quiet == 0 and one == 1, string.format("quiet fires %d, text changes after a spend %d", quiet, one))
    model.mana = model.max
    Ticks(S, 30)
end)

Guarded("7. tint", function()
    local CF = MD.ClockFace
    local by = {}
    for _, s in ipairs(CF.SAMPLES) do by[s.key] = s.face end
    local warn = {}
    for k, v in pairs(by.oom) do warn[k] = v end
    warn.value, warn.tone = 45, "warn"
    local want = {
        { "fullnow", by.fullnow, "mana" }, { "ooc", by.ooc, "mana" }, { "full", by.full, "mana" },
        { "warmup", by.warmup, "muted" }, { "hold", by.hold, "muted" }, { "bound", by.bound, "muted" },
        { "none", by.none, "muted" }, { "nodata", by.nodata, "muted" }, { "unstable", by.unstable, "muted" },
        { "oom > 60", by.oom, "normal" }, { "oom < 60", warn, "warn" }, { "oom < 20", by.crit, "crit" },
    }
    local bad = {}
    for _, w in ipairs(want) do
        local got = LDBS.ClockTone(w[2])
        if got ~= w[3] then bad[#bad + 1] = w[1] .. "=" .. tostring(got) end
    end
    -- and the live object carries the tone of the face it shows, as RGB
    local o = Obj(NAME)
    local r, g, b = CF.ToneRGB(LDBS.ClockTone(MD.Feeds.Face("clock")))
    local _, ir, ig, ib = H.LdbIcon(o)
    check("7. the tint per tone: FULL mana, bound / warm-up / no number muted, OOM by its band",
        #bad == 0 and ir == r and ig == g and ib == b, table.concat(bad, ", "))
end)

Guarded("8. regen", function()
    local model = MD.Pool.model
    local function N(rate) return math.floor(rate * 5 + 0.5) end
    local base, casting = MD.Pool:LastRegen()
    Ticks(S, 12)
    local out = H.LdbBlockText(Obj(REGEN))
    model:Spend(100, GetTime())
    S.Tick(0.5)
    local fsr = H.LdbBlockText(Obj(REGEN))
    local _, rr, rg, rb = H.LdbIcon(Obj(REGEN))
    local ar, ag, ab = MD.ClockFace.ToneRGB("warn")
    S.inCombat = true
    S.Fire("PLAYER_REGEN_DISABLED")
    S.Tick(0.5)
    local inFsr = H.LdbBlockText(Obj(REGEN))
    Ticks(S, 12)
    local inCombat = H.LdbBlockText(Obj(REGEN))
    S.Fire("PLAYER_REGEN_ENABLED")
    S.inCombat = false
    Ticks(S, 2)
    local uses = MD.player.usesMana
    MD.player.usesMana = false
    S.Tick(0.5)
    local none = H.LdbBlockText(Obj(REGEN))
    MD.player.usesMana = uses
    Ticks(S, 2)
    for _, s in ipairs({ out, fsr, inFsr, inCombat, none }) do Seen(s) end
    check("8. regen: 'Regen N' out of combat, (5SR) in the rule, '~' in combat, '--' without a reading",
        out == "Regen " .. N(base) and fsr == "Regen " .. N(casting) .. " (5SR)"
        and rr == ar and rg == ag and rb == ab
        and inFsr == "Regen ~" .. N(casting) .. " (5SR)" and inCombat == "Regen ~" .. N(base)
        and none == "Regen --",
        table.concat({ tostring(out), tostring(fsr), tostring(inFsr), tostring(inCombat), tostring(none) }, " / "))
end)

Guarded("9. clicks", function()
    local toggles, settings = 0, 0
    local rt, rs = MD.ToggleDashboard, MD.OpenDashboardSettings
    MD.ToggleDashboard = function() toggles = toggles + 1 end
    MD.OpenDashboardSettings = function() settings = settings + 1 end
    local block = CreateFrame("Button", nil, UIParent)
    Obj(NAME).OnClick(block, "LeftButton")
    Obj(REGEN).OnClick(block, "RightButton")
    local inC = MD.inCombat
    MD.inCombat = true
    Obj(NAME).OnClick(block, "LeftButton")
    Obj(REGEN).OnClick(block, "RightButton")
    MD.inCombat = inC
    MD.ToggleDashboard, MD.OpenDashboardSettings = rt, rs
    check("9. left-click opens the window, right-click Settings; both refused in combat",
        toggles == 1 and settings == 1, toggles .. "," .. settings)
end)

Guarded("10. tooltip", function()
    local function Lines(name)
        local tt = H.LdbTooltip(Obj(name))
        return tt and tt.log or {}
    end
    local log = Lines(NAME)
    local summary = MD.Clock:SummaryLines(GetTime())
    local has = {}
    for _, l in ipairs(log) do
        has[l] = true
        for field in l:gmatch("[^\t]+") do Seen(field) end
    end
    local summaryIn = #summary > 0
    for _, s in ipairs(summary) do
        local found = false
        for _, l in ipairs(log) do
            if l:find("AddDoubleLine\t" .. s.l .. "\t" .. s.r, 1, true) == 1 then found = true end
        end
        if not found then summaryIn = false end
    end
    local hints = false
    for _, l in ipairs(log) do
        if l:find("AddDoubleLine\tLeft-click\topen the window", 1, true) == 1 then hints = true end
    end
    local right, notInCombat = false, false
    for _, l in ipairs(log) do
        if l:find("AddDoubleLine\tRight-click\tSettings", 1, true) == 1 then right = true end
        if l:find("AddLine\t(not in combat)", 1, true) == 1 then notInCombat = true end
    end
    local shows = 0
    for _, l in ipairs(log) do if l == "Show" then shows = shows + 1 end end
    local regenLog = Lines(REGEN)
    check("10. the tooltip: the clock's summary and the hints, shown by the display (OnTooltipShow)",
        log[1] == "ClearLines" and log[2] and log[2]:find("^AddLine\tSpellTuner") ~= nil and summaryIn
        and hints and right and notInCombat and shows == 1 and log[#log] == "Show" and #regenLog == #log,
        string.format("lines %d summary=%s hints=%s/%s/%s shows=%d", #log, tostring(summaryIn), tostring(hints),
            tostring(right), tostring(notInCombat), shows))
end)

Guarded("11. a late reader", function()
    local before = Created(lib, NAME) + Created(lib, REGEN)
    local again = LDBS.Publish()
    -- a display created now: it binds by name and hears the next change
    local heard = 0
    local reader = {}
    lib.RegisterCallback(reader, "LibDataBroker_AttributeChanged_" .. NAME, function() heard = heard + 1 end)
    local found = lib:GetDataObjectByName(NAME)
    S.Cast(5185)
    S.Tick(0.5)
    check("11. a late reader finds the objects by name and hears the next change; no second NewDataObject",
        again == true and before == 2 and Created(lib, NAME) + Created(lib, REGEN) == 2
        and found == LDBS.Object("clock") and heard >= 1,
        string.format("created %d -> %d heard %d", before, Created(lib, NAME) + Created(lib, REGEN), heard))
    MD.Pool.model.mana = MD.Pool.model.max
    Ticks(S, 30)
end)

--------------------------------------------------------------------------------
-- 12, 14-16, 18: EllesmereUI's entry points
--------------------------------------------------------------------------------
T.section("12-18. EllesmereUI")
local elem = E._unlockRegisteredElements and E._unlockRegisteredElements["SpellTuner_Clock"]

Guarded("12. the mover", function()
    local frame = MD.Clock.frame
    S.Geometry(true)
    local reg = elem ~= nil and elem.folder == "SpellTuner" and elem.label == "SpellTuner clock"
        and elem.group == "SpellTuner" and elem.getFrame("SpellTuner_Clock") == frame
    local w, h = elem.getSize("SpellTuner_Clock")
    -- save (EllesmereUI hands CENTER/CENTER on UIParent), load, apply
    elem.savePosition("SpellTuner_Clock", "CENTER", "CENTER", 10, -20)
    local p = MD.db.clock.point
    local saved = type(p) == "table" and p[1] == "CENTER" and p[2] == nil and p[3] == "CENTER" and p[4] == 10 and p[5] == -20
    local fp, frel, frp, fx, fy = frame:GetPoint(1)
    local applied = frame:GetNumPoints() == 1 and fp == "CENTER" and frel == UIParent and frp == "CENTER" and fx == 10 and fy == -20
    local lp = elem.loadPosition("SpellTuner_Clock")
    local loaded = lp and lp.point == "CENTER" and lp.relPoint == "CENTER" and lp.x == 10 and lp.y == -20
    -- clear: the clock's reset, its default place
    elem.clearPosition("SpellTuner_Clock")
    local cp, crel, crp, cx, cy = frame:GetPoint(1)
    local cleared = MD.db.clock.point == nil and cp == "TOP" and crel == UIParent and crp == "TOP" and cx == 0 and cy == -120
        and elem.loadPosition("SpellTuner_Clock") == nil
    -- apply what is stored
    MD.db.clock.point = { "CENTER", nil, "CENTER", -30, 40 }
    elem.applyPosition("SpellTuner_Clock")
    local _, _, _, ax, ay = frame:GetPoint(1)
    local applyOk = ax == -30 and ay == 40
    -- in a fight the point is kept and applied after it
    MD.inCombat = true
    S.inCombat = true
    elem.savePosition("SpellTuner_Clock", "CENTER", "CENTER", 5, 5)
    local _, _, _, wx, wy = frame:GetPoint(1)
    local waited = wx == -30 and wy == 40 and MD.db.clock.point[4] == 5
    S.inCombat = false
    S.Fire("PLAYER_REGEN_ENABLED")
    local _, _, _, ex, ey = frame:GetPoint(1)
    local afterFight = ex == 5 and ey == 5
    -- hidden with the clock
    MD.db.clock.shown = false
    local hiddenOff = elem.isHidden("SpellTuner_Clock") == true
    MD.db.clock.shown = true
    local hiddenOn = elem.isHidden("SpellTuner_Clock") == false
    -- the listener: /unlock opened previews the clock, closed ends it
    E:_NotifyUnlockModeListeners(true)
    local previewing = MD.Clock:Previewing()
    E:_NotifyUnlockModeListeners(false, "save")
    local ended = not MD.Clock:Previewing()
    S.Geometry(false)
    elem.clearPosition("SpellTuner_Clock")
    check("12. the mover: saves, loads, applies, clears, waits out a fight, hides with the clock; /unlock previews",
        reg and w == 180 and h == 30 and saved and applied and loaded and cleared and applyOk and waited and afterFight
        and hiddenOff and hiddenOn and previewing and ended and E.calls.RegisterUnlockModeListener[1] == "SpellTuner",
        string.format("reg=%s size=%sx%s saved=%s applied=%s loaded=%s cleared=%s apply=%s waited=%s after=%s "
            .. "hidden=%s/%s preview=%s/%s", tostring(reg), tostring(w), tostring(h), tostring(saved), tostring(applied),
            tostring(loaded), tostring(cleared), tostring(applyOk), tostring(waited), tostring(afterFight),
            tostring(hiddenOff), tostring(hiddenOn), tostring(previewing), tostring(ended)))
end)

check("14. RegisterSkin is called once, with \"SpellTuner\"",
    E.calls and #E.calls.RegisterSkin == 1 and E.calls.RegisterSkin[1] == "SpellTuner" and EUI.skinRegistered == true,
    E.calls and tostring(#E.calls.RegisterSkin) or "no calls")

Guarded("15. whitelist", function()
    local passed = E.calls.MakeUnlockElement[1]
    local off = {}
    for k in pairs(passed or {}) do
        if H.UNLOCK_WHITELIST[k] == nil then off[#off + 1] = tostring(k) end
    end
    local required = { "key", "label", "group", "order", "getFrame", "getSize", "savePosition", "loadPosition",
        "clearPosition", "applyPosition", "isHidden" }
    local missing = {}
    for _, f in ipairs(required) do if elem[f] == nil then missing[#missing + 1] = f end end
    -- an option outside the list never reaches the unlock module: the fake drops it as EllesmereUI does
    local probe = E.MakeUnlockElement({ key = "x", notOnTheList = true })
    check("15. only whitelisted fields are passed; the element still saves and applies through what survived",
        #E.calls.MakeUnlockElement == 2 and #off == 0 and #missing == 0 and elem.noResize == true
        and probe.notOnTheList == nil and #E.calls.RegisterUnlockElements == 1,
        "off the list: " .. table.concat(off, ",") .. "; missing: " .. table.concat(missing, ","))
end)

Guarded("16. version", function()
    local at934 = DumpLine(MD)
    local pane934 = MD.Integrations.Lines()
    H.AddOnMeta(MD, { EllesmereUI = { Version = "9.4.0" } })
    local at940 = DumpLine(MD)
    local pane940 = MD.Integrations.Lines()
    Seen(at934); Seen(at940)
    for _, l in ipairs(pane934) do Seen(l) end
    for _, l in ipairs(pane940) do Seen(l) end
    local still = LDBS.Object("clock") ~= nil and EUI.mover == "SpellTuner_Clock"
    H.AddOnMeta(MD, { EllesmereUI = { Version = "9.3.4" } })
    check("16. an EllesmereUI other than 9.3.4 runs; the lines say (tested 9.3.4)",
        at934 == "integrations: EllesmereUI 9.3.4 (tested 9.3.4), skin apiVersion 2, brokers SpellTuner + "
            .. "SpellTuner Regen, mover SpellTuner_Clock"
        and at940 == "integrations: EllesmereUI 9.4.0 (tested 9.3.4), skin apiVersion 2, brokers SpellTuner + "
            .. "SpellTuner Regen, mover SpellTuner_Clock"
        and #pane940 == 1 and pane940[1] == "EllesmereUI 9.4.0 (tested 9.3.4): brokers SpellTuner + SpellTuner Regen; "
            .. "mover SpellTuner clock"
        and pane934[1] == "EllesmereUI 9.3.4 (tested 9.3.4): brokers SpellTuner + SpellTuner Regen; mover SpellTuner clock"
        and still,
        tostring(at940) .. " | " .. tostring(pane940[1]))
end)

Guarded("18. EUI_SKIN_READY", function()
    E._DispatchSkins(S2) -- a second drain changes nothing
    local readyOnce = #skinReady == 1 and skinReady[1] == S2 and MD.EUISkin == S2
    H.LooksChanged(S2)
    local getters = (S2.reads.GetAccentColor or 0) + (S2.reads.GetPanelColor or 0) + (S2.reads.GetFont or 0)
    check("18. EUI_SKIN_READY fires once (EllesmereUI's login after ours); OnLooksChanged -> EUI_LOOKS_CHANGED",
        readyOnce and looksChanged == 1 and S2.reads.OnLooksChanged == 1 and getters == 0 and EUI.SkinFollowed(),
        string.format("ready %d, looks %d, hooked %s, getters %d", #skinReady, looksChanged,
            tostring(S2.reads.OnLooksChanged), getters))
end)

--------------------------------------------------------------------------------
-- 17 (and 18's other order): a facade with apiVersion 3, handed over before
-- SpellTuner registered (EllesmereUI's login first: the registration runs
-- the callback at once).
--------------------------------------------------------------------------------
Guarded("17. apiVersion 3", function()
    local E3, S3 = nil, H.SkinFacade({ apiVersion = 3 })
    local readyN = 0
    local MD3, S = Session(function()
        H.InstallLDB()
        E3 = H.InstallEllesmere()
        E3._DispatchSkins(S3)
    end)
    -- the callback ran at SpellTuner's file load, before this listener: the
    -- facade is stored all the same
    MD3:RegisterCallback("EUI_SKIN_READY", function() readyN = readyN + 1 end)
    E3._DispatchSkins(S3)
    Ticks(S, 6)
    local reads = 0
    for _, n in pairs(S3.reads) do reads = reads + n end
    local line = DumpLine(MD3)
    Seen(line)
    check("17. apiVersion 3: stored, no getter read, nothing hooked, 'skin apiVersion 3: not followed'",
        MD3.EUISkin == S3 and reads == 0 and readyN == 0 and not MD3.EUI.SkinFollowed()
        and line ~= nil and line:find(", skin apiVersion 3: not followed, ", 1, true) ~= nil,
        string.format("reads %d, ready %d, line %s", reads, readyN, tostring(line)))
end)

--------------------------------------------------------------------------------
-- 13. settings off
--------------------------------------------------------------------------------
Guarded("13. settings off", function()
    local E4, lib4
    local MD4, S = Session(function()
        _G.SpellTunerDB = { feeds = { ldb = false }, eui = { unlock = false } }
        lib4 = H.InstallLDB()
        E4 = H.InstallEllesmere()
    end)
    Ticks(S, 6)
    local n = 0
    for _ in lib4:DataObjectIterator() do n = n + 1 end
    local line = DumpLine(MD4)
    Seen(line)
    check("13. db.feeds.ldb = false publishes nothing; db.eui.unlock = false registers no mover",
        n == 0 and #E4.calls.MakeUnlockElement == 0 and #E4.calls.RegisterUnlockElements == 0
        and MD4.EUI.moverWhy == "off" and MD4.db.feeds.compact == false and MD4.db.feeds.elvui == true
        and line == "integrations: EllesmereUI ? (tested 9.3.4), skin: not handed over, brokers off, mover: off",
        string.format("objects %d, elements %d, line %s", n, #E4.calls.RegisterUnlockElements, tostring(line)))
end)

--------------------------------------------------------------------------------
-- 5. every string seen above
--------------------------------------------------------------------------------
do
    local bad
    for _, s in ipairs(seen) do
        local okA, why = T.Ascii(s, { noColour = true })
        if not okA then bad = tostring(s) .. " (" .. tostring(why) .. ")"; break end
    end
    check("5. ASCII only, no colour code, no bare pipe: texts, labels, tooltips, integrations lines",
        #seen > 150 and bad == nil, bad or (#seen .. " strings"))
end

T.done()
