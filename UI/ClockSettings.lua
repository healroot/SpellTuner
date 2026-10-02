-- T102 (docs/SPEC-next.md 5.4, 6.3, 7.3-7.4, section 11 row T102; mockups
-- M7b, M8f, M8g, M9d): the Settings join point, on both lines.
--
--   * Settings -> Clock (7.4): a view of its own in the Settings group (TBC
--     General, Clock, About; Forever General, Clock, Modules, About), built by
--     MD.ClockSettings.Build. Its PREVIEW is a separate frame drawn by
--     MD.ClockView.Build (UI/ClockView.lua), never the clock on screen, so the
--     single visibility owner of each line (CLAUDE.md) is never touched from
--     here. The state chips paint MD.ClockFace.SAMPLES -- the table
--     tools/clockfacecheck.lua and tools/clockui.lua render -- as this line
--     draws a face (Forever: the "~", one colour, "0:15", no arrow); (Live)
--     paints MD.ClockFace.Current every tick while the view is shown. LAYOUT
--     is one button per MD.ClockView.LAYOUTS (T104's ring joins the row when
--     it is drawn) and Reset to style; under them a level-3 box
--     (UI.CreateNavBox) with Colours, Frame, Bar, Show and When. A control
--     writes one override through MD.ClockView.Set (db.clockLook.over, read
--     only by the resolver), which fires CLOCK_LOOK: the line's clock and this
--     preview rebuild. Show and When hold the line's own switches (TBC
--     db.showRest / showCooldown / locked / widgetTooltip, Forever
--     db.clock.*), which each line's dashboard hands in (opts.show /
--     opts.when): a line's keys stay in that line's files (7.3 phase 1).
--     The swatch row (the tones, the style's tokens, the class colour, eight
--     fixed colours; no client call) is local to this file.
--   * The Look controls (5.4, M7b): the style dropdown (UI.Styles' keys; the
--     Ellesmere entry named by UI.Ellesmere.Label, "Ellesmere (following
--     EllesmereUI)" while it follows), "Use my class colour" (db.useClassColour,
--     registered here) and the honest reload line (decision 4): UI.Restyle's
--     "N windows finish changing after a reload: ..." with [Reload], while what
--     is painted differs from what the session logged in with AND T107 counts
--     something left (since the wave N4 integration nothing is, so it stays
--     hidden). Each line's APPEARANCE /
--     Windows pane places them.
--   * The INTEGRATIONS pane (6.3, M9d): MD.Integrations.Lines() (what was
--     found), the broker switches (db.feeds.ldb, db.feeds.compact) and a hint;
--     a line adds its own switches (the Forever EllesmereUI mover).
--   * The clock subcommands (7.4, 2.5) through MD:AddSubcommand: `/st clock
--     layout <name>`, `/st clock look reset`, `/st clock preview`. Forever's
--     `/st clock` and `/st clock lock` keep their meaning (a sub is matched
--     only on its own first word); on TBC, which had no `clock` verb, the subs
--     create `/md clock`.
--   * MD.ClockLook (MD:Provide): the line's resolved clock look, which
--     Integrations/Surface_LDB.lua follows so the broker drops the rest
--     segment when the clock does (2.3 "one string, every place").
--
-- "Use my class colour" overrides any style's accent (decision 3). UI/Styles.lua
-- (T103's this wave) applies a style through UI.ApplyStyleTokens; this file
-- wraps that applier, handing it the style with accent "class" while the
-- switch is on, and re-applies the active style through UI.Styles.Refresh when
-- it changes (one STYLE_CHANGED). Flat's accent is the class colour already,
-- so under Flat the switch changes nothing.
--
-- Client calls: GetTime (the preview's clock) and ReloadUI through MD.API.Call.
-- No secret is read: the Live preview's pool is drawn by the line's own `draw`
-- (Forever: MD.API.DrawUnitPower, never read back), everything else is the
-- face's plain fields. Every string drawn here is ASCII with no bare pipe.
local _, MD = ...
local UI = MD.UI

MD.ClockSettings = MD.ClockSettings or {}
local CS = MD.ClockSettings

-- decision 3: off -- each style keeps its own accent
MD:RegisterDefaults({ useClassColour = false })

--------------------------------------------------------------------------------
-- The look of SpellTuner's windows: the style, the class colour, the reload line
--------------------------------------------------------------------------------
function CS.ClassColour()
    return type(MD.db) == "table" and MD.db.useClassColour == true
end

-- The applier every style goes through (UI/Theme_Flat.lua), wrapped: the
-- class colour in place of the style's own accent while the switch is on.
local baseApply = UI.ApplyStyleTokens
if type(baseApply) == "function" then
    UI.ApplyStyleTokens = function(style)
        if CS.ClassColour() and type(style) == "table" and style.accent ~= "class" then
            style = setmetatable({ accent = "class" }, { __index = style })
        end
        return baseApply(style)
    end
end

local function ActiveStyle()
    local S = UI.Styles
    return S and S.Active and S.Active() or "flat"
end

-- What the session logged in with: the style and the accent painted then.
local login
local function Login()
    if not login then login = { style = ActiveStyle(), accent = UI.accentHex } end
    return login
end
MD:RegisterCallback("CORE_LOGIN", function()
    login = nil
    Login()
end)

-- CS.ReloadNeeded(): the windows built before a live switch keep some colours
-- set when they were made (T107 converts them) -- true while the style or the
-- accent painted differs from the login's.
function CS.ReloadNeeded()
    local l = Login()
    return ActiveStyle() ~= l.style or UI.accentHex ~= l.accent
end

-- CS.ReloadLine(): T107's count of what finishes after a reload
-- ("N windows finish changing after a reload: A, B"), nil when nothing is left.
function CS.ReloadLine()
    local R = UI.Restyle
    if not (R and type(R.Line) == "function") then return nil end
    local okL, line = pcall(R.Line)
    if okL and type(line) == "string" and line ~= "" then return line end
    return nil
end

function CS.Reload()
    MD.API.Call("ReloadUI")
end

local accentLine = false
local function NoteAccent()
    if accentLine or not CS.ClassColour() then return end
    accentLine = true
    MD:AddDumpLine("accent", function()
        return "accent: " .. (CS.ClassColour() and "your class colour (Use my class colour)" or "the style's")
    end)
end

-- CS.SetClassColour(on): saved, the active style applied again.
function CS.SetClassColour(on)
    if type(MD.db) ~= "table" then return false end
    MD.db.useClassColour = on and true or false
    NoteAccent()
    local S = UI.Styles
    if S and S.Refresh then S.Refresh(ActiveStyle()) end
    return true
end

-- The style dropdown's names: a style's own `name`, Ellesmere's from its
-- follow (UI.Ellesmere.Label: "Ellesmere (following EllesmereUI)" while a
-- getter source is there).
local LABEL = {
    ellesmere = function()
        local E = UI.Ellesmere
        if E and type(E.Label) == "function" then
            local okL, text = pcall(E.Label)
            if okL and type(text) == "string" then return text end
        end
    end,
}

function CS.LookItems()
    local items = {}
    local S = UI.Styles
    if not (S and S.Keys) then return items end
    for _, key in ipairs(S.Keys()) do
        local s = S.Get(key)
        local text = (LABEL[key] and LABEL[key]()) or (s and s.name) or key
        items[#items + 1] = { id = key, text = text, tooltip = s and s.hint or nil }
    end
    return items
end

-- CS.SetLook(key) -> true | false, why: UI.SetStyle (saved, repainted at once).
function CS.SetLook(key)
    if type(UI.SetStyle) ~= "function" then return false, "no styles" end
    local okS, done, why = pcall(UI.SetStyle, key)
    if not okS then return false, tostring(done) end
    return done, why
end

local lookControls = setmetatable({}, { __mode = "k" })

local function RefreshLook(c)
    local key = ActiveStyle()
    c.dropdown:SetItems(CS.LookItems())
    c.dropdown:SetValue(key)
    c.classCheck:SetChecked(CS.ClassColour())
    -- T107 (wave N4 integration): shown only while something finishes after a
    -- reload (UI.Restyle.Line, nil once nothing is left), with that line as its text
    local line = CS.ReloadNeeded() and CS.ReloadLine() or nil
    if line then
        c.reloadText:SetText(line)
        c.reload:Show()
    else
        c.reload:Hide()
    end
end

-- CS.LookControls(parent, ddWidth) -> { label, dropdown, classCheck, reload,
-- reloadText, reloadButton, Refresh }. The caller places label (the dropdown
-- hangs right of it), classCheck and reload.
function CS.LookControls(parent, ddWidth)
    local c = {}
    c.label = parent:CreateFontString(nil, "OVERLAY", UI.FONT)
    c.label:SetText("Look")
    c.dropdown = UI.CreateDropdown(parent, ddWidth or 170, 18, function(id)
        CS.SetLook(id)
    end)
    c.dropdown:SetPoint("LEFT", c.label, "RIGHT", 8, 0)
    c.classCheck = UI.CreateCheckButton(parent, "Use my class colour", function(checked)
        CS.SetClassColour(checked)
    end, "Use my class colour", "Your class colour as the accent, whatever the look.",
        "Off: each look keeps its own (Flat's is your class colour already).")

    c.reload = CreateFrame("Frame", nil, parent)
    c.reload:SetHeight(18)
    c.reloadText = c.reload:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    c.reloadText:SetPoint("LEFT", c.reload, "LEFT", 0, 0)
    c.reloadText:SetJustifyH("LEFT")
    c.reloadText:SetTextColor(UI.RGB("muted"))
    c.reloadText:SetText("Some windows finish changing after a reload")
    c.reloadButton = UI.CreateButton(c.reload, "Reload", "accent-hover", { 56, 16 }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL, "Reload", "Reloads the interface now.")
    c.reloadButton:SetPoint("LEFT", c.reloadText, "RIGHT", 6, 0)
    c.reloadButton:SetScript("OnClick", CS.Reload)
    c.reload:Hide()

    function c:Refresh() RefreshLook(c) end
    lookControls[c] = true
    RefreshLook(c)
    return c
end

--------------------------------------------------------------------------------
-- INTEGRATIONS (6.3): what was found, the broker switches, a hint
--------------------------------------------------------------------------------
local MAX_LINES = 4

local function FeedsDB()
    if type(MD.db) ~= "table" then return {} end
    if type(MD.db.feeds) ~= "table" then MD.db.feeds = {} end
    return MD.db.feeds
end

function CS.IntegrationLines()
    local INT = MD.Integrations
    if INT and type(INT.Lines) == "function" then
        local okL, lines = pcall(INT.Lines)
        if okL and type(lines) == "table" and #lines > 0 then return lines end
    end
    return { "none found" }
end

-- The hint under the switches: where the brokers show, for what was found.
function CS.IntegrationHint()
    local surf = MD.Surfaces or {}
    local elv = surf.elvui and surf.elvui.datatexts and #surf.elvui.datatexts or 0
    local brokers = surf.ldb and surf.ldb.objects and #surf.ldb.objects or 0
    if surf.eui then return "Add them in /eui -> DataBars -> a Broker Plugin block." end
    if elv > 0 and brokers > 0 then return "In ElvUI pick SpellTuner, not LDB: SpellTuner - both read the same." end
    if brokers > 0 then return "A broker display (Titan Panel, ChocolateBar) lists them." end
    return "Brokers show in a display addon: EllesmereUI's DataBars, Titan Panel, ElvUI."
end

local function Switch(parent, def)
    local cb = UI.CreateCheckButton(parent, def.text, function(checked)
        def.set(checked and true or false)
        if def.after then def.after(checked) end
    end, def.tips and def.tips[1], def.tips and def.tips[2], def.tips and def.tips[3])
    cb.def = def
    return cb
end

local function RefreshIntegrations(sec)
    local lines = CS.IntegrationLines()
    local prev
    for i = 1, MAX_LINES do
        local fs = sec.found[i]
        if lines[i] then
            fs:SetText(lines[i])
            fs:Show()
            prev = fs
        else
            fs:SetText("")
            fs:Hide()
        end
    end
    sec.checkRow:ClearAllPoints()
    sec.checkRow:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", -5, -6)
    sec.checkRow:SetPoint("RIGHT", sec, "RIGHT", 0, 0)
    for _, cb in ipairs(sec.switches) do
        cb:SetChecked(cb.def.get())
        local shown = cb.def.shown == nil or cb.def.shown()
        if shown then cb:Show() else cb:Hide() end
    end
    sec.hint:SetText(CS.IntegrationHint())
end

-- CS.BuildIntegrations(parent, width, height, extra) -> a titled pane with
-- :Refresh(). `extra` (optional): the line's own switches, each { text, get,
-- set, tips, shown }, laid under the two broker switches.
function CS.BuildIntegrations(parent, width, height, extra)
    local sec = UI.CreateTitledPane(parent, "INTEGRATIONS", width, height)
    sec.integrations = true -- marks this pane for tools/clocksettings.lua
    sec.found = {}
    for i = 1, MAX_LINES do
        local fs = sec:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        if i == 1 then
            fs:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -25)
        else
            fs:SetPoint("TOPLEFT", sec.found[i - 1], "BOTTOMLEFT", 0, -2)
        end
        fs:SetPoint("RIGHT", sec, "RIGHT", -2, 0)
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(UI.RGB("label"))
        sec.found[i] = fs
    end

    sec.checkRow = CreateFrame("Frame", nil, sec)
    sec.checkRow:SetHeight(14)
    local ldb = Switch(sec, {
        text = "Publish brokers",
        tips = { "Publish broker objects", "SpellTuner and SpellTuner Regen for a broker display",
                 "(EllesmereUI's DataBars, Titan Panel, ElvUI). Off: after a reload, none." },
        get = function() return FeedsDB().ldb ~= false end,
        set = function(on) FeedsDB().ldb = on end,
    })
    ldb:SetPoint("TOPLEFT", sec.checkRow, "TOPLEFT", 5, 0)
    local compact = Switch(sec, {
        text = "Compact broker text",
        tips = { "Compact broker text", "The clock's words without the rest segment,",
                 "for a narrow bar. The ~ and the label stay." },
        get = function() return FeedsDB().compact == true end,
        set = function(on) FeedsDB().compact = on end,
    })
    compact:SetPoint("LEFT", ldb, "LEFT", math.floor((width - 10) / 2), 0)
    sec.switches = { ldb, compact }
    sec.ldbCheck, sec.compactCheck = ldb, compact

    local prev = ldb
    for _, def in ipairs(extra or {}) do
        local cb = Switch(sec, def)
        cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)
        sec.switches[#sec.switches + 1] = cb
        prev = cb
    end

    sec.hint = sec:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    sec.hint:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6)
    sec.hint:SetPoint("RIGHT", sec, "RIGHT", -2, 0)
    sec.hint:SetJustifyH("LEFT")
    sec.hint:SetTextColor(UI.RGB("muted"))

    function sec:Refresh() RefreshIntegrations(sec) end
    RefreshIntegrations(sec)
    return sec
