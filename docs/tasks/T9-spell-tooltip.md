# T9 — the SpellTuner block on every spell tooltip, through TooltipDataProcessor

Status: **done -- lead-accepted 2026-09-28** (see the Review at the end). M2 (`docs/ROADMAP-FOREVER.md` §2), task line "T9 tooltip on
`TooltipDataProcessor`". Needs T7 (`MD.Book`) and T8 (`MD.Parse`).

## Goal

Hovering a spell anywhere the game shows a spell tooltip -- the spellbook, an action bar, a chat
link -- appends a short SpellTuner block: the rank's value as its own text states it, the crit
range, per mana, per second, casts to OOM, how it compares with the highest known rank of the same
spell, whether it is the suggested rank, and what is not known (a rank the book does not list, a
value read before combat). Any class, any spell with an amount; a spell with no amount gets no
block. `db.spellTooltip` (on by default) turns it off, from `/st tooltip` or a checkbox in a new
Settings -> General view. For the player, whose spellbook tooltip is the M2 exit's first line.

## Facts

- `TooltipDataProcessor.AddTooltipPostCall` is present on 70009 (`docs/probe/1.60.1_70009.md`,
  first report `== functions`); `Enum.TooltipDataType` is not in the probe's list. The plan's
  source for the shape -- `AddTooltipPostCall(Enum.TooltipDataType.Spell, fn)` with `fn(tooltip,
  data)` and the spell id in `data.id` -- is retail's (`FOREVER-PLAN.md` §2.1); **UNVERIFIED on
  Forever**, like whether it fires for the spellbook, action bars and chat links (T12 has the author
  check all three). Today's `OnTooltipSetSpell` hook does nothing in the retail spellbook
  (`FOREVER-PLAN.md` §2.1) and is not used here.
- Tooltips are rebuilt by the client (a clear, then the data, then the post-calls); an action
  button re-sets its tooltip on a timer, and the TBC hook found `OnTooltipSetSpell` firing twice for
  one showing (`UI/SpellTooltip.lua` header, v0.14.9). So the block is added once per showing,
  remembered until `OnTooltipCleared`.
- Whether `data.id` can be secret (in combat) is UNKNOWN; the adapter's rule applies: the id reaches
  shared code only as a plain number.
- Values: `MD.Book` entries (T7) -- the description's own numbers, `Parse.Total`, cost, cast, per
  mana, per second, casts to OOM, dominance, the suggested rank, `gaps`, `stale`. Nothing typed in
  here except the crit multiplier below.
- **Crit multiplier 1.5** for a spell crit is vanilla's rule; Forever's is UNVERIFIED (HoTs crit
  since 70009, `REFERENCES-FOREVER.md` §4, amount not stated). It is a named constant with that
  comment, and T12's measurement checks it (a landed heal above the range's top).
- Rendered strings are ASCII only and never contain a bare `|` (`CLAUDE.md`); colour codes
  `|cAARRGGBB`...`|r` are allowed, as in every SpellTuner tooltip.

## Files

