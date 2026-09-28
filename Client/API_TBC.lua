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
