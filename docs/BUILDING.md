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

Both ask for administrator rights once, because the plugin folder lives under *Program Files*. Illustrator reads that folder only at startup and holds the *.aip* open while it runs, so it has to be closed first; `tools\redeploy.ps1` does build, stop, install, and start in one step, and can turn the plugin's trace file on for the new session.

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

It exists because the bounds fallback — the code that measures the artwork itself when the host refuses to — only runs in a situation that cannot be arranged on demand, and code that never runs is code nobody has checked.

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

Or all of them in order, which also regenerates the matrix:

```powershell
.\tools\run-release-suite.ps1
```

Each writes its raw output under *docs/evidence/*. [RELEASE_TEST_MATRIX.md](RELEASE_TEST_MATRIX.md) is generated from those files.

The measurement library the probes share is *tools/harness.jsx*. Illustrator keeps the globals of one `DoJavaScript` call alive for the next, so it is sent once per session and every probe afterward is a short call into `LS.*`. Its fixtures are deliberately asymmetric: a centered square cannot tell a geometric anchor from a visible one.

## The scripting bridge

The plugin answers `app.sendScriptMessage("LiveShear", selector, arguments)` with a set of selectors used by the probes: `version`, `log`, `registry`, `appearance`, `selection`, `geometry`, `matrix`, `apply effect`, `set param`, `delete param`, `move effect`, `remove effect`, `count effects`, `bounds`, `edit effect`, and `native shear`. It is in the shipped binary on purpose, so that the binary which passes the tests is the binary that ships. It grants no privilege a script does not already have — anything it can reach is reachable through Illustrator's own scripting and action interfaces.
