# Building Shear

Everything here was done on Windows 11 with Visual Studio 2022. The plugin is Windows-only today; nothing in the geometry is platform-specific, but the dialog is plain Win32 and has no counterpart on macOS yet.

## What you need

| | |
| --- | --- |
| Toolchain | Visual Studio 2022, *Desktop development with C++* workload (platform toolset v143, C++17) |
| Windows SDK | 10.0 or later, for *winres.h* and the DPI entry points |
| Illustrator SDK | Adobe Illustrator 2026 SDK, build 114 |
| Python | 3.x on *PATH* — the SDK's *tools/pipl/create_pipl.py* runs as a prebuild step |
| Architecture | x64 only |

The Adobe SDK is not redistributable, so it is not vendored in this repository and no path to it is baked into the project. Point at your own copy:

```powershell
$env:AI_SDK_ROOT = "<path to>\Adobe Illustrator 2026 SDK"
.\tools\build.ps1
```

`tools\build.ps1` refuses to run without *AI_SDK_ROOT* rather than guessing, and checks that the folder really is an Illustrator SDK before handing it to MSBuild. It takes `-Configuration Debug` as well; *Release* is the default and is what gets tested and shipped.

The build writes *build\Release\LiveShear.aip*.

## What the project settings are for

A few of them are not obvious, and all of them matter.

- **`/utf-8`** — the source carries a degree sign in a string literal, and without this the compiler reads it in the system codepage.
- **Warning level 4, with 4819 and 4828 disabled** — those two fire once per Adobe SDK header per translation unit, because the SDK headers are not UTF-8 and `/utf-8` makes the compiler say so. Neither can be triggered by our own sources. Nothing else is suppressed, and our sources build clean.
- **`/PDBALTPATH:$(TargetName).pdb`** — without it the linker stamps the absolute path of the build machine's symbol file into the shipped binary.
- **`/Zc:sizedDealloc-`** and 8-byte struct alignment — required by the SDK's own ABI.
- **`PluginMain.def`** from the SDK — the one exported entry point Illustrator looks for.
- **Its own version resource** — the SDK ships a *VersionInfo.rc* that stamps every sample with Adobe's company name, product name, and copyright. That is right for an Adobe sample and wrong for anything else, so *plugin/Resources/Win/LiveShear.rc* declares its own.

## Installing what you built

```powershell
.\tools\install.ps1              # copy into Illustrator's Plug-ins folder
.\tools\install.ps1 -Uninstall   # take it out again
```

Both ask for administrator rights once, because the plugin folder lives under *Program Files*.

For development that is the wrong way round, and on a machine where your account is not an administrator it is not available at all — Windows asks for an administrator's password rather than offering a button. Use Illustrator's Additional Plug-ins Folder instead, which needs no rights whatsoever:

```powershell
.\tools\sideload.ps1 -Path "$env:LOCALAPPDATA\LiveShear\Plug-ins"   # point Illustrator at a folder you own
.\tools\sideload.ps1 -Show                                          # what it is set to now
.\tools\sideload.ps1 -Restore                                       # put the setting back
```

The preference lives in Illustrator's own preferences file rather than anywhere a script can reach, so the tool edits that file; it refuses to run while Illustrator is open, because Illustrator rewrites the file when it exits and would undo the change. After that, deploying a new build is a file copy and a restart, with no prompt of any kind.

**Only one at a time.** If the same plugin is in both folders under the same file name, Illustrator says so and ignores the additional folder entirely. Under different file names it loads both and registers the effect twice.

Illustrator reads its plugin folders only at startup and holds the *.aip* open while it runs, so it has to be closed first; `tools\redeploy.ps1` does build, stop, install, and start in one step, and can turn the plugin's trace file on for the new session.

## Tracing

Set `LIVESHEAR_LOG` to a writable file path before starting Illustrator, and the effect records every evaluation: the art type it was handed, the angles it read, which bounds route answered, the anchor, and the matrix it applied. Read it back without leaving Illustrator with

```javascript
app.sendScriptMessage("LiveShear", "log", "");
```

Tracing is off when the variable is unset, which is the normal case.

## Running the tests

Two of them need no Illustrator at all. One rebuilds both configurations from clean and inspects the binary; the other compiles the arithmetic under the effect against a handful of stub types and checks it against brute-force sampling.

