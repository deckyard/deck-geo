# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - what a recorded path adds up to.
# Spliced into geo.j via include - not a standalone module.

/**
 * How much a climb must rise to be counted, in metres.
 *
 * An altimeter wanders a few metres while standing still, and summing every
 * upward step counts that wander as climbing. Only a rise of at least this
 * much above the last counted elevation is counted.
 */
export def const ASCENT_THRESHOLD as float init 3.0;

/**
 * How fast something must be going to count as moving, in metres per second.
 *
 * 0.5 m/s is about 1.8 km/h: slower than walking, faster than a stationary
 * fix drifts.
 */
export def const MOVING_SPEED as float init 0.5;

/**
 * What a recorded path adds up to.
 *
 * @field points {int} how many positions it holds
 * @field distance {float} how far it went, in metres
 * @field ascent {float} how much it climbed, in metres
 * @field descent {float} how much it dropped, in metres
 * @field minElevation {float} the lowest elevation, in metres
 * @field maxElevation {float} the highest elevation, in metres
 * @field hasElevation {bool} whether any point carried an elevation
 * @field totalSeconds {int} seconds from the first timed fix to the last
 * @field movingSeconds {int} seconds of that spent at the moving speed or faster
 * @field hasTime {bool} whether the timing fields mean anything
 * @field averageSpeed {float} `distance` over the moving time, in metres per second
 * @field maxSpeed {float} the fastest leg, in metres per second
 */
export def struct TrackStats {
    points as int,
    distance as float,
    ascent as float,
    descent as float,
    minElevation as float,
    maxElevation as float,
    hasElevation as bool,
    totalSeconds as int,
    movingSeconds as int,
    hasTime as bool,
    averageSpeed as float,
    maxSpeed as float
};

/**
 * Measure a recorded path.
 *
 * {@link statsWith} with {@link ASCENT_THRESHOLD} and {@link MOVING_SPEED}.
 * The list is one continuous path: on `trackPoints` of a multi-segment track,
 * `distance` includes the gaps between segments. With no elevations the
 * elevation fields are zero and `hasElevation` false; with fewer than two
 * parseable times the timing fields are zero and `hasTime` false.
 *
 * @param points {list of Point} the path, in order
 * @return {TrackStats} what it adds up to
 * @example
 *   def s as geo.TrackStats init geo.statsOf($doc.tracks[0].segments[0].points);
 *   io.printf("%f|prec=1 km\n", $s.distance / 1000.0);
 */
export func statsOf(points as list of Point) {
    return statsWith($points, ASCENT_THRESHOLD, MOVING_SPEED);
}

/**
 * Measure a recorded path, with the thresholds stated.
 *
 * @param points {list of Point} the path, in order
 * @param climbThreshold {float} how much a rise must be to count, in metres
 * @param movingSpeed {float} how fast counts as moving, in metres per second
 * @return {TrackStats} what it adds up to
 * @throws {Error} when either threshold is negative
 */
export func statsWith(points as list of Point, climbThreshold as float, movingSpeed as float) {
    if ($climbThreshold < 0.0 or $movingSpeed < 0.0) {
        fail("a statistics threshold cannot be negative");
    }
    def out as TrackStats init emptyStats();
    $out.points = len($points);
    if (len($points) == 0) {
        return $out;
    }
    $out = measureElevation($out, $points, $climbThreshold);
    return measureLegs($out, $points, $movingSpeed);
}

/**
 * A measurement of nothing.
 *
 * @return {TrackStats} every field zero, every flag false
 */
func emptyStats() {
    return TrackStats{
        points: 0,
        distance: 0.0,
        ascent: 0.0,
        descent: 0.0,
        minElevation: 0.0,
        maxElevation: 0.0,
        hasElevation: false,
        totalSeconds: 0,
        movingSeconds: 0,
        hasTime: false,
        averageSpeed: 0.0,
        maxSpeed: 0.0
    };
}

/**
 * Fill in the elevation fields.
 *
 * Accumulated against a running reference, not point to point: a rise counts
 * only once it has gone `climbThreshold` above the last elevation that
 * counted, and the reference then moves there. Sensor wander below the
 * threshold never moves the reference, so it never adds up - while a long slow
 * climb of one-metre steps still accumulates, because the steps are measured
 * from the reference rather than from the point before.
 *
 * @param into {TrackStats} the measurement to fill in
 * @param points {list of Point} the path, in order
 * @param climbThreshold {float} how much a rise must be to count, in metres
 * @return {TrackStats} a fresh measurement; the argument is not changed
 */
func measureElevation(into as TrackStats, points as list of Point, climbThreshold as float) {
    def out as TrackStats init $into;
    def withEle as list of Point init [];
    for (def p in $points) {
        if ($p.hasElevation) {
            $withEle[] = $p;
        }
    }
    if (len($withEle) == 0) {
        return $out;
    }
    $out.hasElevation = true;
    $out.minElevation = $withEle[0].ele;
    $out.maxElevation = $withEle[0].ele;
    def reference as float init $withEle[0].ele;
    for (def p in $withEle) {
        $out.minElevation = math.min($out.minElevation, $p.ele);
        $out.maxElevation = math.max($out.maxElevation, $p.ele);
        def step as float init $p.ele - $reference;
        if ($step >= $climbThreshold) {
            $out.ascent = $out.ascent + $step;
            $reference = $p.ele;
        } elseif (-$step >= $climbThreshold) {
            $out.descent = $out.descent - $step;
            $reference = $p.ele;
        }
    }
    return $out;
}

