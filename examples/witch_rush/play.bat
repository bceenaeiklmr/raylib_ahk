@echo off
title Junk Food Witch: Broom Rush
cd /d "%~dp0"
if exist "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe" (
    start "" "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe" "%~dp0witch_rush.ahk" %*
) else (
    start "" "%~dp0witch_rush.ahk" %*
)
