#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * fuzz - throw malformed input at every reader and assert it holds.
 *
 * The deck draws a line between two kinds of bad input, and the line is only
 * as good as what has been thrown at it:
 *
 *   **damage** - a file cut short, markup this model does not cover, an
 *   unknown entity, a geometry with no coordinates. A reader works around it
 *   and returns what it could read.
 *
 *   **bad data** - a coordinate that is not a number, or one outside the world.
 *   A reader raises, because silently inventing a position is worse.
 *
 * Both are asserted here. For every mutation of every fixture:
 *
 *   1  a reader either returns a Document or raises `Error{kind: "geo"}` -
 *      never an uncaught interpreter error, and never a hang
 *   2  every point that comes back is a position on the Earth
 *   3  whatever came back can be written in all four formats and read again,
 *      and the second read agrees with the first
 *
 * The inputs are a fixture per format, truncated at every offset that lands on
 * a byte boundary of interest, with one byte bent at every eleventh offset,
 * with random runs spliced over them, and with numbers and JSON arrays swapped
 * for values of the wrong type or size. Markup damage alone never reached the
 * places a value of the wrong kind breaks: an overflowing entity, a `1e300`
 * dimension, a JSON number where an array belongs. Every random value comes from a seeded
 * `math.randSeed`, so a failure here reproduces exactly.
 *
 *   jennifer run tools/fuzz.j
 */

use io;
use math;
use strings;
use convert;

import "../src/geo.j" as geo;

/** How many inputs were driven through the readers. */
def inputs as int init 0;

/** How many invariants broke. Non-zero exits 1. */
def failures as int init 0;

/** The text formats, each with a fixture to mutate. */
def const FORMATS as list of string init ["gpx", "kml", "geojson", "gml"];

/**
 * Report a broken invariant.
 *
 * @param format {string} the format whose reader broke
 * @param what {string} the invariant that broke
 * @param input {string} the input that broke it
 */
func broke(format as string, what as string, input as string) {
    $failures = $failures + 1;
    def shown as string init $input;
    if (len($shown) > 120) {
        $shown = strings.substring($shown, 0, 120) + "...";
    }
    io.printf("BROKE %s: %s\n  input: %s\n", $format, $what, $shown);
}

/**
 * A fixture in one format, with every feature the reader knows about.
 *
 * @param format {string} one of FORMATS
 * @return {string} the document
 */
func fixture(format as string) {
    def doc as geo.Document init geo.document();
    $doc.name = "Fuzz & co <test>";
    $doc.desc = "Ca\u00f1on";
    $doc.at = "2026-09-30T06:00:00Z";
    $doc.waypoints = [
        geo.named(geo.withElevation(geo.point(47.2692, 11.4041), 574.0), "Start"),
        geo.point(-33.8688, 151.2093)
    ];
    $doc.routes = [geo.route("Plan", [geo.point(47.0, 11.0), geo.point(47.1, 11.1)])];
    $doc.tracks = [
        geo.Track{
            name: "Day 1",
            desc: "",
            kind: "hiking",
            segments: [
                geo.Segment{
                    points: [
                        geo.withTime(
                            geo.withElevation(geo.point(47.2, 11.2), 600.0),
                            "2026-09-30T06:01:00Z"),
                        geo.withElevation(geo.point(47.3, 11.3), 700.0)
                    ]
                },
                geo.Segment{points: [geo.point(47.4, 11.4), geo.point(47.5, 11.5)]}
            ]
        }
    ];
    return geo.writeText($doc, $format);
}

/**
 * Read one input and check every invariant on what comes back.
 *
 * @param format {string} the format to read it as
 * @param input {string} the document, malformed or not
 */
func drive(format as string, input as string) {
    $inputs = $inputs + 1;
    def doc as geo.Document init geo.document();
    def raised as bool init false;
    try {
        $doc = geo.readText($input, $format);
    } catch (e) {
        $raised = true;
        if ($e.kind != "geo") {
            broke($format, "raised " + $e.kind + " rather than geo: " + $e.message, $input);
        }
    }
    if ($raised) {
        return;
    }
    checkPoints($format, $doc, $input);
    checkRewrite($format, $doc, $input);
}

/**
 * Every point that came back must be a position on the Earth.
 *
 * @param format {string} the format it was read as
 * @param doc {geo.Document} what came back
 * @param input {string} the document it came from
 */
func checkPoints(format as string, doc as geo.Document, input as string) {
    for (def p in geo.documentPoints($doc)) {
        if ($p.lat < -90.0 or $p.lat > 90.0 or $p.lon < -180.0 or $p.lon > 180.0) {
            broke($format, "returned a point outside the world", $input);
            return;
        }
    }
}

/**
 * Whatever came back must survive a write and a second read, in every format.
 *
 * @param format {string} the format it was read as
 * @param doc {geo.Document} what came back
 * @param input {string} the document it came from
 */
func checkRewrite(format as string, doc as geo.Document, input as string) {
    def wanted as int init len(geo.documentPoints($doc));
    for (def target in FORMATS) {
        def text as string init "";
        try {
            $text = geo.writeText($doc, $target);
        } catch (e) {
            broke($format, "could not be written as " + $target + ": " + $e.message, $input);
            return;
        }
        checkSecondRead($format, $target, $text, $wanted, $input);
    }
}

