-- tools/run.sh [--flavour tbc|forever] tools/clocksettings.lua
--
-- T102 (docs/SPEC-next.md 5.4, 6.3, 7.3-7.4, section 11 row T102; mockups
-- M7b, M8f, M8g, M9d): the Settings join point, UI/ClockSettings.lua, on both
-- lines. The flavour's whole TOC is loaded -- TBC's UI files and both lines'
-- Integrations/ included -- with the stub's geometry on and fake hosts
-- installed BEFORE the TOC (tools/stub_hosts.lua: LibDataBroker on both,
-- ElvUI's datatexts on TBC, EllesmereUI 9.3.4 on Forever), so the
-- INTEGRATIONS pane has something to say. UI/ClockSettings.lua is loaded where
-- the integrator's TOC line puts it (right after UI/Widget.lua on TBC, right
-- after UI/Clock_Forever.lua on Forever) when the TOC does not list it yet.
--
-- What is held, on both flavours:
--   1. Settings has a Clock view (TBC general, clock, about; Forever general,
--      clock, modules, about); its pane has PREVIEW and LAYOUT and the level-3
--      box (Colours, Frame, Bars, Show, When), and the preview is a frame of
--      its own -- neither the clock on screen nor a child of it;
--   2. each state chip paints its ClockFace.SAMPLES face, as this line draws a
--      face (Forever: "~", one colour, "0:15", no arrow), into the preview --
--      the words checked against the face built here from SAMPLES, not
--      through the pane's own helper -- and the clock on screen is untouched
--      (its words, its shown state, no Show / Hide on it); (Live) paints
--      MD.ClockFace.Current;
--   3. the layout buttons save db.clockLook.layout (CLOCK_LOOK once) and the
--      clock on screen and the preview rebuild in it;
--   4. a control writes db.clockLook.over -- a tone swatch, Mana colour, the
--      Bars tab (bars.<layout>.*, kept per layout), the Frame tab (width,
--      height with the minimum named, scale on release, alpha), the rule
--      chips (T115) -- and the clock on
--      screen rebuilds with it; Reset to style empties it, the layout kept;
--   5. Show / When hold the line's own switches (the rest segment: the
--      preview's rest chip loses it, and so does MD.ClockLook, the broker's
--      look); the When tab's lock;
--   6. the Look dropdown on General (TBC Windows pane, Forever APPEARANCE)
--      lists every registered style (Ellesmere by UI.Ellesmere.Label), writes
--      db.ui.style and repaints at once (STYLE_CHANGED once, the palette is
--      the style's), the reload line shows UI.Restyle.Line() while the look
--      differs from the login's (hidden while UI.Restyle.Left() is 0, as since
--      the wave N4 integration); "Use my class colour" puts the class colour over a style's
--      accent and takes it back;
--   7. the subcommands: /st clock layout compact / nosuch / ring (accepted
--      only where a ring is drawn), look reset, preview; on Forever /st clock
--      and /st clock lock answer exactly as before; on TBC /md clock prints
--      the subs' usage; the help row carries the three subs;
--   8. INTEGRATIONS: the lines are MD.Integrations.Lines(), the broker and
--      compact switches write db.feeds, the hint names the host found (TBC:
--      pick SpellTuner in ElvUI; Forever: /eui -> DataBars) and Forever's
--      EllesmereUI mover switch writes db.eui.unlock; with nothing found the
--      pane says "none found";
--   9. Customise... on the everyday clock pane (TBC OOM Widget, Forever MANA
--      CLOCK) opens Settings -> Clock;
--  10. every word the new panes draw is ASCII with no bare pipe, and every
--      titled pane of Settings -> General and of Settings -> Clock lies inside
--      its view (the windows' fixed sizes, TBC 1036 x 646, Forever 860 x 560);
--  11. Forever, under the stub's forever profile: (Live) in a fight paints
--      without raising and no font string of the pane holds a secret.
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

local MD = {}
local toc = "SpellTuner_TBC.toc"
if forever then
    S.UseProfile("forever")
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

local UI = MD.UI or {}
local CS = MD.ClockSettings or {}
local CV = MD.ClockView or {}
local CF = MD.ClockFace or {}
local W = MD.ClockWidget or {}
local widget = W.frame

-- the first run's placing preview ended, the clock locked
if MD.db then MD.db.locked = true end
if W.Preview then pcall(W.Preview, W, 0) end
if forever and MD.db and type(MD.db.clock) == "table" then MD.db.clock.locked = true end

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
if MD.RegisterCallback then
    MD:RegisterCallback("CLOCK_LOOK", function() counts.CLOCK_LOOK = counts.CLOCK_LOOK + 1 end)
    MD:RegisterCallback("STYLE_CHANGED", function() counts.STYLE_CHANGED = counts.STYLE_CHANGED + 1 end)
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

local function Over()
    local l = MD.db and MD.db.clockLook
    return type(l) == "table" and type(l.over) == "table" and l.over or {}
end
local function WidgetLook() return W.view and W.view.look or {} end

-- the faces as this line draws them: SAMPLES, with Forever's marks on Forever
local function LineFace(key)
    for _, s in ipairs(CF.SAMPLES or {}) do
        if s.key == key then
            local f = {}
            for k, v in pairs(s.face) do f[k] = v end
            if forever then f.modelled, f.mono, f.timeFmt, f.arrow, f.unstable = true, true, "mss", nil, false end
            return f
        end
    end
end
local WARMUP = { mode = "warmup", label = "OOM", known = "pending", tone = "muted" }
local function Words(face, look)
    return CF.JoinSegments(CF.Segments(face or WARMUP, look) or CF.Segments(WARMUP, look))
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
-- 108-px column, 8-px pads, a 24-px view row)
local VIEW_W = forever and (860 - 108 - 16) or (1036 - 108 - 16)
local VIEW_H = forever and (560 - 24 - 16) or (646 - 24 - 16)

