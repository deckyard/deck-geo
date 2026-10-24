# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - white-box tests for the geodesy topic.
# Spliced into geo_test.j via include - run with:
#   jennifer test src/geo_test.j

/** How close a computed distance must be, in metres, to count as right. */
func closeEnough(actual as float, expected as float, slack as float) {
    testing.assertTrue(math.abs($actual - $expected) <= $slack);
}

func testToRadiansAndBack() {
    testing.assertEqual(toRadians(180.0), math.PI);
    testing.assertEqual(toDegrees(math.PI), 180.0);
    testing.assertEqual(toRadians(0.0), 0.0);
    closeEnough(toDegrees(toRadians(47.2692)), 47.2692, 0.0000001);
}

func testHaversineAgainstAKnownDistance() {
    # Innsbruck to Vienna, 385.9 km by great circle
    closeEnough(haversine(47.2692, 11.4041, 48.2082, 16.3738), 385943.7, 1.0);
}

func testHaversineOfOneDegreeOfLatitude() {
    # a degree of latitude is a sixtieth of the meridian: 111.2 km
    closeEnough(haversine(0.0, 0.0, 1.0, 0.0), 111195.0, 5.0);
}

func testHaversineIsSymmetricAndZeroOnItself() {
    def there as float init haversine(47.2692, 11.4041, 48.2082, 16.3738);
    def back as float init haversine(48.2082, 16.3738, 47.2692, 11.4041);
    testing.assertEqual($there, $back);
    testing.assertEqual(haversine(47.2692, 11.4041, 47.2692, 11.4041), 0.0);
}

func testHaversineSurvivesTwoPointsAlmostTheSame() {
    # the case that makes clampUnit load-bearing: h rounds past 1.0 and
    # math.sqrt of a negative raises rather than returning a NaN
    def tiny as float init haversine(47.2692, 11.4041, 47.26920001, 11.40410001);
    testing.assertTrue($tiny >= 0.0);
    testing.assertTrue($tiny < 0.1);
}

func testHaversineAcrossTheAntipodes() {
    def half as float init math.PI * EARTH_RADIUS;
    closeEnough(haversine(0.0, 0.0, 0.0, 180.0), $half, 1.0);
    closeEnough(haversine(-90.0, 0.0, 90.0, 0.0), $half, 1.0);
}

func testDistanceIsHaversineOverPoints() {
    def a as Point init point(47.2692, 11.4041);
    def b as Point init point(48.2082, 16.3738);
    testing.assertEqual(distance($a, $b), haversine(47.2692, 11.4041, 48.2082, 16.3738));
}

func testBearingDueNorthAndSouth() {
    testing.assertEqual(bearing(point(0.0, 0.0), point(1.0, 0.0)), 0.0);
    testing.assertEqual(bearing(point(1.0, 0.0), point(0.0, 0.0)), 180.0);
}

func testBearingDueEastAndWestOnTheEquator() {
    closeEnough(bearing(point(0.0, 0.0), point(0.0, 1.0)), 90.0, 0.0001);
    closeEnough(bearing(point(0.0, 1.0), point(0.0, 0.0)), 270.0, 0.0001);
}

func testBearingIsAlwaysInRange() {
    def here as Point init point(47.2692, 11.4041);
    for (def lon in [-179.0, -90.0, 0.0, 11.0, 90.0, 179.0]) {
        def to2 as float init bearing($here, point(0.0, $lon));
        testing.assertTrue($to2 >= 0.0);
        testing.assertTrue($to2 < 360.0);
    }
}

func testBearingToItselfIsZero() {
    def here as Point init point(47.2692, 11.4041);
    testing.assertEqual(bearing($here, $here), 0.0);
}

func testFinalBearingDiffersFromTheInitialOne() {
    def a as Point init point(47.2692, 11.4041);
    def b as Point init point(48.2082, 16.3738);
    # on a great circle running east the heading swings clockwise
    testing.assertTrue(finalBearing($a, $b) > bearing($a, $b));
    closeEnough(finalBearing(point(0.0, 0.0), point(0.0, 1.0)), 90.0, 0.0001);
}

