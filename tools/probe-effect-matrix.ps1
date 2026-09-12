<#
.SYNOPSIS
    Measures the affine map a live effect actually renders.

.DESCRIPTION
    A live effect leaves the source geometry alone, so its transformation can
    only be read out of the rendered result. Each case applies an effect to the
    fixture rectangle, expands the appearance into real geometry, and records
    the anchor points before and after. tools/solve-shear.py turns those into a
    matrix.

    Cases are given as "effectName|paramSpec" strings, using the plugin's
    typed parameter syntax (r: real, i: integer, b: boolean, s: string).
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [string[]] $Case
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\effect-matrix.tsv' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

if (-not $Case) {
    $Case = @(
        # Our own effect, across the interesting parameter space.
        'VulpesNexus Shear|shearAngle=r:30',
        'VulpesNexus Shear|shearAngle=r:-30',
        'VulpesNexus Shear|shearAngle=r:45',
        'VulpesNexus Shear|shearAngle=r:30;axisAngle=r:90',
        'VulpesNexus Shear|shearAngle=r:30;axisAngle=r:45',
        'VulpesNexus Shear|shearAngle=r:30;axisAngle=r:-45',
        'VulpesNexus Shear|shearAngle=r:30;axisAngle=r:30',
        # The built-in Transform effect. Its dictionary stores the angle in both
        # degrees and radians and the scale as both a percentage and a factor;
        # part of the point of these cases is to find out which form the
        # renderer actually reads. The reflect flag is pinned off explicitly
        # because an absent one does not behave as if it were false.
        'Adobe Transform|',
        'Adobe Transform|reflect=b:false',
        'Adobe Transform|reflect=b:false;moveH_Pts=r:40',
        'Adobe Transform|reflect=b:false;moveV_Pts=r:25',
        'Adobe Transform|reflect=b:false;rotate_Degrees=r:30',
        'Adobe Transform|reflect=b:false;rotate_Radians=r:0.5235987755982988',
        'Adobe Transform|reflect=b:false;scaleH_Percent=r:150',
        'Adobe Transform|reflect=b:false;scaleH_Factor=r:1.5',
        'Adobe Transform|reflect=b:false;scaleV_Factor=r:0.5',
        'Adobe Transform|reflect=b:false;scaleH_Factor=r:1.5;scaleV_Factor=r:0.5',
        'Adobe Transform|reflect=b:true;reflectX=b:true',
        'Adobe Transform|reflect=b:true;reflectY=b:true',
        'Adobe Transform|reflect=b:false;scaleH_Factor=r:1.5;rotate_Radians=r:0.5235987755982988',
        'Adobe Transform|reflect=b:false;scaleH_Factor=r:1.5;scaleV_Factor=r:0.5;rotate_Radians=r:0.5235987755982988;moveH_Pts=r:40;moveV_Pts=r:25',
        'Adobe Transform|reflect=b:false;scaleH_Factor=r:1.5;pinPoint=i:0',
        'Adobe Transform|reflect=b:false;scaleH_Factor=r:1.5;pinPoint=i:8'
    )
}

function Format-Invariant([double] $value) {
    # The shell may be running under a locale that writes decimal commas, which
    # would make the tab-separated output unparseable.
    $value.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-Anchors {
    $dump = Send-AiMessage geometry
    $points = @()
    foreach ($line in ($dump -split "`n")) {
        if ($line -match '^\s+seg \d+ p=\(([-0-9.]+), ([-0-9.]+)\)') {
            $points += ((Format-Invariant ([double]$Matches[1])) + ',' + (Format-Invariant ([double]$Matches[2])))
        }
    }
    $points -join ' '
}

$records = New-Object Collections.Generic.List[string]
$records.Add("effect`tparams`tdx`tdy`tapplied`tbefore`tafter")

foreach ($spec in $Case) {
    $parts = $spec.Split('|', 2)
    $effect = $parts[0]
    $params = if ($parts.Length -gt 1) { $parts[1] } else { '' }

    Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
    Invoke-AiScript -Path (Join-Path $repo 'fixtures\make_probe_shape.jsx') | Out-Null

    $before = Get-Anchors
    $applied = (Send-AiMessage 'apply effect' ('{0}|{1}' -f $effect, $params)).TrimEnd()

    # A style applied through the SDK is not evaluated until something needs to
    # draw it, and Expand Appearance will otherwise expand the stale result.
    Invoke-AiScript 'app.redraw();' | Out-Null

    # Expand the appearance so the rendered result becomes readable geometry.
    Invoke-AiScript 'app.executeMenuCommand("expandStyle");' | Out-Null
    Invoke-AiScript 'app.executeMenuCommand("selectall");' | Out-Null
    $after = Get-Anchors

    $ok = if ($applied -match 'to (\d+) of') { $Matches[1] } else { '?' }
    $records.Add(("{0}`t{1}`t0`t0`t{2}`t{3}`t{4}" -f $effect, $params, $ok, $before, $after))
    Write-Output ("{0,-22} {1,-70} applied={2}" -f $effect, $params, $ok)
}

Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
[System.IO.File]::WriteAllLines($OutPath, $records)
Write-Output "`nWritten to $OutPath"
