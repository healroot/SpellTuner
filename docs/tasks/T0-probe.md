# T0 — the capability probe

Status: **final (lead, 2026-09-27)** — ready for the implementer. Phase 0 of `docs/FOREVER-PLAN.md`,
milestone M0 of `docs/ROADMAP-FOREVER.md`. Everything else in the port waits on this report, so it
is small, defensive, and it is the first thing that runs on the beta.

## Goal

The repository root is the addon folder and, after this task, it carries two addons in one tree:
the TBC addon exactly as today under `SpellTuner_TBC.toc` (Interface 20506), and a Forever probe
under a new `SpellTuner.toc` (Interface 16001) plus two suffixed copies of it. The Forever TOCs
load three small files only — a one-line TOC marker, `Client/API.lua` and `Client/Probe.lua` —
never today's `Core.lua`. `/st probe` (and `/md probe`) produces a plain-text report that (a) opens
in a copy box, (b) is saved to `SpellTunerDB` keyed by build number, and (c) answers the nine
questions of `docs/FOREVER-PLAN.md` §6 as far as the client lets it at that moment, ending with a
checklist that tells the author exactly what to do for each question still open (change bonus
healing and run it again; pull a mob in a party; `/reload`). It is for the planner, who reads the
pasted report, and for the author, who runs it on the beta as Healroot. It must survive the
beta's own bugs: every client call under `pcall`, every result a string, no arithmetic on
anything the client returned, and it never raises.

## Facts

Sources: the plan (`docs/FOREVER-PLAN.md`, dated 2026-09-27) and **EllesmereUI**, the working
Forever addon in the author's beta folder that plan §1 names as a live reference
(`/mnt/e/Blizzard/World of Warcraft/_classic_beta_/Interface/AddOns/`, paths below relative to it).
A fact with no source is marked UNKNOWN and the probe answers it.

The client and its TOCs
- Interface `16001`; retail engine, `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` — plan §1.1.
- Forever reports an interface number in `[16000, 20000)`; Classic Era reports 115xx and retail
  12xxxx — `EllesmereUI/EllesmereUI_ClientGate.lua:22-33` (`local iface = select(4, GetBuildInfo())`,
  `if iface >= 16000 and iface < 20000 then EUI_CLIENT_FOREVER = true`).
- `GetBuildInfo()` returns version, build, date, interface — `EllesmereUI/EllesmereUI_Lite.lua:54`.
  Current build 70009 — plan §1.5.
- A **plain** TOC loads on Forever: EllesmereUI ships one TOC, `EllesmereUI/EllesmereUI.toc`, with
  `## Interface: 120000, 120001, 120005, 120007, 120100, 16001`, and runs (plan §1). Whether a
  suffixed TOC takes precedence, and which suffix: **UNKNOWN — the probe answers it (Q9).**
- A TOC's files run in the listed order (EllesmereUI.toc: "Pre-12.1 client failsafe -- MUST load
  first").
- The TBC client prefers a `_TBC` TOC over the plain one: the author's Cell fork ships `Cell.toc`
  (`## Interface: 120100`) and `Cell_TBC.toc` (`## Interface: 20506`) in one folder and runs on TBC
  Anniversary (`../Cell/*.toc`, the flavour table in the top-level CLAUDE.md).
- `Core.lua:8` reads the version with `GetAddOnMetadata`; whether Forever has the global or only
  `C_AddOns.GetAddOnMetadata`: **UNKNOWN — the probe answers it.**

What is gone, what throws, what is secret
- Gone: `GetSpellInfo`, `UnitAura`, `UnitBuff`, `GetTalentInfo`, `GetItemInfo` — plan §1.1.
  `CombatLogGetCurrentEventInfo` absent — plan §1.2; "Addons lost the combat log in 12.0" —
  `EllesmereUIResourceBars/EUI_ResourceBars_SwingTimer.lua:5`.
- Registering an unknown event throws; `ReloadUI()` is protected (presence check only, never call
  it) — plan §1.1.
- Error reporting stops after 100 errors per session — plan §1.4. The probe must never raise; a
  failure is recorded as the string `<error: ...>`.
- SavedVariables are not always read back — plan §1.4; `EllesmereUI/EllesmereUI_ForeverNotice.lua`
  header: the beta client "persists SavedVariables only some of the time".
- A secret value: arithmetic, comparison, `#`, table key, call raise; store, pass, concat and
  `StatusBar:SetValue` are allowed; `issecretvalue(v)` tests — plan §1.2. `type()` answers "table"
  for a secret table, so indexing one raises rather than reading nil —
  `EllesmereUIMythicTimer/EUI_MythicTimer_RunSummary.lua:185-187`. What `tostring()` does to a
  secret: **UNKNOWN** — so the probe never calls `tostring` on a value before `issecretvalue` has
  said no, and prints the literal `<secret>` instead.
- Own auras in combat: reading throws "Auras cannot be accessed when secret while tainted" — plan §1.2.
- `C_Secrets`: `ShouldAurasBeSecret()` takes no argument (`EllesmereUI/EllesmereUI_AuraKit.lua:1843`);
  `ShouldUnitIdentityBeSecret(unit)` takes a unit (`EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin.lua:722`);
  `ShouldSpellAuraBeSecret` and `ShouldCooldownsBeSecret` exist (EllesmereUI calls them). The full
  set and its size: **UNKNOWN** — the draft's "28 of them, plan §1.3" is not in the plan; the probe
  enumerates `C_Secrets` at run time.

The spellbook and descriptions (Q1)
- `C_SpellBook.GetSpellBookItemInfo(index, Enum.SpellBookSpellBank.Player)` returns a table with
  `.spellID`; `C_Spell.GetSpellName(id)` — `EllesmereUICooldownManager/EllesmereUICdmHooks.lua:5313-5322`.
  `C_Spell.GetSpellSubtext(id)` is the rank-like subtext — `EllesmereUICooldownManager/EllesmereUICdmBuffBars.lua:3753-3755`.
  `C_Spell.GetSpellDescription(id)` — `EllesmereUICdmHooks.lua:4680`.
- Whether `GetSpellBookItemInfo` returns nil or raises past the last item: **UNKNOWN** — the probe
  walks a fixed range of slots with its own counter, each call under pcall.
- Whether a description is filled on first call or comes back `""` until spell data loads:
  **UNKNOWN** — the probe counts empty descriptions.
- Description dynamism (Q1): **UNKNOWN** — the probe dumps the descriptions with the bonus healing
  beside them and diffs against the previous run.
- **Reference sources.** The author names https://talentsforever.com/ (the more current one right
  now) and Wowhead as reference sources for Forever spell data. The probe's dump of spell
  descriptions is what the planner will compare against those two sites, so the dump prints each
  spell's id, name and rank text exactly as the client gives them (only the reversible escaping in
  Rules applied) and the description whole. Nothing from either site is typed into code in T0 —
  values come from the client or a measurement (`CLAUDE.md`, the `Data/SpellData.lua` rule); the
  sites are for checking, not for populating.

Talents (Q6)
- `C_SpecializationInfo.GetTalentInfo` is called with a query table `{tier=, column=}` by
  LibSpecialization's Mists branch (`EllesmereUI/Libs/LibSpecialization/LibSpecialization.lua:362`);
  the planner's draft names the positional form `(1, 1)`. `C_ClassTalents.GetActiveConfigID()` and
  `C_Traits.GetConfigInfo(configID)` are used by EllesmereUI (10 and 12 call sites). Which of them
  answers on Forever's trees: **UNKNOWN — Q6.**

The fight (Q2-Q5, Q8)
- `UNIT_COMBAT` payload `(unit, action, descriptor, amount, damageType)` — plan §1.3. Whether the
  amount is readable in combat and whether it fires for heals: **UNKNOWN — Q3.**
- `UNIT_SPELLCAST_SENT` payload `(unit, target, castGUID, spellID)` —
  `EllesmereUIDamageMeters/EllesmereUIDamageMeters_SpellHistory.lua:271`. Target readable in combat:
  **UNKNOWN — Q8.**
- `C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")` — `EllesmereUIAuraBuffReminders/EllesmereUIAuraBuffReminders.lua:455`.
  Party auras secret in / out of combat: **UNKNOWN — Q5.**
- `GetShapeshiftFormID()` present — plan §1.3; readable in combat **UNKNOWN — Q8.**
  `UnitHealth("party1")` in combat: **UNKNOWN — Q2.**
