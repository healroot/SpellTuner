# T-publish -- `./release.sh --publish`: the two zips to CurseForge

Status: **built** 2026-10-02 on branch `next/publish`, base `6fab263` (0.16.7). Waiting for the
integrator. No addon file changes: `release.sh`, a new committed config and `tools/releasecheck.lua`
only. Nothing was ever sent to CurseForge; the suite runs a fake curl.

## What the author runs

    # see what would be sent (no network at all; says only whether the token is present)
    ~/.local/bin/secret-env run CURSEFORGE_API_TOKEN -- ./release.sh --publish --dry-run

    # upload both zips
    ~/.local/bin/secret-env run CURSEFORGE_API_TOKEN -- ./release.sh --publish

    # only one (Forever not listed on CurseForge yet), or another release type
    ~/.local/bin/secret-env run CURSEFORGE_API_TOKEN -- ./release.sh --publish --only tbc
    ~/.local/bin/secret-env run CURSEFORGE_API_TOKEN -- ./release.sh --publish --release-type alpha

Before the first upload: fill in `project_id` in `tools/data/curseforge.txt` and confirm the two
game version names against `GET https://wow.curseforge.com/api/game/versions`, then commit the
file (a publish refuses an uncommitted tree).

## The config: `tools/data/curseforge.txt` (committed, not secret)

    project_id =                     # empty: --publish refuses before building, naming this file
    tbc_game_versions = 2.5.6        # comma-separated game version NAMES
    forever_game_versions = 1.60.1
    release_type = beta              # alpha | beta | release; --release-type overrides

The placeholders come from the TOCs: interface 20506 is 2.5.6, Forever's 16001 is 1.60.1 (the
client's own 1.60.1 builds, `docs/probe/1.60.1_70124.md`). **To be confirmed** against the
versions endpoint. A name CurseForge lists under two version types is refused with both ids;
`name@<gameVersionTypeID>` picks one.

## What `--publish` does, in order

1. **Options.** `--publish [--release-type alpha|beta|release] [--dry-run] [--only tbc|forever]`.
   `--dry-run`, `--only` and `--release-type` without `--publish` are refused; `--publish` with
   `--flavour`, an install, `--set-version` or `--version` is refused (`$WOW_ADDONS` is not read
   for a publish: it installs nothing).
2. **Everything `release.sh` already checks** (the TOCs' flavours, the one version, every file on
   disk) runs as before.
