local _, ST = ...

--------------------------------------------------------------------------------
-- T137 (docs/tasks/T137-forever-talent-planner.md; the author: "a small copy of
-- the actual talent tree where the player can plan a build, and we calculate
-- like he has those talents"): the talent planner, a sheet over the main window,
-- Forever TOCs only. The What if drawer's "Talent plan..." opens it.
--
-- Three trees laid out as the game lays them (Data/TalentTree_Forever.lua), each
-- talent its real icon; left-click adds a point, right-click takes one off, under
-- the game's rules (Spells/TalentPlan.lua). A blue dot marks a talent the What if
-- moves numbers by. The panel on the right: the hovered talent, then every change
-- from the live build. "Use in What if" puts the plan into the What if and
-- closes; the x or ESC closes without it. Never opens in combat; never saved.
--
-- ST.TalentPlanner: Open(win) -> the sheet or nil, why; sheet (for the suites).
--------------------------------------------------------------------------------
local UI = ST.UI
local TP = ST.TalentPlan
if not (UI and TP) then return end

local TPL = {}
ST.TalentPlanner = TPL

local SHEET_W, SHEET_H = 840, 520
local CELL, GAP_X, GAP_Y = 34, 14, 18
local TREE_W = 196
local PAD = 12
local GRID_TOP = 62
local PANEL_X = PAD + 3 * TREE_W + 8
local PANEL_W = SHEET_W - 2 - PANEL_X - PAD
local ICON_PATH = "Interface\\Icons\\"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local sheet, cells, trees, plan, points, live, sel

local function Esc(s) return ST.Text and ST.Text.Esc and ST.Text.Esc(s) or s end

local function ClassName()
    local c = ST.player and ST.player.class or ""
    return c:sub(1, 1) .. c:sub(2):lower()
end

-- A cell's state at paint: maxed, some, open (can take a point), locked.
local function CellState(t)
    local r = TP.Rank(plan, t.name)
    if r > 0 then
        local f = TP.Find(trees, t.name)
        local q = t.req and TP.Find(trees, t.req)
        if TP.Spent(plan, trees, f.tree, t.row) < (t.row - 1) * 5 or (q and TP.Rank(plan, t.req) < q.t.max) then
            return "broken" -- review m5
        end
    end
    if r >= t.max then return "maxed" end
    if r > 0 then return "some" end
    if TP.CanAdd(plan, trees, t.name, points) then return "open" end
    -- out of points is not locked: the tier and the requirement are what lock
    local need = (t.row - 1) * 5
    local f = TP.Find(trees, t.name)
    if TP.Spent(plan, trees, f.tree, t.row) < need then return "locked" end
    if t.req then
        local q = TP.Find(trees, t.req)
        if q and TP.Rank(plan, t.req) < q.t.max then return "locked" end
    end
    return "open"
end

local EDGE = { maxed = "accent", some = "good", open = "label", locked = "disabled", broken = "bad" }

local function PaintCell(c)
    local t = c.talent
    local state = CellState(t)
    local r, g, b = UI.RGB(EDGE[state])
    c.edge:SetColorTexture(r, g, b, 1)
    c.icon:SetAlpha(state == "locked" and 0.45 or 1)
    if c.icon.SetDesaturated then c.icon:SetDesaturated(state == "locked") end
    c.rank:SetText(TP.Rank(plan, t.name) .. "/" .. t.max)
    c.rank:SetTextColor(UI.RGB(state == "maxed" and "accent" or state == "some" and "good" or "label"))
    local mr, mg, mb = UI.RGB("mana")
    c.dot:SetColorTexture(mr, mg, mb, 1)
    c.dot:SetShown(TP:Modelled(t.name))
    c.selected:SetShown(sel == t.name)
end

local MAX_CHANGES = 10

local function ChangesText()
    local names, seen = {}, {}
    for k in pairs(plan) do if not seen[k] then seen[k] = true; names[#names + 1] = k end end
    for k in pairs(live) do
        if not seen[k] and TP.Find(trees, k) then seen[k] = true; names[#names + 1] = k end
    end
    table.sort(names)
    local lines, more = {}, 0
    for _, n in ipairs(names) do
        local a, b = TP.Rank(live, n), TP.Rank(plan, n)
        if a ~= b and #lines >= MAX_CHANGES then
            more = more + 1
        elseif a ~= b then
            local tag = TP:Modelled(n) and (UI.Hex("mana") .. "moves|r") or (UI.Hex("muted") .. "no effect|r")
            lines[#lines + 1] = Esc(n) .. "  " .. UI.Hex("label") .. a .. " to " .. b .. "|r  " .. tag
        end
    end
    if #lines == 0 then return UI.Hex("muted") .. "None: the plan is your live build.|r" end
    if more > 0 then lines[#lines + 1] = UI.Hex("muted") .. "and " .. more .. " more|r" end
    return table.concat(lines, "|n")
end

local function PaintPanel()
    local f = sel and TP.Find(trees, sel)
    if not f then
        sheet.selName:SetText("")
        sheet.selInfo:SetText("")
        sheet.selDesc:SetText("")
        sheet.selModel:SetText("")
    else
        local t = f.t
        sheet.selName:SetText(Esc(t.name))
        local info = trees[f.tree].name .. ", tier " .. t.row .. " - rank " .. TP.Rank(plan, t.name) .. " of " .. t.max
        if t.req then info = info .. "|nRequires " .. Esc(t.req) .. " at full rank" end
        local ok, why = TP.CanAdd(plan, trees, t.name, points)
        if not ok and TP.Rank(plan, t.name) < t.max then info = info .. "|n" .. UI.Hex("bad") .. why .. "|r" end
        sheet.selInfo:SetText(info)
        sheet.selDesc:SetText(Esc(t.desc or ""))
        sheet.selModel:SetText(TP:Modelled(t.name)
            and (UI.Hex("mana") .. "Moves SpellTuner's numbers: the Spells pane follows this rank.|r")
            or (UI.Hex("muted") .. "Not modelled yet: it counts for points and tiers, no number moves.|r"))
    end
    sheet.changes:SetText(ChangesText())
end

local function Paint()
    local spent = TP.Total(plan, trees)
    local info = ClassName() .. ", level " .. tostring(ST.player and ST.player.level or "?") .. ": "
        .. points .. " points  " .. (spent == points and UI.Hex("good") or UI.Hex("label")) .. spent .. " spent|r"
    -- review m5: a plan the spinners typed past the game's rules is said, never painted as fine
    local problems = TP.Problems(plan, trees, points)
    if #problems > 0 then
        info = info .. "  " .. UI.Hex("bad") .. "breaks the rules: " .. Esc(problems[1])
            .. (#problems > 1 and (" (+" .. (#problems - 1) .. ")") or "") .. "|r"
    end
    sheet.info:SetText(info)
    for ti, tree in ipairs(trees) do
        local h = sheet.heads[ti]
        if h then h:SetText(Esc(tree.name) .. "  " .. UI.Hex("accent") .. TP.Spent(plan, trees, ti) .. "|r") end
    end
    for _, c in ipairs(cells) do PaintCell(c) end
    PaintPanel()
end

local function Change(name, delta)
    if delta > 0 and not TP.CanAdd(plan, trees, name, points) then return false end
    if delta < 0 and not TP.CanRemove(plan, trees, name) then return false end
    local r = TP.Rank(plan, name) + delta
    plan[name] = (r > 0) and r or nil
    sel = name
    Paint()
    return true
end
TPL.Change = Change -- for the suites

local function MakeCell(parent, t, x, y)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(CELL, CELL)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    if c.RegisterForClicks then c:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    c.talent = t
    c.edge = c:CreateTexture(nil, "BACKGROUND")
    c.edge:SetAllPoints(c)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", c, "TOPLEFT", 2, -2)
    c.icon:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -2, 2)
    c.iconPath = t.icon and (ICON_PATH .. t.icon) or FALLBACK_ICON
    if c.icon:SetTexture(c.iconPath) == false then
        c.iconPath = FALLBACK_ICON -- a name the client does not have
        c.icon:SetTexture(c.iconPath)
    end
    if c.icon.SetTexCoord then c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    c.dot = c:CreateTexture(nil, "OVERLAY")
    c.dot:SetSize(6, 6)
    c.dot:SetPoint("TOPLEFT", c, "TOPLEFT", 3, -3)
    c.selected = c:CreateTexture(nil, "OVERLAY")
    c.selected:SetPoint("TOPLEFT", c, "TOPLEFT", -2, 2)
    c.selected:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 2, -2)
    c.selected:SetColorTexture(1, 1, 1, 0.18)
    c.rankBg = c:CreateTexture(nil, "OVERLAY")
    c.rankBg:SetColorTexture(0, 0, 0, 0.85)
    c.rank = c:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    c.rank:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 6, -7)
    c.rankBg:SetPoint("TOPLEFT", c.rank, "TOPLEFT", -2, 1)
    c.rankBg:SetPoint("BOTTOMRIGHT", c.rank, "BOTTOMRIGHT", 2, -1)
    c:SetScript("OnClick", function(_, button)
        Change(t.name, (button == "RightButton") and -1 or 1)
    end)
    c:SetScript("OnEnter", function()
        if sel ~= t.name then sel = t.name; Paint() end
    end)
    return c
end

local function Text(parent, font, x, y, w)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or UI.FONT)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    if w then fs:SetWidth(w) end
    fs:SetJustifyH("LEFT")
    if fs.SetJustifyV then fs:SetJustifyV("TOP") end
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    return fs
end

local function Build(win)
    if sheet then sheet:Hide() end
    sheet = UI.CreateSheet(win, win, SHEET_W, SHEET_H, "TALENT PLAN")
    sheet.win = win
    cells = nil
    sheet.talentPlanner = true -- marks the sheet for tools/talentplancheck.lua
    local body = sheet:Body()
    sheet.info = Text(body, UI.FONT, PAD, 10)
    UI.Tint(sheet.info, "text", "text")

    local use = UI.CreateButton(body, "Use in What if", "accent-hover", { 110, 20 }, false, false, UI.FONT_SMALL, nil)
    use:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, -6)
    use:SetScript("OnClick", function()
        TP:Apply(plan)
        sheet:Hide()
    end)
    local clear = UI.CreateButton(body, "Clear", "accent-hover", { 60, 20 }, false, false, UI.FONT_SMALL, nil)
    clear:SetPoint("RIGHT", use, "LEFT", -6, 0)
    clear:SetScript("OnClick", function() plan = {}; Paint() end)
    local mine = UI.CreateButton(body, "My talents", "accent-hover", { 84, 20 }, false, false, UI.FONT_SMALL, nil)
    mine:SetPoint("RIGHT", clear, "LEFT", -6, 0)
    mine:SetScript("OnClick", function()
        plan = {}
        for k, v in pairs(live) do
            local f = TP.Find(trees, k)
            if f and type(v) == "number" and v > 0 then plan[k] = math.min(v, f.t.max) end -- review m5
        end
        Paint()
    end)
    sheet.useBtn, sheet.clearBtn, sheet.mineBtn = use, clear, mine

    sheet.heads, sheet.body = {}, body
    -- review m4: each line of the panel under the one before, so a long sentence pushes
    local function Under(fs, above, gap)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -gap)
        return fs
    end
    sheet.selName = Text(body, UI.FONT_CLASS or UI.FONT, PANEL_X, 40, PANEL_W)
    UI.Tint(sheet.selName, "text", "accent")
    sheet.selInfo = Under(Text(body, UI.FONT_SMALL, PANEL_X, 0, PANEL_W), sheet.selName, 6)
    UI.Tint(sheet.selInfo, "text", "label")
    sheet.selDesc = Under(Text(body, UI.FONT_SMALL, PANEL_X, 0, PANEL_W), sheet.selInfo, 8)
    UI.Tint(sheet.selDesc, "text", "text")
    sheet.selModel = Under(Text(body, UI.FONT_SMALL, PANEL_X, 0, PANEL_W), sheet.selDesc, 8)
    local ch = Under(Text(body, UI.FONT, PANEL_X, 0, PANEL_W), sheet.selModel, 14)
    ch:SetText("Changes from your talents")
    UI.Tint(ch, "text", "text")
    sheet.changes = Under(Text(body, UI.FONT_SMALL, PANEL_X, 0, PANEL_W), ch, 6)
    local legend = Text(body, UI.FONT_SMALL, PAD, SHEET_H - 22 - 40, SHEET_W - 2 * PAD)
    legend:SetText(UI.Hex("mana") .. "Blue dot|r: moves SpellTuner's numbers.  Left-click adds a point, right-click "
        .. "takes one off; five points in a tree open its next tier.|nPreliminary, from talentsforever. Not saved "
        .. "to your character: the What if uses the plan until you clear it.")
    UI.Tint(legend, "text", "muted")
    sheet.legend = legend
    sheet:HookScript("OnHide", function() sel = nil end)
    -- review m2: the What if drawer sits outside the mask; a spinner moved while the
    -- sheet is open moves the plan too, so Use never overwrites it unseen
    ST:RegisterCallback("WHATIF_CHANGED", function()
        if not (sheet and sheet:IsShown() and plan and live) then return end
        local WI = ST.WhatIf
        for _, tree in ipairs(trees) do
            for _, t in ipairs(tree.talents) do
                if TP:Modelled(t.name) then
                    local r = WI:Get("talent:" .. t.name)
                    if r == nil then r = TP.Rank(live, t.name) end
                    plan[t.name] = (r > 0) and math.min(r, t.max) or nil
                end
            end
        end
        Paint()
    end)
    -- closes with its window (the bindings sheet's rule)
    win:HookScript("OnHide", function() if sheet:IsShown() then sheet:Hide() end end)
end

-- The trees' cells, rebuilt when the class's trees differ from the last ones.
local function Layout()
    if sheet.builtFor == trees then return end
    for _, c in ipairs(cells or {}) do c:Hide() end
    for _, h in ipairs(sheet.heads) do h:Hide() end
    cells, sheet.heads = {}, {}
    local body = sheet.body
    for ti, tree in ipairs(trees) do
        local x0 = PAD + (ti - 1) * TREE_W
        local h = Text(body, UI.FONT, x0, 40)
        UI.Tint(h, "text", "text")
        sheet.heads[ti] = h
        for _, t in ipairs(tree.talents) do
            local x = x0 + (t.col - 1) * (CELL + GAP_X)
            local y = GRID_TOP + (t.row - 1) * (CELL + GAP_Y)
            cells[#cells + 1] = MakeCell(body, t, x, y)
        end
    end
    sheet.cells = cells
    sheet.builtFor = trees
end

-- TPL.Open(win) -> the sheet shown, or nil and why.
function TPL.Open(win)
    -- review m2: a second press while it is open keeps the plan in progress
    if sheet and sheet:IsShown() and sheet.win == win then return sheet end
    if ST.inCombat then
        return nil, "the talent plan does not open in combat"
    end
    trees = TP.Trees()
    if not trees then return nil, "no talent trees for this class" end
    live = TP:Live()
    if not live then return nil, "your talents were not read yet" end
    if not win then return nil, "no window" end
    if not sheet or sheet.win ~= win then Build(win) end
    Layout()
    plan = TP:Current() or {}
    local liveTotal = TP.Total(live, trees)
    points = TP.Points(ST.player and ST.player.level, liveTotal)
    if not (sel and TP.Find(trees, sel)) then sel = trees[1].talents[1] and trees[1].talents[1].name end
    Paint()
    sheet:Show()
    if ST.Win and ST.Win.Push then ST.Win:Push(sheet) end
    return sheet
end

function TPL.Available()
    return TP.Trees() ~= nil and TP:Live() ~= nil
end

function TPL.Sheet() return sheet end
function TPL.Plan() return plan end
