"""Repair text that was read as ANSI and written back as UTF-8, which turns every
non-ASCII character into mojibake ("--" becomes "â€""). PowerShell 5.1's
`Get-Content -Raw` without -Encoding does exactly this.

  python tools/fix_mojibake.py [file ...]     (default: the markdown and text files)
"""
import io
import sys

# Escapes, so this file stays ASCII and is not itself a match.
MARKS = ["\u00e2\u20ac", "\u00c3\u00a2", "\u00c3\u00a9", "\u0178", "\u00c2"]


def looks_broken(text):
    return any(mark in text for mark in MARKS)


def repair(text):
    # the bytes were decoded as cp1252, so encoding them back recovers the UTF-8
    return text.encode("cp1252", errors="strict").decode("utf-8", errors="strict")


def main():
    paths = sys.argv[1:] or ["README.md", ".gitignore", ".gitattributes", "tools/skipped.txt"]
    for path in paths:
        raw = open(path, "rb").read()
        bom = raw.startswith(b"\xef\xbb\xbf")
        text = raw.decode("utf-8-sig")
        if not looks_broken(text):
            print("%s: clean" % path)
            continue
        try:
            fixed = repair(text)
        except (UnicodeEncodeError, UnicodeDecodeError) as exc:
            print("%s: looks broken but not repairable automatically (%s)" % (path, exc))
            continue
        io.open(path, "w", encoding="utf-8-sig" if bom else "utf-8", newline="").write(fixed)
        print("%s: repaired (%d -> %d chars)" % (path, len(text), len(fixed)))


if __name__ == "__main__":
    main()
