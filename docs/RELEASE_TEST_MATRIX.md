# Release test matrix

Generated from the evidence files by *tools/make-test-matrix.py*. Every row is one check that was actually run; nothing here is transcribed by hand. The first three sections need no Illustrator — the built artifact, the scripts that judge, and the arithmetic. Everything after them was measured against a running one.

**19 passed, 7 not discriminating — 26 checks.**

Not present in this run: *release-verdicts.tsv*, *appearance.tsv*, *persistence.tsv*, *fills.tsv*, *export.tsv*, *limits.tsv*, *dialog.tsv*, *undo.tsv*, *stability.tsv*, *gpu.tsv*, *missing-plugin.tsv*, *crash-ab.tsv*, *shutdown.tsv*.

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
