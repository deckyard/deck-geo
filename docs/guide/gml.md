<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# GML geometry

The deck reads and writes a subset of GML.

GML (ISO 19136) is a framework from which an application schema builds a
format: hundreds of element types and no fixed document shape. The deck
implements the geometry vocabulary, which stays the same across application
schemas and is what WFS responses, INSPIRE data and GML embedded in other
documents carry.

```jennifer
def doc as geo.Document init geo.readGml($wfsResponse);
def out as string init geo.writeGml($doc);
```

## What is read

| Element | Becomes |
|---|---|
| `<gml:Point>` | a waypoint |
| `<gml:LineString>`, `<gml:Curve>`, `<gml:LinearRing>` | a track |
| `<gml:Polygon>` | one track per ring, exterior and interior |
| `<gml:MultiPoint>`, `<gml:MultiCurve>`, `<gml:MultiGeometry>`, `<gml:MultiSurface>` | each geometry inside |
| `<gml:pos>`, `<gml:posList>` | the coordinates |
| `<gml:coordinates>` | the coordinates, pre-3.0 spelling, `lon,lat` tuples as in KML |

Unlike KML and GeoJSON, a GML polygon's inner rings are not dropped: each
comes back as a track of its own after the outer ring.

Geometries are found at any depth, so an unknown application schema still
reads:

```xml
<wfs:FeatureCollection>
  <wfs:member>
    <app:Summit>
      <app:name>Peak</app:name>
      <app:where><gml:Point><gml:pos>47.0 11.0</gml:pos></gml:Point></app:where>
    </app:Summit>
  </wfs:member>
</wfs:FeatureCollection>
```

That reads as one waypoint called `Peak`. A feature's `name` (any prefix,
`gml:name` included) names the geometries inside it, inherited inwards. A bare
`<gml:Point>` as the whole document, as a WFS returns for a single geometry,
also reads.

Wrappers between a geometry and its coordinates are descended through rather
than listed: a polygon's `<gml:exterior>`/`<gml:LinearRing>`, a curve's
`<gml:segments>`/`<gml:LineStringSegment>`, and others of the same shape.
Descent stops at `MAX_NESTING` (100) levels.

## Axis order

GML does not fix whether a position is `lat lon` or `lon lat`; the coordinate
reference system does, and the common spellings of WGS 84 disagree:

| `srsName` | Axis order |
|---|---|
| `urn:ogc:def:crs:EPSG::4326` | latitude first |
| `http://www.opengis.net/def/crs/EPSG/0/4326` | latitude first |
| any other `urn:` or `opengis.net/def/crs/` name | latitude first |
| `CRS:84`, `urn:ogc:def:crs:OGC:1.3:CRS84`, any name containing `crs:84` or `crs84` | longitude first |
| `EPSG:4326`, and any other name | longitude first |
| absent | latitude first, the GML default |

The same two numbers name different places depending on that attribute. Both
of these are Innsbruck:

```xml
<gml:Point srsName="urn:ogc:def:crs:EPSG::4326"><gml:pos>47.3122 11.3889</gml:pos></gml:Point>
<gml:Point srsName="EPSG:4326"><gml:pos>11.3889 47.3122</gml:pos></gml:Point>
```

The `srsName` nearest the geometry applies; a geometry without one inherits
it from the closest enclosing element that has one. Names are compared
case-insensitively.

**No reprojection is performed.** Coordinates are read as WGS 84 degrees
whatever the CRS. A document in a projected system (a national grid, a UTM
zone) reads eastings and northings as degrees, and the range check usually
rejects them with an error.

## posList and srsDimension

`<gml:posList>` is a flat run of numbers; `srsDimension` says how many make
one position:

```xml
<gml:posList srsDimension="3">47.0 11.0 500 47.1 11.1 600</gml:posList>
```

Without `srsDimension`, 2 is assumed. Any value other than 2 or 3 raises, and so
does a count that does not divide into whole positions, rather than shifting
every coordinate after a stray number. A `<gml:pos>` is one position whatever
its length; a third number is the elevation.

## What is written

`writeGml` writes a GML 3.2 `gml:FeatureCollection` (`GML_NAMESPACE`) with the
document name as `gml:name` and one `gml:featureMember` per waypoint, route
and track segment. Each holds a `gml:Feature` with a `gml:name` and a
`gml:Point` (`gml:pos`) or a `gml:LineString` (`gml:posList`), in
`GML_CRS` (`urn:ogc:def:crs:EPSG::4326`), latitude first.

Positions are written two-dimensional (`srsDimension="2"`), so elevations are
dropped, as are descriptions, symbols and times. A path of fewer than two
points is not written.

The output is not schema-valid against any application schema, since GML has
no generic one. It carries geometry between readers of the same subset; to
conform to a specific schema, wrap the geometry yourself.
