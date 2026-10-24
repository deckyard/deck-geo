# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - white-box tests for the stats topic.
# Spliced into geo_test.j via include - run with:
#   jennifer test src/geo_test.j

/** A climb of 100 m over four points, one minute apart, at walking pace. */
func climbingPath() {
    def out as list of Point init [];
    def elevations as list of float init [500.0, 530.0, 570.0, 600.0];
    for (def i as int init 0; $i < 4; $i = $i + 1) {
        def lon as float init 11.4041 + convert.toFloat($i) * 0.002;
        def at as string init "2026-09-30T06:0" + convert.toString($i) + ":00Z";
        $out[] = withTime(withElevation(point(47.2692, $lon), $elevations[$i]), $at);
    }
    return $out;
}

func testStatsOfNothing() {
    def s as TrackStats init statsOf([]);
    testing.assertEqual($s.points, 0);
    testing.assertEqual($s.distance, 0.0);
    testing.assertFalse($s.hasElevation);
    testing.assertFalse($s.hasTime);
}

func testStatsOfOnePoint() {
    def s as TrackStats init statsOf([withElevation(point(47.2692, 11.4041), 574.0)]);
    testing.assertEqual($s.points, 1);
    testing.assertEqual($s.distance, 0.0);
    testing.assertTrue($s.hasElevation);
    testing.assertEqual($s.minElevation, 574.0);
    testing.assertEqual($s.maxElevation, 574.0);
    # one stamped point is not a span of time
    testing.assertFalse($s.hasTime);
}

func testStatsCountsTheClimb() {
    def s as TrackStats init statsOf(climbingPath());
    testing.assertEqual($s.points, 4);
    testing.assertEqual($s.ascent, 100.0);
    testing.assertEqual($s.descent, 0.0);
    testing.assertEqual($s.minElevation, 500.0);
    testing.assertEqual($s.maxElevation, 600.0);
    testing.assertTrue($s.hasElevation);
}

func testStatsCountsTheDescent() {
    def down as list of Point init [
        withElevation(point(47.2692, 11.4041), 600.0),
        withElevation(point(47.2692, 11.4061), 550.0),
        withElevation(point(47.2692, 11.4081), 500.0)
    ];
    def s as TrackStats init statsOf($down);
    testing.assertEqual($s.descent, 100.0);
    testing.assertEqual($s.minElevation, 500.0);
    testing.assertEqual($s.ascent, 0.0);
}

func testStatsIgnoresElevationNoise() {
    # a flat walk whose barometer wanders by a metre either way: a naive sum of
    # every upward step would report tens of metres of climbing
    def flat as list of Point init [];
    def wobble as list of float init [500.0, 501.0, 500.0, 501.0, 500.0, 501.0, 500.0, 501.0];
    for (def i as int init 0; $i < len($wobble); $i = $i + 1) {
        def lon as float init 11.4041 + convert.toFloat($i) * 0.001;
        $flat[] = withElevation(point(47.2692, $lon), $wobble[$i]);
    }
    def s as TrackStats init statsOf($flat);
    testing.assertEqual($s.ascent, 0.0);
    testing.assertEqual($s.descent, 0.0);
    # but the wander is still visible in the range
    testing.assertEqual($s.minElevation, 500.0);
    testing.assertEqual($s.maxElevation, 501.0);
}

func testStatsWithATighterThresholdCountsMore() {
    def flat as list of Point init [
        withElevation(point(47.2692, 11.4041), 500.0),
        withElevation(point(47.2692, 11.4061), 502.0)
    ];
    testing.assertEqual(statsOf($flat).ascent, 0.0);
    testing.assertEqual(statsWith($flat, 1.0, MOVING_SPEED).ascent, 2.0);
}

func testStatsMeasuresTime() {
    def s as TrackStats init statsOf(climbingPath());
    testing.assertTrue($s.hasTime);
    # 06:00:00 to 06:03:00
    testing.assertEqual($s.totalSeconds, 180);
    testing.assertTrue($s.movingSeconds > 0);
    testing.assertTrue($s.movingSeconds <= $s.totalSeconds);
    testing.assertTrue($s.averageSpeed > 0.0);
    testing.assertTrue($s.maxSpeed > 0.0);
}

func testStatsSaysNothingAboutTimeWithoutStamps() {
    def bare as list of Point init [point(47.2692, 11.4041), point(47.2792, 11.4141)];
    def s as TrackStats init statsOf($bare);
    testing.assertFalse($s.hasTime);
    testing.assertEqual($s.totalSeconds, 0);
    testing.assertEqual($s.movingSeconds, 0);
    testing.assertEqual($s.averageSpeed, 0.0);
    # the distance is still measured
    testing.assertTrue($s.distance > 0.0);
}

