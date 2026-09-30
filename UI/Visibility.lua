-- T68 (P24 of docs/PLAN-refactor-ux.md, review A29): the one rule for when a
-- mana clock is on screen, shared by the TBC widget (UI/Widget.lua
-- MD:UpdateVisibility) and the Forever clock (UI/Clock_Forever.lua), which
-- until T68 each carried a copy of the 90/95 hysteresis.
--
-- PURE: no frame, no client call, no clock -- every input is an argument, so
-- both lines ask the same question and a suite can ask it with no widget.
-- Each widget keeps its own single owner of Show/Hide (CLAUDE.md "widget
-- visibility has one owner per line"); this only answers "should it be shown".
local _, MD = ...

MD.Visibility = MD.Visibility or {}
local Visibility = MD.Visibility

-- Out of combat the clock appears once mana falls BELOW 90% of max and, once
-- shown, stays until mana is ABOVE 95% -- a band, so it never flickers where
-- a single threshold would redraw at 94.x% (T11b, the author's "~refill 0:05"
-- sighting).
Visibility.SHOW_BELOW = 0.90
Visibility.HIDE_ABOVE = 0.95

-- pct       mana / max as a plain number, or nil when there is nothing to
--           compare (no max yet): nil reads as "not low", so hidden.
-- shown     whether the widget is shown now (the band's memory).
-- inCombat  in combat the clock is always wanted.
-- unlocked  being dragged or previewed: always wanted, whatever the mana.
function Visibility.Want(pct, shown, inCombat, unlocked)
    if unlocked then return true end
    if inCombat then return true end
    if type(pct) ~= "number" then return false end
    if shown then return pct <= Visibility.HIDE_ABOVE end
    return pct < Visibility.SHOW_BELOW
end
