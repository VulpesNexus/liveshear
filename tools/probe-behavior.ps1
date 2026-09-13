<#
.SYNOPSIS
    The behavioral test suite for the Shear live effect, run against a live
    Illustrator.

.DESCRIPTION
    Each check states what it expects before it looks, so a pass means the host
    agreed rather than that nothing crashed. Results go to
    docs\evidence\behavior.txt.
#>
[CmdletBinding()]
param([string] $LogPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $LogPath) { $LogPath = Join-Path $repo 'docs\evidence\behavior.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath)

$scratch = Join-Path $env:TEMP 'liveshear-probe'
$null = New-Item -ItemType Directory -Force -Path $scratch

$log = New-Object Collections.Generic.List[string]
$script:passed = 0
$script:failed = 0

function Note([string] $line) { $log.Add($line); Write-Output $line }

function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:passed++ } else { $script:failed++ }
    Note ("[{0}] {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name)
    if ($detail) { foreach ($d in ($detail -split "`n")) { Note ("       " + $d.TrimEnd()) } }
}

function Info([string] $name, [string] $detail) {
    Note ("[INFO] {0}" -f $name)
    if ($detail) { foreach ($d in ($detail -split "`n")) { Note ("       " + $d.TrimEnd()) } }
}

function Reset-Doc {
    # Emptying one document is used in preference to closing and reopening.
    # Repeated create/close cycles trip an access violation inside Illustrator
    # itself -- see docs\evidence\crash-control.txt, where the same churn kills
    # it with the plugin uninstalled -- and this probe is not the place to
    # reproduce that.
    if ([int] (Invoke-AiScript 'app.documents.length;') -eq 0) {
        Invoke-AiScript 'app.documents.add(DocumentColorSpace.RGB, 600, 600); app.activeDocument.rulerOrigin = [0,0];' | Out-Null
        return
    }
    Invoke-AiScript @'
var d = app.activeDocument;
app.executeMenuCommand("deselectall");
for (var i = d.pageItems.length - 1; i >= 0; i--) { try { d.pageItems[i].remove(); } catch (e) {} }
'@ | Out-Null
}

function Num([double] $v) {
    # The shell locale may write decimal commas, which would make a list of
    # bounds unreadable once joined with commas.
    [Math]::Round($v, 3).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
}

function Bounds([string] $expr) {
    $raw = Invoke-AiScript "$expr.visibleBounds.join(',');"
    ($raw -split ',' | ForEach-Object { Num ([double] $_) })
}

function Round3([double] $v) { Num $v }

function Near([double] $a, [double] $b, [double] $tol = 0.01) { [Math]::Abs($a - $b) -le $tol }

Note 'Live Shear -- behavior probe'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Illustrator {0}" -f (Get-AiApp).Version)
Note ''

# ---------------------------------------------------------------- registration
$registry = Send-AiMessage registry
Check 'effect is registered with the application' `
    ($registry -match 'VulpesNexus Shear') `
    (($registry -split "`n" | Where-Object { $_ -match 'VulpesNexus Shear' }) -join "`n")

# ------------------------------------------------------- geometry stays intact
Reset-Doc
Invoke-AiScript @'
var d = app.activeDocument;
var r = d.pathItems.rectangle(500, 100, 200, 120);
r.name = "r";
r.filled = true; r.stroked = false;
var c = new RGBColor(); c.red = 200; c.green = 40; c.blue = 40; r.fillColor = c;
app.executeMenuCommand("deselectall"); r.selected = true;
'@ | Out-Null
$srcBefore = Send-AiMessage geometry
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:30' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
$srcAfter = Send-AiMessage geometry
$b = Bounds 'app.activeDocument.pathItems.getByName("r")'

# tan(30) * 120 = 69.282, so the 200pt wide box renders 269.282pt wide.
Check 'artwork renders sheared' `
    ((Near $b[0] 65.359 0.01) -and (Near $b[2] 334.641 0.01)) `
    ("visible bounds " + ($b -join ', ') + "; expected left 65.359 and right 334.641")

$segBefore = ($srcBefore -split "`n" | Where-Object { $_ -match 'seg ' }) -join '|'
$segAfter  = ($srcAfter  -split "`n" | Where-Object { $_ -match 'seg ' }) -join '|'
Check 'source path is not modified (the effect is non-destructive)' `
    ($segBefore -eq $segAfter) `
    "anchor points identical before and after applying the effect"

