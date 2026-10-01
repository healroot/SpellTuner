-- The Review tab (docs/SPEC-v0.7.md 8): the fights this character recorded, what
-- the engine can and cannot reproduce about each, and -- for the ones it can --
-- what a better plan would have done.
--
-- The validate column is the point of the tab. A fight the engine cannot
-- reproduce is shown greyed with the number that failed, and its Coach button
-- is disabled with the reason on it. Nothing is hidden and nothing is guessed:
-- if the model cannot replay a pull, saying so is more useful than a card.
--
-- v0.9.2: the tab lists two kinds of thing. [Fights] is the ring of 8 single
-- recordings; one button per stored RUN lists that run's pulls in order, the
-- ones under the recording gate included -- greyed, with Coach disabled,
-- because a dungeon is mostly those and hiding them would misrepresent the run.
-- Every button (Validate / Coach / Play) addresses a pull as "run:pull", which
-- is the same address the slash commands take (/md replay 2:7).
--
-- Class-agnostic for listing (the stream is just numbers); Coach needs the
-- druid spell kit.
local _, MD = ...
local UI = MD.UI

MD.DashboardParts = MD.DashboardParts or {}

-- T43 (docs/SPEC-forever-ui.md 4.1, 4.4): under the Forever theme the pane's
-- small text is the kit's UI.FONT_SMALL and the run line the accent; TBC keeps
-- GameFontHighlightSmall and gold. T69 (P25): the font asks UI.THEMED (set by
-- UI/Theme_Forever.lua, before any module file); the colour is a token read,
-- TBC's accent token being that gold.
local SMALL  = UI.THEMED and UI.FONT_SMALL or "GameFontHighlightSmall"
local RUN_HI = UI.Hex("accent")

local ROW_HEIGHT = 16
local COLS = {
    { "n",      0,   22,  "#" },
    { "when",   22,  110, "when" },
    { "zone",   132, 150, "zone" },
    { "dur",    282, 46,  "dur" },
    { "tgts",   328, 40,  "tgts" },
    { "casts",  368, 48,  "casts" },
    { "spent",  416, 56,  "spent" },
    { "low",    472, 66,  "low mana" },
    { "valid",  538, 190, "validate" },
}

-- T16c, lead review (2026-09-28), correcting T16b: a zone name, a gate's own
-- text (which can embed a target name, T14) and a roster name come straight
-- from the client and paint in the game's own font for that name -- an
-- EU-realm accented byte is not ours to mangle. Only a bare "|" is unsafe
-- (the client reads it as the start of a colour code or texture escape);
-- everything this pane composes itself is ASCII by construction, so nothing
-- else needs escaping, on either client. That rule is MD.Text.Esc (pipe-
-- doubling only), and the formatters are MD.Util's (Core.lua; T60, P16,
-- review A9): K is "2.3k" from 1000 on, Clock is m:ss -- every number handed
-- to either here is a mana sum or a duration, never below zero.
local Esc   = MD.Text.Esc
local K     = MD.Util.K
local Clock = MD.Util.Clock

-- The fight's mana low-water mark, read back out of the recorded samples: the
-- stream is the record, so nothing needs to be stored twice.
local function LowestMana(rec)
    local pool = rec.pool or 0
    if pool <= 0 then return 0 end
    local low = nil
    for _, v in ipairs(rec.mana and rec.mana.v or {}) do
        if not low or v < low then low = v end
    end
    return (low or pool) / pool
end

