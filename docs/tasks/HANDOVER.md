# Lead handover -- WoW: Forever port

Rewritten by the lead after every commit and every hand-out. A successor continues from this file
alone. Worktree: `/home/penek/projects/addons/SpellTuner/.claude/worktrees/manademon-folder-continue-41eabc`,
branch `claude/manademon-folder-continue-41eabc`.

Last updated: 2026-10-03, after the **One UI** round (`docs/SPEC-one-ui.md`; T117-T123, all
landed) and the **0.17.0** commit. 0.17.0 is built, **not installed and not published**: the
packages are in the top-level `dist/manademon-folder-continue-41eabc/` (`tbc/` and `forever/`,
`SpellTuner-tbc-0.17.0.zip`, `SpellTuner-forever-0.17.0.zip`). Both clients run **0.16.8**
(installed 2026-10-02 and published to CurseForge as a beta from d6de018; `dist/.../published.txt`).
The version ruling is `docs/DECISIONS.md` "One version, two installations". Install only on the
author's request:
`./release.sh --install-forever "/mnt/e/Blizzard/World of Warcraft/_classic_beta_/Interface/AddOns"`
and `./release.sh --install-tbc ".../_anniversary_/Interface/AddOns"`; never cross them. Publish
only on the author's word: `secret-env run CURSEFORGE_API_TOKEN -- ./release.sh --publish
--dry-run`, then without `--dry-run` (CHANGELOG.md has the `## 0.17.0` section it sends).

## One UI (0.17.0): what landed, what did not

From the author's "can we make spellbook dashboard in TBC like we did in Forever? and in general
have mostly similar UI in both", the approach "shared pane, I would like to have forever features
in TBC and vice versa TBC feature (like what if) in forever (but make it well designed)", and
"go with your recommendations" for D1-D9 (`docs/SPEC-one-ui.md` section 9; mockup
`docs/mockups/one-ui.html` M1-M6). Seven tasks in four waves, each test first in its own worktree,
integrated here in order. **All seven landed; nothing did not land.**

| task | wave | commits | what |
|---|---|---|---|
| **T117** the book contract | A | 6c2a689 / 6693faf, integrated 535cff4 | `Spells/BookShape.lua` (`MD.BookShape`), `Spells/Coefficients.lua` (RankMath's and DamageMath's goldens equal), Forever's `family` / estimated `bonus` / `calc`, `Book:Pool` / `Book:Bonus`, Words on TBC, the renames `UI/SpellsPane.lua` / `UI/SpellTip.lua` |
| **T118** the TBC book | B | 4f8c08d / 4374411 / 05117c4, integrated d6691fe | `Spells/Book_Model.lua`: `MD.Book` on TBC from `RankMath:Compute({ live = true })`, always live, `Get({ whatIf = true })` the only door to `MD.sim`; the druid's damage; `Spells/Families_TBC.lua` retired |
| **T119** Settings | B | e8aa3fe / bd51052, integrated d6691fe | `UI/Settings.lua` + `MD.SettingsLine` (`UI/Settings_TBC.lua`; `UI/OptionsFrame.lua`, `UI/Options_About.lua` deleted); General / Clock / Review / (Modules) / About in two columns; TBC Settings 860 x 560 |
| **T120** one Spells pane | C | 00c4c2f / 2b85b16, integrated 49494eb | `UI/SpellsPane.lua` on the TBC TOC (`UI/SpellsView_TBC.lua` deleted), `MD.SpellsLine`, TBC's drop / Whole book / Export / full picker, TBC Spells 860 x 560 |
| **T121** one tooltip block | C | 1fa5636 / dfe6d85, integrated 49494eb | `UI/SpellTip.lua` on TBC, the model's derivation as How behind the detail key; `Tip:Spell` / `Tip:Damage` / `Tip:Columns` deleted |
| **T122** What if | D | 525eccf / 96452f4, integrated 4b5683c | `Spells/WhatIf.lua`, `_TBC`, `_Forever`; `Book:MeasureBonus` (`cdb.bonusCounts`); M2's WHAT IF pane; `UI/Dashboard_Simulate.lua` deleted |
| **T123** TBC classes and damage | D | 909e7c0 / 2b1e94b, integrated 4b5683c | T111's swaps finished, `rankTable` / `tooltip` granted to the TBC priest / shaman / paladin (coach / practice / simulate / advisor stay the druid's), class `damage` profile data, `DM.FamiliesFor`; `MD.FamiliesTBC` and `Tip:Row` deleted |

Still UNVERIFIED in game, each asked by `docs/TESTING.md` §49: TBC's drag from the spellbook
(`MD.API.CursorInfo`, 49.1 step 4) and the rank row's game tooltip (`SetTooltipSpell`, 49.1 step
3); every class damage row (VERIFY, 49.2); TBC's +damage header (49.2 step 3, below); Forever's
measured +healing share (49.3 step 4).

## Committed this round (newest first)

| hash | what |
|---|---|
| (the commit after 4b5683c) | 0.17.0 on every TOC (`release.sh --set-version`; the import fixture rebuilt, unchanged); CHANGELOG.md `## 0.17.0`; TESTING §49 (49.1 TBC druid, 49.2 TBC priest / shaman / paladin, 49.3 Forever druid); HISTORY; CLAUDE.md's version prose; this handover; both packages built, nothing installed or published |
| 4b5683c / 2b1e94b / 909e7c0 / 96452f4 / 525eccf | wave D: T122, T123 and their integrator lines |
| 49494eb / dfe6d85 / 1fa5636 / 2b85b16 / 00c4c2f | wave C: T120, T121 and their integrator lines |
| d6691fe / bd51052 / e8aa3fe / 05117c4 / 4374411 / 4f8c08d | wave B: T118, T119 (T118's review fixes) and their integrator lines |
| 535cff4 / 6693faf / 6c2a689 | wave A: T117 and its integrator lines |
| e93d367 | the tasks T117-T123, the spec corrected in place, the lead's corrections (spec section 11) |
| a37813f | the spec `docs/SPEC-one-ui.md` and the approved mockup `docs/mockups/one-ui.html` |
| d6de018 / 7a5de2c / 37227cd | T-publish: `./release.sh --publish`, `CHANGELOG.md` |

## In the tree, not committed

Nothing. The top-level `dist/` (gitignored) holds the 0.17.0 packages beside the older ones.

## Open from the task files (none planned)

- **TBC's `Book:Bonus("damage", school)`** hands `GetSpellBonusDamage` the school's NAME
  (`fam.school`, "Nature"), not the client's school number (T120 deviation 11; `Spells/Book_Model.lua`
  `Book:Bonus`, `UI/SpellsPane.lua` 1598). The header's `+N <School> damage` may read 0 or raise
  into `Live`'s guard. §49.2 step 3 asks; a one-line fix (map the name through `DM.SCHOOL_NAMES`
  or carry the number) once the paste confirms.
