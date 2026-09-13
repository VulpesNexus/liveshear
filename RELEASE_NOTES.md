# Release notes

## 0.1.0

The first stable release, and 0.1.0-rc.6 with the suffix taken off: the only change to the plugin is the version it reports. Nothing about the geometry, the dialog, the menu item, or the parameter handling is different from the last candidate, and the whole suite was run again against this exact binary rather than carried over from it — the counts and every individual result are in [docs/RELEASE_TEST_MATRIX.md](docs/RELEASE_TEST_MATRIX.md).

The README is shorter. Where the shear anchors and how it stacks, which had grown into the longest section in it, is now [docs/BEHAVIOR.md](docs/BEHAVIOR.md); the README keeps the part a person needs in order to use the effect and links to the rest.

What the release candidates below added, in one list: the dialog opens in the middle of Illustrator rather than the corner of the screen, it is drawn in Illustrator's own colors, the effect is at *Effect > Shear…* on the *Effect* menu itself, there is a proper About window under *Help > About VulpesNexus Plug-ins*, and the plugin installs into the shared plugin folder alongside your other Illustrator plugins.

## 0.1.0-rc.6

Everything in rc.5, and:

- **The dialog opens in the middle of Illustrator's window**, where the host puts its own, instead of in the top-left corner of the primary monitor. It was created with `CW_USEDEFAULT` for its position, which reads like "let Windows choose" and is not: that value applies to overlapped windows only, and for a popup — which this dialog is — the coordinates are documented to be taken as zero. So it was not falling back to a corner, it was being placed there, every time. It is now centered on Illustrator and then pushed back inside the work area of whatever monitor that lands on, so a window against a screen edge cannot put it half off the desktop or under the taskbar.

- **The dialog probe looks at where the window opened**, which nothing had ever done — it measured the dialog's size, its caption, its labels, and everything it did, and never once a coordinate. It now compares the dialog's center against Illustrator's, and checks the window lands entirely inside the monitor work area. The edge case is driven rather than assumed: Illustrator is moved until its own middle is 60 pixels from the desktop edge, far closer than half a dialog, and the dialog has to come back on screen from there.

- **A new illustration in the README**, showing the effect on live type with the *Appearance* panel beside it, rather than the dialog on its own.

## 0.1.0-rc.5

Everything in rc.4, and:

- **The effect is at *Effect > Shear…* now**, on the *Effect* menu itself rather than in a submenu. It used to register the category *Distort & Transform*, which looked like it would put it in Illustrator's submenu of that name and does not: Illustrator files a third-party category under a group it names *Live 3rd Party* plus the category, so what appeared was a **second** *Distort & Transform* submenu next to Adobe's — and since that group name is also the submenu's label, and labels go through Windows mnemonic handling, the bare ampersand was eaten and it read *Distort  Transform*.

  Adobe's own submenu can in fact be reached, by creating that third-party group next to Adobe's before the host creates it. It was built and measured, and it is not shipped: an item placed there stops responding to *Effect > Apply Last Effect*, which then returns without error and does nothing. The tables are in [LIVE_SHEAR_INVESTIGATION.md](LIVE_SHEAR_INVESTIGATION.md#where-the-menu-item-goes).

- **The About window shows the name and the release**, *Shear 0.1.0*, instead of the product name and the build string. The release-candidate suffix belongs on the download; it is still on the *.aip*'s file version and in the archive name, so a binary can still be traced back to the release it came from. The two forms are now built from the same three numbers and checked against each other at compile time.

- **The About window says what happens without the plugin.** A document made with the effect still draws the shear on a machine that does not have it; it just cannot be edited there. That was already in the README and is now in the window itself, where someone about to send a file will see it.

- **An About-dialog harness**, at *tools/AboutHarness/*, which builds the plugin's own dialog and resource into a standalone executable so the window can be looked at — in both themes — without Illustrator. The prose does not scroll and nothing warns when it overflows, so this is how the wording above got checked.

## 0.1.0-rc.4

Everything in rc.3, and:

- **A proper About window**, at *Help > About VulpesNexus Plug-ins > Shear…*, replacing the plain text alert the SDK's helper puts up. It is the same window *Subgroup* shows — same layout, same two bands, same controls — because every Illustrator plugin here wears one About box, and it takes its colors from Illustrator like the Shear dialog does, down to the title bar.
- **One menu group for every plugin from this publisher.** Adobe's default files third-party plugins under *About SDK Plug-ins*, which reads as though they were Adobe's own samples. Both this plugin and *Subgroup* now appear under *About VulpesNexus Plug-ins* instead — verified by asking Illustrator for its menu groups, which reports one publisher group and no SDK one.
- **An INSTALL.txt in the archive**, because a tester double-clicked *LiveShear.aip* and got Illustrator's *"the file format is unknown"* alert. That alert means Illustrator tried to *open* the plugin as artwork; nothing is wrong with the file. The new file says so before it says anything else.

## 0.1.0-rc.3

Everything in rc.2, and:

- **The dialog is drawn in Illustrator's own colors.** It asks the host what it paints its dialogs with and uses that — background, text, fields, borders, focus ring, and the title bar — so it matches whatever *Edit > Preferences > User Interface > Brightness* is set to instead of being a light gray Windows box in a dark application. Measured rather than eyeballed: driven from Illustrator's darkest setting to its lightest, the dialog's own pixels go from RGB(50,50,50) to RGB(240,240,240), following the host both times. Illustrator applies that preference when it starts, so the dialog that matches is one opened after a restart.
- **It does not load in Illustrator 2025.** Now tried rather than assumed: given its own folder and its own preference, Illustrator 2025 did not load this build. rc.2's notes said neighboring versions were expected to work. One was tried, and that was wrong. Whether a 2026 build loads in Illustrator 2027 cannot be known until that version exists.
- **Install into the shared plugin folder**, *%LOCALAPPDATA%\\Adobe Illustrator Plug-ins\\30*, alongside your other Illustrator plugins. Illustrator has only one Additional Plug-ins Folder, so a folder holding this plugin alone stops the others from loading.

Nothing about the shear itself changed: the geometry, the reference point, persistence, and the parameter handling are the same code, re-measured against this binary.

## 0.1.0-rc.2

First release candidate that has been run in Illustrator. Every bullet below was measured against the binary being packaged, not against an earlier one; what was not measured is not claimed. [docs/RELEASE_TEST_MATRIX.md](docs/RELEASE_TEST_MATRIX.md) lists every check and its result, and [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) lists what it does not do.

A non-destructive **Shear** effect for Adobe Illustrator, at *Effect > Distort & Transform > Shear…*.

- Shears artwork by an angle along an axis, and stays editable in the *Appearance* panel.
- Anchors on the same reference point *Object > Transform > Shear* does — the center of the artwork's geometric bounds. Checked one kind of artwork at a time, along two axes each: paths open, closed, compound, and self-intersecting; groups plain, nested, clipped, and transformed; point, area, multi-line, and edited text; symbol instances; and embedded rasters. Where the two disagreed, the effect was wrong and was fixed.
- Leaves the artwork underneath alone. Text stays live text, paths stay editable paths, and deleting the effect gives back exactly what you started with. Every case checks the source path's own anchors, not just how it looks.
- Composes in either stack order. A *Transform* above a Shear renders what that *Transform* renders above Illustrator's own shear; a Shear above a *Transform* renders what Illustrator's own shear renders on that *Transform* expanded into real geometry; and the two orders differ from each other.
- Two Shear effects on one object render as two successive native shears. Forty reorders leave the result unchanged, swapping them changes it, and deleting one leaves the other intact.
- Survives save, close, reopen, and a second round trip, on paths, live text, stroked art, two instances, and Shear stacked with *Transform*.
- Exports to PDF and SVG with the same visible bounds as the canvas, with no raster substituted, and with point text still a text frame.
- Gradients and pattern fills shear with the artwork. Rendered by the effect and by the native command and compared pixel by pixel, they differ in not one sampled pixel.
- One pass through the dialog costs one undo step, however many slider positions it went through.
- Refuses to make a shear it cannot: ±90°, ±180°, 10³⁰⁰, infinity, and a NaN all come out inside ±89°, wherever they were written, including straight into the parameter dictionary by a script or a saved document.
- Reads a parameter block it did not write without harm: keys missing, keys of the wrong type, no keys at all, or a schema number from a version that does not exist yet. A later version's extra keys survive being read and written back here.
- Blends. Illustrator calls the effect's interpolation handler while building a blend, and the axis takes the short way round modulo 180 — blending an axis of 179° with one of 1° passes through 180°, not 90°.
- The dialog previews live, takes a decimal point or a decimal comma, ignores a degree sign, and responds to the arrow keys.

**Requires** Adobe Illustrator 2026, 64-bit, on Windows 10 or 11. **Verified on** Illustrator 30.7.0, 64-bit, on Windows 11 build 10.0.26200 — that one configuration and no other. It needs no Visual C++ redistributable: the three runtime files it uses are named by *Illustrator.exe* itself, so any machine that can start Illustrator already has them.

Not claimed, and in [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md): display scaling above 100%, which no available monitor could exercise; GPU preview, which this machine has none of; macOS; and brushed artwork, which no live effect can make match the destructive command.
