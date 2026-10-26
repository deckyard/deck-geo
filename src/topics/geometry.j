# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# geo - bounding boxes, centroids, simplification and containment.
# Spliced into geo.j via include - not a standalone module.

/**
 * The smallest latitude and longitude rectangle holding every point.
 *
 * Computed in degrees, so a path that straddles the antimeridian comes back
 * as a box spanning nearly the whole globe rather than the narrow one that
 * crosses it. Tracks that cross 180 degrees of longitude are rare enough that
 * the simple answer is the useful one, and the alternative cannot be told
 * apart from a global box.
 *
 * @param points {list of Point} the points to bound
 * @return {Bounds} the rectangle
 * @throws {Error} when the list is empty
 * @example
 *   def box as geo.Bounds init geo.bounds(geo.documentPoints($doc));
 */
export func bounds(points as list of Point) {
    if (len($points) == 0) {
        fail("bounds of no points");
    }
    def minLat as float init $points[0].lat;
    def maxLat as float init $points[0].lat;
    def minLon as float init $points[0].lon;
    def maxLon as float init $points[0].lon;
    for (def p in $points) {
        $minLat = math.min($minLat, $p.lat);
        $maxLat = math.max($maxLat, $p.lat);
        $minLon = math.min($minLon, $p.lon);
        $maxLon = math.max($maxLon, $p.lon);
    }
    return Bounds{minLat: $minLat, minLon: $minLon, maxLat: $maxLat, maxLon: $maxLon};
}

/**
 * Whether a rectangle holds a point, edges included.
 *
 * @param box {Bounds} the rectangle
 * @param p {Point} the point to test
 * @return {bool} whether the point is inside or on the edge
 */
export func containsPoint(box as Bounds, p as Point) {
    return $p.lat >= $box.minLat and $p.lat <= $box.maxLat and $p.lon >= $box.minLon and
        $p.lon <= $box.maxLon;
}

/**
 * The centre of a rectangle.
 *
 * @param box {Bounds} the rectangle
 * @return {Point} the point half way along each edge
 */
export func boundsCenter(box as Bounds) {
    return point(($box.minLat + $box.maxLat) / 2.0, ($box.minLon + $box.maxLon) / 2.0);
}

/**
 * The mean position of a list of points.
 *
 * Averaged as unit vectors rather than as degrees, so a cluster either side of
 * the antimeridian averages to a point between them rather than to the
 * opposite side of the planet.
 *
 * @param points {list of Point} the points to average
 * @return {Point} the mean position
 * @throws {Error} when the list is empty
 */
export func centroid(points as list of Point) {
    if (len($points) == 0) {
        fail("centroid of no points");
    }
    def x as float init 0.0;
    def y as float init 0.0;
    def z as float init 0.0;
    for (def p in $points) {
        def phi as float init toRadians($p.lat);
        def lambda as float init toRadians($p.lon);
        $x = $x + math.cos($phi) * math.cos($lambda);
        $y = $y + math.cos($phi) * math.sin($lambda);
        $z = $z + math.sin($phi);
    }
    def n as float init convert.toFloat(len($points));
    return vectorPoint($x / $n, $y / $n, $z / $n);
}

/**
 * The point a mean unit vector names.
 *
 * @param x {float} the component through the prime meridian at the equator
 * @param y {float} the component through 90 degrees east at the equator
 * @param z {float} the component through the north pole
 * @return {Point} the position, or the equator and prime meridian when the vector is zero
 */
func vectorPoint(x as float, y as float, z as float) {
    def flat as float init math.hypot($x, $y);
    if ($flat == 0.0 and $z == 0.0) {
        return point(0.0, 0.0);
    }
    def lat as float init toDegrees(math.atan2($z, $flat));
    def lon as float init toDegrees(math.atan2($y, $x));
    return point($lat, normalizeLongitude($lon));
}

/**
 * Cross-track distance: how far a point lies off the great circle through two
 * others, in metres.
 *
 * A navigator's off-course distance, measured to the infinite great circle:
 * a point beyond the end of the leg gets its distance from the course line,
 * not from the waypoint. When `a` and `b` coincide, the distance from `a`.
 *
 * @param p {Point} the point to measure
 * @param a {Point} the leg's start, which also fixes the course
 * @param b {Point} the leg's end
 * @return {float} the distance in metres, never negative
 */
export func crossTrackDistance(p as Point, a as Point, b as Point) {
    def legLength as float init distance($a, $b);
    if ($legLength == 0.0) {
        return distance($a, $p);
    }
    def delta as float init distance($a, $p) / EARTH_RADIUS;
    def theta as float init toRadians(bearing($a, $p) - bearing($a, $b));
    def across as float init math.asin(clampUnit(math.sin($delta) * math.sin($theta)));
    return math.abs($across * EARTH_RADIUS);
}

