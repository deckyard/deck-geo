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
 * A well-formed document is decoded whole with `xml.decode` and read from the
 * tree. A document `xml.decode` rejects (malformed, an unknown entity, past
 * its node or nesting cap) is read by the element scanner instead, which
 * tolerates damage. Both give the same `Document` for the same input.
 *
 * @param text {string} the document
 * @return {Document} what it held
 * @throws {Error} when the root is not `<gpx>`, or a point's `lat` or `lon` is
 *   missing, does not parse or is out of range
 * @example
 *   def doc as geo.Document init geo.readGpx(fs.readString("hike.gpx"));
 */
export func readGpx(text as string) {
    return readGpxSource(convert.bytesFromString($text, "utf-8"), $text);
}

/**
 * Read a GPX document from its bytes.
 *
 * What {@link openGpx} calls. Bytes that are not valid UTF-8 go to the
 * scanner, which reports where.
 *
 * @param src {bytes} the document
 * @return {Document} what it held
 * @throws {Error} when the root is not `<gpx>`, or a coordinate does not parse
 */
func readGpxBytes(src as bytes) {
    def text as string init "";
    def utf8 as bool init true;
    try {
        $text = convert.stringFromBytes($src, "utf-8");
    } catch (e) {
        $utf8 = false;
    }
    if (not $utf8) {
        return readGpxScan($src);
    }
    return readGpxSource($src, $text);
}

/**
 * Read a GPX document from the tree when it decodes and reads the same as by
 * the scanner, otherwise with the scanner.
 *
 * Only a failed `xml.decode` or a failed {@link treeMatchesScan} check falls
 * back. Errors the tree walk raises (a bad coordinate) propagate: every check
 * runs before the first point is read, so the walk raises what the scanner
 * would.
 *
 * @param src {bytes} the document
 * @param text {string} the same document as text
 * @return {Document} what it held
 * @throws {Error} when the root is not `<gpx>`, or a coordinate does not parse
 */
func readGpxSource(src as bytes, text as string) {
    def tree as GpxTree init gpxTree($src, $text);
    if ($tree.usable) {
        return readGpxTree($src, $tree.root);
    }
    return readGpxScan($src);
}

/**
 * A decoded GPX document, and whether the tree reader may read it.
 *
 * @field usable {bool} whether `xml.decode` accepted the document and
 *   {@link treeMatchesScan} passed
 * @field root {xml.Value} the root element; a placeholder when not usable
 */
def struct GpxTree {
    usable as bool,
    root as xml.Value
};

/**
 * Decode a GPX document for the tree reader.
 *
 * @param src {bytes} the document
 * @param text {string} the same document as text
 * @return {GpxTree} the tree, `usable` only when it reads as the scanner reads
 */
func gpxTree(src as bytes, text as string) {
    def out as GpxTree init GpxTree{usable: false, root: xml.element("gpx")};
    def body as string init $text;
    # The scanner steps over a byte-order mark; xml.decode rejects one.
    if (strings.startsWith($body, "\uFEFF")) {
        $body = strings.substring($body, 1, len($body));
    }
    if (not decodeFits($body, meta.BUILD)) {
        return $out;
    }
    def root as xml.Value init $out.root;
    try {
        $root = xml.decode($body);
    } catch (e) {
        return $out;
    }
    $out.root = $root;
    $out.usable = treeMatchesScan($src, $text, $root);
    return $out;
}

/**
 * jennifer-tiny's `xml.decode` node cap (`MaxDecodedNodes`, 2^18, in the
 * interpreter's `internal/limits/nesting_tiny.go`).
 */
def const TINY_DECODE_NODES as int init 262144;

/**
 * Whether `xml.decode` can take a document on this build.
 *
 * On `jennifer-tiny` a document past {@link TINY_DECODE_NODES} fails only after
 * the whole parse (2.6 s for 10 MB), so it goes to the scanner first. The
 * Go build's cap (2^21) is left to the decode. A wrong estimate changes only
 * the path, not the result.
 *
 * @param text {string} the document
 * @param build {string} `meta.BUILD`
 * @return {bool} false when `build` is `"tinygo"` and the estimate exceeds the cap
 */
