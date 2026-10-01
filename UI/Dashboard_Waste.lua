-- The Waste view: where the mana went and where the healing was wasted, from
-- the combat log. Four groupings -- Spell (per event kind), Role, Class,
-- Target -- and two scopes: this session (undecayed, has targets) or all
-- persisted data (decayed, no targets). Exports a constructor on
-- MD.DashboardParts; UI/Dashboard.lua shows it when the "Waste" tab is up.
--
-- Mana belongs to the SPELL, not the target, so Casts / Mana only appear in
-- Spell mode. A role or target that was guessed rather than read carries a
-- marker: the number is still real, its label is not certain.
--
-- T81 (C2 of docs/PLAN-refactor-ux.md, review U5 / A23): each grouping is an
-- `opts` set on UI/Dashboard_Rows.lua's one table, as Review's list is --
-- numbers right-justified in Arial Narrow on 20-px rows, zebra, a rule under
-- the header -- and the list scrolls (the wheel, a thin bar) instead of
-- ending with T53's "... and N more" line. The colours are token reads.
local _, MD = ...
local UI = MD.UI

MD.DashboardParts = MD.DashboardParts or {}

local MODES = { { "spell", "Spell" }, { "role", "Role" }, { "class", "Class" }, { "target", "Target" } }
local LIST_TOP, BOTTOM = 20, 24   -- under the mode buttons; above the total line
local RESET = "|r"
local WARN = "|cffffcc66"         -- overheal between 30% and 45% (no theme token names it)
local LIFE_TAP = "|cff9482c9"     -- the warlock's class colour

-- column sets per mode, in the table's shape; numbers right-justified, words
-- in the kit's small font (x and w are inside the row)
local function Num(key, x, w, label)
    return { key = key, x = x, w = w, label = label, justify = "RIGHT" }
end
local function Word(key, x, w, label)
    return { key = key, x = x, w = w, label = label, font = UI.FONT_SMALL }
end
local function Cols(rowW)
    return {
        spell = {
            Word("label", 8, 150, "Spell"),       Word("sub", 162, 60, ""),
            Num("casts", 226, 50, "Casts"),        Num("mana", 280, 60, "Mana"),
            Num("healed", 344, 70, "Healing"),     Num("frac", 418, 64, "Overheal"),
            Num("waste", 486, 84, "Wasted mana"),  Num("wev", 574, 100, "Fully wasted"),
        },
        role = {
            Word("label", 8, 110, "Role"),         Num("healed", 122, 80, "Healing"),
            Num("frac", 206, 64, "Overheal"),      Num("waste", 274, 84, "Wasted mana"),
            Num("wev", 362, 100, "Fully wasted"),  Word("sub", 474, rowW - 478, "Targets"),
        },
        class = {
            Word("label", 8, 110, "Class"),        Num("healed", 122, 80, "Healing"),
            Num("frac", 206, 64, "Overheal"),      Num("waste", 274, 84, "Wasted mana"),
            Num("wev", 362, 100, "Fully wasted"),  Word("sub", 474, rowW - 478, ""),
        },
        target = {
            Word("label", 8, 120, "Target"),       Word("sub", 132, 110, "Class"),
            Word("role", 246, 90, "Role"),         Num("healed", 340, 80, "Healing"),
            Num("frac", 424, 64, "Overheal"),      Num("waste", 492, 84, "Wasted mana"),
            Num("wev", 580, 100, "Fully wasted"),
        },
    }
end

local function Pct(f) return string.format("%.1f%%", f * 100) end
-- MD.Util.K (Core.lua; T60, P16, review A9) with this view's own threshold:
-- "12.3k" only from 10000 on, below it the rounded whole number. Every amount
-- here (mana, healing, waste) is a sum of non-negative events.
local K_FROM = 10000
local function K(n) return MD.Util.K(n, K_FROM) end
local function Tone(token, text) return UI.Hex(token) .. text .. RESET end

