<#
.SYNOPSIS
    Drives the Shear effect's dialog the way a person would, and checks what it
    leaves behind.

.DESCRIPTION
    Invoking the effect opens a modal dialog, which blocks the scripting call
    that opened it. So the dialog is driven from a second PowerShell process:
    the foreground issues the edit command, a background job finds the window,
    works the controls, and then dismisses it.

    While the dialog is up the foreground cannot ask Illustrator anything, so
    the checks that need to know what the artwork did *during* the dialog read
    the plugin's own trace file instead. Set LIVESHEAR_LOG before starting
    Illustrator and pass the same path here.

    Checked: OK commits, Cancel restores, Escape cancels, Enter commits, the
    close button cancels, preview off leaves the artwork alone until OK,
    dragging does not compound, typed values commit, and the arrow keys nudge.
#>
[CmdletBinding()]
param(
    [string] $LogPath,
    [string] $TracePath = $env:LIVESHEAR_LOG
)

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
    Add-ProbeResult -Group 'dialog' -Case $name -Expected 'the dialog behaves like an Adobe dialog' -Observed $detail -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
}
function Num([double] $v) { [Math]::Round($v, 3).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture) }
function Near([double] $a, [double] $b, [double] $tol = 0.01) { [Math]::Abs($a - $b) -le $tol }

