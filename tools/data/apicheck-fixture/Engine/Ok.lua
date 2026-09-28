-- apicheck.py selftest fixture only (T13c): a root file the Sample module
-- TOC lists as "Engine\Ok.lua" -- it does not exist under Modules/Sample/, so
-- it must resolve at the fixture's own root and be scanned from there, with
-- zero findings of its own (pure Lua, no client call, no new global).
local _, MD = ...
local x = 1
