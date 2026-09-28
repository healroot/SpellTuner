-- Simulate -> Practice (v0.15.0, docs/SPEC-v0.15.md): set up a fight, then
-- play it. The group, every member's health and the damage each of them takes,
-- group AoE, other healers, and what your keys and mouse buttons cast. Start
-- opens the replay window in practice mode (UI/ReplayWindow.lua); what you play
-- comes back as a recording under Reports -> Review -> Practice.
--
-- The setup is per character (cdb.practiceSetup: health depends on level) and
-- the bindings are account-wide (db.practiceBinds: your hands do not change).
-- Every default number is a placeholder and the panel says so.
local _, MD = ...
local UI = MD.UI
MD.DashboardParts = MD.DashboardParts or {}

local ROW_H = 20
-- the table's columns: key, header, width, how it is shown (pct = x100)
local COLS = {
    { "name",       "Name",        120, "text" },
    { "kind",       "Role",         56, "label" },
    { "maxHP",      "Max HP",       58, "int" },
    { "dps",        "Dmg %/s",      58, "pct",  "Steady damage per second, as a percent of their max health." },
    { "swing",      "Hit every s",  66, "num",  "Seconds between the hits that deliver it. 0 = a smooth 1s tick." },
    { "spike",      "Spike %",      56, "pct",  "One big hit, as a percent of their max health." },
    { "spikeEvery", "Spike every s", 78, "num", "Average seconds between spikes. 0 = no spikes." },
    { "jitter",     "Random %",     60, "pct",  "How far hit sizes and timings wander either side of the average." },
}

local function Fmt(v, how)
    if v == nil then return "" end
    if how == "pct" then v = v * 100 end
    if how == "int" then return string.format("%d", v + 0.5) end
    local str = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
    return str
end

local function Parse(text, how)
    local v = tonumber((tostring(text or ""):gsub(",", ".")))
    if not v or v < 0 then return nil end
    if how == "pct" then v = v / 100 end
    if how == "int" then v = math.floor(v + 0.5) end
    return v
end

-- one numeric field that writes itself back on Enter or when focus leaves
local function Field(parent, width, get, set, how, tip)
    local eb = UI.CreateEditBox(parent, width, ROW_H - 2)
    eb:SetJustifyH("RIGHT")
    local function Commit(self)
        local v = Parse(self:GetText(), how)
        if v ~= nil then set(v) end
        self:SetText(Fmt(get(), how))
    end
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0); Commit(self) end)
    function eb:Refresh() self:SetText(Fmt(get(), how)) end
    if tip then UI.SetTooltips(eb, "ANCHOR_TOP", 0, 2, tip) end
    return eb
end

