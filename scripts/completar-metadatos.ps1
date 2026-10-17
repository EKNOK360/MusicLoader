# Completa metadatos de canciones FLAC, MP3 y M4A de CUALQUIER descargador (SpotiFLAC u otro).
# Solo AGREGA lo que falta; nunca cambia lo que ya tiene el archivo.
#   - Titulo, artista, album, artista del album, ano, pista y genero  -> iTunes Search API (gratis, sin cuenta)
#   - Portada (1200 px)                                               -> iTunes
#   - Letra SINCRONIZADA                                              -> LRCLIB o NetEase (duracion +-2 s)
# Escritura:
#   FLAC: metaflac (solo etiquetas/imagen; el audio no se toca). Se comprueba la huella de los bytes de audio.
#   MP3 : ffmpeg crea una copia con las etiquetas (-c copy); se compara CADA cuadro de audio y las etiquetas
#         que ya tenia; solo si todo es identico reemplaza el original. Letra tambien en .lrc al lado.
#   M4A : no se reescribe (ffmpeg pierde portada/cuadros); solo se crea el .lrc al lado y se reporta lo que falta.
# Sin -Aplicar: solo muestra el plan. -Archivo: un solo archivo (para pruebas). -Raiz: carpeta de la musica.
param([string]$Raiz = "", [string]$Archivo = "", [switch]$Aplicar, [switch]$SinLetras, [switch]$SinPortadas)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\progreso.ps1"
. "$PSScriptRoot\lrc-fuentes.ps1"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$dir = Join-Path $env:USERPROFILE 'reportes-musica'; New-Item -ItemType Directory -Force $dir | Out-Null
if (-not $Raiz) { $cfg = Join-Path $dir 'config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
$mf = Get-Content (Join-Path $dir 'metaflac-path.txt')
$ff = Get-Content (Join-Path $dir 'ffmpeg-path.txt'); $fp = Join-Path (Split-Path $ff) 'ffprobe.exe'
$cacheFile = Join-Path $dir 'itunes-cache.json'
$cache = @{}; if (Test-Path $cacheFile) { (Get-Content $cacheFile -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } }

function Json($url) { $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8; $wc.Headers.Add('User-Agent', 'MusicLoader/1.0'); try { $wc.DownloadString($url) | ConvertFrom-Json } finally { $wc.Dispose() } }
function Norm($s) { if (-not $s) { return '' }; ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '\(.*?\)|\[.*?\]' -replace '[^\p{L}\p{N}]', '' }
function Info($f) {
    $j = & $fp -v error -show_format -show_streams -of json $f | ConvertFrom-Json
    $t = @{}; foreach ($p in @($j.format.tags.PSObject.Properties) + @($j.streams | Where-Object codec_type -eq 'audio' | ForEach-Object { $_.tags.PSObject.Properties })) { if ($p) { $t[($p.Name.ToLower() -replace '-.*$', '')] = "$($p.Value)" } }
    [pscustomobject]@{ tags = $t; dur = [double]$j.format.duration; pic = [bool]($j.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -eq 1 }) }
}
function HuellaFlac($f) { $s = [IO.File]::OpenRead($f); try { $b = New-Object byte[] 4; [void]$s.Read($b, 0, 4); $u = $false; while (-not $u) { [void]$s.Read($b, 0, 4); $u = ($b[0] -band 0x80) -ne 0; $l = ([int]$b[1] -shl 16) -bor ([int]$b[2] -shl 8) -bor [int]$b[3]; [void]$s.Seek($l, 'Current') }; [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($s)) } finally { $s.Close() } }
# contenido de cada cuadro (sin marcas de tiempo, que ffmpeg recalcula) + sonido decodificado completo
function CuadrosAudio($f) { ((& $ff -v error -i $f -map 0:a -c copy -f framemd5 - | Where-Object { $_ -notmatch '^#' } | ForEach-Object { ($_ -split ',\s*')[5] }) -join "`n") + "`n" + (& $ff -v error -i $f -map 0:a -f md5 -) }
function ITunes($art, $tit) {
    $k = "$art|$tit"; if ($cache.ContainsKey($k)) { return $cache[$k] }
    $r = $null
    try {
        $res = @((Json "https://itunes.apple.com/search?country=US&lang=en_us&entity=song&limit=10&term=$([uri]::EscapeDataString("$art $tit"))").results)
        $r = $res | Where-Object { (Norm $_.trackName) -eq (Norm $tit) -and ((Norm $_.artistName).Contains((Norm $art)) -or (Norm $art).Contains((Norm $_.artistName))) } | Select-Object -First 1
    } catch { }
    $v = if ($r) { [pscustomobject]@{ title = $r.trackName; artist = $r.artistName; album = $r.collectionName; albumartist = $(if ($r.collectionArtistName) { $r.collectionArtistName } else { $r.artistName }); date = "$($r.releaseDate)".Substring(0, [Math]::Min(4, "$($r.releaseDate)".Length)); track = "$($r.trackNumber)"; genre = $r.primaryGenreName; cover = ($r.artworkUrl100 -replace '100x100bb', '1200x1200bb'); dur = [double]$r.trackTimeMillis / 1000 } } else { [pscustomobject]@{ title = '' } }
    $cache[$k] = $v; Start-Sleep -Seconds 3  # iTunes permite ~20 consultas por minuto
    $v
}
function Letra($art, $tit, $alb, $dur) { (BuscarLetra $art $tit $alb $dur).lrc }  # LRCLIB + NetEase (lrc-fuentes.ps1)

