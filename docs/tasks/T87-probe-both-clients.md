# T87 -- the probe on both clients, and five sections for the next round

Status: **built** 2026-10-01 on branch `next/T87` (base `e2b13f4`), wave N1, awaiting the
integrator. Spec: `docs/SPEC-next.md` section 11 row T87, decision 22 (9.1: as recommended),
5.3, 6, 7.5, 4.2 P1 / P3 / P4, risks X8 and X10, in-game check 12.1.

Files: `Client/Probe.lua`, `tools/probecheck.lua`, `tools/stub_art.lua` (new),
`tools/slashcheck.lua`. No TOC, no `CLAUDE.md`, no `docs/*` other than this file, no
`tools/check.sh`, no `tools/data/expected-counts.json` edited: their lines are below.
No default registered (`defaultscheck` unchanged: tbc 49, forever 52).

## What was built

### The probe on the TBC line (`Client/Probe.lua`)

- **`/md probe` (`/st probe`) is a hidden row on TBC** (`MD:AddCommand(..., not OnForever())`),
  as TBC's `help` and `unlock` are: the TBC help and the About tab keep their 27 rows. Forever's
  help lists it as before.
- **Forever-only sections print one line, `absent (Forever only)`**, on any client whose TOC
  marker is not Forever's (`MD.API.client`, read in `Client/` only): `== secrets now`, the
  `== spells` walk (`slots 1-500: absent (Forever only)`; the header with bonus healing stays),
  `== spells against the previous run`, `== talents`, `== shapes`, `== damage meter`, the new
  `== auras`, and `book cooldown` inside `== cooldowns`. Q1-Q8 and the macro to-do become one
  line, `Q1-Q8: Forever questions, absent on this client`; Q9 (the TOC) and the esc to-do stay.
  Everything else (client, functions, events, blocked actions, readings, the 2-s combat
  snapshot, events seen, unit combat tokens, saved variables, toc, windows) answers on TBC as
  it does on Forever, each missing function reading `<absent>`.
- **ManaDemon's adoption kept** (found by running `migrate/tbc` with the probe on the TBC TOC):
  the probe's `ADDON_LOADED` made `SpellTunerDB = {}` before `Core.lua`'s `PLAYER_LOGIN`
  adoption, which adopts `ManaDemonDB` only while `SpellTunerDB` is nil -- every ManaDemon
  setting and recording would have been dropped. When `SpellTunerDB` is nil and `ManaDemonDB` is a
  table, the probe now keeps its record on `ManaDemonDB`, the table about to become
  `SpellTunerDB`. Forever's TOC lists no `ManaDemonDB`, so Forever is unchanged.

### Five new sections, between `== windows` and `== to do`

Each built under its own `pcall` (a raise is one `<error: ...>` line, never a lost report), every
call under `pcall`, every result a string, `IsSecret` before anything but storing; a client value
handed to a texture or a font string goes straight from the call into the setter.

