# Download raylib and place the runtime pieces in the repo:
#   lib\raylib.dll      the DLL the wrapper DllCall-s into
#   vendor\raylib.h     the header tools\gen_wrapper.py generates from
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

Write-Host "extracting to $root"
Expand-Archive $zip -DestinationPath $tmp -Force
$dir = (Get-ChildItem $tmp -Directory)[0].FullName
New-Item -ItemType Directory -Force -Path "$root\lib", "$root\vendor" | Out-Null
Copy-Item "$dir\lib\raylib.dll" "$root\lib\raylib.dll" -Force
Copy-Item "$dir\include\raylib.h" "$root\vendor\raylib.h" -Force
Remove-Item $tmp -Recurse -Force

Write-Host "raylib $tag installed:"
Write-Host ("  lib\raylib.dll   {0:N0} bytes" -f (Get-Item "$root\lib\raylib.dll").Length)
Write-Host ("  vendor\raylib.h  {0:N0} bytes" -f (Get-Item "$root\vendor\raylib.h").Length)
Write-Host "regenerate the wrapper with:  python tools\gen_wrapper.py"
