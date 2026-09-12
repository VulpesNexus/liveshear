<#
.SYNOPSIS
    Hostile parameter values, by every route that can carry one.

.DESCRIPTION
    The dialog clamps what a user can type, but a stored parameter can arrive
    from somewhere else: a document written by another version, a script writing
    the dictionary directly, a file edited by hand. Illustrator becomes
    pathological as a shear approaches a right angle -- a native shear of 89
    degrees returns at once, 89.9 did not return at all in the run that measured
    it -- so a value that slips past the dialog must still be made safe before
    it reaches tan().

    Each case writes a value straight into the effect's parameter dictionary,
    redraws with a watchdog on the clock, and reports what the effect actually
    rendered. The watchdog is the point: a case that hangs is a release blocker
    and has to be distinguishable from one that merely looks wrong.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [int] $TimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\limits.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'limits'

# The fixture is a 200 by 120 rectangle whose center is at (200, 540), so the
# expected half-width after a horizontal shear of theta is 100 + 60*tan(theta).
function Expected([double] $degrees) {
    $k = [math]::Tan($degrees * [math]::PI / 180.0)
    return 60.0 * [math]::Abs($k) + 100.0
}

Note 'Live Shear -- parameter safety'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Watchdog: {0} seconds per redraw" -f $TimeoutSeconds)
Note ''
Note ("{0,-14} {1,-12} {2,-46} {3}" -f 'written', 'seconds', 'rendered bounds', 'verdict')

# The written value, and the angle the effect is expected to settle on.
$cases = @(
    @{ Write = '0';        Effective = 0.0 },
    @{ Write = '30';       Effective = 30.0 },
    @{ Write = '89';       Effective = 89.0 },
    @{ Write = '-89';      Effective = -89.0 },
    @{ Write = '89.000001';Effective = 89.0 },
    @{ Write = '89.9';     Effective = 89.0 },
    @{ Write = '90';       Effective = 89.0 },
    @{ Write = '-90';      Effective = -89.0 },
    @{ Write = '180';      Effective = 89.0 },
    @{ Write = '-180';     Effective = -89.0 },
    @{ Write = '1e9';      Effective = 89.0 },
    @{ Write = 'nan';      Effective = 0.0 },
    @{ Write = 'inf';      Effective = 89.0 },
    @{ Write = '-inf';     Effective = -89.0 },
    @{ Write = '0.000001'; Effective = 0.0 },
    @{ Write = '0.001';    Effective = 0.001 }
)

$pass = 0; $fail = 0
Js "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.selectOnly(LS.target);" | Out-Null
Js 'app.redraw();' | Out-Null
Js 'LS.shear(0, 0);' | Out-Null
Js 'app.redraw();' | Out-Null

foreach ($case in $cases) {
    $written = $case.Write
    $expectedHalf = Expected $case.Effective
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $bounds = 'not reached'
    $timedOut = $false
    try {
        $job = Start-Job -ScriptBlock {
            param($repo, $value)
            . (Join-Path $repo 'tools\ai.ps1')
            Invoke-AiScript ("app.sendScriptMessage('LiveShear', 'set param', '0|shearAngle|real|{0}');" -f $value) | Out-Null
            Invoke-AiScript 'app.redraw();' | Out-Null
            (Invoke-AiScript 'var o = app.activeDocument.pageItems[0]; var v = o.visibleBounds; v[0].toFixed(6)+","+v[1].toFixed(6)+","+v[2].toFixed(6)+","+v[3].toFixed(6);').Trim()
        } -ArgumentList $repo, $written
        if (Wait-Job $job -Timeout $TimeoutSeconds) {
            $bounds = (Receive-Job $job) -join ''
        }
        else {
            $timedOut = $true
            Stop-Job $job
        }
        Remove-Job $job -Force
    }
    catch { $bounds = "error: $($_.Exception.Message)" }
    $sw.Stop()

    $verdict = 'FAIL'
    if ($timedOut) {
        $verdict = 'HANG -- release blocker'
    }
    elseif ($bounds -match '^([-0-9.]+),([-0-9.]+),([-0-9.]+),([-0-9.]+)$') {
        $left = [double]$Matches[1]
        $right = [double]$Matches[3]
        $half = ($right - $left) / 2.0
        $ok = [math]::Abs($half - $expectedHalf) -lt 0.001
        $verdict = if ($ok) { "PASS (clamped to {0} deg)" -f $case.Effective } else { "FAIL expected half-width {0:F4}, got {1:F4}" -f $expectedHalf, $half }
        if ($ok) { $pass++ } else { $fail++ }
    }
    else {
        $fail++
        $verdict = "FAIL $bounds"
    }
    if ($timedOut) { $fail++ }

    Add-ProbeResult -Group 'stored parameter' -Case ("shearAngle written as {0}" -f $written) -Expected ("clamped to {0} degrees, no hang" -f $case.Effective) -Observed ("{0} in {1:F2} s" -f $bounds, $sw.Elapsed.TotalSeconds) -Status $(if ($verdict -like 'PASS*') { 'PASS' } else { 'FAIL' })
    Note ("{0,-14} {1,-12:F2} {2,-46} {3}" -f $written, $sw.Elapsed.TotalSeconds, $bounds, $verdict)
    if ($timedOut) { break }
}

# The same hostile value, but arriving from a saved document rather than from a
# script: write it, save, close, reopen, and see what opens.
Note ''
Note '--- a document that stores 90 degrees ---'
$file = Join-Path ([IO.Path]::GetTempPath()) 'liveshear-ninety.ai'
$js = $file.Replace('\', '\\')
Js "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.selectOnly(LS.target);" | Out-Null
Js 'app.redraw();' | Out-Null
Js 'LS.shear(30, 0);' | Out-Null
Js 'app.redraw();' | Out-Null
Js "LS.send('set param', '0|shearAngle|real|90');" | Out-Null
Js 'app.redraw();' | Out-Null
$storedBounds = Js 'LS.vb(LS.target);'
Js "app.activeDocument.saveAs(new File('$js')); app.activeDocument.close(SaveOptions.SAVECHANGES); 'saved';" | Out-Null
$sw = [Diagnostics.Stopwatch]::StartNew()
Js "app.open(new File('$js')); app.redraw(); 'opened';" | Out-Null
$sw.Stop()
Js 'app.executeMenuCommand("selectall"); LS.target = app.activeDocument.selection[0]; app.redraw();' | Out-Null
$reopened = Js 'LS.vb(LS.target);'
$appearance = Js 'LS.appearance();'
$stored = if ($appearance -match 'shearAngle[^=]*=\s*([-0-9.]+)') { $Matches[1] } else { '?' }
Note ("reopened in {0:F2} s   bounds {1}   dictionary still holds shearAngle {2}" -f $sw.Elapsed.TotalSeconds, $reopened, $stored)
$ok = ($storedBounds -eq $reopened)
if ($ok) { $pass++ } else { $fail++ }
Add-ProbeResult -Group 'stored parameter' -Case 'a document storing 90 degrees opens and renders the same' -Expected 'opens promptly, clamped, unchanged bounds' -Observed ("opened in {0:F2} s, dictionary holds {1}, bounds {2}" -f $sw.Elapsed.TotalSeconds, $stored, $reopened) -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
Note ("renders the same before and after the round trip: {0}" -f $(if ($ok) { 'PASS' } else { "FAIL $storedBounds vs $reopened" }))

Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } app.documents.add(); "reset";' | Out-Null

Note ''
Note ("{0} passed, {1} failed" -f $pass, $fail)
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
