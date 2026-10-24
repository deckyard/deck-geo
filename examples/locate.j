#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * locate - geodesy, geofencing and the two addressing schemes.
 *
 * Distances and bearings between places, a fence to test them against, and the
 * geohash and map tile each one falls in.
 *
 *   jennifer run examples/locate.j
 */

use io;

import "../src/geo.j" as geo;

def innsbruck as geo.Point init geo.named(geo.point(47.2692, 11.4041), "Innsbruck");
def vienna as geo.Point init geo.named(geo.point(48.2082, 16.3738), "Vienna");
def munich as geo.Point init geo.named(geo.point(48.1351, 11.5820), "Munich");
def places as list of geo.Point init [$innsbruck, $vienna, $munich];

io.printf("from Innsbruck:\n");
for (def place in [$vienna, $munich]) {
    io.printf(
        "  %s|pad=10|align=left %f|prec=1 km   bearing %f|prec=1 deg out, " + "%f|prec=1 deg in\n",
        $place.name,
        geo.distance($innsbruck, $place) / 1000.0,
        geo.bearing($innsbruck, $place),
        geo.finalBearing($innsbruck, $place));
}

# Dead reckoning: the inverse of a bearing and a distance.
def heading as float init geo.bearing($innsbruck, $vienna);
def metres as float init geo.distance($innsbruck, $vienna);
def arrived as geo.Point init geo.destination($innsbruck, $heading, $metres);
io.printf(
    "\nholding %f|prec=1 deg for %f|prec=1 km from Innsbruck lands at\n",
    $heading,
    $metres / 1000.0);
io.printf(
    "  %f|prec=4 %f|prec=4 - %f|prec=2 m from Vienna\n",
    $arrived.lat,
    $arrived.lon,
    geo.distance($arrived, $vienna));

def half as geo.Point init geo.midpoint($innsbruck, $vienna);
io.printf("  the midpoint is %f|prec=4 %f|prec=4\n", $half.lat, $half.lon);

# A fence around Tyrol, roughly. A polygon closes implicitly.
def tyrol as list of geo.Point init [
    geo.point(47.0, 10.5),
    geo.point(47.0, 12.2),
    geo.point(47.6, 12.2),
    geo.point(47.6, 10.5)
];

io.printf("\ninside the Tyrol fence:\n");
for (def place in $places) {
    def inside as bool init geo.pointInPolygon($place, $tyrol);
    io.printf("  %s|pad=10|align=left %t\n", $place.name, $inside);
}

def box as geo.Bounds init geo.bounds($places);
io.printf(
    "\nall three fit in %f|prec=3 %f|prec=3 to %f|prec=3 %f|prec=3\n",
    $box.minLat,
    $box.minLon,
    $box.maxLat,
    $box.maxLon);

io.printf("\naddressing:\n");
for (def place in $places) {
    def hash as string init geo.geohash($place, 7);
    def tile as geo.Tile init geo.tileOf($place, 12);
    io.printf(
        "  %s|pad=10|align=left geohash %s   tile %d/%d/%d   quadkey %s\n",
        $place.name,
        $hash,
        $tile.z,
        $tile.x,
        $tile.y,
        geo.quadkey($tile));
}

# A geohash prefix is a proximity test, which is what makes it a usable key.
def near as geo.Point init geo.destination($innsbruck, 30.0, 40.0);
io.printf("\n40 m from Innsbruck hashes to %s,\n", geo.geohash($near, 9));
io.printf(
    "against %s for Innsbruck itself - the shared prefix is the distance.\n",
    geo.geohash($innsbruck, 9));
