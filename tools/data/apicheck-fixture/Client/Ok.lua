-- A client call inside Client/, and a real C_ member string -- no finding.
local a = UnitHealth
local b = C_Timer
local c = "C_Timer.After"
-- T57 (rule 9): Client/ registers events on its own frames -- no finding.
CreateFrame("Frame"):RegisterEvent("ADDON_LOADED")
