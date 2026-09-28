-- apicheck.py selftest fixture only (T13c): a plain module bootstrap file,
-- no client call, no new global -- contributes zero findings.
local _, ns = ...
if type(_G.SpellTuner) == "table" then
    setmetatable(ns, { __index = _G.SpellTuner, __newindex = _G.SpellTuner })
end
