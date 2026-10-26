# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# geo - white-box tests for the file topic.
# Spliced into geo_test.j via include - run with:
#   jennifer test src/geo_test.j
#
# The one overlay that touches the filesystem: every other topic is pure
# computation. Each test makes its own temporary directory and removes it.

/** A document with one named waypoint and one two-point track. */
func fileFixture() {
    def doc as Document init document();
    $doc.name = "Tyrol";
    $doc.creator = "file_test";
    $doc.waypoints = [named(withElevation(point(47.3122, 11.3889), 2334.0), "Nordkette")];
    $doc.tracks = [track("Ridge", [point(47.3122, 11.3889), point(47.3140, 11.3950)])];
    return $doc;
}

func testFormatOfEveryExtension() {
    testing.assertEqual(formatOf("hike.gpx"), "gpx");
    testing.assertEqual(formatOf("places.kml"), "kml");
    testing.assertEqual(formatOf("places.kmz"), "kmz");
    testing.assertEqual(formatOf("places.geojson"), "geojson");
    testing.assertEqual(formatOf("places.json"), "geojson");
    testing.assertEqual(formatOf("features.gml"), "gml");
    testing.assertEqual(formatOf("features.xml"), "gml");
}

func testFormatOfIgnoresCaseAndDirectories() {
    testing.assertEqual(formatOf("HIKE.GPX"), "gpx");
    testing.assertEqual(formatOf("/tmp/a.b/hike.Gpx"), "gpx");
}

func testFormatOfWhatItDoesNotKnow() {
    testing.assertEqual(formatOf("notes.txt"), FORMAT_UNKNOWN);
    testing.assertEqual(formatOf("hike"), FORMAT_UNKNOWN);
    testing.assertEqual(formatOf(""), FORMAT_UNKNOWN);
}

func testWriteTextAndReadTextForEveryFormat() {
    def before as Document init fileFixture();
    for (def format in ["gpx", "kml", "geojson", "gml"]) {
        def text as string init writeText($before, $format);
        def after as Document init readText($text, $format);
        testing.assertEqual(len($after.waypoints), 1);
        testing.assertEqual($after.waypoints[0].name, "Nordkette");
        testing.assertEqual(len($after.tracks), 1);
        testing.assertEqual(len(trackPoints($after.tracks[0])), 2);
    }
}

func failOnWriteTextOfAnUnknownFormat() {
    writeText(document(), "shapefile");
}

func failOnReadTextOfAnUnknownFormat() {
    readText("<gpx />", "shapefile");
}

func testTextCodecsRejectAFormatTheyDoNotKnow() {
    testing.assertThrows("failOnWriteTextOfAnUnknownFormat", ERROR_KIND);
    testing.assertThrows("failOnReadTextOfAnUnknownFormat", ERROR_KIND);
}

func testSaveAndOpenRoundTripEveryFormat() {
    def dir as string init fs.makeTempDir();
    defer fs.removeAll($dir);
    def before as Document init fileFixture();
    for (def name in ["a.gpx", "a.kml", "a.kmz", "a.geojson", "a.gml"]) {
        def target as string init path.join($dir, $name);
        save($before, $target);
        testing.assertTrue(fs.isFile($target));
        def after as Document init open($target);
        testing.assertEqual(len($after.waypoints), 1);
        testing.assertEqual($after.waypoints[0].name, "Nordkette");
        testing.assertEqual(len(trackPoints($after.tracks[0])), 2);
    }
}

func testOpenGpxAndSaveGpx() {
    def dir as string init fs.makeTempDir();
    defer fs.removeAll($dir);
    def target as string init path.join($dir, "hike.gpx");
    saveGpx(fileFixture(), $target);
    def back as Document init openGpx($target);
    testing.assertEqual($back.name, "Tyrol");
    testing.assertEqual($back.creator, "file_test");
    testing.assertEqual($back.waypoints[0].ele, 2334.0);
}

func testOpenKmlAndSaveKml() {
    def dir as string init fs.makeTempDir();
    defer fs.removeAll($dir);
    def target as string init path.join($dir, "places.kml");
    saveKml(fileFixture(), $target);
    def back as Document init openKml($target);
    testing.assertEqual($back.name, "Tyrol");
    testing.assertEqual(len($back.waypoints), 1);
}

func testOpenKmzAndSaveKmz() {
    def dir as string init fs.makeTempDir();
    defer fs.removeAll($dir);
    def target as string init path.join($dir, "places.kmz");
    saveKmz(fileFixture(), $target);
    # a KMZ is a zip, so the bytes on disk are not XML
    testing.assertTrue(fs.isFile($target));
    def back as Document init openKmz($target);
    testing.assertEqual($back.name, "Tyrol");
    testing.assertEqual(len($back.tracks), 1);
}

func testConvertFileBetweenFormats() {
    def dir as string init fs.makeTempDir();
    defer fs.removeAll($dir);
    def source as string init path.join($dir, "hike.gpx");
    saveGpx(fileFixture(), $source);
    def target as string init path.join($dir, "hike.geojson");
    def read as Document init convertFile($source, $target);
    testing.assertEqual($read.name, "Tyrol");
    testing.assertTrue(fs.isFile($target));
    def landed as Document init open($target);
    testing.assertEqual(len($landed.waypoints), 1);
    testing.assertEqual($landed.waypoints[0].name, "Nordkette");
}

