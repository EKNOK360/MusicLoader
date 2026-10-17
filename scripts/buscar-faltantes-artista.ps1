# Compara la discografia de un artista en Spotify con tus archivos de SpotiFLAC.
# Ignora versiones (acustica, en vivo, remix...) y repetidas (single que luego salio en album).
# Las que faltan se agregan a la playlist y se listan en el Escritorio.
param([string]$Artista = "Morat", [string]$Raiz = "D:\SpotiFLAC", [string]$Nombre = "Por recuperar")
. "$PSScriptRoot\spotify-auth.ps1" -Scopes "playlist-read-private playlist-modify-private playlist-modify-public"

$versiones = 'ac[uú]stic|acoustic|en vivo|live|remix|versi[oó]n|version|sped|slowed|instrumental|demo|karaoke|edit|unplugged|session|directo|soundscape|endel'
function Base($s) {
    # quita (...), [...] y " - ..." y deja solo letras/numeros sin acentos
    $s = ($s -replace '\(.*?\)|\[.*?\]', '' -split ' - ')[0]
    $s = $s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    ($s.ToLower() -replace '[^a-z0-9]', '')
}
function EsVersion($s) { $extra = ([regex]::Matches($s, '\(.*?\)|\[.*?\]').Value -join ' ') + ' ' + (($s -split ' - ', 2)[1]); $extra -match $versiones }

# 1. Canciones que ya tienes (archivos "Artista - Titulo" en cualquier carpeta)
$tengo = New-Object 'Collections.Generic.HashSet[string]'
Get-ChildItem $Raiz -Recurse -File | Where-Object { '.flac', '.m4a', '.mp3' -contains $_.Extension.ToLower() -and $_.BaseName -match [regex]::Escape($Artista) } |
    ForEach-Object { $t = ($_.BaseName -split ' - ', 2)[-1]; [void]$tengo.Add((Base $t)) }

# 2. Discografia en Spotify (albumes primero, asi la version de album gana sobre el single)
$art = (Api Get "/search?type=artist&limit=5&q=$([uri]::EscapeDataString($Artista))").artists.items | Where-Object { $_.name -eq $Artista } | Select-Object -First 1
if (-not $art) { throw "No encontre al artista $Artista en Spotify." }
$discos = @(); $next = "/artists/$($art.id)/albums?include_groups=album,single&limit=10"
while ($next) { $pg = Api Get $next; $discos += @($pg.items); $next = $pg.next }
$discos = $discos | Where-Object { -not ($_.name -match $versiones) } | Sort-Object @{e = { $_.album_type -ne 'album' } }, release_date

$vistas = @{}; $faltan = @()
foreach ($d in $discos) {
    $next = "/albums/$($d.id)/tracks?limit=50"
    while ($next) {
        $pg = Api Get $next; $next = $pg.next
        foreach ($t in $pg.items) {
            if (-not ($t.artists.id -contains $art.id) -or (EsVersion $t.name)) { continue }
            $b = Base $t.name
            if ($vistas.ContainsKey($b)) { continue }
            $vistas[$b] = 1
            if (-not $tengo.Contains($b)) { $faltan += [pscustomobject]@{ Cancion = $t.name; Disco = $d.name; Uri = $t.uri } }
        }
    }
}

# 3. Agregar a la playlist las que no esten ya
$pl = Api Get "/me/playlists?limit=50"
$plId = ($pl.items | Where-Object { $_.name -eq $Nombre } | Select-Object -First 1).id
if (-not $plId) { throw "No encontre la playlist '$Nombre'." }
$ya = New-Object 'Collections.Generic.HashSet[string]'
$next = "/playlists/$plId/items?limit=100"
while ($next) { $pg = Api Get $next; $pg.items | ForEach-Object { $x = if ($_.item) { $_.item } else { $_.track }; if ($x) { [void]$ya.Add((Base $x.name)) } }; $next = $pg.next }
$nuevas = @($faltan | Where-Object { -not $ya.Contains((Base $_.Cancion)) })
for ($i = 0; $i -lt $nuevas.Count; $i += 100) {
    $null = Api Post "/playlists/$plId/items" @{ uris = @($nuevas[$i..([Math]::Min($i + 99, $nuevas.Count - 1))].Uri) }
}

$lista = $faltan | ForEach-Object { "$($_.Cancion)  ($($_.Disco))" + $(if ($ya.Contains((Base $_.Cancion))) { "  [ya estaba en la playlist]" }) }
$lista | Set-Content "$desk\faltantes-$Artista.txt" -Encoding utf8
"Tienes $($tengo.Count) canciones de $Artista. Discografia sin repetidas: $($vistas.Count)."
"Te faltan $($faltan.Count). Agregadas a '$Nombre': $($nuevas.Count)`n"
$lista
