<#
.SYNOPSIS
    Identity, drift, numerical stability, performance, and bulk documents.

.DESCRIPTION
    A live effect recomputes from its source every time anything redraws, so the
    failure mode to rule out is accumulation: an effect that transforms the
    previous result instead of the source would drift a little further every
    pass and look perfectly correct in a single screenshot.

    Every case here ends by putting the parameters back where they started and
    comparing against artwork that was never touched at all.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [int] $DriftEdits = 100,
    [int] $BulkObjects = 200,
    [int] $Iterations = 100
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\stability.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

function Deviation([string] $a, [string] $b) {
    $x = $a -split ','
    $y = $b -split ','
    if ($x.Count -ne 4 -or $y.Count -ne 4) { return [double]::PositiveInfinity }
    $max = 0.0
    for ($i = 0; $i -lt 4; $i++) {
        $d = [math]::Abs([double]$x[$i] - [double]$y[$i])
        if ($d -gt $max) { $max = $d }
    }
    return $max
}

$script:pass = 0
$script:fail = 0
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    $verdict = if ($ok) { 'PASS' } else { "FAIL  $detail" }
    Note ("{0,-56} {1}" -f $name, $verdict)
    Add-ProbeResult -Group $script:group -Case $name -Expected 'no change from the untouched artwork' -Observed $detail -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
}

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'stability'
$script:group = 'identity'

Note 'Live Shear -- stability'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ''

# ---- identity ---------------------------------------------------------
Note '--- a zero shear is exactly nothing ---'
foreach ($axis in @(0, 17, 45, 90, 137, 180, -63)) {
    $untouched = Js "LS.clear(); LS.target = LS.fixtures['spike'](); app.redraw(); LS.vb(LS.target);"
    $anchorsBefore = Js 'LS.anchorsOf(LS.target);'
    Js "LS.selectOnly(LS.target); LS.shear(0, $axis);" | Out-Null
    # Force many reevaluations, so anything cumulative has room to show.
    for ($i = 0; $i -lt 25; $i++) { Js 'app.redraw();' | Out-Null }
    $after = Js 'LS.vb(LS.target);'
    $anchorsAfter = Js 'LS.anchorsOf(LS.target);'
    $dev = Deviation $untouched $after
    Check ("identity at axis {0}, 25 redraws" -f $axis) (($dev -eq 0) -and ($anchorsBefore -eq $anchorsAfter)) "deviation $dev"
}

# ---- drift ------------------------------------------------------------
$script:group = 'drift'
Note '--- editing the angle many times and returning to it ---'
$untouched = Js "LS.clear(); LS.target = LS.fixtures['bezier'](); app.redraw(); LS.vb(LS.target);"
Js 'LS.selectOnly(LS.target); LS.shear(30, 0);' | Out-Null
Js 'app.redraw();' | Out-Null
$atThirty = Js 'LS.vb(LS.target);'

$sequence = @(0, 30, -20, 70, 0, 45, -89, 89, 12.5, 0)
for ($round = 0; $round -lt [math]::Ceiling($DriftEdits / $sequence.Count); $round++) {
    foreach ($v in $sequence) {
        Js ("LS.send('set param', '0|shearAngle|real|{0}');" -f $v) | Out-Null
        Js 'app.redraw();' | Out-Null
    }
}
Js "LS.send('set param', '0|shearAngle|real|30');" | Out-Null
Js 'app.redraw();' | Out-Null
$backToThirty = Js 'LS.vb(LS.target);'
$dev = Deviation $atThirty $backToThirty
Check ("{0} parameter edits then back to 30 degrees" -f ($sequence.Count * [math]::Ceiling($DriftEdits / $sequence.Count))) ($dev -eq 0) "deviation $dev"

Js "LS.send('set param', '0|shearAngle|real|0');" | Out-Null
Js 'app.redraw();' | Out-Null
$backToZero = Js 'LS.vb(LS.target);'
Check 'and back to zero, against artwork never sheared' ((Deviation $untouched $backToZero) -eq 0) ("deviation " + (Deviation $untouched $backToZero))

# ---- the effect never rewrites its own source --------------------------
$script:group = 'source'
Note '--- the source geometry after all of that ---'
$anchorsNow = Js 'LS.anchorsOf(LS.target);'
$fresh = Js "LS.clear(); LS.target = LS.fixtures['bezier'](); LS.anchorsOf(LS.target);"
Check 'source anchors identical to a fresh fixture' ($anchorsNow -eq $fresh) 'the source moved'

