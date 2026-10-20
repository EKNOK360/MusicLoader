# Versiones EXPLICITAS sin usar la API de Spotify (que bloquea ~24 h tras ~700 busquedas al dia).
# Para cada cancion del disco:
#   1) iTunes (Apple Music) o, si no, Deezer dicen si existe una version explicita (mismo artista, titulo y duracion +-10 s).
#   2) song.link convierte ese enlace de Apple al de Spotify.
#   3) Si ese enlace de Spotify es distinto al de tu archivo (etiqueta COMMENT de SpotiFLAC), tu archivo es la version
#      censurada: se imprime "EXPLICITA | Artista - Titulo | link" y se guarda en reportes-musica\explicitas-links.txt.
# Va primero por los generos con mas versiones censuradas (reggaeton, trap, hip-hop, pop...). Se puede cortar y seguir.
param([string]$Raiz = "")
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
if (-not $Raiz) { $cfg = Join-Path $dir 'config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
. "$PSScriptRoot\progreso.ps1"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$mf = Get-Content "$dir\metaflac-path.txt"
function Norm($s) { ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^\p{L}\p{N}]', '' }
function Base($s) { Norm (($s -replace '\((clean|edited|radio edit|explicit|censored|feat[^)]*|with [^)]*)[^)]*\)|\[[^\]]*\]', '' -split ' - ')[0]) }
function Json($url) { $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8; $wc.Headers.Add('User-Agent', 'MusicLoader/1.0'); try { $wc.DownloadString($url) | ConvertFrom-Json } finally { $wc.Dispose() } }
function Explicita($id) {  # $true / $false segun la pagina publica (embed) de Spotify; $null si no se pudo leer
    try { $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8; $wc.Headers.Add('User-Agent', 'Mozilla/5.0'); $h = $wc.DownloadString("https://open.spotify.com/embed/track/$id"); Start-Sleep -Milliseconds 800
        $m = [regex]::Match($h, '"isExplicit":(true|false)'); if ($m.Success) { $m.Groups[1].Value -eq 'true' } else { $null } } catch { $null }
}
function Tag($f, $k) { (& $mf --no-utf8-convert "--show-tag=$k" $f | Select-Object -First 1) -replace "^$k=", '' }

# canciones del disco, primero los generos donde mas hay versiones censuradas
$prio = 'Reggaeton|Latin Trap|Trap|Hip-Hop|Rap|R&B|Dancehall|Phonk|Pop|Electronic|Rock|Metal|Punk|Alternative|Indie|K-Pop|Funk'
$lista = foreach ($f in Get-ChildItem -LiteralPath $Raiz -Recurse -File -Filter *.flac) {
    $g = (& $mf --no-utf8-convert --show-tag=GENRE $f.FullName) -join ' '
    [pscustomobject]@{ f = $f; p = $(if ($g -match "GENRE=($prio)\b") { 0 } elseif ($g -match $prio) { 1 } else { 2 }) }
}
$lista = @($lista | Sort-Object p)
$cf = "$dir\explicitas-sin-spotify.json"; $cache = @{}; if (Test-Path $cf) { (Get-Content $cf -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } }
$out = "$dir\explicitas-links.txt"; $n = 0; $hall = @($cache.Values | Where-Object { $_ -like 'https://*' }).Count
foreach ($x in $lista) {
    $n++; $f = $x.f.FullName
    if ($n % 25 -eq 0) { $cache | ConvertTo-Json -Compress | Set-Content $cf -Encoding utf8 }  # guardar avance (se puede cortar y seguir)
    Progreso 'explicitas-sin-spotify' $n $lista.Count @{ con_explicita = $hall } $x.f.BaseName
    $c = Tag $f 'COMMENT'; if ("$c" -notmatch 'open\.spotify\.com/track/([A-Za-z0-9]{22})') { continue }; $id = $Matches[1]
    if ($cache.ContainsKey($id)) { continue }
    $art = (Tag $f 'ARTIST') -split ',\s*|;\s*' | Select-Object -First 1; $tit = Tag $f 'TITLE'
    $dur = [double](& $mf --show-total-samples $f) / [double](& $mf --show-sample-rate $f)
    try {
        $r = @((Json "https://itunes.apple.com/search?country=US&entity=song&limit=25&term=$([uri]::EscapeDataString("$art $(($tit -replace '\(.*?\)|\[.*?\]| - .*$', '').Trim())"))").results)
    } catch { Start-Sleep -Seconds 60; continue }
    Start-Sleep -Milliseconds 3100
    $e = $r | Where-Object { $_.trackExplicitness -eq 'explicit' -and (Base $_.trackName) -eq (Base $tit) -and ((Norm $_.artistName).Contains((Norm $art)) -or (Norm $art).Contains((Norm $_.artistName))) -and [Math]::Abs($_.trackTimeMillis / 1000 - $dur) -le 10 } | Select-Object -First 1
    $origen = if ($e) { $e.trackViewUrl } else { '' }
    if (-not $origen) {  # Deezer: otro catalogo (sin cuenta, ~50 consultas cada 5 s)
        try { $dz = @((Json "https://api.deezer.com/search?limit=25&q=$([uri]::EscapeDataString("$art $(($tit -replace '\(.*?\)|\[.*?\]| - .*$', '').Trim())"))").data) } catch { $dz = @() }
        $d = $dz | Where-Object { $_.explicit_lyrics -and (Base $_.title) -eq (Base $tit) -and ((Norm $_.artist.name).Contains((Norm $art)) -or (Norm $art).Contains((Norm $_.artist.name))) -and [Math]::Abs($_.duration - $dur) -le 10 } | Select-Object -First 1
        if ($d) { $origen = $d.link }
    }
    if (-not $origen) { $cache[$id] = 'no'; continue }
    # Apple/Deezer -> Spotify con song.link (~10 consultas/min sin clave)
    try { $sl = Json "https://api.song.link/v1-alpha.1/links?userCountry=US&url=$([uri]::EscapeDataString($origen))" } catch { Start-Sleep -Seconds 60; continue }
    Start-Sleep -Milliseconds 6500
    $sp = $sl.linksByPlatform.spotify.url
    if (-not $sp) { $cache[$id] = 'sin-spotify'; continue }
    if ($sp -match "/track/$id") { $cache[$id] = 'ya-explicita'; continue }   # tu archivo YA es la version explicita
    # comprobar en la pagina publica de Spotify (no usa la API): tu archivo debe ser censurado y el link nuevo explicito
    if ((Explicita $id) -ne $false) { $cache[$id] = 'ya-explicita'; continue }
    if ((Explicita ($sp -replace '^.*/track/([A-Za-z0-9]{22}).*$', '$1')) -ne $true) { $cache[$id] = 'link-no-explicito'; continue }
    $cache[$id] = $sp; $hall++
    $linea = "EXPLICITA | $art - $tit | $sp"
    $linea; Add-Content $out -Value $linea -Encoding utf8
    if ($n % 10 -eq 0) { $cache | ConvertTo-Json -Compress | Set-Content $cf -Encoding utf8 }
}
$cache | ConvertTo-Json -Compress | Set-Content $cf -Encoding utf8
"TERMINADO: $hall canciones censuradas con version explicita (lista en reportes-musica\explicitas-links.txt)"
