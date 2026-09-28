#!/usr/bin/env bash
# Build a ready-to-copy release of SpellTuner from the main checkout or any
# git worktree, into the TOP-LEVEL dist/ grouped by source:
#
#   dist/<name>/SpellTuner/                 <name> = "main" or the worktree folder
#   dist/<name>/SpellTuner_Recorder/        the three LoadOnDemand siblings (T2),
#   dist/<name>/SpellTuner_Replay/          each only if Modules/<Name>/ exists
#   dist/<name>/SpellTuner_Practice/        in the source
#   dist/<name>/SpellTuner-<version>.zip    holds SpellTuner/ plus every sibling
#
#   ./release.sh                     build the checkout this script lives in
#   ./release.sh --menu              pick the source interactively (make release)
#   ./release.sh --src NAME|DIR      build a named worktree ("main", "feedback-round-3")
#                                    or any directory containing SpellTuner_TBC.toc or
#                                    SpellTuner.toc
#   ./release.sh --list              show the available sources
#   ./release.sh --out DIR           override the output folder
#   ./release.sh --install DIR       also copy SpellTuner/ (and every sibling) into
#                                    that AddOns folder
#   ./release.sh /path/to/AddOns     same (legacy positional form); WOW_ADDONS env too
#
# The file list is the union (no duplicates) of every SpellTuner*.toc's load
# entries in the source root, plus the .toc files themselves and README.md, so
# the release can never drift from what any of the game's clients actually
# loads (T0: one tree, one .toc per client). The version -- zip name, --list,
# the menu -- comes from SpellTuner_TBC.toc when the source has one, else from
# SpellTuner.toc. Dev files (docs/, CLAUDE.md, Makefile, .git, this script) are
# excluded by construction. Each Modules/<Name>/ folder with at least one
# <Name>*.toc becomes its own top-level package the same way, built from ITS
# OWN TOCs' file lists (T2, docs/ROADMAP-FOREVER.md §1.1) -- a checkout with no
# Modules/ builds exactly as before.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repo root = the main checkout, even when run from inside a worktree.
if COMMON="$(git -C "$HERE" rev-parse --git-common-dir 2>/dev/null)"; then
    [[ "$COMMON" = /* ]] || COMMON="$HERE/$COMMON"
    ROOT="$(cd "$COMMON/.." && pwd)"
else
    ROOT="$HERE"
fi

# name<TAB>path<TAB>branch, main checkout first.
list_sources() {
    if git -C "$ROOT" worktree list --porcelain >/dev/null 2>&1; then
        local path="" branch=""
        while IFS= read -r line; do
            case "$line" in
                "worktree "*) path="${line#worktree }" ;;
                "branch "*)   branch="${line#branch refs/heads/}" ;;
                "")
                    if [[ -n "$path" ]]; then
                        local name="$(basename "$path")"
                        [[ "$path" == "$ROOT" ]] && name="main"
                        printf '%s\t%s\t%s\n' "$name" "$path" "${branch:-detached}"
                    fi
                    path="" branch=""
                    ;;
            esac
        done < <(git -C "$ROOT" worktree list --porcelain; echo)
    else
        printf 'main\t%s\t-\n' "$ROOT"
    fi
}

resolve_source() {
    local want="$1"
    if [[ -d "$want" && ( -f "$want/SpellTuner_TBC.toc" || -f "$want/SpellTuner.toc" ) ]]; then
        cd "$want" && pwd
        return
    fi
    while IFS=$'\t' read -r name path _; do
        if [[ "$name" == "$want" ]]; then echo "$path"; return; fi
    done < <(list_sources)
    echo "ERROR: unknown source '$want' (try --list)" >&2
    exit 1
}

# The version toc: SpellTuner_TBC.toc when the source has one, else the plain
# SpellTuner.toc (a Forever-only checkout).
version_toc() {
    if [[ -f "$1/SpellTuner_TBC.toc" ]]; then echo "$1/SpellTuner_TBC.toc"; else echo "$1/SpellTuner.toc"; fi
}

version_of() {
    sed -n 's/^## Version:[[:space:]]*//p' "$(version_toc "$1")" 2>/dev/null | tr -d '\r'
}

show_sources() {
    local i=0
    while IFS=$'\t' read -r name path branch; do
        i=$((i + 1))
        printf '  %d) %-22s v%-7s %s  (%s)\n' "$i" "$name" "$(version_of "$path")" "$branch" "$path"
    done < <(list_sources)
}

menu() {
    echo "Build a release from:" >&2
    show_sources >&2
    local choice
    read -rp "Choice [1]: " choice
    choice="${choice:-1}"
    local i=0
    while IFS=$'\t' read -r name path _; do
        i=$((i + 1))
        if [[ "$choice" == "$i" || "$choice" == "$name" ]]; then echo "$path"; return; fi
    done < <(list_sources)
    resolve_source "$choice"
}

SRC="" OUT="" TARGET="${WOW_ADDONS:-}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --src)      SRC="$2"; shift 2 ;;
        --out)      OUT="$2"; shift 2 ;;
        --install)  TARGET="$2"; shift 2 ;;
        --menu)     SRC="$(menu)"; shift ;;
        --list)     show_sources; exit 0 ;;
        -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
        *)          TARGET="$1"; shift ;;
    esac
