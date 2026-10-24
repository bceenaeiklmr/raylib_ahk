"""Generate the AutoHotkey v2 bindings for raylib from vendor/raylib.h:

  lib/raylib.ahk       the RL class everything else includes
  vendor/shim.c        flat-ABI C wrappers, built by tools/build_shim.ps1
  tools/skipped.txt    prototypes with no binding, and the reason

Two calling paths are emitted:

  direct   AutoHotkey's DllCall passes and returns scalars, pointers and Color (a
           4 byte struct, which the Microsoft x64 ABI keeps in a register). Those
           methods call raylib.dll directly.

  shim     Everything else passes or returns a struct larger than 8 bytes by
           value, which DllCall cannot express. shim.c gives each of those a flat
           twin: Vector2/Vector3/Vector4/Rectangle become floats, other structs
           travel as a Buffer that AutoHotkey owns, a Color is one integer, struct
           results come back through an out pointer, and 'const Vector2 *points'
           with its count becomes one flat AutoHotkey array.

Usage:  python tools/gen_wrapper.py [path/to/raylib.h]
"""
import os
import re
import sys
import time

HEADER = sys.argv[1] if len(sys.argv) > 1 else os.path.join("vendor", "raylib.h")
OUT_AHK = os.path.join("lib", "raylib.ahk")
OUT_C = os.path.join("vendor", "shim.c")
OUT_SKIPPED = os.path.join("tools", "skipped.txt")
OUT_DEF = os.path.join("vendor", "raylib.def")
MAX_LINE = 108

# Structs that flatten to scalar floats in both directions.
FLATTEN = ("Vector2", "Vector3", "Vector4", "Rectangle")

# Scalar members of raylib structs as (size, align) for the Microsoft x64 layout:
# long is 4 bytes, pointers 8, and raylib uses no packing pragmas.
SCALARS = {
    "char": (1, 1), "unsigned char": (1, 1), "bool": (1, 1),
    "short": (2, 2), "unsigned short": (2, 2),
    "int": (4, 4), "unsigned int": (4, 4), "float": (4, 4),
    "long": (4, 4), "unsigned long": (4, 4),
    "long long": (8, 8), "unsigned long long": (8, 8), "double": (8, 8),
}
DLLCALL_OF = {
    "char": "Char", "unsigned char": "UChar", "bool": "Char",
    "short": "Short", "unsigned short": "UShort",
    "int": "Int", "unsigned int": "UInt", "long": "Int", "unsigned long": "UInt",
    "float": "Float", "double": "Double",
}

# Reachable in principle but left out on purpose, grouped by why. Everything here
# either hands back memory raylib owns and AutoHotkey would have to free by hand,
# installs a callback, or duplicates something AutoHotkey does better.
DENY_REASONS = [
    ("raw allocation and file bytes, AutoHotkey has Buffer() and FileRead for those", {
        "MemAlloc", "MemRealloc", "MemFree", "LoadFileData", "UnloadFileData", "SaveFileData",
        "GetFileModTime", "LoadFileText", "UnloadFileText", "SaveFileText", "CompressData",
        "DecompressData", "EncodeDataBase64", "DecodeDataBase64", "ComputeCRC32", "ComputeMD5",
        "ComputeSHA1", "LoadRandomSequence", "UnloadRandomSequence"}),
    ("text helpers, AutoHotkey strings and StrLen/SubStr/InStr already do these", {
        "LoadUTF8", "UnloadUTF8", "LoadCodepoints", "UnloadCodepoints", "GetCodepointCount",
        "GetCodepoint", "GetCodepointNext", "GetCodepointPrevious", "CodepointToUTF8",
        "TextCopy", "TextIsEqual", "TextLength", "TextSubtext", "TextReplace", "TextInsert",
        "TextJoin", "TextSplit", "TextAppend", "TextFindIndex", "TextToUpper", "TextToLower",
        "TextToPascal", "TextToSnake", "TextToCamel", "TextToInt", "TextToFloat"}),
    ("returns generated source or bytes that only MemFree() can release", {
        "ExportDataAsCode", "ExportImageAsCode", "ExportFontAsCode", "ExportMeshAsCode",
        "ExportImageToMemory"}),
    ("installs a callback, which AutoHotkey cannot hand over safely", {
        "SetTraceLogCallback", "SetLoadFileDataCallback", "SetSaveFileDataCallback",
        "SetLoadFileTextCallback", "SetSaveFileTextCallback", "SetAudioStreamCallback",
        "AttachAudioStreamProcessor", "DetachAudioStreamProcessor", "AttachAudioMixedProcessor",
        "DetachAudioMixedProcessor", "SetAudioStreamBufferSizeDefault"}),
    ("automation events, which need an AutomationEventList that raylib owns", {
        "SetAutomationEventList", "SetAutomationEventBaseFrame", "StartAutomationEventRecording",
        "StopAutomationEventRecording", "PlayAutomationEvent", "LoadAutomationEventList",
        "UnloadAutomationEventList", "ExportAutomationEventList"}),
    ("VR stereo, which needs a VrStereoConfig built by hand", {
        "LoadVrStereoConfig", "UnloadVrStereoConfig", "BeginVrStereoMode"}),
    ("FilePathList: a char** plus a count that raylib keeps ownership of", {
        "LoadDirectoryFiles", "LoadDirectoryFilesEx", "UnloadDirectoryFiles", "LoadDroppedFiles",
        "UnloadDroppedFiles"}),
    ("arrays plus counts that raylib allocates (materials, animation sets)", {
        "LoadMaterials", "LoadMaterialSet", "LoadMaterialAnimSet", "LoadMaterialAnimTexture",
        "LoadModelAnimations", "UnloadModelAnimations"}),
    ("font baking: takes a GlyphInfo array and returns a Rectangle**", {
        "GenImageFontAtlas", "LoadFontData", "UnloadFontData"}),
]
DENY = {name for _reason, names in DENY_REASONS for name in names}


