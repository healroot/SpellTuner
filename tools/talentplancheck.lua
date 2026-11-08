-- tools/run.sh --flavour forever tools/talentplancheck.lua
--
-- T137 (docs/tasks/T137-forever-talent-planner.md): the talent planner.
--
--   1. Data/TalentTree_Forever.lua as generated: every class three trees, each
--      talent in the grid, a requirement in its own tree, Bloom where the game has it
--   2. the rules: points by level, tiers, requirements, points left; a point never
--      comes off under a later tier or a dependant
--   3. the bridge: the plan starts from the live build; Apply types the modelled
--      talents in one change, clears one equal to live, keeps the rest; a cleared
--      What if starts from live again
--   4. the sheet: refused unread and in combat; every talent a cell with its icon;
--      left adds, right removes, the panel follows; Use puts it in the What if;
--      the drawer's Talent plan... opens it
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end
local function T(name, fn)
    local good, cond, detail = pcall(fn)
    if not good then check(name, false, "raised: " .. tostring(cond)) return end
    check(name, cond == true, detail)
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB
local TP, WI, Book = ST.TalentPlan, ST.WhatIf, ST.Book
local UI = ST.UI

S.level, ST.player.level = 26, 26

local TRAIT_NAMES = { "C_ClassTalents.GetActiveConfigID", "C_Traits.GetConfigInfo", "C_Traits.GetTreeNodes",
    "C_Traits.GetNodeInfo", "C_Traits.GetEntryInfo", "C_Traits.GetDefinitionInfo" }
local function Use(talents)
    WI:Clear()
    if talents == false then
        C_Traits, C_ClassTalents = nil, nil
    else
        S.AddTraits(talents)
    end
    for _, n in ipairs(TRAIT_NAMES) do ST.API.Invalidate(n) end
    S.Fire("PLAYER_TALENT_UPDATE")
    Book:MarkDirty()
    return Book:Get()
end

local LIVE = { ["Nature's Focus"] = 5, ["Naturalist"] = 5, ["Gift of Nature"] = 2 }

--------------------------------------------------------------------------------
-- 1: the data
--------------------------------------------------------------------------------
T("1 every class three trees; every talent in the 7 x 4 grid; a requirement in its own tree", function()
    local bad, classes = nil, 0
    for class, trees in pairs(ST.TalentTree) do
        classes = classes + 1
        if #trees ~= 3 and not bad then bad = class .. " has " .. #trees .. " trees" end
        for _, tree in ipairs(trees) do
            local names, seen = {}, {}
            for _, t in ipairs(tree.talents) do names[t.name] = true end
            for _, t in ipairs(tree.talents) do
                local cell = t.row .. ":" .. t.col
                if (t.row < 1 or t.row > 7 or t.col < 1 or t.col > 4 or t.max < 1 or seen[cell]) and not bad then
                    bad = class .. " " .. t.name .. " at " .. cell
                end
                seen[cell] = true
                if t.req and not names[t.req] and not bad then bad = t.name .. " requires " .. t.req end
            end
        end
    end
    return bad == nil and classes == 9, bad or (classes .. " classes")
end)

T("1 the druid: Balance, Feral Combat, Restoration; Bloom tier 3 column 4 with its icon", function()
    local trees = TP.Trees("DRUID")
    local f = TP.Find(trees, "Bloom")
    return trees[1].name == "Balance" and trees[2].name == "Feral Combat" and trees[3].name == "Restoration"
        and f and f.tree == 3 and f.t.row == 3 and f.t.col == 4 and f.t.icon == "inv_misc_herb_felblossom"
        and type(f.t.desc) == "string" and f.t.desc:find("Spirit", 1, true) ~= nil
end)

--------------------------------------------------------------------------------
-- 2: the rules
--------------------------------------------------------------------------------
local trees = TP.Trees("DRUID")

