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
      * a new Shear opens its dialog with the angles and the axis button used
        last, and a canceled dialog is not remembered. This is the one route
        that applies a new effect through the dialog; editing an existing one
        is in probe-dialog.ps1. It also records what Illustrator itself hands
        a new effect, which is the reason the plugin remembers at all.

    Using the dialog changes what it remembers, so that is read first and put
    back in a finally block.

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
    param([int] $Tenths = 0, [int] $TimeoutSeconds = 40, [int[]] $Clicks = @(), [string] $Key = 'enter')
    Start-Job -ScriptBlock {
        param($tenths, $timeout, $clicks, $key)
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
    [DllImport("user32.dll", EntryPoint = "SendMessageW", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageBuf(IntPtr h, uint m, IntPtr w, StringBuilder l);
    public static string Text(IntPtr dialog, int id) {
        var s = new StringBuilder(64);
        SendMessageBuf(GetDlgItem(dialog, id), 0x000D, (IntPtr) 64, s);
        return s.ToString();
    }
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
        $opened = ''
        $deadline = (Get-Date).AddSeconds($timeout)
        while ((Get-Date) -lt $deadline) {
            $h = [MenuShearDlg]::Find()
            if ($h -ne [IntPtr]::Zero) {
                $seen++
                Start-Sleep -Milliseconds 600
                # What it opened with, before anything is touched: the two
                # fields, and which axis button answers BM_GETCHECK.
                $selected = @()
                $names = @{ 1007 = 'Horizontal'; 1008 = 'Vertical'; 1009 = 'Angle' }
                foreach ($id in 1007, 1008, 1009) {
                    $b = [MenuShearDlg]::GetDlgItem($h, $id)
                    if ([int64] [MenuShearDlg]::SendMessage($b, 0x00F0, [IntPtr]::Zero, [IntPtr]::Zero) -eq 1) { $selected += $names[$id] }
                }
                $opened = "opened with shear '{0}', axis '{1}', selected {2}" -f `
                    [MenuShearDlg]::Text($h, 1002), [MenuShearDlg]::Text($h, 1004), ($selected -join '+')
                foreach ($id in $clicks) {
                    [MenuShearDlg]::SendMessage([MenuShearDlg]::GetDlgItem($h, $id), 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
                    Start-Sleep -Milliseconds 300
                }
                if ($tenths -ne 0) {
                    $slider = [MenuShearDlg]::GetDlgItem($h, 1001)
                    [MenuShearDlg]::SendMessage($slider, 1029, [IntPtr] 1, [IntPtr] $tenths) | Out-Null
                    [MenuShearDlg]::SendMessage($h, 0x0114, [IntPtr] 8, $slider) | Out-Null
                    Start-Sleep -Milliseconds 500
                }
                $vk = if ($key -eq 'escape') { 0x1B } else { 0x0D }
                [MenuShearDlg]::PostMessage($h, 0x0100, [IntPtr] $vk, [IntPtr] 0) | Out-Null
                [MenuShearDlg]::PostMessage($h, 0x0101, [IntPtr] $vk, [IntPtr] 0) | Out-Null
                Start-Sleep -Milliseconds 1200
                continue
            }
            if ($seen -gt 0) { return "dialogs: $seen; $opened" }
            Start-Sleep -Milliseconds 200
        }
        return "dialogs: $seen (timed out); $opened"
    } -ArgumentList $Tenths, $TimeoutSeconds, $Clicks, $Key
}

function Near([double] $a, [double] $b, [double] $tol = 0.05) { [Math]::Abs($a - $b) -le $tol }

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
Check 'it is not inside one of Adobe''s own submenus' (-not ($group -like 'Live Vector*')) `
    'menu placement' 'no group named Live Vector... -- that placement breaks Apply Last Effect' `
    ("the group is '{0}'" -f $group)
Check 'the item still reads Shear...' ($itemText -like 'Shear*') `
    'menu placement' 'Shear...' $itemText

#  Draws a rectangle, picks the menu item on it with the driver working the
#  dialog, and reports what the dialog opened with and what the object ended
#  up holding.
function Invoke-MenuShear {
    param([string] $Name, [double] $Top, [int] $Tenths = 0, [int[]] $Clicks = @(), [string] $Key = 'enter')

    # Built by concatenation, not -f: the script is mostly braces, and every one
    # of them would have to be doubled to survive a format string.
    Js ("var o = LS.paint(LS.rect(0, " + (Format-AiNumber $Top) + ", 100, 60)); o.name = '" + $Name + "'; LS.doc().selection = [o]; '';") | Out-Null
    $driver = Start-MenuDialogDriver -Tenths $Tenths -Clicks $Clicks -Key $Key
    Js ("try { app.executeMenuCommand('" + $command + "'); } catch (e) {} ''") | Out-Null
    $drove = ((Receive-Job -Job $driver -Wait) -join '')
    Remove-Job $driver -Force
    # Assigned away because Note also writes to the pipeline, and anything
    # written there becomes part of what this function returns: the result
    # would be an array of two, whose Count is 2 whatever the object holds.
    $null = Note ("    {0}: driver reported: {1}" -f $Name, $drove)

    Js ("LS.doc().selection = [LS.named('{0}')]; ''" -f $Name) | Out-Null
    $appearance = Send-AiMessage 'appearance' ''
    $opened = [regex]::Match($drove, "opened with shear '([^']*)', axis '([^']*)', selected (\S*)")
    $stored = {
        param($key)
        $m = [regex]::Match($appearance, ([regex]::Escape($key) + ' \(Real\) = ([-0-9.]+)'))
        if ($m.Success) { [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) } else { [double]::NaN }
    }
    [pscustomobject]@{
        Drove       = $drove
        OpenShear   = $(if ($opened.Success) { $opened.Groups[1].Value } else { '' })
        OpenAxis    = $(if ($opened.Success) { $opened.Groups[2].Value } else { '' })
        Selected    = $(if ($opened.Success) { $opened.Groups[3].Value } else { '' })
        Count       = ([regex]::Matches($appearance, 'VulpesNexus Shear')).Count
        StoredShear = & $stored 'shearAngle'
        StoredAxis  = & $stored 'axisAngle'
    }
}

function Describe($r) {
    "the dialog opened reading {0} along {1} with {2} selected; the object holds {3} Shear effect(s), at {4} along {5}" -f `
        $r.OpenShear, $r.OpenAxis, $(if ($r.Selected) { $r.Selected } else { 'no button' }), $r.Count, $r.StoredShear, $r.StoredAxis
}

# Picking the menu item is how a person applies a new Shear, and the dialog
# remembers what it was last used with. That memory belongs to the person's
# Illustrator session, so it is read here and put back in the finally block.
$savedMemory = Get-ShearDialogMemory
Note ("    dialog memory on arrival: {0}; restored at the end" -f `
      $(if ($savedMemory.Remembered) { "{0} along {1}" -f $savedMemory.Shear, $savedMemory.Axis } else { 'nothing remembered' }))
Get-ShearDialogMemory 'forget' | Out-Null

try {
    # ---- choosing it -----------------------------------------------------
    Js 'LS.clear(); "";' | Out-Null
    $a = Invoke-MenuShear -Name 'menuA' -Top 200 -Tenths $Tenths

    Check 'the command string reaches the item' ($a.Drove -like 'dialogs: 1;*') `
        'choosing it' 'one dialog opens' $a.Drove
    Check 'choosing it applies exactly one Shear' ($a.Count -eq 1) `
        'choosing it' 'one Shear effect on the object' ("{0} Shear effect(s)" -f $a.Count)

    # ---- Apply Last Effect -----------------------------------------------
    #
    # The one the placement can break without raising anything. In the
    # arrangement that puts the item inside Adobe's own submenu, this command
    # returns normally and leaves the artwork alone.
    Js 'var b = LS.paint(LS.rect(0, 400, 100, 60)); b.name = "menuB"; LS.doc().selection = [b]; "";' | Out-Null

    $said = Js 'var r = ""; try { app.executeMenuCommand("Adobe Apply Last Effect"); r = "returned"; } catch (e) { r = "threw: " + e; } r;'
    Note ("    Adobe Apply Last Effect " + $said)
    $onB = Count-Shears 'menuB'
    Check 'Apply Last Effect reapplies it to another object' ($onB -eq 1) `
        'Apply Last Effect' 'one Shear effect on the second object' `
        ("{0} Shear effect(s); the command {1}" -f $onB, $said)

    # ---- the values used last ----------------------------------------------
    #
    # A new Shear opens with what the dialog last committed. menuA was committed
    # at the angle the driver set, with nothing remembered before it.
    $expectedShear = ($Tenths / 10).ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)
    $c = Invoke-MenuShear -Name 'menuC' -Top 600
    Check 'a new Shear opens with the angle committed last' `
        ($a.OpenShear -eq '0.0' -and $c.OpenShear -eq $expectedShear -and $c.Count -eq 1 -and (Near $c.StoredShear ($Tenths / 10))) `
        'the values used last' ("the first pick opened at {0} with nothing remembered and committed {1}; the next opens at {1}" -f $a.OpenShear, $expectedShear) `
        ("first pick: {0}. Second pick: {1}" -f (Describe $a), (Describe $c))

    # Whether Illustrator would have done this by itself: with the plugin's own
    # memory forgotten, what a new effect opens with is exactly what Illustrator
    # handed it. If this ever reads the last angle, the memory is redundant.
    Get-ShearDialogMemory 'forget' | Out-Null
    $d = Invoke-MenuShear -Name 'menuD' -Top 800
    Check 'Illustrator itself hands a new Shear the defaults, which is why the plugin remembers' `
        ($d.OpenShear -eq '0.0' -and $d.OpenAxis -eq '0.0') `
        'the values used last' 'with the plugin''s memory forgotten, the dialog opens at 0.0 along 0.0, though the effect was just applied at another angle' `
        (Describe $d)

    # The axis button travels with the angles.
    $e = Invoke-MenuShear -Name 'menuE' -Top 1000 -Clicks @(1008) -Tenths 150
    $f = Invoke-MenuShear -Name 'menuF' -Top 1200
    Check 'and with the axis button used last' `
        ($f.OpenShear -eq '15.0' -and $f.OpenAxis -eq '90.0' -and $f.Selected -eq 'Vertical' -and
         (Near $f.StoredShear 15) -and (Near $f.StoredAxis 90)) `
        'the values used last' 'after committing 15.0 along Vertical, the next new Shear opens at 15.0 with Vertical selected' `
        ("committed: {0}. Next pick: {1}" -f (Describe $e), (Describe $f))

    # Cancel is not remembered, and applies nothing.
    $g = Invoke-MenuShear -Name 'menuG' -Top 1400 -Tenths 350 -Key 'escape'
    $h = Invoke-MenuShear -Name 'menuH' -Top 1600
    Check 'a canceled dialog is not remembered' `
        ($g.Count -eq 0 -and $h.OpenShear -eq '15.0' -and $h.Selected -eq 'Vertical') `
        'the values used last' 'a dialog moved to 35.0 and canceled leaves no effect, and the next still opens at 15.0 along Vertical' `
        ("canceled: {0}. Next pick: {1}" -f (Describe $g), (Describe $h))

    Js 'LS.clear();' | Out-Null
}
finally {
    # Caught, because a host that died mid-run cannot be asked anything, and
    # the error from asking would replace the one that explains the run.
    try {
        $restored = Restore-ShearDialogMemory $savedMemory
        Note ("    dialog memory restored: {0}" -f `
              $(if ($restored.Remembered) { "{0} along {1}" -f $restored.Shear, $restored.Axis } else { 'nothing remembered' }))
    }
    catch {
        Note ("    dialog memory could NOT be restored, and Illustrator may keep this run's values: " + $_.Exception.Message)
    }
}
Note ''
Note ("{0} passed, {1} failed" -f $script:pass, $script:fail)
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
Save-ProbeTranscript -Path $OutPath -Lines $log
Write-Output "Written to $OutPath"
