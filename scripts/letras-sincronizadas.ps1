# Letras SINCRONIZADAS (LRC) para los FLAC. Fuentes: LRCLIB y NetEase Cloud Music (ver lrc-fuentes.ps1).
#  - Sin letra sincronizada  -> se agrega la de LRCLIB si es valida.
#  - Con letra sincronizada  -> se compara linea por linea con LRCLIB; si va desfasada (> 0.75 s de mediana)
#                               o tiene tiempos despues del final de la cancion, se reemplaza por la de LRCLIB.
#  - Instrumentales (LRCLIB instrumental=true) -> no se tocan.
# Una letra de LRCLIB es valida si: es sincronizada, su duracion coincide con la del archivo (+-2 s; se elige la
# mas parecida), el ultimo tiempo no pasa el final y tiene >= 5 lineas con tiempo.
# Sin -Aplicar: solo busca (guarda cache) y muestra el plan. Con -Aplicar: escribe SOLO la etiqueta LYRICS y
# verifica que los bytes del audio y las demas etiquetas queden identicos. -Archivo x.flac: solo ese archivo.
param([switch]$Aplicar, [string]$Archivo = "", [string]$Raiz = "", [switch]$ConLrc, [ValidateSet('', 'moderno', 'viejito')][string]$Reproductor = '')  # -Raiz carpeta: solo esa carpeta
# -Reproductor: codificacion de los .lrc. viejito = ANSI (Windows-1252; los reproductores sencillos muestran "dÃ­a" con UTF-8),
#   moderno = UTF-8. Sin indicarlo: los .lrc de MP3 van en ANSI y los de FLAC/M4A en UTF-8.
# -ConLrc: ademas deja un .lrc al lado de CADA cancion con letra sincronizada (reproductores sencillos solo leen el .lrc)
if (-not $Raiz) { $cfg = Join-Path $env:USERPROFILE 'reportes-musica\config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\progreso.ps1"
. "$PSScriptRoot\lrc-fuentes.ps1"
. "$PSScriptRoot\lrc-ansi.ps1"
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
$ffm = Get-Content "$dir\ffmpeg-path.txt"; $ffp = Join-Path (Split-Path $ffm) 'ffprobe.exe'
function EsM4a($f) { $f -like '*.m4a' -or $f -like '*.mp3' }  # M4A/MP3: etiquetas con mutagen (letra-tag.py), medidas con ffprobe
function Tag($f, $k) {
    if (EsM4a $f) { return (& $ffp -v error -show_entries "format_tags=$($k.ToLower())" -of default=nw=1:nk=1 $f | Select-Object -First 1) }
    (& $mf --no-utf8-convert "--show-tag=$k" $f | Select-Object -First 1) -replace "^$k=", ''
}
function Duracion($f) {
    if (EsM4a $f) { return [double](& $ffp -v error -show_entries format=duration -of default=nw=1:nk=1 $f) }
    [double](& $mf --show-total-samples $f) / [double](& $mf --show-sample-rate $f)
}
function CodLrc($audio) { if ($Reproductor -eq 'viejito') { 'ansi' } elseif ($Reproductor -eq 'moderno') { 'utf8' } elseif ($audio -like '*.mp3') { 'ansi' } else { 'utf8' } }
function LeerLrc($p) {  # detecta como esta guardado un .lrc: BOM UTF-8, UTF-8 valido o ANSI
    $b = [IO.File]::ReadAllBytes($p)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return [Text.Encoding]::UTF8.GetString($b, 3, $b.Length - 3) }
    try { (New-Object Text.UTF8Encoding $false, $true).GetString($b) } catch { [Text.Encoding]::GetEncoding(1252).GetString($b) }
}
function EscribirLrc($audio, $texto) {  # .lrc al lado del audio, en ANSI o UTF-8 segun CodLrc; si no cabe en ANSI (p. ej. japones), UTF-8 con BOM
    $p = [IO.Path]::ChangeExtension($audio, '.lrc')
    if ((CodLrc $audio) -eq 'ansi') {
        $a = TextoAnsi $texto  # lrc-ansi.ps1: quita marcas (е rusa...) y ♪; $null si no cabe en ANSI
        if ($null -ne $a) { [IO.File]::WriteAllBytes($p, $script:Ansi1252.GetBytes($a)) } else { [IO.File]::WriteAllText($p, $texto, (New-Object Text.UTF8Encoding $true)) }
        return
    }
    [IO.File]::WriteAllText($p, $texto, (New-Object Text.UTF8Encoding $false))
}
function LeerLetra($f) {  # M4A: con mutagen (letra-tag.py); FLAC: etiqueta LYRICS
    if (EsM4a $f) {
        $l = (& $py "$PSScriptRoot\letra-tag.py" leer $f) -join "`n"
        $lrc = [IO.Path]::ChangeExtension($f, '.lrc')  # MP3: muchos reproductores usan el .lrc de al lado
        if ($l -notmatch '\[\d+:\d+' -and (Test-Path -LiteralPath $lrc)) { $l = LeerLrc $lrc }
        return $l
    }
    ((& $mf --no-utf8-convert --show-tag=LYRICS $f) -join "`n") -replace '^LYRICS=', ''
}
function Norm($s) { ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^\p{L}\p{N}]', '' }
function Lineas($lrc) {  # -> lista de @{t=segundos; x=texto normalizado}
    foreach ($m in [regex]::Matches("$lrc", '(?m)^\[(\d+):(\d+(?:\.\d+)?)\](.*)$')) {
        [pscustomobject]@{ t = [int]$m.Groups[1].Value * 60 + [double]$m.Groups[2].Value; x = (Norm $m.Groups[3].Value) }
    }
}
function Buscar($art, $tit, $alb, $dur) {  # LRCLIB y, si no hay, NetEase (ver lrc-fuentes.ps1). Cache por cancion.
    $k = "$art|$tit|$([int]$dur)"
    if ($cache.ContainsKey($k) -and $cache[$k].v3) { return $cache[$k] }  # v3 = busqueda estricta (mismo artista y titulo)
    $r = BuscarLetra $art $tit $alb $dur
    $v = [pscustomobject]@{ lrc = $r.lrc; fuente = $r.fuente; inst = $r.inst; v3 = $true }
    $cache[$k] = $v; Start-Sleep -Milliseconds 250
    $v
}function Valida($lrc, $dur) { $l = @(Lineas $lrc); $l.Count -ge 5 -and $l[-1].t -le $dur + 1 }
function Desfase($vieja, $nueva) {  # mediana de (tiempo viejo - tiempo nuevo); cada linea se compara con su repeticion MAS CERCANA (coros)
    $n = @{}; foreach ($l in Lineas $nueva) { if ($l.x.Length -ge 6) { if (-not $n.ContainsKey($l.x)) { $n[$l.x] = New-Object Collections.Generic.List[double] }; $n[$l.x].Add($l.t) } }
    $d = @(foreach ($l in Lineas $vieja) { if ($n.ContainsKey($l.x)) { $tv = $l.t; ($n[$l.x] | Sort-Object { [Math]::Abs($tv - $_) } | Select-Object -First 1 | ForEach-Object { $tv - $_ }) } }) | Sort-Object
    if ($d.Count -lt 5) { return $null }
    $d[[int][Math]::Floor($d.Count / 2)]
}
function Palabras($a) { $h = @{}; foreach ($w in ((($a -replace '\[[^\]]*\]', '').Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -split '[^\p{L}\p{N}]+')) { if ($w.Length -ge 2) { $h[$w] = 1 } }; $h }
function Parecido($a, $b) {  # 0..1: palabras en comun (las dos ya en letras latinas). Medido: misma cancion ~0.76, otra cancion <= 0.11
    $x = Palabras $a; $y = Palabras $b
    $nx = $x.Keys.Count; $ny = $y.Keys.Count  # .Keys.Count: si la letra trae la palabra "count", $x.Count devolveria ESE valor
    if (-not $nx -or -not $ny) { return 0 }
    $c = @($x.Keys | Where-Object { $y.ContainsKey($_) }).Count
    $c / ($nx + $ny - $c)
}
$py = if (Test-Path "$dir\python-path.txt") { Get-Content "$dir\python-path.txt" } else { '' }
function NoLatina($s) { "$s" -match '[぀-ヿ㐀-鿿가-힯]' }
function Romanizar($lrc) {  # japones/coreano -> letras latinas (romaji), sin traducir; ver romanizar.py
    if (-not (NoLatina $lrc) -or -not $py) { return $lrc }
    $e = Join-Path $env:TEMP 'rom-in.lrc'; $s = Join-Path $env:TEMP 'rom-out.lrc'
    [IO.File]::WriteAllText($e, $lrc, (New-Object Text.UTF8Encoding $false))
    & $py "$PSScriptRoot\romanizar.py" $e $s
    if ($LASTEXITCODE -ne 0) { return $lrc }
    [IO.File]::ReadAllText($s, [Text.Encoding]::UTF8)
}

$archivos = if ($Archivo) { @(Get-Item -LiteralPath $Archivo) } else { @(Get-ChildItem -LiteralPath $Raiz -Recurse -File | Where-Object { $_.Extension -in '.flac', '.m4a', '.mp3' }) }
$plan = @(); $res = [ordered]@{ agregar = 0; corregir = 0; equivocada = 0; romaji = 0; bien = 0; instrumental = 0; sinLetra = 0; sinComparar = 0 }; $sinLetra = @(); $corregidas = @(); $sinVerificar = @(); $i = 0
foreach ($f in $archivos) {
    $i++; Progreso 'letras-analisis' $i $archivos.Count @{ agregar = $res.agregar; corregir = $res.corregir; equivocadas = $res.equivocada; romaji = $res.romaji; bien = $res.bien; sin_verificar = $res.sinComparar; sin_letra = $res.sinLetra } $f.BaseName; if ($i % 100 -eq 0) { Write-Host "Avance: $i de $($archivos.Count) $(Get-Date -Format HH:mm)"; $cache | ConvertTo-Json -Depth 3 -Compress | Set-Content $cacheFile -Encoding utf8 }
    $actual = LeerLetra $f.FullName
    $tieneSync = $actual -match '(?m)^\[\d+:\d+'
    $art = (Tag $f.FullName 'ARTIST') -split ',\s*|;\s*' | Select-Object -First 1
    $tit = Tag $f.FullName 'TITLE'; $alb = Tag $f.FullName 'ALBUM'; $dur = Duracion $f.FullName
    $r = Buscar $art $tit $alb $dur
    $ok = $r.lrc -and (Valida $r.lrc $dur)
    $cand = if ($ok) { Romanizar $r.lrc } else { '' }
    if (-not $tieneSync) {
        if ($ok) { $plan += [pscustomobject]@{ f = $f.FullName; lrc = $cand; tipo = 'agregar' }; $res.agregar++ }
        elseif ($r.inst) { $res.instrumental++ } else { $res.sinLetra++; $sinLetra += "$art - $tit" }
        continue
    }
    $l = @(Lineas $actual)
    $pasaFinal = $l.Count -and $l[-1].t -gt $dur + 1
    if (-not $ok) {  # no hay fuente de la MISMA cancion para comprobarla
        $tituloEnLetra = (Norm ($actual -replace '\[[^\]]*\]', '')).Contains((Norm ($tit -replace '\(.*?\)|\[.*?\]| - .*$', '')))
        $sinVerificar += [pscustomobject]@{ f = $f.FullName; nombre = "$art - $tit"; dudosa = (-not $tituloEnLetra); spotiflac = ($actual -match '\[by:SpotiFLAC') }
        if (NoLatina $actual) { $plan += [pscustomobject]@{ f = $f.FullName; lrc = (Romanizar $actual); tipo = 'romaji' }; $res.romaji++ }
        if ($pasaFinal) { $corregidas += "SIN ARREGLO (no hay version buena): $art - $tit" }; $res.sinComparar++; continue
    }
    $actualR = Romanizar $actual  # se comparan las dos ya en letras latinas
    $p = Parecido $actualR $cand
    $d = Desfase $actualR $cand
    if ($p -lt 0.3) {
        $plan += [pscustomobject]@{ f = $f.FullName; lrc = $cand; tipo = 'equivocada' }; $res.equivocada++
        $corregidas += "{0} - {1}  (letra de OTRA cancion: parecido {2:P0})" -f $art, $tit, $p
    } elseif ($pasaFinal -or ($null -ne $d -and [Math]::Abs($d) -gt 0.75)) {
        $plan += [pscustomobject]@{ f = $f.FullName; lrc = $cand; tipo = 'corregir' }; $res.corregir++
        $corregidas += "{0} - {1}  ({2})" -f $art, $tit, $(if ($pasaFinal) { 'tiempos pasan del final' } else { 'desfase {0:+0.0;-0.0} s' -f $d })
    } elseif (NoLatina $actual) { $plan += [pscustomobject]@{ f = $f.FullName; lrc = $actualR; tipo = 'romaji' }; $res.romaji++ }
    else { $res.bien++ }
}
$cache | ConvertTo-Json -Depth 3 -Compress | Set-Content $cacheFile -Encoding utf8
$plan | Export-Clixml "$dir\letras-plan.xml"
$sinVerificar | Export-Clixml "$dir\letras-sin-verificar.xml"
"Revisadas: $($archivos.Count) | " + (($res.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ' | ')
"--- a corregir:"; $corregidas
"--- sin letra disponible (primeras 40):"; $sinLetra | Select-Object -First 40
"--- DUDOSAS (sin fuente para comprobar y el titulo no aparece en la letra): $(@($sinVerificar | Where-Object dudosa).Count)"; $sinVerificar | Where-Object dudosa | ForEach-Object { "$($_.nombre)$(if ($_.spotiflac) { '  [puesta por SpotiFLAC]' })" }

if ($Aplicar) {
    $bien = 0; $mal = @(); $tmp = Join-Path $env:TEMP 'letra.lrc'
    function Etiquetas($f) { & $mf --export-tags-to=- $f | Where-Object { $_ -match '^[A-Za-z0-9_ ]+=' -and $_ -notmatch '^LYRICS=' } }
    foreach ($x in $plan) {
        $p = $x.f
        if (EsM4a $p) {  # M4A/MP3: solo la etiqueta de la letra; se verifica que el audio decodificado y las demas etiquetas no cambien
            $md5 = { param($q) (& $ffm -v error -i $q -map 0:a -f md5 - 2>$null) -join '' }
            $tags = { param($q) (& $ffp -v error -show_entries format_tags -of json $q | ConvertFrom-Json).format.tags.PSObject.Properties | Where-Object Name -notmatch 'lyric' | ForEach-Object { "$($_.Name)=$($_.Value)" } }
            $pics = { param($q) @(& $ffp -v error -select_streams v -show_entries stream=index -of csv=p=0 $q).Count }
            $bk = Join-Path $env:TEMP ([IO.Path]::GetFileName($p)); Copy-Item -LiteralPath $p $bk -Force
            $a1 = & $md5 $p; $t1 = & $tags $p; $c1 = & $pics $p; $mt = (Get-Item -LiteralPath $p).LastWriteTime
            [IO.File]::WriteAllText($tmp, $x.lrc, (New-Object Text.UTF8Encoding $false))
            & $py "$PSScriptRoot\letra-tag.py" escribir $p $tmp
            if ($LASTEXITCODE -eq 0 -and $a1 -and $a1 -eq (& $md5 $p) -and -not (Compare-Object @($t1) @(& $tags $p)) -and $c1 -eq (& $pics $p) -and (LeerLetra $p) -match '\[\d+:\d+') {
                (Get-Item -LiteralPath $p).LastWriteTime = $mt; $bien++; Remove-Item $bk
                if ($p -like '*.mp3') { EscribirLrc $p $x.lrc }  # y el .lrc al lado (ANSI por defecto en MP3)
            }
            else { Copy-Item $bk -LiteralPath $p -Force; $mal += $p }
            Progreso 'letras-escribir' ($bien + $mal.Count) $plan.Count @{ escritas = $bien; problemas = $mal.Count } ([IO.Path]::GetFileNameWithoutExtension($p)); continue
        }
        $antes = Etiquetas $p; $h = HuellaAudio $p
        [IO.File]::WriteAllText($tmp, $x.lrc, (New-Object Text.UTF8Encoding $false))
        & $mf --preserve-modtime --remove-tag=LYRICS "--set-tag-from-file=LYRICS=$tmp" $p
        $lyr = (& $mf --show-tag=LYRICS $p) -join "`n"
        if ($LASTEXITCODE -eq 0 -and $h -eq (HuellaAudio $p) -and $lyr -match '\[\d+:\d+' -and -not (Compare-Object @($antes) @(Etiquetas $p))) { $bien++ } else { $mal += $p }; Progreso 'letras-escribir' ($bien + $mal.Count) $plan.Count @{ escritas = $bien; problemas = $mal.Count } ([IO.Path]::GetFileNameWithoutExtension($p))
    }
    "Letras escritas: $bien | con problemas: $($mal.Count)"; $mal
}
if ($ConLrc) {
    $n = 0
    foreach ($f in $archivos) {
        $l = LeerLetra $f.FullName
        if ($l -notmatch '(?m)^\[\d+:\d+') { continue }
        $lrc = [IO.Path]::ChangeExtension($f.FullName, '.lrc')
        if ((Test-Path -LiteralPath $lrc) -and -not $Reproductor -and (LeerLrc $lrc) -eq $l) { continue }  # con -Reproductor se reescribe para dejar la codificacion pedida
        EscribirLrc $f.FullName $l; $n++
    }
    "Archivos .lrc escritos al lado de las canciones: $n"
    "(Para cambiar la codificacion de .lrc que ya existen: convertir-lrc.ps1 -Codificacion ansi|utf8)"
}
