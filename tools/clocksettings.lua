-- tools/run.sh [--flavour tbc|forever] tools/clocksettings.lua
--
-- T102 (docs/SPEC-next.md 5.4, 6.3, 7.3-7.4), re-based by T145d
-- (docs/SPEC-clock-v3.md 3; docs/tasks/T145d-clock-pane.md): the Settings join
-- point, UI/ClockSettings.lua, on both lines. The flavour's whole TOC is
-- loaded -- TBC's UI files and both lines' Integrations/ included -- with the
-- stub's geometry on and fake hosts installed BEFORE the TOC
-- (tools/stub_hosts.lua: LibDataBroker on both, ElvUI's datatexts on TBC,
-- EllesmereUI 9.3.4 on Forever), so the INTEGRATIONS pane has something to say.
--
-- What is held, on both flavours:
--   1. Settings has a Clock view after General; the pane is PREVIEW on top
--      and, scrolling under it, BAR, TEXTS, PRESETS, WHEN (no tabs); the
--      preview is a frame of its own, never the clock on screen;
--   2. the chips (In a fight, Running out, Filling, Full, Live) paint their
--      faces' words into the preview and leave the clock on screen untouched;
--      Live paints ST.ClockFace.Current through ClockWords;
--   3. the control registry (CS.CONTROLS): every entry has its widget; an off
--      text shows only its switch, its name and a sample; Time as / Warn only
--      with the time on, Custom's swatch only with a colour fill, Undo only
--      while held (every control against the live clock: tools/clocke2e.lua);
--   4. the Texture list (EllesmereUI's, your UI's; at most 12 rows in view),
--      the reason beside a choice the client cannot draw, the colour picker;
--   5. When: the line's own switches, no Rest (the Rest text has its own);
--   6. the Look dropdown on General lists every style, writes db.ui.style and
--      repaints at once; Use my class colour;
--   7. the subcommands: /st clock layout (the Bar only), look reset, preview;
--      Forever's /st clock and /st clock lock as before; TBC's usage;
--   8. INTEGRATIONS: ST.Integrations.Lines(), the broker switches, the hint,
--      Forever's EllesmereUI mover switch, "none found";
--   9. Customise... on the everyday clock pane opens Settings -> Clock;
--  10. every word the pane draws is ASCII with no bare pipe; the preview and
--      the scrolling area lie inside the view, every section inside the
--      scrolling area's width; General's panes inside the view;
--  11. Forever, under the stub's forever profile: Live in a fight paints
--      without raising and no font string of the pane holds a secret.
-- The 36 checks T145c skipped (U4) were ported here (the chips, Live, When's
-- lock, the Look dropdown, EllesmereUI / LibSharedMedia textures, the Texture
-- list, the colour picker, the words and places) or replaced by
-- tools/clocke2e.lua (every Bar / Text / Colour / Frame control and preset);
-- the Line / Compact slots, tabs and layout buttons are gone with them
-- (docs/review/T145de-implementer-report.md lists each).
HARNESS_FLAVOUR = { "tbc", "forever" }

local here = arg[0]:match("^(.*)/[^/]+$")
local root = arg[1] or "."

local flavour = os.getenv("ST_FLAVOUR")
if flavour == nil or flavour == "" then flavour = "tbc" end
if flavour ~= "forever" and flavour ~= "tbc" then
    print("skip: clocksettings.lua runs under tbc, forever only")
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

local FILE = "UI/ClockSettings.lua"
local AFTER = forever and "UI/Clock_Forever.lua" or "UI/Widget.lua"

local ST = {}
local toc = "SpellTuner_TBC.toc"
if forever then
    S.UseProfile("forever")
    S.UseAtlases() -- T142: the game bar frame draws on Forever
    toc = "SpellTuner_Mainline.toc"
end
S.Geometry(true)

-- the hosts, before the TOC (EllesmereUI and ElvUI load before SpellTuner)
local lib = H.InstallLDB()
if forever then H.InstallEllesmere() else H.InstallElvUI() end

local function Exists(rel)
    local f = io.open(root .. "/" .. rel, "r")
    if f then f:close(); return true end
    return false
end

local files, listed = {}, false
for _, rel in ipairs(S.TocFiles(toc)) do
    if rel == FILE then listed = true end
