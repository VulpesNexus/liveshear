<#
.SYNOPSIS
    Illustrator died twice at the same point in the suite. Does it need this
    plugin to do that?

.DESCRIPTION
    Two full suite runs ended with an access violation inside Illustrator.exe,
    both times during the save-and-reopen probe and both times immediately
    after the appearance-composition probe. The save-and-reopen probe on its
    own ran three times in a row without trouble, so it is the sequence and not
    the probe.

    That is a reproducible sequence, which is worth far more than the
    non-reproducible crash recorded earlier, because a reproducible sequence
    can be controlled.

    Two arms, alternated so that anything drifting over the session hits both:

        with     the same work, with the Shear effect applied throughout
        without  the same work, the same document churn, the same expand and
                 save and reopen, and no Shear effect anywhere

    If both arms die, the plugin is not necessary for the crash and the
    sequence is the cause. If only the first does, the plugin is implicated and
    this is a release blocker. Either answer is worth having; neither is
    assumed.

    Each trial runs in a fresh Illustrator, because the whole point is what
    accumulates within one session.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [int] $Trials = 3
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\sequence-crash.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }

function Crash-Count {
    @(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-6)} -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'Illustrator\.exe' }).Count
}

function Latest-Offset {
    $record = Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-6)} -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match 'Illustrator\.exe' } | Select-Object -First 1
    if (-not $record) { return '' }
    (($record.Message -split "`n" | Where-Object { $_ -match 'Fault offset' }) -replace '.*:\s*', '').Trim()
}

function Kill-Ai {
    Get-Process Illustrator -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Process Illustrator -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
}

# One trial: the composition work, then the save-and-reopen work, in one
# Illustrator session. Returns how far it got.
function Run-Trial([bool] $useEffect) {
    Kill-Ai
    Start-Ai | Out-Null

    # COM answers before Illustrator is ready to be asked anything useful, and
    # a call made in that window fails with an RPC error that looks exactly
    # like the crash this probe is trying to count. Settle first, and retry,
    # so a slow start is never recorded as a death.
    $ready = $false
    for ($attempt = 1; $attempt -le 20 -and -not $ready; $attempt++) {
        Start-Sleep -Seconds 2
        try {
            Invoke-AiScript 'app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS; app.documents.length + "";' | Out-Null
            Install-AiHarness | Out-Null
            Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } app.documents.add(); "ready";' | Out-Null
            $ready = $true
        }
        catch { }
    }
    if (-not $ready) { return [pscustomobject]@{ Reached = 'never started'; Died = $true; Message = 'Illustrator would not answer' } }

    $transform = 'reflect=b:false;scaleH_Factor=r:1.6;scaleV_Factor=r:0.7'
    $stage = 'start'
    try {
        # --- the composition work ---
        foreach ($name in @('plainRect', 'selfIntersecting', 'bezier')) {
            foreach ($round in 1..4) {
                $stage = "composition $name $round"
                Invoke-AiScript "LS.clear(); LS.target = LS.fixtures['$name'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
                Invoke-AiScript 'app.redraw();' | Out-Null
                if ($useEffect) { Invoke-AiScript 'LS.shear(30, 0);' | Out-Null }
                Invoke-AiScript "LS.applyEffect('Adobe Transform', '$transform');" | Out-Null
                Invoke-AiScript 'app.redraw();' | Out-Null
                Invoke-AiScript 'app.executeMenuCommand("expandStyle");' | Out-Null
                Invoke-AiScript 'app.executeMenuCommand("selectall"); app.redraw();' | Out-Null
                Invoke-AiScript "LS.nativeShearChecked('subject', 30, 0);" | Out-Null
                Invoke-AiScript 'app.redraw();' | Out-Null
            }
        }

        # --- the save-and-reopen work ---
        $folder = (Join-Path ([IO.Path]::GetTempPath()) 'liveshear-sequence').Replace('\', '/')
        $null = New-Item -ItemType Directory -Force -Path $folder
        foreach ($round in 1..6) {
            $stage = "save and reopen $round"
            Invoke-AiScript "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
            if ($useEffect) { Invoke-AiScript 'LS.shear(22, 15);' | Out-Null }
            Invoke-AiScript 'app.redraw();' | Out-Null
            Invoke-AiScript "app.activeDocument.saveAs(new File('$folder/trial.ai'));" | Out-Null
            Invoke-AiScript 'app.activeDocument.close(SaveOptions.DONOTSAVECHANGES);' | Out-Null
            Invoke-AiScript "app.open(new File('$folder/trial.ai'));" | Out-Null
            Invoke-AiScript 'app.redraw();' | Out-Null
        }
        $stage = 'finished'
    }
    catch {
        return [pscustomobject]@{ Reached = $stage; Died = $true; Message = $_.Exception.Message }
    }
    return [pscustomobject]@{ Reached = $stage; Died = $false; Message = '' }
}

Start-ProbeResults -Probe 'sequence-crash'
Note 'Live Shear -- the crash that happens at the same point twice'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("{0} trials per arm, alternated, each in a fresh Illustrator" -f $Trials)
Note ''
Note ("{0,-8} {1,-6} {2,-28} {3,-8} {4}" -f 'trial', 'arm', 'reached', 'crashed', 'fault offset')

$results = @{ with = @(); without = @() }
for ($trial = 1; $trial -le $Trials; $trial++) {
    foreach ($arm in @('with', 'without')) {
        $before = Crash-Count
        $outcome = Run-Trial ($arm -eq 'with')
        $after = Crash-Count
        $crashed = ($after -gt $before)
        $offset = if ($crashed) { Latest-Offset } else { '' }
        $results[$arm] += [pscustomobject]@{ Reached = $outcome.Reached; Crashed = $crashed }
        Note ("{0,-8} {1,-6} {2,-28} {3,-8} {4}" -f $trial, $arm, $outcome.Reached, $(if ($crashed) { 'yes' } else { 'no' }), $offset)
    }
}

Kill-Ai
Note ''
foreach ($arm in @('with', 'without')) {
    $crashes = @($results[$arm] | Where-Object { $_.Crashed }).Count
    $finished = @($results[$arm] | Where-Object { $_.Reached -eq 'finished' }).Count
    Note ("{0,-8} {1} of {2} trials crashed; {3} ran to the end" -f $arm, $crashes, $Trials, $finished)
    Add-ProbeResult -Group 'document churn' `
        -Case ("the composition-then-save sequence, {0} the Shear effect" -f $arm) `
        -Expected 'the two arms are compared; neither count is a threshold' `
        -Observed ("{0} of {1} trials ended in an access violation inside Illustrator.exe; {2} ran to the end" -f $crashes, $Trials, $finished) `
        -Status 'MEASURED'
}

$withCrashes = @($results['with'] | Where-Object { $_.Crashed }).Count
$withoutCrashes = @($results['without'] | Where-Object { $_.Crashed }).Count
Note ''
if ($withoutCrashes -gt 0) {
    Note 'Both arms crash, so the effect is not necessary for this: the sequence is. What these counts cannot establish is whether having it loaded changes how often, and that is not claimed.'
}
elseif ($withCrashes -gt 0) {
    Note 'Only the arm that uses the effect crashed. That is not proof on its own, but it is the shape of a real problem and it needs more trials before release.'
}
else {
    Note 'Neither arm crashed in this run, so the sequence alone does not account for it either.'
}

Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