| Section | Lines |
|---|---|
| `== art` (5.3) | `GetFileIDFromPath present, C_Texture.GetAtlasInfo absent`; per file the styles name (31: Classic's and Modern's plain files from 5.1 / `R-styles` 5.1, the broker icon, the probe box's fill) `file <path> id=<n / absent / <absent>> set=<SetTexture's return> get=<GetTexture after it>` (the texture cleared first); per atlas (Modern's `Options_List_Hover` / `_Active`, the `128-RedButton` pieces under both centre spellings, `RedButton-Exit`, EllesmereUI's two) `atlas <name> file=<id> <w>x<h>` / `absent` / `<absent>` |
| `== hosts` (6) | `addon <name> loaded=<..>` and `version=<..>` when loaded, else `reason=<GetAddOnInfo's reason>` (MISSING, DISABLED) -- no metadata read of an addon that is not there -- for EllesmereUI, its DataBars / Minimap / BlizzardSkin, ElvUI, Titan, ChocolateBar; `EllesmereUI present: RegisterSkin present, RegisterUnlockElements ..., MakeUnlockElement ..., GetAccentColor ..., GetFontPath ...` or `EllesmereUI absent`; `ElvUI present|absent`; `LibStub present minor=<n>` and `lib <LibDataBroker-1.1 / CallbackHandler-1.0 / LibSharedMedia-3.0> minor=<n> / absent`. Hosts are reached by name through `MD.API.Has` (no global held; apicheck rule 11, when it lands, sees no `EllesmereUI` / `LibStub` identifier here) |
| `== clock` (7.5) | `Q-clock-1 colour curve: value <shape>, SetVertexColor <ok / error>, read back <secret / plain v>` (a `C_CurveUtil.CreateColorCurve` with two `CreateColor` points, `SetType(Enum.LuaCurveType.Linear)` where that constant reads, `UnitPowerPercent("player", 0, false, curve)`, its `GetRGB()` handed straight to a hidden texture); `Q-clock-2 percent as text: SetText ok, GetText <secret / plain>, width <..>` (`UnitPowerPercent` handed unread to a hidden font string); `Q-clock-3 ColorPickerFrame <present>, SetupColorPickerAndShow <..>, SetColorRGB <..>`; `Q-clock-4 texture <UI-StatusBar / Raid-Bar-Hp-Fill> id=.. set=.. get=..`, `Q-clock-4 font <FRIZQT__ / ARIALN / skurri / MORPHEUS> set=<SetFont's return> get=<GetFont's face>`, `Q-clock-4 rotation SetRotation(0.5) <..>, GetRotation <..>` |
| `== cooldowns` (4.2 P1 / P3) | `GetSpellBaseCooldown`, `C_Spell.GetSpellCooldown`, `GetSpellCooldown` on Swiftmend 18562 and Holy Shock 20473; Forever: the book's first two spells whose base cooldown reads plain above 0 (else whose tooltip has a right text naming a cooldown) as `book cooldown <id> <name> <rank>: base <ms / not read>`, the first one's tooltip lines whole; `UnitGetTotalAbsorbs(player / party1)` now and `... in combat` from the snapshot; `UNIT_COMBAT <phase> action=<a> descriptor=<d> n=.. amount readable=.. secret=..` (a new counter beside the old ones, so a hit into a shield is seen by its action and descriptor) |
| `== auras` (4.2 P4, X8; Forever only) | `C_Secrets.ShouldAurasBeSecret() now = .. (in combat: ..)` and `... in combat = ..` from the snapshot; `helpful auras on you: N, mana sources M, secret names S, secret rows R`, then each mana source (Innervate, Mana Spring, Mana Tide, (Greater) Blessing of Wisdom, by its plain name) and each row whose name is secret, at most 8: `aura <i> [mana source]: id=.. name=.. duration=.. expires=.. source=..`, each field `<secret>` where it is; the same scan taken in the 2-s combat snapshot, prefixed `in combat: ` |

Two Forever to-do lines, gone once answered: `auras to do: ...` until the combat snapshot saw a
mana source on the player, `absorb to do: ...` until a `UNIT_COMBAT` action or descriptor named
`ABSORB`.

### `tools/stub_art.lua` (new, not a suite)

Loaded by `probecheck` only, after `wowstub.lua` and its profile: textures (`SetTexture`
answering true for a known file, `GetTexture` its id), `GetFileIDFromPath` (or absent),
`C_Texture.GetAtlasInfo` (or absent), `SetAtlas`, `SetVertexColor` / `GetVertexColor` (secrets kept
secret), `SetRotation` / `GetRotation` (or absent: `false`, since a stub frame answers every
unknown method with a no-op), `SetFont` answering true for the four built-in faces, the colour
curve (`UnitPowerPercent` with a curve answers a colour whose `GetRGB` is three secrets), and
`ColorPickerFrame` "modern" / "classic" (a plain table, so "classic" truly lacks the method).

### `tools/probecheck.lua`, now both flavours

`HARNESS_FLAVOUR = { "forever", "tbc" }`. Step 1 (the TBC line, 2 checks) runs in both (forced).
**Under forever:** every existing step (the 88 that ran keyed `probecheck/tbc` were Forever steps
all along), the visible-row check in step 14, and step 15 (15a: every function the new sections
ask about, a fight with a hit into a shield and an Innervate whose fields go secret; 15b: none of
them). **Under tbc:** step 1, then the TBC line's own file list (the harness's filter) with
`Client/Probe.lua` appended where the TOC will list it -- the TOC's own list once it does --
under the stub's TBC profile (no `C_Secrets`, `C_SpellBook`, `C_TooltipInfo`, `C_DamageMeter`,
`C_UnitAuras`), ElvUI loaded, a borrowed LibStub with LDB, `ManaDemonDB` waiting for adoption,
a fight with the 2-s snapshot; then the run ends with its own footer.

New checks, forever (+9): the probe row stays listed on Forever; the five sections in order and
none raising (15a, 15b); `== art`; `== hosts`; `== clock`; `== cooldowns`; `== auras`; with none
of the functions every new line reads absent; ASCII / no bare pipe and the two to-dos going once
answered.

