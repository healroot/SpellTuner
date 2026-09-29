# T35 -- the spell list model, pure

Status: **built** 2026-09-29 on branch `ui/T35` (base af266e5), for review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T35** | **Spell list model, pure** (3.3): `Spells/Tabs.lua`: `Seed(book)`, `Get`, `Add`, `Remove` (records `removed`), `Move`, `Undo`, `Reconcile(book)`, `Reset`, `Resolve(key)` giving a family or `stale`. `Book` gives each family `key` and `ids`. `cdb.spellTabs` initialised. | `Spells/Tabs.lua` (new), `Spells/Book.lua`, `Core_Forever.lua`, both Forever TOCs | new `tools/tabscheck.lua` (seed = known heals by learn level; fallback to damage with a mana cost; reconcile appends a new heal once and never a removed one or a damage spell; stale entries kept; undo) | -- (parallel with T29) |

Spec sections it cites: 3.3 (storage, the seed, the reconcile, a family the book no longer has),
and through it 3.2 (Undo "until the next change", the new dot, Reset to my heals) and 3.4 (ticking
appends, unticking records `removed`, passives not listed). Decision 2 (8.1): a newly learned heal
is appended with a dot unless it was removed once.

## What was built

**`Spells/Tabs.lua`** (new, `MD.Tabs`; Forever TOCs only, listed right after `Spells\Book.lua`).
No frames, no client call: every book it reads is the table `Book:Scan()` built, and everything it
keeps is `MD.cdb.spellTabs`:

```lua
MD.cdb.spellTabs = {
  order   = { "Healing Touch", "Rejuvenation" },  -- family keys, the player's order
  removed = { ["Moonfire"] = true },              -- never re-added by Reconcile
  seen    = { ["Healing Touch"] = true },         -- viewed once: no "new" dot
  ids     = { ["Healing Touch"] = { 5185, 5186 } }, -- the rank ids beside a key (3.3's fallback)
  kind    = "heal",                               -- what the seed took: "heal" / "damage" / nil
  seeded  = true,
}
```

