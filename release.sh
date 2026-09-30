#!/usr/bin/env bash
# Build ready-to-copy releases of SpellTuner from the main checkout or any git
# worktree, into the TOP-LEVEL dist/ grouped by source. One tree, one version,
# TWO installations (T23; docs/DECISIONS.md "One version, two installations"):
#
#   dist/<name>/tbc/SpellTuner/               TBC: SpellTuner_TBC.toc and its files
#   dist/<name>/forever/SpellTuner/           Forever: the two Forever TOCs and theirs
#   dist/<name>/forever/SpellTuner_Recorder/  ... plus the three LoadOnDemand siblings
#   dist/<name>/forever/SpellTuner_Replay/    (each only if Modules/<Name>/ exists)
#   dist/<name>/forever/SpellTuner_Practice/
#   dist/<name>/SpellTuner-tbc-<version>.zip      holds SpellTuner/
#   dist/<name>/SpellTuner-forever-<version>.zip  holds SpellTuner/ and every sibling
#
#   ./release.sh                        build both flavours of the checkout this script is in
#   ./release.sh --flavour tbc|forever|both   build only one (an install builds what it installs)
#   ./release.sh --menu                 pick the source interactively (make release)
#   ./release.sh --src NAME|DIR         build a named worktree ("main", "feedback-round-3")
#                                       or any directory with a SpellTuner*.toc in it
#   ./release.sh --list                 show the available sources and their version
#   ./release.sh --out DIR              override the output folder
#   ./release.sh --version              print the tree's one version
#   ./release.sh --set-version X        rewrite the "## Version:" line of every TOC to X
#                                       (x.y.z or x.y.z-suffix) and build nothing
#   ./release.sh --install-tbc DIR      install the TBC package into that AddOns folder
#   ./release.sh --install-forever DIR  install the Forever package (and its siblings) there
#   ./release.sh --install DIR          same, the flavour detected from the path:
#                                       /_classic_beta_/ is forever, /_anniversary_/ is tbc,
#                                       anything else is refused
#   ./release.sh /path/to/AddOns        same as --install (legacy positional form); so does
#                                       $WOW_ADDONS when no install option is given
#
# An install puts exactly ONE flavour into ONE client: it replaces DIR/SpellTuner
# whole (so a TOC of the other flavour or a file an older build had cannot stay),
# and installing tbc also removes DIR/<Module> for every module of the tree.
# DIR must exist and end in AddOns. Every refusal happens before anything is built.
#
# Each package's file list is its flavour's TOCs' own load entries (the union, no
# duplicates), plus those TOCs and README.md, so a package can never drift from
# what its client loads; dev files (docs/, CLAUDE.md, Makefile, .git, this script)
# are excluded by construction. Each Modules/<Name>/ with at least one <Name>*.toc
# is its own package inside the Forever one, built from ITS OWN TOCs' file lists
# (T2); an entry under Engine/, Spells/, Data/ or UI/ that is not in the module
# folder is a shared file, copied from the repository root to the same path (T13c).
# A TOC's flavour is the marker file it loads (Client/TOC_TBC.lua tbc, Client/TOC_Mainline.lua
# or Client/TOC_Plain.lua forever) and every TOC under Modules/ is forever; its "## Interface:"
# band decides only for a TOC with neither, and a TOC whose interface is outside its
# flavour's band builds with a warning (T47). Markers and bands are tools/data/flavours.txt,
# the table Client/API.lua, tools/apicheck.py and tools/releasecheck.lua agree with. The
# version is every TOC's "## Version:" line, which must all be equal (T22): the
# build refuses otherwise, and --set-version bumps them together.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "ERROR: $*" >&2; exit 1; }

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

has_toc() { compgen -G "$1/SpellTuner*.toc" >/dev/null; }

resolve_source() {
    local want="$1"
    if [[ -d "$want" ]] && has_toc "$want"; then
        cd "$want" && pwd
        return
    fi
    while IFS=$'\t' read -r name path _; do
        if [[ "$name" == "$want" ]]; then echo "$path"; return; fi
    done < <(list_sources)
    die "unknown source '$want' (try --list)"
}

