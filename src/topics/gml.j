# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - the GML geometry subset.
# Spliced into geo.j via include - not a standalone module.

/** The namespace a GML 3.2 document declares. */
export def const GML_NAMESPACE as string init "http://www.opengis.net/gml/3.2";

/**
 * The `srsName` {@link writeGml} writes: WGS 84, latitude first.
 *
 * The short `EPSG:4326` that most tools write is read longitude first; see
 * {@link readGml}.
 */
export def const GML_CRS as string init "urn:ogc:def:crs:EPSG::4326";

/**
 * Read the geometries out of a GML document.
 *
 * A subset: GML (ISO 19136) is a framework that application schemas build
 * formats from, so this reads the geometry vocabulary that WFS responses and
 * embedded GML share:
 *
 *   `Point`, `LineString`, `LinearRing`, `Curve`, `Polygon`
 *   `MultiPoint`, `MultiCurve`, `MultiGeometry`, `MultiSurface`
 *   `pos`, `posList` and the deprecated `coordinates`
 *
 * Geometries are found at any depth (to `MAX_NESTING`), so an unknown
 * application schema still reads. A feature's `name` or `gml:name` names the
 * geometries inside it. A `Polygon` yields one track per ring, interior rings
 * included.
 *
 * Axis order: `pos` and `posList` are latitude first for an `srsName` that is
 * a `urn:` or `opengis.net/def/crs/` name or is absent, and longitude first for
 * `CRS:84` / `CRS84` and any other name, `EPSG:4326` included. The `srsName`
 * nearest the geometry applies. `coordinates` is always read `lon,lat`.
 *
 * @param text {string} the document
 * @return {Document} the geometries it held
 * @throws {Error} when the text holds no XML element, a coordinate does not parse
 *   or is out of range, a list does not divide into positions, or the nesting
 *   passes `MAX_NESTING`
 * @example
 *   def doc as geo.Document init geo.readGml(fs.readString("features.gml"));
 */
export func readGml(text as string) {
    return readGmlBytes(convert.bytesFromString($text, "utf-8"));
}

/**
 * Read a GML document from its bytes.
 *
 * What {@link open} calls, so a file is scanned as read rather than decoded
 * to a string first.
 *
 * @param src {bytes} the document, as UTF-8
 * @return {Document} the geometries it held
 * @throws {Error} when the bytes are not XML, or a coordinate does not parse
 */
func readGmlBytes(src as bytes) {
    def root as Node init rootNode($src);
    def out as Document init document();
    def rootCrs as string init nodeAttr($src, $root, "srsName");
    # A bare <gml:Point> or <gml:LineString> is a whole GML document, and is
    # what a WFS hands back for a single geometry - so the root is a candidate
    # geometry, not just a container to look inside.
    if (isGmlGeometry(localName($root.name))) {
        return mergeDocument($out, gmlGeometry($src, $root, "", $rootCrs, 0));
    }
    def top as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    $out.name = childText($src, $top, "name");
    return collectGml($out, $src, $top, "", $rootCrs, 0);
}

/**
 * Walk a GML document, collecting every geometry at any depth.
 *
 * Contributions are appended into local lists and the document is assembled
 * once, rather than merged per node. Merging per node copies the accumulated
 * lists every time, which is quadratic in the number of features: 2,000
 * `featureMember`s took 14 seconds that way, and a 20,000-feature WFS response
 * would have taken a quarter of an hour.
 *
 * @param into {Document} the document to fill in
 * @param src {bytes} the whole document
 * @param nodes {list of Node} the children to walk
 * @param name {string} the name inherited from the enclosing feature
 * @param crs {string} the `srsName` inherited from an enclosing element
 * @param depth {int} how many elements deep this call is
 * @return {Document} a fresh document; the argument is not changed
 * @throws {Error} when a coordinate does not parse, or the nesting is too deep
 */
func collectGml(
    into as Document,
    src as bytes,
    nodes as list of Node,
    name as string,
    crs as string,
    depth as int) {
    checkDepth($depth, "GML elements");
    def waypoints as list of Point init $into.waypoints;
    def routes as list of Route init $into.routes;
    def tracks as list of Track init $into.tracks;
    for (def node in $nodes) {
        def got as Document init gmlNode($src, $node, $name, $crs, $depth);
        for (def p in $got.waypoints) {
            $waypoints[] = $p;
        }
        for (def r in $got.routes) {
            $routes[] = $r;
        }
        for (def t in $got.tracks) {
            $tracks[] = $t;
        }
    }
    def out as Document init $into;
    $out.waypoints = $waypoints;
    $out.routes = $routes;
    $out.tracks = $tracks;
    return $out;
}

