-- Rank dashboard (/md): a Cell-style movable frame (header bar with title and
-- close), a row of spell tabs, the header/hint lines and the recap. The rank
-- table is an opts set on UI/Dashboard_Rows.lua's one table (T81, below) and
-- the "Simulate" strip is UI/Dashboard_Simulate.lua's; both load first and
-- hand back a small object. Settings are in the options frame
-- (UI/OptionsFrame.lua).
--
-- T80 (C1 of docs/PLAN-refactor-ux.md, decision 10, the author's answer 1):
-- the window is the window manager's (UI/Windows.lua) as on Forever -- placed
-- by it, a size per group handed in at Register (SIZES below), on the ESC
-- stack instead of UISpecialFrames, hidden in combat and reopened on the same
-- view, and every MD:SelectView through MD.Win:ShowMain. A place the client
-- kept for it while it was user-placed is adopted once.
local _, MD = ...
local UI = MD.UI

local WIDTH, HEIGHT = 912, 617 -- +20% (author, 2026-09-06: not everything fit); was 760 x 514
local frame, statsFS, calloutFS, hintFS, recapFS, messageFS, effectiveCB
local rankTable, simStrip, wasteView, reviewView, practiceView, nav
local currentGroup = "spells"
local currentFamily = "HealingTouch"
local userPicked = false   -- once a tab is clicked, stop picking one automatically

-- The family this character actually casts most (persisted counts kept by the
-- spend tracker), so the dashboard opens on the spell that matters. The first
-- dungeon log had one Healing Touch in 29 minutes and 245 Lifeblooms; it opened
-- on Healing Touch.
local function DefaultFamily()
    local counts = MD.cdb and MD.cdb.familyCasts
    local best, bestN = "HealingTouch", -1
    if counts then
        for _, family in ipairs(MD.SpellData.familyOrder) do
            local info = MD.SpellData.families[family]
            if info and not info.exclude and (counts[family] or 0) > bestN then
                best, bestN = family, counts[family] or 0
            end
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- The rank table (T81, C2 of docs/PLAN-refactor-ux.md; review U5 / A23;
-- mockup M6's RANKS table): an `opts` set on UI/Dashboard_Rows.lua's one
-- table, as on Forever -- numbers right-justified in Arial Narrow on 20-px
-- rows, zebra, a rule under the header, the suggested row marked by its fill
-- and the 2-px accent bar (no gold, no star), a per-mana bar in the HPM cell,
-- and a Tag column (best / max / beaten / learn at N / rolling) instead of
-- the gold note, each tag explaining itself on hover. The columns keep TBC's
-- words (Heal/cast, HPM, HPS, To OOM): the glossary (Tip:Columns, every
-- header's hover) and the hint line name them. The rows are RankMath's, the
-- row hover its derivation (Tip:Row), beside the row.
--------------------------------------------------------------------------------
local RESET = "|r"
local RANK_W = 600
-- Columns whose values become overheal-adjusted in "Effective" mode. Mana,
-- Cast and To OOM never move: mana spent is mana spent.
local EFFECTIVE_COLS = { heal = true, hpm = true, hps = true }

local function Fmt(n, decimals)
    return string.format(decimals and ("%." .. decimals .. "f") or "%d", n)
end

-- What every header says on hover: the glossary, which carries the regen and
-- mana the To OOM column counts from.
local function Glossary() return MD.Tip and MD.Tip:Columns() or nil end

-- A row's tag (the author's words, docs/PLAN-refactor-ux.md 8.1 item 7):
-- nil for none.
local function TagOf(r)
    if not r then return nil end
    if not r.known then return "learn at " .. tostring(r.level) end
    if r.virtual then return "rolling" end
    if r.suggested then return "best" end
    if r.isMax then return "max" end
    if r.dominated then return "beaten" end
    return nil
end

local function TagText(r)
    local tag = TagOf(r)
    if not tag then return "" end
    return UI.Hex(tag == "best" and "accent" or "label") .. tag .. RESET
end

-- A tag explains itself (T78's shape, mockup M5 / M6): one sentence, and a
-- beaten rank names the rank that beats it with both numbers side by side.
local function TagTip(r)
    local tag = TagOf(r)
    if not tag then return nil end
    if tag == "beaten" then
        local by = r.beatenBy -- the row the table's Render found (below)
        if not by then
            return { { l = "Beaten", c = "text" },
                     { l = "Another rank wins on both heal per mana and heal per second.", c = "label", wrap = true } }
        end
        local name = "Rank " .. by.rank
        return {
            { l = "Beaten by " .. name, c = "text" },
            { l = "HPM", r = Fmt(by.hpm, 2) .. " vs " .. Fmt(r.hpm, 2), c = "label", rc = "text" },
            { l = "HPS", r = Fmt(by.hps) .. " vs " .. Fmt(r.hps), c = "label", rc = "text" },
            { l = name .. " is better on both, and you know it.", c = "muted", wrap = true },
        }
    end
    local title, sentence
    if tag == "best" then
        title = "Best"
        sentence = "The rank SpellTuner suggests: the best heal per mana among the ranks nothing beats, "
            .. "of those that heal at least " .. Fmt((MD.Rules and MD.Rules.SUGGESTED_FLOOR or 0.4) * 100)
            .. "% of your highest." .. (r.isMax and " It is your highest rank too." or "")
    elseif tag == "max" then
        title, sentence = "Max", "Your highest known rank."
    elseif tag == "rolling" then
        title = "Rolling " .. tostring(r.rankLabel or "")
        sentence = "Lifebloom refreshed before it blooms, at this many stacks: 6 ticks, no bloom. "
            .. "A different use of the spell, so it is not ranked against the single casts."
    else
        title = "Not learned"
        sentence = "Not learned yet: learn at level " .. tostring(r.level) .. "."
    end
    return { { l = title, c = "text" }, { l = sentence, c = "label", wrap = true } }
end

local RANK_COLS = {
    { key = "rank",  x = 8,   w = 44,  label = "Rank",      tooltip = Glossary },
    { key = "level", x = 52,  w = 34,  label = "Lvl",       justify = "RIGHT", tooltip = Glossary },
    { key = "cost",  x = 86,  w = 50,  label = "Mana",      justify = "RIGHT", tooltip = Glossary },
    { key = "heal",  x = 136, w = 74,  label = "Heal/cast", justify = "RIGHT", tooltip = Glossary },
    { key = "hpm",   x = 210, w = 124, label = "HPM",       justify = "RIGHT", type = "bar", barWidth = 80, gap = 4,
      tooltip = Glossary },
    { key = "hps",   x = 334, w = 58,  label = "HPS",       justify = "RIGHT", tooltip = Glossary },
    { key = "cast",  x = 392, w = 52,  label = "Cast",      justify = "RIGHT", tooltip = Glossary },
    { key = "casts", x = 444, w = 58,  label = "To OOM",    justify = "RIGHT", tooltip = Glossary },
    { key = "tag",   x = 510, w = 84,  label = "", font = UI.FONT_SMALL, cellTooltip = function(r) return TagTip(r) end },
}

-- The values a row shows: overheal-adjusted in Effective mode when the row
-- has a measurement of its own, else raw with `unmeasured` set.
local function ShownValues(r, effective)
    if effective and r.overheal then return r.effHeal, r.effHpm, r.effHps, false end
    return r.heal, r.hpm, r.hps, effective
end

-- r.hpmFrac (the HPM bar's fill) and r.beatenBy (the row that beats a beaten
-- one) are written on the rows by the table's Render, below: RankMath hands
-- out fresh rows on every Compute, so they never outlive the render.
local function RenderRank(row, r, color)
    local effective = MD.db and MD.db.effectiveMode and true or false
    local heal, hpm, hps, unmeasured = ShownValues(r, effective)
    local c = row.cells
    c.wide:SetText("")
    c.rank:SetText(color .. (r.rankLabel or ("R" .. r.rank)) .. RESET)
    c.level:SetText(color .. r.level .. RESET)
    c.cost:SetText(color .. Fmt(r.cost) .. RESET)
    -- In effective mode a row with no measurement of its own keeps its raw
    -- value and gets a "?" so the two are never confused.
    c.heal:SetText(color .. Fmt(heal) .. RESET .. (unmeasured and (UI.Hex("muted") .. "?" .. RESET) or ""))
    c.hpm:SetText(color .. Fmt(hpm, 2) .. RESET)
    c.hps:SetText(color .. Fmt(hps) .. RESET)
    -- the "*" means the cast time is a Nature's Grace average
    c.cast:SetText(color .. Fmt(r.cast, 1) .. "s" .. RESET .. (r.ng and (UI.Hex("muted") .. "*" .. RESET) or ""))
    c.casts:SetText(color .. (r.casts == math.huge and "inf" or Fmt(r.casts)) .. RESET)
    c.tag:SetText(TagText(r))
    row:SetBar("hpm", r.hpmFrac, (not r.known) and 0.25 or nil)
end

local function RankEnter(row, r)
    if not (r and MD.Tip and MD.RankMath) then return end
    MD.Tip:Show(row, MD.Tip:Row(MD.RankMath:Explain(r.id, r.variant)), { anchor = "beside" })
end

-- MD.DashboardParts.CreateRankTable(content, width) -> the table's api, whose
-- Render takes RankMath:Compute()'s rows for one family. On DashboardParts so
-- C3's Spells view can build its RANKS on it, and dashui can build one.
function MD.DashboardParts.CreateRankTable(content, width)
    local header = {}
    local api = MD.DashboardParts.CreateTable(content, width, {
        cols = RANK_COLS, header = header,
        font = UI.FONT_NUM or UI.FONT, wideFont = UI.FONT_SMALL,
        rowHeight = UI.Pitch and UI.Pitch(20) or 20, headerHeight = UI.Pitch and UI.Pitch(22) or 22,
        headerRule = true, zebra = true, rowWidth = RANK_W, marker = "bar",
        headerFont = UI.FONT_SPECIAL, headerColor = UI.Hex("label"),
        render = RenderRank, onEnter = RankEnter,
        onLeave = function() if MD.Tip then MD.Tip:Hide() end end,
    })
    local paint = api.Render
    -- rows come straight from RankMath:Compute(). In "Effective" mode the
    -- three healing columns' headers take the accent, so it is never
    -- ambiguous which numbers moved.
    function api:Render(rows)
        local effective = MD.db and MD.db.effectiveMode and true or false
        for i, col in ipairs(RANK_COLS) do
            header[i] = (effective and EFFECTIVE_COLS[col.key]) and (UI.Hex("accent") .. col.label .. RESET) or nil
        end
        rows = rows or {}
        -- the bar's scale: the best HPM shown among the real ranks
        local suggested, maxHpm
        for _, r in ipairs(rows) do
            if r.suggested then suggested = r end
            local _, hpm = ShownValues(r, effective)
            if not r.virtual and type(hpm) == "number" and (not maxHpm or hpm > maxHpm) then maxHpm = hpm end
        end
        -- who beats a beaten rank (Spells/RankRules.lua, the rule the
        -- dominance came from; a beater is always a known, real rank)
        if MD.RankRules and MD.RankMath and MD.RankMath.RULE_FIELDS then
            MD.RankRules.DominatedBy(rows, suggested, MD.RankMath.RULE_FIELDS)
        end
        for _, r in ipairs(rows) do
            local _, hpm = ShownValues(r, effective)
            r.hpmFrac = (maxHpm and maxHpm > 0 and type(hpm) == "number") and hpm / maxHpm or nil
            r.beatenBy = nil
            if r.dominatedBy ~= nil then
                for _, x in ipairs(rows) do
                    if x.id == r.dominatedBy and not x.virtual then r.beatenBy = x end
                end
            end
        end
        return paint(api, rows)
    end
    return api
end

--------------------------------------------------------------------------------
-- refresh
--------------------------------------------------------------------------------
local function Shown(f, on) if not f then return end if on then f:Show() else f:Hide() end end

local function Refresh()
    if not frame or not frame:IsShown() then return end

    -- Only two groups own this furniture. Simulate and Settings bring their own
    -- panel, and drawing the rank table's header lines and the what-if strip on
    -- top of it is what the author's screenshots showed (v0.11.5).
    local spells, reports = currentGroup == "spells", currentGroup == "reports"
    Shown(statsFS, spells or reports)
    Shown(calloutFS, spells or reports)
    Shown(hintFS, spells or reports)
    Shown(recapFS, spells or reports)
    if simStrip then simStrip:SetShown(spells and MD.player.isDruid) end
    Shown(effectiveCB, spells and MD.player.isDruid)
    if not (spells or reports) then
        messageFS:Hide()
        return
    end
    messageFS:Hide()

    -- overall info line: current regen state
    local RM = MD.Regen
    local bonus = 0
    if GetSpellBonusHealing then
        local ok, v = pcall(GetSpellBonusHealing)
        if ok then bonus = v or 0 end
    end
    local spiritPerSec, mp5Gear, _, unreported = RM:Components()
    statsFS:SetFormattedText(
        "+%d healing   regen |cff33ff66%d|r mana/s out of 5SR, |cffffaa33%d|r casting   ~%d mp5 spirit, ~%d mp5 gear/buffs%s",
        bonus, RM.base, RM.casting, spiritPerSec * 5, mp5Gear,
        unreported > 0 and string.format(", +%d mp5 not in the API (Dreamstate %d, measured %d)",
            unreported * 5 + 0.5, RM.dreamstate * 5 + 0.5, RM.measured * 5 + 0.5) or "")

    -- the Waste and Review views each replace the rank table, its hint and its
    -- callout
    -- a pane is built on first sight, so any of these may still be nil
    local review = (currentFamily == "Review" or currentFamily == "Runs")
    if review and reviewView then
        effectiveCB:Hide()
        messageFS:Hide()
        if rankTable then rankTable:Release() end
        calloutFS:SetText("|cffffcc00The fights this character recorded, and what the engine can reproduce about each.|r")
        -- T81: Review's words since C1 gave TBC the Result column and the
        -- row menu (it named a validate column and a passing-only Coach)
        hintFS:SetText(UI.Hex("muted") .. "A fight the engine cannot replay says why in the Result column. Coach runs " ..
            "only on fights that replay, because advice from a fight the engine gets wrong is worse than none; " ..
            "right-click a row for Coach anyway.|r")
        reviewView:Render()
        return
    end

    local waste = currentFamily == "Waste"
    Shown(effectiveCB, not waste and not review and MD.player.isDruid and spells)
    if waste and wasteView then
        messageFS:Hide()
        if rankTable then rankTable:Release() end
        calloutFS:SetText("|cffffcc00Where the mana went and where the healing was wasted, from your own combat log.|r")
        hintFS:SetText("|cff888888Overheal is a share of gross healing. Wasted mana is each event that healed nothing, " ..
            "carrying its share of the cast's cost. Mana belongs to the spell, so it only appears in Spell mode.|r")
        wasteView:Render()
        return
    end

    if review or waste or not spells then return end
    if not MD.player.isDruid then
        if rankTable then rankTable:Release() end
        messageFS:Show()
        messageFS:SetText("Rank analysis is Druid-only in v1 - the OOM widget, datatext and advisor still work for your class.")
        calloutFS:SetText("")
        return
    end

    local results = MD.RankMath:Compute()
    local info = MD.RankMath.info
    if info then
        simStrip:SetPlaceholders(info.live)
        if info.simulated then
            statsFS:SetText("|cffff9933SIMULATION|r  " .. statsFS:GetText())
        end
        if info.costCtx then
            -- the client can only price the form and talents you actually have
            statsFS:SetText(statsFS:GetText() ..
                "   |cffff9933costs from the static table while simulating form/talents|r")
        end
    end
    if info and info.relic then
        local r = info.relic
        local fl = r.family and MD.SpellData.families[r.family] and MD.SpellData.families[r.family].label or "?"
        local what = r.flat and string.format("+%d %s", r.flat, fl)
            or r.perTick and string.format("+%d per %s tick", r.perTick, fl)
            or r.castReduce and string.format("-%.2fs %s cast", r.castReduce, fl)
            or r.cost and string.format("-%d mana %s", r.cost, fl)
            or r.aura and string.format("+%d Tree aura", r.aura) or ""
        if r.verify then what = what .. ", unverified" end
        statsFS:SetText(statsFS:GetText() .. string.format("   relic: %s (%s)", r.name, what))
    end
    if info and info.treeAura > 0 then
        statsFS:SetText((statsFS:GetText():gsub("^%+%d+ healing",
            string.format("+%d healing (+%d Tree of Life aura on party targets)", info.statBonus, info.treeAura))))
    elseif info and info.inTree then
        statsFS:SetText((statsFS:GetText():gsub("^%+%d+ healing", "%0 (Tree aura not counted - see Settings)")))
    end
    if info then
        -- One line only: this sits 18px above the table, and the old paragraph
        -- wrapped onto the rows. The full glossary is the header row's tooltip.
        hintFS:SetFormattedText("|cff888888HPM heal per mana - HPS heal per second of cast - " ..
            "To OOM chain-casts from %d mana at %d mp5 casting regen.  Hover the header or any row.|r",
            info.mana, info.castingRegen * 5 + 0.5)
    end

    local res = results[currentFamily]
    if not res or not rankTable then
        if rankTable then rankTable:Release() end
        calloutFS:SetText("")
        return
    end

    local tolNote = (MD:InTreeForm() and not res.tol) and "  |cffff4444(not castable in Tree form)|r" or ""
    local ohNote = ""
    if MD.Overheal then
        local frac, n = MD.Overheal:FamilyFraction(currentFamily)
        if frac then
            ohNote = string.format("  |cff888888overheal %d%% (%d events)|r", frac * 100, n)
        end
    end
    calloutFS:SetText("|cffffcc00" .. (res.callout or "") .. "|r" .. tolNote .. ohNote)

    rankTable:Render(res.rows)

    -- recap
    local last = MD.fightHistory and MD.fightHistory[#MD.fightHistory]
    if last then
        recapFS:SetText("Last fight: " .. (last.summary or "-") ..
            (#MD.fightHistory > 1 and ("  |cff666666(" .. #MD.fightHistory .. " fights this session)|r") or ""))
    else
        recapFS:SetText("|cff666666No fights recorded this session yet.|r")
    end
end

--------------------------------------------------------------------------------
-- frame construction (v0.11.1: the navigation kit, docs/SPEC-v0.11.md)
--
-- The window is groups down the left and that group's views along the top. The
-- three panes -- the rank table, Waste and Review -- are unchanged and simply
-- parent themselves to the content frame; they are built the first time their
-- view is selected and cached after, so a non-druid never builds a rank table.
--
-- `currentFamily` is the selected VIEW id, which is why the families and the
-- two reports can share one variable: a family id ("Rejuvenation") and a report
-- id ("Waste") are both just the view that is showing.
--------------------------------------------------------------------------------
local CONTENT_W = 912          -- what the panes were laid out for; the window is wider by the nav
local NAV_W, NAV_PAD = 108, 8
local WIN_W, WIN_H = CONTENT_W + NAV_W + 2 * NAV_PAD, 646

-- T80 (C1, review A22): TBC's sizes per group, handed to the window manager
-- at Register. Every pane here is laid out for the 912-wide content, so each
-- group is today's 1036 x 646 and fixed (its minimum is its size: no grip).
-- C3 gives Spells its own size.
local SIZES = {
    spells   = { w = WIN_W, h = WIN_H, minW = WIN_W, minH = WIN_H },
    reports  = { w = WIN_W, h = WIN_H, minW = WIN_W, minH = WIN_H },
    simulate = { w = WIN_W, h = WIN_H, minW = WIN_W, minH = WIN_H },
    settings = { w = WIN_W, h = WIN_H, minW = WIN_W, minH = WIN_H },
}

-- Reports' views depend on what has been recorded.
local function ReportViews()
    local views = { { id = "Waste", text = "Waste" }, { id = "Review", text = "Review" } }
    if MD.RunRecorder and #(MD.RunRecorder:List()) > 0 then
        views[#views + 1] = { id = "Runs", text = "Runs" }
    end
    return views
end

local function Groups()
    local spells = {}
    for _, family in ipairs(MD.SpellData.familyOrder) do
        local info = MD.SpellData.families[family]
        if info and not info.exclude then
            spells[#spells + 1] = { id = family, text = info.label or family,
                                    hidden = not MD.player.isDruid }
        end
    end
    return {
        { id = "spells", text = "Spells", views = spells },
        -- Waste and Review work for any class: a recorded stream is numbers
        -- Runs appears only once one has been recorded: a view that is always
        -- empty teaches nothing, and nav:SetViews puts it there the moment a
        -- run is stored (v0.11.4)
        { id = "reports", text = "Reports", views = ReportViews() },
        -- v0.15.0: Practice first. Building a fight for the planner to play
        -- answered a question nobody was asking; playing it yourself does
        { id = "simulate", text = "Simulate", views = {
            { id = "practice", text = "Practice" }, { id = "build", text = "Build a fight" } } },
        { id = "settings", text = "Settings", views = {
            { id = "general", text = "General" }, { id = "about", text = "About" } } },
    }
end

local function CreateDashboard()
    if nav then return end     -- MD_READY can be fired more than once
    nav = UI.CreateNavFrame("SpellTuner", "SpellTunerDashboard", WIN_W, WIN_H, Groups(),
        function(group, view, content)
            -- built once, on first sight
            if group == "reports" and view == "Waste" then
                wasteView = MD.DashboardParts.CreateWaste(content, CONTENT_W)
                wasteView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -104)
                wasteView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 24)
                return wasteView.frame
            elseif group == "reports" and view == "Runs" then
                -- the Review pane already knows how to list a run's pulls; the
                -- Runs view is that pane with a run selected instead of Fights
                if not reviewView then
                    reviewView = MD.DashboardParts.CreateReview(content, CONTENT_W)
                    reviewView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -104)
                    reviewView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 24)
                end
                return reviewView.frame
            elseif group == "reports" and view == "Review" then
                reviewView = MD.DashboardParts.CreateReview(content, CONTENT_W)
                reviewView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -104)
                reviewView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 24)
                return reviewView.frame
            elseif group == "simulate" and view == "practice" then
                practiceView = MD.DashboardParts.CreatePractice(content, CONTENT_W)
                practiceView.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -6)
                practiceView.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
                return practiceView.frame
            elseif group == "simulate" then
                if MD.AdoptSimPanel then return MD:AdoptSimPanel(content) end
                return nil
            elseif group == "settings" then
                -- one panel for both settings views; the tabs inside it show
                -- and hide themselves on the ShowOptionsTab callback
                if MD.AdoptOptionsPanel then MD:AdoptOptionsPanel(content) end
                return MD.optionsFrame
            elseif group == "spells" and not rankTable then
                rankTable = MD.DashboardParts.CreateRankTable(content, CONTENT_W) -- T81
                rankTable.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -104)
                rankTable.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 24)
                return rankTable.frame
            end
            return rankTable and rankTable.frame or nil
        end,
        function(group, view)
            -- the source is set when the VIEW changes, never on a refresh: the
            -- 2s ticker calls Refresh, and setting it there put the run back
            -- one second after the author clicked Fights (v0.11.6)
            if group == "reports" and reviewView and view ~= currentFamily then
                reviewView:SetSource(view == "Runs" and "run" or "fights")
            end
            currentGroup, currentFamily = group, view
            userPicked = true
            MD.Win:SetGroup("main", group) -- T80: the group's own size, the TOPLEFT kept
            MD:Fire("UI_VIEW_SELECTED", group, view)
            Refresh()

        end)
    frame = nav.frame
    local content = nav:Content()

    -- Settings is the fourth group now, not a button that opens a second window
    effectiveCB = UI.CreateCheckButton(frame, "Effective", function(checked)
        MD.db.effectiveMode = checked
        Refresh()
    end, "Overheal-adjusted values", "Heal, HPM and HPS become value x (1 - measured overheal),",
        "from your own combat log. Mana, Cast and To OOM never move.",
        "A grey ? means that rank has no measurement of its own yet.")
    effectiveCB:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -100, -2) -- label runs right of the box
    effectiveCB:SetShown(MD.player.isDruid)

    simStrip = MD.DashboardParts.CreateStrip(content, 2, -2, Refresh)

    statsFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsFS:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -46)
    statsFS:SetJustifyH("LEFT")
    statsFS:SetWidth(CONTENT_W - 8)

    calloutFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    calloutFS:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -64)
    calloutFS:SetJustifyH("LEFT")
    calloutFS:SetWidth(CONTENT_W - 8)

    hintFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintFS:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -82)
    hintFS:SetJustifyH("LEFT")
    hintFS:SetWidth(CONTENT_W - 8)

    messageFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    messageFS:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -110)
    messageFS:SetJustifyH("LEFT")
    messageFS:SetWidth(CONTENT_W - 8)
    messageFS:Hide()

    recapFS = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    recapFS:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 2)
    recapFS:SetJustifyH("LEFT")
    recapFS:SetWidth(CONTENT_W - 8)

    frame:SetScript("OnShow", function()
        effectiveCB:SetChecked(MD.db.effectiveMode and true or false)
        local path = MD.db.uiPath
        if path and path[1] then
            nav:Select(path[1], path[2])
        else
            nav:Select("spells", DefaultFamily())
        end
        Refresh()
    end)

    -- T80 (C1): the window manager's host (registered after the OnShow script
    -- above, since Register hooks OnShow): its strata, place and scale, the
    -- sizes per group, one ESC stack entry (no UISpecialFrames line), the
    -- combat hide; how to open it on a view and read the one it shows; the
    -- practice view a session goes back to. adoptPlaced: the place the client
    -- kept for it while it was user-placed (before C1) becomes its saved one.
    MD.Win:Register(frame, { key = "main", role = "host", sizes = SIZES, group = "spells",
        open = function(group, view) return MD:OpenMainWindow(group, view) end,
        selected = function() return MD:SelectedView() end,
        practicePath = { "simulate", "practice" }, adoptPlaced = true })

    -- The "To OOM" column follows your current mana: re-render every 2s while
    -- the frame is open (rendering only; the model is event-driven).
    local acc = 0
    MD:OnTick(function(dt)
        if not frame:IsShown() then return end
        acc = acc + dt
        if acc >= 2 then
            acc = 0
            Refresh()
        end
    end)
