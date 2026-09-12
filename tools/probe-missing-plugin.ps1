<#
.SYNOPSIS
    Answers what happens to a document containing the Shear effect when it is
    opened on a machine that does not have the plug-in.

.DESCRIPTION
    Runs in three phases, uninstalling and reinstalling the plug-in and
    restarting Illustrator between them:

      1. with the plug-in:    build and save the documents
      2. without the plug-in: open them, look at what survived, edit, re-save
      3. with the plug-in:    reopen both the original and the file that was
                              re-saved while the plug-in was missing

    Phase 2 cannot use the plug-in's own appearance dump, for obvious reasons,
    so it reads what the scripting DOM can see: whether the artwork still
    renders sheared, whether the source geometry is still unsheared (which is
    only true if a live effect is still doing the work), and whether text is
    still text.

    Results go to docs\evidence\missing-plugin.txt.
#>
[CmdletBinding()]
param([string] $LogPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
$install = Join-Path $PSScriptRoot 'install.ps1'
if (-not $LogPath) { $LogPath = Join-Path $repo 'docs\evidence\missing-plugin.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath)

$scratch = Join-Path $env:TEMP 'liveshear-probe'
$null = New-Item -ItemType Directory -Force -Path $scratch
$withPlugin = Join-Path $scratch 'shear-with-plugin.ai'
$reSaved = Join-Path $scratch 'shear-resaved-without-plugin.ai'

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }

function Num([double] $v) {
    [Math]::Round($v, 3).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
}

function JsPath([string] $p) { $p.Replace('\', '\\') }

# What the scripting DOM alone can tell us about the opened document.
function Survey {
    $raw = Invoke-AiScript @'
var d = app.activeDocument;
var out = [];
for (var i = 0; i < d.pageItems.length; i++) {
    var it = d.pageItems[i];
    var b = it.visibleBounds;
    var line = it.typename + "; name=" + it.name +
        "; visibleWidth=" + Math.round((b[2] - b[0]) * 1000) / 1000 +
        "; geometricWidth=" + Math.round((it.geometricBounds[2] - it.geometricBounds[0]) * 1000) / 1000;
    if (it.typename == "PathItem") {
        var xs = [];
        for (var j = 0; j < it.pathPoints.length; j++) { xs.push(Math.round(it.pathPoints[j].anchor[0] * 1000) / 1000); }
        line += "; anchorsX=" + xs.join("/");
    }
    if (it.typename == "TextFrame") { line += "; contents=" + it.contents; }
    out.push(line);
}
out.join("\n");
'@
    $raw
}

Note 'Live Shear -- what a machine without the plug-in sees'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ''

# ----------------------------------------------------------- phase 1: authoring
Note '=== Phase 1: authored with the plug-in installed ==='
Start-Ai | Out-Null
$version = Send-AiMessage version
if ($version -notmatch 'LiveShear') { throw 'The plug-in is not loaded; install it before running this probe.' }

Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
Invoke-AiScript @'
var d = app.documents.add(DocumentColorSpace.RGB, 600, 600);
d.rulerOrigin = [0, 0];
var r = d.pathItems.rectangle(500, 100, 200, 120);
r.name = "rect"; r.filled = true; r.stroked = false;
var c = new RGBColor(); c.red = 200; c.green = 40; c.blue = 40; r.fillColor = c;
var t = d.textFrames.add();
t.name = "text"; t.contents = "Handgloves"; t.position = [100, 250];
t.textRange.characterAttributes.size = 48;
app.executeMenuCommand("selectall");
'@ | Out-Null
Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:30' | Out-Null
Invoke-AiScript 'app.redraw();' | Out-Null
Note (Survey)
Note ''
Note 'appearance as the plug-in reports it:'
Note ((Send-AiMessage appearance).TrimEnd())

$p = JsPath $withPlugin
Invoke-AiScript @"
var f = new File("$p");
var o = new IllustratorSaveOptions();
o.compatibility = Compatibility.ILLUSTRATOR24;
o.pdfCompatible = true;
app.activeDocument.saveAs(f, o);
"@ | Out-Null
Note ''
Note ("saved to {0} ({1:N0} bytes)" -f $withPlugin, (Get-Item $withPlugin).Length)
Note ''

# ------------------------------------------------- phase 2: plug-in uninstalled
Note '=== Phase 2: the same file opened with the plug-in removed ==='
Stop-Ai | Out-Null
& $install -Uninstall | Out-Null
Start-Ai | Out-Null

$stillThere = $false
try { $stillThere = (Send-AiMessage version) -match 'LiveShear' } catch { }
Note ("plug-in reachable: {0}" -f $stillThere)

$opened = $true
$openError = ''
try {
    Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
    Invoke-AiScript ("app.open(new File(`"" + (JsPath $withPlugin) + "`")); app.redraw();") | Out-Null
}
catch { $opened = $false; $openError = $_.Exception.Message }
Note ("document opens: {0} {1}" -f $opened, $openError)
if ($opened) {
    Note 'what the document looks like now:'
    Note (Survey)

    # Does editing the artwork still drive the effect, or is the result frozen?
    Invoke-AiScript 'app.activeDocument.textFrames[0].contents = "Handgloves and more"; app.redraw();' | Out-Null
    Note ''
    Note 'after retyping the text (if the effect were still running, the sheared result would grow):'
    Note (Survey)

    $p2 = JsPath $reSaved
    Invoke-AiScript @"
var f = new File("$p2");
var o = new IllustratorSaveOptions();
o.compatibility = Compatibility.ILLUSTRATOR24;
o.pdfCompatible = true;
app.activeDocument.saveAs(f, o);
"@ | Out-Null
    Note ''
    Note ("re-saved without the plug-in to {0} ({1:N0} bytes)" -f $reSaved, (Get-Item $reSaved).Length)
}
Note ''

# ------------------------------------------------- phase 3: plug-in reinstalled
Note '=== Phase 3: the plug-in reinstalled ==='
Stop-Ai | Out-Null
& $install | Out-Null
Start-Ai | Out-Null

Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
Invoke-AiScript ("app.open(new File(`"" + (JsPath $withPlugin) + "`")); app.redraw();") | Out-Null
Note 'the original file, reopened with the plug-in back:'
Note (Survey)
Invoke-AiScript 'app.executeMenuCommand("selectall");' | Out-Null
Note ((Send-AiMessage appearance).TrimEnd())

Note ''
Note 'the file that was re-saved while the plug-in was missing:'
Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
Invoke-AiScript ("app.open(new File(`"" + (JsPath $reSaved) + "`")); app.redraw();") | Out-Null
Note (Survey)
Invoke-AiScript 'app.executeMenuCommand("selectall");' | Out-Null
Note ((Send-AiMessage appearance).TrimEnd())

Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null

[System.IO.File]::WriteAllLines($LogPath, $log)
Write-Output "`nWritten to $LogPath"