function MD.DashboardParts.CreateWaste(parent, width)
    local pane = CreateFrame("Frame", nil, parent)
    pane:Hide()
    local mode, scope = "spell", "session"
    local api = { frame = pane }
    local rowW = width - 72          -- the scroll bar sits just right of the rows
    local rowH = UI.Pitch and UI.Pitch(20) or 20
    local headH = UI.Pitch and UI.Pitch(22) or 22
    local COLS = Cols(rowW)

    -- controls: by-mode group on the left, scope group on the right
    local byLabel = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    byLabel:SetPoint("TOPLEFT", pane, "TOPLEFT", 12, -2)
    byLabel:SetTextColor(UI.RGB("label"))
    byLabel:SetText("by:")
    local modeBtns, prev = {}, nil
    for _, def in ipairs(MODES) do
        local b = UI.CreateButton(pane, def[2], "accent-hover", { 56, 16 }, false, false, UI.FONT_SMALL, nil)
        b.id = def[1]
        if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0) else b:SetPoint("LEFT", byLabel, "RIGHT", 6, 0) end
        modeBtns[#modeBtns + 1] = b
        prev = b
    end
    local highlightMode = UI.CreateButtonGroup(modeBtns, function(id) mode = id; api:Render() end)

    local scopeLabel = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    scopeLabel:SetTextColor(UI.RGB("label"))
    scopeLabel:SetText("scope:")
    local sessionBtn = UI.CreateButton(pane, "session", "accent-hover", { 60, 16 }, false, false, UI.FONT_SMALL, nil,
        "This login", "Undecayed; the only scope with per-target rows.")
    local allBtn = UI.CreateButton(pane, "all", "accent-hover", { 40, 16 }, false, false, UI.FONT_SMALL, nil,
        "Everything recorded on this character", "Decays with a 150-event half-life so old content fades out.", "No per-target rows: those are never saved.")
    sessionBtn.id, allBtn.id = "session", "all"
    allBtn:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -12, -2)
    sessionBtn:SetPoint("RIGHT", allBtn, "LEFT", 1, 0)
    scopeLabel:SetPoint("RIGHT", sessionBtn, "LEFT", -6, 0)
    local highlightScope = UI.CreateButtonGroup({ sessionBtn, allBtn }, function(id) scope = id; api:Render() end)

    local totalFS = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    totalFS:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 12, 4)
    totalFS:SetJustifyH("LEFT")
    totalFS:SetWidth(width - 60)

    local emptyFS = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    emptyFS:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, -(LIST_TOP + 4 + headH + 4))
    emptyFS:SetJustifyH("LEFT")
    emptyFS:SetTextColor(UI.RGB("muted"))

    -- One table per grouping (a table's columns are fixed when it is built),
    -- built on first sight; the others are hidden.
    local tables = {}
    local function RenderRow(row, r)
        for key, fs in pairs(row.cells) do fs:SetText(r.cells[key] or "") end
    end
    local function TableFor(m)
        local t = tables[m]
        if t then return t end
        t = MD.DashboardParts.CreateTable(pane, width, {
            cols = COLS[m], font = UI.FONT_NUM_SMALL or UI.FONT_SMALL, wideFont = UI.FONT_SMALL,
            rowHeight = rowH, headerHeight = headH, headerRule = true,
            zebra = true, rowWidth = rowW, scroll = true,
            render = RenderRow,
        })
        t.frame:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -LIST_TOP)
        t.frame:SetWidth(width)
        tables[m] = t
        return t
    end

    function api:Release()
        for _, t in pairs(tables) do t:Release() end
    end

    -- casts + mana per family this session, for Spell mode
    local function FamilySpend()
        local out = {}
        local ST = MD.Spend
        if ST and ST.session then
            for fam, v in pairs(ST.session) do out[fam] = v end
        end
        return out
    end

    -- One row's cells, as the old pane painted them (token colours).
    local function Cells(r, spend, shownFam, OH)
        local c = r.guessed and "text2" or "text"
        local out = {}
        out.label = Tone(c, r.label)
        out.sub = Tone("muted", r.sub or "")
        if mode == "spell" then
            local id = r.key:match("^k:(%d+):")
            local s = id and MD.SpellData.spells[tonumber(id)]
            local fam = s and s.family
            -- casts / mana belong to the spell as a whole: show them on the
            -- first event-kind row of each family only
            if fam and spend and spend[fam] and not shownFam[fam] then
                shownFam[fam] = true
                out.casts = Tone(c, tostring(spend[fam].casts))
                out.mana = Tone(c, K(spend[fam].mana))
            else
                out.casts = Tone("disabled", "-")
                out.mana = Tone("disabled", "-")
            end
        end
        if mode == "target" then
            local st = OH.session[r.key]
            out.role = Tone(c, (st and st.role or "?") .. (r.guessed and " ?" or ""))
            local guid = r.key:match("^u:(.+)$")
            local taps = MD.Targets and MD.Targets:LifeTaps(guid) or 0
            if taps > 0 then
                -- overheal on a tapping warlock is partly the HoT doing its job
                out.sub = Tone("muted", r.sub or "") .. " " .. LIFE_TAP .. "Life Tap x" .. taps .. RESET
            end
        end
        out.healed = Tone(c, K(r.healed + r.overhealed))
        local fc = r.frac >= 0.45 and UI.Hex("bad") or r.frac >= 0.30 and WARN or UI.Hex("good")
        out.frac = fc .. Pct(r.frac) .. RESET
        out.waste = Tone(c, r.wastedMana > 0 and K(r.wastedMana) or "-")
        out.wev = Tone("muted", r.wastedEvents > 0 and (r.wastedEvents .. " events") or "-")
        if mode ~= "spell" and mode ~= "target" then
            -- who is in this bucket (session only)
            local names = {}
            if scope == "session" then
                for _, t in ipairs(OH:TargetRows()) do
                    local st = OH.session[t.key]
                    if st and ((mode == "role" and st.role == r.label) or (mode == "class" and st.class == r.label)) then
                        names[#names + 1] = st.name
                    end
                end
            end
            out.sub = Tone("muted", table.concat(names, ", "))
        end
        return out
    end

    function api:Render()
        if not pane:IsShown() then return end
        highlightMode(mode); highlightScope(scope)
        local OH = MD.Overheal
        local rows
        if mode == "spell" then rows = OH:SpellRows(scope)
        elseif mode == "role" then rows = OH:RoleRows(scope)
        elseif mode == "class" then rows = OH:ClassRows(scope)
        else rows = OH:TargetRows() end

        for m, t in pairs(tables) do
            if m ~= mode then t:Release(); t.frame:Hide() end
        end
        local t = TableFor(mode)
        t.frame:Show()
        -- the list's height from the pane's (a size per group, decision 6)
        local listH = math.max(80, pane:GetHeight() - LIST_TOP - BOTTOM)
        t.frame:SetHeight(listH)
        t:SetVisibleRows(math.max(3, math.floor((listH - 4 - headH) / rowH)))

        local spend = mode == "spell" and FamilySpend() or nil
        local shownFam = {}
        local list = {}
        for i, r in ipairs(rows) do
            list[i] = { id = r.key, cells = Cells(r, spend, shownFam, OH) }
        end
        if t.lastMode ~= mode or t.lastScope ~= scope then
            t:ScrollTo(0)
            t.lastMode, t.lastScope = mode, scope
        end
        t:Render(list)

        emptyFS:SetText(#rows == 0 and ("No heals recorded" .. (scope == "session" and " this session" or "") ..
            " yet - heal something.") or "")

        local wm, we = OH:WastedTotal()
        local spent = MD.Spend and MD.Spend.sessionSpent or 0
        if spent > 0 then
            totalFS:SetFormattedText("%s%s spent this session, ~%s (%d%%) into targets at full health across %d events.  " ..
                "Grey label / ? = role guessed, not read.|r", UI.Hex("muted"), K(spent), K(wm), wm / spent * 100, we)
        else
            totalFS:SetText("")
        end
    end

    return api
end
