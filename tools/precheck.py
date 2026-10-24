"""Pre-publication checks: encodings a fresh clone would trip over, dead links, and
numbers the README quotes but the generator no longer prints.

  python tools/precheck.py
"""
import io
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

# Mojibake left behind when Windows PowerShell 5.1 reads UTF-8 as ANSI and writes it
# back as UTF-8. See tools/fix_mojibake.py.
# Escapes, not literals: a checker that contains the bytes it looks for flags itself.
MOJIBAKE = ["\u00e2\u20ac", "\u00c3\u00a2", "\u00c3\u00a9", "\u0178", "\u00c2"]

tracked = subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split()
problems = []

for path in tracked:
    if path.endswith((".dll", ".png")):
        continue
    with open(path, "rb") as handle:
        raw = handle.read()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        problems.append("%s: not valid UTF-8 (%s)" % (path, exc))
        continue

    # AutoHotkey only decodes a script as UTF-8 when it starts with a BOM; without one
    # every non-ASCII literal turns into mojibake at runtime, silently.
    if path.endswith(".ahk") and not raw.startswith(b"\xef\xbb\xbf"):
        if any(ord(c) > 126 for c in text):
            problems.append("%s: non-ASCII text without a UTF-8 BOM" % path)

    for mark in MOJIBAKE:
        if mark in text:
            problems.append("%s: mojibake (%s) - run tools/fix_mojibake.py" % (path, mark))
            break

    # Nothing should carry a local user's path.
    for number, line in enumerate(text.splitlines(), 1):
        if re.search(r"[A-Za-z]:[\\/]+[Uu]sers[\\/]+\w", line):
            problems.append("%s:%d: personal path: %s" % (path, number, line.strip()[:80]))

# Links in the README must resolve, or GitHub renders a 404 the local reader never sees.
readme = io.open("README.md", encoding="utf-8-sig").read()
for link in re.findall(r"\]\(([^)#][^)]*)\)", readme):
    if not link.startswith("http") and not os.path.exists(link.replace("\\", "/")):
        problems.append("README links to a missing file: %s" % link)

# The README quotes the generator's counts; regeneration must not leave them stale.
report = subprocess.run([sys.executable, "tools/gen_wrapper.py"], capture_output=True, text=True)
counts = {
    "bound": re.search(r"bound (\d+) of", report.stdout).group(1),
    "constants": re.search(r"constants (\d+)", report.stdout).group(1),
    "colours": re.search(r"colors (\d+)", report.stdout).group(1),
}
for phrase, want in [(r"\*\*(\d+) are bound\*\*", counts["bound"]),
                     (r"(\d+) constants", counts["constants"]),
                     (r"(\d+) colours", counts["colours"])]:
    for found in re.findall(phrase, readme):
        if found != want:
            problems.append("README says %s, generator says %s (%s)" % (found, want, phrase))

dirty = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout
if dirty.strip():
    print("uncommitted:\n" + dirty)

print("\n".join(problems) if problems else "precheck: clean")
sys.exit(1 if problems else 0)
