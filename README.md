# @deckyard/geo

[![test](https://github.com/deckyard/deck-geo/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-geo/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-geo/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-geo)](https://github.com/deckyard/deck-geo/releases/latest)

A [Jennifer](https://jennifer-lang.dev/) deck that reads, edits and writes GPX,
KML, KMZ, GeoJSON and the GML geometry subset through one `Document` type, so a
conversion is a read and a write. It also measures: great-circle distances and
bearings, track statistics, simplification, point-in-polygon tests, geohashes
and Web Mercator map tiles.

## Install

```sh
jvc add @deckyard/geo
```

Or unpack `src/` from a release archive (`deckyard-geo-<version>.tar.gz`) into
`vendor/deckyard/geo/`.

Requires Jennifer 0.25.0 or newer. The deck declares no capabilities, so it
runs on `jennifer-tiny`; only `open`, `save` and their per-format siblings
touch the disk.

## Example

```jennifer
use io;
import "@deckyard/geo/" as geo;

def doc as geo.Document init geo.open("hike.gpx");
def km as float init geo.trackDistance($doc.tracks[0]) / 1000.0;
io.printf("%s: %f|prec=1 km\n", geo.describe($doc), $km);

geo.save($doc, "hike.kml");
geo.convertFile("hike.gpx", "hike.geojson");
```

Coordinates are WGS 84 degrees and are never reprojected: a document in a
projected system (a national grid, a UTM zone) is rejected, not misread. GPX
`<extensions>`, KML styles and timestamps, and polygon holes are not carried
(GML reads a hole as a track of its own), and there is no TCX, FIT or NMEA.
[Formats](https://deckyard.github.io/deck-geo/guide/formats.html) lists what
each conversion loses.

## Documentation

[deckyard.github.io/deck-geo](https://deckyard.github.io/deck-geo/), with the
full API in the
[cheatsheet](https://deckyard.github.io/deck-geo/reference/cheatsheet.html).
Runnable programs are in [`examples/`](examples). `tools/check-all.sh` runs the
CI gate.

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.
