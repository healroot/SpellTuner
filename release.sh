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
#
# Publishing to CurseForge (T-publish, docs/tasks/T-publish-curseforge.md):
#
#   ./release.sh --publish [--release-type alpha|beta|release] [--dry-run] [--only tbc|forever]
#
# builds both packages as above, then uploads each zip (both, or the --only one) to
# the CurseForge project named in tools/data/curseforge.txt (project_id, each
# flavour's game version NAMES, release_type), as "SpellTuner <version> (TBC)" /
# "(Forever)", the changelog the newest docs/HISTORY.md entry. The token is the
# environment variable CURSEFORGE_API_TOKEN and nothing else:
#
#   ~/.local/bin/secret-env run CURSEFORGE_API_TOKEN -- ./release.sh --publish --dry-run
#
# It is never printed, never on a command line (curl reads it from a config on
# stdin) and never traced: this script turns xtrace off when the variable is set,
# and no child process inherits it. Refused before anything is built: an empty
# project_id, no token (except --dry-run), a tree with uncommitted changes or a
# HEAD whose TOCs are not at the version, a flavour already published at this
# version (dist/<name>/published.txt, not committed). Refused before anything is
# uploaded: a game version name CurseForge does not list. --dry-run prints what it
# would send, says only whether the token is present, and contacts nothing.
set -euo pipefail

# The CurseForge token (T-publish): xtrace off before it is read, taken into a
# shell variable no child process inherits, removed from the environment.
[[ -z "${CURSEFORGE_API_TOKEN:+set}" ]] || { set +x; } 2>/dev/null
CF_TOKEN="${CURSEFORGE_API_TOKEN:-}"
unset CURSEFORGE_API_TOKEN

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

SRC="" OUT="" FLAVOUR_OPT="both" FLAVOUR_SET=0 SET_VERSION="" SHOW_VERSION=0
PUBLISH=0 DRY_RUN=0 ONLY="" RELEASE_TYPE=""
INST_MODE=()   # tbc | forever | detect
INST_DIR=()
need_arg() { [[ $# -ge 2 ]] || die "$1 needs an argument"; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --src)             need_arg "$@"; SRC="$2"; shift 2 ;;
        --out)             need_arg "$@"; OUT="$2"; shift 2 ;;
        --flavour)         need_arg "$@"; FLAVOUR_OPT="$2"; FLAVOUR_SET=1; shift 2 ;;
        --publish)         PUBLISH=1; shift ;;
        --dry-run)         DRY_RUN=1; shift ;;
        --only)            need_arg "$@"; ONLY="$2"; shift 2 ;;
        --release-type)    need_arg "$@"; RELEASE_TYPE="$2"; shift 2 ;;
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
if [[ $PUBLISH -eq 1 ]]; then
    [[ -z "$SET_VERSION" && $SHOW_VERSION -eq 0 ]] || die "--publish does not combine with --set-version or --version"
    [[ ${#INST_DIR[@]} -eq 0 ]] || die "--publish does not install; run the install on its own"
    [[ $FLAVOUR_SET -eq 0 ]] || die "--publish builds both flavours; --only tbc|forever picks the one to upload"
    case "$ONLY" in ""|tbc|forever) ;; *) die "--only is tbc or forever, not '$ONLY'" ;; esac
    case "$RELEASE_TYPE" in ""|alpha|beta|release) ;; *) die "--release-type is alpha, beta or release, not '$RELEASE_TYPE'" ;; esac
else
    [[ $DRY_RUN -eq 0 && -z "$ONLY" && -z "$RELEASE_TYPE" ]] || die "--dry-run, --only and --release-type go with --publish"
