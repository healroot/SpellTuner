# T27 -- practice: bindings for spells not in the book, hidden (Forever)

Status: built 2026-09-29 on `ui/T27` (base `af266e5`), for review.

## The row (docs/SPEC-forever-ui.md section 9)

> **Practice: bindings for spells not in the book** (decision 9). On Forever: `PR.ApplyImport` skips
> families `PR.InBook` rejects and returns them by name, and the import report prints
> `skipped (not in your spellbook): Lifebloom`; `PR.Binds()` (what the panel, the sheet and the
> session read) leaves out a binding whose family is not in the book, **without deleting it**, so it
> comes back when the spell is learned; `PR.HiddenBinds()` lists them for the sheet's footer line and
> its `[Forget]`. TBC unchanged.
>
> Files: `Engine/Practice.lua`, `UI/PracticePanel.lua`, `UI/BindingsWindow.lua` (the report line, the
> footer line). Tests: `tools/practiceforever.lua` (+5: an import skips and names Lifebloom; an
> existing Lifebloom binding is not listed, not counted, not cast; it is still in
> `db.practiceBinds`; learning the spell brings it back; Forget deletes it); `tools/practice.lua`,
> `tools/practiceui.lua` unchanged. Needs: --.

Cited sections: 1 (Lifebloom in practice), 4.4 (the bindings summary does not count them), 8
decision 9 and 8.1 (the author took every recommendation: hide automatically), 10 step 1 (the
in-game check).

## What was built

`Engine/Practice.lua`
- `PR.AllBinds()` -- the stored list, `db.practiceBinds` itself (the old `PR.Binds()` body, T24's
  one-time drop of the shipped TBC defaults included).
- `PR.Binds()` -- what is shown and cast. On TBC it is `PR.AllBinds()` (same table, same path). On
  Forever it leaves out every binding whose family `PR.InBook` rejects; when none is hidden it is
  still the stored table itself, otherwise a new list of the same binding tables (a field edit
  through it is saved; adding or removing a row goes through `PR.AddBind` / `PR.RemoveBind`). A row
  with no spell picked yet is never hidden. `PR.BindFor` (the press path) reads it, so a hidden
  binding is never cast.
- `PR.HiddenBinds()` -- the hidden ones in stored order (`{}` on TBC); `PR.ForgetHidden()` deletes
  them and returns how many.
- `PR.AddBind(b)` / `PR.RemoveBind(b)` -- a row added to, or removed from, the stored list by the
  table itself, wherever it sits among hidden ones.
