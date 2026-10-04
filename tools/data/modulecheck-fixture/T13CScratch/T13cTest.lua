-- tools/modulecheck.lua fixture only (T13c): the shape the task's acceptance
-- text names, minus the stray "t13c" id argument -- this codebase's
-- ST:RegisterCallback(name, fn) (Core.lua:48) takes no handler-id argument
-- (that 3-arg convention is Cell's, a different addon); passing one here
-- drops the real callback function and calling it raises.
local _, ST = ...
ST.T13cProbe = ST.API.client
ST:RegisterCallback("T13C", function() ST.T13cFired = true end)
