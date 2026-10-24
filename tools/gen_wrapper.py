"""Generate lib/raylib.ahk (AutoHotkey v2 wrapper) from raylib.h.

Only functions AutoHotkey's DllCall can actually reach are emitted: scalar or
pointer parameters and returns, plus Color (a 4 byte struct, which the Microsoft
x64 ABI passes and returns in a general purpose register). Functions that pass or
return structs larger than 8 bytes by value (Texture2D, Vector2, Font, Image,
Rectangle, ...) cannot be called through DllCall at all; see README.md.

Usage: python tools/gen_wrapper.py [path/to/raylib.h]
"""
import os
import re
import sys

HEADER = sys.argv[1] if len(sys.argv) > 1 else os.path.join("vendor", "raylib.h")
OUT = os.path.join("lib", "raylib.ahk")

# C type -> (DllCall type, expression template for the AHK parameter)
ARG = {
    "int": ("Int", "{}"),
    "unsigned int": ("UInt", "{}"),
    "long": ("Int", "{}"),
    "unsigned long": ("UInt", "{}"),
    "float": ("Float", "{}"),
    "double": ("Double", "{}"),
    "bool": ("Char", "{}"),
    "Color": ("UInt", "RL.ABGR({})"),
    "const char *": ("Ptr", "RL.U8({})"),
    "char *": ("Ptr", "RL.U8({})"),
    "void *": ("Ptr", "{}"),
    "unsigned char *": ("Ptr", "{}"),
    "const unsigned char *": ("Ptr", "{}"),
}
# C return type -> DllCall return type (None = void, "" = convert UTF-8 char*)
RET = {
    "void": None,
    "int": "Int",
    "unsigned int": "UInt",
    "long": "Int",
    "float": "Float",
    "double": "Double",
    "bool": "Char",
    "const char *": "",
    "char *": "",
}

# Callable through DllCall but useless or unsafe from AHK: raylib-owned memory
# that would have to be freed by hand, callbacks, or things AHK does natively.
DENY = {
    "MemAlloc", "MemRealloc", "MemFree", "ExportDataAsCode", "SetTraceLogCallback",
    "SetAutomationEventList", "SetAutomationEventBaseFrame",
    "StartAutomationEventRecording", "StopAutomationEventRecording",
    "LoadFileData", "UnloadFileData", "SaveFileData", "CompressData", "DecompressData",
    "EncodeDataBase64", "DecodeDataBase64", "ComputeCRC32", "ComputeMD5", "ComputeSHA1",
    "LoadFileText", "UnloadFileText", "SaveFileText", "GetFileModTime",
    "LoadRandomSequence", "UnloadRandomSequence",
    "LoadUTF8", "UnloadUTF8", "LoadCodepoints", "UnloadCodepoints", "GetCodepointCount",
    "GetCodepoint", "GetCodepointNext", "GetCodepointPrevious", "CodepointToUTF8",
    "TextCopy", "TextIsEqual", "TextLength", "TextSubtext", "TextReplace", "TextInsert",
    "TextJoin", "TextSplit", "TextAppend", "TextFindIndex", "TextToUpper", "TextToLower",
    "TextToPascal", "TextToSnake", "TextToCamel", "TextToInt", "TextToFloat",
    "GetWindowScaleDPI", "SetAudioStreamCallback", "AttachAudioStreamProcessor",
    "DetachAudioStreamProcessor", "SetAudioStreamBufferSizeDefault",
}

