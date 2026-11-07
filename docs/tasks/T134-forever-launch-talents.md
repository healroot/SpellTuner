# T134: the launch talents on Forever -- Bloom, and talent builds in the What if

The author, 2026-11-07, the game released: "there are quite changes in talents right before release
(check the site) so we need to adjust our calculations. For example druid get bloom talent which
heals by 100% or your spirit when hot end its duration." And: "lets also add a posibility to simulate
different talent build with what if setting. So that we can check how the bloom impact efficiency
without doing actuall respec."

## The data

`tools/.cache/talentsforever.json` is the 2026-11-04 export. `Data/Talents_Forever.lua` and
`Data/Coefs_Forever.lua` regenerated from it (never by hand). `tools/buildtalents.py` learns:

- the multiplier shapes "amount healed by your X spell(s)", periodic (`scope.periodic`, Genesis) and
  instant-cast (`scope.instant`, Twin Disciplines);
- `ST.TalentCosts`: a percent off a mana cost (What if only: the client's cost already carries the
  talents taken);
- `ST.TalentExpiry`: a heal when a spell runs out (Bloom, `scope = { spells, stat }`);
- `ST.TalentStats`: a percent on Spirit (Living Spirit).

Each refuses a sentence it does not recognise and names it in the file's header, as before.
Priest's Forever profile loses Binding Heal and Lightwell (not in the launch spellbook).

## Bloom, live

`Book.adjust[3]` sets `entry.expiryHeal` for a spell a rule names when the talent is taken, and
`Numbers` adds `amount = Spirit x pct / 100` to `value`, so per mana, per second and the marks see it.
`textValue` keeps what the text says; the bonus fit reads that, so a Bloom never measures as a share.

- **Assumed, said in the words ("if it runs out", "predicted"):** the spell runs its whole duration. A
  refresh or a Swiftmend consume forfeits it. Flat: no +healing, no talent multiplier (VERIFY).
- **Spirit** through `ST.API.Spirit()` (`UnitStat`, second return). Secret in combat: the last plain
  reading stays. Never read: the card says "Spirit not read" and no amount is added. It already
  carries Living Spirit, which is never added again.
- **Not in Practice, Coach or the replay**: `Modules/SpellTuner_Replay/Kit_Forever.lua` does not read
  `value`, so the simulator does not model Bloom.

## The periodic multiplier

`TalentMult` keeps `factor` and `tickFactor` apart; `Coefficients.FromRow` multiplies only the
over-time share by `tickFactor`.

## What if -> Talents

`Spells/WhatIf_Forever.lua`. The drawer shows one-line rank rows (`compact`) for the talents that move a
rank of the family on screen (`classRowsFor`), and Spirit with a talent that reads it; `classRows` is
every row, which `Clean` validates against. A talent typed on one family stays typed on another; the
Summary names it. Unread ranks: no rows and a sentence, never "assume 0".

A typed rank moves each rank **from the live ranks to the typed ones**, because the client's text and
cost already carry the live talents:

- multiplier: parts x `(1 + typed) / (1 + live)`, periodic scope on `over` / `tick` only; the copied
  share x new text / old text (on a hybrid under Genesis that is the whole-spell ratio, an approximation
  the What if accepts);
- cast: `cast + live reduction - typed reduction`, never below 0, not on a channel;
- cost: all cost talents matching the rank, percents **added** (assumed), rounded;
- Bloom: `Book.ExpiryFor` at the typed ranks and the typed Spirit (else the last reading) x each changed
  stat talent's typed / live.

The heal and damage halves move by the talents that reach each; an absorb only by a talent naming the
spell. A moved share says so (`bonus.movedFrom`). The +healing move runs after, on the moved share. The live book, its generation and its entries are
never written.

**Not moved, and the sentence says so:** crit (Holy Power, Tidal Mastery, Improved Regrowth, Holy
Specialization), durations (Nature's Splendor), regen, stat-to-bonus (Spiritual Guidance, Mental
Quickness, Natural Instinct), spells a talent teaches (Swiftmend, Wild Growth, Riptide, Penance: not in
the book until learned), procs (Holy Binding, Litany of Light, Illumination), Oath of Light (by target).

## Acceptance

`tools/talentwhatifcheck.lua` (forever), `coefscheck`, `talentscheck`, `bookcheck`, `spellsui`,
`make check`. In game: `docs/TESTING.md` section 56.
