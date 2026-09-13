<#
.SYNOPSIS
    Appearance composition: stack order, two instances, reordering, deletion.

.DESCRIPTION
    The reason a live Shear is worth having is that it composes. These cases
    check that it composes the way a live effect is supposed to, using
    Illustrator's own destructive shear as the oracle throughout.

    Substitution is the central idea. If the live effect renders exactly what
    the native command would have produced, then anything stacked above it must
    see the same input, so

        Transform( Shear-effect( art ) )  ==  Transform( native-shear( art ) )

    and, the other way up, a Shear effect above a Transform must match a native
    shear of that Transform once it has been expanded into real geometry:

        Shear-effect( Transform( art ) )  ==  native-shear( expand( Transform( art ) ) )

    The two stacks must also differ from each other, or the test would pass on
    an effect that ignored its position entirely.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [string[]] $Fixture = @('plainRect', 'selfIntersecting', 'bezier')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\appearance.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

function Same([string] $a, [string] $b, [double] $tolerance = 1e-6) {
    $x = $a -split ','
    $y = $b -split ','
    if ($x.Count -ne 4 -or $y.Count -ne 4) { return $false }
    for ($i = 0; $i -lt 4; $i++) {
        if ([math]::Abs([double]$x[$i] - [double]$y[$i]) -gt $tolerance) { return $false }
    }
    return $true
}

$script:pass = 0
$script:fail = 0
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    $verdict = if ($ok) { 'PASS' } else { "FAIL  $detail" }
    Note ("{0,-56} {1}" -f $name, $verdict)
    Add-ProbeResult -Group $script:group -Case $name -Expected 'matches the native oracle' -Observed $detail -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
}

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'appearance'

# Illustrator's shear action returns success whether or not it sheared
# anything: with nothing it can act on it raises a modal alert, which
# DONTDISPLAYALERTS answers with Continue, and the action carries on past the
# step it skipped. So every use of it here asks the artwork instead, and a
# comparison against artwork that was never sheared is stopped rather than
# reported as a difference.
$script:oracleFailures = 0
function Assert-Oracle([string] $moved, [string] $fixture) {
    if ($moved -notmatch 'moved') {
        $script:oracleFailures++
        Note ("       [oracle] {0}: Illustrator's own shear did not move the artwork; the comparison that follows is void" -f $fixture)
    }
}
$script:group = 'composition'
$transform = 'reflect=b:false;scaleH_Factor=r:1.6;scaleV_Factor=r:0.7'

Note 'Live Shear -- appearance composition'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Transform effect used as the partner: {0}" -f $transform)
Note ''

foreach ($name in $Fixture) {
    Note ("--- {0} ---" -f $name)
    $script:group = $name

    # 1. Transform above a live Shear, against Transform above a native shear.
    Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
    Js 'app.redraw();' | Out-Null
    Js 'LS.shear(30, 0);' | Out-Null
    Js "LS.applyEffect('Adobe Transform', '$transform');" | Out-Null
    Js 'app.redraw();' | Out-Null
    $liveOverTransform = Js 'LS.vb(LS.named("subject"));'

    Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
    Js 'app.redraw();' | Out-Null
    Assert-Oracle (Js 'LS.nativeShearChecked("subject", 30, 0);') "$name"

    Js 'app.redraw(); LS.selectOnly(LS.named("subject"));' | Out-Null
    Js "LS.applyEffect('Adobe Transform', '$transform');" | Out-Null
    Js 'app.redraw();' | Out-Null
    $nativeOverTransform = Js 'LS.vb(LS.named("subject"));'
    Check "$name : Transform over Shear matches Transform over native" (Same $liveOverTransform $nativeOverTransform) "$liveOverTransform vs $nativeOverTransform"

    # 2. A live Shear above a Transform, against a native shear of the expanded
    #    Transform result.
    Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
    Js 'app.redraw();' | Out-Null
    Js "LS.applyEffect('Adobe Transform', '$transform');" | Out-Null
    Js 'LS.shear(30, 0);' | Out-Null
    Js 'app.redraw();' | Out-Null
    $shearOverTransform = Js 'LS.vb(LS.named("subject"));'

    Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
    Js 'app.redraw();' | Out-Null
    Js "LS.applyEffect('Adobe Transform', '$transform');" | Out-Null
    Js 'app.redraw();' | Out-Null
    Js 'app.executeMenuCommand("expandStyle");' | Out-Null
    Js 'app.executeMenuCommand("selectall"); LS.target = app.activeDocument.selection[0]; LS.target.name = "subject"; app.redraw();' | Out-Null
    Assert-Oracle (Js 'LS.nativeShearChecked("subject", 30, 0);') "$name"

    Js 'app.redraw();' | Out-Null
    $nativeOverExpanded = Js 'LS.vb(LS.named("subject"));'
    Check "$name : Shear over Transform matches native over expanded" (Same $shearOverTransform $nativeOverExpanded) "$shearOverTransform vs $nativeOverExpanded"

    Check "$name : the two stack orders differ" (-not (Same $liveOverTransform $shearOverTransform)) "both $liveOverTransform"

    # 3. Two Shear instances against two successive native shears.
    Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
    Js 'app.redraw();' | Out-Null
    Js 'LS.shear(30, 0);' | Out-Null
    Js 'LS.shear(-12, 90);' | Out-Null
    Js 'app.redraw();' | Out-Null
    $twoEffects = Js 'LS.vb(LS.named("subject"));'

    Js "LS.clear(); LS.target = LS.fixtures['$name'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
    Js 'app.redraw();' | Out-Null
    Assert-Oracle (Js 'LS.nativeShearChecked("subject", 30, 0);') "$name"

    Js 'app.redraw(); LS.selectOnly(LS.named("subject"));' | Out-Null
    Assert-Oracle (Js 'LS.nativeShearChecked("subject", -12, 90);') "$name"

    Js 'app.redraw();' | Out-Null
    $twoNative = Js 'LS.vb(LS.named("subject"));'
    Check "$name : two Shear effects match two native shears" (Same $twoEffects $twoNative) "$twoEffects vs $twoNative"
}

