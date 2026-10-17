# Solo lectura: lee una playlist (por id) y la compara con el disco.
# Guarda reportes-musica\externa.json (todas) y externa-faltan.json (las que no estan descargadas).
param([string]$Id = "", [string]$Nombre = "", [string]$Raiz = "D:\SpotiFLAC")
. "$PSScriptRoot\spotify-auth.ps1" -Scopes "playlist-read-private playlist-read-collaborative"
function Base($s) { if (-not $s) { return '' }; $s = ($s -replace '\(.*?\)|\[.*?\]', '' -split ' - ')[0]; $s = $s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''; ($s.ToLower() -replace '[^\p{L}\p{N}]', '') }
function Norm($s) { if (-not $s) { return '' }; ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^\p{L}\p{N}]', '' }

if (-not $Id) { $mias = @(); $n = "/me/playlists?limit=50"; while ($n) { $pg = Api Get $n; $mias += @($pg.items); $n = $pg.next }; $m = @($mias | Where-Object { $_.name -like $Nombre }); if ($m.Count -ne 1) { throw "Encontre $($m.Count) playlists con el nombre $Nombre : $(($m.name) -join ' | ')" }; $Id = $m[0].id }
$info = Api Get "/playlists/$Id`?fields=name,owner(display_name)"
"Playlist: $($info.name)  (de $($info.owner.display_name))"
$tr = @(); $next = "/playlists/$Id/items?limit=100"
while ($next) { $pg = Api Get $next; $pg.items | ForEach-Object { $x = if ($_.item) { $_.item } else { $_.track }; if ($x -and $x.uri -match '^spotify:track:') { $tr += [pscustomobject]@{ a = ($x.artists.name -join ', '); n = $x.name; al = $x.album.name; u = $x.uri } } }; $next = $pg.next }

$tengo = New-Object 'Collections.Generic.HashSet[string]'
Get-ChildItem $Raiz -Recurse -File -Include *.flac, *.m4a, *.mp3 | ForEach-Object { $p = $_.BaseName -split ' - ', 2; foreach ($a in $p[0] -split ',\s*') { [void]$tengo.Add("$(Norm $a)|$(Base $p[1])") } }
$faltan = @(foreach ($t in $tr) { $hit = $false; foreach ($a in $t.a -split ', ') { if ($tengo.Contains("$(Norm $a)|$(Base $t.n)")) { $hit = $true; break } }; if (-not $hit) { $t } })

$tr | ConvertTo-Json -Compress | Set-Content "$desk\externa.json" -Encoding utf8
$faltan | ConvertTo-Json -Compress | Set-Content "$desk\externa-faltan.json" -Encoding utf8
"Canciones: $($tr.Count) | ya descargadas: $($tr.Count - $faltan.Count) | NO descargadas: $($faltan.Count)"
"--- no descargadas:"; $faltan | ForEach-Object { "$($_.a) - $($_.n)" }
