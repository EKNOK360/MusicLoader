# MusicLoader

Skill de [Claude Code](https://claude.com/claude-code) para gestionar tu biblioteca de música (**FLAC, MP3 o M4A**) descargada con **SpotiFLAC o con cualquier otro descargador**, y organizar tus playlists de **Spotify**. Le hablas a Claude en lenguaje normal ("revisa mi música", "vigila la descarga", "ponles letra") y la skill sabe qué hacer.

## Qué hace

| Función | Descripción |
|---|---|
| 🔍 **Canciones perdidas** | Encuentra carpetas de álbumes vacías y crea una playlist en Spotify para volver a descargarlas. |
| 📁 **Ordenar** | Pasa cada descarga a `Artista\Álbum\canción`, leyendo los datos del propio archivo (sirve para cualquier descargador), y guarda en respaldo lo que reemplaza. |
| 🧩 **Completar metadatos** | Para FLAC, MP3 y M4A: agrega lo que falte (título, artista, álbum, año, pista, género y **portada en 1200 px**) desde iTunes, y la **letra sincronizada** desde LRCLIB. En MP3 la letra también queda en un `.lrc` al lado. |
| 🔁 **Duplicados** | Detecta canciones repetidas y arma un **cuadro comparativo** (calidad, tamaño, portada, letra, género) marcando la mejor. **No borra nada** hasta que tú lo confirmes. |
| 🏷️ **Géneros** | Busca el género de cada artista en MusicBrainz y lo escribe en el archivo, **solo esa etiqueta**. |
| 🎤 **Letras sincronizadas** | Agrega letras LRC desde LRCLIB y **NetEase Cloud Music**, corrige las desincronizadas y salta las instrumentales. Solo acepta letras cuya duración coincide con la de tu archivo. |
| 🖼️ **Portadas** | Revisa qué canciones no tienen portada o la tienen pequeña (menos de 500 px), agrupadas por álbum. |
| 🩺 **Archivos sanos** | Decodifica todo el audio de cada FLAC para confirmar que ninguno esté dañado. |
| 🛠️ **Mantenimiento completo** | Un solo comando revisa toda la biblioteca: acomoda, pone géneros, letras, metadatos y portadas, y reporta repetidas. |
| 📊 **Vigilante de tareas** | Reporte en el chat **cada 10 minutos** (y al empezar, terminar o si hay un error) con barra, canciones, hora de inicio, fin estimado, canción actual y contadores. Con Remote Control de Claude también llega al **celular**. |
| 👀 **Vigilante de descargas** | Reporte cada ~15 min: avance, canciones saltadas en orden de la lista, internet y espacio en disco. Al terminar acomoda todo. |
| 🎵 **Playlists de Spotify** | Compara playlists y likes con tu disco, crea playlists "para descargar", reparte canciones por estilo (siempre en su playlist + `All`) y hace recomendaciones. |

Antes y después de cada cambio se verifica que **el audio, las letras, la portada y las demás etiquetas** queden idénticos.

## Requisitos

- Windows 10/11 con PowerShell 5.1.
- [Claude Code](https://claude.com/claude-code).
- Tu música en una carpeta, descargada con [SpotiFLAC](https://github.com/afkarxyz/SpotiFLAC) **o con cualquier otro programa** (FLAC, MP3, M4A). Por defecto `D:\SpotiFLAC`; para usar otra, crea `%USERPROFILE%\reportes-musica\config.json` con `{ "raiz": "D:\\Musica" }`.
- Herramientas (con `winget`):
  ```powershell
  winget install Xiph.FLAC      # metaflac: etiquetas FLAC
  winget install Gyan.FFmpeg    # ffprobe: verificación de M4A
  ```
- Para las funciones de Spotify: una app propia en [developer.spotify.com](https://developer.spotify.com/dashboard) con:
  - Redirect URI: `http://127.0.0.1:8888/callback`
  - API: **Web API**
  - No hace falta el *Client Secret* (el login usa PKCE).

## Instalación

1. Copia esta carpeta en `%USERPROFILE%\.claude\skills\music-loader\`:
   ```powershell
   git clone https://github.com/EKNOK360/MusicLoader "$env:USERPROFILE\.claude\skills\music-loader"
   ```
2. Crea la carpeta de datos y guarda el **Client ID** de tu app de Spotify:
   ```powershell
   New-Item -ItemType Directory -Force "$env:USERPROFILE\reportes-musica"
   Set-Content "$env:USERPROFILE\reportes-musica\spotify-client-id.txt" "TU_CLIENT_ID"
   ```
3. Guarda las rutas de las herramientas, si no las detecta solo:
   ```powershell
   (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter metaflac.exe | Select -First 1).FullName | Set-Content "$env:USERPROFILE\reportes-musica\metaflac-path.txt"
   (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ffmpeg.exe   | Select -First 1).FullName | Set-Content "$env:USERPROFILE\reportes-musica\ffmpeg-path.txt"
   ```

## Uso

Abre Claude Code y pídele cosas como:

- *"Revisa qué carpetas de mi música están vacías y hazme una playlist para recuperarlas."*
- *"Ya empezó la descarga, activa el vigilante."*
- *"Revisa todo: acomoda, quita repetidas y ponles género y letra."*
- *"Bajé unos MP3 con otro programa: ponles portada, letra y género, y acomódalos."*
- *"Compara mis likes con lo que tengo descargado."*
- *"Recomiéndame canciones de electro swing y agrégalas a una playlist para descargar."*

Cada vez que un script se conecta a Spotify se abre el navegador: haz clic en **Aceptar**.

## Notas

- Las apps de Spotify en *modo desarrollo* solo pueden leer **tus propias playlists**; para una de otra persona, cópiala a una tuya. Las búsquedas tienen un máximo de 10 resultados, y si se hacen demasiadas Spotify puede bloquear la app por unas horas.
- Los datos (cachés, reglas de géneros, progreso) se guardan en `%USERPROFILE%\reportes-musica\` y **no** se suben al repositorio.
- Las reglas para repartir por estilo (`scripts/repartir-playlists.ps1`) usan los nombres de playlists del autor (Random, Pop & More, Old songs, Rock & Phonk, Reggae & Dancehall, Classical, All); ajústalas a las tuyas.
