<#
    Build the README artwork: a banner, a labelled screenshot gallery, a pipeline
    diagram and a rule. Everything is drawn from the demo screenshots that
    tools\check_all.ps1 writes, so the pictures can never drift from what the demos
    actually render.

      powershell -ExecutionPolicy Bypass -File tools\art.ps1

    Sizes are 2x so GitHub's scaled-down rendering stays sharp on HiDPI screens.
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Set-Location (Split-Path $PSScriptRoot -Parent)
if (-not (Test-Path docs)) { New-Item -ItemType Directory docs | Out-Null }

# raylib's own palette, so the art matches what the library draws
$Ink = [System.Drawing.Color]::FromArgb(255, 247, 247, 247)      # RAYWHITE
$Sky = [System.Drawing.Color]::FromArgb(255, 89, 203, 239)       # SKYBLUE
$Deep = [System.Drawing.Color]::FromArgb(255, 39, 80, 155)       # DARKBLUE
$Nite = [System.Drawing.Color]::FromArgb(255, 16, 24, 43)        # night blue
$Muted = [System.Drawing.Color]::FromArgb(255, 150, 170, 195)
$Paper = [System.Drawing.Color]::FromArgb(255, 246, 248, 250)

$Title = New-Object System.Drawing.Font('Segoe UI Black', 66)
$Sub = New-Object System.Drawing.Font('Segoe UI Semilight', 26)
$Head = New-Object System.Drawing.Font('Segoe UI Semibold', 21)
$Body = New-Object System.Drawing.Font('Segoe UI', 18)
$Small = New-Object System.Drawing.Font('Segoe UI', 15)
$White = New-Object System.Drawing.SolidBrush $Ink
$SkyBrush = New-Object System.Drawing.SolidBrush $Sky
$Panel = [System.Drawing.Color]::FromArgb(255, 32, 42, 54)            # slate, not white
$PanelBrush = New-Object System.Drawing.SolidBrush $Panel
$DeepBrush = New-Object System.Drawing.SolidBrush $Deep
$MutedBrush = New-Object System.Drawing.SolidBrush $Muted
$Format = New-Object System.Drawing.StringFormat
$Format.Alignment = 'Center'

function New-Canvas([int]$w, [int]$h, [System.Drawing.Color]$back) {
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'ClearTypeGridFit'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.Clear($back)
    return @($bmp, $g)
}

function Save([System.Drawing.Bitmap]$bmp, [System.Drawing.Graphics]$g, [string]$name) {
    $g.Dispose()
    $path = Join-Path 'docs' $name
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    "{0,-16} {1,9:N0} bytes" -f $name, (Get-Item $path).Length
}

function Gradient([System.Drawing.Graphics]$g, [System.Drawing.Rectangle]$r,
                  [System.Drawing.Color]$a, [System.Drawing.Color]$b) {
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r, $a, $b, 35)
    $g.FillRectangle($br, $r); $br.Dispose()
}

function Shot([string]$name) {
    $p = "tests\out\$name.png"
    if (-not (Test-Path $p)) { throw "missing $p - run tools\check_all.ps1 first" }
    [System.Drawing.Image]::FromFile((Resolve-Path $p).Path)
}

function Tile([System.Drawing.Graphics]$g, [System.Drawing.Image]$img,
              [int]$x, [int]$y, [int]$w) {
    $h = [int]($img.Height * $w / $img.Width)
    $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60, 0, 0, 0))
    $g.FillRectangle($shadow, $x + 6, $y + 8, $w, $h)
    $shadow.Dispose()
    $g.DrawImage($img, $x, $y, $w, $h)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, 255, 255, 255)), 2
    $g.DrawRectangle($pen, $x, $y, $w, $h); $pen.Dispose()
    return $h
}

# ---------------------------------------------------------------- banner 1920x600
$bmps = @((Shot 'shapes'), (Shot 'cube'), (Shot 'paddle'))
$pair = New-Canvas 1920 600 $Nite
$bmp, $g = $pair
$rect = New-Object System.Drawing.Rectangle 0, 0, 1920, 600
Gradient $g $rect $Nite $Deep

