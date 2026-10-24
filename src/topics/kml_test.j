# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - white-box tests for the kml topic.
# Spliced into geo_test.j via include - run with:
#   jennifer test src/geo_test.j

/** A KML 2.2 document with a prefixed root, a folder, a point and a line. */
func kmlFixture() {
    def parts as list of string init [];
    $parts[] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    $parts[] = "<kml:kml xmlns:kml=\"http://www.opengis.net/kml/2.2\">\n";
    $parts[] = "  <kml:Document><kml:name>Tyrol</kml:name>\n";
    $parts[] = "  <kml:description>Alpine</kml:description>\n";
    $parts[] = "  <kml:Placemark><kml:name>Nordkette</kml:name>\n";
    $parts[] = "    <kml:Point><kml:coordinates>11.3889,47.3122,2334";
    $parts[] = "</kml:coordinates></kml:Point></kml:Placemark>\n";
    $parts[] = "  <kml:Folder><kml:name>Routes</kml:name>\n";
    $parts[] = "    <kml:Placemark><kml:name>Ridge</kml:name>\n";
    $parts[] = "      <kml:LineString><kml:coordinates>\n";
    $parts[] = "        11.3889,47.3122,2334\n        11.3950,47.3140,2410\n";
    $parts[] = "      </kml:coordinates></kml:LineString></kml:Placemark>\n";
    $parts[] = "  </kml:Folder>\n  </kml:Document>\n</kml:kml>\n";
    return strings.join($parts, "");
}

func testReadKmlReadsTheDocumentHeader() {
    def doc as Document init readKml(kmlFixture());
    testing.assertEqual($doc.name, "Tyrol");
    testing.assertEqual($doc.desc, "Alpine");
}

func testReadKmlReadsAPointAsAWaypoint() {
    def doc as Document init readKml(kmlFixture());
    testing.assertEqual(len($doc.waypoints), 1);
    def w as Point init $doc.waypoints[0];
    testing.assertEqual($w.name, "Nordkette");
    # KML writes lon,lat - the opposite of GPX - and this is where that is fixed
    testing.assertEqual($w.lat, 47.3122);
    testing.assertEqual($w.lon, 11.3889);
    testing.assertEqual($w.ele, 2334.0);
    testing.assertTrue($w.hasElevation);
}

func testReadKmlDescendsIntoAFolder() {
    def doc as Document init readKml(kmlFixture());
    testing.assertEqual(len($doc.tracks), 1);
    testing.assertEqual($doc.tracks[0].name, "Ridge");
    testing.assertEqual(len(trackPoints($doc.tracks[0])), 2);
}

func testReadKmlReadsAnUnprefixedDocument() {
    def text as string init "<kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document>" +
        "<Placemark><name>P</name><Point><coordinates>11,47</coordinates>" +
        "</Point></Placemark></Document></kml>";
    def doc as Document init readKml($text);
    testing.assertEqual(len($doc.waypoints), 1);
    testing.assertEqual($doc.waypoints[0].lat, 47.0);
}

func testReadKmlReadsAPolygonAsItsOuterRing() {
    def text as string init "<kml><Document><Placemark><name>Fence</name><Polygon>" +
        "<outerBoundaryIs><LinearRing><coordinates>" +
        "0,0 1,0 1,1 0,1 0,0</coordinates></LinearRing></outerBoundaryIs>" +
        "</Polygon></Placemark></Document></kml>";
    def doc as Document init readKml($text);
    testing.assertEqual(len($doc.tracks), 1);
    testing.assertEqual(len(trackPoints($doc.tracks[0])), 5);
}

func testReadKmlUnwrapsAMultiGeometry() {
    def text as string init "<kml><Document><Placemark><name>Both</name>" +
        "<MultiGeometry><Point><coordinates>11,47</coordinates></Point>" +
        "<LineString><coordinates>11,47 12,48</coordinates></LineString>" +
        "</MultiGeometry></Placemark></Document></kml>";
    def doc as Document init readKml($text);
    testing.assertEqual(len($doc.waypoints), 1);
    testing.assertEqual(len($doc.tracks), 1);
}

