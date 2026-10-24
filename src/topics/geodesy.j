# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - distances, bearings and dead reckoning on a spherical Earth.
# Spliced into geo.j via include - not a standalone module.

/**
 * The Earth's mean radius in metres, IUGG R1.
 *
 * Every distance and bearing in this deck is computed on a sphere of this
 * radius. Against the WGS 84 ellipsoid that is typically within 0.3 percent,
 * at most about 0.5 percent.
 */
export def const EARTH_RADIUS as float init 6371008.8;

/** Metres in one nautical mile. */
export def const NAUTICAL_MILE as float init 1852.0;

/**
 * Degrees to radians.
 *
 * @param degrees {float} the angle in degrees
 * @return {float} the same angle in radians
 */
export func toRadians(degrees as float) {
    return $degrees * math.PI / 180.0;
}

/**
 * Radians to degrees.
 *
 * @param radians {float} the angle in radians
 * @return {float} the same angle in degrees
 */
export func toDegrees(radians as float) {
    return $radians * 180.0 / math.PI;
}

/**
 * The great-circle distance between two coordinate pairs, in metres.
 *
 * The haversine formula on a sphere of radius {@link EARTH_RADIUS}. It stays
 * well conditioned for legs of a few metres, where the `acos` of the spherical
 * law of cosines does not.
 *
 * @param aLat {float} the first latitude in degrees
 * @param aLon {float} the first longitude in degrees
 * @param bLat {float} the second latitude in degrees
 * @param bLon {float} the second longitude in degrees
 * @return {float} the distance in metres, never negative
 * @example
 *   geo.haversine(47.2692, 11.4041, 48.2082, 16.3738);   # 385943.7...
 */
export func haversine(aLat as float, aLon as float, bLat as float, bLon as float) {
    def phi1 as float init toRadians($aLat);
    def phi2 as float init toRadians($bLat);
    def dPhi as float init toRadians($bLat - $aLat);
    def dLambda as float init toRadians($bLon - $aLon);
    def sinPhi as float init math.sin($dPhi / 2.0);
    def sinLambda as float init math.sin($dLambda / 2.0);
    def h as float init $sinPhi * $sinPhi +
        math.cos($phi1) * math.cos($phi2) * $sinLambda * $sinLambda;
    # Two points a few centimetres apart reach h slightly past 1.0 by
    # rounding, and math.sqrt of a negative raises rather than returning a NaN.
    def unit as float init clampUnit($h);
    return 2.0 * EARTH_RADIUS * math.atan2(math.sqrt($unit), math.sqrt(1.0 - $unit));
}

/**
 * The great-circle distance between two points, in metres.
 *
 * @param a {Point} where to measure from
 * @param b {Point} where to measure to
 * @return {float} the distance in metres, never negative
 * @example
 *   def km as float init geo.distance($innsbruck, $vienna) / 1000.0;
 */
export func distance(a as Point, b as Point) {
    return haversine($a.lat, $a.lon, $b.lat, $b.lon);
}

/**
 * The initial bearing from one point to another, in degrees.
 *
 * The heading to set off on, clockwise from true north. On a great circle it
 * differs from the heading on arrival ({@link finalBearing}). Two equal points
 * give 0.
 *
 * @param a {Point} where to set off from
 * @param b {Point} where to arrive
 * @return {float} the bearing in degrees, 0.0 <= result < 360.0
 * @example
 *   geo.bearing($innsbruck, $vienna);   # 72.5...
 */
export func bearing(a as Point, b as Point) {
    def phi1 as float init toRadians($a.lat);
    def phi2 as float init toRadians($b.lat);
    def dLambda as float init toRadians($b.lon - $a.lon);
    def y as float init math.sin($dLambda) * math.cos($phi2);
    def northward as float init math.cos($phi1) * math.sin($phi2);
    def inward as float init math.sin($phi1) * math.cos($phi2) * math.cos($dLambda);
    def x as float init $northward - $inward;
    if ($y == 0.0 and $x == 0.0) {
        return 0.0;
    }
    return normalizeBearing(toDegrees(math.atan2($y, $x)));
}