tbc (13 new, 15 with step 1): loads with the probe, client `tbc`; `/md probe` a hidden row, the
help not naming it; `/md probe` runs and saves keyed by build; no section raises (every header
in order, no `<error` anywhere); the Forever-only sections and questions read absent; `== art`
for the TBC paths, atlases absent; `== clock` Q-clock-3/4 answered, the curve and the secret
text absent; `== hosts` with ElvUI and LibStub, EllesmereUI MISSING; `== cooldowns` base
cooldowns and a hit by action; the combat snapshot on TBC; ManaDemon still adopted; ASCII; the
timers all ran on the clock.

### `tools/slashcheck.lua` (+2)

Loads `Client/Probe.lua` after the harness while the TBC TOC does not list it, so the golden
transcript is compared with the probe in place: **the help and the About rows are unchanged,
the golden is not re-based**. Two checks: `/md probe` is a hidden row with usage `/st probe`;
`/md probe` runs and says `SpellTuner probe: build ...`.

## Failing first (the parent's `Client/Probe.lua`, the new tests and stub in)

```
tools/run.sh --flavour forever tools/probecheck.lua    89 ok, 8 failed  (every step-15 check)
tools/run.sh --flavour tbc tools/probecheck.lua         7 ok, 8 failed  (hidden row, sections,
                                                                         absent, art, clock, hosts,
                                                                         cooldowns, ManaDemon)
tools/run.sh --flavour tbc tools/slashcheck.lua         5 ok, 5 failed  (the help, the bare pass
                                                                         and the About tab grew a
                                                                         probe row; the row hidden)
```

The checks that pass on the parent guard what must not move: Forever's visible row, step 1,
the TBC load, the save keyed by build, the TBC combat snapshot, ASCII, the clock's timers.

## Suites, before and after

| suite | before | after |
|---|---|---|
| `probecheck/tbc` | 88 (the Forever steps, keyed tbc) | **15** (step 1 + 13 TBC checks) |
| `probecheck/forever` | -- (not run) | **97** (the 88 + 9) |
| `slashcheck/tbc` | 8 | **10** (+2) |
| every other suite | unchanged | unchanged |

`make check` with the integrator's `stub_art` NOT_SUITES line and the three counts applied
(a temporary copy of `tools/check.sh`, then removed): **73 run(s), all passed**, 68 counted
against 68 expected; apicheck 60 files, 48 globals, **0 findings**; textcheck 0 findings;
`luac -p` clean on the four files.