# ---- performance ------------------------------------------------------
$script:group = 'performance'
Note '--- how long one evaluation takes ---'
Note 'Timed inside Illustrator rather than across the scripting bridge. A round'
Note 'trip over COM costs around a tenth of a second, which is more than the'
Note 'effect does and would bury it; timing the loop in one call removes it.'
Note ''
Note ("{0,-16} {1,14} {2,16} {3,16}" -f 'fixture', 'redraws', 'with the effect', 'per evaluation')
foreach ($name in @('plainRect', 'bezier', 'multilineText', 'manyChildren', 'compound')) {
    Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.selectOnly(LS.target);" | Out-Null
    Js 'app.redraw();' | Out-Null

    # The same loop, once with nothing to recompute and once with the effect
    # re-evaluated every pass. Neither number is subtracted from the other;
    # both are reported, because what a person feels when dragging the slider
    # is the second one, not the difference.
    $plain = [double] (Js "var t0 = new Date().getTime(); for (var i = 0; i < $Iterations; i++) { app.redraw(); } (new Date().getTime() - t0);")

    Js 'LS.shear(30, 0);' | Out-Null
    Js 'app.redraw();' | Out-Null
    $withEffect = [double] (Js "var t0 = new Date().getTime(); for (var i = 0; i < $Iterations; i++) { LS.send('set param', '0|shearAngle|real|' + (20 + (i % 20))); app.redraw(); } (new Date().getTime() - t0);")

    $per = $withEffect / $Iterations
    Note ("{0,-16} {1,11:F0} ms {2,13:F0} ms {3,13:F2} ms" -f $name, $plain, $withEffect, $per)
    Add-ProbeResult -Group 'performance' -Case ("{0}: {1} evaluations with the effect" -f $name, $Iterations) -Expected 'fast enough that dragging the slider does not lag' -Observed ("{0:F0} ms in total, {1:F2} ms each; the same loop with nothing to recompute took {2:F0} ms" -f $withEffect, $per, $plain) -Status 'MEASURED'
}
Note ''

# ---- a document full of them ------------------------------------------
Note ("--- a document with {0} independent Shear effects ---" -f $BulkObjects)
Js 'LS.clear();' | Out-Null
$build = Measure-Command {
    Invoke-AiScript ("var d = LS.doc(); for (var i = 0; i < $BulkObjects; i++) { var r = LS.paint(LS.rect(20 + (i % 25) * 22, 700 - Math.floor(i / 25) * 22, 18, 14), 0); d.selection = null; r.selected = true; LS.shear(10 + (i % 40), (i % 7) * 15); } app.redraw(); 'built';") | Out-Null
}
$memAfterBuild = [int]((Get-Process Illustrator).WorkingSet64 / 1MB)
$redraw = Measure-Command { Invoke-AiScript 'app.redraw();' | Out-Null }

$bulkFile = Join-Path ([IO.Path]::GetTempPath()) 'liveshear-bulk.ai'
$jsBulk = $bulkFile.Replace('\', '\\')
$save = Measure-Command { Invoke-AiScript "app.activeDocument.saveAs(new File('$jsBulk')); 'saved';" | Out-Null }
Invoke-AiScript 'app.activeDocument.close(SaveOptions.SAVECHANGES); "closed";' | Out-Null
$open = Measure-Command { Invoke-AiScript "app.open(new File('$jsBulk')); app.redraw(); 'opened';" | Out-Null }
$count = Js 'var d = app.activeDocument; d.pathItems.length;'
$memAfterOpen = [int]((Get-Process Illustrator).WorkingSet64 / 1MB)
$size = if (Test-Path $bulkFile) { (Get-Item $bulkFile).Length } else { 0 }

Note ("build {0:F0} ms   redraw {1:F0} ms   save {2:F0} ms   reopen {3:F0} ms   {4} paths   {5} bytes" -f $build.TotalMilliseconds, $redraw.TotalMilliseconds, $save.TotalMilliseconds, $open.TotalMilliseconds, $count, $size)
Note ("memory after building {0} MB, after reopening {1} MB" -f $memAfterBuild, $memAfterOpen)
Check ("all {0} objects survived the round trip" -f $BulkObjects) ([int]$count -eq $BulkObjects) "found $count"

Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } app.documents.add(); "reset";' | Out-Null

Note ''
Note ("{0} passed, {1} failed" -f $script:pass, $script:fail)
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
