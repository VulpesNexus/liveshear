# Release readiness

## A. Verdict

**RELEASABLE, WITH DOCUMENTED LIMITATIONS.** Shipped as 0.1.0.

The binary has been run in Illustrator, and every result below was measured against the artifact being packaged rather than against an earlier one. Source artwork is safe in every case the suite can construct: the effect's own path anchors are compared before and after in all 61 artwork cases and never move. The reference point matches Illustrator's own shear command for every kind of artwork the suite can build, along both axes. Claims in the README, the release notes, and the limitations list were checked one at a time against the evidence behind them, and several were weakened or corrected because the evidence did not support them.

What keeps this from being an unqualified release is a short list of bounded, named limitations, none of which risks a document, and none of which the release candidates closed:

- **Display scaling above 100% has never been seen.** The layout is proven by arithmetic at five scales; the rendering is not proven at all.
- **GPU preview could not be compared**, because this machine has no GPU preview to compare against.
- **Windows 10, and Illustrator versions other than 30.7.0, are expected rather than verified.**
- **Brushed and stroked-text artwork cannot match the destructive command**, and no live effect can — including Adobe's own, which was measured as the control. On that artwork the effect is the more exact of the two.
- **Illustrator itself crashes under sustained scripted document churn.** The plugin is not necessary for it; whether it influences how often is not established, and is not claimed.

Section T says what would have to change for those qualifications to come off.

## B. Exact build

| | |
| --- | --- |
| Plugin version | 0.1.0 |
| Binary | *LiveShear.aip*; size and SHA-256 in [evidence/build.txt](evidence/build.txt) |
| Commit | recorded in the same file, with whether the working tree was clean |
| Illustrator | 2026, version 30.7.0, 64-bit — **this binary has been loaded and driven by it** |
| SDK | Adobe Illustrator 2026 SDK, build 114 |
| Compiler | MSVC 14.44.35207, C++17, `/W4`, x64 |
| Windows | Windows 11, 10.0.26200 |

Both configurations rebuild from clean with zero warnings and zero errors. The Release binary links only the retail C runtime, exports the entry point Illustrator looks for, carries the PIPL resource, names *VulpesNexus* rather than Adobe as its publisher, and contains no path from the machine that built it.

**It needs nothing installed alongside it.** Its dependencies are Windows system libraries, the Universal CRT — part of Windows 10 and later — and `MSVCP140.dll`, `VCRUNTIME140.dll` and `VCRUNTIME140_1.dll`. Those three are named by *Illustrator.exe* itself, so a machine that can start Illustrator already has them and no redistributable is required. Nothing from the SDK, from the developer's machine, or from the test harness is linked.

**What ties this artifact to that source is the commit, not the hash.** MSVC stamps a link timestamp into the PE header, so building the same source twice gives two different files: three builds of this source produced three different SHA-256s. Hash reproducibility would need `/Brepro`, which this project does not set. So the chain is: the build probe rebuilds both configurations from clean, records the commit it was at *and* whether the working tree was clean, and hashes what came out; the packaged archive is assembled from that same file rather than from a fresh build, so the binary a user receives is the one whose hash is in the evidence.

The build probe reports the working tree as it stood when it ran. The record cited here was taken after the final commit, on a clean tree, and the same binary was then installed and driven through the whole suite before being packed. *tools/make-release.ps1* refuses to pack a binary claiming Adobe as its publisher, or one carrying an absolute path from this machine.

## C. Architecture

One standalone live effect, registered as a post-effect accepting any input art but plugin groups, at *Effect > Shear…*. Its `Go` handler reads two angles from the parameter dictionary, takes the center of the incoming artwork's geometric bounds as the reference point, builds one matrix, and calls `AITransformArtSuite::TransformArt` once.

It is not an extension of Adobe's *Transform* effect because it cannot be: that effect has no shear state to expose, and no public interface adds behavior to an effect another plugin registered. [LIVE_SHEAR_INVESTIGATION.md](../LIVE_SHEAR_INVESTIGATION.md) has the evidence for both.

## D. Native equivalence

Each fixture is built twice, one copy carrying the live effect and the other sheared by *Object > Transform > Shear* with the same angles, and the two are compared on visible bounds. The live copy's own path anchors are compared before and after, because an effect that rewrote its own source would still look right and would still be wrong.

**61 cases: 55 matched, 4 differ for a reason that is proven rather than argued, and 2 could not be measured. None failed.** [RELEASE_TEST_MATRIX.md](RELEASE_TEST_MATRIX.md), [evidence/release-verdicts.tsv](evidence/release-verdicts.tsv).