def deny_reason(name):
    for reason, names in DENY_REASONS:
        if name in names:
            return reason
    return "left out on purpose"

# Section title -> predicate over the function name. First match wins, so the
# narrowest sections come first and "misc" catches the rest.
SECTIONS = [
    ("cursor", lambda n: n.startswith(("ShowCursor", "HideCursor", "IsCursorHidden",
                                       "EnableCursor", "DisableCursor", "IsCursorOnScreen"))),
    ("gamepad", lambda n: "Gamepad" in n),
    ("keyboard", lambda n: n.startswith(("IsKey", "GetKey", "GetChar", "SetExitKey"))),
    ("mouse", lambda n: "Mouse" in n),
    ("touch & gestures", lambda n: n.startswith(("GetTouch", "SetGesture", "IsGesture",
                                                 "GetGesture"))),
    ("audio", lambda n: re.search(r"(Sound|Music|Wave|Audio)", n) is not None),
    ("fonts", lambda n: re.search(r"(Font|Glyph|Codepoint)", n) is not None),
    ("textures & images", lambda n: re.search(r"(Texture|Image|Pixel)", n) is not None),
    ("camera & projection", lambda n: re.search(r"(Camera|WorldToScreen|ScreenToWorld)", n) is not None),
    ("shaders & materials", lambda n: re.search(r"(Shader|Material)", n) is not None),
    ("3D models & meshes", lambda n: re.search(
        r"(Mesh|Model|Billboard|Cube|Sphere|Cylinder|Capsule|Heightmap|Grid)", n) is not None),
    ("3D drawing", lambda n: re.search(r"(DrawPlane|DrawRay|DrawBoundingBox|Line3D|Point3D)", n) is not None),
    ("collision", lambda n: n.startswith(("CheckCollision", "GetCollision"))),
    ("colour & math", lambda n: n.startswith(("Color", "Clamp", "Lerp", "Normalize", "Remap",
                                              "Wrap", "Erase", "Fade"))),
    ("render textures", lambda n: n in ("BeginTextureMode", "EndTextureMode")),
    ("shapes", lambda n: n.startswith(("ClearBackground", "DrawPixel", "DrawLine", "DrawCircle",
                                       "DrawEllipse", "DrawRing", "DrawRectangle", "DrawTriangle",
                                       "DrawPoly", "DrawSpline", "SetShapesTexture",
                                       "GetShapesTexture"))),
    ("text", lambda n: n.startswith(("DrawText", "DrawFPS", "SetText", "MeasureText"))),
    ("window & context", lambda n: "Audio" not in n and n.startswith((
        "InitWindow", "CloseWindow", "WindowShouldClose", "IsWindow", "SetWindow", "GetWindow",
        "GetScreen", "GetRender", "GetMonitor", "GetCurrentMonitor", "Toggle", "Maximize",
        "Minimize", "Restore", "SetClipboard", "GetClipboard", "EnableEvent", "DisableEvent",
        "SetConfigFlags", "GetApplication", "SetAppName"))),
    ("drawing modes", lambda n: n.startswith(("Begin", "End"))),
    ("time, control & misc", lambda n: n in (
        "SetTargetFPS", "GetFrameTime", "GetTime", "GetFPS", "SwapScreenBuffer", "PollInputEvents",
        "WaitTime", "SetRandomSeed", "GetRandomValue", "TakeScreenshot", "OpenURL",
        "SetTraceLogLevel")),
    ("files & paths", lambda n: n.startswith(("FileExists", "DirectoryExists", "IsFile", "IsPath",
                                              "IsFileName", "MakeDirectory", "ChangeDirectory",
                                              "GetFile", "GetDirectory", "GetPrev", "GetWorking"))),
    ("misc", lambda n: True),
]