# Section title -> predicate over the function name. First match wins, so the
# narrowest sections come first.
SECTIONS = [
    ("cursor", lambda n: n.startswith(("ShowCursor", "HideCursor", "IsCursorHidden",
                                       "EnableCursor", "DisableCursor", "IsCursorOnScreen"))),
    ("mouse", lambda n: "Mouse" in n),
    ("keyboard", lambda n: n.startswith(("IsKey", "GetKey", "GetChar", "SetExitKey"))),
    ("gamepad", lambda n: "Gamepad" in n),
    ("touch & gestures", lambda n: n.startswith(("GetTouch", "SetGesture", "IsGesture",
                                                 "GetGesture"))),
    ("audio device", lambda n: n.startswith(("InitAudio", "CloseAudio", "IsAudio",
                                             "SetMaster", "GetMaster"))),
    ("shapes", lambda n: n.startswith(("ClearBackground", "DrawPixel", "DrawLine", "DrawCircle",
                                       "DrawEllipse", "DrawRing", "DrawRectangle", "DrawTriangle",
                                       "DrawPoly"))),
    ("text", lambda n: n.startswith(("DrawText", "DrawFPS", "SetText", "MeasureText"))),
    ("window & context", lambda n: "Audio" not in n and n.startswith((
        "InitWindow", "CloseWindow", "WindowShouldClose", "IsWindow", "SetWindow", "GetWindow",
        "GetScreen", "GetRender", "GetMonitor", "GetCurrentMonitor", "Toggle", "Maximize",
        "Minimize", "Restore", "SetClipboard", "GetClipboard", "EnableEvent", "DisableEvent",
        "SetConfigFlags"))),
    ("drawing modes", lambda n: n.startswith(("Begin", "End"))),
    ("time, control & misc", lambda n: n in (
        "SetTargetFPS", "GetFrameTime", "GetTime", "GetFPS", "SwapScreenBuffer",
        "PollInputEvents", "WaitTime", "SetRandomSeed", "GetRandomValue", "TakeScreenshot",
        "OpenURL", "SetTraceLogLevel")),
    ("files & paths", lambda n: n.startswith(("FileExists", "DirectoryExists", "IsFile",
                                              "IsPath", "IsFileName", "MakeDirectory",
                                              "ChangeDirectory", "GetFile", "GetDirectory",
                                              "GetPrev", "GetWorking", "GetApplication"))),
]

HELPERS = '''
    ; Load raylib.dll. Called automatically at include time, from the directory
    ; that holds this file.
    static Init() {
        static Loaded := 0
        if Loaded
            return
        SplitPath A_LineFile, , &rlDir
        rlDll := rlDir "\\raylib.dll"
        if !DllCall("kernel32\\LoadLibraryW", "WStr", rlDll, "Ptr")
            throw Error("raylib.ahk: cannot load " rlDll " (error " A_LastError ")")
        Loaded := 1
    }

    ; 0xRRGGBBAA -> the 0xAABBGGRR integer a Color struct occupies in memory
    ; (a Color is {r, g, b, a} in that byte order, read back as little endian).
    static ABGR(RGBA) {
        return ((((RGBA & 0xFF) << 24) | (((RGBA >> 8) & 0xFF) << 16)
            | (((RGBA >> 16) & 0xFF) << 8) | ((RGBA >> 24) & 0xFF)))
    }

    ; Set the alpha byte of a 0xRRGGBBAA color (Amount = 0.0 .. 1.0).
    static Alpha(RGBA, Amount) {
        return (RGBA & 0xFFFFFF00) | Round(Amount < 0 ? 0 : (Amount > 1 ? 255 : Amount * 255))
    }

    ; AHK string -> Buffer with UTF-8 bytes. Raylib takes UTF-8, so "AStr"
    ; (system codepage) would mangle anything outside ASCII.
    static U8(rlStr) {
        rlBuf := Buffer((StrLen(rlStr) + 1) * 4, 0)
        StrPut(rlStr, rlBuf, "UTF-8")
        return rlBuf
    }

    ; Raylib's UTF-8 char* -> AHK string ("" for NULL).
    static S8(rlPtr) {
        return rlPtr ? StrGet(rlPtr, "UTF-8") : ""
    }

    ; Convenience: raw DllCall into raylib.dll for anything not wrapped.
    static Raw(rlFunc, rlParams*) {
        return DllCall("raylib.dll\\" rlFunc, rlParams*)
    }
'''

