#!/usr/bin/env python3
"""tools/textcheck.py [--root DIR] [--luac FILE] [--selftest]

One text rule (T47, docs/tasks/T47-launch-safety.md): rendered text is ASCII.
No string constant in a shipped file may carry a byte above 127 -- a WoW font
without the glyph draws a box, and a pasted report carries multibyte bytes.

"Shipped" is every file any TOC in the tree loads (all nine: the TBC TOC, the
two Forever TOCs and each module's two), a module entry under Engine/, Spells/,
Data/ or UI/ resolved at the repository root as release.sh does. Its own tool
rather than an apicheck rule because it covers the TBC TOC too, and apicheck
covers the Forever TOCs against the Forever baseline.

The constants are read out of `luac -l -l -p`'s own listing (never guessed from
source text), so a comment is never a finding and an escape written in the
source ("\\226\\128\\148") is one. Each finding names the line of the
instruction that uses the constant.

The other half of the rule -- never a bare pipe -- is not mechanised: `|c`,
`|r` and `|T` are legitimate escapes, so a bare pipe is a reading question.

--selftest reads tools/data/textcheck-fixture.lua (an em dash in a call, a
table store, a source escape, a comparison and a long string; a comment with an
em dash and an ASCII line with an escaped backslash that are not findings).
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKOUT_ROOT = os.path.dirname(HERE)

EXCLUDE_DIRS = {"tools", "dist", ".git", ".claude", "docs"}
MODULE_ROOT_PREFIXES = ("Engine/", "Spells/", "Data/", "UI/")

FIXTURE = os.path.join(HERE, "data", "textcheck-fixture.lua")
# (line, what) in the fixture: the five sites the selftest must find, and no other.
FIXTURE_EXPECTED = {4, 5, 6, 8, 9}

FUNC_RE = re.compile(r"^(?:main|function) <[^>]*:(\d+),(\d+)> ")
INSTR_RE = re.compile(r"^\t\d+\t\[(\d+)\]\t\S+\s*\t[^\t]*(?:\t; (.*))?$")
CONSTS_RE = re.compile(r"^constants \(\d+\) for ")
CONST_RE = re.compile(r"^\t\d+\t(\".*\")$")
SECTION_RE = re.compile(r"^(?:locals|upvalues) \(\d+\) for ")
QUOTED_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')


def decode(body):
    """luac's printed string body -> its bytes (luac escapes \\" \\\\ \\a..\\v and
    any unprintable byte as \\ddd)."""
    out = bytearray()
    i = 0
    simple = {"a": 7, "b": 8, "f": 12, "n": 10, "r": 13, "t": 9, "v": 11, '"': 34, "\\": 92}
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            d = body[i + 1]
            m = re.match(r"\d{1,3}", body[i + 1:])
            if m:
                out.append(int(m.group(0)) & 0xFF)
                i += 1 + len(m.group(0))
                continue
            out.append(simple.get(d, ord(d)))
            i += 2
            continue
        out.extend(c.encode("latin-1", "replace"))
        i += 1
    return bytes(out)


def show(data):
    """ASCII rendering of a finding's constant, the high bytes as \\ddd."""
    text = "".join(chr(b) if 32 <= b < 127 else "\\{:03d}".format(b) for b in data)
    return text if len(text) <= 70 else text[:67] + "..."


