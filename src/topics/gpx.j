# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# geo - GPX 1.0 and 1.1, the GPS exchange format.
# Spliced into geo.j via include - not a standalone module.

/** The namespace a GPX 1.1 document declares. */
export def const GPX_NAMESPACE as string init "http://www.topografix.com/GPX/1/1";

/** What this deck writes in a GPX `creator` attribute. */
export def const GPX_CREATOR as string init "@deckyard/geo";

/**
 * Read a GPX document.
 *
 * GPX 1.0 and 1.1: the document's name, description and time are read from
 * the root (1.0) or from `<metadata>` (1.1). `<extensions>` are skipped. A
 * point whose closing tag is missing, as at the end of a truncated file, is
 * dropped.
 *
 * The document is scanned for element boundaries and only the leaves are
 * decoded, so memory follows the points read rather than the file size.
 *
 * @param text {string} the document
 * @return {Document} what it held
 * @throws {Error} when the root is not `<gpx>`, or a point's `lat` or `lon` is
 *   missing, does not parse or is out of range
 * @example
 *   def doc as geo.Document init geo.readGpx(fs.readString("hike.gpx"));
 */
export func readGpx(text as string) {
    return readGpxBytes(convert.bytesFromString($text, "utf-8"));
}

/**
 * Read a GPX document from its bytes.
 *
 * What {@link openGpx} calls: a file is read as bytes and scanned directly,
 * with no decode of the whole document to a string first.
 *
 * @param src {bytes} the document
 * @return {Document} what it held
 * @throws {Error} when the root is not `<gpx>`, or a coordinate does not parse
 */
func readGpxBytes(src as bytes) {
    def root as Node init rootNode($src);
    if (localName($root.name) != "gpx") {
        fail("not a GPX document: the root element is <" + $root.name + ">");
    }
    def top as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    # Read once: every point decodes against the root's xmlns bindings.
    def ns as map of string to string init namespaceBindings($src, $root);
    def out as Document init document();
    $out.creator = nodeAttr($src, $root, "creator");
    $out = readGpxHeader($out, $src, $root, $top);
    # Appended into locals and assigned once: `$out.waypoints[]` does not
    # parse, and growing a field through a copy per point would be quadratic.
    def waypoints as list of Point init [];
    for (def node in findChildren($top, "wpt")) {
        if ($node.closed) {
            $waypoints[] = readGpxPoint($src, $node, $ns);
        }
    }
    def routes as list of Route init [];
    for (def node in findChildren($top, "rte")) {
        $routes[] = readGpxRoute($src, $node, $ns);
    }
    def tracks as list of Track init [];
    for (def node in findChildren($top, "trk")) {
        $tracks[] = readGpxTrack($src, $node, $ns);
    }
    $out.waypoints = $waypoints;
    $out.routes = $routes;
    $out.tracks = $tracks;
    return $out;
}

/**
 * Read a GPX document's name, description and time.
 *
 * @param into {Document} the document to fill in
 * @param src {bytes} the whole document
 * @param root {Node} the `<gpx>` element
 * @param top {list of Node} the root's children
 * @return {Document} a fresh document; the argument is not changed
 */
func readGpxHeader(into as Document, src as bytes, root as Node, top as list of Node) {
    def out as Document init $into;
    # GPX 1.0 puts these on the root; 1.1 moves them into <metadata>.
    def meta as Node init findChild($top, "metadata");
    def fields as list of Node init $top;
    if (isNode($meta)) {
        $fields = childNodes($src, $meta.openEnd, $meta.innerEnd);
    }
    $out.name = childText($src, $fields, "name");
    $out.desc = childText($src, $fields, "desc");
    $out.at = childText($src, $fields, "time");
    return $out;
}

/**
 * Read one `<wpt>`, `<rtept>` or `<trkpt>`.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the element
 * @param ns {map of string to string} the root's namespace bindings (`namespaceBindings`)
 * @return {Point} the position and whatever else the element carried
 * @throws {Error} when `lat` or `lon` is missing or does not parse
 */
