<#
.SYNOPSIS
    Copies LiveShear.aip into Illustrator's plug-in folder, or removes it again.

.DESCRIPTION
    Writing to the Illustrator plug-in folder needs administrator rights, so the
    script relaunches itself elevated unless it already is. Illustrator only
    reads its plug-in folder at startup: quit and reopen it after installing or
    uninstalling.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string] $Configuration = 'Release',
    [string] $PluginFolder = 'C:\Program Files\Adobe\Adobe Illustrator 2026\Plug-ins',
    [switch] $Uninstall,
    [switch] $Elevated
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo "build\$Configuration\LiveShear.aip"
$target = Join-Path $PluginFolder 'LiveShear.aip'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($Elevated) { throw 'Relaunched elevated but still not running as administrator.' }
    # Every path here can contain spaces, ampersands, and non-ASCII characters,
    # so each one is quoted individually before Start-Process re-joins them.
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass',
                   '-File', "`"$PSCommandPath`"",
                   '-Configuration', "`"$Configuration`"",
                   '-PluginFolder', "`"$PluginFolder`"",
                   '-Elevated')
    if ($Uninstall) { $arguments += '-Uninstall' }
    Write-Output 'Requesting administrator rights...'
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Elevated run failed with exit code $($process.ExitCode)." }
    Write-Output 'Done. Restart Illustrator for the change to take effect.'
    return
}

if ($Uninstall) {
    if (Test-Path $target) {
        [System.IO.File]::Delete($target)
        Write-Output "Removed $target"
    }
    else {
        Write-Output "Nothing to remove at $target"
    }
    return
}

if (-not (Test-Path $source)) { throw "Build output not found: $source. Run tools\build.ps1 first." }
[System.IO.File]::Copy($source, $target, $true)
Write-Output "Installed $target"
