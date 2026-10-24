<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Addressing

Two ways to turn a coordinate into a key a database can index.

## Geohashes

```jennifer
geo.geohash(geo.point(47.2692, 11.4041), 7);   # "u22hgt0"
```

Each character narrows the cell a point lies in, alternating longitude and
latitude bits, five bits per character. `length` is 1 to 20; anything else
raises. `GEOHASH_LENGTH` (9) is a sensible default to pass: nine characters
give a cell of about 4.8 m by 4.8 m at the equator, six about 1.2 km by
0.6 km.

Nearby points share a prefix, so a prefix scan is a proximity search and
truncating a hash coarsens it:

```jennifer
def hash as string init geo.geohash($p, 9);
strings.substring($hash, 0, 5);   # the same as geo.geohash($p, 5)
```

(`testGeohashIsAPrefixCode`.)

The alphabet (`GEOHASH_ALPHABET`) is base 32 without `a`, `i`, `l` and `o`,
so a hash read aloud or copied by hand has no letter to confuse with `1` or
`0`.

### Cell edges

Two points either side of a cell boundary share no prefix however close they
are; across the equator or the prime meridian they differ in the first
character. That follows from recursive subdivision, not from this
implementation. A prefix scan finds most of what is near a point but not all
of it: when that matters, also check the neighbouring cells, or query a
bounding box from `bounds`.

### Decoding

A geohash names a cell, not a point:

```jennifer
def box as geo.Bounds init geo.geohashBounds("u22hgt0");
def middle as geo.Point init geo.geohashDecode("u22hgt0");
```

`geohashDecode` returns the centre of the cell, so it is off by up to half a
cell; encoding that centre at the same length gives the hash back. Both accept
upper case and raise on an empty string or a character outside the alphabet.

## Map tiles

```jennifer
def t as geo.Tile init geo.tileOf(geo.point(47.2692, 11.4041), 14);
```

That is tile `14/8711/5744` in the Web Mercator (EPSG:3857) scheme that
OpenStreetMap, Google Maps and other slippy maps share: at zoom `z` the world
is a grid of 2^z by 2^z tiles, `x` counting east from the antimeridian and `y`
south from the top.

```
https://tile.openstreetmap.org/14/8711/5744.png
```

Zoom runs from 0 to `MAX_ZOOM` (22); anything else raises. `tileBounds`
returns the latitude and longitude box a tile covers, and raises on an `x` or
`y` outside the grid. `quadkey` writes the same address as the single string
Bing Maps and some tile caches use, one digit per zoom level:

```jennifer
geo.quadkey(geo.Tile{x: 8711, y: 5744, z: 14});   # "12023002220111"
```

A parent tile's quadkey is a prefix of its children's, as with geohashes.
`quadkey` checks the zoom only, not `x` and `y`.

### The Mercator limit

Web Mercator sends the poles to infinity, so it stops at `MERCATOR_LIMIT`,
85.0511287798 degrees north and south. `tileOf` clamps a latitude beyond it
instead of raising: a track into the high Arctic lands in the top row. The
poles themselves need another projection.

## Which to use

Geohashes suit a key in a store with prefix or range queries, and a short
location that can be read out. Tiles suit fetching or caching map imagery and
bucketing points at a fixed scale. Neither is a spatial index for exact
nearest-neighbour queries.
