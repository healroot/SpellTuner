# T125 review: What if as a drawer (commit 8652065 vs 8d1861e)

Reviewer: independent adversarial review (Opus 5.5), 2026-10-04.
Contract: `docs/tasks/T125-whatif-drawer.md`, CLAUDE.md conventions.

**Verdict: pass with minors, plus 1 major.** No blockers, 1 major, 5 minors.

What I checked and ran: `spellsui` (tbc 22/22, forever 59/59), `whatifcheck`, `themecheck`,
`restylecheck`, `wincheck` (both flavours, all green), apicheck 0, textcheck 0. I also ran a scratch
probe (not committed) of close/reopen, `Win:EnterCombat` / `LeaveCombat` and `Win:SetEscStack`
with the drawer open.

## Sound (checked, no finding)

- **Hide with the window, combat, takeover:** the drawer is a child of `nav.frame`, so it hides
  with the window in every case: ESC, the x, the combat hide and a replay takeover. The hooks on
  `f` / `host` OnHide (`UI/SpellsPane.lua:1705-1706`) also clear its shown flag. When the window
  shows again, both windows' OnShow scripts (`UI/Dashboard.lua` OnShow, `UI/Dashboard_Forever.lua:561`)
  call `nav:Select(uiPath)`, which always runs onShow, then `RenderFamily` and `SyncWhatIf`, and the
  drawer comes back at once. `LeaveCombat` goes through `ShowMain`, so it takes the same path.
- **ESC order, stack on:** the push waits one frame (`MD.API.After(0)`, line 1396-1403), so the
  drawer lands above the window's entry whichever OnShow fires first. `Esc:Push`'s OnHide hook takes
  the entry off on every hide. `onEsc` goes through `CloseWhatIf`, so `whatIfOpen` and the
  drawer stay in step. I found no path that leaves the drawer shown while `whatIfOpen` is false.
- **The 2 s tick (line 1753):** it runs only while `f:IsVisible()`. It cannot bring the drawer
  back after the window is closed, another group or the Overview is selected, or a takeover runs.
  It cannot undo an x or ESC close either, because those clear `whatIfOpen`.
- **OnUpdate:** it runs only while the drawer is visible, so it never runs hidden, and it leaks
  nothing (see m4 for its cost).
- **Strata and level:** the drawer is built after `Win:Register`, so it inherits HIGH at the
  window's level + 1. Clicks raise the toplevel window.
- **Restyle:** `StylizeFrame(d, P.frame, P.border)` and `UI.Skin(header, "header", ...)` resolve to
  names and register in `UI.skinned`. Every font string uses `UI.Tint`. `StyleChanged`, then
  `Show(view)`, then `RenderFamily` repaints the drawer, and `PixelLayout` is re-snapped by
  `RestylePixels`. Both frames use `"BackdropTemplate"`. Text is ASCII with no bare `|`. The code
  has no `UI.STYLE` or `MD.API.client` branch.
- **Clamp at the top:** the drawer's header sits at the same y as the window's header. The window is
  clamped with a 20 px top inset, so the drawer's x is never off the top.
- **Alt+Z:** the drawer hides with UIParent. See m1 for how it comes back.

## Findings

### M1 (major) `UI/SpellsPane.lua:1306`: the drawer is placed off-screen when neither side fits

**Fixed in 4b02936**: right when it fits, else left when it fits, else the side with more room; `d:SetClampedToScreen(true)`. Test T125-5 (UIParent about 910 wide).

**Defect.** `PlaceDrawer` tests only the right side. When the right side fails it anchors left
without checking that the left side fits. The drawer is not clamped (`SetClampedToScreen` is never
set on it), and the window's clamp covers only the window's own rect.

**Failure scenario.** `Win:Place` centres the window by default. A centred 860-wide window leaves
`(sw - 860*s) / 2` on each side, and the drawer needs `222*s`. So any UIParent narrower than
`1304*s` units fails both sides, where `s` is the window scale:
- UIParent 768 tall on a 16:10 screen (1229 wide) at 100 %: each side has 184 and the drawer
  needs 222.
- The same height on a 16:9 screen (1365 wide) at a window scale of 110 % or more.
- Any 4:3 or 5:4 screen.

In these cases the drawer opens on the left with 38 to 100 units past the screen's left edge. The
pane's border, the STATS labels and the boxes' left halves are cut off. Dragging the window to one
side works around it only when `sw >= 1082*s`.

**Fix.** Pick the side with more room when neither fits. Also call `d:SetClampedToScreen(true)`, so
the client pushes the drawer back on-screen over the window's edge instead of off it. A further
option is to nudge the window inward by the shortfall through `MD.Win`.

### m1 (minor) `UI/SpellsPane.lua:1705-1706`, `:1753`: Alt+Z costs the drawer up to 2 s

**Fixed in 4b02936**: both hooks hide the drawer only when the view itself is not shown or the window is still visible (a hide inside the window); the `drawerDown` clause is gone. Test T125-6 (Alt+Z by hand, as the stub fires no child OnHide).

**Defect.** The OnHide hooks on `f` and `host` hide the drawer on any ancestor hide. That includes
UIParent under Alt+Z and the window itself, where the drawer would follow its parent anyway.

