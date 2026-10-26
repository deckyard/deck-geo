#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * doc-claims - assert that the values the guides print are what the code
 * returns.
 *
 * `tools/check-docs.sh` runs this and compares its output to the markdown:
 * every integer a guide annotates a snippet with must be one of the values
 * claimed here, labelled with that guide's path, and every listing printed
 * here must appear verbatim in the guide it names.
 *
 * Two output shapes, both read by check-docs.sh:
 *
 *   claim <doc> <what> => <value>
 *   <<<listing <doc> ... >>>
 *
 *   jennifer run tools/doc-claims.j
 */

use io;
use math;
use strings;

import "../src/geo.j" as geo;

def failures as int init 0;

/**
 * Print one claim, and check it.
 *
 * @param doc {string} the guide that prints this value
 * @param what {string} the expression the guide shows
 * @param actual {int} what the code returns
 * @param expected {int} what the guide says
 */
func claim(doc as string, what as string, actual as int, expected as int) {
    if ($actual == $expected) {
        io.printf("claim %s %s => %d\n", $doc, $what, $actual);
        return;
    }
    $failures = $failures + 1;
    io.printf("MISMATCH %s: %s is %d, the guide says %d\n", $doc, $what, $actual, $expected);
}

/**
 * Print one claim about a float, rounded to a whole number.
 *
 * The guides quote distances to the metre, so the comparison is to the metre.
 *
 * @param doc {string} the guide that prints this value
 * @param what {string} the expression the guide shows
 * @param actual {float} what the code returns
 * @param expected {int} what the guide says, rounded
 */
func claimRounded(doc as string, what as string, actual as float, expected as int) {
    claim($doc, $what, math.round($actual), $expected);
}

/** Innsbruck, the point every guide measures from. */
func innsbruck() {
    return geo.point(47.2692, 11.4041);
}

/** Vienna, the point every guide measures to. */
func vienna() {
    return geo.point(48.2082, 16.3738);
}

# --- guide/measuring.md -----------------------------------------------------
#
# The two numbers the distance-and-bearing section opens with.

claimRounded(
    "docs/guide/measuring.md",
    "distance(innsbruck, vienna)",
    geo.distance(innsbruck(), vienna()),
    385944);
claimRounded(
    "docs/guide/measuring.md",
    "bearing(innsbruck, vienna)",
    geo.bearing(innsbruck(), vienna()) * 10.0,
    725);
# The guide prints these to one decimal place, so the whole part is what its
# annotation carries - and what check-docs.sh compares against.
claim(
    "docs/guide/measuring.md",
    "distance(innsbruck, vienna) whole metres",
    math.trunc(geo.distance(innsbruck(), vienna())),
    385943);
claim(
    "docs/guide/measuring.md",
    "bearing(innsbruck, vienna) whole degrees",
    math.trunc(geo.bearing(innsbruck(), vienna())),
    72);

# --- guide/addressing.md ---------------------------------------------------
#
# The tile the quadkey section addresses, and the quadkey itself.

def tile as geo.Tile init geo.tileOf(innsbruck(), 14);
claim("docs/guide/addressing.md", "tileOf(innsbruck, 14).x", $tile.x, 8711);
claim("docs/guide/addressing.md", "tileOf(innsbruck, 14).y", $tile.y, 5744);

/**
 * Check a string the guides quote.
 *
 * @param doc {string} the guide that prints it
 * @param what {string} the expression the guide shows
 * @param actual {string} what the code returns
 * @param expected {string} what the guide says
 */
func claimText(doc as string, what as string, actual as string, expected as string) {
    if ($actual == $expected) {
        io.printf("claim %s %s => %s\n", $doc, $what, $actual);
        return;
    }
    $failures = $failures + 1;
    io.printf(
        "MISMATCH %s: %s is \"%s\", the guide says \"%s\"\n",
        $doc,
        $what,
        $actual,
        $expected);
}

