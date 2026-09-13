# Where the shear anchors, and how it stacks

How the effect behaves, as opposed to what it does not do — that is [KNOWN_LIMITATIONS.md](../KNOWN_LIMITATIONS.md) — and as opposed to why it exists at all, which is [LIVE_SHEAR_INVESTIGATION.md](../LIVE_SHEAR_INVESTIGATION.md). The [README](../README.md) states the short form of everything here.

## The reference point

The artwork is sheared about the center of its **geometric** bounds: the Bézier outline, with strokes, effects, and the glyphs of area text left out. That is the same reference point *Object > Transform > Shear* uses.

It is measured rather than assumed. For each kind of artwork the suite can build, the effect and the native command are given the same angle, and the difference between the two results is solved back into the distance between their reference points. That distance is zero for paths, compound paths, plain, nested, clipped, and transformed groups, point and area text, symbol instances, and embedded rasters. The per-fixture results are in [SUPPORT_MATRIX.md](SUPPORT_MATRIX.md), and the runs behind them in [RELEASE_TEST_MATRIX.md](RELEASE_TEST_MATRIX.md#reference-point-by-kind-of-artwork).

Two kinds of artwork are worth saying out loud, because Illustrator is not consistent about them:

- A **clipping group** anchors on its clip path, not on everything inside it — even though the geometric bounds Illustrator *reports* for such a group are the union of its children.
- **Area text** anchors on its frame, not on its glyphs, so a line whose ascenders overshoot the frame does not move the center.

## Why it composes

The effect anchors on what the appearance pipeline hands it, not on the original object, and that is what makes it stack. An *Offset Path* or a *Transform* below the Shear grows or moves the artwork, and the shear's reference point moves with it — exactly as stacking two transforms should. So the result depends on where in the *Appearance* panel the Shear sits, which is the point of having a stack. Put the Shear at the bottom to anchor on the bare geometry.

That composition is checked in both directions rather than asserted:

- A *Transform* above a Shear renders what the same *Transform* renders above Illustrator's own shear.
- A Shear above a *Transform* renders what Illustrator's own shear renders on that *Transform* expanded into real geometry.
- The two orders differ from each other, so the comparison is discriminating rather than trivially satisfied.

Two Shear effects on one object render as two successive native shears, and reordering, swapping, or deleting them behaves the way two transforms should. Forty reorders leave the result unchanged. The measurements are in [RELEASE_TEST_MATRIX.md](RELEASE_TEST_MATRIX.md#appearance-composition).

## Blends

Illustrator calls the effect's interpolation handler while building a blend, and the axis takes the short way round modulo 180°: blending an axis of 179° with one of 1° passes through 180°, not 90°.
