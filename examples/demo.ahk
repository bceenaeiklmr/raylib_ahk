; Interactive demo for lib\raylib.ahk: a ball with gravity that you can nudge and
; fling. Also runs headless-safe for automation:
;
;   & 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut examples\demo.ahk
;   & 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut examples\demo.ahk /auto:2000 /shot:demo
;
; /auto[:ms]  close the window by itself (default 3000 ms)
; /shot:name  write tests\out\name.png just before closing
#Requires AutoHotkey v2.0
#Warn All, StdOut
#SingleInstance Force

#Include ..\lib\raylib.ahk
#Include harness.ahk

Width := 960, Height := 540
FloorY := Height - 46
Gravity := 1500.0   ; pixels/s^2
Bounce := 0.82      ; energy kept after a wall hit
Drag := 0.35        ; per second
MaxSpeed := 2600.0  ; px/s cap, keeps the cursor spring from diverging
RestSpeed := 60.0   ; px/s below which the ball counts as parked
Relaunch := 2200.0  ; ms parked before it gets pushed again
PushVX := 420.0     ; relaunch impulse, px/s
PushVY := 900.0
Palette := [RL.MAROON, RL.SKYBLUE, RL.GOLD, RL.LIME, RL.PURPLE, RL.ORANGE]
Pen := 1

; Vsync tracks the display refresh. SetTargetFPS(60) instead waits on the ~15.6 ms
; Windows timer tick and lands at ~24 ms per frame, about 41 fps with jitter.
RL.SetConfigFlags(RL.FLAG_WINDOW_RESIZABLE | RL.FLAG_VSYNC_HINT)
RL.InitWindow(Width, Height, "raylib.ahk demo  -  WASD/arrows nudge, hold left mouse to fling, C color, R reset, Esc quits")
Reset()
StartTick := A_TickCount
ParkedSince := A_TickCount
Kicks := 0

while !RL.WindowShouldClose() {
    Dt := RL.GetFrameTime()
    if (Dt > 0.05)
        Dt := 0.05  ; a dragged or minimised window would otherwise teleport the ball

    Nudge := 1400 * Dt
    if (RL.IsKeyDown(RL.KEY_LEFT) || RL.IsKeyDown(RL.KEY_A))
        VX -= Nudge
    if (RL.IsKeyDown(RL.KEY_RIGHT) || RL.IsKeyDown(RL.KEY_D))
        VX += Nudge
    if (RL.IsKeyDown(RL.KEY_UP) || RL.IsKeyDown(RL.KEY_W))
        VY -= Nudge
    if (RL.IsKeyDown(RL.KEY_DOWN) || RL.IsKeyDown(RL.KEY_S))
        VY += Nudge
    if RL.IsKeyPressed(RL.KEY_C)
        Pen := Mod(Pen, Palette.Length) + 1
    if RL.IsKeyPressed(RL.KEY_R)
        Reset()
    if RL.IsMouseButtonDown(RL.MOUSE_BUTTON_LEFT) {
        ; spring the ball towards the cursor while the button is held
        VX += (RL.GetMouseX() - X) * 360 * Dt
        VY += (RL.GetMouseY() - Y) * 360 * Dt
    }

    VY += Gravity * Dt
    VX *= 1.0 - Drag * Dt
    VY *= 1.0 - Drag * Dt

    ; Cap the speed. Unbounded, the cursor spring feeds itself every frame until
    ; the position runs away to Inf and the ball leaves the window for good.
    Speed := Sqrt(VX * VX + VY * VY)
    if (Speed > MaxSpeed) {
        VX *= MaxSpeed / Speed
        VY *= MaxSpeed / Speed
    }

    ; Never let it look dead: gravity and bouncing bleed the energy out, so after a
    ; quiet moment at rest the ball gets pushed again, alternating direction.
    if (Speed > RestSpeed)
        ParkedSince := A_TickCount
    else if (A_TickCount - ParkedSince > Relaunch) {
        Kicks++
        VX := Mod(Kicks, 2) ? PushVX : -PushVX
        VY := -PushVY
        ParkedSince := A_TickCount
    }

    X += VX * Dt
    Y += VY * Dt
    if (Y + Radius > FloorY) {
        Y := FloorY - Radius
        VY := -VY * Bounce
        if (Abs(VY) < 40)
            VY := 0
    }
    if (Y - Radius < 0) {
        Y := Radius
        VY := -VY * Bounce
    }
    if (X - Radius < 0) {
        X := Radius
        VX := -VX * Bounce
    } else if (X + Radius > Width) {
        X := Width - Radius
        VX := -VX * Bounce
    }

    Trail.Push(X, Y)
    while (Trail.Length > 90) {  ; drop whole pairs so x,y stays aligned
        ; RemoveAt shifts the array down. Delete only punches a hole, so Length
        ; would never shrink and this loop would spin with the window frozen.
        Trail.RemoveAt(1, 2)
    }

    RenderFrame(Dt)

    if (AutoExit && A_TickCount - StartTick >= AutoExit) {
        Shoot(() => RenderFrame(Dt))
        break
    }
}

RL.CloseWindow()
ExitApp(0)

Reset() {
    global
    X := Width * 0.35, Y := Height * 0.25
    VX := 240.0, VY := -60.0, Radius := 26.0
    Trail := []
}

RenderFrame(Dt) {
    global
    RL.BeginDrawing()
    RL.ClearBackground(RL.RAYWHITE)
    RL.DrawRectangleGradientV(0, 0, Width, Height, RL.Alpha(RL.SKYBLUE, 0.3), RL.Alpha(RL.RAYWHITE, 0))

    ; floor
    RL.DrawRectangle(0, FloorY, Width, Height - FloorY, RL.LIGHTGRAY)
    RL.DrawLine(0, FloorY, Width, FloorY, RL.DARKGRAY)

    ; motion trail, oldest points faintest
    Points := Trail.Length // 2
    Loop Points {
        Fade := A_Index / Points
        RL.DrawCircle(Trail[2 * A_Index - 1], Trail[2 * A_Index], Radius * 0.4 * Fade,
            RL.Alpha(RL.GRAY, 0.5 * Fade))
    }

    ; shadow, ball, highlight
    RL.DrawEllipse(Round(X), FloorY + 6, Radius * 1.1, 7, RL.Alpha(RL.BLACK, 0.18))
    RL.DrawCircle(Round(X), Round(Y), Radius, Palette[Pen])
    RL.DrawCircle(Round(X - Radius * 0.3), Round(Y - Radius * 0.35), Radius * 0.28,
        RL.Alpha(RL.WHITE, 0.45))
    RL.DrawCircleLines(Round(X), Round(Y), Radius, RL.DARKGRAY)

    ; readouts
    RL.DrawText("speed " Format("{:6.0f}", Sqrt(VX * VX + VY * VY)) " px/s", 10, 10, 20, RL.DARKGRAY)
    RL.DrawText("pos " Format("{:4.0f}", X) "," Format("{:4.0f}", Y), 10, 34, 20, RL.GRAY)
    RL.DrawText("WASD/arrows nudge   hold left mouse to fling   C color   R reset   Esc quit",
        10, Height - 24, 16, RL.GRAY)
    RL.DrawFPS(Width - 90, 10)
    RL.EndDrawing()
}
