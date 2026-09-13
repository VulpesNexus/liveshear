<#
.SYNOPSIS
    What the effect does with a parameter dictionary that is not the one it
    wrote: keys missing, keys of the wrong type, and a schema number from a
    version that does not exist yet.

.DESCRIPTION
    tools/probe-limits.ps1 covers hostile *values* -- 90 degrees, infinity, a
    NaN. This covers hostile *shapes*. A document can reach this effect having
    been written by a later version of it, by another plugin, by a script, or
    by a file that was damaged, and in none of those cases may it produce an
    undefined transform or fail to return.

    The parameter block carries a schema number, and a schema number that is
    never tested is decoration. Two things have to be true for it to be worth
    having:

        reading    a dictionary with no schema key means schema 1, because
                   that is what the first version wrote before the key existed

        writing    keys this version does not know about survive being read and
                   written back, or a later version's documents would be
                   damaged by opening them here

    The second is the one that makes the number useful, and it is the one that
    is easy to get wrong.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [int] $TimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\schema.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

$script:pass = 0
$script:fail = 0
function Check([string] $name, [bool] $ok, [string] $detail) {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    Note ("[{0}] {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name)
    if ($detail) { Note ("       " + $detail) }
    Add-ProbeResult -Group 'serialization' -Case $name `
        -Expected 'a dictionary this version did not write is read safely and written back without loss' `
        -Observed $detail -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
}

function Num([double] $v) { $v.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture) }

# The fixture is 200 by 120 with its center at (200, 540), so a horizontal
# shear of theta makes it 200 + 120*tan(theta) wide.
function ExpectedWidth([double] $degrees) {
    return 200.0 + 120.0 * [Math]::Abs([Math]::Tan($degrees * [Math]::PI / 180.0))
}

function Build {
    Js "LS.clear(); LS.target = LS.fixtures['plainRect'](); LS.target.name = 'subject'; LS.selectOnly(LS.target);" | Out-Null
    Js 'app.redraw();' | Out-Null
    Js 'LS.shear(30, 0);' | Out-Null
    Js 'app.redraw();' | Out-Null
}

# Redraw behind a watchdog, so a dictionary that made the effect fail to return
# is reported as a hang rather than hanging this script.
function RenderedWidth([int] $seconds) {
    $job = Start-Job -ScriptBlock {
        param($root)
        . (Join-Path $root 'ai.ps1')
        Invoke-AiScript 'app.redraw(); LS.vb(LS.named("subject"));'
    } -ArgumentList $PSScriptRoot
    $done = Wait-Job $job -Timeout $seconds
    if (-not $done) { Stop-Job $job; Remove-Job $job -Force; return $null }
    $out = (Receive-Job $job) -join ''
    Remove-Job $job -Force
    $parts = $out.Trim() -split ','
    if ($parts.Count -ne 4) { return $null }
    return [double]$parts[2] - [double]$parts[0]
}

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'schema'

Note 'Live Shear -- a parameter dictionary this version did not write'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("Watchdog: {0} seconds per redraw" -f $TimeoutSeconds)
Note ''

$sheared = ExpectedWidth 30
$identity = 200.0

# key, type, value, what the effect should settle on, why
$cases = @(
    @{ do = 'delete|shearSchema';                want = $sheared;  name = 'no schema key at all means schema 1';
       why = 'the first version wrote no schema key, and its documents must keep rendering' },
    @{ do = 'set|shearSchema|int|999';           want = $sheared;  name = 'a schema number from a later version still renders';
       why = 'an unknown schema is not a reason to refuse to draw; the two angles mean what they have always meant' },
    @{ do = 'set|shearSchema|int|-1';            want = $sheared;  name = 'a nonsense schema number still renders' ;
       why = 'nothing about the number changes what the angles mean here' },
    @{ do = 'delete|shearAngle';                 want = $identity; name = 'no shear angle means no shear';
       why = 'the default is zero, and zero is the identity' },
    @{ do = 'delete|axisAngle';                  want = $sheared;  name = 'no axis angle means the horizontal axis';
       why = 'the default axis is zero, which is the shear the fixture already has' },
    @{ do = 'set|shearAngle|string|thirty';      want = $identity; name = 'a shear angle stored as text is refused';
       why = 'reading a real out of a string entry fails, and a failed read leaves the default' },
    @{ do = 'set|axisAngle|string|sideways';     want = $sheared;  name = 'an axis angle stored as text is refused';
       why = 'same, and the default axis is zero' },
    @{ do = 'set|shearAngle|bool|1';             want = $identity; name = 'a shear angle stored as a flag is refused';
       why = 'the type is wrong, so the default stands' },
    @{ do = 'delete|shearAngle;delete|axisAngle;delete|shearSchema'; want = $identity; name = 'an empty parameter block is the identity';
       why = 'every key absent is every default, and the defaults are zero' }
)

