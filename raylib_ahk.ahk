#DllLoad "%A_ScriptDir%\raylib.dll"

; Windows-related functions

; Initialize window and OpenGL context
InitWindow(Width, Height, Title := "") {
    DllCall("raylib.dll\InitWindow", "Int", Width, "Int", Height, "AStr", Title)
}

; Check if KEY_ESCAPE pressed or Close icon pressed
WindowShouldClose() {
    return DllCall("raylib.dll\WindowShouldClose")
}

; Close window and unload OpenGL context
CloseWindow() {
    DllCall("raylib.dll\CloseWindow")
}

; Check if window has been initialized successfully
IsWindowReady() {
    return DllCall("raylib.dll\IsWindowReady")
}

; Check if window is currently fullscreen
IsWindowFullscreen() {
    return DllCall("raylib.dll\IsWindowFullscreen")
}

; Check if window is currently hidden (only PLATFORM_DESKTOP)
IsWindowHidden() {
    return DllCall("raylib.dll\IsWindowHidden")
}

; Check if window is currently minimized (only PLATFORM_DESKTOP)
IsWindowMinimized() {
    return DllCall("raylib.dll\IsWindowMinimized")
}

; Check if window is currently maximized (only PLATFORM_DESKTOP)
IsWindowMaximized() {
    return DllCall("raylib.dll\IsWindowMaximized")
}

; Check if window is currently focused (only PLATFORM_DESKTOP)
IsWindowFocused() {
    return DllCall("raylib.dll\IsWindowFocused")
}

; Check if window has been resized last frame
IsWindowResized() {
    return DllCall("raylib.dll\IsWindowResized")
}

; bool IsWindowState(unsigned int flag);                      // Check if one specific window flag is enabled
IsWindowState(Flag) {
    return DllCall("raylib.dll\IsWindowState", "uint", Flag)
}

; void SetWindowState(unsigned int flags);                    // Set window configuration state using flags (only PLATFORM_DESKTOP)
SetWindowState(Flags) {
    return DllCall("raylib.dll\SetWindowState", "uint", Flags)
}

; void ClearWindowState(unsigned int flags);                  // Clear window configuration state flags
ClearWindowState(Flags) {
    return DllCall("raylib.dll\ClearWindowState", "uint", Flags)
}

; Toggle window state: fullscreen/windowed (only PLATFORM_DESKTOP)
ToggleFullscreen() {
    DllCall("raylib.dll\ToggleFullscreen")
}

; Set window state: maximized, if resizable (only PLATFORM_DESKTOP)
MaximizeWindow() {
    DllCall("raylib.dll\MaximizeWindow")
}

; Set window state: minimized, if resizable (only PLATFORM_DESKTOP)
MinimizeWindow() {
    DllCall("raylib.dll\MinimizeWindow")
}

; Set window state: not minimized/maximized (only PLATFORM_DESKTOP)
RestoreWindow() {
    DllCall("raylib.dll\RestoreWindow")
}

; void SetWindowIcon(Image image); // Set icon for window (only PLATFORM_DESKTOP)

; void SetWindowTitle(const char *title); // Set title for window (only PLATFORM_DESKTOP)
SetWindowTitle(Title := "") {
    DllCall("raylib.dll\SetWindowTitle", "AStr", Title)
}
 
; void SetWindowPosition(int x, int y); // Set window position on screen (only PLATFORM_DESKTOP)
SetWindowPosition(x, y) {
    DllCall("raylib.dll\SetWindowPosition", "int", x, "int", y)
}

; Set monitor for the current window (fullscreen mode)
SetWindowMonitor(Monitor) {
    DllCall("raylib.dll\SetWindowMonitor", "int", Monitor)
}

; Set window minimum dimensions (for FLAG_WINDOW_RESIZABLE)
SetWindowMinSize(Width, Height) {
    DllCall("raylib.dll\SetWindowMinSize", "int", Width, "int", Height)
}

; Set window dimensions
SetWindowSize(Width, Height) {
    DllCall("raylib.dll\SetWindowSize", "int", Width, "int", Height)
}

; Set window opacity [0.0f..1.0f] (only PLATFORM_DESKTOP)
SetWindowOpacity(Opacity := 1) {
    DllCall("raylib.dll\SetWindowOpacity", "float", Opacity)
}

; void *GetWindowHandle(void); // Get native window handle

; Get current screen width | int GetScreenWidth(void)
GetScreenWidth() {
    DllCall("raylib.dll\GetScreenWidth")
}

