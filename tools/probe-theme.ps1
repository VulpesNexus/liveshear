<#
.SYNOPSIS
    Does the dialog actually follow Illustrator's interface brightness, or does
    it just happen to look dark on this machine?

.DESCRIPTION
    The dialog asks the host for its own dialog colors through AIUIThemeSuite
    and paints itself with them. A screen capture at one brightness cannot tell
    that apart from a fixed dark palette that happens to match, so this walks
    Illustrator through its brightness settings and captures the dialog at each
    one.

    What is checked is not a color anybody chose. It is that the pixels of the
    dialog move when the host's setting moves, in the same direction, and that
    at the lightest setting the dialog is light rather than dark. A palette
    baked into the plugin would give the same picture every time.

    Illustrator has to be restarted between settings. Writing uiBrightness
    through scripting stores the number -- reading it back returns the new one
    -- but the running application goes on drawing itself at the old
    brightness, and goes on reporting the old colors through the theme suite
    with it. Only a restart applies it. A first attempt at this probe set the
    preference four times without restarting, got an identical picture every
    time, and would have read as "the dialog ignores the host" when what it
    had actually measured was that nothing in the host had changed yet.

    The brightness the machine was set to is read first and put back at the
    end, whatever happens in between.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    # The darkest and the lightest the Preferences dialog offers. Each one
    # costs a restart of Illustrator, so this walks the ends rather than all
    # four presets; the claim is that the dialog follows the host, and the
    # ends are what shows it.
    [double[]] $Brightness = @(0.0, 1.0)
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\theme.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)
$shotDir = Join-Path $repo 'docs\evidence'

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }

