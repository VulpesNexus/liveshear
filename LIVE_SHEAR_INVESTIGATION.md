# Live Shear: restoring the missing affine degree of freedom

An investigation into why Adobe Illustrator's non-destructive Appearance system has no shear, and whether it can be given one.

Everything below was measured against **Adobe Illustrator 2026, version 30.7.0 (build 30.7.0.114), 64-bit, on Windows 11**, using the **Adobe Illustrator 2026 SDK, build 114**. Where a claim rests on a host measurement, the evidence file that produced it is named. Raw output lives in [docs/evidence/](docs/evidence/).

The investigation produced a working plugin. Its source is in [plugin/](plugin/), and [README.md](README.md) covers building and installing it.

---

## A. Current Illustrator limitation

Illustrator can shear artwork in exactly one place: *Object > Transform > Shear…*, which rewrites the geometry in place. The same command is reachable through the *Shear* tool (*O*), through *Transform Each*, and through the *Transform* panel's shear field — all of them destructive.

The Appearance system offers *Effect > Distort & Transform > Transform*, which is the live effect internally named `Adobe Transform`. Its controls are Scale (horizontal and vertical), Move (horizontal and vertical), Rotate, Reflect X, Reflect Y, a nine-point reference-point pin, a copy count, and a Random toggle. There is no shear control, and nothing equivalent to one.

So of the six degrees of freedom in a 2D affine map, the Appearance stack exposes translation (2), rotation (1), and scale (2), and omits shear (1). That is the whole of the gap.

Enumerating every live effect registered with the running application — all 93 of them — confirms there is no shear effect of any kind, under any name ([docs/evidence/registry.txt](docs/evidence/registry.txt)). The only other effect that can express a shear at all is `Adobe Free Distort`, and only by accident: it stores a source quad and a destination quad, so a parallelogram destination happens to be an affine map. It has no angle input and no way to type a number.

---

## B. Native Shear semantics

The *Shear* command is not implemented in a plugin; it lives in *Illustrator.exe* itself. Its action-manager event is `adobe_shear`, and the SDK header `actions/AIObjectAction.h` documents its seven parameters:

| Parameter | Key | Type | Meaning |
| --- | --- | --- | --- |
| Shear Angle | `shag` | real | how far the artwork leans, in degrees |
| Axis Angle | `angl` | real | the direction the shear runs along, in degrees |
| About dX | `detX` | real | horizontal offset of the origin from the selection center |
| About dY | `detY` | real | vertical offset of the origin from the selection center |
| Copy | `copy` | bool | shear a duplicate instead of the original |
| Objects | `objt` | bool | shear the geometry |
| Patterns | `patn` | bool | shear pattern fills |

The dialog's *Horizontal* and *Vertical* radio buttons are not separate parameters; they set the axis angle to 0 and 90.

### The matrix

Playing `adobe_shear` on a path with known anchor points and reading the points back in Illustrator's own coordinates gives the transformation directly. Across 23 parameter combinations the operation is affine to within 10⁻¹³ pt, and the matrix is exactly

```
M = T(origin) · R(φ) · [ 1  tan θ ] · R(−φ) · T(−origin)
                       [ 0    1   ]
```

with θ the shear angle, φ the axis angle, and the origin at the center of the selection's geometric bounds offset by (detX, −detY). Expanded into Illustrator's `AIRealMatrix` (where x′ = a·x + c·y + tx and y′ = b·x + d·y + ty), and writing k = tan θ:

```
a = 1 − k·cos φ·sin φ        c = k·cos² φ
b = −k·sin² φ                d = 1 + k·cos φ·sin φ
```

The determinant is 1 for every θ and φ, so shear preserves area exactly.

Two details are worth stating because they are easy to get wrong:

- **detY runs the other way.** The offset is expressed in the dialog's y-down convention, while Illustrator's artwork coordinates are y-up. A `detY` of +50 moves the origin 50 pt *down* the page, which is −50 in artwork coordinates. Every case with a non-zero `detY` disagreed with the obvious reading of the matrix by exactly twice that amount until the sign was flipped.
- **The angle has a practical ceiling.** tan θ is unbounded at 90°. A shear of 89° completes instantly; 89.9° sends Illustrator into a computation that had not returned after several minutes and had to be abandoned. The plugin's slider therefore stops at ±89°.

Evidence: [docs/evidence/native-shear.tsv](docs/evidence/native-shear.tsv), verified by `tools/solve-shear.py`, which recovers the matrix from the point data by least squares and compares it against the formula the plugin uses. All 23 cases match, worst deviation 3.3 × 10⁻⁶ — which is the rounding in the recorded coordinates, not a disagreement.