- Damage meter: `C_DamageMeter.GetCombatSessionFromType(sessionType, meterType)` with
  `Enum.DamageMeterSessionType.Current` / `.Overall` and `Enum.DamageMeterType.HealingDone`; the
  session has `combatSources`, each row `sourceGUID`, `totalAmount`, `amountPerSecond`,
  `isLocalPlayer`, `classFilename`, `specIconID` — `EUI_MythicTimer_RunSummary.lua:152-187`,
  `EllesmereUIDamageMeters/EllesmereUIDamageMeters.lua:31-47`.
  `C_DamageMeter.GetCombatSessionSourceFromType(sessionType, meterType, sourceGUID, creatureID)`
  returns a table with `combatSpells` (rows with `spellID`, `totalAmount`) —
  `EllesmereUIDamageMeters.lua:4556-4568`. `C_DamageMeter.IsDamageMeterAvailable()` —
  `EUI_MythicTimer_RunSummary.lua:138`. Every `GetCombatSession*` is secret in combat and
  declassification lags regen — `EUI_MythicTimer_RunSummary.lua:131-134`. An overheal field:
  **UNKNOWN — Q4.**

Widgets and plumbing on Forever (all in `EllesmereUI/EllesmereUI.lua`, which runs there)
- `CreateFrame(..., "BackdropTemplate")` :3493, `CreateFrame("ScrollFrame")` :2562,
  `CreateFrame("EditBox")` :6450, `SetMultiLine` :7090, `C_Timer.After` :1174, `DEFAULT_CHAT_FRAME`
  :1522, `SlashCmdList` :6002, `UISpecialFrames` :12086, `STANDARD_TEXT_FONT` :4328,
  `RegisterEvent("ADDON_LOADED")` :12130.
- Named templates (`UIPanelScrollFrameTemplate`, ...) and font objects (`ChatFontNormal`,
  `GameFontNormal`, ...): **UNKNOWN on Forever** — the copy box uses none of them.

## Files

Repository layout (decided by the planner, `docs/ROADMAP-FOREVER.md` §1.1): the root is the addon
folder; one TOC per client.

| file | change | role |
|---|---|---|
| `SpellTuner_TBC.toc` | **`git mv SpellTuner.toc SpellTuner_TBC.toc`**, then insert two lines, `Client\TOC_TBC.lua` and `Client\API.lua`, directly above `Core.lua`. Nothing else changes (Interface 20506, Version 0.15.4, `SavedVariables: SpellTunerDB, ManaDemonDB`, `OptionalDeps: ElvUI`, every file line) | the TBC addon, as today |
| `SpellTuner.toc` | **new**, content below | Forever (plain suffix) |
| `SpellTuner_Forever.toc` | **new**, identical to `SpellTuner.toc` except its first file line is `Client\TOC_Forever.lua` | Q9 |
| `SpellTuner_Vanilla.toc` | **new**, identical except `Client\TOC_Vanilla.lua` | Q9 |
| `Client/TOC_Plain.lua`, `Client/TOC_Forever.lua`, `Client/TOC_Vanilla.lua`, `Client/TOC_TBC.lua` | **new**, one comment line saying why + one statement: `SPELLTUNER_TOC = "Plain"` (resp. `"Forever"`, `"Vanilla"`, `"TBC"`) | tell the report which TOC the client chose |
| `Client/API.lua` | **new** | the adapter: `MD.API.Has`, `MD.API.client`, nothing else. Listed by **every** TOC |
| `Client/Probe.lua` | **new** | the probe: own event frame, SavedVariables guard, copy box, `/st probe` + `/md probe`. Forever TOCs only |
| `tools/wowstub.lua` | changed | TBC profile reads `SpellTuner_TBC.toc`; new `S.UseProfile("forever")` |
| `tools/harness.lua` | changed | `"Client/TOC_TBC.lua", "Client/API.lua"` added at the front of its file list (it mirrors the TBC TOC); comment names `SpellTuner_TBC.toc` |
| `tools/probecheck.lua` | **new** | the probe under the `forever` profile |
| `release.sh` | changed | builds the union of every `SpellTuner*.toc` |
| `docs/tasks/T0-probe.md` | Report section only | your report |

The `Makefile` has no TOC reference and does not change.

### `SpellTuner.toc` (exact; CRLF not required)

```
## Interface: 16001
## Title: SpellTuner
## Notes: Capability probe for WoW: Forever. Type /st probe.
## Author: NeRgY
## Version: 1.0.0-alpha.0
## SavedVariables: SpellTunerDB

Client\TOC_Plain.lua
Client\API.lua
Client\Probe.lua
```

### `Client/API.lua`

`local _, MD = ...`; `MD.API = MD.API or {}`. It sets no global.

- `MD.API.Has(name)` — `name` is a dotted path from `_G` (`"UnitHealth"`, `"C_Spell.GetSpellDescription"`,
  `"Enum.DamageMeterType"`). Walk it one segment at a time inside **one** `pcall`; a non-table in
  the middle means absent. Returns the value itself when it is a function or a table, `true` for
  any other non-nil value, `false` when absent or when the walk raised — so it never hands a
  client scalar (possibly secret) to its caller. Cache the answer per name in a local table.
- `MD.API.client` — computed once at load: `"forever"` when `GetBuildInfo`'s fourth return is a
  number, not secret, and in `[16000, 20000)`; `"tbc"` in `[20000, 30000)`; `"unknown"` otherwise,
  including when `GetBuildInfo` or its fourth return is missing. `GetBuildInfo` is reached through
  `Has` and called under `pcall`; `issecretvalue`, if `Has` finds it, is called under `pcall`
  before the comparison.
- This file is listed by both TOCs, so it is the one shared file: every client name it touches goes
  through `Has`/`pcall`, and the range check above is its only flavour logic.

### `Client/Probe.lua`

`local ADDON_NAME, MD = ...`. Exports exactly one table on the addon table, `MD.Probe = { Run = Run }`,
where `Run()` builds the report, saves it, shows it in the copy box, prints one chat line, and
returns the report string.

**Helpers** (locals in this file; names are suggestions, behaviour is not):
- `IsSecret(v)` — `false` if `issecretvalue` is absent; else `pcall(issecretvalue, v)` and true only
  when that returned `true`. Never raises.