HELPERS = '''
    ; Load raylib.dll and, when it is present, the generated shim. Runs at include
    ; time, from the directory that holds this file.
    static Init() {
        static Loaded := 0
        if Loaded
            return
        SplitPath A_LineFile, , &rlDir
        if !DllCall("kernel32\\LoadLibraryW", "WStr", rlDir "\\raylib.dll", "Ptr")
            throw Error("raylib.ahk: cannot load " rlDir "\\raylib.dll (error " A_LastError ")")
        if FileExist(rlDir "\\raylib_ahk_shim.dll")
            && DllCall("kernel32\\LoadLibraryW", "WStr", rlDir "\\raylib_ahk_shim.dll", "Ptr")
            RL.VerifyLayout()
        Loaded := 1
    }

    ; 0xRRGGBBAA -> the 0xAABBGGRR integer a Color occupies in memory, and back.
    static ABGR(RGBA) {
        return (((RGBA & 0xFF) << 24) | (((RGBA >> 8) & 0xFF) << 16)
            | (((RGBA >> 16) & 0xFF) << 8) | ((RGBA >> 24) & 0xFF))
    }

    static RGBA(ABGR) {
        return (((ABGR & 0xFF) << 24) | (((ABGR >> 8) & 0xFF) << 16)
            | (((ABGR >> 16) & 0xFF) << 8) | ((ABGR >> 24) & 0xFF))
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

    ; Flat array of screen coordinates [x1, y1, x2, y2, ...] -> Buffer of floats.
    static PackPoints(rlPoints) {
        rlCount := rlPoints.Length
        if Mod(rlCount, 2)
            throw Error("raylib.ahk: expected complete x,y pairs", -1)
        rlBuf := Buffer(rlCount * 4, 0)
        Loop rlCount
            NumPut("Float", rlPoints[A_Index], rlBuf, (A_Index - 1) * 4)
        return rlBuf
    }

    ; Codepoints of a string as an Int32 Buffer, for LoadFontEx's codepoint array
    ; (pass rlStr.Size // 4 as the count). Basic plane only, which is everything
    ; except emoji and historic scripts.
    static Codepoints(rlStr) {
        rlBuf := Buffer(StrLen(rlStr) * 4, 0)
        Loop StrLen(rlStr)
            NumPut("Int", Ord(SubStr(rlStr, A_Index, 1)), rlBuf, (A_Index - 1) * 4)
        return rlBuf
    }

    ; A Camera3D Buffer: eye, center and up as [x, y, z] arrays, Fov in degrees,
    ; Projection RL.CAMERA_PERSPECTIVE or RL.CAMERA_ORTHOGRAPHIC.
    static MakeCamera3D(Eye := [0, 0, 0], Center := [0, 0, 0], Up := [0, 1, 0],
        Fov := 60.0, Projection := 0) {
        rlBuf := Buffer(RL.Camera3D_Size, 0)
        Loop 3 {
            NumPut("Float", Eye[A_Index], rlBuf, (A_Index - 1) * 4)
            NumPut("Float", Center[A_Index], rlBuf, 12 + (A_Index - 1) * 4)
            NumPut("Float", Up[A_Index], rlBuf, 24 + (A_Index - 1) * 4)
        }
        NumPut("Float", Fov, rlBuf, 36)
        NumPut("Int", Projection, rlBuf, 40)
        return rlBuf
    }

    ; A Camera2D Buffer: offset and target as [x, y], rotation in degrees, zoom as
    ; a unit scale (1.0 draws 1:1).
    static MakeCamera2D(Offset := [0, 0], Target := [0, 0], Rotation := 0.0, Zoom := 1.0) {
        rlBuf := Buffer(RL.Camera2D_Size, 0)
        NumPut("Float", Offset[1], rlBuf, 0)
        NumPut("Float", Offset[2], rlBuf, 4)
        NumPut("Float", Target[1], rlBuf, 8)
        NumPut("Float", Target[2], rlBuf, 12)
        NumPut("Float", Rotation, rlBuf, 16)
        NumPut("Float", Zoom, rlBuf, 20)
        return rlBuf
    }

    ; Save what is on screen to a full path. TakeScreenshot() wants a bare file name
    ; and resolves it against the directory the process was in when raylib started,
    ; because its file code keeps a copy of that path: changing the working directory
    ; afterwards has no effect. This exports the Image from LoadImageFromScreen(), so the path can be
    ; absolute, which is what a test wants.
    static ScreenShot(rlPath) {
        rlImg := RL.LoadImageFromScreen()
        rlOk := RL.ExportImage(rlImg, rlPath)
        RL.UnloadImage(rlImg)
        if !rlOk
            throw Error("raylib.ahk: cannot write " rlPath, -1)
    }

    ; Convenience: raw DllCall into raylib.dll for anything not wrapped.
    static Raw(rlFunc, rlParams*) {
        return DllCall("raylib.dll\\" rlFunc, rlParams*)
    }
'''


# ------------------------------------------------------------------ header parsing
def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def parse_funcs(text):
    """RLAPI prototypes -> (ret, name, [arg types], [arg names], comment)."""
    text = re.sub(r"\s*\*\s*", " * ", text)
    out = []
    for m in re.finditer(r"^RLAPI\s+(.+?)\s+(\w+)\s*\(([^;{}]*)\)\s*;", text, flags=re.S | re.M):
        ret = " ".join(strip_comments(m.group(1)).split())
        name, args = m.group(2), " ".join(strip_comments(m.group(3)).split())
        comment = ""
        tail = text[m.end():].split("\n", 1)[0]
        if "//" in tail:
            comment = tail.split("//", 1)[1].strip()
        split = [a.strip() for a in args.split(",")] if args and args != "void" else []
        types, names = [], []
        for i, a in enumerate(split):
            if a == "...":
                types.append("...")
                names.append("")
                continue
            m2 = re.match(r"^(.*?)\s*\b(\w+)$", a)
            types.append((m2.group(1).strip() if m2 else a))
            names.append(m2.group(2) if m2 and not a.endswith("*") else "arg%d" % (i + 1))
        out.append((ret, name, types, names, comment))
    return out


def parse_structs(text):
    """typedef struct Name { ... } Name;  ->  {name: [(type, field, count), ...]}"""
    out = {}
    for m in re.finditer(r"typedef struct\s+(\w+)\s*\{(.*?)\}\s*\w*\s*;", text, flags=re.S):
        name, body = m.group(1), strip_comments(m.group(2))
        fields = []
        for stmt in body.split(";"):
            stmt = " ".join(stmt.split())
            if not stmt:
                continue
            base = None
            for part in stmt.split(","):
                part = part.strip()
                if not part:
                    continue
                count = 1
                arr = re.search(r"\s*\[\s*(\d+)\s*\]\s*$", part)
                if arr:
                    count = int(arr.group(1))
                    part = part[:arr.start()]
                nm = re.search(r"(\w+)\s*$", part)
                if not nm:
                    continue
                lead = " ".join(part[:nm.start()].split())
                stars = lead.count("*")
                if base is None:
                    base = lead[:-1].strip() if stars else lead
                if not base:
                    continue
                ctype = base + " *" * stars
                if not ctype:
                    continue
                fields.append((ctype, nm.group(1), count))
        if fields:
            out[name] = fields
    return out


def parse_aliases(text):
    """'typedef Texture Texture2D;' -> {'Texture2D': 'Texture'}, resolved transitively."""
    raw = {alias: target for target, alias in re.findall(r"typedef\s+(\w+)\s+(\w+)\s*;", text)}
    out = {}
    for alias, target in raw.items():
        seen, name = {alias}, target
        while name in raw and name not in seen:
            seen.add(name)
            name = raw[name]
        if name != alias:
            out[alias] = name
    return out


def parse_enums(text):
    out = []
    for body in re.findall(r"typedef enum\s*\{(.*?)\}\s*\w+\s*;", text, flags=re.S):
        next_value = 0
        for item in body.split(","):
            m = re.match(r"\s*(\w+)\s*(?:=\s*(.+?))?\s*$", item, flags=re.S)
            if not m:
                continue
            name, expr = m.group(1), " ".join((m.group(2) or "").split())
            try:
                value = int(eval(expr, {"__builtins__": {}})) if expr else next_value
            except Exception:
                continue
            out.append((name, str(value)))
            next_value = value + 1
    return out


