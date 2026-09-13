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
          [int] $PreviewClicks, [int] $ArrowUps, [string] $TracePath, [string] $ShotPath)

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
    public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    // Posting a key message never touches the keyboard state, so the dialog's
    // GetKeyState(VK_SHIFT) reads whatever is ambient -- including a Shift the
    // person at the machine is holding. keybd_event does change it, so the
    // driver can put Shift down and up for real.
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint from, uint to, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);

    // Windows refuses SetForegroundWindow to a process that does not already
    // own the foreground, which a background job never does. Attaching to the
    // foreground thread's input queue for the duration of the call is the
    // documented way around it.
    public static bool ForceForeground(IntPtr h) {
        uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
        uint me = GetCurrentThreadId();
        bool attached = fg != 0 && fg != me && AttachThreadInput(fg, me, true);
        bool ok = SetForegroundWindow(h);
        if (attached) AttachThreadInput(fg, me, false);
        return ok;
    }
    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool GetMonitorInfoW(IntPtr mon, ref MONITORINFO mi);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public int dwFlags; }

    // The work area of the monitor a window is on -- the desktop minus the
    // taskbar. What "still somewhere a person can reach" means.
    public static bool WorkAreaOf(IntPtr h, out RECT work) {
        work = new RECT();
        MONITORINFO mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        IntPtr mon = MonitorFromWindow(h, 2);   // MONITOR_DEFAULTTONEAREST
        if (mon == IntPtr.Zero || !GetMonitorInfoW(mon, ref mi)) return false;
        work = mi.rcWork;
        return true;
    }

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

    # Where it opened, which is not the same question as how big it is. The
    # dialog is a popup window, and CW_USEDEFAULT does not pick a position for
    # a popup -- it is documented to set x and y to zero -- so every invocation
    # used to open in the top-left corner of the primary monitor no matter
    # where Illustrator was. Nothing here looked at a coordinate, so nothing
    # noticed.
    $ai = Get-Process Illustrator -ErrorAction SilentlyContinue |
          Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if ($ai) {
        $owner = New-Object Dlg+RECT
        [Dlg]::GetWindowRect($ai.MainWindowHandle, [ref] $owner) | Out-Null
        $work = New-Object Dlg+RECT
        [Dlg]::WorkAreaOf($dialog, [ref] $work) | Out-Null
        $dx = [int](($rect.Left + $rect.Right) / 2 - ($owner.Left + $owner.Right) / 2)
        $dy = [int](($rect.Top + $rect.Bottom) / 2 - ($owner.Top + $owner.Bottom) / 2)
        $inside = $rect.Left -ge $work.Left -and $rect.Top -ge $work.Top -and
                  $rect.Right -le $work.Right -and $rect.Bottom -le $work.Bottom
        $lines.Add(("placed at {0},{1}; Illustrator's window is {2},{3} to {4},{5}; centers differ by {6},{7} pixels" -f `
            $rect.Left, $rect.Top, $owner.Left, $owner.Top, $owner.Right, $owner.Bottom, $dx, $dy))
        $lines.Add(("work area is {0},{1} to {2},{3}; the dialog is entirely inside it: {4}" -f `
            $work.Left, $work.Top, $work.Right, $work.Bottom, $inside))
    }
    else {
        $lines.Add(("placed at {0},{1}; Illustrator's own window could not be found to compare against" -f $rect.Left, $rect.Top))
    }

    # A picture of the dialog, so "the labels are not clipped and the fields are
    # usable" is something a reader can check rather than take on trust.
    if ($ShotPath) {
        try {
            Add-Type -AssemblyName System.Drawing
            $client = New-Object Dlg+RECT
            [Dlg]::GetClientRect($dialog, [ref] $client) | Out-Null
            $w = $client.Right - $client.Left
            $h = $client.Bottom - $client.Top
            if ($w -gt 0 -and $h -gt 0) {
                $bmp = New-Object System.Drawing.Bitmap $w, $h
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $dc = $g.GetHdc()
                [Dlg]::PrintWindow($dialog, $dc, 2) | Out-Null
                $g.ReleaseHdc($dc)
                $g.Dispose()
                $bmp.Save($ShotPath)
                $bmp.Dispose()
                $lines.Add(("captured the dialog to {0}, client area {1} by {2}" -f $ShotPath, $w, $h))
            }
        }
        catch { $lines.Add("could not capture the dialog: " + $_.Exception.Message) }
    }

    # The text the window actually holds, as code points. The dialog was
    # mixing the narrow and wide Windows entry points once, which turned its
    # title into two Chinese characters and its degree sign into two half-width
    # katakana on a Japanese Windows. Reading the code points back is the only
    # way to be sure that has not come back.
    $cap = New-Object Text.StringBuilder 256
    [Dlg]::GetWindowTextW($dialog, $cap, 256) | Out-Null
    $capText = $cap.ToString()
    $capCodes = (($capText.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' ')
    $lines.Add("caption: '$capText'   $capCodes")

    $childCb = [Dlg+EnumProc]{ param($h, $l)
        $t = New-Object Text.StringBuilder 128
        [Dlg]::GetWindowTextW($h, $t, 128) | Out-Null
        $s = $t.ToString()
        if ($s.Length -gt 0) {
            $c = (($s.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' ')
            $lines.Add("  label: '$s'   $c")
        }
        return $true }
    [Dlg]::EnumChildWindows($dialog, $childCb, [IntPtr]::Zero) | Out-Null

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

    if ($ArrowUps -gt 0) {
        # The dialog nudges by one degree, or by ten with Shift held, and it
        # asks GetKeyState which key is down. GetKeyState answers out of the
        # calling thread's *synchronized* key state, and only real input that
        # that thread processes ever updates it -- a posted message is not real
        # input. So the dialog answers out of the last hardware key its own
        # thread saw, which can be a Shift pressed in another window minutes
        # ago and released while this thread was not in the foreground to see
        # the release.
        #
        # Not hypothetical: three arrows once moved the angle by thirty degrees,
        # and a suite run moved it by twelve -- ten, then one, then one -- with
        # nothing wrong in the plugin either time. Injecting a Shift-up alone
        # does not fix it, because injected input goes to whichever thread owns
        # the foreground, and in a suite that is rarely this one.
        #
        # So the dialog is pulled to the front first, and then Shift is pressed
        # and released for real, so this thread certainly processes both and its
        # idea of the keyboard is known rather than inherited. After that, a
        # ten-degree step is a defect rather than an artifact.
        $fg = [Dlg]::ForceForeground($dialog)
        Start-Sleep -Milliseconds 250
        [Dlg]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero)   # VK_SHIFT down, for real
        Start-Sleep -Milliseconds 80
        [Dlg]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero)   # VK_SHIFT up, for real
        Start-Sleep -Milliseconds 250
        $held = ([Dlg]::GetAsyncKeyState(0x10) -band 0x8000) -ne 0
        $lines.Add(("brought the dialog to the front: {0}; Shift cycled down and up; physically held afterwards: {1}" -f $fg, $held))
    }
    # Read after every arrow rather than only at the end. A wrong total says
    # nothing about which step was wrong, and the one failure this has ever had
    # shows up as a single ten among ones.
    $steps = New-Object Collections.Generic.List[string]
    for ($i = 0; $i -lt $ArrowUps; $i++) {
        [Dlg]::PostMessage($edit, $WM_KEYDOWN, [IntPtr] $VK_UP, [IntPtr] 0) | Out-Null
        Start-Sleep -Milliseconds 200
        $sb = New-Object Text.StringBuilder 64
        [Dlg]::SendMessageBuf($edit, 0x000D, [IntPtr] 64, $sb) | Out-Null
        $steps.Add($sb.ToString())
    }
    if ($ArrowUps -gt 0) {
        $lines.Add(("{0} up arrows; the field read {1} in turn" -f $ArrowUps, ($steps -join ', ')))
        $lines.Add(("{0} up arrows; numeric field now reads '{1}'" -f $ArrowUps, $steps[$steps.Count - 1]))
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
        [int] $ArrowUps = 0,
        [string] $ShotPath = ''
    )
    $resultFile = Join-Path $env:TEMP ("liveshear-dialog-{0}.txt" -f [Guid]::NewGuid().ToString('N'))
    $job = Start-Job -ScriptBlock $driver -ArgumentList $Angles, $Button, $resultFile, $TypeInto, $PreviewClicks, $ArrowUps, $TracePath, $ShotPath
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
    Invoke-AiScript ("LS.shear({0}, 0);" -f (Format-AiNumber $startAngle)) | Out-Null
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

