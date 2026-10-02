-- tools/run.sh tools/spellsui.lua
--
-- T10 (docs/tasks/T10-spells-pane.md): the Spells -> Spellbook pane
-- (UI/Dashboard_Forever.lua) on UI/Dashboard_Rows.lua's now-shared table
-- widget. Forever only.
--
-- T36 (docs/SPEC-forever-ui.md 3.1-3.4, 3.6): rewritten for the Spells pane
-- that moved into UI/SpellsPane_Forever.lua. The Spells group is a rail
-- group: MY SPELLS, Overview, then one row per family of the player's list
-- (Spells/Tabs.lua). The T36 items hold the rail, the picker sheet, the drop
-- from the spellbook (the cursor never cleared), /st spell, the preview
-- banner and the pitches at a font offset of +2.
--
-- T39 (docs/SPEC-forever-ui.md 3.6): today's Spellbook table is Overview ->
-- Whole book under 3.5's look, so items 1-17 open "overview" in Whole book
-- and hold that table in its new shape -- 3.5's rank rows (a Tag column, no
-- star, no gold, To OOM from full), a gap a row of its own, a family header
-- for Other's families too, the rank row's hover the game's tooltip. Four
-- items after T38's hold Whole book (a row per rank of every family, the gap
-- row, + adds) and My spells.
--
-- T38 (docs/SPEC-forever-ui.md 3.5): eight items before the ASCII walk hold
-- one spell's view -- the header and the decision strip, the RANKS table, the
-- rank card, the row hover (the game's tooltip through MD.API.SetTooltipSpell,
-- the block added when no post-call runs, the edge, the kit tooltip's
-- reasons), each shape, the refresh split and the pitches, and no gold.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB
local Book = MD.Book
local UI = MD.UI

-- T36: anchors recorded for THIS suite only (the stub keeps none; navui's own
-- instrumentation, the same three methods), so the picker's anchor and its
-- mask's region can be read back.
local FrameMT = getmetatable(UIParent)
function FrameMT:SetPoint(p, rel, rp, x, y)
    if type(rel) == "number" then rel, rp, x, y = nil, p, rel, rp end
    self.points = self.points or {}
    self.points[p] = { rel = rel or self.parentFrame, rp = rp or p, x = x or 0, y = y or 0 }
end
function FrameMT:ClearAllPoints() self.points = {}; self.allPoints = nil end
function FrameMT:SetAllPoints(rel) self.points = {}; self.allPoints = rel or self.parentFrame end

--------------------------------------------------------------------------------
-- T36: the kindless fixtures first (they are no heal, so the seed does not
-- take them; the picker lists them), the rail and the picker against the
-- stub's own book (Healing Touch R1, Rejuvenation R1/R2, Wrath R1), then the
-- heal fixtures of items 1-17 and those items on the Overview view.
--------------------------------------------------------------------------------
-- item 1/Other section: a family with no heal/damage/absorb numbers at all,
-- but a mana cost -- T10c: a kindless family needs one to be worth comparing
-- on this table (a shapeshift costs mana; Facts).
S.AddSpell(92100, "Bearform", "Passive",
    function() return "You transform into a bear, increasing armor." end,
    { cast = 0, cost = 30, level = 10 })

-- T10c: a passive with no mana cost -- left off the pane, counted, and still
-- in the export.
S.AddSpell(92200, "Oakskin", "Passive",
    function() return "Increases your armor." end,
    { cast = 0, noCost = true, passive = true, level = 10 })

-- T10c: a kindless, non-passive spell whose description carries no amount at
-- all -- no mana cost either, so it is left off the pane the same as a
-- passive.
S.AddSpell(92201, "Swing", "",
    function() return "A melee attack." end,
    { cast = 0, noCost = true, level = 1 })

--------------------------------------------------------------------------------
-- T36 (docs/SPEC-forever-ui.md 3.1-3.4, 3.6): the rail and the picker. Each
-- block runs under pcall, so the old code (no rail, no MD.SpellsPane) fails
-- item by item instead of stopping the suite.
--------------------------------------------------------------------------------
local SP = MD.SpellsPane
local function T36(name, fn)
    local good, cond, detail = pcall(fn)
    if not good then check(name, false, "raised: " .. tostring(cond)) return end
    check(name, cond == true, detail)
end

