<#
.SYNOPSIS
    Runs every host probe in order and writes the evidence the release report
    cites.

.DESCRIPTION
    Illustrator has to be installed with the plugin and reachable over COM; the
    suite starts it if it is not already running. Tracing is turned on for the
    dialog and blend probes, which need it to see what the artwork did while a
    modal dialog was blocking every other way of asking, and whether Illustrator
    called a callback that nothing else can observe.

    Every probe that drives Illustrator gets a fresh one, because this host does
    not survive a whole suite in a single session. Pass -SameHost to run them
    all in one, which is faster and not reproducible.

    The crash experiment is not included: it takes the plugin out and puts it
    back, which is slow rather than difficult now that installing means copying
    a file into a folder this account owns. Run tools\probe-crash-ab.ps1
    separately.
#>
[CmdletBinding()]
param(
    [string] $TracePath = $env:LIVESHEAR_LOG,
    # Leaves out the two probes that take minutes rather than seconds: the
    # stability suite and the shutdown suite. Useful while iterating; never
    # for a release run.
    [switch] $SkipSlow,
    # Run every probe in one Illustrator session, the way the suite used to.
    # Faster, and not reproducible: see Reset-Host below.
    [switch] $SameHost,
    # Leave the built artifact alone.
    #
    # probe-build.ps1 rebuilds both configurations, which replaces the very
    # binary the rest of the suite is testing. MSVC stamps a link timestamp, so
    # the rebuilt file is not byte-identical to the installed one even from
    # identical source -- and then the artifact that was tested is not the
    # artifact that gets packed.
    #
    # For a release: commit, run probe-build.ps1 once to rebuild and record the
    # commit and hash, install that binary, run this suite with
    # -SkipBuildProbe, and pack with make-release.ps1 -SkipBuild.
    [switch] $SkipBuildProbe
)

$ErrorActionPreference = 'Continue'

# Python's own output is written in the machine's codepage when it is
# redirected, and the workspace path has an en dash in it. Without this a
# solver that prints its own file name dies on a UnicodeEncodeError rather than
# on anything to do with the measurements.
$env:PYTHONIOENCODING = 'utf-8'
. (Join-Path $PSScriptRoot 'ai.ps1')

$repo = Split-Path -Parent $PSScriptRoot
$evidence = Join-Path $repo 'docs\evidence'
$null = New-Item -ItemType Directory -Force -Path $evidence

$summary = New-Object Collections.Generic.List[string]
$script:hostRestarts = 0

# Illustrator 30.7.0 dies with an access violation under long runs of scripted
# document churn, with or without this plugin installed, and a full suite is
# exactly that kind of load. Losing every remaining probe to it would mean no
# matrix at all, so a probe that fails because the host went away is retried
# once against a fresh Illustrator, and the restart is counted and reported
# rather than hidden.
function Restart-IfHostDied([string] $message) {
    if ($message -notmatch 'RPC server is unavailable|remote procedure call failed|0x800706BA|0x800706BE|0x800706BF|RPC_E_|not reachable over COM|Illustrator did not quit|never became ready to run a script') { return $false }
    # Not conditional on the process having gone. A process that is still
    # listed but no longer answering COM is the same problem from here, and
    # waiting for it to disappear on its own loses the rest of the run.
    $lingering = Get-Process Illustrator -ErrorAction SilentlyContinue
    if ($lingering) {
        Write-Output 'Illustrator is still listed but not answering; ending it.'
        $lingering | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    $script:hostRestarts++
    Write-Output 'Illustrator is gone. Restarting it and trying this probe once more.'
    Start-Ai | Out-Null
    Install-AiHarness | Out-Null
    Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } app.documents.add(); "ready";' | Out-Null
    return $true
}

# A fresh Illustrator for each probe that drives one.
#
# Illustrator 30.7.0 does not survive a whole suite in one session. Three runs
# ended with an access violation inside Illustrator.exe, at three different
# fault offsets, always well into the run; a fourth did not crash outright but
# started failing checks that pass cleanly on their own -- forty reorders came
# back with eighteen errors where a fresh host gives eighteen passes out of
# eighteen. Both are the same thing: what accumulates in a session, not what
# any one probe does.
#
# Restarting between probes costs about half a minute each and removes the
# failure mode. It also makes the run reproducible, which matters more: a
# result that depends on how much work preceded it is not a measurement.
function Reset-Host {
    try { Stop-Ai | Out-Null } catch { }
    $lingering = Get-Process Illustrator -ErrorAction SilentlyContinue
    if ($lingering) { $lingering | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3 }
    try { Start-Ai | Out-Null }
    catch {
        # Illustrator can come up listed, holding two gigabytes, and never
        # answer a script at all. Waiting longer does not help; ending it and
        # starting again does.
        Write-Output 'Illustrator came up but would not run a script. Ending it and starting again.'
        Get-Process Illustrator -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Start-Ai | Out-Null
    }
    Install-AiHarness | Out-Null
    # A just-started Illustrator will answer a script before it will make a
    # document -- app.documents.add() comes back as error 8702, "there is no
    # document" -- so this is worth a couple of attempts. It is not fatal
    # either way: every probe goes through LS.doc(), which makes one if there
    # is none.
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-AiScript 'while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } app.documents.add(); "ready";' | Out-Null
            break
        }
        catch { Start-Sleep -Seconds 3 }
    }
}

