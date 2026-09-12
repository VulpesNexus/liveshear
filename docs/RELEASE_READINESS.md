# Release readiness

## A. Verdict

**NOT RELEASE READY.** Not because anything is known to be wrong, but because this build has not been run in Illustrator.

Installing a plugin means copying it into Illustrator's folder under *Program Files*, which needs administrator rights and a prompt answered by a person. That prompt has not been answered, so the binary that carries the reference-point fix, the parameter clamps, the dialog work, and the new identity has never been loaded by the host. Everything below distinguishes what has been measured from what is waiting on that.

A release candidate needs the suite in [RELEASE_TEST_MATRIX.md](RELEASE_TEST_MATRIX.md) run against this binary, and its remaining sections filled. The suite is written, debugged against a running Illustrator, and starts with one command:

```powershell
.\tools\run-release-suite.ps1
```

## B. Exact build

| | |
| --- | --- |
| Plugin version | 0.1.0-rc.1 |
| Binary | *LiveShear.aip*, 154,112 bytes, SHA-256 `D434A1A815638CEE2CD41B365F339D2E0C3E33E92530BDD0F271A8E214985AD6` |
| Commit | see *git log*; this document is written against the head of `main` |
| Illustrator | 2026, version 30.7.0, 64-bit — the version the earlier work was measured against; **this build has not been loaded by it** |
| SDK | Adobe Illustrator 2026 SDK, build 114 |
| Compiler | MSVC 14.44.35207, C++17, `/W4`, x64 |
| Windows | Windows 11, 10.0.26200 |

Both configurations rebuild from clean with zero warnings and zero errors. The Release binary links only the retail C runtime, exports the entry point Illustrator looks for, carries the PIPL resource, names *VulpesNexus* rather than Adobe as its publisher, and contains no path from the machine that built it. Fourteen checks, all passing: [evidence/build.txt](evidence/build.txt).

## C. Architecture

One standalone live effect, registered as a post-effect accepting any input art but plugin groups, at *Effect > Distort & Transform > Shear…*. Its `Go` handler reads two angles from the parameter dictionary, takes the center of the incoming artwork's geometric bounds as the reference point, builds one matrix, and calls `AITransformArtSuite::TransformArt` once.

It is not an extension of Adobe's *Transform* effect because it cannot be: that effect has no shear state to expose, and no public interface adds behavior to an effect another plugin registered. [LIVE_SHEAR_INVESTIGATION.md](../LIVE_SHEAR_INVESTIGATION.md) has the evidence for both.

## D. Native equivalence

Pending the host run. The claim to be re-established for this binary is that each fixture, built twice and sheared once by the live effect and once by *Object > Transform > Shear*, renders to the same visible bounds within a ten-millionth of a point, with the live copy's own path anchors unchanged.

What is already established, and does not depend on the build: the native command's transform is `R(φ)·H(θ)·R(−φ)` about the reference point, matched across 23 host cases to 3×10⁻⁶, and the matrix the plugin builds for the same parameters is that matrix — checked here at 2,541 points without a host, including the determinant at every angle and axis and the reference point as a fixed point ([evidence/mathtest.txt](evidence/mathtest.txt)).

## E. Reference point

**Settled.** Illustrator's own shear anchors on the center of the selection's **geometric** bounds: the Bézier outline, with strokes, effects, and the glyphs of area text excluded.

That was measured rather than reasoned about. A shear along axis 0 displaces x in proportion to distance from the reference point's y and leaves y alone, so a straight-line fit through the artwork a native shear actually produced recovers the y exactly; axis 90 recovers the x. Against fixtures whose geometric and visible centers lie far apart — an acute triangle whose mitered join reaches 600 pt past its geometry, and a group whose two members carry different stroke weights — every discriminating case comes back geometric, residuals around 10⁻¹⁰. Fixtures whose two centers coincide cannot tell them apart and are reported as not discriminating rather than counted as agreement. [evidence/anchor.tsv](evidence/anchor.tsv), [evidence/anchor-verdicts.tsv](evidence/anchor-verdicts.tsv).

The effect had been anchoring on visible bounds, which on that triangle put its reference point 295 pt away from the native one. It now asks the host for geometric bounds, twice, and when the host refuses — which it does for art outside the document tree, exactly the situation a live effect's `Go` runs in — computes the same box itself, solving each cubic's derivative for the true extremes rather than settling for the control hull. That fallback is the one code path that cannot be reached on demand from a host test, which is why it is covered by the arithmetic test instead: every curve extent is checked against a hundred thousand samples of the same curve.

The reference point is taken from the artwork the appearance pipeline hands the effect, not from the original object. That is deliberate and it is what makes the effect compose: an *Offset Path* or a *Transform* below it moves the reference point with the artwork, exactly as stacking two transforms should.

## F. Supported artwork