$archivos = if ($Archivo) { @(Get-Item -LiteralPath $Archivo) } else { @(Get-ChildItem $Raiz -Recurse -File -Include *.flac, *.mp3, *.m4a) }
$campos = 'title', 'artist', 'album', 'album_artist', 'date', 'track', 'genre'
$res = [ordered]@{ revisadas = 0; completas = 0; conCambios = 0; escritas = 0; problemas = 0 }; $detalle = @(); $tmp = Join-Path $env:TEMP 'musicloader'; New-Item -ItemType Directory -Force $tmp | Out-Null
foreach ($f in $archivos) {
    $res.revisadas++; Progreso 'metadatos' $res.revisadas $archivos.Count @{ completas = $res.completas; con_cambios = $res.conCambios; escritas = $res.escritas; problemas = $res.problemas }; if ($res.revisadas % 50 -eq 0) { Write-Host "Avance: $($res.revisadas) de $($archivos.Count)"; $cache | ConvertTo-Json -Depth 3 -Compress | Set-Content $cacheFile -Encoding utf8 }
    $i = Info $f.FullName; $t = $i.tags; $ext = $f.Extension.ToLower()
    if ($t['album_artist'] -eq $null -and $t['albumartist']) { $t['album_artist'] = $t['albumartist'] }
    # artista y titulo: de las etiquetas o del nombre "Artista - Titulo"
    $p = $f.BaseName -split ' - ', 2
    $art = if ($t['artist']) { ($t['artist'] -split ',\s*|;\s*|\s+feat\.?\s+' )[0] } elseif ($p.Count -eq 2) { $p[0] } else { '' }
    $tit = if ($t['title']) { $t['title'] } elseif ($p.Count -eq 2) { $p[1] } else { $f.BaseName }
    $lrcFile = [IO.Path]::ChangeExtension($f.FullName, '.lrc')
    $tieneLetra = (($t['lyrics'] -match '\[\d+:\d+') -or (Test-Path -LiteralPath $lrcFile))
    $falta = @($campos | Where-Object { -not $t[$_] }); $faltaPic = (-not $SinPortadas) -and -not $i.pic; $faltaLetra = (-not $SinLetras) -and -not $tieneLetra
    if (-not $falta -and -not $faltaPic -and -not $faltaLetra) { $res.completas++; continue }
    $nuevo = @{}; $cover = $null
    if ($falta -or $faltaPic) {
        $it = if ($art -and $tit) { ITunes $art $tit } else { [pscustomobject]@{ title = '' } }
        if ($it.title -and (-not $i.dur -or -not $it.dur -or [Math]::Abs($it.dur - $i.dur) -le 15)) {
            $map = @{ title = $it.title; artist = $it.artist; album = $it.album; album_artist = $it.albumartist; date = $it.date; track = $it.track; genre = $it.genre }
            foreach ($c in $falta) { if ($map[$c]) { $nuevo[$c] = $map[$c] } }
            if ($faltaPic -and $it.cover) { $cover = $it.cover }
        }
    }
    $lrc = if ($faltaLetra -and $art -and $tit) { Letra $art $tit $(if ($t['album']) { $t['album'] } else { $nuevo['album'] }) $i.dur } else { '' }
    if (-not $nuevo.Count -and -not $cover -and -not $lrc) { $detalle += "SIN DATOS NUEVOS  $($f.Name)  (falta: $((@($falta) + $(if ($faltaPic) { 'portada' }) + $(if ($faltaLetra) { 'letra' })) -join ', '))"; continue }
    $res.conCambios++
    $detalle += "AGREGAR  $($f.Name): " + ((@($nuevo.Keys | ForEach-Object { "$_=$($nuevo[$_])" }) + $(if ($cover) { 'portada' }) + $(if ($lrc) { 'letra sincronizada' })) -join ' | ')
    if (-not $Aplicar) { continue }

    $img = $null; if ($cover) { $img = Join-Path $tmp 'cover.jpg'; (New-Object Net.WebClient).DownloadFile($cover, $img) }
    $ok = $false; $fecha = $f.LastWriteTime
    try {
        if ($ext -eq '.flac') {
            $h = HuellaFlac $f.FullName
            $vorbis = @{ title = 'TITLE'; artist = 'ARTIST'; album = 'ALBUM'; album_artist = 'ALBUMARTIST'; date = 'DATE'; track = 'TRACKNUMBER'; genre = 'GENRE' }
            $a = @('--preserve-modtime') + @($nuevo.Keys | ForEach-Object { "--set-tag=$($vorbis[$_])=$($nuevo[$_])" })
            if ($img) { $a += "--import-picture-from=3||||$img" }
            if ($lrc) { $lf = Join-Path $tmp 'letra.lrc'; [IO.File]::WriteAllText($lf, $lrc, (New-Object Text.UTF8Encoding $false)); $a += "--set-tag-from-file=LYRICS=$lf" }
            if ($a.Count -gt 1) { & $mf @a $f.FullName }
            $ok = ($LASTEXITCODE -eq 0) -and ($h -eq (HuellaFlac $f.FullName))
        } elseif ($ext -eq '.mp3') {
            $out = Join-Path $tmp ("nuevo" + $ext)

            $todo = @{}; foreach ($k in $t.Keys) { if ($k -ne 'encoder') { $todo[$k] = $t[$k] } }; foreach ($k in $nuevo.Keys) { $todo[$k] = $nuevo[$k] }; if ($lrc) { $todo['lyrics'] = $lrc }
            $esc = { param($v) ($v -replace '\\', '\\' -replace '=', '\=' -replace ';', '\;' -replace '#', '\#' -replace "`r?`n", "\`n") }
            $meta = Join-Path $tmp 'meta.txt'; [IO.File]::WriteAllText($meta, ";FFMETADATA1`n" + (($todo.Keys | ForEach-Object { "$_=$(& $esc $todo[$_])" }) -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
            $a = @('-v', 'error', '-y', '-i', $f.FullName, '-f', 'ffmetadata', '-i', $meta); if ($img) { $a += @('-i', $img) }
            $a += @('-map', '0:a'); if ($i.pic) { $a += @('-map', '0:v') } elseif ($img) { $a += @('-map', '2:0') }
            $a += @('-c', 'copy', '-map_metadata', '1', '-id3v2_version', '3')
            if ($img -and -not $i.pic) { $a += @('-metadata:s:v:0', 'title=Album cover', '-metadata:s:v:0', 'comment=Cover (front)', '-disposition:v:0', 'attached_pic') }
            $a += $out
            & $ff @a
            $j = Info $out
            $difs = @($t.Keys | Where-Object { $_ -notin 'encoder' -and $j.tags[$_] -ne $t[$_] }); $tagsOk = -not $difs.Count; if (-not $tagsOk) { $detalle += "   etiquetas que cambiaron: $($difs -join ', ')" }; if ((CuadrosAudio $f.FullName) -ne (CuadrosAudio $out)) { $detalle += "   el audio cambio" }
            if ($LASTEXITCODE -eq 0 -and $tagsOk -and (CuadrosAudio $f.FullName) -eq (CuadrosAudio $out)) { Move-Item $out $f.FullName -Force; (Get-Item -LiteralPath $f.FullName).LastWriteTime = $fecha; $ok = $true } else { Remove-Item $out -ErrorAction SilentlyContinue }
        } else { $ok = $true }  # M4A: solo el .lrc
        if ($ok -and $lrc -and $ext -ne '.flac') { [IO.File]::WriteAllText($lrcFile, $lrc, (New-Object Text.UTF8Encoding $false)) }
    } catch { $ok = $false; $detalle += "   motivo: $($_.Exception.Message)" }
    if ($ok) { $res.escritas++ } else { $res.problemas++; $detalle += "PROBLEMA (no se cambio nada)  $($f.FullName)" }
}
$cache | ConvertTo-Json -Depth 3 -Compress | Set-Content $cacheFile -Encoding utf8
($res.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ' | '
$detalle