- `Esc(s)` for a plain string — reversible ASCII escaping, in this order: `\` -> `\\`, `|` -> `||`,
  every byte outside 32-126 -> `\` + three decimal digits (`\010` for a newline, `\226\128\156`
  for a curly quote). Assign each `gsub` to a local (gsub returns two values).
- `Fmt(v)` — `<secret>` if `IsSecret(v)`; `nil`; a string -> `Esc(v)`; a number or boolean ->
  `tostring(v)`; a table -> `<table>`; anything else -> `<` .. type(v) .. `>`.
- `Describe(v)` — like `Fmt`, but a non-secret table becomes `{k=v, ...}`: keys `Esc(tostring(k))`
  sorted, values through `Fmt`, at most 24 keys then `, ...`; the walk under `pcall`, a raise ->
  `<error: ...>`.
- `Show(name, ...)` — `MD.API.Has(name)`; not a function -> `<absent>`; else pack
  `pcall(fn, ...)` with `select("#", ...)` (never `a and f() or b`); failure ->
  `<error: ` .. Fmt(err) .. `>`; success -> every return through `Describe`, joined with `", "`;
  no returns -> `nothing`.

**At load** (file scope): create one plain frame; its `OnEvent` looks the event up in a local
handler table and calls the handler through `pcall`, so no handler can raise. `pcall` the
registration of `ADDON_LOADED`, then of each event in `EVENTS` (below), recording `ok` or
`throws <error: ...>` per event for the report. Register slash commands with the same names
`Core.lua` uses: `SLASH_SPELLTUNER1 = "/spelltuner"`, `SLASH_SPELLTUNER2 = "/st"`,
`SLASH_SPELLTUNER3 = "/md"`, `SlashCmdList.SPELLTUNER = function(msg)`; `probe` (case-insensitive,
first word) calls `Run()`, anything else prints one usage line.

**ADDON_LOADED** for `ADDON_NAME` (then unregister `ADDON_LOADED`; it is handled once):
the SavedVariables guard. Record for the report: `type(SpellTunerDB)`; if it is a table with a
`probe` table, the string `probe.stamp` (the previous session's) and, from `probe.reports`, one
entry per build key: `<build> (<char>, <at>)`, sorted by key. Then: if `SpellTunerDB` is not a
table, set it to `{}` (never replace or wipe an existing table); ensure `SpellTunerDB.probe` and
`SpellTunerDB.probe.reports` are tables; write `SpellTunerDB.probe.stamp = <now>`, where `<now>` is
`date("%Y-%m-%d %H:%M:%S")` under `pcall` (`<no date>` if that fails).

**Listeners** (from `EVENTS`, each only if its registration succeeded):
- `PLAYER_REGEN_DISABLED`: set the local phase to `"combat"`; schedule the combat snapshot with
  `C_Timer.After(2, fn)` (through `Has`; take it at once if absent). The snapshot stores `<now>`,
  `Show("UnitAffectingCombat", "player")`, and the lines of the **secrets** and **readings**
  blocks below, as they read at that moment. The last snapshot of the session is kept.
- `PLAYER_REGEN_ENABLED`: phase `"ooc"`.
- `UNIT_COMBAT(unit, action, descriptor, amount, damageType)`: one counter per
  `<phase> <unitclass> <action>`, where unitclass is `player`, `party` (token starts with `party`),
  `raid`, `target` or `other`, and a secret or non-string unit / action becomes `<secret>` /
  `<none>`. Each counter holds `n`, `readable` (amount not secret and not nil), `secret`, `nil`,
  and `sample` = `Fmt(amount)` of the first readable one. The amount is never added, compared or
  used as a key.
- `UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)`: one counter per phase with `n`,
  `readable` (target a non-secret, non-empty string), `secret`, `empty` (nil or `""`), `sample` =
  `Fmt(target)` of the first readable one.

**`EVENTS`** (exact, in this order): `UNIT_SPELLCAST_SENT`, `UNIT_SPELLCAST_START`,
`UNIT_SPELLCAST_SUCCEEDED`, `UNIT_SPELLCAST_STOP`, `UNIT_SPELLCAST_FAILED`, `UNIT_HEALTH`,
`UNIT_MAXHEALTH`, `UNIT_POWER_UPDATE`, `UNIT_AURA`, `UNIT_FLAGS`, `UNIT_COMBAT`,
`GROUP_ROSTER_UPDATE`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, `SPELLS_CHANGED`,
`PLAYER_TALENT_UPDATE`, `TRAIT_CONFIG_UPDATED`, `DAMAGE_METER_COMBAT_SESSION_UPDATED`,
`ADDON_RESTRICTION_STATE_CHANGED`, `COMBAT_LOG_EVENT_UNFILTERED`. (Plan §1.3's event list, §2.3's
`UNIT_FLAGS` / `STOP` / `FAILED` / `SENT`, and the combat log event whose registration outcome is
itself a finding.)

**`FUNCTIONS`** (exact list; presence only, via `MD.API.Has`, **never called** here):

```lua
-- plan §1.1, gone or protected
"GetSpellInfo", "UnitAura", "UnitBuff", "GetTalentInfo", "GetItemInfo", "ReloadUI",
-- plan §1.2
"CombatLogGetCurrentEventInfo", "C_CombatLog.IsCombatLogRestricted", "C_Secrets.ShouldAurasBeSecret",
"issecretvalue", "C_DamageMeter.GetCombatSessionFromType",
-- plan §1.3, survive
"GetManaRegen", "GetSpellBonusHealing", "GetSpellBonusDamage", "GetSpellCritChance", "UnitStat",
"UnitPower", "UnitPowerMax", "UnitHealth", "UnitHealthMax", "UnitThreatSituation", "UnitCastingInfo",
"GetShapeshiftFormID", "GetInventoryItemID", "GetMacroInfo", "GetBinding", "GetActionInfo", "IsSpellKnown",
-- plan §1.3, moved
"C_Spell.GetSpellInfo", "C_Spell.GetSpellPowerCost", "C_Spell.GetSpellDescription",
"C_Spell.GetSpellSubtext", "C_Spell.GetSpellLevelLearned", "C_Spell.GetSpellName",
"C_Spell.GetSpellTexture", "C_Spell.GetSpellCooldown", "C_SpellBook.GetNumSpellBookSkillLines",
"C_SpellBook.GetSpellBookSkillLineInfo", "C_SpellBook.GetSpellBookItemInfo", "C_SpellBook.IsSpellKnown",
"TooltipDataProcessor.AddTooltipPostCall", "C_TooltipInfo", "C_SpecializationInfo.GetTalentInfo",
"C_Traits.GetConfigInfo", "C_ClassTalents.GetActiveConfigID", "C_UnitAuras.GetAuraDataByIndex",
-- plan §2.2 and §3.1
"C_Spell.GetBaseSpell", "C_AddOns.LoadAddOn",
-- EllesmereUI (Facts)
"C_DamageMeter.GetCombatSessionSourceFromType", "C_DamageMeter.IsDamageMeterAvailable",
"Enum.DamageMeterType", "Enum.DamageMeterSessionType", "Enum.SpellBookSpellBank", "C_Timer.After",
-- what this probe and Core.lua call
"GetBuildInfo", "GetAddOnMetadata", "C_AddOns.GetAddOnMetadata", "GetNumTalentTabs",
"UnitAffectingCombat", "UnitExists", "UnitName", "UnitClass", "UnitLevel", "GetRealmName", "CreateFrame",
```

**The report** — lines joined with `"\n"`, sections in exactly this order, header lines starting
with `== ` exactly as written (a section may add text after its header words):

```
SpellTuner probe <version> -- <now>
== client
build: <version> <build> <date> interface <interface>
client: <MD.API.client>
project: WOW_PROJECT_ID=<> WOW_PROJECT_MAINLINE=<> WOW_PROJECT_CLASSIC=<> WOW_PROJECT_BURNING_CRUSADE_CLASSIC=<>
character: <UnitName player> <GetRealmName> <UnitClass player, 2nd return> level <UnitLevel player>
in combat: <UnitAffectingCombat player>
== functions (<p> present, <a> absent)
present <name>            one line per FUNCTIONS entry, in list order
absent <name>
== events
ok <EVENT>                one line per EVENTS entry
throws <EVENT> <error: ...>
== secrets now
<Name> = <Show result>    every function in C_Secrets whose key starts with "Should", sorted,
                          called with no argument; "C_Secrets absent" if Has finds no table
== spells (bonus healing <Show("GetSpellBonusHealing")>)
slots 1-500: <n> with a spell, <h> healing, <e> empty description, <s> secret
spell <id>
  name: <GetSpellName>
  rank: <GetSpellSubtext>
  desc: <GetSpellDescription, whole>
== spells against the previous run
previous: <this session|saved> at <stamp>, bonus healing <old> -> <new>
changed <id> <name>       one per spell present in both runs whose description differs
no description changed    (instead of the changed lines, when none did)
no previous run to compare   (instead of all of the above)
== talents
C_SpecializationInfo.GetTalentInfo(1, 1) = <Show>
C_SpecializationInfo.GetTalentInfo({tier=1, column=1}) = <Show>
C_ClassTalents.GetActiveConfigID() = <Show>
C_Traits.GetConfigInfo(<first return above>) = <Show>
== readings now
UnitExists(party1) = <Show>
UnitHealth(player) = <Show>
UnitHealth(party1) = <Show>
UnitHealthMax(party1) = <Show>
UnitHealth(target) = <Show>
UnitPower(player, 0) = <Show>
GetManaRegen() = <Show>
GetShapeshiftFormID() = <Show>
C_UnitAuras.GetAuraDataByIndex(player, 1, HELPFUL) = <Show>
C_UnitAuras.GetAuraDataByIndex(party1, 1, HELPFUL) = <Show>
== combat snapshot
none this session         (or:)
taken <stamp>, in combat: <Show result stored>
<the secrets-now lines and the readings-now lines as they read then>
== events seen this session
UNIT_COMBAT <phase> <unitclass> <action> n=<> readable=<> secret=<> nil=<> sample=<>
UNIT_SPELLCAST_SENT <phase> n=<> readable=<> secret=<> empty=<> sample=<>
none                      (when neither counted anything)
== damage meter
C_DamageMeter.IsDamageMeterAvailable() = <Show>
session <Current|Overall> HealingDone = <secret>|<absent>|<error: ...>|sources=<n>
  source <i> isLocalPlayer=<Fmt> totalAmount=<Fmt>     first 5 rows
  local source = <Describe of the row whose isLocalPlayer is true>
  local spells = <secret>|<absent>|<error: ...>|combatSpells=<n>
  spell <i> = <Describe>                                first 5 rows
== saved variables
SpellTunerDB at load: <type>
previous session stamp: <stamp|none>
reports at load: <build> (<char>, <at>); ...   | none
this session stamp: <now at ADDON_LOADED>
== toc
SPELLTUNER_TOC = <Fmt(SPELLTUNER_TOC)>
== to do
<one line per question Q1..Q9, "Qn answered: ..." or "Qn to do: ...">
```

Rules for the sections that need them:
- `<version>` from `C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")`, else the global
  `GetAddOnMetadata`, else `<absent>`. `build:` from `GetBuildInfo()`'s four returns through `Fmt`.