# a faint shape field, echoing what the library draws
$ghost = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(34, 255, 255, 255)), 3
for ($i = 0; $i -lt 9; $i++) { $g.DrawEllipse($ghost, 1180 + $i * 42, 90 + ($i % 3) * 120, 260, 260) }
$ghost.Dispose()
$ghostFill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(46, 89, 203, 239))
$g.FillEllipse($ghostFill, 1500, 340, 200, 200)
$ghostFill.Dispose()

$g.DrawString('raylib.ahk', $Title, $White, 96, 120)
$underline = New-Object System.Drawing.SolidBrush $Sky
$g.FillRectangle($underline, 100, 268, 452, 9); $underline.Dispose()
$g.DrawString('raylib 5.5 for AutoHotkey v2', $Sub, $White, 96, 306)
$g.DrawString('497 of 581 functions bound  -  generated from raylib.h  -  no compiler needed',
    (New-Object System.Drawing.Font('Segoe UI', 19)), $MutedBrush, 96, 372)
$Badges = @(
    'Windows x64',
    'AutoHotkey v2.0+',
    'MIT (raylib: zlib)'
)
$y = 448
foreach ($b in $Badges) { $g.DrawString($b, $Small, $MutedBrush, 96, $y); $y += 26 }

# three demo tiles, fanned along the right edge
$sizes = @(430, 360, 330)
for ($i = 0; $i -lt 3; $i++) {
    # 40 + 155 per step keeps the lowest tile and its shadow inside the 600 px canvas
    & Tile $g $bmps[$i] (1120 + $i * 62) (40 + $i * 155) $sizes[$i] | Out-Null
}
Save $bmp $g 'banner.png'
foreach ($b in $bmps) { $b.Dispose() }

# ---------------------------------------------------------------- gallery 1920 wide
$Demos = @(
    @{ f = 'shapes'; t = 'shapes.ahk'; d = 'every 2D primitive, one per labelled cell' },
    @{ f = 'cube'; t = 'cube.ahk'; d = '3D, orbital camera, a texture built in RAM' },
    @{ f = 'textures'; t = 'textures.ahk'; d = 'procedural textures, tints, sprite sheet, offscreen pass' },
    @{ f = 'fonts'; t = 'fonts.ahk'; d = 'LoadFontEx at four sizes, spacing, DrawTextPro' },
    @{ f = 'input'; t = 'input.ahk'; d = 'held keys, UTF-8 characters, five buttons, wheel, gamepad' },
    @{ f = 'paddle'; t = 'paddle.ahk'; d = 'playable bricks, delta-time physics, sound from RAM' },
    @{ f = 'demo'; t = 'demo.ahk'; d = 'gravity, wall bounces, cursor spring, fading trail' }
)
$Cols = 3
$CellW = 586
$GapX = 40
$Caption = 108                       # room for the title and description under a tile
$Top = 56

# measure first: a row's height is its tallest tile, or tiles walk over each other
$Imgs = @()
foreach ($d in $Demos) {
    $img = Shot $d.f
    $Imgs += [pscustomobject]@{
        Img = $img
        H = [int]($img.Height * $CellW / $img.Width)
        T = $d.t
        D = $d.d
    }
}
$Rows = [math]::Ceiling(($Imgs.Count + 1) / $Cols)     # +1 for the numbers tile
$Ys = @()
$y = $Top
for ($r = 0; $r -lt $Rows; $r++) {
    $tallest = 0
    for ($c = 0; $c -lt $Cols; $c++) {
        $i = $r * $Cols + $c
        if ($i -lt $Imgs.Count -and $Imgs[$i].H -gt $tallest) { $tallest = $Imgs[$i].H }
    }
    $Ys += $y
    $y += $tallest + $Caption
}
$CanvasH = $y + 150
$pair = New-Canvas 1920 ([int]$CanvasH) $Paper
$bmp, $g = $pair
$InkBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 32, 42, 54))
$GreyBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 96, 108, 122))

