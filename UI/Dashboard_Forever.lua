-- Forever's window (T2 of docs/ROADMAP-FOREVER.md): the Cell-style navigation
-- frame from UI/Style.lua (shared) with two groups -- Spells (a placeholder;
-- the spell tables arrive in M2) and Settings -> Modules (switch the three
-- LoadOnDemand siblings on or off). Built on first use, not at load: TBC's
-- own UI/Dashboard.lua stays TBC-only and reads none of this.
--
-- Client calls only through MD.API; nothing here calls one directly (the
-- widget toolkit and WoW's Lua extensions are not client calls -- CLAUDE.md,
-- T1b Facts).
local _, MD = ...
local UI = MD.UI

-- T32 (docs/SPEC-forever-ui.md 6.7): the window's size is the window
-- manager's, one per group (UI/Windows_Forever.lua, MD.Win.SIZES) -- Reports
-- and Simulate at 1036 x 646 for the Review and Practice panes' 912-wide
-- content, Spells and Settings at 860 x 560. The late grow on MODULE_LOADED is
-- gone. These are only the size the frame is built at, before MD.Win places it.
local WIDTH, HEIGHT = 860, 560

local nav, frame

local function Groups()
    return {
        { id = "spells", text = "Spells", views = {
            { id = "book", text = "Spellbook" } } },
        { id = "reports", text = "Reports", views = {
            { id = "review", text = "Review" } } },
        -- T18: a placeholder until the Practice module is on (Files/Rules),
        -- same shape as Reports -> Review's own placeholder-then-module.
        { id = "simulate", text = "Simulate", views = {
            { id = "practice", text = "Practice" } } },
        { id = "settings", text = "Settings", views = {
            { id = "general", text = "General" },
            { id = "modules", text = "Modules" } } },
    }
end

--------------------------------------------------------------------------------
-- Settings -> General
--------------------------------------------------------------------------------
local generalPane

local function RefreshGeneralPane()
    if not generalPane or not generalPane.tooltipCheck then return end
    generalPane.tooltipCheck:SetChecked(MD.db.spellTooltip ~= false)
    if generalPane.clockCheck then
        generalPane.clockCheck:SetChecked(MD.db.clock and MD.db.clock.shown ~= false)
    end
    if generalPane.detailDropdown and MD.SpellTip and MD.SpellTip.DetailMode then
        generalPane.detailDropdown:SetValue(MD.SpellTip:DetailMode())
    end
end

local function BuildGeneralPane(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    local title = pane:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    title:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    title:SetText("General")

    local check = UI.CreateCheckButton(pane, "Add SpellTuner lines to spell tooltips", function(checked)
        MD.db.spellTooltip = checked and true or false
    end)
    check:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -30)
    check:SetChecked(MD.db.spellTooltip ~= false)

    pane.tooltipCheck = check -- marks this pane for tools/tipcheck.lua

    -- T37 (docs/SPEC-forever-ui.md 5.6, decision 5): the key that shows the
    -- block's detail lines. T42 moves it into its titled pane.
    local below = check
    if MD.SpellTip and MD.SpellTip.DETAIL_MODES then
        local detailLabel = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        detailLabel:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 20, -12)
        detailLabel:SetText("Detail lines")
        local dd = UI.CreateDropdown(pane, 120, 18, function(id)
            MD.db.spellTooltipDetail = id
        end)
        dd:SetPoint("LEFT", detailLabel, "RIGHT", 8, 0)
        dd:SetItems(MD.SpellTip.DETAIL_MODES)
        dd:SetValue(MD.SpellTip:DetailMode())
        pane.detailDropdown = dd -- marks this pane for tools/tipcheck.lua
        below = detailLabel
    end

    local clockCheck = UI.CreateCheckButton(pane, "Show the mana clock", function(checked)
        MD.db.clock = MD.db.clock or {}
        MD.db.clock.shown = checked and true or false
        if MD.Clock and MD.Clock.Refresh then MD.Clock:Refresh() end
    end)
    if below == check then
        clockCheck:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 0, -20)
    else
        clockCheck:SetPoint("TOPLEFT", below, "BOTTOMLEFT", -20, -16)
    end
    clockCheck:SetChecked(MD.db.clock and MD.db.clock.shown ~= false)
    pane.clockCheck = clockCheck -- marks this pane for tools/clockcheck.lua

    return pane