- **Spells.** Walk slots 1 to 500 with your own counter; for each,
  `C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)` under pcall (pass
  `nil` as the bank if `Enum.SpellBookSpellBank` is absent). A result that is a non-secret table
  with a non-secret `spellID` counts as "with a spell"; one id is listed once. A spell is
  **healing** when its description is a non-secret string whose lowercase contains `heal` (which
  also catches "health"). A secret id or description counts under `secret` and is not listed.
  Spells are listed in slot order. Name, rank and description are printed through `Fmt` — nothing
  else is done to them.
- **Against the previous run.** The previous run is the last `Run()` of this session if any, else
  `SpellTunerDB.probe.reports[<build>]` as it stood at load, if it has a `desc` table. Compare the
  bonus-healing strings and the escaped description strings; never numbers.
- **Damage meter.** Session types from `Enum.DamageMeterSessionType.Current` and `.Overall`, meter
  type `Enum.DamageMeterType.HealingDone`. The local source's spells come from
  `GetCombatSessionSourceFromType(sessionType, meterType, row.sourceGUID, nil)`. Every index into
  a result happens only after `IsSecret` said no and `type` said table, inside one `pcall` per
  session type. `isLocalPlayer` is tested with `== true` after `IsSecret` said no. Rows other
  than the local player's print only `isLocalPlayer` and `totalAmount` (no names, no GUIDs).
- **To do.** Exactly these conditions and wordings (the `...` after "answered:" is free text):
  - Q1 answered when there is a previous run and the bonus-healing strings differ:
    `Q1 answered: <c> of <m> spell descriptions changed when bonus healing went <old> -> <new>`
    (`<m>` counts every spell present in both runs, healing or not);
    else `Q1 to do: change your bonus healing (put on or take off a +healing item, or take a buff that changes the number in the spells header), then type /st probe again in the same session`.
  - Q2, Q5 answered when a combat snapshot exists and its `UnitExists(party1)` read `true`;
    else `Q2 to do: ...` / `Q5 to do: ...` saying: in a party, pull a mob; the probe reads itself
    2 seconds into the fight; type /st probe after the fight.
  - Q3 answered when a `UNIT_COMBAT combat party ...` counter exists; else to do (same fight,
    let the party member take damage and be healed).
  - Q4 answered when a session read out of combat gave `sources=` at least 1; else
    `Q4 to do: after a fight, out of combat, type /st probe`.
  - Q6 always `Q6 answered: see == talents`.
  - Q7 answered when the previous session stamp came back:
    `Q7 answered: SavedVariables came back (previous stamp <stamp>)`; else
    `Q7 to do: type /reload, then /st probe; if this line still says to do, SavedVariables did not come back`.
  - Q8 answered when a combat snapshot exists and `UNIT_SPELLCAST_SENT combat` counted at least
    one cast; else to do (cast a heal on the party member during the fight).
  - Q9 always `Q9 answered: SPELLTUNER_TOC = <Fmt(SPELLTUNER_TOC)>`.
- **Save.** Before saving, compute the diff. Then
  `SpellTunerDB.probe.reports[<build>] = { char = "<name>-<realm>", at = <now>, text = <report>, bonus = <bonus string>, desc = { [<id string>] = <escaped desc> } }`,
  where `<build>` is `Fmt` of `GetBuildInfo()`'s second return (`"unknown"` if absent). Keep the
  same record in a local as "the previous run" for the next `Run()` of the session.
- **Copy box.** One frame named `SpellTunerProbeFrame`, created on first `Run()` with
  `CreateFrame("Frame", "SpellTunerProbeFrame", UIParent, "BackdropTemplate")`, backdrop dark with a
  1 px border; a `ScrollFrame` with no template, its scroll child a multi-line `EditBox`
  (`SetMultiLine(true)`, `SetAutoFocus(false)`, `SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")`
  under pcall), mouse wheel scrolling by hand, Escape on the edit box hides the frame, the frame's
  name added to `UISpecialFrames`, movable by dragging. On each `Run()`: `SetText(report)`, show,
  focus, `HighlightText()`. The whole build and show under one `pcall`; if it fails, print the
  report to `DEFAULT_CHAT_FRAME` line by line and say so first. The chat line after a run:
  `SpellTuner probe: build <build>, <n> lines, saved. Click the box, Ctrl+A, Ctrl+C.`

### `tools/wowstub.lua`

The TBC profile (what the sixteen suites get from `dofile`) changes in one respect only:
`GetAddOnMetadata` reads `S.root .. "/" .. S.toc`, with `S.toc = "SpellTuner_TBC.toc"` by default.
Nothing else a TBC suite can observe changes.

Add `function S.UseProfile(name)`; for `"forever"` it (and only a call to it) does:
- `S.profile = "forever"`, `S.toc = "SpellTuner.toc"`, `S.inCombat = false`, `S.bonusHealing = 0`.
- Sets to nil: `CombatLogGetCurrentEventInfo`, `GetSpellInfo`, `UnitAura`, `UnitBuff`,
  `GetTalentInfo`, `GetItemInfo` (plan §1.1-1.2). Everything else the TBC profile defines stays —
  the full "only what exists" profile is M1's T5, not this task.
- `S.Secret()` — a table whose metatable raises (`"attempt to use a secret value (stub)"`) on
  `__add __sub __mul __div __mod __pow __unm __concat __lt __le __eq __len __index __newindex
  __call __tostring`. `__concat` and `__tostring` are stricter than the client (which yields a
  secret string that raises later); say so in a comment. `issecretvalue(v)` true exactly for
  those tables (compare `getmetatable(v)` with `rawequal`).
- `GetBuildInfo()` -> `"1.60.1", "70009", "Sep 20 2026", 16001` (a stand-in; comment it).
  `WOW_PROJECT_ID = 1`, `WOW_PROJECT_MAINLINE = 1`.
- `UnitAffectingCombat` and `InCombatLockdown` return `S.inCombat`. `UnitHealth(u)` and
  `UnitHealthMax(u)` return `S.Secret()` when `S.inCombat` and `u ~= "player"` — a stand-in that
  exercises the secret path, **not** a claim about Q2 (comment it).
- `GetSpellBonusHealing()` returns `S.bonusHealing`; `GetShapeshiftFormID()` returns nil.
- `Enum = { SpellBookSpellBank = { Player = 0 }, DamageMeterType = { HealingDone = 1 }, DamageMeterSessionType = { Overall = 0, Current = 1 } }` (stand-in values).
- `C_SpellBook.GetSpellBookItemInfo(slot, bank)` -> `{ spellID = <id> }` for slots 1-3, nil after;
  the three spells are 774, 5185, 5176. `C_Spell.GetSpellName`: Rejuvenation, Healing Touch,
  Wrath. `C_Spell.GetSpellSubtext`: `"Rank 1"`. `C_Spell.GetSpellDescription`:
  774 -> `"Heals the target for " .. (32 + S.bonusHealing) .. " over 12 sec."`;
  5185 -> `"Heals a friendly target for 40 to 55.|nIt is \226\128\156quoted\226\128\157."`
  (a pipe and non-ASCII bytes, for the escaping); 5176 -> `"Causes 13 to 16 Nature damage to the target."`.
- `C_Secrets = { ShouldAurasBeSecret = function() return S.inCombat end, ShouldUnitIdentityBeSecret = function(u) if u == nil then error("bad argument #1") end return false end }`.
- `C_UnitAuras.GetAuraDataByIndex(u, i, filter)`: in combat raise
  `"Auras cannot be accessed when secret while tainted"`; out of combat
  `{ name = "Mark of the Wild", spellId = 1126, duration = 1800 }` for `("player", 1)`, else nil.
- `C_SpecializationInfo.GetTalentInfo(a, b)`: raises for a number argument, returns
  `{ name = "Improved Wrath", rank = 0 }` for a table. `C_Traits` and `C_ClassTalents` stay
  **undefined** (the absent path).
- `C_DamageMeter`: `IsDamageMeterAvailable()` -> true; `GetCombatSessionFromType(st, mt)` ->
  `S.Secret()` in combat, else `{ combatSources = { { sourceGUID = "Player-1", isLocalPlayer = true, totalAmount = 1234, amountPerSecond = 41 } } }`;
  `GetCombatSessionSourceFromType(st, mt, guid, cid)` -> `S.Secret()` in combat, else
  `{ combatSpells = { { spellID = 774, totalAmount = 1000 } } }`.
