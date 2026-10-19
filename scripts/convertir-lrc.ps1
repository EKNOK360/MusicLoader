# Vuelve a guardar los .lrc con otra codificacion. Reproductores sencillos (p. ej. MIBAO) leen los .lrc en ANSI
# (Windows-1252) y muestran "dÃ­a" en vez de "día" si estan en UTF-8. Opciones: ansi | utf8bom | utf8.
# Si una letra tiene caracteres que no caben en ANSI (p. ej. japones sin romanizar), ese archivo NO se toca y se avisa.
# Uso: convertir-lrc.ps1 -Raiz E:\Music -Codificacion ansi   [-Archivo una.lrc para probar con una sola]
param([string]$Raiz = "", [ValidateSet('ansi', 'utf8bom', 'utf8')][string]$Codificacion = 'ansi', [string]$Archivo = "")
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ansi = [Text.Encoding]::GetEncoding(1252, [Text.EncoderFallback]::ExceptionFallback, [Text.DecoderFallback]::ExceptionFallback)
$enc = switch ($Codificacion) { 'ansi' { $ansi } 'utf8bom' { New-Object Text.UTF8Encoding $true } default { New-Object Text.UTF8Encoding $false } }
function Leer($p) {  # detecta como esta guardado: BOM UTF-8, UTF-8 valido, o ANSI
    $b = [IO.File]::ReadAllBytes($p)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return [Text.Encoding]::UTF8.GetString($b, 3, $b.Length - 3) }
    try { return (New-Object Text.UTF8Encoding $false, $true).GetString($b) } catch { return [Text.Encoding]::GetEncoding(1252).GetString($b) }
}
$lista = if ($Archivo) { @(Get-Item -LiteralPath $Archivo) } else { @(Get-ChildItem -LiteralPath $Raiz -Recurse -File -Filter *.lrc) }
$ok = 0; $no = @()
foreach ($f in $lista) {
    $t = Leer $f.FullName
    try { $bytes = $enc.GetBytes($t) } catch { $no += $f.Name; continue }
    if ($Codificacion -eq 'utf8bom') { $bytes = [byte[]](0xEF, 0xBB, 0xBF) + $bytes }
    [IO.File]::WriteAllBytes($f.FullName, $bytes)
    if ((Leer $f.FullName) -ne $t) { $no += "$($f.Name) (no quedo igual)"; continue }
    $ok++
}
"Convertidos a ${Codificacion}: $ok | sin convertir: $($no.Count)"; $no