def parse_defines(text):
    out = []
    for name, value in re.findall(r"#define\s+(\w+)\s+(-?(?:0x[\da-fA-F]+|\d*\.?\d+)f?)\s*(?://|$)",
                                  text, flags=re.M):
        if name.startswith("_") or name.startswith("RAYLIB_") or name.endswith("_H"):
            continue
        out.append((name, value.rstrip("f")))
    return out


def parse_color_defines(text):
    return [(n, "0x%02X%02X%02X%02X" % (int(r), int(g), int(b), int(a)), c.strip())
            for n, r, g, b, a, c in re.findall(
                r"#define\s+(\w+)\s+CLITERAL\(Color\)\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,"
                r"\s*(\d+)\s*\}\s*//(.*)", text, flags=re.M)]


# ------------------------------------------------------------------ struct layout
class Layout(object):
    """Microsoft x64 sizes and offsets, so AutoHotkey can read struct Buffers."""

    def __init__(self, structs, aliases=None):
        self.structs = structs
        self.aliases = aliases or {}
        self._cache = {}

    def canon(self, ctype):
        """'const Texture2D *' -> 'const Texture *' (raylib's own aliases)."""
        t = self.bare(ctype)
        star = t.endswith(" *")
        base = t[:-2] if star else t
        base = self.aliases.get(base, base)
        return base + (" *" if star else "")

    @staticmethod
    def bare(ctype):
        return ctype.replace("const ", "").strip()

    def size_align(self, ctype):
        t = self.canon(ctype)
        if t.endswith("*"):
            return (8, 8)
        if t in SCALARS:
            return SCALARS[t]
        if t in self.structs:
            return self.struct_layout(t)[0]
        raise KeyError(ctype)

    def struct_layout(self, name):
        if name in self._cache:
            return self._cache[name]
        self._cache[name] = ((0, 1), [])          # cycle guard
        offset, size, align, fields = 0, 0, 1, []
        for ctype, field, count in self.structs[name]:
            fsize, falign = self.size_align(ctype)
            offset = (offset + falign - 1) // falign * falign
            fields.append((ctype, field, offset, count))
            offset += fsize * count
            size = offset
            align = max(align, falign)
        total = (size + align - 1) // align * align
        self._cache[name] = ((total, align), fields)
        return self._cache[name]

    def size(self, name):
        return self.struct_layout(name)[0][0]

    def fields(self, name):
        return self.struct_layout(name)[1]


def dllcall_of(ctype):
    t = Layout.bare(ctype)
    return "Ptr" if t.endswith("*") else DLLCALL_OF.get(t)


def camel(word):
    return word[:1].upper() + word[1:]


def lower1(word):
    return word[:1].lower() + word[1:]


