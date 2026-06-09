#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

echo "==> Actualizando vizcoso-pelis (Super Producciones)..."
yt-dlp --flat-playlist --print "%(title)s | %(webpage_url)s" \
  "https://www.youtube.com/playlist?list=PL58F985571B763484" \
  > "$SCRIPT_DIR/vizcoso-pelis"

echo "==> Actualizando vizcoso-musicales (music playlist + Arseniko + Bye Bye Bikinis)..."
yt-dlp --flat-playlist --print "%(title)s | %(webpage_url)s" \
  "https://www.youtube.com/playlist?list=PLKCoMIUhCOzWJcczu8WvxxF7XntBbCLSU" \
  > "$SCRIPT_DIR/vizcoso-musicales"
echo "Arseniko - LA KZ | https://www.youtube.com/watch?v=Xz8ja6W1PZM" >> "$SCRIPT_DIR/vizcoso-musicales"
echo "Bye Bye Bikinis En Vivo | https://www.youtube.com/watch?v=ubV2gTvxT2A" >> "$SCRIPT_DIR/vizcoso-musicales"

echo "==> Actualizando vizcoso-animaciones..."
cat > "$SCRIPT_DIR/vizcoso-animaciones" <<- EOF
VIZCOSO SESSION | https://www.youtube.com/watch?v=oU7BLWWvK58
Vizcoso Entertainment | https://www.youtube.com/watch?v=-HNVOKPp0Vg
EOF

echo "=== Hecho ==="
wc -l "$SCRIPT_DIR/vizcoso-pelis" "$SCRIPT_DIR/vizcoso-musicales" "$SCRIPT_DIR/vizcoso-animaciones"