**Not one case moved the source geometry.**

The tolerance is five thousandths of a point, about two microns — four hundred times finer than a 2400 dpi imagesetter can place a dot. It is not tighter because Illustrator will not report bounds more precisely than that where text is involved: the residues that turn up are 0.000488 and 0.000977 pt, which are 1/2048 and 1/1024 exactly, the last bit of a float32 rather than a measurement of anything.

The four that differ for a proven reason are the three brushes and stroked text; section R establishes why that is the only possible answer, and why on those four this effect is the one that gets the shear exactly right. The two that could not be measured are a zero-height line and a single-anchor path — Illustrator's own command declines to shear either, so there is nothing to compare against, and they are recorded as inconclusive rather than as agreement.

The arithmetic underneath is checked separately and without a host: **3,092 checks**, covering the matrix at every angle and axis, the determinant, the reference point as a fixed point, the exact extent of cubic Béziers against a hundred thousand samples each, the angle sanitizing, and the dialog layout at five display scales. [evidence/mathtest.txt](evidence/mathtest.txt).

## E. Reference point

**Settled, and it moved during this sprint.** Illustrator's own shear anchors on the center of the selection's **geometric** bounds: the Bézier outline, with strokes, effects, and the glyphs of area text excluded.

Two independent measurements agree.

The first fits the anchor out of artwork the native command actually produced. A shear along axis 0 displaces x in proportion to distance from the reference point's y and leaves y alone, so a straight-line fit through the anchors recovers the y exactly; axis 90 recovers the x. Every discriminating case comes back geometric, with residuals around 10⁻¹⁰. Fixtures whose geometric and visible centers coincide cannot tell the two apart and are reported as not discriminating rather than counted as agreement. [evidence/anchor-verdicts.tsv](evidence/anchor-verdicts.tsv).

The second works for artwork that has no path anchors to fit a line through — text, symbols, rasters. Two shears of the same angle about different reference points differ by a pure translation and nothing else, so subtracting the two bounding boxes recovers how far apart the reference points were, in points. **44 of 52 cases: the same reference point, exactly. Not one case anywhere shows a reference point in a different place.** The remaining 8 are the brushes and stroked text, where the two results differ by more than a translation — which means the difference is in what was transformed, not in where it was anchored. [evidence/artwork-anchor.txt](evidence/artwork-anchor.txt).

That covers paths open, closed, compound, and self-intersecting; groups plain, nested, clipped, and transformed; point, area, multi-line, stroked, retyped, resized, and deliberately off-center text; symbol instances; embedded rasters; and artwork rotated, scaled, or reflected before the effect was applied.

**Three things were wrong and were fixed, all found by pointing the measurement at artwork nobody had measured before:**

1. **The bounds flags were an invalid combination.** `kControlBounds` cannot be combined with `kNoStrokeBounds` or `kNoExtendedBounds`; together they return `kBadParameterErr`. Every request the effect made of the host failed, and it fell back to computing the box itself every single time. The previous release report explained those failures as the host declining to measure art outside the document tree — a satisfying story that was not what was happening. The SDK header is also wrong that `kNoExtendedBounds` implies `kNoStrokeBounds`: on a mitered triangle it leaves the 600 pt spike of the miter in. The flag table this was read off is in [evidence/bounds-flags.txt](evidence/bounds-flags.txt), and the `bounds flags` script selector prints it on demand.

2. **A clipping group anchors on its clip path**, not on the union of its children — even though the geometric bounds Illustrator *reports* for such a group are that union. Measured at 10 pt in y and 20 pt in x on one fixture, and settled with a clip path larger than what it clips, where the mask's box and the visible result are different rectangles: the native command follows the mask.

3. **Area text anchors on its frame, not its glyphs.** A frame whose ascenders overshoot its rectangle came back 3 pt taller than the rectangle, putting the reference point 1.5 pt from the native one.

The effect walks the artwork itself in preference to asking the host, for two reasons that are now measured rather than assumed: it measures paths from their segments, solving each cubic's derivative for the true extremes rather than taking the hull of the control points; and the host's own answer for a clipping group is the wrong box for this purpose. Where it does ask — text, symbols, rasters — it asks one leaf at a time, with flags that return exactly what the DOM calls `geometricBounds`.

The reference point is taken from the artwork the appearance pipeline hands the effect, not from the original object. That is deliberate, it is what makes the effect compose, and section G proves it rather than asserting it.