See [SUPPORT_MATRIX.md](SUPPORT_MATRIX.md), which is generated from the release matrix rather than written by hand, and which lists what the suite does not cover as untested rather than omitting it. Pending the host run.

One result is already in, and it is worth stating because bounds cannot reach it. **Gradients shear with the artwork**: a linear and a radial gradient fill, rendered by the effect and by the native command, exported at the same size and compared pixel by pixel, differ in not one sampled pixel.

**Pattern fills could not be tested at all**, and the probe says so rather than reporting agreement. A pattern swatch built through Illustrator's scripting interface does not render — not sheared, not unsheared, not at all. The object is there and reports a `PatternColor` fill; the page comes out blank. Three ways of building the tile were tried, including the grouped bounding-box form Adobe's own documentation describes. The probe now renders each fixture unsheared first and refuses to compare anything whose picture the shear did not change, which is what turned a meaningless pass into an honest UNTESTED.

## G. Appearance composition

Pending the host run. The checks written and debugged: a *Transform* above a live Shear against a *Transform* above a native shear; a live Shear above a *Transform* against a native shear of that *Transform* expanded into real geometry; that the two stack orders differ; two Shear effects against two successive native shears; that editing one instance leaves the other alone; forty reorders; and deleting one of two.

## H. Persistence

Pending re-run against this binary. The same five cases passed against the previous build: one effect on a path, on live text, and on stroked art; two Shear effects; and Shear with a *Transform*. Each is saved, closed, reopened, edited through the parameter dictionary, saved and reopened again.

## I. Export

Pending re-run against this binary. PDF and SVG passed against the previous build for a rectangle, point text, and a gradient fill: the exported file, opened back in Illustrator, has the same visible bounds as the canvas, and contains no raster image. Point text stays a text frame in both formats.

## J. Dialog

Pending the host run for this binary. Checks written, and all of them already exercised against the previous one: OK commits; Cancel, Escape, and the title bar's close button each restore both the artwork and the parameter; Enter commits; dragging through several positions does not compound; a value typed with a decimal comma, with trailing text, or past the limit; the arrow keys; the title and labels read back as the code points they should be; and Preview off leaving the artwork alone until OK — that last one read out of the plugin's own trace, because while a modal dialog is up there is no other way to ask what the artwork did.

Nine of those passed against the previous binary and four failed, which is the right answer: the four are the decimal comma, the arrow keys, Preview off, and the text encoding, and all four are what this build changed.

The probe captures the dialog to *evidence/dialog.png*, which is how the text problem was found in the first place and is worth keeping for that reason alone.

**High-DPI scaling is not exercised here.** The display this runs on reports 96 dots per inch, so the dialog is measured at its unscaled size — 448 by 199 pixels, client area 432 by 160, nothing clipped, every control reachable. The scaling path reads `GetDpiForWindow` and multiplies every coordinate and the font height through it, but a display that would make it do anything is not available, so it is untested rather than verified.

## K. Parameter safety

One function makes a shear angle safe, and every route a value can arrive by passes through it: the slider, the numeric field, a pasted string, a parameter dictionary read out of a saved document, another plugin writing the dictionary directly. Anything that is not a finite number becomes zero; anything past ±89° is clamped to it.

The limit is 89° because Illustrator itself becomes pathological approaching a right angle: a native shear of 89° returns at once, one of 89.9° did not return at all in the run that measured it. The clamps are verified without a host — 90, ±180, 10³⁰⁰, ±∞, and NaN all come out inside the range ([evidence/mathtest.txt](evidence/mathtest.txt)). What is pending is the host half: that a document which stores 90° opens clamped rather than hanging, with a watchdog on the clock to tell a wrong answer from no answer.

## L. Undo and redo

Partly established, against the previous build. **One pass through the dialog costs one undo step**, however many slider positions it went through; applying the effect is one step; redo puts it back. To be re-run against this binary.

Edits made through the plugin's scripting bridge are not undo steps, because they rebuild the art style through the SDK rather than as one of Illustrator's own operations. Nothing a person does in the interface goes through that bridge.

## M. Performance

Pending the host run. The measurement is the cost of one hundred re-evaluations, with and without the effect, on a rectangle, a Bézier path, multi-line text, a group of two hundred children, and a compound path; plus building, saving, and reopening a document with two hundred independent Shear effects.

## N. Memory and resources

Pending the host run for the differential measurement. By inspection: the effect acquires no suites of its own beyond the import table the SDK manages, creates no temporary art, and holds no handle past the callback that gave it. The dialog registers one window class lazily and unregisters it at shutdown, creates one font and deletes it after its modal loop rather than during `WM_DESTROY`, when the controls still hold it, and hands the application's own quit message back instead of swallowing it.

### What the code review found