end

--------------------------------------------------------------------------------
-- The line's look for the broker: Integrations/Surface_LDB.lua's MD.ClockLook
--------------------------------------------------------------------------------
MD:Provide("ClockLook", function()
    local W = MD.ClockWidget
    local v = W and W.view
    return v and v.look or nil
end)

--------------------------------------------------------------------------------
-- Settings -> Clock: the preview
--------------------------------------------------------------------------------
-- The chips, in the order 7.4 draws them: (Live), then SAMPLES by key.
CS.CHIPS = { "live", "oom", "crit", "bound", "hold", "warmup", "full", "rest", "ooc" }
CS.SAMPLE_POOL = 0.6   -- the preview's illustrative fill for the pool and the model
CS.SAMPLE_FSR = 3      -- seconds left in the five-second rule in a sample fight
CS.GROUND = { dark = { 0.05, 0.05, 0.05, 1 }, light = { 0.72, 0.72, 0.72, 1 } }

local DEFAULT_FACTS = { source = "none", labelSample = "FULL", show = {} }

-- The line's facts (UI/Widget.lua's or UI/Clock_Forever.lua's, T98).
local function Facts()
    local W = MD.ClockWidget
    return (W and type(W.facts) == "table") and W.facts or DEFAULT_FACTS
end

local function Sample(key)
    for _, s in ipairs(MD.ClockFace and MD.ClockFace.SAMPLES or {}) do
        if s.key == key then return s end
    end
