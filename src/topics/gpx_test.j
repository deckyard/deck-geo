# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# geo - white-box tests for the gpx topic.
# Spliced into geo_test.j via include - run with:
#   jennifer test src/geo_test.j

/** A small GPX 1.1 document with a waypoint, a route and a two-segment track. */
func gpxFixture() {
    def parts as list of string init [];
    $parts[] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    $parts[] = "<gpx version=\"1.1\" creator=\"Fixture\" ";
    $parts[] = "xmlns=\"http://www.topografix.com/GPX/1/1\">\n";
    $parts[] = "  <metadata><name>Innsbruck loop</name>";
    $parts[] = "<desc>A &amp; B</desc><time>2026-09-30T06:00:00Z</time></metadata>\n";
    $parts[] = "  <wpt lat=\"47.2692\" lon=\"11.4041\">";
    $parts[] = "<ele>574</ele><name>Start</name><sym>Flag</sym></wpt>\n";
    $parts[] = "  <rte><name>Plan</name>";
    $parts[] = "<rtept lat=\"47.0\" lon=\"11.0\" /><rtept lat=\"47.1\" lon=\"11.1\" /></rte>\n";
    $parts[] = "  <trk><name>Day 1</name><type>hiking</type>\n";
    $parts[] = "    <trkseg><trkpt lat=\"47.2\" lon=\"11.2\">";
    $parts[] = "<ele>600</ele><time>2026-09-30T06:01:00Z</time></trkpt>\n";
    $parts[] = "    <trkpt lat=\"47.3\" lon=\"11.3\"><ele>700</ele></trkpt></trkseg>\n";
    $parts[] = "    <trkseg><trkpt lat=\"47.4\" lon=\"11.4\" /></trkseg>\n";
    $parts[] = "  </trk>\n</gpx>\n";
    return strings.join($parts, "");
}

func testReadGpxReadsTheMetadata() {
    def doc as Document init readGpx(gpxFixture());
    testing.assertEqual($doc.name, "Innsbruck loop");
    testing.assertEqual($doc.desc, "A & B");
    testing.assertEqual($doc.at, "2026-09-30T06:00:00Z");
    testing.assertEqual($doc.creator, "Fixture");
}

func testReadGpxLeavesAnOutOfRangeReferenceInTheHeaderStanding() {
    # xml.decode rejects the reference, so this reads through the scanner, and
    # the scanner's own entity decoder has to refuse an overflowing reference
    def huge as string init "&#99999999999999999999999;";
    def text as string init "<gpx creator=\"a" + $huge + "\"><metadata><name>" + $huge +
        "</name></metadata><trk><name>" + $huge + "</name><trkseg>" +
        "<trkpt lat=\"1\" lon=\"2\"/></trkseg></trk></gpx>";
    def doc as Document init readGpx($text);
    testing.assertEqual($doc.creator, "a" + $huge);
    testing.assertEqual($doc.name, $huge);
    testing.assertEqual($doc.tracks[0].name, $huge);
}

func testReadGpxReadsAWaypoint() {
    def doc as Document init readGpx(gpxFixture());
    testing.assertEqual(len($doc.waypoints), 1);
    def w as Point init $doc.waypoints[0];
    testing.assertEqual($w.lat, 47.2692);
    testing.assertEqual($w.lon, 11.4041);
    testing.assertEqual($w.ele, 574.0);
    testing.assertTrue($w.hasElevation);
    testing.assertEqual($w.name, "Start");
    testing.assertEqual($w.sym, "Flag");
    testing.assertFalse($w.hasTime);
}

func testReadGpxReadsARoute() {
    def doc as Document init readGpx(gpxFixture());
    testing.assertEqual(len($doc.routes), 1);
    testing.assertEqual($doc.routes[0].name, "Plan");
    testing.assertEqual(len($doc.routes[0].points), 2);
    testing.assertEqual($doc.routes[0].points[1].lon, 11.1);
}

func testReadGpxKeepsTheSegmentsApart() {
    def doc as Document init readGpx(gpxFixture());
    testing.assertEqual(len($doc.tracks), 1);
    def t as Track init $doc.tracks[0];
    testing.assertEqual($t.name, "Day 1");
    testing.assertEqual($t.kind, "hiking");
    testing.assertEqual(len($t.segments), 2);
    testing.assertEqual(len($t.segments[0].points), 2);
    testing.assertEqual(len($t.segments[1].points), 1);
    testing.assertEqual(len(trackPoints($t)), 3);
}

func testReadGpxReadsAGpx10Document() {
    # 1.0 puts the name on the root rather than in <metadata>
    def text as string init "<gpx version=\"1.0\" creator=\"Old\">" +
        "<name>Legacy</name><wpt lat=\"47.0\" lon=\"11.0\" /></gpx>";
    def doc as Document init readGpx($text);
    testing.assertEqual($doc.name, "Legacy");
    testing.assertEqual(len($doc.waypoints), 1);
}

