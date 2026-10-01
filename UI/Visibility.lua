-- T68 (P24 of docs/PLAN-refactor-ux.md, review A29): the one rule for when a
-- mana clock is on screen, shared by the TBC widget (UI/Widget.lua
-- MD:UpdateVisibility) and the Forever clock (UI/Clock_Forever.lua), which
-- until T68 each carried a copy of the 90/95 hysteresis.
--
-- PURE: no frame, no client call, no clock -- every input is an argument, so
-- both lines ask the same question and a suite can ask it with no widget.
-- Each widget keeps its own single owner of Show/Hide (CLAUDE.md "widget
-- visibility has one owner per line"); this only answers "should it be shown".
--
-- T93 (docs/SPEC-next.md 7.3 "When", F3): the answer follows a show RULE.
-- With no rule, or the default one, it is exactly the rule above (held by
-- tools/clockfacecheck.lua section 5 against the parent's Want, case by case).
local _, MD = ...

MD.Visibility = MD.Visibility or {}
local Visibility = MD.Visibility

-- Out of combat the clock appears once mana falls BELOW 90% of max and, once
-- shown, stays until mana is ABOVE 95% -- a band, so it never flickers where
-- a single threshold would redraw at 94.x% (T11b, the author's "~refill 0:05"
-- sighting).
Visibility.SHOW_BELOW = 0.90
Visibility.HIDE_ABOVE = 0.95

-- The rule (T93):
--   combat         "always" | "never"           in combat
--   ooc            "low" | "always" | "never"   out of combat; "low" is the band
--   showBelow      the band's lower edge        (nil: SHOW_BELOW)
--   hideAbove      the band's upper edge        (nil: HIDE_ABOVE)
--   manaUsersOnly  true: a character with no mana pool gets no clock, in
--                  combat included (F3: a Forever warrior saw "~OOM ..." in
--                  every fight); the TBC widget's own gate, moved here
-- A field the rule leaves out is the default's.
Visibility.DEFAULT_RULE = { combat = "always", ooc = "low", manaUsersOnly = true }

local DEFAULT = Visibility.DEFAULT_RULE

local function Field(rule, key)
    local v = rule[key]
    if v == nil then v = DEFAULT[key] end
    return v
end

-- pct       mana / max as a plain number, or nil when there is nothing to
--           compare (no max yet): nil reads as "not low", so hidden.
-- shown     whether the widget is shown now (the band's memory).
-- inCombat  in combat the clock is wanted (rule.combat "always").
-- unlocked  being dragged or previewed: always wanted, whatever the mana,
--           the class or the rule.
-- rule      the show rule above; nil is the default.
-- usesMana  whether the character has a mana pool (MD.player.usesMana);
--           only `false` hides under manaUsersOnly -- nil (not known) does not.
function Visibility.Want(pct, shown, inCombat, unlocked, rule, usesMana)
    if unlocked then return true end
    if type(rule) ~= "table" then rule = DEFAULT end
    if usesMana == false and Field(rule, "manaUsersOnly") ~= false then return false end
    if inCombat then return Field(rule, "combat") ~= "never" end
    local ooc = Field(rule, "ooc")
    if ooc == "always" then return true end
    if ooc == "never" then return false end
    if type(pct) ~= "number" then return false end
    if shown then return pct <= (rule.hideAbove or Visibility.HIDE_ABOVE) end
    return pct < (rule.showBelow or Visibility.SHOW_BELOW)
end