# Every TOC of a source, relative to it: the root's SpellTuner*.toc, then each
# Modules/<Name>/<Name>*.toc. Fills TOC_LIST.
TOC_LIST=()
list_tocs() {
    TOC_LIST=()
    local f d mname
    shopt -s nullglob
    for f in "$1"/SpellTuner*.toc; do TOC_LIST+=("$(basename "$f")"); done
    for d in "$1"/Modules/*/; do
        mname="$(basename "$d")"
        for f in "$d$mname"*.toc; do TOC_LIST+=("Modules/$mname/$(basename "$f")"); done
    done
    shopt -u nullglob
}

read_version() {
    sed -n 's/^## Version:[[:space:]]*//p' "$1" 2>/dev/null | tr -d '\r' | sed -n 's/[[:space:]]*$//;1p'
}

read_interface() {
    sed -n 's/^## Interface:[[:space:]]*//p' "$1" 2>/dev/null | tr -d '\r' | sed -n 's/[[:space:]]*$//;1p'
}

# The one version of a source, or "mixed" (for --list and the menu; never fails).
version_summary() {
    list_tocs "$1"
    local rel v first="" mixed=0
    for rel in ${TOC_LIST[@]+"${TOC_LIST[@]}"}; do
        v="$(read_version "$1/$rel")"
        if [[ -z "$first" ]]; then first="$v"; elif [[ "$v" != "$first" ]]; then mixed=1; fi
    done
    if [[ $mixed -eq 1 ]]; then echo "mixed"; elif [[ -n "$first" ]]; then echo "$first"; else echo "?"; fi
}

show_sources() {
    local i=0
    while IFS=$'\t' read -r name path branch; do
        i=$((i + 1))
        printf '  %d) %-22s v%-7s %s  (%s)\n' "$i" "$name" "$(version_summary "$path")" "$branch" "$path"
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

# ---------------------------------------------------------------- arguments ---

SRC="" OUT="" FLAVOUR_OPT="both" SET_VERSION="" SHOW_VERSION=0
INST_MODE=()   # tbc | forever | detect
INST_DIR=()
need_arg() { [[ $# -ge 2 ]] || die "$1 needs an argument"; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --src)             need_arg "$@"; SRC="$2"; shift 2 ;;
        --out)             need_arg "$@"; OUT="$2"; shift 2 ;;
        --flavour)         need_arg "$@"; FLAVOUR_OPT="$2"; shift 2 ;;
        --install)         need_arg "$@"; INST_MODE+=("detect"); INST_DIR+=("$2"); shift 2 ;;
        --install-tbc)     need_arg "$@"; INST_MODE+=("tbc"); INST_DIR+=("$2"); shift 2 ;;
        --install-forever) need_arg "$@"; INST_MODE+=("forever"); INST_DIR+=("$2"); shift 2 ;;
        --set-version)     need_arg "$@"; SET_VERSION="$2"; shift 2 ;;
        --version)         SHOW_VERSION=1; shift ;;
        --menu)            SRC="$(menu)"; shift ;;
        --list)            show_sources; exit 0 ;;
        -h|--help)         sed -n '2,/^set -euo pipefail/{/^set -euo pipefail/!p}' "$0"; exit 0 ;;
        -*)                die "unknown option $1 (try --help)" ;;
        *)                 INST_MODE+=("detect"); INST_DIR+=("$1"); shift ;;
    esac