# 4. Independence, reordering, and deletion, on one fixture.
Note '--- two instances: independence, reorder, delete ---'
$script:group = 'two instances'
Js "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
Js 'app.redraw();' | Out-Null
Js 'LS.shear(30, 0);' | Out-Null
Js 'LS.shear(-12, 90);' | Out-Null
Js 'app.redraw();' | Out-Null
$appearance = Js 'LS.appearance();'
$instances = ([regex]::Matches($appearance, 'VulpesNexus Shear')).Count
Check 'two separate entries in the appearance' ($instances -eq 2) "found $instances"

# Changing the first must not disturb the second.
Js 'LS.send("set param", "0|shearAngle|real|5");' | Out-Null
Js 'app.redraw();' | Out-Null
$afterEdit = Js 'LS.appearance();'
$secondIntact = [bool]([regex]::IsMatch($afterEdit, 'axisAngle[^=]*=\s*90'))
Check 'editing one instance leaves the other alone' $secondIntact 'the second instance changed too'

# Reorder, many times, then check the result is back where it started.
Js 'LS.send("set param", "0|shearAngle|real|30");' | Out-Null
Js 'app.redraw();' | Out-Null
$beforeReorder = Js 'LS.vb(LS.named("subject"));'
$reorderErrors = 0
for ($i = 0; $i -lt 20; $i++) {
    if ((Js 'LS.send("move effect", "0,1");') -notmatch 'result 0') { $reorderErrors++ }
    if ((Js 'LS.send("move effect", "0,1");') -notmatch 'result 0') { $reorderErrors++ }
}
Js 'app.redraw();' | Out-Null
$afterReorder = Js 'LS.vb(LS.named("subject"));'
Check '40 reorders leave the result unchanged' (($reorderErrors -eq 0) -and (Same $beforeReorder $afterReorder)) "$reorderErrors errors, $beforeReorder vs $afterReorder"

# One swap must change the result, since the two shears do not commute.
Js 'LS.send("move effect", "0,1");' | Out-Null
Js 'app.redraw();' | Out-Null
$swapped = Js 'LS.vb(LS.named("subject"));'
Check 'swapping the two instances changes the result' (-not (Same $beforeReorder $swapped)) "both $swapped"

# Delete one; the other must still work.
Js 'LS.send("move effect", "0,1");' | Out-Null
Js 'LS.send("remove effect", "1");' | Out-Null
Js 'app.redraw();' | Out-Null
$afterDelete = Js 'LS.vb(LS.named("subject"));'
Js "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
Js 'app.redraw();' | Out-Null
Js 'LS.shear(30, 0);' | Out-Null
Js 'app.redraw();' | Out-Null
$onlyFirst = Js 'LS.vb(LS.named("subject"));'
Check 'deleting the second leaves the first intact' (Same $afterDelete $onlyFirst) "$afterDelete vs $onlyFirst"

# Deleting the last one must restore the original artwork exactly.
$original = Js "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.target.name = 'subject'; app.redraw(); LS.vb(LS.target);"
Js 'LS.selectOnly(LS.target); LS.shear(30, 0);' | Out-Null
Js 'app.redraw();' | Out-Null
Js 'LS.send("remove effect", "0");' | Out-Null
Js 'app.redraw();' | Out-Null
$restored = Js 'LS.vb(LS.named("subject"));'
Check 'deleting the only effect restores the artwork' (Same $original $restored) "$original vs $restored"

Note ''
Note ("{0} passed, {1} failed" -f $script:pass, $script:fail)
Js 'LS.clear();' | Out-Null
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
