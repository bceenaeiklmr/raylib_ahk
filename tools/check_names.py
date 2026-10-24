"""Report every RL.<name> used by a script that the generated wrapper does not define.

Catches invented or misspelled API names before a script is ever run.

  python tools/check_names.py [file ...]     (default: examples/*.ahk and tests/*.ahk)
"""
import glob
import io
import re
import sys

LIB = "lib/raylib.ahk"


def defined():
    """Members of class RL: methods, constants, colors, struct sizes and accessors."""
    text = io.open(LIB, encoding="utf-8-sig").read()
    names = set(re.findall(r"^\s*static\s+(\w+)\s*[(:=]", text, re.M))
    names |= {"Size"}            # <Struct>_Size is used through RL.<Struct>_Size
    return {n.lower() for n in names}


def used(path):
    text = io.open(path, encoding="utf-8-sig").read()
    # strip comment lines so a note in prose cannot look like a call
    text = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith(";"))
    return {n.lower() for n in re.findall(r"\bRL\.(\w+)", text)}


def main():
    args = sys.argv[1:] or sorted(glob.glob("examples/*.ahk") + glob.glob("tests/*.ahk"))
    have = defined()
    bad = 0
    for path in args:
        missing = sorted(used(path) - have)
        if missing:
            bad += len(missing)
            print("%s: %s" % (path, ", ".join(missing)))
    print("%d unknown name(s) across %d file(s)" % (bad, len(args)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
