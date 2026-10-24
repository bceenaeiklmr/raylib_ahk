; Input: keyboard state, typed characters (UTF-8, so accents survive a real keyboard
; layout), the three mouse buttons, the wheel, the cursor, and a gamepad readout that
; appears the moment a pad is connected.
;
;   & 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut examples\input.ahk
;   & '...' examples\input.ahk /auto:6000 /shot:input
;
; C hides the cursor, Backspace edits the typed line, R clears it.
;
; /auto[:ms]  close the window by itself (default 3000 ms)
; /shot:name  write tests\out\name.png just before closing
#Requires AutoHotkey v2.0
#Warn All, StdOut
#SingleInstance Force

#Include ..\lib\raylib.ahk
#Include harness.ahk

Width := 760, Height := 470

; Key name -> raylib constant, for the state panel on the left.
Keys := [["W", RL.KEY_W], ["A", RL.KEY_A], ["S", RL.KEY_S], ["D", RL.KEY_D],
    ["UP", RL.KEY_UP], ["LEFT", RL.KEY_LEFT], ["DOWN", RL.KEY_DOWN], ["RIGHT", RL.KEY_RIGHT],
    ["SPACE", RL.KEY_SPACE], ["ENTER", RL.KEY_ENTER], ["C", RL.KEY_C], ["R", RL.KEY_R]]

Buttons := [["left", RL.MOUSE_BUTTON_LEFT], ["right", RL.MOUSE_BUTTON_RIGHT],
    ["middle", RL.MOUSE_BUTTON_MIDDLE], ["side", RL.MOUSE_BUTTON_SIDE], ["extra", RL.MOUSE_BUTTON_EXTRA]]

; Pad face buttons and axes, drawn only when a pad is present.
Face := [["A", RL.GAMEPAD_BUTTON_RIGHT_FACE_DOWN], ["B", RL.GAMEPAD_BUTTON_RIGHT_FACE_RIGHT],
    ["X", RL.GAMEPAD_BUTTON_RIGHT_FACE_LEFT], ["Y", RL.GAMEPAD_BUTTON_RIGHT_FACE_UP]]
Axes := [["left x", RL.GAMEPAD_AXIS_LEFT_X], ["left y", RL.GAMEPAD_AXIS_LEFT_Y],
    ["right x", RL.GAMEPAD_AXIS_RIGHT_X], ["right y", RL.GAMEPAD_AXIS_RIGHT_Y]]

Typed := ""            ; characters gathered from GetKeyPressed
Zoom := 1.0            ; mouse wheel
Wheel := 0.0           ; smoothed, for the readout

RL.SetConfigFlags(RL.FLAG_VSYNC_HINT)
RL.InitWindow(Width, Height, "raylib.ahk - keyboard, mouse, gamepad")
RL.SetMouseScale(1.0, 1.0)

StartTick := A_TickCount
while !RL.WindowShouldClose() {
    T := (A_TickCount - StartTick) / 1000.0
    PollInput()
    RenderFrame()
    if (AutoExit && A_TickCount - StartTick >= AutoExit) {
        Shoot(RenderFrame)
        break
    }
}
RL.CloseWindow()
ExitApp(0)

PollInput() {
    global Typed, Zoom, Wheel
    ; GetKeyPressed returns one decoded UTF-8 codepoint per call and must be drained
    ; in a loop; one call per frame would drop keys on fast typing.
    while (Code := RL.GetKeyPressed()) {
        if (Code == 8)                          ; backspace
            Typed := SubStr(Typed, 1, StrLen(Typed) - 1)
        else if (Code == 13 || Code == 32 || (Code > 31 && Code < 0x10FFFF))
            Typed .= Chr(Code)
        if (StrLen(Typed) > 40)
            Typed := SubStr(Typed, 1, 40)
    }
    if RL.IsKeyPressed(RL.KEY_R)
        Typed := ""
    if RL.IsKeyPressed(RL.KEY_C)
        RL.IsCursorHidden() ? RL.EnableCursor() : RL.HideCursor()

    Wheel := Wheel + (RL.GetMouseWheelMove() - Wheel) * 0.25   ; ease the readout
    Zoom += RL.GetMouseWheelMove() * 0.1
    Zoom := Zoom < 0.4 ? 0.4 : (Zoom > 3.0 ? 3.0 : Zoom)
}

