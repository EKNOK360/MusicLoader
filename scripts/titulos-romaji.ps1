# Titulos en japones/coreano -> "Romaji (Original)", p. ej. "Yoru ni Kakeru (夜に駆ける)", para encontrarlas facil en el reproductor.
# Solo cambia la etiqueta TITLE (FLAC con metaflac; M4A/MP3 con mutagen). El nombre del archivo no se toca.
# Sin -Aplicar solo muestra el plan. Con -Aplicar verifica que el audio y las demas etiquetas queden identicos.
param([switch]$Aplicar, [string]$Raiz = "")
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
if (-not $Raiz) { $cfg = Join-Path $dir 'config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$mf = Get-Content "$dir\metaflac-path.txt"; $py = Get-Content "$dir\python-path.txt"
$ffm = Get-Content "$dir\ffmpeg-path.txt"; $ffp = Join-Path (Split-Path $ffm) 'ffprobe.exe'
$noLat = '[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]'
function EsFlac($f) { $f -like '*.flac' }
function LeerTitulo($f) {
    if (EsFlac $f) { return ((& $mf --no-utf8-convert --show-tag=TITLE $f | Select-Object -First 1) -replace '^TITLE=', '') }
    (& $py "$PSScriptRoot\letra-tag.py" titulo-leer $f) -join ''
}
function Romaji($s) {
    $e = Join-Path $env:TEMP 'tit-in.txt'; $o = Join-Path $env:TEMP 'tit-out.txt'
    [IO.File]::WriteAllText($e, $s, (New-Object Text.UTF8Encoding $false)); & $py "$PSScriptRoot\romanizar.py" $e $o
    [IO.File]::ReadAllText($o, [Text.Encoding]::UTF8).Trim()
}
function Nuevo($t) {
    if ($t -notmatch $noLat -or $t -match "\($noLat") { return $null }  # ya latino, o ya tiene el original entre parentesis
    $partes = $t -split ' - '
    $lat = @($partes | Where-Object { $_ -notmatch $noLat })
    $orig = (@($partes | Where-Object { $_ -match $noLat }) -join ' - ')
    $rom = if ($lat) { $lat -join ' - ' } else { Romaji $orig }   # "オトノケ - Otonoke" -> ya trae su romaji
    "$rom ($orig)"
}

$plan = @()
foreach ($f in Get-ChildItem -LiteralPath $Raiz -Recurse -File | Where-Object { $_.Extension -in '.flac', '.m4a', '.mp3' }) {
    $t = LeerTitulo $f.FullName
    $n = Nuevo $t
    if ($n) { $plan += [pscustomobject]@{ f = $f.FullName; antes = $t; despues = $n } }
}
"Titulos a cambiar: $($plan.Count)"; $plan | ForEach-Object { "$($_.antes)  ->  $($_.despues)" }
if (-not $Aplicar) { return }

$bien = 0; $mal = @()
foreach ($x in $plan) {
    $p = $x.f; $bk = Join-Path $env:TEMP ([IO.Path]::GetFileName($p)); Copy-Item -LiteralPath $p $bk -Force
    $md5 = (& $ffm -v error -i $p -map 0:a -f md5 - 2>$null) -join ''
    $otras = { param($q) (& $ffp -v error -show_entries format_tags -of json $q | ConvertFrom-Json).format.tags.PSObject.Properties | Where-Object Name -notmatch '^title$' | ForEach-Object { "$($_.Name)=$($_.Value)" } }
    $antes = & $otras $p; $mt = (Get-Item -LiteralPath $p).LastWriteTime
    if (EsFlac $p) { & $mf --preserve-modtime --no-utf8-convert --remove-tag=TITLE "--set-tag=TITLE=$($x.despues)" $p }
    else { $e = Join-Path $env:TEMP 'tit.txt'; [IO.File]::WriteAllText($e, $x.despues, (New-Object Text.UTF8Encoding $false)); & $py "$PSScriptRoot\letra-tag.py" titulo-escribir $p $e }
    if ($LASTEXITCODE -eq 0 -and $md5 -and $md5 -eq ((& $ffm -v error -i $p -map 0:a -f md5 - 2>$null) -join '') -and (LeerTitulo $p) -eq $x.despues -and -not (Compare-Object @($antes) @(& $otras $p))) {
        (Get-Item -LiteralPath $p).LastWriteTime = $mt; $bien++; Remove-Item $bk
    } else { Copy-Item $bk -LiteralPath $p -Force; $mal += $p }
}
"Titulos cambiados: $bien | con problemas (restaurados): $($mal.Count)"; $mal
