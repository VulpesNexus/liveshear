"""Solves the affine map that Illustrator's native Shear applied in each case.

Reads the TSV written by tools/probe-native-shear.ps1, recovers the matrix by
least squares from the before/after anchor points, and compares it against the
matrix the Live Shear plug-in would build for the same parameters.

    python tools/solve-shear.py [docs/evidence/native-shear.tsv]
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from solve_shear_support import (bounds_center, parse_points, plugin_matrix,
                                 solve_affine)


def fmt(values):
    return "[" + " ".join("%+.6f" % v for v in values) + "]"


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("docs/evidence/native-shear.tsv")
    lines = path.read_text(encoding="utf-8").splitlines()
    header = lines[0].split("\t")
    assert header[0] == "shear", header

    worst = 0.0
    print("%-8s %-6s %-5s %-5s %-4s  %s" % ("shear", "axis", "dx", "dy", "res", "verdict"))
    for line in lines[1:]:
        if not line.strip():
            continue
        shear, axis, dx, dy, result, before_s, after_s = line.split("\t")
        before = parse_points(before_s)
        after = parse_points(after_s)
        if not before or len(before) != len(after):
            print("%-8s %-6s %-5s %-5s %-4s  no usable geometry" % (shear, axis, dx, dy, result))
            continue

        if before == after:
            print("%-8s %-6s %-5s %-5s %-4s  UNCHANGED (command refused or no-op)"
                  % (shear, axis, dx, dy, result))
            continue

        measured = solve_affine(before, after)
        cx, cy = bounds_center(before)
        # detX/detY offset the origin from the centre of the selection, but in
        # the y-down convention the dialog uses, not the y-up one Illustrator's
        # artwork coordinates use. Hence the negated dy.
        anchor = (cx + float(dx), cy - float(dy))
        predicted = plugin_matrix(float(shear), float(axis), anchor)
        delta = max(abs(m - p) for m, p in zip(measured, predicted))
        worst = max(worst, delta)

        # Residual of the least-squares fit: how affine the operation really is.
        residual = 0.0
        a, b, c, d, tx, ty = measured
        for (x, y), (ox, oy) in zip(before, after):
            residual = max(residual,
                           abs(a * x + c * y + tx - ox),
                           abs(b * x + d * y + ty - oy))

        verdict = "MATCH" if delta < 1e-3 else "DIFFERS by %.6f" % delta
        print("%-8s %-6s %-5s %-5s %-4s  %s (affine residual %.2e)"
              % (shear, axis, dx, dy, result, verdict, residual))
        if delta >= 1e-3:
            print("        measured  %s" % fmt(measured))
            print("        predicted %s" % fmt(predicted))

    print("\nworst deviation across all matched cases: %.3e" % worst)


if __name__ == "__main__":
    main()
