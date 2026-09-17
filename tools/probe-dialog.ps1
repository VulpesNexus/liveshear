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
    The axis buttons: the one naming the stored axis is selected on opening,
    Horizontal and Vertical put their angle on the artwork, Angle keeps the
    angle it held, the arrow keys move between them, and Reset goes back to
    Horizontal. An effect being edited opens on its own values whatever the
    dialog last committed, and the Preview box opens the way it was left.

    Using the dialog changes what it remembers, in the Illustrator session and
    in its preferences file, so the probe reads that state first and puts it
    back in a finally block.
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
          [int] $PreviewClicks, [int] $ArrowUps, [string] $TracePath, [string] $ShotPath,
          [int[]] $Clicks, [string[]] $AxisKeys)

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
    public static extern bool IsWindowEnabled(IntPtr h);
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr h, int index);
    [DllImport("user32.dll")]
    public static extern int GetDlgCtrlID(IntPtr h);
    [StructLayout(LayoutKind.Sequential)]
    public struct GUITHREADINFO {
        public int cbSize, flags;
        public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }
    [DllImport("user32.dll")]
    public static extern bool GetGUIThreadInfo(uint thread, ref GUITHREADINFO info);

    // The control that has the keyboard focus in the dialog's own thread. A
    // window in another process cannot be asked directly; its thread can.
    public static int FocusedId(IntPtr dialog) {
        uint thread = GetWindowThreadProcessId(dialog, IntPtr.Zero);
        GUITHREADINFO info = new GUITHREADINFO();
        info.cbSize = Marshal.SizeOf(typeof(GUITHREADINFO));
        if (thread == 0 || !GetGUIThreadInfo(thread, ref info) || info.hwndFocus == IntPtr.Zero) return 0;
        return GetDlgCtrlID(info.hwndFocus);
    }
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
    $BM_GETCHECK = 0x00F0
    $SHEAR_SLIDER = 1001
    $SHEAR_EDIT = 1002
    $AXIS_EDIT = 1004
    $PREVIEW = 1005
    $AXIS_NAMES = @('Horizontal', 'Vertical', 'Angle')
    $AXIS_BUTTON = @{ 'Horizontal' = 1007; 'Vertical' = 1008; 'Angle' = 1009 }
    $CONTROL_NAMES = @{ 1 = 'OK'; 2 = 'Cancel'; 1005 = 'Preview'; 1006 = 'Reset'; 1007 = 'Horizontal'; 1008 = 'Vertical'; 1009 = 'Angle' }

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
    $axisEdit = [Dlg]::GetDlgItem($dialog, $AXIS_EDIT)

    # The axis row as a person would see it: what the angle field reads,
    # whether it takes input, which button is selected, and which button Tab
    # would land on. BM_GETCHECK is answered by the dialog for its owner-drawn
    # buttons; WS_TABSTOP is the style bit Tab follows.
    $readAxis = {
        $sb = New-Object Text.StringBuilder 64
        [Dlg]::SendMessageBuf($axisEdit, 0x000D, [IntPtr] 64, $sb) | Out-Null
        $selected = @()
        $stops = @()
        foreach ($name in $AXIS_NAMES) {
            $b = [Dlg]::GetDlgItem($dialog, $AXIS_BUTTON[$name])
            if ([int64] [Dlg]::SendMessage($b, $BM_GETCHECK, [IntPtr]::Zero, [IntPtr]::Zero) -eq 1) { $selected += $name }
            if (([Dlg]::GetWindowLong($b, -16) -band 0x00010000) -ne 0) { $stops += $name }
        }
        "axis field '{0}', enabled {1}, selected {2}, tab stop {3}, focus {4}" -f `
            $sb.ToString(), [Dlg]::IsWindowEnabled($axisEdit), ($selected -join '+'), ($stops -join '+'), [Dlg]::FocusedId($dialog)
    }

    $sb = New-Object Text.StringBuilder 64
    [Dlg]::SendMessageBuf($edit, 0x000D, [IntPtr] 64, $sb) | Out-Null
    $lines.Add(("opened with: shear field '{0}'; {1}" -f $sb.ToString(), (& $readAxis)))

    for ($i = 0; $i -lt $PreviewClicks; $i++) {
        [Dlg]::SendMessage($preview, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 150
        $lines.Add('clicked the Preview box')
    }

    foreach ($id in $Clicks) {
        $b = [Dlg]::GetDlgItem($dialog, $id)
        [Dlg]::SendMessage($b, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 300
        $lines.Add(("clicked {0}; {1}" -f $CONTROL_NAMES[$id], (& $readAxis)))
    }

    # Each key is posted to whichever axis button is selected at that moment,
    # which is where a person's focus would be after using the buttons, or,
    # written key@id, to that control. A posted arrow does not read the
    # keyboard state, so nothing is brought to the front and no real key is
    # pressed.
    foreach ($spec in $AxisKeys) {
        $parts = $spec -split '@', 2
        $vk = switch ($parts[0]) { 'left' { 0x25 } 'up' { 0x26 } 'right' { 0x27 } default { 0x28 } }
        $target = [IntPtr]::Zero
        if ($parts.Count -eq 2) {
            $target = [Dlg]::GetDlgItem($dialog, [int] $parts[1])
            $where = $CONTROL_NAMES[[int] $parts[1]]
        }
        else {
            foreach ($name in $AXIS_NAMES) {
                $b = [Dlg]::GetDlgItem($dialog, $AXIS_BUTTON[$name])
                if ([int64] [Dlg]::SendMessage($b, $BM_GETCHECK, [IntPtr]::Zero, [IntPtr]::Zero) -eq 1) { $target = $b }
            }
            $where = 'the selected axis button'
        }
        [Dlg]::PostMessage($target, $WM_KEYDOWN, [IntPtr] $vk, [IntPtr] 0) | Out-Null
        Start-Sleep -Milliseconds 300
        $lines.Add(("pressed {0} on {1}; {2}" -f $parts[0], $where, (& $readAxis)))
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
        [string] $ShotPath = '',
        [int[]] $Clicks = @(),
        [string[]] $AxisKeys = @()
    )
    $resultFile = Join-Path $env:TEMP ("liveshear-dialog-{0}.txt" -f [Guid]::NewGuid().ToString('N'))
    $job = Start-Job -ScriptBlock $driver -ArgumentList $Angles, $Button, $resultFile, $TypeInto, $PreviewClicks, $ArrowUps, $TracePath, $ShotPath, $Clicks, $AxisKeys
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

function New-Case([double] $startAngle = 5, [double] $startAxis = 0) {
    Invoke-AiScript "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.selectOnly(LS.target); 'built';" | Out-Null
    Invoke-AiScript 'app.redraw();' | Out-Null
    Invoke-AiScript ("LS.shear({0}, {1});" -f (Format-AiNumber $startAngle), (Format-AiNumber $startAxis)) | Out-Null
    Invoke-AiScript 'app.redraw();' | Out-Null
}
function CaseBounds {
    ((Invoke-AiScript 'LS.vb(LS.target);').Trim() -split ',' | ForEach-Object { [double] $_ })
}
function StoredParameter([string] $key) {
    $a = Send-AiMessage appearance
    $m = [regex]::Match($a, ([regex]::Escape($key) + ' \(Real\) = ([-0-9.]+)'))
    if ($m.Success) { [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) } else { [double]::NaN }
}
function StoredAngle { StoredParameter 'shearAngle' }
function StoredAxis { StoredParameter 'axisAngle' }

# What the driver saw of the axis row: when the dialog opened, and after each
# button it clicked or key it pressed, in order.
function Get-AxisRows([string[]] $transcript) {
    foreach ($t in $transcript) {
        $m = [regex]::Match($t, "^(.*?)(?:; )?axis field '([^']*)', enabled (\w+), selected (\S*), tab stop (\S*), focus (\d+)")
        if ($m.Success) {
            [pscustomobject]@{
                Step     = $m.Groups[1].Value
                Field    = $m.Groups[2].Value
                Enabled  = $m.Groups[3].Value -eq 'True'
                Selected = $m.Groups[4].Value
                TabStop  = $m.Groups[5].Value
                Focus    = [int] $m.Groups[6].Value
                Line     = $t.Trim()
            }
        }
    }
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

# The dialog remembers what it was last used with, and the Preview box is kept
# in Illustrator's preferences file, so this run would otherwise leave its own
# test values in the Illustrator a person works in. Read first, put back in the
# finally block at the end. Preview starts ticked, which the case that turns it
# off depends on.
$savedMemory = Get-ShearDialogMemory
Note ("Dialog memory on arrival: angles {0}, Preview {1}; restored at the end" -f `
      $(if ($savedMemory.Remembered) { "{0} along {1}" -f (Num $savedMemory.Shear), (Num $savedMemory.Axis) } else { 'none' }),
      $(if ($savedMemory.Preview) { 'ticked' } else { 'unticked' }))
