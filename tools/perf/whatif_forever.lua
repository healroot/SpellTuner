-- tools/run.sh tools/perf/whatif_forever.lua -- not a suite (make check skips tools/perf/).
-- The author's 2026-11-16 in-game report: a What if change cost up to 50 ms and
-- 1.4 MB in the Spells pane, and a soft-marked book read 40 ms. This drives the
-- same path offline under /st perf: the Spells pane on a family, the talent
-- planner open, talent changes through the What if, a hover, an aura soft mark
-- and a tooltip -- then prints the profiler's report.
HARNESS_FLAVOUR = "forever"
HARNESS_SLICED_BOOK = true -- as in game: a read with a book kept is sliced
local here = (arg[0]:match("^(.*)/[^/]+$"):gsub("/perf$", ""))
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB
local WI, Book = ST.WhatIf, ST.Book
ST.Print = function() end

S.level, ST.player.level = 26, 26
S.AddTraits({ ["Nature's Focus"] = 5, ["Naturalist"] = 5, ["Gift of Nature"] = 2 })
S.Fire("PLAYER_TALENT_UPDATE")
Book:MarkDirty(); Book:Get()

ST:ToggleDashboard()
ST:SelectView("spells", "fam:HealingTouch")
local win = CreateFrame("Frame", nil, UIParent); win:SetSize(860, 560); win:Show()
local sheet = ST.TalentPlanner and ST.TalentPlanner.Open(win)
S.Tick(0.1)

ST.Perf.Command("on")
local names = { "Naturalist", "Gift of Nature", "Tranquil Spirit", "Improved Rejuvenation", "Nature's Focus" }
local m0 = collectgarbage("count")
for i = 1, 5 do
    WI:Set("talent:" .. names[i], 1)
    S.Tick(0.05)
end
local kbWhatIf = collectgarbage("count") - m0
-- an aura out of combat, then a spell tooltip
S.Fire("UNIT_AURA", "player")
if ST.SpellTip and ST.SpellTip.OnSpell then
    local tt = GameTooltip
    for _ = 1, 3 do
        if tt.ClearLines then tt:ClearLines() end
        ST.SpellTip.OnSpell(tt, 5185, "spell")
        S.Fire("UNIT_AURA", "player")
        S.Tick(0.05)
    end
end
for _ = 1, 40 do S.Tick(0.016) end
print(string.format("what-if changes: %.0f KB for 5 (heap delta); full reads %d, family reads %d, last read %s slices", kbWhatIf, Book.scans or 0, Book.familyRefreshes or 0, tostring(Book.lastScanSlices)))
print(ST.Perf.Report())