func testReadGpxAcceptsANamespacePrefix() {
    def text as string init "<gpx:gpx xmlns:gpx=\"http://www.topografix.com/GPX/1/1\">" +
        "<gpx:wpt lat=\"47.0\" lon=\"11.0\"><gpx:name>P</gpx:name></gpx:wpt></gpx:gpx>";
    def doc as Document init readGpx($text);
    testing.assertEqual(len($doc.waypoints), 1);
    testing.assertEqual($doc.waypoints[0].name, "P");
}

func testReadGpxIgnoresExtensions() {
    # a Garmin heart-rate extension is not a field this model carries, and must
    # not be mistaken for one either
    def text as string init "<gpx><trk><trkseg><trkpt lat=\"47.0\" lon=\"11.0\">" +
        "<ele>500</ele><extensions><gpxtpx:TrackPointExtension>" +
        "<gpxtpx:hr>140</gpxtpx:hr><gpxtpx:ele>999</gpxtpx:ele>" +
        "</gpxtpx:TrackPointExtension></extensions></trkpt></trkseg></trk></gpx>";
    def doc as Document init readGpx($text);
    def p as Point init $doc.tracks[0].segments[0].points[0];
    testing.assertEqual($p.ele, 500.0);
}

# The common Garmin shape: the extension prefix is declared on the root, so each
# cut-out point decodes against the root's bindings on the first try.
func testReadGpxReadsDeclaredExtensions() {
    def text as string init "<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" " +
        "xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\">" +
        "<trk><trkseg><trkpt lat=\"47.0\" lon=\"11.0\"><ele>500</ele><extensions>" +
        "<gpxtpx:TrackPointExtension><gpxtpx:hr>140</gpxtpx:hr></gpxtpx:TrackPointExtension>" +
        "</extensions></trkpt></trkseg></trk></gpx>";
    def p as Point init readGpx($text).tracks[0].segments[0].points[0];
    testing.assertEqual($p.ele, 500.0);
}

func failOnNonGpxRoot() {
    readGpx("<kml><Document /></kml>");
}

func failOnWaypointWithNoCoordinates() {
    readGpx("<gpx><wpt><name>nowhere</name></wpt></gpx>");
}

func failOnWaypointWithAWordForALatitude() {
    readGpx("<gpx><wpt lat=\"north\" lon=\"11.0\" /></gpx>");
}

func failOnWaypointOutsideTheWorld() {
    readGpx("<gpx><wpt lat=\"91.0\" lon=\"11.0\" /></gpx>");
}

func testReadGpxRejectsWhatItCannotRead() {
    testing.assertThrows("failOnNonGpxRoot", ERROR_KIND);
    testing.assertThrows("failOnWaypointWithNoCoordinates", ERROR_KIND);
    testing.assertThrows("failOnWaypointWithAWordForALatitude", ERROR_KIND);
    testing.assertThrows("failOnWaypointOutsideTheWorld", ERROR_KIND);
}

func testWriteGpxOpensWithADeclarationAndTheNamespace() {
    def text as string init writeGpx(document());
    testing.assertTrue(strings.startsWith($text, "<?xml version=\"1.0\""));
    testing.assertContains($text, GPX_NAMESPACE);
    testing.assertContains($text, "version=\"1.1\"");
    testing.assertContains($text, "creator=\"" + GPX_CREATOR + "\"");
    testing.assertTrue(strings.endsWith($text, "</gpx>\n"));
}

func testWriteGpxKeepsTheCreatorItWasGiven() {
    def doc as Document init document();
    $doc.creator = "Garmin Edge 530";
    testing.assertContains(writeGpx($doc), "creator=\"Garmin Edge 530\"");
}

func testWriteGpxWritesNoEmptyElements() {
    def doc as Document init document();
    $doc.waypoints = [point(47.2692, 11.4041)];
    def text as string init writeGpx($doc);
    # a field the point does not carry is an absent element, not an empty one
    testing.assertEqual(strings.indexOf($text, "<name>"), -1);
    testing.assertEqual(strings.indexOf($text, "<ele>"), -1);
    testing.assertEqual(strings.indexOf($text, "<metadata>"), -1);
    testing.assertContains($text, "<wpt lat=\"47.2692\" lon=\"11.4041\" />");
}

func testWriteGpxEscapesText() {
    def doc as Document init document();
    $doc.name = "A & B <C>";
    testing.assertContains(writeGpx($doc), "<name>A &amp; B &lt;C&gt;</name>");
}

func testWriteGpxWritesSeaLevelWhenItIsStated() {
    def doc as Document init document();
    $doc.waypoints = [withElevation(point(47.2692, 11.4041), 0.0)];
    testing.assertContains(writeGpx($doc), "<ele>0</ele>");
}

