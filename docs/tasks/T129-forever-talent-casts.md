# T129: Forever reads talent ranks; the +bonus estimate uses the base cast

Author's report (2026-10-04, Forever, Wrath card): `+Damage counts ~20% estimated
(cast 1.5 / 3.5 x 0.47)` on Rank 2. Rank 2's cast is 1.7 s; the author has 2 points
in Improved Wrath, so the client reports 1.5 s (Rank 1: 1.5 -> 1.3). The
coefficient uses the cast **before** talents (clamped to 1.5..3.5), so Rank 2 must
read `cast 1.7 / 3.5`. Rank 1 stays `1.5 / 3.5` (the clamp). The card's own `Cast`
line keeps showing the client's (talented) cast -- that one is right.

Author's ruling (2026-10-04): read the talents on Forever; **talentsforever.com is
the preliminary source of truth** for what a talent does until it is verified in
game (they update regularly). Add a dated entry to `docs/DECISIONS.md` saying so.

Facts already known:
- Probe 1.60.1_70009-m2: `C_SpecializationInfo.GetTalentInfo` answers nil;
  `C_ClassTalents.GetActiveConfigID()` answers (5562168), `C_Traits` is present.
  `C_Traits.GetTreeNodes / GetNodeInfo / GetEntryInfo / GetDefinitionInfo` are in
  `tools/data/forever_api.json`; `TRAIT_CONFIG_UPDATED` is **not** (check how the
  baseline treats events; register it only if it is safe under `ST:On`, else use
  `PLAYER_TALENT_UPDATE`, which the probe saw `ok`).
- talentsforever `data.json` (`generated` 2026-10-03; CC BY 4.0, attribution
  `Data from talentsforever.com (https://talentsforever.com)`; facts in
  `docs/REFERENCES-FOREVER.md` §1): `talents[Class].trees[i].talents[j]` =
  `{ name, max, desc = { rank1 sentence, ..., rankN } }`; no spell ids, so talents
  are matched by **name**. A local copy is at
  `/tmp/claude-1000/-home-penek-projects-addons-SpellTuner--claude-worktrees-spelltune-whatif-fair-compare-29f8cd/f84bf552-66c3-44f8-9a4c-90d9a2c2cb6a/scratchpad/tf.json`.