# The plugin reads LIVESHEAR_LOG out of Illustrator's environment, not out of
# this one, so setting it here after Illustrator started does nothing at all.
# That is easy to miss and it turns a behavior check into a silent failure, so
# ask the plugin whether it is really writing before relying on it.
$traceIsLive = $false
if ($TracePath) {
    $before = if (Test-Path $TracePath) { (Get-Item $TracePath).Length } else { -1 }
    Invoke-AiScript 'LS.clear(); LS.target = LS.fixtures["plainRect"](); LS.selectOnly(LS.target);' | Out-Null
    Invoke-AiScript 'LS.shear(7, 0);' | Out-Null
    Invoke-AiScript 'app.redraw();' | Out-Null
    $after = if (Test-Path $TracePath) { (Get-Item $TracePath).Length } else { -1 }
    $traceIsLive = ($after -gt $before)
    Note ("Tracing is live: {0}" -f $(if ($traceIsLive) { 'yes' } else { 'no -- Illustrator was started without LIVESHEAR_LOG in its environment' }))
}
Note ''

# --------------------------------------------------------- OK commits the value
New-Case 5
$shot = Join-Path $repo 'docs\evidence\dialog.png'
$transcript = Invoke-Dialog -Angles @(10, 20, 30, 40) -Button 'ok' -ShotPath $shot
Note 'driver transcript:'
foreach ($t in $transcript) { Note ("       " + $t) }
Invoke-AiScript 'app.redraw();' | Out-Null
$afterOk = CaseBounds
$angle = StoredAngle
Check 'the dialog opened and OK committed the slider value' (Near $angle 40 0.05) ("shearAngle in the appearance after OK: " + $angle)

