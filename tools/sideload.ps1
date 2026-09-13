<#
.SYNOPSIS
    Installs the plugin without administrator rights, through Illustrator's
    Additional Plug-ins Folder.

.DESCRIPTION
    Copying an .aip into Program Files needs an administrator. On a machine
    where the signed-in account is an ordinary user that is not a prompt anyone
    can click through -- Windows asks for an administrator's password, which a
    user may simply not have.

    Illustrator has always had a second place to look. Edit > Preferences >
    Plug-ins and Scratch Disks carries an Additional Plug-ins Folder, and that
    folder can live anywhere the user can write. This script sets it, because
    the preference is stored in a file rather than reachable from scripting.

    The preferences file is plain text with hex-encoded path entries:

        /plugins [ 60
            453a5c4c6f6c6920...
        ]

    where the number is the length of the path in bytes, UTF-8, wrapped at
    thirty-two bytes to the line.

    Illustrator rewrites this file when it exits, so it has to be closed while
    the change is made or the change is simply overwritten. The script refuses
    to run otherwise.

    The previous value is kept so -Restore puts the machine back exactly as it
    was, and the whole preferences file is backed up before the first change.

.EXAMPLE
    .\tools\sideload.ps1 -Show
    .\tools\sideload.ps1 -Path "$env:LOCALAPPDATA\Adobe Illustrator Plug-ins\30"
    .\tools\sideload.ps1 -Restore
#>
[CmdletBinding(DefaultParameterSetName = 'Show')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Set', Position = 0)]
    [string] $Path,

    [Parameter(Mandatory, ParameterSetName = 'Restore')]
    [switch] $Restore,

    [Parameter(ParameterSetName = 'Show')]
    [switch] $Show,

    # Where Illustrator keeps its preferences. Only worth overriding to test
    # the parsing against a copy.
    [string] $PrefsPath,

    # The settings generation, which is the major version. 30 is Illustrator
    # 2026.
    [int] $Generation = 30
)

$ErrorActionPreference = 'Stop'

if (-not $PrefsPath) {
    $roaming = [Environment]::GetFolderPath('ApplicationData')
    $locale = 'en_US'
    $localeFile = Join-Path $roaming ("Adobe\Adobe Illustrator {0} Settings\.locale" -f $Generation)
    if (Test-Path $localeFile) {
        $read = ([IO.File]::ReadAllText($localeFile)).Trim()
        if ($read) { $locale = $read }
    }
    $PrefsPath = Join-Path $roaming ("Adobe\Adobe Illustrator {0} Settings\{1}\x64\Adobe Illustrator Prefs" -f $Generation, $locale)
}

if (-not (Test-Path $PrefsPath)) { throw "No Illustrator preferences at $PrefsPath" }

$stateDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'LiveShear'
# Both of these are per generation. Illustrator keeps a separate preferences
# file for every version it has ever installed, so more than one can be
# sideloaded at once -- which is the normal state of affairs on a machine that
# has last year's Illustrator and this year's side by side. A single shared
# state file meant the second generation recorded no previous value at all,
# and restoring it then wrote the *other* version's old path into it and
# deleted the record both of them depended on.
$statePath = Join-Path $stateDir ("sideload-previous.{0}.txt" -f $Generation)
$backupPath = Join-Path $stateDir ("Adobe Illustrator Prefs.{0}.backup" -f $Generation)

# A value saved before the state file was split by generation belongs to the
# generation whose backup sits beside it.
$legacyStatePath = Join-Path $stateDir 'sideload-previous.txt'
if ((Test-Path $legacyStatePath) -and -not (Test-Path $statePath) -and (Test-Path $backupPath)) {
    [IO.File]::Move($legacyStatePath, $statePath)
}

# Latin-1 round-trips every byte through a string unchanged, which is what
# lets the hex payload and the rest of the file survive being edited as text.
# GetEncoding(28591) rather than [Text.Encoding]::Latin1, which arrived in
# .NET 5 and is not in Windows PowerShell.
$latin1 = [Text.Encoding]::GetEncoding(28591)

function Read-Prefs { $latin1.GetString([IO.File]::ReadAllBytes($PrefsPath)) }

function Write-Prefs([string] $text) {
    [IO.File]::WriteAllBytes($PrefsPath, $latin1.GetBytes($text))
}

