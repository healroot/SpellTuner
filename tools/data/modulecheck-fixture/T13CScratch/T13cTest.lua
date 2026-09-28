-- tools/modulecheck.lua fixture only (T13c): the shape the task's acceptance
-- text names, minus the stray "t13c" id argument -- this codebase's
-- MD:RegisterCallback(name, fn) (Core.lua:48) takes no handler-id argument
-- (that 3-arg convention is Cell's, a different addon); passing one here
-- drops the real callback function and calling it raises.
local _, MD = ...
MD.T13cProbe = MD.API.client
MD:RegisterCallback("T13C", function() MD.T13cFired = true end)