func readGpxPoint(src as bytes, node as Node, ns as map of string to string) {
    # The leaf, decoded: a track point is small, and one native parse of it
    # beats an interpreted walk of its children by more than an order of
    # magnitude. The scanner found the boundary; `xml` reads what is inside.
    def element as xml.Value init decodeLeaf($src, $node, $ns);
    def latText as string init leafAttr($element, "lat");
    def lonText as string init leafAttr($element, "lon");
    if ($latText == "" or $lonText == "") {
        fail("<" + $node.name + "> has no lat and lon attribute pair");
    }
    def lat as float init number($latText, "<" + $node.name + "> lat");
    def lon as float init number($lonText, "<" + $node.name + "> lon");
    checkCoord($lat, $lon);
    def out as Point init point($lat, $lon);
    $out.name = leafText($element, "name");
    $out.desc = leafText($element, "desc");
    $out.sym = leafText($element, "sym");
    if (hasLeafChild($element, "ele")) {
        $out = withElevation($out, number(leafText($element, "ele"), "<ele>"));
    }
    if (hasLeafChild($element, "time")) {
        $out = withTime($out, leafText($element, "time"));
    }
    return $out;
}

/**
 * Read one `<rte>`.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the `<rte>` element
 * @param ns {map of string to string} the root's namespace bindings (`namespaceBindings`)
 * @return {Route} the route
 */
func readGpxRoute(src as bytes, node as Node, ns as map of string to string) {
    def fields as list of Node init childNodes($src, $node.openEnd, $node.innerEnd);
    def points as list of Point init [];
    for (def rtept in findChildren($fields, "rtept")) {
        if ($rtept.closed) {
            $points[] = readGpxPoint($src, $rtept, $ns);
        }
    }
    return Route{
        name: childText($src, $fields, "name"),
        desc: childText($src, $fields, "desc"),
        points: $points
    };
}

/**
 * Read one `<trk>`.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the `<trk>` element
 * @param ns {map of string to string} the root's namespace bindings (`namespaceBindings`)
 * @return {Track} the track, one `Segment` per `<trkseg>`
 */
func readGpxTrack(src as bytes, node as Node, ns as map of string to string) {
    def fields as list of Node init childNodes($src, $node.openEnd, $node.innerEnd);
    def segments as list of Segment init [];
    for (def seg in findChildren($fields, "trkseg")) {
        $segments[] = Segment{points: readGpxSegment($src, $seg, $ns)};
    }
    return Track{
        name: childText($src, $fields, "name"),
        desc: childText($src, $fields, "desc"),
        kind: childText($src, $fields, "type"),
        segments: $segments
    };
}

/**
 * Read the track points of one `<trkseg>`.
 *
 * Streamed with {@link nextChild} rather than listed with `childNodes`: a
 * segment holds as many children as the track has points, so materialising
 * them would make the node list the largest thing in the program. Only one
 * point exists at a time, and the points list is the only thing that grows.
 *
 * @param src {bytes} the whole document
 * @param seg {Node} the `<trkseg>` element
 * @param ns {map of string to string} the root's namespace bindings (`namespaceBindings`)
 * @return {list of Point} the segment's points, in order
 * @throws {Error} when a coordinate is missing, unparseable or out of range
 */
func readGpxSegment(src as bytes, seg as Node, ns as map of string to string) {
    def points as list of Point init [];
    def child as Node init nextChild($src, $seg.openEnd, $seg.innerEnd);
    while (isNode($child)) {
        # A point whose closing tag the file never got to is the damage at the
        # end of an interrupted recording: it is dropped, and every point
        # written before it is kept. A point that *is* closed but carries a bad
        # coordinate is an error, not damage to work around.
        if (localName($child.name) == "trkpt" and $child.closed) {
            $points[] = readGpxPoint($src, $child, $ns);
        }
        $child = nextChild($src, $child.end, $seg.innerEnd);
    }
    return $points;
}

/**
 * Write a document as GPX 1.1.
 *
 * Rendered as text and joined once, with no tree. The `creator` attribute is
 * the document's creator, or {@link GPX_CREATOR} when that is empty. An empty
 * field writes no element.
 *
 * @param doc {Document} what to write
 * @return {string} a complete GPX 1.1 document
 * @example
 *   fs.writeString("out.gpx", geo.writeGpx($doc));
 */
export func writeGpx(doc as Document) {
    def parts as list of string init [];
    $parts[] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    $parts[] = "<gpx version=\"1.1\" creator=\"" + gpxCreator($doc) + "\"\n";
    $parts[] = "     xmlns=\"" + GPX_NAMESPACE + "\">\n";
    $parts[] = writeGpxMetadata($doc);
    for (def wpt in $doc.waypoints) {
        $parts[] = writeGpxPoint("wpt", $wpt, 1);
    }
    for (def rte in $doc.routes) {
        $parts[] = writeGpxRoute($rte);
    }
    for (def trk in $doc.tracks) {
        $parts[] = writeGpxTrack($trk);
    }
    $parts[] = "</gpx>\n";
    return strings.join($parts, "");
}

