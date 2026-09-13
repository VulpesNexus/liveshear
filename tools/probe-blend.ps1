<#
.SYNOPSIS
    Does Illustrator ever call the effect's interpolation handler, and does it
    interpolate correctly when it does?

.DESCRIPTION
    The plugin implements AILiveEffectInterpParamMessage, which Illustrator is
    supposed to call when it blends two objects whose appearances differ. It is
    executable code in the shipped binary that no test had ever driven.

    There is no way to ask a script whether a callback ran, so the handler
    writes a line to the plugin's trace and this probe reads it back. Set
    LIVESHEAR_LOG before starting Illustrator.

    The angles are chosen to catch the one piece of arithmetic that is not
    obvious. A shear axis has a period of 180 degrees, not 360, so an axis of
    179 is one degree from an axis of 0 and not a hundred and seventy-nine, and
    interpolating between them must go the short way round. The cases here are
    the ones where a naive midpoint gives the wrong answer:

        0 to 179     the midpoint is 179.5, which is -0.5, not 89.5
        1 to 179     the midpoint is 0, not 90
        89 to -89    the midpoint is 90, not 0

    The blend is expanded afterwards so the intermediate objects become real
    art whose appearance can be read back.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [string] $TracePath = $env:LIVESHEAR_LOG
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\blend.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

$script:pass = 0
$script:fail = 0
function Check([string] $name, [bool] $ok, [string] $detail, [string] $status = '') {
    if (-not $status) { $status = if ($ok) { 'PASS' } else { 'FAIL' } }
    if ($status -eq 'PASS') { $script:pass++ } elseif ($status -eq 'FAIL') { $script:fail++ }
    Note ("[{0}] {1}" -f $status, $name)
    if ($detail) { Note ("       " + $detail) }
    Add-ProbeResult -Group 'blend' -Case $name -Expected 'the interpolation handler runs and takes the short way round modulo 180' -Observed $detail -Status $status
}

function Num([double] $v) { $v.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture) }

# How far apart two axis angles are, remembering that the axis repeats every
# 180 degrees.
function AxisDistance([double] $a, [double] $b) {
    $d = [Math]::IEEERemainder($a - $b, 180.0)
    return [Math]::Abs($d)
}

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'blend'

Note 'Live Shear -- blending two objects that carry different Shear effects'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Trace file: {0}" -f $(if ($TracePath) { $TracePath } else { 'not set' }))
Note ''

# Is the trace actually live? The plugin reads LIVESHEAR_LOG from
# Illustrator's environment, not from this shell's.
$traceIsLive = $false
if ($TracePath) {
    $before = if (Test-Path $TracePath) { (Get-Item $TracePath).Length } else { -1 }
    Js 'LS.clear(); LS.target = LS.fixtures["plainRect"](); LS.selectOnly(LS.target); LS.shear(7, 0); app.redraw();' | Out-Null
    $after = if (Test-Path $TracePath) { (Get-Item $TracePath).Length } else { -1 }
    $traceIsLive = ($after -gt $before)
}
Note ("Tracing is live: {0}" -f $(if ($traceIsLive) { 'yes' } else { 'no -- Illustrator was started without LIVESHEAR_LOG in its environment' }))
Note ''

$cases = @(
    @{ name = 'straight down the middle'; a = @(30, 0);   b = @(10, 40)  },
    @{ name = '0 to 179 the short way';   a = @(20, 0);   b = @(20, 179) },
    @{ name = '1 to 179 across zero';     a = @(20, 1);   b = @(20, 179) },
    @{ name = '89 to -89 across ninety';  a = @(20, 89);  b = @(20, -89) }
)