# Functions taking 'const Vector2 *points' are reachable through a pointer, so
# they are wrapped by hand: the points are packed into a Buffer of float pairs.
MANUAL = '''
    ; ---------------------------------------------------------------- point arrays
    ; Pass a flat array of screen coordinates: [x1, y1, x2, y2, ...].
    static PackPoints(rlPoints) {
        rlCount := rlPoints.Length
        if Mod(rlCount, 2)
            throw Error("raylib.ahk: expected complete x,y pairs", -1)
        rlBuf := Buffer(rlCount * 4, 0)
        Loop rlCount
            NumPut("Float", rlPoints[A_Index], rlBuf, (A_Index - 1) * 4)
        return rlBuf
    }

    ; Draw lines sequence (using gl lines)
    static DrawLineStrip(rlPoints, rlColor) {
        rlBuf := RL.PackPoints(rlPoints)
        DllCall("raylib.dll\\DrawLineStrip", "Ptr", rlBuf, "Int", rlBuf.Size // 8, "UInt", RL.ABGR(rlColor))
    }
    ; Draw a triangle fan defined by points (first vertex is the center).
    ; raylib culls clockwise polygons, so list the points counter-clockwise on
    ; screen (left-to-right along the bottom, then back along the top).
    static DrawTriangleFan(rlPoints, rlColor) {
        rlBuf := RL.PackPoints(rlPoints)
        DllCall("raylib.dll\\DrawTriangleFan", "Ptr", rlBuf, "Int", rlBuf.Size // 8, "UInt", RL.ABGR(rlColor))
    }
    ; Draw a triangle strip defined by points
    static DrawTriangleStrip(rlPoints, rlColor) {
        rlBuf := RL.PackPoints(rlPoints)
        DllCall("raylib.dll\\DrawTriangleStrip", "Ptr", rlBuf, "Int", rlBuf.Size // 8, "UInt", RL.ABGR(rlColor))
    }
    ; Draw spline: Linear, minimum 2 points
    static DrawSplineLinear(rlPoints, rlThick, rlColor) {
        rlBuf := RL.PackPoints(rlPoints)
        DllCall("raylib.dll\\DrawSplineLinear", "Ptr", rlBuf, "Int", rlBuf.Size // 8, "Float", rlThick,
            "UInt", RL.ABGR(rlColor))
    }
    ; Draw spline: Catmull-Rom, minimum 4 points
    static DrawSplineCatmullRom(rlPoints, rlThick, rlColor) {
        rlBuf := RL.PackPoints(rlPoints)
        DllCall("raylib.dll\\DrawSplineCatmullRom", "Ptr", rlBuf, "Int", rlBuf.Size // 8, "Float", rlThick,
            "UInt", RL.ABGR(rlColor))
    }
'''


def typify(arg):
    """'const char *text' -> 'const char *', 'int posX' -> 'int', 'char sym[]' -> 'char'."""
    a = " ".join(arg.replace("[]", "").split())
    m = re.match(r"^(.+?)\s*\b(\w+)$", a)
    return m.group(1).strip() if m else a


def arg_name(arg):
    if arg.strip().endswith("*"):
        return ""
    m = re.search(r"(\w+)\s*$", arg)
    return m.group(1) if m else ""


def parse_enums(text):
    """Enum members, resolving the implicit values ('LOG_TRACE,') by counting on."""
    out = []
    for body, tag in re.findall(r"typedef enum\s*\{(.*?)\}\s*(\w+)\s*;", text, flags=re.S):
        next_value = 0
        for item in body.split(","):
            m = re.match(r"\s*(\w+)\s*(?:=\s*(.+?))?\s*$", item, flags=re.S)
            if not m:
                continue
            name, expr = m.group(1), " ".join((m.group(2) or "").split())
            try:
                value = int(eval(expr, {"__builtins__": {}})) if expr else next_value
            except Exception:
                print("skip constant %s = %s" % (name, expr))
                continue
            out.append((name, str(value), tag))
            next_value = value + 1
    return out


