#!/usr/bin/env bash
# Run a harness script against this checkout with a real Lua 5.1.
#
#   tools/run.sh [--flavour forever|tbc] tools/simcheck.lua [--curve]
#
# There is no Lua in this repo and none is assumed on the machine: the first
# run downloads and builds Lua 5.1.5 into tools/.lua (gitignored, ~10 seconds).
# 5.1 specifically, because that is what the TBC client runs.
#
# T57 (P13, review Q15): the tarball is the harness's trust root, so it is
# checked against lua.org's published SHA-256 before it is unpacked; a mismatch
# deletes it and stops. A script run under a flavour it does not declare exits
# 3 (tools/harness.lua), which tools/check.sh reads as a skip.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_DIR="$ROOT/tools/.lua"
LUA="$LUA_DIR/lua-5.1.5/src/lua"
# https://www.lua.org/ftp/ -- lua-5.1.5.tar.gz
LUA_SHA256="2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333"

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

if [ ! -x "$LUA" ]; then
    echo "building Lua 5.1.5 into tools/.lua ..." >&2
    mkdir -p "$LUA_DIR"
    curl -sSL -o "$LUA_DIR/lua.tar.gz" https://www.lua.org/ftp/lua-5.1.5.tar.gz
    got="$(sha256_of "$LUA_DIR/lua.tar.gz")"
    if [ "$got" != "$LUA_SHA256" ]; then
        rm -f "$LUA_DIR/lua.tar.gz"
        echo "tools/run.sh: lua-5.1.5.tar.gz has SHA-256 $got, expected $LUA_SHA256 - not unpacked" >&2
        exit 1
    fi
    ( cd "$LUA_DIR" && tar xzf lua.tar.gz && cd lua-5.1.5 && make posix >/dev/null 2>&1 )
fi

if [ "${1:-}" = "--flavour" ]; then
    case "${2:-}" in
        forever|tbc) ;;
        *) echo "usage: tools/run.sh [--flavour forever|tbc] <script.lua> [args]" >&2; exit 2 ;;
    esac
    export ST_FLAVOUR="$2"
    shift 2
fi

SCRIPT="${1:?usage: tools/run.sh [--flavour forever|tbc] <script.lua> [args]}"
shift
exec "$LUA" "$ROOT/${SCRIPT#./}" "$ROOT" "$@"
