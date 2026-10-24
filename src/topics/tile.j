# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - Web Mercator map tiles, the addressing every slippy map uses.
# Spliced into geo.j via include - not a standalone module.

/**
 * The northern and southern limit of Web Mercator, in degrees.
 *
 * The projection sends the poles to infinity, so every tile scheme cuts it off
 * here. A latitude past this is clamped rather than refused: a track that runs
 * into the Arctic still has tiles; they are the top row.
 */
export def const MERCATOR_LIMIT as float init 85.0511287798;

/** The largest zoom level a tile address is defined for. */
export def const MAX_ZOOM as int init 22;

/**
 * One map tile.
 *
 * The addressing OpenStreetMap, Google Maps and every other slippy map share:
 * at zoom `z` the world is a grid of `2^z` by `2^z` tiles, `x` counting east
 * from the antimeridian and `y` counting south from the top.
 *
 * @field x {int} how far east, 0 to 2^z - 1
 * @field y {int} how far south, 0 to 2^z - 1
 * @field z {int} the zoom level
 */
export def struct Tile {
    x as int,
    y as int,
    z as int
};

/**
 * The tile a point falls in.
 *
 * @param p {Point} the point to locate
 * @param zoom {int} the zoom level, 0 to 22
 * @return {Tile} the tile holding the point
 * @throws {Error} when the zoom is outside 0 to 22
 * @example
 *   def t as geo.Tile init geo.tileOf(geo.point(47.2692, 11.4041), 14);
 *   # https://tile.openstreetmap.org/14/8711/5744.png
 */
export func tileOf(p as Point, zoom as int) {
    checkZoom($zoom);
    def side as int init 1 << $zoom;
    def width as float init convert.toFloat($side);
    def lat as float init clampLatitude($p.lat);
    def x as float init ($p.lon + 180.0) / 360.0 * $width;
    def phi as float init toRadians($lat);
    def mercator as float init math.ln(math.tan($phi) + 1.0 / math.cos($phi));
    def y as float init (1.0 - $mercator / math.PI) / 2.0 * $width;
    return Tile{x: clampIndex($x, $side), y: clampIndex($y, $side), z: $zoom};
}

/**
 * The box a tile covers.
 *
 * @param t {Tile} the tile
 * @return {Bounds} the box, in degrees
 * @throws {Error} when the tile's zoom or indices are out of range
 * @example
 *   def box as geo.Bounds init geo.tileBounds(geo.tileOf($p, 14));
 */
export func tileBounds(t as Tile) {
    checkZoom($t.z);
    def side as int init 1 << $t.z;
    if ($t.x < 0 or $t.x >= $side or $t.y < 0 or $t.y >= $side) {
        fail("tile " + convert.toString($t.x) + "/" + convert.toString($t.y) + " is outside zoom " +
            convert.toString($t.z));
    }
    def width as float init convert.toFloat($side);
    def west as float init convert.toFloat($t.x) / $width * 360.0 - 180.0;
    def east as float init convert.toFloat($t.x + 1) / $width * 360.0 - 180.0;
    return Bounds{
        minLat: tileLatitude($t.y + 1, $width),
        minLon: $west,
        maxLat: tileLatitude($t.y, $width),
        maxLon: $east
    };
}

/**
 * The latitude of a horizontal tile edge.
 *
 * @param row {int} the edge's row index, 0 at the top
 * @param width {float} how many tiles span the world at this zoom
 * @return {float} the latitude in degrees
 */
func tileLatitude(row as int, width as float) {
    def n as float init math.PI * (1.0 - 2.0 * convert.toFloat($row) / $width);
    return toDegrees(math.atan(math.sinh($n)));
}

/**
 * A tile as a Bing Maps quadkey.
 *
 * The same address written as one string, which is how Bing and a few tile
 * caches name their tiles. Each character descends one zoom level.
 *
 * @param t {Tile} the tile
 * @return {string} the quadkey, one character per zoom level
 * @throws {Error} when the zoom is outside 0 to 22
 * @example
 *   geo.quadkey(geo.Tile{x: 8711, y: 5744, z: 14});   # "12023002220111"
 */
export func quadkey(t as Tile) {
    checkZoom($t.z);
    def out as string init "";
    for (def level as int init $t.z; $level > 0; $level = $level - 1) {
        def mask as int init 1 << ($level - 1);
        def digit as int init 0;
        if (($t.x & $mask) != 0) {
            $digit = $digit + 1;
        }
        if (($t.y & $mask) != 0) {
            $digit = $digit + 2;
        }
        $out = $out + convert.toString($digit);
    }
    return $out;
}

/**
 * Check that a zoom level is one a tile address is defined for.
 *
 * @param zoom {int} the level to check
 * @throws {Error} when it is outside 0 to 22
 */
func checkZoom(zoom as int) {
    if ($zoom < 0 or $zoom > MAX_ZOOM) {
        fail("zoom " + convert.toString($zoom) + " is outside 0..22");
    }
}

/**
 * A latitude, clamped to where Web Mercator is defined.
 *
 * @param lat {float} the latitude in degrees
 * @return {float} the latitude, inside the projection's limits
 */
func clampLatitude(lat as float) {
    return math.max(-MERCATOR_LIMIT, math.min(MERCATOR_LIMIT, $lat));
}

/**
 * A fractional tile coordinate as an index inside the grid.
 *
 * @param value {float} the fractional coordinate
 * @param side {int} how many tiles span the world at this zoom
 * @return {int} the index, 0 to `side` - 1
 */
func clampIndex(value as float, side as int) {
    def index as int init math.floor($value);
    if ($index < 0) {
        return 0;
    }
    if ($index >= $side) {
        return $side - 1;
    }
    return $index;
}
