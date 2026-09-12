<#
.SYNOPSIS
    Build, install, and restart Illustrator in one step.

.DESCRIPTION
    Illustrator reads its plugin folder only at startup and holds the .aip open
    while it runs, so every change needs the same four moves: build, quit the
    host, copy, start it again. This does them, and optionally turns on the
    plugin's own trace file for the new session.

.EXAMPLE
    .\tools\redeploy.ps1 -LogPath C:\temp\shear.log
#>
[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string] $Configuration = 'Release',
    [string] $SdkRoot = $env:AI_SDK_ROOT,
    [string] $LogPath,
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1') -Configuration $Configuration -SdkRoot $SdkRoot | Out-Null
    Write-Output 'Built.'
}

try { Stop-Ai | Out-Null } catch { }
if (Get-Process Illustrator -ErrorAction SilentlyContinue) {
    Stop-Process -Name Illustrator -Force
    Start-Sleep -Seconds 2
}
Write-Output 'Illustrator stopped.'

& (Join-Path $PSScriptRoot 'install.ps1') -Configuration $Configuration | Out-Null
Write-Output 'Installed.'

if ($LogPath) {
    if (Test-Path $LogPath) { [System.IO.File]::Delete($LogPath) }
    $env:LIVESHEAR_LOG = $LogPath
    Write-Output "Tracing to $LogPath"
}
Start-Ai | Out-Null
Install-AiHarness | Out-Null
Invoke-AiScript 'app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS; while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } app.documents.add(); "ready";'