T("2 points: level 10 one, 26 seventeen, 60 and 70 fifty-one; never under the live build's", function()
    return TP.Points(10) == 1 and TP.Points(26) == 17 and TP.Points(60) == 51 and TP.Points(70) == 51
        and TP.Points(9) == 0 and TP.Points(26, 20) == 20
end)

T("2 tiers: Bloom needs 10 points above it in Restoration; with them it opens", function()
    local okE, why = TP.CanAdd({}, trees, "Bloom", 17)
    local okF = TP.CanAdd({ ["Nature's Focus"] = 5, ["Naturalist"] = 5 }, trees, "Bloom", 17)
    local okB = TP.CanAdd({ ["Nature's Focus"] = 5, ["Naturalist"] = 4 }, trees, "Bloom", 17)
    return okE == false and why == "needs 10 points in Restoration" and okF == true and okB == false, why
end)

T("2 a requirement: Nature's Splendor needs Nature's Majesty at full rank", function()
    local base = { ["Genesis"] = 5, ["Improved Wrath"] = 5 }
    local no, why = TP.CanAdd(base, trees, "Nature's Splendor", 17)
    base["Nature's Majesty"] = 2
    local yes = TP.CanAdd(base, trees, "Nature's Splendor", 17)
    return no == false and why == "needs Nature's Majesty at full rank" and yes == true, why
end)

T("2 points left and full rank refuse", function()
    local plan = { ["Nature's Focus"] = 5, ["Heart of the Wild"] = 5, ["Naturalist"] = 5, ["Reflection"] = 2 }
    local none, why1 = TP.CanAdd(plan, trees, "Reflection", 17)
    local full, why2 = TP.CanAdd(plan, trees, "Naturalist", 30)
    return none == false and why1 == "no points left" and full == false and why2 == "at full rank"
end)

T("2 a point stays under a later tier and under a dependant; a free one comes off", function()
    local plan = { ["Nature's Focus"] = 5, ["Naturalist"] = 5, ["Bloom"] = 1 }
    local tier, why1 = TP.CanRemove(plan, trees, "Naturalist")
    local plan2 = { ["Genesis"] = 5, ["Improved Wrath"] = 5, ["Nature's Majesty"] = 2, ["Nature's Splendor"] = 1 }
    local dep, why2 = TP.CanRemove(plan2, trees, "Nature's Majesty")
    local free = TP.CanRemove(plan, trees, "Bloom")
    local none = TP.CanRemove(plan, trees, "Reflection")
    return tier == false and why1 == "Bloom would lose its tier" and dep == false
        and why2 == "Nature's Splendor needs it" and free == true and none == false, why1 .. " / " .. why2
end)

--------------------------------------------------------------------------------
-- 3: the bridge
--------------------------------------------------------------------------------
T("3 unread talents: no current plan", function()
    Use(false)
    return TP:Current() == nil and TP:Apply({}) == 0
end)

T("3 the plan starts from the live build", function()
    Use(LIVE)
    local plan = TP:Current()
    return plan and plan["Naturalist"] == 5 and plan["Nature's Focus"] == 5 and plan["Gift of Nature"] == 2
        and plan["Bloom"] == nil
end)

T("3 Apply: modelled talents typed in one change, unmodelled kept, equal to live cleared", function()
    Use(LIVE)
    WI:Set("talent:Naturalist", 3)
    local serial = WI.serial
    local plan = { ["Nature's Focus"] = 4, ["Naturalist"] = 5, ["Gift of Nature"] = 2, ["Bloom"] = 1 }
    local n = TP:Apply(plan)
    local typed = WI:Get("talent:Bloom") == 1 and WI:Get("talent:Naturalist") == nil
        and WI:Get("talent:Nature's Focus") == nil and WI:Get("talent:Gift of Nature") == nil
    local again = TP:Current()
    local kept = again["Nature's Focus"] == 4 and again["Bloom"] == 1 and again["Naturalist"] == 5
    WI:Clear()
    local back = TP:Current()
    return n == 2 and WI.serial == serial + 2 and typed and kept and back["Nature's Focus"] == 5
        and back["Bloom"] == nil, string.format("n=%d serial+%d typed=%s kept=%s", n, WI.serial - serial,
            tostring(typed), tostring(kept))
end)

