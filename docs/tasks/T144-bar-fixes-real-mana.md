# T144: the clock bar after the first in-game look (T142/T143 follow-up; Forever first, both lines)

The author, 2026-11-08, with screenshots after installing T142 + T143:
1. "texture selector dont fit options": the Texture dropdown in Settings -> Clock -> Bar look lists
   about 35 entries (SpellTuner's, the game's, EllesmereUI's, LibSharedMedia's) and runs off the
   screen.
2. "text sizes change the bar size, which I dont want to happen".
3. "I would like to remove those ~ symbols". The Bar texts show `~25s`, `~142`.
4. "our mana data is different from EUI manabar". Side by side: SpellTuner 142 vs EllesmereUI 154,
   and 207 vs 224. The number is the model's (`~`), EllesmereUI's is the real pool.
5. "I would like OOM and time to full timer also change once a sec by 5s intervals". The time jumped
   from `~25s` to `~15s`.

## 1. A dropdown that fits

Find the dropdown widget the Bar look's Texture control uses (`UI/Style.lua` / `UI/ClockSettings.lua`).
- Give the open list a maximum height, about 12 rows or what fits on screen, whichever is smaller.
- Make it scroll with the mouse wheel, with a scroll bar or arrows in the kit's style.
- The selected entry is scrolled into view on open.
- Fix it in the shared widget, so every long dropdown benefits. The ESC stack and `UI_POPUP`
  behaviour stay as they are.
- Groups such as "(EllesmereUI)" may get a muted header row if the widget already supports headers.
  Do not invent a header system for this.

## 2. Text never changes the bar's size

- The bar's width is the layout's frame width (default 200), and its height is the bar height
  (default 8).
- No text item, at any size, place or offset, changes either.
- T142 let inside texts set a minimum width. **Remove that.** An inside text wider than the bar
  overflows it, drawn over or beyond the ends, never clipped into nonsense.
- Width and height change only through their own controls.
- Check `View:Minimum` / the metrics path and anything else that measures item fonts into the
  frame size.
- Tests: change every item's size 6 -> 32 and each place, and assert the frame's width and height
  are unchanged.

## 3. No `~` on the Bar texts

- `CF.ItemPieces` (`Engine/ClockFace.lua`) gives no `~` on any piece: time, label, mana, pct,
  manaMax, mp5.
- The Line and Compact layouts and the tooltips keep theirs. The tooltip is where the clock says a
  value is modelled.
- Update the Bar layout's samples (`CV.KIND_SAMPLE` users for items), the T142 tests, and the
  `look.labelSample` handling for items.

## 4. The real mana on the bar's texts (Forever)

EllesmereUI, in the author's client (`EllesmereUIResourceBars/EUI_ResourceBars_Update.lua`), shows the
real pool as text:
- It hands the secret `UnitPower("player", pt)` to the client's own C functions
  (`AbbreviateNumbers`, `string.format`) and then `FontString:SetText`.
- It never does arithmetic or comparisons on it. Its own comment: "string.format handles secrets
  natively (C function): store as-is and only pass to format/SetFormattedText, NEVER arithmetic".

This is the in-game evidence probe Q-clock-2 was waiting for. Steps:

- **Change `ST.API.DrawPowerText`** (`Client/API_Forever.lua`) to draw with
  `fs:SetFormattedText(fmt, value...)`, not `SetText(value)`:
  - `mana`: `"%d"` with `UnitPower(unit, pt)`;
  - `manaMax`: `"%d/%d"` with `UnitPower` and `UnitPowerMax`;
  - `pct`: `"%d%%"` with `UnitPowerPercent(unit, pt, true, CurveConstants.ScaleTo100)` where
    `CurveConstants` exists, else nil, "absent" (no maths on a secret to make a percent).
  - All of it inside the one pcall. Never compare, concatenate or do arithmetic on the values.
  - Keep `POWER_TEXT` as the names table, adding `manaMax`.
- **Set `ST.API.POWER_TEXT_READS = true`** with a comment naming this evidence (EllesmereUI's shipped
  code on the same client, 2026-11-08). Update `Client/Probe.lua` / `docs/DECISIONS.md` Q-clock-2's
  open item to say it is answered by that evidence, with a probe confirmation still welcome.
- **`View:PaintItems`** asks `draw.powerText` for `manaMax` too.
- **On TBC the line's `powerText` is unchanged.** TBC reads mana plainly; check whether TBC's items
  already show real mana, and if they show the model, make them read the real value through TBC's
  adapter path.
- **The real text follows the bar:**
  - On Forever's `UNIT_POWER_FREQUENT` handler (`UI/Clock_Forever.lua`, T143), also repaint the
    mana / manaMax / pct item texts, cheaply: only `fs:SetFormattedText` through `powerText`, no
    layout.
  - Add a `View` method for that, for example `View:PaintPowerTexts()`.
- **Tests:** stub `SetFormattedText` and record it; check that a secret goes in unread (the
  `DrawUnitPower` test's pattern) and that the flag is honoured.

## 5. The time moves once a second, one 5 s step at a time

Forever's face already rounds the time to the nearest 5 s (`Engine/ManaModel.lua` `Shown`). The
jumps (25 -> 15) are the estimate moving between 0.5 s ticks. The author asked for the shown time to
change once a second by 5 s steps. That means:

- **A pure helper** in `Engine/ManaModel.lua`, for example `MM.Steady(latch, face, now)`, applied
  in `UI/Clock_Forever.lua` `PaintFace` before `view:Paint`.
- **Within one label** (OOM, or FULL / time to full) with a numeric `face.value` (`known == "point"`):
  - the shown value changes at most once per 1.0 s;
  - each change moves it one 5 s step toward the face's new value. A 25 s shown with a new 15 s
    estimate reads 20 s, then 15 s a second later.
- **Snap to the new value** when:
  - the label or mode changes;
  - the value goes nil, bound or pending, or comes back from one of those;
  - the difference is 60 s or more (a new fight, a potion). This threshold is a named constant.
- **When a step is due**, the steady value never runs behind a true countdown by more than one step.
- **The latch lives in the clock and is reset** on `PLAYER_REGEN_*` and on hide.
- **Tests:** a sequence of faces and times (25 -> 15 at t = 0 gives 20 at t = 1.0 and 15 at
  t = 2.0, nothing in between at t = 0.5), a label change snaps, a nil snaps, and the 60 s snap.

## Rules

CLAUDE.md applies:
- the adapter rule (client calls in `Client/` only);
- ClockView never shows or hides the frame;
- ASCII only;
- `make check` green, with expected counts and the import fixture updated if what is stored changes.

Run only the affected suites while iterating, and `make check` once at the end, in the background.

## Acceptance

- `make check` green.
- `docs/TESTING.md`: add §65 (Forever, about 3 min):
  - the texture list scrolls and fits;
  - sizes and places never change the bar;
  - no `~`;
  - the mana number equals EllesmereUI's at every moment, including while regenerating;
  - the time steps by 5 s, at most once a second.
- `docs/HISTORY.md`: a dated entry.
- Commit on `worktree-forever-talents`, message `T144: ...`, ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not install.
