<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Directories

## The source tree

`src/geo.j` is the only compilable unit. It `use`s the libraries and
`include`s every file under `src/topics/`. `include` is a textual splice,
so a topic file cannot be linted or tested on its own: in isolation its calls
into its siblings read as undefined. Lint `src/geo.j` and `src/geo_test.j`.

`src/geo_test.j` mirrors the splice over `src/topics/*_test.j`, so the
overlay is white-box and the tests call unexported helpers directly.

**Include order matters for type declarations only.** `model.j` precedes
everything that handles a `Point`; `geodesy.j` precedes `geometry.j` and
`stats.j`, which measure with it; `scan.j` precedes the four codecs;
`file.j` is last because it dispatches to all of them. Functions resolve
late, so call order is free.

```
src/geo.j                 the module boundary and every export
src/geo_test.j            the white-box overlay
src/topics/version.j      generated; VERSION
src/topics/core.j         errors, entity codec, number formatting, clamping
src/topics/model.j        Point, Segment, Track, Route, Document, Bounds
src/topics/geodesy.j      haversine distance, bearings, dead reckoning
src/topics/geometry.j     bounds, centroid, simplification, containment
src/topics/stats.j        TrackStats and the thresholds behind it
src/topics/geohash.j      geohash encode and decode
src/topics/tile.j         Web Mercator tiles and quadkeys
src/topics/scan.j         the streaming element scanner the XML codecs walk
src/topics/gpx.j          GPX 1.0 and 1.1
src/topics/kml.j          KML 2.2 and KMZ
src/topics/geojson.j      GeoJSON, RFC 7946
src/topics/gml.j          the GML geometry subset
src/topics/file.j         whole files and the format dispatch
```

Each has a co-located `_test.j` beside it, except the generated
`version.j`, which opts out with a `# ci-no-overlay` line.

## The rest

```
docs/          the book; docs/SUMMARY.md is the outline
examples/      runnable programs, all of which CI runs
tools/         the CI helpers, the fuzz sweep and the doc-claims checker
site/          the built book; not committed
```

## Errors

Every failure is `Error{kind: "geo", ...}` raised through `fail()` in
`core.j`. The line between an error and damage a reader works around is in
[the introduction](../index.md); `tools/fuzz.j` asserts it, and that no
malformed input raises any other `kind`.

## Value semantics

Functions that change a value return a new one and leave the argument alone.
Tests assert it
(`testNamedAndWithersLeaveTheArgumentAlone`,
`testMergeDocumentLeavesBothArgumentsAlone`). What it costs on a large track
is measured in [Memory](memory.md).
