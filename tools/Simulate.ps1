param(
    [Parameter(Mandatory=$true)][string]$VsimCommand,
    [ValidateSet('control','voice','scaler')][string]$Case = 'control'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$simRoot = Join-Path $projectRoot 'TD_Project/sim'
$vsimExe = (Resolve-Path -LiteralPath $VsimCommand -ErrorAction Stop).Path
$runFile = 'run_clip_' + $Case + '.do'
Push-Location -LiteralPath $simRoot
try {
    & $vsimExe -c -do ('do ' + $runFile)
    if ($LASTEXITCODE -ne 0) { throw ('Simulation failed, exit code ' + $LASTEXITCODE) }
} finally { Pop-Location }
