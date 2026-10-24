<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Formats

## By extension

`open` and `save` pick the codec from the file extension, case-insensitively:

```jennifer
def doc as geo.Document init geo.open("hike.gpx");
geo.save($doc, "hike.kml");
```

| Extension | Format |
|---|---|
| `.gpx` | GPX |
| `.kml` | KML |
| `.kmz` | KMZ, a zipped KML |
| `.geojson`, `.json` | GeoJSON |
| `.gml`, `.xml` | GML geometry |

`formatOf` returns that choice (`"gpx"`, `"kml"`, `"kmz"`, `"geojson"`,
`"gml"`), or `FORMAT_UNKNOWN` (`""`) for any other extension. `open` and
`save` raise on an unknown extension; they do not sniff the content.
`openGpx`, `openKml`, `openKmz` and the matching `save*` calls use their own
format whatever the extension.

`convertFile` opens one path, saves to the other and returns the document it
read:

```jennifer
def doc as geo.Document init geo.convertFile("hike.gpx", "hike.geojson");
```

## By text

For text that is not a file, such as a response body or a database column,
name the format:

```jennifer
def doc as geo.Document init geo.readText($body, "gpx");
def out as string init geo.writeText($doc, "geojson");
```

These take `"gpx"`, `"kml"`, `"geojson"` or `"gml"` and raise on anything
else. KMZ is a zip, so it has `readKmz` and `writeKmz` over `bytes` instead.

## Character encodings

A string is already decoded, so `readText` and the `read*` functions take it
as it is. A file is bytes, and `open` and the `open*` functions honour the XML
declaration: a GPX, KML or GML file that declares `ISO-8859-1`,
`windows-1252` or another single-byte encoding is transcoded to UTF-8 before
it is read, as older Garmin and GIS exports need. UTF-16 raises, as does an
encoding with no codec. A GeoJSON file is read as UTF-8, which RFC 7946
requires.

Writers produce UTF-8. They drop the characters XML 1.0 cannot hold (the C0
controls other than tab, line feed and carriage return, and U+FFFE and U+FFFF),
because no escape can carry them and a strict parser rejects the whole file
over one.

## What each format holds

What a format cannot hold is lost when a document passes through it.

| | GPX | KML | GeoJSON | GML |
|---|---|---|---|---|
| Document name | yes | yes | **no** | yes |
| Waypoints | yes | yes | yes | yes |
| Routes, kept apart from tracks | yes | **no** | **no** | **no** |
| Multi-segment tracks | yes | yes | yes | yes |
| Time per point | yes | **no** | **no** | **no** |
| Elevation per point | yes | yes | yes | read only |
| Waypoint name | yes | yes | yes | yes |
| Waypoint description | yes | yes | yes | **no** |
| Waypoint symbol (`sym`) | yes | read only | yes | **no** |

- A route becomes a track in KML, GeoJSON and GML, so a GPX document that
  passes through any of them comes back with its routes as tracks.
- Timestamps, and everything [`statsOf`](measuring.md) derives from them, do
  not survive KML, GeoJSON or GML.
- A GeoJSON `FeatureCollection` has no title, so the document name is dropped.
  Per-feature names survive in `properties`.
- `writeGml` writes two-dimensional positions, so elevations are dropped. KML
  reads `<styleUrl>` into `sym` but `writeKml` does not write it.

Segment breaks survive all four: a multi-segment track is written as a KML
`MultiGeometry`, a GeoJSON `MultiLineString`, or one GML `featureMember` per
segment.

## Writing

Writers build text, not a tree, and emit an element only when it has content:

```jennifer
def doc as geo.Document init geo.document();
$doc.waypoints = [geo.point(47.2692, 11.4041)];
geo.writeGpx($doc);
```

The waypoint is written as:

```xml
<wpt lat="47.2692" lon="11.4041" />
```

with no empty `<name>`, no `<ele>` and no `<metadata>` block, so a document
does not grow on a round trip.

Coordinates are written with up to `COORD_PLACES` (7) decimal places, about a
centimetre, with trailing zeros removed: `47.2692` stays `47.2692`. Elevations
get up to `ELEVATION_PLACES` (2). Negative zero is written as `0`.

A path of fewer than two points is not written by `writeKml` or `writeGml`, and
`writeGeojson` skips such a track segment, since a line needs two positions.
`writeGeojson` does write a route of one point, as a one-position
`LineString`, which RFC 7946 does not allow.

## A conversion, end to end

[`examples/convert.j`](https://github.com/deckyard/deck-geo/blob/main/examples/convert.j)
builds a document, writes it as GPX, converts that to the other four formats
and reads each one back.