foreach ($case in $cases) {
    Note ("--- {0}: shear {1} axis {2}  ->  shear {3} axis {4} ---" -f $case.name, $case.a[0], $case.a[1], $case.b[0], $case.b[1])

    $mark = if ($traceIsLive -and (Test-Path $TracePath)) { (Get-Item $TracePath).Length } else { 0 }

    # Two rectangles far enough apart that the blend has room, each carrying a
    # Shear with its own parameters.
    Js 'LS.clear();' | Out-Null
    Js @"
(function () {
  var d = LS.doc();
  var a = LS.paint(LS.rect(80, 700, 120, 80), 0);  a.name = 'blendA';
  var b = LS.paint(LS.rect(380, 700, 120, 80), 0); b.name = 'blendB';
  return 'built';
})();
"@ | Out-Null
    Js 'LS.selectOnly(LS.named("blendA"));' | Out-Null
    Js ("LS.shear({0}, {1});" -f (Format-AiNumber $case.a[0]), (Format-AiNumber $case.a[1])) | Out-Null
    Js 'LS.selectOnly(LS.named("blendB"));' | Out-Null
    Js ("LS.shear({0}, {1});" -f (Format-AiNumber $case.b[0]), (Format-AiNumber $case.b[1])) | Out-Null
    Js 'app.redraw();' | Out-Null

    # Blend them, with whatever step count the document's blend options carry.
    # Object > Blend > Blend Options is a modal dialog and there is no
    # dialog-free form of it from a script, so the count is not set here; any
    # count at all exercises the handler, which is what this is for.
    Js @"
(function () {
  var d = LS.doc();
  d.selection = null;
  LS.named('blendA').selected = true;
  LS.named('blendB').selected = true;
  return 'selected';
})();
"@ | Out-Null
    $made = Js 'app.executeMenuCommand("Path Blend Make"); app.redraw(); app.activeDocument.pageItems.length + " items";'
    Note ("       after Object > Blend > Make: {0}" -f $made)

    # Expand it, so the intermediate objects become real art we can read.
    Js 'app.executeMenuCommand("selectall"); app.executeMenuCommand("Path Blend Expand"); app.redraw();' | Out-Null
    $count = Js 'app.activeDocument.pageItems.length + "";'

    $newTrace = ''
    if ($traceIsLive -and (Test-Path $TracePath)) {
        $bytes = [IO.File]::ReadAllBytes($TracePath)
        if ($bytes.Length -gt $mark) {
            $newTrace = [Text.Encoding]::UTF8.GetString($bytes, $mark, $bytes.Length - $mark)
        }
    }
    $calls = @([regex]::Matches($newTrace, 'Interpolate: t=([-0-9.eE+]+) shear ([-0-9.eE+]+) -> ([-0-9.eE+]+) = ([-0-9.eE+]+); axis ([-0-9.eE+]+) -> ([-0-9.eE+]+) = ([-0-9.eE+]+)'))

    if (-not $traceIsLive) {
        Check ("{0}: Illustrator calls the interpolation handler" -f $case.name) $false `
            'the plugin is not writing a trace, so whether the handler ran cannot be seen' 'INCONCLUSIVE'
        continue
    }

    Check ("{0}: Illustrator calls the interpolation handler" -f $case.name) ($calls.Count -gt 0) `
        ("the handler ran {0} time(s) while the blend was built; {1} objects after expanding" -f $calls.Count, $count)
    if ($calls.Count -eq 0) { continue }

    # Every call must land on the short way round: the interpolated axis is
    # never further from either end than the ends are from each other.
    $span = AxisDistance $case.a[1] $case.b[1]
    $worst = 0.0
    $worstDetail = ''
    $stepList = @()
    foreach ($m in $calls) {
        $stepList += ("t={0} -> axis {1}" -f (Num ([double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture))),
                                          (Num ([double]::Parse($m.Groups[7].Value, [Globalization.CultureInfo]::InvariantCulture))))
    }
    foreach ($m in $calls) {
        $t = [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
        $axis = [double]::Parse($m.Groups[7].Value, [Globalization.CultureInfo]::InvariantCulture)
        $fromStart = AxisDistance $axis $case.a[1]
        $fromEnd = AxisDistance $axis $case.b[1]
        $excess = ($fromStart + $fromEnd) - $span
        if ([Math]::Abs($excess) -gt $worst) {
            $worst = [Math]::Abs($excess)
            $worstDetail = ("t={0} gave axis {1}; {2} from the start and {3} from the end, against a span of {4}" -f `
                (Num $t), (Num $axis), (Num $fromStart), (Num $fromEnd), (Num $span))
        }
    }
    Check ("{0}: every step takes the short way round" -f $case.name) ($worst -le 1e-6) `
        $(if ($worstDetail) { $worstDetail } else {
            ("{0}; the two ends are {1} degrees apart going the short way, and every step is inside that. A naive midpoint would have given {2}." -f `
                ($stepList -join ', '), (Num $span), (Num (($case.a[1] + $case.b[1]) / 2))) })

    # And the shear angle itself is a straight line between the two.
    $shearOk = $true
    $shearDetail = ''
    foreach ($m in $calls) {
        $t = [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
        $got = [double]::Parse($m.Groups[4].Value, [Globalization.CultureInfo]::InvariantCulture)
        $want = $case.a[0] + ($case.b[0] - $case.a[0]) * $t
        if ([Math]::Abs($got - $want) -gt 1e-6) {
            $shearOk = $false
            $shearDetail = ("t={0} gave shear {1}, expected {2}" -f (Num $t), (Num $got), (Num $want))
        }
    }
    Check ("{0}: the shear angle is a straight line between the two" -f $case.name) $shearOk `
        $(if ($shearDetail) { $shearDetail } else { ("all {0} steps are exactly on the line from {1} to {2}" -f $calls.Count, (Num $case.a[0]), (Num $case.b[0])) })
}

Note ''
Note ("{0} passed, {1} failed" -f $script:pass, $script:fail)
Js 'LS.clear();' | Out-Null
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
