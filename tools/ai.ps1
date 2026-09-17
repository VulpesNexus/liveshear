<#
.SYNOPSIS
    Helpers for driving Illustrator from PowerShell during the investigation.

.DESCRIPTION
    Dot-source this file, then use Invoke-AiScript to run ExtendScript and
    Send-AiMessage to reach the LiveShear plugin's research bridge.

        . .\tools\ai.ps1
        Send-AiMessage registry
#>

function Get-AiApp {
    [CmdletBinding()]
    param([int] $TimeoutSeconds = 180)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        try { return [Runtime.InteropServices.Marshal]::GetActiveObject('Illustrator.Application') }
        catch {
            if ((Get-Date) -ge $deadline) { throw 'Illustrator is not reachable over COM.' }
            Start-Sleep -Seconds 2
        }
    }
}

function Invoke-AiScript {
    [CmdletBinding(DefaultParameterSetName = 'Code')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Code', Position = 0)]
        [string] $Code,
        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string] $Path
    )

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $Code = [System.IO.File]::ReadAllText($Path)
    }
    (Get-AiApp).DoJavaScript($Code)
}

function Send-AiMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $Selector,
        [Parameter(Position = 1)] [string] $Arguments = '',
        [string] $Plugin = 'LiveShear'
    )

    # Both strings travel through ExtendScript source, so quote and backslash
    # have to survive the trip.
    $escape = { param($s) $s -replace '\\', '\\' -replace '"', '\"' }
    $sel = & $escape $Selector
    $arg = & $escape $Arguments
    Invoke-AiScript "app.sendScriptMessage(`"$Plugin`", `"$sel`", `"$arg`");"
}

function Stop-Ai {
    [CmdletBinding()]
    param()

    if (-not (Get-Process Illustrator -ErrorAction SilentlyContinue)) { return 'Illustrator was not running.' }

    # Close every document first so nothing can raise a save prompt, then quit.
    # Application.Quit() is unreliable once a document has been opened and
    # closed in the session; the Quit menu command always works, and takes the
    # COM channel down with it, so the RPC failure it raises is expected.
    try { Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null } catch { }
    try { Invoke-AiScript 'app.executeMenuCommand("quit");' | Out-Null } catch { }

    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Process Illustrator -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    if (Get-Process Illustrator -ErrorAction SilentlyContinue) { throw 'Illustrator did not quit.' }
    'Illustrator stopped.'
}

function Wait-AiReady {
    <#
    .SYNOPSIS
        Waits until Illustrator will actually run a script, not merely until it
        answers COM.
    .DESCRIPTION
        The two are not the same moment. GetActiveObject succeeds while the
        application is still starting, and a DoJavaScript call made in that
        window fails with RPC_E_CALL_REJECTED or "the remote procedure call
        failed" -- which reads exactly like the access violation that ends a
        long run, and was twice mistaken for one.
    #>
    [CmdletBinding()]
    param([int] $TimeoutSeconds = 180)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            (Get-AiApp -TimeoutSeconds 10).DoJavaScript('app.documents.length + "";') | Out-Null
            return $true
        }
        catch {
            # After a crash, Illustrator starts on a prompt offering to launch
            # or to run diagnostics, and no script runs until it is answered.
            # A posted click answers it without taking the mouse or the focus.
            $running = Get-Process Illustrator -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($running) { [AiLaunch]::AnswerCrashPrompt($running.Id) | Out-Null }
            Start-Sleep -Seconds 2
        }
    }
    return $false
}

