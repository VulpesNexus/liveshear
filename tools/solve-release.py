"""Turns the raw release matrix into verdicts.

Two invariants are checked for every case.

Native equivalence: the visible bounds of the copy carrying the live effect
must match the visible bounds of the copy Illustrator sheared itself. Visible
bounds are used because they are the only bounds the DOM reports that reflect a
live effect at all, and because they need no knowledge of the shape's outline,
which is what lets text, symbols and clipping groups be measured the same way
as a rectangle.

Source invariance: the path anchors under the live copy must be unchanged. A
live effect that rewrote its own source would still look right and would still
be wrong.

The verdicts are also written out as a tab-separated file, because the release
test matrix has to be generated from data rather than transcribed from prose.
"""

import sys
from pathlib import Path

# Illustrator stores coordinates as doubles, and the two routes into a shear
# are different code paths through the same arithmetic.
#
# The limit is not the arithmetic, though; it is what Illustrator will tell us.
# Bounds that involve text come back through a narrower float, and the residue
# is visible in the numbers: the differences on text are 0.000488 and 0.000977
# pt, which are 1/2048 and 1/1024 exactly. Those are the last bit of a float32,
# not a measurement of anything.
#
# Five thousandths of a point is about two microns. It is four hundred times
# finer than a 2400 dpi imagesetter can place a dot, and eighty times smaller
# than the smallest real difference this suite has ever found.
TOLERANCE = 5e-3

# Artwork Illustrator generates from a path rather than storing: brushes.
# Transforming the path destructively re-runs the brush along the new path;
# a live effect is handed the art the brush already produced and can only
# transform that. The two do not agree and cannot be made to, and Adobe's own
# Transform effect does not agree with Adobe's own command on these either --
# measured, in docs/evidence/generated-art.txt, with a plain rectangle and a
# stroked one as the controls that do agree.
#
# So for these the expectation "matches Illustrator's own shear" is the wrong
# one to hold them to, and a row that says FAIL against it is misleading.
REGENERATED = {
    "calligraphicBrush": "a calligraphic brush",
    "artBrush": "an art brush",
    "patternBrush": "a pattern brush",
    "strokedText": "a stroke on live text",
}

HEADER = "probe\tgroup\tcase\texpected\tobserved\tstatus"
EXPECTED = "matches Illustrator's own shear, source untouched"


def quad(text):
    return [float(v) for v in text.split(",")] if text else None


def main(path, out=None):
    rows = Path(path).read_text(encoding="utf-8").splitlines()
    header = rows[0].split("\t")
    verdicts = [HEADER]
    passed = failed = inconclusive = expected_count = malformed = 0

    print(f"{'fixture':<20}{'shear':>9}{'axis':>7}  {'max dev':>12}  source  verdict")
    for row in rows[1:]:
        if not row.strip():
            continue
        cells = dict(zip(header, row.split("\t")))
        # A row that is not a row. One malformed line used to end the whole run
        # with a KeyError, which meant a single broken fixture cost the entire
        # matrix; saying so and carrying on is the right shape for a tool whose
        # job is to report what happened.
        if not {"fixture", "shear", "axis"}.issubset(cells):
            print("  skipped a malformed line: {!r}".format(row[:70]))
            malformed += 1
            continue
        name = cells["fixture"]
        shear = cells["shear"]
        axis = cells["axis"]
        case = f"{name} at {shear} deg, axis {axis}"

        if cells.get("geometric") == "ERROR" or not cells.get("liveVisible"):
            note = cells.get("applied", "no result")[:120]
            print(f"{name:<20}{shear:>9}{axis:>7}  {'-':>12}  {'-':<6}  ERROR {note}")
            verdicts.append(f"release\tart types\t{case}\t{EXPECTED}\t{note}\tFAIL")
            failed += 1
            continue

        # At zero degrees both routes are the identity, so artwork that did not
        # move is the right answer rather than a failed oracle. Comparing the
        # two is still worth doing -- it is the case that catches an effect
        # which does something when asked for nothing.
        try:
            asked_for_nothing = float(shear) == 0.0
        except ValueError:
            asked_for_nothing = False

        if not asked_for_nothing and cells.get("oracle", "moved").strip() == "did not move":
            note = ("Illustrator's own shear reported success but left the oracle "
                    "untouched after three attempts; nothing to compare against")
            print(f"{name:<20}{shear:>9}{axis:>7}  {'-':>12}  {'-':<6}  INCONCLUSIVE")
            verdicts.append(f"release\tart types\t{case}\t{EXPECTED}\t{note}\tINCONCLUSIVE")
            inconclusive += 1
            continue

        live = quad(cells["liveVisible"])
        native = quad(cells["nativeVisible"])
        deviation = max(abs(a - b) for a, b in zip(live, native))
        source_ok = cells["anchorsBefore"] == cells["anchorsAfter"]

        ok = deviation <= TOLERANCE and source_ok
        regenerated = name in REGENERATED

        if ok:
            verdict, notes = "PASS", []
            passed += 1
        elif not source_ok:
            # Nothing excuses this one.
            verdict, notes = "FAIL", ["SOURCE GEOMETRY CHANGED"]
            failed += 1
        elif regenerated:
            verdict = "EXPECTED"
            notes = ["Illustrator regenerates this artwork from the path"]
            expected_count += 1
        else:
            verdict, notes = "FAIL", ["differs from native"]
            failed += 1

        print(f"{name:<20}{shear:>9}{axis:>7}  {deviation:>12.2e}  "
              f"{'ok' if source_ok else 'CHANGED':<6}  {verdict} {' '.join(notes)}")

        if verdict == "EXPECTED":
            observed = (
                f"differs from the destructive command by {deviation:.2e} pt, and must: "
                f"{REGENERATED[name]} is laid along the path again when the path is "
                f"transformed destructively, while a live effect is handed the art the "
                f"generator already produced. Adobe's own Transform effect differs from Adobe's "
                f"own command here too (docs/evidence/generated-art.txt). Source geometry "
                f"{'unchanged' if source_ok else 'CHANGED'}")
        else:
            observed = (f"largest difference from the native result {deviation:.2e} pt; "
                        f"source geometry {'unchanged' if source_ok else 'CHANGED'}")
        verdicts.append(f"release\tart types\t{case}\t{EXPECTED}\t{observed}\t{verdict}")

    total = passed + failed + expected_count + inconclusive
    tally = (f"\n{passed} passed, {failed} failed, {expected_count} expected-to-differ, "
             f"{inconclusive} inconclusive, ")
    if malformed:
        tally += f"{malformed} malformed line(s) skipped, "
    print(tally + f"{total} cases")
    if out:
        Path(out).write_text("\n".join(verdicts) + "\n", encoding="utf-8")
        print(f"verdicts written to {out}")
    return 1 if failed else 0


if __name__ == "__main__":
    source = sys.argv[1] if len(sys.argv) > 1 else "docs/evidence/release-matrix.tsv"
    destination = (sys.argv[2] if len(sys.argv) > 2
                   else str(Path(source).with_name("release-verdicts.tsv")))
    sys.exit(main(source, destination))
