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

function Start-Ai {
    [CmdletBinding()]
    param([string] $Exe = 'C:\Program Files\Adobe\Adobe Illustrator 2026\Support Files\Contents\Windows\Illustrator.exe')

    if (-not (Get-Process Illustrator -ErrorAction SilentlyContinue)) { Start-Process $Exe }
    Get-AiApp | Out-Null
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
    [System.IO.File]::WriteAllLines($Path, $script:ProbeRows)
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
