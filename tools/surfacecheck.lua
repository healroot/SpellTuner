-- tools/run.sh [--flavour tbc|forever] tools/surfacecheck.lua [--print | --golden]
--
-- T92 (docs/SPEC-next.md 2.3, S3 step 1; R-arch.md 5): feeds and the ElvUI
-- surface. A FEED (UI/Feeds.lua, MD.Feeds: `clock`, `regen`) is one piece of
-- information to show -- a text, a face, a tooltip, a click; a SURFACE shows
-- feeds. The ElvUI datatexts moved from Integrations/ElvUIDatatext.lua to
-- Integrations/Surface_ElvUI.lua and read the feeds; the TBC text stays byte
-- for byte what it was. The harness now loads Integrations/ on TBC.
--
-- What is held:
--   1. no host: the surface file loads with no ElvUI, with only LibStub /
--      LibDataBroker present, and with a half ElvUI (no DataTexts module), and
--      registers nothing and raises nothing; on TBC the harness loaded it from
--      the TOC (Integrations/ is no longer dropped);
--   2. ElvUI gets exactly two datatexts, "SpellTuner" and "SpellTuner Regen",
--      with ElvUI's argument shape (update, click, enter, ApplySettings);
--   3. tbc: the golden -- both datatexts' text, with and without a value
--      colour from ApplySettings (in both shapes ElvUI hands it), over a
--      scripted fight, the tooltip at three moments, the throttle and both
--      clicks -- captured with --golden on the parent (231525d) against
--      Integrations/ElvUIDatatext.lua, BEFORE the move, and equal after;
--      forever: the clock datatext is the pool's face, the regen datatext the
--      pool's last plain reading (`~` in combat, `(5SR)` in the rule), never
--      MD.Regen and never a secret;
--   4. ApplySettings recolours the value (both lines);
--   5. the feeds' contract: two feeds in order, a second registration
--      raising, every clock sample through the clock feed equal to
--      ClockFace.LineString, ASCII and no bare pipe (plain: no colour code),
--      the regen feed's words, the tooltip the minimap's lines, the click
--      (left: the window, right: Settings, nothing in combat), a feed that
--      raises answering its label;
--   6. FEED_CHANGED fires from the tick exactly when a feed's text changed.
--
-- `--print` prints the transcript; `--golden` prints the golden block to paste.
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local mode = "check"
for i = 1, #arg do
    if arg[i] == "--print" then mode = "print" elseif arg[i] == "--golden" then mode = "golden" end
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB
local T = dofile(here .. "/lib/t.lua")
local H = dofile(here .. "/stub_hosts.lua")
local check = T.check
local FLAVOUR = S.flavour
local root = S.root or "."

local NEW_FILE, OLD_FILE = "Integrations/Surface_ElvUI.lua", "Integrations/ElvUIDatatext.lua"
local FEEDS_FILE = "UI/Feeds.lua"
local function Exists(rel)
    local f = io.open(root .. "/" .. rel, "r")
    if f then f:close() return true end
    return false
end
local SURFACE = Exists(NEW_FILE) and NEW_FILE or OLD_FILE
local function Loaded(rel)
    for _, r in ipairs(S.loadedFiles or {}) do if r == rel then return true end end
    return false
end

-- A block that raises (on the parent: no feeds) is one FAIL, not the end.
local function Guarded(name, fn)
    local okRun, err = pcall(fn)
    if not okRun then check(name, false, "raised: " .. tostring(err)) end
end

