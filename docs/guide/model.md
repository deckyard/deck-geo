<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# The model

Every reader returns these types and every writer takes them.

## Point

A position, plus whatever the file said about it.

```jennifer
def p as geo.Point init geo.point(47.2692, 11.4041);
$p = geo.named($p, "Goldenes Dachl");
$p = geo.withElevation($p, 574.0);
$p = geo.withTime($p, "2026-09-30T06:00:00Z");
```

`point(lat, lon)` takes latitude first, in WGS 84 degrees, and raises on a
latitude outside -90..90 or a longitude outside -180..180. `withElevation`
raises on an elevation more than 1,000,000 m from zero. Elevation is in metres
and is passed through as the source gives it, with no datum conversion: GPX
and KML elevations are normally above sea level, GeoJSON's above the WGS 84
ellipsoid. `withTime` takes an RFC 3339 string and does not parse it.

The other fields are plain and writable:

```jennifer
$p.desc = "Where the tour starts";
$p.sym = "Flag";
```

### Stated, or not stated

`hasElevation` and `hasTime` record whether `ele` and `at` came from the
source.

```jennifer
def sea as geo.Point init geo.withElevation(geo.point(0.0, 0.0), 0.0);
def unknown as geo.Point init geo.point(0.0, 0.0);

$sea.ele;              # 0.0, and hasElevation is true
$unknown.ele;          # 0.0, and hasElevation is false
```

Writers emit `<ele>` and `<time>` only when the flag is set, so a round trip
does not add `<ele>0</ele>` to points that had no elevation. Set elevation and
time through `withElevation` and `withTime`: `$p.ele = 574.0` on its own
leaves `hasElevation` false, and the elevation is not written.

## Segment, Track and Route

A track is a recorded path, a route a planned one. GPX keeps them apart; KML,
GeoJSON and GML have one kind of line, which reads as a track.

A track splits into segments wherever the recorder lost its fix:

```jennifer
def t as geo.Track init $doc.tracks[0];
len($t.segments);                      # how many unbroken runs
len(geo.trackPoints($t));              # every point, segments run together
```

The gap between two segments was not travelled.
[`trackDistance`](../reference/cheatsheet.md) measures each segment and sums;
`pathLength(trackPoints($t))` and `statsOf(trackPoints($t))` count the gap as
distance. Use `trackPoints` for a bounding box or a centroid, not for a
distance.

`track(name, points)` builds a single-segment track:

```jennifer
$doc.tracks = [geo.track("Day 1", $points)];
```

## Document

```jennifer
def doc as geo.Document init geo.document();
$doc.name = "Innsbruck loop";
$doc.creator = "my tool 1.0";
$doc.waypoints = [$p];
$doc.tracks = [geo.track("Day 1", $points)];
```

```jennifer
geo.describe($doc);   # "Innsbruck loop: 1 waypoint, 1 track, 3 points"
```

`documentPoints` flattens a document in the order waypoints, route points,
track points:

```jennifer
def box as geo.Bounds init geo.bounds(geo.documentPoints($doc));
```

## Appending

Jennifer copies a value on assignment and on every argument pass, so growing a
list field one element at a time copies the whole list each time, which is
quadratic on a long track. `$doc.tracks[] = ...` does not parse: the append
form takes a bare variable. Build a local list and assign the field once:

```jennifer
def points as list of geo.Point init [];
for (def fix in $fixes) {
    $points[] = geo.point($fix.lat, $fix.lon);
}
$doc.tracks = [geo.track("Day 1", $points)];
```

[Memory](../internal/memory.md) has the measurements.

## Bounds

A latitude and longitude rectangle, from `bounds`, `geohashBounds` or
`tileBounds`.

```jennifer
def box as geo.Bounds init geo.bounds($points);
geo.containsPoint($box, $p);
def middle as geo.Point init geo.boundsCenter($box);
```

`bounds` works in plain degrees, so a path that crosses the antimeridian gets a
box spanning nearly every longitude instead of the narrow one across 180
degrees. [`centroid`](../reference/cheatsheet.md) averages unit vectors and
gives the right mean for a cluster either side of 180 degrees.
