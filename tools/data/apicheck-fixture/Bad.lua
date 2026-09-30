local r1 = GetSpellInfo
os.time()
local r3 = UnitHealth("player")
NewGlobalName = 1
local r5 = "COMBAT_LOG_EVENT_UNFILTERED"
local r6 = "C_Spell.NoSuchMember"
local ok1 = wipe
local ok2 = CreateFrame
local ok3 = SlashCmdList
local ok4 = SpellTunerDB
-- T57 (rule 9): a raw frame registering an event, outside Client/ and Core.lua; the mention of RegisterEvent( in this comment is not one.
CreateFrame("Frame"):RegisterEvent("PLAYER_REGEN_DISABLED")
