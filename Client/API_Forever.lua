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
})