fi
# a publish installs nothing, so $WOW_ADDONS is not read for it
if [[ $PUBLISH -eq 0 && ${#INST_DIR[@]} -eq 0 && -n "${WOW_ADDONS:-}" ]]; then
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

# ------------------------------------------------- publish: before building ---
# Every refusal of --publish that needs no network comes here, before the build
# touches the output (T-publish).

CF_API="https://wow.curseforge.com/api"
CF_FILE="$SRC/tools/data/curseforge.txt"
CF_FLAVOURS=() CF_TMP="" CF_PROJECT="" CF_RECORD=""
cf_label() { if [[ "$1" == tbc ]]; then echo "TBC"; else echo "Forever"; fi; }
cf_get() {                 # the value of "key = value" in the config, or nothing
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$CF_FILE" | tr -d '\r' | sed 's/[[:space:]]*$//' | tail -n 1
}
if [[ $PUBLISH -eq 1 ]]; then
    [[ -f "$CF_FILE" ]] || die "--publish needs tools/data/curseforge.txt (project_id, the game version names) in $SRC"
    CF_PROJECT="$(cf_get project_id)"
    [[ -n "$CF_PROJECT" ]] || die "tools/data/curseforge.txt: project_id is empty -- fill in the CurseForge project's id ($CF_FILE) and commit it"
    [[ "$CF_PROJECT" =~ ^[0-9]+$ ]] || die "tools/data/curseforge.txt: project_id '$CF_PROJECT' is not a number"
    [[ -n "$RELEASE_TYPE" ]] || RELEASE_TYPE="$(cf_get release_type)"
    [[ -n "$RELEASE_TYPE" ]] || RELEASE_TYPE="beta"
    case "$RELEASE_TYPE" in
        alpha|beta|release) ;;
        *) die "tools/data/curseforge.txt: release_type is alpha, beta or release, not '$RELEASE_TYPE'" ;;
    esac
    if [[ -n "$ONLY" ]]; then CF_FLAVOURS=("$ONLY"); else CF_FLAVOURS=(tbc forever); fi
    for fl in "${CF_FLAVOURS[@]}"; do
        [[ " ${BUILD[*]} " == *" $fl "* ]] || die "--publish: no $(cf_label "$fl") TOC in $SRC"
        [[ -n "$(cf_get "${fl}_game_versions")" ]] \
            || die "tools/data/curseforge.txt: ${fl}_game_versions is empty -- name the game versions the $(cf_label "$fl") zip is for"
    done
    command -v python3 >/dev/null 2>&1 || die "--publish needs python3 (the metadata JSON and CurseForge's answers)"
    if [[ $DRY_RUN -eq 0 ]]; then
        [[ -n "$CF_TOKEN" ]] || die "--publish needs the CurseForge token in CURSEFORGE_API_TOKEN:" \
            "~/.local/bin/secret-env run CURSEFORGE_API_TOKEN -- ./release.sh --publish ..."
        [[ "$CF_TOKEN" != *[[:space:]\"\\]* ]] || die "CURSEFORGE_API_TOKEN holds whitespace, a quote or a backslash; not a token"
        command -v curl >/dev/null 2>&1 || die "--publish needs curl"
    fi
    git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "--publish needs a git checkout; $SRC is not one"
    CF_DIRTY="$(git -C "$SRC" status --porcelain)"
    if [[ -n "$CF_DIRTY" ]]; then
        echo "ERROR: --publish needs a clean tree; $SRC has uncommitted changes:" >&2
        echo "$CF_DIRTY" | head -n 10 | sed 's/^/  /' >&2
        exit 1
    fi
    for rel in "${TOC_LIST[@]}"; do
        v="$(git -C "$SRC" show "HEAD:./$rel" 2>/dev/null | sed -n 's/^## Version:[[:space:]]*//p' | tr -d '\r' | sed -n 's/[[:space:]]*$//;1p')" || v=""
        [[ "$v" == "$VERSION" ]] || die "--publish: HEAD's $rel is at ${v:-(not committed)}, not $VERSION -- commit the version first"
    done
    # the upload record: "<version> TAB <flavour> TAB <file id> TAB <UTC time> TAB <project id>"
    CF_RECORD="$OUT/published.txt"
    for fl in "${CF_FLAVOURS[@]}"; do
        prev=""
        [[ ! -f "$CF_RECORD" ]] || prev="$(awk -F'\t' -v v="$VERSION" -v f="$fl" '$1 == v && $2 == f { print $3; exit }' "$CF_RECORD")"
        [[ -z "$prev" ]] || die "SpellTuner $VERSION ($(cf_label "$fl")) was already published (file id $prev, $REL/published.txt);" \
            "bump the version (--set-version) to publish again"
    done
    CF_TMP="$(mktemp -d)"
    trap 'rm -rf "$CF_TMP"' EXIT
    # the changelog: the newest docs/HISTORY.md entry (its "## " heading to the end), trimmed
    [[ -f "$SRC/docs/HISTORY.md" ]] || die "--publish takes its changelog from docs/HISTORY.md; $SRC has none"
    python3 - "$SRC/docs/HISTORY.md" "$CF_TMP/changelog.md" <<'PYEOF' || die "no '## ' entry in docs/HISTORY.md to take the changelog from"
import sys
LIMIT = 4000
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
starts = [i for i, l in enumerate(lines) if l.startswith("## ")]
if not starts:
    sys.exit(1)
text = "\n".join(lines[starts[-1]:]).strip()
if len(text) > LIMIT:
    note = "\n\n(trimmed)"
    cut = text.rfind("\n", 0, LIMIT - len(note))
    text = text[:cut if cut > 0 else LIMIT - len(note)].rstrip() + note
with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write(text)
PYEOF
fi

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

# ------------------------------------------------------ publish: the uploads ---
# The token goes to curl in a config read from stdin (printf is a builtin, so it is
# on no command line); xtrace is off since the token was read.

# cf_curl <response file> <curl arguments...>: prints the HTTP status
cf_curl() {
    printf 'header = "X-Api-Token: %s"\n' "$CF_TOKEN" \
        | curl -sS --connect-timeout 20 --max-time 600 -K - -o "$1" -w '%{http_code}' "${@:2}"
}

# cf_body <response file>: its start, for an error line, the token never in it
cf_body() {
    local body
    body="$(head -c 300 "$1" 2>/dev/null | tr '\r\n' '  ')" || body=""
    echo "${body//"$CF_TOKEN"/<token>}"
}

# cf_metadata <flavour> <comma list> names|ids: the metadata JSON (pretty with names
# for a dry run, compact with the ids for an upload)
cf_metadata() {
    python3 - "$CF_TMP/changelog.md" "SpellTuner $VERSION ($(cf_label "$1"))" "$RELEASE_TYPE" "$2" "$3" <<'PYEOF'
import json, sys
changelog, display, release, versions, mode = sys.argv[1:6]
items = [v.strip() for v in versions.split(",") if v.strip()]
meta = {
    "changelog": open(changelog, encoding="utf-8").read(),
    "changelogType": "markdown",
    "displayName": display,
    "gameVersions": items if mode == "names" else [int(v) for v in items],
    "releaseType": release,
}
if mode == "names":
    print(json.dumps(meta, indent=2, sort_keys=True))
else:
    print(json.dumps(meta, separators=(",", ":"), sort_keys=True))
PYEOF
}

# cf_resolve <flavour>: the ids of its game version names ("1,2"), or the reasons it cannot
cf_resolve() {
    python3 - "$CF_TMP/versions.json" "$(cf_get "${1}_game_versions")" <<'PYEOF'
import json, sys
try:
    versions = json.load(open(sys.argv[1], encoding="utf-8"))
except ValueError:
    versions = None
if not isinstance(versions, list):
    print("CurseForge's game version list is not a JSON list")
    sys.exit(1)
ids, bad = [], []
for name in [n.strip() for n in sys.argv[2].split(",") if n.strip()]:
    want, vtype = name, None
    if "@" in name:
        want, _, t = name.rpartition("@")
        vtype = int(t) if t.isdigit() else -1
    hits = [v for v in versions if isinstance(v, dict) and v.get("name") == want
            and (vtype is None or v.get("gameVersionTypeID") == vtype)]
    if not hits:
        bad.append("'%s' is not a game version CurseForge lists" % name)
    elif len(hits) > 1:
        bad.append("'%s' is %s -- write it as name@<gameVersionTypeID>" % (name, ", ".join(
            "id %s (type %s)" % (h.get("id"), h.get("gameVersionTypeID")) for h in hits)))
    elif not isinstance(hits[0].get("id"), int):
        bad.append("'%s' has no numeric id" % name)
    else:
        ids.append(str(hits[0]["id"]))
if bad:
    print("; ".join(bad))
    sys.exit(1)
print(",".join(ids))
PYEOF
}

publish() {
    { set +x; } 2>/dev/null
    local fl i zip label status id out
    local -a ids=() bad=() done_fl=()
    for fl in "${CF_FLAVOURS[@]}"; do
        [[ -f "$OUT/SpellTuner-$fl-$VERSION.zip" ]] || die "no $REL/SpellTuner-$fl-$VERSION.zip to upload (zip or python3 makes it)"
    done

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "Dry run: nothing is sent to CurseForge."
        if [[ -n "$CF_TOKEN" ]]; then
            echo "  token: present (CURSEFORGE_API_TOKEN)"
        else
            echo "  token: absent -- the real run refuses without CURSEFORGE_API_TOKEN"
        fi
        echo "  first: GET $CF_API/game/versions, every name below to its id; a name it does not list stops the run before any upload"
        for fl in "${CF_FLAVOURS[@]}"; do
            zip="$OUT/SpellTuner-$fl-$VERSION.zip"
            echo "SpellTuner $VERSION ($(cf_label "$fl")): POST $CF_API/projects/$CF_PROJECT/upload-file"
            echo "  file: $REL/$(basename "$zip") ($(wc -c < "$zip" | tr -d ' ') bytes)"
            echo "  game versions: $(cf_get "${fl}_game_versions") (names here; the upload sends their ids)"
            echo "  metadata:"
            cf_metadata "$fl" "$(cf_get "${fl}_game_versions")" names | sed 's/^/    /'
        done
        echo "A dry run records nothing in $REL/published.txt."
        return 0
    fi

    # 1. every name to its id, before anything is uploaded
    status="$(cf_curl "$CF_TMP/versions.json" "$CF_API/game/versions")" || die "could not read $CF_API/game/versions (curl failed); nothing uploaded"
    [[ "$status" == 200 ]] || die "GET $CF_API/game/versions answered HTTP $status: $(cf_body "$CF_TMP/versions.json"); nothing uploaded"
    for i in "${!CF_FLAVOURS[@]}"; do
        fl="${CF_FLAVOURS[$i]}"
        if out="$(cf_resolve "$fl")"; then
            ids[$i]="$out"
        else
            echo "ERROR: $(cf_label "$fl") ($fl): ${fl}_game_versions in tools/data/curseforge.txt: $out" >&2
            bad+=("$fl")
        fi
    done
    if [[ ${#bad[@]} -gt 0 ]]; then
        for fl in "${CF_FLAVOURS[@]}"; do
            if [[ " ${bad[*]} " != *" $fl "* ]]; then
                echo "  the $(cf_label "$fl") versions resolve: ./release.sh --publish --only $fl uploads that zip alone" >&2
            fi
        done
        die "nothing uploaded"
    fi

    # 2. the uploads, each recorded as soon as CurseForge answers with its file id
    for i in "${!CF_FLAVOURS[@]}"; do
        fl="${CF_FLAVOURS[$i]}"
        label="$(cf_label "$fl")"
        zip="SpellTuner-$fl-$VERSION.zip"
        cf_metadata "$fl" "${ids[$i]}" ids > "$CF_TMP/metadata-$fl.json"
        echo "Uploading $REL/$zip to CurseForge project $CF_PROJECT as \"SpellTuner $VERSION ($label)\", $RELEASE_TYPE, game versions ${ids[$i]} ..."
        local after=""
        [[ ${#done_fl[@]} -eq 0 ]] || after=" (already uploaded and recorded: ${done_fl[*]})"
        status="$(cd "$OUT" && cf_curl "$CF_TMP/upload-$fl.json" -F "metadata=<$CF_TMP/metadata-$fl.json" -F "file=@$zip" \
            "$CF_API/projects/$CF_PROJECT/upload-file")" || die "the upload of $zip failed (curl)$after"
        [[ "$status" == 200 ]] || die "CurseForge refused $zip: HTTP $status: $(cf_body "$CF_TMP/upload-$fl.json")$after"
        id="$(python3 -c 'import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
i = d.get("id") if isinstance(d, dict) else None
if not isinstance(i, int) or isinstance(i, bool):
    sys.exit(1)
print(i)' "$CF_TMP/upload-$fl.json" 2>/dev/null)" || die "CurseForge answered $zip without a file id: $(cf_body "$CF_TMP/upload-$fl.json")$after"
        printf '%s\t%s\t%s\t%s\t%s\n' "$VERSION" "$fl" "$id" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CF_PROJECT" >> "$CF_RECORD"
        done_fl+=("$fl")
        echo "Published SpellTuner $VERSION ($label) to CurseForge project $CF_PROJECT: file id $id"
    done
}

if [[ $PUBLISH -eq 1 ]]; then
    publish
    exit 0
fi

if [[ ${#VALID_DIR[@]} -eq 0 ]]; then
    echo "Copy $REL/<flavour>/SpellTuner (and, for Forever, its siblings) into the matching client's Interface/AddOns folder, or:"
    echo "  ./release.sh --install-tbc \"/mnt/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns\""
    echo "  ./release.sh --install-forever \"/mnt/c/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns\""
    echo "(or: make install WOW_ADDONS=\"<AddOns folder>\" [FLAVOUR=tbc|forever])"
fi
