# raylib_ahk

AutoHotkey v2 bindings for [raylib](https://www.raylib.com) 5.5. `lib\raylib.ahk`
is a generated `RL` class over `raylib.dll`, so any AHK script can open a window
and draw with hardware-accelerated shapes and text:

```autohotkey
#Requires AutoHotkey v2.0
#Include ..\lib\raylib.ahk

RL.InitWindow(800, 450, "raylib + AutoHotkey")
RL.SetTargetFPS(60)

while !RL.WindowShouldClose() {
    RL.BeginDrawing()
    RL.ClearBackground(RL.RAYWHITE)
    RL.DrawCircle(RL.GetMouseX(), RL.GetMouseY(), 40, RL.MAROON)
    RL.DrawText("esc to quit", 10, 10, 20, RL.DARKGRAY)
    RL.DrawFPS(10, 40)
    RL.EndDrawing()
}

RL.CloseWindow()
```

Run it (the `/ErrorStdOut` keeps load errors on the console instead of a dialog):

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut examples\demo.ahk
```

`examples\demo.ahk` is a small physics toy: WASD/arrows nudge the ball, holding
the left mouse button springs it towards the cursor, `C` changes color, `R`
resets, `Esc` quits. It also runs unattended for automation: `/auto:2000` closes
after 2 seconds, `/shot:name.png` writes a framebuffer capture before closing.

## Layout

| Path | |
|---|---|
| `lib\raylib.ahk` | the wrapper. Generated, do not edit by hand |
| `lib\raylib.dll` | raylib 5.5 win64 MSVC build |
| `vendor\raylib.h` | the header the wrapper is generated from |
| `tools\gen_wrapper.py` | generator (`python tools\gen_wrapper.py`) |
| `tools\get_raylib.ps1` | re-downloads the DLL and header |
| `tools\skipped.txt` | every raylib function that is not wrapped, with its signature |
| `tests\smoke.ahk` | self-checking test, exits non-zero on the first failure |
| `legacy\` | the original hand-written wrapper, kept for reference |

`raylib.dll` is loaded from beside `raylib.ahk` when the file is included, so no
`SetWorkingDir` or `#DllLoad` is needed.

## Colors

Colors are plain `0xRRGGBBAA` integers, the same order as raylib's own constants
and `ColorToInt()`, and the constants match raylib's palette:

```autohotkey
RL.DrawRectangle(50, 50, 100, 40, RL.RED)              ; 0xE62937FF
RL.DrawRectangle(50, 50, 100, 40, 0x00FF00FF)          ; green
RL.DrawRectangle(50, 50, 100, 40, RL.Alpha(RL.RED, .5)) ; 50% transparent
```

A `Color` is a 4 byte struct, which the x64 ABI passes in a register, so no
marshalling is involved: `RL.ABGR()` just reorders the bytes into the layout raylib
expects. `tests\smoke.ahk` asserts that reordering against raylib's own `GetColor()`.

## What is covered

148 raylib functions, generated straight from `raylib.h`, grouped like the header:

- **window**: `InitWindow`, `WindowShouldClose`, `SetConfigFlags`, monitor and
  size/position/state queries, clipboard (UTF-8 both ways)
- **input**: keyboard (`IsKeyPressed`, `IsKeyDown`, `GetCharPressed`, ...),
  mouse, gamepad, touch, gestures
- **shapes**: pixels, lines, beziers, circles, ellipses, rings, rectangles,
  gradients, triangles, polygons and splines that take a point array
- **text**: `DrawText`, `MeasureText`, `DrawFPS`, `SetTextLineSpacing`
- **timing/misc**: `SetTargetFPS`, `GetFrameTime`, `GetTime`, `GetFPS`, `WaitTime`,
  `TakeScreenshot`, `OpenURL`, files and paths, cursor, blend/scissor modes,
  audio device on/off and master volume

All raylib enums (`KEY_*`, `MOUSE_BUTTON_*`, `GAMEPAD_*`, `FLAG_*`, `GESTURE_*`,
`PIXELFORMAT_*`, ...) and the standard palette are included as `RL.*` constants.
For anything else, `RL.Raw()` is a thin `DllCall` passthrough:

```autohotkey
value := RL.Raw("GetColor", "UInt", 0xE62937FF, "UInt")
```

## What cannot work, and why

AutoHotkey's `DllCall` can pass scalars and pointers, but it cannot place a
struct **larger than 8 bytes by value** into an argument register or stack slot.
Most of raylib's texture, font, 3D and audio API takes or returns structs like
that, so it is unreachable from AHK without an intermediate C shim. Concretely:

```c
Texture2D LoadTexture(const char *fileName);                         // 28 byte return
void DrawTexturePro(Texture2D t, Rectangle s, Rectangle d, ...);      // 28 + 16 + 16 byte params
void DrawTextEx(Font f, const char *t, Vector2 p, ...);               // 36 byte Font
void BeginMode3D(Camera3D camera);                                   // 64 byte Camera3D
```

That accounts for most of the 433 functions that are not wrapped; `tools\skipped.txt`
lists every one of them (a few are callable but left out on purpose, because AHK
does them better natively). The rest of raylib still gives a complete immediate-mode
2D renderer: anything made of rectangles, circles, polygons, lines and text, with
full input and timing. Functions that *return* the small `Color` struct also work
through `RL.Raw()` with an explicit integer return type.

## Behaviour worth knowing

- **Strings are UTF-8.** The wrapper converts AHK's UTF-16 to UTF-8 on the way in
  (`"AStr"` would use the system codepage and mangle non-ASCII) and back on the way out.
- **The default font is ASCII only.** UTF-8 reaches raylib intact, but glyphs
  above codepoint 126 come out as blanks until you load a font, and `LoadFontEx`
  returns a `Font` struct, which `DllCall` cannot receive. Use `DrawText` with
  ASCII, or add a shim DLL for custom fonts.
- **`Array.Delete(1)` does not shrink `Length`.** It leaves a hole; only
  `Array.RemoveAt(1, 2)` shifts the array down. A `while Length > n` trim loop
  built on `Delete` spins forever and freezes the window at the frame the cap is
  reached (this is what the first version of the demo did, at about one second).
- **`TakeScreenshot()` writes into the process working directory.** It drops the
  directory part of the name it is given, so `SetWorkingDir()` first.
- **A screenshot is one buffer swap behind.** raylib flushes its draw batch inside
  `EndDrawing()`, and the framebuffer readback returns the buffer that was
  presented on the previous swap. To capture a frame, draw it, `EndDrawing()`,
  draw it once more, `EndDrawing()`, then take the shot. The demo and the smoke
  test both do this.
- **Point arrays must be counter-clockwise** for `DrawTriangleFan`; raylib culls
  clockwise polygons and the fan silently draws nothing otherwise.
- **The BMP that `TakeScreenshot()` exports** is 32 bit, bottom-up, stored B,G,R.
  `tests\smoke.ahk` contains a small parser for it (`LoadBmp`), handy for checks.

## Tests

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut tests\smoke.ahk 2>&1
```

41 checks, exit code 0 on success. It opens an undecorated unfocused 320x240
window, draws one shape of each kind, captures the frame with raylib itself and
verifies the pixels, so the ABI assumptions the wrapper depends on are tested
against real rendered output rather than against the header: color byte order
(including 50% alpha blending), `bool` results being read from `AL` only, float
returns, UTF-8 round-trips, `const Vector2 *` point arrays, and screenshot timing.
Artifacts land in `tests\out\` (`smoke.bmp`, `smoke.png`).

## Regenerating

```powershell
python tools\get_raylib.ps1 -Version 5.5   # optional: fetch DLL + header
python tools\gen_wrapper.py                # regenerate lib\raylib.ahk
```

The generator parses `vendor\raylib.h` for prototypes, enums and `CLITERAL(Color)`
palette entries, keeps the functions `DllCall` can reach, maps C types to DllCall
types (`bool` to `"Char"`, `Color` to `"UInt"` through `RL.ABGR()`, `const char *`
to a UTF-8 `Buffer`), and renames parameters to `rl*` so a user's global variable
can never trip AHK's `LocalSameAsGlobal` warning inside the library.

## License

MIT, as raylib and the original repository are.
