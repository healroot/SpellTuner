-- Integrations/Surface_LDB.lua (T97, docs/SPEC-next.md 6.2; R-ellesmere.md
-- 3.1-3.2): the LibDataBroker SURFACE of the feeds (UI/Feeds.lua), on both
-- main TOCs, after UI/Feeds.lua.
--
-- Two LibDataBroker-1.1 data objects, whatever broker display the user runs:
-- EllesmereUI's DataBars ("Broker Plugin" block) on Forever, Titan Panel,
-- ChocolateBar or ElvUI's own "Data Broker" list on TBC.
--   "SpellTuner"        -- the `clock` feed's words, plain: "~OOM 1:20  rest
--                          2:10" (Forever), "OOM 1:20 v" (TBC); T114: Line's
--                          slots (MD.ClockLook().texts.line). db.feeds.compact
--                          drops the secondary segment (rest / a cooldown; T114:
--                          both Right slots, whatever they hold) for a narrow bar; the honesty marks (~ > = -- ...) and
--                          the label stay, so the words still say what is
--                          meant. The icon tint carries the tone, because a
--                          broker display may strip colour codes (DataBars
--                          does by default) but honours iconR/G/B.
--   "SpellTuner Regen"  -- the `regen` feed, plain: "Regen 123", "Regen 123
--                          (5SR)", "Regen ~123" when it is the last plain
--                          reading, "Regen --" before one. Amber inside the
--                          five-second rule.
-- Both: the minimap button's icon; left-click the window, right-click
-- Settings, out of combat only (MD.Feeds.Click, decision 17); the tooltip
-- through OnTooltipShow (the display anchors and skins the GameTooltip; never
-- OnEnter, which would hand the whole tooltip to us), filled by MD.Tip:Render
-- with the feed's lines and the click hints.
--
-- The library is BORROWED: LibStub's LibDataBroker-1.1, which a host loaded
-- (EllesmereUI ships it in its parent addon; so do ElvUI and Titan). Nothing is
-- shipped and nothing is published without a host (CLAUDE.md "no libraries").
-- Created at MD_READY (every addon has loaded by PLAYER_LOGIN), again on a
-- later ADDON_LOADED for a host that came late; a display that binds later
-- finds the objects by name (GetDataObjectByName) -- a second NewDataObject is
-- never attempted, and a name another addon already holds is left to it.
-- Updated from MD:OnTick (registered at MD_READY, so after the state moved);
-- the library drops an equal write, so a display repaints only on a change.
--
-- MD.Integrations (this file, both TOCs): what was found, for Settings ->
-- General -> INTEGRATIONS (T102 shows Lines()) and /st dump (one line through
-- MD:AddDumpLine, registered only once something was found, so a dump with no
-- host is byte-identical).
--
-- Host addons are reached only from Integrations/ (apicheck rule 11). Every
-- string here is ASCII with no bare pipe; the broker text carries no colour
-- code at all. Nothing in this file registers an event on a frame of its own
-- (MD:On / MD:OnTick, apicheck rule 9).
local _, MD = ...

-- The settings this file reads (docs/SPEC-next.md 6.3). `elvui` is the
-- ElvUI surface's switch, declared with its two siblings as the spec groups
-- them; Integrations/Surface_ElvUI.lua registers its datatexts at file load,
-- before any setting exists, and does not read it yet (task file, deviations).
MD:RegisterDefaults({ feeds = { ldb = true, elvui = true, compact = false } })

MD.Surfaces = MD.Surfaces or {}

local LDBS = {}
MD.SurfaceLDB = LDBS

LDBS.ICON = "Interface\\Icons\\Spell_Shadow_Manaburn" -- the minimap button's
LDBS.KEYS = { "clock", "regen" }
LDBS.NAMES = { clock = "SpellTuner", regen = "SpellTuner Regen" }

local objects = {}  -- feed key -> our data object
local taken = {}    -- feed key -> true: the name was another addon's
local tickOn = false
local ready = false

