"""Recovers the anchor a shear was performed about, from before/after anchors.

A shear along axis 0 maps (x, y) to (x + k*(y - ay), y); along axis 90 it maps
(x, y) to (x, y - k*(x - ax)). Fitting the displacement against the free
coordinate gives k and the anchor coordinate the shear was taken about, which
is then compared against the fixture's geometric and visible bounds.

This is what answers the question the release report has to answer: which box
does Illustrator's own shear command take its reference point from. Fixtures
whose geometric and visible centers coincide cannot answer it and are reported
as not discriminating rather than as agreement.
"""

import sys
from pathlib import Path

TOLERANCE = 1e-4
HEADER = "probe\tgroup\tcase\texpected\tobserved\tstatus"


def points(field):
    out = []
    for token in field.split():
        x, y = token.split(",")
        out.append((float(x), float(y)))
    return out


def fit(free, disp):
    """Least-squares slope and intercept of disp = slope*free + intercept."""
    n = len(free)
    mf = sum(free) / n
    md = sum(disp) / n
    num = sum((f - mf) * (d - md) for f, d in zip(free, disp))
    den = sum((f - mf) ** 2 for f in free)
    if abs(den) < 1e-12:
        return None, None, None
    slope = num / den
    intercept = md - slope * mf
    resid = max(abs(d - (slope * f + intercept)) for f, d in zip(free, disp))
    return slope, intercept, resid


def center(box):
    left, top, right, bottom = [float(v) for v in box.split(",")]
    return (left + right) / 2.0, (top + bottom) / 2.0


def main(path, out=None):
    rows = Path(path).read_text(encoding="utf-8").splitlines()
    header = rows[0].split("\t")
    verdicts = [HEADER]
    print(f"{'fixture':<14}{'axis':>5}{'k':>12}{'anchor':>14}"
          f"{'geometric':>14}{'visible':>14}  verdict")

    for row in rows[1:]:
        if not row.strip():
            continue
        cells = dict(zip(header, row.split("\t")))
        name = cells["fixture"]
        axis = int(cells["axis"])
        case = f"{name}, axis {axis}"

        before = points(cells["before"])
        after = points(cells["after"])
        if len(before) != len(after):
            print(f"{name:<14} point count changed; cannot fit")
            verdicts.append(f"anchor\tnative semantics\t{case}\t"
                            f"anchor is the geometric bounds center\t"
                            f"point count changed\tFAIL")
            continue

        gx, gy = center(cells["geometric"])
        vx, vy = center(cells["visible"])
        if axis == 0:
            free = [p[1] for p in before]
            disp = [a[0] - b[0] for b, a in zip(before, after)]
            g, v = gy, vy
        else:
            free = [p[0] for p in before]
            disp = [a[1] - b[1] for b, a in zip(before, after)]
            g, v = gx, vx

        slope, intercept, resid = fit(free, disp)
        if slope is None or abs(slope) < 1e-9:
            print(f"{name:<14}{axis:>5}  degenerate fit")
            verdicts.append(f"anchor\tnative semantics\t{case}\t"
                            f"anchor is the geometric bounds center\t"
                            f"degenerate fit\tFAIL")
            continue

        anchor = -intercept / slope
        matches_geometric = abs(anchor - g) < TOLERANCE
        matches_visible = abs(anchor - v) < TOLERANCE
        discriminating = abs(g - v) >= 1e-9

        labels = []
        if matches_geometric:
            labels.append("geometric")
        if matches_visible:
            labels.append("visible")
        verdict = "+".join(labels) if labels else "NEITHER"
        if not discriminating:
            verdict += " (not discriminating)"

        print(f"{name:<14}{axis:>5}{slope:>12.6f}{anchor:>14.6f}"
              f"{g:>14.6f}{v:>14.6f}  {verdict}  resid={resid:.2e}")

        observed = (f"anchor {anchor:.6f}; geometric center {g:.6f}, "
                    f"visible center {v:.6f}; residual {resid:.2e}")
        if not discriminating:
            status = "NOT DISCRIMINATING"
        elif matches_geometric and not matches_visible:
            status = "PASS"
        else:
            status = "FAIL"
        verdicts.append(f"anchor\tnative semantics\t{case}\t"
                        f"anchor is the geometric bounds center\t{observed}\t{status}")

    if out:
        Path(out).write_text("\n".join(verdicts) + "\n", encoding="utf-8")
        print(f"\nverdicts written to {out}")
    return 0


if __name__ == "__main__":
    source = sys.argv[1] if len(sys.argv) > 1 else "docs/evidence/anchor.tsv"
    destination = (sys.argv[2] if len(sys.argv) > 2
                   else str(Path(source).with_name("anchor-verdicts.tsv")))
    sys.exit(main(source, destination))
