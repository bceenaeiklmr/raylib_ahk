; Smoke test for lib\raylib.ahk. Headless-safe: no dialogs, prints failures to
; stdout and exits non-zero if any check fails.
;
;   & 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut tests\smoke.ahk 2>&1
;
; The pattern is captured with raylib's own TakeScreenshot() and verified by
; parsing the BMP in AutoHotkey, so the ABI assumptions the wrapper is built on
; (Color byte order, bool in AL, float args, UTF-8 strings, const Vector2 *
; point arrays) are all checked against pixels that really got rendered.
;
; Screenshot timing, measured on this machine (see README):
;   - raylib batches draw calls and flushes them inside EndDrawing(), so a shot
;     taken mid-frame only shows ClearBackground();
;   - the framebuffer readback is the buffer that was presented one swap earlier.
; So every frame is drawn twice and the shot is taken after the second swap.
#Requires AutoHotkey v2.0
#Warn All, StdOut
#SingleInstance Force

OnError(HeadlessErrorHandler)
SetTimer(Watchdog, -30000)

#Include ..\lib\raylib.ahk

WinW := 320, WinH := 240
OutDir := A_ScriptDir "\out"
DirCreate(OutDir)
; TakeScreenshot() drops the directory part of the name and writes into the
; process working directory, so point that at the output folder first.
SetWorkingDir(OutDir)
Checks := 0, Fails := 0

RL.SetTraceLogLevel(RL.LOG_WARNING)
RL.SetConfigFlags(RL.FLAG_WINDOW_UNFOCUSED | RL.FLAG_WINDOW_UNDECORATED)
RL.InitWindow(WinW, WinH, "raylib.ahk smoke test")

; ---------------------------------------------------------------- API sanity
Check(RL.IsWindowReady(), "IsWindowReady")
Check(RL.GetScreenWidth() == WinW, "GetScreenWidth == " WinW)
Check(RL.GetScreenHeight() == WinH, "GetScreenHeight == " WinH)
Check(RL.GetRenderWidth() > 0, "GetRenderWidth > 0")
Check(RL.GetMonitorCount() >= 1, "GetMonitorCount >= 1")
Check(RL.GetMonitorName(RL.GetCurrentMonitor()) != "", "GetMonitorName returns UTF-8 text")
Check(RL.FileExists(A_ScriptDir "\..\lib\raylib.dll"), "FileExists(raylib.dll)")
Check(RL.GetFileLength(A_ScriptDir "\..\lib\raylib.dll") > 1000000, "GetFileLength(raylib.dll)")
Check(RL.GetFileName("C:\tmp\hero.txt") == "hero.txt", "GetFileName")
Check(RL.GetFileExtension("C:\tmp\hero.txt") == ".txt", "GetFileExtension")
Check(RL.GetWorkingDirectory() == OutDir, "GetWorkingDirectory")

; bool results live in AL only; reading EAX would leak garbage into the number.
Check(RL.IsKeyDown(RL.KEY_A) == 0, "IsKeyDown(KEY_A) is exactly 0")
Check(RL.IsMouseButtonDown(RL.MOUSE_BUTTON_LEFT) == 0, "IsMouseButtonDown is exactly 0")
Check(RL.GetRandomValue(7, 9) >= 7, "GetRandomValue(7,9) in range")

; A Color is a 4 byte struct returned in RAX. raylib's own GetColor() is the
; oracle for the byte order every draw call in the wrapper depends on.
Check(RL.Raw("GetColor", "UInt", RL.RED, "UInt") == RL.ABGR(RL.RED),
    "ABGR() agrees with raylib GetColor(), got " Hex(RL.Raw("GetColor", "UInt", RL.RED, "UInt")))
Check(RL.ABGR(RL.ABGR(RL.SKYBLUE)) == RL.SKYBLUE, "ABGR() is its own inverse")
Check(RL.Alpha(RL.RED, 0) == (RL.RED & 0xFFFFFF00), "Alpha() rewrites the alpha byte")

; Clipboard round-trip proves the UTF-8 conversion in both directions. The text is
; built with Chr() so this file stays pure ASCII: AutoHotkey only reads a script as
; UTF-8 when it carries a byte-order mark.
Probe := Chr(225) Chr(337) Chr(369) Chr(246) " " Chr(26085) Chr(26412) Chr(35486)
RL.SetClipboardText(Probe)
got := RL.GetClipboardText()
Check(got == Probe, "clipboard round-trips UTF-8, got [" got "]")

