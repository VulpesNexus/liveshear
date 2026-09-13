# Support matrix

Generated from the release matrix by *tools/make-support-matrix.py*. A row says VERIFIED only when every case the suite ran for that kind of artwork rendered the same visible bounds as Illustrator's own *Object > Transform > Shear*, to within a ten-millionth of a point, and left the source geometry untouched.

**2 partial, 7 untested, 39 verified.**

| Artwork | Fixture | Cases | Status | Notes |
| --- | --- | --- | --- | --- |
| Simple paths | `plainRect` | 11 | VERIFIED | a filled rectangle |
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
| Clipping groups | `clipGroup` | 3 | VERIFIED | an ellipse masking a rectangle |
| Transformed groups | `transformedGroup` | 1 | VERIFIED | a nested group rotated and moved |
| Live point text | `pointText` | 3 | VERIFIED | 72 pt point text |
| Live area text | `areaText` | 1 | VERIFIED | text flowed into a rectangular frame |
| Multi-line text | `multilineText` | 1 | VERIFIED | two lines of point text |
| Stroked text | `strokedText` | 1 | VERIFIED | point text with a 6 pt character stroke |
| Text with off-center ink | `asymmetricText` | 1 | VERIFIED | glyphs with descenders on one side and none on the other |
| Text edited after the frame was made | `retypedText` | 1 | VERIFIED | point text whose contents were replaced |
| Text resized after the frame was made | `resizedText` | 1 | VERIFIED | point text whose size was changed |
| Embedded rasters | `embeddedRaster` | 1 | VERIFIED | a bitmap placed and embedded in the document |
| Symbol instances | `symbolInstance` | 1 | VERIFIED | an instance of a symbol made from a stroked rectangle |
| Linear gradients | `gradientFill` | 1 | VERIFIED | a linear gradient fill |
| Radial gradients | `radialFill` | 1 | VERIFIED | a radial gradient fill |
| Pattern-filled objects | `patternFill` | 1 | VERIFIED | an object carrying a pattern swatch fill |
| Calligraphic brushes | `calligraphicBrush` | 1 | VERIFIED | a calligraphic brush on an open path |
| Art brushes | `artBrush` | 1 | VERIFIED | an art brush on an open path |
| Pattern brushes | `patternBrush` | 1 | VERIFIED | a pattern brush on an open path |
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
| Variable-width strokes | — | 0 | UNTESTED | No case builds one: the width profile is not reachable from Illustrator's scripting interface, so a fixture would have to be drawn by hand. |
| Scatter brushes | — | 0 | UNTESTED | No scatter brush ships in the default document profile used by the fixtures. |
| Meshes | — | 0 | UNTESTED | Not exercised. |
| Linked images | — | 0 | UNTESTED | An embedded raster is exercised and anchors exactly where the native command does; a linked one is not built by any fixture. |
| Graphs | — | 0 | UNTESTED | Not exercised. |
| 3D and raster effects below the Shear in the stack | — | 0 | UNTESTED | Composition was measured against Adobe's Transform and against Offset Path, not against a raster effect. |
| Non-Windows hosts | — | 0 | UNTESTED | The plugin is Windows-only; the dialog is plain Win32. |
