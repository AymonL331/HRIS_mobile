# Generates the launcher-icon sources from the web brand block (a primary dot):
#   assets/brand/icon_foreground.png  1024x1024, transparent, #2563eb dot (adaptive foreground)
#   assets/brand/icon_legacy.png      1024x1024, #f1f5f9 page colour, #2563eb dot (legacy mipmaps)
# Run from the project root:  powershell -ExecutionPolicy Bypass -File tool/brand/make_icons.ps1
# Then:  dart run flutter_launcher_icons
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out = Join-Path $root "assets\brand"
New-Item -ItemType Directory -Force $out | Out-Null

function Draw-Icon([string]$path, [System.Drawing.Color]$bg, [int]$dot) {
  $size = 1024
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear($bg)
  $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml("#2563eb"))
  $offset = ($size - $dot) / 2
  $g.FillEllipse($brush, $offset, $offset, $dot, $dot)
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose(); $brush.Dispose()
  Write-Host "wrote $path"
}

# The adaptive foreground must keep its mark inside the central 66% safe zone.
Draw-Icon (Join-Path $out "icon_foreground.png") ([System.Drawing.Color]::Transparent) 400
Draw-Icon (Join-Path $out "icon_legacy.png") ([System.Drawing.ColorTranslator]::FromHtml("#f1f5f9")) 480
