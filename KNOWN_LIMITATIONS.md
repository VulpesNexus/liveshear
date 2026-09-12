# Known limitations

What Shear does not do, or does differently from what you might expect. Everything here is a limitation that still stands; problems that were found and fixed are not listed. The evidence behind each one is in [docs/RELEASE_TEST_MATRIX.md](docs/RELEASE_TEST_MATRIX.md) and [docs/evidence/](docs/evidence/).

## Windows only

The geometry is platform-neutral but the dialog is plain Win32, so there is no macOS build. **Affected:** everyone on a Mac. **Workaround:** none. **Planned:** the dialog is the only thing standing in the way; it is perhaps two hundred lines of Cocoa.

## One host version has been tested

Illustrator 2026, version 30.7.0, 64-bit, on Windows 11. The plugin is built against the Illustrator 2026 SDK and uses only documented, long-stable interfaces, so neighboring versions are expected to work — but expected is not verified, and nothing else has been run. **Affected:** anyone on another version. **Source art is safe** either way: a plugin that fails to load cannot damage a document. **Workaround:** try it; if the effect does not appear in the *Effect* menu, the plugin did not load. **Planned:** testing widens as versions become available.

## The shear angle stops at 89 degrees

Illustrator itself becomes pathological as a shear approaches a right angle. A native shear of 89° returns at once; one of 89.9° did not return at all in the run that measured it, and had to be killed. The effect therefore refuses anything past ±89°, wherever the value comes from: the slider, the numeric field, a pasted string, a parameter dictionary written by another script, or a document that somehow stores 90. **Affected:** nobody in practice — tan(89°) is about 57, so a 100 pt object already becomes 5,700 pt wide. **Workaround:** stack two Shear effects if you genuinely need more. **Planned:** no.

## The reference point is always the center

Illustrator's own *Shear* dialog offers an origin offset, and the *Transform* effect offers a nine-point pin. This effect offers neither: it shears about the center of the incoming artwork's geometric bounds, which is what *Object > Transform > Shear* does when no other origin is given. **Affected:** anyone who wants to shear about a corner. **Workaround:** put a *Transform* effect below the Shear to move the artwork, shear, and move it back; the two compose exactly. **Planned:** a reference-point control is the most likely next addition, and the parameter block already carries a schema number so it can be added without orphaning documents written by this version.

## Geometry-changing effects below it move the reference point

The effect anchors on what it is handed, not on the original object. That is what makes it compose: an *Offset Path* or a *Transform* below the Shear grows or moves the artwork, and the shear's reference point moves with it, exactly as stacking two transforms should. It does mean the result depends on where in the *Appearance* panel the Shear sits, which is the point of having a stack. **Affected:** anyone reordering the stack and expecting the shear to stay put. **Workaround:** put the Shear at the bottom of the stack to anchor on the bare geometry.

## GPU and CPU preview were not compared

The comparison could not be made on the machine the suite runs on: Illustrator reports CPU preview in its window title and neither the *Ctrl+E* shortcut nor any menu command switches it, which is what happens when the machine has no GPU that Illustrator will use. The capture that would have made the comparison was verified to work by moving the artwork and watching the picture change, so this is an absent mode rather than a broken test. The effect produces art objects and never draws anything itself, so a difference between the two paths could only come from Illustrator's own renderer — but that is an argument, not a measurement, and it is recorded as untested. **Affected:** unknown. **Workaround:** none needed; exports are measured separately and are correct.

## Documents opened without the plugin keep drawing, but stop updating

Illustrator shows its standard missing-plugin warning, opens the document, and draws the artwork sheared from the result cached in the file. The source geometry is not expanded, not flattened, and not lost, and text stays live. What stops is the effect: edit the text on a machine without the plugin and the drawn shape stays frozen at the old shape while the text underneath changes. Saving from that state loses nothing — reopen with the plugin back and everything is live again. **Affected:** anyone sending files to someone without the plugin. **Workaround:** expand the appearance before sending, if the recipient needs to edit. **Planned:** nothing can be done about it; this is how Illustrator treats every missing effect.

## Edits made through the scripting bridge are not undo steps

The plugin answers `app.sendScriptMessage("LiveShear", …)` with a set of selectors the test suite drives it through, and those rebuild the art style through the SDK directly rather than as one of Illustrator's own operations. Undo does not step back over them one at a time. **Affected:** only scripts that drive the bridge; nothing a person does in the interface goes through it. Editing the effect in the *Appearance* panel costs one undo step, however long the drag. **Workaround:** none needed.

## Blending two Shear effects is implemented but unexercised

The effect implements Illustrator's interpolation callback, so a blend between two objects carrying different Shear parameters should interpolate the angles — taking the shorter way round modulo 180°, which is the axis's real period. No test drives it. **Affected:** anyone blending sheared objects. **Workaround:** none needed if it works; report it if it does not.

## Illustrator crashes under repeated scripted document churn

Not this plugin's doing, and measured rather than assumed. Creating and closing documents over and over through Illustrator's scripting interface kills Illustrator 30.7.0 with an access violation inside *Illustrator.exe*, and it does so with this plugin uninstalled. See the crash section of [docs/RELEASE_READINESS.md](docs/RELEASE_READINESS.md) for the three-arm experiment and what it does and does not establish. **Affected:** scripts that churn documents, not people using Illustrator. **Workaround:** reuse one document and empty it between operations.

## Illustrator clamps artwork past about 12,000 points from the origin

A fixture placed at 12,000 by 9,000 points came back clamped to something else entirely; at 4,000 by 3,000 it is placed exactly as asked. This is Illustrator's canvas limit, not the effect's, and it applies whether or not the plugin is installed. **Affected:** nobody working inside the canvas. **Workaround:** none needed.