function Run([string] $name, [scriptblock] $body, [switch] $NeedsHost) {
    Write-Output ''
    Write-Output ('=== {0} ===' -f $name)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    if ($NeedsHost -and -not $SameHost) {
        try { Reset-Host }
        catch { Write-Output ('could not give this probe a fresh Illustrator: ' + $_.Exception.Message) }
    }
    try {
        $out = & $body 2>&1
        $died = @($out | Where-Object { "$_" -match 'RPC server is unavailable|remote procedure call failed|0x800706BA|0x800706BE' })
        if ($died.Count -and (Restart-IfHostDied ($died -join ' '))) {
            Write-Output ('--- {0}, second attempt ---' -f $name)
            $out = & $body 2>&1
        }
        $out | ForEach-Object { Write-Output $_ }
        # A probe's own tally, not any tally. The solver self-test prints the
        # verdicts it reached on deliberately broken rows -- "2 passed, 3
        # failed" is that test working -- and reporting those as the probe's
        # result said three things had failed when nothing had.
        $lines = @($out | ForEach-Object { "$_" })
        $tail = ($lines | Where-Object { $_ -match '^\s*\d+ checks, \d+ failed' } | Select-Object -Last 1)
        if (-not $tail) { $tail = ($lines | Where-Object { $_ -match '^\s*\d+ passed, \d+ failed' } | Select-Object -Last 1) }
        $summary.Add(('{0,-22} {1,7:F0} s  {2}' -f $name, $sw.Elapsed.TotalSeconds, $tail))
    }
    catch {
        if (Restart-IfHostDied $_.Exception.Message) {
            try {
                Write-Output ('--- {0}, second attempt ---' -f $name)
                $out = & $body 2>&1
                $out | ForEach-Object { Write-Output $_ }
                $lines = @($out | ForEach-Object { "$_" })
                $tail = ($lines | Where-Object { $_ -match '^\s*\d+ checks, \d+ failed' } | Select-Object -Last 1)
                if (-not $tail) { $tail = ($lines | Where-Object { $_ -match '^\s*\d+ passed, \d+ failed' } | Select-Object -Last 1) }
                $summary.Add(('{0,-22} {1,7:F0} s  {2}  (after a host restart)' -f $name, $sw.Elapsed.TotalSeconds, $tail))
                return
            }
            catch { }
        }
        $summary.Add(('{0,-22} {1,7:F0} s  ERROR {2}' -f $name, $sw.Elapsed.TotalSeconds, $_.Exception.Message))
        Write-Output ("ERROR: " + $_.Exception.Message)
    }
}

# Not Get-AiApp: that returns as soon as the application registers itself, which
# is well before it will run a script, and the first probe then dies on an RPC
# error that looks like a crash.
if (-not (Get-Process Illustrator -ErrorAction SilentlyContinue)) { Start-Ai | Out-Null }
if (-not (Wait-AiReady)) { throw 'Illustrator is not answering; start it and try again.' }

# The plugin reads LIVESHEAR_LOG out of Illustrator's own environment. Setting
# it in this shell after Illustrator has started does nothing, and the dialog
# probe then cannot see what the artwork did behind a modal dialog. Restart
# once, here, rather than let a whole probe quietly lose its instrument.
if ($TracePath) {
    $env:LIVESHEAR_LOG = $TracePath
    Install-AiHarness | Out-Null
    $before = if (Test-Path $TracePath) { (Get-Item $TracePath).Length } else { -1 }
    Invoke-AiScript 'LS.clear(); LS.target = LS.fixtures["plainRect"](); LS.selectOnly(LS.target); LS.shear(7, 0); app.redraw();' | Out-Null
    $after = if (Test-Path $TracePath) { (Get-Item $TracePath).Length } else { -1 }
    if ($after -le $before) {
        Write-Output 'Illustrator is not writing the trace; restarting it so it inherits LIVESHEAR_LOG.'
        Restart-Ai | Out-Null
    }
}

Install-AiHarness | Out-Null
Invoke-AiScript 'app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS; while (app.documents.length > 0) { app.documents[0].close(SaveOptions.DONOTSAVECHANGES); } app.documents.add(); "ready";' | Out-Null

