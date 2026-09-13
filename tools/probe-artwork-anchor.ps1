<#
.SYNOPSIS
    For every kind of artwork: where does Illustrator's own shear anchor, and
    does the effect anchor in the same place?

.DESCRIPTION
    tools/probe-anchor.ps1 answers which box the native command measures, by
    fitting a line through path anchors the command actually moved. That is
    exact, and it is useless for text, symbols and rasters, which have no path
    anchors to fit.

    This probe recovers the same number a different way, one that works for any
    art at all. Two shears of the same angle about different reference points
    differ by a pure translation and nothing else:

        x' = x + (y - c) * tan(t)      so     dx = (c_effect - c_native) * tan(t)

    So shear one copy with the effect, shear another with the native command,
    and subtract the two bounding boxes. Along axis 0 the vertical edges must
    not have moved at all and the two horizontal ones must have moved together;
    when they do, the difference divided by tan(t) is exactly how far apart the
    two reference points are. When they do not, the difference is not a
    reference-point difference and the probe says so instead of reporting a
    number that would mean nothing.

    An offset of zero is agreement. A non-zero offset is reported in points,
    with the fixture's own geometric and visible bounds beside it, so that an
    art type whose native semantics differ from a path's can be recognised
    rather than merely counted as a failure.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [double] $Angle = 30,
    [string[]] $Fixture = @(
        # paths, as the control: these are known to agree
        'plainRect', 'strokedRect', 'spike', 'bezier', 'openPath', 'compound',
        'selfIntersecting',
        # groups
        'mixedGroup', 'nestedGroup', 'clipGroup', 'transformedGroup',
        # text
        'pointText', 'areaText', 'multilineText', 'strokedText',
        'asymmetricText', 'retypedText', 'resizedText',
        # generated artwork
        'symbolInstance', 'calligraphicBrush', 'artBrush', 'patternBrush',
        'embeddedRaster',
        # transformed source art
        'rotatedRect', 'scaledRect', 'reflectedRect'
    )
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\artwork-anchor.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }
function Nums([string] $csv) { $csv -split ',' | ForEach-Object { [double] $_ } }
function Num([double] $v) { $v.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture) }

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'artwork-anchor'

$tan = [Math]::Tan($Angle * [Math]::PI / 180)
# A five-hundredth of a point.
#
# Illustrator reports text bounds through a narrower float than it computes
# them in, and the residue is visible in the numbers: the differences that turn
# up on text are 0.000488 and 0.000977 pt, which are 1/2048 and 1/1024 exactly.
# Those are not measurements of anything, they are the last bit of a float32.
#
# 0.005 pt is about two microns, some four hundred times finer than a 2400 dpi
# imagesetter can place a dot, and it is still two hundred times smaller than
# the smallest real difference this probe has found. Nothing can hide under it.
$tolerance = 5.0e-3

Note 'Live Shear -- the reference point, one kind of artwork at a time'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Shearing {0} degrees; an offset is how far the native reference point sits from the effect's, in points" -f $Angle)
Note ''
Note ("{0,-20} {1,-5} {2,12} {3,12} {4,12}   {5}" -f 'fixture', 'axis', 'offset pt', 'edge drift', 'cross drift', 'verdict')