## F. Supported artwork

[SUPPORT_MATRIX.md](SUPPORT_MATRIX.md), generated from the release matrix rather than written by hand, and listing what the suite does not cover as untested rather than omitting it.

**Gradients and pattern fills shear with the artwork.** Rendered by the effect and by the native command, exported at the same size and compared pixel by pixel, a linear gradient, a radial gradient, and a pattern fill differ in **not one sampled pixel**. The pattern case also discriminates: with the native command's *Patterns* option off, 4.073% of pixels differ, so the comparison can see a pattern that failed to shear and is not merely holding two identical blanks against each other.

Pattern fills were reported as untestable in the previous release report, on the grounds that Illustrator would not draw one. That was wrong, and it is worth recording because the wrong conclusion was the comfortable one. A pattern assigned as `new PatternColor()` with its `.pattern` set reads back correctly through the DOM and draws nothing whatsoever; the identical pattern assigned from a swatch draws. Measured side by side in one document: the first contributes no non-white pixel, the second nearly two thousand. Three different ways of building a tile had all failed for that one reason — every one of them ended at the same constructor.

## G. Appearance composition

**18 of 18.** [evidence/appearance.txt](evidence/appearance.txt).

Substitution holds in both directions, which is the strong form of the claim:

- A *Transform* above a live Shear renders exactly what that *Transform* renders above Illustrator's own shear.
- A live Shear above a *Transform* renders exactly what Illustrator's own shear renders on that *Transform* expanded into real geometry.
- The two stack orders differ from each other, so the effect is not ignoring its position.
- Two Shear effects on one object render as two successive native shears.
- Editing one instance leaves the other alone; forty reorders leave the result unchanged; swapping them changes it; deleting one leaves the other intact; deleting the last restores the artwork.

Stack-order dependence is therefore a consequence of composition semantics and not an implementation accident. It is described in the README as how the effect works, rather than in the limitations as a defect.

## H. Persistence

**5 of 5.** One effect on a path, on live text, and on stroked art; two Shear effects; and Shear with a *Transform*. Each is saved, closed, reopened, edited through the parameter dictionary, then saved and reopened again. [evidence/persistence.txt](evidence/persistence.txt).

## I. Export

**12 of 12.** PDF and SVG, for a rectangle, a stroked rectangle, point text, a group, a gradient fill, and a clipping group: the exported file, opened back in Illustrator, has the same visible bounds as the canvas and contains no raster image. Point text is still a text frame in both formats. [evidence/export.txt](evidence/export.txt).

## J. Serialization and parameter safety

Two questions, both answered against this binary.

**Hostile values.** One function makes an angle safe, and every route a value can arrive by passes through it. 90°, ±180°, 10⁹, ±∞ and NaN all come out inside ±89°, wherever they were written — including straight into the parameter dictionary by a script, and including a saved document that stores 90, which reopens clamped rather than hanging. Each redraw runs behind a watchdog, so a value that made the effect fail to return would be reported as a hang rather than hanging the run. [evidence/limits.txt](evidence/limits.txt).

**Hostile shapes.** A parameter block this version did not write: no schema key at all, a schema number from a version that does not exist yet, a nonsense schema, a missing angle, a missing axis, an angle stored as text, an angle stored as a flag, and a block with no keys at all. Every one renders safely and deterministically. [evidence/schema.txt](evidence/schema.txt).

The schema number is worth having rather than decorative, and that was measured too: a block carrying a later version's keys survives **the plugin's own dialog writing it back** — not merely the test bridge — and the block is stamped with the version that last wrote it, so it says what it means rather than what it used to mean. That is what lets a reference-point control be added later without making existing documents ambiguous.

## K. Blends

**12 of 12.** [evidence/blend.txt](evidence/blend.txt).

The effect implements Illustrator's interpolation handler, and until this sprint nothing had ever driven it — executable code in a shipped binary that the host may call on its own. Illustrator **does** call it while building a blend. Since no script can observe that, the handler writes to the plugin's trace and the probe reads it back.

The axis takes the short way round modulo 180, which is the arithmetic that is easy to get wrong, and it was checked where a naive midpoint would give the wrong answer: an axis of 179° blended with 0° passes through 179.5° rather than 89.5°; 179° with 1° passes through 180° rather than 90°; 89° with −89° passes through −90° rather than 0°.

## L. Dialog

