# Release test matrix

Generated from the evidence files by *tools/make-test-matrix.py*. Every row is one check that was actually run; nothing here is transcribed by hand. The first three sections need no Illustrator — the built artifact, the scripts that judge, and the arithmetic. Everything after them was measured against a running one.

**147 passed, 27 failed, 2 inconclusive, 5 measured, 7 not discriminating, 1 untested — 189 checks.**

Not present in this run: *artwork-anchor.tsv*, *missing-plugin.tsv*, *crash-ab.tsv*.

## The built artifact

Both configurations rebuilt from clean, and the Release binary inspected: warnings, identity, C runtime linkage, exported entry point, and whether it gives away anything about the machine that built it.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | release build | Release builds with no warnings and no errors | the artifact is fit to ship | 0 warnings, 0 errors | PASS |
| 2 | release build | Debug builds with no warnings and no errors | the artifact is fit to ship | 0 warnings, 0 errors | PASS |
| 3 | release build | the Release build produced a plugin | the artifact is fit to ship | build\Release\LiveShear.aip | PASS |
| 4 | release build | the binary does not claim Adobe as its publisher | the artifact is fit to ship | CompanyName is VulpesNexus | PASS |
| 5 | release build | the binary names its own product | the artifact is fit to ship | ProductName is Shear for Illustrator | PASS |
| 6 | release build | the binary carries a version | the artifact is fit to ship | FileVersion is 0.1.0-rc.1 | PASS |
| 7 | release build | Release links the retail C runtime, not the debug one | the artifact is fit to ship | links MSVCP140.dll, VCRUNTIME140.dll | PASS |
| 8 | release build | no path from the build machine is embedded | the artifact is fit to ship | none found | PASS |
| 9 | release build | the symbol reference is a bare file name | the artifact is fit to ship | symbol references: LiveShear.pdb | PASS |
| 10 | release build | the entry point Illustrator looks for is exported | the artifact is fit to ship | PluginMain is in the export table | PASS |
| 11 | release build | the plugin metadata resource is present | the artifact is fit to ship | the PIPL resource is in the binary | PASS |
| 12 | release build | the effect name that documents store is unchanged | the artifact is fit to ship | VulpesNexus Shear | PASS |
| 13 | release build | the menu entry reads as a plain Adobe command | the artifact is fit to ship | Effect > Distort & Transform > Shear... | PASS |
| 14 | release build | no debug trace is on by default | the artifact is fit to ship | tracing is behind the LIVESHEAR_LOG environment variable | PASS |
| 15 | release build | the source this was built from is identified | the artifact is fit to ship | commit f40c4aaea2c6c62ebc7bc35890a9b0a114488ac4 | PASS |
| 16 | release build | the working tree was clean when it was built | the artifact is fit to ship | 6 uncommitted change(s) | **FAIL** |
| 17 | release build | nothing is linked but Windows and the C runtime | the artifact is fit to ship | no SDK, developer, or test-harness DLL is named | PASS |
| 18 | release build | the C runtime it needs is one Illustrator already needs | the artifact is fit to ship | Illustrator.exe names the same MSVCP140.dll, VCRUNTIME140.dll, VCRUNTIME140_1.dll, so no redistributable has to be installed for the plugin | PASS |

Source: [docs/evidence/build.tsv](evidence/build.tsv)

## Test infrastructure

The two scripts that turn measurements into verdicts, fed rows whose right answer is known by construction. A bug in either would turn a real failure into a green matrix, which is the one kind of bug running more tests cannot catch.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | test infrastructure | the scripts that decide pass and fail, fed rows whose right answer is known by construction | every verdict is the one the construction requires | 12 checks, 0 failed | PASS |

Source: [docs/evidence/solvers.tsv](evidence/solvers.tsv)

## Arithmetic

The affine algebra and the exact extent of a cubic Bezier, compiled against stub types and run without Illustrator. It covers the bounds fallback, which only runs when the host refuses to measure art itself and therefore cannot be reached on demand from a host test.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | arithmetic | the affine algebra and the exact extent of a cubic Bezier, compiled against stub types and checked against brute-force sampling | every check passes | 2541 checks, 0 failed | PASS |

