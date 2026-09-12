<#
.SYNOPSIS
    Measures which bounding box Illustrator's own shear command anchors on.

.DESCRIPTION
    A shear along the horizontal axis displaces x in proportion to the distance
    from the anchor's y, and leaves y alone; along the vertical axis it does the
    reverse. So one run at axis 0 recovers the anchor's y and one at axis 90
    recovers its x, by fitting a straight line through the recorded anchor
    points. Comparing that against the fixture's geometric and visible bounds
    answers the question the report has to answer.

    The shear action resolves "about the center" from a cached selection
    bounding box which a scripted selection does not refresh, so every case
    plays a zero-angle shear first; see LS.nativeShearPrimed in harness.jsx.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [string[]] $Fixture = @('plainRect', 'strokedRect', 'spike', 'mixedGroup', 'bezier')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\anchor.tsv' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

Install-AiHarness | Out-Null

$records = New-Object Collections.Generic.List[string]
$records.Add("fixture`taxis`tgeometric`tvisible`tbefore`tafter")

foreach ($axis in @(0, 90)) {
    foreach ($name in $Fixture) {
        Invoke-AiScript "LS.clear(); LS.target = LS.fixtures['$name'](); LS.selectOnly(LS.target); 'built';" | Out-Null
        # A round trip of its own, so the selection cache is up to date before
        # the action reads it.
        Invoke-AiScript 'app.redraw(); "drawn";' | Out-Null
        $bounds = (Invoke-AiScript 'LS.bounds(LS.target);').Trim()
        $before = (Invoke-AiScript 'LS.anchors();').Trim()
        Invoke-AiScript "LS.nativeShearPrimed(30, $axis);" | Out-Null
        Invoke-AiScript 'app.redraw(); "drawn";' | Out-Null
        $after = (Invoke-AiScript 'LS.anchors();').Trim()

        $parts = $bounds.Split(';')
        $records.Add(("{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f $name, $axis, $parts[0], $parts[1], $before, $after))
        Write-Output ("{0,-14} axis {1,-3} measured" -f $name, $axis)
    }
}

Invoke-AiScript 'LS.clear(); "cleared";' | Out-Null
[System.IO.File]::WriteAllLines($OutPath, $records)
Write-Output "`nWritten to $OutPath"
