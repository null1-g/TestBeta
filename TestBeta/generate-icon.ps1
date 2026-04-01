$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$iconPath = Join-Path $projectRoot "app.ico"

Add-Type -AssemblyName System.Drawing

$size = 64
$bitmap = New-Object System.Drawing.Bitmap $size, $size
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::FromArgb(24, 18, 14))

$backgroundBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(224, 98, 47))
$accentBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(120, 213, 222))
$lightBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(246, 231, 208))
$ringPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(246, 231, 208), 3)
$crossPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(37, 22, 12), 3)

$graphics.FillEllipse($backgroundBrush, 6, 6, 52, 52)
$graphics.DrawEllipse($ringPen, 8, 8, 48, 48)
$graphics.FillEllipse($accentBrush, 23, 23, 18, 18)
$graphics.DrawLine($crossPen, 32, 12, 32, 22)
$graphics.DrawLine($crossPen, 32, 42, 32, 52)
$graphics.DrawLine($crossPen, 12, 32, 22, 32)
$graphics.DrawLine($crossPen, 42, 32, 52, 32)
$graphics.FillRectangle($lightBrush, 14, 46, 10, 4)
$graphics.FillRectangle($lightBrush, 26, 46, 10, 4)

$icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
$stream = [System.IO.File]::Create($iconPath)
$icon.Save($stream)
$stream.Dispose()

$graphics.Dispose()
$bitmap.Dispose()
$icon.Dispose()
$backgroundBrush.Dispose()
$accentBrush.Dispose()
$lightBrush.Dispose()
$ringPen.Dispose()
$crossPen.Dispose()

Write-Host "Built $iconPath"