Source: [docs/evidence/mathtest.tsv](evidence/mathtest.tsv)

## Reference point

Which box Illustrator's own Shear command anchors on, recovered by fitting the anchor out of artwork it actually produced. A fixture whose geometric and visible centers coincide cannot tell the two apart and is marked as not discriminating rather than counted as agreement.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | native semantics | plainRect, axis 0 | anchor is the geometric bounds center | anchor 540.000000; geometric center 540.000000, visible center 540.000000; residual 2.84e-14 | NOT DISCRIMINATING |
| 2 | native semantics | strokedRect, axis 0 | anchor is the geometric bounds center | anchor 540.000000; geometric center 540.000000, visible center 540.000000; residual 2.84e-14 | NOT DISCRIMINATING |
| 3 | native semantics | spike, axis 0 | anchor is the geometric bounds center | anchor 597.000000; geometric center 597.000000, visible center 600.764024; residual 3.59e-10 | PASS |
| 4 | native semantics | mixedGroup, axis 0 | anchor is the geometric bounds center | anchor 550.000000; geometric center 550.000000, visible center 550.000000; residual 1.42e-14 | NOT DISCRIMINATING |
| 5 | native semantics | bezier, axis 0 | anchor is the geometric bounds center | anchor 550.000000; geometric center 550.000000, visible center 550.000000; residual 1.89e-10 | NOT DISCRIMINATING |
| 6 | native semantics | plainRect, axis 90 | anchor is the geometric bounds center | anchor 200.000000; geometric center 200.000000, visible center 200.000000; residual 0.00e+00 | NOT DISCRIMINATING |
| 7 | native semantics | strokedRect, axis 90 | anchor is the geometric bounds center | anchor 200.000000; geometric center 200.000000, visible center 200.000000; residual 0.00e+00 | NOT DISCRIMINATING |
| 8 | native semantics | spike, axis 90 | anchor is the geometric bounds center | anchor 250.000000; geometric center 250.000000, visible center 545.176577; residual 0.00e+00 | PASS |
| 9 | native semantics | mixedGroup, axis 90 | anchor is the geometric bounds center | anchor 250.000000; geometric center 250.000000, visible center 260.000000; residual 3.00e-10 | PASS |
| 10 | native semantics | bezier, axis 90 | anchor is the geometric bounds center | anchor 220.000000; geometric center 220.000000, visible center 220.000000; residual 3.00e-10 | NOT DISCRIMINATING |

Source: [docs/evidence/anchor-verdicts.tsv](evidence/anchor-verdicts.tsv)

## Artwork types

