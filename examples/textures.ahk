; Textures without a single image file: three generated in RAM, then tinted, rotated,
; scaled and cut out of a sprite sheet, plus an offscreen pass into a render texture,
; which turns out to be an ordinary texture afterwards.
;
;   & 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut examples\textures.ahk
;   & '...' examples\textures.ahk /auto:2500 /shot:textures
;
; /auto[:ms]  close the window by itself (default 3000 ms)
; /shot:name  write tests\out\name.png just before closing
#Requires AutoHotkey v2.0
#Warn All, StdOut
#SingleInstance Force

#Include ..\lib\raylib.ahk
#Include harness.ahk

Width := 900, Height := 440
SheetCell := 32       ; the sprite sheet is four 32x32 frames in a row
SheetScale := 3

RL.SetConfigFlags(RL.FLAG_VSYNC_HINT)
RL.InitWindow(Width, Height, "raylib.ahk - textures, sprite sheets, render textures")

; ---------------------------------------------------------------- textures in RAM
; GenImage* builds the pixels, LoadTextureFromImage uploads them, and the Image is
; released straight away: after the upload only the Texture is needed.
Checked := TextureFromImage(RL.GenImageChecked(64, 64, 4, 4, RL.SKYBLUE, RL.RAYWHITE))
Glow := TextureFromImage(RL.GenImageGradientRadial(64, 64, 0.1, RL.WHITE, RL.SKYBLUE))
Noise := TextureFromImage(RL.GenImagePerlinNoise(64, 64, 0, 0, 8.0))

; ---------------------------------------------------------------- sprite sheet
; Four frames, drawn once into a render texture. Rendering into a texture is how you
; build an atlas without shipping a PNG, and it leaves nothing to read from disk.
; Frames sit in a row, so a frame is one source rectangle: x = frame * 32.
Sheet := RL.LoadRenderTexture(SheetCell * 4, SheetCell)
BuildSheet(Sheet)
SheetTex := Attachment(Sheet)                       ; its colour attachment, as a Texture
RL.SetTextureFilter(SheetTex, RL.TEXTURE_FILTER_POINT)   ; nearest, so scaling stays crisp

StartTick := A_TickCount
while !RL.WindowShouldClose() {
    T := (A_TickCount - StartTick) / 1000.0
    RenderFrame()
    if (AutoExit && A_TickCount - StartTick >= AutoExit) {
        Shoot(RenderFrame)
        break
    }
}

RL.UnloadRenderTexture(Sheet)
RL.UnloadTexture(Checked)
RL.UnloadTexture(Glow)
RL.UnloadTexture(Noise)
RL.CloseWindow()
ExitApp(0)

; GenImage* hands back an Image; upload it and release the pixels in one step.
TextureFromImage(Img) {
    local Tex
    Tex := RL.LoadTextureFromImage(Img)
    RL.UnloadImage(Img)
    return Tex
}