$transcriptText = ($transcript -join "`n")
$caption = if ($transcriptText -match "caption: '([^']*)'") { $Matches[1] } else { '' }
Check 'the window title reads Shear' ($caption -eq 'Shear') ("the title bar holds '" + $caption + "'")
# Said as an observation rather than as an accusation, because this detail is
# what the generated matrix publishes and a passing row must not carry the
# sentence that belongs to a failing one.
$degrees = ([regex]::Matches($transcriptText, 'U\+00B0')).Count
Check 'the degree sign is a degree sign' ($degrees -gt 0) ("U+00B0 appears {0} time(s) among the dialog's labels" -f $degrees)

# --------------------------------------------------------------- where it opens
#
# The dialog is a popup window, and CW_USEDEFAULT picks no position for one:
# it is documented to set x and y to zero instead. So the dialog opened in the
# top-left corner of the primary monitor every single time, and no check here
# had ever looked at a coordinate.
function Get-Placement([string] $text) {
    $m = [regex]::Match($text, "placed at (-?\d+),(-?\d+);.*centers differ by (-?\d+),(-?\d+) pixels")
    if (-not $m.Success) { return $null }
    $w = [regex]::Match($text, "the dialog is entirely inside it: (\w+)")
    [pscustomobject]@{
        X      = [int] $m.Groups[1].Value
        Y      = [int] $m.Groups[2].Value
        Dx     = [int] $m.Groups[3].Value
        Dy     = [int] $m.Groups[4].Value
        Inside = $w.Success -and $w.Groups[1].Value -eq 'True'
        Line   = $m.Value
    }
}

$place = Get-Placement $transcriptText
# Four pixels, not zero: the centering divides by two in integers, and the two
# sides round independently here and in the plugin. The failure this guards
# against is measured in hundreds.
Check 'the dialog opens centered on Illustrator, not in a corner' `
    ($null -ne $place -and [Math]::Abs($place.Dx) -le 4 -and [Math]::Abs($place.Dy) -le 4) `
    $(if ($null -eq $place) { 'the driver could not read the placement back' }
      else { "{0}; a top-left corner placement would be 0,0" -f $place.Line })