; Get current screen height
GetScreenHeight() {
    return DllCall("raylib.dll\GetScreenHeight")
}

; Get current render width (it considers HiDPI)
GetRenderWidth() {
    return DllCall("raylib.dll\GetRenderWidth")
}

; Get current render height (it considers HiDPI)
GetRenderHeight() {
    return DllCall("raylib.dll\GetRenderHeight")
}

; Get number of connected monitors
GetMonitorCount() {
    return DllCall("raylib.dll\GetMonitorCount")
}

; Get current connected monitor
GetCurrentMonitor() {
    return DllCall("raylib.dll\GetCurrentMonitor")
}

; Vector2 GetMonitorPosition(int monitor);                    // Get specified monitor position

; Get specified monitor width (current video mode used by monitor)
GetMonitorWidth(Monitor) {
    return DllCall("raylib.dll\GetMonitorWidth", "int", Monitor)
}

; Get specified monitor height (current video mode used by monitor)
GetMonitorHeight(Monitor) {
    return DllCall("raylib.dll\GetMonitorHeight", "int", Monitor)
}

; Get specified monitor physical width in millimetres
GetMonitorPhysicalWidth(Monitor) {
    return DllCall("raylib.dll\GetMonitorPhysicalWidth", "int", Monitor)
}

; Get specified monitor physical height in millimetres
GetMonitorPhysicalHeight(Monitor) {
    return DllCall("raylib.dll\GetMonitorPhysicalHeight", "int", Monitor)
}

; Get specified monitor refresh rate
GetMonitorRefreshRate(Monitor) {
    return DllCall("raylib.dll\GetMonitorRefreshRate", "int", Monitor)
}

; Vector2 GetWindowPosition(void);                            // Get window position XY on monitor
; Vector2 GetWindowScaleDPI(void);                            // Get window scale DPI factor

; Get the human-readable, UTF-8 encoded name of the primary monitor | const char *GetMonitorName(int monitor); 
GetMonitorName(Monitor) {
    return DllCall("raylib.dll\GetMonitorName")
}

; void SetClipboardText(const char *text);                    // Set clipboard text content
SetClipboardText(Text) {
    DllCall("raylib.dll\SetClipboardText", "AStr", Text)
}

; const char *GetClipboardText(void);                         // Get clipboard text content
GetClipboardText() {
    DllCall("raylib.dll\GetClipboardText")
}

; void EnableEventWaiting(void);                              // Enable waiting for events on EndDrawing(), no automatic event polling
EnableEventWaiting() {
    DllCall("raylib.dll\EnableEventWaiting")
}

; void DisableEventWaiting(void);                             // Disable waiting for events on EndDrawing(), automatic events polling
DisableEventWaiting() {
    DllCall("raylib.dll\DisableEventWaiting")
}

; Load texture from file into GPU memory (VRAM)
LoadTexture(fileName) {
    return DllCall("raylib.dll\LoadTexture", "AStr", fileName)
}

;void DrawTexture(Texture2D texture, int posX, int posY, Color tint);
; Draw a Texture2D
DrawTexture(Texture, posX, posY, Color := 0xFFFFFFFF) {
    DllCall("raylib.dll\DrawTexture", "ptr*", Texture, "int", posX, "int", posY, "uint", GetColor(Color)) ;  
}

; Draw rectangle within an image
ImageDrawRectangle(Image, posX, posY, width, height, Color) {
    DllCall("raylib.dll\ImageDrawRectangle", "int*", Image, "int", posX, "int", posY, "int", Width, "int", Height, "uint", GetColor(color))
}

LoadImage(fileName) {
    return DllCall("raylib.dll\LoadImage", "AStr", fileName)  ; image struct
}

IsImageReady(Image) {
    return DllCall("raylib.dll\IsImageReady", "ptr*", Image)
}

DrawText(Text, posX, posY, fontSize, Color) {
    DllCall("raylib.dll\DrawText", "AStr", Text, "int", posX, "int", posY, "int", fontSize, "uint", GetColor(color))
}

GetFontDefault() {
    return DllCall("raylib.dll\GetFontDefault")
}

; Set background color (framebuffer clear color)
ClearBackground(Color) {
    DllCall("raylib.dll\ClearBackground", "uint", GetColor(Color))
}

; Setup canvas (framebuffer) to start drawing
BeginDrawing() {
    DllCall("raylib.dll\BeginDrawing")
}

