#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * convert - read one format, write the other three.
 *
 * Every format reads into the same `Document` and every writer takes one, so a
 * conversion is a read and a write.
 *
 *   jennifer run examples/convert.j
 */

use io;
use fs;
use path;

import "../src/geo.j" as geo;

def dir as string init fs.makeTempDir();
defer fs.removeAll($dir);

# Build a small document by hand rather than shipping a fixture.
def doc as geo.Document init geo.document();
$doc.name = "Innsbruck loop";
$doc.desc = "Three stops and the ridge above them";
$doc.waypoints = [
    geo.named(geo.withElevation(geo.point(47.2692, 11.4041), 574.0), "Goldenes Dachl"),
    geo.named(geo.withElevation(geo.point(47.3122, 11.3889), 2334.0), "Nordkette")
];
$doc.tracks = [
    geo.track(
        "Ridge",
        [
            geo.withElevation(geo.point(47.3122, 11.3889), 2334.0),
            geo.withElevation(geo.point(47.3140, 11.3950), 2410.0),
            geo.withElevation(geo.point(47.3160, 11.4010), 2502.0)
        ])
];

io.printf("%s\n\n", geo.describe($doc));

def source as string init path.join($dir, "loop.gpx");
geo.save($doc, $source);

for (def name in ["loop.kml", "loop.kmz", "loop.geojson", "loop.gml"]) {
    def target as string init path.join($dir, $name);
    geo.convertFile($source, $target);
    def back as geo.Document init geo.open($target);
    def size as int init len(fs.readBytes($target));
    io.printf(
        "%s|pad=14|align=left %d|pad=6 bytes   reads back as: %s\n",
        $name,
        $size,
        geo.describe($back));
}

io.printf("\nthe GPX this started from:\n\n%s", fs.readString($source));
