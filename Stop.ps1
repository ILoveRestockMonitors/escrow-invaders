$ErrorActionPreference = 'Stop'
$pidFile = Join-Path $PSScriptRoot '.runtime/server.pid'
if (-not (Test-Path -LiteralPath $pidFile)) { Write-Output 'No game server launched from this folder.'; exit 0 }
$serverProcessId = [int](Get-Content -LiteralPath $pidFile -Raw).Trim()
$serverProcess = Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $serverProcessId)
if (-not $serverProcess) { Write-Output 'Game server is already stopped.'; exit 0 }
$expectedScript = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'server.mjs'))
if ($serverProcess.Name -ne 'node.exe' -or -not $serverProcess.CommandLine.Contains($expectedScript)) {
    throw 'The saved process is no longer this game server. Nothing was stopped.'
}
Stop-Process -Id $serverProcessId
Write-Output 'Escrow Invaders server stopped. Run Play.cmd to reopen it.'