function MD.DashboardParts.CreatePractice(parent, width)
    local PR = MD.Practice
    local pane = CreateFrame("Frame", nil, parent)
    pane:Hide()
    local api = { frame = pane }

    local function Setup()
        MD.cdb.practiceSetup = MD.cdb.practiceSetup or PR.DefaultSetup("5")
        return MD.cdb.practiceSetup
    end

    local intro = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    intro:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    intro:SetWidth(width - 20)
    intro:SetJustifyH("LEFT")
    intro:SetText("Heal a fight you play. Set the group and the damage, press Start, then hover a frame and " ..
        "press a binding. What you play is recorded like a real pull: it opens as a replay, and the coach " ..
        "answers it. |cff888888Every default number here is a placeholder - one healer's guess at a TBC " ..
        "group - so change them to the fight you want to rehearse.|r")

    ----------------------------------------------------------------------------
    -- the group
    ----------------------------------------------------------------------------
    local groupBtns, prev = {}, nil
    for i, g in ipairs(PR.GROUPS) do
        local b = UI.CreateButton(pane, g.label, "accent-hover", { 70, 18 }, false, false, UI.FONT_SMALL, nil)
        b.id = g.id
        if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0)
        else b:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -44) end
        groupBtns[i] = b
        prev = b
    end
    local highlightGroup
    highlightGroup = UI.CreateButtonGroup(groupBtns, function(id)
        local old = Setup()
        local new = PR.DefaultSetup(id)
        new.dur, new.startHp, new.otherHealing, new.aoe = old.dur, old.startHp, old.otherHealing, old.aoe
        MD.cdb.practiceSetup = new
        api:Render()
    end)

    -- fight-wide numbers on one line
    local fightFields = {}
    local function FightField(label, w, key, how, sub, tip, x)
        local fs = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        fs:SetText(label)
        local eb = Field(pane, w,
            function() local t = sub and Setup()[sub] or Setup(); return t and t[key] end,
            function(v)
                local st = Setup()
                if sub then st[sub] = st[sub] or {}; st[sub][key] = v else st[key] = v end
            end, how, tip)
        fightFields[#fightFields + 1] = eb
        return fs, eb
    end
    local line2 = {
        { "Length (s)",        44, "dur",          "int", nil,   "How long the fight runs (10 to 600 seconds)." },
        { "Start health %",    40, "startHp",      "pct", nil,   "Where everyone's health starts." },
        { "Other healers %",   40, "otherHealing", "pct", nil,   "A share of every hit that somebody else heals back, a second or two later." },
        { "AoE %",             40, "size",         "pct", "aoe", "A hit on everyone at once, as a percent of each one's max health. 0 = none." },
        { "every s",           40, "every",        "num", "aoe", "Average seconds between AoE hits." },
        { "random %",          40, "jitter",       "pct", "aoe", "How far the AoE's size and timing wander." },
    }
    local anchor = nil
    for _, d in ipairs(line2) do
        local fs, eb = FightField(d[1], d[2], d[3], d[4], d[5], d[6])
        if anchor then fs:SetPoint("LEFT", anchor, "RIGHT", 14, 0)
        else fs:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -72) end
        eb:SetPoint("LEFT", fs, "RIGHT", 4, 0)
        anchor = eb
    end

    local seedCB, seedEB
    seedCB = UI.CreateCheckButton(pane, "Same fight again", function(checked)
        Setup().fixedSeed = checked and (Setup().fixedSeed or (time and time()) or 1) or nil
        api:Render()
    end, "Same fight again", "On: the damage comes out identical every time, so you can",
        "replay a fight you lost. Off: a new roll of the dice each Start.")
    seedCB:SetPoint("LEFT", anchor, "RIGHT", 16, 0)
    seedEB = Field(pane, 80, function() return Setup().fixedSeed end,
        function(v) Setup().fixedSeed = math.max(1, math.floor(v)) end, "int", "The seed: the same number is the same fight.")
    seedEB:SetPoint("LEFT", seedCB.label, "RIGHT", 6, 0)

    ----------------------------------------------------------------------------
    -- the group, one row each
    ----------------------------------------------------------------------------
    local TABLE_W = 0
    for _, c in ipairs(COLS) do TABLE_W = TABLE_W + c[3] + 4 end
    local tableTop = -100
    local header = CreateFrame("Frame", nil, pane)
    header:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, tableTop)
    header:SetSize(TABLE_W, ROW_H)
    do
        local x = 0
        for _, c in ipairs(COLS) do
            local fs = header:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
            fs:SetPoint("LEFT", header, "LEFT", x, 0)
            fs:SetWidth(c[3])
            fs:SetJustifyH(c[4] == "text" and "LEFT" or c[4] == "label" and "LEFT" or "RIGHT")
            fs:SetText("|cff888888" .. c[2] .. "|r")
            x = x + c[3] + 4
        end
    end

    -- "set every tank at once": one row of the same fields per role kind
    local roleRows = {}
    local roleBox = CreateFrame("Frame", nil, pane)
    roleBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    roleBox:SetSize(TABLE_W, #PR.ROLE_ORDER * ROW_H)
    for r, kind in ipairs(PR.ROLE_ORDER) do
        local row = CreateFrame("Frame", nil, roleBox)
        row:SetPoint("TOPLEFT", roleBox, "TOPLEFT", 0, -(r - 1) * ROW_H)
        row:SetSize(TABLE_W, ROW_H)
        row.fields = {}
        local x = 0
        for _, c in ipairs(COLS) do
            if c[1] == "name" then
                local fs = row:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
                fs:SetPoint("LEFT", row, "LEFT", x, 0)
                fs:SetText("|cffffcc00every " .. PR.ROLES[kind].label:lower() .. "|r")
            elseif c[4] ~= "label" and c[1] ~= "maxHP" then
                local key, how = c[1], c[4]
                local eb = Field(row, c[3], function()
                    for _, tg in ipairs(Setup().targets) do if tg.kind == kind then return tg[key] end end
                    return PR.ROLES[kind][key]
                end, function(v)
                    PR.ApplyRole(Setup(), kind, { [key] = v })
                    api:Render()
                end, how, c[5] and ("Every " .. PR.ROLES[kind].label:lower() .. ": " .. c[5]))
                eb:SetPoint("LEFT", row, "LEFT", x, 0)
                row.fields[#row.fields + 1] = eb
            end
            x = x + c[3] + 4
        end
        roleRows[r] = row
    end

    local scroll = UI.CreateScrollFrame(pane, 0, 0)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", roleBox, "BOTTOMLEFT", 0, -6)
    scroll:SetSize(TABLE_W + 4, 250)
    scroll:SetScrollStep(ROW_H * 3)
    local rows = {}
    local function Row(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, scroll.content)
        row:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetSize(TABLE_W, ROW_H)
        row.fields = {}
        local x = 0
        for _, c in ipairs(COLS) do
            local key, how = c[1], c[4]
            if how == "label" then
                local fs = row:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
                fs:SetPoint("LEFT", row, "LEFT", x + 2, 0)
                fs:SetWidth(c[3])
                fs:SetJustifyH("LEFT")
                row.kindFS = fs
            else
                local eb = UI.CreateEditBox(row, c[3], ROW_H - 2)
                eb:SetPoint("LEFT", row, "LEFT", x, 0)
                eb:SetJustifyH(how == "text" and "LEFT" or "RIGHT")
                eb.key, eb.how = key, how
                eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                eb:SetScript("OnEditFocusLost", function(self)
                    self:HighlightText(0, 0)
                    local tg = Setup().targets[row.index]
                    if not tg then return end
                    if how == "text" then
                        local t = strtrim(self:GetText() or "")
                        if t ~= "" then tg[key] = t:gsub("|", "") end
                        self:SetText(tg[key] or "")
                    else
                        local v = Parse(self:GetText(), how)
                        if v ~= nil then
                            if key == "maxHP" and v < 1 then v = 1 end
                            tg[key] = v
                        end
                        self:SetText(Fmt(tg[key], how))
                    end
                end)
                if c[5] then UI.SetTooltips(eb, "ANCHOR_TOP", 0, 2, c[2], c[5]) end
                row.fields[#row.fields + 1] = eb
            end
            x = x + c[3] + 4
        end
        rows[i] = row
        return row
    end

    ----------------------------------------------------------------------------
    -- bindings: shown here, edited in their own window (UI/BindingsWindow.lua)
    ----------------------------------------------------------------------------
    local BIND_X = TABLE_W + 30
    local bindTitle = pane:CreateFontString(nil, "OVERLAY", UI.FONT)
    bindTitle:SetPoint("TOPLEFT", pane, "TOPLEFT", BIND_X, tableTop)
    bindTitle:SetText("What your presses cast")
    local bindFS = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    bindFS:SetPoint("TOPLEFT", bindTitle, "BOTTOMLEFT", 0, -6)
    bindFS:SetWidth(width - BIND_X - 10)
    bindFS:SetJustifyH("LEFT")
    bindFS:SetJustifyV("TOP")

    local bindBtn = UI.CreateButton(pane, "Edit bindings", "accent-hover", { 110, 20 }, false, false,
        UI.FONT_SMALL, nil, "Practice bindings", "Set what each key and mouse button casts,",
        "or import them from Cell or Clique.")
    bindBtn:SetScript("OnClick", function() if MD.ShowBindings then MD:ShowBindings() end end)

    local function BindLines()
        PR.EnsureKit()
        local SD = MD.SpellData
        local out = {}
        for _, b in ipairs(PR.Binds()) do
            local id = PR.SpellFor(b)
            local label = (SD.families[b.family] and SD.families[b.family].label) or b.family
            if b.rank and id and SD.spells[id].rank == b.rank then label = label .. " " .. b.rank end
            out[#out + 1] = string.format("|cffffcc00%s|r  %s%s",
                b.key ~= "" and b.key or "unbound", label, id and "" or "  |cffff9966(not trained)|r")
        end
        if #out == 0 then return "|cffff9966Nothing is bound - press Edit bindings.|r" end
        out[#out + 1] = "|cff888888Hover a frame and press. Import from Cell or Clique in the bindings window.|r"
        return table.concat(out, "\n")
    end

    ----------------------------------------------------------------------------
    -- start
    ----------------------------------------------------------------------------
    local startBtn = UI.CreateButton(pane, "Start practice", "accent", { 160, 26 }, false, false, nil, nil,
        "Start practice", "Opens the fight. Hover a frame and press a binding;",
        "space pauses; End (or closing the window) keeps what you played.")
    startBtn:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 4, 30)
    local statusFS = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    statusFS:SetPoint("LEFT", startBtn, "RIGHT", 12, 0)
    statusFS:SetWidth(width - 200)
    statusFS:SetJustifyH("LEFT")
    startBtn:SetScript("OnClick", function()
        -- an edit box still holding focus has not written its value yet
        for _, row in ipairs(rows) do for _, eb in ipairs(row.fields) do if eb:HasFocus() then eb:ClearFocus() end end end
        for _, eb in ipairs(fightFields) do if eb:HasFocus() then eb:ClearFocus() end end
        local st = Setup()
        if MD.OpenPractice then MD:OpenPractice(PR.CopySetup(st), st.fixedSeed) end
    end)

    function api:Render()
        if not pane:IsShown() then return end
        local st = Setup()
        highlightGroup(st.group)
        for _, eb in ipairs(fightFields) do eb:Refresh() end
        seedCB:SetChecked(st.fixedSeed ~= nil)
        if st.fixedSeed then seedEB:Show(); seedEB:Refresh() else seedEB:Hide() end
        for _, row in ipairs(roleRows) do for _, eb in ipairs(row.fields) do eb:Refresh() end end

        for i, tg in ipairs(st.targets) do
            local row = Row(i)
            row.index = i
            row.kindFS:SetText((tg.you and "|cff99dd99you|r " or "") .. "|cff888888" ..
                PR.ROLES[tg.kind].label:lower() .. "|r")
            for _, eb in ipairs(row.fields) do
                if eb.how == "text" then eb:SetText(tg[eb.key] or "") else eb:SetText(Fmt(tg[eb.key], eb.how)) end
            end
            row:Show()
        end
        for i = #st.targets + 1, #rows do rows[i]:Hide() end
        scroll:SetContentHeight(math.max(1, #st.targets) * ROW_H)

        bindFS:SetText(BindLines())
        bindBtn:ClearAllPoints()
        bindBtn:SetPoint("TOPLEFT", bindFS, "BOTTOMLEFT", 0, -8 - 12 * #PR.Binds())

        local total = 0
        for _, tg in ipairs(st.targets) do
            total = total + (tg.dps or 0) * (tg.maxHP or 0)
            if (tg.spikeEvery or 0) > 0 then total = total + (tg.spike or 0) * (tg.maxHP or 0) / tg.spikeEvery end
            if st.aoe and (st.aoe.every or 0) > 0 then total = total + (st.aoe.size or 0) * (tg.maxHP or 0) / st.aoe.every end
        end
        total = total * (1 - (st.otherHealing or 0))
        local canCast = MD.player.isDruid
        if canCast then startBtn:Enable() else startBtn:Disable() end
        statusFS:SetText(canCast and string.format(
            "|cff888888about %d damage a second for you to heal, over %d:%02d|r", total + 0.5,
            math.floor((st.dur or 0) / 60), (st.dur or 0) % 60)
            or "|cffff9966Practice is Druid-only, like the rest of the healing model.|r")
    end

    -- the bindings window writes db.practiceBinds; this is how the summary hears
    function MD:PracticeBindsChanged() api:Render() end

    pane:SetScript("OnShow", function() api:Render() end)
    return api
end