Write-Output ('Plugin: ' + ((Send-AiMessage version) -replace "`r?`n", ' | '))

Run 'solvers'     { python (Join-Path $PSScriptRoot 'test-solvers.py') (Join-Path $evidence 'solvers.tsv') }
if (-not $SkipBuildProbe) { Run 'built artifact' { & (Join-Path $PSScriptRoot 'probe-build.ps1') } }
else { Write-Output ''; Write-Output '=== built artifact ==='; Write-Output 'skipped, so the binary under test stays the one that was installed' }
Run 'arithmetic'  { & (Join-Path $PSScriptRoot 'run-mathtest.ps1') }
Run 'anchor'      { & (Join-Path $PSScriptRoot 'probe-anchor.ps1') } -NeedsHost
Run 'anchor verdicts' { python (Join-Path $PSScriptRoot 'solve-anchor.py') (Join-Path $evidence 'anchor.tsv') }
Run 'anchor by artwork' { & (Join-Path $PSScriptRoot 'probe-artwork-anchor.ps1') } -NeedsHost
Run 'bounds flags' { & (Join-Path $PSScriptRoot 'probe-bounds-flags.ps1') } -NeedsHost
Run 'release matrix' { & (Join-Path $PSScriptRoot 'probe-release.ps1') } -NeedsHost
Run 'matrix verdicts' { python (Join-Path $PSScriptRoot 'solve-release.py') (Join-Path $evidence 'release-matrix.tsv') }
Run 'appearance'  { & (Join-Path $PSScriptRoot 'probe-appearance.ps1') } -NeedsHost
Run 'persistence' { & (Join-Path $PSScriptRoot 'probe-persistence.ps1') } -NeedsHost
Run 'export'      { & (Join-Path $PSScriptRoot 'probe-export.ps1') } -NeedsHost
Run 'fills'       { & (Join-Path $PSScriptRoot 'probe-fills.ps1') } -NeedsHost
Run 'limits'      { & (Join-Path $PSScriptRoot 'probe-limits.ps1') } -NeedsHost
Run 'schema'      { & (Join-Path $PSScriptRoot 'probe-schema.ps1') } -NeedsHost
Run 'blend'       { & (Join-Path $PSScriptRoot 'probe-blend.ps1') -TracePath $TracePath } -NeedsHost
Run 'generated art' { & (Join-Path $PSScriptRoot 'probe-generated-art.ps1') } -NeedsHost
Run 'everyday use' { & (Join-Path $PSScriptRoot 'probe-everyday.ps1') } -NeedsHost
Run 'dialog'      { & (Join-Path $PSScriptRoot 'probe-dialog.ps1') -TracePath $TracePath } -NeedsHost
Run 'undo'        { & (Join-Path $PSScriptRoot 'probe-undo.ps1') } -NeedsHost
Run 'preview mode' { & (Join-Path $PSScriptRoot 'probe-gpu.ps1') } -NeedsHost
if (-not $SkipSlow) {
    Run 'stability' { & (Join-Path $PSScriptRoot 'probe-stability.ps1') } -NeedsHost
    # Illustrator applies its interface brightness only at startup, so proving
    # the dialog follows it costs a restart per setting and one more to put
    # the machine back.
    Run 'theme'     { & (Join-Path $PSScriptRoot 'probe-theme.ps1') } -NeedsHost
    # Shutdown restarts Illustrator four times, which is the other thing a
    # quick pass has no patience for.
    Run 'shutdown' { & (Join-Path $PSScriptRoot 'probe-shutdown.ps1') }
}
Run 'test matrix' { python (Join-Path $PSScriptRoot 'make-test-matrix.py') $evidence (Join-Path $repo 'docs\RELEASE_TEST_MATRIX.md') }
Run 'support matrix' { python (Join-Path $PSScriptRoot 'make-support-matrix.py') $evidence (Join-Path $repo 'docs\SUPPORT_MATRIX.md') }
Run 'registry'    {
    $r = Send-AiMessage registry
    [System.IO.File]::WriteAllText((Join-Path $evidence 'registry.txt'), $r)
    ($r -split "`n" | Select-Object -First 3) -join "`n"
}

Write-Output ''
Write-Output '=== summary ==='
$summary | ForEach-Object { Write-Output $_ }
if ($script:hostRestarts -gt 0) {
    Write-Output ''
    Write-Output ("Illustrator had to be restarted {0} time(s) during this run, because it stopped answering." -f $script:hostRestarts)
    Write-Output 'Check the Windows event log for Application Error records naming Illustrator.exe, and see the crash section of docs/RELEASE_READINESS.md.'
}
