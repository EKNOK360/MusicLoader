# 1) Quita canciones repetidas de la playlist.  2) Agrega las recomendaciones de recomendaciones.txt
# (formato Genero|Artista|Titulo) que no tengas ya descargadas ni esten en la playlist.
param([string]$Nombre = "Por recuperar", [string]$Raiz = "D:\SpotiFLAC", [string]$Lista = "$PSScriptRoot\recomendaciones.txt", [string]$TambienEn = "", [switch]$Repartir)
. "$PSScriptRoot\spotify-auth.ps1" -Scopes "playlist-read-private playlist-modify-private playlist-modify-public"

function Base($s) {
    $s = ($s -replace '\(.*?\)|\[.*?\]', '' -split ' - ')[0]
    $s = $s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    ($s.ToLower() -replace '[^a-z0-9]', '')
}
function Norm($s) { ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^a-z0-9]', '' }
function MismoArtista($a, $b) { $x = Norm $a; $y = Norm $b; $x -and $y -and ($x.Contains($y) -or $y.Contains($x)) }
function LeerPlaylist($id) {
    $out = @(); $next = "/playlists/$id/items?limit=100"
    while ($next) { $pg = Api Get $next; $pg.items | ForEach-Object { $x = if ($_.item) { $_.item } else { $_.track }; if ($x) { $out += $x } }; $next = $pg.next }
    $out
}

$plId = ((Api Get "/me/playlists?limit=50").items | Where-Object { $_.name -eq $Nombre } | Select-Object -First 1).id
if (-not $plId) { throw "No encontre la playlist '$Nombre'." }

# 1. Repetidas: mismo artista principal + mismo nombre completo
$canciones = @(LeerPlaylist $plId)
$quitar = @(); $reAgregar = @(); $repetidas = @()
foreach ($g in $canciones | Group-Object { "$(Norm $_.artists[0].name)|$(Norm $_.name)" } | Where-Object Count -gt 1) {
    $keep = $g.Group[0].uri
    $quitar += @($g.Group.uri | Where-Object { $_ -ne $keep } | Select-Object -Unique)
    # borrar por uri quita todas las copias; si la que se queda estaba 2 veces, se borra y se vuelve a poner una
    if (@($g.Group.uri | Where-Object { $_ -eq $keep }).Count -gt 1) { $quitar += $keep; $reAgregar += $keep }
    $repetidas += "$($g.Group[0].artists[0].name) - $($g.Group[0].name) (x$($g.Count))"
}
$quitar = @($quitar | Select-Object -Unique)
for ($i = 0; $i -lt $quitar.Count; $i += 100) {
    $null = Api Delete "/playlists/$plId/items" @{ items = @($quitar[$i..([Math]::Min($i + 99, $quitar.Count - 1))] | ForEach-Object { @{ uri = $_ } }) }
}
if ($reAgregar) { $null = Api Post "/playlists/$plId/items" @{ uris = @($reAgregar) } }

# 2. Recomendaciones
$tengo = New-Object 'Collections.Generic.HashSet[string]'
Get-ChildItem $Raiz -Recurse -File | Where-Object { '.flac', '.m4a', '.mp3' -contains $_.Extension.ToLower() -and $_.BaseName -like '* - *' } | ForEach-Object {
    $p = $_.BaseName -split ' - ', 2
    foreach ($a in $p[0] -split ',\s*') { [void]$tengo.Add("$(Norm $a)|$(Base $p[1])") }
}
$enPl = New-Object 'Collections.Generic.HashSet[string]'
foreach ($t in LeerPlaylist $plId) { foreach ($a in $t.artists.name) { [void]$enPl.Add("$(Norm $a)|$(Base $t.name)") } }

