# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * White-box unit tests for the geo module.
 *
 * Runs as the co-located test overlay: `jennifer test src/geo_test.j`.
 * The tests are split into topic files under `topics/`, spliced together here
 * with `include` - one test file per implementation topic file, in the same
 * order `geo.j` splices the topics themselves.
 *
 * Almost all of the deck is pure computation over text and numbers, so almost
 * all of it is covered here directly: the entity codec, the element scanner
 * against malformed and awkward markup, the geodesy formulae against known
 * distances and against their own inverses, the simplifier, every container
 * format in both directions, and the round trip between all four. The handful
 * of functions that touch the filesystem - `open`, `save`, `openGpx` and their
 * siblings - are covered through a temporary directory in `file_test.j`.
 *
 * The fixtures the format overlays build their documents from live in
 * `model_test.j`.
 */

use testing;
use strings;
use convert;
use binary;
use math;
use io;
use fs;
use path;
use time;
use json;
use archive;
use encoding;

include "topics/core_test.j";
include "topics/model_test.j";
include "topics/geodesy_test.j";
include "topics/geometry_test.j";
include "topics/stats_test.j";
include "topics/geohash_test.j";
include "topics/tile_test.j";
include "topics/scan_test.j";
include "topics/gpx_test.j";
include "topics/kml_test.j";
include "topics/geojson_test.j";
include "topics/gml_test.j";
include "topics/file_test.j";
