"""Shared geometry helpers for the Live Shear solvers.

Kept in an importable module because the scripts that use them are named with
hyphens, which Python cannot import.
"""

import math


def parse_points(field):
    points = []
    for pair in field.split():
        x, y = pair.split(",")
        points.append((float(x), float(y)))
    return points


def solve_affine(before, after):
    """Least-squares solve for (a, b, c, d, tx, ty) with
    x' = a*x + c*y + tx and y' = b*x + d*y + ty."""
    # Two independent 3-parameter systems: (a, c, tx) and (b, d, ty).
    def solve_row(target_index):
        # Normal equations for [x y 1] . p = target
        ata = [[0.0] * 3 for _ in range(3)]
        atb = [0.0] * 3
        for (x, y), out in zip(before, after):
            row = (x, y, 1.0)
            t = out[target_index]
            for i in range(3):
                atb[i] += row[i] * t
                for j in range(3):
                    ata[i][j] += row[i] * row[j]
        return gaussian(ata, atb)

    ax, cx, tx = solve_row(0)
    by, dy_, ty = solve_row(1)
    return ax, by, cx, dy_, tx, ty


def gaussian(matrix, rhs):
    n = len(rhs)
    m = [row[:] + [rhs[i]] for i, row in enumerate(matrix)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(m[r][col]))
        if abs(m[pivot][col]) < 1e-12:
            raise ValueError("singular system")
        m[col], m[pivot] = m[pivot], m[col]
        for r in range(n):
            if r == col:
                continue
            factor = m[r][col] / m[col][col]
            for k in range(col, n + 1):
                m[r][k] -= factor * m[col][k]
    return [m[i][n] / m[i][i] for i in range(n)]


def plugin_matrix(shear_deg, axis_deg, anchor):
    k = math.tan(math.radians(shear_deg))
    c = math.cos(math.radians(axis_deg))
    s = math.sin(math.radians(axis_deg))
    a = 1.0 - k * c * s
    b = -k * s * s
    cc = k * c * c
    d = 1.0 + k * c * s
    ax, ay = anchor
    tx = ax - (a * ax + cc * ay)
    ty = ay - (b * ax + d * ay)
    return a, b, cc, d, tx, ty


def bounds_center(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return ((min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0)