local function Nav() return SP and SP.nav end
local function Rail() return Nav() and Nav():Rail("spells") end
local function RailIds()
    local ids = {}
    for _, r in ipairs(Rail() and Rail():Rows() or {}) do ids[#ids + 1] = r.id end
    return ids
end
local function RailRow(id)
    for _, r in ipairs(Rail() and Rail():Rows() or {}) do if r.id == id then return r end end
    return nil
end
local function Order() return table.concat(MD.Tabs:Get(), ",") end
local function ShownViewButtons()
    local n = 0
    for _, b in ipairs(Nav() and Nav().viewButtons or {}) do if b:IsShown() then n = n + 1 end end
    return n
end
local function PickerRow(key)
    for _, r in ipairs(SP.picker and SP.picker.rows or {}) do
        if r.key == key and r:IsShown() then return r end
    end
    return nil
end
local function Click(b, button)
    local fn = b and b:GetScript("OnClick")
    if fn then fn(b, button or "LeftButton") end
end
local function Tick(row, on)
    row.check:SetChecked(on)
    Click(row.check)
end
local chat = {}
local function Chat(fn)
    wipe(chat)
    local frame = _G.DEFAULT_CHAT_FRAME
    local saved = frame.AddMessage
    frame.AddMessage = function(_, m) chat[#chat + 1] = m end
    local good, err = pcall(fn)
    frame.AddMessage = saved
    if not good then error(err, 0) end
end
local function Slash(msg) SlashCmdList.SPELLTUNER(msg) end

-- 18: the Spells group is a rail
T36("the Spells group is a rail: MY SPELLS, Overview, then the seeded families", function()
    MD:SelectView("spells")
    local book = Book:Get()
    local rj = book.families["Rejuvenation"]
    local ids = RailIds()
    local htRow, rjRow = RailRow("fam:Healing Touch"), RailRow("fam:Rejuvenation")
    local st = MD.cdb.spellTabs
    local good = Rail() ~= nil and Rail().title:GetText() == "MY SPELLS"
        and table.concat(ids, ",") == "overview,fam:Healing Touch,fam:Rejuvenation"
        and st.seeded == true and Order() == "Healing Touch,Rejuvenation"
        and ShownViewButtons() == 0 and Nav().contentTop == -8
        and htRow.data.tag == "R1" and rjRow.data.tag == "R" .. rj.suggested.rank
        and htRow.data.icon == 136041
    return good, "rail=" .. table.concat(ids, ",") .. " order=" .. Order()
        .. " viewButtons=" .. ShownViewButtons()
end)

-- 19: the picker opens as a sheet over the view only, and lists the book
T36("+ Add opens the picker over the spell view, not over the rail", function()
    Click(SP.addBtn)
    local p = SP.picker
    local view = Nav():RailView("spells")
    local tl = p and p.points and p.points.TOPLEFT
    local ht, rj, wr = PickerRow("Healing Touch"), PickerRow("Rejuvenation"), PickerRow("Wrath")
    local good = p ~= nil and p:IsShown() and p.mask:IsShown() and p.mask.allPoints == view
        and tl ~= nil and tl.rel == Rail().frame and tl.rp == "TOPRIGHT" and tl.x == 4
        and ht ~= nil and ht.check:GetChecked() and rj ~= nil and rj.check:GetChecked()
        and wr ~= nil and not wr.check:GetChecked()
        and PickerRow("Oakskin") == nil -- a passive is not listed
        and PickerRow("Swing") ~= nil -- a free spell is, under Other
        and ht.section == "heal" and wr.section == "damage" and PickerRow("Swing").section == "other"
    return good, string.format("shown=%s mask=%s anchor=%s ht=%s wrath=%s",
        tostring(p and p:IsShown()), tostring(p and p.mask.allPoints == view),
        tostring(tl and tl.rp), tostring(ht ~= nil), tostring(wr ~= nil))
end)

-- 20: a tick adds a view
T36("a tick adds the family to the rail as a view", function()
    Tick(PickerRow("Wrath"), true)
    Click(SP.picker.doneBtn)
    local views = {}
    for _, g in ipairs(Nav().groups) do
        if g.id == "spells" then for _, v in ipairs(g.views) do views[#views + 1] = v.id end end
    end
    MD:SelectView("spells", "fam:Wrath")
    local _, view = Nav():Selected()
    local good = Order() == "Healing Touch,Rejuvenation,Wrath"
        and RailRow("fam:Wrath") ~= nil and views[#views] == "fam:Wrath"
        and view == "fam:Wrath" and SP.picker:IsShown() == false -- Done only closes the sheet
    return good, "order=" .. Order() .. " view=" .. tostring(view)
end)

-- 21: unticking removes (and records it); Undo in the rail puts it back
T36("unticking removes it, and the rail's Undo line brings it back", function()
    Click(SP.addBtn)
    Tick(PickerRow("Wrath"), false)
    local removed = MD.cdb.spellTabs.removed["Wrath"] == true
    local line = SP.undoText:IsShown() and SP.undoText:GetText() or ""
    local gone = RailRow("fam:Wrath") == nil
    Click(SP.undoBtn)
    local back = Order() == "Healing Touch,Rejuvenation,Wrath" and RailRow("fam:Wrath") ~= nil
        and PickerRow("Wrath").check:GetChecked() and not SP.undoText:IsShown()
    return removed and gone and line == "Wrath removed" and back,
        string.format("removed=%s line=%q back=%s", tostring(removed), line, tostring(back))
end)

-- 22: the search box filters by substring as you type
T36("the picker's search filters by substring", function()
    SP.picker.search:SetText("JUV")
    SP.picker.search:GetScript("OnTextChanged")(SP.picker.search, true)
    local only = PickerRow("Rejuvenation") ~= nil and PickerRow("Healing Touch") == nil and PickerRow("Wrath") == nil
    SP.picker.search:SetText("")
    SP.picker.search:GetScript("OnTextChanged")(SP.picker.search, true)
    return only and PickerRow("Healing Touch") ~= nil, "filtered=" .. tostring(only)
end)

-- 23: a spellbook spell dropped on a row goes in at that row; the cursor stays
T36("a drop adds at the row and leaves the cursor as it was", function()
    Click(SP.picker.doneBtn)
    Rail().opts.onRemove("fam:Wrath")
    local cursor = { "spell", 3, "spell", 5176 }
    S.cursor = cursor
    local before = S.clearCursorCalls
    local ht = RailRow("fam:Healing Touch")
    ht:GetScript("OnReceiveDrag")(ht)
    local good = Order() == "Wrath,Healing Touch,Rejuvenation"
        and S.cursor == cursor and S.cursor[4] == 5176 and S.clearCursorCalls == before
        and SP.picker:IsShown() == false
    S.cursor = nil
    return good, "order=" .. Order() .. " cleared=" .. (S.clearCursorCalls - before)
end)

-- 24: something that is not a spell adds nothing; a click with a spell on
-- the cursor drops rather than selects
T36("an item on the cursor adds nothing; a click with a spell drops it", function()
    Rail().opts.onRemove("fam:Wrath")
    S.cursor = { "item", 6948 }
    local ht = RailRow("fam:Healing Touch")
    ht:GetScript("OnReceiveDrag")(ht)
    local itemNothing = Order() == "Healing Touch,Rejuvenation"
    S.cursor = { "spell", 3, "spell", 5176 }
    local rj = RailRow("fam:Rejuvenation")
    Click(rj)
    local _, view = Nav():Selected()
    local dropped = Order() == "Healing Touch,Wrath,Rejuvenation" and view ~= "fam:Rejuvenation"
    S.cursor = nil
    return itemNothing and dropped, "item=" .. tostring(itemNothing) .. " order=" .. Order()
end)

-- 25: the rail stays live while the picker is open
T36("the rail takes a drop while the picker is open, and the picker follows", function()
    Rail().opts.onRemove("fam:Wrath")
    Click(SP.addBtn)
    local unticked = not PickerRow("Wrath").check:GetChecked()
    S.cursor = { "spell", 3, "spell", 5176 }
    Rail().frame:GetScript("OnReceiveDrag")(Rail().frame)
    S.cursor = nil
    local good = unticked and Order() == "Healing Touch,Rejuvenation,Wrath"
        and SP.picker:IsShown() and PickerRow("Wrath").check:GetChecked()
    Click(SP.picker.doneBtn)
    return good, "order=" .. Order()
end)

-- 26: the adapter answers the cursor's spell id only when it is plain
T36("MD.API.CursorInfo answers a spell id only when plain", function()
    S.cursor = { "spell", 3, "spell", 5176 }
    local k1, id1 = MD.API.CursorInfo()
    S.cursor = { "spell", 3, "spell", S.Secret() }
    local k2, id2 = MD.API.CursorInfo()
    S.cursor = { "item", 6948 }
    local k3, id3 = MD.API.CursorInfo()
    S.cursor = nil
    local k4, id4 = MD.API.CursorInfo()
    return k1 == "spell" and id1 == 5176 and id2 == nil and k3 == "item" and id3 == nil
        and k4 == nil and id4 == nil,
        string.format("%s/%s %s/%s %s/%s %s/%s", tostring(k1), tostring(id1), tostring(k2), tostring(id2),
            tostring(k3), tostring(id3), tostring(k4), tostring(id4))
end)

-- 27: /st spell <name> selects the view, through the window manager
T36("/st spell selects one, through MD.Win:ShowMain", function()
    MD:SelectView("settings", "modules")
    local calls = {}
    local orig = MD.Win.ShowMain
    MD.Win.ShowMain = function(self, g, v) calls[#calls + 1] = tostring(g) .. "/" .. tostring(v); return orig(self, g, v) end
    Slash("spell reju")
    MD.Win.ShowMain = orig
    local g, view = Nav():Selected()
    return g == "spells" and view == "fam:Rejuvenation" and calls[#calls] == "spells/fam:Rejuvenation"
        and RailRow("fam:Rejuvenation").selected == true,
        "selected=" .. tostring(g) .. "/" .. tostring(view) .. " calls=" .. table.concat(calls, ";")
end)

-- 28: a family not in the list opens as a preview, with its banner
T36("/st spell on a family not in the list opens its preview; Add lists it", function()
    Rail().opts.onRemove("fam:Wrath")
    Slash("spell WRA")
    local banner = SP.banner
    local text = banner and banner:IsShown() and banner.text:GetText() or ""
    local previewing = SP.family:IsShown() and SP.family.key == "Wrath"
    local noneSelected = true
    for _, r in ipairs(Rail():Rows()) do if r.selected then noneSelected = false end end
    Click(banner.addBtn)
    local _, view = Nav():Selected()
    local good = text:find("Not in your list.", 1, true) ~= nil and previewing and noneSelected
        and Order() == "Healing Touch,Rejuvenation,Wrath" and view == "fam:Wrath" and not banner:IsShown()
    return good, string.format("banner=%q previewing=%s noneSelected=%s view=%s", text,
        tostring(previewing), tostring(noneSelected), tostring(view))
end)

-- 29: no match says so and changes nothing
T36("/st spell with no match says so", function()
    local before = Order()
    Chat(function() Slash("spell zzz") end)
    local line = chat[1] or ""
    return Order() == before and line:find("zzz", 1, true) ~= nil and line:find("no spell", 1, true) ~= nil,
        line
end)

-- 30: a family the book no longer has stays, greyed, with its own Remove
T36("a family the book no longer has stays in the rail, greyed, with Remove", function()
    table.insert(MD.cdb.spellTabs.order, "Healing Wave")
    SP:RefreshRail()
    local row = RailRow("fam:Healing Wave")
    local stale = row ~= nil and row.data.stale == true
    MD:SelectView("spells", "fam:Healing Wave")
    local msg = SP.family.staleText:IsShown() and SP.family.staleText:GetText() or ""
    Click(SP.family.removeBtn)
    return stale and msg == "Healing Wave is not in this character's spellbook." and RailRow("fam:Healing Wave") == nil
        and Order() == "Healing Touch,Rejuvenation,Wrath", "msg=" .. msg .. " order=" .. Order()
end)

-- 31: a heal learned later is appended with the new dot until it is opened
T36("a newly learned heal appears with the new dot until opened", function()
    S.AddSpell(92400, "Regrowth", "Rank 1",
        function() return "Heals a friendly target for 84 to 98." end,
        { cast = 2000, cost = 80, level = 12 })
    Book:MarkDirty()
    MD:SelectView("spells", "overview")
    local row = RailRow("fam:Regrowth")
    local dot = row ~= nil and row.data.new == true and row.dot:IsShown()
    MD:SelectView("spells", "fam:Regrowth")
    row = RailRow("fam:Regrowth")
    return dot and row.data.new ~= true and not row.dot:IsShown(), "dot=" .. tostring(dot)
end)

-- 31b: a family clicked in Overview opens: its view when listed, else its preview
T36("a family clicked in Overview opens its view, or its preview when not listed", function()
    MD:SelectView("spells", "overview")
    if SP.SetOverviewMode then SP:SetOverviewMode("mine") end -- T39: a listed family clicked in My spells
    local function ClickFamily(name)
        for _, f in ipairs(S.allFrames) do
            -- T39: a My spells row ("mine") or a Whole book family header ("family")
            if f.cells and f.data and (f.data.kind == "family" or f.data.kind == "mine")
                and f.data.family and f.data.family.name == name and f:IsShown()
                and f:GetScript("OnMouseUp") then
                f:GetScript("OnMouseUp")(f, "LeftButton") -- the table's click (T30's onClick)
                return true
            end
        end
        return false
    end
    local clickedRj = ClickFamily("Rejuvenation")
    local _, v1 = Nav():Selected()
    Rail().opts.onRemove("fam:Wrath")
    MD:SelectView("spells", "overview")
    if SP.SetOverviewMode then SP:SetOverviewMode("book") end -- T39: not listed, so only Whole book has it
    local clickedWr = ClickFamily("Wrath")
    local _, v2 = Nav():Selected()
    local preview = SP.banner:IsShown() and SP.family.key == "Wrath"
    SP:Undo()
    return clickedRj and v1 == "fam:Rejuvenation" and clickedWr and v2 == "overview" and preview
        and Order() == "Healing Touch,Rejuvenation,Wrath,Regrowth",
        string.format("v1=%s v2=%s preview=%s order=%s", tostring(v1), tostring(v2), tostring(preview), Order())
end)

-- 32: the picker refuses to open in combat
T36("the picker does not open in combat", function()
    S.inCombat = true
    Chat(function() Click(SP.addBtn) end)
    S.inCombat = false
    return SP.picker:IsShown() == false and (chat[1] or ""):find("combat", 1, true) ~= nil, chat[1]
end)

-- 32b (integration of T33 and T36, 6.5: "the sheets" join the ESC stack): with
-- the picker open, one ESC closes the picker and leaves the window up
T36("one ESC closes the picker, not the window (T33's stack)", function()
    MD:SelectView("spells", "fam:Healing Touch")
    local frame = _G.SpellTunerDashboard
    if frame and not frame:IsShown() then frame:Show() end
    Click(SP.addBtn)
    local opened = SP.picker:IsShown()
    local names = {}
    for _, name in ipairs(UISpecialFrames) do names[#names + 1] = name end
    for _, name in ipairs(names) do
        local f = _G[name]
        if f and f:IsShown() then f:Hide() end
    end
    local pickerUp, frameUp = SP.picker:IsShown(), frame and frame:IsShown()
    -- T54 (P10, review Q8): the next frame is a tick of the stub's clock, which
    -- runs the proxy's After(0) re-arm -- not a hand-run of the queue -- and
    -- nothing is left pending after it
    S.Tick(0)
    local left = S.Pending and S.Pending() or #(S.timers or {})
    local proxy = _G.SpellTunerEscProxy
    return opened and not pickerUp and frameUp == true and proxy ~= nil and proxy:IsShown() and left == 0,
        string.format("opened=%s picker=%s frame=%s proxy=%s pending=%s", tostring(opened), tostring(pickerUp),
            tostring(frameUp), tostring(proxy and proxy:IsShown()), tostring(left))
end)

-- 33: the pitches grow with the font offset, and the pane re-renders at once
T36("at font offset +2 the rail rows are 22 tall (21 apart, the 1-px overlap)", function()
    MD:SelectView("spells", "fam:Healing Touch")
    UI.ApplyFonts(2)
    local a, b = RailRow("fam:Healing Touch"), RailRow("fam:Rejuvenation")
    local h, gap = a:GetHeight(), b.top - a.top
    local headH = SP.family.header:GetHeight()
    UI.ApplyFonts(0)
    local h0 = RailRow("fam:Healing Touch"):GetHeight()
    return h == 22 and gap == 21 and headH == 50 and h0 == 20,
        string.format("height=%s apart=%s header=%s back=%s", tostring(h), tostring(gap), tostring(headH), tostring(h0))
end)

-- T77 (P33 of docs/PLAN-refactor-ux.md, review A31): the pane re-pitches on
-- the kit's FONTS_CHANGED event -- it no longer wraps UI.ApplyFonts, so the
-- event alone (the offset already applied) re-renders the rail and the view
T36("T77: FONTS_CHANGED alone re-pitches the rail and the spell view", function()
    MD:SelectView("spells", "fam:Healing Touch")
    local saved = UI.fontOffset
    UI.fontOffset = 2
    MD:Fire("FONTS_CHANGED", 2)
    local a, b = RailRow("fam:Healing Touch"), RailRow("fam:Rejuvenation")
    local h, gap = a:GetHeight(), b.top - a.top
    local headH = SP.family.header:GetHeight()
    UI.fontOffset = saved
    MD:Fire("FONTS_CHANGED", saved)
    local h0 = RailRow("fam:Healing Touch"):GetHeight()
    return h == 22 and gap == 21 and headH == 50 and h0 == 20,
        string.format("height=%s apart=%s header=%s back=%s", tostring(h), tostring(gap), tostring(headH), tostring(h0))
end)

-- T77 (P33, review U8; mockup M4): a rail row hovered for half a second says
-- what its tag is -- the suggested rank among the known ones and its per
-- mana -- and how to move it
T36("T77: a rail row's tooltip: Suggested  Rank N of M known, Per mana, the drag hint", function()
    MD:SelectView("spells", "overview")
    local fam = MD.Book:Get().families["Rejuvenation"]
    local s = fam and fam.suggested
    local known = 0
    for _, e in ipairs(fam and fam.ranks or {}) do if e.known ~= false then known = known + 1 end end
    local want = s and string.format("Rank %d of %d known", s.rank, known)
    local row = RailRow("fam:Rejuvenation")
    local tt = UI.tooltip
    tt:Hide(); tt.lines = {}
    row:GetScript("OnEnter")(row)
    S.Tick(0.2)
    local early = tt:IsShown()
    S.Tick(0.4)
    local got, pm, hint = false, false, false
    for _, l in ipairs(tt.lines or {}) do
        if l[1] == "Suggested" and l[2] == want then got = true end
        if l[1] == "Per mana" and l[2] == MD.Words.PerMana(s, "cell") then pm = true end
        if l[1] == UI.RAIL_HINT then hint = true end
    end
    local first = tt.lines and tt.lines[1] and tt.lines[1][1]
    local shown = tt:IsShown()
    row:GetScript("OnLeave")(row)
    return not early and shown and first == "Rejuvenation" and got and pm and hint and not tt:IsShown(),
        string.format("early=%s shown=%s first=%s want=%s suggested=%s permana=%s hint=%s", tostring(early),
            tostring(shown), tostring(first), tostring(want), tostring(got), tostring(pm), tostring(hint))
end)

--------------------------------------------------------------------------------
-- fixtures -- named for which acceptance item they exercise. The four fixed
-- slots (5185 Healing Touch R1, 774/1058 Rejuvenation R1/R2, 5176 Wrath R1)
-- are already in the stub (tools/wowstub.lua); Rejuvenation R2 dominates R1
-- and is the family's suggested rank (T7's own scan, docs/tasks/T7-spell-book.md
-- Report), which item 3 relies on directly rather than re-deriving it.
--------------------------------------------------------------------------------

-- item 4: a third Healing Touch rank whose text carries no heal numbers at
-- all -- Book's own PartValue returns nil,nil for it, so value/per mana/per
-- second/casts must render "-", never 0, even though the family's kind is
-- still "heal" (from rank 1).
S.AddSpell(92003, "Healing Touch", "Rank 3",
    function() return "This rank requires no reagent." end,
    { cast = 0, cost = 10, level = 20 })

-- item 5: a family listed from rank 2 only (a gap) -- shares tools/bookcheck.lua's
-- own construction.
S.AddSpell(92011, "GapFamily", "Rank 2",
    function() return "Heals a friendly target for 40 to 50." end,
    { cast = 0, cost = 25, level = 10 })

-- item 6: a spell costly enough that the chain-cast interval does NOT let
-- regen alone cover it (Engine/RankMath.lua's CastsToOOM: "inf" whenever
-- regen*interval >= cost, no matter how little mana is left, which is why
-- the cheap fixtures above -- and the real Healing Touch/Wrath fixtures --
-- all read "inf" against either pool and cannot show the pool ever mattered).
-- 300 mana vs. this stub's out-of-combat casting rate (28.33) * a 1.5s
-- interval = 42.5 leaves a strictly positive net, so the current pool decides
-- a finite answer.
S.AddSpell(92050, "BigSpell", "Rank 1",
    function() return "Heals a friendly target for 90 to 110." end,
    { cast = 1500, cost = 300, level = 1 })
-- T36: the book was read by the rail above; these are new to it
Book:MarkDirty()

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function Num(v, decimals)
    if type(v) ~= "number" or v ~= v then return "-" end
    if decimals then return string.format("%." .. decimals .. "f", v) end
    return tostring(math.floor(v + 0.5))
end

local function ManaText(e)
    -- review R13: a Rage / Focus / Energy cost is named, never read as mana
    if e.cost and type(e.cost.power) == "string" and type(e.cost.powerAmount) == "number" then
        return Num(e.cost.powerAmount) .. " " .. e.cost.power
    end
    if e.costState == "free" then return "free" end
    if e.cost then
        if type(e.cost.amount) == "number" then return Num(e.cost.amount) end
        if type(e.cost.percent) == "number" then return Num(e.cost.percent, 0) .. "%" end
    end
    return "-"
end

local function CastText(e)
    if e.castKind == "instant" then return "inst" end
    if e.castKind == "channeled" then return "chan" end
    if type(e.cast) == "number" then return Num(e.cast, 1) .. "s" end
    return "-"
end

-- T39: Whole book's To OOM is 3.5's -- casts from a FULL pool at the
-- clock's max and casting regen, never the drained current pool.
local function FullCasts(e)
    local pool = MD.Clock:Pool()
    return Book:CastsFor(e, { max = pool.max, regenCasting = pool.regenCasting })
end

local function CastsWord(n)
    if n == math.huge then return "inf" end
    if type(n) == "number" then return Num(n, 0) end
    return "-"
end

-- T39: the RANKS table's Tag column (3.5): best, learn at N, max, and (T78,
-- P34, the author's word, docs/PLAN-refactor-ux.md 8.1 item 7) beaten.
local function TagText(e, family)
    if e.suggested then return "best" end
    if e.known == false then return (type(e.level) == "number") and ("learn at " .. e.level) or "not learned" end
    if family and family.maxKnown == e then return "max" end
    if e.dominated then return "beaten" end
    return ""
end

local function SpellTipBlocks(tt)
    local n = 0
    for _, line in ipairs(tt.lines or {}) do if line[1] == "SpellTuner" then n = n + 1 end end
    return n
end

local function StripColor(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- UI/Style.lua's own header close button ("x", U+00D7, line 166) -- shared by
-- every Cell-style window in the tree and already an accepted, named
-- exception in tools/modulecheck.lua's own ASCII walk (Review, 2026-09-28).
local CLOSE_GLYPH = "\195\151"

local function AsciiNoBarePipe(text)
    if text == CLOSE_GLYPH then return true end
    for i = 1, #text do
        if text:byte(i) > 126 then return false, "non-ascii" end
    end
    local stripped = text:gsub("||", "")
    stripped = stripped:gsub("|c%x%x%x%x%x%x%x%x", "")
    stripped = stripped:gsub("|r", "")
    if stripped:find("|") then return false, "bare pipe" end
    return true
end

-- The pane is the frame UI/Dashboard_Forever.lua marks with .spellsBook, the
-- same convention modulecheck's placeholder-era fixture used.
local function FindPane()
    for _, f in ipairs(S.allFrames) do
        if f.spellsBook then return f end
    end
    return nil
end

-- The row frame CreateTable built for one row descriptor `r` -- table
-- identity, since row.data IS the very same table Render() was handed
-- (UI/Dashboard_Rows.lua's generic branch), never a copy.
local function RowFor(rows, r)
    for _, f in ipairs(S.allFrames) do
        if f.cells and f.data == r then return f end
    end
    return nil
end

local function CellText(row, key)
    local fs = row and row.cells and row.cells[key]
    return fs and StripColor(fs:GetText() or "") or nil
end

-- T39: today's table is Overview -> Whole book (3.6); lastRows is the table
-- the pane shows
local function OpenPane()
    MD:SelectView("spells", "overview")
    if SP.SetOverviewMode then SP:SetOverviewMode("book") end
    return FindPane()
end

local function FamilyRow(rows, name)
    for _, r in ipairs(rows or {}) do
        if r.kind == "family" and r.family.name == name then return r end
    end
    return nil
end
local function EntryRow(rows, id)
    for _, r in ipairs(rows or {}) do
        if r.kind == "rank" and r.entry.id == id then return r end -- T39: 3.5's rank rows
    end
    return nil
end
local function NoteRow(rows, substring)
    for _, r in ipairs(rows or {}) do
        if r.kind == "note" and r.text:find(substring, 1, true) then return r end
    end
    return nil
end

local function IndexOf(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
    return nil
end

local pane = OpenPane()
if not pane then error("spellsui: no .spellsBook pane found -- fixture/build is broken, not one of the 11 acceptance items") end

--------------------------------------------------------------------------------
-- 1: the Spellbook view lists every family of the book, heals then damage
-- then other
--------------------------------------------------------------------------------
-- T39: every listed family, Other's included, gets a header row ("family")
-- with its ranks under it.
local sectionOrder = {}
for _, r in ipairs(pane.lastRows or {}) do
    if r.kind == "family" then
        sectionOrder[#sectionOrder + 1] = r.family.name
    end
end
do
    local iHT, iRejuv = IndexOf(sectionOrder, "Healing Touch"), IndexOf(sectionOrder, "Rejuvenation")
    local iWrath = IndexOf(sectionOrder, "Wrath")
    local iBear = IndexOf(sectionOrder, "Bearform")
    local order = iHT ~= nil and iRejuv ~= nil and iWrath ~= nil and iBear ~= nil
        and iHT < iRejuv and iRejuv < iWrath and iWrath < iBear

    check("Whole book lists every family of the book, heals then damage then other", -- T39
        order == true, "order=" .. table.concat(sectionOrder, ", "))
end

--------------------------------------------------------------------------------
-- 2: each rank row shows the book's own numbers
--------------------------------------------------------------------------------
do
    local bad
    local checked = 0
    for _, r in ipairs(pane.lastRows or {}) do
        if r.kind == "rank" then -- T39: 3.5's RANKS columns, no star, a Tag column
            local e = r.entry
            local row = RowFor(pane.lastRows, r)
            if not row then
                bad = bad or ("no row frame for id " .. tostring(e.id))
            else
                checked = checked + 1
                local wantRank = e.rank and ("R" .. e.rank) or "-"
                local valued = r.family.kind ~= nil -- a family with no value leaves its value cells empty
                local expect = {
                    { "rank", wantRank }, { "level", Num(e.level) }, { "mana", ManaText(e) },
                    { "value", valued and Num(e.value) or "" }, { "permana", valued and Num(e.perMana, 2) or "" },
                    { "persec", valued and Num(e.perSec, 1) or "" },
                    -- review R38: the row's own count; T39: from a full pool (3.5)
                    { "cast", CastText(e) }, { "toOOM", valued and CastsWord(FullCasts(e)) or "" },
                    { "tag", TagText(e, r.family) },
                }
                for _, p in ipairs(expect) do
                    local key, want = p[1], p[2]
                    local got = CellText(row, key)
                    if got ~= want and not bad then
                        bad = string.format("id=%s col=%s got=%q want=%q", tostring(e.id), key, tostring(got), tostring(want))
                    end
                end
            end
        end
    end
    check("each rank row shows the book's own numbers", bad == nil and checked > 0,
        bad or ("checked=" .. checked))
end

--------------------------------------------------------------------------------
-- 3 (T39): the suggested rank is tagged best and marked by the bar and the
-- fill -- no star, no "suggested:" in the header, no gold anywhere
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local rejuv = book.families["Rejuvenation"]
    local r2 = book.spells[1058]

    local headerRow = RowFor(pane.lastRows, FamilyRow(pane.lastRows, "Rejuvenation"))
    local headerText = CellText(headerRow, "wide") -- T10c: family text moved off the Rank column

    local r2Row = RowFor(pane.lastRows, EntryRow(pane.lastRows, 1058))
    local r2RankCell = CellText(r2Row, "rank")
    local gold
    for _, r in ipairs(pane.lastRows or {}) do
        local row = RowFor(pane.lastRows, r)
        for _, fs in pairs(row and row.cells or {}) do
            local t = (fs:GetText() or ""):lower()
            if not gold and (t:find("ffcc00", 1, true) or t:find("ffd100", 1, true)) then gold = t end
        end
    end
    local fill = r2Row and r2Row.fill and r2Row.fill:IsShown() and r2Row.fill.color and r2Row.fill.color[4]

    check("the suggested rank is tagged best and marked by the bar, never starred or gold",
        rejuv.suggested == r2 and r2.suggested == true
        and headerText == "Rejuvenation" and r2RankCell == "R2" and CellText(r2Row, "tag") == "best"
        and r2Row.mark ~= nil and r2Row.mark:IsShown() and fill == 0.10 and gold == nil,
        string.format("suggestedId=%s header=%q rankCell=%q tag=%q fill=%s gold=%s",
            tostring(rejuv.suggested and rejuv.suggested.id), tostring(headerText), tostring(r2RankCell),
            tostring(CellText(r2Row, "tag")), tostring(fill), tostring(gold)))
end

--------------------------------------------------------------------------------
-- 4: a number the book does not have is a dash, never a zero
--------------------------------------------------------------------------------
do
    -- Healing Touch Rank 3 (92003) has no heal numbers in its own text
    -- (PartValue reads nil,nil for it -- Spells/Book.lua), so value/per
    -- mana/per second have nothing to be computed from. Casts to OOM stays
    -- OUT of this check: it is a function of cost/interval/pool alone
    -- (Spells/Book.lua's CastsToOOM), never of `value`, so a rank with no
    -- amount can still legitimately answer "inf" there -- that is not this
    -- rule's zero-vs-dash question.
    local book = Book:Get()
    local e = book.spells[92003]
    local row = RowFor(pane.lastRows, EntryRow(pane.lastRows, 92003))
    local valueCell, permanaCell, persecCell = CellText(row, "value"), CellText(row, "permana"), CellText(row, "persec")

    check("a number the book does not have is a dash, never a zero",
        e.value == nil and e.perMana == nil and e.perSec == nil
        and valueCell == "-" and permanaCell == "-" and persecCell == "-",
        string.format("value=%s permana=%s persec=%s", tostring(valueCell), tostring(permanaCell), tostring(persecCell)))
end

--------------------------------------------------------------------------------
-- 5: gaps and stale values are noted under the family
--------------------------------------------------------------------------------
do
    -- T39: a gap is a row of its own under the family (3.5), not a note
    local gapNote
    for i, r in ipairs(pane.lastRows or {}) do
        if r.kind == "gap" and r.family.name == "GapFamily" and r.rank == 1 then
            local after = pane.lastRows[i + 1]
            if after and after.kind == "rank" and after.entry.id == 92011 then gapNote = r end
        end
    end
    local gapGood = gapNote ~= nil

    -- the stale value: 5185's description goes secret in combat (tools/wowstub.lua),
    -- the same mechanic tools/tipcheck.lua's own stale test uses.
    S.inCombat = false
    Book:MarkDirty(); Book:Get()
    S.inCombat = true
    Book:MarkDirty(); Book:Get()
    S.inCombat = false

    local pane2 = OpenPane()
    local staleNote = NoteRow(pane2.lastRows, "Text read before combat - may be out of date")
    local staleUnder = false
    for i, r in ipairs(pane2.lastRows or {}) do
        if r == staleNote then
            local prev = pane2.lastRows[i - 1]
            staleUnder = prev ~= nil and prev.kind == "family" and prev.family.name == "Healing Touch"
        end
    end

    check("gaps and stale values are noted under the family",
        gapGood and staleNote ~= nil and staleUnder,
        string.format("gap=%s stale=%s under=%s", tostring(gapNote and gapNote.rank),
            tostring(staleNote and staleNote.text), tostring(staleUnder)))

    Book:MarkDirty(); Book:Get()
    pane = OpenPane()
end

--------------------------------------------------------------------------------
-- 6: casts to OOM use the clock's modelled pool when there is one
--------------------------------------------------------------------------------
do
    local book = Book:Get()
    local defaultPool = Book:DefaultPool()
    Book:Rows(book.families["BigSpell"], defaultPool)
    local defaultCasts = book.spells[92050].casts -- against the DEFAULT pool (pool.max = 7009, no drain)

    -- drain the clock's own modelled pool below BigSpell's cost (300) --
    -- the default pool would never do this.
    MD.Clock.model:Anchor(GetTime(), 5, "test: drained for spellsui")
    local pane3 = OpenPane()
    local r = EntryRow(pane3.lastRows, 92050)
    local cell = CellText(RowFor(pane3.lastRows, r), "toOOM")
    local fromFull = FullCasts(Book:Get().spells[92050]) -- T39: 3.5's To OOM, the clock's max full

    -- review R38: the pane counts on its own row (r.casts), never in the
    -- entries Book:Get() shares -- the very scan it drew from still holds
    -- the from-full count, and so does the spell tooltip read from it.
    local cachedEntry = Book:Get().spells[92050]
    local tip = MD.SpellTip:Lines(92050)
    local tipCasts
    for _, line in ipairs(tip or {}) do
        -- T37 / T78: the block reads "N from full, ~M now" -- its from-full count is N
        if type(line[1]) == "string" and line[1]:find("Casts to OOM", 1, true) then
            tipCasts = tostring(line[2]):match("^(%S+) from full") -- T78
        end
    end

    check("casts to OOM count from the clock's pool when full, never the drained one",
        type(defaultCasts) == "number" and defaultCasts > 0 and defaultCasts ~= math.huge
        and type(fromFull) == "number" and fromFull > 0 and fromFull ~= math.huge
        and r ~= nil and r.fullCasts == fromFull and cell == Num(fromFull),
        string.format("defaultPoolCasts=%s fromFull=%s rowCasts=%s cell=%s",
            tostring(defaultCasts), tostring(fromFull), tostring(r and r.fullCasts), tostring(cell)))
    check("the pane never rewrites the book's own casts to OOM",
        cachedEntry.casts == defaultCasts and tipCasts == tostring(defaultCasts),
        string.format("book entry=%s tooltip=%s from full=%s",
            tostring(cachedEntry.casts), tostring(tipCasts), tostring(defaultCasts)))

    -- restore a full modelled pool so nothing after this item is affected.
    MD.Clock.model:Anchor(GetTime(), MD.Clock.model.max, "test: restored")
    pane = OpenPane()
end

--------------------------------------------------------------------------------
-- 7: hovering a row shows the spell's tooltip block
--------------------------------------------------------------------------------
do
    -- T39: a rank row's hover is 3.5's -- the game's own tooltip for that
    -- rank, the SpellTuner block under it once
    local row = RowFor(pane.lastRows, EntryRow(pane.lastRows, 5185))
    local enter = row and row:GetScript("OnEnter")
    GameTooltip.lines = nil
    S.setSpellByIdCalls = {}
    if enter then enter(row) end
    local calls = table.concat(S.setSpellByIdCalls, ",")
    S.setSpellByIdCalls = nil
    local blocks = SpellTipBlocks(GameTooltip)
    local first = GameTooltip.lines and GameTooltip.lines[1] and GameTooltip.lines[1][1]
    check("hovering a row shows the spell's tooltip block",
        row ~= nil and calls == "5185" and first == "Healing Touch" and blocks == 1,
        string.format("calls=%s first=%s blocks=%d", calls, tostring(first), blocks))

    local leave = row and row:GetScript("OnLeave")
    if leave then leave(row) end
end

--------------------------------------------------------------------------------
-- 8: the export is the probe's block format with cost, cast and level
--------------------------------------------------------------------------------
local exportText
do
    local captured
    local origShow = MD.ShowCopyPopup
    MD.ShowCopyPopup = function(self, title, text) captured = { title = title, text = text } end
    pane.exportBtn:GetScript("OnClick")(pane.exportBtn)
    MD.ShowCopyPopup = origShow

    exportText = captured and captured.text
    local hasCharLine = exportText ~= nil and exportText:find("^character: %S+ %S+ %S+ level %d+") ~= nil
    local hasSection = exportText ~= nil and exportText:find("\n== spells\n", 1, true) ~= nil
    local hasSpellBlock = exportText ~= nil
        and exportText:find("spell 5185\n  name: Healing Touch\n  rank: Rank 1\n  desc: ", 1, true) ~= nil
    local hasCostCastLevel = exportText ~= nil
        and exportText:find("\n  cost: 25 Mana\n", 1, true) ~= nil
        and exportText:find("\n  cast: 1.5 sec cast\n", 1, true) ~= nil
        and exportText:find("\n  level: 1", 1, true) ~= nil

    -- python3 tools/refcheck.py <export> --data tools/data/refcheck-fixture/data.json
    -- (Acceptance: run with os.execute only if python3 is on PATH, else a
    -- printed skip -- folded into this one item's own condition rather than a
    -- twelfth named assertion).
    local refcheckOk = true
    local hasPython = os.execute("command -v python3 >/dev/null 2>&1")
    if hasPython == true or hasPython == 0 then
        local root = S.root or "."
        local path = root .. "/.spellsui-export.tmp.txt"
        local f = io.open(path, "w")
        f:write(exportText or "")
        f:close()
        local cmd = string.format('python3 "%s/tools/refcheck.py" "%s" --data "%s/tools/data/refcheck-fixture/data.json" >/dev/null 2>&1',
            root, path, root)
        local rc = os.execute(cmd)
        os.remove(path)
        refcheckOk = (rc == true or rc == 0)
    else
        print("  (skip: python3 not on PATH -- refcheck.py not run)")
    end

    check("the export is the probe's block format with cost, cast and level",
        captured ~= nil and captured.title == "SpellTuner spellbook"
        and hasCharLine and hasSection and hasSpellBlock and hasCostCastLevel and refcheckOk,
        string.format("hasCharLine=%s hasSection=%s hasSpellBlock=%s hasCostCastLevel=%s refcheckOk=%s",
            tostring(hasCharLine), tostring(hasSection), tostring(hasSpellBlock), tostring(hasCostCastLevel), tostring(refcheckOk)))
end

--------------------------------------------------------------------------------
-- 8b (review B20, T50): the export's character line is escaped like every
-- other client string in it -- a name with a diaeresis ("Zoe", e-umlaut, two
-- UTF-8 bytes) exports as the probe's "\ddd" escapes, ASCII with no bare pipe.
--------------------------------------------------------------------------------
do
    local player = S.units.player
    local oldName = player.name
    player.name = "Zo\195\171|x"
    local captured
    local origShow = MD.ShowCopyPopup
    MD.ShowCopyPopup = function(self, title, text) captured = { title = title, text = text } end
    pane.exportBtn:GetScript("OnClick")(pane.exportBtn)
    MD.ShowCopyPopup = origShow
    player.name = oldName

    local text = captured and captured.text or ""
    local first = text:match("^[^\n]*") or ""
    local good, why = AsciiNoBarePipe(text)
    check("a non-ASCII character name exports escaped, ASCII with no bare pipe",
        good and first:find("character: Zo\\195\\171||x ", 1, true) == 1,
        string.format("%s; line=%q", tostring(why or "ascii"), first))
end

--------------------------------------------------------------------------------
-- 9: the pane refreshes on show and every two seconds while shown, not while
-- hidden
--------------------------------------------------------------------------------
do
    pane = OpenPane() -- OnShow already refreshed it once
    local afterShow = pane.refreshCount

    for _ = 1, 3 do S.Tick(0.5) end -- 1.5s: not yet due
    local before2s = pane.refreshCount

    S.Tick(0.5) -- crosses 2s
    local after2s = pane.refreshCount

    -- hide the window (select another group) -- the ticker must not refresh
    -- a hidden pane.
    MD:SelectView("settings", "modules")
    for _ = 1, 8 do S.Tick(0.5) end -- 4s while hidden
    local whileHidden = pane.refreshCount

    check("the pane refreshes on show and every two seconds while shown, not while hidden",
        afterShow >= 1 and before2s == afterShow and after2s == afterShow + 1 and whileHidden == after2s,
        string.format("afterShow=%d before2s=%d after2s=%d whileHidden=%d",
            afterShow, before2s, after2s, whileHidden))

    pane = OpenPane()
end

--------------------------------------------------------------------------------
-- 10: no module beyond core is loaded to draw it
--------------------------------------------------------------------------------
check("no module beyond core is loaded to draw it", #S.loadAddOnCalls == 0,
    "#loadAddOnCalls=" .. #S.loadAddOnCalls)

--------------------------------------------------------------------------------
-- 12 (T10b): each non-empty section has a title row before its first family,
-- and an empty one has none
--------------------------------------------------------------------------------
do
    pane = OpenPane()
    local rows = pane.lastRows or {}
    local sectionIdx, familyIdx, otherIdx = {}, {}, nil
    for i, r in ipairs(rows) do
        if r.kind == "section" then sectionIdx[r.text] = sectionIdx[r.text] or i end
        if r.kind == "family" and not familyIdx[1] then familyIdx[1] = { i, r.family.name } end
        if r.kind == "family" and r.family.name == "Wrath" and not familyIdx[2] then familyIdx[2] = { i, r.family.name } end
        if r.kind == "family" and r.family.name == "Bearform" and not otherIdx then otherIdx = i end -- T39
    end

    -- this fixture book has no Damage-kind family with a "damage" kind row
    -- that isn't Wrath, so "Heals" precedes the first heal family and
    -- "Damage" precedes Wrath; both are non-empty here, and "Other" precedes
    -- the first "other" line (Bearform).
    local heals = sectionIdx["Heals"]
    local damage = sectionIdx["Damage"]
    local other = sectionIdx["Other"]
    local ok12 = heals ~= nil and damage ~= nil and other ~= nil and otherIdx ~= nil -- T39: nil-safe
        and heals < familyIdx[1][1]
        and damage < familyIdx[2][1]
        and other < otherIdx

    -- an empty section has none: strip Wrath's kind so the book has no
    -- damage-kind family left, refresh, and check "Damage" is absent.
    local book = MD.Book:Get()
    local wrath = book.families["Wrath"]
    local savedKind = wrath.kind
    wrath.kind = nil
    local pane2 = OpenPane()
    local hasDamageSection = false
    for _, r in ipairs(pane2.lastRows or {}) do
        if r.kind == "section" and r.text == "Damage" then hasDamageSection = true end
    end
    wrath.kind = savedKind
    OpenPane() -- restore the real book's rows for anything after this

    check("each non-empty section has a title row before its first family, and an empty one has none",
        ok12 and not hasDamageSection,
        string.format("heals=%s damage=%s other=%s firstFamily=%d wrath=%d firstOther=%s emptyDamageAbsent=%s",
            tostring(heals), tostring(damage), tostring(other), familyIdx[1][1], familyIdx[2][1], tostring(otherIdx),
            tostring(not hasDamageSection)))
end

--------------------------------------------------------------------------------
-- 13 (T10c): family, section, note and Other rows are one line across the
-- table, never inside the Rank column (T39: Other's families are family rows)
--------------------------------------------------------------------------------
do
    pane = OpenPane()
    local rows = pane.lastRows or {}
    local bad
    local checked = 0
    local SPELL_COL_KEYS = { "rank", "level", "mana", "value", "permana", "persec", "cast", "toOOM", "tag" } -- T39

    for _, r in ipairs(rows) do
        local row = RowFor(rows, r)
        if not row then
            bad = bad or ("no row frame for kind=" .. tostring(r.kind))
        else
            if r.kind == "section" or r.kind == "family" or r.kind == "note" then
                checked = checked + 1
                local wideText = CellText(row, "wide")
                local rankText = CellText(row, "rank")
                local wideWrap = row.cells.wide and row.cells.wide:GetWordWrap()
                if not bad and (wideText == nil or wideText == "") then
                    bad = "kind=" .. r.kind .. " wide cell empty"
                end
                if not bad and rankText ~= "" then
                    bad = "kind=" .. r.kind .. " rank cell not empty: " .. tostring(rankText)
                end
                if not bad and wideWrap ~= false then
                    bad = "kind=" .. r.kind .. " wide.wordWrap=" .. tostring(wideWrap)
                end
            end
            for _, key in ipairs(SPELL_COL_KEYS) do
                local fs = row.cells[key]
                if fs and fs.GetWordWrap and fs:GetWordWrap() ~= false and not bad then
                    bad = "kind=" .. tostring(r.kind) .. " col=" .. key .. " wordWrap not false"
                end
            end
        end
    end

    check("family, section, note and Other rows are one line across the table, never inside the Rank column",
        bad == nil and checked > 0, bad or ("checked=" .. checked))
end

--------------------------------------------------------------------------------
-- 14 (T10c): passives and spells with no mana cost are left off the pane,
-- counted, and kept in the export
--------------------------------------------------------------------------------
do
    pane = OpenPane()
    local rows = pane.lastRows or {}
    local sawOakskin, sawSwing = false, false
    local noteText
    for _, r in ipairs(rows) do
        local hay
        if r.kind == "family" then hay = r.family.name
        elseif r.kind == "rank" then hay = r.family.name -- T39
        elseif r.kind == "note" then
            hay = r.text
            if r.text:find("passives and spells with no mana cost", 1, true) then noteText = r.text end
        elseif r.kind == "section" then hay = r.text end
        if hay then
            if hay:find("Oakskin", 1, true) then sawOakskin = true end
            if hay:find("Swing", 1, true) then sawSwing = true end
        end
    end

    local exportCapture
    do
        local origShow = MD.ShowCopyPopup
        MD.ShowCopyPopup = function(self, title, text) exportCapture = text end
        pane.exportBtn:GetScript("OnClick")(pane.exportBtn)
        MD.ShowCopyPopup = origShow
    end
    local exportHasBoth = exportCapture ~= nil
        and exportCapture:find("name: Oakskin", 1, true) ~= nil
        and exportCapture:find("name: Swing", 1, true) ~= nil

    check("passives and spells with no mana cost are left off the pane, counted, and kept in the export",
        not sawOakskin and not sawSwing
        and noteText == "2 passives and spells with no mana cost not listed - Export has them"
        and exportHasBoth,
        string.format("sawOakskin=%s sawSwing=%s note=%q exportHasBoth=%s",
            tostring(sawOakskin), tostring(sawSwing), tostring(noteText), tostring(exportHasBoth)))
end

--------------------------------------------------------------------------------
-- 15 (T10c): hovering a family or an Other row shows its full name (T39: the
-- kit tooltip beside the row; Other's families are family headers too)
--------------------------------------------------------------------------------
do
    pane = OpenPane()
    local rows = pane.lastRows or {}
    local familyRow = FamilyRow(rows, "Healing Touch")
    local otherRow
    for _, r in ipairs(rows) do
        if r.kind == "family" and r.family and r.family.name == "Bearform" then otherRow = r end -- T39
    end

    local function LinesContain(text)
        for _, tt in ipairs({ GameTooltip, UI.tooltip }) do -- T39: the kit tooltip
            for _, line in ipairs(tt.lines or {}) do
                if type(line[1]) == "string" and line[1]:find(text, 1, true) then return true end
            end
        end
        return false
    end

    local famRowFrame = RowFor(rows, familyRow)
    local famEnter = famRowFrame and famRowFrame:GetScript("OnEnter")
    GameTooltip.lines = nil
    if UI.tooltip then UI.tooltip.lines = nil end -- T39
    if famEnter then famEnter(famRowFrame) end
    local famOk = LinesContain("Healing Touch")
    local famLeave = famRowFrame and famRowFrame:GetScript("OnLeave")
    if famLeave then famLeave(famRowFrame) end

    local otherRowFrame = RowFor(rows, otherRow)
    local otherEnter = otherRowFrame and otherRowFrame:GetScript("OnEnter")
    GameTooltip.lines = nil
    if UI.tooltip then UI.tooltip.lines = nil end -- T39
    if otherEnter then otherEnter(otherRowFrame) end
    local otherOk = LinesContain("Bearform")
    local otherLeave = otherRowFrame and otherRowFrame:GetScript("OnLeave")
    if otherLeave then otherLeave(otherRowFrame) end

    check("hovering a family or an Other row shows its full name",
        familyRow ~= nil and otherRow ~= nil and famOk and otherOk,
        string.format("familyRow=%s otherRow=%s famOk=%s otherOk=%s",
            tostring(familyRow ~= nil), tostring(otherRow ~= nil), tostring(famOk), tostring(otherOk)))
end

--------------------------------------------------------------------------------
-- 17 (review R13): a Rage cost is named in the Mana column and the export --
-- "10 Rage", the client's own cost-line words -- never read as mana. Added
-- last so item 12's "Wrath is the only damage family" fixture holds. Text
-- and cost line: talentsforever's beta client 1.60.1.70009 (Rend, Rank 1).
--------------------------------------------------------------------------------
do
    S.AddSpell(92300, "Rend", "Rank 1",
        function() return "Wounds the target causing them to bleed for 15 damage over 9 sec." end,
        { cast = 0, level = 4, costLine = "10 Rage",
          costList = { { type = 1, name = "RAGE", cost = 10, minCost = 10, costPercent = 0, costPerSec = 0,
                         requiredAuraID = 0, hasRequiredAura = false } } })
    Book:MarkDirty()
    pane = OpenPane()
    local r = EntryRow(pane.lastRows, 92300)
    local row = RowFor(pane.lastRows, r)
    local manaCell, perManaCell, oomCell = CellText(row, "mana"), CellText(row, "permana"), CellText(row, "toOOM")

    local exportCapture
    do
        local origShow = MD.ShowCopyPopup
        MD.ShowCopyPopup = function(self, title, text) exportCapture = text end
        pane.exportBtn:GetScript("OnClick")(pane.exportBtn)
        MD.ShowCopyPopup = origShow
    end
    local block
    local at = exportCapture and exportCapture:find("spell 92300\n", 1, true)
    if at then
        local nextAt = exportCapture:find("\nspell ", at + 1, true)
        block = exportCapture:sub(at, nextAt or #exportCapture) .. "\n"
    end
    local exportGood = block ~= nil and block:find("\n  cost: 10 Rage\n", 1, true) ~= nil

    check("a Rage cost is named in the Mana column and the export, never read as mana",
        manaCell == "10 Rage" and perManaCell == "-" and oomCell == "-" and exportGood,
        string.format("mana=%s permana=%s toOOM=%s export=%s", tostring(manaCell), tostring(perManaCell),
            tostring(oomCell), tostring(block and block:match("cost: [^\n]*"))))
end

--------------------------------------------------------------------------------
-- T38 (docs/SPEC-forever-ui.md 3.5, docs/tasks/T38-one-spell-view.md): one
-- spell's view -- the header, the decision strip, the RANKS table (T30's
-- options: the per-mana bar, the gap and not-learned rows, the tags, the row
-- states), the rank card, the row hover through MD.API.SetTooltipSpell with
-- its fallback, the refresh split and the pitches. Each block under pcall
-- (T36's T36()), so the old view fails item by item.
--
-- Fixtures: "Nourish", a direct heal listed at ranks 1, 2 and 4 (rank 3 a
-- gap, rank 4 not learned), with the spec's own numbers (3.5, 10.6: R1 40-55
-- for 25 mana in 1.5 s, R2 90-115 for 55 in 2.0 s); Rejuvenation (the stub's
-- R1 dominated by R2) as a HoT; "Starfall" (the probe's Moonfire R1 text) as a
-- hybrid; Bearform (above) as a family with no value.
--------------------------------------------------------------------------------
S.AddSpell(93801, "Nourish", "Rank 1",
    function() return "Heals a friendly target for 40 to 55." end,
    { cast = 1500, cost = 25, level = 1 })
S.AddSpell(93802, "Nourish", "Rank 2",
    function() return "Heals a friendly target for 90 to 115." end,
    { cast = 2000, cost = 55, level = 8 })
S.AddSpell(93804, "Nourish", "Rank 4",
    function() return "Heals a friendly target for 150 to 170." end,
    { cast = 2500, cost = 100, level = 20, known = false })
S.AddSpell(93811, "Starfall", "Rank 1",
    function() return "Burns the enemy for 9 to 12 Arcane damage and then an additional 12 Arcane damage over 9 sec." end,
    { cast = 0, cost = 25, level = 4 })
Book:MarkDirty()

local F = function() return SP.family end
local function OpenView(key)
    if not MD.Tabs:Has(key) then MD.Tabs:Add(key, nil); SP:ListChanged() end
    MD:SelectView("spells", "fam:" .. key)
    return SP.family
end
local function ViewRows()
    local out = {}
    for _, r in ipairs(F().lastRows or {}) do out[#out + 1] = r end
    return out
end
local function ViewRow(rank)
    for _, r in ipairs(ViewRows()) do
        if r.rank == rank then return r, RowFor(nil, r) end
    end
    return nil
end
local function Pairs()
    local out = {}
    for _, p in ipairs(F().card and F().card.shown or {}) do
        out[#out + 1] = StripColor(p.label:GetText() or "") .. "=" .. StripColor(p.value:GetText() or "")
    end
    return table.concat(out, "; ")
end
local function PairValue(label)
    for _, p in ipairs(F().card and F().card.shown or {}) do
        if StripColor(p.label:GetText() or "") == label then return StripColor(p.value:GetText() or "") end
    end
    return nil
end
local function Fill(rowFrame)
    if not (rowFrame and rowFrame.fill and rowFrame.fill:IsShown()) then return nil end
    return rowFrame.fill.color and rowFrame.fill.color[4]
end
local function BlockCount(tt)
    local n = 0
    for _, line in ipairs(tt.lines or {}) do if line[1] == "SpellTuner" then n = n + 1 end end
    return n
end
local function Hover(rowFrame)
    GameTooltip.lines = nil
    if UI.tooltip then UI.tooltip.lines = nil end
    rowFrame:GetScript("OnEnter")(rowFrame)
end
-- T78 (P34): the lines a hover put in GameTooltip, "left|right" each, colour
-- codes kept off; the tag cell's hover (UI/Dashboard_Rows.lua's
-- col.cellTooltip hit frame) and a header label's (col.tooltip).
local function TipText(tt)
    local out = {}
    for _, l in ipairs(tt and tt.lines or {}) do
        out[#out + 1] = StripColor(tostring(l[1])) .. ((l[2] ~= nil) and ("|" .. StripColor(tostring(l[2]))) or "")
    end
    return table.concat(out, " / ")
end
local function TagHover(rowFrame)
    GameTooltip.lines = nil
    if UI.tooltip then UI.tooltip.lines = nil end
    local hit = rowFrame and rowFrame.cellHits and rowFrame.cellHits.tag
    if not (hit and hit:IsShown()) then return nil end
    hit:GetScript("OnEnter")(hit)
    return hit
end
local function HeadHover(header, key)
    GameTooltip.lines = nil
    local hit = header and header.colHits and header.colHits[key]
    if not (hit and hit:IsShown()) then return "" end
    hit:GetScript("OnEnter")(hit)
    local text = TipText(GameTooltip)
    hit:GetScript("OnLeave")(hit)
    return text
end
local function Unhover(rowFrame)
    rowFrame:GetScript("OnLeave")(rowFrame)
end
local function FullPoolCasts(e)
    local pool = MD.Clock:Pool()
    return Book:CastsFor(e, { max = pool.max, regenCasting = pool.regenCasting })
end
local PAD_SCREEN = 4000
-- The card's To OOM and Now: this stub's casting regen (28.33 a second)
-- keeps up with every cheap rank, so both read "never" there; BigSpell (300
-- mana, above) is the finite case (T38-7).
local function OOMWord(n)
    if n == math.huge then return "never - regen keeps up" end
    return Num(n) .. " casts from full"
end
local function NowWord(n, pool)
    if n == math.huge then return "never - regen keeps up" end
    return "~" .. Num(n) .. " from ~" .. Num(pool.mana) .. " mana"
end

-- T38-1: the header and the decision strip
T36("T38 the header and the decision strip: which rank, and one factual line", function()
    local f = OpenView("Nourish")
    local pool = MD.Clock:Pool()
    local rawMana = f.header.mana:GetText() or ""
    local manaText = StripColor(rawMana)
    local wantMana = "~" .. Num(pool.mana) .. " / " .. Num(pool.max) .. " mana"
    local _, tildes = manaText:gsub("~", "")
    local good = StripColor(f.header.name:GetText() or "") == "Nourish"
        and f.header.sub:GetText() == "Direct heal - Rank 2 of 2 known - 2.0 s cast"
        and manaText == wantMana and tildes == 1
        and rawMana:find(UI.TEXT.mana.hex .. "~", 1, true) == 1 -- only the modelled pool in the mana colour
        and f.strip:IsShown() and f.strip.chipLabel:GetText() == "SUGGESTED"
        and f.strip.chipRank:GetText() == "Rank 1"
        and f.strip.compare:GetText() == "vs Rank 2 (your highest): 2% more healing per mana, 46% of the heal, a 25% shorter cast."
    return good, string.format("sub=%q mana=%q chip=%q cmp=%q", tostring(f.header.sub:GetText()), manaText,
        tostring(f.strip.chipRank and f.strip.chipRank:GetText()), tostring(f.strip.compare and f.strip.compare:GetText()))
end)

-- T38-2: the RANKS table -- a row per rank from 1 to the highest listed, the
-- gap spanning, the not-learned row, the bar, the tags, the suggested row
T36("T38 the ranks table: every rank to the highest listed, the gap, the bar and the tags", function()
    local f = F()
    local r1, row1 = ViewRow(1)
    local r2, row2 = ViewRow(2)
    local r3, row3 = ViewRow(3)
    local r4, row4 = ViewRow(4)
    local e1, e2 = Book:Get().spells[93801], Book:Get().spells[93802]
    local order = {}
    for _, r in ipairs(ViewRows()) do order[#order + 1] = r.kind .. tostring(r.rank) end
    local function Cells(row)
        local t = {}
        for _, k in ipairs({ "rank", "level", "mana", "value", "permana", "persec", "cast", "toOOM", "tag" }) do
            t[#t + 1] = CellText(row, k) or "?"
        end
        return table.concat(t, ",")
    end
    local want1 = table.concat({ "R1", "1", "25", "48", "1.90", "31.7", "1.5s", Num(FullPoolCasts(e1)), "best" }, ",")
    local want2 = table.concat({ "R2", "8", "55", "103", Num(e2.perMana, 2), Num(e2.perSec, 1), "2.0s",
        Num(FullPoolCasts(e2)), "max" }, ",")
    local header
    for _, fr in ipairs(S.allFrames) do
        if fr.isHeader and fr.cells and fr.cells.value and fr:IsVisible() then header = fr end
    end
    local gapText = CellText(row3, "wide")
    -- T78 (P34, review U1 / U7 / U10; mockup M5): the selected rank is a white
    -- 2-px bar, the fill the suggested row's alone; the gap's explanation and
    -- the tags readable (muted, label); headers 12 px in label, each with a
    -- sentence on hover; a tag explains itself, and a row with no tag keeps
    -- the row's own hover over the tag cell.
    local L, M, D = UI.TEXT.label.hex, UI.TEXT.muted.hex, UI.TEXT.disabled.hex
    local headTips = HeadHover(header, "toOOM") .. " // " .. HeadHover(header, "persec")
        .. " // " .. HeadHover(header, "value")
    local hit1 = TagHover(row1)
    local bestTip = TipText(GameTooltip)
    if hit1 then hit1:GetScript("OnLeave")(hit1) end
    -- a row with nothing in its tag cell has no hit there: the row's hover
    -- (the gap's reason) covers the whole row
    local hit3 = row3.cellHits and row3.cellHits.tag
    local gapTip = { (hit3 and hit3:IsShown()) and "a tag hit on the gap row" or "no tag hit" }
    local t78 = row1.pick and row1.pick:IsShown() and row1.pick.w == 2 and row1.pick.color
        and row1.pick.color[1] == 1 and row1.pick.color[2] == 1 and row1.pick.color[3] == 1
        and not row2.pick:IsShown()
        and (row3.cells.rank:GetText() or ""):find(D, 1, true) == 1
        and (row3.cells.wide:GetText() or ""):find(M, 1, true) == 1
        and (row4.cells.tag:GetText() or ""):find(L, 1, true) == 1
        and (row2.cells.tag:GetText() or ""):find(L, 1, true) == 1
        and (header.cells.persec:GetText() or ""):find(L, 1, true) == 1
        and CellText(header, "persec") == "Per sec" and CellText(header, "toOOM") == "Casts"
        and headTips == "Casts / Casts in a row from a full pool. // Per sec / Healing per second of casting."
            .. " // Heal / The average heal of one cast, from the spell's own text."
        and bestTip == "Best / The rank SpellTuner suggests."
        and gapTip[1] == "no tag hit"
    local good = t78 and table.concat(order, ",") == "rank1,rank2,gap3,rank4"
        and Cells(row1) == want1 and Cells(row2) == want2
        and CellText(row3, "rank") == "R3"
        and gapText == 'not in your spellbook - untrained, or hidden by "show all ranks"'
        and CellText(row4, "tag") == "learn at 20"
        and (row4.cells.value:GetText() or ""):find(UI.TEXT.disabled.hex, 1, true) == 1
        and header ~= nil and CellText(header, "value") == "Heal" and CellText(header, "permana") == "Per mana"
        and row1.bars.permana.fill:IsShown() and row1.bars.permana.fill.w == 72
        and math.abs(row2.bars.permana.fill.w - 72 * e2.perMana / e1.perMana) < 1e-6
        and not row3.bars.permana.track:IsShown()
        and row1.mark:IsShown() and not row2.mark:IsShown()
        and f.selectedId == 93801 and Fill(row1) == 0.10 and Fill(row2) == 0.03 -- T78: suggested's fill; zebra
    return good, string.format("t78=%s order=%s r1=%s r2=%s gap=%q r4tag=%s fill1=%s heads=%q best=%q gapTip=%q",
        tostring(t78), table.concat(order, ","), Cells(row1), Cells(row2), tostring(gapText),
        tostring(CellText(row4, "tag")), tostring(Fill(row1)), headTips, bestTip, table.concat(gapTip, " / "))
end)

-- T38-3: the card follows the selected rank; a click selects another
T36("T38 the rank card: the suggested rank by default, a click selects another", function()
    local f = F()
    local before = f.card.title:GetText() .. " / " .. f.card.learned:GetText()
    local firstPairs = Pairs()
    local _, row2 = ViewRow(2)
    row2:GetScript("OnMouseUp")(row2, "LeftButton")
    local e2 = Book:Get().spells[93802]
    local pool = MD.Clock:Pool()
    local _, row1 = ViewRow(1)
    local good = before == "RANK 1 / learned at 1"
        and firstPairs:find("Heals=40 - 55 (avg 48); Crit=60 - 83 (x1.5 assumed)", 1, true) == 1
        and f.selectedId == 93802 and f.card.title:GetText() == "RANK 2" and f.card.learned:GetText() == "learned at 8"
        and f.card.quote:GetText() == '"Heals a friendly target for 90 to 115."'
        and PairValue("Heals") == "90 - 115 (avg 103)" and PairValue("Crit") == "135 - 173 (x1.5 assumed)"
        and PairValue("Cost") == "55 mana" and PairValue("Cast") == "2.0 s"
        and PairValue("Per mana") == Num(e2.perMana, 2)
        and PairValue("Per sec") == Num(e2.perSec, 1) .. " over a 2.0 s cast" -- T78
        and PairValue("Casts") == OOMWord(FullPoolCasts(e2)) -- T78
        and PairValue("Now") == NowWord(Book:CastsFor(e2, pool), pool)
        -- T78 (U1): the selection moved as a white bar; no `selected` fill on
        -- either row -- the suggested row keeps its fill and its accent bar
        and Fill(row2) == 0.03 and row2.pick:IsShown() and not row1.pick:IsShown()
        and Fill(row1) == 0.10 and row1.mark:IsShown()
        and f.footer:GetText() == "Values come from the spell's own text. ~ = modelled."
    return good, "before=" .. before .. " | " .. Pairs()
end)

-- T38-4: a row's hover is the game's own tooltip for that rank, through the
-- adapter, with the block under it once, beside the row
T36("T38 row hover: the game's tooltip through MD.API.SetTooltipSpell, the block once, beside the row", function()
    UIParent:SetWidth(PAD_SCREEN)
    local _, row1 = ViewRow(1)
    S.setSpellByIdCalls = {}
    Hover(row1)
    local calls = table.concat(S.setSpellByIdCalls, ",")
    local tl = GameTooltip.points and GameTooltip.points.TOPLEFT
    local good = calls == "93801" and GameTooltip.lines ~= nil and GameTooltip.lines[1][1] == "Nourish"
        and BlockCount(GameTooltip) == 1 and GameTooltip._spellTipId == 93801
        and tl ~= nil and tl.rel == row1 and tl.rp == "TOPRIGHT" and tl.x == 6
        and row1.highlight:IsShown()
    Unhover(row1)
    return good and not row1.highlight:IsShown(), string.format("calls=%s blocks=%d anchor=%s/%s",
        calls, BlockCount(GameTooltip), tostring(tl and tl.rp), tostring(tl and tl.x))
end)

-- T38-5: no post-call -> the row adds the block itself; off the screen's
-- right edge -> the tooltip on the row's left; a gap or a not-learned row ->
-- the kit tooltip with the reason, and no game tooltip
T36("T38 row hover: the block added when no post-call runs, flipped at the edge, a reason for gap rows", function()
    local _, row2 = ViewRow(2)
    S.setSpellByIdNoPostCall = true
    UIParent:SetWidth(560)
    Hover(row2)
    S.setSpellByIdNoPostCall = nil
    local tr = GameTooltip.points and GameTooltip.points.TOPRIGHT
    local fallback = BlockCount(GameTooltip) == 1 and GameTooltip.lines[1][1] == "Nourish"
        and tr ~= nil and tr.rel == row2 and tr.rp == "TOPLEFT" and tr.x == -6
    Unhover(row2)
    UIParent:SetWidth(PAD_SCREEN)

    local _, row3 = ViewRow(3)
    local _, row4 = ViewRow(4)
    S.setSpellByIdCalls = {}
    Hover(row3)
    local gapLines = {}
    for _, l in ipairs(UI.tooltip.lines or {}) do gapLines[#gapLines + 1] = l[1] end
    Unhover(row3)
    Hover(row4)
    local learnLines = {}
    for _, l in ipairs(UI.tooltip.lines or {}) do learnLines[#learnLines + 1] = l[1] end
    Unhover(row4)
    local gapText, learnText = table.concat(gapLines, " / "), table.concat(learnLines, " / ")
    local good = fallback and #S.setSpellByIdCalls == 0
        and gapText == 'Nourish Rank 3 / Not in your spellbook: untrained, or hidden by "show all ranks".'
        and learnText == "Nourish Rank 4 / Not learned yet: learn at level 20."
    return good, string.format("fallback=%s gap=%q learn=%q", tostring(fallback), gapText, learnText)
end)

-- T38-6: a HoT, a hybrid and a family with no value each read as what they are
T36("T38 a HoT, a hybrid and a spell with no value: header, strip, columns and card by shape", function()
    local f = OpenView("Rejuvenation")
    local _, rj1 = ViewRow(1)
    local hot = f.header.sub:GetText() == "Heal over time - Rank 2 of 2 known - 12 s"
        and f.strip:IsShown() and f.strip.chipRank:GetText() == "Rank 2"
        and f.strip.compare:GetText() == "Your highest rank is also the best per mana."
        and CellText(rj1, "tag") == "beaten" -- T78: the author's word
        and (rj1.cells.level:GetText() or ""):find(UI.TEXT.text.hex, 1, true) == 1 -- T78: numbers, not greyed
        and PairValue("Heals") == "56 over 12 s" and PairValue("Crit") == nil
    -- T78 (U10; mockup M5): the beaten tag names the rank that beats it
    local rjE1, rjE2 = Book:Get().spells[774], nil
    for _, e in ipairs(Book:Get().families["Rejuvenation"].ranks) do if e.rank == 2 then rjE2 = e end end
    local rjHit = TagHover(rj1)
    local beatenTip = TipText(GameTooltip)
    if rjHit then rjHit:GetScript("OnLeave")(rjHit) end
    local wantBeaten = "Beaten by Rank 2 / Per mana|" .. Num(rjE2.perMana, 2) .. " vs " .. Num(rjE1.perMana, 2)
        .. " / Per sec|" .. Num(rjE2.perSec, 1) .. " vs " .. Num(rjE1.perSec, 1)
        .. " / Rank 2 is better on both, and you know it."
    hot = hot and beatenTip == wantBeaten and rjE1.dominatedBy == rjE2.id
    local hotSub = f.header.sub:GetText() .. " | " .. beatenTip

    OpenView("Starfall")
    local hybrid = f.header.sub:GetText() == "Damage - hit and over time - Arcane - Rank 1 of 1 known"
        and not f.strip:IsShown()
        and PairValue("Hit") == "9 - 12" and PairValue("Over time") == "12 over 9 s" and PairValue("Total") == "23"
    local hybridSub = f.header.sub:GetText()

    OpenView("Bearform")
    local headers = {}
    for _, fr in ipairs(S.allFrames) do
        if fr.isHeader and fr.cells and fr:IsVisible() then
            for _, c in ipairs(f.activeTable.cols) do headers[#headers + 1] = CellText(fr, c.key) end
        end
    end
    local none = f.header.sub:GetText() == "Utility - 30 mana" and not f.strip:IsShown()
        and f.activeTable == f.otherTable and not f.rankTable.frame:IsShown()
        and table.concat(headers, ",") == "Rank,Lvl,Mana,Cast,"
        and PairValue("Cost") == "30 mana" and PairValue("Per mana") == nil
    return hot and hybrid and none, string.format("hot=%s(%q) hybrid=%s(%q) none=%s(%q, %s) | %s",
        tostring(hot), tostring(hotSub), tostring(hybrid), tostring(hybridSub), tostring(none),
        tostring(f.header.sub:GetText()), table.concat(headers, ","), Pairs())
end)

-- T38-7: the 2-s tick updates the header's mana, Now and To OOM in place; a
-- book change re-renders; at font offset +2 every pitch grows
T36("T38 the refresh split: mana, Now and To OOM in place; a book change re-renders; pitches at +2", function()
    -- BigSpell: one rank, 300 mana, so both counts are finite here
    local f = OpenView("BigSpell")
    local renders, lives = f.renderCount, f.liveCount
    local _, row1 = ViewRow(1)
    local e1 = Book:Get().spells[92050]
    local fullBefore = PairValue("Casts") -- T78
    MD.Clock.model:Anchor(GetTime(), 100, "test: drained for T38")
    MD.Clock.model.lastSpend = GetTime() -- as after a cast: the clock does not assume it refilled
    for _ = 1, 4 do S.Tick(0.5) end
    local pool = MD.Clock:Pool()
    local _, row1b = ViewRow(1)
    local inPlace = f.renderCount == renders and f.liveCount == lives + 1 and row1b == row1
        and StripColor(f.header.mana:GetText()) == "~" .. Num(pool.mana) .. " / " .. Num(pool.max) .. " mana"
        and PairValue("Now") == "~0 from ~" .. Num(pool.mana) .. " mana"
        and fullBefore == OOMWord(FullPoolCasts(e1)) and fullBefore:find("casts from full", 1, true) ~= nil
        and CellText(row1, "toOOM") == Num(FullPoolCasts(e1))
    local liveDetail = string.format("renders %s->%s lives %s->%s same=%s mana=%q now=%q full=%q cell=%q",
        tostring(renders), tostring(f.renderCount), tostring(lives), tostring(f.liveCount), tostring(row1b == row1),
        StripColor(f.header.mana:GetText()), tostring(PairValue("Now")), tostring(fullBefore), tostring(CellText(row1, "toOOM")))
    MD.Clock.model:Anchor(GetTime(), MD.Clock.model.max, "test: restored")
    OpenView("Nourish")
    renders = f.renderCount

    Book:MarkDirty()
    for _ = 1, 4 do S.Tick(0.5) end
    local rerendered = f.renderCount == renders + 1

    UI.ApplyFonts(2)
    local _, a = ViewRow(1)
    local _, b = ViewRow(2)
    local rowGap = a.points.TOPLEFT.y - b.points.TOPLEFT.y
    local pitches = rowGap == 22 and a:GetHeight() == 22 and f.header:GetHeight() == 50
        and f.strip:GetHeight() == 46 and f.card.pitch == 19
    local pitchDetail = string.format("rowGap=%s strip=%s card=%s", tostring(rowGap), tostring(f.strip:GetHeight()),
        tostring(f.card.pitch))
    UI.ApplyFonts(0)
    local _, a0 = ViewRow(1)
    local _, b0 = ViewRow(2)
    local back = a0.points.TOPLEFT.y - b0.points.TOPLEFT.y == 20 and f.card.pitch == 17
    return inPlace and rerendered and pitches and back, string.format(
        "inPlace=%s (%s) rerendered=%s at +2 %s back=%s", tostring(inPlace), liveDetail, tostring(rerendered),
        pitchDetail, tostring(back))
end)

-- T38-8: no Blizzard gold anywhere in the view, nor in its row tooltips
T36("T38 no ffcc00 anywhere in the view or its tooltips", function()
    local f = OpenView("Nourish")
    local function Under(fr)
        local p, guard = fr, 0
        while p and guard < 60 do
            if p == f then return true end
            p, guard = p.parentFrame, guard + 1
        end
        return false
    end
    local bad
    local function Scan(text, where)
        if type(text) == "string" and not bad then
            local low = text:lower()
            if low:find("ffcc00", 1, true) or low:find("ffd100", 1, true) then bad = where .. ": " .. text end
        end
    end
    local seen = 0
    for _, fr in ipairs(S.allFrames) do
        if Under(fr) then
            seen = seen + 1
            Scan(fr.GetText and fr:GetText(), "painted")
            local c = fr.textColor
            if c and not bad and math.abs(c[1] - 1) < 0.01 and math.abs(c[2] - 0.82) < 0.01 and c[3] < 0.01 then
                bad = "gold text colour on '" .. tostring(fr:GetText()) .. "'"
            end
        end
    end
    for _, rank in ipairs({ 1, 2, 3, 4 }) do
        local _, row = ViewRow(rank)
        Hover(row)
        for _, tt in ipairs({ GameTooltip, UI.tooltip }) do
            for _, l in ipairs(tt.lines or {}) do Scan(l[1], "tooltip"); Scan(l[2], "tooltip") end
        end
        Unhover(row)
    end
    return bad == nil and seen > 40, bad or ("frames=" .. seen)
end)

--------------------------------------------------------------------------------
-- T39 (docs/SPEC-forever-ui.md 3.6, docs/tasks/T39-overview.md): Overview.
-- My spells -- one row per listed family, its suggested rank against its
-- highest; Whole book -- today's table under 3.5's look: sections, a header
-- row per family with + or listed, one row per rank in the RANKS columns,
-- gaps and ranks not learned included; Export (format unchanged, item 8).
-- After the T38 fixtures, so Nourish's gap and its rank not learned are in
-- the book. Each block under T36(), so the old pane fails item by item.
--------------------------------------------------------------------------------
local function BookRows()
    local p = OpenPane()
    return p, (p and p.lastRows) or {}
end
local function ListedInBook(fam)
    if fam.kind then return true end
    local rep = fam.maxKnown or fam.ranks[1]
    return rep ~= nil and not rep.passive and rep.cost ~= nil
        and (rep.cost.amount ~= nil or rep.cost.percent ~= nil)
end
local function HeaderFor(rows, name)
    for _, r in ipairs(rows) do
        if r.kind == "family" and r.family.name == name then return r, RowFor(nil, r) end
    end
    return nil
end

-- T39-1: a row per known rank of every family, each under its own header
T36("T39 Whole book has a row per known rank of every family, under its header", function()
    local p, rows = BookRows()
    local book = Book:Get()
    local seen, current, bad = {}, nil, nil
    local headers = 0
    for _, r in ipairs(rows) do
        if r.kind == "family" then current = r.family; headers = headers + 1
        elseif r.kind == "rank" then
            if r.family ~= current and not bad then bad = "rank " .. tostring(r.entry.id) .. " not under its family" end
            seen[r.entry.id] = (seen[r.entry.id] or 0) + 1
            local row = RowFor(nil, r)
            local want = r.entry.rank and ("R" .. r.entry.rank) or "-"
            if not bad and CellText(row, "rank") ~= want then bad = "rank cell " .. tostring(CellText(row, "rank")) end
        end
    end
    local families, ranks = 0, 0
    for _, name in ipairs(book.order) do
        local fam = book.families[name]
        if ListedInBook(fam) then
            families = families + 1
            for _, e in ipairs(fam.ranks) do
                ranks = ranks + 1
                if seen[e.id] ~= 1 and not bad then
                    bad = string.format("%s id %s rows=%s", name, tostring(e.id), tostring(seen[e.id]))
                end
            end
        end
    end
    local r4 = EntryRow(rows, 93804)
    local learn = CellText(RowFor(nil, r4), "tag")
    return bad == nil and headers == families and families > 5 and learn == "learn at 20"
        and p.bookTable ~= nil and p.bookTable.frame:IsShown(),
        string.format("bad=%s headers=%d families=%d ranks=%d r4tag=%s", tostring(bad), headers, families, ranks,
            tostring(learn))
end)

-- T39-2: a gap is one disabled row across the table, with its reason on hover
T36("T39 Whole book: a gap is one disabled row across the table", function()
    local _, rows = BookRows()
    local order, gapRow, gapR = {}, nil, nil
    local inNourish = false
    for _, r in ipairs(rows) do
        if r.kind == "family" then inNourish = (r.family.name == "Nourish")
        elseif inNourish and (r.kind == "rank" or r.kind == "gap") then
            order[#order + 1] = r.kind .. tostring(r.rank)
            if r.kind == "gap" then gapR, gapRow = r, RowFor(nil, r) end
        end
    end
    local raw = gapRow and gapRow.cells.rank:GetText() or ""
    local wide = gapRow and CellText(gapRow, "wide")
    if gapRow then Hover(gapRow) end
    local lines = {}
    for _, l in ipairs(UI.tooltip.lines or {}) do lines[#lines + 1] = l[1] end
    if gapRow then Unhover(gapRow) end
    local tip = table.concat(lines, " / ")
    local good = table.concat(order, ",") == "rank1,rank2,gap3,rank4"
        and CellText(gapRow, "rank") == "R3" and raw:find(UI.TEXT.disabled.hex, 1, true) == 1
        and wide == 'not in your spellbook - untrained, or hidden by "show all ranks"'
        and CellText(gapRow, "level") == "" and CellText(gapRow, "tag") == ""
        and not gapRow.bars.permana.track:IsShown()
        and tip == 'Nourish Rank 3 / Not in your spellbook: untrained, or hidden by "show all ranks".'
    return good, string.format("order=%s rank=%q wide=%q tip=%q", table.concat(order, ","), raw, tostring(wide), tip)
end)

-- T39-3: + adds a family to the list (the rail follows, Overview stays); a
-- listed family reads a grey "listed" and has no +
T36("T39 Whole book: + adds a family to the list; a listed one reads listed", function()
    MD.Tabs:Remove("Rend") -- not listed (a damage family the reconcile never adds)
    SP:ListChanged()
    local _, rows = BookRows()
    local _, rend = HeaderFor(rows, "Rend")
    local plusBefore = rend and rend.plusBtn and rend.plusBtn:IsShown()
    local listedBefore = rend and rend.listed and rend.listed:IsShown()
    Click(rend and rend.plusBtn)
    local added = MD.Tabs:Has("Rend") and RailRow("fam:Rend") ~= nil
    local g, v = Nav():Selected()
    local _, rows2 = BookRows()
    local _, rend2 = HeaderFor(rows2, "Rend")
    local after = rend2 and rend2.listed:IsShown() and not rend2.plusBtn:IsShown()
        and rend2.listed:GetText() == "listed"
    local _, ht = HeaderFor(rows2, "Healing Touch")
    local htGood = ht and ht.listed:IsShown() and not ht.plusBtn:IsShown()
        and ht.listed.textColor ~= nil and math.abs(ht.listed.textColor[1] - UI.TEXT.muted[1]) < 1e-6
        and ht.famIcon:IsShown()
    SP:Remove("Rend")
    return plusBefore == true and listedBefore == false and added and g == "spells" and v == "overview"
        and after == true and htGood == true,
        string.format("plus=%s listed=%s added=%s view=%s/%s after=%s ht=%s", tostring(plusBefore),
            tostring(listedBefore), tostring(added), tostring(g), tostring(v), tostring(after), tostring(htGood))
end)

-- T39-4: My spells -- one row per listed family in the list's order, its
-- suggested rank against its highest; a click opens that family's view
T36("T39 My spells: a row per listed family, suggested against highest; a click opens it", function()
    MD:SelectView("spells", "overview")
    SP:SetOverviewMode("mine")
    local p = FindPane()
    local rows = p.lastRows or {}
    local keys = {}
    for _, r in ipairs(rows) do keys[#keys + 1] = r.key end
    local want = {}
    for _, k in ipairs(MD.Tabs:Get()) do
        if type(MD.Tabs:Resolve(k, Book:Get())) == "table" then want[#want + 1] = k end
    end
    local nourish
    for _, r in ipairs(rows) do if r.key == "Nourish" then nourish = RowFor(nil, r) end end
    local e1, e2 = Book:Get().spells[93801], Book:Get().spells[93802]
    local function Cells(row)
        local t = {}
        for _, k in ipairs({ "spell", "suggested", "value", "permana", "toOOM", "highest", "hvalue", "hpermana" }) do
            t[#t + 1] = CellText(row, k) or "?"
        end
        return table.concat(t, ",")
    end
    local wantN = table.concat({ "Nourish", "R1", "48", "1.90", CastsWord(FullCasts(e1)), "R2", "103",
        Num(e2.perMana, 2) }, ",")
    local header
    for _, fr in ipairs(S.allFrames) do
        if fr.isHeader and fr.cells and fr.cells.hpermana and fr:IsVisible() then header = fr end
    end
    local labels = header and Cells(header) or ""
    local bookHidden = not p.bookTable.frame:IsShown()
    local rj
    for _, r in ipairs(rows) do if r.key == "Rejuvenation" then rj = RowFor(nil, r) end end
    rj:GetScript("OnMouseUp")(rj, "LeftButton")
    local _, v = Nav():Selected()
    local good = table.concat(keys, ",") == table.concat(want, ",") and #keys > 3
        and Cells(nourish) == wantN
        and labels == "Spell,Suggested,Value,Per mana,Casts,Highest,Value,Per mana" -- T78
        and bookHidden and v == "fam:Rejuvenation"
    return good, string.format("keys=%s nourish=%s labels=%s view=%s", table.concat(keys, ","),
        nourish and Cells(nourish) or "nil", labels, tostring(v))
end)

-- F3 (docs/tasks/F3-whole-book-empty.md): the author on 0.16.6, "Whole book
-- is empty when opened, fixed once start scrolling". The client draws a
-- scroll child through the rect the scroll frame last took from it -- at the
-- layout pass when the pane appeared, and again on UpdateScrollChildRect or
-- SetVerticalScroll (a wheel notch is the latter). The stub has no scroll
-- frame, so this item models that half on the Overview's own frame: a row is
-- drawn when it is in the frame's window AND inside the rect last taken.
-- Opening Whole book from My spells, with no wheel event, must draw every row
-- in the window; so must every switch back and forth, and a Whole book left
-- scrolled down comes back at its top.
T36("F3 Whole book draws its rows when opened, no scroll needed; back and forth keeps them", function()
    MD:SelectView("spells", "overview")
    SP:SetOverviewMode("mine")
    local p = FindPane()
    local sf, content = p.scroll, p.scroll.content
    local FRAME_H = 528 -- the Spells group's 560 less the title row and the bottom inset
    local savedH = sf.h
    sf:SetHeight(FRAME_H)
    local taken, offset, wheel = content:GetHeight(), 0, 0 -- the pass when Overview appeared
    sf.UpdateScrollChildRect = function() taken = content:GetHeight() end
    sf.SetVerticalScroll = function(_, v) offset = tonumber(v) or 0; taken = content:GetHeight() end
    sf.GetVerticalScroll = function() return offset end
    local savedWheel = sf:GetScript("OnMouseWheel")
    sf:SetScript("OnMouseWheel", function(...) wheel = wheel + 1; return savedWheel(...) end)
    local function Drawn()
        local tbl = p.activeTable
        local inWindow, drawn = 0, 0
        for _, f in ipairs(S.allFrames) do
            if f.cells and f.data ~= nil and f.parentFrame == tbl.frame and f:IsShown() then
                local top = -((f.points and f.points.TOPLEFT and f.points.TOPLEFT.y) or 0)
                if top < offset + FRAME_H and top + tbl.rowHeight > offset then
                    inWindow = inWindow + 1
                    if top + tbl.rowHeight <= taken then drawn = drawn + 1 end
                end
            end
        end
        return inWindow, drawn
    end
    local log, good = {}, true
    local function Step(label, mode, min)
        local n, d = Drawn()
        local shown = p.mode == mode and p.activeTable.frame:IsShown()
        log[#log + 1] = string.format("%s %d/%d at %d", label, d, n, offset)
        if not (shown and n >= min and d == n and offset == 0) then good = false end
    end
    local mineH = content:GetHeight()
    Click(p.bookBtn);  Step("book", "book", 20)
    Click(p.mineBtn);  Step("mine", "mine", 3)
    Click(p.bookBtn);  Step("book again", "book", 20)
    sf:VerticalScroll(200) -- the user scrolls Whole book down, then leaves it
    local scrolled = offset
    Click(p.mineBtn);  Step("mine after a scroll", "mine", 3)
    Click(p.bookBtn);  Step("book at its top", "book", 20)
    sf.UpdateScrollChildRect, sf.SetVerticalScroll, sf.GetVerticalScroll = nil, nil, nil
    sf:SetScript("OnMouseWheel", savedWheel)
    sf.h = savedH
    return good and wheel == 0 and scrolled > 0 and content:GetHeight() > FRAME_H and FRAME_H > mineH,
        string.format("%s wheel=%d scrolled=%d mineH=%d bookH=%d", table.concat(log, ", "), wheel, scrolled,
            mineH, content:GetHeight())
end)

--------------------------------------------------------------------------------
-- T95 (docs/SPEC-next.md 4.2 P1, decision 12): the rank card on another
-- class's spells -- the cooldown that paces Holy Shock, a group heal's reach
-- in words (an upper bound) and Power Word: Shield's lockout. The spells are
-- tools/data/books/' extracts of talentsforever's export (CC BY 4.0), added
-- beside the stub's book by tools/stub_books.lua for these two items only
-- (before the ASCII walk below, so what they paint is walked too).
--------------------------------------------------------------------------------
local Books = dofile(here .. "/stub_books.lua")
local CLASS_FAMILIES = { ["Holy Shock"] = true, ["Prayer of Healing"] = true, ["Power Word: Shield"] = true,
    ["Chain Heal"] = true }
local function ClassFamily(row) return CLASS_FAMILIES[row.name] == true end
local restoreBooks = Books.Install(Books.Load("paladin"), { only = ClassFamily, firstSlot = 300, MD = MD })
local restoreBooks2 = Books.Install(Books.Load("priest"), { only = ClassFamily, firstSlot = 320, MD = MD })
local restoreBooks3 = Books.Install(Books.Load("shaman"), { only = ClassFamily, firstSlot = 340, MD = MD })

-- T95-1: Holy Shock's card says its per second is over its 10 s cooldown, and
-- names the cooldown; Holy Light-like spells without one say nothing new
T36("T95 the rank card: a cooldown paces per sec and is named", function()
    OpenView("Holy Shock")
    local shockPerSec, shockCd = PairValue("Per sec"), PairValue("Cooldown")
    local shockTitle = F().card.title:GetText()
    OpenView("Nourish")
    local plain = PairValue("Cooldown") == nil and PairValue("Reach") == nil and PairValue("Lockout") == nil
    local good = shockTitle == "RANK 4" and shockPerSec == "32.0 over its 10 s cooldown" and shockCd == "10 s"
        and plain
    return good, string.format("title=%s perSec=%q cooldown=%q nourishPlain=%s | %s", tostring(shockTitle),
        tostring(shockPerSec), tostring(shockCd), tostring(plain), Pairs())
end)

-- T95-2: Prayer of Healing's card says its reach in words and keeps per mana
-- one member's; Chain Heal's says its chain; Power Word: Shield's its lockout
T36("T95 the rank card: reach in words, per mana one target's; a lockout per target", function()
    OpenView("Prayer of Healing")
    local pohReach, pohMana = PairValue("Reach"), PairValue("Per mana")
    OpenView("Chain Heal")
    local chainReach = PairValue("Reach")
    OpenView("Power Word: Shield")
    local shieldLock, shieldCd, shieldReach = PairValue("Lockout"), PairValue("Cooldown"), PairValue("Reach")
    local good = pohReach == "x up to 5 targets" and pohMana == "0.61"
        and chainReach == "up to 1.75x if 3 are hurt"
        and shieldLock == "15 s per target" and shieldCd == "4 s" and shieldReach == nil
    return good, string.format("poh=%q/%q chain=%q shield=%q/%q/%q", tostring(pohReach), tostring(pohMana),
        tostring(chainReach), tostring(shieldLock), tostring(shieldCd), tostring(shieldReach))
end)

restoreBooks3()
restoreBooks2()
restoreBooks()

--------------------------------------------------------------------------------
-- 11: every string the pane renders or exports is ASCII with no bare pipe
-- (T36: run last, so the rail, the picker and the family views are in it)
--------------------------------------------------------------------------------
do
    local bad
    for _, f in ipairs(S.allFrames) do
        local t = f.GetText and f:GetText()
        if type(t) == "string" and t ~= "" and not bad then
            local good, why = AsciiNoBarePipe(t)
            if not good then bad = why .. " in painted '" .. t .. "'" end
        end
    end
    if not bad and exportText then
        local good, why = AsciiNoBarePipe(exportText)
        if not good then bad = why .. " in the export" end
    end
    check("every string the pane renders or exports is ASCII with no bare pipe", bad == nil, bad)
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
