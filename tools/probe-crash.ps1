<#
.SYNOPSIS
    Looks for the intermittent Illustrator crash seen while running the
    behaviour probe, and tries to say whether the plug-in is implicated.

.DESCRIPTION
    Runs the same create/apply/close cycle many times in four variants:

      control     create a document, close it
      apply       create, apply the Shear effect, close
      expand      create, apply, expand the appearance, close
      raster      create with an embedded image, apply, close

    Each variant reports how many cycles completed before Illustrator stopped
    answering. A control that also dies says the churn is the problem rather
    than the effect.
#>
[CmdletBinding()]
param(
    [int] $Cycles = 40,
    [string[]] $Variant = @('control', 'apply', 'expand', 'raster'),
    [string] $LogPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $LogPath) { $LogPath = Join-Path $repo 'docs\evidence\crash-probe.txt' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath)

$scratch = Join-Path $env:TEMP 'liveshear-probe'
$null = New-Item -ItemType Directory -Force -Path $scratch
$rasterPath = Join-Path $scratch 'probe.png'
if (-not (Test-Path $rasterPath)) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 120, 80
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.Clear([System.Drawing.Color]::CornflowerBlue)
    $gfx.Dispose()
    $bmp.Save($rasterPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
$rasterJs = $rasterPath.Replace('\', '\\')

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }

function Alive {
    try { Invoke-AiScript '1;' | Out-Null; return $true } catch { return $false }
}

Note 'Live Shear -- crash bisect'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ("{0} cycles per variant" -f $Cycles)
Note ''

foreach ($v in $Variant) {
    Stop-Ai | Out-Null
    Start-Ai | Out-Null
    Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); }' | Out-Null

    $completed = 0
    $died = $false
    for ($i = 0; $i -lt $Cycles; $i++) {
        try {
            switch ($v) {
                'raster' {
                    Invoke-AiScript "var d = app.documents.add(DocumentColorSpace.RGB, 600, 600); d.rulerOrigin=[0,0]; var a = d.placedItems.add(); a.file = new File(`"$rasterJs`"); a.embed(); app.executeMenuCommand('deselectall'); d.pageItems[0].selected = true;" | Out-Null
                    Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:30' | Out-Null
                    Invoke-AiScript 'app.redraw();' | Out-Null
                }
                default {
                    Invoke-AiScript 'var d = app.documents.add(DocumentColorSpace.RGB, 600, 600); d.rulerOrigin=[0,0]; var r = d.pathItems.rectangle(500,100,200,120); r.filled = true; r.stroked = false; app.executeMenuCommand("deselectall"); r.selected = true;' | Out-Null
                    if ($v -ne 'control') {
                        Send-AiMessage 'apply effect' 'VulpesNexus Shear|shearAngle=r:30' | Out-Null
                        Invoke-AiScript 'app.redraw();' | Out-Null
                    }
                    if ($v -eq 'expand') {
                        Invoke-AiScript 'app.executeMenuCommand("expandStyle");' | Out-Null
                    }
                }
            }
            Invoke-AiScript 'app.activeDocument.close(SaveOptions.DONOTSAVECHANGES);' | Out-Null
            $completed++
        }
        catch {
            $died = $true
            Note ("{0}: died on cycle {1} -- {2}" -f $v, ($i + 1), $_.Exception.Message)
            break
        }
    }
    if (-not $died -and -not (Alive)) { $died = $true; Note ("{0}: process gone after the loop" -f $v) }
    Note ("{0}: {1} of {2} cycles completed{3}" -f $v, $completed, $Cycles, $(if ($died) { ' before Illustrator stopped responding' } else { '' }))
    Note ''
}

[System.IO.File]::WriteAllLines($LogPath, $log)
Write-Output "Written to $LogPath"