end

--------------------------------------------------------------------------------
-- Settings -> Modules
--------------------------------------------------------------------------------
local function ModuleLabel(name)
    for _, m in ipairs(MD.modules or {}) do
        if m.name == name then return m.label end
    end
    return name
end

-- One line, from MD:ModuleState -- ASCII only, the reason already sanitised
-- by Core.lua's registry (a bad LoadAddOn reason becomes "unknown" there).
local function StateText(name)
    local state, reason = MD:ModuleState(name)
    if state == "loaded" then return "loaded" end
    if state == "on" then return "on - loads at login" end
    if state == "failed" then return "could not load: " .. tostring(reason) end
    if state == "unloads" then return "off - unloads at your next /reload" end
    return "off"
end

local modulesPane

local function RefreshModulesPane()
    if not modulesPane or not modulesPane.rows then return end
    for _, m in ipairs(MD.modules or {}) do
        local row = modulesPane.rows[m.name]
        if row then
            row.check:SetChecked(MD.db.modules and MD.db.modules[m.name] == true)
            row.state:SetText(StateText(m.name))
        end
    end
end

local function BuildModulesPane(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    pane.rows = {}

    local title = pane:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    title:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    title:SetText("Modules")

    local prevRow
    for _, m in ipairs(MD.modules or {}) do
        local row = CreateFrame("Frame", nil, pane)
        if prevRow then
            row:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -10)
        else
            row:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -30)
        end
        row:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
        row:SetHeight(48)

        local check = UI.CreateCheckButton(row, m.label, function(checked)
            MD:SetModule(m.name, checked)
            RefreshModulesPane()
        end)
        check:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

        local text = row:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        text:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 19, -2)
        text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        text:SetJustifyH("LEFT")
        text:SetText(m.text or "")

        local anchor = text
        if m.needs and #m.needs > 0 then
            local labels = {}
            for _, n in ipairs(m.needs) do labels[#labels + 1] = ModuleLabel(n) end
            local needsFS = row:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
            needsFS:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -2)
            needsFS:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            needsFS:SetJustifyH("LEFT")
            needsFS:SetText("needs " .. table.concat(labels, ", "))
            anchor = needsFS
        end

        local state = row:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        state:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        state:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        state:SetJustifyH("LEFT")

        pane.rows[m.name] = { check = check, state = state }
        prevRow = row
    end

    return pane
end

--------------------------------------------------------------------------------
-- Spells (T10, docs/tasks/T10-spells-pane.md): the whole book, Heals then
-- Damage then Other, on UI/Dashboard_Rows.lua's shared table widget. Reads
-- only MD.Book, MD.SpellTip, MD.Clock -- no module beyond core (Files/Rules).
--------------------------------------------------------------------------------
local SPELL_COLS = {
    { key = "rank",    x = 8,   w = 56,  label = "Rank" },
    { key = "level",   x = 66,  w = 32,  label = "Lvl" },
    { key = "mana",    x = 100, w = 56,  label = "Mana" },
    { key = "value",   x = 158, w = 64,  label = "Value" },
    { key = "permana", x = 224, w = 64,  label = "Per mana" },
    { key = "persec",  x = 290, w = 60,  label = "Per sec" },
    { key = "cast",    x = 352, w = 46,  label = "Cast" },
    { key = "toOOM",   x = 400, w = 56,  label = "To OOM" },
    { key = "note",    x = 458, w = 180, label = "" },
}
local SPELL_ROW_HEIGHT = 16 -- must track UI/Dashboard_Rows.lua's own ROW_HEIGHT (not exported besides api.rowHeight)

local GREY = "|cff999999"
local RESET = "|r"

