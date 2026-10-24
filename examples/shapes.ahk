; Every 2D primitive in raylib, drawn once each with a label, so the window is a
; picture of the shape API. The ring, the polygon and the bezier curve move; the rest
; is still.
;
;   & 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut examples\shapes.ahk
;   & '...' examples\shapes.ahk /auto:2500 /shot:shapes
;
; /auto[:ms]  close the window by itself (default 3000 ms)
; /shot:name  write tests\out\name.png just before closing
#Requires AutoHotkey v2.0
#Warn All, StdOut
#SingleInstance Force

#Include ..\lib\raylib.ahk
#Include harness.ahk

Width := 792, Height := 500
Cols := 6
CellW := Width // Cols            ; one primitive per cell
Row1 := 112, Row2 := 252, Row3 := 392
Gap := 140                        ; distance between rows

RL.SetConfigFlags(RL.FLAG_VSYNC_HINT)
RL.InitWindow(Width, Height, "raylib.ahk - 2D shapes")

StartTick := A_TickCount
while !RL.WindowShouldClose() {
    T := (A_TickCount - StartTick) / 1000.0     ; seconds since the window opened
    RenderFrame()
    if (AutoExit && A_TickCount - StartTick >= AutoExit) {
        Shoot(RenderFrame)
        break
    }
}
RL.CloseWindow()
ExitApp(0)

