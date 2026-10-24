"""Compare the struct layout the generator computes in Python with the compiler's
own sizeof()/offsetof(), read straight out of the built shim.

  python tools/check_layout.py

Needs lib/raylib_ahk_shim.dll (tools/build_shim.ps1). Prints one line per struct
that disagrees; no output means the model and the compiler agree.
"""
import ctypes
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_wrapper as g  # noqa: E402

HEADER = os.path.join("vendor", "raylib.h")
SHIM = os.path.join("lib", "raylib_ahk_shim.dll")

text = open(HEADER, encoding="utf-8", errors="replace").read()
structs = g.parse_structs(text)
layout = g.Layout(structs, g.parse_aliases(text))

if hasattr(os, "add_dll_directory"):
    os.add_dll_directory(os.path.abspath("lib"))
shim = ctypes.CDLL(SHIM)

names = [n for n in sorted(structs) if hasattr(shim, "rla_layout_%s" % n)]
bad = 0
for name in names:
    want = [layout.size(name)] + [it["off"] for it in g.flat_fields(layout, name)]
    got = (ctypes.c_uint * len(want))()
    getattr(shim, "rla_layout_%s" % name)(got)
    if list(got) != want:
        bad += 1
        labels = ["size"] + [it["name"] for it in g.flat_fields(layout, name)]
        diff = ", ".join("%s python=%d compiler=%d" % (a, b, c)
                         for a, b, c in zip(labels, want, got) if b != c)
        print("%-18s %s" % (name, diff))
if not bad:
    print("%d structs: python model matches the compiler" % len(names))
sys.exit(1 if bad else 0)
