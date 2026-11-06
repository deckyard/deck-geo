<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# KML and KMZ

KML 2.2, the OGC standard that started as Google Earth's format, and KMZ, its
zipped form.

```jennifer
def doc as geo.Document init geo.openKml("places.kml");
geo.saveKml($doc, "out.kml");

def zipped as geo.Document init geo.openKmz("places.kmz");
geo.saveKmz($zipped, "out.kmz");
```

## Longitude first

A KML tuple is `lon,lat` or `lon,lat,ele`, the reverse of GPX's attribute
order. The deck swaps it on read and write:

```xml
<coordinates>11.3889,47.3122,2334</coordinates>
```

reads as latitude 47.3122, longitude 11.3889, elevation 2334 m. Tuples are
separated by any run of whitespace, newlines and indentation included.

## What is read

| Element | Becomes |
|---|---|
| `<Document>` `<name>` `<description>` | the document's own fields |
| `<Placemark>` with `<Point>` | a waypoint |
| `<Placemark>` with `<LineString>` | a single-segment track |
| `<Placemark>` with `<LinearRing>` | a track along the ring |
| `<Placemark>` with `<Polygon>` | a track along the outer ring |
| `<MultiGeometry>` | each geometry inside it, separately |
| `<styleUrl>` | `Point.sym` of a waypoint |

`<Folder>` and nested `<Document>` elements are walked to any depth up to
`MAX_NESTING`, and the nesting is flattened. A polygon's inner rings (its
holes) are dropped; a polygon whose outer ring is empty contributes nothing.
`<TimeStamp>` and `<gx:Track>` are not read, and nothing
is written for them, so a track converted to KML loses its timing and with it
everything [`statsOf`](measuring.md) derives from timing.

## What is written

Waypoints become `Placemark`/`Point`, routes and tracks `Placemark`/`LineString`.
A track with several segments is written as one `MultiGeometry` of
`LineString`s:

```jennifer
def back as geo.Document init geo.readKml(geo.writeKml($doc));
```

A two-segment track comes back as two tracks: the points and the breaks
survive, the grouping does not, because KML cannot say that two lines in one
placemark are runs of one recording. A path of fewer than two points is not
written; write it as a waypoint. `sym` is not written.

Names and descriptions are trimmed on read, because KML is routinely indented
inside its elements, so leading and trailing whitespace does not survive a
round trip, and a name of only whitespace is not written.

## KMZ

A KMZ is a zip holding a KML document and the files it references. `readKmz`
reads the entry named `doc.kml` (`KMZ_ENTRY`, compared case-insensitively),
which is what Google Earth opens. Without one it takes the first `.kml` at the
root of the archive, then the first `.kml` anywhere, because a KMZ can carry
other KML, such as a legend, listed first. Other entries are ignored.

```jennifer
def doc as geo.Document init geo.readKmz(fs.readBytes("places.kmz"));
```

`writeKmz` writes an archive with a single `doc.kml` entry. A KMZ is typically
about a third the size of its KML.

### Untrusted KMZ files

Zip compresses XML at better than 400:1, so the size of a KMZ says little
about what it unpacks to: a 1 MB archive can expand to half a gigabyte.
`readKmz` therefore inflates through `archive.unpackWith` with two caps, and
refuses the archive with `kind` `"geo"` as soon as one is passed:

| Cap | Value | Bounds |
|---|---|---|
| `MAX_KMZ_ENTRY_BYTES` | 16 MiB | any one entry, the KML or a file beside it |
| `MAX_KMZ_TOTAL_BYTES` | 64 MiB | all entries together |

The message names the cap that was passed. The total matters on its own:
fifteen entries just under 16 MiB fit in a 246 KB archive. An archive with
more than 65,536 entries is refused by `archive` itself.

16 MiB is already a large KML: reading one costs far more memory than its
text. For a trusted archive that needs more, unpack it yourself with
`archive.unpackWith` and larger `maxEntryBytes` / `maxTotalBytes`, and pass
the KML entry's text to `readKml`.

A symbolic link, device or FIFO member holds no file, so it is skipped rather
than refusing the archive.

Entry names are never used as paths, so an entry that tries to escape its
directory does no harm; `archive.unpack` rejects one anyway.

## Nesting

Folder depth comes from the file, and each level rescans the range inside it,
so the cost grows with the square of the depth. Before the cap, 800 nested
folders in a 13 KB file took 11 seconds to read. `MAX_NESTING` (100) bounds
it; a deeper document raises.