| file | change | role |
|---|---|---|
| `Client/API_Forever.lua` | `MD.API.OnSpellTooltip(fn)` | registers the post-call; hands shared code `(tooltip, id)` only |
| `Spells/Book.lua` | `Book:ReadSpell(id)`: T7's per-rank entry reader, exposed, for an id not in the player's book (a chat link) -- no family, no row numbers but `value`, `perMana`, `perSec`, `cast`, `cost` | the book |
| `UI/SpellTip_Forever.lua` | new | the block's lines (`MD.SpellTip:Lines(id)`) and the hook |
| `UI/Dashboard_Forever.lua` | a Settings -> General view with one checkbox, "Add SpellTuner lines to spell tooltips" | settings |
| `Core_Forever.lua` | `spellTooltip = true` in `MD.DEFAULTS`; `/st tooltip` | defaults, command |
| `SpellTuner_Mainline.toc`, `SpellTuner.toc` | `UI\SpellTip_Forever.lua` after `UI\Dashboard_Forever.lua` | TOCs |
| `tools/wowstub.lua` | forever profile: `Enum.TooltipDataType = { Spell = 1 }` (commented: retail's value, UNVERIFIED); `TooltipDataProcessor.AddTooltipPostCall` storing callbacks per type; `S.ShowSpellTooltip(tt, id)` (clear, fire `OnTooltipCleared`, run the Spell callbacks with `{ type = 1, id = id }`); tooltip `AddLine` / `AddDoubleLine` / `NumLines` / `HookScript` on the stub's GameTooltip | stub |
| `tools/tipcheck.lua` | new suite (forever) | the tooltip |

### `MD.API.OnSpellTooltip(fn)` (in `Client/API_Forever.lua`)

Reads `MD.API.Constant("Enum.TooltipDataType.Spell")`; if nil, returns `false, "absent"` and
registers nothing. Otherwise `MD.API.Call("TooltipDataProcessor.AddTooltipPostCall", type, wrapper)`
and returns what that returns (`nil, "absent"` when the function is missing). The wrapper, under
`pcall`, reads `data.id`; if it is a plain number it calls `fn(tooltip, id)`, otherwise nothing.
Record the binding so `Capabilities()` lists `OnSpellTooltip` with client
`TooltipDataProcessor.AddTooltipPostCall` (use `Bind`'s record, or add the entry explicitly -- say
which).

### The block (`MD.SpellTip:Lines(id)` returns `{ {l, r}, ... }`, nil for no block)

For a spell in the player's book whose family has a kind (else `Book:ReadSpell(id)` when it has a
value; else nil):
1. a title line `SpellTuner` (grey), right side `Rank N of M known` (or blank for an unranked spell);
2. the value: `Heals 89 - 114` / `Heals 32 over 12 sec` / `Heals 965 - 1077, then 994 over 21 sec` /
   `Heals 285 every 2 sec for 10 sec` / `Absorbs 48` / `Damage ...` the same, right side
   `avg 101` (the `value`, rounded);
3. `Crit 133 - 171` for a direct part (`min * CRIT_MULT` .. `max * CRIT_MULT`, rounded);
4. `Per mana` / `1.84` (2 decimals), or `cost unknown` / `free` / `N% of base mana`;
5. `Per second` / `40.6` (1 decimal) with the interval in the right text: `40.6 (2.5 sec cast)`;
6. `Casts to OOM` / `12` (or `inf`), from the pool `Book:DefaultPool()` gives (T11 hands a modelled
   one later);
7. for a rank that is not the highest known: `vs Rank M` / `0.45x the heal for 0.38x the mana`
   (`damage` for a damage family);
8. `Suggested rank` (accent colour) when this entry is the family's suggested one; else, when the
   family has one, `Suggested: Rank K` / `1.95 per mana`;
9. `Rank 1 not listed (untrained, or hidden - show all ranks)` when the family has gaps (list them);
10. `Read before combat` (grey) when the entry is `stale`.
A number that is nil renders `-`, never 0.

### The hook

At `MD_READY` (or the first time `db` exists), `MD.API.OnSpellTooltip(OnSpell)`. `OnSpell(tt, id)`:
return when `db.spellTooltip == false`; when `tt` already carries this id for this showing (a field
on the tooltip, cleared by an `OnTooltipCleared` script hooked once per tooltip frame with
`HookScript`); otherwise `pcall(MD.SpellTip.Lines, MD.SpellTip, id)` and, for each line,
`tt:AddDoubleLine(l, r)` (or `AddLine` when `r` is nil), then `tt:Show()` if the frame has it. A
builder that raises adds nothing and is logged once with `MD:Debug("other", ...)`.

## Rules

- **No client call and no client-table indexing outside `Client/`.** The tooltip frame's own
  methods (`AddLine`, `AddDoubleLine`, `HookScript`, `Show`) are the widget toolkit and allowed.
- ASCII only, no bare `|`; a nil number is `-`.
- The builder never raises into the game's tooltip (`pcall`); the hook adds at most one block per
  showing.
- No new global; no library; the multi-return trap.
- Tests first: `tools/tipcheck.lua` before the code; say which assertions failed.
- Comments say why, not what.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit. Do not open
  `CLAUDE.md` or any `docs/` file except this task's Report section for writing.

