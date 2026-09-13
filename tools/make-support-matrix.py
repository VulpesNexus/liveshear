"""Generates docs/SUPPORT_MATRIX.md from the release matrix results.

Which artwork is supported is a claim about evidence, so the statuses come
from what the probes measured rather than from anyone's recollection. Each
fixture the suite exercises maps to a row here; anything in the artwork model
that the suite does not exercise is listed too, as untested, because a support
matrix that quietly omits what was not tried is worse than none.

    VERIFIED   every case for this artwork matched Illustrator's own shear
    PARTIAL    some cases matched and some did not; the difference is named
    UNTESTED   no case covers it, or the host could not be made to run one
"""

import sys
from pathlib import Path
from collections import defaultdict

# fixture -> (category, what it is)
FIXTURES = {
    "plainRect": ("Simple paths", "a filled rectangle"),
    "strokedRect": ("Ordinary strokes", "a 40 pt centered stroke"),
    "spike": ("Mitered joins", "an acute triangle whose mitered join reaches far past the geometry"),
    "roundJoin": ("Round joins", "the same triangle with a round join"),
    "bevelJoin": ("Bevel joins", "the same triangle with a bevel join"),
    "dashedStroke": ("Dashed strokes", "a 12 pt stroke dashed 18 on, 9 off"),
    "bezier": ("Bezier paths", "an open path of smooth curves"),
    "openPath": ("Open paths", "an open path with round caps"),
    "compound": ("Compound paths", "a rectangle with a rectangular hole"),
    "selfIntersecting": ("Self-intersecting paths", "a five-pointed star drawn as one closed path"),
    "mixedGroup": ("Groups", "two rectangles with different stroke weights"),
    "nestedGroup": ("Nested groups", "a group inside a group"),
    "clipGroup": ("Clipping groups", "an ellipse masking a rectangle"),
    "transformedGroup": ("Transformed groups", "a nested group rotated and moved"),
    "pointText": ("Live point text", "72 pt point text"),
    "areaText": ("Live area text", "text flowed into a rectangular frame"),
    "multilineText": ("Multi-line text", "two lines of point text"),
    "strokedText": ("Stroked text", "point text with a 6 pt character stroke"),
    "asymmetricText": ("Text with off-center ink", "glyphs with descenders on one side and none on the other"),
    "retypedText": ("Text edited after the frame was made", "point text whose contents were replaced"),
    "resizedText": ("Text resized after the frame was made", "point text whose size was changed"),
    "embeddedRaster": ("Embedded rasters", "a bitmap placed and embedded in the document"),
    "symbolInstance": ("Symbol instances", "an instance of a symbol made from a stroked rectangle"),
    "gradientFill": ("Linear gradients", "a linear gradient fill"),
    "radialFill": ("Radial gradients", "a radial gradient fill"),
    "patternFill": ("Pattern-filled objects", "an object carrying a pattern swatch fill"),
    "calligraphicBrush": ("Calligraphic brushes", "a calligraphic brush on an open path"),
    "artBrush": ("Art brushes", "an art brush on an open path"),
    "patternBrush": ("Pattern brushes", "a pattern brush on an open path"),
    "rotatedRect": ("Rotated source art", "a rectangle rotated 37 degrees"),
    "scaledRect": ("Scaled source art", "a rectangle scaled non-uniformly"),
    "reflectedRect": ("Reflected source art", "a triangle reflected horizontally"),
    "preShearedRect": ("Already-sheared source art", "a rectangle sheared 20 degrees destructively"),
    "tinyPath": ("Very small artwork", "a rectangle a hundredth of a point across"),
    "hugePath": ("Very large artwork", "a rectangle 8,000 by 5,000 points"),
    "farFromOrigin": ("Artwork far from the origin", "a rectangle at 4,000 by 3,000 points"),
    "negativeCoords": ("Negative coordinates", "a rectangle at negative x and y"),
    "zeroHeight": ("Degenerate: no height", "a horizontal line"),
    "zeroWidth": ("Degenerate: no width", "a vertical line"),
    "singleAnchor": ("Degenerate: one anchor", "a path with a single point and no extent"),
    "manyChildren": ("Large groups", "a group of two hundred rectangles"),
}

