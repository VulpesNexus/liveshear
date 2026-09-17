# Known limitations

What Shear does not do, or does differently from what you might expect.

Each entry says what kind of thing it is, because they are not all the same kind:

- **Product limitation** — this plugin could do it and does not.
- **Support boundary** — outside what has been tested, not known to be broken.
- **Host behavior** — Illustrator does this, to every effect, and the plugin follows.
- **Untested** — nobody has been able to run it, and it is not claimed either way.

Behavior that is simply how the effect works — how it composes with other effects, where it anchors — is described in [docs/BEHAVIOR.md](docs/BEHAVIOR.md) rather than here. Problems that were found and fixed are not listed at all. The evidence behind every entry is in [docs/RELEASE_TEST_MATRIX.md](docs/RELEASE_TEST_MATRIX.md) and [docs/evidence/](docs/evidence/).

## Windows only

**Product limitation.** The geometry is platform-neutral but the dialog is plain Win32, so there is no macOS build. **Affected:** everyone on a Mac. **Workaround:** none. **Planned:** the dialog is the only thing standing in the way; it is perhaps two hundred lines of Cocoa.

## One host version has been tested

**Support boundary.** Everything measured here was measured on Illustrator 2026, version 30.7.0, 64-bit. This build is for that version: given its own folder and its own preference under **Illustrator 2025, it did not load at all**. An earlier version of this entry said neighboring versions were expected to work; one was then tried, and that expectation was wrong. Whether a 2026 build loads in Illustrator 2027 cannot be tested until that version exists. **Affected:** anyone on another version. **Source art is safe** either way: a plugin that fails to load cannot damage a document. **Workaround:** none for an older Illustrator — it needs a build made against that version's SDK. If the effect does not appear in the *Effect* menu, the plugin did not load. **Planned:** a build per Illustrator generation, each in its own folder.

## One version of Windows has been tested

**Support boundary.** Every measurement was taken on Windows 11, build 10.0.26200. Windows 10 is *expected* to work and is not verified: the plugin calls `GetDpiForWindow`, which arrived in Windows 10 version 1607, and everything else it uses is older than that, so there is a concrete reason to expect it rather than only hope. It has not been run there. **Affected:** anyone on Windows 10. **Workaround:** none needed if it works. **Planned:** testing when a Windows 10 machine is at hand.

## The shear angle stops at 89 degrees

**Product limitation, and deliberate.** Illustrator itself becomes pathological as a shear approaches a right angle: a native shear of 89° returns at once; one of 89.9° did not return at all in the run that measured it, and had to be killed. The effect therefore refuses anything past ±89°, wherever the value comes from — the slider, the numeric field, a pasted string, a parameter dictionary written by another script, or a document that somehow stores 90. **Affected:** nobody in practice — tan(89°) is about 57, so a 100 pt object already becomes 5,700 pt wide. **Workaround:** stack two Shear effects if you genuinely need more. **Planned:** no.

## The dialog works to a tenth of a degree

**Product limitation.** The sliders carry tenths of a degree and the fields show one decimal, so that is the resolution the dialog offers: type 18.25 and it becomes 18.3, which is what the field then shows and what gets stored. A script writing the parameter dictionary directly is not limited this way — the effect honors whatever angle it is given, to full precision. **Affected:** anyone wanting a hundredth of a degree from the dialog. **Workaround:** set it from a script. **Planned:** possibly, if anyone wants it; 0.1° on a 100 pt object is 0.17 pt.

## The reference point is always the center

**Product limitation.** Illustrator's own *Shear* dialog offers an origin offset, and the *Transform* effect offers a nine-point pin. This effect offers neither: it shears about the center of the incoming artwork's geometric bounds, which is what *Object > Transform > Shear* does when no other origin is given. **Affected:** anyone who wants to shear about a corner. **Workaround:** put a *Transform* effect below the Shear to move the artwork, shear, and move it back; the two compose exactly. **Planned:** a reference-point control is the most likely next addition, and the parameter block carries a schema number so it can be added without orphaning documents written by this version — which is measured, not assumed: a block carrying a later version's keys survives this version reading and writing it.

## Brushed artwork does not match the destructive command, and cannot

**Host behavior.** A brush is not artwork, it is a rule for making artwork out of a path, and that leaves two different right answers. *Object > Transform > Shear* shears the path and then lays the brush along it again. A live effect is handed the art the brush has already produced and can only shear that, because the brush definition is not what arrives and there is no way back to it.

This is not particular to this effect. Adobe's own *Transform* effect does not match Adobe's own command on a brushed path either: scaled to a quarter height, the two routes differ over 1.3% of the sampled pixels on a pattern brush, while a plain rectangle and a stroked rectangle put through the same comparison differ in not one pixel. See [docs/evidence/generated-art.txt](docs/evidence/generated-art.txt).

