<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Cheatsheet

Every export of `@deckyard/geo`, by topic, called through the import alias:
`import "@deckyard/geo/" as geo;` then `geo.open(path)`. Coordinates are WGS 84
degrees, latitude before longitude in every signature; distances are metres.

## Version

| Constant | Value | Meaning |
|---|---|---|
| `VERSION` | `"0.1.0"` | The version of this deck. |

## Errors and precision

| Constant | Value | Meaning |
|---|---|---|
| `ERROR_KIND` | `"geo"` | The `kind` every `Error` this deck raises carries. |
| `COORD_PLACES` | `7` | How many decimal places a latitude or longitude is written with. |
| `ELEVATION_PLACES` | `2` | How many decimal places an elevation is written with. |
| `MAX_NESTING` | `100` | How deeply a document may nest containers before a reader raises. |

## The model

See [The model](../guide/model.md).

### `Point`

One position on the Earth, with whatever the file said about it.

| Field | Holds |
|---|---|
| `lat as float` | degrees north of the equator, -90 to 90 |
| `lon as float` | degrees east of Greenwich, -180 to 180 |
| `ele as float` | elevation in metres, as the source gives it; no datum conversion |
| `hasElevation as bool` | whether `ele` came from the source |
| `at as string` | when the point was recorded, as RFC 3339 |
| `hasTime as bool` | whether `at` came from the source |
| `name as string` | what the source called it |
| `desc as string` | a longer description |
| `sym as string` | the symbol or style name to draw it with |

### `Segment`

One unbroken run of track points.

| Field | Holds |
|---|---|
| `points as list of Point` | the positions, in the order recorded |

### `Track`

A recorded path: where something went.

| Field | Holds |
|---|---|
| `name as string` | what the source called it |
| `desc as string` | a longer description |
| `kind as string` | the activity, as GPX `<type>` spells it |
| `segments as list of Segment` | the runs of points, in order |

### `Route`

A planned path: where something is meant to go.

| Field | Holds |
|---|---|
| `name as string` | what the source called it |
| `desc as string` | a longer description |
| `points as list of Point` | the points to visit, in order |

### `Document`

A whole file, in the shape every codec in this deck reads and writes.

| Field | Holds |
|---|---|
| `name as string` | the document title |
| `desc as string` | a longer description |
| `creator as string` | what wrote the file |
| `at as string` | when the file was written, as RFC 3339 |
| `waypoints as list of Point` | standalone points of interest |
| `routes as list of Route` | planned paths |
| `tracks as list of Track` | recorded paths |

### `Bounds`

A latitude and longitude rectangle.

| Field | Holds |
|---|---|
| `minLat as float` | the southern edge |
| `minLon as float` | the western edge |
| `maxLat as float` | the northern edge |
| `maxLon as float` | the eastern edge |

| Signature | Returns | Does |
|---|---|---|
| `point(lat, lon)` | `Point` | One point; raises outside -90..90 / -180..180. |
| `named(p, name)` | `Point` | The same point, named. |
| `withElevation(p, metres)` | `Point` | The same point, at a stated elevation; raises beyond 1,000,000 m. |
| `withTime(p, at)` | `Point` | The same point, at a stated RFC 3339 time. |
| `document()` | `Document` | An empty document. |
| `track(name, points)` | `Track` | One track, from a list of points, as a single segment. |
| `route(name, points)` | `Route` | One route, from a list of points. |
| `trackPoints(t)` | `list of Point` | Every point of a track, segments run together. |
| `documentPoints(doc)` | `list of Point` | Every point a document holds, whatever it holds it as. |
| `describe(doc)` | `string` | One line saying what a document holds. |

## Geodesy

On a sphere of radius `EARTH_RADIUS`. See [Measuring](../guide/measuring.md).

| Constant | Value | Meaning |
|---|---|---|
| `EARTH_RADIUS` | `6371008.8` | The Earth's mean radius in metres, IUGG R1. |
| `NAUTICAL_MILE` | `1852.0` | Metres in one nautical mile. |

