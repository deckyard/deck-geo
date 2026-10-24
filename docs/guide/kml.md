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
holes) are dropped. `<TimeStamp>` and `<gx:Track>` are not read, and nothing
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

**`readKmz` decompresses the whole archive into memory, with no limit.** Zip
compresses XML at better than 400:1, so a 1 MB archive can expand to half a
gigabyte and a 20 MB one to 10 GB. `archive.unpack` takes a buffer and returns
every entry decompressed, so there is no size limit to pass.

For KMZ files from an untrusted source, reject archives above a size you can
afford to decompress a few hundred times over, or read them in a process you
can afford to lose. The four text formats have no such hazard: a reader holds
the input plus the points read so far.

Entry names are never used as paths, so an entry that tries to escape its
directory does no harm; `archive.unpack` rejects one anyway.

## Nesting

Folder depth comes from the file, and each level rescans the range inside it,
so the cost grows with the square of the depth. Before the cap, 800 nested
folders in a 13 KB file took 11 seconds to read. `MAX_NESTING` (100) bounds
it; a deeper document raises.