func testReadKmlWithNoDocumentElement() {
    # a Placemark straight under <kml> is legal and turns up in the wild
    def text as string init "<kml><Placemark><Point><coordinates>11,47" +
        "</coordinates></Point></Placemark></kml>";
    def doc as Document init readKml($text);
    testing.assertEqual(len($doc.waypoints), 1);
}

func testReadKmlKeepsTheStyleUrlAsTheSymbol() {
    def text as string init "<kml><Document><Placemark><styleUrl>#pin</styleUrl>" +
        "<Point><coordinates>11,47</coordinates></Point></Placemark></Document></kml>";
    testing.assertEqual(readKml($text).waypoints[0].sym, "#pin");
}

func failOnNonKmlRoot() {
    readKml("<gpx><wpt lat=\"1\" lon=\"1\" /></gpx>");
}

func failOnCoordinatesWithNoComma() {
    def text as string init "<kml><Placemark><Point><coordinates>11 47" +
        "</coordinates></Point></Placemark></kml>";
    readKml($text);
}

func failOnCoordinatesOutsideTheWorld() {
    def text as string init "<kml><Placemark><Point><coordinates>11,91" +
        "</coordinates></Point></Placemark></kml>";
    readKml($text);
}

func failOnOverNestedKml() {
    # 10,000 nested folders is a 170 KB file that would otherwise take half an
    # hour to walk: the cost of descending is quadratic in the depth
    def deep as string init strings.repeat("<Folder>", MAX_NESTING + 2);
    def shut as string init strings.repeat("</Folder>", MAX_NESTING + 2);
    readKml("<kml><Document>" + $deep + $shut + "</Document></kml>");
}

func testReadKmlRefusesPathologicalNesting() {
    testing.assertThrows("failOnOverNestedKml", ERROR_KIND);
}

func testReadKmlAcceptsNestingUpToTheCeiling() {
    def deep as string init strings.repeat("<Folder>", 20);
    def shut as string init strings.repeat("</Folder>", 20);
    def mark as string init "<Placemark><Point><coordinates>11,47</coordinates>" +
        "</Point></Placemark>";
    def doc as Document init readKml("<kml><Document>" + $deep + $mark + $shut + "</Document></kml>");
    testing.assertEqual(len($doc.waypoints), 1);
}

func testReadKmlRejectsWhatItCannotRead() {
    testing.assertThrows("failOnNonKmlRoot", ERROR_KIND);
    testing.assertThrows("failOnCoordinatesWithNoComma", ERROR_KIND);
    testing.assertThrows("failOnCoordinatesOutsideTheWorld", ERROR_KIND);
}

func testParseCoordinatesHandlesWhitespaceAndElevation() {
    def text as string init "\n  11.3889,47.3122,2334\n  11.3950,47.3140\n";
    def points as list of Point init parseCoordinates($text);
    testing.assertEqual(len($points), 2);
    testing.assertEqual($points[0].ele, 2334.0);
    testing.assertTrue($points[0].hasElevation);
    testing.assertFalse($points[1].hasElevation);
}

func testParseCoordinatesOfNothing() {
    testing.assertEqual(len(parseCoordinates("   \n  ")), 0);
    testing.assertEqual(len(parseCoordinates("")), 0);
}

func testWhitespaceFields() {
    testing.assertEqual(whitespaceFields(" a  b\n\tc "), ["a", "b", "c"]);
    testing.assertEqual(len(whitespaceFields("   ")), 0);
}

func testWriteKmlStructure() {
    def doc as Document init document();
    $doc.name = "Tyrol";
    $doc.waypoints = [named(point(47.3122, 11.3889), "Nordkette")];
    def text as string init writeKml($doc);
    testing.assertTrue(strings.startsWith($text, "<?xml version=\"1.0\""));
    testing.assertContains($text, KML_NAMESPACE);
    testing.assertContains($text, "<Placemark>");
    # longitude first, as KML wants
    testing.assertContains($text, "<coordinates>11.3889,47.3122</coordinates>");
    testing.assertTrue(strings.endsWith($text, "</kml>\n"));
}