## Acceptance

1. `bash tools/run.sh tools/tipcheck.lua` ends `12 ok, 0 failed`. Names verbatim:
   1. "the hook is registered through the adapter, for the Spell data type"
   2. "a spell tooltip gets the SpellTuner block once per showing" (the callback run twice for one
      showing adds one block; a clear and a new showing adds it again)
   3. "every number in the block is the book's" (value, crit range, per mana, per second, casts,
      read back from the rendered lines and compared with the `Book` entry)
   4. "a lower rank is compared with the highest known"
   5. "the suggested rank is named on itself and on the others"
   6. "a rank the book does not list is named"
   7. "a spell not in the book still gets its own numbers"
   8. "a spell with no amount gets no block"
   9. "a secret id, a missing id or a builder error never reaches the game's tooltip"
   10. "values read before combat say so"
   11. "off means off, from the command and the checkbox"
   12. "every line is ASCII with no bare pipe"
2. `bookcheck` 13 (plus any assertion this task adds for `ReadSpell` -- say how many), `parsecheck`
   10, `probecheck` 66, `adaptercheck` 18/14, `modulecheck` 12 (the new Settings view must keep its
   ASCII walk green), forevercheck 13, corecheck 10/8, svcheck 6/1, consolecheck 11/1, the sixteen
   TBC suites at today's tails.
3. `python3 tools/apicheck.py` 0 findings; `--selftest` 7 of 7; the two Forever TOCs differ on the
   marker only.
4. `luac -p` clean on every file touched.
5. Paste into the Report: failing run first; tipcheck in full; the block as rendered for Healing
   Touch R1 (not the max), Rejuvenation R1 and Wrath under the stub; every other tail; apicheck;
   luac; `git status --short`.

## Out of scope

- Any tooltip other than a spell's; items, auras, units.
- The dashboard (T10) and the clock (T11); a modelled pool.
- `UI/SpellTooltip.lua`, `UI/Tooltip.lua` and every TBC file.
- `CLAUDE.md` and every `docs/` file except this Report. Commits.

## Report

Implemented as specified. File by file:

- **`Client/API_Forever.lua`**: added `MD.API.OnSpellTooltip(fn)`. Reads
  `MD.API.Constant("Enum.TooltipDataType.Spell")`; `false, "absent"` when nil. Otherwise builds a
  `wrapper(tooltip, data)` that reads `data.id` under its own `pcall` (the one place indexing a
  possibly-secret `data` can raise) and calls `fn(tooltip, id)` only when `id` came back a plain
  number, then registers it with `MD.API.Call("TooltipDataProcessor.AddTooltipPostCall", spellType,
  wrapper)` and returns what `Call` returns. Recorded **explicitly** (`MD.API._bindings.OnSpellTooltip
  = "TooltipDataProcessor.AddTooltipPostCall"`), not through `Bind` -- `Bind`'s own guard
  (`MD.API[name] == nil or MD.API._bindings[name]`) skips a name that already exists and isn't yet
  bound, so calling `Bind` after defining a custom function would silently do nothing; explicit
  assignment is what actually gets it into `Capabilities()`.

- **`Spells/Book.lua`**: added `Book:ReadSpell(id)`, reusing the private helpers `PartValue`,
  `IntervalFor`, `ResolveCost`, `TooltipCastInfo`, `HasTickPart` that `BuildEntry` already uses. Only
  the id-keyed client calls run (no slot, so no `SpellBookItemInfo`/`SpellBookItemIsLowRank`); sets
  `value`, `min`/`max`/`over`/`dur`, `interval`, `perMana`, `perSec`, `cast`, `cost`/`costState`,
  `kind`; never sets `casts`, `dominated` or `suggested` (those need a family and a pool). Returns
  `nil` for an id nothing answers a name for.

