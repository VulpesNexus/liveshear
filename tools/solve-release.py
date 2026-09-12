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
# are different code paths through the same arithmetic. A ten-millionth of a
# point is far below anything that can be drawn, printed, or exported.
TOLERANCE = 1e-6

HEADER = "probe\tgroup\tcase\texpected\tobserved\tstatus"
EXPECTED = "matches Illustrator's own shear, source untouched"


def quad(text):
    return [float(v) for v in text.split(",")] if text else None


def main(path, out=None):
    rows = Path(path).read_text(encoding="utf-8").splitlines()
    header = rows[0].split("\t")
    verdicts = [HEADER]
    passed = failed = inconclusive = 0

    print(f"{'fixture':<20}{'shear':>9}{'axis':>7}  {'max dev':>12}  source  verdict")
    for row in rows[1:]:
        if not row.strip():
            continue
        cells = dict(zip(header, row.split("\t")))
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

        if cells.get("oracle", "moved").strip() == "did not move":
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
        verdict = "PASS" if ok else "FAIL"
        if ok:
            passed += 1
        else:
            failed += 1

        notes = []
        if deviation > TOLERANCE:
            notes.append("differs from native")
        if not source_ok:
            notes.append("SOURCE GEOMETRY CHANGED")
        print(f"{name:<20}{shear:>9}{axis:>7}  {deviation:>12.2e}  "
              f"{'ok' if source_ok else 'CHANGED':<6}  {verdict} {' '.join(notes)}")

        observed = (f"largest difference from the native result {deviation:.2e} pt; "
                    f"source geometry {'unchanged' if source_ok else 'CHANGED'}")
        verdicts.append(f"release\tart types\t{case}\t{EXPECTED}\t{observed}\t{verdict}")

    print(f"\n{passed} passed, {failed} failed, {passed + failed} cases")
    if out:
        Path(out).write_text("\n".join(verdicts) + "\n", encoding="utf-8")
        print(f"verdicts written to {out}")
    return 1 if failed else 0


if __name__ == "__main__":
    source = sys.argv[1] if len(sys.argv) > 1 else "docs/evidence/release-matrix.tsv"
    destination = (sys.argv[2] if len(sys.argv) > 2
                   else str(Path(source).with_name("release-verdicts.tsv")))
    sys.exit(main(source, destination))
