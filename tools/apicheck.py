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
  8. an event handler's argument compared, used in arithmetic, indexed,
     measured with `#`, or type()-tested before the same function has asked
     IsSecret about it (outside Client/, from the handler's own source text --
     see docs/tasks/T13a-secret-arg-check.md). Known limits: a parameter
     passed on to another function and compared there is not followed; an
     alias (`local u = unit`) is not followed; a check in a branch that does
     not dominate the use still counts as a check.

A Forever TOC is one that loads a forever marker file of tools/data/flavours.txt,
or sits under Modules/, or (with neither) whose interface is in forever's band
(T47, docs/tasks/T47-launch-safety.md).

See docs/tasks/T6-apicheck.md for the full rule text (rules 1-7) and
docs/tasks/T13a-secret-arg-check.md for rule 8.
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


class Rule8Finding(Finding):
    """rule 8: <file>:<line> <param> used before IsSecret in the <EVENT> handler"""

    def __init__(self, path, line, param, event):
        reason = "used before IsSecret in the {} handler".format(event)
        Finding.__init__(self, path, line, param, reason)

    def render(self):
        return "rule 8: {}:{} {} {}".format(self.path, self.line, self.name, self.reason)


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


FLAVOURS_FILE = os.path.join(HERE, "data", "flavours.txt")


def load_flavours(path=FLAVOURS_FILE):
    """tools/data/flavours.txt (T47): [(name, {marker files}, lo, hi)] -- the
    table release.sh and tools/releasecheck.lua classify TOCs by, and
    Client/API.lua's MD.API.BANDS / MD.API.MARKERS must equal."""
    flavours = []
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            m = re.match(r"^(\S+)\s+(\S+)\s+(\d+)-(\d+)$", line)
            if not m:
                raise ValueError("{}: cannot read '{}'".format(path, line))
            flavours.append((m.group(1), set(m.group(2).split(",")), int(m.group(3)), int(m.group(4))))
    return flavours


def toc_flavour(path, root, flavours):
    """The marker file a TOC loads decides; a TOC under Modules/ is forever;
    the interface band only for a TOC with neither (T47)."""
    for _, relfile in toc_entries(path):
        for name, markers, _, _ in flavours:
            if relfile in markers:
                return name
    modules_dir = os.path.abspath(os.path.join(root, "Modules"))
    toc_dir = os.path.abspath(os.path.dirname(path))
    if os.path.commonpath([toc_dir, modules_dir]) == modules_dir:
        return "forever"
    nums = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\r\n")
            if line.lower().startswith("## interface:"):
                nums = [int(n) for n in re.findall(r"\d+", line.split(":", 1)[1])]
                break
    for name, _, lo, hi in flavours:
        if nums and all(lo <= n <= hi for n in nums):
            return name
    return None


def is_forever_toc(path, root, flavours):
    return toc_flavour(path, root, flavours) == "forever"


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


# ---------------------------------------------------------------------------
# Rule 8: an event handler's argument used riskily before IsSecret asks about
# it. Source text only (T13a) -- a secret's own shape does not survive to
# luac's listing the way a plain global name does.
# ---------------------------------------------------------------------------

HANDLER_INLINE_RE = re.compile(
    r'MD:On\(\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*,\s*function\s*\(([^)]*)\)'
)
HANDLER_NAMED_RE = re.compile(
    r'MD:On\(\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)'
)

BLOCK_TOKEN_RE = re.compile(r'\b(function|if|do|repeat|until|end)\b')
CHECK_CALL_RE = re.compile(r'([A-Za-z_][A-Za-z0-9_.:]*IsSecret)\s*\(([^)]*)\)')

RISKY_PATTERNS_TMPL = [
    r'\b{p}\b\s*(?:==|~=|<=|>=|<|>)',
    r'(?:==|~=|<=|>=|<|>)\s*\b{p}\b',
    r'\b{p}\b\s*[-+*/%^]',
    r'[-+*/%^]\s*\b{p}\b',
    r'#\s*\b{p}\b',
    r'\b{p}\b\s*\[',
    r'\b{p}\b\s*\.\s*[A-Za-z_]',
    r'\b{p}\b\s*:',
    r'\b{p}\b\s*\(',
    r'\btype\s*\(\s*{p}\b\s*\)',
]


def _blank(segment):
    return ''.join('\n' if ch == '\n' else ' ' for ch in segment)