func decodeFits(text as string, build as string) {
    if ($build != "tinygo") {
        return true;
    }
    return decodeNodes($text) <= TINY_DECODE_NODES;
}

/**
 * Estimate the nodes `xml.decode` builds: elements, attributes and text runs,
 * counted natively.
 *
 * Elements are `<` less `</`, `<?` and `<!`; attributes are `="` and `='`; text
 * runs are `>` not followed by `<`. Markup inside comments, CDATA or attribute
 * values counts too. 600,015 for a 10 MB, 50,000-point track that decodes to
 * 600,012 nodes.
 *
 * @param text {string} the document
 * @return {int} the estimated node count
 */
func decodeNodes(text as string) {
    def elements as int init strings.count($text, "<") -
        strings.count($text, "</") - strings.count($text, "<?") - strings.count($text, "<!");
    def attributes as int init strings.count($text, "=\"") + strings.count($text, "='");
    def texts as int init strings.count($text, ">") - strings.count($text, "><");
    return $elements + $attributes + $texts;
}

/**
 * Read a GPX document with the element scanner.
 *
 * The document is scanned for element boundaries and only the leaves are
 * decoded, so memory follows the points read rather than the file size.
 * Reads damaged documents {@link readGpxTree} cannot.
 *
 * @param src {bytes} the document
 * @return {Document} what it held
 * @throws {Error} when the root is not `<gpx>`, or a coordinate does not parse
 */
func readGpxScan(src as bytes) {
    def root as Node init rootNode($src);
    if (localName($root.name) != "gpx") {
        fail("not a GPX document: the root element is <" + $root.name + ">");
    }
    def top as list of Node init gpxChildren($src, $root.openEnd, $root.innerEnd, "wpt");
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
    def fields as list of Node init leadingFields($top);
    if (isNode($meta)) {
        $fields = childNodes($src, $meta.openEnd, $meta.innerEnd);
    }
    $out.name = childText($src, $fields, "name");
    $out.desc = childText($src, $fields, "desc");
    $out.at = childText($src, $fields, "time");
    return $out;
}

/**
 * Read one `<wpt>`, `<rtept>` or `<trkpt>` the scanner found.
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
    return gpxPoint(decodeLeaf($src, $node, $ns));
}

/**
 * Read one decoded `<wpt>`, `<rtept>` or `<trkpt>`.
 *
 * @param element {xml.Value} the point element
 * @return {Point} the position and whatever else the element carried
 * @throws {Error} when `lat` or `lon` is missing, does not parse or is out of
 *   range, or `<ele>` does not parse or is out of range
 */
func gpxPoint(element as xml.Value) {
    def points as list of Point init pointsFrom(
        [$element],
        xml.findAll($element, "*:ele[1]"),
        xml.findAll($element, "*:time[1]"),
        xml.findAll($element, "*:name[1]"),
        xml.findAll($element, "*:desc[1]"),
        xml.findAll($element, "*:sym[1]"));
    return $points[0];
}

/**
 * Read point elements whose fields are already looked up.
 *
 * Both readers end here, so a point's fields and errors do not depend on
 * which reader ran. Each field list holds the first such child of every
 * point, in point order, or is empty when no point has one. The first of a
 * repeated field wins; text is trimmed; an empty `<time>` states no time.
 * Numbers that match `NUMBER_PATTERN` as written are converted directly;
 * anything else goes through {@link number}, which trims and raises.
 *
 * @param elements {list of xml.Value} the point elements
 * @param eles {list of xml.Value} their `<ele>`, or none
 * @param times {list of xml.Value} their `<time>`, or none
 * @param names {list of xml.Value} their `<name>`, or none
 * @param descs {list of xml.Value} their `<desc>`, or none
 * @param syms {list of xml.Value} their `<sym>`, or none
 * @return {list of Point} one point per element, in order
 * @throws {Error} when `lat` or `lon` is missing, does not parse or is out of
 *   range, or `<ele>` does not parse or is out of range
 */
