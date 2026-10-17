# Canciones REPETIDAS (mismo artista principal + mismo titulo; FLAC/MP3/M4A).
# Sin -Aplicar (por defecto): SOLO REPORTA. Arma un cuadro comparativo de cada grupo (formato, bits/kHz o kbps,
# tamano, duracion, portada, letra sincronizada, genero) y marca la MEJOR; guarda el cuadro en
# reportes-musica\repetidas.md y el plan en repetidas.json. NO borra nada.
# Con -Aplicar (solo cuando el usuario lo pida despues de ver el cuadro): borra las de menor calidad y deja la mejor
# en la carpeta bien acomodada.
# Mejor calidad = FLAC/ALAC sin perdida > con perdida; luego mas bits, mas kHz, mas kbps, mas tamano.
param([switch]$Aplicar, [string]$Raiz = "")
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
if (-not $Raiz) { $cfg = Join-Path $dir 'config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
$ff = Get-Content (Join-Path $dir 'ffmpeg-path.txt'); $fp = Join-Path (Split-Path $ff) 'ffprobe.exe'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
function NormS($s) { if (-not $s) { return '' }; ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^\p{L}\p{N}]', '' }
function Calidad($f) {
    $j = & $fp -v error -show_format -show_streams -of json $f.FullName | ConvertFrom-Json
    $a = $j.streams | Where-Object codec_type -eq 'audio' | Select-Object -First 1
    $t = @{}; foreach ($p in @($j.format.tags.PSObject.Properties) + @($a.tags.PSObject.Properties)) { if ($p) { $t[$p.Name.ToLower()] = "$($p.Value)" } }
    $sinPerdida = $a.codec_name -in 'flac', 'alac', 'wav', 'pcm_s16le', 'pcm_s24le'
    $bits = if ($a.bits_per_raw_sample) { [int]$a.bits_per_raw_sample } elseif ($a.bits_per_sample) { [int]$a.bits_per_sample } else { 0 }
    $kbps = [int]([double]$j.format.bit_rate / 1000)
    [pscustomobject]@{
        f = $f; codec = $a.codec_name; sp = [int]$sinPerdida; bits = $bits; hz = [int]$a.sample_rate; kbps = $kbps
        mb = [Math]::Round($f.Length / 1MB, 1); dur = [Math]::Round([double]$j.format.duration)
        portada = [bool]($j.streams | Where-Object { $_.codec_type -eq 'video' }); letra = [bool](($t.Keys | Where-Object { $_ -match 'lyrics' } | ForEach-Object { $t[$_] }) -match '\[\d+:\d+') -or (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($f.FullName, '.lrc')))
        genero = $t['genre']
        txt = if ($sinPerdida -and $bits) { "$($a.codec_name.ToUpper()) $bits-bit/$([Math]::Round([int]$a.sample_rate / 1000, 1)) kHz" } else { "$($a.codec_name.ToUpper()) $kbps kbps" }
    }
}
function Doble($f) { $r = $f.FullName.Substring($Raiz.Length + 1) -split '\\'; ($r.Count -gt 2 -and $r[0] -eq $r[1]) -or $r[0] -eq 'Various Artists' }

$todos = @(Get-ChildItem $Raiz -Recurse -File | Where-Object { $_.Extension -in '.flac', '.m4a', '.mp3' -and -not $_.FullName.StartsWith("$Raiz\_reemplazados") })
$grupos = @($todos | Group-Object { $p = $_.BaseName -replace '_\d\d$', '' -split ' - ', 2; "$(NormS (($p[0] -split ',\s*')[0]))|$(NormS $p[1])" } | Where-Object Count -gt 1)
$md = @("# Canciones repetidas ($($grupos.Count) grupos) - $(Get-Date -Format 'yyyy-MM-dd HH:mm')", ''); $plan = @(); $n = 0
foreach ($g in $grupos) {
    $n++
    $c = @($g.Group | ForEach-Object { Calidad $_ })
    $orden = @($c | Sort-Object @{e = { $_.sp }; d = $true }, @{e = { $_.bits }; d = $true }, @{e = { $_.hz }; d = $true }, @{e = { $_.kbps }; d = $true }, @{e = { $_.mb }; d = $true })
    $mejor = $orden[0]; $otros = @($orden | Select-Object -Skip 1)
    $iguales = ($otros | Where-Object { $_.txt -eq $mejor.txt }).Count -gt 0
    $destDir = $mejor.f.DirectoryName
    if (Doble $mejor.f) { $bien = $otros | Where-Object { -not (Doble $_.f) } | Select-Object -First 1; if ($bien) { $destDir = $bien.f.DirectoryName } }
    $md += "## $n. $(($mejor.f.BaseName -split ' - ', 2)[1]) — $(($mejor.f.BaseName -split ' - ', 2)[0])"
    $md += '| | Calidad | Tamaño | Duración | Portada | Letra sinc. | Género | Carpeta |'
    $md += '|---|---|---|---|---|---|---|---|'
    foreach ($x in $orden) {
        $marca = if ($x -eq $mejor) { if ($iguales) { '⭐ se queda (misma calidad)' } else { '⭐ **mejor**' } } else { '🗑️ menor' }
        $md += "| $marca | $($x.txt) | $($x.mb) MB | $([int]($x.dur / 60)):$('{0:00}' -f ($x.dur % 60)) | $(if ($x.portada) { '✅' } else { '❌' }) | $(if ($x.letra) { '✅' } else { '❌' }) | $(if ($x.genero) { $x.genero } else { '❌' }) | ``$($x.f.DirectoryName.Substring($Raiz.Length + 1))`` |"
    }
    $md += ''
    $plan += [pscustomobject]@{ queda = $mejor.f.FullName; destino = (Join-Path $destDir $mejor.f.Name); borrar = @($otros | ForEach-Object { $_.f.FullName }) }
}
$md | Set-Content (Join-Path $dir 'repetidas.md') -Encoding utf8
$plan | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $dir 'repetidas.json') -Encoding utf8
"Grupos de repetidas: $($grupos.Count) | archivos de menor calidad: $(($plan | ForEach-Object { $_.borrar.Count } | Measure-Object -Sum).Sum) | cuadro: reportes-musica\repetidas.md"
if (-not $Aplicar) { "(Solo reporte: no se borro nada. Para borrar las de menor calidad: -Aplicar, SOLO si el usuario lo pide.)"; return }

$hechos = 0
foreach ($p in $plan) {
    if (-not (Test-Path -LiteralPath $p.queda)) { "NO EXISTE la que se queda, no se toca este grupo: $($p.queda)"; continue }
    foreach ($b in $p.borrar) { Remove-Item -LiteralPath $b -Force; $l = [IO.Path]::ChangeExtension($b, '.lrc'); if (Test-Path -LiteralPath $l) { Remove-Item -LiteralPath $l -Force } }
    if ($p.destino -ne $p.queda) { Move-Item -LiteralPath $p.queda $p.destino -Force }
    $hechos++
}
Get-ChildItem $Raiz -Recurse -Directory | Where-Object { -not $_.FullName.StartsWith("$Raiz\_reemplazados") } | Sort-Object { $_.FullName.Length } -Descending |
    Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Where-Object { $_.Extension -in '.flac', '.m4a', '.mp3' }) } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
"Grupos resueltos: $hechos"
