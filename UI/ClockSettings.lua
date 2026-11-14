-- T102 (docs/SPEC-next.md 5.4, 6.3, 7.3-7.4, section 11 row T102; mockups
-- M7b, M8f, M8g, M9d): the Settings join point, on both lines.
--
--   * Settings -> Clock: T145d (docs/SPEC-clock-v3.md 3; the approved mockup
--     tools/.cache/clockv3/index.html; docs/tasks/T145d-clock-pane.md) -- ONE
--     pane, no tabs: PREVIEW (a ClockBar of its own on a ground strip, never
--     the clock on screen, so each line's single visibility owner is never
--     touched from here; the chips In a fight, Running out, Filling, Full,
--     Live; Show on screen), then, scrolling, BAR, TEXTS, PRESETS and WHEN.
--     Every control is an entry of CS.CONTROLS (id, kind, key, values,
--     visible, affects, write): the pane is built from it, every write is ONE
--     ClockStore write and ONE CLOCK_LOOK, a control the look makes inert is
--     hidden (an off text shows only its switch, P1), and tools/clocke2e.lua
--     walks the same list against the live clock. A choice the client cannot
--     honour shows the renderer's reason (look.notes) beside it and stays
--     clickable (spec 2.6).
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
--   * T145d: no ST.ClockLook provider any more -- the feeds draw the default
--     ClockFace.LineString (spec 1.1).
--
-- "Use my class colour" overrides any style's accent (decision 3). UI/Styles.lua
-- (T103's this wave) applies a style through UI.ApplyStyleTokens; this file
-- wraps that applier, handing it the style with accent "class" while the
-- switch is on, and re-applies the active style through UI.Styles.Refresh when
-- it changes (one STYLE_CHANGED). Flat's accent is the class colour already,
-- so under Flat the switch changes nothing.
--
-- Client calls: GetTime (the preview's clock), ReloadUI and the colour picker
-- through ST.API. No secret is read: the Live preview's pool is drawn by the
-- line's own `draw` (Forever: ST.API.DrawUnitPower, never read back),
-- everything else is the face's plain fields. Every string drawn here is ASCII
-- with no bare pipe.
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
-- Settings -> Clock (docs/SPEC-clock-v3.md 3): the preview, the sample faces
--------------------------------------------------------------------------------
-- The sample states (spec 3.1) and their faces, as each line draws them.
CS.CHIPS = { "fight", "low", "filling", "full", "live" }
CS.CHIP_NAMES = { fight = "In a fight", low = "Running out", filling = "Filling", full = "Full", live = "Live" }
CS.SAMPLE_POOL = 0.6   -- the preview's illustrative fill
CS.SAMPLE_FSR = 3      -- seconds left in the five-second rule when a fight's chip is picked
CS.SAMPLE_GAP = 1.5    -- seconds between two of the sample's rules (the mockup's loop)
CS.GROUND = { 0.05, 0.05, 0.05, 1 }

local SAMPLE_FACES = {
    fight = { mode = "oom", label = "OOM", value = 80, known = "point", tone = "normal", combat = true,
        timeFmt = "mss", pct = 0.6, mana = 4210, manaMax = 7000, mp5 = 92, fsr = 3,
        second = { kind = "rest", label = "rest", value = 130 } },
    low = { mode = "oom", label = "OOM", value = 15, known = "point", tone = "crit", combat = true,
        timeFmt = "mss", pct = 0.1, mana = 700, manaMax = 7000, mp5 = 92, fsr = 3 },
    filling = { mode = "ooc", label = "FULL", value = 45, known = "point", tone = "good", combat = false,
        timeFmt = "mss", pct = 0.8, mana = 5600, manaMax = 7000, mp5 = 140 },
    full = { mode = "fullnow", label = "FULL", known = "none", tone = "good", combat = false,
        timeFmt = "mss", pct = 1, mana = 7000, manaMax = 7000, mp5 = 140 },
}
local RULE_CHIPS = { fight = true, low = true }

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

local function LiveDraw()
    local W = ST.ClockWidget
    return W and (W.draw or (W.renderer and W.renderer.draw)) or nil
end

-- The preview's sources: the sample pool and the pane's own five-second rule
-- (a fight's chip: a rule that runs again after CS.SAMPLE_GAP), or the
-- line's own (Live: its pool, range, rule and power texts).
local function SampleDraw(p)
    if p.sampleDraw then return p.sampleDraw end
    p.sampleDraw = {
        pool = function(b)
            if p.chip == "live" then
                local d = LiveDraw()
                if d and d.pool then d.pool(b) return end
            end
            b:SetValue(CS.SAMPLE_POOL)
        end,
        poolMax = function(b)
            if p.chip == "live" then
                local d = LiveDraw()
                if d and d.poolMax then d.poolMax(b) return end
            end
            b:SetMinMaxValues(0, 1)
        end,
        -- T145 review N4: Live draws the game's own mana texts, as the
        -- clock on screen does; a sample chip, the sample's words
        powerText = function(fs, kind)
            if p.chip == "live" then
                local d = LiveDraw()
                if d and d.powerText then return d.powerText(fs, kind) end
            end
            return false
        end,
        fsrEnd = function()
            if p.chip == "live" then
                local d = LiveDraw()
                if d and d.fsrEnd then return d.fsrEnd() end
                return nil
            end
            if not RULE_CHIPS[p.chip] then return nil end
            local now = GetTime()
            if not p.ruleEnd or now >= p.ruleEnd + CS.SAMPLE_GAP then p.ruleEnd = now + ST.ClockBar.RULE end
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
    if RULE_CHIPS[key] then
        p.ruleEnd = GetTime() + CS.SAMPLE_FSR
    else
        p.ruleEnd = nil
    end
    CS.PaintPreview(p)
end
CS.Chip = Chip

--------------------------------------------------------------------------------
-- The words of the pane
--------------------------------------------------------------------------------
CS.SHAPE_NAMES = { rect = "Rectangle", round = "Rounded", pill = "Pill" }
CS.FRAME_NAMES = { none = "None", border = "Border", game = "Game frame" }
CS.FONT_NAMES = { eui = "EllesmereUI's", st = "SpellTuner's" }
CS.FILL_NAMES = { mana = "Mana blue", class = "Class colour", custom = "Custom" }
CS.LINE_NAMES = { on = "On", off = "Off" }
CS.TIME_NAMES = { mss = "1:20", sec = "80s" }
CS.STEP_NAMES = {
    place = { inside = "Inside", above = "Above", below = "Below" },
    align = { left = "Left", center = "Centre", right = "Right" },
    outline = { none = "None", outline = "Outline", thick = "Thick", shadow = "Shadow" },
}
CS.TEXTURE_NAMES = { soft = "Soft", flat = "Flat", smooth = "Smooth", gloss = "Gloss", striped = "Striped",
    minimal = "Minimal", statusbar = "Status bar", raid = "Raid health" }
-- Custom's first colour when the fill is Mana blue or the class colour: one
-- that differs from both (EllesmereUI's mana blue), so the click shows.
CS.CUSTOM_FILL = "008CFF"

-- What each text says in its row (the In a fight sample's words).
local function SampleWords(kind, look)
    if kind == "time" then
        return (look and look.timeFmt == "sec") and "80s / FULL" or "1:20 / FULL"
    end
    local w = { mana = "4210", manaMax = "4210/7000", pct = "60%", mp5 = "92 mp5", fsr = "5SR 3.0",
        rest = "rest 2:10" }
    return w[kind] or ""
end
CS.SampleWords = SampleWords

-- The Texture list: SpellTuner's and the game's, then EllesmereUI's, then the
-- host's (LibSharedMedia).
function CS.TextureItems()
    local Store = ST.ClockStore
    local items = {}
    for _, id in ipairs(Store.TEXTURES) do
        items[#items + 1] = { id = id, text = CS.TEXTURE_NAMES[id] or id }
    end
    for _, x in ipairs(ST.Media and ST.Media.Ellesmere and ST.Media.Ellesmere() or {}) do
        items[#items + 1] = { id = Store.EUI_PREFIX .. x.key, text = x.name .. " (EllesmereUI)" }
    end
    for _, x in ipairs(ST.Media and ST.Media.Bars and ST.Media.Bars() or {}) do
        items[#items + 1] = { id = Store.LSM_PREFIX .. x.name, text = x.name .. " (your UI)" }
    end
    return items
end

local function Hex6(r, g, b)
    local function C(x) return math.max(0, math.min(255, math.floor(x * 255 + 0.5))) end
    return string.format("%02X%02X%02X", C(r), C(g), C(b))
end
CS.Hex6 = Hex6

local function HexRGB(h) return ST.ClockBar.HexRGB(h) end

--------------------------------------------------------------------------------
-- The control registry (spec 3): every control of the pane, and what the
-- end-to-end suite (tools/clocke2e.lua) walks. Each entry:
--   id        the control's name
--   kind      buttons | slider | dropdown | swatch | check | number | step
--   key       the store path it writes
--   values    the test's sample values to cycle
--   get(look) the control's value in a look (a Fill hex reads "custom")
--   visible(look)  when the control shows (an off text's fields: hidden)
--   affects   the ClockBar:Drawn() fields it changes ("text.*.face": any text)
--   write(v)  ONE ClockStore write, ONE CLOCK_LOOK -> true | false, why
--------------------------------------------------------------------------------
local function Always() return true end
local function IsHex(v) return type(v) == "string" and v:match("^%x%x%x%x%x%x$") ~= nil end

local function Set(key, value) return ST.ClockStore.Set(key, value) end

-- Fill's three buttons: Custom keeps a colour already custom, else the
-- session's last custom colour, else CS.CUSTOM_FILL.
local lastCustom = nil
function CS.SetFill(id)
    if id == "custom" then
        local now = ST.ClockStore.Look().fill
        if IsHex(now) then return Set("fill", now) end
        return Set("fill", lastCustom or CS.CUSTOM_FILL)
    end
    return Set("fill", id)
end
local function SetFillColour(hex)
    lastCustom = hex
    return Set("fill", hex)
end

-- The Background swatch: colour and opacity in one write.
function CS.SetBack(hex, alpha)
    return ST.ClockStore.SetMany({ back = hex, backAlpha = alpha })
end

CS.CONTROLS = {
    { id = "width", kind = "slider", key = "width", values = { 150, 300, 400 }, range = { 100, 400 },
      label = "Width", affects = { "host.w" } },
    { id = "height", kind = "slider", key = "height", values = { 4, 12, 20 }, range = { 3, 30 },
      label = "Height", affects = { "host.h" } },
    { id = "shape", kind = "buttons", key = "shape", values = { "rect", "round", "pill" }, names = CS.SHAPE_NAMES,
      label = "Shape", affects = { "masks.file" }, note = "shape" },
    { id = "frame", kind = "buttons", key = "frame", values = { "none", "border", "game" }, names = CS.FRAME_NAMES,
      label = "Frame", affects = { "edge.shown", "game" }, note = "frame" },
    { id = "texture", kind = "dropdown", key = "texture", values = { "flat", "gloss", "statusbar", "soft" },
      label = "Texture", affects = { "bar.texture" }, note = "texture" },
    { id = "font", kind = "buttons", key = "font", values = { "eui", "st" }, names = CS.FONT_NAMES,
      label = "Font", affects = { "text.*.face" }, note = "font",
      -- T145 review N2: with every text off a font draws nothing
      visible = function(look)
          for _, kind in ipairs(ST.ClockStore.KINDS) do
              if look.texts[kind] and look.texts[kind].on == true then return true end
          end
          return false
      end },
    { id = "fill", kind = "buttons", key = "fill", values = { "mana", "class", "custom" }, names = CS.FILL_NAMES,
      label = "Fill", affects = { "bar.colour" },
      get = function(look) return IsHex(look.fill) and "custom" or look.fill end,
      write = CS.SetFill },
    { id = "fillColour", kind = "swatch", key = "fill", values = { "112233", "AA5500" },
      label = "Custom", affects = { "bar.colour" },
      get = function(look) return IsHex(look.fill) and look.fill or nil end,
      visible = function(look) return IsHex(look.fill) end,
      write = SetFillColour },
    { id = "back", kind = "swatch", key = "back", alpha = true, values = { { "222222", 1 }, { "0A0A0A", 0.5 } },
      label = "Background", affects = { "back.colour" },
      get = function(look) return { look.back, look.backAlpha } end,
      write = function(v) return CS.SetBack(v[1], v[2]) end },
    { id = "line", kind = "buttons", key = "line", values = { "on", "off" }, names = CS.LINE_NAMES,
      label = "5SR line", affects = { "line.on", "line.shown" },
      get = function(look) return look.line and "on" or "off" end,
      write = function(v) return Set("line", v == "on") end,
      hint = "amber, crossing the bar for the five seconds after a priced cast" },
}

-- The texts' controls, per kind in drawing order.
CS.TEXT_FIELDS = { "place", "align", "x", "y", "size", "colour", "outline" }
local TEXT_VALUES = {
    place = { "inside", "above", "below" },
    align = { "left", "center", "right" },
    x = { -5, 6 }, y = { -3, 4 }, size = { 9, 16 },
    colour = { "FF4040", "40FF40" },
    outline = { "none", "outline", "thick", "shadow" },
}
local TEXT_KIND = { place = "step", align = "step", x = "number", y = "number", size = "number",
    colour = "swatch", outline = "step" }
local TEXT_AFFECTS = { place = { "point" }, align = { "point" }, x = { "point" }, y = { "point" },
    size = { "size" }, colour = { "colour" }, outline = { "flags", "shadow" } }

for _, kind in ipairs(ST.ClockStore.KINDS) do
    local base = "texts." .. kind
    CS.CONTROLS[#CS.CONTROLS + 1] = {
        id = base .. ".on", kind = "check", key = base .. ".on", text = kind, field = "on", values = { true, false },
        affects = { "text." .. kind .. ".shown" },
    }
    for _, f in ipairs(CS.TEXT_FIELDS) do
        CS.CONTROLS[#CS.CONTROLS + 1] = {
            id = base .. "." .. f, kind = TEXT_KIND[f], key = base .. "." .. f, text = kind, field = f,
            values = TEXT_VALUES[f], range = (f == "x" or f == "y" or f == "size") and ST.ClockStore.RANGES[f] or nil,
            affects = (function()
                local a = {}
                for i, x in ipairs(TEXT_AFFECTS[f]) do a[i] = "text." .. kind .. "." .. x end
                return a
            end)(),
            visible = function(look) return look.texts[kind].on == true end,
        }
    end
    if kind == "time" then
        CS.CONTROLS[#CS.CONTROLS + 1] = {
            id = "timeFmt", kind = "buttons", key = "timeFmt", values = { "mss", "sec" }, names = CS.TIME_NAMES,
            text = "time", label = "Time as", affects = { "text.time.words" },
            visible = function(look) return look.texts.time.on == true end,
        }
        CS.CONTROLS[#CS.CONTROLS + 1] = {
            id = "warn", kind = "check", key = "warn", values = { true, false }, text = "time",
            label = "Warn colours", affects = { "text.time.colour" },
            visible = function(look) return look.texts.time.on == true end,
            hint = "red under 20 s, amber under 60 s, while running out",
        }
    end
end

-- Defaults of the registry: get / visible / write from the key.
local function PathGet(look, key)
    local t = look
    for part in key:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end
CS.PathGet = PathGet
CS.byId = {}
for _, c in ipairs(CS.CONTROLS) do
    c.get = c.get or function(look) return PathGet(look, c.key) end
    c.visible = c.visible or Always
    c.write = c.write or function(v) return Set(c.key, v) end
    CS.byId[c.id] = c
end

-- CS.Control(id) -> the registry's entry.
function CS.Control(id) return CS.byId[id] end

-- The next (or, back, the previous) value of a stepped text field.
function CS.StepValue(field, now, back)
    local list = TEXT_VALUES[field]
    local i = 1
    for k, v in ipairs(list) do if v == now then i = k end end
    if back then i = (i - 2) % #list + 1 else i = i % #list + 1 end
    return list[i]
end

-- A colour through the game's picker: onPick(hex, alpha) on every move and,
-- on Cancel, with the colour it opened with.
function CS.PickColour(hex, alpha, onPick)
    local r, g, b = HexRGB(hex)
    local ok, why = ST.API.PickColour(r, g, b, alpha or 1, function(nr, ng, nb, na)
        onPick(Hex6(nr, ng, nb), na)
    end)
    if not ok then ST:Print("mana clock: the colour picker is not available (" .. tostring(why) .. ")") end
    return ok
end

--------------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------------
local function Section(parent, text, height)
    local t = UI.CreateTitledPane(parent, text, 400, height)
    return t
end

local function Note(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(UI.RGB("muted"))
    fs:SetText(text or "")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

local function Label(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(UI.RGB("label"))
    fs:SetText(text)
    return fs
end

local function SmallButton(parent, text, w, title, tip)
    return UI.CreateButton(parent, text, "accent-hover", { w, 18 }, false, false, UI.FONT_SMALL, UI.FONT_SMALL,
        title, tip)
end

local function Swatch(parent, onClick, title, tip)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(14, 14)
    UI.Skin(b, "field", "field", "border")
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b:SetScript("OnClick", onClick)
    UI.SetTooltips(b, "ANCHOR_TOPLEFT", 0, 3, title, tip)
    function b:SetHex(hex, a)
        local r, g, bb = HexRGB(hex)
        b.tex:SetColorTexture(r, g, bb, a or 1)
        b.hex, b.alpha = hex, a
    end
    return b
end

-- A row of buttons in a frame of its own (the control's widget): one
-- highlighted, a click writes.
local function ButtonRow(parent, c, w)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(#c.values * (w - 1) + 1, 18)
    row.buttons = {}
    local prev
    for _, v in ipairs(c.values) do
        local b = SmallButton(row, c.names and c.names[v] or tostring(v), w, c.label)
        b.id = v
        if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0) else b:SetPoint("LEFT", row, "LEFT", 0, 0) end
        row.buttons[#row.buttons + 1] = b
        prev = b
    end
    row.highlight = UI.CreateButtonGroup(row.buttons, function(id) c.write(id) end)
    return row
end

--------------------------------------------------------------------------------
-- PREVIEW
--------------------------------------------------------------------------------
local function BuildPreview(p, pane)
    local sec = Section(pane, "PREVIEW", 108)
    sec:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    sec:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
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
        local b = SmallButton(sec, name, math.max(40, #name * 6 + 14))
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

--------------------------------------------------------------------------------
-- BAR
--------------------------------------------------------------------------------
local LABEL_X, CONTROL_X, ROW_H = 6, 90, 24

local function BuildBar(p, parent)
    local sec = Section(parent, "BAR", 100)
    p.barSection = sec
    sec.sub = Note(sec, "the game's own mana fill; nothing here reads it")
    sec.sub:SetPoint("BOTTOMRIGHT", sec.line, "TOPRIGHT", 0, 2)

    -- Width and Height: two sliders, written on release (or Enter)
    local x = CONTROL_X
    for _, id in ipairs({ "width", "height" }) do
        local c = CS.byId[id]
        local s = UI.CreateSlider(c.label, sec, c.range[1], c.range[2], 160, 1, nil, function(value)
            value = tonumber(value)
            if value then c.write(math.floor(value + 0.5)) end
        end, false, c.label, id == "width" and "The bar's width, 100 to 400."
            or "The bar's height, 3 to 30; no text ever changes it.")
        s:SetPoint("TOPLEFT", sec, "TOPLEFT", x, -46)
        p.widgets[id] = s
        x = x + 240
    end

    local y = -86
    local function Row(text)
        local l = Label(sec, text)
        l:SetPoint("TOPLEFT", sec, "TOPLEFT", LABEL_X, y - 3)
        return l
    end
    local function NoteAfter(id, anchor)
        local n = Note(sec, CS.byId[id].hint)
        n:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
        n:SetPoint("RIGHT", sec, "RIGHT", -4, 0)
        p.notes[id] = n
        return n
    end

    for _, id in ipairs({ "shape", "frame" }) do
        local c = CS.byId[id]
        Row(c.label)
        local row = ButtonRow(sec, c, id == "frame" and 82 or 74)
        row:SetPoint("TOPLEFT", sec, "TOPLEFT", CONTROL_X, y)
        p.widgets[id] = row
        NoteAfter(id, row)
        y = y - ROW_H
    end

    Row("Texture")
    local tex = UI.CreateDropdown(sec, 180, 18, function(id) CS.byId.texture.write(id) end)
    tex:SetPoint("TOPLEFT", sec, "TOPLEFT", CONTROL_X, y)
    UI.SetTooltips(tex, "ANCHOR_TOPLEFT", 0, 3, "Texture",
        "SpellTuner's, the game's two bars, EllesmereUI's and the bar textures your UI addons share (LibSharedMedia).")
    p.widgets.texture = tex
    p.textureDropdown = tex
    NoteAfter("texture", tex)
    y = y - ROW_H

    Row("Font")
    local font = ButtonRow(sec, CS.byId.font, 96)
    font:SetPoint("TOPLEFT", sec, "TOPLEFT", CONTROL_X, y)
    p.widgets.font = font
    NoteAfter("font", font)
    y = y - ROW_H

    Row("Fill")
    local fill = ButtonRow(sec, CS.byId.fill, 82)
    fill:SetPoint("TOPLEFT", sec, "TOPLEFT", CONTROL_X, y)
    p.widgets.fill = fill
    local fc = Swatch(sec, function(self, button)
        local look = p.look or ST.ClockStore.Look()
        if button == "RightButton" then return CS.SetFill("mana") end
        CS.PickColour(IsHex(look.fill) and look.fill or CS.CUSTOM_FILL, 1, function(hex) SetFillColour(hex) end)
    end, "Custom fill", "Click: any colour. Right-click: Mana blue.")
    fc:SetPoint("LEFT", fill, "RIGHT", 8, 0)
    p.widgets.fillColour = fc
    y = y - ROW_H

    Row("Background")
    local back = Swatch(sec, function(self, button)
        local look = p.look or ST.ClockStore.Look()
        if button == "RightButton" then
            local d = ST.ClockStore.DEFAULTS
            return CS.SetBack(d.back, d.backAlpha)
        end
        CS.PickColour(look.back, look.backAlpha, function(hex, a)
            if type(a) ~= "number" then a = look.backAlpha end
            a = math.max(0, math.min(1, math.floor(a * 100 + 0.5) / 100))
            CS.SetBack(hex, a)
        end)
    end, "Background", "Click: its colour and opacity. Right-click: SpellTuner's.")
    back:SetPoint("TOPLEFT", sec, "TOPLEFT", CONTROL_X, y - 2)
    p.widgets.back = back
    p.backAlphaText = Note(sec, "")
    p.backAlphaText:SetPoint("LEFT", back, "RIGHT", 6, 0)
    y = y - ROW_H

    Row("5SR line")
    local line = ButtonRow(sec, CS.byId.line, 50)
    line:SetPoint("TOPLEFT", sec, "TOPLEFT", CONTROL_X, y)
    p.widgets.line = line
    NoteAfter("line", line)
    y = y - ROW_H

    sec:SetHeight(-y + 4)
    return sec
end

--------------------------------------------------------------------------------
-- TEXTS
--------------------------------------------------------------------------------
CS.TEXT_COLS = { on = 4, name = 22, sample = 84, place = 170, align = 228, x = 290, y = 328, size = 366,
    colour = 408, outline = 430 }
local TEXT_ROW = 22

local function NumberBox(parent, c)
    local eb = UI.CreateEditBox(parent, 34, 16, false, false, false, UI.FONT_SMALL)
    eb:SetTextInsets(3, 3, 0, 0)
    local function Commit()
        local n = tonumber(eb:GetText() or "")
        if n then
            n = math.max(c.range[1], math.min(c.range[2], math.floor(n + 0.5)))
            local look = ST.ClockStore.Look()
            if c.get(look) ~= n then c.write(n) end
        end
        if eb.refresh then eb.refresh() end
    end
    eb.commit = Commit
    eb:SetScript("OnEnterPressed", function() Commit(); eb:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function() eb:HighlightText(0, 0); Commit() end)
    return eb
end

local function TextRow(p, parent, kind)
    local C = CS.TEXT_COLS
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(500, TEXT_ROW - 2)
    row.kind = kind
    local name = ST.ClockStore.NAMES[kind]
    local onC = CS.byId["texts." .. kind .. ".on"]
    row.on = UI.CreateCheckButton(row, "", function(checked) onC.write(checked and true or false) end,
        "Show " .. name, "On: its place, size, colour and outline. Off: nothing drawn, its settings kept.")
    row.on:SetPoint("LEFT", row, "LEFT", C.on, 0)
    p.widgets[onC.id] = row.on
    row.name = row:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    row.name:SetPoint("LEFT", row, "LEFT", C.name, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetText(name)
    row.sample = Note(row, "")
    row.sample:SetPoint("LEFT", row, "LEFT", C.sample, 0)

    local function Step(field, w, title, tip)
        local c = CS.byId["texts." .. kind .. "." .. field]
        local b = UI.CreateButton(row, "", "accent-hover", { w, 16 }, false, false, UI.FONT_SMALL, UI.FONT_SMALL,
            title, tip)
        b:SetPoint("LEFT", row, "LEFT", C[field], 0)
        if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        b:SetScript("OnClick", function(_, button)
            local look = ST.ClockStore.Look()
            c.write(CS.StepValue(field, c.get(look), button == "RightButton"))
        end)
        p.widgets[c.id] = b
        return b
    end
    Step("place", 56, "Place", "Inside the bar, above it or below it: outside, it never makes the bar taller. "
        .. "Click: next; right-click: back.")
    Step("align", 60, "Align", "From the bar's left edge, centre or right edge. Click: next; right-click: back.")
    for _, f in ipairs({ "x", "y", "size" }) do
        local c = CS.byId["texts." .. kind .. "." .. f]
        local eb = NumberBox(row, c)
        eb:SetPoint("LEFT", row, "LEFT", C[f], 0)
        eb.refresh = function() CS.Refresh(p) end
        UI.SetTooltips(eb, "ANCHOR_TOPLEFT", 0, 3, (f == "size") and "Size" or string.upper(f),
            string.format("%d to %d; Enter writes it.", c.range[1], c.range[2]))
        p.widgets[c.id] = eb
    end
    local cc = CS.byId["texts." .. kind .. ".colour"]
    local sw = Swatch(row, function(_, button)
        local look = ST.ClockStore.Look()
        if button == "RightButton" then return cc.write(ST.ClockStore.DEFAULTS.texts[kind].colour) end
        CS.PickColour(look.texts[kind].colour, 1, function(hex) cc.write(hex) end)
    end, "Colour", "Click: any colour. Right-click: SpellTuner's.")
    sw:SetPoint("LEFT", row, "LEFT", C.colour, 0)
    p.widgets[cc.id] = sw
    Step("outline", 64, "Outline", "None, an outline, a thick outline or a drop shadow. "
        .. "Click: next; right-click: back.")

    if kind == "time" then
        local ex = CreateFrame("Frame", nil, parent)
        ex:SetSize(500, TEXT_ROW - 2)
        local l = Label(ex, "Time as")
        l:SetPoint("LEFT", ex, "LEFT", C.name, 0)
        local tf = ButtonRow(ex, CS.byId.timeFmt, 44)
        tf:SetPoint("LEFT", ex, "LEFT", C.sample, 0)
        p.widgets.timeFmt = tf
        local wc = CS.byId.warn
        local warn = UI.CreateCheckButton(ex, "Warn colours", function(checked) wc.write(checked and true or false) end,
            "Warn colours", "The time red under 20 s and amber under 60 s while running out.",
            "Off: always the text's own colour.")
        warn:SetPoint("LEFT", ex, "LEFT", C.place, 0)
        p.widgets.warn = warn
        local hint = Note(ex, wc.hint)
        hint:SetPoint("LEFT", ex, "LEFT", C.place + 104, 0)
        row.extra = ex
    end
    return row
end

local function BuildTexts(p, parent)
    local sec = Section(parent, "TEXTS", 100)
    p.textsSection = sec
    sec.sub = Note(sec, "inside, above or below the bar; no text ever changes the bar's size")
    sec.sub:SetPoint("BOTTOMRIGHT", sec.line, "TOPRIGHT", 0, 2)
    local C = CS.TEXT_COLS
    for _, h in ipairs({ { "Show", C.on - 2 }, { "Text", C.name }, { "Place", C.place }, { "Align", C.align },
        { "X", C.x }, { "Y", C.y }, { "Size", C.size }, { "Colour", C.colour - 6 }, { "Outline", C.outline } }) do
        local fs = Label(sec, h[1])
        fs:SetPoint("TOPLEFT", sec, "TOPLEFT", h[2], -24)
    end
    p.textRows = {}
    for _, kind in ipairs(ST.ClockStore.KINDS) do
        p.textRows[#p.textRows + 1] = TextRow(p, sec, kind)
    end
    p.textsNote = Note(sec, "Place, Align and Outline step on a click (right-click steps back). Mana, Mana / max "
        .. "and Mana % are the game's own numbers, drawn unread. A bare time is until OOM; a refill always says FULL.")
    return sec
end

-- The rows placed for the look: the Time row's extra line only while the
-- time is on; an off row shows its switch, its name and a sample only.
local function LayTexts(p, look)
    local sec = p.textsSection
    local y = -40
    for _, row in ipairs(p.textRows) do
        local kind = row.kind
        local on = look.texts[kind].on == true
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, y)
        y = y - TEXT_ROW
        row.on:SetChecked(on)
        row.sample:SetText(SampleWords(kind, look))
        if on then
            row.name:SetTextColor(UI.RGB("text"))
            row.sample:Hide()
        else
            row.name:SetTextColor(UI.RGB("muted"))
            row.sample:Show()
        end
        if row.extra then
            if on then
                row.extra:ClearAllPoints()
                row.extra:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, y)
                row.extra:Show()
                y = y - TEXT_ROW
            else
                row.extra:Hide()
            end
        end
    end
    p.textsNote:ClearAllPoints()
    p.textsNote:SetPoint("TOPLEFT", sec, "TOPLEFT", 6, y - 4)
    p.textsNote:SetPoint("RIGHT", sec, "RIGHT", -4, 0)
    if p.textsNote.SetWordWrap then p.textsNote:SetWordWrap(true) end
    sec:SetHeight(-y + 34)
end

--------------------------------------------------------------------------------
-- PRESETS and WHEN
--------------------------------------------------------------------------------
-- CS.ApplyPreset(key): ClockStore's preset (EllesmereUI's with its live mana
-- colour when it is loaded).
function CS.ApplyPreset(key)
    local opts
    local pr = ST.ClockStore.Preset(key)
    if pr and pr.hostFill and ST.Media and ST.Media.EllesmereMana then
        local c = ST.Media.EllesmereMana()
        if type(c) == "table" then opts = { fill = Hex6(c[1], c[2], c[3]) } end
    end
    return ST.ClockStore.ApplyPreset(key, opts)
end

local function BuildPresets(p, parent)
    local sec = Section(parent, "PRESETS", 52)
    p.presetsSection = sec
    sec.sub = Note(sec, "a preset replaces the whole look; Undo puts yours back")
    sec.sub:SetPoint("BOTTOMRIGHT", sec.line, "TOPRIGHT", 0, 2)
    p.presetButtons = {}
    local prev
    for _, pr in ipairs(ST.ClockStore.PRESETS) do
        local b = SmallButton(sec, pr.name, math.max(90, #pr.name * 7 + 16), pr.name, pr.tip)
        b.id = pr.key
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", sec, "TOPLEFT", 6, -26) end
        b:SetScript("OnClick", function() CS.ApplyPreset(pr.key) end)
        p.presetButtons[#p.presetButtons + 1] = b
        prev = b
    end
    local undo = SmallButton(sec, "Undo preset", 90, "Undo preset", "Your look before the last preset.")
    undo:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    undo:SetScript("OnClick", function() ST.ClockStore.Undo() end)
    p.undoButton = undo
    local note = Note(sec, "no preset turns off the time or the 5SR line")
    note:SetPoint("LEFT", undo, "RIGHT", 10, 0)
    p.presetNote = note
    return sec
end

-- "Always visible" (2026-11-14): db.clockAlways, both lines -- the clock
-- stays up out of combat at any mana (ST.Visibility.Rule). Each host's own
-- visibility owner applies it; this only writes the key and asks it to.
ST:RegisterDefaults({ clockAlways = false })
local function RefreshVisibility()
    if ST.Clock and ST.Clock.Refresh and ST.Clock.frame then ST.Clock:Refresh() end
    if ST.UpdateVisibility then ST:UpdateVisibility() end
end
function CS.SetAlways(on)
    ST.db.clockAlways = on == true
    RefreshVisibility()
end
CS.ALWAYS_SWITCH = {
    text = "Always visible",
    tips = { "Always visible", "On: the clock stays on screen out of combat too, at any mana.",
        "Off: out of combat it shows under 90% mana and hides over 95%. Same as /st clock always." },
    get = function() return ST.db.clockAlways == true end,
    set = function(on) CS.SetAlways(on) end,
}
ST:AddSubcommand("clock", "always", function()
    CS.SetAlways(ST.db.clockAlways ~= true)
    ST:Print("mana clock: " .. (ST.db.clockAlways and "always visible"
        or "out of combat only under 90% mana (hides over 95%)"))
end, "always", "keep the clock on screen out of combat too")

local function BuildWhen(p, parent)
    local defs = { CS.ALWAYS_SWITCH }
    for _, def in ipairs(p.opts.when or {}) do defs[#defs + 1] = def end
    local sec = Section(parent, "WHEN", 30 + 22 * #defs + 18)
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
    local n = Note(sec, "In combat the clock is always up; out of combat it shows under 90% mana and hides over 95%, unless Always visible is on.")
    n:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, y - 2)
    n:SetPoint("RIGHT", sec, "RIGHT", -4, 0)
    return sec
end

--------------------------------------------------------------------------------
-- Refresh: the stored look into the preview and every control
--------------------------------------------------------------------------------
local function ShowIf(w, on)
    if not w then return end
    if on then w:Show() else w:Hide() end
end

-- The renderer's reason beside a control it cannot honour (spec 2.6), else
-- the control's own hint.
local function PutNotes(p)
    local notes = (p.view and p.view.look and p.view.look.notes) or {}
    for id, fs in pairs(p.notes) do
        local c = CS.byId[id]
        local why = c and c.note and notes[c.note]
        if why then
            fs:SetText(why)
        else
            fs:SetText(c and c.hint or "")
        end
    end
end

function CS.Refresh(p)
    if not p or not p.view then return end
    local look = ST.ClockStore.Look()
    p.look = look
    p.view:Apply(look)
    PutNotes(p)
    local W = p.widgets
    for _, c in ipairs(CS.CONTROLS) do
        local w = W[c.id]
        local v = c.get(look)
        if w then
            if c.kind == "buttons" then
                w.highlight(v)
            elseif c.kind == "slider" then
                w:SetValue(v)
            elseif c.kind == "dropdown" then
                w:SetItems(CS.TextureItems())
                w:SetValue(v)
                if w:GetText() == "" then w:SetText(tostring(v)) end
            elseif c.kind == "check" then
                w:SetChecked(v == true)
            elseif c.kind == "number" then
                if not (w.HasFocus and w:HasFocus()) then w:SetText(tostring(v)) end
            elseif c.kind == "step" then
                local names = CS.STEP_NAMES[c.field]
                w:SetText(names and names[v] or tostring(v))
            elseif c.kind == "swatch" then
                if c.alpha then w:SetHex(v[1], v[2]) elseif IsHex(v) then w:SetHex(v) end
            end
            -- the visible(look) rule: a control the look makes inert is hidden
            if c.id ~= "fill" then ShowIf(w, c.visible(look)) end
        end
    end
    if p.backAlphaText then p.backAlphaText:SetText(string.format("%d %%", math.floor(look.backAlpha * 100 + 0.5))) end
    LayTexts(p, look)
    if p.undoButton then ShowIf(p.undoButton, ST.ClockStore.HasUndo()) end
    for _, cb in ipairs(p.switches or {}) do cb:SetChecked(cb.def.get() and true or false) end
    if p.scroll then
        local h = 0
        for _, s in ipairs({ p.barSection, p.textsSection, p.presetsSection, p.whenSection }) do
            h = h + (s:GetHeight() or 0) + 12
        end
        p.scroll:SetContentHeight(h + 8)
    end
    CS.PaintPreview(p)
end

-- ST.ClockSettings.Build(content, opts) -> the Settings -> Clock pane.
-- opts.when: the line's own switches, each { text, tips, get, set }.
function CS.Build(content, opts)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    local p = { pane = pane, opts = opts or {}, chip = "fight", widgets = {}, notes = {} }
    pane.clockSettings = p -- marks this pane for the suites
    BuildPreview(p, pane)

    -- the rest scrolls under the preview
    local holder = CreateFrame("Frame", nil, pane)
    holder:SetPoint("TOPLEFT", p.previewSection, "BOTTOMLEFT", 0, -8)
    holder:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -12, 2)
    p.holder = holder
    local sf = UI.CreateScrollFrame(holder, 0, 0)
    p.scroll = sf
    local c = sf.content
    p.content = c

    local bar = BuildBar(p, c)
    bar:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -4)
    bar:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    local texts = BuildTexts(p, c)
    texts:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -12)
    texts:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    local presets = BuildPresets(p, c)
    presets:SetPoint("TOPLEFT", texts, "BOTTOMLEFT", 0, -12)
    presets:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    local when = BuildWhen(p, c)
    when:SetPoint("TOPLEFT", presets, "BOTTOMLEFT", 0, -12)
    when:SetPoint("RIGHT", holder, "RIGHT", 0, 0)

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
