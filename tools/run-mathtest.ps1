<#
.SYNOPSIS
    Compiles and runs the arithmetic test, which needs neither Illustrator nor
    the Adobe SDK.

.DESCRIPTION
    The plugin's pure headers -- the affine algebra and the exact extent of a
    cubic Bezier -- are compiled against a handful of stub types and checked
    against brute-force sampling and against the invariants they are supposed
    to hold. It takes a second, and it covers the one code path that only runs
    when Illustrator refuses to measure art itself, which is not a condition
    that can be arranged on demand.

    Needs only a Visual Studio C++ toolchain.
#>
[CmdletBinding()]
param([string] $OutPath)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$source = Join-Path $PSScriptRoot 'mathtest\mathtest.cpp'
$stub = Join-Path $PSScriptRoot 'mathtest\stub'
$plugin = Join-Path $repo 'plugin\Source'
$work = Join-Path ([IO.Path]::GetTempPath()) 'liveshear-mathtest'
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\mathtest.txt' }
$null = New-Item -ItemType Directory -Force -Path $work
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found; install Visual Studio 2022 or the Build Tools.' }
$install = & $vswhere -products * -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
if (-not $install) { throw 'No Visual Studio C++ toolchain found.' }

$versionFile = Join-Path $install 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt'
$toolsVersion = (Get-Content $versionFile -Raw).Trim()
$cl = Join-Path $install ("VC\Tools\MSVC\{0}\bin\Hostx64\x64\cl.exe" -f $toolsVersion)
if (-not (Test-Path $cl)) { throw "cl.exe not found at $cl" }

# The compiler needs its own headers and the Windows SDK on INCLUDE and LIB.
$sdkRoot = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SDKs\Windows\v10.0' -ErrorAction SilentlyContinue).InstallationFolder
if (-not $sdkRoot) { $sdkRoot = 'C:\Program Files (x86)\Windows Kits\10\' }
$sdkVersion = (Get-ChildItem (Join-Path $sdkRoot 'Include') -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name

$vcTools = Join-Path $install ("VC\Tools\MSVC\{0}" -f $toolsVersion)
$env:INCLUDE = @(
    (Join-Path $vcTools 'include'),
    (Join-Path $sdkRoot "Include\$sdkVersion\ucrt"),
    (Join-Path $sdkRoot "Include\$sdkVersion\um"),
    (Join-Path $sdkRoot "Include\$sdkVersion\shared")
) -join ';'
$env:LIB = @(
    (Join-Path $vcTools 'lib\x64'),
    (Join-Path $sdkRoot "Lib\$sdkVersion\ucrt\x64"),
    (Join-Path $sdkRoot "Lib\$sdkVersion\um\x64")
) -join ';'

$exe = Join-Path $work 'mathtest.exe'
Push-Location $work
try {
    $compile = & $cl /nologo /EHsc /std:c++17 /W4 /WX /O2 "/I$stub" "/I$plugin" $source "/Fe:$exe" 2>&1
    $compile | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw "The arithmetic test did not compile (exit $LASTEXITCODE)." }
}
finally { Pop-Location }

$output = & $exe 2>&1
$code = $LASTEXITCODE
$output | ForEach-Object { Write-Output $_ }

$lines = New-Object Collections.Generic.List[string]
$lines.Add('Live Shear -- arithmetic, without Illustrator')
$lines.Add(("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
$lines.Add(("Compiler: cl.exe {0}, /W4 /WX /std:c++17 /O2" -f $toolsVersion))
$lines.Add('')
foreach ($line in $output) { $lines.Add([string] $line) }
[System.IO.File]::WriteAllLines($OutPath, $lines)

$summary = ($output | Where-Object { $_ -match '^\d+ checks' } | Select-Object -Last 1)
if ($summary -match '^(\d+) checks, (\d+) failed') {
    $rows = @("probe`tgroup`tcase`texpected`tobserved`tstatus")
    $rows += ("mathtest`tarithmetic`tthe affine algebra and the exact extent of a cubic Bezier, compiled against stub types and checked against brute-force sampling`tevery check passes`t{0} checks, {1} failed`t{2}" -f $Matches[1], $Matches[2], $(if ([int] $Matches[2] -eq 0) { 'PASS' } else { 'FAIL' }))
    [System.IO.File]::WriteAllLines(($OutPath -replace '\.txt$', '.tsv'), $rows)
}

Write-Output ""
Write-Output "Written to $OutPath"
if ($code -ne 0) { throw 'The arithmetic test failed.' }
