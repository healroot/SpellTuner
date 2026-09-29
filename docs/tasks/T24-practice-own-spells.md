# T24 -- practice offers only the spells in your own spellbook (Forever)

Status: handed out 2026-09-29.

## Goal

On Forever, practice never names a spell the player does not have. With nothing saved, nothing is
bound: the panel and the bindings window say so and point at **Import** and **Edit bindings**
instead of inventing binds. A bind list that is exactly the TBC author's shipped defaults (which
0.16.0 wrote into the beta's SavedVariables the first time the panel was opened) is dropped once. A
bind that names a family the player's spellbook does not have says `(not in your spellbook)` and
casts nothing. The spell picker, a new row's spell and the kit the session casts from come only from
the Forever kit (T15, built from `MD.Book`). For the author on the beta, whose screenshot showed
"BUTTON5 Lifebloom (not trained)". **TBC is unchanged**: its defaults, its picker, its counts.

## Facts

- The author's report, 2026-09-29, item 1 (via the planner): the bindings list on the beta shows
  "BUTTON5 Lifebloom (not trained)", Regrowth, "Swiftmend (not trained)" -- the TBC author's Cell
  defaults; "we need to adjust to spells the player really has". No TBC spell names or ids as
  defaults on Forever; TBC keeps its defaults.
- `Engine/Practice.lua` 131-138 `PR.DEFAULT_BINDS` (six entries: BUTTON5 Lifebloom, ALT-BUTTON5
  Rejuvenation, SHIFT-BUTTON5 Rejuvenation rank 5, BUTTON1 Regrowth, BUTTON2 Swiftmend, SHIFT-BUTTON1
  HealingTouch); 144-150 `PR.Binds()` copies them into `MD.db.practiceBinds` when that is not a
  table -- on every client. That write is how the beta's SavedVariables got them.
- `PR.EnsureKit` (166-171) builds the Forever kit on first use; `PR.SpellFor` (174-183) reads
  `SD.known` / `SD.maxRank`, which on Forever exist only after `EnsureKit` (T15, the comment at
  158-165).
- The Forever kit (`Modules/SpellTuner_Replay/Kit_Forever.lua` 18-34, 49-90) maps the book's families
  to `HealingTouch`, `Regrowth`, `Rejuvenation`, `Swiftmend`, `Tranquility` (excluded from plans); no
  Lifebloom on Forever (its comment, T15 Facts). `SD.all[key]` = every rank the book lists,
  `SD.known[key]` = the known ones, `SD.maxRank[key]` = the highest known. `SD.familyOrder` =
  `{ "HealingTouch", "Rejuvenation", "Regrowth" }`. A class with no modelled family gets empty tables.
- `UI/BindingsWindow.lua` 30-50 `SpellItems()`: a hard-coded family list filtered by `SD.known` (so
  on Forever it is already book-only; this task holds that with an assertion); 140
  `row.spell:SetValue((b.family or "Rejuvenation") ...)`; 197 a new row `{ key = "", family =
  "Rejuvenation" }`; 200-203 the Defaults button and its tooltip naming the TBC spells.
- `UI/PracticePanel.lua` 268-281 `BindLines()`: `(not trained)` when `PR.SpellFor` is nil; the empty
  text "Nothing is bound - press Edit bindings."; 286-300 the Start button opens a session whatever
  is bound.