/**
 * Drop the points of a path that do not change its shape.
 *
 * Ramer-Douglas-Peucker: the two ends are kept, and within each span the
 * point furthest from the segment joining the span's ends is kept, splitting
 * the span, when it lies more than `tolerance` metres from it. Paths of fewer
 * than three points are returned as they are.
 *
 * Driven by an explicit worklist rather than by recursion. The recursive
 * shape has to carry the marker list through every call, and Jennifer copies
 * a value on every argument pass - which turns a 50,000-point track into tens
 * of thousands of 50,000-element copies. The worklist keeps the markers in one
 * place and hands the spans around instead.
 *
 * The surviving points come back whole: elevation, time, name and all.
 *
 * @param points {list of Point} the path to thin, in order
 * @param tolerance {float} how far the line may move, in metres
 * @return {list of Point} the surviving points, in order
 * @throws {Error} when the tolerance is negative
 * @example
 *   def thin as list of geo.Point init geo.simplify($points, 10.0);
 */
export func simplify(points as list of Point, tolerance as float) {
    if ($tolerance < 0.0) {
        fail("simplify tolerance " + decimal($tolerance, 2) + " is negative");
    }
    if (len($points) < 3) {
        return $points;
    }
    def keep as list of bool init [];
    for (def i as int init 0; $i < len($points); $i = $i + 1) {
        $keep[] = false;
    }
    $keep[0] = true;
    $keep[len($points) - 1] = true;
    # The spans still to judge, as two parallel lists walked by a cursor. A
    # span that splits appends its two halves, so the walk ends when every
    # span is either too short to split or flat enough to drop.
    def firsts as list of int init [0];
    def lasts as list of int init [len($points) - 1];
    def at as int init 0;
    while ($at < len($firsts)) {
        def first as int init $firsts[$at];
        def last as int init $lasts[$at];
        $at = $at + 1;
        def furthest as int init furthestFrom($points, $first, $last, $tolerance);
        if ($furthest > 0) {
            $keep[$furthest] = true;
            $firsts[] = $first;
            $lasts[] = $furthest;
            $firsts[] = $furthest;
            $lasts[] = $last;
        }
    }
    def out as list of Point init [];
    for (def i as int init 0; $i < len($points); $i = $i + 1) {
        if ($keep[$i]) {
            $out[] = $points[$i];
        }
    }
    return $out;
}

/**
 * The point of a span furthest from the line closing it, if any is far enough.
 *
 * @param points {list of Point} the whole path
 * @param first {int} the index the span starts at
 * @param last {int} the index the span ends at
 * @param tolerance {float} how far the line may move, in metres
 * @return {int} the index of the furthest point, or `-1` when none is past the tolerance
 */
func furthestFrom(points as list of Point, first as int, last as int, tolerance as float) {
    def furthest as int init -1;
    def worst as float init $tolerance;
    for (def i as int init $first + 1; $i < $last; $i = $i + 1) {
        def off as float init segmentOffset($points[$i], $points[$first], $points[$last]);
        if ($off > $worst) {
            $worst = $off;
            $furthest = $i;
        }
    }
    return $furthest;
}

/**
 * How far a point lies from the segment between two others, in metres.
 *
 * Projected onto a local plane - degrees of longitude scaled by the cosine of
 * the latitude, taken the short way across the antimeridian - rather than
 * solved on the sphere. Over the distances a simplification tolerance names,
 * the two agree to well under a millimetre, and the planar form costs two
 * multiplications where the spherical form costs half a dozen trigonometric
 * calls per point per span.
 *
 * Measured to the **segment**, not to the infinite line through it: a point
 * beyond either end is measured to that end. {@link crossTrackDistance} is the
 * other question: distance to the great circle, what a navigator means by
 * cross-track error.
 *
 * @param p {Point} the point to measure
 * @param a {Point} one end of the segment
 * @param b {Point} the other end of the segment
 * @return {float} the distance in metres
 */
func segmentOffset(p as Point, a as Point, b as Point) {
    def scale as float init math.cos(toRadians($a.lat));
    def metresPerDegree as float init math.PI * EARTH_RADIUS / 180.0;
    def px as float init longitudeDelta($a.lon, $p.lon) * $scale;
    def py as float init $p.lat - $a.lat;
    def bx as float init longitudeDelta($a.lon, $b.lon) * $scale;
    def by as float init $b.lat - $a.lat;
    def square as float init $bx * $bx + $by * $by;
    if ($square == 0.0) {
        return math.hypot($px, $py) * $metresPerDegree;
    }
    def along as float init ($px * $bx + $py * $by) / $square;
    def clamped as float init math.max(0.0, math.min(1.0, $along));
    def dx as float init $px - $clamped * $bx;
    def dy as float init $py - $clamped * $by;
    return math.hypot($dx, $dy) * $metresPerDegree;
}