func pointsFrom(
    elements as list of xml.Value,
    eles as list of xml.Value,
    times as list of xml.Value,
    names as list of xml.Value,
    descs as list of xml.Value,
    syms as list of xml.Value) {
    def hasEle as bool init len($eles) > 0;
    def hasTime as bool init len($times) > 0;
    def hasName as bool init len($names) > 0;
    def hasDesc as bool init len($descs) > 0;
    def hasSym as bool init len($syms) > 0;
    def points as list of Point init [];
    # One loop body, no helper call per point: a call costs as much as several
    # native lookups. Each point starts as a copy of `blank` (cheaper than a
    # struct literal) and is filled in place, where withElevation and
    # withTime each copied it.
    def blank as Point init point(0.0, 0.0);
    for (def i as int init 0; $i < len($elements); $i = $i + 1) {
        def element as xml.Value init $elements[$i];
        def out as Point init $blank;
        # Unprefixed plain numbers in one try; anything else (absent,
        # prefixed, malformed, out of float range) is read again by
        # checkedPosition, which raises the deck's errors.
        def parsed as bool init false;
        try {
            def latText as string init xml.attr($element, "lat");
            def lonText as string init xml.attr($element, "lon");
            if (regex.matches(NUMBER_PAIR_PATTERN, $latText + " " + $lonText)) {
                $out.lat = convert.toFloat($latText);
                $out.lon = convert.toFloat($lonText);
                $parsed = true;
            }
        } catch (e) { # lint-disable: L103
            # Read again below.
        }
        if (not $parsed) {
            $out = checkedPosition($out, $element);
        }
        if ($out.lat < -90.0 or $out.lat > 90.0 or $out.lon < -180.0 or $out.lon > 180.0) {
            checkCoord($out.lat, $out.lon);
        }
        # The same fast path for <ele>; `parsed` starts true without one.
        def eleText as string init "";
        $parsed = not $hasEle;
        if ($hasEle) {
            $eleText = strings.trim(xml.text($eles[$i]));
            $out.hasElevation = true;
        }
        try {
            if (not $parsed and regex.matches(NUMBER_PATTERN, $eleText)) {
                $out.ele = convert.toFloat($eleText);
                $parsed = true;
            }
        } catch (e) { # lint-disable: L103
            # Out of float range: number() below raises the deck's error.
        }
        if (not $parsed) {
            $out.ele = number($eleText, "<ele>");
        }
        if ($out.ele < -ELEVATION_LIMIT or $out.ele > ELEVATION_LIMIT) {
            checkElevation($out.ele);
        }
        if ($hasTime) {
            $out.at = strings.trim(xml.text($times[$i]));
            $out.hasTime = $out.at != "";
        }
        if ($hasName) {
            $out.name = strings.trim(xml.text($names[$i]));
        }
        if ($hasDesc) {
            $out.desc = strings.trim(xml.text($descs[$i]));
        }
        if ($hasSym) {
            $out.sym = strings.trim(xml.text($syms[$i]));
        }
        $points[] = $out;
    }
    return $points;
}

/**
 * A point's position, read with every check.
 *
 * The path {@link pointsFrom} takes for anything but two unprefixed plain
 * numbers: attributes matched on their local part, numbers trimmed.
 *
 * @param into {Point} the point to fill in
 * @param element {xml.Value} the point element
 * @return {Point} a fresh point with `lat` and `lon` set; the argument is not changed
 * @throws {Error} when `lat` or `lon` is missing or does not parse
 */
func checkedPosition(into as Point, element as xml.Value) {
    def out as Point init $into;
    def latText as string init leafAttr($element, "lat");
    def lonText as string init leafAttr($element, "lon");
    if ($latText == "" or $lonText == "") {
        fail("<" + xml.tag($element) + "> has no lat and lon attribute pair");
    }
    $out.lat = number($latText, "<" + xml.tag($element) + "> lat");
    $out.lon = number($lonText, "<" + xml.tag($element) + "> lon");
    return $out;
}

