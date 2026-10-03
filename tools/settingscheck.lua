-- tools/run.sh [--flavour forever|tbc] tools/settingscheck.lua
--
-- T119 (docs/SPEC-one-ui.md 7, 10 W7; mockup M6): Settings is one file on both
-- lines, UI/Settings.lua (MD.Settings), built from the rows each line installs
-- as MD.SettingsLine (UI/Settings_TBC.lua on TBC, UI/Dashboard_Forever.lua on
-- Forever). The flavour's whole TOC is loaded with the stub's geometry on and
-- the fake hosts installed before it (tools/stub_hosts.lua, as
-- tools/clocksettings.lua does), so INTEGRATIONS has something to say.
--
-- Both flavours:
--   1. the Settings views, in order (TBC general, clock, review, about;
--      Forever general, clock, review, modules, about);
--   2. General's left column SPELL TOOLTIPS, APPEARANCE, WINDOWS and its right
--      MANA CLOCK, (TBC: ALERTS), TOOLS, INTEGRATIONS; Review's RECORDING |
--      MODEL;
--   3. every view fits its 736 x 520 content area at font offsets -2..+2:
--      every titled pane inside it, the panes of a column apart, every shown
--      control inside its pane;
--   4. each check writes its key and re-reads it on Refresh; each slider
--      writes its scaled key;
--   5. About: "SpellTuner <version>", the line's client words, the shared
--      blurb (never "TBC Anniversary"), one row per MD:Commands() row with a
--      usage;
--   6. the Detail lines dropdown is drawn only where MD.SpellTip has
--      DETAIL_MODES, and writes spellTooltipDetail;
--   7. every string the three views draw, and every tooltip line, is ASCII
--      with no bare pipe.
-- TBC only:
--   8. every control of the parent's UI/Options_General.lua (its keys and
--      button words, captured on 535cff4) is in its new place per the task's
--      map; Show rest time and Show mana cooldown are not on General;
--   9. Show now runs MD.Widget:Preview; Customise... selects Settings -> Clock;
--  10. MD:ShowOptionsFrame() opens General, ("about") About; MD.optionsFrame
--      is nil;
--  11. the Settings group is 860 x 560 with no grip; Spells is still 1036 x 646.
-- Forever only:
--  12. Measure is on Review / MODEL with the ~ sentence; TOOLS holds Debug
--      console and Copy /st dump only;
--  13. RECORDING is drawn disabled with "needs the Replay module - off" while
--      the module is off, and live once it loads (MODULE_LOADED).
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")
local root = arg[1] or "."

local flavour = os.getenv("ST_FLAVOUR")
if flavour == nil or flavour == "" then flavour = "tbc" end
if flavour ~= "forever" and flavour ~= "tbc" then
    print("skip: settingscheck.lua runs under tbc, forever only")
    os.exit(3)
end
local forever = flavour == "forever"

local T = dofile(here .. "/lib/t.lua")
local check = T.check

dofile(here .. "/wowstub.lua")
local S = _G.STUB
S.root = root
S.flavour = flavour
local H = dofile(here .. "/stub_hosts.lua")

local MD = {}
local toc = "SpellTuner_TBC.toc"
if forever then
    S.UseProfile("forever")
    toc = "SpellTuner_Mainline.toc"
end
S.Geometry(true)

H.InstallLDB()
if forever then H.InstallEllesmere() else H.InstallElvUI() end

local files = S.TocFiles(toc)
S.loadedFiles = files
local navGroups = {}
local loadedOK, loadErr = pcall(function()
    for _, rel in ipairs(files) do
        S.Load({ rel }, "SpellTuner", MD)
        if rel == "UI/Style.lua" then
            local make = MD.UI.CreateNavFrame
            MD.UI.CreateNavFrame = function(title, name, w, h, groups, ...)
                if name == "SpellTunerDashboard" then navGroups = groups end
                return make(title, name, w, h, groups, ...)
            end
        end
    end
end)
if not loadedOK then print("load: " .. tostring(loadErr)) end
H.AddOnMeta(MD, { EllesmereUI = { Version = "9.3.4" } })
S.Fire("ADDON_LOADED", "SpellTuner")
S.Fire("PLAYER_LOGIN")
S.Fire("PLAYER_ENTERING_WORLD")
if MD.db then MD.db.locked = true end
if forever and MD.db and type(MD.db.clock) == "table" then MD.db.clock.locked = true end

