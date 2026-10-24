<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Memory

Why the XML readers scan instead of parsing. The figures are from one host,
reading a 10 MB GPX of 50,000 track points, each with an elevation, a
timestamp and a Garmin extensions block.

## The problem

Jennifer's `xml.decode` builds a tree. Over this file:

| | Wall | Peak RSS |
|---|---|---|
| `xml.decode` on the whole document, reading nothing out | 0.7 s | 1.34 GB |
| the same, then walking it into `Point` structs | 2.3 s | 2.49 GB |

A 10 MB document costs 1.34 GB as a tree, around 130 times its own size, all
live at once. Three such files do not fit in 4 GB, and GPS archives hold files
this size.

## What the deck does instead

`src/topics/scan.j` walks element boundaries over the raw `bytes`:

- `nextChild` yields one direct child at a time. A `<trkseg>` has as many
  children as the track has points, so a list of them would be the largest
  thing in the program. `childNodes` returns a list and is used only where the
  count is known to be small: a document header, a waypoint's fields.
- The hot primitives are native. `binary.indexOf` finds the next `<`;
  `binary.slice` plus one value comparison tests a probe. An interpreted loop
  per byte measured **12.5 s** on a tenth of this file where the native form
  measures **1.5 s**.
- Element names are matched with their boundaries respected. `<trk` occurs
  inside every one of a track's `<trkpt>`s, so a bare substring search sends
  every GPX track down the nesting-aware slow path. That cost **1.9 s** of a
  5 s read until `openTagAt` learned to check the following byte.
- `decodeLeaf` hands each **leaf** - a `<trkpt>`, a `<wpt>` - to
  `xml.decode`. One native parse of a 200-byte element beats an interpreted
  walk of its children by more than an order of magnitude, and the tree alive
  at any moment covers one point rather than the document. Replacing the
  interpreted walk with this took the read from **19 s to 1.5 s** per 5,700
  points.

The scanner finds boundaries; the interpreter's parser reads fields. Entity
decoding, CDATA and attribute quoting for the structural elements are the
scanner's own (`xmlUnescape`, `nodeText`, `nodeAttr`), covering the same
ground as `xml.decode` with one deliberate difference: an unknown entity is
left standing rather than raising, because a GIS exporter writing `&deg;`
should not make a track log unreadable.

## What it costs

| | Wall | Peak RSS |
|---|---|---|
| this deck, 10 MB / 50,000 points | 19.4 s | 1.10 GB |
| this deck, 1.2 MB / 5,700 points | 1.5 s | 0.17 GB |
| `xml.decode` tree of the same 10 MB, nothing read out | 0.7 s | 1.34 GB |

**The scan is slower in wall-clock time than building a tree.** It buys
memory proportional to the result rather than to the file: the ceiling moves
from "the file must fit in memory 130 times over" to "the points must fit". A
typical GPX of a few thousand points, well under a megabyte, reads in well
under a second.

## The remaining cost is value semantics

The 1.10 GB above is not the scanner. It is mostly deep copies of the point
list, a property of the language rather than of this design.

Jennifer copies a compound value on assignment, on every argument pass and on
every return. A segment's points are copied out of `readGpxSegment`, again
into the `Segment` literal, again into the segments list, again into the
`Track`, again on its return, and again into the document: about seven deep
copies of 50,000 structs. `GOGC=20` brings 1.23 GB down only to 0.93 GB,
so this is memory retained by copies, not collectable garbage. `jennifer profile --allocs` names the copies.

The same trap caught the GeoJSON and GML readers, which first accumulated with
a merge per feature. Merging copies the whole accumulated list each time, so
reading was quadratic in the feature count:

| Features | merge per feature | appended into locals |
|---|---|---|
| 500 GeoJSON | 0.61 s | 0.03 s |
| 2,000 GeoJSON | 8.58 s | 0.12 s |
| 2,000 GML | 14.19 s | 0.87 s |

A 20,000-feature city dataset, an ordinary size for GeoJSON, would have taken a
quarter of an hour. Both readers now append into local lists and assemble the
document once, and `testReadGeojsonScalesToManyFeatures` reads a collection
large enough that a return to the quadratic form shows up in the suite's
runtime.

Two consequences for callers:

- **Read once.** `geo.open` costs what it costs; calling it twice costs
  twice.
- **Work from a flat list.** `trackPoints` once into a local, then measure,
  simplify and write from that, rather than reaching through
  `$doc.tracks[0].segments[0].points` repeatedly. Each of those is a copy.

The 10 MB buffer itself is **not** among the copies: passing `bytes` to a
function does not deep-copy it, which is what makes the scanner's shape viable.

## Writing

Every writer renders into a `list of string` and joins once; no tree is
built. 50,000 points render to GPX in about a third of a second.

## If this needs to be faster

In rough order of expected return:

1. **Fewer copies on the way in.** A reader appending into one flat list and
   recording segment boundaries as indices, converting to `Segment`s once at
   the end, would cut most of the seven copies.
2. **A streaming reader.** `readGpx` necessarily materialises a whole
   `Document`. An API handing each point to a callback as it is read would let
   a caller measure a 100 MB track in constant memory. The scanner already
   supports that; the model does not expose it.
3. **Native help.** Most of the remaining wall-clock is interpreter overhead
   per statement, which nothing in the deck can fix.