/** Two `NUMBER_PATTERN` numbers joined by one space: both coordinates in one match. */
def const NUMBER_PAIR_PATTERN as string init strings.replace(NUMBER_PATTERN, "$", "") + " " +
    strings.replace(NUMBER_PATTERN, "^", "");

/**
 * Read one `<rte>`.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the `<rte>` element
 * @param ns {map of string to string} the root's namespace bindings (`namespaceBindings`)
 * @return {Route} the route
 */
func readGpxRoute(src as bytes, node as Node, ns as map of string to string) {
    def children as list of Node init gpxChildren($src, $node.openEnd, $node.innerEnd, "rtept");
    def points as list of Point init [];
    for (def rtept in findChildren($children, "rtept")) {
        if ($rtept.closed) {
            $points[] = readGpxPoint($src, $rtept, $ns);
        }
    }
    def fields as list of Node init leadingFields($children);
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
    def child as Node init nextChildOf($src, $seg.openEnd, $seg.innerEnd, "trkpt");
    while (isNode($child)) {
        # A point whose closing tag the file never got to is the damage at the
        # end of an interrupted recording: it is dropped, and every point
        # written before it is kept. A point that *is* closed but carries a bad
        # coordinate is an error, not damage to work around.
        if (localName($child.name) == "trkpt" and $child.closed) {
            $points[] = readGpxPoint($src, $child, $ns);
        }
        $child = nextChildOf($src, gpxResume($child), $seg.innerEnd, "trkpt");
    }
    return $points;
}

/**
 * The direct children of a GPX element, reading past a point left unclosed.
 *
 * {@link childNodes} takes an unclosed element to run to the end of its
 * parent: right for a truncated container, but one damaged `<wpt>`,
 * `<rtept>` or `<trkpt>` would hide every sibling after it. A point holds no
 * point or container, so the walk resumes past its open tag
 * ({@link gpxResume}). The point's own fields then appear as siblings;
 * readers take an element's fields from {@link leadingFields} only.
 *
 * @param src {bytes} the whole document
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @param leaf {string} the point element among the children, read as a leaf
 *   ({@link nextChildOf})
 * @return {list of Node} the children, in document order
 */
func gpxChildren(src as bytes, from as int, limit as int, leaf as string) {
    def out as list of Node init [];
    def child as Node init nextChildOf($src, $from, $limit, $leaf);
    while (isNode($child)) {
        $out[] = $child;
        $child = nextChildOf($src, gpxResume($child), $limit, $leaf);
    }
    return $out;
}

/**
 * Where the walk after a GPX child resumes.
 *
 * @param child {Node} the child just read
 * @return {int} its end, or the end of its open tag when it is an unclosed point
 */
func gpxResume(child as Node) {
    if (not $child.closed and isGpxPoint(localName($child.name))) {
        return $child.openEnd;
    }
    return $child.end;
}

/**
 * Whether a local name is one of GPX's three point elements.
 *
 * @param name {string} the local name
 * @return {bool} whether it is `wpt`, `rtept` or `trkpt`
 */
func isGpxPoint(name as string) {
    return $name == "wpt" or $name == "rtept" or $name == "trkpt";
}

/**
 * The children before the first unclosed point.
 *
 * {@link gpxChildren} lists an unclosed point's own fields as siblings after
 * it, so a `<name>` there may be the point's rather than the document's or
 * route's. A list with no unclosed point comes back whole.
 *
 * @param nodes {list of Node} the children, in document order
 * @return {list of Node} the leading run of them
 */
func leadingFields(nodes as list of Node) {
    def out as list of Node init [];
    for (def node in $nodes) {
        if (not $node.closed and isGpxPoint(localName($node.name))) {
            return $out;
        }
        $out[] = $node;
    }
    return $out;
}