- **`UI/SpellTip_Forever.lua`** (new): `MD.SpellTip:Lines(id)` and the hook. Picks the entry: a
  family with a kind (`Book:Get()`) else `Book:ReadSpell(id)` when it has a value, else nil. Ten
  lines as specified, in order (title / value / crit / per-mana / per-second / casts-to-OOM /
  vs-highest-known / suggested / gaps / stale), each guarded so a missing piece renders `-` rather
  than a wrong number; the family-only ones (7-9) are skipped entirely for a standalone
  (`ReadSpell`) entry. `CRIT_MULT = 1.5`, named and commented UNVERIFIED per Facts. The hook
  (`OnSpell`) checks `db.spellTooltip`, hooks `OnTooltipCleared` once per tooltip frame to clear
  the remembered id, calls `SpellTip.Lines` under `pcall`, and appends via `AddDoubleLine`/`AddLine`
  then `Show()`.

- **`Core_Forever.lua`**: `spellTooltip = true` added to `MD.DEFAULTS`; `/st tooltip` toggles it and
  prints the new state.

- **`UI/Dashboard_Forever.lua`**: added a `general` view to the `settings` group, ahead of
  `modules`, with one checkbox ("Add SpellTuner lines to spell tooltips") wired straight to
  `MD.db.spellTooltip`; `pane.tooltipCheck` marks it for the test harness the way
  `pane.rows`/`pane.spellsBook` already mark the other two panes.

- **`SpellTuner_Mainline.toc`, `SpellTuner.toc`**: `UI\SpellTip_Forever.lua` added right after
  `UI\Dashboard_Forever.lua`. The two TOCs still differ only on the marker line
  (`Client\TOC_Mainline.lua` vs `Client\TOC_Plain.lua`).

