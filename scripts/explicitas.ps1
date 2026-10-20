# Versiones EXPLICITAS: busca canciones censuradas/"clean" (en tus playlists, tus Me gusta y tu disco) que tienen
# version explicita en Spotify (mismo artista, mismo titulo, duracion +-10 s, sin en vivo/remix si la original no lo es).
# Sin -Aplicar: solo reporte (reportes-musica\explicitas.md). Con -Aplicar:
#   - en cada playlist tuya y en Me gusta: quita la censurada y pone la explicita (si ya estaba, solo quita la censurada)
#   - las del disco van a la playlist "Descargar Explicitas" (al bajarlas, acomodar-descargas reemplaza la vieja)
# -Excluir: playlists que no se tocan (patron -like; p. ej. las de otra persona).
# -Apartar: (usa el ultimo reporte, sin Spotify) mueve del disco las censuradas que tienen version explicita a
#   <Raiz>\_censuradas\Artista\Album\ (con su .lrc) y borra las carpetas que queden vacias. Para borrarlas cuando
#   ya bajaste las explicitas de la playlist "Descargar Explicitas".
param([switch]$Aplicar, [string]$Raiz = "", [string[]]$Excluir = @('Descargar*'), [switch]$Apartar, [int]$MaxBusquedas = 400)  # -MaxBusquedas: tope de busquedas en Spotify por vez (~700/dia la bloquea 24 h)
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
if (-not $Raiz) { $cfg = Join-Path $dir 'config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
if ($Apartar) {
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    $dest = Join-Path $Raiz '_censuradas'; $movidas = @()
    foreach ($p in @(Import-Clixml "$dir\explicitas-plan.xml") | Where-Object { $_.archivo -and (Test-Path -LiteralPath $_.archivo) }) {
        $rel = $p.archivo.Substring($Raiz.TrimEnd('\').Length + 1); $d = Join-Path $dest (Split-Path $rel)
        New-Item -ItemType Directory -Force $d | Out-Null
        Move-Item -LiteralPath $p.archivo $d
        $lrc = [IO.Path]::ChangeExtension($p.archivo, '.lrc'); if (Test-Path -LiteralPath $lrc) { Move-Item -LiteralPath $lrc $d }
        $movidas += $rel
    }
    # carpetas vacias (de abajo hacia arriba)
    $vacias = @(Get-ChildItem -LiteralPath $Raiz -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending | Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } | ForEach-Object { Remove-Item -LiteralPath $_.FullName; $_.Name })
    "Apartadas en _censuradas: $($movidas.Count) | carpetas vacias borradas: $($vacias.Count)"; $movidas
    return
}
. "$PSScriptRoot\progreso.ps1"
. "$PSScriptRoot\spotify-auth.ps1" -Scopes "playlist-read-private playlist-modify-private playlist-modify-public user-library-read user-library-modify"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$mf = Get-Content "$dir\metaflac-path.txt"; $ffp = Join-Path (Split-Path (Get-Content "$dir\ffmpeg-path.txt")) 'ffprobe.exe'
function Norm($s) { ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^\p{L}\p{N}]', '' }
function Base($s) { Norm (($s -replace '\((clean|edited|radio edit|explicit|censored|sucia|limpia)[^)]*\)|\[(clean|edited|explicit)[^\]]*\]', '' -split ' - (Clean|Radio Edit|Edit|Explicit)')[0]) }
$vivo = '(?i)\b(live|en vivo|remix|acoustic|ac[uú]stico|sped up|slowed|instrumental|karaoke)\b'
function Leer($id) { $out = @(); $next = "/playlists/$id/items?limit=100"; while ($next) { $pg = Api Get $next; foreach ($i in $pg.items) { $x = if ($i.item) { $i.item } else { $i.track }; if ($x -and $x.uri -like 'spotify:track:*') { $out += $x } }; $next = $pg.next }; $out }

# 1) todo lo guardado: playlists propias + Me gusta + disco
$me = (Api Get "/me").id
$pls = @((Api Get "/me/playlists?limit=50").items | Where-Object { $_.owner.id -eq $me } | Where-Object { $n = $_.name; -not ($Excluir | Where-Object { $n -like $_ }) })
$donde = @{}; $pista = @{}
function Anota($t, $lugar) { $pista[$t.uri] = $t; if (-not $donde[$t.uri]) { $donde[$t.uri] = New-Object Collections.Generic.List[string] }; if (-not $donde[$t.uri].Contains($lugar)) { $donde[$t.uri].Add($lugar) } }
foreach ($p in $pls) { foreach ($t in Leer $p.id) { Anota $t "playlist:$($p.name)" } }
$next = "/me/tracks?limit=50"; while ($next) { $pg = Api Get $next; foreach ($i in $pg.items) { if ($i.track) { Anota $i.track 'likes' } }; $next = $pg.next }
$archivo = @{}
foreach ($f in Get-ChildItem -LiteralPath $Raiz -Recurse -File | Where-Object { $_.Extension -in '.flac', '.m4a', '.mp3' }) {
    $c = if ($f.Extension -eq '.flac') { & $mf --no-utf8-convert --show-tag=COMMENT $f.FullName } else { & $ffp -v error -show_entries format_tags=comment -of default=nw=1:nk=1 $f.FullName }
    if ("$c" -match 'open\.spotify\.com/track/([A-Za-z0-9]{22})') { $u = "spotify:track:$($Matches[1])"; $archivo[$u] = $f.FullName
        if (-not $pista[$u]) { try { Anota (Api Get "/tracks/$($Matches[1])") 'disco' } catch { } } else { Anota $pista[$u] 'disco' } }
}

# 2) para cada no explicita, buscar su version explicita (cache: no repetir busquedas)
$cacheF = "$dir\explicitas-cache.json"; $cache = @{}; if (Test-Path $cacheF) { (Get-Content $cacheF -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } }
$limpias = @($pista.Values | Where-Object { -not $_.explicit }); $n = 0; $pares = @(); $busq = 0; $pendientes = 0
$itunes = @{}; if (Test-Path "$dir\itunes-explicitas.json") { (Get-Content "$dir\itunes-explicitas.json" -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $itunes[$_.Name] = $_.Value } }
foreach ($t in $limpias) {
    $n++; Progreso 'explicitas' $n $limpias.Count @{ con_explicita = $pares.Count } "$($t.artists[0].name) - $($t.name)"
    # pre-filtro iTunes (explicitas-prefiltro.ps1): si Apple dice que NO hay version explicita, no se gasta busqueda en Spotify
    if (-not $cache.ContainsKey($t.uri) -and $itunes[$t.uri] -eq 'no') { $cache[$t.uri] = '' }
    if (-not $cache.ContainsKey($t.uri) -and $busq -ge $MaxBusquedas) { $pendientes++; continue }
    if (-not $cache.ContainsKey($t.uri)) {
        $busq++
        $q = [uri]::EscapeDataString("track:$(($t.name -replace ' - .*$|\(.*?\)', '').Trim()) artist:$($t.artists[0].name)")
        $e = $null
        try { $res = (Api Get "/search?type=track&limit=10&q=$q").tracks.items }
        catch {  # si Spotify limita, se PARA y se guarda lo hecho; nunca se anota "no tiene" por un error
            $cache | ConvertTo-Json -Depth 3 -Compress | Set-Content $cacheF -Encoding utf8
            if ("$_" -match 'Limite de Spotify') { throw "$_ (revisadas hasta ahora: $n de $($limpias.Count); se puede seguir despues sin repetir)" }
            continue
        }
        $e = @($res | Where-Object { $_ -and $_.explicit -and (Norm $_.artists[0].name) -eq (Norm $t.artists[0].name) -and (Base $_.name) -eq (Base $t.name) -and [Math]::Abs($_.duration_ms - $t.duration_ms) -le 10000 -and (("$($_.name) $($_.album.name)" -match $vivo) -eq ("$($t.name) $($t.album.name)" -match $vivo)) }) | Sort-Object { [Math]::Abs($_.duration_ms - $t.duration_ms) } | Select-Object -First 1
        $cache[$t.uri] = if ($e) { [pscustomobject]@{ u = $e.uri; n = "$($e.artists[0].name) - $($e.name)"; al = $e.album.name } } else { '' }
        if ($n % 25 -eq 0) { $cache | ConvertTo-Json -Depth 3 -Compress | Set-Content $cacheF -Encoding utf8 }
        Start-Sleep -Milliseconds 1200  # ~50 busquedas/min: a ~100/min Spotify bloqueo la app ~20 horas
    }
    $x = $cache[$t.uri]
    if ($x -and $x.u) { $pares += [pscustomobject]@{ limpia = $t.uri; explicita = $x.u; nombre = "$($t.artists[0].name) - $($t.name)"; albumLimpio = $t.album.name; albumExplicito = $x.al; donde = ($donde[$t.uri] -join ', '); archivo = $archivo[$t.uri] } }
}
$cache | ConvertTo-Json -Depth 3 -Compress | Set-Content $cacheF -Encoding utf8
$pares | Export-Clixml "$dir\explicitas-plan.xml"
$md = @("# Canciones censuradas con version explicita ($($pares.Count))", '', '| # | Cancion | Album censurado | Album explicito | Donde |', '|---|---|---|---|---|')
$i = 0; foreach ($p in $pares) { $i++; $md += "| $i | $($p.nombre) | $($p.albumLimpio) | $($p.albumExplicito) | $(($p.donde -replace 'playlist:', '')) |" }
$md | Set-Content "$dir\explicitas.md" -Encoding utf8
if ($pendientes) { "PAUSA: quedan $pendientes por buscar en Spotify (tope de $MaxBusquedas por vez). Correr de nuevo otro dia: no repite lo ya buscado." }
"Revisadas: $($pista.Count) (no explicitas: $($limpias.Count)) | con version explicita disponible: $($pares.Count) | reporte: reportes-musica\explicitas.md"
$pares | ForEach-Object { "$($_.nombre)  [$($_.albumLimpio) -> $($_.albumExplicito)]  en: $($_.donde -replace 'playlist:', '')" }
if (-not $Aplicar) { return }

# 3) aplicar
foreach ($p in $pls) {
    $aqui = @($pares | Where-Object { $donde[$_.limpia] -contains "playlist:$($p.name)" }); if (-not $aqui) { continue }
    $ya = @{}; foreach ($t in Leer $p.id) { $ya[$t.uri] = 1 }
    $null = Api Delete "/playlists/$($p.id)/items" @{ items = @($aqui | ForEach-Object { @{ uri = $_.limpia } }) }
    $add = @($aqui | Where-Object { -not $ya[$_.explicita] } | ForEach-Object { $_.explicita } | Select-Object -Unique)
    for ($k = 0; $k -lt $add.Count; $k += 100) { $null = Api Post "/playlists/$($p.id)/items" @{ uris = @($add[$k..([Math]::Min($k + 99, $add.Count - 1))]) } }
    "$($p.name): $($aqui.Count) censuradas cambiadas por la explicita"
}
$lk = @($pares | Where-Object { $donde[$_.limpia] -contains 'likes' })
if ($lk) {
    for ($k = 0; $k -lt $lk.Count; $k += 40) { $g = $lk[$k..([Math]::Min($k + 39, $lk.Count - 1))]
        $null = Invoke-RestMethod -Method Put -Uri "https://api.spotify.com/v1/me/library?uris=$([uri]::EscapeDataString(($g.explicita -join ',')))" -Headers $h
        $null = Invoke-RestMethod -Method Delete -Uri "https://api.spotify.com/v1/me/library?uris=$([uri]::EscapeDataString(($g.limpia -join ',')))" -Headers $h }
    "Me gusta: $($lk.Count) cambiadas por la explicita"
}
$dl = @($pares | Where-Object archivo | ForEach-Object { $_.explicita } | Select-Object -Unique)
if ($dl) {
    $pl = (Api Get "/me/playlists?limit=50").items | Where-Object name -eq 'Descargar Explicitas' | Select-Object -First 1
    if (-not $pl) { $pl = Api Post "/me/playlists" @{ name = 'Descargar Explicitas'; public = $false; description = 'Versiones explicitas para reemplazar las censuradas del disco' } }
    for ($k = 0; $k -lt $dl.Count; $k += 100) { $null = Api Post "/playlists/$($pl.id)/items" @{ uris = @($dl[$k..([Math]::Min($k + 99, $dl.Count - 1))]) } }
    "Para descargar (estan censuradas en tu disco): $($dl.Count) -> playlist 'Descargar Explicitas': $($pl.external_urls.spotify)"
}
