<#
.SYNOPSIS
    Closing Illustrator from the states this plugin can leave it in.

.DESCRIPTION
    A plugin that registers an effect, a menu item, and a window class has three
    things to give back at shutdown, and the usual way to find out that one of
    them was missed is a crash on the way out. Each case puts Illustrator into a
    state, quits it the ordinary way, and checks that it went, that it went
    promptly, and that the Windows event log has nothing new to say about it.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [int] $QuitTimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\shutdown.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

$script:pass = 0
$script:fail = 0
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    Note ("{0,-48} {1}" -f $name, $(if ($ok) { 'PASS' } else { "FAIL  $detail" }))
    Add-ProbeResult -Group 'shutdown' -Case $name -Expected 'quits promptly, nothing left running, nothing in the event log' -Observed $detail -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
}

function Get-NewCrashRecords([datetime] $since) {
    $e = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since } -MaxEvents 40 -ErrorAction SilentlyContinue |
         Where-Object { $_.Message -match 'Illustrator' -and $_.LevelDisplayName -eq 'Error' }
    if (-not $e) { return '' }
    return (($e | ForEach-Object { ($_.Message -replace "`r?`n", ' ').Substring(0, [Math]::Min(160, $_.Message.Length)) }) -join ' // ')
}

# A modal dialog opened and dismissed, so the window class has been registered
# in this session before the application is asked to quit.
$driver = {
    param([string] $ResultFile)
    Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class D3 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr p, int id);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    public static IntPtr Find(string needle) {
        IntPtr hit = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            StringBuilder cls = new StringBuilder(256);
            GetClassNameW(h, cls, 256);
            if (cls.ToString().Contains(needle)) { hit = h; return false; }
            return true;
        }, IntPtr.Zero);
        return hit;
    }
}
"@
    $deadline = (Get-Date).AddSeconds(30)
    $dlg = [IntPtr]::Zero
    while ((Get-Date) -lt $deadline) {
        $dlg = [D3]::Find('VulpesNexusShearDialog')
        if ($dlg -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 200
    }
    if ($dlg -eq [IntPtr]::Zero) { [IO.File]::WriteAllText($ResultFile, 'dialog never appeared'); return }
    [D3]::SendMessage($dlg, 0x0111, [IntPtr] 2, [D3]::GetDlgItem($dlg, 2)) | Out-Null
    [IO.File]::WriteAllText($ResultFile, 'opened the dialog and canceled it')
}

$cases = @(
    @{ Name = 'no documents open'; Setup = { Js 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } "empty";' | Out-Null } },
    @{ Name = 'one document with a Shear effect'; Setup = {
            Js "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.selectOnly(LS.target);" | Out-Null
            Js 'LS.shear(30, 0); app.redraw();' | Out-Null
        } },
    @{ Name = 'three documents, two with effects'; Setup = {
            Js 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } "cleared";' | Out-Null
            for ($i = 0; $i -lt 3; $i++) {
                Js 'app.documents.add();' | Out-Null
                Install-AiHarness | Out-Null
                if ($i -lt 2) {
                    Js "LS.target = LS.fixtures['plainRect'](); LS.selectOnly(LS.target); LS.shear(20, 0); app.redraw();" | Out-Null
                }
            }
        } },
    @{ Name = 'after the dialog has been opened'; Setup = {
            Js "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.selectOnly(LS.target);" | Out-Null
            Js 'LS.shear(15, 0); app.redraw();' | Out-Null
            $resultFile = Join-Path $env:TEMP ("liveshear-shutdown-{0}.txt" -f [Guid]::NewGuid().ToString('N'))
            $job = Start-Job -ScriptBlock $driver -ArgumentList $resultFile
            try { Send-AiMessage 'edit effect' '0' | Out-Null } catch { }
            Wait-Job $job -Timeout 60 | Out-Null
            Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
            Remove-Job $job -Force
            Note ("    driver: " + $(if (Test-Path $resultFile) { Get-Content $resultFile } else { 'no output' }))
            if (Test-Path $resultFile) { [IO.File]::Delete($resultFile) }
        } }
)

Start-ProbeResults -Probe 'shutdown'
Note 'Live Shear -- application shutdown'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ''

foreach ($case in $cases) {
    Start-Ai | Out-Null
    Install-AiHarness | Out-Null
    Js 'app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS; "ready";' | Out-Null
    & $case.Setup

    $since = Get-Date
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { Stop-Ai | Out-Null } catch { }
    $deadline = (Get-Date).AddSeconds($QuitTimeoutSeconds)
    while ((Get-Process Illustrator -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    $sw.Stop()
    $stillRunning = [bool] (Get-Process Illustrator -ErrorAction SilentlyContinue)
    if ($stillRunning) { Stop-Process -Name Illustrator -Force; Start-Sleep -Seconds 2 }
    Start-Sleep -Seconds 2
    $crash = Get-NewCrashRecords $since

    Check $case.Name ((-not $stillRunning) -and ($crash -eq '')) ("quit in {0:F1} s; still running {1}; event log: {2}" -f $sw.Elapsed.TotalSeconds, $stillRunning, $(if ($crash) { $crash } else { 'nothing' }))
    Note ("    quit in {0:F1} s" -f $sw.Elapsed.TotalSeconds)
}

Start-Ai | Out-Null
Install-AiHarness | Out-Null

Note ''
Note ("{0} passed, {1} failed" -f $script:pass, $script:fail)
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
Save-ProbeTranscript -Path $OutPath -Lines $log
Write-Output "Written to $OutPath"
