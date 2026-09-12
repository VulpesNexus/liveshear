# Shear for Illustrator

A non-destructive **Shear** effect for Adobe Illustrator.

Illustrator can shear an object through *Object > Transform > Shear…*, but that rewrites the geometry in place. Its Appearance system has no equivalent: the built-in *Transform* effect offers move, scale, rotate, and reflect, and stops there. Shear is the one ordinary affine degree of freedom that never made it into the non-destructive stack. This plugin adds it.

Once installed, the effect appears at *Effect > Distort & Transform > Shear…*, takes a shear angle and an axis angle, previews live, and stays editable in the *Appearance* panel for as long as the document exists. The artwork underneath is never touched: text stays live text, paths stay editable paths, and deleting the effect gives you exactly what you started with.

## Requirements

- Adobe Illustrator 2026, version 30.7.0, 64-bit
- Windows 10 or 11

Other Illustrator versions are not supported yet. See [Host versions](#host-versions) for what that means in practice.

## Installing

1. Quit Illustrator. It reads its plugin folder only at startup.
2. Copy *LiveShear.aip* into Illustrator's plugin folder, which by default is

   ```
   C:\Program Files\Adobe\Adobe Illustrator 2026\Plug-ins
   ```

   That folder is under *Program Files*, so Windows will ask for administrator rights once.
3. Start Illustrator. *Effect > Distort & Transform > Shear…* is now there.

If you built the plugin yourself, `.\tools\install.ps1` does the copy and asks for the rights it needs.

## Using it

Select some artwork and choose *Effect > Distort & Transform > Shear…*.

- **Shear Angle** is how far the artwork leans, in degrees, from −89° to 89°. Positive values lean the leading edge forward, the same direction Illustrator's own *Shear* command leans it.
- **Axis Angle** is the direction the shear runs along. At 0° the shear is horizontal, which is the familiar italic slant; at 90° it is vertical. An axis of φ and one of φ + 180° describe the same shear.
- **Preview** updates the artwork as you drag. *Cancel*, *Escape*, and the window's close button all put everything back exactly as it was; *OK* and *Enter* commit.
- The numeric fields take a decimal point or a decimal comma, ignore a degree sign, and respond to the up and down arrow keys — by ten degrees with *Shift* held.

The artwork is sheared about the center of its geometric bounds, which is the same reference point *Object > Transform > Shear* uses.

The effect sits in the *Appearance* panel like any other. Double-click it to edit, drag it above or below other effects to change the order, and delete it to get the original artwork back. Two Shear effects on one object compose the way two transforms should.

## Uninstalling

Quit Illustrator and delete *LiveShear.aip* from the plugin folder, or run `.\tools\install.ps1 -Uninstall`. Nothing else is installed: no services, no registry entries, no startup items, no temporary files. The plugin writes a trace file only when the `LIVESHEAR_LOG` environment variable names one, which it does not by default.

### Documents made with the effect, opened without it

Illustrator shows its standard missing-plugin warning, naming *Shear (LiveShear.aip)*, and then opens the document. The artwork still draws sheared, from the rendered result cached in the file. The source geometry is not expanded, not flattened, and not lost; text is still live text. What stops is the effect itself: editing the artwork will not re-shear it, so an edit made without the plugin renders against the old shape. Saving from that state loses nothing — put the plugin back and everything is live again.

This is Illustrator's standard behavior for any missing effect, not something particular to this one, but it is worth knowing before sending a file to someone who does not have the plugin.

## Known limitations

The full list, with what each one does and whether there is a way around it, is in [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md). [docs/SUPPORT_MATRIX.md](docs/SUPPORT_MATRIX.md) says which kinds of artwork are verified, which are untested, and which are not supported.

## Host versions

Everything claimed here was measured against Illustrator 30.7.0 on Windows 11. The plugin is built against the Illustrator 2026 SDK and uses only documented, long-stable interfaces, so neighboring versions are *expected* to work — but expected is not verified, and nothing else has been host-tested. If you run it on another version, treat it as untested.

## For developers

- [docs/BUILDING.md](docs/BUILDING.md) — toolchain, SDK, project settings, and how to run the tests
- [docs/RELEASE_TEST_MATRIX.md](docs/RELEASE_TEST_MATRIX.md) — every check the test suite ran, and its result
- [docs/RELEASE_READINESS.md](docs/RELEASE_READINESS.md) — the release assessment, with evidence
- [LIVE_SHEAR_INVESTIGATION.md](LIVE_SHEAR_INVESTIGATION.md) — why this is a standalone effect rather than an extension of Adobe's *Transform*, and what was ruled out on the way

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

This project is not affiliated with, endorsed by, or connected to Adobe. *Adobe*, *Illustrator*, and *Adobe Illustrator* are trademarks of Adobe Inc.
