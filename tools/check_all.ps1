<#
    Run a headless verification chain: regenerate, rebuild the shim, check the struct
    model, validate every script, and run the tests.

      powershell -ExecutionPolicy Bypass -File tools\check_all.ps1
#>
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)
$ahk = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
$fail = 0

function Step([string]$name, [scriptblock]$body) {
    Write-Host "`n=== $name"
    & $body
    if ($LASTEXITCODE -ne 0) { $script:fail++; Write-Host "FAILED: $name (exit $LASTEXITCODE)" }
}

Step 'generate' { python tools\gen_wrapper.py | Select-Object -Last 3 }
Step 'build shim' { & tools\build_shim.ps1 | Select-Object -Last 1 }
Step 'struct model' { python tools\check_layout.py | Select-Object -Last 1 }
Step 'validate lib' { & $ahk /Validate /ErrorStdOut lib\raylib.ahk 2>&1 }
Step 'validate tests' { & $ahk /Validate /ErrorStdOut tests\smoke.ahk 2>&1 }
Step 'validate demo' { & $ahk /Validate /ErrorStdOut examples\demo.ahk 2>&1 }`nStep 'validate cube' { & $ahk /Validate /ErrorStdOut examples\cube.ahk 2>&1 }
Step 'smoke test' { & $ahk /ErrorStdOut tests\smoke.ahk 2>&1 }
Step 'demo' { & $ahk /ErrorStdOut '/auto:7000' examples\demo.ahk 2>&1 }
Step 'cube' { & $ahk /ErrorStdOut '/auto:2500' '/shot:cube' examples\cube.ahk 2>&1 }

if ($fail) { Write-Host "`n$fail step(s) failed"; exit 1 }
Write-Host "`nall steps passed"
exit 0
