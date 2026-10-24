<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/geo

Reads GPX, KML, KMZ, GeoJSON and the GML geometry subset into one
[`Document`](reference/cheatsheet.md) and writes any of them back out. On top
of the model: great-circle distances and bearings, track statistics,
simplification, point-in-polygon tests, geohashes and map tiles.

This deck is part of [Deckyard](https://github.com/deckyard), community decks for [Jennifer](https://jennifer-lang.dev/).

```jennifer
use io;
import "@deckyard/geo/" as geo;

def doc as geo.Document init geo.open("hike.gpx");
io.printf("%s\n", geo.describe($doc));
io.printf("%f|prec=1 km\n", geo.trackDistance($doc.tracks[0]) / 1000.0);

geo.save($doc, "hike.kml");
```

The trailing slash in the import resolves to the entry module. A conversion
is one call:

```jennifer
geo.convertFile("hike.gpx", "hike.geojson");
```

GPX loses least in a conversion: it is the only one of the five that keeps
routes apart from tracks and has a place for a per-point timestamp.
[Formats](guide/formats.md) has the full table.

## Value semantics

Every function that changes a point, a track or a document returns a new
value and leaves its argument alone, so the calling shape is
`$x = something($x, ...)`:

```jennifer
def bare as geo.Point init geo.point(47.2692, 11.4041);
def named as geo.Point init geo.named($bare, "Start");

$bare.name;    # still ""
```

On a large track the copies cost memory: see [Memory](internal/memory.md).

## Errors

Every failure is an `Error` with `kind` `"geo"` (`ERROR_KIND`).

```jennifer
try {
    def doc as geo.Document init geo.open("not-a-track.gpx");
} catch (e) {
    io.printf("%s\n", $e.message);
}
```

A reader raises on: a root element of another format, a coordinate that is
not a number or lies outside -90..90 / -180..180, a GML coordinate list that
does not divide into whole positions, a KMZ with no KML inside, an extension
that names no format, and nesting deeper than `MAX_NESTING` (100).

Damage a reader can work around is not an error. A file cut short yields the
points written before the cut, an unknown entity is left as written, and
markup the model does not cover is ignored. `tools/fuzz.j` checks this line on
every commit with about 1,800 seeded inputs (truncated, byte-bent and
type-swapped fixtures): each either reads into points that are all on the
Earth, and survives a write and re-read in all four text formats, or raises
`kind` `"geo"`.

Nothing beyond the five predefined XML entities and numeric character
references is expanded, and no external entity is fetched. An untrusted KMZ is
a risk because decompression is unbounded: see [KML and KMZ](guide/kml.md).

## Contents

| Page | Covers |
|---|---|
| [The model](guide/model.md) | points, paths, documents |
| [Formats](guide/formats.md) | reading, writing, converting, what survives |
| [GPX](guide/gpx.md) | GPX 1.0 and 1.1 |
| [KML and KMZ](guide/kml.md) | placemarks, folders, geometries, the zip |
| [GeoJSON](guide/geojson.md) | features, collections, geometries |
| [GML geometry](guide/gml.md) | the subset, and axis order |
| [Measuring](guide/measuring.md) | distance, bearing, statistics, simplification |
| [Addressing](guide/addressing.md) | geohashes and map tiles |
| [Cheatsheet](reference/cheatsheet.md) | the full API |
| [Memory](internal/memory.md) | why the XML readers stream, with measurements |
| [Directories](internal/directories.md) | the source tree |
| [Versioning](internal/versioning.md) | git tags, `VERSION`, CI injection |

Runnable programs:
[`examples/`](https://github.com/deckyard/deck-geo/tree/main/examples).