T("3 a plan of unmodelled talents only is kept, though the What if has nothing typed", function()
    Use(LIVE)
    TP:Apply({ ["Nature's Focus"] = 3, ["Naturalist"] = 5, ["Gift of Nature"] = 2, ["Heart of the Wild"] = 2 })
    local plan = TP:Current()
    return not WI:Active() and plan["Nature's Focus"] == 3 and plan["Heart of the Wild"] == 2
end)

T("3 review M1: a talent the plan takes to 0 stays at 0", function()
    Use(LIVE)
    TP:Apply({ ["Naturalist"] = 5, ["Gift of Nature"] = 2 }) -- Nature's Focus 5 -> 0, unmodelled
    local plan = TP:Current()
    return plan["Nature's Focus"] == nil and plan["Naturalist"] == 5, tostring(plan["Nature's Focus"])
end)

T("3 review m1: clearing an empty What if forgets a plan of unmodelled talents", function()
    Use(LIVE)
    TP:Apply({ ["Nature's Focus"] = 3, ["Naturalist"] = 5, ["Gift of Nature"] = 2 })
    local kept = TP:Current()["Nature's Focus"] == 3
    local fired = WI:Clear()
    return kept and fired == false and TP:Current()["Nature's Focus"] == 5
end)

T("3 review m5: Problems names a tier, a requirement and points over; a legal plan has none", function()
    local legal = #TP.Problems(LIVE, trees, 17) == 0
    local tier = TP.Problems({ ["Bloom"] = 1 }, trees, 17)
    local req = TP.Problems({ ["Nature's Splendor"] = 1, ["Nature's Majesty"] = 1, ["Improved Wrath"] = 5,
        ["Genesis"] = 5 }, trees, 51)
    local over = TP.Problems(LIVE, trees, 5)
    local saysReq = false
    for _, p in ipairs(req) do if p:find("needs Nature's Majesty", 1, true) then saysReq = true end end
    return legal and #tier == 1 and tier[1]:find("needs 10 points in Restoration", 1, true) ~= nil
        and saysReq and #over == 1 and over[1]:find("12 points spent, 5 to spend", 1, true) ~= nil,
        tostring(tier[1]) .. " / " .. tostring(over[1])
end)

--------------------------------------------------------------------------------
-- 4: the sheet
--------------------------------------------------------------------------------
local TPL = ST.TalentPlanner
local win = CreateFrame("Frame", nil, UIParent)
win:SetSize(860, 560)
win:Show()

T("4 refused while talents are unread, and in combat", function()
    Use(false)
    local s1, why1 = TPL.Open(win)
    Use(LIVE)
    ST.inCombat = true
    local s2, why2 = TPL.Open(win)
    ST.inCombat = false
    return s1 == nil and why1 == "your talents were not read yet" and s2 == nil
        and why2 == "the talent plan does not open in combat"
end)

local function CellOf(sheet, name)
    for _, c in ipairs(sheet.cells) do if c.talent.name == name then return c end end
end
local function Click(b, button)
    local fn = b and b:GetScript("OnClick")
    if fn then fn(b, button or "LeftButton") end
end

