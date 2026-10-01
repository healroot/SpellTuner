# T113 -- kernel seams: subcommands and dump lines (S0)

Status: **built** 2026-10-01 on branch `next/T113` (base `e2b13f4`), awaiting the integrator.
Wave N1, batch B. Spec: `docs/SPEC-next.md` 2.5 (S0) and section 11's T113 row; the need comes
from `docs/research/next/CRITIQUE-next.md` item 4 (`/st ui style` and `/st clock layout` would
otherwise collide with `Core_Forever.lua`'s own `ui` and `clock` verbs, depending on load order).
Owned files only: `Core.lua`, `UI/Dump_Forever.lua`, `tools/corecheck.lua`,
`tools/consolecheck.lua`. No TOC changes, no default registered (`defaultscheck` unchanged).

## What was built

### `Core.lua` -- `MD:AddSubcommand(verb, sub, fn, usage, text)`

- `/st <verb> <sub> <rest>` runs `fn(rest, rawRest)`: the sub is the argument's first word,
  matched case-insensitively (the dispatcher already lower-cases `arg`); `rest` is the rest
  lower-cased and `rawRest` the rest as typed, the same pair a verb gets. **Any other argument
  reaches the verb's own function exactly as before** (`/st clock`, `/st clock lock`,
  `/st ui reset`, `/md window 20`).
- **Kept across `MD:AddCommand`:** `AddCommand` on a verb that has subs replaces only its
  function, usage, text and hidden flag; the subs stay. Both load orders give the same
  dispatch and the same row (the only difference: a verb created by a sub keeps the position
  the sub gave it in the list).
- **A sub on a verb nobody registered creates it** with a function that prints one
  `usage: /st <verb> <sub usage>` line per sub, and a row `/st <verb> <usage1> / <usage2>`
  whose text is the subs' texts joined by `"; "`. A later `AddCommand` of that verb replaces the
  printer, the usage and the text (subs kept).