func testDestinationWalksTheDistanceAsked() {
    def start as Point init point(47.2692, 11.4041);
    def north as Point init destination($start, 0.0, 1000.0);
    closeEnough(distance($start, $north), 1000.0, 0.5);
    testing.assertTrue($north.lat > $start.lat);
    closeEnough($north.lon, $start.lon, 0.0000001);
}

func testDestinationAndBearingAreInverses() {
    def start as Point init point(47.2692, 11.4041);
    for (def heading in [0.0, 45.0, 137.0, 270.0, 359.0]) {
        def there as Point init destination($start, $heading, 5000.0);
        closeEnough(bearing($start, $there), $heading, 0.001);
        closeEnough(distance($start, $there), 5000.0, 0.5);
    }
}

func testDestinationWrapsPastTheAntimeridian() {
    def near as Point init point(0.0, 179.9);
    def over as Point init destination($near, 90.0, 50000.0);
    # it has crossed into negative longitude rather than reporting 180.3
    testing.assertTrue($over.lon < 0.0);
    testing.assertTrue($over.lon >= -180.0);
    closeEnough(distance($near, $over), 50000.0, 1.0);
}

func testMidpointIsHalfWay() {
    def a as Point init point(0.0, 0.0);
    def b as Point init point(0.0, 10.0);
    def middle as Point init midpoint($a, $b);
    closeEnough($middle.lon, 5.0, 0.0001);
    closeEnough($middle.lat, 0.0, 0.0001);
    closeEnough(distance($a, $middle), distance($middle, $b), 0.5);
}

func testMidpointOfOnePointIsThatPoint() {
    def here as Point init point(47.2692, 11.4041);
    def same as Point init midpoint($here, $here);
    closeEnough($same.lat, 47.2692, 0.0000001);
    closeEnough($same.lon, 11.4041, 0.0000001);
}

func testPathLengthSumsTheLegs() {
    def a as Point init point(0.0, 0.0);
    def b as Point init point(0.0, 1.0);
    def c as Point init point(0.0, 2.0);
    def total as float init pathLength([$a, $b, $c]);
    closeEnough($total, distance($a, $b) + distance($b, $c), 0.001);
}

func testPathLengthOfTooFewPointsIsZero() {
    testing.assertEqual(pathLength([]), 0.0);
    testing.assertEqual(pathLength([point(47.2692, 11.4041)]), 0.0);
}

func testTrackDistanceDoesNotBridgeASegmentGap() {
    def first as Segment init Segment{points: [point(0.0, 0.0), point(0.0, 1.0)]};
    def second as Segment init Segment{points: [point(0.0, 5.0), point(0.0, 6.0)]};
    def t as Track init Track{name: "Gapped", desc: "", kind: "", segments: [$first, $second]};
    def perSegment as float init trackDistance($t);
    def joined as float init pathLength(trackPoints($t));
    # the four-degree gap where the fix was lost is not a leg that was walked
    closeEnough($perSegment, pathLength($first.points) + pathLength($second.points), 0.001);
    testing.assertTrue($joined > $perSegment * 2.0);
}

func testEarthRadiusAndNauticalMile() {
    testing.assertEqual(EARTH_RADIUS, 6371008.8);
    testing.assertEqual(NAUTICAL_MILE, 1852.0);
    # a minute of latitude is a nautical mile, which is what defines it - on a
    # sphere of mean radius it comes out 1.3 m over the defined 1852
    closeEnough(haversine(0.0, 0.0, 1.0 / 60.0, 0.0), NAUTICAL_MILE, 2.0);
}

func testFinalBearingOfAPointToItselfIsZero() {
    def here as Point init point(1.0, 1.0);
    testing.assertEqual(finalBearing($here, $here), bearing($here, $here));
    testing.assertEqual(finalBearing($here, $here), 0.0);
}
