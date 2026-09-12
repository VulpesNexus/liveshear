# Release notes

## 0.1.0-rc.1

First release candidate. A non-destructive **Shear** effect for Adobe Illustrator, at *Effect > Distort & Transform > Shear…*.

- Shears artwork by an angle along an axis, and stays editable in the *Appearance* panel.
- Renders what *Object > Transform > Shear* renders, about the same reference point: the center of the artwork's geometric bounds.
- Leaves the artwork underneath alone. Text stays live text, paths stay editable paths, and deleting the effect gives back exactly what you started with.
- Composes with other effects in either stack order, and with a second Shear.
- Survives save, close, reopen, copy, paste, duplicate, and undo.
- The dialog previews live, takes a decimal point or a decimal comma, ignores a degree sign, responds to the arrow keys, and scales with the display.

Supported on Adobe Illustrator 2026 (30.7.0), 64-bit, on Windows 10 and 11. See [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) for what it does not do.
