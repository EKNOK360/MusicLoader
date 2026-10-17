# Solo lectura: revisa la portada incrustada de cada cancion (FLAC, MP3, M4A).
# Reporta canciones SIN portada y con portada pequena (< 500 px), agrupadas por album.
# Las medidas se leen de la imagen real con ffprobe (algunos descargadores dejan "width: 0" en el bloque PICTURE).
param([string]$Raiz = "", [int]$MinPx = 500)
. "$PSScriptRoot\progreso.ps1"
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
if (-not $Raiz) { $cfg = Join-Path $dir 'config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
$ff = Get-Content (Join-Path $dir 'ffmpeg-path.txt'); $fp = Join-Path (Split-Path $ff) 'ffprobe.exe'
$todos = @(Get-ChildItem $Raiz -Recurse -File | Where-Object { $_.Extension -in '.flac', '.mp3', '.m4a' }); $n = 0
$sin = @(); $chica = @(); $ok = 0
foreach ($f in $todos) {
    $n++; Progreso 'portadas' $n $todos.Count @{ sin_portada = $sin.Count; pequenas = $chica.Count } $f.BaseName
    $w = 0
    $s = & $fp -v error -select_streams v -show_entries stream=width -of csv=p=0 $f.FullName 2>$null
    foreach ($x in @($s)) { if ([int]"0$x" -gt $w) { $w = [int]"0$x" } }
    $rel = $f.FullName.Substring($Raiz.Length + 1)
    if (-not $w) { $sin += $rel } elseif ($w -lt $MinPx) { $chica += "$rel ($w px)" } else { $ok++ }
}
"Con portada buena: $ok | sin portada: $($sin.Count) | portada pequena (< $MinPx px): $($chica.Count)"
"--- sin portada (por album):"; $sin | Group-Object { Split-Path $_ } | ForEach-Object { "$($_.Name) ($($_.Count))" }
"--- portada pequena:"; $chica
