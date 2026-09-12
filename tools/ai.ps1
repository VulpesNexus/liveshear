<#
.SYNOPSIS
    Helpers for driving Illustrator from PowerShell during the investigation.

.DESCRIPTION
    Dot-source this file, then use Invoke-AiScript to run ExtendScript and
    Send-AiMessage to reach the LiveShear plug-in's research bridge.

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