end

function MD:SelectedView()
    if not nav then return nil end
    return nav:Selected()
end

-- What MD.Win:ShowMain opens (T80, the host's `open`): the window on the view
-- asked for, or on the remembered one when none is named.
function MD:OpenMainWindow(group, view)
    if not nav then return end
    if not frame:IsShown() then frame:Show() end
    if group then nav:Select(group, view) end
end

-- Every entry point that wants a particular view goes through here: /md sim,
-- /md options, the minimap button's right-click. T80 (C1): through the window
-- manager, which closes a replay first and refuses while practice plays.
function MD:SelectView(group, view)
    if not nav then return end
    return MD.Win:ShowMain(group, view)
end

function MD:ToggleDashboard()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else MD.Win:ShowMain() end
end

-- Kept for the minimap button's right-click.
function MD:OpenDashboardSettings()
    MD:ShowOptionsFrame("general")
end

-- a run stored while the window is open makes the Runs view appear
local function RefreshReportViews()
    if nav then nav:SetViews("reports", ReportViews()) end
end
MD:RegisterCallback("RUN_STORED", RefreshReportViews)

MD:RegisterCallback("MD_READY", CreateDashboard)
MD:RegisterCallback("TALENTS_CHANGED", Refresh)
MD:RegisterCallback("SPELLS_REBUILT", Refresh)
MD:RegisterCallback("FIGHT_RECORDED", Refresh)
MD:RegisterCallback("FORM_CHANGED", Refresh) -- Tree of Life: costs and aura change
MD:On("PLAYER_EQUIPMENT_CHANGED", function()
    if frame and frame:IsShown() then Refresh() end
end)
