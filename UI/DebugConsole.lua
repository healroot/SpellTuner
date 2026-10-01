-- Debug console (Cell-style): MD:Debug() lines land in an in-memory ring,
-- shown in a movable window with per-category filters, and exported through
-- a "Copy" popup (select-all edit box, Ctrl+C). Logging is off unless the
-- "Enable Debug Logging" box is ticked; nothing is persisted.
local _, MD = ...
local UI = MD.UI

local CATEGORY_ORDER = { "regen", "mana", "spend", "tto", "heal", "cast", "calib", "combat", "chat", "sim", "other" }
local CATEGORY_LABELS = {
    regen = "Regen", mana = "Mana", spend = "Spend", tto = "TTO", heal = "Heal",
    cast = "Cast", calib = "Calib", combat = "Combat", chat = "Chat", sim = "Sim", other = "Other",
}
local CATEGORY_COLORS = {
    regen = "|cff33ff66", mana = "|cff66aaff", spend = "|cffff9933", tto = "|cffffcc00",
    heal = "|cff66ff99", cast = "|cffcc99ff", calib = "|cffffd27f", combat = "|cffff5555", chat = "|cffaaaaaa",
    sim = "|cff77ddff",
    other = "|cffcccccc",
}

-- Category filter grid: 5 per row at a fixed pitch wide enough for the
-- longest label ("Combat"), so adding a category grows a row instead of
-- overflowing the frame.
local CATEGORY_COLUMNS, CATEGORY_COL_W, CATEGORY_ROW_H = 5, 84, 20

local MIN_LINES, MAX_LINES, DEFAULT_LINES = 200, 20000, 1000
local VIEW_LINES = 300       -- rendered in the window (newest)

local function MaxLogLines()
    local n = MD.db and MD.db.debug and tonumber(MD.db.debug.maxLines) or DEFAULT_LINES
    if n < MIN_LINES then n = MIN_LINES elseif n > MAX_LINES then n = MAX_LINES end
    return n
end
local logLines = {}
local sessionT0 = GetTime()

local consoleFrame, content, categoryCBs, enableCB, countFS
local dirty = false

-- T3: "Errors this session: N distinct, M total - /st dump copies them",
-- read fresh every refresh (MD.errors is nil on TBC, so this is a no-op there).
local function RefreshErrorsLine()
    if not (consoleFrame and consoleFrame.errorsFS) then return end
    if type(MD.errors) ~= "table" then return end
    local distinct = #MD.errors
    local total = tonumber(MD.errorTotal) or 0
    if distinct == 0 and total == 0 then
        consoleFrame.errorsFS:SetText("Errors this session: none")
    else
        consoleFrame.errorsFS:SetText(string.format(
            "Errors this session: %d distinct, %d total - /st dump copies them", distinct, total))
    end
end

local function Categories()
    return MD.db and MD.db.debug and MD.db.debug.categories or {}
end