- `MD.API.client` is `"forever"` on interface 16000-19999, else `"tbc"` (`Client/API.lua` 89,
  CLAUDE.md's `Client/API.lua` row) -- the one way a shared file tells the two apart.
- `tools/practiceforever.lua` (9 today) sets `MD.db.practiceBinds` explicitly for its session cases
  (108, the key "1" -> Rejuvenation) and resets it to `nil` at 95.

## Files

| file | change | role |
|---|---|---|
| `Engine/Practice.lua` | `PR.Binds()` on Forever: nothing saved -> an empty list (stored as `{}`), never the defaults; a saved list equal to `PR.DEFAULT_BINDS` (same length, same key / family / rank in order) replaced by `{}` once, with one `MD:Debug("other", ...)` line; `PR.InBook(bind)` (new): true when the bind's family is in `MD.SpellData.all` on Forever (always true on TBC); `PR.SpellFor` returns nil for a bind not in the book and never indexes a nil `SD.known` / `SD.maxRank`; `PR.FirstFamily()` (new): the first of `SD.familyOrder`, then `Swiftmend`, that has a known rank, else nil | practice model |
| `UI/PracticePanel.lua` | `BindLines()`: a bind not in the book reads `(not in your spellbook)` (Forever only; TBC keeps `(not trained)`); nothing bound reads `Nothing is bound - Import your keybindings, Cell or Clique, or add one, in Edit bindings.`; Start with nothing bound, or with no family `PR.FirstFamily()` can find, writes the reason in the status line beside it and opens nothing | the panel |
| `UI/BindingsWindow.lua` | a new row's family is `PR.FirstFamily()` (nil = the picker shows no value until one is picked; nothing raises); `SetValue` with a nil family shows nothing picked rather than `Rejuvenation`; the Defaults button hidden on Forever (there are no Forever defaults) | the bindings window |
| `tools/practiceforever.lua` | the six assertions below; existing cases set their own binds as today | Forever suite |

## Rules

- `CLAUDE.md`: no libraries; ASCII-only rendered strings, no bare `|` (the colour codes already in
  these files are the existing pattern); no client call outside `Client/API.lua` (read the flavour
  as `MD.API.client`, nothing else); no new global; the multi-return trap.
- **Functional only.** A parallel design workflow is redesigning this UI. Do not restyle, move,
  resize or re-colour anything: hide the Defaults button, change the texts named above, nothing more.
- **TBC unchanged.** Every change is behind `MD.API.client == "forever"` except the Start refusal
  with nothing bound (harmless on TBC, which always has its defaults). `PR.DEFAULT_BINDS` stays as
  it is and is still what TBC gets.
- Never delete a bind the player made: only an exact copy of `PR.DEFAULT_BINDS` is dropped; any
  other list is kept whole and its foreign entries are labelled, not removed.
- Tests first: write the new assertions, run them against today's code, paste the failures in the
  Report, then change the code.
- **Other implementers are working in this tree at the same time** on `Spells/Measure.lua`,
  `Core_Forever.lua`, `tools/measurecheck.lua` (T26) and `Client/API_Forever.lua`,
  `UI/SpellTip_Forever.lua`, `tools/wowstub.lua`, `tools/tipcheck.lua` (T25). Do not edit those
  files. If a suite fails in a file you did not touch, wait a minute, re-run it once, and report it;
  do not fix it.
- Git: no `add`, `stash`, `checkout -- <path>`, `reset`, commit. No `docs/` or `CLAUDE.md` edit except
  this Report.

## Acceptance

1. `bash tools/run.sh tools/practiceforever.lua` ends `15 ok, 0 failed` (9 + 6). New assertions,
   names verbatim:
   1. "on Forever nothing is bound until you bind or import" -- `MD.db.practiceBinds = nil`, then
      `PR.Binds()` is an empty table, `MD.db.practiceBinds` is that table, and the panel's bindings
      text contains `Import` and `Edit bindings` and no family name.
   2. "the TBC author's defaults saved on Forever are dropped once" -- `MD.db.practiceBinds` = a copy
      of `PR.DEFAULT_BINDS`: `PR.Binds()` is empty; a copy with one key changed is returned whole
      (six entries, same order).
   3. "a bind for a spell not in your spellbook says so and casts nothing" -- binds `{ key = "1",
      family = "Lifebloom" }, { key = "2", family = "Rejuvenation" }`: the panel text has
      `(not in your spellbook)` on the Lifebloom line only, `PR.SpellFor` of the first is nil, and in
      a running session pressing `1` over a frame casts nothing while `2` casts.
   4. "the spell picker lists only families in your spellbook" -- every item and child id of the
      bindings window's spell list names a family with `SD.known[family]` non-empty, and none names
      Lifebloom.
   5. "a new binding row picks a spell you have" -- the window's `+ binding` gives the new row
      `PR.FirstFamily()`'s family, which is in `SD.known`; with the kit's known tables emptied
      (restore them after), it gives a row with no family and nothing raises.
   6. "Start with nothing bound says so and opens nothing" -- empty binds, click Start: no session
      is live, and the status text says nothing is bound.
2. Unchanged: `practice.lua` 74, `practiceui.lua` 49, `bindscheck.lua` 6, and every other suite of
   the loop in `docs/TOOLS.md` §1 at `docs/tasks/HANDOVER.md`'s Baselines (apart from suites T25 /
   T26 are changing: report their numbers as you find them). `python3 tools/apicheck.py` 0 findings,
   `--selftest` 10 of 10.
3. Paste: the failing run before the change, the passing run after, `luac -p` of the three changed
   shipped files, the loop's last lines.

## Out of scope

The importers (`PR.ImportKeybinds` / `ImportCell` / `ImportClique`, `PR.MacroSpell`,
`PR.BindsReport`); the session engine; `Kit_Forever.lua`; TBC's picker order and defaults; any
styling or layout; every file T25 and T26 own (Rules).

## Report

(implementer)
