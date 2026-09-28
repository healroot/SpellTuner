-- The handshake, last (T13c of docs/tasks/T13c-module-plumbing.md): by the
-- time this file runs, every shared file this module's TOC lists above it
-- has already run with MD == SpellTuner's own namespace (Module.lua, first
-- in the TOC, wired that up), so MODULE_LOADED now means "loaded AND ready"
-- rather than merely "the bootstrap file ran".
local name = ...
if _G.SpellTuner and _G.SpellTuner.ModuleLoaded then
    _G.SpellTuner:ModuleLoaded(name)
end
