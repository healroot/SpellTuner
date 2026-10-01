-- The one table every list in the window is drawn on: the column layout, the
-- row frame pool and the per-row rendering, configured by the caller's `opts`.
-- Exports a constructor on MD.DashboardParts.
--
-- T10 (docs/tasks/T10-spells-pane.md): SHARED (both TOCs) since the Forever
-- Spellbook pane reused the row pool with its own columns/render/hover.
-- T81 (C2 of docs/PLAN-refactor-ux.md, review U5 / A23): ONE table. Until
-- T81, `opts == nil` was a second table in the same closure -- the TBC rank
-- table, with its own Render, its fixed columns, gold and the MD.Tip:Row /
-- MD.RankMath hover -- and every option below was a diff in a TBC-loaded
-- file. The TBC rank table (UI/Dashboard.lua), Waste and Review are now
-- `opts` sets like every Forever list, and CreateTable refuses a call without
-- opts.render. No client call and no flavour check belong here -- CreateFrame
-- and font strings are the widget toolkit (CLAUDE.md, FOREVER-PLAN.md
-- sec3.2) -- and nothing here reads a TBC-only table any more.
local _, MD = ...

MD.DashboardParts = MD.DashboardParts or {}

local ROW_HEIGHT = 16 -- a data row's pitch when opts.rowHeight is not given

-- T30 (docs/SPEC-forever-ui.md 3.5, 4.1, 4.3): the table options' fills and
-- text colours. T69 (P25): token reads -- MD.UI.Fill / MD.UI.Hex. T81: the
-- row colour without marker = "bar" reads the tokens too (it was the old
-- table's literals, gold included).

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

-- opts (T10; required since T81 -- a call without opts.render raises):
--   opts.cols    -- the column list ({key, x, w, label, ...}), used for both
--                    the fontstrings AcquireRow builds and the header labels.
--   opts.render(row, r, color) -- fills one data row's cells for one entry
--                    `r`, given the row colour (known / suggested / dominated).
--   opts.onEnter(row, r) / opts.onLeave(row) -- the row's hover (the wash
--                    shows only for a table that has an onEnter).
--   opts.header  -- an array of header label overrides by column index; a
--                    missing entry falls back to that column's own .label.
--                    Read at every Render, so a caller may change it between.
--
-- T30 (docs/SPEC-forever-ui.md 3.5, 4.3), each optional:
--   opts.font       -- a font object name every cell is built from (default
--                       GameFontHighlightSmall); a column's own col.font wins.
--   col.justify     -- "LEFT" (default) / "RIGHT" / "CENTER" per column.
--   opts.rowHeight  -- the data rows' pitch (default 16); a Forever caller
--                       passes UI.Pitch(20). opts.headerHeight is the header's
--                       (default 18; UI.Pitch(22)); when set, the header row's
--                       frame is that tall too, so its labels centre in the band
--                       and the rule sits on its bottom edge.
--   opts.headerRule -- true (the theme's `line`) or an {r, g, b, a}: a 1-px
--                       rule along the header's bottom edge.
--   opts.headerColor -- the header labels' colour code (default `muted`).
--   opts.zebra      -- even data rows get the `rowAlt` fill.
--   opts.rowWidth   -- a row's width: a number, or true for the table's whole
--                       width (default width - 60).
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
--
-- T71 (P27, review U25 / U17), each optional and off unless asked for:
--   opts.scroll     -- the table shows a window of its rows: api:Render(rows)
--                       paints rows offset+1 .. offset+visible, the mouse wheel
--                       moves the window (opts.scrollStep rows a notch, 3), and
--                       a thin bar at the right edge (rowWidth + 4) shows where
--                       it is (its thumb drags). `visible` is
--                       api:SetVisibleRows(n), else what the frame's height
--                       holds. api:ScrollTo(offset) / ScrollBy(n) re-render;
--                       api:Reveal(i) moves the window so row i is in it (for
--                       the next Render); api:Offset() / api:Visible() read it.
--                       A row's `index` (the zebra's parity) is its place in
--                       the whole list, so stripes do not swap on a scroll.
--   opts.onDoubleClick(row, r, button) -- a second LeftButton click on the
--                       same entry (r.id, else r) within DOUBLE_CLICK seconds;
--                       opts.onClick is still called for both clicks, first.
--   opts.noHeader   -- no header row: the data rows start at the top.
--
-- T76 (P32, review U10 -- the mechanism; the words are P34's):
--   col.tooltip     -- a sentence (or a list of UI/Tip.lua lines) shown when
--                       the pointer is over that column's header label: the
--                       label in `text`, the sentence in `text2`, through
--                       MD.Tip:Show. A column without one has no hover (T81:
--                       the TBC rank table gives every column its glossary,
--                       Tip:Columns, this way).
--
-- T78 (P34, review U1 / U7 / U10; mockup M5), each off unless asked for:
--   col.tooltip may also be a function(label) answering the sentence (or the
--                       lines) for the label the header actually shows (an
--                       opts.header override included); that label is the
--                       tooltip's title.
--   col.cellTooltip(r, row) -- a data row's cell explains itself: over that
--                       column's cell the function's lines (UI/Tip.lua's line
--                       model) are shown beside the cell. Asked when the row
--                       is drawn: nil there and the cell has no hover of its
--                       own (the row's hover, its click, a button the render
--                       put there all reach the row); asked again on hover,
--                       where nil falls back to the row's hover, and a click
--                       on the cell is always the row's click.
--   opts.selection = "bar" -- under marker = "bar", the selected row is a
--                       white 2-px bar at its left and no fill: the fill (and
--                       the accent bar) stay the suggested row's alone.
--   opts.headerFont -- the header labels' font object (the data cells keep
--                       opts.font); a pooled row gets its own fonts back when
--                       it serves as a data row again.
local DOUBLE_CLICK = 0.4

