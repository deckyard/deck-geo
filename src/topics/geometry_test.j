# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# geo - white-box tests for the geometry topic.
# Spliced into geo_test.j via include - run with:
#   jennifer test src/geo_test.j

/** A square degree of ocean off west Africa, as a closed ring. */
func squareFence() {
    return [point(0.0, 0.0), point(0.0, 1.0), point(1.0, 1.0), point(1.0, 0.0)];
}

/** A smooth eastward path of eleven points along the equator. */
func straightPath() {
    def out as list of Point init [];
    for (def i as int init 0; $i <= 10; $i = $i + 1) {
        $out[] = point(0.0, convert.toFloat($i) / 100.0);
    }
    return $out;
}

func testBoundsHoldsEveryPoint() {
    def box as Bounds init bounds([point(47.0, 11.0), point(48.0, 12.0), point(46.5, 13.0)]);
    testing.assertEqual($box.minLat, 46.5);
    testing.assertEqual($box.maxLat, 48.0);
    testing.assertEqual($box.minLon, 11.0);
    testing.assertEqual($box.maxLon, 13.0);
}

func testBoundsOfOnePointIsThatPoint() {
    def box as Bounds init bounds([point(47.2692, 11.4041)]);
    testing.assertEqual($box.minLat, $box.maxLat);
    testing.assertEqual($box.minLon, $box.maxLon);
    testing.assertEqual($box.minLat, 47.2692);
}

func failOnBoundsOfNothing() {
    bounds([]);
}

func testBoundsOfNothingIsAnError() {
    testing.assertThrows("failOnBoundsOfNothing", ERROR_KIND);
}

func testContainsPointIncludesTheEdges() {
    def box as Bounds init bounds([point(0.0, 0.0), point(1.0, 1.0)]);
    testing.assertTrue(containsPoint($box, point(0.5, 0.5)));
    testing.assertTrue(containsPoint($box, point(0.0, 0.0)));
    testing.assertTrue(containsPoint($box, point(1.0, 1.0)));
    testing.assertFalse(containsPoint($box, point(1.5, 0.5)));
    testing.assertFalse(containsPoint($box, point(0.5, -0.1)));
}

func testBoundsCenterIsTheMiddle() {
    def box as Bounds init bounds([point(0.0, 0.0), point(2.0, 4.0)]);
    def middle as Point init boundsCenter($box);
    testing.assertEqual($middle.lat, 1.0);
    testing.assertEqual($middle.lon, 2.0);
}

func testCentroidOfOnePointIsThatPoint() {
    def only as Point init centroid([point(47.2692, 11.4041)]);
    testing.assertTrue(math.abs($only.lat - 47.2692) < 0.0000001);
    testing.assertTrue(math.abs($only.lon - 11.4041) < 0.0000001);
}

func testCentroidIsBetweenItsPoints() {
    def middle as Point init centroid([point(0.0, 0.0), point(0.0, 10.0)]);
    testing.assertTrue(math.abs($middle.lon - 5.0) < 0.0001);
    testing.assertTrue(math.abs($middle.lat) < 0.0001);
}

func testCentroidAveragesAcrossTheAntimeridian() {
    # averaged as vectors, two points either side of 180 give a point between
    # them - averaging the degrees would give the opposite side of the planet
    def middle as Point init centroid([point(0.0, 179.0), point(0.0, -179.0)]);
    testing.assertTrue(math.abs($middle.lon) > 179.0);
    testing.assertTrue(math.abs($middle.lat) < 0.0001);
}

func failOnCentroidOfNothing() {
    centroid([]);
}

func testCentroidOfNothingIsAnError() {
    testing.assertThrows("failOnCentroidOfNothing", ERROR_KIND);
}

func testCrossTrackDistanceIsZeroOnTheCourse() {
    def a as Point init point(0.0, 0.0);
    def b as Point init point(0.0, 10.0);
    testing.assertTrue(crossTrackDistance(point(0.0, 5.0), $a, $b) < 1.0);
}

func testCrossTrackDistanceMeasuresOffCourse() {
    def a as Point init point(0.0, 0.0);
    def b as Point init point(0.0, 10.0);
    def off as float init crossTrackDistance(point(0.1, 5.0), $a, $b);
    # a tenth of a degree of latitude is about 11.1 km
    testing.assertTrue(math.abs($off - 11119.0) < 100.0);
}

func testCrossTrackDistanceOfADegenerateLegIsTheDistanceToIt() {
    def a as Point init point(47.2692, 11.4041);
    def p as Point init point(47.2792, 11.4041);
    testing.assertEqual(crossTrackDistance($p, $a, $a), distance($a, $p));
}