if (-not ('AiLaunch' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class AiLaunch {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO { public int cb; public string lpReserved, lpDesktop, lpTitle; public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags; public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, int flags, IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr hwnd, out int pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextW(IntPtr hwnd, StringBuilder text, int size);
    [DllImport("user32.dll")] static extern bool PostMessageW(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam);

    // STARTF_USESHOWWINDOW with SW_SHOWMINNOACTIVE. Returns the process id,
    // or the negated Win32 error.
    public static int Start(string exe, string dir) {
        var si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        si.dwFlags = 1;
        si.wShowWindow = 7;
        PROCESS_INFORMATION pi;
        if (!CreateProcessW(exe, "\"" + exe + "\"", IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, dir, ref si, out pi))
            return -Marshal.GetLastWin32Error();
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        return pi.dwProcessId;
    }

    // Posts BM_CLICK to the prompt's "Launch Illustrator" button.
    public static bool AnswerCrashPrompt(int pid) {
        bool clicked = false;
        EnumWindows((top, unused) => {
            int owner;
            GetWindowThreadProcessId(top, out owner);
            if (owner != pid) return true;
            EnumChildWindows(top, (child, unused2) => {
                var text = new StringBuilder(128);
                GetWindowTextW(child, text, text.Capacity);
                if (text.ToString() != "&Launch Illustrator") return true;
                PostMessageW(child, 0x00F5, IntPtr.Zero, IntPtr.Zero);
                clicked = true;
                return false;
            }, IntPtr.Zero);
            return !clicked;
        }, IntPtr.Zero);
        return clicked;
    }
}
"@
}

function Start-Ai {
    [CmdletBinding()]
    param([string] $Exe = 'C:\Program Files\Adobe\Adobe Illustrator 2026\Support Files\Contents\Windows\Illustrator.exe')

    # Minimized and never activated, so the restart before each probe does not
    # take the foreground from whoever is using the machine; Start-Process
    # activates the window even when asked for it minimized. CreateProcess
    # from this process, not WMI, so Illustrator inherits this environment and
    # LIVESHEAR_LOG with it. Started in Illustrator's own folder: its helper
    # processes outlive it holding the folder they were started in.
    if (-not (Get-Process Illustrator -ErrorAction SilentlyContinue)) {
        $id = [AiLaunch]::Start($Exe, (Split-Path -Parent $Exe))
        if ($id -le 0) { throw ('Illustrator could not be started: Win32 error {0}.' -f (-$id)) }
    }
    if (-not (Wait-AiReady)) { throw 'Illustrator started but never became ready to run a script.' }
    'Illustrator running.'
}

function Restart-Ai {
    [CmdletBinding()]
    param()

    Stop-Ai | Out-Null
    Start-Ai
}

function Install-AiHarness {
    <#
    .SYNOPSIS
        Sends tools/harness.jsx into Illustrator's scripting engine.
    .DESCRIPTION
        Illustrator keeps the globals of one DoJavaScript call alive for the
        next, so the measurement library only has to be installed once per
        session. Probes then make short calls into LS.*, one COM round trip
        each, which also gives the application the idle time it needs between
        selecting artwork and acting on it.

        Alerts are turned off at the same time, and that cuts both ways. An
        Illustrator modal blocks the scripting call that raised it, so a probe
        that meets one waits for a person forever -- one did, on "The object
        Shear is not currently available", which is what the shear action says
        when it cannot see the selection.

        But suppressing it is exactly how that failure becomes invisible:
        Illustrator answers the alert with Continue, the action skips the step
        it could not do, and PlayActionEvent returns 0 for success. Measured
        directly -- with nothing selected at all, the action returns 0 and the
        artwork does not move. That is the whole of the "the oracle reported
        success and did nothing" anomaly.

        So the suppression is paired with a rule the probes follow: never trust
        the oracle's return value, check that the artwork moved. That is what
        LS.nativeShearChecked is for.
    #>
    [CmdletBinding()]
    param()
    try { Invoke-AiScript 'app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS; "ok";' | Out-Null } catch { }
    Invoke-AiScript -Path (Join-Path $PSScriptRoot 'harness.jsx')
}

function Invoke-AiHarness {
    <#
    .SYNOPSIS
        Runs one expression against the installed harness, reinstalling it if
        the engine has been restarted since.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)] [string] $Expression)

    $probe = Invoke-AiScript 'typeof LS === "undefined" ? "no" : "yes";'
    if ($probe -ne 'yes') { Install-AiHarness | Out-Null }
    Invoke-AiScript $Expression
}

#  Probe results, recorded as data as well as prose.
#
#  Every probe prints a readable transcript, but the release test matrix has to
#  be generated rather than transcribed, so each check is also appended to a
#  tab-separated file under docs\evidence. "Twenty-four checks passed" is not
#  evidence; a list of what the twenty-four were is.

