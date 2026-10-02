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

-- T95 (Spells/Book.lua, docs/SPEC-next.md 4.2 P1): a spell's base cooldown,
-- GetSpellBaseCooldown(id) -> cooldown ms, global cooldown ms (in the 69893
-- baseline; retail's shape, UNVERIFIED on Forever). Bound, but Book reads it
-- only while MD.API.BASE_CD_READS is true -- false until T87's probe report
-- from a Forever client shows `== cooldowns` answering it plain (the
-- BAR_READS_MAX pattern, Client/API.lua; the integrator flips it). Until then
-- the cooldown is the tooltip line's right text ("10 sec cooldown",
-- Parse.Cooldown).
MD.API.Bind({
    BaseCooldown = "GetSpellBaseCooldown",
})
MD.API.BASE_CD_READS = false

-- T114 (docs/tasks/T114-clock-face-slots.md; mockup clock-v2 C1, probe
-- Q-clock-2): the player's mana as TEXT -- the clock's Mana % / Mana slots
-- drawn from the client rather than the model. UnitPower is secret always on
-- this client; whether a font string shows a secret handed to SetText is
-- Q-clock-2's question (`fs:SetText(UnitPowerPercent("player", 0))` shows a
-- number). Until a Forever probe report answers it, POWER_TEXT_READS stays
-- false and the slots draw the model's "~" values (the BAR_READS_MAX pattern,
-- Client/API.lua; the integrator flips it). How a real percent is worded
-- (0..1 or 0..100) is that report's question too.
--   kind "pct"  -> UnitPowerPercent(unit, powerType)
--   kind "mana" -> UnitPower(unit, powerType)
-- The value goes straight into fs:SetText -- never read, compared,
-- concatenated or formatted: the sanctioned path for a secret into a font
-- string, as DrawUnitPower is for a status bar. Answers true; nil, "secret"
-- while the flag is false (nothing touched: no client function called, no
-- font string written); nil, "absent" without the function or the font
-- string; nil, "error" for an unknown kind or a raise. Nothing calls it yet
-- (T116's renderer asks the Forever line's draw.powerText for it). Recorded
-- explicitly, as OnSpellTooltip: it is not a Bind() wrapper.
MD.API.POWER_TEXT_READS = false

local POWER_TEXT = { pct = "UnitPowerPercent", mana = "UnitPower" }

function MD.API.DrawPowerText(fs, unit, powerType, kind)
    if MD.API.POWER_TEXT_READS ~= true then return nil, "secret" end
    local name = POWER_TEXT[kind]
    if not name then return nil, "error" end
    if type(fs) ~= "table" then return nil, "absent" end
    local fn = MD.API.Has(name)
    if type(fn) ~= "function" then return nil, "absent" end
    local ok = pcall(function()
        fs:SetText(fn(unit, powerType)) -- never inspected: a secret goes straight in
    end)
    if not ok then return nil, "error" end
    return true
end
MD.API._bindings.DrawPowerText = "UnitPowerPercent"

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

-- T36 (UI/SpellsPane_Forever.lua, docs/SPEC-forever-ui.md 3.2): what the
-- cursor holds, for a spell dragged from the spellbook onto the Spells rail.
-- GetCursorInfo is in the 69893 baseline; its shape for a spell is retail's
-- ("spell", book slot, book type, spell id), UNVERIFIED on Forever. Answers
-- `kind, spellId`: the kind only when it is a plain string, the id only for a
-- "spell" whose fourth return is a plain number; anything secret, absent or
-- raising answers nil (a drop then does nothing, and the picker still works).
-- Read only: nothing here, and nothing that calls it, clears the cursor.
function MD.API.CursorInfo()
    local kind, _, _, id = MD.API.Call("GetCursorInfo")
    if type(kind) ~= "string" or MD.API.IsSecret(kind) then return nil end
    if kind == "spell" and type(id) == "number" and not MD.API.IsSecret(id) then
        return kind, id
    end
    return kind, nil
end
MD.API._bindings.CursorInfo = "GetCursorInfo"

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
--       -> GetActionInfo: "macro" with sub-type "spell" and the spell id
--       itself (build 70124, T85: taken as it is), or with sub-type "" and a
--       macro index (a text macro; GetMacroSpell names its spell, if any).
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

-- A slot's spell: GetActionInfo, then, for a macro, by its sub-type. T85
-- (docs/probe/1.60.1_70124.md, "What it settles"): build 70124 answers a
-- macro that casts a spell as ("macro", <SPELL ID>, "spell") -- the id IS the
-- spell, and GetMacroSpell, which takes a macro index, names nothing for it
-- (or, for a low id that is also a live macro index, another macro's spell)
-- -- and a text-only macro as ("macro", <macro index>, ""), the one shape
-- GetMacroSpell is asked about. Answers the step's text, the id (plain or
-- nil) and the action's kind. ActionInfo goes through MD.API.Call, so every
-- return here is plain (a secret one makes kind nil).
local function SlotSpell(slot)
    local text = "slot " .. Desc(slot)
    -- three returns; written out, never `a and f() or b`.
    local kind, id, subType = MD.API.ActionInfo(slot)
    if kind == nil then
        local why = (type(id) == "string") and id or "empty"
        return text .. " -> ActionInfo " .. Desc(why)
    end
    if kind ~= "macro" then return text .. " -> " .. Desc(kind) .. " (not a macro)", nil, kind end
    if subType == "spell" then
        text = text .. " -> macro spell " .. Desc(id)
        if PlainNumber(id) then return text, id, kind end
        return text, nil, kind
    end
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

-- T38 (UI/SpellsPane_Forever.lua, docs/SPEC-forever-ui.md 3.5): the game's
-- own spell tooltip for one rank, for a row hover in a spell's view --
-- tooltip:SetSpellByID(id), retail's method; the Spell post-call above then
-- appends the SpellTuner block, so the pane and the action bar read the same.
-- UNVERIFIED on Forever that the post-call fires for SetSpellByID: the caller
-- checks the tooltip's own guard and adds the block itself when it did not.
-- Answers true, or nil plus "absent" (no method, or an id that is not a plain
-- number) / "error" (the method raised); nothing reaches the caller.
function MD.API.SetTooltipSpell(tooltip, id)
    if type(id) ~= "number" or MD.API.IsSecret(id) then return nil, "absent" end
    local ok, fn = pcall(function() return type(tooltip) == "table" and tooltip.SetSpellByID end)
    if not ok then return nil, "error" end
    if type(fn) ~= "function" then return nil, "absent" end
    if not pcall(fn, tooltip, id) then return nil, "error" end
    return true
end
MD.API._bindings.SetTooltipSpell = "GameTooltip.SetSpellByID"
