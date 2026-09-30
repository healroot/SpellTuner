-- Forever's own names for the add-on-management bindings (add-on management
-- moved under C_AddOns on this client, plan Facts) and the one event this
-- client refuses to register -- the sixth probe report saw
-- ADDON_ACTION_FORBIDDEN fire for COMBAT_LOG_EVENT_UNFILTERED rather than a
-- raise, and no Forever file may name that event again (FOREVER-PLAN.md
-- §1.2). Listed by the Forever TOCs only, right after Client/API.lua.
local _, MD = ...

MD.API.Bind({
    AddOnMetadata = "C_AddOns.GetAddOnMetadata",
    IsAddOnLoaded = "C_AddOns.IsAddOnLoaded",
    LoadAddOn = "C_AddOns.LoadAddOn",
    IsAddOnLoadOnDemand = "C_AddOns.IsAddOnLoadOnDemand",
    AddOnInfo = "C_AddOns.GetAddOnInfo",
})

MD.API.ForbidEvent("COMBAT_LOG_EVENT_UNFILTERED")

-- T7 (Spells/Book.lua): the spellbook and spell bindings, most of them
-- copying (docs/tasks/T7-spell-book.md Facts: every shape past the book walk
-- itself is the retail 12.x documentation, UNVERIFIED here) so Book never
-- indexes a client table directly.
MD.API.Bind({
    SpellBookItemInfo = { client = "C_SpellBook.GetSpellBookItemInfo", copy = 1 },
    SpellBookSkillLines = "C_SpellBook.GetNumSpellBookSkillLines",
    SpellBookSkillLineInfo = { client = "C_SpellBook.GetSpellBookSkillLineInfo", copy = 1 },
    SpellBookItemIsLowRank = "C_SpellBook.IsSpellBookItemLowRank",
    SpellKnown = "C_SpellBook.IsSpellKnown",
    SpellName = "C_Spell.GetSpellName",
    SpellSubtext = "C_Spell.GetSpellSubtext",
    SpellDescription = "C_Spell.GetSpellDescription",
    SpellInfo = { client = "C_Spell.GetSpellInfo", copy = 1 },
    -- copy = 2: an array of cost-type rows, one level of table past the array itself.
    SpellPowerCost = { client = "C_Spell.GetSpellPowerCost", copy = 2 },
    SpellLevelLearned = "C_Spell.GetSpellLevelLearned",
    BaseSpell = "C_Spell.GetBaseSpell",
    SpellTexture = "C_Spell.GetSpellTexture",
    -- copy = 3: the tooltip table -> its `lines` array -> each line's own fields.
    SpellTooltipData = { client = "C_TooltipInfo.GetSpellByID", copy = 3 },
})