function Start-ProbeResults {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Probe)
    $script:ProbeName = $Probe
    $script:ProbeRows = New-Object Collections.Generic.List[string]
    $script:ProbeRows.Add("probe`tgroup`tcase`texpected`tobserved`tstatus")
}

function Add-ProbeResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Case,
        [string] $Group = '',
        [string] $Expected = '',
        [string] $Observed = '',
        [Parameter(Mandatory)] [string] $Status
    )
    if (-not $script:ProbeRows) { return }
    $clean = { param($s) ($s -replace "[`t`r`n]+", ' ').Trim() }
    $script:ProbeRows.Add(("{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f $script:ProbeName,
        (& $clean $Group), (& $clean $Case), (& $clean $Expected), (& $clean $Observed), $Status))
}

function Save-ProbeResults {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    if (-not $script:ProbeRows) { return }
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)
    [System.IO.File]::WriteAllLines($Path, (Hide-Personal $script:ProbeRows))
}

function Format-AiNumber {
    <#
    .SYNOPSIS
        Formats a number for ExtendScript, decimal point and all.
    .DESCRIPTION
        PowerShell's -f operator formats in the machine's own culture. On a
        machine whose decimal separator is a comma, "{0}" -f 0.25 is "0,25",
        and a probe that builds script source out of that quietly asks
        Illustrator to do something other than what it meant -- the parameter
        spec "scaleV_Factor=r:0,25" does not mean a quarter.

        That cost a run: Adobe's own Transform effect appeared to disagree with
        Adobe's own command about a plain rectangle, which is not a thing that
        can happen, and the number was the reason.

        The plugin itself parses in the C locale for the same reason; this is
        the same care on this side of the bridge.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)] [double] $Value)
    $Value.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
}

#  Keeping the machine out of the evidence.
#
#  Probes print paths, and the paths on a development machine name the person
#  using it: the profile directory carries the account name, and a working
#  directory carries whatever the folder above it is called. Those files are
#  committed, so anything they record travels with the repository.
#
#  This is not a formatting nicety. A build warning once arrived carrying the
#  full absolute path of the project, and the trace file's own path appears in
#  three probes' transcripts. Redacting at the moment of writing catches all of
#  it, including text that arrived from a compiler or from Windows and that no
#  probe composed itself.