for ($i = 0; $i -lt $Imgs.Count; $i++) {
    $col = $i % $Cols; $row = [math]::Floor($i / $Cols)
    $x = $GapX + $col * ($CellW + $GapX)
    & Tile $g $Imgs[$i].Img $x $Ys[$row] $CellW | Out-Null
    $g.DrawString($Imgs[$i].T, $Head, $InkBrush, $x, $Ys[$row] + $Imgs[$i].H + 24)
    $g.DrawString($Imgs[$i].D, $Small, $GreyBrush, $x, $Ys[$row] + $Imgs[$i].H + 60)
}

# the last cell: what the generator actually bound, so the grid is not lopsided
$i = $Imgs.Count
$col = $i % $Cols; $row = [math]::Floor($i / $Cols)
$x = $GapX + $col * ($CellW + $GapX)
$rowTop = $Ys[$row]
$h = $Imgs[$row * $Cols].H
$g.FillRectangle($PanelBrush, $x, $rowTop, $CellW, $h)
$ty = $rowTop + 26
$g.DrawString('the numbers', $Head, $White, $x + 28, $ty)
$ty += 52
foreach ($line in @(
    '497 of 581 functions bound',
    '218 by plain DllCall',
    '279 through the C shim',
    '84 left out, reason recorded',
    '308 constants, 26 colours',
    '25 structs with accessors',
    '69 pixel checks, 0 failures'
)) {
    $g.DrawString($line, $Small, $White, $x + 28, $ty)
    $ty += 29
}
# and the last cell: the two commands that get a window open
$i = $Imgs.Count + 1
$col = $i % $Cols
$row = [math]::Floor($i / $Cols)
if ($i -lt $Rows * $Cols) {
    $x = $GapX + $col * ($CellW + $GapX)
    $h = $Imgs[$row * $Cols].H
    $g.FillRectangle($DeepBrush, $x, $Ys[$row], $CellW, $h)
    $ty = $Ys[$row] + 26
    $g.DrawString('run one', $Head, $White, $x + 28, $ty)
    $ty += 52
    $Mono = New-Object System.Drawing.Font('Consolas', 15)
    foreach ($line in @(
        'git clone https://github.com/',
        '  bceenaeiklmr/raylib_ahk',
        '',
        'cd raylib_ahk',
        '"C:\Program Files\AutoHotkey\',
        '  v2\AutoHotkey64.exe" \',
        '  examples\demo.ahk'
    )) {
        $g.DrawString($line, $Mono, $White, $x + 28, $ty)
        $ty += 27
    }
    $g.DrawString('64-bit AutoHotkey v2 is the only', $Small, $White, $x + 28, $ty + 10)
    $g.DrawString('requirement: no compiler, no raylib', $Small, $White, $x + 28, $ty + 36)
    $g.DrawString('install, no runtime redist.', $Small, $White, $x + 28, $ty + 62)
}

foreach ($m in $Imgs) { $m.Img.Dispose() }

$note = $Ys[$Rows - 1] + 470
$g.DrawString('Every image above was captured by the demo itself with RL.ScreenShot(), a wrapper around', $Small, $GreyBrush, $GapX, $note)
$g.DrawString('LoadImageFromScreen() + ExportImage(): TakeScreenshot() takes only a bare name, resolves it', $Small, $GreyBrush, $GapX, $note + 26)
$g.DrawString('against the startup directory, and hands back the frame one swap behind the one you asked for.', $Small, $GreyBrush, $GapX, $note + 52)
Save $bmp $g 'gallery.png'

# ---------------------------------------------------------------- pipeline 1920x620
$pair = New-Canvas 1920 620 $Paper
$bmp, $g = $pair
$g.DrawString('How a call gets from a script to the GPU', $Head, $InkBrush, 60, 34)

$BoxPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 32, 42, 54)), 3

