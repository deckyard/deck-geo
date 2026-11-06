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
 * point furthest from the great-circle arc joining the span's ends is kept,
 * splitting the span, when it lies more than `tolerance` metres from it.
 * Paths of fewer than three points are returned as they are.
 *
 * Offsets are measured on the sphere (see {@link segmentOffset}), so a span of
 * any length is judged correctly: points on one great circle are collinear
 * however far apart the span's ends are.
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
    def path as UnitVectors init unitVectors($points);
    def limit as float init chordSquared($tolerance);
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
        def furthest as int init furthestFrom($path, $first, $last, $limit);
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
 * A path's points as unit vectors from the Earth's centre, in parallel lists.
 *
 * @field xs {list of float} the components through the prime meridian at the equator
 * @field ys {list of float} the components through 90 degrees east at the equator
 * @field zs {list of float} the components through the north pole
 */
def struct UnitVectors {
    xs as list of float,
    ys as list of float,
    zs as list of float
};

/**
 * Every point of a path as a unit vector, computed once per path so that the
 * per-span loop of {@link simplify} does arithmetic only.
 *
 * @param points {list of Point} the path
 * @return {UnitVectors} one vector per point, in order
 */
func unitVectors(points as list of Point) {
    def xs as list of float init [];
    def ys as list of float init [];
    def zs as list of float init [];
    for (def p in $points) {
        def phi as float init toRadians($p.lat);
        def lambda as float init toRadians($p.lon);
        def flat as float init math.cos($phi);
        $xs[] = $flat * math.cos($lambda);
        $ys[] = $flat * math.sin($lambda);
        $zs[] = math.sin($phi);
    }
    return UnitVectors{xs: $xs, ys: $ys, zs: $zs};
}

/**
 * The squared chord, on the unit sphere, of an arc a distance long.
 *
 * Offsets are compared as squared chords, which rise with the arc from 0 to
 * half way round the Earth, so the hot loop needs no `asin`.
 *
 * @param metres {float} the arc length along the surface, not negative
 * @return {float} the squared chord, 0.0 to 4.0
 */
func chordSquared(metres as float) {
    def angle as float init math.min($metres / EARTH_RADIUS, math.PI);
    def half as float init 2.0 * math.sin($angle / 2.0);
    return $half * $half;
}

/**
 * The point of a span furthest from the arc closing it, if any is far enough.
 *
 * @param path {UnitVectors} the whole path
 * @param first {int} the index the span starts at
 * @param last {int} the index the span ends at
 * @param limit {float} the squared chord a point must exceed, from {@link chordSquared}
 * @return {int} the index of the furthest point, or `-1` when none is past the limit
 */
func furthestFrom(path as UnitVectors, first as int, last as int, limit as float) {
    def arc as Arc init arcOf($path, $first, $last);
    def furthest as int init -1;
    def worst as float init $limit;
    for (def i as int init $first + 1; $i < $last; $i = $i + 1) {
        def off as float init chordToArc($arc, $path.xs[$i], $path.ys[$i], $path.zs[$i]);
        if ($off > $worst) {
            $worst = $off;
            $furthest = $i;
        }
    }
    return $furthest;
}

/**
 * A great-circle arc, with what measuring a point against it needs taken once.
 *
 * `u = n x a` and `w = b x n`: a point's foot on the great circle lies between
 * `a` and `b` when its dot products with both are not negative.
 *
 * @field ax {float} the start's x
 * @field ay {float} the start's y
 * @field az {float} the start's z
 * @field bx {float} the end's x
 * @field by {float} the end's y
 * @field bz {float} the end's z
 * @field nx {float} the unit normal's x
 * @field ny {float} the unit normal's y
 * @field nz {float} the unit normal's z
 * @field ux {float} `n x a`, x
 * @field uy {float} `n x a`, y
 * @field uz {float} `n x a`, z
 * @field wx {float} `b x n`, x
 * @field wy {float} `b x n`, y
 * @field wz {float} `b x n`, z
 * @field degenerate {bool} whether the ends coincide (or are antipodal), so no circle is defined
 */
def struct Arc {
    ax as float,
    ay as float,
    az as float,
    bx as float,
    by as float,
    bz as float,
    nx as float,
    ny as float,
    nz as float,
    ux as float,
    uy as float,
    uz as float,
    wx as float,
    wy as float,
    wz as float,
    degenerate as bool
};

/**
 * The arc between two vectors of a path.
 *
 * @param path {UnitVectors} the path
 * @param first {int} the index of the arc's start
 * @param last {int} the index of the arc's end
 * @return {Arc} the arc
 */
func arcOf(path as UnitVectors, first as int, last as int) {
    def ax as float init $path.xs[$first];
    def ay as float init $path.ys[$first];
    def az as float init $path.zs[$first];
    def bx as float init $path.xs[$last];
    def by as float init $path.ys[$last];
    def bz as float init $path.zs[$last];
    def nx as float init $ay * $bz - $az * $by;
    def ny as float init $az * $bx - $ax * $bz;
    def nz as float init $ax * $by - $ay * $bx;
    def size as float init math.sqrt($nx * $nx + $ny * $ny + $nz * $nz);
    if ($size > 0.0) {
        $nx = $nx / $size;
        $ny = $ny / $size;
        $nz = $nz / $size;
    }
    return Arc{
        ax: $ax,
        ay: $ay,
        az: $az,
        bx: $bx,
        by: $by,
        bz: $bz,
        nx: $nx,
        ny: $ny,
        nz: $nz,
        ux: $ny * $az - $nz * $ay,
        uy: $nz * $ax - $nx * $az,
        uz: $nx * $ay - $ny * $ax,
        wx: $by * $nz - $bz * $ny,
        wy: $bz * $nx - $bx * $nz,
        wz: $bx * $ny - $by * $nx,
        degenerate: $size == 0.0
    };
}

