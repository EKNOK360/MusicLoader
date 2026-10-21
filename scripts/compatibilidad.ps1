# Deja los FLAC compatibles con reproductores sencillos (que dicen "archivo danado / no compatible", se cortan a los
# pocos segundos o muestran "unknown" y el nombre del archivo):
#   - 24 bits / >48 kHz  ->  FLAC 16 bits 44,1 kHz (calidad CD)
#   - portada grande     ->  JPG de 500 px (las de 2000 px y >1 MB traban a muchos reproductores)
# Conserva todas las etiquetas (titulo, artista, album, genero, LETRA, enlace) y el .lrc de al lado (mismo nombre).
# Cada archivo se reemplaza SOLO si la version nueva se decodifica sin errores, dura lo mismo y conserva sus etiquetas.
# Sin -Aplicar: solo muestra cuantos hay que convertir.   Uso: compatibilidad.ps1 -Raiz E:\Music -Aplicar
param([Parameter(Mandatory)][string]$Raiz, [switch]$Aplicar, [int]$Portada = 500)
. "$PSScriptRoot\progreso.ps1"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
$ff = Get-Content "$dir\ffmpeg-path.txt"; $fp = Join-Path (Split-Path $ff) 'ffprobe.exe'; $mf = Get-Content "$dir\metaflac-path.txt"; $py = Get-Content "$dir\python-path.txt"
function Etiquetas($f) { & $mf --no-utf8-convert --export-tags-to=- $f | Where-Object { $_ -match '^[A-Za-z0-9_ ]+=' } | Sort-Object }
$lista = @(Get-ChildItem -LiteralPath $Raiz -Recurse -File -Filter *.flac)
$plan = foreach ($f in $lista) {
    $a = (& $fp -v error -select_streams a:0 -show_entries stream=sample_rate,bits_per_raw_sample -of csv=p=0 $f.FullName) -split ','
    $w = [int]"0$((& $fp -v error -select_streams v -show_entries stream=width -of csv=p=0 $f.FullName) | Select-Object -First 1)"
    $hires = [int]$a[0] -gt 48000 -or [int]$a[1] -gt 16
    if ($hires -or $w -gt $Portada) { [pscustomobject]@{ f = $f; hires = $hires; w = $w } }
}
$plan = @($plan)
"FLAC: $($lista.Count) | a convertir: $($plan.Count) (alta resolucion: $(@($plan | Where-Object hires).Count), portada grande: $(@($plan | Where-Object { $_.w -gt $Portada }).Count))"
if (-not $Aplicar) { return }

$tmpA = Join-Path $env:TEMP 'compat-audio.flac'; $tmpC = Join-Path $env:TEMP 'compat-cover.jpg'; $bien = 0; $mal = @(); $n = 0
foreach ($x in $plan) {
    $n++; $p = $x.f.FullName; Progreso 'compatibilidad' $n $plan.Count @{ listas = $bien; problemas = $mal.Count } $x.f.BaseName
    $antes = Etiquetas $p; $d1 = [double](& $fp -v error -show_entries format=duration -of csv=p=0 $p)
    if ($x.w) { & $ff -v error -y -i $p -an -vf "scale=${Portada}:-2" -q:v 3 $tmpC }
    if ($x.hires) { & $ff -v error -y -i $p -map 0:a -c:a flac -sample_fmt s16 -ar 44100 -map_metadata -1 $tmpA }   # audio nuevo; etiquetas se copian abajo tal cual
    else { Copy-Item -LiteralPath $p $tmpA -Force }
    # etiquetas (letra de varias lineas, generos multiples) y portada: con mutagen (copiar-etiquetas.py)
    if ($x.w -and (Test-Path $tmpC)) { & $py "$PSScriptRoot\copiar-etiquetas.py" $p $tmpA $tmpC } else { & $py "$PSScriptRoot\copiar-etiquetas.py" $p $tmpA }
    $err = & $ff -v error -i $tmpA -f null - 2>&1
    $d2 = [double](& $fp -v error -show_entries format=duration -of csv=p=0 $tmpA)
    if (-not $err -and [Math]::Abs($d1 - $d2) -le 0.5 -and -not (Compare-Object @($antes) @(Etiquetas $tmpA))) { Copy-Item -LiteralPath $tmpA -Destination $p -Force; $bien++ }
    else { $mal += $x.f.Name }
    Remove-Item $tmpC -ErrorAction SilentlyContinue
}
Progreso 'compatibilidad' $plan.Count $plan.Count @{ listas = $bien; problemas = $mal.Count } ''
"Convertidas: $bien | sin tocar por problemas: $($mal.Count)"; $mal