foreach ($case in $cases) {
    Build
    foreach ($step in ($case.do -split ';')) {
        $parts = $step -split '\|'
        if ($parts[0] -eq 'delete') { Js ("LS.send('delete param', '0|{0}');" -f $parts[1]) | Out-Null }
        else { Js ("LS.send('set param', '0|{0}|{1}|{2}');" -f $parts[1], $parts[2], $parts[3]) | Out-Null }
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $width = RenderedWidth $TimeoutSeconds
    $sw.Stop()

    if ($null -eq $width) {
        Check $case.name $false ("the redraw did not return within {0} seconds" -f $TimeoutSeconds)
        continue
    }
    $ok = [Math]::Abs($width - $case.want) -lt 0.01
    Check $case.name $ok ("{0}; rendered {1} pt wide in {2:N2} s, expected {3} pt" -f `
        $case.why, (Num $width), $sw.Elapsed.TotalSeconds, (Num $case.want))
}

# --- the one that makes the schema number worth having ---------------------
#
# A later version will add a key. If reading and writing the dictionary here
# drops it, a document that has merely been opened on this version comes back
# damaged.
Note ''
Note '--- a key from a version that does not exist yet ---'
Build
Js "LS.send('set param', '0|shearSchema|int|2');" | Out-Null
Js "LS.send('set param', '0|referencePoint|string|bottomLeft');" | Out-Null
Js "LS.send('set param', '0|somethingElse|real|1.25');" | Out-Null
Js 'app.redraw();' | Out-Null

# Writing it through the script bridge proves nothing about the path a person
# takes, so the block is rewritten by the plugin itself: the dialog is opened
# and committed, which is what runs ShearEffect::WriteParameters.
$driver = Start-Job -ScriptBlock {
    Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Sd {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static IntPtr Find() {
        IntPtr hit = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            var c = new StringBuilder(128); GetClassNameW(h, c, 128);
            if (c.ToString().Contains("VulpesNexusShearDialog")) { hit = h; return false; }
            return true;
        }, IntPtr.Zero);
        return hit;
    }
}
"@
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        $h = [Sd]::Find()
        if ($h -ne [IntPtr]::Zero) {
            Start-Sleep -Milliseconds 400
            [Sd]::PostMessage($h, 0x0100, [IntPtr]0x0D, [IntPtr]0) | Out-Null   # Enter commits
            [Sd]::PostMessage($h, 0x0101, [IntPtr]0x0D, [IntPtr]0) | Out-Null
            return 'committed'
        }
        Start-Sleep -Milliseconds 200
    }
    return 'the dialog never appeared'
}
$edited = Js "LS.send('edit effect', '0');"
$driverSaid = (Receive-Job -Job $driver -Wait) -join ''
Remove-Job $driver -Force
Note ("       dialog driver: {0}; edit effect said: {1}" -f $driverSaid, ($edited -replace "`r?`n", ' '))
Js 'app.redraw();' | Out-Null
$after = Js 'LS.appearance();'

$keptReference = $after -match 'referencePoint'
$keptOther = $after -match 'somethingElse'
Check 'a later version''s extra keys survive the dialog writing the block back' ($keptReference -and $keptOther) `
    ("referencePoint {0}, somethingElse {1} after the plugin itself rewrote the block through the dialog" -f `
        $(if ($keptReference) { 'kept' } else { 'LOST' }), $(if ($keptOther) { 'kept' } else { 'LOST' }))

$schemaNow = if ($after -match 'shearSchema[^=]*=\s*([-0-9]+)') { $Matches[1] } else { 'absent' }
Check 'the block records which version last wrote it' ($schemaNow -eq '1') `
    ("shearSchema is {0} after this version wrote it, which is this version's number: the block says what it means rather than what it used to mean" -f $schemaNow)

Note ''
Note ("{0} passed, {1} failed" -f $script:pass, $script:fail)
Js 'LS.clear();' | Out-Null
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