Driven through the window manager from a second process, because the call that opens the dialog blocks until it closes. The checks that need to know what the artwork did *during* the dialog read the plugin's own trace, and the probe now verifies that tracing is actually live before relying on it — Illustrator reads `LIVESHEAR_LOG` from its own environment, so setting it after Illustrator has started does nothing, and a check that silently loses its instrument is worse than one that says so.

OK commits; Cancel, Escape, and the title bar's close button each restore both the artwork and the parameter; Enter commits; dragging through several positions does not compound; a value typed with a decimal comma or with trailing text commits; the arrow keys nudge; and the title and labels read back as the code points they should be.

That last check exists because **a screen capture of the dialog found a defect no numeric check would have.** The window class was registered with the narrow entry point while `DefWindowProc` resolved to the wide one, so the title "Shear" was stored as its own bytes reinterpreted as UTF-16 and displayed as 桓槌r; the degree sign, written as UTF-8 into an ANSI call, came through the machine's code page as two half-width katakana. Every string the dialog touches now goes through the wide entry points, and the *Appearance* panel's description goes through `SetUnicodeStringEntry` rather than a plain `char*`. The picture is kept at [evidence/dialog.png](evidence/dialog.png).

Also fixed here: the dialog rounded one typed number three different ways. The slider rounded a half away from zero, the field's formatting rounded a half to even, and the state kept the unrounded number until something re-read the field — typing 18.25 committed 18.2 while the slider sat at 18.3. Rounding happens once now, on the way in, so the number shown, the slider position, and the value stored are the same number. The resolution that gives is a tenth of a degree, and that is stated in the limitations.

**Where the window opens is now measured, and it was wrong.** The dialog opened in the top-left corner of the primary monitor on every invocation, for five releases, and the probe never noticed because it read the window's size, its caption, its labels, and everything it did, and never once a coordinate. The cause was `CW_USEDEFAULT`, which reads as "let Windows choose" and applies to overlapped windows only: for a popup, which this is, the coordinates are documented to be taken as zero. It is centered on Illustrator's window now and clamped into the work area of the monitor that lands on, and both are checked — the centers coincide exactly when Illustrator is maximized, and the clamp is driven rather than assumed by putting Illustrator in the corner at 487 × 140, where centering alone would open the dialog thirty pixels above the top of the desktop and it opens at the edge instead. The plugin's own trace records the position it chose, so the driver's measurement has a second source.

**High-DPI scaling is not exercised.** The only display available reports 96 dots per inch. What can be checked without a monitor is arithmetic, and it is: every control's box comes from one table in *ShearLayout.h*, which the dialog builds from and the test reads, and the test walks it at 100%, 125%, 150%, 200%, and 250% checking that nothing leaves the window, nothing overlaps, every focusable control stays at least sixteen pixels across, and the tab order still reads left to right and top to bottom. That covers the layout and not the rendering: font substitution, and the trackbar's own idea of its minimum height, are outside it. The release notes do not claim scaling works.

## M. Undo and redo

**One pass through the dialog costs one undo step**, however many slider positions it went through. Applying the effect is one step, and redo puts it back. Deleting an effect and reordering the stack through the script bridge each cost one undo step too, and undo leaves the document coherent; a parameter edit made through the bridge is not an undo step, which is stated in the limitations. The source path is unchanged after all of it. [evidence/undo.txt](evidence/undo.txt).

## N. Performance

About **47 ms per evaluation** including Illustrator's own redraw, against 31 ms for the same loop with nothing to recompute — and essentially flat from one rectangle to a group of two hundred children, which is what one matrix and one `TransformArt` call should look like. A document with two hundred independent Shear effects builds, saves, and reopens with all two hundred objects intact.

The earlier figures for this were negative, because the measurement was taken across the COM bridge and the round trip dwarfed the effect. Timing inside a single scripting call fixed it. [evidence/stability.txt](evidence/stability.txt).

## O. Ordinary use

Every other probe shears one scripted object in an empty document, which is not how anyone uses Illustrator. This one asks what a person would do in the first five minutes that nothing else had ever done. [evidence/everyday.txt](evidence/everyday.txt).

Selecting three objects at once and applying the effect gives all three the effect, **each sheared about its own center** — which is not what Illustrator's own command does with a multiple selection, since that shears the whole selection about one center. Neither is wrong: a live effect is applied per object and can only anchor on what it is handed. It is written into the README rather than left as a surprise.

Also covered: text set along a path, a graphic style carrying the effect to another object, shearing one child of a group without disturbing its siblings, duplicating a sheared object and editing the duplicate, and copying one into another document.

## P. Memory, resources, and what the code review found

