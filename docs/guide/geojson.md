<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# GeoJSON

RFC 7946.

```jennifer
def doc as geo.Document init geo.readGeojson($body);
def out as string init geo.writeGeojson($doc);
```

A position is `[lon, lat]` or `[lon, lat, ele]`, longitude first as RFC 7946
fixes it, with elevation in metres above the WGS 84 ellipsoid. The deck swaps
the order on read and write; there is nothing to configure.

## What is read

The document may be a `FeatureCollection`, a single `Feature` or a bare
geometry.

| `type` | Becomes |
|---|---|
| `Point` | a waypoint |
| `MultiPoint` | one waypoint per position |
| `LineString` | a single-segment track |
| `MultiLineString` | a track, one segment per line |
| `Polygon` | a track along the outer ring |
| `MultiPolygon` | a track, one segment per polygon's outer ring |
| `GeometryCollection` | each geometry inside it |

Inner rings (holes) are dropped. Any other `type`, or a feature with no
geometry, contributes nothing, so a collection that mixes a `Point` with
something unsupported still yields the point. A position with fewer than two
numbers, a coordinate out of range, or an array member of the wrong JSON type
raises.

## Names live in properties

RFC 7946 does not define feature properties. The deck uses the common
convention:

```json
{
  "type": "Feature",
  "properties": {"name": "Nordkette", "description": "Alpine", "sym": "pin"},
  "geometry": {"type": "Point", "coordinates": [11.3889, 47.3122, 2334]}
}
```

`name` and `description` become the name and description; `sym` is this
deck's own and round-trips through GeoJSON and GPX. A property that is missing
or not a string reads as `""`.

## The document name is lost

A `FeatureCollection` has no title member, so `$doc.name` is not written:

```jennifer
def before as geo.Document init geo.open("hike.gpx");
def after as geo.Document init geo.readGeojson(geo.writeGeojson($before));
```

`$after.name` is empty whatever `$before.name` was. Per-feature names survive.
The deck does not add a non-standard member, because other readers would
ignore it.

## What is written

A `FeatureCollection`, indented, with one `Feature` per waypoint, route and
track. A track with several segments becomes a `MultiLineString`, so the
breaks survive; a segment of fewer than two points is left out, and a track
with nothing left is not written. A route is not filtered: one of fewer than
two points is written as a `LineString` RFC 7946 does not allow. Strings go through `json.encode`, so a name
with a quote, a backslash or a newline round-trips exactly
(`testWriteGeojsonEscapesThroughTheJsonEncoder`).
