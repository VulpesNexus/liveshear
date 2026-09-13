<#
.SYNOPSIS
    Where the effect's menu item is, and whether choosing it works.

.DESCRIPTION
    The rest of the suite applies the effect through the script bridge, which
    goes straight to NewArtStyleByMergingLiveEffect and never touches a menu.
    That is the right way to measure geometry and the wrong way to notice that
    the menu item moved, vanished, or stopped applying anything -- which is
    exactly what three releases of a mis-registered category did.

    So this drives the menu item itself, by the command string Illustrator
    derives from the effect's name, and checks three things:

      * the item is in "Effects 3rd Party", meaning the Effect menu itself.
        A name beginning "Live 3rd Party" would mean a submenu of its own had
        come back; one beginning "Live Vector" would mean it had been put
        inside one of Adobe's, which silently breaks Apply Last Effect.
      * choosing it opens the dialog and applies exactly one effect.
      * Effect > Apply Last Effect then reapplies it to something else. That
        is the one the placement can break without any error being raised.

    The dialog is modal, so the call that opens it does not return until it
    closes; a background job waits for the window and dismisses it, the same
    way Invoke-ShearDialog does for the edit dialog.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [int] $Tenths = 200
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\menu.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

$script:pass = 0
$script:fail = 0
function Check([string] $name, [bool] $ok, [string] $group, [string] $expected, [string] $detail) {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    Note ("{0,-56} {1}" -f $name, $(if ($ok) { 'PASS' } else { "FAIL  $detail" }))
    Add-ProbeResult -Group $group -Case $name -Expected $expected -Observed $detail `
                    -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
}

function Start-MenuDialogDriver {
    param([int] $Tenths = 0, [int] $TimeoutSeconds = 40)
    Start-Job -ScriptBlock {
        param($tenths, $timeout)
        Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class MenuShearDlg {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr p, int id);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static IntPtr Find() {
        IntPtr hit = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            var c = new StringBuilder(128);
            GetClassNameW(h, c, 128);
            if (c.ToString().Contains("VulpesNexusShearDialog")) { hit = h; return false; }
            return true;
        }, IntPtr.Zero);
        return hit;
    }
}
"@
        # Counts the dialogs rather than stopping at the first: one menu pick
        # that opens two dialogs would otherwise look identical to one that
        # opens one, and the effect would simply be applied twice.
        $seen = 0
        $deadline = (Get-Date).AddSeconds($timeout)
        while ((Get-Date) -lt $deadline) {
            $h = [MenuShearDlg]::Find()
            if ($h -ne [IntPtr]::Zero) {
                $seen++
                Start-Sleep -Milliseconds 600
                if ($tenths -ne 0) {
                    $slider = [MenuShearDlg]::GetDlgItem($h, 1001)
                    [MenuShearDlg]::SendMessage($slider, 1029, [IntPtr] 1, [IntPtr] $tenths) | Out-Null
                    [MenuShearDlg]::SendMessage($h, 0x0114, [IntPtr] 8, $slider) | Out-Null
                    Start-Sleep -Milliseconds 500
                }
                [MenuShearDlg]::PostMessage($h, 0x0100, [IntPtr] 0x0D, [IntPtr] 0) | Out-Null
                [MenuShearDlg]::PostMessage($h, 0x0101, [IntPtr] 0x0D, [IntPtr] 0) | Out-Null
                Start-Sleep -Milliseconds 1200
                continue
            }
            if ($seen -gt 0) { return "dialogs: $seen" }
            Start-Sleep -Milliseconds 200
        }
        return "dialogs: $seen (timed out)"
    } -ArgumentList $Tenths, $TimeoutSeconds
}

function Count-Shears([string] $name) {
    Js ("LS.doc().selection = [LS.named('{0}')]; ''" -f $name) | Out-Null
    ([regex]::Matches((Send-AiMessage 'appearance' ''), 'VulpesNexus Shear')).Count
}

Start-ProbeResults -Probe 'menu'
Install-AiHarness | Out-Null

# ---- where the host filed it --------------------------------------------
$placement = Send-AiMessage 'effect menu' ''
foreach ($line in ($placement -split "`r?`n")) { if ($line.Trim()) { Note ("    " + $line.Trim()) } }

$group = ''
$command = ''
$itemText = ''
foreach ($line in ($placement -split "`r?`n")) {
    $f = $line -split "`t", 2
    if ($f.Count -lt 2) { continue }
    switch ($f[0].Trim()) {
        'group'          { $group = $f[1].Trim() }
        'command string' { $command = $f[1].Trim() }
        'item text'      { $itemText = $f[1].Trim() }
    }
}

Check 'the item is on the Effect menu, not in a submenu' ($group -eq 'Effects 3rd Party') `
    'menu placement' 'the group is Effects 3rd Party' ("the group is '{0}'" -f $group)
Check 'no submenu of its own has come back' (-not ($group -like 'Live 3rd Party*')) `
    'menu placement' 'no group named Live 3rd Party...' ("the group is '{0}'" -f $group)
Check 'it is not inside one of Adobe s own submenus' (-not ($group -like 'Live Vector*')) `
    'menu placement' 'no group named Live Vector... -- that placement breaks Apply Last Effect' `
    ("the group is '{0}'" -f $group)
Check 'the item still reads Shear...' ($itemText -like 'Shear*') `
    'menu placement' 'Shear...' $itemText

# ---- choosing it ---------------------------------------------------------
Js @'
LS.clear();
var a = LS.paint(LS.rect(0, 200, 100, 60));
a.name = "menuA";
LS.doc().selection = [a];
"";
'@ | Out-Null

$driver = Start-MenuDialogDriver -Tenths $Tenths
# Built by concatenation, not -f: the script is mostly braces, and every one of
# them would have to be doubled to survive a format string.
Js ("try { app.executeMenuCommand('" + $command + "'); } catch (e) {} ''") | Out-Null
$drove = ((Receive-Job -Job $driver -Wait) -join '')
Remove-Job $driver -Force
Note ("    driver reported: " + $drove)

Check 'the command string reaches the item' ($drove -like 'dialogs: 1*') `
    'choosing it' 'one dialog opens' $drove

$onA = Count-Shears 'menuA'
Check 'choosing it applies exactly one Shear' ($onA -eq 1) `
    'choosing it' 'one Shear effect on the object' ("{0} Shear effect(s)" -f $onA)

# ---- Apply Last Effect ---------------------------------------------------
#
# The one the placement can break without raising anything. In the arrangement
# that puts the item inside Adobe's own submenu, this command returns normally
# and leaves the artwork alone.
Js @'
var b = LS.paint(LS.rect(0, 400, 100, 60));
b.name = "menuB";
LS.doc().selection = [b];
"";
'@ | Out-Null

$said = Js 'var r = ""; try { app.executeMenuCommand("Adobe Apply Last Effect"); r = "returned"; } catch (e) { r = "threw: " + e; } r;'
Note ("    Adobe Apply Last Effect " + $said)
$onB = Count-Shears 'menuB'
Check 'Apply Last Effect reapplies it to another object' ($onB -eq 1) `
    'Apply Last Effect' 'one Shear effect on the second object' `
    ("{0} Shear effect(s); the command {1}" -f $onB, $said)

Js 'LS.clear();' | Out-Null
Note ''
Note ("{0} passed, {1} failed" -f $script:pass, $script:fail)
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
Save-ProbeTranscript -Path $OutPath -Lines $log
Write-Output "Written to $OutPath"
