-- tools/apicheck.py --selftest only (T97, rule 11): a host addon's global read.
-- The selftest scans this file twice: as apicheck-fixture-foreign.lua (outside
-- Integrations/: one finding, line 6) and as Integrations/apicheck-fixture-foreign.lua
-- (the one folder where a host addon may be reached: no finding). The mention of
-- EllesmereUI in these comments is not a read.
local host = EllesmereUI
local ok = type(host) == "table"