# ------------------------------------------------------------------ one prototype
class Plan(object):
    """Bridges one raylib prototype to AutoHotkey, plus its shim twin if needed."""

    def __init__(self, func, layout):
        self.ret, self.name, self.argtypes, self.argnames, self.comment = func
        self.layout = layout
        self.reason = "not reachable"
        self.items = []          # one entry per C parameter, in order
        self.ret_kind = "void"   # void | scalar | text | ptr | color | struct
        self.ret_type = None     # DllCall type for scalar/text/ptr/color
        self.ret_struct = None   # struct name for struct results
        self.ret_flat = False    # struct result returned as an array of floats
        self.shim = False
        self.buffers = []        # struct names that travel as Buffers

    def build(self):
        self.ok = True
        if self.name in DENY:
            return self.fail(deny_reason(self.name))
        if "..." in self.argtypes:
            return self.fail("variadic arguments")
        ret = self.layout.canon(self.ret)
        if ret == "..." or not self.plan_ret(ret):
            return self
        for i, (ctype, aname) in enumerate(zip(self.argtypes, self.argnames)):
            if not self.plan_arg(ctype, aname, i):
                return self
        self.merge_point_arrays()
        return self

    def fail(self, reason):
        self.ok = False
        self.reason = reason
        return self

    def plan_ret(self, ret):
        if ret == "void":
            return True
        if ret in ("char *", "const char *"):
            self.ret_kind, self.ret_type = "text", "Ptr"
            return True
        if ret.endswith("*"):
            self.ret_kind, self.ret_type = "ptr", "Ptr"      # hand back to Unload*()
            return True
        if ret in DLLCALL_OF:
            self.ret_kind, self.ret_type = "scalar", DLLCALL_OF[ret]
            return True
        if ret == "Color":
            self.ret_kind, self.ret_type = "color", "UInt"   # 4 bytes: comes back in EAX
            return True
        if ret in self.layout.structs:
            self.ret_kind, self.ret_struct = "struct", ret
            self.ret_flat = ret in FLATTEN
            self.buffers.append(ret)
            self.shim = True
            return True
        self.fail("return type %s cannot be bridged" % self.ret)
        return False
    def plan_arg(self, ctype, aname, index):
        t = self.layout.canon(ctype)
        ahk = "rl" + camel(aname)
        c = lower1(ahk[2:])
        item = dict(ctype=ctype, ahk=ahk)
        if t in ("char *", "const char *"):
            item.update(kind="string", dt="Ptr", expr="RL.U8(%s)" % ahk,
                        cdecl="%s %s" % (ctype, c), carg=c)
        elif t.endswith("*"):
            item.update(kind="ptr", dt="Ptr", expr=ahk, cdecl="%s %s" % (ctype, c), carg=c)
        elif t in DLLCALL_OF:
            item.update(kind="scalar", dt=DLLCALL_OF[t], expr=ahk, cdecl="%s %s" % (ctype, c),
                        carg=c)
        elif t == "Color":
            item.update(kind="color", dt="UInt", expr="RL.ABGR(%s)" % ahk,
                        cdecl="unsigned int %sRaw" % c, carg=c, raw=c + "Raw")
        elif t in FLATTEN:
            members = [(ahk + camel(field), lower1(c + camel(field)))
                       for _ct, field, _o, _n in self.layout.fields(t)]
            item.update(kind="flat", struct=t, members=members, local=c)
            self.shim = True
        elif t in self.layout.structs:
            item.update(kind="struct", struct=t, dt="Ptr", expr=ahk,
                        cdecl=("const %s *%s" if ctype.startswith("const ") else "%s *%s") % (t, c),
                        carg="*" + c)
            self.buffers.append(t)
            self.shim = True
        else:
            self.fail("parameter type %s cannot be bridged" % ctype)
            return False
        self.items.append(item)
        return True

    def merge_point_arrays(self):
        """'const Vector2 *points' plus the count right after it -> one flat AHK array."""
        for i, item in enumerate(self.items[:-1]):
            nxt = self.items[i + 1]
            if (item["kind"] == "ptr" and item["ctype"] == "const Vector2 *"
                    and nxt["kind"] == "scalar" and nxt["ctype"] == "int"):
                item["kind"] = "points"
                item["buf"] = "rlPts"
                nxt["merged"] = True

    # -- AutoHotkey side ------------------------------------------------------
    def ahk_params(self):
        out = []
        for item in self.items:
            if item.get("merged"):
                continue
            if item["kind"] == "flat":
                out += [name for name, _c in item["members"]]
            else:
                out.append(item["ahk"])
        return out

    def ahk_args(self):
        """DllCall argument pairs in call order, plus any setup lines."""
        pairs, setup = [], []
        for item in self.items:
            if item.get("merged"):
                continue
            kind = item["kind"]
            if kind == "flat":
                pairs += [("Float", name) for name, _c in item["members"]]
            elif kind == "points":
                buf = item["buf"]
                setup.append("        %s := RL.PackPoints(%s)" % (buf, item["ahk"]))
                pairs.append(("Ptr", buf))
                pairs.append(("Int", "%s.Size // 8" % buf))
            else:
                pairs.append((item["dt"], item["expr"]))
        return pairs, setup

    def ahk(self):
        pairs, setup = self.ahk_args()
        keep_text = self.ret_kind == "text"
        body = list(setup)
        strings = []
        for i, (dt, expr) in enumerate(pairs):
            if expr.startswith("RL.U8(") and keep_text:
                buf = "rlBuf%d" % i
                strings.append("        %s := %s" % (buf, expr))
                pairs[i] = (dt, buf)
        body += strings
        if self.shim:
            args = []
            if self.ret_struct:
                args.append(("Ptr", "rlOut"))
                body.append("        rlOut := Buffer(%d, 0)" % self.layout.size(self.ret_struct))
            args += pairs
            if self.ret_struct:
                body.append(dllcall_line("raylib_ahk_shim\\rla_%s" % self.name, args, None, ""))
                if self.ret_flat:
                    reads = ", ".join('NumGet(rlOut, %d, "Float")' % off
                                      for _c, _f, off, _n in self.layout.fields(self.ret_struct))
                    body.append("        return [%s]" % reads)
                else:
                    body.append("        return rlOut")
            else:
                ret = {"void": None, "scalar": self.ret_type, "ptr": "Ptr",
                       "text": "Ptr", "color": "UInt"}[self.ret_kind]
                prefix = {"void": "", "scalar": "return ", "ptr": "return ",
                          "text": "return RL.S8(", "color": "return RL.RGBA("}[self.ret_kind]
                suffix = ")" if self.ret_kind in ("text", "color") else ""
                body.append(dllcall_line("raylib_ahk_shim\\rla_%s" % self.name, args, ret,
                                         prefix, suffix))
            return self._method(body)

        target = "raylib.dll\\%s" % self.name
        if self.ret_kind == "void":
            body.append(dllcall_line(target, pairs, None, ""))
        elif self.ret_kind == "text":
            body.append(dllcall_line(target, pairs, "Ptr", "return RL.S8(", ")"))
        elif self.ret_kind == "color":
            body.append(dllcall_line(target, pairs, "UInt", "return RL.RGBA(", ")"))
        else:
            body.append(dllcall_line(target, pairs, self.ret_type, "return "))
        return self._method(body)

    def _method(self, body):
        params = self.ahk_params()
        head = "    static %s(%s) {" % (self.name, ", ".join(params))
        params = self.ahk_params()
        head = "    static %s(%s) {" % (self.name, ", ".join(params))  # noqa: E501
        if len(head) > MAX_LINE:
            rows = [", ".join(params[i:i + 4]) for i in range(0, len(params), 4)]
            head = "    static %s(\n        %s) {" % (self.name, ",\n        ".join(rows))
        out = (["    ; %s" % self.comment] if self.comment else []) + [head] + body + ["    }"]
        return "\n".join(out)

    # -- C side ---------------------------------------------------------------
    def c(self):
        if not self.shim:
            return None
        decls, setup, args = [], [], []
        if self.ret_struct:
            decls.append("%s *out" % self.ret_struct)
        for item in self.items:
            kind = item["kind"]
            if kind == "flat":
                decls += ["float %s" % c for _n, c in item["members"]]
                setup.append("%s %s = { %s };" % (item["struct"], item["local"],
                                                  ", ".join(c for _n, c in item["members"])))
                args.append(item["local"])
            elif kind == "struct":
                decls.append(item["cdecl"])
                args.append(item["carg"])
            elif kind == "color":
                decls.append(item["cdecl"])
                raw = item["raw"]
                setup.append("Color %s = { (unsigned char)(%s), (unsigned char)(%s >> 8),"
                             " (unsigned char)(%s >> 16), (unsigned char)(%s >> 24) };"
                             % (item["carg"], raw, raw, raw, raw))
                args.append(item["carg"])
            else:                                # string, scalar, ptr, points
                decls.append(item["cdecl"])
                args.append(item["carg"])
        call = "%s(%s)" % (self.name, ", ".join(args))
        body = ["    " + s for s in setup]
        if self.ret_struct:
            body.append("    *out = %s;" % call)
        elif self.ret_kind == "void":
            body.append("    %s;" % call)
        elif self.ret_kind == "color":
            # the same 0xAABBGGRR integer a direct call reads out of EAX
            body.append("    Color rlRet = %s;" % call)
            body.append("    return ((unsigned int)rlRet.a << 24) | ((unsigned int)rlRet.b << 16)")
            body.append("        | ((unsigned int)rlRet.g << 8) | rlRet.r;")
        else:                                    # scalar, pointer or string result
            body.append("    return %s;" % call)
        ret_c = {"void": "void", "struct": "void", "color": "unsigned int",
                 "scalar": self.ret, "ptr": self.ret, "text": self.ret}[self.ret_kind]
        return "RLA %s rla_%s(%s) {\n%s\n}" % (
            ret_c, self.name, ", ".join(decls) if decls else "void", "\n".join(body))


