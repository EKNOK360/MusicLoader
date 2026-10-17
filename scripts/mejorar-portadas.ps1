# Cambia por una portada de 1200 px (iTunes) las portadas pequenas (< -MinPx) de los FLAC.
# Solo cambia la imagen: respalda el archivo, reemplaza el bloque PICTURE y verifica que los bytes del audio
# y las demas etiquetas queden identicos (si no, restaura el respaldo). Sin -Aplicar solo muestra el plan.
param([string]$Raiz = "", [int]$MinPx = 500, [switch]$Aplicar)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
if (-not $Raiz) { $cfg = Join-Path $dir 'config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
$mf = Get-Content (Join-Path $dir 'metaflac-path.txt')
$ff = Get-Content (Join-Path $dir 'ffmpeg-path.txt'); $fp = Join-Path (Split-Path $ff) 'ffprobe.exe'
$tmp = Join-Path $env:TEMP 'musicloader-portadas'; New-Item -ItemType Directory -Force $tmp | Out-Null
function Json($url) { $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8; $wc.Headers.Add('User-Agent', 'MusicLoader/1.0'); try { $wc.DownloadString($url) | ConvertFrom-Json } finally { $wc.Dispose() } }
function Norm($s) { if (-not $s) { return '' }; ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '\(.*?\)|\[.*?\]|-.*$' -replace '[^\p{L}\p{N}]', '' }
function NormAlb($s) { if (-not $s) { return '' }; ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^\p{L}\p{N}]', '' }  # album exacto (sin quitar 'acoustic', 'deluxe'...)
function Ancho($f) { $w = 0; foreach ($x in @(& $fp -v error -select_streams v -show_entries stream=width -of csv=p=0 $f 2>$null)) { if ([int]"0$x" -gt $w) { $w = [int]"0$x" } }; $w }
function Tag($f, $k) { (& $mf --no-utf8-convert "--show-tag=$k" $f | Select-Object -First 1) -replace "^$k=", '' }
function HuellaFlac($f) { $s = [IO.File]::OpenRead($f); try { $b = New-Object byte[] 4; [void]$s.Read($b, 0, 4); $u = $false; while (-not $u) { [void]$s.Read($b, 0, 4); $u = ($b[0] -band 0x80) -ne 0; $l = ([int]$b[1] -shl 16) -bor ([int]$b[2] -shl 8) -bor [int]$b[3]; [void]$s.Seek($l, 'Current') }; [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($s)) } finally { $s.Close() } }
function Etiquetas($f) { & $mf --export-tags-to=- $f | Where-Object { $_ -match '^[A-Za-z0-9_ ]+=' } }

$res = @()
foreach ($f in Get-ChildItem $Raiz -Recurse -File -Filter *.flac) {
    $w = Ancho $f.FullName
    if ($w -ge $MinPx) { continue }
    $art = (Tag $f.FullName 'ARTIST') -split ',\s*|;\s*' | Select-Object -First 1; $tit = Tag $f.FullName 'TITLE'; $alb = Tag $f.FullName 'ALBUM'
    $r = @((Json "https://itunes.apple.com/search?country=US&entity=song&limit=10&term=$([uri]::EscapeDataString("$art $tit"))").results)
    $hit = $r | Where-Object { (Norm $_.trackName) -eq (Norm $tit) -and ((Norm $_.artistName).Contains((Norm $art)) -or (Norm $art).Contains((Norm $_.artistName))) } |
        Where-Object { (NormAlb $_.collectionName) -eq (NormAlb $alb) } | Select-Object -First 1  # solo la portada del MISMO album
    Start-Sleep -Seconds 3
    if (-not $hit) { $res += "SIN PORTADA NUEVA (iTunes no tiene ese album exacto: $alb)  $($f.Name)  ($w px)"; continue }
    $url = $hit.artworkUrl100 -replace '100x100bb', '1200x1200bb'
    if (-not $Aplicar) { $res += "CAMBIARIA  $($f.Name): $w px -> 1200 px  [$($hit.collectionName)]"; continue }
    $img = Join-Path $tmp 'cover.jpg'; (New-Object Net.WebClient).DownloadFile($url, $img)
    $bk = Join-Path $tmp $f.Name; Copy-Item -LiteralPath $f.FullName $bk -Force
    $h = HuellaFlac $f.FullName; $et = Etiquetas $f.FullName
    & $mf --preserve-modtime --remove --block-type=PICTURE $f.FullName
    & $mf --preserve-modtime "--import-picture-from=3||||$img" $f.FullName
    $nuevo = Ancho $f.FullName
    if ($h -eq (HuellaFlac $f.FullName) -and -not (Compare-Object @($et) @(Etiquetas $f.FullName)) -and $nuevo -ge $MinPx) { $res += "LISTA  $($f.Name): $w px -> $nuevo px"; Remove-Item $bk }
    else { Copy-Item $bk -LiteralPath $f.FullName -Force; $res += "RESTAURADA (algo no cuadro)  $($f.Name)" }
}
if (-not $res) { "Todas las portadas tienen $MinPx px o mas." } else { $res }