-- T53 (P9, review U25): which rows of a list fit, and what the last slot says
-- when they do not all fit. `top` is the first row's y, `floor` the lowest y a
-- row may start at (the loop's old `break` condition, unchanged), so the
-- number of slots is exactly the number of rows painted before. When the
-- list is longer, the last slot is the tail line and `hidden` counts every
-- row not painted; the window starts at the selected row when the selection
-- would fall below it, backed up so the slots stay full at the list's end.
-- No slot at all (a pane with no height yet) paints nothing, as before.
local function ListWindow(n, top, floor, selected)
    local slots = 0
    if top >= floor then slots = math.floor((top - floor) / ROW_HEIGHT) + 1 end
    if n <= slots then return 1, n, 0 end
    if slots == 0 then return 1, 0, 0 end
    local rows = slots - 1
    local first = 1
    if selected and selected > rows then
        first = math.max(1, math.min(selected, n - rows + 1))
    end
    return first, first + rows - 1, n - rows
end
local function TailText(hidden)
    return string.format("|cff888888... and %d more (scroll: not yet)|r", hidden)
end

local function When(id)
    if not id then return "?" end
    local days = math.floor((time() - id) / 86400)
    local hm = date and date("%H:%M", id) or "?"
    if days <= 0 then return "today " .. hm end
    if days == 1 then return "yesterday " .. hm end
    return (date and date("%d %b %H:%M", id)) or hm
end

function MD.DashboardParts.CreateReview(parent, width)
    local pane = CreateFrame("Frame", nil, parent)
    pane:Hide()
    local rowPool, usedRows = {}, {}
    local selected = 1
    local source = "fights"   -- "fights" or "run1" / "run2": which list is shown
    local cache = {}     -- recording id -> validation result (validating is not cheap)
    local api = { frame = pane }

    -- Which run is shown, if any, and the list of rows to draw.
    local function RunIndex()
        return tonumber(source:match("^run(%d+)$"))
    end
    local function CurrentRun()
        local i = RunIndex()
        return i and MD.RunRecorder and MD.RunRecorder:Get(i) or nil
    end
    -- v0.15.0: practice fights (Engine/Practice.lua), kept apart from real ones
    local function IsPractice() return source == "practice" end
    local function Rows()
        local run = CurrentRun()
        if run then return run.pulls or {} end
        if IsPractice() then return MD.Practice and MD.Practice.List() or {} end
        return MD.FightRecorder and MD.FightRecorder:List() or {}
    end
    -- The address the commands take: "3" for a single fight, "2:7" for a pull.
    local function Spec()
        local i = RunIndex()
        if IsPractice() then return "p" .. selected end
        return i and (i .. ":" .. selected) or tostring(selected)
    end

    local habitsFS = pane:CreateFontString(nil, "OVERLAY", SMALL)
    habitsFS:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 12, 20)
    habitsFS:SetJustifyH("LEFT")
    habitsFS:SetWidth(width - 60)

    local progressFS = pane:CreateFontString(nil, "OVERLAY", SMALL)
    progressFS:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 12, 4)
    progressFS:SetJustifyH("LEFT")
    progressFS:SetWidth(width - 60)

    -- the source selector: [Fights] and one button per stored run. The buttons
    -- are a fixed pool (a run list is at most MAX_RUNS long) relabelled on
    -- render, so a run appearing or being replaced never leaves a dead button.
    local sourceBtns, prevBtn = {}, nil
    for i = 1, 4 do
        local b = UI.CreateButton(pane, i == 1 and "Fights" or i == 4 and "Practice" or "run", "accent-hover",
            { 110, 16 }, false, false, UI.FONT_SMALL, nil)
        b.id = i == 1 and "fights" or i == 4 and "practice" or ("run" .. (i - 1))
        if prevBtn then b:SetPoint("LEFT", prevBtn, "RIGHT", -1, 0)
        else b:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -2) end
        sourceBtns[i] = b
        prevBtn = b
    end
    local highlightSource = UI.CreateButtonGroup(sourceBtns, function(id)
        source = id
        selected = 1
        api:Render()
    end)

    local runFS = pane:CreateFontString(nil, "OVERLAY", SMALL)
    runFS:SetPoint("TOPLEFT", pane, "TOPLEFT", 2, -22)
    runFS:SetJustifyH("LEFT")
    runFS:SetWidth(width - 60)

    local validateBtn = UI.CreateButton(pane, "Validate", "accent-hover", { 72, 18 }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL, "Replay this fight through the engine",
        "Runs the eight gates and shows what matched and what did not.")
    local coachBtn = UI.CreateButton(pane, "Coach", "accent-hover", { 78, 18 }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL)
    -- T71 (P27, section 8.1 item 5): under UI.THEMED the star and the
    -- shift-click go -- forcing is the row menu's "Coach anyway" -- so neither
    -- tooltip mentions them there. TBC keeps both until wave C.
    local THEMED = UI.THEMED
    -- while a run is shown, Coach coaches the run and this coaches one pull
    local pullBtn = UI.CreateButton(pane, "Coach pull", "accent-hover", { 82, 18 }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL, "Coach this one pull",
        "The v0.7 card for the selected pull, inside the run.",
        THEMED and "A pull that does not replay: right-click it for Coach anyway."
            or "A star means the pull does not replay: shift-click to coach it anyway.")
    local pinBtn = UI.CreateButton(pane, "Pin", "accent-hover", { 68, 18 }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL, "Keep this recording",
        "Pinned fights are never replaced (at most two).",
        "While a run is shown this pins the whole run: a run is kept or dropped as one thing.")
    local exportBtn = UI.CreateButton(pane, "Export", "accent-hover", { 60, 18 }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL, "Copy every recording as text", "Same as /md export.")
    local playBtn
    if THEMED then
        playBtn = UI.CreateButton(pane, "Play", "accent-hover", { 48, 18 }, false, false,
            UI.FONT_SMALL, UI.FONT_SMALL, "Play this fight as unit frames",
            "What you did on the left; what Coach suggested on the right.",
            "Double-click a row to play it. A fight coached with Coach anyway",
            "plays with both columns, marked FORCED.")
    else
        playBtn = UI.CreateButton(pane, "Play", "accent-hover", { 48, 18 }, false, false,
            UI.FONT_SMALL, UI.FONT_SMALL, "Play this fight as unit frames",
            "What you did on the left; what Coach suggested on the right.",
            "Press Coach first for the right column. Any class can play the left one.",
            "Shift-click to force the right column onto a fight that does not replay",
            "(coach it first with /md coach N force).")
    end

    local runBtn = UI.CreateButton(pane, "Start run", "accent-hover", { 76, 18 }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL, "Record a whole dungeon",
        "Every pull and the gaps between them - drinking, deaths, the clock.",
        "Same as /md run start; it stops itself 30s after you leave the instance.")
    runBtn:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 12, 40)
    runBtn:SetScript("OnClick", function()
        local RR = MD.RunRecorder
        if not RR then return end
        if RR.active then
            RR:Stop("manual")
        else
            local run, why = RR:Start("manual")
            if not run then MD:Print("run: " .. tostring(why)) end
        end
        api:Render()
    end)

    exportBtn:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -12, 40)
    pinBtn:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
    playBtn:SetPoint("RIGHT", pinBtn, "LEFT", -4, 0)
    coachBtn:SetPoint("RIGHT", playBtn, "LEFT", -4, 0)
    pullBtn:SetPoint("RIGHT", coachBtn, "LEFT", -4, 0)
    validateBtn:SetPoint("RIGHT", pullBtn, "LEFT", -4, 0)

    local function Selected()
        return Rows()[selected]
    end

    -- v0.11.4: the Reports group has a Runs view, which is this pane with a run
    -- selected rather than the ring of single fights. The selector stays: with
    -- two runs kept, choosing between them is still a click.
    function api:SetSource(which)
        if which == "run" then
            if not RunIndex() and MD.RunRecorder and MD.RunRecorder:Get(1) then
                source = "run1"
                selected = 1
            end
        elseif which == "fights" and RunIndex() then
            source = "fights"
            selected = 1
        end
    end


    local function Validation(rec, force)
        if not rec then return nil end
        if cache[rec.id] and not force then return cache[rec.id] end
        if not (MD.SimModel and MD.RankMath) then return nil end
        cache[rec.id] = MD.SimModel:Validate(rec)
        return cache[rec.id]
    end

    validateBtn:SetScript("OnClick", function()
        if THEMED then api:Validate() return end -- T71: into the result area
        local rec = Selected()
        if not rec then return end
        Validation(rec, true)
        for _, line in ipairs(MD:ValidationReport(rec, Spec())) do MD:Print(line) end
        api:Render()
    end)
    -- On a run, Coach coaches the RUN: one plan and a drink policy for the whole
    -- dungeon, scored on time before mana. On a single fight it is v0.7's card.
    --
    -- v0.9.8: shift-click forces, on a fight the gates rejected. The button is
    -- no longer DISABLED for that case -- a disabled button cannot be
    -- shift-clicked, and it says nothing unless you happen to hover it. It is
    -- marked instead, and a plain click still refuses, printing which gate
    -- failed. You cannot get a card from a fight the engine gets wrong by
    -- accident; you can get one on purpose.
    local function Forcing()
        return MD.API.IsShiftKeyDown and MD.API.IsShiftKeyDown() or false
    end
    coachBtn:SetScript("OnClick", function()
        local i = RunIndex()
        if THEMED then -- T71: the card in the result area, one chat line
            if i then api:CoachRun() else api:Coach(false) end
            return
        end
        if i then
            if MD.RunCoachRun then MD:RunCoachRun(tostring(i)) end
        elseif MD.RunCoach then
            MD:RunCoach(Spec() .. (Forcing() and " force" or ""))
        end
    end)
    pullBtn:SetScript("OnClick", function()
        if THEMED then api:Coach(false) return end -- T71
        if MD.RunCoach then MD:RunCoach(Spec() .. (Forcing() and " force" or "")) end
    end)
    -- T49 (P5), B14: a single fight is pinned through the recorder's own capped
    -- Pin (Recorder_Forever.lua's on Forever), which refuses a third with a
    -- reason. TBC's Engine/FightRecorder.lua has no Pin yet (the shared
    -- Engine/Recordings.lua, P18, is where one lands for both lines); until
    -- then the same cap is kept here, at that file's MAX_PINNED, so a pin the
    -- recorder would not honour is refused instead of silently not protecting.
    local PIN_CAP = 2
    local function PinFight(rec, on)
        local FR = MD.FightRecorder
        if not FR then return false, "no recorder" end
        local list = FR:List()
        local n
        for i, r in ipairs(list) do if r == rec then n = i end end
        if not n then return false, "no such recording" end
        if FR.Pin then return FR:Pin(n, on) end
        if on then
            local count = 0
            for _, r in ipairs(list) do
                if r.pinned and r ~= rec then count = count + 1 end
            end
            if count >= PIN_CAP then
                return false, string.format("at most %d fights can be pinned - unpin one first.", PIN_CAP)
            end
        end
        rec.pinned = on and true or false
        return true
    end
    -- Pinning a pull would be meaningless: a run is kept or dropped whole, so
    -- while a run is shown this pins the RUN.
    local function DoPin()
        local run = CurrentRun()
        if run then
            run.pinned = not run.pinned
            api:Render()
            return
        end
        local rec = Selected()
        if not rec then return end
        if IsPractice() and MD.Practice and MD.Practice.Pin then
            -- 2026-09-29: a practice fight a report is about is kept past the
            -- next eight; the pinned ones have a cap of their own
            local ok, why = MD.Practice.Pin(rec)
            if not ok then MD:Print("practice: " .. why) end
        else
            local ok, why = PinFight(rec, not rec.pinned)
            if not ok then MD:Print("pin: " .. Esc(why or "refused")) end
        end
        api:Render()
    end
    pinBtn:SetScript("OnClick", DoPin)
    exportBtn:SetScript("OnClick", function() if MD.RunExport then MD:RunExport() end end)
    -- runtime lookup: UI/ReplayWindow.lua loads after this file
    -- on a run with no pull selected yet, Play opens its first pull with the
    -- run strip; the strip is the map from there. Shift-click forces the
    -- suggested column onto a fight the gates rejected -- it needs a plan, so
    -- /md coach N force has to have run first (v0.9.6).
    playBtn:SetScript("OnClick", function()
        if not MD.Replay then return end
        if THEMED then MD.Replay:Open(Spec()) return end -- T71: no shift-click
        local shift = MD.API.IsShiftKeyDown and MD.API.IsShiftKeyDown()
        MD.Replay:Open(Spec() .. (shift and " force" or ""))
    end)

    local function AcquireRow()
        local row = table.remove(rowPool)
        if not row then
            row = CreateFrame("Button", nil, pane)
            row:SetSize(width - 60, ROW_HEIGHT)
            row.cells = {}
            for _, col in ipairs(COLS) do
                local fs = row:CreateFontString(nil, "OVERLAY", SMALL)
                fs:SetJustifyH("LEFT")
                fs:SetPoint("LEFT", row, "LEFT", col[2], 0)
                fs:SetWidth(col[3])
                row.cells[col[1]] = fs
            end
            row.highlight = row:CreateTexture(nil, "BACKGROUND")
            row.highlight:SetAllPoints()
            row.highlight:SetColorTexture(1, 1, 1, 0.06)
            row.highlight:Hide()
        end
        -- a pooled row still carries the last render's text in every cell it is
        -- not given this time. The empty-state row sets only `when`, and the
        -- header's other columns showed through underneath it (v0.11.6).
        for _, col in ipairs(COLS) do
            row.cells[col[1]]:SetText("")
            row.cells[col[1]]:SetWidth(col[3])
        end
        row.highlight:Hide()
        row:EnableMouse(true)
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row:Show()
        usedRows[#usedRows + 1] = row
        return row
    end

    function api:Release()
        for _, row in ipairs(usedRows) do row:Hide(); rowPool[#rowPool + 1] = row end
        wipe(usedRows)
    end

    -- The one line that says whether a fight is usable, and why not when it is
    -- not. The first failing gate wins: a healer does not need five reasons.
    local function ValidateCell(v)
        if not v then return "|cff888888not checked|r", false end
        if v.ok then return "|cff99dd99ok|r", true end
        for _, g in ipairs(v.gates) do
            if not g.ok then
                local short = g.text:match("^([^%(]+)")
                return "|cffff9966" .. g.name .. ": " .. Esc((short or g.text):gsub("%s+$", "")) .. "|r", false
            end
        end
        return "|cffff9966failed|r", false
    end

    -- Habits: the same labels the summaries have carried since v0.7.0, summed
    -- over every recorded fight. `ok` is never a habit.
    local function Habits()
        local mana, casts = {}, {}
        local n = 0
        for _, f in ipairs(MD.fightHistory or {}) do
            if f.labels then
                n = n + 1
                for k, v in pairs(f.labels) do
                    if k ~= "ok" then
                        mana[k] = (mana[k] or 0) + v
                        casts[k] = (casts[k] or 0) + ((f.labelCasts and f.labelCasts[k]) or 0)
                    end
                end
            end
        end
        if n == 0 then return nil end
        local list = {}
        for k, v in pairs(mana) do if v > 0 then list[#list + 1] = { k, v } end end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        local parts = {}
        for i = 1, math.min(3, #list) do
            parts[#parts + 1] = string.format("%s %d casts %s", list[i][1], casts[list[i][1]] or 0, K(list[i][2]))
        end
        if #parts == 0 then return nil end
        return string.format("Habits over the last %d fights:  %s", n, table.concat(parts, "   "))
    end

    ----------------------------------------------------------------------------
    -- T71 (P27, review U20 / U22 / U25 / U17; docs/mockups/refactor-ux.html
    -- M2). Under UI.THEMED only -- TBC's pane above and below is untouched
    -- until wave C:
    --   * the list is the generic table (UI/Dashboard_Rows.lua) with T30's
    --     options, scrolled (the wheel, a thin bar) -- no tail line;
    --   * a RESULT area under it shows the last validation or coach card as
    --     lines, and the coach's progress while it searches; chat gets one line;
    --   * a double-click plays the row; a right-click opens the row menu (Play,
    --     Validate, Coach, Coach anyway, Pin, Export -- UI/ContextMenu.lua);
    --   * the Result cell reads the gates' own `short` (SM.NewValidation), not
    --     their prose.
    ----------------------------------------------------------------------------
    local T = { result = nil }   -- the themed pieces, built below when THEMED
    local LIST_TOP, BOTTOM = 38, 64
    local function Tone(token, text) return UI.Hex(token) .. text .. "|r" end

    -- "fight 3", "pull 7", "practice fight 2": what the result and chat call
    -- the selected row.
    local function Label(i)
        if IsPractice() then return "practice fight " .. i end
        if RunIndex() then return "pull " .. i end
        return "fight " .. i
    end
    local function FirstFailed(v)
        for _, g in ipairs(v and v.gates or {}) do if not g.ok then return g end end
        return nil
    end

    -- A line longer than the area is cut into rows at word boundaries
    -- (the rows are one height; a font string set not to wrap would clip it).
    local function Wrap(text, chars)
        local out = {}
        local lead = text:match("^(%s*)") or ""
        local rest = text
        while #rest > chars do
            local cut = rest:sub(1, chars):match("^.*()%s") or chars + 1
            if cut <= #lead + 1 then cut = chars + 1 end
            out[#out + 1] = rest:sub(1, cut - 1)
            rest = lead .. "  " .. rest:sub(cut):gsub("^%s+", "")
        end
        out[#out + 1] = rest
        return out
    end

    if THEMED then
        local font = UI.FONT_NUM_SMALL or UI.FONT_SMALL
        local rowH = UI.Pitch and UI.Pitch(20) or 20
        local headH = UI.Pitch and UI.Pitch(22) or 22
        local rowW = width - 72
        T.rowW = rowW
        local LIST_COLS = {
            { key = "n",     x = 6,   w = 26,  label = "#",        justify = "RIGHT" },
            { key = "when",  x = 44,  w = 120, label = "When",     font = UI.FONT_SMALL },
            { key = "zone",  x = 168, w = 168, label = "Zone",     font = UI.FONT_SMALL },
            { key = "dur",   x = 340, w = 50,  label = "Length",   justify = "RIGHT" },
            { key = "tgts",  x = 394, w = 52,  label = "Targets",  justify = "RIGHT" },
            { key = "casts", x = 450, w = 46,  label = "Casts",    justify = "RIGHT" },
            { key = "spent", x = 500, w = 54,  label = "Spent",    justify = "RIGHT" },
            { key = "low",   x = 558, w = 70,  label = "Low mana", justify = "RIGHT" },
            { key = "valid", x = 646, w = rowW - 650, label = "Result", font = UI.FONT_SMALL },
        }
        T.header = {}
        local function RenderListRow(row, r)
            for _, col in ipairs(LIST_COLS) do
                local key = col.key
                local tone = (key == "valid") and r.resultTone or r.tone
                row.cells[key]:SetText(Tone(tone, r.cells[key] or ""))
            end
        end
        local function ListEnter(row, r)
            local tip = MD.Tip
            if not (tip and r and r.rec) then return end
            local rec, v = r.rec, cache[r.rec.id]
            local lines = {}
            lines[#lines + 1] = { l = Esc(rec.zone or "?"), r = When(rec.id) }
            lines[#lines + 1] = { l = "result", r = r.cells.valid }
            lines[#lines + 1] = { l = "foreign healing",
                r = string.format("%d%%", (rec.foreignShare or 0) * 100 + 0.5) }
            if rec.manaModelled then
                lines[#lines + 1] = { l = "low mana",
                    r = string.format("~%d%% - modelled pool, not read", LowestMana(rec) * 100 + 0.5) }
            end
            if rec.truncated then
                lines[#lines + 1] = { l = Tone("bad", "stream truncated"), r = "over 4000 events" }
            end
            if v then
                for _, g in ipairs(v.gates) do
                    lines[#lines + 1] = { l = Tone(g.ok and "good" or "bad", g.name), r = Esc(g.text) }
                end
                for idx, why in pairs(v.excluded) do
                    local nm = rec.roster and rec.roster[idx] and rec.roster[idx].name
                    lines[#lines + 1] = { l = "  excluded " .. (nm and Esc(nm) or tostring(idx)), r = why }
                end
            else
                lines[#lines + 1] = { l = Tone("muted", "not checked yet - right-click -> Validate"), r = "" }
            end
            lines[#lines + 1] = { l = Tone("muted", "Double-click: Play. Right-click: Play, Validate, Coach anyway, Pin, Export."), r = "" }
            tip:Show(row, "ANCHOR_CURSOR", lines)
        end
        local function ListLeave() if MD.Tip then MD.Tip:Hide() end end

        T.list = MD.DashboardParts.CreateTable(pane, width, {
            cols = LIST_COLS, header = T.header, font = font, wideFont = UI.FONT_SMALL,
            rowHeight = rowH, headerHeight = headH, headerRule = true,
            zebra = true, rowWidth = rowW, marker = "bar", scroll = true,
            render = RenderListRow, onEnter = ListEnter, onLeave = ListLeave,
            onClick = function(row, r, button)
                if not r.i then return end
                local was = selected
                selected = r.i
                if T.menu then T.menu:Close() end
                if was ~= selected or button == "RightButton" then api:Render() end
                if button == "RightButton" then api:OpenMenu() end
            end,
            onDoubleClick = function(row, r)
                if r.i then selected = r.i; api:Play() end
            end,
        })
        T.list.frame:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -LIST_TOP)
        T.list.frame:SetWidth(width)

        T.empty = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        T.empty:SetPoint("TOPLEFT", T.list.frame, "TOPLEFT", 8, -(4 + headH + 4))
        T.empty:SetJustifyH("LEFT")
        T.empty:SetTextColor(UI.RGB("muted"))

        -- the RESULT area: a title line, a rule, then lines on a scrolled
        -- table with no header (label / state / text, or one wide line)
        T.resultTitle = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        T.resultTitle:SetJustifyH("LEFT")
        T.resultTitle:SetWordWrap(false)
        T.resultTitle:SetWidth(rowW)
        T.resultRule = pane:CreateTexture(nil, "BORDER")
        T.resultRule:SetColorTexture(UI.Fill("line"))
        local resRowH = UI.Pitch and UI.Pitch(16) or 16
        T.resRowH = resRowH
        T.chars = math.floor((rowW - 16) / 6)
        T.textChars = math.floor((rowW - 214) / 6)
        T.resultApi = MD.DashboardParts.CreateTable(pane, width, {
            cols = {
                { key = "label", x = 8,   w = 150 },
                { key = "state", x = 162, w = 40 },
                { key = "text",  x = 206, w = rowW - 210 },
            },
            font = UI.FONT_SMALL, wideFont = UI.FONT_SMALL, rowHeight = resRowH,
            rowWidth = rowW, noHeader = true, scroll = true,
            render = function(row, r)
                if r.wide then
                    row.cells.wide:SetText(Tone(r.tone or "text2", r.text or ""))
                    row.cells.label:SetText(""); row.cells.state:SetText(""); row.cells.text:SetText("")
                else
                    row.cells.wide:SetText("")
                    row.cells.label:SetText(Tone("text2", r.label or ""))
                    row.cells.state:SetText(Tone(r.stateTone or "text2", r.state or ""))
                    row.cells.text:SetText(Tone(r.tone or "text2", r.text or ""))
                end
            end,
        })
        T.resultApi.frame:SetWidth(width)

        T.hint = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        T.hint:SetPoint("LEFT", runBtn, "RIGHT", 12, 0)
        T.hint:SetJustifyH("LEFT")
        T.hint:SetWidth(width - 560) -- short of the buttons on the right
        T.hint:SetWordWrap(false)
        T.hint:SetTextColor(UI.RGB("muted"))
        T.hint:SetText("Double-click a row to play it. Right-click for the rest.")

        if UI.CreateContextMenu then T.menu = UI.CreateContextMenu(pane, 190) end
        pane:HookScript("OnHide", function() if T.menu then T.menu:Close() end end)
        -- a resized window (a size per group, decision 6) re-lays the list
        -- and the result area; the validation is cached, so this is a repaint
        pane:HookScript("OnSizeChanged", function() if pane:IsShown() then api:Render() end end)
    end

    -- Where the list ends and the result area begins, from the pane's height.
    local function Layout()
        local h = pane:GetHeight()
        local avail = h - LIST_TOP - BOTTOM
        local resH = math.max(120, math.floor(avail * 0.42))
        local listH = math.max(80, avail - resH - 8)
        local rowH = T.list.rowHeight
        T.list:SetVisibleRows(math.max(3, math.floor((listH - 4 - T.list.headerHeight) / rowH)))
        T.list.frame:SetHeight(listH)
        local top = -(LIST_TOP + listH + 8)
        T.resultTitle:ClearAllPoints()
        T.resultTitle:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, top)
        T.resultRule:ClearAllPoints()
        T.resultRule:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, top - 16)
        T.resultRule:SetSize(T.rowW, UI.px and UI.px(1, pane) or 1)
        T.resultApi.frame:ClearAllPoints()
        T.resultApi.frame:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, top - 18)
        T.resultApi.frame:SetHeight(resH - 18)
        T.resultApi:SetVisibleRows(math.max(3, math.floor((resH - 26) / T.resRowH)))
    end

    -- The result area's content: a title (what it is about) and its lines.
    local function PaintResult()
        local res = T.result
        if not res then
            T.resultTitle:SetText(Tone("muted", "RESULT") .. "   "
                .. Tone("muted", "Validate or Coach a fight and the answer appears here."))
            T.resultApi:Render({})
            return
        end
        T.resultTitle:SetText(Tone("muted", "RESULT") .. "   " .. Tone("text2", res.title or ""))
        T.resultApi:Render(res.lines or {})
    end
    local function ShowResult(title, lines, keepScroll)
        T.result = { title = title, lines = lines }
        if not keepScroll then T.resultApi:ScrollTo(0) end
        if pane:IsShown() then PaintResult() end
    end

    -- Wide lines from text (wrapped), each with its tone.
    local function Wide(out, text, tone)
        for _, piece in ipairs(Wrap(text, T.chars)) do
            out[#out + 1] = { wide = true, text = Esc(piece), tone = tone }
        end
    end

    -- A validation as lines: the verdict, a row per gate (name, ok / FAIL,
    -- its text), who was excluded, why a failing gate's limit is where it is,
    -- and what to do next.
    local function ValidationLines(rec, v)
        local out = {}
        if not v then
            Wide(out, "Nothing to validate.", "muted")
            return out
        end
        Wide(out, v.ok and "verdict: REPLAYS - safe to coach from"
            or "verdict: does NOT replay - nothing will be suggested from this fight", v.ok and "good" or "bad")
        for _, g in ipairs(v.gates) do
            local pieces = Wrap(g.text or "", T.textChars)
            for k, piece in ipairs(pieces) do
                out[#out + 1] = { label = k == 1 and g.name or "", state = k == 1 and (g.ok and "ok" or "FAIL") or "",
                    stateTone = g.ok and "good" or "bad", text = Esc(piece), tone = g.ok and "text2" or "text" }
            end
        end
        if (v.energize or 0) > 0 then
            Wide(out, string.format("energize: %.2f/s (%d mp5) the API does not report%s", v.energize,
                v.energize * 5 + 0.5, v.energizeAssumed and " - assumed: the current measurement was applied"
                    or " - recorded with the fight"), "note")
        end
        for idx, why in pairs(v.excluded or {}) do
            local nm = rec.roster and rec.roster[idx] and rec.roster[idx].name or ("target " .. idx)
            Wide(out, "excluded: " .. nm .. " - " .. why, "muted")
        end
        for _, g in ipairs(v.gates) do
            if not g.ok and g.why then
                Wide(out, string.format("why %s is %s: %s", g.name,
                    g.limit and string.format("%.2f", g.limit) or "set where it is", g.why), "muted")
            end
        end
        if v.ok then
            Wide(out, "Coach searches for a better plan; double-click the row to play it.", "muted")
        else
            Wide(out, "The engine cannot rebuild this fight, so a plan made from it would be advice about a "
                .. "different fight. Right-click the row -> Coach anyway to coach it regardless.", "muted")
        end
        return out
    end

    -- The card's structured lines (SP.CardLines) as wide lines; the tones map
    -- straight onto the theme's tokens.
    local CARD_TONE = { head = "text", text = "text2", good = "good", bad = "bad", note = "muted", muted = "muted" }
    local function CardResultLines(cardLines, chat)
        local out = {}
        if type(cardLines) == "table" and #cardLines > 0 then
            for _, l in ipairs(cardLines) do Wide(out, l.text or "", CARD_TONE[l.tone] or "text2") end
        else
            for _, l in ipairs(chat or {}) do
                Wide(out, (tostring(l):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), "text2")
            end
        end
        return out
    end

    local function Title(i, rec, what)
        local where = RunIndex() and ("+" .. Clock(rec.runT0 or 0)) or When(rec.id)
        return string.format("%s - %s, %s - %s", Label(i), Esc(rec.zone or "?"), where, what)
    end

    function api:Validate()
        local rec, i = Selected(), selected
        if not rec then return end
        local v = Validation(rec, true)
        ShowResult(Title(i, rec, "validated just now"), ValidationLines(rec, v))
        local g = FirstFailed(v)
        MD:Print(string.format("%s validated - %s. The details are in Review.", Label(i),
            not v and "nothing to validate" or v.ok and "replays" or ("does not replay (" .. g.name .. ")")))
        api:Render()
    end

    -- Coach one fight or pull. `force` is the row menu's Coach anyway; a plain
    -- Coach on a fight that does not replay shows why in the result area and
    -- searches nothing.
    function api:Coach(force)
        local rec, i = Selected(), selected
        if not (rec and MD.SimPlanner and MD.SimModel) then return end
        if rec.short then return end
        if not MD.player.isDruid then MD:Print("coach: coaching is Druid-only in v1.") return end
        local v = Validation(rec)
        if not force and v and not v.ok then
            ShowResult(Title(i, rec, "does not replay"), ValidationLines(rec, v))
            MD:Print(string.format("%s does not replay (%s) - nothing to coach. Right-click it for Coach anyway.",
                Label(i), FirstFailed(v).name))
            api:Render()
            return
        end
        -- an auto-coach the replay started gives way, as /coach does
        if MD.coachSearch and MD.replayCoaching then
            MD.coachSearch:Cancel()
            MD.coachSearch, MD.replayCoaching = nil, nil
        end
        if MD.coachSearch then MD:Print("coach: already searching.") return end
        local title = Title(i, rec, force and "coach card (Coach anyway)" or "coach card")
        local coaching = Title(i, rec, "coaching")
        ShowResult(coaching, { { wide = true, text = "coaching... 0 plans", tone = "text" } })
        local SP = MD.SimPlanner
        local handle
        handle = SP.CoachAsync(rec, {
            n = Spec(), force = force, noChat = true,
            onProgress = function(evals, max, best)
                local lines = { { wide = true, text = string.format("coaching... %d of %d plans", evals, max or evals),
                    tone = "text" } }
                if best and best[3] then
                    lines[2] = { wide = true, text = string.format("best so far: %s mana used (and owed)", K(best[3])),
                        tone = "muted" }
                end
                ShowResult(coaching, lines, true)
            end,
        }, function(chat, validation, cardLines)
            if MD.coachSearch == handle then MD.coachSearch = nil end
            ShowResult(title, CardResultLines(cardLines, chat))
            local used = type(cardLines) == "table" and cardLines.used
            if used and used.you and used.best then
                T.saved = T.saved or {}
                T.saved[rec.id] = used.you - used.best
                MD:Print(string.format("%s coached - used: you %s, best %s. The card is in Review.",
                    Label(i), K(used.you), K(used.best)))
            else
                MD:Print(string.format("%s: %s", Label(i), Esc(tostring(chat and chat[1] or "no card"))))
            end
            api:Render()
        end)
        MD.coachSearch = handle
    end

    -- Coach the run shown: one plan for the dungeon (SP.CoachRun).
    function api:CoachRun()
        local run = CurrentRun()
        if not (run and MD.SimPlanner) then return end
        if not MD.player.isDruid then MD:Print("coachrun: coaching is Druid-only in v1.") return end
        if MD.runSearch then MD:Print("coachrun: already searching.") return end
        local title = string.format("run %s - coach card", Esc(run.name or "?"))
        ShowResult(string.format("run %s - coaching", Esc(run.name or "?")),
            { { wide = true, text = "coaching the run...", tone = "text" } })
        local handle
        handle = MD.SimPlanner.CoachRun(run, {
            onProgress = function(evals)
                ShowResult(string.format("run %s - coaching", Esc(run.name or "?")),
                    { { wide = true, text = string.format("coaching the run... %d plans", evals), tone = "text" } }, true)
            end,
        }, function(lines)
            if MD.runSearch == handle then MD.runSearch = nil end
            ShowResult(title, CardResultLines(nil, lines))
            MD:Print(string.format("run %s coached - the card is in Review.", Esc(run.name or "?")))
            api:Render()
        end)
        MD.runSearch = handle
    end

    function api:Play()
        if Selected() and MD.Replay then MD.Replay:Open(Spec()) end
    end

    -- The row menu, on the selected row (the right-click selected it first).
    function api:OpenMenu()
        if not T.menu then return end
        local rec, i = Selected(), selected
        if not rec then return end
        local run = CurrentRun()
        local v = cache[rec.id]
        local druid = MD.player.isDruid
        local coachNote = rec.short and "short" or not druid and "Druid only"
            or (v and not v.ok) and "does not replay" or nil
        local items = {
            { text = "Play", note = "double-click", disabled = MD.Replay == nil, onClick = function() api:Play() end },
            { text = "Validate", onClick = function() api:Validate() end },
            { text = run and "Coach pull" or "Coach", note = coachNote, disabled = coachNote ~= nil,
              onClick = function() api:Coach(false) end },
            { text = "Coach anyway", note = (rec.short and "short") or (not druid and "Druid only") or nil,
              disabled = rec.short or not druid, onClick = function() api:Coach(true) end },
            { text = run and (run.pinned and "Unpin the run" or "Pin the run") or (rec.pinned and "Unpin" or "Pin"),
              onClick = function() DoPin() end },
        }
        if MD.RunExport then
            items[#items + 1] = { text = "Export", onClick = function() MD:RunExport() end }
        end
        local where = run and ("+" .. Clock(rec.runT0 or 0)) or When(rec.id)
        T.menu:Open(T.list.frame, string.upper(Label(i)) .. " - " .. where, items)
    end

    -- The list's rows, the Result cell from the gates' `short`.
    function api:RenderThemed(list, run)
        Layout()
        T.header[2] = run and "At" or "When"
        local rows = {}
        for i, rec in ipairs(list) do
            local v = cache[rec.id]
            local result, rtone
            if rec.short then
                result, rtone = "short - under the recording gate, not coached", "muted"
            elseif not v then
                result, rtone = "not checked", "muted"
            elseif v.ok then
                result, rtone = "replays", "good"
            else
                local g = FirstFailed(v)
                result, rtone = "does not replay: " .. Esc(g and g.short or "failed"), "bad"
            end
            if not rec.short and MD.SimPlanner and MD.SimPlanner.plans[rec.id] then
                local saved = T.saved and T.saved[rec.id]
                result = result .. ((saved and saved > 0) and (" - coached: " .. K(saved) .. " less mana")
                    or " - coached")
            end
            if rec.pinned then result = result .. " - pinned" end
            local dim = rec.short and "muted" or (v and not v.ok) and "text2" or "text"
            rows[i] = {
                id = rec.id or i, i = i, rec = rec, selected = (i == selected),
                tone = dim, resultTone = rtone,
                cells = {
                    n = tostring(i),
                    when = run and ("+" .. Clock(rec.runT0 or 0)) or When(rec.id),
                    zone = Esc(rec.zone or "?"),
                    dur = Clock(rec.dur or 0),
                    tgts = tostring(#(rec.tracked or {})),
                    casts = tostring(rec.ownCasts or 0),
                    spent = K(rec.spent or 0),
                    low = (rec.manaModelled and "~" or "") .. string.format("%d%%", LowestMana(rec) * 100 + 0.5),
                    valid = result,
                },
            }
        end
        if T.source ~= source then T.source = source; T.list:Reveal(1) end
        T.list:Render(rows)
        T.empty:SetText(#list == 0 and (run and "This run kept no pulls."
            or IsPractice() and "No practice fights yet - Simulate -> Practice."
            or "No recorded fights yet - pull something for 20s.") or "")
        PaintResult()
    end

    function api:Render()
        if not pane:IsShown() then return end
        api:Release()

        -- the selector: [Fights] plus one button per stored run
        local RR = MD.RunRecorder
        local runs = RR and RR:List() or {}
        for i = 2, 3 do
            local run = runs[i - 1]
            if run then
                sourceBtns[i]:SetText((run.pinned and "*" or "") .. (run.name or "run"))
                sourceBtns[i]:Show()
            else
                sourceBtns[i]:Hide()
            end
        end
        if RunIndex() and not runs[RunIndex()] then source = "fights"; selected = 1 end
        highlightSource(source)

        local run = CurrentRun()
        local list = Rows()
        if selected > #list then selected = math.max(1, #list) end

        if run then
            runFS:SetText(RUN_HI .. RR:Line(run) .. "|r" ..
                (run.truncated and "" or ""))
        elseif IsPractice() then
            runFS:SetText("|cff888888Fights you played in Simulate -> Practice. They replay and coach like real " ..
                "ones; the damage the dead would have taken is kept, so the coach can show how to save them.|r")
        elseif RR and RR.active then
            local st = RR:Status()
            runFS:SetText("|cff99dd99" .. (st[1] or "") .. "|r")
        else
            runFS:SetText("|cff888888The last 8 single pulls. A whole dungeon - every pull and the gaps - " ..
                "is recorded with Start run.|r")
        end

        -- The selected row is validated on sight (one simulation, cached), so
        -- the buttons can tell the truth without the author pressing Validate
        -- first. Before v0.9.8 the "a fight that does not replay has Coach
        -- disabled" rule only took effect AFTER a manual Validate, which is the
        -- one moment it was not needed. Druid-only: the gates run the druid
        -- spell kit, and running them for anyone else would print fiction.
        -- T49 (P5), B24: before the rows are painted, so the selected row's
        -- own cell and hover carry the verdict the buttons already act on.
        local rec = Selected()
        local v = rec and MD.player.isDruid and Validation(rec) or (rec and cache[rec.id])

        -- T71 (P27): under UI.THEMED the list is the generic table, scrolled,
        -- with the result area under it; TBC paints its rows below, unchanged.
        if THEMED then api:RenderThemed(list, run) end
        if not THEMED then
        local y = -38
        local header = AcquireRow()
        header:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
        header:EnableMouse(false)
        for _, col in ipairs(COLS) do header.cells[col[1]]:SetText("|cff888888" .. col[4] .. "|r") end
        y = y - 18

        if #list == 0 then
            local row = AcquireRow()
            row:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
            row.cells.when:SetText(run and "|cff888888This run kept no pulls.|r"
                or IsPractice() and "|cff888888No practice fights yet - Simulate -> Practice.|r"
                or "|cff888888No recorded fights yet - pull something for 20s.|r")
            row.cells.when:SetWidth(width - 80)
        end

        -- T53 (P9, review U25): the rows stop at the pane's height, as they
        -- always have, but no longer silently -- when the list is longer, the
        -- last slot says how many are not shown, and the selected row is kept
        -- on screen (the list starts at it when it would fall off). There is
        -- no scroll yet; the Forever list gets one in P27.
        local first, last, hidden = ListWindow(#list, y, -(pane:GetHeight() - 70), selected)
        for i = first, last do
            local rec = list[i]
            local row = AcquireRow()
            row:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
            row.highlight:SetShown(i == selected)
            row:EnableMouse(true)
            row.recIndex = i
            row:SetScript("OnClick", function(self) selected = self.recIndex; api:Render() end)

            local v = cache[rec.id]
            local cell, ok = ValidateCell(v)
            if rec.short then
                -- under the recording gate (20s / 5 casts). Kept, because a
                -- dungeon is mostly these; not coachable, and the cell says so.
                cell, ok = "|cff888888short - under the recording gate|r", false
            end
            local c = ((v and not ok) or rec.short) and "|cffbbbbbb" or "|cffffffff"
            row.cells.n:SetText(c .. i .. (rec.pinned and "*" or "") .. "|r")
            row.cells.when:SetText(c .. (run and ("+" .. Clock(rec.runT0 or 0)) or When(rec.id)) .. "|r")
            row.cells.zone:SetText(c .. Esc(rec.zone or "?") .. "|r")
            row.cells.dur:SetText(c .. Clock(rec.dur or 0) .. "|r")
            row.cells.tgts:SetText(c .. #(rec.tracked or {}) .. "|r")
            row.cells.casts:SetText(c .. (rec.ownCasts or 0) .. "|r")
            row.cells.spent:SetText(c .. K(rec.spent or 0) .. "|r")
            -- R39 (review 2026-09-29): a v3 recording's mana samples are the
            -- clock's model, not a reading (UnitPower is secret on Forever),
            -- so the cell carries the clock's own "~". A TBC recording never
            -- sets manaModelled and prints as it always has.
            row.cells.low:SetText(c .. (rec.manaModelled and "~" or "")
                .. string.format("%d%%", LowestMana(rec) * 100 + 0.5) .. "|r")
            row.cells.valid:SetText(cell)

            row:SetScript("OnEnter", function(self)
                local tip = MD.Tip
                if not tip then return end
                local lines = {}
                lines[#lines + 1] = { l = Esc(rec.zone or "?"), r = When(rec.id) }
                lines[#lines + 1] = { l = "foreign healing",
                    r = string.format("%d%%", (rec.foreignShare or 0) * 100 + 0.5) }
                if rec.manaModelled then
                    lines[#lines + 1] = { l = "low mana",
                        r = string.format("~%d%% - modelled pool, not read", LowestMana(rec) * 100 + 0.5) }
                end
                if rec.truncated then
                    lines[#lines + 1] = { l = "|cffff9966stream truncated|r", r = "over 4000 events" }
                end
                if v then
                    for _, g in ipairs(v.gates) do
                        lines[#lines + 1] = { l = (g.ok and "|cff99dd99" or "|cffff9966") .. g.name .. "|r",
                                              r = Esc(g.text) }
                    end
                    for idx, why in pairs(v.excluded) do
                        local nm = rec.roster[idx] and rec.roster[idx].name
                        lines[#lines + 1] = { l = "  excluded " .. (nm and Esc(nm) or tostring(idx)),
                                              r = why }
                    end
                else
                    lines[#lines + 1] = { l = "|cff888888press Validate to replay this fight|r", r = "" }
                end
                tip:Show(self, "ANCHOR_RIGHT", lines)
            end)
            row:SetScript("OnLeave", function() if MD.Tip then MD.Tip:Hide() end end)
            y = y - ROW_HEIGHT
        end
        if hidden > 0 then
            local row = AcquireRow()
            row:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
            row:EnableMouse(false)
            row.cells.when:SetText(TailText(hidden))
            row.cells.when:SetWidth(width - 80)
        end
        end -- not THEMED

        -- buttons follow the selection (rec and v are read above, before the rows)
        if run then
            pinBtn:SetText(run.pinned and "Unpin run" or "Pin run")
        else
            pinBtn:SetText(rec and rec.pinned and "Unpin" or "Pin")
        end
        runBtn:SetText(RR and RR.active and "Stop run" or "Start run")
        -- Enable/Disable rather than SetEnabled: the older call exists on every
        -- client this addon targets.
        local function Set(btn, on) if on then btn:Enable() else btn:Disable() end end
        Set(pinBtn, run ~= nil or rec ~= nil)
        Set(validateBtn, rec ~= nil)
        Set(playBtn, rec ~= nil and MD.Replay ~= nil)
        -- R40 (review 2026-09-29): MD:RunExport is Verify.lua's, on the TBC
        -- TOC only. Where it does not exist the button is not offered at all
        -- rather than sitting enabled and doing nothing; TBC takes the old path.
        if MD.RunExport then
            Set(exportBtn, #list > 0)
        else
            exportBtn:Disable()
            exportBtn:Hide()
        end
        Set(runBtn, RR ~= nil)
        -- a fight the gates rejected keeps its button, marked with a star: a
        -- plain click refuses and names the gate, shift forces
        local rejected = (v and not v.ok) and true or false
        -- T71: no star under UI.THEMED (the row menu's Coach anyway forces)
        local star = (rejected and not THEMED) and "*" or ""
        coachBtn:SetText(run and "Coach run" or ("Coach" .. star))
        pullBtn:SetText("Coach pull" .. star)
        pullBtn:SetShown(run ~= nil)
        Set(pullBtn, rec ~= nil and not rec.short and MD.player.isDruid)
        if run then
            Set(coachBtn, MD.player.isDruid and #(run.pulls or {}) > 0)
        else
            Set(coachBtn, rec ~= nil and not rec.short and MD.player.isDruid)
        end
        coachBtn:SetScript("OnEnter", function(self)
            if not MD.Tip then return end
            local lines = { { l = run and "Coach run" or "Coach", r = "" } }
            if run then
                lines[#lines + 1] = { l = "One plan and one drink policy for the whole run,", r = "" }
                lines[#lines + 1] = { l = "with the pulls chained and the gaps simulated.", r = "" }
                lines[#lines + 1] = { l = "|cff888888Scored on time first: added time, then drinks,", r = "" }
                lines[#lines + 1] = { l = "|cff888888then mana. Coach pull is the single-fight card.|r", r = "" }
                MD.Tip:Show(self, "ANCHOR_RIGHT", lines)
                return
            end
            if rec and rec.short then
                lines[#lines + 1] = { l = "|cff888888This pull is under the recording gate", r = "" }
                lines[#lines + 1] = { l = "|cff888888(20s and 5 casts). It is kept because a dungeon", r = "" }
                lines[#lines + 1] = { l = "|cff888888is mostly these - but there is nothing to learn", r = "" }
                lines[#lines + 1] = { l = "|cff888888from eight seconds.|r", r = "" }
            elseif not MD.player.isDruid then
                lines[#lines + 1] = { l = "|cff888888Coaching is Druid-only in v1.|r", r = "" }
            elseif v and not v.ok then
                lines[#lines + 1] = { l = "|cffff9966This fight does not replay, so nothing would be", r = "" }
                lines[#lines + 1] = { l = "|cffff9966suggested from it.|r", r = "" }
                for _, g in ipairs(v.gates) do
                    if not g.ok then lines[#lines + 1] = { l = "  " .. g.name, r = Esc(g.text) } end
                end
                if THEMED then -- T71: the row menu, not a modifier
                    lines[#lines + 1] = { l = UI.Hex("accent") .. "right-click the row|r -> Coach anyway", r = "" }
                    lines[#lines + 1] = { l = UI.Hex("muted") .. "Play then shows both columns, marked FORCED.|r", r = "" }
                else
                lines[#lines + 1] = { l = "|cffffff00shift-click|r to coach it anyway", r = "" }
                lines[#lines + 1] = { l = "|cff888888(or /md coach " .. Spec() .. " force)|r", r = "" }
                lines[#lines + 1] = { l = "|cff888888Play then shows both columns, marked FORCED.|r", r = "" }
                end
            elseif not v then
                lines[#lines + 1] = { l = "|cff888888Validate first, or press Coach to do both.|r", r = "" }
            else
                lines[#lines + 1] = { l = THEMED and "Search for a better plan; the card appears under the list."
                    or "Search for a better plan and print the card.", r = "" }
                lines[#lines + 1] = { l = "|cff888888Runs across frames; /md coach cancel stops it.|r", r = "" }
            end
            MD.Tip:Show(self, "ANCHOR_RIGHT", lines)
        end)
        coachBtn:SetScript("OnLeave", function() if MD.Tip then MD.Tip:Hide() end end)

        habitsFS:SetText(Habits() or "|cff888888Habits appear once a few fights have been summarised.|r")
        local zone = MD.API.RealZoneText and MD.API.RealZoneText() or nil
        local prog = MD.SimPlanner and zone and MD.SimPlanner.Progress(zone)
        progressFS:SetText(prog and ("|cff99dd99" .. prog .. "|r") or "")
    end

    return api
end
