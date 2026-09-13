<#
.SYNOPSIS
    Derives the affine transformation that Object > Transform > Shear applies,
    by playing the built-in adobe_shear action on a path with known anchor
    points and reading the points back in Illustrator's own coordinates.

.DESCRIPTION
    Writes one tab-separated record per case to docs\evidence\native-shear.tsv:
    the parameters, the four source anchors and the four result anchors. The
    matrix is solved from those numbers by tools\solve-shear.py.
#>
[CmdletBinding()]
param([string] $OutPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\native-shear.tsv' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

# shear, axis, aboutDX, aboutDY
#
# Angles of 89.9 degrees and above are deliberately absent. tan(89.9) is about
# 573 and tan(90) is unbounded, and playing adobe_shear at those values sends
# Illustrator into a computation that has not returned after several minutes.
# The largest angle that still completes instantly is 89, which is where the
# plugin's own slider stops.
$cases = @(
    @(30, 0, 0, 0), @(-30, 0, 0, 0), @(45, 0, 0, 0), @(10, 0, 0, 0),
    @(30, 90, 0, 0), @(30, 45, 0, 0), @(30, -45, 0, 0), @(30, 30, 0, 0),
    @(30, 180, 0, 0), @(30, 270, 0, 0),
    @(30, 0, 50, 0), @(30, 0, 0, 50), @(30, 0, 0, -50), @(30, 0, -40, 25),
    @(30, 90, 50, 0), @(30, 90, -50, 0), @(30, 90, 0, 50),
    @(30, 45, 50, 50), @(30, 45, -50, -50),
    @(60, 0, 0, 0), @(75, 0, 0, 0), @(85, 0, 0, 0), @(89, 0, 0, 0)
)

function Format-Invariant([double] $value) {
    # The shell may be running under a locale that writes decimal commas, which
    # would make the tab-separated output unparseable.
    $value.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-RectAnchors {
    # Anchors of fixture-rect in Illustrator's internal artwork coordinates,
    # read through the plugin so no ExtendScript coordinate convention is
    # involved.
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
$records.Add("shear`taxis`tdx`tdy`tresult`tbefore`tafter")

foreach ($case in $cases) {
    Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
    Invoke-AiScript -Path (Join-Path $repo 'fixtures\make_fixture.jsx') | Out-Null
    Invoke-AiScript @'
app.executeMenuCommand("deselectall");
app.activeDocument.pathItems.getByName("fixture-rect").selected = true;
'@ | Out-Null

    $before = Get-RectAnchors
    $spec = '{0},{1},{2},{3},0,1,0' -f $case[0], $case[1], $case[2], $case[3]
    $reply = (Send-AiMessage 'native shear' $spec).TrimEnd()
    $result = if ($reply -match 'result (-?\d+)') { $Matches[1] } else { '?' }
    $after = Get-RectAnchors

    $records.Add(("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}" -f $case[0], $case[1], $case[2], $case[3], $result, $before, $after))
    Write-Output ("shear={0,-6} axis={1,-5} dx={2,-4} dy={3,-4} result={4}" -f $case[0], $case[1], $case[2], $case[3], $result)
}

Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
Save-ProbeTranscript -Path $OutPath -Lines $records
Write-Output "`nWritten to $OutPath"