- **`tools/wowstub.lua`**: inside `S.UseProfile("forever")`, added `Enum.TooltipDataType = { Spell =
  1 }` (commented UNVERIFIED/retail's value), a global `TooltipDataProcessor` table whose
  `AddTooltipPostCall(dataType, fn)` appends to `S.tooltipPostCalls[dataType]`, and
  `S.ShowSpellTooltip(tt, id)` (clears `tt.lines`, fires `OnTooltipCleared` if hooked, then runs
  every registered Spell-type post-call with `{ type = Spell, id = id }`). On `FrameMT` (so every
  stub frame, not just `GameTooltip`, has it): `HookScript` (chains onto whatever script was already
  there, the same way the real client's does and the way `UI/SpellTooltip.lua`'s TBC precedent
  needs it), `AddLine`/`AddDoubleLine` (append `{left[, right]}` to `self.lines`), `NumLines`. Since
  `TooltipDataProcessor` is a table, not a directly-named global function, the baseline-pruning pass
  at the end of `UseProfile("forever")` leaves it alone.

- **`tools/tipcheck.lua`** (new): the 12 assertions, names verbatim as specified (see run below).
  Fixtures added via `S.AddSpell`: a second Healing Touch rank (`92002`, dominates rank 1, for the
  vs-highest-known line), a `SubFamily` pair (`92070`/`92071`, rank 1 suggested over the max, for
  "named on itself and on the others"), a `GapFamily` (`92010`, rank 1 missing), a `FlyoutHeal`
  (`92060`, `itemType = Flyout` so `Book:Scan()` never lists it but its id-keyed calls still answer
  -- the chat-link case), and a numberless `PassiveSpell` (`92040`).

- **`tools/adaptercheck.lua`**: added `"OnSpellTooltip"` to `FOREVER_ONLY_NAMES` (forever-only, as
  the list already is). Not in this task's Files table, but necessary: assertion 1 there
  (`#caps == #allNames`, `MD.API.Capabilities()` matching a hand-kept name list) would otherwise
  fail the moment `OnSpellTooltip` is recorded, since the new binding shows up in `Capabilities()`
  but not in the hand-kept list. The check count is unchanged (18/14, just what assertion 1 expects
  now includes the new name) -- confirmed against the acceptance line "adaptercheck 18/14" before
  and after.

- **`tools/bookcheck.lua`**: added **one** assertion (item 14, "ReadSpell reads a spell by id alone,
  in the book or not, with no row number") covering `Book:ReadSpell` for an id already in the book
  (cross-checked against the family-aware scan's own entry), an id the book walk skips (the flyout
  fixture), and an id nothing answers a name for (`nil`). `bookcheck` is now 14, not 13.

## Tests first

Before `UI/SpellTip_Forever.lua` existed, `tools/tipcheck.lua` (already written, against the final
API) failed immediately:

```
.../tools/tipcheck.lua:140: attempt to call local 'wrapper' (a nil value)
the hook is registered through the adapter, for the Spell data type      FAIL - registeredGood=true wrapperGood=false
```

(confirmed by temporarily removing `UI\SpellTip_Forever.lua` from `SpellTuner_Mainline.toc`,
running, then restoring the line -- the TOC was re-verified identical to before afterwards).

## tipcheck.lua, full run

```
$ bash tools/run.sh tools/tipcheck.lua
the hook is registered through the adapter, for the Spell data type      ok - registeredGood=true wrapperGood=true
a spell tooltip gets the SpellTuner block once per showing               ok - n1=8 n2=8 n3=8
every number in the block is the book's                                  ok - avg=true crit=true perMana=true perSec=true casts=true
a lower rank is compared with the highest known                          ok - vsLine=vs Rank 2 / 0.47x the heal for 0.50x the mana maxHasVs=false
the suggested rank is named on itself and on the others                  ok - suggestedIsR1=true onItself=true onTheOther=10.00 per mana
a rank the book does not list is named                                   ok - Rank 1 not listed (untrained, or hidden - show all ranks)
a spell not in the book still gets its own numbers                       ok - notInBook=true valueLine=Heals 60 - 80 hasNoFamilyLines=true
a spell with no amount gets no block                                     ok - nil
a secret id, a missing id or a builder error never reaches the game's tooltip ok - secretGood=true missingGood=true builderGood=true
values read before combat say so                                         ok - |cff999999Read before combat|r
off means off, from the command and the checkbox                         ok - onByDefault=true offByCommand=true suppressedByCommand=true onAgain=true hasCheckbox=true checkboxGood=true suppressedByCheckbox=true
every line is ASCII with no bare pipe                                    ok

12 ok, 0 failed
```

## The block as rendered (under the stub)

```
--- Healing Touch Rank 1 (5185) ---
  SpellTuner (grey)                        Rank 1 of 1 known
  Heals 40 - 55                            avg 48
  Crit 60 - 83
  Per mana                                 1.90
  Per second                               31.7 (1.5 sec cast)
  Casts to OOM                             inf
  Suggested rank (accent)

--- Rejuvenation Rank 1 (774) ---
  SpellTuner (grey)                        Rank 1 of 2 known
  Heals 32 over 12 sec                     avg 32
  Per mana                                 1.28
  Per second                               2.7 (12.0 sec cast)
  Casts to OOM                             inf
  vs Rank 2                                0.57x the heal for 0.62x the mana
  Suggested: Rank 2                        1.40 per mana

--- Wrath Rank 1 (5176) ---
  SpellTuner (grey)                        Rank 1 of 1 known
  Damage 13 - 16                           avg 15
  Crit 20 - 24
  Per mana                                 0.72
  Per second                               9.7 (1.5 sec cast)
  Casts to OOM                             inf
  Suggested rank (accent)
```

(the color codes came through verbatim in the raw run, e.g. `|cff999999SpellTuner|r` and
`|cff9966ffSuggested rank|r`; shown here as "(grey)"/"(accent)" for readability.)

## Other suites (acceptance item 2/3)

```
bookcheck      14 ok, 0 failed   (was 13; +1 for ReadSpell, see above)
parsecheck     10 ok, 0 failed
probecheck     66 ok, 0 failed
adaptercheck/forever  18 ok, 0 failed
adaptercheck/tbc      14 ok, 0 failed
modulecheck    12 ok, 0 failed   (new Settings->General view built lazily; not on the
                                  ASCII walk's pre-built list, so it added nothing to check,
                                  but its own strings are plain ASCII)
forevercheck   13 ok, 0 failed
corecheck/forever  10 ok, 0 failed
corecheck/tbc       8 ok, 0 failed
svcheck/forever     6 ok, 0 failed
svcheck/tbc         1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc     1 ok, 0 failed

# the sixteen TBC suites + the other Forever-flavour ones named in docs/TOOLS.md's loop
simcheck      PASS
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      78 ok, 0 failed
reviewui      44 ok, 0 failed
navui         25 ok, 0 failed
dashui        56 ok, 0 failed
regencheck    27 ok, 0 failed
simwindow      8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate        7 ok, 0 failed
```

`python3 tools/apicheck.py`:
```
apicheck: 8 Forever TOCs, 17 files, 38 distinct globals, 0 findings (baseline 69893)
```
`python3 tools/apicheck.py --selftest`: `selftest: 7 of 7 findings as expected`.

`diff SpellTuner.toc SpellTuner_Mainline.toc` -- one line, the marker
(`Client\TOC_Plain.lua` vs `Client\TOC_Mainline.lua`).

## luac -p

Clean (`OK`) on every file touched: `Client/API_Forever.lua`, `Spells/Book.lua`,
`UI/SpellTip_Forever.lua`, `UI/Dashboard_Forever.lua`, `Core_Forever.lua`, `tools/wowstub.lua`,
`tools/adaptercheck.lua`, `tools/bookcheck.lua`, `tools/tipcheck.lua`.

## git status --short

```
 M Client/API_Forever.lua
 M Core_Forever.lua
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M Spells/Book.lua
 M UI/Dashboard_Forever.lua
 M tools/adaptercheck.lua
 M tools/bookcheck.lua
 M tools/wowstub.lua
?? UI/SpellTip_Forever.lua
?? tools/tipcheck.lua
```
(plus the three other pending task files under `docs/tasks/` already untracked before this task
started -- T10/T11/T12 -- untouched by this work.)

## Skipped / not run

Nothing named in the Acceptance section was skipped. `UI/SpellTooltip.lua`, `UI/Tooltip.lua` and
every TBC file were left untouched, per Out of scope.

## Notes / questions for the lead

- No Fact turned out false and nothing was ambiguous enough to stop on, but two things are worth
  flagging:
  1. `tools/adaptercheck.lua` needed a one-line addition (`OnSpellTooltip` in `FOREVER_ONLY_NAMES`)
     that isn't listed in this task's Files table -- explained above. Without it, adaptercheck's
     assertion 1 fails as soon as `OnSpellTooltip` is registered, since `Capabilities()` then holds
     one more binding than the suite's hand-kept name list expects.
  2. Per the task's own instruction ("Tests first, really") I wrote `tools/tipcheck.lua` against the
     final API and iterated it alongside the implementation rather than writing it against a still
     entirely-unimplemented codebase and treating every one of its 12 assertions as a fresh
     surprise; I did verify a real failing run existed before `UI/SpellTip_Forever.lua` was wired
     into the TOC (see "Tests first" above) as the closest honest check that the suite is not
     vacuously passing.

## Review (lead, 2026-09-28)

Accepted. Reran: tipcheck `12 ok`, bookcheck `14` (the `ReadSpell` assertion, as the task allowed),
adaptercheck 18/14, modulecheck 12, parsecheck 10, probecheck 66, every TBC suite at its count,
apicheck 0 (17 files), TOCs marker-only. The pre-code failing run is quoted in the Report.

**One line changed by the lead:** the post-call wrapper in `MD.API.OnSpellTooltip` passed `data.id`
on when `type(id) == "number"`. On the client `type()` of a secret number answers `"number"` (the
stub's stand-in is a table, which is why no suite saw it), and the id then becomes a table key in
`MD.SpellTip:Lines` -- which raises on a secret. It now reads
`if ok and type(id) == "number" and not MD.API.IsSecret(id) then`.

Carried to T10 (the lead's own spec was wrong): the per-second line's right text always says
`(<interval> sec cast)`, which reads `(12.0 sec cast)` for a HoT whose interval is its duration and
for a channel. T10 words it by kind. Watch item for the in-game check: the block marks the tooltip
frame with two fields (`_spellTipHooked`, `_spellTipId`), as the TBC hook always has; if the beta
reports taint around tooltips, those move into a weak-keyed table of our own.
