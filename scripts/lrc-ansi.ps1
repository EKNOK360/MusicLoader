# Ayuda para .lrc en ANSI (Windows-1252). Se carga con:  . "$PSScriptRoot\lrc-ansi.ps1"
#   TextoAnsi $texto  -> el texto listo para ANSI, o $null si tiene caracteres que no caben (p. ej. griego o japones de verdad)
# - Letras "marcadas": algunas paginas de letras meten letras rusas/griegas identicas a las latinas (е, а, о...) dentro de
#   palabras en espanol/ingles para detectar copias. Solo en palabras MEZCLADAS se cambian por la latina; un texto
#   que de verdad esta en ruso o griego no se toca.
# - ♪ -> ~ ; ′ -> ' (no existen en ANSI).
$script:Homoglifos = @{ [char]0x0430 = 'a'; [char]0x0435 = 'e'; [char]0x043E = 'o'; [char]0x0440 = 'p'; [char]0x0441 = 'c'; [char]0x0443 = 'y'; [char]0x0445 = 'x'; [char]0x0456 = 'i'; [char]0x0458 = 'j'; [char]0x0455 = 's'
    [char]0x0410 = 'A'; [char]0x0415 = 'E'; [char]0x041E = 'O'; [char]0x0420 = 'P'; [char]0x0421 = 'C'; [char]0x0425 = 'X'; [char]0x0406 = 'I'; [char]0x041C = 'M'; [char]0x041D = 'H'; [char]0x0422 = 'T'; [char]0x0412 = 'B'; [char]0x041A = 'K'
    [char]0x03BF = 'o'; [char]0x03B1 = 'a'; [char]0x03B9 = 'i'; [char]0x039F = 'O'; [char]0x0391 = 'A'; [char]0x0395 = 'E'; [char]0x0399 = 'I'; [char]0x039A = 'K'; [char]0x039C = 'M'; [char]0x039D = 'N'; [char]0x03A4 = 'T' }
$script:Ansi1252 = [Text.Encoding]::GetEncoding(1252, [Text.EncoderFallback]::ExceptionFallback, [Text.DecoderFallback]::ExceptionFallback)
function TextoAnsi($t) {
    $sb = New-Object Text.StringBuilder; $i = 0
    foreach ($m in [regex]::Matches($t, '[\p{L}\p{M}]+')) {  # (un MatchEvaluator con scriptblock falla dentro de funciones en PS 5.1)
        [void]$sb.Append($t.Substring($i, $m.Index - $i)); $w = $m.Value
        if ($w -match '[A-Za-z]' -and $w -match '[Ͱ-ӿ]') { foreach ($ch in $w.ToCharArray()) { if ($script:Homoglifos.ContainsKey($ch)) { [void]$sb.Append($script:Homoglifos[$ch]) } else { [void]$sb.Append($ch) } } }
        else { [void]$sb.Append($w) }
        $i = $m.Index + $m.Length
    }
    [void]$sb.Append($t.Substring($i)); $t = $sb.ToString()
    # signos "anchos" de teclados chinos (letras de NetEase): （）＝－＇ -> ()=-' ; 《》「」 -> «» "" ; espacio ideografico -> espacio
    $t = [regex]::Replace($t, '[！-～]', { param($m) [string][char]([int][char]$m.Value - 0xFEE0) })
    $t = $t.Replace([string][char]0x300A, [string][char]0x00AB).Replace([string][char]0x300B, [string][char]0x00BB).Replace([string][char]0x300C, '"').Replace([string][char]0x300D, '"').Replace([string][char]0x3000, ' ')
    $t = $t.Replace([string][char]0x266A, '~').Replace([string][char]0x266B, '~').Replace([string][char]0x2032, "'")
    try { $null = $script:Ansi1252.GetBytes($t); $t } catch { $null }
}
