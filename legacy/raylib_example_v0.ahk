
#Requires AutoHotkey >=v2.0.0
#Warn

#Include raylib.ah2

Width  := 1920
Height := 1080
Title  := "raylib autohotkey wrapper"

InitWindow(Width, Height, Title)
;CloseWindow()

SetClipboardText("Hello bence")

dbg := 0
if dbg {
	Msgbox "IsWindowReady" "`t" IsWindowReady() "`n"
	. "IsWindowFullscreen" "`t" IsWindowFullscreen() "`n"
	. "IsWindowHidden" "`t" IsWindowHidden() "`n"
	. "IsWindowMinimized" "`t" IsWindowMinimized() "`n"
	. "IsWindowMaximized" "`t" IsWindowMaximized() "`n"
	. "IsWindowFocused" "`t" IsWindowFocused() "`n"
	. "IsWindowResized" "`t" IsWindowResized() "`n"
	. "GetScreenWidth" "`t" GetScreenWidth() "`n"
	. "GetScreenHeight" "`t" GetScreenHeight() "`n"
	. "GetMonitorCount" "`t" GetMonitorCount() "`n"
	. "GetCurrentMonitor" "`t" (m := GetCurrentMonitor()) "`n"
	. "GetMonitorWidth" "`t" GetMonitorWidth(m) "`n"
	. "GetMonitorHeight" "`t" GetMonitorHeight(m) "`n"
	. "GetMonitorPhysicalWidth" "`t" GetMonitorPhysicalWidth(m) "`n"
	. "GetMonitorPhysicalHeight" "`t" GetMonitorPhysicalHeight(m) "`n"
	. "GetMonitorRefreshRate" "`t" GetMonitorRefreshRate(m) "`n"
	. "GetMonitorName" "`t" GetMonitorName(m) "`n"
	 ;"GetClipboardText" "`t" GetClipboardText() "`n"
}

SetWindowTitle(Title " test")
;SetWindowPosition(0, 0)
;SetWindowOpacity(.75)
;SetWindowMonitor(1)
;SetWindowMinSize(Width, Height)
;SetWindowSize(1280, 720)

SetTargetFPS(144)

vFPS := 0, rad := 1

while !WindowShouldClose() {

    BeginDrawing()

    ClearBackground(0x00000000)
        
    DrawLine(50, 50, 50+A_index, 50, 0xFFADADFF)
    
    rad := (!Mod(rad, 100)) ? 1 : rad+1
    DrawCircleGradient(150, 200, rad, 0x00FF00FF, 0xFF0000FF)

    DrawEllipse(150, 300, 10, 10, 0xFF00FFFF)

    DrawEllipseLines(150, 700, 30, 30, 0xFFADADFF)

    DrawRectangle(50, 400, A_index, 50, 0xFF00ABFF)

    DrawRectangleGradientV(50, 500, A_index, 50, 0x00FF00FF, 0xFF0000FF)

    DrawRectangleGradientH(50, 600, A_index, 50, 0x00FF00FF, 0xFF0000FF)
    
    DrawText(title, 500, 200, 34, 0xFF0000FF)

    DllCall("raylib.dll\DrawRectangle", "int", 500, "int", 200, "int", 500, "int", 50, "uint", 0xFF0000FF)

    EndDrawing()

    ;tooltip "current fps is " GetFPS()
}