func testSegmentOffsetMeasuresToTheSegmentNotTheLine() {
    def a as Point init point(0.0, 0.0);
    def b as Point init point(0.0, 1.0);
    # a point well past b: to the segment that is the distance to b itself
    def beyond as Point init point(0.0, 2.0);
    testing.assertTrue(math.abs(segmentOffset($beyond, $a, $b) - distance($b, $beyond)) < 0.001);
    # whereas the great circle through a and b runs straight through it
    testing.assertTrue(crossTrackDistance($beyond, $a, $b) < 1.0);
}

func testSegmentOffsetOfADegeneratePair() {
    def a as Point init point(0.0, 0.0);
    def p as Point init point(0.0, 1.0);
    testing.assertTrue(math.abs(segmentOffset($p, $a, $a) - distance($a, $p)) < 0.001);
}

func testSegmentOffsetBesideTheArcIsTheCrossTrackDistance() {
    # the foot of (1, 0.5) on the equator lies between the ends, so the offset
    # is the distance to the great circle itself
    def p as Point init point(1.0, 0.5);
    def a as Point init point(0.0, 0.0);
    def b as Point init point(0.0, 1.0);
    testing.assertTrue(math.abs(segmentOffset($p, $a, $b) - crossTrackDistance($p, $a, $b)) < 0.001);
}

func testSimplifyMeasuresALongSpanOnTheSphere() {
    # (60, 1) against the arc (0, 0) - (60, 0) along the prime meridian: its foot
    # lies just past (60, 0), so the offset is the haversine distance to it,
    # 2 R asin(cos 60 * sin 0.5 deg) = 2 * 6371008.8 * asin(0.5 * 0.0087265) = 55,597 m.
    # A plane scaled by cos(0) at the span's start made it a full degree, 111 km.
    def path as list of Point init [point(0.0, 0.0), point(60.0, 1.0), point(60.0, 0.0)];
    testing.assertEqual(len(simplify($path, 60000.0)), 2);
    testing.assertEqual(len(simplify($path, 55000.0)), 3);
}

func testSimplifyDropsPointsOnOneLongGreatCircle() {
    # destination() at one initial bearing from one start walks a single great
    # circle, so every point lies on the arc from the first to the last; at 60 N
    # it bends away from the parallel by kilometres over 500 km
    def start as Point init point(60.0, 0.0);
    def path as list of Point init [$start];
    for (def i as int init 1; $i <= 10; $i = $i + 1) {
        $path[] = destination($start, 90.0, convert.toFloat($i) * 50000.0);
    }
    testing.assertEqual(len(simplify($path, 1.0)), 2);
}

func testSimplifyKeepsTheEnds() {
    def thin as list of Point init simplify(straightPath(), 10.0);
    testing.assertEqual(len($thin), 2);
    testing.assertEqual($thin[0].lon, 0.0);
    testing.assertEqual($thin[1].lon, 0.1);
}

func testSimplifyKeepsACorner() {
    # a right-angle turn is the shape simplification must not lose
    def path as list of Point init [
        point(0.0, 0.0),
        point(0.0, 0.5),
        point(0.0, 1.0),
        point(0.5, 1.0),
        point(1.0, 1.0)
    ];
    def thin as list of Point init simplify($path, 100.0);
    testing.assertEqual(len($thin), 3);
    testing.assertEqual($thin[1].lon, 1.0);
    testing.assertEqual($thin[1].lat, 0.0);
}

func testSimplifyDropsAStraightPointAcrossTheAntimeridian() {
    def path as list of Point init [point(0.0, 179.9), point(0.0, -180.0), point(0.0, -179.9)];
    # the middle point is on the line; measured the long way it looked 360 degrees off
    testing.assertEqual(len(simplify($path, 1.0)), 2);
}

func testSimplifyAtZeroToleranceStillDropsCollinearPoints() {
    def thin as list of Point init simplify(straightPath(), 0.0);
    testing.assertTrue(len($thin) <= len(straightPath()));
    testing.assertTrue(len($thin) >= 2);
}

func testSimplifyPassesShortPathsThrough() {
    def two as list of Point init [point(0.0, 0.0), point(0.0, 1.0)];
    testing.assertEqual(len(simplify($two, 10.0)), 2);
    testing.assertEqual(len(simplify([], 10.0)), 0);
    testing.assertEqual(len(simplify([point(0.0, 0.0)], 10.0)), 1);
}

func testSimplifyKeepsTheWholePointNotJustItsCoordinates() {
    def path as list of Point init [
        withElevation(named(point(0.0, 0.0), "start"), 100.0),
        point(0.0, 0.5),
        withElevation(named(point(0.0, 1.0), "end"), 200.0)
    ];
    def thin as list of Point init simplify($path, 1000.0);
    testing.assertEqual(len($thin), 2);
    testing.assertEqual($thin[0].name, "start");
    testing.assertEqual($thin[0].ele, 100.0);
    testing.assertEqual($thin[1].name, "end");
}

