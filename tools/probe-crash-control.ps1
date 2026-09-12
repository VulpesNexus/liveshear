<#
.SYNOPSIS
    Repeats the plainest possible document churn, with and without the plugin
    installed, to find out whether the plugin is implicated in the crash.

.DESCRIPTION
    The cycle creates a document with one rectangle and closes it again. It
    never applies the effect and never speaks to the plugin, so the only
    difference between the two arms is whether LiveShear.aip is loaded at all.
    Illustrator is restarted before every run so the arms cannot contaminate
    each other.
#>
[CmdletBinding()]
param(
    [int] $Cycles = 40,
    [int] $Runs = 3,
    [string] $LogPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
$install = Join-Path $PSScriptRoot 'install.ps1'
if (-not $LogPath) { $LogPath = Join-Path $repo 'docs\evidence\crash-control.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }

function Churn([int] $n) {
    Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
    for ($i = 0; $i -lt $n; $i++) {
        try {
            Invoke-AiScript 'var d = app.documents.add(DocumentColorSpace.RGB, 600, 600); d.rulerOrigin=[0,0]; var r = d.pathItems.rectangle(500,100,200,120); r.filled = true; r.stroked = false; app.executeMenuCommand("deselectall"); r.selected = true;' | Out-Null
            Invoke-AiScript 'app.activeDocument.close(SaveOptions.DONOTSAVECHANGES);' | Out-Null
        }
        catch { return $i }
    }
    return $n
}

Note 'Live Shear -- is the plugin implicated in the crash?'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("{0} runs of {1} create/close cycles per arm" -f $Runs, $Cycles)
Note ''

foreach ($arm in @('without the plugin', 'with the plugin')) {
    Stop-Ai | Out-Null
    if ($arm -eq 'without the plugin') { & $install -Uninstall | Out-Null } else { & $install | Out-Null }

    $results = @()
    for ($r = 0; $r -lt $Runs; $r++) {
        Stop-Ai | Out-Null
        Start-Ai | Out-Null
        $loaded = $false
        try { $loaded = (Send-AiMessage version) -match 'LiveShear' } catch { }
        $done = Churn $Cycles
        $results += $done
        Note ("{0}, run {1}: {2} of {3} cycles (plugin loaded: {4})" -f $arm, ($r + 1), $done, $Cycles, $loaded)
    }
    $survived = ($results | Where-Object { $_ -eq $Cycles }).Count
    Note ("{0}: {1} of {2} runs completed all {3} cycles" -f $arm, $survived, $Runs, $Cycles)
    Note ''
}

# Leave the plugin installed.
Stop-Ai | Out-Null
& $install | Out-Null
Start-Ai | Out-Null

[System.IO.File]::WriteAllLines($LogPath, $log)
Write-Output "Written to $LogPath"
