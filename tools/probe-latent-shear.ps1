<#
.SYNOPSIS
    Asks the built-in "Adobe Transform" live effect whether it has any latent
    shear parameter, by writing candidate keys into its parameter dictionary and
    watching the rendered bounds.

.DESCRIPTION
    A control key (moveH_Pts) is written first to prove the injection path
    reaches the effect and makes it re-render. Every candidate key is then
    written with a value large enough that a real shear would be obvious, and
    the resulting bounds compared against the baseline.

    Run with Illustrator open and the LiveShear plug-in installed.
#>
[CmdletBinding()]
param([string] $LogPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $LogPath) { $LogPath = Join-Path $repo 'docs\evidence\latent-shear-probe.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }

function Get-RectBounds {
    $raw = Invoke-AiScript 'app.activeDocument.pathItems.getByName("fixture-rect").visibleBounds.join(",");'
    ($raw -split ',' | ForEach-Object { ([double] $_).ToString('0.####', [Globalization.CultureInfo]::InvariantCulture) }) -join ','
}

Note "Live Shear -- latent parameter probe on the built-in Transform effect"
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Illustrator {0}" -f (Get-AiApp).Version)
Note ''

# Fresh fixture every run so nothing carries over between probes.
Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
Invoke-AiScript -Path (Join-Path $repo 'fixtures\make_fixture.jsx') | Out-Null
Invoke-AiScript @'
app.executeMenuCommand("deselectall");
app.activeDocument.pathItems.getByName("fixture-rect").selected = true;
'@ | Out-Null

Note "Applying Adobe Transform with an empty parameter dictionary."
Note (Send-AiMessage 'apply effect' 'Adobe Transform|').TrimEnd()
$baseline = Get-RectBounds
Note "baseline bounds: $baseline"
Note ''

Note '--- control: a documented key must move the art ---'
Note (Send-AiMessage 'set param' '0|moveH_Pts|real|40').TrimEnd()
$control = Get-RectBounds
Note "bounds with moveH_Pts=40: $control"
if ($control -eq $baseline) { Note 'CONTROL FAILED: the injection path does not reach the effect. Nothing below is meaningful.' }
else { Note 'CONTROL PASSED: writing a key into the built-in effect dictionary re-renders the art.' }
Note (Send-AiMessage 'delete param' '0|moveH_Pts').TrimEnd()
$restored = Get-RectBounds
Note "bounds after deleting moveH_Pts: $restored"
Note ''

# Names worth trying: Adobe's own vocabulary style (documented keys use
# lowerCamelCase with a units suffix), plus the obvious alternatives and the
# generic matrix forms a renderer might accept.
$candidates = @(
    @{ key = 'shear';                 type = 'real';   value = '30' }
    @{ key = 'shear_Degrees';         type = 'real';   value = '30' }
    @{ key = 'shear_Radians';         type = 'real';   value = '0.5236' }
    @{ key = 'shearH_Degrees';        type = 'real';   value = '30' }
    @{ key = 'shearV_Degrees';        type = 'real';   value = '30' }
    @{ key = 'shearAngle';            type = 'real';   value = '30' }
    @{ key = 'shearAxis';             type = 'real';   value = '0' }
    @{ key = 'shearAxis_Degrees';     type = 'real';   value = '0' }
    @{ key = 'shearX';                type = 'real';   value = '30' }
    @{ key = 'shearY';                type = 'real';   value = '30' }
    @{ key = 'skew';                  type = 'real';   value = '30' }
    @{ key = 'skewX';                 type = 'real';   value = '30' }
    @{ key = 'skewY';                 type = 'real';   value = '30' }
    @{ key = 'skew_Degrees';          type = 'real';   value = '30' }
    @{ key = 'skewAngle';             type = 'real';   value = '30' }
    @{ key = 'slant';                 type = 'real';   value = '30' }
    @{ key = 'slant_Degrees';         type = 'real';   value = '30' }
    @{ key = 'axis';                  type = 'real';   value = '45' }
    @{ key = 'axis_Degrees';          type = 'real';   value = '45' }
    @{ key = 'tangent';               type = 'real';   value = '0.5774' }
    @{ key = 'matrix';                type = 'matrix'; value = '1,0,0.5774,1,0,0' }
    @{ key = 'transformMatrix';       type = 'matrix'; value = '1,0,0.5774,1,0,0' }
    @{ key = 'affine';                type = 'matrix'; value = '1,0,0.5774,1,0,0' }
    @{ key = 'Matrix';                type = 'matrix'; value = '1,0,0.5774,1,0,0' }
    @{ key = 'shearMatrix';           type = 'matrix'; value = '1,0,0.5774,1,0,0' }
)

Note '--- candidates ---'
$changed = @()
foreach ($c in $candidates) {
    $spec = '0|{0}|{1}|{2}' -f $c.key, $c.type, $c.value
    Send-AiMessage 'set param' $spec | Out-Null
    $after = Get-RectBounds
    $verdict = if ($after -eq $restored) { 'no effect' } else { 'CHANGED'; }
    Note ("{0,-22} {1,-7} = {2,-22} -> {3}  [{4}]" -f $c.key, $c.type, $c.value, $verdict, $after)
    if ($after -ne $restored) { $changed += $c.key }
    Send-AiMessage 'delete param' ('0|{0}' -f $c.key) | Out-Null
}

Note ''
if ($changed.Count -eq 0) {
    Note 'RESULT: no candidate key changed the rendering. The built-in Transform effect exposes no latent shear.'
}
else {
    Note ("RESULT: these keys changed the rendering: {0}" -f ($changed -join ', '))
}

Note ''
Note 'Final dictionary state:'
Note (Send-AiMessage appearance).TrimEnd()

[System.IO.File]::WriteAllLines($LogPath, $log)
Write-Output "`nWritten to $LogPath"
