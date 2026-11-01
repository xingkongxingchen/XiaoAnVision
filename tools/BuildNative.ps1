param(
    [Parameter(Mandatory=$true)][string]$TdCommand,
    [ValidatePattern('^[a-z0-9]+$')][string]$Tag = 'native01'
)
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path $PSScriptRoot -Parent
$tdExe = (Resolve-Path -LiteralPath $TdCommand).Path
$workRoot = Join-Path $packageRoot ('native_build_' + $Tag)
if (Test-Path -LiteralPath $workRoot) { throw 'Existing build directory is preserved. Use a new -Tag.' }
Copy-Item -LiteralPath (Join-Path $packageRoot 'TD_Project') -Destination $workRoot -Recurse
$savedRoot = [Environment]::GetEnvironmentVariable('XIAOAN_NATIVE_ROOT','Process')
try {
    [Environment]::SetEnvironmentVariable('XIAOAN_NATIVE_ROOT',$workRoot,'Process')
    Push-Location -LiteralPath $workRoot
    try {
        foreach ($phase in @('native_flow.tcl','native_finalize.tcl')) {
            $scriptPath = (Join-Path $PSScriptRoot $phase).Replace('\','/')
            $command = 'if {[catch {source {' + $scriptPath + '}} err]} {puts "NATIVE_BUILD_FAILED: $err"; exit 1}' + "`nexit`n"
            $command | & $tdExe 2>&1 | Tee-Object -FilePath (Join-Path $workRoot ($phase + '.log'))
            if ($LASTEXITCODE -ne 0) { throw ('TD phase failed: ' + $phase) }
        }
        $bit = Join-Path $workRoot 'native_final/XiaoAnVision.bit'
        if (-not (Test-Path -LiteralPath $bit)) { throw 'Timing-qualified bit was not generated.' }
        Write-Output ('Build passed. Bit: ' + $bit)
        Write-Output ('Final timing report: ' + (Join-Path $workRoot 'native_final/route.timing'))
    } finally { Pop-Location }
} finally {
    [Environment]::SetEnvironmentVariable('XIAOAN_NATIVE_ROOT',$savedRoot,'Process')
}