T("4 the sheet: every druid talent a cell with its icon; the live ranks; the points", function()
    Use(LIVE)
    TP.kept = nil
    local sheet = TPL.Open(win)
    local n = 0
    for _, tree in ipairs(trees) do n = n + #tree.talents end
    local bloom, nat = CellOf(sheet, "Bloom"), CellOf(sheet, "Naturalist")
    local icon = bloom and bloom.iconPath
    local info = sheet.info:GetText() or ""
    local good = sheet:IsShown() and #sheet.cells == n and n == 52 and icon == "Interface\\Icons\\inv_misc_herb_felblossom"
        and nat.rank:GetText() == "5/5" and bloom.rank:GetText() == "0/1" and bloom.dot:IsShown()
        and not CellOf(sheet, "Furor").dot:IsShown() and info:find("17 points", 1, true) ~= nil
    sheet:Hide()
    return good, string.format("cells %d icon %s info %q", #sheet.cells, tostring(icon), info)
end)

T("4 left adds, right takes off, under the rules; the panel names the change", function()
    Use(LIVE)
    TP.kept = nil
    local sheet = TPL.Open(win)
    local bloom = CellOf(sheet, "Bloom")
    Click(bloom, "LeftButton")
    local added = TPL.Plan()["Bloom"] == 1 and bloom.rank:GetText() == "1/1"
    local changes = (sheet.changes:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    Click(CellOf(sheet, "Naturalist"), "RightButton")
    local held = TPL.Plan()["Naturalist"] == 5 -- Bloom stands on it
    Click(bloom, "RightButton")
    Click(CellOf(sheet, "Naturalist"), "RightButton")
    local stillHeld = TPL.Plan()["Naturalist"] == 5 -- Gift of Nature (tier 3) stands on it too
    Click(CellOf(sheet, "Gift of Nature"), "RightButton")
    Click(CellOf(sheet, "Gift of Nature"), "RightButton")
    Click(CellOf(sheet, "Naturalist"), "RightButton")
    local off = stillHeld and TPL.Plan()["Bloom"] == nil and TPL.Plan()["Naturalist"] == 4
    local name = sheet.selName:GetText()
    sheet:Hide()
    return added and changes:find("Bloom  0 to 1  moves", 1, true) ~= nil and held and off and name == "Naturalist",
        string.format("added %s held %s off %s name %s", tostring(added), tostring(held), tostring(off), tostring(name))
end)

T("4 T141: each click goes into the What if at once (one WHATIF_CHANGED); no Use button; x keeps the plan", function()
    Use(LIVE)
    TP.kept = nil
    WI:Clear()
    local fired = 0
    ST:RegisterCallback("WHATIF_CHANGED", function() fired = fired + 1 end)
    local sheet = TPL.Open(win)
    local noUse = sheet.useBtn == nil
    local f0 = fired
    Click(CellOf(sheet, "Bloom"), "LeftButton")
    local now = WI:Get("talent:Bloom") == 1 and fired - f0 == 1 and TPL.Plan()["Bloom"] == 1
    Click(CellOf(sheet, "Bloom"), "RightButton")
    local back = WI:Get("talent:Bloom") == nil and TPL.Plan()["Bloom"] == nil
    Click(CellOf(sheet, "Bloom"), "LeftButton")
    sheet:Hide()
    local kept = WI:Get("talent:Bloom") == 1
    sheet = TPL.Open(win)
    local reopened = TPL.Plan()["Bloom"] == 1
    Click(sheet.clearBtn)
    local cleared = WI:Get("talent:Naturalist") == 0 and WI:Get("talent:Bloom") == nil
    Click(sheet.mineBtn)
    local mine = WI:Get("talent:Naturalist") == nil and WI:Get("talent:Bloom") == nil
    sheet:Hide()
    WI:Clear()
    return noUse and now and back and kept and reopened and cleared and mine, string.format(
        "noUse %s now %s back %s kept %s reopened %s cleared %s mine %s", tostring(noUse), tostring(now),
        tostring(back), tostring(kept), tostring(reopened), tostring(cleared), tostring(mine))
end)

T("4 T141: docked beside the window, never over it -- its right, else its left where the screen has no room", function()
    Use(LIVE)
    TP.kept = nil
    local pane = CreateFrame("Frame", nil, win)
    local savedR, savedW = win.GetRight, UIParent.GetWidth
    win.GetRight = function() return 900 end
    UIParent.GetWidth = function() return 1920 end
    local sheet = TPL.Open(pane)
    local onWin = sheet:GetParent() == win and sheet.dockedTo == win and sheet.docked == true
    local right = sheet.side == "right"
    local masked = sheet.mask and sheet.mask.IsShown and sheet.mask:IsShown()
    sheet:Hide()
    win.GetRight = function() return 1800 end
    sheet = TPL.Open(pane)
    local left = sheet.side == "left"
    win.GetRight, UIParent.GetWidth = savedR, savedW
    sheet:Hide()
    return onWin and right and left and not masked, string.format("onWin %s right %s left %s masked %s",
        tostring(onWin), tostring(right), tostring(left), tostring(masked))
end)

T("4 My talents and Clear", function()
    Use(LIVE)
    TP.kept = nil
    local sheet = TPL.Open(win)
    Click(sheet.clearBtn)
    local cleared = next(TPL.Plan()) == nil and (sheet.info:GetText() or ""):find("0 of 51 spent", 1, true) ~= nil
    Click(sheet.mineBtn)
    local mine = TPL.Plan()["Naturalist"] == 5 and TPL.Plan()["Gift of Nature"] == 2
    sheet:Hide()
    return cleared and mine
end)

T("4 the drawer's Talent plan... opens the panel beside the window (T141)", function()
    Use(LIVE)
    TP.kept = nil
    if not ST.Tabs:Has("Rejuvenation") then ST.Tabs:Add("Rejuvenation", nil); ST.SpellsPane:ListChanged() end
    ST:SelectView("spells", "fam:Rejuvenation")
    local f = ST.SpellsPane.family
    if not (f and f.strip and f.strip.whatIfBtn) then return false, "no What if button" end
    if not (f.whatIf and f.whatIf:IsShown()) then Click(f.strip.whatIfBtn) end
    local d = f.whatIf
    if not (d and d.planBtn) then return false, "no drawer" end
    local shown = d.planBtn:IsShown()
    Click(d.planBtn)
    local sheet = TPL.Sheet()
    local open = sheet and sheet:IsShown() and sheet:GetParent() == TPL.TopOf(d:GetParent())
    if sheet then sheet:Hide() end
    Click(f.strip.whatIfBtn)
    return shown and open, tostring(shown) .. " " .. tostring(open)
end)

T("4 the plan docks beside the open What if drawer, never over it; beside the window once it closes (2026-11-08)", function()
    Use(LIVE)
    TP.kept = nil
    ST:SelectView("spells", "fam:Rejuvenation")
    local f = ST.SpellsPane.family
    if not (f.whatIf and f.whatIf:IsShown()) then Click(f.strip.whatIfBtn) end
    local d = f.whatIf
    if not (d and d:IsShown()) then return false, "no drawer" end
    local sheet = TPL.Open(d)
    if not sheet then return false, "no sheet" end
    local rel
    local orig = sheet.SetPoint
    sheet.SetPoint = function(self, p, r, ...) rel = r; return orig(self, p, r, ...) end
    TPL.Redock()
    local beside = sheet.besideDrawer == true and rel == d
    Click(f.strip.whatIfBtn) -- closes the drawer; OnHide redocks
    local back = sheet.besideDrawer == false and rel == sheet.win and not d:IsShown()
    sheet.SetPoint = orig
    sheet:Hide()
    return beside and back, string.format("beside %s back %s", tostring(beside), tostring(back))
end)

local function SameColour(tex, token)
    local r, g, b = UI.RGB(token)
    local c = tex.color or {}
    return c[1] == r and c[2] == g and c[3] == b
end

T("4 review m9: a locked cell's edge is the disabled colour; ESC stack holds the sheet; the window hides it", function()
    Use(LIVE)
    TP.kept = nil
    local sheet = TPL.Open(win)
    local locked = SameColour(CellOf(sheet, "Wild Growth").edge, "disabled") -- the stub keeps no alpha
    local stacked = false
    for _, e in ipairs(ST.EscStack.stack) do if e.frame == sheet then stacked = true end end
    win:Hide()
    local hidden = not sheet:IsShown()
    win:Show()
    return locked and stacked and hidden, string.format("locked %s stacked %s hidden %s",
        tostring(locked), tostring(stacked), tostring(hidden))
end)

T("4 review m5: a typed talent past the rules is red and the info line says so; My talents clamps", function()
    Use({ ["Nature's Focus"] = 5 })
    TP.kept = nil
    WI:Set("talent:Bloom", 1) -- Restoration has 5 points, Bloom needs 10
    local sheet = TPL.Open(win)
    local red = SameColour(CellOf(sheet, "Bloom").edge, "bad")
    local says = (sheet.info:GetText() or ""):find("breaks the rules: Bloom needs 10 points", 1, true) ~= nil
    sheet:Hide()
    WI:Clear()
    Use({ ["Naturalist"] = 9 })
    sheet = TPL.Open(win)
    Click(sheet.mineBtn)
    local clamped = TPL.Plan()["Naturalist"] == 5
    sheet:Hide()
    return red and says and clamped, string.format("red %s says %s clamped %s",
        tostring(red), tostring(says), tostring(clamped))
end)

T("4 review m2: a spinner moved while the sheet is open moves the plan; a second press keeps it", function()
    Use(LIVE)
    TP.kept = nil
    local sheet = TPL.Open(win)
    Click(CellOf(sheet, "Heart of the Wild"), "LeftButton") -- unmodelled, in progress
    WI:Set("talent:Naturalist", 3)
    local synced = TPL.Plan()["Naturalist"] == 3 and CellOf(sheet, "Naturalist").rank:GetText() == "3/5"
    TPL.Open(win)
    local keptInProgress = TPL.Plan()["Heart of the Wild"] == 1
    Click(CellOf(sheet, "Genesis"), "LeftButton") -- a modelled click not yet used
    WI:Set("level", 40)
    keptInProgress = keptInProgress and TPL.Plan()["Genesis"] == 1 and TP:Modelled("Genesis")
        and TPL.Plan()["Naturalist"] == 3
    sheet:Hide()
    WI:Clear()
    return synced and keptInProgress
end)

T("4 review m3: the drawer's Talent plan... shows when the family has no talent rows", function()
    Use(LIVE)
    TP.kept = nil
    local rowsFor = WI.ClassRowsFor
    WI.ClassRowsFor = function() return nil end
    ST:SelectView("spells", "fam:Rejuvenation")
    local f = ST.SpellsPane.family
    if f.whatIf and f.whatIf:IsShown() then Click(f.strip.whatIfBtn) end
    Click(f.strip.whatIfBtn)
    local shown = f.whatIf.planBtn:IsShown()
    WI.ClassRowsFor = rowsFor
    Click(f.strip.whatIfBtn)
    return shown
end)

T("4 T138 the plan spends up to 51; past the level's points it says the level it needs", function()
    Use(LIVE)
    TP.kept = nil
    local sheet = TPL.Open(win)
    local fits = (sheet.info:GetText() or ""):find("needs level", 1, true) == nil
    for _ = 1, 3 do Click(CellOf(sheet, "Heart of the Wild"), "LeftButton") end -- 15 spent
    for _ = 1, 5 do Click(CellOf(sheet, "Furor"), "LeftButton") end              -- 20 spent, 17 at 26
    local spent = TP.Total(TPL.Plan(), trees)
    local info = (sheet.info:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local warns = info:find("you don't have that many yet: needs level 29", 1, true) ~= nil
    WI:Set("level", 40)
    local info40 = (sheet.info:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    sheet:Hide()
    WI:Clear()
    return fits and spent == 20 and warns and info40:find("level 40: 31 points", 1, true) ~= nil
        and info40:find("needs level", 1, true) == nil, info .. " / " .. info40
end)

T("4 T138 TP.Level and TP.NeedLevel", function()
    Use(LIVE)
    local live = TP.Level()
    WI:Set("level", 50)
    local typed = TP.Level()
    WI:Clear()
    return live == 26 and typed == 50 and TP.NeedLevel(51) == 60 and TP.NeedLevel(1) == 10 and TP.NeedLevel(0) == nil
end)

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
os.exit(#fails == 0 and 0 or 1)