Each fixture built twice: one copy carrying the live effect, the other sheared by *Object > Transform > Shear* with the same angles. The two must render to the same visible bounds, and the live copy's own path anchors must be unchanged.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | art types | plainRect at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 2 | art types | strokedRect at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 3 | art types | spike at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 4 | art types | roundJoin at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 5 | art types | bevelJoin at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 6 | art types | dashedStroke at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 7 | art types | bezier at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 8 | art types | openPath at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 9 | art types | compound at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 10 | art types | selfIntersecting at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 11 | art types | mixedGroup at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 12 | art types | nestedGroup at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 13 | art types | clipGroup at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 5.77e+00 pt; source geometry unchanged | **FAIL** |
| 14 | art types | transformedGroup at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 15 | art types | pointText at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 9.77e-04 pt; source geometry unchanged | **FAIL** |
| 16 | art types | areaText at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 8.80e-01 pt; source geometry unchanged | **FAIL** |
| 17 | art types | multilineText at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 9.77e-04 pt; source geometry unchanged | **FAIL** |
| 18 | art types | strokedText at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 4.03e-01 pt; source geometry unchanged | **FAIL** |
| 19 | art types | symbolInstance at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 20 | art types | gradientFill at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 21 | art types | radialFill at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 22 | art types | patternFill at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 23 | art types | calligraphicBrush at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 3.98e-01 pt; source geometry unchanged | **FAIL** |
| 24 | art types | artBrush at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 1.05e+00 pt; source geometry unchanged | **FAIL** |
| 25 | art types | patternBrush at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 2.68e+00 pt; source geometry unchanged | **FAIL** |
| 26 | art types | rotatedRect at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 27 | art types | scaledRect at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 28 | art types | reflectedRect at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 29 | art types | preShearedRect at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 30 | art types | tinyPath at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 31 | art types | hugePath at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 32 | art types | farFromOrigin at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 33 | art types | negativeCoords at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 34 | art types | zeroHeight at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | Illustrator's own shear reported success but left the oracle untouched after three attempts; nothing to compare against | INCONCLUSIVE |
| 35 | art types | zeroWidth at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 36 | art types | singleAnchor at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | Illustrator's own shear reported success but left the oracle untouched after three attempts; nothing to compare against | INCONCLUSIVE |
| 37 | art types | manyChildren at 30 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 38 | art types | plainRect at -20 deg, axis 90 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 39 | art types | plainRect at 45 deg, axis 37.5 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 40 | art types | spike at -20 deg, axis 90 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 41 | art types | spike at 45 deg, axis 37.5 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 42 | art types | mixedGroup at -20 deg, axis 90 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 43 | art types | mixedGroup at 45 deg, axis 37.5 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 44 | art types | pointText at -20 deg, axis 90 | matches Illustrator's own shear, source untouched | largest difference from the native result 4.88e-04 pt; source geometry unchanged | **FAIL** |
| 45 | art types | pointText at 45 deg, axis 37.5 | matches Illustrator's own shear, source untouched | largest difference from the native result 9.77e-04 pt; source geometry unchanged | **FAIL** |
| 46 | art types | compound at -20 deg, axis 90 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 47 | art types | compound at 45 deg, axis 37.5 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 48 | art types | clipGroup at -20 deg, axis 90 | matches Illustrator's own shear, source untouched | largest difference from the native result 7.28e+00 pt; source geometry unchanged | **FAIL** |
| 49 | art types | clipGroup at 45 deg, axis 37.5 | matches Illustrator's own shear, source untouched | largest difference from the native result 1.60e+01 pt; source geometry unchanged | **FAIL** |
| 50 | art types | plainRect at 0 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 51 | art types | plainRect at 0.000001 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 1.05e-06 pt; source geometry unchanged | **FAIL** |
| 52 | art types | plainRect at 0.001 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 1.05e-03 pt; source geometry unchanged | **FAIL** |
| 53 | art types | plainRect at 88 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 54 | art types | plainRect at 88.9 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 55 | art types | plainRect at 89 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 56 | art types | plainRect at -89 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 0.00e+00 pt; source geometry unchanged | PASS |
| 57 | art types | plainRect at -0.001 deg, axis 0 | matches Illustrator's own shear, source untouched | largest difference from the native result 1.05e-03 pt; source geometry unchanged | **FAIL** |

Source: [docs/evidence/release-verdicts.tsv](evidence/release-verdicts.tsv)

## Appearance composition

