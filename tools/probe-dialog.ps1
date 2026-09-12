<#
.SYNOPSIS
    Drives the Shear effect's dialog the way a person would, and checks what it
    leaves behind.

.DESCRIPTION
    Invoking the effect from the Effect menu opens a modal dialog, which blocks
    the scripting call that opened it. So the dialog is driven from a second
    PowerShell process: the foreground issues the menu command, a background job
    finds the window by its class name, moves the shear slider through a series
    of values, and then presses OK or Cancel.

    Three things are being checked:

      * OK commits the value the slider was left on
      * dragging through several values does not compound -- the artwork after
        10, 20, 30 then 40 degrees must equal a single 40 degree shear
      * Cancel restores the artwork exactly, leaving no effect behind

    Results go to docs\evidence\dialog.txt.
#>
[CmdletBinding()]
param([string] $LogPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $LogPath) { $LogPath = Join-Path $repo 'docs\evidence\dialog.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath)

$log = New-Object Collections.Generic.List[string]
$script:passed = 0
$script:failed = 0
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:passed++ } else { $script:failed++ }
    Note ("[{0}] {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name)
    if ($detail) { foreach ($d in ($detail -split "`n")) { Note ("       " + $d.TrimEnd()) } }
}
function Num([double] $v) { [Math]::Round($v, 3).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture) }
function Near([double] $a, [double] $b, [double] $tol = 0.01) { [Math]::Abs($a - $b) -le $tol }

