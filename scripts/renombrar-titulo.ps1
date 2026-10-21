# Renombra cada cancion a SOLO su titulo ("Artista - Titulo.flac" -> "Titulo.flac"), para reproductores que muestran
# el nombre del archivo. El artista, album, etc. quedan en las etiquetas. El .lrc de al lado se renombra igual.
# Si en la misma carpeta ya hay otro archivo con ese titulo, se agrega " (2)", " (3)"...
# OJO: no usar en la biblioteca principal (las demas herramientas esperan "Artista - Titulo").
# Sin -Aplicar: solo muestra el plan.   Uso: renombrar-titulo.ps1 -Raiz E:\Music -Aplicar
param([Parameter(Mandatory)][string]$Raiz, [switch]$Aplicar)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$dir = Join-Path $env:USERPROFILE 'reportes-musica'
$mf = Get-Content "$dir\metaflac-path.txt"; $ffp = Join-Path (Split-Path (Get-Content "$dir\ffmpeg-path.txt")) 'ffprobe.exe'
function Limpio($s) { ($s -replace '[\\/:*?"<>|]', ' ' -replace '\s+', ' ').Trim().TrimEnd('.') }
function Titulo($f) {
    $t = if ($f.Extension -eq '.flac') { ((& $mf --no-utf8-convert --show-tag=TITLE $f.FullName) | Select-Object -First 1) -replace '^TITLE=', '' }
         else { & $ffp -v error -show_entries format_tags=title -of default=nw=1:nk=1 $f.FullName | Select-Object -First 1 }
    if (-not $t) { $t = ($f.BaseName -split ' - ', 2)[-1] }   # sin etiqueta: lo que va despues de "Artista - "
    Limpio $t
}
$n = 0; $iguales = 0
foreach ($f in Get-ChildItem -LiteralPath $Raiz -Recurse -File | Where-Object { $_.Extension -in '.flac', '.m4a', '.mp3' }) {
    $t = Titulo $f
    if (-not $t -or $t -eq $f.BaseName) { $iguales++; continue }
    $nuevo = $t; $k = 2
    while ((Test-Path -LiteralPath (Join-Path $f.DirectoryName "$nuevo$($f.Extension)")) -and "$nuevo$($f.Extension)" -ne $f.Name) { $nuevo = "$t ($k)"; $k++ }
    "$($f.Name)  ->  $nuevo$($f.Extension)"
    if ($Aplicar) {
        $lrc = [IO.Path]::ChangeExtension($f.FullName, '.lrc')
        Rename-Item -LiteralPath $f.FullName -NewName "$nuevo$($f.Extension)"
        if (Test-Path -LiteralPath $lrc) { Rename-Item -LiteralPath $lrc -NewName "$nuevo.lrc" }
    }
    $n++
}
"Renombradas: $n | ya estaban bien: $iguales$(if (-not $Aplicar) { ' (solo plan; usar -Aplicar)' })"
