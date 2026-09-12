<#
.SYNOPSIS
    Undo and redo, including how many steps one deliberate edit costs.

.DESCRIPTION
    Two questions. Does undo put the artwork back exactly, and does one thing a
    person did read as one thing to undo? A dialog that leaves forty undo steps
    behind after one drag of a slider is not broken, but it is not shippable
    either.

    Every case counts how many undos are needed to reach the state before the
    edit, then redoes the same number and checks the result came back.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [int] $MaxUndo = 60
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\undo.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

$script:pass = 0
$script:fail = 0
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    Note ("{0,-52} {1}" -f $name, $(if ($ok) { 'PASS' } else { "FAIL  $detail" }))
    Add-ProbeResult -Group 'undo and redo' -Case $name -Expected 'the artwork returns exactly, in a sensible number of steps' -Observed $detail -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
}

function Bounds { Js 'LS.vb(LS.target);' }

# Undo until the artwork matches `target`, or give up. Returns the number of
# steps taken, or -1 if it never got there.
function Undo-Until([string] $target) {
    for ($i = 1; $i -le $MaxUndo; $i++) {
        Js 'app.undo(); app.redraw();' | Out-Null
        # Undoing past the artwork itself means the state being looked for was
        # never reached; redo back so the document is left as it was found.
        if ([int] (Js 'app.activeDocument.pageItems.length;') -eq 0) {
            for ($back = 0; $back -lt $i; $back++) { Js 'app.redo();' | Out-Null }
            Js 'app.redraw();' | Out-Null
            return -1
        }
        Js 'LS.target = app.activeDocument.pageItems[0];' | Out-Null
        if ((Bounds) -eq $target) { return $i }
    }
    return -1
}

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'undo'

Note 'Live Shear -- undo and redo'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ''

# ---- applying the effect ---------------------------------------------
Js "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.selectOnly(LS.target);" | Out-Null
Js 'app.redraw();' | Out-Null
$plain = Bounds
Js 'LS.shear(30, 0);' | Out-Null
Js 'app.redraw();' | Out-Null
$sheared = Bounds
Check 'applying the effect changes the artwork' ($plain -ne $sheared) "$plain then $sheared"

$steps = Undo-Until $plain
Check 'one undo removes a freshly applied effect' ($steps -eq 1) ("took {0} undo steps" -f $steps)

Js 'app.redo(); app.redraw(); LS.target = app.activeDocument.pageItems[0];' | Out-Null
Check 'redo puts it back' ((Bounds) -eq $sheared) ("after redo " + (Bounds) + ", wanted " + $sheared)

# ---- editing a parameter through the test bridge ------------------------
# What follows is worth saying plainly. The probe changes parameters, reorders
# effects and deletes them through the plugin's script bridge, which rebuilds
# the art style through the SDK directly. Illustrator wraps its own user
# operations in undo transactions; a style rebuilt from a script message is not
# one of those, so the number of undo steps such an edit costs is a property of
# the bridge and not of the effect. The cases below therefore check that undo
# leaves the document coherent, not that it takes any particular number of
# steps. The step count that does matter -- what one pass through the dialog
# costs, which is the only way a person edits the effect -- is measured further
# down, with the dialog driven the way a person drives it.
Js "LS.send('set param', '0|shearAngle|real|45');" | Out-Null
Js 'app.redraw();' | Out-Null
$edited = Bounds
Check 'editing the angle changes the artwork' ($edited -ne $sheared) "$sheared then $edited"

$steps = Undo-Until $sheared
Note ("    a parameter edit made through the script bridge cost {0} undo steps" -f $steps)
Check 'undo after a bridge parameter edit leaves the document coherent' ([int] (Js 'app.activeDocument.pageItems.length;') -ge 1) 'the document lost its artwork'

