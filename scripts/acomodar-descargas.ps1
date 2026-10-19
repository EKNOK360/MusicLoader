# Pasa todo lo de "D:\SpotiFLAC\Por recuperar\Artista\Album\..." a "D:\SpotiFLAC\Artista\Album\...".
# Si ya existe un archivo con el mismo nombre, el viejo se mueve a D:\SpotiFLAC\_reemplazados (no se borra nada).
param([string]$Raiz = "", [string]$Origen = "Por recuperar", [switch]$Prueba)
if (-not $Raiz) { $cfg = Join-Path $env:USERPROFILE 'reportes-musica\config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
$ErrorActionPreference = 'Stop'
$src = Join-Path $Raiz $Origen
$bak = Join-Path $Raiz "_reemplazados"
$log = @(); $movidos = 0; $reemplazados = 0; $errores = 0

foreach ($f in Get-ChildItem -LiteralPath $src -Recurse -File) {
    if ($f.Name -like '*.cover.jpg' -or $f.Name -like '.spotiflac-*' -or $f.Extension -eq '.tmp') { continue }  # temporales de la descarga
    $rel = $f.FullName.Substring($src.Length + 1)
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
$log | Where-Object { $_ -like 'ERROR*' }