# The window driver, run in a separate process so it can act while the
# scripting call that opened the dialog is still blocked.
$driver = {
    param([double[]] $Angles, [string] $Button, [string] $ResultFile, [string] $TypeInto,
          [int] $PreviewClicks, [int] $ArrowUps, [string] $TracePath)

    Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Dlg {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")]
    public static extern IntPtr GetDlgItem(IntPtr parent, int id);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool PostMessage(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
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
    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    // Finding the dialog by class name alone is unreliable: it is registered
    // with the ANSI entry point from inside the plugin. Walking every visible
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
    $WM_KEYDOWN = 0x0100
    $WM_CLOSE = 0x0010
    $BM_CLICK = 0x00F5
    $VK_RETURN = 0x0D
    $VK_ESCAPE = 0x1B
    $VK_UP = 0x26
    $IDOK = 1
    $IDCANCEL = 2
    $SHEAR_SLIDER = 1001
    $SHEAR_EDIT = 1002
    $PREVIEW = 1005

    $lines = New-Object Collections.Generic.List[string]

    $deadline = (Get-Date).AddSeconds(30)
    $dialog = [IntPtr]::Zero
    while ((Get-Date) -lt $deadline) {
        $dialog = [Dlg]::Find('VulpesNexusShearDialog')
        if ($dialog -eq [IntPtr]::Zero) { $dialog = [Dlg]::Find('Shear') }
        if ($dialog -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 200
    }
    if ($dialog -eq [IntPtr]::Zero) {
        $lines.Add('dialog never appeared')
        [System.IO.File]::WriteAllLines($ResultFile, $lines)
        return
    }
    $rect = New-Object Dlg+RECT
    [Dlg]::GetWindowRect($dialog, [ref] $rect) | Out-Null
    $lines.Add(("dialog found, {0} by {1} pixels" -f ($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top)))

    $slider = [Dlg]::GetDlgItem($dialog, $SHEAR_SLIDER)
    $edit = [Dlg]::GetDlgItem($dialog, $SHEAR_EDIT)
    $preview = [Dlg]::GetDlgItem($dialog, $PREVIEW)

    for ($i = 0; $i -lt $PreviewClicks; $i++) {
        [Dlg]::SendMessage($preview, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 150
        $lines.Add('clicked the Preview box')
    }

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

    for ($i = 0; $i -lt $ArrowUps; $i++) {
        [Dlg]::PostMessage($edit, $WM_KEYDOWN, [IntPtr] $VK_UP, [IntPtr] 0) | Out-Null
        Start-Sleep -Milliseconds 200
    }
    if ($ArrowUps -gt 0) {
        $sb = New-Object Text.StringBuilder 64
        [Dlg]::SendMessageBuf($edit, 0x000D, [IntPtr] 64, $sb) | Out-Null
        $lines.Add(("{0} up arrows; numeric field now reads '{1}'" -f $ArrowUps, $sb.ToString()))
    }

    # What the effect was last asked to render while the dialog was still open.
    if ($TracePath -and (Test-Path $TracePath)) {
        $go = Get-Content $TracePath | Where-Object { $_ -match 'Go: artType' } | Select-Object -Last 1
        if ($go) { $lines.Add("last evaluation during the dialog: " + $go.Trim()) }
    }

    switch ($Button) {
        'cancel' {
            $btn = [Dlg]::GetDlgItem($dialog, $IDCANCEL)
            $lines.Add('pressing Cancel')
            [Dlg]::SendMessage($dialog, $WM_COMMAND, [IntPtr] $IDCANCEL, $btn) | Out-Null
        }
        'escape' {
            $lines.Add('pressing Escape')
            [Dlg]::PostMessage($dialog, $WM_KEYDOWN, [IntPtr] $VK_ESCAPE, [IntPtr] 0) | Out-Null
        }
        'enter' {
            $lines.Add('pressing Enter')
            [Dlg]::PostMessage($dialog, $WM_KEYDOWN, [IntPtr] $VK_RETURN, [IntPtr] 0) | Out-Null
        }
        'close' {
            $lines.Add('pressing the title bar close button')
            [Dlg]::PostMessage($dialog, $WM_CLOSE, [IntPtr] 0, [IntPtr] 0) | Out-Null
        }
        default {
            $btn = [Dlg]::GetDlgItem($dialog, $IDOK)
            $lines.Add('pressing OK')
            [Dlg]::SendMessage($dialog, $WM_COMMAND, [IntPtr] $IDOK, $btn) | Out-Null
        }
    }

    Start-Sleep -Milliseconds 500
    $lines.Add("dialog still open afterwards: " + [Dlg]::IsWindow($dialog))
    [System.IO.File]::WriteAllLines($ResultFile, $lines)
}

function Invoke-Dialog {
    param(
        [double[]] $Angles = @(),
        [string] $Button = 'ok',
        [string] $TypeInto = '',
        [int] $PreviewClicks = 0,
        [int] $ArrowUps = 0
    )
    $resultFile = Join-Path $env:TEMP ("liveshear-dialog-{0}.txt" -f [Guid]::NewGuid().ToString('N'))
    $job = Start-Job -ScriptBlock $driver -ArgumentList $Angles, $Button, $resultFile, $TypeInto, $PreviewClicks, $ArrowUps, $TracePath
    try {
        # Blocks until the dialog closes. This is the same call the Appearance
        # panel makes when an effect entry is double-clicked.
        Send-AiMessage 'edit effect' '0' | Out-Null
    }
    catch { }
    Wait-Job $job -Timeout 90 | Out-Null
    Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $job -Force
    $out = if (Test-Path $resultFile) { Get-Content $resultFile } else { @('no driver output') }
    if (Test-Path $resultFile) { [System.IO.File]::Delete($resultFile) }
    $out
}

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'dialog'

function New-Case([double] $startAngle = 5) {
    Invoke-AiScript "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.selectOnly(LS.target); 'built';" | Out-Null
    Invoke-AiScript 'app.redraw();' | Out-Null
    Invoke-AiScript ("LS.shear({0}, 0);" -f $startAngle) | Out-Null
    Invoke-AiScript 'app.redraw();' | Out-Null
}
function CaseBounds {
    ((Invoke-AiScript 'LS.vb(LS.target);').Trim() -split ',' | ForEach-Object { [double] $_ })
}
function StoredAngle {
    $a = Send-AiMessage appearance
    $m = [regex]::Match($a, 'shearAngle \(Real\) = ([-0-9.]+)')
    if ($m.Success) { [double] $m.Groups[1].Value } else { [double]::NaN }
}

Note 'Live Shear -- dialog probe'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Trace file: {0}" -f $(if ($TracePath) { $TracePath } else { 'not set -- preview checks will be skipped' }))
Note ''

# --------------------------------------------------------- OK commits the value
New-Case 5
$transcript = Invoke-Dialog -Angles @(10, 20, 30, 40) -Button 'ok'
Note 'driver transcript:'
foreach ($t in $transcript) { Note ("       " + $t) }
Invoke-AiScript 'app.redraw();' | Out-Null
$afterOk = CaseBounds
$angle = StoredAngle
Check 'the dialog opened and OK committed the slider value' (Near $angle 40 0.05) ("shearAngle in the appearance after OK: " + $angle)

# A 200 x 120 box sheared 40 degrees widens by tan(40) * 120 = 100.692 pt.
$expected = 200 + 120 * [Math]::Tan(40 * [Math]::PI / 180)
Check 'dragging through several values does not compound' (Near ($afterOk[2] - $afterOk[0]) $expected 0.02) ("width after dragging through 10, 20, 30, 40 is " + (Num ($afterOk[2] - $afterOk[0])) + " pt; a single 40 degree shear gives " + (Num $expected) + " pt; compounding would give far more")

# -------------------------------------------------------- Cancel leaves no trace
foreach ($dismiss in @('cancel', 'escape', 'close')) {
    New-Case 5
    $before = CaseBounds
    $transcript = Invoke-Dialog -Angles @(35) -Button $dismiss
    Note ("driver transcript ({0}):" -f $dismiss)
    foreach ($t in $transcript) { Note ("       " + $t) }
    Invoke-AiScript 'app.redraw();' | Out-Null
    $after = CaseBounds
    $angleAfter = StoredAngle
    $closed = ($transcript -join ' ') -match 'dialog still open afterwards: False'
    Check ("{0} restores the artwork and the parameter it started with" -f $dismiss) ((Near $after[0] $before[0]) -and (Near $after[2] $before[2]) -and (Near $angleAfter 5 0.05) -and $closed) ("bounds before " + (($before | ForEach-Object { Num $_ }) -join ', ') + "; after " + (($after | ForEach-Object { Num $_ }) -join ', ') + "; shearAngle after " + $angleAfter + " (it was 5)")
}

# ----------------------------------------------------------------- Enter commits
New-Case 5
$transcript = Invoke-Dialog -Angles @(33) -Button 'enter'
Note 'driver transcript (enter):'
foreach ($t in $transcript) { Note ("       " + $t) }
Invoke-AiScript 'app.redraw();' | Out-Null
Check 'Enter commits, like the default button' (Near (StoredAngle) 33 0.05) ("shearAngle after Enter: " + (StoredAngle))

# ------------------------------------------------------------- numeric entry
New-Case 5
$transcript = Invoke-Dialog -Button 'ok' -TypeInto '22,5'
Note 'driver transcript (typed with a decimal comma):'
foreach ($t in $transcript) { Note ("       " + $t) }
Invoke-AiScript 'app.redraw();' | Out-Null
Check 'a value typed with a decimal comma is committed' (Near (StoredAngle) 22.5 0.05) ("shearAngle after typing 22,5 and pressing OK: " + (StoredAngle))

New-Case 5
$transcript = Invoke-Dialog -Button 'ok' -TypeInto '18.25 deg'
Note 'driver transcript (typed with trailing text):'
foreach ($t in $transcript) { Note ("       " + $t) }
Invoke-AiScript 'app.redraw();' | Out-Null
Check 'a value typed with trailing text still reads as a number' (Near (StoredAngle) 18.25 0.05) ("shearAngle after typing '18.25 deg': " + (StoredAngle))

New-Case 5
$transcript = Invoke-Dialog -Button 'ok' -TypeInto '95'
Note 'driver transcript (typed past the limit):'
foreach ($t in $transcript) { Note ("       " + $t) }
Invoke-AiScript 'app.redraw();' | Out-Null
Check 'a value typed past the limit is clamped to 89' (Near (StoredAngle) 89 0.05) ("shearAngle after typing 95: " + (StoredAngle))

# --------------------------------------------------------------- arrow keys
New-Case 10
$transcript = Invoke-Dialog -Button 'ok' -ArrowUps 3
Note 'driver transcript (arrow keys):'
foreach ($t in $transcript) { Note ("       " + $t) }
Invoke-AiScript 'app.redraw();' | Out-Null
Check 'three up arrows raise the angle by three degrees' (Near (StoredAngle) 13 0.05) ("shearAngle after three up arrows from 10: " + (StoredAngle))

# ------------------------------------------------------------- preview off
if ($TracePath) {
    New-Case 5
    $before = CaseBounds
    $transcript = Invoke-Dialog -Angles @(44) -Button 'ok' -PreviewClicks 1
    Note 'driver transcript (preview off):'
    foreach ($t in $transcript) { Note ("       " + $t) }
    $duringLine = ($transcript | Where-Object { $_ -match 'last evaluation during the dialog' }) -join ''
    $duringAngle = if ($duringLine -match 'shear=([-0-9.]+)') { [double] $Matches[1] } else { [double]::NaN }
    Invoke-AiScript 'app.redraw();' | Out-Null
    $after = CaseBounds
    Check 'with Preview off the artwork is not redrawn at the new angle' (Near $duringAngle 5 0.05) ("the effect was last evaluated at " + $duringAngle + " degrees while the dialog was open; it started at 5")
    Check 'and OK still commits the new angle' (Near (StoredAngle) 44 0.05) ("shearAngle after OK: " + (StoredAngle) + "; bounds " + (($after | ForEach-Object { Num $_ }) -join ', ') + " (were " + (($before | ForEach-Object { Num $_ }) -join ', ') + ")")
}

Invoke-AiScript 'LS.clear(); "cleared";' | Out-Null

if ($TracePath -and (Test-Path $TracePath)) {
    $dpi = Get-Content $TracePath | Where-Object { $_ -match 'dialog: closed' } | Select-Object -Last 1
    if ($dpi) { Note ("last dialog trace line: " + $dpi.Trim()) }
}

Note ''
Note ("{0} passed, {1} failed" -f $script:passed, $script:failed)
Save-ProbeResults -Path ($LogPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($LogPath, $log)
Write-Output "`nWritten to $LogPath"
