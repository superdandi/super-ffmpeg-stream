#!/usr/bin/env bash
set -euo pipefail

STREAM_KEY="${1:-}"
OVERLAY="${2:-}"
RES="1366x768"
FPS="24"
V_BITRATE="1500k"
A_BITRATE="96k"

if [[ -z "$STREAM_KEY" ]]; then
    echo "Uso: $0 TU_STREAM_KEY [ruta/overlay.png]"
    echo ""
    echo "Si pasas un PNG transparente como segundo argumento,"
    echo "se superpondrá en la esquina inferior derecha."
    exit 1
fi

# Inputs base
INPUTS=(
    -video_size "$RES" -framerate "$FPS" -f x11grab -i :0.0+0,0
    -f pulse -i "$(pactl get-default-sink).monitor"
)

# Filtros
FILTERS=""

if [[ -n "$OVERLAY" ]]; then
    INPUTS+=(-i "$OVERLAY")
    FILTERS="-filter_complex overlay=main_w-overlay_w-10:main_h-overlay_h-10"
fi

ffmpeg "${INPUTS[@]}" \
       $FILTERS \
       -c:v libx264 -preset ultrafast -b:v "$V_BITRATE" \
       -maxrate "$V_BITRATE" -bufsize 3000k \
       -pix_fmt yuv420p -g 48 \
       -c:a aac -b:a "$A_BITRATE" -ar 44100 \
       -f flv "rtmp://live.twitch.tv/app/$STREAM_KEY"
