# Acomoda canciones de CUALQUIER descargador (FLAC, MP3, M4A) en  Raiz\Artista\Album\Artista - Titulo.ext
# usando las etiquetas del archivo (artista del album > artista, album, titulo). Si faltan, usa el nombre
# "Artista - Titulo" y el album "Singles". Mueve tambien el .lrc que tenga al lado.
# Si ya existe un archivo con ese nombre, el viejo va a Raiz\_reemplazados (no se borra nada).
# Sin -Aplicar solo muestra el plan. Consejo: correr antes completar-metadatos.ps1 sobre la carpeta de origen.
param([Parameter(Mandatory)][string]$Origen, [string]$Raiz = "", [switch]$Aplicar)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
if (-not $Raiz) { $cfg = Join-Path $dir 'config.json'; $Raiz = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).raiz } else { 'D:\SpotiFLAC' } }
$ff = Get-Content (Join-Path $dir 'ffmpeg-path.txt'); $fp = Join-Path (Split-Path $ff) 'ffprobe.exe'
function Limpio($s) { $s = ($s -replace '[\\/:*?"<>|]', ' ' -replace '\s+', ' ').Trim().TrimEnd('.'); if ($s.Length -gt 120) { $s = $s.Substring(0, 120).Trim() }; $s }
$bak = Join-Path $Raiz '_reemplazados'; $n = 0; $rep = 0; $err = 0; $log = @()
foreach ($f in Get-ChildItem -LiteralPath $Origen -Recurse -File | Where-Object { $_.Extension -in '.flac', '.mp3', '.m4a' }) {
    if ($f.Name -like '.*' -or $f.FullName.StartsWith($bak)) { continue }
    try {
        $j = & $fp -v error -show_format -of json $f.FullName | ConvertFrom-Json
        $t = @{}; $j.format.tags.PSObject.Properties | ForEach-Object { $t[$_.Name.ToLower()] = "$($_.Value)" }
        $p = $f.BaseName -split ' - ', 2
        $artista = if ($t['artist']) { $t['artist'] } elseif ($p.Count -eq 2) { $p[0] } else { 'Desconocido' }
        $carpeta = if ($t['album_artist']) { $t['album_artist'] } elseif ($t['albumartist']) { $t['albumartist'] } else { ($artista -split ',\s*|;\s*|\s+feat\.?\s+')[0] }
        $album = if ($t['album']) { $t['album'] } else { 'Singles' }
        $titulo = if ($t['title']) { $t['title'] } elseif ($p.Count -eq 2) { $p[1] } else { $f.BaseName }
        $dest = Join-Path (Join-Path (Join-Path $Raiz (Limpio $carpeta)) (Limpio $album)) "$(Limpio $artista) - $(Limpio $titulo)$($f.Extension.ToLower())"
        if ($dest -eq $f.FullName) { continue }
        $existe = Test-Path -LiteralPath $dest
        $log += "$(if ($existe) { 'REEMPLAZA' } else { 'MUEVE    ' })  $($f.FullName.Substring($Origen.Length).TrimStart('\'))  ->  $($dest.Substring($Raiz.Length + 1))"
        if ($Aplicar) {
            if ($existe) { $v = Join-Path $bak $dest.Substring($Raiz.Length + 1); New-Item -ItemType Directory -Force (Split-Path $v) | Out-Null; Move-Item -LiteralPath $dest $v -Force; $rep++ }
            New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null; Move-Item -LiteralPath $f.FullName $dest
            $lrc = [IO.Path]::ChangeExtension($f.FullName, '.lrc'); if (Test-Path -LiteralPath $lrc) { Move-Item -LiteralPath $lrc ([IO.Path]::ChangeExtension($dest, '.lrc')) -Force }
        }
        $n++
    } catch { $err++; $log += "ERROR  $($f.FullName): $($_.Exception.Message)" }
}
"$(if ($Aplicar) { 'Movidas' } else { 'Se moverian' }): $n | reemplazan a una vieja: $rep | errores: $err"
$log
