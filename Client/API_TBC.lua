-- TBC's own names for the add-on-management bindings -- the classic globals,
-- unmoved on this client. Listed by SpellTuner_TBC.toc only, right after
-- Client/API.lua. No forbidden events: TBC registers the combat log today
-- (UI/Summary.lua, through MD:On) and this task changes none of that.
local _, MD = ...

MD.API.Bind({
    AddOnMetadata = "GetAddOnMetadata",
    IsAddOnLoaded = "IsAddOnLoaded",
    LoadAddOn = "LoadAddOn",
    IsAddOnLoadOnDemand = "IsAddOnLoadOnDemand",
    AddOnInfo = "GetAddOnInfo",
})

-- T15: GetSpellInfo's first return is the name -- all Engine/SimModel.lua and
-- Engine/SimPlanner.lua's four call sites (both TOCs list both files) use of
-- it, so the shared code can call MD.API.SpellName(id) on either client.
MD.API.Bind({
    SpellName = "GetSpellInfo",
})

-- T16a (UI/ReplayWindow.lua): the icon fallback used GetSpellInfo's third
-- return for the texture on the 2.5.x client; Forever's own is T7's
-- C_Spell.GetSpellTexture (Client/API_Forever.lua). Same binding name either
-- side.
MD.API.Bind({
    SpellTexture = "GetSpellTexture",
})

-- T16b (UI/Dashboard_Review.lua): the Review tab's own progress line reads
-- the current zone; Forever's own binding is Client/API_Forever.lua's (T13's
-- recorder). Same binding name, same classic global either side.
MD.API.Bind({
    RealZoneText = "GetRealZoneText",
})

-- T18 (Engine/Practice.lua): the same client calls the bindings import needs on
-- Forever (Client/API_Forever.lua), the classic globals unmoved on this client
-- -- plus GetSpecialization, which Forever's own baseline lacks (Client/
-- API_Forever.lua's own comment).
MD.API.Bind({
    BindingCount = "GetNumBindings",
    Binding = "GetBinding",
    BindingAction = "GetBindingAction",
    ActionInfo = "GetActionInfo",
    MacroInfo = "GetMacroInfo",
    Specialization = "GetSpecialization",
})

-- T111 (docs/SPEC-next.md 4.2 P5, decision 8 (b)): what Spells/Book_TBC.lua
-- reads to put a priest's, shaman's or paladin's ranks on the TBC rank table
-- -- the spellbook walk, each rank's own text, cost, cast, learn level and
-- cooldown, and the two stats the rank math puts on top. Every name is the
-- classic global; which of them the 2.5.x client answers is VERIFY (the book
-- falls back from each to the spell's tooltip lines, below, and says so).
-- The druid's own path reads none of them (Data/SpellData.lua is unchanged).
--   SpellBookItemName   (slot, "spell") -> name, rank text, spell id
--   SpellBookItemKind   (slot, "spell") -> "SPELL", spell id (positional:
--                        Forever's SpellBookItemInfo is a table, so the TBC
--                        read has a name of its own)
--   SpellInfoList       GetSpellInfo's positional returns (name, rank, icon,
--                        cast ms, min range, max range, spell id); also how a
--                        lower rank is found by "Name(Rank N)"
MD.API.Bind({
    SpellTabCount = "GetNumSpellTabs",
    SpellTabInfo = "GetSpellTabInfo",
    SpellBookItemName = "GetSpellBookItemName",
    SpellBookItemKind = "GetSpellBookItemInfo",
    SpellInfoList = "GetSpellInfo",
    SpellDescription = "GetSpellDescription",
    SpellPowerCost = { client = "GetSpellPowerCost", copy = 2 },
    SpellLevelLearned = "GetSpellLevelLearned",
    BaseCooldown = "GetSpellBaseCooldown",
    SpellBonusHealing = "GetSpellBonusHealing",
    SpellCritChance = "GetSpellCritChance",
})

