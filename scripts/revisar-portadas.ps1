# Solo lectura: revisa la portada incrustada de cada FLAC (bloque PICTURE).
# Reporta canciones SIN portada y con portada pequena (< 500 px), agrupadas por album.
param([string]$Raiz = "D:\SpotiFLAC", [int]$MinPx = 500)
. "$PSScriptRoot\progreso.ps1"
$todos = @(Get-ChildItem $Raiz -Recurse -File -Filter *.flac); $n = 0
$mf = Get-Content (Join-Path $env:USERPROFILE 'reportes-musica\metaflac-path.txt')
$sin = @(); $chica = @(); $ok = 0
foreach ($f in $todos) {
    $n++; Progreso 'portadas' $n $todos.Count @{ sin_portada = $sin.Count; pequenas = $chica.Count } $f.BaseName
    $b = & $mf --list --block-type=PICTURE $f.FullName 2>$null
    $w = ($b | Where-Object { $_ -match '^\s*width:\s*(\d+)' } | ForEach-Object { [int]($_ -replace '\D', '') } | Measure-Object -Maximum).Maximum
    $rel = $f.FullName.Substring($Raiz.Length + 1)
    if (-not $w) { $sin += $rel } elseif ($w -lt $MinPx) { $chica += "$rel ($w px)" } else { $ok++ }
}
"Con portada buena: $ok | sin portada: $($sin.Count) | portada pequena (< $MinPx px): $($chica.Count)"
"--- sin portada (por album):"; $sin | Group-Object { Split-Path $_ } | ForEach-Object { "$($_.Name) ($($_.Count))" }
"--- portada pequena:"; $chica
