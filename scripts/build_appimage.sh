#!/usr/bin/env bash
# Builds a release Termex AppImage into dist/.
# Needs: flutter, appimagetool, ImageMagick (for the icon).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
APPDIR=build/Termex.AppDir

flutter build linux --release

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" dist
cp -r build/linux/x64/release/bundle/. "$APPDIR/usr/bin/"

cat > "$APPDIR/AppRun" <<'RUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/termex" "$@"
RUN
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/termex.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Termex
Comment=SSH & SFTP client with an encrypted, synced vault
Exec=termex
Icon=termex
Categories=Network;System;TerminalEmulator;
Terminal=false
StartupWMClass=com.example.termex
DESK

# Icon in Lumen colours: accent prompt on the dark background.
magick -size 256x256 xc:none \
  -fill '#14171C' -draw 'roundrectangle 8,8 248,248 48,48' \
  -fill none -stroke '#7C8CFF' -strokewidth 22 -draw 'polyline 70,80 128,128 70,176' \
  -stroke none -fill '#7C8CFF' -draw 'roundrectangle 138,166 196,186 8,8' \
  "$APPDIR/termex.png"

ARCH=x86_64 appimagetool --no-appstream "$APPDIR" "dist/Termex-$VERSION-x86_64.AppImage"
echo "Built dist/Termex-$VERSION-x86_64.AppImage"