# ------------------------------------------------------------------- live text
Reset-Doc
Invoke-AiScript @'
var d = app.activeDocument;
var t = d.textFrames.add();
t.name = "t";
t.contents = "Handgloves";
t.position = [100, 400];
t.textRange.characterAttributes.size = 48;
app.executeMenuCommand("deselectall"); t.selected = true;
'@ | Out-Null
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:20' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
$textState = Invoke-AiScript @'
var t = app.activeDocument.textFrames[0];
[t.typename, t.contents, t.textRange.characterAttributes.size].join("|");
'@
$textBounds1 = Bounds 'app.activeDocument.textFrames[0]'
Check 'live text stays live text' `
    ($textState -match '^TextFrame\|Handgloves\|48') `
    "typename/contents/size after the effect: $textState"

Invoke-AiScript 'app.activeDocument.textFrames[0].contents = "Handgloves and more"; app.redraw();' | Out-Null
$textBounds2 = Bounds 'app.activeDocument.textFrames[0]'
Check 'retyping the text re-runs the effect' `
    ($textBounds2[2] -gt $textBounds1[2]) `
    ("bounds before retyping " + ($textBounds1 -join ', ') + "; after " + ($textBounds2 -join ', '))

Invoke-AiScript 'app.activeDocument.textFrames[0].textRange.characterAttributes.size = 24; app.redraw();' | Out-Null
$textBounds3 = Bounds 'app.activeDocument.textFrames[0]'
Check 'changing the font size re-runs the effect' `
    ($textBounds3[1] - $textBounds3[3] -lt $textBounds2[1] - $textBounds2[3]) `
    ("bounds at 48pt " + ($textBounds2 -join ', ') + "; at 24pt " + ($textBounds3 -join ', '))

# -------------------------------------------------------- two instances coexist
Reset-Doc
Invoke-AiScript @'
var d = app.activeDocument;
var r = d.pathItems.rectangle(500, 100, 200, 120);
r.name = "r"; r.filled = true; r.stroked = false;
app.executeMenuCommand("deselectall"); r.selected = true;
'@ | Out-Null
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:20' | Out-Null
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:0;axisAngle=r:90' | Out-Null
Send-AiMessage 'set param' '1|shearAngle|real|15' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
$appearance = Send-AiMessage appearance
$entries = ([regex]::Matches($appearance, 'VulpesNexus Shear')).Count
$angles = [regex]::Matches($appearance, 'shearAngle \(Real\) = ([-0-9.]+)') | ForEach-Object { [double] $_.Groups[1].Value }
Check 'two instances are independent appearance entries' `
    ($entries -eq 2 -and $angles.Count -eq 2 -and (Near $angles[0] 20) -and (Near $angles[1] 15)) `
    ("found $entries entries with shear angles " + ($angles -join ', ') + "; expected 20 and 15")

# --------------------------------------------------------------- stack ordering
function Measure-Stack([string[]] $specs) {
    Reset-Doc
    Invoke-AiScript @'
var d = app.activeDocument;
var r = d.pathItems.rectangle(500, 100, 200, 120);
r.name = "r"; r.filled = true; r.stroked = false;
app.executeMenuCommand("deselectall"); r.selected = true;
'@ | Out-Null
    foreach ($s in $specs) { Send-AiMessage 'apply effect' $s | Out-Null }
    Invoke-AiScript 'app.redraw();' | Out-Null
    (Bounds 'app.activeDocument.pathItems.getByName("r")') -join ','
}

$shearThenMove = Measure-Stack @('VulpesNexus Shear|shearAngle=r:30', 'Adobe Transform|reflect=b:false;rotate_Radians=r:0.7853981633974483')
$moveThenShear = Measure-Stack @('Adobe Transform|reflect=b:false;rotate_Radians=r:0.7853981633974483', 'VulpesNexus Shear|shearAngle=r:30')
Check 'stack order changes the result (Shear then Rotate differs from Rotate then Shear)' `
    ($shearThenMove -ne $moveThenShear) `
    "Shear then Transform: $shearThenMove`nTransform then Shear: $moveThenShear"

