"""Generates docs/RELEASE_TEST_MATRIX.md from the evidence files.

Every probe writes a tab-separated record of what it checked alongside its
readable transcript, so the matrix is assembled from data rather than copied
out of prose. "Twenty-four checks passed" is not evidence; a list of what the
twenty-four were is.

Each row is probe, group, case, expected, observed, status.
"""

import sys
from collections import Counter
from pathlib import Path

SOURCES = [
    ("build.tsv", "The built artifact", "Both configurations rebuilt from clean, and the Release binary inspected: warnings, identity, C runtime linkage, exported entry point, and whether it gives away anything about the machine that built it."),
    ("solvers.tsv", "Test infrastructure", "The two scripts that turn measurements into verdicts, fed rows whose right answer is known by construction. A bug in either would turn a real failure into a green matrix, which is the one kind of bug running more tests cannot catch."),
    ("mathtest.tsv", "Arithmetic", "The affine algebra and the exact extent of a cubic Bezier, compiled against stub types and run without Illustrator. It covers the bounds fallback, which only runs when the host refuses to measure art itself and therefore cannot be reached on demand from a host test."),
    ("anchor-verdicts.tsv", "Reference point", "Which box Illustrator's own Shear command anchors on, recovered by fitting the anchor out of artwork it actually produced. A fixture whose geometric and visible centers coincide cannot tell the two apart and is marked as not discriminating rather than counted as agreement."),
    ("artwork-anchor.tsv", "Reference point, by kind of artwork", "The same question as the row above, asked of artwork that has no path anchors to fit a line through. Two shears of one angle about different reference points differ by a translation and nothing else, so subtracting the two bounding boxes recovers how far apart the reference points were -- and says so in points, rather than reporting that two numbers were not equal."),
    ("release-verdicts.tsv", "Artwork types", "Each fixture built twice: one copy carrying the live effect, the other sheared by *Object > Transform > Shear* with the same angles. The two must render to the same visible bounds, and the live copy's own path anchors must be unchanged."),
    ("appearance.tsv", "Appearance composition", "Stack order, two instances, reordering, and deletion, with the native command as the oracle at every step."),
    ("persistence.tsv", "Save and reopen", "Write the document, close it, open it again, edit the effect, save and open once more."),
    ("fills.tsv", "Gradients and patterns", "Rendered to PNG and compared pixel by pixel against the native command, because bounds cannot see whether a fill inside the shape sheared with it."),
    ("export.tsv", "Export", "Export, then open the exported file back in Illustrator and measure what is in it."),
    ("limits.tsv", "Parameter safety", "Values written straight into the parameter dictionary, past anything the dialog would allow, each redraw under a watchdog."),
    ("schema.tsv", "Serialization and schema", "Parameter blocks this version did not write: keys missing, keys of the wrong type, an empty block, and a schema number from a version that does not exist yet. Each one redrawn behind a watchdog, so a dictionary that made the effect fail to return would be reported rather than hang the run."),
    ("blend.tsv", "Blends", "Two objects carrying different Shear parameters, blended. Illustrator calls the effect's interpolation handler while it builds the blend, which nothing else can observe, so the handler writes to the plugin's trace and the probe reads it back. The angles are chosen so that a naive midpoint would be wrong."),
    ("generated-art.tsv", "Artwork generated from a path", "Brushes are not artwork but a rule for making it, and a destructive transform re-applies the rule while a live effect can only transform what the rule already produced. Adobe's own Transform effect is the control: where it differs from Adobe's own command, this effect differs in the same way."),
    ("everyday.tsv", "Ordinary use", "Things a person does in the first five minutes that no other probe covers, because every other probe shears one scripted object in an empty document: three objects selected at once, text on a path, a graphic style carrying the effect to something else, and a single child of a group."),
    ("sequence-crash.tsv", "The crash, controlled", "Illustrator died twice at the same point in a full suite run. These rows are the two-arm comparison that followed: the same work with the effect and without it, alternated, each trial in a fresh Illustrator. MEASURED rather than passed or failed, because the question is a comparison between arms."),
    ("dialog.tsv", "Dialog", "Driven through the window manager from a second process, because the call that opens the dialog is blocked until it closes."),
    ("undo.tsv", "Undo and redo", "Every edit undone and redone, counting how many steps one deliberate action costs."),
    ("stability.tsv", "Stability and performance", "Identity, cumulative drift, source invariance, evaluation cost, and a document full of independent instances."),
    ("gpu.tsv", "Preview mode", "The document window captured as a bitmap under each preview path and compared pixel by pixel."),
    ("missing-plugin.tsv", "Opened without the plugin", "The document authored with the effect, then opened on a machine where the plugin is not installed: what still draws, what stops, and whether saving from that state loses anything."),
    ("crash-ab.tsv", "Document churn", "Illustrator dies under long runs of scripted document create/close with no third-party plugin installed at all. These rows are the three-arm comparison that says whether having this one loaded, or using it, changes that. They are labeled MEASURED rather than passed or failed, because the question is a comparison between arms and not a threshold."),
    ("shutdown.tsv", "Application shutdown", "Illustrator quit the ordinary way from each state this plugin can leave it in, checking that it went, that it went promptly, and that the Windows event log has nothing new to say."),
]


