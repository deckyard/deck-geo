# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - white-box tests for the geohash topic.
# Spliced into geo_test.j via include - run with:
#   jennifer test src/geo_test.j

func testGeohashOfAKnownPlace() {
    # Innsbruck; every geohash implementation agrees on this string
    testing.assertEqual(geohash(point(47.2692, 11.4041), 7), "u22hgt0");
}

func testGeohashOfTheOrigin() {
    # 0,0 sits at the corner of four cells and hashes to the start of s
    testing.assertEqual(geohash(point(0.0, 0.0), 1), "s");
}

func testGeohashLengthIsTheLengthAsked() {
    def p as Point init point(47.2692, 11.4041);
    for (def n in [1, 2, 5, 9, 12, 20]) {
        testing.assertEqual(len(geohash($p, $n)), $n);
    }
}

func testGeohashIsAPrefixCode() {
    # a shorter hash of the same point is a prefix of a longer one, which is
    # the whole property a proximity search by prefix depends on
    def p as Point init point(47.2692, 11.4041);
    def long as string init geohash($p, 9);
    for (def n in [1, 3, 6, 8]) {
        testing.assertEqual(geohash($p, $n), strings.substring($long, 0, $n));
    }
}

func testNeighboursShareAPrefix() {
    def here as Point init point(47.2692, 11.4041);
    def near as Point init destination($here, 45.0, 20.0);
    testing.assertEqual(
        strings.substring(geohash($here, 6), 0, 6),
        strings.substring(geohash($near, 6), 0, 6));
}

func failOnZeroLengthGeohash() {
    geohash(point(0.0, 0.0), 0);
}

func failOnOverlongGeohash() {
    geohash(point(0.0, 0.0), 21);
}

func testGeohashRejectsALengthItCannotWrite() {
    testing.assertThrows("failOnZeroLengthGeohash", ERROR_KIND);
    testing.assertThrows("failOnOverlongGeohash", ERROR_KIND);
}

func testGeohashBoundsHoldsThePointThatMadeIt() {
    def p as Point init point(47.2692, 11.4041);
    def box as Bounds init geohashBounds(geohash($p, 9));
    testing.assertTrue(containsPoint($box, $p));
}

func testGeohashBoundsNarrowWithLength() {
    def p as Point init point(47.2692, 11.4041);
    def coarse as Bounds init geohashBounds(geohash($p, 3));
    def fine as Bounds init geohashBounds(geohash($p, 8));
    testing.assertTrue($coarse.maxLat - $coarse.minLat > $fine.maxLat - $fine.minLat);
    testing.assertTrue(containsPoint($coarse, boundsCenter($fine)));
}

func testGeohashBoundsOfOneCharacterIsAQuarterOfTheWorld() {
    def box as Bounds init geohashBounds("s");
    testing.assertEqual($box.minLat, 0.0);
    testing.assertEqual($box.maxLat, 45.0);
    testing.assertEqual($box.minLon, 0.0);
    testing.assertEqual($box.maxLon, 45.0);
}

func testGeohashBoundsIgnoresCase() {
    def lower as Bounds init geohashBounds("u22hgt0");
    def upper as Bounds init geohashBounds("U22HGT0");
    testing.assertEqual($lower.minLat, $upper.minLat);
    testing.assertEqual($lower.maxLon, $upper.maxLon);
}

func failOnEmptyGeohash() {
    geohashBounds("");
}

func failOnGeohashWithAnI() {
    # a, i, l and o are not in the alphabet, which is the point of it
    geohashBounds("u2i");
}

func testGeohashBoundsRejectsWhatIsNotAGeohash() {
    testing.assertThrows("failOnEmptyGeohash", ERROR_KIND);
    testing.assertThrows("failOnGeohashWithAnI", ERROR_KIND);
}

func testGeohashDecodeIsAccurateToTheCellSize() {
    def p as Point init point(47.2692, 11.4041);
    def back as Point init geohashDecode(geohash($p, 9));
    # nine characters locates a point to about five metres
    testing.assertTrue(distance($p, $back) < 5.0);
}

func testGeohashDecodeAndEncodeAreStable() {
    def hash as string init "u22hgt0";
    testing.assertEqual(geohash(geohashDecode($hash), len($hash)), $hash);
}

func testGeohashAlphabetHasNoLookalikes() {
    testing.assertEqual(len(GEOHASH_ALPHABET), 32);
    testing.assertEqual(GEOHASH_LENGTH, 9);
    for (def ch in ["a", "i", "l", "o"]) {
        testing.assertEqual(strings.indexOf(GEOHASH_ALPHABET, $ch), -1);
    }
}

func testHalveSelectsTheRightHalf() {
    testing.assertEqual(halve(0.0, 10.0, 1), [5.0, 10.0]);
    testing.assertEqual(halve(0.0, 10.0, 0), [0.0, 5.0]);
}
