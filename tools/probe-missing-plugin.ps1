<#
.SYNOPSIS
    Answers what happens to a document containing the Shear effect when it is
    opened on a machine that does not have the plugin.

.DESCRIPTION
    Runs in three phases, uninstalling and reinstalling the plugin and
    restarting Illustrator between them:

      1. with the plugin:    build and save the documents
      2. without the plugin: open them, look at what survived, edit, re-save
      3. with the plugin:    reopen both the original and the file that was
                              re-saved while the plugin was missing

    Phase 2 cannot use the plugin's own appearance dump, for obvious reasons,
    so it reads what the scripting DOM can see: whether the artwork still
    renders sheared, whether the source geometry is still unsheared (which is
    only true if a live effect is still doing the work), and whether text is
    still text.

    Results go to docs\evidence\missing-plugin.txt.
#>
[CmdletBinding()]
param(
    [string] $LogPath,
    # Arm A of the crash experiment needs the plugin uninstalled, which is the
    # one thing this probe already arranges. Running it here means the whole
    # release suite asks for administrator rights twice instead of four times.
    [int] $CrashTrials = 0,
    [int] $CrashCycles = 60,
    [string] $CrashLogPath
)

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

if (-not $CrashLogPath) { $CrashLogPath = Join-Path $repo 'docs\evidence\crash-arm-a.txt' }

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }

$script:pass = 0
$script:fail = 0
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    Note ("[{0}] {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name)
    if ($detail) { Note ("       " + $detail) }
    Add-ProbeResult -Group 'without the plugin' -Case $name -Expected 'the document opens and nothing is lost' -Observed $detail -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
}

function Widths([string] $survey) {
    $out = @{}
    foreach ($line in ($survey -split "`n")) {
        if ($line -match 'name=([^;]*);\s*visibleWidth=([-0-9.]+);\s*geometricWidth=([-0-9.]+)') {
            $out[$Matches[1].Trim()] = @([double] $Matches[2], [double] $Matches[3])
        }
    }
    return $out
}

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

Start-ProbeResults -Probe 'without the plugin'
Note 'Live Shear -- what a machine without the plugin sees'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ''

# ----------------------------------------------------------- phase 1: authoring
Note '=== Phase 1: authored with the plugin installed ==='
Start-Ai | Out-Null
$version = Send-AiMessage version
if ($version -notmatch 'LiveShear') { throw 'The plugin is not loaded; install it before running this probe.' }

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
$authored = Survey
Note $authored
$authoredWidths = Widths $authored
Note ''
Note 'appearance as the plugin reports it:'
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

# ------------------------------------------------- phase 2: plugin uninstalled
Note '=== Phase 2: the same file opened with the plugin removed ==='
Stop-Ai | Out-Null
& $install -Uninstall | Out-Null
Start-Ai | Out-Null

$stillThere = $false
try { $stillThere = (Send-AiMessage version) -match 'LiveShear' } catch { }
Note ("plugin reachable: {0}" -f $stillThere)

