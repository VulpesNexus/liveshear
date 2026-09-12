// make_probe_shape.jsx -- a document holding one asymmetric polygon.
//
// Measuring what an effect rendered means pairing the anchor points of the
// expanded result with the anchor points of the source. A rectangle is no good
// for that: it maps onto itself under reflection, so a wrong pairing fits the
// data just as exactly as the right one. This polygon has no affine symmetry,
// so only the true correspondence produces a zero residual.

(function () {
    var doc = app.documents.add(DocumentColorSpace.RGB, 600, 600);
    doc.rulerOrigin = [0, 0];

    var shape = doc.pathItems.add();
    shape.name = "probe-shape";
    shape.setEntirePath([
        [100, 300],
        [310, 350],
        [270, 470],
        [170, 520],
        [130, 410]
    ]);
    shape.closed = true;

    var fill = new RGBColor();
    fill.red = 180; fill.green = 60; fill.blue = 140;
    shape.filled = true;
    shape.fillColor = fill;
    shape.stroked = false;

    app.executeMenuCommand("deselectall");
    shape.selected = true;
    "probe-shape";
})();
