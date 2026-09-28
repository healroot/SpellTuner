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