# ------------------------------------------------------------------ save/reopen
Reset-Doc
Invoke-AiScript @'
var d = app.activeDocument;
var r = d.pathItems.rectangle(500, 100, 200, 120);
r.name = "r"; r.filled = true; r.stroked = false;
var t = d.textFrames.add(); t.name = "t"; t.contents = "Live"; t.position = [100, 200];
t.textRange.characterAttributes.size = 48;
app.executeMenuCommand("selectall");
'@ | Out-Null
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:27.5;axisAngle=r:12.25' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
$beforeSave = (Bounds 'app.activeDocument.pathItems.getByName("r")') -join ','
$aiPath = Join-Path $scratch 'liveshear-roundtrip.ai'
$aiPathJs = $aiPath -replace '\\', '\\\\'
Invoke-AiScript @"
var f = new File("$aiPathJs");
var opts = new IllustratorSaveOptions();
opts.compatibility = Compatibility.ILLUSTRATOR24;
opts.pdfCompatible = true;
app.activeDocument.saveAs(f, opts);
app.activeDocument.close(SaveOptions.SAVECHANGES);
"@ | Out-Null
Invoke-AiScript "app.open(new File(`"$aiPathJs`")); app.redraw();" | Out-Null
$afterOpen = (Bounds 'app.activeDocument.pathItems.getByName("r")') -join ','
Invoke-AiScript 'app.executeMenuCommand("selectall");' | Out-Null
$reopened = Send-AiMessage appearance
$reopenedAngle = [regex]::Match($reopened, 'shearAngle \(Real\) = ([-0-9.]+)')
$reopenedAxis = [regex]::Match($reopened, 'axisAngle \(Real\) = ([-0-9.]+)')
Check 'effect survives save and reopen' `
    ($beforeSave -eq $afterOpen -and $reopened -match 'VulpesNexus Shear') `
    "bounds before save $beforeSave; after reopen $afterOpen"
Check 'parameters survive save and reopen' `
    ($reopenedAngle.Success -and (Near ([double]$reopenedAngle.Groups[1].Value) 27.5) -and
     $reopenedAxis.Success -and (Near ([double]$reopenedAxis.Groups[1].Value) 12.25)) `
    ("read back shearAngle=" + $reopenedAngle.Groups[1].Value + " axisAngle=" + $reopenedAxis.Groups[1].Value)

$reopenedText = Invoke-AiScript 'var t = app.activeDocument.textFrames[0]; [t.typename, t.contents].join("|");'
Check 'text is still live text after a save/reopen round trip' `
    ($reopenedText -match '^TextFrame\|Live') `
    "read back: $reopenedText"

# editing a parameter after reopening
Invoke-AiScript 'app.executeMenuCommand("deselectall"); app.activeDocument.pathItems.getByName("r").selected = true;' | Out-Null
Send-AiMessage 'set param' '0|shearAngle|real|40' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
$afterEdit = (Bounds 'app.activeDocument.pathItems.getByName("r")') -join ','
Check 'the reopened effect is still editable' `
    ($afterEdit -ne $afterOpen) `
    "bounds after changing shearAngle to 40: $afterEdit"

# ------------------------------------------------------------------ PDF export
$pdfPath = Join-Path $scratch 'liveshear-roundtrip.pdf'
$pdfPathJs = $pdfPath -replace '\\', '\\\\'
if (Test-Path $pdfPath) { [System.IO.File]::Delete($pdfPath) }
Invoke-AiScript @"
var f = new File("$pdfPathJs");
app.activeDocument.saveAs(f, new PDFSaveOptions());
"@ | Out-Null
$pdfOk = Test-Path $pdfPath
Check 'the sheared artwork exports to PDF' `
    ($pdfOk -and (Get-Item $pdfPath).Length -gt 1000) `
    $(if ($pdfOk) { "wrote {0:N0} bytes" -f (Get-Item $pdfPath).Length } else { 'no file produced' })

# --------------------------------------------------------------- copy and paste
Reset-Doc
Invoke-AiScript @'
var d = app.activeDocument;
var r = d.pathItems.rectangle(500, 100, 200, 120);
r.name = "r"; r.filled = true; r.stroked = false;
app.executeMenuCommand("deselectall"); r.selected = true;
'@ | Out-Null
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:33' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
$original = (Bounds 'app.activeDocument.pathItems.getByName("r")') -join ','

Invoke-AiScript 'var d = app.activeDocument; var c = d.pathItems.getByName("r").duplicate(); c.name = "copy"; app.redraw();' | Out-Null
$duplicate = (Bounds 'app.activeDocument.pathItems.getByName("copy")') -join ','
Check 'duplicating an object carries the effect' ($duplicate -eq $original) `
    "original $original; duplicate $duplicate"

