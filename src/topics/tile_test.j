# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# geo - white-box tests for the tile topic.
# Spliced into geo_test.j via include - run with:
#   jennifer test src/geo_test.j

func testTileOfZeroZoomIsTheWholeWorld() {
    def t as Tile init tileOf(point(47.2692, 11.4041), 0);
    testing.assertEqual($t.x, 0);
    testing.assertEqual($t.y, 0);
    testing.assertEqual($t.z, 0);
}

func testTileOfAKnownPlace() {
    # Innsbruck at zoom 14 is tile 8711/5744 on every slippy map
    def t as Tile init tileOf(point(47.2692, 11.4041), 14);
    testing.assertEqual($t.x, 8711);
    testing.assertEqual($t.y, 5744);
    testing.assertEqual($t.z, 14);
}

func testTileQuadrantsAtZoomOne() {
    # x counts east from the antimeridian, y south from the top
    testing.assertEqual(tileOf(point(45.0, -90.0), 1), Tile{x: 0, y: 0, z: 1});
    testing.assertEqual(tileOf(point(45.0, 90.0), 1), Tile{x: 1, y: 0, z: 1});
    testing.assertEqual(tileOf(point(-45.0, -90.0), 1), Tile{x: 0, y: 1, z: 1});
    testing.assertEqual(tileOf(point(-45.0, 90.0), 1), Tile{x: 1, y: 1, z: 1});
}

func testTileOfClampsBeyondTheMercatorLimit() {
    # the projection sends the poles to infinity, so the top row is the answer
    def northPole as Tile init tileOf(point(90.0, 0.0), 4);
    testing.assertEqual($northPole.y, 0);
    def southPole as Tile init tileOf(point(-90.0, 0.0), 4);
    testing.assertEqual($southPole.y, 15);
}

func testTileOfStaysInsideTheGridAtTheAntimeridian() {
    def east as Tile init tileOf(point(0.0, 180.0), 3);
    testing.assertEqual($east.x, 7);
    def west as Tile init tileOf(point(0.0, -180.0), 3);
    testing.assertEqual($west.x, 0);
}

func failOnNegativeZoom() {
    tileOf(point(0.0, 0.0), -1);
}

func failOnOverlargeZoom() {
    tileOf(point(0.0, 0.0), 23);
}

func testTileOfRejectsAZoomItCannotAddress() {
    testing.assertThrows("failOnNegativeZoom", ERROR_KIND);
    testing.assertThrows("failOnOverlargeZoom", ERROR_KIND);
}

func testTileBoundsOfZoomZeroSpansTheProjection() {
    def box as Bounds init tileBounds(Tile{x: 0, y: 0, z: 0});
    testing.assertEqual($box.minLon, -180.0);
    testing.assertEqual($box.maxLon, 180.0);
    testing.assertTrue(math.abs($box.maxLat - MERCATOR_LIMIT) < 0.0001);
    testing.assertTrue(math.abs($box.minLat + MERCATOR_LIMIT) < 0.0001);
}

func testTileBoundsHoldsThePointThatMadeIt() {
    def p as Point init point(47.2692, 11.4041);
    for (def zoom in [1, 8, 14, 19]) {
        testing.assertTrue(containsPoint(tileBounds(tileOf($p, $zoom)), $p));
    }
}

func testNeighbouringTilesShareAnEdge() {
    def box as Bounds init tileBounds(Tile{x: 8711, y: 5744, z: 14});
    def right as Bounds init tileBounds(Tile{x: 8712, y: 5744, z: 14});
    def below as Bounds init tileBounds(Tile{x: 8711, y: 5745, z: 14});
    testing.assertEqual($box.maxLon, $right.minLon);
    testing.assertEqual($box.minLat, $below.maxLat);
}

func failOnTileOutsideItsZoom() {
    tileBounds(Tile{x: 4, y: 0, z: 2});
}

func testTileBoundsRejectsAnIndexOutsideTheGrid() {
    testing.assertThrows("failOnTileOutsideItsZoom", ERROR_KIND);
}

func testQuadkeyIsOneCharacterPerZoomLevel() {
    testing.assertEqual(quadkey(Tile{x: 0, y: 0, z: 0}), "");
    testing.assertEqual(quadkey(Tile{x: 8711, y: 5744, z: 14}), "12023002220111");
}

func testQuadkeyOfTheFourQuadrants() {
    testing.assertEqual(quadkey(Tile{x: 0, y: 0, z: 1}), "0");
    testing.assertEqual(quadkey(Tile{x: 1, y: 0, z: 1}), "1");
    testing.assertEqual(quadkey(Tile{x: 0, y: 1, z: 1}), "2");
    testing.assertEqual(quadkey(Tile{x: 1, y: 1, z: 1}), "3");
}

func testQuadkeyDescendsFromItsParent() {
    def parent as Tile init Tile{x: 8711, y: 5744, z: 14};
    def child as Tile init Tile{x: 17422, y: 11489, z: 15};
    testing.assertEqual(strings.substring(quadkey($child), 0, 14), quadkey($parent));
}

func testClampIndexAndClampLatitude() {
    testing.assertEqual(clampIndex(-0.5, 4), 0);
    testing.assertEqual(clampIndex(1.7, 4), 1);
    testing.assertEqual(clampIndex(9.0, 4), 3);
    testing.assertEqual(clampLatitude(90.0), MERCATOR_LIMIT);
    testing.assertEqual(clampLatitude(-90.0), -MERCATOR_LIMIT);
    testing.assertEqual(clampLatitude(47.2692), 47.2692);
}

func testZoomConstants() {
    testing.assertEqual(MAX_ZOOM, 22);
    testing.assertEqual(MERCATOR_LIMIT, 85.0511287798);
}