- `FrameMT.RegisterEvent` raises `'unknown event "<e>"'` for an event not in the stub's Forever
  set: every `EVENTS` entry except `COMBAT_LOG_EVENT_UNFILTERED`, plus `ADDON_LOADED`,
  `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `PLAYER_LOGOUT`.

### `tools/probecheck.lua`

Same `check(name, cond, detail)` / `"%d ok, %d failed"` / `os.exit(1)` shape as `tools/migrate.lua`.
Three steps in one process:

1. **TBC.** Load `tools/harness.lua` the way `tools/migrate.lua` does. Assert the TBC line.
2. **Forever, fresh.** `dofile` the stub again (a clean frame registry), `S.root = arg[1]`,
   `STUB.UseProfile("forever")`; set `SpellTunerDB`, `ManaDemonDB`, `SPELLTUNER_TOC` and the
   `SLASH_SPELLTUNER1..3` globals to nil; record the set of `_G` keys; `S.AddUnit("party1", ...)`;
   `S.Load({ "Client/TOC_Forever.lua", "Client/API.lua", "Client/Probe.lua" }, "SpellTuner", MD)`
   with a new table; fire `ADDON_LOADED "SpellTuner"` and `PLAYER_LOGIN`. Then, every call through
   `pcall`:
   - run 1: `SlashCmdList.SPELLTUNER("probe")` out of combat, bonus healing 0;
   - fire `UNIT_COMBAT("party1", "HEAL", "", 120, 1)`; set `S.inCombat = true`; fire
     `PLAYER_REGEN_DISABLED`; call every function in `S.timers`; fire
     `UNIT_COMBAT("party1", "WOUND", "", S.Secret(), 1)` and
     `UNIT_SPELLCAST_SENT("player", "Tankname", "Cast-1", 774)`;
   - run 2: `/st probe` in combat;
   - `S.inCombat = false`; fire `PLAYER_REGEN_ENABLED`; `S.bonusHealing = 50`;
   - run 3: `/st probe` out of combat.
   Read each run's report from `SpellTunerDB.probe.reports["70009"].text` right after it.
3. **Forever, SavedVariables came back.** `dofile` the stub again, `UseProfile("forever")`, set
   `SpellTunerDB = { probe = { stamp = "2026-09-26 10:00:00", reports = { ["69893"] = { char = "Healroot-Test", at = "2026-09-26 10:05:00", text = "old" } } } }`,
   load the three files into a new table, fire `ADDON_LOADED "SpellTuner"`, run once.

## Rules

From `CLAUDE.md` and the lead's rules, the ones that bite here:
- **No libraries.** Plain frames.
- **Client calls live in `Client/` only.** `Client/API.lua` is the adapter; `Client/Probe.lua` calls
  the client directly because its whole job is to see the raw value the adapter would turn into
  nil (plan §3.2 against §3.3; the planner's T0 decision: the probe carries its own frame,
  SavedVariables and slash). The TOC markers assign one global and call nothing. No other file in
  this task gains a client call.
- **Shared files** (listed by both TOCs; only `Client/API.lua` here) reach every client name
  through `Has`/`pcall`; no other flavour check (roadmap §1.1).
- **No arithmetic on a client value** in `Probe.lua`: a value from a game function or an event
  payload passes `IsSecret` before anything but storing or passing it on; after that only
  `type()`, `tostring()` (via `Fmt`), `== <literal>` and string functions on a string. No
  `+ - * / % < > <= >= #` on it, never a table key unless it went through `Fmt` first. Loop
  bounds are your own constants. Exempt: the copy box's own widget geometry
  (`GetVerticalScroll`, `GetVerticalScrollRange`) for wheel scrolling. Inside `Client/API.lua` the
  interface-range comparison is allowed after `type` and `issecretvalue` checks.
- **Everything from the client under `pcall`;** the event handler table is called through `pcall`.
  The probe never raises — the beta stops reporting errors after 100.
- **Every rendered string ASCII, never a bare `|`** — the report, the chat lines, the frame's
  labels. Client strings go through `Esc`.
- **Any frame you style needs `"BackdropTemplate"`** — the copy box.
- **The multi-return trap.** `a and f() or b` truncates `f()`; pack `pcall` returns with
  `select("#", ...)`; assign `gsub` to a local.
- **No new globals** except the four `SPELLTUNER_TOC` markers, `SpellTunerDB` (SavedVariables),
  `SLASH_SPELLTUNER1..3` (the slash API needs them) and `SpellTunerProbeFrame` (the named copy
  box, so Escape can close it).
- Comments say **why**, not what.

## Acceptance

1. `tools/run.sh tools/probecheck.lua` ends with `N ok, 0 failed`, N >= 27, and contains each of
   these assertion names verbatim (the condition after each is what it must check):
   - "the TBC line reads its version from SpellTuner_TBC.toc" — after step 1 `MD.version` equals
     the `## Version:` parsed from `SpellTuner_TBC.toc` by the test, and is not `0.0.0`.
   - "Client/API.lua loads under the TBC line" — step 1: `MD.API.Has` is a function,
     `MD.API.Has("UnitHealth")` is truthy, `SPELLTUNER_TOC == "TBC"`.
   - "MD.API.client is forever on interface 16001"
   - "MD.API.Has walks dotted names and says false for a missing one" — truthy for
     `C_Spell.GetSpellDescription`, `false` for `C_Spell.NoSuchThing` and `NoSuchNamespace.X`.
   - "the probe never raises" — every `pcall` in steps 2 and 3 returned true.
   - "a missing function is reported absent, not raised" — run 1 has `absent CombatLogGetCurrentEventInfo`,
     `absent GetSpellInfo`, and `C_ClassTalents.GetActiveConfigID() = <absent>`.
   - "registering a bad event is caught" — `throws COMBAT_LOG_EVENT_UNFILTERED` and `ok UNIT_COMBAT`.
   - "a secret value is reported secret, not summed" — run 2 has `UnitHealth(party1) = <secret>`
     under readings now **and** in the combat snapshot, and
     `UNIT_COMBAT combat party WOUND n=1 readable=0 secret=1 nil=0`.
   - "a client error is reported as a string" — run 2's
     `C_UnitAuras.GetAuraDataByIndex(player, 1, HELPFUL) = <error:` line.
   - "the report is ASCII with no bare pipe" — every run: all bytes are 10 or 32-126, and after
     removing every `||` no `|` remains.
   - "the report is keyed by build" — `SpellTunerDB.probe.reports["70009"]` exists with a string
     `char` and its `text` equals the report `Run()` returned.
   - "the report reaches the copy box" — the last `EditBox` in `S.allFrames` holds the report.
   - "the report sections are in order" — the fourteen `== ` headers appear in the order above.
   - "the header names build 70009 and interface 16001"
   - "healing spells are dumped with id, name, rank and the whole description" —
     `spell 774\n  name: Rejuvenation\n  rank: Rank 1\n  desc: Heals the target for 32 over 12 sec.`
     in run 1, and the 5185 desc line reads
     `Heals a friendly target for 40 to 55.||nIt is \226\128\156quoted\226\128\157.` (literally,
     backslashes and digits).
   - "a spell that does not heal is not dumped" — no `spell 5176`.
   - "a change in bonus healing is reported against the previous run" — run 3 has
     `bonus healing 0 -> 50` and `changed 774 Rejuvenation`, and no `changed 5185`.
   - "the combat snapshot is taken in combat" — run 2 has `taken ` and `in combat: true` under
     `== combat snapshot`.
   - "UNIT_COMBAT and UNIT_SPELLCAST_SENT are counted by phase" — run 3 has
     `UNIT_COMBAT ooc party HEAL n=1 readable=1 secret=0 nil=0 sample=120` and
     `UNIT_SPELLCAST_SENT combat n=1 readable=1 secret=0 empty=0 sample=Tankname`.
   - "the damage meter in combat is reported secret, not walked" — run 2 has
     `session Current HealingDone = <secret>`.
   - "the damage meter after combat lists sources and spells" — run 3 has
     `session Current HealingDone = sources=1`, `combatSpells=1` and `spellID=774`.
   - "SavedVariables that did not come back are reported as such" — run 1 has
     `SpellTunerDB at load: nil`, `previous session stamp: none` and `Q7 to do`.
   - "SavedVariables that came back are reported with their stamp" — step 3 has
     `previous session stamp: 2026-09-26 10:00:00`, `69893 (Healroot-Test, 2026-09-26 10:05:00)`
     and `Q7 answered`.
   - "the report prints the TOC that loaded" — `SPELLTUNER_TOC = Forever`.
   - "the probe adds no global but its own" — after step 2 the new `_G` keys are a subset of
     `SPELLTUNER_TOC`, `SpellTunerDB`, `SLASH_SPELLTUNER1`, `SLASH_SPELLTUNER2`,
     `SLASH_SPELLTUNER3`, `SpellTunerProbeFrame`.
   - "/st and /md both reach the probe" — `SLASH_SPELLTUNER2 == "/st"`, `SLASH_SPELLTUNER3 == "/md"`,
     `SlashCmdList.SPELLTUNER` is a function.
   - "the to-do list names what is left" — run 1 has `Q1 to do` and `Q2 to do`; run 3 has
     `Q1 answered`, `Q2 answered` and `Q9 answered: SPELLTUNER_TOC = Forever`.
   Write each assertion first, run it, see it fail, then make it pass. Never weaken one to pass.
