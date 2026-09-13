//  harness.jsx -- the measurement library the probes drive Illustrator with.
//
//  Illustrator keeps the globals of one DoJavaScript call alive for the next,
//  so this file is sent once per session and every probe afterward is a short
//  call into LS.*. Keeping the fixtures here means every probe builds the same
//  artwork from the same code.
//
//  The central measurement is LS.compareNative: it builds a fixture twice,
//  gives one copy the live Shear effect and the other copy Illustrator's own
//  destructive shear with the same angles, and reports both sets of visible
//  bounds. Any disagreement is a real difference in what the two produce, for
//  any kind of artwork, without having to know the shape's outline.
//
//  Pure ASCII on purpose: the file is read in the system codepage.

var LS = (function () {

    var api = {};

    var SEPARATOR = String.fromCharCode(9);
    var RE_NEWLINES = new RegExp('[' + String.fromCharCode(13) +
                                 String.fromCharCode(10) + ']+', 'g');

    // ---- basics ---------------------------------------------------------

    api.doc = function () {
        if (app.documents.length === 0) { app.documents.add(); }
        app.coordinateSystem = CoordinateSystem.DOCUMENTCOORDINATESYSTEM;
        return app.documents[0];
    };

    api.clear = function () {
        var d = api.doc();
        d.selection = null;
        while (d.pageItems.length > 0) {
            try { d.pageItems[0].locked = false; d.pageItems[0].hidden = false; } catch (e) {}
            d.pageItems[0].remove();
        }
        while (d.symbols.length > 0) { d.symbols[0].remove(); }
        // Patterns accumulate otherwise: every run of a fixture that makes one
        // leaves another swatch behind in the same document. The one imported
        // from Illustrator's own library is kept, because fetching it means
        // opening a document and this host falls over under repeated scripted
        // open and close.
        for (var p = d.patterns.length - 1; p >= 0; p--) {
            try {
                if (d.patterns[p].name === api.PATTERN_NAME) { continue; }
                d.patterns[p].remove();
            } catch (e) {}
        }
        return d;
    };

    api.f = function (n) { return n.toFixed(9); };

    api.black = function () { var c = new GrayColor(); c.gray = 100; return c; };

    api.gray = function (g) { var c = new GrayColor(); c.gray = g; return c; };

    api.paint = function (o, strokeWidth) {
        o.filled = true;
        o.fillColor = api.black();
        if (strokeWidth && strokeWidth > 0) {
            o.stroked = true;
            o.strokeColor = api.gray(50);
            o.strokeWidth = strokeWidth;
        } else {
            o.stroked = false;
        }
        return o;
    };

    api.rect = function (left, top, w, h) {
        return api.doc().pathItems.rectangle(top, left, w, h);
    };

    // ---- measurement ----------------------------------------------------

    /** Every path anchor under one object, in tree order. A destructive
        transform maps these one to one, so fitting a matrix through them is
        exact. */
    api.anchorsOf = function (o) {
        var s = [];
        function walk(item) {
            if (item.typename === 'PathItem') {
                for (var j = 0; j < item.pathPoints.length; j++) {
                    var a = item.pathPoints[j].anchor;
                    s.push(api.f(a[0]) + ',' + api.f(a[1]));
                }
                return;
            }
            if (item.pageItems) {
                for (var k = 0; k < item.pageItems.length; k++) { walk(item.pageItems[k]); }
            }
        }
        walk(o);
        return s.join(' ');
    };

    /** Every path anchor in the document, in document order. */
    api.anchors = function () {
        var d = api.doc(), s = [];
        for (var i = 0; i < d.pathItems.length; i++) {
            var p = d.pathItems[i];
            for (var j = 0; j < p.pathPoints.length; j++) {
                var a = p.pathPoints[j].anchor;
                s.push(api.f(a[0]) + ',' + api.f(a[1]));
            }
        }
        return s.join(' ');
    };

    /** Visible bounds: the only bounds that reflect a live effect. The DOM's
        geometricBounds ignores the appearance entirely, which is why every
        comparison below is made on these. */
    api.vb = function (o) {
        var v = o.visibleBounds;
        return api.f(v[0]) + ',' + api.f(v[1]) + ',' + api.f(v[2]) + ',' + api.f(v[3]);
    };

    api.gb = function (o) {
        var g = o.geometricBounds;
        return api.f(g[0]) + ',' + api.f(g[1]) + ',' + api.f(g[2]) + ',' + api.f(g[3]);
    };

    /** Geometric bounds and visible bounds of one object, semicolon separated. */
    api.bounds = function (o) { return api.gb(o) + ';' + api.vb(o); };

    api.selectOnly = function (o) {
        var d = api.doc();
        d.selection = null;
        o.selected = true;
        return o;
    };

    /** Finds a top-level object by name.

        Illustrator's scripting references are resolved by position, not by
        identity: duplicating an object inserts the copy at the top of the
        layer, every index below it shifts, and a reference held in a variable
        from an earlier call quietly starts pointing at a different object.
        Anything that has to survive a change in z-order, or a return from one
        DoJavaScript call to the next, is addressed by name instead. */
    api.named = function (name) {
        var d = api.doc();
        for (var i = 0; i < d.pageItems.length; i++) {
            if (d.pageItems[i].name === name) { return d.pageItems[i]; }
        }
        return null;
    };

    // ---- plugin bridge --------------------------------------------------

    api.send = function (selector, args) {
        return app.sendScriptMessage('LiveShear', selector, args || '');
    };

    api.nativeShear = function (shearAngle, axisAngle, dx, dy) {
        return api.send('native shear',
            [shearAngle, axisAngle, (dx || 0), (dy || 0), 0, 1, 0].join(','));
    };

    /** The shear action resolves "about the center" from a cached selection
        bounding box that a scripted selection does not refresh: redrawing,
        sleeping, reassigning the selection, and running the select-all menu
        command all leave it one selection behind. Playing the action itself is
        what refreshes it, so a zero-angle pass -- the identity, and therefore
        invisible in the geometry -- is played first. Without this every
        measurement is taken about the previous fixture's center. */
    api.nativeShearPrimed = function (shearAngle, axisAngle, dx, dy) {
        api.send('native shear', '0,0,0,0,0,1,0');
        return api.nativeShear(shearAngle, axisAngle, dx, dy);
    };

    /** Plays the native shear on one named object and says whether the object
        actually moved.

        The action reports success whether or not it did anything. It has been
        seen, in a long-running session, to return success and leave the
        artwork untouched for a run of attempts and then start working again,
        with no difference in the calls being made -- so a probe that assumed
        the oracle had been sheared would quietly compare against unsheared
        artwork and report the effect as wrong. Every caller checks this return
        value, retries, and marks the case inconclusive rather than failed if
        the oracle never moves. */
    api.nativeShearChecked = function (name, shearAngle, axisAngle) {
        var before = api.gb(api.named(name));
        api.nativeShearPrimed(shearAngle, axisAngle);
        app.redraw();
        return (api.gb(api.named(name)) === before) ? 'did not move' : 'moved';
    };

    api.applyEffect = function (name, spec) {
        return api.send('apply effect', name + '|' + (spec || ''));
    };

    api.shear = function (shearAngle, axisAngle) {
        return api.applyEffect('VulpesNexus Shear',
            'shearAngle=r:' + shearAngle + ';axisAngle=r:' + (axisAngle || 0));
    };

    api.appearance = function () { return api.send('appearance'); };

    // ---- the central comparison ----------------------------------------

    /** Builds `name` twice, shears one copy with the live effect and the other
        with Illustrator's own command, and reports what each produced.

        It is split into steps on purpose. AIMatchingArtSuite sees a selection
        made moments earlier in the same script, which is why applying the live
        effect works in one call -- but the action manager does not: a shear
        played in the same call as the selection it should act on finds nothing
        selected and does nothing at all. Illustrator has to be let back to its
        event loop in between, so each step is its own call from the probe.

        Fields: live visible bounds, native visible bounds, the live copy's own
        path anchors before and after (they must be identical -- a live effect
        may not touch its source), and whatever the plugin said when the effect
        was applied. */
    api.compareBegin = function (name) {
        api.clear();
        var live = api.fixtures[name]();
        live.name = 'lsLive';
        api.oracleMoved = false;
        app.redraw();
        var oracle = live.duplicate();
        oracle.name = 'lsOracle';
        api.caseName = name;
        api.beforeAnchors = api.anchorsOf(api.named('lsLive'));
        api.geometric = api.gb(api.named('lsLive'));
        api.applied = '';
        api.selectOnly(api.named('lsLive'));
        return 'built ' + name;
    };

    api.compareApplyLive = function (shearAngle, axisAngle) {
        api.applied = api.shear(shearAngle, axisAngle);
        app.redraw();
        return api.applied;
    };

    api.compareSelectOracle = function () {
        api.selectOnly(api.named('lsOracle'));
        return 'oracle selected';
    };

    api.compareShearOracle = function (shearAngle, axisAngle) {
        return api.nativeShearChecked('lsOracle', shearAngle, axisAngle);
    };

    api.compareRow = function (shearAngle, axisAngle) {
        var live = api.named('lsLive');
        var oracle = api.named('lsOracle');
        return [api.caseName, shearAngle, (axisAngle || 0), api.geometric,
                api.vb(live), api.vb(oracle),
                api.beforeAnchors, api.anchorsOf(live),
                api.applied.replace(RE_NEWLINES, ' '),
                (api.oracleMoved ? 'moved' : 'did not move')].join(SEPARATOR);
    };

    // ---- fixtures -------------------------------------------------------
    //
    //  Each returns the object a probe should target. They are deliberately
    //  asymmetric where symmetry would hide a bug: a centered square cannot
    //  tell a geometric anchor from a visible one.

    api.fixtures = {};

    api.fixtures.plainRect = function () {
        return api.paint(api.rect(100, 600, 200, 120), 0);
    };

    api.fixtures.strokedRect = function () {
        return api.paint(api.rect(100, 600, 200, 120), 40);
    };

    /** An acute triangle with a thick mitered stroke. The join spike pushes the
        visible bounds hundreds of points past the geometry on one side only,
        so geometric and visible centers are far apart. */
    api.fixtures.spike = function () {
        var p = api.doc().pathItems.add();
        p.setEntirePath([[100, 600], [400, 604], [100, 590]]);
        p.closed = true;
        api.paint(p, 20);
        p.strokeJoin = StrokeJoin.MITERENDJOIN;
        p.strokeMiterLimit = 100;
        return p;
    };

    /** Two rectangles with different stroke weights inside one group, so the
        union of the geometric bounds is centered elsewhere than the union of
        the visible bounds. */
    api.fixtures.mixedGroup = function () {
        var g = api.doc().groupItems.add();
        var a = api.paint(api.rect(100, 600, 100, 100), 0);
        a.move(g, ElementPlacement.PLACEATEND);
        var b = api.paint(api.rect(300, 600, 100, 100), 40);
        b.move(g, ElementPlacement.PLACEATEND);
        return g;
    };

    /** An open Bezier path: curves, not just corners. */
    api.fixtures.bezier = function () {
        var p = api.doc().pathItems.add();
        p.setEntirePath([[100, 500], [180, 620], [260, 480], [340, 600]]);
        p.closed = false;
        for (var i = 0; i < p.pathPoints.length; i++) {
            p.pathPoints[i].pointType = PointType.SMOOTH;
        }
        p.filled = false;
        p.stroked = true;
        p.strokeColor = api.black();
        p.strokeWidth = 6;
        return p;
    };

    api.fixtures.openPath = function () {
        var p = api.doc().pathItems.add();
        p.setEntirePath([[100, 500], [200, 620], [340, 520]]);
        p.closed = false;
        p.filled = false;
        p.stroked = true;
        p.strokeColor = api.black();
        p.strokeWidth = 12;
        p.strokeCap = StrokeCap.ROUNDENDCAP;
        return p;
    };

    /** A rectangle with a rectangular hole: a compound path with a real
        interior, so winding rules and child traversal both matter. */
    api.fixtures.compound = function () {
        var d = api.doc();
        var c = d.compoundPathItems.add();
        var outer = d.pathItems.rectangle(620, 100, 240, 160);
        outer.move(c, ElementPlacement.PLACEATEND);
        var inner = d.pathItems.rectangle(580, 140, 100, 80);
        inner.move(c, ElementPlacement.PLACEATEND);
        c.pathItems[0].filled = true;
        c.pathItems[0].fillColor = api.black();
        return c;
    };

    /** A five-pointed star drawn as one self-intersecting closed path. */
    api.fixtures.selfIntersecting = function () {
        var p = api.doc().pathItems.add();
        var pts = [], cx = 220, cy = 550, r = 90;
        for (var i = 0; i < 5; i++) {
            var a = -Math.PI / 2 + (i * 4 * Math.PI / 5);
            pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
        }
        p.setEntirePath(pts);
        p.closed = true;
        api.paint(p, 0);
        return p;
    };

    api.fixtures.tinyPath = function () {
        return api.paint(api.rect(100, 600, 0.01, 0.006), 0);
    };

    api.fixtures.hugePath = function () {
        return api.paint(api.rect(-4000, 4000, 8000, 5000), 0);
    };

    /** Far from the ruler origin, but inside Illustrator's canvas: past about
        12,000 points the application clamps what it will place, which makes a
        fixture out there measure something other than what was asked for. */
    api.fixtures.farFromOrigin = function () {
        return api.paint(api.rect(4000, 3000, 200, 120), 0);
    };

    api.fixtures.negativeCoords = function () {
        return api.paint(api.rect(-800, -400, 200, 120), 0);
    };

    /** Zero height: a horizontal line. The bounds center is still defined but
        the box has no extent in one direction. */
    api.fixtures.zeroHeight = function () {
        var p = api.doc().pathItems.add();
        p.setEntirePath([[100, 600], [300, 600]]);
        p.closed = false;
        p.filled = false;
        p.stroked = true;
        p.strokeColor = api.black();
        p.strokeWidth = 4;
        return p;
    };

    api.fixtures.zeroWidth = function () {
        var p = api.doc().pathItems.add();
        p.setEntirePath([[200, 500], [200, 620]]);
        p.closed = false;
        p.filled = false;
        p.stroked = true;
        p.strokeColor = api.black();
        p.strokeWidth = 4;
        return p;
    };

    /** A path with one anchor and no extent at all. */
    api.fixtures.singleAnchor = function () {
        var p = api.doc().pathItems.add();
        p.setEntirePath([[200, 600]]);
        p.closed = false;
        p.filled = false;
        p.stroked = true;
        p.strokeColor = api.black();
        p.strokeWidth = 4;
        return p;
    };

    api.fixtures.pointText = function () {
        var t = api.doc().textFrames.add();
        t.contents = 'Shear';
        t.position = [100, 600];
        t.textRange.characterAttributes.size = 72;
        return t;
    };

    api.fixtures.areaText = function () {
        var d = api.doc();
        var box = d.pathItems.rectangle(620, 100, 260, 160);
        var t = d.textFrames.areaText(box);
        t.contents = 'Shear the frame, not the glyphs.';
        t.textRange.characterAttributes.size = 24;
        return t;
    };

    api.fixtures.multilineText = function () {
        var t = api.doc().textFrames.add();
        t.contents = 'Shear\rtwo lines';
        t.position = [100, 600];
        t.textRange.characterAttributes.size = 48;
        return t;
    };

    api.fixtures.strokedText = function () {
        var t = api.fixtures.pointText();
        t.textRange.characterAttributes.strokeColor = api.gray(40);
        t.textRange.characterAttributes.strokeWeight = 6;
        return t;
    };

    /** Glyphs whose ink sits far off-center inside the frame: descenders on one
        side, capitals and no descender on the other. Point text is anchored at
        its baseline, so the visible ink and the frame's own box are a long way
        apart here, which is what makes it worth shearing. */
    api.fixtures.asymmetricText = function () {
        var t = api.doc().textFrames.add();
        t.contents = 'gjpqy TTT';
        t.position = [100, 600];
        t.textRange.characterAttributes.size = 96;
        return t;
    };

    /** Text whose contents were replaced after the frame was made. The frame
        keeps its origin and the ink moves, so anything that cached a box when
        the frame was created is caught out. */
    api.fixtures.retypedText = function () {
        var t = api.fixtures.pointText();
        t.contents = 'Retyped much wider';
        return t;
    };

    /** The same, for a font size changed after the fact. */
    api.fixtures.resizedText = function () {
        var t = api.fixtures.pointText();
        t.textRange.characterAttributes.size = 24;
        return t;
    };

    /** A raster embedded in the document. Drawn as a small PNG written to disk
        and placed, then embedded, because there is no way to hand Illustrator
        pixels directly from a script. */
    api.fixtures.embeddedRaster = function () {
        var d = api.doc();
        var f = new File(Folder.temp.fsName + '/liveshear-raster.png');
        if (!f.exists) {
            // A 2x2 checker, written by hand as an uncompressed BMP -- one
            // format simple enough to emit from ExtendScript without a
            // library, and one Illustrator will place.
            var bytes = api.tinyBitmap();
            f = new File(Folder.temp.fsName + '/liveshear-raster.bmp');
            f.encoding = 'BINARY';
            f.open('w');
            f.write(bytes);
            f.close();
        }
        var placed = d.placedItems.add();
        placed.file = f;
        placed.position = [100, 600];
        placed.width = 200;
        placed.height = 120;
        try { placed.embed(); } catch (e) {}
        return d.pageItems[0];
    };

    /** A 2 by 2 24-bit BMP: header, then four pixels, bottom row first, each
        row padded to a multiple of four bytes. */
    api.tinyBitmap = function () {
        function le(n, width) {
            var s = '';
            for (var i = 0; i < width; i++) { s += String.fromCharCode((n >> (8 * i)) & 0xFF); }
            return s;
        }
        var pixels = le(0x000000, 3) + le(0xFFFFFF, 3) + le(0, 2) +   // bottom row + padding
                     le(0xFFFFFF, 3) + le(0x000000, 3) + le(0, 2);    // top row + padding
        var header = 'BM' + le(14 + 40 + pixels.length, 4) + le(0, 2) + le(0, 2) + le(14 + 40, 4);
        var info = le(40, 4) + le(2, 4) + le(2, 4) + le(1, 2) + le(24, 2) +
                   le(0, 4) + le(pixels.length, 4) + le(2835, 4) + le(2835, 4) + le(0, 4) + le(0, 4);
        return header + info + pixels;
    };

    api.fixtures.nestedGroup = function () {
        var d = api.doc();
        var outer = d.groupItems.add();
        var inner = d.groupItems.add();
        inner.move(outer, ElementPlacement.PLACEATEND);
        var a = api.paint(api.rect(100, 600, 100, 100), 0);
        a.move(inner, ElementPlacement.PLACEATEND);
        var b = api.paint(api.rect(260, 560, 120, 80), 10);
        b.move(inner, ElementPlacement.PLACEATEND);
        var c = api.paint(api.rect(120, 460, 200, 40), 0);
        c.move(outer, ElementPlacement.PLACEATEND);
        return outer;
    };

    /** A clipping group: the topmost member is the mask. */
    api.fixtures.clipGroup = function () {
        var d = api.doc();
        var g = d.groupItems.add();
        var art = api.paint(api.rect(100, 620, 300, 200), 0);
        art.move(g, ElementPlacement.PLACEATEND);
        var mask = d.pathItems.ellipse(600, 140, 180, 140);
        mask.move(g, ElementPlacement.PLACEATBEGINNING);
        mask.clipping = true;
        g.clipped = true;
        return g;
    };

    api.fixtures.symbolInstance = function () {
        var d = api.doc();
        var art = api.paint(api.rect(100, 600, 120, 80), 8);
        var sym = d.symbols.add(art);
        var inst = d.symbolItems.add(sym);
        inst.position = [140, 580];
        return inst;
    };

    api.fixtures.gradientFill = function () {
        var d = api.doc();
        var r = api.rect(100, 600, 240, 140);
        var grad = d.gradients.add();
        grad.type = GradientType.LINEAR;
        var gc = new GradientColor();
        gc.gradient = grad;
        r.filled = true;
        r.fillColor = gc;
        r.stroked = false;
        return r;
    };

    api.fixtures.radialFill = function () {
        var r = api.fixtures.gradientFill();
        r.fillColor.gradient.type = GradientType.RADIAL;
        return r;
    };

    // Pattern fills looked untestable for a while, and the reason turned out
    // to be neither the tile nor Illustrator's renderer but one line of
    // scripting. A fill assigned as
    //
    //     var pc = new PatternColor(); pc.pattern = doc.patterns[0];
    //     item.fillColor = pc;
    //
    // reads back as a PatternColor, reports the right pattern, and draws
    // nothing whatsoever. The identical pattern assigned as
    //
    //     item.fillColor = doc.swatches.getByName(name).color;
    //
    // draws. Measured side by side in one document, one rectangle each: the
    // first contributes no non-white pixel, the second nearly two thousand.
    // That is why three different ways of building a tile all seemed to fail
    // -- every one of them ended at the same constructor.
    //
    // So the fixture goes through a swatch, and takes the pattern from a
    // library Illustrator ships rather than building one, which makes it a
    // real Adobe-authored pattern rather than a construction of ours.
    api.PATTERN_NAME = '10 dpi 50%';

    api.patternLibrary = function () {
        return new File(app.path.fsName.replace(/\\/g, '/') +
            '/Presets/' + app.locale +
            '/Swatches/Patterns/Basic Graphics/Basic Graphics_Dots.ai');
    };

    /** The swatch color for api.PATTERN_NAME, imported into the working
        document the first time and reused afterwards. Returns null if the
        library is not where Illustrator usually puts it, so a caller can
        report the fixture as unavailable rather than silently testing a
        rectangle with no pattern in it. */
    api.patternColor = function () {
        var d = api.doc();
        var i;
        for (i = 0; i < d.swatches.length; i++) {
            if (d.swatches[i].name === api.PATTERN_NAME) { return d.swatches[i].color; }
        }

        var f = api.patternLibrary();
        if (!f.exists) { return null; }

        // Carried across on the clipboard, which brings the pattern definition
        // with it. The library document is opened read-only in effect: the
        // scratch rectangle is removed again and it is closed without saving.
        var lib = app.open(f);
        var src = lib.pathItems.rectangle(200, 0, 100, 100);
        src.stroked = false;
        src.filled = true;
        src.fillColor = lib.swatches.getByName(api.PATTERN_NAME).color;
        lib.selection = null;
        src.selected = true;
        app.copy();

        // Paste before closing the library, not after. Closing the document
        // the clipboard came from discards it -- Illustrator would normally
        // ask whether to keep it, and under DONTDISPLAYALERTS that question is
        // answered for us. The paste then produces no selection at all and the
        // next line fails on an undefined object.
        app.activeDocument = d;
        app.paste();
        var pasted = (d.selection && d.selection.length) ? d.selection[0] : null;
        if (pasted) { pasted.remove(); }
        d.selection = null;

        app.activeDocument = lib;
        src.remove();
        lib.close(SaveOptions.DONOTSAVECHANGES);
        app.activeDocument = d;

        for (i = 0; i < d.swatches.length; i++) {
            if (d.swatches[i].name === api.PATTERN_NAME) { return d.swatches[i].color; }
        }
        return null;
    };

    api.fixtures.patternFill = function () {
        var r = api.rect(100, 600, 240, 140);
        r.filled = true;
        r.stroked = false;
        var pc = api.patternColor();
        if (pc) { r.fillColor = pc; }
        return r;
    };

    api.fixtures.dashedStroke = function () {
        var r = api.paint(api.rect(100, 600, 200, 120), 12);
        r.strokeDashes = [18, 9];
        return r;
    };

    api.fixtures.roundJoin = function () {
        var p = api.fixtures.spike();
        p.strokeJoin = StrokeJoin.ROUNDENDJOIN;
        return p;
    };

    api.fixtures.bevelJoin = function () {
        var p = api.fixtures.spike();
        p.strokeJoin = StrokeJoin.BEVELENDJOIN;
        return p;
    };

    /** Applies the first brush whose name matches, falling back to the first
        brush the document has. A default document ships a calligraphic set and
        a few art and pattern brushes; which ones depends on the profile, so
        nothing here assumes a particular one is present. */
    api.brushed = function (names) {
        var p = api.fixtures.openPath();
        var brushes = app.activeDocument.brushes;
        for (var n = 0; n < names.length; n++) {
            for (var i = 0; i < brushes.length; i++) {
                if (brushes[i].name === names[n]) {
                    try { brushes[i].applyTo(p); return p; } catch (e) {}
                }
            }
        }
        if (brushes.length > 0) { try { brushes[0].applyTo(p); } catch (e) {} }
        return p;
    };

    api.fixtures.calligraphicBrush = function () {
        return api.brushed(['5 pt. Round', '3 pt. Oval', '5 pt. Flat']);
    };

    api.fixtures.artBrush = function () {
        return api.brushed(['Charcoal - Feather', 'Mop', 'Dry Ink 2']);
    };

    api.fixtures.patternBrush = function () {
        return api.brushed(['Denim Seam', 'Divider', 'Rope']);
    };

    // ---- source art that already carries a transform --------------------

    api.fixtures.rotatedRect = function () {
        var r = api.paint(api.rect(100, 600, 200, 120), 0);
        r.rotate(37);
        return r;
    };

    api.fixtures.scaledRect = function () {
        var r = api.paint(api.rect(100, 600, 200, 120), 0);
        r.resize(180, 60);
        return r;
    };

    api.fixtures.reflectedRect = function () {
        var p = api.doc().pathItems.add();
        p.setEntirePath([[100, 600], [300, 610], [280, 500]]);
        p.closed = true;
        api.paint(p, 0);
        p.resize(-100, 100);
        return p;
    };

    /** Source art that has already been sheared destructively. The transform is
        applied through the DOM rather than by playing the shear action, because
        the action reads a cached selection box that a selection made moments
        earlier in the same script has not refreshed. */
    api.fixtures.preShearedRect = function () {
        var r = api.paint(api.rect(100, 600, 200, 120), 0);
        var b = r.geometricBounds;
        var k = Math.tan(20 * Math.PI / 180);
        var m = app.getIdentityMatrix();
        m.mValueC = k;
        m.mValueTX = -k * (b[1] + b[3]) / 2;
        r.transform(m, true, true, true, true, 1, Transformation.DOCUMENTORIGIN);
        return r;
    };

    api.fixtures.transformedGroup = function () {
        var g = api.fixtures.nestedGroup();
        g.rotate(23);
        g.translate(40, -15);
        return g;
    };

    /** A group with many children, for the performance and stress cases. */
    api.fixtures.manyChildren = function () {
        var d = api.doc();
        var g = d.groupItems.add();
        for (var i = 0; i < 200; i++) {
            var r = api.paint(api.rect(100 + (i % 20) * 12, 600 - Math.floor(i / 20) * 12, 10, 10), 0);
            r.move(g, ElementPlacement.PLACEATEND);
        }
        return g;
    };

    return api;
})();
"harness installed";
