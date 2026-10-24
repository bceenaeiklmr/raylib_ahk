; Shared plumbing for the examples, so a demo can be about raylib instead of about
; argument parsing. Include it after your own directives:
;
;     #Include ..\lib\raylib.ahk
;     #Include harness.ahk
;
; It sets two globals:
;   AutoExit   milliseconds after which the window closes by itself (0 = never), /auto[:ms]
;   ShotPath   full path of the screenshot to write before closing, /shot:name
;
; and installs an error handler that prints to stdout and exits non-zero, which is what
; makes a headless run fail loudly instead of sitting there with a frozen window.
#Requires AutoHotkey v2.0
#Warn All, StdOut

; AutoHotkey includes every file once, so an example that also includes raylib.ahk is
; fine, and validating this file on its own does not warn about an unknown RL class.
#Include ..\lib\raylib.ahk

OnError(ExampleError)

AutoExit := 0, ShotName := "", ShotPath := ""
for Arg in A_Args {
    if (SubStr(Arg, 1, 5) = "/auto") {
        Colon := InStr(Arg, ":")
        AutoExit := Colon ? Integer(SubStr(Arg, Colon + 1)) : 3000
    } else if (SubStr(Arg, 1, 5) = "/shot") {
        Colon := InStr(Arg, ":")
        ShotName := Colon ? SubStr(Arg, Colon + 1) : "example"
    }
}
if (ShotName != "" && !InStr(ShotName, "."))
    ShotName .= ".png"   ; raylib picks the image format from the extension
if (ShotName != "") {
    ; raylib keeps a copy of the working directory from startup, so it is set here,
    ; before InitWindow, and A_WorkingDir resolves the ".." for a plain full path.
    SetWorkingDir A_ScriptDir "\..\tests\out"
    ShotPath := A_WorkingDir "\" ShotName
}

; Draw one more frame through Draw, then write the screenshot. TakeScreenshot() reads
; one buffer swap behind, so a demo that is asked for a picture draws once more first.
; ScreenShot() takes a full path, which TakeScreenshot() refuses to.
Shoot(Draw) {
    global   ; the includer owns RL, AutoExit and ShotPath
    if (ShotPath == "")
        return
    Draw.Call()
    RL.ScreenShot(ShotPath)
}

; Any TrueType on the system will do; arial first because it is always there.
FindTtf() {
    static Names := ["arial.ttf", "segoeui.ttf", "tahoma.ttf", "calibri.ttf", "cour.ttf"]
    for Name in Names {
        if FileExist(A_WinDir "\Fonts\" Name)
            return A_WinDir "\Fonts\" Name
    }
    Loop Files A_WinDir "\Fonts\*.ttf"
        return A_LoopFileFullPath
    return ""
}

ExampleError(err, mode) {
    FileAppend("[ERROR] " err.Message "`n"
        . "File: " err.File " (Line " err.Line ")`n"
        . "Stack:`n" err.Stack "`n", "**")
    ExitApp(1)
}