**And with the TOC line applied** (`Client\Probe.lua` last on `SpellTuner_TBC.toc`, plus the
corecheck line below), the whole check again: **73 run(s), all passed** -- `migrate/tbc` 7,
`corecheck/tbc` 24, `slashcheck/tbc` 10, `probecheck/tbc` 15 (now from the TOC's own list),
`releasecheck` (the TBC package carries `Client/Probe.lua`), every TBC suite loading the probe.
Both applied lines were then reverted.

## Integrator lines

**`SpellTuner_TBC.toc`:** a last line, after `Engine\ReviewCommands.lua` (the Forever TOCs list
it last):

```
Client\Probe.lua
```

**`tools/check.sh`:** `stub_art` in `NOT_SUITES` (it is a stub extension, not a suite; without it
check.sh runs it and fails it for having no footer):

```
NOT_SUITES=" harness wowstub stub_art fakepull foreverfixture import ..."
```

`probecheck` needs no check.sh line to run under tbc: its `HARNESS_FLAVOUR = { "forever", "tbc" }`
is what check.sh reads.

**`tools/data/expected-counts.json`:** `"probecheck/forever": 97,` (new), `"probecheck/tbc": 15,`
(was 88), `"slashcheck/tbc": 10,` (was 8).

**`tools/corecheck.lua` (T113's file this wave), with the TOC line and not before:** `"probe"`
at the end of `VERBS.tbc.names` (the list of every TBC verb, hidden ones included); without it
`corecheck/tbc` fails `unexpected: 'probe'` once the TOC lists the probe. Count unchanged (24).

**`docs/DECISIONS.md`** (decision 22):

> **The probe on TBC (T87, decision 22, 2026-10-01).** `Client/Probe.lua` is on
> `SpellTuner_TBC.toc` (its last file): `/md probe` (`/st probe`) as a hidden row, the report
> saved in `SpellTunerDB.probe` keyed by build as on Forever. On TBC the sections that only ask
> Forever's questions (secrets, the spellbook walk and its comparison, talents, shapes, the
> damage meter, auras) and Q1-Q8 print `absent (Forever only)`; the rest answers there. Visible
> TBC change: none in the help or the About tab; the probe listens to the same events it does on
> Forever (blocked actions, UNIT_COMBAT, cast events, the regen events, its 2-s combat snapshot).
> With ManaDemon's saved variables still waiting for adoption, the probe's record goes on
> `ManaDemonDB` so the adoption still runs.

**`CLAUDE.md`, the `Client/Probe.lua` row,** append:

> **T87** (`docs/SPEC-next.md` decision 22): on both TOCs -- on TBC `/md probe` is a hidden
> row and the Forever-only sections (secrets, the spellbook walk and its comparison, talents,
> shapes, the damage meter, auras, Q1-Q8) print `absent (Forever only)`; with `ManaDemonDB`
> waiting for adoption the record goes on it. Five sections between `== windows` and `== to do`:
> `== art` (every file and atlas a style names: `GetFileIDFromPath`, a hidden texture's
> `SetTexture` / `GetTexture`, `C_Texture.GetAtlasInfo`), `== hosts` (EllesmereUI and its modules,
> ElvUI, Titan, ChocolateBar loaded / version / GetAddOnInfo's reason, EllesmereUI's
> `RegisterSkin` and unlock entry points, LibStub and the LDB / CallbackHandler / LSM in it),
> `== clock` (Q-clock-1 a curve colour into a texture, Q-clock-2 a secret into a font string,
> Q-clock-3 the colour picker, Q-clock-4 bar textures, the four fonts, `SetRotation`),
> `== cooldowns` (`GetSpellBaseCooldown` on Swiftmend / Holy Shock, the book's cooldown spell's
> tooltip whole, `UnitGetTotalAbsorbs` out of and in combat, UNIT_COMBAT by action and
> descriptor), `== auras` (Forever: `ShouldAurasBeSecret` out of and in combat, the mana sources
> on you with their fields, plain or secret); `auras to do` / `absorb to do` until answered.

**`CLAUDE.md`, the `tools/` row,** after `tools/probecheck.lua`'s sentence, append:

> Since T87 `probecheck` runs under both flavours (`tbc`: the TBC file list with the probe on it,
> the Forever-only sections absent, ManaDemon's adoption kept) and `tools/stub_art.lua` (not a
> suite) fakes textures, atlases, `GetFileIDFromPath`, `SetRotation`, fonts, the colour curve and
> the colour picker for the suites that load it.

**`docs/TOOLS.md` section 1:** `probecheck` -- flavours `forever, tbc` (was `tbc`), counts 97 /
15; a line for `tools/stub_art.lua` beside the stub (`A.Install(S, opts)`; loaded by
`probecheck`; not a suite).

**`docs/TESTING.md` section 46, check 1** (`docs/SPEC-next.md` 12.1, unchanged): `/st probe` on
Forever, `/md probe` on TBC (new); paste `== art`, `== hosts`, `== clock`, `== cooldowns`,
`== auras` -- Forever once out of combat and once after a fight with an Innervate or Mana Spring
on you (the snapshot reads itself 2 s in), once with EllesmereUI enabled and once without, once
on a priest / shaman / paladin alt of level 10+ with a cooldown heal in the book (a priest:
shield yourself and take a hit, for `absorb to do`); on TBC the Forever-only sections read
`absent (Forever only)` and nothing raises.

**`docs/HISTORY.md`:** one entry for the wave (T87: the probe on both clients, five sections,
ManaDemon's adoption kept with the probe on the TBC TOC).

## Deviations

- **probecheck's counts.** The spec assumed `probecheck/forever` existed (+7). It did not: the
  suite declared `tbc` and its 88 Forever checks ran keyed `probecheck/tbc`. Now
  `probecheck/forever` is 97 (88 + 9) and `probecheck/tbc` 15 -- a smaller tbc number than the
  expected-counts file holds, so the counts line is needed with the merge.
- **No check.sh flavour line** for probecheck (check.sh reads the suite's own declaration); the
  one check.sh line is `stub_art` in `NOT_SUITES`.
- **Host fakes inline in `tools/probecheck.lua`** (a LibStub, EllesmereUI's entry points, addon
  answers), not in `tools/stub_hosts.lua`, which the spec gives to a later task (T92 / T97); the
  probe needed only presence, versions and LibStub's `GetLibrary`.
- **`tools/corecheck.lua` needs one line** (`"probe"` in the TBC verb list) once the TOC lists the
  probe; corecheck is T113's file this wave, so it is an integrator line, not an edit here.
- **The ManaDemon adoption fix** is not in the spec's row; it is what putting the probe on the TBC
  TOC requires (`migrate/tbc` fails without it).
- **`== hosts` asks a version only of a loaded addon** and otherwise `GetAddOnInfo`'s reason
  (MISSING, DISABLED) -- the spec says "presence and versions"; a metadata read of an absent
  addon may raise on the client, and DISABLED is the author's EllesmereUI state.
