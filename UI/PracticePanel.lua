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

-- T40 (docs/SPEC-forever-ui.md 4.4, 6.4, 6.7): under the flat theme
-- (UI.THEMED since T69/P25, set by UI/Theme_Flat.lua -- on every main TOC
-- since T80 / C1; colours are token reads) the panel drops Blizzard gold (the
-- role rows in text2, the key labels in the accent), shows "you" as a small
-- accent tag after the name, wraps the fight fields onto a second row when
-- the pane is narrower than them (the Simulate group goes down to 900 wide),
-- sizes its table to the pane, and folds the bindings list into one summary
-- line with the list in its hover. "Edit bindings" opens the bindings SHEET
-- on this pane (UI/BindingsWindow.lua; T80: on both lines, the window manager
-- being on every main TOC). Without the theme (a suite that loads the kit
-- alone) the panel is built as TBC's was before C1.
-- a tooltip's first line takes the client's gold unless it is coloured: the
-- accent under the theme, the text unchanged on TBC
local function Title(text)
    if UI.THEMED then return UI.Hex("accent") .. text .. "|r" end
    return text
end

-- T40: every practice pane built, so /st binds can find the one inside the
-- host window (the sheet sits on it; T80: MD.Win.host, the window manager's)
local hosts = setmetatable({}, { __mode = "k" })
function MD.DashboardParts.PracticeHost()
    local w = MD.Win.host
    local main = w and w.frame
    if not main then return nil end
    for pane in pairs(hosts) do
        local f, guard = pane, 0
        while f and guard < 50 do
            if f == main then return pane end
            f, guard = f:GetParent(), guard + 1
        end
    end
    return nil
end
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
    if tip then UI.SetTooltips(eb, "ANCHOR_TOP", 0, 2, Title(tip)) end
    return eb
end

function MD.DashboardParts.CreatePractice(parent, width)
    local PR = MD.Practice
    local pane = CreateFrame("Frame", nil, parent)
    pane:Hide()
    local api = { frame = pane }
    local themed = UI.THEMED                       -- T40: the Forever theme (T69: the flag)
    local GREY = UI.Hex("muted")                   -- T69: 888888 on TBC, the theme's muted on Forever
    hosts[pane] = true

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
        "answers it. " .. GREY .. "Every default number here is a placeholder - one healer's guess at a TBC " ..
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
    local fightItems = {}      -- T40: laid out by Layout under the theme
    api.fightFrames = {}       -- T40: every frame of the fight row (tools/practiceforever.lua)
    for _, d in ipairs(line2) do
        local fs, eb = FightField(d[1], d[2], d[3], d[4], d[5], d[6])
        if themed then
            fightItems[#fightItems + 1] = { lead = fs, fs = fs, ebW = d[2] }
        elseif anchor then fs:SetPoint("LEFT", anchor, "RIGHT", 14, 0)
        else fs:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -72) end
        eb:SetPoint("LEFT", fs, "RIGHT", 4, 0)
        anchor = eb
        api.fightFrames[#api.fightFrames + 1] = fs
        api.fightFrames[#api.fightFrames + 1] = eb
    end

    local seedCB, seedEB
    seedCB = UI.CreateCheckButton(pane, "Same fight again", function(checked)
        Setup().fixedSeed = checked and (Setup().fixedSeed or (time and time()) or 1) or nil
        api:Render()
    end, Title("Same fight again"), "On: the damage comes out identical every time, so you can",
        "replay a fight you lost. Off: a new roll of the dice each Start.")
    if themed then
        fightItems[#fightItems + 1] = { lead = seedCB, cb = seedCB, gap = 16 }
    else
        seedCB:SetPoint("LEFT", anchor, "RIGHT", 16, 0)
    end
    seedEB = Field(pane, 80, function() return Setup().fixedSeed end,
        function(v) Setup().fixedSeed = math.max(1, math.floor(v)) end, "int", "The seed: the same number is the same fight.")
    seedEB:SetPoint("LEFT", seedCB.label, "RIGHT", 6, 0)
    api.fightFrames[#api.fightFrames + 1] = seedCB
    api.fightFrames[#api.fightFrames + 1] = seedCB.label
    api.fightFrames[#api.fightFrames + 1] = seedEB

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
            fs:SetText(GREY .. c[2] .. "|r")
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
                fs:SetText(UI.Hex("note") .. "every "
                    .. PR.ROLES[kind].label:lower() .. "|r") -- T40/T69: "note", gold on TBC, text2 themed
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
                if themed and key == "name" then
                    -- T40: "you" as a small accent tag after the name
                    row.nameEB = eb
                    row.youFS = eb:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
                    row.youFS:SetPoint("RIGHT", eb, "RIGHT", -5, 0)
                    row.youFS:SetText(UI.Hex("accent") .. "you|r")
                    row.youFS:Hide()
                end
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
                if c[5] then UI.SetTooltips(eb, "ANCHOR_TOP", 0, 2, Title(c[2]), c[5]) end
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
    local bindTitle, bindFS, summary
    if themed then
        -- T40: one line beside the group buttons, "6 bindings  [Edit bindings]",
        -- the list in its hover; only what practice would cast is counted
        summary = CreateFrame("Frame", nil, pane)
        summary:SetSize(60, 20)
        summary:SetPoint("LEFT", groupBtns[#groupBtns], "RIGHT", 20, 0)
        summary:EnableMouse(true)
        summary.fs = summary:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        summary.fs:SetPoint("LEFT", summary, "LEFT", 0, 0)
        summary.fs:SetJustifyH("LEFT")
        api.summary = summary
    else
        local BIND_X = TABLE_W + 30
        bindTitle = pane:CreateFontString(nil, "OVERLAY", UI.FONT)
        bindTitle:SetPoint("TOPLEFT", pane, "TOPLEFT", BIND_X, tableTop)
        bindTitle:SetText("What your presses cast")
        bindFS = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        bindFS:SetPoint("TOPLEFT", bindTitle, "BOTTOMLEFT", 0, -6)
        bindFS:SetWidth(width - BIND_X - 10)
        bindFS:SetJustifyH("LEFT")
        bindFS:SetJustifyV("TOP")
    end

    local bindBtn = UI.CreateButton(pane, "Edit bindings", "accent-hover", { 110, 20 }, false, false,
        UI.FONT_SMALL, nil, Title("Practice bindings"), "Set what each key and mouse button casts,",
        "or import them from Cell or Clique.")
    -- T40: the sheet on this pane (6.4); T80 (C1): on both lines
    bindBtn:SetScript("OnClick", function()
        if MD.ShowBindings then MD:ShowBindings(pane) end
    end)
    if summary then bindBtn:SetPoint("LEFT", summary.fs, "RIGHT", 8, 0) end

    local function BindLines()
        PR.EnsureKit()
        local SD = MD.SpellData
        local out = {}
        for _, b in ipairs(PR.Binds()) do
            local id = PR.SpellFor(b)
            local label = b.family and ((SD.families[b.family] and SD.families[b.family].label) or b.family)
                or "no spell picked"
            if b.rank and id and SD.spells[id].rank == b.rank then label = label .. " " .. b.rank end
            local note = ""
            if not id and b.family then
                if PR.InBook(b) then note = "  |cffff9966(not trained)|r"
                else note = "  |cffff9966(not in your spellbook)|r" end
            end
            out[#out + 1] = string.format("|cffffcc00%s|r  %s%s",
                b.key ~= "" and b.key or "unbound", label, note)
        end
        if #out == 0 then
            return "|cffff9966Nothing is bound - Import your keybindings, Cell or Clique, or add one, in Edit bindings.|r"
        end
        out[#out + 1] = "|cff888888Hover a frame and press. Import from Cell or Clique in the bindings window.|r"
        return table.concat(out, "\n")
    end

    -- T40: the summary line and its hover (the theme only)
    local function RenderSummary()
        PR.EnsureKit()
        local SD = MD.SpellData
        local binds = PR.Binds()
        local accent, white = UI.Hex("accent"), UI.Hex("text")
        local tips = { Title("What your presses cast") }
        if #binds == 0 then
            summary.fs:SetText("|cffff9966Nothing is bound|r")
            tips[#tips + 1] = "Nothing is bound - Import your keybindings, Cell or Clique, or add one, in Edit bindings."
        else
            summary.fs:SetText(string.format("%d %s", #binds, #binds == 1 and "binding" or "bindings"))
            for _, b in ipairs(binds) do
                local id = PR.SpellFor(b)
                local label = b.family and ((SD.families[b.family] and SD.families[b.family].label) or b.family)
                    or "no spell picked"
                if b.rank and id and SD.spells[id].rank == b.rank then label = label .. " " .. b.rank end
                local note = ""
                if not id and b.family then
                    if PR.InBook(b) then note = "  |cffff9966(not trained)|r"
                    else note = "  |cffff9966(not in your spellbook)|r" end
                end
                -- the label coloured on its own: after a |r a tooltip line
                -- falls back to its default colour, not to white
                tips[#tips + 1] = accent .. (b.key ~= "" and b.key or "unbound") .. "|r  " .. white .. label .. "|r" .. note
            end
            tips[#tips + 1] = GREY .. "Hover a frame and press. Import from Cell or Clique in Edit bindings.|r"
        end
        summary:SetWidth(math.max(20, summary.fs:GetStringWidth() + 2))
        UI.SetTooltips(summary, "ANCHOR_BOTTOMLEFT", 0, -3, unpack(tips))
    end

    ----------------------------------------------------------------------------
    -- start
    ----------------------------------------------------------------------------
    local startBtn = UI.CreateButton(pane, "Start practice", "accent", { 160, 26 }, false, false, nil, nil,
        Title("Start practice"), "Opens the fight. Hover a frame and press a binding;",
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
        if #PR.Binds() == 0 then
            statusFS:SetText("|cffff9966Nothing is bound yet - import your bindings or add one in Edit bindings first.|r")
            return
        end
        if PR.policy.kitIsLive and not PR.FirstFamily() then
            statusFS:SetText("|cffff9966No healing spell in your spellbook for practice to cast.|r")
            return
        end
        if MD.OpenPractice then MD:OpenPractice(PR.CopySetup(st), st.fixedSeed) end
    end)

    ----------------------------------------------------------------------------
    -- T40: the layout that follows the pane's width (the theme only). The
    -- fight fields flow left to right and wrap onto a new row when the next
    -- one would pass the pane's right edge; the table moves down by the rows
    -- added, and its scroll area takes the height left above Start. The TBC
    -- panel keeps its fixed one-row layout.
    ----------------------------------------------------------------------------
    local FIELD_MID, FIELD_ROW = -78, 24   -- the first row's middle; a row's pitch
    local function ItemWidth(it)
        if it.cb then
            -- the box, its label, the seed field beside it (shown or not)
            return 14 + 5 + it.cb.label:GetStringWidth() + 6 + 80
        end
        return it.fs:GetStringWidth() + 4 + it.ebW
    end
    local function Layout()
        if not themed then return end
        local w = pane:GetWidth()
        if type(w) ~= "number" or w <= 0 then w = width end
        local right = w - 4
        local x, line = 4, 0
        for i, it in ipairs(fightItems) do
            local iw = ItemWidth(it)
            local gap = (i == 1) and 0 or (it.gap or 14)
            if i > 1 and x + gap + iw > right then
                line, x, gap = line + 1, 4, 0
            end
            x = x + gap
            it.lead:ClearAllPoints()
            it.lead:SetPoint("LEFT", pane, "TOPLEFT", x, FIELD_MID - line * FIELD_ROW)
            x = x + iw
        end
        local down = line * FIELD_ROW
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, tableTop - down)
        intro:SetWidth(w - 20)
        statusFS:SetWidth(math.max(40, w - 4 - 160 - 12 - 8))
        -- the rows' scroll area: down to 8 px above Start (bottom 30, 26 tall)
        local h = pane:GetHeight()
        local top = -tableTop + down + ROW_H + 2 + #PR.ROLE_ORDER * ROW_H + 6
        local sh = 250
        if type(h) == "number" and h > top + 64 + 3 * ROW_H then sh = h - top - 64 end
        scroll:SetSize(TABLE_W + 4, sh)
    end
    if themed then pane:SetScript("OnSizeChanged", function() Layout() end) end

    function api:Render()
        if not pane:IsShown() then return end
        Layout() -- T40: nothing on TBC
        -- T27: a spell learned since the last paint brings back a binding that
        -- was hidden for it (Forever only; nothing on TBC)
        PR.RefreshKit()
        local st = Setup()
        highlightGroup(st.group)
        for _, eb in ipairs(fightFields) do eb:Refresh() end
        seedCB:SetChecked(st.fixedSeed ~= nil)
        if st.fixedSeed then seedEB:Show(); seedEB:Refresh() else seedEB:Hide() end
        for _, row in ipairs(roleRows) do for _, eb in ipairs(row.fields) do eb:Refresh() end end

        for i, tg in ipairs(st.targets) do
            local row = Row(i)
            row.index = i
            if row.youFS then
                -- T40: the role alone in its cell, "you" a tag after the name
                row.kindFS:SetText(GREY .. PR.ROLES[tg.kind].label:lower() .. "|r")
                if tg.you then row.youFS:Show() else row.youFS:Hide() end
                row.nameEB:SetTextInsets(5, tg.you and 30 or 5, 0, 0)
            else
                row.kindFS:SetText((tg.you and "|cff99dd99you|r " or "") .. "|cff888888" ..
                    PR.ROLES[tg.kind].label:lower() .. "|r")
            end
            for _, eb in ipairs(row.fields) do
                if eb.how == "text" then eb:SetText(tg[eb.key] or "") else eb:SetText(Fmt(tg[eb.key], eb.how)) end
            end
            row:Show()
        end
        for i = #st.targets + 1, #rows do rows[i]:Hide() end
        scroll:SetContentHeight(math.max(1, #st.targets) * ROW_H)

        if summary then
            RenderSummary()
        else
            bindFS:SetText(BindLines())
            bindBtn:ClearAllPoints()
            bindBtn:SetPoint("TOPLEFT", bindFS, "BOTTOMLEFT", 0, -8 - 12 * #PR.Binds())
        end

        local total = 0
        for _, tg in ipairs(st.targets) do
            total = total + (tg.dps or 0) * (tg.maxHP or 0)
            if (tg.spikeEvery or 0) > 0 then total = total + (tg.spike or 0) * (tg.maxHP or 0) / tg.spikeEvery end
            if st.aoe and (st.aoe.every or 0) > 0 then total = total + (st.aoe.size or 0) * (tg.maxHP or 0) / st.aoe.every end
        end
        total = total * (1 - (st.otherHealing or 0))
        -- T99 (docs/SPEC-next.md 4.4): the class profile's practice capability
        local canCast, why = MD.ClassProfile:Can("practice")
        if canCast then startBtn:Enable() else startBtn:Disable() end
        statusFS:SetText(canCast and string.format(
            GREY .. "about %d damage a second for you to heal, over %d:%02d|r", total + 0.5,
            math.floor((st.dur or 0) / 60), (st.dur or 0) % 60)
            or ("|cffff9966" .. MD.Profiles.Refusal("practice", why, "Practice") .. "|r"))
    end

    -- the bindings window writes db.practiceBinds; this is how the summary hears
    function MD:PracticeBindsChanged() api:Render() end

    pane:SetScript("OnShow", function() api:Render() end)
    return api
end
