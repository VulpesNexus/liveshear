<#
.SYNOPSIS
    What GetArtTransformBounds actually returns for each combination of the
    bounds flags, on each kind of artwork that distinguishes them.

.DESCRIPTION
    The effect's reference point is the center of the artwork's geometric
    bounds, and which flags ask the host for that box is not something the SDK
    header can be trusted on. Two of its statements are wrong:

        kControlBounds says the other flags "can be combined" when it is off.
        Combined with it, they do not mean something stricter -- the call
        returns kBadParameterErr, error 1346458189, and every such request
        fails. The effect asked that way for a whole sprint, fell back to
        computing the box itself every single time, and the failures were
        written up as the host declining to measure art outside the document
        tree. That was not what was happening.

        kNoExtendedBounds says it "implies kNoStrokeBounds". It does not. On a
        mitered triangle, visible|noExtended still carries the 600 pt spike of
        the miter; only setting both gives the outline.

    So this prints the table, against fixtures chosen so that each flag has
    something to do: a mitered spike for strokes, area text for glyphs, a
    clipping group, and a plain stroked rectangle. Illustrator's own
    geometricBounds and visibleBounds are printed beside it as the reference
    the answer has to match.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [string[]] $Fixture = @('spike', 'areaText', 'clipGroup', 'strokedRect', 'plainRect')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\bounds-flags.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'bounds-flags'

Note 'Live Shear -- what each combination of the bounds flags returns'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ''
Note 'Error 1346458189 is kBadParameterErr: the call failed and returned nothing.'
Note 'The flags the effect uses are visible|noStroke|noExtended, which is the row'
Note 'that matches what Illustrator itself calls geometricBounds.'
Note ''

$agreements = 0
$errors = 0
foreach ($name in $Fixture) {
    Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.selectOnly(LS.target); app.redraw();" | Out-Null
    $dom = Js 'LS.bounds(LS.target);'
    $parts = $dom -split ';'
    Note ("--- {0} ---" -f $name)
    Note ("  Illustrator's geometricBounds: {0}" -f $parts[0])
    Note ("  Illustrator's visibleBounds:   {0}" -f $parts[1])

    $table = Send-AiMessage 'bounds flags'
    foreach ($line in ($table -split "`r?`n")) {
        if (-not $line.Trim()) { continue }
        Note ("  " + $line.Trim())
    }

    # The one row the effect depends on has to equal the host's own
    # geometricBounds, or the reference point is being taken from the wrong box.
    $wanted = ($table -split "`r?`n" | Where-Object { $_ -match 'visible\|noStroke\|noExtended' }) -join ''
    $cells = $wanted -split "`t"
    $ok = $false
    if ($cells.Count -ge 7) {
        $fromFlags = ($cells[3..6] | ForEach-Object { [double] $_ })
        $fromDom = ($parts[0] -split ',' | ForEach-Object { [double] $_ })
        $ok = $true
        for ($i = 0; $i -lt 4; $i++) { if ([Math]::Abs($fromFlags[$i] - $fromDom[$i]) -gt 1e-6) { $ok = $false } }
    }
    if ($ok) { $agreements++ }
    if ($table -match '1346458189') { $errors++ }

    Add-ProbeResult -Group 'bounds flags' -Case ("{0}: visible|noStroke|noExtended returns Illustrator's geometricBounds" -f $name) `
        -Expected 'the flags the effect uses ask for the box the native shear anchors on' `
        -Observed $(if ($ok) { "the flags return {0}, which is what the DOM calls geometricBounds" -f $parts[0] } else { "the flags do not return the DOM's geometricBounds ({0})" -f $parts[0] }) `
        -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
    Note ''
}

Add-ProbeResult -Group 'bounds flags' -Case 'kControlBounds cannot be combined with the flags that exclude things' `
    -Expected 'the SDK header implies it can; the host says otherwise' `
    -Observed ("every control|noStroke and control|noExtended request returned kBadParameterErr (1346458189), on {0} of {1} fixtures" -f $errors, @($Fixture).Count) `
    -Status $(if ($errors -eq @($Fixture).Count) { 'PASS' } else { 'FAIL' })

Note ("{0} of {1} fixtures: visible|noStroke|noExtended equals Illustrator's own geometricBounds" -f $agreements, @($Fixture).Count)
Note ("{0} of {1} fixtures: combining kControlBounds with an exclusion flag returned kBadParameterErr" -f $errors, @($Fixture).Count)
Js 'LS.clear();' | Out-Null
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
Save-ProbeTranscript -Path $OutPath -Lines $log
Write-Output "Written to $OutPath"