3. **Before building** (nothing written to the output, nothing sent): the config exists,
   `project_id` is a number, the release type is valid, each flavour to publish has its game
   version names; python3 is there; unless `--dry-run`, the token is set (no whitespace, quote
   or backslash) and curl is there; the source is a git checkout with **no uncommitted or
   untracked change** (`git status --porcelain`, listed), and **HEAD's** copy of every TOC is at
   the version; no flavour to publish is already in `dist/<name>/published.txt` at this version.
   The changelog is taken (integrator's change): `CHANGELOG.md`'s `## <version>` section, written for
   players (refused when absent; `docs/HISTORY.md` is the developers' log and never published),
   cut at a line under 4000 characters with `(trimmed)` when longer.
4. **The build**, both packages, exactly as today.
5. **`--dry-run`** prints, per flavour, the URL, the zip and its size, the game version names and
   the metadata JSON (pretty, the names where the ids will go), and `token: present` / `absent`.
   It contacts nothing and records nothing.
6. **The names to ids**: one `GET https://wow.curseforge.com/api/game/versions`; every name of
   every flavour to publish must resolve to exactly one id. A name that does not is refused by
   name, with the flavour; when the other flavour resolves the refusal says
   `./release.sh --publish --only <it>`; **nothing is uploaded**.
7. **The uploads**: `POST https://wow.curseforge.com/api/projects/<id>/upload-file`, multipart
   `metadata` (compact JSON: `changelog`, `changelogType: "markdown"`,
   `displayName: "SpellTuner <version> (TBC)"` / `"(Forever)"`, `gameVersions` the ids,
   `releaseType`) and `file` (the zip, from `dist/<name>/`, under its own name). On `{id}` the
   upload is appended to `dist/<name>/published.txt` (`version TAB flavour TAB file id TAB UTC
   time TAB project id`) and `Published SpellTuner <v> (<Label>) to CurseForge project <p>: file
   id <id>` printed. A failure names the HTTP status and the start of CurseForge's answer, and
   which flavour was already uploaded and recorded.

`dist/` is ignored, so the record is per checkout and `make clean` forgets it; CurseForge itself
would accept a duplicate.

## The token

- Read only from `CURSEFORGE_API_TOKEN`. At the top of the script, when it is set, xtrace is
  turned off (`{ set +x; } 2>/dev/null`) before it is read; it is copied into a shell variable
  and **unset from the environment**, so no child (git, python3, zip, curl) inherits it.
- It reaches curl only as a config on stdin, `printf 'header = "X-Api-Token: %s"\n' | curl -K -`
  (`printf` is a builtin: no command line holds it). Never `-v`.
- Nothing prints it: a dry run says `present` / `absent`; an error body is cut to 300 characters
  and any copy of the token in it replaced with `<token>`.
- The base URL is fixed in the script (no override that could send the token elsewhere).

## Tests (`tools/releasecheck.lua`, 21 -> 36)

A scratch git repository of the tree (`tools/.lua/releasecheck/scratch tree/publish tree`, the
TOCs put back to the tree's, a newest HISTORY entry with a quote, a backslash and an em dash),
`fakebin/curl` first on PATH: it records argv, stdin (when `-K -`), cwd, the metadata file's
content and whether the file part exists, honours `-o` / `-w`, and answers canned versions JSON
or `{"id": 4240 + n}`. The token is a made-up string. On `6fab263` (the failing commit
`810835f`): 22 ok, 14 failed. The fifteen:

1. the scratch repository is committed and clean (scaffold);
2. the **committed** `tools/data/curseforge.txt` has an empty `project_id` and refuses before
   building, naming the file -- no output folder, no curl call;
3. no `CURSEFORGE_API_TOKEN`: refused before building, nothing sent;
4. an untracked file: refused, named;
5. `--dry-run`: both zips built, curl never run, nothing recorded;
6. `--dry-run` prints both display names, the release type, the changelog, the URL and
   `token: present`, never the token;
7. an unknown name (`9.9.9-nope` among Forever's): refused by name and flavour, one call (the
   versions GET), no upload, no record;
8. the same refusal offers `--only tbc`;
9. `--only tbc --release-type alpha` under `bash -x`: the versions GET then one upload of the TBC
   zip (the unresolvable Forever config not read);
10. `2.5.6` resolves to its id (an int);
11. the metadata JSON: exactly the five keys, display name, markdown, `alpha`, the changelog equal
    to the newest HISTORY entry byte for byte (escaping included);
12. the token in no argv (nor cwd), in every call's stdin as the header line, and in nothing
    printed -- under `bash -x`;
13. the file id printed and recorded in `dist/main/published.txt`;
14. a second `--only tbc` at the same version refused (`already published`), nothing sent, the
    record unchanged;
15. `--only forever`: the Forever zip, its id, `(Forever)`, the config's `beta`, both flavours
    recorded.

`make check` green (with `tools/.cache/talentsforever.json` present for profilecheck's counted
names), apicheck 0 findings, textcheck 0 findings.

## Integrator lines

- `tools/data/expected-counts.json`: `"releasecheck": 38` (was 21; 36 as built, +1 for the integrator's CHANGELOG.md refusal, +1 for the committed project id).
- `CLAUDE.md`, the `release.sh` / `Makefile` row, append: **T-publish:** `--publish
  [--release-type alpha|beta|release] [--dry-run] [--only tbc|forever]` uploads the zips to the
  CurseForge project in `tools/data/curseforge.txt` (committed, not secret: `project_id`, each
  flavour's game version names, `release_type`) as `SpellTuner <v> (TBC)` / `(Forever)`, the
  changelog the newest `docs/HISTORY.md` entry; the token only from `CURSEFORGE_API_TOKEN`
  (`secret-env run CURSEFORGE_API_TOKEN -- ./release.sh --publish`), xtrace off, unset from the
  environment, handed to curl on stdin; refused before building: an empty `project_id`, no token
  (but `--dry-run`), a dirty tree or a HEAD whose TOCs are not at the version, a flavour already
  in `dist/<name>/published.txt`; refused before any upload: a game version name CurseForge does
  not list; `--dry-run` contacts nothing. Held by `tools/releasecheck.lua` against a fake curl.
- `CLAUDE.md`, the `tools/` row's releasecheck mention, or `docs/TOOLS.md` section 1, the
  `releasecheck.lua` row, append: Since **T-publish** (36): `--publish` on a scratch git
  repository with a fake curl on PATH -- the committed empty `project_id` and a missing token
  refused before building, a dirty tree refused, `--dry-run` sending nothing, names to ids, an
  unknown name refused before any upload (with `--only` offered), the metadata JSON, the token in
  no argv and nothing printed under `bash -x`, `published.txt` and a second upload refused,
  `--only tbc` / `--only forever`.
- `docs/TOOLS.md`, a line where `release.sh` is described (or the Makefile header): the two
  publish commands above.
- `docs/HISTORY.md`: an entry when integrated -- and note the next publish takes its changelog
  from whatever entry is newest then.
- No TOC line, setting, slash verb or client global changed.

## Not done

- No `make publish` target (the Makefile's `release` runs the check first; a publish is the
  author's explicit act with the token wrapper around it).
- Never run against CurseForge: the endpoint's real answers (the versions list's shape, the
  upload's `{id}`, error bodies) are as the API page describes them, untested.