func failOnNegativeTolerance() {
    simplify(straightPath(), -1.0);
}

func testSimplifyRejectsANegativeTolerance() {
    testing.assertThrows("failOnNegativeTolerance", ERROR_KIND);
}

func testFurthestFromFindsTheOutlier() {
    def path as list of Point init [point(0.0, 0.0), point(0.5, 0.5), point(0.0, 1.0)];
    def vectors as UnitVectors init unitVectors($path);
    testing.assertEqual(furthestFrom($vectors, 0, 2, chordSquared(10.0)), 1);
    # with a tolerance wider than the deviation, nothing is far enough
    testing.assertEqual(furthestFrom($vectors, 0, 2, chordSquared(100000.0)), -1);
}

func testChordSquaredOfAnArc() {
    testing.assertEqual(chordSquared(0.0), 0.0);
    # a quarter of the way round: chord sqrt(2), squared 2
    testing.assertTrue(math.abs(chordSquared(EARTH_RADIUS * math.PI / 2.0) - 2.0) < 1e-12);
    # half way round or more: the diameter, squared 4
    testing.assertTrue(math.abs(chordSquared(EARTH_RADIUS * 4.0) - 4.0) < 1e-12);
}

func testPointInPolygonInsideAndOutside() {
    def fence as list of Point init squareFence();
    testing.assertTrue(pointInPolygon(point(0.5, 0.5), $fence));
    testing.assertFalse(pointInPolygon(point(1.5, 0.5), $fence));
    testing.assertFalse(pointInPolygon(point(0.5, 1.5), $fence));
    testing.assertFalse(pointInPolygon(point(-0.5, 0.5), $fence));
}

func testPointInPolygonAcceptsAnExplicitlyClosedRing() {
    # a KML LinearRing repeats its first vertex; the result must not change
    def closed as list of Point init [
        point(0.0, 0.0),
        point(0.0, 1.0),
        point(1.0, 1.0),
        point(1.0, 0.0),
        point(0.0, 0.0)
    ];
    testing.assertTrue(pointInPolygon(point(0.5, 0.5), $closed));
    testing.assertFalse(pointInPolygon(point(2.0, 2.0), $closed));
}

func testPointInPolygonHandlesAConcaveShape() {
    # an L: the notch is outside even though it is inside the bounding box
    def ell as list of Point init [
        point(0.0, 0.0),
        point(0.0, 2.0),
        point(1.0, 2.0),
        point(1.0, 1.0),
        point(2.0, 1.0),
        point(2.0, 0.0)
    ];
    testing.assertTrue(pointInPolygon(point(0.5, 0.5), $ell));
    testing.assertTrue(pointInPolygon(point(1.5, 0.5), $ell));
    testing.assertFalse(pointInPolygon(point(1.5, 1.5), $ell));
}

func failOnTwoVertexPolygon() {
    pointInPolygon(point(0.0, 0.0), [point(0.0, 0.0), point(1.0, 1.0)]);
}

func testPointInPolygonNeedsThreeVertices() {
    testing.assertThrows("failOnTwoVertexPolygon", ERROR_KIND);
}

func testResampleSpacesThePointsOut() {
    def a as Point init point(0.0, 0.0);
    def b as Point init point(0.0, 1.0);
    def even as list of Point init resample([$a, $b], 20000.0);
    # a degree of longitude on the equator is 111.3 km, so about six steps
    testing.assertTrue(len($even) >= 6);
    testing.assertTrue(len($even) <= 8);
    testing.assertEqual($even[0].lon, 0.0);
    testing.assertEqual($even[len($even) - 1].lon, 1.0);
    def gap as float init distance($even[1], $even[2]);
    testing.assertTrue(math.abs($gap - 20000.0) < 500.0);
}

func testResampleStaysOnALegAcrossTheAntimeridian() {
    def even as list of Point init resample([point(0.0, 179.5), point(0.0, -179.5)], 20000.0);
    testing.assertTrue(len($even) >= 6);
    for (def p in $even) {
        testing.assertTrue(math.abs($p.lon) >= 179.5);
    }
}

func testResampleEmitsASampleThatLandsOnAVertex() {
    # three equal legs on the equator, resampled at exactly one leg: the samples
    # are the inner vertices themselves, and the end is not doubled
    def path as list of Point init [
        point(0.0, 0.0),
        point(0.0, 0.001),
        point(0.0, 0.002),
        point(0.0, 0.003)
    ];
    def leg as float init distance($path[0], $path[1]);
    testing.assertEqual(distance($path[1], $path[2]), $leg);
    def even as list of Point init resample($path, $leg);
    testing.assertEqual(len($even), 4);
    for (def i as int init 0; $i < 4; $i = $i + 1) {
        testing.assertTrue(math.abs($even[$i].lon - $path[$i].lon) < 1e-12);
    }
}