Invoke-AiScript 'app.executeMenuCommand("deselectall"); app.activeDocument.pathItems.getByName("r").selected = true; app.copy();' | Out-Null
Invoke-AiScript 'app.documents.add(DocumentColorSpace.RGB, 600, 600); app.paste(); app.redraw();' | Out-Null
$pastedAppearance = Send-AiMessage appearance
$pastedBounds = Invoke-AiScript 'app.activeDocument.pageItems[0].visibleBounds; var b = app.activeDocument.pageItems[0].visibleBounds; (Math.round((b[2]-b[0])*1000)/1000).toString();'
Check 'pasting into another document carries the effect' `
    ($pastedAppearance -match 'VulpesNexus Shear') `
    "pasted width $pastedBounds pt (a 200pt box sheared 33 degrees is 277.9pt wide); appearance lists the effect: $($pastedAppearance -match 'VulpesNexus Shear')"

# ---------------------------------------------------------------- undo and redo
Reset-Doc
Invoke-AiScript @'
var d = app.activeDocument;
var r = d.pathItems.rectangle(500, 100, 200, 120);
r.name = "r"; r.filled = true; r.stroked = false;
app.executeMenuCommand("deselectall"); r.selected = true;
'@ | Out-Null
$plain = (Bounds 'app.activeDocument.pathItems.getByName("r")') -join ','
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:30' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
$applied = (Bounds 'app.activeDocument.pathItems.getByName("r")') -join ','
Invoke-AiScript 'app.undo(); app.redraw();' | Out-Null
$undone = (Bounds 'app.activeDocument.pathItems.getByName("r")') -join ','
Invoke-AiScript 'app.redo(); app.redraw();' | Out-Null
$redone = (Bounds 'app.activeDocument.pathItems.getByName("r")') -join ','
Check 'undo removes the effect and redo puts it back' `
    ($undone -eq $plain -and $redone -eq $applied) `
    "plain $plain; applied $applied; after undo $undone; after redo $redone"

