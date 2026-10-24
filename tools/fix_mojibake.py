"""Repair text that was read as ANSI and written back as UTF-8, which turns every
non-ASCII character into mojibake: an em dash becomes a three-character mess, aHungarian
o-double-acute becomes an A-ring. Windows PowerShell 5.1's `Get-Content -Raw` without
-Encoding does exactly this, and `Set-Content -Encoding UTF8` then saves the damage.

  python tools/fix_mojibake.py [file ...]
    without arguments: every text file git tracks

This file stays pure ASCII on purpose: a checker whose own source contains the bytes it
hunts for reports itself as broken. Run tools/precheck.py to see whether anything is.
"""
import io
import os
import subprocess
import sys

# Escapes, never literals. Each is what a cp1252 or cp1250 reading of UTF-8 bytes for a
# common non-ASCII character looks like: em dash, curly quote, accent, a-ring, degree.
MARKS = ["\u00e2\u20ac", "\u00e2\u201a", "\u00c3\u00a2", "\u00c3\u00a9", "\u00c3\u00a8", "\u00c3\u00b6", "\u00c3\u00bc", "\u0178", "\u00c2"]

# The codepage that did the damage depends on the machine's ANSI locale.
CANDIDATES = ["cp1252", "cp1250", "latin-1"]


def looks_broken(text):
    return any(mark in text for mark in MARKS)


def repair(text):
    for codepage in CANDIDATES:
        try:
            fixed = text.encode(codepage).decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            continue
        # A real repair removes the markers; a lucky round trip does not.
        if fixed != text and not looks_broken(fixed):
            return fixed, codepage
    return None, None


def tracked_files():
    out = subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split()
    return [p.replace("\\", "/") for p in out]


def main():
    paths = sys.argv[1:] or tracked_files()
    changed = 0
    for path in paths:
        if not os.path.exists(path) or path.endswith((".dll", ".png", ".lib", ".obj")):
            continue
        with open(path, "rb") as handle:
            raw = handle.read()
        bom = raw.startswith(b"\xef\xbb\xbf")
        text = raw.decode("utf-8-sig", errors="replace")
        if not looks_broken(text):
            continue
        fixed, codepage = repair(text)
        if fixed is None:
            print("%s: has mojibake markers but no codepage round-trips cleanly" % path)
            continue
        io.open(path, "w", encoding="utf-8-sig" if bom else "utf-8", newline="").write(fixed)
        print("%s: repaired via %s (%d -> %d chars)" % (path, codepage, len(text), len(fixed)))
        changed += 1
    if not changed:
        print("no file needed repair")


if __name__ == "__main__":
    main()