---

## C. Native Transform internals

`Adobe Transform` is implemented by *Plug-ins/Extensions/Transform.aip* (internal plugin name `ai_plugin_TransformEach`). Its complete parameter vocabulary, read out of the binary and then confirmed by driving each key in the host:

| Key | Type | Consumed by the renderer? |
| --- | --- | --- |
| `moveH_Pts`, `moveV_Pts` | real | yes |
| `rotate_Radians` | real | yes |
| `rotate_Degrees` | real | **no** — stored for the dialog only |
| `scaleH_Factor`, `scaleV_Factor` | real | yes |
| `scaleH_Percent`, `scaleV_Percent` | real | **no** — stored for the dialog only |
| `reflect`, `reflectX`, `reflectY` | bool | yes; `reflect` gates the other two |
| `pinPoint` | int | yes; the nine-point reference, center when absent |
| `numCopies`, `doCopy` | int, bool | yes |
| `randomize`, `Transform:random seed` | bool, — | yes |
| `scaleLines`, `scaleLineWeight` | bool, real | yes |
| `policyForPreservingCorners` | — | corner-radius handling |
| `AbsoluteScalingTransformEach`, `ConstrainWHForTransformEach`, `TransformEachConstrain` | — | *Transform Each* dialog state |

The split between the two forms of the angle and the two forms of the scale is the same idea as the SDK's own `TranslateTransform`, which stores a move as both h/v and distance/angle so that reopening the dialog does not show round-off. The dialog writes both; the renderer reads only one.

An empty parameter dictionary renders the identity. That is worth stating because a symmetric test shape can make a wrong point-correspondence fit a mirror just as exactly as the identity — the first run of this measurement did read a reflection, and it was an artifact of using a rectangle. The measurement was redone with a five-sided polygon that has no affine symmetry.

### Composition order

Measured, not assumed. Each component was driven alone and then in combination, the appearance was expanded to make the rendered result readable, and the resulting matrix was compared against every permutation:

```
M = T(move) · T(pin) · R(rotate) · S(scaleH, scaleV) · T(−pin)
```

Scale happens first, then rotation, both about the reference point; the move is a plain displacement and commutes with the reference-point translations, so it can equivalently be described as happening before or after. The combined scale-and-rotate cases are consistent with "scale then rotate about the center" and with nothing else.

Evidence: [docs/evidence/effect-matrix.tsv](docs/evidence/effect-matrix.tsv), analyzed by `tools/solve-effect.py`.

---

## D. Hidden shear investigation

**Q1: can Illustrator's existing Transform effect internally represent shear? No.**

Two independent lines of evidence, one static and one in the host.

### The binary contains no shear

Every printable string in *Transform.aip* was extracted and searched for `shear`, `skew`, `matrix`, `affine`, `slant`, `tangent`, and `axis`. The parameter vocabulary is the table in section C and nothing else. There is no matrix key, no shear key, and no generic affine storage. The effect composes its matrix internally from move, scale, rotate, and reflect; the stored state is those scalars.

### The host ignores every candidate key

The plugin can write arbitrary typed values into the parameter dictionary of any live effect already sitting in an object's appearance, including Adobe's own. Twenty-five candidate keys were written into a real `Adobe Transform` effect — `shear`, `shear_Degrees`, `shear_Radians`, `shearH_Degrees`, `shearV_Degrees`, `shearAngle`, `shearAxis`, `shearAxis_Degrees`, `shearX`, `shearY`, `skew`, `skewX`, `skewY`, `skew_Degrees`, `skewAngle`, `slant`, `slant_Degrees`, `axis`, `axis_Degrees`, `tangent`, and five matrix-typed keys (`matrix`, `transformMatrix`, `affine`, `Matrix`, `shearMatrix`) — each with a value large enough that a real shear would be unmistakable.

None of them changed the rendering by so much as a rounding error.

The control for that experiment matters as much as the result: writing the documented key `moveH_Pts = 40` into the same dictionary, by the same mechanism, moved the rendered artwork 40 pt to the right while leaving the source path untouched. So the injection path demonstrably reaches Adobe's effect and makes it re-render. The candidate keys were ignored because the effect has nothing to do with them, not because the experiment could not reach it.

Evidence: [docs/evidence/history/latent-shear-probe-2026-09-12.txt](docs/evidence/history/latent-shear-probe-2026-09-12.txt).

**There is no latent shear in the native Transform effect. Outcome 1 — the "BEST" case — is not available.**

---

## E. Native-effect augmentation feasibility

**Q2: can a third-party plugin make the existing Transform effect expose and edit shear?**