/**
 * What one element of a GML document contributes.
 *
 * A geometry contributes itself; anything else with content is descended into,
 * carrying its own `name` and `srsName` inwards.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the element
 * @param name {string} the name inherited from the enclosing feature
 * @param crs {string} the `srsName` inherited from an enclosing element
 * @param depth {int} how many elements deep this call is
 * @return {Document} only what this element and its children contributed
 * @throws {Error} when a coordinate does not parse, or the nesting is too deep
 */
func gmlNode(src as bytes, node as Node, name as string, crs as string, depth as int) {
    def kind as string init localName($node.name);
    def here as string init inheritedCrs($src, $node, $crs);
    if (isGmlGeometry($kind)) {
        return gmlGeometry($src, $node, $name, $here, $depth);
    }
    if ($node.openEnd >= $node.innerEnd) {
        return document();
    }
    def inner as list of Node init childNodes($src, $node.openEnd, $node.innerEnd);
    def label as string init featureName($src, $inner, $name);
    return collectGml(document(), $src, $inner, $label, $here, $depth + 1);
}

/**
 * The `srsName` in force for an element.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the element
 * @param inherited {string} what the enclosing element declared
 * @return {string} this element's `srsName`, or the inherited one
 */
func inheritedCrs(src as bytes, node as Node, inherited as string) {
    def declared as string init nodeAttr($src, $node, "srsName");
    if ($declared != "") {
        return $declared;
    }
    return $inherited;
}

/**
 * The name a feature element gives what is inside it.
 *
 * @param src {bytes} the whole document
 * @param inner {list of Node} the feature's children
 * @param inherited {string} the name from further out
 * @return {string} this feature's `name`, or the inherited one
 */
func featureName(src as bytes, inner as list of Node, inherited as string) {
    def found as string init childText($src, $inner, "name");
    if ($found != "") {
        return $found;
    }
    return $inherited;
}

/**
 * Whether a local name is a GML geometry this deck reads.
 *
 * @param name {string} the element's local name
 * @return {bool} whether it is one of the geometries in the subset
 */
func isGmlGeometry(name as string) {
    if ($name == "Point" or $name == "LineString" or $name == "LinearRing") {
        return true;
    }
    if ($name == "Curve" or $name == "Polygon" or $name == "MultiPoint") {
        return true;
    }
    return $name == "MultiCurve" or $name == "MultiGeometry" or $name == "MultiSurface";
}

/**
 * Read one GML geometry.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the geometry element
 * @param name {string} what to call what comes out of it
 * @param crs {string} the `srsName` in force
 * @param depth {int} how many elements deep this call is
 * @return {Document} a document holding only what this geometry contributed
 * @throws {Error} when a coordinate does not parse, or the nesting is too deep
 */
func gmlGeometry(src as bytes, node as Node, name as string, crs as string, depth as int) {
    def kind as string init localName($node.name);
    def out as Document init document();
    if (isGmlMulti($kind)) {
        def inner as list of Node init childNodes($src, $node.openEnd, $node.innerEnd);
        return collectGml($out, $src, $inner, $name, $crs, $depth + 1);
    }
    def points as list of Point init gmlPositions($src, $node, $crs, $depth);
    if (len($points) == 0) {
        return $out;
    }
    if ($kind == "Point") {
        def p as Point init $points[0];
        $p.name = $name;
        $out.waypoints = [$p];
        return $out;
    }
    $out.tracks = [track($name, $points)];
    return $out;
}

/**
 * Whether a local name is a GML aggregate rather than a single geometry.
 *
 * @param name {string} the element's local name
 * @return {bool} whether its children are themselves geometries
 */
func isGmlMulti(name as string) {
    return $name == "MultiPoint" or $name == "MultiCurve" or $name == "MultiGeometry" or
        $name == "MultiSurface" or $name == "Polygon";
}

/**
 * Every position inside a geometry element, at any depth.
 *
 * GML wraps its coordinate lists in a different intermediate element for each
 * geometry - `exterior` / `LinearRing` for a polygon, `segments` /
 * `LineStringSegment` for a curve - so the coordinate carriers are gathered by
 * descending rather than by knowing each shape's schema.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the geometry element
 * @param crs {string} the `srsName` in force
 * @param depth {int} how many elements deep this call is
 * @return {list of Point} the positions, in document order
 * @throws {Error} when a coordinate does not parse, or the nesting is too deep
 */