/**
 * What to put in the `creator` attribute.
 *
 * A document that came from another tool keeps saying so, because a consumer
 * uses `creator` to decide which quirks to expect.
 *
 * @param doc {Document} the document being written
 * @return {string} the document's creator, or this deck's name
 */
func gpxCreator(doc as Document) {
    if (strings.trim($doc.creator) == "") {
        return GPX_CREATOR;
    }
    return xmlEscape($doc.creator);
}

/**
 * Write a document's `<metadata>` block, or nothing when it has none.
 *
 * @param doc {Document} the document being written
 * @return {string} the block, indented, or `""`
 */
func writeGpxMetadata(doc as Document) {
    def inner as string init element("name", $doc.name, 2) + element("desc", $doc.desc, 2) +
        element("time", $doc.at, 2);
    if ($inner == "") {
        return "";
    }
    return indent(1) + "<metadata>\n" + $inner + indent(1) + "</metadata>\n";
}

/**
 * Write one `<wpt>`, `<rtept>` or `<trkpt>`.
 *
 * @param tag {string} which of the three to write
 * @param p {Point} the point to write
 * @param depth {int} how far to indent it
 * @return {string} the element
 */
func writeGpxPoint(tag as string, p as Point, depth as int) {
    def head as string init indent($depth) + "<" + $tag + " lat=\"" +
        decimal($p.lat, COORD_PLACES) + "\"" + " lon=\"" + decimal($p.lon, COORD_PLACES) + "\"";
    def inner as string init "";
    if ($p.hasElevation) {
        $inner = $inner + element("ele", decimal($p.ele, ELEVATION_PLACES), $depth + 1);
    }
    if ($p.hasTime) {
        $inner = $inner + element("time", $p.at, $depth + 1);
    }
    $inner = $inner + element("name", $p.name, $depth + 1) + element("desc", $p.desc, $depth + 1) +
        element("sym", $p.sym, $depth + 1);
    if ($inner == "") {
        return $head + " />\n";
    }
    return $head + ">\n" + $inner + indent($depth) + "</" + $tag + ">\n";
}

/**
 * Write one `<rte>`.
 *
 * @param r {Route} the route to write
 * @return {string} the element
 */
func writeGpxRoute(r as Route) {
    def parts as list of string init [indent(1) + "<rte>\n"];
    $parts[] = element("name", $r.name, 2);
    $parts[] = element("desc", $r.desc, 2);
    for (def p in $r.points) {
        $parts[] = writeGpxPoint("rtept", $p, 2);
    }
    $parts[] = indent(1) + "</rte>\n";
    return strings.join($parts, "");
}

/**
 * Write one `<trk>`.
 *
 * @param t {Track} the track to write
 * @return {string} the element
 */
func writeGpxTrack(t as Track) {
    def parts as list of string init [indent(1) + "<trk>\n"];
    $parts[] = element("name", $t.name, 2);
    $parts[] = element("desc", $t.desc, 2);
    $parts[] = element("type", $t.kind, 2);
    for (def seg in $t.segments) {
        $parts[] = indent(2) + "<trkseg>\n";
        for (def p in $seg.points) {
            $parts[] = writeGpxPoint("trkpt", $p, 3);
        }
        $parts[] = indent(2) + "</trkseg>\n";
    }
    $parts[] = indent(1) + "</trk>\n";
    return strings.join($parts, "");
}

/**
 * Write a leaf element, or nothing when its text is empty.
 *
 * Every optional field in every XML writer here goes through this, so an absent
 * field is an absent element rather than an empty one. Strict GPX validators
 * want that, and it is what keeps a round trip stable.
 *
 * @param tag {string} the element name
 * @param text {string} the content, escaped here
 * @param depth {int} how far to indent it
 * @return {string} the element, or `""` when `text` is empty
 */
func element(tag as string, text as string, depth as int) {
    if (strings.trim($text) == "") {
        return "";
    }
    return indent($depth) + "<" + $tag + ">" + xmlEscape($text) + "</" + $tag + ">\n";
}

/**
 * Indentation for one nesting depth.
 *
 * @param depth {int} how deep the element sits
 * @return {string} two spaces per level
 */
func indent(depth as int) {
    return strings.repeat("  ", $depth);
}
