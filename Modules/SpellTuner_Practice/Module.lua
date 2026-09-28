-- SpellTuner module stub (T2 of docs/ROADMAP-FOREVER.md): nothing but the
-- handshake that tells the core this sibling addon loaded. No frame, no
-- event, no global -- a module that is off must cost nothing, and this is
-- the only thing that runs even when it is on, until M4 fills it in.
local name = ...
if _G.SpellTuner and _G.SpellTuner.ModuleLoaded then
    _G.SpellTuner:ModuleLoaded(name)
end
