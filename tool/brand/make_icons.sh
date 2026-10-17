#!/bin/bash
# Renders the ATLAS Meridian app artwork from the guideline drawings (headless Chrome).
set -e
# Run from the repo root (Git Bash):  bash tool/brand/make_icons.sh
# then:  dart run flutter_launcher_icons
M="$(pwd)"
S="$(cygpath -m "$M/build/brand")"
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
rm -rf "$S"; mkdir -p "$S"

# Adaptive background: brand red, full bleed.
cat > "$S/background.svg" <<'X'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108"><rect width="108" height="108" fill="#ED0C2C"/></svg>
X
# Adaptive foreground + monochrome: the tile's white glyph alone, centred in the
# 66 dp safe zone of the 108 dp canvas (guideline p.15); the legs continue past
# the bottom edge like the app tile (they leave the tile, never stop short).
cat > "$S/foreground.svg" <<'X'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">
  <g transform="translate(18 18) scale(1.5)" fill="none" stroke="#FFFFFF" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round">
    <path d="M24 18C18.6 22.2 15 30 13.4 50L12.44 62"/>
    <path d="M24 18C29.4 22.2 33 30 34.6 50L35.56 62"/>
    <path d="M15.7 32.6Q24 37 32.3 32.6"/>
  </g>
  <circle cx="54" cy="34.8" r="5.25" fill="#FFFFFF"/>
</svg>
X
# Legacy launcher (Android 7): the app tile exactly as drawn (guideline p.16).
cat > "$S/legacy.svg" <<'X'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <clipPath id="tile"><rect width="48" height="48" rx="12"/></clipPath>
  <rect width="48" height="48" rx="12" fill="#ED0C2C"/>
  <g clip-path="url(#tile)" fill="none" stroke="#FFFFFF" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round">
    <path d="M24 18C18.6 22.2 15 30 13.4 50"/>
    <path d="M24 18C29.4 22.2 33 30 34.6 50"/>
    <path d="M15.7 32.6Q24 37 32.3 32.6"/>
  </g>
  <circle cx="24" cy="11.2" r="3.5" fill="#FFFFFF"/>
</svg>
X
# Notification icon: the one-colour WHITE mark (glyph cut out of the disc,
# guideline p.13) — Android draws it as a silhouette in the status bar.
cat > "$S/notify.svg" <<'X'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <defs>
    <clipPath id="globe"><circle cx="24" cy="24" r="22"/></clipPath>
    <mask id="glyph" maskUnits="userSpaceOnUse" x="0" y="0" width="48" height="48">
      <rect width="48" height="48" fill="#FFFFFF"/>
      <g clip-path="url(#globe)" fill="none" stroke="#000000" stroke-width="3.8" stroke-linecap="round" stroke-linejoin="round">
        <path d="M24 17.6C18 22 14.2 30 12.6 47"/>
        <path d="M24 17.6C30 22 33.8 30 35.4 47"/>
        <path d="M15 32.4Q24 37 33 32.4"/>
      </g>
      <circle cx="24" cy="10.6" r="3.6" fill="#000000"/>
    </mask>
  </defs>
  <circle cx="24" cy="24" r="22" fill="#FFFFFF" mask="url(#glyph)"/>
</svg>
X
# Splash: the full-colour mark (same on light and dark, guideline p.4).
cat > "$S/mark.svg" <<'X'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <clipPath id="globe"><circle cx="24" cy="24" r="22"/></clipPath>
  <circle cx="24" cy="24" r="22" fill="#ED0C2C"/>
  <g clip-path="url(#globe)" fill="none" stroke="#FFFFFF" stroke-width="3.8" stroke-linecap="round" stroke-linejoin="round">
    <path d="M24 17.6C18 22 14.2 30 12.6 47"/>
    <path d="M24 17.6C30 22 33.8 30 35.4 47"/>
    <path d="M15 32.4Q24 37 33 32.4"/>
  </g>
  <circle cx="24" cy="10.6" r="3.6" fill="#FFFFFF"/>
</svg>
X

render() { # svg size out
  local html="$S/$3.html"
  printf '<html><body style="margin:0;background:transparent"><img src="file:///%s" width="%s" height="%s" style="display:block"></body></html>' "$(cygpath -m "$S/$1")" "$2" "$2" > "$html"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 --allow-file-access-from-files --window-size=$2,$2 --screenshot="$(cygpath -w "$S/$3")" "file:///$(cygpath -m "$html")" >/dev/null 2>&1
  echo "rendered $3 (${2}px)"
}
render background.svg 1024 icon_background.png
render foreground.svg 1024 icon_foreground.png
cp "$S/icon_foreground.png" "$S/icon_monochrome.png"
render legacy.svg 1024 icon_legacy.png
render mark.svg 384 splash_logo.png
for d in mdpi:24 hdpi:36 xhdpi:48 xxhdpi:72 xxxhdpi:96; do render notify.svg ${d#*:} "ic_stat_${d%:*}.png"; done

# Into the app.
for f in icon_background icon_foreground icon_legacy icon_monochrome; do cp "$S/$f.png" "$M/assets/brand/"; done
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do cp "$S/ic_stat_$d.png" "$M/android/app/src/main/res/drawable-$d/ic_stat_hris.png"; done
cp "$S/splash_logo.png" "$M/android/app/src/main/res/drawable-nodpi/"
cp "$S/splash_logo.png" "$M/android/app/src/main/res/drawable-night-nodpi/"
echo "copied into assets/brand and android/app/src/main/res"