- `PR.ApplyImport(list)` -- on Forever an imported binding whose family is not in the book is
  dropped before keys are matched and returned by name as a fourth value (`{ "Lifebloom" }`, each
  name once, the player's spelling via `PR.FamilyLabel`). Keys are matched against every stored
  binding, hidden ones included, so an import re-points a hidden binding on the same key. TBC gets
  `{}` as the fourth value and nothing else changes.
- `PR.ParseSpellText` -- on Forever only, a practice family the kit does not know (the kit knows
  only the book's families) is still recognised by the engine's name (`PR.FAMILY_LABELS`), so Cell's
  `spell Lifebloom` reaches `ApplyImport` and is named as skipped instead of "not a heal this addon
  models".
- `PR.MacroSpell` -- the first clause **in the book** wins; only when no clause is does it return
  the first one named (to be skipped by name). `[known:33763]Lifebloom;Rejuvenation` imports
  Rejuvenation on Forever, which is what the macro casts there. On TBC every family is in the book,
  so it returns the first clause, as before.
- `PR.RefreshKit()` -- on Forever rebuilds the kit from the book (`MD.RankMath:SpellKit`), so a
  spell learned since the last paint brings its binding back without a `/reload`. Called by the
  panel's and the sheet's paint only, never on the press path; a no-op on TBC.

`UI/BindingsWindow.lua`
- The import report adds `skipped (not in your spellbook): Lifebloom` (grey, like the other
  not-imported lines) and no longer says "Everything it had was a heal" when it skipped one.
- The footer: `1 binding kept for a spell you have not learned  [Forget]` (plural for more), grey,
  beside `+ binding` where TBC's Defaults sits (hidden on Forever). Its hover names each kept
  binding (`BUTTON5  Lifebloom`). Forget deletes them and says how many. Shown only while a binding
  is hidden, so never on TBC.
- Rows are the shown bindings; delete and `+ binding` go through `PR.RemoveBind` / `PR.AddBind`.
  Taking a key clears it from every stored binding, hidden ones too ("one press, one spell"), so a
  kept binding cannot come back on the key the player has since given another spell.
- Its paint calls `PR.RefreshKit()`.

`UI/PracticePanel.lua` -- its paint calls `PR.RefreshKit()`. It already lists and counts
`PR.Binds()`, so a hidden binding is neither listed nor counted, and with only hidden bindings
Start says nothing is bound.

## Tests first

`tools/practiceforever.lua` +5 (T27 1-5 at the end of the file). On the old code (`af266e5` with
only the test file changed) all five failed:

```
T27: an import skips a spell not in your spellbook and names it       FAIL - status=... not imported - BUTTON5: not a heal this addon models (Lifebloom) direct=false
T27: a binding for a spell not in your spellbook is not listed, ...   FAIL - binds=2 rows=2 bound=table ... Lifebloom  (not in your spellbook)
T27: the hidden binding is still in db.practiceBinds                  FAIL - db=2 first=Rejuvenation visible=2
T27: the sheet's footer names the kept binding and Forget deletes it  FAIL - line=false hover=false hidden=0 db=2 after=false
T27: learning the spell brings its binding back                       FAIL - before=false visible=2 id=nil ... Regrowth  (not in your spellbook)
14 ok, 6 failed
```

(the sixth is T24's check 3, rewritten below). After the change: **20 ok, 0 failed**.

## Full check

- The suite loop in `docs/TOOLS.md` section 1: every suite at its old count except
  `practiceforever` 15 -> 20 (+5, this task). The TBC suites `practice` (74), `practiceui` (49) and
  the Forever `bindscheck` (6) print exactly what they printed before, line for line (addresses
  aside).
- `python3 tools/apicheck.py`: 0 findings (46 distinct globals, was 45: Lua's own `unpack`, for the
  footer's hover lines); `--selftest` 10 of 10; `python3 tools/refcheck.py --selftest` ok.
- `luac -p` on `Engine/Practice.lua`, `UI/PracticePanel.lua`, `UI/BindingsWindow.lua`,
  `tools/practiceforever.lua`: ok.
- No new adapter binding, no TOC change, no stub change.

## Deviations

- **Two T24 checks in `tools/practiceforever.lua` changed with the behaviour they held.** Check 3
  asserted the panel lists Lifebloom with `(not in your spellbook)`; decision 9 is that it is not
  listed at all, so it now asserts Lifebloom is absent (the "casts nothing" half is unchanged and
  renamed "is not shown and casts nothing"). Check 2's "any other list is kept whole" now reads the
  stored list (`PR.AllBinds()`), since `PR.Binds()` leaves out the three families this book lacks.
  Same count (15 of them) plus five.
- **"Learning the spell brings it back" is tested with Regrowth, not Lifebloom.** Forever has no
  Lifebloom to learn: `Kit_Forever.lua`'s `FAMILY_KEY` has no slot for it, so a Lifebloom binding
  stays hidden there for good (Forget is its way out). Regrowth is the real case (a level 12 spell
  bound before level 12); the test adds it to the stub's book with `S.AddSpell`.
- **`PR.ParseSpellText` and `PR.MacroSpell` changed on Forever** (not named in the row): without it
  Cell's `spell Lifebloom` never reaches `ApplyImport` on Forever (the kit does not know the family),
  and the report could not name it as the row and section 10 step 1 require. TBC's path is
  unchanged in both (the fallback is gated on Forever; `InBook` is always true on TBC).
- **`PR.AllBinds`, `PR.AddBind`, `PR.RemoveBind`, `PR.ForgetHidden`, `PR.FamilyLabel`,
  `PR.RefreshKit`** are new helpers the row implies but does not name.
- The footer and the report line use today's grey (`|cff888888`); the theme's `muted` token is T29 /
  T40's.
