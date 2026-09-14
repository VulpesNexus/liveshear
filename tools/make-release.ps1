<#
.SYNOPSIS
    Builds the Release plugin and assembles the distribution archive.

.DESCRIPTION
    Produces dist\LiveShear-<version>.zip containing the plugin, the README, the
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
# somebody once had. An earlier version hard-coded the first word of the
# developer's own directory, in the file whose whole job is keeping the
# developer out of the binary, so the names are taken from $repo and the
# environment at run time and none of them is written down here. Naming a
# folder in order to explain why you should not name it still names it.
$patterns = @('[A-Za-z]:\\Users[ -~]{0,120}', '[A-Za-z]:\\Documents and Settings[ -~]{0,120}')
foreach ($secret in @($repo, $env:USERPROFILE, (Split-Path -Parent $repo))) {
    if ($secret) { $patterns += [regex]::Escape($secret) + '[ -~]{0,120}' }
}
# The account name, but only as a whole word. Without the boundaries a short
# account name turns up inside ordinary English: one here is a prefix of
# "through", and it matched the plugin's own trace line "art passed through
# unchanged", refusing to pack a binary that was perfectly clean.
if ($env:USERNAME -and $env:USERNAME.Length -gt 2) {
    $patterns += '(?<![A-Za-z0-9])' + [regex]::Escape($env:USERNAME) + '(?![A-Za-z0-9])'
}
$leaks = [regex]::Matches($ascii, ($patterns -join '|'))
if ($leaks.Count -gt 0) {
    $leaks | Select-Object -First 5 | ForEach-Object { Write-Output ("  leak: " + $_.Value) }
    throw 'The binary contains an absolute path from the build machine.'
}
Write-Output 'No build-machine paths in the binary.'

# --- the evidence describes this binary -----------------------------------
#
# A probe that dies partway leaves its previous results on disk, and the
# generated matrix then quotes rows measured against a different binary as
# though they described this one. That happened: the persistence probe printed
# its heading, lost its COM connection, and left an older file behind, and the
# suite's summary column showed nothing wrong.
#
# So every evidence file has to be newer than the build record, which is
# written by probe-build.ps1 at the start of the sequence.
#
# A file earns an exemption by not describing this binary at all -- and by
# nothing else. Being awkward to run, slow, or outside the suite is a reason to
# remember to run it, not a reason for the gate to stop asking. The list was
# once the other way round, and it quietly carried a crash comparison measured
# against an older build through a release, plus an entry for a probe that had
# not been run at all.
#
# The sentence above said "every evidence file" for two releases while the code
# below filtered *.tsv, so every readable transcript and every screenshot was
# outside the gate the whole time -- including the crash comparison that started
# all this. That is the same defect as the exemption list, one level down: the
# earlier fix went into the list of what is excused when the hole was in the
# list of what is examined. A gate is worth exactly what its narrowest clause
# says, not what its comment says, so the two now agree by construction.
$buildRecord = Join-Path $repo 'docs\evidence\build.txt'
if (Test-Path $buildRecord) {
    $builtAt = (Get-Item $buildRecord).LastWriteTimeUtc
    # native-shear.tsv records what Illustrator's own Shear command does. It is
    # the oracle this plugin is measured against, not a measurement of it, so a
    # rebuild cannot invalidate it; only a new Illustrator could.
    #
    # build.tsv is the build probe's own result, written in the same instant as
    # the record it would be compared against; a strict comparison makes it look
    # older than itself. build.txt is that record, and comparing it against
    # itself is not a question worth asking.
    $exempt = @('native-shear.tsv', 'build.tsv', 'build.txt')
    # Results, transcripts, and screenshots alike: a stale screenshot of the
    # dialog misrepresents this build exactly as a stale row does. Not recursive
    # on purpose -- docs\evidence\history\ holds runs that are dated in their
    # filenames and are not claimed to describe this binary, which is a thing a
    # reader sees in the path rather than having to find in this script.
    $kinds = @('.tsv', '.txt', '.png')
    $stale = @(Get-ChildItem (Join-Path $repo 'docs\evidence') -File |
               Where-Object { $kinds -contains $_.Extension.ToLower() -and
                              $_.LastWriteTimeUtc -lt $builtAt -and
                              $exempt -notcontains $_.Name })
    if ($stale.Count -gt 0) {
        $stale | ForEach-Object {
            Write-Output ("  stale: {0}  written {1}" -f $_.Name, $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
        }
        $message = "{0} evidence file(s) predate the build in docs\evidence\build.txt, so the matrix would " +
                   "describe a binary this archive does not contain. Re-run those probes. If a file is an " +
                   "older run kept for the record and nothing cites it as current, move it to " +
                   "docs\evidence\history\ with its date in the filename instead. Only add a file to the " +
                   "exempt list in this script if it does not describe the plugin binary at all; being " +
                   "slow or run by hand does not qualify."
        throw ($message -f $stale.Count)
    }
    Write-Output 'Evidence checked: every probe result postdates the build it describes.'
}

# --- assemble -------------------------------------------------------------
# Named to match the repository and the plugin file rather than the
# product name, so an archive on disk is obviously this thing.
$stage = Join-Path $dist ("LiveShear-" + $version)
if (Test-Path $stage) { [IO.Directory]::Delete($stage, $true) }
$null = New-Item -ItemType Directory -Force -Path $stage
$null = New-Item -ItemType Directory -Force -Path (Join-Path $dist 'symbols')

Copy-Item $binary (Join-Path $stage 'LiveShear.aip')
# LICENSE-EXCEPTION travels with the binary, not just with the source: it is
# the permission that makes this .aip distributable at all, because seven of
# its object files are compiled from Adobe's sample framework. An archive that
# cited it without carrying it would be citing a file its recipient does not
# have.
foreach ($doc in @('README.md', 'LICENSE', 'LICENSE-EXCEPTION', 'KNOWN_LIMITATIONS.md', 'RELEASE_NOTES.md')) {
    $source = Join-Path $repo $doc
    if (Test-Path $source) { Copy-Item $source (Join-Path $stage $doc) }
    else { Write-Output ("  missing, not packed: {0}" -f $doc) }
}

# INSTALL.txt carries the version in its first line, so it is a template, and
# it is the file a downloader actually reads: the README is long and the .aip
# sits next to it looking openable. A tester double-clicked the .aip and got
# Illustrator's "the file format is unknown" alert, which says nothing about
# what to do instead. This is what says it.
$installTemplate = Join-Path $repo 'packaging\INSTALL.txt'
if (Test-Path $installTemplate) {
    $installText = [IO.File]::ReadAllText($installTemplate).Replace('{VERSION}', $version)
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $stage 'INSTALL.txt'), $installText, $utf8)
    Write-Output '  INSTALL.txt written from packaging\INSTALL.txt'
}

$archive = Join-Path $dist ("LiveShear-" + $version + ".zip")
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
