-- T36 (docs/SPEC-forever-ui.md 3.1-3.4, 3.6; docs/tasks/T36-spells-rail-picker.md):
-- the Forever window's Spells group, split out of UI/Dashboard_Forever.lua.
--
-- The group is a rail group (UI.CreateNavFrame's layout = "rail", T31): no
-- view row, a 172-px list down the content's left edge -- MY SPELLS,
-- Overview, then one row per family of the player's own list
-- (Spells/Tabs.lua, T35), each row a real nav view ("fam:<family>"), so
-- db.uiPath remembers it and MD:SelectView("spells", "fam:Rejuvenation")
-- works. [ + Add ] opens the picker, a sheet over the spell view only (the
-- rail stays live under it); a spell dragged from the spellbook onto the rail
-- goes in at the drop row, read through MD.API.CursorInfo -- the cursor is
-- NEVER cleared (a spell picked off an action bar is off the bar; clearing it
-- would delete the player's button). /st spell <name> opens a family's view,
-- or its preview with a banner when it is not in the list.
--
-- What each view shows is T36's interim: Overview is today's Spellbook table
-- (T10-T10c, the review's R13/R38, Export) until T39 turns it into My spells /
-- Whole book, and a family's view is a header over that family's rows of the
-- same table until T38 builds the view of 3.5.
--
-- Forever TOCs only. Client data only through MD.API (the book, the clock,
-- the cursor); the widget toolkit is not a client call (CLAUDE.md, T1b).
local _, MD = ...
local UI = MD.UI

local SpellsPane = {}
MD.SpellsPane = SpellsPane

-- 3.2 / 4.3 metrics at font offset 0; every vertical pitch below goes through
-- UI.Pitch (4.2), so it grows with a positive offset.
local RAIL_ROW = 20
local FOOTER_H = 48         -- [ + Add ] and the Undo line above it
local HEADER_H = 48         -- a family view's header
local BANNER_H = 20         -- the preview banner
local PICKER_W, PICKER_H = 300, 400
local PICKER_ROW = 20
local PICKER_SECTION = 22   -- a section title, its rule at -17
local VIEW_PREFIX = "fam:"

local function Pitch(n)
    if UI.Pitch then return UI.Pitch(n) end
    return n
end

-- A theme token's colour code / r, g, b, with the flat literal as fallback
-- (the theme is always listed before this file on Forever).
local function Hex(token, fallback)
    local t = UI.TEXT and UI.TEXT[token]
    return (t and t.hex) or fallback
end
local function SetColor(fs, token, r, g, b)
    local t = UI.TEXT and UI.TEXT[token]
    if t then fs:SetTextColor(t[1], t[2], t[3]) else fs:SetTextColor(r, g, b) end
end

local GREY = "|cff999999"
local RESET = "|r"

-- The probe's own escaping (Client/Probe.lua's Esc, duplicated -- this pane
-- takes no dependency on Client/Probe.lua): a literal backslash doubled
-- first, then a pipe as "||", then any non-ASCII/control byte as "\ddd", so
-- every client-read name on screen, in a tooltip or in the export stays ASCII
-- with no bare pipe.
local function Esc(s)
    if type(s) ~= "string" then return "" end
    local step1 = s:gsub("\\", "\\\\")
    local step2 = step1:gsub("|", "||")
    local step3 = step2:gsub("[^ -~]", function(c) return string.format("\\%03d", c:byte()) end)
    return step3
end

-- A number that is nil renders "-", never 0 (CLAUDE.md).
local function Num(v, decimals)
    if type(v) ~= "number" or v ~= v then return "-" end
    if decimals then return string.format("%." .. decimals .. "f", v) end
    return tostring(math.floor(v + 0.5))
end

local function Book() return MD.Book end
local function Tabs() return MD.Tabs end

local function FamilyKey(viewId)
    if type(viewId) == "string" and viewId:sub(1, #VIEW_PREFIX) == VIEW_PREFIX then
        return viewId:sub(#VIEW_PREFIX + 1)
    end
    return nil
end

local function AllPassive(fam)
    local any = false
    for _, e in ipairs(fam.ranks or {}) do
        any = true
        if e.passive ~= true then return false end
    end
    return any
end

local function InCombat()
    local v = MD.API.UnitAffectingCombat and MD.API.UnitAffectingCombat("player")
    return v == true
end

--------------------------------------------------------------------------------
-- Today's Spellbook table (T10, docs/tasks/T10-spells-pane.md), moved here
-- whole: Heals then Damage then Other on UI/Dashboard_Rows.lua's shared table
-- widget. The note column is 90 wide (was 180) so the table fits the 556-px
-- view right of the rail; its three words fit.
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
    { key = "note",    x = 458, w = 90,  label = "" },
}
local TABLE_W = 548
local SPELL_ROW_HEIGHT = 16 -- UI/Dashboard_Rows.lua's own ROW_HEIGHT; its cells use GameFontHighlightSmall, which the font offset does not size

-- Review R13: a spell that costs Rage / Focus / Energy costs no mana; its
-- own cost is named ("10 Rage") rather than read as mana or called "free".
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

local function NoteCellText(e, family)
    if e.known == false then return "not learned" end
    if e.dominated then return "dominated" end
    if family and family.maxKnown == e then return "max rank" end
    return ""
end

local function ClearCells(row)
    for _, col in ipairs(SPELL_COLS) do row.cells[col.key]:SetText("") end
end

-- opts.render(row, r, color): r.kind picks the shape -- "section", "family",
-- "note", "entry", "other" (T10b/T10c).
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

-- Hovering a row shows the spell's tooltip block beside the window (T38
-- moves it beside the row, with the game's own tooltip).
local function OpenSpellTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    local frame = SpellsPane.nav and SpellsPane.nav.frame
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

-- One family's rows: its header, a gap note, a stale note, then its ranks,
-- each carrying its own casts to OOM against `pool` (review R38: never
-- written into the book's shared entries).
local function AddFamilyRows(rows, fam, pool)
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

-- The whole book: Heals, then Damage, then one "other" line per kindless
-- family cast for mana (T10c: the rest counted, never listed; Export has
-- every one).
local function BuildSpellRows(book, pool)
    local rows = {}
    local hasHeal, hasDamage = false, false
    for _, name in ipairs(book.order) do
        local kind = book.families[name].kind
        if kind == "heal" then hasHeal = true
        elseif kind == "damage" then hasDamage = true end
    end

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
        if book.families[name].kind == "heal" then AddFamilyRows(rows, book.families[name], pool) end
    end
    if hasDamage then rows[#rows + 1] = { kind = "section", text = "Damage" } end
    for _, name in ipairs(book.order) do
        if book.families[name].kind == "damage" then AddFamilyRows(rows, book.families[name], pool) end
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

local function Pool()
    local pool
    if MD.Clock and MD.Clock.Pool then pool = MD.Clock:Pool() end
    return pool or MD.Book:DefaultPool()
end

local function ManaLineText(pool)
    if type(pool.mana) == "number" then
        return string.format("Mana %s (modelled %s)", Num(pool.max), Num(pool.mana))
    end
    return string.format("Mana %s, casts to OOM from full", Num(pool.max))
end

--------------------------------------------------------------------------------
-- Export: the probe's dump block format, so tools/refcheck.py reads it the
-- way it reads a probe report. Scope: the whole book (3.6).
--------------------------------------------------------------------------------
local function ExportCostText(e)
    local other = OtherPowerText(e)
    if other then return other end
    if e.costState == "free" then return "free" end
    if e.cost then
        if type(e.cost.amount) == "number" then return Num(e.cost.amount) .. " Mana" end
        if type(e.cost.percent) == "number" then return Num(e.cost.percent, 0) .. "% of base mana" end
    end
    return "unknown"
end

local function ExportCastText(e)
    if e.castKind == "instant" then return "Instant" end
    if e.castKind == "channeled" then return "Channeled" end
    if e.castKind == "cast" and type(e.cast) == "number" then
        return string.format("%.1f sec cast", e.cast)
    end
    return "unknown"
end

local function Str(v)
    return (type(v) == "string") and v or "?"
end

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

--------------------------------------------------------------------------------
-- The Overview view: today's Spellbook table and Export (T39 rebuilds it)
--------------------------------------------------------------------------------
local function RefreshOverview(pane)
    if not (MD.Book and MD.SpellTip) then return end
    local book = MD.Book:Get()
    local pool = Pool()

    pane.manaLine:SetText(ManaLineText(pool))
    pane.legendLine:SetText("Rank table: * suggested, grey dominated, dark not learned - click a spell to open it")

    local rows = BuildSpellRows(book, pool)
    pane.lastRows = rows -- tools/spellsui.lua's own hook: the exact render order
    pane.tableApi:Render(rows)
    local height = 4 + 18 + (#rows * SPELL_ROW_HEIGHT) + 8
    pane.tableApi.frame:SetHeight(height)
    if pane.scroll then pane.scroll:SetContentHeight(height) end

    pane.lastRefresh = GetTime()
    pane.refreshCount = (pane.refreshCount or 0) + 1 -- tools/spellsui.lua's own hook
end

-- A click on a family (its header or one of its ranks) opens it: its view
-- when it is in the list, else its preview (3.6).
local function OverviewClick(_, r)
    local fam = r and r.family
    if type(fam) ~= "table" or type(fam.name) ~= "string" then return end
    SpellsPane:OpenFamily(fam.key or fam.name)
end

local function BuildOverview(host)
    local pane = CreateFrame("Frame", nil, host)
    pane:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    pane.spellsBook = true -- marks this pane for tools/modulecheck.lua / tools/spellsui.lua

    local exportBtn = UI.CreateButton(pane, "Export", "accent-hover", { 70, 20 })
    exportBtn:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -4, -4)
    exportBtn:SetScript("OnClick", function()
        MD:ShowCopyPopup("SpellTuner spellbook", ExportText())
    end)
    pane.exportBtn = exportBtn

    local manaLine = pane:CreateFontString(nil, "OVERLAY", UI.FONT)
    manaLine:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -4)
    manaLine:SetPoint("RIGHT", exportBtn, "LEFT", -8, 0)
    manaLine:SetJustifyH("LEFT")
    pane.manaLine = manaLine

    local legendLine = pane:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    legendLine:SetPoint("TOPLEFT", manaLine, "BOTTOMLEFT", 0, -2)
    legendLine:SetPoint("RIGHT", pane, "RIGHT", -4, 0)
    legendLine:SetJustifyH("LEFT")
    legendLine:SetWordWrap(false)
    pane.legendLine = legendLine

    local scroll = UI.CreateScrollFrame(pane, -42, 4)
    pane.scroll = scroll

    local tableApi = MD.DashboardParts.CreateTable(scroll.content, TABLE_W, {
        cols = SPELL_COLS,
        render = RenderSpellRow,
        onEnter = SpellRowEnter,
        onLeave = SpellRowLeave,
        onClick = OverviewClick,
    })
    tableApi.frame:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, 0)
    tableApi.frame:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, 0)
    pane.tableApi = tableApi

    -- refreshed on show and every 2 s while shown (T10's Goal); the master
    -- ticker runs at 0.5 s and this never fires while the pane is hidden
    MD:OnTick(function()
        if not pane:IsVisible() then return end
        local now = GetTime()
        if not pane.lastRefresh or (now - pane.lastRefresh) >= 2 then
            RefreshOverview(pane)
        end
    end)
    return pane
end

--------------------------------------------------------------------------------
-- A family's view (T36's interim: T38 builds 3.5 in its place): the preview
-- banner, a header (icon, name, what it is, the modelled pool) and the
-- family's rows of the table above; a family the book no longer has says so,
-- with its [Remove].
--------------------------------------------------------------------------------
local function KindWord(kind)
    if kind == "heal" then return "Heal" end
    if kind == "damage" then return "Damage" end
    return "Utility"
end

local function SubText(fam)
    local known = 0
    for _, e in ipairs(fam.ranks or {}) do if e.known ~= false then known = known + 1 end end
    local top = fam.maxKnown and fam.maxKnown.rank
    if type(top) == "number" then
        return string.format("%s - Rank %d of %d known", KindWord(fam.kind), top, known)
    end
    return KindWord(fam.kind) .. " - not learned yet"
end

local function HeaderManaText(pool)
    if type(pool) == "table" and type(pool.mana) == "number" and type(pool.max) == "number" then
        return Hex("mana", "|cff4d99ff") .. "~" .. Num(pool.mana) .. RESET .. " / " .. Num(pool.max) .. " mana"
    end
    return Hex("muted", "|cff7a7a7a") .. "mana not modelled yet" .. RESET
end

local function LayoutFamily(f)
    local top = 0
    f.banner:SetHeight(Pitch(BANNER_H))
    if f.banner:IsShown() then top = Pitch(BANNER_H) + 6 end
    f.header:ClearAllPoints()
    f.header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
    f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -top)
    f.header:SetHeight(Pitch(HEADER_H))
    local below = top + Pitch(HEADER_H) + 12
    f.staleText:ClearAllPoints()
    f.staleText:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -below)
    f.staleText:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    f.scroll:Resize(-below, 4)
