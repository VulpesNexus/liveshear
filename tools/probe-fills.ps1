<#
.SYNOPSIS
    Do gradients and patterns shear with the artwork? Answered in pixels.

.DESCRIPTION
    Every other comparison in the suite is made on visible bounds, which is what
    lets text and symbols be measured the same way as a rectangle. Bounds cannot
    see inside the shape, though: a gradient ramp that failed to shear, or a
    pattern that stayed upright while its object leaned, would leave the bounds
    exactly where they were and pass.

    So this one renders. Each fixture is built twice into identically framed
    documents, one sheared by the live effect and one by Illustrator's own
    command, both exported to PNG at the same size, and the two images are
    compared pixel by pixel.

    Illustrator's Shear dialog has a Patterns option, so the native side is run
    both ways and the probe reports which one the effect agrees with rather
    than assuming.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [string] $ImageFolder,
    [string[]] $Fixture = @('gradientFill', 'radialFill', 'patternFill'),
    [double] $ShearAngle = 30,
    [double] $AxisAngle = 0
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\fills.txt' }
if (-not $ImageFolder) { $ImageFolder = Join-Path ([IO.Path]::GetTempPath()) 'liveshear-fills' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)
$null = New-Item -ItemType Directory -Force -Path $ImageFolder

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

Add-Type -AssemblyName System.Drawing

function Compare-Images([string] $a, [string] $b) {
    if (-not (Test-Path $a) -or -not (Test-Path $b)) { return -1 }
    $x = [System.Drawing.Bitmap]::FromFile($a)
    $y = [System.Drawing.Bitmap]::FromFile($b)
    try {
        if ($x.Width -ne $y.Width -or $x.Height -ne $y.Height) { return -1 }
        $differing = 0
        $total = 0
        for ($row = 0; $row -lt $x.Height; $row += 2) {
            for ($col = 0; $col -lt $x.Width; $col += 2) {
                $total++
                $p = $x.GetPixel($col, $row)
                $q = $y.GetPixel($col, $row)
                # A few levels of tolerance per channel: the two routes reach
                # the same geometry by different arithmetic, and the rasterizer
                # is entitled to land a boundary pixel either side.
                if ([Math]::Abs($p.R - $q.R) -gt 6 -or
                    [Math]::Abs($p.G - $q.G) -gt 6 -or
                    [Math]::Abs($p.B - $q.B) -gt 6 -or
                    [Math]::Abs($p.A - $q.A) -gt 6) { $differing++ }
            }
        }
        if ($total -eq 0) { return -1 }
        return [double] $differing / $total
    }
    finally { $x.Dispose(); $y.Dispose() }
}

function Export-Png([string] $path) {
    $js = $path.Replace('\', '\\')
    Invoke-AiScript "var o = new ExportOptionsPNG24(); o.artBoardClipping = true; o.horizontalScale = 200; o.verticalScale = 200; o.antiAliasing = false; o.transparency = false; app.activeDocument.exportFile(new File('$js'), ExportType.PNG24, o); 'exported';" | Out-Null
}

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'fills'

Note 'Live Shear -- do gradients and patterns shear with the artwork?'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Shear {0} degrees, axis {1}; images at 200 percent, antialiasing off" -f $ShearAngle, $AxisAngle)
Note ''

$pass = 0
$fail = 0
foreach ($name in $Fixture) {
    # --- the live effect ---
    Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.selectOnly(LS.target);" | Out-Null
    Js 'app.redraw();' | Out-Null
    Js ("LS.shear({0}, {1});" -f $ShearAngle, $AxisAngle) | Out-Null
    Js 'app.activeDocument.selection = null; app.redraw();' | Out-Null
    $live = Join-Path $ImageFolder "$name-effect.png"
    Export-Png $live

    $results = @{}
    foreach ($patterns in @(1, 0)) {
        Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.selectOnly(LS.target);" | Out-Null
        Js 'app.redraw();' | Out-Null
        # A separate call, because the action cannot see a selection made in
        # the same one, and a zero-angle pass first, because it reads a cached
        # selection box that a scripted selection does not refresh.
        Js "LS.send('native shear', '0,0,0,0,0,1,$patterns');" | Out-Null
        $moved = Js ("LS.send('native shear', '{0},{1},0,0,0,1,{2}');" -f $ShearAngle, $AxisAngle, $patterns)
        Js 'app.activeDocument.selection = null; app.redraw();' | Out-Null
        $native = Join-Path $ImageFolder ("{0}-native-patterns{1}.png" -f $name, $patterns)
        Export-Png $native
        $results[$patterns] = Compare-Images $live $native
    }

    $withPatterns = $results[1]
    $withoutPatterns = $results[0]
    $best = if ($withPatterns -ge 0 -and ($withoutPatterns -lt 0 -or $withPatterns -le $withoutPatterns)) { 'patterns on' } else { 'patterns off' }
    $bestValue = [Math]::Min([Math]::Max($withPatterns, 0), [Math]::Max($withoutPatterns, 0))
    if ($withPatterns -lt 0 -and $withoutPatterns -lt 0) { $bestValue = -1 }

    # Half a percent of sampled pixels: enough room for the rasterizer to
    # disagree on a boundary, nowhere near enough to hide a fill that did not
    # shear at all.
    $ok = $bestValue -ge 0 -and $bestValue -lt 0.005
    if ($ok) { $pass++ } else { $fail++ }

    Note ("{0,-14} against native with patterns on: {1}   with patterns off: {2}   closest: {3}   {4}" -f `
        $name,
        $(if ($withPatterns -lt 0) { 'not comparable' } else { "{0:P3}" -f $withPatterns }),
        $(if ($withoutPatterns -lt 0) { 'not comparable' } else { "{0:P3}" -f $withoutPatterns }),
        $best,
        $(if ($ok) { 'PASS' } else { 'FAIL' }))
    Add-ProbeResult -Group 'fills' -Case ("{0} renders as the native command does" -f $name) -Expected 'the rendered pixels agree, so the fill sheared with the object' -Observed ("patterns on {0}, patterns off {1}, closest {2}" -f $withPatterns, $withoutPatterns, $best) -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
}

Note ''
Note ("images in {0}" -f $ImageFolder)
Note ("{0} passed, {1} failed" -f $pass, $fail)
Js 'LS.clear();' | Out-Null
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
