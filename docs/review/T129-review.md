# T129 review -- Forever reads talent ranks; the +bonus estimate uses the base cast

Commits reviewed: 5af5f44..3a7f768 (4 commits), against `docs/tasks/T129-forever-talent-casts.md`
and CLAUDE.md's conventions. Reviewer: independent (Opus 5.5, high). `make check` was not run
(a gate-runner owns that). Each finding was checked by reading the code path. Three things were
also run:

- `tools/talentscheck.lua` on its own: 17 ok.
- The generator, rebuilt from the scratchpad `tf.json`: byte-identical to the committed
  `Data/Talents_Forever.lua`.
- Mutants in a scratch copy of the tree: a stub walk with missing or empty nodes, and
  `PLAYER_TALENT_UPDATE` unregistered.

**Verdict: fail** -- 0 blockers, 1 major, 6 minors.

## Verified correct

- **Base-cast arithmetic and clamp.** `Coef.Estimate` (`Spells/Coefficients.lua:126`) takes
  `e.baseCast` when it is a number. The direct part and the hybrid direct part both clamp
  through `Coef.Direct`. With Improved Wrath 2:
  - R1: client 1.3, base 1.5. The why reads `1.5 / 3.5 (1.3 + 0.2 ...)`.
  - R2: client 1.5, base 1.7. The why reads `1.7 / 3.5`, and the counts are 0.2307.
  - R3: client 1.8, base 2.0.

  `Num` handles 10 -> "10", 2 -> "2", 0.17 and 0.2 (float noise rounded away). Channelled
  spells and hots ignore `baseCast`.
- **Entry lifetime.** Entries are rebuilt on every scan (`BuildEntry`, `ReadSpell`), so after a
  respec to 0 points no stale `baseCast` or `castTalent` survives. `EntrySig` signs the new
  scalars, so the generation moves on a respec.
- **Rescan on change.** `PLAYER_TALENT_UPDATE`, `TRAIT_CONFIG_UPDATED` and `SPELLS_CHANGED`
  set `_talentsDirty`. Both talent events are `ok` in probe 1.60.1_70009, and `ST:On` registers
  under pcall. The mutant without `PLAYER_TALENT_UPDATE` fails checks 4-8, so the event path is
  really tested.
- **Secrets.** The secrets are handled in three ways:
  - A secret return is caught by `Call`.
  - A secret nested field is caught by `Copy`'s `_secret`.
  - A secret talent name is caught through `SpellName`.

  Each one turns the whole answer into `nil, "secret"`. Only copies and plain numbers or
  strings leave the adapter.
- **Generator.** Every picked rule is read rank by rank from its own sentence. Every
  trailing clause in the current export is a non-cast effect (mana, threat, stun, damage, or
  indoors). Eclipse, Maelstrom Weapon, Nature's Swiftness, Heating Up, Infusion of Light and
  Presence of Mind are all skipped. Improved Ghost Wolf `{1, 3}` and Elemental Alacrity
  `{0.17, 0.33, 0.5}` match the source. Bane's Soul Fire part looks up the rank under `"Bane"`
  (`r.talent`).
- **Readers of `e.cast`.** Nothing else reads the new fields. `Coef.Estimate` is called only from
  `Spells/Book.lua:484`. The TBC `Book_Model` and `DamageMath` never call `Estimate`, so TBC is
  unchanged.

## Major

### M1 `Client/API_Forever.lua:551-597` -- a walk where no node answers is reported as "none taken"

**Defect.** A tree or node that answers nothing, or answers "absent", is skipped silently. So
a walk in which no node answered returns `{}`. `Book:Talents` (`Spells/Book.lua:69`) caches that
as read, the estimate drops the `(talents not read)` note, and the dump says
`talents: none taken`.

