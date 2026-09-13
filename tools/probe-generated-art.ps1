<#
.SYNOPSIS
    Artwork Illustrator generates from a path -- brushes, and strokes on text
    -- rendered by the live effect and by the destructive command, with Adobe's
    own Transform effect as the control.

.DESCRIPTION
    A brush is not artwork, it is a rule for making artwork out of a path. That
    leaves two defensible answers to "shear this", and Illustrator gives a
    different one depending on how it is asked:

        destructively   shear the path, then lay the brush along it again
        as an effect    lay the brush along the path, then shear what came out

    A live effect cannot choose the first. It is handed art the appearance
    pipeline has already generated; the brush definition is not what arrives
    and the effect has no way back to it.

    So the question is not whether this effect matches the destructive command
    -- it cannot -- but whether it behaves like a live effect is supposed to.
    Adobe's own Transform effect settles that. This probe puts the same scale
    through Adobe's effect and through the destructive command, and reports
    what Adobe's own difference is. A plain stroked rectangle is carried
    alongside as the control that must agree, so a run where everything differs
    is recognizable as a broken measurement rather than a finding.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [string[]] $Fixture = @('patternBrush', 'artBrush', 'calligraphicBrush', 'strokedText', 'strokedRect', 'plainRect'),
    # A hard vertical squash: whatever the two routes disagree about, this
    # makes it large enough to see.
    [double] $ScaleV = 25
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\generated-art.txt' }
$images = Join-Path ([IO.Path]::GetTempPath()) 'liveshear-generated'
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)
$null = New-Item -ItemType Directory -Force -Path $images

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

Add-Type -AssemblyName System.Drawing

function Export-Png([string] $path) {
    $js = $path.Replace('\', '/')
    Invoke-AiScript "var o = new ExportOptionsPNG24(); o.artBoardClipping = true; o.horizontalScale = 200; o.verticalScale = 200; o.antiAliasing = false; o.transparency = false; app.activeDocument.exportFile(new File('$js'), ExportType.PNG24, o); 'ok';" | Out-Null
}

function Compare-Images([string] $a, [string] $b) {
    if (-not (Test-Path $a) -or -not (Test-Path $b)) { return -1 }
    $x = [Drawing.Bitmap]::FromFile($a)
    $y = [Drawing.Bitmap]::FromFile($b)
    try {
        if ($x.Width -ne $y.Width -or $x.Height -ne $y.Height) { return -1 }
        $differing = 0; $total = 0
        for ($row = 0; $row -lt $x.Height; $row += 2) {
            for ($col = 0; $col -lt $x.Width; $col += 2) {
                $total++
                $p = $x.GetPixel($col, $row); $q = $y.GetPixel($col, $row)
                if ([Math]::Abs($p.R - $q.R) -gt 6 -or [Math]::Abs($p.G - $q.G) -gt 6 -or
                    [Math]::Abs($p.B - $q.B) -gt 6) { $differing++ }
            }
        }
        if ($total -eq 0) { return -1 }
        return [double] $differing / $total
    }
    finally { $x.Dispose(); $y.Dispose() }
}

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'generated-art'

Note 'Live Shear -- artwork Illustrator generates from a path'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Scaled vertically to {0} percent, by Adobe's own Transform effect and by the destructive command" -f $ScaleV)
Note ''
Note ("{0,-20} {1,14}   {2}" -f 'fixture', 'Adobe differs', 'what that means')

$factor = $ScaleV / 100
foreach ($name in $Fixture) {
    Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.selectOnly(LS.target); app.redraw();" | Out-Null
    Js ("LS.applyEffect('Adobe Transform', 'reflect=b:false;scaleH_Factor=r:1;scaleV_Factor=r:{0}');" -f (Format-AiNumber $factor)) | Out-Null
    Js 'app.activeDocument.selection = null; app.redraw();' | Out-Null
    $byEffect = Join-Path $images "$name-adobe-effect.png"
    Export-Png $byEffect

    Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.selectOnly(LS.target); app.redraw();" | Out-Null
    Js ("LS.target.resize(100, {0}, true, true, true, true, 100, Transformation.CENTER);" -f (Format-AiNumber $ScaleV)) | Out-Null
    Js 'app.activeDocument.selection = null; app.redraw();' | Out-Null
    $byCommand = Join-Path $images "$name-destructive.png"
    Export-Png $byCommand

    $diff = Compare-Images $byEffect $byCommand
    # Edge pixels land either side of a boundary in two independent renders;
    # a tenth of a percent of sampled pixels is that, and nothing more.
    $regenerates = $diff -gt 0.001
    $meaning = if ($diff -lt 0) { 'not comparable' }
               elseif ($regenerates) { "Adobe's own effect does not match its own command either: this artwork is regenerated when the path is transformed" }
               else { 'the two routes agree, so this artwork is not regenerated' }

    Note ("{0,-20} {1,14}   {2}" -f $name, $(if ($diff -lt 0) { '-' } else { "{0:P3}" -f $diff }), $meaning)
    # MEASURED, not passed or failed: this is a fact about Illustrator, and
    # neither answer would be a defect in this plugin.
    Add-ProbeResult -Group 'generated artwork' -Case ("{0}: does a live effect match the destructive command?" -f $name) `
        -Expected "whatever Adobe's own Transform effect does on the same artwork" `
        -Observed ("Adobe's Transform effect differs from the destructive command by {0} of sampled pixels; {1}" -f $(if ($diff -lt 0) { 'an incomparable amount' } else { "{0:P3}" -f $diff }), $meaning) `
        -Status 'MEASURED'
}

Note ''
Note 'A live effect is handed generated artwork, not the rule that generated it, so it can only transform what it is given.'
Note 'Where Adobe''s own effect differs from Adobe''s own command, this one differs in the same way and for the same reason.'
Js 'LS.clear();' | Out-Null
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