function Get-PluginsBlock([string] $text) {
    # /plugins [ <count><CRLF><TAB><hex>...<CRLF>]<CRLF>
    $m = [regex]::Match($text, "/plugins \[ (\d+)\r\n(.*?)\r\n\]\r\n", [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) { return $null }
    $hex = ($m.Groups[2].Value -replace "[^0-9a-fA-F]", '')
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [pscustomobject]@{
        Match = $m
        Bytes = $bytes
        Value = [Text.Encoding]::UTF8.GetString($bytes)
    }
}

function New-PluginsBlock([string] $folder) {
    if (-not $folder) { return "/plugins [ 0`r`n`r`n`t]`r`n" }
    $bytes = [Text.Encoding]::UTF8.GetBytes($folder)
    $hex = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
    $lines = New-Object Collections.Generic.List[string]
    # Thirty-two bytes, sixty-four hex characters, to the line: the shape
    # Illustrator writes itself.
    for ($i = 0; $i -lt $hex.Length; $i += 64) {
        $take = [Math]::Min(64, $hex.Length - $i)
        $lines.Add("`t" + $hex.Substring($i, $take))
    }
    "/plugins [ {0}`r`n{1}`r`n]`r`n" -f $bytes.Length, ($lines -join "`r`n")
}

function Assert-IllustratorClosed {
    if (Get-Process Illustrator -ErrorAction SilentlyContinue) {
        throw 'Illustrator is running. It rewrites its preferences when it exits, so close it first (tools/ai.ps1 Stop-Ai does it over COM).'
    }
}

$text = Read-Prefs
$block = Get-PluginsBlock $text
$current = if ($block) { $block.Value } else { '' }

switch ($PSCmdlet.ParameterSetName) {
    'Show' {
        if ($current) {
            Write-Output "Additional Plug-ins Folder: $current"
            if (Test-Path $current) {
                $found = @(Get-ChildItem -Path $current -Filter *.aip -Recurse -ErrorAction SilentlyContinue)
                Write-Output ("  the folder exists and holds {0} plugin(s): {1}" -f $found.Count, (($found | ForEach-Object { $_.Name }) -join ', '))
            }
            else { Write-Output '  the folder does not exist, so Illustrator loads nothing extra' }
        }
        else { Write-Output 'Additional Plug-ins Folder: not set' }
        if (Test-Path $statePath) {
            Write-Output ("Saved previous value: {0}" -f ([IO.File]::ReadAllText($statePath)))
        }
    }

    'Set' {
        Assert-IllustratorClosed
        $full = [IO.Path]::GetFullPath($Path)
        if (-not (Test-Path $full)) { $null = New-Item -ItemType Directory -Force -Path $full }
        $null = New-Item -ItemType Directory -Force -Path $stateDir

        if (-not (Test-Path $backupPath)) { Copy-Item $PrefsPath $backupPath }
        # Only record the previous value the first time, so setting the folder
        # twice in a row cannot lose the original.
        if (-not (Test-Path $statePath)) {
            [IO.File]::WriteAllText($statePath, $current)
            Write-Output ("Saved the previous value: {0}" -f $(if ($current) { $current } else { '(not set)' }))
        }

        $replacement = New-PluginsBlock $full
        if ($block) { $text = $text.Remove($block.Match.Index, $block.Match.Length).Insert($block.Match.Index, $replacement) }
        else { $text = $replacement + $text }
        Write-Prefs $text

        Write-Output "Additional Plug-ins Folder set to: $full"
        Write-Output 'Start Illustrator for it to take effect.'
    }

    'Restore' {
        Assert-IllustratorClosed
        if (-not (Test-Path $statePath)) { throw "Nothing saved to restore; the folder is currently $current" }
        $previous = [IO.File]::ReadAllText($statePath)

        $replacement = New-PluginsBlock $previous
        if ($block) { $text = $text.Remove($block.Match.Index, $block.Match.Length).Insert($block.Match.Index, $replacement) }
        else { $text = $replacement + $text }
        Write-Prefs $text
        [IO.File]::Delete($statePath)

        Write-Output ("Additional Plug-ins Folder restored to: {0}" -f $(if ($previous) { $previous } else { '(not set)' }))
        Write-Output "The preferences as they were before the first change are kept at $backupPath"
    }
}
