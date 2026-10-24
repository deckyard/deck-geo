# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - the one point model every codec reads into and writes out of.
# Spliced into geo.j via include - not a standalone module.

/**
 * One position on the Earth, with whatever the file said about it.
 *
 * A waypoint, a track or route point, or one vertex of a line, in any of the
 * five formats. A field the source did not carry is left at its zero value;
 * `hasElevation` and `hasTime` tell a writer whether `ele` and `at` were
 * stated, so sea level is not confused with "no elevation".
 *
 * @field lat {float} degrees north of the equator, -90 to 90
 * @field lon {float} degrees east of Greenwich, -180 to 180
 * @field ele {float} elevation in metres, as the source gives it; no datum conversion
 * @field hasElevation {bool} whether `ele` came from the source
 * @field at {string} when the point was recorded, as RFC 3339
 * @field hasTime {bool} whether `at` came from the source
 * @field name {string} what the source called it
 * @field desc {string} a longer description
 * @field sym {string} the symbol or style name to draw it with
 */
export def struct Point {
    lat as float,
    lon as float,
    ele as float,
    hasElevation as bool,
    at as string,
    hasTime as bool,
    name as string,
    desc as string,
    sym as string
};

/**
 * One unbroken run of track points.
 *
 * A GPX `<trkseg>`. A track starts a new segment wherever the recorder lost
 * its fix, so the gap between segments was not travelled; {@link trackDistance}
 * measures per segment.
 *
 * @field points {list of Point} the positions, in the order recorded
 */
export def struct Segment {
    points as list of Point
};

/**
 * A recorded path: where something went.
 *
 * @field name {string} what the source called it
 * @field desc {string} a longer description
 * @field kind {string} the activity, as GPX `<type>` spells it
 * @field segments {list of Segment} the runs of points, in order
 */
export def struct Track {
    name as string,
    desc as string,
    kind as string,
    segments as list of Segment
};

/**
 * A planned path: where something is meant to go.
 *
 * GPX keeps routes and tracks apart; KML, GeoJSON and GML do not, so a line
 * read from them is a track, and a route written to them is read back as one.
 *
 * @field name {string} what the source called it
 * @field desc {string} a longer description
 * @field points {list of Point} the points to visit, in order
 */
export def struct Route {
    name as string,
    desc as string,
    points as list of Point
};

/**
 * A whole file, in the shape every codec in this deck reads and writes.
 *
 * @field name {string} the document title
 * @field desc {string} a longer description
 * @field creator {string} what wrote the file
 * @field at {string} when the file was written, as RFC 3339
 * @field waypoints {list of Point} standalone points of interest
 * @field routes {list of Route} planned paths
 * @field tracks {list of Track} recorded paths
 */
export def struct Document {
    name as string,
    desc as string,
    creator as string,
    at as string,
    waypoints as list of Point,
    routes as list of Route,
    tracks as list of Track
};

/**
 * A latitude and longitude rectangle.
 *
 * @field minLat {float} the southern edge
 * @field minLon {float} the western edge
 * @field maxLat {float} the northern edge
 * @field maxLon {float} the eastern edge
 */
export def struct Bounds {
    minLat as float,
    minLon as float,
    maxLat as float,
    maxLon as float
};

/**
 * One point, from a latitude and a longitude.
 *
 * @param lat {float} degrees north, -90 to 90
 * @param lon {float} degrees east, -180 to 180
 * @return {Point} the point, with nothing else stated
 * @throws {Error} when either coordinate is outside its range
 * @example
 *   def innsbruck as geo.Point init geo.point(47.2692, 11.4041);
 */
export func point(lat as float, lon as float) {
    checkCoord($lat, $lon);
    return Point{
        lat: $lat,
        lon: $lon,
        ele: 0.0,
        hasElevation: false,
        at: "",
        hasTime: false,
        name: "",
        desc: "",
        sym: ""
    };
}

/**
 * The same point, named.
 *
 * @param p {Point} the point to name
 * @param name {string} what to call it
 * @return {Point} a fresh point; the argument is not changed
 * @example
 *   def start as geo.Point init geo.named(geo.point(47.2692, 11.4041), "Start");
 */
export func named(p as Point, name as string) {
    def out as Point init $p;
    $out.name = $name;
    return $out;
}

/** The largest elevation magnitude {@link withElevation} accepts, in metres. */
def const ELEVATION_LIMIT as float init 1000000.0;

/**
 * The same point, at a stated elevation.
 *
 * @param p {Point} the point to raise
 * @param metres {float} elevation in metres
 * @return {Point} a fresh point with `hasElevation` set; the argument is not changed
 * @throws {Error} when the elevation is outside -1,000,000 to 1,000,000 metres
 */
