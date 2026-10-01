-- T84 (C5 of docs/PLAN-refactor-ux.md, section 7.1; mockup M4 layout B): the
-- Spells rail's glue, shared by both lines. It moved here out of
-- UI/SpellsPane_Forever.lua (T36, docs/SPEC-forever-ui.md 3.2-3.4) so TBC's
-- Spells group (UI/Dashboard.lua) is the same rail: Overview first, then one
-- row per family of the player's own list (Spells/Tabs.lua), [ + Add ] and
-- the picker, the "<spell> removed [Undo]" line, drag to reorder, one x and
-- the right-click row menu (UI.CreateRail's, P33).
--
-- MD.SpellRail.Install(pane, spec) puts the glue's methods on `pane` (the
-- Forever SpellsPane, or TBC's Spells group object), so a pane calls
-- pane:RefreshRail(), pane:Remove(key) ... and keeps its fields where they
-- were (pane.nav, pane.addBtn, pane.undoText, pane.undoBtn, pane.picker,
-- pane.preview). spec:
--   source()             the book the list reads: MD.Book:Get() on Forever,
--                        Spells/Families_TBC.lua's families on TBC (both in
--                        Book's family shape)
--   row(fam, key, ctx)   a listed family's rail row: { text, icon, tag,
--                        tooltip } (the glue adds id, key and the new dot)
--   prepare()            optional: computed once per Views(), handed to row
--   label(key)           optional: how a bare key reads (the Undo line, a
--                        stale row); the escaped key when absent
--   pickerTip            optional: the picker's tip line (hidden when nil)
-- A pane may define RailSelected(id) (a rail row clicked, after the nav
-- selected it). The group's id is "spells" and a family's view id is
-- "fam:<key>" on both lines.
--
-- Client data only through MD.API (the cursor, a spell's name, combat); the
-- widget toolkit is not a client call (CLAUDE.md, T1b).
local _, MD = ...
local UI = MD.UI

local SpellRail = {}
MD.SpellRail = SpellRail

-- 3.2 / 4.3 metrics at font offset 0; every vertical pitch goes through
-- UI.Pitch (4.2), so it grows with a positive offset.
local GROUP = "spells"
local RAIL_ROW = 20
local FOOTER_H = 48         -- [ + Add ] and the Undo line above it
local PICKER_W, PICKER_H = 300, 400
local PICKER_ROW = 20
local PICKER_SECTION = 22   -- a section title, its rule at -17
local VIEW_PREFIX = "fam:"
SpellRail.VIEW_PREFIX, SpellRail.RAIL_ROW = VIEW_PREFIX, RAIL_ROW

local function Pitch(n)
    if UI.Pitch then return UI.Pitch(n) end
    return n
end

-- The probe's escaping (MD.Text.EscASCII, T60): every name on screen stays
-- ASCII with no bare pipe.
local Esc = MD.Text.EscASCII

-- The family key a view id names ("fam:<key>"), or nil (Overview).
function SpellRail.FamilyKey(viewId)
    if type(viewId) == "string" and viewId:sub(1, #VIEW_PREFIX) == VIEW_PREFIX then
        return viewId:sub(#VIEW_PREFIX + 1)
    end
    return nil
end
local FamilyKey = SpellRail.FamilyKey

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

local function SpellsGroup(nav)
    for _, g in ipairs(nav.groups or {}) do
        if g.id == GROUP then return g end
    end
    return nil
end

local function SameIds(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i].id ~= b[i].id then return false end end
    return true
end

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

function SpellRail.Install(pane, spec)
    spec = spec or {}
    pane.railSpec = spec
    local function Source() return spec.source and spec.source() or nil end
    local function Label(key)
        if spec.label then return spec.label(key) end
        return Esc(key)
    end

    ----------------------------------------------------------------------------
    -- The list: rail rows from Spells/Tabs.lua (3.2, 3.3)
    ----------------------------------------------------------------------------
    -- The rail's views: Overview, then one per listed family. The first call
    -- with a book seeds the list (the seed runs on first open).
    function pane:Views()
        local views = { { id = "overview", text = "Overview", fixed = true } }
        local book = Source()
        if not (book and MD.Tabs) then return views end
        local ctx = spec.prepare and spec.prepare() or nil
        for _, key in ipairs(MD.Tabs:Get(book)) do
            local fam = MD.Tabs:Resolve(key, book)
            if type(fam) == "table" then
                local v = spec.row and spec.row(fam, key, ctx) or { text = Esc(fam.name or key) }
                v.id, v.key = VIEW_PREFIX .. key, key
                v.new = MD.Tabs:IsNew(key)
                views[#views + 1] = v
            else
                views[#views + 1] = { id = VIEW_PREFIX .. key, key = key, text = Label(key),
                    stale = true, tooltip = "not in your spellbook" }
            end
        end
        return views
    end

    -- The rail follows the list. A change in which rows there are (or their
    -- order) is nav:SetViews (3.1: every row a view); anything else -- a tag,
    -- the new dot, a stale name -- repaints the rows in place, so the view on
    -- screen is not re-selected under the player.
    function pane:RefreshRail()
        local nav = self.nav
        if not nav then return end
        if self.busy then self.railPending = true; return end
        self.busy = true
        local ok, err = pcall(function()
            local views = self:Views()
            local g = SpellsGroup(nav)
            if g and g.views and SameIds(g.views, views) then
                g.views = views
                local rail = nav:Rail(GROUP)
                if rail then
                    rail:SetRows(views)
                    if self.preview and nav.group == GROUP then rail:Select(nil) end
                end
            else
                nav:SetViews(GROUP, views)
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
    function pane:ListChanged()
        self:RefreshRail()
        if self.picker and self.picker:IsShown() then self:RefreshPicker() end
    end

    function pane:Remove(key)
        if MD.Tabs:Remove(key) then self:ListChanged() end
    end

    function pane:Undo()
        if MD.Tabs:Undo() then self:ListChanged() end
    end

    -- The rail's footer: [ + Add ] pinned at the bottom, and after a removal
    -- the line above it reads "Wrath removed  [Undo]" until the next change.
    function pane:RefreshFooter()
        if not self.undoText then return end
        local key = MD.Tabs and MD.Tabs:UndoKey()
        if key then
            self.undoText:SetText(Label(key) .. " removed")
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
        add:SetScript("OnClick", function() pane:OpenPicker() end)
        pane.addBtn = add

        local undoText = footer:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        undoText:SetPoint("BOTTOMLEFT", add, "TOPLEFT", 5, 8)
        undoText:SetJustifyH("LEFT")
        UI.Tint(undoText, "text", "text2")
        pane.undoText = undoText

        local undo = UI.CreateButton(footer, "Undo", "accent-hover", { 44, 16 }, false, false,
            UI.FONT_SMALL, UI.FONT_SMALL)
        undo:SetPoint("LEFT", undoText, "RIGHT", 8, 0)
        undo:SetScript("OnClick", function() pane:Undo() end)
        pane.undoBtn = undo
        pane:RefreshFooter()
    end

    ----------------------------------------------------------------------------
    -- The drop from the spellbook (3.2): the family of the spell on the
    -- cursor goes in at the drop row (moved there when it is listed already).
    -- The cursor is read, never cleared: the spell stays on it after the
    -- drop. Only where the adapter reads the cursor (MD.API.CursorInfo).
    ----------------------------------------------------------------------------
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

    function pane:CanDrop()
        local kind = MD.API.CursorInfo and MD.API.CursorInfo()
        return kind == "spell"
    end

    function pane:Drop(at)
        if not MD.API.CursorInfo then return end
        local kind, id = MD.API.CursorInfo()
        if kind ~= "spell" or type(id) ~= "number" then return end
        local book = Source()
        if not book then return end
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

    ----------------------------------------------------------------------------
    -- The picker sheet (3.4): over the spell view only, the rail live beside it
    ----------------------------------------------------------------------------
    local function PickerSectionFrame(p, i)
        local s = p.sectionPool[i]
        if s then return s end
        s = CreateFrame("Frame", nil, p.scroll.content)
        s.title = s:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
        s.title:SetPoint("TOPLEFT", s, "TOPLEFT", 2, -2)
        s.title:SetJustifyH("LEFT")
        UI.Tint(s.title, "text", "accent") -- T107: names, so a switch repaints them
        s.rule = s:CreateTexture(nil, "ARTWORK")
        s.rule:SetHeight(1)
        s.rule:SetPoint("TOPLEFT", s, "TOPLEFT", 2, -17)
        s.rule:SetPoint("TOPRIGHT", s, "TOPRIGHT", -2, -17)
        if UI.PALETTE and UI.PALETTE.rule then UI.Tint(s.rule, "texture", "rule")
        else UI.Tint(s.rule, "texture", "accent", 0.6) end
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
                if pane.preview == r.key then pane.preview = nil end
            else
                MD.Tabs:Remove(r.key)
            end
            pane:ListChanged()
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
        UI.Tint(r.range, "text", "muted")
        r.name = r:CreateFontString(nil, "OVERLAY", UI.FONT)
        r.name:SetPoint("LEFT", r, "LEFT", 46, 0)
        r.name:SetPoint("RIGHT", r, "RIGHT", -64, 0)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        p.rowPool[i] = r
        return r
    end

    function pane:RefreshPicker()
        local p = self.picker
        if not p then return end
        local book = Source() or { order = {}, families = {} }
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
                    and (filter == "" or name:lower():find(filter, 1, true)
                        or (type(fam.name) == "string" and fam.name:lower():find(filter, 1, true))) then
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
        local nav = pane.nav
        local rail = nav:Rail(GROUP)
        local view = nav:RailView(GROUP)
        local p = UI.CreateSheet(view, view, PICKER_W, PICKER_H, "ADD SPELLS")
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", rail.frame, "TOPRIGHT", 4, 0)
        p.spellsPicker = true -- marks the sheet for tools/spellsui.lua and tools/dashui.lua
        p.sectionPool, p.rowPool, p.rows = {}, {}, {}
        local body = p:Body()

        local search = UI.CreateEditBox(body, PICKER_W - 18, 20)
        search:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -6)
        search:SetScript("OnTextChanged", function() pane:RefreshPicker() end)
        p.search = search
        local placeholder = search:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
        placeholder:SetPoint("LEFT", search, "LEFT", 6, 0)
        UI.Tint(placeholder, "text", "muted")
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
        UI.Tint(tip, "text", "muted")
        tip:SetText(spec.pickerTip or "")
        if not spec.pickerTip then tip:Hide() end
        p.tip = tip

        local reset = UI.CreateButton(body, "Reset to my heals", "accent-hover", { 130, 20 })
        reset:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 6, 6)
        reset:SetScript("OnClick", function()
            MD.Tabs:Reset()
            pane.preview = nil
            pane:ListChanged()
        end)
        p.resetBtn = reset

        local done = UI.CreateButton(body, "Done", "accent-hover", { 70, 20 })
        done:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -6, 6)
        done:SetScript("OnClick", function() p:Hide() end)
        p.doneBtn = done

        pane.picker = p
        return p
    end

    -- [ + Add ]: the picker, refused in combat (6.6).
    function pane:OpenPicker()
        if not self.nav then return end
        if InCombat() then
            MD:Print("spells: the picker does not open in combat")
            return
        end
        local p = self.picker or BuildPicker()
        p:Show()
        -- 6.5: a sheet is an entry on T33's ESC stack (one ESC closes the
        -- picker, not the window); Done, the window hiding or the combat
        -- hide take it off through the manager's OnHide hook.
        MD.Win:Push(p)
        self:RefreshPicker()
    end

    ----------------------------------------------------------------------------
    -- The font offset (4.2): the rail's pitch and the picker follow it
    ----------------------------------------------------------------------------
    function pane:RailFontsChanged()
        local nav = self.nav
        if not nav then return end
        local g = SpellsGroup(nav)
        if g and g.rail then g.rail.rowHeight = Pitch(RAIL_ROW) end
        local rail = nav.rails and nav.rails[GROUP] and nav.rails[GROUP].rail
        if rail then rail:SetRowHeight(Pitch(RAIL_ROW)) end
        if self.picker and self.picker:IsShown() then self:RefreshPicker() end
    end

    ----------------------------------------------------------------------------
    -- Wiring (the dashboard file)
    ----------------------------------------------------------------------------
    -- The group's definition, built when the window is: the rail's rows are
    -- the list (seeded here on the first open). The row menu (Move up / Move
    -- down / Remove) and the drag are the kit's, reported through onMove /
    -- onRemove.
    function pane:Group()
        return { id = GROUP, text = "Spells", layout = "rail", views = self:Views(), rail = {
            title = "MY SPELLS",
            rowHeight = Pitch(RAIL_ROW),
            footerHeight = FOOTER_H,
            empty = "Add the spells you want to watch.",
            onSelect = function(id) if pane.RailSelected then pane:RailSelected(id) end end,
            onMove = function(id, to)
                local key = FamilyKey(id)
                if key and MD.Tabs:Move(key, to) then pane:ListChanged() end
            end,
            onRemove = function(id)
                local key = FamilyKey(id)
                if key then pane:Remove(key) end
            end,
            onDrop = function(at) pane:Drop(at) end,
            canDrop = function() return pane:CanDrop() end,
        } }
    end

    -- The nav built: its rail's footer.
    function pane:Attach(nav)
        self.nav = nav
        local rail = nav:Rail(GROUP)
        if rail and not self.addBtn then BuildFooter(rail) end
    end

    return pane
end