- No TBC `IsPassiveSpell` binding (T118 deviation 3): `passive` from the rank text.
- A TBC class's own casts are still labelled `utility` in the end-of-fight labels: `UI/Summary.lua`'s
  capture reads `Data/SpellData.lua` (T123 deviation 8).
- Mind Flay is not read (no channel shape in `DM.Parse`; T123 deviation 1): it lists under Other.
- The three tooltip defaults are registered by `UI/SpellTip.lua` and still declared by both cores
  (T121); `PerSecText` / `CritMult` local to the block, to fold into `Spells/Words.lua` (T121
  deviation 5); comments that still name `UI/SpellsPane_Forever.lua` / `UI/SpellTip_Forever.lua`
  (T117 deviation 9); moving TBC's tooltip hook into `Client/API_TBC.lua` (spec 3.4).
- From before, still standing: T102 deviation 3, T106 deviations 7 and 8, T97 deviation 2, and the
  refactor plan's left-overs (below).

## Waiting on the probe or the author

| task | state | why / what it waits on |
|---|---|---|
| **T103** Modern style | not started | `== art` from both clients (46.1) |
| **T104** Ring clock | not started | `== clock`'s Q-clock-4 from both clients (46.1) |
| **T105** mana sources | not started | `== auras` on Forever (46.1 step 2) |
| **T108** Classic style | not started | `== art` from both clients; `docs/research/next/R-classicui.md` is its input |
| **T109** absorbs | not started | the absorb lines of `== auras` (46.4 step 1, a priest) |
| **T110's remainder** | waits | T105's seam (`docs/tasks/T110-non-healer-extras.md` "Left for after T105") |
| **T111's cap grant** | **done by T123** | `rankTable` / `tooltip` granted; coach / practice stay the druid's on TBC (D7) |
| **T112** two-line clock | not scheduled | decision 13 |
| `MD.API.BASE_CD_READS` flip | off | `== cooldowns`' `GetSpellBaseCooldown` lines (46.1) |
| Forever's real Mana % / Mana, bar textures | off | Q-clock-2 (`POWER_TEXT_READS`), Q-clock-4 (46.1) |

## Next, in order

1. **The author installs 0.17.0 (on request) and runs `docs/TESTING.md` §49**: 49.1 a TBC druid
   (the 860 x 560 window, one spell's page against 0.16.8's numbers, the rank row's tooltip, the
   picker with DAMAGE and the spellbook drop, Whole book and Export, After overheal and the rolled
   rows, What if, the tooltip block and its detail key, Settings), 49.2 a TBC priest / shaman /
   paladin (heals and damage switched on, the +damage header against the character sheet, the
   coach still refused), 49.3 a Forever druid (the header's +healing, What if with the estimated
   share, the measured share after a gear swap, the How lines, Settings). Pastes:
   `.logs/tbc/0.17.0-s1.md`, `.logs/tbc/0.17.0-s2.md`, `docs/probe/<build>-0.17.0-s1.md`. A task
   per failed check, from the paste only; the +damage school first if 49.2 step 3 fails.
2. **Publish 0.17.0** on the author's word (above).
3. **The probe, still pending: §46.1 on both clients** -- unblocks T103, T104, T105, T108, T109,
   the `BASE_CD_READS` flip, Q-clock-2 / Q-clock-4, then T110's remainder.
4. §48 (clock v2) on 0.16.8 / 0.17.0 if not yet run; then 46.2-46.7 and §45; the older §38-§44
   items, the "Measured" line, pair mode, decision 12 of the UI spec; M5 of the roadmap (launch
   client, 2026-11-04).

Suite loop: `make check` (`tools/check.sh`; docs/TOOLS.md section 1) -- every suite under its
flavours, apicheck, textcheck, the selftests and the expected counts in
`tools/data/expected-counts.json`. A new or changed count goes into that file in the same commit.
`importcheck`'s fixture does not embed the version (T54); rebuild it with
`bash tools/run.sh tools/importfixture.lua` whenever what is stored changes (a new default does).
`releasecheck` in a `git archive` export needs a throwaway `git init` there.

## Baselines (at the 0.17.0 commit)

`make check`: 101 runs, all passed; 96 counted against 96 expected (profilecheck/forever's expected
count is 64, the run with `tools/.cache/talentsforever.json`; without the cache it runs 59 and the
counts fail until `python3 tools/refcheck.py --fetch`). TBC: adaptercheck 19, bookcheck 2,
bookshapecheck 18, capscheck 36, clockfacecheck 24, clocksettings 46, clocktextcheck 13, clockui
41, consolecheck 1, corecheck 29, costcheck 3, dashui 67, defaultscheck 49, kitcheck 5, migrate 7,
minimapcheck 8, navui 46, practice 84, practiceui 56, probecheck 15, profilecheck 55, reccheck 63,
recordingscheck 32, regencheck 27, replaycheck 82, replayui 110, restcheck 51, restylecheck 50,
reviewui 50, runcheck 81, settingscheck 12, simcheck 13, simwindow 8, slashcheck 10, solvercheck
95, spellsui 16, spelltip 35, stylecheck 34, surfacecheck 36, svcheck 1, tabscheck 7,
tbcclasscheck 63, themecheck 9, timeline 27, ttocheck 53, verifycheck 14, whatifcheck 8, wincheck
4. Forever: adaptercheck 26, bindscheck 6, bookcheck 32, bookshapecheck 10, capscheck 32,
classcoach 39, clockcheck 37, clockfacecheck 21, clocksettings 47, clocktextcheck 13, clockui 41,
coachforever 22, consolecheck 22, corecheck 29, defaultscheck 52, euicheck 21, forevercheck 16,
gatecheck 12, kitcheck 19, measurecheck 30, minimapcheck 9, modulecheck 19, parsecheck 42,
practiceforever 31, probecheck 97, profilecheck 64, recordcheck 31, recordingscheck 32,
replayforever 28, restylecheck 45, reviewforever 22, scenariocheck 19, settingscheck 10, spellsui
57, stylecheck 34, surfacecheck 43, svcheck 6, tabscheck 27, themecheck 38, tipcheck 53,
whatifcheck 7, wincheck 66. importcheck 21, releasecheck 38, lib/t 12. apicheck 0 findings (8
Forever TOCs, 78 files, 51 distinct globals), apicheck selftest 14, textcheck 0 findings over 118
files (9 TOCs), textcheck selftest 2, refcheck selftest 2; reproduce and strategies smoke runs ok.
Packages (`make release SRC=manademon-folder-continue-41eabc`): TBC 90 files, Forever 53 files
plus the three modules (`SpellTuner-tbc-0.17.0.zip`, `SpellTuner-forever-0.17.0.zip`). Not
installed, not published.

