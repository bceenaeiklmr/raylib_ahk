; A playable brick game: mouse or A/D moves the paddle, where the ball hits the paddle
; decides its new angle, bricks break, and the two sound effects are synthesised in RAM
; so the demo ships without any asset files.
;
;   & 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut examples\paddle.ahk
;   & '...' examples\paddle.ahk /auto:9000 /shot:paddle
;
; R restarts, P pauses. After a game over the round restarts by itself, so a headless
; run never looks like a frozen window.
;
; /auto[:ms]  close the window by itself (default 3000 ms)
; /shot:name  write tests\out\name.png just before closing
#Requires AutoHotkey v2.0
#Warn All, StdOut
#SingleInstance Force

#Include ..\lib\raylib.ahk
#Include harness.ahk

Width := 720, Height := 460
Cols := 10, Rows := 5
BrickW := 62, BrickH := 20, Gap := 4
Top := 74
PaddleW := 104, PaddleH := 14, PaddleY := Height - 46
BallR := 8

RL.SetConfigFlags(RL.FLAG_VSYNC_HINT)
RL.InitWindow(Width, Height, "raylib.ahk - paddle and bricks")

RowColor := [RL.MAROON, RL.ORANGE, RL.GOLD, RL.LIME, RL.SKYBLUE]

; ---------------------------------------------------------------- sound in RAM
; raudio will decode WAV bytes handed to it in memory, which is the cheapest way to get
; a sound effect without a file: build the RIFF header and the samples in a Buffer.
Vol := 1.0
Blip := 0, Clap := 0
RL.InitAudioDevice()
if RL.IsAudioDeviceReady() {
    Blip := SoundFromSamples(520.0, 0.05)
    Clap := SoundFromSamples(880.0, 0.07)
}

Reset(true)
Paused := false
RestTick := 0

StartTick := A_TickCount
while !RL.WindowShouldClose() {
    Dt := RL.GetFrameTime()
    if (Dt > 0.05)          ; a stalled frame must not teleport the ball
        Dt := 0.05
    HandleKeys()
    if !Paused
        Step(Dt)
    RenderFrame()
    if (AutoExit && A_TickCount - StartTick >= AutoExit) {
        Shoot(RenderFrame)
        break
    }
}

if Blip
    RL.UnloadSound(Blip)
if Clap
    RL.UnloadSound(Clap)
RL.CloseAudioDevice()
RL.CloseWindow()
ExitApp(0)

; A short 16 bit mono WAV in a Buffer, decoded by raudio into a Wave.
SoundFromSamples(Freq, Seconds) {
    local Rate, N, Buf, K, A, TwoPi, W
    Rate := 44100
    N := Integer(Rate * Seconds)
    Buf := Buffer(44 + N * 2, 0)
    PutTag("RIFF", Buf, 0)
    NumPut("UInt", 36 + N * 2, Buf, 4)
    PutTag("WAVE", Buf, 8)
    PutTag("fmt ", Buf, 12)
    NumPut("UInt", 16, Buf, 16)             ; fmt chunk size
    NumPut("UShort", 1, Buf, 20)            ; PCM
    NumPut("UShort", 1, Buf, 22)            ; mono
    NumPut("UInt", Rate, Buf, 24)
    NumPut("UInt", Rate * 2, Buf, 28)       ; bytes per second
    NumPut("UShort", 2, Buf, 32)            ; block align
    NumPut("UShort", 16, Buf, 34)           ; bits per sample
    PutTag("data", Buf, 36)
    NumPut("UInt", N * 2, Buf, 40)
    TwoPi := 6.283185307179586
    Loop N {
        K := A_Index - 1
        A := 1.0 - K / N                    ; decay, so it is a blip and not a beep
        NumPut("Short", Round(Sin(TwoPi * K * Freq / Rate) * 9000 * A), Buf, 44 + K * 2)
    }
    ; raudio wants the type with its leading dot: "wav" is refused as unsupported
    W := RL.LoadWaveFromMemory(".wav", Buf, Buf.Size)
    if (RL.Wave_FrameCount(W) != N)
        return 0
    return RL.LoadSoundFromWave(W)
}

PutTag(Chars, Buf, Pos) {
    Loop 4
        NumPut("UChar", Ord(SubStr(Chars, A_Index, 1)), Buf, Pos + A_Index - 1)
}

Reset(FirstLevel := false) {
    global
    Alive := []
    Loop Rows * Cols
        Alive.Push(1)
    Left := Rows * Cols
    if FirstLevel
        Speed := 320.0
    Score := 0
    Lives := 3
    PaddleX := Width / 2 - PaddleW / 2
    Serve()
}

Serve() {
    global
    BX := Width / 2
    BY := PaddleY - 40
    Angle := -60 - 30 * RL.GetRandomValue(0, 60) / 60.0     ; degrees, roughly upward
    Rest := 0
}

HandleKeys() {
    global Paused, Vol
    if RL.IsKeyPressed(RL.KEY_P)
        Paused := !Paused
    if RL.IsKeyPressed(RL.KEY_R)
        Reset()
    if RL.IsKeyPressed(RL.KEY_M) {
        Vol := Vol > 0 ? 0.0 : 1.0
        if Blip
            RL.SetSoundVolume(Blip, Vol)
        if Clap
            RL.SetSoundVolume(Clap, Vol)
    }
}