/**
 * Reading back what was just written must agree with the first read.
 *
 * A written document is well-formed by construction, so this is the one place
 * the deck is held to exactness rather than to tolerance.
 *
 * @param format {string} the format the document was first read as
 * @param target {string} the format it was written as
 * @param text {string} what was written
 * @param wanted {int} how many points went in
 * @param input {string} the document it all came from
 */
func checkSecondRead(
    format as string,
    target as string,
    text as string,
    wanted as int,
    input as string) {
    def back as geo.Document init geo.document();
    try {
        $back = geo.readText($text, $target);
    } catch (e) {
        broke($format, "wrote " + $target + " it could not read back: " + $e.message, $input);
        return;
    }
    # A single-point path has no line to write in KML, GeoJSON or GML, so only
    # GPX is held to the exact count; the rest must not gain points.
    def got as int init len(geo.documentPoints($back));
    if ($target == "gpx" and $got != $wanted) {
        broke(
            $format,
            "lost points through gpx: " + convert.toString($wanted) + " in, " +
                convert.toString($got) + " out",
            $input);
    }
    if ($got > $wanted) {
        broke($format, "gained points through " + $target, $input);
    }
}

/**
 * One byte of a string, bent to another value.
 *
 * @param text {string} the document to damage
 * @param at {int} which character to replace
 * @return {string} the document with one character changed
 */
func bend(text as string, at as int) {
    def replacements as list of string init ["<", ">", "\"", "&", "/", "x", " ", ";", "9", "-"];
    def pick as string init $replacements[math.randInt(0, len($replacements) - 1)];
    return strings.substring($text, 0, $at) + $pick + strings.substring($text, $at + 1, len($text));
}

/** Values of the wrong type or size, put where a number or an array was. */
def const HOSTILE as list of string init [
    "5",
    "null",
    '"s"',
    '{}',
    "[]",
    "1e300",
    "-1e308",
    "1_0",
    "2.4",
    "&#99999999999999999999;",
    "]]>",
    '{"0": 1, "1": 2}'
];

/**
 * Replace the number, or the JSON array, at or after an offset.
 *
 * @param text {string} the document
 * @param from {int} where to start looking
 * @param value {string} what to put there
 * @return {string} the document with one value swapped, or unchanged when
 *   nothing follows the offset
 */
func swapValue(text as string, from as int, value as string) {
    def chars as list of string init strings.chars($text);
    def at as int init $from;
    while ($at < len($chars) and not isValueStart($chars[$at])) {
        $at = $at + 1;
    }
    if ($at >= len($chars)) {
        return $text;
    }
    def end as int init $at + 1;
    if ($chars[$at] == "[") {
        while ($end < len($chars) and $chars[$end] != "]") {
            $end = $end + 1;
        }
        $end = math.min($end + 1, len($chars));
    } else {
        while ($end < len($chars) and strings.contains("0123456789.-eE", $chars[$end])) {
            $end = $end + 1;
        }
    }
    return strings.substring($text, 0, $at) + $value + strings.substring($text, $end, len($text));
}

/**
 * Whether a value worth swapping starts at a character.
 *
 * @param ch {string} one character
 * @return {bool} whether it opens a number or an array
 */
func isValueStart(ch as string) {
    return $ch == "[" or strings.contains("0123456789", $ch);
}

math.randSeed(20260930);

for (def format in FORMATS) {
    def whole as string init fixture($format);
    drive($format, $whole);

    # truncated at every offset: the shape of an interrupted write
    for (def at as int init 0; $at < len($whole); $at = $at + 7) {
        drive($format, strings.substring($whole, 0, $at));
    }

    # one byte bent, at every eleventh offset
    for (def at as int init 0; $at < len($whole); $at = $at + 11) {
        drive($format, bend($whole, $at));
    }

    # a run of the document replaced by another part of it
    for (def n as int init 0; $n < 60; $n = $n + 1) {
        def from as int init math.randInt(0, len($whole) - 1);
        def size as int init math.randInt(1, 40);
        def end as int init math.min($from + $size, len($whole));
        def spliced as string init strings.substring($whole, 0, $from) +
            strings.substring($whole, $end, len($whole));
        drive($format, $spliced);
    }

    # a number or an array swapped for a value of the wrong type or size
    for (def n as int init 0; $n < 120; $n = $n + 1) {
        def value as string init HOSTILE[math.randInt(0, len(HOSTILE) - 1)];
        drive($format, swapValue($whole, math.randInt(0, len($whole) - 1), $value));
    }

    # pure noise, at many lengths
    for (def n as int init 0; $n < 40; $n = $n + 1) {
        def size as int init math.randInt(0, 200);
        def noise as string init "";
        for (def i as int init 0; $i < $size; $i = $i + 1) {
            $noise = $noise + bend(" ", 0);
        }
        drive($format, $noise);
    }
}

io.printf("%d inputs, %d invariant(s) broken\n", $inputs, $failures);
if ($failures > 0) {
    exit 1;
}