-- Entry point used by MD:Debug (Core.lua). Timestamp = wall clock plus
-- seconds since load, so sub-second spacing (mana ticks, 5SR edges) is visible.
function MD:DebugLog(category, text)
    if not CATEGORY_LABELS[category] then category = "other" end
    local line = string.format("|cff888888%s +%.2f|r %s[%s]|r %s",
        date("%H:%M:%S"), GetTime() - sessionT0, CATEGORY_COLORS[category], category, tostring(text))
    logLines[#logLines + 1] = { category = category, text = line }
    -- Trim in batches (drop the oldest 25% once the ring is a quarter over its
    -- size) so a 20k-line buffer never pays a per-line table.remove(1).
    local max = MaxLogLines()
    if #logLines > max * 1.25 then
        local keep = {}
        for i = #logLines - max + 1, #logLines do keep[#keep + 1] = logLines[i] end
        logLines = keep
    end
    dirty = true
end

local function RefreshLog()
    dirty = false
    if not (consoleFrame and consoleFrame:IsShown()) then return end
    RefreshErrorsLine()
    local shown = Categories()
    local newest, n = {}, 0
    for i = #logLines, 1, -1 do
        local e = logLines[i]
        if shown[e.category] ~= false then
            n = n + 1
            newest[n] = e.text
            if n >= VIEW_LINES then break end
        end
    end
    local ordered = {}
    for i = n, 1, -1 do ordered[#ordered + 1] = newest[i] end
    content:SetText(table.concat(ordered, "\n"))
    local h = math.max(content:GetStringHeight() + 10, 2)
    consoleFrame.scrollFrame:SetContentHeight(h)
    consoleFrame.scrollFrame:ScrollToBottom()
    countFS:SetText(string.format("%d line%s%s", #logLines, #logLines == 1 and "" or "s",
        n < #logLines and (" (" .. n .. " shown)") or ""))
end

local function StripColors(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- T3 (/st dump): the newest n lines, every category, colour codes stripped --
-- plus the ring's true length so the dump's header can say "newest n of m".
-- Unlike BuildPlainTextLog this ignores the category checkboxes: a bug report
-- wants everything that happened, not just what is ticked on right now.
function MD:DebugLogTail(n)
    local total = #logLines
    local start = math.max(1, total - n + 1)
    local lines = {}
    for i = start, total do
        lines[#lines + 1] = StripColors(logLines[i].text)
    end
    return lines, total
end

local function BuildPlainTextLog()
    local shown = Categories()
    local lines = {}
    for _, entry in ipairs(logLines) do
        if shown[entry.category] ~= false then
            lines[#lines + 1] = StripColors(entry.text)
        end
    end
    return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- Copy popup: a read-only scroll edit box holding plain text, pre-selected so
-- Ctrl+C just works. Public (MD:ShowCopyPopup) because /md profile hands the
-- author 40 lines of state and chat is the wrong place for that.
--------------------------------------------------------------------------------
local copyFrame, copyTextArea, copyTitle

function MD:ShowCopyPopup(title, text)
    if not copyFrame then
        copyFrame = UI.CreateMovableFrame("Copy", "SpellTunerDebugCopyFrame", 460, 340, "FULLSCREEN_DIALOG", 10, true)
        copyFrame:SetToplevel(true)
        copyTitle = copyFrame.header.text

        local hint = copyFrame:CreateFontString(nil, "OVERLAY", UI.FONT)
        hint:SetPoint("TOPLEFT", 5, -5)
        hint:SetText("Ctrl+C to copy, then paste it wherever you need")

        copyTextArea = UI.CreateScrollEditBox(copyFrame)
        copyTextArea:SetPoint("TOPLEFT", 5, -22)
        copyTextArea:SetPoint("BOTTOMRIGHT", -5, 5)
        UI.StylizeFrame(copyTextArea.scrollFrame, { 0, 0, 0, 0 }, UI.AccentSpec(1)) -- T107: the accent by name

        copyTextArea.eb:SetScript("OnEditFocusGained", function() copyTextArea.eb:HighlightText() end)
        copyTextArea.eb:SetScript("OnMouseUp", function() copyTextArea.eb:HighlightText() end)
        copyTextArea.eb:SetScript("OnEditFocusLost", function() copyFrame:Hide() end)
        copyTextArea.eb:SetScript("OnEscapePressed", function() copyTextArea.eb:ClearFocus() end)
        -- read-only: any typed character restores the text
        copyTextArea.eb:SetScript("OnChar", function()
            copyTextArea.eb:SetText(copyFrame.text)
            copyTextArea.eb:HighlightText()
        end)
    end

    if copyTitle then copyTitle:SetText(title or "Copy") end
    copyFrame.text = text or ""
    copyTextArea.eb:SetText(copyFrame.text)
    copyTextArea.eb:SetCursorPosition(0)

    copyFrame:ClearAllPoints()
    -- T33 (6.2, 6.5; T80 / C1: both lines): FULLSCREEN_DIALOG / 20, above the
    -- lists; any open list closed; the window scale; centred on the window
    -- that asked (the newest one on the ESC stack), and on the stack itself
    -- once shown (Push, so it closes first).
    copyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    copyFrame:SetFrameLevel(20)
    copyFrame:SetScale(MD.Win:Scale())
    MD.Win:CloseLists()
    local owner = MD.Win:TopWindow(copyFrame)
    if owner then
        copyFrame:SetPoint("CENTER", owner, "CENTER")
    else
        copyFrame:SetPoint("CENTER")
    end
    copyFrame:Show()
    MD.Win:Push(copyFrame)
    copyTextArea.eb:SetFocus()
    copyTextArea.eb:HighlightText()
end

local function ShowLogCopyPopup()
    -- Every pasted log carries its own inputs: the first dungeon log could not
    -- say whether Nature's Grace was even talented, and the analysis had to
    -- infer it from a cast time.
    local text = BuildPlainTextLog()
    if MD.Snapshot then
        local head = { string.format("=== SpellTuner v%s  %s  %s level %d  %s ===", MD.version, MD.player.charKey,
            MD.player.class, MD.player.level, date("%Y-%m-%d %H:%M")) }
        for _, line in ipairs(MD:Snapshot()) do head[#head + 1] = line end
        head[#head + 1] = "--- log ---"
        text = table.concat(head, "\n") .. "\n" .. text
    end
    MD:ShowCopyPopup("Copy Debug Log", text)
end

--------------------------------------------------------------------------------
-- Console window
--------------------------------------------------------------------------------
local function CreateDebugConsoleFrame()
    consoleFrame = UI.CreateMovableFrame("SpellTuner Debug Console", "SpellTunerDebugConsole", 700, 560, "DIALOG", 1, true)
    consoleFrame:SetToplevel(true)

    enableCB = UI.CreateCheckButton(consoleFrame, "Enable Debug Logging", function(checked)
        MD.db.debug.enabled = checked
        -- MD:TalentSummary is Core_TBC.lua's (the TBC talent scan); Forever has
        -- no talent scan, so its header line leaves talents out rather than
        -- calling a method that is not there (review R15/R16).
        if type(MD.TalentSummary) == "function" then
            MD:Debug("other", "debug logging enabled (v%s, %s level %d, talents: %s)",
                MD.version, MD.player.class, MD.player.level, MD:TalentSummary())
        else
            MD:Debug("other", "debug logging enabled (v%s, %s level %d)",
                MD.version, MD.player.class, MD.player.level)
        end
        RefreshLog()
    end, "Enable Debug Logging", "Records regen / mana ticks / casts / clock state into this window (memory only, nothing is saved).", "Leave it off when you are not testing.")
    enableCB:SetPoint("TOPLEFT", 10, -12)

    local clearBtn = UI.CreateButton(consoleFrame, "Clear", "red-hover", { 60, 17 })
    clearBtn:SetPoint("TOPRIGHT", -10, -10)
    clearBtn:SetScript("OnClick", function()
        logLines = {}
        RefreshLog()
    end)

    local copyBtn = UI.CreateButton(consoleFrame, "Copy", "accent-hover", { 60, 17 }, false, false, nil, nil,
        "Copy", "Opens a text box with the visible categories as plain text - Ctrl+C there.")
    copyBtn:SetPoint("RIGHT", clearBtn, "LEFT", -5, 0)
    copyBtn:SetScript("OnClick", ShowLogCopyPopup)

    -- Only on TBC, where MD.RunRegenTest reads the TBC engine -- Forever has
    -- no such test yet, so its console does not offer a button that would do
    -- nothing (checked at build time: this frame is built once, on first
    -- open, so a module loading later can never make the button appear).
    local regenBtn
    if type(MD.RunRegenTest) == "function" then
        regenBtn = UI.CreateButton(consoleFrame, "Regen test", "accent-hover", { 80, 17 }, false, false, nil, nil,
            "Regen test (30s)", "Stand idle at partial mana, no drink, no casting.",
            "Compares observed mana gain with GetManaRegen and says whether Dreamstate is included.")
        regenBtn:SetPoint("RIGHT", copyBtn, "LEFT", -5, 0)
        regenBtn:SetScript("OnClick", function()
            if not MD.db.debug.enabled then
                enableCB:SetChecked(true)
                enableCB.onClick(true, enableCB)
            end
            if MD.RunRegenTest then MD:RunRegenTest(30) end
        end)
    end

    -- Fixed grid, not a chained row: the labels are different widths, and
    -- chaining them ran the last category off the frame and under the "keep
    -- lines" box as soon as a ninth category (Cast) was added. Columns are a
    -- fixed pitch so they line up, and the row count follows the category
    -- count instead of being implied by the frame width.
    local categoryRows = math.ceil(#CATEGORY_ORDER / CATEGORY_COLUMNS)
    categoryCBs = {}
    for i, category in ipairs(CATEGORY_ORDER) do
        local cb = UI.CreateCheckButton(consoleFrame, CATEGORY_LABELS[category], function(checked)
            MD.db.debug.categories[category] = checked
            RefreshLog()
        end)
        local col = (i - 1) % CATEGORY_COLUMNS
        local row = math.floor((i - 1) / CATEGORY_COLUMNS)
        cb:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", col * CATEGORY_COL_W, -12 - row * CATEGORY_ROW_H)
        categoryCBs[category] = cb
    end

    countFS = consoleFrame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    countFS:SetPoint("RIGHT", regenBtn or copyBtn, "LEFT", -8, 0)
    countFS:SetTextColor(0.6, 0.6, 0.6)

    -- T3: only present when MD.errors exists (Forever only -- TBC never
    -- installs the capture, so MD.errors stays nil and this line is absent).
    -- Refreshed alongside the log (RefreshLog below), not just on show, so a
    -- fresh error while the console is already open is reflected at once.
    local errorsFS
    local errorsRowH = 0
    if type(MD.errors) == "table" then
        errorsFS = consoleFrame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        errorsFS:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -12 - categoryRows * CATEGORY_ROW_H)
        errorsFS:SetTextColor(0.8, 0.5, 0.5)
        errorsRowH = CATEGORY_ROW_H
    end
    consoleFrame.errorsFS = errorsFS

    -- "keep N lines": ring size, saved in the settings
    local keepEB = UI.CreateEditBox(consoleFrame, 56, 16, false, false, true, UI.FONT_SMALL)
    keepEB:SetPoint("TOPRIGHT", -10, -37)
    keepEB:SetTextInsets(3, 3, 0, 0)
    local keepLabel = consoleFrame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    keepLabel:SetPoint("RIGHT", keepEB, "LEFT", -4, 0)
    keepLabel:SetTextColor(0.7, 0.7, 0.7)
    keepLabel:SetText("keep lines")
    UI.SetTooltips(keepEB, "ANCHOR_TOPLEFT", 0, 3, "Lines kept in memory",
        string.format("%d to %d (default %d). Copy exports all of them; the", MIN_LINES, MAX_LINES, DEFAULT_LINES),
        string.format("window shows the newest %d. A long fight with Mana on is ~3 lines/s.", VIEW_LINES))
    local function ApplyKeep(self)
        local n = tonumber(self:GetText())
        if n then
            if n < MIN_LINES then n = MIN_LINES elseif n > MAX_LINES then n = MAX_LINES end
            MD.db.debug.maxLines = n
        end
        self:SetText(tostring(MaxLogLines()))
        self:HighlightText(0, 0)
    end
    keepEB:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    keepEB:SetScript("OnEditFocusLost", ApplyKeep)
    consoleFrame.keepEB = keepEB

    UI.CreateScrollFrame(consoleFrame, -(46 + categoryRows * CATEGORY_ROW_H + errorsRowH), 5)
    consoleFrame.scrollFrame:SetScrollStep(37)
    UI.StylizeFrame(consoleFrame.scrollFrame, { 0.1, 0.1, 0.1, 0.5 })
    -- T107: the log's category colours are the legend (docs/SPEC-next.md 5.1:
    -- the same under every style), so a style switch's follow never enters it
    consoleFrame.scrollFrame.restyleExempt = true

    content = consoleFrame.scrollFrame.content:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    content:SetPoint("TOPLEFT", 5, -5)
    content:SetWidth(consoleFrame:GetWidth() - 30)
    content:SetJustifyH("LEFT")
    content:SetJustifyV("TOP")
    content:SetSpacing(2)

    consoleFrame:SetScript("OnShow", function()
        enableCB:SetChecked(MD.db.debug.enabled)
        consoleFrame.keepEB:SetText(tostring(MaxLogLines()))
        for category, cb in pairs(categoryCBs) do
            cb:SetChecked(MD.db.debug.categories[category] ~= false)
        end
        RefreshLog()
    end)

    -- Re-render at most 4x/s while shown (mana ticks can arrive in bursts).
    local acc = 0
    consoleFrame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.25 then
            acc = 0
            if dirty then RefreshLog() end
        end
    end)

    -- T33 (docs/SPEC-forever-ui.md 6.2, 6.5; T80 / C1: both lines, the manager
    -- UI/Windows.lua on every main TOC): a tool in FULLSCREEN / 10, above the
    -- replay's DIALOG; its place remembered in db.ui.win.console; one ESC
    -- stack entry instead of its own UISpecialFrames line. Registered after
    -- its OnShow script, which Register hooks.
    MD.Win:Register(consoleFrame, { key = "console", role = "tool" })
end

function MD:ToggleDebugConsole()
    if not consoleFrame then
        CreateDebugConsoleFrame()
    end
    if consoleFrame:IsShown() then
        consoleFrame:Hide()
    else
        MD.Win:Place("console") -- T33: where it was left (clamped), not re-centred
        consoleFrame:Show()
    end
end
