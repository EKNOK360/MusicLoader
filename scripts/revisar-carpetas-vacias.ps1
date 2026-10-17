# Busca carpetas dentro de SpotiFLAC que no tienen ninguna canción (ni directamente ni en subcarpetas).
# Solo revisa, no borra nada.
param([string]$Raiz = "D:\SpotiFLAC")

$audio = '.flac', '.m4a', '.mp3', '.wav', '.ogg', '.opus', '.aac'
$reporte = Join-Path (Join-Path $env:USERPROFILE 'reportes-musica') "carpetas-vacias.txt"
New-Item -ItemType Directory -Force (Split-Path $reporte) | Out-Null

$vacias = Get-ChildItem $Raiz -Directory -Recurse | Where-Object {
    -not (Get-ChildItem $_.FullName -File -Recurse | Where-Object { $audio -contains $_.Extension.ToLower() })
} | ForEach-Object { $_.FullName.Substring($Raiz.Length + 1) }

if ($vacias) {
    $vacias | Set-Content $reporte -Encoding utf8
    $vacias
    "`nTotal: $(@($vacias).Count) carpetas sin canciones. Lista guardada en: $reporte"
} else {
    "Todo bien: ninguna carpeta vacía."
}