; End canvas drawing and swap buffers (double buffering)
EndDrawing() {
    DllCall("raylib.dll\EndDrawing")
}

; module: r shapes

SetTargetFPS(fps := 0) {
    DllCall("raylib.dll\SetTargetFPS", "Int", fps)
}

GetFPS() {
    return DllCall("raylib.dll\GetFPS")
}

; Get time in seconds for last frame drawn (delta time)
GetFrameTime() {
    return DllCall("raylib.dll\GetFrameTime")
}

; Get elapsed time in seconds since InitWindow()
GetTime() {
    return DllCall("raylib.dll\GetTime")
}

DrawFPS(posX, posY) {
    DllCall("raylib.dll\InitWindow", "Int", posX, "Int", posY)
}

; Draw a line
DrawLine(startPosX, startPosY, endPosX, endPosY, color := 0xFFFFFFFF) {
    DllCall("raylib.dll\DrawLine", "Int", startPosX, "Int", startPosY, "Int", endPosX, "Int", endPosY, "uint", GetColor(color))
}

; Draw a gradient-filled circle
DrawCircleGradient(centerX, centerY, Radius, Color1, Color2) {
    DllCall("raylib.dll\DrawCircleGradient", "int", centerX, "int", centerY, "float", Radius, "uint", GetColor(color1), "uint", GetColor(color2))
}

; DrawEllipse(int centerX, int centerY, float radiusH, float radiusV, Color color
DrawEllipse(centerX, centerY, RadiusH, RadiusV, Color) {
    DllCall("raylib.dll\DrawEllipse", "int", centerX, "int", centerY, "float", RadiusH, "float", RadiusV, "uint", GetColor(color))
}

; DrawEllipseLines(int centerX, int centerY, float radiusH, float radiusV, Color color)
DrawEllipseLines(centerX, centerY, RadiusH, RadiusV, Color) {
    DllCall("raylib.dll\DrawEllipseLines", "int", centerX, "int", centerY, "float", RadiusH, "float", RadiusV, "uint", GetColor(color))
}

; 
DrawRectangle(posX, posY, Width, Height, Color) {
    DllCall("raylib.dll\DrawRectangle", "int", posX, "int", posY, "int", width, "int", height, "uint", GetColor(color))
}

; DrawRectangleRec(Rectangle rec, Color color);                                                 // Draw a color-filled rectangle

; Draw a vertical-gradient-filled rectangle
DrawRectangleGradientV(posX, posY, width, height, color1, color2) {
    DllCall("raylib.dll\DrawRectangleGradientV", "int", posX, "int", posY, "int", width, "int", height, "uint", GetColor(color1), "uint", GetColor(color2))
}

; Draw a horizontal-gradient-filled rectangle
DrawRectangleGradientH(posX, posY, width, height, color1, color2) {
    DllCall("raylib.dll\DrawRectangleGradientH", "int", posX, "int", posY, "int", width, "int", height, "uint", GetColor(color1), "uint", GetColor(color2))
}

; void DrawRectangleLinesEx(Rectangle rec, float lineThick, Color color);                            // Draw rectangle outline with extended parameters
;DrawRectangleLinesEx(posX, posY, width, height, color1, color2) {
;    DllCall("raylib.dll\DrawRectangleLinesEx", "int", posX, "int", posY, "int", width, "int", height, "uint", GetColor(color1), "uint", GetColor(color2))
;}

; void DrawRectangleRounded(Rectangle rec, float roundness, int segments, Color color);              // Draw rectangle with rounded edges
GetColor(hexValue := 0xFFFFFFFF) {
    return DllCall("raylib.dll\GetColor", "Uint", hexValue)
}

; Get hexadecimal value for a Color
;ColorToInt(Color) {
;    return DllCall("raylib.dll\ColorToInt")
;}

; Cursor-related functions

; Shows cursor
ShowCursor() {
    DllCall("raylib.dll\ShowCursor")
}

; Hides cursor
HideCursor() {
    DllCall("raylib.dll\HideCursor")
}

; Check if cursor is not visible
IsCursorHidden() {
    return DllCall("raylib.dll\IsCursorHidden")
}

; Enables cursor (unlock cursor)
EnableCursor() {
    DllCall("raylib.dll\EnableCursor")
}

; Disables cursor (lock cursor)
DisableCursor() {
    DllCall("raylib.dll\DisableCursor")
}

; Check if cursor is on the screen
IsCursorOnScreen() {
    return DllCall("raylib.dll\IsCursorOnScreen")
}