def parse_defines(text):
    """Numeric #defines (integers and floats). Skips RAYLIB_* version macros."""
    out = []
    for name, value in re.findall(r"#define\s+(\w+)\s+(-?(?:0x[\da-fA-F]+|\d*\.?\d+)f?)\s*(?://|$)",
                                  text, flags=re.M):
        if name.startswith("_") or name.startswith("RAYLIB_") or name.endswith("_H"):
            continue
        out.append((name, value.rstrip("f"), "define"))
    return out


def parse_color_defines(text):
    return [(n, "0x%02X%02X%02X%02X" % (int(r), int(g), int(b), int(a)), c.strip())
            for n, r, g, b, a, c in re.findall(
                r"#define\s+(\w+)\s+CLITERAL\(Color\)\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,"
                r"\s*(\d+)\s*\}\s*//(.*)", text, flags=re.M)]


def parse_funcs(text):
    """Collect RLAPI prototypes. '*' is split into its own token so that pointer
    return types survive ('const char *GetMonitorName' -> ret 'const char *')."""
    text = re.sub(r"\s*\*\s*", " * ", text)
    out = []
    for m in re.finditer(r"^RLAPI\s+(.+?)\s+(\w+)\s*\(([^;{}]*)\)\s*;", text, flags=re.S | re.M):
        ret = " ".join(strip_comments(m.group(1)).split())
        name = m.group(2)
        args = " ".join(strip_comments(m.group(3)).split())
        comment = ""
        tail = text[m.end():].split("\n", 1)[0]
        if "//" in tail:
            comment = tail.split("//", 1)[1].strip()
        split = args.split(",") if args and args != "void" else []
        out.append((ret, name, [typify(a) for a in split], [arg_name(a) for a in split], comment))
    return out


def wrappable(ret, name, argtypes, argnames):
    if name in DENY or ret not in RET:
        return False
    return all(t in ARG for t in argtypes) and all(argnames)


def local(Name):
    """Parameter names become rl-prefixed locals, so a user global called 'color'
    can never trip AHK's LocalSameAsGlobal warning inside the generated code."""
    return "rl" + Name[:1].upper() + Name[1:]


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


src = open(HEADER, encoding="utf-8", errors="replace").read()
plain = strip_comments(src)
version = (re.search(r'#define\s+RAYLIB_VERSION\s+"([^"]+)"', plain) or type("", (), {"group": lambda s, i: "unknown"})).group(1)

funcs = parse_funcs(src)
buckets = {title: [] for title, _ in SECTIONS}
taken = set()
for title, pred in SECTIONS:
    for f in funcs:
        if f[1] in taken or not pred(f[1]) or not wrappable(f[0], f[1], f[2], f[3]):
            continue
        buckets[title].append(f)
        taken.add(f[1])

