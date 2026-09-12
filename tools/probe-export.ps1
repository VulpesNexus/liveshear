<#
.SYNOPSIS
    Exports sheared artwork to PDF and SVG and checks what came out.

.DESCRIPTION
    An effect that looks right on the canvas and wrong in the export is worse
    than no effect at all. Each case applies Shear, writes the document out,
    opens the exported file back in Illustrator, and compares the visible bounds
    of its contents against the bounds on the canvas. The exported file is also
    read as text to see whether Illustrator turned the artwork into a raster
    image on the way out.
#>
[CmdletBinding()]
param(
    [string] $OutPath,
    [string] $WorkFolder,
    [string[]] $Fixture = @('plainRect', 'strokedRect', 'pointText', 'mixedGroup', 'gradientFill', 'clipGroup')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'docs\evidence\export.txt' }
if (-not $WorkFolder) { $WorkFolder = Join-Path ([IO.Path]::GetTempPath()) 'liveshear-export' }
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutPath)
$null = New-Item -ItemType Directory -Force -Path $WorkFolder

$log = New-Object Collections.Generic.List[string]
function Note([string] $line) { $log.Add($line); Write-Output $line }

Install-AiHarness | Out-Null
Start-ProbeResults -Probe 'export'

function Escape-Path([string] $p) { $p.Replace('\', '\\') }

function Compare-Bounds([string] $a, [string] $b, [double] $tolerance = 0.02) {
    $x = $a -split ','; $y = $b -split ','
    if ($x.Count -ne 4 -or $y.Count -ne 4) { return $false }
    for ($i = 0; $i -lt 4; $i++) {
        $d = [math]::Abs([double]$x[$i] - [double]$y[$i])
        if ($d -gt $tolerance) { return $false }
    }
    return $true
}

Note 'Live Shear -- export fidelity'
Note ("Run at {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Note ''

$pass = 0; $fail = 0
foreach ($name in $Fixture) {
    foreach ($format in @('pdf', 'svg')) {
        # The fixture is rebuilt for each format on purpose: saving as PDF
        # replaces the document's identity with the saved file, so a second
        # export from the same document has nothing to export.
        Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } app.documents.add(); "reset";' | Out-Null
        Install-AiHarness | Out-Null
        Invoke-AiScript "LS.clear(); LS.target = LS.fixtures['$name'](); LS.selectOnly(LS.target); 'built';" | Out-Null
        Invoke-AiScript 'app.redraw();' | Out-Null
        Invoke-AiScript 'LS.shear(30, 0);' | Out-Null
        Invoke-AiScript 'app.redraw();' | Out-Null
        $canvas = (Invoke-AiScript 'LS.vb(LS.target);').Trim()

        $file = Join-Path $WorkFolder "$name.$format"
        $js = Escape-Path $file
        if ($format -eq 'pdf') {
            Invoke-AiScript "var o = new PDFSaveOptions(); o.preserveEditability = false; app.activeDocument.saveAs(new File('$js'), o); 'exported';" | Out-Null
        }
        else {
            Invoke-AiScript "var o = new ExportOptionsSVG(); o.embedRasterImages = true; app.activeDocument.exportFile(new File('$js'), ExportType.SVG, o); 'exported';" | Out-Null
        }

        $size = if (Test-Path $file) { (Get-Item $file).Length } else { 0 }
        # Latin-1 so every byte maps to a character and nothing in a binary PDF
        # is lost or throws; only literal markers are being looked for.
        # Encoding.Latin1 is .NET 5 and later, and this runs on 5.1.
        $latin1 = [Text.Encoding]::GetEncoding(28591)
        $text = if ($size -gt 0 -and $size -lt 20MB) { [IO.File]::ReadAllText($file, $latin1) } else { '' }
        $raster = if ($format -eq 'svg') { $text -match '<image' } else { $text -match '/Subtype\s*/Image' }

        # Open the exported file and measure what is actually in it.
        Invoke-AiScript "app.open(new File('$js')); app.redraw(); 'opened';" | Out-Null
        $reopened = (Invoke-AiScript 'var d = app.activeDocument; var b = null; for (var i = 0; i < d.pageItems.length; i++) { var v = d.pageItems[i].visibleBounds; if (!b) { b = v.slice(0); } else { if (v[0] < b[0]) b[0] = v[0]; if (v[1] > b[1]) b[1] = v[1]; if (v[2] > b[2]) b[2] = v[2]; if (v[3] < b[3]) b[3] = v[3]; } } b ? b[0].toFixed(9)+","+b[1].toFixed(9)+","+b[2].toFixed(9)+","+b[3].toFixed(9) : "none";').Trim()
        $kinds = (Invoke-AiScript 'var d = app.activeDocument, s = {}; for (var i = 0; i < d.pageItems.length; i++) { s[d.pageItems[i].typename] = 1; } var out = []; for (var k in s) { out.push(k); } out.join(",");').Trim()
        Invoke-AiScript 'app.activeDocument.close(SaveOptions.DONOTSAVECHANGES); "closed";' | Out-Null

        $match = Compare-Bounds $canvas $reopened
        $ok = $match -and -not $raster
        if ($ok) { $pass++ } else { $fail++ }
        Add-ProbeResult -Group $format -Case ("{0} exported to {1}" -f $name, $format) -Expected 'bounds match the canvas, no rasterization' -Observed ("bounds match {0}, raster {1}, items {2}, {3} bytes" -f $match, [bool]$raster, $kinds, $size) -Status $(if ($ok) { 'PASS' } else { 'FAIL' })
        Note ("{0,-14} {1,-4} {2,8} bytes  bounds {3,-5} raster {4,-5} items {5,-28} {6}" -f `
            $name, $format, $size, $match, [bool]$raster, $kinds, $(if ($ok) { 'PASS' } else { 'FAIL' }))
        if (-not $ok) {
            Note ("    canvas   {0}" -f $canvas)
            Note ("    reopened {0}" -f $reopened)
        }
    }
    Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } app.documents.add(); "reset";' | Out-Null
}

Note ''
Note ("{0} passed, {1} failed" -f $pass, $fail)
Save-ProbeResults -Path ($OutPath -replace '\.txt$', '.tsv')
[System.IO.File]::WriteAllLines($OutPath, $log)
Write-Output "Written to $OutPath"