RenderFrame() {
    global
    Mouse := RL.GetMousePosition()
    RL.BeginDrawing()
    RL.ClearBackground(RL.RAYWHITE)
    RL.DrawText("keyboard, mouse and gamepad", 16, 12, 22, RL.DARKGRAY)
    RL.DrawFPS(Width - 100, 12)

    ; ---------------------------------------------------------- key states
    RL.DrawText("held keys", 16, 52, 16, RL.DARKGRAY)
    for Item in Keys {
        Row := A_Index - 1
        X := 16, Y := 76 + Row * 26
        RL.DrawText(Item[1], X, Y + 3, 14, RL.GRAY)
        Down := RL.IsKeyDown(Item[2])
        RL.DrawRectangleRounded(X + 62, Y, 60, 18, 0.4, 6, Down ? RL.SKYBLUE : RL.ColorAlpha(RL.LIGHTGRAY, 0.6))
        RL.DrawText(Down ? "down" : "-", X + 82, Y + 3, 13, Down ? RL.DARKBLUE : RL.GRAY)
    }

    ; ---------------------------------------------------------- typed text
    RL.DrawRectangleLines(220, 52, 520, 66, RL.GRAY)
    RL.DrawText("typed (GetKeyPressed, UTF-8):", 228, 58, 14, RL.GRAY)
    RL.DrawText(Typed == "" ? "type something, accents included" : Typed, 228, 82, 24,
        Typed == "" ? RL.LightGray : RL.DARKGRAY)
    RL.DrawText("Backspace edits, R clears, C toggles the cursor", 228, 124, 14, RL.GRAY)

    ; ---------------------------------------------------------- mouse
    RL.DrawText("mouse", 220, 158, 16, RL.DARKGRAY)
    RL.DrawText("position  " . Round(Mouse[1]) . ", " . Round(Mouse[2])
        . "     delta  " . Round(RL.GetMouseDelta()[1]) . ", " . Round(RL.GetMouseDelta()[2])
        . "     wheel  " . Round(Wheel, 2), 220, 180, 15, RL.DARKGRAY)
    for Item in Buttons {
        X := 220 + (A_Index - 1) * 96
        Down := RL.IsMouseButtonDown(Item[2])
        RL.DrawCircle(X + 14, 212, 12, Down ? RL.MAROON : RL.ColorAlpha(RL.GRAY, 0.7))
        RL.DrawText(Item[1], X + 32, 205, 14, Down ? RL.DARKBLUE : RL.GRAY)
    }
    RL.DrawText("cursor: " . (RL.IsCursorHidden() ? "hidden" : "visible"), 220, 236, 15, RL.DARKGRAY)

    ; The wheel zooms the square in its own box on the right, where it cannot cover
; the key list however the pointer moves.
    RL.DrawRectangleLines(604, 268, 136, 136, RL.GRAY)
    Side := 64 * Zoom
    RL.DrawRectanglePro(672, 336, Side, Side, Side / 2, Side / 2, 20 * Sin(T), RL.GOLD)
    RL.DrawText("wheel zooms", 604, 412, 14, RL.GRAY)
    RL.DrawText("zoom " . Round(Zoom, 1), 604, 428, 14, RL.GRAY)

    ; a ring that follows the pointer, so movement is visible without looking at numbers
    RL.DrawCircleLines(Round(Mouse[1]), Round(Mouse[2]), 26, RL.SKYBLUE)
    RL.DrawPixelV(Mouse[1], Mouse[2], RL.MAROON)

    ; ---------------------------------------------------------- gamepad
    RL.DrawText("gamepad", 16, 396, 16, RL.DARKGRAY)
    if RL.IsGamepadAvailable(0) {
        RL.DrawText(RL.GetGamepadName(0), 90, 396, 15, RL.DARKGRAY)
        for Item in Face {
            X := 16 + (A_Index - 1) * 62
            Held := RL.IsGamepadButtonDown(0, Item[2])
            RL.DrawCircle(X + 12, 432, 12, Held ? RL.LIME : RL.ColorAlpha(RL.GRAY, 0.7))
            RL.DrawText(Item[1], X + 28, 425, 14, Held ? RL.DARKGREEN : RL.GRAY)
        }
        for Item in Axes {
            Y := 416 + (A_Index - 1) * 14
            V := RL.GetGamepadAxisMovement(0, Item[2])
            RL.DrawText(Item[1], 300, Y, 13, RL.GRAY)
            RL.DrawRectangleLines(360, Y + 2, 120, 8, RL.GRAY)
            RL.DrawRectangle(360 + 60, Y + 3, 58 * V, 6, V < 0 ? RL.ORANGE : RL.SKYBLUE)
        }
    } else {
        RL.DrawText("none connected - plug one in and it appears here", 90, 396, 15, RL.GRAY)
    }

    ; ---------------------------------------------------------- gestures
    RL.DrawText("touch x=" . RL.GetTouchX() . ", tap "
        . (RL.IsGestureDetected(RL.GESTURE_TAP) ? "detected" : "not this frame")
        . ", " . (RL.IsGestureDetected(RL.GESTURE_HOLD) ? "holding" : "not holding"),
        220, 428, 14, RL.GRAY)
    RL.DrawText("drag with the mouse, scroll to zoom, type to fill the box", 220, 448, 14, RL.GRAY)
    RL.EndDrawing()
}