def scan(luac, abspath, relpath):
    """[(relpath, line, excerpt)] for every string constant with a byte > 127."""
    proc = subprocess.run([luac, "-l", "-l", "-p", abspath], capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError("luac failed on {}: {}".format(relpath, proc.stderr.decode("latin-1").strip()))
    listing = proc.stdout.decode("latin-1")
    findings = set()
    func_line = 0
    uses = {}          # printed literal -> [lines] within the current function
    in_consts = False
    for raw in listing.splitlines():
        fm = FUNC_RE.match(raw)
        if fm:
            func_line, uses, in_consts = int(fm.group(1)), {}, False
            continue
        if CONSTS_RE.match(raw):
            in_consts = True
            continue
        if SECTION_RE.match(raw):
            in_consts = False
            continue
        if in_consts:
            cm = CONST_RE.match(raw)
            if cm:
                literal = cm.group(1)
                data = decode(literal[1:-1])
                if any(b > 127 for b in data):
                    lines = uses.get(literal) or [func_line]
                    for line in lines:
                        findings.add((relpath, line, show(data)))
            continue
        im = INSTR_RE.match(raw)
        if im and im.group(2):
            for q in QUOTED_RE.finditer(im.group(2)):
                uses.setdefault('"' + q.group(1) + '"', []).append(int(im.group(1)))
    return sorted(findings)


def find_tocs(root):
    result = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for fn in filenames:
            if fn.endswith(".toc"):
                result.append(os.path.join(dirpath, fn))
    return sorted(result)


def shipped_files(root):
    """[(abspath, relpath)] every .lua file some TOC loads, once; plus missing entries."""
    files, missing, seen = [], [], set()
    modules_dir = os.path.abspath(os.path.join(root, "Modules"))
    tocs = find_tocs(root)
    for toc in tocs:
        toc_dir = os.path.dirname(toc)
        is_module = os.path.commonpath([os.path.abspath(toc_dir), modules_dir]) == modules_dir
        with open(toc, "r", encoding="utf-8", errors="replace") as f:
            for raw in f:
                entry = raw.strip().replace("\\", "/")
                if not entry or entry.startswith("#"):
                    continue
                abspath = os.path.normpath(os.path.join(toc_dir, entry))
                if not os.path.isfile(abspath) and is_module and entry.startswith(MODULE_ROOT_PREFIXES):
                    abspath = os.path.normpath(os.path.join(root, entry))
                if not os.path.isfile(abspath):
                    missing.append((os.path.relpath(toc, root).replace(os.sep, "/"), entry))
                    continue
                if abspath.endswith(".lua") and abspath not in seen:
                    seen.add(abspath)
                    files.append((abspath, os.path.relpath(abspath, root).replace(os.sep, "/")))
    return tocs, files, missing


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--root", default=CHECKOUT_ROOT)
    ap.add_argument("--luac", default=os.path.join(CHECKOUT_ROOT, "tools", ".lua", "lua-5.1.5", "src", "luac"))
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if not os.path.isfile(args.luac):
        print("textcheck: no luac at {} - run any suite once with tools/run.sh to build it".format(args.luac))
        return 2

    if args.selftest:
        found = scan(args.luac, FIXTURE, "tools/data/textcheck-fixture.lua")
        for rel, line, text in found:
            print("FAIL {}:{} \"{}\"".format(rel, line, text))
        lines = {line for _, line, _ in found}
        checks = [
            ("every non-ASCII constant in the fixture is found at its line", FIXTURE_EXPECTED <= lines,
             sorted(FIXTURE_EXPECTED - lines)),
            ("nothing else is found (a comment, an escaped backslash)", lines <= FIXTURE_EXPECTED,
             sorted(lines - FIXTURE_EXPECTED)),
        ]
        ok = 0
        for name, cond, detail in checks:
            print("{:<66} {}{}".format(name, "ok" if cond else "FAIL", "" if cond else " - lines {}".format(detail)))
            ok += 1 if cond else 0
        print("selftest: {} of {} ok".format(ok, len(checks)))
        return 0 if ok == len(checks) else 1

    root = os.path.abspath(args.root)
    tocs, files, missing = shipped_files(root)
    findings = []
    for abspath, relpath in files:
        findings.extend(scan(args.luac, abspath, relpath))
    for toc, entry in missing:
        print("FAIL {}: {} missing file".format(toc, entry))
    for rel, line, text in findings:
        print("FAIL {}:{} \"{}\"".format(rel, line, text))
    n = len(findings) + len(missing)
    print("textcheck: {} TOCs, {} files, {} findings".format(len(tocs), len(files), n))
    return 0 if n == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
