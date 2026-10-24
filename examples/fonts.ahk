; Fonts: the built-in one has 224 glyphs and stops at ASCII, so a TrueType is loaded
; with only the codepoints this file needs. Sizes, spacing, measured centring, rotated
; text, and the same accented line drawn by each font, so the difference is visible.
;
;   & 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut examples\fonts.ahk
;   & '...' examples\fonts.ahk /auto:2500 /shot:fonts
;
; /auto[:ms]  close the window by itself (default 3000 ms)
; /shot:name  write tests\out\name.png just before closing
#Requires AutoHotkey v2.0
#Warn All, StdOut
#SingleInstance Force

#Include ..\lib\raylib.ahk
#Include harness.ahk

Width := 760, Height := 470
Big := "Typography"
Sizes := "The quick brown fox"
Accented := "Accents: é ë í ö Ö ü Ü ő ű Ő Ű ß ñ"
Symbols := "Symbols: arrows and signs"
Arrow := Chr(0x2192) . " " . Chr(0x00A9) . " " . Chr(0x20AC) . " " . Chr(0x221A) . " " . Chr(0x00BD)

RL.SetConfigFlags(RL.FLAG_VSYNC_HINT)
RL.InitWindow(Width, Height, "raylib.ahk - fonts and Unicode")

Ttf := FindTtf()
Font := 0
if (Ttf != "") {
    ; LoadFontEx bakes a glyph atlas, and only the codepoints listed here end up in it.
    ; Passing 0, 0 instead would load the 224 glyphs raylib ships by default.
    Cps := RL.Codepoints(Big . Sizes . Accented . Symbols . Arrow)
    Font := RL.LoadFontEx(Ttf, 48, Cps, Cps.Size // 4)
}
Fallback := "no TrueType font found in " A_WinDir "\Fonts"
Builtin := RL.GetFontDefault()     ; raylib ships 224 glyphs, ASCII and a little more
BuiltinWidth := RL.MeasureTextEx(Builtin, Accented, 24, 1.0)[1]
TtfWidth := Font ? RL.MeasureTextEx(Font, Accented, 24, 1.0)[1] : 0

StartTick := A_TickCount
while !RL.WindowShouldClose() {
    T := (A_TickCount - StartTick) / 1000.0
    RenderFrame()
    if (AutoExit && A_TickCount - StartTick >= AutoExit) {
        Shoot(RenderFrame)
        break
    }
}
if Font
    RL.UnloadFont(Font)
RL.CloseWindow()
ExitApp(0)

RenderFrame() {
    global
    RL.BeginDrawing()
    RL.ClearBackground(RL.RAYWHITE)
    RL.DrawText("fonts - " . (Font ? Ttf : Fallback), 16, 12, 20, RL.DARKGRAY)
    RL.DrawFPS(Width - 100, 12)

    if Font {
        ; one baked atlas, drawn at four sizes and four spacings
        RL.DrawTextEx(Font, Big, 16, 52, 48, 2, RL.DARKGRAY)
        RL.DrawText("size 48", 16, 106, 14, RL.GRAY)

        for Size in [12, 18, 26, 34] {
            RL.DrawTextEx(Font, Sizes, 16, 132 + 30 * (A_Index - 1), Size, 1.0, RL.DARKBLUE)
            RL.DrawText("size " . Size, 430, 132 + 30 * (A_Index - 1), 14, RL.GRAY)
        }

        Loop 4 {
            RL.DrawTextEx(Font, "spacing", 16, 260 + 26 * (A_Index - 1), 22,
                -2 + 4 * A_Index, RL.MAROON)
            RL.DrawText("spacing " . (-2 + 4 * A_Index), 430, 260 + 26 * (A_Index - 1), 14, RL.GRAY)
        }

        ; centred by measuring first, which is all MeasureTextEx is for
        Box := [520, 44, 224, 150]
        RL.DrawRectangleLines(Box[1], Box[2], Box[3], Box[4], RL.GRAY)
        Size := 30
        M := RL.MeasureTextEx(Font, "measured", Size, 1.0)
        RL.DrawTextEx(Font, "measured", Box[1] + (Box[3] - M[1]) / 2, Box[2] + (Box[4] - M[2]) / 2,
            Size, 1.0, RL.LIME)
        RL.DrawText("MeasureTextEx -> " . Round(M[1]) . " x " . Round(M[2]), Box[1], Box[2] + Box[4] + 6,
            14, RL.GRAY)

        ; DrawTextPro adds an origin and an angle, so the text pivots around its own
; middle instead of around its top-left corner.
        Word := "pivot"
        Wide := RL.MeasureTextEx(Font, Word, 40, 1.0)
        RL.DrawTextPro(Font, Word, Box[1] + Box[3] // 2, 250, Wide[1] / 2, Wide[2] / 2,
            24 * Sin(T), 40, 1.0, RL.GOLD)
        RL.DrawText("DrawTextPro: origin and angle", Box[1], 292, 14, RL.GRAY)
        RL.DrawTextEx(Font, Accented, 16, 380, 24, 1.0, RL.DARKGRAY)
        RL.DrawText("the built-in font draws the same line as " . Round(BuiltinWidth)
            . " px of question marks, this one as " . Round(TtfWidth) . " px of letters",
            16, 412, 14, RL.GRAY)
        RL.DrawTextEx(Font, Symbols . "  " . Arrow, 16, 434, 20, 1.0, RL.DARKBLUE)

        ; which glyph the atlas actually holds
        RL.DrawText("GetGlyphIndex:  A=" . RL.GetGlyphIndex(Font, 65)
            . "  a=" . RL.GetGlyphIndex(Font, 97)
            . "  oe=" . RL.GetGlyphIndex(Font, 246)
            . "  Z=" . RL.GetGlyphIndex(Font, 90), 430, 380, 14, RL.GRAY)
    } else {
        RL.DrawText(Fallback, 16, 60, 24, RL.MAROON)
        RL.DrawText(Accented, 16, 100, 24, RL.DARKGRAY)
    }
    RL.EndDrawing()
}