-- The probe's own escaping (Client/Probe.lua's Esc, duplicated -- this pane
-- takes no dependency on Client/Probe.lua, Facts/Rules): a literal backslash
-- doubled first, then a pipe as "||", then any non-ASCII/control byte as
-- "\ddd" so rendered/tooltip text and the export stay ASCII with no bare pipe
-- either way. Moved above RenderSpellRow/SpellRowEnter (T10c) since both now
-- put a client-read name on screen, not just in the export.
local function Esc(s)
    if type(s) ~= "string" then return "" end
    local step1 = s:gsub("\\", "\\\\")
    local step2 = step1:gsub("|", "||")
    local step3 = step2:gsub("[^ -~]", function(c) return string.format("\\%03d", c:byte()) end)
    return step3
end

-- A number that is nil renders "-", never 0 (CLAUDE.md); mirrors
-- UI/SpellTip_Forever.lua's own Num, duplicated because that file is not a
-- dependency this pane is allowed to take on (Facts: only Book/SpellTip/Clock).
local function Num(v, decimals)
    if type(v) ~= "number" or v ~= v then return "-" end
    if decimals then return string.format("%." .. decimals .. "f", v) end
    return tostring(math.floor(v + 0.5))
end

-- Review R13: a spell that costs Rage / Focus / Energy costs no mana; its
-- own cost is named ("10 Rage") rather than read as mana or called "free".
-- The power word is Book's own (one of three fixed ASCII words).
local function OtherPowerText(e)
    if e.cost and type(e.cost.power) == "string" and type(e.cost.powerAmount) == "number" then
        return Num(e.cost.powerAmount) .. " " .. e.cost.power
    end
    return nil
end

local function ManaCellText(e)
    local other = OtherPowerText(e)
    if other then return other end
    if e.costState == "free" then return "free" end
    if e.cost then
        if type(e.cost.amount) == "number" then return Num(e.cost.amount) end
        if type(e.cost.percent) == "number" then return Num(e.cost.percent, 0) .. "%" end
    end
    return "-"
end

local function CastCellText(e)
    if e.castKind == "instant" then return "inst" end
    if e.castKind == "channeled" then return "chan" end
    if type(e.cast) == "number" then return Num(e.cast, 1) .. "s" end
    return "-"
end

-- `casts` is the row's own count against the pane's pool (review R38), never
-- the book entry's.
local function ToOOMCellText(casts)
    if casts == math.huge then return "inf" end
    if type(casts) == "number" then return Num(casts, 0) end
    return "-"
end

-- The TBC table's own three words (Rules: "as the TBC table words them"),
-- first match wins; the star on the rank cell already marks "suggested", so
-- this column does not repeat it.
local function NoteCellText(e, family)
    if e.known == false then return "not learned" end
    if e.dominated then return "dominated" end
    if family and family.maxKnown == e then return "max rank" end
    return ""
end

local function ClearCells(row)
    for _, col in ipairs(SPELL_COLS) do row.cells[col.key]:SetText("") end
end

