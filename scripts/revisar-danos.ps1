# Revisa que ningun archivo de musica este danado.
#   FLAC: flac -t (decodifica todo el audio y verifica).   MP3/M4A: ffmpeg decodifica todo y reporta errores.
# Solo lectura. Avance en reportes-musica\tarea-danos.json (ver reporte-tarea.ps1).
param([string]$Raiz = "")
. "$PSScriptRoot\progreso.ps1"
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
if (-not $Raiz) { $cfg = Join-Path $dir 'config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
$mf = Get-Content (Join-Path $dir 'metaflac-path.txt'); $flac = Join-Path (Split-Path $mf) 'flac.exe'
$ff = Get-Content (Join-Path $dir 'ffmpeg-path.txt')
$f = @(Get-ChildItem $Raiz -Recurse -File | Where-Object { $_.Extension -in '.flac', '.mp3', '.m4a' })
$mal = @(); $i = 0
foreach ($x in $f) {
    $i++
    if ($x.Extension -eq '.flac') { $o = & $flac -t -s $x.FullName 2>&1; if ($LASTEXITCODE -ne 0) { $mal += "$($x.FullName) :: $(($o | Select-Object -Last 1))" } }
    else { $o = & $ff -v error -i $x.FullName -map 0:a -f null - 2>&1; if ($o) { $mal += "$($x.FullName) :: $(($o | Select-Object -First 1))" } }
    Progreso 'danos' $i $f.Count @{ danados = $mal.Count } $x.BaseName
}
"REVISADOS: $($f.Count) | DANADOS: $($mal.Count)"; $mal