func testGpxRoundTripPreservesEverythingTheModelHolds() {
    def before as Document init readGpx(gpxFixture());
    def after as Document init readGpx(writeGpx($before));
    testing.assertEqual($after.name, $before.name);
    testing.assertEqual($after.desc, $before.desc);
    testing.assertEqual($after.at, $before.at);
    testing.assertEqual($after.creator, $before.creator);
    testing.assertEqual($after.waypoints, $before.waypoints);
    testing.assertEqual($after.routes, $before.routes);
    testing.assertEqual($after.tracks, $before.tracks);
}

func testGpxRoundTripIsStableOnASecondPass() {
    def once as string init writeGpx(readGpx(gpxFixture()));
    def twice as string init writeGpx(readGpx($once));
    testing.assertEqual($once, $twice);
}

func testGpxRoundTripKeepsCoordinatePrecision() {
    def doc as Document init document();
    $doc.waypoints = [point(47.2690914, 11.4038358)];
    def back as Document init readGpx(writeGpx($doc));
    testing.assertEqual($back.waypoints[0].lat, 47.2690914);
    testing.assertEqual($back.waypoints[0].lon, 11.4038358);
}

func testElementAndIndent() {
    testing.assertEqual(element("name", "A", 1), "  <name>A</name>\n");
    testing.assertEqual(element("name", "", 1), "");
    testing.assertEqual(element("name", "   ", 1), "");
    testing.assertEqual(element("name", " A ", 0), "<name>A</name>\n");
    testing.assertEqual(indent(0), "");
    testing.assertEqual(indent(3), "      ");
}

func testGpxCreator() {
    def doc as Document init document();
    testing.assertEqual(gpxCreator($doc), GPX_CREATOR);
    $doc.creator = "A & B";
    testing.assertEqual(gpxCreator($doc), "A &amp; B");
}

func testReadGpxKeepsAnUnknownEntityInAPointAsWritten() {
    # the scanner leaves `&deg;` standing in structural text; a point did not,
    # and one exporter's entity made the whole file unreadable
    def doc as Document init readGpx("<gpx><wpt lat=\"1\" lon=\"2\"><name>10&deg; N</name>" +
        "<desc>a & b</desc></wpt><trk><name>10&deg;</name></trk></gpx>");
    testing.assertEqual($doc.waypoints[0].name, "10&deg; N");
    testing.assertEqual($doc.waypoints[0].desc, "a & b");
    testing.assertEqual($doc.tracks[0].name, "10&deg;");
}

func testReadGpxReadsACloseTagWithSpace() {
    def doc as Document init readGpx("<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"><ele>5</ele>" +
        "</trkpt ><trkpt lat=\"3\" lon=\"4\" /></trkseg ></trk></gpx>");
    def pts as list of Point init trackPoints($doc.tracks[0]);
    testing.assertEqual(len($pts), 2);
    testing.assertEqual($pts[0].ele, 5.0);
    testing.assertEqual($pts[1].lat, 3.0);
}

func testReadGpxIgnoresMarkupInCommentsAndCdata() {
    def doc as Document init readGpx("<gpx><!-- end </gpx> --><wpt lat=\"1\" lon=\"2\">" +
        "<desc><![CDATA[x </wpt> <wpt> y]]></desc></wpt><wpt lat=\"3\" lon=\"4\" />" +
        "<trk><trkseg><!-- </trkseg> --><trkpt lat=\"5\" lon=\"6\" /></trkseg></trk></gpx>");
    testing.assertEqual(len($doc.waypoints), 2);
    testing.assertEqual($doc.waypoints[0].desc, "x </wpt> <wpt> y");
    testing.assertEqual($doc.waypoints[1].lat, 3.0);
    testing.assertEqual(len(trackPoints($doc.tracks[0])), 1);
}

func testReadGpxReadsPastAnUnclosedTrackPoint() {
    # the first <trkpt> never closes; the two after it are whole and are kept
    def doc as Document init readGpx("<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"><ele>1</ele>" +
        "<trkpt lat=\"3\" lon=\"4\"></trkpt><trkpt lat=\"5\" lon=\"6\"></trkpt></trkseg></trk></gpx>");
    def pts as list of Point init trackPoints($doc.tracks[0]);
    testing.assertEqual(len($pts), 2);
    testing.assertEqual($pts[0].lat, 3.0);
    testing.assertEqual($pts[1].lat, 5.0);
}

func testReadGpxReadsPastAnUnclosedWaypoint() {
    # the unclosed waypoint's <name> is not taken for the document's
    def doc as Document init readGpx("<gpx><wpt lat=\"1\" lon=\"2\"><name>broken</name>" +
        "<wpt lat=\"3\" lon=\"4\"><name>B</name></wpt>" +
        "<rte><name>R</name><rtept lat=\"7\" lon=\"8\"><name>x</name><rtept lat=\"9\" lon=\"8\" /></rte>" +
        "<trk><trkseg><trkpt lat=\"5\" lon=\"6\" /></trkseg></trk></gpx>");
    testing.assertEqual($doc.name, "");
    testing.assertEqual(len($doc.waypoints), 1);
    testing.assertEqual($doc.waypoints[0].name, "B");
    testing.assertEqual($doc.routes[0].name, "R");
    testing.assertEqual(len($doc.routes[0].points), 1);
    testing.assertEqual($doc.routes[0].points[0].lat, 9.0);
    testing.assertEqual(len(trackPoints($doc.tracks[0])), 1);
}

