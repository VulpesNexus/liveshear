"""Checks the scripts that decide whether the release passes.

The probes measure; these two scripts judge. A bug in either would turn a real
failure into a green matrix, which is the one kind of bug a test suite cannot
catch by running more tests. So they are fed rows whose right answer is known
by construction -- artwork sheared by exact arithmetic about an anchor chosen
in advance -- and their verdicts are checked.

Needs no Illustrator and no Adobe SDK. Run it with

    python tools/test-solvers.py
"""

import importlib.util
import math
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


solve_release = load("solve_release", "solve-release.py")
solve_anchor = load("solve_anchor", "solve-anchor.py")

FAILURES = []
CHECKS = [0]

SEP = chr(9)
NEWLINE = chr(10)


def check(ok, what, detail=""):
    CHECKS[0] += 1
    if ok:
        return
    FAILURES.append(f"{what}{'  --  ' + detail if detail else ''}")
    print(f"FAIL  {what}" + (f"  --  {detail}" if detail else ""))


def write(rows):
    path = Path(tempfile.mkdtemp()) / "rows.tsv"
    path.write_text("\n".join("\t".join(r) for r in rows) + "\n", encoding="utf-8")
    return path


def verdicts_of(path, solver):
    out = path.with_name("verdicts.tsv")
    solver.main(str(path), str(out))
    rows = out.read_text(encoding="utf-8").splitlines()
    header = rows[0].split("\t")
    return [dict(zip(header, r.split("\t"))) for r in rows[1:] if r.strip()]


# ---- the release solver -------------------------------------------------

RELEASE_HEADER = ["fixture", "shear", "axis", "geometric", "liveVisible",
                  "nativeVisible", "anchorsBefore", "anchorsAfter", "applied", "oracle"]


def release_row(name, live, native, before="1,2", after="1,2", oracle="moved",
                geometric="0,0,0,0", applied="ok"):
    return [name, "30", "0", geometric, live, native, before, after, applied, oracle]


def test_release():
    print("the release solver")
    rows = [RELEASE_HEADER,
            # Identical to the last digit: the effect rendered what the native
            # command rendered.
            release_row("exact", "1,2,3,4", "1,2,3,4"),
            # A ten-millionth of a point, which is below anything Illustrator
            # draws and inside the tolerance.
            release_row("within tolerance", "1,2,3,4", "1,2,3.0000001,4"),
            # A hundredth of a point, which is not.
            release_row("outside tolerance", "1,2,3,4", "1,2,3.01,4"),
            # The artwork is right but the effect rewrote its own source, which
            # is the failure a bounds comparison alone would miss.
            release_row("source moved", "1,2,3,4", "1,2,3,4", after="9,9"),
            # The oracle never moved, so there was nothing to compare against.
            release_row("oracle stuck", "1,2,3,4", "1,2,3,4", oracle="did not move"),
            # A brush, whose artwork Illustrator regenerates when the path is
            # transformed destructively. This one is allowed to differ.
            release_row("patternBrush", "1,2,3,4", "1,2,5,4"),
            # The same difference on a fixture that is not regenerated must
            # still fail, or the excuse would be a hole big enough to lose a
            # real defect through.
            release_row("plainRect", "1,2,3,4", "1,2,5,4"),
            # And a brush that rewrote its own source geometry is still a
            # failure: being allowed to look different is not being allowed to
            # damage the artwork.
            release_row("artBrush", "1,2,3,4", "1,2,5,4", after="9,9"),
            # The probe itself failed on this case.
            ["errored", "30", "0", "ERROR", "", "", "", "", "something broke", ""]]

    got = {row["case"].split(" at ")[0]: row["status"] for row in
           verdicts_of(write(rows), solve_release)}

    check(got.get("exact") == "PASS", "an exact match passes", str(got.get("exact")))
    check(got.get("within tolerance") == "PASS",
          "a difference below the tolerance passes", str(got.get("within tolerance")))
    check(got.get("outside tolerance") == "FAIL",
          "a difference above the tolerance fails", str(got.get("outside tolerance")))
    check(got.get("source moved") == "FAIL",
          "matching artwork still fails if the source geometry moved",
          str(got.get("source moved")))
    check(got.get("oracle stuck") == "INCONCLUSIVE",
          "an oracle that never moved is inconclusive, not a pass",
          str(got.get("oracle stuck")))
    check(got.get("errored") == "FAIL", "a case the probe could not run fails",
          str(got.get("errored")))
    check(got.get("patternBrush") == "EXPECTED",
          "artwork Illustrator regenerates is allowed to differ",
          str(got.get("patternBrush")))
    check(got.get("plainRect") == "FAIL",
          "the same difference on artwork it does not regenerate still fails",
          str(got.get("plainRect")))
    check(got.get("artBrush") == "FAIL",
          "a brush that moved its own source geometry still fails",
          str(got.get("artBrush")))
    check(len(got) == 9, "every row produced a verdict", str(len(got)))


