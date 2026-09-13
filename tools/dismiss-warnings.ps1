<#
.SYNOPSIS
    Presses OK on Illustrator's own modal warnings while a probe runs.

.DESCRIPTION
    Opening a document whose effects are missing raises Illustrator's warning
    dialog -- the one the missing-plugin probe exists to observe:

        The document 'shear-with-plugin.ai' contains elements that are managed
        by plug-ins that are not currently available. ... Shear (LiveShear.aip)

    A modal blocks the scripting call that raised it, so nothing in the probe's
    own process can dismiss it: the probe is inside that call, waiting. It has
    to come from somewhere else.

    app.userInteractionLevel = DONTDISPLAYALERTS does not cover this one. That
    suppresses alerts a script causes; this is raised while a document opens.

    Start it before the probe and it presses OK on anything titled "Adobe
    Illustrator" until its time runs out:

        $job = Start-Job -FilePath .\tools\dismiss-warnings.ps1 -ArgumentList 10
        .\tools\probe-missing-plugin.ps1
        Receive-Job $job -Wait | Out-Null

    It is deliberately narrow: only windows of class #32770 whose title is
    exactly "Adobe Illustrator". The effect's own dialog has its own class and
    is never touched, so a probe driving that is unaffected.
#>
param([int] $Minutes = 10)

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class AiWarning {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static int DismissAll() {
        var hits = new List<IntPtr>();
        EnumWindows(delegate(IntPtr h, IntPtr p) {
            if (!IsWindowVisible(h)) return true;
            var c = new StringBuilder(64);
            GetClassNameW(h, c, 64);
            var t = new StringBuilder(160);
            GetWindowTextW(h, t, 160);
            if (c.ToString() == "#32770" && t.ToString() == "Adobe Illustrator") { hits.Add(h); }
            return true;
        }, IntPtr.Zero);
        foreach (var h in hits) {
            PostMessage(h, 0x0100, (IntPtr) 0x0D, IntPtr.Zero);
            PostMessage(h, 0x0101, (IntPtr) 0x0D, IntPtr.Zero);
        }
        return hits.Count;
    }
}
"@

$total = 0
$deadline = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $deadline) {
    $total += [AiWarning]::DismissAll()
    Start-Sleep -Milliseconds 800
}
"dismissed $total Illustrator warning(s)"