RenderFrame() {
    global
    RL.BeginDrawing()
    RL.ClearBackground(RL.RAYWHITE)
    RL.DrawRectangleGradientV(0, 0, Width, Height, RL.RAYWHITE, RL.GRAY)
    RL.DrawText("2D shapes - one primitive per cell", 16, 14, 22, RL.DARKGRAY)
    RL.DrawFPS(Width - 100, 14)

    ; ---------------------------------------------------------------- row 1
    Loop 18
        Loop 18
            RL.DrawPixel(Col(1) - 9 + A_Index, Row1 - 9 + A_Index,
                Mod(A_Index, 2) ? RL.SKYBLUE : RL.WHITE)
    Caption("DrawPixel x 18", Col(1), Row1 + 30)

    RL.DrawLine(Col(2) - 40, Row1 - 22, Col(2) + 40, Row1 - 6, RL.MAROON)
    RL.DrawLineEx(Col(2) - 40, Row1 + 8, Col(2) + 40, Row1 + 24, 7, RL.DARKBLUE)
    Caption("DrawLine + Ex", Col(2), Row1 + 30)

    RL.DrawCircle(Col(3), Row1, 26, RL.SKYBLUE)
    RL.DrawCircleLines(Col(3), Row1, 34, RL.MAROON)
    Caption("Circle + Lines", Col(3), Row1 + 30)

    RL.DrawRectangle(Col(4) - 28, Row1 - 24, 56, 48, RL.GOLD)
    RL.DrawRectangleLines(Col(4) - 34, Row1 - 30, 68, 60, RL.DARKBLUE)
    Caption("Rect + Lines", Col(4), Row1 + 30)

    RL.DrawRing(Col(5), Row1, 14, 36, 0, 90 + 250 * Abs(Sin(T)), 48, RL.PURPLE)
    Caption("DrawRing", Col(5), Row1 + 30)

    RL.DrawEllipse(Col(6), Row1, 40, 16, RL.ORANGE)
    RL.DrawEllipse(Col(6), Row1 + 6, 20, 30, RL.PINK)
    Caption("DrawEllipse", Col(6), Row1 + 30)

    ; ---------------------------------------------------------------- row 2
    ; Winding matters: these vertices are counter-clockwise, because raylib culls
    ; clockwise polygons and the shape would silently not appear.
    RL.DrawTriangle(Col(1) - 34, Row2 + 26, Col(1) + 34, Row2 + 26, Col(1), Row2 - 30, RL.RED)
    Caption("Triangle, ccw", Col(1), Row2 + 42)

    RL.DrawTriangleFan([Col(2), Row2 + 4, Col(2) - 38, Row2 + 22, Col(2) - 20, Row2 - 26,
        Col(2) + 20, Row2 - 26, Col(2) + 38, Row2 + 22, Col(2), Row2 + 30], RL.LIME)
    Caption("TriangleFan", Col(2), Row2 + 42)

    RL.DrawPoly(Col(3), Row2, 6, 32, 45 + 30 * Sin(T), RL.MAROON)
    Caption("DrawPoly", Col(3), Row2 + 42)

    RL.DrawPolyLinesEx(Col(4), Row2, 5, 32, 0, 4, RL.DARKBLUE)
    Caption("PolyLinesEx", Col(4), Row2 + 42)

    RL.DrawSplineCatmullRom([Col(5) - 44, Row2 + 22, Col(5) - 16, Row2 - 24, Col(5) + 8,
        Row2 + 18, Col(5) + 44, Row2 - 18], 4, RL.DARKGREEN)
    Caption("Spline Catmull", Col(5), Row2 + 42)

    RL.DrawLineBezier(Col(6) - 40, Row2 + 24, Col(6) + 40, Row2 + 24, 5, RL.ORANGE)
    RL.DrawCircleV(Col(6) - 40, Row2 + 24, 4, RL.DARKGRAY)
    RL.DrawCircleV(Col(6) + 40, Row2 + 24, 4, RL.DARKGRAY)
    Caption("LineBezier", Col(6), Row2 + 42)

    ; ---------------------------------------------------------------- row 3
    RL.DrawRectangleGradientV(Col(1) - 38, Row3 - 30, 76, 60, RL.SKYBLUE, RL.MAROON)
    Caption("GradientV", Col(1), Row3 + 42)

    RL.DrawRectangleGradientH(Col(2) - 38, Row3 - 30, 76, 60, RL.LIME, RL.PURPLE)
    Caption("GradientH", Col(2), Row3 + 42)

    RL.DrawRectangleGradientEx(Col(3) - 38, Row3 - 30, 76, 60, RL.WHITE, RL.BLACK, RL.GOLD, RL.SKYBLUE)
    Caption("GradientEx", Col(3), Row3 + 42)

    RL.DrawCircleSector(Col(4), Row3, 32, 0, 260, 24, RL.ORANGE)
    RL.DrawCircleSectorLines(Col(4), Row3, 32, 0, 260, 24, RL.MAROON)
    Caption("CircleSector", Col(4), Row3 + 42)

    RL.DrawRectangleRounded(Col(5) - 38, Row3 - 28, 76, 56, 0.4, 12, RL.DARKBLUE)
    RL.DrawRectangleRoundedLinesEx(Col(5) - 38, Row3 - 28, 76, 56, 0.4, 12, 3, RL.SKYBLUE)
    Caption("RoundedRect", Col(5), Row3 + 42)

    RL.DrawText("text", Col(6) - 18, Row3 - 8, 24, RL.DARKGRAY)
    RL.DrawRectangleLines(Col(6) - 38, Row3 - 28, 76, 56, RL.GRAY)
    Caption("DrawText", Col(6), Row3 + 42)

    ; Cell separators last, so they never cover a shape.
    Loop Cols - 1
        RL.DrawLine(CellW * A_Index, 56, CellW * A_Index, Height - 14, RL.ColorAlpha(RL.GRAY, 0.35))
    Loop 2
        RL.DrawLine(14, Row1 + Gap * A_Index - 40, Width - 14, Row1 + Gap * A_Index - 40,
            RL.ColorAlpha(RL.GRAY, 0.35))
    RL.EndDrawing()
}

; Centre x of cell N (1..Cols).
Col(N) {
    global CellW
    return Round(CellW * (N - 0.5))
}

; Caption centred under the shape drawn at X in the row above Y.
Caption(Text, X, Y) {
    local W
    W := RL.MeasureText(Text, 14)
    RL.DrawText(Text, X - W // 2, Y, 14, RL.DARKGRAY)
}
