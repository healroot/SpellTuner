#!/usr/bin/env bash
# tools/check.sh -- every suite, one verdict (T57, P13, review Q4, Q5, Q15).
#
#   tools/check.sh                    run everything; exit 0 only when all of it passed
#   tools/check.sh --only a,b         only the suites named (no "expected but not run")
#   tools/check.sh --counts FILE      compare with FILE instead of tools/data/expected-counts.json
#   tools/check.sh --write-counts     after a green run, write the counts to that file
#   tools/check.sh --tree NAME|DIR    run the check of another source (a worktree name
#                                     from ./release.sh --list, or a directory) -- its own
#                                     tools/check.sh, so the code checked is the code built
#   tools/check.sh --pick             ask which source (./release.sh --list) and print its
#                                     path (make release / make install use it)
#
# What it runs:
#   * every tools/*.lua that is a suite (all but the helpers and research tools in
#     NOT_SUITES below), under EACH flavour its HARNESS_FLAVOUR line declares
#     (tools/run.sh --flavour F), or plainly when it declares none -- ST_FLAVOUR is
#     always scrubbed first, so a flavour exported in the shell reaches nothing;
#   * tools/lib/t.lua's self-test;
#   * the harness's skip: a tbc-only suite under forever must exit 3 and say "skip:";
#   * two smoke runs of the research tools on the author's practice fight
#     (tools/reproduce.lua and tools/strategies.lua --fixture);
#   * python3 tools/apicheck.py (0 findings) and tools/textcheck.py, and the
#     --selftest of apicheck, textcheck and refcheck.
#
# A suite passes when it exits 0 AND prints the standard footer "<n> ok, 0 failed"
# with n > 0 AND prints no assertion line marked FAIL. Exit 3 is the harness's
# skip: under a flavour this script asked for it is a failure, never a pass.
# Counts are compared with tools/data/expected-counts.json ({"suite/flavour": n}):
# fewer assertions than expected fails, a run the file expects that did not happen
# fails (a suite whose declaration lost a flavour), more is reported, not failed.
# Every run's output is kept in tools/.lua/check/<suite>.<flavour>.out.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# tools/*.lua that are not suites: loaded by suites, or research tools that read
# the author's own (gitignored) data. A new file not listed here is run as a
# suite, and fails loudly if it has no footer -- add it here if it is not one.
NOT_SUITES=" harness wowstub stub_art stub_hosts stub_books fakepull foreverfixture import importforever importfixture reportlines svwrite buildintuition strategies solvercmp wclcheckkit reproduce healcheck "

COUNTS_FILE="$ROOT/tools/data/expected-counts.json"
WRITE_COUNTS=0
ONLY=""
OUT_DIR="$ROOT/tools/.lua/check"

die() { echo "tools/check.sh: $*" >&2; exit 2; }

# The path of a source named as ./release.sh --list names it, or a directory.
resolve_tree() {
    local want="$1" line num name path
    # "  3) name   v0.16.3  branch  (/path)" -- release.sh's show_sources
    local re='^ *([0-9]+)\) ([^ ]+) +v[^ ]+ +[^ ]+ +\((.*)\)$'
    if [ -d "$want" ] && compgen -G "$want/SpellTuner*.toc" >/dev/null; then
        (cd "$want" && pwd); return 0
    fi
    while IFS= read -r line; do
        if [[ "$line" =~ $re ]]; then
            num="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"; path="${BASH_REMATCH[3]}"
            if [ "$want" = "$name" ] || [ "$want" = "$num" ]; then echo "$path"; return 0; fi
        fi
    done < <("$ROOT/release.sh" --list)
    return 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --only)         [ $# -ge 2 ] || die "--only needs a list"; ONLY=",$2,"; shift 2 ;;
        --counts)       [ $# -ge 2 ] || die "--counts needs a file"; COUNTS_FILE="$2"; shift 2 ;;
        --write-counts) WRITE_COUNTS=1; shift ;;
        --tree)
            [ $# -ge 2 ] || die "--tree needs a source"
            dir="$(resolve_tree "$2")" || die "unknown source '$2' (./release.sh --list)"
            shift 2
            if [ "$dir" = "$ROOT" ]; then continue; fi
            [ -x "$dir/tools/check.sh" ] || die "$dir has no tools/check.sh (older than T57): check it by hand, or NO_CHECK=1"
            echo "tools/check.sh: checking $dir"
            exec "$dir/tools/check.sh" "$@"
            ;;
        --pick)
            "$ROOT/release.sh" --list >&2
            read -rp "Choice [1]: " choice || die "no choice read"
            resolve_tree "${choice:-1}" || die "unknown source '${choice:-1}'"
            exit 0
            ;;
        -h|--help)      sed -n '2,/^set -uo pipefail/{/^set -uo pipefail/!p}' "$0"; exit 0 ;;
        *)              die "unknown option $1 (try --help)" ;;
    esac
