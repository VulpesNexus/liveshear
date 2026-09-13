# Release notes

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