/**
 * Read a decoded GPX document.
 *
 * Mirrors {@link readGpxScan} element for element: header fields from the
 * first `<metadata>` or else the root, the first child of each field name,
 * text trimmed; then every waypoint, route and track, in that order, so the
 * first bad point raised is the scanner's. `creator` is read from the bytes
 * with {@link nodeAttr}, as the scanner reads it: `xml.decode` normalises
 * tabs and newlines in it to spaces and matches `creator` before `x:creator`.
 *
 * @param src {bytes} the document
 * @param root {xml.Value} its decoded root, checked by {@link treeMatchesScan}
 * @return {Document} what it held
 * @throws {Error} when a point's `lat` or `lon` is missing, does not parse or
 *   is out of range
 */
func readGpxTree(src as bytes, root as xml.Value) {
    def out as Document init document();
    $out.creator = nodeAttr($src, rootOpenTag($src), "creator");
    def head as xml.Value init gpxHead($root);
    $out.name = fieldText($head, "name");
    $out.desc = fieldText($head, "desc");
    $out.at = fieldText($head, "time");
    def waypoints as list of Point init treePoints($root, "*:wpt");
    def routes as list of Route init [];
    for (def rte in xml.findAll($root, "*:rte")) {
        $routes[] = Route{
            name: fieldText($rte, "name"),
            desc: fieldText($rte, "desc"),
            points: treePoints($rte, "*:rtept")
        };
    }
    def tracks as list of Track init [];
    for (def trk in xml.findAll($root, "*:trk")) {
        $tracks[] = Track{
            name: fieldText($trk, "name"),
            desc: fieldText($trk, "desc"),
            kind: fieldText($trk, "type"),
            segments: treeSegments($trk)
        };
    }
    $out.waypoints = $waypoints;
    $out.routes = $routes;
    $out.tracks = $tracks;
    return $out;
}

/**
 * One `<trk>`'s segments, read from the tree.
 *
 * @param trk {xml.Value} the `<trk>` element
 * @return {list of Segment} one per `<trkseg>`
 * @throws {Error} when a point's coordinate is missing, unparseable or out of range
 */
func treeSegments(trk as xml.Value) {
    def segments as list of Segment init [];
    for (def seg in xml.findAll($trk, "*:trkseg")) {
        $segments[] = Segment{points: treePoints($seg, "*:trkpt")};
    }
    return $segments;
}

/**
 * The points among an element's children, read from the tree.
 *
 * Fields are fetched per parent, not per point: one native path query per
 * field lists the first `<ele>` (say) of every point that has one. When each
 * field is held by every point or by none, the lists line up with the points
 * and each point is read by index; otherwise every point is read with
 * {@link gpxPoint}.
 *
 * @param parent {xml.Value} the root, a `<rte>` or a `<trkseg>`
 * @param step {string} the points' path step, `*:wpt`, `*:rtept` or `*:trkpt`
 * @return {list of Point} the points, in order
 * @throws {Error} when a point's coordinate is missing, unparseable or out of
 *   range, or its `<ele>` does not parse or is out of range
 */
func treePoints(parent as xml.Value, step as string) {
    def elements as list of xml.Value init xml.findAll($parent, $step);
    def n as int init len($elements);
    def eles as list of xml.Value init xml.findAll($parent, $step + "/*:ele[1]");
    def times as list of xml.Value init xml.findAll($parent, $step + "/*:time[1]");
    def names as list of xml.Value init xml.findAll($parent, $step + "/*:name[1]");
    def descs as list of xml.Value init xml.findAll($parent, $step + "/*:desc[1]");
    def syms as list of xml.Value init xml.findAll($parent, $step + "/*:sym[1]");
    if (allOrNone($eles, $n) and allOrNone($times, $n) and allOrNone($names, $n) and
        allOrNone($descs, $n) and allOrNone($syms, $n)) {
        return pointsFrom($elements, $eles, $times, $names, $descs, $syms);
    }
    def points as list of Point init [];
    for (def element in $elements) {
        $points[] = gpxPoint($element);
    }
    return $points;
}

/**
 * Whether a field list from {@link treePoints} lines up with the points.
 *
 * @param fields {list of xml.Value} the first field of each point that has one
 * @param points {int} how many points there are
 * @return {bool} whether every point or no point has the field
 */
