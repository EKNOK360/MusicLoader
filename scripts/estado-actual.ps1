# Imprime la GRAFICA del estado actual de todas las tareas (markdown), para cerrar cada mensaje del chat con ella.
# Lee reportes-musica\tarea-*.json (progreso.ps1). Muestra tareas activas y las terminadas en los ultimos 30 min.
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
$nombres = @{ danos = 'Revisión de daños'; 'letras-analisis' = 'Análisis de letras'; 'letras-escribir' = 'Escribiendo letras'; generos = 'Géneros'; metadatos = 'Metadatos'; portadas = 'Portadas'; mantenimiento = 'Mantenimiento completo'; descarga = 'Descarga' }
function Hora($d) { $d.ToString('h:mm tt', [Globalization.CultureInfo]'es-CR') }
$ahora = Get-Date; $filas = @()
foreach ($f in Get-ChildItem $dir -Filter 'tarea-*.json' -ErrorAction SilentlyContinue) {
    try { $t = Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { continue }
    $act = [datetime]$t.actualizado; $ini = [datetime]$t.inicio
    if ($t.terminado -and ($ahora - $act).TotalMinutes -gt 30) { continue }
    if (-not $t.terminado -and ($ahora - $act).TotalHours -gt 2) { continue }
    $pct = if ($t.total) { [Math]::Min(100, [int](100 * $t.hechos / $t.total)) } else { 0 }
    $n = [int][Math]::Round($pct / 5); $barra = ('█' * $n) + ('░' * (20 - $n))
    $vel = $t.hechos / [Math]::Max(0.1, ($act - $ini).TotalMinutes)
    $prob = ($t.datos.PSObject.Properties | Where-Object { $_.Name -in 'problemas', 'danados', 'saltadas' } | Measure-Object Value -Sum).Sum
    $estado = if ($t.terminado) { if ($prob) { "⚠️ terminó con $prob problema(s)" } else { '✅ terminó' } } elseif ($t.total -gt 10 -and ($ahora - $act).TotalMinutes -gt 1) { "🟡 sin avanzar hace $([int]($ahora - $act).TotalMinutes) min" } elseif ($prob) { "⚠️ $prob problema(s)" } else { '▶️ en curso' }
    $fin = if ($t.terminado) { Hora $act } elseif ($vel -gt 0) { Hora ($act.AddMinutes(($t.total - $t.hechos) / $vel)) } else { '—' }
    $nom = if ($nombres[$t.tarea]) { $nombres[$t.tarea] } else { $t.tarea }
    $cuenta = if ($t.total -le 10) { "Paso $($t.hechos + [int](-not $t.terminado)) de $($t.total)$(if ($t.datos.paso) { " ($($t.datos.paso))" })" } else { "$('{0:N0}' -f $t.hechos) de $('{0:N0}' -f $t.total) canciones" }
    $lineas = @("**$nom**", "``$barra`` **$pct%**", "- 🎵 $cuenta", "- 🕐 Inicio: $(Hora $ini)", "- 🏁 $(if ($t.terminado) { 'Terminó' } else { 'Fin estimado' }): $fin", "- 📌 Estado: $estado")
    if ($t.actual -and -not $t.terminado) { $lineas += "- ♪ Ahora: $($t.actual)" }
    $filas += [pscustomobject]@{ orden = [int]$t.terminado; txt = ($lineas -join "`n") + "`n" }
}
"## 📊 Estado actual · $(Hora $ahora)"
if (-not $filas) { 'Sin tareas en curso.'; return }
($filas | Sort-Object orden).txt