| Call | Does |
|---|---|
| `Tabs:Store()` | `MD.cdb.spellTabs`, created on first use and repaired field by field (a non-string or repeated key dropped from `order`) |
| `Tabs:SeedList(book)` | `kind, keys` a seed of this book would give: every `heal` family with a known rank, by the lowest learn level of its known ranks (then name); with none, the `damage` families whose known ranks cost mana (an amount or a percent; Book's `free` costs -- none, Rage, Focus, Energy -- are not mana); with neither, `nil, {}`. A family whose every rank is passive is never taken |
| `Tabs:Seed(book)` | once per character: `true` when it seeded, `false` when already seeded. Seeded families are `seen` (no dot) |
| `Tabs:Get(book)` | a copy of `order`; with a book, the first call seeds (the seed runs on first open) |
| `Tabs:Has(key)`, `IsNew(key)`, `MarkSeen(key)` | listed; listed and never viewed; viewed |
| `Tabs:Add(key, at, book)` | inserts at row `at` (the end when nil), clamped; refuses a listed key or one the book does not have; clears `removed[key]`, marks it seen, keeps its ids |
| `Tabs:Remove(key)` | the row it had; records `removed[key]`; one pending Undo |
| `Tabs:Undo()`, `UndoKey()` | the last removal put back at its old row, once; any other edit (Add, Move, Reset, another Remove) ends it |
| `Tabs:Move(key, to)` | the row it ends on, clamped |
| `Tabs:Reset(book)` | "Reset to my heals": the seed again, every removal forgotten |
| `Tabs:Resolve(key, book)` | the family, else by the kept rank ids (a renamed family), else `"stale"` |
| `Tabs:Reconcile(book)` | the keys it appended. Nothing before the seed. A key renamed in the book is renamed in place; a stale key stays; the ids of present keys follow the book; a newly known family of the seeded kind that is neither listed nor removed is appended once, new until viewed. A list seeded empty takes the seed's rule again, so its first heal (or mana-costing damage spell) sets its kind |

The book argument is optional where a caller may not have one at hand (`Add`, `Reset`,
`Resolve`); it then reads `MD.Book:Get()`. `Add` reads the book before it looks at the list,
because reading it may rescan and a rescan reconciles.

**`Spells/Book.lua`**: `GroupFamilies` gives each family `key` (its name, as it groups them) and
`ids` (every rank's id, in rank order). `Scan` fires `MD:Fire("BOOK_CHANGED", book)` when the scan
follows `MarkDirty` (or is the first); the 2-second rescans of an unchanged book do not fire.
`Spells/Tabs.lua` reconciles on it -- "whenever `Book` marks itself dirty" (3.3) -- and T36's pane
can re-render on it.

**`Core_Forever.lua`**: on `CORE_LOGIN` (after the kernel's `InitDB`), `MD.Tabs:Store()` puts
`cdb.spellTabs` in place, empty and not seeded.

**TOCs**: `Spells\Tabs.lua` after `Spells\Book.lua` in `SpellTuner_Mainline.toc` and
`SpellTuner.toc`. The TBC TOC is untouched.

## Tests first

`tools/tabscheck.lua` (new, forever, 24). Pure cases build their books with `Book:GroupFamilies`
and `Book:Rows` on synthetic entries (so key, ids and kind are Book's own); the first and last go
through the stub's spellbook. Each block runs under `pcall`, so the old code fails per block
instead of crashing.

Against the base (af266e5, the suite copied into an export of it): **0 ok, 15 failed** -- `Book
gives every family its key and the ids of its ranks - HT key=nil ids=`, `cdb.spellTabs initialised
at login - spellTabs=nil`, and the thirteen `MD.Tabs` blocks raising `attempt to index upvalue
'Tabs' (a nil value)`.

After: **24 ok, 0 failed**:

- Book gives every family its key and the ids of its ranks (the stub: HT `5185`, Rejuvenation `774,1058`)
- `cdb.spellTabs` initialised at login: empty, not seeded
- the seed is the known heals by learn level (Healing Touch 1, Rejuvenation 4; not Regrowth, unlearned; not Wrath, Mark of the Wild, or a passive heal)
- a seeded family is not new, and its rank ids are kept beside its key
- the seed runs once: an edited list is not seeded again
- the first Get with a book seeds the list
- with no heal the seed is the damage that costs mana, by learn level (not a Rage spell, not a free one, not a utility)
- with neither the list is empty, and seeded
- the reconcile appends a newly known heal once, as new (the player's own order kept)
- the reconcile never adds a damage or a utility family to a heal list
- a family viewed once is no longer new
- the reconcile never re-adds a removed family
- the reconcile does nothing before the seed
- a list seeded empty takes the seed's rule when a heal is learned
- a family the book no longer has stays in the list, stale
- a renamed family resolves through its ids and keeps its place (no duplicate appended)
- Add inserts at a row, once, and only a family the book has
- Remove records the family as removed
- Undo puts it back where it was, once, and forgets the removal
- Undo lasts until the next change
- adding a removed family back forgets that it was removed
- Move puts a family at a row, clamped to the list
- Reset gives the seed back and forgets every removal
- a heal learned after the seed is appended when the book rescans (`S.AddSpell` Regrowth and Moonfire, `SPELLS_CHANGED`, `Book:Get()`: Regrowth appended and new, Moonfire not)

## Full check

The loop in `docs/TOOLS.md` section 1 plus `tabscheck`, on this branch, compared line by line with
the same loop on an export of af266e5: every suite's count and last line unchanged -- simcheck PASS,
reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56,
regencheck 27, simwindow 8, solvercheck 77, timeline 27, spelltip 48, practice 74, practiceui 49,
migrate 7, probecheck 86, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24,
scenariocheck 12, gatecheck 9, replayforever 11, reviewforever 10, coachforever 18,
practiceforever 15, bindscheck 6, parsecheck 12, bookcheck 17, tipcheck 22, clockcheck 17,
spellsui 17, measurecheck 30, releasecheck 13, adaptercheck 22 / 15, corecheck 10 / 8,
svcheck 6 / 1, consolecheck 14 / 1 -- plus **tabscheck 24** (new). The only other line that moved:
`apicheck: 8 Forever TOCs, 45 files` (44 before: the new file), 45 distinct globals, **0
findings**; `apicheck --selftest` 10 of 10; `refcheck --selftest` ok. (On the export, releasecheck
cannot run -- it reads `git ls-files` and an export has no repository; on this branch it passes 13.)
`luac -p` on `Spells/Tabs.lua`, `Spells/Book.lua`, `Core_Forever.lua`, `tools/tabscheck.lua`: ok.

The TBC line: no TBC-loaded file changed (`Spells/`, `Core_Forever.lua` and the two TOCs are
Forever-only); every TBC suite's count and output are as before.

## Deviations

- **`kind` and `ids` in the store**, beside the four fields 3.3 shows. `ids` is the "stored beside
  each key" fallback 3.3 names. `kind` is what the seed took, so the reconcile knows which kind it
  may append ("a newly known family of the seeded kind"); a list seeded empty (a character with
  neither heals nor mana-costing damage yet) has `kind = nil` and takes the seed's rule again at
  each reconcile, so its first heal is appended rather than never.
- **`BOOK_CHANGED`**: 3.3 says the reconcile "runs whenever `Book` marks itself dirty", but a dirty
  book has no new data until it rescans, so the reconcile runs on the first scan after the mark
  (Book fires the callback), not on the mark itself.
- **Undo is session memory** (`Tabs._undo`), not saved: 3.2's `Wrath removed [Undo]` lasts "until
  the next change", and a `/reload` is treated as one.
- **The seed marks its families seen** (no dot); only the reconcile's appends are new. 3.2/3.3 give
  the dot to a family "new" after the list exists, and the seeded list is the first list.
- **A renamed family** (its key gone, its kept ids now under another name) is renamed in place by
  the reconcile, keeping its row and dot state, so it is neither a stale row nor appended twice.
- `docs/TOOLS.md` section 1 does not list `tabscheck` yet: that file is outside this row, and T44
  writes the docs for the whole wave (CLAUDE.md rows, TOOLS). The suite runs with the loop's own
  line: `bash tools/run.sh tools/tabscheck.lua`.
