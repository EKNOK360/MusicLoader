# Para cada artista que ya esta en la playlist, busca sus canciones descargadas en SpotiFLAC
# y las agrega a la playlist (sin repetir). Asi la playlist queda con TODO lo de esos artistas.
param([string]$Nombre = "Por recuperar", [string]$Raiz = "D:\SpotiFLAC")
. "$PSScriptRoot\spotify-auth.ps1" -Scopes "playlist-read-private playlist-modify-private playlist-modify-public"

$versiones = 'ac[uú]stic|acoustic|en vivo|live|remix|versi[oó]n|version|sped|slowed|instrumental|demo|karaoke|edit|unplugged|session|directo|soundscape|endel'
function Base($s) {
    $s = ($s -replace '\(.*?\)|\[.*?\]', '' -split ' - ')[0]
    $s = $s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    ($s.ToLower() -replace '[^a-z0-9]', '')
}
function EsVersion($s) { $extra = ([regex]::Matches($s, '\(.*?\)|\[.*?\]').Value -join ' ') + ' ' + (($s -split ' - ', 2)[1]); [bool]($extra -match $versiones) }
function Norm($s) { ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^a-z0-9]', '' }

# 1. Lo que ya esta en la playlist
$plId = ((Api Get "/me/playlists?limit=50").items | Where-Object { $_.name -eq $Nombre } | Select-Object -First 1).id
if (-not $plId) { throw "No encontre la playlist '$Nombre'." }
$enPlaylist = @(); $next = "/playlists/$plId/items?limit=100"
while ($next) { $pg = Api Get $next; $pg.items | ForEach-Object { $x = if ($_.item) { $_.item } else { $_.track }; if ($x) { $enPlaylist += $x } }; $next = $pg.next }
$artistas = @($enPlaylist | ForEach-Object { $_.artists[0].name } | Sort-Object -Unique)
$claves = New-Object 'Collections.Generic.HashSet[string]'
foreach ($t in $enPlaylist) { foreach ($a in $t.artists.name) { [void]$claves.Add("$(Norm $a)|$(Base $t.name)|$(EsVersion $t.name)") } }

# 2. Archivos descargados de esos artistas ("Artista1, Artista2 - Titulo")
$artNorm = @{}; $artistas | ForEach-Object { $artNorm[(Norm $_)] = $_ }
$archivos = Get-ChildItem $Raiz -Recurse -File | Where-Object { '.flac', '.m4a', '.mp3' -contains $_.Extension.ToLower() -and $_.BaseName -like '* - *' } | ForEach-Object {
    $partes = $_.BaseName -split ' - ', 2
    $de = @($partes[0] -split ',\s*' | Where-Object { $artNorm.ContainsKey((Norm $_)) })
    if ($de) { [pscustomobject]@{ Artista = $artNorm[(Norm $de[0])]; Titulo = $partes[1]; Ruta = $_.FullName } }
}
"Artistas en la playlist: $($artistas.Count). Archivos descargados de esos artistas: $(@($archivos).Count)"

# 3. Buscar en Spotify los que no estan en la playlist y agregarlos
$ya = @(); $nuevas = @(); $noHalladas = @(); $vistos = @{}
foreach ($f in $archivos) {
    $clave = "$(Norm $f.Artista)|$(Base $f.Titulo)|$(EsVersion $f.Titulo)"
    if ($claves.Contains($clave)) { $ya += "$($f.Artista) - $($f.Titulo)"; continue }
    if ($vistos.ContainsKey($clave)) { continue }
    $vistos[$clave] = 1
    try {
        $q = [uri]::EscapeDataString("$($f.Titulo) $($f.Artista)")
        $res = @((Api Get "/search?type=track&limit=10&q=$q").tracks.items | Where-Object { $_ -and ($_.artists.name | Where-Object { (Norm $_) -eq (Norm $f.Artista) }) })
        $t = $res | Where-Object { (Norm $_.name) -eq (Norm $f.Titulo) } | Select-Object -First 1
        if (-not $t) { $t = $res | Where-Object { (Base $_.name) -eq (Base $f.Titulo) -and (EsVersion $_.name) -eq (EsVersion $f.Titulo) } | Select-Object -First 1 }
        if ($t) { $nuevas += $t; [void]$claves.Add($clave) } else { $noHalladas += "$($f.Artista) - $($f.Titulo)" }
    } catch { $noHalladas += "$($f.Artista) - $($f.Titulo)  (error: $($_.Exception.Message))" }
}
$uris = @($nuevas.uri | Select-Object -Unique)
for ($i = 0; $i -lt $uris.Count; $i += 100) {
    $null = Api Post "/playlists/$plId/items" @{ uris = @($uris[$i..([Math]::Min($i + 99, $uris.Count - 1))]) }
}

$rep = @("YA DESCARGADAS Y YA EN LA PLAYLIST ($($ya.Count)):") + ($ya | Sort-Object) + "" +
    "DESCARGADAS Y AGREGADAS AHORA ($($uris.Count)):" + ($nuevas | ForEach-Object { "$($_.artists[0].name) - $($_.name)" } | Sort-Object -Unique) + "" +
    "DESCARGADAS PERO NO ENCONTRADAS EN SPOTIFY ($($noHalladas.Count)):" + ($noHalladas | Sort-Object)
$rep | Set-Content "$desk\descargadas-en-playlist.txt" -Encoding utf8
$rep