- Permanent cast-time talents in it (desc rank 1): Druid Improved Wrath ("Reduces the
  cast time of your Wrath spell by 0.1 sec and its Mana cost by 10%."), Improved
  Starfire, Naturalist (Healing Touch); Priest Divine Fury ("Reduces the casting time
  of your Smite, Holy Fire, Heal, and Greater Heal spells by 0.1 sec."), Improved Mana
  Burn; Shaman Improved Healing Wave, Elemental Alacrity (0.17); Mage Improved
  Fireball, Improved Frostbolt; Warlock Bane (two amounts in one sentence), Improved
  Corruption; Paladin Instrument of Law. Proc / charge / percentage ones (Eclipse,
  Infusion of Light, Heating Up, Maelstrom Weapon, Nature's Swiftness) are **not**
  permanent and must not be picked up.

## 1. The talent rules, generated (`tools/buildtalents.py` -> `Data/Talents_Forever.lua`)

- A generator in the manner of `tools/buildintuition.lua`: reads a talentsforever
  `data.json` path, writes `Data/Talents_Forever.lua` (`-- GENERATED, do not hand
  edit`, the source's `generated` date, the attribution line, "PRELIMINARY until
  verified in game"). Shape: `ST.TalentRules = { [class] = { [talentName] = {
  spells = { "Wrath" }, castPerRank = { 0.1, 0.2, ... } } } }` -- every rank's
  amount read from **that rank's own sentence**, never multiplied out.
- It recognises only a sentence that **starts** "Reduces the cast(ing) time of
  (your)? <spell list> (spell(s))? by N sec" (Bane's "... and your Soul Fire spell
  by 0.4 sec" gives Soul Fire its own row). Anything else is skipped; skipped
  cast-time talents are listed by name in the file header, never guessed.
- Commit the generated file. The generator is a tool, not run by `make check`.
- A Lua suite (`tools/talentscheck.lua`, forever) checks the data file's shape:
  every class known, `castPerRank` positive and strictly ascending, length equal to
  the talent's ranks, spells non-empty; Improved Wrath = 0.1..0.5; no Eclipse /
  Maelstrom Weapon / Nature's Swiftness.
- List the file in the Forever TOCs (both) before `Spells/Book.lua`. TBC: nothing
  (TBC's base casts come from `Data/SpellData.lua`).

## 2. Reading the ranks (`Client/API_Forever.lua`)

- One binding, `ST.API.TalentRanks()` -> a plain table `{ [talentName] = rank }`
  (rank > 0 only) or `nil, "absent" | "error" | "secret"`: active config ->
  `C_Traits.GetConfigInfo(cfg).treeIDs` -> `GetTreeNodes` -> `GetNodeInfo(cfg, node)`
  (`activeRank`, `activeEntry.entryID`) -> `GetEntryInfo(cfg, entryID).definitionID`
  -> `GetDefinitionInfo(def)` (`overrideName`, else the name of `spellID` through
  the adapter). Every call guarded; a secret anywhere makes the answer `nil,
  "secret"`; only copies leave the adapter (adapter rules, `tools/adaptercheck.lua`
  lists the new Forever-only names).
- The TBC adapter answers `nil, "absent"` (or leave it undefined if the pattern
  for a Forever-only binding says so -- follow the existing one).
- The stub: `tools/wowstub.lua`'s installer at ~L1878 grows a node walk; a druid
  config with Improved Wrath at rank 2 is the default fixture for the new tests.

## 3. The base cast (`Spells/Book.lua`, the Q6 seam; `Spells/Coefficients.lua`)

- Book.adjust gets its first function (update the seam's comment: the client's
  cast line moves with the talent, the coefficient does not): for an entry with a
  number `cast > 0` that is not channelled, if a rule for the player's class names
  the entry's family and the read rank is r > 0: `e.baseCast = e.cast +
  castPerRank[r]`, `e.castTalent = "<talent> <r>"`. Ranks unread (nil) but a rule
  exists for the family: `e.castTalent = "talents not read"`, no `baseCast`.
  A rank above the rule's length: no `baseCast`, `castTalent = "<talent> <r>: no
  rule"` -- never extrapolate.
- The book rescans on the talent event(s) (section's facts) as it does on
  `SPELLS_CHANGED`.
- `Coef.Estimate` uses `e.baseCast` when it is a number, else `e.cast`. The `why`:
  `cast 1.7 / 3.5 (1.5 + 0.2 Improved Wrath 2) x 0.47`; unread: `cast 1.5 / 3.5
  (talents not read) x 0.47`; no rule: unchanged. Hybrid's direct part likewise.
- A measured count still replaces the estimate (unchanged).
- `/st dump` line `talents: Improved Wrath 2` (or the reason none were read) via
  `ST:AddDumpLine`; `/st tooltip why` shows `castTalent` when set.

## 4. Tests (oracles)

Forever stub, druid, Improved Wrath 2:
- Wrath R2 (client cast 1.5): `baseCast` 1.7, estimate `1.7/3.5` x its sub-20 factor,
  why contains `1.5 + 0.2 Improved Wrath 2`.
- Wrath R1 (client 1.3): `baseCast` 1.5, estimate `1.5/3.5` (clamp), why says so.
- A rank cast at 2.0 base (R3+, client 1.8): `2.0/3.5`.
- Healing Touch with no Naturalist point: unchanged, no `castTalent`.
- C_Traits absent: no `baseCast`, why has `talents not read`; the old counts.
- A secret in the walk: same as absent, reason `secret`.
Update goldens only where these cases move them, and list each moved line in the
report.

## 5. Docs

`docs/TOOLS.md` (new suite, generator), expected counts, `CHANGELOG.md` under
`## 0.17.1`, `docs/TESTING.md` §50 a new step (Forever druid with Improved Wrath:
Wrath R2's card says `cast 1.7 / 3.5 (1.5 + 0.2 Improved Wrath 2)`; `/st dump`
has the talents line; respec, the line follows), `docs/REFERENCES-FOREVER.md` §1
(talents used, matched by name, preliminary), `docs/DECISIONS.md` (the ruling).
**Do not edit CLAUDE.md** -- the lead adds the rows.

## Acceptance

Section 4's oracles pass; `make check` green (apicheck 0, textcheck 0, counts);
nothing on TBC changes.
