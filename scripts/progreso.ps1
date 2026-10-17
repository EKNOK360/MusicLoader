# Ayudante de avance para tareas largas. Se carga con:  . "$PSScriptRoot\progreso.ps1"
# Progreso 'nombre' hechos total @{ agregadas = 3; problemas = 0 }  -> escribe reportes-musica\tarea-<nombre>.json
# (como mucho cada 5 s; siempre al llegar al total). reporte-tarea.ps1 lee esos archivos y arma el reporte.
$script:__progDir = Join-Path $env:USERPROFILE 'reportes-musica'
$script:__progUlt = @{}
function Progreso([string]$Tarea, [int]$Hechos, [int]$Total, [hashtable]$Datos = @{}) {
    $ahora = Get-Date
    if ($Hechos -lt $Total -and $script:__progUlt[$Tarea] -and ($ahora - $script:__progUlt[$Tarea]).TotalSeconds -lt 5) { return }
    $script:__progUlt[$Tarea] = $ahora
    $f = Join-Path $script:__progDir "tarea-$Tarea.json"
    $inicio = if (Test-Path $f) { try { (Get-Content $f -Raw | ConvertFrom-Json).inicio } catch { $null } } else { $null }
    if (-not $inicio -or $Hechos -le 1) { $inicio = $ahora.ToString('o') }
    [ordered]@{ tarea = $Tarea; hechos = $Hechos; total = $Total; inicio = $inicio; actualizado = $ahora.ToString('o'); terminado = ($Hechos -ge $Total); datos = $Datos } |
        ConvertTo-Json -Depth 3 -Compress | Set-Content $f -Encoding utf8
}
