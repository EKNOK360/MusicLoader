# Letras SINCRONIZADAS (LRC) para los FLAC de D:\SpotiFLAC. Fuente: LRCLIB (lrclib.net, base abierta y gratuita).
#  - Sin letra sincronizada  -> se agrega la de LRCLIB si es valida.
#  - Con letra sincronizada  -> se compara linea por linea con LRCLIB; si va desfasada (> 0.75 s de mediana)
#                               o tiene tiempos despues del final de la cancion, se reemplaza por la de LRCLIB.
#  - Instrumentales (LRCLIB instrumental=true) -> no se tocan.
# Una letra de LRCLIB es valida si: es sincronizada, su duracion coincide con la del archivo (+-2 s; se elige la
# mas parecida), el ultimo tiempo no pasa el final y tiene >= 5 lineas con tiempo.
# Sin -Aplicar: solo busca (guarda cache) y muestra el plan. Con -Aplicar: escribe SOLO la etiqueta LYRICS y
# verifica que los bytes del audio y las demas etiquetas queden identicos. -Archivo x.flac: solo ese archivo.
param([switch]$Aplicar, [string]$Archivo = "")
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dir = (Join-Path $env:USERPROFILE 'reportes-musica')
$mf = Get-Content "$dir\metaflac-path.txt"
[Console]::OutputEncoding = [Text.Encoding]::UTF8  # metaflac --no-utf8-convert entrega UTF-8 tal cual
$cacheFile = "$dir\lrclib-cache.json"
$cache = @{}; if (Test-Path $cacheFile) { (Get-Content $cacheFile -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } }

function Json($url) { $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8; $wc.Headers.Add('User-Agent', 'MusicLoader/1.0 (organizador personal)'); try { $wc.DownloadString($url) | ConvertFrom-Json } finally { $wc.Dispose() } }
function HuellaAudio($f) {  # SHA256 de todo lo que va despues de los bloques de metadatos
    $s = [IO.File]::OpenRead($f)
    try {
        $b = New-Object byte[] 4; [void]$s.Read($b, 0, 4); $ultimo = $false
        while (-not $ultimo) { [void]$s.Read($b, 0, 4); $ultimo = ($b[0] -band 0x80) -ne 0; $len = ([int]$b[1] -shl 16) -bor ([int]$b[2] -shl 8) -bor [int]$b[3]; [void]$s.Seek($len, 'Current') }
        [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($s))
    } finally { $s.Close() }
}
function Tag($f, $k) { (& $mf --no-utf8-convert "--show-tag=$k" $f | Select-Object -First 1) -replace "^$k=", '' }
function Duracion($f) { [double](& $mf --show-total-samples $f) / [double](& $mf --show-sample-rate $f) }
function Norm($s) { ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^\p{L}\p{N}]', '' }
function Lineas($lrc) {  # -> lista de @{t=segundos; x=texto normalizado}
    foreach ($m in [regex]::Matches("$lrc", '(?m)^\[(\d+):(\d+(?:\.\d+)?)\](.*)$')) {
        [pscustomobject]@{ t = [int]$m.Groups[1].Value * 60 + [double]$m.Groups[2].Value; x = (Norm $m.Groups[3].Value) }
    }
}
function Buscar($art, $tit, $alb, $dur) {
    $k = "$art|$tit|$([int]$dur)"
    if ($cache.ContainsKey($k)) { return $cache[$k] }
    $cands = @()
    try { $g = Json "https://lrclib.net/api/get?artist_name=$([uri]::EscapeDataString($art))&track_name=$([uri]::EscapeDataString($tit))&album_name=$([uri]::EscapeDataString($alb))&duration=$([int][Math]::Round($dur))"; if ($g) { $cands += $g } } catch { }
    try { $cands += @(Json "https://lrclib.net/api/search?artist_name=$([uri]::EscapeDataString($art))&track_name=$([uri]::EscapeDataString($tit))") } catch { }
    $cands = @($cands | ForEach-Object { $_ } | Where-Object { $_ -and $_.duration })
    $inst = [bool]($cands | Where-Object { $_.instrumental -and [Math]::Abs([double]$_.duration - $dur) -le 2 })
    $best = $cands | Where-Object { $_.syncedLyrics -and [Math]::Abs([double]$_.duration - $dur) -le 2 } | Sort-Object { [Math]::Abs([double]$_.duration - $dur) } | Select-Object -First 1
    $v = [pscustomobject]@{ lrc = $(if ($best) { $best.syncedLyrics } else { '' }); dur = $(if ($best) { [double]$best.duration } else { 0 }); inst = $inst }
    $cache[$k] = $v; Start-Sleep -Milliseconds 250
    $v
}
function Valida($lrc, $dur) { $l = @(Lineas $lrc); $l.Count -ge 5 -and $l[-1].t -le $dur + 1 }
function Desfase($vieja, $nueva) {  # mediana de (tiempo viejo - tiempo nuevo) en lineas con el mismo texto
    $n = @{}; foreach ($l in Lineas $nueva) { if ($l.x.Length -ge 6 -and -not $n.ContainsKey($l.x)) { $n[$l.x] = $l.t } }
    $d = @(foreach ($l in Lineas $vieja) { if ($n.ContainsKey($l.x)) { $l.t - $n[$l.x] } }) | Sort-Object
    if ($d.Count -lt 5) { return $null }
    $d[[int][Math]::Floor($d.Count / 2)]
}

