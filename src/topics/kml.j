# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - KML 2.2 and its zipped form, KMZ.
# Spliced into geo.j via include - not a standalone module.

/** The namespace a KML 2.2 document declares. */
export def const KML_NAMESPACE as string init "http://www.opengis.net/kml/2.2";

/** The entry a KMZ archive keeps its document in. */
export def const KMZ_ENTRY as string init "doc.kml";

/**
 * Read a KML document.
 *
 * A `Placemark` holding a `Point` becomes a waypoint; one holding a
 * `LineString` becomes a single-segment track; one holding a `Polygon`
 * becomes a track along the outer ring, holes dropped. `MultiGeometry`
 * contributes each of its geometries, and `Folder` and `Document` are walked
 * to `MAX_NESTING` levels and flattened. `styleUrl` becomes a waypoint's `sym`.
 *
 * KML tuples are `lon,lat[,ele]`, longitude first; the reader swaps them.
 *
 * @param text {string} the document
 * @return {Document} what it held
 * @throws {Error} when the root is not `<kml>`, a coordinate does not parse or is
 *   out of range, or the nesting passes `MAX_NESTING`
 * @example
 *   def doc as geo.Document init geo.readKml(fs.readString("places.kml"));
 */
export func readKml(text as string) {
    return readKmlBytes(convert.bytesFromString($text, "utf-8"));
}

/**
 * Read a KML document from its bytes.
 *
 * @param src {bytes} the document
 * @return {Document} what it held
 * @throws {Error} when the root is not `<kml>`, or a coordinate does not parse
 */
func readKmlBytes(src as bytes) {
    def root as Node init rootNode($src);
    if (localName($root.name) != "kml") {
        fail("not a KML document: the root element is <" + $root.name + ">");
    }
    def out as Document init document();
    def top as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    def container as Node init findChild($top, "Document");
    def fields as list of Node init $top;
    if (isNode($container)) {
        $fields = childNodes($src, $container.openEnd, $container.innerEnd);
        $out.name = childText($src, $fields, "name");
        $out.desc = childText($src, $fields, "description");
    }
    return collectPlacemarks($out, $src, $fields, 0);
}

/**
 * Walk a KML container, collecting its placemarks and descending into folders.
 *
 * @param into {Document} the document to fill in
 * @param src {bytes} the whole document
 * @param fields {list of Node} the container's children
 * @param depth {int} how many containers deep this call is
 * @return {Document} a fresh document; the argument is not changed
 * @throws {Error} when the nesting passes `MAX_NESTING`
 */
func collectPlacemarks(into as Document, src as bytes, fields as list of Node, depth as int) {
    checkDepth($depth, "KML containers");
    def out as Document init $into;
    def waypoints as list of Point init $out.waypoints;
    def tracks as list of Track init $out.tracks;
    for (def mark in findChildren($fields, "Placemark")) {
        def read as Document init readPlacemark($src, $mark, $depth);
        for (def p in $read.waypoints) {
            $waypoints[] = $p;
        }
        for (def t in $read.tracks) {
            $tracks[] = $t;
        }
    }
    $out.waypoints = $waypoints;
    $out.tracks = $tracks;
    for (def holder in nestedContainers($fields)) {
        def inner as list of Node init childNodes($src, $holder.openEnd, $holder.innerEnd);
        $out = collectPlacemarks($out, $src, $inner, $depth + 1);
    }
    return $out;
}

/**
 * The `<Folder>` and `<Document>` children of a container.
 *
 * @param fields {list of Node} the container's children
 * @return {list of Node} the children that hold more placemarks
 */
func nestedContainers(fields as list of Node) {
    def out as list of Node init [];
    for (def node in $fields) {
        def name as string init localName($node.name);
        if ($name == "Folder" or $name == "Document") {
            $out[] = $node;
        }
    }
    return $out;
}

/**
 * Read one `<Placemark>`.
 *
 * @param src {bytes} the whole document
 * @param mark {Node} the `<Placemark>` element
 * @param depth {int} how many containers deep this call is
 * @return {Document} a document holding only what this placemark contributed
 * @throws {Error} when a coordinate does not parse, or the nesting is too deep
 */
