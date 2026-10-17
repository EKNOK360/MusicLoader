# Crea una playlist privada en Spotify con los albumes de carpetas-vacias.txt (Escritorio).
# Login oficial de Spotify (PKCE): no usa contrasena ni Client Secret.
param([string]$Nombre = "Por recuperar")
. "$PSScriptRoot\spotify-auth.ps1"

# 2. Buscar cada album y juntar sus canciones
$items = Get-Content "$desk\carpetas-vacias.txt" -Encoding utf8 | Where-Object { $_ -like '*\*' } |
    ForEach-Object { $p = $_ -split '\\'; [pscustomobject]@{ Artista = $p[0]; Album = $p[-1] } } | Sort-Object Artista, Album -Unique
$uris = New-Object Collections.Generic.List[string]
$reporte = @()
foreach ($it in $items) {
    try {
        $q = [uri]::EscapeDataString("$($it.Album) $($it.Artista)")
        $found = @((Api Get "/search?type=album&limit=5&q=$q").albums.items | Where-Object { $_ })
        $pick = $found | Where-Object { ($_.artists.name -join ' ') -match [regex]::Escape($it.Artista) } | Select-Object -First 1
        if (-not $pick) { $pick = $found | Select-Object -First 1 }
        if (-not $pick) { $reporte += "NO ENCONTRADO  $($it.Artista) - $($it.Album)"; continue }
        $next = "/albums/$($pick.id)/tracks?limit=50"
        while ($next) { $pg = Api Get $next; $pg.items | ForEach-Object { $uris.Add($_.uri) }; $next = $pg.next }
        $reporte += "OK  $($it.Artista) - $($it.Album)  =>  $($pick.name) ($($pick.artists[0].name))"
    } catch { $reporte += "ERROR  $($it.Artista) - $($it.Album): $($_.Exception.Message)" }
}

# 3. Crear la playlist y agregar canciones (de 100 en 100)
$pl = Api Post "/me/playlists" @{ name = $Nombre; public = $false; description = "Albumes que se borraron de SpotiFLAC" }
$todas = @($uris | Select-Object -Unique)
for ($i = 0; $i -lt $todas.Count; $i += 100) {
    $chunk = @($todas[$i..([Math]::Min($i + 99, $todas.Count - 1))])
    try { $null = Api Post "/playlists/$($pl.id)/items" @{ uris = $chunk } }
    catch { $null = Api Post "/playlists/$($pl.id)/tracks" @{ uris = $chunk } }  # endpoint antiguo
}

$reporte | Set-Content "$desk\playlist-reporte.txt" -Encoding utf8
$reporte
"`nPlaylist '$Nombre' creada con $($todas.Count) canciones: $($pl.external_urls.spotify)"
