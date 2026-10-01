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
S.Load({ "UI/Style.lua", "UI/Tooltip.lua", "UI/Dashboard_Rows.lua", "UI/Dashboard_Simulate.lua",
         "UI/Dashboard_Waste.lua", "UI/Dashboard_Review.lua", "UI/PracticePanel.lua", "UI/Dashboard.lua" }, "SpellTuner", MD)

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

check("the four groups are the author's, minus the two still to move",
    ButtonNamed("Spells") ~= nil and ButtonNamed("Reports") ~= nil)

MD:ToggleDashboard()
check("it opens", frame:IsShown())

-- opening lands on a spell, and the rank table is built
check("it opens on a spell", MD.db.uiPath and MD.db.uiPath[1] == "spells",
    MD.db.uiPath and table.concat(MD.db.uiPath, "/") or "no path")
check("the rank table is built for it", Painted("HPM heal per mana") ~= nil)
check("the Simulate strip is with the spells", ButtonNamed("Clear") ~= nil)

-- switching families keeps the group
local rg = ButtonNamed("Regrowth")
check("a family button exists", rg ~= nil)
Click(rg)
check("clicking a family selects it", MD.db.uiPath[2] == "Regrowth", MD.db.uiPath[2])

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
Click(ButtonNamed("Spells"))
check("going back to Spells restores the rank table", Painted("HPM heal per mana") ~= nil)
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
S.Load({ "UI/OptionsFrame.lua", "UI/Options_General.lua", "UI/Options_About.lua" }, "SpellTuner", MD)
check("the settings panel exists", MD.optionsFrame ~= nil)
check("it is a panel, not a window", _G.SpellTunerOptionsFrame == nil,
    tostring(_G.SpellTunerOptionsFrame))

Click(ButtonNamed("Settings"))
check("Settings is a group of the one window", MD.db.uiPath[1] == "settings",
    table.concat(MD.db.uiPath, "/"))
check("it opens on General", MD.db.uiPath[2] == "general", MD.db.uiPath[2])
check("the general pane is in there", ButtonNamed("Record fights") ~= nil
    or Painted("Record fights") ~= nil)
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
check("About is its second view", MD.db.uiPath[2] == "about", MD.db.uiPath[2])

-- /md options routes into the group instead of opening anything
Click(ButtonNamed("Spells"))
MD:ShowOptionsFrame("general")
check("/md options selects the settings group", MD.db.uiPath[1] == "settings"
    and MD.db.uiPath[2] == "general", table.concat(MD.db.uiPath, "/"))
check("and it did not open a second window", _G.SpellTunerOptionsFrame == nil)

-- the spell-only furniture is not drawn over the settings
Click(ButtonNamed("Settings"))
check("the rank table's header lines are hidden in Settings", (function()
    for _, f in ipairs(S.allFrames) do
        local t = f.GetText and f:GetText() or ""
        if type(t) == "string" and t:find("HPM heal per mana") and f.shown ~= false then return false end
    end
    return true
end)())

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
check("no rank-table hint over the simulator", ShownText("HPM heal per mana") == nil,
    ShownText("HPM heal per mana"))
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
    and ShownText("HPM heal per mana") == nil,
    ShownText("The fights this character recorded") or ShownText("HPM heal per mana"))

Click(ButtonNamed("Settings"))
check("nor over the settings", ShownText("HPM heal per mana") == nil and not ShownButton("Clear"))

-- and the Spells furniture comes back when Spells does
Click(ButtonNamed("Spells"))
check("the rank table comes back with Spells", ShownText("HPM heal per mana") ~= nil)
check("and so does the what-if strip", ShownButton("Clear"))

-- the rank table is one frame registered under every family: switching family
-- must not leave it hidden (the nav hides everything, then shows the keeper)
Click(ButtonNamed("Regrowth"))
check("switching family keeps the table visible", ShownText("HPM heal per mana") ~= nil)

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
-- T30 (docs/SPEC-forever-ui.md sec 9, 3.5, 4.3): the table's options. Every
-- check above is the all-nil table (today's, gold included) and stays as it
-- was; these six build one table with the options set. The stub's SetPoint,
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
local legacy = MD.DashboardParts.CreateTable(CreateFrame("Frame"), 700)
legacy:Render({})
local legacyHeader
for _, f in ipairs(S.allFrames) do
    if f.isHeader and f.parentFrame == legacy.frame then legacyHeader = f end
end

local function Alpha(tex) return tex and tex.color and tex.color[4] end
local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

check("T30 font and justify: the table's font, a column's own", R1 and R1.cells.rank.template == UI.FONT
    and R1.cells.rank.justify == "LEFT" and R1.cells.pm.template == UI.FONT
    and R1.cells.pm.justify == "RIGHT" and R1.cells.casts.justify == "RIGHT"
    and R1.cells.tag.template == UI.FONT_SMALL
    and legacyHeader and legacyHeader.cells.rank.template == "GameFontHighlightSmall"
    and legacyHeader.cells.rank.justify == "LEFT",
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

for k, fn in pairs(saved) do rawset(MT, k, fn) end

--------------------------------------------------------------------------------
-- T53 (P9, review U25): a Waste list longer than the pane ends with a tail
-- line saying how many rows it does not show. A 300-high pane has 14 slots
-- below the header: 13 rows and "... and 27 more" for a list of 40.
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
    local waste = MD.DashboardParts.CreateWaste(wparent, 760)
    waste.frame:SetSize(760, 300)
    waste.frame:Show()
    waste:Render()
    local labels, tail, last = 0, nil, nil
    for _, f in ipairs(S.allFrames) do
        if f.cells and f.cells.wev and f.shown and f:GetParent() == waste.frame then
            local t = (f.cells.label:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if t:match("^Spell %d+$") then
                labels = labels + 1
                last = math.max(last or 0, tonumber(t:match("%d+")))
            end
            tail = tail or tonumber(t:match("^%.%.%. and (%d+) more %(scroll: not yet%)$"))
        end
    end
    check("a long Waste list ends with the tail line", labels == 13 and last == 13 and tail == 27,
        string.format("rows=%d last=%s tail=%s", labels, tostring(last), tostring(tail)))
    OH.SpellRows = realRows
end

print(string.format("\n%d ok, %d failed", ok, #fails))
if #fails > 0 then for _, m in ipairs(fails) do print("  FAIL " .. m) end; os.exit(1) end
