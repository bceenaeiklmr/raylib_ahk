<#
    Run the whole verification chain: regenerate, rebuild the shim, check the struct
    model and the API names, validate every script, and run the tests and every demo
    headlessly with a screenshot.

      powershell -ExecutionPolicy Bypass -File tools\check_all.ps1
#>
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)
$ahk = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
$fail = 0
$Demos = 'demo', 'shapes', 'textures', 'fonts', 'input', 'paddle', 'cube'

function Step([string]$name, [scriptblock]$body) {
    Write-Host "`n=== $name"
    & $body
    if ($LASTEXITCODE -ne 0) { $script:fail++; Write-Host "FAILED: $name (exit $LASTEXITCODE)" }
}

Step 'generate' { python tools\gen_wrapper.py | Select-Object -Last 3 }
Step 'build shim' { & tools\build_shim.ps1 | Select-Object -Last 1 }
Step 'struct model' { python tools\check_layout.py | Select-Object -Last 1 }
Step 'api names' { python tools\check_names.py | Select-Object -Last 1 }
Step 'precheck' { python tools\precheck.py | Select-Object -Last 3 }
Step 'validate lib' { & $ahk /Validate /ErrorStdOut lib\raylib.ahk 2>&1 }
Step 'validate tests' { & $ahk /Validate /ErrorStdOut tests\smoke.ahk 2>&1 }
foreach ($d in $Demos) {
    Step "validate $d" { & $ahk /Validate /ErrorStdOut "examples\$d.ahk" 2>&1 }
}
Step 'smoke test' { & $ahk /ErrorStdOut tests\smoke.ahk 2>&1 }
foreach ($d in $Demos) {
    Step "run $d" { & $ahk /ErrorStdOut '/auto:2500' "/shot:$d" "examples\$d.ahk" 2>&1 }
}

Write-Host "`nshots: $((Get-ChildItem tests\out\*.png).Count) files in tests\out"
if ($fail) { Write-Host "$fail step(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'all steps passed'
exit 0
