-- Practice bindings (v0.15.1): the window where a press is given a spell, in
-- the shape Cell's Click Castings and Clique use -- one row per binding, click
-- the key box and press what you want, pick the spell from a tree (a family,
-- its ranks under it -- v0.15.2, because a flat list of forty ranks ran off the
-- bottom of the window).
--
-- And the three import buttons. Cell and Clique already hold "this press casts
-- that spell"; Engine/Practice.lua reads their tables (and, for a macro
-- binding, the first heal the macro casts) so the bindings do not have to be
-- retyped. Neither addon is a dependency and neither is read during a fight:
-- the import happens when the button is pressed, and what it CANNOT import it
-- prints rather than guessing.
--
-- An import ADDS to the list (v0.15.4): a key both have is re-pointed to the
-- imported spell, everything the import does not mention stays. Defaults is the
-- one button that starts over.
--
-- These bindings are account-wide (db.practiceBinds): your hands do not change
-- with the character.
--
-- T40 (docs/SPEC-forever-ui.md 4.4, 6.2, 6.4, 6.5, 6.6): with the window
-- manager (MD.Win, the Forever TOCs only) this is a SHEET on the Simulate ->
-- Practice pane, not a window: BW:Build(parent) builds it there once (440 x
-- 460, the whole pane masked), /st binds and "Edit bindings" open the main
-- window on that view with the sheet shown, it is one entry on the ESC stack
-- (one ESC closes the sheet and leaves the window), it hides with its pane,
-- and it refuses to open in combat. Under the theme (UI.TEXT) the waiting key
-- box is in the accent and an import's notes in text2, not Blizzard gold.
-- TBC keeps its own movable window exactly as before.
local _, MD = ...
local UI = MD.UI