-- T12 (Spells/Measure.lua): plain out of combat, UNKNOWN in combat (Facts --
-- stats go secret in combat, T7a's seventh report) -- read through the
-- adapter like every other stat, printed as "?" when it does not come back a
-- plain number.
MD.API.Bind({
    SpellBonusHealing = "GetSpellBonusHealing",
})

-- T15 (Modules/SpellTuner_Replay/Kit_Forever.lua): crit chance per school,
-- plain out of combat (m2 296), UNKNOWN in combat -- same reasoning as
-- SpellBonusHealing above.
MD.API.Bind({
    SpellCritChance = "GetSpellCritChance",
})

-- T29 (UI/Style.lua's UI.px, docs/SPEC-forever-ui.md 4.3): the physical screen
-- size in pixels (width, height), in the 69893 baseline; UI.px reads the height
-- for pixel-snapped 1-px edges and returns n unchanged when it is not a number.
MD.API.Bind({
    PhysicalScreenSize = "GetPhysicalScreenSize",
})

-- T13 (Modules/SpellTuner_Recorder/Recorder_Forever.lua): the recorder's own
-- bindings, none of which T13b's probe added. UnitGroupRolesAssigned is the
-- same global on every client (Engine/Targets.lua's TBC comment); bound here,
-- rather than in Client/API.lua's shared list, because only this Forever file
-- calls it today. RealZoneText/AuraByIndex/MeterSession/MeterSource are
-- named, not literal Blizzard identifiers, because the dotted target itself
-- (GetRealZoneText, C_UnitAuras.GetAuraDataByIndex, C_DamageMeter's two
-- session readers) says nothing about what the recorder uses it for.
MD.API.Bind({
    UnitGroupRolesAssigned = "UnitGroupRolesAssigned",
    RealZoneText = "GetRealZoneText",
    -- copy = 1: the aura row's own scalar fields only (spellId,
    -- expirationTime, applications, name, ...) -- Facts: readable out of
    -- combat, raises in combat, so this is only ever called while not.
    AuraByIndex = { client = "C_UnitAuras.GetAuraDataByIndex", copy = 1 },
    -- copy = 3: the session table -> its combatSources/combatSpells array ->
    -- each row's own fields (T7's own reasoning for a copying binding).
    MeterSession = { client = "C_DamageMeter.GetCombatSessionFromType", copy = 3 },
    MeterSource = { client = "C_DamageMeter.GetCombatSessionSourceFromType", copy = 3 },
})

-- T9 (UI/SpellTip_Forever.lua): registers the block on every spell tooltip
-- through TooltipDataProcessor.AddTooltipPostCall (docs/tasks/T9-spell-tooltip.md
-- Facts: present on 70009, UNVERIFIED whether it fires for the spellbook,
-- action bars and chat links -- T12 checks). Not a plain Bind() wrapper (the
-- client hands the wrapper a data TABLE, not the arguments MD.API.Call
-- forwards), so the binding is recorded explicitly rather than through Bind's
-- own bookkeeping -- Capabilities() still lists it because
-- MD.API._bindings is the one table it reads.
function MD.API.OnSpellTooltip(fn)
    local spellType = MD.API.Constant("Enum.TooltipDataType.Spell")
    if spellType == nil then return false, "absent" end

    local wrapper = function(tooltip, data)
        -- Under its own pcall: `data` may be secret, or a shape past the
        -- probe's own reach entirely -- indexing it is the one place this
        -- wrapper can raise, and a raise here must never reach the client's
        -- tooltip dispatch.
        local ok, id = pcall(function() return data and data.id end)
        if ok and type(id) == "number" and not MD.API.IsSecret(id) then
            fn(tooltip, id)
        end
    end
    return MD.API.Call("TooltipDataProcessor.AddTooltipPostCall", spellType, wrapper)
end
MD.API._bindings.OnSpellTooltip = "TooltipDataProcessor.AddTooltipPostCall"

-- T18 (Engine/Practice.lua): the bindings-import triad plus the macro/action
-- reads, all present on the 69893 baseline (docs/tasks/T18-practice-forever.md
-- Facts, lead's own apicheck run). GetSpecialization is NOT -- Client/API_TBC.lua
-- binds it alone, so MD.API.Specialization stays nil on this client and every
-- caller's own `MD.API.Specialization and ...` guard already treats that as
-- absent.
MD.API.Bind({
    BindingCount = "GetNumBindings",
    Binding = "GetBinding",
    BindingAction = "GetBindingAction",
    ActionInfo = "GetActionInfo",
    MacroInfo = "GetMacroInfo",
    -- T25: a macro's spell by macro index (69893 baseline).
    MacroSpell = "GetMacroSpell",
})

-- T25 (UI/SpellTip_Forever.lua): the same block on a macro's tooltip
-- (docs/tasks/T25-macro-tooltip.md). Every shape below is the retail 12.x
-- engine's, UNVERIFIED on Forever (T25a's probe lines will confirm); a shape
-- that does not match adds nothing and raises nothing. The spell id is
-- resolved here, in this order, and shared code gets only a plain id:
--   (1) the first data line whose tooltipType is the Spell type and whose
--       tooltipID is a number;
--   (2) T28 (docs/SPEC-forever-ui.md 5.5): the FIRST line's tooltipID,
--       whatever its type -- what ElvUI's own Macro handler reads
--       (`GetTooltipData().lines[1].tooltipID`, no type check);
--   (3) the hovered button's slot (owner.action, else the "action" attribute)
--       -> GetActionInfo: "macro" with a macro index (GetMacroSpell names its
--       spell) or, on newer retail, already the spell id with sub-type "spell".
-- T28: a candidate is handed to `fn(tooltip, id)`, which answers
-- `done, note`: done stops the chain (a block shown, or the block switched
-- off), anything else lets the next step try -- so a first line naming an id
-- that is not a spell still leaves the slot its turn. `note` (a short string)
-- is kept beside the step for /st tooltip why.
-- Each step under its own pcall: the tooltip data, the owner and the client's
-- answers can all be secret or a shape past our reach, and a raise here must
-- never reach the client's tooltip dispatch.
local function PlainNumber(v)
    return type(v) == "number" and not MD.API.IsSecret(v)
end

-- T28: a client value as a short ASCII word for the hover record -- never
-- touching a secret (checked first), a string cut to letters, digits and a
-- few marks (no pipe can survive), anything else named by its type.
local function Desc(v)
    if v == nil then return "nil" end
    if MD.API.IsSecret(v) then return "secret" end
    local t = type(v)
    if t == "number" then
        if v ~= v then return "nan" end
        return tostring(v)
    end
    if t == "string" then
        local s = v:gsub("[^%w _%-%.]", "?")
        if #s > 24 then s = s:sub(1, 24) end
        return s
    end
    return t
end

-- T28: the last macro hover, strings only (docs/SPEC-forever-ui.md 5.5) --
-- which path fired and what each step answered. One record per showing: it
-- is kept on the tooltip until OnTooltipCleared, so a Macro post-call and the
-- SetAction hook of one showing write into the same record.
local lastHover
MD.API.tooltipHooks = MD.API.tooltipHooks or { macro = "not registered", action = "not registered" }

function MD.API.LastMacroHover()
    return lastHover
end

local function HoverRecord(tooltip, path)
    local rec
    if type(tooltip) == "table" then rec = rawget(tooltip, "_stMacroRec") end
    if rec == nil then
        rec = { path = {}, steps = {} }
        if type(tooltip) == "table" and tooltip.HookScript then
            if not rawget(tooltip, "_stMacroHooked") then
                rawset(tooltip, "_stMacroHooked", true)
                -- a hook that cannot be installed must not cost the block
                pcall(tooltip.HookScript, tooltip, "OnTooltipCleared",
                    function(self) rawset(self, "_stMacroRec", nil) end)
            end
            rawset(tooltip, "_stMacroRec", rec)
        end
    end
    rec.path[#rec.path + 1] = path
    lastHover = rec
    return rec
end

local function Step(rec, text)
    rec.steps[#rec.steps + 1] = text
    return #rec.steps
end

-- Hands `id` to fn once per chain; the answer goes beside step i.
-- T37: fn is also told the id came from a macro (docs/SPEC-forever-ui.md
-- 5.5: the block's header then reads "- macro").
local function Offer(fn, tooltip, id, rec, i, tried, source)
    if tried[id] then
        rec.steps[i] = rec.steps[i] .. " -> tried above"
        return false
    end
    tried[id] = true
    local ok, done, note = pcall(fn, tooltip, id, source)
    if not ok then done, note = false, "error" end
    if type(note) ~= "string" then note = done and "done" or "nothing" end
    rec.steps[i] = rec.steps[i] .. " -> " .. Desc(note)
    return done == true
end

-- (1)
local function MacroSpellFromData(data, spellType)
    if data == nil or MD.API.IsSecret(data) then return nil end
    local lines = data.lines
    if type(lines) ~= "table" or MD.API.IsSecret(lines) then return nil end
    for i = 1, #lines do
        local line = lines[i]
        if type(line) == "table" and not MD.API.IsSecret(line) then
            local lineType, lineId = line.tooltipType, line.tooltipID
            if PlainNumber(lineType) and lineType == spellType and PlainNumber(lineId) then
                return lineId
            end
        end
    end
    return nil
end

-- (2) T28: the step's text, and the id when it is a plain number.
local function FirstLine(data)
    if data == nil then return "first line: no data" end
    if MD.API.IsSecret(data) then return "first line: data secret" end
    local lines = data.lines
    if type(lines) ~= "table" or MD.API.IsSecret(lines) then return "first line: none" end
    local line = lines[1]
    if type(line) ~= "table" or MD.API.IsSecret(line) then return "first line: none" end
    local lineType, lineId = line.tooltipType, line.tooltipID
    local text = "first line: type " .. Desc(lineType) .. " id " .. Desc(lineId)
    if PlainNumber(lineId) then return text, lineId end
    return text
end

-- A slot's spell, T25's order: GetActionInfo, then GetMacroSpell for a macro,
-- then a "spell" sub-type's own id. Answers the step's text, the id (plain or
-- nil) and the action's kind.
local function SlotSpell(slot)
    local text = "slot " .. Desc(slot)
    -- three returns; written out, never `a and f() or b`.
    local kind, id, subType = MD.API.ActionInfo(slot)
    if kind == nil then
        local why = (type(id) == "string") and id or "empty"
        return text .. " -> ActionInfo " .. Desc(why)
    end
    if kind ~= "macro" then return text .. " -> " .. Desc(kind) .. " (not a macro)", nil, kind end
    text = text .. " -> macro " .. Desc(id)
    if MD.API.MacroSpell then
        local spellId, why = MD.API.MacroSpell(id)
        if PlainNumber(spellId) then return text .. " -> GetMacroSpell " .. Desc(spellId), spellId, kind end
        if spellId == nil and type(why) == "string" then
            text = text .. " -> GetMacroSpell " .. Desc(why)
        else
            text = text .. " -> GetMacroSpell " .. Desc(spellId)
        end
    end
    if subType == "spell" and PlainNumber(id) then return text .. " -> spell sub-type", id, kind end
    return text, nil, kind
end

-- (3)
local function SlotFromOwner(tooltip)
    if type(tooltip) ~= "table" or not tooltip.GetOwner then return "slot: no owner" end
    local owner = tooltip:GetOwner()
    if owner == nil then return "slot: no owner" end
    if type(owner) ~= "table" or MD.API.IsSecret(owner) then return "slot: owner " .. Desc(owner) end
    local slot = owner.action
    if not PlainNumber(slot) then
        slot = nil
        if owner.GetAttribute then slot = owner:GetAttribute("action") end
    end
    if not PlainNumber(slot) then return "slot: none on owner" end
    return SlotSpell(slot)
end

local function MacroChain(fn, tooltip, data, spellType)
    local rec = HoverRecord(tooltip, "macro post-call")
    local tried = {}

    -- the post-call's own data; the tooltip's only when the client gave none
    if data == nil and type(tooltip) == "table" and tooltip.GetTooltipData then
        local ok, d = pcall(tooltip.GetTooltipData, tooltip)
        if ok and d ~= nil then
            data = d
            Step(rec, "data: from GetTooltipData")
        end
    end

    local ok, found = pcall(MacroSpellFromData, data, spellType)
    local i
    if not ok then
        Step(rec, "spell line: raised")
    elseif PlainNumber(found) then
        i = Step(rec, "spell line: " .. Desc(found))
        if Offer(fn, tooltip, found, rec, i, tried, "macro") then return end
    else
        Step(rec, "spell line: none")
    end

    local text, id
    ok, text, id = pcall(FirstLine, data)
    if not ok then
        Step(rec, "first line: raised")
    else
        i = Step(rec, text)
        if PlainNumber(id) and Offer(fn, tooltip, id, rec, i, tried, "macro") then return end
    end

    ok, text, id = pcall(SlotFromOwner, tooltip)
    if not ok then
        Step(rec, "slot: owner raised")
    else
        i = Step(rec, text)
        if PlainNumber(id) then Offer(fn, tooltip, id, rec, i, tried, "macro") end
    end
end

function MD.API.OnMacroTooltip(fn)
    local macroType = MD.API.Constant("Enum.TooltipDataType.Macro")
    if macroType == nil then
        MD.API.tooltipHooks.macro = "absent"
        return false, "absent"
    end
    local spellType = MD.API.Constant("Enum.TooltipDataType.Spell")

    local wrapper = function(tooltip, data)
        pcall(MacroChain, fn, tooltip, data, spellType)
    end
    local r1, why, detail = MD.API.Call("TooltipDataProcessor.AddTooltipPostCall", macroType, wrapper)
    MD.API.tooltipHooks.macro = (type(why) == "string") and why or "on"
    return r1, why, detail
end
MD.API._bindings.OnMacroTooltip = "TooltipDataProcessor.AddTooltipPostCall"

-- T28 (docs/SPEC-forever-ui.md 5.5): a third path. Every Blizzard and
-- LibActionButton bar calls GameTooltip:SetAction(slot) whatever data type
-- the client then assigns, so the hook reads the SLOT IT IS HANDED -- no
-- owner lookup -- and resolves it in T25's order (SlotSpell). It records
-- only a macro's hover, or a showing a Macro post-call already recorded, so
-- hovering a plain spell button never overwrites the last macro hover. The
-- once-per-showing guard is fn's own (UI/SpellTip_Forever.lua's OnSpell,
-- the same fn every path hands its id to), so a showing that also fired the
-- Macro or Spell post-call gets the block once. hooksecurefunc cannot be
-- undone, so this installs once.
local function ActionHook(fn, tooltip, slot)
    local rec = (type(tooltip) == "table") and rawget(tooltip, "_stMacroRec") or nil
    if not PlainNumber(slot) then
        if rec then
            HoverRecord(tooltip, "SetAction hook")
            Step(rec, "SetAction slot " .. Desc(slot))
        end
        return
    end
    local text, id, kind = SlotSpell(slot)
    if kind ~= "macro" and rec == nil then return end
    rec = HoverRecord(tooltip, "SetAction hook")
    local i = Step(rec, "SetAction " .. text)
    -- T37: a macro's slot marks the block; a plain spell button's does not
    local source
    if kind == "macro" then source = "macro" end
    if PlainNumber(id) then Offer(fn, tooltip, id, rec, i, {}, source) end
end

function MD.API.OnActionTooltip(fn)
    if MD.API._actionHooked then return true end
    if type(MD.API.Has("GameTooltip.SetAction")) ~= "function" then
        MD.API.tooltipHooks.action = "absent"
        return false, "absent"
    end
    local hook = function(tooltip, slot)
        pcall(ActionHook, fn, tooltip, slot)
    end
    local _, why, detail = MD.API.Call("hooksecurefunc", rawget(_G, "GameTooltip"), "SetAction", hook)
    if type(why) == "string" then
        MD.API.tooltipHooks.action = why
        return false, why, detail
    end
    MD.API._actionHooked = true
    MD.API.tooltipHooks.action = "on"
    return true
end
MD.API._bindings.OnActionTooltip = "GameTooltip.SetAction"

-- T37 (UI/SpellTip_Forever.lua, docs/SPEC-forever-ui.md 5.6): the detail
-- key's refresh -- tooltip:RefreshData(), which clears the tooltip and runs
-- its post-calls again. Retail's method; UNVERIFIED on Forever that it re-runs
-- the post-calls (if it does not, the detail lines show on the next hover,
-- as before). Guarded: a tooltip without it answers absent, a raise error;
-- neither reaches the caller.
function MD.API.RefreshTooltip(tooltip)
    local ok, fn = pcall(function() return type(tooltip) == "table" and tooltip.RefreshData end)
    if not ok then return nil, "error" end
    if type(fn) ~= "function" then return nil, "absent" end
    if not pcall(fn, tooltip) then return nil, "error" end
    return true
end
MD.API._bindings.RefreshTooltip = "GameTooltip.RefreshData"
