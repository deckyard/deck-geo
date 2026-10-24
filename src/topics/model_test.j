# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - white-box tests for the model topic.
# Spliced into geo_test.j via include - run with:
#   jennifer test src/geo_test.j

/** Innsbruck, the fixture every overlay here builds from. */
func innsbruck() {
    return point(47.2692, 11.4041);
}

/** Vienna, 385 km east-north-east of Innsbruck. */
func vienna() {
    return point(48.2082, 16.3738);
}

/** A three-point track with elevations and timestamps one minute apart. */
func sampleTrack() {
    def a as Point init withTime(withElevation(innsbruck(), 574.0), "2026-09-30T06:00:00Z");
    def b as Point init withTime(
        withElevation(point(47.2792, 11.4141), 674.0),
        "2026-09-30T06:01:00Z");
    def c as Point init withTime(
        withElevation(point(47.2892, 11.4241), 644.0),
        "2026-09-30T06:02:00Z");
    return track("Day 1", [$a, $b, $c]);
}

func testPointStartsWithNothingStated() {
    def p as Point init innsbruck();
    testing.assertEqual($p.lat, 47.2692);
    testing.assertEqual($p.lon, 11.4041);
    testing.assertFalse($p.hasElevation);
    testing.assertFalse($p.hasTime);
    testing.assertEqual($p.name, "");
    testing.assertEqual($p.ele, 0.0);
}

func failOnImpossibleLatitude() {
    point(91.0, 0.0);
}

func testPointRejectsAnImpossibleCoordinate() {
    testing.assertThrows("failOnImpossibleLatitude", ERROR_KIND);
}

func testNamedAndWithersLeaveTheArgumentAlone() {
    def bare as Point init innsbruck();
    def full as Point init withTime(
        withElevation(named($bare, "Start"), 574.0),
        "2026-09-30T06:00:00Z");
    testing.assertEqual($full.name, "Start");
    testing.assertEqual($full.ele, 574.0);
    testing.assertTrue($full.hasElevation);
    testing.assertEqual($full.at, "2026-09-30T06:00:00Z");
    testing.assertTrue($full.hasTime);
    # value semantics: the point handed in is untouched
    testing.assertEqual($bare.name, "");
    testing.assertFalse($bare.hasElevation);
    testing.assertFalse($bare.hasTime);
}

func testHasElevationTellsSeaLevelFromNotStated() {
    def stated as Point init withElevation(innsbruck(), 0.0);
    testing.assertTrue($stated.hasElevation);
    testing.assertEqual($stated.ele, 0.0);
    testing.assertFalse(innsbruck().hasElevation);
}

func testDocumentStartsEmpty() {
    def doc as Document init document();
    testing.assertEqual(len($doc.waypoints), 0);
    testing.assertEqual(len($doc.routes), 0);
    testing.assertEqual(len($doc.tracks), 0);
    testing.assertEqual($doc.name, "");
}

func testTrackHoldsOneSegment() {
    def t as Track init sampleTrack();
    testing.assertEqual($t.name, "Day 1");
    testing.assertEqual(len($t.segments), 1);
    testing.assertEqual(len($t.segments[0].points), 3);
}

func testRouteHoldsItsPoints() {
    def r as Route init route("Plan", [innsbruck(), vienna()]);
    testing.assertEqual($r.name, "Plan");
    testing.assertEqual(len($r.points), 2);
    testing.assertEqual($r.desc, "");
}

func testTrackPointsRunsTheSegmentsTogether() {
    def t as Track init Track{
        name: "Two",
        desc: "",
        kind: "",
        segments: [Segment{points: [innsbruck()]}, Segment{points: [vienna()]}]
    };
    def all as list of Point init trackPoints($t);
    testing.assertEqual(len($all), 2);
    testing.assertEqual($all[0].lat, 47.2692);
    testing.assertEqual($all[1].lat, 48.2082);
}

func testDocumentPointsCoversAllThreeHolders() {
    def doc as Document init document();
    $doc.waypoints = [named(innsbruck(), "W")];
    $doc.routes = [route("R", [vienna()])];
    $doc.tracks = [sampleTrack()];
    def all as list of Point init documentPoints($doc);
    # one waypoint, one route point, three track points
    testing.assertEqual(len($all), 5);
    testing.assertEqual($all[0].name, "W");
}

func testDescribeNamesWhatIsThere() {
    def doc as Document init document();
    testing.assertEqual(describe($doc), "empty");
    $doc.name = "Innsbruck loop";
    $doc.waypoints = [innsbruck()];
    $doc.tracks = [sampleTrack()];
    testing.assertEqual(describe($doc), "Innsbruck loop: 1 waypoint, 1 track, 4 points");
}

func testDescribePluralises() {
    def doc as Document init document();
    $doc.waypoints = [innsbruck(), vienna()];
    testing.assertEqual(describe($doc), "2 waypoints, 2 points");
}

func testCountLabel() {
    testing.assertEqual(countLabel(0, "track", "tracks"), "");
    testing.assertEqual(countLabel(1, "track", "tracks"), "1 track");
    testing.assertEqual(countLabel(7, "track", "tracks"), "7 tracks");
}

func failOnAnUnboundedElevation() {
    withElevation(point(0.0, 0.0), 1e308);
}

func testWithElevationRejectsAnUnboundedHeight() {
    # 1e308 and -1e308 overflowed statsOf subtracting them
    testing.assertThrows("failOnAnUnboundedElevation", ERROR_KIND);
    testing.assertEqual(withElevation(point(0.0, 0.0), -11000.0).ele, -11000.0);
}