Get-ShearDialogMemory 'forget' | Out-Null
Get-ShearDialogMemory 'preview 1' | Out-Null
Note ''
try {

    # --------------------------------------------------------- OK commits the value
    New-Case 5
    # Beside the transcript, so a run written somewhere other than the evidence
    # folder does not replace the evidence picture.
    $shot = $LogPath -replace '\.txt$', '.png'
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

    # ------------------------------------------------------------ the axis buttons
    #
    # Horizontal and Vertical are Illustrator's names for an axis of 0 and of 90
    # degrees, and Angle hands the axis to the slider. Nothing about them is stored,
    # so every check below reads the axis angle the effect ends up holding, and the
    # shape the artwork ends up with, rather than trusting the buttons' look.

    $HORIZONTAL = 1007
    $VERTICAL = 1008
    $ANGLE = 1009
    $RESET = 1006
    $AXIS_IDS = @{ 'Horizontal' = $HORIZONTAL; 'Vertical' = $VERTICAL; 'Angle' = $ANGLE }

    # A 200 x 120 pt box, sheared 5 degrees. Horizontally its top slides past its
    # bottom and it widens by 120 tan 5; vertically its right side climbs past its
    # left and it grows taller by 200 tan 5.
    $tan5 = [Math]::Tan(5 * [Math]::PI / 180)
    function Size([double[]] $b) { [pscustomobject]@{ W = [Math]::Abs($b[2] - $b[0]); H = [Math]::Abs($b[1] - $b[3]) } }

    $remembered = Get-ShearDialogMemory
    foreach ($case in @(
            @{ Axis = 0;   Selected = 'Horizontal'; Enabled = $false },
            @{ Axis = 90;  Selected = 'Vertical';   Enabled = $false },
            @{ Axis = 37;  Selected = 'Angle';      Enabled = $true  },
            @{ Axis = -90; Selected = 'Angle';      Enabled = $true  })) {
        New-Case 5 $case.Axis
        $transcript = Invoke-Dialog -Button 'cancel'
        Note ("driver transcript (opening on an axis of {0}):" -f $case.Axis)
        foreach ($t in $transcript) { Note ("       " + $t) }
        $open = @(Get-AxisRows $transcript) | Select-Object -First 1
        $shearField = if (($transcript -join "`n") -match "opened with: shear field '([^']*)'") { $Matches[1] } else { '' }
        $ok = $null -ne $open -and $open.Selected -eq $case.Selected -and $open.TabStop -eq $case.Selected -and
              $open.Enabled -eq $case.Enabled -and (Near ([double]::Parse($open.Field, [Globalization.CultureInfo]::InvariantCulture)) $case.Axis 0.05)
        Check ("an axis of {0} opens with {1} selected" -f $case.Axis, $case.Selected) $ok `
            $(if ($null -eq $open) { 'the driver did not record the axis row' }
              elseif ($case.Axis -eq -90) { "{0}; -90 shears like 90 but is stored as -90, so it opens as the angle it is" -f $open.Line }
              else { $open.Line })
        if ($case.Axis -eq 37) {
            # Discriminating only if the dialog has something else to remember,
            # which the cases above made sure of by pressing OK.
            Check 'an effect being edited opens on its own values, not the ones committed last' `
                ($remembered.Remembered -and -not (Near $remembered.Shear 5 0.05) -and $shearField -eq '5.0' -and (Near $open.Field 37 0.05)) `
                ("the dialog last committed {0} degrees along {1}; the effect holds 5 along 37; the fields opened reading '{2}' and '{3}'" -f `
                 (Num $remembered.Shear), (Num $remembered.Axis), $shearField, $open.Field)
        }
    }

    New-Case 5 0
    $before = Size (CaseBounds)
    $transcript = Invoke-Dialog -Button 'ok' -Clicks @($VERTICAL)
    Note 'driver transcript (Vertical):'
    foreach ($t in $transcript) { Note ("       " + $t) }
    Invoke-AiScript 'app.redraw();' | Out-Null
    $after = Size (CaseBounds)
    $row = @(Get-AxisRows $transcript) | Where-Object { $_.Step -like 'clicked Vertical*' } | Select-Object -First 1
    Check 'Vertical sets the axis to 90 degrees and leaves the angle row locked' `
        ($null -ne $row -and $row.Field -eq '90.0' -and -not $row.Enabled -and $row.Selected -eq 'Vertical' -and $row.TabStop -eq 'Vertical') `
        $(if ($null -eq $row) { 'the driver did not record the click' } else { $row.Line })
    Check 'and OK shears the artwork vertically' `
        ((Near (StoredAxis) 90 0.001) -and (Near (StoredAngle) 5 0.05) -and (Near $after.W 200 0.02) -and (Near $after.H (120 + 200 * $tan5) 0.02)) `
        ("axisAngle {0}, shearAngle {1}; {2} x {3} pt, was {4} x {5}; a vertical 5 degree shear of this box is 200 x {6}" -f `
         (StoredAxis), (StoredAngle), (Num $after.W), (Num $after.H), (Num $before.W), (Num $before.H), (Num (120 + 200 * $tan5)))

    New-Case 5 90
    $transcript = Invoke-Dialog -Button 'ok' -Clicks @($HORIZONTAL)
    Note 'driver transcript (Horizontal):'
    foreach ($t in $transcript) { Note ("       " + $t) }
    Invoke-AiScript 'app.redraw();' | Out-Null
    $after = Size (CaseBounds)
    Check 'Horizontal sets the axis back to 0 degrees and shears the artwork horizontally' `
        ((Near (StoredAxis) 0 0.001) -and (Near $after.W (200 + 120 * $tan5) 0.02) -and (Near $after.H 120 0.02)) `
        ("axisAngle {0}; {1} x {2} pt; a horizontal 5 degree shear of this box is {3} x 120" -f `
         (StoredAxis), (Num $after.W), (Num $after.H), (Num (200 + 120 * $tan5)))

    New-Case 5 37
    $transcript = Invoke-Dialog -Button 'cancel' -Clicks @($HORIZONTAL, $ANGLE, $VERTICAL)
    Note 'driver transcript (Angle keeps its angle):'
    foreach ($t in $transcript) { Note ("       " + $t) }
    Invoke-AiScript 'app.redraw();' | Out-Null
    $rows = @(Get-AxisRows $transcript)
    $seen = ($rows | ForEach-Object { "{0} '{1}' {2}" -f $_.Selected, $_.Field, $(if ($_.Enabled) { 'editable' } else { 'locked' }) }) -join ' -> '
    $expected = "Angle '37.0' editable -> Horizontal '0.0' locked -> Angle '37.0' editable -> Vertical '90.0' locked"
    Check 'Angle gives back the angle it held after a look at Horizontal' ($seen -eq $expected) `
        ("the axis row read {0}" -f $seen)
    Check 'and Cancel leaves the stored axis as it was, whatever buttons were used' (Near (StoredAxis) 37 0.001) `
        ("axisAngle after Cancel: {0} (it was 37)" -f (StoredAxis))

    New-Case 5 0
    $transcript = Invoke-Dialog -Button 'ok' -AxisKeys @('down', 'down', 'down', 'up', 'up')
    Note 'driver transcript (arrow keys between the axis buttons):'
    foreach ($t in $transcript) { Note ("       " + $t) }
    Invoke-AiScript 'app.redraw();' | Out-Null
    $rows = @(Get-AxisRows $transcript | Where-Object { $_.Step -like 'pressed*' })
    $walk = ($rows | ForEach-Object { $_.Selected }) -join ' -> '
    $focusFollows = @($rows | Where-Object { $_.Focus -ne $AXIS_IDS[$_.Selected] }).Count -eq 0
    Check 'the arrow keys move between the axis buttons, wrapping at both ends' `
        ($walk -eq 'Vertical -> Angle -> Horizontal -> Angle -> Vertical' -and $focusFollows) `
        ("from Horizontal, down down down up up selected {0}; the focus moved with the selection: {1}" -f $walk, $focusFollows)
    Check 'and OK commits the axis they left selected' (Near (StoredAxis) 90 0.001) ("axisAngle after OK: {0}" -f (StoredAxis))

    # The arrow keys on the controls below the buttons. With the angle row
    # locked, the nearest enabled control above Preview is the Angle button,
    # so if those keys ever moved the focus there, a dialog that selected on
    # focus would switch the axis back to the angle Angle held. Opening on 37
    # and clicking Horizontal gives Angle something to switch back to. It is a
    # guard, not a reproduction: it also passed against the build that
    # selected on focus, because in this window the keys did not move the
    # focus at all.
    New-Case 5 37
    $transcript = Invoke-Dialog -Button 'ok' -Clicks @($HORIZONTAL) -AxisKeys @('up@1005', 'left@1005', 'left@1', 'left@2', 'up@1006')
    Note 'driver transcript (arrow keys on the controls below the buttons):'
    foreach ($t in $transcript) { Note ("       " + $t) }
    Invoke-AiScript 'app.redraw();' | Out-Null
    $rows = @(Get-AxisRows $transcript | Where-Object { $_.Step -like 'pressed*' })
    $stayed = $rows.Count -eq 5 -and @($rows | Where-Object { $_.Selected -ne 'Horizontal' -or $_.Field -ne '0.0' }).Count -eq 0
    Check 'the arrow keys on Preview, Reset, Cancel, and OK leave the axis alone' ($stayed -and (Near (StoredAxis) 0 0.001)) `
        ("after clicking Horizontal on an axis of 37: {0}; axisAngle after OK: {1}" -f `
         (($rows | ForEach-Object { "{0} -> {1} '{2}'" -f $_.Step, $_.Selected, $_.Field }) -join '; '), (StoredAxis))

    New-Case 5 37
    $transcript = Invoke-Dialog -Button 'ok' -Clicks @($RESET)
    Note 'driver transcript (Reset):'
    foreach ($t in $transcript) { Note ("       " + $t) }
    Invoke-AiScript 'app.redraw();' | Out-Null
    $row = @(Get-AxisRows $transcript) | Where-Object { $_.Step -like 'clicked Reset*' } | Select-Object -First 1
    Check 'Reset goes back to Horizontal and no shear' `
        ($null -ne $row -and $row.Selected -eq 'Horizontal' -and $row.Field -eq '0.0' -and -not $row.Enabled -and
         (Near (StoredAngle) 0 0.001) -and (Near (StoredAxis) 0 0.001)) `
        ("{0}; after OK shearAngle {1}, axisAngle {2}" -f $(if ($row) { $row.Line } else { 'the driver did not record the click' }), (StoredAngle), (StoredAxis))

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

        # The box is kept the way it was left, as Illustrator keeps its own
        # dialogs' Preview boxes. The plugin reports the preference it saved, and
        # the trace says what the next dialog actually opened with.
        $kept = Get-ShearDialogMemory
        New-Case 5
        $transcript = Invoke-Dialog -Button 'cancel'
        Note 'driver transcript (the dialog after Preview was turned off):'
        foreach ($t in $transcript) { Note ("       " + $t) }
        if ($traceIsLive) {
            $opened = Get-Content $TracePath | Where-Object { $_ -match 'EditParameters:' } | Select-Object -Last 1
            Check 'Preview opens the way it was left' (-not $kept.Preview -and $opened -match 'preview=0') `
                ("the saved preference reads {0}; the next dialog opened with: {1}" -f `
                 $(if ($kept.Preview) { 'ticked' } else { 'unticked' }), $(if ($opened) { $opened.Trim() } else { 'no EditParameters line in the trace' }))
        }
        else {
            Check 'Preview opens the way it was left' (-not $kept.Preview) `
                ("the saved preference reads {0}; without a trace, what the next dialog opened with could not be read" -f $(if ($kept.Preview) { 'ticked' } else { 'unticked' }))
        }
        Get-ShearDialogMemory 'preview 1' | Out-Null
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
}
finally {
    # Caught, because a host that died mid-run cannot be asked anything, and
    # the error from asking would replace the one that explains the run.
    try {
        $restored = Restore-ShearDialogMemory $savedMemory
        Note ("Dialog memory restored: angles {0}, Preview {1}" -f `
              $(if ($restored.Remembered) { "{0} along {1}" -f (Num $restored.Shear), (Num $restored.Axis) } else { 'none' }),
              $(if ($restored.Preview) { 'ticked' } else { 'unticked' }))
    }
    catch {
        Note ("Dialog memory could NOT be restored, and Illustrator may keep this run's values: " + $_.Exception.Message)
    }
}

Note ''
Note ("{0} passed, {1} failed" -f $script:passed, $script:failed)
Save-ProbeResults -Path ($LogPath -replace '\.txt$', '.tsv')
Save-ProbeTranscript -Path $LogPath -Lines $log
Write-Output "`nWritten to $LogPath"
