# T125: What if as a drawer on the window's right edge

Author's request (2026-10-04): "can we make 'what if' as a side panel? so that it
does not eat much vertical space, and when we have lots of ranks we can still see
all of them while manipulating with the stats". Ruling: mockup **M2** in
`docs/mockups/whatif-side.html` (commit e5669ea).

## What changes

1. The WHAT IF titled pane (T122; `BuildWhatIf` / `PaintWhatIf` in
   `UI/SpellsPane.lua`) no longer sits between the decision strip and RANKS.
   RANKS (and the card) move up to where they were before T122; the spell view's
   vertical layout is the same whether What if is open or closed.
2. What if is a **drawer**: a 220 x window-height panel, a child of the main
   window, anchored outside its right edge (TOPLEFT to the window's TOPRIGHT, small
   gap per the mockup). Same STATS rows, steppers, changes summary and Reset as
   today, stacked vertically for a 220 px column; it must fit at font offset +2
   without clipping (measure; the mockup says no scroll needed).
3. Opening and closing: the strip's existing "What if..." button toggles it
   (`SpellsPane.whatIfOpen`, per session, unchanged). The drawer shows only while
   the Spells view of one spell is showing; switching to another group/view hides
   it and returning restores it if `whatIfOpen`. Closing the window hides it. A
   close (x) on the drawer itself closes What if the same as the button.
4. **ESC**: the drawer joins `MD.EscStack` (`Push` when shown, `Remove` when
   hidden), so the first ESC closes the drawer, the next the window. With
   `db.ui.escStack = false`, ESC behaviour falls back as other tools do.
5. **Screen edge**: if the window's right edge plus the drawer would leave the
   screen (UIParent right), anchor the drawer to the window's LEFT edge instead.
   Re-evaluate on show and after the window is moved/scaled (`MD.Win` scale).
6. **Combat**: the drawer hides with the window (MD.Win combat hide) and comes
   back with it.
7. The What if lens itself (Spells/WhatIf.lua, the what-if book, RANKS marks and
   tooltips, the strip comparison) is unchanged. Both lines (shared file).

## Rules

Paint only through tokens / `UI.Tint`; pitches through `UI.Pitch`; ASCII only, no
bare `|`; `"BackdropTemplate"` on any styled frame; no `UI.STYLE` branch; no
`MD.API.client` branch. Restyle (`STYLE_CHANGED`) must repaint the drawer.

## Tests

`tools/spellsui.lua` (both flavours) and `tools/whatifcheck.lua` as needed:
drawer hidden by default; button opens it and RANKS top y is unchanged by opening;
ESC closes it first; flips to the left when the window's right edge is near the
screen's; hidden when the view changes and restored on return; geometry fits at
offsets -2..+2 (`S.Geometry(true)`). Update `tools/data/expected-counts.json`.
`themecheck`, `restylecheck`, `wincheck`, apicheck 0, textcheck 0.

## Docs

`CHANGELOG.md` line under `## 0.17.1`; `docs/TESTING.md` §50 note for the drawer
(open, ESC, near screen edge, combat).