-- T111: a spell's tooltip as plain lines, the book's fallback for every read
-- above (the description when GetSpellDescription is absent, the cost, cast,
-- cooldown and "Requires level" lines). A hidden GameTooltip owned by
-- WorldFrame, filled by SetSpellByID (else SetHyperlink "spell:<id>") and read
-- line by line -- the scan addons have used on this client since 1.x. Answers
-- a list of { l = left text, r = right text } (strings only), or nil plus
-- "absent" / "error". Never raises; the tooltip is never shown.
local SCAN = "SpellTunerScanTooltip"
local function ScanTip()
    local tip = _G[SCAN]
    if tip == nil and type(CreateFrame) == "function" then
        tip = CreateFrame("GameTooltip", SCAN, nil, "GameTooltipTemplate")
    end
    return tip
end
local function LineText(region)
    if type(region) ~= "table" or type(region.GetText) ~= "function" then return nil end
    local text = region:GetText()
    if type(text) == "string" and text ~= "" then return text end
    return nil
end
function MD.API.SpellTooltipLines(id)
    if type(id) ~= "number" then return nil, "absent" end
    local ok, out = pcall(function()
        local tip = ScanTip()
        if type(tip) ~= "table" then return nil end
        if tip.SetOwner and WorldFrame then tip:SetOwner(WorldFrame, "ANCHOR_NONE") end
        if tip.ClearLines then tip:ClearLines() end
        if type(tip.SetSpellByID) == "function" then
            tip:SetSpellByID(id)
        elseif type(tip.SetHyperlink) == "function" then
            tip:SetHyperlink("spell:" .. id)
        else
            return nil
        end
        local n = type(tip.NumLines) == "function" and tip:NumLines() or 0
        local lines = {}
        for i = 1, n do
            local l = LineText(_G[SCAN .. "TextLeft" .. i])
            local r = LineText(_G[SCAN .. "TextRight" .. i])
            if l or r then lines[#lines + 1] = { l = l, r = r } end
        end
        if tip.Hide then tip:Hide() end
        return lines
    end)
    if not ok then return nil, "error" end
    if out == nil then return nil, "absent" end
    return out
end
MD.API._bindings.SpellTooltipLines = "GameTooltip.SetSpellByID"

-- T120 (UI/SpellsPane.lua on both lines, docs/tasks/T120-one-spells-pane.md):
-- what the cursor holds, for a spell dragged from the spellbook onto the
-- Spells rail (UI/SpellRail.lua's CanDrop / Drop). The classic shape for a
-- spell is ("spell", book slot, book type, spell id) -- UNVERIFIED on the
-- 2.5.x client until the author drags one (docs/TESTING.md 49): the id from
-- the fourth return, else the slot's through GetSpellBookItemInfo (the
-- SpellBookItemKind binding above). Answers `kind, spellId` as Forever's
-- does: the kind only when it is a plain string, the id only for a "spell";
-- anything absent or raising answers nil. Read only: the cursor is never
-- cleared.
function MD.API.CursorInfo()
    local kind, slot, bookType, id = MD.API.Call("GetCursorInfo")
    if type(kind) ~= "string" then return nil end
    if kind ~= "spell" then return kind, nil end
    if type(id) == "number" then return kind, id end
    if type(slot) == "number" then
        local _, fromSlot = MD.API.Call("SpellBookItemKind", slot,
            (type(bookType) == "string") and bookType or "spell")
        if type(fromSlot) == "number" then return kind, fromSlot end
    end
    return kind, nil
end
MD.API._bindings.CursorInfo = "GetCursorInfo"

-- T120: the game's own spell tooltip for one rank, the rank row's hover in a
-- spell's view -- tooltip:SetSpellByID(id), which the 2.5.x client has (the
-- scan tooltip above uses it); UI/SpellTooltip.lua's OnTooltipSetSpell hook
-- then appends what it appends on the action bar. Forever's contract
-- (Client/API_Forever.lua): true, or nil plus "absent" (no method, or an id
-- that is not a number) / "error" (the method raised); never raises.
function MD.API.SetTooltipSpell(tooltip, id)
    if type(id) ~= "number" then return nil, "absent" end
    local ok, fn = pcall(function() return type(tooltip) == "table" and tooltip.SetSpellByID end)
    if not ok then return nil, "error" end
    if type(fn) ~= "function" then return nil, "absent" end
    if not pcall(fn, tooltip, id) then return nil, "error" end
    return true
end
MD.API._bindings.SetTooltipSpell = "GameTooltip.SetSpellByID"
