; Textured 3D cube, orbiting camera, and a Hungarian caption from a system TTF.
; Everything in this file needs the generated shim: Texture, Mesh, Model, Font and
; Camera3D are structs too big for DllCall to pass.
;
;   & 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut examples\cube.ahk
;   & 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut examples\cube.ahk /auto:3000 /shot:cube
;
; /auto[:ms]  close the window by itself (default 3000 ms)
; /shot:name  write tests\out\name.png just before closing
#Requires AutoHotkey v2.0
#Warn All, StdOut
#SingleInstance Force

OnError(CubeErrorHandler)

#Include ..\lib\raylib.ahk

AutoExit := 0, ShotName := ""
for Arg in A_Args {
    if (SubStr(Arg, 1, 5) = "/auto") {
        Colon := InStr(Arg, ":")
        AutoExit := Colon ? Integer(SubStr(Arg, Colon + 1)) : 3000
    } else if (SubStr(Arg, 1, 5) = "/shot") {
        Colon := InStr(Arg, ":")
        ShotName := Colon ? SubStr(Arg, Colon + 1) : "cube"
    }
}
if (ShotName != "" && !InStr(ShotName, "."))
    ShotName .= ".png"   ; raylib picks the format from the extension
ShotPath := ""
if (ShotName != "") {
    ; Set the directory before InitWindow (raylib keeps a copy of it) and let
    ; A_WorkingDir resolve the "..", so the path handed to ScreenShot is plain.
    SetWorkingDir A_ScriptDir "\..\tests\out"
    ShotPath := A_WorkingDir "\" ShotName
}

Width := 800, Height := 480
Caption := "A kocka forog - o, u, oe, ue: ő ű Ő Ű"

; vsync paces the loop better than SetTargetFPS, which overshoots its budget on
; Windows because the sleep clock ticks every ~15.6 ms.
RL.SetConfigFlags(RL.FLAG_VSYNC_HINT)
RL.InitWindow(Width, Height, "raylib.ahk - 3D, textures and TrueType fonts")

; A checkerboard made in RAM, so the example ships without asset files.
Img := RL.GenImageChecked(128, 128, 4, 4, RL.SKYBLUE, RL.RAYWHITE)
Tex := RL.LoadTextureFromImage(Img)
RL.UnloadImage(Img)

; A mesh becomes a model, and the model's first material gets the texture. Material
; is a pointer field, so Model_Materials() gives back its address, which
; SetMaterialTexture() takes as-is. LoadModelFromMesh() takes ownership of the mesh,
; so UnloadModel() is enough and UnloadMesh() would be wrong.
Mesh := RL.GenMeshCube(2.0, 2.0, 2.0)
Model := RL.LoadModelFromMesh(Mesh)
RL.SetMaterialTexture(RL.Model_Materials(Model), RL.MATERIAL_MAP_DIFFUSE, Tex)

; position, target, up, field of view, projection
Cam := RL.MakeCamera3D([4.0, 3.0, 4.0], [0.0, 0.8, 0.0], [0.0, 1.0, 0.0], 50.0,
    RL.CAMERA_PERSPECTIVE)

; The built-in font holds 224 glyphs and has no ő or ű, so a TTF is loaded with only
; the codepoints this caption uses. Without a TTF the text falls back to ASCII.
FontFile := FindTtf()
CustomFont := 0
if (FontFile != "") {
    Cps := RL.Codepoints(Caption)
    CustomFont := RL.LoadFontEx(FontFile, 26, Cps, Cps.Size // 4)
} else {
    Caption := "no TrueType font found, built-in font only"
}
View := RL.GetFontDefault()
Builtin := RL.MeasureTextEx(View, Caption, 26, 1.0)[1]
Custom := CustomFont ? RL.MeasureTextEx(CustomFont, Caption, 26, 1.0)[1] : 0

StartTick := A_TickCount
while !RL.WindowShouldClose() {
    RenderFrame()
    if (AutoExit && A_TickCount - StartTick >= AutoExit) {
        if (ShotPath != "") {
            ; ScreenShot() takes a full path, which TakeScreenshot() refuses: it only
            ; accepts a bare name and writes it next to where the process started.
            RenderFrame()
            RL.ScreenShot(ShotPath)
        }
        break
    }
}

RL.UnloadModel(Model)
if CustomFont
    RL.UnloadFont(CustomFont)
RL.UnloadTexture(Tex)
RL.CloseWindow()
ExitApp(0)

RenderFrame() {
    global
    ; raylib turns the mouse into an orbit; scroll zooms.
    RL.UpdateCamera(Cam, RL.CAMERA_ORBITAL)

    RL.BeginDrawing()
    RL.ClearBackground(RL.RAYWHITE)
    RL.BeginMode3D(Cam)
    RL.DrawGrid(12, 1.0)
    RL.DrawModel(Model, 0.0, 1.0, 0.0, 1.0, RL.WHITE)
    RL.DrawCubeWires(0.0, 1.0, 0.0, 2.0, 2.0, 2.0, RL.MAROON)
    RL.EndMode3D()

    if CustomFont {
        ; the same string, once with each font: the built-in one has no accents to draw
        RL.DrawTextEx(CustomFont, Caption, 16, 12, 26, 1.0, RL.DARKGRAY)
        RL.DrawText(Caption, 16, 48, 20, RL.MAROON)
        RL.DrawText("above: LoadFontEx() " Round(Custom) " px wide, below: built-in font "
            . Round(Builtin) " px wide", 16, 78, 16, RL.GRAY)
    } else {
        RL.DrawText(Caption, 16, 12, 24, RL.DARKGRAY)
    }
    RL.DrawText("scroll to zoom, drag to look around", 16, Height - 32, 16, RL.GRAY)
    RL.DrawFPS(Width - 100, 12)
    RL.EndDrawing()
}

; Any TrueType on the system will do; arial first because it is always there.
FindTtf() {
    static Names := ["arial.ttf", "segoeui.ttf", "tahoma.ttf", "calibri.ttf", "cour.ttf"]
    for Name in Names {
        if FileExist(A_WinDir "\Fonts\" Name)
            return A_WinDir "\Fonts\" Name
    }
    Loop Files A_WinDir "\Fonts\*.ttf" {
        return A_LoopFileFullPath
    }
    return ""
}

CubeErrorHandler(err, mode) {
    FileAppend("[ERROR] " err.Message "`n"
        . "File: " err.File " (Line " err.Line ")`n"
        . "Stack:`n" err.Stack "`n", "**")
    ExitApp(1)
}
