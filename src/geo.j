# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * geo - read, edit and write geographic coordinate formats.
 *
 * Five formats over one point model, plus the measurement layer on top:
 *
 *   model       {@link Point} / {@link Track} / {@link Route} / {@link Document}
 *   any format  {@link open} / {@link save} / {@link formatOf}
 *   GPX         {@link readGpx} / {@link writeGpx}
 *   KML, KMZ    {@link readKml} / {@link writeKml} / {@link readKmz} / {@link writeKmz}
 *   GeoJSON     {@link readGeojson} / {@link writeGeojson}
 *   GML         {@link readGml} / {@link writeGml}
 *   geodesy     {@link distance} / {@link bearing} / {@link destination}
 *   geometry    {@link bounds} / {@link centroid} / {@link simplify}
 *   statistics  {@link statsOf} / {@link TrackStats}
 *   addressing  {@link geohash} / {@link tileOf}
 *
 * Every reader returns a {@link Document} and every writer takes one, so a
 * conversion is a read and a write. Coordinates are WGS 84 degrees, latitude
 * before longitude in every signature whatever order the format writes;
 * distances are metres on a sphere of {@link EARTH_RADIUS}.
 *
 * The XML codecs never decode a whole document into a tree: a scanner walks
 * the element boundaries and `xml.decode` reads one leaf at a time, so peak
 * memory follows the result rather than the file size
 * (`docs/internal/memory.md`).
 *
 * A function that changes a point, a track or a document returns a new value
 * and leaves its argument alone: `$x = something($x, ...)`.
 *
 * The topic files under `topics/` are spliced in with `include`, so this file
 * is the module boundary and carries every `export`. The white-box tests are
 * in `geo_test.j`.
 *
 * @module geo
 * @see https://www.topografix.com/GPX/1/1/
 * @see https://www.ogc.org/standard/kml/
 * @see https://datatracker.ietf.org/doc/html/rfc7946
 * @example
 *   import "@deckyard/geo/" as geo;
 *
 *   def doc as geo.Document init geo.open("hike.gpx");
 *   def stats as geo.TrackStats init geo.statsOf($doc.tracks[0].segments[0].points);
 *   io.printf("%f|prec=1 km, %f|prec=0 m up\n", $stats.distance / 1000.0, $stats.ascent);
 *
 *   geo.save($doc, "hike.kml");
 */

use strings;
use convert;
use binary;
use math;
use io;
use fs;
use path;
use time;
use json;
use xml;
use archive;
use encoding;
use regex;

include "topics/version.j";
include "topics/core.j";
include "topics/model.j";
include "topics/geodesy.j";
include "topics/geometry.j";
include "topics/stats.j";
include "topics/geohash.j";
include "topics/tile.j";
include "topics/scan.j";
include "topics/gpx.j";
include "topics/kml.j";
include "topics/geojson.j";
include "topics/gml.j";
include "topics/file.j";
