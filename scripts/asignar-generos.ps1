# Calcula el/los generos de cada artista (MusicBrainz + genero que ya traia el archivo + ajustes manuales)
# y, con -Aplicar, escribe SOLO la etiqueta GENRE en los FLAC (metaflac; audio, letras y demas etiquetas intactas).
param([switch]$Aplicar)
. "$PSScriptRoot\progreso.ps1"
$dir = (Join-Path $env:USERPROFILE 'reportes-musica')
$mf = Get-Content "$dir\metaflac-path.txt"

# etiqueta (en minusculas, de MusicBrainz o del archivo) -> genero. El orden importa: lo mas especifico primero.
$mapa = [ordered]@{
    'electro swing' = 'Electro Swing'; 'phonk' = 'Phonk'; 'dembow' = 'Dembow'
    'reggaeton|reggaetón|urbano latino' = 'Reggaeton'; 'latin trap|trap latino|argentine trap' = 'Latin Trap'
    'bachata' = 'Bachata'; 'salsa' = 'Salsa'; 'merengue' = 'Merengue'; 'cumbia' = 'Cumbia'; 'vallenato' = 'Vallenato'
    'regional mexican|norteño|corrido|mariachi|ranchera|banda sinaloense|sierreño' = 'Regional Mexican'
    'dancehall' = 'Dancehall'; 'calypso|soca' = 'Calypso'; 'reggae|ska' = 'Reggae'
    'metalcore|deathcore|post-hardcore|screamo' = 'Metalcore'; 'nu metal' = 'Nu Metal'; 'metal' = 'Metal'
    'pop punk|punk|emo' = 'Punk'
    'rock en español|rock latino|latin rock|argentine rock|rock nacional' = 'Latin Rock'
    'k-pop' = 'K-Pop'; 'j-rock|visual kei' = 'J-Rock'; 'j-pop|anime|vocaloid|japanese' = 'J-Pop'
    'musical|show tunes|broadway|musiques de films|comédie musicale' = 'Musical'
    'soundtrack|film score|video game|bandes originales' = 'Soundtrack'
    'classical|classique|baroque|romantic|opera|orchestral|neoclassical|contemporary classical' = 'Classical'
    'tango' = 'Tango'; 'bolero' = 'Bolero'; 'nueva canción|nueva trova|trova' = 'Trova'
    'jazz|swing' = 'Jazz'; 'funk|disco' = 'Funk'; 'r&b|rnb|soul' = 'R&B'
    'hip hop|hip-hop|rap' = 'Hip-Hop'; 'trap' = 'Trap'
    'electronic|électronique|edm|house|dubstep|electropop|synthpop|techno|trance|drum and bass' = 'Electronic'
    'indie|alternatif et indé|bedroom pop|lo-fi' = 'Indie'; 'alternative' = 'Alternative'
    'folk|celtic|singer-songwriter|acoustic' = 'Folk'
    'rock' = 'Rock'; 'latin pop|pop latino|amérique latine|latin|spanish' = 'Latin Pop'; 'pop' = 'Pop'
}
$latam = 'AR','MX','CO','CL','PE','VE','UY','PR','DO','CR','ES','EC','BO','PY','PA','CU','GT','HN','SV','NI'
function Generos($etiquetas, $pais) {
    $g = New-Object Collections.Generic.List[string]
    foreach ($e in $etiquetas) {
        $e = "$e".ToLower()
        foreach ($k in $mapa.Keys) { if ($e -match "(^|[^a-z])($k)([^a-z]|$)") { if (-not $g.Contains($mapa[$k])) { $g.Add($mapa[$k]) }; break } }
    }
    # Pop/Rock de artistas latinos -> Latin Pop / Latin Rock
    if ($latam -contains $pais) { for ($i = 0; $i -lt $g.Count; $i++) { if ($g[$i] -eq 'Pop') { $g[$i] = 'Latin Pop' } elseif ($g[$i] -eq 'Rock') { $g[$i] = 'Latin Rock' } } }
    @($g | Select-Object -Unique | Select-Object -First 3)
}

$mb = @{}; (Get-Content "$dir\mb-generos.json" -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $mb[$_.Name] = $_.Value }
$manual = @{}; if (Test-Path "$dir\generos-manual.txt") { Get-Content "$dir\generos-manual.txt" -Encoding utf8 | Where-Object { $_ -match '\|' } | ForEach-Object { $a, $g = $_ -split '\|', 2; $manual[$a.Trim()] = @($g -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } }

$plan = @(); $sinGenero = @{}
foreach ($f in Get-ChildItem 'D:\SpotiFLAC' -Recurse -File -Filter *.flac) {
    $art = (($f.BaseName -split ' - ', 2)[0] -split ',\s*')[0].Trim()
    $actual = @(& $mf --show-tag=GENRE $f.FullName | ForEach-Object { $_.Substring(6) } | ForEach-Object { $_ -split '\s*/\s*|;\s*' } | Where-Object { $_ -and $_ -notmatch 'billboard' })
    $g = if ($manual.ContainsKey($art)) { $manual[$art] } else {
        $info = $mb[$art]
        Generos (@($info.tags) + $actual) $info.pais
    }
    $g = @($g); if ($g.Count -eq 0) { $sinGenero[$art] = 1 + [int]$sinGenero[$art]; continue }
    $plan += [pscustomobject]@{ ruta = $f.FullName; artista = $art; antes = ($actual -join ' / '); generos = @($g) }
}

"Canciones con genero calculado: $($plan.Count) | artistas sin genero: $($sinGenero.Count) ($(($sinGenero.Values | Measure-Object -Sum).Sum) canciones)"
$plan | ForEach-Object { $_ } | Export-Clixml "$dir\generos-plan.xml"; $plan | Group-Object { $_.generos[0] } | Sort-Object Count -Descending | ForEach-Object { "{0,5}  {1}" -f $_.Count, $_.Name }
$sinGenero.Keys | Sort-Object | Set-Content "$dir\artistas-sin-genero.txt" -Encoding utf8

if ($Aplicar) {
    $ok = 0; $mal = @()
    foreach ($p in $plan) {
        $ya = @(& $mf --show-tag=GENRE $p.ruta | ForEach-Object { $_.Substring(6) }); if (($ya -join '|') -eq ($p.generos -join '|')) { $ok++; Progreso 'generos' ($ok + $mal.Count) $plan.Count @{ listas = $ok; problemas = $mal.Count }; continue }
        $antesTags = & $mf --export-tags-to=- $p.ruta | Where-Object { $_ -notmatch '^GENRE=' }
        $args2 = @('--preserve-modtime', '--remove-tag=GENRE') + ($p.generos | ForEach-Object { "--set-tag=GENRE=$_" }) + @($p.ruta)
        & $mf @args2
        $despTags = & $mf --export-tags-to=- $p.ruta | Where-Object { $_ -notmatch '^GENRE=' }
        if ($LASTEXITCODE -ne 0 -or @(Compare-Object $antesTags $despTags).Count) { $mal += $p.ruta } else { $ok++ }; Progreso 'generos' ($ok + $mal.Count) $plan.Count @{ listas = $ok; problemas = $mal.Count }
    }
    "Escritos: $ok | con problemas: $($mal.Count)"; $mal
}