def read(path):
    if not path.exists():
        return None
    rows = path.read_text(encoding="utf-8").splitlines()
    if not rows:
        return None
    header = rows[0].split("\t")
    out = []
    for row in rows[1:]:
        if row.strip():
            out.append(dict(zip(header, row.split("\t"))))
    return out


def escape(text):
    return text.replace("|", r"\|").strip()


def main(evidence_dir, out_path):
    evidence = Path(evidence_dir)
    sections = []
    totals = Counter()
    missing = []

    for filename, title, blurb in SOURCES:
        rows = read(evidence / filename)
        if rows is None:
            missing.append(filename)
            continue

        lines = [f"## {title}", "", blurb, "",
                 "| # | Group | Case | Expected | Observed | Status |",
                 "| --- | --- | --- | --- | --- | --- |"]
        for index, row in enumerate(rows, 1):
            status = row.get("status", "").strip() or "UNLABELED"
            totals[status] += 1
            mark = "**FAIL**" if status == "FAIL" else status
            lines.append("| {} | {} | {} | {} | {} | {} |".format(
                index,
                escape(row.get("group", "")),
                escape(row.get("case", "")),
                escape(row.get("expected", "")),
                escape(row.get("observed", "")),
                mark))
        lines.append("")
        lines.append(f"Source: [docs/evidence/{filename}](evidence/{filename})")
        lines.append("")
        sections.append("\n".join(lines))

    total = sum(totals.values())
    # Status labels other than PASS and FAIL are deliberate: a fixture whose
    # geometric and visible centers coincide cannot tell an anchor apart, and a
    # comparison the host would not let us make is not a pass.
    ordered = ([f"{totals['PASS']} passed"] if totals["PASS"] else [])
    ordered += ([f"{totals['FAIL']} failed"] if totals["FAIL"] else [])
    ordered += [f"{count} {label.lower()}"
                for label, count in sorted(totals.items())
                if label not in ("PASS", "FAIL")]
    head = [
        "# Release test matrix",
        "",
        "Generated from the evidence files by *tools/make-test-matrix.py*. Every row is one check that was actually run; nothing here is transcribed by hand. The first three sections need no Illustrator — the built artifact, the scripts that judge, and the arithmetic. Everything after them was measured against a running one.",
        "",
        f"**{', '.join(ordered)} — {total} checks.**",
        "",
    ]
    if missing:
        head.append("Not present in this run: " + ", ".join(f"*{m}*" for m in missing) + ".")
        head.append("")

    Path(out_path).write_text("\n".join(head) + "\n" + "\n".join(sections), encoding="utf-8")
    print(f"{total} checks written to {out_path}")
    print("  " + ", ".join(ordered))
    if missing:
        print("  missing: " + ", ".join(missing))
    return 1 if totals["FAIL"] else 0


if __name__ == "__main__":
    directory = sys.argv[1] if len(sys.argv) > 1 else "docs/evidence"
    destination = sys.argv[2] if len(sys.argv) > 2 else "docs/RELEASE_TEST_MATRIX.md"
    sys.exit(main(directory, destination))