function Hide-Personal {
    <#
    .SYNOPSIS
        Replaces anything that names this machine or its user with a
        placeholder, for text about to be written into the repository.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0, ValueFromPipeline)] [AllowNull()] $Text)

    begin {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        # Longest first, so the repository is replaced before the drive it is on.
        $rules = @(
            @{ From = $repoRoot;                                      To = '<repo>' },
            @{ From = [Environment]::GetFolderPath('LocalApplicationData'); To = '<localappdata>' },
            @{ From = [Environment]::GetFolderPath('ApplicationData');      To = '<appdata>' },
            @{ From = [IO.Path]::GetTempPath().TrimEnd('\');          To = '<temp>' },
            @{ From = $env:USERPROFILE;                               To = '<user>' },
            @{ From = (Split-Path -Parent $repoRoot);                 To = '<workspace>' }
        )
        # A tool that has to turn a path into a single folder name spells it
        # with every character that is not a letter or a digit replaced by a
        # dash, so this repository's parent becomes one long slug. That slug
        # still names the folder, and the drive it sits on, to anybody who
        # reads it -- but it matches none of the rules above, which look for
        # the path as Windows spells it.
        #
        # It is not caught by the net at the end of this function either, and
        # the reason is worth keeping: that net needs a drive letter, and by
        # the time it runs the temporary directory rule has already replaced
        # the drive letter with a placeholder. Sanitizing the front of a
        # string disarmed the check on the rest of it, and the evidence for
        # two probes went into the repository carrying the workspace folder's
        # name for a whole release before anybody noticed.
        $rules += foreach ($rule in @($rules)) {
            $slug = $rule.From -replace '[^A-Za-z0-9]', '-'
            if ($slug -ne $rule.From) { @{ From = $slug; To = $rule.To } }
        }
        $rules = $rules | Where-Object { $_.From } | Sort-Object { -$_.From.Length }
        $name = $env:USERNAME
    }
    process {
        if ($null -eq $Text) { return $Text }
        $out = foreach ($line in @($Text)) {
            $s = [string] $line
            foreach ($rule in $rules) {
                $s = $s.Replace($rule.From, $rule.To)
                # The same path with forward slashes, as ExtendScript and the
                # compiler both like to print it.
                $s = $s.Replace($rule.From.Replace('\', '/'), $rule.To)
            }
            if ($name) { $s = $s -replace ('(?<![A-Za-z0-9])' + [regex]::Escape($name) + '(?![A-Za-z0-9])'), '<user>' }
            # Everything above replaces a path this machine knows the spelling
            # of, which fails the moment the text has been somewhere that
            # changed the spelling. A path came back from Illustrator with the
            # en dash in a folder name re-encoded as mojibake: it matched no
            # rule, was written into the evidence, and was committed. So
            # anything still shaped like an absolute path is redacted whatever
            # it spells. The lookbehind keeps URLs out, where the "s" of
            # "https:" is otherwise a perfectly good drive letter.
            # Spaces are consumed on purpose: the folder being hidden is very
            # likely to contain one, and stopping at the first space would
            # redact as far as the drive and publish the folder name after
            # it -- which is the half that identifies anybody. It
            # runs to a comma, a quote, or the end of the line, which
            # over-redacts a sentence now and then -- the safe direction for a
            # net that only ever sees what the rules above already missed.
            $s = $s -replace '(?<![A-Za-z])[A-Za-z]:[\\/](?![\\/])[^\r\n"'',;]*', '<path>'
            $s
        }
        $out
    }
}

function Save-ProbeTranscript {
    <#
    .SYNOPSIS
        Writes a probe's readable transcript, with this machine redacted out.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowEmptyCollection()] $Lines
    )
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)
    [System.IO.File]::WriteAllLines($Path, @(Hide-Personal $Lines))
}

function Get-AiAdditionalPluginFolder {
    <#
    .SYNOPSIS
        Illustrator's Additional Plug-ins Folder, as its preferences file
        records it, or an empty string when it is not set.
    .DESCRIPTION
        The preference is not reachable from scripting, so it is read out of
        the preferences file, where it is stored as a hex-encoded path:

            /plugins [ 60
                453a5c4c6f6c6920...
            ]

        tools/sideload.ps1 writes the same entry. This reader is here so that
        anything needing to know where the plugin actually is -- the installer,
        the probes that take it out and put it back -- can ask without
        duplicating the parsing.
    #>
    [CmdletBinding()]
    param([int] $Generation = 30)

    $roaming = [Environment]::GetFolderPath('ApplicationData')
    $locale = 'en_US'
    $localeFile = Join-Path $roaming ("Adobe\Adobe Illustrator {0} Settings\.locale" -f $Generation)
    if (Test-Path $localeFile) {
        $read = ([IO.File]::ReadAllText($localeFile)).Trim()
        if ($read) { $locale = $read }
    }
    $prefs = Join-Path $roaming ("Adobe\Adobe Illustrator {0} Settings\{1}\x64\Adobe Illustrator Prefs" -f $Generation, $locale)
    if (-not (Test-Path $prefs)) { return '' }

    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $text = $latin1.GetString([IO.File]::ReadAllBytes($prefs))
    $m = [regex]::Match($text, "/plugins \[ (\d+)\r\n(.*?)\r\n\]\r\n", [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) { return '' }
    $hex = ($m.Groups[2].Value -replace '[^0-9a-fA-F]', '')
    if ($hex.Length -lt 2) { return '' }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
    [Text.Encoding]::UTF8.GetString($bytes)
}

function Invoke-ShearDialog {
    <#
    .SYNOPSIS
        Opens the effect's dialog on the selected object, works it, and closes
        it -- from a second process, because the call that opens it blocks.
    .DESCRIPTION
        The dialog is modal, so the scripting call that opens it does not
        return until it closes. Anything that has to act on the dialog has to
        come from somewhere else; this starts a background job that waits for
        the window, drives it, and dismisses it.

        This exists because the difference between the dialog and the script
        bridge turned out to matter. An object and its duplicate share an art
        style until something forks it: editing one through the bridge, which
        writes the parameter dictionary in place, changes both. Editing through
        the dialog, which goes through EditEffectParameters and
        UpdateParameters, changes only the one edited. So a test that used the
        bridge to check they were independent reported a defect that does not
        exist for anyone using Illustrator.
    .PARAMETER Tenths
        Slider position in tenths of a degree: 50 is five degrees.
    #>
    [CmdletBinding()]
    param(
        [int] $Tenths = 0,
        [ValidateSet('ok', 'cancel')] [string] $Button = 'ok',
        [int] $EffectIndex = 0,
        [int] $TimeoutSeconds = 30
    )

    $driver = Start-Job -ScriptBlock {
        param($tenths, $button, $timeout)
        Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ShearDlg {
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
        $deadline = (Get-Date).AddSeconds($timeout)
        while ((Get-Date) -lt $deadline) {
            $h = [ShearDlg]::Find()
            if ($h -ne [IntPtr]::Zero) {
                Start-Sleep -Milliseconds 500
                if ($tenths -ne 0) {
                    $slider = [ShearDlg]::GetDlgItem($h, 1001)
                    [ShearDlg]::SendMessage($slider, 1029, [IntPtr] 1, [IntPtr] $tenths) | Out-Null
                    [ShearDlg]::SendMessage($h, 0x0114, [IntPtr] 8, $slider) | Out-Null
                    Start-Sleep -Milliseconds 500
                }
                $key = if ($button -eq 'cancel') { 0x1B } else { 0x0D }
                [ShearDlg]::PostMessage($h, 0x0100, [IntPtr] $key, [IntPtr] 0) | Out-Null
                [ShearDlg]::PostMessage($h, 0x0101, [IntPtr] $key, [IntPtr] 0) | Out-Null
                return 'driven'
            }
            Start-Sleep -Milliseconds 200
        }
        return 'the dialog never appeared'
    } -ArgumentList $Tenths, $Button, $TimeoutSeconds

    $result = Invoke-AiScript ("app.sendScriptMessage('LiveShear', 'edit effect', '{0}');" -f $EffectIndex)
    $said = (Receive-Job -Job $driver -Wait) -join ''
    Remove-Job $driver -Force
    [pscustomobject]@{ Driver = $said; Host = ($result -replace "`r?`n", ' ').Trim() }
}

function Get-ShearDialogMemory {
    <#
    .SYNOPSIS
        What a newly applied Shear opens its dialog with, and whether Preview
        opens ticked.
    .DESCRIPTION
        Using the dialog changes both: OK remembers the angles for the rest of
        the Illustrator session, and the Preview box is kept in Illustrator's
        preferences file. A probe that uses the dialog on the Illustrator a
        person works in would leave its own test angles and its own Preview
        setting behind, so it reads this first and hands it to
        Restore-ShearDialogMemory in a finally block.
    #>
    [CmdletBinding()]
    param([string] $Command = '')

    $text = Send-AiMessage 'dialog memory' $Command
    $fields = @{}
    foreach ($line in ($text -split "`r?`n")) {
        $f = $line -split "`t", 2
        if ($f.Count -eq 2) { $fields[$f[0].Trim()] = $f[1].Trim() }
    }
    if (-not $fields.ContainsKey('remembered')) {
        throw "The plugin did not answer 'dialog memory' (is this an older build?): $text"
    }
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    [pscustomobject]@{
        Remembered = $fields['remembered'] -eq '1'
        Shear      = [double]::Parse($fields['shear'], $invariant)
        Axis       = [double]::Parse($fields['axis'], $invariant)
        Preview    = $fields['preview'] -ne '0'
    }
}

function Restore-ShearDialogMemory {
    <#
    .SYNOPSIS
        Puts back what Get-ShearDialogMemory read, and returns the state that
        results, so the caller can check it took.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)] $Saved)

    if ($Saved.Remembered) {
        Get-ShearDialogMemory ('angles {0}|{1}' -f (Format-AiNumber $Saved.Shear), (Format-AiNumber $Saved.Axis)) | Out-Null
    }
    else {
        Get-ShearDialogMemory 'forget' | Out-Null
    }
    Get-ShearDialogMemory ('preview {0}' -f $(if ($Saved.Preview) { 1 } else { 0 }))
}