end

local function Copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and Copy(v) or v end
    return out
end

-- CS.SampleFace(key, facts) -> a SAMPLES face as this line draws one: on a
-- line with a modelled pool (Forever) the "~", one colour, "0:15" and no
-- arrow (it keeps no trend), the model's illustrative pct.
function CS.SampleFace(key, facts)
    local s = Sample(key)
    if not s then return nil end
    local f = Copy(s.face)
    facts = facts or Facts()
    if facts.model then
        f.modelled, f.mono, f.timeFmt, f.arrow, f.unstable = true, true, "mss", nil, false
        if f.pct == nil then f.pct = CS.SAMPLE_POOL end
    end
    return f
end

function CS.ChipName(key)
    if key == "live" then return "(Live)" end
    local s = Sample(key)
    return s and s.name or key
end

local sampleFsr = 0
local SAMPLE_DRAW = {
    pool = function(b)
        b:SetMinMaxValues(0, 1)
        b:SetValue(CS.SAMPLE_POOL)
    end,
    fsr = function() return sampleFsr end,
}

-- The line's own bar sources (the pool it draws, its five-second rule).
local function LiveDraw()
    local W = MD.ClockWidget
    local v = W and W.view
    return v and type(v.draw) == "table" and v.draw or SAMPLE_DRAW
