param([switch]$Aplicar)
function NormS($s) { if (-not $s) { return '' }; ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^\p{L}\p{N}]', '' }
$raiz = 'D:\SpotiFLAC'
function Calidad($f) {
    # FLAC: lee STREAMINFO (frecuencia y bits). Otros formatos cuentan como peor calidad.
    if ($f.Extension -ne '.flac') { return [pscustomobject]@{ flac = 0; bits = 0; hz = 0; txt = $f.Extension.TrimStart('.') } }
    $b = New-Object byte[] 42; $s = [IO.File]::OpenRead($f.FullName); [void]$s.Read($b, 0, 42); $s.Close()
    $i = 8  # 4 "fLaC" + 4 cabecera de bloque
    $hz = ([int]$b[$i + 10] -shl 12) -bor ([int]$b[$i + 11] -shl 4) -bor ([int]$b[$i + 12] -shr 4)
    $bits = (((([int]$b[$i + 12]) -band 1) -shl 4) -bor ([int]$b[$i + 13] -shr 4)) + 1
    [pscustomobject]@{ flac = 1; bits = $bits; hz = $hz; txt = "$bits-bit/$([Math]::Round($hz/1000,1))kHz" }
}
function Doble($f) { $r = $f.FullName.Substring($raiz.Length + 1) -split '\\'; ($r.Count -gt 2 -and $r[0] -eq $r[1]) -or $r[0] -like 'EPIC The Musical*' -or $r[0] -eq 'Various Artists' }

$f = @(Get-ChildItem $raiz -Recurse -File -Include *.flac, *.m4a, *.mp3 | Where-Object { -not $_.FullName.StartsWith("$raiz\_reemplazados") })
$grupos = $f | Group-Object { $p = $_.BaseName -replace '_\d\d$', '' -split ' - ', 2; "$(NormS (($p[0] -split ',\s*')[0]))|$(NormS $p[1])" } | Where-Object Count -gt 1
$hechos = 0
foreach ($g in $grupos) {
    $c = $g.Group | ForEach-Object { [pscustomobject]@{ f = $_; q = (Calidad $_) } }
    $mejor = ($c | Sort-Object @{e = { $_.q.flac }; d = $true }, @{e = { $_.q.bits }; d = $true }, @{e = { $_.q.hz }; d = $true }, @{e = { $_.f.Length }; d = $true })[0]
    $otros = @($c | Where-Object { $_.f.FullName -ne $mejor.f.FullName })
    # destino: si la mejor esta en carpeta doble/vieja, va a la carpeta bien acomodada de otra copia
    $destDir = $mejor.f.DirectoryName
    if (Doble $mejor.f) { $bien = $otros | Where-Object { -not (Doble $_.f) } | Select-Object -First 1; if ($bien) { $destDir = $bien.f.DirectoryName } }
    $dest = Join-Path $destDir $mejor.f.Name
    "QUEDA  $($mejor.q.txt)  $($dest.Substring($raiz.Length + 1))" + $(if ($dest -ne $mejor.f.FullName) { "   (movida desde $($mejor.f.DirectoryName.Substring($raiz.Length + 1)))" })
    foreach ($o in $otros) { "  BORRA  $($o.q.txt)  $($o.f.FullName.Substring($raiz.Length + 1))" }
    if ($Aplicar) {
        foreach ($o in $otros) { Remove-Item -LiteralPath $o.f.FullName -Force }
        if ($dest -ne $mejor.f.FullName) { Move-Item -LiteralPath $mejor.f.FullName $dest -Force }
        $hechos++
    }
}
if ($Aplicar) {
    # carpetas sin musica que quedaron vacias
    Get-ChildItem $raiz -Recurse -Directory | Where-Object { -not $_.FullName.StartsWith("$raiz\_reemplazados") } | Sort-Object { $_.FullName.Length } -Descending |
        Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Include *.flac, *.m4a, *.mp3) } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
    "Grupos resueltos: $hechos"
}