/**
 * The bearing to steer on arrival, in degrees.
 *
 * The initial bearing of the reverse leg, turned around.
 *
 * @param a {Point} where the leg started
 * @param b {Point} where it ends
 * @return {float} the bearing in degrees, 0.0 <= result < 360.0
 */
export func finalBearing(a as Point, b as Point) {
    # Two equal points have no direction; agree with bearing() and say 0, not
    # the 180 that turning a 0 around would give.
    if ($a.lat == $b.lat and $a.lon == $b.lon) {
        return 0.0;
    }
    return normalizeBearing(bearing($b, $a) + 180.0);
}

/**
 * Where you arrive setting off on a bearing and holding it for a distance.
 *
 * Along a great circle. The result carries only coordinates, with the
 * longitude wrapped into -180 to 180.
 *
 * @param from {Point} where to set off
 * @param degrees {float} the bearing to hold, clockwise from true north
 * @param metres {float} how far to travel
 * @return {Point} where you end up
 * @example
 *   def north as geo.Point init geo.destination($start, 0.0, 1000.0);
 */
export func destination(from as Point, degrees as float, metres as float) {
    def angular as float init $metres / EARTH_RADIUS;
    def theta as float init toRadians($degrees);
    def phi1 as float init toRadians($from.lat);
    def lambda1 as float init toRadians($from.lon);
    def sinPhi2 as float init math.sin($phi1) * math.cos($angular) +
        math.cos($phi1) * math.sin($angular) * math.cos($theta);
    def phi2 as float init math.asin(clampUnit($sinPhi2));
    def y as float init math.sin($theta) * math.sin($angular) * math.cos($phi1);
    def x as float init math.cos($angular) - math.sin($phi1) * $sinPhi2;
    def lambda2 as float init $lambda1 + math.atan2($y, $x);
    return point(toDegrees($phi2), normalizeLongitude(toDegrees($lambda2)));
}

/**
 * The point half way along the great circle between two points.
 *
 * @param a {Point} one end
 * @param b {Point} the other end
 * @return {Point} the midpoint, carrying nothing but its coordinates
 */
export func midpoint(a as Point, b as Point) {
    def phi1 as float init toRadians($a.lat);
    def phi2 as float init toRadians($b.lat);
    def lambda1 as float init toRadians($a.lon);
    def dLambda as float init toRadians($b.lon - $a.lon);
    def bx as float init math.cos($phi2) * math.cos($dLambda);
    def by as float init math.cos($phi2) * math.sin($dLambda);
    def x as float init math.cos($phi1) + $bx;
    def phi3 as float init math.atan2(math.sin($phi1) + math.sin($phi2), math.hypot($x, $by));
    def lambda3 as float init $lambda1 + math.atan2($by, $x);
    return point(toDegrees($phi3), normalizeLongitude(toDegrees($lambda3)));
}

/**
 * The total length of a path, in metres.
 *
 * Leg by leg along the list. A list of fewer than two points is zero long.
 *
 * @param points {list of Point} the path, in order
 * @return {float} the sum of every leg, in metres
 * @example
 *   geo.pathLength($segment.points) / 1000.0;   # kilometres walked
 */
export func pathLength(points as list of Point) {
    def total as float init 0.0;
    for (def i as int init 1; $i < len($points); $i = $i + 1) {
        $total = $total + distance($points[$i - 1], $points[$i]);
    }
    return $total;
}

/**
 * The length of a track, in metres, measured per segment.
 *
 * The gap between two segments is where the recorder lost its fix, so it is
 * not counted.
 *
 * @param t {Track} the track to measure
 * @return {float} the sum of every segment's length, in metres
 */
export func trackDistance(t as Track) {
    def total as float init 0.0;
    for (def seg in $t.segments) {
        $total = $total + pathLength($seg.points);
    }
    return $total;
}