func allOrNone(fields as list of xml.Value, points as int) {
    return len($fields) == 0 or len($fields) == $points;
}

/**
 * The root element's open tag, found as {@link rootNode} finds it but
 * without searching for its close tag.
 *
 * @param src {bytes} a document `xml.decode` accepted
 * @return {Node} the root, with `start` and `openEnd` set (`end` and
 *   `innerEnd` are `openEnd`), or a missing node when there is no element
 */
func rootOpenTag(src as bytes) {
    def limit as int init len($src);
    def lt as int init indexOfByte($src, LT_PROBE, 0, $limit);
    while ($lt >= 0) {
        def skip as int init skipNonElement($src, $lt, $limit);
        if ($skip < 0) {
            break;
        }
        $lt = indexOfByte($src, LT_PROBE, $skip, $limit);
    }
    if ($lt < 0) {
        return missingNode();
    }
    def nameEnd as int init $lt + 1;
    while ($nameEnd < $limit and not isNameEnd($src[$nameEnd])) {
        $nameEnd = $nameEnd + 1;
    }
    def openEnd as int init endOfOpenTag($src, $nameEnd, $limit);
    return Node{
        name: byteText($src, $lt + 1, $nameEnd),
        start: $lt,
        end: $openEnd,
        openEnd: $openEnd,
        innerEnd: $openEnd,
        closed: false
    };
}

/**
 * The element a GPX document's name, description and time are read from.
 *
 * @param root {xml.Value} the `<gpx>` element
 * @return {xml.Value} the first `<metadata>` (1.1), or the root (1.0)
 */
func gpxHead(root as xml.Value) {
    def metas as list of xml.Value init xml.findAll($root, "*:metadata");
    if (len($metas) > 0) {
        return $metas[0];
    }
    return $root;
}

/**
 * The trimmed text of an element's first child with a local name.
 *
 * @param parent {xml.Value} the element
 * @param name {string} the child's local name
 * @return {string} its text, or `""` when there is no such child
 */
func fieldText(parent as xml.Value, name as string) {
    def found as list of xml.Value init xml.findAll($parent, "*:" + $name);
    if (len($found) == 0) {
        return "";
    }
    return strings.trim(xml.text($found[0]));
}

/**
 * Whether {@link readGpxTree} reads a decoded document exactly as
 * {@link readGpxScan} reads its bytes.
 *
 * The scanner departs from the XML tree on some well-formed input. Each
 * check below rules out one such case; a document that fails one is read by
 * the scanner. All of them run on the text or natively on the tree, before
 * any point is read.
 *
 * @param src {bytes} the document
 * @param text {string} the same document as text
 * @param root {xml.Value} its decoded root
 * @return {bool} whether the tree reader may read it
 */
func treeMatchesScan(src as bytes, text as string, root as xml.Value) {
    # A root other than <gpx> raises; the scanner path raises it.
    if (xml.localName($root) != "gpx") {
        return false;
    }
    if (not textMatchesScan($src, $text)) {
        return false;
    }
    # nestedClose takes 102 nested elements of one name as unclosed.
    if (xml.has($root, DEEP_PATH)) {
        return false;
    }
    if (not pointsMatchScan($text, $root, "*:wpt", "") or
        not pointsMatchScan($text, $root, "*:rtept", "*:rte/") or
        not pointsMatchScan($text, $root, "*:trkpt", "*:trk/*:trkseg/")) {
        return false;
    }
    if (not fieldsMatchScan(gpxHead($root), ["name", "desc", "time"])) {
        return false;
    }
    for (def rte in xml.findAll($root, "*:rte")) {
        if (declaresNamespace($rte) or not fieldsMatchScan($rte, ["name", "desc"])) {
            return false;
        }
    }
    for (def trk in xml.findAll($root, "*:trk")) {
        if (declaresNamespace($trk) or not fieldsMatchScan($trk, ["name", "desc", "type"])) {
            return false;
        }
        for (def seg in xml.findAll($trk, "*:trkseg")) {
            if (declaresNamespace($seg)) {
                return false;
            }
        }
    }
    return true;
}

