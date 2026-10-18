# Reparte las canciones de "Por recuperar" en tus otras playlists segun el artista, y todas a "All".
# Sin -Aplicar solo muestra el plan (usa reportes-musica\playlists.json, no toca Spotify).
param([switch]$Aplicar, [string]$Origen = "Por recuperar", [string]$Borrar = "", [string]$FuenteJson = "", [string]$CrearDesde = "", [string]$NuevaPlaylist = "")

$reglas = [ordered]@{
    'Reggae & Dancehall' = @('Alborosie', 'Alpha Blondy', 'Beenie Man', 'Bob Marley & The Wailers', 'Charly Black', 'Chronixx', 'Cultura Profética', 'Damian Marley', 'Dread Mar I', 'Elephant Man', 'Fidel Nadal', 'Gondwana', 'Kevin Lyttle', 'Los Cafres', 'Matisyahu', 'Mr. Vegas', 'Popcaan', 'Rebelution', 'Rawayana', 'Sean Paul', 'Shaggy', 'Shenseea', 'SOJA', 'Spice', 'UB40', 'Vybz Kartel', 'Wayne Wonder', 'Mekatelyu', '4bes', 'DJ Kendo', 'DEEIKEL', 'GIMARIO', 'Kybba', 'Letty', 'Lil Quil', 'Lion Fiah', 'Mr Fran Official Limón Crew', 'Noro M', 'Staar Watson', 'Toledo', 'Haquil', 'Tapon', 'Dani Maro', 'Shel Dixon', 'Nerry Money', 'Xeuz', 'GOLDSTONE MUSIC', 'Los Excavators', 'BETABOM', 'Konshens', 'Blaiz Fayah', 'J Capri', 'Enur', 'T.O.K', 'Big Shroom', 'Ghettox Music')
    'Rock & Phonk'      = @('A Day To Remember', 'AC/DC', 'Architects', 'Asking Alexandria', 'Avenged Sevenfold', 'Bad Omens', 'Beartooth', 'Billy Talent', 'blink-182', 'Breaking Benjamin', 'Bring Me The Horizon', 'Bullet For My Valentine', 'Deftones', 'Disturbed', 'Enter Shikari', 'Falling In Reverse', 'Foo Fighters', 'Good Charlotte', 'Green Day', 'Greta Van Fleet', "Guns N' Roses", 'I Prevail', 'Knocked Loose', 'Korn', 'Limp Bizkit', 'Linkin Park', 'Motionless In White', 'My Chemical Romance', 'Nirvana', 'NOTHING MORE', 'Of Mice & Men', 'Papa Roach', 'Paramore', 'Poppy', 'Rage Against The Machine', 'Rise Against', 'Royal Blood', 'Simple Plan', 'Sleep Token', 'Sleeping With Sirens', 'Slipknot', 'Spiritbox', 'Sum 41', 'System Of A Down', 'The Offspring', 'Three Days Grace', 'Wage War', 'Muse', 'Queen', 'Red Hot Chili Peppers', 'The White Stripes', 'Atreyu', 'Staind', 'Once Monsters', 'Skindred')
    'Old songs'         = @('Angel Y Khriz', 'Anthony Santos', 'Arcángel', 'Aventura', 'Bacilos', 'Buena Vista Social Club', 'Chino & Nacho', 'Cosculluela', 'Daddy Yankee', 'Don Omar', 'Eddie Santiago', 'Elvis Crespo', 'Frank Reyes', 'Frankie Ruiz', 'Fruko Y Sus Tesos', 'Fulanito', 'Gilberto Santa Rosa', 'Gilda', 'Grupo Niche', 'Héctor "El Father"', 'Héctor Lavoe', 'Hombres G', 'Ivy Queen', 'Juan Luis Guerra 4.40', 'Luis Miguel', 'Marc Anthony', 'Monchy & Alexandra', 'Nicky Jam', "Oscar D'León", 'Plan B', 'Prince Royce', 'Proyecto Uno', 'R.K.M & Ken-Y', 'Reik', 'Romeo Santos', 'Rubén Blades', 'Sonora Carruseles', 'Tego Calderón', 'Tito "El Bambino"', 'Tito Rojas', 'Toby Love', 'Tony Dize', 'Víctor Manuelle', 'Wilfrido Vargas', 'Willie Colón', 'Wisin & Yandel', 'Xtreme', 'Zion & Lennox', 'Los Ángeles Azules', 'Mecano', 'Mocedades', 'Andrés Cepeda', 'Black Eyed Peas', 'Counting Crows', 'a-ha', 'Journey', 'TOTO', 'Michael Jackson', 'Earth', 'Soda Stereo', 'Gustavo Cerati', 'Caifanes', 'Los Enanitos Verdes', 'Café Tacvba', 'Los Prisioneros', 'Los Fabulosos Cadillacs', 'Heroes Del Silencio', 'Molotov', 'Maná', 'Jarabe De Palo', 'Charly García', 'Fito Paez', 'Bersuit Vergarabat', 'Silvio Rodríguez', 'Mercedes Sosa', 'Joan Manuel Serrat', 'Facundo Cabral', 'Simón Díaz', 'Kapanga', 'Calle 13', 'Manu Chao', 'Antony Badilla Vargas', '3BallMTY', 'Dalvin La Melodia', 'Chris Lebron', 'Raulin Rodriguez', 'Alex Bueno', 'Son By Four')
    'Pop & More'        = @('Milo j', 'Alleh', 'AKRIILA', 'Aitana', 'Alvaro Diaz', 'Ariza', 'Bad Bunny', 'Bandalos Chinos', 'Beret', 'Bhavi', 'Canserbero', 'Carín León', 'Cocofunka', 'Debi Nova', 'Duki', 'ELENA ROSE', 'Emilia', 'Feid', 'Grupo Frontera', 'Kali Uchis', 'Kevin Kaarl', 'Malpaís', 'Myke Towers', 'Nabález', 'Natalia Lafourcade', 'Nicki Nicole', 'Rauw Alejandro', 'Residente', 'ROSALÍA', 'Trueno', 'WOS', 'Yera', 'Antonio José', 'Vicente Garcia', 'Wamba', 'Pj Sin Suela', 'Silvana Estrada', 'Monsieur Periné', 'Bomba Estéreo', 'Jorge Drexler', 'Kevin Johansen', 'Lila Downs', 'Pedro Guerra', 'Pedro Capmany', 'Manuel Obregón', 'Gandhi', 'Percance', '424', 'Bocaraca', 'Babasonicos', 'Zoé', 'La Vela Puerca', 'No Te Va Gustar', 'Los Govinda', 'VENGO DE UNA TIERRA', 'Smash Hits', 'Los Mesoneros', 'Paty Cantú', 'Manuel Carrasco', 'Esto es ¡FA!', 'Paulina Rubio', 'melodymano', 'Kalis K3', 'Sanalejo', 'CoolestAndie', 'Ceaxe')
    'Random'            = @('El Cuarteto De Nos', 'Ado', 'Kenshi Yonezu', 'King Gnu', 'Creepy Nuts', 'Eve', 'Vaundy', 'Linked Horizon', 'OFFICIAL HIGE DANDISM', 'YOASOBI', 'SawanoHiroyuki[nZk]', 'bbno$', 'Y2K', 'Imagine Dragons', 'Måneskin', 'Dua Lipa', 'The Neighbourhood', 'Twenty One Pilots', 'Panic! At The Disco', 'Tally Hall', 'Will Wood', 'Wallows', 'Lovejoy', 'Cavetown', 'Mother Mother', 'Hozier', 'MGMT', 'Foster The People', 'Cage The Elephant', 'Lord Huron', 'Djo', 'Fitz and The Tantrums', 'Bastille', 'Two Door Cinema Club', 'Tame Impala', 'Mitski', 'Chappell Roan', 'Powfu', 'Ruth B.', 'Confetti', 'Black Gryph0n', 'Hazbin Hotel', 'Ben Platt', 'Leslie Odom Jr.', 'Jorge Rivera-Herrans', 'Keala Settle', 'Stephen Schwartz', 'George Salazar', 'Alan Walker', 'Martin Garrix', 'Daft Punk', 'Swedish House Mafia', 'Calvin Harris', 'Stromae', 'Gotan Project', 'The Killers', 'The Strokes', 'Oasis', 'Las Robertas', 'American Authors', 'Beach House', 'Connor Price', 'DNCE', 'Drod', 'Jason Mraz', 'Jaymes Young', 'Lil Nas X', 'Lonely God', 'Neon Trees', 'Nicky Youre', 'Sam Smith', 'Seafret', 'Stephen Sanchez', 'Steve Lacy', 'The Chainsmokers', 'The Script', 'Tom Odell', 'Vundabar', 'Halsey', 'NF', 'Jain', 'Celtic Woman', 'Yung Crusha')
    'Classical'         = @('logan feece', "Beethoven's Wig", 'Vittorio Monti')
}
function Norm($s) { ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^a-z0-9]', '' }
function Clave($t) { "$(Norm (($t.a -split ', ')[0]))|$(Norm $t.n)" }

