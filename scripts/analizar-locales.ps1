# Solo lectura: busca en Spotify las canciones del disco que no esten en ninguna playlist.
# Resultado: reportes-musica\locales.json (y playlists.json si no se usa -SinExportar).
# Guarda lo que ya busco en busquedas-cache.json para poder continuar si Spotify lo frena.
param([string]$Raiz = "D:\SpotiFLAC", [string]$Excluir = "Por recuperar", [switch]$SinExportar)
. "$PSScriptRoot\spotify-auth.ps1" -Scopes "playlist-read-private playlist-read-collaborative user-library-read"
function Base($s) {
    $s = ($s -replace '\(.*?\)|\[.*?\]', '' -split ' - ')[0]
    $s = $s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    ($s.ToLower() -replace '[^a-z0-9]', '')
}
function Norm($s) { if (-not $s) { return '' }; ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^a-z0-9]', '' }

# 1. Playlists (exportar de nuevo o reusar la exportacion anterior)
if ($SinExportar) {
    $export = @(Get-Content "$desk\playlists.json" -Raw -Encoding utf8 | ConvertFrom-Json) | ForEach-Object { $_ }
} else {
    $me = Api Get "/me"
    $pls = @(); $next = "/me/playlists?limit=50"
    while ($next) { $pg = Api Get $next; $pls += @($pg.items); $next = $pg.next }
    $export = foreach ($pl in $pls | Where-Object { $_.owner.id -eq $me.id }) {
        $tr = @(); $next = "/playlists/$($pl.id)/items?limit=100"
        while ($next) { $pg = Api Get $next; $pg.items | ForEach-Object { $x = if ($_.item) { $_.item } else { $_.track }; if ($x -and $x.uri) { $tr += [pscustomobject]@{ a = ($x.artists.name -join ', '); n = $x.name; al = $x.album.name; u = $x.uri } } }; $next = $pg.next }
        [pscustomobject]@{ nombre = $pl.name; id = $pl.id; canciones = $tr }
    }
    $export | ConvertTo-Json -Depth 5 -Compress | Set-Content "$desk\playlists.json" -Encoding utf8
}
# Likes (canciones que te gustan)
$likes = @(); $next = "/me/tracks?limit=50"
while ($next) { $pg = Api Get $next; $pg.items | ForEach-Object { if ($_.track.uri) { $likes += [pscustomobject]@{ a = ($_.track.artists.name -join ', '); n = $_.track.name; al = $_.track.album.name; u = $_.track.uri } } }; $next = $pg.next; Start-Sleep -Milliseconds 200 }
$likes | ConvertTo-Json -Depth 3 -Compress | Set-Content "$desk\likes.json" -Encoding utf8
Write-Host "Likes: $($likes.Count)"
$conocidas = @{}
foreach ($p in $export) { foreach ($t in $p.canciones) { foreach ($a in $t.a -split ', ') { $conocidas["$(Norm $a)|$(Base $t.n)"] = $t } } }

# 2. Archivos del disco
$cacheFile = "$desk\busquedas-cache.json"
$cache = @{}
if (Test-Path $cacheFile) { (Get-Content $cacheFile -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } }
function GuardarCache { $cache | ConvertTo-Json -Depth 3 -Compress | Set-Content $cacheFile -Encoding utf8 }

$src = Join-Path $Raiz $Excluir
$archivos = @(Get-ChildItem $Raiz -Recurse -File | Where-Object { '.flac', '.m4a', '.mp3' -contains $_.Extension.ToLower() -and -not $_.FullName.StartsWith($src) -and $_.BaseName -like '* - *' })
$res = @(); $vistos = @{}; $buscadas = 0; $sinMatch = 0; $i = 0
foreach ($f in $archivos) {
    $i++
    if ($i % 100 -eq 0) { Write-Host "Avance: $i de $($archivos.Count) archivos ($buscadas buscadas en Spotify) $(Get-Date -Format HH:mm)"; GuardarCache }
    $p = $f.BaseName -split ' - ', 2
    $arts = $p[0] -split ',\s*'
    $clave = "$(Norm $arts[0])|$(Base $p[1])"
    if ($vistos.ContainsKey($clave)) { continue }
    $vistos[$clave] = 1
    $t = $null
    foreach ($a in $arts) { $k = "$(Norm $a)|$(Base $p[1])"; if ($conocidas.ContainsKey($k)) { $t = $conocidas[$k]; break } }
    if (-not $t -and $cache.ContainsKey($clave)) {
        $t = $cache[$clave]
        if (-not $t.u) { $sinMatch++; $res += [pscustomobject]@{ a = $p[0]; n = $p[1]; al = ''; u = '' }; continue }
    }
    if (-not $t) {
        $buscadas++; Start-Sleep -Milliseconds 300
        try {
            $q = [uri]::EscapeDataString("$($p[1]) $($arts[0])")
            $r = @((Api Get "/search?type=track&limit=10&q=$q").tracks.items | Where-Object { $_ -and ($_.artists.name | Where-Object { (Norm $_) -eq (Norm $arts[0]) }) })
        } catch { GuardarCache; throw }
        $x = $r | Where-Object { (Norm $_.name) -eq (Norm $p[1]) } | Select-Object -First 1
        if (-not $x) { $x = $r | Where-Object { (Base $_.name) -eq (Base $p[1]) } | Select-Object -First 1 }
        if ($x) { $t = [pscustomobject]@{ a = ($x.artists.name -join ', '); n = $x.name; al = $x.album.name; u = $x.uri } }
        $cache[$clave] = if ($t) { $t } else { [pscustomobject]@{ u = '' } }
    }
    if ($t) { $res += $t } else { $sinMatch++; $res += [pscustomobject]@{ a = $p[0]; n = $p[1]; al = ''; u = '' } }
}
GuardarCache
$res | ConvertTo-Json -Depth 3 -Compress | Set-Content "$desk\locales.json" -Encoding utf8
"Archivos: $($archivos.Count). Canciones distintas: $($res.Count). Buscadas en Spotify: $buscadas. Sin encontrar: $sinMatch"