Check 'and entirely inside the monitor work area' `
    ($null -ne $place -and $place.Inside) `
    $(if ($null -eq $place) { 'the driver could not read the placement back' }
      else { "opened at {0},{1}, with no part of it off the desktop or under the taskbar" -f $place.X, $place.Y })

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
# 18.3 rather than 18.25, and deliberately. The sliders carry tenths of a
# degree and the fields show one decimal, so a tenth is the resolution this
# dialog can express; rounding once on the way in is what makes the number
# shown, the slider position, and the value stored the same number. Asserting
# 18.25 here would be asserting the bug this replaced -- three different
# roundings of one typed value. The documented behavior is in
# KNOWN_LIMITATIONS.md, and a script writing the dictionary directly still gets
# full precision.
Check 'a value typed with trailing text reads as a number, at the dialog''s resolution' (Near (StoredAngle) 18.3 0.001) ("typing '18.25 deg' committed " + (StoredAngle) + " degrees: the trailing text is ignored and the value is rounded once, to the tenth of a degree the sliders and fields work in")

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
$arrowSteps = if (($transcript -join "`n") -match 'the field read ([^\r\n]+) in turn') { $Matches[1] } else { 'not recorded' }
# The per-step readings are in the detail because the way this goes wrong is a
# single ten among ones, and a bare total of 22 does not say that.
Check 'three up arrows raise the angle by three degrees' (Near (StoredAngle) 13 0.05) `
    ("shearAngle after three up arrows from 10: " + (StoredAngle) + "; the field read " + $arrowSteps + " in turn")

# ------------------------------------------------------------- preview off
if ($TracePath) {
    New-Case 5
    $before = CaseBounds
    $transcript = Invoke-Dialog -Angles @(44) -Button 'ok' -PreviewClicks 1
    Note 'driver transcript (preview off):'
    foreach ($t in $transcript) { Note ("       " + $t) }
    $duringLine = ($transcript | Where-Object { $_ -match 'last evaluation during the dialog' }) -join ''
    Invoke-AiScript 'app.redraw();' | Out-Null
    $after = CaseBounds

    if (-not $traceIsLive) {
        # Without a trace there is no way to ask what the artwork did while a
        # modal dialog held every other route shut. Saying so is the honest
        # answer; failing the check would report a defect that was never
        # measured.
        Note '[SKIP] with Preview off the artwork is not redrawn at the new angle'
        Note '       the plugin is not writing a trace, so there is nothing to read this out of'
        Add-ProbeResult -Group 'dialog' -Case 'with Preview off the artwork is not redrawn at the new angle' `
            -Expected 'the dialog behaves like an Adobe dialog' `
            -Observed 'the plugin was not writing a trace during this run, and while a modal dialog is up there is no other way to ask' -Status 'INCONCLUSIVE'
    }
    elseif (-not $duringLine) {
        # Better than the angle staying put: the effect was never asked to run
        # at all while Preview was off.
        Check 'with Preview off the artwork is not redrawn at the new angle' $true 'the effect was not evaluated at all while the dialog was open'
    }
    else {
        $duringAngle = if ($duringLine -match 'shear=([-0-9.]+)') { [double] $Matches[1] } else { [double]::NaN }
        Check 'with Preview off the artwork is not redrawn at the new angle' (Near $duringAngle 5 0.05) ("the effect was last evaluated at " + $duringAngle + " degrees while the dialog was open; it started at 5")
    }
    Check 'and OK still commits the new angle' (Near (StoredAngle) 44 0.05) ("shearAngle after OK: " + (StoredAngle) + "; bounds " + (($after | ForEach-Object { Num $_ }) -join ', ') + " (were " + (($before | ForEach-Object { Num $_ }) -join ', ') + ")")
}

# ------------------------------------- the clamp, with Illustrator off the edge
#
# Centering is easy to get right in the middle of a screen and easy to get
# wrong at its edge, and the clamp that handles the edge is the part no
# ordinary run exercises. So Illustrator is put in the corner of the work area
# and made small enough that its own middle is less than half a dialog from the
# edge -- centering alone would then put a good part of the dialog past it --
# and the dialog is opened from there. The window's placement is saved first
# and put back afterwards, maximized state included.
#
# Illustrator will not be moved to a negative coordinate: asked to sit off the
# left of the desktop it comes back to zero. So the overshoot this arranges is
# the vertical one, and the check reads whichever axis actually overshot rather
# than assuming which.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class HostWin {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct WINDOWPLACEMENT {
        public int length, flags, showCmd;
        public POINT ptMinPosition, ptMaxPosition;
        public RECT rcNormalPosition;
    }
    [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT p);
    [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT p);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
}
"@ -ErrorAction SilentlyContinue

$aiProc = Get-Process Illustrator -ErrorAction SilentlyContinue |
          Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
if (-not $aiProc) {
    Note '[SKIP] the dialog is pushed back on screen when Illustrator sits in the corner'
    Note '       Illustrator has no main window handle to move'
    Add-ProbeResult -Group 'dialog' -Case 'the dialog is pushed back on screen when Illustrator sits in the corner' `
        -Expected 'the dialog behaves like an Adobe dialog' `
        -Observed 'Illustrator reported no main window, so it could not be moved to the edge' -Status 'INCONCLUSIVE'
}
else {
    $hwnd = $aiProc.MainWindowHandle
    $saved = New-Object HostWin+WINDOWPLACEMENT
    $saved.length = [Runtime.InteropServices.Marshal]::SizeOf([type] 'HostWin+WINDOWPLACEMENT')
    $havePlacement = [HostWin]::GetWindowPlacement($hwnd, [ref] $saved)
    try {
        [HostWin]::ShowWindow($hwnd, 9) | Out-Null        # SW_RESTORE
        Start-Sleep -Milliseconds 600
        # SWP_NOZORDER | SWP_NOACTIVATE. Small enough that half of it is less
        # than half the dialog, in the corner, so the middle of the window is
        # nearer the edge than the dialog's own half-height.
        [HostWin]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, 400, 140, 0x0014) | Out-Null
        Start-Sleep -Milliseconds 800
        $r = New-Object HostWin+RECT
        [HostWin]::GetWindowRect($hwnd, [ref] $r) | Out-Null
        Note ("Illustrator is at {0},{1} to {2},{3}; its middle is {4},{5}" -f `
              $r.Left, $r.Top, $r.Right, $r.Bottom, [int](($r.Left + $r.Right) / 2), [int](($r.Top + $r.Bottom) / 2))

        New-Case 5
        $transcript = Invoke-Dialog -Angles @(12) -Button 'cancel'
        Note 'driver transcript (Illustrator in the corner):'
        foreach ($t in $transcript) { Note ("       " + $t) }
        $edge = Get-Placement (($transcript -join "`n"))
        # The distance between the two centers is the overshoot the clamp took
        # back: with nothing to clamp they coincide, as they do in every case
        # above.
        $pushed = if ($null -eq $edge) { 0 } else { [Math]::Max([Math]::Abs($edge.Dx), [Math]::Abs($edge.Dy)) }

        if ($null -eq $edge) {
            Check 'the dialog is pushed back on screen when Illustrator sits in the corner' $false `
                'the driver could not read the placement back'
        }
        elseif ($pushed -le 4) {
            # Centering and clamping agreed, which means the window never got
            # near enough to the edge for the clamp to have anything to do.
            # Reporting a pass here would be reporting an arrangement, not a
            # result.
            Note '[----] the dialog is pushed back on screen when Illustrator sits in the corner'
            Note ('       ' + $edge.Line)
            Add-ProbeResult -Group 'dialog' -Case 'the dialog is pushed back on screen when Illustrator sits in the corner' `
                -Expected 'the dialog behaves like an Adobe dialog' `
                -Observed ('Illustrator did not end up close enough to the edge for centering to overshoot it, so the clamp had nothing to do: ' + $edge.Line) `
                -Status 'NOT DISCRIMINATING'
        }
        else {
            Check 'the dialog is pushed back on screen when Illustrator sits in the corner' $edge.Inside `
                ("centering alone would have put it {0} pixels past the edge; it opened at {1},{2}, entirely on the desktop" -f `
                 $pushed, $edge.X, $edge.Y)
        }
    }
    finally {
        if ($havePlacement) { [HostWin]::SetWindowPlacement($hwnd, [ref] $saved) | Out-Null }
        else { [HostWin]::ShowWindow($hwnd, 3) | Out-Null }   # SW_MAXIMIZE
        Start-Sleep -Milliseconds 600
        Note 'Illustrator put back where it was'
    }
}

Invoke-AiScript 'LS.clear(); "cleared";' | Out-Null

if ($TracePath -and (Test-Path $TracePath)) {
    $dpi = Get-Content $TracePath | Where-Object { $_ -match 'dialog: closed' } | Select-Object -Last 1
    if ($dpi) { Note ("last dialog trace line: " + $dpi.Trim()) }
}

Note ''
Note ("{0} passed, {1} failed" -f $script:passed, $script:failed)
Save-ProbeResults -Path ($LogPath -replace '\.txt$', '.tsv')
Save-ProbeTranscript -Path $LogPath -Lines $log
Write-Output "`nWritten to $LogPath"