local W, H = 470, 430
local SHEET_W, SHEET_H = 440, 460 -- T40: the sheet's size (6.2)
local ROW_H = 22
local frame, rows, addBtn, defBtn, cellBtn, cliqueBtn, keysBtn, importFS, statusFS, list
local hiddenLine, hiddenFS, forgetBtn -- T27: the footer for bindings kept but hidden
local host -- T40: the practice pane the sheet sits on (nil: TBC's window)
local capturing = nil

-- T40: a colour from the theme, else today's literal (TBC)
local function Hex(token, fallback)
    local t = UI.TEXT and UI.TEXT[token]
    return (t and t.hex) or fallback
end

-- a tooltip's first line takes the client's gold unless it is coloured: the
-- accent under the theme, the text unchanged on TBC
local function Title(text)
    local t = UI.TEXT and UI.TEXT.accent
    return t and (t.hex .. text .. "|r") or text
end

local function InCombat()
    local v = MD.API.UnitAffectingCombat and MD.API.UnitAffectingCombat("player")
    return v == true
end

local function Binds() return MD.Practice.Binds() end

-- One row per family, its ranks in a submenu on hover: a flat list of every
-- rank is forty rows and ran off the bottom of the window (v0.15.2).
local function SpellItems()
    MD.Practice.EnsureKit()
    local SD = MD.SpellData
    local items = {}
    for _, family in ipairs({ "Lifebloom", "Rejuvenation", "Regrowth", "Swiftmend", "HealingTouch" }) do
        local known = SD.known[family]
        if known and #known > 0 then
            local label = (SD.families[family] and SD.families[family].label) or family
            local top = SD.spells[known[#known]].rank
            local kids = { { id = family .. ":0", text = "highest (rank " .. top .. ", follows training)" } }
            for j = #known, 1, -1 do
                kids[#kids + 1] = { id = family .. ":" .. SD.spells[known[j]].rank,
                                    text = label .. " " .. SD.spells[known[j]].rank }
            end
            items[#items + 1] = { id = family .. ":0", text = label, children = #known > 1 and kids or nil }
        end
    end
    return items
end

local function Status(text, colour)
    if statusFS then statusFS:SetText((colour or "|cff888888") .. text .. "|r") end
end

local Render

-- One row: the key box (click, then press), the spell, and a remove button.
local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, list.content)
    row:SetSize(W - 40, ROW_H)
    row:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -(i - 1) * (ROW_H + 2))
    row.key = UI.CreateButton(row, "", "accent-hover", { 150, ROW_H - 2 }, false, false, UI.FONT_SMALL, nil)
    row.key:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.key:RegisterForClicks("AnyUp")
    row.spell = UI.CreateTreeDropdown(row, 200, ROW_H - 2, function(id)
        local b = Binds()[row.index]
        if not b then return end
        local family, rank = id:match("^(%a+):(%d+)$")
        b.family = family
        b.rank = (tonumber(rank) or 0) > 0 and tonumber(rank) or nil
    end)
    row.spell:SetPoint("LEFT", row.key, "RIGHT", 6, 0)
    row.del = UI.CreateButton(row, "x", "red-hover", { 22, ROW_H - 2 }, false, false, UI.FONT_SMALL, nil)
    row.del:SetPoint("LEFT", row.spell, "RIGHT", 6, 0)
    row.del:SetScript("OnClick", function()
        -- T27: removed from the stored list by the binding itself -- with a
        -- hidden one before it, the row's index is not its place in the list
        local b = Binds()[row.index]
        if b then MD.Practice.RemoveBind(b) end
        capturing = nil
        Render()
    end)

    local function Take(key)
        local b = Binds()[row.index]
        if b and key then
            local PR = MD.Practice
            local full = PR.Mods(MD.API.IsAltKeyDown and MD.API.IsAltKeyDown(),
                MD.API.IsControlKeyDown and MD.API.IsControlKeyDown(),
                MD.API.IsShiftKeyDown and MD.API.IsShiftKeyDown()) .. key
            for _, other in ipairs(PR.AllBinds()) do
                -- one press, one spell: taking a key takes it from whoever had
                -- it -- T27: a hidden binding too, so it cannot come back on
                -- the same key as this one when its spell is learned
                if other ~= b and other.key == full then other.key = "" end
            end
            b.key = full
            Status("bound " .. full .. ".")
        end
        capturing = nil
        row.key:EnableKeyboard(false)
        Render()
    end
    row.key:SetScript("OnClick", function(self, button)
        if capturing ~= row then
            capturing = row
            self:SetText(Hex("accent", "|cffffcc00") .. "press a key or button...|r") -- T40
            self:EnableKeyboard(true)
            Status("press the key or mouse button, with any modifiers held. Escape cancels.")
            return
        end
        Take(MD.Practice.MOUSE[button])
    end)
    row.key:SetScript("OnKeyDown", function(self, key)
        if capturing ~= row then return end
        if key == "LSHIFT" or key == "RSHIFT" or key == "LALT" or key == "RALT"
           or key == "LCTRL" or key == "RCTRL" or key == "UNKNOWN" then return end
        if key == "ESCAPE" then
            capturing = nil
            self:EnableKeyboard(false)
            Render()
            return
        end
        Take(key)
    end)
    rows[i] = row
    return row
end

-- T27: "1 binding kept for a spell you have not learned  [Forget]", its
-- hover naming them; shown only while a binding is hidden (never on TBC).
local function RenderHidden()
    if not hiddenLine then return end
    local hidden = MD.Practice.HiddenBinds()
    if #hidden == 0 then
        hiddenLine:Hide()
        return
    end
    local one = #hidden == 1
    hiddenFS:SetText(string.format("|cff888888%d %s kept for %s you have not learned|r", #hidden,
        one and "binding" or "bindings", one and "a spell" or "spells"))
    local tips = { Title("Kept for when you learn the spell") }
    for _, b in ipairs(hidden) do
        tips[#tips + 1] = (b.key ~= "" and b.key or "unbound") .. "  " .. MD.Practice.FamilyLabel(b.family)
            .. (b.rank and (" " .. b.rank) or "")
    end
    tips[#tips + 1] = "Not listed, not counted, never cast until then. Forget deletes them."
    UI.SetTooltips(hiddenLine, "ANCHOR_TOPLEFT", 0, 3, unpack(tips))
    hiddenLine:Show()
end

Render = function()
    if not frame then return end
    MD.Practice.RefreshKit() -- T27: a spell learned since brings its binding back (Forever only)
    local binds = Binds()
    local items = SpellItems()
    for i, b in ipairs(binds) do
        local row = Row(i)
        row.index = i
        if capturing ~= row then
            row.key:SetText(b.key ~= "" and b.key or "|cffff9966unbound|r")
            row.key:EnableKeyboard(false)
        end
        row.spell:SetItems(items)
        if b.family then
            row.spell:SetValue(b.family .. ":" .. (b.rank or 0))
        else
            row.spell:SetValue(nil)
        end
        row:Show()
    end
    for i = #binds + 1, #rows do rows[i]:Hide() end
    list:SetContentHeight(math.max(1, #binds) * (ROW_H + 2))
    RenderHidden()
    if MD.PracticeBindsChanged then MD:PracticeBindsChanged() end
end

-- What an import did, in full: a line per binding it could not take.
local function Report(newList, report)
    if not newList then
        Status(report and report.error or "nothing to import.", "|cffff9966")
        return
    end
    local added, replaced, same, notInBook = MD.Practice.ApplyImport(newList)
    notInBook = notInBook or {}
    capturing = nil
    Render()
    -- added on top of what was there; a key both had now casts the imported spell
    local lines = { string.format("|cff99dd99From %s: %d added, %d replaced%s. Everything else kept.|r",
        report.source or "?", added, replaced, same > 0 and string.format(", %d already the same", same) or "") }
    for _, note in ipairs(report.notes or {}) do
        lines[#lines + 1] = Hex("text2", "|cffffcc00") .. note .. "|r" -- T40
    end
    for _, why in ipairs(report.skipped or {}) do
        lines[#lines + 1] = "|cff888888not imported - " .. why .. "|r"
    end
    -- T27: named, so nothing an import had vanishes unexplained
    if #notInBook > 0 then
        lines[#lines + 1] = "|cff888888skipped (not in your spellbook): " .. table.concat(notInBook, ", ") .. "|r"
    end
    if #(report.skipped or {}) == 0 and #(report.notes or {}) == 0 and #notInBook == 0 then
        lines[#lines + 1] = "|cff888888Everything it had was a heal.|r"
    end
    statusFS:SetText(table.concat(lines, "\n"))
end

-- T40: onPane (Forever, with the manager) builds the sheet on that pane;
-- nothing (TBC) builds today's window. `root` is what everything below is
-- built in: the sheet's body under its title row, or the window itself.
local function Build(onPane)
    if frame then return end
    local root
    if onPane then
        frame = UI.CreateSheet(onPane, onPane, SHEET_W, SHEET_H, "PRACTICE BINDINGS")
        frame.bindingsSheet = true -- marks the sheet for tools/practiceforever.lua
        host = onPane
        root = frame:Body()
        W, H = SHEET_W - 2, SHEET_H - 23 -- the body: inside the 1-px edge, under the title row
        -- the kit's own OnShow / OnHide keep the mask; these only add to them
        frame:HookScript("OnHide", function() capturing = nil end)
        -- hides with its owner (6.2): switching view or closing the window
        -- closes the sheet, and its OnHide takes it off the ESC stack
        onPane:HookScript("OnHide", function() if frame:IsShown() then frame:Hide() end end)
        local done = UI.CreateButton(frame, "Done", "accent-hover", { 50, 18 }, false, false, UI.FONT_SMALL, nil)
        done:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
        done:SetScript("OnClick", function() frame:Hide() end)
    else
        frame = UI.CreateMovableFrame("SpellTuner: Practice bindings", "SpellTunerBindingsWindow", W, H)
        tinsert(UISpecialFrames, "SpellTunerBindingsWindow")
        frame:SetScript("OnHide", function() capturing = nil end)
        root = frame
    end
    rows = {}

    local hint = root:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    hint:SetPoint("TOPLEFT", root, "TOPLEFT", 12, -10)
    hint:SetWidth(W - 24)
    hint:SetJustifyH("LEFT")
    hint:SetText("In practice you hover a frame and press. Click a binding's key box, then press the key " ..
        "or mouse button you want, modifiers held.|n" .. Hex("muted", "|cff888888") .. "These are SpellTuner's own bindings - " ..
        "practice never reads your keybindings, Cell or Clique while you play, so import them here.|r")

    list = UI.CreateScrollFrame(root, 0, 0)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", root, "TOPLEFT", 12, -56)
    list:SetSize(W - 30, H - 56 - 96)
    list:SetScrollStep(ROW_H * 3)

    addBtn = UI.CreateButton(root, "+ binding", "accent-hover", { 90, 20 }, false, false, UI.FONT_SMALL, nil)
    addBtn:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 12, 72)
    addBtn:SetScript("OnClick", function()
        local family = "Rejuvenation"
        if MD.Practice.policy.kitIsLive then family = MD.Practice.FirstFamily() end
        MD.Practice.AddBind({ key = "", family = family }) -- T27: into the stored list
        Render()
        Status("click the new row's key box and press something.")
    end)

    defBtn = UI.CreateButton(root, "Defaults", "accent-hover", { 80, 20 }, false, false, UI.FONT_SMALL, nil,
        Title("Back to the shipped defaults"), "Read from your Cell click-casting when this was written:",
        "Button5 Lifebloom, Alt-Button5 Rejuvenation, Shift-Button5 Rejuvenation Rank 5,",
        "left Regrowth, right Swiftmend, Shift-left Healing Touch.")
    defBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    -- no defaults to go back to on a line whose policy ships none (Forever:
    -- the shipped ones are the TBC author's Cell bindings)
    if #MD.Practice.policy.defaultBinds == 0 then defBtn:Hide() end
    defBtn:SetScript("OnClick", function()
        MD.db.practiceBinds = nil
        Binds()
        capturing = nil
        Render()
        Status("back to the defaults.")
    end)

    -- T27: the footer for hidden bindings, where Defaults would sit (Defaults
    -- is TBC's only, and TBC never hides one)
    hiddenLine = CreateFrame("Frame", nil, root)
    hiddenLine:SetSize(W - 24 - 90 - 12, 20)
    hiddenLine:SetPoint("LEFT", addBtn, "RIGHT", 12, 0)
    hiddenLine:EnableMouse(true)
    hiddenFS = hiddenLine:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    hiddenFS:SetPoint("LEFT", hiddenLine, "LEFT", 0, 0)
    hiddenFS:SetJustifyH("LEFT")
    forgetBtn = UI.CreateButton(hiddenLine, "Forget", "red-hover", { 60, 18 }, false, false, UI.FONT_SMALL, nil,
        Title("Forget them"), "Deletes the bindings kept for spells you have not learned.")
    forgetBtn:SetPoint("LEFT", hiddenFS, "RIGHT", 8, 0)
    forgetBtn:SetScript("OnClick", function()
        local n = MD.Practice.ForgetHidden()
        capturing = nil
        Render()
        Status(string.format("forgot %d %s.", n, n == 1 and "binding" or "bindings"))
    end)
    hiddenLine:Hide()

    importFS = root:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    importFS:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 12, 48)
    importFS:SetText("Import from")

    keysBtn = UI.CreateButton(root, "Keybindings", "accent-hover", { 100, 20 }, false, false, UI.FONT_SMALL, nil,
        Title("Read the game's own keybindings"), "Follows every bound key to the action-bar slot it presses and reads",
        "what is in it: a spell, or a macro's first heal - which is how a mouseover",
        "macro on a bar becomes a practice binding. Blizzard's bars, ElvUI's and any",
        "bar addon whose buttons carry an `action` attribute.",
        "Adds to your list: a key you already bound casts the imported spell.",
        "A binding that casts on your target rather than your mouseover is imported",
        "and said so: here it casts on the frame you hover.")
    keysBtn:SetPoint("LEFT", importFS, "RIGHT", 8, 0)
    keysBtn:SetScript("OnClick", function() Report(MD.Practice.ImportKeybinds()) end)

    cellBtn = UI.CreateButton(root, "Cell", "accent-hover", { 60, 20 }, false, false, UI.FONT_SMALL, nil,
        Title("Read Cell's click-castings"), "Takes the bindings Cell would use (its common set, or this spec's).",
        "A macro binding becomes the first heal the macro casts, rank included.",
        "Targeting, the unit menu and anything this addon does not model are listed, not guessed.",
        "Adds to your list: a key you already bound casts the imported spell.")
    cellBtn:SetPoint("LEFT", keysBtn, "RIGHT", 6, 0)
    cellBtn:SetScript("OnClick", function() Report(MD.Practice.ImportCell()) end)

    cliqueBtn = UI.CreateButton(root, "Clique", "accent-hover", { 70, 20 }, false, false, UI.FONT_SMALL, nil,
        Title("Read Clique's bindings"), "Same idea: Clique already spells its keys the way this window does.",
        "Adds to your list: a key you already bound casts the imported spell.")
    cliqueBtn:SetPoint("LEFT", cellBtn, "RIGHT", 6, 0)
    cliqueBtn:SetScript("OnClick", function() Report(MD.Practice.ImportClique()) end)

    statusFS = root:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    statusFS:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 12, 8)
    statusFS:SetWidth(W - 24)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetJustifyV("BOTTOM")
    Status("hover a frame in practice and press one of these.")
end

-- T40: with the manager, the sheet on the Practice pane -- `onPane` when the
-- pane's own "Edit bindings" asks, else the main window opened on Simulate ->
-- Practice first (MD.Win:ShowMain, which may refuse: then nothing opens).
-- Refused in combat (6.6). Returns the sheet or window shown, or nil.
local function ShowSheet(onPane)
    if InCombat() then
        MD:Print("bindings: the bindings sheet does not open in combat")
        return nil
    end
    if not (onPane and onPane:IsVisible()) and not (host and host:IsVisible()) then
        MD.Win:ShowMain("simulate", "practice")
    end
    if not frame then
        if not (onPane and onPane:IsVisible()) then
            onPane = MD.DashboardParts and MD.DashboardParts.PracticeHost and MD.DashboardParts.PracticeHost()
        end
        if not onPane then return nil end
        Build(onPane)
    end
    if not (host and host:IsVisible()) then return nil end
    Render()
    frame:Show()
    -- 6.5: one entry on the ESC stack; the manager's OnHide hook takes it off
    -- however the sheet closes (Done, ESC, its pane hiding)
    MD.Win:Push(frame)
    return frame
end

function MD:ShowBindings(onPane)
    if MD.Win then return ShowSheet(onPane) end
    Build()
    Render()
    frame:Show()
    return frame
end

function MD:ToggleBindings()
    if MD.Win then -- T40
        if frame and frame:IsShown() and host and host:IsVisible() then frame:Hide() else MD:ShowBindings() end
        return
    end
    Build()
    if frame:IsShown() then frame:Hide() else MD:ShowBindings() end
end

-- for tools/practiceui.lua
MD.BindingsWindow = {
    -- T40 (6.4): BW:Build(parent) -- the sheet on a practice pane, built once
    -- (Forever); the window's own Build stays behind MD:ShowBindings on TBC
    Build = function(_, parent) Build(parent); return frame end,
    _frame = function() return frame end,
    _rows = function() return rows end,
    _status = function() return statusFS and statusFS:GetText() or "" end,
}