The effect acquires no suites of its own beyond the import table the SDK manages, creates no temporary art, and holds no handle past the callback that gave it. The dialog registers one window class lazily and unregisters it at shutdown, creates one font, and deletes it after its modal loop rather than during `WM_DESTROY`, when the controls still hold it, and hands the application's own quit message back instead of swallowing it. Illustrator quits cleanly in 1.4 to 3.5 seconds from each of four states the plugin can leave it in, with nothing new in the Windows event log.

Fixed across the two hardening sprints, each described where it lives: the reference point came from the wrong box; the parameter clamp lived in the dialog and so did not apply to a value from a saved document; `DeleteObject` on the dialog's font ran while the child controls still held it; the modal loop consumed `WM_QUIT`; the window class was never unregistered; six `reinterpret_cast<HMENU>(int)` conversions were narrowing in reverse on 64-bit; the arrow keys never reached the numeric fields because `IsDialogMessage` consumed them; the dialog mangled its own text; a preview that would change nothing still asked Illustrator to re-render; the binary claimed Adobe as its publisher; and the linker stamped the build machine's symbol path into the shipped binary.

Found and fixed in this sprint: the script bridge bounds-checked the source index of `move effect` but handed its *destination* index to `InsertNthPostEffect` unchecked.

**The script bridge ships enabled, deliberately**, so that the binary the tests pass against is the binary that ships. It is documented in [BUILDING.md](BUILDING.md) as a test interface with no stability guarantee. It grants no privilege a script does not already have through Illustrator's own scripting and action interfaces, and every argument that reaches a host API is range-checked first.

## Q. The host crash

Illustrator 30.7.0 dies with an access violation inside *Illustrator.exe* under sustained scripted document churn.

**Proven: this plugin is not necessary for it.** Three runs of forty create/close cycles that never touch the effect, with the plugin uninstalled, completed 9, 32, and 40 ([evidence/crash-control.txt](evidence/crash-control.txt)).

**Not proven, and not claimed: that having the plugin loaded makes no difference to how often it happens.** With the plugin installed the same runs completed 2, 20, and 3. Three runs per arm with that spread cannot distinguish a real effect from noise, and it has never been claimed that they can.

During this sprint the full suite crashed three times, at three different fault offsets — `0xdfdd45`, `0x849dee`, and the earlier `0x18162a7` — always well into a long run. Twice it happened at the same probe, which looked like a reproducible sequence, so it was controlled: the same composition-then-save work, with the effect and without it, alternated, each trial in a fresh Illustrator. **Neither arm crashed in six trials**, which says the specific sequence is not the cause and points back at cumulative session load. [evidence/sequence-crash.txt](evidence/sequence-crash.txt).

The practical consequence is in the test suite rather than the product: every probe that drives Illustrator now gets a fresh one, because a result that depends on how much work preceded it is not a measurement. A fourth run did not crash outright but began failing checks that pass cleanly in isolation — forty reorders came back with eighteen errors where a fresh host gives eighteen passes out of eighteen.

**This is a host defect under scripted automation, not something a person using Illustrator will meet:** nothing anyone does in the interface creates and destroys documents at that rate.

## R. Artwork Illustrator generates from a path

A brush is not artwork, it is a rule for making artwork out of a path, and that leaves two defensible answers. Transforming the path destructively lays the brush along it again; a live effect is handed the art the brush already produced and can only transform that, because the brush definition is not what arrives and there is no way back to it.

So the question is not whether this effect matches the destructive command — it cannot — but whether it behaves the way a live effect is supposed to. **Adobe's own *Transform* effect settles that.** Put through the same vertical scale, Adobe's effect differs from Adobe's own command by 1.276% of sampled pixels on a pattern brush, 0.167% on an art brush and 0.220% on a calligraphic brush, while a plain rectangle, a stroked rectangle, and stroked text — the controls — differ in **not one pixel**. [evidence/generated-art.txt](evidence/generated-art.txt).

Those three brushes are therefore recorded as EXPECTED rather than FAIL in the matrix, and the solver's own self-test guards the excuse: the same difference on a fixture that is not regenerated still fails, and a brush that moved its own source geometry still fails.

**Stroked text belongs with them**, and one measurement settles it without needing any oracle at all.

A shear along the horizontal axis maps (x, y) to (x + (y − c)·tan θ, y). The y is untouched, so the vertical extent of the artwork cannot change. Anything that does change it did not come from the shear.