# Things the artwork model contains that the suite does not exercise. Listed
# so the matrix cannot be read as a claim about them.
UNTESTED = [
    ("Variable-width strokes", "a stroke whose width profile varies along the path", "No case builds one: the width profile is not reachable from Illustrator's scripting interface, so a fixture would have to be drawn by hand."),
    ("Scatter brushes", "a brush that scatters copies of art along a path", "No scatter brush ships in the default document profile used by the fixtures."),
    ("Meshes", "a gradient mesh object", "Not exercised."),
    ("Linked images", "an image linked rather than embedded", "An embedded raster is exercised and anchors exactly where the native command does; a linked one is not built by any fixture."),
    ("Graphs", "a graph object", "Not exercised."),
    ("3D and raster effects below the Shear in the stack", "an effect that rasterizes before the shear runs", "Composition was measured against Adobe's Transform and against Offset Path, not against a raster effect."),
    ("Non-Windows hosts", "macOS", "The plugin is Windows-only; the dialog is plain Win32."),
]


def read(path):
    if not path.exists():
        return []
    rows = path.read_text(encoding="utf-8").splitlines()
    header = rows[0].split("\t")
    return [dict(zip(header, r.split("\t"))) for r in rows[1:] if r.strip()]



def prettify(text):
    """ASCII stand-ins to the real glyphs.

    The probes write their result strings in PowerShell and ExtendScript
    sources, which have to stay pure ASCII -- both are read in the system
    codepage, and a stray byte there is a mangled file. The Markdown generated
    from those strings is prose, though, and prose here uses the real
    characters. So the conversion happens on the way out.
    """
    return (text.replace(' -- ', ' — ')
                .replace('->', '→')
                .replace('...', '…'))


def main(evidence_dir, out_path):
    evidence = Path(evidence_dir)
    verdicts = read(evidence / "release-verdicts.tsv")

    by_fixture = defaultdict(list)
    for row in verdicts:
        case = row.get("case", "")
        name = case.split(" at ")[0].strip()
        by_fixture[name].append(row)

    lines = [
        "# Support matrix",
        "",
        "Generated from the release matrix by *tools/make-support-matrix.py*. A row says VERIFIED only when every case the suite ran for that kind of artwork rendered the same visible bounds as Illustrator's own *Object > Transform > Shear*, to within a ten-millionth of a point, and left the source geometry untouched.",
        "",
        "| Artwork | Fixture | Cases | Status | Notes |",
        "| --- | --- | --- | --- | --- |",
    ]

    counts = defaultdict(int)
    for fixture, (category, description) in FIXTURES.items():
        rows = by_fixture.get(fixture, [])
        if not rows:
            status, note = "UNTESTED", "no case in this run"
        else:
            bad = [r for r in rows if r.get("status") == "FAIL"]
            unclear = [r for r in rows if r.get("status") == "INCONCLUSIVE"]
            if bad:
                status = "PARTIAL"
                note = "; ".join(sorted({r.get("observed", "") for r in bad}))[:220]
            elif unclear:
                status = "PARTIAL"
                note = "some cases could not be measured: " + "; ".join(
                    sorted({r.get("observed", "") for r in unclear}))[:180]
            else:
                status = "VERIFIED"
                note = description
        counts[status] += 1
        lines.append(f"| {category} | `{fixture}` | {len(rows)} | {status} | {prettify(note)} |")

    for category, description, note in UNTESTED:
        counts["UNTESTED"] += 1
        lines.append(f"| {category} | — | 0 | UNTESTED | {prettify(note)} |")

    summary = ", ".join(f"{n} {s.lower()}" for s, n in sorted(counts.items()))
    lines.insert(4, f"**{summary}.**")
    lines.insert(5, "")

    Path(out_path).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"support matrix written to {out_path}")
    print("  " + summary)
    return 0


if __name__ == "__main__":
    directory = sys.argv[1] if len(sys.argv) > 1 else "docs/evidence"
    destination = sys.argv[2] if len(sys.argv) > 2 else "docs/SUPPORT_MATRIX.md"
    sys.exit(main(directory, destination))
