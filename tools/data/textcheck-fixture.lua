-- tools/data/textcheck-fixture.lua: read by `python3 tools/textcheck.py --selftest` (T47) only.
-- A comment may carry an em dash — it never reaches the screen, so it is not a finding.
local t = {}
print("first run — the widget is unlocked")
t.close = "×"
t.escaped = "\226\128\148"
print("plain ASCII, a || doubled pipe and an escaped \\226 that is only a backslash")
if t.x == "é" then print("never") end
local long = [[a long string – too]]
return t, long