$counts = @{}
foreach ($name in $Fixture) {
    foreach ($axis in @(0, 90)) {
        $exists = Js "(typeof LS.fixtures['$name'] === 'function') ? 'yes' : 'no';"
        if ($exists -ne 'yes') {
            Note ("{0,-20} {1,-5} {2,12} {3,12} {4,12}   {5}" -f $name, $axis, '-', '-', '-', 'NO SUCH FIXTURE')
            $counts['NO SUCH FIXTURE'] = [int] $counts['NO SUCH FIXTURE'] + 1
            continue
        }

        # --- the effect ---
        Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
        Js 'app.redraw();' | Out-Null
        $plainBounds = Js 'LS.bounds(LS.named("subject"));'
        Js ("LS.shear({0}, {1});" -f (Format-AiNumber $Angle), $axis) | Out-Null
        Js 'app.redraw();' | Out-Null
        $live = Nums (Js 'LS.vb(LS.named("subject"));')

        # --- the native command ---
        Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
        Js 'app.redraw();' | Out-Null
        $moved = 'did not move'
        for ($attempt = 0; $attempt -lt 3 -and $moved -eq 'did not move'; $attempt++) {
            $moved = Js ("LS.nativeShearChecked('subject', {0}, {1});" -f (Format-AiNumber $Angle), $axis)
        }
        if ($moved -eq 'did not move') {
            Note ("{0,-20} {1,-5} {2,12} {3,12} {4,12}   {5}" -f $name, $axis, '-', '-', '-', 'INCONCLUSIVE (the oracle would not shear)')
            $counts['INCONCLUSIVE'] = [int] $counts['INCONCLUSIVE'] + 1
            Add-ProbeResult -Group 'reference point by artwork' -Case ("{0}, axis {1}" -f $name, $axis) `
                -Expected 'the effect and the native command anchor in the same place' `
                -Observed 'Illustrator''s own shear reported success and left the artwork untouched after three attempts' -Status 'INCONCLUSIVE'
            continue
        }
        $native = Nums (Js 'LS.vb(LS.named("subject"));')

        # visibleBounds is [left, top, right, bottom]
        $dLeft   = $native[0] - $live[0]
        $dTop    = $native[1] - $live[1]
        $dRight  = $native[2] - $live[2]
        $dBottom = $native[3] - $live[3]

        if ($axis -eq 0) {
            # A horizontal shear moves x and leaves y alone.
            $along = @($dLeft, $dRight)
            $across = @($dTop, $dBottom)
        }
        else {
            $along = @($dTop, $dBottom)
            $across = @($dLeft, $dRight)
        }

        $edgeDrift = [Math]::Abs($along[0] - $along[1])       # do both edges agree?
        $crossDrift = [Math]::Max([Math]::Abs($across[0]), [Math]::Abs($across[1]))
        $shift = ($along[0] + $along[1]) / 2
        $offset = if ($tan -ne 0) { $shift / $tan } else { [double]::NaN }

        if ($edgeDrift -gt $tolerance -or $crossDrift -gt $tolerance) {
            # The two results do not differ by a translation, so whatever is
            # different about them is not where they were anchored.
            $verdict = 'NOT A REFERENCE-POINT DIFFERENCE'
            $status = 'FAIL'
            $observed = ("the two results differ by more than a translation: the two {0} edges disagree by {1} pt and the {2} edges moved by {3} pt, so the difference is in what was transformed rather than in where it was anchored" -f `
                $(if ($axis -eq 0) { 'horizontal' } else { 'vertical' }), (Num $edgeDrift),
                $(if ($axis -eq 0) { 'vertical' } else { 'horizontal' }), (Num $crossDrift))
        }
        elseif ([Math]::Abs($shift) -le $tolerance) {
            $verdict = 'SAME REFERENCE POINT'
            $status = 'PASS'
            $observed = ("the two agree to {0} pt" -f (Num ([Math]::Abs($shift))))
        }
        else {
            $verdict = ("OFFSET {0} pt" -f (Num $offset))
            $status = 'FAIL'
            $observed = ("the native reference point sits {0} pt from the effect's along {1}; the fixture's geometric and visible bounds are {2}" -f `
                (Num $offset), $(if ($axis -eq 0) { 'y' } else { 'x' }), $plainBounds)
        }

        $counts[$verdict -replace ' -?[0-9.]+ pt', ''] = [int] $counts[$verdict -replace ' -?[0-9.]+ pt', ''] + 1
        Note ("{0,-20} {1,-5} {2,12} {3,12} {4,12}   {5}" -f $name, $axis, (Num $offset), (Num $edgeDrift), (Num $crossDrift), $verdict)
        Add-ProbeResult -Group 'reference point by artwork' -Case ("{0}, axis {1}" -f $name, $axis) `
            -Expected 'the effect and the native command anchor in the same place' -Observed $observed -Status $status
    }
}

Note ''
foreach ($k in ($counts.Keys | Sort-Object)) { Note ("{0,-40} {1}" -f $k, $counts[$k]) }
Js 'LS.clear();' | Out-Null
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
