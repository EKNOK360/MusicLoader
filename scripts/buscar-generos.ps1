# Solo lectura: busca en MusicBrainz las etiquetas de genero de cada artista.
# Guarda reportes-musica\mb-generos.json (artista -> etiquetas). Se puede cortar y continuar.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dir = (Join-Path $env:USERPROFILE 'reportes-musica')
$out = "$dir\mb-generos.json"
$res = @{}; if (Test-Path $out) { (Get-Content $out -Raw -Encoding utf8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $res[$_.Name] = $_.Value } }
$ua = @{ 'User-Agent' = 'OrganizadorMusicaPersonal/1.0' }
$artistas = @(Get-ChildItem 'D:\SpotiFLAC' -Recurse -File -Include *.flac, *.m4a, *.mp3 | ForEach-Object { (($_.BaseName -split ' - ', 2)[0] -split ',\s*')[0].Trim() } | Sort-Object -Unique); $artistas | Set-Content "$dir\artistas.txt" -Encoding utf8
$i = 0
foreach ($a in $artistas) {
    $i++
    if ($res.ContainsKey($a) -and -not $res[$a].error) { continue }
    $q = [uri]::EscapeDataString("artist:`"$a`"")
    try {
        $r = $null; for ($k = 0; $k -lt 4 -and -not $r; $k++) { try { $r = Invoke-RestMethod -Uri "https://musicbrainz.org/ws/2/artist/?query=$q&fmt=json&limit=3" -Headers $ua } catch { if ($k -eq 3) { throw }; Start-Sleep -Seconds (3 * ($k + 1)) } }
        $m = $r.artists | Where-Object { $_.score -ge 90 } | Select-Object -First 1
        $tags = if ($m -and $m.tags) { @($m.tags | Sort-Object { [int]$_.count } -Descending | Select-Object -First 6 | ForEach-Object { $_.name }) } else { @() }
        $res[$a] = [pscustomobject]@{ pais = $m.country; tags = $tags }
    } catch { $res[$a] = [pscustomobject]@{ pais = $null; tags = @(); error = $_.Exception.Message } }
    if ($i % 25 -eq 0) { $res | ConvertTo-Json -Depth 4 -Compress | Set-Content $out -Encoding utf8; Write-Host "Avance: $i de $($artistas.Count)" }
    Start-Sleep -Milliseconds 1600
}
$res | ConvertTo-Json -Depth 4 -Compress | Set-Content $out -Encoding utf8
"Listo: $($res.Count) artistas, con etiquetas: $(@($res.Values | Where-Object { $_.tags.Count }).Count)"
