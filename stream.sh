#!/usr/bin/env bash
set -euo pipefail
# ============================================================
#  stream.sh — Streamer universal para Twitch
#  Modos:  1) Captura de pantalla
#          2) Parrilla (videos por horario)
# ============================================================

OVERLAY_DEFAULT="$HOME/Descargas/vizcosotransparente.png"
V_BITRATE="1500k"
A_BITRATE="96k"
FPS="24"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
STATE_FILE="$SCRIPT_DIR/.vlive_state"
BW=50
LOG_FILE="/tmp/stream_log_$$.txt"
STREAM_START=0
has_text_overlay=0

MODO="${2:-}"
OVERLAY_CUSTOM="${3:-}"

# ============================================================
#  Interfaz
# ============================================================

top()     { printf '  ┌%s┐\n' "$(printf '─%.0s' $(seq 1 $BW))"; }
bottom()  { printf '  └%s┘\n' "$(printf '─%.0s' $(seq 1 $BW))"; }
divider() { printf '  ├%s┤\n' "$(printf '─%.0s' $(seq 1 $BW))"; }
linea()   { printf '  │ %-*s│\n' "$((BW-1))" "$1"; }

# ============================================================
#  Dashboard (tput ncurses)
# ============================================================

declare -a EVENTS=()
MAX_EVENTS=3

init_ui() {
    tput civis
    tput clear
}

end_ui() {
    tput cnorm
    tput sgr0
}

box_content() {
    local s="${1:0:BW}"
    printf '%-*s' "$BW" "$s"
}

dash_setup() {
    cb=$(tput bold)
    cn=$(tput sgr0)
    cB=$(tput setaf 4)
    cC=$(tput setaf 6)
    cY=$(tput setaf 3)
    cG=$(tput setaf 2)
    cR=$(tput setaf 1)
    cW=$(tput setaf 7)
    sep="$(printf '─%.0s' $(seq 1 $BW))"
}

dash_top()     { printf '%s┌%s┐%s\n'   "$cB" "$sep" "$cn"; }
dash_div()     { printf '%s├%s┤%s\n'   "$cB" "$sep" "$cn"; }
dash_bot()     { printf '%s└%s┘%s\n'   "$cB" "$sep" "$cn"; }
dash_title()   { printf '%s│%s%s%s│%s\n' "$cB" "$cC$cb" "$(box_content '               VIZCOSO STREAMER v2               ')" "$cB" "$cn"; }
dash_sub()     { printf '%s│%s%s%s│%s\n' "$cB" "$cY" "$(box_content "  $1     $2")" "$cB" "$cn"; }
dash_line()    { printf '%s│%s%s%s│%s\n' "$cB" "$cY" "$(box_content "  $1")" "$cB" "$cn"; }
dash_line_raw(){ printf '%s│%s%s%s│%s\n' "$cB" "$1" "$(box_content "$2")" "$cB" "$cn"; }

