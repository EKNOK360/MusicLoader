# Cada 15 min imprime avance, velocidad de descarga de canciones, hora estimada
# y velocidad de internet (promedio y pico, bajada/subida, medida cada 10 s).
. "$PSScriptRoot\saltadas.ps1"; $log = "$env:USERPROFILE\reportes-musica\progreso.txt"; $total = $script:lista.Count; $cada = 10; $periodo = 870
function Bytes { $s = Get-NetAdapter | Where-Object Status -eq 'Up' | Get-NetAdapterStatistics; [pscustomobject]@{ rx = ($s | Measure-Object ReceivedBytes -Sum).Sum; tx = ($s | Measure-Object SentBytes -Sum).Sum } }
function Mbps($bytes, $seg) { $bytes * 8 / 1e6 / $seg }
function Linea($bajProm, $subProm, $bajPico, $subPico) {
    $l = @(Get-Content $log | Where-Object { $_ -match 'canciones: \d+' })
    [void]($l[-1] -match '^(\d\d:\d\d)\s+canciones: (\d+)\s+\(([\d,\.]+) GB\)\s+sin cambios hace (\d+)')
    $n = [int]$Matches[2]; $gb = $Matches[3]; $quieto = [int]$Matches[4]
    [void]($l[[Math]::Max(0, $l.Count - 16)] -match 'canciones: (\d+)')  # ~30 min antes
    $vel = ($n - [int]$Matches[1]) / [Math]::Max(1, ([Math]::Min(15, $l.Count - 1) * 2))
    $fin = if ($vel -gt 0) { (Get-Date).AddMinutes(($total - $n) / $vel).ToString('h:mm tt') } else { '?' }
    $d = Get-PSDrive D
    $falta = ($total - $n) * ([double]($gb -replace ',', '.') / [Math]::Max(1, $n))  # GB que faltan, con el peso promedio real
    "AVANCE $(Get-Date -Format 'HH:mm') | $n de $total ($([int](100*$n/$total))%) | $gb GB | {0:N1} canciones/min | fin estimado: $fin | sin cambios hace $quieto min | internet bajada prom {1:N1} / pico {2:N1} Mbps, subida prom {3:N1} / pico {4:N1} Mbps | disco D libre {5:N1} de {6:N1} GB ({7}% usado), faltan ~{8:N1} GB por bajar, libre al terminar ~{9:N1} GB | {10}" -f $vel, $bajProm, $bajPico, $subProm, $subPico, ($d.Free/1GB), (($d.Used+$d.Free)/1GB), [int](100*$d.Used/($d.Used+$d.Free)), $falta, ($d.Free/1GB - $falta), $(try { $r = Saltadas; "va por la #$($r.posicion), saltadas $($r.saltadas.Count): $(($r.saltadas | Select-Object -First 10) -join '; ')" } catch { "saltadas: error $($_.Exception.Message)" })
}
while ($true) {
    $ini = Bytes; $prev = $ini; $bp = 0.0; $sp = 0.0
    for ($t = 0; $t -lt $periodo; $t += $cada) {
        Start-Sleep -Seconds $cada
        $cur = Bytes
        $bp = [Math]::Max($bp, (Mbps ($cur.rx - $prev.rx) $cada)); $sp = [Math]::Max($sp, (Mbps ($cur.tx - $prev.tx) $cada))
        $prev = $cur
    }
    try { Linea (Mbps ($prev.rx - $ini.rx) $periodo) (Mbps ($prev.tx - $ini.tx) $periodo) $bp $sp } catch { "AVANCE error: $($_.Exception.Message)" }
}
