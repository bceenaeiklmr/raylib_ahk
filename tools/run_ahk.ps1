# Run an AutoHotkey script headless and print its stdout/stderr and exit code.
#   powershell -ExecutionPolicy Bypass -File tools\run_ahk.ps1 tests\smoke.ahk
param(
    [Parameter(ValueFromRemainingArguments = $true)][string[]] $Args2
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$psi.Arguments = ($Args2 | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join " "
$psi.WorkingDirectory = $root
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = [System.Diagnostics.Process]::Start($psi)
$so = $p.StandardOutput.ReadToEnd()
$se = $p.StandardError.ReadToEnd()
if (-not $p.WaitForExit(120000)) { Stop-Process -Id $p.Id -Force; Write-Host "TIMEOUT after 120 s" }
$lines = (($so + "`n" + $se) -split "`n") | Where-Object { $_ -notmatch '^INFO' -and $_.Trim() }
$lines | ForEach-Object { Write-Host $_ }
Write-Host "exit: $($p.ExitCode)"
exit $p.ExitCode