# The window driver, run in a separate process so it can act while the
# scripting call that opened the dialog is still blocked.
$driver = {
    param([double[]] $Angles, [string] $Button, [string] $ResultFile, [string] $TypeInto)

    Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class Dlg {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")]
    public static extern IntPtr GetDlgItem(IntPtr parent, int id);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    // SetWindowText and GetWindowText are documented not to work on a control
    // owned by another process. WM_SETTEXT and WM_GETTEXT are marshalled by
    // the system, so they do.
    [DllImport("user32.dll", EntryPoint = "SendMessageW", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageText(IntPtr h, uint msg, IntPtr wp, string lp);
    [DllImport("user32.dll", EntryPoint = "SendMessageW", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageBuf(IntPtr h, uint msg, IntPtr wp, StringBuilder lp);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr h);

    // Finding the dialog by class name alone is unreliable: it is registered
    // with the ANSI entry point from inside the plug-in. Walking every visible
    // top-level window and matching either the class or the caption is not.
    public static IntPtr Find(string needle) {
        IntPtr hit = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            StringBuilder cls = new StringBuilder(256);
            GetClassNameW(h, cls, 256);
            StringBuilder cap = new StringBuilder(256);
            GetWindowTextW(h, cap, 256);
            if (cls.ToString().Contains(needle) || cap.ToString() == needle) { hit = h; return false; }
            return true;
        }, IntPtr.Zero);
        return hit;
    }
}
"@

    $TBM_SETPOS = 1029      # WM_USER + 5
    $WM_HSCROLL = 0x0114
    $SB_ENDSCROLL = 8
    $WM_COMMAND = 0x0111
    $IDOK = 1
    $IDCANCEL = 2
    $SHEAR_SLIDER = 1001
    $SHEAR_EDIT = 1002

    $lines = New-Object Collections.Generic.List[string]

    $deadline = (Get-Date).AddSeconds(30)
    $dialog = [IntPtr]::Zero
    while ((Get-Date) -lt $deadline) {
        $dialog = [Dlg]::Find('Shear')
        if ($dialog -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 200
    }
    if ($dialog -eq [IntPtr]::Zero) {
        $lines.Add('dialog never appeared')
        [System.IO.File]::WriteAllLines($ResultFile, $lines)
        return
    }
    $lines.Add('dialog found')

    $slider = [Dlg]::GetDlgItem($dialog, $SHEAR_SLIDER)
    $edit = [Dlg]::GetDlgItem($dialog, $SHEAR_EDIT)
    foreach ($a in $Angles) {
        $pos = [int][Math]::Round($a * 10)
        [Dlg]::SendMessage($slider, $TBM_SETPOS, [IntPtr] 1, [IntPtr] $pos) | Out-Null
        [Dlg]::SendMessage($dialog, $WM_HSCROLL, [IntPtr] $SB_ENDSCROLL, $slider) | Out-Null
        Start-Sleep -Milliseconds 250
        $sb = New-Object Text.StringBuilder 64
        [Dlg]::SendMessageBuf($edit, 0x000D, [IntPtr] 64, $sb) | Out-Null   # WM_GETTEXT
        $lines.Add(("slider set to {0}; numeric field now reads '{1}'" -f $a, $sb.ToString()))
    }

    if ($TypeInto) {
        $EN_KILLFOCUS = 512
        [Dlg]::SendMessageText($edit, 0x000C, [IntPtr]::Zero, $TypeInto) | Out-Null   # WM_SETTEXT
        $wp = [IntPtr] (($EN_KILLFOCUS -shl 16) -bor $SHEAR_EDIT)
        [Dlg]::SendMessage($dialog, $WM_COMMAND, $wp, $edit) | Out-Null
        Start-Sleep -Milliseconds 250
        $lines.Add("typed '$TypeInto' into the numeric field")
    }

    $id = if ($Button -eq 'cancel') { $IDCANCEL } else { $IDOK }
    $btn = [Dlg]::GetDlgItem($dialog, $id)
    $lines.Add("pressing $Button")
    [Dlg]::SendMessage($dialog, $WM_COMMAND, [IntPtr] $id, $btn) | Out-Null
    [System.IO.File]::WriteAllLines($ResultFile, $lines)
}

function Invoke-Dialog([double[]] $Angles, [string] $Button, [string] $TypeInto = '') {
    $resultFile = Join-Path $env:TEMP ("liveshear-dialog-{0}.txt" -f [Guid]::NewGuid().ToString('N'))
    $job = Start-Job -ScriptBlock $driver -ArgumentList $Angles, $Button, $resultFile, $TypeInto
    try {
        # Blocks until the dialog closes. This is the same call the Appearance
        # panel makes when an effect entry is double-clicked.
        Send-AiMessage 'edit effect' '0' | Out-Null
    }
    catch { }
    Wait-Job $job -Timeout 60 | Out-Null
    Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $job -Force
    $out = if (Test-Path $resultFile) { Get-Content $resultFile } else { @('no driver output') }
    if (Test-Path $resultFile) { [System.IO.File]::Delete($resultFile) }
    $out
}

function New-Rect {
    Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
    Invoke-AiScript 'var d = app.documents.add(DocumentColorSpace.RGB, 600, 600); d.rulerOrigin=[0,0]; var r = d.pathItems.rectangle(500,100,200,120); r.name="r"; r.filled=true; r.stroked=false; app.executeMenuCommand("deselectall"); r.selected = true;' | Out-Null
}

function RectBounds {
    $raw = Invoke-AiScript 'app.activeDocument.pathItems.getByName("r").visibleBounds.join(",");'
    ($raw -split ',' | ForEach-Object { [double] $_ })
}

Note 'Live Shear -- dialog probe'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ''

# --------------------------------------------------------- OK commits the value
# The dialog edits an effect that is already in the appearance, so one is put
# there first with a known starting angle.
New-Rect
$plain = RectBounds
Note ("plain rectangle: " + (($plain | ForEach-Object { Num $_ }) -join ', '))
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:5' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
$transcript = Invoke-Dialog @(10, 20, 30, 40) 'ok'
Note 'driver transcript:'
foreach ($t in $transcript) { Note ("       " + $t) }
Invoke-AiScript 'app.redraw();' | Out-Null
$afterOk = RectBounds
$appearance = Send-AiMessage appearance
$angle = [regex]::Match($appearance, 'shearAngle \(Real\) = ([-0-9.]+)')

Check 'the dialog opened and OK committed the slider value' `
    ($angle.Success -and (Near ([double]$angle.Groups[1].Value) 40 0.05)) `
    ("shearAngle in the appearance after OK: " + $(if ($angle.Success) { $angle.Groups[1].Value } else { 'not found' }))

# A 200 x 120 box sheared 40 degrees widens by tan(40) * 120 = 100.692 pt.
$expected = 200 + 120 * [Math]::Tan(40 * [Math]::PI / 180)
Check 'dragging through several values does not compound' `
    (Near ($afterOk[2] - $afterOk[0]) $expected 0.02) `
    ("width after dragging through 10, 20, 30, 40 is " + (Num ($afterOk[2] - $afterOk[0])) +
     " pt; a single 40 degree shear gives " + (Num $expected) +
     " pt; compounding would give far more")

# -------------------------------------------------------- Cancel leaves no trace
New-Rect
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:5' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
$before = RectBounds
$transcript = Invoke-Dialog @(35) 'cancel'
Note 'driver transcript:'
foreach ($t in $transcript) { Note ("       " + $t) }
Invoke-AiScript 'app.redraw();' | Out-Null
$afterCancel = RectBounds
$appearanceAfterCancel = Send-AiMessage appearance
$cancelAngle = [regex]::Match($appearanceAfterCancel, 'shearAngle \(Real\) = ([-0-9.]+)')
Check 'Cancel restores the artwork and the parameter it started with' `
    ((Near $afterCancel[0] $before[0]) -and (Near $afterCancel[2] $before[2]) -and
     $cancelAngle.Success -and (Near ([double]$cancelAngle.Groups[1].Value) 5 0.05)) `
    ("bounds before " + (($before | ForEach-Object { Num $_ }) -join ', ') +
     "; after cancel " + (($afterCancel | ForEach-Object { Num $_ }) -join ', ') +
     "; shearAngle after cancel " + $(if ($cancelAngle.Success) { $cancelAngle.Groups[1].Value } else { 'not found' }) +
     " (it was 5 before the dialog opened)")

# ------------------------------------------------------------- numeric entry
New-Rect
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:5' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
$transcript = Invoke-Dialog @() 'ok' '22.5'
Note 'driver transcript:'
foreach ($t in $transcript) { Note ("       " + $t) }
Invoke-AiScript 'app.redraw();' | Out-Null
$typedAppearance = Send-AiMessage appearance
$typedAngle = [regex]::Match($typedAppearance, 'shearAngle \(Real\) = ([-0-9.]+)')
Check 'a value typed into the numeric field is committed' `
    ($typedAngle.Success -and (Near ([double]$typedAngle.Groups[1].Value) 22.5 0.05)) `
    ("shearAngle after typing 22.5 and pressing OK: " + $(if ($typedAngle.Success) { $typedAngle.Groups[1].Value } else { 'not found' }))

Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null

Note ''
Note ("{0} passed, {1} failed" -f $script:passed, $script:failed)
[System.IO.File]::WriteAllLines($LogPath, $log)
Write-Output "`nWritten to $LogPath"
