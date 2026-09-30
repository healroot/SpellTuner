-- The rank table inside the dashboard: column layout, the row frame pool and
-- the per-row rendering. Split out of UI/Dashboard.lua so the frame file stays
-- about the frame. Exports a constructor on MD.DashboardParts; UI/Dashboard.lua
-- loads after this and calls it.
--
-- T10 (docs/tasks/T10-spells-pane.md): this file is now SHARED (both TOCs) --
-- CreateTable(parent, width, opts) grew an optional fourth argument so
-- UI/Dashboard_Forever.lua's Spellbook pane can reuse the same row pool with
-- its own columns/render/hover, while `opts == nil` (every existing TBC call)
-- renders BYTE FOR BYTE what it always has. No client call and no flavour
-- check belong here either way -- CreateFrame and font strings are the widget
-- toolkit (CLAUDE.md, FOREVER-PLAN.md sec3.2), and the only client-shaped reads
-- below (MD.Tip, MD.RankMath) sit behind the `not opts` branch, which a
-- Forever caller never takes.
local _, MD = ...

MD.DashboardParts = MD.DashboardParts or {}

local COLS = {
    { key = "rank",  x = 12,  w = 46,  label = "Rank" },
    { key = "level", x = 62,  w = 40,  label = "Lvl" },
    { key = "cost",  x = 106, w = 60,  label = "Mana" },
    { key = "heal",  x = 170, w = 86,  label = "Heal/cast" },
    { key = "hpm",   x = 260, w = 64,  label = "HPM" },
    { key = "hps",   x = 328, w = 64,  label = "HPS" },
    { key = "cast",  x = 396, w = 50,  label = "Cast" },
    { key = "casts", x = 450, w = 56,  label = "To OOM" },
    { key = "note",  x = 510, w = 228, label = "" },
}

local ROW_HEIGHT = 16

-- Columns whose values become overheal-adjusted in "Effective" mode. Mana,
-- Cast and To OOM never move: mana spent is mana spent.
local EFFECTIVE_COLS = { heal = true, hpm = true, hps = true }

local function Fmt(n, decimals)
    return string.format(decimals and ("%." .. decimals .. "f") or "%d", n)
end

local function AccentHex()
    local a = MD.UI.accent
    return string.format("|cff%02x%02x%02x", a[1] * 255, a[2] * 255, a[3] * 255)
end

-- T30 (docs/SPEC-forever-ui.md 3.5, 4.1, 4.3): the theme's fills and text
-- colours for the table options, read from UI.PALETTE / UI.TEXT when the
-- Forever theme wrote them and from these literals otherwise. Only an option
-- reaches them: the all-nil table never calls either.
local function FillColor(key)
    local P = MD.UI.PALETTE
    local c = P and P[key]
    if c then return c[1], c[2], c[3], c[4] end
    local a = MD.UI.accent
    if key == "rowAlt" then return 1, 1, 1, 0.03 end
    if key == "hover" then return a[1], a[2], a[3], 0.12 end
    if key == "selected" then return a[1], a[2], a[3], 0.28 end
    if key == "suggested" then return a[1], a[2], a[3], 0.10 end
    if key == "line" then return 0x2A / 255, 0x2A / 255, 0x2A / 255, 1 end
    return a[1], a[2], a[3], 1
end

local function TextHex(token, literal)
    local T = MD.UI.TEXT
    local t = T and T[token]
    return (t and t.hex) or literal
end

-- row:SetBar(key, fraction, alpha) (T30, a `type = "bar"` column): the bar
-- scaled to `fraction` (0..1) of its width, accent at `alpha` (default 0.5,
-- 0.25 on a dominated row); a fraction that is not a number hides the bar
-- and its track (a gap row, a spell with no value).
local function SetBar(row, key, frac, alpha)
    local b = row.bars and row.bars[key]
    if not b then return end
    if type(frac) ~= "number" or frac ~= frac then
        b.track:Hide(); b.fill:Hide()
        return
    end
    if frac > 1 then frac = 1 end
    b.track:Show()
    if frac <= 0 then b.fill:Hide(); return end
    if not alpha then alpha = (row.data and row.data.dominated) and 0.25 or 0.5 end
    local a = MD.UI.accent
    b.fill:SetWidth(b.width * frac)
    b.fill:SetColorTexture(a[1], a[2], a[3], alpha)
    b.fill:Show()