func failOnResamplingIntoTooManyPoints() {
    # 1,112 m at 1 mm is 1.1 million points
    resample([point(0.0, 0.0), point(0.0, 0.01)], 0.001);
}

func failOnASpacingBelowTheRoundingStep() {
    # 1e-300 m: before the cap, a running sum never advanced past the first sample
    resample([point(0.0, 0.0), point(0.0, 1.0)], 1e-300);
}

func testResampleRefusesMoreThanMaxResamplePoints() {
    testing.assertThrows("failOnResamplingIntoTooManyPoints", ERROR_KIND);
    testing.assertThrows("failOnASpacingBelowTheRoundingStep", ERROR_KIND);
    testing.assertEqual(MAX_RESAMPLE_POINTS, 1000000);
    # a degree on the equator, 111,195 m, at 1 km: samples at 1..111 km plus both ends
    testing.assertEqual(len(resample([point(0.0, 0.0), point(0.0, 1.0)], 1000.0)), 113);
}

func testResamplePassesShortPathsThrough() {
    testing.assertEqual(len(resample([], 100.0)), 0);
    testing.assertEqual(len(resample([point(0.0, 0.0)], 100.0)), 1);
}

func failOnZeroSpacing() {
    resample(straightPath(), 0.0);
}

func testResampleRejectsANonPositiveSpacing() {
    testing.assertThrows("failOnZeroSpacing", ERROR_KIND);
}

func testInterpolateWalksTheLeg() {
    def a as Point init withElevation(point(0.0, 0.0), 100.0);
    def b as Point init withElevation(point(0.0, 1.0), 200.0);
    def middle as Point init interpolate($a, $b, 0.5);
    testing.assertEqual($middle.lon, 0.5);
    testing.assertEqual($middle.ele, 150.0);
    testing.assertTrue($middle.hasElevation);
    testing.assertEqual(interpolate($a, $b, 0.0).lon, 0.0);
    testing.assertEqual(interpolate($a, $b, 1.0).lon, 1.0);
}

func testInterpolateStatesNoElevationUnlessBothEndsHadOne() {
    def a as Point init withElevation(point(0.0, 0.0), 100.0);
    def bare as Point init point(0.0, 1.0);
    testing.assertFalse(interpolate($a, $bare, 0.5).hasElevation);
    testing.assertFalse(interpolate($bare, $bare, 0.5).hasElevation);
}

func failOnExtrapolatingOffTheEarth() {
    interpolate(point(45.0, 0.0), point(80.0, 0.0), 2.0);
}

func testInterpolateExtrapolatesRatherThanClamping() {
    def a as Point init point(45.0, 0.0);
    def b as Point init point(50.0, 0.0);
    # a fraction past 1.0 goes past b, which is documented and occasionally wanted
    testing.assertEqual(interpolate($a, $b, 2.0).lat, 55.0);
    testing.assertEqual(interpolate($a, $b, -1.0).lat, 40.0);
    # far enough past, and the latitude is not on the Earth
    testing.assertThrows("failOnExtrapolatingOffTheEarth", ERROR_KIND);
}

func testInterpolateWrapsLongitudeRatherThanRaising() {
    def a as Point init point(0.0, 170.0);
    def b as Point init point(0.0, 179.0);
    def over as Point init interpolate($a, $b, 2.0);
    testing.assertTrue($over.lon >= -180.0);
    testing.assertTrue($over.lon < 180.0);
    testing.assertEqual($over.lon, -172.0);
}

func testInterpolateWrapsAFractionTooLargeForFloor() {
    # lon = 1e30 as a float, 1000000000000000019884624838656, wrapped: 0 mod 8
    # (ends 656), 7 mod 9 (digit sum 79), 1 mod 5, so 16 mod 360; -180 -> -164
    def far as Point init interpolate(point(10.0, 0.0), point(10.0, 1.0), 1e30);
    testing.assertEqual($far.lat, 10.0);
    testing.assertEqual($far.lon, -164.0);
}

func testInterpolateCrossesTheAntimeridianTheShortWay() {
    def a as Point init point(0.0, 179.5);
    def b as Point init point(0.0, -179.5);
    # the leg is one degree east; the long way round would land on 0.0
    def middle as Point init interpolate($a, $b, 0.5);
    testing.assertEqual($middle.lon, -180.0);
    testing.assertTrue(math.abs(interpolate($a, $b, 0.25).lon - 179.75) < 0.000001);
}

func testInterpolateCarriesNoTimeOrName() {
    def a as Point init withTime(named(point(0.0, 0.0), "start"), "2026-09-30T06:00:00Z");
    def b as Point init point(0.0, 1.0);
    def middle as Point init interpolate($a, $b, 0.5);
    # an interpolated point was never recorded, so it has no stamp of its own
    testing.assertFalse($middle.hasTime);
    testing.assertEqual($middle.name, "");
}
