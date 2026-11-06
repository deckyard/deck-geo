<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Memory

Why the XML readers scan instead of parsing, and why the GPX reader now
decodes first. The figures are from one host, reading a 10 MB GPX of 50,000
track points, each with an elevation, a timestamp and a Garmin extensions
block. The tables before [Measured again](#measured-again) are from the
interpreter the scanner was designed on; that section has the current
figures, which reverse the premise. [GPX: tree first](#gpx-tree-first) is the
design that followed. KML and GML still scan.

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

- Close tags are found with one native search for `</name`, plus searches for
  `<name` and `<!` bounded by that close tag. Only a same-name nested element
  or a comment/CDATA section inside the element takes the walk in
  `nestedClose`, which keeps each event kind's next position and searches
  again only once passed, so it is linear in the element. A name probe that
  hits a longer name (`<trk` in `<trkpt`) switches to one native search per
  spelling that can end the name (`exactTagAt`) instead of a step per hit.
  GPX points never contain their own name, so they are read as leaves
  (`leafClose`): the close search stops at the next `<trkpt`, and an unclosed
  point costs no more than a closed one.

The scanner finds boundaries; the interpreter's parser reads fields. Entity
decoding, CDATA and attribute quoting for the structural elements are the
scanner's own (`xmlUnescape`, `nodeText`, `nodeAttr`), covering the same
ground as `xml.decode` with one deliberate difference: an unknown entity is
left standing rather than raising, because a GIS exporter writing `&deg;`
should not make a track log unreadable. `decodeLeaf` keeps the same rule for
leaves: when `xml.decode` rejects one, it retries with every unknown `&...;`
escaped (`escapeUnknownEntities`).

## What it costs

| | Wall | Peak RSS |
|---|---|---|
| this deck, 10 MB / 50,000 points | 19.4 s | 1.10 GB |
| this deck, 1.2 MB / 5,700 points | 1.5 s | 0.17 GB |
| `xml.decode` tree of the same 10 MB, nothing read out | 0.7 s | 1.34 GB |

**The scan is slower in wall-clock time than building a tree.** It bought
memory proportional to the result rather than to the file: the ceiling moves
from "the file must fit in memory 130 times over" to "the points must fit". A
typical GPX of a few thousand points, well under a megabyte, reads in well
under a second.

## The remaining cost is value semantics

The 1.10 GB above was mostly deep copies of the point list: on that
interpreter a segment's points were copied out of `readGpxSegment`, into the
`Segment` literal, into the segments list, into the `Track` and into the
document. The interpreter now borrows read-only parameters and hands a
returned value on without a copy, and `jennifer profile --allocs` over a read
of the 10 MB file shows no list copies at all. What is left is two copies of
one `Point` per point, inside `withElevation` and `withTime` (`model.j`),
about 117 MiB each over 50,000 points; they are garbage at once and do not add
to the peak.

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
built. 50,000 points with elevation and time render to GPX in 1.4 s (3.0 s
before `decimal()` used `%f|trim=true` instead of a loop per character, and
before `writeGpxPoint` stopped calling `element()` for absent fields and
`xmlEscape` for text with nothing to escape).

## Measured again

Interpreter `0.25.0-dev+43.c0cb864`, the same 10 MB / 50,000-point file:

| | Wall | Peak RSS |
|---|---|---|
| `xml.decode` on the whole document, reading nothing out | 0.06 s | 84 MB |
| the same, then walking every `<trkpt>` and parsing its `lat` | 0.16 s | 146 MB |
| this deck, `openGpx` | 6.0 s | 579 MB |
| this deck, `openGpx`, 1 MB / 4,829 points | 0.6 s | 79 MB |

`xml.decode` no longer costs 130 times the file: a whole-document tree is now
smaller and about 40 times faster than the scan. The per-point cost of the
scan is in the interpreted walk (`readNode`, `endOfOpenTag`) and in
`decodeLeaf`'s per-leaf `xml.decode`.

## GPX: tree first

`readGpx` and `readGpxBytes` (so `openGpx`, `open` and `readText` for GPX)
run `xml.decode` on the whole document, a leading byte-order mark stripped.
`readGpxTree` walks the tree into the `Document`. The scanner path,
`readGpxScan`, is unchanged and runs when:

- `xml.decode` raises: malformed or truncated markup, an unknown entity
  (`&deg;`), bytes that are not UTF-8, nesting past 1,000 levels (64 on
  `jennifer-tiny`), or more than 2,097,152 nodes (262,144 on `jennifer-tiny`;
  `MaxDecodedNodes` in `jennifer/internal/limits/nesting_*.go`). Elements,
  attributes and text runs count; the 10 MB file has 600,012, about 12 per
  point, so `jennifer-tiny` reads files past about 21,000 such points with
  the scanner;
- `treeMatchesScan` finds a well-formed construct the scanner reads
  differently from the tree (below).

Both run before the first point is read. Errors the walk raises (a missing,
unparseable or out-of-range coordinate or elevation) propagate, with the
scanner's `kind` and message, in the scanner's order: waypoints, then routes,
then tracks. Both paths read points through `pointsFrom`.

Why both: `jennifer-tiny` rejects a long track as a decode bomb, and
`xml.decode` is strict where the scanner reads damage (truncation, an
unclosed point mid-file, unknown entities, undeclared prefixes).

`treeMatchesScan` sends a decoded document to the scanner when it holds:

| Construct | What the scanner does differently |
|---|---|
| `<!DOCTYPE` | ends it at the first `>`, inside an internal subset |
| `<!-->`, `<!--->` | finds the comment's `-->` inside its own `<!--` |
| `&#+65;`, `&#x+41;` | leaves the reference standing; `xml.decode` reads the sign |
| a processing instruction inside the root, or a second one | does not skip it in close searches |
| `<![CDATA[` inside a comment | splits field text at it |
| an element 102 levels deep (`DEEP_PATH`) | takes 102 nested elements of one name as unclosed (`nestedClose`) |
| a point holding an element of its written name, or a point name outside a point position | ends the point at the inner open tag (`leafClose`) |
| points of one kind under two written names | nothing; the point check needs one name |
| a header, route or track field with element children, or `<![CDATA[` in its text | keeps the children's text (`textOnly`); splits at the opener (`cdataText`) |
| `xmlns` on a `<rte>`, `<trk>` or `<trkseg>` | decodes points against the root's bindings only |

The point check counts open tags of the written name in the text
(`strings.count`, six name endings) against the points the tree holds, so an
occurrence in a comment also sends the document to the scanner. `creator` is
read from the bytes with the scanner's `nodeAttr`: `xml.decode` normalises
tabs and newlines in attribute values to spaces and prefers `creator` to
`x:creator`.

Points are read per parent, not per point. `treePoints` runs one native
`xml.findAll` per field (`*:trkpt/*:ele[1]` lists the first `<ele>` of each
point that has one); when every point or none holds each field, the lists
line up and `pointsFrom` reads each point by index. Otherwise each point is
read with `gpxPoint`, a lookup per field. A point starts as a copy of a blank
`Point` (a struct literal costs more) and is filled in place;
`withElevation` and `withTime` each copied it. Coordinates that match
`NUMBER_PATTERN` as written are converted in one `try`; anything else goes
through `number()`, which raises the deck's error.

Interpreter `0.25.0-dev+43.c0cb864`, `openGpx` only:

| | Go wall | Go peak RSS | tiny wall | tiny peak RSS |
|---|---|---|---|---|
| scanner, 10 MB / 50,000 points | 6.1 s | 554 MB | 29.1 s | 1.54 GB |
| tree, 10 MB / 50,000 points | 1.4 s | 661 MB | 29.3 s (estimate over the cap, scanner) | 1.56 GB |
| scanner, 1 MB / 4,829 points | 0.63 s | 75 MB | 0.96 s | 172 MB |
| tree, 1 MB / 4,829 points | 0.14 s | 97 MB | 0.54 s | 190 MB |

On `jennifer-tiny`, `decodeFits` estimates the nodes before decoding
(`decodeNodes`: elements are `<` less `</`, `<?`, `<!`; attributes `="` and
`='`; text runs `>` not followed by `<`; 600,015 against 600,012 decoded for the
10 MB file) and sends a document over `TINY_DECODE_NODES` (2^18) to the
scanner. Without it the decode failed after the full parse and the 10 MB file
took 31.7 s. A wrong estimate only changes the path.

Of the 1.4 s, `xml.decode` takes 0.06 s and the checks about 0.1 s. The rest
is the interpreter: per point about 25 statements and 15 native calls, a
`Point` copy and append (3 µs), and the copies that put a 50,000-point list
into a `Segment`, the segment list into a `Track` and the tracks into the
`Document` (about 0.1 s each). Peak RSS is 107 MB above the scanner's: the
tree (84 MB on its own) stays live while the points are built.

Parity is tested in `gpx_test.j`: `testReadGpxTreeMatchesScanOnEveryFuzzInput`
rebuilds the GPX inputs of `tools/fuzz.j` and compares both readers on each
one the tree reader takes, and one test per row of the table above asserts
the scanner reads it.

## If this needs to be faster

In rough order of expected return:

1. **Decode the whole document in KML and GML**, as GPX does
   ([GPX: tree first](#gpx-tree-first)), with the scanner as fallback.
2. **A streaming reader.** `readGpx` necessarily materialises a whole
   `Document`. An API handing each point to a callback as it is read would let
   a caller measure a 100 MB track in constant memory. The scanner already
   supports that; the model does not expose it.
3. **Native help.** Most of the remaining wall-clock is interpreter overhead
   per statement, which nothing in the deck can fix.