/**
 * Whether a point lies inside a polygon.
 *
 * Even-odd ray casting in plain degrees. The ring closes implicitly, so a
 * KML `LinearRing` or a GeoJSON ring works whether or not it repeats its first
 * vertex. A point exactly on an edge can come back either way. Longitudes are
 * not unwrapped, so a polygon crossing the antimeridian is not handled.
 *
 * @param p {Point} the point to test
 * @param polygon {list of Point} the vertices, in order
 * @return {bool} whether the point is inside
 * @throws {Error} when the polygon has fewer than three vertices
 * @example
 *   if (geo.pointInPolygon($fix, $fence)) { alert(); }
 */
export func pointInPolygon(p as Point, polygon as list of Point) {
    if (len($polygon) < 3) {
        fail("a polygon needs three vertices, got " + convert.toString(len($polygon)));
    }
    def inside as bool init false;
    def n as int init len($polygon);
    def j as int init $n - 1;
    for (def i as int init 0; $i < $n; $i = $i + 1) {
        if (crossesRay($p, $polygon[$i], $polygon[$j])) {
            $inside = not $inside;
        }
        $j = $i;
    }
    return $inside;
}

/**
 * Whether the edge between two vertices crosses the ray east of a point.
 *
 * @param p {Point} the point the ray starts at
 * @param a {Point} one end of the edge
 * @param b {Point} the other end of the edge
 * @return {bool} whether the edge crosses the ray
 */
func crossesRay(p as Point, a as Point, b as Point) {
    def straddles as bool init ($a.lat > $p.lat) != ($b.lat > $p.lat);
    if (not $straddles) {
        return false;
    }
    def span as float init $b.lat - $a.lat;
    if ($span == 0.0) {
        return false;
    }
    def at as float init $a.lon + ($p.lat - $a.lat) / $span * ($b.lon - $a.lon);
    return $p.lon < $at;
}

/**
 * Resample a path to a fixed spacing.
 *
 * Emits a point every `spacing` metres along the path, interpolated along the
 * leg it falls on, plus the original first and last points. Interpolated
 * points carry coordinates, and an elevation when both ends of their leg had
 * one; no time and no name. A path of fewer than two points is returned as is.
 *
 * @param points {list of Point} the path to resample, in order
 * @param spacing {float} how far apart the results should be, in metres
 * @return {list of Point} the resampled path
 * @throws {Error} when the spacing is not positive
 */
export func resample(points as list of Point, spacing as float) {
    if ($spacing <= 0.0) {
        fail("resample spacing " + decimal($spacing, 2) + " is not positive");
    }
    if (len($points) < 2) {
        return $points;
    }
    def out as list of Point init [$points[0]];
    def carried as float init 0.0;
    for (def i as int init 1; $i < len($points); $i = $i + 1) {
        def leg as float init distance($points[$i - 1], $points[$i]);
        def walked as float init $spacing - $carried;
        while ($walked < $leg) {
            $out[] = interpolate($points[$i - 1], $points[$i], $walked / $leg);
            $walked = $walked + $spacing;
        }
        $carried = legRemainder($carried, $leg, $spacing);
    }
    $out[] = $points[len($points) - 1];
    return $out;
}

/**
 * How far past the last emitted point a leg ends.
 *
 * @param carried {float} what was left over from the leg before
 * @param leg {float} how long this leg is, in metres
 * @param spacing {float} the sampling interval, in metres
 * @return {float} the leftover to carry into the next leg
 */
func legRemainder(carried as float, leg as float, spacing as float) {
    def total as float init $carried + $leg;
    def whole as float init convert.toFloat(math.floor($total / $spacing));
    return $total - $whole * $spacing;
}

/**
 * A point a fraction of the way along the line between two others.
 *
 * Interpolated in degrees, which over one leg of a track log - tens of metres
 * - is indistinguishable from interpolating along the great circle. Longitude
 * goes the short way round, so a leg across the antimeridian stays near it
 * rather than sweeping through the prime meridian.
 *
 * A fraction outside 0.0 to 1.0 **extrapolates** past the end of the leg rather
 * than being clamped, which is occasionally what a caller wants and is a trap
 * otherwise: extrapolating far enough reaches a latitude that is not on the
 * Earth, and that raises. Longitude wraps instead of raising, because a meridian
 * past 180 degrees is still a meridian.
 *
 * @param a {Point} the leg's start
 * @param b {Point} the leg's end
 * @param fraction {float} how far along, 0.0 at `a` and 1.0 at `b`
 * @return {Point} the interpolated position, with an elevation when both ends had one
 * @throws {Error} when extrapolation puts the latitude outside -90 to 90
 */
export func interpolate(a as Point, b as Point, fraction as float) {
    def lat as float init $a.lat + ($b.lat - $a.lat) * $fraction;
    def lon as float init $a.lon + longitudeDelta($a.lon, $b.lon) * $fraction;
    def out as Point init point($lat, normalizeLongitude($lon));
    if ($a.hasElevation and $b.hasElevation) {
        $out = withElevation($out, $a.ele + ($b.ele - $a.ele) * $fraction);
    }
    return $out;
}