claimText(
    "docs/guide/addressing.md",
    "quadkey(tileOf(innsbruck, 14))",
    geo.quadkey($tile),
    "12023002220111");
claimText(
    "docs/guide/addressing.md",
    "geohash(innsbruck, 7)",
    geo.geohash(innsbruck(), 7),
    "u22hgt0");

# The prefix property the addressing guide asserts in prose.
def long as string init geo.geohash(innsbruck(), 9);
claimText(
    "docs/guide/addressing.md",
    "geohash(innsbruck, 9) truncated to 5",
    strings.substring($long, 0, 5),
    geo.geohash(innsbruck(), 5));

# --- guide/model.md --------------------------------------------------------
#
# The describe() line the model guide prints.

def loop as geo.Document init geo.document();
$loop.name = "Innsbruck loop";
$loop.waypoints = [geo.named(innsbruck(), "Goldenes Dachl")];
$loop.tracks = [geo.track("Day 1", [innsbruck(), vienna()])];
claimText(
    "docs/guide/model.md",
    "describe(doc)",
    geo.describe($loop),
    "Innsbruck loop: 1 waypoint, 1 track, 3 points");

# The guide shows that a stated sea-level elevation and an unstated one both
# read 0.0, and that only hasElevation tells them apart.
def atSeaLevel as geo.Point init geo.withElevation(geo.point(0.0, 0.0), 0.0);
def unstated as geo.Point init geo.point(0.0, 0.0);
claim("docs/guide/model.md", "a stated sea-level elevation", math.trunc($atSeaLevel.ele), 0);
claim("docs/guide/model.md", "an unstated elevation", math.trunc($unstated.ele), 0);
if (not $atSeaLevel.hasElevation or $unstated.hasElevation) {
    $failures = $failures + 1;
    io.printf("MISMATCH docs/guide/model.md: hasElevation does not tell a stated " +
        "sea-level elevation from an unstated one\n");
}

# --- the listings the guides show verbatim ---------------------------------
#
# A writer's output drifting from what a guide prints is the failure mode a
# human reviewer never catches. Each line below must appear in the named file.

def waypointOnly as geo.Document init geo.document();
$waypointOnly.waypoints = [innsbruck()];
def minimal as string init geo.writeGpx($waypointOnly);

io.printf("<<<listing docs/guide/formats.md\n");
for (def line in strings.split($minimal, "\n")) {
    def trimmed as string init strings.trim($line);
    if (strings.startsWith($trimmed, "<wpt")) {
        io.printf("%s\n", $trimmed);
    }
}
io.printf(">>>\n");

# The GML axis-order examples, both of which must name Innsbruck.
def urnForm as string init "<gml:Point srsName=\"urn:ogc:def:crs:EPSG::4326\">" +
    "<gml:pos>47.3122 11.3889</gml:pos></gml:Point>";
def shortForm as string init "<gml:Point srsName=\"EPSG:4326\">" +
    "<gml:pos>11.3889 47.3122</gml:pos></gml:Point>";
def fromUrn as geo.Point init geo.readGml($urnForm).waypoints[0];
def fromShort as geo.Point init geo.readGml($shortForm).waypoints[0];
claimRounded(
    "docs/guide/gml.md",
    "the URN form reads latitude first",
    $fromUrn.lat * 10000.0,
    473122);
claimRounded(
    "docs/guide/gml.md",
    "the short form reads longitude first",
    $fromShort.lat * 10000.0,
    473122);
if ($fromUrn.lat != $fromShort.lat or $fromUrn.lon != $fromShort.lon) {
    $failures = $failures + 1;
    io.printf("MISMATCH docs/guide/gml.md: the two axis-order examples are not " +
        "the same place\n");
}

if ($failures > 0) {
    io.printf("%d claim(s) do not match the code\n", $failures);
    exit 1;
}
io.printf("every claim matches the code\n");