func testWriteKmlUsesAMultiGeometryForASegmentedTrack() {
    def t as Track init Track{
        name: "Gapped",
        desc: "",
        kind: "",
        segments: [
            Segment{points: [point(0.0, 0.0), point(0.0, 1.0)]},
            Segment{points: [point(0.0, 5.0), point(0.0, 6.0)]}
        ]
    };
    def doc as Document init document();
    $doc.tracks = [$t];
    def text as string init writeKml($doc);
    testing.assertContains($text, "<MultiGeometry>");
    # the breaks survive rather than being joined into one line
    def back as Document init readKml($text);
    testing.assertEqual(len($back.tracks), 2);
}

func testWriteKmlSkipsAPathWithOnePoint() {
    def doc as Document init document();
    $doc.tracks = [track("One", [point(0.0, 0.0)])];
    def text as string init writeKml($doc);
    testing.assertEqual(strings.indexOf($text, "LineString"), -1);
}

func testWriteKmlWritesARouteAsALine() {
    def doc as Document init document();
    $doc.routes = [route("Plan", [point(0.0, 0.0), point(0.0, 1.0)])];
    testing.assertContains(writeKml($doc), "<LineString>");
}

func testCoordinateText() {
    testing.assertEqual(coordinateText(point(47.3122, 11.3889)), "11.3889,47.3122");
    testing.assertEqual(
        coordinateText(withElevation(point(47.3122, 11.3889), 2334.0)),
        "11.3889,47.3122,2334");
}

func testKmlRoundTripKeepsWhatKmlCanHold() {
    def before as Document init readKml(kmlFixture());
    def after as Document init readKml(writeKml($before));
    testing.assertEqual($after.name, $before.name);
    testing.assertEqual($after.desc, $before.desc);
    testing.assertEqual(len($after.waypoints), len($before.waypoints));
    testing.assertEqual($after.waypoints[0].name, "Nordkette");
    testing.assertEqual($after.waypoints[0].lat, 47.3122);
    testing.assertEqual(len($after.tracks), 1);
    testing.assertEqual($after.tracks[0].name, "Ridge");
}

func testKmzRoundTrip() {
    def before as Document init readKml(kmlFixture());
    def archived as bytes init writeKmz($before);
    def after as Document init readKmz($archived);
    testing.assertEqual($after.name, "Tyrol");
    testing.assertEqual(len($after.waypoints), 1);
    testing.assertEqual(len($after.tracks), 1);
}

func testWriteKmzHoldsOneDocKml() {
    def entries as list of archive.Entry init archive.unpack(writeKmz(document()), "zip");
    testing.assertEqual(len($entries), 1);
    testing.assertEqual($entries[0].name, KMZ_ENTRY);
}

func testReadKmzFindsTheKmlPastOtherEntries() {
    def icon as archive.Entry init archive.Entry{
        name: "files/icon.png",
        data: convert.bytesFromString("not really a png", "utf-8"),
        mode: 0o644,
        mtime: 0
    };
    def doc as archive.Entry init archive.Entry{
        name: "doc.kml",
        data: convert.bytesFromString(kmlFixture(), "utf-8"),
        mode: 0o644,
        mtime: 0
    };
    def blob as bytes init archive.pack([$icon, $doc], "zip");
    testing.assertEqual(readKmz($blob).name, "Tyrol");
}

func failOnKmzThatIsNotAZip() {
    readKmz(convert.bytesFromString("just text", "utf-8"));
}

func failOnKmzWithNoKml() {
    def only as archive.Entry init archive.Entry{
        name: "readme.txt",
        data: convert.bytesFromString("nothing here", "utf-8"),
        mode: 0o644,
        mtime: 0
    };
    readKmz(archive.pack([$only], "zip"));
}

func testReadKmzRejectsWhatIsNotAKmz() {
    testing.assertThrows("failOnKmzThatIsNotAZip", ERROR_KIND);
    testing.assertThrows("failOnKmzWithNoKml", ERROR_KIND);
}