; ---------------------------------------------------------------- rendered output
DrawPattern()
DrawPattern()
ShotName := "smoke.bmp"
Shot := OutDir "\" ShotName
if (FileExist(Shot) != "")
    FileDelete(Shot)
RL.TakeScreenshot(ShotName)
Check(FileExist(Shot) != "", "TakeScreenshot wrote " ShotName)

px := LoadBmp(Shot)
if (px == 0) {
    Fail("could not parse " Shot)
} else {
    Check(px.W == WinW && px.H == WinH, "screenshot is " WinW "x" WinH)
    Expect(px, 4, 4, RL.RED, "rect top-left")
    Expect(px, WinW - 4, 4, RL.BLUE, "rect top-right")
    Expect(px, 4, WinH - 4, RL.LIME, "rect bottom-left")
    Expect(px, WinW - 4, WinH - 4, RL.YELLOW, "rect bottom-right")
    Expect(px, 160, 120, RL.MAROON, "circle center")
    Expect(px, 160, 60, RL.PURPLE, "ellipse center")
    Expect(px, 160, 75, RL.PURPLE, "ellipse fills down to radiusV")
    Expect(px, 250, 40, RL.GOLD, "DrawTriangleFan quad (point array)")
    Expect(px, 70, 120, RL.SKYBLUE, "DrawLine midpoint")
    Expect(px, 2, 120, RL.BLACK, "background stays black")
    Check(FindColor(px, 99, 99, 112, 112, RL.WHITE) != "", "DrawRectangleLines outline")
    Check(FindColor(px, 30, 200, 130, 235, RL.WHITE) != "", "DrawText rendered glyphs")
    Check(FindColor(px, 38, 165, 135, 200, RL.PINK) != "", "DrawLineStrip (point array)")
    ExpectNear(px, 215, 220, 0x7F7F7F, 6, "50% white over black blends")
    top := px.Get(260, 103), bot := px.Get(260, 156)
    Check(RGB(top) != RGB(bot) && Red(top) > 100 && Blue(bot) > 100,
        "DrawRectangleGradientV blends " RGBStr(top) " -> " RGBStr(bot))
    Check(RL.MeasureText("ABC", 20) > 10, "MeasureText > 0")
}

; A PNG copy for eyeballing; TakeScreenshot() picks the format from the extension.
DrawShowcase()
DrawShowcase()
RL.TakeScreenshot("smoke.png")

