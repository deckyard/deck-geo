<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# GPX

The GPS Exchange Format, the one of the five built for recorded tracks.

```jennifer
def doc as geo.Document init geo.openGpx("hike.gpx");
geo.saveGpx($doc, "out.gpx");
```

`readGpx` and `writeGpx` do the same over a string.

## Versions

GPX 1.0 and 1.1 are both read. 1.0 puts the document's `<name>`, `<desc>` and
`<time>` on the root, 1.1 inside `<metadata>`; both read into the `Document`
fields.

Output is always GPX 1.1 in the `GPX_NAMESPACE`. The `creator` attribute is
`$doc.creator` when set, so a file keeps naming the tool that recorded it,
which consumers use to anticipate quirks. An empty creator is written as
`GPX_CREATOR` (`"@deckyard/geo"`).

```jennifer
$doc.creator;   # "Garmin Edge 530", if that is what wrote it
```

## What is read

| Element | Becomes |
|---|---|
| `<metadata>` `<name>` `<desc>` `<time>` | the document's own fields |
| `<wpt>` | a waypoint |
| `<rte>` with `<rtept>` | a `Route` |
| `<trk>` with `<trkseg>` and `<trkpt>` | a `Track`, one `Segment` per `<trkseg>` |
| `<ele>` `<time>` `<name>` `<desc>` `<sym>` | the point's fields |
| `<type>` on a track | `Track.kind` |

`lat` and `lon` are required on every point. A complete point without them, or
with a value that does not parse or is out of range, raises.

## Extensions

`<extensions>` blocks (heart rate, cadence, temperature, power) are skipped:

```xml
<trkpt lat="47.2" lon="11.2">
  <ele>600</ele>
  <extensions>
    <gpxtpx:TrackPointExtension><gpxtpx:hr>140</gpxtpx:hr></gpxtpx:TrackPointExtension>
  </extensions>
</trkpt>
```

That reads as a point at latitude 47.2, longitude 11.2, elevation 600 m.
Fields are read from the point's direct children only, so a `<gpxtpx:ele>`
inside the extensions is not taken for the point's `<ele>`. Reading
extensions would need a schema per vendor; the element scanner they would
build on is `src/topics/scan.j`.

## Namespace prefixes

Both spellings read:

```xml
<gpx xmlns="http://www.topografix.com/GPX/1/1"><wpt lat="47" lon="11" /></gpx>
<gpx:gpx xmlns:gpx="..."><gpx:wpt gpx:lat="47" gpx:lon="11" /></gpx:gpx>
```

Elements and attributes are matched on their local part, so the prefix a file
chose, and the GPX version its namespace URI names, make no difference. The
reader decodes each point on its own, cut out of the file, against the
`xmlns` declarations on the root, which is where GPX files declare their
extension prefixes (`gpxtpx:` and the like). A file that uses a prefix it never
declares is read anyway, as damage rather than an error. Output is unprefixed,
with a default namespace.

## A file cut short

A recording that ended on a flat battery stops mid-element:

```xml
<gpx><trk><trkseg>
  <trkpt lat="47.0" lon="11.0"><ele>500</ele></trkpt>
  <trkpt lat="47.1" lon="11.1"><ele>5
```

That reads as a one-point track. A point whose closing tag never arrived is
dropped; the complete points before it are kept.

## Round trips

A document read, written and read again is unchanged, and a second write is
byte-identical to the first
(`testGpxRoundTripPreservesEverythingTheModelHolds`,
`testGpxRoundTripIsStableOnASecondPass`).