func testConvertFileThroughEveryPair() {
    def dir as string init fs.makeTempDir();
    defer fs.removeAll($dir);
    def start as string init path.join($dir, "start.gpx");
    saveGpx(fileFixture(), $start);
    # every format reads what every other wrote, which is the deck's whole point
    def chain as list of string init [
        "one.kml",
        "two.geojson",
        "three.gml",
        "four.kmz",
        "five.gpx"
    ];
    def from as string init $start;
    for (def name in $chain) {
        def target as string init path.join($dir, $name);
        convertFile($from, $target);
        $from = $target;
    }
    def final as Document init open($from);
    testing.assertEqual(len($final.waypoints), 1);
    testing.assertEqual($final.waypoints[0].name, "Nordkette");
    testing.assertEqual($final.waypoints[0].lat, 47.3122);
    testing.assertEqual(len(trackPoints($final.tracks[0])), 2);
}

func failOnOpenOfAnUnknownExtension() {
    open("notes.txt");
}

func failOnSaveToAnUnknownExtension() {
    save(document(), "notes.txt");
}

func testFileDispatchRejectsAnExtensionItDoesNotKnow() {
    testing.assertThrows("failOnOpenOfAnUnknownExtension", ERROR_KIND);
    testing.assertThrows("failOnSaveToAnUnknownExtension", ERROR_KIND);
}

func testVersionIsASemverString() {
    testing.assertTrue(len(VERSION) > 0);
    testing.assertTrue(strings.indexOf(VERSION, ".") > 0);
}

/** A path no test run can have created: a file in a directory that is not there. */
def const NOWHERE as string init "no-such-directory-for-geo/missing";

func failOnOpeningAMissingFile() {
    open(NOWHERE + ".gpx");
}

func failOnOpeningAMissingKmz() {
    openKmz(NOWHERE + ".kmz");
}

func failOnSavingIntoAMissingDirectory() {
    save(fileFixture(), NOWHERE + ".geojson");
}

func failOnSavingAKmzIntoAMissingDirectory() {
    saveKmz(fileFixture(), NOWHERE + ".kmz");
}

func testFileFailuresAreThisDecksErrors() {
    # fs raises kind "runtime"; every failure of this deck is kind "geo"
    testing.assertThrows("failOnOpeningAMissingFile", ERROR_KIND);
    testing.assertThrows("failOnOpeningAMissingKmz", ERROR_KIND);
    testing.assertThrows("failOnSavingIntoAMissingDirectory", ERROR_KIND);
    testing.assertThrows("failOnSavingAKmzIntoAMissingDirectory", ERROR_KIND);
}

func testOpenReadsADeclaredLatin1File() {
    def dir as string init fs.makeTempDir();
    defer fs.removeAll($dir);
    def head as string init "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>" +
        "<gpx><wpt lat=\"1\" lon=\"2\"><name>Ca";
    def parts as list of bytes init [
        convert.bytesFromString($head, "utf-8"),
        encoding.encode("\u00f1", "iso-8859-1"),
        convert.bytesFromString("on</name></wpt></gpx>", "utf-8")
    ];
    # an older Garmin export: Latin-1, and saying so in its declaration
    def target as string init path.join($dir, "old.gpx");
    fs.writeBytes($target, binary.join($parts));
    testing.assertEqual(open($target).waypoints[0].name, "Ca\u00f1on");
    testing.assertEqual(openGpx($target).waypoints[0].name, "Ca\u00f1on");
}

func testReadKmzPrefersDocKml() {
    def legend as string init "<kml><Document><name>legend</name></Document></kml>";
    def entries as list of archive.Entry init [
        archive.Entry{
            name: "files/legend.kml",
            data: convert.bytesFromString($legend, "utf-8"),
            mode: 420,
            mtime: 0
        },
        archive.Entry{
            name: KMZ_ENTRY,
            data: convert.bytesFromString(writeKml(fileFixture()), "utf-8"),
            mode: 420,
            mtime: 0
        }
    ];
    def doc as Document init readKmz(archive.pack($entries, "zip"));
    testing.assertEqual($doc.name, "Tyrol");
}

func testKmzEntryIndexFallsBackToARootKmlThenAnyKml() {
    def nothing as bytes init convert.bytesFromString("", "utf-8");
    def nested as archive.Entry init archive.Entry{
        name: "a/x.kml",
        data: $nothing,
        mode: 420,
        mtime: 0
    };
    def atRoot as archive.Entry init archive.Entry{
        name: "places.KML",
        data: $nothing,
        mode: 420,
        mtime: 0
    };
    def image as archive.Entry init archive.Entry{
        name: "icon.png",
        data: $nothing,
        mode: 420,
        mtime: 0
    };
    testing.assertEqual(kmzEntryIndex([$nested, $atRoot]), 1);
    testing.assertEqual(kmzEntryIndex([$image, $nested]), 1);
    testing.assertEqual(kmzEntryIndex([$image]), -1);
}