Sheared 30° horizontally, the effect moves the top and bottom of stroked text by **exactly zero**, and the destructive command moves them by **0.40 pt**. The same holds for all three brushes — 2.20 pt, 1.05 pt, and 0.02 pt for the destructive command, zero for the effect — while a plain rectangle and a stroked rectangle, the controls, move zero either way.

So on this artwork the two routes do not merely differ: the effect is the one that keeps the shear exact, and the destructive command is the one that changes something the shear did not do, because it regenerates the stroke around the sheared outline. The 0.40 pt difference in visible bounds is that regeneration, and rendered it comes to 0.099% of sampled pixels — edge antialiasing on a 6 pt stroke around 96 pt glyphs.

## S. Without the plugin

Illustrator shows its standard missing-plugin warning naming *Shear (LiveShear.aip)*, opens the document, and draws the artwork sheared from the cached result. The source geometry is neither expanded nor flattened, text stays live, and a file re-saved from that state loses nothing. What stops is the effect itself, so an edit made without the plugin renders against the old shape — Illustrator's standard behavior for any missing effect.

## T. What would have to change

Nothing here is a correctness, persistence, serialization, or documentation blocker. To take the qualifications off the verdict:

1. **Run the dialog on a display above 100%.** Needs a scaled monitor, or a second display this machine can be told to scale without disturbing the one in use.
2. **Compare GPU and CPU preview.** Needs a machine with a GPU that Illustrator will use.
3. **Run it on Windows 10.** A neighboring Illustrator version has since been tried and is settled rather than outstanding: Illustrator 2025, given its own folder and its own preference, did not load this build at all, and neither did *Subgroup*'s. A build per Illustrator generation is the answer, not a wider claim for this one. The forward direction — a 2026 build under Illustrator 2027 — cannot be tested until that version exists.
4. **Decide whether the crash deserves a stronger experiment** than three runs per arm, or whether "not necessary for it, influence unmeasured" is the honest end of it.

## U. Evidence

Raw output from every probe is in [evidence/](evidence/). [RELEASE_TEST_MATRIX.md](RELEASE_TEST_MATRIX.md) is generated from it by *tools/make-test-matrix.py*, and [SUPPORT_MATRIX.md](SUPPORT_MATRIX.md) by *tools/make-support-matrix.py*. Nothing in either is transcribed by hand.

### Which evidence describes the binary being shipped

Every file under *evidence/* except two was written after the build recorded in [evidence/build.txt](evidence/build.txt), against the binary that hash names. The exceptions are **native-shear.tsv** and **sequence-crash.tsv**, which come from probes deliberately run outside the suite and were last written against an earlier build. Nothing in this release touches what they measure — 0.1.0 changes only the version the plugin reports, and the candidate before it moved where the dialog window opens, neither of which is reachable from the effect's geometry or from the crash comparison — but the matrix does not distinguish the two cases, so it is said here instead.

For 0.1.0 that evidence came from more than one pass of the suite rather than a single run, and the timestamp rule above is what makes that safe to say. The machine was short of memory and the suite was killed partway through twice; the probes it had not reached were then run one at a time. Three of them had to be re-measured for reasons that were not the plugin: the release matrix's `patternFill` case, the fills probe, and the everyday-use probe all died on the same `app.paste()` failure, a clipboard race on a machine several applications were sharing, and all three came back clean afterward — `patternFill` at a difference of 0.00e+00 from the native result. The blend probe and two dialog checks were re-run because the first pass was started without `LIVESHEAR_LOG` set, and without the trace there is no way to see whether Illustrator called the interpolation handler at all. Every one of these ran against the same installed binary, whose hash is compared with the build record before anything is packed.

That distinction is worth making because it has already caught something. In the run for this release the persistence probe printed its heading, died on an RPC failure when Illustrator dropped the connection, and left its previous results in place; the suite's summary showed nothing wrong, and the matrix would have quoted rows measured against a different binary as though they described this one. Comparing each evidence file's timestamp against the build record is what found it. That check belongs in the release sequence, not in a person's memory.

Both generators, and the two solvers that turn measurements into verdicts, are themselves tested against rows whose right answer is known by construction — **15 checks** — because a bug in a solver would turn a real failure into a green matrix, which is the one kind of bug that running more tests cannot catch. That test earned its place this sprint: the release probe was skipping the oracle entirely for any angle below a hundredth of a degree, on a premise that turned out to be false, and comparing a sheared result against artwork nothing had been done to.

Every path in the evidence is written through a redaction step, so nothing in it names the machine it was measured on.
