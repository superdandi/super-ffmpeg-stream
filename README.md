# super-ffmpeg-stream

Streamer universal para Twitch basado en FFmpeg. Permite transmitir en 3 modos: captura de pantalla, parrilla de videos por horario, o cámara web.

> Este stream está actualmente en vivo en **[twitch.tv/vizcoso](https://twitch.tv/vizcoso)** — 24/7 reproduciendo videos de dominio público.

Todos los videos son tomados de **[archive.org](https://archive.org)**, seleccionados por su antigüedad (años 70 o anteriores).

## Requisitos

- **FFmpeg** compilado con libx264, aac, pulse, v4l2, x11grab
- **PulseAudio** (para audio de sistema/micrófono)
- **Bash 4+**
- **xrandr** (detección de resolución opcional)
- **v4l2-ctl** (cámara, opcional)
- **yt-dlp** (para reproducción de videos de YouTube)

## Instalación

```bash
git clone https://github.com/superdandi/super-ffmpeg-stream.git
cd super-ffmpeg-stream
chmod +x stream.sh
```

## Uso

```bash
./stream.sh [stream_key] [modo] [overlay]
```

### Argumentos

| Argumento | Descripción | Default |
|---|---|---|
| `stream_key` | Clave de stream de Twitch | solicitada interactivamente |
| `modo` | 1=Pantalla, 2=Parrilla, 3=Cámara | solicitado interactivamente |
| `overlay` | Ruta a imagen de overlay, "0" para ninguno | default o solicitado |

### Variables de entorno

| Variable | Descripción | Default |
|---|---|---|
| `RES` | Resolución de captura (ej: `1920x1080`) | auto-detectada |
| `CAM_RES` | Resolución de cámara (ej: `1280x720`) | auto-detectada |
| `CAM_DEVICE` | Dispositivo de cámara | `/dev/video0` |
| `V_BITRATE` | Bitrate de video | `1500k` |
| `A_BITRATE` | Bitrate de audio | `96k` |
| `AUDIO_SINK` | Fuente de audio de sistema (sink PulseAudio) | auto-detectada |
| `AUDIO_SOURCE` | Fuente de micrófono (source PulseAudio) | auto-detectada |
| `FPS` | Frames por segundo (modo pantalla) | `24` |

## Modos

### 1 — Captura de pantalla

Transmite el escritorio completo con audio de sistema. Usa `x11grab` para captura.

```bash
./stream.sh live_key_123 1
```

### 2 — Parrilla (reproducción por horario)

Lee el archivo `parrilla` para determinar qué categoría de video reproducir según la hora actual. Cada categoría es un archivo en el mismo directorio con una lista de URLs de videos. Al terminar un video, pasa al siguiente de la misma categoría y opcionalmente reproduce un video separador de `animaciones`. El índice de reproducción se persiste en `.vlive_state`.

```bash
./stream.sh live_key_123 2
```

### 3 — Cámara web

Transmite desde cámara web con micrófono.

```bash
./stream.sh live_key_123 3 /ruta/overlay.png
```

## Archivo `parrilla`

Define la programación diaria. Formato por línea:

```
HH:MM-HH:MM | categoria
```

Ejemplo:

```
06:00-07:00 | noticias
07:00-09:00 | musicales
19:00-22:00 | animados
23:00-03:00 | pelis
```

El bloque `03:00-06:00` cruza la medianoche y se maneja automáticamente. La categoría debe coincidir con un archivo en el mismo directorio.

## Archivos de categoría

Cada categoría es un archivo de texto con una URL por línea:

```
# Comentarios
Nombre del video | https://archive.org/.../video.mp4
```

El formato es `título | URL`. Solo se requiere la URL después del pipe.

### Categorías incluidas

| Archivo | Contenido |
|---|---|
| `musicales` | Videos musicales retro (Shindig, American Bandstand, Soul Train) |
| `noticias` | Noticieros y reportajes de dominio público |
| `animados` | Dibujos animados clásicos |
| `animales` | Documentales y videos de animales |
| `documentales` | Documentales de dominio público |
| `pelis` | Películas completas de dominio público (años 70 o anteriores) |
| `comidas` | Videos de cocina y comidas |
| `deportes` | Eventos deportivos clásicos |
| `comerciales` | Comerciales vintage |
| `animaciones` | Separadores entre bloques (Electric Sheep, etc.) |

### Contenido original de Vizcoso

Además del contenido de archive.org, el script puede reproducir videos desde YouTube. Los archivos con prefijo `vizcoso-` contienen URLs de YouTube (canal de [Vizcoso Entertainment](https://www.youtube.com/channel/UCGYhMw5VupEQEnNrQlbT1iA)) y se reproducen **antes** que el contenido de archive.org en cada categoría.

| Archivo | Fuente |
|---|---|
| `vizcoso-pelis` | Playlist [Super Producciones](https://www.youtube.com/playlist?list=PL58F985571B763484) |
| `vizcoso-musicales` | Playlist [music](https://www.youtube.com/playlist?list=PLKCoMIUhCOzWJcczu8WvxxF7XntBbCLSU) + videos del canal |
| `vizcoso-animaciones` | Videos VIZCOSO SESSION y Vizcoso Entertainment |

#### Script de actualización

```bash
./actualizar_vizcoso.sh
```

Actualiza las listas `vizcoso-*` desde YouTube. Ejecutar periódicamente para mantener el contenido sincronizado.

## Overlay

El script soporta una imagen PNG como overlay (watermark). Por defecto busca en `~/Descargas/vizcosotransparente.png`. Se puede:

- Pasar como tercer argumento
- Pasar la ruta en el prompt interactivo
- Usar `"0"` para deshabilitar

## Funcionamiento interno (modo parrilla)

1. Lee `parrilla` y determina la categoría según la hora actual
2. Carga primero la lista de URLs de `vizcoso-$CATEGORIA` (YouTube, si existe), luego del archivo de categoría (archive.org)
3. Si la URL es de YouTube, la resuelve a una URL directa vía `yt-dlp -g`
4. Reproduce el video actual vía FFmpeg con `-re` (velocidad real)
5. Guarda el índice del siguiente video en `.vlive_state`
6. Si existen `vizcoso-animaciones` o `animaciones`, reproduce un video separador
7. Repite el ciclo

El estado se persiste entre reinicios del script para no repetir el mismo video.

## Notas

- Todos los videos son de **dominio público** tomados de **[archive.org](https://archive.org)**
- Seleccionados por antigüedad: **años 70 o anteriores**
- El stream corre **24/7** en **[twitch.tv/vizcoso](https://twitch.tv/vizcoso)**
- Todos los videos deben ser URLs directas accesibles por FFmpeg (idealmente MP4)
- La conexión a Twitch se valida con TCP al puerto RTMP 1935
- Los logs de transmisión se escriben a `/tmp/stream_log_*.txt`
