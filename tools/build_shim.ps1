# Build lib\raylib_ahk_shim.dll from the generated vendor\shim.c.
#
# AutoHotkey's DllCall cannot pass or return structs larger than 8 bytes by value,
# so the shim gives those raylib functions a flat ABI. Only a rebuild after a
# raylib version bump needs this script; the DLL is committed, so users need no
# compiler and no build step.
#
#   powershell -ExecutionPolicy Bypass -File tools\build_shim.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build"
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

foreach ($need in "$root\vendor\shim.c", "$root\vendor\raylib.def") {
    if (-not (Test-Path $need)) {
        throw "$(Split-Path $need -Leaf) is missing, run:  python tools\gen_wrapper.py"
    }
}
if (-not (Test-Path $vswhere)) {
    throw @"
No Visual Studio Installer found at $vswhere
Install the C++ build tools, then rerun this script:
  winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools --passive --wait"
"@
}
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath | Select-Object -First 1
if (-not $vs) { throw "no MSVC toolchain (missing Microsoft.VisualStudio.Component.VC.Tools.x86.x64)" }
$vcvars = Join-Path $vs "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) { throw "not found: $vcvars" }

New-Item -ItemType Directory -Force -Path $build | Out-Null
$dll = Join-Path $root "lib\raylib_ahk_shim.dll"
# Link into build\ first. Writing straight over lib\raylib_ahk_shim.dll leaves a window
# where the file is a partially written image, and a demo that loads it in that instant
# reports "Failed to load downloaded DLL"; a script that is already running holds the file
# open and makes the write fail outright.
$staged = Join-Path $build "raylib_ahk_shim.dll"
$implib = Join-Path $build "raylib_import.lib"

# An import library built from the header's own export list. The release also ships
# raylib.lib, but that is the static library: linking it would embed a second,
# private copy of raylib in the shim, with window and texture state that the
# raylib.dll AutoHotkey calls into knows nothing about.
$bat = Join-Path $build "compile.bat"
@(
    '@echo off'
    'call "' + $vcvars + '" >nul || exit /b 1'
    'lib /nologo /def:"' + (Join-Path $root "vendor\raylib.def") + '" /machine:x64' +
        ' /out:"' + $implib + '" || exit /b 1'
    'cl /nologo /MT /O2 /W3 /D_CRT_SECURE_NO_WARNINGS /LD "' + (Join-Path $root "vendor\shim.c") + '"' +
        ' /Fe:"' + $staged + '" /link /Brepro /IMPLIB:"' + (Join-Path $build "raylib_ahk_shim.lib") + '"' +
        ' "' + $implib + '" || exit /b 1'
) | Set-Content $bat -Encoding Ascii

Push-Location $build
try {
    & cmd.exe /c "`"$bat`""
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}
Remove-Item "$build\shim.obj", $bat -Force -ErrorAction SilentlyContinue
if ($code -ne 0) { throw "the build failed with exit code $code" }

# Publish it only if it changed, and retry a little if a running demo still has the old one
# loaded. /Brepro makes the image byte-stable, so an unchanged shim is now a no-op here.
if ((Test-Path $dll) -and
        (Get-FileHash $staged -Algorithm SHA256).Hash -eq (Get-FileHash $dll -Algorithm SHA256).Hash) {
    Write-Host 'lib\raylib_ahk_shim.dll unchanged, left in place'
} else {
    $copied = $false
    for ($try = 1; $try -le 20 -and -not $copied; $try++) {
        try { Copy-Item $staged $dll -Force; $copied = $true }
        catch { Start-Sleep -Milliseconds 250 }
    }
    if (-not $copied) {
        throw @"
Could not replace lib\raylib_ahk_shim.dll: a running script still has it loaded.
Close any demo window (or the script that opened it) and run this script again.
The newly built copy is at build\raylib_ahk_shim.dll
"@
    }
}

# /Brepro leaves the timestamp out of the image, so rebuilding the same shim.c produces
# the same bytes. The DLL is committed, and a build that rewrote it every time would
# leave the working tree permanently dirty and the diff useless.
Write-Host ("lib\raylib_ahk_shim.dll  {0:N0} bytes  sha256 {1}" -f (Get-Item $dll).Length,
    (Get-FileHash $dll -Algorithm SHA256).Hash)
Write-Host "regenerate both with:  python tools\gen_wrapper.py  &&  powershell tools\build_shim.ps1"