$opened = $true
$openError = ''
try {
    Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
    Invoke-AiScript ("app.open(new File(`"" + (JsPath $withPlugin) + "`")); app.redraw();") | Out-Null
}
catch { $opened = $false; $openError = $_.Exception.Message }
Note ("document opens: {0} {1}" -f $opened, $openError)
Check 'the plugin really is gone' (-not $stillThere) ("the script bridge answers: {0}" -f $stillThere)
Check 'the document opens without the plugin' $opened $openError
if ($opened) {
    Note 'what the document looks like now:'
    $without = Survey
    Note $without
    $withoutWidths = Widths $without

    $drawnSame = $true
    $sourceSame = $true
    foreach ($name in $authoredWidths.Keys) {
        if (-not $withoutWidths.ContainsKey($name)) { $drawnSame = $false; $sourceSame = $false; continue }
        if ([Math]::Abs($authoredWidths[$name][0] - $withoutWidths[$name][0]) -gt 0.01) { $drawnSame = $false }
        if ([Math]::Abs($authoredWidths[$name][1] - $withoutWidths[$name][1]) -gt 0.01) { $sourceSame = $false }
    }
    Check 'the artwork still draws sheared' $drawnSame ('drawn widths with the plugin: ' + (($authoredWidths.Keys | ForEach-Object { "$_=$($authoredWidths[$_][0])" }) -join ', ') + '; without it: ' + (($withoutWidths.Keys | ForEach-Object { "$_=$($withoutWidths[$_][0])" }) -join ', '))
    Check 'the source geometry is neither expanded nor flattened' $sourceSame ('geometric widths with the plugin: ' + (($authoredWidths.Keys | ForEach-Object { "$_=$($authoredWidths[$_][1])" }) -join ', ') + '; without it: ' + (($withoutWidths.Keys | ForEach-Object { "$_=$($withoutWidths[$_][1])" }) -join ', '))
    Check 'text is still live text' ($without -match 'TextFrame') 'no TextFrame in the reopened document'

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
    Note ("re-saved without the plugin to {0} ({1:N0} bytes)" -f $reSaved, (Get-Item $reSaved).Length)
    Check 'the document can be re-saved without the plugin' (Test-Path $reSaved) ("{0:N0} bytes" -f (Get-Item $reSaved).Length)
}
Note ''

# Arm A of the crash experiment: the plugin is uninstalled right now, which is
# the state that arm needs, and arranging it again later would mean asking for
# administrator rights twice more.
if ($CrashTrials -gt 0) {
    Note ("=== Crash experiment, arm A: {0} trials of up to {1} document cycles, plugin absent ===" -f $CrashTrials, $CrashCycles)
    $armA = New-Object Collections.Generic.List[string]
    $armA.Add(("Arm A, plugin absent. Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    $build = 'var d = app.documents.add(DocumentColorSpace.RGB, 600, 600); d.rulerOrigin=[0,0]; var r = d.pathItems.rectangle(500,100,200,120); r.filled = true; r.stroked = false; app.executeMenuCommand("deselectall"); r.selected = true; "built";'
    for ($t = 1; $t -le $CrashTrials; $t++) {
        Stop-Ai | Out-Null
        if (Get-Process Illustrator -ErrorAction SilentlyContinue) { Stop-Process -Name Illustrator -Force; Start-Sleep -Seconds 2 }
        Start-Ai | Out-Null
        Invoke-AiScript 'app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS; while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } "ready";' | Out-Null
        $done = $CrashCycles
        for ($i = 0; $i -lt $CrashCycles; $i++) {
            try {
                Invoke-AiScript $build | Out-Null
                Invoke-AiScript 'app.activeDocument.close(SaveOptions.DONOTSAVECHANGES); "closed";' | Out-Null
            }
            catch { $done = $i; break }
        }
        $peak = 0
        $p = Get-Process Illustrator -ErrorAction SilentlyContinue
        if ($p) { $peak = [int] ($p.PeakWorkingSet64 / 1MB) }
        $line = ("A absent          trial {0}: {1,3} of {2} cycles, peak {3} MB" -f $t, $done, $CrashCycles, $peak)
        $armA.Add($line)
        Note ("  " + $line)
    }
    [System.IO.File]::WriteAllLines($CrashLogPath, $armA)
    Note ("arm A written to {0}" -f $CrashLogPath)
    Note ''
}

# ------------------------------------------------- phase 3: plugin reinstalled
Note '=== Phase 3: the plugin reinstalled ==='
Stop-Ai | Out-Null
& $install | Out-Null
Start-Ai | Out-Null

Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
Invoke-AiScript ("app.open(new File(`"" + (JsPath $withPlugin) + "`")); app.redraw();") | Out-Null
Note 'the original file, reopened with the plugin back:'
$recovered = Survey
Note $recovered
Invoke-AiScript 'app.executeMenuCommand("selectall");' | Out-Null
$recoveredStyle = (Send-AiMessage appearance).TrimEnd()
Note $recoveredStyle
Check 'the original file still holds the effect and its parameters' (($recoveredStyle -match 'VulpesNexus Shear') -and ($recoveredStyle -match 'shearAngle \(Real\) = 30')) 'the effect or its angle did not survive'

Note ''
Note 'the file that was re-saved while the plugin was missing:'
Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null
Invoke-AiScript ("app.open(new File(`"" + (JsPath $reSaved) + "`")); app.redraw();") | Out-Null
$resurvey = Survey
Note $resurvey
Invoke-AiScript 'app.executeMenuCommand("selectall");' | Out-Null
$resavedStyle = (Send-AiMessage appearance).TrimEnd()
Note $resavedStyle
Check 'a file re-saved without the plugin loses nothing' (($resavedStyle -match 'VulpesNexus Shear') -and ($resavedStyle -match 'shearAngle \(Real\) = 30')) 'the effect or its angle did not survive the round trip through a machine without the plugin'

Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null

Note ''
Note ("{0} passed, {1} failed" -f $script:pass, $script:fail)
Save-ProbeResults -Path ($LogPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($LogPath, $log)
Write-Output "`nWritten to $LogPath"
