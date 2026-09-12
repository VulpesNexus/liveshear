# Support matrix

Generated from the release matrix by *tools/make-support-matrix.py*. A row says VERIFIED only when every case the suite ran for that kind of artwork rendered the same visible bounds as Illustrator's own *Object > Transform > Shear*, to within a ten-millionth of a point, and left the source geometry untouched.

**45 untested.**

| Artwork | Fixture | Cases | Status | Notes |
| --- | --- | --- | --- | --- |
| Simple paths | `plainRect` | 0 | UNTESTED | no case in this run |
| Ordinary strokes | `strokedRect` | 0 | UNTESTED | no case in this run |
| Mitered joins | `spike` | 0 | UNTESTED | no case in this run |
| Round joins | `roundJoin` | 0 | UNTESTED | no case in this run |
| Bevel joins | `bevelJoin` | 0 | UNTESTED | no case in this run |
| Dashed strokes | `dashedStroke` | 0 | UNTESTED | no case in this run |
| Bezier paths | `bezier` | 0 | UNTESTED | no case in this run |
| Open paths | `openPath` | 0 | UNTESTED | no case in this run |
| Compound paths | `compound` | 0 | UNTESTED | no case in this run |
| Self-intersecting paths | `selfIntersecting` | 0 | UNTESTED | no case in this run |
| Groups | `mixedGroup` | 0 | UNTESTED | no case in this run |
| Nested groups | `nestedGroup` | 0 | UNTESTED | no case in this run |
| Clipping groups | `clipGroup` | 0 | UNTESTED | no case in this run |
| Transformed groups | `transformedGroup` | 0 | UNTESTED | no case in this run |
| Live point text | `pointText` | 0 | UNTESTED | no case in this run |
| Live area text | `areaText` | 0 | UNTESTED | no case in this run |
| Multi-line text | `multilineText` | 0 | UNTESTED | no case in this run |
| Stroked text | `strokedText` | 0 | UNTESTED | no case in this run |
| Symbol instances | `symbolInstance` | 0 | UNTESTED | no case in this run |
| Linear gradients | `gradientFill` | 0 | UNTESTED | no case in this run |
| Radial gradients | `radialFill` | 0 | UNTESTED | no case in this run |
| Pattern fills | `patternFill` | 0 | UNTESTED | no case in this run |
| Calligraphic brushes | `calligraphicBrush` | 0 | UNTESTED | no case in this run |
| Art brushes | `artBrush` | 0 | UNTESTED | no case in this run |
| Pattern brushes | `patternBrush` | 0 | UNTESTED | no case in this run |
| Rotated source art | `rotatedRect` | 0 | UNTESTED | no case in this run |
| Scaled source art | `scaledRect` | 0 | UNTESTED | no case in this run |
| Reflected source art | `reflectedRect` | 0 | UNTESTED | no case in this run |
| Already-sheared source art | `preShearedRect` | 0 | UNTESTED | no case in this run |
| Very small artwork | `tinyPath` | 0 | UNTESTED | no case in this run |
| Very large artwork | `hugePath` | 0 | UNTESTED | no case in this run |
| Artwork far from the origin | `farFromOrigin` | 0 | UNTESTED | no case in this run |
| Negative coordinates | `negativeCoords` | 0 | UNTESTED | no case in this run |
| Degenerate: no height | `zeroHeight` | 0 | UNTESTED | no case in this run |
| Degenerate: no width | `zeroWidth` | 0 | UNTESTED | no case in this run |
| Degenerate: one anchor | `singleAnchor` | 0 | UNTESTED | no case in this run |
| Large groups | `manyChildren` | 0 | UNTESTED | no case in this run |
| Variable-width strokes | — | 0 | UNTESTED | No case builds one: the width profile is not reachable from Illustrator's scripting interface, so a fixture would have to be drawn by hand. |
| Scatter brushes | — | 0 | UNTESTED | No scatter brush ships in the default document profile used by the fixtures. |
| Meshes | — | 0 | UNTESTED | Not exercised. |
| Placed and linked images | — | 0 | UNTESTED | The earlier behavior suite applied the effect to an embedded raster without error; no case measures the result against the native command. |
| Blends | — | 0 | UNTESTED | The Interpolate handler is implemented but no case drives it. |
| Graphs | — | 0 | UNTESTED | Not exercised. |
| 3D and raster effects below the Shear in the stack | — | 0 | UNTESTED | Composition was measured against Adobe's Transform and against Offset Path, not against a raster effect. |
| Non-Windows hosts | — | 0 | UNTESTED | The plugin is Windows-only; the dialog is plain Win32. |