def _strip(text, strip_strings):
    """Blank out comments (and, if strip_strings, string literals too),
    character-for-character -- same length, newlines kept in place -- so
    offsets still line up with the raw source for line numbers."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if text.startswith("--", i):
            j = i + 2
            long_end = None
            if j < n and text[j] == '[':
                k = j + 1
                eq = 0
                while k < n and text[k] == '=':
                    eq += 1
                    k += 1
                if k < n and text[k] == '[':
                    close = ']' + '=' * eq + ']'
                    found = text.find(close, k + 1)
                    long_end = (found + len(close)) if found != -1 else n
            if long_end is None:
                long_end = text.find('\n', i)
                if long_end == -1:
                    long_end = n
            out.append(_blank(text[i:long_end]))
            i = long_end
            continue
        if strip_strings and c in ('"', "'"):
            quote = c
            j = i + 1
            while j < n and text[j] != quote:
                if text[j] == '\\' and j + 1 < n:
                    j += 2
                else:
                    j += 1
            j = min(j + 1, n)
            out.append(_blank(text[i:j]))
            i = j
            continue
        if strip_strings and c == '[':
            k = i + 1
            eq = 0
            while k < n and text[k] == '=':
                eq += 1
                k += 1
            if k < n and text[k] == '[':
                close = ']' + '=' * eq + ']'
                found = text.find(close, k + 1)
                end = (found + len(close)) if found != -1 else n
                out.append(_blank(text[i:end]))
                i = end
                continue
        out.append(c)
        i += 1
    return ''.join(out)


def strip_comments(text):
    return _strip(text, strip_strings=False)


def strip_source(text):
    return _strip(text, strip_strings=True)


def find_block_end(stripped, body_start):
    """Position of the `end` (or the `until` its `repeat` closes) that ends
    the block opened at body_start (the handler function itself already
    counted as open)."""
    stack = ["function"]
    for m in BLOCK_TOKEN_RE.finditer(stripped, body_start):
        tok = m.group(1)
        if tok in ("function", "if", "do", "repeat"):
            stack.append(tok)
        elif tok == "end":
            if stack and stack[-1] != "repeat":
                stack.pop()
        elif tok == "until":
            if stack and stack[-1] == "repeat":
                stack.pop()
        if not stack:
            return m.start()
    return len(stripped)


def param_names(paramlist):
    names = []
    for p in paramlist.split(","):
        p = p.strip()
        if p and p not in ("_", "self", "..."):
            names.append(p)
    return names


def check_positions(body, param):
    positions = []
    for m in CHECK_CALL_RE.finditer(body):
        args = [a.strip() for a in m.group(2).split(",")]
        if param in args:
            positions.append(m.start())
    return positions


def first_risky_use(body, param):
    p = re.escape(param)
    best = None
    for tmpl in RISKY_PATTERNS_TMPL:
        m = re.compile(tmpl.format(p=p)).search(body)
        if m and (best is None or m.start() < best):
            best = m.start()
    return best


def line_of(text, pos):
    return text.count('\n', 0, pos) + 1


def rule8_findings_for_body(relpath, stripped_file, body_start, body_end, event, params):
    findings = []
    body = stripped_file[body_start:body_end]
    for param in params:
        use_pos = first_risky_use(body, param)
        if use_pos is None:
            continue
        if any(cp < use_pos for cp in check_positions(body, param)):
            continue
        line = line_of(stripped_file, body_start + use_pos)
        findings.append(Rule8Finding(relpath, line, param, event))
    return findings


def scan_rule8(abspath, relpath):
    if under_client_dir(relpath):
        return []
    with open(abspath, "r", encoding="utf-8", errors="replace") as f:
        raw = f.read()
    no_comments = strip_comments(raw)   # for locating handlers -- strings intact
    stripped = strip_source(raw)        # for body scanning -- strings blanked too
    findings = []

    for m in HANDLER_INLINE_RE.finditer(no_comments):
        event = m.group(1)
        params = param_names(m.group(2))
        if not params:
            continue
        body_start = m.end()
        body_end = find_block_end(stripped, body_start)
        findings.extend(rule8_findings_for_body(relpath, stripped, body_start, body_end, event, params))

    for m in HANDLER_NAMED_RE.finditer(no_comments):
        event, fname = m.group(1), m.group(2)
        dm = re.search(r'\blocal\s+function\s+' + re.escape(fname) + r'\s*\(([^)]*)\)', no_comments)
        if not dm:
            continue  # not a same-file local function -- out of scope (Facts)
        params = param_names(dm.group(1))
        if not params:
            continue
        body_start = dm.end()
        body_end = find_block_end(stripped, body_start)
        findings.extend(rule8_findings_for_body(relpath, stripped, body_start, body_end, event, params))

    return findings


def collect(root, baseline):
    """Returns (forever_tocs, checked_files[abspath,relpath], findings, globals_seen, per_file_globals)."""
    all_tocs = find_tocs(root)
    flavours = load_flavours()
    forever_tocs = [t for t in all_tocs if is_forever_toc(t, root, flavours)]

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
        findings.extend(scan_rule8(abspath, relpath))

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
        # rule 8: Handlers.lua's two bad handlers use their param before
        # IsSecret ever asks about it (T13a); the two good ones raise nothing.
        expected.append(("Handlers.lua", 21, "unit", "used before IsSecret in the UNIT_HEALTH_BAD handler"))
        expected.append(("Handlers.lua", 27, "unit", "used before IsSecret in the UNIT_AURA_BAD handler"))
        # rule 7: Gone.lua is missing, referenced from the fixture TOC.
        toc_rel = None
        for t in forever_tocs:
            if os.path.basename(t) == "Fixture_Mainline.toc":
                toc_rel = to_posix(os.path.relpath(t, root))
        expected.append((toc_rel, 7, "Gone.lua", "missing file"))
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