func testStatsDoesNotCountAStandingStillAsMoving() {
    # two fixes a minute apart, a metre and a half apart: that is not walking
    def still as list of Point init [
        withTime(point(47.2692, 11.4041), "2026-09-30T06:00:00Z"),
        withTime(point(47.26921, 11.40411), "2026-09-30T06:01:00Z")
    ];
    def s as TrackStats init statsOf($still);
    testing.assertEqual($s.totalSeconds, 60);
    testing.assertEqual($s.movingSeconds, 0);
}

func testStatsNeverReportsMoreMovingTimeThanElapsed() {
    # a recorder whose clock stepped backwards, or two files concatenated
    def jumbled as list of Point init [
        withTime(point(47.0000, 11.0), "2026-09-30T06:00:00Z"),
        withTime(point(47.0100, 11.0), "2026-09-30T06:10:00Z"),
        withTime(point(47.0200, 11.0), "2026-09-30T06:01:00Z")
    ];
    def s as TrackStats init statsOf($jumbled);
    testing.assertTrue($s.movingSeconds <= $s.totalSeconds);
}

func failOnNegativeThreshold() {
    statsWith([], -1.0, 0.5);
}

func testStatsWithRejectsANegativeThreshold() {
    testing.assertThrows("failOnNegativeThreshold", ERROR_KIND);
}

func testSecondsBetween() {
    testing.assertEqual(secondsBetween("2026-09-30T06:00:00Z", "2026-09-30T06:01:00Z"), 60);
    testing.assertEqual(secondsBetween("2026-09-30T06:00:00Z", "2026-09-30T06:00:00Z"), 0);
    testing.assertEqual(secondsBetween("2026-09-30T06:01:00Z", "2026-09-30T06:00:00Z"), -60);
}

func testSecondsBetweenAcceptsAnOffsetAndFractions() {
    # the same instant written two ways is no time at all apart
    testing.assertEqual(secondsBetween("2026-09-30T08:00:00+02:00", "2026-09-30T06:00:00Z"), 0);
    testing.assertEqual(secondsBetween("2026-09-30T06:00:00.500Z", "2026-09-30T06:00:01.500Z"), 1);
}

func testSecondsBetweenReportsMinusOneForWhatDoesNotParse() {
    testing.assertEqual(secondsBetween("not a time", "2026-09-30T06:00:00Z"), -1);
    testing.assertEqual(secondsBetween("2026-09-30T06:00:00Z", ""), -1);
    testing.assertEqual(secondsBetween("", ""), -1);
}

func testInstantOf() {
    testing.assertEqual(instantOf("1970-01-01T00:00:00Z"), Instant{valid: true, millis: 0});
    testing.assertEqual(instantOf("1970-01-01T00:01:00.250Z").millis, 60250);
    # before 1970 is a real instant, not the "unreadable" it used to collide with
    testing.assertEqual(instantOf("1969-12-31T23:59:59Z"), Instant{valid: true, millis: -1000});
    testing.assertFalse(instantOf("rubbish").valid);
    testing.assertFalse(instantOf("  ").valid);
}

func testSecondsBetweenReadsAStampWithNoZoneAsUtc() {
    testing.assertEqual(secondsBetween("2026-01-01T10:00:00", "2026-01-01T10:00:10"), 10);
    testing.assertEqual(secondsBetween("2026-01-01T10:00:00", "2026-01-01T10:00:00Z"), 0);
}

func testStatsTimesLegsShorterThanASecond() {
    # three points a 111 m apart, 0.6 s apart: a 5 Hz logger at speed
    def fast as list of Point init [
        withTime(point(0.0, 0.000), "2026-09-30T10:00:00.200Z"),
        withTime(point(0.0, 0.001), "2026-09-30T10:00:00.800Z"),
        withTime(point(0.0, 0.002), "2026-09-30T10:00:01.400Z")
    ];
    def s as TrackStats init statsOf($fast);
    testing.assertEqual($s.totalSeconds, 1);
    testing.assertEqual($s.movingSeconds, 1);
    testing.assertTrue(math.abs($s.maxSpeed - 185.3) < 0.5);
    testing.assertTrue(math.abs($s.averageSpeed - 185.3) < 0.5);
}

func testStatsTimesATrackFrom1969() {
    def old as list of Point init [
        withTime(point(0.0, 0.00), "1969-12-31T23:59:00Z"),
        withTime(point(0.0, 0.01), "1970-01-01T00:01:00Z")
    ];
    def s as TrackStats init statsOf($old);
    testing.assertTrue($s.hasTime);
    testing.assertEqual($s.totalSeconds, 120);
}

func testThresholdConstants() {
    testing.assertEqual(ASCENT_THRESHOLD, 3.0);
    testing.assertEqual(MOVING_SPEED, 0.5);
}