--------------------------------------------------------------------------------
T.section("1. Settings -> Clock")
--------------------------------------------------------------------------------
check("UI/ClockSettings.lua loaded (" .. (listed and "listed by the TOC" or "where the TOC line goes") .. ")",
    loadedOK and type(CS.Build) == "function", loadErr and tostring(loadErr))

local pane, p
Try("the Settings group has a Clock view, after General", function()
    MD:SelectView("settings", "general") -- the Forever window is built on first use
    local ids = {}
    for _, g in ipairs(navGroups) do
        if g.id == "settings" then
            for _, v in ipairs(g.views or {}) do ids[#ids + 1] = v.id end
        end
    end
    local want = forever and "general,clock,modules,about" or "general,clock,about"
    return table.concat(ids, ",") == want, table.concat(ids, ",")
end)

Try("selecting it builds the pane: PREVIEW, LAYOUT, the box with five tabs", function()
    MD:SelectView("settings", "clock")
    for _, f in ipairs(S.allFrames) do if f.clockSettings then pane, p = f, f.clockSettings end end
    local g, v = MD:SelectedView()
    local titles = {}
    for _, t in ipairs(TitledUnder(pane)) do titles[#titles + 1] = t.title:GetText() end
    local tabs = {}
    for _, t in ipairs(CS.TABS or {}) do tabs[#tabs + 1] = t.id end
    return g == "settings" and v == "clock" and pane ~= nil and pane:IsVisible()
        and table.concat(titles, ",") == "PREVIEW,LAYOUT" and p.box ~= nil
        and table.concat(tabs, ",") == "colours,frame,bars,show,when",
        string.format("%s/%s titles %s", tostring(g), tostring(v), table.concat(titles, ","))
end)

Try("the preview is a frame of its own, not the clock on screen nor a child of it", function()
    local f = p.previewFrame
    local up, guard, child = f and f.parentFrame, 0, false
    while up and guard < 20 do
        if up == widget then child = true end
        up, guard = up.parentFrame, guard + 1
    end
    return f ~= nil and widget ~= nil and f ~= widget and not child and p.view ~= W.view
end)

--------------------------------------------------------------------------------
T.section("2. the chips paint the SAMPLES faces into the preview; the clock is untouched")
--------------------------------------------------------------------------------
Try("each chip paints its face, as this line draws one", function()
    local before = W.view and W.view:Text()
    local shownBefore = widget and widget:IsShown()
    local n0 = #visCalls
    local bad, n = {}, 0
    for _, b in ipairs(p.chips) do
        if b.id ~= "live" then
            Click(b)
            n = n + 1
            local want = Words(LineFace(b.id), p.look)
            local got = p.view:Text()
            if got ~= want or p.chip ~= b.id then bad[#bad + 1] = b.id .. ": " .. tostring(got) .. " / " .. want end
        end
    end
    local untouched = W.view:Text() == before and widget:IsShown() == shownBefore and #visCalls == n0
    return n == 8 and #bad == 0 and untouched,
        string.format("%d chips, %s; clock untouched %s (%d Show/Hide)", n, table.concat(bad, "; "),
            tostring(untouched), #visCalls - n0)
end)

Try("the chips are the eight of 7.4 after (Live), named as SAMPLES names them", function()
    local names = {}
    for _, b in ipairs(p.chips) do names[#names + 1] = b:GetText() end
    return table.concat(names, ",") == "(Live),OOM,OOM <20s,bound,hold,warm-up,FULL,rest,ooc", table.concat(names, ",")
end)

Try("(Live) paints the line's own face (MD.ClockFace.Current)", function()
    Click(p.chips[1])
    local okF, face = pcall(CF.Current, GetTime())
    local want = Words(okF and face or nil, p.look)
    Tick(1)
    okF, face = pcall(CF.Current, GetTime())
    local want2 = Words(okF and face or nil, p.look)
    return p.chip == "live" and p.view:Text() == want2, tostring(p.view:Text()) .. " / " .. want .. " / " .. want2
end)

--------------------------------------------------------------------------------
T.section("3. the layout buttons")
--------------------------------------------------------------------------------
Try("a layout button saves db.clockLook.layout, CLOCK_LOOK once, the clock and the preview rebuild", function()
    local b
    for _, x in ipairs(p.layoutButtons) do if x.id == "compact" then b = x end end
    local n0 = counts.CLOCK_LOOK
    Click(b)
    local saved = MD.db.clockLook.layout == "compact"
    local fired = counts.CLOCK_LOOK - n0
    local rebuilt = WidgetLook().layout == "compact" and p.look.layout == "compact"
    local ids = {}
    for _, x in ipairs(p.layoutButtons) do ids[#ids + 1] = x.id end
    for _, x in ipairs(p.layoutButtons) do if x.id == "line" then Click(x) end end
    return saved and fired == 1 and rebuilt and MD.db.clockLook.layout == "line"
        and table.concat(ids, ",") == table.concat(CV.LAYOUTS, ","),
        string.format("saved %s fired %d rebuilt %s buttons %s", tostring(saved), fired, tostring(rebuilt),
            table.concat(ids, ","))
end)

--------------------------------------------------------------------------------
T.section("4. a control writes db.clockLook.over; the clock rebuilds")
--------------------------------------------------------------------------------
Try("Colours: a tone's swatch writes colors.<tone>, on the clock and the preview", function()
    p.box:Select("colours")
    local row = p.toneRows and p.toneRows.crit
    local sw
    for _, b in ipairs(row and row.swatches or {}) do if b.hex == "00ccff" then sw = b end end
    Click(sw)
    local o = Over()
    return sw ~= nil and o.colors and o.colors.crit == "00ccff" and WidgetLook().colors.crit == "00ccff"
        and p.look.colors.crit == "00ccff"
end)

Try("Colours: Mana colour writes colors.manaBar (by tone, class, a swatch); the strip keeps its own", function()
    p.box:Select("colours")
    local ids = {}
    for _, it in ipairs(p.manaColour and p.manaColour.items or {}) do ids[#ids + 1] = it.id end
    local picked = Pick(p.manaColour, "tone")
    local toneOK = Over().colors and Over().colors.manaBar == "tone" and WidgetLook().colors.manaBar == "tone"
    local sw
    for _, b in ipairs(p.manaColourRow and p.manaColourRow.swatches or {}) do if b.hex == "ff8000" then sw = b end end
    Click(sw)
    local c = Over().colors and Over().colors.manaBar
    local fixed = type(c) == "table" and math.abs(c[1] - 1) < 1e-9 and math.abs(c[2] - 0x80 / 255) < 1e-9
        and p.manaColour.value == "fixed"
    Click(p.manaColourRow and p.manaColourRow.reset)
    local back = Over().colors == nil or Over().colors.manaBar == nil
    return table.concat(ids, ",") == "mana,tone,class,fixed" and picked and toneOK and fixed and back,
        string.format("items %s, tone %s, fixed %s, back %s", table.concat(ids, ","), tostring(toneOK),
            tostring(fixed), tostring(back))
end)

Try("Bars: each dropdown and the 5SR thickness write bars.<layout>.*; the clock draws them", function()
    p.box:Select("bars")
    local picks = Pick(p.showDropdown, "mana") and Pick(p.showDropdown, "both") and Pick(p.joinDropdown, "veil")
        and Pick(p.orderDropdown, "fsrOver") and Pick(p.afterDropdown, "empty")
    Type(p.fsrSlider, "5")
    local o = Over().bars and Over().bars.line or {}
    local wl = WidgetLook().bars or {}
    local okW = o.show == nil and o.join == "veil" and o.order == "fsrOver" and o.after == "empty" and o.fsr == 5
        and wl.join == "veil" and wl.order == "fsrOver" and wl.after == "empty" and wl.fsr == 5
        and p.look.bars.join == "veil"
    return picks and okW, string.format("picks %s, over join %s order %s after %s fsr %s show %s", tostring(picks),
        tostring(o.join), tostring(o.order), tostring(o.after), tostring(o.fsr), tostring(o.show))
end)

Try("Bars: the choices are this line's (" .. (forever and "Mana from; no tick; flat only" or "the tick; three textures; no Mana from") .. ")", function()
    local function Ids(dd)
        local ids = {}
        for _, it in ipairs(dd and dd.items or {}) do ids[#ids + 1] = it.id end
        return table.concat(ids, ",")
    end
    local show, join, order = Ids(p.showDropdown), Ids(p.joinDropdown), Ids(p.orderDropdown)
    local after, tex, mana = Ids(p.afterDropdown), Ids(p.textureDropdown), p.manaDropdown and Ids(p.manaDropdown)
    local common = show == "both,mana,fsr,none" and join == "stacked,veil,chip" and order == "manaOver,fsrOver"
    local own
    if forever then
        own = after == "green,empty" and tex == "flat" and mana == "game,model"
            and T.Has(p.afterNote and p.afterNote:GetText(), "cannot be learned")
    else
        own = after == "green,empty,tick" and tex == "flat,statusbar,raid" and mana == nil
    end
    return common and own, string.format("show %s join %s order %s after %s texture %s mana %s", show, join, order,
        after, tex, tostring(mana))
end)

Try("Bars: a choice is kept per layout (compact has its own; line's comes back)", function()
    for _, x in ipairs(p.layoutButtons) do if x.id == "compact" then Click(x) end end
    local fresh = p.joinDropdown.value == "stacked"
    Pick(p.joinDropdown, "chip")
    local compactSet = Over().bars.compact and Over().bars.compact.join == "chip"
    for _, x in ipairs(p.layoutButtons) do if x.id == "line" then Click(x) end end
    local lineBack = p.joinDropdown.value == "veil" and WidgetLook().bars.join == "veil"
    return fresh and compactSet and lineBack, string.format("fresh %s, compact %s, line back %s", tostring(fresh),
        tostring(compactSet), tostring(lineBack))
end)

Try("Frame: width and height write frame.<layout>.w / h; each slider names the layout's minimum", function()
    p.box:Select("frame")
    Type(p.hSlider, "44")
    Type(p.wSlider, "260")
    local fr = Over().frame and Over().frame.line or {}
    local mw, mh = p.view:Minimum()
    local wl = WidgetLook().frame or {}
    local okF = fr.w == 260 and fr.h == 44 and wl.w == 260 and wl.h == 44
    local okMin = p.wMin and p.wMin:GetText() == "min " .. mw and p.hMin and p.hMin:GetText() == "min " .. mh
    local note = false
    for _, fs in ipairs(FontStrings(p.tabFrames.frame)) do
        if fs:GetText() == "Width, height and scale are kept per layout." then note = true end
    end
    return okF and okMin and note, string.format("over %s x %s, min %s / %s (%s x %s), note %s", tostring(fr.w),
        tostring(fr.h), tostring(p.wMin and p.wMin:GetText()), tostring(p.hMin and p.hMin:GetText()), tostring(mw),
        tostring(mh), tostring(note))
end)

Try("Frame: Scale writes frame.<layout>.scale on release (a drag alone writes nothing)", function()
    local n0 = counts.CLOCK_LOOK
    if p.scaleSlider.onValueChangedFn then p.scaleSlider.onValueChangedFn(150) end
    local dragged = (Over().frame.line.scale == nil) and counts.CLOCK_LOOK == n0
    Type(p.scaleSlider, "150")
    local released = Over().frame.line.scale == 150 and WidgetLook().frame.scale == 150
        and math.abs(widget:GetScale() - 1.5) < 1e-9
    Type(p.scaleSlider, "100")
    return dragged and released, string.format("drag wrote nothing %s, release %s", tostring(dragged),
        tostring(released))
end)

Try("Frame: the background alpha writes panel.fill with the fill's colour", function()
    Type(p.alphaSlider, "50")
    local f = Over().panel and Over().panel.fill
    return type(f) == "table" and math.abs((f[4] or 0) - 0.5) < 1e-9
        and math.abs((UI.SkinColour(WidgetLook().panel.fill) or {})[4] - 0.5) < 1e-9
end)

Try("the rule chips paint the preview's five-second rule: 3.0 s left, just cast, regen running", function()
    local names, res = {}, {}
    for _, b in ipairs(p.ruleChips or {}) do names[#names + 1] = b:GetText() end
    MD.ClockView.ResetToStyle()
    Click(p.chips[2]) -- a sample face
    for _, b in ipairs(p.ruleChips or {}) do
        Click(b)
        res[b.id] = p.view.strip and p.view.strip.value
    end
    local okR = math.abs((res.rule or -1) - 2) < 0.05 and math.abs((res.cast or -1) - 0) < 0.05
        and math.abs((res.regen or -1) - 5) < 1e-9
    return table.concat(names, ",") == "in the rule, 3.0 s left,just cast,regen running" and okR,
        string.format("%s: rule %s cast %s regen %s", table.concat(names, ","), tostring(res.rule),
            tostring(res.cast), tostring(res.regen))
end)

Try("Reset to style empties the overrides and keeps the layout", function()
    MD.ClockView.SetLayout("bar")
    local n0 = counts.CLOCK_LOOK
    Click(p.resetButton)
    local empty = next(Over()) == nil
    local kept = MD.db.clockLook.layout == "bar" and WidgetLook().layout == "bar"
    local fired = counts.CLOCK_LOOK - n0
    MD.ClockView.SetLayout("line")
    return empty and kept and fired == 1 and WidgetLook().colors.crit == nil
end)

--------------------------------------------------------------------------------
T.section("5. Show and When: the line's own switches")
--------------------------------------------------------------------------------
local function SwitchNamed(text)
    for _, cb in ipairs(p.switches or {}) do if cb.def.text:find(text, 1, true) == 1 then return cb end end
end

Try("Show: the rest switch is the line's; the rest chip and the broker's look drop the segment", function()
    p.box:Select("show")
    local cb = SwitchNamed("Rest time")
    local restChip
    for _, b in ipairs(p.chips) do if b.id == "rest" then restChip = b end end
    Click(restChip)
    local with = p.view:Text()
    cb:SetChecked(false); cb.onClick(false, cb)
    Tick(1)
    local key
    if forever then key = MD.db.clock and MD.db.clock.showRest else key = MD.db.showRest end
    local without = p.view:Text()
    local look = MD.ClockLook and MD.ClockLook()
    local brokerOff = type(look) == "table" and look.show and look.show.rest == false
    cb:SetChecked(true); cb.onClick(true, cb)
    Tick(1)
    local back = p.view:Text()
    return cb ~= nil and key == false and T.Has(with, "rest ") and not T.Has(without, "rest ")
        and back == with and brokerOff,
        string.format("with %q without %q back %q key %s broker %s", tostring(with), tostring(without),
            tostring(back), tostring(key), tostring(brokerOff))
end)

Try("When: Locked is the line's own lock", function()
    p.box:Select("when")
    local cb = SwitchNamed("Locked")
    cb:SetChecked(false); cb.onClick(false, cb)
    local off = forever and MD.db.clock.locked == false or (not forever and MD.db.locked == false)
    cb:SetChecked(true); cb.onClick(true, cb)
    local on = forever and MD.db.clock.locked == true or (not forever and MD.db.locked == true)
    if W.Preview then W:Preview(0) end
    return cb ~= nil and off and on
end)

--------------------------------------------------------------------------------
T.section("6. the Look dropdown and Use my class colour")
--------------------------------------------------------------------------------
local look, generalPane
local function FindLook()
    MD:SelectView("settings", "general")
    if not forever and MD.ShowOptionsFrame then MD:ShowOptionsFrame("general") end
    for _, f in ipairs(S.allFrames) do
        if f.lookControls then look, generalPane = f.lookControls, f end
    end
    if forever then
        for _, f in ipairs(S.allFrames) do if f.fontSlider then generalPane = f end end
    end
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
    local label = p.styleLabel:GetText()
    return picked and hidden and MD.db.ui.style == "ellesmere" and UI.STYLE == "ellesmere" and fired == 1
        and repainted and shown and T.Has(label, "style: Ellesmere"),
        string.format("fired %d repainted %s reload %s label %q", fired, tostring(repainted), tostring(shown),
            tostring(label))
end)

Try("Use my class colour puts the class colour over the style's accent, and takes it back", function()
    local styleAccent = { UI.accent[1], UI.accent[2], UI.accent[3] }
    local n0 = counts.STYLE_CHANGED
    local cb = look.classCheck
    cb:SetChecked(true); cb.onClick(true, cb)
    local on = MD.db.useClassColour == true and math.abs(UI.accent[1] - UI.classAccent[1]) < 1e-6
        and math.abs(UI.accent[2] - UI.classAccent[2]) < 1e-6 and math.abs(UI.accent[3] - UI.classAccent[3]) < 1e-6
    local fired = counts.STYLE_CHANGED - n0
    cb:SetChecked(false); cb.onClick(false, cb)
    local off = MD.db.useClassColour == false and math.abs(UI.accent[1] - styleAccent[1]) < 1e-6
        and math.abs(UI.accent[3] - styleAccent[3]) < 1e-6
    local differs = math.abs(styleAccent[1] - UI.classAccent[1]) > 1e-6 or math.abs(styleAccent[3] - UI.classAccent[3]) > 1e-6
    return on and off and fired == 1 and differs, string.format("on %s off %s fired %d", tostring(on), tostring(off), fired)
end)

Try("back to Flat: the palette is Flat's, the reload line hides, the clock pane says Flat", function()
    Pick(look.dropdown, "flat")
    local flatBg = UI.FLAT.palette.bg
    local r, g, b = UI.Fill("bg")
    return MD.db.ui.style == "flat" and not look.reload:IsShown() and math.abs(r - flatBg[1]) < 1e-9
        and math.abs(b - flatBg[3]) < 1e-9 and T.Has(p.styleLabel:GetText(), "style: Flat")
end)

--------------------------------------------------------------------------------
T.section("7. the subcommands")
--------------------------------------------------------------------------------
local slash = SlashCmdList and SlashCmdList.SPELLTUNER
Try("/st clock layout compact saves it; nosuch is refused, naming the layouts", function()
    local a = Plain(Chat(function() slash("clock layout compact") end))
    local saved = MD.db.clockLook.layout == "compact" and WidgetLook().layout == "compact"
    local b = Plain(Chat(function() slash("clock layout Nosuch") end))
    local kept = MD.db.clockLook.layout == "compact"
    slash("clock layout line")
    return a[1] == "mana clock: layout compact" and saved and kept
        and b[1] == "mana clock: unknown layout 'nosuch' (layouts: " .. table.concat(CV.LAYOUTS, ", ") .. ")",
        tostring(a[1]) .. " | " .. tostring(b[1])
end)

Try("/st clock layout ring: saved where a ring is drawn (T104), else refused", function()
    local lines = Plain(Chat(function() slash("clock layout ring") end))
    local drawn = CV.LAYOUT and CV.LAYOUT.ring ~= nil
    local okR
    if drawn then
        okR = MD.db.clockLook.layout == "ring" and lines[1] == "mana clock: layout ring"
    else
        okR = MD.db.clockLook.layout == "line" and T.Has(lines[1], "unknown layout 'ring'")
    end
    slash("clock layout line")
    return okR, tostring(lines[1])
end)

Try("/st clock look reset empties the overrides; /st clock look alone prints its usage", function()
    MD.ClockView.Set("colors.warn", "123456")
    local a = Plain(Chat(function() slash("clock look reset") end))
    local b = Plain(Chat(function() slash("clock look") end))
    return next(Over()) == nil and a[1] == "mana clock: every colour and bar setting back to the look's own"
        and b[1] == "usage: /st clock look reset"
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
        MD.db.clock.shown, MD.db.clock.locked = true, false
        local a = Plain(Chat(function() slash("clock") end))
        local hidden = MD.db.clock.shown == false
        local b = Plain(Chat(function() slash("clock") end))
        local c = Plain(Chat(function() slash("clock lock") end))
        local d = Plain(Chat(function() slash("clock lock") end))
        MD.db.clock.locked = true
        return hidden and a[1] == "mana clock: hidden" and b[1] == "mana clock: shown" and c[1] == "mana clock: locked"
            and d[1] == "mana clock: unlocked" and #a == 1 and #b == 1 and #c == 1 and #d == 1,
            table.concat({ a[1] or "", b[1] or "", c[1] or "", d[1] or "" }, " | ")
    end)
else
    Try("TBC: /md clock alone prints the subs' usage", function()
        local a = Plain(Chat(function() slash("clock") end))
        return table.concat(a, " | ") == "usage: /st clock layout <name> | usage: /st clock look reset | "
            .. "usage: /st clock preview", table.concat(a, " | ")
    end)
end

Try("the clock's help row carries layout, look reset and preview", function()
    local row
    for _, c in ipairs(MD:Commands()) do if c.name == "clock" then row = c end end
    local want = forever and "/st clock [lock] / rest / clickthrough / layout <name> / look reset / preview"
        or "/st clock layout <name> / look reset / preview"
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

Try("the pane shows MD.Integrations.Lines(), one line each", function()
    integ:Refresh()
    local want = MD.Integrations.Lines()
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
    local off = MD.db.feeds.ldb == false
    ldb:SetChecked(true); ldb.onClick(true, ldb)
    compact:SetChecked(true); compact.onClick(true, compact)
    local c = MD.db.feeds.compact == true
    compact:SetChecked(false); compact.onClick(false, compact)
    return off and MD.db.feeds.ldb == true and c and MD.db.feeds.compact == false
end)

if forever then
    Try("Forever with EllesmereUI: the /unlock mover switch is shown and writes db.eui.unlock", function()
        local mover
        for _, cb in ipairs(integ.switches) do if T.Has(cb.def.text, "mover") then mover = cb end end
        integ:Refresh()
        local shown = mover and mover:IsShown()
        mover:SetChecked(false); mover.onClick(false, mover)
        local off = MD.db.eui.unlock == false
        mover:SetChecked(true); mover.onClick(true, mover)
        return shown and off and MD.db.eui.unlock == true
    end)
end

Try("with nothing found the pane says so", function()
    local keep = MD.Integrations
    MD.Integrations = nil
    local lines = CS.IntegrationLines()
    MD.Integrations = keep
    return #lines == 1 and lines[1] == "none found"
end)

--------------------------------------------------------------------------------
T.section("9. Customise... on the everyday clock pane")
--------------------------------------------------------------------------------
Try("Customise... opens Settings -> Clock", function()
    FindLook()
    local b
    for _, f in ipairs(S.allFrames) do
        if forever and f.clockCustomise then b = f.clockCustomise end
        if not forever and f.customiseButton then b = f.customiseButton end
    end
    Click(b)
    local g, v = MD:SelectedView()
    return b ~= nil and g == "settings" and v == "clock" and b:GetText() == "Customise...", tostring(g) .. "/" .. tostring(v)
end)

--------------------------------------------------------------------------------
T.section("10. words and places")
--------------------------------------------------------------------------------
Try("every word the clock view and the INTEGRATIONS pane draw is ASCII, no bare pipe", function()
    local bad
    local tops = { pane, integ }
    if look then tops[#tops + 1] = look.reload end
    for _, chip in ipairs(p.chips) do Click(chip) end
    for _, tab in ipairs(CS.TABS) do p.box:Select(tab.id) end
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
    return bad == nil and n > 40, bad or (n .. " strings")
end)

Try("every titled pane of Settings -> Clock lies inside the view", function()
    local bad
    local box = Rect(p.box.frame, pane, VIEW_W, VIEW_H)
    local base = { l = 0, t = 0, r = VIEW_W, b = -VIEW_H }
    for _, t in ipairs(TitledUnder(pane)) do
        local r = Rect(t, pane, VIEW_W, VIEW_H)
        if not (r and Inside(r, base)) then bad = bad or (t.title:GetText() .. " " .. R(r)) end
    end
    if not (box and Inside(box, base)) then bad = bad or ("the box " .. R(box)) end
    for _, b in ipairs({ p.showButton, p.placeButton }) do
        local r = Rect(b, pane, VIEW_W, VIEW_H)
        if not (r and Inside(r, base)) then bad = bad or (b:GetText() .. " " .. R(r)) end
    end
    return bad == nil, bad
end)

Try("every titled pane of Settings -> General lies inside the view", function()
    FindLook()
    local base = forever and generalPane or (MD.optionsFrame and _G.SpellTunerOptionsFrame_GeneralTab)
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
    MD:SelectView("settings", "clock")
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