-- opts.render(row, r, color): r.kind picks the shape -- "section" (a Heals/
-- Damage/Other title, T10b: nothing on the pane named where one ended),
-- "family" (a family header + its "suggested: Rank K"), "note" (a gap/stale
-- line under it), "entry" (one rank row, the TBC table's own colour rule),
-- "other" (one line for a kindless family, spec's own four fields).
local function RenderSpellRow(row, r, color)
    if r.kind == "section" then
        ClearCells(row)
        row.cells.wide:SetText(UI.accentHex .. r.text .. RESET)
    elseif r.kind == "family" then
        ClearCells(row)
        local text = Esc(r.family.name)
        if r.family.suggested and r.family.suggested.rank then
            text = text .. "   suggested: Rank " .. tostring(r.family.suggested.rank)
        end
        row.cells.wide:SetText(text)
    elseif r.kind == "note" then
        ClearCells(row)
        row.cells.wide:SetText(GREY .. r.text .. RESET)
    elseif r.kind == "other" then
        ClearCells(row)
        row.cells.wide:SetText(r.text)
    else -- "entry"
        row.cells.wide:SetText("")
        local e = r.entry
        local rankText = e.rank and ("R" .. e.rank) or "-"
        if e.suggested then rankText = rankText .. " *" end
        row.cells.rank:SetText(color .. rankText .. RESET)
        row.cells.level:SetText(color .. Num(e.level) .. RESET)
        row.cells.mana:SetText(color .. ManaCellText(e) .. RESET)
        row.cells.value:SetText(color .. Num(e.value) .. RESET)
        row.cells.permana:SetText(color .. Num(e.perMana, 2) .. RESET)
        row.cells.persec:SetText(color .. Num(e.perSec, 1) .. RESET)
        row.cells.cast:SetText(color .. CastCellText(e) .. RESET)
        row.cells.toOOM:SetText(color .. ToOOMCellText(r.casts) .. RESET)
        row.cells.note:SetText(NoteCellText(e, r.family))
    end
end

-- Hovering a row shows the spell's own tooltip block (T9's builder), anchored
-- to the right of the whole window -- `frame` is this file's own module-level
-- local, the nav window itself, set once CreateDashboard runs.
--
-- T10c: a family or Other row's own line is truncated with "..." on the pane
-- (SetWordWrap(false), UI/Dashboard_Rows.lua), so hovering it must show the
-- full text instead -- a family's name, its suggested rank and how many ranks
-- are listed, or an Other row's name, rank text, mana and cast.
local function OpenSpellTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    if frame then
        GameTooltip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    end
end

local function SpellRowEnter(row, r)
    if not r then return end
    if r.kind == "family" then
        OpenSpellTooltip(row)
        GameTooltip:AddLine(Esc(r.family.name))
        if r.family.suggested and r.family.suggested.rank then
            GameTooltip:AddLine("suggested: Rank " .. tostring(r.family.suggested.rank))
        end
        GameTooltip:AddLine("ranks listed: " .. tostring(#r.family.ranks))
        GameTooltip:Show()
        return
    end
    if r.kind == "other" then
        local rep = r.family and (r.family.maxKnown or r.family.ranks[1])
        if not rep then return end
        OpenSpellTooltip(row)
        GameTooltip:AddLine(Esc(rep.name or ""))
        GameTooltip:AddLine(rep.rankText or "-")
        GameTooltip:AddLine("mana: " .. ManaCellText(rep))
        GameTooltip:AddLine("cast: " .. CastCellText(rep))
        GameTooltip:Show()
        return
    end
    if r.kind ~= "entry" or not r.entry or type(r.entry.id) ~= "number" then return end
    OpenSpellTooltip(row)
    -- T37: the block with its colours (SpellTip:Render); the plain block,
    -- the detail lines with the key (T38 replaces this hover)
    local ok, lines = pcall(MD.SpellTip.Lines, MD.SpellTip, r.entry.id, MD.SpellTip:DetailShown())
    if ok and type(lines) == "table" then
        MD.SpellTip:Render(GameTooltip, lines)
    end
    GameTooltip:Show()
end
local function SpellRowLeave()
    GameTooltip:Hide()
end

-- One flat, ordered list: Heals families, then Damage families (each a
-- "family" header, an optional gap note, an optional stale note, then its
-- ranks), then one "other" line per kindless family (Goal/pane spec). Each
-- rank row carries its own casts to OOM against `pool` (the clock's modelled
-- pool) through Book:CastsFor -- review R38: re-running Book:Rows here wrote
-- the modelled count into the entries Book:Get() shares with the spell
-- tooltip, the clock and the modules, so their "Casts to OOM" flipped between
-- the full pool and the modelled one with the pane's refreshes. The book's
-- entries keep the from-full count Book:Scan() gave them.
local function BuildSpellRows(book, pool)
    local rows = {}
    local function AddFamily(name)
        local fam = book.families[name]
        rows[#rows + 1] = { kind = "family", family = fam }
        if fam.gaps and #fam.gaps > 0 then
            rows[#rows + 1] = { kind = "note",
                text = "Rank " .. table.concat(fam.gaps, ", ") .. " not listed (untrained, or hidden - show all ranks)" }
        end
        local stale = false
        for _, e in ipairs(fam.ranks) do if e.stale then stale = true end end
        if stale then
            rows[#rows + 1] = { kind = "note", text = "values read before combat" }
        end
        for _, e in ipairs(fam.ranks) do
            rows[#rows + 1] = { kind = "entry", entry = e, family = fam, id = e.id,
                known = e.known, suggested = e.suggested, dominated = e.dominated,
                casts = MD.Book:CastsFor(e, pool) }
        end
    end

    -- T10b: a title row before each non-empty section, so a reader can tell
    -- where one ends -- none at all when a section has no family in it.
    local hasHeal, hasDamage = false, false
    for _, name in ipairs(book.order) do
        local kind = book.families[name].kind
        if kind == "heal" then hasHeal = true
        elseif kind == "damage" then hasDamage = true end
    end

    -- T10c: a kindless family is only USEFUL on this table when it has a mana
    -- cost to compare -- a passive or a free spell has nothing to put in Mana/
    -- Per mana/Per second/To OOM. Those are counted, never listed, and the
    -- Export (ExportText) still dumps every one of them (Files/Goal).
    local listedOther, skippedOther = {}, 0
    for _, name in ipairs(book.order) do
        local fam = book.families[name]
        if not fam.kind then
            local rep = fam.maxKnown or fam.ranks[1]
            local hasCost = rep.cost and (rep.cost.amount ~= nil or rep.cost.percent ~= nil)
            if not rep.passive and hasCost then
                listedOther[#listedOther + 1] = fam
            else
                skippedOther = skippedOther + 1
            end
        end
    end
    local hasOther = #listedOther > 0 or skippedOther > 0

    if hasHeal then rows[#rows + 1] = { kind = "section", text = "Heals" } end
    for _, name in ipairs(book.order) do
        if book.families[name].kind == "heal" then AddFamily(name) end
    end
    if hasDamage then rows[#rows + 1] = { kind = "section", text = "Damage" } end
    for _, name in ipairs(book.order) do
        if book.families[name].kind == "damage" then AddFamily(name) end
    end
    if hasOther then rows[#rows + 1] = { kind = "section", text = "Other" } end
    for _, fam in ipairs(listedOther) do
        local rep = fam.maxKnown or fam.ranks[1]
        rows[#rows + 1] = { kind = "other", family = fam,
            text = Esc(fam.name) .. "  " .. (rep.rankText or "-") .. "  " .. ManaCellText(rep) .. "  " .. CastCellText(rep) }
    end
    if skippedOther > 0 then
        rows[#rows + 1] = { kind = "note",
            text = tostring(skippedOther) .. " passives and spells with no mana cost not listed - Export has them" }
    end
    return rows
end

local function ManaLineText(pool)
    if type(pool.mana) == "number" then
        return string.format("Mana %s (modelled %s)", Num(pool.max), Num(pool.mana))
    end
    return string.format("Mana %s, casts to OOM from full", Num(pool.max))
end

local function RefreshSpellbookPane(pane)
    if not (MD.Book and MD.SpellTip) then return end
    local book = MD.Book:Get()
    local pool
    if MD.Clock and MD.Clock.Pool then pool = MD.Clock:Pool() end
    pool = pool or MD.Book:DefaultPool()

    pane.manaLine:SetText(ManaLineText(pool))
    pane.legendLine:SetText("Rank table: * suggested, grey dominated, dark not learned")

    local rows = BuildSpellRows(book, pool)
    pane.lastRows = rows -- tools/spellsui.lua's own hook: the exact render order
    pane.tableApi:Render(rows)
    local height = 4 + 18 + (#rows * SPELL_ROW_HEIGHT) + 8
    pane.tableApi.frame:SetHeight(height)
    if pane.scroll then pane.scroll:SetContentHeight(height) end

    pane.lastRefresh = GetTime()
    pane.refreshCount = (pane.refreshCount or 0) + 1 -- tools/spellsui.lua's own hook
end

-- "<n> Mana" / "<p>% of base mana" / "free" / "unknown" -- the probe's own
-- cost-line words (T8b Facts), read back by tools/refcheck.py's `cost:` field.
local function ExportCostText(e)
    local other = OtherPowerText(e) -- review R13: "10 Rage", the client's own cost-line words
    if other then return other end
    if e.costState == "free" then return "free" end
    if e.cost then
        if type(e.cost.amount) == "number" then return Num(e.cost.amount) .. " Mana" end
        if type(e.cost.percent) == "number" then return Num(e.cost.percent, 0) .. "% of base mana" end
    end
    return "unknown"
end

-- "<s> sec cast" / "Instant" / "Channeled" / "unknown" -- the probe's own
-- tooltip cast-line words, read back by tools/refcheck.py's `cast:` field.
local function ExportCastText(e)
    if e.castKind == "instant" then return "Instant" end
    if e.castKind == "channeled" then return "Channeled" end
    if e.castKind == "cast" and type(e.cast) == "number" then
        return string.format("%.1f sec cast", e.cast)
    end
    return "unknown"
end

-- A plain string, else a one-character placeholder that stays ASCII and
-- never confuses a nil for a real (empty) value in the export's own reader.
local function Str(v)
    return (type(v) == "string") and v or "?"
end

-- MD:ShowCopyPopup("SpellTuner spellbook", text) -- the probe's dump block
-- format (Facts/Files), so tools/refcheck.py reads this export the same way
-- it reads a probe report.
local function ExportText()
    local book = MD.Book:Get()

    local name = MD.API.UnitName("player")
    local realm = MD.API.RealmName()
    local locClass, classToken = MD.API.UnitClass("player")
    if type(locClass) ~= "string" or type(classToken) ~= "string" then classToken = nil end
    local level = MD.API.UnitLevel("player")
    local levelText = (type(level) == "number") and tostring(level) or "?"

    local lines = {}
    lines[#lines + 1] = "character: " .. Str(name) .. " " .. Str(realm) .. " " .. Str(classToken)
        .. " level " .. levelText
    lines[#lines + 1] = "== spells"

    local function DumpFamily(name2)
        for _, e in ipairs(book.families[name2].ranks) do
            lines[#lines + 1] = "spell " .. tostring(e.id)
            lines[#lines + 1] = "  name: " .. Esc(e.name or "")
            lines[#lines + 1] = "  rank: " .. Esc(e.rankText or "")
            lines[#lines + 1] = "  desc: " .. Esc(e.desc or "")
            lines[#lines + 1] = "  cost: " .. ExportCostText(e)
            lines[#lines + 1] = "  cast: " .. ExportCastText(e)
            if type(e.level) == "number" then
                lines[#lines + 1] = "  level: " .. tostring(e.level)
            end
        end
    end

    for _, n in ipairs(book.order) do if book.families[n].kind == "heal" then DumpFamily(n) end end
    for _, n in ipairs(book.order) do if book.families[n].kind == "damage" then DumpFamily(n) end end
    for _, n in ipairs(book.order) do if not book.families[n].kind then DumpFamily(n) end end

    return table.concat(lines, "\n")
end

local function BuildSpellbookPane(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    pane.spellsBook = true -- marks this pane for tools/modulecheck.lua

    local exportBtn = UI.CreateButton(pane, "Export", "accent-hover", { 70, 20 })
    exportBtn:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -4, -4)
    exportBtn:SetScript("OnClick", function()
        MD:ShowCopyPopup("SpellTuner spellbook", ExportText())
    end)
    pane.exportBtn = exportBtn -- marks this pane for tools/spellsui.lua

    local manaLine = pane:CreateFontString(nil, "OVERLAY", UI.FONT)
    manaLine:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    manaLine:SetPoint("RIGHT", exportBtn, "LEFT", -8, 0)
    manaLine:SetJustifyH("LEFT")
    pane.manaLine = manaLine

    local legendLine = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    legendLine:SetPoint("TOPLEFT", manaLine, "BOTTOMLEFT", 0, -2)
    legendLine:SetJustifyH("LEFT")
    pane.legendLine = legendLine

    local scroll = UI.CreateScrollFrame(pane, -42, 4)
    pane.scroll = scroll

    local tableApi = MD.DashboardParts.CreateTable(scroll.content, 620, {
        cols = SPELL_COLS,
        render = RenderSpellRow,
        onEnter = SpellRowEnter,
        onLeave = SpellRowLeave,
    })
    tableApi.frame:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, 0)
    tableApi.frame:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, 0)
    pane.tableApi = tableApi

    -- "refreshed on show and every 2 s while shown" (Goal): the master ticker
    -- runs at 0.5s (Core.lua); this throttles to 2s of its own accord and
    -- never fires at all while the pane (or its window) is hidden.
    MD:OnTick(function()
        if not pane:IsVisible() then return end
        local now = GetTime()
        if not pane.lastRefresh or (now - pane.lastRefresh) >= 2 then
            RefreshSpellbookPane(pane)
        end
    end)

    return pane
end

--------------------------------------------------------------------------------
-- Reports -> Review (T16b, docs/tasks/T16b-review-tab.md): the TBC Review tab
-- (UI/Dashboard_Review.lua, shared) with the Replay module on; a placeholder
-- naming how to switch it on, off. The placeholder never loads the module --
-- only the Modules pane's own switch does (Rules).
--------------------------------------------------------------------------------
local reviewPane        -- the api object MD.DashboardParts.CreateReview hands back
local reviewPlaceholder -- the placeholder frame, while the module is off

local function BuildReviewPlaceholder(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    local text = pane:CreateFontString(nil, "OVERLAY", UI.FONT)
    text:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    text:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetText("Review needs the Replay module - Settings -> Modules")

    pane.reviewPlaceholder = true -- marks this pane for tools/reviewforever.lua
    reviewPlaceholder = pane
    return pane
end

local function BuildReviewPane(content)
    reviewPane = MD.DashboardParts.CreateReview(content, 912)
    reviewPane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    reviewPane.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    return reviewPane.frame
end

local function RefreshReviewPane()
    if reviewPane then reviewPane:Render() end
end

--------------------------------------------------------------------------------
-- Simulate -> Practice (T18, docs/tasks/T18-practice-forever.md): the TBC
-- practice panel (UI/PracticePanel.lua, shared with TBC) with the Practice
-- module on; a placeholder naming how to switch it on while it is off, same
-- shape as Reports -> Review's own (Rules: never loads the module itself).
--------------------------------------------------------------------------------
local practicePane        -- the api object MD.DashboardParts.CreatePractice hands back
local practicePlaceholder -- the placeholder frame, while the module is off

local function BuildPracticePlaceholder(content)
    local pane = CreateFrame("Frame", nil, content)
    pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

    local text = pane:CreateFontString(nil, "OVERLAY", UI.FONT)
    text:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    text:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetText("Practice needs the Practice module - Settings -> Modules")

    pane.practicePlaceholder = true -- marks this pane for tools/practiceforever.lua
    practicePlaceholder = pane
    return pane
end

local function BuildPracticePane(content)
    practicePane = MD.DashboardParts.CreatePractice(content, 912)
    practicePane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    practicePane.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    return practicePane.frame
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local function CreateDashboard()
    if nav then return end -- MD_READY-equivalent callers may ask more than once
    nav = UI.CreateNavFrame("SpellTuner", "SpellTunerDashboard", WIDTH, HEIGHT, Groups(),
        function(group, view, content)
            if group == "spells" and view == "book" then
                return BuildSpellbookPane(content)
            elseif group == "reports" and view == "review" then
                if MD.DashboardParts.CreateReview then
                    return BuildReviewPane(content)
                end
                return BuildReviewPlaceholder(content)
            elseif group == "simulate" and view == "practice" then
                if MD.DashboardParts.CreatePractice then
                    return BuildPracticePane(content)
                end
                return BuildPracticePlaceholder(content)
            elseif group == "settings" and view == "general" then
                generalPane = BuildGeneralPane(content)
                return generalPane
            elseif group == "settings" and view == "modules" then
                modulesPane = BuildModulesPane(content)
                return modulesPane
            end
            return nil
        end,
        function(group, view, pane)
            -- T32: the group's own size, the TOPLEFT kept (6.7)
            if MD.Win then MD.Win:SetGroup("main", group) end
            if group == "settings" and view == "general" then RefreshGeneralPane() end
            if group == "settings" and view == "modules" then RefreshModulesPane() end
            if group == "reports" and view == "review" then RefreshReviewPane() end
            -- "refreshed on show" (Goal): nav:Select runs this on every visit,
            -- the FIRST included -- a plain Show()/OnShow pair would miss the
            -- first one, since a frame is created already shown (CLAUDE.md's
            -- "one owner" rule is about hide/show, not about this).
            if group == "spells" and view == "book" and pane then RefreshSpellbookPane(pane) end
        end, { resizable = true, notUserPlaced = true })
    frame = nav.frame
    -- T32: strata, place, scale, the size per group (6.2, 6.7)
    if MD.Win then MD.Win:Register(frame, { key = "main", role = "host", sizes = MD.Win.SIZES }) end
    tinsert(UISpecialFrames, "SpellTunerDashboard") -- ESC closes

    frame:SetScript("OnShow", function()
        local path = MD.db.uiPath
        if path and path[1] then
            nav:Select(path[1], path[2])
        else
            nav:Select("spells", "book")
        end
    end)
end

function MD:ShowDashboard()
    CreateDashboard()
    if frame then frame:Show() end
end

function MD:ToggleDashboard()
    CreateDashboard()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    elseif MD.Win then
        MD.Win:ShowMain() -- T32: on the remembered view
    else
        frame:Show()
    end
end

-- T32: what MD.Win:ShowMain opens -- the window on the view asked for, or on
-- the remembered one when none is named. Opens the window if closed.
function MD:OpenMainWindow(group, view)
    CreateDashboard()
    if not nav then return end
    if not frame:IsShown() then frame:Show() end
    if group then nav:Select(group, view) end
end

-- Every entry point that wants a particular view goes through here (/st
-- modules today; the same door M2/M3/M4 use). Since T32 (6.3) it goes
-- through the window manager, which T34 teaches the takeover rules.
function MD:SelectView(group, view)
    if MD.Win then return MD.Win:ShowMain(group, view) end
    return MD:OpenMainWindow(group, view)
end

function MD:SelectedView()
    if not nav then return nil end
    return nav:Selected()
end

-- A module can finish loading while the pane is open (the click that
-- switched it on already refreshes; this covers CORE_READY's own login-time
-- loads landing while the window happens to be up from a previous session
-- were that ever possible, and any other module firing MODULE_LOADED later).
MD:RegisterCallback("MODULE_LOADED", RefreshModulesPane)

-- T16b: SpellTuner_Replay finishing load (its own last file, Ready.lua)
-- brings MD.DashboardParts.CreateReview with it. If a placeholder is what the
-- Review view is currently showing, replace it with the real pane --
-- re-selecting it if it happens to be the one on screen, which both shows the
-- new pane (nav.panes already carries it) and refreshes it. (T32: the window
-- no longer grows here -- Reports has its own size, 6.7.)
MD:RegisterCallback("MODULE_LOADED", function(name)
    if name ~= "SpellTuner_Replay" or not MD.DashboardParts.CreateReview then return end
    if nav and nav.panes and nav.panes.reports and nav.panes.reports.review == reviewPlaceholder
            and reviewPlaceholder then
        local content = nav:Content()
        local pane = BuildReviewPane(content)
        nav.panes.reports.review = pane
        reviewPlaceholder:Hide()
        reviewPlaceholder = nil
        if nav.group == "reports" and nav.view == "review" then
            nav:Select("reports", "review")
        end
    end
end)

-- T18: SpellTuner_Practice finishing load brings MD.DashboardParts.CreatePractice
-- with it -- same swap as the Review one above, on the Simulate -> Practice
-- placeholder.
MD:RegisterCallback("MODULE_LOADED", function(name)
    if name ~= "SpellTuner_Practice" or not MD.DashboardParts.CreatePractice then return end
    if nav and nav.panes and nav.panes.simulate and nav.panes.simulate.practice == practicePlaceholder
            and practicePlaceholder then
        local content = nav:Content()
        local pane = BuildPracticePane(content)
        nav.panes.simulate.practice = pane
        practicePlaceholder:Hide()
        practicePlaceholder = nil
        if nav.group == "simulate" and nav.view == "practice" then
            nav:Select("simulate", "practice")
        end
    end
end)