func gmlPositions(src as bytes, node as Node, crs as string, depth as int) {
    checkDepth($depth, "GML elements");
    def out as list of Point init [];
    def fields as list of Node init childNodes($src, $node.openEnd, $node.innerEnd);
    for (def field in $fields) {
        def kind as string init localName($field.name);
        def here as string init inheritedCrs($src, $field, $crs);
        def found as list of Point init positionsOf($src, $field, $kind, $here, $depth);
        for (def p in $found) {
            $out[] = $p;
        }
    }
    return $out;
}

/**
 * The positions one child of a geometry carries.
 *
 * @param src {bytes} the whole document
 * @param field {Node} the child element
 * @param kind {string} the child's local name
 * @param crs {string} the `srsName` in force
 * @param depth {int} how many elements deep this call is
 * @return {list of Point} what it carried, or nothing
 * @throws {Error} when a coordinate does not parse, or the nesting is too deep
 */
func positionsOf(src as bytes, field as Node, kind as string, crs as string, depth as int) {
    if ($kind == "pos") {
        return parseGmlTuples(nodeText($src, $field), 1, $crs);
    }
    if ($kind == "posList") {
        return parseGmlTuples(nodeText($src, $field), gmlDimension($src, $field), $crs);
    }
    if ($kind == "coordinates") {
        return parseCoordinates(nodeText($src, $field));
    }
    if ($field.openEnd < $field.innerEnd) {
        return gmlPositions($src, $field, $crs, $depth + 1);
    }
    return [];
}

/**
 * How many numbers one position of a `posList` takes.
 *
 * `srsDimension` states it; without one, two is the only safe assumption,
 * because a flat list of numbers cannot be split any other way.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the `posList` element
 * @return {int} 2 or 3
 * @throws {Error} when `srsDimension` is neither
 */
func gmlDimension(src as bytes, node as Node) {
    def stated as string init nodeAttr($src, $node, "srsDimension");
    if ($stated == "") {
        return 2;
    }
    # Compared as a float before any rounding: 1e300 does not fit an int, and
    # rounding first accepted 2.4 as 2.
    def dimension as float init number($stated, "srsDimension");
    if ($dimension != 2.0 and $dimension != 3.0) {
        fail("srsDimension " + quoted($stated) + " is not 2 or 3");
    }
    return math.round($dimension);
}

/**
 * Parse a whitespace-separated run of GML coordinate numbers.
 *
 * @param text {string} the element's content
 * @param dimension {int} how many numbers one position takes, 1 for a bare `pos`
 * @param crs {string} the `srsName` in force
 * @return {list of Point} the positions, in order
 * @throws {Error} when the count is not a whole number of positions, or one does not parse
 */
func parseGmlTuples(text as string, dimension as int, crs as string) {
    def fields as list of string init whitespaceFields($text);
    def stride as int init $dimension;
    if ($stride == 1) {
        # A bare <pos> is one position, however many numbers it carries.
        $stride = len($fields);
    }
    if ($stride < 2) {
        fail("a GML position needs at least two numbers");
    }
    if (len($fields) % $stride != 0) {
        fail("a GML coordinate list of " + convert.toString(len($fields)) +
            " numbers does not divide into positions of " + convert.toString($stride));
    }
    def latFirst as bool init gmlLatitudeFirst($crs);
    def out as list of Point init [];
    for (def i as int init 0; $i + $stride <= len($fields); $i = $i + $stride) {
        $out[] = gmlPoint($fields, $i, $stride, $latFirst);
    }
    return $out;
}

/**
 * One position out of a run of GML numbers.
 *
 * @param fields {list of string} every number in the list
 * @param at {int} where this position starts
 * @param stride {int} how many numbers one position takes
 * @param latFirst {bool} whether the CRS puts latitude first
 * @return {Point} the position
 * @throws {Error} when a number does not parse, or a coordinate is out of range
 */
func gmlPoint(fields as list of string, at as int, stride as int, latFirst as bool) {
    def first as float init number($fields[$at], "a GML coordinate");
    def second as float init number($fields[$at + 1], "a GML coordinate");
    def lat as float init $first;
    def lon as float init $second;
    if (not $latFirst) {
        $lat = $second;
        $lon = $first;
    }
    checkCoord($lat, $lon);
    def out as Point init point($lat, $lon);
    if ($stride > 2) {
        $out = withElevation($out, number($fields[$at + 2], "a GML elevation"));
    }
    return $out;
}

/**
 * Whether a CRS name puts latitude before longitude.
 *
 * The URN form of EPSG:4326 is latitude first, as is its
 * `http://www.opengis.net/def/crs/EPSG/0/4326` spelling and the GML default
 * when nothing is stated. The short `EPSG:4326` form is what tools write when they
 * mean longitude first, and `CRS:84` says so outright.
 *
 * @param crs {string} the `srsName`, or `""`
 * @return {bool} whether latitude comes first
 */
