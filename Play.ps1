param([switch]$ServerOnly)
$ErrorActionPreference = 'Stop'
$gameRoot = $PSScriptRoot
$gameUrl = 'http://127.0.0.1:9472/'
$alreadyRunning = $false
try {
    $health = Invoke-RestMethod -Uri ($gameUrl + 'health') -TimeoutSec 2
    if ($health.app -eq 'escrow-invaders') { $alreadyRunning = $true }
    else { throw 'Port 9472 is occupied by another service.' }
} catch {
    if ($_.Exception.Message -match 'another service') { throw }
}
if (-not $alreadyRunning) {
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCommand) { throw 'Node.js is needed to serve the local game. Install Node.js, then run Play again.' }
    $logDirectory = Join-Path $gameRoot '.runtime'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $serverFile = Join-Path $gameRoot 'server.mjs'
    $serverProcess = Start-Process -FilePath $nodeCommand.Source -ArgumentList @(('"' + $serverFile + '"')) -WorkingDirectory $gameRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDirectory 'server.log') -RedirectStandardError (Join-Path $logDirectory 'server-error.log')
    $serverProcess.Id | Set-Content -LiteralPath (Join-Path $logDirectory 'server.pid')
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $health = Invoke-RestMethod -Uri ($gameUrl + 'health') -TimeoutSec 1
            if ($health.app -eq 'escrow-invaders') { $alreadyRunning = $true; break }
        } catch { Start-Sleep -Milliseconds 200 }
    }
    if (-not $alreadyRunning) { throw ('The game server did not start. See ' + $logDirectory) }
}
if (-not $ServerOnly) { Start-Process $gameUrl }
Write-Output ('Game ready at ' + $gameUrl)
