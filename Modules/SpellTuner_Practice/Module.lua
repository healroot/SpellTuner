-- SpellTuner module bootstrap (T13c of docs/tasks/T13c-module-plumbing.md):
-- a LoadOnDemand addon's files each receive this sibling's OWN fresh table as
-- the second vararg -- never MD -- so a shared file listed below that starts
-- `local _, MD = ...` would otherwise see an empty table instead of
-- SpellTuner's namespace. Wiring this table's __index/__newindex onto
-- _G.SpellTuner makes every read and write on it land on SpellTuner's MD
-- instead: Core.lua never compares `self ==` or does `pairs(MD)` (checked),
-- so a proxy is safe for every core method called with `:`. Guarded (should
-- be impossible -- every sibling depends on SpellTuner) rather than assuming
-- SpellTuner loaded first. No longer calls ModuleLoaded: that now happens in
-- Ready.lua, the LAST file this TOC lists, once every shared file above has
-- actually run under MD == SpellTuner.
local _, ns = ...
if type(_G.SpellTuner) == "table" then
    setmetatable(ns, { __index = _G.SpellTuner, __newindex = _G.SpellTuner })
end
