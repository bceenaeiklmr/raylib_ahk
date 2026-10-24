"""Check every RL.<Function>( call against the arity the generated wrapper declares.

A wrong argument count is a runtime error in AutoHotkey: no dialog is suppressed by
/ErrorStdOut (that switch only redirects script-load errors), so a headless run of the
offending script shows a modal dialog on someone's desktop and reports exit code 0. A
mistake like that can pass a verification chain silently and land in documentation.

This catches it statically: read the signatures out of lib/raylib.ahk, read the calls out
of the demos, the tests and the README's own code blocks, and compare.

  python tools/check_calls.py [file ...]
    without arguments: examples/*.ahk, tests/*.ahk and README.md
"""
import glob
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib", "raylib.ahk")


def signatures():
    """name -> (required, total), where a '?' or '*' parameter makes the count open ended.

    The generator wraps long parameter lists over several lines, so a signature is found by
    scanning from 'static Name(' to its matching ')' rather than by reading one line.
    """
    with io.open(LIB, encoding="utf-8-sig") as handle:
        text = handle.read()
    sigs = {}
    for match in re.finditer(r"\bstatic\s+(\w+)\(", text):
        name = match.group(1)
        end = match.end() - 1
        depth = 0
        index = end
        while index < len(text):
            char = text[index]
            if char in "([{":
                depth += 1
            elif char in ")]}":
                depth -= 1
                if depth == 0:
                    break
            elif char in "\"'":                       # a default may contain brackets
                quote = char
                index += 1
                while index < len(text) and text[index] != quote:
                    index += 1
            index += 1
        params = text[end + 1:index].replace("\n", " ").strip()
        params = re.sub(r"\s+", " ", params)
        if not params:
            sigs[name] = (0, 0)
            continue
        parts, depth, current = [], 0, ""
        for char in params:
            if char in "([{":
                depth += 1
            elif char in ")]}":
                depth -= 1
            if char == "," and depth == 0:
                parts.append(current)
                current = ""
            else:
                current += char
        parts.append(current)
        parts = [p for p in parts if p.strip()]
        total = len(parts)
        if parts[-1].strip().endswith("*"):           # variadic: any number above the rest
            sigs[name] = (total - 1, 1000)
            continue
        required = len([p for p in parts if ":=" not in p])
        sigs[name] = (required, total)
    return sigs


def count_arguments(text, open_index):
    """Arguments of the call whose '(' is at open_index, quote and depth aware.

    Scanning starts after the opening paren, so the paren itself is never mistaken for the
    first argument - which would report every CloseWindow() as taking one.
    """
    depth, quote, commas, seen = 1, None, 0, False
    index = open_index + 1
    while index < len(text):
        char = text[index]
        if quote:
            if char == quote:
                quote = None
            elif depth == 1:
                seen = True                           # a string is still an argument
        elif char in "\"'":
            quote = char
            if depth == 1:
                seen = True
        elif char in "([{":
            depth += 1
            seen = True
        elif char in ")]}":
            depth -= 1
            if depth == 0:
                return commas + 1 if seen else 0
        elif char == "," and depth == 1:
            commas += 1
            seen = True
        elif char not in " \t\r\n" and depth == 1:
            seen = True
        index += 1
    return None            # unbalanced: not our business here


def check(path, sigs):
    with io.open(path, encoding="utf-8-sig") as handle:
        text = handle.read()
    problems = []
    calls = 0
    for match in re.finditer(r"\bRL\.(\w+)\(", text):
        name = match.group(1)
        line = text.count("\n", 0, match.start()) + 1
        before = text[:match.start()].rstrip("\n").split("\n")[-1]
        if before.lstrip().startswith(";"):
            continue                                    # a comment, not a call
        if name not in sigs:
            problems.append("%s:%d: RL.%s is not defined by lib\\raylib.ahk" % (path, line, name))
            continue
        called = count_arguments(text, match.end() - 1)
        if called is None:
            continue
        calls += 1
        required, total = sigs[name]
        if not required <= called <= total:
            wanted = str(required) if required == total else "%d-%d" % (required, total)
            problems.append("%s:%d: RL.%s takes %s argument(s), called with %d"
                            % (path, line, name, wanted, called))
    return calls, problems


def readme_blocks(path):
    """The README's ahk snippets, in a temp file, so documented code is checked too."""
    import tempfile
    with io.open(path, encoding="utf-8-sig") as handle:
        text = handle.read()
    blocks = re.findall(r"```ahk\r?\n(.*?)```", text, re.S)
    if not blocks:
        return None
    handle = tempfile.NamedTemporaryFile("w", suffix=".ahk", delete=False, encoding="utf-8-sig")
    handle.write("\n\n".join(blocks))
    handle.close()
    return handle.name


def main():
    if not os.path.exists(LIB):
        raise SystemExit("lib/raylib.ahk is missing, run:  python tools\\gen_wrapper.py")
    sigs = signatures()
    targets = sys.argv[1:]
    if not targets:
        targets = sorted(glob.glob(os.path.join(ROOT, "examples", "*.ahk")))
        targets += sorted(glob.glob(os.path.join(ROOT, "tests", "*.ahk")))
        targets.append(os.path.join(ROOT, "README.md"))

    total_calls, all_problems = 0, []
    for target in targets:
        path = target if os.path.isabs(target) else os.path.join(ROOT, target)
        if os.path.basename(path).lower() == "readme.md":
            temp = readme_blocks(path)
            if not temp:
                continue
            calls, problems = check(temp, sigs)
            for text in problems:                      # point at the README, not the temp
                all_problems.append(text.replace(temp, "README.md (code block)", 1))
            os.unlink(temp)
        else:
            if not os.path.exists(path):
                all_problems.append("%s: no such file" % target)
                continue
            calls, problems = check(path, sigs)
            all_problems += problems
        total_calls += calls
        shown = path if not os.path.isabs(target) else os.path.basename(path)
        print("%-28s %3d call(s)" % (os.path.basename(shown), calls))

    print("%d signatures known, %d calls checked" % (len(sigs), total_calls))
    if all_problems:
        print("\n".join(all_problems))
        print("%d arity problem(s)" % len(all_problems))
        sys.exit(1)
    print("0 arity problem(s)")


if __name__ == "__main__":
    main()