func gmlLatitudeFirst(crs as string) {
    def name as string init strings.lower(strings.trim($crs));
    if ($name == "") {
        return true;
    }
    if (strings.contains($name, "crs:84") or strings.contains($name, "crs84")) {
        return false;
    }
    # The http form is the OGC's own name for the URN, used by GML 3.2 and
    # INSPIRE, and means the same axis order.
    if (strings.startsWith($name, "urn:") or strings.contains($name, "opengis.net/def/crs/")) {
        return true;
    }
    return false;
}

/**
 * Write a document as a GML 3.2 feature collection.
 *
 * One `featureMember` per waypoint, route and track segment, holding a
 * `gml:Point` or a `gml:LineString` with a `gml:posList`, in {@link GML_CRS}
 * (latitude first). Positions are two-dimensional, so elevations are dropped,
 * as are descriptions, symbols and times; a path of fewer than two points is
 * skipped. Not schema-valid against any application schema, since GML has no
 * generic one.
 *
 * @param doc {Document} what to write
 * @return {string} a GML 3.2 feature collection
 * @example
 *   fs.writeString("out.gml", geo.writeGml($doc));
 */
export func writeGml(doc as Document) {
    def parts as list of string init [];
    $parts[] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    $parts[] = "<gml:FeatureCollection xmlns:gml=\"" + GML_NAMESPACE + "\">\n";
    $parts[] = element("gml:name", $doc.name, 1);
    for (def wpt in $doc.waypoints) {
        $parts[] = gmlMember($wpt.name, gmlPointElement($wpt, 3));
    }
    for (def rte in $doc.routes) {
        $parts[] = gmlLineMember($rte.name, $rte.points);
    }
    for (def trk in $doc.tracks) {
        for (def seg in $trk.segments) {
            $parts[] = gmlLineMember($trk.name, $seg.points);
        }
    }
    $parts[] = "</gml:FeatureCollection>\n";
    return strings.join($parts, "");
}

/**
 * Write one `gml:featureMember`.
 *
 * @param name {string} what to call the feature
 * @param geometry {string} the geometry element, already rendered
 * @return {string} the member
 */
func gmlMember(name as string, geometry as string) {
    def parts as list of string init [indent(1) + "<gml:featureMember>\n"];
    $parts[] = indent(2) + "<gml:Feature>\n";
    $parts[] = element("gml:name", $name, 3);
    $parts[] = $geometry;
    $parts[] = indent(2) + "</gml:Feature>\n";
    $parts[] = indent(1) + "</gml:featureMember>\n";
    return strings.join($parts, "");
}

/**
 * Write one `gml:featureMember` holding a `LineString`, or nothing.
 *
 * @param name {string} what to call the feature
 * @param points {list of Point} the path, in order
 * @return {string} the member, or `""` when there is no line to draw
 */
func gmlLineMember(name as string, points as list of Point) {
    if (len($points) < 2) {
        return "";
    }
    return gmlMember($name, gmlLineElement($points, 3));
}

/**
 * Write one `gml:Point`.
 *
 * @param p {Point} the position
 * @param depth {int} how far to indent it
 * @return {string} the element
 */
func gmlPointElement(p as Point, depth as int) {
    def parts as list of string init [];
    $parts[] = indent($depth) + "<gml:Point srsName=\"" + GML_CRS + "\">\n";
    $parts[] = element("gml:pos", gmlTuple($p), $depth + 1);
    $parts[] = indent($depth) + "</gml:Point>\n";
    return strings.join($parts, "");
}

/**
 * Write one `gml:LineString`.
 *
 * @param points {list of Point} the path, in order
 * @param depth {int} how far to indent it
 * @return {string} the element
 */
func gmlLineElement(points as list of Point, depth as int) {
    def tuples as list of string init [];
    for (def p in $points) {
        $tuples[] = gmlTuple($p);
    }
    def head as string init indent($depth) + "<gml:LineString srsName=\"" + GML_CRS + "\">\n";
    def list2 as string init indent($depth + 1) + "<gml:posList srsDimension=\"2\">" +
        strings.join($tuples, " ") + "</gml:posList>\n";
    return $head + $list2 + indent($depth) + "</gml:LineString>\n";
}

/**
 * One point as a GML coordinate pair.
 *
 * Latitude first, matching {@link GML_CRS}.
 *
 * @param p {Point} the point
 * @return {string} `lat lon`
 */
func gmlTuple(p as Point) {
    return decimal($p.lat, COORD_PLACES) + " " + decimal($p.lon, COORD_PLACES);
}