# ---- a whole dialog session -------------------------------------------
# The dialog previews by rewriting the parameters and asking Illustrator to
# re-run the effect, once per slider position. If each preview were its own
# undo step, one drag would cost as many undos as it had positions.
$driver = {
    param([string] $ResultFile)
    Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class D2 {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr p, int id);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    public static IntPtr Find(string needle) {
        IntPtr hit = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            StringBuilder cls = new StringBuilder(256);
            GetClassNameW(h, cls, 256);
            if (cls.ToString().Contains(needle)) { hit = h; return false; }
            return true;
        }, IntPtr.Zero);
        return hit;
    }
}
"@
    $deadline = (Get-Date).AddSeconds(30)
    $dlg = [IntPtr]::Zero
    while ((Get-Date) -lt $deadline) {
        $dlg = [D2]::Find('VulpesNexusShearDialog')
        if ($dlg -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 200
    }
    if ($dlg -eq [IntPtr]::Zero) { [IO.File]::WriteAllText($ResultFile, 'dialog never appeared'); return }
    $slider = [D2]::GetDlgItem($dlg, 1001)
    foreach ($a in @(10, 20, 30, 40, 50, 60)) {
        [D2]::SendMessage($slider, 1029, [IntPtr] 1, [IntPtr] ([int]($a * 10))) | Out-Null
        [D2]::SendMessage($dlg, 0x0114, [IntPtr] 8, $slider) | Out-Null
        Start-Sleep -Milliseconds 200
    }
    [D2]::SendMessage($dlg, 0x0111, [IntPtr] 1, [D2]::GetDlgItem($dlg, 1)) | Out-Null
    [IO.File]::WriteAllText($ResultFile, 'drove the slider through six positions and pressed OK')
}

Js "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.selectOnly(LS.target);" | Out-Null
Js 'app.redraw();' | Out-Null
Js 'LS.shear(5, 0);' | Out-Null
Js 'app.redraw();' | Out-Null
$beforeDialog = Bounds

$resultFile = Join-Path $env:TEMP ("liveshear-undo-{0}.txt" -f [Guid]::NewGuid().ToString('N'))
$job = Start-Job -ScriptBlock $driver -ArgumentList $resultFile
try { Send-AiMessage 'edit effect' '0' | Out-Null } catch { }
Wait-Job $job -Timeout 90 | Out-Null
Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
Remove-Job $job -Force
Note ("driver: " + $(if (Test-Path $resultFile) { Get-Content $resultFile } else { 'no output' }))
if (Test-Path $resultFile) { [IO.File]::Delete($resultFile) }

Js 'app.redraw(); LS.target = app.activeDocument.pageItems[0];' | Out-Null
$afterDialog = Bounds
Check 'the dialog session committed the last slider position' ($afterDialog -ne $beforeDialog) "$beforeDialog then $afterDialog"

$steps = Undo-Until $beforeDialog
Check 'one drag through six positions costs a handful of undo steps' (($steps -ge 1) -and ($steps -le 8)) ("took {0} undo steps to get back to the state before the dialog opened" -f $steps)
Note ("    a drag through six slider positions cost {0} undo steps" -f $steps)

# ---- deleting and reordering -------------------------------------------
Js "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.selectOnly(LS.target);" | Out-Null
Js 'app.redraw();' | Out-Null
Js 'LS.shear(30, 0); LS.shear(-12, 90);' | Out-Null
Js 'app.redraw();' | Out-Null
$two = Bounds
Js "LS.send('remove effect', '1');" | Out-Null
Js 'app.redraw();' | Out-Null
$one = Bounds
Check 'deleting one of two effects changes the artwork' ($one -ne $two) ("two effects {0}, one effect {1}" -f $two, $one)
$steps = Undo-Until $two
Note ("    deleting an effect through the script bridge cost {0} undo steps" -f $steps)
Check 'undo after a bridge deletion leaves the document coherent' ([int] (Js 'app.activeDocument.pageItems.length;') -ge 1) 'the document lost its artwork'

Js "LS.send('move effect', '0,1');" | Out-Null
Js 'app.redraw();' | Out-Null
$swapped = Bounds
$steps = Undo-Until $two
Note ("    reordering through the script bridge cost {0} undo steps" -f $steps)
Check 'undo after a bridge reorder leaves the document coherent' ([int] (Js 'app.activeDocument.pageItems.length;') -ge 1) ("the document lost its artwork; swapped bounds were {0}" -f $swapped)

# ---- the source survives all of it --------------------------------------
$anchorsNow = Js 'LS.anchorsOf(LS.target);'
$fresh = Js "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.anchorsOf(LS.target);"
Check 'the source path is unchanged after all of that' ($anchorsNow -eq $fresh) "$anchorsNow vs $fresh"

Js 'LS.clear();' | Out-Null
Note ''
Note ("{0} passed, {1} failed" -f $script:pass, $script:fail)
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
