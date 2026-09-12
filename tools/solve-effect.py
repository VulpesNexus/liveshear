"""Recovers the affine map each live effect rendered, from expanded geometry.

Reads docs/evidence/effect-matrix.tsv (written by tools/probe-effect-matrix.ps1)
and prints the measured matrix for every case. For the plugin's own Shear
effect the measured matrix is checked against the formula in ShearMath.h; for
the built-in Transform effect the measured matrix is checked against every
plausible composition order of its documented components, so the order
Illustrator uses can be read off rather than guessed.

    python tools/solve-effect.py [docs/evidence/effect-matrix.tsv]
"""

import itertools
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from solve_shear_support import (bounds_center, parse_points, plugin_matrix,
                                 solve_affine)


def mat_mul(m, n):
    """Composes two PostScript matrices: the result applies n, then m."""
    a1, b1, c1, d1, tx1, ty1 = m
    a2, b2, c2, d2, tx2, ty2 = n
    return (
        a1 * a2 + c1 * b2,
        b1 * a2 + d1 * b2,
        a1 * c2 + c1 * d2,
        b1 * c2 + d1 * d2,
        a1 * tx2 + c1 * ty2 + tx1,
        b1 * tx2 + d1 * ty2 + ty1,
    )


IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def translate(tx, ty):
    return (1.0, 0.0, 0.0, 1.0, tx, ty)


def scale(sx, sy):
    return (sx, 0.0, 0.0, sy, 0.0, 0.0)


def rotate(degrees):
    r = math.radians(degrees)
    return (math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0.0, 0.0)


def about(m, anchor):
    ax, ay = anchor
    return mat_mul(translate(ax, ay), mat_mul(m, translate(-ax, -ay)))


def parse_params(spec):
    values = {}
    for pair in spec.split(";"):
        if not pair or "=" not in pair:
            continue
        key, tagged = pair.split("=", 1)
        raw = tagged.split(":", 1)[1]
        if raw in ("true", "false"):
            values[key] = 1.0 if raw == "true" else 0.0
        else:
            values[key] = float(raw)
    return values


def fmt(m):
    return "[" + " ".join("%+.5f" % v for v in m) + "]"


def close(m, n, tol=1e-3):
    return all(abs(x - y) <= tol for x, y in zip(m, n))


def residual_of(m, before, after):
    a, b, c, d, tx, ty = m
    worst = 0.0
    for (x, y), (ox, oy) in zip(before, after):
        worst = max(worst, abs(a * x + c * y + tx - ox), abs(b * x + d * y + ty - oy))
    return worst


def best_correspondence(before, after):
    """Expanding an appearance can renumber a closed path's anchor points, so
    the true pairing is whichever rotation (and direction) of the result list
    fits an affine map with no residual. With an asymmetric source shape only
    one pairing can fit."""
    n = len(after)
    best = None
    for reverse in (False, True):
        seq = list(reversed(after)) if reverse else list(after)
        for shift in range(n):
            rotated = seq[shift:] + seq[:shift]
            try:
                m = solve_affine(before, rotated)
            except ValueError:
                continue
            r = residual_of(m, before, rotated)
            label = "shift %d%s" % (shift, ", reversed" if reverse else "")
            if best is None or r < best[1]:
                best = (m, r, label)
    return best


def pin_points(points):
    """The nine reference points of the source bounding box, named the way
    Illustrator's preference constants number them."""
    xs = [q[0] for q in points]
    ys = [q[1] for q in points]
    left, right = min(xs), max(xs)
    bottom, top = min(ys), max(ys)
    mid_x, mid_y = (left + right) / 2.0, (bottom + top) / 2.0
    return {
        "left-top": (left, top), "mid-top": (mid_x, top), "right-top": (right, top),
        "left-mid": (left, mid_y), "center": (mid_x, mid_y), "right-mid": (right, mid_y),
        "left-bottom": (left, bottom), "mid-bottom": (mid_x, bottom), "right-bottom": (right, bottom),
    }


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("docs/evidence/effect-matrix.tsv")
    lines = path.read_text(encoding="utf-8").splitlines()

    for line in lines[1:]:
        if not line.strip():
            continue
        effect, params, _dx, _dy, _applied, before_s, after_s = line.split("\t")
        before = parse_points(before_s)
        after = parse_points(after_s)
        print("\n%s  %s" % (effect, params or "(no parameters)"))
        if len(before) != len(after) or not before:
            print("    point counts differ (%d -> %d); cannot solve" % (len(before), len(after)))
            continue

        measured, residual, pairing = best_correspondence(before, after)
        print("    measured  %s   (residual %.2e, %s)" % (fmt(measured), residual, pairing))
        if residual > 1e-4:
            print("    NOT AFFINE under any pairing of the anchor points.")
            continue

        if close(measured, IDENTITY, 1e-6):
            print("    identity -- these parameters changed nothing")
            continue

        anchor = bounds_center(before)
        p = parse_params(params)

        if effect.endswith("Shear"):
            predicted = plugin_matrix(p.get("shearAngle", 0.0), p.get("axisAngle", 0.0), anchor)
            print("    formula   %s   -> %s" % (fmt(predicted),
                                                "MATCH" if close(measured, predicted) else "DIFFERS"))
            continue

        # Built-in Transform: try every order of the components it exposes,
        # about each of the nine reference points, so both the composition
        # order and the pin the renderer honours can be read off.
        sx = p.get("scaleH_Factor", p.get("scaleH_Percent", 100.0) / 100.0)
        sy = p.get("scaleV_Factor", p.get("scaleV_Percent", 100.0) / 100.0)
        angle = math.degrees(p.get("rotate_Radians", 0.0))
        reflecting = p.get("reflect", 0.0) != 0.0
        rx = -1.0 if (reflecting and p.get("reflectX", 0.0) != 0.0) else 1.0
        ry = -1.0 if (reflecting and p.get("reflectY", 0.0) != 0.0) else 1.0

        components = {
            "scale": scale(sx * rx, sy * ry),
            "rotate": rotate(angle),
        }
        move = translate(p.get("moveH_Pts", 0.0), p.get("moveV_Pts", 0.0))

        matches = []
        for pin_name, pin in pin_points(before).items():
            for order in itertools.permutations(components):
                inner = IDENTITY
                for name in order:
                    inner = mat_mul(components[name], inner)
                for placement in ("move-outside", "move-inside"):
                    if placement == "move-outside":
                        candidate = mat_mul(move, about(inner, pin))
                    else:
                        candidate = about(mat_mul(move, inner), pin)
                    if close(measured, candidate):
                        matches.append("%s about %s (%s)" % (" then ".join(order), pin_name, placement))
        if matches:
            print("    consistent with: %s" % "; ".join(sorted(set(matches))))
        else:
            print("    no tried order reproduces this matrix")


if __name__ == "__main__":
    main()