def dllcall_line(target, pairs, ret_type, prefix="return ", suffix=""):
    """One DllCall statement, wrapped after commas when it gets long.

    AutoHotkey continues a statement on the next line when the previous one ends
    with a comma, so the wrapped form is valid as-is.
    """
    pieces = ['"%s", %s' % (dt, expr) for dt, expr in pairs]
    if ret_type:
        pieces.append('"%s"' % ret_type)
    head = "        " + prefix + 'DllCall("%s"' % target
    one = head + (", " + ", ".join(pieces) if pieces else "") + ")" + suffix
    if len(one) <= MAX_LINE:
        return one
    lines, cur = [head + ", "], ""
    for p in pieces:
        if cur and len(cur) + len(p) + 2 > MAX_LINE - 12:
            # AutoHotkey continues the statement because this line ends with a comma
            lines[-1] += cur.strip().rstrip(",") + ","
            lines.append(" " * 16)
            cur = ""
        cur += p + ", "
    lines[-1] += cur[:-2] + ")" + suffix
    return "\n".join(lines)


# ---------------------------------------------------------------------- emission
def flat_fields(layout, struct, prefix="", base=0, depth=0):
    """Scalar fields of a struct with nested structs flattened, one entry per accessor:
    the AutoHotkey name suffix, its offset, the NumGet type and a C offsetof expression.
    """
    out = []
    for ctype, field, off, count in layout.fields(struct):
        t = Layout.bare(ctype)
        if t in layout.structs and count == 1 and depth < 2:
            for item in flat_fields(layout, t, "%s_" % camel(field) if prefix else camel(field),
                                    base + off, depth + 1):
                item["c"] = "(unsigned int)offsetof(%s, %s) + %s" % (struct, field, item["c"])
                out.append(item)
            continue
        dt = dllcall_of(ctype)
        if dt is None:
            continue
        out.append(dict(name="%s%s" % (prefix, camel(field)), off=base + off, dt=dt,
                        c="(unsigned int)offsetof(%s, %s)" % (struct, field)))
    return out