/** A path that matches any element 102 levels deep, the root being level 1. */
def const DEEP_PATH as string init strings.repeat("*/", MAX_NESTING) + "*";

/**
 * The markup checks of {@link treeMatchesScan}: constructs the scanner reads
 * differently from `xml.decode`, found by native searches over the text.
 *
 * - `<!DOCTYPE`: the scanner ends it at the first `>`, inside an internal subset.
 * - `<!-->`, `<!--->`: the scanner finds the comment's `-->` inside its `<!--`.
 * - `&#+`, `&#x+`: `xml.decode` reads the sign, the scanner leaves the reference.
 * - a processing instruction other than one before the root: close searches do
 *   not skip them, and the scanner ends one at the first `?>` after its `<`.
 * - `<![CDATA[` inside a comment: field text splits at it.
 *
 * @param src {bytes} the document
 * @param text {string} the same document as text
 * @return {bool} whether none of them occurs
 */
func textMatchesScan(src as bytes, text as string) {
    for (def probe in SCAN_DEPARTURES) {
        if (strings.contains($text, $probe)) {
            return false;
        }
    }
    def pis as int init strings.count($text, "<?");
    if ($pis > 1) {
        return false;
    }
    if ($pis == 1) {
        def at as int init strings.indexOf($text, "<?");
        def end as int init strings.indexOf($text, "?>", $at + 2);
        def next as int init strings.indexOf($text, "<", $at + 1);
        if ($at != strings.indexOf($text, "<") or $end < 0 or ($next >= 0 and $next < $end)) {
            return false;
        }
    }
    if (strings.contains($text, "<![CDATA[") and strings.contains($text, "<!--")) {
        return not commentHoldsCdata($src);
    }
    return true;
}

/** Substrings {@link textMatchesScan} declines on. */
def const SCAN_DEPARTURES as list of string init [
    "<!DOCTYPE",
    "<!-->",
    "<!--->",
    "&#+",
    "&#x+",
    "&#X+"
];

/** The end of a comment, as bytes. */
def const COMMENT_END_PROBE as bytes init convert.bytesFromString("-->", "utf-8");

/**
 * Whether any comment holds `<![CDATA[`.
 *
 * @param src {bytes} the document
 * @return {bool} whether one does; also `true` for an unterminated comment
 */
func commentHoldsCdata(src as bytes) {
    def at as int init indexOfByte($src, COMMENT_PROBE, 0, len($src));
    while ($at >= 0) {
        def end as int init indexOfByte($src, COMMENT_END_PROBE, $at + 4, len($src));
        if ($end < 0 or indexOfByte($src, CDATA_PROBE, $at + 4, $end) >= 0) {
            return true;
        }
        $at = indexOfByte($src, COMMENT_PROBE, $end + 3, len($src));
    }
    return false;
}

/**
 * Whether the scanner reads one kind of point as the tree holds it.
 *
 * The scanner ends a point at the next open tag of its written name, so a
 * point holding an element of its own name reads differently. The check: all
 * points of the kind share one written name, and the text holds exactly as
 * many open tags of that name as the tree holds points. Any other occurrence
 * (nested, misplaced, in a comment) fails it.
 *
 * @param text {string} the document
 * @param root {xml.Value} its decoded root
 * @param point {string} the points' path step, `*:wpt`, `*:rtept` or `*:trkpt`
 * @param parents {string} the path from the root to their parent, with a
 *   trailing `/`, or `""` for the root
 * @return {bool} whether the counts agree
 */
func pointsMatchScan(text as string, root as xml.Value, point as string, parents as string) {
    def all as list of xml.Value init xml.findAll($root, $parents + $point);
    if (len($all) == 0) {
        return true;
    }
    def tag as string init xml.tag($all[0]);
    if (len(xml.findAll($root, $parents + $tag)) != len($all)) {
        return false;
    }
    def opens as int init 0;
    for (def ending in [" ", ">", "/", "\n", "\t", "\r"]) {
        $opens = $opens + strings.count($text, "<" + $tag + $ending);
    }
    return $opens == len($all);
}