```powershell
.\tools\probe-build.ps1          # warnings, identity, linkage, embedded paths
.\tools\run-mathtest.ps1         # the affine algebra and the Bezier extremes
```

The arithmetic test exists because the bounds fallback — the code that measures the artwork itself when the host refuses to — only runs in a situation that cannot be arranged on demand, and code that never runs is code nobody has checked.

The rest of the suite drives a real Illustrator over COM; there is no mock. Start Illustrator, then:

```powershell
.\tools\probe-release.ps1        # every art type against the native shear command
python .\tools\solve-release.py  # turns the raw numbers into verdicts
.\tools\probe-appearance.ps1     # stack order, two instances, reorder, delete
.\tools\probe-persistence.ps1    # save, close, reopen, edit, save, reopen
.\tools\probe-export.ps1         # PDF and SVG
.\tools\probe-fills.ps1          # gradients and patterns, compared in pixels
.\tools\probe-stability.ps1      # identity, drift, performance, bulk documents
.\tools\probe-limits.ps1         # hostile parameter values
.\tools\probe-dialog.ps1         # the dialog, driven through the window manager
.\tools\probe-undo.ps1           # undo, redo, and how many steps an edit costs
.\tools\probe-anchor.ps1         # which bounds the native command anchors on
python .\tools\solve-anchor.py
```

Two more are run separately, because each has to take the plugin out and put it back:

```powershell
.\tools\probe-missing-plugin.ps1 -CrashTrials 6   # what a machine without it sees, and crash arm A
.\tools\probe-crash-ab.ps1 -SkipArmA              # crash arms B and C, interleaved
```

Arm A of the crash experiment runs inside the missing-plugin probe on purpose: that probe already arranges for the plugin to be absent, and arranging it twice would mean doing the same work again. Installed through the Additional Plug-ins Folder, taking it out is deleting a file you own, so neither of these needs administrator rights any more.

And one that is only worth running when the host has just died:

```powershell
.\tools\probe-sequence-crash.ps1 -Trials 3        # the same work with and without the effect
```

Or all the rest in order, which also regenerates the matrix:

```powershell
.\tools\run-release-suite.ps1
```

Each writes its raw output under *docs/evidence/*. [RELEASE_TEST_MATRIX.md](RELEASE_TEST_MATRIX.md) is generated from those files.

The measurement library the probes share is *tools/harness.jsx*. Illustrator keeps the globals of one `DoJavaScript` call alive for the next, so it is sent once per session and every probe afterward is a short call into `LS.*`. Its fixtures are deliberately asymmetric: a centered square cannot tell a geometric anchor from a visible one.

## The scripting bridge

The plugin answers `app.sendScriptMessage("LiveShear", selector, arguments)` with a set of selectors used by the probes: `version`, `log`, `registry`, `appearance`, `selection`, `geometry`, `matrix`, `apply effect`, `set param`, `delete param`, `move effect`, `remove effect`, `count effects`, `bounds`, `bounds flags`, `edit effect`, and `native shear`.

**Status: a test interface, not a public API.** It is unsupported, undocumented beyond this paragraph, and carries no stability guarantee whatsoever: selectors may change meaning, change arguments, or disappear between any two versions without a note. Do not build anything on it.

It is in the shipped binary on purpose, so that the binary which passes the tests is the binary that ships — a test suite that runs against a different build than the one users get is testing the wrong thing. Two questions follow from shipping it, and both have been answered rather than assumed:

**Does it grant anything?** No. Everything it reaches is reachable through Illustrator's own scripting and action interfaces, which any script already has. `native shear` plays Illustrator's own shear action; `apply effect` applies an effect by name; the rest read state or edit this plugin's own parameters. There is no file, network, or process access in any of it.

**Can a malformed message hurt the host?** Every argument is parsed defensively. Numbers go through `atof`, which yields zero rather than throwing on nonsense; missing fields take documented defaults; and every index that reaches a host API is range-checked first against the actual number of post-effects — including the destination index of `move effect`, which was not, and which would otherwise have handed `InsertNthPostEffect` whatever a caller sent. A selector that is not recognized returns a message and does nothing.

If you would rather it were not there at all, `HandleScriptMessage` in *LiveShearPlugin.cpp* is the only entry point; removing the `kCallerAIScriptMessage` branch in `Message` removes the whole surface. The test suite stops working at that point, which is the trade.
