---
name: music-loader
description: Gestión completa de una biblioteca de música (FLAC, MP3 o M4A) descargada con SpotiFLAC o con cualquier otro descargador, y de las playlists de Spotify del usuario. Usar cuando el usuario hable de su reproductor de música, SpotiFLAC u otro descargador de música, MP3, descargar canciones, carpetas vacías o canciones perdidas, acomodar/organizar la música por artista y álbum, canciones repetidas/duplicadas, géneros, portadas, letras sincronizadas o metadatos, vigilar una descarga, playlists de Spotify (crear, repartir, comparar, likes, recomendaciones) o diga "music loader".
---

# Music Loader

Objetivo: que la biblioteca de música esté completa y en orden para disfrutarla al máximo en el reproductor: canciones sin perder, bien acomodadas, sin repetidas, con portada, género y letra sincronizada.

Biblioteca: la carpeta de `reportes-musica\config.json` (`{ "raiz": "D:\\Musica" }`; por defecto `D:\SpotiFLAC`), o el parámetro `-Raiz`. Formato final: `Artista\Álbum\Artista - Título.ext`. Sirve para descargas de **SpotiFLAC o de cualquier otro programa** (FLAC, MP3, M4A).
Scripts: `~/.claude/skills/music-loader/scripts/` (PowerShell 5.1, guardados con UTF-8 BOM).
Datos/estado: `%USERPROFILE%\reportes-musica\` (Client ID de Spotify, json de playlists, cachés, reglas de géneros, progreso del vigilante). Nada de eso va al repositorio.
Ejecutar siempre: `powershell -ExecutionPolicy Bypass -File "<script>" <args>`.

## Reglas
- Hablar en el idioma del usuario, simple; resultados en **tablas/listas en el chat**. No crear archivos en el Escritorio.
- **Regla de playlists:** toda canción va en su playlist de estilo **y** en una playlist general ("All"). Las playlists de estilo y qué artistas van en cada una se definen en `repartir-playlists.ps1` (`$reglas`); adaptarlas a las playlists del usuario la primera vez y preguntar si hay alguna que no se debe tocar (por ejemplo, una bandeja de canciones nuevas). Revisar la memoria del usuario por reglas propias.
- Versiones: preferir **estudio/álbum**; evitar en vivo, remix, sped up, AI y soundscapes, salvo que el usuario las pida.
- Antes de borrar archivos o playlists: mirar el objetivo y borrar solo lo que el usuario pidió. Mover a respaldo cuando se pueda. **Repetidas: nunca borrar sin que el usuario lo ordene después de ver el cuadro comparativo.**
- Editar metadatos **solo** la etiqueta pedida (género o letra); verificar que audio, letras, portada y demás etiquetas queden idénticos. Probar primero en una copia.
## Spotify (app propia del usuario en modo desarrollo; login PKCE en `spotify-auth.ps1`, Client ID en `reportes-musica\spotify-client-id.txt`)
- Cada script con Spotify abre el navegador: **avisar al usuario que haga clic en Aceptar**. Correr en segundo plano.
- Límites: búsqueda `limit` máx. **10**; solo se pueden leer playlists **propias** (las de otros dan 403: pedir al usuario que la copie a una suya con ⋯ → Agregar a otra playlist → Nueva playlist); si hay error 429 con espera larga (>15 min) el script se detiene: esperar, no crear otra app.
- Endpoints nuevos: `/me/playlists`, `/playlists/{id}/items` (campo `item` o `track`).

## Funciones
| Tarea | Script |
|---|---|
| Carpetas vacías (canciones perdidas) | `revisar-carpetas-vacias.ps1` |
| Leer todas mis playlists → playlists.json | `exportar-playlists.ps1` |
| Leer playlists + likes + buscar canciones del disco sin playlist → likes.json, locales.json | `analizar-locales.ps1 [-SinExportar]` |
| Comparar una playlist (por `-Id` o `-Nombre "patrón*"`) con el disco → externa.json / externa-faltan.json | `revisar-playlist-externa.ps1` |
| Repartir canciones en playlists de estilo + All (reglas por artista dentro del script; artistas nuevos: agregarlos a las reglas) | `repartir-playlists.ps1 -FuenteJson x.json` (simulación) / `-Aplicar` / `-CrearDesde faltan.json -NuevaPlaylist "Descargar X"` |
| Faltantes de un artista vs su discografía (sin versiones/repetidas) | `buscar-faltantes-artista.ps1 -Artista "X"` |
| Recomendaciones (lista `Genero\|Artista\|Titulo`; `?busqueda` libre, `*N` = N más populares, `+Titulo` = forzar) | `recomendar-y-limpiar.ps1 -Nombre <playlist> -Lista x.txt [-TambienEn All]` |
| Playlist para descargar (copia lo no descargado de otra + lista `Destinos\|Artista\|?busqueda`) | `playlist-descarga.ps1 -Nombre "Descargar X" [-CopiarDe P] [-Lista x.txt]` |
| **Completar metadatos** de cualquier descargador (FLAC/MP3/M4A): título, artista, álbum, artista del álbum, año, pista, género y portada 1200 px desde iTunes; letra sincronizada desde LRCLIB. Solo agrega lo que falta. MP3: copia con ffmpeg + comparación del contenido de cada cuadro y del sonido decodificado; letra también en `.lrc` al lado | `completar-metadatos.ps1` (plan) / `-Aplicar` / `-Archivo x` / `-Raiz carpeta` |
| **Ordenar por etiquetas** (cualquier descargador): mueve a `Raiz\Artista\Álbum\Artista - Título.ext` según las etiquetas (o el nombre "Artista - Título"), con su `.lrc` | `ordenar-por-etiquetas.ps1 -Origen "carpeta de descargas"` (plan) / `-Aplicar` |
| Acomodar una descarga **de SpotiFLAC** (ya viene en `Artista\Álbum`) (viejos con mismo nombre → `_reemplazados`) | `acomodar-descargas.ps1 -Origen "<carpeta>"` |
| Repetidas: **cuadro comparativo** por grupo (calidad: FLAC/ALAC bits+kHz o kbps, tamaño, duración, portada, letra sincronizada, género) con la mejor marcada ⭐; guarda `reportes-musica\repetidas.md`. **No borra nada**: mostrar el cuadro al usuario y esperar su orden. Antes, completar metadatos de todas las copias | `duplicados.ps1` (solo reporte) / `-Aplicar` **solo** si el usuario dice que borre las de menor calidad |
| Géneros: buscar en MusicBrainz (1 consulta/s, caché) | `buscar-generos.ps1` |
| Géneros FLAC (metaflac; mapa de etiquetas + `generos-manual.txt` `Artista\|G1;G2`; no reescribe si ya está igual) | `asignar-generos.ps1` (simulación) / `-Aplicar` |
| Géneros M4A/MP3 (propiedades de Windows + verificación cuadro a cuadro con ffprobe) | `generos-m4a.ps1 -Generos @{ 'Artista' = 'G1;G2' }` |

| Letras **sincronizadas** (LRCLIB y, si no está, **NetEase Cloud Music**; módulo `lrc-fuentes.ps1`): agrega a las que no tienen, corrige las desincronizadas (desfase mediano > 0.75 s o tiempos después del final), salta instrumentales; solo acepta letras con duración ±2 s de la del archivo | `letras-sincronizadas.ps1` (análisis, guarda `letras-plan.xml`) / `-Aplicar` / `-Archivo copia.flac` (prueba) |
| Portadas: canciones sin portada o con portada pequeña (< 500 px), por álbum | `revisar-portadas.ps1` |
| Revisar que ningún archivo esté dañado (FLAC: `flac -t`; MP3/M4A: ffmpeg decodifica todo) | `revisar-danos.ps1` |
| **Mantenimiento completo** en un solo proceso: acomodar descargas pendientes → géneros → letras → metadatos → portadas → repetidas | `mantenimiento.ps1 [-EsperarArchivo salida.txt]` (en segundo plano; detalle en `reportes-musica\mantenimiento.log`) |

**Letras:** solo sincronizadas (formato LRC `[mm:ss.xx]`). **Regla: toda canción que tenga letra debe tenerla sincronizada**; si la tiene sin tiempos o desincronizada, buscar en todas las fuentes (`BuscarLetra`). Solo quedan sin letra las instrumentales o las que ninguna fuente tenga (reportarlas). Antes de aplicar a todas, probar en una **copia** y pedir al usuario que la escuche en **MusicBee** (instalado; Ver → Letras) para confirmar la sincronización. Leer etiquetas con `metaflac --no-utf8-convert` y `[Console]::OutputEncoding = UTF8` (si no, las tildes salen mal y las búsquedas fallan). Las respuestas de LRCLIB se descargan con WebClient en UTF-8. Comprobar el audio con la huella SHA256 de los bytes después de los metadatos (muchos FLAC de SpotiFLAC no traen MD5).

**Si el disco D se desconecta o la PC se apaga durante una escritura:** parar, y al volver revisar TODOS los FLAC con `flac -t` antes de seguir (metaflac conserva la fecha, así que no se puede filtrar por fecha).

Herramientas instaladas (winget): metaflac (`reportes-musica\metaflac-path.txt`), ffmpeg/ffprobe (`ffmpeg-path.txt`). Nunca usar ffmpeg para reescribir M4A (pierde portada y cuadros).

## Vigilante de descargas
1. La descarga de SpotiFLAC crea `D:\SpotiFLAC\<nombre de la playlist>` (sin ":").
2. Escribir `reportes-musica\vigilar.txt`: línea 1 = nombre de la playlist en Spotify, línea 2 = carpeta, línea 3 (opcional) = json con la lista en orden. Exportar playlists antes si la playlist es nueva. Mover el `progreso.txt` anterior.
3. `vigilante.ps1` en segundo plano (avisa TERMINADO) + Monitor con `reporte15.ps1` (una línea `AVANCE` cada ~14.5 min; re-armar al expirar).
4. Reportar en el chat con este formato: barra `█░` de 20, avance N de total, fin estimado, velocidad (🟢 ≥1.5/min, 🟡 1–1.5, 🔴 <1), canción por la que va, saltadas en orden de la lista (`saltadas.ps1`; verificar carpetas vacías antes de dar una saltada por real; repetidas en la lista no son saltadas), internet prom/pico (🟢 >20, 🟡 5–20, 🔴 <5 Mbps), disco D libre y libre al terminar.
5. Al terminar: confirmar 0 temporales (`.spotiflac-*`, `.tmp`), `acomodar-descargas.ps1`, borrar carpetas vacías de la descarga, revisar repetidas, poner géneros, dar resumen. Si se reinició la PC: revisar duplicados `_01` y re-armar todo.

## Descargas de otros programas (MP3, etc.)
1. `completar-metadatos.ps1 -Raiz "<carpeta de descargas>"` → revisar plan → `-Aplicar` (así cada archivo tiene artista/álbum/título correctos). 2. `ordenar-por-etiquetas.ps1 -Origen "<carpeta de descargas>"` → `-Aplicar`. 3. Seguir con el mantenimiento completo.

## Vigilante de tareas (revisiones largas)
- Cada script de revisión llama a `progreso.ps1` y escribe `reportes-musica\tarea-<nombre>.json`.
- `reporte-tarea.ps1` (correr con Monitor, re-armar al expirar) emite una línea `TAREA` **cada 15 min** si la tarea tiene ≥1000 archivos, o **cada 100 archivos** si tiene menos, y `TERMINADA` al final.
- **Formato del reporte en el chat** (bonito y fácil de leer): título con emoji y hora (`## 🔍 Vigilante de tareas · 11:35 a.m.`), una tabla con una fila por tarea: emoji + nombre en negrita, barra de 20 bloques en código (`██████░░░░`) con el % en negrita, "N de total", fin estimado y contadores con ✅/⚠️; al final una nota corta 📝 con lo importante (problemas, qué sigue).
- **Notificaciones al celular:** si el usuario no está frente a la PC, enviar `PushNotification` con cada reporte (una línea: tarea, %, problemas, fin estimado). Para que lleguen, Claude Code debe tener Remote Control activo (`/remote-control`, o `"remoteControlAtStartup": true` en `~/.claude/settings.json` para todas las sesiones) y la app Claude en el celular con notificaciones permitidas. Bloquear la PC (Win+L) no detiene nada; suspenderla sí.

## Mantenimiento completo ("revisa todo")
Lo más simple: `mantenimiento.ps1` en segundo plano + Monitor con `reporte-tarea.ps1`. Pasos manuales equivalentes:
1. Acomodar cualquier carpeta de descarga pendiente. 2. Verificar que todo esté en `Artista\Álbum\canción` (nivel 3), renombrar `_01`. 3. `duplicados.ps1`. 4. `buscar-generos.ps1` → `asignar-generos.ps1` (revisar los artistas sin género y clasificarlos en `generos-manual.txt`) → `-Aplicar`; M4A con `generos-m4a.ps1`. 5. `letras-sincronizadas.ps1` → revisar plan → `-Aplicar` (FLAC: agrega y corrige desincronizadas); `completar-metadatos.ps1` para MP3/M4A y para portadas o datos que falten. 6. `revisar-portadas.ps1`. 7. Resumen: total de canciones, sin género, con/sin letra sincronizada, sin portada, repetidas, espacio libre.
