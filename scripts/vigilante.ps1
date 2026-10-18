# Vigilante: anota cada 2 min en reportes-musica\progreso.txt cuantas canciones hay en la carpeta de descarga
# y termina (imprime TERMINADO) cuando pasan 20 min sin canciones nuevas y no quedan temporales.
# Uso: vigilante.ps1  (lee la carpeta de reportes-musica\vigilar.txt, linea 2)
$dir = (Join-Path $env:USERPROFILE 'reportes-musica'); $vig = @(Get-Content "$dir\vigilar.txt" -Encoding utf8)
$src = if ([IO.Path]::IsPathRooted($vig[1])) { $vig[1] } else { Join-Path 'D:\SpotiFLAC' $vig[1] }  # ruta completa = descarga fuera de la biblioteca
 $log = "$dir\progreso.txt"; $mov = "$dir\movidos-$(Split-Path $vig[1] -Leaf).txt"
$arranque = Get-Date
Remove-Item $log -ErrorAction SilentlyContinue  # cada descarga empieza con registro limpio (si no, la velocidad mezcla descargas)
while ($true) {
    $a = @(Get-ChildItem -LiteralPath $src -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.flac', '.m4a', '.mp3' } | Where-Object { $_.Name -notlike '.spotiflac-*' })
    $nMov = if (Test-Path $mov) { @(Get-Content $mov -Encoding utf8 | Where-Object { $_ -match '\.(flac|m4a|mp3)$' }).Count } else { 0 }
    $temp = @(Get-ChildItem -LiteralPath $src -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.spotiflac-*' -or $_.Extension -eq '.tmp' })
    $ult = ($a | Measure-Object LastWriteTime -Maximum).Maximum
    $desde = if ($ult -and $ult -gt $arranque) { $ult } else { $arranque }  # al reiniciar el vigilante, los 20 min se cuentan desde que arranca
    $quieto = [int]((Get-Date) - $desde).TotalMinutes
    "$(Get-Date -Format 'HH:mm')  canciones: $($a.Count + $nMov)  ({0:N1} GB)  sin cambios hace $quieto min" -f (($a | Measure-Object Length -Sum).Sum / 1GB) | Add-Content $log
    if ($a.Count -gt 0 -and $quieto -ge 20 -and $temp.Count -eq 0) { "TERMINADO: $($a.Count) canciones en $($vig[1]), ultima a las $($ult.ToString('HH:mm'))"; break }
    Start-Sleep -Seconds 120
}