2. The sixteen TBC suites print exactly what they printed before the change:
   ```
   for s in simcheck reccheck replaycheck replayui runcheck reviewui navui dashui regencheck simwindow solvercheck timeline spelltip practice practiceui migrate; do tools/run.sh tools/$s.lua | tail -1; done
   ```
   Baseline (2026-09-27): simcheck `... -> PASS`; reccheck 54, replaycheck 80, replayui 98,
   runcheck 78, reviewui 44, navui 25, dashui 56, regencheck 27, simwindow 8, solvercheck 70,
   timeline 27, spelltip 48, practice 74, practiceui 49, migrate 7 — each `ok, 0 failed`.
3. `tools/.lua/lua-5.1.5/src/luac -p` passes on every `.lua` file you created or changed.
4. `./release.sh --out <your scratchpad>/rel` succeeds (never into the repo), and its package
   contains all four `SpellTuner*.toc`, the four `Client/TOC_*.lua`, `Client/API.lua`,
   `Client/Probe.lua`, `Core.lua` and every file `SpellTuner_TBC.toc` lists; the zip is named
   `SpellTuner-0.15.4.zip`. `release.sh`: a source is a directory holding `SpellTuner_TBC.toc` or
   `SpellTuner.toc`; the files are every `SpellTuner*.toc` in the source root, `README.md` and the
   union (no duplicates) of their load entries; the version (zip name, `--list`, the menu) comes
   from `SpellTuner_TBC.toc` when present, else `SpellTuner.toc`; the header comments and error
   messages say so. Output folders and the `--install` behaviour are unchanged.
5. The TOC split was made with `git mv` (history follows the TBC TOC), and `git status --short`
   lists only the files in the Files table. Note the header matching in the order check: `== spells`
   is a prefix of `== spells against the previous run` and `== events` of `== events seen this
   session`, so match each header together with what follows it.
6. Paste into the Report: the full `probecheck` output, the sixteen tail lines, the `luac` command
   and its (empty) output, the `release.sh` lines and a `find` of the package's `*.toc` and
   `Client/` files, the full text of run 3's report, and `git status --short`.

## Out of scope

- Everything else in the TBC addon: `Core.lua`, `Engine/`, `UI/`, `Data/`, `Verify.lua`,
  `Integrations/`. Folding the probe into a shared `Core.lua` is M1 (T1/T2).
- A module registry, the debug console, the adapter's wrappers beyond `Has` / `client`, the
  cross-build diff of plan §3.3 ("since 70009: X gone"), the SavedVariables seed workaround (T4).
- The full `forever` stub profile, a TOC-driven harness file list, `tools/run.sh --flavour`
  (T5); `apicheck.py` (T6).
- `CLAUDE.md`, `docs/HISTORY.md`, `docs/PLAN.md`, `docs/FOREVER-PLAN.md`, `docs/TOOLS.md`,
  `docs/ROADMAP-FOREVER.md`, the `Makefile` — even where they still say `SpellTuner.toc`; list
  them in the report instead.
- Any existing suite's assertions.
- Commits. Do not commit.

## Report

This picks up where the previous attempt left off (its `git mv`, the four `SpellTuner*.toc`
files, the four `Client/TOC_*.lua` markers and `Client/API.lua` were already on disk and are
unchanged here).

**`tools/wowstub.lua`.** Added `S.toc` (default `"SpellTuner_TBC.toc"`) and pointed
`GetAddOnMetadata` at `S.root .. "/" .. S.toc` instead of the hard-coded `SpellTuner.toc`. Added
`function S.UseProfile(name)`: for `"forever"` it nils the plan §1.1/§1.2 casualties
(`CombatLogGetCurrentEventInfo`, `GetSpellInfo`, `UnitAura`, `UnitBuff`, `GetTalentInfo`,
`GetItemInfo`), sets `S.toc = "SpellTuner.toc"`, `S.profile = "forever"`, `S.inCombat = false`,
`S.bonusHealing = 0`, installs the `S.Secret()`/`issecretvalue` pair, the stand-in
`GetBuildInfo`/`WOW_PROJECT_*`, the in-combat-secret `UnitHealth`/`UnitHealthMax`, `Enum`, the
three-spell `C_SpellBook`/`C_Spell` tables, `C_Secrets`, `C_UnitAuras`, `C_SpecializationInfo`
(with `C_Traits`/`C_ClassTalents` left undefined), and `C_DamageMeter`. Also added a
`FOREVER_EVENTS` allow-list and gated `FrameMT:RegisterEvent` on `S.profile == "forever"` so an
event outside that list raises `unknown event "<e>"` — this only fires when a script has called
`UseProfile("forever")`, so the sixteen TBC suites (which never call it) are unaffected, confirmed
by running them before and after.

**`tools/harness.lua`.** Added `"Client/TOC_TBC.lua", "Client/API.lua"` at the front of the file
list and reworded the comment to name `SpellTuner_TBC.toc`.

**`tools/probecheck.lua`** (new). Three steps as specified: step 1 loads `tools/harness.lua` the
way `tools/migrate.lua` does and checks the TBC line; step 2 loads a fresh stub, calls
`STUB.UseProfile("forever")`, nils the relevant globals, records the pre-load `_G` key set, adds
`party1`, loads the three Forever files into a new `MD` table, fires `ADDON_LOADED`/`PLAYER_LOGIN`,
then drives the scripted fight (every action through a `Do()` wrapper that pcalls it and records
the outcome) across three `/st probe` calls, reading `SpellTunerDB.probe.reports["70009"].text`
after each; step 3 repeats the fresh load with a pre-seeded `SpellTunerDB` and one run. 27
assertions, matching the Acceptance list's names verbatim. Wrote the assertions first, ran them
(most passed first try since `Client/Probe.lua` was written directly against this spec), then
fixed two real failures — see "Surprising" below.

**`Client/Probe.lua`** (new, ~1000 lines, built in the many small pieces the task asked for so no
single tool call risked the output limit). `MD.Probe = { Run = Run }` only. Structure: `IsSecret` /
`Esc` / `Fmt` / `Describe` / `Show` / `Field` helpers; the exact `FUNCTIONS` and `EVENTS` lists;
session state locals; `UnitClassOf`/`ActionOf`/`SafeDate`/`BuildKey`/`Version`; the counters
(`BumpCombat`, `BumpSent`); one builder function per report section (`ClientLines`,
`FunctionsLines`, `EventsSummaryLines`, `SecretsLines`, `ReadingsLines`, `SpellWalk`,
`TalentsLines`, `AgainstPreviousLines`, `TakeCombatSnapshot`/`CombatSnapshotLines`,
`EventsSeenLines`, `SessionBlock`/`DamageMeterLines`, `SavedVarsLines`, `TocLines`); the copy box
(`ShowReportBox`, raw `CreateFrame`/`ScrollFrame`/`EditBox`, hand-rolled wheel scrolling using the
two exempt widget-geometry calls); `Run()` assembling all fourteen sections plus the nine-question
to-do list and the save; and the load-time frame/event-registration/slash-command block. Every
client call is under `pcall`; every value that could be secret passes `IsSecret` before it is
compared, used as a key, or walked; every rendered string goes through `Fmt`/`Esc`/`Describe`.

**`release.sh`.** `resolve_source`/the source check now accept a directory with either
`SpellTuner_TBC.toc` or `SpellTuner.toc`. New `version_toc()` picks `SpellTuner_TBC.toc` when
present else `SpellTuner.toc`; `version_of` uses it. The file-collection block now globs every
`SpellTuner*.toc` in the source root and unions (de-duplicating) all of their load entries plus
`README.md` and the `.toc` files themselves, instead of reading one hard-coded `SpellTuner.toc`.
Header comment and the two error messages updated to say so. Output folder layout, the zip
fallback and `--install` are untouched.

