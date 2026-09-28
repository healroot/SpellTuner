#!/usr/bin/env python3
"""tools/apicheck.py [--root DIR] [--baseline FILE] [--luac FILE] [--report] [--selftest]

Every global the Forever TOCs' files read or write, read out of `luac -l -p`'s
own listing (never guessed from source text) and checked against the build's
API baseline and the adapter rule (CLAUDE.md / docs/FOREVER-PLAN.md):

  1. a name the build does not have                       -- unknown
  2. WoW's Lua does not have os/io/require/...             -- not-in-client
  3. a client call (present in the baseline) outside Client/
  4. a new global (a SETGLOBAL of a name that is not ours)
  5. the COMBAT_LOG_EVENT_UNFILTERED constant anywhere but Client/API_Forever.lua
  6. a "C_Namespace.Member" string whose namespace/member the baseline lacks,
     outside Client/Probe.lua (which names absent members as strings on purpose)
  7. a TOC entry with no file on disk

See docs/tasks/T6-apicheck.md for the full rule text.
"""
import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKOUT_ROOT = os.path.dirname(HERE)

EXCLUDE_DIRS = {"tools", "dist", ".git", ".claude", "docs"}

# Lua 5.1's own base names that WoW keeps.
LUA_BASE = {
    "_G", "assert", "error", "getmetatable", "setmetatable", "ipairs", "pairs",
    "next", "pcall", "xpcall", "rawequal", "rawget", "rawset", "select",
    "tonumber", "tostring", "type", "unpack", "getfenv", "setfenv",
    "loadstring", "collectgarbage", "gcinfo", "print", "math", "string",
    "table", "coroutine",
}

# This addon's own globals -- the only names a Forever file may assign.
OURS = {
    "SpellTuner", "SpellTunerDB", "ManaDemonDB", "SPELLTUNER_TOC",
    "SLASH_SPELLTUNER1", "SLASH_SPELLTUNER2", "SLASH_SPELLTUNER3",
}

# Lua extensions WoW ships, allowed in any file (each must be in the
# baseline's `functions`).
LUA_EXTENSIONS = {
    "wipe", "tinsert", "tremove", "strsplit", "strtrim", "strjoin", "format",
    "date", "time", "GetTime", "debugprofilestop",
}

# The widget toolkit, allowed in any file. Some of these are not captured by
# the baseline (tables/strings, not functions) -- --report says so, nothing
# fails for it.
TOOLKIT = {
    "CreateFrame", "CreateFont", "UIParent", "GameTooltip", "GameFontNormal",
    "GameFontNormalSmall", "GameFontHighlightSmall", "Minimap",
    "UISpecialFrames", "RAID_CLASS_COLORS", "SOUNDKIT", "PlaySound",
    "GetCursorPosition", "Mixin", "BackdropTemplateMixin", "SlashCmdList",
    "STANDARD_TEXT_FONT",
}

# WoW's Lua does not have these (lead, 2026-09-28).
NOT_IN_CLIENT = {"os", "io", "require", "dofile", "loadfile", "package", "module", "debug"}

# T13c: the same four shared folders release.sh (and the stub) resolve a
# missing module TOC entry against, at the repository root.
MODULE_ROOT_PREFIXES = ("Engine/", "Spells/", "Data/", "UI/")

FORBIDDEN_EVENT = "COMBAT_LOG_EVENT_UNFILTERED"
FORBIDDEN_EVENT_HOME = "Client/API_Forever.lua"
PROBE_FILE = "Client/Probe.lua"

C_MEMBER_RE = re.compile(r"^(C_[A-Za-z0-9_]+)\.([A-Za-z0-9_]+)$")

INSTR_RE = re.compile(r"^\t\d+\t\[(\d+)\]\t(\S+)\s*\t([^\t]*)(?:\t; (.*))?$")


class Finding:
    __slots__ = ("path", "line", "name", "reason")

    def __init__(self, path, line, name, reason):
        self.path = path
        self.line = line
        self.name = name
        self.reason = reason

    def key(self):
        return (self.path, self.line, self.name, self.reason)

    def render(self):
        return "FAIL {}:{} {} {}".format(self.path, self.line, self.name, self.reason)


def to_posix(path):
    return path.replace("\\", "/")


