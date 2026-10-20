# Pre-filtro SIN Spotify para explicitas.ps1: pregunta a iTunes (Apple Music) si cada cancion tiene version EXPLICITA.
# Spotify (apps en modo desarrollo) bloquea ~24 h tras unas 700 busquedas al dia; asi solo se busca en Spotify lo necesario.
# Lee las canciones de reportes-musica\playlists.json (tus playlists) y de tu disco (enlace de Spotify en COMMENT).
# Guarda reportes-musica\itunes-explicitas.json:  uri -> 'explicit' | 'no' | '?' (no estaba en iTunes)
# ~19 consultas/min (limite de iTunes); se puede cortar y seguir despues sin repetir.
param([string]$Raiz = "")  # (las playlists "Descargar..." y las copias "(2)" no cuentan)
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
if (-not $Raiz) { $cfg = Join-Path $dir 'config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
. "$PSScriptRoot\progreso.ps1"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$mf = Get-Content "$dir\metaflac-path.txt"; $ffp = Join-Path (Split-Path (Get-Content "$dir\ffmpeg-path.txt")) 'ffprobe.exe'
function Norm($s) { ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^\p{L}\p{N}]', '' }
function Base($s) { Norm (($s -replace '\((clean|edited|radio edit|explicit|censored|sucia|limpia|feat[^)]*|with [^)]*)[^)]*\)|\[[^\]]*\]', '' -split ' - ')[0]) }

# canciones: uri -> artista, titulo
$canc = [ordered]@{}
foreach ($p in @(Get-Content "$dir\playlists.json" -Raw -Encoding utf8 | ConvertFrom-Json) | Where-Object { $_.nombre -notlike 'Descargar*' -and $_.nombre -notlike '* (2)' }) { foreach ($t in $p.canciones) { if ($t.u -like 'spotify:track:*' -and -not $canc.Contains($t.u)) { $canc[$t.u] = @{ a = ($t.a -split ', ')[0]; n = $t.n } } } }
foreach ($f in Get-ChildItem -LiteralPath $Raiz -Recurse -File | Where-Object { $_.Extension -in '.flac', '.m4a', '.mp3' }) {
    $c = if ($f.Extension -eq '.flac') { & $mf --no-utf8-convert --show-tag=COMMENT $f.FullName } else { & $ffp -v error -show_entries format_tags=comment -of default=nw=1:nk=1 $f.FullName }
    if ("$c" -match 'open\.spotify\.com/track/([A-Za-z0-9]{22})') { $u = "spotify:track:$($Matches[1])"; if (-not $canc.Contains($u)) { $p = $f.BaseName -split ' - ', 2; $canc[$u] = @{ a = ($p[0] -split ',\s*')[0]; n = $p[1] } } }
}

$cf = "$dir\itunes-explicitas.json"; $cache = @{}; if (Test-Path $cf) { (Get-Content $cf -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cache[$_.Name] = $_.Value } }
$falta = @($canc.Keys | Where-Object { -not $cache.ContainsKey($_) }); $n = 0
foreach ($u in $falta) {
    $n++; $x = $canc[$u]
    Progreso 'prefiltro-explicitas' $n $falta.Count @{ con_explicita = @($cache.Values | Where-Object { $_ -eq 'explicit' }).Count } "$($x.a) - $($x.n)"
    $q = [uri]::EscapeDataString("$($x.a) $(($x.n -replace '\(.*?\)|\[.*?\]| - .*$', '').Trim())")
    try {
        $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8; $wc.Headers.Add('User-Agent', 'MusicLoader/1.0')
        $r = @(($wc.DownloadString("https://itunes.apple.com/search?country=US&entity=song&limit=25&term=$q") | ConvertFrom-Json).results)
        $m = @($r | Where-Object { (Base $_.trackName) -eq (Base $x.n) -and ((Norm $_.artistName).Contains((Norm $x.a)) -or (Norm $x.a).Contains((Norm $_.artistName))) })
        $cache[$u] = if (@($m | Where-Object trackExplicitness -eq 'explicit').Count) { 'explicit' } elseif ($m.Count) { 'no' } else { '?' }
    } catch { Start-Sleep -Seconds 60; continue }   # iTunes limita: esperar y seguir (esta queda para la proxima vuelta)
    if ($n % 25 -eq 0) { $cache | ConvertTo-Json -Compress | Set-Content $cf -Encoding utf8 }
    Start-Sleep -Milliseconds 3200
}
$cache | ConvertTo-Json -Compress | Set-Content $cf -Encoding utf8
$v = @($cache.Values); "Revisadas en iTunes: $($v.Count) | con version explicita: $(@($v | Where-Object { $_ -eq 'explicit' }).Count) | sin explicita: $(@($v | Where-Object { $_ -eq 'no' }).Count) | no estan en iTunes: $(@($v | Where-Object { $_ -eq '?' }).Count)"