end

local function BuildFamily(host)
    local f = CreateFrame("Frame", nil, host)
    f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    f.spellsFamily = true -- marks this pane for tools/spellsui.lua

    -- the preview banner (3.6): "Not in your list.  [+ Add to my spells]"
    local banner = CreateFrame("Frame", nil, f, "BackdropTemplate")
    banner:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    banner:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    banner:SetHeight(Pitch(BANNER_H))
    local P = UI.PALETTE or {}
    UI.StylizeFrame(banner, P.suggested or P.pane or { 0.13, 0.13, 0.13, 1 }, P.border or { 0, 0, 0, 1 })
    banner.text = banner:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    banner.text:SetPoint("LEFT", banner, "LEFT", 8, 0)
    banner.text:SetJustifyH("LEFT")
    SetColor(banner.text, "text2", 0.7, 0.7, 0.7)
    banner.text:SetText("Not in your list.")
    banner.addBtn = UI.CreateButton(banner, "+ Add to my spells", "accent-hover", { 130, 16 },
        false, false, UI.FONT_SMALL, UI.FONT_SMALL)
    banner.addBtn:SetPoint("LEFT", banner.text, "RIGHT", 10, 0)
    banner.addBtn:SetScript("OnClick", function()
        local key = SpellsPane.preview
        if key then SpellsPane:AddFromPreview(key) end
    end)
    banner:Hide()
    f.banner = banner
    SpellsPane.banner = banner

    -- the header: a 32x32 icon with a 1-px black border, the name, what it
    -- is, and the modelled pool at the right
    local header = CreateFrame("Frame", nil, f)
    header.iconEdge = header:CreateTexture(nil, "ARTWORK")
    header.iconEdge:SetSize(34, 34)
    header.iconEdge:SetPoint("LEFT", header, "LEFT", 4, 0)
    header.iconEdge:SetColorTexture(0, 0, 0, 1)
    header.icon = header:CreateTexture(nil, "OVERLAY")
    header.icon:SetSize(32, 32)
    header.icon:SetPoint("LEFT", header, "LEFT", 5, 0)
    header.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    header.name = header:CreateFontString(nil, "OVERLAY", UI.FONT_HEAD or UI.FONT_TITLE)
    header.name:SetPoint("TOPLEFT", header, "TOPLEFT", 46, -6)
    header.name:SetJustifyH("LEFT")
    header.name:SetWordWrap(false)
    header.sub = header:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    header.sub:SetPoint("TOPLEFT", header.name, "BOTTOMLEFT", 0, -4)
    header.sub:SetJustifyH("LEFT")
    SetColor(header.sub, "text2", 0.7, 0.7, 0.7)
    header.mana = header:CreateFontString(nil, "OVERLAY", UI.FONT_NUM or UI.FONT)
    header.mana:SetPoint("TOPRIGHT", header, "TOPRIGHT", -4, -8)
    header.mana:SetJustifyH("RIGHT")
    f.header = header

    -- a family the book no longer has (3.3)
    f.staleText = f:CreateFontString(nil, "OVERLAY", UI.FONT)
    f.staleText:SetJustifyH("LEFT")
    SetColor(f.staleText, "text2", 0.7, 0.7, 0.7)
    f.staleText:Hide()
    f.removeBtn = UI.CreateButton(f, "Remove", "accent-hover", { 70, 20 })
    f.removeBtn:SetPoint("TOPLEFT", f.staleText, "BOTTOMLEFT", 0, -8)
    f.removeBtn:SetScript("OnClick", function()
        if f.key then SpellsPane:Remove(f.key) end
    end)
    f.removeBtn:Hide()

    f.scroll = UI.CreateScrollFrame(f, -(HEADER_H + 12), 4)
    f.tableApi = MD.DashboardParts.CreateTable(f.scroll.content, TABLE_W, {
        cols = SPELL_COLS,
        render = RenderSpellRow,
        onEnter = SpellRowEnter,
        onLeave = SpellRowLeave,
    })
    f.tableApi.frame:SetPoint("TOPLEFT", f.scroll.content, "TOPLEFT", 0, 0)
    f.tableApi.frame:SetPoint("TOPRIGHT", f.scroll.content, "TOPRIGHT", 0, 0)

    LayoutFamily(f)

    MD:OnTick(function()
        if not f:IsVisible() or not f.key then return end
        local now = GetTime()
        if not f.lastRefresh or (now - f.lastRefresh) >= 2 then
            SpellsPane:RenderFamily(f.key, f.preview)
        end
    end)
    return f
