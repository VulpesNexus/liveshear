<#
.SYNOPSIS
    Save, close, reopen, edit, save again, reopen again.

.DESCRIPTION
    A live effect that does not survive a round trip through the file format is
    not a live effect. Each case applies one or more effects, writes the
    document, closes it, opens it again, and compares what is on screen and what
    is in the parameter dictionary against what was there before. Then it edits
    the effect through the dictionary, saves and reopens once more, so a second
    generation of the same file is covered too.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [string] $WorkFolder
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\persistence.txt' }
if (-not $WorkFolder) { $WorkFolder = Join-Path ([IO.Path]::GetTempPath()) 'liveshear-persistence' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)
$null = New-Item -ItemType Directory -Force -Path $WorkFolder

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'persistence'

function Escape-Path([string] $p) { $p.Replace('\', '\\') }

$cases = @(
    @{ Name = 'one effect on a path';      Fixture = 'plainRect';  Effects = @(@(30, 0)) },
    @{ Name = 'one effect on live text';   Fixture = 'pointText';  Effects = @(@(25, 0)) },
    @{ Name = 'one effect on stroked art'; Fixture = 'strokedRect';Effects = @(@(-18, 0)) },
    @{ Name = 'two Shear effects';         Fixture = 'plainRect';  Effects = @(@(30, 0), @(-12, 90)) },
    @{ Name = 'Shear plus Transform';      Fixture = 'plainRect';  Effects = @(@(30, 0)); Transform = $true }
)

$pass = 0; $fail = 0
foreach ($case in $cases) {
    $file = Join-Path $WorkFolder ((($case.Name) -replace '[^A-Za-z0-9]', '-') + '.ai')
    $jsFile = Escape-Path $file

    Invoke-AiScript "LS.clear(); LS.target = LS.fixtures['$($case.Fixture)'](); LS.selectOnly(LS.target); 'built';" | Out-Null
    Invoke-AiScript 'app.redraw();' | Out-Null
    foreach ($e in $case.Effects) {
        Invoke-AiScript ("LS.shear({0}, {1});" -f (Format-AiNumber $e[0]), (Format-AiNumber $e[1])) | Out-Null
    }
    if ($case.Transform) {
        Invoke-AiScript "LS.applyEffect('Adobe Transform', 'reflect=b:false;moveH_Pts=r:40');" | Out-Null
    }
    Invoke-AiScript 'app.redraw();' | Out-Null

    $beforeBounds = (Invoke-AiScript 'LS.vb(LS.target);').Trim()
    $beforeStyle = (Send-AiMessage appearance).Trim()

    Invoke-AiScript "var f = new File('$jsFile'); app.activeDocument.saveAs(f); 'saved';" | Out-Null
    Invoke-AiScript 'app.activeDocument.close(SaveOptions.SAVECHANGES); "closed";' | Out-Null
    Invoke-AiScript "app.open(new File('$jsFile')); app.redraw(); 'opened';" | Out-Null
    Invoke-AiScript 'app.executeMenuCommand("selectall"); LS.target = app.activeDocument.selection[0]; app.redraw(); "reselected";' | Out-Null

    $afterBounds = (Invoke-AiScript 'LS.vb(LS.target);').Trim()
    $afterStyle = (Send-AiMessage appearance).Trim()

    $boundsSame = $beforeBounds -eq $afterBounds
    $styleSame = $afterStyle -match 'VulpesNexus Shear'

    # Second generation: change the angle through the dictionary, save, reopen.
    Invoke-AiScript "LS.send('set param', '0|shearAngle|real|12.5');" | Out-Null
    Invoke-AiScript 'app.redraw();' | Out-Null
    $editedBounds = (Invoke-AiScript 'LS.vb(LS.target);').Trim()
    Invoke-AiScript 'app.activeDocument.save(); app.activeDocument.close(SaveOptions.SAVECHANGES); "resaved";' | Out-Null
    Invoke-AiScript "app.open(new File('$jsFile')); app.redraw(); 'reopened';" | Out-Null
    Invoke-AiScript 'app.executeMenuCommand("selectall"); LS.target = app.activeDocument.selection[0]; app.redraw(); "reselected";' | Out-Null
    $secondBounds = (Invoke-AiScript 'LS.vb(LS.target);').Trim()
    $secondStyle = (Send-AiMessage appearance).Trim()

    $editSurvived = $editedBounds -eq $secondBounds
    $ok = $boundsSame -and $styleSame -and $editSurvived
    if ($ok) { $pass++ } else { $fail++ }

    Add-ProbeResult -Group 'save and reopen' -Case $case.Name -Expected 'same bounds, effect present, edit survives a second round trip' -Observed ("reopen {0}, present {1}, edited reopen {2}" -f $boundsSame, [bool]$styleSame, $editSurvived) -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
    Note ("{0,-24} reopen bounds {1,-5} effect present {2,-5} edited reopen {3,-5} {4}" -f `
        $case.Name, $boundsSame, [bool]$styleSame, $editSurvived, $(if ($ok) { 'PASS' } else { 'FAIL' }))
    if (-not $ok) {
        Note ("    before  {0}" -f $beforeBounds)
        Note ("    after   {0}" -f $afterBounds)
        Note ("    edited  {0}" -f $editedBounds)
        Note ("    second  {0}" -f $secondBounds)
        Note ("    style   {0}" -f (($secondStyle -split "`n" | Select-Object -First 12) -join ' | '))
    }
    Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } app.documents.add(); "reset";' | Out-Null
}

Note ''
Note ("{0} passed, {1} failed" -f $pass, $fail)
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
