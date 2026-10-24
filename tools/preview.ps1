<#
    Compose docs/preview.png from the demo screenshots, so the README opens with a
    picture of what the bindings draw. Run tools\check_all.ps1 first: it writes the
    screenshots this reads.

      powershell -ExecutionPolicy Bypass -File tools\preview.ps1
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Set-Location (Split-Path $PSScriptRoot -Parent)

# name on the tile, and the screenshot it comes from
$Tiles = @(
    @{ Label = 'shapes.ahk - every 2D primitive';    File = 'tests\out\shapes.png' },
    @{ Label = 'cube.ahk - 3D, texture, special characters'; File = 'tests\out\cube.png' },
    @{ Label = 'textures.ahk - sprite sheet, offscreen pass'; File = 'tests\out\textures.png' },
    @{ Label = 'paddle.ahk - playable bricks';       File = 'tests\out\paddle.png' }
)

$CellW = 620
$LabelH = 34
$Gap = 8

# scale every shot to the same width and keep its aspect
$Sizes = @()
foreach ($Tile in $Tiles) {
    if (-not (Test-Path $Tile.File)) { throw "missing screenshot: $($Tile.File) (run tools\check_all.ps1)" }
    $img = [System.Drawing.Image]::FromFile((Resolve-Path $Tile.File))
    $Sizes += [pscustomobject]@{ W = $CellW; H = [int]($img.Height * $CellW / $img.Width) }
    $img.Dispose()
}

$Cols = 2
$Rows = [math]::Ceiling($Tiles.Count / $Cols)
$CellH = ($Sizes | Measure-Object -Property H -Maximum).Maximum
$W = $Cols * $CellW + ($Cols + 1) * $Gap
$H = $Rows * ($CellH + $LabelH) + ($Rows + 1) * $Gap

$Bmp = New-Object System.Drawing.Bitmap $W, $H
$G = [System.Drawing.Graphics]::FromImage($Bmp)
$G.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$G.Clear([System.Drawing.Color]::FromArgb(245, 245, 245))
$Font = New-Object System.Drawing.Font('Segoe UI', 10)
$Brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(80, 80, 80))

for ($i = 0; $i -lt $Tiles.Count; $i++) {
    $Col = $i % $Cols
    $Row = [math]::Floor($i / $Cols)
    $X = $Gap + $Col * ($CellW + $Gap)
    $Y = $Gap + $Row * ($CellH + $LabelH + $Gap)
    $img = [System.Drawing.Image]::FromFile((Resolve-Path $Tiles[$i].File))
    $G.DrawImage($img, $X, $Y, $CellW, $Sizes[$i].H)
    $img.Dispose()
    $G.DrawString($Tiles[$i].Label, $Font, $Brush, $X, $Y + $Sizes[$i].H + 4)
}
$G.Dispose()

if (-not (Test-Path docs)) { New-Item -ItemType Directory docs | Out-Null }
$Bmp.Save("$PWD\docs\preview.png", [System.Drawing.Imaging.ImageFormat]::Png)
$Bmp.Dispose()
"$W x $H -> docs\preview.png  ($((Get-Item docs\preview.png).Length) bytes)"
