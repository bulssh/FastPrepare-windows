<#
    Tests pour l'intégration continue : chaque fichier de tests est lancé dans son propre
    processus Windows PowerShell, avec un délai maximal. Un fichier qui se bloque est arrêté et
    signalé, sans empêcher les autres. Affiche les tests en échec, puis un bilan.

    Usage : tools\Invoke-TestsCi.ps1 [-TimeoutSeconds 300] [-Filter '*Step*']
#>
[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 300,
    [string]$Filter = '*.Tests.ps1'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'tools\out'
if (-not (Test-Path -LiteralPath $out)) { New-Item -ItemType Directory -Path $out | Out-Null }

$runner = Join-Path $out 'run-one.ps1'
Set-Content -LiteralPath $runner -Encoding UTF8 -Value @'
param([string]$File, [string]$ResultPath)
Import-Module Pester -MinimumVersion 5.0 -Force
$configuration = New-PesterConfiguration
$configuration.Run.Path = $File
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'None'
$result = Invoke-Pester -Configuration $configuration
$lines = @("TOTAL passed=$($result.PassedCount) failed=$($result.FailedCount) skipped=$($result.SkippedCount) containersFailed=$($result.FailedContainersCount)")
foreach ($test in $result.Failed) { $lines += ("ECHEC {0} :: {1}" -f $test.ExpandedPath, (($test.ErrorRecord | ForEach-Object { $_.Exception.Message }) -join ' | ')) }
foreach ($container in $result.Containers) {
    if ($container.Result -eq 'Failed' -and $container.ErrorRecord) { $lines += ("CONTENEUR {0}" -f (($container.ErrorRecord | ForEach-Object { $_.Exception.Message }) -join ' | ')) }
}
[System.IO.File]::WriteAllLines($ResultPath, $lines)
'@

$files = @(Get-ChildItem -Path (Join-Path $root 'tests') -Filter $Filter -Recurse | Sort-Object -Property FullName)
$summary = New-Object System.Collections.Generic.List[string]
$failed = $false
foreach ($file in $files) {
    $resultPath = Join-Path $out ($file.BaseName + '.result.txt')
    if (Test-Path -LiteralPath $resultPath) { Remove-Item -LiteralPath $resultPath -Force }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$runner`"", '-File', "`"$($file.FullName)`"", '-ResultPath', "`"$resultPath`"")
    $finished = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) {
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        $summary.Add(('BLOQUE   {0} (arrêté après {1} s)' -f $file.Name, $TimeoutSeconds))
        $failed = $true
        continue
    }
    $seconds = [int]$watch.Elapsed.TotalSeconds
    if (-not (Test-Path -LiteralPath $resultPath)) {
        $summary.Add(('ERREUR   {0} (aucun résultat, code {1}, {2} s)' -f $file.Name, $process.ExitCode, $seconds))
        $failed = $true
        continue
    }
    $lines = @(Get-Content -LiteralPath $resultPath -Encoding UTF8)
    $bad = @($lines | Where-Object { $_ -match '^(ECHEC|CONTENEUR)' })
    if ($bad.Count -gt 0) { $failed = $true }
    $summary.Add(('{0} {1} — {2} ({3} s)' -f $(if ($bad.Count -gt 0) { 'ECHEC   ' } else { 'OK      ' }), $file.Name, $lines[0], $seconds))
    foreach ($line in $bad) { $summary.Add('    ' + $line) }
}

Write-Output ''
Write-Output '===== BILAN ====='
$summary | ForEach-Object { Write-Output $_ }
if ($failed) { exit 1 }