def emit_ahk(version, layout, buckets, plans, buffers, header_text):
    names_of = {}
    for alias, target in layout.aliases.items():
        names_of.setdefault(target, []).append(alias)
    L = []
    add = L.append
    add("; Autogenerated by tools/gen_wrapper.py from raylib.h (raylib %s). Do not edit by hand." % version)
    add("; Regenerate:  python tools/gen_wrapper.py  then  powershell tools/build_shim.ps1")
    add(";")
    add("; Colors are plain 0xRRGGBBAA integers, the same order as the constants below and as")
    add("; ColorToInt(); RL.ABGR() converts to the byte order a Color has in memory.")
    add("; Structs too big for DllCall (Texture2D, Image, Font, Sound, Camera3D, ...) travel as")
    add("; a Buffer, which is what the loaders hand back and what these methods take again.")
    add("; Vector2, Vector3, Vector4 and Rectangle are plain numbers, and a function that")
    add("; returns one gives back an array: pos := RL.GetMousePosition().")
    add("; Fields of a nested struct carry their path in the accessor name, so the camera")
    add("; position is RL.Camera3D_PositionX(cam) and a render texture's color buffer is")
    add("; RL.RenderTexture2D_TextureId(rt). Pass a second argument to write the field:")
    add("; RL.Texture_Width(tex, 320). A field that is a pointer in C gives back the")
    add("; address, which any method taking that struct accepts: RL.SetMaterialTexture(")
    add("; RL.Model_Materials(model), RL.MATERIAL_MAP_DIFFUSE, tex).")
    add("; Every struct that DllCall could not pass goes through raylib_ahk_shim.dll, which")
    add("; sits next to raylib.dll and is loaded with it; without it only the plain-number")
    add("; functions work and the loaders are missing.")
    add(";")
    add(";     tex := RL.LoadTexture(\"player.png\")     ; load once and keep the Buffer")
    add(";     RL.DrawTexturePro(tex, 0, 0, 32, 32, 100, 100, 64, 64, 32, 32, 0, RL.WHITE)")
    add(";     RL.UnloadTexture(tex)")
    add(";     cps := RL.Codepoints(\"\u0151\u0171\")   ; one Int32 per character, only these get baked")
    add(";     font := RL.LoadFontEx(A_WinDir \"\\Fonts\\arial.ttf\", 32, cps, cps.Size // 4)")
    add(";     RL.DrawTextEx(font, \"\u0151\u0171\", 20, 20, 2, RL.DARKGRAY)   ; any Unicode")
    add(";     RL.UnloadFont(font)")
    add(";")
    add("; DrawTriangleFan wants its points counter-clockwise, raylib culls clockwise polygons.")
    add("; TakeScreenshot() wants a bare file name, resolves it against the directory raylib")
    add("; started in (its file code keeps a copy), and reads one buffer swap behind: set the")
    add("; working directory before InitWindow and draw the frame twice. RL.ScreenShot() is")
    add("; the way out: it takes a full path.")
    add(";")
    add("#Requires AutoHotkey v2.0")
    add("")
    add("class RL {")
    add('    static Version := "%s"' % version)
    add("")
    add("    ; ---------------------------------------------------------------- helpers")
    for line in HELPERS.lstrip("\n").rstrip().splitlines():
        add(line)

    for title, _ in SECTIONS:
        if not buckets[title]:
            continue
        add("")
        add("    ; ---------------------------------------------------------------- %s" % title)
        for plan in buckets[title]:
            add(plan.ahk())

    add("")
    add("    ; ---------------------------------------------------------------- struct buffers")
    add("    ; Loaders hand back one of these Buffers; the accessors read its fields, and the")
    add("    ; same Buffer goes straight back into any method taking that struct. Sizes and")
    add("    ; offsets come from the header and are checked against the compiled shim at")
    add("    ; include time, so a layout change fails loudly instead of drawing garbage.")
    for name in sorted(buffers):
        add("    ; %s (%d bytes)%s" % (name, layout.size(name),
                                       "" if not names_of.get(name) else
                                       ", also called " + ", ".join(sorted(names_of[name]))))
        for label in sorted([name] + names_of.get(name, [])):
            add("    static %s_Size := %d" % (label, layout.size(name)))
            for item in flat_fields(layout, name):
                # One method reads and writes: an empty rlValue means read. Zero is a
                # legitimate value and stays distinct from "" in AutoHotkey v2.
                add("    static %s_%s(rlBuf, rlValue := \"\") {" % (label, item["name"]))
                add("        if (rlValue != \"\")")
                add("            NumPut(\"%s\", rlValue, rlBuf, %d)" % (item["dt"], item["off"]))
                add("        return NumGet(rlBuf, %d, \"%s\")" % (item["off"], item["dt"]))
                add("    }")

    add("")
    add("    ; Compares the accessors above with sizeof()/offsetof() compiled into the shim.")
    add("    ; Rows rather than an object literal: in AutoHotkey 2.0.26 a plain object is")
    add("    ; only enumerable through OwnProps(), while arrays enumerate directly.")
    add("    static VerifyLayout() {")
    add("        static Wants := [")
    rows = []
    for name in sorted(buffers):
        want = [layout.size(name)] + [item["off"] for item in flat_fields(layout, name)]
        rows.append("            [\"%s\", %s]" % (name, ", ".join(str(v) for v in want)))
    add(",\n".join(rows))
    add("        ]")
    add("        for rlRow in Wants {")
    add("            rlBuf := Buffer(4 * (rlRow.Length - 1), 0)")
    add("            DllCall(\"raylib_ahk_shim\\rla_layout_\" rlRow[1], \"Ptr\", rlBuf)")
    add("            Loop rlRow.Length - 1")
    add("                if (NumGet(rlBuf, 4 * (A_Index - 1), \"UInt\") != rlRow[A_Index + 1])")
    add('                    throw Error("raylib.ahk: " rlRow[1] " layout no longer matches")')
    add("        }")
    add("    }")

    add("")
    add("    ; ---------------------------------------------------------------- constants")
    header = strip_comments(header_text)
    seen, values, rows = set(), {}, []
    for name, value in parse_defines(header) + parse_enums(header):
        if name.lower() in seen:
            continue
        seen.add(name.lower())
        values[name] = value
        rows.append("    static %-30s := %s" % (name, value))
    # A #define may name another constant instead of a number, which is how raylib
    # keeps old enum names working: MATERIAL_MAP_DIFFUSE is MATERIAL_MAP_ALBEDO. Two
    # passes, so an alias of an alias still resolves.
    alias = re.findall(r"#define\s+(\w+)\s+([A-Z]\w*)\s*$", header, re.M)
    for _pass in range(2):
        for name, target in alias:
            if name.lower() in seen or target not in values:
                continue
            seen.add(name.lower())
            values[name] = values[target]
            rows.append("    static %-30s := %s" % (name, values[target]))
    L.extend(rows)
    add("")
    add("    ; ---------------------------------------------------------------- colors")
    colors = parse_color_defines(header_text)
    for name, value, comment in colors:
        if name.lower() in seen:
            continue
        seen.add(name.lower())
        add("    static %-30s := %s  ; %s" % (name, value, comment))
    add("}")
    add("")
    add("RL.Init()")
    # utf-8-sig: AutoHotkey reads a script as UTF-8 only when it begins with a BOM.
    write_atomic(OUT_AHK, "\n".join(L) + "\n", encoding="utf-8-sig", newline="\r\n")
    return len(L), len(seen) - len(colors), len(colors)