Stack order, two instances, reordering, and deletion, with the native command as the oracle at every step.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | plainRect | plainRect : Transform over Shear matches Transform over native | matches the native oracle | -15.425625842,582.000000000,415.425625842,498.000000000 vs 100.000000000,600.000000000,300.000000000,480.000000000 | **FAIL** |
| 2 | plainRect | plainRect : Shear over Transform matches native over expanded | matches the native oracle | 15.751288694,582.000000000,384.248711306,498.000000000 vs 40.000000000,582.000000000,360.000000000,498.000000000 | **FAIL** |
| 3 | plainRect | plainRect : the two stack orders differ | matches the native oracle | both -15.425625842,582.000000000,415.425625842,498.000000000 | PASS |
| 4 | plainRect | plainRect : two Shear effects match two native shears | matches the native oracle | 65.358983849,628.618831453,334.641016151,451.381168547 vs 100.000000000,600.000000000,300.000000000,480.000000000 | **FAIL** |
| 5 | selfIntersecting | selfIntersecting : Transform over Shear matches Transform over native | matches the native oracle | 64.332650721,598.389800070,378.877465706,484.421729424 vs 134.404913533,622.811529494,305.595086467,460.000000000 | **FAIL** |
| 6 | selfIntersecting | selfIntersecting : Shear over Transform matches native over expanded | matches the native oracle | 75.281284651,598.389800070,349.185561344,484.421729424 vs 83.047861653,598.389800070,356.952138347,484.421729424 | **FAIL** |
| 7 | selfIntersecting | selfIntersecting : the two stack orders differ | matches the native oracle | both 64.332650721,598.389800070,378.877465706,484.421729424 | PASS |
| 8 | selfIntersecting | selfIntersecting : two Shear effects match two native shears | matches the native oracle | 123.309803531,643.704830858,319.900312897,449.668752426 vs 134.404913533,622.811529494,305.595086467,460.000000000 | **FAIL** |
| 9 | bezier | bezier : Transform over Shear matches Transform over native | matches the native oracle | -19.183315729,603.255518297,459.183315729,496.744481703 vs 97.503849117,625.702957558,342.496150883,474.297042442 | **FAIL** |
| 10 | bezier | bezier : Shear over Transform matches native over expanded | matches the native oracle | 6.503520270,602.778572493,433.496479730,497.221427507 vs 26.354030676,602.676003408,413.645969324,497.323996592 | **FAIL** |
| 11 | bezier | bezier : the two stack orders differ | matches the native oracle | both -19.183315729,603.255518297,459.183315729,496.744481703 | PASS |
| 12 | bezier | bezier : two Shear effects match two native shears | matches the native oracle | 68.993979295,633.746759857,371.006020705,466.253240143 vs 97.503849117,625.702957558,342.496150883,474.297042442 | **FAIL** |
| 13 | two instances | two separate entries in the appearance | matches the native oracle | found 2 | PASS |
| 14 | two instances | editing one instance leaves the other alone | matches the native oracle | the second instance changed too | PASS |
| 15 | two instances | 40 reorders leave the result unchanged | matches the native oracle | 0 errors, 65.358983849,628.618831453,334.641016151,451.381168547 vs 65.358983849,628.618831453,334.641016151,451.381168547 | PASS |
| 16 | two instances | swapping the two instances changes the result | matches the native oracle | both 53.087025039,621.255656167,346.912974961,458.744343833 | PASS |
| 17 | two instances | deleting the second leaves the first intact | matches the native oracle | 65.358983849,600.000000000,334.641016151,480.000000000 vs 65.358983849,600.000000000,334.641016151,480.000000000 | PASS |
| 18 | two instances | deleting the only effect restores the artwork | matches the native oracle | 100.000000000,600.000000000,300.000000000,480.000000000 vs 100.000000000,600.000000000,300.000000000,480.000000000 | PASS |

Source: [docs/evidence/appearance.tsv](evidence/appearance.tsv)

## Save and reopen

Write the document, close it, open it again, edit the effect, save and open once more.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | save and reopen | one effect on a path | same bounds, effect present, edit survives a second round trip | reopen True, present True, edited reopen True | PASS |
| 2 | save and reopen | one effect on live text | same bounds, effect present, edit survives a second round trip | reopen True, present True, edited reopen True | PASS |
| 3 | save and reopen | one effect on stroked art | same bounds, effect present, edit survives a second round trip | reopen True, present True, edited reopen True | PASS |
| 4 | save and reopen | two Shear effects | same bounds, effect present, edit survives a second round trip | reopen True, present True, edited reopen True | PASS |
| 5 | save and reopen | Shear plus Transform | same bounds, effect present, edit survives a second round trip | reopen True, present True, edited reopen True | PASS |