end

local function LiveFace()
    local CF = MD.ClockFace
    if not (CF and type(CF.Current) == "function") then return nil end
    local okF, face = pcall(CF.Current, GetTime())
    if okF and type(face) == "table" then return face end
    return nil
end

local panes = setmetatable({}, { __mode = "k" })

-- The look the preview draws with: the line's resolved one (the layout, the
-- style's clock role, the overrides), its switches as the line has them now.
local function PreviewLook(p)
    local look = MD.ClockView.Look(Facts())
    p.look = look
    return look
end

-- The segments the line shows: its facts (refreshed at the line's own paint),
-- then the line's own switches read now -- a Show switch carrying `segment`
-- ("rest" / "cd") -- so the preview follows a click at once.
local function SyncShow(p, look)
    local show = Facts().show or {}
    look.show = look.show or {}
    look.show.rest, look.show.cd = show.rest, show.cd
    for _, def in ipairs(p.opts and p.opts.show or {}) do
        if def.segment and type(def.get) == "function" then look.show[def.segment] = def.get() and true or false end
    end
end

-- Paint the preview: the chip's face (or the live one) in the resolved look.
function CS.PaintPreview(p)
    local v = p and p.view
    if not v then return end
    local look = p.look or PreviewLook(p)
    SyncShow(p, look)
    local face
    if p.chip == "live" then
        v.draw = LiveDraw()
        face = LiveFace()
    else
        v.draw = SAMPLE_DRAW
        face = CS.SampleFace(p.chip)
        sampleFsr = (face and face.combat) and CS.SAMPLE_FSR or 0
    end
    v:Paint(face, look)
    v:PaintBar(GetTime())
    p.face = face
end

--------------------------------------------------------------------------------
-- Settings -> Clock: the swatch row
--------------------------------------------------------------------------------
CS.FIXED = { "ffffff", "bfbfbf", "000000", "ff3333", "ff8000", "ffd100", "00ccff", "b266ff" }
local TONES = { "crit", "warn", "normal", "good", "muted", "mana" }
local TOKENS = { "accent", "text", "label", "muted", "mana", "good", "bad" }

local function HexOf(code)
    if type(code) ~= "string" then return nil end
    local h = code:match("^|c[fF][fF](%x%x%x%x%x%x)$") or code:match("^(%x%x%x%x%x%x)$")
    return h and h:lower() or nil
end

-- CS.Swatches() -> { { name, hex } }: the tones, the style's tokens, the class
-- colour, eight fixed colours -- read now (a style changes the tokens).
function CS.Swatches()
    local out = {}
    local CF = MD.ClockFace
    for _, t in ipairs(TONES) do
        local h = CF and CF.HEX and HexOf(CF.HEX[t])
        if h then out[#out + 1] = { name = "tone: " .. t, hex = h } end
    end
    for _, t in ipairs(TOKENS) do
        local tok = UI.TEXT[t]
        local h = tok and HexOf(tok.hex)
        if h then out[#out + 1] = { name = "style: " .. t, hex = h } end
    end
    local class = HexOf(UI.classAccentHex)
    if class then out[#out + 1] = { name = "your class colour", hex = class } end
    for _, h in ipairs(CS.FIXED) do out[#out + 1] = { name = h, hex = h } end
    return out
end

function CS.RGB(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255
end

local SWATCH = 12

local function PaintSwatches(row)
    local list = CS.Swatches()
    for i, b in ipairs(row.swatches) do
        local s = list[i]
        if s then
            b.hex, b.name = s.hex, s.name
            b.tex:SetColorTexture(CS.RGB(s.hex))
            UI.SetTooltips(b, "ANCHOR_TOPLEFT", 0, 3, s.name, s.hex)
            b:Show()
        else
            b:Hide()
        end
    end
end

-- A row of swatches; a click hands onPick the hex ("rrggbb"); the last
-- button ("x", style) hands it nil: back to the style's.
local function SwatchRow(parent, onPick)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(SWATCH + 2)
    row.swatches = {}
    local n = #CS.Swatches()
    for i = 1, n do
        local b = CreateFrame("Button", nil, row, "BackdropTemplate")
        b:SetSize(SWATCH, SWATCH)
        b:SetPoint("LEFT", row, "LEFT", (i - 1) * (SWATCH + 2), 0)
        UI.Skin(b, "field", "field", "border")
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        b.tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        b:SetScript("OnClick", function(self) onPick(self.hex) end)
        row.swatches[i] = b
    end
    local reset = UI.CreateButton(row, "style", "accent-hover", { 40, SWATCH + 2 }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL, "Back to the style's", "This setting follows the look again.")
    reset:SetPoint("LEFT", row, "LEFT", n * (SWATCH + 2) + 4, 0)
    reset:SetScript("OnClick", function() onPick(nil) end)
    row.reset = reset
    row:SetWidth(n * (SWATCH + 2) + 48)
    PaintSwatches(row)
    return row
end

--------------------------------------------------------------------------------
-- Settings -> Clock: the tabs of the level-3 box
--------------------------------------------------------------------------------
local ROW = 22
local LABEL_W = 112

local function RowLabel(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    fs:SetWidth(LABEL_W - 4)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function Note(parent, text, anchor, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    fs:SetPoint("TOPLEFT", anchor or parent, anchor and "BOTTOMLEFT" or "TOPLEFT", 0, y or 0)
    fs:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(UI.RGB("muted"))
    fs:SetText(text)
    return fs
end

local function Set(key, value)
    return MD.ClockView.Set(key, value)
end

local function Rgba(hex, a)
    if not hex then return nil end
    local r, g, b = CS.RGB(hex)
    return { r, g, b, a or 1 }
end

local TONE_LABEL = {
    crit = "Crit (under 20 s)", warn = "Warn (under 60 s)", normal = "Normal",
    good = "Good (FULL)", muted = "Muted", mana = "Mana cooldown",
}

local BAR_COLOURS = {
    { id = "source", text = "By source" }, { id = "tone", text = "By tone" }, { id = "class", text = "Class colour" },
    { id = "fixed", text = "A swatch" },
}

local TAB = {}

TAB.colours = function(p, f)
    local y = -2
    p.toneRows = {}
    for _, tone in ipairs(TONES) do
        RowLabel(f, TONE_LABEL[tone], y - 1)
        local row = SwatchRow(f, function(hex) Set("colors." .. tone, hex) end)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_W, y)
        p.toneRows[tone] = row
        y = y - ROW
    end
    RowLabel(f, "Bar colour", y - 3)
    local dd = UI.CreateDropdown(f, 110, 18, function(id)
        if id ~= "fixed" then Set("bar.color", id) end
    end)
    dd:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_W, y)
    dd:SetItems(BAR_COLOURS)
    p.barColour = dd
    local row = SwatchRow(f, function(hex)
        Set("bar.color", hex and Rgba(hex) or nil)
    end)
    row:SetPoint("LEFT", dd, "RIGHT", 8, 0)
    p.barColourRow = row
    y = y - ROW
    RowLabel(f, "Bar background", y - 1)
    local back = SwatchRow(f, function(hex) Set("bar.back", Rgba(hex)) end)
    back:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_W, y)
    p.barBackRow = back
end

TAB.frame = function(p, f)
    local y = -2
    RowLabel(f, "Background", y - 1)
    p.fillRow = SwatchRow(f, function(hex)
        local a = (p.look and p.look.panel and UI.SkinColour(p.look.panel.fill) or {})[4] or 1
        Set("panel.fill", hex and Rgba(hex, a) or nil)
    end)
    p.fillRow:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_W, y)
    y = y - ROW - 12
    local alpha = UI.CreateSlider("Background alpha", f, 0, 100, 160, 5, nil, function(value)
        local c = p.look and p.look.panel and UI.SkinColour(p.look.panel.fill) or { 0, 0, 0, 1 }
        Set("panel.fill", { c[1], c[2], c[3], (tonumber(value) or 100) / 100 })
    end, true, "Background alpha", "0 %: no background, only the words and the bar.")
    alpha:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_W + 2, y)
    p.alphaSlider = alpha
    y = y - 40
    RowLabel(f, "Border", y - 1)
    p.edgeRow = SwatchRow(f, function(hex) Set("panel.edge", Rgba(hex)) end)
    p.edgeRow:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_W, y)
    local none = UI.CreateButton(f, "none", "accent-hover", { 40, SWATCH + 2 }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL, "No border", "The clock without its edge.")
    none:SetPoint("LEFT", p.edgeRow, "RIGHT", 4, 0)
    none:SetScript("OnClick", function() Set("panel.edge", { 0, 0, 0, 0 }) end)
    p.edgeNone = none
    y = y - ROW
    Note(f, "The size follows the layout; the place is the clock's own (drag it, or Reset place).", nil, y - 4)
end

local SOURCE_TEXT = {
    pool = "Your mana", model = "Modelled mana", time = "Time to OOM", fsr = "Five-second rule", none = "None",
}

local function SourceItems(p)
    local items = {}
    local facts = Facts()
    local layout = p.look and p.look.layout or "line"
    for _, s in ipairs(MD.ClockView.SOURCES or {}) do
        if MD.ClockView.SourceOK(layout, s, facts) then
            items[#items + 1] = { id = s, text = SOURCE_TEXT[s] or s }
        end
    end
    return items
end

TAB.bar = function(p, f)
    local y = -2
    RowLabel(f, "Source", y - 3)
    local dd = UI.CreateDropdown(f, 140, 18, function(id) Set("bar.source", id) end)
    dd:SetPoint("TOPLEFT", f, "TOPLEFT", LABEL_W, y)
    p.sourceDropdown = dd
    y = y - ROW - 4
    local spark = UI.CreateCheckButton(f, "Spark: the five-second rule", function(checked)
        Set("bar.spark", checked and "fsr" or "none")
    end, "Spark", "A yellow mark sweeping the bar over the five seconds after a spend,",
        "on whatever the bar shows.")
    spark:SetPoint("TOPLEFT", f, "TOPLEFT", 2, y)
    p.sparkCheck = spark
    y = y - ROW - 18
    local height = UI.CreateSlider("Height", f, 2, 24, 140, 1, nil, function(value)
        Set("bar.height", tonumber(value))
    end, false, "Bar height", "2 to 24 pixels; the Line layout grows to hold it.")
    height:SetPoint("TOPLEFT", f, "TOPLEFT", 4, y)
    p.heightSlider = height
    local horizon = UI.CreateSlider("Horizon (s)", f, 60, 600, 140, 30, nil, function(value)
        Set("bar.horizon", tonumber(value))
    end, false, "Horizon", "For 'Time to OOM': the time a full bar stands for.")
    horizon:SetPoint("LEFT", height, "RIGHT", 40, 0)
    p.horizonSlider = horizon
    y = y - 42
    Note(f, "Each line keeps its own bar by default: the five-second rule on TBC, your mana on Forever.",
        nil, y)
end

local function SwitchList(p, f, defs, y)
    p.switches = p.switches or {}
    for _, def in ipairs(defs or {}) do
        local cb = Switch(f, {
            text = def.text, tips = def.tips, get = def.get,
            set = function(on)
                def.set(on)
                CS.Refresh(p)
            end,
        })
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", 2, y)
        p.switches[#p.switches + 1] = cb
        y = y - ROW
    end
    return y
end

TAB.show = function(p, f)
    local y = SwitchList(p, f, p.opts.show, -2)
    Note(f, "The Line layout shows at most one secondary segment.", nil, y - 4)
end

TAB.when = function(p, f)
    local y = SwitchList(p, f, p.opts.when, -2)
    local n1 = Note(f, "In combat the clock is always up; out of combat it shows under 90% mana and hides again over 95%.",
        nil, y - 4)
    Note(f, "Left-click opens the window, out of combat only.", n1, -4)
end

CS.TABS = {
    { id = "colours", text = "Colours" }, { id = "frame", text = "Frame" }, { id = "bar", text = "Bar" },
    { id = "show", text = "Show" }, { id = "when", text = "When" },
}

--------------------------------------------------------------------------------
-- Settings -> Clock: the pane
--------------------------------------------------------------------------------
local function Section(pane, text, height, above, gap)
    local t = UI.CreateTitledPane(pane, text, 400, height)
    if above then
        t:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -(gap or 12))
    else
        t:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    end
    t:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    return t
end

local function StyleName()
    local S = UI.Styles
    local key = ActiveStyle()
    local s = S and S.Get and S.Get(key)
    local text = (LABEL[key] and LABEL[key]()) or (s and s.name) or tostring(key)
    return text
end

local function Chip(p, key)
    p.chip = key
    if p.highlightChip then p.highlightChip(key) end
    CS.PaintPreview(p)
end

local function BuildPreview(p, pane)
    local sec = Section(pane, "PREVIEW", 124)
    p.previewSection = sec

    -- the ground the preview sits on: dark (a dungeon) or light (a snowfield)
    local groundBtns = {}
    for i, key in ipairs({ "light", "dark" }) do
        local b = UI.CreateButton(sec, key, "accent-hover", { 44, 16 }, false, false, UI.FONT_SMALL, UI.FONT_SMALL)
        b.id = key
        if i == 1 then
            b:SetPoint("BOTTOMRIGHT", sec.line, "TOPRIGHT", 0, 2)
        else
            b:SetPoint("RIGHT", groundBtns[i - 1], "LEFT", 1, 0)
        end
        groundBtns[i] = b
    end
    local groundLabel = sec:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    groundLabel:SetPoint("RIGHT", groundBtns[2], "LEFT", -6, 0)
    groundLabel:SetTextColor(UI.RGB("muted"))
    groundLabel:SetText("ground")

    local ground = CreateFrame("Frame", nil, sec)
    ground:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -24)
    ground:SetPoint("RIGHT", sec, "RIGHT", 0, 0)
    ground:SetHeight(60)
    ground.tex = ground:CreateTexture(nil, "BACKGROUND")
    ground.tex:SetAllPoints(ground)
    p.ground = ground
    local function Ground(key)
        p.groundKey = key
        local c = CS.GROUND[key]
        ground.tex:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    local highlightGround = UI.CreateButtonGroup(groundBtns, function(id) Ground(id) end)
    Ground("dark")
    highlightGround("dark")

    -- the preview: its own frame, drawn by the clock's renderer
    local frame = CreateFrame("Frame", nil, ground, "BackdropTemplate")
    frame:SetPoint("CENTER", ground, "CENTER", 0, 0)
    frame:SetFrameLevel((ground:GetFrameLevel() or 1) + 2)
    p.previewFrame = frame
    p.view = MD.ClockView.Build(frame, PreviewLook(p), SAMPLE_DRAW)

    -- the chips
    local stateLabel = sec:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    stateLabel:SetPoint("TOPLEFT", ground, "BOTTOMLEFT", 0, -9)
    stateLabel:SetText("state")
    stateLabel:SetTextColor(UI.RGB("muted"))
    p.chips = {}
    local prev
    for _, key in ipairs(CS.CHIPS) do
        local name = CS.ChipName(key)
        local w = math.max(32, math.ceil(UI.TextWidth and UI.TextWidth(name, UI.FONT_SMALL) or (#name * 6)) + 12)
        local b = UI.CreateButton(sec, name, "accent-hover", { w, 18 }, false, false, UI.FONT_SMALL, UI.FONT_SMALL)
        b.id = key
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", -1, 0)
        else
            b:SetPoint("LEFT", stateLabel, "RIGHT", 8, 0)
        end
        p.chips[#p.chips + 1] = b
        prev = b
    end
    p.highlightChip = UI.CreateButtonGroup(p.chips, function(id) Chip(p, id) end)
    p.chipNote = Note(sec, "A chip paints a sample face here; the clock on screen is untouched.", stateLabel, -8)
end

local function BuildLayoutRow(p, pane)
    local sec = Section(pane, "LAYOUT", 46, p.previewSection)
    p.layoutSection = sec
    p.layoutButtons = {}
    local prev
    for _, key in ipairs(MD.ClockView.LAYOUTS or {}) do
        local d = MD.ClockView.LAYOUT[key]
        local name = d and d.name or key
        local b = UI.CreateButton(sec, name, "accent-hover", { math.max(64, #name * 8 + 16), 20 }, false, false,
            UI.FONT_SMALL, UI.FONT_SMALL)
        b.id = key
        if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0)
        else b:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -24) end
        p.layoutButtons[#p.layoutButtons + 1] = b
        prev = b
    end
    p.highlightLayout = UI.CreateButtonGroup(p.layoutButtons, function(id)
        local okL, why = MD.ClockView.SetLayout(id)
        if not okL then MD:Print("mana clock: " .. tostring(why)) end
    end)
    local reset = UI.CreateButton(sec, "Reset to style", "accent-hover", { 110, 20 }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL, "Reset to style", "Every colour and bar setting back to the look's own.",
        "The layout is kept.")
    reset:SetPoint("TOPRIGHT", sec, "TOPRIGHT", 0, -24)
    reset:SetScript("OnClick", function() MD.ClockView.ResetToStyle() end)
    p.resetButton = reset
    local style = sec:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    style:SetPoint("RIGHT", reset, "LEFT", -10, 0)
    style:SetTextColor(UI.RGB("muted"))
    p.styleLabel = style
end

local function BuildBox(p, pane)
    local box = UI.CreateNavBox(pane, 400, 214, CS.TABS, function(group, _, content)
        p.tab = group
        p.tabFrames = p.tabFrames or {}
        for id, fr in pairs(p.tabFrames) do
            if id ~= group then fr:Hide() end
        end
        local fr = p.tabFrames[group]
        if not fr then
            fr = CreateFrame("Frame", nil, content)
            fr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 22)
            fr:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
            p.tabFrames[group] = fr
            TAB[group](p, fr)
            CS.Refresh(p)
        end
        fr:Show()
    end)
    box.frame:SetPoint("TOPLEFT", p.layoutSection, "BOTTOMLEFT", 0, -12)
    box.frame:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    p.box = box
end

local function BuildBottom(p, pane)
    local show = UI.CreateButton(pane, "Show on screen 60 s", "accent-hover", { 140, 20 }, false, false,
        nil, nil, "Show on screen 60 s", "The clock up for 60 s at any mana level, to see or move it.")
    show:SetPoint("TOPRIGHT", p.box.frame, "BOTTOMRIGHT", 0, -8)
    show:SetScript("OnClick", function()
        local W = MD.ClockWidget
        if W and W.Preview then W:Preview(60) end
    end)
    p.showButton = show
    local place = UI.CreateButton(pane, "Reset place", "accent-hover", { 96, 20 }, false, false,
        nil, nil, "Reset place", "The clock back at its default place.")
    place:SetPoint("RIGHT", show, "LEFT", -6, 0)
    place:SetScript("OnClick", function()
        local W = MD.ClockWidget
        if W and W.ResetPosition then W:ResetPosition() end
        MD:Print("mana clock: position reset")
    end)
    p.placeButton = place
end

-- CS.Refresh(p): every control from the resolved look and the line's
-- switches, the preview repainted.
function CS.Refresh(p)
    if not p or not p.view then return end
    local look = PreviewLook(p)
    p.view:SetLook(look)
    if p.highlightLayout then p.highlightLayout(look.layout) end
    if p.styleLabel then p.styleLabel:SetText("style: " .. StyleName() .. " (Settings -> General -> Look)") end
    if p.sourceDropdown then
        p.sourceDropdown:SetItems(SourceItems(p))
        p.sourceDropdown:SetValue(look.bar.source)
    end
    if p.sparkCheck then p.sparkCheck:SetChecked(look.bar.spark == "fsr") end
    if p.heightSlider then p.heightSlider:SetValue(look.bar.height or 4) end
    if p.horizonSlider then p.horizonSlider:SetValue(look.bar.horizon or 180) end
    if p.barColour then
        local c = look.bar.color
        p.barColour:SetValue((c == "source" or c == "tone" or c == "class") and c or "fixed")
    end
    if p.alphaSlider then
        local c = UI.SkinColour(look.panel.fill) or {}
        p.alphaSlider:SetValue(math.floor((c[4] or 1) * 100 + 0.5))
    end
    for _, row in ipairs({ p.fillRow, p.edgeRow, p.barColourRow, p.barBackRow }) do PaintSwatches(row) end
    for _, row in pairs(p.toneRows or {}) do PaintSwatches(row) end
    for _, cb in ipairs(p.switches or {}) do cb:SetChecked(cb.def.get() and true or false) end
    CS.PaintPreview(p)
end

-- MD.ClockSettings.Build(content, opts) -> the Settings -> Clock pane.
-- opts.show / opts.when: the line's own switches, each { text, tips, get, set };
-- a Show switch with `segment` ("rest" / "cd") also drives the preview's
-- look.show at once (the line's own facts follow at its next paint).
function CS.Build(content, opts)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    local p = { pane = pane, opts = opts or {}, chip = "oom" }
    pane.clockSettings = p -- marks this pane for tools/clocksettings.lua
    BuildPreview(p, pane)
    BuildLayoutRow(p, pane)
    BuildBox(p, pane)
    BuildBottom(p, pane)
    panes[p] = true
    p.highlightChip("oom")
    p.box:Select("colours")
    CS.Refresh(p)
    return pane
end

-- The pane's controls again (the dashboards' onShow).
function CS.Show(pane)
    local p = pane and pane.clockSettings
    if p then CS.Refresh(p) end
end

--------------------------------------------------------------------------------
-- Following what changes elsewhere
--------------------------------------------------------------------------------
local function RefreshAll()
    for p in pairs(panes) do CS.Refresh(p) end
    for c in pairs(lookControls) do RefreshLook(c) end
end
MD:RegisterCallback("CLOCK_LOOK", RefreshAll)
MD:RegisterCallback("STYLE_CHANGED", RefreshAll)

-- (Live) follows the real face while the view is on screen.
MD:OnTick(function()
    for p in pairs(panes) do
        if p.chip == "live" and p.pane:IsVisible() then CS.PaintPreview(p) end
    end
end)

--------------------------------------------------------------------------------
-- /st clock layout | look | preview (7.4), through the kernel's seam (2.5)
--------------------------------------------------------------------------------
MD:AddSubcommand("clock", "layout", function(rest)
    local CV = MD.ClockView
    local name = (rest or ""):match("^(%S+)")
    if not name then
        local look = CV.Look(Facts())
        MD:Print(string.format("mana clock: layout %s (layouts: %s)", look.layout, table.concat(CV.LAYOUTS, ", ")))
        return
    end
    local okL, why = CV.SetLayout(name)
    if okL then
        MD:Print("mana clock: layout " .. name:lower())
    else
        MD:Print("mana clock: " .. tostring(why))
    end
end, "layout <name>", "the mana clock's layout (Settings -> Clock shows each)")

MD:AddSubcommand("clock", "look", function(rest)
    if (rest or ""):match("^(%S+)") == "reset" then
        MD.ClockView.ResetToStyle()
        MD:Print("mana clock: every colour and bar setting back to the look's own")
    else
        MD:Print("usage: /st clock look reset")
    end
end, "look reset", "every clock colour and bar setting back to the look's own")

MD:AddSubcommand("clock", "preview", function()
    local W = MD.ClockWidget
    if W and W.Preview then
        W:Preview(60)
        MD:Print("mana clock: on screen for 60 s")
    else
        MD:Print("mana clock: not loaded")
    end
end, "preview", "the clock on screen for 60 s, to see or move it")