done

mkdir -p "$OUT_DIR"
RESULTS="$OUT_DIR/results.tsv"      # key <TAB> count
: > "$RESULTS"
FAILED=()
RUNS=0

wanted() { [ -z "$ONLY" ] || [[ "$ONLY" == *",$1,"* ]]; }

# note <key> <verdict line>
report() { printf '  %-5s %-26s %s\n' "$1" "$2" "$3"; }

# Judge one suite run: rc, the footer, the FAIL lines.
judge_suite() {
    local key="$1" rc="$2" out="$3" footer okN failN fails
    RUNS=$((RUNS + 1))
    footer="$(grep -E '^[0-9]+ ok, [0-9]+ failed$' "$out" | tail -1)"
    okN="${footer%% ok,*}"
    failN="$(echo "$footer" | sed -n 's/^[0-9]* ok, \([0-9]*\) failed$/\1/p')"
    # an assertion printed as failed: "<name> FAIL" or "<name> FAIL - <detail>",
    # or a footer's "FAIL <name>" / "FAIL: <name>" list line
    fails="$(grep -E '(^[[:space:]]*FAIL[: ])|([[:space:]]FAIL( - .*)?$)' "$out" | head -5)"
    if [ "$rc" -eq 3 ]; then
        report FAIL "$key" "skipped (exit 3) under a flavour it was asked for: $(grep -m1 '^skip:' "$out")"
    elif [ "$rc" -ne 0 ]; then
        report FAIL "$key" "exit $rc${footer:+ ($footer)}"
    elif [ -z "$footer" ]; then
        report FAIL "$key" "no footer (\"<n> ok, <m> failed\"): $(tail -1 "$out" | cut -c1-80)"
    elif [ "$failN" != "0" ] || [ -n "$fails" ] || [ "$okN" = "0" ]; then
        report FAIL "$key" "$footer"
    else
        report ok "$key" "$okN"
        printf '%s\t%s\n' "$key" "$okN" >> "$RESULTS"
        return 0
    fi
    [ -n "$fails" ] && echo "$fails" | sed 's/^/          /' | cut -c1-160
    echo "          output: ${out#$ROOT/}"
    FAILED+=("$key")
    return 1
}

run_suite() {
    local name="$1" flavour="$2" key out rc
    if [ -n "$flavour" ]; then key="$name/$flavour"; else key="$name"; fi
    out="$OUT_DIR/${key//\//.}.out"
    if [ -n "$flavour" ]; then
        env -u ST_FLAVOUR "$ROOT/tools/run.sh" --flavour "$flavour" "tools/$name.lua" > "$out" 2>&1
    else
        env -u ST_FLAVOUR "$ROOT/tools/run.sh" "tools/$name.lua" > "$out" 2>&1
    fi
    rc=$?
    judge_suite "$key" "$rc" "$out"
}

# A command that is not a suite: exit 0 and (when given) a line matching $3.
# $4, when given, is a sed expression printing the count kept for $1.
run_other() {
    local key="$1" cmd="$2" want="${3:-}" countExpr="${4:-}" out rc n
    out="$OUT_DIR/${key//[\/ ]/.}.out"
    RUNS=$((RUNS + 1))
    bash -c "$cmd" > "$out" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        report FAIL "$key" "exit $rc: $(tail -1 "$out" | cut -c1-100)"
    elif [ -n "$want" ] && ! grep -qE "$want" "$out"; then
        report FAIL "$key" "no line matching /$want/: $(tail -1 "$out" | cut -c1-80)"
    else
        n=""
        [ -n "$countExpr" ] && n="$(sed -n "$countExpr" "$out" | tail -1)"
        report ok "$key" "${n:-$(tail -1 "$out" | cut -c1-80)}"
        [ -n "$n" ] && printf '%s\t%s\n' "$key" "$n" >> "$RESULTS"
        return 0
    fi
    echo "          output: ${out#$ROOT/}"
    FAILED+=("$key")
    return 1
}

