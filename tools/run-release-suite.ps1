<#
.SYNOPSIS
    Runs every host probe in order and writes the evidence the release report
    cites.

.DESCRIPTION
    Illustrator has to be running with the plugin installed. Tracing is turned
    on for the dialog probe, which needs it to see what the artwork did while a
    modal dialog was blocking every other way of asking.

    The crash experiment is not included: it uninstalls and reinstalls the
    plugin, which needs administrator rights and an answer at a prompt. Run
    tools\probe-crash-ab.ps1 separately.
#>
[CmdletBinding()]
param(
    [string] $TracePath = $env:LIVESHEAR_LOG,
    # Leaves out the two probes that take minutes rather than seconds: the
    # stability suite and the shutdown suite. Useful while iterating; never
    # for a release run.
    [switch] $SkipSlow
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
$evidence = Join-Path $repo 'docs\evidence'
$null = New-Item -ItemType Directory -Force -Path $evidence

$summary = New-Object Collections.Generic.List[string]
function Run([string] $name, [scriptblock] $body) {
    Write-Output ''
    Write-Output ('=== {0} ===' -f $name)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $out = & $body 2>&1
        $out | ForEach-Object { Write-Output $_ }
        $tail = ($out | Where-Object { $_ -match 'passed, \d+ failed|cases$' } | Select-Object -Last 1)
        $summary.Add(('{0,-22} {1,7:F0} s  {2}' -f $name, $sw.Elapsed.TotalSeconds, $tail))
    }
    catch {
        $summary.Add(('{0,-22} {1,7:F0} s  ERROR {2}' -f $name, $sw.Elapsed.TotalSeconds, $_.Exception.Message))
        Write-Output ("ERROR: " + $_.Exception.Message)
    }
}

Get-AiApp | Out-Null
Install-AiHarness | Out-Null
Invoke-AiScript 'app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS; while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } app.documents.add(); "ready";' | Out-Null

Write-Output ('Plugin: ' + ((Send-AiMessage version) -replace "`r?`n", ' | '))

Run 'built artifact' { & (Join-Path $PSScriptRoot 'probe-build.ps1') }
Run 'arithmetic'  { & (Join-Path $PSScriptRoot 'run-mathtest.ps1') }
Run 'anchor'      { & (Join-Path $PSScriptRoot 'probe-anchor.ps1') }
Run 'anchor verdicts' { python (Join-Path $PSScriptRoot 'solve-anchor.py') (Join-Path $evidence 'anchor.tsv') }
Run 'release matrix' { & (Join-Path $PSScriptRoot 'probe-release.ps1') }
Run 'matrix verdicts' { python (Join-Path $PSScriptRoot 'solve-release.py') (Join-Path $evidence 'release-matrix.tsv') }
Run 'appearance'  { & (Join-Path $PSScriptRoot 'probe-appearance.ps1') }
Run 'persistence' { & (Join-Path $PSScriptRoot 'probe-persistence.ps1') }
Run 'export'      { & (Join-Path $PSScriptRoot 'probe-export.ps1') }
Run 'fills'       { & (Join-Path $PSScriptRoot 'probe-fills.ps1') }
Run 'limits'      { & (Join-Path $PSScriptRoot 'probe-limits.ps1') }
Run 'dialog'      { & (Join-Path $PSScriptRoot 'probe-dialog.ps1') -TracePath $TracePath }
Run 'undo'        { & (Join-Path $PSScriptRoot 'probe-undo.ps1') }
Run 'preview mode' { & (Join-Path $PSScriptRoot 'probe-gpu.ps1') }
if (-not $SkipSlow) {
    Run 'stability' { & (Join-Path $PSScriptRoot 'probe-stability.ps1') }
    # Shutdown restarts Illustrator four times, which is the other thing a
    # quick pass has no patience for.
    Run 'shutdown' { & (Join-Path $PSScriptRoot 'probe-shutdown.ps1') }
}
Run 'test matrix' { python (Join-Path $PSScriptRoot 'make-test-matrix.py') $evidence (Join-Path $repo 'docs\RELEASE_TEST_MATRIX.md') }
Run 'support matrix' { python (Join-Path $PSScriptRoot 'make-support-matrix.py') $evidence (Join-Path $repo 'docs\SUPPORT_MATRIX.md') }
Run 'registry'    {
    $r = Send-AiMessage registry
    [System.IO.File]::WriteAllText((Join-Path $evidence 'registry.txt'), $r)
    ($r -split "`n" | Select-Object -First 3) -join "`n"
}

Write-Output ''
Write-Output '=== summary ==='
$summary | ForEach-Object { Write-Output $_ }