dash_events() {
    local i ev ce
    for ((i = 0; i < MAX_EVENTS; i++)); do
        if [[ $i -lt ${#EVENTS[@]} ]]; then
            ev="${EVENTS[$i]}"
            if [[ "$ev" == *"OK"* ]]; then ce="$cG"
            elif [[ "$ev" == *"Error"* ]]; then ce="$cR"
            else ce="$cW"; fi
        else ev=""; ce="$cW"; fi
        dash_line_raw "$ce" "$ev"
    done
}

render_dashboard() {
    local modo="$1" tiempo="$2" categoria="$3" vidx="$4"
    local vname="$5" vurl="$6" sig="$7"

    dash_setup
    tput cup 0 0
    dash_top; dash_title; dash_div
    dash_sub "Modo: $modo" "Tiempo: $tiempo"
    dash_line "Categoria: $categoria  [$vidx]"
    dash_div
    dash_line "Video: $vname"
    dash_line_raw "$cW" "  $vurl"
    dash_div
    dash_line "Siguiente: $sig"
    dash_div
    dash_line "Ultimos eventos:"
    dash_events
    dash_div
    dash_line "Ctrl+C para detener"
    dash_bot
}

render_info_dashboard() {
    local mode="$1" tiempo="$2"
    shift 2
    local rows=("$@")

    dash_setup
    tput cup 0 0
    dash_top; dash_title; dash_div
    dash_sub "Modo: $mode" "Tiempo: $tiempo"
    local row
    for row in "${rows[@]}"; do
        dash_line "$row"
    done
    dash_div
    dash_line "Ultimos eventos:"
    dash_events
    dash_div
    dash_line "Ctrl+C para detener"
    dash_bot
}

log_event() {
    local severity="$1" msg="$2"
    local ts icon="●"
    ts=$(date +%H:%M)
    case "$severity" in
        ok)  icon="OK" ;;
        err) icon="Error" ;;
        *)   icon="●" ;;
    esac
    EVENTS+=("$ts $icon $msg")
    if [[ ${#EVENTS[@]} -gt $MAX_EVENTS ]]; then
        EVENTS=("${EVENTS[@]: -$MAX_EVENTS}")
    fi
}

# ============================================================
#  URL helpers
# ============================================================

trunc() {
    local s="$1" max="$2"
    if [[ ${#s} -gt $max ]]; then
        echo "${s:0:$((max-3))}..."
    else
        echo "$s"
    fi
}

url_to_name() {
    local url="$1" name=""
    if [[ "$url" == *youtube.com/watch* ]]; then
        name=$(echo "$url" | sed 's/.*v=//;s/&.*//' | head -1)
        echo "Youtube [${name:-video}]"
    elif [[ "$url" == *youtu.be/* ]]; then
        name=$(echo "$url" | sed 's|.*youtu.be/||;s/?.*//' | head -1)
        echo "Youtube [${name:-video}]"
    else
        name=$(basename "$url" | sed 's/%20/ /g' | sed -E 's/\.(mp4|webm|mkv|avi|flv)$//')
        echo "${name:-unknown}"
    fi
}

url_to_display() {
    local url="$1"
    local display="${url#https://}"
    display="${display#http://}"
    trunc "$display" 46
}

# ============================================================
#  Stream helpers
# ============================================================

OVERLAY_FILTER="[1]scale='max(min(iw*0.15,200),150)':-2[over];[0][over]overlay=W-w-10:H-h-10"

validar_key() {
    local key="$1"

    # No vacia, sin espacios
    if [[ -z "$key" || "$key" != "${key// /}" ]]; then
        return 1
    fi

    # Conexion TCP a Twitch ingest (puerto RTMP 1935)
    if ! timeout 3 bash -c "echo '' > /dev/tcp/live.twitch.tv/1935" 2>/dev/null; then
        return 1
    fi

    return 0
}

transmitir() {
    local url="$1"
    local etiqueta="$2"
    shift 2
    local extra_inputs=("$@")
    [[ -z "$url" ]] && { echo "  [!] URL vacia, saltando..."; return 1; }
    local cmd=(ffmpeg -hide_banner -loglevel error)
    local filter_string=""

    cmd+=("${extra_inputs[@]}" -i "$url")

    if [[ $has_overlay -eq 1 ]]; then
        cmd+=(-i "$OVERLAY")
        filter_string="[1]scale='max(min(iw*0.15,200),150)':-2[over];[0][over]overlay=W-w-10:H-h-10"
    fi

    if [[ $has_text_overlay -eq 1 ]]; then
        local text_filter="drawtext=textfile='$LOG_FILE':reload=1:fontsize=13:fontcolor=#ff00ff:fontfile=/usr/share/fonts/xscreensaver/clacon.ttf:x=10:y=H-th-30:shadowcolor=black:shadowx=2:shadowy=2"
        if [[ -n "$filter_string" ]]; then
            filter_string+=",$text_filter"
        else
            filter_string="$text_filter"
        fi
    fi

    if [[ -n "$filter_string" ]]; then
        cmd+=(-filter_complex "$filter_string")
    fi

    cmd+=(
        -c:v libx264 -preset ultrafast -b:v "$V_BITRATE"
        -maxrate "$V_BITRATE" -bufsize 3000k
        -pix_fmt yuv420p -g 48
        -c:a aac -b:a "$A_BITRATE" -ar 44100
        -f flv "rtmp://live.twitch.tv/app/$STREAM_KEY"
    )

    echo "  [$etiqueta] Transmitiendo..."
    "${cmd[@]}" || echo "  [!] Error, saltando..."
}

resolver_url() {
    local url="$1"
    case "$url" in
        *youtube.com*|*youtu.be*)
            yt-dlp -g -f "best[height<=720]" "$url" 2>/dev/null | head -1 || true ;;
        *) echo "$url" ;;
    esac
}

t_re() {
    local url
    url=$(resolver_url "$1")
    transmitir "$url" "$2" -re
}

# ============================================================
#  Deteccion de sistema (fallbacks + env vars)
# ============================================================

detectar_resolucion() {
    local res="${RES:-}"
    [[ -n "$res" ]] && echo "$res" && return 0
    if command -v xrandr &>/dev/null; then
        res=$(xrandr --current 2>/dev/null | grep '\*' | awk '{print $1}' | head -1)
        [[ -n "$res" ]] && echo "$res" && return 0
    fi
    if [[ -f /sys/class/graphics/fb0/virtual_size ]]; then
        res=$(tr ',' 'x' < /sys/class/graphics/fb0/virtual_size 2>/dev/null)
        [[ -n "$res" ]] && echo "$res" && return 0
    fi
    echo "  [!] No se pudo detectar resolucion, usando 1280x720" >&2
    echo "1280x720"
}

detectar_camara_res() {
    local res="${CAM_RES:-}"
    local dev="${CAM_DEVICE:-/dev/video0}"
    [[ -n "$res" ]] && echo "$res" && return 0
    if command -v v4l2-ctl &>/dev/null && [[ -c "$dev" ]]; then
        res=$(v4l2-ctl --device="$dev" --get-fmt-video 2>/dev/null \
            | grep -oP 'Width/Height\s+:\s+\K\d+x\d+')
        [[ -n "$res" ]] && echo "$res" && return 0
    fi
    echo "  [!] v4l2-ctl o camara no disponible, usando 640x480" >&2
    echo "640x480"
}

obtener_audio_sink() {
    local s="${AUDIO_SINK:-}"
    [[ -n "$s" ]] && echo "$s" && return 0
    if command -v pactl &>/dev/null; then
        s=$(pactl get-default-sink 2>/dev/null)
        [[ -n "$s" ]] && echo "${s}.monitor" && return 0
    fi
    echo "  [!] pactl no disponible, sin audio de sistema" >&2
    echo ""
}

obtener_audio_source() {
    local s="${AUDIO_SOURCE:-}"
    [[ -n "$s" ]] && echo "$s" && return 0
    if command -v pactl &>/dev/null; then
        s=$(pactl get-default-source 2>/dev/null)
        [[ -n "$s" ]] && echo "$s" && return 0
    fi
    echo "  [!] pactl no disponible, sin microfono" >&2
    echo ""
}

calcular_tiempo() {
    local elapsed=$(( $(date +%s) - STREAM_START ))
    local min=$(( elapsed / 60 ))
    local sec=$(( elapsed % 60 ))
    echo "${min}m ${sec}s"
}

# ============================================================
#  Parrilla helpers
# ============================================================

obtener_categoria() {
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

        if (( fin_total <= inicio_total )); then
            if (( hora_actual_minutos >= inicio_total || hora_actual_minutos < fin_total )); then
                echo "$categoria"; return 0
            fi
        else
            if (( hora_actual_minutos >= inicio_total && hora_actual_minutos < fin_total )); then
                echo "$categoria"; return 0
            fi
        fi
    done < "$PARRILLA"
    head -n1 "$PARRILLA" | grep -oP '\|\s*\K\w+' || true
}

obtener_indice() {
    local categoria="$1"
    [[ -f "$STATE_FILE" ]] && grep "^$categoria " "$STATE_FILE" | head -1 | awk '{print $2}' || true
}

guardar_indice() {
    local categoria="$1" indice="$2"
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

# ============================================================
#  Pantalla 1 — Modo
# ============================================================

if [[ -z "$MODO" ]]; then
    clear
    top
    linea "         Streamer Universal"
    divider
    linea "  1) Pantalla (captura de escritorio)"
    linea "  2) Parrilla (videos por horario)"
    linea "  3) Camara (webcam + microfono)"
    divider
    read -p "  │  Selecciona [1/2/3]: " -r MODO
    bottom
fi

case "$MODO" in
    1|2|3) ;;
    *) echo "  Modo invalido. Usa 1, 2 o 3."; exit 1 ;;
esac

# ============================================================
#  Pantalla 2 — Stream key (loop)
# ============================================================

STREAM_KEY="${1:-}"
REINTENTO=0

while true; do
    if [[ -n "$STREAM_KEY" ]]; then
        echo -n "  Validando key..."
        if validar_key "$STREAM_KEY"; then
            echo " OK"
            break
        fi
        echo " invalida"
        STREAM_KEY=""
        REINTENTO=1
    fi

    clear
    top
    linea "         Streamer Universal"
    divider
    if [[ $REINTENTO -eq 1 ]]; then
        linea "  [!] Stream key invalida"
    fi
    linea "  Stream key de Twitch:"
    linea "  (Ctrl+C para salir)"
    divider
    read -s -p "  │  Key: " -r STREAM_KEY
    echo ""
    bottom
done

# ============================================================
#  Pantalla 3 — Overlay
# ============================================================

has_overlay=0
OVERLAY=""

if [[ -n "$OVERLAY_CUSTOM" ]]; then
    if [[ "$OVERLAY_CUSTOM" == "0" ]]; then
        has_overlay=0; OVERLAY=""
    elif [[ -f "$OVERLAY_CUSTOM" ]]; then
        has_overlay=1; OVERLAY="$OVERLAY_CUSTOM"
    else
        echo "  [!] Overlay no encontrado: $OVERLAY_CUSTOM, sin overlay"
        has_overlay=0; OVERLAY=""
    fi
else
    clear
    top
    linea "         Streamer Universal"
    divider
    linea "  Overlay (Enter = default)"
    linea "  0 = Ninguno"
    linea "  ruta = Custom"
    divider
    read -p "  │  > " -r OVERLAY_INPUT
    bottom

    if [[ "$OVERLAY_INPUT" == "0" ]]; then
        has_overlay=0; OVERLAY=""
    elif [[ -n "$OVERLAY_INPUT" ]]; then
        if [[ -f "$OVERLAY_INPUT" ]]; then
            has_overlay=1; OVERLAY="$OVERLAY_INPUT"
        else
            echo "  [!] Archivo no encontrado: $OVERLAY_INPUT, sin overlay"
            has_overlay=0; OVERLAY=""
        fi
    elif [[ -f "$OVERLAY_DEFAULT" ]]; then
        has_overlay=1; OVERLAY="$OVERLAY_DEFAULT"
    else
        has_overlay=0; OVERLAY=""
    fi
fi

# ============================================================
#  Pantalla 4 — Resumen
# ============================================================

NOMBRE_MODO="Pantalla"; [[ "$MODO" == "2" ]] && NOMBRE_MODO="Parrilla"; [[ "$MODO" == "3" ]] && NOMBRE_MODO="Camara"
TEXTO_OVERLAY="No"; [[ $has_overlay -eq 1 ]] && TEXTO_OVERLAY="SI"

clear
top
linea "         Streamer Universal"
divider
linea "  Modo    : $NOMBRE_MODO"
linea "  Overlay : $TEXTO_OVERLAY"
linea "  Bitrate : $V_BITRATE / $A_BITRATE"
linea "  Ctrl+C para detener"
bottom
echo ""

# ============================================================
#  MODO 1 — Captura de pantalla
# ============================================================

if [[ "$MODO" == 1 ]]; then
    RES=$(detectar_resolucion)
    AUDIO=$(obtener_audio_sink)

    init_ui
    STREAM_START=$(date +%s)
    trap 'end_ui; rm -f "$LOG_FILE"; exit 0' INT TERM

    log_event ok "Stream iniciado"
    log_event info "Resolucion: $RES"
    if [[ -n "$AUDIO" ]]; then
        log_event ok "Audio: $AUDIO"
    else
        log_event err "Audio NO disponible"
    fi

    render_info_dashboard "Pantalla" "$(calcular_tiempo)" \
        "Resolucion: $RES" \
        "Audio: ${AUDIO:-NO}" \
        "Bitrate: $V_BITRATE / $A_BITRATE" \
        "Overlay: $TEXTO_OVERLAY"

    : > "$LOG_FILE"
    echo "[$(date +%H:%M)] [Pantalla - $RES]" > "$LOG_FILE"

    cmd=(ffmpeg -hide_banner -loglevel error)
    cmd+=(-video_size "$RES" -framerate "$FPS" -f x11grab -i ":0.0+0,0")

    if [[ $has_overlay -eq 1 ]]; then
        cmd+=(-i "$OVERLAY")
        cmd+=(-filter_complex "$OVERLAY_FILTER")
    fi

    if [[ -n "$AUDIO" ]]; then
        cmd+=(-f pulse -i "$AUDIO")
    fi

    cmd+=(
        -c:v libx264 -preset ultrafast -b:v "$V_BITRATE"
        -maxrate "$V_BITRATE" -bufsize 3000k
        -pix_fmt yuv420p -g 48
        -c:a aac -b:a "$A_BITRATE" -ar 44100
        -f flv "rtmp://live.twitch.tv/app/$STREAM_KEY"
    )

    "${cmd[@]}"
    end_ui
    exit 0
fi

# ============================================================
#  MODO 3 — Cámara
# ============================================================

if [[ "$MODO" == 3 ]]; then
    CAMPATH="${CAM_DEVICE:-/dev/video0}"
    CAM_RES=$(detectar_camara_res)
    AUDIO=$(obtener_audio_source)

    init_ui
    STREAM_START=$(date +%s)
    trap 'end_ui; rm -f "$LOG_FILE"; exit 0' INT TERM

    log_event ok "Stream iniciado"
    log_event info "Resolucion: $CAM_RES"
    log_event info "Dispositivo: $CAMPATH"
    if [[ -n "$AUDIO" ]]; then
        log_event ok "Audio: $AUDIO"
    else
        log_event err "Audio NO disponible"
    fi

    render_info_dashboard "Camara" "$(calcular_tiempo)" \
        "Resolucion: $CAM_RES" \
        "Dispositivo: $CAMPATH" \
        "Audio: ${AUDIO:-NO}" \
        "Overlay: $TEXTO_OVERLAY"

    : > "$LOG_FILE"
    echo "[$(date +%H:%M)] [Camara - $CAM_RES]" > "$LOG_FILE"

    cmd=(ffmpeg -hide_banner -loglevel error)
    cmd+=(-f v4l2 -framerate 30 -video_size "$CAM_RES" -i "$CAMPATH")

    if [[ $has_overlay -eq 1 ]]; then
        cmd+=(-i "$OVERLAY")
        cmd+=(-filter_complex "$OVERLAY_FILTER")
    fi

    if [[ -n "$AUDIO" ]]; then
        cmd+=(-f pulse -i "$AUDIO")
    fi

    cmd+=(
        -c:v libx264 -preset ultrafast -b:v "$V_BITRATE"
        -maxrate "$V_BITRATE" -bufsize 3000k
        -pix_fmt yuv420p -g 48
        -c:a aac -b:a "$A_BITRATE" -ar 44100
        -f flv "rtmp://live.twitch.tv/app/$STREAM_KEY"
    )

    "${cmd[@]}"
    end_ui
    exit 0
fi

# ============================================================
#  MODO 2 — Parrilla
# ============================================================

PARRILLA="$SCRIPT_DIR/parrilla"
[[ -f "$PARRILLA" ]] || { echo "  Error: no se encuentra $PARRILLA"; exit 1; }
[[ -f "$STATE_FILE" ]] || > "$STATE_FILE"
has_text_overlay=1
STREAM_START=$(date +%s)
: > "$LOG_FILE"

init_ui
trap 'end_ui; rm -f "$LOG_FILE"; exit 0' INT TERM

while true; do
    CATEGORIA=$(obtener_categoria)
    ARCHIVO="$SCRIPT_DIR/$CATEGORIA"
    VIZ_ARCHIVO="$SCRIPT_DIR/vizcoso-$CATEGORIA"

    URLS=()
    if [[ -f "$VIZ_ARCHIVO" ]]; then
        mapfile -t VIZ_URLS < <(cargar_urls "$VIZ_ARCHIVO")
        URLS+=("${VIZ_URLS[@]}")
    fi

    if [[ ! -f "$ARCHIVO" ]]; then
        log_event err "No se encuentra $CATEGORIA"
        render_dashboard "Parrilla" "$(calcular_tiempo)" "$CATEGORIA" "-" "-" "-" "-"
        sleep 30; continue
    fi

    mapfile -t ARCHIVE_URLS < <(cargar_urls "$ARCHIVO")
    URLS+=("${ARCHIVE_URLS[@]}")
    TOTAL=${#URLS[@]}
    if [[ $TOTAL -eq 0 ]]; then
        log_event err "$CATEGORIA vacio"
        render_dashboard "Parrilla" "$(calcular_tiempo)" "$CATEGORIA" "-" "-" "-" "-"
        sleep 30; continue
    fi

    IDX=$(obtener_indice "$CATEGORIA"); IDX="${IDX:-0}"
    (( IDX >= TOTAL )) && IDX=0
    NUEVO_IDX=$(( (IDX + 1) % TOTAL ))
    guardar_indice "$CATEGORIA" "$NUEVO_IDX"

    ARCHIVO_ANIM="$SCRIPT_DIR/animaciones"
    VIZ_ANIM="$SCRIPT_DIR/vizcoso-animaciones"
    ANIM_URLS=()
    if [[ -f "$VIZ_ANIM" ]]; then
        mapfile -t VIZ_A < <(cargar_urls "$VIZ_ANIM")
        ANIM_URLS+=("${VIZ_A[@]}")
    fi
    if [[ -f "$ARCHIVO_ANIM" ]]; then
        mapfile -t ARC_A < <(cargar_urls "$ARCHIVO_ANIM")
        ANIM_URLS+=("${ARC_A[@]}")
    fi
    ANIM_TOTAL=${#ANIM_URLS[@]}
    if [[ $ANIM_TOTAL -gt 0 ]]; then
        ANIM_IDX=$(obtener_indice "animaciones"); ANIM_IDX="${ANIM_IDX:-0}"
        (( ANIM_IDX >= ANIM_TOTAL )) && ANIM_IDX=0
        ANIM_SIG="separador $((ANIM_IDX+1))/$ANIM_TOTAL"
    else
        ANIM_SIG="-"
    fi

    VNAME=$(url_to_name "${URLS[$IDX]}")
    VURL=$(url_to_display "${URLS[$IDX]}")
    VIDX="$((IDX+1))/$TOTAL"
    TIEMPO=$(calcular_tiempo)

    log_event ok "$CATEGORIA $VIDX"
    render_dashboard "Parrilla" "$TIEMPO" "$CATEGORIA" "$VIDX" "$VNAME" "$VURL" "$ANIM_SIG"
    echo "[$(date +%H:%M)] [$CATEGORIA $VIDX] - $TIEMPO" > "$LOG_FILE"
    t_re "${URLS[$IDX]}" "$CATEGORIA $VIDX"

    if [[ $ANIM_TOTAL -gt 0 ]]; then
        ANIM_NUEVO=$(( (ANIM_IDX + 1) % ANIM_TOTAL ))
        guardar_indice "animaciones" "$ANIM_NUEVO"
        TIEMPO=$(calcular_tiempo)
        SNAME=$(url_to_name "${ANIM_URLS[$ANIM_IDX]}")
        SURL=$(url_to_display "${ANIM_URLS[$ANIM_IDX]}")
        SIDX="$((ANIM_IDX+1))/$ANIM_TOTAL"

        log_event ok "separador $SIDX"
        render_dashboard "Parrilla" "$TIEMPO" "$CATEGORIA" "$VIDX" "$SNAME" "$SURL" "-"
        echo "[$(date +%H:%M)] [separador $SIDX] - $TIEMPO" > "$LOG_FILE"
        t_re "${ANIM_URLS[$ANIM_IDX]}" "separador $SIDX"
    fi
done
