# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

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
    # the header and the track names go through the scanner, not xml.decode, so
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
    testing.assertEqual(indent(0), "");
    testing.assertEqual(indent(3), "      ");
}

func testGpxCreator() {
    def doc as Document init document();
    testing.assertEqual(gpxCreator($doc), GPX_CREATOR);
    $doc.creator = "A & B";
    testing.assertEqual(gpxCreator($doc), "A &amp; B");
}