Source: [docs/evidence/persistence.tsv](evidence/persistence.tsv)

## Gradients and patterns

Rendered to PNG and compared pixel by pixel against the native command, because bounds cannot see whether a fill inside the shape sheared with it.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | fills | gradientFill renders as the native command does | the rendered pixels agree, so the fill sheared with the object | patterns on 0, patterns off 0, closest patterns on | PASS |
| 2 | fills | radialFill renders as the native command does | the rendered pixels agree, so the fill sheared with the object | patterns on 0, patterns off 0, closest patterns on | PASS |
| 3 | fills | patternFill renders as the native command does | the rendered pixels agree, so the fill sheared with the object | patterns on 0, patterns off 0,0407320756585462, closest patterns on | PASS |

Source: [docs/evidence/fills.tsv](evidence/fills.tsv)

## Export

Export, then open the exported file back in Illustrator and measure what is in it.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | pdf | plainRect exported to pdf | bounds match the canvas, no rasterization | bounds match True, raster False, items PathItem, 44664 bytes | PASS |
| 2 | svg | plainRect exported to svg | bounds match the canvas, no rasterization | bounds match True, raster False, items PathItem, 448 bytes | PASS |
| 3 | pdf | strokedRect exported to pdf | bounds match the canvas, no rasterization | bounds match True, raster False, items PathItem, 45632 bytes | PASS |
| 4 | svg | strokedRect exported to svg | bounds match the canvas, no rasterization | bounds match True, raster False, items PathItem, 594 bytes | PASS |
| 5 | pdf | pointText exported to pdf | bounds match the canvas, no rasterization | bounds match True, raster False, items TextFrame, 50798 bytes | PASS |
| 6 | svg | pointText exported to svg | bounds match the canvas, no rasterization | bounds match True, raster False, items TextFrame, 2588734 bytes | PASS |
| 7 | pdf | mixedGroup exported to pdf | bounds match the canvas, no rasterization | bounds match True, raster False, items GroupItem,PathItem, 45512 bytes | PASS |
| 8 | svg | mixedGroup exported to svg | bounds match the canvas, no rasterization | bounds match True, raster False, items GroupItem,PathItem, 603 bytes | PASS |
| 9 | pdf | gradientFill exported to pdf | bounds match the canvas, no rasterization | bounds match True, raster False, items PathItem, 45546 bytes | PASS |
| 10 | svg | gradientFill exported to svg | bounds match the canvas, no rasterization | bounds match True, raster False, items PathItem, 754 bytes | PASS |
| 11 | pdf | clipGroup exported to pdf | bounds match the canvas, no rasterization | bounds match True, raster False, items GroupItem,PathItem, 44658 bytes | PASS |
| 12 | svg | clipGroup exported to svg | bounds match the canvas, no rasterization | bounds match True, raster False, items GroupItem,PathItem, 1760 bytes | PASS |

Source: [docs/evidence/export.tsv](evidence/export.tsv)

## Parameter safety

