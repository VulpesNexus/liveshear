<#
.SYNOPSIS
    Compares what sheared artwork looks like on screen under GPU and CPU
    preview.

.DESCRIPTION
    The effect produces art objects; it never draws anything itself, so a
    difference between the two preview paths could only come from Illustrator's
    renderer or from a redraw that was never invalidated. Reasoning is not
    evidence, though, so this captures the document window as a bitmap in each
    mode and counts the pixels that differ.

    Two things have to be established before any of that means anything. The
    capture has to work, which is checked by moving the artwork and confirming
    the picture changes. And the mode has to actually switch, which Illustrator
    reports in its window title: a document drawn by the GPU says "GPU Preview"
    there. If the mode cannot be switched -- GPU preview needs supported
    hardware and is simply absent on a machine without it -- the probe says the
    comparison was not made rather than reporting agreement it did not observe.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [string] $ImageFolder
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\gpu.txt' }
if (-not $ImageFolder) { $ImageFolder = Join-Path ([IO.Path]::GetTempPath()) 'liveshear-gpu' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)
$null = New-Item -ItemType Directory -Force -Path $ImageFolder

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }
function Js([string] $code) { (Invoke-AiScript $code).Trim() }

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Cap {
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

function Get-WindowBitmap([IntPtr] $hwnd) {
    $r = New-Object Cap+RECT
    [Cap]::GetClientRect($hwnd, [ref] $r) | Out-Null
    $w = $r.Right - $r.Left
    $h = $r.Bottom - $r.Top
    if ($w -le 0 -or $h -le 0) { return $null }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $dc = $g.GetHdc()
    # PW_RENDERFULLCONTENT, so a window drawn by the GPU is captured too.
    [Cap]::PrintWindow($hwnd, $dc, 2) | Out-Null
    $g.ReleaseHdc($dc)
    $g.Dispose()
    return $bmp
}

function Compare-Bitmaps($a, $b) {
    if ($null -eq $a -or $null -eq $b) { return -1 }
    if ($a.Width -ne $b.Width -or $a.Height -ne $b.Height) { return -1 }
    $differing = 0
    $total = 0
    # Every fourth pixel in each direction: enough to catch a redraw fault,
    # fast enough to run in a few seconds.
    for ($y = 0; $y -lt $a.Height; $y += 4) {
        for ($x = 0; $x -lt $a.Width; $x += 4) {
            $total++
            if ($a.GetPixel($x, $y).ToArgb() -ne $b.GetPixel($x, $y).ToArgb()) { $differing++ }
        }
    }
    if ($total -eq 0) { return -1 }
    return [double] $differing / $total
}

function Get-Title { (Get-Process Illustrator).MainWindowTitle }

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'gpu'

Note 'Live Shear -- GPU against CPU preview'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ''

$proc = Get-Process Illustrator
$hwnd = $proc.MainWindowHandle
$shell = New-Object -ComObject WScript.Shell
$shell.AppActivate($proc.Id) | Out-Null
Start-Sleep -Milliseconds 800

Js "LS.clear(); LS.target = LS.fixtures['spike'](); LS.selectOnly(LS.target);" | Out-Null
Js 'LS.shear(30, 0);' | Out-Null
Js 'app.activeDocument.selection = null; app.executeMenuCommand("fitall"); app.redraw();' | Out-Null
Start-Sleep -Milliseconds 800

$first = Get-WindowBitmap $hwnd
if ($first) { $first.Save((Join-Path $ImageFolder 'preview-a.png')) }
Note ("window title: {0}" -f (Get-Title))
Note ("captured {0}" -f (Join-Path $ImageFolder 'preview-a.png'))

# Does the capture see the canvas at all? Move the artwork and look again.
Js 'LS.target.translate(0, -120); app.redraw();' | Out-Null
Start-Sleep -Milliseconds 800
$moved = Get-WindowBitmap $hwnd
$movedDiff = Compare-Bitmaps $first $moved
if ($moved) { $moved.Dispose() }
Js 'LS.target.translate(0, 120); app.redraw();' | Out-Null
Start-Sleep -Milliseconds 800
Note ("self-check: moving the artwork changed {0:P3} of sampled pixels" -f [Math]::Max($movedDiff, 0))
$captureWorks = $movedDiff -gt 0.0005
Add-ProbeResult -Group 'preview mode' -Case 'the window capture sees the canvas' -Expected 'moving the artwork changes the captured picture' -Observed ("{0:P3} of sampled pixels changed" -f [Math]::Max($movedDiff, 0)) -Status $(if ($captureWorks) { 'PASS' } else { 'FAIL' })

# Try to switch the mode. Ctrl+E is the shortcut; the menu command strings are
# tried too in case the shortcut has been reassigned.
$titleBefore = Get-Title
$switched = $null
$shell.AppActivate($proc.Id) | Out-Null
Start-Sleep -Milliseconds 500
$shell.SendKeys('^e')
Start-Sleep -Milliseconds 2000
if ((Get-Title) -ne $titleBefore) { $switched = 'the Ctrl+E shortcut' }
if (-not $switched) {
    foreach ($command in @('GPU Preview', 'CPU Preview', 'gpuPreview', 'cpuPreview', 'Preview on CPU', 'Preview on GPU')) {
        try { Js ("app.executeMenuCommand('{0}');" -f $command) | Out-Null } catch { }
        Js 'app.redraw();' | Out-Null
        Start-Sleep -Milliseconds 700
        if ((Get-Title) -ne $titleBefore) { $switched = "the menu command '$command'"; break }
    }
}

if ($switched) {
    Start-Sleep -Milliseconds 1200
    $second = Get-WindowBitmap $hwnd
    if ($second) { $second.Save((Join-Path $ImageFolder 'preview-b.png')) }
    $diff = Compare-Bitmaps $first $second
    if ($second) { $second.Dispose() }
    Note ("switched with {0}; title is now {1}" -f $switched, (Get-Title))
    Note ("{0:P3} of sampled pixels differ between the two modes" -f [Math]::Max($diff, 0))
    # Antialiasing differs between the two renderers, so a small difference is
    # expected; a large one would mean the geometry itself came out different.
    $ok = $diff -ge 0 -and $diff -lt 0.02
    Add-ProbeResult -Group 'preview mode' -Case 'GPU and CPU preview draw the same sheared artwork' -Expected 'no more than a couple of percent of pixels differ, from antialiasing' -Observed ("{0:P3} differ; switched with {1}" -f [Math]::Max($diff, 0), $switched) -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
    $shell.AppActivate($proc.Id) | Out-Null
    Start-Sleep -Milliseconds 400
    $shell.SendKeys('^e')
    Start-Sleep -Milliseconds 1200
    Note ("restored; title is {0}" -f (Get-Title))
}
else {
    Note ''
    Note ("The preview mode could not be switched. The window title stayed {0}, which names the mode Illustrator is drawing in, and neither the Ctrl+E shortcut nor any candidate menu command changed it." -f $titleBefore)
    Note 'GPU preview needs supported hardware and is absent when the machine has none, so on this machine there is only one preview path and the comparison cannot be made. It is recorded as untested rather than as agreement.'
    Add-ProbeResult -Group 'preview mode' -Case 'GPU and CPU preview draw the same sheared artwork' -Expected 'no more than a couple of percent of pixels differ, from antialiasing' -Observed ("the mode never changed; the window title stayed {0}" -f $titleBefore) -Status 'UNTESTED'
}

if ($first) { $first.Dispose() }
Js 'LS.clear();' | Out-Null

Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