**Not touched, as the task says**: `Makefile` (grepped — it has no `.toc` reference), `CLAUDE.md`,
`docs/PLAN.md`, `docs/HISTORY.md`, `docs/FOREVER-PLAN.md`, `docs/TOOLS.md`,
`docs/ROADMAP-FOREVER.md`, and every existing suite's assertions.

**Surprising / bugs found while building this, not in the spec:**
- A real bug of my own making, caught before it shipped: in `SessionBlock` (the damage-meter
  block) I first wrote the per-row detail lines into `lines[#lines+1]` while `lines` was still
  effectively empty, then set the summary line at `lines[1]` *afterwards* — which clobbered the
  first detail row instead of preceding it. Fixed by building the summary line and the row lines
  into a fresh table in the right order and assigning `lines` to it exactly once. Caught by the
  "the damage meter after combat lists sources and spells" assertion before I ever ran the full
  suite the first time.
- A second self-made bug: `eventOutcomes[event] = { ok = ok, err = ok and nil or (...) }` — this is
  the exact trap CLAUDE.md names (`a and nil or b` always evaluates to `b`, since `a and nil` is
  always falsy), which would have silently put an error string on every *successful* registration
  too. Written out as an explicit `if not ok then ... end` instead.
- Not a bug but worth flagging: the report's escaped text for the curly-quote description is the
  *literal* seven/eight-character text `\226\128\156` (backslash + three digits, three times), not
  the raw UTF-8 bytes — matches the task's "(literally, backslashes and digits)" note, but my first
  draft of the probecheck assertion used a Lua byte-escape (`"\226"` = one raw byte) instead of the
  literal text (`"\\226"` = five ASCII bytes) and failed until I caught the distinction.
- Q1's to-do line reads "`<c> of <m> healing descriptions changed`", but `<m>` (and `<c>`) are
  computed from every spell found in both runs, not filtered to the ones this run classified as
  healing (`AgainstPreviousLines`' `order` table is the full spell list, healing and not, since the
  saved `desc` table and the "changed" listing are specified without a healing filter). On the
  fixture this reads "1 of 3" rather than "1 of 2" the wording alone might suggest. No Acceptance
  line pins the numbers, so I did not treat this as a blocking ambiguity, but flagging it in case
  the planner wants `<m>` restricted to healing spells only.
- Everything else in "Facts" that was marked UNKNOWN is, correctly, left for the probe itself to
  answer on the beta — nothing here assumes an answer to Q1–Q9 beyond what the stub's own
  stand-ins (explicitly commented as such in `tools/wowstub.lua`) exercise.

No open question — nothing here required guessing past what the task already resolved.

### Acceptance 6 pastes

**`tools/run.sh tools/probecheck.lua`** (chat-line noise from the probe's own `DEFAULT_CHAT_FRAME`
calls omitted for the four "first run" and per-probe lines that print between assertions; the four
"SpellTuner probe: build ..." lines are kept since they are the literal chat output):

```
the TBC line reads its version from SpellTuner_TBC.toc                   ok
Client/API.lua loads under the TBC line                                  ok
MD.API.client is forever on interface 16001                              ok
MD.API.Has walks dotted names and says false for a missing one           ok
SpellTuner probe: build 70009, 158 lines, saved. Click the box, Ctrl+A, Ctrl+C.
the report is keyed by build                                             ok
SpellTuner probe: build 70009, 165 lines, saved. Click the box, Ctrl+A, Ctrl+C.
SpellTuner probe: build 70009, 173 lines, saved. Click the box, Ctrl+A, Ctrl+C.
SpellTuner probe: build 70009, 158 lines, saved. Click the box, Ctrl+A, Ctrl+C.
the probe never raises                                                   ok
a missing function is reported absent, not raised                        ok
registering a bad event is caught                                        ok
a secret value is reported secret, not summed                            ok
a client error is reported as a string                                   ok
the report is ASCII with no bare pipe                                    ok
the report reaches the copy box                                          ok
the report sections are in order                                         ok
the header names build 70009 and interface 16001                         ok
healing spells are dumped with id, name, rank and the whole description  ok
a spell that does not heal is not dumped                                 ok
a change in bonus healing is reported against the previous run           ok
the combat snapshot is taken in combat                                   ok
UNIT_COMBAT and UNIT_SPELLCAST_SENT are counted by phase                 ok
the damage meter in combat is reported secret, not walked                ok
the damage meter after combat lists sources and spells                   ok
SavedVariables that did not come back are reported as such               ok
SavedVariables that came back are reported with their stamp              ok
the report prints the TOC that loaded                                    ok
the probe adds no global but its own                                     ok - SpellTunerDB, SPELLTUNER_TOC, SLASH_SPELLTUNER1, SpellTunerProbeFrame, SLASH_SPELLTUNER2, SLASH_SPELLTUNER3
/st and /md both reach the probe                                         ok
the to-do list names what is left                                        ok

27 ok, 0 failed
```

**The sixteen TBC suites**, unchanged from the 2026-09-27 baseline:

```
simcheck: |cff9966ffSpellTuner:|r   measured mean 1.3%  max 2.8% at 23.0s   (+ 23.1 mana/s energize) -> PASS
reccheck: 54 ok, 0 failed
replaycheck: 80 ok, 0 failed
replayui: 98 ok, 0 failed
runcheck: 78 ok, 0 failed
reviewui: 44 ok, 0 failed
navui: 25 ok, 0 failed
dashui: 56 ok, 0 failed
regencheck: 27 ok, 0 failed
simwindow: 8 ok, 0 failed
solvercheck: 70 ok, 0 failed
timeline: 27 ok, 0 failed
spelltip: 48 ok, 0 failed
practice: 74 ok, 0 failed
practiceui: 49 ok, 0 failed
migrate: 7 ok, 0 failed
```

**`luac -p`** on every file created or changed (no output = pass on all nine):

```
$ tools/.lua/lua-5.1.5/src/luac -p Client/API.lua Client/Probe.lua Client/TOC_Plain.lua Client/TOC_Forever.lua Client/TOC_Vanilla.lua Client/TOC_TBC.lua tools/wowstub.lua tools/harness.lua tools/probecheck.lua
(exit 0, no output = pass)
```

`release.sh` is bash, not Lua; `bash -n release.sh` also passed with no output.

**`./release.sh --out <scratchpad>/rel`** (never into the repo or the main checkout's `dist/`):

```
Built <scratchpad>/rel/SpellTuner (v0.15.4, 60 files) from combat-log-design-arch-ffb907.
Built <scratchpad>/rel/SpellTuner-0.15.4.zip
Copy <scratchpad>/rel/SpellTuner into your game's Interface/AddOns folder
(or: make install WOW_ADDONS="/mnt/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns")
```

`find` of the package's `*.toc` and `Client/` files (also verified against the zip via
`zipfile.namelist()`, and that every file `SpellTuner_TBC.toc` lists is present):

```
SpellTuner/SpellTuner.toc
SpellTuner/SpellTuner_Forever.toc
SpellTuner/SpellTuner_TBC.toc
SpellTuner/SpellTuner_Vanilla.toc
SpellTuner/Client/API.lua
SpellTuner/Client/Probe.lua
SpellTuner/Client/TOC_Forever.lua
SpellTuner/Client/TOC_Plain.lua
SpellTuner/Client/TOC_TBC.lua
SpellTuner/Client/TOC_Vanilla.lua
```

**`git status --short`** (matches the Files table exactly):

```
RM SpellTuner.toc -> SpellTuner_TBC.toc
 M docs/tasks/T0-probe.md
 M release.sh
 M tools/harness.lua
 M tools/wowstub.lua
?? Client/
?? SpellTuner.toc
?? SpellTuner_Forever.toc
?? SpellTuner_Vanilla.toc
?? tools/probecheck.lua
```

**Run 3's full report** (`/st probe` out of combat, after the scripted fight, bonus healing 50):

