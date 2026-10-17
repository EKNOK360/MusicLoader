# Fuentes de letras SINCRONIZADAS. Se carga con:  . "$PSScriptRoot\lrc-fuentes.ps1"
#   BuscarLetra $artista $titulo $album $duracionSegundos  ->  @{ lrc; fuente; inst }
# Orden: 1) LRCLIB (lrclib.net, abierta)  2) NetEase Cloud Music (API publica no oficial, muy usada por reproductores).
# Solo se acepta una letra si: la duracion de la fuente coincide con la del archivo (+-2 s), tiene >= 5 lineas
# con tiempo y el ultimo tiempo no pasa el final de la cancion. Se quitan lineas de creditos (compositor, etc.).
function LrcJson($url, $referer = '') {
    $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8
    $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) MusicLoader/1.0'); if ($referer) { $wc.Headers.Add('Referer', $referer) }
    try { $wc.DownloadString($url) | ConvertFrom-Json } finally { $wc.Dispose() }
}
function LrcNorm($s) { if (-not $s) { return '' }; ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '\(.*?\)|\[.*?\]|-.*$' -replace '[^\p{L}\p{N}]', '' }
function LrcLimpia($lrc) {  # quita creditos tipo "作词 : ..." / "Composer:" y lineas de metadatos
    (($lrc -split "`r?`n") | Where-Object { $_ -notmatch '^\[\d+:\d+(\.\d+)?\]\s*(作词|作曲|编曲|制作|混音|和声|监制|母带|录音|吉他|贝斯|鼓|Lyricist|Composer|Arranger|Producer|Written by|Lyrics by|Music by)\s*[:：]' -and $_ -notmatch '^\[(ar|ti|al|by|offset|length|re|ve):' }) -join "`n"
}
function LrcValida($lrc, $dur) {
    $m = [regex]::Matches("$lrc", '(?m)^\[(\d+):(\d+(?:\.\d+)?)\]\s*\S')
    if ($m.Count -lt 5) { return $false }
    $u = $m[$m.Count - 1]; ([int]$u.Groups[1].Value * 60 + [double]$u.Groups[2].Value) -le $dur + 1
}
function BuscarLrclib($art, $tit, $alb, $dur) {
    $c = @()
    try { $g = LrcJson "https://lrclib.net/api/get?artist_name=$([uri]::EscapeDataString($art))&track_name=$([uri]::EscapeDataString($tit))&album_name=$([uri]::EscapeDataString($alb))&duration=$([int][Math]::Round($dur))"; if ($g) { $c += $g } } catch { }
    try { $c += @(LrcJson "https://lrclib.net/api/search?artist_name=$([uri]::EscapeDataString($art))&track_name=$([uri]::EscapeDataString($tit))") } catch { }
    $c = @($c | ForEach-Object { $_ } | Where-Object { $_ -and $_.duration })
    $inst = [bool]($c | Where-Object { $_.instrumental -and [Math]::Abs([double]$_.duration - $dur) -le 2 })
    $b = $c | Where-Object { $_.syncedLyrics -and [Math]::Abs([double]$_.duration - $dur) -le 2 -and (LrcValida $_.syncedLyrics $dur) } | Sort-Object { [Math]::Abs([double]$_.duration - $dur) } | Select-Object -First 1
    [pscustomobject]@{ lrc = $(if ($b) { $b.syncedLyrics } else { '' }); fuente = 'LRCLIB'; inst = $inst }
}
function BuscarNetease($art, $tit, $dur) {
    try {
        $r = LrcJson "https://music.163.com/api/search/get?type=1&limit=10&s=$([uri]::EscapeDataString("$art $tit"))" 'https://music.163.com/'
        $nt = LrcNorm $tit; $na = LrcNorm $art
        $songs = @($r.result.songs | Where-Object { $_ -and [Math]::Abs([double]$_.duration / 1000 - $dur) -le 2 -and ((LrcNorm $_.name) -eq $nt -or (LrcNorm $_.name).Contains($nt)) -and (@($_.artists | Where-Object { (LrcNorm $_.name).Contains($na) -or $na.Contains((LrcNorm $_.name)) }).Count) } |
            Sort-Object { [Math]::Abs([double]$_.duration / 1000 - $dur) })
        foreach ($s in $songs | Select-Object -First 3) {
            Start-Sleep -Milliseconds 400
            $l = LrcJson "https://music.163.com/api/song/lyric?id=$($s.id)&lv=1&kv=1&tv=-1" 'https://music.163.com/'
            $lrc = LrcLimpia "$($l.lrc.lyric)"
            if (LrcValida $lrc $dur) { return [pscustomobject]@{ lrc = $lrc; fuente = 'NetEase'; inst = $false } }
        }
    } catch { }
    [pscustomobject]@{ lrc = ''; fuente = ''; inst = $false }
}
function BuscarLetra($art, $tit, $alb, $dur) {
    $r = BuscarLrclib $art $tit $alb $dur
    if ($r.lrc -or $r.inst) { return $r }
    $n = BuscarNetease $art $tit $dur
    if ($n.lrc) { return $n }
    $r
}