# ---- the anchor solver --------------------------------------------------

ANCHOR_HEADER = ["fixture", "axis", "geometric", "visible", "before", "after"]


def shear_points(points, degrees, anchor_y):
    """Shears along axis 0 about anchor_y, exactly."""
    k = math.tan(math.radians(degrees))
    return [(x + k * (y - anchor_y), y) for x, y in points]


def fmt(points):
    return " ".join(f"{x:.9f},{y:.9f}" for x, y in points)


def anchor_row(name, anchor_y, geometric_y, visible_y):
    before = [(100.0, 480.0), (100.0, 600.0), (300.0, 600.0), (300.0, 480.0)]
    after = shear_points(before, 30.0, anchor_y)
    # Boxes written as left,top,right,bottom with the given vertical centers.
    geometric = f"100,{geometric_y + 60},300,{geometric_y - 60}"
    visible = f"100,{visible_y + 60},300,{visible_y - 60}"
    return [name, "0", geometric, visible, fmt(before), fmt(after)]


def test_anchor():
    print("the anchor solver")
    rows = [ANCHOR_HEADER,
            # Sheared about the geometric center, with the visible center
            # elsewhere: the answer the effect needs to be right about.
            anchor_row("geometric", 540.0, 540.0, 600.0),
            # Sheared about the visible center instead.
            anchor_row("visible", 600.0, 540.0, 600.0),
            # Both centers in the same place, so this fixture cannot tell them
            # apart whatever the answer is.
            anchor_row("coincident", 540.0, 540.0, 540.0),
            # Sheared about neither.
            anchor_row("neither", 123.0, 540.0, 600.0)]

    got = {row["case"].split(",")[0]: row["status"] for row in
           verdicts_of(write(rows), solve_anchor)}

    check(got.get("geometric") == "PASS",
          "a shear about the geometric center passes", str(got.get("geometric")))
    check(got.get("visible") == "FAIL",
          "a shear about the visible center fails", str(got.get("visible")))
    check(got.get("coincident") == "NOT DISCRIMINATING",
          "a fixture that cannot tell them apart says so rather than passing",
          str(got.get("coincident")))
    check(got.get("neither") == "FAIL",
          "a shear about neither center fails", str(got.get("neither")))

    # And the recovered anchor itself, not just the verdict.
    detail = [row["observed"] for row in verdicts_of(write(rows), solve_anchor)
              if row["case"].startswith("geometric")][0]
    check("anchor 540.000000" in detail,
          "the recovered anchor is the one the artwork was sheared about", detail)


def main(out_path=None):
    test_release()
    test_anchor()
    print(f"\n{CHECKS[0]} checks, {len(FAILURES)} failed")
    if out_path:
        status = "FAIL" if FAILURES else "PASS"
        observed = f"{CHECKS[0]} checks, {len(FAILURES)} failed"
        if FAILURES:
            observed += ": " + "; ".join(FAILURES)[:300]
        rows = [SEP.join(["probe", "group", "case", "expected", "observed", "status"]),
                SEP.join(["solvers", "test infrastructure",
                          "the scripts that decide pass and fail, fed rows whose right "
                          "answer is known by construction",
                          "every verdict is the one the construction requires",
                          observed, status])]
        Path(out_path).parent.mkdir(parents=True, exist_ok=True)
        Path(out_path).write_text(NEWLINE.join(rows) + NEWLINE, encoding="utf-8")
        print(f"written to {out_path}")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    destination = (sys.argv[1] if len(sys.argv) > 1
                   else str(HERE.parent / "docs" / "evidence" / "solvers.tsv"))
    sys.exit(main(destination))