end

-- opts (T10, optional -- nil is today's TBC behaviour, unchanged):
--   opts.cols    -- a column list in COLS' own shape ({key,x,w,label}), used
--                    for both the fontstrings AcquireRow builds and the header
--                    labels, instead of the fixed TBC set.
--   opts.render(row, r, color) -- fills one data row's cells for one entry
--                    `r`, given the same known/suggested/dominated colour the
--                    TBC branch derives; called instead of the TBC rendering.
--   opts.onEnter(row, r) / opts.onLeave(row) -- the row's hover, instead of
--                    MD.Tip/MD.RankMath (which a Forever caller must never
--                    reach -- both are TBC-only globals, CLAUDE.md).
--   opts.header  -- an array of header label overrides by column index; a
--                    missing entry falls back to that column's own .label.
--
-- T30 (docs/SPEC-forever-ui.md 3.5, 4.3), each optional; with all of them nil
-- the table is today's, gold included:
--   opts.font       -- a font object name every cell is built from, instead of
--                       GameFontHighlightSmall; a column's own col.font wins.
--   col.justify     -- "LEFT" (default) / "RIGHT" / "CENTER" per column.
--   opts.rowHeight  -- the data rows' pitch (default 16); a Forever caller
--                       passes UI.Pitch(20). opts.headerHeight is the header's
--                       (default 18; UI.Pitch(22)); when set, the header row's
--                       frame is that tall too, so its labels centre in the band
--                       and the rule sits on its bottom edge.
--   opts.headerRule -- true (the theme's `line`) or an {r, g, b, a}: a 1-px
--                       rule along the header's bottom edge.
--   opts.headerColor -- the header labels' colour code (default |cff888888,
--                       `muted` under marker = "bar").
--   opts.zebra      -- even data rows get the `rowAlt` fill.
--   opts.rowWidth   -- a row's width: a number, or true for the table's whole
--                       width (default width - 60, today's).
--   col.type = "bar" -- a per-mana bar cell: a col.barWidth (72) track, a
--                       col.gap (4), then the number in row.cells[key] over the
--                       rest; opts.render fills it with row:SetBar(key, frac).
--                       The header's label spans the whole column (col.x, col.w).
--   opts.marker = "bar" -- the suggested row is marked by the `suggested` fill
--                       and a 2-px accent bar at its left instead of gold; the
--                       colour handed to render is text / muted / disabled,
--                       never gold; hover takes the `hover` fill; a selected
--                       row (r.selected, or api:SetSelected(id)) the `selected`.
--   opts.onUpdateCells(row, r) -- api:UpdateCells() calls it for every data
--                       row in place, without releasing or re-rendering one.
--   opts.onClick(row, r, button) -- a data row's click.
--   opts.wideFont   -- the spanning cell's font (default opts.font).
function MD.DashboardParts.CreateTable(parent, width, opts)
    local pane = CreateFrame("Frame", nil, parent)
    local rowPool, usedRows = {}, {}
    local cols = (opts and opts.cols) or COLS

    -- T30: the options, each falling back to today's value.
    local rowH = (opts and opts.rowHeight) or ROW_HEIGHT
    local headerH = (opts and opts.headerHeight) or 18
    local rowW = width - 60
    if opts and opts.rowWidth == true then
        rowW = width
    elseif opts and type(opts.rowWidth) == "number" then
        rowW = opts.rowWidth
    end
    local marker = opts and opts.marker
    local zebra = opts and opts.zebra
    local api -- the table's own api, assigned below (PaintFill reads its selection)

    -- T30: the row's fill under marker = "bar" / zebra -- selected over
    -- suggested over the even-row stripe -- and the suggested row's 2-px bar.
    local function PaintFill(row)
        if not row.fill then return end
        local r = row.data
        local key
        if r and marker == "bar" and (r.selected or (api.selectedId ~= nil and r.id == api.selectedId)) then
            key = "selected"
        elseif r and marker == "bar" and r.suggested then
            key = "suggested"
        elseif zebra and row.index and row.index % 2 == 0 then
            key = "rowAlt"
        end
        if key then
            row.fill:SetColorTexture(FillColor(key))
            row.fill:Show()
        else
            row.fill:Hide()
        end
        if row.mark then
            if r and r.suggested then row.mark:Show() else row.mark:Hide() end
        end
    end

    -- T30: a bar column's label. On a data row the number sits after the bar
    -- (col.x + barWidth + gap, the rest of the column); on the header row the
    -- label spans the whole column (col.x, col.w), so "Per mana" is never
    -- squeezed into the number's 40 px. A pooled row can serve as either, so
    -- Render places it per role and Release puts it back as a data row.
    local function PlaceBarCells(row, asHeader)
        if not row.barCells or row.barAsHeader == asHeader then return end
        for _, bc in ipairs(row.barCells) do
            local col, x, w = bc.col, bc.col.x, bc.col.w
            if not asHeader then x, w = x + bc.bw + bc.gap, w - bc.bw - bc.gap end
            bc.fs:ClearAllPoints()
            bc.fs:SetPoint("LEFT", row, "LEFT", x, 0)
            bc.fs:SetWidth(w)
        end
        row.barAsHeader = asHeader
    end

    local function AcquireRow()
        local row = table.remove(rowPool)
        if not row then
            row = CreateFrame("Frame", nil, pane)
            row:SetSize(rowW, rowH)
            row.cells = {}

            -- T30: the fill (under the hover wash) and the suggested marker,
            -- built only when an option asks for them.
            if marker == "bar" or zebra then
                row.fill = row:CreateTexture(nil, "BACKGROUND", nil, -1)
                row.fill:SetAllPoints()
                row.fill:Hide()
            end
            if marker == "bar" then
                local a = MD.UI.accent
                row.mark = row:CreateTexture(nil, "BORDER")
                row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
                row.mark:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
                row.mark:SetWidth(2)
                row.mark:SetColorTexture(a[1], a[2], a[3], 1)
                row.mark:Hide()
            end

            -- Hover: a faint accent wash and the full breakdown of every
            -- number in the row (RankMath:Explain rebuilds it on demand, so
            -- the 2s re-render never allocates it).
            row.highlight = row:CreateTexture(nil, "BACKGROUND")
            row.highlight:SetAllPoints()
            if marker == "bar" then
                row.highlight:SetColorTexture(FillColor("hover")) -- T30
            else
                row.highlight:SetColorTexture(MD.UI.accent[1], MD.UI.accent[2], MD.UI.accent[3], 0.10)
            end
            row.highlight:Hide()
            if opts and opts.onClick then -- T30
                row:SetScript("OnMouseUp", function(self, button)
                    if self.isHeader or not self.data then return end
                    opts.onClick(self, self.data, button)
                end)
            end

            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                if opts and opts.onEnter then
                    if self.isHeader then return end -- no glossary hover in the generic pane (T10)
                    self.highlight:Show()
                    opts.onEnter(self, self.data)
                    return
                end
                if self.isHeader then
                    MD.Tip:ShowAt(self, "TOPLEFT", pane:GetParent(), "TOPRIGHT", 4, 0, MD.Tip:Columns())
                    return
                end
                if not self.spellID then return end
                self.highlight:Show()
                MD.Tip:ShowAt(self, "TOPLEFT", pane:GetParent(), "TOPRIGHT", 4, 0,
                    MD.Tip:Row(MD.RankMath:Explain(self.spellID, self.variant)))
            end)
            row:SetScript("OnLeave", function(self)
                self.highlight:Hide()
                if opts and opts.onLeave then
                    opts.onLeave(self)
                    return
                end
                MD.Tip:Hide()
            end)
            for _, col in ipairs(cols) do
                local fs = row:CreateFontString(nil, "OVERLAY",
                    col.font or (opts and opts.font) or "GameFontHighlightSmall")
                local x, w = col.x, col.w
                if col.type == "bar" then
                    -- T30: the bar cell -- track, fill, then the number.
                    local bw, gap = col.barWidth or 72, col.gap or 4
                    local track = row:CreateTexture(nil, "ARTWORK")
                    track:SetPoint("LEFT", row, "LEFT", col.x, 0)
                    track:SetSize(bw, 8)
                    track:SetColorTexture(1, 1, 1, 0.05)
                    track:Hide()
                    local fill = row:CreateTexture(nil, "ARTWORK", nil, 1)
                    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
                    fill:SetSize(bw, 8)
                    fill:Hide()
                    row.bars = row.bars or {}
                    row.bars[col.key] = { track = track, fill = fill, width = bw }
                    row.SetBar = SetBar
                    x, w = col.x + bw + gap, col.w - bw - gap
                    row.barCells = row.barCells or {}
                    row.barCells[#row.barCells + 1] = { fs = fs, col = col, bw = bw, gap = gap }
                    row.barAsHeader = false
                end
                fs:SetPoint("LEFT", row, "LEFT", x, 0)
                fs:SetWidth(w)
                fs:SetJustifyH(col.justify or "LEFT")
                if opts and opts.render then fs:SetWordWrap(false) end -- T10c, generic path only
                row.cells[col.key] = fs
            end

            -- T10c (generic path only): a full-width cell for a family header,
            -- section title, note or Other line -- text that names a spell
            -- rather than comparing ranks, so it must never wrap into the
            -- 56px Rank column and overprint the rows below it.
            if opts and opts.render then
                local wide = row:CreateFontString(nil, "OVERLAY",
                    opts.wideFont or opts.font or "GameFontHighlightSmall")
                wide:SetPoint("LEFT", row, "LEFT", 8, 0)
                wide:SetWidth(rowW - 12)
                wide:SetJustifyH("LEFT")
                wide:SetWordWrap(false)
                row.cells.wide = wide
            end
        end
        row:Show()
        usedRows[#usedRows + 1] = row
        return row
    end

    api = { frame = pane, cols = cols, rowHeight = rowH, headerHeight = headerH, rowWidth = rowW }

    function api:Release()
        for _, row in ipairs(usedRows) do
            row.spellID, row.variant, row.isHeader, row.data = nil, nil, nil, nil
            row.index = nil -- T30
            if row.cells.wide then row.cells.wide:SetText("") end -- T10c: cleared like the rest
            if row.fill then row.fill:Hide() end -- T30
            if row.mark then row.mark:Hide() end -- T30
            if row.bars then -- T30
                for _, b in pairs(row.bars) do b.track:Hide(); b.fill:Hide() end
            end
            PlaceBarCells(row, false) -- T30: back to a data row's layout
            if row.headerSized then row:SetHeight(rowH); row.headerSized = nil end -- T30
            row.highlight:Hide()
            row:Hide()
            rowPool[#rowPool + 1] = row
        end
        wipe(usedRows)
    end

    if opts and opts.render then
        -- The generic path (T10): one plain header row from `cols`' own
        -- labels (or opts.header's override), then one opts.render call per
        -- entry in `rows`, in order -- no RankMath/Tip read, no effective-mode
        -- concept (that is a TBC-only, overheal-measured idea -- CLAUDE.md's
        -- Out of scope).
        -- T30: the header's rule, one texture on the pane, built on first use.
        local headerRule
        local headerHex = opts.headerColor
            or (marker == "bar" and TextHex("muted", "|cff888888")) or "|cff888888"

        function api:Render(rows)
            api:Release()
            local y = -4

            local header = AcquireRow()
            header.isHeader = true
            header:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
            if opts.headerHeight then -- T30: the header band's own height (4.3's 22)
                header:SetHeight(headerH)
                header.headerSized = true
            end
            PlaceBarCells(header, true) -- T30: the label over the whole column
            for i, col in ipairs(cols) do
                local label = (opts.header and opts.header[i]) or col.label
                header.cells[col.key]:SetText(headerHex .. label .. "|r")
            end
            if opts.headerRule then
                if not headerRule then
                    headerRule = pane:CreateTexture(nil, "BORDER")
                    if type(opts.headerRule) == "table" then
                        local c = opts.headerRule
                        headerRule:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
                    else
                        headerRule:SetColorTexture(FillColor("line"))
                    end
                end
                local px = MD.UI.px and MD.UI.px(1, pane) or 1
                headerRule:ClearAllPoints()
                headerRule:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y - headerH + px)
                headerRule:SetSize(rowW, px)
                headerRule:Show()
            end
            y = y - headerH

            for i, r in ipairs(rows) do
                local row = AcquireRow()
                row:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
                row.data = r
                row.spellID = r.id
                row.index = i -- T30: the zebra's parity
                PlaceBarCells(row, false) -- T30: the number after the bar

                local color
                if marker == "bar" then
                    -- T30: no gold -- the fill, the bar and the caller's tag
                    -- mark the suggested row.
                    if r.known == false then
                        color = TextHex("disabled", "|cff555555")
                    elseif r.dominated then
                        color = TextHex("muted", "|cff8a8a8a")
                    else
                        color = TextHex("text", "|cffffffff")
                    end
                elseif r.known == false then
                    color = "|cff555555"
                elseif r.suggested then
                    color = "|cffffcc00"
                elseif r.dominated then
                    color = "|cff8a8a8a"
                else
                    color = "|cffffffff"
                end

                PaintFill(row)
                opts.render(row, r, color)
                y = y - rowH
            end
        end

        -- T30: the selected row (drives T38's card) by its data's id; nil
        -- clears it. Repaints the fills in place.
        function api:SetSelected(id)
            api.selectedId = id
            for _, row in ipairs(usedRows) do
                if not row.isHeader then PaintFill(row) end
            end
        end

        -- T30: refresh in place -- opts.onUpdateCells(row, r) for every data
        -- row now shown, nothing released or re-acquired. Returns the count.
        function api:UpdateCells()
            local n = 0
            if not opts.onUpdateCells then return n end
            for _, row in ipairs(usedRows) do
                if not row.isHeader and row.data ~= nil then
                    opts.onUpdateCells(row, row.data)
                    n = n + 1
                end
            end
            return n
        end

        return api
    end

    -- rows come straight from RankMath:Compute(). In "Effective" mode the four
    -- healing columns show value * (1 - measured overheal); their headers turn
    -- the accent colour so it is never ambiguous which numbers moved.
    function api:Render(rows)
        api:Release()
        local effective = MD.db and MD.db.effectiveMode and true or false
        local accent = AccentHex()
        local y = -4

        local header = AcquireRow()
        header.isHeader = true -- pooled like any row; its hover shows the glossary
        header:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
        for _, col in ipairs(COLS) do
            local hex = (effective and EFFECTIVE_COLS[col.key]) and accent or "|cff888888"
            header.cells[col.key]:SetText(hex .. col.label .. "|r")
        end
        y = y - 18

        for _, r in ipairs(rows) do
            local row = AcquireRow()
            row:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
            row.spellID, row.variant = r.id, r.variant

            local c
            if not r.known then
                c = "|cff555555"
            elseif r.suggested then
                c = "|cffffcc00"
            elseif r.dominated then
                c = "|cff8a8a8a"
            else
                c = "|cffffffff"
            end
            -- In effective mode a row with no measurement of its own keeps its
            -- raw value and gets a grey "?" so the two are never confused.
            local heal, hpm, hps = r.heal, r.hpm, r.hps
            local unmeasured = ""
            if effective then
                if r.overheal then
                    heal, hpm, hps = r.effHeal, r.effHpm, r.effHps
                else
                    unmeasured = "|cff777777?|r"
                end
            end

            row.cells.rank:SetText(c .. (r.rankLabel or ("R" .. r.rank)) .. (r.suggested and " *" or "") .. "|r")
            row.cells.level:SetText(c .. r.level .. "|r")
            row.cells.cost:SetText(c .. Fmt(r.cost) .. "|r")
            row.cells.heal:SetText(c .. Fmt(heal) .. "|r" .. unmeasured)
            row.cells.hpm:SetText(c .. Fmt(hpm, 2) .. "|r")
            row.cells.hps:SetText(c .. Fmt(hps) .. "|r")
            -- the grey "*" means the cast time is a Nature's Grace average
            row.cells.cast:SetText(c .. Fmt(r.cast, 1) .. "s|r" .. (r.ng and "|cff888888*|r" or ""))
            row.cells.casts:SetText(c .. (r.casts == math.huge and "inf" or Fmt(r.casts)) .. "|r")

            local note
            if not r.known then
                note = "|cff555555not learned|r"
            elseif r.virtual then
                note = "|cff888888rolling stack (6 ticks, no bloom)|r"
            elseif r.suggested and r.isMax then
                note = "|cffffcc00efficient + max rank|r"
            elseif r.suggested then
                note = "|cffffcc00efficient rank|r"
            elseif r.isMax then
                note = "|cff888888max rank|r"
            elseif r.dominated then
                note = "|cff5a5a5adominated|r"
            else
                note = ""
            end
            row.cells.note:SetText(note)

            y = y - ROW_HEIGHT
        end
    end

    return api
end
