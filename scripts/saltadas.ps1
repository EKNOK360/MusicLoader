# Compara la playlist "Por recuperar" (en orden) con lo descargado: saltadas = las que estan antes
# de la ultima descargada pero no tienen archivo.
function NormS($s) { if (-not $s) { return '' }; ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^\p{L}\p{N}]', '' }
$script:vig = @(Get-Content "$env:USERPROFILE\reportes-musica\vigilar.txt" -Encoding utf8); $script:lista = if ($script:vig.Count -gt 2 -and $script:vig[2]) { @(@(Get-Content $script:vig[2] -Raw -Encoding utf8 | ConvertFrom-Json) | ForEach-Object { $_ }) } else { @((@(Get-Content "$env:USERPROFILE\reportes-musica\playlists.json" -Raw -Encoding utf8 | ConvertFrom-Json) | ForEach-Object { $_ } | Where-Object nombre -eq $script:vig[0]).canciones) }
function Saltadas {
    $tengo = New-Object 'Collections.Generic.HashSet[string]'
    Get-ChildItem -LiteralPath (Join-Path "D:\SpotiFLAC" $script:vig[1]) -Recurse -File | Where-Object { $_.Extension -in '.flac', '.m4a', '.mp3' } | ForEach-Object {
        $p = $_.BaseName -split ' - ', 2
        foreach ($a in $p[0] -split ',\s*') { [void]$tengo.Add("$(NormS $a)|$(NormS $p[1])") }
    }
    if (Test-Path "$env:USERPROFILE\reportes-musica\movidos-$($script:vig[1]).txt") { Get-Content "$env:USERPROFILE\reportes-musica\movidos-$($script:vig[1]).txt" -Encoding utf8 | ForEach-Object { $p = [IO.Path]::GetFileNameWithoutExtension($_) -split ' - ', 2; foreach ($a in $p[0] -split ',\s*') { [void]$tengo.Add("$(NormS $a)|$(NormS $p[1])") } } }
    $usadas = New-Object 'Collections.Generic.HashSet[string]'
    $ok = @(); for ($i = 0; $i -lt $script:lista.Count; $i++) {
        $t = $script:lista[$i]; $k = "$(NormS (($t.a -split ', ')[0]))|$(NormS $t.n)"
        $hit = $tengo.Contains($k)
        if (-not $hit -and $k.Length -gt 12) { foreach ($x in $tengo) { if ($x.Length -gt 12 -and ($k.StartsWith($x) -or $x.StartsWith($k))) { $hit = $true; break } } }
        if ($hit -and -not $usadas.Add($k)) { $hit = $false }  # cancion repetida en la lista: el archivo cuenta una sola vez
        $ok += $hit
    }
    $ultima = [Array]::LastIndexOf($ok, $true)
    $salt = @(for ($i = 0; $i -lt $ultima; $i++) { if (-not $ok[$i]) { "#$($i+1) $($script:lista[$i].a) - $($script:lista[$i].n)" } })
    [pscustomobject]@{ bajadas = @($ok | Where-Object { $_ }).Count; posicion = $ultima + 1; saltadas = $salt }
}
