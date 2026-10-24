<#
    Answer one question about a script file: is it readable, and is it the file git has?

    Two intermittent errors have been seen while the repo was being rewritten from another
    process - `Missing "#Include" directive argument` and `Failed to read text file`. Both
    are what a partially written or briefly locked file looks like to the interpreter, and
    neither reproduces on a stable tree. This reports what it can see, with a plain verdict.

      powershell -ExecutionPolicy Bypass -File tools\check_file.ps1 examples\cube.ahk
#>
param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not (Test-Path $Path)) { throw "no such file: $Path" }
$full = (Resolve-Path $Path).Path

$item = Get-Item $Path
"file        : $full"
"size        : {0:N0} bytes, last written {1}" -f $item.Length, $item.LastWriteTime
"attributes  : $((Get-Item $Path).Attributes)"
"streams     : " + ((Get-Item $Path -Stream * -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Stream)=$($_.Length)" }) -join ', ')

# Try to read it the way the interpreter does, and name the Win32 reason if that fails.
$read = $null
for ($try = 1; $try -le 5; $try++) {
    try {
        $fs = [System.IO.File]::Open($full, 'Open', 'Read', ([System.IO.FileShare]::ReadWrite))
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        $read = $sr.ReadToEnd()
        $sr.Close(); $fs.Close()
        break
    } catch {
        if ($try -eq 5) { "read attempt: FAILED after 5 tries - $($_.Exception.Message)" }
        Start-Sleep -Milliseconds 200
    }
}
if ($null -ne $read) {
    "read attempt: OK ($($read.Length) chars) on try $try"
    # A truncated write shows up as an #Include with nothing after it.
    $bad = @()
    foreach ($line in $read -split "`r?`n") {
        if ($line -match '^\s*#Include\s*$') { $bad += $line }
    }
    if ($bad.Count) { "include check: " + ($bad.Count) + " empty #Include line(s)" }
    else {
        $inc = @($read -split "`r?`n" | Where-Object { $_ -match '^\s*#Include' })
        "include check: $($inc.Count) directive(s), all with an argument"
        foreach ($i in $inc) {
            $arg = ($i -replace '^\s*#Include\s+', '').Trim()
            $dir = Split-Path $full -Parent
            $resolved = if ($arg -like '*%*') {
                $arg -replace '%A_ScriptDir%', $dir
            } elseif ($arg -match '^\.{1,2}[\\/]') {
                [System.IO.Path]::GetFullPath((Join-Path $dir $arg))
            } else {
                Join-Path $dir $arg
            }
            "    $arg  ->  $resolved  exists=$((Test-Path $resolved))"
        }
    }
}

# Is the copy on disk the committed one? An editor buffer that saved half a file, or a
# file that was never saved from, both show up here.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { "git          : not on PATH, skipped" }
else {
    $disk = (Get-FileHash $Path -Algorithm SHA256).Hash
    $obj = (git hash-object $Path).Trim()
    $inIndex = git status --porcelain -- $Path
    "hash disk   : $disk"
    "hash git    : $obj (object id for these bytes)"
    "vs HEAD     : " + $(if ($inIndex.Trim()) { "DIFFERENT - the working copy has been modified:" + $inIndex } else { "identical to the committed file" })
}

"antivirus     : " + ($(Get-MpComputerStatus -ErrorAction SilentlyContinue | ForEach-Object RealTimeProtectionEnabled))
"interpreter   : " + (Get-Item 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe').VersionInfo.ProductVersion
$bad = & 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /Validate /ErrorStdOut $Path 2>&1
"validate      : exit $LASTEXITCODE" + $(if ($bad) { " " + (($bad | Select-Object -First 1)))
