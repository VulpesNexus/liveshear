<#
.SYNOPSIS
    Builds LiveShear.aip against a local copy of the Adobe Illustrator SDK.

.DESCRIPTION
    The SDK is not redistributable and is not vendored into this repository.
    Point -SdkRoot at your copy, or set the AI_SDK_ROOT environment variable.
#>
[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string] $Configuration = 'Release',
    [string] $SdkRoot = $env:AI_SDK_ROOT
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repo 'plugin\LiveShear.vcxproj'
if (-not (Test-Path $project)) { throw "Project not found: $project" }

if (-not $SdkRoot) {
    throw 'Set the AI_SDK_ROOT environment variable, or pass -SdkRoot, to point at your copy of the Adobe Illustrator 2026 SDK.'
}
if (-not (Test-Path (Join-Path $SdkRoot 'illustratorapi\illustrator\AILiveEffect.h'))) {
    throw "That does not look like an Illustrator SDK: $SdkRoot"
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found; install Visual Studio 2022 or the Build Tools." }

$msbuild = $null
foreach ($install in (& $vswhere -products * -requires Microsoft.Component.MSBuild -format value -property installationPath)) {
    $candidate = Join-Path $install 'MSBuild\Current\Bin\MSBuild.exe'
    if (Test-Path $candidate) { $msbuild = $candidate; break }
}
if (-not $msbuild) { throw 'MSBuild.exe not found.' }

$arguments = @($project, "/p:Configuration=$Configuration", '/p:Platform=x64', '/v:minimal', '/nologo', '/nodeReuse:false')
if ($SdkRoot) { $arguments += "/p:AISDKRoot=$SdkRoot" }

& $msbuild @arguments
if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE." }

$output = Join-Path $repo "build\$Configuration\LiveShear.aip"
if (-not (Test-Path $output)) { throw "Build reported success but $output is missing." }
Write-Output $output
