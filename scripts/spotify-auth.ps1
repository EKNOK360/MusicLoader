# Login oficial de Spotify (PKCE): no usa contrasena ni Client Secret. Se carga con: . .\spotify-auth.ps1
# Deja disponible la funcion Api y la variable $desk.
param([string]$Scopes = "playlist-modify-private playlist-modify-public", [string]$ClientId = (Get-Content (Join-Path $env:USERPROFILE 'reportes-musica\spotify-client-id.txt') -ErrorAction SilentlyContinue | Select-Object -First 1))
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$desk = (Join-Path $env:USERPROFILE 'reportes-musica'); New-Item -ItemType Directory -Force $desk | Out-Null
$redirect = "http://127.0.0.1:8888/callback"
if (-not $ClientId) { throw "Falta el Client ID de tu app de Spotify: guardalo en $env:USERPROFILE\reportes-musica\spotify-client-id.txt" }

function B64Url($bytes) { [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
function RandomBytes($n) { $b = New-Object byte[] $n; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); $b }
$verifier = B64Url (RandomBytes 48)
$challenge = B64Url ([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier)))
$state = B64Url (RandomBytes 16)

$auth = "https://accounts.spotify.com/authorize?response_type=code&client_id=$ClientId" +
    "&scope=$([uri]::EscapeDataString($Scopes))&redirect_uri=$([uri]::EscapeDataString($redirect))" +
    "&code_challenge_method=S256&code_challenge=$challenge&state=$state"
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 8888)
$listener.Start()
Start-Process $auth
$params = $null
$deadline = (Get-Date).AddMinutes(5)
while (-not $params) {
    if ((Get-Date) -gt $deadline) { $listener.Stop(); throw "No se acepto el permiso en 5 minutos." }
    if (-not $listener.Pending()) { Start-Sleep -Milliseconds 200; continue }
    $client = $listener.AcceptTcpClient()
    $stream = $client.GetStream()
    $line = (New-Object IO.StreamReader($stream)).ReadLine()
    $msg = [Text.Encoding]::UTF8.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/html`r`nConnection: close`r`n`r`n<h2>Listo, puedes cerrar esta ventana y volver con Claude.</h2>")
    $stream.Write($msg, 0, $msg.Length); $client.Close()
    if ($line -match '^GET /callback\?(\S+)') {
        $params = @{}
        foreach ($kv in $Matches[1] -split '&') { $k, $v = $kv -split '=', 2; $params[$k] = [uri]::UnescapeDataString($v) }
    }
}
$listener.Stop()
if ($params.error) { throw "Spotify rechazo el permiso: $($params.error)" }
if ($params.state -ne $state) { throw "Respuesta invalida (state no coincide)." }

$tok = Invoke-RestMethod -Method Post -Uri "https://accounts.spotify.com/api/token" -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ grant_type = 'authorization_code'; code = $params.code; redirect_uri = $redirect; client_id = $ClientId; code_verifier = $verifier }
$h = @{ Authorization = "Bearer $($tok.access_token)" }

function Api($method, $path, $body) {
    $uri = if ($path -like 'http*') { $path } else { "https://api.spotify.com/v1$path" }
    for ($i = 0; $i -lt 5; $i++) {
        try {
            if ($body) {
                $json = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 5))
                return Invoke-RestMethod -Method $method -Uri $uri -Headers $h -ContentType 'application/json; charset=utf-8' -Body $json
            }
            return Invoke-RestMethod -Method $method -Uri $uri -Headers $h
        } catch {
            $r = $_.Exception.Response
            if ($r -and [int]$r.StatusCode -eq 429) { $w = [int]$r.Headers['Retry-After'] + 1; Write-Host "Spotify pide esperar $w segundos ($(Get-Date -Format HH:mm))"; if ($w -gt 900) { throw "Limite de Spotify: hay que esperar $([int]($w/60)) minutos" }; Start-Sleep -Seconds $w; continue }
            throw
        }
    }
}
