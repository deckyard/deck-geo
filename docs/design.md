<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

The deck reads, edits and writes GPX (1.0 and 1.1), KML, KMZ, GeoJSON and the
GML geometry subset through one `Document` model, and measures on top of it:
haversine distances and bearings, track statistics, simplification,
point-in-polygon tests, resampling, geohashes and Web Mercator tiles.

It is pure computation over text and bytes. Only `open`, `save`, their
per-format siblings and `convertFile` touch the disk; nothing opens a socket
or runs a program, so the deck declares no capabilities and runs on
`jennifer-tiny`.

Deliberately out of scope:

- **Reprojection.** Coordinates are WGS 84 degrees. A document in a projected
  system (a national grid, a UTM zone) is rejected rather than misread.
- **Styling and extensions.** GPX `<extensions>`, KML styles and timestamps
  are not carried; [Formats](guide/formats.md) lists what each conversion
  loses.
- **Polygon holes.** A hole is not modelled; GML reads one as a track of its
  own.
- **Other formats.** TCX, FIT and NMEA are not read or written.

## Decisions

- **One model, every format.** Every reader returns a `Document`, every
  writer takes one, so a conversion is a read plus a write and a new format is
  two functions. Latitude comes before longitude in every signature; GeoJSON
  and GML `coordinates`, which write longitude first, are swapped on the way
  in and out.
- **Value semantics.** Every function that changes a point, path or document
  returns a new value and leaves its argument alone; the tests assert that
  arguments are untouched.
- **XML is scanned, not parsed whole (KML, GML).** A whole-document
  `xml.decode` tree ran to about 130 times the file's size on the interpreter
  the deck was designed on (1.34 GB for a 10 MB GPX). The XML readers walk
  element boundaries over the raw `bytes` with native searches and hand only
  each leaf (a `<trkpt>`, a `<wpt>`) to `xml.decode`. The memory then scales
  with the result rather than the file. [Memory](internal/memory.md) has the
  measurements.
- **GPX: tree first, scanner as fallback.** On current interpreters the same
  10 MB GPX decodes in about 84 MB, so GPX now decodes the whole document and
  walks the tree, which is about four times faster than the scan. Any decode
  failure (malformed or non-UTF-8 input, an unknown entity, the decoder's
  depth or node caps) falls back to the scanner, which also reads damaged
  files. The two paths must give the same `Document` or the same error for
  every input both read; a check declines the tree for the well-formed
  constructs the scanner reads differently (a DOCTYPE, processing
  instructions inside the root, very deep nesting, mixed point prefixes, and
  similar), and a parity test replays every fuzz input through both. On
  `jennifer-tiny`, whose decoder has a lower node cap, a document estimated
  past that cap goes straight to the scanner. KML and GML would need the same
  parity work before they could decode whole.
- **Namespaces by local name.** Tags and attributes are matched on their
  local part, never on prefix or namespace URI, since exporters disagree on
  both. A leaf cut out of a document has lost its `xmlns` declarations, so the
  readers read the root's bindings once and pass them to `xml.decode` (the
  namespace map added for this deck in `jennifer`'s M28.34). If a leaf still
  uses an undeclared prefix, it is retried with every such prefix bound to a
  stand-in URI.
- **Damage versus bad data.** Damage a reader can work around is not an
  error: a file cut short yields the points before the cut, an unclosed GPX
  point is dropped without hiding the points after it, an unknown entity
  (`&deg;` from a GIS exporter) is left as written, and markup outside the
  model is ignored. A coordinate that is not a number or lies off the Earth
  is an error. `xml.decode` raises on an unknown entity; the deck
  deliberately does not.
- **Strict numbers.** Coordinates and elevations accept only the xsd:double
  form without INF and NaN, because `convert.toFloat` also takes `1_0` and
  `0x1p4`. Elevation is bounded to plus or minus 1,000,000 m, since a value
  like 1e308 made the statistics overflow.
- **Strict GeoJSON.** Valid JSON that is not GeoJSON (a non-object root, no
  string `type`, a non-object feature or geometry) raises; a `null` geometry
  is an unlocated feature and contributes nothing.
- **GML axis order follows `srsName`.** A `urn:` or `opengis.net/def/crs/`
  name, or none, is latitude first; `EPSG:4326`, `CRS:84` and anything else
  are longitude first; `coordinates` is always longitude first. The writer
  names `GML_CRS` (`urn:ogc:def:crs:EPSG::4326`, latitude first).
- **KMZ entry choice.** `doc.kml` wins, then the first `.kml` at the root,
  then the first anywhere, which matches what Google Earth reads when a KMZ
  carries a legend or an overlay besides.