/**
 * Whether the scanner reads an element's text fields as the tree holds them.
 *
 * The scanner's field text keeps the text of child elements and splits at a
 * `<![CDATA[` inside a CDATA section; `xml.text` does neither. A field (the
 * first child of the name) with element children, or whose text holds
 * `<![CDATA[`, fails.
 *
 * @param parent {xml.Value} the element holding the fields
 * @param names {list of string} the fields' local names
 * @return {bool} whether every field is plain text
 */
func fieldsMatchScan(parent as xml.Value, names as list of string) {
    for (def name in $names) {
        def found as list of xml.Value init xml.findAll($parent, "*:" + $name);
        if (len($found) > 0 and
            (len(xml.children($found[0])) > 0 or
            strings.contains(xml.text($found[0]), "<![CDATA["))) {
            return false;
        }
    }
    return true;
}

/**
 * Whether an element declares a namespace.
 *
 * The scanner decodes each point against the root's declarations only; one on
 * a `<trk>`, `<trkseg>` or `<rte>` in between can change what a point decodes
 * to, or whether it does.
 *
 * @param element {xml.Value} the element
 * @return {bool} whether it carries an `xmlns` or `xmlns:` attribute
 */
func declaresNamespace(element as xml.Value) {
    for (def name in xml.attrs($element)) {
        if ($name == "xmlns" or strings.startsWith($name, "xmlns:")) {
            return true;
        }
    }
    return false;
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
    def pad as string init indent($depth);
    def head as string init $pad + "<" + $tag + " lat=\"" + decimal($p.lat, COORD_PLACES) +
        "\" lon=\"" + decimal($p.lon, COORD_PLACES) + "\"";
    # Empty fields are skipped here rather than in element(): most points
    # carry two of the five, and a call per absent field was a fifth of the
    # writer's time.
    def child as int init $depth + 1;
    def fields as list of string init [];
    if ($p.hasElevation) {
        $fields[] = element("ele", decimal($p.ele, ELEVATION_PLACES), $child);
    }
    if ($p.hasTime and $p.at != "") {
        $fields[] = element("time", $p.at, $child);
    }
    if ($p.name != "") {
        $fields[] = element("name", $p.name, $child);
    }
    if ($p.desc != "") {
        $fields[] = element("desc", $p.desc, $child);
    }
    if ($p.sym != "") {
        $fields[] = element("sym", $p.sym, $child);
    }
    def inner as string init strings.join($fields, "");
    if ($inner == "") {
        return $head + " />\n";
    }
    return $head + ">\n" + $inner + $pad + "</" + $tag + ">\n";
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
 * want that, and it is what keeps a round trip stable. The text is written
 * trimmed, as every reader here reads it back.
 *
 * @param tag {string} the element name
 * @param text {string} the content, trimmed and escaped here
 * @param depth {int} how far to indent it
 * @return {string} the element, or `""` when `text` is empty or whitespace
 */
func element(tag as string, text as string, depth as int) {
    def trimmed as string init strings.trim($text);
    if ($trimmed == "") {
        return "";
    }
    # One native test instead of xmlEscape's six passes for the usual text,
    # a timestamp or a plain name.
    if (regex.matches(NEEDS_ESCAPE, $trimmed)) {
        $trimmed = xmlEscape($trimmed);
    }
    return indent($depth) + "<" + $tag + ">" + $trimmed + "</" + $tag + ">\n";
}

/** What {@link xmlEscape} changes: the five escaped characters and those XML cannot hold. */
def const NEEDS_ESCAPE as string init '[&<>"\x27\x00-\x08\x0B-\x1F\x{FFFE}\x{FFFF}]';

/**
 * Indentation for one nesting depth.
 *
 * @param depth {int} how deep the element sits
 * @return {string} two spaces per level
 */
func indent(depth as int) {
    return strings.repeat("  ", $depth);
}
