[CmdletBinding()]
param(
    [string]$GodotPath = 'godot',
    [string]$TemplatesPath = 'SUPPLY_LOCAL_PATH',
    [string]$NodePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$gameRoot = $PSScriptRoot

function Resolve-GameExecutable {
    param([string]$Candidate, [string]$Description)
    if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Candidate).Path
    }
    $command = Get-Command -Name $Candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw "$Description was not found: $Candidate. Supply its executable path. This script does not download software."
}

function Assert-GameEngineRun {
    param([int]$ExitCode, [string]$LogPath, [string]$Step)
    if ($ExitCode -ne 0) { throw "$Step failed with exit code $ExitCode. See $LogPath" }
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        throw "$Step did not produce its expected log: $LogPath"
    }
    # This host can emit a certificate-store warning even for offline builds.
    # Keep every other engine/script error fatal, including errors with exit 0.
    $failures = @(Get-Content -LiteralPath $LogPath | Where-Object {
        ($_ -match '^(ERROR:|SCRIPT ERROR:)') -and
        ($_ -notmatch '^ERROR: Failed to read the root certificate store\.')
    })
    if ($failures.Count -gt 0) {
        throw ("$Step reported errors. See $LogPath`n" + ($failures -join "`n"))
    }
}

$godotExecutable = Resolve-GameExecutable -Candidate $GodotPath -Description 'Godot'
if (-not (Test-Path -LiteralPath $TemplatesPath -PathType Container)) {
    throw "Template directory was not found: $TemplatesPath. Pass -TemplatesPath with the matching Godot export-template folder."
}
$templateRoot = (Resolve-Path -LiteralPath $TemplatesPath).Path
$debugTemplate = Join-Path $templateRoot 'web_nothreads_debug.zip'
$releaseTemplate = Join-Path $templateRoot 'web_nothreads_release.zip'
foreach ($template in @($debugTemplate, $releaseTemplate)) {
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw "Required web template is missing: $template" }
}

if ([string]::IsNullOrWhiteSpace($NodePath)) {
    $nodeCommand = Get-Command -Name node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nodeCommand) { $NodePath = $nodeCommand.Source }
    else { throw 'Node.js was not found. Install Node.js or pass -NodePath.' }
}
$nodeExecutable = Resolve-GameExecutable -Candidate $NodePath -Description 'Node.js'

$versionOutput = @(& $godotExecutable --headless --version)
if ($LASTEXITCODE -ne 0) { throw 'Godot could not report its version.' }
$godotVersion = $versionOutput | Where-Object { $_ -match '^\d+\.\d+' } | Select-Object -First 1
if (-not $godotVersion) { throw 'Could not identify the Godot engine version.' }
$godotVersion = $godotVersion.Trim()
if ($godotVersion -notmatch '^4\.7\.2\.') {
    throw "This build was verified with Godot 4.7.2; supplied engine reports $godotVersion. Use matching 4.7.2 engine and templates."
}
$templateVersionFile = Join-Path $templateRoot 'version.txt'
if (Test-Path -LiteralPath $templateVersionFile -PathType Leaf) {
    $templateVersion = (Get-Content -LiteralPath $templateVersionFile -Raw).Trim()
    if (-not $godotVersion.StartsWith($templateVersion + '.')) {
        throw "Engine $godotVersion does not match templates $templateVersion."
    }
}

$presetPath = Join-Path $gameRoot 'export_presets.cfg'
$presetText = Get-Content -LiteralPath $presetPath -Raw
foreach ($setting in @(
    @{ Key = 'custom_template/debug'; Value = $debugTemplate },
    @{ Key = 'custom_template/release'; Value = $releaseTemplate }
)) {
    $pattern = '(?m)^' + [regex]::Escape($setting.Key) + '=[^\r\n]*'
    $templateMatches = [regex]::Matches($presetText, $pattern)
    if ($templateMatches.Count -ne 1) { throw "Expected exactly one $($setting.Key) setting in export_presets.cfg." }
    $replacement = $setting.Key + '="' + $setting.Value.Replace('\', '/') + '"'
    $presetText = $presetText.Replace($templateMatches[0].Value, $replacement)
}
[System.IO.File]::WriteAllText($presetPath, $presetText, [System.Text.UTF8Encoding]::new($false))

$runtimeRoot = Join-Path $gameRoot '.runtime'
$buildData = Join-Path $runtimeRoot 'build-data'
$buildLocalData = Join-Path $buildData 'local'
$webRoot = Join-Path $gameRoot 'build/web'
foreach ($directory in @($runtimeRoot, $buildData, $buildLocalData, $webRoot)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
$importLog = Join-Path $runtimeRoot 'build-import.log'
$exportLog = Join-Path $runtimeRoot 'build-export.log'
$webEntry = Join-Path $webRoot 'index.html'
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA

try {
    # Scope editor caches/userdata to this build, without changing machine settings.
    $env:APPDATA = $buildData
    $env:LOCALAPPDATA = $buildLocalData
    Write-Host "Importing with Godot $godotVersion..."
    & $godotExecutable --headless --editor --path $gameRoot --import --log-file $importLog
    Assert-GameEngineRun -ExitCode $LASTEXITCODE -LogPath $importLog -Step 'Asset import'

    Write-Host 'Exporting the Web release...'
    & $godotExecutable --headless --path $gameRoot --export-release Web $webEntry --log-file $exportLog
    Assert-GameEngineRun -ExitCode $LASTEXITCODE -LogPath $exportLog -Step 'Web export'
} finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
}

foreach ($filename in @('index.html', 'index.js', 'index.wasm', 'index.pck')) {
    $artifact = Join-Path $webRoot $filename
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) { throw "Export artifact is missing: $artifact" }
}

& $nodeExecutable (Join-Path $gameRoot 'web/finalize.mjs') $webRoot
if ($LASTEXITCODE -ne 0) { throw 'App manifest/service worker finalization failed.' }

$gzipScript = @'
import fs from 'node:fs';
import path from 'node:path';
import { gzipSync } from 'node:zlib';
const root = path.resolve(process.argv[1]);
for (const name of fs.readdirSync(root)) {
  if (!/\.(?:html|js|wasm|pck)$/.test(name)) continue;
  const file = path.join(root, name);
  if (!fs.statSync(file).isFile()) continue;
  const raw = fs.readFileSync(file);
  const compressed = gzipSync(raw, { level: 9 });
  fs.writeFileSync(file + '.gz', compressed);
  console.log(`${name}: ${raw.length.toLocaleString()} -> ${compressed.length.toLocaleString()} bytes`);
}
'@
Write-Host 'Refreshing gzip copies for the local server...'
& $nodeExecutable --input-type=module --eval $gzipScript $webRoot
if ($LASTEXITCODE -ne 0) { throw 'Gzip generation failed. The uncompressed web export remains in build/web.' }
Write-Host "Build complete: $webEntry"
Write-Host 'Run Play.cmd to open it, or refresh the existing local game tab.'