def load_baseline(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def find_tocs(root):
    result = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for fn in filenames:
            if fn.endswith(".toc"):
                result.append(os.path.join(dirpath, fn))
    return sorted(result)


def is_forever_toc(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\r\n")
            if line.lower().startswith("## interface:"):
                nums = re.findall(r"\d+", line.split(":", 1)[1])
                for n in nums:
                    if 16000 <= int(n) <= 19999:
                        return True
    return False


def toc_entries(path):
    """[(lineno, relfile)] -- CR stripped, blank/# lines skipped, \\ -> /."""
    entries = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for i, raw in enumerate(f, start=1):
            line = raw.rstrip("\r\n").strip()
            if not line or line.startswith("#"):
                continue
            entries.append((i, to_posix(line)))
    return entries


def classify(name):
    if name in LUA_BASE:
        return "lua"
    if name in OURS:
        return "ours"
    if name in LUA_EXTENSIONS:
        return "lua-extension"
    if name in TOOLKIT:
        return "toolkit"
    if name in NOT_IN_CLIENT:
        return "not-in-client"
    return None  # caller checks the baseline next


def classify_with_baseline(name, baseline):
    cls = classify(name)
    if cls is not None:
        return cls
    if name in baseline["functions"] or name in baseline["frames"] or name in baseline["namespaces"]:
        return "client"
    return "unknown"


def under_client_dir(relpath):
    parts = relpath.split("/")
    return "Client" in parts[:-1]


def run_luac(luac, filepath):
    proc = subprocess.run([luac, "-l", "-p", filepath], capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError("luac failed on {}: {}".format(filepath, proc.stderr.strip()))
    return proc.stdout


def scan_file(luac, abspath, relpath, baseline, globals_seen, per_file_globals):
    findings = []
    listing = run_luac(luac, abspath)
    build = baseline["client"]["build"]
    for raw in listing.splitlines():
        m = INSTR_RE.match(raw)
        if not m:
            continue
        line = int(m.group(1))
        op = m.group(2)
        comment = m.group(4)
        if op == "GETGLOBAL" and comment is not None:
            name = comment
            cls = classify_with_baseline(name, baseline)
            globals_seen.add(name)
            per_file_globals.setdefault(relpath, {})[name] = cls
            if cls == "unknown":
                findings.append(Finding(relpath, line, name, "not in baseline {}".format(build)))
            elif cls == "not-in-client":
                findings.append(Finding(relpath, line, name, "not in the client's Lua"))
            elif cls == "client" and not under_client_dir(relpath):
                findings.append(Finding(relpath, line, name, "client call outside Client/"))
        elif op == "SETGLOBAL" and comment is not None:
            name = comment
            cls = classify_with_baseline(name, baseline)
            globals_seen.add(name)
            per_file_globals.setdefault(relpath, {})[name] = cls
            if name not in OURS:
                findings.append(Finding(relpath, line, name, "new global"))
        elif op == "LOADK" and comment is not None and len(comment) >= 2 and comment[0] == '"' and comment[-1] == '"':
            value = comment[1:-1]
            if value == FORBIDDEN_EVENT and relpath != FORBIDDEN_EVENT_HOME:
                findings.append(Finding(relpath, line, value, "{} named".format(FORBIDDEN_EVENT)))
            else:
                cm = C_MEMBER_RE.match(value)
                if cm and relpath != PROBE_FILE:
                    ns, member = cm.group(1), cm.group(2)
                    members = baseline["namespaces"].get(ns)
                    if members is None or member not in members:
                        findings.append(Finding(relpath, line, value, "C_ member not in baseline {}".format(build)))
    return findings


def collect(root, baseline):
    """Returns (forever_tocs, checked_files[abspath,relpath], findings, globals_seen, per_file_globals)."""
    all_tocs = find_tocs(root)
    forever_tocs = [t for t in all_tocs if is_forever_toc(t)]

    findings = []
    checked = []  # (abspath, relpath)
    seen_abs = set()

    modules_dir = os.path.join(root, "Modules")

    for toc in forever_tocs:
        toc_rel = to_posix(os.path.relpath(toc, root))
        toc_dir = os.path.dirname(toc)
        is_module_toc = os.path.commonpath([os.path.abspath(toc_dir), os.path.abspath(modules_dir)]) == os.path.abspath(modules_dir)
        for lineno, relfile in toc_entries(toc):
            abspath = os.path.normpath(os.path.join(toc_dir, relfile))
            if not os.path.isfile(abspath) and is_module_toc and relfile.startswith(MODULE_ROOT_PREFIXES):
                # T13c: an entry not under the module's own folder is a shared
                # file resolved at the repository root -- the same rule
                # release.sh and tools/wowstub.lua follow.
                root_abspath = os.path.normpath(os.path.join(root, relfile))
                if os.path.isfile(root_abspath):
                    abspath = root_abspath
            if not os.path.isfile(abspath):
                findings.append(Finding(toc_rel, lineno, relfile, "missing file"))
                continue
            if abspath not in seen_abs:
                seen_abs.add(abspath)
                relpath = to_posix(os.path.relpath(abspath, root))
                checked.append((abspath, relpath))

    return forever_tocs, checked, findings


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--root", default=CHECKOUT_ROOT)
    ap.add_argument("--baseline", default=os.path.join(CHECKOUT_ROOT, "tools", "data", "forever_api.json"))
    ap.add_argument("--luac", default=os.path.join(CHECKOUT_ROOT, "tools", ".lua", "lua-5.1.5", "src", "luac"))
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if not os.path.isfile(args.luac):
        print("apicheck: no luac at {} - run any suite once with tools/run.sh to build it".format(args.luac))
        return 2

    baseline = load_baseline(args.baseline)
    build = baseline["client"]["build"]

    root = args.root
    if args.selftest:
        root = os.path.join(CHECKOUT_ROOT, "tools", "data", "apicheck-fixture")

    root = os.path.abspath(root)

    forever_tocs, checked, findings = collect(root, baseline)

    globals_seen = set()
    per_file_globals = {}
    for abspath, relpath in checked:
        findings.extend(scan_file(args.luac, abspath, relpath, baseline, globals_seen, per_file_globals))

    findings.sort(key=lambda f: f.key())

    if args.report:
        for relpath in sorted(per_file_globals.keys()):
            print("{}:".format(relpath))
            for name in sorted(per_file_globals[relpath].keys()):
                print("  {} {}".format(name, per_file_globals[relpath][name]))

    for f in findings:
        print(f.render())

    if args.selftest:
        expected = [
            ("Bad.lua", 1, "GetSpellInfo", "not in baseline {}".format(build)),
            ("Bad.lua", 2, "os", "not in the client's Lua"),
            ("Bad.lua", 3, "UnitHealth", "client call outside Client/"),
            ("Bad.lua", 4, "NewGlobalName", "new global"),
            ("Bad.lua", 5, "COMBAT_LOG_EVENT_UNFILTERED", "{} named".format(FORBIDDEN_EVENT)),
            ("Bad.lua", 6, "C_Spell.NoSuchMember", "C_ member not in baseline {}".format(build)),
        ]
        # rule 7: Gone.lua is missing, referenced from the fixture TOC.
        toc_rel = None
        for t in forever_tocs:
            if os.path.basename(t) == "Fixture_Mainline.toc":
                toc_rel = to_posix(os.path.relpath(t, root))
        expected.append((toc_rel, 6, "Gone.lua", "missing file"))
        # T13c: Modules/Sample/Sample_Mainline.toc lists Engine\Ok.lua (not
        # under Modules/Sample/, resolves at the fixture root -- zero findings
        # of its own, proving the resolution) and Missing.lua (nowhere at
        # all -- still the existing "missing file" error, line 7).
        sample_toc_rel = None
        for t in forever_tocs:
            if os.path.basename(t) == "Sample_Mainline.toc":
                sample_toc_rel = to_posix(os.path.relpath(t, root))
        expected.append((sample_toc_rel, 7, "Missing.lua", "missing file"))
        expected_keys = sorted(expected)
        actual_keys = sorted(f.key() for f in findings)
        ok = expected_keys == actual_keys
        n = len(expected)
        if ok:
            print("selftest: {} of {} findings as expected".format(n, n))
            return 0
        else:
            print("selftest: FAILED")
            print("expected: {}".format(expected_keys))
            print("actual:   {}".format(actual_keys))
            return 1

    G = len(globals_seen)
    T = len(forever_tocs)
    F = len(checked)
    N = len(findings)
    print("apicheck: {} Forever TOCs, {} files, {} distinct globals, {} findings (baseline {})".format(
        T, F, G, N, build))
    return 0 if N == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