--------------------------------------------------------------------------------
-- The words
--------------------------------------------------------------------------------
local function Settings()
    local f = MD.db and MD.db.feeds
    if type(f) == "table" then return f end
    return {}
end

-- The look the broker draws the face with: the line's own clock look when a
-- file provides one (MD.ClockLook(), the user's clock settings: the rest
-- switch, T98 / T102), else every segment the face carries; compact drops the
-- secondary whatever the look says. T114: Line's slots (look.texts.line, the
-- contract T116's resolver fulfils) when present, so the broker says what the
-- datatext says whatever layout is on screen.
local function Look(compact)
    local look
    if type(MD.ClockLook) == "function" then
        local okL, l = pcall(MD.ClockLook)
        if okL and type(l) == "table" then look = l end
    end
    local show = { rest = true, cd = true }
    if look and type(look.show) == "table" then
        show.rest = look.show.rest ~= false
        show.cd = look.show.cd ~= false
    end
    if compact then show.rest, show.cd = false, false end
    local text
    if look and type(look.texts) == "table" and type(look.texts.line) == "table" then text = look.texts.line end
    return { show = show, text = text }
end

local function UsesMana()
    return not (MD.player and MD.player.usesMana == false)
end

-- The clock's words, plain: the face cut into its segments and joined
-- (Engine/ClockFace.lua -- LineString's words without a colour code). The
-- feed's label before a face exists, and for a character with no mana pool
-- (no clock is shown for one, F3).
function LDBS.ClockText(compact)
    local Feeds, CF = MD.Feeds, MD.ClockFace
    if not (Feeds and CF and CF.Segments and CF.JoinSegments) then return LDBS.NAMES.clock end
    if not UsesMana() then return LDBS.NAMES.clock end
    local face = Feeds.Face("clock")
    if not face then return LDBS.NAMES.clock end
    local okS, text = pcall(function()
        local segs = CF.Segments(face, Look(compact))
        -- compact drops both Right slots (T114), whatever kind they hold
        if compact and type(segs) == "table" then segs.second, segs.right, segs.right2 = nil, nil, nil end
        return CF.JoinSegments(segs)
    end)
    if not okS or type(text) ~= "string" or text == "" then return LDBS.NAMES.clock end
    return text
end

function LDBS.RegenText()
    if not MD.Feeds then return "Regen --" end
    return MD.Feeds.Text("regen", { plain = true })
end

--------------------------------------------------------------------------------
-- The tint (iconR/G/B): the tone the clock would paint, as a colour.
--   FULL (full, out of combat, full now) -> the mana colour
--   a bound, a warm-up, no number, an unstable value -> muted
--   a point OOM value -> its band: crit (under 20 s) red, warn (under 60 s)
--   amber, otherwise white (the icon as it is drawn)
-- Regen: amber inside the five-second rule, white outside, muted with no
-- reading. Presentation only; the model is untouched.
--------------------------------------------------------------------------------
local FULL_MODE = { full = true, ooc = true, fullnow = true }

function LDBS.ClockTone(face)
    if type(face) ~= "table" then return "muted" end
    if face.mode == "fullnow" then return "mana" end
    if face.known ~= "point" or type(face.value) ~= "number" or face.unstable then return "muted" end
    if FULL_MODE[face.mode] then return "mana" end
    if face.tone == "crit" or face.tone == "warn" then return face.tone end
    return "normal"
end

function LDBS.RegenTone()
    local read = MD.Feeds and MD.Feeds.RegenReading
    local r = type(read) == "function" and read() or nil
    if not r then return "muted" end
    if r.fsr then return "warn" end
    return "normal"
end

local function RGB(tone)
    local CF = MD.ClockFace
    if CF and CF.ToneRGB then return CF.ToneRGB(tone) end
    return 1, 1, 1
end

-- What each object says now: text and tint.
local function State(key)
    local compact = Settings().compact == true
    if key == "clock" then
        local tone = "muted"
        if UsesMana() and MD.Feeds then tone = LDBS.ClockTone(MD.Feeds.Face("clock")) end
        return LDBS.ClockText(compact), tone
    end
    if not UsesMana() then return LDBS.RegenText(), "muted" end
    return LDBS.RegenText(), LDBS.RegenTone()
end
LDBS.State = State

--------------------------------------------------------------------------------
-- Click and tooltip
--------------------------------------------------------------------------------
local WHITE = { 1, 1, 1 }

function LDBS.TooltipLines(key)
    local lines = {}
    local src = MD.Feeds and MD.Feeds.Tooltip(key) or {}
    for i = 1, #src do lines[i] = src[i] end
    if #lines == 0 then lines[1] = { l = LDBS.NAMES[key] or "SpellTuner", c = "accent" } end
    lines[#lines + 1] = {}
    lines[#lines + 1] = { l = "Left-click", r = "open the window", c = "label", rc = WHITE }
    lines[#lines + 1] = { l = "Right-click", r = "Settings", c = "label", rc = WHITE }
    lines[#lines + 1] = { l = "(not in combat)", c = "muted" }
    return lines
end

local function Tooltip(key)
    return function(tt)
        if not tt then return end
        local lines = LDBS.TooltipLines(key)
        if MD.Tip and MD.Tip.Render then
            MD.Tip:Render(tt, lines)
        else
            for _, ln in ipairs(lines) do
                if ln.r ~= nil then tt:AddDoubleLine(ln.l or "", ln.r) else tt:AddLine(ln.l or " ") end
            end
        end
    end
end

local function Click(key)
    return function(_, button)
        if MD.Feeds then MD.Feeds.Click(key, button) end
    end
end

--------------------------------------------------------------------------------
-- Publishing
--------------------------------------------------------------------------------
-- LibStub's LibDataBroker-1.1, or nil (no LibStub, no library, a raise).
local function Lib()
    local LS = LibStub
    if type(LS) ~= "table" then return nil end
    local okG, get = pcall(function() return LS.GetLibrary end)
    if not okG or type(get) ~= "function" then return nil end
    local okL, lib = pcall(get, LS, "LibDataBroker-1.1", true)
    if not okL or type(lib) ~= "table" then return nil end
    if type(lib.NewDataObject) ~= "function" or type(lib.GetDataObjectByName) ~= "function" then return nil end
    return lib
end

-- Why nothing is published (for the INTEGRATIONS / dump line), or nil.
LDBS.why = nil

function LDBS.Update()
    if Settings().ldb == false then return end
    for _, key in ipairs(LDBS.KEYS) do
        local obj = objects[key]
        if obj then
            local text, tone = State(key)
            local r, g, b = RGB(tone)
            -- the library drops an equal write: a display hears only a change
            obj.text = text
            obj.iconR, obj.iconG, obj.iconB = r, g, b
        end
    end
end

local function Published()
    local names = {}
    for _, key in ipairs(LDBS.KEYS) do
        if objects[key] then names[#names + 1] = LDBS.NAMES[key] end
    end
    return names
end

function LDBS.Publish()
    if next(objects) ~= nil then return true end
    if Settings().ldb == false then LDBS.why = "off"; return false end
    if not MD.Feeds then LDBS.why = "no feeds"; return false end
    local lib = Lib()
    if not lib then LDBS.why = "no broker library"; return false end
    for _, key in ipairs(LDBS.KEYS) do
        local name = LDBS.NAMES[key]
        local okE, existing = pcall(lib.GetDataObjectByName, lib, name)
        if okE and existing ~= nil then
            taken[key] = true -- another addon's: never a second NewDataObject
        else
            local text, tone = State(key)
            local r, g, b = RGB(tone)
            local okN, obj = pcall(lib.NewDataObject, lib, name, {
                type = "data source", label = name, text = text, icon = LDBS.ICON,
                iconR = r, iconG = g, iconB = b,
                OnClick = Click(key), OnTooltipShow = Tooltip(key),
            })
            if okN and type(obj) == "table" then objects[key] = obj end
        end
    end
    local names = Published()
    if #names == 0 then
        LDBS.why = "names taken"
        return false
    end
    LDBS.why = nil
    MD.Surfaces.ldb = { objects = names }
    if not tickOn then
        tickOn = true
        MD:OnTick(LDBS.Update)
    end
    if MD.Integrations then MD.Integrations.Note() end
    return true
end

-- Our object for a feed key (a suite, the INTEGRATIONS pane), or nil.
function LDBS.Object(key) return objects[key] end

MD:RegisterCallback("MD_READY", function()
    ready = true
    LDBS.Publish()
    if MD.Surfaces.elvui and MD.Integrations then MD.Integrations.Note() end
end)

-- A host that loaded after us (load on demand): try once more.
MD:On("ADDON_LOADED", function()
    if ready and next(objects) == nil then LDBS.Publish() end
end)

--------------------------------------------------------------------------------
-- MD.Integrations: what was found, in one line each.
--   Lines()     the INTEGRATIONS pane's lines (T102 shows them):
--               "EllesmereUI 9.3.4 (tested 9.3.4): brokers SpellTuner +
--               SpellTuner Regen; mover SpellTuner clock", "ElvUI: 2
--               datatexts", "Broker: 2 objects", or "none found"
--   DumpLine()  /st dump's line: "integrations: EllesmereUI 9.3.4 (tested
--               9.3.4), skin apiVersion 2, brokers SpellTuner + SpellTuner
--               Regen, mover SpellTuner_Clock"
--   Note()      registers the dump line (once something was found)
-- The EllesmereUI parts are Integrations/EllesmereUI_Forever.lua's
-- (MD.EUI.PanePart / DumpParts), present on the Forever TOCs only.
--------------------------------------------------------------------------------
MD.Integrations = MD.Integrations or {}
local INT = MD.Integrations

function INT.BrokersText()
    local names = MD.Surfaces.ldb and MD.Surfaces.ldb.objects
    if names and #names > 0 then return "brokers " .. table.concat(names, " + ") end
    if LDBS.why == "off" then return "brokers off" end
    if LDBS.why == "names taken" then return "brokers: names taken by another addon" end
    return "brokers: no broker library"
end

local function ElvUIDatatexts()
    local e = MD.Surfaces.elvui
    return e and e.datatexts and #e.datatexts or 0
end

function INT.Lines()
    local out = {}
    local eui = MD.EUI and MD.Surfaces.eui
    if eui then out[#out + 1] = MD.EUI.PanePart(INT.BrokersText()) end
    local n = ElvUIDatatexts()
    if n > 0 then out[#out + 1] = string.format("ElvUI: %d datatexts", n) end
    local names = MD.Surfaces.ldb and MD.Surfaces.ldb.objects
    if not eui and names and #names > 0 then
        out[#out + 1] = string.format("Broker: %d objects", #names)
    end
    if #out == 0 then out[1] = "none found" end
    return out
end

function INT.DumpLine()
    local parts = {}
    local eui = MD.EUI and MD.Surfaces.eui
    if eui then
        for _, p in ipairs(MD.EUI.DumpParts(INT.BrokersText())) do parts[#parts + 1] = p end
    elseif MD.Surfaces.ldb then
        parts[#parts + 1] = INT.BrokersText()
    end
    local n = ElvUIDatatexts()
    if n > 0 then parts[#parts + 1] = string.format("ElvUI %d datatexts", n) end
    if #parts == 0 then parts[1] = "none found" end
    return "integrations: " .. table.concat(parts, ", ")
end

local noted = false
function INT.Note()
    if noted or not MD.AddDumpLine then return end
    noted = true
    MD:AddDumpLine("integrations", INT.DumpLine)
end
