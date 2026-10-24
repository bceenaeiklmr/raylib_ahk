; Textured 3D cube, orbiting camera, and a caption with special characters drawn
; by a system TrueType.
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

#Include ..\lib\raylib.ahk
#Include harness.ahk

Width := 800, Height := 480
Caption := "Spinning cube - special characters: é ë ö Ö ü Ü ő ű ß ñ € ½ ± °"

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
        Shoot(RenderFrame)
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
    RL.DrawFPS(Width - 100, Height - 32)
    RL.EndDrawing()
}