| Signature | Returns | Does |
|---|---|---|
| `toRadians(degrees)` | `float` | Degrees to radians. |
| `toDegrees(radians)` | `float` | Radians to degrees. |
| `haversine(aLat, aLon, bLat, bLon)` | `float` | The great-circle distance between two coordinate pairs, in metres, by the haversine formula. |
| `distance(a, b)` | `float` | The great-circle distance between two points, in metres. |
| `bearing(a, b)` | `float` | The initial bearing from one point to another, in degrees from true north, 0 <= result < 360. |
| `finalBearing(a, b)` | `float` | The bearing to steer on arrival, in degrees. |
| `destination(from, degrees, metres)` | `Point` | Where you arrive setting off on a bearing and holding it for a distance. |
| `midpoint(a, b)` | `Point` | The point half way along the great circle between two points. |
| `pathLength(points)` | `float` | The total length of a path, in metres. |
| `trackDistance(t)` | `float` | The length of a track, in metres, measured per segment. |

## Geometry

| Signature | Returns | Does |
|---|---|---|
| `bounds(points)` | `Bounds` | The smallest latitude and longitude rectangle holding every point. |
| `containsPoint(box, p)` | `bool` | Whether a rectangle holds a point, edges included. |
| `boundsCenter(box)` | `Point` | The centre of a rectangle. |
| `centroid(points)` | `Point` | The mean position of a list of points. |
| `crossTrackDistance(p, a, b)` | `float` | How far a point lies off the great circle through two others, in metres. |
| `simplify(points, tolerance)` | `list of Point` | Ramer-Douglas-Peucker: drop the points that move the path by `tolerance` metres or less. |
| `pointInPolygon(p, polygon)` | `bool` | Whether a point lies inside a polygon. |
| `resample(points, spacing)` | `list of Point` | Resample a path to one point every `spacing` metres. |
| `interpolate(a, b, fraction)` | `Point` | A point a fraction of the way along the line between two others. |

## Track statistics

| Constant | Value | Meaning |
|---|---|---|
| `ASCENT_THRESHOLD` | `3.0` | How much a climb must rise to be counted, in metres. |
| `MOVING_SPEED` | `0.5` | How fast something must be going to count as moving, in metres per second. |

### `TrackStats`

What a recorded path adds up to.

| Field | Holds |
|---|---|
| `points as int` | how many positions it holds |
| `distance as float` | how far it went, in metres |
| `ascent as float` | how much it climbed, in metres |
| `descent as float` | how much it dropped, in metres |
| `minElevation as float` | the lowest elevation, in metres |
| `maxElevation as float` | the highest elevation, in metres |
| `hasElevation as bool` | whether any point carried an elevation |
| `totalSeconds as int` | seconds from the first timed fix to the last |
| `movingSeconds as int` | seconds of that spent at `MOVING_SPEED` or faster |
| `hasTime as bool` | whether the timing fields mean anything |
| `averageSpeed as float` | metres per second over `movingSeconds` |
| `maxSpeed as float` | the fastest leg, in metres per second |

| Signature | Returns | Does |
|---|---|---|
| `statsOf(points)` | `TrackStats` | Measure a recorded path. |
| `statsWith(points, climbThreshold, movingSpeed)` | `TrackStats` | Measure a recorded path, with the thresholds stated. |
| `secondsBetween(from, to2)` | `int` | Seconds between two RFC 3339 timestamps, or `-1` when either does not parse. |

## Geohashes

See [Addressing](../guide/addressing.md).

| Constant | Value | Meaning |
|---|---|---|
| `GEOHASH_ALPHABET` | `"0123456789bcdefghjkmnpqrstuvwxyz"` | The 32 characters a geohash is spelled with. |
| `GEOHASH_LENGTH` | `9` | A default length to pass to `geohash`: a cell of about 4.8 m. |

| Signature | Returns | Does |
|---|---|---|
| `geohash(p, length)` | `string` | A point as a geohash of 1 to 20 characters. |
| `geohashBounds(hash)` | `Bounds` | The box a geohash names. |
| `geohashDecode(hash)` | `Point` | The centre of the box a geohash names. |

## Map tiles

Web Mercator slippy-map tiles. See [Addressing](../guide/addressing.md).

| Constant | Value | Meaning |
|---|---|---|
| `MERCATOR_LIMIT` | `85.0511287798` | The northern and southern limit of Web Mercator, in degrees. |
| `MAX_ZOOM` | `22` | The largest zoom level a tile address is defined for. |