echo "tools/check.sh: $ROOT"
echo "suites"
for f in "$ROOT"/tools/*.lua; do
    name="$(basename "$f" .lua)"
    [[ "$NOT_SUITES" == *" $name "* ]] && continue
    flavours="$(grep -m1 -E '^HARNESS_FLAVOUR[[:space:]]*=' "$f" | grep -oE '"[a-z]+"' | tr -d '"')"
    if [ -z "$flavours" ]; then
        wanted "$name" && run_suite "$name" ""
    else
        for fl in $flavours; do
            wanted "$name" && run_suite "$name" "$fl"
        done
    fi
done
wanted "lib/t" && run_suite "lib/t" ""

echo "the harness and the research tools"
if wanted "harness-skip"; then
    run_other "harness-skip" \
        "env -u ST_FLAVOUR '$ROOT/tools/run.sh' --flavour forever tools/costcheck.lua; rc=\$?; [ \$rc -eq 3 ] || { echo \"exit \$rc, not 3\"; exit 1; }" \
        '^skip: costcheck\.lua runs under tbc only$'
fi
wanted "reproduce-smoke" && run_other "reproduce-smoke" \
    "env -u ST_FLAVOUR '$ROOT/tools/run.sh' tools/reproduce.lua --fixture tools/data/practice/1790701698.lua" \
    '^ +casts executed +[0-9]+ +[0-9]+'
wanted "strategies-smoke" && run_other "strategies-smoke" \
    "env -u ST_FLAVOUR '$ROOT/tools/run.sh' tools/strategies.lua --fixture tools/data/practice/1790701698.lua" \
    '^ranked by the lexicographic tuple'

echo "python"
wanted "apicheck" && run_other "apicheck" "python3 '$ROOT/tools/apicheck.py'" ' 0 findings '
wanted "apicheck-selftest" && run_other "apicheck-selftest" "python3 '$ROOT/tools/apicheck.py' --selftest" \
    '^selftest: [0-9]+ of [0-9]+ findings as expected$' 's/^selftest: \([0-9]*\) of \1 findings as expected$/\1/p'
wanted "textcheck" && run_other "textcheck" "python3 '$ROOT/tools/textcheck.py'" ' 0 findings$'
wanted "textcheck-selftest" && run_other "textcheck-selftest" "python3 '$ROOT/tools/textcheck.py' --selftest" \
    '^selftest: [0-9]+ of [0-9]+ ok$' 's/^selftest: \([0-9]*\) of \1 ok$/\1/p'
wanted "refcheck-selftest" && run_other "refcheck-selftest" "python3 '$ROOT/tools/refcheck.py' --selftest" \
    '^selftest: [0-9]+ of [0-9]+ ok$' 's/^selftest: \([0-9]*\) of \1 ok$/\1/p'

# ---------------------------------------------------------------- the counts ---
echo "counts"
COUNT_OUT="$(python3 - "$RESULTS" "$COUNTS_FILE" "$ONLY" <<'PY'
import json, os, sys
results, path, only = sys.argv[1], sys.argv[2], sys.argv[3]
# a key is in scope when everything ran, or when --only named its suite
def in_scope(key):
    return only == "" or ("," + key.split("/")[0] + ",") in only or ("," + key + ",") in only
got = {}
with open(results) as f:
    for line in f:
        k, n = line.rstrip("\n").split("\t")
        got[k] = int(n)
if not os.path.isfile(path):
    print("NOTE no {} -- counts not compared (tools/check.sh --write-counts writes it)".format(path))
    sys.exit(0)
with open(path) as f:
    want = json.load(f)
bad = 0
for k in sorted(want):
    if k not in got:
        if in_scope(k):
            print("FAIL {}: expected {} assertion(s), and it did not run (or did not pass)".format(k, want[k]))
            bad += 1
    elif got[k] < want[k]:
        print("FAIL {}: {} assertion(s), expected {} -- a suite lost assertions".format(k, got[k], want[k]))
        bad += 1
    elif got[k] > want[k]:
        print("NOTE {}: {} assertion(s), {} expected -- update the expected counts".format(k, got[k], want[k]))
for k in sorted(got):
    if k not in want:
        print("NOTE {}: {} assertion(s), not in the expected counts".format(k, got[k]))
print("counted {} run(s) against {} expected".format(len(got), len(want)))
sys.exit(1 if bad else 0)
PY
)"
COUNT_RC=$?
echo "$COUNT_OUT" | sed 's/^/  /'
[ "$COUNT_RC" -eq 0 ] || FAILED+=("counts")

if [ ${#FAILED[@]} -eq 0 ] && [ "$WRITE_COUNTS" -eq 1 ]; then
    python3 - "$RESULTS" "$COUNTS_FILE" <<'PY'
import json, sys
got = {}
with open(sys.argv[1]) as f:
    for line in f:
        k, n = line.rstrip("\n").split("\t")
        got[k] = int(n)
with open(sys.argv[2], "w") as f:
    json.dump(got, f, indent=2, sort_keys=True)
    f.write("\n")
print("  wrote {} count(s) to {}".format(len(got), sys.argv[2]))
PY
elif [ "$WRITE_COUNTS" -eq 1 ]; then
    echo "  not writing the counts: the run did not pass"
fi

echo
if [ ${#FAILED[@]} -eq 0 ]; then
    echo "check: $RUNS run(s), all passed"
    exit 0
fi
echo "check: $RUNS run(s), ${#FAILED[@]} failed: ${FAILED[*]}"
exit 1
