# Crea (o usa) una playlist para descargar y le agrega:
#  - las canciones de -CopiarDe que no esten descargadas en el disco
#  - las de -Lista (formato: Destinos|Artista|?busqueda  o  Destinos|Artista|Titulo exacto)
#    Destinos = otras playlists separadas por ';' (regla: estilo + All). Se evitan versiones en vivo.
param([string]$Nombre = "Descargar", [string]$CopiarDe = "", [string]$Lista = "", [string]$Raiz = "D:\SpotiFLAC")
. "$PSScriptRoot\spotify-auth.ps1" -Scopes "playlist-read-private playlist-modify-private playlist-modify-public"
function Base($s) { if (-not $s) { return '' }; $s = ($s -replace '\(.*?\)|\[.*?\]', '' -split ' - ')[0]; $s = $s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''; ($s.ToLower() -replace '[^\p{L}\p{N}]', '') }
function Norm($s) { if (-not $s) { return '' }; ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^\p{L}\p{N}]', '' }
function MismoArtista($a, $b) { $x = Norm $a; $y = Norm $b; $x -and $y -and ($x.Contains($y) -or $y.Contains($x)) }
function Leer($id) { $o = @(); $n = "/playlists/$id/items?limit=100"; while ($n) { $pg = Api Get $n; $pg.items | ForEach-Object { $x = if ($_.item) { $_.item } else { $_.track }; if ($x -and $x.uri) { $o += $x } }; $n = $pg.next }; $o }
function Agregar($id, $uris) { for ($i = 0; $i -lt $uris.Count; $i += 100) { $null = Api Post "/playlists/$id/items" @{ uris = @($uris[$i..([Math]::Min($i + 99, $uris.Count - 1))]) } } }

$mias = @(); $n = "/me/playlists?limit=50"; while ($n) { $pg = Api Get $n; $mias += @($pg.items); $n = $pg.next }
function IdDe($nombre) { ($mias | Where-Object { $_.name -eq $nombre } | Select-Object -First 1).id }
$dest = IdDe $Nombre
if (-not $dest) { $dest = (Api Post "/me/playlists" @{ name = $Nombre; public = $false; description = "Canciones para pasar por SpotiFLAC" }).id; "Playlist nueva: $Nombre" }

# lo que ya esta descargado
$tengo = New-Object 'Collections.Generic.HashSet[string]'; $exacto = New-Object 'Collections.Generic.HashSet[string]'
Get-ChildItem $Raiz -Recurse -File -Include *.flac, *.m4a, *.mp3 | ForEach-Object { $p = $_.BaseName -split ' - ', 2; foreach ($a in $p[0] -split ',\s*') { [void]$tengo.Add("$(Norm $a)|$(Base $p[1])"); [void]$exacto.Add("$(Norm $a)|$(Norm $p[1])") } }
function DescargadaExacta($t) { foreach ($a in $t.artists.name) { if ($exacto.Contains("$(Norm $a)|$(Norm $t.name)")) { return $true } }; $false }
function Descargada($t) { foreach ($a in $t.artists.name) { if ($tengo.Contains("$(Norm $a)|$(Base $t.name)")) { return $true } }; $false }

$enDest = @{}; foreach ($t in Leer $dest) { $enDest[$t.uri] = 1 }
$nuevas = @(); $extra = @{}; $rep = @()

if ($CopiarDe) {
    foreach ($t in Leer (IdDe $CopiarDe)) {
        if (Descargada $t) { $rep += "YA DESCARGADA  $($t.artists[0].name) - $($t.name)"; continue }
        if (-not $enDest.ContainsKey($t.uri)) { $nuevas += $t.uri; $enDest[$t.uri] = 1; $rep += "DE $CopiarDe  $($t.artists[0].name) - $($t.name)" }
    }
}
if ($Lista) {
    foreach ($l in Get-Content $Lista -Encoding utf8 | Where-Object { $_ -match '\|' }) {
        $destinos, $art, $q = $l -split '\|', 3
        $libre = $q.StartsWith('?'); $q = $q.TrimStart('?')
        $res = @((Api Get "/search?type=track&limit=10&q=$([uri]::EscapeDataString("$q $art"))").tracks.items | Where-Object { $_ -and ($_.artists.name | Where-Object { MismoArtista $_ $art }) })
        if ($q -notmatch 'live|vivo') { $res = @($res | Where-Object { "$($_.name) $($_.album.name)" -notmatch 'live|en vivo|session' }) }
        if (-not $libre) { $res = @($res | Where-Object { (Base $_.name) -eq (Base $q) }) }
        $t = $res | Where-Object { -not $enDest.ContainsKey($_.uri) -and -not (DescargadaExacta $_) } | Select-Object -First 1
        if (-not $t) { $rep += "NO ENCONTRADA o ya descargada  $art - $q"; continue }
        $nuevas += $t.uri; $enDest[$t.uri] = 1
        $rep += "AGREGADA  $(($t.artists.name | Select-Object -First 2) -join ', ') - $($t.name)  [$($t.album.name)]"
        foreach ($d in $destinos -split ';' | Where-Object { $_ }) { if (-not $extra[$d]) { $extra[$d] = @() }; $extra[$d] += $t }
    }
}
Agregar $dest $nuevas
foreach ($d in $extra.Keys) {
    $id = IdDe $d; if (-not $id) { $rep += "No existe la playlist $d"; continue }
    $ya = @{}; foreach ($t in Leer $id) { $ya[$t.uri] = 1; $ya["$(Norm $t.artists[0].name)|$(Base $t.name)"] = 1 }
    $u = @($extra[$d] | Where-Object { -not $ya[$_.uri] -and -not $ya["$(Norm $_.artists[0].name)|$(Base $_.name)"] } | ForEach-Object { $_.uri })
    Agregar $id $u; $rep += "Tambien en ${d}: $($u.Count)"
}
$rep
"Playlist '$Nombre': +$($nuevas.Count) canciones -> https://open.spotify.com/playlist/$dest"
