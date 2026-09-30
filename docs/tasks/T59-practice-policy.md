# T59 -- Practice policy seam (plan P15)

Status: **built** 2026-09-30 on branch `plan/P15` (base `8c4cc93`), wave 6 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P15)

Review items (`docs/review/2026-09-30-project-review.md`): A6a (flavour branches in shared code: the
practice half) and A30 (the practice writer's missing fields).

- `MD.Practice.policy = { defaultBinds, kitIsLive }`; the TBC value (the author's Cell binds,
  `kitIsLive = false`) is the default inside `Engine/Practice.lua`; `Kit_Forever.lua` installs
  `{ defaultBinds = {}, kitIsLive = true }`. `OnForever()` and the three `MD.API.client` checks in
  PracticePanel and BindingsWindow read the policy.
- apicheck forbids `MD.API.client` outside `Client/` and `UI/Dump_Forever.lua`.
- Practice's own `Esc` copy goes to `MD.Text.EscASCII`.
- A30: `Practice.Session:Finish` writes `names` and `threatOn` as `FightRecorder` does (empty
  `threatOn`: practice has no threat).
- Tests: `practice` +2; equal counts `practiceui`, `practiceforever`, `bindscheck`; apicheck selftest +1.

Owned files (section 4, wave 6): `Engine/Practice.lua`, `UI/PracticePanel.lua`,
`UI/BindingsWindow.lua`, `Replay/Kit_Forever.lua`, `tools/apicheck.py`, `tools/practice.lua`,
`tools/practiceui.lua`, `tools/practiceforever.lua`, `tools/bindscheck.lua`. Two further files were
touched, both data the owned tools read (see Deviations): `tools/data/apicheck-fixture/` (`Bad.lua`,
`Client/Ok.lua`) and the generated `tools/data/import-forever-sv.lua`.

## What was built

| file | change |
|---|---|
| `Engine/Practice.lua` | `OnForever()` is gone. `PR.TBC_POLICY = { defaultBinds = PR.DEFAULT_BINDS, kitIsLive = false, client = "tbc" }` and `PR.policy = MD.PracticePolicy or PR.TBC_POLICY`, read at every call (a comment block names each field). `PR.AllBinds` seeds a new list from `policy.defaultBinds` and drops a stored exact copy of the TBC defaults once only where `policy.defaultBinds` is not them (Forever's are `{}`); `Binds`, `HiddenBinds`, `ForgetHidden`, `RefreshKit`, `InBook` and `ParseSpellText`'s engine-name fallback ask `policy.kitIsLive`. The local `Esc` is `MD.Text.EscASCII` (Core.lua, T55): the same three steps; every caller already hands it a string (`tostring(...)`, a key, a type-checked name), so the one difference -- `nil` reads `""` there, `"nil"` here -- never arises. `Session:Finish`: `names` is written for every spell id the healer's own events carry -- `OWNCAST`, `CASTSTART`, `OWNHEAL`, `OWNTICK`, the crit flag (+100000) stripped, an alias resolved through `SD:Resolve` (TBC), the bloom's own id named `"Lifebloom bloom"` -- instead of the cast ids only; `threatOn = {}` is written (no `K.THREAT` event ever is); `client` is `PR.policy.client` instead of `MD.API.client`. |
| `Modules/SpellTuner_Replay/Kit_Forever.lua` | In the branch that installs its `SpellKit` (only where no flavour has a kit of its own), `MD:Provide("PracticePolicy", { defaultBinds = {}, kitIsLive = true, client = "forever" })`. The Replay module loads before the Practice module (Practice needs it), so the policy is there when `Engine/Practice.lua` runs; `MD:Provide` (T55) raises on a second provider. `MD.Practice` itself is not created here: `Recorder_Forever`, `Dashboard_Review` and `OpenPractice` read `MD.Practice` as "the Practice module is loaded". |
| `UI/PracticePanel.lua` | Start's "no healing spell in your spellbook" refusal asks `PR.policy.kitIsLive`. |
| `UI/BindingsWindow.lua` | `+ binding` picks `FirstFamily()` when `policy.kitIsLive`; `Defaults` is hidden when `#policy.defaultBinds == 0` (no defaults to go back to). |
| `tools/apicheck.py` | Rule 10: `API.client` / `API["client"]` read (source text, comments and strings blanked, a `["client"]` index kept) outside `Client/` and `UI/Dump_Forever.lua` -> `FAIL <file>:<line> MD.API.client read outside Client/ and UI/Dump_Forever.lua (a flavour installs a policy)`. A copy of `MD.API` under a name other than `API` is not followed (stated in the docstring). Selftest expects one more finding. |
| `tools/data/apicheck-fixture/` | `Bad.lua` lines 13-15: a comment naming `MD.API.client` (no finding) and a read (line 15, the finding). `Client/Ok.lua`: the same read, no finding. |
| `tools/practice.lua` | +2 assertions after "heals are written down ...": the stream names every roster index and every spell id its own events carry; it carries a `threatOn` table, empty, with no `K.THREAT` event. |
| `tools/data/import-forever-sv.lua` | Regenerated with `tools/run.sh tools/importfixture.lua`: the two Forever practice records gain `["threatOn"] = {}` (2 lines; nothing else moved -- Forever has no bloom id, and its heals carry the cast ids). |

## Tests first

The first commit (`d0d0611`) is the tests alone on the parent's code.

**`practice` (tbc) on the parent's `Engine/Practice.lua`:** rc 1, 81 ok, 2 failed --

```
the stream names every roster index and every spell its own events carry FAIL - spell 33778
...and carries a threatOn table, empty: practice has no threat FAIL - nil, 0 threat events
```

`names` was already written (since v0.15.0), but only for cast ids: Lifebloom's bloom arrives under
33778, which no cast carries, and was unnamed. `threatOn` was absent.

**apicheck rule 10 on the parent tree** (`git archive 8c4cc93`, this branch's `apicheck.py`
pointed at it with `--root`): rc 1, 5 findings --

```
FAIL Engine/Practice.lua:150 MD.API.client read outside Client/ and UI/Dump_Forever.lua (a flavour installs a policy)
FAIL Engine/Practice.lua:1536 MD.API.client read outside Client/ and UI/Dump_Forever.lua (a flavour installs a policy)
FAIL UI/BindingsWindow.lua:287 MD.API.client read outside Client/ and UI/Dump_Forever.lua (a flavour installs a policy)
FAIL UI/BindingsWindow.lua:299 MD.API.client read outside Client/ and UI/Dump_Forever.lua (a flavour installs a policy)
FAIL UI/PracticePanel.lua:427 MD.API.client read outside Client/ and UI/Dump_Forever.lua (a flavour installs a policy)
apicheck: 8 Forever TOCs, 48 files, 47 distinct globals, 5 findings (baseline 69893)
```

**The parent's `apicheck.py --selftest` on the new fixture:** `12 of 12` (it has no rule 10), so
`tools/check.sh` fails it on the count once `expected-counts.json` says 13.

**Mutation on this branch** (reverted): Kit_Forever's `MD:Provide("PracticePolicy", ...)` commented
out, so Forever runs the TBC default -- `practiceforever` 17 ok, **11 failed** (among them `a Forever
practice record carries the book's kit ...` `client=tbc`, `on Forever nothing is bound until you bind
or import` `n=6`, `the TBC author's defaults saved on Forever are dropped once`, `a bind for a spell
not in your spellbook is not shown and casts nothing`, `a new binding row picks a spell you have`)
and `importcheck` fails its byte-equal fixture. The seam is load-bearing on Forever and read nowhere
else.

After: `practice` 83 ok, 0 failed; `apicheck` 0 findings; `apicheck --selftest` 13 of 13.

## Suites (`make check`, exit codes checked)

| suite | before (8c4cc93, `tools/data/expected-counts.json`) | after |
|---|---|---|
| `practice` (tbc) | 81 | **83** |
| `apicheck.py --selftest` | 12 | **13** |
| `practiceui` (tbc), `practiceforever`, `bindscheck` (the plan's equal counts) | 52, 28, 6 | 52, 28, 6 |
| `importcheck` | 21 | 21 (after the fixture rebuild; 20 / 1 failed before it) |
| every other suite | as `expected-counts.json` | all equal, all rc 0 |
| `apicheck.py` | 0 findings (47 globals) | 0 findings (47 globals) |
| `textcheck.py` / `--selftest`, `refcheck.py --selftest` | 0 / 2 / 2 | same |

`make check`: `check: 60 run(s), all passed`, with the two NOTE lines for `practice/tbc` 83 and
`apicheck-selftest` 13. `luac -p` passes on `Engine/Practice.lua`, `UI/PracticePanel.lua`,
`UI/BindingsWindow.lua`, `Modules/SpellTuner_Replay/Kit_Forever.lua`, `tools/practice.lua`.

**Output, not only counts.** The parent tree and this branch were each run through the TBC suites of
plan section 2 plus `practiceforever`, `bindscheck` and `wincheck`, and the outputs diffed (root path
normalised). `dashui`, `navui`, `practiceui`, `replaycheck`, `runcheck`, `regencheck`, `spelltip`,
`consolecheck` (tbc), `simwindow`, `restcheck`, `importcheck`, `bindscheck` and `wincheck` are
byte-identical. `reviewui`, `replayui`, `reccheck`, `simcheck`, `solvercheck` and `practiceforever`
differ only in `N ms`, the coach's time-sliced `search N evaluations` (and, in `replayui`, which of two
concurrent searches finishes first -- three parent runs alone show the same spread), memory per run
and table addresses.

## TBC

Shared files. What a TBC player sees does not change: the policy's TBC value is exactly what
`OnForever() == false` did (the author's Cell defaults, no hidden bindings, the static kit never
rebuilt, `Defaults` shown), and `rec.client` stays `"tbc"`. What a TBC practice recording carries
changes by two fields: `threatOn = {}`, and `names` also names the bloom id (33778 ->
`"Lifebloom bloom"`) -- everything else in `names` was already there, since every heal and tick
carries its cast's id. Old recordings are left as they are (nothing reads `threatOn` from a practice
record; a missing `names` entry reads as it always did). The DECISIONS entry below says so.

## Integrator lines

**docs/DECISIONS.md** (one entry, after T58's):

> ## Practice is a policy the flavour installs; its recording carries FightRecorder's fields (2026-09-30, T59)
>
> `Engine/Practice.lua` no longer asks which client it runs on. `MD.Practice.policy` --
> `defaultBinds`, `kitIsLive`, `client` -- is TBC's by default (the author's Cell click-casting, the
> static kit, `"tbc"`), and `Modules/SpellTuner_Replay/Kit_Forever.lua` provides Forever's
> (`MD.PracticePolicy`: no bindings, the live spellbook kit, `"forever"`); the panel and the bindings
> sheet read it, and apicheck rule 10 refuses `MD.API.client` outside `Client/` and
> `UI/Dump_Forever.lua` (review A6a). A practice recording now writes `threatOn = {}` (practice has no
> threat) and names every spell id its own events carry, the bloom's 33778 included (review A30).
> Nothing a TBC player sees changes; recordings already stored are left as they are.

**CLAUDE.md**:

- `Engine/Practice.lua` row, append before the closing ` |`: ` **T59 (P15):** what differs between
  the lines is `PR.policy` (`defaultBinds`, `kitIsLive`, `client`), TBC's by default, Forever's
  provided by `Kit_Forever.lua` as `MD.PracticePolicy` -- no client check in the file; its escape is
  `MD.Text.EscASCII`; a recording carries `threatOn = {}` and `names` for every own spell id (the bloom
  included).`
- `UI/BindingsWindow.lua` row, append: ` **T59 (P15):** `+ binding` and `Defaults` read
  `MD.Practice.policy` (`kitIsLive`; `Defaults` hidden when the policy ships none).`
- `UI/PracticePanel.lua` row, append: ` **T59 (P15):** Start's "no healing spell in your spellbook"
  refusal reads `PR.policy.kitIsLive`.`
- `Modules/<Name>/` row, after the **T15** sentence: ` **T59:** `Kit_Forever.lua` also provides the
  practice policy (`MD.PracticePolicy`: no default bindings, the live kit, `"forever"`).`
- `tools/` row, after the `python3 tools/apicheck.py` sentence: ` Since T59 it also refuses
  `MD.API.client` read outside `Client/` and `UI/Dump_Forever.lua` (rule 10).`
- The "Verifying changes" paragraph, after "Nothing on a Forever TOC registers
  `COMBAT_LOG_EVENT_UNFILTERED`, not even under `pcall`.": ` Nor does a shared file branch on
  `MD.API.client`: a flavour difference is a value the flavour installs (T59).`

**docs/TOOLS.md**, the `apicheck.py` paragraph: `(10 findings since T13a, 12 since T57)` becomes
`(10 findings since T13a, 12 since T57, 13 since T59)`, and after the T57 sentence (`...rule 9: no
RegisterEvent outside Client/ and Core.lua (T57); --selftest 12.`) add: `Since **T59**, rule 10: the
client's name (`API.client`, `API["client"]`) read outside `Client/` and `UI/Dump_Forever.lua` -- a
flavour difference is a policy the flavour installs, never a branch in shared code; --selftest 13.`
In the `practice.lua` row of section 1, append before the closing ` |`: ` Since **T59** (83): the
stream names every own spell id (the bloom's included) and carries an empty `threatOn``.

**tools/data/expected-counts.json**: `"practice/tbc": 83`, `"apicheck-selftest": 13` (or
`tools/check.sh --write-counts` after the merge).

**TOCs**: none (no file added or moved).

**docs/HISTORY.md / docs/TESTING.md**: nothing in game to test beyond what T24/T27 already ask
(Forever: no default bindings, `Defaults` hidden, a Lifebloom binding hidden); the integrator's wave
entry may cite this task.

## Deviations

1. **The policy has a third field, `client`.** The plan names `{ defaultBinds, kitIsLive }`, but
   `Session:Finish` stamped `rec.client = MD.API.client`, which rule 10 forbids in this file; the
   stamp is the flavour's, so it went into the policy (`"tbc"` / `"forever"`, the values the stamp
   had on each client). `tools/import.lua` reads `rec.client == "forever"` to identify a Forever file;
   `importcheck` holds it (the regenerated fixture still says `forever`).
2. **Kit_Forever provides `MD.PracticePolicy`, not `MD.Practice.policy` directly.** The Replay module
   loads before the Practice module, and creating `MD.Practice` there would make every "is the Practice
   module loaded" test (`MD.Practice and MD.Practice.Get`, `.List`, `OpenPractice`) true with the
   module off. `Engine/Practice.lua` adopts it: `MD.Practice.policy` is the one the rest reads.
3. **`names` was not missing.** Practice has written `names` since v0.15.0, for the cast ids. The new
   assertion found the real gap -- the bloom's own id (33778), which no cast carries -- and the writer
   now names every id its own events carry. "Names for every roster index" in the plan is read as
   both: every roster entry has its name (it had) and every own spell id is named.
4. **Two files outside the table**, both data owned tools read: the apicheck fixture
   (`tools/data/apicheck-fixture/Bad.lua`, `Client/Ok.lua` -- the selftest's +1 cannot exist
   without them) and the generated `tools/data/import-forever-sv.lua` (importcheck's byte-equal guard
   of the persisted shape fails until it is rebuilt with `tools/run.sh tools/importfixture.lua`,
   exactly because A30 changes that shape: `+ ["threatOn"] = {}` twice). No other wave-6 task owns
   either.
5. `tools/practiceui.lua`, `tools/practiceforever.lua`, `tools/bindscheck.lua`: unchanged (equal
   counts, as planned).
