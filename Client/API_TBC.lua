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
