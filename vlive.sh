#!/usr/bin/env bash
set -euo pipefail

STREAM_KEY="${1:-}"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PARRILLA="$SCRIPT_DIR/parrilla"
STATE_FILE="$SCRIPT_DIR/.vlive_state"
OVERLAY="$HOME/Descargas/vizcosotransparente.png"
V_BITRATE="1500k"
A_BITRATE="96k"

if [[ -z "$STREAM_KEY" ]]; then
    echo "Uso: $0 TU_STREAM_KEY"
    exit 1
fi

if [[ ! -f "$PARRILLA" ]]; then
    echo "Error: no se encuentra $PARRILLA"
    exit 1
fi

has_overlay=0
[[ -f "$OVERLAY" ]] && has_overlay=1

# Inicializar .vlive_state si no existe
if [[ ! -f "$STATE_FILE" ]]; then
    > "$STATE_FILE"
fi

obtener_categoria() {
    local hora_actual
    hora_actual=$(date +%H:%M)
    local hora_h hora_m
    hora_h=$(date +%H)
    hora_m=$(date +%M)
    local hora_actual_minutos=$(( 10#$hora_h * 60 + 10#$hora_m ))

    while IFS='|' read -r rango categoria; do
        rango="${rango// /}"
        categoria="${categoria// /}"
        [[ -z "$rango" || "$rango" == \#* ]] && continue

        local inicio="${rango%%-*}"
        local fin="${rango##*-}"

        local inicio_h="${inicio%%:*}"
        local inicio_m="${inicio##*:}"
        local fin_h="${fin%%:*}"
        local fin_m="${fin##*:}"

        local inicio_total=$(( 10#$inicio_h * 60 + 10#$inicio_m ))
        local fin_total=$(( 10#$fin_h * 60 + 10#$fin_m ))

        # Cruza la medianoche (ej: 22:00-06:00)
        if (( fin_total <= inicio_total )); then
            if (( hora_actual_minutos >= inicio_total || hora_actual_minutos < fin_total )); then
                echo "$categoria"
                return 0
            fi
        else
            if (( hora_actual_minutos >= inicio_total && hora_actual_minutos < fin_total )); then
                echo "$categoria"
                return 0
            fi
        fi
    done < "$PARRILLA"

    # Fallback: primera categoria
    head -n1 "$PARRILLA" | grep -oP '\|\s*\K\w+'
}

obtener_indice() {
    local categoria="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep "^$categoria " "$STATE_FILE" | head -1 | awk '{print $2}'
    fi
}

guardar_indice() {
    local categoria="$1"
    local indice="$2"
    if grep -q "^$categoria " "$STATE_FILE" 2>/dev/null; then
        sed -i "s/^$categoria .*/$categoria $indice/" "$STATE_FILE"
    else
        echo "$categoria $indice" >> "$STATE_FILE"
    fi
}

cargar_urls() {
    local archivo="$1"
    grep -v '^#' "$archivo" | grep '|' | sed 's/^[^|]*| *//' | grep -v '^$'
}

trap 'echo "Stream finalizado"; exit 0' INT TERM

echo "Stream iniciado. Leyendo horario de $PARRILLA"
echo "Overlay: $([ $has_overlay -eq 1 ] && echo 'SI' || echo 'NO')"

while true; do
    CATEGORIA=$(obtener_categoria)
    ARCHIVO="$SCRIPT_DIR/$CATEGORIA"

    if [[ ! -f "$ARCHIVO" ]]; then
        echo "Error: no se encuentra ~/$CATEGORIA, esperando 30s..."
        sleep 30
        continue
    fi

    mapfile -t URLS < <(cargar_urls "$ARCHIVO")
    TOTAL=${#URLS[@]}

    if [[ $TOTAL -eq 0 ]]; then
        echo "Error: ~/$CATEGORIA no contiene URLs, esperando 30s..."
        sleep 30
        continue
    fi

    IDX=$(obtener_indice "$CATEGORIA")
    IDX="${IDX:-0}"
    # Ajustar si el archivo se achicó
    if (( IDX >= TOTAL )); then
        IDX=0
    fi

    URL="${URLS[$IDX]}"
    NUEVO_IDX=$(( (IDX + 1) % TOTAL ))
    guardar_indice "$CATEGORIA" "$NUEVO_IDX"

    echo "[$(date +%H:%M)] [$CATEGORIA $((IDX+1))/$TOTAL] Reproduciendo: ${URLS[$IDX]}"

    if [[ $has_overlay -eq 1 ]]; then
        ffmpeg -hide_banner -loglevel error \
               -re -i "$URL" \
               -i "$OVERLAY" \
               -filter_complex "[1]scale='max(min(iw*0.15,200),150)':-1[over];[0][over]overlay=W-w-10:H-h-10" \
               -c:v libx264 -preset ultrafast -b:v "$V_BITRATE" \
               -maxrate "$V_BITRATE" -bufsize 3000k \
               -pix_fmt yuv420p -g 48 \
               -c:a aac -b:a "$A_BITRATE" -ar 44100 \
               -f flv "rtmp://live.twitch.tv/app/$STREAM_KEY" \
               || echo "Error en video, saltando..."
    else
        ffmpeg -hide_banner -loglevel error \
               -re -i "$URL" \
               -c:v libx264 -preset ultrafast -b:v "$V_BITRATE" \
               -maxrate "$V_BITRATE" -bufsize 3000k \
               -pix_fmt yuv420p -g 48 \
               -c:a aac -b:a "$A_BITRATE" -ar 44100 \
               -f flv "rtmp://live.twitch.tv/app/$STREAM_KEY" \
               || echo "Error en video, saltando..."
    fi

    # ---- Animacion separadora ----
    ARCHIVO_ANIM="$SCRIPT_DIR/animaciones"
    if [[ -f "$ARCHIVO_ANIM" ]]; then
        mapfile -t ANIM_URLS < <(cargar_urls "$ARCHIVO_ANIM")
        ANIM_TOTAL=${#ANIM_URLS[@]}

        if [[ $ANIM_TOTAL -gt 0 ]]; then
            ANIM_IDX=$(obtener_indice "animaciones")
            ANIM_IDX="${ANIM_IDX:-0}"
            if (( ANIM_IDX >= ANIM_TOTAL )); then
                ANIM_IDX=0
            fi

            ANIM_URL="${ANIM_URLS[$ANIM_IDX]}"
            ANIM_NUEVO=$(( (ANIM_IDX + 1) % ANIM_TOTAL ))
            guardar_indice "animaciones" "$ANIM_NUEVO"

            echo "[$(date +%H:%M)] [animacion $((ANIM_IDX+1))/$ANIM_TOTAL] Reproduciendo separador"

            if [[ $has_overlay -eq 1 ]]; then
                ffmpeg -hide_banner -loglevel error \
                       -re -i "$ANIM_URL" \
                       -i "$OVERLAY" \
                       -filter_complex "[1]scale='max(min(iw*0.15,200),150)':-1[over];[0][over]overlay=W-w-10:H-h-10" \
                       -c:v libx264 -preset ultrafast -b:v "$V_BITRATE" \
                       -maxrate "$V_BITRATE" -bufsize 3000k \
                       -pix_fmt yuv420p -g 48 \
                       -c:a aac -b:a "$A_BITRATE" -ar 44100 \
                       -f flv "rtmp://live.twitch.tv/app/$STREAM_KEY" \
                       || echo "Error en animacion, saltando..."
            else
                ffmpeg -hide_banner -loglevel error \
                       -re -i "$ANIM_URL" \
                       -c:v libx264 -preset ultrafast -b:v "$V_BITRATE" \
                       -maxrate "$V_BITRATE" -bufsize 3000k \
                       -pix_fmt yuv420p -g 48 \
                       -c:a aac -b:a "$A_BITRATE" -ar 44100 \
                       -f flv "rtmp://live.twitch.tv/app/$STREAM_KEY" \
                       || echo "Error en animacion, saltando..."
            fi
        fi
    fi
done