func readPlacemark(src as bytes, mark as Node, depth as int) {
    def fields as list of Node init childNodes($src, $mark.openEnd, $mark.innerEnd);
    def name as string init childText($src, $fields, "name");
    def desc as string init childText($src, $fields, "description");
    def style as string init childText($src, $fields, "styleUrl");
    def out as Document init document();
    def waypoints as list of Point init [];
    def tracks as list of Track init [];
    for (def geometry in geometryNodes($src, $fields, $depth)) {
        def kind as string init localName($geometry.name);
        def coords as list of Point init geometryPoints($src, $geometry, $depth);
        if (len($coords) == 0) {
            continue;
        }
        if ($kind == "Point") {
            def p as Point init $coords[0];
            $p.name = $name;
            $p.desc = $desc;
            $p.sym = $style;
            $waypoints[] = $p;
        } else {
            def t as Track init track($name, $coords);
            $t.desc = $desc;
            $tracks[] = $t;
        }
    }
    $out.waypoints = $waypoints;
    $out.tracks = $tracks;
    return $out;
}

/**
 * The geometry elements of a placemark, `MultiGeometry` unwrapped.
 *
 * @param src {bytes} the whole document
 * @param fields {list of Node} the placemark's children
 * @param depth {int} how many levels deep this call is
 * @return {list of Node} the `Point`, `LineString`, `LinearRing` and `Polygon` elements
 * @throws {Error} when the nesting passes `MAX_NESTING`
 */
func geometryNodes(src as bytes, fields as list of Node, depth as int) {
    checkDepth($depth, "KML geometries");
    def out as list of Node init [];
    for (def node in $fields) {
        if (isGeometry(localName($node.name))) {
            $out[] = $node;
        } elseif (localName($node.name) == "MultiGeometry") {
            def inner as list of Node init childNodes($src, $node.openEnd, $node.innerEnd);
            for (def nested in geometryNodes($src, $inner, $depth + 1)) {
                $out[] = $nested;
            }
        }
    }
    return $out;
}

/**
 * Whether a local name is one of the geometries this deck reads.
 *
 * @param name {string} the element's local name
 * @return {bool} whether it carries coordinates
 */
func isGeometry(name as string) {
    return $name == "Point" or $name == "LineString" or $name == "LinearRing" or
        $name == "Polygon" or $name == "Track";
}

/**
 * The points of one KML geometry.
 *
 * A `Polygon` is read as its outer ring; the inner rings that cut holes in it
 * have nowhere to go in a point-and-path model, so they are dropped.
 *
 * @param src {bytes} the whole document
 * @param geometry {Node} the geometry element
 * @param depth {int} how many levels deep this call is
 * @return {list of Point} its vertices, in order
 * @throws {Error} when a coordinate does not parse, or the nesting is too deep
 */
func geometryPoints(src as bytes, geometry as Node, depth as int) {
    checkDepth($depth, "KML geometries");
    def fields as list of Node init childNodes($src, $geometry.openEnd, $geometry.innerEnd);
    def coords as Node init findChild($fields, "coordinates");
    if (isNode($coords)) {
        return parseCoordinates(nodeText($src, $coords));
    }
    for (def nested in $fields) {
        def inner as list of Point init geometryPoints($src, $nested, $depth + 1);
        if (len($inner) > 0) {
            return $inner;
        }
    }
    return [];
}

/**
 * Parse a KML `<coordinates>` list.
 *
 * Tuples are `lon,lat` or `lon,lat,ele`, separated by any whitespace. A
 * coordinate list is the one place KML is routinely written with newlines and
 * indentation inside the values, so every run of whitespace separates tuples.
 *
 * @param text {string} the element's content
 * @return {list of Point} the points, in order
 * @throws {Error} when a tuple has fewer than two numbers, or one does not parse
 * @example
 *   parseCoordinates("11.4041,47.2692,574");
 */
func parseCoordinates(text as string) {
    def out as list of Point init [];
    for (def tuple in whitespaceFields($text)) {
        def numbers as list of string init strings.split($tuple, ",");
        if (len($numbers) < 2) {
            fail("coordinate tuple \"" + $tuple + "\" has no comma");
        }
        def lon as float init number($numbers[0], "a KML longitude");
        def lat as float init number($numbers[1], "a KML latitude");
        checkCoord($lat, $lon);
        def p as Point init point($lat, $lon);
        if (len($numbers) > 2 and strings.trim($numbers[2]) != "") {
            $p = withElevation($p, number($numbers[2], "a KML elevation"));
        }
        $out[] = $p;
    }
    return $out;
}