export func withElevation(p as Point, metres as float) {
    # Every reader comes through here. An unbounded height let 1e308 in, and
    # statsOf then overflowed subtracting two of them; a million metres is
    # well past any orbit a track log records.
    if ($metres < -ELEVATION_LIMIT or $metres > ELEVATION_LIMIT) {
        fail("elevation " + convert.toString($metres) + " is outside -1000000..1000000 metres");
    }
    def out as Point init $p;
    $out.ele = $metres;
    $out.hasElevation = true;
    return $out;
}

/**
 * The same point, at a stated time.
 *
 * @param p {Point} the point to stamp
 * @param at {string} the instant, as RFC 3339; not parsed here
 * @return {Point} a fresh point with `hasTime` set; the argument is not changed
 */
export func withTime(p as Point, at as string) {
    def out as Point init $p;
    $out.at = $at;
    $out.hasTime = true;
    return $out;
}

/**
 * An empty document.
 *
 * @return {Document} no name, no waypoints, no routes, no tracks
 * @example
 *   def doc as geo.Document init geo.document();
 *   $doc.name = "Tyrol";
 */
export func document() {
    return Document{
        name: "",
        desc: "",
        creator: "",
        at: "",
        waypoints: [],
        routes: [],
        tracks: []
    };
}

/**
 * One track, from a list of points, as a single segment.
 *
 * @param name {string} what to call the track
 * @param points {list of Point} the positions, in order
 * @return {Track} a track holding one segment
 * @example
 *   $doc.tracks = [geo.track("Day 1", $points)];
 */
export func track(name as string, points as list of Point) {
    return Track{name: $name, desc: "", kind: "", segments: [Segment{points: $points}]};
}

/**
 * One route, from a list of points.
 *
 * @param name {string} what to call the route
 * @param points {list of Point} the points to visit, in order
 * @return {Route} the route
 */
export func route(name as string, points as list of Point) {
    return Route{name: $name, desc: "", points: $points};
}

/**
 * Every point of a track, segments run together.
 *
 * For a bounding box or a centroid. A distance measured over the result
 * counts the gaps between segments; use {@link trackDistance}.
 *
 * @param t {Track} the track to flatten
 * @return {list of Point} the points of every segment, in order
 */
export func trackPoints(t as Track) {
    def out as list of Point init [];
    for (def seg in $t.segments) {
        for (def p in $seg.points) {
            $out[] = $p;
        }
    }
    return $out;
}

/**
 * Every point a document holds, whatever it holds it as.
 *
 * Waypoints first, then route points, then track points.
 *
 * @param doc {Document} the document to flatten
 * @return {list of Point} every point in the document
 */
export func documentPoints(doc as Document) {
    def out as list of Point init [];
    for (def p in $doc.waypoints) {
        $out[] = $p;
    }
    for (def r in $doc.routes) {
        for (def p in $r.points) {
            $out[] = $p;
        }
    }
    for (def t in $doc.tracks) {
        for (def p in trackPoints($t)) {
            $out[] = $p;
        }
    }
    return $out;
}

/**
 * One line saying what a document holds.
 *
 * @param doc {Document} the document to describe
 * @return {string} the name, then the waypoint, route, track and point counts
 * @example
 *   io.printf("%s\n", geo.describe($doc));
 *   # Innsbruck loop: 1 waypoint, 1 track, 2 points
 */
export func describe(doc as Document) {
    def parts as list of string init [];
    $parts[] = countLabel(len($doc.waypoints), "waypoint", "waypoints");
    $parts[] = countLabel(len($doc.routes), "route", "routes");
    $parts[] = countLabel(len($doc.tracks), "track", "tracks");
    $parts[] = countLabel(len(documentPoints($doc)), "point", "points");
    def kept as list of string init [];
    for (def part in $parts) {
        if ($part != "") {
            $kept[] = $part;
        }
    }
    if (len($kept) == 0) {
        $kept[] = "empty";
    }
    def body as string init strings.join($kept, ", ");
    if ($doc.name == "") {
        return $body;
    }
    return $doc.name + ": " + $body;
}

/**
 * A count and its noun, or `""` when the count is zero.
 *
 * @param n {int} how many there are
 * @param one {string} the singular noun
 * @param many {string} the plural noun
 * @return {string} for example `"2 tracks"`, or `""` when `n` is zero
 */
func countLabel(n as int, one as string, many as string) {
    if ($n == 0) {
        return "";
    }
    if ($n == 1) {
        return "1 " + $one;
    }
    return convert.toString($n) + " " + $many;
}