**Failure scenario.** Run in the stub (scratch harness) with Improved Wrath 2 and `C_Traits`
present. Each of these four cases gives `TalentRanks() = {}`, `why = nil` and Wrath R2
`cast 1.5 / 3.5 x 0.47`, with no `castTalent`:

- `GetTreeNodes` missing.
- `GetNodeInfo` missing.
- `GetNodeInfo` answering nil.
- `treeIDs = {}`.

That is the author's original wrong number, now unmarked.

**Why it matters.** The adapter comment marks the walk past `GetConfigInfo` as UNVERIFIED on
Forever, so these are the likeliest real-client shapes. The cached `{}` is also not retried until
the next talent event or `SPELLS_CHANGED` (no "re-read on nil"). The task's own rule is that half
a talent list must never price a rank silently, and a list that is all missing is the extreme
case.

**Fix direction.** If no node in any tree answered a table, answer `nil, "absent"`. Add a
check in `talentscheck` for each of the four shapes.

## Minors

### m1 `Spells/Book.lua:132` / `Spells/Coefficients.lua:112` -- under haste the decomposition is wrong

**Defect.** `baseCast = cast + castPerRank[r]` assumes the client's cast is free of haste. On
retail, `C_Spell.GetSpellInfo().castTime` includes spell haste.

**Failure scenario.** Nature's Grace (in the export: +10% spellcasting speed for 3 s) is up
during a 2-second rescan with Improved Starfire 5. The client reads 3.0 / 1.1 = 2.73, so
`baseCast` is 3.23, the counts are 0.92 instead of 1.0, and the why reads `(2.73 + 0.5 ...)`.
The error itself predates T129, but the new words state wrong arithmetic as fact. Note it in
DECISIONS, or skip the decomposition while a haste aura is up.

### m2 `Spells/Book.lua:69-75` -- the dump line can be missing

**Defect.** The `talents:` dump line is added only when a cast rule is first priced.

**Failure scenario.** A hunter or warrior, or any class whose book has no ruled family, gets no
`talents:` line in `/st dump`. Task section 3 asks for the line, or the reason none were
read, without that condition.

### m3 `Spells/Book.lua:76` -- an unread answer is re-walked once per entry, every scan

**Defect.** With `_talents == nil`, every `Book:Talents()` call walks again: once per ruled
entry, every 2-second scan, and every `ReadSpell`.

**Failure scenario.** Take a druid in combat whose walk answers `secret` at a late node. About
25 Wrath, Healing Touch and Starfire ranks each trigger a full node walk every 2 seconds. Retry
once per scan, not once per entry.

### m4 `tools/buildtalents.py:26-28` -- the regex ignores the trailing clause

**Defect.** `LEAD` accepts any text after `by N sec` (`rest` is never inspected).

**Failure scenario.** A future export sentence such as "Reduces the cast time of your Heal spell
by 0.5 sec while in Shadowform" would be emitted as a permanent rule. The current export has
none (verified above). Possible fixes:

- Accept only an empty rest, `.`, or a known non-cast clause.
- List each accepted rest in the header.

### m5 `tools/talentscheck.lua` -- tests that are missing or cannot fail

- The secret check (check 5) only covers a wholly secret `GetNodeInfo` table. A secret nested
  field (the `Copy` `_secret` path) and a secret definition name are not tested.
- `TRAIT_CONFIG_UPDATED` is never fired.
- The Healing Touch "unchanged" check compares `b.counts` against `Coef.Estimate` on a copy, so
  that half cannot fail on an `Estimate` regression. The `no "("` half carries the check.
- `docs/TOOLS.md` says the suite checks "no TBC binding", but the suite has no such check.

### m6 `UI/SpellTip.lua:813-820` -- tooltip why misses spells outside the book

**Defect.** `/st tooltip why` looks up the last block's id in `Book:Get().spells` only.

**Failure scenario.** Hover a Wrath chat link for a rank that is not in the book (a
`ReadSpell` entry). Its `castTalent` is never shown, although the block priced it with the
talent.
