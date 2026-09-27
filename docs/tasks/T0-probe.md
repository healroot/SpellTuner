# T0 — the capability probe

Status: **draft by the planner, for the lead to finalise.** Phase 0 of `docs/FOREVER-PLAN.md`.
Everything else in the port waits on this report, so it is small, defensive, and it is the
first thing that runs on the beta.

## Goal

A `ManaDemon` addon folder that loads on interface 16001 without a single Lua error, contains
only `Core.lua`, `Client/API.lua` (stub: presence checks) and `Client/Probe.lua`, and answers
`/md probe` with a report that (a) prints to a copyable box, (b) is written to SavedVariables
keyed by build number, and (c) answers the eight questions in `docs/FOREVER-PLAN.md` §6 as far
as they can be answered without the author's participation, and tells the author exactly what to
do for the rest (equip a +healing item and run `/md probe again`; pull a mob and run it in
combat). It is the debug tool for a moving beta, so it is built to survive the beta's own bugs:
every check under `pcall`, every result a string, no arithmetic on anything the client returned.

## Facts

- Interface `16001`; `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` — kit README, EllesmereUI_ClientGate.lua (plan §1.1).
- Registering an unknown event throws — kit README. Every `RegisterEvent` under `pcall`.
- Error reporting stops after 100 errors per session — kit BUG_REPORTS. The probe must never
  raise; it records `"<error: ...>"` strings.
- SavedVariables may not be read back — kit BUG_REPORTS, EllesmereUI_ForeverNotice.lua. The
  probe reports whether its own previous report came back, which is question 7.
- `issecretvalue(v)` exists; arithmetic on a secret errors — wiki Secret values (plan §1.2).
- Function presence per the kit baseline (plan §1.3) — to be **confirmed**, not assumed: the
  probe checks each name and prints present/absent.
- `C_Secrets.Should*` predicates exist (28 of them, plan §1.3) — call each zero-argument one
  under pcall in and out of combat.
- Description dynamism (Q1) is UNKNOWN — the probe records the description text of every
  healing spell in the book now, and compares with the previous report if the author changed gear.

## Files

- `ManaDemon.toc` — `## Interface: 16001`, `## SavedVariables: ManaDemonDB`, three files.
- `Core.lua` — namespace, `ManaDemonDB` with the read-back guard, `/md`, the copy box.
- `Client/API.lua` — `MD.API.Has(name)` (dotted names, cached), `MD.API.client`, nothing else yet.
- `Client/Probe.lua` — the checks and the report.
- `tools/wowstub.lua` — a `forever` profile just large enough to load these three files and run the probe offline (no `CombatLogGetCurrentEventInfo`, `issecretvalue`, `C_Spell.GetSpellDescription`, `C_SpellBook` enumeration of three fake spells).
- `tools/probecheck.lua` — the probe under the stub: it produces a report, never raises, and marks a missing function as absent rather than crashing.

## Rules

`CLAUDE.md` conventions apply: no libraries; the copy box frame uses `"BackdropTemplate"`; every
rendered string ASCII and free of a bare `|`; `pcall` everything from the client; no arithmetic
on a client value in `Probe.lua` — it formats with `tostring` only.

## Acceptance

- `tools/run.sh tools/probecheck.lua` passes with at least these named assertions: "a missing
  function is reported absent, not raised"; "a secret value is reported secret, not summed";
  "registering a bad event is caught"; "the report is ASCII with no bare pipe"; "the report is
  keyed by build".
- `luac -p` clean on all files.
- The report has, in this order: build and interface; project id; for each of the ~40 functions
  in plan §1.3, present/absent; for each `C_Secrets.Should*` predicate, its value; the
  descriptions of every healing spell in the spellbook (name, rank text, description); the talent
  API that answers (`C_SpecializationInfo.GetTalentInfo(1,1)` vs `C_Traits.GetConfigInfo` of the
  active config); whether the previous report (same character, any build) came back from
  SavedVariables; and the instructions for the two author-driven checks (gear swap, in-combat run).

## Out of scope

Anything from the current addon. No tooltip, no dashboard, no recorder. No module registry yet.

## Report

(implementer writes here)