$archivos = if ($Archivo) { @(Get-Item -LiteralPath $Archivo) } else { @(Get-ChildItem 'D:\SpotiFLAC' -Recurse -File -Filter *.flac) }
$plan = @(); $res = [ordered]@{ agregar = 0; corregir = 0; bien = 0; instrumental = 0; sinLetra = 0; sinComparar = 0 }; $sinLetra = @(); $corregidas = @(); $i = 0
foreach ($f in $archivos) {
    $i++; if ($i % 100 -eq 0) { Write-Host "Avance: $i de $($archivos.Count) $(Get-Date -Format HH:mm)"; $cache | ConvertTo-Json -Depth 3 -Compress | Set-Content $cacheFile -Encoding utf8 }
    $actual = ((& $mf --no-utf8-convert --show-tag=LYRICS $f.FullName) -join "`n") -replace '^LYRICS=', ''
    $tieneSync = $actual -match '(?m)^\[\d+:\d+'
    $art = (Tag $f.FullName 'ARTIST') -split ',\s*|;\s*' | Select-Object -First 1
    $tit = Tag $f.FullName 'TITLE'; $alb = Tag $f.FullName 'ALBUM'; $dur = Duracion $f.FullName
    $r = Buscar $art $tit $alb $dur
    $ok = $r.lrc -and (Valida $r.lrc $dur)
    if (-not $tieneSync) {
        if ($ok) { $plan += [pscustomobject]@{ f = $f.FullName; lrc = $r.lrc; tipo = 'agregar' }; $res.agregar++ }
        elseif ($r.inst) { $res.instrumental++ } else { $res.sinLetra++; $sinLetra += "$art - $tit" }
        continue
    }
    $l = @(Lineas $actual)
    $pasaFinal = $l.Count -and $l[-1].t -gt $dur + 1
    if (-not $ok) { if ($pasaFinal) { $corregidas += "SIN ARREGLO (no hay version buena en LRCLIB): $art - $tit" }; $res.sinComparar++; continue }
    $d = Desfase $actual $r.lrc
    if ($pasaFinal -or ($null -ne $d -and [Math]::Abs($d) -gt 0.75)) {
        $plan += [pscustomobject]@{ f = $f.FullName; lrc = $r.lrc; tipo = 'corregir' }; $res.corregir++
        $corregidas += "{0} - {1}  ({2})" -f $art, $tit, $(if ($pasaFinal) { 'tiempos pasan del final' } else { 'desfase {0:+0.0;-0.0} s' -f $d })
    } else { $res.bien++ }
}
$cache | ConvertTo-Json -Depth 3 -Compress | Set-Content $cacheFile -Encoding utf8
$plan | Export-Clixml "$dir\letras-plan.xml"
"Revisadas: $($archivos.Count) | " + (($res.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ' | ')
"--- a corregir:"; $corregidas
"--- sin letra disponible (primeras 40):"; $sinLetra | Select-Object -First 40

if ($Aplicar) {
    $bien = 0; $mal = @(); $tmp = Join-Path $env:TEMP 'letra.lrc'
    function Etiquetas($f) { & $mf --export-tags-to=- $f | Where-Object { $_ -match '^[A-Za-z0-9_ ]+=' -and $_ -notmatch '^LYRICS=' } }
    foreach ($x in $plan) {
        $p = $x.f
        $antes = Etiquetas $p; $h = HuellaAudio $p
        [IO.File]::WriteAllText($tmp, $x.lrc, (New-Object Text.UTF8Encoding $false))
        & $mf --preserve-modtime --remove-tag=LYRICS "--set-tag-from-file=LYRICS=$tmp" $p
        $lyr = (& $mf --show-tag=LYRICS $p) -join "`n"
        if ($LASTEXITCODE -eq 0 -and $h -eq (HuellaAudio $p) -and $lyr -match '\[\d+:\d+' -and -not (Compare-Object @($antes) @(Etiquetas $p))) { $bien++ } else { $mal += $p }
    }
    "Letras escritas: $bien | con problemas: $($mal.Count)"; $mal
}
