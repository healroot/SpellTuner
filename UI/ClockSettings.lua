-- T102 (docs/SPEC-next.md 5.4, 6.3, 7.3-7.4, section 11 row T102; mockups
-- M7b, M8f, M8g, M9d): the Settings join point, on both lines.
--
--   * Settings -> Clock (7.4): a view of its own in the Settings group (TBC
--     General, Clock, About; Forever General, Clock, Modules, About), built by
--     ST.ClockSettings.Build. T145c (docs/SPEC-clock-v3.md, U3): a MINIMAL
--     pane until U4 rewrites it -- its PREVIEW is a separate frame drawn by
--     ST.ClockBar.New (UI/ClockBar.lua), never the clock on screen, so the
--     single visibility owner of each line (CLAUDE.md) is never touched from
--     here; the sample chips (In a fight, Running out, Filling, Full, Live);
--     the two presets with Undo, the 5SR line and Reset, each one write
--     through UI/ClockStore.lua (one CLOCK_LOOK); the line's When switches
--     (opts.when, each line's dashboard hands them in). CS.Refresh reads
--     ClockStore.Look().
--   * The Look controls (5.4, M7b): the style dropdown (UI.Styles' keys; the
--     Ellesmere entry named by UI.Ellesmere.Label, "Ellesmere (following
--     EllesmereUI)" while it follows), "Use my class colour" (db.useClassColour,
--     registered here) and the honest reload line (decision 4): UI.Restyle's
--     "N windows finish changing after a reload: ..." with [Reload], while what
--     is painted differs from what the session logged in with AND T107 counts
--     something left (since the wave N4 integration nothing is, so it stays
--     hidden). Each line's APPEARANCE /
--     Windows pane places them.
--   * The INTEGRATIONS pane (6.3, M9d): ST.Integrations.Lines() (what was
--     found), the broker switches (db.feeds.ldb, db.feeds.compact) and a hint;
--     a line adds its own switches (the Forever EllesmereUI mover).
--   * The clock subcommands (7.4, 2.5) through ST:AddSubcommand: `/st clock
--     layout` (T145c: says the Bar is the only one), `/st clock look reset`,
--     `/st clock preview`. Forever's
--     `/st clock` and `/st clock lock` keep their meaning (a sub is matched
--     only on its own first word); on TBC, which had no `clock` verb, the subs
--     create `/st clock`.
--   * ST.ClockLook (ST:Provide): the line's rest / cooldown switches, which
--     Integrations/Surface_LDB.lua follows so the broker drops the rest
--     segment when the line does (U4 removes it: the default LineString).
--
-- "Use my class colour" overrides any style's accent (decision 3). UI/Styles.lua
-- (T103's this wave) applies a style through UI.ApplyStyleTokens; this file
-- wraps that applier, handing it the style with accent "class" while the
-- switch is on, and re-applies the active style through UI.Styles.Refresh when
-- it changes (one STYLE_CHANGED). Flat's accent is the class colour already,
-- so under Flat the switch changes nothing.
--
-- Client calls: GetTime (the preview's clock) and ReloadUI through ST.API.Call.
-- No secret is read: the Live preview's pool is drawn by the line's own `draw`
-- (Forever: ST.API.DrawUnitPower, never read back), everything else is the
-- face's plain fields. Every string drawn here is ASCII with no bare pipe.
local _, ST = ...
local UI = ST.UI

ST.ClockSettings = ST.ClockSettings or {}
local CS = ST.ClockSettings

-- decision 3: off -- each style keeps its own accent
ST:RegisterDefaults({ useClassColour = false })

--------------------------------------------------------------------------------
-- The look of SpellTuner's windows: the style, the class colour, the reload line
--------------------------------------------------------------------------------
function CS.ClassColour()
    return type(ST.db) == "table" and ST.db.useClassColour == true
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
ST:RegisterCallback("CORE_LOGIN", function()
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
    ST.API.Call("ReloadUI")
end

local accentLine = false
local function NoteAccent()
    if accentLine or not CS.ClassColour() then return end
    accentLine = true
    ST:AddDumpLine("accent", function()
        return "accent: " .. (CS.ClassColour() and "your class colour (Use my class colour)" or "the style's")
    end)
end

-- CS.SetClassColour(on): saved, the active style applied again.
function CS.SetClassColour(on)
    if type(ST.db) ~= "table" then return false end
    ST.db.useClassColour = on and true or false
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
    if type(ST.db) ~= "table" then return {} end
    if type(ST.db.feeds) ~= "table" then ST.db.feeds = {} end
    return ST.db.feeds
end

function CS.IntegrationLines()
    local INT = ST.Integrations
    if INT and type(INT.Lines) == "function" then
        local okL, lines = pcall(INT.Lines)
        if okL and type(lines) == "table" and #lines > 0 then return lines end
    end
    return { "none found" }
end

-- The hint under the switches: where the brokers show, for what was found.
function CS.IntegrationHint()
    local surf = ST.Surfaces or {}
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
-- The line's look for the broker: Integrations/Surface_LDB.lua's ST.ClockLook.
-- T145c: the Bar is the only layout and its texts are not the broker's; the
-- broker keeps the line's own rest / cooldown switches (U4 removes this).
--------------------------------------------------------------------------------
ST:Provide("ClockLook", function()
    local show = { rest = true, cd = true }
    local db = ST.db
    if type(db) == "table" then
        if type(db.clock) == "table" and db.clock.showRest == false then show.rest = false end
        if db.showRest == false then show.rest = false end
        if db.showCooldown == false then show.cd = false end
    end
    return { show = show }
end)

--------------------------------------------------------------------------------
-- Settings -> Clock: a minimal pane until U4 (docs/SPEC-clock-v3.md 5, U3):
-- the preview (a ClockBar of its own on a ground strip, never the clock on
-- screen), the two presets with Undo, the 5SR line, Reset, Show on screen,
-- and the line's When switches. Every write goes through UI/ClockStore.lua
-- (one CLOCK_LOOK); CS.Refresh reads ClockStore.Look(). U4 replaces it.
--------------------------------------------------------------------------------
-- The sample states (spec 3.1) and their faces, as each line draws them.
CS.CHIPS = { "fight", "low", "filling", "full", "live" }
CS.CHIP_NAMES = { fight = "In a fight", low = "Running out", filling = "Filling", full = "Full", live = "Live" }
CS.SAMPLE_POOL = 0.6   -- the preview's illustrative fill
CS.SAMPLE_FSR = 3      -- seconds left in the five-second rule in a sample fight
CS.GROUND = { 0.05, 0.05, 0.05, 1 }

local SAMPLE_FACES = {
    fight = { mode = "oom", label = "OOM", value = 80, known = "point", tone = "normal", combat = true,
        timeFmt = "mss", pct = 0.6, mana = 4210, manaMax = 7000, mp5 = 92, fsr = 3,
        second = { kind = "rest", label = "rest", value = 130 } },
    low = { mode = "oom", label = "OOM", value = 15, known = "point", tone = "crit", combat = true,
        timeFmt = "mss", pct = 0.1, mana = 700, manaMax = 7000, mp5 = 92 },
    filling = { mode = "ooc", label = "FULL", value = 45, known = "point", tone = "good", combat = false,
        timeFmt = "mss", pct = 0.8, mana = 5600, manaMax = 7000, mp5 = 140 },
    full = { mode = "fullnow", label = "FULL", known = "none", tone = "good", combat = false,
        timeFmt = "mss", pct = 1, mana = 7000, manaMax = 7000, mp5 = 140 },
}

-- CS.SampleFace(key) -> a copy of a sample face (nil for "live").
function CS.SampleFace(key)
    local f = SAMPLE_FACES[key]
    if not f then return nil end
    local out = {}
    for k, v in pairs(f) do
        if type(v) == "table" then
            local c = {}
            for k2, v2 in pairs(v) do c[k2] = v2 end
            out[k] = c
        else
            out[k] = v
        end
    end
    return out
end

function CS.ChipName(key) return CS.CHIP_NAMES[key] or key end

local function LiveFace()
    local CF = ST.ClockFace
    if not (CF and type(CF.Current) == "function") then return nil end
    local okF, face = pcall(CF.Current, GetTime())
    if okF and type(face) == "table" then return face end
    return nil
end

-- The preview's sources: the sample pool and the pane's own five-second rule
-- (a fight's chip: CS.SAMPLE_FSR seconds left), or the line's own (Live).
local function SampleDraw(p)
    if p.sampleDraw then return p.sampleDraw end
    p.sampleDraw = {
        pool = function(b)
            if p.chip == "live" then
                local W = ST.ClockWidget
                local d = W and (W.draw or (W.renderer and W.renderer.draw))
                if d and d.pool then d.pool(b) return end
            end
            b:SetValue(CS.SAMPLE_POOL)
        end,
        poolMax = function(b)
            if p.chip == "live" then
                local W = ST.ClockWidget
                local d = W and (W.draw or (W.renderer and W.renderer.draw))
                if d and d.poolMax then d.poolMax(b) return end
            end
            b:SetMinMaxValues(0, 1)
        end,
        fsrEnd = function()
            if p.chip == "live" then
                local W = ST.ClockWidget
                local d = W and (W.draw or (W.renderer and W.renderer.draw))
                if d and d.fsrEnd then return d.fsrEnd() end
                return nil
            end
            return p.ruleEnd
        end,
    }
    return p.sampleDraw
end

local panes = setmetatable({}, { __mode = "k" })

-- CS.PaintPreview(p): the chip's face (or the live one) in the stored look.
function CS.PaintPreview(p)
    local v = p and p.view
    if not v then return end
    local face
    if p.chip == "live" then face = LiveFace() else face = CS.SampleFace(p.chip) end
    p.words = ST.ClockWords.Build(face, p.look, nil, GetTime(), p.words, false)
    v:Paint(p.words)
    v:PaintPower(true)
    p.face = face
end

local function Chip(p, key)
    p.chip = key
    if p.highlightChip then p.highlightChip(key) end
    local face = CS.SampleFace(key)
    if face and face.combat then p.ruleEnd = GetTime() + CS.SAMPLE_FSR else p.ruleEnd = nil end
    CS.PaintPreview(p)
end

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

local function Note(parent, text, anchor, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    fs:SetPoint("TOPLEFT", anchor or parent, anchor and "BOTTOMLEFT" or "TOPLEFT", 0, y or 0)
    fs:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(UI.RGB("muted"))
    fs:SetText(text)
    return fs
end

local function SmallButton(parent, text, w, title, tip)
    return UI.CreateButton(parent, text, "accent-hover", { w, 20 }, false, false, UI.FONT_SMALL, UI.FONT_SMALL,
        title, tip)
end

local function BuildPreview(p, pane)
    local sec = Section(pane, "PREVIEW", 118)
    p.previewSection = sec
    local ground = CreateFrame("Frame", nil, sec)
    ground:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -24)
    ground:SetPoint("RIGHT", sec, "RIGHT", 0, 0)
    ground:SetHeight(56)
    ground.tex = ground:CreateTexture(nil, "BACKGROUND")
    ground.tex:SetAllPoints(ground)
    ground.tex:SetColorTexture(CS.GROUND[1], CS.GROUND[2], CS.GROUND[3], CS.GROUND[4])
    p.ground = ground

    -- the preview: its own frame, drawn by the clock's renderer
    local frame = CreateFrame("Frame", nil, ground, "BackdropTemplate")
    frame:SetPoint("CENTER", ground, "CENTER", 0, 0)
    frame:SetFrameLevel((ground:GetFrameLevel() or 1) + 2)
    p.previewFrame = frame
    p.view = ST.ClockBar.New(frame, SampleDraw(p))

    p.chips = {}
    local prev
    for _, key in ipairs(CS.CHIPS) do
        local name = CS.ChipName(key)
        local w = math.max(40, #name * 6 + 14)
        local b = SmallButton(sec, name, w)
        b.id = key
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", -1, 0)
        else
            b:SetPoint("TOPLEFT", ground, "BOTTOMLEFT", 0, -8)
        end
        p.chips[#p.chips + 1] = b
        prev = b
    end
    p.highlightChip = UI.CreateButtonGroup(p.chips, function(id) Chip(p, id) end)
    local show = SmallButton(sec, "Show on screen", 110, "Show on screen",
        "The clock up for 60 s at any mana level, to see or move it.")
    show:SetPoint("TOPRIGHT", ground, "BOTTOMRIGHT", 0, -8)
    show:SetScript("OnClick", function()
        local W = ST.ClockWidget
        if W and W.Preview then W:Preview(60) end
    end)
    p.showButton = show
end

local function BuildBar(p, pane)
    local sec = Section(pane, "BAR", 104, p.previewSection)
    p.barSection = sec
    local label = sec:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    label:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -28)
    label:SetText("Presets")
    p.presetButtons = {}
    local prev = label
    for _, pr in ipairs(ST.ClockStore.PRESETS) do
        local b = SmallButton(sec, pr.name, math.max(80, #pr.name * 7 + 16), pr.name, pr.tip)
        b.id = pr.key
        b:SetPoint("LEFT", prev, "RIGHT", (prev == label) and 8 or 4, 0)
        b:SetScript("OnClick", function() CS.ApplyPreset(pr.key) end)
        p.presetButtons[#p.presetButtons + 1] = b
        prev = b
    end
    local undo = SmallButton(sec, "Undo", 60, "Undo", "Your look before the last preset.")
    undo:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    undo:SetScript("OnClick", function() ST.ClockStore.Undo() end)
    p.undoButton = undo
    local reset = SmallButton(sec, "Reset", 60, "Reset", "The SpellTuner look.")
    reset:SetPoint("TOPRIGHT", sec, "TOPRIGHT", 0, -24)
    reset:SetScript("OnClick", function() ST.ClockStore.Reset() end)
    p.resetButton = reset

    local line = UI.CreateCheckButton(sec, "5SR line", function(checked)
        ST.ClockStore.Set("line", checked and true or false)
    end, "5SR line", "The amber line crossing the bar for the five seconds after your last priced cast.")
    line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -12)
    p.lineCheck = line
    p.barNote = Note(sec, "Width, height, the texture, the texts and their places come back in the next build.",
        line, -8)
end

local function BuildWhen(p, pane)
    local defs = p.opts.when or {}
    local sec = Section(pane, "WHEN", 30 + 22 * #defs + 18, p.barSection)
    p.whenSection = sec
    p.switches = {}
    local y = -26
    for _, def in ipairs(defs) do
        local cb = Switch(sec, {
            text = def.text, tips = def.tips, get = def.get,
            set = function(on)
                def.set(on)
                CS.Refresh(p)
            end,
        })
        cb:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, y)
        p.switches[#p.switches + 1] = cb
        y = y - 22
    end
    Note(sec, "In combat the clock is always up; out of combat it shows under 90% mana and hides over 95%.",
        nil, y - 2)
end

-- CS.ApplyPreset(key): ClockStore's preset (EllesmereUI's with its live mana
-- colour when it is loaded).
function CS.ApplyPreset(key)
    local opts
    local pr = ST.ClockStore.Preset(key)
    if pr and pr.hostFill and ST.Media and ST.Media.EllesmereMana then
        local c = ST.Media.EllesmereMana()
        if type(c) == "table" then
            opts = { fill = string.format("%02X%02X%02X", math.floor(c[1] * 255 + 0.5),
                math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) }
        end
    end
    return ST.ClockStore.ApplyPreset(key, opts)
end

-- CS.Refresh(p): the stored look into the preview and the controls.
function CS.Refresh(p)
    if not p or not p.view then return end
    p.look = ST.ClockStore.Look()
    p.view:Apply(p.look)
    if p.lineCheck then p.lineCheck:SetChecked(p.look.line == true) end
    if p.undoButton then
        if ST.ClockStore.HasUndo() then p.undoButton:Show() else p.undoButton:Hide() end
    end
    for _, cb in ipairs(p.switches or {}) do cb:SetChecked(cb.def.get() and true or false) end
    CS.PaintPreview(p)
end

-- ST.ClockSettings.Build(content, opts) -> the Settings -> Clock pane.
-- opts.when: the line's own switches, each { text, tips, get, set }.
function CS.Build(content, opts)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    local p = { pane = pane, opts = opts or {}, chip = "fight" }
    pane.clockSettings = p -- marks this pane for tools/clocksettings.lua
    BuildPreview(p, pane)
    BuildBar(p, pane)
    BuildWhen(p, pane)
    panes[p] = true
    p.highlightChip("fight")
    p.ruleEnd = GetTime() + CS.SAMPLE_FSR
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
ST:RegisterCallback("CLOCK_LOOK", RefreshAll)
ST:RegisterCallback("STYLE_CHANGED", RefreshAll)

-- Live follows the real face while the view is on screen.
ST:OnTick(function()
    for p in pairs(panes) do
        if p.chip == "live" and p.pane:IsVisible() then CS.PaintPreview(p) end
    end
end)

--------------------------------------------------------------------------------
-- /st clock layout | look | preview (7.4), through the kernel's seam (2.5)
--------------------------------------------------------------------------------
ST:AddSubcommand("clock", "layout", function()
    ST:Print("mana clock: the Bar is the only layout now (Settings -> Clock sets its look)")
end, "layout", "the mana clock's layout: the Bar")

ST:AddSubcommand("clock", "look", function(rest)
    if (rest or ""):match("^(%S+)") == "reset" then
        ST.ClockStore.Reset()
        ST:Print("mana clock: the look back to SpellTuner's")
    else
        ST:Print("usage: /st clock look reset")
    end
end, "look reset", "the clock's look back to SpellTuner's")

ST:AddSubcommand("clock", "preview", function()
    local W = ST.ClockWidget
    if W and W.Preview then
        W:Preview(60)
        ST:Print("mana clock: on screen for 60 s")
    else
        ST:Print("mana clock: not loaded")
    end
end, "preview", "the clock on screen for 60 s, to see or move it")
