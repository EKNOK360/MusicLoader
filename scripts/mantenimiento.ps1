# Mantenimiento COMPLETO de la biblioteca, en orden y sin intervencion:
#   0) (opcional) esperar a que termine otra tarea   1) acomodar descargas de SpotiFLAC pendientes
#   2) generos (MusicBrainz + reglas)   3) letras sincronizadas (agregar + corregir)
#   4) completar metadatos (titulo, artista, album, ano, pista, genero, portada, letra)  5) portadas  6) repetidas (solo reporte)
# Cada paso deja su avance en reportes-musica\tarea-*.json (ver reporte-tarea.ps1) y su salida en mantenimiento.log.
param([string]$Raiz = "", [string]$EsperarArchivo = "", [string]$EsperarTexto = "REVISADOS")
. "$PSScriptRoot\progreso.ps1"
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
if (-not $Raiz) { $cfg = Join-Path $dir 'config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
$log = Join-Path $dir 'mantenimiento.log'; "=== Mantenimiento $(Get-Date -Format 'yyyy-MM-dd HH:mm') en $Raiz" | Set-Content $log -Encoding utf8
function Paso($n, $nombre, $script, $argsExtra) {
    Progreso 'mantenimiento' ($n - 1) 6 @{ paso = $nombre }
    "`n=== $n. $nombre ($(Get-Date -Format HH:mm))" | Add-Content $log -Encoding utf8
    $salida = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $script) @argsExtra 2>&1 | ForEach-Object { "$_" }
    $salida | Add-Content $log -Encoding utf8
    "PASO $n $nombre listo: $(($salida | Where-Object { $_ -match '^(Revisadas|revisadas|Letras escritas|Escritos|Con portada|Canciones con genero|Movidos)' }) -join ' / ')"
}
if ($EsperarArchivo) { while (-not (Select-String -LiteralPath $EsperarArchivo -Pattern $EsperarTexto -Quiet -ErrorAction SilentlyContinue)) { Start-Sleep 30 } }
# 1) descargas de SpotiFLAC pendientes (carpetas "Descargar ..." o "Por ..." en la raiz)
Progreso 'mantenimiento' 0 6 @{ paso = 'acomodar' }
foreach ($d in Get-ChildItem $Raiz -Directory | Where-Object { $_.Name -like 'Descargar*' -or $_.Name -like 'Por *' -or $_.Name -like 'Likes*' }) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\acomodar-descargas.ps1" -Raiz $Raiz -Origen $d.Name | Add-Content $log -Encoding utf8
}
Paso 2 'generos' 'buscar-generos.ps1' @()
Paso 2 'generos' 'asignar-generos.ps1' @('-Aplicar')
Paso 3 'letras' 'letras-sincronizadas.ps1' @('-Aplicar')
Paso 4 'metadatos' 'completar-metadatos.ps1' @('-Raiz', $Raiz, '-Aplicar')
Paso 5 'portadas' 'revisar-portadas.ps1' @('-Raiz', $Raiz)
Paso 6 'repetidas' 'duplicados.ps1' @()
Progreso 'mantenimiento' 6 6 @{ paso = 'terminado' }
"MANTENIMIENTO TERMINADO $(Get-Date -Format HH:mm) - detalle en $log"
