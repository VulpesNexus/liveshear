<#
.SYNOPSIS
    Checks the built plugin itself: both configurations, warnings, identity,
    linkage, and what the binary gives away about the machine that made it.

.DESCRIPTION
    None of this needs Illustrator. It is the part of a release check that is
    about the artifact rather than the behavior: that Release and Debug both
    build clean at the warning level the project sets, that Release links the
    retail C runtime rather than the debug one a user will not have, that the
    binary carries this project's identity rather than the Adobe SDK sample
    defaults it started from, that it exports the one entry point Illustrator
    looks for, and that it contains no absolute path from the build machine.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [string] $SdkRoot = $env:AI_SDK_ROOT
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\build.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)
if (-not $SdkRoot) { throw 'Set AI_SDK_ROOT, or pass -SdkRoot, to point at your copy of the Adobe Illustrator 2026 SDK.' }

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }

$script:pass = 0
$script:fail = 0
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    Note ("[{0}] {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name)
    if ($detail) { Note ("       " + $detail) }
    Add-ProbeResult -Group 'release build' -Case $name -Expected 'the artifact is fit to ship' -Observed $detail -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
}

Start-ProbeResults -Probe 'build'
Note 'Live Shear -- the built artifact'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Windows {0}" -f [Environment]::OSVersion.Version)
Note ''

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found; install Visual Studio 2022 or the Build Tools.' }

# More than one Visual Studio can be installed, and the newest is not
# necessarily the one with the C++ compiler in it, so take the first that has
# both MSBuild and a C++ toolchain rather than whichever is latest.
$msbuild = $null
$toolsVersion = $null
foreach ($candidate in (& $vswhere -products * -requires Microsoft.Component.MSBuild -format value -property installationPath)) {
    $exe = Join-Path $candidate 'MSBuild\Current\Bin\MSBuild.exe'
    $versionFile = Join-Path $candidate 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
    if ((Test-Path $exe) -and (Test-Path $versionFile)) {
        $msbuild = $exe
        $toolsVersion = (Get-Content $versionFile -Raw).Trim()
        break
    }
}
if (-not $msbuild) { throw 'No Visual Studio installation with both MSBuild and a C++ toolchain was found.' }
Note ("Toolchain: MSVC {0}" -f $toolsVersion)
Note ("SDK:       {0}" -f $SdkRoot)
Note ''

foreach ($configuration in @('Release', 'Debug')) {
    $output = & $msbuild (Join-Path $repo 'plugin\LiveShear.vcxproj') "/p:Configuration=$configuration" /p:Platform=x64 /v:minimal /nologo "/p:AISDKRoot=$SdkRoot" /t:Rebuild 2>&1
    $warnings = @($output | Where-Object { $_ -match ': warning ' })
    $errors = @($output | Where-Object { $_ -match ': error ' })
    Check ("{0} builds with no warnings and no errors" -f $configuration) (($warnings.Count -eq 0) -and ($errors.Count -eq 0)) ("{0} warnings, {1} errors" -f $warnings.Count, $errors.Count)
    foreach ($w in ($warnings | Select-Object -First 5)) { Note ("       " + $w) }
}

$binary = Join-Path $repo 'build\Release\LiveShear.aip'
Check 'the Release build produced a plugin' (Test-Path $binary) $binary
if (-not (Test-Path $binary)) {
    Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
    [System.IO.File]::WriteAllLines($OutPath, $log)
    throw 'No Release binary to inspect.'
}

$info = (Get-Item $binary).VersionInfo
Note ''
Note ("File version:   {0}" -f $info.FileVersion)
Note ("Company:        {0}" -f $info.CompanyName)
Note ("Product:        {0}" -f $info.ProductName)
Note ("Description:    {0}" -f $info.FileDescription)
Note ("Copyright:      {0}" -f $info.LegalCopyright)
Note ("Size:           {0:N0} bytes" -f (Get-Item $binary).Length)
Note ("SHA-256:        {0}" -f (Get-FileHash $binary -Algorithm SHA256).Hash)
Note ''

Check 'the binary does not claim Adobe as its publisher' ($info.CompanyName -notmatch 'Adobe') ("CompanyName is {0}" -f $info.CompanyName)
Check 'the binary names its own product' ($info.ProductName -notmatch '^Adobe Illustrator$') ("ProductName is {0}" -f $info.ProductName)
Check 'the binary carries a version' ([bool] $info.FileVersion) ("FileVersion is {0}" -f $info.FileVersion)

$bytes = [IO.File]::ReadAllBytes($binary)
$ascii = [Text.Encoding]::ASCII.GetString($bytes)

$runtimes = ([regex]::Matches($ascii, 'MSVCP\d+D?\.dll|VCRUNTIME\d+D?\.dll|ucrtbased?\.dll') | ForEach-Object { $_.Value } | Sort-Object -Unique)
$debugRuntime = @($runtimes | Where-Object { $_ -match 'D\.dll$|ucrtbased' })
Check 'Release links the retail C runtime, not the debug one' ($debugRuntime.Count -eq 0) ("links {0}" -f ($runtimes -join ', '))

$paths = [regex]::Matches($ascii, '[A-Za-z]:\\(Users|Documents and Settings)[ -~]{0,100}')
Check 'no path from the build machine is embedded' ($paths.Count -eq 0) $(if ($paths.Count -eq 0) { 'none found' } else { ($paths | Select-Object -First 3 | ForEach-Object { $_.Value }) -join ' | ' })

# Wrapped in @() because a single match would otherwise arrive as a bare
# string, whose [0] is its first character rather than the whole name.
$pdbNames = @([regex]::Matches($ascii, '[ -~]{0,80}\.pdb') | ForEach-Object { $_.Value } | Sort-Object -Unique)
Check 'the symbol reference is a bare file name' (($pdbNames.Count -eq 1) -and ($pdbNames[0] -eq 'LiveShear.pdb')) ("symbol references: {0}" -f ($pdbNames -join ', '))

Check 'the entry point Illustrator looks for is exported' ($ascii -match 'PluginMain') 'PluginMain is in the export table'
Check 'the plugin metadata resource is present' ($ascii -match 'ADBEkind' -or $ascii -match 'PiPL') 'the PIPL resource is in the binary'
Check 'the effect name that documents store is unchanged' ($ascii -match 'VulpesNexus Shear') 'VulpesNexus Shear'
Check 'the menu entry reads as a plain Adobe command' (($ascii -match 'Distort & Transform') -and ($ascii -match 'Shear\.\.\.')) 'Effect > Distort & Transform > Shear...'
Check 'no debug trace is on by default' ($ascii -match 'LIVESHEAR_LOG') 'tracing is behind the LIVESHEAR_LOG environment variable'

Note ''
Note ("{0} passed, {1} failed" -f $script:pass, $script:fail)
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
