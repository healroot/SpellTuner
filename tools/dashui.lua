-- tools/run.sh tools/dashui.lua
--
-- The dashboard under the stub (docs/SPEC-v0.11.md §4, v0.11.1): the window is
-- now the navigation kit, so this drives it the way a mouse would -- click a
-- group, click a view, read back what was painted and which panes exist.
--
-- It also holds the line the spec draws under the move: /md must behave exactly
-- as it did, and a pane must not know it lives in a different window.
local here = arg[0]:match("^(.*)/[^/]+$")
HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB
-- T84 (C5): Spells/Tabs.lua and Spells/Families_TBC.lua are on the TBC TOC
-- (the harness loads them from it); on a tree whose TOC does not list them
-- yet they are loaded here, before the dashboard is built, with the same
-- existence guard as the UI files below.
do
    local need = {}
    if not MD.Tabs then need[#need + 1] = "Spells/Tabs.lua" end
    if not MD.FamiliesTBC then need[#need + 1] = "Spells/Families_TBC.lua" end
    local present = {}
    for _, rel in ipairs(need) do
        local fh = io.open((S.root or ".") .. "/" .. rel, "r")
        if fh then fh:close(); present[#present + 1] = rel end
    end
    if #present > 0 then S.Load(present, "SpellTuner", MD) end
end
-- T80 (C1): the theme and the window manager after the kit, as the TBC TOC lists them.
-- T83 (C3): the Spells view before UI/Dashboard.lua; before T83 the file did
-- not exist, and the guard lets this suite run on such a commit and fail
-- check by check.
local UI_FILES = { "UI/Style.lua", "UI/Theme_Flat.lua", "UI/EscStack.lua", "UI/Windows.lua",
         "UI/Tip.lua", "UI/Tip_TBC.lua", "UI/Dashboard_Rows.lua", "UI/SpellRail.lua", "UI/Dashboard_Simulate.lua",
         "UI/Dashboard_Waste.lua", "UI/Dashboard_Review.lua", "UI/PracticePanel.lua", "UI/SpellsView_TBC.lua",
         "UI/Dashboard.lua" }
do
    local present = {}
    for _, rel in ipairs(UI_FILES) do
        local fh = io.open((S.root or ".") .. "/" .. rel, "r")
        if fh then fh:close(); present[#present + 1] = rel end
    end
    S.Load(present, "SpellTuner", MD)
end

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-48s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end
local chat = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }

-- the dashboard builds on MD_READY. The harness has already fired it, and
-- firing it again used to build a SECOND window whose buttons shadowed the
-- first: CreateDashboard is idempotent now, and this asserts it.
MD:Fire("MD_READY")

local frame = _G.SpellTunerDashboard
check("the dashboard exists", frame ~= nil)
check("firing MD_READY twice does not build a second one", (function()
    local n = 0
    for _, f in ipairs(S.allFrames) do if f.frameName == "SpellTunerDashboard" then n = n + 1 end end
    return n == 1
end)())
check("it is one window, not two", frame ~= MD.optionsFrame)

local function ButtonNamed(text)
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Button" and f.text == text and f.shown ~= false then return f end
    end
    return nil
end
local function Click(b) local fn = b and b:GetScript("OnClick"); if fn then fn(b) end end
-- what the eye sees: shown, and every parent shown too
local function ShownText(pat)
    for _, f in ipairs(S.allFrames) do
        local t = f.GetText and f:GetText() or ""
        if type(t) == "string" and t:find(pat) and f:IsVisible() then return t end
    end
    return nil
end
local function ShownButton(text)
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Button" and f.text == text and f:IsVisible() then return true end
    end
    return false
end

local function Painted(pat)
    for _, f in ipairs(S.allFrames) do
        local t = f.GetText and f:GetText() or ""
        if type(t) == "string" and t:find(pat) then return t end
    end
    return nil
end

-- T84 (C5): the Spells group is a rail; its rows are the views
local function SpellsRail()
    local sp = MD.SpellsTBC
    return sp and sp.nav and sp.nav:Rail("spells") or nil
end
local function RailRow(id)
    local rail = SpellsRail()
    for _, r in ipairs(rail and rail:Rows() or {}) do if r.id == id then return r end end
    return nil
end
local function RailIds()
    local ids = {}
    local rail = SpellsRail()
    for _, r in ipairs(rail and rail:Rows() or {}) do ids[#ids + 1] = r.id end
    return table.concat(ids, ",")
end
local function RailClick(id)
    local r = RailRow(id)
    if r then r:GetScript("OnClick")(r, "LeftButton") end
    return r
end

check("the four groups are the author's, minus the two still to move",
    ButtonNamed("Spells") ~= nil and ButtonNamed("Reports") ~= nil)

MD:ToggleDashboard()
check("it opens", frame:IsShown())

-- opening lands on a spell, and the rank table is built
-- T84 (C5): the first open is Overview, the rail's first row
check("it opens on a spell", MD.db.uiPath and MD.db.uiPath[1] == "spells",
    MD.db.uiPath and table.concat(MD.db.uiPath, "/") or "no path")
-- T83 (C3): the Spells view -- its RANKS pane, and What if... in its strip
-- T84 (C5): a family's rail row opens it
RailClick("fam:HealingTouch")
check("the rank table is built for it", ShownText("^RANKS$") ~= nil)
check("the Simulate strip is with the spells", ButtonNamed("What if...") ~= nil and ButtonNamed("Clear") ~= nil)

-- switching families keeps the group
-- T84 (C5): a family is a rail row, not a view button
local rg = RailRow("fam:Regrowth")
check("a family rail row exists", rg ~= nil, RailIds())
RailClick("fam:Regrowth")
check("clicking a family selects it", MD.db.uiPath[2] == "fam:Regrowth", MD.db.uiPath[2])

-- Reports: a different group, its own views, built on first sight
Click(ButtonNamed("Reports"))
check("Reports selects its first view", MD.db.uiPath[1] == "reports" and MD.db.uiPath[2] == "Waste",
    table.concat(MD.db.uiPath, "/"))
check("the Waste pane says what it is", Painted("Where the mana went") ~= nil)
Click(ButtonNamed("Review"))
check("Review is a view of Reports", MD.db.uiPath[2] == "Review", MD.db.uiPath[2])
check("the Review pane is built", Painted("The fights this character recorded") ~= nil)
check("Review's own buttons came with it", ButtonNamed("Validate") ~= nil
    and ButtonNamed("Play") ~= nil and ButtonNamed("Start run") ~= nil)

-- back to a spell: the pane is not rebuilt, and the table is drawn again
-- T84 (C5): the Spells group button opens its first row, Overview
Click(ButtonNamed("Spells"))
check("going back to Spells shows its first row, Overview", ShownText("^OVERVIEW$") ~= nil
    and ShownText("^RANKS$") == nil)
check("and the path followed", MD.db.uiPath[1] == "spells", MD.db.uiPath[1])

-- the path is remembered across an open/close
MD:ToggleDashboard()
check("it closes", not frame:IsShown())
Click(ButtonNamed("Reports")); -- no-op while hidden, but must not error
MD:ToggleDashboard()
check("it reopens where it was", frame:IsShown() and MD.db.uiPath[1] ~= nil,
    table.concat(MD.db.uiPath, "/"))

--------------------------------------------------------------------------------
-- Settings is the fourth group, not a second window (v0.11.2)
--------------------------------------------------------------------------------
-- T79 (P36): UI/MinimapButton.lua owns db.minimap's default, which the
-- General pane's "Minimap button" box reads (in game the TOC loads it
-- before anything is shown; registered after login it back-fills MD.db).
-- T119 (SPEC-one-ui 7, re-based): Settings is UI/Settings.lua's views over
-- UI/Settings_TBC.lua's rows (the options frame, its General and About tabs
-- are gone): "the settings panel exists" asks for MD.Settings and no
-- MD.optionsFrame; the general pane is told by its MANA CLOCK's "Lock in
-- place", the danger slider is found on Settings -> Review, About is a view.
S.Load({ "UI/MinimapButton.lua", "UI/Settings.lua", "UI/Settings_TBC.lua" }, "SpellTuner", MD)
check("the settings panel exists", MD.Settings ~= nil and MD.SettingsLine ~= nil and MD.optionsFrame == nil)
check("it is a panel, not a window", _G.SpellTunerOptionsFrame == nil,
    tostring(_G.SpellTunerOptionsFrame))

Click(ButtonNamed("Settings"))
check("Settings is a group of the one window", MD.db.uiPath[1] == "settings",
    table.concat(MD.db.uiPath, "/"))
check("it opens on General", MD.db.uiPath[2] == "general", MD.db.uiPath[2])
check("the general pane is in there", ShownText("^Lock in place$") ~= nil)
MD:SelectView("settings", "review")
-- T73 (P29, review U24): db.simFloor is the line for fights built in
-- Simulate (and a recorded target's fallback); a recorded fight measures its
-- own. The slider says so, and its tooltip does not call it the scoring line.
check("the danger slider names built fights, truly", (function()
    local label
    for _, f in ipairs(S.allFrames) do
        if f.GetText and f:GetText() == "Danger line for built fights (%)" then label = f end
    end
    local slider = label and label:GetParent()
    if not (slider and slider.onEnter) or Painted("Danger below") then return false end
    local tip = MD.UI.tooltip
    tip.lines = {}
    slider.onEnter()
    local all = {}
    for _, l in ipairs(tip.lines or {}) do all[#all + 1] = tostring(l[1]) end
    local text = table.concat(all, " ")
    slider.onLeave()
    return text:find("built in Simulate", 1, true) ~= nil
        and text:find("A recorded fight measures its own line", 1, true) ~= nil
end)())
Click(ButtonNamed("About"))
check("About is one of its views", MD.db.uiPath[2] == "about", MD.db.uiPath[2])

-- T80 (C1 of docs/PLAN-refactor-ux.md, mockup M1): TBC's Settings -> General
-- gains the Windows pane -- In combat, Close one window per ESC, Text size,
-- Window size, Reset window positions -- each writing db.ui through the
-- window manager or the theme. A slider is typed into (its box's Enter runs
-- both callbacks), a dropdown row and a button are clicked.
check("T80: the Windows pane in Settings -> General writes and applies its five controls", (function()
    MD:ShowOptionsFrame("general")
    local wp
    for _, f in ipairs(S.allFrames) do if f.windowsPane then wp = f.windowsPane end end
    if not (wp and wp.combat and wp.esc and wp.font and wp.scale and wp.reset) then return false end
    local function Type(slider, text)
        local eb = slider.currentEditBox
        if not eb then return end
        eb:SetText(text)
        eb:GetScript("OnEnterPressed")(eb)
    end
    local function Pick(dd, id)
        for i, it in ipairs(dd.items or {}) do
            if it.id == id and dd.rows and dd.rows[i] then dd.rows[i]:GetScript("OnClick")(dd.rows[i]) end
        end
    end
    local u = MD.db.ui
    Pick(wp.combat, "keep")
    local combat = u.combat == "keep" and MD.Win:CombatMode() == "keep"
    Pick(wp.combat, "hide")
    combat = combat and u.combat == "hide"
    wp.esc:SetChecked(false); wp.esc.onClick(false, wp.esc)
    local esc = u.escStack == false and not MD.Win:EscStackOn()
    wp.esc:SetChecked(true); wp.esc.onClick(true, wp.esc)
    esc = esc and u.escStack == true and MD.Win:EscStackOn()
    Type(wp.font, "2")
    local font = u.fontOffset == 2 and MD.UI.fontOffset == 2
    Type(wp.font, "0")
    font = font and u.fontOffset == 0
    Type(wp.scale, "90")
    local scale = math.abs((u.scale or 0) - 0.9) < 1e-6 and MD.Win:ScalePercent() == 90
    Type(wp.scale, "100")
    scale = scale and u.scale == 1
    u.win.main = { x = 5, y = 500 }
    Click(wp.reset)
    local reset = next(u.win) == nil
    return combat and esc and font and scale and reset
end)())

-- /md options routes into the group instead of opening anything
Click(ButtonNamed("Spells"))
MD:ShowOptionsFrame("general")
check("/md options selects the settings group", MD.db.uiPath[1] == "settings"
    and MD.db.uiPath[2] == "general", table.concat(MD.db.uiPath, "/"))
check("and it did not open a second window", _G.SpellTunerOptionsFrame == nil)

-- the spell-only furniture is not drawn over the settings
Click(ButtonNamed("Settings"))
check("the rank table's header lines are hidden in Settings", ShownText("^RANKS$") == nil
    and ShownText("^SUGGESTED$") == nil and ShownText("^SIMULATED$") == nil)

--------------------------------------------------------------------------------
-- Simulate is the third group, not a third window (v0.11.3)
--------------------------------------------------------------------------------
S.Load({ "UI/SimWindow.lua" }, "SpellTuner", MD)
Click(ButtonNamed("Simulate"))
check("Simulate is a group of the one window", MD.db.uiPath[1] == "simulate",
    table.concat(MD.db.uiPath, "/"))
-- v0.15.0: Practice is Simulate's first view
check("Simulate opens on Practice", MD.db.uiPath[2] == "practice", table.concat(MD.db.uiPath, "/"))
check("the practice panel has its Start button", ButtonNamed("Start practice") ~= nil)
Click(ButtonNamed("Build a fight"))
check("it did not open a third window", _G.SpellTunerSimWindow == nil)
check("the simulator's own controls came with it", ButtonNamed("Run") ~= nil
    or ButtonNamed("From recordings") ~= nil)
-- the panel builds all the way through: a frame it styles without
-- "BackdropTemplate" would have thrown here rather than in the author's game
check("the simulator's result box exists", (function()
    for _, f in ipairs(S.allFrames) do
        if f.backdrop and f.bg and f.bg[4] == 0.5 then return true end
    end
    return false
end)())

-- /md sim selects the group
Click(ButtonNamed("Spells"))
MD:ToggleSimWindow()
check("/md sim selects Simulate", MD.db.uiPath[1] == "simulate", table.concat(MD.db.uiPath, "/"))
-- ...and toggles the window when it is already what is showing
MD:ToggleSimWindow()
check("/md sim again closes the window", not frame:IsShown())
MD:ToggleDashboard()

--------------------------------------------------------------------------------
-- Runs is a Reports view, and only once there is a run (v0.11.4)
--------------------------------------------------------------------------------
Click(ButtonNamed("Reports"))
check("no Runs view before a run exists", ButtonNamed("Runs") == nil)

MD.cdb.runs = { { v = 1, id = 1757000000, name = "Ramparts", zone = "Ramparts", pool = 7009,
                  dur = 300, pulls = {}, mana = { t = {}, v = {} },
                  ev = { t = {}, kind = {}, a = {}, b = {} }, zones = { "Ramparts" },
                  stats = { pulls = 0, recorded = 0, wall = 300, combat = 0, combatPct = 0,
                            drinks = 0, drinkTime = 0, deaths = 0, deadTime = 0, spent = 0,
                            manaAtPull = {} } } }
MD:Fire("RUN_STORED", MD.cdb.runs[1])
check("storing a run makes the view appear", ButtonNamed("Runs") ~= nil)
Click(ButtonNamed("Runs"))
check("Runs is a view of Reports", MD.db.uiPath[1] == "reports" and MD.db.uiPath[2] == "Runs",
    table.concat(MD.db.uiPath, "/"))
check("it opens on the run, not on the fights", Painted("run Ramparts") ~= nil,
    Painted("run Ramparts") or "the run line was not painted")
Click(ButtonNamed("Review"))
check("Review goes back to the single fights", MD.db.uiPath[2] == "Review", MD.db.uiPath[2])

-- On the Runs view the pane's own Fights/run selector must stick: the 2s
-- ticker calls Refresh, and setting the source there put the run back a second
-- after the author clicked Fights (v0.11.6).
Click(ButtonNamed("Runs"))
check("Runs opens on the run", Painted("run Ramparts") ~= nil)
Click(ButtonNamed("Fights"))
check("clicking Fights inside Runs shows the fights", ShownText("Hellfire") ~= nil
    or ShownText("No recorded fights") ~= nil, ShownText("run Ramparts") or "nothing")
for _ = 1, 6 do S.Tick(0.5) end       -- three ticker refreshes
check("and a refresh does not put the run back", ShownText("run Ramparts") == nil,
    ShownText("run Ramparts"))

-- a pooled row must not show the previous render's cells
check("no stale text in a reused row", (function()
    local seen = 0
    for _, f in ipairs(S.allFrames) do
        local t = f.GetText and f:GetText() or ""
        if type(t) == "string" and t:find("low mana") and f:IsVisible() then seen = seen + 1 end
    end
    return seen <= 1
end)())

--------------------------------------------------------------------------------
-- One group's furniture must not be drawn over another's panel (v0.11.5). The
-- author's screenshots of Simulate had the Spells what-if strip, the regen
-- line, the rank table and the recap painted on top of it.
--------------------------------------------------------------------------------
Click(ButtonNamed("Simulate"))
check("no rank-table hint over the simulator", ShownText("^RANKS$") == nil,
    ShownText("^RANKS$"))
check("no regen line over the simulator", ShownText("healing   regen") == nil,
    ShownText("healing   regen"))
check("no recap line over the simulator", ShownText("No fights recorded") == nil
    and ShownText("Last fight:") == nil, ShownText("Last fight:") or ShownText("No fights recorded"))
check("the what-if strip is not over the simulator", not ShownButton("Clear"))
check("the simulator's own controls are visible", ShownButton("Run") or ShownButton("From recordings")
    or ShownButton("Start practice"))

-- ...and coming from Reports, not just from Spells: the author saw both
Click(ButtonNamed("Reports"))
Click(ButtonNamed("Review"))
Click(ButtonNamed("Simulate"))
check("nor when arriving from Reports", ShownText("The fights this character recorded") == nil
    and ShownText("^RANKS$") == nil,
    ShownText("The fights this character recorded") or ShownText("^RANKS$"))

Click(ButtonNamed("Settings"))
check("nor over the settings", ShownText("^RANKS$") == nil and not ShownButton("Clear")
    and not ShownButton("What if..."))

-- and the Spells furniture comes back when Spells does
-- T84 (C5): Spells comes back on Overview; a family's row brings the view
Click(ButtonNamed("Spells"))
check("Overview comes back with Spells", ShownText("^OVERVIEW$") ~= nil)
RailClick("fam:HealingTouch")
-- T83: the strip is folded behind What if..., which comes back with Spells
check("and so does the what-if strip", ShownButton("What if..."))

-- the rank table is one frame registered under every family: switching family
-- must not leave it hidden (the nav hides everything, then shows the keeper)
RailClick("fam:Regrowth")
check("switching family keeps the table visible", ShownText("^RANKS$") ~= nil)

--------------------------------------------------------------------------------
-- T83 (C3 of docs/PLAN-refactor-ux.md, review U6; mockup M6): the TBC Spells
-- view in the Forever structure -- the header, the chip and one comparison
-- line, the rank table with the suggested row's fill and bar and the
-- selection's white bar, the card, Casts reading inf / 999+, "After
-- overheal" for "Effective", and the Simulate strip folded behind
-- "What if...". The harness druid is level 64: Rejuvenation R6 suggested,
-- R12 the highest known. Each check runs under pcall, so on a commit without
-- the view every one of them fails on its own.
--------------------------------------------------------------------------------
do
    local function Try(name, fn)
        local okRun, cond, detail = pcall(fn)
        if okRun then check(name, cond, detail) else check(name, false, tostring(cond)) end
    end
    local function View()
        for _, f in ipairs(S.allFrames) do
            if f.spellsViewTBC and f:IsVisible() then return f end
        end
        return nil
    end
    local function Plain(fs) return ((fs and fs:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function RowsOf(api)
        local byKey = {}
        for _, f in ipairs(S.allFrames) do
            if f.parentFrame == api.rankTable.frame and f.data and not f.isHeader and f:IsShown() then
                byKey[(f.data.rankLabel or ("R" .. f.data.rank))] = f
            end
        end
        return byKey
    end
    local function Alpha(tex) return tex and tex.color and tex.color[4] end
    local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
    local accent = MD.UI.Hex("accent")
    local function Open(family)
        MD:SelectView("spells", family)
        local v = View()
        return v, v and v.api
    end

    -- 1. the header: name, shape / rank / cast, mana and +healing; the four
    -- prose lines are gone
    Try("T83: the header names the family, its shape, rank and cast, the mana and +healing; no prose lines", function()
        local v = Open("HealingTouch")
        local h = v.header
        local sub = Plain(h.sub)
        return Plain(h.name) == "Healing Touch"
            and sub:match("^Direct heal %- Rank %d+ of %d+ known %- %d%.%d s cast") ~= nil
            and Plain(h.mana):match("^%d+ / %d+ mana$") ~= nil
            and Plain(h.stats):match("^%+%d+ healing") ~= nil
            and h.icon:IsShown()
            and ShownText("healing   regen") == nil and ShownText("Hover the header") == nil
            and ShownText("costs %d%.%dx the mana") == nil and ShownText("No fights recorded") == nil,
            Plain(h.name) .. " | " .. sub .. " | " .. Plain(h.mana) .. " | " .. Plain(h.stats)
    end)

    -- 2. the chip and one comparison line, After overheal and its share
    Try("T83: the chip says SUGGESTED Rank 6 and one line compares it with your highest", function()
        local v = Open("Rejuvenation")
        local st = v.strip
        local cmp = Plain(st.compare)
        return Plain(st.chipLabel) == "SUGGESTED" and Plain(st.chipRank) == "Rank 6"
            and cmp:match("^vs Rank 12 %(your highest%): %d+%% more healing per mana, %d+%% of the heal, the same cast%.$") ~= nil
            and st.after.label:GetText() == "After overheal" and Plain(st.measured) == "not measured yet"
            and ButtonNamed("Effective") == nil,
            Plain(st.chipLabel) .. " " .. Plain(st.chipRank) .. " | " .. cmp .. " | " .. Plain(st.measured)
    end)

    -- 3. the suggested row: its fill and accent bar; it is selected by
    -- default (the white bar) and the card is its; a click moves the white
    -- bar and the card, never the fill
    Try("T83: the suggested row keeps its fill and bar; a click moves the white bar and the card", function()
        local v, api = Open("Rejuvenation")
        local rows = RowsOf(api)
        local r6, r12 = rows.R6, rows.R12
        local before = r6.fill:IsShown() and Near(Alpha(r6.fill), 0.10) and r6.mark:IsShown()
            and r6.pick ~= nil and r6.pick:IsShown() and not r12.pick:IsShown()
            and Plain(v.card.title) == "RANK 6" and Plain(v.card.note):match("^learned at %d+ %- you are 64$") ~= nil
        r12:GetScript("OnMouseUp")(r12, "LeftButton")
        rows = RowsOf(api)
        r6, r12 = rows.R6, rows.R12
        local labels = {}
        for _, p in ipairs(api.cardPairs or {}) do labels[#labels + 1] = p[1] end
        local after = r12.pick:IsShown() and not r6.pick:IsShown() and r6.mark:IsShown()
            and Near(Alpha(r6.fill), 0.10) and not r12.mark:IsShown()
            and Plain(v.card.title) == "RANK 12" and table.concat(labels, ",") == "Tick,Total,Downrank,Cost"
            and Plain(v.card.base):match("^Base heal %d+ over 12 s, before your %+healing") ~= nil
        return before and after, string.format("before=%s after=%s card=%s pairs=%s", tostring(before),
            tostring(after), Plain(v.card.title), table.concat(labels, ","))
    end)

    -- 4. Casts: 999+ past 999, inf when regen keeps up; any what-if value
    -- turns the chip SIMULATED and puts the changed stats in the accent
    Try("T83: Casts reads 999+ past 999 and inf when regen keeps up; a what-if value says SIMULATED", function()
        local v, api = Open("Rejuvenation")
        MD.sim.mana, MD.sim.casting = 200000, 0
        api:Render("Rejuvenation")
        local rows = RowsOf(api)
        local big, plain = Plain(rows.R1.cells.casts), Plain(rows.R12.cells.casts)
        local simOk = Plain(v.strip.chipLabel) == "SIMULATED" and v.header.mana:GetText():find(accent, 1, true) == 1
            and Plain(v.header.mana):match("^200000 mana") ~= nil
            and v.header.stats:GetText():find(accent .. "0 mp5 casting", 1, true) ~= nil
        MD.sim.casting = 100000
        api:Render("Rejuvenation")
        local inf = 0
        for _, row in pairs(RowsOf(api)) do if Plain(row.cells.casts) == "inf" then inf = inf + 1 end end
        wipe(MD.sim)
        api:Render("Rejuvenation")
        return big == "999+" and tonumber(plain) ~= nil and tonumber(plain) <= 999 and inf == 13 and simOk
            and Plain(v.strip.chipLabel) == "SUGGESTED",
            string.format("R1=%s R12=%s inf=%d simulated=%s", big, plain, inf, tostring(simOk))
    end)
    wipe(MD.sim)

    -- 5. What if... folds the Simulate strip: shut on first sight, open on a
    -- click (between the strip and RANKS), shut again on the second; a value
    -- typed in it stays
    Try("T83: What if... unfolds the Simulate strip above RANKS and folds it again", function()
        local v, api = Open("Rejuvenation")
        local shut = not api:WhatIfOpen() and not ShownButton("Clear") and ShownButton("What if...")
        -- the stub keeps no anchors: the unfolded strip shows in the view's height
        local y0 = api.contentHeight
        Click(ButtonNamed("What if..."))
        local open = api:WhatIfOpen() and ShownButton("Clear") and ShownText("^What if:$") ~= nil
        local y1 = api.contentHeight
        local eb
        for _, f in ipairs(S.allFrames) do
            if f.kind == "EditBox" and f:IsVisible() and not eb then eb = f end
        end
        eb:SetText("1500"); eb:GetScript("OnEditFocusLost")(eb)
        local typed = MD.sim.heal == 1500 and Plain(v.strip.chipLabel) == "SIMULATED"
            and v.header.stats:GetText():find(accent .. "+1500", 1, true) ~= nil
        Click(ButtonNamed("What if..."))
        local folded = not api:WhatIfOpen() and not ShownButton("Clear") and MD.sim.heal == 1500
            and api.contentHeight == y0
        api.whatIf:Clear()
        return shut and open and typed and folded and type(y0) == "number" and type(y1) == "number" and y1 > y0
            and Plain(v.strip.chipLabel) == "SUGGESTED",
            string.format("shut=%s open=%s typed=%s folded=%s height %s -> %s", tostring(shut), tostring(open),
                tostring(typed), tostring(folded), tostring(y0), tostring(y1))
    end)
    wipe(MD.sim)

    -- 6. After overheal (was Effective): the box writes db.effectiveMode and
    -- the healing headers take the accent; a HoT's value column is Total
    local was = MD.db.effectiveMode
    Try("T83: After overheal puts the accent on the healing headers; a HoT's value column is Total", function()
        local v, api = Open("Rejuvenation")
        local function HeaderRow()
            for _, f in ipairs(S.allFrames) do
                if f.parentFrame == api.rankTable.frame and f.isHeader and f:IsShown() then return f end
            end
        end
        v.strip.after:SetChecked(true); v.strip.after:GetScript("OnClick")(v.strip.after)
        local hdr = HeaderRow()
        local on = MD.db.effectiveMode == true and hdr.cells.heal:GetText():find(accent .. "Total", 1, true) ~= nil
            and hdr.cells.hpm:GetText():find(accent .. "Per mana", 1, true) ~= nil
        v.strip.after:SetChecked(false); v.strip.after:GetScript("OnClick")(v.strip.after)
        hdr = HeaderRow()
        local off = MD.db.effectiveMode == false and hdr.cells.heal:GetText():find(accent, 1, true) == nil
            and Plain(hdr.cells.heal) == "Total" and Plain(hdr.cells.casts) == "Casts"
        return on and off, string.format("on=%s off=%s", tostring(on), tostring(off))
    end)
    MD.db.effectiveMode = was
end

--------------------------------------------------------------------------------
-- T84 (C5 of docs/PLAN-refactor-ux.md, section 7.1; mockup M4 layout B): the
-- spell rail on TBC. The Spells group is a rail (no view row): MY SPELLS,
-- Overview first, then the harness druid's families as Spells/Tabs.lua
-- seeded them from Spells/Families_TBC.lua (known heals by learn level);
-- Overview lists one row per listed family with its suggested rank; a rail
-- row, or an Overview row, opens C3's view for that family; the row's x
-- removes it and Undo puts it back where it was. Each check under pcall.
--------------------------------------------------------------------------------
do
    local function Try(name, fn)
        local okRun, cond, detail = pcall(fn)
        if okRun then check(name, cond, detail) else check(name, false, tostring(cond)) end
    end
    local function Plain(fs) return ((fs and fs:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function Overview()
        for _, f in ipairs(S.allFrames) do
            if f.spellsOverviewTBC and f:IsVisible() then return f end
        end
        return nil
    end
    local function View()
        for _, f in ipairs(S.allFrames) do
            if f.spellsViewTBC and f:IsVisible() then return f end
        end
        return nil
    end
    local SEEDED = "overview,fam:HealingTouch,fam:Rejuvenation,fam:Regrowth,fam:Lifebloom"

    -- 1. a rail: MY SPELLS, Overview first (fixed), the seeded families, each
    -- with its suggested rank's tag; no view row
    Try("T84: the Spells group is a rail with Overview first, then the seeded families", function()
        MD:SelectView("spells", "overview")
        local rail = SpellsRail()
        local views = 0
        for _, b in ipairs(MD.SpellsTBC.nav.viewButtons or {}) do if b:IsShown() then views = views + 1 end end
        local results = MD.RankMath:Compute()
        local tags = true
        for _, key in ipairs({ "HealingTouch", "Rejuvenation", "Regrowth", "Lifebloom" }) do
            local s
            for _, r in ipairs(results[key].rows) do if r.suggested then s = r end end
            local row = RailRow("fam:" .. key)
            if not (row and s and row.data.tag == "R" .. s.rank and row:IsVisible()) then tags = false end
        end
        local ov = RailRow("overview")
        return rail ~= nil and RailIds() == SEEDED and views == 0 and tags
            and ov and ov.data.fixed == true and rail.title:GetText() == "MY SPELLS"
            and RailRow("fam:Rejuvenation").data.text == "Rejuvenation"
            and MD.cdb.spellTabs and MD.cdb.spellTabs.seeded == true,
            RailIds() .. " views=" .. views .. " tags=" .. tostring(tags)
    end)

    -- 2. Overview: one row per listed family, in the list's order, with its
    -- suggested rank (the rank RankMath suggests) and the highest known
    Try("T84: Overview lists one row per listed family, with its suggested rank", function()
        MD:SelectView("spells", "overview")
        local ov = Overview()
        local api = ov and ov.api
        local results = MD.RankMath:Compute()
        local keys, cells, good = {}, {}, true
        for _, r in ipairs(api.lastRows or {}) do
            keys[#keys + 1] = r.key
            local s
            for _, x in ipairs(results[r.key].rows) do if x.suggested then s = x end end
            if not (r.suggestedRow and s and r.suggestedRow.rank == s.rank and r.highestRow) then good = false end
        end
        for _, f in ipairs(S.allFrames) do
            if f.parentFrame == api.table.frame and f.data and not f.isHeader and f:IsShown() then
                cells[f.data.key] = Plain(f.cells.suggested)
            end
        end
        return table.concat(keys, ",") == "HealingTouch,Rejuvenation,Regrowth,Lifebloom" and good
            and cells.Rejuvenation == "R6" and Plain(ov.title) == "OVERVIEW" and View() == nil,
            table.concat(keys, ",") .. " Rejuvenation=" .. tostring(cells.Rejuvenation)
    end)

    -- 3. a rail row opens C3's view for that family (and an Overview row too;
    -- a path saved before C5 names a bare family and opens its row)
    Try("T84: a rail row opens C3's view for that family", function()
        RailClick("fam:Regrowth")
        local v = View()
        local viaRail = v ~= nil and Plain(v.header.name) == "Regrowth" and Overview() == nil
            and MD.db.uiPath[2] == "fam:Regrowth" and ShownText("^RANKS$") ~= nil
        MD:SelectView("spells", "overview")
        local api = Overview().api
        local lb
        for _, f in ipairs(S.allFrames) do
            if f.parentFrame == api.table.frame and f.data and f.data.key == "Lifebloom" and f:IsShown() then lb = f end
        end
        lb:GetScript("OnMouseUp")(lb, "LeftButton")
        v = View()
        local viaOverview = v ~= nil and Plain(v.header.name) == "Lifebloom" and MD.db.uiPath[2] == "fam:Lifebloom"
        MD:SelectView("spells", "Rejuvenation")
        local bare = MD.db.uiPath[2] == "fam:Rejuvenation" and View() ~= nil
        return viaRail and viaOverview and bare,
            string.format("rail=%s overview=%s bare=%s", tostring(viaRail), tostring(viaOverview), tostring(bare))
    end)

    -- 4. the hover x removes a row (Overview follows); the footer says so with Undo, which puts
    -- it back at its old place
    Try("T84: x removes a rail row and Undo puts it back where it was", function()
        MD:SelectView("spells", "overview")
        local sp = MD.SpellsTBC
        local row = RailRow("fam:Rejuvenation")
        row.rm:GetScript("OnClick")(row.rm)
        local gone = RailRow("fam:Rejuvenation") == nil and not MD.Tabs:Has("Rejuvenation")
            and MD.cdb.spellTabs.removed.Rejuvenation == true
            and Plain(sp.undoText) == "Rejuvenation removed" and sp.undoText:IsShown() and sp.undoBtn:IsShown()
            and #Overview().api.lastRows == 3 -- Overview follows the list
        local mid = RailIds()
        Click(sp.undoBtn)
        local back = RailIds() == SEEDED and MD.Tabs:Has("Rejuvenation") and not sp.undoBtn:IsShown()
            and MD.cdb.spellTabs.removed.Rejuvenation == nil
        MD:SelectView("spells", "overview")
        return gone and back and #Overview().api.lastRows == 4,
            string.format("gone=%s (%s) back=%s (%s)", tostring(gone), mid, tostring(back), RailIds())
    end)
end

-- no bare pipe anywhere it paints
local bad
for _, f in ipairs(S.allFrames) do
    local t = f.GetText and f:GetText() or ""
    if type(t) == "string" then
        local stripped = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if stripped:find("|", 1, true) then bad = bad or t end
    end
end
check("no bare pipe in any painted string", bad == nil, bad)

--------------------------------------------------------------------------------
-- T30 (docs/SPEC-forever-ui.md sec 9, 3.5, 4.3): the table's options; these
-- build one table with the options set (T81: and then the TBC rank table,
-- which is such a set now, and the refusal of a table without one). The stub's SetPoint,
-- SetJustifyH, CreateFontString and CreateTexture are no-ops that record
-- nothing, so this section records them itself -- here, after every check
-- above has run, so none of those sees a difference.
--------------------------------------------------------------------------------
local MT = getmetatable(CreateFrame("Frame"))
local saved = { SetPoint = rawget(MT, "SetPoint"), SetJustifyH = rawget(MT, "SetJustifyH"),
                CreateFontString = rawget(MT, "CreateFontString"), CreateTexture = rawget(MT, "CreateTexture") }
rawset(MT, "SetPoint", function(self, p, rel, rp, x, y) self.pt = { p, rel, rp, x, y } end)
rawset(MT, "SetJustifyH", function(self, j) self.justify = j end)
rawset(MT, "CreateFontString", function(self, name, layer, tmpl)
    local c = saved.CreateFontString(self); c.template = tmpl; return c
end)
rawset(MT, "CreateTexture", function(self, name, layer, tmpl, sub)
    local c = saved.CreateTexture(self); c.layer, c.sublevel = layer, sub; return c
end)

local UI = MD.UI
local T30_COLS = {
    { key = "rank",  x = 8,   w = 52,  label = "Rank" },
    { key = "pm",    x = 60,  w = 116, label = "Per mana", justify = "RIGHT", type = "bar", barWidth = 72, gap = 4 },
    { key = "casts", x = 176, w = 58,  label = "To OOM", justify = "RIGHT" },
    { key = "tag",   x = 234, w = 60,  label = "", font = UI.FONT_SMALL },
}
local t30rows, t30updates = {}, 0
local t30 = MD.DashboardParts.CreateTable(CreateFrame("Frame"), 556, {
    cols = T30_COLS, font = UI.FONT, rowHeight = 20, headerHeight = 22, rowWidth = 540,
    zebra = true, marker = "bar",
    render = function(row, r, color)
        t30rows[r.id] = row
        row.cells.rank:SetText(color .. "R" .. r.rank .. "|r")
        row.cells.pm:SetText(color .. (r.frac and string.format("%.2f", r.frac * 1.9) or "") .. "|r")
        row:SetBar("pm", r.frac)
        row.cells.casts:SetText(color .. r.casts .. "|r")
        row.cells.tag:SetText(r.suggested and "best" or "")
    end,
    onUpdateCells = function(row, r)
        t30updates = t30updates + 1
        row.cells.casts:SetText("~" .. (r.casts - 1))
    end,
})
t30:Render({
    { id = 1, rank = 1, frac = 1,    casts = 14, suggested = true },
    { id = 2, rank = 2, frac = 0.5,  casts = 6,  dominated = true },
    { id = 3, rank = 3,              casts = 0,  known = false },
    { id = 4, rank = 4, frac = 0.25, casts = 3 },
})
local R1, R2, R3, R4 = t30rows[1], t30rows[2], t30rows[3], t30rows[4]
local t30header
for _, f in ipairs(S.allFrames) do
    if f.isHeader and f.parentFrame == t30.frame then t30header = f end
end
local function Alpha(tex) return tex and tex.color and tex.color[4] end
local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

check("T30 font and justify: the table's font, a column's own", R1 and R1.cells.rank.template == UI.FONT
    and R1.cells.rank.justify == "LEFT" and R1.cells.pm.template == UI.FONT
    and R1.cells.pm.justify == "RIGHT" and R1.cells.casts.justify == "RIGHT"
    and R1.cells.tag.template == UI.FONT_SMALL,
    R1 and (tostring(R1.cells.rank.template) .. "/" .. tostring(R1.cells.pm.justify)) or "no row")

check("T30 rowHeight and rowWidth: 540 x 20 rows under a 22 header", R1 and R2 and t30header
    and R1.w == 540 and R1.h == 20 and t30header.pt[5] == -4
    and R1.pt[5] == -26 and R2.pt[5] == -46 and t30.rowHeight == 20,
    R1 and string.format("%s x %s at %s, %s", tostring(R1.w), tostring(R1.h),
        tostring(R1.pt and R1.pt[5]), tostring(R2 and R2.pt and R2.pt[5])) or "no row")

check("T30 zebra: even rows take rowAlt, odd rows nothing", R2 and R3 and R4 and R2.fill
    and R2.fill:IsShown() and Near(Alpha(R2.fill), 0.03)
    and not R3.fill:IsShown() and R4.fill:IsShown() and Near(Alpha(R4.fill), 0.03),
    R2 and R2.fill and tostring(Alpha(R2.fill)) or "no fill texture")

local b1, b2, b3, b4 = R1 and R1.bars and R1.bars.pm, R2 and R2.bars and R2.bars.pm,
    R3 and R3.bars and R3.bars.pm, R4 and R4.bars and R4.bars.pm
check("T30 bar cell: fraction x 72, the number after it, dominated 0.25", b1 and b2 and b3 and b4
    and b1.fill:IsShown() and b1.fill.w == 72 and Near(Alpha(b1.fill), 0.5)
    and b4.fill.w == 18 and Near(Alpha(b2.fill), 0.25) and b1.track:IsShown()
    and Near(Alpha(b1.track), 0.05) and b1.track.w == 72 and b1.track.h == 8
    and not b3.track:IsShown() and not b3.fill:IsShown()
    and R1.cells.pm.pt[4] == 60 + 72 + 4 and R1.cells.pm.w == 116 - 72 - 4
    and not t30header.bars.pm.track:IsShown(),
    b1 and string.format("w=%s a=%s num@%s", tostring(b1.fill.w), tostring(Alpha(b1.fill)),
        tostring(R1.cells.pm.pt and R1.cells.pm.pt[4])) or "no bar")

-- the one the row names: a table built with marker = "bar" carries no gold
-- (T81: no table carries any now -- the old no-options table is gone)
local gold
for _, f in ipairs(S.allFrames) do
    local p, guard = f.parentFrame, 0
    while p and p ~= t30.frame and guard < 10 do p, guard = p.parentFrame, guard + 1 end
    local t = p == t30.frame and f.GetText and f:GetText() or ""
    if type(t) == "string" and t:lower():find("ffcc00", 1, true) then gold = gold or t end
end
if t30.SetSelected then t30:SetSelected(2) end
check("T30 marker = bar: fill and a 2-px bar, no ffcc00 in the rows", gold == nil and R1 and R1.mark
    and R1.mark:IsShown() and R1.mark.w == 2 and R1.fill:IsShown() and Near(Alpha(R1.fill), 0.10)
    and not R2.mark:IsShown() and Near(Alpha(R2.fill), 0.28) and not t30header.mark:IsShown(),
    gold or (R1 and R1.fill and tostring(Alpha(R1.fill))) or "no marker")

local nFrames, before = #S.allFrames, R1 and R1.data
local n = t30.UpdateCells and t30:UpdateCells()
check("T30 onUpdateCells: data rows refreshed in place", n == 4 and t30updates == 4
    and #S.allFrames == nFrames and R1.data == before and R1:IsShown()
    and R1.cells.casts:GetText() == "~13" and R4.cells.casts:GetText() == "~2"
    and R1.cells.rank:GetText():find("R1", 1, true) ~= nil,
    string.format("n=%s calls=%d frames %d -> %d", tostring(n), t30updates, nFrames, #S.allFrames))

-- review of T30: a bar column's HEADER label spans the whole column (a data
-- row's number sits after the bar), and the header frame is headerHeight tall
-- so its label centres in the 22 band and the rule lies on its bottom edge.
-- Rendered twice: the pool hands the second header the first render's last
-- data row, and the first header comes back as a data row.
local function BarHeader()
    local h
    for _, f in ipairs(S.allFrames) do
        if f.isHeader and f.parentFrame == t30.frame and f:IsShown() then h = f end
    end
    return h
end
local h1 = BarHeader()
local hpm1 = h1 and h1.cells.pm
-- read now: the pool may hand this very frame back as a data row below
local first = h1 and hpm1.pt and { x = hpm1.pt[4], w = hpm1.w, j = hpm1.justify, h = h1.h } or {}
local firstHeader = h1
t30rows = {}
t30:Render({
    { id = 1, rank = 1, frac = 1,    casts = 14, suggested = true },
    { id = 2, rank = 2, frac = 0.5,  casts = 6,  dominated = true },
    { id = 3, rank = 3,              casts = 0,  known = false },
    { id = 4, rank = 4, frac = 0.25, casts = 3 },
})
local h2 = BarHeader()
local reused -- the first render's header, now a data row
for _, row in pairs(t30rows) do if row == firstHeader then reused = row end end
local function Cell(fs) return fs and fs.pt and string.format("@%s w=%s", tostring(fs.pt[4]), tostring(fs.w)) or "?" end
check("T30 bar header: the label over the whole column, the header 22 tall", hpm1 and h2
    and first.x == 60 and first.w == 116 and first.j == "RIGHT"
    and first.h == 22 and h2.h == 22 and h2.cells.pm.pt[4] == 60 and h2.cells.pm.w == 116
    and h2 ~= firstHeader and reused and reused.h == 20
    and reused.cells.pm.pt[4] == 60 + 72 + 4 and reused.cells.pm.w == 40,
    string.format("header pm @%s w=%s h=%s; again %s h=%s; old header as a row %s h=%s",
        tostring(first.x), tostring(first.w), tostring(first.h), Cell(h2 and h2.cells.pm), tostring(h2 and h2.h),
        Cell(reused and reused.cells.pm), tostring(reused and reused.h)))

--------------------------------------------------------------------------------
-- T81 (C2 of docs/PLAN-refactor-ux.md, review U5 / A23; mockup M6's RANKS):
-- the TBC rank table is an opts set on the one table -- built here as the
-- dashboard builds it (MD.DashboardParts.CreateRankTable) and rendered with
-- RankMath's own Rejuvenation rows (the harness druid: R6 suggested, R12 the
-- highest known, R13 not learned, R1 beaten) -- and a table without
-- opts.render is refused.
--------------------------------------------------------------------------------
-- Before T81 the dashboard's rank table was CreateTable with no options; the
-- fallback lets this suite run on such a commit and fail check by check.
local function RankTable(parent, width)
    local make = MD.DashboardParts.CreateRankTable
    if make then return make(parent, width) end
    return MD.DashboardParts.CreateTable(parent, width)
end
do
    local results = MD.RankMath:Compute()
    local rows = results.Rejuvenation and results.Rejuvenation.rows or {}
    local rank = RankTable(CreateFrame("Frame"), 912)
    rank:Render(rows)
    local byRank, header = {}, nil
    for _, f in ipairs(S.allFrames) do
        if f.parentFrame == rank.frame and f.cells and f:IsShown() then
            if f.isHeader then header = f elseif f.data then byRank[f.data.rank] = f end
        end
    end
    local function Plain(fs) return ((fs and fs:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function RowWithTag(word)
        for _, f in pairs(byRank) do if Plain(f.cells.tag) == word then return f end end
        return nil
    end
    local r1, r4, r6 = byRank[1], byRank[4], byRank[6]

    -- 1. the look: right-justified numbers in Arial Narrow, 20-px rows under
    -- a 22 header with its rule, zebra
    local rule
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Texture" and f.parentFrame == rank.frame and f.layer == "BORDER" and f:IsShown() then rule = f end
    end
    local right = true
    for _, key in ipairs({ "level", "cost", "heal", "hpm", "hps", "cast", "casts" }) do
        if not (r6 and r6.cells[key].justify == "RIGHT" and r6.cells[key].template == UI.FONT_NUM) then right = false end
    end
    check("T81: the rank table's numbers are right-justified in Arial Narrow on 20-px rows",
        right and r6.cells.rank.justify == "LEFT" and r6.cells.tag.template == UI.FONT_SMALL
          and r6.h == 20 and header and header.h == 22 and rule ~= nil and rank.rowWidth == 600
          and r4 and r4.fill and r4.fill:IsShown() and Near(Alpha(r4.fill), 0.03)
          and byRank[3] and not byRank[3].fill:IsShown(),
        r6 and string.format("cost %s/%s h=%s header=%s rule=%s", tostring(r6.cells.cost.justify),
            tostring(r6.cells.cost.template), tostring(r6.h), tostring(header and header.h), tostring(rule ~= nil))
          or "no R6 row")

    -- 2. the suggested row: the fill and the 2-px accent bar, no gold, no
    -- star; its tag says best (in the accent) and the HPM cell has its bar
    local gold
    for _, f in ipairs(S.allFrames) do
        local p, guard = f.parentFrame, 0
        while p and p ~= rank.frame and guard < 10 do p, guard = p.parentFrame, guard + 1 end
        local t = p == rank.frame and f.GetText and f:GetText() or ""
        if type(t) == "string" and t:lower():find("ffcc00", 1, true) then gold = gold or t end
    end
    local bar = r6 and r6.bars and r6.bars.hpm
    check("T81: the suggested row is the fill and the bar, its tag best, no gold, no star", gold == nil and r6
        and r6.data.suggested and r6.mark:IsShown() and Near(Alpha(r6.fill), 0.10)
        and Plain(r6.cells.rank) == "R6" and Plain(r6.cells.tag) == "best"
        and r6.cells.tag:GetText():find(UI.Hex("accent"), 1, true) == 1
        and r4 and not r4.mark:IsShown() and bar and bar.fill:IsShown() and bar.width == 80,
        gold or (r6 and Plain(r6.cells.rank) .. " / " .. Plain(r6.cells.tag)) or "no R6 row")

    -- 3. the Tag column instead of the gold note: max, learn at N, beaten
    -- (its hover names the rank that beats it), rolling on Lifebloom's stacks
    local max, learn, beaten = RowWithTag("max"), byRank[13], byRank[1]
    local tip = beaten and rank.cols[9].cellTooltip(beaten.data, beaten)
    local by = tip and tip[1] and tip[1].l or ""
    -- read now: the Lifebloom render below hands these pooled rows on
    local tags = string.format("max=%s learn=%s beaten=%s", tostring(max and max.data.rank),
        learn and Plain(learn.cells.tag) or "-", beaten and Plain(beaten.cells.tag) or "-")
    local tagsOk = max ~= nil and max.data.rank == 12 and learn ~= nil
        and Plain(learn.cells.tag) == "learn at " .. learn.data.level
        and beaten ~= nil and Plain(beaten.cells.tag) == "beaten"
    local lb = results.Lifebloom and results.Lifebloom.rows or {}
    rank:Render(lb)
    local rolling = 0
    for _, f in ipairs(S.allFrames) do
        if f.parentFrame == rank.frame and f.cells and f.data and f:IsShown() and Plain(f.cells.tag) == "rolling" then
            rolling = rolling + 1
        end
    end
    check("T81: a Tag column (max, learn at N, beaten by Rank N, rolling), no note", tagsOk
        and by:match("^Beaten by Rank %d+$") ~= nil
        and rank.cols[9].key == "tag" and rank.cols[9].label == "" and rolling == 2,
        string.format("%s tip=%q rolling=%d", tags, by, rolling))

    -- 4. every header label shows the glossary; a row's hover is its
    -- derivation (Tip:Row), beside the row
    rank:Render(rows)
    for _, f in ipairs(S.allFrames) do
        if f.parentFrame == rank.frame and f.isHeader and f:IsShown() then header = f end
    end
    local hits = 0
    for _ in pairs(header and header.colHits or {}) do hits = hits + 1 end
    GameTooltip.lines = nil
    local hpmHit = header and header.colHits and header.colHits.hpm
    if hpmHit then hpmHit:GetScript("OnEnter")(hpmHit) end
    -- T83 (C3): each header its own sentence (was Tip:Columns' glossary)
    local glossary = GameTooltip.lines and GameTooltip.lines[1] and GameTooltip.lines[1][1]
    local sentence = GameTooltip.lines and GameTooltip.lines[2] and GameTooltip.lines[2][1]
    GameTooltip:Hide()
    local r6b
    for _, f in ipairs(S.allFrames) do
        if f.parentFrame == rank.frame and f.data and f.data.rank == 6 and not f.data.virtual and f:IsShown() then r6b = f end
    end
    GameTooltip.lines = nil
    if r6b then r6b:GetScript("OnEnter")(r6b) end
    local derivation = GameTooltip.lines and GameTooltip.lines[1] and GameTooltip.lines[1][1]
    if r6b then r6b:GetScript("OnLeave")(r6b) end
    check("T81: every header label explains the columns; a row's hover is its derivation",
        hits == 8 and glossary == "Per mana" and sentence == "Healing for each point of mana."
          and type(derivation) == "string"
          and derivation:find("Rank 6", 1, true) ~= nil and not GameTooltip:IsShown(),
        string.format("hits=%d glossary=%s row=%s", hits, tostring(glossary), tostring(derivation)))

    -- 5. Effective mode: the three healing headers in the accent, an
    -- unmeasured heal marked "?" (the harness has no overheal measured)
    local was = MD.db.effectiveMode
    MD.db.effectiveMode = true
    rank:Render(MD.RankMath:Compute().Rejuvenation.rows)
    for _, f in ipairs(S.allFrames) do
        if f.parentFrame == rank.frame and f.isHeader and f:IsShown() then header = f end
    end
    local r6e
    for _, f in ipairs(S.allFrames) do
        if f.parentFrame == rank.frame and f.data and f.data.rank == 6 and f:IsShown() then r6e = f end
    end
    local accent = UI.Hex("accent")
    local effOk = header and header.cells.heal:GetText():find(accent, 1, true) ~= nil
        and header.cells.hpm:GetText():find(accent, 1, true) ~= nil
        and header.cells.hps:GetText():find(accent, 1, true) ~= nil
        and header.cells.cost:GetText():find(accent, 1, true) == nil
        and r6e and Plain(r6e.cells.heal):sub(-1) == "?"
    local effDetail = (header and header.cells.heal:GetText() or "no header") .. " / " .. (r6e and Plain(r6e.cells.heal) or "no R6")
    MD.db.effectiveMode = was
    rank:Render(rows)
    local plainAgain
    for _, f in ipairs(S.allFrames) do
        if f.parentFrame == rank.frame and f.isHeader and f:IsShown() then plainAgain = f end
    end
    check("T81: After overheal puts the accent on Heal, Per mana, Per sec and a ? on an unmeasured heal",
        effOk and plainAgain and plainAgain.cells.heal:GetText():find(accent, 1, true) == nil, effDetail)

    -- 6. one table: CreateTable without opts.render raises
    local okNil = pcall(MD.DashboardParts.CreateTable, CreateFrame("Frame"), 700)
    local okNoRender = pcall(MD.DashboardParts.CreateTable, CreateFrame("Frame"), 700, { cols = {} })
    check("T81: CreateTable refuses a table without opts.render (the second table is gone)",
        okNil == false and okNoRender == false)
end

for k, fn in pairs(saved) do rawset(MT, k, fn) end

--------------------------------------------------------------------------------
-- T53 (P9, review U25): a Waste list longer than the pane ended with a tail
-- line saying how many rows it did not show. T81 (C2): Waste is an opts set on
-- the one table and scrolls, as Review does -- a 300-high pane shows 11 of
-- 40 rows, the wheel reaches Spell 40, no tail line is painted; the numbers
-- are right-justified in Arial Narrow on 20-px rows, the words are not.
--------------------------------------------------------------------------------
do
    local OH = MD.Overheal
    local realRows = OH.SpellRows
    local fake = {}
    for i = 1, 40 do
        fake[i] = { key = "x:" .. i, label = "Spell " .. i, healed = 100, overhealed = 10, frac = 0.1,
                    wastedMana = 0, wastedEvents = 0 }
    end
    OH.SpellRows = function() return fake end
    local wparent = CreateFrame("Frame")
    wparent:SetSize(760, 300)
    local justify = rawget(MT, "SetJustifyH") -- recorded while the rows are built, as T30's are
    rawset(MT, "SetJustifyH", function(self, j) self.justify = j end)
    local waste = MD.DashboardParts.CreateWaste(wparent, 760)
    waste.frame:SetSize(760, 300)
    waste.frame:Show()
    waste:Render()
    rawset(MT, "SetJustifyH", justify)
    local function Shown()
        local labels, tail, first, last, list = 0, nil, nil, nil, nil
        for _, f in ipairs(S.allFrames) do
            if f.cells and f.cells.wev and f:IsShown() and f.parentFrame and f.parentFrame:GetParent() == waste.frame then
                local t = (f.cells.label:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                local n = tonumber(t:match("^Spell (%d+)$"))
                if n then
                    labels = labels + 1
                    first, last = math.min(first or n, n), math.max(last or 0, n)
                    list = f
                end
                local w = (f.cells.wide and f.cells.wide:GetText() or "") .. t
                tail = tail or w:match("more %(scroll: not yet%)")
            end
        end
        return labels, first, last, tail, list
    end
    local n0, first0, last0, tail0, row = Shown()
    local listFrame = row and row.parentFrame
    -- read now: the wheel's renders hand this pooled row on (a header, maybe)
    local looks = row and { healed = row.cells.healed.justify, label = row.cells.label.justify, h = row.h } or {}
    local wheel = listFrame and listFrame:GetScript("OnMouseWheel")
    local notches = 0
    while wheel and notches < 40 do
        local _, _, before = Shown()
        wheel(listFrame, -1)
        notches = notches + 1
        local _, _, after = Shown()
        if after == before then break end
    end
    local n1, _, last1, tail1 = Shown()
    check("a long Waste list scrolls to its last row, no tail line (T81)", n0 == 11 and first0 == 1 and last0 == 11
        and n1 == 11 and last1 == 40 and tail0 == nil and tail1 == nil
        and looks.healed == "RIGHT" and looks.label ~= "RIGHT" and looks.h == 20,
        string.format("rows=%d %s..%s, after the wheel %d ..%s, tail=%s/%s, healed %s, h=%s", n0, tostring(first0),
            tostring(last0), n1, tostring(last1), tostring(tail0), tostring(tail1),
            tostring(looks.healed), tostring(looks.h)))
    OH.SpellRows = realRows
end

--------------------------------------------------------------------------------
-- T76 (P32 of docs/PLAN-refactor-ux.md; review U10 -- the mechanism, U13): a
-- generic table's header label shows its column's own tooltip (col.tooltip);
-- a column without one has none, and the TBC rank table's columns carry none.
-- And the motion-while-disabled flag is the theme's: T80 (C1) lists the
-- theme on TBC, so a disabled TBC button explains itself on hover too.
--------------------------------------------------------------------------------
do
    local parent = CreateFrame("Frame")
    local api = MD.DashboardParts.CreateTable(parent, 400, {
        cols = { { key = "casts", x = 8, w = 60, label = "Casts", tooltip = "Chain casts from a full pool." },
                 { key = "plain", x = 80, w = 60, label = "Plain" } },
        render = function() end,
    })
    api:Render({})
    local header
    for _, f in ipairs(S.allFrames) do
        if f.isHeader and f.parentFrame == api.frame and f:IsShown() then header = f end
    end
    local hits = header and header.colHits or {}
    local hit = hits.casts
    GameTooltip.lines = nil
    local enter = hit and hit:GetScript("OnEnter")
    if enter then enter(hit) end
    local l = GameTooltip.lines or {}
    local shown = #l == 2 and l[1][1] == "Casts" and l[2][1] == "Chain casts from a full pool."
    local leave = hit and hit:GetScript("OnLeave")
    if leave then leave(hit) end
    -- T81: the TBC rank table is an opts set now, and every labelled column
    -- carries a tooltip (T83: its own sentence, was Tip:Columns' glossary)
    local rankCols = 0
    local rankApi = RankTable(CreateFrame("Frame"), 760)
    for _, col in ipairs(rankApi.cols or {}) do if col.tooltip then rankCols = rankCols + 1 end end
    check("T76: a header label shows its column's tooltip", header ~= nil and hit ~= nil and shown
        and hits.plain == nil and not GameTooltip:IsShown() and rankCols == 8
        and not (MD.Tip.Skinned and MD.Tip:Skinned(GameTooltip)),
        string.format("header=%s hit=%s lines=%d plain=%s", tostring(header ~= nil), tostring(hit ~= nil), #l,
            tostring(hits.plain ~= nil)))

    local FrameMT = getmetatable(UIParent)
    local saved = rawget(FrameMT, "SetMotionScriptsWhileDisabled")
    FrameMT.SetMotionScriptsWhileDisabled = function(self, v) self.motionWhileDisabled = v end
    local b = MD.UI.CreateButton(UIParent, "Coach", "accent", { 64, 20 }, nil, nil, nil, nil, "Coach")
    FrameMT.SetMotionScriptsWhileDisabled = saved
    check("T76/T80: a disabled TBC button keeps its motion scripts (the theme's)", b.motionWhileDisabled == true,
        tostring(b.motionWhileDisabled))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
if #fails > 0 then for _, m in ipairs(fails) do print("  FAIL " .. m) end; os.exit(1) end