func testReadGpxTreatsAnEmptyTimeAsNone() {
    def doc as Document init readGpx("<gpx><wpt lat=\"1\" lon=\"2\"><time> </time></wpt>" +
        "<wpt lat=\"1\" lon=\"2\"><time></time></wpt></gpx>");
    testing.assertFalse($doc.waypoints[0].hasTime);
    testing.assertFalse($doc.waypoints[1].hasTime);
}

func testReadGpxTakesTheFirstOfARepeatedField() {
    def doc as Document init readGpx("<gpx><wpt lat=\"1\" lon=\"2\"><name>A</name><ele>3</ele>" +
        "<name>B</name><ele>4</ele><g:sym xmlns:g=\"urn:x\">S</g:sym></wpt></gpx>");
    testing.assertEqual($doc.waypoints[0].name, "A");
    testing.assertEqual($doc.waypoints[0].ele, 3.0);
    testing.assertEqual($doc.waypoints[0].sym, "S");
}

func testGpxChildrenAndLeadingFields() {
    def src as bytes init buffer("<gpx><name>N</name><wpt lat=\"1\" lon=\"2\"><name>W</name></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init gpxChildren($src, $root.openEnd, $root.innerEnd, "wpt");
    # name, the unclosed wpt, and the wpt's own name, listed as a sibling
    testing.assertEqual(len($kids), 3);
    testing.assertFalse($kids[1].closed);
    testing.assertEqual(len(leadingFields($kids)), 1);
    testing.assertEqual(gpxResume($kids[1]), $kids[1].openEnd);
    testing.assertEqual(gpxResume($kids[0]), $kids[0].end);
    testing.assertTrue(isGpxPoint("rtept"));
    testing.assertFalse(isGpxPoint("rte"));
}

func testWriteGpxWritesTextTrimmed() {
    # readers trim, so writing the padding made the first round trip change
    # the text and the second not
    def p as Point init point(1.0, 2.0);
    $p.name = "  padded\nname  ";
    def doc as Document init document();
    $doc.waypoints = [$p];
    def text as string init writeGpx($doc);
    testing.assertContains($text, "<name>padded\nname</name>");
    testing.assertEqual(writeGpx(readGpx($text)), $text);
}

func testWriteGpxEscapesEveryFieldThatNeedsIt() {
    def p as Point init withTime(point(1.0, 2.0), "t<1>");
    $p.name = "a\"b'c";
    $p.desc = "x\u0001y";
    $p.sym = "plain";
    def doc as Document init document();
    $doc.waypoints = [$p];
    def text as string init writeGpx($doc);
    testing.assertContains($text, "<time>t&lt;1&gt;</time>");
    testing.assertContains($text, "<name>a&quot;b&apos;c</name>");
    testing.assertContains($text, "<desc>xy</desc>");
    testing.assertContains($text, "<sym>plain</sym>");
}

func testElementWritesAnInnerCarriageReturnAsAReference() {
    # the fast path must not skip xmlEscape for a CR (XML 1.0 2.11 folds a raw CR into LF)
    testing.assertEqual(element("name", "a\rb", 0), "<name>a&#13;b</name>\n");
}

/** What one reader made of a document: the document, or the error it raised. */
def struct GpxRead {
    doc as Document,
    error as string
};

/**
 * Read a document with the scanner only.
 *
 * @param text {string} the document
 * @return {GpxRead} what it read, or `kind: message`
 */
func scanGpxRead(text as string) {
    def out as GpxRead init GpxRead{doc: document(), error: ""};
    try {
        $out.doc = readGpxScan(convert.bytesFromString($text, "utf-8"));
    } catch (e) {
        $out.error = $e.kind + ": " + $e.message;
    }
    return $out;
}

/**
 * Read a document with the tree reader only, asserting it may.
 *
 * @param text {string} the document
 * @return {GpxRead} what it read, or `kind: message`
 */
func treeGpxRead(text as string) {
    def src as bytes init convert.bytesFromString($text, "utf-8");
    def tree as GpxTree init gpxTree($src, $text);
    testing.assertTrue($tree.usable);
    def out as GpxRead init GpxRead{doc: document(), error: ""};
    try {
        $out.doc = readGpxTree($src, $tree.root);
    } catch (e) {
        $out.error = $e.kind + ": " + $e.message;
    }
    return $out;
}

/**
 * Assert the tree reader takes a document and reads what the scanner reads.
 *
 * @param text {string} the document
 * @return {Document} what both read
 */
func assertTreeReadsAsScan(text as string) {
    def tree as GpxRead init treeGpxRead($text);
    testing.assertEqual($tree, scanGpxRead($text));
    return $tree.doc;
}

/**
 * Assert a document `xml.decode` accepts is still read by the scanner.
 *
 * @param text {string} the document
 * @return {Document} what `readGpx` read, which is the scanner's
 */
func assertScanReadsDecodable(text as string) {
    testing.assertEqual(xml.localName(xml.decode($text)), "gpx");
    def src as bytes init convert.bytesFromString($text, "utf-8");
    testing.assertFalse(gpxTree($src, $text).usable);
    def doc as Document init readGpx($text);
    testing.assertEqual($doc, readGpxScan($src));
    return $doc;
}

func testReadGpxReadsAWellFormedDocumentFromTheTree() {
    def doc as Document init assertTreeReadsAsScan(gpxFixture());
    testing.assertEqual($doc.name, "Innsbruck loop");
    testing.assertEqual($doc.desc, "A & B");
    testing.assertEqual($doc.creator, "Fixture");
    testing.assertEqual(len($doc.waypoints), 1);
    testing.assertEqual($doc.waypoints[0].ele, 574.0);
    testing.assertEqual($doc.routes[0].name, "Plan");
    testing.assertEqual(len($doc.routes[0].points), 2);
    testing.assertEqual($doc.tracks[0].kind, "hiking");
    testing.assertEqual(len($doc.tracks[0].segments), 2);
    testing.assertEqual($doc.tracks[0].segments[0].points[0].at, "2026-09-30T06:01:00Z");
    testing.assertFalse($doc.tracks[0].segments[0].points[1].hasTime);
}

func testReadGpxTreeKeepsTheScannersRules() {
    # GPX 1.0 header on the root, the first of a repeated field, trimming
    def doc as Document init assertTreeReadsAsScan("<gpx version=\"1.0\"><name> A </name>" +
        "<name>B</name><time>t0</time><wpt lat=\" 1 \" lon=\"2\"><name>x</name><name>y</name>" +
        "<ele>3</ele><ele>4</ele><time> </time><desc>d</desc><sym>s</sym></wpt>" +
        "<wpt lat=\"5\" lon=\"6\"><time>t1</time></wpt></gpx>");
    testing.assertEqual($doc.name, "A");
    testing.assertEqual($doc.at, "t0");
    def w as Point init $doc.waypoints[0];
    testing.assertEqual($w.lat, 1.0);
    testing.assertEqual($w.name, "x");
    testing.assertEqual($w.ele, 3.0);
    testing.assertFalse($w.hasTime);
    testing.assertEqual($w.desc, "d");
    testing.assertEqual($w.sym, "s");
    testing.assertFalse($doc.waypoints[1].hasElevation);
    testing.assertEqual($doc.waypoints[1].at, "t1");
    # <metadata> wins over the root's fields; an empty <metadata/> gives none
    $doc = assertTreeReadsAsScan("<gpx><name>root</name><metadata/><metadata><name>m</name>" +
        "</metadata></gpx>");
    testing.assertEqual($doc.name, "");
    # prefixes everywhere, extensions skipped, a BOM, CRLF, CDATA and comments
    $doc = assertTreeReadsAsScan("\uFEFF<?xml version=\"1.0\"?>\r\n<!-- c -->" +
        "<g:gpx xmlns:g=\"urn:g\" xmlns:x=\"urn:x\" creator=\"a&#9;b\">\r\n<g:metadata>" +
        "<g:name><![CDATA[<b>&]]> <!-- n -->z</g:name></g:metadata><g:trk><g:name>T</g:name>" +
        "<g:trkseg><g:trkpt g:lat=\"47\" g:lon=\"11\"><g:ele>5</g:ele><g:extensions>" +
        "<x:ele>9</x:ele></g:extensions></g:trkpt><g:trkpt lat=\"48\" lon=\"12\"></g:trkpt >" +
        "</g:trkseg></g:trk></g:gpx>");
    testing.assertEqual($doc.creator, "a\tb");
    testing.assertEqual($doc.name, "<b>& z");
    def pts as list of Point init trackPoints($doc.tracks[0]);
    testing.assertEqual(len($pts), 2);
    testing.assertEqual($pts[0].ele, 5.0);
    testing.assertEqual($pts[1].lon, 12.0);
    # a field held by some points only reads each point on its own
    $doc = assertTreeReadsAsScan("<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"><ele>3</ele>" +
        "</trkpt><trkpt lat=\"4\" lon=\"5\"/></trkseg></trk></gpx>");
    $pts = trackPoints($doc.tracks[0]);
    testing.assertTrue($pts[0].hasElevation);
    testing.assertFalse($pts[1].hasElevation);
}

func testReadGpxRaisesTheSameErrorFromTheTree() {
    def cases as list of string init [
        "<gpx><wpt lat=\"north\" lon=\"11\"/></gpx>",
        "<gpx><wpt lat=\"1\"/></gpx>",
        "<gpx><rte><rtept lat=\"91\" lon=\"1\"/></rte></gpx>",
        "<gpx><trk><trkseg><trkpt lat=\"1\" lon=\"2\"><ele>high</ele></trkpt></trkseg></trk></gpx>",
        "<gpx><wpt lat=\"1\" lon=\"2\"><ele>2e6</ele></wpt></gpx>",
        "<gpx><wpt lat=\"1e999\" lon=\"2\"/></gpx>",
        "<gpx><g:wpt xmlns:g=\"u\" g:lat=\"1\" g:lon=\"x\"/></gpx>"
    ];
    def wanted as list of string init [
        "geo: <wpt> lat is not a number: \"north\"",
        "geo: <wpt> has no lat and lon attribute pair",
        "geo: latitude 91.0 is outside -90..90",
        "geo: <ele> is not a number: \"high\"",
        "geo: elevation 2e+06 is outside -1000000..1000000 metres",
        "geo: <wpt> lat is not a number: \"1e999\"",
        "geo: <g:wpt> lon is not a number: \"x\""
    ];
    for (def i as int init 0; $i < len($cases); $i = $i + 1) {
        def read as GpxRead init treeGpxRead($cases[$i]);
        testing.assertEqual($read.error, $wanted[$i]);
        testing.assertEqual($read, scanGpxRead($cases[$i]));
    }
}

func testReadGpxFallsBackWhenTheDecodeFails() {
    # an unknown entity: xml.decode raises, the scanner keeps it as written
    def src as bytes init buffer("<gpx><name>10&deg;</name></gpx>");
    testing.assertFalse(gpxTree($src, "<gpx><name>10&deg;</name></gpx>").usable);
    testing.assertEqual(readGpx("<gpx><name>10&deg;</name></gpx>").name, "10&deg;");
    # past the decoder's nesting cap (1000 levels; 64 on jennifer-tiny)
    def deep as string init "<gpx><wpt lat=\"1\" lon=\"2\"/>" + strings.repeat("<a>", 1001) +
        strings.repeat("</a>", 1001) + "</gpx>";
    testing.assertFalse(gpxTree(buffer($deep), $deep).usable);
    testing.assertEqual(len(readGpx($deep).waypoints), 1);
}

func testReadGpxFallsBackPastTheNodeCap() {
    # 2^21 + 1 elements: one more than xml.decode builds on the Go binary
    # (2^18 on jennifer-tiny). The scanner steps over <extensions> in a few
    # native searches.
    def text as string init "<gpx><wpt lat=\"1\" lon=\"2\"><name>A</name></wpt><extensions>" +
        strings.repeat("<x/>", 2097153) + "</extensions></gpx>";
    testing.assertFalse(gpxTree(buffer($text), $text).usable);
    def doc as Document init readGpx($text);
    testing.assertEqual(len($doc.waypoints), 1);
    testing.assertEqual($doc.waypoints[0].name, "A");
}

func testReadGpxFallsBackWhereTheScannerReadsDifferently() {
    # a point holding an element of its own name: the scanner ends the outer
    # point at the inner open tag, drops it as unclosed, and steps over the
    # <extensions> holding the inner one
    def doc as Document init assertScanReadsDecodable("<gpx><trk><trkseg><trkpt lat=\"1\" " +
        "lon=\"2\"><extensions><trkpt lat=\"3\" lon=\"4\"/></extensions></trkpt></trkseg></trk></gpx>");
    testing.assertEqual(len(trackPoints($doc.tracks[0])), 0);
    # a field holding markup: the scanner keeps the child's text
    $doc = assertScanReadsDecodable("<gpx><metadata><name>a<b>c</b>d</name></metadata></gpx>");
    testing.assertEqual($doc.name, "acd");
    # a sign in a character reference: the scanner leaves it standing
    $doc = assertScanReadsDecodable("<gpx><trk><name>&#+65;</name></trk></gpx>");
    testing.assertEqual($doc.tracks[0].name, "&#+65;");
    # a processing instruction inside the root
    $doc = assertScanReadsDecodable("<gpx><?pi x?><name>N</name></gpx>");
    testing.assertEqual($doc.name, "N");
    # a DOCTYPE, and comments the scanner ends early
    assertScanReadsDecodable("<!DOCTYPE gpx><gpx><name>N</name></gpx>");
    assertScanReadsDecodable("<gpx><!-->--><name>N</name></gpx>");
    assertScanReadsDecodable("<gpx><!-- <![CDATA[ --><name>N</name></gpx>");
    # a CDATA section holding a CDATA opener, in a field
    $doc = assertScanReadsDecodable("<gpx><name><![CDATA[a<![CDATA[b]]></name></gpx>");
    testing.assertEqual($doc.name, "ab");
    # a namespace declared between the root and a point
    assertScanReadsDecodable("<gpx><trk xmlns:p=\"urn:p\"><trkseg><trkpt lat=\"1\" lon=\"2\"/>" +
        "</trkseg></trk></gpx>");
    # 101 nested elements of one name: the scanner takes the outer as unclosed,
    # running to the root's end, so the waypoint after it is not a root child
    $doc = assertScanReadsDecodable("<gpx>" + strings.repeat("<a>", 102) +
        strings.repeat("</a>", 102) + "<wpt lat=\"1\" lon=\"2\"/></gpx>");
    testing.assertEqual(len($doc.waypoints), 0);
}

func testTreeMatchesScanChecks() {
    def plain as string init "<?xml version=\"1.0\"?><gpx/>";
    testing.assertTrue(textMatchesScan(buffer($plain), $plain));
    testing.assertFalse(textMatchesScan(buffer("<?a?><?b?><gpx/>"), "<?a?><?b?><gpx/>"));
    testing.assertFalse(textMatchesScan(buffer("<?a <x>?><gpx/>"), "<?a <x>?><gpx/>"));
    testing.assertFalse(textMatchesScan(buffer("<gpx>&#x+41;</gpx>"), "<gpx>&#x+41;</gpx>"));
    testing.assertFalse(commentHoldsCdata(buffer("<!-- x --><gpx><![CDATA[y]]></gpx>")));
    testing.assertTrue(commentHoldsCdata(buffer("<!-- <![CDATA[ --><gpx/>")));
    testing.assertFalse(commentHoldsCdata(buffer("<gpx><![CDATA[ <!-- ]]><!-- x --></gpx>")));
    def root as xml.Value init xml.decode("<gpx><wpt lat=\"1\" lon=\"2\"/><x><wpt/></x></gpx>");
    testing.assertFalse(pointsMatchScan(
        "<gpx><wpt lat=\"1\" lon=\"2\"/><x><wpt/></x></gpx>",
        $root,
        "*:wpt",
        ""));
    testing.assertTrue(pointsMatchScan(
        "<gpx/>",
        xml.decode("<gpx/>"),
        "*:trkpt",
        "*:trk/*:trkseg/"));
    testing.assertFalse(fieldsMatchScan(xml.decode("<m><name>a<b/></name></m>"), ["name"]));
    testing.assertTrue(fieldsMatchScan(xml.decode("<m><desc>a</desc></m>"), ["name", "desc"]));
    testing.assertTrue(declaresNamespace(xml.decode("<trk xmlns=\"u\"/>")));
    testing.assertFalse(declaresNamespace(xml.decode("<trk a=\"xmlns\"/>")));
    testing.assertTrue(allOrNone([], 3));
    testing.assertFalse(allOrNone([xml.element("ele")], 2));
    def tag as Node init rootOpenTag(buffer("<?xml?><!-- <a> --><gpx creator=\"c\"><x/></gpx>"));
    testing.assertEqual($tag.name, "gpx");
    testing.assertEqual($tag.start, 19);
    testing.assertEqual($tag.openEnd, 36);
    testing.assertFalse(isNode(rootOpenTag(buffer("no markup"))));
}

# The GPX inputs of tools/fuzz.j, rebuilt here: fuzz.j imports the deck and
# cannot reach readGpxScan or readGpxTree. Same seed, same fixture, same
# draws in the same order (GPX is the first format fuzz.j mutates), so this is
# the same set of inputs.

/**
 * The document tools/fuzz.j mutates for GPX.
 *
 * @return {string} the fixture, as GPX
 */
func fuzzGpxFixture() {
    def doc as Document init document();
    $doc.name = "Fuzz & co <test>";
    $doc.desc = "Ca\u00f1on";
    $doc.at = "2026-09-30T06:00:00Z";
    $doc.waypoints = [
        named(withElevation(point(47.2692, 11.4041), 574.0), "Start"),
        point(-33.8688, 151.2093)
    ];
    $doc.routes = [route("Plan", [point(47.0, 11.0), point(47.1, 11.1)])];
    $doc.tracks = [
        Track{
            name: "Day 1",
            desc: "",
            kind: "hiking",
            segments: [
                Segment{
                    points: [
                        withTime(withElevation(point(47.2, 11.2), 600.0), "2026-09-30T06:01:00Z"),
                        withElevation(point(47.3, 11.3), 700.0)
                    ]
                },
                Segment{points: [point(47.4, 11.4), point(47.5, 11.5)]}
            ]
        }
    ];
    return writeText($doc, "gpx");
}

/**
 * fuzz.j's `bend`: one character replaced by a random one of ten.
 *
 * @param text {string} the document
 * @param at {int} which character to replace
 * @return {string} the document with one character changed
 */
func fuzzBend(text as string, at as int) {
    def replacements as list of string init ["<", ">", "\"", "&", "/", "x", " ", ";", "9", "-"];
    def pick as string init $replacements[math.randInt(0, len($replacements) - 1)];
    return strings.substring($text, 0, $at) + $pick + strings.substring($text, $at + 1, len($text));
}

/** fuzz.j's `HOSTILE` values. */
def const FUZZ_HOSTILE as list of string init [
    "5",
    "null",
    '"s"',
    '{}',
    "[]",
    "1e300",
    "-1e308",
    "1_0",
    "2.4",
    "&#99999999999999999999;",
    "]]>",
    '{"0": 1, "1": 2}'
];

/**
 * fuzz.j's `swapValue`: the number or JSON array at or after an offset replaced.
 *
 * @param text {string} the document
 * @param from {int} where to start looking
 * @param value {string} what to put there
 * @return {string} the document with one value swapped
 */
func fuzzSwap(text as string, from as int, value as string) {
    def chars as list of string init strings.chars($text);
    def at as int init $from;
    while ($at < len($chars) and
        not ($chars[$at] == "[" or strings.contains("0123456789", $chars[$at]))) {
        $at = $at + 1;
    }
    if ($at >= len($chars)) {
        return $text;
    }
    def end as int init $at + 1;
    if ($chars[$at] == "[") {
        while ($end < len($chars) and $chars[$end] != "]") {
            $end = $end + 1;
        }
        $end = math.min($end + 1, len($chars));
    } else {
        while ($end < len($chars) and strings.contains("0123456789.-eE", $chars[$end])) {
            $end = $end + 1;
        }
    }
    return strings.substring($text, 0, $at) + $value + strings.substring($text, $end, len($text));
}

/**
 * Every GPX input tools/fuzz.j drives through the reader.
 *
 * @return {list of string} the inputs, in fuzz.j's order
 */
func fuzzGpxInputs() {
    math.randSeed(20260930);
    def whole as string init fuzzGpxFixture();
    def out as list of string init [$whole];
    for (def at as int init 0; $at < len($whole); $at = $at + 7) {
        $out[] = strings.substring($whole, 0, $at);
    }
    for (def at as int init 0; $at < len($whole); $at = $at + 11) {
        $out[] = fuzzBend($whole, $at);
    }
    for (def n as int init 0; $n < 60; $n = $n + 1) {
        def from as int init math.randInt(0, len($whole) - 1);
        def size as int init math.randInt(1, 40);
        def end as int init math.min($from + $size, len($whole));
        $out[] = strings.substring($whole, 0, $from) + strings.substring($whole, $end, len($whole));
    }
    for (def n as int init 0; $n < 120; $n = $n + 1) {
        def value as string init FUZZ_HOSTILE[math.randInt(0, len(FUZZ_HOSTILE) - 1)];
        $out[] = fuzzSwap($whole, math.randInt(0, len($whole) - 1), $value);
    }
    for (def n as int init 0; $n < 40; $n = $n + 1) {
        def size as int init math.randInt(0, 200);
        def noise as string init "";
        for (def i as int init 0; $i < $size; $i = $i + 1) {
            $noise = $noise + fuzzBend(" ", 0);
        }
        $out[] = $noise;
    }
    return $out;
}

func testReadGpxTreeMatchesScanOnEveryFuzzInput() {
    def inputs as list of string init fuzzGpxInputs();
    # the fixture, a truncation per 7 characters, a bend per 11, 60 splices,
    # 120 swaps, 40 noise runs
    def size as int init len(fuzzGpxFixture());
    testing.assertEqual(len($inputs), 1 + ($size + 6) // 7 + ($size + 10) // 11 + 60 + 120 + 40);
    def compared as int init 0;
    for (def text in $inputs) {
        if (gpxTree(convert.bytesFromString($text, "utf-8"), $text).usable) {
            testing.assertEqual(treeGpxRead($text), scanGpxRead($text));
            $compared = $compared + 1;
        }
    }
    # the whole fixture, the valid truncation-free swaps and some bends decode
    testing.assertTrue($compared > 50);
}

func testDecodeNodesCountsElementsAttributesAndText() {
    # elements gpx, trk (2); attribute a (1); '>' 4 less '><' 2 = 2 text runs
    # ("x" and the end of input): 5. xml.decode builds 4 (gpx, a, trk, "x").
    testing.assertEqual(decodeNodes("<gpx a=\"1\"><trk>x</trk></gpx>"), 5);
}

func testDecodeFitsSkipsTheDecodeOnlyOnTinyPastItsCap() {
    # 262,144 empty elements inside <gpx>: 262,145 elements, '>' 262,146 less
    # '><' 262,145 = 1 text run, 262,146 in all - two past the cap.
    def big as string init "<gpx>" + strings.repeat("<p/>", 262144) + "</gpx>";
    testing.assertEqual(decodeNodes($big), 262146);
    testing.assertFalse(decodeFits($big, "tinygo"));
    testing.assertTrue(decodeFits($big, "go"));
    testing.assertTrue(decodeFits("<gpx><p/></gpx>", "tinygo"));
}
