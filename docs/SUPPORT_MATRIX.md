# Support matrix

Generated from the release matrix by *tools/make-support-matrix.py*. A row says VERIFIED only when every case the suite ran for that kind of artwork rendered the same visible bounds as Illustrator's own *Object > Transform > Shear*, to within a ten-millionth of a point, and left the source geometry untouched.

**11 partial, 9 untested, 26 verified.**

| Artwork | Fixture | Cases | Status | Notes |
| --- | --- | --- | --- | --- |
| Simple paths | `plainRect` | 11 | PARTIAL | largest difference from the native result 1.05e-03 pt; source geometry unchanged; largest difference from the native result 1.05e-06 pt; source geometry unchanged |
| Ordinary strokes | `strokedRect` | 1 | VERIFIED | a 40 pt centered stroke |
| Mitered joins | `spike` | 3 | VERIFIED | an acute triangle whose mitered join reaches far past the geometry |
| Round joins | `roundJoin` | 1 | VERIFIED | the same triangle with a round join |
| Bevel joins | `bevelJoin` | 1 | VERIFIED | the same triangle with a bevel join |
| Dashed strokes | `dashedStroke` | 1 | VERIFIED | a 12 pt stroke dashed 18 on, 9 off |
| Bezier paths | `bezier` | 1 | VERIFIED | an open path of smooth curves |
| Open paths | `openPath` | 1 | VERIFIED | an open path with round caps |
| Compound paths | `compound` | 3 | VERIFIED | a rectangle with a rectangular hole |
| Self-intersecting paths | `selfIntersecting` | 1 | VERIFIED | a five-pointed star drawn as one closed path |
| Groups | `mixedGroup` | 3 | VERIFIED | two rectangles with different stroke weights |
| Nested groups | `nestedGroup` | 1 | VERIFIED | a group inside a group |
| Clipping groups | `clipGroup` | 3 | PARTIAL | largest difference from the native result 1.60e+01 pt; source geometry unchanged; largest difference from the native result 5.77e+00 pt; source geometry unchanged; largest difference from the native result 7.28e+00 pt; s |
| Transformed groups | `transformedGroup` | 1 | VERIFIED | a nested group rotated and moved |
| Live point text | `pointText` | 3 | PARTIAL | largest difference from the native result 4.88e-04 pt; source geometry unchanged; largest difference from the native result 9.77e-04 pt; source geometry unchanged |
| Live area text | `areaText` | 1 | PARTIAL | largest difference from the native result 8.80e-01 pt; source geometry unchanged |
| Multi-line text | `multilineText` | 1 | PARTIAL | largest difference from the native result 9.77e-04 pt; source geometry unchanged |
| Stroked text | `strokedText` | 1 | PARTIAL | largest difference from the native result 4.03e-01 pt; source geometry unchanged |
| Symbol instances | `symbolInstance` | 1 | VERIFIED | an instance of a symbol made from a stroked rectangle |
| Linear gradients | `gradientFill` | 1 | VERIFIED | a linear gradient fill |
| Radial gradients | `radialFill` | 1 | VERIFIED | a radial gradient fill |
| Pattern-filled objects | `patternFill` | 1 | VERIFIED | an object carrying a pattern swatch fill |
| Calligraphic brushes | `calligraphicBrush` | 1 | PARTIAL | largest difference from the native result 3.98e-01 pt; source geometry unchanged |
| Art brushes | `artBrush` | 1 | PARTIAL | largest difference from the native result 1.05e+00 pt; source geometry unchanged |
| Pattern brushes | `patternBrush` | 1 | PARTIAL | largest difference from the native result 2.68e+00 pt; source geometry unchanged |
| Rotated source art | `rotatedRect` | 1 | VERIFIED | a rectangle rotated 37 degrees |
| Scaled source art | `scaledRect` | 1 | VERIFIED | a rectangle scaled non-uniformly |
| Reflected source art | `reflectedRect` | 1 | VERIFIED | a triangle reflected horizontally |
| Already-sheared source art | `preShearedRect` | 1 | VERIFIED | a rectangle sheared 20 degrees destructively |
| Very small artwork | `tinyPath` | 1 | VERIFIED | a rectangle a hundredth of a point across |
| Very large artwork | `hugePath` | 1 | VERIFIED | a rectangle 8,000 by 5,000 points |
| Artwork far from the origin | `farFromOrigin` | 1 | VERIFIED | a rectangle at 4,000 by 3,000 points |
| Negative coordinates | `negativeCoords` | 1 | VERIFIED | a rectangle at negative x and y |
| Degenerate: no height | `zeroHeight` | 1 | PARTIAL | some cases could not be measured: Illustrator's own shear reported success but left the oracle untouched after three attempts; nothing to compare against |
| Degenerate: no width | `zeroWidth` | 1 | VERIFIED | a vertical line |
| Degenerate: one anchor | `singleAnchor` | 1 | PARTIAL | some cases could not be measured: Illustrator's own shear reported success but left the oracle untouched after three attempts; nothing to compare against |
| Large groups | `manyChildren` | 1 | VERIFIED | a group of two hundred rectangles |
| Pattern fills | — | 0 | UNTESTED | The object is exercised and its bounds match the native command, but whether the pattern inside it leans with the shape could not be seen: a pattern built through Illustrator's scripting interface does not render at all, so there is nothing to compare. Gradients are verified in pixels. |
| Variable-width strokes | — | 0 | UNTESTED | No case builds one: the width profile is not reachable from Illustrator's scripting interface, so a fixture would have to be drawn by hand. |
| Scatter brushes | — | 0 | UNTESTED | No scatter brush ships in the default document profile used by the fixtures. |
| Meshes | — | 0 | UNTESTED | Not exercised. |
| Placed and linked images | — | 0 | UNTESTED | The earlier behavior suite applied the effect to an embedded raster without error; no case measures the result against the native command. |
| Blends | — | 0 | UNTESTED | The Interpolate handler is implemented but no case drives it. |
| Graphs | — | 0 | UNTESTED | Not exercised. |
| 3D and raster effects below the Shear in the stack | — | 0 | UNTESTED | Composition was measured against Adobe's Transform and against Offset Path, not against a raster effect. |
| Non-Windows hosts | — | 0 | UNTESTED | The plugin is Windows-only; the dialog is plain Win32. |
