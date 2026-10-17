# Genero para M4A/MP3 (los FLAC van con asignar-generos.ps1). Usa el sistema de propiedades de Windows
# (genero-windows.ps1) y verifica con ffprobe que etiquetas, portada y CADA cuadro de audio queden identicos;
# si algo cambia, restaura el respaldo. Generos: reportes-musica\generos-manual.txt o mb (via asignar-generos -SoloPlan).
param([Parameter(Mandatory)][hashtable]$Generos)  # @{ 'Artista' = 'Genero1;Genero2' }
$ff = Get-Content (Join-Path $env:USERPROFILE 'reportes-musica\ffmpeg-path.txt'); $fp = Join-Path (Split-Path $ff) 'ffprobe.exe'
$bk = Join-Path $env:TEMP 'respaldo-m4a'; New-Item -ItemType Directory -Force $bk | Out-Null
function Firma($f) { $i = & $fp -v error -show_format -show_streams -of json $f | ConvertFrom-Json; $t = ($i.format.tags.PSObject.Properties | Where-Object Name -ne 'genre' | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "`n"; $h = (& $ff -v error -i $f -map 0 -c copy -f framemd5 - | Where-Object { $_ -notmatch '^#' }) -join "`n"; "$t`n$($i.streams.Count)`n$h" }
foreach ($f in Get-ChildItem 'D:\SpotiFLAC' -Recurse -File -Include *.m4a, *.mp3) {
    $art = ($f.BaseName -split ' - ', 2)[0]; $g = $Generos[$art]; if (-not $g) { "SIN GENERO DEFINIDO: $($f.Name)"; continue }
    $copia = Join-Path $bk $f.Name; Copy-Item -LiteralPath $f.FullName $copia -Force; $fecha = $f.LastWriteTime
    $antes = Firma $f.FullName
    powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\genero-windows.ps1" -Archivo $f.FullName -Generos $g
    $desp = Firma $f.FullName
    $nuevo = & $fp -v error -show_entries format_tags=genre -of default=nw=1:nk=1 $f.FullName
    if ($antes -eq $desp -and $nuevo) { (Get-Item -LiteralPath $f.FullName).LastWriteTime = $fecha; "OK  $($f.BaseName) -> $nuevo" } else { Copy-Item $copia -LiteralPath $f.FullName -Force; "RESTAURADO: $($f.Name)" }
}
Remove-Item $bk -Recurse -Force