; ---------------------------------------------------------------- textures & fonts
; Texture2D is 20 bytes and Font 48, so nothing in this section is reachable through
; plain DllCall: every one of these calls goes through the generated shim.
FontFile := FindTtf()
if (FontFile == "") {
    Fail("no TrueType font found in " A_WinDir "\Fonts")
} else {
    Sheet := RL.GenImageColor(16, 8, RL.WHITE)
    Check(RL.Image_Width(Sheet) == 16 && RL.Image_Height(Sheet) == 8,
        "GenImageColor and the Image accessors")
    RL.ImageDrawRectangle(Sheet, 0, 0, 8, 8, RL.RED)
    Tex := RL.LoadTextureFromImage(Sheet)
    Check(RL.Texture2D_Id(Tex) != 0, "LoadTextureFromImage returned a texture id")
    Check(RL.Texture2D_Width(Tex) == 16 && RL.Texture2D_Height(Tex) == 8, "Texture2D accessors")

    ; a font with only the two Hungarian glyphs in it, which the default font lacks
    Cps := RL.Codepoints(Chr(337) Chr(369))
    Check(Cps.Size == 8 && NumGet(Cps, 0, "Int") == 337, "Codepoints packs UTF-16 as Int32")
    Font := RL.LoadFontEx(FontFile, 32, 0, 0)
    Check(RL.Font_GlyphCount(Font) > 90, "LoadFontEx baked the default set")
    Font2 := RL.LoadFontEx(FontFile, 32, Cps, Cps.Size // 4)
    Check(RL.Font_GlyphCount(Font2) == 2, "LoadFontEx with an explicit codepoint list")
    Box := RL.MeasureTextEx(Font, "AWAY", 32, 2)
    Check(Box.Length == 2 && Box[1] > 40 && Box[2] > 10,
        "MeasureTextEx returns [width, height], got " Box[1] "x" Box[2])

    Cam := RL.MakeCamera3D([0, 4, 8], [0, 0, 0], [0, 1, 0], 50, RL.CAMERA_PERSPECTIVE)
    Check(RL.Camera3D_PositionZ(Cam) == 8 && RL.Camera3D_TargetY(Cam) == 0
        && RL.Camera3D_UpY(Cam) == 1 && RL.Camera3D_Fovy(Cam) == 50,
        "MakeCamera3D agrees with the accessors")

    DrawMedia()
    DrawMedia()
    RL.TakeScreenshot("media.bmp")
    mp := LoadBmp(OutDir "\media.bmp")
    if (mp == 0) {
        Fail("could not parse media.bmp")
    } else {
        Expect(mp, 12, 12, RL.RED, "texture drawn 1:1 keeps its own color")
        Expect(mp, 20, 32, RL.SKYBLUE, "white texture under a SKYBLUE tint")
        Expect(mp, 84, 34, RL.WHITE, "DrawTexturePro samples the src rectangle only")
        Expect(mp, 20, 12, RL.WHITE, "the untouched half of the sheet stays white")
        Check(FindColor(mp, 10, 80, 200, 105, RL.BLACK) != "", "DrawTextEx rendered a custom font")
        ; the default font has no room for those two, so raylib substitutes its
        ; fallback glyph and the run measures exactly as wide as two question marks
        Fallback := RL.MeasureTextEx(Font, "??", 32, 2)
        Missing := RL.MeasureTextEx(Font, Chr(337) Chr(369), 32, 2)
        Custom := RL.MeasureTextEx(Font2, Chr(337) Chr(369), 32, 2)
        Check(Custom[1] > 0 && Custom[2] > 10, "the two custom glyphs have a real advance")
        Check(Abs(Fallback[1] - Missing[1]) < 2, "default font falls back to a placeholder glyph")
        Check(RL.GetGlyphIndex(Font2, 337) != RL.GetGlyphIndex(Font2, 369),
            "GetGlyphIndex gives each baked glyph its own index")
        Check(CountDark(mp, 10, 165, 200, 200) > 20, "custom font draws the Hungarian glyphs")
    }

    RL.UnloadTexture(Tex)
    RL.UnloadImage(Sheet)
    RL.UnloadFont(Font)
    RL.UnloadFont(Font2)
}

; TakeScreenshot() refuses full paths; RL.ScreenShot() takes one, by exporting the
; Image from LoadImageFromScreen(). Reading the file back proves it was written.
ApiShot := OutDir "\api_shot.png"
FileExist(ApiShot) && FileDelete(ApiShot)
RL.ScreenShot(ApiShot)
Shot2 := RL.LoadTexture(ApiShot)
if (Shot2 == 0) {
    Fail("RL.ScreenShot wrote no readable image")
} else {
    Check(RL.Texture_Width(Shot2) == WinW && RL.Texture_Height(Shot2) == WinH,
        "RL.ScreenShot exported the whole framebuffer to a full path")
    RL.UnloadTexture(Shot2)
}

; ---------------------------------------------------------------- 3D and audio
; Both need structs that DllCall cannot pass: Camera3D is 44 bytes and Wave 24.
Cam := RL.MakeCamera3D([0, 2, 5], [0, 0.5, 0], [0, 1, 0], 45, RL.CAMERA_PERSPECTIVE)
DrawScene3D(Cam, -2.0)
DrawScene3D(Cam, -2.0)
RL.TakeScreenshot("scene_left.bmp")
DrawScene3D(Cam, 2.0)
DrawScene3D(Cam, 2.0)
RL.TakeScreenshot("scene_right.bmp")
sl := LoadBmp(OutDir "\scene_left.bmp")
sr := LoadBmp(OutDir "\scene_right.bmp")
if (sl == 0 || sr == 0) {
    Fail("could not parse the 3D screenshots")
} else {
    Check(FindColor(sl, 4, 60, WinW // 2, WinH - 40, RL.RED) != "",
        "the cube projects left when its x is negative")
    Check(FindColor(sr, WinW // 2, 60, WinW - 4, WinH - 40, RL.RED) != "",
        "the cube projects right when its x is positive")
    Check(CountNot(sl, 8, 150, WinW - 8, WinH - 30, RL.RAYWHITE >> 8) > 150,
        "DrawGrid painted the ground plane")
}

WavPath := OutDir "\tone.wav"
Frames := WriteWav(WavPath)
Wave := RL.LoadWave(WavPath)
if (Wave == 0) {
    Fail("LoadWave could not read the generated WAV")
} else {
    Check(RL.Wave_FrameCount(Wave) == Frames, "LoadWave decoded the generated WAV")
    ; raudio reports sampleSize in bits, not bytes
    Check(RL.Wave_Data(Wave) != 0 && RL.Wave_SampleRate(Wave) == 44100
        && RL.Wave_Channels(Wave) == 1 && RL.Wave_SampleSize(Wave) == 16,
        "the Wave accessors agree with the file")
    RL.InitAudioDevice()
    if RL.IsAudioDeviceReady() {
        Snd := RL.LoadSoundFromWave(Wave)
        Check(RL.IsSoundValid(Snd), "LoadSoundFromWave")
        RL.SetSoundVolume(Snd, 0.0)   ; the whole audio path runs, silently
        RL.PlaySound(Snd)
        Check(RL.IsSoundPlaying(Snd), "PlaySound")
        RL.StopSound(Snd)
        Check(!RL.IsSoundPlaying(Snd), "StopSound")
        RL.UnloadSound(Snd)
    }
    RL.UnloadWave(Wave)
    RL.CloseAudioDevice()
}

; ---------------------------------------------------------------- timing
Check(RL.GetTime() > 0.0, "GetTime > 0")
Check(RL.GetFrameTime() > 0.0, "GetFrameTime > 0")
Check(RL.GetFPS() >= 0, "GetFPS >= 0")

; The demo's trail trim depends on this: Delete only punches a hole, so Length
; never shrinks and a `while Length > n` guard spins forever with the window
; frozen. Only RemoveAt shifts the array down.
Tr := []
Loop 100
    Tr.Push(A_Index, A_Index)
Tr.Delete(1)
Check(Tr.Length == 200, "Array.Delete leaves Length unchanged")
Tr.RemoveAt(1, 2)
Check(Tr.Length == 198, "Array.RemoveAt shifts and shrinks Length")

RL.CloseWindow()

FileAppend("checks: " Checks ", failures: " Fails "`n", "*")
ExitApp(Fails ? 1 : 0)

; ---------------------------------------------------------------- frames
; Every drawable is exercised once here, in screen coordinates.
DrawPattern() {
    global RL, WinW, WinH
    RL.BeginDrawing()
    RL.ClearBackground(RL.BLACK)
    RL.DrawRectangle(0, 0, 32, 32, RL.RED)
    RL.DrawRectangle(WinW - 32, 0, 32, 32, RL.BLUE)
    RL.DrawRectangle(0, WinH - 32, 32, 32, RL.LIME)
    RL.DrawRectangle(WinW - 32, WinH - 32, 32, 32, RL.YELLOW)
    RL.DrawCircle(160, 120, 30, RL.MAROON)
    RL.DrawEllipse(160, 60, 40, 20, RL.PURPLE)
    RL.DrawRectangleLines(100, 100, 60, 40, RL.WHITE)
    RL.DrawLine(40, 120, 110, 120, RL.SKYBLUE)
    RL.DrawRectangleGradientV(240, 100, 40, 60, RL.RED, RL.BLUE)
    ; raylib culls clockwise point lists here, so the fan is listed counter-clockwise
    RL.DrawTriangleFan([220, 80, 280, 80, 280, 20, 220, 20], RL.GOLD)
    RL.DrawLineStrip([40, 170, 70, 190, 100, 170, 130, 190], RL.PINK)
    RL.DrawText("ABC", 40, 205, 20, RL.WHITE)
    ; half transparent white over black: proves the alpha byte lands where it should
    RL.DrawRectangle(200, 205, 30, 30, RL.Alpha(RL.WHITE, 0.5))
    RL.EndDrawing()
}

DrawShowcase() {
    global RL, WinW, WinH
    RL.BeginDrawing()
    RL.ClearBackground(RL.RAYWHITE)
    RL.DrawCircle(WinW // 2, WinH // 2, 50, RL.MAROON)
    RL.DrawLineStrip([20, 200, 90, 170, 160, 210, 300, 160], RL.SKYBLUE)
    RL.DrawText("raylib " RL.Version " + AutoHotkey " A_AhkVersion, 10, 10, 20, RL.DARKGRAY)
    RL.DrawText("shapes, text and input from AutoHotkey", 10, 40, 20, RL.MAROON)
    RL.DrawFPS(10, WinH - 30)
    RL.EndDrawing()
}

; Textures and fonts, placed so every check below has its own band of rows.
DrawMedia() {
    global RL, Tex, Font, Font2
    RL.BeginDrawing()
    RL.ClearBackground(RL.RAYWHITE)
    ; rows 10..17: the sheet 1:1 (left half red, right half white)
    RL.DrawTexture(Tex, 10, 10, RL.WHITE)
    ; rows 30..37: the same sheet tinted, so the white pixels show the tint exactly
    RL.DrawTexture(Tex, 10, 30, RL.SKYBLUE)
    ; src rect (8,0,8,8), the white half, scaled up to 48x48 at 60,10
    RL.DrawTexturePro(Tex, 8, 0, 8, 8, 60, 10, 48, 48, 0, 0, 0, RL.WHITE)
    RL.DrawTextEx(Font, "AWAY", 10, 80, 32, 2, RL.BLACK)
    RL.DrawText(Chr(337) Chr(369), 10, 130, 32, RL.BLACK)
    RL.DrawTextEx(Font2, Chr(337) Chr(369), 10, 170, 32, 2, RL.BLACK)
    RL.EndDrawing()
}

; Any TrueType font will do; Windows always ships a few.
FindTtf() {
    for Name in ["arial.ttf", "tahoma.ttf", "segoeui.ttf", "calibri.ttf"] {
        if FileExist(A_WinDir "\Fonts\" Name)
            return A_WinDir "\Fonts\" Name
    }
    Loop Files A_WinDir "\Fonts\*.ttf" {
        return A_LoopFileShortPath
    }
    return ""
}

; Pixels whose color differs from a given one in a region.
CountNot(P, X0, Y0, X1, Y1, Want) {
    local n, x, y
    n := 0
    Loop (Y1 - Y0) {
        y := Y0 + A_Index - 1
        Loop (X1 - X0) {
            x := X0 + A_Index - 1
            if (P.Get(x, y) != Want)
                n++
        }
    }
    return n
}

; A 3D view of one cube; CubeX moves it across the screen.
DrawScene3D(Cam, CubeX) {
    global RL, WinW, WinH
    RL.BeginDrawing()
    RL.ClearBackground(RL.RAYWHITE)
    RL.BeginMode3D(Cam)
    RL.DrawGrid(10, 1.0)
    RL.DrawCube(CubeX, 0.5, 0, 1.0, 1.0, 1.0, RL.RED)
    RL.DrawCubeWires(CubeX, 0.5, 0, 1.0, 1.0, 1.0, RL.MAROON)
    RL.EndMode3D()
    RL.EndDrawing()
}

; Four ASCII bytes into a Buffer at an offset (StrPut has no position parameter).
PutTag(Chars, Buf, Pos) {
    local i
    Loop 4
        NumPut("UChar", Ord(SubStr(Chars, A_Index, 1)), Buf, Pos + A_Index - 1)
}

; Write a 16 bit mono WAV so the audio path can be tested without shipping a file.
; Returns the number of frames, which is what Wave_FrameCount must report.
WriteWav(Path, Hz := 440.0, Seconds := 0.1, Rate := 44100) {
    local n, buf, h, k, TwoPi
    n := Rate * Seconds
    buf := Buffer(44 + n * 2, 0)
    PutTag("RIFF", buf, 0)
    NumPut("UInt", 36 + n * 2, buf, 4)
    PutTag("WAVE", buf, 8)
    PutTag("fmt ", buf, 12)
    NumPut("UInt", 16, buf, 16)            ; fmt chunk size
    NumPut("UShort", 1, buf, 20)           ; PCM
    NumPut("UShort", 1, buf, 22)           ; mono
    NumPut("UInt", Rate, buf, 24)
    NumPut("UInt", Rate * 2, buf, 28)      ; bytes per second
    NumPut("UShort", 2, buf, 32)           ; block align
    NumPut("UShort", 16, buf, 34)          ; bits per sample
    PutTag("data", buf, 36)
    NumPut("UInt", n * 2, buf, 40)
    TwoPi := 6.283185307179586
    Loop n {
        k := A_Index - 1
        NumPut("Short", Round(Sin(TwoPi * k * Hz / Rate) * 12000), buf, 44 + k * 2)
    }
    h := FileOpen(Path, "w")
    h.RawWrite(buf, buf.Size)
    h.Close()
    return n
}

; Pixels darker than mid grey in a region: text renders as dark ink on RAYWHITE.
CountDark(P, X0, Y0, X1, Y1) {
    local n, x, y, c
    n := 0
    Loop (Y1 - Y0) {
        y := Y0 + A_Index - 1
        Loop (X1 - X0) {
            x := X0 + A_Index - 1
            c := P.Get(x, y)
            if (((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF)) < 240
                n++
        }
    }
    return n
}

; ---------------------------------------------------------------- helpers
Check(Cond, What) {
    global Checks
    Checks++
    if !Cond
        Fail(What)
}

Fail(What) {
    global Fails
    Fails++
    FileAppend("FAIL  " What "`n", "*")
}

Hex(Value) => Format("0x{:08X}", Value)

; Parse the uncompressed 24/32 bit BMP that raylib exports. Rows are bottom-up
; and the bytes are B,G,R,(A); Get(x, y) returns 0xRRGGBB.
LoadBmp(Path) {
    local bytes, offBits, w, h, bpp, stride
    bytes := FileRead(Path, "RAW")
    if (bytes.Size < 54 || NumGet(bytes, 0, "UShort") != 0x4D42)  ; "BM"
        return 0
    offBits := NumGet(bytes, 10, "UInt")
    w := NumGet(bytes, 18, "Int")
    h := NumGet(bytes, 22, "Int")
    bpp := NumGet(bytes, 28, "UShort")
    if (h < 0)
        h := -h  ; top-down BMP, not produced by raylib but cheap to allow
    if !(bpp == 32 || bpp == 24)
        return 0
    stride := w * (bpp // 8)
    return {W: w, H: h, Bytes: bytes, Off: offBits, Stride: stride, Bpp: bpp, Get: BmpPixel}
}

BmpPixel(P, X, Y) {
    local o
    o := P.Off + (P.H - 1 - Y) * P.Stride + X * (P.Bpp // 8)
    if (o + 2 >= P.Bytes.Size)
        throw Error("BMP pixel out of range: " X "," Y)
    return (NumGet(P.Bytes, o + 2, "UChar") << 16) | (NumGet(P.Bytes, o + 1, "UChar") << 8)
        | NumGet(P.Bytes, o, "UChar")
}

; Compare a rendered pixel with a 0xRRGGBB expected color, within a tolerance.
ExpectNear(P, X, Y, Color, Tolerance, What) {
    local got, d, worst
    got := P.Get(X, Y)
    worst := 0
    for Shift in [16, 8, 0] {
        d := Abs(((got >> Shift) & 0xFF) - ((Color >> Shift) & 0xFF))
        if (d > worst)
            worst := d
    }
    Check(worst <= Tolerance, What " at " X "," Y ": got " RGBStr(got)
        ", want " RGBStr(Color) " +/" Tolerance " (off " worst ")")
}

; Compare a rendered pixel with a 0xRRGGBBAA expected color.
Expect(P, X, Y, Color, What) {
    local got, want
    got := P.Get(X, Y)
    want := Color >> 8
    Check(got == want, What " at " X "," Y ": got " RGBStr(got) ", want " RGBStr(want))
}

; Find an exact color inside a region, return "x,y" or "".
FindColor(P, X0, Y0, X1, Y1, Color) {
    local want, x, y
    want := Color >> 8
    Loop (Y1 - Y0) {
        y := Y0 + A_Index - 1
        Loop (X1 - X0) {
            x := X0 + A_Index - 1
            if (P.Get(x, y) == want)
                return x "," y
        }
    }
    return ""
}

RGB(Color) => Color & 0xFFFFFF
Red(Color) => (Color >> 16) & 0xFF
Blue(Color) => Color & 0xFF
RGBStr(Color) => Format("0x{:06X}", Color & 0xFFFFFF)

Watchdog() => ExitApp(101)

HeadlessErrorHandler(err, mode) {
    FileAppend("[ERROR] " err.Message "`n"
        . "File: " err.File " (Line " err.Line ")`n"
        . "Stack:`n" err.Stack "`n", "**")
    ExitApp(1)
}
