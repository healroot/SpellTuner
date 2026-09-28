-- tools/modulecheck.lua fixture only (T13c) -- not part of any real module
-- or release build. Identical in shape to the real Modules/<Name>/Ready.lua.
local name = ...
if _G.SpellTuner and _G.SpellTuner.ModuleLoaded then
    _G.SpellTuner:ModuleLoaded(name)
end