### `Tile`

One map tile.

| Field | Holds |
|---|---|
| `x as int` | how far east, 0 to 2^z - 1 |
| `y as int` | how far south, 0 to 2^z - 1 |
| `z as int` | the zoom level |

| Signature | Returns | Does |
|---|---|---|
| `tileOf(p, zoom)` | `Tile` | The tile a point falls in. |
| `tileBounds(t)` | `Bounds` | The box a tile covers. |
| `quadkey(t)` | `string` | A tile as a Bing Maps quadkey. |

## GPX

Reads GPX 1.0 and 1.1, writes 1.1. See [GPX](../guide/gpx.md).

| Constant | Value | Meaning |
|---|---|---|
| `GPX_NAMESPACE` | `"http://www.topografix.com/GPX/1/1"` | The namespace a GPX 1.1 document declares. |
| `GPX_CREATOR` | `"@deckyard/geo"` | What this deck writes in a GPX `creator` attribute. |

| Signature | Returns | Does |
|---|---|---|
| `readGpx(text)` | `Document` | Read a GPX document. |
| `writeGpx(doc)` | `string` | Write a document as GPX 1.1. |

## KML and KMZ

See [KML and KMZ](../guide/kml.md).

| Constant | Value | Meaning |
|---|---|---|
| `KML_NAMESPACE` | `"http://www.opengis.net/kml/2.2"` | The namespace a KML 2.2 document declares. |
| `KMZ_ENTRY` | `"doc.kml"` | The entry a KMZ archive keeps its document in. |

| Signature | Returns | Does |
|---|---|---|
| `readKml(text)` | `Document` | Read a KML document. |
| `writeKml(doc)` | `string` | Write a document as KML 2.2. |
| `readKmz(data)` | `Document` | Read a KMZ archive. |
| `writeKmz(doc)` | `bytes` | Write a document as a KMZ archive. |

## GeoJSON

RFC 7946. See [GeoJSON](../guide/geojson.md).

| Signature | Returns | Does |
|---|---|---|
| `readGeojson(text)` | `Document` | Read a GeoJSON document. |
| `writeGeojson(doc)` | `string` | Write a document as a GeoJSON `FeatureCollection`. |

## GML geometry

The GML 3.2 geometry subset. See [GML geometry](../guide/gml.md).

| Constant | Value | Meaning |
|---|---|---|
| `GML_NAMESPACE` | `"http://www.opengis.net/gml/3.2"` | The namespace a GML 3.2 document declares. |
| `GML_CRS` | `"urn:ogc:def:crs:EPSG::4326"` | The coordinate reference system this deck reads and writes GML in. |

| Signature | Returns | Does |
|---|---|---|
| `readGml(text)` | `Document` | Read the geometries out of a GML document. |
| `writeGml(doc)` | `string` | Write a document as a GML 3.2 feature collection. |

## Files and formats

See [Formats](../guide/formats.md).

| Constant | Value | Meaning |
|---|---|---|
| `FORMAT_UNKNOWN` | `""` | What `formatOf` returns for an extension it does not recognise. |

| Signature | Returns | Does |
|---|---|---|
| `formatOf(target)` | `string` | `"gpx"`, `"kml"`, `"kmz"`, `"geojson"` or `"gml"`, from a path's extension. |
| `open(target)` | `Document` | Read a file, in whichever format its extension names. |
| `save(doc, target)` | `null` | Write a document to a file, in whichever format its extension names. |
| `writeText(doc, format)` | `string` | Write a document in a named text format: gpx, kml, geojson or gml. |
| `readText(text, format)` | `Document` | Read a document from text in a named text format. |
| `openGpx(target)` | `Document` | Read a GPX file. |
| `saveGpx(doc, target)` | `null` | Write a document to a file as GPX 1.1. |
| `openKml(target)` | `Document` | Read a KML file. |
| `saveKml(doc, target)` | `null` | Write a document to a file as KML 2.2. |
| `openKmz(target)` | `Document` | Read a KMZ file. |
| `saveKmz(doc, target)` | `null` | Write a document to a file as KMZ. |
| `convertFile(from, to2)` | `Document` | Open one file and save it as another; returns what was read. |

