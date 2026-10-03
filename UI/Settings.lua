-- Settings, both lines (T119, docs/SPEC-one-ui.md 7, mockup M6): one file
-- builds Settings -> General, Settings -> Review and Settings -> About on TBC
-- and on Forever. What differs is the table a line installs as
-- MD.SettingsLine (UI/Settings_TBC.lua on TBC, UI/Dashboard_Forever.lua on
-- Forever), never a branch on the client (apicheck rule 10).
--
--   General  left   SPELL TOOLTIPS  the block on heals, and on damage spells,
--                                   the detail key (where MD.SpellTip has
--                                   DETAIL_MODES)
--                   APPEARANCE      the Look, Text size, Window size
--                   WINDOWS         In combat, one window per ESC, Minimap
--                                   button, Reset window positions
--            right  MANA CLOCK      SettingsLine.clock
--                   ALERTS          SettingsLine.alerts (only when it has rows)
--                   TOOLS           SettingsLine.tools
--                   INTEGRATIONS    UI/ClockSettings.lua's pane, with
--                                   SettingsLine.integrations' switches
--   Review   left   RECORDING       SettingsLine.recording (recordingNote on
--                                   the title row)
--            right  MODEL           SettingsLine.model, then modelHint
--   About           the version, SettingsLine.client(), the blurb, COMMANDS
--                   from MD:Commands(), a line per module not loaded, the
--                   optional SettingsLine.aboutNote
--
-- The sections and their spacing are Forever's (T42, T70 of
-- UI/Dashboard_Forever.lua, moved here): two columns, the left 352 px wide
-- at x 4, the right from x 376 to the pane's edge, 12 px between panes, the
-- title at 0, the rule at -17, the first control at -27. Every pitch goes
-- through UI.Pitch, and a pane is laid out again when the fonts change, so a
-- column fits at every font offset (tools/settingscheck.lua measures it).
--
-- Rows are data:
--   { kind = "check", text, key | get / set, default, tips, live, after, mark, collect }
--   { kind = "slider", text, key | get / set, min, max, step, scale, percent,
--     default, width, tips, live, mark }
--   { kind = "dropdown", text, items (fn or list), get, set, width, mark }
--   { kind = "buttons", { text, onClick(button), tips, label = fn, enabled = fn,
--     color, width, mark }, ... }
--   { kind = "hint", text, mark, indent }
-- A key a line may not have registered is read through MD:Setting (a nil
-- answer falls back to the row's `default`), and written into MD.db.
--
-- Colours are names (UI.Tint), so a style switch repaints them (T107).
local _, MD = ...
local UI = MD.UI

local MS = {}
MD.Settings = MS

local PANE_GAP = 12
local LEFT_W = 352   -- the left column (M1)
local RIGHT_X = 376  -- where the right column starts
local FIRST_Y = -27  -- the first control under a section's rule
MS.PANE_GAP, MS.LEFT_W, MS.RIGHT_X = PANE_GAP, LEFT_W, RIGHT_X

-- The content area Settings gets on both lines: 860 x 560 less the nav's
-- column (108), its pads (16) and the view row (24) -- 736 x 520.
MS.CONTENT_W, MS.CONTENT_H = 736, 520

MS.BLURB = "Your spells rank by rank, your mana clock, and your fights recorded, replayed and coached."

local panes = {}  -- view id -> its pane, once built
MS.panes = panes

local function Line() return MD.SettingsLine or {} end
local function Round(v) return math.floor((tonumber(v) or 0) + 0.5) end
-- the theme's pitch (UI/Theme_Flat.lua), the plain number before it loads
local function Pitch(n) if UI.Pitch then return UI.Pitch(n) end return n end
local function Call(v, ...) if type(v) == "function" then return v(...) end return v end

local function SetEnabled(w, on)
    if not w then return end
    if on then w:Enable() else w:Disable() end
end

-- the views every line has, in order; a line adds its own before About
function MS.Views()
    local views = {
        { id = "general", text = "General" },
        -- T102 (docs/SPEC-next.md 7.4): the clock's look, with a preview
        { id = "clock", text = "Clock" },
        { id = "review", text = "Review" },
    }
    for _, v in ipairs(Line().views or {}) do views[#views + 1] = v end
    views[#views + 1] = { id = "about", text = "About" }
    return views
end

-- Does this module build the view? (General, Review, About)
function MS.Owns(view)
    return view == "general" or view == "review" or view == "about"
end

--------------------------------------------------------------------------------
-- Reading and writing a row's value
--------------------------------------------------------------------------------
local function Read(row)
    if row.get then return row.get() end
    local v = MD:Setting(row.key)
    if v == nil then v = row.default end
    return v
end

local function Live(row)
    if row.live == nil then return true end
    return Call(row.live) and true or false
end

local function CheckedOf(row)
    local v = Read(row)
    if v == nil then return false end
    return v ~= false
end

local function WriteCheck(row, on)
    if row.set then row.set(on) else MD.db[row.key] = on end
    if row.after then row.after(on) end
end

local function WriteSlider(row, value)
    local v = tonumber(value)
    if not v then return end
    if row.set then row.set(v); return end
    MD.db[row.key] = v / (row.scale or 1)
    if row.after then row.after(v) end
end

local function SliderValue(row)
    local v = tonumber(Read(row))
    if not v then return nil end
    return Round(v * (row.scale or 1))
end

--------------------------------------------------------------------------------
-- Sections and their layout
--------------------------------------------------------------------------------
-- A titled pane in a column ("left" / "right"), under `above` (nil: the
-- column's top). Its controls are laid out by Layout, from its items.
local function Section(pane, text, above, column)
    local sec = UI.CreateTitledPane(pane, text, LEFT_W, 40)
    if above then
        sec:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -PANE_GAP)
    elseif column == "right" then
        sec:SetPoint("TOPLEFT", pane, "TOPLEFT", RIGHT_X, -4)
    else
        sec:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    end
    if column == "right" then sec:SetPoint("RIGHT", pane, "RIGHT", -4, 0) end
    sec.items = {}
    pane.sections[#pane.sections + 1] = sec
    return sec
end

-- item = { region, x, top = fn (room above the region's own top: a slider's
-- label), height = fn, right = true (also anchored to the section's right) }
-- or { place = fn(sec, y) -> height } for a block that places itself.
local function Layout(sec)
    if sec.fixed then
        sec:SetHeight(sec.fixed())
        return
    end
    local y = FIRST_Y
    for _, it in ipairs(sec.items) do
        local h
        if it.place then
            h = it.place(sec, y)
        else
            local r = it.region
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", sec, "TOPLEFT", it.x or 5, y - (it.top and it.top() or 0))
            if it.right then r:SetPoint("RIGHT", sec, "RIGHT", 0, 0) end
            h = it.height()
        end
        y = y - h
    end
    sec:SetHeight(-y + 4)
end

local function LayoutPane(pane)
    for _, sec in ipairs(pane.sections or {}) do Layout(sec) end
    if pane.LayoutExtra then pane:LayoutExtra() end
end

local function Mark(pane, name, value)
    if name then pane[name] = value end
end

local function TextHeight(fs, min)
    local h = fs and fs:GetStringHeight() or 0
    if type(h) ~= "number" or h < (min or 0) then h = min or 0 end
    return h
end

-- The height of a string set to wrap at `width`: the client's own answer, or
-- one line of its font per width its text needs, whichever is taller (the
-- harness's metric does not wrap).
local function WrappedHeight(fs, width, min)
    local h = TextHeight(fs, min)
    if not (fs and width and width > 0) then return h end
    local tw = tonumber(UI.TextWidth(fs:GetText() or "", UI.FONT_SMALL, fs)) or 0
    local lines = math.max(1, math.ceil(tw / width - 0.001))
    local _, size = fs:GetFont()
    size = tonumber(size) or 10
    return math.max(h, lines * size)
end

-- A muted sentence, `x` in from the section's edge, to its right edge.
local function HintString(sec, text)
    local fs = sec:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    fs:SetJustifyH("LEFT")
    UI.Tint(fs, "text", "muted")
    fs:SetText(text)
    return fs
end

--------------------------------------------------------------------------------
-- The row kinds
--------------------------------------------------------------------------------
local function Tips(t)
    t = t or {}
    return t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8]
end

local BUILD = {}

function BUILD.check(pane, sec, row)
    local cb = UI.CreateCheckButton(sec, row.text, function(checked)
        WriteCheck(row, checked and true or false)
        MS.Refresh(pane.view)
    end, Tips(row.tips))
    sec.items[#sec.items + 1] = { region = cb, x = 5 + (row.indent or 0), height = function() return Pitch(20) end }
    pane.controls[#pane.controls + 1] = { kind = "check", ctl = cb, row = row }
    Mark(pane, row.mark, cb)
    if row.collect then
        pane[row.collect] = pane[row.collect] or {}
        local list = pane[row.collect]
        list[#list + 1] = { key = row.key, check = cb }
    end
    return cb
end

function BUILD.slider(pane, sec, row)
    local s = UI.CreateSlider(row.text, sec, row.min, row.max, row.width or 160, row.step or 1, function(value)
        WriteSlider(row, value)
    end, nil, row.percent and true or false, Tips(row.tips))
    -- the label sits above the slider (Pitch(14) of room), its box under it
    sec.items[#sec.items + 1] = {
        region = s, x = 5 + (row.indent or 15),
        top = function() return Pitch(14) + 4 end,
        height = function() return Pitch(14) + 4 + 10 + 15 + Pitch(10) end,
    }
    pane.controls[#pane.controls + 1] = { kind = "slider", ctl = s, row = row }
    Mark(pane, row.mark, s)
    return s
end

function BUILD.dropdown(pane, sec, row)
    local label = sec:CreateFontString(nil, "OVERLAY", UI.FONT)
    label:SetText(row.text)
    local dd = UI.CreateDropdown(sec, row.width or 160, 18, function(id)
        if row.set then row.set(id) end
    end)
    dd:SetPoint("LEFT", label, "RIGHT", 8, 0)
    dd:SetItems(Call(row.items) or {})
    if row.get then dd:SetValue(row.get()) end
    sec.items[#sec.items + 1] = { region = label, x = 5,
        top = function() return -2 end,
        height = function() return Pitch(26) end }
    pane.controls[#pane.controls + 1] = { kind = "dropdown", ctl = dd, row = row }
    Mark(pane, row.mark, dd)
    return dd
end

function BUILD.buttons(pane, sec, row)
    local prev, first
    for _, def in ipairs(row) do
        local text = Call(def.label) or def.text
        local w = def.width or math.max(80, Round(UI.TextWidth(text, UI.FONT) + 24))
        local b = UI.CreateButton(sec, text, def.color or "accent-hover", { w, 20 }, false, false,
            nil, nil, Tips(def.tips))
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else first = b end
        b:SetScript("OnClick", function(self)
            if def.onClick then def.onClick(self) end
            MS.Refresh(pane.view)
        end)
        pane.controls[#pane.controls + 1] = { kind = "button", ctl = b, row = def }
        Mark(pane, def.mark, b)
        prev = b
    end
    if first then
        sec.items[#sec.items + 1] = { region = first, x = 5 + (row.indent or 0),
            height = function() return Pitch(26) end }
    end
    return first
end

function BUILD.hint(pane, sec, row)
    local fs = HintString(sec, row.text)
    sec.items[#sec.items + 1] = { region = fs, x = 5 + (row.indent or 0), right = true,
        top = function() return 2 end,
        height = function() return TextHeight(fs, 10) + Pitch(8) end }
    Mark(pane, row.mark, fs)
    return fs
end

local function BuildRows(pane, sec, rows)
    for _, row in ipairs(rows or {}) do
        local b = BUILD[row.kind]
        if b and (row.when == nil or Call(row.when)) then b(pane, sec, row) end
    end
end

--------------------------------------------------------------------------------
-- General -> SPELL TOOLTIPS (both lines: spec 6, the block's two halves)
--------------------------------------------------------------------------------
local function TooltipRows()
    return {
        { kind = "check", text = "Add SpellTuner lines to heal tooltips", key = "spellTooltip", default = true,
          mark = "tooltipCheck",
          tips = { "Heal tooltips", "SpellTuner's lines under the game's own tooltip of a heal,",
                   "on your bars and in the spellbook." } },
        { kind = "check", text = "...and to damage spells", key = "spellTooltipDamage", default = true,
          mark = "damageTipCheck",
          tips = { "Damage spells", "The same lines under the tooltip of a damage spell." } },
        -- T37 (5.6, decision 5): the key that shows the block's detail lines
        { kind = "dropdown", text = "Detail lines", width = 120, mark = "detailDropdown",
          when = function() return MD.SpellTip ~= nil and MD.SpellTip.DETAIL_MODES ~= nil end,
          items = function() return MD.SpellTip.DETAIL_MODES end,
          get = function() return MD.SpellTip:DetailMode() end,
          set = function(id) MD.db.spellTooltipDetail = id end },
    }
end

--------------------------------------------------------------------------------
-- General -> APPEARANCE (Forever's T42 / T70 / T102 section, as it was)
--------------------------------------------------------------------------------
-- T70 (U15): the two knobs named by what they change, a sentence under each.
local TEXT_SIZE_HINT = "Every SpellTuner text, one size bigger or smaller."
local WINDOW_SIZE_HINT = "Every SpellTuner window, bigger or smaller."
-- T102 (mockup M7b): the Look dropdown and "Use my class colour" on the
-- section's first row, the reload line under them; the sliders LOOK_H lower.
local LOOK_H = 44

local HINT_W = 150 -- each slider's sentence wraps at its slider's width

local function BuildAppearance(pane, above)
    local sec = Section(pane, "APPEARANCE", above, "left")

    local c
    if MD.ClockSettings and MD.ClockSettings.LookControls then
        c = MD.ClockSettings.LookControls(sec, 150)
        pane.lookControls = c
    end

    -- 4.2: -2..+2 (decision 13), every SpellTuner font. T80 (C1):
    -- UI.SetFontOffset (UI/Theme_Flat.lua) applies and saves it.
    local lo, hi = UI.FONT_OFFSET_MIN or -2, UI.FONT_OFFSET_MAX or 2
    local font = UI.CreateSlider("Text size", sec, lo, hi, 150, 1, function(value)
        UI.SetFontOffset(value)
    end, nil, false,
        "Text size", "Every SpellTuner text a size bigger or smaller, -2 to +2.",
        "Spells' rows and cards move apart with it.")
    pane.fontSlider = font
    pane.fontHint = HintString(sec, TEXT_SIZE_HINT)
    pane.fontHint:SetWidth(HINT_W)

    -- 4.3: 70-120 %, through the window manager (the saved places converted);
    -- applied on the mouse-up (the window must not scale under the pointer)
    local slo, shi = Round(MD.Win.SCALE_MIN * 100), Round(MD.Win.SCALE_MAX * 100)
    local scale = UI.CreateSlider("Window size", sec, slo, shi, 150, 5, nil, function(value)
        MD.Win:SetScale((tonumber(value) or 100) / 100)
    end, true,
        "Window size", "Makes the main, replay and practice windows bigger or smaller,",
        "along with the console and the copy box.")
    pane.scaleSlider = scale
    pane.scaleHint = HintString(sec, WINDOW_SIZE_HINT)
    pane.scaleHint:SetWidth(HINT_W)

    sec.items[#sec.items + 1] = { place = function(s, y)
        if c then
            c.label:ClearAllPoints()
            c.label:SetPoint("TOPLEFT", s, "TOPLEFT", 5, y - 2)
            c.classCheck:ClearAllPoints()
            c.classCheck:SetPoint("TOPLEFT", s, "TOPLEFT", 200, y - 4)
            c.reload:ClearAllPoints()
            c.reload:SetPoint("TOPLEFT", s, "TOPLEFT", 5, y - 22)
            c.reload:SetPoint("RIGHT", s, "RIGHT", 0, 0)
        end
        local look = c and Pitch(LOOK_H) or 0
        local lh = Pitch(14)
        local top = y - look - lh - 4
        font:ClearAllPoints()
        font:SetPoint("TOPLEFT", s, "TOPLEFT", 5, top)
        scale:ClearAllPoints()
        scale:SetPoint("TOPLEFT", s, "TOPLEFT", 190, top)
        pane.fontHint:ClearAllPoints()
        pane.fontHint:SetPoint("TOPLEFT", font, "BOTTOMLEFT", 0, -20)
        pane.scaleHint:ClearAllPoints()
        pane.scaleHint:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, -20)
        local hint = math.max(WrappedHeight(pane.fontHint, HINT_W, 10), WrappedHeight(pane.scaleHint, HINT_W, 10))
        return look + lh + 4 + 10 + 20 + hint + Pitch(6)
    end }
    pane.controls[#pane.controls + 1] = { kind = "custom", refresh = function()
        if c then c:Refresh() end
        local u = type(MD.db.ui) == "table" and MD.db.ui or {}
        font:SetValue(Round(UI.fontOffset or u.fontOffset))
        scale:SetValue(MD.Win:ScalePercent())
    end }
    return sec
end

--------------------------------------------------------------------------------
-- General -> WINDOWS (Forever's section; T79's Minimap button, both lines)
--------------------------------------------------------------------------------
local function WindowsRows()
    return {
        -- 6.6, decision 4
        { kind = "dropdown", text = "In combat", width = 160, mark = "combatDropdown",
          items = function() return MD.Win.COMBAT_MODES end,
          get = function() return MD.Win:CombatMode() end,
          set = function(id) MD.Win:SetCombat(id) end },
        -- 6.5: off is the fallback, one UISpecialFrames entry per window
        { kind = "check", text = "Close one window per ESC", mark = "escCheck",
          get = function() return MD.Win:EscStackOn() end,
          set = function(on) MD.Win:SetEscStack(on) end,
          tips = { "Close one window per ESC", "On: each ESC closes the window opened last, then the next.",
                   "Off: one ESC closes every SpellTuner window at once." } },
        -- T79 (P36, mockup M1): UI/MinimapButton.lua owns the button and db.minimap
        { kind = "check", text = "Minimap button", mark = "minimapCheck",
          get = function() return not (type(MD.db.minimap) == "table" and MD.db.minimap.hide) end,
          set = function(on)
              MD.db.minimap = MD.db.minimap or {}
              MD.db.minimap.hide = not on
              if MD.UpdateMinimapButton then MD:UpdateMinimapButton() end
          end,
          tips = { "Minimap button", "The SpellTuner button on the minimap's rim.",
                   "Left-click opens the window, right-click opens Settings; drag it round the map." } },
        { kind = "hint", text = "Left-click opens the window, right-click opens Settings.", indent = 19,
          mark = "minimapHint" },
        { kind = "buttons",
          { text = "Reset window positions", width = 170, mark = "resetButton",
            tips = { "Reset window positions",
                     "Every SpellTuner window back at its default place and size (/st ui reset)." },
            onClick = function()
                MD.Win:Reset()
                MD:Print("windows: every position and size reset")
            end } },
    }
end

--------------------------------------------------------------------------------
-- General -> INTEGRATIONS (UI/ClockSettings.lua's pane, under TOOLS)
--------------------------------------------------------------------------------
local function IntegrationsHeight(sec)
    local n = 0
    for _, fs in ipairs(sec.found or {}) do if fs:IsShown() then n = n + 1 end end
    if n == 0 then n = 1 end
    local lh = TextHeight(sec.found and sec.found[1], 10)
    local extra = 0
    for i, cb in ipairs(sec.switches or {}) do
        if i > 2 and cb:IsShown() then extra = extra + Pitch(20) end
    end
    return 25 + n * (lh + 2) + 6 + Pitch(14) + extra + 6 + TextHeight(sec.hint, 10) + 6
end

local function BuildIntegrations(pane, above)
    if not (MD.ClockSettings and MD.ClockSettings.BuildIntegrations) then return nil end
    local sec = MD.ClockSettings.BuildIntegrations(pane, LEFT_W, 120, Line().integrations)
    sec:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -PANE_GAP)
    sec:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    sec.fixed = function() return IntegrationsHeight(sec) end
    pane.sections[#pane.sections + 1] = sec
    pane.integrations = sec
    pane.controls[#pane.controls + 1] = { kind = "custom", refresh = function() sec:Refresh() end }
    return sec
end

--------------------------------------------------------------------------------
-- The panes
--------------------------------------------------------------------------------
local function NewPane(content, view)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    pane.view = view
    pane.sections, pane.controls = {}, {}
    return pane
end

local function BuildGeneral(content)
    local pane = NewPane(content, "general")
    local L = Line()

    local tips = Section(pane, "SPELL TOOLTIPS", nil, "left")
    BuildRows(pane, tips, TooltipRows())
    local look = BuildAppearance(pane, tips)
    local windows = Section(pane, "WINDOWS", look, "left")
    BuildRows(pane, windows, WindowsRows())
    pane.windowsPane = { combat = pane.combatDropdown, esc = pane.escCheck, font = pane.fontSlider,
        scale = pane.scaleSlider, reset = pane.resetButton } -- for tools/dashui.lua

    local clock = Section(pane, "MANA CLOCK", nil, "right")
    BuildRows(pane, clock, L.clock)
    local last = clock
    if L.alerts and #L.alerts > 0 then
        local alerts = Section(pane, "ALERTS", last, "right")
        BuildRows(pane, alerts, L.alerts)
        last = alerts
    end
    local tools = Section(pane, "TOOLS", last, "right")
    BuildRows(pane, tools, L.tools)
    BuildIntegrations(pane, tools) -- T102
    return pane
end

local function BuildReview(content)
    local pane = NewPane(content, "review")
    local L = Line()

    local rec = Section(pane, "RECORDING", nil, "left")
    if L.recordingNote then
        local note = rec:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        note:SetPoint("BOTTOMRIGHT", rec.line, "TOPRIGHT", 0, 3)
        note:SetJustifyH("RIGHT")
        UI.Tint(note, "text", "muted")
        note:SetText(Call(L.recordingNote) or "")
        pane.reviewNote = note
    end
    BuildRows(pane, rec, L.recording)

    local model = Section(pane, "MODEL", nil, "right")
    BuildRows(pane, model, L.model)
    if L.modelHint then BuildRows(pane, model, { { kind = "hint", text = L.modelHint, mark = "modelHint" } }) end
    return pane
end

--------------------------------------------------------------------------------
-- About (T70, P26, review U24, mockup M1; one page on both lines since T119):
-- the version, the client and every command MD:Commands() lists, usage in the
-- numbers font, the text cut at its first "; " (the whole on hover). Rebuilt
-- on every show, so a module that loaded since adds its commands; a module
-- not loaded gets one line. The rows run in two columns when one would not
-- fit the view.
--------------------------------------------------------------------------------
local ABOUT_ROW_H = 17
local USAGE_W = 196      -- one column
local USAGE_W2 = 150     -- two columns
local COLUMN_GAP = 16

-- The command's text up to its first "; " -- the rest is the hover's.
local function ShortText(text)
    local cut = text:find("; ", 1, true)
    if cut then return text:sub(1, cut - 1), true end
    return text, false
end
MS.ShortText = ShortText

local function AboutRow(pane, i)
    local r = pane.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, pane.list)
    r:SetHeight(ABOUT_ROW_H)
    r:EnableMouse(true)
    r.usage = r:CreateFontString(nil, "OVERLAY", UI.FONT_NUM or UI.FONT)
    r.usage:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.usage:SetJustifyH("LEFT")
    r.usage:SetWordWrap(false)
    r.text = r:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    pane.rows[i] = r
    return r
end

-- Where row i of n goes: one column while it fits, else two.
local function PlaceRows(pane, n)
    local list = pane.list
    local pitch = Pitch(ABOUT_ROW_H)
    local noteH = pane.note and pane.note:IsShown() and pane.noteHeight() or 0
    local listTop = pane.ListTop()
    local room = MS.CONTENT_H - listTop - 27 - 4 - noteH
    local perCol = n
    if n * pitch > room then perCol = math.ceil(n / 2) end
    local two = perCol < n
    local colW = two and math.floor((MS.CONTENT_W - 8 - COLUMN_GAP) / 2) or nil
    local usageW = two and USAGE_W2 or USAGE_W
    for i = 1, n do
        local r = pane.rows[i]
        local col = math.floor((i - 1) / perCol)
        local k = (i - 1) % perCol
        local x = 5 + col * ((colW or 0) + COLUMN_GAP)
        r:ClearAllPoints()
        r:SetHeight(pitch)
        r:SetPoint("TOPLEFT", list, "TOPLEFT", x, -27 - k * pitch)
        if two then r:SetWidth(colW - 5) else r:SetPoint("RIGHT", list, "RIGHT", 0, 0) end
        r.usage:SetWidth(usageW - 6)
        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", r, "LEFT", usageW, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    end
    pane.columns = two and 2 or 1
    list:SetHeight(27 + perCol * pitch + 4)
end

local function RefreshAbout(pane)
    local L = Line()
    pane.version:SetText("SpellTuner " .. tostring(MD.version))
    pane.client:SetText(tostring(Call(L.client) or ""))

    local n = 0
    for _, e in ipairs(MD:Commands()) do
        if not e.hidden and type(e.usage) == "string" and e.usage ~= "" then
            n = n + 1
            local r = AboutRow(pane, n)
            local short, cut = ShortText(e.text or "")
            r.usage:SetText(e.usage)
            UI.Tint(r.usage, "text", "text")
            r.text:SetText(short)
            UI.Tint(r.text, "text", "text2")
            r.command = e.name
            r.fullText = e.text or ""
            -- the whole of it on hover: a cut text, and a usage or text a
            -- narrow column may clip
            UI.SetTooltips(r, "ANCHOR_TOPLEFT", 0, 3, e.usage, e.text or "")
            if not cut and pane.columns ~= 2 then r.tooltips = nil end
            r:Show()
        end
    end
    for _, m in ipairs(MD.modules or {}) do
        if MD:ModuleState(m.name) ~= "loaded" then
            n = n + 1
            local r = AboutRow(pane, n)
            r.usage:SetText(m.label)
            UI.Tint(r.usage, "text", "text")
            r.text:SetText("off: its commands are listed here once it is on (Settings -> Modules)")
            UI.Tint(r.text, "text", "muted")
            r.command, r.tooltips, r.fullText = nil, nil, nil
            r:Show()
        end
    end
    for i = n + 1, #pane.rows do pane.rows[i]:Hide() end
    pane.shown = n
    PlaceRows(pane, n)
    -- a second pass: the first may have chosen two columns after the
    -- tooltips were decided
    for i = 1, n do
        local r = pane.rows[i]
        if r.fullText and r.tooltips == nil and pane.columns == 2 then
            UI.SetTooltips(r, "ANCHOR_TOPLEFT", 0, 3, r.usage:GetText(), r.fullText)
        end
    end
end

local function BuildAbout(content)
    local pane = NewPane(content, "about")
    pane.rows = {}
    pane.about = true -- marks this pane for tools/wincheck.lua

    local version = pane:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    version:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    pane.version = version

    local client = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    client:SetPoint("LEFT", version, "RIGHT", 10, 0)
    UI.Tint(client, "text", "muted")
    pane.client = client

    local blurb = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    blurb:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -4)
    blurb:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    blurb:SetJustifyH("LEFT")
    UI.Tint(blurb, "text", "text2")
    blurb:SetText(MS.BLURB)
    pane.blurb = blurb

    local list = UI.CreateTitledPane(pane, "COMMANDS", LEFT_W, 60)
    list:SetPoint("TOPLEFT", blurb, "BOTTOMLEFT", 0, -14)
    list:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    local both = list:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    both:SetPoint("BOTTOMRIGHT", list.line, "TOPRIGHT", 0, 3)
    UI.Tint(both, "text", "muted")
    both:SetText("/st and /md both answer")
    pane.list = list

    -- where the list starts, from the pane's top
    function pane.ListTop()
        return 4 + TextHeight(version, 14) + 4 + TextHeight(blurb, 10) + 14
    end

    local note = Line().aboutNote
    if note then
        local sec = UI.CreateTitledPane(pane, note.title, LEFT_W, 40)
        sec:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -PANE_GAP)
        sec:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
        local how = sec:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        how:SetPoint("TOPLEFT", sec, "TOPLEFT", 5, -24)
        how:SetPoint("RIGHT", sec, "RIGHT", -5, 0)
        how:SetJustifyH("LEFT")
        UI.Tint(how, "text", "text2")
        how:SetText(note.text)
        pane.note, pane.noteText = sec, how
        function pane.noteHeight() return 24 + TextHeight(how, 10) + 6 + PANE_GAP end
        function pane:LayoutExtra() sec:SetHeight(24 + TextHeight(how, 10) + 6) end
    end
    return pane
end

--------------------------------------------------------------------------------
-- MS.Build(view, content) -> the pane; MS.Refresh(view) re-reads it
--------------------------------------------------------------------------------
function MS.Build(view, content)
    local pane
    if view == "general" then pane = BuildGeneral(content)
    elseif view == "review" then pane = BuildReview(content)
    elseif view == "about" then pane = BuildAbout(content)
    else return nil end
    panes[view] = pane
    MS.Refresh(view)
    return pane
end

local function RefreshControls(pane)
    for _, c in ipairs(pane.controls) do
        local row, ctl = c.row, c.ctl
        if c.kind == "check" then
            local live = Live(row)
            ctl:SetChecked(live and CheckedOf(row) or false)
            SetEnabled(ctl, live)
        elseif c.kind == "slider" then
            local live = Live(row)
            local v = live and SliderValue(row)
            if v then ctl:SetValue(v) end
            SetEnabled(ctl, live)
        elseif c.kind == "dropdown" then
            if row.get then ctl:SetValue(row.get()) end
        elseif c.kind == "button" then
            if row.label then ctl:SetText(Call(row.label)) end
            if row.enabled then SetEnabled(ctl, Call(row.enabled) and true or false) end
        elseif c.kind == "custom" then
            c.refresh()
        end
    end
    if pane.reviewNote then pane.reviewNote:SetText(Call(Line().recordingNote) or "") end
end

function MS.Refresh(view)
    if view == nil then
        for v in pairs(panes) do MS.Refresh(v) end
        return
    end
    local pane = panes[view]
    if not pane then return end
    if view == "about" then
        RefreshAbout(pane)
    else
        RefreshControls(pane)
    end
    LayoutPane(pane)
end

-- every pitch follows the font offset: lay the panes out again (T77's
-- FONTS_CHANGED, fired once the kit's fonts are re-sized)
if MD.RegisterCallback then
    MD:RegisterCallback("FONTS_CHANGED", function() MS.Refresh() end)
    -- T70: a module's keys go live as it loads, and About lists its commands
    MD:RegisterCallback("MODULE_LOADED", function() MS.Refresh() end)
end
