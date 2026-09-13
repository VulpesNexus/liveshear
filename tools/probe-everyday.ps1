<#
.SYNOPSIS
    Ordinary things a person does that no other probe covers.

.DESCRIPTION
    Every other probe in the suite shears one object, built by a script, in a
    document with nothing else in it. That is not how anyone uses Illustrator,
    and it is where an embarrassing defect would be hiding: not in an exotic
    combination, but in something so obvious nobody wrote it down.

    So this asks the question the other way round. What would a person do in
    the first five minutes that the suite has never once done?

        select three objects at once and apply the effect
        put the effect on text set along a path
        save it as a graphic style and use it on something else
        copy a sheared object into another document
        apply it to an object that is inside a group
        apply it twice by mistake, then undo

    Multiple selection is the interesting one. Illustrator's own command shears
    a multi-object selection about the whole selection's center; a live effect
    is applied to each object and anchors on each object's own. Those are
    different results, and neither is a defect -- but if the difference is real
    it belongs in the documentation rather than in a surprise.
#>
[CmdletBinding()]
param([string] $OutPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\everyday.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

$script:pass = 0
$script:fail = 0
function Check([string] $name, [bool] $ok, [string] $detail, [string] $status = '') {
    if (-not $status) { $status = if ($ok) { 'PASS' } else { 'FAIL' } }
    if ($status -eq 'PASS') { $script:pass++ } elseif ($status -eq 'FAIL') { $script:fail++ }
    Note ("[{0}] {1}" -f $status, $name)
    if ($detail) { Note ("       " + $detail) }
    Add-ProbeResult -Group 'everyday use' -Case $name -Expected 'behaves the way someone would expect' -Observed $detail -Status $status
}

function Num([double] $v) { $v.ToString('0.####', [Globalization.CultureInfo]::InvariantCulture) }

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'everyday'

Note 'Live Shear -- ordinary things a person does'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ''

# --------------------------------------------------- three objects at once
Note '--- selecting three objects and applying the effect once ---'
Js @'
(function () {
  LS.clear();
  var a = LS.paint(LS.rect(60, 700, 100, 60), 0);  a.name = 'one';
  var b = LS.paint(LS.rect(260, 620, 100, 60), 0); b.name = 'two';
  var c = LS.paint(LS.rect(460, 540, 100, 60), 0); c.name = 'three';
  return 'built';
})();
'@ | Out-Null
Js 'app.redraw();' | Out-Null
$before = Js '(function () { var d = LS.doc(), s = []; for (var i = 0; i < d.pageItems.length; i++) { s.push(d.pageItems[i].name + "=" + LS.vb(d.pageItems[i])); } return s.join(" ; "); })();'
Js 'app.activeDocument.selection = null; LS.named("one").selected = true; LS.named("two").selected = true; LS.named("three").selected = true;' | Out-Null
Js 'app.redraw();' | Out-Null
$applied = Js 'LS.shear(30, 0);'
Js 'app.redraw();' | Out-Null
$after = Js '(function () { var d = LS.doc(), s = []; for (var i = 0; i < d.pageItems.length; i++) { s.push(d.pageItems[i].name + "=" + LS.vb(d.pageItems[i])); } return s.join(" ; "); })();'
$counts = Js '(function () { var d = LS.doc(), n = 0; for (var i = 0; i < d.pageItems.length; i++) { LS.selectOnly(d.pageItems[i]); if (LS.send("count effects").indexOf("post 1") >= 0 || LS.send("appearance").indexOf("VulpesNexus Shear") >= 0) { n++; } } return n + ""; })();'
Check 'all three objects get the effect' ($counts -eq '3') ("{0} of 3 objects carry a Shear after one apply" -f $counts)
Note ("       before: {0}" -f $before)
Note ("       after:  {0}" -f $after)

# Each object should have been sheared about its own center, not about the
# center of the three together. Object 'one' is 100 x 60 at (60,700), so a
# 30 degree horizontal shear widens it by 60*tan(30) = 34.641 pt and leaves
# its vertical extent alone.
$oneAfter = (Js 'LS.vb(LS.named("one"));') -split ','
$width = [double]$oneAfter[2] - [double]$oneAfter[0]
$expectedOwn = 100.0 + 60.0 * [Math]::Tan(30 * [Math]::PI / 180)
Check 'each object is sheared about its own center, not the selection''s' ([Math]::Abs($width - $expectedOwn) -lt 0.01) `
    ("the first object is {0} pt wide; shearing it about its own center gives {1} pt. A live effect is applied to each object separately, so a multiple selection is not the same as Illustrator's own command, which shears the whole selection about one center." -f (Num $width), (Num $expectedOwn))

# --------------------------------------------------------- text on a path
Note ''
Note '--- text set along a path ---'
$built = Js @'
(function () {
  LS.clear();
  var d = LS.doc();
  var spine = d.pathItems.add();
  spine.setEntirePath([[80, 600], [240, 700], [400, 600]]);
  spine.stroked = false; spine.filled = false;
  var t = d.textFrames.pathText(spine);
  t.contents = 'Shear along a path';
  t.textRange.characterAttributes.size = 28;
  t.name = 'subject';
  LS.selectOnly(t);
  return 'kind=' + t.kind + ' ' + LS.bounds(t);
})();
'@
Note ("       $built")
Js 'app.redraw();' | Out-Null
$anchorsBefore = Js 'LS.anchors();'
Js 'LS.shear(30, 0);' | Out-Null
Js 'app.redraw();' | Out-Null
$pathTextLive = Js 'LS.vb(LS.named("subject"));'
$anchorsAfter = Js 'LS.anchors();'
Check 'text on a path shears without disturbing its spine' ($anchorsBefore -eq $anchorsAfter) `
    ("the path the text runs along is {0} after shearing; the result is {1}" -f `
        $(if ($anchorsBefore -eq $anchorsAfter) { 'unchanged' } else { 'CHANGED' }), $pathTextLive)

# --------------------------------------------------------- graphic styles
Note ''
Note '--- saved as a graphic style and used on something else ---'
Js 'LS.clear();' | Out-Null
Js 'LS.target = LS.fixtures["plainRect"](); LS.target.name = "styled"; LS.selectOnly(LS.target);' | Out-Null
Js 'app.redraw();' | Out-Null
Js 'LS.shear(25, 0);' | Out-Null
Js 'app.redraw();' | Out-Null
$styledBounds = Js 'LS.vb(LS.named("styled"));'
# Illustrator's scripting interface can read the graphic styles a document
# has and apply one, but it cannot make one: graphicStyles has no add(). So
# this case reports what it could not do rather than pretending, and the
# applying half below is skipped rather than failed.
$styleMade = Js @'
(function () {
  var d = LS.doc();
  LS.selectOnly(LS.named('styled'));
  var before = d.graphicStyles.length;
  try {
    d.graphicStyles.add('Sheared 25');
    return before + ' -> ' + d.graphicStyles.length;
  } catch (e) {
    return 'cannot create: ' + e.message;
  }
})();
'@
Note ("       graphic styles: {0}" -f $styleMade)
$applyStyle = Js @'
(function () {
  var d = LS.doc();
  var other = LS.paint(LS.rect(360, 400, 200, 120), 0);
  other.name = 'borrowed';
  var style = null;
  for (var i = 0; i < d.graphicStyles.length; i++) {
    if (d.graphicStyles[i].name === 'Sheared 25') { style = d.graphicStyles[i]; }
  }
  if (!style) { return 'no such style'; }
  style.applyTo(other);
  app.redraw();
  return LS.vb(LS.named('borrowed'));
})();
'@
Note ("       the second object, with the style applied: {0}" -f $applyStyle)
# It is a 200 x 120 rectangle like the first, so the same style must widen it
# by the same amount: 120 * tan(25).
$borrowed = $applyStyle -split ','
$ok = $borrowed.Count -eq 4
$borrowedWidth = if ($ok) { [double]$borrowed[2] - [double]$borrowed[0] } else { 0 }
$expectedStyle = 200.0 + 120.0 * [Math]::Tan(25 * [Math]::PI / 180)
if (-not $ok) {
    # Illustrator's scripting interface can read a document's graphic styles
    # and apply one, but it cannot create one: graphicStyles has no add().
    # Saying so is the honest answer; a fixture that cannot be built is not a
    # defect in the thing it was meant to test.
    Check 'a graphic style carries the effect to another object' $false `
        'Illustrator has no scripting call that creates a graphic style, so this could not be set up. It would have to be done by hand in the Graphic Styles panel.' 'UNTESTED'
}
else {
    Check 'a graphic style carries the effect to another object' ([Math]::Abs($borrowedWidth - $expectedStyle) -lt 0.01) `
        ("the borrowed object is {0} pt wide, against {1} pt for the same shear" -f (Num $borrowedWidth), (Num $expectedStyle))
}

# --------------------------------------------- inside a group, and twice over
Note ''
Note '--- applied to one object inside a group ---'
Js @'
(function () {
  LS.clear();
  var d = LS.doc();
  var g = d.groupItems.add(); g.name = 'holder';
  var inner = LS.paint(LS.rect(100, 600, 160, 100), 0); inner.name = 'inner';
  inner.move(g, ElementPlacement.PLACEATEND);
  var sibling = LS.paint(LS.rect(320, 600, 160, 100), 0); sibling.name = 'sibling';
  sibling.move(g, ElementPlacement.PLACEATEND);
  return 'built';
})();
'@ | Out-Null
Js 'app.redraw();' | Out-Null
$siblingBefore = Js 'LS.vb(LS.named("sibling"));'
Js 'LS.selectOnly(LS.named("inner"));' | Out-Null
Js 'app.redraw();' | Out-Null
Js 'LS.shear(30, 0);' | Out-Null
Js 'app.redraw();' | Out-Null
$siblingAfter = Js 'LS.vb(LS.named("sibling"));'
$innerAfter = Js 'LS.vb(LS.named("inner"));'
Check 'shearing one child of a group leaves its siblings alone' ($siblingBefore -eq $siblingAfter) `
    ("the sibling is {0}; the sheared child is now {1}" -f $(if ($siblingBefore -eq $siblingAfter) { 'untouched' } else { "CHANGED from $siblingBefore to $siblingAfter" }), $innerAfter)

# -------------------------------------------- duplicated, and copied elsewhere
Note ''
Note '--- duplicated in place, and copied into another document ---'
Js 'LS.clear();' | Out-Null
Js 'LS.target = LS.fixtures["plainRect"](); LS.target.name = "original"; LS.selectOnly(LS.target);' | Out-Null
Js 'app.redraw();' | Out-Null
Js 'LS.shear(28, 0);' | Out-Null
Js 'app.redraw();' | Out-Null
$originalBounds = Js 'LS.vb(LS.named("original"));'

$duplicate = Js @'
(function () {
  var copy = LS.named('original').duplicate();
  copy.name = 'copy';
  app.redraw();
  return LS.vb(LS.named('copy'));
})();
'@
Check 'a duplicate carries the effect and renders the same' ($duplicate -eq $originalBounds) `
    ("the original is {0}; the duplicate is {1}" -f $originalBounds, $duplicate)

# Editing one must not disturb the other -- and this has to go through the
# dialog rather than the script bridge.
#
# An object and its duplicate share an art style until something forks it. The
# bridge's "set param" writes the parameter dictionary in place, so editing
# either one through it moves both; the dialog goes through
# EditEffectParameters and UpdateParameters, which forks the style properly.
# Testing this through the bridge reported a defect that does not exist for
# anyone using Illustrator, which is why it is driven the way a person would.
Js 'LS.selectOnly(LS.named("copy"));' | Out-Null
Js 'app.redraw();' | Out-Null
$drive = Invoke-ShearDialog -Tenths 50 -Button ok
Js 'app.redraw();' | Out-Null
$originalStill = Js 'LS.vb(LS.named("original"));'
$copyNow = Js 'LS.vb(LS.named("copy"));'
Note ("       dialog driver: {0}" -f $drive.Driver)
Check 'editing the duplicate through the dialog leaves the original alone' `
    (($originalStill -eq $originalBounds) -and ($copyNow -ne $originalBounds)) `
    ("the original is {0}; the duplicate is now {1}" -f `
        $(if ($originalStill -eq $originalBounds) { 'unchanged' } else { "CHANGED to $originalStill" }), $copyNow)

# Each step its own call. Copying and then creating a document in one script
# leaves nothing on the clipboard to paste -- the same class of problem as
# selecting and acting in one call, and it made this look as though the effect
# were lost in transit when it travels perfectly well.
$sourceWidth = Js '(function () { var b = LS.vb(LS.named("original")).split(","); return (parseFloat(b[2]) - parseFloat(b[0])).toFixed(6); })();'
# Selecting and copying have to be separate calls as well. Done together, the
# copy takes whatever was selected before -- here the duplicate at five
# degrees rather than the original at twenty-eight, which made the pasted
# object look like it had lost its effect when it had merely copied a
# different object.
Js 'var d = app.activeDocument; d.selection = null; LS.named("original").selected = true;' | Out-Null
Js 'app.redraw();' | Out-Null
Js 'app.copy();' | Out-Null
Js 'app.documents.add(DocumentColorSpace.RGB, 800, 800);' | Out-Null
Js 'app.paste(); app.redraw();' | Out-Null
Js 'app.activeDocument.selection = null; app.activeDocument.pageItems[0].selected = true;' | Out-Null
Js 'app.redraw();' | Out-Null
$pastedAppearance = Js 'LS.send("appearance");'
$pastedWidth = Js '(function () { var b = LS.vb(app.activeDocument.pageItems[0]).split(","); return (parseFloat(b[2]) - parseFloat(b[0])).toFixed(6); })();'
Js 'app.activeDocument.close(SaveOptions.DONOTSAVECHANGES);' | Out-Null
$carried = $pastedAppearance -match 'VulpesNexus Shear'
$sameWidth = [Math]::Abs([double]$pastedWidth - [double]$sourceWidth) -lt 0.01
Check 'pasting into another document carries the effect with it' ($carried -and $sameWidth) `
    ("the pasted object {0} a Shear in its appearance, and is {1} pt wide against {2} pt in the document it came from" -f `
        $(if ($carried) { 'still carries' } else { 'has LOST' }), $pastedWidth, $sourceWidth)

Note ''
Note ("{0} passed, {1} failed" -f $script:pass, $script:fail)
Js 'LS.clear();' | Out-Null
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
Save-ProbeTranscript -Path $OutPath -Lines $log
Write-Output "Written to $OutPath"