done
case "$FLAVOUR_OPT" in tbc|forever|both) ;; *) die "--flavour is tbc, forever or both, not '$FLAVOUR_OPT'" ;; esac
if [[ ${#INST_DIR[@]} -eq 0 && -n "${WOW_ADDONS:-}" ]]; then
    INST_MODE+=("detect"); INST_DIR+=("$WOW_ADDONS")
fi

if [[ -z "$SRC" ]]; then
    SRC="$HERE"
else
    SRC="$(resolve_source "$SRC")"
fi

if [[ -n "$SET_VERSION" ]]; then
    [[ "$SET_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] \
        || die "--set-version '$SET_VERSION' is not x.y.z or x.y.z-suffix"
fi

# ------------------------------------------------------ 1. classify the TOCs ---

list_tocs "$SRC"
[[ ${#TOC_LIST[@]} -gt 0 ]] || die "no SpellTuner*.toc found in $SRC"

# The flavour table (T47): "<name> <marker files, comma-separated> <lo>-<hi>" per line.
FLAV_FILE=""
for cand in "$SRC/tools/data/flavours.txt" "$HERE/tools/data/flavours.txt"; do
    if [[ -f "$cand" ]]; then FLAV_FILE="$cand"; break; fi
done
[[ -n "$FLAV_FILE" ]] || die "no tools/data/flavours.txt (the flavour table) in $SRC or $HERE"
FLAV_NAMES=() FLAV_MARKERS=() FLAV_LO=() FLAV_HI=()
while read -r fname fmarkers fband _; do
    [[ -z "$fname" || "$fname" == \#* ]] && continue
    [[ "$fband" =~ ^([0-9]+)-([0-9]+)$ ]] || die "$FLAV_FILE: '$fname' has no band lo-hi"
    FLAV_NAMES+=("$fname"); FLAV_MARKERS+=("$fmarkers")
    FLAV_LO+=("${BASH_REMATCH[1]}"); FLAV_HI+=("${BASH_REMATCH[2]}")
done < <(tr -d '\r' < "$FLAV_FILE")
[[ ${#FLAV_NAMES[@]} -gt 0 ]] || die "$FLAV_FILE lists no flavour"

band_of() {                # tbc -> "20000-29999"
    local i
    for i in "${!FLAV_NAMES[@]}"; do
        if [[ "${FLAV_NAMES[$i]}" == "$1" ]]; then echo "${FLAV_LO[$i]}-${FLAV_HI[$i]}"; return 0; fi
    done
    return 0
}

class_of_interface() {     # "20506" / "11508, 11509" -> the flavour whose band holds them all, or nothing
    local v i any=0 all
    local -a hit=()
    for i in "${!FLAV_NAMES[@]}"; do hit[$i]=1; done
    for v in ${1//,/ }; do
        [[ "$v" =~ ^[0-9]+$ ]] || return 0
        v=$((10#$v)); any=1
        for i in "${!FLAV_NAMES[@]}"; do
            if [[ $v -lt ${FLAV_LO[$i]} || $v -gt ${FLAV_HI[$i]} ]]; then hit[$i]=0; fi
        done
    done
    [[ $any -eq 1 ]] || return 0
    for i in "${!FLAV_NAMES[@]}"; do
        if [[ ${hit[$i]} -eq 1 ]]; then echo "${FLAV_NAMES[$i]}"; return 0; fi
    done
    return 0
}

class_of_marker() {        # a TOC -> the flavour whose marker file it loads, "conflict", or nothing
    local found="" entry i m
    while IFS= read -r entry; do
        entry="${entry//\\//}"
        entry="${entry#"${entry%%[![:space:]]*}"}"; entry="${entry%"${entry##*[![:space:]]}"}"
        [[ -z "$entry" || "$entry" == \#* ]] && continue
        for i in "${!FLAV_NAMES[@]}"; do
            for m in ${FLAV_MARKERS[$i]//,/ }; do
                if [[ "$entry" == "$m" ]]; then
                    if [[ -n "$found" && "$found" != "${FLAV_NAMES[$i]}" ]]; then echo conflict; return 0; fi
                    found="${FLAV_NAMES[$i]}"
                fi
            done
        done
    done < <(tr -d '\r' < "$1")
    [[ -z "$found" ]] || echo "$found"
    return 0
}

TBC_TOCS=() FOREVER_TOCS=() MODULE_NAMES=()
for rel in "${TOC_LIST[@]}"; do
    iface="$(read_interface "$SRC/$rel")"
    band="$(class_of_interface "$iface")"
    class="$(class_of_marker "$SRC/$rel")" by="its marker file"
    [[ "$class" != conflict ]] || die "$rel loads the marker files of two flavours (tools/data/flavours.txt)"
    if [[ -z "$class" && "$rel" == Modules/* ]]; then class=forever by="its Modules/ folder"; fi
    if [[ -n "$class" ]]; then
        if [[ "$band" != "$class" ]]; then
            echo "WARNING: $rel has interface ${iface:-(none)}, outside $class's band $(band_of "$class") (tools/data/flavours.txt); packaged as $class by $by" >&2
        fi
    else
        class="$band"
        [[ -n "$class" ]] || die "$rel has no marker file and interface ${iface:-(none)} is in no band of tools/data/flavours.txt"
    fi
    if [[ "$rel" == Modules/* ]]; then
        [[ "$class" == forever ]] || die "$rel is $class: a module TOC must be forever"
        mname="${rel#Modules/}"; mname="${mname%%/*}"
        seen=0
        for m in ${MODULE_NAMES[@]+"${MODULE_NAMES[@]}"}; do [[ "$m" == "$mname" ]] && seen=1; done
        [[ $seen -eq 1 ]] || MODULE_NAMES+=("$mname")
    elif [[ "$class" == tbc ]]; then
        TBC_TOCS+=("$rel")
    elif [[ "$class" == forever ]]; then
        FOREVER_TOCS+=("$rel")
    else
        die "$rel is $class: release.sh packages tbc and forever only"
    fi
done

# ------------------------------------------------------- 5. --set-version ---

if [[ -n "$SET_VERSION" ]]; then
    for rel in "${TOC_LIST[@]}"; do
        # the CR of a CRLF file is in [[:space:]], so it stays in \2; nothing else moves
        sed "/^## Version:/s/^\\(## Version:[[:space:]]*\\)[^[:space:]]*\\(.*\\)\$/\\1$SET_VERSION\\2/" \
            "$SRC/$rel" > "$SRC/$rel.tmp.$$"
        cat "$SRC/$rel.tmp.$$" > "$SRC/$rel"
        rm -f "$SRC/$rel.tmp.$$"
        echo "Set $rel to $SET_VERSION"
    done
    exit 0
fi

# ------------------------------------------------------------ 2. one version ---

VERSION=""
for rel in "${TOC_LIST[@]}"; do
    v="$(read_version "$SRC/$rel")"
    [[ -n "$v" ]] || die "no '## Version:' line in $rel"
    if [[ -z "$VERSION" ]]; then VERSION="$v"; fi
done
agree=1
for rel in "${TOC_LIST[@]}"; do
    [[ "$(read_version "$SRC/$rel")" == "$VERSION" ]] || agree=0
done
if [[ $agree -eq 0 ]]; then
    echo "ERROR: the TOCs disagree on the version:" >&2
    for rel in "${TOC_LIST[@]}"; do echo "  $rel: $(read_version "$SRC/$rel")" >&2; done
    exit 1
fi
if [[ $SHOW_VERSION -eq 1 ]]; then echo "$VERSION"; exit 0; fi

# ------------------------------------------------------------- 4. installs ---
# Validated now, so every refusal comes before anything is built or written.

VALID_FLAV=() VALID_DIR=()
for i in "${!INST_DIR[@]}"; do
    dir="${INST_DIR[$i]}"
    mode="${INST_MODE[$i]}"
    while [[ "$dir" == */ && "$dir" != "/" ]]; do dir="${dir%/}"; done
    [[ -d "$dir" ]] || die "AddOns folder not found: $dir"
    dir="$(cd "$dir" && pwd)"
    [[ "$(basename "$dir")" == "AddOns" ]] || die "$dir is not an AddOns folder (its last component must be AddOns)"
    detected=""
    case "$dir/" in
        */_classic_beta_/*) detected="forever" ;;
    esac
    case "$dir/" in
        */_anniversary_/*) if [[ -n "$detected" ]]; then detected="both"; else detected="tbc"; fi ;;
    esac
    if [[ "$mode" == detect ]]; then
        if [[ "$detected" != tbc && "$detected" != forever ]]; then
            die "cannot tell which client $dir belongs to; use --install-tbc or --install-forever"
        fi
        mode="$detected"
    elif [[ -n "$detected" && "$detected" != "$mode" ]]; then
        die "$dir looks like a $detected client; refusing to install $mode there"
    fi
    VALID_FLAV+=("$mode"); VALID_DIR+=("$dir")
done

# what to build: the option, and at least whatever an install needs
want_tbc=0 want_fv=0 need_tbc=0 need_fv=0
case "$FLAVOUR_OPT" in
    tbc) want_tbc=1; need_tbc=1 ;;
    forever) want_fv=1; need_fv=1 ;;
    both) want_tbc=1; want_fv=1 ;;
esac
for f in ${VALID_FLAV[@]+"${VALID_FLAV[@]}"}; do
    if [[ "$f" == tbc ]]; then want_tbc=1; need_tbc=1; else want_fv=1; need_fv=1; fi
done
BUILD=()
if [[ $want_tbc -eq 1 ]]; then
    if [[ ${#TBC_TOCS[@]} -gt 0 ]]; then BUILD+=(tbc); elif [[ $need_tbc -eq 1 ]]; then die "no TBC TOC in $SRC"; fi
fi
if [[ $want_fv -eq 1 ]]; then
    if [[ ${#FOREVER_TOCS[@]} -gt 0 ]]; then BUILD+=(forever); elif [[ $need_fv -eq 1 ]]; then die "no Forever TOC in $SRC"; fi
fi
[[ ${#BUILD[@]} -gt 0 ]] || die "nothing to build in $SRC"

NAME="$(basename "$SRC")"
[[ "$SRC" == "$ROOT" ]] && NAME="main"
[[ -n "$OUT" ]] || OUT="$ROOT/dist/$NAME"
REL="${OUT#$ROOT/}"

# ---------------------------------------------------------- 3. the packages ---

# FILES: README.md, the flavour's root TOCs and the union (no duplicates) of
# their load entries -- a file two TOCs share (Client/API.lua) is packaged once.
FILES=()
have() { local x; for x in "${FILES[@]}"; do [[ "$x" == "$1" ]] && return 0; done; return 1; }
collect_core() {
    local tocs=() toc line entry
    if [[ "$1" == tbc ]]; then tocs=("${TBC_TOCS[@]}"); else tocs=("${FOREVER_TOCS[@]}"); fi
    FILES=("README.md")
    for toc in "${tocs[@]}"; do FILES+=("$toc"); done
    for toc in "${tocs[@]}"; do
        while IFS= read -r line; do
            line="${line%$'\r'}"                      # strip CR (the .toc may be CRLF)
            [[ -z "$line" || "$line" == \#* ]] && continue
            entry="${line//\\//}"                     # .toc uses backslashes; use / on disk
            have "$entry" || FILES+=("$entry")
        done < "$SRC/$toc"
    done
}

# A module's files (T2), from ITS OWN TOCs. T13c: an entry not under the module's
# own folder is a shared file (Engine/SimModel.lua etc.) the client never loads
# across addon folders, so it is resolved at the repository root under the same
# four shared folders the stub and apicheck.py accept, and copied to the SAME
# relative path inside the package. Anything else missing is an error.
MFILES=() MSRC=() MISSING=0
mhave() { local x; for x in "${MFILES[@]}"; do [[ "$x" == "$1" ]] && return 0; done; return 1; }
collect_module() {
    local mname="$1" mdir="$SRC/Modules/$1" toc line entry f mtocs=()
    shopt -s nullglob
    mtocs=("$mdir"/"$mname"*.toc)
    shopt -u nullglob
    MFILES=() MSRC=()
    for f in "${mtocs[@]}"; do MFILES+=("$(basename "$f")"); done
    for toc in "${mtocs[@]}"; do
        while IFS= read -r line; do
            line="${line%$'\r'}"
            [[ -z "$line" || "$line" == \#* ]] && continue
            entry="${line//\\//}"
            mhave "$entry" || MFILES+=("$entry")
        done < "$toc"
    done
    for f in "${MFILES[@]}"; do
        if [[ -f "$mdir/$f" ]]; then
            MSRC+=("$mdir/$f")
        elif [[ "$f" == Engine/* || "$f" == Spells/* || "$f" == Data/* || "$f" == UI/* ]] && [[ -f "$SRC/$f" ]]; then
            MSRC+=("$SRC/$f")
        else
            echo "ERROR: Modules/$mname/$f is listed in the .toc but missing on disk" >&2
            MISSING=1
            MSRC+=("")
        fi
    done
}

# Verify everything exists before touching the output.
for fl in "${BUILD[@]}"; do
    collect_core "$fl"
    for f in "${FILES[@]}"; do
        if [[ ! -f "$SRC/$f" ]]; then
            echo "ERROR: $f is listed in the .toc but missing on disk" >&2
            MISSING=1
        fi
    done
    if [[ "$fl" == forever ]]; then
        for mname in ${MODULE_NAMES[@]+"${MODULE_NAMES[@]}"}; do collect_module "$mname"; done
    fi
done
[[ $MISSING -eq 0 ]] || exit 1

# The old layout (one mixed SpellTuner/ and its siblings straight under OUT) must
# not linger where someone would copy it.
mkdir -p "$OUT"
rm -rf "$OUT/SpellTuner" "$OUT"/SpellTuner_*

for fl in "${BUILD[@]}"; do
    pkg="$OUT/$fl"
    rm -rf "$pkg"
    mkdir -p "$pkg/SpellTuner"
    collect_core "$fl"
    for f in "${FILES[@]}"; do
        mkdir -p "$pkg/SpellTuner/$(dirname "$f")"
        cp "$SRC/$f" "$pkg/SpellTuner/$f"
    done
    nfiles=${#FILES[@]}

    folders=(SpellTuner)
    if [[ "$fl" == forever ]]; then
        for mname in ${MODULE_NAMES[@]+"${MODULE_NAMES[@]}"}; do
            collect_module "$mname"
            mkdir -p "$pkg/$mname"
            for i in "${!MFILES[@]}"; do
                f="${MFILES[$i]}"
                mkdir -p "$pkg/$mname/$(dirname "$f")"
                cp "${MSRC[$i]}" "$pkg/$mname/$f"
            done
            folders+=("$mname")
        done
    fi

    if [[ "$fl" == forever && ${#MODULE_NAMES[@]} -gt 0 ]]; then
        echo "Built $REL/$fl/SpellTuner (v$VERSION, $nfiles files) from $NAME," \
            "plus ${#MODULE_NAMES[@]} module(s): ${MODULE_NAMES[*]}."
    else
        echo "Built $REL/$fl/SpellTuner (v$VERSION, $nfiles files) from $NAME."
    fi

    # Zip (zip if available, python3 zipfile as fallback): the flavour's folders,
    # paths inside relative to the flavour folder.
    ZIP="$OUT/SpellTuner-$fl-$VERSION.zip"
    rm -f "$ZIP"
    if command -v zip >/dev/null 2>&1; then
        (cd "$pkg" && zip -qr "../$(basename "$ZIP")" "${folders[@]}")
        echo "Built $REL/$(basename "$ZIP")"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$pkg" "$ZIP" "$REL" "${folders[@]}" <<'PYEOF'
import os, sys, zipfile
pkg_dir, out, rel = sys.argv[1], sys.argv[2], sys.argv[3]
folders = sys.argv[4:]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for folder in folders:
        for base, dirs, names in os.walk(os.path.join(pkg_dir, folder)):
            dirs.sort()
            for name in sorted(names):
                path = os.path.join(base, name)
                z.write(path, os.path.relpath(path, pkg_dir))
print("Built " + rel + "/" + os.path.basename(out))
PYEOF
    else
        echo "NOTE: neither zip nor python3 found — skipped the zip archive."
    fi
done

# ---------------------------------------------------------------- installs ---
# Replacing SpellTuner/ whole is what removes another flavour's TOC (and any file
# an older build had) from the client.

for i in "${!VALID_DIR[@]}"; do
    dir="${VALID_DIR[$i]}"
    fl="${VALID_FLAV[$i]}"
    rm -rf "$dir/SpellTuner"
    cp -r "$OUT/$fl/SpellTuner" "$dir/SpellTuner"
    for mname in ${MODULE_NAMES[@]+"${MODULE_NAMES[@]}"}; do
        if [[ "$fl" == forever ]]; then
            rm -rf "$dir/$mname"
            cp -r "$OUT/forever/$mname" "$dir/$mname"
        elif [[ -e "$dir/$mname" ]]; then
            rm -rf "$dir/$mname"
            echo "Removed stale $dir/$mname (Forever only)"
        fi
    done
    echo "Installed $fl v$VERSION into $dir"
done

if [[ ${#VALID_DIR[@]} -eq 0 ]]; then
    echo "Copy $REL/<flavour>/SpellTuner (and, for Forever, its siblings) into the matching client's Interface/AddOns folder, or:"
    echo "  ./release.sh --install-tbc \"/mnt/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns\""
    echo "  ./release.sh --install-forever \"/mnt/c/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns\""
    echo "(or: make install WOW_ADDONS=\"<AddOns folder>\" [FLAVOUR=tbc|forever])"
fi