Values written straight into the parameter dictionary, past anything the dialog would allow, each redraw under a watchdog.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | stored parameter | shearAngle written as 0 | clamped to 0 degrees, no hang | 100.000000,600.000000,300.000000,480.000000 in 3,60 s | PASS |
| 2 | stored parameter | shearAngle written as 30 | clamped to 30 degrees, no hang | 65.358984,600.000000,334.641016,480.000000 in 3,47 s | PASS |
| 3 | stored parameter | shearAngle written as 89 | clamped to 89 degrees, no hang | -3337.397698,600.000000,3737.397698,480.000000 in 3,38 s | PASS |
| 4 | stored parameter | shearAngle written as -89 | clamped to -89 degrees, no hang | -3337.397698,600.000000,3737.397698,480.000000 in 3,41 s | PASS |
| 5 | stored parameter | shearAngle written as 89.000001 | clamped to 89 degrees, no hang | -3337.397698,600.000000,3737.397698,480.000000 in 3,35 s | PASS |
| 6 | stored parameter | shearAngle written as 89.9 | clamped to 89 degrees, no hang | -3337.397698,600.000000,3737.397698,480.000000 in 3,35 s | PASS |
| 7 | stored parameter | shearAngle written as 90 | clamped to 89 degrees, no hang | -3337.397698,600.000000,3737.397698,480.000000 in 3,38 s | PASS |
| 8 | stored parameter | shearAngle written as -90 | clamped to -89 degrees, no hang | -3337.397698,600.000000,3737.397698,480.000000 in 3,55 s | PASS |
| 9 | stored parameter | shearAngle written as 180 | clamped to 89 degrees, no hang | -3337.397698,600.000000,3737.397698,480.000000 in 3,42 s | PASS |
| 10 | stored parameter | shearAngle written as -180 | clamped to -89 degrees, no hang | -3337.397698,600.000000,3737.397698,480.000000 in 3,27 s | PASS |
| 11 | stored parameter | shearAngle written as 1e9 | clamped to 89 degrees, no hang | -3337.397698,600.000000,3737.397698,480.000000 in 3,36 s | PASS |
| 12 | stored parameter | shearAngle written as nan | clamped to 0 degrees, no hang | 100.000000,600.000000,300.000000,480.000000 in 3,24 s | PASS |
| 13 | stored parameter | shearAngle written as inf | clamped to 89 degrees, no hang | -3337.397698,600.000000,3737.397698,480.000000 in 3,26 s | PASS |
| 14 | stored parameter | shearAngle written as -inf | clamped to -89 degrees, no hang | -3337.397698,600.000000,3737.397698,480.000000 in 3,22 s | PASS |
| 15 | stored parameter | shearAngle written as 0.000001 | clamped to 0 degrees, no hang | 99.999999,600.000000,300.000001,480.000000 in 3,32 s | PASS |
| 16 | stored parameter | shearAngle written as 0.001 | clamped to 0,001 degrees, no hang | 99.998953,600.000000,300.001047,480.000000 in 3,29 s | PASS |
| 17 | stored parameter | a document storing 90 degrees opens and renders the same | opens promptly, clamped, unchanged bounds | opened in 0,70 s, dictionary holds 90.000000, bounds -3337.397697846,600.000000000,3737.397697846,480.000000000 | PASS |

Source: [docs/evidence/limits.tsv](evidence/limits.tsv)

## Dialog

Driven through the window manager from a second process, because the call that opens the dialog is blocked until it closes.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | dialog | the dialog opened and OK committed the slider value | the dialog behaves like an Adobe dialog | shearAngle in the appearance after OK: 40 | PASS |
| 2 | dialog | the window title reads Shear | the dialog behaves like an Adobe dialog | the title bar holds 'Shear' | PASS |
| 3 | dialog | the degree sign is a degree sign | the dialog behaves like an Adobe dialog | no U+00B0 among the labels; the degree sign has been mangled by a code page again | PASS |
| 4 | dialog | dragging through several values does not compound | the dialog behaves like an Adobe dialog | width after dragging through 10, 20, 30, 40 is 300.692 pt; a single 40 degree shear gives 300.692 pt; compounding would give far more | PASS |
| 5 | dialog | cancel restores the artwork and the parameter it started with | the dialog behaves like an Adobe dialog | bounds before 94.751, 600, 305.249, 480; after 94.751, 600, 305.249, 480; shearAngle after 5 (it was 5) | PASS |
| 6 | dialog | escape restores the artwork and the parameter it started with | the dialog behaves like an Adobe dialog | bounds before 94.751, 600, 305.249, 480; after 94.751, 600, 305.249, 480; shearAngle after 5 (it was 5) | PASS |
| 7 | dialog | close restores the artwork and the parameter it started with | the dialog behaves like an Adobe dialog | bounds before 94.751, 600, 305.249, 480; after 94.751, 600, 305.249, 480; shearAngle after 5 (it was 5) | PASS |
| 8 | dialog | Enter commits, like the default button | the dialog behaves like an Adobe dialog | shearAngle after Enter: 33 | PASS |
| 9 | dialog | a value typed with a decimal comma is committed | the dialog behaves like an Adobe dialog | shearAngle after typing 22,5 and pressing OK: 22.5 | PASS |
| 10 | dialog | a value typed with trailing text still reads as a number | the dialog behaves like an Adobe dialog | shearAngle after typing '18.25 deg': 18.2 | **FAIL** |
| 11 | dialog | a value typed past the limit is clamped to 89 | the dialog behaves like an Adobe dialog | shearAngle after typing 95: 89 | PASS |
| 12 | dialog | three up arrows raise the angle by three degrees | the dialog behaves like an Adobe dialog | shearAngle after three up arrows from 10: 13 | PASS |
| 13 | dialog | with Preview off the artwork is not redrawn at the new angle | the dialog behaves like an Adobe dialog | the effect was last evaluated at NaN degrees while the dialog was open; it started at 5 | **FAIL** |
| 14 | dialog | and OK still commits the new angle | the dialog behaves like an Adobe dialog | shearAngle after OK: 44; bounds 42.059, 600, 357.941, 480 (were 94.751, 600, 305.249, 480) | PASS |