**Affected:** anyone shearing a calligraphic, art, or pattern brush and expecting the two routes to agree exactly. **Source art is safe.** **Workaround:** expand the appearance first if you need the destructive result. **Planned:** nothing can be done about it.

## Edits made through the scripting bridge are not always undo steps

**Product limitation, on a surface no person touches.** The plugin answers `app.sendScriptMessage("LiveShear", …)` with a set of selectors the test suite drives it through. Deleting an effect and reordering the stack through that bridge each cost one undo step, and undo leaves the document coherent; a parameter edit made through it is not an undo step at all. **Affected:** only scripts that drive the bridge. Nothing a person does in the interface goes through it, and editing the effect in the *Appearance* panel costs exactly one undo step however long the drag. **Workaround:** none needed. The bridge is a test interface and is documented as unsupported in [docs/BUILDING.md](docs/BUILDING.md).

## The dialog has not been seen on a display above 100%

**Untested.** It is measured at 96 dots per inch, where it is 448 by 233 pixels with nothing clipped and every control reachable, and a picture of it is in [docs/evidence/dialog.png](docs/evidence/dialog.png). No display that would scale it was available, and *the release notes do not claim scaling works*.

What can be said without a monitor is arithmetic, and it is checked rather than asserted: every control's box comes from one table, multiplied through one function, and the test walks that table at 100%, 125%, 150%, 200%, and 250% checking that nothing leaves the window, nothing lands on top of anything else, every control a person can tab to stays at least sixteen pixels across, and the tab order still reads left to right and top to bottom. That covers the layout. It does not cover font substitution or the trackbar's own idea of its minimum height, which is why this says untested rather than verified. **Affected:** anyone running Windows above 100% scaling. **Workaround:** none needed if it works; the failure mode would be cosmetic rather than a control you cannot reach.

## GPU and CPU preview were not compared

**Untested, because the machine has no GPU preview.** Illustrator reports CPU preview in its window title and neither the *Ctrl+E* shortcut nor any menu command switches it, which is what happens when the machine has no GPU that Illustrator will use. The capture that would have made the comparison was verified to work by moving the artwork and watching the picture change, so this is an absent mode rather than a broken test. The effect produces art objects and never draws anything itself, so a difference between the two paths could only come from Illustrator's own renderer — but that is an argument, not a measurement. **Affected:** unknown. **Workaround:** none needed; exports are measured separately and are correct.

## Documents opened without the plugin keep drawing, but stop updating

**Host behavior.** Illustrator shows its standard missing-plugin warning, opens the document, and draws the artwork sheared from the result cached in the file. The source geometry is not expanded, not flattened, and not lost, and text stays live. What stops is the effect: edit the text on a machine without the plugin and the drawn shape stays frozen at the old shape while the text underneath changes. Saving from that state loses nothing — reopen with the plugin back and everything is live again. **Affected:** anyone sending files to someone without the plugin. **Workaround:** expand the appearance before sending, if the recipient needs to edit. **Planned:** nothing can be done about it; this is how Illustrator treats every missing effect.

## Two copies installed at once give two Shear commands

**Host behavior, and worth knowing before you install.** If the plugin is in Illustrator's own *Plug-ins* folder *and* in the Additional Plug-ins Folder under the same file name, Illustrator notices, says so, and ignores the additional folder entirely — including any other plugin in it. Under different file names it loads both, and the effect is then registered twice: two *Shear…* entries in the *Effect* menu, and no way to tell which is which. **Affected:** anyone who installs it twice. **Workaround:** install it in one place. See [README.md](README.md) for the two ways.

## Illustrator crashes under repeated scripted document churn

**Host defect.** Creating and closing documents over and over through Illustrator's scripting interface kills Illustrator 30.7.0 with an access violation inside *Illustrator.exe*.

What is proven is that **this plugin is not necessary for the crash**: it happens with the plugin uninstalled. What is *not* proven is that having the plugin loaded makes no difference to how often it happens — that is a comparison between arms of an experiment, and the arms are noisy. The crash section of [docs/RELEASE_READINESS.md](docs/RELEASE_READINESS.md) gives the numbers and says exactly what they do and do not support.

**Affected:** scripts that churn documents, not people using Illustrator: nothing a person does in the interface creates and destroys documents at that rate. **Workaround:** reuse one document and empty it between operations.

## Illustrator clamps artwork past about 12,000 points from the origin

**Host behavior.** A fixture placed at 12,000 by 9,000 points came back clamped to something else entirely; at 4,000 by 3,000 it is placed exactly as asked. This is Illustrator's canvas limit, not the effect's, and it applies whether or not the plugin is installed. It is here only because a test fixture met it. **Affected:** nobody working inside the canvas. **Workaround:** none needed.