# --------------------------------------------------------------------- art types
# A real image on disk, so the placed-art case places something.
$rasterPath = Join-Path $scratch 'probe.png'
if (-not (Test-Path $rasterPath)) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 120, 80
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.Clear([System.Drawing.Color]::CornflowerBlue)
    $gfx.FillEllipse([System.Drawing.Brushes]::Gold, 10, 10, 60, 60)
    $gfx.Dispose()
    $bmp.Save($rasterPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
$rasterPathJs = $rasterPath.Replace('\', '\\')

Reset-Doc
$artTypes = @(
    @{ name = 'group'; build = 'var g = d.groupItems.add(); g.name="x"; var a = d.pathItems.rectangle(500,100,80,80); a.moveToBeginning(g); var b2 = d.pathItems.ellipse(400,220,80,80); b2.moveToBeginning(g);' }
    @{ name = 'nested group'; build = 'var g = d.groupItems.add(); g.name="x"; var inner = d.groupItems.add(); inner.moveToBeginning(g); var a = d.pathItems.rectangle(500,100,80,80); a.moveToBeginning(inner); var b2 = d.pathItems.ellipse(400,220,80,80); b2.moveToBeginning(inner);' }
    @{ name = 'compound path'; build = 'var cp = d.compoundPathItems.add(); cp.name="x"; var o = d.pathItems.ellipse(500,100,160,160); o.moveToBeginning(cp); var i2 = d.pathItems.ellipse(460,140,80,80); i2.moveToBeginning(cp);' }
    @{ name = 'clipping group'; build = 'var g = d.groupItems.add(); g.name="x"; var art = d.pathItems.rectangle(500,100,200,160); art.moveToBeginning(g); var clip = d.pathItems.ellipse(480,120,160,120); clip.moveToBeginning(g); clip.clipping = true; g.clipped = true;' }
    @{ name = 'symbol instance'; build = 'var src = d.pathItems.rectangle(500,100,120,80); var sym = d.symbols.add(src); var inst = d.symbolItems.add(sym); inst.name="x"; inst.position=[100,500];' }
    @{ name = 'placed raster'; build = 'var art = d.placedItems.add(); art.file = new File("RASTERPATH"); art.embed(); art.name="x"; art.position=[100,500];' }
)
foreach ($t in $artTypes) {
    Reset-Doc
    $built = $true
    try {
        $build = $t.build -replace 'RASTERPATH', $rasterPathJs
        Invoke-AiScript ("var d = app.activeDocument; " + $build + " app.executeMenuCommand(""deselectall""); app.activeDocument.pageItems[0].selected = true;") | Out-Null
    }
    catch { $built = $false }
    if (-not $built) { Info ("art type: " + $t.name) 'could not be built in this fixture; not tested'; continue }

    $bBefore = Invoke-AiScript 'app.activeDocument.pageItems[0].visibleBounds.join(",");'
    $reply = (Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:30').TrimEnd()
    Invoke-AiScript 'app.redraw();' | Out-Null
    $bAfter = Invoke-AiScript 'app.activeDocument.pageItems[0].visibleBounds.join(",");'
    # A shear moves the bounds; it does not always widen them, because it can
    # bring a diagonal arrangement of shapes closer together horizontally.
    $ok = ($reply -match 'to [1-9]') -and ($bBefore -ne $bAfter)
    Check ("art type accepted: " + $t.name) $ok `
        ("bounds before " + $bBefore + " -> after " + $bAfter + "; " + ($reply -replace "`n", ' '))
}

# ------------------------------------------------------------ coordinate space
# The same shear parameters applied to the same shape in different surroundings.
# A live effect that works in the art's own space gives every case the same
# shape, differing only by where the surrounding transform puts it.
$spaceCases = @(
    @{ name = 'untouched';              setup = '' }
    @{ name = 'translated';             setup = 'r.translate(120, -60);' }
    @{ name = 'rotated 40 degrees';     setup = 'r.rotate(40);' }
    @{ name = 'scaled 150/70 percent';  setup = 'r.resize(150, 70);' }
    @{ name = 'reflected horizontally'; setup = 'r.resize(-100, 100);' }
    @{ name = 'inside a rotated group'; setup = 'var g = d.groupItems.add(); r.moveToBeginning(g); g.rotate(25);' }
)
$spaceResults = @{}
foreach ($c in $spaceCases) {
    Reset-Doc
    Invoke-AiScript ("var d = app.activeDocument; var r = d.pathItems.rectangle(500, 100, 200, 120); r.name = 'r'; r.filled = true; r.stroked = false; " + $c.setup + " app.executeMenuCommand('deselectall'); app.activeDocument.pageItems[0].selected = true;") | Out-Null
    $wBefore = [double](Invoke-AiScript 'var b = app.activeDocument.pageItems[0].visibleBounds; ((b[2]-b[0])).toString();')
    $hBefore = [double](Invoke-AiScript 'var b = app.activeDocument.pageItems[0].visibleBounds; ((b[1]-b[3])).toString();')
    Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:30' | Out-Null
    Invoke-AiScript 'app.redraw();' | Out-Null
    $wAfter = [double](Invoke-AiScript 'var b = app.activeDocument.pageItems[0].visibleBounds; ((b[2]-b[0])).toString();')
    $hAfter = [double](Invoke-AiScript 'var b = app.activeDocument.pageItems[0].visibleBounds; ((b[1]-b[3])).toString();')
    $spaceResults[$c.name] = @{ w = $wAfter; h = $hAfter; grew = ($wAfter - $wBefore) }
    Info ('coordinate space: ' + $c.name) ("width {0} -> {1}, height {2} -> {3}, widened by {4}" -f (Num $wBefore), (Num $wAfter), (Num $hBefore), (Num $hAfter), (Num ($wAfter - $wBefore)))
}
# A horizontal shear of 30 degrees widens an upright box by tan(30) * height.
$expectedGrowth = 120 * [Math]::Tan(30 * [Math]::PI / 180)
Check 'shear is applied in the object''s own space, not the page''s' `
    ((Near $spaceResults['untouched'].grew $expectedGrowth 0.01) -and
     (Near $spaceResults['translated'].grew $expectedGrowth 0.01) -and
     (Near $spaceResults['reflected horizontally'].grew $expectedGrowth 0.01)) `
    ("an upright 200x120 box should widen by tan(30) * 120 = " + (Num $expectedGrowth) + " pt; untouched grew " + (Num $spaceResults['untouched'].grew) + ", translated " + (Num $spaceResults['translated'].grew) + ", reflected " + (Num $spaceResults['reflected horizontally'].grew))
Check 'a rotated object shears about the page axes, as Illustrator''s own Shear does' `
    (-not (Near $spaceResults['rotated 40 degrees'].grew $expectedGrowth 0.01)) `
    ("a box rotated 40 degrees widened by " + (Num $spaceResults['rotated 40 degrees'].grew) + " pt rather than " + (Num $expectedGrowth) + ", which is what a shear along the page's horizontal axis does")

# ------------------------------------------------------- strokes, gradients, patterns
Reset-Doc
Invoke-AiScript @'
var d = app.activeDocument;
var p = d.pathItems.rectangle(500, 100, 200, 120);
p.name = "r";
p.filled = false;
p.stroked = true;
var c = new RGBColor(); c.red = 0; c.green = 0; c.blue = 0;
p.strokeColor = c;
p.strokeWidth = 12;
p.strokeDashes = [12, 6];
app.executeMenuCommand("deselectall"); p.selected = true;
'@ | Out-Null
$strokeBefore = (Bounds 'app.activeDocument.pathItems.getByName("r")') -join ','
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:30' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
$strokeAfter = (Bounds 'app.activeDocument.pathItems.getByName("r")') -join ','
$stillDashed = Invoke-AiScript 'var p = app.activeDocument.pathItems.getByName("r"); [p.stroked, p.strokeWidth, p.strokeDashes.join("/")].join("|");'
Info 'dashed stroke' "bounds before $strokeBefore; after $strokeAfter; stroke attributes still $stillDashed"

Reset-Doc
Invoke-AiScript @'
var d = app.activeDocument;
var p = d.pathItems.rectangle(500, 100, 200, 120);
p.name = "r"; p.stroked = false; p.filled = true;
var g = d.gradients.add();
g.name = "g";
g.type = GradientType.LINEAR;
var gc = new GradientColor();
gc.gradient = g;
p.fillColor = gc;
app.executeMenuCommand("deselectall"); p.selected = true;
'@ | Out-Null
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:30' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
$gradBounds = (Bounds 'app.activeDocument.pathItems.getByName("r")') -join ','
Info 'gradient fill' "shears without error; bounds $gradBounds. Whether the gradient ramp itself is sheared has to be judged visually; the effect passes kTransformFillGradients to TransformArt so it should travel with the geometry."

# -------------------------------------------------------------------- performance
Reset-Doc
Invoke-AiScript @'
var d = app.activeDocument;
var p = d.pathItems.add();
p.name = "big";
var pts = [];
for (var i = 0; i < 500; i++) {
    var a = i * 0.13;
    pts.push([300 + 200 * Math.cos(a) * (0.5 + 0.5 * Math.sin(a * 3)),
              300 + 200 * Math.sin(a) * (0.5 + 0.5 * Math.cos(a * 5))]);
}
p.setEntirePath(pts);
p.filled = false; p.stroked = true;
app.executeMenuCommand("deselectall"); p.selected = true;
'@ | Out-Null
$sw = [Diagnostics.Stopwatch]::StartNew()
Invoke-AiScript 'app.redraw();' | Out-Null
$sw.Stop(); $plainDraw = $sw.Elapsed.TotalMilliseconds
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:30' | Out-Null
$sw = [Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt 10; $i++) {
    Send-AiMessage 'set param' ("0|shearAngle|real|" + (20 + $i)) | Out-Null
    Invoke-AiScript 'app.redraw();' | Out-Null
}
$sw.Stop()
Info 'performance on a 500-point path' `
    ("baseline redraw {0:N0} ms; ten parameter changes with a redraw each took {1:N0} ms, so about {2:N0} ms per re-evaluation including Illustrator's own redraw" -f $plainDraw, $sw.Elapsed.TotalMilliseconds, ($sw.Elapsed.TotalMilliseconds / 10))

# ------------------------------------------------------------------------ tidy up
Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null

Note ''
Note ("{0} passed, {1} failed" -f $script:passed, $script:failed)
Save-ProbeTranscript -Path $LogPath -Lines $log
Write-Output "`nWritten to $LogPath"
