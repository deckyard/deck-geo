#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * measure - what a recorded track adds up to.
 *
 * Distance, climb, time and speed, then the same track thinned at three
 * tolerances without losing its shape.
 *
 *   jennifer run examples/measure.j
 */

use io;
use math;
use convert;

import "../src/geo.j" as geo;

/**
 * A synthetic hour-long walk up a gentle grade: 120 fixes, one every thirty
 * seconds, with the elevation wander a real barometer shows.
 *
 * @return {list of geo.Point} the track, in order
 */
func recordedClimb() {
    def out as list of geo.Point init [];
    for (def i as int init 0; $i < 120; $i = $i + 1) {
        def step as float init convert.toFloat($i);
        # a curving path, so thinning it has something to preserve
        def turn as float init $step / 119.0 * math.PI / 2.0;
        def lat as float init 47.2692 + 0.012 * math.sin($turn);
        def lon as float init 11.4041 + 0.018 * (1.0 - math.cos($turn));
        # +1 m per fix, with 6 m of wander either way on top: a barometer that
        # drifts over ground that undulates, which is what a real elevation
        # trace looks like on a gentle grade
        def ele as float init 574.0 + $step * 1.0 + math.sin($step / 3.0) * 6.0;
        def minute as string init io.sprintf("%d|pad=2|fill=0", ($i * 30) // 60);
        def second as string init io.sprintf("%d|pad=2|fill=0", ($i * 30) % 60);
        def at as string init "2026-09-30T06:" + $minute + ":" + $second + "Z";
        $out[] = geo.withTime(geo.withElevation(geo.point($lat, $lon), $ele), $at);
    }
    return $out;
}

def points as list of geo.Point init recordedClimb();
def stats as geo.TrackStats init geo.statsOf($points);

io.printf("points        %d\n", $stats.points);
io.printf("distance      %f|prec=2 km\n", $stats.distance / 1000.0);
io.printf("climb         %f|prec=0 m up, %f|prec=0 m down\n", $stats.ascent, $stats.descent);
io.printf("elevation     %f|prec=0 m to %f|prec=0 m\n", $stats.minElevation, $stats.maxElevation);
io.printf("elapsed       %d s, moving %d s\n", $stats.totalSeconds, $stats.movingSeconds);
io.printf(
    "speed         %f|prec=2 m/s average, %f|prec=2 m/s peak\n",
    $stats.averageSpeed,
    $stats.maxSpeed);

# The sensor wander is 1.5 m either way; the deck's threshold does not count it.
def naive as geo.TrackStats init geo.statsWith($points, 0.0, geo.MOVING_SPEED);
io.printf(
    "\nthreshold     %f|prec=0 m counted, against %f|prec=0 m with no\n",
    $stats.ascent,
    $naive.ascent);
io.printf("              threshold at all - which counts every upward twitch of\n");
io.printf("              the sensor as ground gained.\n");

def box as geo.Bounds init geo.bounds($points);
io.printf(
    "\nbounds        %f|prec=4 %f|prec=4 to %f|prec=4 %f|prec=4\n",
    $box.minLat,
    $box.minLon,
    $box.maxLat,
    $box.maxLon);
def middle as geo.Point init geo.centroid($points);
io.printf("centroid      %f|prec=5 %f|prec=5\n", $middle.lat, $middle.lon);

for (def tolerance in [1.0, 5.0, 25.0]) {
    def thin as list of geo.Point init geo.simplify($points, $tolerance);
    def kept as float init convert.toFloat(len($thin)) / convert.toFloat(len($points));
    io.printf(
        "simplify %f|prec=0 m   %d points (%f|prec=0%% of the track), " + "%f|prec=2 km\n",
        $tolerance,
        len($thin),
        $kept * 100.0,
        geo.pathLength($thin) / 1000.0);
}
