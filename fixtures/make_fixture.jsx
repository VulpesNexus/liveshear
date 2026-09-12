// make_fixture.jsx -- builds the controlled test document for the Live Shear
// investigation: one rectangle, one Bezier path, one live text object and one
// group. Every object is named so probes can address it.
//
// Returns the document name.

(function () {
    var doc = app.documents.add(DocumentColorSpace.RGB, 600, 600);
    doc.rulerOrigin = [0, 0];

    function noStroke(item) { item.stroked = false; }
    function fill(item, r, g, b) {
        var c = new RGBColor();
        c.red = r; c.green = g; c.blue = b;
        item.filled = true;
        item.fillColor = c;
    }

    // A plain rectangle with exact, memorable coordinates.
    // Illustrator's rectangle() takes [top, left, width, height].
    var rect = doc.pathItems.rectangle(500, 100, 200, 120);
    rect.name = "fixture-rect";
    fill(rect, 200, 40, 40);
    noStroke(rect);

    // A Bezier path with curve handles, so shear can be checked on control
    // points as well as anchors.
    var curve = doc.pathItems.add();
    curve.name = "fixture-curve";
    curve.setEntirePath([[100, 100], [200, 250], [300, 100]]);
    curve.pathPoints[1].leftDirection = [150, 250];
    curve.pathPoints[1].rightDirection = [250, 250];
    curve.filled = false;
    curve.stroked = true;
    var strokeColor = new RGBColor();
    strokeColor.red = 30; strokeColor.green = 60; strokeColor.blue = 200;
    curve.strokeColor = strokeColor;
    curve.strokeWidth = 4;

    // Live point text.
    var text = doc.textFrames.add();
    text.name = "fixture-text";
    text.contents = "Handgloves";
    text.position = [340, 480];
    text.textRange.characterAttributes.size = 48;

    // A group of two shapes.
    var group = doc.groupItems.add();
    group.name = "fixture-group";
    var a = doc.pathItems.ellipse(340, 340, 100, 100);
    fill(a, 40, 160, 80);
    noStroke(a);
    a.name = "group-circle";
    a.moveToBeginning(group);
    var b = doc.pathItems.rectangle(300, 380, 80, 50);
    fill(b, 240, 180, 20);
    noStroke(b);
    b.name = "group-square";
    b.moveToBeginning(group);

    app.executeMenuCommand("deselectall");
    doc.name;
})();
