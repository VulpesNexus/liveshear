<#
.SYNOPSIS
    Three-arm test of whether this plugin makes Illustrator's document-churn
    crash more likely.

.DESCRIPTION
    Illustrator 30.7.0 dies with an access violation inside Illustrator.exe
    during long runs of scripted document create/close, and it does so with no
    third-party plugin installed at all. The question a release has to answer is
    narrower: does having this plugin loaded, or actually using it, make the
    failure more likely or make it arrive sooner?

    Three arms, one deterministic workload:

        A  plugin not installed
        B  plugin installed, effect never applied
        C  plugin installed, Shear applied and rendered in every cycle

    Illustrator is restarted between trials so no trial can inherit another's
    state. Arms B and C are interleaved, which is what matters: they share an
    install, so alternating them spreads any drift in machine state evenly
    across the two. Arm A cannot be interleaved with them, because switching
    would mean copying into the Illustrator program folder -- an elevated,
    interactive step -- before every trial; it runs as one block instead, and
    the report says so.
#>
[CmdletBinding()]
param(
    [int] $Cycles = 60,
    [int] $Trials = 6,
    [string] $LogPath,
    # Arm A needs the plugin uninstalled, which means an elevated copy and a
    # prompt to answer. tools\probe-missing-plugin.ps1 already arranges exactly
    # that state, so it runs arm A there and leaves the result here.
    [switch] $SkipArmA,
    [string] $ArmAPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
$install = Join-Path $PSScriptRoot 'install.ps1'
if (-not $LogPath) { $LogPath = Join-Path $repo 'docs\evidence\crash-ab.txt' }
if (-not $ArmAPath) { $ArmAPath = Join-Path $repo 'docs\evidence\crash-arm-a.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }

function Get-PeakMemoryMB {
    $p = Get-Process Illustrator -ErrorAction SilentlyContinue
    if (-not $p) { return 0 }
    return [int]($p.PeakWorkingSet64 / 1MB)
}

function Get-LastCrashRecord([datetime] $since) {
    $e = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; StartTime = $since } -MaxEvents 5 -ErrorAction SilentlyContinue |
         Where-Object { $_.Message -match 'Illustrator' } | Select-Object -First 1
    if (-not $e) { return 'no Application Error record' }
    $m = $e.Message -replace "`r?`n", ' '
    if ($m -match 'Faulting module name:\s*([^,]+),') { $module = $Matches[1] } else { $module = '?' }
    if ($m -match 'Exception code:\s*(0x[0-9a-fA-F]+)') { $code = $Matches[1] } else { $code = '?' }
    if ($m -match 'Fault offset:\s*(0x[0-9a-fA-F]+)') { $offset = $Matches[1] } else { $offset = '?' }
    return "module $module exception $code offset $offset"
}

# One cycle: a fresh document, one rectangle, optionally the effect, then close.
$buildOnly = 'var d = app.documents.add(DocumentColorSpace.RGB, 600, 600); d.rulerOrigin=[0,0]; var r = d.pathItems.rectangle(500,100,200,120); r.filled = true; r.stroked = false; app.executeMenuCommand("deselectall"); r.selected = true; "built";'
$buildShear = $buildOnly.Replace('"built";', 'app.sendScriptMessage("LiveShear", "apply effect", "VulpesNexus Shear|shearAngle=r:30"); app.redraw(); "sheared";')

function Invoke-Trial([string] $arm, [string] $build) {
    Stop-Ai | Out-Null
    if (Get-Process Illustrator -ErrorAction SilentlyContinue) {
        Stop-Process -Name Illustrator -Force; Start-Sleep -Seconds 2
    }
    $started = Get-Date
    Start-Ai | Out-Null

    $loaded = $false
    try { $loaded = (Send-AiMessage version) -match 'Shear' } catch { }

    Invoke-AiScript 'app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS; while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } "ready";' | Out-Null

    $peak = 0
    $done = $Cycles
    for ($i = 0; $i -lt $Cycles; $i++) {
        try {
            Invoke-AiScript $build | Out-Null
            Invoke-AiScript 'app.activeDocument.close(SaveOptions.DONOTSAVECHANGES); "closed";' | Out-Null
            if (($i % 10) -eq 0) { $peak = [math]::Max($peak, (Get-PeakMemoryMB)) }
        }
        catch { $done = $i; break }
    }
    $peak = [math]::Max($peak, (Get-PeakMemoryMB))
    $crash = if ($done -lt $Cycles) { Get-LastCrashRecord $started } else { '' }
    return [pscustomobject]@{
        Arm = $arm; Cycles = $done; Completed = ($done -eq $Cycles)
        PeakMB = $peak; PluginLoaded = $loaded; Crash = $crash
    }
}

Note 'Live Shear -- does the plugin change the document-churn crash?'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("{0} trials per arm, up to {1} create/close cycles each" -f $Trials, $Cycles)
Note ''

$results = New-Object Collections.Generic.List[object]

if ($SkipArmA) {
    if (Test-Path $ArmAPath) {
        Note ("Arm A read from {0}:" -f $ArmAPath)
        foreach ($line in (Get-Content $ArmAPath)) {
            Note ("  " + $line)
            if ($line -match 'trial \d+:\s*(\d+) of (\d+) cycles, peak (\d+) MB') {
                $results.Add([pscustomobject]@{
                    Arm = 'A absent'; Cycles = [int] $Matches[1]
                    Completed = ([int] $Matches[1] -eq [int] $Matches[2])
                    PeakMB = [int] $Matches[3]; PluginLoaded = $false; Crash = ''
                })
            }
        }
    }
    else {
        Note ("Arm A skipped and no earlier result at {0}." -f $ArmAPath)
    }
}
else {
    Stop-Ai | Out-Null
    & $install -Uninstall | Out-Null
    Note 'Arm A: plugin uninstalled.'
    for ($t = 1; $t -le $Trials; $t++) {
        $r = Invoke-Trial 'A absent' $buildOnly
        $results.Add($r)
        Note ("  A absent          trial {0}: {1,3} of {2} cycles, peak {3} MB, plugin loaded {4}. {5}" -f $t, $r.Cycles, $Cycles, $r.PeakMB, $r.PluginLoaded, $r.Crash)
    }
}

if (-not $SkipArmA) {
    Stop-Ai | Out-Null
    & $install | Out-Null
}
Note 'Arms B and C: plugin installed, trials interleaved.'
for ($t = 1; $t -le $Trials; $t++) {
    foreach ($arm in @('B unused', 'C exercised')) {
        $build = if ($arm -eq 'C exercised') { $buildShear } else { $buildOnly }
        $r = Invoke-Trial $arm $build
        $results.Add($r)
        Note ("  {0,-17} trial {1}: {2,3} of {3} cycles, peak {4} MB, plugin loaded {5}. {6}" -f $arm, $t, $r.Cycles, $Cycles, $r.PeakMB, $r.PluginLoaded, $r.Crash)
    }
}

Note ''
Note 'Summary'
Note ("{0,-14} {1,>7} {2,>9} {3,>11} {4,>9}" -f 'arm', 'trials', 'complete', 'mean cycles', 'peak MB')
foreach ($arm in @('A absent', 'B unused', 'C exercised')) {
    $rows = $results | Where-Object { $_.Arm -eq $arm }
    if (-not $rows) { continue }
    $mean = ($rows | Measure-Object -Property Cycles -Average).Average
    $peak = ($rows | Measure-Object -Property PeakMB -Maximum).Maximum
    $complete = ($rows | Where-Object { $_.Completed }).Count
    Note ("{0,-14} {1,7} {2,9} {3,11:F1} {4,9}" -f $arm, $rows.Count, $complete, $mean, $peak)
}

Stop-Ai | Out-Null
Start-Ai | Out-Null
[System.IO.File]::WriteAllLines($LogPath, $log)
Write-Output "`nWritten to $LogPath"