- **Geometry on the sphere.** `simplify` measures offsets on the sphere (unit
  vectors and chords to the arc); an earlier local plane mis-measured long
  spans away from the equator by kilometres. Every argument to `acos` and
  `asin` is clamped to -1..1, since those raise rather than return NaN.
  `tileOf` settles the row against the tile's own edge latitude, because the
  forward formula put about one in six north edges a row too far north.
- **Linear readers.** Readers accumulate into local lists and assemble the
  document once; merging per feature copied the accumulated list each time
  and was quadratic (2,000 GML members took 14 s). Writers render into a list
  of strings and join once. Close-tag searches cache their next positions so
  nested or comment-laden elements stay linear in their size.
- **A deck, not a module.** The formats are generic, but the model, the
  conversion rules and the measuring surface are opinionated choices that
  version better on their own than with the interpreter.
- **Parameter names.** `to` cannot be a parameter name, so `convertFile` and
  `secondsBetween` take `to2`.

## Errors

Every failure is an `Error` of kind `"geo"` (`ERROR_KIND`), except a reached
cap, which is kind `"limit"`: nesting past `MAX_NESTING`, a KMZ past
`MAX_KMZ_ENTRY_BYTES` or `MAX_KMZ_TOTAL_BYTES`, `resample` past
`MAX_RESAMPLE_POINTS`, and GeoJSON text or an XML point past the nesting or
node caps of `json.decode` or `xml.decode`, whose `"limit"` error passes on
unchanged. (A whole-document GPX decode that reaches a cap is not an error:
the reader falls back to the scanner.) A KMZ cap reported by `archive` stays `"limit"` with
the deck's message naming the cap. Messages quote input truncated to 48
characters. `secondsBetween` raises on an unparseable stamp rather than
returning a value that could also be a real answer.

## Security and limits

- No external entity is fetched and nothing beyond the five predefined XML
  entities and numeric character references is expanded.
- `MAX_NESTING` (100) bounds folder and collection depth. Descent cost grows
  with depth, and the interpreter's own recursion cap would raise kind
  `"runtime"`, breaking the promise above.
- A KMZ is unpacked under a per-entry cap of 16 MiB and a total of 64 MiB;
  symbolic links, devices and FIFOs inside the archive are dropped.
- `resample` refuses up front when the path length over the spacing reaches
  `MAX_RESAMPLE_POINTS` (1,000,000), dividing rather than multiplying so the
  check cannot overflow.
- Angles past 2^53 are reduced exactly before normalising, since
  `math.floor` raises on a result that does not fit an `int`.
- Error messages format hostile numbers compactly (a 1e308 would otherwise
  print 309 digits).

## Testing and validation

- 367 tests in one overlay per topic, with fixtures built in code (no
  `testdata/`). Two tests read input at two sizes and compare the growth, so a
  return to quadratic reading fails the suite.
- `tools/fuzz.j` (seeded, about 1,800 inputs from truncated, byte-bent and
  type-swapped fixtures) runs in `tools/check-extra.sh`: each input either
  reads into points on the Earth that survive a write and re-read in all four
  text formats, or raises kind `"geo"` or `"limit"`, never another kind and
  never a hang. The same check verifies that every exported function is
  called from a test.
- `tools/doc-claims.j` checks every number and listing the guides print
  against what the code returns.
- Not covered: files from real devices beyond the hand-built fixtures, and
  conformance against a reference GIS library.

## Known limitations and open questions

- KML and GML still scan; moving them to a whole-document decode needs the
  same parity checks GPX has.
- The scanner is slower in wall-clock time than a tree, and the copies that
  value semantics imply cost memory on large tracks; take `trackPoints` once
  into a local rather than reaching through the document repeatedly.
- The KMZ message names which cap was hit by reading `archive`'s message
  wording; a reworded message there gives a generic one. The error's kind is
  unaffected.
- `interpolate` extrapolates for a fraction outside 0..1; far enough out the
  latitude leaves the Earth and it raises.
- A streaming XML reader in the interpreter (`jennifer`'s M30.11) would let
  the hand scanner go.

## Dependencies on the interpreter

- Floor `>=0.27.0` for `jennifer` and `jennifer-tiny`, for the UTF-8 codecs
  of `encoding.encode` / `decode` and `strings.replicate`; `xml.decode` with
  a namespace map (`jennifer`'s M28.34) needs 0.26.0.
- A reached cap as kind `"limit"` (M28.54, M28.55; the deck's caps moved
  under M28.57).
- The borrowed read-only parameters and copy-free returns of
  `0.25.0-dev+43` (the per-function borrow, M25.2) are what made the
  whole-document GPX read affordable. The copy elision still planned as
  M30.2 would cut the remaining per-point copies.