/**
 * A parsed timestamp.
 *
 * A struct rather than a sentinel: every millisecond count is a real instant,
 * and the `-1` this used to return for "unreadable" made 1969 unreadable too.
 *
 * @field valid {bool} whether the text parsed
 * @field millis {int} milliseconds since the Unix epoch, negative before 1970
 */
def struct Instant {
    valid as bool,
    millis as int
};

/**
 * Fill in the distance, timing and speed fields.
 *
 * Timed in milliseconds, not whole seconds. A logger recording faster than
 * once a second puts several points in one second: truncating to the second
 * dropped those legs as zero-length and overstated the speed of the rest.
 *
 * @param into {TrackStats} the measurement to fill in
 * @param points {list of Point} the path, in order
 * @param movingSpeed {float} how fast counts as moving, in metres per second
 * @return {TrackStats} a fresh measurement; the argument is not changed
 */
func measureLegs(into as TrackStats, points as list of Point, movingSpeed as float) {
    def out as TrackStats init $into;
    def instants as list of Instant init [];
    for (def p in $points) {
        $instants[] = pointInstant($p);
    }
    def movingMillis as int init 0;
    for (def i as int init 1; $i < len($points); $i = $i + 1) {
        def metres as float init distance($points[$i - 1], $points[$i]);
        $out.distance = $out.distance + $metres;
        def a as Instant init $instants[$i - 1];
        def b as Instant init $instants[$i];
        if ($a.valid and $b.valid and $b.millis > $a.millis) {
            def millis as int init $b.millis - $a.millis;
            def speed as float init $metres * 1000.0 / convert.toFloat($millis);
            $out.maxSpeed = math.max($out.maxSpeed, $speed);
            if ($speed >= $movingSpeed) {
                $movingMillis = $movingMillis + $millis;
            }
        }
    }
    def span as int init spanMillis($instants);
    if ($span < 0) {
        return $out;
    }
    # Timestamps that run backwards - a recorder whose clock stepped, or two
    # files concatenated - can sum more moving time than the span they cover.
    # Reporting that would be nonsense, so the span is the ceiling.
    $movingMillis = math.min($movingMillis, $span);
    $out.hasTime = true;
    $out.totalSeconds = math.round(convert.toFloat($span) / 1000.0);
    $out.movingSeconds = math.round(convert.toFloat($movingMillis) / 1000.0);
    if ($movingMillis > 0) {
        $out.averageSpeed = $out.distance * 1000.0 / convert.toFloat($movingMillis);
    }
    return $out;
}

/**
 * The time from the first stamped point to the last.
 *
 * @param instants {list of Instant} one per point, in order
 * @return {int} the span in milliseconds, or `-1` when fewer than two points are
 *   stamped or the last precedes the first
 */
func spanMillis(instants as list of Instant) {
    def first as int init -1;
    def last as int init -1;
    for (def i as int init 0; $i < len($instants); $i = $i + 1) {
        if ($instants[$i].valid) {
            if ($first < 0) {
                $first = $i;
            }
            $last = $i;
        }
    }
    if ($first < 0 or $first == $last) {
        return -1;
    }
    def span as int init $instants[$last].millis - $instants[$first].millis;
    if ($span < 0) {
        return -1;
    }
    return $span;
}

/**
 * How many seconds there are between two RFC 3339 timestamps.
 *
 * A stamp that does not parse yields `-1` rather than raising. A stamp with no
 * zone is read as UTC. The difference is rounded to the nearest second.
 *
 * @param from {string} the earlier instant
 * @param to2 {string} the later instant
 * @return {int} the difference in seconds, or `-1` when either does not parse
 */
export func secondsBetween(from as string, to2 as string) {
    def a as Instant init instantOf($from);
    def b as Instant init instantOf($to2);
    if (not $a.valid or not $b.valid) {
        return -1;
    }
    return math.round(convert.toFloat($b.millis - $a.millis) / 1000.0);
}

/**
 * A point's timestamp, parsed.
 *
 * @param p {Point} the point
 * @return {Instant} its instant, invalid when it has none or it does not parse
 */
func pointInstant(p as Point) {
    if (not $p.hasTime) {
        return Instant{valid: false, millis: 0};
    }
    return instantOf($p.at);
}

/**
 * An RFC 3339 timestamp as milliseconds since the Unix epoch.
 *
 * A stamp with no zone - GPX 1.0 files and some phone apps write local time
 * that way - is read as UTC, the only reading that does not invent an offset.
 *
 * @param at {string} the instant, as RFC 3339
 * @return {Instant} the instant, invalid when the text does not parse
 */
func instantOf(at as string) {
    def text as string init strings.trim($at);
    if ($text == "") {
        return Instant{valid: false, millis: 0};
    }
    def parsed as time.Time init time.now();
    try {
        $parsed = time.fromIso($text);
    } catch (e) {
        try {
            $parsed = time.fromIso($text + "Z");
        } catch (again) {
            return Instant{valid: false, millis: 0};
        }
    }
    return Instant{valid: true, millis: time.unixMillis($parsed)};
}
