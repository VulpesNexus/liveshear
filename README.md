# Shear for Illustrator

A non-destructive **Shear** effect for Adobe Illustrator.

Illustrator can shear an object through *Object > Transform > Shear…*, but that rewrites the geometry in place. Its Appearance system has no equivalent: the built-in *Transform* effect offers move, scale, rotate, and reflect, and stops there. Shear is the one ordinary affine degree of freedom that never made it into the non-destructive stack. This plugin adds it.

Once installed, the effect appears at *Effect > Distort & Transform > Shear…*, takes a shear angle and an axis angle, previews live, and stays editable in the *Appearance* panel for as long as the document exists. The artwork underneath is never touched: text stays live text, paths stay editable paths, and deleting the effect gives you exactly what you started with.

## Requirements

- Adobe Illustrator 2026, 64-bit
- Windows 10 or 11
- No Visual C++ redistributable. The three runtime files the plugin uses are the same ones *Illustrator.exe* names itself, so a machine that can start Illustrator already has them.

**Verified on** Illustrator 30.7.0, 64-bit, Windows 11 build 10.0.26200 — that one configuration. It does **not** load in Illustrator 2025, which was tried; Windows 10 has not been run. See [Host versions](#host-versions).

## Installing

Quit Illustrator first. It reads its plugin folders only at startup.

There are two places to put *LiveShear.aip*, and **only one of them at a time**. Illustrator reads both folders, and it does not cope well with finding the plugin in both: under the same file name it says so and then ignores the whole additional folder, including anything else in it; under different file names it loads both copies and registers the effect twice, so the *Effect* menu gets two *Shear…* entries with no way to tell them apart.

### If you can install software on this machine

Copy *LiveShear.aip* into Illustrator's own plugin folder, which by default is

```
C:\Program Files\Adobe\Adobe Illustrator 2026\Plug-ins
```

That folder is under *Program Files*, so Windows asks for administrator rights. `.\tools\install.ps1` does the copy and asks for the rights it needs.

### If you cannot

You do not need administrator rights at all. Illustrator has always had a second place to look, and it can be anywhere you can write:

1. Make *%LOCALAPPDATA%\\Adobe Illustrator Plug-ins\\30* and put *LiveShear.aip* in it. The *30* is Illustrator 2026's version number; next year's Illustrator gets its own folder beside it, because a plugin built for one year is not guaranteed to load in another.
2. Start Illustrator, open *Edit > Preferences > Plug-ins & Scratch Disks*, tick **Additional Plug-ins Folder**, and choose that folder.
3. Restart Illustrator.

**That folder is shared with every other Illustrator plugin you install this way**, and it has to be: Illustrator has only one Additional Plug-ins Folder, so pointing it at a folder holding just this plugin stops any other one you installed there from loading. Put them all in the one folder — Illustrator loads them all.

This is worth knowing: on a machine where the signed-in account is an ordinary user rather than an administrator, Windows does not offer a button to click past — it asks for an administrator's password, which you may simply not have. The Additional Plug-ins Folder needs none.

`.\tools\sideload.ps1 -Path <folder>` sets the preference from a script, for when Illustrator is not the thing you want to be clicking through.

Either way: start Illustrator, and *Effect > Distort & Transform > Shear…* is there.

## Using it

Select some artwork and choose *Effect > Distort & Transform > Shear…*.

- **Shear Angle** is how far the artwork leans, in degrees, from −89° to 89°. Positive values lean the leading edge forward, the same direction Illustrator's own *Shear* command leans it.
- **Axis Angle** is the direction the shear runs along. At 0° the shear is horizontal, which is the familiar italic slant; at 90° it is vertical. An axis of φ and one of φ + 180° describe the same shear.
- **Preview** updates the artwork as you drag. *Cancel*, *Escape*, and the window's close button all put everything back exactly as it was; *OK* and *Enter* commit.
- The window takes its colors from Illustrator, so it matches whatever you have set under *Edit > Preferences > User Interface > Brightness*, down to the title bar. Illustrator applies that setting when it starts, so a dialog opened after you change it is the one that matches.
- The numeric fields take a decimal point or a decimal comma, ignore a degree sign, and respond to the up and down arrow keys — by ten degrees with *Shift* held. They work to a tenth of a degree, which is what the sliders carry and what the fields show.

## Where it shears about, and how it stacks

The artwork is sheared about the center of its **geometric** bounds — the Bézier outline, with strokes, effects, and the glyphs of area text left out. That is the same reference point *Object > Transform > Shear* uses, and it is measured rather than assumed: for each kind of artwork the suite can build, the effect and the native command are given the same angle and the difference between the two results is solved back into the distance between their reference points. That distance is zero for paths, compound paths, plain, nested, clipped, and transformed groups, point and area text, symbol instances, and embedded rasters.

Two of those are worth saying out loud, because Illustrator is not consistent about them:

- A **clipping group** anchors on its clip path, not on everything inside it — even though the geometric bounds Illustrator *reports* for such a group are the union of its children.
- **Area text** anchors on its frame, not on its glyphs, so a line whose ascenders overshoot the frame does not move the center.

The effect anchors on what the appearance pipeline hands it, not on the original object, and that is what makes it compose. An *Offset Path* or a *Transform* below the Shear grows or moves the artwork, and the shear's reference point moves with it — exactly as stacking two transforms should. So the result depends on where in the *Appearance* panel the Shear sits, which is the point of having a stack. Put the Shear at the bottom to anchor on the bare geometry.

That composition is checked in both directions rather than asserted: a *Transform* above a Shear renders what the same *Transform* renders above Illustrator's own shear, and a Shear above a *Transform* renders what Illustrator's own shear renders on that *Transform* expanded into real geometry. Two Shear effects on one object render as two successive native shears, and reordering, swapping, or deleting them behaves the way two transforms should.

## Uninstalling

Quit Illustrator and delete *LiveShear.aip* from wherever you put it, or run `.\tools\install.ps1 -Uninstall`. If you used the Additional Plug-ins Folder, `.\tools\sideload.ps1 -Restore` puts that preference back as it was.

Nothing else is installed: no services, no registry entries, no startup items, no temporary files. The plugin writes a trace file only when the `LIVESHEAR_LOG` environment variable names one, which it does not by default.

### Documents made with the effect, opened without it

Illustrator shows its standard missing-plugin warning, naming *Shear (LiveShear.aip)*, and then opens the document. The artwork still draws sheared, from the rendered result cached in the file. The source geometry is not expanded, not flattened, and not lost; text is still live text. What stops is the effect itself: editing the artwork will not re-shear it, so an edit made without the plugin renders against the old shape. Saving from that state loses nothing — put the plugin back and everything is live again.

This is Illustrator's standard behavior for any missing effect, not something particular to this one, but it is worth knowing before sending a file to someone who does not have the plugin.

## Known limitations

The full list, with what each one is and whether there is a way around it, is in [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md). [docs/SUPPORT_MATRIX.md](docs/SUPPORT_MATRIX.md) says which kinds of artwork are verified, which are untested, and which are not supported.

The short version: Windows only; the shear angle stops at ±89°; the reference point is always the center; brushed artwork cannot match the destructive command and no live effect can; display scaling above 100% and GPU preview are untested because no machine here could run them.

## Host versions

Everything claimed here was measured against Illustrator 30.7.0 on Windows 11.

This build is for **Illustrator 2026**. It was given its own folder and its own preference under Illustrator 2025, and Illustrator 2025 did not load it — so this is not a case of "probably fine on nearby versions." An earlier draft of this section said neighboring versions were expected to work; one of them was then tried, and it did not.

Whether a 2026 build will load in Illustrator 2027 is a different question, and an open one: that version does not exist yet, so it cannot be tried. Assume each Illustrator needs a build made for it, and keep each year's build in its own folder.

## For developers

- [docs/BUILDING.md](docs/BUILDING.md) — toolchain, SDK, project settings, how to run the tests, and the scripting bridge
- [docs/RELEASE_TEST_MATRIX.md](docs/RELEASE_TEST_MATRIX.md) — every check the test suite ran, and its result
- [docs/RELEASE_READINESS.md](docs/RELEASE_READINESS.md) — the release assessment, with evidence
- [LIVE_SHEAR_INVESTIGATION.md](LIVE_SHEAR_INVESTIGATION.md) — why this is a standalone effect rather than an extension of Adobe's *Transform*, and what was ruled out on the way

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

This project is not affiliated with, endorsed by, or connected to Adobe. *Adobe*, *Illustrator*, and *Adobe Illustrator* are trademarks of Adobe Inc.