end

function SpellsPane:RenderFamily(key, preview)
    local f = self.family
    if not f then return end
    f.key, f.preview = key, preview and true or false
    f.lastRefresh = GetTime()
    if preview then f.banner:Show() else f.banner:Hide() end
    LayoutFamily(f)

    local book = MD.Book:Get()
    local fam = MD.Tabs:Resolve(key, book)
    if type(fam) ~= "table" then
        -- 3.3: kept, greyed, never dropped silently
        f.header.icon:Hide(); f.header.iconEdge:Hide()
        f.header.name:SetText(Esc(key))
        SetColor(f.header.name, "disabled", 0.3, 0.3, 0.3)
        f.header.sub:SetText("")
        f.header.mana:SetText("")
        f.staleText:SetText(Esc(key) .. " is not in this character's spellbook.")
        f.staleText:Show()
        f.removeBtn:Show()
        f.tableApi:Render({})
        f.scroll:Hide()
        f.lastRows = {}
        return
    end
    f.staleText:Hide()
    f.removeBtn:Hide()
    f.scroll:Show()

    local rep = fam.maxKnown or fam.ranks[1]
    if rep and rep.icon then
        f.header.icon:SetTexture(rep.icon); f.header.icon:Show(); f.header.iconEdge:Show()
    else
        f.header.icon:Hide(); f.header.iconEdge:Hide()
    end
    f.header.name:SetText(Esc(fam.name or key))
    SetColor(f.header.name, "text", 1, 1, 1)
    f.header.sub:SetText(SubText(fam))
    local pool = Pool()
    f.header.mana:SetText(HeaderManaText(pool))

    local rows = {}
    AddFamilyRows(rows, fam, pool)
    f.lastRows = rows
    f.tableApi:Render(rows)
    local height = 4 + 18 + (#rows * SPELL_ROW_HEIGHT) + 8
    f.tableApi.frame:SetHeight(height)
    f.scroll:SetContentHeight(height)
    f.refreshCount = (f.refreshCount or 0) + 1
end

--------------------------------------------------------------------------------
-- The list: rail rows from Spells/Tabs.lua (3.2, 3.3)
--------------------------------------------------------------------------------
-- The rail's views: Overview, then one per listed family. The first call
-- with a book seeds the list (the seed runs on first open).
function SpellsPane:Views()
    local views = { { id = "overview", text = "Overview", fixed = true } }
    if not (MD.Book and MD.Tabs) then return views end
    local book = MD.Book:Get()
    for _, key in ipairs(MD.Tabs:Get(book)) do
        local fam = MD.Tabs:Resolve(key, book)
        if type(fam) == "table" then
            local rep = fam.maxKnown or (fam.ranks and fam.ranks[1])
            local rank = fam.suggested and fam.suggested.rank
            views[#views + 1] = { id = VIEW_PREFIX .. key, key = key, text = Esc(fam.name or key),
                icon = rep and rep.icon or nil,
                tag = (type(rank) == "number") and ("R" .. rank) or nil,
                new = MD.Tabs:IsNew(key) }
        else
            views[#views + 1] = { id = VIEW_PREFIX .. key, key = key, text = Esc(key),
                stale = true, tooltip = "not in your spellbook" }
        end
    end
    return views
end

local function SpellsGroup(nav)
    for _, g in ipairs(nav.groups or {}) do
        if g.id == "spells" then return g end
    end
    return nil
end

local function SameIds(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i].id ~= b[i].id then return false end end
    return true
end

-- The rail follows the list. A change in which rows there are (or their
-- order) is nav:SetViews (3.1: every row a view); anything else -- a tag, the
-- new dot, a stale name -- repaints the rows in place, so the view on screen
-- is not re-selected under the player.
function SpellsPane:RefreshRail()
    local nav = self.nav
    if not nav then return end
    if self.busy then self.railPending = true; return end
    self.busy = true
    local ok, err = pcall(function()
        local views = self:Views()
        local g = SpellsGroup(nav)
        if g and g.views and SameIds(g.views, views) then
            g.views = views
            local rail = nav:Rail("spells")
            if rail then
                rail:SetRows(views)
                if self.preview and nav.group == "spells" then rail:Select(nil) end
            end
        else
            nav:SetViews("spells", views)
        end
        self:RefreshFooter()
    end)
    self.busy = false
    if self.railPending then
        self.railPending = false
        self:RefreshRail()
    end
    if not ok then error(err, 0) end
end

-- One change to the list: the rail, the picker's ticks and the Undo line
-- all follow it.
function SpellsPane:ListChanged()
    self:RefreshRail()
    if self.picker and self.picker:IsShown() then self:RefreshPicker() end
end

function SpellsPane:Remove(key)
    if MD.Tabs:Remove(key) then self:ListChanged() end
end

function SpellsPane:Undo()
    if MD.Tabs:Undo() then self:ListChanged() end
end

-- The rail's footer: [ + Add ] pinned at the bottom, and after a removal the
-- line above it reads "Wrath removed  [Undo]" until the next change.
function SpellsPane:RefreshFooter()
    if not self.undoText then return end
    local key = MD.Tabs and MD.Tabs:UndoKey()
    if key then
        self.undoText:SetText(Esc(key) .. " removed")
        self.undoText:Show()
        self.undoBtn:Show()
    else
        self.undoText:SetText("")
        self.undoText:Hide()
        self.undoBtn:Hide()
    end
end

local function BuildFooter(rail)
    local footer = rail:Footer()
    local add = UI.CreateButton(footer, "+ Add", "accent-hover", { 164, 20 })
    add:SetPoint("BOTTOM", footer, "BOTTOM", 0, 3)
    add:SetScript("OnClick", function() SpellsPane:OpenPicker() end)
    SpellsPane.addBtn = add

    local undoText = footer:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    undoText:SetPoint("BOTTOMLEFT", add, "TOPLEFT", 5, 8)
    undoText:SetJustifyH("LEFT")
    SetColor(undoText, "text2", 0.7, 0.7, 0.7)
    SpellsPane.undoText = undoText

    local undo = UI.CreateButton(footer, "Undo", "accent-hover", { 44, 16 }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL)
    undo:SetPoint("LEFT", undoText, "RIGHT", 8, 0)
    undo:SetScript("OnClick", function() SpellsPane:Undo() end)
    SpellsPane.undoBtn = undo
    SpellsPane:RefreshFooter()
end

--------------------------------------------------------------------------------
-- The drop from the spellbook (3.2): the family of the spell on the cursor
-- goes in at the drop row (moved there when it is listed already). The
-- cursor is read, never cleared: the spell stays on it after the drop.
--------------------------------------------------------------------------------
local function FamilyOfSpell(id, book)
    local e = book.spells and book.spells[id]
    if type(e) == "table" and type(e.name) == "string" and book.families[e.name] then
        return e.name
    end
    -- a rank the book does not list under this id: the family by the spell's name
    local name = MD.API.SpellName and MD.API.SpellName(id)
    if type(name) == "string" and not MD.API.IsSecret(name) and book.families[name] then
        return name
    end
    return nil
end

function SpellsPane:CanDrop()
    local kind = MD.API.CursorInfo and MD.API.CursorInfo()
    return kind == "spell"
end

function SpellsPane:Drop(at)
    if not MD.API.CursorInfo then return end
    local kind, id = MD.API.CursorInfo()
    if kind ~= "spell" or type(id) ~= "number" then return end
    local book = MD.Book:Get()
    local key = FamilyOfSpell(id, book)
    if not key then
        MD:Debug("other", "spells rail: dropped spell %s is in no family of the book", tostring(id))
        return
    end
    local order = MD.Tabs:Get()
    local from
    for i, k in ipairs(order) do if k == key then from = i end end
    if from then
        local to = at
        if type(to) ~= "number" then to = #order end
        if to > from then to = to - 1 end
        MD.Tabs:Move(key, to)
    else
        MD.Tabs:Add(key, at, book)
    end
    if self.preview == key then self.preview = nil end
    self:ListChanged()
end

--------------------------------------------------------------------------------
-- The picker sheet (3.4): over the spell view only, the rail live beside it
--------------------------------------------------------------------------------
local function Section(fam)
    if fam.kind == "heal" then return "heal" end
    if fam.kind == "damage" then return "damage" end
    return "other"
end
local SECTIONS = { { id = "heal", title = "HEALS" }, { id = "damage", title = "DAMAGE" }, { id = "other", title = "OTHER" } }

local function RankRange(fam)
    local lo, hi
    for _, e in ipairs(fam.ranks or {}) do
        if type(e.rank) == "number" then
            if not lo or e.rank < lo then lo = e.rank end
            if not hi or e.rank > hi then hi = e.rank end
        end
    end
    if not lo then return "" end
    if lo == hi then return "R" .. lo end
    return "R" .. lo .. " - R" .. hi
end

local function PickerSectionFrame(p, i)
    local s = p.sectionPool[i]
    if s then return s end
    s = CreateFrame("Frame", nil, p.scroll.content)
    s.title = s:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    s.title:SetPoint("TOPLEFT", s, "TOPLEFT", 2, -2)
    s.title:SetJustifyH("LEFT")
    local a = UI.TEXT and UI.TEXT.accent or UI.accent
    s.title:SetTextColor(a[1], a[2], a[3])
    s.rule = s:CreateTexture(nil, "ARTWORK")
    s.rule:SetHeight(1)
    s.rule:SetPoint("TOPLEFT", s, "TOPLEFT", 2, -17)
    s.rule:SetPoint("TOPRIGHT", s, "TOPRIGHT", -2, -17)
    local rc = UI.PALETTE and UI.PALETTE.rule or { a[1], a[2], a[3], 0.6 }
    s.rule:SetColorTexture(rc[1], rc[2], rc[3], rc[4] or 0.6)
    p.sectionPool[i] = s
    return s
end

local function PickerRowFrame(p, i)
    local r = p.rowPool[i]
    if r then return r end
    r = CreateFrame("Frame", nil, p.scroll.content)
    r.check = UI.CreateCheckButton(r, "", function(checked)
        if not r.key then return end
        if checked then
            MD.Tabs:Add(r.key, nil)
            if SpellsPane.preview == r.key then SpellsPane.preview = nil end
        else
            MD.Tabs:Remove(r.key)
        end
        SpellsPane:ListChanged()
    end)
    r.check:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.iconEdge = r:CreateTexture(nil, "ARTWORK")
    r.iconEdge:SetSize(18, 18)
    r.iconEdge:SetPoint("LEFT", r, "LEFT", 23, 0)
    r.iconEdge:SetColorTexture(0, 0, 0, 1)
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetSize(16, 16)
    r.icon:SetPoint("LEFT", r, "LEFT", 24, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.range = r:CreateFontString(nil, "OVERLAY", UI.FONT_NUM_SMALL or UI.FONT_SMALL)
    r.range:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.range:SetJustifyH("RIGHT")
    SetColor(r.range, "muted", 0.48, 0.48, 0.48)
    r.name = r:CreateFontString(nil, "OVERLAY", UI.FONT)
    r.name:SetPoint("LEFT", r, "LEFT", 46, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", -64, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    p.rowPool[i] = r
    return r
end

function SpellsPane:RefreshPicker()
    local p = self.picker
    if not p then return end
    local book = MD.Book:Get()
    local filter = (p.search:GetText() or ""):lower()
    if filter == "" then p.placeholder:Show() else p.placeholder:Hide() end

    for _, s in ipairs(p.sectionPool) do s:Hide() end
    for _, r in ipairs(p.rowPool) do r:Hide(); r.key = nil end
    p.rows = p.rowPool

    local y, ns, nr = 0, 0, 0
    local rowH = Pitch(PICKER_ROW)
    for _, sec in ipairs(SECTIONS) do
        local list = {}
        for _, name in ipairs(book.order) do
            local fam = book.families[name]
            if Section(fam) == sec.id and not AllPassive(fam)
                and (filter == "" or name:lower():find(filter, 1, true)) then
                list[#list + 1] = fam
            end
        end
        if #list > 0 then
            ns = ns + 1
            local s = PickerSectionFrame(p, ns)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", p.scroll.content, "TOPLEFT", 0, -y)
            s:SetPoint("TOPRIGHT", p.scroll.content, "TOPRIGHT", 0, -y)
            s:SetHeight(Pitch(PICKER_SECTION))
            s.title:SetText(sec.title)
            s:Show()
            y = y + Pitch(PICKER_SECTION)
            for _, fam in ipairs(list) do
                nr = nr + 1
                local r = PickerRowFrame(p, nr)
                local key = fam.key or fam.name
                r.key, r.section = key, sec.id
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", p.scroll.content, "TOPLEFT", 0, -y)
                r:SetPoint("TOPRIGHT", p.scroll.content, "TOPRIGHT", 0, -y)
                r:SetHeight(rowH)
                local rep = fam.maxKnown or fam.ranks[1]
                if rep and rep.icon then
                    r.icon:SetTexture(rep.icon); r.icon:Show(); r.iconEdge:Show()
                else
                    r.icon:Hide(); r.iconEdge:Hide()
                end
                r.name:SetText(Esc(fam.name or key))
                r.range:SetText(RankRange(fam))
                r.check:SetChecked(MD.Tabs:Has(key))
                r:Show()
                y = y + rowH - 1
            end
            y = y + 6
        end
    end
    p.scroll.content:SetHeight(math.max(y, 2))
end

local function BuildPicker()
    local nav = SpellsPane.nav
    local rail = nav:Rail("spells")
    local view = nav:RailView("spells")
    local p = UI.CreateSheet(view, view, PICKER_W, PICKER_H, "ADD SPELLS")
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", rail.frame, "TOPRIGHT", 4, 0)
    p.spellsPicker = true -- marks the sheet for tools/spellsui.lua
    p.sectionPool, p.rowPool, p.rows = {}, {}, {}
    local body = p:Body()

    local search = UI.CreateEditBox(body, PICKER_W - 18, 20)
    search:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -6)
    search:SetScript("OnTextChanged", function() SpellsPane:RefreshPicker() end)
    p.search = search
    local placeholder = search:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    placeholder:SetPoint("LEFT", search, "LEFT", 6, 0)
    SetColor(placeholder, "muted", 0.48, 0.48, 0.48)
    placeholder:SetText("search...")
    p.placeholder = placeholder

    local holder = CreateFrame("Frame", nil, body)
    holder:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -34)
    holder:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 66)
    p.scroll = UI.CreateScrollFrame(holder, 0, 0)

    local tip = body:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    tip:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 8, 34)
    tip:SetPoint("RIGHT", body, "RIGHT", -8, 0)
    tip:SetJustifyH("LEFT")
    SetColor(tip, "muted", 0.48, 0.48, 0.48)
    tip:SetText("Tip: drag a spell from your spellbook onto the list.")
    p.tip = tip

    local reset = UI.CreateButton(body, "Reset to my heals", "accent-hover", { 130, 20 })
    reset:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 6, 6)
    reset:SetScript("OnClick", function()
        MD.Tabs:Reset()
        SpellsPane.preview = nil
        SpellsPane:ListChanged()
    end)
    p.resetBtn = reset

    local done = UI.CreateButton(body, "Done", "accent-hover", { 70, 20 })
    done:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -6, 6)
    done:SetScript("OnClick", function() p:Hide() end)
    p.doneBtn = done

    SpellsPane.picker = p
    return p
