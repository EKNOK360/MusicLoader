# Pasa todo lo de "D:\SpotiFLAC\Por recuperar\Artista\Album\..." a "D:\SpotiFLAC\Artista\Album\...".
# Si ya existe un archivo con el mismo nombre, el viejo se mueve a D:\SpotiFLAC\_reemplazados (no se borra nada).
# Una cancion que llega SUELTA (sin carpetas) va a Artista\Album segun sus etiquetas (ALBUMARTIST o ARTIST, y ALBUM).
param([string]$Raiz = "", [string]$Origen = "Por recuperar", [switch]$Prueba)
if (-not $Raiz) { $cfg = Join-Path $env:USERPROFILE 'reportes-musica\config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
$ErrorActionPreference = 'Stop'
$src = Join-Path $Raiz $Origen
$bak = Join-Path $Raiz "_reemplazados"
$log = @(); $movidos = 0; $reemplazados = 0; $errores = 0
# cancion suelta (sin carpetas Artista\Album en la descarga): la carpeta se arma con sus etiquetas
$dirDatos = Join-Path $env:USERPROFILE 'reportes-musica'
$mf = Get-Content "$dirDatos\metaflac-path.txt"; $ffp = Join-Path (Split-Path (Get-Content "$dirDatos\ffmpeg-path.txt")) 'ffprobe.exe'
function Limpio($s) { ($s -replace '[\\/:*?"<>|]', ' ' -replace '\s+', ' ').Trim().TrimEnd('.') }
function CarpetaPorEtiquetas($p) {
    if ($p -like '*.flac') { $a = (& $mf --no-utf8-convert --show-tag=ALBUMARTIST --show-tag=ARTIST --show-tag=ALBUM $p) }
    else { $a = (& $ffp -v error -show_entries format_tags=album_artist,artist,album -of default=nw=1 $p) -replace '^TAG:', '' -replace '^album_artist=', 'ALBUMARTIST=' -replace '^artist=', 'ARTIST=' -replace '^album=', 'ALBUM=' }
    $art = ($a | Where-Object { $_ -like 'ALBUMARTIST=*' } | Select-Object -First 1) -replace '^ALBUMARTIST=', ''
    if (-not $art) { $art = (($a | Where-Object { $_ -like 'ARTIST=*' } | Select-Object -First 1) -replace '^ARTIST=', '' -split ',\s*|;\s*')[0] }
    $alb = ($a | Where-Object { $_ -like 'ALBUM=*' } | Select-Object -First 1) -replace '^ALBUM=', ''
    if ($art -and $alb) { Join-Path (Limpio $art) (Limpio $alb) } else { '' }
}
$sueltas = @{}  # nombre sin extension -> carpeta Artista\Album (para que el .lrc vaya con su cancion)
foreach ($a in Get-ChildItem -LiteralPath $src -File | Where-Object { $_.Extension -in '.flac', '.m4a', '.mp3' }) { $sueltas[$a.BaseName] = CarpetaPorEtiquetas $a.FullName }

foreach ($f in Get-ChildItem -LiteralPath $src -Recurse -File) {
    if ($f.Name -like '*.cover.jpg' -or $f.Name -like '.spotiflac-*' -or $f.Extension -eq '.tmp') { continue }  # temporales de la descarga
    $rel = $f.FullName.Substring($src.Length + 1)
    if (-not (Split-Path $rel) -and $sueltas[$f.BaseName]) { $rel = Join-Path $sueltas[$f.BaseName] $rel }  # suelta -> Artista\Album
    $dest = Join-Path $Raiz $rel
    try {
        if (Test-Path -LiteralPath $dest) {
            $viejo = Join-Path $bak $rel
            if (-not $Prueba) { New-Item -ItemType Directory -Force (Split-Path $viejo) | Out-Null; Move-Item -LiteralPath $dest $viejo -Force }
            $log += "REEMPLAZADO  $rel"; $reemplazados++
        } else { $log += "NUEVO        $rel" }
        if (-not $Prueba) { New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null; Move-Item -LiteralPath $f.FullName $dest }
        $movidos++
    } catch { $log += "ERROR        $rel : $($_.Exception.Message)"; $errores++ }
}

# quitar carpetas vacias que quedaron en "Por recuperar"
if (-not $Prueba) {
    Get-ChildItem -LiteralPath $src -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending |
        Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Where-Object { $_.Name -notlike '*.cover.jpg' }) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
}

$log | Where-Object { $_ -match '^(NUEVO|REEMPLAZADO)\s+(.+)$' } | ForEach-Object { $Matches[2].Trim() } | Add-Content "$env:USERPROFILE\reportes-musica\movidos-$Origen.txt" -Encoding utf8
$res = "Movidos: $movidos  (nuevos: $($movidos - $reemplazados), reemplazaron a uno viejo: $reemplazados)  Errores: $errores"
if (-not $Prueba) { (@($res, "") + $log) | Set-Content "$env:USERPROFILE\reportes-musica\acomodo-reporte.txt" -Encoding utf8 }
$res
if ($Prueba) { $log } else { $log | Where-Object { $_ -like 'ERROR*' } }
