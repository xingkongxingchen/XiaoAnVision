param(
    [Parameter(Mandatory=$true)][string]$TdCommand,
    [ValidatePattern('^[a-z0-9]+$')][string]$Tag = 'submit01'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$fpgaRoot = Join-Path $projectRoot 'TD_Project'
$tdExe = (Resolve-Path -LiteralPath $TdCommand -ErrorAction Stop).Path
$buildLog = Join-Path $fpgaRoot ('build_' + $Tag + '.log')
if (Test-Path -LiteralPath $buildLog) { throw 'Existing build log is preserved. Use a new -Tag.' }
$buildEnv = @{
    COPY_MAP_MODE='area_prior'; COPY_MAP_STRATEGY='1'; COPY_PACK_EFFORT='high'
    COPY_BUILD_TAG=$Tag; COPY_PLACE_SEED='29'
}
$previousEnv = @{}
foreach($name in $buildEnv.Keys){ $previousEnv[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    foreach($name in $buildEnv.Keys){ [Environment]::SetEnvironmentVariable($name,$buildEnv[$name],'Process') }
    Push-Location -LiteralPath $fpgaRoot
    try {
        $inputTcl = 'if {[catch {source scripts/build_layout.tcl} err]} {puts "BUILD_FAILED: $err"; exit 1}' + "`nexit`n"
        $inputTcl | & $tdExe 2>&1 | Tee-Object -FilePath $buildLog
        $buildExitCode = $LASTEXITCODE
        if ($buildExitCode -ne 0) { throw ('TD build failed, exit code ' + $buildExitCode + '. See ' + $buildLog) }
        Write-Output ('Build completed. Inspect timing reports under ' + (Join-Path $fpgaRoot 'build'))
    } finally { Pop-Location }
} finally {
    foreach($name in $buildEnv.Keys){ [Environment]::SetEnvironmentVariable($name,$previousEnv[$name],'Process') }
}