**Failure scenario.** Alt+Z with the drawer open, then Alt+Z again: the window comes back
immediately, but the drawer stays missing until the next 2 s tick re-renders the whole family view.
For the same reason, the first ESC in that gap closes the window, not the drawer.

**Fix.** In both hooks, hide the drawer only when the view itself was hidden:
`if not self:IsShown() then ... end`. When an ancestor hides, `self:IsShown()` is still true, as
`Esc:Push`'s own hook already assumes. The `drawerDown` clause in the tick can then go.

### m2 (minor) `UI/Windows.lua:583` with `UI/EscStack.lua:240`: turning the ESC stack back on skips the drawer

**Fixed in 4b02936**: `Esc:Companion(frame, onEsc)` (`Win:Companion`); `Esc:Set(true, ...)` pushes every companion on screen after the windows. Test T125-7 (off: drawer shown, no entry, not in UISpecialFrames; on: drawer above the window, first ESC closes it).

**Defect.** `Win:SetEscStack(true)` re-pushes only the registered windows. The drawer is not a
registered window. With the stack off, the unnamed drawer never enters `UISpecialFrames`, which is
an acceptable fallback, since ESC closes the window and the drawer goes with it.

**Failure scenario.** Open the drawer, then Settings: escStack off, then back on. Returning to the
spell is fine, because the drawer is re-shown and re-pushed. But if the stack is toggled with
`/st` while the drawer is on screen, the stack holds only the window, and the first ESC closes the
window instead of the drawer. The probe confirmed this: after off and on, n=1 and the top entry is
not the drawer.

**Fix.** Push the drawer again on the toggle. Either `SpellsPane` listens for the change, or
`SetEscStack` takes extra frames that are shown. The cheapest option is a `Win` hook that lets a
pane add `{ frame, onEsc }` to `shown`. Add a suite case for escStack=false and for turning it
back on, which the brief asks for.

### m3 (minor) `UI/EscStack.lua:228` (`TopWindow`): copy boxes centre on the drawer

**Fixed in 4b02936**: `TopWindow` skips companions. Test T125-6.

**Defect.** The drawer is a non-list stack entry above the window, so `Win:TopWindow` returns it.

**Failure scenario.** With the drawer open, run `/md profile`, `/md export` or the debug log's
Copy. `MD:ShowCopyPopup` (`UI/DebugConsole.lua:176`) centres the large copy frame on the 220-wide
drawer, which sits outside the window's edge. The copy frame lands off-centre and can run past the
screen edge when the drawer is on the right near the screen's right.

**Fix.** Mark the drawer (for example `d.escAux = true`) and have `TopWindow` skip such entries.
Alternatively, push the drawer with a flag that `TopWindow` ignores.

### m4 (minor) `UI/SpellsPane.lua:1406-1418`: the drawer polls the window five times a second

**Fixed in 4b02936**: six numbers (window left, width, height, scale; UIParent right, scale) compared against fields on the drawer; no table or strings. Hooks not used (SetHeight kept, height now in the compare).

**Defect.** Every 0.2 s while the drawer is shown, the OnUpdate builds a table, five `tostring`
strings and a concat, just to notice a move or a scale change. That is small but steady garbage
on a panel that may stay open for a long time. It also leaves out the window's height, which is
harmless today because the Spells group is a fixed 860x560.

**Fix.** Compare the five numbers directly against fields stored on `d`. Better, re-place on the
window's `OnMoved` hook (end of drag), `Win:SetScale` and `UI_SCALE_CHANGED` / `DISPLAY_SIZE_CHANGED`,
and anchor TOP and BOTTOM to the window so the height never needs setting.

### m5 (minor) `tools/spellsui.lua:792-831`, T125 forever: the geometry test cannot catch wrapping or a wide delta

**Fixed in 4b02936**: the stub wraps a `SetWordWrap(true)` string with a width by words under geometry (`S.WrappedLines`); T125-1 hands each string its font object, uses a long footer (4-6 lines) and checks label, unit and delta widths; a Forever -2..+2 case with the class note (2-3 lines) and footer measured through `S.WrappedLines`.

**Defect.** Under `S.Geometry(true)`, the stub's `GetStringHeight` counts explicit newlines only
(`tools/wowstub.lua:833`). It ignores `SetWidth` wrapping, so `classNote` and the now word-wrapped
footer always measure one line. The check that "contents fit at +2" (387 to 407 of 560) therefore
cannot fail on a long footer or class sentence. The width check also skips `r.delta`, the one part
whose width varies. Forever's class-note path, where the provider's sentence wraps at 188 px, has
no geometry check at all.

**Failure scenario.** A longer `WI.Changes` text on a Forever priest at +2 could overflow the
drawer's bottom edge with every suite still green.

**Fix.** Make the stub wrap when a width is set (`ceil(stringWidth / width)` lines), include
`r.delta` in the width check against `DRAWER_W - DRAWER_PAD`, and add the offsets -2..+2 loop to the
Forever T125 case with a non-druid class note.

## Not verifiable in the stub (in-game, `docs/TESTING.md` §50.6)

The stub does not fire children's OnHide or OnShow when a parent hides or shows. In the probe, the
drawer's flag stayed true after `win:Hide()`, and after `LeaveCombat` it was not re-pushed. So the
suites cannot prove close/reopen, the combat hide and return, or the ESC order after a reopen.
§50.6 covers all three. The probe's reasoning against the real client is under "Sound" above.