def emit_c(version, layout, plans, buffers):
    L = ["// Autogenerated by tools/gen_wrapper.py from raylib.h (raylib %s). Do not edit by hand." % version,
         "// Build: powershell tools/build_shim.ps1  ->  lib/raylib_ahk_shim.dll",
         "//",
         "// AutoHotkey's DllCall cannot pass or return a struct larger than 8 bytes by value,",
         "// so each such raylib function gets a flat twin here: Vector2/Vector3/Vector4/",
         "// Rectangle become floats, other structs travel as pointers AutoHotkey owns, a",
         "// Color is one 0xAABBGGRR integer, and struct results are written through an out",
         "// pointer.",
         "#include <stddef.h>",
         '#include "raylib.h"',
         "",
         "#define RLA __declspec(dllexport)",
         ""]
    seen, count = set(), 0
    for plan in plans:
        src = plan.c()
        if src and plan.name not in seen:
            seen.add(plan.name)
            count += 1
            L += [src, ""]
    L.append("/* sizeof() and offsetof() straight from the compiler; RL.VerifyLayout() checks")
    L.append("   them against the accessor offsets generated into lib/raylib.ahk */")
    for name in sorted(buffers):
        L.append("RLA void rla_layout_%s(unsigned int *out) {" % name)
        L.append("    out[0] = (unsigned int)sizeof(%s);" % name)
        for i, item in enumerate(flat_fields(layout, name)):
            L.append("    out[%d] = %s;" % (i + 1, item["c"]))
        L.append("}")
    open(OUT_C, "w", encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
    return count


def emit_def(plans):
    """vendor/raylib.def: the exports the shim links against, from the header.

    tools/build_shim.ps1 turns this into an import library with lib.exe. The raylib
    release also ships raylib.lib, but that is the *static* library: linking it would
    put a second, private copy of raylib inside the shim, with window and texture
    state that the raylib.dll AutoHotkey calls into knows nothing about.
    """
    names = sorted({p.name for p in plans})
    text = ("; Autogenerated by tools/gen_wrapper.py: raylib exports used by shim.c\n"
            "LIBRARY raylib.dll\nEXPORTS\n"
            + "".join("    %s\n" % name for name in names))
    write_atomic(OUT_DEF, text, encoding="ascii")
    return len(names)


def emit_skipped(skipped, total, wrapped):
    with open(OUT_SKIPPED, "w") as fh:
        fh.write("raylib functions with no AutoHotkey binding, and why\n")
        fh.write("=" * 78 + "\n\n")
        by_reason = {}
        for plan in skipped:
            by_reason.setdefault(plan.reason, []).append(plan)
        for reason in sorted(by_reason, key=lambda r: (-len(by_reason[r]), r)):
            fh.write("%s (%d)\n%s\n" % (reason, len(by_reason[reason]), "-" * 78))
            for plan in sorted(by_reason[reason], key=lambda p: p.name):
                fh.write("  %-32s %s %s(%s)\n" % (plan.name, plan.ret, "", ", ".join(plan.argtypes)))
            fh.write("\n")
        fh.write("bound %d of %d\n" % (wrapped, total))


def write_atomic(path, text, encoding="utf-8", newline="\n"):
    """Replace a file in one step, so a reader never sees it half written. Returns False
    when the file already held these bytes and was left untouched.

    lib/raylib.ahk is ~190 KB and every demo #Includes it. Truncating it in place and then
    filling it leaves a window in which a script launched at that instant reads an empty
    file, or a line that stops after '#Include ', which AutoHotkey reports as
    'Failed to read text file' or 'Missing "#Include" directive argument'. Writing to a
    sibling temporary file and renaming it is atomic on the same volume: a reader gets
    either the whole old file or the whole new one.

    Windows refuses the rename outright while another process holds the file open without
    FILE_SHARE_DELETE, and for that instant a reader can be denied opening it at all -
    which AutoHotkey reports as 'Failed to read text file'. So the strongest guarantee is
    not to write when the bytes are unchanged, and they usually are: the generator is
    deterministic, so re-running it against an unchanged header yields identical output.
    """
    if newline != "\n":
        text = text.replace("\n", newline)        # same translation text mode would do
    data = text.encode(encoding)
    if os.path.exists(path):
        with open(path, "rb") as fh:
            if fh.read() == data:
                return False                       # unchanged: leave readers alone
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(data)
    for _attempt in range(40):
        try:
            os.replace(tmp, path)
            return True
        except PermissionError:
            time.sleep(0.05)
    raise SystemExit(
        "%s is open in another process, so the new %s could not take its place.\n"
        "Close the script or editor holding it (the temp file %s holds the new content)."
        % (path, os.path.basename(path), tmp)
    )


def main():
    header_text = open(HEADER, encoding="utf-8-sig", errors="replace").read()
    version = (re.search(r'#define\s+RAYLIB_VERSION\s+"([^"]+)"', header_text)
               or type("", (), {"group": lambda s, i: "unknown"})).group(1)

    structs = parse_structs(header_text)
    layout = Layout(structs, parse_aliases(header_text))
    for name, want in (("Vector2", 8), ("Vector3", 12), ("Vector4", 16), ("Rectangle", 16),
                       ("Matrix", 64), ("Color", 4)):
        if name in structs and layout.size(name) != want:
            raise SystemExit("layout model: %s computed %d bytes, expected %d"
                             % (name, layout.size(name), want))
    for name in FLATTEN:
        if name in structs and any(f[0] != "float" for f in structs[name]):
            raise SystemExit("%s is no longer all-float; drop it from FLATTEN" % name)

    funcs = parse_funcs(header_text)
    plans, skipped = [], []
    for func in funcs:
        plan = Plan(func, layout).build()
        (plans if plan.ok else skipped).append(plan)

    buckets = {title: [] for title, _ in SECTIONS}
    for plan in plans:
        for title, pred in SECTIONS:
            if pred(plan.name):
                buckets[title].append(plan)
                break

    buffers = []
    for plan in plans:
        for name in plan.buffers:
            if name not in buffers:
                buffers.append(name)
    buffers = [n for n in buffers if n in structs]

    lines, n_const, n_colors = emit_ahk(version, layout, buckets, plans, buffers, header_text)
    n_c = emit_c(version, layout, plans, buffers)
    n_def = emit_def(plans)
    emit_skipped(skipped, len(funcs), len(plans))

    print("bound %d of %d raylib functions (%d flat shim wrappers, %d struct accessors)"
          % (len(plans), len(funcs), n_c, len(buffers)))
    for title, _ in SECTIONS:
        if buckets[title]:
            print("  %-22s %3d" % (title, len(buckets[title])))
    print("constants %d, colors %d, %d lines -> %s" % (n_const, n_colors, lines, OUT_AHK))
    print("shim: %d wrappers, %d exports -> %s" % (n_c, n_def, OUT_C))
    direct = sum(1 for p in plans if not p.shim)
    print("direct %d, through the shim %d, left out %d" % (direct, len(plans) - direct, len(skipped)))


if __name__ == "__main__":
    main()
