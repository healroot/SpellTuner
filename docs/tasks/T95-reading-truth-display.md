# T95 -- reading truth, display: cooldowns, reach and lockouts in the book, the block and the card

Status: **built** 2026-10-01 on branch `next/T95` (base `231525d`), wave N2, awaiting the
integrator. `docs/SPEC-next.md` section 11 row T95; section 4.2 P1 (display half; T91 built the
parser half); decision 12 (the author: as recommended, 9.1); 4.5 (the reach is an upper bound);
4.2 P6's "keep both halves" (shown by role in T110). Owned files only; integrator-owned files
(`tools/check.sh`, `tools/data/expected-counts.json`, CLAUDE.md, the docs) were **not** edited --
`make check` was run with the lines below applied, then they were reverted.

Forever only: `Spells/Book.lua`, `Spells/Words.lua`, `UI/SpellTip_Forever.lua`,
`UI/SpellsPane_Forever.lua` and `Client/API_Forever.lua` are on the Forever TOCs alone (section 8:
"Parse fixes, targets, cooldowns in the book / tooltip / Spells view -- Forever yes, TBC no").
Nothing on TBC changes; no TOC line; no default registered (`defaultscheck` unchanged).

## What was built

### `Spells/Book.lua`

- **`entry.cooldown`, `entry.cooldownFrom`** (`ReadCooldown`): by default the first tooltip line
  whose **right text** `Parse.Cooldown` reads whole (`"10 sec cooldown"` beside the cast line --
  the export's shape, `R-classes` 1.2); `"tooltip"`. Only when **`MD.API.BASE_CD_READS == true`**
  does `MD.API.BaseCooldown(id)` (`GetSpellBaseCooldown`) come first, a plain read above 0 winning
  (`"base"`), a 0 or nothing falling through to the tooltip line. An unreadable tooltip (absent,
  secret, raised) keeps the previous scan's cooldown, as a secret description keeps its text.
- **`entry.targets`, `entry.reach`, `entry.targetsWhy`, `entry.lockout`** (`ApplyReach`, after
  `ApplyStale`, so a stale entry reads its kept text): `Parse.Targets` asked only of a text that
  heals or absorbs (a damage spell's reach is not a heal's); `targets` its word (`single`, `party`,
  `chain`, `selfAndTarget`, `caster`), `reach` its whole answer (count, jumps, falloff, range,
  from, partyOnly, belowPct, charges), a refusal kept as `targetsWhy` (never taken for "single");
  `lockout` is `Parse.Lockout`'s seconds from any text.
- **`IntervalFor = max(cast, GCD, cooldown)`**: the old rule is `BaseInterval`; a cooldown longer
  than it becomes the interval and the second return `"cooldown"` (`entry.intervalBy`). For a
  spell over time that is `max(duration, cooldown)`, for a channel `max(channel, cooldown)`.
  `Book.IntervalFor` is exported (the tooltip's Other lines read it).
- **`Numbers(e, kind)`**: `Rows` and `ReadSpell` share one filling of value / parts / interval /
  per mana / per second. **Per mana and per second stay one target's** (decision 12).
- **The damage half kept** (4.2 P6; nothing shows it until T110): a heal family whose text also
  deals damage gets `family.altKind = "damage"` and each rank `entry.alt = { kind = "damage",
  value, min, max, over, dur, interval, perMana, perSec }` (Holy Shock R4: 348 damage, 34.8 per
  second over its cooldown; Holy Nova).

### `Spells/Words.lua`

`W.PARTY_SIZE = 5` (the one number not in a text: a five-man party, 4.5), `W.Seconds` ("10 s",
"1.5 s", "5 min"), `W.ChainSum` (1 + f + f^2 ... over the count: Chain Heal 1.75), `W.Reach`
(`x up to 5 targets`, `up to 1.75x if 3 are hurt`, `x up to 2 targets`, `on you only`; nil for
one target), `W.ReachDetail` (`the target's party within 40 yd, up to 5 - an upper bound`,
`your party within 10 yd, ...`, `3 targets, each jump 50% of the last: up to 1.75x - an upper
bound`, `the target and you - an upper bound`, `you only`), `W.Every` (`every 10 s` when the
cooldown sets the interval). `W.PerSec` "tip": `32.0  every 10 s`; "card": `32.0 over its 10 s
cooldown`. `W.PerMana` "tip": `0.61  x up to 5 targets` -- the number one target's, the reach
beside it in words.

### `UI/SpellTip_Forever.lua`

The plain block keeps its four facts (no line added): the reach rides on **Per mana**, the pace on
**Per sec**. Behind the detail key, after the value and the crit line: **Reaches**, **Cooldown**,
**Lockout** (`15 s per target`), **Only** (`on a target below 50% health`), each only when the
book read one. An Other spell's casts to OOM counts over `Book.IntervalFor(entry)` (never under
its cooldown).

### `UI/SpellsPane_Forever.lua`

The rank card gains **Reach** (heals; `W.Reach`), **Cooldown** and **Lockout** pairs after Per sec,
each only when read; Per sec says `over its 10 s cooldown` when the cooldown paces it. A family
with none of them (every druid fixture in the suites) paints exactly as before.

### `Client/API_Forever.lua`

`MD.API.Bind({ BaseCooldown = "GetSpellBaseCooldown" })` (in the 69893 baseline; apicheck 0
findings) and **`MD.API.BASE_CD_READS = false`** -- the `BAR_READS_MAX` pattern: the integrator
flips it once T87's Forever report shows `== cooldowns` answering `GetSpellBaseCooldown` plain.

### `tools/stub_books.lua` (new, not a suite) and `tools/data/books/*` (new)

`Books.Load(class)` / `Books.Install(data, opts)`: wraps, in place, the client functions Book
reads (C_SpellBook's walk, C_Spell's name / rank / text / cast / cost / level / base spell, the
tooltip data, and -- with `opts.baseCooldowns` -- `GetSpellBaseCooldown`); a class book `alone`
(the stub's druid rows gone, slots 1..n) or added beside the stub's book from `firstSlot`; `only`
filters rows; `MD` clears that addon table's `Has` cache and marks its book dirty; the returned
function restores. The tooltip data is the name line, the extract's lines (cost / range, cast /
cooldown) and the description -- the client's order. Loaded only by bookcheck, tipcheck and
spellsui, so no other count moves.

`tools/data/books/{paladin,priest,shaman}_forever.lua`: every spell of each class's three
spellbook tabs (166 / 241 / 181 rows, all `"s": "beta"`, source "beta client 1.60.1.70009", every
row with an id), each its id, name, rank, tab, learn level, tooltip lines and description,
extracted unchanged from talentsforever's `data.json` (generated 2026-09-26), with the export's
attribution and licence (CC BY 4.0) in each header. All ASCII. The generator (run once from the
main checkout's `tools/.cache/talentsforever.json`; not committed, it is this file's):

```python
#!/usr/bin/env python3
# genbooks.py CACHE OUTDIR -- tools/data/books/<class>_forever.lua from data.json
import json, re, sys
cache, outdir = sys.argv[1], sys.argv[2]
d = json.load(open(cache)); sd, sb = d['spell_desc'], d['spellbooks']
def q(s):  # a Lua string literal, ASCII
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == '\\': out.append('\\\\')
        elif ch == '"': out.append('\\"')
        elif ch == '\n': out.append('\\n')
        elif o < 32 or o > 126: out.append('\\%d' % o)
        else: out.append(ch)
    return ''.join(out) + '"'
for cls, token in (('Paladin', 'PALADIN'), ('Priest', 'PRIEST'), ('Shaman', 'SHAMAN')):
    book, rows = sb[cls], []
    for tab in book['tabs']:
        for name, rank in tab['spells']:
            v = sd[cls + '|' + name + '|' + rank]
            m = re.match(r'^Learned at level (\d+)$', v.get('lv') or '')
            lines = ', '.join('{ %s, %s }' % (q(a), q(b)) for a, b in v['l'])
            rows.append('    { id = %d, name = %s, rank = %s, tab = %s, level = %s,\n'
                        '      lines = { %s },\n      desc = %s },'
                        % (v['id'], q(name), q(rank), q(tab['name']),
                           m.group(1) if m else 'nil', lines, q(v['d'])))
    # header: source, generated date, the export's attribution and licence (see any file)
    ...
```

## Tests

| suite | before | after | the new items |
|---|---|---|---|
| `bookcheck/forever` | 22 | **29** (+7) | 23 Holy Shock per second over its 10 s cooldown on every rank (R4 32.0), the damage half kept (`alt` 348, 34.8/s), Holy Light still 2.5 s; 24 Prayer of Healing `targets = party` from the target, 40 yd, per mana one member's (649 / 1070); 25 Chain Heal a chain of 3, jumps 2, falloff 0.5, party only, `ChainSum` 1.75, numbers the first target's; Riptide's 6 s; 26 PW:S lockout 15 and cooldown 4 on all ten ranks (per second 232 over 4 s), Renew neither; 27 Light's Vigil has no value (no kind, every rank blank, cost 1340, cooldown 6); 28 a class coverage count (below); 29 `BASE_CD_READS` false (as shipped) reads the tooltip line whatever the base says, true reads a base above 0 and falls back on a 0 |
| `tipcheck/forever` | 48 | **51** (+3) | `0.61  x up to 5 targets` (PoH), `0.41  x up to 5 targets` (Holy Nova), `1.25  up to 1.75x if 3 are hurt` (Chain Heal), the Reaches detail lines; `32.0  every 10 s` (Holy Shock) with `Cooldown 10 s` behind the key only; nothing multiplied (per mana and per sec the text's average over cost and interval, on four spells) |
| `spellsui/forever` | 50 | **52** (+2) | the card: `32.0 over its 10 s cooldown` and `Cooldown 10 s` on Holy Shock R4, Nourish unchanged; `Reach x up to 5 targets` with Per mana `0.61` (PoH), `up to 1.75x if 3 are hurt` (Chain Heal), `Lockout 15 s per target` / `Cooldown 4 s` and no Reach (PW:S); before the ASCII walk, which walks them too |
| `adaptercheck/forever` | 23 | **24** (+1) | `BaseCooldown` in `FOREVER_ONLY_NAMES`, bound to `GetSpellBaseCooldown`, a plain answer passed through, absent when the global is, `BASE_CD_READS == false` |
| every other suite | -- | unchanged | `adaptercheck/tbc` 16, `bookcheck/tbc` 2 included |

**Class coverage (bookcheck 28), pinned:**

| class | families | valued | heals | with a cooldown | heals beyond one target | heal reach refused |
|---|---|---|---|---|---|---|
| Paladin | 53 | 10 | 3 (Flash of Light, Holy Light, Holy Shock) | 22 | 0 | 0 |
| Priest | 56 | 22 | 12 | 24 | 3 (PoH, Binding Heal, Holy Nova) | 1 (Contingency Plan) |
| Shaman | 56 | 12 | 4 (Healing Wave, Lesser Healing Wave, Chain Heal, Riptide) | 18 | 1 (Chain Heal) | 0 |

### Failing first (the parent's five source files, the new tests in)

```
git checkout 231525d -- Client/API_Forever.lua Spells/Book.lua Spells/Words.lua \
    UI/SpellTip_Forever.lua UI/SpellsPane_Forever.lua
tools/run.sh --flavour forever tools/bookcheck.lua     22 ok, 7 failed  (every T95 item: cd=nil,
    interval=1.5, perSec 213.3; targets nil; ChainSum absent; lockout nil; coverage cooldowns=0
    multi=0 refused=3/12/4; BASE_CD_READS nil)
tools/run.sh --flavour forever tools/tipcheck.lua      48 ok, 3 failed  (poh "0.61", per sec
    "213.3", Holy Shock interval 1.5)
tools/run.sh --flavour forever tools/spellsui.lua      50 ok, 2 failed  ("213.3 over the 1.5 s
    global cooldown", no Reach / Cooldown / Lockout)
tools/run.sh --flavour forever tools/adaptercheck.lua  22 ok, 2 failed  (the binding count, T95)
```

With the change: 29 / 51 / 52 / 24, 0 failed.

`make check` (with the integrator's `stub_books` NOT_SUITES line and the four counts applied):
**77 run(s), all passed**, 72 counted against 72 expected; `apicheck`: 8 Forever TOCs, 63 files,
48 distinct globals, **0 findings**; `textcheck`: 9 TOCs, 102 files, **0 findings**; `luac -p`
clean on every changed file and the three data files.

## Integrator lines

**`tools/check.sh`**, `NOT_SUITES`: add `stub_books` beside `stub_art`:

```
NOT_SUITES=" harness wowstub stub_art stub_books fakepull ... "
```

**`tools/data/expected-counts.json`:**

```
"adaptercheck/forever": 24,   (was 23)
"bookcheck/forever": 29,      (was 22)
"spellsui/forever": 52,       (was 50)
"tipcheck/forever": 51,       (was 48)
```

**`MD.API.BASE_CD_READS`** (`Client/API_Forever.lua`, the line right after the `BaseCooldown`
binding): flip to `true` once T87's report from a Forever client shows `== cooldowns`'
`GetSpellBaseCooldown(18562 Swiftmend) = 15000, ...` (a plain number); adaptercheck 24's
`BASE_CD_READS == false` and bookcheck 29's `shipped == false` then move with it.

**CLAUDE.md:**

- the `Spells/Book.lua` row, append: **T95** (2026-10-01, `docs/SPEC-next.md` 4.2 P1): each entry
  carries `cooldown` / `cooldownFrom` (the tooltip line's right text through `Parse.Cooldown`;
  `MD.API.BaseCooldown` first only while `MD.API.BASE_CD_READS`; an unreadable tooltip keeps the
  last), `targets` / `reach` / `targetsWhy` (`Parse.Targets`, heals and absorbs only, a refusal
  never "single") and `lockout` (`Parse.Lockout`); `IntervalFor = max(cast, GCD, cooldown)`
  (`max(duration, cooldown)` over time, `intervalBy = "cooldown"` when the cooldown sets it,
  `Book.IntervalFor` exported); per mana and per second stay one target's (decision 12); an
  either-or heal family keeps its damage half (`family.altKind`, `entry.alt`; shown by role in
  T110).
- the `Spells/Words.lua` row, append: **T95**: `W.PARTY_SIZE` (5), `W.Seconds`, `W.ChainSum`,
  `W.Reach` (`x up to 5 targets`, `up to 1.75x if 3 are hurt`, `x up to 2 targets`, `on you
  only`), `W.ReachDetail` (who, the range, "an upper bound"), `W.Every` (`every 10 s`); `PerSec`
  "tip" `N  every 10 s`, "card" `over its 10 s cooldown`; `PerMana` "tip" the reach beside the
  one-target number -- never multiplied.
- the `UI/SpellTip_Forever.lua` row, append: **T95**: the reach on Per mana and the pace on Per
  sec (the plain block keeps four facts); Reaches / Cooldown / Lockout / Only behind the detail
  key; an Other spell's casts to OOM over `Book.IntervalFor`.
- the `UI/SpellsPane_Forever.lua` row, append: **T95**: the rank card's Reach / Cooldown / Lockout
  pairs and Per sec `over its N s cooldown`.
- the `Client/API_Forever.lua` row, append: **T95**: `BaseCooldown` (`GetSpellBaseCooldown`) and
  `MD.API.BASE_CD_READS = false` (the `BAR_READS_MAX` pattern; flipped on T87's Forever report).
- the `tools/` row, append: **`tools/stub_books.lua`** (T95, not a suite): a priest, shaman or
  paladin spellbook served to the forever stub, alone or beside the druid's
  (`Books.Install(data, { alone, only, firstSlot, baseCooldowns, MD })`), from
  `tools/data/books/<class>_forever.lua` -- each class's three tabs extracted unchanged from
  talentsforever's export (CC BY 4.0, attributed in each header); loaded by bookcheck, tipcheck
  and spellsui only.

**`docs/TOOLS.md` section 1:**

- `bookcheck.lua`: "Since **T95** (29 forever): the priest, shaman and paladin books
  (`tools/stub_books.lua`) -- Holy Shock over its 10 s cooldown with its damage half kept, Prayer
  of Healing `targets = party`, Chain Heal's chain of 3 at 50 %, PW:S's 15 s lockout and 4 s
  cooldown, Light's Vigil without a value, a pinned class coverage count, `BASE_CD_READS`."
- `tipcheck.lua`: "Since **T95** (51): `x up to 5 targets`, `up to 1.75x if 3 are hurt`, `every
  10 s`, nothing multiplied -- on the class books."
- `spellsui.lua`: "Since **T95** (52): the rank card's Reach / Cooldown / Lockout and Per sec over a
  cooldown, on class spells added beside the stub's book."
- `adaptercheck.lua`: "Since **T95** (24 forever): `BaseCooldown`, a Forever-only binding read only
  once `BASE_CD_READS` is set."
- a new line for `stub_books.lua` beside `stub_art.lua` (not a suite; what it serves, its opts).

**`docs/HISTORY.md`**, the wave N2 entry: "T95: the book carries cooldown (tooltip line by
default, `BASE_CD_READS` false), targets and lockout; `IntervalFor = max(cast, GCD, cooldown)`;
the reach said as an upper bound on the block and the card, never multiplied; priest / shaman /
paladin book fixtures (bookcheck 22 -> 29, tipcheck 48 -> 51, spellsui 50 -> 52, adaptercheck
23 -> 24)."

**`docs/TESTING.md`** (section 46, in-game check 3 / "Tooltips for other classes"): on a Forever
alt (paladin, shaman or priest) hover Holy Shock / Riptide / Prayer of Healing / Chain Heal /
Power Word: Shield: Per sec reads `N  every 10 s` (Holy Shock; 6 s Riptide; 4 s PW:S), Per mana
carries `x up to 5 targets` (PoH, Holy Nova) or `up to 1.75x if 3 are hurt` (Chain Heal), and with
the detail key Reaches / Cooldown / Lockout appear; Light's Vigil shows only its cast to OOM line.
On the author's druid: Swiftmend's Per sec now reads `every 15 s`, Tranquility's `every 5 min`
(both from their tooltip lines; see the DECISIONS line below). Report any spell whose cooldown line
is not read (a probe `== cooldowns` dump shows the line).

**`docs/DECISIONS.md`** (proposed, Forever only -- principle 10 does not require one, but the
author's druid view moves): "T95: per second and casts to OOM are over `max(cast, GCD, cooldown)`
on Forever -- a channel or HoT too (`max(duration, cooldown)`), so Tranquility reads per second
over its 5 min cooldown (sustained) rather than over its 10 s channel, and Swiftmend over 15 s.
Within-family rank verdicts are unchanged (the cooldown is the same on every rank)."

No TOC line, no defaults.

## Deviations and notes

- **Words placement.** The spec names the words (`x up to 5 targets`, `every 10 s`, `up to 1.75x
  if 3 are hurt`) but not where they go. To keep the plain block at its four facts (5.1,
  `SPEC-forever-ui.md`; tipcheck's "at most 5 plain lines" still holds) they ride on the Per mana
  and Per sec lines (two spaces apart, principle 3); the long form is behind the detail key.
- **The cooldown applies to every shape**, a channel and a HoT included (`max(base, cooldown)`),
  as the spec's rule reads; Tranquility's per second is therefore over 5 min on Forever (proposed
  DECISIONS line above). A narrower reading (cooldowns only on direct spells) is a one-line change
  in `IntervalFor`.
- **`entry.targets` only for heals and absorbs.** `Parse.Targets` describes a heal's reach; on a
  damage text it reads enemy wording as reach and refuses (Chain Lightning's "jump"). The book
  asks it only of a text that heals or absorbs; `lockout` and `cooldown` are read for every spell.
- **The damage half** is kept in data only (`entry.alt`, `family.altKind`); nothing displays it
  (T110 owns the role choice). It is asserted inside bookcheck 23 rather than as an item of its own
  (the row lists seven items; T110 adds its own two).
- **`W.PARTY_SIZE = 5`** is the one number in the words that is not in a spell's text: the most a
  party reach can be (4.5's assumption, an upper bound).
- **Forever druid view moves where a tooltip states a cooldown** (Swiftmend 15 s, Tranquility
  5 min, Innervate 6 min, Wild Growth 6 s -- Wild Growth's 7 s duration stays the interval). The
  stub's druid book carries no cooldown line, so every druid suite is byte-identical; the kit
  (`Kit_Forever.lua`) reads explicit fields only (cost, cast, min / max / over / dur) and is
  unaffected.
- **The cooldown line's live shape** is the export's (right text of the cast line); T87's probe
  confirms it on the client. Until then a cooldown the live tooltip words differently is simply
  not read (nil, the old interval) -- never guessed.