-- Loads files after login and hands them the MD_READY they missed (only their
-- own handlers, captured as they register: tools/ttocheck.lua's way).
local function LoadByHand(files)
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

-- A surface file loaded on its own (no MD_READY to hand it: it registers at
-- load, as the old file did).
local function LoadSurface()
    return pcall(S.Load, { SURFACE }, "SpellTuner", MD)
end

--------------------------------------------------------------------------------
-- What the TBC harness does not load: the kit, the tooltip builders and the
-- feeds (UI/ is dropped there but for UI/Summary.lua). On Forever the main TOC
-- lists UI/Feeds.lua; a tree whose TOC does not list it yet has it loaded here.
--------------------------------------------------------------------------------
local feedsByToc = Loaded(FEEDS_FILE)
do
    local files = {}
    if FLAVOUR == "tbc" then
        files = { "UI/Style.lua", "UI/Theme_Flat.lua", "UI/Tip.lua", "UI/Tip_TBC.lua" }
    end
    if not feedsByToc and Exists(FEEDS_FILE) then files[#files + 1] = FEEDS_FILE end
    if #files > 0 then
        local okLoad, err = LoadByHand(files)
        if not okLoad then print("load: " .. tostring(err)) end
    end
end
local Feeds = MD.Feeds

--------------------------------------------------------------------------------
-- 1. no host
--------------------------------------------------------------------------------
T.section("1. no host")
if FLAVOUR == "tbc" then
    check("1a. the TBC harness loads Integrations/ (the surface from the TOC)", Loaded(NEW_FILE),
        "loaded: " .. tostring(Loaded(NEW_FILE)) .. ", old file loaded: " .. tostring(Loaded(OLD_FILE)))
else
    check("1a. the Forever TOC lists UI/Feeds.lua", feedsByToc)
end
check("1b. MD.Feeds exists", type(Feeds) == "table")

H.Remove()
do
    local okLoad, err = LoadSurface()
    check("1c. no ElvUI: the surface loads and raises nothing", okLoad, tostring(err))
end
do
    local lib = H.InstallLDB()
    local okLoad, err = LoadSurface()
    local n = 0
    for _ in lib:DataObjectIterator() do n = n + 1 end
    check("1d. LibStub + LibDataBroker but no ElvUI: no raise, no object", okLoad and n == 0,
        tostring(err) .. ", objects " .. n)
    H.Remove()
end
do
    H.InstallElvUI({ noDataTexts = true })
    local okLoad, err = LoadSurface()
    check("1e. a half ElvUI (no DataTexts module): no raise", okLoad, tostring(err))
    H.Remove()
end

--------------------------------------------------------------------------------
-- 2. ElvUI: exactly two datatexts
--------------------------------------------------------------------------------
T.section("2. ElvUI gets two datatexts")
local _, DT = H.InstallElvUI()
do
    local okLoad, err = LoadSurface()
    check("2a. with ElvUI the surface loads", okLoad, tostring(err))
end
local OOM, REG = DT.byName["SpellTuner"], DT.byName["SpellTuner Regen"]
check("2b. exactly two datatexts: SpellTuner, SpellTuner Regen", #DT.registered == 2 and OOM and REG
    and DT.registered[1] == OOM and DT.registered[2] == REG, tostring(#DT.registered))
local function Shape(rec)
    return rec and type(rec.updateFunc) == "function" and type(rec.clickFunc) == "function"
        and type(rec.onEnterFunc) == "function" and type(rec.applySettings) == "function"
        and rec.category == nil and rec.events == nil and rec.eventFunc == nil and rec.onLeaveFunc == nil
        and rec.localizedName == rec.name and rec.objectEvent == nil and rec.n == 11
end
check("2c. ElvUI's argument shape (update, click, enter, ApplySettings; 11 arguments)", Shape(OOM) and Shape(REG))

-- One read of a datatext: a fresh panel, ElvUI's first OnUpdate (20000).
local function Read(rec)
    local p = H.Panel()
    rec.updateFunc(p, 20000)
    return p.value
end
local function Colour(hex) OOM.applySettings(nil, hex); REG.applySettings(nil, hex) end

--------------------------------------------------------------------------------
-- 3. tbc: the golden (and the fight that FEED_CHANGED reuses below)
--------------------------------------------------------------------------------
local transcript = {}
local function Rec(line) transcript[#transcript + 1] = line end
local function Snap(id)
    Colour(nil)
    local a, r1 = Read(OOM), Read(REG)
    Colour("16c3f2")
    local b, r2 = Read(OOM), Read(REG)
    Colour("|cff16c3f2")
    local c, r3 = Read(OOM), Read(REG)
    Colour(nil)
    Rec(table.concat({ id, a, b, c, r1, r2, r3 }, "\t"))
end
local function Tooltip(id)
    DT.tooltip.log = {}
    OOM.onEnterFunc()
    for i, l in ipairs(DT.tooltip.log) do Rec(id .. "#" .. i .. "\t" .. l) end
    local first = #DT.tooltip.log
    DT.tooltip.log = {}
    REG.onEnterFunc()
    local same = #DT.tooltip.log == first
    Rec(id .. "#regen-same\t" .. tostring(same))
end

local SD = MD.SpellData
local HT5 = 5189
local function Ticks(n) for _ = 1, n do S.Tick(0.5) end end

if FLAVOUR == "tbc" then
    T.section("3. tbc: the datatexts byte for byte (golden captured before the move)")
    local regenBase, regenCast = 10, 5
    _G.GetManaRegen = function() return regenBase, regenCast end
    local function Cast(id)
        S.mana = math.max(0, S.mana - SD:GetCost(id))
        S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", id)
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
    end
    Guarded("3. the golden fight", function()
        Snap("login")
        Ticks(2)
        Snap("full")
        Tooltip("tip-full")
        S.mana = math.floor(S.manaMax * 0.74)
        S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
        Ticks(2)
        Snap("ooc74")
        S.Fire("PLAYER_REGEN_DISABLED")
        Ticks(1)
        Snap("pull")
        local n = 0
        for i = 1, 60 do
            if i % 4 == 1 then Cast(HT5); n = n + 1 end
            S.Tick(0.5)
            if i % 3 == 0 then Snap("fight" .. i) end
        end
        Tooltip("tip-fight")
        for i = 1, 30 do
            if i % 2 == 1 then Cast(HT5) end
            S.Tick(0.5)
            if i % 3 == 0 then Snap("fast" .. i) end
        end
        regenBase, regenCast = 200, 120
        for i = 1, 24 do
            S.Tick(0.5)
            if i % 4 == 0 then Snap("regen" .. i) end
        end
        S.Fire("PLAYER_REGEN_ENABLED")
        Ticks(1)
        Snap("left")
        Ticks(12)
        Snap("left6s")
        Tooltip("tip-after")
        local uses = MD.player.usesMana
        MD.player.usesMana = false
        Snap("nomana")
        MD.player.usesMana = uses
        -- the throttle: a write only once 0.25 s has gathered
        local p = H.Panel()
        OOM.updateFunc(p, 20000); local w1 = p.writes
        OOM.updateFunc(p, 0.1); local w2 = p.writes
        OOM.updateFunc(p, 0.1); local w3 = p.writes
        OOM.updateFunc(p, 0.1); local w4 = p.writes
        Rec("throttle\t" .. w1 .. "," .. w2 .. "," .. w3 .. "," .. w4)
        -- the clicks
        local toggles, resets = 0, 0
        local realToggle, realReset = MD.ToggleDashboard, MD.Spend.Reset
        MD.ToggleDashboard = function() toggles = toggles + 1 end
        MD.Spend.Reset = function(self, ...) resets = resets + 1; return realReset(self, ...) end
        local chat = T.CapturedChat(function()
            S.shift = false
            OOM.clickFunc(); REG.clickFunc()
            S.shift = true
            OOM.clickFunc(); REG.clickFunc()
            S.shift = false
        end)
        MD.ToggleDashboard, MD.Spend.Reset = realToggle, realReset
        Rec("clicks\ttoggles=" .. toggles .. "\tresets=" .. resets .. "\tchat=" .. table.concat(chat, " / "))
    end)

    if mode == "golden" then
        print("-- GOLDEN (paste between the markers)")
        for _, l in ipairs(transcript) do print(l) end
        os.exit(0)
    end
    if mode == "print" then for _, l in ipairs(transcript) do print(l) end end

    local GOLDEN = {}
    local src = io.open(arg[0], "r"):read("*a")
    local block = src:match("%-%-%[=%[GOLDEN_TBC\n(.-)%]=%]")
    for line in (block or ""):gmatch("([^\n]*)\n") do GOLDEN[#GOLDEN + 1] = line end
    local firstDiff
    for i = 1, math.max(#GOLDEN, #transcript) do
        if GOLDEN[i] ~= transcript[i] then firstDiff = i; break end
    end
    check("3a. the golden holds line for line (" .. #GOLDEN .. " lines)", #GOLDEN > 0 and firstDiff == nil,
        firstDiff and ("line " .. firstDiff .. ": want [" .. tostring(GOLDEN[firstDiff]) .. "] got ["
            .. tostring(transcript[firstDiff]) .. "]"))
    local clean, bad = true, nil
    for _, l in ipairs(transcript) do
        for field in l:gmatch("[^\t]+") do
            local okA = T.Ascii(field)
            if not okA then clean, bad = false, field end
        end
    end
    check("3b. every datatext string ASCII, no bare pipe", clean, bad)
else
    T.section("3. forever: the datatexts read the pool")
    Guarded("3. forever datatexts", function()
        Ticks(2)
        local CF = MD.ClockFace
        local face = CF.Current()
        local want = CF.LineString(face)
        check("3a. the clock datatext is the pool's face (ClockFace.Current)",
            Read(OOM) == (want ~= "" and want or "SpellTuner"), tostring(Read(OOM)) .. " / " .. tostring(want))
        check("3b. out of combat: Regen: 346 (69.24 mp1 x 5)", Read(REG) == "Regen: |cffffffff346|r", Read(REG))

        -- a trap: any read of MD.Regen counted (it is nil on this line)
        local regenReads = 0
        local hadMeta = getmetatable(MD)
        if hadMeta == nil then
            setmetatable(MD, { __index = function(_, k) if k == "Regen" then regenReads = regenReads + 1 end end })
        end
        local model = MD.Pool.model
        model:Spend(100, GetTime())
        check("3c. inside the five-second rule: the casting rate and (5SR)",
            Read(REG) == "Regen: |cffffffff142|r |cffffaa33(5SR)|r", Read(REG))
        S.inCombat = true
        S.Fire("PLAYER_REGEN_DISABLED")
        Ticks(1)
        local inFsr = Read(REG)
        Ticks(12)
        local outFsr = Read(REG)
        check("3d. in combat (ManaRegen secret): the last plain reading, marked ~",
            inFsr == "Regen: |cffffffff~142|r |cffffaa33(5SR)|r" and outFsr == "Regen: |cffffffff~346|r",
            tostring(inFsr) .. " / " .. tostring(outFsr))
        local base, casting = MD.API.ManaRegen()
        check("3e. ...while the client's own reading is secret (the stub's in combat)",
            base == nil and casting == "secret", tostring(base) .. ", " .. tostring(casting))
        local face2 = CF.Current()
        check("3f. the clock datatext in combat is still the face",
            Read(OOM) == CF.LineString(face2), Read(OOM))
        -- a secret where a reading should be: "--", never a raise
        local realLast = MD.Pool.LastRegen
        MD.Pool.LastRegen = function() return S.Secret(), S.Secret() end
        local okR, txt = pcall(Read, REG)
        MD.Pool.LastRegen = realLast
        check("3g. a secret regen reading reads --, raises nothing", okR and txt == "Regen: |cffffffff--|r",
            tostring(txt))
        local uses = MD.player.usesMana
        MD.player.usesMana = false
        check("3h. no mana pool: Regen: --", Read(REG) == "Regen: |cffffffff--|r", Read(REG))
        MD.player.usesMana = uses
        if hadMeta == nil then setmetatable(MD, nil) end
        check("3i. MD.Regen never read on this line", regenReads == 0, tostring(regenReads))
        S.inCombat = false
        S.Fire("PLAYER_REGEN_ENABLED")
        Ticks(2)
        -- shift-click on this line: there is no spend window to reset, the window toggles
        local toggles = 0
        local realToggle = MD.ToggleDashboard
        MD.ToggleDashboard = function() toggles = toggles + 1 end
        S.shift = true
        local okC, errC = pcall(OOM.clickFunc)
        S.shift = false
        OOM.clickFunc()
        MD.ToggleDashboard = realToggle
        check("3j. a click raises nothing without TBC's spend window", okC and toggles >= 1, tostring(errC))
        DT.tooltip.log = {}
        local okT, errT = pcall(OOM.onEnterFunc)
        local first = DT.tooltip.log[2] or ""
        check("3k. the tooltip: the clock feed's lines, shown", okT and DT.tooltip.shown and #DT.tooltip.log > 2
            and first:find("SpellTuner", 1, true) ~= nil, tostring(errT) .. " " .. first)
    end)
end

--------------------------------------------------------------------------------
-- 4. ApplySettings recolours the value
--------------------------------------------------------------------------------
T.section("4. ApplySettings")
Guarded("4. ApplySettings", function()
    Colour("ff0000")
    local r1 = Read(REG)
    Colour("|cff00ff00")
    local r2 = Read(REG)
    Colour(nil)
    local r3 = Read(REG)
    check("4a. the regen value in the host's colour, white without one",
        r1:find("|cffff0000", 1, true) ~= nil and r2:find("|cff00ff00", 1, true) ~= nil
        and r3:find("|cffffffff", 1, true) ~= nil and not r3:find("ff0000", 1, true), r1 .. " / " .. r2)
    if FLAVOUR == "tbc" then
        -- the clock's value colour (TBC: the face is coloured; a point value takes the host's)
        local saved = MD.ClockFace.Current
        local sample
        for _, s in ipairs(MD.ClockFace.SAMPLES) do if s.key == "oom" then sample = s.face end end
        rawset(MD.ClockFace, "Current", function() return sample end)
        Colour("ff0000")
        local c1 = Read(OOM)
        Colour(nil)
        local c2 = Read(OOM)
        rawset(MD.ClockFace, "Current", saved)
        check("4b. the clock's value in the host's colour", c1:find("|cffff0000", 1, true) ~= nil
            and c2:find("|cffff0000", 1, true) == nil, c1)
    else
        check("4b. the clock's line keeps its one colour on this line (mono until T93)",
            not Read(OOM):find("|c", 1, true), Read(OOM))
    end
end)

--------------------------------------------------------------------------------
-- 5. the feeds' contract
--------------------------------------------------------------------------------
T.section("5. MD.Feeds")
Guarded("5. feeds", function()
    local list = Feeds.List()
    check("5a. two feeds, in order: clock, regen", #list == 2 and list[1] == "clock" and list[2] == "regen",
        table.concat(list, ","))
    local clock, regen = Feeds.Get("clock"), Feeds.Get("regen")
    check("5b. labels and the icon", clock.label == "SpellTuner" and regen.label == "SpellTuner Regen"
        and clock.icon == "Interface\\Icons\\Spell_Shadow_Manaburn" and regen.icon == clock.icon)
    check("5c. a second registration raises", not pcall(Feeds.Register, "clock", { Text = function() return "" end }))
    check("5d. a feed with no Text raises", not pcall(Feeds.Register, "nothing", {}))
    check("5e. List is a copy", (function() local l = Feeds.List(); l[1] = "x"; return Feeds.List()[1] == "clock" end)())

    -- every clock sample through the feed: the face's own line
    local CF = MD.ClockFace
    local saved = CF.Current
    local same, clean, plainClean, bad = true, true, true, nil
    for _, s in ipairs(CF.SAMPLES) do
        rawset(CF, "Current", function() return s.face end)
        local want = CF.LineString(s.face)
        local got, gotHex = Feeds.Text("clock", {}), Feeds.Text("clock", { valueHex = "|cff16c3f2" })
        local plain = Feeds.Text("clock", { plain = true })
        if got ~= want or gotHex ~= CF.LineString(s.face, "|cff16c3f2") then same, bad = false, s.key end
        if not T.Ascii(got) or not T.Ascii(gotHex) then clean, bad = false, s.key end
        if not T.Ascii(plain, { noColour = true }) or plain ~= T.Strip(want) then plainClean, bad = false, s.key end
    end
    rawset(CF, "Current", function() return nil end)
    local none = Feeds.Text("clock", {})
    rawset(CF, "Current", saved)
    check("5f. every clock sample: the feed's text is ClockFace.LineString (with and without a value colour)", same, bad)
    check("5g. ASCII, no bare pipe", clean, bad)
    check("5h. plain: the same words, no colour code", plainClean, bad)
    check("5i. no face yet: the feed's label", none == "SpellTuner", none)

    local face = Feeds.Face("clock")
    check("5j. Face answers the current face", type(face) == "table" and face.label ~= nil)

    -- the regen feed's words
    local plain = Feeds.Text("regen", { plain = true })
    check("5k. regen plain: 'Regen <n>' with no colour code",
        plain:match("^Regen ~?%d+$") ~= nil or plain:match("^Regen ~?%d+ %(5SR%)$") ~= nil, plain)
    local uses = MD.player.usesMana
    MD.player.usesMana = false
    local dash, dashPlain = Feeds.Text("regen", {}), Feeds.Text("regen", { plain = true })
    MD.player.usesMana = uses
    check("5l. no reading: 'Regen: --' / plain 'Regen --'", dash == "Regen: |cffffffff--|r" and dashPlain == "Regen --",
        dash .. " / " .. dashPlain)

    -- the tooltip: the minimap tooltip's lines
    local tip = Feeds.Tooltip("clock")
    local mm = MD.MinimapLines and MD.MinimapLines()
    local equal = type(tip) == "table" and type(mm) == "table" and #tip == #mm
    if equal then for i = 1, #tip do if tip[i].l ~= mm[i].l or tip[i].r ~= mm[i].r then equal = false end end end
    check("5m. the clock feed's tooltip is the minimap tooltip's lines", equal and #tip > 0)
    check("5n. the regen feed's tooltip too", type(Feeds.Tooltip("regen")) == "table" and #Feeds.Tooltip("regen") > 0)

    -- the click: left the window, right Settings, nothing in combat
    local toggles, settings = 0, 0
    local rt, rs = MD.ToggleDashboard, MD.OpenDashboardSettings
    MD.ToggleDashboard = function() toggles = toggles + 1 end
    MD.OpenDashboardSettings = function() settings = settings + 1 end
    Feeds.Click("clock", "LeftButton")
    Feeds.Click("regen", "RightButton")
    local inC = MD.inCombat
    MD.inCombat = true
    local refused = Feeds.Click("clock", "LeftButton")
    MD.inCombat = inC
    MD.ToggleDashboard, MD.OpenDashboardSettings = rt, rs
    check("5o. click: left the window, right Settings, refused in combat", toggles == 1 and settings == 1
        and refused == false, toggles .. "," .. settings .. "," .. tostring(refused))
end)

--------------------------------------------------------------------------------
-- 6. FEED_CHANGED from the tick, only on a change
--------------------------------------------------------------------------------
T.section("6. FEED_CHANGED")
Guarded("6. FEED_CHANGED", function()
    local fired = { clock = 0, regen = 0 }
    local atFire = {}
    MD:RegisterCallback("FEED_CHANGED", function(key)
        fired[key] = (fired[key] or 0) + 1
        atFire[#atFire + 1] = { key = key, text = Feeds.Text(key, {}) }
    end)
    Ticks(4)
    fired.clock, fired.regen, atFire = 0, 0, {}
    Ticks(8)
    check("6a. nothing changes: no FEED_CHANGED", fired.clock == 0 and fired.regen == 0,
        fired.clock .. "," .. fired.regen)

    -- a fight: count the ticks on which each feed's text changed, beside the fires
    local changes = { clock = 0, regen = 0 }
    local last = { clock = Feeds.Text("clock", {}), regen = Feeds.Text("regen", {}) }
    if FLAVOUR == "tbc" then
        S.Fire("PLAYER_REGEN_DISABLED")
    else
        S.inCombat = true
        S.Fire("PLAYER_REGEN_DISABLED")
    end
    for i = 1, 40 do
        if i % 5 == 1 then
            if FLAVOUR == "tbc" then
                S.mana = math.max(0, S.mana - SD:GetCost(HT5))
                S.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", HT5)
                S.Fire("UNIT_POWER_UPDATE", "player", "MANA")
            else
                MD.Pool.model:Spend(150, GetTime())
            end
        end
        S.Tick(0.5)
        for _, k in ipairs({ "clock", "regen" }) do
            local now = Feeds.Text(k, {})
            if now ~= last[k] then changes[k] = changes[k] + 1; last[k] = now end
        end
    end
    check("6b. a fight: FEED_CHANGED once per tick on which the text changed",
        fired.clock == changes.clock and fired.regen == changes.regen and changes.clock > 0 and changes.regen > 0,
        string.format("clock %d/%d, regen %d/%d", fired.clock, changes.clock, fired.regen, changes.regen))
    local fresh = true
    for _, f in ipairs(atFire) do if f.text ~= last[f.key] and f == atFire[#atFire] then fresh = false end end
    check("6c. a listener reads the new text when it fires", fresh)
end)

-- Last: a feed whose Text raises answers its label (registered here, after
-- every count above).
Guarded("7. a raising feed", function()
    Feeds.Register("zz-test", { label = "Test", Text = function() error("boom") end })
    local okT, txt = pcall(Feeds.Text, "zz-test", {})
    check("7. a feed that raises answers its label, never into the host", okT and txt == "Test", tostring(txt))
end)

T.done()

--[=[GOLDEN_TBC
login	SpellTuner	SpellTuner	SpellTuner	Regen: |cffffffff346|r	Regen: |cff16c3f2346|r	Regen: |cff16c3f2346|r
full	|cff33ff66FULL|r	|cff33ff66FULL|r	|cff33ff66FULL|r	Regen: |cffffffff50|r	Regen: |cff16c3f250|r	Regen: |cff16c3f250|r
tip-full#1	ClearLines
tip-full#2	AddLine	SpellTuner
tip-full#3	AddDoubleLine	Time to full (raw)	0s	1	1	1	1	1	1
tip-full#4	AddDoubleLine	Net rate (pessimistic)	+10 mana/s	1	1	1	1	1	1
tip-full#5	AddDoubleLine	Spending	0 +- 0 mana/s (0 casts, CV 0.00)	1	1	1	1	1	1
tip-full#6	AddDoubleLine	Regen now / projected	10 / 10 mana/s  (5SR 0% of time)	1	1	1	1	1	1
tip-full#7	AddDoubleLine	Regen out of 5SR / casting	10 / 5 mana/s	1	1	1	1	1	1
tip-full#8	AddDoubleLine	Spirit / gear mp5	~35 / ~14	1	1	1	1	1	1
tip-full#9	AddLine	 
tip-full#10	AddDoubleLine	Innervate	571 mana, ready	0.780	0.780	0.780	0.310	0.660	0.940
tip-full#11	AddLine	 
tip-full#12	AddLine	Click: dashboard   Shift-click: reset window	0.500	0.500	0.500
tip-full#13	Show
tip-full#regen-same	true
ooc74	|cff999999FULL|r |cff33ff663:05|r	|cff999999FULL|r |cff16c3f23:05|r	|cff999999FULL|r |cff16c3f23:05|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
pull	|cff999999OOM ...|r  |cff999999rest 3:05|r	|cff999999OOM ...|r  |cff999999rest 3:05|r	|cff999999OOM ...|r  |cff999999rest 3:05|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight3	|cff999999OOM ...|r  |cff999999rest 3:25|r	|cff999999OOM ...|r  |cff999999rest 3:25|r	|cff999999OOM ...|r  |cff999999rest 3:25|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight6	|cff999999OOM ...|r  |cff999999rest 3:50|r	|cff999999OOM ...|r  |cff999999rest 3:50|r	|cff999999OOM ...|r  |cff999999rest 3:50|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight9	|cff999999OOM|r |cff999999~2:00|r |cff999999=|r  |cff999999rest 4:10|r	|cff999999OOM|r |cff999999~2:00|r |cff999999=|r  |cff999999rest 4:10|r	|cff999999OOM|r |cff999999~2:00|r |cff999999=|r  |cff999999rest 4:10|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight12	|cff999999OOM|r |cff999999~2:00|r |cff999999=|r  |cff999999rest 4:10|r	|cff999999OOM|r |cff999999~2:00|r |cff999999=|r  |cff999999rest 4:10|r	|cff999999OOM|r |cff999999~2:00|r |cff999999=|r  |cff999999rest 4:10|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight15	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:30|r	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:30|r	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:30|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight18	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:55|r	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:55|r	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 4:55|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight21	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 5:15|r	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 5:15|r	|cff999999OOM|r |cff999999~1:30|r |cff999999=|r  |cff999999rest 5:15|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight24	|cff999999OOM|r |cff999999~1:00|r |cff999999=|r  |cff999999rest 5:15|r	|cff999999OOM|r |cff999999~1:00|r |cff999999=|r  |cff999999rest 5:15|r	|cff999999OOM|r |cff999999~1:00|r |cff999999=|r  |cff999999rest 5:15|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight27	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 5:35|r	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 5:35|r	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 5:35|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight30	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 6:00|r	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 6:00|r	|cff999999OOM|r |cff999999~1:00|r |cffffaa33v|r  |cff999999rest 6:00|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight33	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 6:20|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 6:20|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 6:20|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight36	|cff999999OOM|r |cffffaa3340s|r |cffffaa33v|r  |cff999999rest 6:20|r	|cff999999OOM|r |cff16c3f240s|r |cffffaa33v|r  |cff999999rest 6:20|r	|cff999999OOM|r |cff16c3f240s|r |cffffaa33v|r  |cff999999rest 6:20|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight39	|cff999999OOM|r |cffffaa3340s|r |cffffaa33v|r  |cff999999rest 6:45|r	|cff999999OOM|r |cff16c3f240s|r |cffffaa33v|r  |cff999999rest 6:45|r	|cff999999OOM|r |cff16c3f240s|r |cffffaa33v|r  |cff999999rest 6:45|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight42	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:05|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:05|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:05|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight45	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:25|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:25|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:25|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight48	|cff999999OOM|r |cffffaa3330s|r |cffffaa33v|r  |cff999999rest 7:25|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:25|r	|cff999999OOM|r |cff16c3f230s|r |cffffaa33v|r  |cff999999rest 7:25|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight51	|cff999999OOM|r |cffffaa3325s|r |cffffaa33v|r  |cff999999rest 7:50|r	|cff999999OOM|r |cff16c3f225s|r |cffffaa33v|r  |cff999999rest 7:50|r	|cff999999OOM|r |cff16c3f225s|r |cffffaa33v|r  |cff999999rest 7:50|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight54	|cff999999OOM|r |cffffaa3320s|r |cff999999=|r  |cff999999rest 8:10|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r  |cff999999rest 8:10|r	|cff999999OOM|r |cff16c3f220s|r |cff999999=|r  |cff999999rest 8:10|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight57	|cff999999OOM|r |cffffaa3320s|r |cffffaa33v|r  |cff999999rest 8:35|r	|cff999999OOM|r |cff16c3f220s|r |cffffaa33v|r  |cff999999rest 8:35|r	|cff999999OOM|r |cff16c3f220s|r |cffffaa33v|r  |cff999999rest 8:35|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fight60	|cff999999OOM|r |cffffaa3320s|r |cffffaa33v|r  |cff999999rest 8:30|r	|cff999999OOM|r |cff16c3f220s|r |cffffaa33v|r  |cff999999rest 8:30|r	|cff999999OOM|r |cff16c3f220s|r |cffffaa33v|r  |cff999999rest 8:30|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
tip-fight#1	ClearLines
tip-fight#2	AddLine	SpellTuner
tip-fight#3	AddDoubleLine	Time to OOM (raw)	19s +- 4s	1	1	1	1	1	1
tip-fight#4	AddDoubleLine	Full if you stop casting	512s	1	1	1	1	1	1
tip-fight#5	AddDoubleLine	Net rate (pessimistic)	-95 mana/s	1	1	1	1	1	1
tip-fight#6	AddDoubleLine	Spending	78 +- 21 mana/s (14 casts, CV 0.28)	1	1	1	1	1	1
tip-fight#7	AddDoubleLine	Regen now / projected	5 / 5 mana/s  (5SR 100% of time)	1	1	1	1	1	1
tip-fight#8	AddDoubleLine	Regen out of 5SR / casting	10 / 5 mana/s	1	1	1	1	1	1
tip-fight#9	AddDoubleLine	Spirit / gear mp5	~35 / ~14	1	1	1	1	1	1
tip-fight#10	AddDoubleLine	Spirit regen resumes	3.0s	1	0.670	0.200	1	1	1
tip-fight#11	AddLine	 
tip-fight#12	AddDoubleLine	Innervate	671 mana -> OOM 27s	0.780	0.780	0.780	0.310	0.660	0.940
tip-fight#13	AddLine	 
tip-fight#14	AddLine	Click: dashboard   Shift-click: reset window	0.500	0.500	0.500
tip-fight#15	Show
tip-fight#regen-same	true
fast3	|cffff4444OOM 15s vv|r  |cff999999rest 9:15|r	|cffff4444OOM 15s vv|r  |cff999999rest 9:15|r	|cffff4444OOM 15s vv|r  |cff999999rest 9:15|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fast6	|cffff4444OOM 10s vv|r  |cff999999rest 9:40|r	|cffff4444OOM 10s vv|r  |cff999999rest 9:40|r	|cffff4444OOM 10s vv|r  |cff999999rest 9:40|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fast9	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r	|cffff4444OOM 10s vv|r  |cff999999rest >10m|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fast12	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fast15	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r	|cffff4444OOM 5s vv|r  |cff999999rest >10m|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fast18	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fast21	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fast24	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	Regen: |cffffffff25|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r	Regen: |cff16c3f225|r |cffffaa33(5SR)|r
fast27	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	Regen: |cffffffff50|r	Regen: |cff16c3f250|r	Regen: |cff16c3f250|r
fast30	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	|cffff4444OOM 0s vv|r  |cff999999rest >10m|r	Regen: |cffffffff50|r	Regen: |cff16c3f250|r	Regen: |cff16c3f250|r
regen4	|cff999999OOM >0s =|r  |cff999999rest 35s|r	|cff999999OOM >0s =|r  |cff999999rest 35s|r	|cff999999OOM >0s =|r  |cff999999rest 35s|r	Regen: |cffffffff1000|r	Regen: |cff16c3f21000|r	Regen: |cff16c3f21000|r
regen8	|cff999999OOM >0s =|r  |cff999999rest 35s|r	|cff999999OOM >0s =|r  |cff999999rest 35s|r	|cff999999OOM >0s =|r  |cff999999rest 35s|r	Regen: |cffffffff1000|r	Regen: |cff16c3f21000|r	Regen: |cff16c3f21000|r
regen12	|cff999999OOM >0s =|r  |cff999999rest 35s|r	|cff999999OOM >0s =|r  |cff999999rest 35s|r	|cff999999OOM >0s =|r  |cff999999rest 35s|r	Regen: |cffffffff1000|r	Regen: |cff16c3f21000|r	Regen: |cff16c3f21000|r
regen16	|cff999999OOM >0s =|r  |cff999999rest 35s|r	|cff999999OOM >0s =|r  |cff999999rest 35s|r	|cff999999OOM >0s =|r  |cff999999rest 35s|r	Regen: |cffffffff1000|r	Regen: |cff16c3f21000|r	Regen: |cff16c3f21000|r
regen20	|cff999999FULL|r |cff33ff663:00|r	|cff999999FULL|r |cff16c3f23:00|r	|cff999999FULL|r |cff16c3f23:00|r	Regen: |cffffffff1000|r	Regen: |cff16c3f21000|r	Regen: |cff16c3f21000|r
regen24	|cff999999FULL|r |cff33ff662:00|r	|cff999999FULL|r |cff16c3f22:00|r	|cff999999FULL|r |cff16c3f22:00|r	Regen: |cffffffff1000|r	Regen: |cff16c3f21000|r	Regen: |cff16c3f21000|r
left	|cff999999FULL|r |cff33ff6635s|r	|cff999999FULL|r |cff16c3f235s|r	|cff999999FULL|r |cff16c3f235s|r	Regen: |cffffffff1000|r	Regen: |cff16c3f21000|r	Regen: |cff16c3f21000|r
left6s	|cff999999FULL|r |cff33ff6635s|r	|cff999999FULL|r |cff16c3f235s|r	|cff999999FULL|r |cff16c3f235s|r	Regen: |cffffffff1000|r	Regen: |cff16c3f21000|r	Regen: |cff16c3f21000|r
tip-after#1	ClearLines
tip-after#2	AddLine	SpellTuner
tip-after#3	AddDoubleLine	Time to full (raw)	35s	1	1	1	1	1	1
tip-after#4	AddDoubleLine	Net rate (pessimistic)	+86 mana/s	1	1	1	1	1	1
tip-after#5	AddDoubleLine	Spending	62 +- 12 mana/s (11 casts, CV 0.21)	1	1	1	1	1	1
tip-after#6	AddDoubleLine	Regen now / projected	200 / 161 mana/s  (5SR 48% of time)	1	1	1	1	1	1
tip-after#7	AddDoubleLine	Regen out of 5SR / casting	200 / 120 mana/s	1	1	1	1	1	1
tip-after#8	AddDoubleLine	Spirit / gear mp5	~571 / ~428	1	1	1	1	1	1
tip-after#9	AddLine	 
tip-after#10	AddDoubleLine	Innervate	9915 mana, ready	0.780	0.780	0.780	0.310	0.660	0.940
tip-after#11	AddLine	 
tip-after#12	AddLine	Click: dashboard   Shift-click: reset window	0.500	0.500	0.500
tip-after#13	Show
tip-after#regen-same	true
nomana	|cff999999FULL|r |cff33ff6635s|r	|cff999999FULL|r |cff16c3f235s|r	|cff999999FULL|r |cff16c3f235s|r	Regen: |cffffffff--|r	Regen: |cff16c3f2--|r	Regen: |cff16c3f2--|r
throttle	1,1,1,2
clicks	toggles=2	resets=2	chat=|cff9966ffSpellTuner:|r spend window reset. / |cff9966ffSpellTuner:|r spend window reset.
]=]