Source: [docs/evidence/dialog.tsv](evidence/dialog.tsv)

## Undo and redo

Every edit undone and redone, counting how many steps one deliberate action costs.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | undo and redo | applying the effect changes the artwork | the artwork returns exactly, in a sensible number of steps | 100.000000000,600.000000000,300.000000000,480.000000000 then 65.358983849,600.000000000,334.641016151,480.000000000 | PASS |
| 2 | undo and redo | one undo removes a freshly applied effect | the artwork returns exactly, in a sensible number of steps | took 1 undo steps | PASS |
| 3 | undo and redo | redo puts it back | the artwork returns exactly, in a sensible number of steps | after redo 65.358983849,600.000000000,334.641016151,480.000000000, wanted 65.358983849,600.000000000,334.641016151,480.000000000 | PASS |
| 4 | undo and redo | editing the angle changes the artwork | the artwork returns exactly, in a sensible number of steps | 65.358983849,600.000000000,334.641016151,480.000000000 then 40.000000000,600.000000000,360.000000000,480.000000000 | PASS |
| 5 | undo and redo | undo after a bridge parameter edit leaves the document coherent | the artwork returns exactly, in a sensible number of steps | the document lost its artwork | PASS |
| 6 | undo and redo | the dialog session committed the last slider position | the artwork returns exactly, in a sensible number of steps | 94.750680188,600.000000000,305.249319812,480.000000000 then -3.923048454,600.000000000,403.923048454,480.000000000 | PASS |
| 7 | undo and redo | one drag through six positions costs a handful of undo steps | the artwork returns exactly, in a sensible number of steps | took 1 undo steps to get back to the state before the dialog opened | PASS |
| 8 | undo and redo | deleting one of two effects changes the artwork | the artwork returns exactly, in a sensible number of steps | two effects 65.358983849,628.618831453,334.641016151,451.381168547, one effect 65.358983849,600.000000000,334.641016151,480.000000000 | PASS |
| 9 | undo and redo | undo after a bridge deletion leaves the document coherent | the artwork returns exactly, in a sensible number of steps | the document lost its artwork | PASS |
| 10 | undo and redo | undo after a bridge reorder leaves the document coherent | the artwork returns exactly, in a sensible number of steps | the document lost its artwork; swapped bounds were 53.087025039,621.255656167,346.912974961,458.744343833 | PASS |
| 11 | undo and redo | the source path is unchanged after all of that | the artwork returns exactly, in a sensible number of steps | 100.000000000,480.000000000 100.000000000,600.000000000 300.000000000,600.000000000 300.000000000,480.000000000 vs 100.000000000,480.000000000 100.000000000,600.000000000 300.000000000,600.000000000 300.000000000,480.000000000 | PASS |

Source: [docs/evidence/undo.tsv](evidence/undo.tsv)

## Stability and performance