# The driver runs in its own process: the call that opens the dialog does not
# return until the dialog closes, so nothing in this one could photograph it.
$driver = {
    param([string] $ResultFile, [string] $ShotPath)

    Add-Type -AssemblyName System.Drawing
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class ThemeDlg {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
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

    $lines = New-Object Collections.Generic.List[string]
    $deadline = (Get-Date).AddSeconds(40)
    $dialog = [IntPtr]::Zero
    while ((Get-Date) -lt $deadline) {
        $dialog = [ThemeDlg]::Find('VulpesNexusShearDialog')
        if ($dialog -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 200
    }
    if ($dialog -eq [IntPtr]::Zero) {
        $lines.Add('dialog never appeared')
        [IO.File]::WriteAllLines($ResultFile, $lines)
        return
    }

    # Let the first paint finish before photographing it.
    Start-Sleep -Milliseconds 600

    $rect = New-Object ThemeDlg+RECT
    [ThemeDlg]::GetClientRect($dialog, [ref] $rect) | Out-Null
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    if ($w -gt 0 -and $h -gt 0) {
        $bmp = New-Object System.Drawing.Bitmap $w, $h
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $dc = $g.GetHdc()
        [ThemeDlg]::PrintWindow($dialog, $dc, 2) | Out-Null
        $g.ReleaseHdc($dc)
        $g.Dispose()
        $bmp.Save($ShotPath)

        # A point on the dialog's own face and the average over the whole
        # window. The face says what the background is; the average says the
        # controls moved with it rather than staying light on a dark face.
        #
        # Not the top-left corner: PrintWindow with PW_RENDERFULLCONTENT draws
        # the caption too, so the first rows of the bitmap are title bar and
        # read as the caption's color rather than the dialog's. The bottom
        # margin, below the row of buttons, is bare background.
        $corner = $bmp.GetPixel([int] ($w / 2), $h - 3)
        $total = 0.0
        $count = 0
        for ($y = 0; $y -lt $h; $y += 4) {
            for ($x = 0; $x -lt $w; $x += 4) {
                $p = $bmp.GetPixel($x, $y)
                $total += ($p.R + $p.G + $p.B) / 3.0
                $count++
            }
        }
        $lines.Add(("corner {0},{1},{2}" -f $corner.R, $corner.G, $corner.B))
        # Invariant, because this machine formats a decimal with a comma and
        # the caller parses this back as a number.
        $lines.Add("average " + ($total / $count).ToString('F1', [Globalization.CultureInfo]::InvariantCulture))
        $bmp.Dispose()
    }

    # Escape is a cancel, so nothing is committed by looking at it.
    [ThemeDlg]::PostMessageW($dialog, 0x0100, [IntPtr] 0x1B, [IntPtr] 0) | Out-Null
    [IO.File]::WriteAllLines($ResultFile, $lines)
}

# Tracing has to be on before Illustrator is launched, because the plugin
# reads the variable at startup and the launches happen below. It is set on
# this process so every Illustrator started from here inherits it, and that is
# what lets the probe check where the colors came from rather than only what
# they looked like.
$trace = Join-Path ([IO.Path]::GetTempPath()) 'liveshear-theme-probe.log'
if (Test-Path $trace) { [IO.File]::Delete($trace) }
$env:LIVESHEAR_LOG = $trace

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'theme'

Note 'Live Shear -- does the dialog follow Illustrator''s interface brightness?'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ''

$entry = [double] (Invoke-AiScript 'app.preferences.getRealPreference("uiBrightness");').Trim()
Note ("The machine was set to uiBrightness {0}; it is put back at the end." -f (Format-AiNumber $entry))
Note ''

# One object with the effect on it, so there is something to open the dialog on.
Invoke-AiScript 'LS.clear(); LS.target = LS.fixtures["plainRect"](); LS.selectOnly(LS.target); app.redraw();' | Out-Null
Send-AiMessage 'apply effect' 'VulpesNexus Shear' | Out-Null

function Set-Brightness([double] $value) {
    # Stored now, applied by the next launch. Illustrator writes its
    # preferences when it exits, so the restart has to be a real quit rather
    # than killing the process, or the new value is thrown away.
    Invoke-AiScript ("app.preferences.setRealPreference(""uiBrightness"", {0});" -f (Format-AiNumber $value)) | Out-Null
    Stop-Ai
    Start-Ai | Out-Null
    Wait-AiReady | Out-Null
    Install-AiHarness | Out-Null
    Invoke-AiScript 'LS.clear(); LS.target = LS.fixtures["plainRect"](); LS.selectOnly(LS.target); app.redraw();' | Out-Null
    Send-AiMessage 'apply effect' 'VulpesNexus Shear' | Out-Null
}

$rows = @()
try {
    foreach ($value in $Brightness) {
        $text = Format-AiNumber $value
        Set-Brightness $value

        $shot = Join-Path $shotDir ("dialog-brightness-{0}.png" -f ($text -replace '[^0-9]', ''))
        $resultFile = [IO.Path]::GetTempFileName()
        $job = Start-Job -ScriptBlock $driver -ArgumentList $resultFile, $shot
        Start-Sleep -Milliseconds 400
        try { Send-AiMessage 'edit effect' '0' | Out-Null } catch { }
        Wait-Job $job -Timeout 90 | Out-Null
        Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job $job -Force

        $out = if (Test-Path $resultFile) { Get-Content $resultFile } else { @() }
        [IO.File]::Delete($resultFile)

        $corner = ($out | Where-Object { $_ -like 'corner *' }) -replace 'corner ', ''
        $average = ($out | Where-Object { $_ -like 'average *' }) -replace 'average ', ''
        # Joined before it is split: the bridge hands back an array of lines
        # here and a single multi-line string elsewhere, and splitting an
        # array gives an array of arrays that prints as its type name.
        $reported = [string] (((@(Send-AiMessage 'log' '') -join "`n") -split "`r?`n" |
                     Where-Object { $_ -match 'theme: ' } | Select-Object -Last 1))

        $rows += [PSCustomObject]@{
            Brightness = $value
            Corner     = $corner
            Average    = if ($average) { [double] $average } else { [double]::NaN }
            Reported   = $reported
        }
        Note ("uiBrightness {0,-5}  dialog corner {1,-14} average {2,-6}  {3}" -f
              $text, $corner, $average, ($reported -replace '^\s*\S+\s+', ''))
    }
}
finally {
    # Put the machine back, and restart once more so the application the user
    # comes back to is drawing itself the way they left it.
    Set-Brightness $entry
    Note ''
    Note ("uiBrightness put back to {0}, and Illustrator restarted so it is applied." -f (Format-AiNumber $entry))
}

Note ''
$usable = @($rows | Where-Object { -not [double]::IsNaN($_.Average) })
$darkest = $usable | Sort-Object Brightness | Select-Object -First 1
$lightest = $usable | Sort-Object Brightness | Select-Object -Last 1

Add-ProbeResult -Group 'theme' -Case 'the dialog was captured at every brightness setting' `
    -Expected ("{0} captures" -f @($Brightness).Count) `
    -Observed ("{0} of {1} produced a picture" -f $usable.Count, @($Brightness).Count) `
    -Status $(if ($usable.Count -eq @($Brightness).Count) { 'PASS' } else { 'FAIL' })

if ($usable.Count -ge 2) {
    $spread = $lightest.Average - $darkest.Average
    Add-ProbeResult -Group 'theme' -Case 'the dialog gets lighter when Illustrator does' `
        -Expected 'a palette baked into the plugin would give the same picture at every setting' `
        -Observed ("the average pixel goes from {0} at uiBrightness {1} to {2} at {3}, a spread of {4}" -f
                   (Format-AiNumber $darkest.Average), (Format-AiNumber $darkest.Brightness),
                   (Format-AiNumber $lightest.Average), (Format-AiNumber $lightest.Brightness),
                   (Format-AiNumber $spread)) `
        -Status $(if ($spread -gt 40) { 'PASS' } else { 'FAIL' })

    Add-ProbeResult -Group 'theme' -Case 'the darkest setting is dark and the lightest is light' `
        -Expected 'the dialog is not merely different, but dark and light the right way round' `
        -Observed ("darkest average {0}, lightest average {1}" -f
                   (Format-AiNumber $darkest.Average), (Format-AiNumber $lightest.Average)) `
        -Status $(if ($darkest.Average -lt 128 -and $lightest.Average -gt 128) { 'PASS' } else { 'FAIL' })

    $ordered = $true
    $sorted = @($usable | Sort-Object Brightness)
    for ($i = 1; $i -lt $sorted.Count; $i++) {
        if ($sorted[$i].Average -lt $sorted[$i - 1].Average - 2) { $ordered = $false }
    }
    Add-ProbeResult -Group 'theme' -Case 'it tracks the setting rather than only the extremes' `
        -Expected 'each step is at least as light as the one below it' `
        -Observed (($sorted | ForEach-Object {
                        "{0}:{1}" -f (Format-AiNumber $_.Brightness), (Format-AiNumber $_.Average) }) -join ' ') `
        -Status $(if ($ordered) { 'PASS' } else { 'FAIL' })
}

$fromHost = @($rows | Where-Object { $_.Reported -match 'from host' }).Count
Add-ProbeResult -Group 'theme' -Case 'the colors came from the host, not from the system' `
    -Expected 'the plugin logs which source it used' `
    -Observed ("{0} of {1} openings read the colors from Illustrator" -f $fromHost, $rows.Count) `
    -Status $(if ($fromHost -eq $rows.Count) { 'PASS' } else { 'FAIL' })

Invoke-AiScript 'LS.clear();' | Out-Null
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
Save-ProbeTranscript -Path $OutPath -Lines $log
Write-Output "Written to $OutPath"