## Before this round: clock v2 (0.16.8)

From the author's answers to `docs/mockups/clock-v2.html`, verbatim: "We can do all 3, and let
user decide / And those that are recomended become default" (`docs/DECISIONS.md` "Clock v2: mana
and the five-second rule together" and "Clock v2: what the clock says"). All three tasks landed;
**nothing did not land**.

| task | commits | what |
|---|---|---|
| **T114** the face's slots and words | 63ec215 / 56c58b3, integrated ad4a02f | `Engine/ClockFace.lua`: `CF.KINDS`, `CF.TEXT` (Line Left / Main / Right / Right2, Compact Top / Main / Bottom, Bar Left / Right), `CF.ResolveText`; the face's `mana` / `manaMax` / `manaModelled`; the datatext and brokers follow Line's slots, byte-identical by default; Forever's `MD.API.DrawPowerText` behind `POWER_TEXT_READS = false` (Q-clock-2) |
| **T115** Bars and Frame | 34aa2d4 / 182f513 / 18fd3b6, integrated ad4a02f | Mana + 5SR by default on both lines (replaces decision 15 (a)); Join Stacked (A, default) / One bar (B) / Swipe chip (C); Order, Mana from (Forever), the strip, After the rule (Green / Empty, Regen tick TBC only), texture (Forever flat until Q-clock-4), Mana colour; Frame Width / Height / Scale per layout with measured minimums; `CV.Migrate` reads a 0.16.6 / 0.16.7 look once (`docs/tasks/T115-clock-bars-frame.md`'s table) |
| **T116** the slots drawn, the Text tab | 02ae0ec / 1a547d0, integrated 137599f | `UI/ClockView.lua` draws the slots at fixed places, Size 8-32 / Outline / Shadow / Numbers, the minimum from the slots set, Right2 only where the width allows; `UI/ClockSettings.lua`'s Text tab replaces Show |

Still VERIFY in-game: the Swipe chip's cooldown template (both clients), the regen tick lining up
with the mana ticks (TBC). Waiting on the probe: Forever's real Mana % / Mana (Q-clock-2), Forever's
bar textures (Q-clock-4). `docs/TESTING.md` §48 checks all of it, one session per client.

### Committed in the clock v2 round and the next round (newest first)

| hash | what |
|---|---|
| (the commit after 137599f) | 0.16.8 on every TOC (`release.sh --set-version`; the import fixture rebuilt, unchanged); TESTING §48 as one session per client; HISTORY; CLAUDE.md's version prose; this handover; both packages built, nothing installed |
| 137599f / 1a547d0 / 02ae0ec | clock v2 second half: T116 and its integrator lines |
| ad4a02f / 18fd3b6 / 182f513 / 34aa2d4 / 56c58b3 / 63ec215 | clock v2 first half: T114, T115 and their integrator lines |
| 2f6ac63 | clock v2: the approved mockup (`docs/mockups/clock-v2.html`) and its tasks |
| 6fab263 / 6e1f56b / 9e20ef2 / 2e1f6bb / eadd789 / 90f5cf9 / c71ad2d | 0.16.7: the author's first 0.16.6 feedback (F1 the clock bar's Height and a smooth 5SR, F2 no GCD sweep after a hard cast, F3 Whole book drawn at once); TESTING §47 |
| 2ffece3 | the finish at 0.16.6 (version kept): TESTING §46 for waves N1-N5 (the intro, 46.4 step 4 after T106, 46.6 / 46.7 in the packages, T97 deviation 3 closed), HISTORY, this handover; the import fixture rebuilt, unchanged; both packages rebuilt |
| ee840e0 | wave N5 integrator (TBC TOC: the priest / shaman / paladin TBC profiles, `Spells\Parse.lua`, `Spells\Book_TBC.lua`; counts; CLAUDE.md, TESTING 46.7, DECISIONS, TOOLS) |
| 3be8632 / 2e75430 / fa3d24f | T111 review: the five rejections as failing tests, then TBC non-druids unchanged until the caps are granted (profiles grant `clock` only), `ClassContext` / `DruidContext`, `SpellKit` the druid's for every class; tbcclasscheck 52 |
| 35eeeec / 0d65533 / c445021 / 434d466 | T111 (decision 8 (b)): `Spells/Book_TBC.lua` (bases from each rank's tooltip), the class rules in `Engine/RankMath.lua` (VERIFY), the three TBC class profiles, twelve TBC adapter bindings, the WCL fit with a class |
| fde54a5 / 8c02f1c / c44dc17 | T110 (P6, partial): the list seeded by role (`Tabs:Role`, `SeedList`), either-or halves (`Book:Half`), the tooltip's role half and `Or heals` / `Or damage`, inert MAGE / WARLOCK mana-cooldown rows; tabscheck 27, bookcheck 31, tipcheck 52 |
| 4ff42bf | wave N4 integrator (TOC lines for `UI\ClockSettings.lua` and the three Forever class profiles; T107's lines 1 and 2: `UI.Restyle.LEFT = {}`; the import fixture: `useClassColour`) |
| e391b4e / fe7124f / ce265eb | T107 (decision 4): live restyle -- `UI.Tint`, `UI.FollowTokens`, `UI.Restyle`; restylecheck 44 / 49 (new) |
| 690742c / 9ac10c3 / 1baf1e9 / a94ddd4 | T106 (decision 7): Paladin / Shaman / Priest Forever profiles, the solver-only coach for non-druids (`SP.SolverOnly`, `SP.SOLVER_COACH`, `SP.Unmodelled`); classcoach 39 (new), profilecheck 64 (cached) / 45 |
| 1ad3d2a / 1c083ed / facd7f5 | T102: Settings -> Clock (`UI/ClockSettings.lua`), the Look dropdown with Use my class colour, INTEGRATIONS, `/st clock layout / look reset / preview`, `MD.ClockLook`; clocksettings 34 / 35 (new) |
| 7da7943 | 0.16.6 on every TOC (`release.sh --set-version`; the import fixture rebuilt, unchanged -- fixed version since T54; no other fixture embeds the version); CLAUDE.md's intro at 0.16.6; TESTING §46 rewritten as five sessions for what landed (46.1 the probe on both clients first); HISTORY; this handover |
| 35275c7 | docs: `docs/research/next/R-classicui.md`, the ClassicUI web study (feeds T108's Classic style) |
| 319f6cb | wave N3 integrator (TOC lines, `MD.EUIParent` in `Integrations/EllesmereUI_Forever.lua`, the import fixture: `clockLook`, `eui`, `feeds`) |
| 432a5f0 / ac1c91e | T101 (decision 12): the generic Forever kit -- group / chain / selfAndTarget, the solver's sums, N same-instant claims, own heals replayed as recorded; kitcheck 19, solvercheck 95, scenariocheck 19, practiceforever 31 |
| f565809 | T99 (4.4): capability gates -- `MD.ClassProfile:Can(cap)`, `<subject>: not modelled for <Class> yet`; capscheck forever 32 / tbc 34 (new) |
| 059f262 / aae4a47 | T100: the Ellesmere style (`UI/Style_Ellesmere.lua`, the clone and the follow), a style's `resolve`; stylecheck 34 / 34 |
| 03b99bf / be9ba22 / ae39dc7 | T98 (decisions 13, 15): Compact and Bar clock layouts, `db.clockLook`, the bar's sources and the 5SR spark; clockui 16 / 16 (new), clockfacecheck 22 / 19 |
| 5ed4e6c / a171086 / 2055e3d | T97 (decisions 19, 20, X1): the LDB brokers (`Integrations/Surface_LDB.lua`), EllesmereUI's skin, mover and version guard (`Integrations/EllesmereUI_Forever.lua`), apicheck rule 11; euicheck 19 (new) |
| 25748e3 | wave N2 integrator (TOC lines, stylecheck's clock golden re-based on 546e729, the import fixture) |
| c6f26bc | T96 (decision 11): the kit carries its profile, the engine's HoT slots and cooldowns from it, a channel lands its ticks, `MD.KitLive`; kitcheck 16 / 5, scenariocheck 17 |
| 88c377f / 8e82598 | T95 (P1): the book reads cooldown / targets / lockout, `IntervalFor`, the reach as an upper bound; the priest / shaman / paladin book fixtures; bookcheck 29, tipcheck 51, spellsui 52 |
| 08777cd / dfdcb01 | T94 (S2 step 1): the style registry (`UI/Styles.lua`), Flat as data, skins by role; stylecheck 26 / 26 (new) |
| 546e729 / e936e23 | T93 (K2): clock parity -- `UI/ClockView.lua`, three fixed segments, Forever F1 / F3-F6, TBC left-click out of combat, `MD.ClockWidget`; clockcheck 35, ttocheck 50 |
| 102583b / 7688659 | T92 (S3 step 1): `UI/Feeds.lua`, `Integrations/Surface_ElvUI.lua` byte-identical; surfacecheck 32 / 41 (new) |
| 231525d | wave N1 integrator |
| 061bae3 | T113 (S0): `MD:AddSubcommand`, `MD:AddDumpLine` |
| c2e1181 | T91: `Spells/Parse.lua` decimals, `additional` / `your next` refused; `Parse.Targets` / `Cooldown` / `Lockout` / `ManaSource`; parsecheck 42 |
| 397009b | T87 (decision 22): the probe on both clients and `== art`, `== hosts`, `== clock`, `== cooldowns`, `== auras`; probecheck forever 97 / tbc 15 |
| 153d82c | T90 (decision 10): cooldowns respected per family (`SM.CooldownOf`, `SM.TK.REFUSED`); solvercheck 89 |
| 54993dc | T89 (S1 step 1): class profiles (`Spells/Profiles.lua`, the druid's two, `MD.ClassProfile`); profilecheck 46 / 44 (new) |
| dff6ace / 2b583c9 | T88 (S4 step 1): the clock face (`Engine/ClockFace.lua`), both clocks byte-identical; clockfacecheck (new) |
| e2b13f4 / a6b5e9c | docs: the next round's research, spec, mockups (`docs/mockups/next.html`) and the author's answers (section 9.1) |
| a6a3bcd / 93b2f36 / c911339 | T85: a spell macro's slot is its spell id (build 70124); the 70124 probe reports |

### Waves N4 and N5 (0.16.6)

Landed (integrated on 7da7943, in this branch): **T102** Settings -> Clock / Look / INTEGRATIONS,
**T106** the Paladin / Shaman / Priest Forever profiles and their coach, **T107** live restyle,
**T110** (partial) the list by role and either-or halves, **T111** the TBC class book and rules
(behind a cap not granted). Their task files are `docs/tasks/T102-*`, `T106-*`, `T107-*`, `T110-*`,
`T111-*`.

## Before this round: the refactor plan (0.16.4, 0.16.5)

| hash | what |
|---|---|
| (the commit after ea6eaa5) | 0.16.5 on every TOC (installed in both clients) (`release.sh --set-version`; the import fixture rebuilt, unchanged -- fixed version since T54); the plan's finish: CLAUDE.md intro at 0.16.5, `docs/PLAN-refactor-ux.md` section 4's Status column (every wave done), TESTING §45 (waves 11-C in five sessions, both clients) and §44 pointed at 0.16.5, HISTORY's closing entry, this handover |
| ea6eaa5 | wave C-d integrator (three main TOCs: `Spells\Families_TBC.lua`, `Spells\Tabs.lua`, `UI\SpellRail.lua`), CLAUDE.md, DECISIONS "TBC's Spells group is the rail", TESTING §44 item 34, TOOLS, expected-counts, HISTORY |
| c51613a / 1c9517b | T84 (C5): the spell rail on TBC (`Spells/Families_TBC.lua`, `Tabs.source`, the shared `UI/SpellRail.lua`, TBC Overview); dashui tbc 84, tabscheck tbc 4 (new) |
| 1451738 | wave C-c integrator (TBC TOC `UI\SpellsView_TBC.lua`) |
| bd65321 / 6de233c | T83 (C3): the TBC Spells view in the Forever structure; dashui tbc 80 |
| 03cc1bd | wave C-b integrator |
| fa20cb3 / 45aefb8 | T81 (C2): TBC's rank table, Waste and Review on the one table; dashui tbc 74, reviewui 50 |
| 439eac4 / fb077e1 | T82 (C4): one clock look (M6), `Tip:Clock` in M6's words; ttocheck 47, minimapcheck tbc 7 |
| 70b424d | wave C-a integrator (three main TOCs: `UI\Theme_Flat.lua`, `UI\Windows.lua`, `UI\EscStack.lua`) |
| cbc6730 / 9a7b422 | T80 (C1): the window manager and the flat theme on TBC; wincheck tbc 4 (new), defaultscheck tbc 49 |
| bf35c93 | wave 17 integrator (two TOC lines for the minimap button, the import fixture rebuild) |
| f80fe4b / f2d4902 | T79 (P36): the minimap button on both lines (`UI/MinimapButton.lua`, `MD:Provide("MinimapLines")`); minimapcheck (new) |
| bde6fb1 / 773661d | T78 (P34): words and tones -- `beaten`, Per sec / Casts, one grey, the white selection bar |
| 7fd71b3 | wave 16 integrator |
| 0fcfc9e / fc3f613 | T77 (P33): lists that flip, chevrons, the rail's one-x hover and menu, row tooltips, the rail scrolling, `UI_POPUP` / `FONTS_CHANGED` |
| 7c32bf5 | wave 15 integrator (three TOCs: `UI/Tip.lua`, `UI/Tip_TBC.lua`; `UI/Tooltip.lua` deleted) |
| d20faae / deef06b / c8eaf31 | T76 (P32): one tooltip -- `UI/Tip.lua`, the kit skin under the theme |
| 19ffac6 | wave 14 integrator |
| 0aad7a0 | T75 (P31): kit layout and sizes |
| 0e7dded | wave 13 integrator |
| af380e2 | T74 (P30): kit primitives -- palette tokens, pixel edges, one selection language |
| 7b77391 | wave 12 integrator |
| f7ae260 / 4301e53 | T73 (P29): no dead ends -- `nav:ReplacePane`, Turn on, Reload UI, the combat line, the dump's order, the TBC danger label |
| e00fd63 | wave 11 integrator |
| 2fe4809 / 82390df / f8b944b | T72 (P28): the replay's stable layout, status band and keys |
| 614f538 / 94de083 | T71 (P27): Review answers in the window (`SP.CardLines`, gate shorts, the result area, the row menu, `UI/ContextMenu.lua`) |
| 90a433a / 9dc0444 | T70 (P26): settings you can reach -- General in two columns, MANA CLOCK / REVIEW / TOOLS, About |
| cf9c6ae / e4c24ac / eadf33a | docs: plan P36 and C5, mockups M1-M6 approved, the author's answers (section 8.1) |
| 9e634a3 | 0.16.4 on every TOC (`release.sh --set-version`; the import fixture rebuilt, unchanged -- fixed version since T54); P35's remainder: "Fixed in" under B1-B26 in the review, CLAUDE.md `Data/DruidSpells.lua` row and intro, TESTING §44 for waves 1-10 (item 13, W10, a one-session subset) and the install lines at 0.16.4, HISTORY's closing entry, this handover |
| 3f96611 | wave 10 integrator: TOC lines (`Engine\ManaPool_Forever.lua`, `UI\Visibility.lua`), CLAUDE.md, DECISIONS, TOOLS, expected-counts, HISTORY |
| e736481 / 1fffaeb | T69 (P25): `UI.THEMED`, colour tokens always present (TBC's literals), `UI.Hex` / `RGB` / `Fill`; themecheck forever 28, tbc 7 |
| fa969e4 / 648c581 | T68 (P24): `Engine/ManaPool_Forever.lua` (`MD.Pool`), the clock paints only, `UI/Visibility.lua`; clockcheck 24, recordcheck 31 |
| e0454fc | wave 9 integrator (Recorder TOCs `Stream_Forever.lua`, main TOCs `Spells\RankRules.lua` / `Spells\Words.lua`) |
| f6db718 / c3191a9 | T67 (P23): `Spells/RankRules.lua`, `Spells/Words.lua`, `Book:ReadSpell` stale in combat; tipcheck 38, bookcheck 22 / 2 |
| cb4cc12 / 672f489 | T66 (P22): stream registry by version, `MD.StreamV3`, shared gates; gatecheck 11 |
| 46c09d9 | wave 8 integrator (Replay TOCs) |
| 20a4f27 | wave 8 merge fix: `Commands_Forever.lua` declares no defaults |
| 80dd589 / 7d0b0b0 | T65 (P21): `Engine/ReviewCommands.lua` on both lines; verifycheck, coachforever |
| 8ea70a3 / f7aadd7 / d2505f8 | T64 (P20): defaults declared once; defaultscheck 48 / 52 (new) |
| 3261856 | wave 7 integrator (TOC lines) |
| 95184a1 / 799781a / ecafebe | T63 (P19): `Engine/Kit.lua`, `Book.generation`; kitcheck 11 / 3 |
| ab87c6f / b3ea5b3 / bd0d5d0 | T62 (P18): `Engine/Recordings.lua`, an unreadable address refused; recordingscheck 32 / 32 (new) |
| b2d9b90 | wave 6 integrator |
| 902035a / fc6b0bc / 827f584 | T61 (P17): TBC verbs on `MD:AddCommand`; slashcheck 8 (new) |
| 23ba195 / bf225e8 | T60 (P16): consumers onto `MD.Text` / `MD.Util` |
| 540a9b6 / fb0f96e / e976729 | T59 (P15): practice policy seam, apicheck rule 10 |
| 8c4cc93 | wave 5 integrator (`tools/data/expected-counts.json` created) |
| f288792 / bc0987e / 6750444 | T58 (P14): one combat flag; ttocheck 45 (new) |
| ed6082f / 5fe4ef4 / 50a7ea7 / 149c512 | T57 (P13): `make check` / `tools/check.sh`, `tools/lib/t.lua`, apicheck rules 8-9 |
| a185bfb | wave 4 integrator (`SpellTuner_TBC.toc`: the four files from `Verify.lua`) |
| 2f7cec1 / b36bd87 / c367622 | T56 (P12): `Verify.lua` split into `Diagnostics_TBC.lua`, `Engine/RegenMeasure.lua`, `Engine/SimSelfTest.lua`, `Engine/ReviewCommands.lua`; verifycheck (new) |
| 093ebeb / 00c7283 | T55 (P11): kernel seams (xpcall handlers, `MD.Text` / `Util` / `Rules`, `RegisterDefaults`, `inCombat`, `Provide`) |
| efa247b / b470219 | T54 (P10): stub timers on the clock, geometry, the import fixture's fixed version |
| fecaad4 | wave 3 integrator |
| 2c83b64 / 1bfbcb0 | T53 (P9): Review and Waste tail lines |
| fbd1e2d / 6f26430 | T52 (P8): B1, B2 |
| 18ce073 / 2e16884 | T51 (P7): B17, B18, B21, B22, B23 |
| 4702b5c | wave 2 integrator |
| 40f9557 / a402ee4 | T50 (P6): B4, B19, B20, B25, B26 |
| 2806606 / cd8716c / 865acde | T49 (P5): B14, B15, B16, B24 |
| 5c5554f / 61175d8 / b6bba2a | T48 (P4): B9-B13 |
| 06f0969 | wave 1 integrator |
| 17c3e50 / a71cf2a / 56f85c6 | T47 (P3): client from the TOC marker, textcheck, B3, B11 |
| cb94d8e / 3ddd972 | T46 (P2): B5-B8 |
| cdb84d8 | T45 (P1): stub truth, costcheck (new) |
| d8a926f | docs: the whole-project review and the refactor + UI/UX plan |

## Before the refactor plan (0.16.3 and earlier)

| hash | what |
|---|---|
| 92ff5d2 | docs: CLAUDE.md rows for what the merge changed (SimModel, SimSolver, SimPlanner, Practice, ReplayTrace, the Modules row -- Kit_Forever, Recorder_Forever, Commands_Forever --, ReplayWindow, Dashboard_Review, the tools row: restcheck, importcheck, import.lua's Forever commands and `report`, reportlines.lua), intro 0.16.3; HISTORY; this handover |
| 51c96cc | 0.16.3 on every TOC (`release.sh --set-version`); `tools/data/import-forever-sv.lua` regenerated (it embeds `MD.version`); TESTING's install lines at 0.16.3 |
| 4b6b112 | DECISIONS "The coach values regen" (item 6, the rejected normalisation) and the `solver-frugal` comment: 20 against 30 as measured -- same deaths, floor seconds and 346 casts, 31189 against 31234 used on the anniversary snapshot; identical (442 casts, 33609 used) on the current file |
| 9844770 | merge `work/regen-recordings` (b062413 regen priced by the solver, 9a694f1 the score ranks mana used, cfd4314 practice fights as reports, 9acd5f4 fights stored with their kit, baa0c03 import.lua on Forever, 8b2c2d5 one kit record `SM.KitSnapshot` and one report tool); conflicts in docs only (TOOLS rows and loop, TESTING §42 UI / §43 regen); fixture regenerated; restcheck 51, importcheck 19 (new), practice 80, practiceui 50, practiceforever 25 |
| (the T44 commit) | T44: `0.16.2` on every TOC (`release.sh --set-version`); CLAUDE.md rows (new: `UI/Theme_Forever.lua`, `UI/Windows_Forever.lua`, `UI/SpellsPane_Forever.lua`, `Spells/Tabs.lua`; the changed shared and Forever files annotated), TESTING §42 (three sessions) and §38-§40 pointed at the new places, ROADMAP section, TOOLS (themecheck / tabscheck / wincheck rows and loop, every changed count), HISTORY, this handover |
| 83ec2d1 | T39: Overview -- My spells, Whole book (a row per rank), Export byte-identical (refcheck exit 0); spellsui 47 |
| f4342b3 | T42: Settings -> General -- SPELL TOOLTIPS, APPEARANCE (font offset, window scale, clock), WINDOWS (combat, ESC, reset); wincheck 53 |
| c5a2367 | T40: practice under the theme; the bindings editor a sheet under `MD.Win`; the one-line summary; Simulate minimum 900; practiceforever 24 |
| 0520277 | T38: one spell's view (header, strip, RANKS, card, the game's tooltip on a row, `MD.API.SetTooltipSpell`); `Book:Compare`, `shape`, `dominatedBy`; bookcheck 21, spellsui 43 |
| 4bc1da9 | T34: replay and practice takeover (`MD.Win:TakeOver`, `< SpellTuner`, practice ESC pause then end, `replayPos` adopted); wincheck 47, replayforever 15 |
| 9a04b62 | T36: Spells rail and picker (`UI/SpellsPane_Forever.lua`), drop from the spellbook (`MD.API.CursorInfo`, cursor never cleared), `/st spell`; spellsui 35 |
| 5f1fae2 | T33: the ESC stack, combat hide / reopen, console strata and place, probe `esc=`; wincheck 39, probecheck 87, consolecheck 17 / 1 |
| 3407386 | T43: Review and replay text under the theme; replayforever 14, reviewforever 11 |
| 4c0205a | T41: the clock under the theme; clockcheck 20 |
| 75fa92f | T37: tooltip block redesign, detail key, `MD.API.RefreshTooltip`; tipcheck 37 |
| 1638cee | T32: window manager core (`UI/Windows_Forever.lua`), `/st ui reset`; wincheck 30 (new) |
| 65f8d12 | T31: kit rail, sheet, mask, list strata, `UI.OnPopup`; navui 35 (25 old unchanged) |
| 36de582 / 974ca82 | T30: table options (+ the review's bar-column header fix); dashui 63 (56 old unchanged) |
| 9c2a26e | T35: `Spells/Tabs.lua`, Book's family `key` / `ids`, `BOOK_CHANGED`; tabscheck 24 (new) |
| b9cbf66 | T29: the theme (`UI/Theme_Forever.lua`), `MD.API.PhysicalScreenSize`, `db.ui` defaults; themecheck 23 (new) |
| 99bbff4 | T28: macro block's untyped first line, the `SetAction` hook, `/st tooltip why`; tipcheck 27 |
| 0a14c32 | T27: practice bindings not in the book hidden (not deleted), skipped by imports, `[Forget]`; practiceforever 20 |
| af266e5 | docs: the Forever UI spec and its mockup, with the author's answers |
| c2bab7c | handover: §38-§40 play on 0.16.1 |
| (after 69d9d96) | docs (lead): TESTING §38 opening (probe on 70058 into `docs/probe/1.60.1_70058.md`), §41 (0.16.1 checks), §38-§40 at 0.16.1; TOOLS rows; CLAUDE.md rows (API_Forever, Probe, SpellTip, Measure, Practice, intro 0.16.1, measure usage); HISTORY; this handover |
| 69d9d96 | 0.16.1: every TOC via `release.sh --set-version`; releasecheck's disagreeing version `9.9.9-disagree` (it was the literal 0.16.1) |
| d168f43 | T25a: the probe's `macro` lines in `== shapes` and its own Macro post-call at load; probecheck 86; lead's one-line tipcheck change (two Macro post-calls) |
| 13f8f6e | T24: practice on Forever only from the spellbook -- no default binds, TBC defaults saved there dropped once, `(not in your spellbook)`, `PR.InBook`, `PR.FirstFamily`, Start refuses with nothing bound, Defaults hidden; practiceforever 15 |
| 71ddbb7 | T26: measure lines `{ text, version, build }`; `dump` current version + older count, `dump all`, `clear`; measurecheck 30 |
| 8ffd300 | T25: `MD.API.OnMacroTooltip` + `MacroSpell`; the block on a macro's tooltip; tipcheck 22; lead's adaptercheck list (22/15) |
| d558432 / a24569e | hand-outs of T24, T25, T26 / T25a |
| (after cdf3727) | docs (lead): TESTING install lines by flavour (§35-§40 `--install-forever`, top `--install-tbc`, §36 TBC-modules note dropped, §38-§40 at 0.16.0); TOOLS releasecheck row + loop; CLAUDE.md intro (one version) + release.sh row + suite list; HISTORY; this handover |
| cdf3727 | T23: release.sh two packages and per-flavour installs, `--version`, `--set-version`, version refusal; Makefile `FLAVOUR`; releasecheck 13 (new; CRLF case added by the lead); probecheck's release check on the new layout (82) |
| 6d755f6 | T22: nine TOCs at 0.16.0, the TOCs the single source; consolecheck case 10 and probecheck read the version from disk; DECISIONS "One version, two installations"; ROADMAP versioning; Forever TOC Notes "beta" (lead) |
| 2696187 | T21 docs (lead): CLAUDE.md rows for the review fixes and T20/T20b, intro to alpha.8; ROADMAP section for the review and R6; TESTING §38-§40 written for alpha.8 (R1 measure in combat, R2, R8/R9, R5, R12/R26, R39/R40, R4); HISTORY; this handover |
| c805287 | alpha.8: every Forever TOC + the probecheck / consolecheck pins; R6 marked Fixed in the review; TOOLS rows for solvercheck / coachforever; HISTORY entry; this handover |
| 753cd96 | T20b (R6, second half): `SM.DangerHitFromOthers` (leave-one-out by id, name and level); both builders set `tg.dangerPrior` (the biggest hit that person took in other recordings over this scenario's max); a target with a prior is read as measured; solvercheck 77, coachforever 18 |
| 1c76605 | T20 (R6): `SM.DangerLine` -- a plan decides on the biggest hit so far (prior / floor before the first), the score keeps the whole-fight line; `Solver:AtRisk` and rule 8 read it; synthetic scenarios unchanged; DECISIONS entry for the ruling; solvercheck 74, coachforever 17 |
| a7d604e | alpha.7: every Forever TOC + the probecheck / consolecheck pins; the review annotated `**Fixed** in <hash>` / `**Skipped**` per R-number; TOOLS suite counts; HISTORY entry; this handover |
| a12bcf6 | review-shared R5: a v3 replay's ticks called reconstructed (SimPlanner `rp.ticks.reconstructed`, ReplayWindow hover and checkbox); replayforever 11 |
| baaf6ef | review-shared R23: no `solver-corpus` strategy without `MD.IntuitionTBC`; coachforever |
| bdbd42e | review-shared R39, R40: Review's low mana `~N%` when modelled, Export hidden without `MD.RunExport`; reviewforever 10 |
| e6cc8cd | review-shared R4: Forever practice regen from `MD.API.ManaRegen()` when `MD.Regen` is absent; practiceforever 9 |
| a73d296 | review-spells R13 R31 R35 R36 R37 R38 R41 R42: non-mana costs free, `Book:CastsFor`, wards/reactive damage refused, clock starts in combat after a mid-fight login, stale values across rescans, crit `1.5x, unverified`; parse 12, book 17, tip 17, clock 17, spellsui 17 |
| 80054ab | review-core R15 R16 R21 R22: debug console Enable box on Forever, the stack line names the raising frame, the forward a tail call; consolecheck 14/1; stub `debugstack` from the real stack (`-- review-core`) |
| 3ad8cce | review-probe R2 R3 R17-R20: snapshot only in combat, SV type at load from the guard, pets, GUID mirrors, `no cost`, `SpellTuner_` modules' blocked actions; probecheck 82 |
| 4673fc8 | review-replay R28 R29 R30: Swiftmend ends the HoT it eats, pre-pull ticks by ceiling (with a scoped `Engine/SimModel.lua` `ticksLeft`/`firstTick` read TBC never sets), direct claims by size; scenariocheck 12 |
| 530cc08 | review-replay R27: an excluded target's line says `max estimated`; gatecheck 9 |
| 1463b9b | review-replay R12 R26: `/st coach N safe/health/cheap/regen` picks a strategy; the card keeps its colour codes; coachforever 16 (with baaf6ef) |
| ad3f5f4 | review-recorder R7-R11 R24 R25: dead at the pull, the opener and pre-cast HoTs, meter `none` when empty/partial/in combat again, the healer's death at the end, departed tokens; recordcheck 24 |
| 12ba325 | review-measure R1 R14 R32 R33 R34: deficit in combat only, casts named at another unit not judged (SENT target), HoT crit at 1.5x, lists escaped; measurecheck 26 |
| c725e91 | docs: CLAUDE.md rows for T17b/T17c/T19 and alpha.6 (applied by the planner); the independent Forever review |
| 63b0cf7 | alpha.6: every Forever TOC + the probecheck / consolecheck pins; TESTING §40 (practice and the imports on Forever); ROADMAP M3/M4 ticks; TOOLS rows (coachforever, adaptercheck, recordcheck, bindscheck + the loop); HISTORY entry from T18 on; this handover |
| 9cbc043 | T19: `/st binds check` (`PR.BindsReport`), importers refuse an unknown shape naming what they expected and found; bindscheck 6 (new) |
| 3fc0623 | T17c: `MD.API.HealthMax` reads a party max through a hidden StatusBar behind `MD.API.BAR_READS_MAX = false`; the recorder records a plain read-back (`maxVia = "bar"`); adaptercheck 22/15, recordcheck 15 |
| a5e49e0 | T17b: party max from other recordings (leave-one-out, `SM.PartyMaxFromOthers`), else this fight's estimate with the plan flagged `foresees` and the card line "NOT causal - sees this fight"; coachforever 13 (assertion 6 on a secret max) |
| 34d3509 | docs: the planner's causality ruling, end-of-day handover |
| a25d878 | T18: Practice module carries Engine/Practice.lua, UI/PracticePanel.lua, UI/BindingsWindow.lua (shared, through MD.API) + Commands_Forever.lua; Simulate -> Practice in the Forever window; PR.EnsureKit; practiceforever 8 (new) |
| b95ef03 | Every Forever TOC at 1.0.0-alpha.5 (probecheck/consolecheck pins follow); TESTING §39 (M3 in game); HISTORY entry |
| c3fb09b | T13f: recorder stamps ownCasts/spent/foreignShare; pre-pull aura remaining aged to t0 |
| 46ebdd9 | T17: coach/solver/card/classifier/marks on a v3 recording, no engine change; coachforever 8. Causality leak escalated (below) |
| 4ae77d8 | T16c: paint-time Esc narrowed to the pipe (names painted as given; TBC as before T16a) |
| 243256c | T16b: Forever window Reports -> Review; MD:RunCoach / MD:ValidationReport on Forever; reviewforever 8 |
| a8ba234 | T16a: Replay module carries engine/planner/solver/ReplayTrace/Tooltip/ReplayWindow + Commands_Forever.lua; SM.RecordedHp; replayforever 10; SP.Card `local kit = nil` |
| 6887cdf | T14: Gates_Forever.lua, SM:ValidateV3, gate 8 one-sided until SM.HEAL_AMOUNT is effective; gatecheck 8 |
| 9f2488b | T13d: Scenario_Forever.lua (SM.ScenarioV3, AttributeHeals on both HoT cadences, EstimateMaxHP, reconstructed health); tools/foreverfixture.lua; scenariocheck 9 |
| 6624d58 | T13: Recorder_Forever.lua, v3 stream, /st rec; recordcheck 14 |
| 9876615 | T15: Kit_Forever.lua (kit + spell index from MD.Book), MD.API.SpellName; kitcheck 7 |
| 797ef17 | T13a: apicheck rule 8 (event argument used before IsSecret); selftest 10 of 10 |
| 007d1d1 | T13e: probe asks whether a StatusBar hands a secret back; probecheck 73 |
| bdbc40a | T13c: module plumbing (Module.lua proxy, Ready.lua, root-resolved shared files); modulecheck 14 |
| 2ba2346 and earlier | previous lead run (see docs/HISTORY.md) |

Every accepted task file carries a "Lead review" section saying what the lead changed, if anything.
docs/HISTORY.md's 2026-09-29 entry covers T18 onwards.

The refactor plan's left-overs, none of them planned: comments that still name the old files after
C1 (`Client/Probe.lua`, `UI/Style.lua`, `UI/Dashboard_Review.lua`, `UI/SpellTip_Forever.lua`,
`tools/wowstub.lua`, and `docs/SPEC-forever-ui.md` / the plan); `Core_Forever.lua`'s
`effectiveMode` declaration that nothing on Forever reads since T81; Waste's `ffcc66` literal and
the build-time pitch of TBC's rank table and Waste (T81 deviations 6, 7); `Tip:Columns` dead in
`UI/Tip_TBC.lua` (T83 deviation 4; deleted by T121); Spells on TBC keeps 1036 x 646 (T83
deviation 1; 860 x 560 since T120); no spellbook drop, Whole book or Export on TBC's rail and
Overview, and the rail tags refresh on events, not the 2-s tick (T84 deviations 4, 5, 7; closed by
T120's shared pane). The author's §45 sessions (written for 0.16.5)
hold on 0.16.6.

## Open questions / hazards

- **Resolved (planner's amendment, 2026-09-28; T17b a5e49e0 + T17c 3fc0623):** the causality leak of
  ruling 1's stand-in. Party max from other recordings (leave-one-out); else this fight's estimate,
  the plan flagged `foresees`, the card line "NOT causal - sees this fight"; the status-bar path
  ships off (`MD.API.BAR_READS_MAX = false`) -- **switch it on** (one word, `Client/API.lua` 333)
  only if the author's §38.3 report shows `bar UnitHealthMax(party1): set ok, read plain <n>`.
- **Ruled and fixed (T20):** review R6. Follow-up worth a one-line task some day: the two OLDER
  divergence assertions (solvercheck §4 "a burst at 40s ...", coachforever 6) time a divergence by
  the quiet run's cast only, which could report late when the loud run inserts an early cast; T20's
  two new ones take the earlier of the two (lead's one-line change). Both older ones still pass
  with the stricter time.
- **Waiting on the author:** TESTING §38 (alpha.4 items, notably §38.2 step 4 -- is a `UNIT_COMBAT`
  HEAL amount gross or effective; that sets `SM.HEAL_AMOUNT` and makes gate 8 two-sided -- and
  §38.3, the party probe with the `bar ...` lines), §39 (the recorder, validate, replay, coach and
  Review on real pulls; the CANCEL count against casts actually cancelled, since the STOP /
  SUCCEEDED order is UNKNOWN) and §40 (practice and the imports). All three play on **0.16.5**
  (installed in the beta on 2026-10-01; 0.16.2 the UI build, 0.16.1 build 70058's), after the
  70058 probe, §41, §42, §43, §44 and §45.
- **Lesson -- parallel tasks on disjoint files still meet in the suites (T24-T26, 2026-09-29).**
  Three implementers ran at once, each told which files the others owned; that held. What it did not
  catch: T25's assertion counted Macro post-calls (`#list == 1`) and T25a, written the same hour,
  required a second one at load. When two tasks touch the same registry, say in the second task
  which of the first's assertions it moves. And an assertion that writes a literal version breaks on
  the next bump (releasecheck's `0.16.1`): use a value no tree carries.
- **Lesson -- a clean tree is not a dead implementer (T23, 2026-09-29).** T23 was dispatched twice
  again. The predecessor lead's session (a8fb5831, alive in the process table) handed T23 out at
  16:29:44 and its implementer was still reading. The planner saw a clean tree and an empty Report
  and took that for "left no changes", so it asked for a re-dispatch at 16:31. The two
  implementers both wrote `tools/releasecheck.lua` at 16:31-16:34. The re-dispatched one's `Write`
  overwrote the first one's suite, and on seeing "updated" it stopped. Before re-dispatching: compare
  the hand-out commit's time with now (minutes mean nothing), look for a live session on this
  worktree (`ps -eo pid,etime,args | grep -- --resume=`, a child running a suite in this tree), and
  only then dispatch. An implementer that finds a file it did not expect must stop, as a688ec09 did.
- **Lesson -- check before you dispatch.** T13c was dispatched twice, and two implementers were
  writing in the same tree at once (the previous run's alpha.4 commit also swept in T13c's TOC hunk,
  and T12b's commit its stub hunk). Before handing a task out or re-issuing it: read the task's
  Report section, `git status --short` and `git diff` for its files; if another implementer may
  still be writing, wait until the tree settles (file mtimes stable for a few minutes) rather than
  starting a second one. Stage only the task's own paths; never `git add -A`.
- (Resolved 2026-09-29: the planner repaired the shared `.git` with the author's approval; `git fsck` is
  clean. Still: never touch `.git` internals.)

## Planner, end of 2026-09-28

- **Escalation 1 ruled** (docs/FOREVER-PLAN.md, the amendment under ruling 1): party max for
  coaching from other recordings of the same name; else this fight's estimate with `foresees` set
  and said on the card; drop the stand-in if the T13e readback shows a plain max. Write it as the
  **first task tomorrow** (before T19), with coachforever's causality assertion run on a secret max.
- **Escalation 2 (the 18 empty git objects)** stays with the author -- no agent touches `.git`.
- (superseded 2026-09-29: 0.16.0 is installed in the author's beta, `--install-forever`.)
- 2026-09-29: the amendment is implemented (T17b, T17c); escalation 1 is closed.
