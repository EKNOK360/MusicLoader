# Compara la playlist "Por recuperar" (en orden) con lo descargado: saltadas = las que estan antes
# de la ultima descargada pero no tienen archivo.
function NormS($s) { if (-not $s) { return '' }; ($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLower() -replace '[^\p{L}\p{N}]', '' }
$script:vig = @(Get-Content "$env:USERPROFILE\reportes-musica\vigilar.txt" -Encoding utf8); $script:lista = if ($script:vig.Count -gt 2 -and $script:vig[2]) { @(@(Get-Content $script:vig[2] -Raw -Encoding utf8 | ConvertFrom-Json) | ForEach-Object { $_ }) } else { @((@(Get-Content "$env:USERPROFILE\reportes-musica\playlists.json" -Raw -Encoding utf8 | ConvertFrom-Json) | ForEach-Object { $_ } | Where-Object nombre -eq $script:vig[0]).canciones) }
function Saltadas {
    $tengo = New-Object 'Collections.Generic.HashSet[string]'
    Get-ChildItem -LiteralPath $(if ([IO.Path]::IsPathRooted($script:vig[1])) { $script:vig[1] } else { Join-Path "D:\SpotiFLAC" $script:vig[1] }) -Recurse -File | Where-Object { $_.Extension -in '.flac', '.m4a', '.mp3' } | ForEach-Object {
        $p = $_.BaseName -split ' - ', 2
        foreach ($a in $p[0] -split ',\s*') { [void]$tengo.Add("$(NormS $a)|$(NormS $p[1])") }
    }
    if (Test-Path "$env:USERPROFILE\reportes-musica\movidos-$(Split-Path $script:vig[1] -Leaf).txt") { Get-Content "$env:USERPROFILE\reportes-musica\movidos-$(Split-Path $script:vig[1] -Leaf).txt" -Encoding utf8 | ForEach-Object { $p = [IO.Path]::GetFileNameWithoutExtension($_) -split ' - ', 2; foreach ($a in $p[0] -split ',\s*') { [void]$tengo.Add("$(NormS $a)|$(NormS $p[1])") } } }
    # cada archivo cuenta para UNA sola cancion: primero las coincidencias exactas, despues por inicio del nombre
    # (nombres cortados) solo con archivos que no se usaron; si no, "Cumbia Loca" tambien marcaba "Cumbia Loca Remix"
    $usados = New-Object 'Collections.Generic.HashSet[string]'
    $claves = @(foreach ($t in $script:lista) { "$(NormS (($t.a -split ', ')[0]))|$(NormS $t.n)" })
    $ok = New-Object bool[] $script:lista.Count
    for ($i = 0; $i -lt $claves.Count; $i++) { if ($tengo.Contains($claves[$i]) -and $usados.Add($claves[$i])) { $ok[$i] = $true } }
    for ($i = 0; $i -lt $claves.Count; $i++) {
        $k = $claves[$i]; if ($ok[$i] -or $k.Length -le 12) { continue }
        foreach ($x in $tengo) { if ($x.Length -gt 12 -and -not $usados.Contains($x) -and ($k.StartsWith($x) -or $x.StartsWith($k))) { [void]$usados.Add($x); $ok[$i] = $true; break } }
    }
    $ultima = [Array]::LastIndexOf($ok, $true)
    $salt = @(for ($i = 0; $i -lt $ultima; $i++) { if (-not $ok[$i]) { "#$($i+1) $($script:lista[$i].a) - $($script:lista[$i].n)" } })
    [pscustomobject]@{ bajadas = @($ok | Where-Object { $_ }).Count; posicion = $ultima + 1; saltadas = $salt }
}