This question is now partly moot — there is no shear state to expose — but the mechanics are worth recording, because they were established along the way and they bound what any future attempt could do.

What a plugin provably **can** do to a built-in live effect, all demonstrated in the host:

- **Read its parameter dictionary in full.** `AIArtStyleParserSuite` walks an object's pre-effects, paint fields, per-field effects, and post-effects, and hands back each effect's `AILiveEffectParameters` dictionary for unrestricted inspection.
- **Write into that dictionary**, with any key and any supported type, including keys Adobe never defined.
- **Make the effect re-run** with the modified dictionary, by rebuilding the style through the parser and reinstating it on the art.
- **Append a built-in effect to an object's appearance with parameters chosen programmatically**, via `GetLiveEffectHandleByName` and `NewArtStyleByMergingLiveEffect` — which is how every `Adobe Transform` measurement in this report was taken, without ever opening Adobe's dialog.

What a plugin **cannot** do:

- **Add a parameter the effect will honor.** Unknown keys persist in the dictionary and survive save and reload, but the renderer ignores them. The effect's behavior is fixed in Adobe's binary.
- **Replace or intercept the effect's Go callback.** `AILiveEffectSuite` has no call to re-point an existing effect's owner, and the owning `SPPluginRef` is set once at registration by the plugin that registers it.
- **Replace its edit dialog.** `EditParameters` is marked "Internal. Do not use." in the SDK header, and the edit message is dispatched to the registering plugin.

Classification: **IMPOSSIBLE THROUGH PUBLIC SDK** for augmenting the effect's behavior; **SUPPORTED** for reading and writing its parameters. A companion panel over Adobe's Transform effect could therefore drive its documented parameters perfectly well — it just has no shear to drive.

There is one genuinely interesting near-miss, recorded here because it is the only way to get a live shear out of Adobe's own code: **`Adobe Free Distort` stores a source quad and a destination quad** (`src0h`…`src3v`, `dst0h`…`dst3v`). A parallelogram destination is exactly an affine map, so writing computed corner points into a Free Distort effect would produce a live shear rendered entirely by Adobe. See section I for why that is not the recommended architecture.

---

## F. Standalone Live Effect feasibility

**Q3: can a third-party live effect implement equivalent non-destructive shear cleanly? Yes — built and running.**

The plugin registers one effect:

- unique name `VulpesNexus Shear`, title **Shear**, version 1.0
- registered as `kPostEffectFilter`, accepting `kAnyInputArtButPluginArt`
- menu item at *Effect > Shear…* — see [Where the menu item goes](#where-the-menu-item-goes)

Its `Go` handler reads two reals from the parameter dictionary, takes the center of the incoming art's bounds as the anchor, builds the matrix from section B, and calls `AITransformArtSuite::TransformArt` once, with `kTransformObjects | kTransformChildren`, the gradient and pattern flags, and `kTransformLinkedMasks`. That is the entire implementation: about forty lines of arithmetic and one API call.

The rendered result was measured the same way the native command was — apply, expand the appearance, solve the affine from the anchor points — over seven parameter combinations including three arbitrary axis angles. **Every one matches the formula exactly, and matches what *Object > Transform > Shear* produces for the same numbers.** A 200 × 120 pt rectangle sheared 30° renders with its left edge at 65.358984 and its right edge at 334.641016 under both routes, to six decimal places.

### Where the menu item goes

For three releases the effect registered itself with the category `Distort & Transform`, on the reasonable assumption that naming Illustrator's own submenu would put the item in it. It does not, and the menu read *Distort  Transform* — two spaces, no ampersand — which is what finally got this looked at.

`AIMenuSuite::CountMenuGroups` and `GetNthMenuGroup` list every menu group the host holds, and that list settles it. Illustrator's own submenu is a group named `Live Vector &Distort && Transform`; ours was a second group named `Live 3rd Party Distort & Transform`. The prefix is not conditional. Four categories were registered on throwaway effects and the group each landed in was read back from `AddLiveEffectMenuItem`'s own out-parameter:

| Category passed | Group the item landed in |
| --- | --- |
| `Distort & Transform` | `Live 3rd Party Distort & Transform` |
| `Distort && Transform` | `Live 3rd Party Distort && Transform` |
| `&Distort && Transform` | `Live 3rd Party &Distort && Transform` |
| `Live Vector &Distort && Transform` | `Live 3rd Party Live Vector &Distort && Transform` |

So `"Live 3rd Party "` is pasted on whatever it is given, and **a category can never name an Adobe submenu**. It names a new one beside it. And because the group name is also the submenu's label, and the label goes through Windows mnemonic handling, the bare `&` was read as a mnemonic prefix on the following space and eaten — Adobe's own group name spells it `&&`, with `&D` marking the accelerator.

**Adobe's submenu can be reached, by a different route.** A menu group is looked up by exact name, and the header says adding one that exists returns the existing one — so creating `Live 3rd Party Distort & Transform` *before Illustrator does*, with Adobe's group named as the near group, puts it inside Adobe's submenu, and the host's own effect item then lands there. It works: both groups report the same `AIPlatformMenuHandle` from `GetMenuGroupRange`, Adobe's items at 0–7 and ours at 7, while a third submenu (`Live Vector &Stylize`) reports a different handle — the control that makes the shared handle mean something.

Two things had to be got right for that. The group cannot be created during `StartupPlugin`: plug-in load order is indeterminate, Adobe's group does not exist yet, and naming it as the near group fails with `kBadParameterErr`. It has to happen from `kAIApplicationStartedNotifier`, which the SDK's `Plugin` framework already subscribes to and surfaces as `PostStartupPlugin()`. And the near-group name has to carry the mnemonic markup exactly: `Live Vector Distort & Transform` fails where `Live Vector &Distort && Transform` succeeds.

**It was not shipped, because it costs *Apply Last Effect*.** Measured across four placements, each a fresh Illustrator, each applying the effect through its own menu item and then reapplying to a second object:

| Placement | Group | Effect applies | *Apply Last Effect* |
| --- | --- | --- | --- |
| Registered at startup, category `Distort & Transform` | `Live 3rd Party Distort & Transform` | yes | works |
| Registered at `PostStartupPlugin`, same category | same | yes | works |
| Group pre-created in the usual third-party place | same | yes | works |
| Group pre-created inside Adobe's submenu | same | yes | **does nothing** |

The third row is the discriminator: creating the group ahead of the host is harmless, so it is the *position* that breaks it, not the pre-creation. In the broken case *Effect > Apply Last Effect* returns without error and leaves the artwork alone, while its sibling *Effect > Last Effect*, which reopens the dialog, still works. Illustrator's last-effect bookkeeping evidently expects the item to be in the third-party part of the menu, and nothing in the SDK exposes it — there is no call to set the last effect, only the notifier strings `kAIAdobeApplyLastEffectCommandPreNotifierStr` and friends.

Given the choice between a cosmetic placement and a menu command that silently does nothing, the item went to the top level of the *Effect* menu instead: no category at all, which puts it in Illustrator's `Effects 3rd Party` group with one line and no submenu wrapped around one command. *Apply Last Effect* works there.

### On identifiers, when many plugins are installed

Every name a plugin registers — the effect's unique name, menu group names, the plugin's own name — lives in one flat namespace shared with every other plugin and with Adobe's. Nothing enforces uniqueness. Registering a name that is already taken was tried three times and the host's answer read back each time:

| Name registered a second time | `AddLiveEffect` returned | The name then resolves to |
| --- | --- | --- |
| `VulpesNexus Shear`, this plugin's own | `0` — success | the **first** registration |
| `Adobe Transform`, Illustrator's own | `0` — success | the **first** registration |
| `VulpesNexus Nobody`, taken by nothing | `0` — success | the second, i.e. the new one |

The third row is the control: lookup does return newly registered effects, so "the first" in the other two rows is a real finding and not an artifact. **A duplicate is accepted silently and then ignored.** Two plugins claiming one effect name would not produce an error anywhere; the one that loaded first would answer for both, and a document saved by the second would render through the first one's code.

There is no registry and no allocation authority, so the only defense is the name itself. Everything persistent here carries a publisher prefix — `VulpesNexus Shear` for the effect, `VulpesNexusAboutPluginsGroupName` for the Help group — which is the same convention Adobe follows with `Adobe Transform`. A collision then needs another vendor to choose the identical string, prefix included.

Two things are *not* at risk, which is worth saying because they look like they would be. Parameter dictionary keys (`shearAngle`, `axisAngle`) live inside the effect's own parameter dictionary, one per effect instance, so they cannot meet another plugin's keys. And the keyboard-shortcut dictionary key of the effect's menu item is derived by the host as `"Live "` plus the effect name — `Live VulpesNexus Shear` — so it inherits whatever uniqueness the effect name has and adds no new surface.

### One thing the host was thought to have refused

`AIArtSuite::GetArtTransformBounds` with `kControlBounds | kNoExtendedBounds` fails. That much was right. The explanation given here for a long time was wrong, and it is worth leaving the correction visible rather than quietly replacing it, because the wrong explanation was comfortable and survived a whole sprint.

It was written up as: *Illustrator will not compute control bounds for art that is not in the document tree, which is exactly the situation a live effect runs in.* That is a satisfying story — it explains the failure, it blames nothing, and it justifies writing a fallback.

It is not what was happening. The call fails on art sitting quietly in the document tree too, and the error it returns is `kBadParameterErr` — `1346458189` — not a refusal. `kControlBounds` cannot be combined with `kNoStrokeBounds` or `kNoExtendedBounds` at all; the SDK says as much, obliquely, under `kControlBounds`: *when off, `kNoStrokeBounds`, `kNoExtendedBounds` and `kExcludeUnpaintedObjectBounds` can be combined to ignore certain aspects of the visual bounds.* The flags were simply wrong, every call failed, and the fallback ran every single time.

The header is also wrong about `kNoExtendedBounds`, which it says *implies `kNoStrokeBounds`*. It does not: on a mitered triangle, `kVisibleBounds | kNoExtendedBounds` still carries the 600 pt spike of the miter. Only setting both gives the outline. The table this was read off is printed by the `bounds flags` script selector and kept in [docs/evidence/bounds-flags.txt](docs/evidence/bounds-flags.txt).

With `kVisibleBounds | kNoStrokeBounds | kNoExtendedBounds` the host answers, and answers with exactly what Illustrator calls `geometricBounds`. The effect still walks the art itself in preference to asking, for two reasons that are now measured rather than assumed: it measures paths from their segments, solving each cubic's derivative for the true extremes instead of taking the hull of the control points; and the host's answer for a **clipping group** is the union of its children, while the shear command anchors on the clip path alone. Section J has the measurements.

The general lesson is the one worth keeping: a failing API call had an explanation attached to it that nobody tested, and the explanation was load-bearing. The first version of the effect fell back to `GetArtBounds` and so anchored on *visible* bounds — 295 pt from the right answer on that mitered spike — and the story about the document tree is part of why that went unexamined for so long.

---

## G. Transform+ feasibility

Not justified, and not built.

The case for a `Transform+` effect rests on standalone Shear composing badly with the native Transform effect. It does not. Stacking them behaves exactly as affine composition should: `Shear` then `Transform` and `Transform` then `Shear` produce measurably different geometry, and each is the correct product of the two matrices in that order. Users can reorder them in the *Appearance* panel and get the predictable answer.

Rebuilding Adobe's Transform effect would mean reimplementing move, scale, rotate, reflect, the nine-point pin, copies, random, stroke scaling, and corner-radius policy, and then keeping all of that in step with Adobe's behavior across versions — to gain nothing that stacking two effects does not already give. The smaller effect is the better architecture.

The one thing `Transform+` would buy is a single dialog with all seven degrees of freedom in it, instead of two dialogs. That is a convenience, not a capability, and it is not worth the maintenance surface.

---

## H. Host test results

Milestones, using the scale the brief asked for:

| State | Reached |
| --- | --- |
| CONCEPT | yes |
| COMPILES | yes |
| HOST LOADS | yes — plugin loads in Illustrator 30.7.0 and answers on its script bridge |
| EFFECT APPLIES | yes — geometry matches the native command to six decimal places |
| APPEARANCE EDITABLE | yes — parameters editable in place, two instances independent, reorderable |
| SAVE/REOPEN VERIFIED | yes — including a round trip through a machine without the plugin |
| REGRESSION VERIFIED | yes — the behavior suite below passed 24 of 24 and the dialog 4 of 4, against the build current when this section was written |

Those two counts are from this investigation, not from the release. The suite that decides whether the plugin ships is a different and much larger one, it is generated rather than transcribed, and its tally is in [docs/RELEASE_TEST_MATRIX.md](docs/RELEASE_TEST_MATRIX.md). Read that one for what is true of the binary being released; read this section for how the prototype was proven at the time.

### Behavior suite

From [docs/evidence/history/behavior-2026-09-13.txt](docs/evidence/history/behavior-2026-09-13.txt):

- artwork renders sheared, and the **source path is byte-identical before and after** — the effect is genuinely non-destructive
- **live text stays live text**: typename, contents, and point size all survive; retyping and changing the font size both re-run the effect
- **two instances are independent** appearance entries with independent parameters
- **stack order matters** and behaves like affine composition
- **save and reopen** preserves the effect, its parameters to the digit, and the liveness of text; the reopened effect is still editable
- **PDF export** of sheared artwork succeeds
- **duplicating** an object and **pasting into another document** both carry the effect
- **undo removes the effect and redo restores it**, in single coherent steps
- art types accepted: path, **group**, **nested group**, **compound path**, **clipping group**, **symbol instance**, **embedded raster**, **text frame**

### The dialog

The dialog was driven the way a person drives it, from a second process, while the scripting call that opened it was blocked ([docs/evidence/dialog.txt](docs/evidence/dialog.txt)). All four checks pass:

- the dialog opens from the Appearance panel's edit path, and **OK commits the value the slider was left on**
- the numeric field tracks the slider: dragging to 10, 20, 30, 40 leaves it reading `10.0`, `20.0`, `30.0`, `40.0`
- **dragging does not compound.** After moving through 10°, 20°, 30° and 40°, the artwork is 300.692 pt wide, which is exactly a single 40° shear of a 200 × 120 pt box. Each preview is derived from the unmodified source, as the brief required; the plugin's own trace shows four `Go` calls with shear = 10, 20, 30, 40, each building its matrix from scratch
- **Cancel restores both the artwork and the parameter**: an effect sitting at 5° that is dragged to 35° and canceled is back at 5° with the original bounds
- a value **typed into the numeric field** (22.5) is committed on OK

### Coordinate space

The same 30° shear was applied to the same rectangle untouched, translated, rotated, non-uniformly scaled, reflected, and inside a rotated group. An upright 200 × 120 pt box widens by exactly tan(30°) × 120 = 69.282 pt in the untouched, translated, and reflected cases. A box rotated 40° widens by a different amount, because the shear runs along the page's horizontal axis rather than the object's — which is precisely what *Object > Transform > Shear* also does to a rotated object.

### Behavior with the plugin missing

Asked because it is the question a collaborator will ask. Tested by authoring a document, uninstalling the plugin, restarting Illustrator, and opening it ([docs/evidence/missing-plugin.txt](docs/evidence/missing-plugin.txt)).

Illustrator shows its standard missing-plugin warning, naming the effect by its registered title and the plugin by its file name:

> The document "shear-with-plugin.ai" contains elements that are managed by plug-ins that are not currently available. You can delete or expand these elements but you cannot manipulate them in other ways. The missing plug-ins are listed below.
>
> Shear (LiveShear.aip)

Then:

- the document **opens**; nothing is refused, lost, or silently repaired
- the artwork still **draws sheared** — Illustrator renders the styled result cached in the file; the rectangle's drawn width stays 269.282 pt while its own anchors stay at x = 100/100/300/300
- the source geometry is **not expanded and not flattened**
- text is still live text and can still be retyped, but the effect no longer runs: after retyping, the text's geometric width grew from 237.981 to 440.827 pt while its drawn width stayed frozen at 268.104
- **saving from that state loses nothing** — reopening the re-saved file with the plugin back shows `shearAngle = 30` intact on both objects, and the artwork re-renders correctly for the edited text

The one practical hazard is that stale rendering: someone without the plugin who edits artwork and exports gets the old shape. That is Illustrator's standard behavior for any missing effect, not something specific to this plugin.

### Performance

A shear is one matrix and one `TransformArt` call, and it measures like it. On a 500-point path, ten parameter changes with a full redraw after each took 391 ms in total — about 39 ms per re-evaluation, and that figure includes Illustrator's own redraw, not just the effect. Dragging the slider produced no perceptible lag.

---

## I. Architecture recommendation

Ranked as the brief asked, with the verdict from this investigation:

1. **Extend the native Transform effect** — *ruled out*. There is no shear state in it, and no public way to add behavior to an effect another plugin registered. Sections D and E.
2. **Companion UI over a latent native parameter** — *ruled out*, for the same reason: reading and writing a built-in effect's dictionary works, but there is no latent parameter to drive.
3. **Standalone Shear live effect** — **recommended, and built.** It reproduces the native command's geometry exactly, composes correctly with Adobe's own Transform effect, and behaves like a first-class effect across save, reopen, copy, paste, undo, and reorder.
4. **Transform+** — *not justified*. Section G.
5. **Script** — *not a solution to this problem*. A script can apply the effect, batch it across a selection, or recover a shear matrix from destructively sheared art, and those are worth having as conveniences. None of them is non-destructive on its own.
6. **Deeper host intervention** — *not needed, and not attempted*. No Illustrator binary was modified. The only static inspection performed was reading printable strings out of Adobe's shipped plugins, which is non-invasive and leaves nothing changed.

There is a genuine fourth option that deserves recording even though it is not recommended: **driving `Adobe Free Distort` with computed corner points.** It would be a live shear rendered entirely by Adobe's own code, with no custom rendering to maintain, and it would work on any machine with Illustrator and no third-party plugin at all — because Free Distort is built in. Against it: Free Distort's input preference is `0x87`, a much narrower set of art types than a general effect wants; its quad is defined in absolute coordinates, so the "shear angle" would have to be recomputed whenever the artwork's bounds changed, which defeats the point of a live effect; and the Appearance panel would show *Free Distort*, not *Shear*, with corner coordinates rather than an angle. It is a good trick and a bad product.

---

## J. Remaining unknowns

Listed honestly, worst first.

1. **Reference point is fixed at the center.** Illustrator's own Shear dialog offers an origin offset and the *Transform* effect offers a nine-point pin. This effect offers neither.
2. **Not tested:** *Transform Patterns* and *Transform Objects* as user-facing options, Document Scale Conversion, parallel effect execution (the effect does not declare `kParallelExecutionFilter`), legacy save behavior and `SetLiveEffectAppVersion`, and any platform other than Windows. Blends and the `Interpolate` handler were on this list and are no longer: Illustrator does call the handler, and the axis takes the short way round modulo 180 at every boundary ([docs/evidence/blend.txt](docs/evidence/blend.txt)).

The release-candidate sprint that followed this investigation settled the rest; what it found is in [docs/RELEASE_READINESS.md](docs/RELEASE_READINESS.md), and what it measured is in [docs/RELEASE_TEST_MATRIX.md](docs/RELEASE_TEST_MATRIX.md) and [docs/SUPPORT_MATRIX.md](docs/SUPPORT_MATRIX.md).

### The anchor question, answered

This was recorded above as the open issue most likely to be noticed, and it had a definite answer.

Illustrator's own *Object > Transform > Shear* anchors on the center of the selection's **geometric** bounds — the Bézier outline, with strokes, effects, and the glyphs of area text excluded. That was measured rather than reasoned about. A shear along axis 0 displaces x in proportion to distance from the anchor's y and leaves y alone, so fitting a straight line through the artwork a native shear actually produced recovers the anchor exactly; axis 90 recovers the other coordinate. Run against fixtures whose geometric and visible centers are hundreds of points apart — an acute triangle whose mitered join spike reaches 600 pt past its geometry, and a group whose two members carry different stroke weights — every discriminating case comes back geometric, with residuals around 10⁻¹⁰ ([docs/evidence/anchor.tsv](docs/evidence/anchor.tsv)).

The effect had been anchoring on visible bounds, which on that spike put its reference point 295 pt away from the native one. It now asks for geometric bounds with flags that work — see the correction in section F, where the flags it used before turned out to be an invalid combination rather than a refusal — and walks the art itself in preference to asking, solving each cubic's derivative for the true extremes rather than settling for the hull of its control points.

Two art types needed more than that, and both were found by pointing the measurement at artwork nobody had measured before. A **clipping group** anchors on its clip path, not on the union of its children, even though the geometric bounds Illustrator reports for such a group are that union; the discriminating case is a clip path larger than what it clips, where the mask's box and the visible result are different rectangles, and the native command follows the mask. **Area text** anchors on its frame rather than its glyphs, which is what the flags were meant to have been asking for all along. With both fixed, every kind of artwork the suite can build anchors exactly where the native command does, along both axes: [docs/evidence/artwork-anchor.txt](docs/evidence/artwork-anchor.txt).

Three host behaviors had to be understood before any of this could be measured at all, and each one silently produced plausible wrong numbers first:

- The `adobe_shear` action resolves "about the center" from a **cached selection bounding box** that a scripted selection does not refresh. Redrawing, sleeping, reassigning the selection, and running the select-all menu command all leave it one selection behind, so every measurement comes out about the *previous* fixture's center. Playing the action once refreshes it, so a zero-angle pass — the identity, invisible in the geometry — is played first.
- The action cannot see a selection made in the **same script call** at all: it reports success and does nothing. `AIMatchingArtSuite::GetSelectedArt`, which the effect itself uses, sees that selection immediately. The two disagree, so the test harness selects in one call and acts in the next.
- Illustrator's scripting references are resolved by **position, not identity**. Duplicating an object inserts the copy at the top of the layer and every index below it shifts, so a reference held in a variable from an earlier call quietly starts pointing at a different object. Everything that has to survive a change in z-order is addressed by name.

There was a fourth, recorded as unresolved: in one long session the shear action reported success and left the artwork untouched for a run of about fifteen attempts, then started working again with no difference in the calls being made. **It has since been explained.** The action does not report failure when it cannot act — it raises a modal alert, *The object "Shear" is not currently available*, and `PlayActionEvent` then returns 0 for success. Under `app.userInteractionLevel = DONTDISPLAYALERTS`, which every probe sets so that a modal cannot block a scripted run forever, Illustrator answers that alert with Continue and the action carries on past the step it skipped. Measured directly: with nothing selected at all, the action returns 0 and the artwork does not move.

So the oracle's return value means nothing, and the harness never trusts it — it asks the artwork whether it moved, and reports a case as inconclusive rather than comparing against artwork nothing was done to. A version of the same mistake in a different place cost nine composition cases: the appearance probe held a scripting reference across a destructive action and read stale bounds back from it, with no error of any kind.

### Two things that were unknown and are now settled

**The crash is Illustrator's, not the plugin's.** During long automated runs Illustrator died repeatedly with an access violation inside *Illustrator.exe* (exception `0xc0000005`, faulting offset `0x18162a7`, in the Windows Application event log). Since a crash in a host driven by one's own plugin is the plugin's fault until proven otherwise, it was bisected.

The trigger is repeated create-document / close-document cycles under COM automation. It reproduces **with the plugin uninstalled**: three runs of forty cycles that never touch the effect and never load *LiveShear.aip* completed 9, 32, and 40 cycles before Illustrator stopped answering ([docs/evidence/history/crash-control-2026-09-13.txt](docs/evidence/history/crash-control-2026-09-13.txt)). With the plugin installed the same runs completed 2, 20, and 3 cycles. It has never been seen in ordinary interactive use, or in any run that reuses one document instead of churning them.

So the plugin does not cause it. Whether the plugin being loaded makes it *more likely* was left open at that point, and three runs per arm could never have answered it. For 0.1.1 it was measured properly: three arms of six trials of up to sixty cycles each, interleaved, every trial in a fresh Illustrator — the plugin absent, the plugin loaded but never used, and the effect applied on every cycle.

| arm | crashed | cycles reached | mean |
| --- | --- | --- | --- |
| plugin absent | 4 of 6 | 60, 3, 11, 60, 16, 13 | 27.2 |
| loaded, never used | 4 of 6 | 3, 60, 18, 60, 20, 19 | 30.0 |
| effect exercised | 2 of 6 | 60, 60, 60, 10, 60, 26 | 46.0 |

Absent against loaded-but-unused is four of six against four of six: Fisher's exact p = 1.000 on the counts, and an exact rank test on cycles reached p = 0.494. The arm that exercised the effect crashed *less* often rather than more, which is also not significant — p = 0.567 and p = 0.275. Six trials per arm can exclude only a large difference, and it does exactly that; a small one remains possible, and a null result at this size is not a demonstration that the plugin is irrelevant. Evidence: [docs/evidence/crash-arm-a.txt](docs/evidence/crash-arm-a.txt) and [docs/evidence/crash-ab.tsv](docs/evidence/crash-ab.tsv).

Every crash in all three arms faulted at the same offset, `0x18162a7` — the same offset an unrelated plugin's suite on this machine reproduced with that plugin uninstalled, which is a second project arriving at the same host defect independently.

**One observation, recorded with its n because it is not a finding.** Across the eighteen trials the peak working set separated completely: every trial that survived all sixty cycles peaked between 2483 and 2713 MB, every trial that died had already reached between 3426 and 3923 MB, and nothing fell in the 713 MB between them. What makes it worth writing down is the direction. The survivors did sixty document lifecycles for about 2.6 GB, while the crashers did between three and twenty-six for a gigabyte more — one of them reaching 3694 MB in three lifecycles. That is not the shape of a gradual leak, which would put the longest runs at the top rather than the bottom; the runs appear to divide into two kinds almost immediately instead of drifting toward a threshold.

Three things keep it an observation. It was noticed in the data and then tested on the trials that followed, which is better than fishing but is not a prospective test. Peak is sampled at the end of a trial, so for a crashing run it is as easily a symptom of whatever went wrong as a cause of it. And peak *working set* is not private bytes and not a sampled figure, so it is not comparable to memory numbers gathered any other way. It is here to be checked by an experiment designed for it, not to be relied on.

The probes now empty one document rather than close and reopen, which avoids the trigger entirely.

**Illustrator has no ready-made "what should this effect apply to" selection.** Worth writing down because it cost two rounds of wrong results and any future effect will hit it. `AIMatchingArtSuite::GetSelectedArt` returns a flattened hierarchy: select one group and it hands back the layer's own container group, the group, and every path inside it. Applying an effect to all of that puts it on the children instead of on the group the user selected. Of the ready-made alternatives, `kArtSelectedTopLevelGroups` matches nothing on its own and exactly one object when combined with `kArtSelected`, however many are selected; `kArtSelectedLeaves` behaves the same way; `kArtTargeted` is right when it is populated but goes empty after some scripted edits. The plugin therefore filters the selection itself: drop the layer container, which is the only object with no parent, then keep an object only if none of its ancestors is also selected. The `selection` probe prints what each specification returns, so the reasoning can be re-checked against a future version.