- **The help row** (and `MD:Commands()`'s `usage`, which the About tab and the tests read) is
  the verb's usage followed by each sub's after `" / "` -- one row per verb. With no sub it is
  the usage exactly as registered.
- A sub registered again replaces its function and usage in place. Bad arguments (verb not a
  string, sub not one word, fn not a function) raise at the caller.

### `Core.lua` -- `MD:AddDumpLine(key, fn)` and `MD:DumpLines()`

- On every TOC (a shared file such as `UI/Styles.lua` may call it on both lines; only Forever
  has a dump). Registration order kept; a key registered again replaces its fn in place.
- `MD:DumpLines()` answers `{ key, fn }` copies in order.

### `UI/Dump_Forever.lua`

- The registered lines go at the **end of `== client`** (after `character:`), so with none
  registered no header and no line is added. Each `fn()` runs under `pcall`; a string or number
  answer is escaped with `MD.Text.EscASCII` (ASCII, one line -- a newline becomes `\010` --, no
  bare pipe); a raise becomes `<key>: error <message>` and a non-string answer
  `<key>: no line`, never costing the dump.

## Deviations from the spec text (small, stated)

1. **The row's separator is `" / "`, not `"|"`.** The spec's example row is
   `/st ui reset|style <name>`; a bare pipe in a chat line is an escape-sequence start in the
   game's font (CLAUDE.md: never a bare `|`), and the codebase already writes alternatives with
   `" / "` (`/st measure [dump [all] / clear]`). So the row reads `/st ui reset / style <name>`.
2. **`AddSubcommand` takes an optional fifth argument `text`**, used only for the row of a verb
   the sub created (the spec's four-argument signature works unchanged; `text` defaults to
   `""`). Without it a created verb's help row would read `/st ui style <name> - ` with an
   empty description.
3. **`fn(rest, rawRest)`**: the spec says `fn(rest)`; the raw tail is passed as a second
   argument, the same pair a verb gets, so a sub taking a name (a run's, a style's) can keep the
   case typed. A one-argument `fn` is unaffected.
4. Dump lines are placed in `== client` (the spec names no place). The section is what a
   report is read for first and the style / integrations / clock layout lines are about the
   client's state; no new header means nothing changes while none is registered.

## Byte-identity while nothing registers

Before the first edit a scratch script (not committed) captured, under both flavours, the
chat output of `help`, `nosuch`, `ui`, `ui reset`, `clock`, `clock lock`, `window`,
`window 20`, every `MD:Commands()` row, and (Forever) the whole `MD:BuildDump()` with `date`
pinned. After the change the same capture is **byte-identical** on both flavours (`cmp`).
`slashcheck/tbc` (the TBC golden of every verb and alias, the help and the About rows) is
unchanged: 8 ok.

## Failing first (Core.lua and UI/Dump_Forever.lua at the parent, the new tests in)

```
corecheck/forever   24 ok, 5 failed  (attempt to call method 'AddSubcommand' (a nil value))
corecheck/tbc       24 ok, 5 failed
consolecheck/forever 20 ok, 2 failed (attempt to call method 'AddDumpLine' (a nil value))
```

## Tests added

**`tools/corecheck.lua`** (+5, both flavours, after the T61 section):
1. a sub runs before the verb, its first word matched in any case (`T113Verb STYLE  Blood
   Furnace` -> `blood furnace` / `Blood Furnace`; a bare sub gets `""`; `styles` reaches the verb);
2. every other argument reaches the verb unchanged -- Forever: with a sub on `clock` and on
   `ui`, `/st clock` toggles shown, `/st clock lock` toggles only the lock, `/st ui reset` resets
   once, `/st ui` prints `usage: /st ui reset`; TBC: with a sub on `window`, `/md window 20` sets
   the half-life and `/md window` prints its usage; the subs run exactly twice;
3. `AddCommand` after `AddSubcommand` keeps the subs, both load orders (dispatch and rows);
4. a sub on an unknown verb creates it with its usage printer (two `usage:` lines, the row
   `/st t113new go <name> / stay`, text `go somewhere; stay here`, not hidden);
5. the verb's help row gains the sub's usage, one row per verb (before / after / re-registered).

**`tools/consolecheck.lua`** (+2, forever, a fresh session of their own, last):
1. with no dump line registered the dump is byte-identical -- `== client` is followed by its
   two lines and `== saved variables`; one line registered is the only difference (removing
   it gives the first dump back, byte for byte, date pinned);
2. a dump line appears once, in registration order, ASCII -- a re-registered key replaced in
   place, a colour code / non-ASCII byte / newline escaped (`||cff...`, `\195\169`, `\010`), a
   raising provider `t113raise: error ...`, a nil answer `t113nil: no line`.

## Suites, before and after

| suite | before | after |
|---|---|---|
| `corecheck/forever` | 24 | **29** (+5) |
| `corecheck/tbc` | 24 | **29** (+5) |
| `consolecheck/forever` | 20 | **22** (+2) |
| `consolecheck/tbc` | 1 | 1 |
| `slashcheck/tbc` | 8 | 8 (golden unchanged) |
| every other suite | unchanged | unchanged |

`make check`: **72 run(s), all passed**; the only notes are the three count lines below
(`counted 67 run(s) against 67 expected`). `apicheck`: 60 files, 48 distinct globals,
**0 findings**; `textcheck`: 9 TOCs, 98 files, 0 findings. `luac -p` clean on the four files.

## Integrator lines

**`tools/data/expected-counts.json`:**

```
  "consolecheck/forever": 22,
  "corecheck/forever": 29,
  "corecheck/tbc": 29,
```

**CLAUDE.md, the `Core.lua` row,** append:

> **T113 (S0, `docs/SPEC-next.md` 2.5):** `MD:AddSubcommand(verb, sub, fn, usage, text)` --
> `/st <verb> <sub> <rest>` runs `fn(rest, rawRest)` (the first word, any case), every other
> argument reaches the verb unchanged; subs kept across `MD:AddCommand` (either load order); a
> sub on an unregistered verb creates it with a usage printer; the verb's help row is its usage
> then each sub's after `" / "`. `MD:AddDumpLine(key, fn)` / `MD:DumpLines()` -- a line a file
> adds to `/st dump` without owning it. Nothing changes while nothing registers.

**CLAUDE.md, the `UI/Dump_Forever.lua` row,** append:

> **T113:** the lines registered with `MD:AddDumpLine` end the `== client` section, in
> registration order, each `EscASCII`-escaped to one line; a raising provider reads
> `<key>: error ...`; none registered adds nothing.

**docs/TOOLS.md section 1:** `corecheck` 24 -> 29 (both), `consolecheck/forever` 20 -> 22.

**docs/HISTORY.md:** "T113 (S0): the kernel's subcommand and dump-line seams; byte-identical
while nothing registers (help, slash outputs and the dump captured before and after, both
flavours); corecheck +5 both, consolecheck/forever +2."

No DECISIONS line (no visible change on either line), no TOC line, no `check.sh` line.