Step(Dt) {
    global
    ; the paddle follows the mouse, or the keyboard if that is preferred
    PaddleX += RL.GetMouseX() - (PaddleX + PaddleW / 2)
    if RL.IsKeyDown(RL.KEY_A)
        PaddleX -= 620 * Dt
    if RL.IsKeyDown(RL.KEY_D)
        PaddleX += 620 * Dt
    PaddleX := PaddleX < 0 ? 0 : (PaddleX > Width - PaddleW ? Width - PaddleW : PaddleX)

    Rad := Angle * 0.0174532925199433
    BX += Speed * Cos(Rad) * Dt
    BY += Speed * Sin(Rad) * Dt

    ; walls
    if (BX < BallR) {
        BX := BallR, Angle := 180 - Angle
    } else if (BX > Width - BallR) {
        BX := Width - BallR, Angle := 180 - Angle
    }
    if (BY < BallR) {
        BY := BallR, Angle := -Angle
    }

    ; paddle: where it lands decides the new angle, which is what makes it playable
    if (RL.CheckCollisionCircleRec(BX, BY, BallR, PaddleX, PaddleY, PaddleW, PaddleH)
        && Sin(Angle) > 0) {
        Hit := (BX - (PaddleX + PaddleW / 2)) / (PaddleW / 2)     ; -1 .. 1
        Angle := -90 + 62 * (Hit < -1 ? -1 : (Hit > 1 ? 1 : Hit))
        BY := PaddleY - BallR - 1
        if Blip
            RL.PlaySound(Blip)
    }

    ; bricks
    Loop Rows {
        Row := A_Index
        Loop Cols {
            I := (Row - 1) * Cols + A_Index
            if !Alive[I]
                continue
            X := (A_Index - 1) * (BrickW + Gap) + Gap
            Y := Top + (Row - 1) * (BrickH + Gap)
            if RL.CheckCollisionCircleRec(BX, BY, BallR, X, Y, BrickW, BrickH) {
                Alive[I] := 0
                Left -= 1
                Score += 10 * (Rows - Row + 1)
                Angle := -Angle                      ; cheap but reads well
                if Clap
                    RL.PlaySound(Clap)
                if (Left == 0) {                     ; every brick gone
                    Speed *= 1.08
                    Reset()
                    return
                }
                break 2
            }
        }
    }

    ; missed the paddle
    if (BY > Height + BallR) {
        Lives -= 1
        Serve()
        Rest := A_TickCount
    }
    ; a lost round starts again on its own, so nobody mistakes it for a hang
    if (Lives <= 0 && A_TickCount - Rest > 2500) {
        Speed := 320.0
        Reset(true)
    }
}

RenderFrame() {
    global
    RL.BeginDrawing()
    RL.ClearBackground(RL.RAYWHITE)
    RL.DrawRectangleGradientV(0, 0, Width, Height, RL.WHITE, RL.LIGHTGRAY)

    ; bricks
    Loop Rows {
        Row := A_Index
        Loop Cols {
            I := (Row - 1) * Cols + A_Index
            if !Alive[I]
                continue
            X := (A_Index - 1) * (BrickW + Gap) + Gap
            Y := Top + (Row - 1) * (BrickH + Gap)
            RL.DrawRectangle(X, Y, BrickW, BrickH, RowColor[Row])
            RL.DrawRectangleLines(X, Y, BrickW, BrickH, RL.ColorAlpha(RL.DARKGRAY, 0.35))
        }
    }

    ; paddle, ball, and the line the ball is heading along
    RL.DrawRectangleRounded(PaddleX, PaddleY, PaddleW, PaddleH, 0.5, 8, RL.DARKBLUE)
    Rad := Angle * 0.0174532925199433
    RL.DrawLineV(BX, BY, BX + 26 * Cos(Rad), BY + 26 * Sin(Rad), RL.GRAY)
    RL.DrawCircleV(BX, BY, BallR, RL.MAROON)
    RL.DrawCircleLines(BX, BY, BallR + 3, RL.ColorAlpha(RL.MAROON, 0.3))

    ; status bar
    RL.DrawText("score " . Score, 16, 18, 22, RL.DARKGRAY)
    RL.DrawText("speed " . Round(Speed), 150, 18, 22, RL.GRAY)
    Loop Lives
        RL.DrawCircle(Width - 24 - 22 * (A_Index - 1), 30, 8, RL.MAROON)
    RL.DrawText("mouse or A/D, P pauses, R restarts, M mutes", 16, Height - 24, 15, RL.DARKGRAY)
    if (Lives <= 0)
        RL.DrawText("round over - starting again", Width / 2 - 110, Height / 2, 26, RL.MAROON)
    if Paused
        RL.DrawText("paused", Width / 2 - 42, Height / 2, 34, RL.DARKBLUE)
    RL.DrawFPS(Width - 100, Height - 46)
    RL.EndDrawing()
}