L = []
add = L.append
add("; Autogenerated by tools/gen_wrapper.py from raylib.h (raylib %s). Do not edit by hand." % version)
add("; Regenerate:  python tools/gen_wrapper.py <raylib.h>")
add(";")
add("; Colors are plain 0xRRGGBBAA integers, the same order as the constants below and as")
add("; ColorToInt(). A Color is a 4 byte struct, which the x64 ABI passes in a register,")
add("; so no struct marshalling is needed; RL.ABGR() converts to the memory layout.")
add(";")
add("; Example:")
add(";     #Include ..\\lib\\raylib.ahk")
add(";     RL.InitWindow(800, 450, \"raylib + AutoHotkey\")")
add(";     RL.SetTargetFPS(60)")
add(";     while !RL.WindowShouldClose() {")
add(";         RL.BeginDrawing()")
add(";         RL.ClearBackground(RL.RAYWHITE)")
add(";         RL.DrawCircle(RL.GetMouseX(), RL.GetMouseY(), 40, RL.MAROON)")
add(";         RL.DrawText(\"esc to quit\", 10, 10, 20, RL.DARKGRAY)")
add(";         RL.EndDrawing()")
add(";     }")
add(";     RL.CloseWindow()")
add("; Point arrays (DrawLineStrip, DrawTriangleFan, DrawSpline*) are flat AHK arrays")
add("; [x1, y1, x2, y2, ...]; DrawTriangleFan needs them counter-clockwise, raylib culls")
add("; clockwise polygons. TakeScreenshot() ignores the directory part of its name and")
add("; reads one buffer swap behind, so draw the frame twice and SetWorkingDir() first.")
add(";")
add("#Requires AutoHotkey v2.0")
add("")
add("class RL {")
add('    static Version := "%s"' % version)
add("")
add("    ; ---------------------------------------------------------------- helpers")
for line in HELPERS.lstrip("\n").rstrip().splitlines():
    add(line)
for line in MANUAL.rstrip().splitlines():
    add(line)

for title, _ in SECTIONS:
    picked = buckets[title]
    if not picked:
        continue
    add("")
    add("    ; ---------------------------------------------------------------- %s" % title)
    for ret, name, argtypes, argnames, comment in picked:
        if comment:
            add("    ; %s" % comment)
        locals = [local(n) for n in argnames]
        call = 'DllCall("raylib.dll\\%s"' % name
        for t, n in zip(argtypes, locals):
            dt, tmpl = ARG[t]
            call += ', "%s", %s' % (dt, tmpl.format(n))
        if RET[ret] is None:
            add("    static %s(%s) {\n        %s)\n    }" % (name, ", ".join(locals), call))
        elif RET[ret] == "":
            # The result is a pointer into memory we do not own, and raylib
            # sometimes points back into the argument string, so keep the UTF-8
            # buffers alive until after StrGet() by binding them to locals.
            body = []
            for i, (t, n) in enumerate(zip(argtypes, locals)):
                if t in ("const char *", "char *"):
                    buf = "rlBuf%d" % i
                    body.append("        %s := RL.U8(%s)" % (buf, n))
                    call = call.replace("RL.U8(%s)" % n, buf)
            body.append("        return RL.S8(%s, \"Ptr\"))" % call)
            add("    static %s(%s) {\n%s\n    }" % (name, ", ".join(locals), "\n".join(body)))
        else:
            add("    static %s(%s) {\n        return %s, \"%s\")\n    }"
                % (name, ", ".join(locals), call, RET[ret]))

add("")
add("    ; ---------------------------------------------------------------- constants")
seen = set()
for name, value, _tag in parse_defines(plain) + parse_enums(plain):
    if name.lower() in seen:
        continue
    seen.add(name.lower())
    add("    static %-32s := %s" % (name, value))
add("")
add("    ; ---------------------------------------------------------------- colors")
colors = parse_color_defines(src)
for name, value, comment in colors:
    if name.lower() in seen:
        continue
    seen.add(name.lower())
    add("    static %-32s := %s  ; %s" % (name, value, comment))
add("}")
add("")
add("RL.Init()")

os.makedirs("lib", exist_ok=True)
open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")

skipped = [f for f in funcs if f[1] not in taken]
print("\nwrapped %d of %d functions" % (len(taken), len(funcs)))
for title, _ in SECTIONS:
    print("  %-20s %3d" % (title, len(buckets[title])))
print("constants %d, colors %d -> %s (%d lines)"
      % (len(seen) - len(colors), len(colors), OUT, len(L)))
with open(os.path.join("tools", "skipped.txt"), "w") as fh:
    fh.write("\n".join("%-40s ret=%-18s %s" % (f[1], f[0], ", ".join(f[2])) for f in skipped))