local UI = MD.UI or {}
local MS = MD.Settings or {}

local function Try(name, fn)
    local okR, cond, detail = pcall(fn)
    if not okR then return check(name, false, "raised: " .. tostring(cond)) end
    return check(name, cond, detail)
end
local function Click(b)
    local fn = b and b.GetScript and b:GetScript("OnClick")
    if fn then fn(b, "LeftButton") end
end
local function Pick(dd, id)
    if not dd then return false end
    for i, it in ipairs(dd.items or {}) do
        if it.id == id and dd.rows[i] then
            dd.rows[i]:GetScript("OnClick")(dd.rows[i])
            return true
        end
    end
    return false
end
local function Type(slider, text)
    local eb = slider and slider.currentEditBox
    if not eb then return end
    eb:SetText(text)
    eb:GetScript("OnEnterPressed")(eb)
end

local function Pane(view)
    MD:SelectView("settings", view)
    return MS.panes and MS.panes[view]
end

--------------------------------------------------------------------------------
-- Geometry, relative to a base frame of a given size (tools/clocksettings.lua's)
--------------------------------------------------------------------------------
local function PointXY(rect, p)
    local x = p:find("LEFT") and rect.l or (p:find("RIGHT") and rect.r) or (rect.l + rect.r) / 2
    local y = p:find("TOP") and rect.t or (p:find("BOTTOM") and rect.b) or (rect.b + rect.t) / 2
    return x, y
end
local function Size(r)
    if r.kind == "FontString" then
        -- a string given a width wraps at it, as the client does (the stub's
        -- metric does not wrap): that width, one line per width it needs
        local w, h = r:GetStringWidth(), r:GetStringHeight()
        local set = rawget(r, "w")
        if type(set) == "number" and set > 0 and w > set then
            return set, h * math.ceil(w / set - 0.001)
        end
        return w, h
    end
    return r:GetWidth(), r:GetHeight()
end
local function Rect(r, base, bw, bh, depth)
    depth = depth or 0
    if r == base then return { l = 0, t = 0, r = bw, b = -bh } end
    if not r or depth > 14 then return nil end
    local pts = r.points or {}
    if #pts == 0 then return nil end
    local box = {}
    for _, pt in ipairs(pts) do
        -- the short form SetPoint(p, x, y): the parent's same point
        if type(pt[2]) == "number" or (pt[2] == nil and type(pt[3]) == "number") then
            pt = { pt[1], nil, pt[1], pt[2] or 0, pt[3] or 0 }
        end
        local rr = Rect(pt[2] or r.parentFrame, base, bw, bh, depth + 1)
        if not rr then return nil end
        local x, y = PointXY(rr, pt[3] or pt[1])
        x, y = x + (pt[4] or 0), y + (pt[5] or 0)
        local p = pt[1]
        if p:find("LEFT") then box.l = x elseif p:find("RIGHT") then box.r = x else box.cx = x end
        if p:find("TOP") then box.t = y elseif p:find("BOTTOM") then box.b = y else box.cy = y end
    end
    local w, h = Size(r)
    if box.l and not box.r then box.r = box.l + w
    elseif box.r and not box.l then box.l = box.r - w
    elseif not box.l then box.l = (box.cx or 0) - w / 2; box.r = box.l + w end
    if box.t and not box.b then box.b = box.t - h
    elseif box.b and not box.t then box.t = box.b + h
    elseif not box.t then box.t = (box.cy or 0) + h / 2; box.b = box.t - h end
    return box
end
local EPS = 0.001
local function Inside(a, b)
    return a.l >= b.l - EPS and a.r <= b.r + EPS and a.b >= b.b - EPS and a.t <= b.t + EPS
end
local function R(r) return r and string.format("[%.0f..%.0f x %.0f..%.0f]", r.l, r.r, r.b, r.t) or "nil" end

local VIEW_W, VIEW_H = 736, 520

local function Under(f, top)
    local p, guard = f.parentFrame, 0
    while p and guard < 30 do
        if p == top then return true end
        p, guard = p.parentFrame, guard + 1
    end
    return false
end
-- shown: it and every ancestor up to `top`
local function Visible(f, top)
    local p, guard = f, 0
    while p and p ~= top and guard < 30 do
        if p.IsShown and not p:IsShown() then return false end
        p, guard = p.parentFrame, guard + 1
    end
    return true
end
local function TitledUnder(parent)
    local out = {}
    for _, f in ipairs(S.allFrames) do
        if f.title and f.line and f.parentFrame == parent then out[#out + 1] = f end
    end
    return out
end
-- the pane's sections by column (x < RIGHT_X: left), top to bottom
local function Columns(pane)
    local left, right = {}, {}
    for _, sec in ipairs(TitledUnder(pane)) do
        local r = Rect(sec, pane, VIEW_W, VIEW_H)
        if r then
            local col = r.l < (MS.RIGHT_X or 376) - 1 and left or right
            col[#col + 1] = { sec = sec, r = r }
        end
    end
    local function ByTop(a, b) return a.r.t > b.r.t end
    table.sort(left, ByTop)
    table.sort(right, ByTop)
    return left, right
end
local function Titles(col)
    local out = {}
    for _, c in ipairs(col) do out[#out + 1] = c.sec.title:GetText() end
    return table.concat(out, ",")
end
local function SectionTitled(pane, title)
    for _, sec in ipairs(TitledUnder(pane)) do
        if sec.title:GetText() == title then return sec end
    end
end

--------------------------------------------------------------------------------
T.section("1. the views")
--------------------------------------------------------------------------------
check("UI/Settings.lua loaded: MD.Settings and the line's MD.SettingsLine",
    loadedOK and type(MS.Build) == "function" and type(MD.SettingsLine) == "table",
    loadErr and tostring(loadErr))

Try("the Settings views are the table's, in order", function()
    MD:SelectView("settings", "general")
    local ids = {}
    for _, g in ipairs(navGroups) do
        if g.id == "settings" then
            for _, v in ipairs(g.views or {}) do ids[#ids + 1] = v.id end
        end
    end
    local want = forever and "general,clock,review,modules,about" or "general,clock,review,about"
    return table.concat(ids, ",") == want, table.concat(ids, ",")
end)

--------------------------------------------------------------------------------
T.section("2. the panes in their columns")
--------------------------------------------------------------------------------
Try("General: SPELL TOOLTIPS, APPEARANCE, WINDOWS | MANA CLOCK, " .. (forever and "" or "ALERTS, ")
      .. "TOOLS, INTEGRATIONS; Review: RECORDING | MODEL", function()
    local gl, gr = Columns(Pane("general"))
    local rl, rr = Columns(Pane("review"))
    local wantR = forever and "MANA CLOCK,TOOLS,INTEGRATIONS" or "MANA CLOCK,ALERTS,TOOLS,INTEGRATIONS"
    local got = Titles(gl) .. " | " .. Titles(gr) .. " ; " .. Titles(rl) .. " | " .. Titles(rr)
    return Titles(gl) == "SPELL TOOLTIPS,APPEARANCE,WINDOWS" and Titles(gr) == wantR
        and Titles(rl) == "RECORDING" and Titles(rr) == "MODEL", got
end)

--------------------------------------------------------------------------------
T.section("3. every view fits 736 x 520 at offsets -2..+2")
--------------------------------------------------------------------------------
Try("every titled pane inside the view, a column's panes apart, every shown control inside its pane", function()
    local bad = {}
    local base = { l = 0, t = 0, r = VIEW_W, b = -VIEW_H }
    for _, o in ipairs({ -2, -1, 0, 1, 2 }) do
        UI.SetFontOffset(o)
        for _, view in ipairs({ "general", "review", "about" }) do
            local pane = Pane(view)
            MS.Refresh(view)
            local secs = TitledUnder(pane)
            for _, sec in ipairs(secs) do
                local r = Rect(sec, pane, VIEW_W, VIEW_H)
                if not r or not Inside(r, base) then
                    bad[#bad + 1] = string.format("%+d %s %s %s", o, view, sec.title:GetText(), R(r))
                end
                for _, f in ipairs(S.allFrames) do
                    if Under(f, sec) and Visible(f, sec) and f.points and #f.points > 0
                       and not (f.kind == "FontString" and (f:GetText() or "") == "") then
                        local fr = Rect(f, pane, VIEW_W, VIEW_H)
                        -- the title rule's 1-px shadow (UI.CreateTitledPane)
                        -- sits a pixel right of the rule by design
                        if fr and r and not Inside(fr, { l = r.l, t = r.t, r = r.r + 1, b = r.b }) then
                            bad[#bad + 1] = string.format("%+d %s %s: %s %s outside %s", o, view,
                                sec.title:GetText(), tostring(f.kind),
                                tostring(f.GetText and f:GetText() or f.label and f.label:GetText()), R(fr), R(r))
                        end
                    end
                end
            end
            local l, rcol = Columns(pane)
            for _, col in ipairs({ l, rcol }) do
                for i = 2, #col do
                    if col[i].r.t > col[i - 1].r.b + EPS then
                        bad[#bad + 1] = string.format("%+d %s %s overlaps %s", o, view,
                            col[i].sec.title:GetText(), col[i - 1].sec.title:GetText())
                    end
                end
            end
            if view == "about" and pane then
                for i = 1, pane.shown or 0 do
                    local rr = Rect(pane.rows[i], pane, VIEW_W, VIEW_H)
                    if not rr or not Inside(rr, base) then
                        bad[#bad + 1] = string.format("%+d about row %d %s", o, i, R(rr))
                    end
                end
            end
        end
    end
    UI.SetFontOffset(0)
    return #bad == 0, table.concat(bad, "; ", 1, math.min(#bad, 6))
end)

--------------------------------------------------------------------------------
T.section("4. the controls write their keys")
--------------------------------------------------------------------------------
Try("each live check writes its key and re-reads it; each slider writes its scaled key", function()
    local bad, checks, sliders = {}, 0, 0
    for _, view in ipairs({ "general", "review" }) do
        local pane = Pane(view)
        for _, c in ipairs(pane.controls) do
            local row = c.row
            if c.kind == "check" and row.key and c.ctl:IsEnabled() then
                checks = checks + 1
                local was = c.ctl:GetChecked() and true or false
                c.ctl.onClick(not was, c.ctl)
                if MD.db[row.key] ~= (not was) then
                    bad[#bad + 1] = row.key .. " not written"
                end
                MD.db[row.key] = was
                MS.Refresh(view)
                if (c.ctl:GetChecked() and true or false) ~= was then
                    bad[#bad + 1] = row.key .. " not re-read"
                end
            elseif c.kind == "slider" and row.key and c.ctl:IsEnabled() then
                sliders = sliders + 1
                local v = row.min + (row.step or 1)
                Type(c.ctl, tostring(v))
                local want = v / (row.scale or 1)
                if math.abs((tonumber(MD.db[row.key]) or -1) - want) > 1e-9 then
                    bad[#bad + 1] = row.key .. "=" .. tostring(MD.db[row.key]) .. " want " .. want
                end
            end
        end
    end
    return #bad == 0 and checks >= (forever and 2 or 12) and sliders >= (forever and 0 or 4),
        string.format("checks=%d sliders=%d %s", checks, sliders, table.concat(bad, "; "))
end)

--------------------------------------------------------------------------------
T.section("5. About")
--------------------------------------------------------------------------------
Try("About: the version, the line's client, the shared blurb, a row per command with a usage", function()
    local p = Pane("about")
    local want = 0
    for _, e in ipairs(MD:Commands()) do
        if not e.hidden and type(e.usage) == "string" and e.usage ~= "" then want = want + 1 end
    end
    local commands = 0
    for i = 1, p.shown do if p.rows[i].command then commands = commands + 1 end end
    local client = p.client:GetText() or ""
    local clientOk = forever and client:find("^WoW: Forever") ~= nil or client == "TBC Anniversary"
    local blurb = p.blurb:GetText() or ""
    return p.version:GetText() == "SpellTuner " .. tostring(MD.version) and clientOk
        and blurb == "Your spells rank by rank, your mana clock, and your fights recorded, replayed and coached."
        and not T.Has(blurb, "TBC Anniversary") and commands == want and want > 10,
        string.format("version=%s client=%s commands=%d want=%d", tostring(p.version:GetText()), client,
            commands, want)
end)

--------------------------------------------------------------------------------
T.section("6. the detail key")
--------------------------------------------------------------------------------
Try("Detail lines is drawn only where MD.SpellTip has DETAIL_MODES, and writes spellTooltipDetail", function()
    local real = MD.SpellTip
    local general = MS.panes.general
    local modes = { { id = "SHIFT", text = "Shift" }, { id = "ALT", text = "Alt" } }
    local function Scratch(tip)
        MD.SpellTip = tip
        local content = CreateFrame("Frame", nil, UIParent)
        content:SetSize(VIEW_W, VIEW_H)
        local p = MS.Build("general", content)
        MS.panes.general = general
        content:Hide()
        return p
    end
    local without = Scratch(real and real.DETAIL_MODES and { } or nil)
    local with = Scratch({ DETAIL_MODES = modes, DetailMode = function() return MD.db.spellTooltipDetail or "SHIFT" end })
    MD.SpellTip = real
    local picked = Pick(with.detailDropdown, "ALT")
    local wrote = MD.db.spellTooltipDetail == "ALT"
    MD.db.spellTooltipDetail = nil
    local here = (general.detailDropdown ~= nil) == (real ~= nil and real.DETAIL_MODES ~= nil)
    return without.detailDropdown == nil and with.detailDropdown ~= nil and picked and wrote and here,
        string.format("without=%s with=%s picked=%s wrote=%s line=%s", tostring(without.detailDropdown),
            tostring(with.detailDropdown), tostring(picked), tostring(wrote), tostring(here))
end)

--------------------------------------------------------------------------------
T.section("7. ASCII")
--------------------------------------------------------------------------------
Try("every string the three views draw, and every tooltip line, is ASCII with no bare pipe", function()
    local bad, n = {}, 0
    for _, view in ipairs({ "general", "review", "about" }) do
        local pane = Pane(view)
        for _, f in ipairs(S.allFrames) do
            if Under(f, pane) then
                if f.kind == "FontString" and f:GetText() then
                    n = n + 1
                    local okA, why = T.Ascii(f:GetText())
                    if not okA then bad[#bad + 1] = view .. ": " .. f:GetText() .. " (" .. why .. ")" end
                end
                for _, line in ipairs(type(f.tooltips) == "table" and f.tooltips or {}) do
                    if type(line) == "string" then
                        n = n + 1
                        local okA, why = T.Ascii(line)
                        if not okA then bad[#bad + 1] = view .. " tip: " .. line .. " (" .. why .. ")" end
                    end
                end
            end
        end
    end
    return #bad == 0 and n > 50, n .. " strings " .. table.concat(bad, "; ")
end)

--------------------------------------------------------------------------------
-- The controls, found by their row
--------------------------------------------------------------------------------
local function FindControl(pane, match)
    for _, c in ipairs(pane and pane.controls or {}) do
        local row = c.row or {}
        if (match.key and row.key == match.key) or (match.text and row.text == match.text) then
            return c
        end
    end
end
local function SectionOf(ctl)
    local p, guard = ctl and ctl.parentFrame, 0
    while p and guard < 10 do
        if p.title and p.line then return p.title:GetText() end
        p, guard = p.parentFrame, guard + 1
    end
end

if not forever then
    ----------------------------------------------------------------------------
    T.section("8. TBC: every control of Options_General in its new place")
    ----------------------------------------------------------------------------
    -- captured on 535cff4 from UI/Options_General.lua: each control's key or
    -- words, and where the task's map puts it
    local MAP = {
        { "general", "MANA CLOCK", { key = "locked" } },
        { "general", "MANA CLOCK", { key = "widgetTooltip" } },
        { "general", "MANA CLOCK", { text = "Reset position" } },
        { "general", "MANA CLOCK", { text = "Customise..." } },
        { "general", "ALERTS", { key = "muted" } },
        { "general", "ALERTS", { key = "drinkReminder" } },
        { "general", "ALERTS", { key = "calibAlerts" } },
        { "review", "MODEL", { key = "halfLife" } },
        { "review", "MODEL", { key = "oomConfidence" } },
        { "review", "MODEL", { key = "treeAura" } },
        { "review", "MODEL", { key = "naturesGrace" } },
        { "review", "MODEL", { text = "Reset overheal data" } },
        { "review", "MODEL", { text = "Regen test (30s)" } },
        { "general", "WINDOWS", { text = "Minimap button" } },
        { "general", "SPELL TOOLTIPS", { key = "spellTooltip" } },
        { "general", "SPELL TOOLTIPS", { key = "spellTooltipDamage" } },
        { "general", "TOOLS", { text = "Debug Console" } },
        { "general", "TOOLS", { text = "Verify spell data" } },
        { "general", "TOOLS", { text = "Copy profile" } },
        { "review", "RECORDING", { key = "recordFights" } },
        { "review", "RECORDING", { key = "recordRuns" } },
        { "review", "RECORDING", { key = "replayNextPull" } },
        { "review", "RECORDING", { key = "simAllowRebinds" } },
        { "review", "RECORDING", { key = "simFullHp" } },
        { "review", "RECORDING", { key = "simFloor" } },
        { "review", "RECORDING", { key = "replayAutoCoach" } },
        { "review", "RECORDING", { key = "replayTicks" } },
        { "general", "WINDOWS", { text = "In combat" } },
        { "general", "WINDOWS", { text = "Close one window per ESC" } },
        { "general", "WINDOWS", { text = "Reset window positions" } },
        { "general", "APPEARANCE", { mark = "fontSlider" } },
        { "general", "APPEARANCE", { mark = "scaleSlider" } },
        { "general", "APPEARANCE", { mark = "lookControls" } },
        { "general", "INTEGRATIONS", { mark = "integrations" } },
    }
    Try("each of the 34 controls is in its pane per the map; Show rest time and Show mana cooldown are gone", function()
        local bad = {}
        for _, m in ipairs(MAP) do
            local pane = Pane(m[1])
            local where
            if m[3].mark then
                local ctl = pane[m[3].mark]
                if m[3].mark == "lookControls" then ctl = ctl and ctl.dropdown end
                if m[3].mark == "integrations" then where = ctl and ctl.title:GetText()
                else where = SectionOf(ctl) end
            else
                local c = FindControl(pane, m[3])
                where = c and SectionOf(c.ctl)
            end
            if where ~= m[2] then
                bad[#bad + 1] = (m[3].key or m[3].text or m[3].mark) .. " in " .. tostring(where)
            end
        end
        local gone = true
        for _, f in ipairs(S.allFrames) do
            if f.kind == "FontString" and (Under(f, MS.panes.general) or Under(f, MS.panes.review)) then
                local t = f:GetText() or ""
                if t == "Show rest time" or t == "Show mana cooldown" then gone = false end
            end
        end
        return #bad == 0 and gone, table.concat(bad, "; ") .. " gone=" .. tostring(gone)
    end)

    ----------------------------------------------------------------------------
    T.section("9. TBC: Show now and Customise...")
    ----------------------------------------------------------------------------
    Try("Show now runs MD.Widget:Preview; Customise... selects Settings -> Clock", function()
        local p = Pane("general")
        local previews = 0
        local real = MD.Widget.Preview
        MD.Widget.Preview = function() previews = previews + 1 end
        Click(p.clockShowNow)
        MD.Widget.Preview = real
        Click(p.clockCustomise)
        local g, v = MD:SelectedView()
        return previews == 1 and g == "settings" and v == "clock",
            string.format("previews=%d view=%s/%s", previews, tostring(g), tostring(v))
    end)

    ----------------------------------------------------------------------------
    T.section("10. TBC: MD:ShowOptionsFrame, the door")
    ----------------------------------------------------------------------------
    Try("ShowOptionsFrame() opens General, (\"about\") About; MD.optionsFrame is nil", function()
        MD:SelectView("reports", "Review")
        MD:ShowOptionsFrame()
        local g1, v1 = MD:SelectedView()
        MD:ShowOptionsFrame("about")
        local g2, v2 = MD:SelectedView()
        return g1 == "settings" and v1 == "general" and g2 == "settings" and v2 == "about"
            and MD.optionsFrame == nil,
            table.concat({ tostring(g1), tostring(v1), tostring(g2), tostring(v2), tostring(MD.optionsFrame) }, " ")
    end)

    ----------------------------------------------------------------------------
    T.section("11. TBC: the sizes")
    ----------------------------------------------------------------------------
    Try("Settings is 860 x 560, fixed with no grip; Spells is still 1036 x 646", function()
        local frame = _G.SpellTunerDashboard
        MD:SelectView("settings", "general")
        local sw, sh = frame:GetWidth(), frame:GetHeight()
        local fixed = MD.Win:Fixed("main", "settings")
        local z = MD.Win.SIZES and MD.Win.SIZES.settings or {}
        MD:SelectView("spells", "overview")
        local pw, ph = frame:GetWidth(), frame:GetHeight()
        return sw == 860 and sh == 560 and fixed and z.minW == 860 and z.minH == 560 and pw == 1036 and ph == 646,
            string.format("settings %sx%s fixed=%s spells %sx%s", sw, sh, tostring(fixed), pw, ph)
    end)
else
    ----------------------------------------------------------------------------
    T.section("12. Forever: Measure on Review / MODEL; TOOLS")
    ----------------------------------------------------------------------------
    Try("Measure on Review / MODEL with the ~ sentence; TOOLS holds Debug console and Copy /st dump only", function()
        local g = Pane("general")
        local tools = {}
        for _, c in ipairs(g.controls) do
            if c.kind == "button" and SectionOf(c.ctl) == "TOOLS" then tools[#tools + 1] = c.ctl:GetText() end
        end
        local r = Pane("review")
        local hint = r.modelHint and r.modelHint:GetText()
        return table.concat(tools, ",") == "Debug console,Copy /st dump" and g.measureButton == nil
            and r.measureButton ~= nil and SectionOf(r.measureButton) == "MODEL"
            and hint == "~ marks a number the model computed, not one the game showed.",
            table.concat(tools, ",") .. " hint=" .. tostring(hint)
    end)

    ----------------------------------------------------------------------------
    T.section("13. Forever: RECORDING follows the Replay module")
    ----------------------------------------------------------------------------
    Try("RECORDING is disabled with its note while Replay is off, live once it loads", function()
        local r = Pane("review")
        local function State()
            local on, off = 0, 0
            for _, c in ipairs(r.reviewChecks or {}) do
                if c.check:IsEnabled() then on = on + 1 else off = off + 1 end
            end
            if r.fullHpSlider then
                if r.fullHpSlider:IsEnabled() then on = on + 1 else off = off + 1 end
            end
            return on, off, r.reviewNote and r.reviewNote:GetText()
        end
        local on1, off1, note1 = State()
        MD:SetModule("SpellTuner_Replay", true)
        local on2, off2, note2 = State()
        return on1 == 0 and off1 == 5 and note1 == "needs the Replay module - off"
            and MD:ModuleState("SpellTuner_Replay") == "loaded"
            and off2 == 0 and on2 >= 5 and note2 == "needs the Replay module",
            string.format("off: %d/%d %s; on: %d/%d %s", on1, off1, tostring(note1), on2, off2, tostring(note2))
    end)
end

T.done()