$agregadas = @(); $yaTenia = @(); $noHalladas = @()
foreach ($l in Get-Content $Lista -Encoding utf8 | Where-Object { $_ -match '\|' }) {
    $gen, $art, $tit = $l -split '\|', 3
    # "*N" = las N mas populares del artista que no tengas
    if ($tit -match '^\*(\d+)$') {
        $n = [int]$Matches[1]
        try {
            $qa = [uri]::EscapeDataString('artist:"' + $art + '"')
            $res = @((Api Get "/search?type=track&limit=10&q=$qa").tracks.items | Where-Object { $_ -and ($_.artists.name | Where-Object { (Norm $_) -eq (Norm $art) }) })
            $puestas = 0
            foreach ($t in $res) {
                if ($puestas -ge $n) { break }
                $c = "$(Norm $art)|$(Base $t.name)"
                if ($tengo.Contains($c) -or $enPl.Contains($c)) { continue }
                $agregadas += [pscustomobject]@{ Genero = $gen; Texto = "$($t.artists[0].name) - $($t.name)"; Uri = $t.uri }
                [void]$enPl.Add($c); $puestas++
            }
            if (-not $puestas) { $noHalladas += "$art (ninguna nueva)" }
        } catch { $noHalladas += "$art (error: $($_.Exception.Message))" }
        continue
    }
    # "?texto" = busqueda libre (para piezas clasicas con nombres largos); toma el primer resultado del artista
    if ($tit.StartsWith('?')) {
        try {
            $res = @((Api Get "/search?type=track&limit=10&q=$([uri]::EscapeDataString($tit.TrimStart('?') + ' ' + $art))").tracks.items | Where-Object { $_ -and ($_.artists.name | Where-Object { MismoArtista $_ $art }) })
            $t = $res | Where-Object { -not $enPl.Contains("$(Norm $art)|$(Base $_.name)") } | Select-Object -First 1
            if ($t) { $agregadas += [pscustomobject]@{ Genero = $gen; Texto = "$(($t.artists.name | Select-Object -First 2) -join ', ') - $($t.name)"; Uri = $t.uri }; [void]$enPl.Add("$(Norm $art)|$(Base $t.name)") }
            else { $noHalladas += "$art - $tit" }
        } catch { $noHalladas += "$art - $tit (error: $($_.Exception.Message))" }
        continue
    }
    # "+Titulo" = agregar aunque ya este descargada
    $forzar = $tit.StartsWith('+'); $tit = $tit.TrimStart('+')
    $clave = "$(Norm $art)|$(Base $tit)"
    if ($tengo.Contains($clave) -and -not $forzar) { $yaTenia += "$art - $tit (descargada)"; continue }
    if ($enPl.Contains($clave)) { $yaTenia += "$art - $tit (ya en la playlist)"; continue }
    try {
        $q = [uri]::EscapeDataString("track:$tit artist:$art")
        $res = @((Api Get "/search?type=track&limit=10&q=$q").tracks.items | Where-Object { $_ })
        if (-not $res) { $res = @((Api Get "/search?type=track&limit=10&q=$([uri]::EscapeDataString("$tit $art"))").tracks.items | Where-Object { $_ }) }
        $res = @($res | Where-Object { $_.artists.name | Where-Object { MismoArtista $_ $art } })
        $t = $res | Where-Object { (Base $_.name) -eq (Base $tit) } | Select-Object -First 1
        if (-not $t) { $noHalladas += "$art - $tit"; continue }
        $agregadas += [pscustomobject]@{ Genero = $gen; Texto = "$($t.artists[0].name) - $($t.name)"; Uri = $t.uri }
        [void]$enPl.Add($clave)
    } catch { $noHalladas += "$art - $tit (error: $($_.Exception.Message))" }
}
$uris = @($agregadas.Uri | Select-Object -Unique)
for ($i = 0; $i -lt $uris.Count; $i += 100) {
    $null = Api Post "/playlists/$plId/items" @{ uris = @($uris[$i..([Math]::Min($i + 99, $uris.Count - 1))]) }
}

if ($TambienEn -and $uris.Count) {
    $id2 = ((Api Get "/me/playlists?limit=50").items | Where-Object { $_.name -eq $TambienEn } | Select-Object -First 1).id
    for ($i = 0; $i -lt $uris.Count; $i += 100) { $null = Api Post "/playlists/$id2/items" @{ uris = @($uris[$i..([Math]::Min($i + 99, $uris.Count - 1))]) } }
    "Tambien agregadas a ${TambienEn}: $($uris.Count)"
}
# -Repartir: cada recomendacion tambien va a la playlist que dice su columna Genero y a All
if ($Repartir -and $uris.Count) {
    $mias = (Api Get "/me/playlists?limit=50").items
    foreach ($g in @($agregadas | Group-Object Genero) + [pscustomobject]@{ Name = 'All'; Group = $agregadas }) {
        $dest = @($mias | Where-Object name -eq $g.Name)
        if ($dest.Count -ne 1) { "No reparti '$($g.Name)': hay $($dest.Count) playlists con ese nombre"; continue }
        $ya = @{}; foreach ($t in LeerPlaylist $dest[0].id) { $ya[$t.uri] = 1; $ya["$(Norm $t.artists[0].name)|$(Base $t.name)"] = 1 }
        $u = @($g.Group | Where-Object { -not $ya[$_.Uri] -and -not $ya["$(Norm ($_.Texto -split ' - ', 2)[0])|$(Base ($_.Texto -split ' - ', 2)[1])"] } | ForEach-Object { $_.Uri } | Select-Object -Unique)
        for ($i = 0; $i -lt $u.Count; $i += 100) { $null = Api Post "/playlists/$($dest[0].id)/items" @{ uris = @($u[$i..([Math]::Min($i + 99, $u.Count - 1))]) } }
        "Repartidas a $($g.Name): $($u.Count)"
    }
}
$rep = @("REPETIDAS QUITADAS ($($repetidas.Count)):") + $repetidas + "" + "RECOMENDACIONES AGREGADAS ($($uris.Count)):"
foreach ($g in $agregadas | Group-Object Genero) { $rep += "-- $($g.Name) --"; $rep += $g.Group.Texto }
$rep += ""; $rep += "YA LAS TENIAS ($($yaTenia.Count)):"; $rep += $yaTenia
$rep += ""; $rep += "NO ENCONTRADAS EN SPOTIFY ($($noHalladas.Count)):"; $rep += $noHalladas
$rep | Set-Content "$desk\recomendaciones-agregadas.txt" -Encoding utf8
$rep
