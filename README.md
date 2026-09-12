# Live Shear

A non-destructive **Shear** effect for Adobe Illustrator, and the investigation that produced it.

Illustrator can shear an object destructively through *Object > Transform > Shear…*, but its Appearance system has no equivalent: the built-in *Transform* effect offers move, scale, rotate, and reflect, and stops there. Shear is the one ordinary affine degree of freedom that never made it into the non-destructive stack. This repository adds it back as a first-class live effect.

Once installed, the effect appears at *Effect > Distort & Transform > Shear…*, takes a shear angle and an axis angle, previews live, and stays editable in the *Appearance* panel for as long as the document exists.

## Status

Working proof of concept, verified in Illustrator rather than reasoned about. The effect renders geometry identical to *Object > Transform > Shear* to six decimal places, and 24 behavior checks and 4 dialog checks pass against a live host: text stays live, the effect survives save, reopen, copy, paste, and undo, two instances coexist independently, and a machine without the plugin loses nothing.

Not production-ready yet. See [LIVE_SHEAR_INVESTIGATION.md](LIVE_SHEAR_INVESTIGATION.md) for what has been proven, what has not, and why the architecture is what it is — section J lists the open questions, of which the anchor using visible rather than geometric bounds is the one most likely to be noticed.

## Requirements

- Adobe Illustrator 2026 (30.7.0) on Windows, 64-bit.
- To build: Visual Studio 2022 with the C++ desktop workload, Python 3 on *PATH*, and a copy of the Adobe Illustrator 2026 SDK. The SDK is not redistributable, so it is not vendored here.

## Building

```
$env:AI_SDK_ROOT = "<path to>\Adobe Illustrator 2026 SDK"
.\tools\build.ps1
```

The build writes *build\Release\LiveShear.aip*.

## Installing

```
.\tools\install.ps1
```

This copies the plugin into Illustrator's *Plug-ins* folder, asking for administrator rights once. Illustrator reads that folder only at startup, so quit and reopen it afterward. To remove the plugin again, run `.\tools\install.ps1 -Uninstall`.

## Using it

Select some artwork and choose *Effect > Distort & Transform > Shear…*.

- **Shear Angle** is how far the artwork leans, in degrees. Positive values lean the leading edge forward.
- **Axis Angle** is the direction the shear runs along. At 0° the shear is horizontal, which is the familiar italic slant; at 90° it is vertical.
- **Preview** updates the artwork as you drag; *Cancel* restores it exactly.

The effect sits in the *Appearance* panel like any other. Double-click it to edit, drag it above or below other effects to change the order, and delete it to get the original artwork back. Text stays live text, paths stay editable paths.

## Repository layout

| Path | What is in it |
| --- | --- |
| *plugin/* | The plugin source and its Visual Studio project |
| *tools/* | Build, install, and the probe scripts that produced the evidence |
| *fixtures/* | The controlled test document, built by script |
| *docs/evidence/* | Raw output of every host probe |
| *LIVE_SHEAR_INVESTIGATION.md* | The investigation report |

## License

GPL-3.0-or-later.
