# Solo lectura: guarda el contenido de todas tus playlists propias en reportes-musica\playlists.json
. "$PSScriptRoot\spotify-auth.ps1" -Scopes "playlist-read-private playlist-read-collaborative"
$me = Api Get "/me"
$pls = @(); $next = "/me/playlists?limit=50"
while ($next) { $pg = Api Get $next; $pls += @($pg.items); $next = $pg.next }
$out = foreach ($pl in $pls | Where-Object { $_.owner.id -eq $me.id }) {
    $tr = @(); $next = "/playlists/$($pl.id)/items?limit=100"
    while ($next) { $pg = Api Get $next; $pg.items | ForEach-Object { $x = if ($_.item) { $_.item } else { $_.track }; if ($x -and $x.uri) { $tr += [pscustomobject]@{ a = ($x.artists.name -join ', '); n = $x.name; al = $x.album.name; u = $x.uri } } }; $next = $pg.next }
    [pscustomobject]@{ nombre = $pl.name; id = $pl.id; canciones = $tr }
    "$($pl.name): $($tr.Count)" | Write-Host
}
$out | ConvertTo-Json -Depth 5 -Compress | Set-Content "$desk\playlists.json" -Encoding utf8
