# Builds every launcher / splash source from the two brand masters (the same
# artwork the website uses, transparent, 1024px):
#   assets/brand/hris-icon-light-1024.png   light-surface artwork
#   assets/brand/hris-icon-dark-1024.png    dark-surface artwork (glow)
# Outputs:
#   assets/brand/icon_foreground.png   adaptive foreground: the mark inside the safe zone
#   assets/brand/icon_legacy.png       legacy (Android 7) icon: the mark, nearly full-bleed
#   assets/brand/icon_monochrome.png   themed icons + the notification icon: the person and
#                                      the three lines only, white — a filled card would be a
#                                      featureless block at status-bar size
#   android/app/src/main/res/drawable-<density>/ic_stat_hris.png   notification icon, glyph full-size
#   android/app/src/main/res/drawable-nodpi/splash_logo.png        splash, light theme
#   android/app/src/main/res/drawable-night-nodpi/splash_logo.png  splash, dark theme
# Run from the project root:  powershell -ExecutionPolicy Bypass -File tool/brand/make_icons.ps1
# Then:  dart run flutter_launcher_icons
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

public static class BrandIcons {
  static Graphics Hq(Bitmap b) {
    var g = Graphics.FromImage(b);
    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
    g.CompositingQuality = CompositingQuality.HighQuality;
    g.SmoothingMode = SmoothingMode.HighQuality;
    return g;
  }

  // `src` drawn centred on a transparent `size` canvas at `fraction` of its width.
  public static Bitmap Place(Bitmap src, int size, double fraction) {
    var outBmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
    using (var g = Hq(outBmp)) {
      g.Clear(Color.Transparent);
      int side = (int)Math.Round(size * fraction);
      int off = (size - side) / 2;
      g.DrawImage(src, new Rectangle(off, off, side, side));
    }
    return outBmp;
  }

  // The glyph (person + lines) of a placed light icon: its light, opaque pixels
  // inside the card's content area, as white with the pixel's own coverage. The
  // content rectangle (fractions of the MARK, not the canvas) leaves out the pale
  // rim between the two cards.
  public static Bitmap Glyph(Bitmap placed, double fraction) {
    int size = placed.Width;
    var outBmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
    var r = new Rectangle(0, 0, size, size);
    var sd = placed.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    var od = outBmp.LockBits(r, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    byte[] s = new byte[sd.Stride * size], o = new byte[od.Stride * size];
    Marshal.Copy(sd.Scan0, s, 0, s.Length);
    double side = size * fraction, off = (size - side) / 2;
    int x0 = (int)(off + side * 0.08), x1 = (int)(off + side * 0.80);
    int y0 = (int)(off + side * 0.20), y1 = (int)(off + side * 0.76);
    for (int y = 0; y < size; y++) for (int x = 0; x < size; x++) {
      int i = y * sd.Stride + x * 4;
      byte a = 0;
      if (x >= x0 && x <= x1 && y >= y0 && y <= y1 && s[i + 3] > 200) {
        double lum = 0.2126 * s[i + 2] + 0.7152 * s[i + 1] + 0.0722 * s[i];
        double t = (lum - 120) / (190 - 120);
        t = t < 0 ? 0 : (t > 1 ? 1 : t);
        a = (byte)Math.Round(255 * t);
      }
      o[i] = 255; o[i + 1] = 255; o[i + 2] = 255; o[i + 3] = a;
    }
    Marshal.Copy(o, 0, od.Scan0, o.Length);
    placed.UnlockBits(sd); outBmp.UnlockBits(od);
    return outBmp;
  }

  // The opaque bounding square of `src` (alpha above 16), for cropping a glyph
  // tight before it is resized to a status-bar icon.
  public static Rectangle Bounds(Bitmap src) {
    int w = src.Width, h = src.Height;
    var r = new Rectangle(0, 0, w, h);
    var d = src.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    byte[] p = new byte[d.Stride * h];
    Marshal.Copy(d.Scan0, p, 0, p.Length);
    src.UnlockBits(d);
    int minX = w, minY = h, maxX = -1, maxY = -1;
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
      if (p[y * d.Stride + x * 4 + 3] <= 16) continue;
      if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y;
    }
    int bw = maxX - minX + 1, bh = maxY - minY + 1, side = Math.Max(bw, bh);
    return new Rectangle(minX + bw / 2 - side / 2, minY + bh / 2 - side / 2, side, side);
  }

  // `box` of `src`, filling `fraction` of a transparent `size` square.
  public static void CropTo(Bitmap src, Rectangle box, int size, double fraction, string path) {
    using (var outBmp = new Bitmap(size, size, PixelFormat.Format32bppArgb))
    using (var g = Hq(outBmp)) {
      g.Clear(Color.Transparent);
      int side = (int)Math.Round(size * fraction), off = (size - side) / 2;
      g.DrawImage(src, new Rectangle(off, off, side, side), box, GraphicsUnit.Pixel);
      outBmp.Save(path, ImageFormat.Png);
    }
  }

  public static void Resize(Bitmap src, int size, string path) {
    using (var outBmp = new Bitmap(size, size, PixelFormat.Format32bppArgb))
    using (var g = Hq(outBmp)) {
      g.Clear(Color.Transparent);
      g.DrawImage(src, new Rectangle(0, 0, size, size));
      outBmp.Save(path, ImageFormat.Png);
    }
  }
}
"@

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$brand = Join-Path $root "assets\brand"
$res = Join-Path $root "android\app\src\main\res"
$light = [System.Drawing.Bitmap]::FromFile((Join-Path $brand "hris-icon-light-1024.png"))
$dark = [System.Drawing.Bitmap]::FromFile((Join-Path $brand "hris-icon-dark-1024.png"))

# flutter_launcher_icons insets the foreground by 16%; the mark at 72% of the
# layer then spans ~49% of the icon — inside a circular mask on every launcher.
$fgFraction = 0.72
$fg = [BrandIcons]::Place($light, 1024, $fgFraction)
$fg.Save((Join-Path $brand "icon_foreground.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$mono = [BrandIcons]::Glyph($fg, $fgFraction)
$mono.Save((Join-Path $brand "icon_monochrome.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$legacy = [BrandIcons]::Place($light, 1024, 0.92)
$legacy.Save((Join-Path $brand "icon_legacy.png"), [System.Drawing.Imaging.ImageFormat]::Png)

# The notification (status-bar) icon: the same glyph, cropped tight and filling
# the 24dp square — the launcher monochrome is sized for the launcher's safe zone
# and would read at half size in the status bar.
$glyphBox = [BrandIcons]::Bounds($mono)
foreach ($d in @(@("mdpi", 24), @("hdpi", 36), @("xhdpi", 48), @("xxhdpi", 72), @("xxxhdpi", 96))) {
  $dir = Join-Path $res ("drawable-" + $d[0])
  [BrandIcons]::CropTo($mono, $glyphBox, $d[1], 0.92, (Join-Path $dir "ic_stat_hris.png"))
}

foreach ($pair in @(@("drawable-nodpi", $light), @("drawable-night-nodpi", $dark))) {
  $dir = Join-Path $res $pair[0]
  New-Item -ItemType Directory -Force $dir | Out-Null
  [BrandIcons]::Resize($pair[1], 384, (Join-Path $dir "splash_logo.png"))
}
$fg.Dispose(); $mono.Dispose(); $legacy.Dispose(); $light.Dispose(); $dark.Dispose()
Write-Host "wrote icon_foreground / icon_monochrome / icon_legacy / splash_logo (light + dark)"