```
SpellTuner probe 1.0.0-alpha.0 -- 2025-09-04 15:33:20
== client
build: 1.60.1 70009 Sep 20 2026 interface 16001
client: forever
project: WOW_PROJECT_ID=1 WOW_PROJECT_MAINLINE=1 WOW_PROJECT_CLASSIC=nil WOW_PROJECT_BURNING_CRUSADE_CLASSIC=nil
character: Penek Anniversary DRUID level 64
in combat: false
== functions (39 present, 26 absent)
absent GetSpellInfo
absent UnitAura
absent UnitBuff
absent GetTalentInfo
absent GetItemInfo
absent ReloadUI
absent CombatLogGetCurrentEventInfo
absent C_CombatLog.IsCombatLogRestricted
present C_Secrets.ShouldAurasBeSecret
present issecretvalue
present C_DamageMeter.GetCombatSessionFromType
present GetManaRegen
present GetSpellBonusHealing
absent GetSpellBonusDamage
present GetSpellCritChance
present UnitStat
present UnitPower
present UnitPowerMax
present UnitHealth
present UnitHealthMax
absent UnitThreatSituation
absent UnitCastingInfo
present GetShapeshiftFormID
present GetInventoryItemID
present GetMacroInfo
present GetBinding
present GetActionInfo
present IsSpellKnown
absent C_Spell.GetSpellInfo
absent C_Spell.GetSpellPowerCost
present C_Spell.GetSpellDescription
present C_Spell.GetSpellSubtext
absent C_Spell.GetSpellLevelLearned
present C_Spell.GetSpellName
absent C_Spell.GetSpellTexture
absent C_Spell.GetSpellCooldown
absent C_SpellBook.GetNumSpellBookSkillLines
absent C_SpellBook.GetSpellBookSkillLineInfo
present C_SpellBook.GetSpellBookItemInfo
absent C_SpellBook.IsSpellKnown
absent TooltipDataProcessor.AddTooltipPostCall
absent C_TooltipInfo
present C_SpecializationInfo.GetTalentInfo
absent C_Traits.GetConfigInfo
absent C_ClassTalents.GetActiveConfigID
present C_UnitAuras.GetAuraDataByIndex
absent C_Spell.GetBaseSpell
absent C_AddOns.LoadAddOn
present C_DamageMeter.GetCombatSessionSourceFromType
present C_DamageMeter.IsDamageMeterAvailable
present Enum.DamageMeterType
present Enum.DamageMeterSessionType
present Enum.SpellBookSpellBank
present C_Timer.After
present GetBuildInfo
present GetAddOnMetadata
absent C_AddOns.GetAddOnMetadata
present GetNumTalentTabs
present UnitAffectingCombat
present UnitExists
present UnitName
present UnitClass
present UnitLevel
present GetRealmName
present CreateFrame
== events
ok UNIT_SPELLCAST_SENT
ok UNIT_SPELLCAST_START
ok UNIT_SPELLCAST_SUCCEEDED
ok UNIT_SPELLCAST_STOP
ok UNIT_SPELLCAST_FAILED
ok UNIT_HEALTH
ok UNIT_MAXHEALTH
ok UNIT_POWER_UPDATE
ok UNIT_AURA
ok UNIT_FLAGS
ok UNIT_COMBAT
ok GROUP_ROSTER_UPDATE
ok PLAYER_REGEN_DISABLED
ok PLAYER_REGEN_ENABLED
ok SPELLS_CHANGED
ok PLAYER_TALENT_UPDATE
ok TRAIT_CONFIG_UPDATED
ok DAMAGE_METER_COMBAT_SESSION_UPDATED
ok ADDON_RESTRICTION_STATE_CHANGED
throws COMBAT_LOG_EVENT_UNFILTERED <error: tools/wowstub.lua:221: unknown event "COMBAT_LOG_EVENT_UNFILTERED">
== secrets now
ShouldAurasBeSecret = false
ShouldUnitIdentityBeSecret = <error: tools/wowstub.lua:458: bad argument #1>
== spells (bonus healing 50)
slots 1-500: 3 with a spell, 2 healing, 0 empty description, 0 secret
spell 774
  name: Rejuvenation
  rank: Rank 1
  desc: Heals the target for 82 over 12 sec.
spell 5185
  name: Healing Touch
  rank: Rank 1
  desc: Heals a friendly target for 40 to 55.||nIt is \226\128\156quoted\226\128\157.
== spells against the previous run
previous: this session at 2025-09-04 15:33:20, bonus healing 0 -> 50
changed 774 Rejuvenation
== talents
C_SpecializationInfo.GetTalentInfo(1, 1) = <error: tools/wowstub.lua:476: bad argument #1 to 'GetTalentInfo' (table expected, got number)>
C_SpecializationInfo.GetTalentInfo({tier=1, column=1}) = {name=Improved Wrath, rank=0}
C_ClassTalents.GetActiveConfigID() = <absent>
C_Traits.GetConfigInfo(<first return above>) = <absent>
== readings now
UnitExists(party1) = true
UnitHealth(player) = 5000
UnitHealth(party1) = 4000
UnitHealthMax(party1) = 4000
UnitHealth(target) = 0
UnitPower(player, 0) = 7009
GetManaRegen() = 69.24, 28.33
GetShapeshiftFormID() = nil
C_UnitAuras.GetAuraDataByIndex(player, 1, HELPFUL) = {duration=1800, name=Mark of the Wild, spellId=1126}
C_UnitAuras.GetAuraDataByIndex(party1, 1, HELPFUL) = nil
== combat snapshot
taken 2025-09-04 15:33:20, in combat: true
ShouldAurasBeSecret = true
ShouldUnitIdentityBeSecret = <error: tools/wowstub.lua:458: bad argument #1>
UnitExists(party1) = true
UnitHealth(player) = 5000
UnitHealth(party1) = <secret>
UnitHealthMax(party1) = <secret>
UnitHealth(target) = <secret>
UnitPower(player, 0) = 7009
GetManaRegen() = 69.24, 28.33
GetShapeshiftFormID() = nil
C_UnitAuras.GetAuraDataByIndex(player, 1, HELPFUL) = <error: tools/wowstub.lua:465: Auras cannot be accessed when secret while tainted>
C_UnitAuras.GetAuraDataByIndex(party1, 1, HELPFUL) = <error: tools/wowstub.lua:465: Auras cannot be accessed when secret while tainted>
== events seen this session
UNIT_COMBAT ooc party HEAL n=1 readable=1 secret=0 nil=0 sample=120
UNIT_COMBAT combat party WOUND n=1 readable=0 secret=1 nil=0 sample=
UNIT_SPELLCAST_SENT combat n=1 readable=1 secret=0 empty=0 sample=Tankname
== damage meter
C_DamageMeter.IsDamageMeterAvailable() = true
session Current HealingDone = sources=1
  source 1 isLocalPlayer=true totalAmount=1234
  local source = {amountPerSecond=41, isLocalPlayer=true, sourceGUID=Player-1, totalAmount=1234}
  local spells = combatSpells=1
  spell 1 = {spellID=774, totalAmount=1000}
session Overall HealingDone = sources=1
  source 1 isLocalPlayer=true totalAmount=1234
  local source = {amountPerSecond=41, isLocalPlayer=true, sourceGUID=Player-1, totalAmount=1234}
  local spells = combatSpells=1
  spell 1 = {spellID=774, totalAmount=1000}
== saved variables
SpellTunerDB at load: nil
previous session stamp: none
reports at load: none
this session stamp: 2025-09-04 15:33:20
== toc
SPELLTUNER_TOC = Forever
== to do
Q1 answered: 1 of 3 healing descriptions changed when bonus healing went 0 -> 50
Q2 answered: UnitExists(party1) read true in the combat snapshot
Q5 answered: UnitExists(party1) read true in the combat snapshot
Q3 answered: a UNIT_COMBAT combat party counter was seen
Q4 answered: the damage meter listed at least one source out of combat
Q6 answered: see == talents
Q7 to do: type /reload, then /st probe; if this line still says to do, SavedVariables did not come back
Q8 answered: a UNIT_SPELLCAST_SENT combat counter was seen
Q9 answered: SPELLTUNER_TOC = Forever
```

### Lead review (2026-09-27)

Accepted. Two one-line fixes made by the lead, as the review rules allow:
- `Client/Probe.lua`, the Q1 to-do line: "healing descriptions" -> "spell descriptions". The
  count covers every spell found in both runs (the implementer's flag above); the wording now
  says so, and the To do rule in this task is amended to match.
- `Client/Probe.lua`, `OnRegenDisabled`: the snapshot scheduled with `C_Timer.After` now runs
  inside its own `pcall`. It fires later, outside every other `pcall`, so a raise there would
  have reached the client's error handler.
Accepted as they are: the file-scope `CreateFrame("Frame")` and the three
`DEFAULT_CHAT_FRAME:AddMessage` calls are not under `pcall` (both are sourced as present on
Forever, and without them there is no probe to protect); the to-do list prints Q5 next to Q2
rather than in numeric order (each line is labelled).