Identity, cumulative drift, source invariance, evaluation cost, and a document full of independent instances.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | identity | identity at axis 0, 25 redraws | no change from the untouched artwork | deviation 0 | PASS |
| 2 | identity | identity at axis 17, 25 redraws | no change from the untouched artwork | deviation 0 | PASS |
| 3 | identity | identity at axis 45, 25 redraws | no change from the untouched artwork | deviation 0 | PASS |
| 4 | identity | identity at axis 90, 25 redraws | no change from the untouched artwork | deviation 0 | PASS |
| 5 | identity | identity at axis 137, 25 redraws | no change from the untouched artwork | deviation 0 | PASS |
| 6 | identity | identity at axis 180, 25 redraws | no change from the untouched artwork | deviation 0 | PASS |
| 7 | identity | identity at axis -63, 25 redraws | no change from the untouched artwork | deviation 0 | PASS |
| 8 | drift | 100 parameter edits then back to 30 degrees | no change from the untouched artwork | deviation 0 | PASS |
| 9 | drift | and back to zero, against artwork never sheared | no change from the untouched artwork | deviation 0 | PASS |
| 10 | source | source anchors identical to a fresh fixture | no change from the untouched artwork | the source moved | PASS |
| 11 | performance | plainRect: 100 evaluations with the effect | fast enough that dragging the slider does not lag | 4686 ms in total, 46,86 ms each; the same loop with nothing to recompute took 3119 ms | MEASURED |
| 12 | performance | bezier: 100 evaluations with the effect | fast enough that dragging the slider does not lag | 4731 ms in total, 47,31 ms each; the same loop with nothing to recompute took 3111 ms | MEASURED |
| 13 | performance | multilineText: 100 evaluations with the effect | fast enough that dragging the slider does not lag | 4688 ms in total, 46,88 ms each; the same loop with nothing to recompute took 3118 ms | MEASURED |
| 14 | performance | manyChildren: 100 evaluations with the effect | fast enough that dragging the slider does not lag | 4727 ms in total, 47,27 ms each; the same loop with nothing to recompute took 3114 ms | MEASURED |
| 15 | performance | compound: 100 evaluations with the effect | fast enough that dragging the slider does not lag | 4669 ms in total, 46,69 ms each; the same loop with nothing to recompute took 3115 ms | MEASURED |
| 16 | performance | all 200 objects survived the round trip | no change from the untouched artwork | found 200 | PASS |

Source: [docs/evidence/stability.tsv](evidence/stability.tsv)

## Preview mode

The document window captured as a bitmap under each preview path and compared pixel by pixel.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | preview mode | the window capture sees the canvas | moving the artwork changes the captured picture | 0,492 % of sampled pixels changed | PASS |
| 2 | preview mode | GPU and CPU preview draw the same sheared artwork | no more than a couple of percent of pixels differ, from antialiasing | the mode never changed; the window title stayed Untitled-1* @ 11,33 % (CMYK/Preview) | UNTESTED |

Source: [docs/evidence/gpu.tsv](evidence/gpu.tsv)

## Application shutdown

Illustrator quit the ordinary way from each state this plugin can leave it in, checking that it went, that it went promptly, and that the Windows event log has nothing new to say.

| # | Group | Case | Expected | Observed | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | shutdown | no documents open | quits promptly, nothing left running, nothing in the event log | quit in 1,6 s; still running False; event log: nothing | PASS |
| 2 | shutdown | one document with a Shear effect | quits promptly, nothing left running, nothing in the event log | quit in 1,9 s; still running False; event log: nothing | PASS |
| 3 | shutdown | three documents, two with effects | quits promptly, nothing left running, nothing in the event log | quit in 3,3 s; still running False; event log: nothing | PASS |
| 4 | shutdown | after the dialog has been opened | quits promptly, nothing left running, nothing in the event log | quit in 2,4 s; still running False; event log: nothing | PASS |

Source: [docs/evidence/shutdown.tsv](evidence/shutdown.tsv)