-- T76: one column's header hover -- a hit frame over its label, built the
-- first time a header row carries a column with a tooltip, hidden whenever
-- the row is released (a pooled row also serves as a data row).
local function ColumnTip(hit)
    local col = hit.col
    if not (col and col.tooltip and MD.Tip) then return end
    local title = hit.label or col.label
    local tip = col.tooltip
    if type(tip) == "function" then tip = tip(title) end -- T78: by the label shown
    if tip == nil then return end
    local lines
    if type(tip) == "table" then
        lines = tip
    else
        lines = {}
        if title and title ~= "" then lines[#lines + 1] = { l = title, c = "text" } end
        lines[#lines + 1] = { l = tostring(tip), c = "text2", wrap = true }
    end
    MD.Tip:Show(hit, lines, { anchor = "ANCHOR_TOPLEFT", x = 0, y = 3 })
end

-- T78: one data cell's hover (col.cellTooltip). Its lines beside the cell,
-- else the row's own hover; a click goes to the row.
local function CellTipEnter(hit)
    local row, col = hit.row, hit.col
    local r = row and row.data
    local lines = r and col and col.cellTooltip and col.cellTooltip(r, row)
    if type(lines) == "table" and #lines > 0 and MD.Tip then
        hit.showing = true
        row.highlight:Show()
        MD.Tip:Show(hit, lines, { anchor = "beside" })
        return
    end
    hit.showing = nil
    local enter = row and row:GetScript("OnEnter")
    if enter then enter(row) end
end
local function CellTipLeave(hit)
    local row = hit.row
    if hit.showing then
        hit.showing = nil
        if row then row.highlight:Hide() end
        if MD.Tip then MD.Tip:Hide() end
        return
    end
    local leave = row and row:GetScript("OnLeave")
    if leave then leave(row) end
end
local function CellTipClick(hit, button)
    local row = hit.row
    local up = row and row:GetScript("OnMouseUp")
    if up then up(row, button) end
end

-- A hit frame only over a cell that has something to say when the row is
-- drawn: a cell with nothing to explain stays the row's own (its hover, its
-- click, any button the render puts there).
local function CellTips(row, cols, height)
    for _, col in ipairs(cols) do
        if col.cellTooltip and row.data ~= nil and col.cellTooltip(row.data, row) ~= nil then
            row.cellHits = row.cellHits or {}
            local hit = row.cellHits[col.key]
            if not hit then
                hit = CreateFrame("Frame", nil, row)
                hit:EnableMouse(true)
                hit:SetScript("OnEnter", CellTipEnter)
                hit:SetScript("OnLeave", CellTipLeave)
                hit:SetScript("OnMouseUp", CellTipClick)
                row.cellHits[col.key] = hit
            end
            hit.row, hit.col = row, col
            hit:ClearAllPoints()
            hit:SetPoint("TOPLEFT", row, "TOPLEFT", col.x, 0)
            hit:SetSize(col.w, height)
            hit:Show()
        end
    end
end

local function HeaderTips(header, cols, height, labels)
    for i, col in ipairs(cols) do
        if col.tooltip then
            header.colHits = header.colHits or {}
            local hit = header.colHits[col.key]
            if not hit then
                hit = CreateFrame("Frame", nil, header)
                hit:EnableMouse(true)
                hit:SetScript("OnEnter", ColumnTip)
                hit:SetScript("OnLeave", function() if MD.Tip then MD.Tip:Hide() end end)
                header.colHits[col.key] = hit
            end
            hit.col = col
            hit.label = labels and labels[i] or col.label -- T78: the label shown
            hit:ClearAllPoints()
            hit:SetPoint("TOPLEFT", header, "TOPLEFT", col.x, 0)
            hit:SetSize(col.w, height)
            hit:Show()
        end
    end
end
function MD.DashboardParts.CreateTable(parent, width, opts)
    -- T81 (A23): one table -- the old no-options rank table is gone
    if type(opts) ~= "table" or type(opts.render) ~= "function" then
        error("CreateTable: opts.render is required (T81: the one table is configured by its caller)", 2)
    end
    local pane = CreateFrame("Frame", nil, parent)
    local rowPool, usedRows = {}, {}
    local cols = opts.cols or {}
    local lastClick = { key = nil, at = 0 } -- T71: the double-click's first half

    -- T30: the options, each with its default.
    local rowH = opts.rowHeight or ROW_HEIGHT
    local headerH = opts.headerHeight or 18
    local rowW = width - 60
    if opts.rowWidth == true then
        rowW = width
    elseif type(opts.rowWidth) == "number" then
        rowW = opts.rowWidth
    end
    local marker = opts.marker
    local zebra = opts.zebra
    local pickBar = marker == "bar" and opts.selection == "bar" -- T78
    local headerFont = opts.headerFont -- T78
    local api -- the table's own api, assigned below (PaintFill reads its selection)

    -- T30: the row's fill under marker = "bar" / zebra -- selected over
    -- suggested over the even-row stripe -- and the suggested row's 2-px bar.
    local function PaintFill(row)
        if not row.fill then return end
        local r = row.data
        local key
        local picked = r and marker == "bar" and (r.selected or (api.selectedId ~= nil and r.id == api.selectedId))
        if picked and not pickBar then
            key = "selected"
        elseif r and marker == "bar" and r.suggested then
            key = "suggested"
        elseif zebra and row.index and row.index % 2 == 0 then
            key = "rowAlt"
        end
        if key then
            row.fill:SetColorTexture(MD.UI.Fill(key))
            row.fill:Show()
        else
            row.fill:Hide()
        end
        if row.mark then
            if r and r.suggested then row.mark:Show() else row.mark:Hide() end
        end
        if row.pick then -- T78: the selection's own mark, over the accent bar
            if picked then row.pick:Show() else row.pick:Hide() end
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
            if pickBar then -- T78: white, above the accent bar
                row.pick = row:CreateTexture(nil, "BORDER", nil, 1)
                row.pick:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
                row.pick:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
                row.pick:SetWidth(2)
                row.pick:SetColorTexture(1, 1, 1, 1)
                row.pick:Hide()
            end

            -- Hover: a faint accent wash, then the caller's onEnter.
            row.highlight = row:CreateTexture(nil, "BACKGROUND")
            row.highlight:SetAllPoints()
            if marker == "bar" then
                row.highlight:SetColorTexture(MD.UI.Fill("hover")) -- T30
            else
                row.highlight:SetColorTexture(MD.UI.accent[1], MD.UI.accent[2], MD.UI.accent[3], 0.10)
            end
            row.highlight:Hide()
            if opts.onClick or opts.onDoubleClick then -- T30, T71
                row:SetScript("OnMouseUp", function(self, button)
                    if self.isHeader or not self.data then return end
                    -- read before onClick: a click that re-renders hands this
                    -- pooled row another entry
                    local data = self.data
                    local double = false
                    if opts.onDoubleClick and button == "LeftButton" then
                        local key = data.id ~= nil and data.id or data
                        local now = GetTime()
                        if lastClick.key == key and (now - lastClick.at) <= DOUBLE_CLICK then
                            double, lastClick.key = true, nil
                        else
                            lastClick.key, lastClick.at = key, now
                        end
                    end
                    if opts.onClick then opts.onClick(self, data, button) end
                    if double then opts.onDoubleClick(self, data, button) end
                end)
            end

            row:EnableMouse(true)
            -- T81: the header row's hover is its columns' own (col.tooltip,
            -- HeaderTips); a table without onEnter has no row hover at all.
            row:SetScript("OnEnter", function(self)
                if self.isHeader or not opts.onEnter then return end
                self.highlight:Show()
                opts.onEnter(self, self.data)
            end)
            row:SetScript("OnLeave", function(self)
                self.highlight:Hide()
                if opts.onLeave then
                    opts.onLeave(self)
                elseif MD.Tip then
                    MD.Tip:Hide()
                end
            end)
            for _, col in ipairs(cols) do
                local fs = row:CreateFontString(nil, "OVERLAY",
                    col.font or opts.font or "GameFontHighlightSmall")
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
                fs:SetWordWrap(false) -- T10c
                if headerFont then -- T78: the font a data row gets back
                    fs.ownFont = col.font or opts.font or "GameFontHighlightSmall"
                end
                row.cells[col.key] = fs
            end

            -- T10c: a full-width cell for a family header, section title,
            -- note or Other line -- text that names a spell rather than
            -- comparing ranks, so it must never wrap into the 56px Rank
            -- column and overprint the rows below it.
            local wide = row:CreateFontString(nil, "OVERLAY",
                opts.wideFont or opts.font or "GameFontHighlightSmall")
            wide:SetPoint("LEFT", row, "LEFT", 8, 0)
            wide:SetWidth(rowW - 12)
            wide:SetJustifyH("LEFT")
            wide:SetWordWrap(false)
            row.cells.wide = wide
        end
        row:Show()
        usedRows[#usedRows + 1] = row
        return row
    end

    api = { frame = pane, cols = cols, rowHeight = rowH, headerHeight = headerH, rowWidth = rowW }

    function api:Release()
        for _, row in ipairs(usedRows) do
            row.spellID, row.isHeader, row.data = nil, nil, nil
            row.index = nil -- T30
            row.cells.wide:SetText("") -- T10c: cleared like the rest
            if row.fill then row.fill:Hide() end -- T30
            if row.mark then row.mark:Hide() end -- T30
            if row.bars then -- T30
                for _, b in pairs(row.bars) do b.track:Hide(); b.fill:Hide() end
            end
            PlaceBarCells(row, false) -- T30: back to a data row's layout
            if row.headerSized then row:SetHeight(rowH); row.headerSized = nil end -- T30
            if row.colHits then -- T76: a column's header hover goes with the header
                for _, hit in pairs(row.colHits) do hit:Hide() end
            end
            if row.cellHits then -- T78: a cell's hover goes with its data row
                for _, hit in pairs(row.cellHits) do hit:Hide(); hit.showing = nil end
            end
            if row.pick then row.pick:Hide() end -- T78
            if row.headerFonted then -- T78: the data cells' own fonts back
                for _, fs in pairs(row.cells) do
                    if fs.ownFont then fs:SetFontObject(fs.ownFont) end
                end
                row.headerFonted = nil
            end
            row.highlight:Hide()
            row:Hide()
            rowPool[#rowPool + 1] = row
        end
        wipe(usedRows)
    end

    -- One header row from `cols`' own labels (or opts.header's override),
    -- then one opts.render call per entry in `rows`, in order (T10; T81: the
    -- only Render -- the TBC rank table's own went with the no-options table).
    -- T30: the header's rule, one texture on the pane, built on first use.
    local headerRule
    local headerHex = opts.headerColor or MD.UI.Hex("muted")

    -- T71: the scrolled window (opts.scroll) -- its state, the bar at the
    -- right edge and the wheel. Built only when asked for.
    local scroll = opts.scroll and { offset = 0, visible = nil, rows = nil } or nil
    local bar
    local function Visible()
        if scroll.visible then return scroll.visible end
        local top = 4 + (opts.noHeader and 0 or headerH)
        return math.max(1, math.floor((pane:GetHeight() - top) / rowH))
    end
    local function Clamp(n)
        local maxOffset = math.max(0, n - Visible())
        if scroll.offset > maxOffset then scroll.offset = maxOffset end
        if scroll.offset < 0 then scroll.offset = 0 end
    end
    local function PaintBar(n, top)
        if not bar then return end
        local vis = Visible()
        if n <= vis then bar.track:Hide(); bar.thumb:Hide(); return end
        local trackH = vis * rowH
        local thumbH = math.max(12, math.floor(trackH * vis / n))
        local span = math.max(0, n - vis)
        local y = span > 0 and (trackH - thumbH) * scroll.offset / span or 0
        bar.track:ClearAllPoints()
        bar.track:SetPoint("TOPLEFT", pane, "TOPLEFT", rowW + 4, top)
        bar.track:SetSize(4, trackH)
        bar.track:Show()
        bar.thumb:ClearAllPoints()
        bar.thumb:SetPoint("TOPLEFT", pane, "TOPLEFT", rowW + 3, top - y)
        bar.thumb:SetSize(6, thumbH)
        bar.thumb:Show()
        bar.trackH, bar.thumbH, bar.top, bar.span = trackH, thumbH, top, span
    end
    if scroll then
        local a = MD.UI.accent
        bar = {}
        bar.track = pane:CreateTexture(nil, "BORDER")
        bar.track:SetColorTexture(1, 1, 1, 0.06)
        bar.track:Hide()
        bar.thumb = CreateFrame("Frame", nil, pane)
        local fill = bar.thumb:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", bar.thumb, "TOPLEFT", 1, 0)
        fill:SetPoint("BOTTOMRIGHT", bar.thumb, "BOTTOMRIGHT", -1, 0)
        fill:SetColorTexture(a[1], a[2], a[3], 0.8)
        bar.thumb:EnableMouse(true)
        bar.thumb:Hide()
        -- dragging the thumb: the offset follows the cursor's travel over
        -- the track, in rows
        bar.thumb:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local _, y0 = GetCursorPosition()
            local scale = pane:GetEffectiveScale()
            local from = scroll.offset
            self:SetScript("OnUpdate", function()
                local _, y1 = GetCursorPosition()
                local travel = (y0 - y1) / (scale > 0 and scale or 1)
                local room = (bar.trackH or 0) - (bar.thumbH or 0)
                if room <= 0 then return end
                local want = from + math.floor(travel / room * (bar.span or 0) + 0.5)
                if want ~= scroll.offset then api:ScrollTo(want) end
            end)
        end)
        bar.thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
        bar.thumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
        pane:EnableMouseWheel(true)
        pane:SetScript("OnMouseWheel", function(_, delta)
            api:ScrollBy(-(delta or 0) * (opts.scrollStep or 3))
        end)
    end

    function api:Render(rows)
        api:Release()
        local y = -4

        if not opts.noHeader then -- T71: a table may have none
        local header = AcquireRow()
        header.isHeader = true
        header:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
        if opts.headerHeight then -- T30: the header band's own height (4.3's 22)
            header:SetHeight(headerH)
            header.headerSized = true
        end
        PlaceBarCells(header, true) -- T30: the label over the whole column
        local shown = {}
        for i, col in ipairs(cols) do
            local label = (opts.header and opts.header[i]) or col.label
            shown[i] = label
            if headerFont then header.cells[col.key]:SetFontObject(headerFont) end -- T78
            header.cells[col.key]:SetText(headerHex .. label .. "|r")
        end
        if headerFont then header.headerFonted = true end
        HeaderTips(header, cols, headerH, shown) -- T76: col.tooltip on the label
        if opts.headerRule then
            if not headerRule then
                headerRule = pane:CreateTexture(nil, "BORDER")
                if type(opts.headerRule) == "table" then
                    local c = opts.headerRule
                    headerRule:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
                else
                    headerRule:SetColorTexture(MD.UI.Fill("line"))
                end
            end
            local px = MD.UI.px and MD.UI.px(1, pane) or 1
            headerRule:ClearAllPoints()
            headerRule:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y - headerH + px)
            headerRule:SetSize(rowW, px)
            headerRule:Show()
        end
        y = y - headerH
        end -- T71: not opts.noHeader

        -- T71: all of them, or the scrolled window
        local first, last = 1, #rows
        if scroll then
            scroll.rows = rows
            Clamp(#rows)
            first = scroll.offset + 1
            last = math.min(#rows, scroll.offset + Visible())
            PaintBar(#rows, y)
        end
        for i = first, last do
            local r = rows[i]
            local row = AcquireRow()
            row:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, y)
            row.data = r
            row.spellID = r.id
            row.index = i -- T30: the zebra's parity
            PlaceBarCells(row, false) -- T30: the number after the bar

            -- T30: no gold under marker = "bar" -- the fill, the bar and the
            -- caller's tag mark the suggested row. T81: without the marker
            -- the suggested row's words take the accent (a token read).
            local color
            if r.known == false then
                color = MD.UI.Hex("disabled")
            elseif r.suggested and marker ~= "bar" then
                color = MD.UI.Hex("accent")
            elseif r.dominated then
                color = MD.UI.Hex("dominated")
            else
                color = MD.UI.Hex("text")
            end

            PaintFill(row)
            CellTips(row, cols, rowH) -- T78: col.cellTooltip
            opts.render(row, r, color)
            y = y - rowH
        end
    end

    -- T71: the scrolled window's api (opts.scroll; harmless without it)
    function api:SetVisibleRows(n)
        if scroll then scroll.visible = (type(n) == "number" and n >= 1) and math.floor(n) or nil end
    end
    function api:Offset() return scroll and scroll.offset or 0 end
    function api:Visible() return scroll and Visible() or nil end
    function api:ScrollTo(offset)
        if not scroll then return end
        scroll.offset = math.floor(tonumber(offset) or 0)
        if scroll.rows then api:Render(scroll.rows) end
    end
    function api:ScrollBy(n)
        if scroll then api:ScrollTo(scroll.offset + (n or 0)) end
    end
    function api:Reveal(i)
        if not scroll or type(i) ~= "number" then return end
        local vis = Visible()
        if i <= scroll.offset then
            scroll.offset = i - 1
        elseif i > scroll.offset + vis then
            scroll.offset = i - vis
        end
        if scroll.offset < 0 then scroll.offset = 0 end
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