/**
 * Split text on runs of whitespace, dropping the empty pieces.
 *
 * @param text {string} the text to split
 * @return {list of string} the non-empty fields
 */
func whitespaceFields(text as string) {
    def out as list of string init [];
    def current as string init "";
    for (def ch in strings.chars($text)) {
        if (isSpace($ch)) {
            if ($current != "") {
                $out[] = $current;
            }
            $current = "";
        } else {
            $current = $current + $ch;
        }
    }
    if ($current != "") {
        $out[] = $current;
    }
    return $out;
}

/**
 * Write a document as KML 2.2.
 *
 * Waypoints become `Placemark` / `Point`; routes and tracks become
 * `Placemark` / `LineString`. A track with several segments is written as one
 * `MultiGeometry` of `LineString`s, so the breaks survive. A path of fewer than
 * two points is skipped. Point times and `sym` are not written.
 *
 * @param doc {Document} what to write
 * @return {string} a complete KML 2.2 document
 * @example
 *   fs.writeString("out.kml", geo.writeKml($doc));
 */
export func writeKml(doc as Document) {
    def parts as list of string init [];
    $parts[] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    $parts[] = "<kml xmlns=\"" + KML_NAMESPACE + "\">\n";
    $parts[] = indent(1) + "<Document>\n";
    $parts[] = element("name", $doc.name, 2);
    $parts[] = element("description", $doc.desc, 2);
    for (def wpt in $doc.waypoints) {
        $parts[] = writeKmlPoint($wpt);
    }
    for (def rte in $doc.routes) {
        $parts[] = writeKmlLine($rte.name, $rte.desc, [$rte.points]);
    }
    for (def trk in $doc.tracks) {
        $parts[] = writeKmlLine($trk.name, $trk.desc, segmentLists($trk));
    }
    $parts[] = indent(1) + "</Document>\n";
    $parts[] = "</kml>\n";
    return strings.join($parts, "");
}

/**
 * A track's segments as plain point lists.
 *
 * @param t {Track} the track
 * @return {list of list of Point} one list per segment
 */
func segmentLists(t as Track) {
    def out as list of list of Point init [];
    for (def seg in $t.segments) {
        $out[] = $seg.points;
    }
    return $out;
}

/**
 * Write one waypoint as a `Placemark` holding a `Point`.
 *
 * @param p {Point} the waypoint
 * @return {string} the element
 */
func writeKmlPoint(p as Point) {
    def parts as list of string init [indent(2) + "<Placemark>\n"];
    $parts[] = element("name", $p.name, 3);
    $parts[] = element("description", $p.desc, 3);
    $parts[] = indent(3) + "<Point>\n";
    $parts[] = element("coordinates", coordinateText($p), 4);
    $parts[] = indent(3) + "</Point>\n";
    $parts[] = indent(2) + "</Placemark>\n";
    return strings.join($parts, "");
}

/**
 * Write one path as a `Placemark` holding one or more `LineString`s.
 *
 * @param name {string} what to call it
 * @param desc {string} a longer description
 * @param runs {list of list of Point} one point list per unbroken run
 * @return {string} the element, or `""` when there is nothing to draw
 */
func writeKmlLine(name as string, desc as string, runs as list of list of Point) {
    def drawable as list of list of Point init [];
    for (def run in $runs) {
        if (len($run) > 1) {
            $drawable[] = $run;
        }
    }
    if (len($drawable) == 0) {
        return "";
    }
    def parts as list of string init [indent(2) + "<Placemark>\n"];
    $parts[] = element("name", $name, 3);
    $parts[] = element("description", $desc, 3);
    $parts[] = kmlGeometry($drawable);
    $parts[] = indent(2) + "</Placemark>\n";
    return strings.join($parts, "");
}

/**
 * Write the geometry of a path: one `LineString`, or a `MultiGeometry` of them.
 *
 * @param runs {list of list of Point} one point list per unbroken run
 * @return {string} the geometry element
 */
