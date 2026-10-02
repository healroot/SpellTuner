# T110 -- non-healer extras (P6): either-or halves by role, the list seeded by role

Status: **built in part** 2026-10-02 on branch `next/T110` (base `4ff42bf`, wave N5). It is waiting
for the integrator. The caster mana sources are only partly done: their values wait on T105 (see
"Left for after T105").

Spec:
- `docs/SPEC-next.md` section 11, row T110.
- 4.2 P6: "either-or spells keep both halves (Holy Shock, Holy Nova, Penance) and show the one
  matching the player's role; the list seed by role (a shadow priest no longer starts with heals,
  `Tabs.lua:170-176`); caster mana sources on the clock (Evocation, mana gems, Life Tap)".
- Section 3, principles 1 (client reads through `MD.API`), 2 (ASCII, no bare pipe), 9 (no value
  from memory) and 10 (TBC changes only by decision).

Research: `docs/research/next/R-classes.md` section 4:
- Item 2: "show the half matching the player's role. Read the role from spec or talent points,
  else from the seeded list's kind."
- Item 3: the caster mana sources are ManaCooldowns rows with values from the client's own text.

Dependencies:
- T95 (in the base): `family.altKind` and `entry.alt`.
- T105 (**not landed**; it waits on the author's in-game probe): its aura and instant-gain seam.
  Nothing here assumes T105. Nothing here assumes T103, T104, T108 or T109 either.

## What was built

### The role (`Spells/Tabs.lua`)

Forever's talent API answers nothing readable. The probe found `GetTalentInfo` absent and
`C_SpecializationInfo.GetTalentInfo` returning nil. `MD.API.Specialization` is TBC's only. So the
talent points are read where they show: **a talent's own spell in the book.**

`Tabs.ROLE_TALENT_TREES` holds the talent spells per class, each placed in its healing or damage
tree:
- Source: talentsforever.com `data.json` (generated 2026-09-26, beta client 1.60.1.70009, CC BY 4.0).
- The names come from `spellbooks[Class].talents`; the tree comes from `spellbooks[Class].tabs`.
- Blessed Recovery is passive and left out.
- The tank trees (Protection, Feral Combat) and the classes with no healing tree say nothing.

| Class | heal | damage |
|---|---|---|
| PRIEST | Inner Focus, Penance, Power Infusion (Discipline); Binding Heal, Holy Nova, Prayer of Mending (Holy) | Mind Flay, Shadowform, Silence, Vampiric Embrace (Shadow) |
| PALADIN | Divine Favor, Holy Shock, Light's Vigil, Voice of Truth (Holy) | Repentance, Seal of Command (Retribution) |
| SHAMAN | Mana Tide Totem, Nature's Swiftness, Riptide, Water Shield (Restoration) | Lava Burst (Elemental); Rage of the Farseer, Stormstrike (Enhancement) |
| DRUID | Nature's Swiftness, Swiftmend, Wild Growth (Restoration) | Insect Swarm, Moonkin Form (Balance) |

The table holds names only. A name the book never shows costs nothing. `Tabs.ROLE_TALENTS` is the
flat name-to-role map, built at file load. A name in two classes must say the same role in both
(Nature's Swiftness does), or the file raises.

- **`Tabs:BookRole(book)`** returns `"heal"` | `"damage"` | nil, plus the names that said so. It
  counts the known, not passive families the map names. The larger count wins; a tie or no
  evidence gives nil.
- **`Tabs:Role(book)`** returns `role, source`. The source is `"talents"` (from `BookRole`), else
  `"list"` (the kind the list was seeded with, read from `cdb.spellTabs`), else nil. It never
  creates the store, because a tooltip asks this before the list is opened.

### The list seeded by role (`Spells/Tabs.lua`)

- **`Tabs:SeedList(book, role)`** uses the book's role unless one is given.
  - A **damage** role takes the damage families that cost mana first, by learn level.
  - An either-or heal family (`altKind == "damage"`: Holy Shock, Holy Nova) counts as a damage
    candidate. Its damage half is what that role casts it for.
  - With no damage candidate it takes the heals. Any other role uses the old rule: heals, else
    damage that costs mana.
- A shadow priest's first open now lists Smite, Shadow Word: Pain, Mind Blast and Mind Flay.
- The reconcile appends a newly learned family of the list's kind as before. A damage list now
  also takes a newly learned either-or heal.
- **`Tabs:Reset`** stays heals-first (deviation 1). Its button says "Reset to my heals".
- **TBC is unchanged.** `Spells/Families_TBC.lua`'s druid heal families carry no talent evidence.
  Swiftmend is excluded from that list, so the role is nil and the old seed runs. The tbc half of
  `tabscheck` (4) is unchanged.

### Both halves (`Spells/Book.lua`)

**`Book:Half(family, role, pool)`** is the family itself unless the role is `"damage"` and the
family is an either-or heal (`kind == "heal"`, `altKind == "damage"`). In that case it builds a
**view** of the damage half:
- Every rank becomes a shallow copy with `Numbers` run for `"damage"`: value, min, max, the
  interval with the cooldown still pacing it, per mana and per second.
- The heal's reach (`targets`, `reach`, `targetsWhy`) is dropped, because a heal's party is not the
  damage's targets.
- The rank copy carries `half = "damage"` and `of` = its heal entry, plus its own
  `casts`, dominance, beaten-by ids and suggested rank. These come from `Spells/RankRules.lua` on
  the damage numbers.
- The view itself carries `kind = "damage"`, `altKind = "heal"`, and `of` = the family. Its key,
  name, ids and gaps are the family's.

It is built at each call and written nowhere. The book's entries, `Book:Get()`'s consumers and
`Book.generation` see exactly what they saw.

**`Book:HalfOf(entry, role, pool)`** does the same for one `Book:ReadSpell` entry (no family, no
dominance).

### The tooltip (`UI/SpellTip_Forever.lua`, `Spells/Words.lua`)

- `SpellTip:Lines` asks `MD.Tabs:Role(book)`. For the damage role it swaps an either-or family, and
  the hovered entry, for `Book:Half`'s view (`HalfOf` outside a family).
- Every line then reads the half: Suggested, Per mana, Per sec, Casts to OOM, the value's parts and
  the rank lines.
- The detail lines gain **`W.OtherHalf`**:
  - On the damage half: `Or heals  320  0.98 per mana`.
  - On a heal with a damage half: `Or damage  348  1.07 per mana`.
  - Both are one target's numbers (decision 12).
- The plain block keeps its four facts.
- A heal role, no role, or any other spell gets the block as before, plus the one new detail line
  on an either-or heal.

### The caster mana sources (`Engine/ManaCooldowns.lua`)

Two rows were added to `MC.byClass`, **inert** like the PRIEST, SHAMAN and PALADIN stubs (no
`value`, so `MC:All` and `MC:Active` skip them):

```lua
MAGE    = { { key = "evocation", short = "evo", id = 12051, name = "Evocation", duration = 8 } },
WARLOCK = { { key = "lifetap",   short = "lt",  id = 1454,  name = "Life Tap",  instant = true } },
```

The ids and words come from the same export:
- Evocation 12051: "your mana regeneration is active and increased by 1,500%. Lasts 8 sec." The
  export marks the text the same as Classic's. TBC's own text is VERIFY.
- Life Tap rank 1, 1454: the id `Engine/Targets.lua` already counts. "Converts 30 Health into 30
  Mana": an instant conversion, so it has no duration.

TBC behaviour is unchanged.

## Left for after T105 (and for other owners)

1. **Values from text.** Three shapes need reading, and `Spells/Parse.lua` is not owned here:
   - Evocation's "mana regeneration is active and increased by N%. Lasts N sec." `Parse.ManaSource`'s
     regen shape does not match it: it reads Innervate's "regeneration by N% ... while casting".
   - A gem's "instantly restore N to M mana".
   - Life Tap's "Converts N Health into N Mana".
2. **On the clock.**
   - Forever: T105's seam. Evocation goes in as a regen percentage on the pool's last regen
     reading, a gem and a tap as instant gains into `Engine/ManaPool_Forever.lua`, and the aura
     that marks one running.
   - TBC: a `value` model per row in `MC.VALUES`, read from the spell's description through the
     adapter. TBC has no description binding the model may read yet.
3. **Mana gems.** They are items: Mana Agate, Jade, Citrine, Ruby. Their item ids are in no source
   in the repository (the export has the conjure spells 759, 3552, 10053 and 10054 only). They wait
   beside `MC.potions` until a probe or `/md verify` reads them.
4. **Penance.** It is either-or in the spec, but `Parse.Description` refuses its text (T50, review
   B4). It has no `kind`, so it has no halves until Parse reads it (not owned here).
5. **The Spells pane and the rail** (`UI/SpellsPane_Forever.lua`, `UI/SpellRail.lua`, not owned)
   still show an either-or family's heal half. They can take `Book:Half(fam, MD.Tabs:Role())` the
   same way the tooltip does.

## Counts

| Suite | before (parent `4ff42bf`) | tests on the parent's code | after |
|---|---|---|---|
| tabscheck/forever | 24 | 24 ok, 3 failed | **27** |
| tabscheck/tbc | 4 | 4 | 4 |
| bookcheck/forever | 29 | 29 ok, 2 failed | **31** |
| bookcheck/tbc | 2 | 2 | 2 |
| tipcheck/forever | 51 | 51 ok, 1 failed | **52** |

- Every other suite is identical.
- `make check` reports 91 runs, all passed. Its only notes are the three counts above.
- `apicheck`: 0 findings. `textcheck`: 0 findings.
- `defaultscheck` is unchanged (tbc 49, forever 52): no default was registered.
- `profilecheck/forever` counts 64 only with `tools/.cache/talentsforever.json` present. Without
  the cache, 5 are SKIP, as on the parent.

## Integrator lines

1. **`tools/data/expected-counts.json`**:
   ```
   "bookcheck/forever": 31,
   "tabscheck/forever": 27,
   "tipcheck/forever": 52,
   ```
2. **`CLAUDE.md`**, appended to these rows:
   - `Spells/Tabs.lua`: ` **T110:** the role from the book's talent spells (`Tabs.ROLE_TALENT_TREES` / `ROLE_TALENTS`, talentsforever's talent lists per tree, CC BY 4.0; tank trees and pure classes say nothing), `BookRole` (more wins, a tie nil), `Role(book)` -> `role, "talents" | "list"` (never creates the store); `SeedList(book, role)` -- a damage role takes damage that costs mana first, an either-or heal (`altKind`) among it, else heals; `Reset` stays heals-first; TBC unchanged`
   - `Spells/Book.lua`: ` **T110:** `Book:Half(family, role, pool)` -- the family, or for the damage role an either-or family's damage-half view (each rank a copy through `Numbers(.., "damage")`, the heal's reach dropped, its own dominance and suggested rank, `half` / `of`), written nowhere (generation unchanged); `Book:HalfOf(entry, role, pool)` for a `ReadSpell` entry`
   - `Spells/Words.lua`: ` **T110:** `W.OtherHalf(e)` -- `Or heals` on a damage half, `Or damage` on a heal with `alt`: value and per mana`
   - `UI/SpellTip_Forever.lua`: ` **T110:** an either-or spell's block shows the half `MD.Tabs:Role` names (`Book:Half` / `HalfOf`), the other half a detail line (`W.OtherHalf`)`
   - `Engine/ManaCooldowns.lua`: ` **T110:** MAGE (Evocation 12051, 8 s) and WARLOCK (Life Tap 1454, instant) stub rows, no value (inert) until T105's seam`
3. **`docs/TESTING.md`**, a new item in the Forever section:
   "T110 (0.16.x): on a shadow priest (or a Retribution paladin with Holy Shock), delete
   `SpellTunerDB`'s `spellTabs` for the character (or a fresh character) and open the Spells rail.
   The list should be the damage spells that cost mana, not the heals. Hover Holy Shock: Per mana
   should be the damage's (`1.07` at R4), and the detail key should show `Or heals`. On a holy
   character the same hover shows the heal and `Or damage`. Also report whether a talent you have
   **not** taken shows in the spellbook at all (`/st spell Mind Flay` on a holy priest). The role
   assumes an untaken talent's spell is absent or not known; if it is listed and known, the counts
   tie and the old heals-first seed runs."
4. **`docs/DECISIONS.md`**, a new entry "T110: the role from the book":
   "Forever's talent API is unreadable, so the role is read from the talent spells in the book:
   talentsforever's talent lists per tree, more evidence wins, a tie says nothing. Else the list's
   seeded kind. An either-or spell's tooltip shows the role's half. 'Reset to my heals' stays heals
   first (the button's words). TBC is unchanged: its list holds druid heals only and no talent
   spell."
5. **`docs/HISTORY.md`**: a dated line:
   "2026-10-02: T110 (P6, partial): the list seeded by role, either-or halves by role in the
   tooltip, the casters' mana-source stubs; values wait on T105."
6. **`docs/TOOLS.md`**, section 1:
   - tabscheck forever 24 -> 27 ("T110: the role seed").
   - bookcheck forever 29 -> 31 ("T110: Book:Half").
   - tipcheck forever 51 -> 52 ("T110: the role's half").
7. **TOCs, `tools/check.sh`**: nothing.

## Deviations

1. **`Reset` stays heals-first.** Its button (`UI/SpellRail.lua:431`, not owned) says "Reset to my
   heals". The role-aware seed runs on the first open only. If the author wants Reset by role, the
   button's words change with it: one argument in `Tabs:Reset` and the label.
2. **`tabscheck` +3, not +2.** The third check holds the role table to the committed books, so a
   misspelt talent name cannot sit in the map unseen.
3. **The role is read from the book, not from spec or talent points.** The talent API answers
   nothing readable on Forever. Whether an untaken talent's spell is absent from the Forever book
   is UNVERIFIED (TESTING item above). If it is present, `known` should be false, and only known
   families count.
4. **The caster mana sources are stubs.** Their values are T105's seam and Parse's new shapes (see
   above). This row's code only names them.
5. **The Spells pane and the rail are not by role** (files not owned). Only the tooltip and the seed
   read the role.