end

-- [ + Add ]: the picker, refused in combat (6.6).
function SpellsPane:OpenPicker()
    if not self.nav then return end
    if InCombat() then
        MD:Print("spells: the picker does not open in combat")
        return
    end
    local p = self.picker or BuildPicker()
    p:Show()
    -- 6.5: a sheet is an entry on T33's ESC stack (one ESC closes the picker,
    -- not the window); Done, the window hiding or the combat hide take it off
    -- through the manager's OnHide hook.
    if MD.Win and MD.Win.Push then MD.Win:Push(p) end
    self:RefreshPicker()
end

--------------------------------------------------------------------------------
-- Selection, the preview, /st spell
--------------------------------------------------------------------------------
local function ShowOnly(which)
    local s = SpellsPane
    if s.overview then if which == "overview" then s.overview:Show() else s.overview:Hide() end end
    if s.family then if which == "family" then s.family:Show() else s.family:Hide() end end
end

-- onShow for the group (UI/Dashboard_Forever.lua): Overview, a family's view,
-- or -- on Overview while a preview is asked for -- that family's view with
-- the banner, no rail row selected (it is not in the list).
function SpellsPane:Show(view)
    if not self.host then return end
    local key = FamilyKey(view)
    if key then
        self.preview = nil
        ShowOnly("family")
        self:RenderFamily(key, false)
        if MD.Tabs:IsNew(key) then
            MD.Tabs:MarkSeen(key)
            self:RefreshRail()
        end
        return
    end
    local pv = self.preview
    if pv and MD.Tabs:Has(pv) then pv = nil; self.preview = nil end
    if pv then
        ShowOnly("family")
        self:RenderFamily(pv, true)
        local rail = self.nav and self.nav:Rail("spells")
        if rail then rail:Select(nil) end
        return
    end
    ShowOnly("overview")
    if self.overview then RefreshOverview(self.overview) end