func kmlGeometry(runs as list of list of Point) {
    if (len($runs) == 1) {
        return writeLineString($runs[0], 3);
    }
    def parts as list of string init [indent(3) + "<MultiGeometry>\n"];
    for (def run in $runs) {
        $parts[] = writeLineString($run, 4);
    }
    $parts[] = indent(3) + "</MultiGeometry>\n";
    return strings.join($parts, "");
}

/**
 * Write one `LineString`.
 *
 * @param points {list of Point} the path, in order
 * @param depth {int} how far to indent it
 * @return {string} the element
 */
func writeLineString(points as list of Point, depth as int) {
    def tuples as list of string init [];
    for (def p in $points) {
        $tuples[] = coordinateText($p);
    }
    def parts as list of string init [indent($depth) + "<LineString>\n"];
    $parts[] = indent($depth + 1) + "<coordinates>\n";
    $parts[] = indent($depth + 2) + strings.join($tuples, "\n" + indent($depth + 2)) + "\n";
    $parts[] = indent($depth + 1) + "</coordinates>\n";
    $parts[] = indent($depth) + "</LineString>\n";
    return strings.join($parts, "");
}

/**
 * One point as a KML coordinate tuple.
 *
 * @param p {Point} the point
 * @return {string} `lon,lat` or `lon,lat,ele` - longitude first, as KML wants
 */
func coordinateText(p as Point) {
    def out as string init decimal($p.lon, COORD_PLACES) + "," + decimal($p.lat, COORD_PLACES);
    if ($p.hasElevation) {
        return $out + "," + decimal($p.ele, ELEVATION_PLACES);
    }
    return $out;
}

/**
 * Read a KMZ archive.
 *
 * A KMZ is a zip holding a KML document and the files it references. The
 * entry named `doc.kml` is read; without one, the first `.kml` at the root,
 * then the first `.kml` anywhere. The whole archive is decompressed into
 * memory with no size limit, so bound an untrusted input before calling this.
 *
 * @param data {bytes} the archive
 * @return {Document} what the KML inside held
 * @throws {Error} when the data is not a zip, holds no `.kml` entry, or the KML
 *   does not parse
 * @example
 *   def doc as geo.Document init geo.readKmz(fs.readBytes("places.kmz"));
 */
export func readKmz(data as bytes) {
    def entries as list of archive.Entry init [];
    try {
        $entries = archive.unpack($data, "zip");
    } catch (e) {
        fail("not a KMZ archive: " + $e.message);
    }
    def chosen as int init kmzEntryIndex($entries);
    if ($chosen < 0) {
        fail("the KMZ archive holds no .kml entry");
    }
    return readKmlBytes(toUtf8($entries[$chosen].data));
}

/**
 * Which entry of a KMZ holds the document.
 *
 * Google Earth reads `doc.kml` at the root, and a KMZ can carry other KML
 * besides - a legend, a network-linked overlay - often listed first. So
 * `doc.kml` wins, then the first `.kml` at the root, then the first anywhere.
 *
 * @param entries {list of archive.Entry} the unpacked archive
 * @return {int} the index of the entry to read, or `-1` when none is KML
 */
func kmzEntryIndex(entries as list of archive.Entry) {
    def atRoot as int init -1;
    def anywhere as int init -1;
    for (def i as int init 0; $i < len($entries); $i = $i + 1) {
        def name as string init strings.lower($entries[$i].name);
        if ($name == KMZ_ENTRY) {
            return $i;
        }
        if (strings.endsWith($name, ".kml")) {
            if ($anywhere < 0) {
                $anywhere = $i;
            }
            if ($atRoot < 0 and not strings.contains($name, "/")) {
                $atRoot = $i;
            }
        }
    }
    if ($atRoot >= 0) {
        return $atRoot;
    }
    return $anywhere;
}

/**
 * Write a document as a KMZ archive.
 *
 * One `doc.kml` entry, which is the name a reader looks for first.
 *
 * @param doc {Document} what to write
 * @return {bytes} the archive
 * @example
 *   fs.writeBytes("out.kmz", geo.writeKmz($doc));
 */
export func writeKmz(doc as Document) {
    def entry as archive.Entry init archive.Entry{
        name: KMZ_ENTRY,
        data: convert.bytesFromString(writeKml($doc), "utf-8"),
        mode: 0o644,
        mtime: 0
    };
    return archive.pack([$entry], "zip");
}
