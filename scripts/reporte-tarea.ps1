# Vigilante de TAREAS (revisiones largas: letras, generos, metadatos, danos, portadas...). Por defecto: una linea TAREA cada 10 min, INICIO/ERROR/TERMINADA al momento.
# Lee reportes-musica\tarea-*.json (escritos por progreso.ps1) y emite una linea "TAREA ..." por tarea:
#   - tareas grandes (>= 1000 archivos): cada 10 minutos
#   - tareas chicas  (<  1000 archivos): cada 100 archivos
# y una linea "TERMINADA ..." cuando una tarea llega al total. Termina solo cuando ya no queda ninguna activa.
# Uso tipico: Monitor -> powershell -File reporte-tarea.ps1   (re-armar al expirar)
param([int]$Minutos = 10, [int]$CadaArchivos = 100, [int]$Grande = 0, [switch]$SoloEventos)  # por defecto: reporte cada 10 min + aviso inmediato al terminar o con error
[Console]::OutputEncoding = [Text.Encoding]::UTF8  # para que las barras se vean bien
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
$ultHora = @{}; $ultCant = @{}; $vistas = @{}; $mitad = @{}; $malos = @{}; $arranque = Get-Date
$iconos = @{ danos = 'Revision de danos'; 'letras-analisis' = 'Analisis de letras'; 'letras-escribir' = 'Escribiendo letras'; generos = 'Generos'; metadatos = 'Metadatos'; portadas = 'Portadas'; mantenimiento = 'Mantenimiento completo' }
function Barra($pct) { $n = [int][Math]::Round($pct / 5); ('█' * $n) + ('░' * (20 - $n)) }
function Linea($t, $pref) {
    $pct = if ($t.total) { [int](100 * $t.hechos / $t.total) } else { 0 }
    $min = [Math]::Max(0.1, ((Get-Date) - [datetime]$t.inicio).TotalMinutes)
    $vel = $t.hechos / $min
    $fin = if ($vel -gt 0 -and -not $t.terminado) { (Get-Date).AddMinutes(($t.total - $t.hechos) / $vel).ToString('h:mm tt') } else { '-' }
    $nombre = if ($iconos[$t.tarea]) { $iconos[$t.tarea] } else { $t.tarea }
    $datos = ($t.datos.PSObject.Properties | ForEach-Object { "$($_.Name -replace '_', ' ')=$($_.Value)" }) -join ' · '
    "$pref $(Get-Date -Format 'HH:mm') | $nombre | $(Barra $pct) $pct% | $($t.hechos) de $($t.total) | {0:N1}/min | fin: $fin | $datos" -f $vel
}while ($true) {
    $activas = 0
    foreach ($f in Get-ChildItem $dir -Filter 'tarea-*.json' -ErrorAction SilentlyContinue) {
        try { $t = Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { continue }
        if ([datetime]$t.actualizado -lt $arranque.AddHours(-12)) { continue }   # tareas viejas
        $k = $t.tarea
        # las tareas que ya habian terminado antes de arrancar no cuentan (si no, el vigilante se cierra al instante)
        if ($t.terminado) { if (-not $vistas[$k] -and [datetime]$t.actualizado -ge $arranque) { $vistas[$k] = 1; Linea $t 'TERMINADA' }; continue }
        $activas++
        $prob = ($t.datos.PSObject.Properties | Where-Object { $_.Name -in 'problemas', 'danados', 'saltadas' } | Measure-Object Value -Sum).Sum
        if ($prob -gt [int]$malos[$k]) { $malos[$k] = $prob; Linea $t 'ERROR' }
        if (-not $ultHora.ContainsKey($k)) { $ultHora[$k] = Get-Date; $ultCant[$k] = $t.hechos; Linea $t 'INICIO'; continue }
        if ($SoloEventos) { continue }
        $toca = if ($t.total -ge $Grande) { ((Get-Date) - $ultHora[$k]).TotalMinutes -ge $Minutos } else { $t.hechos - $ultCant[$k] -ge $CadaArchivos }
        if ($toca) { $ultHora[$k] = Get-Date; $ultCant[$k] = $t.hechos; Linea $t 'TAREA' }
    }
    if ($activas -eq 0 -and $vistas.Count -gt 0) { break }
    Start-Sleep -Seconds 20
}
