-- tools/modulecheck.lua fixture only (T13c) -- not part of any real module
-- or release build. Identical in shape to the real Modules/<Name>/Module.lua.
local _, ns = ...
if type(_G.SpellTuner) == "table" then
    setmetatable(ns, { __index = _G.SpellTuner, __newindex = _G.SpellTuner })
end
