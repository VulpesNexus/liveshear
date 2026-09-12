<#
.SYNOPSIS
    Runs the release test matrix: every art type against Illustrator's own shear.

.DESCRIPTION
    For each case the harness builds the fixture twice, gives one copy the live
    Shear effect and the other Illustrator's destructive Shear command with the
    same angles, and reports both sets of visible bounds along with the live
    copy's path anchors before and after.

    Two questions are answered at once. Do we render what the native command
    renders, and did the effect leave the source geometry alone. tools\solve-
    release.py turns the raw numbers into verdicts.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [string[]] $Case
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\release-matrix.tsv' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

if (-not $Case) {
    $shapes = @('plainRect', 'strokedRect', 'spike', 'roundJoin', 'bevelJoin', 'dashedStroke',
                'bezier', 'openPath', 'compound', 'selfIntersecting',
                'mixedGroup', 'nestedGroup', 'clipGroup', 'transformedGroup',
                'pointText', 'areaText', 'multilineText', 'strokedText',
                'symbolInstance', 'gradientFill', 'radialFill', 'patternFill',
                'calligraphicBrush', 'artBrush', 'patternBrush',
                'rotatedRect', 'scaledRect', 'reflectedRect', 'preShearedRect',
                'tinyPath', 'hugePath', 'farFromOrigin', 'negativeCoords',
                'zeroHeight', 'zeroWidth', 'singleAnchor', 'manyChildren')
    $Case = @()
    foreach ($s in $shapes) { $Case += "${s}:30:0" }
    # A second and third angle on a representative spread, so a fixture that
    # only happens to work at one setting cannot pass.
    foreach ($s in @('plainRect', 'spike', 'mixedGroup', 'pointText', 'compound', 'clipGroup')) {
        $Case += "${s}:-20:90"
        $Case += "${s}:45:37.5"
    }
    # The numerical edges of the accepted range.
    foreach ($a in @('0', '0.000001', '0.001', '88', '88.9', '89', '-89', '-0.001')) {
        $Case += "plainRect:${a}:0"
    }
}

Install-AiHarness | Out-Null

$records = New-Object Collections.Generic.List[string]
$records.Add("fixture`tshear`taxis`tgeometric`tliveVisible`tnativeVisible`tanchorsBefore`tanchorsAfter`tapplied`toracle")

foreach ($spec in $Case) {
    $parts = $spec.Split(':')
    $name = $parts[0]; $shear = $parts[1]; $axis = $parts[2]
    try {
        # Each step is its own call. The action manager does not see a selection
        # made in the same script, so the native shear has to be played after
        # Illustrator has been back to its event loop with the oracle selected;
        # see LS.compareBegin in harness.jsx.
        Invoke-AiScript "LS.compareBegin('$name');" | Out-Null
        Invoke-AiScript "LS.compareApplyLive($shear, $axis);" | Out-Null

        # The shear action reports success whether or not it did anything, and
        # has been seen to do nothing for a run of attempts in a long session.
        # So the oracle is checked, retried, and finally reported as not moved
        # rather than compared against unsheared artwork.
        # Below a hundredth of a degree the native shear moves the geometry by
        # less than Illustrator will report, so there is nothing to check for.
        $moved = [math]::Abs([double] $shear) -lt 0.01
        for ($attempt = 1; $attempt -le 3 -and -not $moved; $attempt++) {
            Invoke-AiScript 'LS.compareSelectOracle();' | Out-Null
            Invoke-AiScript 'app.redraw();' | Out-Null
            if ($attempt -gt 1) { Invoke-AiScript 'LS.send("selection");' | Out-Null }
            $moved = (Invoke-AiScript "LS.compareShearOracle($shear, $axis);") -match 'moved'
        }
        Invoke-AiScript ("LS.oracleMoved = {0};" -f $moved.ToString().ToLower()) | Out-Null
        $row = (Invoke-AiScript "LS.compareRow($shear, $axis);").TrimEnd()
        $records.Add($row)
        Write-Output ("{0,-20} shear {1,-10} axis {2,-6} measured" -f $name, $shear, $axis)
    }
    catch {
        $records.Add(("{0}`t{1}`t{2}`tERROR`t`t`t`t`t{3}`t" -f $name, $shear, $axis, $_.Exception.Message))
        Write-Output ("{0,-20} shear {1,-10} axis {2,-6} ERROR: {3}" -f $name, $shear, $axis, $_.Exception.Message)
    }
}

Invoke-AiScript 'LS.clear(); "cleared";' | Out-Null
[System.IO.File]::WriteAllLines($OutPath, $records)
Write-Output "`nWritten to $OutPath"
