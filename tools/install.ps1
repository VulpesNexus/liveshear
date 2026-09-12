<#
.SYNOPSIS
    Copies LiveShear.aip into Illustrator's plugin folder, or removes it again.

.DESCRIPTION
    Writing to the Illustrator plugin folder needs administrator rights, so the
    script relaunches itself elevated unless it already is. Illustrator only
    reads its plugin folder at startup, and holds the plugin open while it runs,
    so it has to be closed: if it is up when the copy is attempted, the script
    says so and waits rather than failing.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string] $Configuration = 'Release',
    [string] $PluginFolder = 'C:\Program Files\Adobe\Adobe Illustrator 2026\Plug-ins',
    [switch] $Uninstall,
    [switch] $Elevated,
    [int] $WaitMinutes = 15
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
                   '-WaitMinutes', "$WaitMinutes",
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

# Illustrator holds the .aip open for as long as it runs, so the copy fails
# while it is up. Rather than refusing outright, wait for it: the installer is
# usually run by someone who can simply close it, and closing it themselves is
# better than having their unsaved work closed for them.
$deadline = (Get-Date).AddMinutes($WaitMinutes)
$warned = $false
while ($true) {
    try {
        [System.IO.File]::Copy($source, $target, $true)
        break
    }
    catch [System.UnauthorizedAccessException] {
        if (-not (Get-Process Illustrator -ErrorAction SilentlyContinue)) { throw }
        if (-not $warned) {
            Write-Output 'Illustrator is running and is holding the plugin open. Close it and this will continue.'
            $warned = $true
        }
        if ((Get-Date) -ge $deadline) {
            throw "Illustrator is still running after $WaitMinutes minutes. Close it and run this again."
        }
        Start-Sleep -Seconds 2
    }
}
Write-Output "Installed $target"
