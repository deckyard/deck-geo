# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - geohashes: a coordinate as a short string that sorts by locality.
# Spliced into geo.j via include - not a standalone module.

/**
 * The 32 characters a geohash is spelled with.
 *
 * Base 32 without `a`, `i`, `l` and `o`, so no letter in a hash copied by
 * hand can be mistaken for `1` or `0`.
 */
export def const GEOHASH_ALPHABET as string init "0123456789bcdefghjkmnpqrstuvwxyz";

/** A default length to pass to {@link geohash}: a cell of about 4.8 m. */
export def const GEOHASH_LENGTH as int init 9;

/**
 * A point as a geohash.
 *
 * Each character adds five bits, alternating longitude and latitude, so
 * nearby places share a prefix and truncating a hash coarsens it. Nine
 * characters give a cell of about 4.8 m by 4.8 m at the equator, six about
 * 1.2 km by 0.6 km.
 *
 * Two points either side of a cell edge share no prefix however close they
 * are; check the neighbouring cells too when that matters.
 *
 * @param p {Point} the point to encode
 * @param length {int} how many characters to write, 1 to 20
 * @return {string} the geohash
 * @throws {Error} when the length is outside 1 to 20
 * @example
 *   geo.geohash(geo.point(47.2692, 11.4041), 7);   # "u22hgt0"
 */
export func geohash(p as Point, length as int) {
    if ($length < 1 or $length > 20) {
        fail("geohash length " + convert.toString($length) + " is outside 1..20");
    }
    def minLat as float init -90.0;
    def maxLat as float init 90.0;
    def minLon as float init -180.0;
    def maxLon as float init 180.0;
    def out as string init "";
    def bit as int init 0;
    def value as int init 0;
    def even as bool init true;
    while (len($out) < $length) {
        if ($even) {
            def midLon as float init ($minLon + $maxLon) / 2.0;
            if ($p.lon >= $midLon) {
                $value = $value * 2 + 1;
                $minLon = $midLon;
            } else {
                $value = $value * 2;
                $maxLon = $midLon;
            }
        } else {
            def midLat as float init ($minLat + $maxLat) / 2.0;
            if ($p.lat >= $midLat) {
                $value = $value * 2 + 1;
                $minLat = $midLat;
            } else {
                $value = $value * 2;
                $maxLat = $midLat;
            }
        }
        $even = not $even;
        $bit = $bit + 1;
        if ($bit == 5) {
            $out = $out + strings.substring(GEOHASH_ALPHABET, $value, $value + 1);
            $bit = 0;
            $value = 0;
        }
    }
    return $out;
}

/**
 * The box a geohash names.
 *
 * @param hash {string} the geohash to decode
 * @return {Bounds} the box the hash covers
 * @throws {Error} when the hash is empty or holds a character the alphabet has no place for
 * @example
 *   def box as geo.Bounds init geo.geohashBounds("u22hgt0");
 */
export func geohashBounds(hash as string) {
    if (len($hash) == 0) {
        fail("an empty string is not a geohash");
    }
    def minLat as float init -90.0;
    def maxLat as float init 90.0;
    def minLon as float init -180.0;
    def maxLon as float init 180.0;
    def even as bool init true;
    for (def ch in strings.chars(strings.lower($hash))) {
        def value as int init strings.indexOf(GEOHASH_ALPHABET, $ch);
        if ($value < 0) {
            fail("\"" + $ch + "\" is not a geohash character");
        }
        for (def shift as int init 4; $shift >= 0; $shift = $shift - 1) {
            def bit as int init ($value >> $shift) & 1;
            if ($even) {
                def lon as list of float init halve($minLon, $maxLon, $bit);
                $minLon = $lon[0];
                $maxLon = $lon[1];
            } else {
                def lat as list of float init halve($minLat, $maxLat, $bit);
                $minLat = $lat[0];
                $maxLat = $lat[1];
            }
            $even = not $even;
        }
    }
    return Bounds{minLat: $minLat, minLon: $minLon, maxLat: $maxLat, maxLon: $maxLon};
}

/**
 * The half of a range one geohash bit selects.
 *
 * @param low {float} the range's lower edge
 * @param high {float} the range's upper edge
 * @param bit {int} `1` for the upper half, `0` for the lower
 * @return {list of float} the new lower and upper edge
 */
func halve(low as float, high as float, bit as int) {
    def middle as float init ($low + $high) / 2.0;
    if ($bit == 1) {
        return [$middle, $high];
    }
    return [$low, $middle];
}

/**
 * The centre of the box a geohash names.
 *
 * A geohash names a box, not a point, so the result is off by up to half a
 * box. Encoding it at the same length gives the hash back.
 *
 * @param hash {string} the geohash to decode
 * @return {Point} the centre of the box
 * @throws {Error} when the hash is empty or holds an unknown character
 * @example
 *   def p as geo.Point init geo.geohashDecode("u22hgt0");
 */
export func geohashDecode(hash as string) {
    return boundsCenter(geohashBounds($hash));
}