; Draw the four animation frames into the render texture.
BuildSheet(Rt) {
    local Palette, I, X
    Palette := [RL.MAROON, RL.SKYBLUE, RL.GOLD, RL.LIME]
    RL.BeginTextureMode(Rt)
    RL.BeginDrawing()
    RL.ClearBackground(RL.Blank)
    Loop 4 {
        I := A_Index
        X := (I - 1) * SheetCell + SheetCell // 2
        RL.DrawCircle(X, SheetCell // 2 + 4 - 3 * I, 11, Palette[I])
        RL.DrawRectangle(X - 4 + 3 * I, 3 + 6 * Mod(I, 3), 6, 6, RL.WHITE)
    }
    RL.EndDrawing()
    RL.EndTextureMode()
}

; A RenderTexture keeps its colour attachment inside itself, while the drawing
; functions want a Texture of their own, so copy the five fields out. The accessor
; methods do the arithmetic; no offsets are written here.
Attachment(Rt) {
    local T
    T := Buffer(RL.Texture_Size, 0)
    RL.Texture_Id(T, RL.RenderTexture2D_TextureId(Rt))
    RL.Texture_Width(T, RL.RenderTexture2D_TextureWidth(Rt))
    RL.Texture_Height(T, RL.RenderTexture2D_TextureHeight(Rt))
    RL.Texture_Mipmaps(T, RL.RenderTexture2D_TextureMipmaps(Rt))
    RL.Texture_Format(T, RL.RenderTexture2D_TextureFormat(Rt))
    return T
}

RenderFrame() {
    global
    RL.BeginDrawing()
    RL.ClearBackground(RL.RAYWHITE)
    RL.DrawText("textures built in RAM - no files", 16, 12, 22, RL.DARKGRAY)
    RL.DrawFPS(Width - 100, 12)

    ; ---------------------------------------------------------------- row 1
    RL.DrawTexture(Checked, 16, 56, RL.WHITE)
    RL.DrawTexture(Glow, 96, 56, RL.WHITE)
    RL.DrawTexture(Noise, 176, 56, RL.WHITE)
    Note(16, 144, "GenImage* then", "LoadTextureFromImage, 1:1")

    ; Rotation and scale. The origin is the middle here, so the picture turns inside
; its box instead of swinging around its top-left corner.
    RL.DrawRectangleLines(292, 44, 96, 96, RL.GRAY)
    RL.DrawTexturePro(Glow, 0, 0, 64, 64, 340, 92, 96, 96, 48, 48, 45 + 20 * Sin(T), RL.WHITE)
    Note(292, 144, "rotated and scaled", "around its centre")

    ; tint: the same pixels, three colours, multiplied in
    RL.DrawTextureRec(Checked, 0, 0, 64, 64, 520, 56, RL.ColorAlpha(RL.RED, 0.85))
    RL.DrawTextureRec(Checked, 0, 0, 64, 64, 596, 56, RL.GREEN)
    RL.DrawTextureRec(Checked, 0, 0, 64, 64, 672, 56, RL.BLUE)
    Note(520, 144, "DrawTextureRec:", "one texture, three tints")

    ; sub-rectangle, destination size, origin and angle all at once
    RL.DrawRectangleLines(756, 44, 96, 96, RL.GRAY)
    RL.DrawTexturePro(Glow, 16, 16, 32, 32, 804, 92, 96, 96, 48, 48, 30 * Sin(T),
        RL.ColorAlpha(RL.ORANGE, 0.9))
    Note(748, 144, "DrawTexturePro:", "src, dst, origin, angle")

    ; ---------------------------------------------------------------- row 2
    ; the sprite sheet as it was rendered, then one frame blown up
    RL.DrawTexture(SheetTex, 16, 176, RL.WHITE)
    RL.DrawRectangleLines(16, 176, SheetCell * 4, SheetCell, RL.GRAY)
    Note(16, 214, "the sheet:", "four frames in one texture")

    Frame := Mod(Integer(T * 4), 4)
    RL.DrawTexturePro(SheetTex, Frame * SheetCell, 0, SheetCell, SheetCell,
        16, 248, SheetCell * SheetScale, SheetCell * SheetScale, 0, 0, 0, RL.WHITE)
    Note(16, 348, "frame " . Frame . " of 3, scaled 3x,", "point filtered so it stays crisp")

    ; the offscreen result, drawn back like any other texture. raylib corrects the
    ; framebuffer's flipped Y while rendering into a texture, so it comes out the right
    ; way up here - a negative height would flip it a second time and put the drawing
    ; outside the box, which is easy to believe and wrong, so this picture is the proof.
    RL.DrawRectangleLines(300, 248, SheetCell * 4, SheetCell, RL.GRAY)
    RL.DrawTexturePro(SheetTex, 0, 0, SheetCell * 4, SheetCell, 300, 248,
        SheetCell * 4, SheetCell, 0, 0, 0, RL.WHITE)
    Note(300, 286, "offscreen pass, drawn back", "the right way up already")

    ; and it is an ordinary texture after that: it tints and stretches too
    RL.DrawTexturePro(SheetTex, 0, 0, SheetCell * 4, SheetCell, 560, 248,
        SheetCell * 6, SheetCell * 1.5, 0, 0, 0, RL.ColorAlpha(RL.LIME, 0.75))
    Note(560, 286, "the same texture,", "tinted and stretched")

    RL.EndDrawing()
}

; Two short lines of explanation, left aligned under the art they belong to.
Note(X, Y, First, Second) {
    RL.DrawText(First, X, Y, 14, RL.GRAY)
    RL.DrawText(Second, X, Y + 16, 14, RL.GRAY)
}