end

-- A rail row clicked (after the nav selected it): the Overview row ends a
-- preview.
function SpellsPane:RailSelected(id)
    if id == "overview" and self.preview then
        self.preview = nil
        self:Show("overview")
    end
end

-- A family's view, or its preview when it is not in the list (3.6).
function SpellsPane:OpenFamily(key)
    if type(key) ~= "string" then return end
    if MD.Tabs:Has(key) then
        self.preview = nil
        return MD:SelectView("spells", VIEW_PREFIX .. key)
    end
    self.preview = key
    MD:SelectView("spells", "overview")
    -- refused (a practice session holds the screen): nothing left pending
    local nav = self.nav
    local g, v
    if nav then g, v = nav:Selected() end
    if not (nav and nav.frame:IsShown() and g == "spells" and v == "overview") then
        self.preview = nil
    end
end

function SpellsPane:AddFromPreview(key)
    self.preview = nil
    MD.Tabs:Add(key, nil)
    self:ListChanged()
    MD:SelectView("spells", VIEW_PREFIX .. key)
end

-- /st spell <name>: an exact name first, then a prefix; the player's list
-- before the rest of the book; case-insensitive.
function SpellsPane:Find(text)
    local want = (type(text) == "string" and text or ""):lower()
    if want == "" or not MD.Book then return nil end
    local book = MD.Book:Get()
    local listed = MD.Tabs:Get(book)
    local function Scan(list, exact)
        for _, key in ipairs(list) do
            local n = key:lower()
            if (exact and n == want) or (not exact and n:sub(1, #want) == want) then return key end
        end
        return nil
    end
    return Scan(listed, true) or Scan(book.order, true) or Scan(listed, false) or Scan(book.order, false)
end

function SpellsPane:Open(text)
    text = strtrim(type(text) == "string" and text or "")
    if text == "" then return MD:SelectView("spells") end
    local key = self:Find(text)
    if not key then
        MD:Print("spell: no spell in your spellbook starts with '" .. Esc(text) .. "'")
        return
    end
    return self:OpenFamily(key)
end

function MD:OpenSpell(text)
    return SpellsPane:Open(text)
end

--------------------------------------------------------------------------------
-- The font offset (4.2): the pitches grow with it, re-rendered at once
--------------------------------------------------------------------------------
function SpellsPane:FontsChanged()
    local nav = self.nav
    if not nav then return end
    local g = SpellsGroup(nav)
    if g and g.rail then g.rail.rowHeight = Pitch(RAIL_ROW) end
    local rail = nav.rails and nav.rails.spells and nav.rails.spells.rail
    if rail then rail:SetRowHeight(Pitch(RAIL_ROW)) end
    if self.family then LayoutFamily(self.family) end
    if self.picker and self.picker:IsShown() then self:RefreshPicker() end
    local group, view = nav:Selected()
    if group == "spells" then self:Show(view) end
end

if type(UI.ApplyFonts) == "function" then
    local applyFonts = UI.ApplyFonts
    UI.ApplyFonts = function(...)
        local offset = applyFonts(...)
        SpellsPane:FontsChanged()
        return offset
    end
end

--------------------------------------------------------------------------------
-- Wiring (UI/Dashboard_Forever.lua)
--------------------------------------------------------------------------------
-- The group's definition, built when the window is: the rail's rows are the
-- list (seeded here on the first open).
function SpellsPane:Group()
    return { id = "spells", text = "Spells", layout = "rail", views = self:Views(), rail = {
        title = "MY SPELLS",
        rowHeight = Pitch(RAIL_ROW),
        footerHeight = FOOTER_H,
        empty = "Add the spells you want to watch.",
        onSelect = function(id) SpellsPane:RailSelected(id) end,
        onMove = function(id, to)
            local key = FamilyKey(id)
            if key and MD.Tabs:Move(key, to) then SpellsPane:ListChanged() end
        end,
        onRemove = function(id)
            local key = FamilyKey(id)
            if key then SpellsPane:Remove(key) end
        end,
        onDrop = function(at) SpellsPane:Drop(at) end,
        canDrop = function() return SpellsPane:CanDrop() end,
    } }
end

-- The nav built: its rail's footer.
function SpellsPane:Attach(nav)
    self.nav = nav
    local rail = nav:Rail("spells")
    if rail and not self.addBtn then BuildFooter(rail) end
end

-- onCreate for any Spells view: one frame holds them all (the kit shows it
-- for each of them), Overview and a family's view inside it.
function SpellsPane:Create(content)
    if self.host then return self.host end
    local host = CreateFrame("Frame", nil, content)
    host:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    host.spellsHost = true
    self.host = host
    self.overview = BuildOverview(host)
    self.family = BuildFamily(host)
    self.family:Hide()
    return host
end

-- A rescan that changed the book (Spells/Tabs.lua reconciled first: it
-- registered before this file loaded): the rail follows.
MD:RegisterCallback("BOOK_CHANGED", function()
    SpellsPane:RefreshRail()
end)
