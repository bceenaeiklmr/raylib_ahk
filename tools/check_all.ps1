<#
    Run the whole verification chain: regenerate, rebuild the shim, check the struct
    model and the API names, validate every script, and run the tests and every demo
    headlessly.

    Three traps this works around, all of them real bugs it used to hide:

      - AutoHotkey64.exe is a GUI-subsystem program. PowerShell's call operator does not
        wait for one and does not take $LASTEXITCODE from it, so a step inherited the
        previous step's exit code and seven failing demos reported success. Run-Ahk waits
        and returns the real code.
      - A switch before the script name is taken as the script name itself:
        `AutoHotkey64.exe /shot:x demo.ahk` dies with "Script file not found". Built-in
        switches go before the script, the demo's own /auto and /shot go after it.
      - An exit code says nothing about pixels. Each shot is deleted before its run and
        then sampled, so a demo that silently did nothing fails instead of leaving an old
        screenshot where a new one should be.

      powershell -ExecutionPolicy Bypass -File tools\check_all.ps1
#>
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Set-Location (Split-Path $PSScriptRoot -Parent)
$ahk = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
$fail = 0
$Demos = 'demo', 'shapes', 'textures', 'fonts', 'input', 'paddle', 'cube'

function Step([string]$name, [scriptblock]$body) {
    Write-Host "`n=== $name"
    & $body
    if ($LASTEXITCODE -ne 0) { $script:fail++; Write-Host "FAILED: $name (exit $LASTEXITCODE)" }
}

# Run the interpreter to completion. Built-in switches before the script, the script's
# own arguments after it. Returns the interesting output lines and sets $LASTEXITCODE.
function Run-Ahk {
    param([string]$Script, [string[]]$Pre = @(), [string[]]$Post = @())
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ahk
    $all = @($Pre) + @('/ErrorStdOut', $Script) + @($Post)
    $psi.Arguments = ($all | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' '
    $psi.WorkingDirectory = $PWD.Path
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $so = $p.StandardOutput.ReadToEnd()
    $se = $p.StandardError.ReadToEnd()
    if (-not $p.WaitForExit(180000)) {
        Stop-Process -Id $p.Id -Force
        Write-Host '  TIMEOUT after 180 s'
        $global:LASTEXITCODE = 124
        return ''
    }
    $kept = @(($so + "`n" + $se) -split "`r?`n" |
        Where-Object { $_ -and $_ -notmatch '^(INFO|WARNING|DEBUG)' })
    $kept | ForEach-Object { Write-Host "  $_" }
    $global:LASTEXITCODE = $p.ExitCode
    return $kept
}

# Count distinct colours in a grid of samples: a frame that rendered nothing has one.
function Test-Shot([string]$path) {
    if (-not (Test-Path $path)) {
        Write-Host "  FAILED: no screenshot at $path"
        $global:LASTEXITCODE = 1
        return
    }
    $bmp = New-Object System.Drawing.Bitmap $path
    $colours = @{}
    for ($y = 0; $y -lt $bmp.Height; $y += [math]::Max(1, $bmp.Height / 40)) {
        for ($x = 0; $x -lt $bmp.Width; $x += [math]::Max(1, $bmp.Width / 60)) {
            $c = $bmp.GetPixel($x, $y)
            $colours[($c.R -shl 16) -bor ($c.G -shl 8) -bor $c.B] = 1
        }
    }
    $w = $bmp.Width; $h = $bmp.Height
    $bmp.Dispose()
    $n = $colours.Count
    Write-Host "  shot: ${w}x${h}, $n distinct colours"
    if ($n -lt 4) {
        Write-Host '  FAILED: the frame is blank'
        $global:LASTEXITCODE = 1
    }
}

Step 'generate' { python tools\gen_wrapper.py | Select-Object -Last 3 }
Step 'build shim' { & tools\build_shim.ps1 | Select-Object -Last 1 }
Step 'struct model' { python tools\check_layout.py | Select-Object -Last 1 }
Step 'api names' { python tools\check_names.py | Select-Object -Last 1 }
Step 'precheck' { python tools\precheck.py | Select-Object -Last 3 }
Step 'validate lib' { Run-Ahk -Script 'lib\raylib.ahk' -Pre @('/Validate') | Out-Null }
Step 'validate tests' { Run-Ahk -Script 'tests\smoke.ahk' -Pre @('/Validate') | Out-Null }
foreach ($d in $Demos) {
    Step "validate $d" { Run-Ahk -Script "examples\$d.ahk" -Pre @('/Validate') | Out-Null }
}

Step 'smoke test' {
    $lines = Run-Ahk -Script 'tests\smoke.ahk'
    $report = $lines -join "`n"
    if ($LASTEXITCODE -eq 0 -and $report -notmatch 'failures: 0') {
        Write-Host '  FAILED: the smoke test did not report zero failures'
        $global:LASTEXITCODE = 1
    }
}

foreach ($d in $Demos) {
    Step "run $d" {
        Remove-Item "tests\out\$d.png" -ErrorAction SilentlyContinue
        Run-Ahk -Script "examples\$d.ahk" -Post @("/auto:2500", "/shot:$d") | Out-Null
        if ($LASTEXITCODE -eq 0) { Test-Shot "tests\out\$d.png" }
    }
}

$minute = (Get-Date).AddMinutes(-10)
$fresh = @($Demos | Where-Object {
    $p = "tests\out\$_.png"
    (Test-Path $p) -and ((Get-Item $p).LastWriteTime -gt $minute)
})
Write-Host "`nshots: $($fresh.Count)/$($Demos.Count) refreshed this run"
if ($fresh.Count -ne $Demos.Count) { Write-Host 'FAILED: missing screenshots'; exit 1 }
if ($fail) { Write-Host "$fail step(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'all steps passed'
exit 0
