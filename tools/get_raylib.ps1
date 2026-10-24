# Download raylib and place the runtime pieces in the repo:
#   lib\raylib.dll              the DLL the wrapper DllCall-s into
#   vendor\raylib.lib           import library, links tools\shim.c
#   vendor\raylib.h             the header tools\gen_wrapper.py generates from
#   vendor\raymath.h, rlgl.h    remaining headers
#
#   powershell -ExecutionPolicy Bypass -File tools\get_raylib.ps1 [-Version 5.5]
param([string] $Version = "5.5")

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tag = (Invoke-RestMethod "https://api.github.com/repos/raysan5/raylib/releases/tags/$Version").tag_name
$asset = (Invoke-RestMethod "https://api.github.com/repos/raysan5/raylib/releases/tags/$Version").assets |
    Where-Object { $_.name -like "*win64_msvc*" } | Select-Object -First 1
if (-not $asset) { throw "no win64 msvc asset found for $Version" }

$tmp = Join-Path $env:TEMP ("raylib_" + $Version)
$zip = Join-Path $tmp "raylib.zip"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Write-Host "downloading $($asset.name)"
Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing

Expand-Archive $zip -DestinationPath $tmp -Force
$dir = (Get-ChildItem $tmp -Directory)[0].FullName
New-Item -ItemType Directory -Force -Path "$root\lib", "$root\vendor" | Out-Null
Copy-Item "$dir\lib\raylib.dll" "$root\lib\raylib.dll" -Force
Copy-Item "$dir\include\*.h" "$root\vendor\" -Force
Remove-Item $tmp -Recurse -Force

Write-Host "raylib $tag installed:"
foreach ($f in 'lib\raylib.dll', 'vendor\raylib.lib', 'vendor\raylib.h') {
    Write-Host ("  {0,-18} {1,10:N0} bytes" -f $f, (Get-Item "$root\$f").Length)
}
Write-Host "regenerate the wrapper with:  python tools\gen_wrapper.py"
Write-Host "rebuild the shim with:        powershell tools\build_shim.ps1"