$j = Get-Content "$env:USERPROFILE\reportes-musica\playlists.json" -Raw -Encoding utf8 | ConvertFrom-Json
$fuente = if ($FuenteJson) { @(Get-Content $FuenteJson -Raw -Encoding utf8 | ConvertFrom-Json) | ForEach-Object { $_ } | Where-Object { $_.u } } else { @(($j | Where-Object nombre -eq $Origen).canciones) }
$destinos = @($reglas.Keys) + 'All'
$ya = @{}; $ids = @{}
foreach ($d in $destinos) {
    $p = $j | Where-Object nombre -eq $d | Select-Object -First 1
    if (-not $p) { throw "No encontre la playlist '$d'." }
    $ids[$d] = $p.id
    $ya[$d] = New-Object 'Collections.Generic.HashSet[string]'
    foreach ($t in $p.canciones) { [void]$ya[$d].Add($t.u); [void]$ya[$d].Add((Clave $t)) }
}

# artista -> playlist donde ya tienes la mayoria de sus canciones (para artistas sin regla)
$cuenta = @{}
foreach ($k in $reglas.Keys) { foreach ($t in ($j | Where-Object nombre -eq $k).canciones) { $a = Norm (($t.a -split ', ')[0]); if (-not $cuenta[$a]) { $cuenta[$a] = @{} }; $cuenta[$a][$k] = 1 + [int]$cuenta[$a][$k] } }
function Mayoria($a) { $c = $cuenta[(Norm $a)]; if ($c) { ($c.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key } }
$plan = @{}; $destinos | ForEach-Object { $plan[$_] = New-Object Collections.Generic.List[object] }
$sinGrupo = @()
foreach ($t in $fuente) {
    $arts = $t.a -split ', '
    $metas = @('All')
    # se reparte por artista principal
    # si ya esta en alguna playlist tematica, solo falta (quiza) en All
    $yaClasificada = $reglas.Keys | Where-Object { $ya[$_].Contains($t.u) -or $ya[$_].Contains((Clave $t)) } | Select-Object -First 1
    $g = if ($yaClasificada) { $yaClasificada } else { $reglas.Keys | Where-Object { $reglas[$_] -contains $arts[0] } | Select-Object -First 1 }
    if (-not $g) { $g = Mayoria $arts[0] }
    if ($g) { $metas += $g } elseif ($arts[0] -ne 'Morat') { $sinGrupo += "$($t.a) - $($t.n)" }
    if ($arts[0] -eq 'Morat' -and -not $g) { $metas += 'Pop & More' }  # tus Morat tambien estan en Pop & More
    foreach ($m in $metas | Select-Object -Unique) {
        if (-not ($ya[$m].Contains($t.u) -or $ya[$m].Contains((Clave $t)))) { $plan[$m].Add($t); [void]$ya[$m].Add($t.u); [void]$ya[$m].Add((Clave $t)) }
    }
}

foreach ($d in $destinos) {
    "=== $d : +$($plan[$d].Count)"
    if ($d -ne 'All') { ($plan[$d] | Group-Object { ($_.a -split ', ')[0] } | Sort-Object Count -Descending | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ' }
}
"=== SIN GRUPO (solo van a All): $($sinGrupo.Count)"; $sinGrupo

if ($Aplicar) {
    . "$PSScriptRoot\spotify-auth.ps1" -Scopes "playlist-read-private playlist-modify-private playlist-modify-public"
    foreach ($d in $destinos) {
        $uris = @($plan[$d] | ForEach-Object { $_.u } | Where-Object { $_ })
        for ($i = 0; $i -lt $uris.Count; $i += 100) {
            $null = Api Post "/playlists/$($ids[$d])/items" @{ uris = @($uris[$i..([Math]::Min($i + 99, $uris.Count - 1))]) }
        }
        "Agregadas a $d : $($uris.Count)"
    }
    # playlist nueva con canciones de un json (ej. likes que no estan descargados)
    if ($CrearDesde) {
        $nu = @(@(Get-Content $CrearDesde -Raw -Encoding utf8 | ConvertFrom-Json) | ForEach-Object { $_ } | ForEach-Object { $_.u } | Select-Object -Unique)
        $pl = Api Post "/me/playlists" @{ name = $NuevaPlaylist; public = $false; description = "Likes que todavia no estan descargados" }
        for ($i = 0; $i -lt $nu.Count; $i += 100) { $null = Api Post "/playlists/$($pl.id)/items" @{ uris = @($nu[$i..([Math]::Min($i + 99, $nu.Count - 1))]) } }
        "Playlist '$NuevaPlaylist' creada con $($nu.Count) canciones: $($pl.external_urls.spotify)"
    }
    # dejar de seguir = quitarla de tu biblioteca (Spotify permite recuperarla unos 90 dias)
    if ($Borrar) {
        $b = @($j | Where-Object { $_.nombre -like $Borrar })
        if ($b.Count -gt 1) { throw "Hay $($b.Count) playlists que coinciden con '$Borrar'; no elimino ninguna." }
        $b = $b[0]
        if ($b) { $null = Api Delete "/playlists/$($b.id)/followers"; "Eliminada: $Borrar" } else { "No encontre la playlist '$Borrar' para eliminar." }
    }
}