end
for _, rel in ipairs(S.TocFiles(toc)) do
    files[#files + 1] = rel
    if rel == AFTER and not listed and Exists(FILE) then files[#files + 1] = FILE end
end
S.loadedFiles = files

-- the navigation's groups, as the dashboards hand them to the kit
local navGroups = {}
local loadedOK, loadErr = pcall(function()
    -- one file at a time, so the kit's navigation is watched from the moment
    -- UI/Style.lua defines it
    for _, rel in ipairs(files) do
        S.Load({ rel }, "SpellTuner", ST)
        if rel == "UI/Style.lua" then
            local make = ST.UI.CreateNavFrame
            ST.UI.CreateNavFrame = function(title, name, w, h, groups, ...)
                if name == "SpellTunerDashboard" then navGroups = groups end
                return make(title, name, w, h, groups, ...)
            end
        end
    end
end)
if not loadedOK then print("load: " .. tostring(loadErr)) end
H.AddOnMeta(ST, { EllesmereUI = { Version = "9.3.4" } })
S.Fire("ADDON_LOADED", "SpellTuner")
S.Fire("PLAYER_LOGIN")
S.Fire("PLAYER_ENTERING_WORLD")

local UI = ST.UI or {}
local CS = ST.ClockSettings or {}
local CF = ST.ClockFace or {}
local W = ST.ClockWidget or {}
local widget = W.frame

-- the first run's placing preview ended, the clock locked
if ST.db then ST.db.locked = true end
if W.Preview then pcall(W.Preview, W, 0) end
if forever and ST.db and type(ST.db.clock) == "table" then ST.db.clock.locked = true end

local function Try(name, fn)
    local okR, cond, detail = pcall(fn)
    if not okR then return check(name, false, "raised: " .. tostring(cond)) end
    return check(name, cond, detail)
end
local function Click(b)
    if b and b.GetScript and b:GetScript("OnClick") then b:GetScript("OnClick")(b) end
end
local function Pick(dd, id)
    if not dd then return false end
    for i, it in ipairs(dd.items) do
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
local function Tick(n) for _ = 1, n or 1 do S.Tick(0.5) end end
local function Chat(body)
    local okC, lines = pcall(T.CapturedChat, body)
    if not okC then return { "RAISED " .. tostring(lines) } end
    return lines
end
local function Plain(lines)
    local out = {}
    for i, l in ipairs(lines) do out[i] = T.Strip(l):gsub("^SpellTuner: ", "") end
    return out
end

local counts = { CLOCK_LOOK = 0, STYLE_CHANGED = 0 }
if ST.RegisterCallback then
    ST:RegisterCallback("CLOCK_LOOK", function() counts.CLOCK_LOOK = counts.CLOCK_LOOK + 1 end)
    ST:RegisterCallback("STYLE_CHANGED", function() counts.STYLE_CHANGED = counts.STYLE_CHANGED + 1 end)
end

-- every Show / Hide on the clock on screen, with the caller's name
local visCalls = {}
if widget then
    local realShow, realHide = widget.Show, widget.Hide
    widget.Show = function(self, ...)
        local info = debug.getinfo(2, "n")
        visCalls[#visCalls + 1] = "Show from " .. tostring(info and info.name)
        return realShow(self, ...)
    end
    widget.Hide = function(self, ...)
        local info = debug.getinfo(2, "n")
        visCalls[#visCalls + 1] = "Hide from " .. tostring(info and info.name)
        return realHide(self, ...)
    end
end

--------------------------------------------------------------------------------
-- Where a region sits, relative to a base frame whose own size is given: the
-- base's TOPLEFT is 0, 0, y grows upward (so everything inside has y <= 0).
--------------------------------------------------------------------------------
local function PointXY(rect, p)
    local x = p:find("LEFT") and rect.l or (p:find("RIGHT") and rect.r) or (rect.l + rect.r) / 2
    local y = p:find("TOP") and rect.t or (p:find("BOTTOM") and rect.b) or (rect.b + rect.t) / 2
    return x, y
end
local function Size(r)
    if r.kind == "FontString" then return r:GetStringWidth(), r:GetStringHeight() end
    return r:GetWidth(), r:GetHeight()
end
local function Rect(r, base, bw, bh, depth)
    depth = depth or 0
    if r == base then return { l = 0, t = 0, r = bw, b = -bh } end
    if not r or depth > 12 then return nil end
    local pts = r.points or {}
    if #pts == 0 then return nil end
    local box = {}
    for _, pt in ipairs(pts) do
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

-- the titled panes made with `parent` as their parent
local function TitledUnder(parent)
    local out = {}
    for _, f in ipairs(S.allFrames) do
        if f.title and f.line and f.parentFrame == parent then out[#out + 1] = f end
    end
    return out
end

-- every font string under a frame (any depth), shown or not
local function FontStrings(top)
    local out = {}
    for _, f in ipairs(S.allFrames) do
        if f.kind == "FontString" then
            local p, guard = f.parentFrame, 0
            while p and guard < 20 do
                if p == top then out[#out + 1] = f; break end
                p, guard = p.parentFrame, guard + 1
            end
        end
    end
    return out
end

-- the content size the dashboards' Settings views get (UI/Style.lua's nav:
-- 108-px column, 8-px pads, a 24-px view row). T119 (SPEC-one-ui 7): TBC's
-- Settings group is 860 x 560 too, so both lines measure against 736 x 520.
local VIEW_W = 860 - 108 - 16
local VIEW_H = 560 - 24 - 16

--------------------------------------------------------------------------------
T.section("1. Settings -> Clock")
--------------------------------------------------------------------------------
check("UI/ClockSettings.lua loaded (" .. (listed and "listed by the TOC" or "where the TOC line goes") .. ")",
    loadedOK and type(CS.Build) == "function", loadErr and tostring(loadErr))

local pane, p
Try("the Settings group has a Clock view, after General", function()
    ST:SelectView("settings", "general") -- the Forever window is built on first use
    local ids = {}
    for _, g in ipairs(navGroups) do
        if g.id == "settings" then
            for _, v in ipairs(g.views or {}) do ids[#ids + 1] = v.id end
        end
    end
    -- T119: Review between Clock and the rest on both lines
    local want = forever and "general,clock,review,modules,about" or "general,clock,review,about"
    return table.concat(ids, ",") == want, table.concat(ids, ",")
end)

-- T145d (docs/SPEC-clock-v3.md 3, the mockup): one pane, no tabs -- PREVIEW
-- on top, then, scrolling under it, BAR, TEXTS, PRESETS and WHEN
Try("selecting it builds the pane: PREVIEW, then BAR, TEXTS, PRESETS, WHEN scrolling under it; no tabs", function()
    ST:SelectView("settings", "clock")
    for _, f in ipairs(S.allFrames) do if f.clockSettings then pane, p = f, f.clockSettings end end
    local g, v = ST:SelectedView()
    local top, under = {}, {}
    for _, t in ipairs(TitledUnder(pane)) do top[#top + 1] = t.title:GetText() end
    for _, t in ipairs(TitledUnder(p.content)) do under[#under + 1] = t.title:GetText() end
    return g == "settings" and v == "clock" and pane ~= nil and pane:IsVisible()
        and table.concat(top, ",") == "PREVIEW" and table.concat(under, ",") == "BAR,TEXTS,PRESETS,WHEN"
        and CS.TABS == nil and p.box == nil,
        string.format("%s/%s top %s under %s", tostring(g), tostring(v), table.concat(top, ","), table.concat(under, ","))
end)

Try("the preview is a frame of its own, not the clock on screen nor a child of it", function()
    local f = p.previewFrame
    local up, guard, child = f and f.parentFrame, 0, false
    while up and guard < 20 do
        if up == widget then child = true end
        up, guard = up.parentFrame, guard + 1
    end
    return f ~= nil and widget ~= nil and f ~= widget and not child and p.view ~= W.renderer
end)

--------------------------------------------------------------------------------
T.section("2. the chips paint the sample faces into the preview; the clock is untouched")
--------------------------------------------------------------------------------
local function PreviewTime() return p.view:Drawn().text.time.words end
local function LiveTime() return W.renderer and W.renderer:Drawn().text.time.words end

Try("the chips are In a fight, Running out, Filling, Full, Live", function()
    local names = {}
    for _, b in ipairs(p.chips) do names[#names + 1] = b:GetText() end
    return table.concat(names, ",") == "In a fight,Running out,Filling,Full,Live", table.concat(names, ",")
end)

Try("each chip paints its face's words (1:20 with the 5SR line, 0:15 red, FULL 0:45, FULL); the clock is untouched",
        function()
    ST.ClockStore.Reset()
    local before = LiveTime()
    local shownBefore = widget and widget:IsShown()
    local n0 = #visCalls
    local got = {}
    for _, b in ipairs(p.chips) do
        if b.id ~= "live" then
            Click(b) -- a chip paints at once; no tick, so the clock on screen is not repainted by time
            p.view.step() -- the preview's own line driver, one frame (the world's tick would move the clock)
            local d = p.view:Drawn()
            got[#got + 1] = b.id .. "=" .. tostring(d.text.time.words) .. (d.line.shown and "+line" or "")
        end
    end
    local untouched = LiveTime() == before and widget:IsShown() == shownBefore and #visCalls == n0
    local want = "fight=1:20+line,low=0:15+line,filling=FULL 0:45,full=FULL"
    Click(p.chips[2])
    local red = p.view:Drawn().text.time.colour
    local crit = { ST.ClockFace.ToneRGB("crit") }
    local isRed = red and math.abs(red[1] - crit[1]) < 1e-6 and math.abs(red[2] - crit[2]) < 1e-6
    return table.concat(got, ",") == want and untouched and isRed,
        string.format("%s; clock untouched %s (%d Show/Hide); red %s", table.concat(got, ","), tostring(untouched),
            #visCalls - n0, tostring(isRed))
end)

Try("Live paints the line's own face (ST.ClockFace.Current) through ClockWords", function()
    Click(p.chips[#p.chips])
    Tick(1)
    CS.PaintPreview(p)
    local face = CF.Current(GetTime())
    local want = ST.ClockWords.Build(face, ST.ClockStore.Look(), nil, GetTime(), nil, false).time.text
    return p.chip == "live" and PreviewTime() == want, tostring(PreviewTime()) .. " / " .. tostring(want)
end)

--------------------------------------------------------------------------------
T.section("3. the controls: one registry, an off text shows only its switch")
--------------------------------------------------------------------------------
Try("every CS.CONTROLS entry has its widget, a write, a visible rule and the fields it changes", function()
    local bad = {}
    for _, c in ipairs(CS.CONTROLS) do
        if not (p.widgets[c.id] and type(c.write) == "function" and type(c.visible) == "function"
            and type(c.affects) == "table" and #c.affects > 0 and type(c.values) == "table" and #c.values > 1) then
            bad[#bad + 1] = c.id
        end
    end
    return #bad == 0 and #CS.CONTROLS == 68, #CS.CONTROLS .. " controls; " .. table.concat(bad, ", ")
end)

local function Row(kind) for _, r in ipairs(p.textRows) do if r.kind == kind then return r end end end
Try("an off text shows its switch, its name and a sample; on, its seven fields; the store keeps them", function()
    ST.ClockStore.Reset()
    local row = Row("pct")
    local fields = { "place", "align", "x", "y", "size", "colour", "outline" }
    local function Shown(on)
        for _, f in ipairs(fields) do
            if p.widgets["texts.pct." .. f]:IsShown() ~= on then return false end
        end
        return true
    end
    local off = not ST.ClockStore.Look().texts.pct.on and row.on:IsShown() and row.sample:IsShown()
        and row.sample:GetText() == "60%" and Shown(false)
    ST.ClockStore.SetText("pct", "size", 14)
    row.on:SetChecked(true); row.on:GetScript("OnClick")(row.on)
    local on = ST.ClockStore.Look().texts.pct.on and Shown(true) and not row.sample:IsShown()
        and p.widgets["texts.pct.size"]:GetText() == "14"
    row.on:SetChecked(false); row.on:GetScript("OnClick")(row.on)
    local kept = ST.ClockStore.Look().texts.pct.size == 14 and Shown(false)
    ST.ClockStore.Reset()
    return off and on and kept, string.format("off %s on %s kept %s", tostring(off), tostring(on), tostring(kept))
end)

Try("Time as and Warn colours only while the time is on; Custom's swatch only while the fill is a colour; "
        .. "Undo only while a preset's undo is held", function()
    ST.ClockStore.Reset()
    local tOn = p.widgets.timeFmt:IsShown() and p.widgets.warn:IsShown()
    ST.ClockStore.SetText("time", "on", false)
    local tOff = not p.widgets.timeFmt:IsShown() and not p.widgets.warn:IsShown()
    ST.ClockStore.Reset()
    local noSwatch = not p.widgets.fillColour:IsShown()
    for _, b in ipairs(p.widgets.fill.buttons) do if b.id == "custom" then Click(b) end end
    local custom = p.widgets.fillColour:IsShown() and ST.ClockStore.Look().fill == CS.CUSTOM_FILL
    local noUndo = not p.undoButton:IsShown()
    for _, b in ipairs(p.presetButtons) do if b.id == "ellesmere" then Click(b) end end
    local undo = p.undoButton:IsShown()
    Click(p.undoButton)
    local back = not p.undoButton:IsShown() and ST.ClockStore.Look().fill == CS.CUSTOM_FILL
    ST.ClockStore.Reset()
    return tOn and tOff and noSwatch and custom and noUndo and undo and back,
        string.format("time %s/%s swatch %s/%s undo %s/%s/%s", tostring(tOn), tostring(tOff), tostring(noSwatch),
            tostring(custom), tostring(noUndo), tostring(undo), tostring(back))
end)

--------------------------------------------------------------------------------
T.section("4. textures, the reason beside a choice, the colour picker")
--------------------------------------------------------------------------------
local function Pane() return ST.ClockStore.Look() end

-- T140 (ported, T145d): EllesmereUI's textures listed and drawn; its preset
-- takes its mana colour; the font follows it
Try("with EllesmereUI: its textures listed and drawn, its preset takes its mana colour, the font follows it",
        function()
    ST.ClockStore.Reset()
    local saved, savedParent = rawget(_G, "EllesmereUI"), ST.EUIParent
    local dir = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
    _G.EllesmereUI = {
        BuildBarTextureTables = function()
            return { atrocity = dir .. "atrocity.tga", ["pixels-dark"] = dir .. "pixels-dark.tga" },
                { none = "None", atrocity = "Atrocity", ["pixels-dark"] = "Pixels Dark" },
                { "none", "atrocity", "pixels-dark" }
        end,
        GetPowerColor = function(key) if key == "MANA" then return { r = 0, g = 0.55, b = 1 } end end,
    }
    ST.EUIParent = { GetFontPath = function() return "Fonts\\EUI.ttf" end }
    CS.Refresh(p)
    local texts = {}
    for _, it in ipairs(p.textureDropdown.items) do texts[#texts + 1] = it.id .. "=" .. it.text end
    local listed = table.concat(texts, "/"):find("eui:atrocity=Atrocity (EllesmereUI)/eui:pixels-dark=Pixels Dark (EllesmereUI)", 1, true) ~= nil
    -- a host arriving is seen by the pane's own repaint (CS.Refresh) -- the
    -- clock on screen repaints on its next CLOCK_LOOK
    local live = p.view:Drawn()
    local def = live.bar.texture == dir .. "pixels-dark.tga" and live.text.time.face == "Fonts\\EUI.ttf"
        and p.notes.texture:GetText() == "" and p.notes.font:GetText() == ""
    Pick(p.textureDropdown, "eui:atrocity")
    local picked = Pane().texture == "eui:atrocity" and W.renderer:Drawn().bar.texture == dir .. "atrocity.tga"
    for _, b in ipairs(p.presetButtons) do if b.id == "ellesmere" then Click(b) end end
    local took = Pane().fill == "008CFF" and Pane().width == 260
    _G.EllesmereUI, ST.EUIParent = saved, savedParent
    ST.ClockStore.Reset()
    return listed and def and picked and took, string.format("listed %s default %s picked %s took %s (%s)",
        tostring(listed), tostring(def), tostring(picked), tostring(took), table.concat(texts, "/"))
end)

-- spec 2.6: a choice the client cannot honour shows the reason beside it and
-- stays clickable (the choice kept for when it can be drawn)
Try("without EllesmereUI: Texture and Font keep the choice, draw Soft and SpellTuner's font, the reason beside each",
        function()
    ST.ClockStore.Reset()
    local saved, savedParent, savedSkin = rawget(_G, "EllesmereUI"), ST.EUIParent, ST.EUISkin
    _G.EllesmereUI, ST.EUIParent, ST.EUISkin = nil, nil, nil
    CS.Refresh(p)
    local CB = ST.ClockBar
    local live = p.view:Drawn()
    local ok = Pane().texture == "eui:pixels-dark" and Pane().font == "eui" and live.bar.texture == CB.TEXTURES.soft
        and p.notes.texture:GetText() == CB.EUI_TEXTURE_MISSING and p.notes.font:GetText() == CB.FONT_EUI_MISSING
        and p.textureDropdown:IsShown() and p.widgets.font:IsShown()
    _G.EllesmereUI, ST.EUIParent, ST.EUISkin = saved, savedParent, savedSkin
    CS.Refresh(p)
    return ok, tostring(p.notes.texture:GetText()) .. " / " .. tostring(p.notes.font:GetText())
end)

-- T139 (ported): your UI's bar textures (LibSharedMedia)
Try("your UI's bar textures (LibSharedMedia) are listed and drawn; without the host, Flat and the reason", function()
    ST.ClockStore.Reset()
    local savedLS = rawget(_G, "LibStub")
    local LSM = {
        List = function(_, kind) return kind == "statusbar" and { "Norm", "Clean" } or {} end,
        Fetch = function(_, kind, name) return "Interface\\AddOns\\Host\\" .. name end,
    }
    _G.LibStub = { GetLibrary = function(_, name) if name == "LibSharedMedia-3.0" then return LSM end end }
    CS.Refresh(p)
    local texts = {}
    for _, it in ipairs(p.textureDropdown.items) do texts[#texts + 1] = it.text end
    local listed = table.concat(texts, "/"):find("Clean (your UI)/Norm (your UI)", 1, true) ~= nil
    Pick(p.textureDropdown, "lsm:Norm")
    local drawn = Pane().texture == "lsm:Norm" and W.renderer:Drawn().bar.texture == "Interface\\AddOns\\Host\\Norm"
    _G.LibStub = nil
    CS.Refresh(p)
    local flat = p.view:Drawn().bar.texture == ST.ClockBar.TEXTURES.flat
        and p.notes.texture:GetText() == ST.ClockBar.LSM_MISSING
    _G.LibStub = savedLS
    ST.ClockStore.Reset()
    return listed and drawn and flat, string.format("listed %s drawn %s flat %s (%s)", tostring(listed),
        tostring(drawn), tostring(flat), table.concat(texts, "/"))
end)

-- T144 (ported): a long list fits -- at most UI.DROPDOWN_ROWS rows in view,
-- the wheel scrolls it, the selected entry in view on open
Try("the Texture list fits: at most 12 rows, the wheel scrolls it, the selected one in view on open", function()
    ST.ClockStore.Reset()
    local savedLS = rawget(_G, "LibStub")
    local names = {}
    for i = 1, 30 do names[i] = string.format("Host%02d", i) end
    local LSM = {
        List = function(_, kind) return kind == "statusbar" and names or {} end,
        Fetch = function(_, kind, name) return "Interface\\AddOns\\Host\\" .. name end,
    }
    _G.LibStub = { GetLibrary = function(_, name) if name == "LibSharedMedia-3.0" then return LSM end end }
    CS.Refresh(p)
    local dd = p.textureDropdown
    local n = #dd.items
    Pick(dd, "lsm:Host28")
    local function InView()
        local out = {}
        for i, r in ipairs(dd.rows) do if i <= n and r:IsShown() then out[#out + 1] = i end end
        return out
    end
    dd:GetScript("OnClick")(dd) -- open
    local open = dd.list:IsShown()
    local view = InView()
    local sel
    for i, it in ipairs(dd.items) do if it.id == "lsm:Host28" then sel = i end end
    local selIn = false
    for _, i in ipairs(view) do if i == sel then selIn = true end end
    local fits = n > 12 and #view == dd.visible and dd.visible <= ST.UI.DROPDOWN_ROWS and dd.visible >= 3
        and dd.scrollBar:IsShown()
    local wheel = dd.list:GetScript("OnMouseWheel")
    for _ = 1, 50 do wheel(dd.list, 1) end
    local top = dd.offset == 0 and InView()[1] == 1
    for _ = 1, 50 do wheel(dd.list, -1) end
    local bottom = dd.offset == n - dd.visible and InView()[#InView()] == n
    local picked = Pick(dd, dd.items[n].id) and not dd.list:IsShown()
    _G.LibStub = savedLS
    ST.ClockStore.Reset()
    return open and selIn and fits and top and bottom and picked, string.format(
        "n %d open %s view %d sel %s in %s fits %s top %s bottom %s picked %s", n, tostring(open), #view,
        tostring(sel), tostring(selIn), tostring(fits), tostring(top), tostring(bottom), tostring(picked))
end)

-- T139 (ported): the game's colour picker; one move is one write; Cancel puts
-- the colour back; right-click is SpellTuner's
Try("a colour opens the game's picker; a move writes it (one CLOCK_LOOK); Cancel puts it back; right-click "
        .. "resets", function()
    ST.ClockStore.Reset()
    local info
    local cur = { 0.1, 0.2, 0.3, 0.5 }
    local saved = rawget(_G, "ColorPickerFrame")
    _G.ColorPickerFrame = {
        SetupColorPickerAndShow = function(_, i) info = i end,
        GetColorRGB = function() return cur[1], cur[2], cur[3] end,
        GetColorAlpha = function() return cur[4] end,
    }
    ST.API.Invalidate("ColorPickerFrame")
    local back = p.widgets.back
    Click(back)
    local opened = info ~= nil and info.hasOpacity == true and math.abs(info.r - 10 / 255) < 1e-6
    local n0 = counts.CLOCK_LOOK
    if info then info.swatchFunc() end
    local moved = Pane().back == "1A334D" and Pane().backAlpha == 0.5 and counts.CLOCK_LOOK - n0 == 1
        and math.abs(W.renderer:Drawn().back.colour[4] - 0.5) < 1e-9
    if info then info.cancelFunc() end
    local cancelled = Pane().back == "0A0A0A" and Pane().backAlpha == 1
    if info then info.swatchFunc() end
    back:GetScript("OnClick")(back, "RightButton")
    local reset = Pane().back == ST.ClockStore.DEFAULTS.back and Pane().backAlpha == ST.ClockStore.DEFAULTS.backAlpha
    -- a text's colour: no opacity kept
    info = nil
    local sw = p.widgets["texts.mana.colour"]
    Click(sw)
    if info then info.swatchFunc() end
    local text = Pane().texts.mana.colour == "1A334D"
    sw:GetScript("OnClick")(sw, "RightButton")
    local textReset = Pane().texts.mana.colour == ST.ClockStore.DEFAULTS.texts.mana.colour
    _G.ColorPickerFrame = saved
    ST.API.Invalidate("ColorPickerFrame")
    ST.ClockStore.Reset()
    return opened and moved and cancelled and reset and text and textReset, string.format(
        "opened %s moved %s cancelled %s reset %s text %s/%s", tostring(opened), tostring(moved), tostring(cancelled),
        tostring(reset), tostring(text), tostring(textReset))
end)

--------------------------------------------------------------------------------
T.section("5. When; the Rest text's own switch")
--------------------------------------------------------------------------------
local function SwitchNamed(text)
    for _, cb in ipairs(p.switches or {}) do if cb.def.text:find(text, 1, true) == 1 then return cb end end
end

Try("When: the line's own switches, no Rest among them; Locked is the line's own lock", function()
    local names = {}
    for _, cb in ipairs(p.switches) do names[#names + 1] = cb.def.text end
    local want = forever and "Show the mana clock,Locked,Click-through" or "Locked,Tooltip and left-click"
    local cb = SwitchNamed("Locked")
    cb:SetChecked(false); cb.onClick(false, cb)
    local off = forever and ST.db.clock.locked == false or (not forever and ST.db.locked == false)
    cb:SetChecked(true); cb.onClick(true, cb)
    local on = forever and ST.db.clock.locked == true or (not forever and ST.db.locked == true)
    if W.Preview then W:Preview(0) end
    return table.concat(names, ",") == want and off and on, table.concat(names, ",")
end)

if forever then
    Try("/st clock rest turns the Rest text on and off, and the pane follows", function()
        ST.ClockStore.Reset()
        local slashFn = SlashCmdList and SlashCmdList.SPELLTUNER
        Chat(function() slashFn("clock rest") end)
        local on = ST.ClockStore.Look().texts.rest.on == true and Row("rest").on:GetChecked()
            and p.widgets["texts.rest.size"]:IsShown()
        Chat(function() slashFn("clock rest") end)
        local off = ST.ClockStore.Look().texts.rest.on == false and not Row("rest").on:GetChecked()
        return on and off, string.format("on %s off %s", tostring(on), tostring(off))
    end)
else
    Try("/st rest still turns the feeds' rest segment (db.showRest); the clock's Rest text is the pane's", function()
        ST.ClockStore.Reset()
        local slashFn = SlashCmdList and SlashCmdList.SPELLTUNER
        local before = ST.db.showRest
        Chat(function() slashFn("rest") end)
        local flipped = ST.db.showRest == not before and ST.ClockStore.Look().texts.rest.on == false
        Chat(function() slashFn("rest") end)
        return flipped and ST.db.showRest == before, tostring(ST.db.showRest)
    end)
end

--------------------------------------------------------------------------------
T.section("6. the Look dropdown and Use my class colour")
--------------------------------------------------------------------------------
local look, generalPane
local function FindLook()
    ST:SelectView("settings", "general")
    if not forever and ST.ShowOptionsFrame then ST:ShowOptionsFrame("general") end
    -- T119: one General pane on both lines, UI/Settings.lua's
    generalPane = ST.Settings and ST.Settings.panes.general
    look = generalPane and generalPane.lookControls
end
pcall(FindLook)

Try("it lists every registered style, Ellesmere by its own label", function()
    local ids, texts = {}, {}
    for _, it in ipairs(look.dropdown.items) do ids[#ids + 1] = it.id; texts[it.id] = it.text end
    return table.concat(ids, ",") == table.concat(UI.Styles.Keys(), ",") and texts.flat == "Flat"
        and texts.ellesmere == UI.Ellesmere.Label() and look.dropdown:Value() == "flat",
        table.concat(ids, ",") .. " / " .. tostring(texts.ellesmere)
end)

Try("picking a style writes db.ui.style and repaints at once (STYLE_CHANGED once); the reload line is UI.Restyle's", function()
    local hidden = not look.reload:IsShown()
    local bg = { UI.Fill("bg") }
    local n0 = counts.STYLE_CHANGED
    local picked = Pick(look.dropdown, "ellesmere")
    local now = { UI.Fill("bg") }
    local fired = counts.STYLE_CHANGED - n0
    local repainted = math.abs(now[1] - bg[1]) > 1e-6 or math.abs(now[3] - bg[3]) > 1e-6
    -- T107 (wave N4 integration): hidden while UI.Restyle.Left() is 0, else UI.Restyle.Line()
    local shown
    if UI.Restyle.Left() == 0 then
        shown = not look.reload:IsShown()
    else
        shown = look.reload:IsShown() and look.reloadText:GetText() == UI.Restyle.Line()
    end
    return picked and hidden and ST.db.ui.style == "ellesmere" and UI.STYLE == "ellesmere" and fired == 1
        and repainted and shown,
        string.format("fired %d repainted %s reload %s", fired, tostring(repainted), tostring(shown))
end)

Try("Use my class colour puts the class colour over the style's accent, and takes it back", function()
    local styleAccent = { UI.accent[1], UI.accent[2], UI.accent[3] }
    local n0 = counts.STYLE_CHANGED
    local cb = look.classCheck
    cb:SetChecked(true); cb.onClick(true, cb)
    local on = ST.db.useClassColour == true and math.abs(UI.accent[1] - UI.classAccent[1]) < 1e-6
        and math.abs(UI.accent[2] - UI.classAccent[2]) < 1e-6 and math.abs(UI.accent[3] - UI.classAccent[3]) < 1e-6
    local fired = counts.STYLE_CHANGED - n0
    cb:SetChecked(false); cb.onClick(false, cb)
    local off = ST.db.useClassColour == false and math.abs(UI.accent[1] - styleAccent[1]) < 1e-6
        and math.abs(UI.accent[3] - styleAccent[3]) < 1e-6
    local differs = math.abs(styleAccent[1] - UI.classAccent[1]) > 1e-6 or math.abs(styleAccent[3] - UI.classAccent[3]) > 1e-6
    return on and off and fired == 1 and differs, string.format("on %s off %s fired %d", tostring(on), tostring(off), fired)
end)

Try("back to Flat: the palette is Flat's, the reload line hides", function()
    Pick(look.dropdown, "flat")
    local flatBg = UI.FLAT.palette.bg
    local r, g, b = UI.Fill("bg")
    return ST.db.ui.style == "flat" and not look.reload:IsShown() and math.abs(r - flatBg[1]) < 1e-9
        and math.abs(b - flatBg[3]) < 1e-9
end)

--------------------------------------------------------------------------------
T.section("7. the subcommands")
--------------------------------------------------------------------------------
local slash = SlashCmdList and SlashCmdList.SPELLTUNER
-- T145c (docs/SPEC-clock-v3.md D1): the Bar is the only layout; the verb
-- says so and saves nothing, the look reset puts SpellTuner's look back
Try("/st clock layout <any> says the Bar is the only layout and saves no layout", function()
    local a = Plain(Chat(function() slash("clock layout compact") end))
    local b = Plain(Chat(function() slash("clock layout ring") end))
    local c = Plain(Chat(function() slash("clock layout") end))
    local say = "mana clock: the Bar is the only layout now (Settings -> Clock sets its look)"
    return a[1] == say and b[1] == say and c[1] == say
        and ST.db.clockLook.layout == nil,
        tostring(a[1]) .. " | " .. tostring(b[1]) .. " | " .. tostring(c[1])
end)

Try("/st clock look reset puts SpellTuner's look back; /st clock look alone prints its usage", function()
    ST.ClockStore.Set("fill", "123456")
    local changed = #ST.ClockStore.Differs() > 0
    local a = Plain(Chat(function() slash("clock look reset") end))
    local b = Plain(Chat(function() slash("clock look") end))
    return changed and #ST.ClockStore.Differs() == 0 and a[1] == "mana clock: the look back to SpellTuner's"
        and b[1] == "usage: /st clock look reset", tostring(a[1]) .. " | " .. tostring(b[1])
end)

Try("/st clock preview puts the clock on screen for 60 s", function()
    if W.Preview then W:Preview(0) end
    Tick(1)
    local a = Plain(Chat(function() slash("clock preview") end))
    Tick(1)
    local up = widget:IsShown()
    W:Preview(0)
    Tick(1)
    return a[1] == "mana clock: on screen for 60 s" and up, tostring(a[1])
end)

if forever then
    Try("Forever: /st clock and /st clock lock answer exactly as before", function()
        ST.db.clock.shown, ST.db.clock.locked = true, false
        local a = Plain(Chat(function() slash("clock") end))
        local hidden = ST.db.clock.shown == false
        local b = Plain(Chat(function() slash("clock") end))
        local c = Plain(Chat(function() slash("clock lock") end))
        local d = Plain(Chat(function() slash("clock lock") end))
        ST.db.clock.locked = true
        return hidden and a[1] == "mana clock: hidden" and b[1] == "mana clock: shown" and c[1] == "mana clock: locked"
            and d[1] == "mana clock: unlocked" and #a == 1 and #b == 1 and #c == 1 and #d == 1,
            table.concat({ a[1] or "", b[1] or "", c[1] or "", d[1] or "" }, " | ")
    end)
else
    Try("TBC: /st clock alone prints the subs' usage", function()
        local a = Plain(Chat(function() slash("clock") end))
        return table.concat(a, " | ") == "usage: /st clock layout | usage: /st clock look reset | "
            .. "usage: /st clock preview", table.concat(a, " | ")
    end)
end

Try("the clock's help row carries layout, look reset and preview", function()
    local row
    for _, c in ipairs(ST:Commands()) do if c.name == "clock" then row = c end end
    local want = forever and "/st clock [lock] / rest / clickthrough / layout / look reset / preview"
        or "/st clock layout / look reset / preview"
    return row ~= nil and row.usage == want and not row.hidden, row and row.usage
end)

--------------------------------------------------------------------------------
T.section("8. INTEGRATIONS")
--------------------------------------------------------------------------------
local integ
pcall(function()
    FindLook()
    for _, f in ipairs(S.allFrames) do if f.integrations then integ = f end end
end)

Try("the pane shows ST.Integrations.Lines(), one line each", function()
    integ:Refresh()
    local want = ST.Integrations.Lines()
    local got = {}
    for _, fs in ipairs(integ.found) do if fs:IsShown() then got[#got + 1] = fs:GetText() end end
    local host = forever and T.Has(want[1], "EllesmereUI 9.3.4 (tested 9.3.4)") or T.Has(want[1], "ElvUI: 2 datatexts")
    return table.concat(got, " / ") == table.concat(want, " / ") and host, table.concat(got, " / ")
end)

Try("the hint names the host found", function()
    local want = forever and "Add them in /eui -> DataBars -> a Broker Plugin block."
        or "In ElvUI pick SpellTuner, not LDB: SpellTuner - both read the same."
    return integ.hint:GetText() == want, integ.hint:GetText()
end)

Try("the broker and compact switches write db.feeds; compact drops the rest from the broker", function()
    local ldb, compact = integ.ldbCheck, integ.compactCheck
    ldb:SetChecked(false); ldb.onClick(false, ldb)
    local off = ST.db.feeds.ldb == false
    ldb:SetChecked(true); ldb.onClick(true, ldb)
    compact:SetChecked(true); compact.onClick(true, compact)
    local c = ST.db.feeds.compact == true
    compact:SetChecked(false); compact.onClick(false, compact)
    return off and ST.db.feeds.ldb == true and c and ST.db.feeds.compact == false
end)

if forever then
    Try("Forever with EllesmereUI: the /unlock mover switch is shown and writes db.eui.unlock", function()
        local mover
        for _, cb in ipairs(integ.switches) do if T.Has(cb.def.text, "mover") then mover = cb end end
        integ:Refresh()
        local shown = mover and mover:IsShown()
        mover:SetChecked(false); mover.onClick(false, mover)
        local off = ST.db.eui.unlock == false
        mover:SetChecked(true); mover.onClick(true, mover)
        return shown and off and ST.db.eui.unlock == true
    end)
end

Try("with nothing found the pane says so", function()
    local keep = ST.Integrations
    ST.Integrations = nil
    local lines = CS.IntegrationLines()
    ST.Integrations = keep
    return #lines == 1 and lines[1] == "none found"
end)

--------------------------------------------------------------------------------
T.section("9. Customise... on the everyday clock pane")
--------------------------------------------------------------------------------
Try("Customise... opens Settings -> Clock", function()
    FindLook()
    local b
    for _, f in ipairs(S.allFrames) do
        -- T119: the shared MANA CLOCK pane's button on both lines
        if f.clockCustomise then b = f.clockCustomise end
    end
    Click(b)
    local g, v = ST:SelectedView()
    return b ~= nil and g == "settings" and v == "clock" and b:GetText() == "Customise...", tostring(g) .. "/" .. tostring(v)
end)

--------------------------------------------------------------------------------
T.section("10. words and places")
--------------------------------------------------------------------------------
Try("every word the clock view and the INTEGRATIONS pane draw is ASCII, no bare pipe", function()
    local bad
    local tops = { pane, integ }
    if look then tops[#tops + 1] = look.reload end
    ST:SelectView("settings", "clock")
    -- every text on, so every row's fields have their words
    for _, kind in ipairs(ST.ClockStore.KINDS) do ST.ClockStore.SetText(kind, "on", true) end
    for _, chip in ipairs(p.chips) do Click(chip); Tick(1) end
    local n = 0
    for _, top in ipairs(tops) do
        for _, fs in ipairs(FontStrings(top)) do
            local text = fs:GetText()
            if text ~= nil and text ~= "" then
                n = n + 1
                local okA, why = T.Ascii(text)
                if not okA then bad = bad or (tostring(text) .. ": " .. why) end
            end
        end
    end
    for _, it in ipairs(look and look.dropdown.items or {}) do
        local okA, why = T.Ascii(it.text)
        if not okA then bad = bad or (it.text .. ": " .. why) end
    end
    for _, it in ipairs(p.textureDropdown.items) do
        local okA, why = T.Ascii(it.text)
        if not okA then bad = bad or (it.text .. ": " .. why) end
    end
    ST.ClockStore.Reset()
    return bad == nil and n > 60, bad or (n .. " strings")
end)

Try("the preview and the scrolling area lie inside the view; every section inside the scrolling area's width",
        function()
    ST:SelectView("settings", "clock")
    local bad
    local base = { l = 0, t = 0, r = VIEW_W, b = -VIEW_H }
    for _, f in ipairs({ p.previewSection, p.holder }) do
        local r = Rect(f, pane, VIEW_W, VIEW_H)
        if not (r and Inside(r, base)) then bad = bad or ((f.title and f.title:GetText() or "holder") .. " " .. R(r)) end
    end
    local hold = Rect(p.holder, pane, VIEW_W, VIEW_H)
    local widest = 0
    if CS.TEXT_COLS then widest = CS.TEXT_COLS.outline + 64 end
    local width = hold and (hold.r - hold.l) or 0
    return bad == nil and width >= widest + 10 and #TitledUnder(p.content) == 4,
        (bad or "") .. string.format(" holder %s, rows need %d", R(hold), widest)
end)

Try("every titled pane of Settings -> General lies inside the view", function()
    FindLook()
    local base = generalPane -- T119: the shared General pane on both lines
    local bad, n = nil, 0
    local all = { l = 0, t = 0, r = VIEW_W, b = -VIEW_H }
    for _, t in ipairs(TitledUnder(base)) do
        n = n + 1
        local r = Rect(t, base, VIEW_W, VIEW_H)
        if not (r and Inside(r, all)) then bad = bad or (t.title:GetText() .. " " .. R(r)) end
    end
    return base ~= nil and bad == nil and n >= 6, bad or (n .. " panes")
end)

--------------------------------------------------------------------------------
T.section("11. a fight")
--------------------------------------------------------------------------------
Try("(Live) in a fight paints without raising, and no word on the pane is a secret", function()
    ST:SelectView("settings", "clock")
    Click(p.chips[1])
    S.Fire("PLAYER_REGEN_DISABLED")
    local okRun, err = pcall(function()
        for _ = 1, 6 do Tick(1) end
        CS.PaintPreview(p)
    end)
    local secret
    for _, fs in ipairs(FontStrings(pane)) do
        local v = rawget(fs, "text")
        if v ~= nil and type(v) ~= "string" then secret = secret or tostring(type(v)) end
    end
    S.Fire("PLAYER_REGEN_ENABLED")
    Tick(2)
    return okRun and secret == nil, err or secret
end)

T.done()