One dedicated read of every source file, looking for the things that go wrong in SDK plugins: unchecked suite calls, stale handles, resource paths that only free on the happy path, degrees confused with radians, sign flips with no explanation, and assumptions about the host that nothing tests.

Fixed during this sprint, each described where it lives:

- The reference point came from the wrong box, and the code said "geometric bounds" while asking for and then falling back to something else. It now asks for what it means and says which route answered, in the trace and through the `bounds` script selector.
- The parameter clamp lived in the dialog, so it did not apply to a value arriving from a saved document. It moved into `ShearMath.h`, and every read and every write passes through it.
- `DeleteObject` on the dialog's font ran during `WM_DESTROY`, while the child controls still held it. `DestroyWindow` sends that message to the parent before it destroys the children.
- The modal loop consumed `WM_QUIT`, so an application quit arriving while the dialog was open would have been swallowed. It is re-posted for Illustrator's own loop now.
- The window class was registered and never unregistered. If the module were unloaded with it still registered, its window procedure would point into freed memory.
- Six `reinterpret_cast<HMENU>(int)` conversions, which are narrowing in reverse on 64-bit. They go through `INT_PTR` now, which is what made the build clean at warning level 4.
- The arrow keys never reached the numeric fields, because `IsDialogMessage` treats them as navigation between controls and consumed them first.
- **The dialog's own text was mangled, and a screen capture of it is what found that.** Two separate faults, both from mixing the narrow and wide Windows entry points. The window class was registered with `RegisterClassExA` while `DefWindowProc` resolved to the wide variant, because the project builds with `UNICODE` defined — so the title "Shear" was stored as its own bytes reinterpreted as UTF-16 and came out as `U+6853 U+6165 U+0072`, which reads 桓槌r. And the degree sign, written as UTF-8 into an ANSI call, was converted through the machine's code page: on this one, page 932, it became `U+FF82 U+FF70`, two half-width katakana. Every string the dialog touches now goes through the wide entry points, so no code page is involved at all. The Appearance panel's one-line description had the same problem for the same reason and now goes through `SetUnicodeStringEntry` rather than a plain `char*`. The dialog probe reads the title and the labels back as code points, and those two checks fail against the old binary and pass against this one.
- A preview that would change nothing still asked Illustrator to re-render, once per slider position.
- The binary claimed Adobe as its publisher, named *Adobe Illustrator* as its product, and filed itself under *About SDK Plug-ins* as an Adobe sample. All three came from the SDK's sample defaults, whose own header says third parties should supply their own.
- The linker stamped the absolute path of the build machine's symbol file into the shipped binary.

Left alone deliberately: the scripting bridge, which is in the shipped binary so that the binary the tests pass against is the binary that ships, and which grants no privilege a script does not already have through Illustrator's own scripting and action interfaces.

No further substantive issue was found on the last read.

## O. Host crash

Illustrator 30.7.0 dies with an access violation inside *Illustrator.exe* during long runs of scripted document create/close, and it does so with this plugin uninstalled: three runs of forty cycles that never touch the effect completed 9, 32, and 40 ([evidence/crash-control.txt](evidence/crash-control.txt)). With the plugin installed the same runs completed 2, 20, and 3 — three runs per arm with that spread cannot distinguish a real effect from noise, and it has never been claimed that they can.

The three-arm experiment that would settle it is written and pending: plugin absent, plugin installed but unused, plugin installed and exercised, six trials each, with arms B and C interleaved. Arm A runs inside the missing-plugin probe, because that probe already arranges for the plugin to be uninstalled and doing it twice would mean two more prompts to answer.

## P. Without the plugin

Pending re-run against this binary. Against the previous build: Illustrator shows its standard missing-plugin warning naming *Shear (LiveShear.aip)*, opens the document, and draws the artwork sheared from the cached result. The source geometry is neither expanded nor flattened, text stays live, and a file re-saved from that state loses nothing. What stops is the effect itself, so an edit made without the plugin renders against the old shape — Illustrator's standard behavior for any missing effect.

## Q. Known limitations

[KNOWN_LIMITATIONS.md](../KNOWN_LIMITATIONS.md). The ones that stand regardless of the host run: Windows only; one host version tested; the shear angle stops at 89°; the reference point is always the center; GPU preview could not be compared because the machine has no GPU preview to compare against; documents opened without the plugin keep drawing but stop updating.

## R. Release blockers

1. **This build has not been run in Illustrator.** Everything in sections D, F, G, H, I, J, L, M, N, O, and P is pending on that. It needs one administrator prompt answered.

Nothing else is known to be outstanding.

## S. Evidence

Raw output from every probe is in [evidence/](evidence/). The matrix in [RELEASE_TEST_MATRIX.md](RELEASE_TEST_MATRIX.md) is generated from it by *tools/make-test-matrix.py*; the support matrix by *tools/make-support-matrix.py*. Nothing in either is transcribed by hand.