$SkyPen = New-Object System.Drawing.Pen $Sky, 5
$DarkPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 32, 42, 54)), 5

function Node([int]$x, [int]$y, [int]$w, [int]$h, [string]$title, [string[]]$lines, [switch]$accent) {
    if ($accent) { $g.FillRectangle($DeepBrush, $x, $y, $w, $h) }
    else { $g.FillRectangle($PanelBrush, $x, $y, $w, $h) }
    $brush = $White
    $ty = $y + 22
    $g.DrawString($title, $Head, $brush, $x + 24, $ty)
    $ty += 44
    foreach ($l in $lines) { $g.DrawString($l, $Small, $brush, $x + 24, $ty); $ty += 26 }
}
function Arrow([int]$x1, [int]$y1, [int]$x2, [int]$y2, [System.Drawing.Pen]$pen) {
    # shorten the shaft so the head does not sit on top of it
    $dx = $x2 - $x1; $dy = $y2 - $y1
    $len = [math]::Sqrt($dx * $dx + $dy * $dy)
    $ux = $dx / $len; $uy = $dy / $len
    $g.DrawLine($pen, $x1, $y1, [int]($x2 - $ux * 14), [int]($y2 - $uy * 14))
    $brush = if ($pen -eq $SkyPen) { $SkyBrush } else { $InkBrush }
    $nx = -$uy; $ny = $ux
    $bx = [int]($x2 - $ux * 15); $by = [int]($y2 - $uy * 15)
    $p1 = New-Object System.Drawing.Point([int]($bx + $nx * 9), [int]($by + $ny * 9))
    $p2 = New-Object System.Drawing.Point($x2, $y2)
    $p3 = New-Object System.Drawing.Point([int]($bx - $nx * 9), [int]($by - $ny * 9))
    $g.FillPolygon($brush, [System.Drawing.Point[]]@($p1, $p2, $p3))
}

Node 60 150 400 200 'your script' @('RL.DrawRectangle(...)', 'RL.LoadFontEx(...)', 'plain AHK strings,', '0xRRGGBBAA colours') -accent:$false
Node 620 150 560 200 'lib\raylib.ahk' @('generated: 497 functions,', '308 constants, 26 colours,', 'read/write struct accessors', 'RL.ABGR, RL.U8, RL.Codepoints')
Node 1380 108 480 176 'raylib.dll  (218 calls)' @('flat arguments only:', 'ints, floats, pointers,', 'Color as one UInt')
Node 1380 320 480 208 'raylib_ahk_shim.dll  (279)' @('one rla_* wrapper per', 'struct-by-value function;', 'prebuilt, 151 KB, MIT')
Node 620 408 560 132 'tools\gen_wrapper.py' @('parses vendor\raylib.h and writes', 'both files: regenerate, never patch')

Arrow 460 250 620 250 $DarkPen
Arrow 1180 196 1380 196 $DarkPen
Arrow 1180 424 1380 424 $SkyPen
Node 60 408 400 132 'AutoHotkey64.exe' @('DllCall, no P/Invoke', 'no marshalling layer')
Arrow 260 408 260 350 $DarkPen
$g.DrawString('the shim exists because DllCall cannot pass', $Small, $GreyBrush, 1380, 542)
$g.DrawString('a struct larger than 8 bytes by value', $Small, $GreyBrush, 1380, 568)
Save $bmp $g 'pipeline.png'

# ---------------------------------------------------------------- rule 1920x24
$pair = New-Canvas 1920 24 ([System.Drawing.Color]::White)
$bmp, $g = $pair
$fade = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Rectangle 0, 0, 1920, 24),
    ([System.Drawing.Color]::FromArgb(0, 89, 203, 239)),
    ([System.Drawing.Color]::FromArgb(200, 89, 203, 239)),
    [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
$g.FillRectangle($fade, 0, 8, 1920, 8)
$fade.Dispose()
Save $bmp $g 'rule.png'

'art written to docs\'
