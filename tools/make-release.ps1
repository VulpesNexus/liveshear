<#
.SYNOPSIS
    Builds the Release plugin and assembles the distribution archive.

.DESCRIPTION
    Produces dist\Shear-<version>.zip containing the plugin, the README, the
    licence text, the release notes, and the list of known limitations, and
    leaves the symbol file beside it in dist\symbols rather than inside the
    archive.

    Nothing is published. This only assembles what a release would contain.

    Two things are checked before anything is packed: that the binary carries
    this project's identity rather than the Adobe SDK sample defaults, and that
    it contains no absolute path from the machine that built it.
#>
[CmdletBinding()]
param(
    [string] $SdkRoot = $env:AI_SDK_ROOT,
    [switch] $SkipBuild
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $repo 'dist'
$binary = Join-Path $repo 'build\Release\LiveShear.aip'
$symbols = Join-Path $repo 'build\Release\LiveShear.pdb'

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1') -Configuration Release -SdkRoot $SdkRoot | Out-Null
    Write-Output 'Built.'
    Write-Output 'Note: this is a fresh build, so its hash will not match the one in'
    Write-Output '      docs/evidence/build.txt -- MSVC stamps a link timestamp, and'
    Write-Output '      building the same source twice gives two different files. For a'
    Write-Output '      release, run tools\probe-build.ps1 first and then pack with'
    Write-Output '      -SkipBuild, so the packed binary is the one that was inspected,'
    Write-Output '      hashed, installed, and tested.'
}
if (-not (Test-Path $binary)) { throw "Build output not found: $binary" }

# --- identity ------------------------------------------------------------
$info = (Get-Item $binary).VersionInfo
$version = $info.FileVersion
Write-Output ("Version:   {0}" -f $version)
Write-Output ("Company:   {0}" -f $info.CompanyName)
Write-Output ("Product:   {0}" -f $info.ProductName)
Write-Output ("Copyright: {0}" -f $info.LegalCopyright)

if ($info.CompanyName -match 'Adobe') {
    throw 'The binary still claims Adobe as its publisher. It is carrying the SDK sample version resource.'
}
if (-not $version) { throw 'The binary has no file version.' }

# --- no developer paths ---------------------------------------------------
$bytes = [IO.File]::ReadAllBytes($binary)
$ascii = [Text.Encoding]::ASCII.GetString($bytes)
# Derived from where this actually is rather than from a list of folder names
# somebody once had. A hard-coded folder name here named the developer's own
# directory in a file meant to keep the developer out of the binary.
$patterns = @('[A-Za-z]:\\Users[ -~]{0,120}', '[A-Za-z]:\\Documents and Settings[ -~]{0,120}')
foreach ($secret in @($repo, $env:USERPROFILE, $env:USERNAME, (Split-Path -Parent $repo))) {
    if ($secret) { $patterns += [regex]::Escape($secret) + '[ -~]{0,120}' }
}
$leaks = [regex]::Matches($ascii, ($patterns -join '|'))
if ($leaks.Count -gt 0) {
    $leaks | Select-Object -First 5 | ForEach-Object { Write-Output ("  leak: " + $_.Value) }
    throw 'The binary contains an absolute path from the build machine.'
}
Write-Output 'No build-machine paths in the binary.'

# --- assemble -------------------------------------------------------------
$stage = Join-Path $dist ("Shear-" + $version)
if (Test-Path $stage) { [IO.Directory]::Delete($stage, $true) }
$null = New-Item -ItemType Directory -Force -Path $stage
$null = New-Item -ItemType Directory -Force -Path (Join-Path $dist 'symbols')

Copy-Item $binary (Join-Path $stage 'LiveShear.aip')
foreach ($doc in @('README.md', 'LICENSE', 'KNOWN_LIMITATIONS.md', 'RELEASE_NOTES.md')) {
    $source = Join-Path $repo $doc
    if (Test-Path $source) { Copy-Item $source (Join-Path $stage $doc) }
    else { Write-Output ("  missing, not packed: {0}" -f $doc) }
}

$archive = Join-Path $dist ("Shear-" + $version + ".zip")
if (Test-Path $archive) { [IO.File]::Delete($archive) }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive
if (Test-Path $symbols) { Copy-Item $symbols (Join-Path $dist ("symbols\LiveShear-" + $version + ".pdb")) -Force }

Write-Output ''
Write-Output ("Archive:  {0} ({1:N0} bytes)" -f $archive, (Get-Item $archive).Length)
Get-ChildItem $stage | ForEach-Object { Write-Output ("  {0,-24} {1,10:N0} bytes" -f $_.Name, $_.Length) }
Write-Output ("Symbols:  {0}" -f (Join-Path $dist 'symbols'))
Write-Output '          The symbol file records the absolute paths of the machine that'
Write-Output '          built it. That is what makes it useful for reading a crash dump,'
Write-Output '          and it is why it is kept out of the archive.'
Write-Output ''
Write-Output 'Nothing has been published.'