done

if [[ -z "$SRC" ]]; then
    SRC="$HERE"
else
    SRC="$(resolve_source "$SRC")"
fi
shopt -s nullglob
TOCS=("$SRC"/SpellTuner*.toc)
shopt -u nullglob
[[ ${#TOCS[@]} -gt 0 ]] || { echo "ERROR: no SpellTuner_TBC.toc or SpellTuner.toc found in $SRC" >&2; exit 1; }

NAME="$(basename "$SRC")"
[[ "$SRC" == "$ROOT" ]] && NAME="main"
[[ -n "$OUT" ]] || OUT="$ROOT/dist/$NAME"
PKG="$OUT/SpellTuner"

VERSION="$(version_of "$SRC")"
[[ -n "$VERSION" ]] || { echo "ERROR: no '## Version:' line in $(basename "$(version_toc "$SRC")")" >&2; exit 1; }

# Collect files: every SpellTuner*.toc in the source root, README.md, and the
# union (no duplicates) of every one of those .toc's load entries -- so a file
# common to two clients (Client/API.lua) is packaged once.
files=("README.md")
for f in "${TOCS[@]}"; do files+=("$(basename "$f")"); done
have() { local x; for x in "${files[@]}"; do [[ "$x" == "$1" ]] && return 0; done; return 1; }
for toc in "${TOCS[@]}"; do
    while IFS= read -r line; do
        line="${line%$'\r'}"                      # strip CR (the .toc may be CRLF)
        [[ -z "$line" || "$line" == \#* ]] && continue
        entry="${line//\\//}"                     # .toc uses backslashes; use / on disk
        have "$entry" || files+=("$entry")
    done < "$toc"
done

# Verify everything exists before touching the output.
missing=0
for f in "${files[@]}"; do
    if [[ ! -f "$SRC/$f" ]]; then
        echo "ERROR: $f is listed in the .toc but missing on disk" >&2
        missing=1
    fi
done
[[ $missing -eq 0 ]] || exit 1

rm -rf "$PKG"
mkdir -p "$PKG"
for f in "${files[@]}"; do
    mkdir -p "$PKG/$(dirname "$f")"
    cp "$SRC/$f" "$PKG/$f"
done

REL="${OUT#$ROOT/}"

# The sibling modules (T2): every Modules/<Name>/ with at least one
# <Name>*.toc, built the same way as SpellTuner/ above but from its OWN TOCs'
# file lists -- no README.md, no version-line requirement (a module's own
# "## Version:" is cosmetic; the core's is what matters).
MODULE_NAMES=()
if [[ -d "$SRC/Modules" ]]; then
    for d in "$SRC"/Modules/*/; do
        [[ -d "$d" ]] || continue
        mname="$(basename "$d")"
        shopt -s nullglob
        mtocs=("$d"/"$mname"*.toc)
        shopt -u nullglob
        [[ ${#mtocs[@]} -gt 0 ]] || continue
        MODULE_NAMES+=("$mname")

        mdir="${d%/}"
        mpkg="$OUT/$mname"
        mfiles=()
        for f in "${mtocs[@]}"; do mfiles+=("$(basename "$f")"); done
        mhave() { local x; for x in "${mfiles[@]}"; do [[ "$x" == "$1" ]] && return 0; done; return 1; }
        for toc in "${mtocs[@]}"; do
            while IFS= read -r line; do
                line="${line%$'\r'}"
                [[ -z "$line" || "$line" == \#* ]] && continue
                entry="${line//\\//}"
                mhave "$entry" || mfiles+=("$entry")
            done < "$toc"
        done

        # T13c: an entry not under the module's own folder is a shared file
        # (Engine/SimModel.lua etc.) that the client never loads across addon
        # folders -- so it is resolved at the repository root, under the same
        # four shared folders the stub and apicheck.py accept, and copied to
        # the SAME relative path inside the package. Anything else missing is
        # still the existing error.
        mmissing=0
        msrc=()
        for f in "${mfiles[@]}"; do
            if [[ -f "$mdir/$f" ]]; then
                msrc+=("$mdir/$f")
            elif [[ "$f" == Engine/* || "$f" == Spells/* || "$f" == Data/* || "$f" == UI/* ]] && [[ -f "$SRC/$f" ]]; then
                msrc+=("$SRC/$f")
            else
                echo "ERROR: Modules/$mname/$f is listed in the .toc but missing on disk" >&2
                mmissing=1
                msrc+=("")
            fi
        done
        [[ $mmissing -eq 0 ]] || exit 1

        rm -rf "$mpkg"
        mkdir -p "$mpkg"
        for i in "${!mfiles[@]}"; do
            f="${mfiles[$i]}"
            mkdir -p "$mpkg/$(dirname "$f")"
            cp "${msrc[$i]}" "$mpkg/$f"
        done
    done
fi

if [[ ${#MODULE_NAMES[@]} -gt 0 ]]; then
    echo "Built $REL/SpellTuner (v$VERSION, ${#files[@]} files) from $NAME," \
        "plus ${#MODULE_NAMES[@]} module(s): ${MODULE_NAMES[*]}."
else
    echo "Built $REL/SpellTuner (v$VERSION, ${#files[@]} files) from $NAME."
fi

# Zip (zip if available, python3 zipfile as fallback) -- SpellTuner/ plus every
# module folder, so the archive is the same four (or one) top-level folders
# the game's AddOn list would show.
ZIP="$OUT/SpellTuner-$VERSION.zip"
rm -f "$ZIP"
if command -v zip >/dev/null 2>&1; then
    (cd "$OUT" && zip -qr "$(basename "$ZIP")" SpellTuner "${MODULE_NAMES[@]}")
    echo "Built $REL/SpellTuner-$VERSION.zip"
elif command -v python3 >/dev/null 2>&1; then
    python3 - "$OUT" "$ZIP" "$REL" "${MODULE_NAMES[@]}" <<'PYEOF'
import os, sys, zipfile
out_dir, out, rel = sys.argv[1], sys.argv[2], sys.argv[3]
folders = ["SpellTuner"] + sys.argv[4:]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for folder in folders:
        for base, _, names in os.walk(os.path.join(out_dir, folder)):
            for name in names:
                path = os.path.join(base, name)
                z.write(path, os.path.relpath(path, out_dir))
print("Built " + rel + "/" + os.path.basename(out))
PYEOF
else
    echo "NOTE: neither zip nor python3 found — skipped the zip archive."
fi

# Optional: copy into the game's AddOns folder -- SpellTuner/ and every
# sibling module folder beside it.
if [[ -n "$TARGET" ]]; then
    [[ -d "$TARGET" ]] || { echo "ERROR: AddOns folder not found: $TARGET" >&2; exit 1; }
    rm -rf "$TARGET/SpellTuner"
    cp -r "$PKG" "$TARGET/SpellTuner"
    for mname in "${MODULE_NAMES[@]}"; do
        rm -rf "$TARGET/$mname"
        cp -r "$OUT/$mname" "$TARGET/$mname"
    done
    echo "Installed into $TARGET/SpellTuner"
else
    echo "Copy $REL/SpellTuner into your game's Interface/AddOns folder"
    echo "(or: make install WOW_ADDONS=\"/mnt/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns\")"
fi