/**
 * The squared chord, on the unit sphere, from a vector to an arc.
 *
 * When the point's foot on the great circle lies on the arc, with `s = p . n`
 * the sine of its angle off the circle, the squared chord is
 * `2 s^2 / (1 + sqrt(1 - s^2))` (the cancellation-free form of `2 - 2 cos`).
 * Otherwise it is the squared chord to the nearer end; for a degenerate arc,
 * to its start.
 *
 * @param arc {Arc} the arc
 * @param px {float} the point's x
 * @param py {float} the point's y
 * @param pz {float} the point's z
 * @return {float} the squared chord, 0.0 to 4.0
 */
func chordToArc(arc as Arc, px as float, py as float, pz as float) {
    if (not $arc.degenerate and $px * $arc.ux + $py * $arc.uy + $pz * $arc.uz >= 0.0 and
        $px * $arc.wx + $py * $arc.wy + $pz * $arc.wz >= 0.0) {
        def s as float init math.min(1.0, math.abs($px * $arc.nx + $py * $arc.ny + $pz * $arc.nz));
        return 2.0 * $s * $s / (1.0 + math.sqrt(1.0 - $s * $s));
    }
    def dx as float init $px - $arc.ax;
    def dy as float init $py - $arc.ay;
    def dz as float init $pz - $arc.az;
    def toA as float init $dx * $dx + $dy * $dy + $dz * $dz;
    if ($arc.degenerate) {
        return $toA;
    }
    $dx = $px - $arc.bx;
    $dy = $py - $arc.by;
    $dz = $pz - $arc.bz;
    return math.min($toA, $dx * $dx + $dy * $dy + $dz * $dz);
}

/**
 * How far a point lies from the great-circle arc between two others, in
 * metres.
 *
 * Measured to the **arc**, not to the whole great circle: a point whose foot
 * on the circle falls outside the arc is measured to the nearer end. Solved on
 * the sphere through unit vectors, so it holds for an arc of any length.
 * {@link crossTrackDistance} is the other question: distance to the great
 * circle, what a navigator means by cross-track error. {@link simplify}
 * applies the same measure, as squared chords, through {@link furthestFrom}.
 *
 * @param p {Point} the point to measure
 * @param a {Point} one end of the arc
 * @param b {Point} the other end of the arc
 * @return {float} the distance in metres
 */
func segmentOffset(p as Point, a as Point, b as Point) {
    def path as UnitVectors init unitVectors([$a, $p, $b]);
    def chord as float init chordToArc(arcOf($path, 0, 2), $path.xs[1], $path.ys[1], $path.zs[1]);
    return 2.0 * math.asin(clampUnit(math.sqrt($chord) / 2.0)) * EARTH_RADIUS;
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
 * The most points {@link resample} returns.
 *
 * The output's size is set by the caller's spacing, not by the input: a 100 km
 * track at 1 mm spacing asks for 100 million points. A path whose length over
 * `spacing` reaches this is refused before any point is built.
 */
export def const MAX_RESAMPLE_POINTS as int init 1000000;

/**
 * Resample a path to a fixed spacing.
 *
 * Emits a point every `spacing` metres along the path, measured from the
 * first point, interpolated along the leg it falls on, plus the original
 * first and last points. A sample that lands exactly on an inner vertex is
 * emitted there. Interpolated points carry coordinates, and an elevation when
 * both ends of their leg had one; no time and no name. A path of fewer than
 * two points is returned as is.
 *
 * @param points {list of Point} the path to resample, in order
 * @param spacing {float} how far apart the results should be, in metres
 * @return {list of Point} the resampled path
 * @throws {Error} when the spacing is not positive, or when the path's length
 *   divided by `spacing` reaches {@link MAX_RESAMPLE_POINTS} - 1
 */
export func resample(points as list of Point, spacing as float) {
    if ($spacing <= 0.0) {
        fail("resample spacing " + decimal($spacing, 2) + " is not positive");
    }
    if (len($points) < 2) {
        return $points;
    }
    def legs as list of float init [];
    def total as float init 0.0;
    for (def i as int init 1; $i < len($points); $i = $i + 1) {
        def leg as float init distance($points[$i - 1], $points[$i]);
        $legs[] = $leg;
        $total = $total + $leg;
    }
    # divided, not multiplied: spacing * MAX could overflow, which raises
    if ($total / convert.toFloat(MAX_RESAMPLE_POINTS - 1) >= $spacing) {
        fail("resample spacing " + convert.toString($spacing) + " m over a " +
            convert.toString(math.round($total)) + " m path exceeds MAX_RESAMPLE_POINTS (" +
            convert.toString(MAX_RESAMPLE_POINTS) + ")");
    }
    def out as list of Point init [$points[0]];
    def last as int init len($points) - 1;
    # how far past the current leg's start the next sample lies
    def ahead as float init $spacing;
    for (def i as int init 1; $i <= $last; $i = $i + 1) {
        def leg as float init $legs[$i - 1];
        def at as float init $ahead;
        # each sample is offset + k * spacing, not a running sum: a sum stops
        # advancing once spacing falls below the rounding step of the total
        def k as int init 0;
        while ($at < $leg or ($at == $leg and $i < $last)) {
            $out[] = interpolate($points[$i - 1], $points[$i], $at / $leg);
            $k = $k + 1;
            $at = $ahead + convert.toFloat($k) * $spacing;
        }
        $ahead = $at - $leg;
    }
    $out[] = $points[$last];
    return $out;
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
