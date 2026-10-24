# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - GeoJSON, RFC 7946.
# Spliced into geo.j via include - not a standalone module.

/**
 * Read a GeoJSON document.
 *
 * A `FeatureCollection`, a single `Feature`, or a bare geometry. `Point`
 * becomes a waypoint and `MultiPoint` one waypoint per position;
 * `LineString` becomes a track, `MultiLineString` a track with one segment per
 * line; `Polygon` becomes a track along its outer ring and `MultiPolygon` a
 * track with one segment per outer ring, holes dropped; `GeometryCollection`
 * contributes each of its geometries. Other types contribute nothing.
 *
 * Positions are `[lon, lat]` or `[lon, lat, ele]`, longitude first as RFC 7946
 * requires; the reader swaps them. `properties.name`, `properties.description`
 * and `properties.sym` fill the name, description and symbol.
 *
 * @param text {string} the document
 * @return {Document} what it held
 * @throws {Error} when the text is not JSON, a position is malformed or out of
 *   range, or geometry collections nest past `MAX_NESTING`
 * @example
 *   def doc as geo.Document init geo.readGeojson(fs.readString("places.geojson"));
 */
export func readGeojson(text as string) {
    def root as json.Value init json.map();
    try {
        $root = json.decode($text);
    } catch (e) {
        fail("not JSON: " + $e.message);
    }
    def out as Document init document();
    def kind as string init jsonString($root, "/type");
    if ($kind == "FeatureCollection") {
        return readFeatureCollection($out, $root);
    }
    if ($kind == "Feature") {
        return mergeDocument($out, readFeature($root, 0));
    }
    return mergeDocument($out, readGeometry($root, "", "", "", 0));
}

/**
 * Read a `FeatureCollection`.
 *
 * Features are appended into local lists and the document is assembled once,
 * rather than merged per feature. Merging per feature copies the accumulated
 * lists every time, which is quadratic in the feature count: 2,000 features took
 * eight seconds that way, and a 20,000-feature city dataset - an ordinary size
 * for GeoJSON - would have taken a quarter of an hour.
 *
 * @param into {Document} the document to fill in
 * @param root {json.Value} the collection
 * @return {Document} a fresh document; the argument is not changed
 * @throws {Error} when a feature is malformed
 */
func readFeatureCollection(into as Document, root as json.Value) {
    def out as Document init $into;
    if (not json.has($root, "/features")) {
        return $out;
    }
    def waypoints as list of Point init $out.waypoints;
    def routes as list of Route init $out.routes;
    def tracks as list of Track init $out.tracks;
    def features as json.Value init jsonArray(json.get($root, "/features"), "GeoJSON features");
    def count as int init json.length($features);
    for (def i as int init 0; $i < $count; $i = $i + 1) {
        def at as string init "/features/" + convert.toString($i);
        def got as Document init readFeature(json.get($root, $at), 0);
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
    $out.waypoints = $waypoints;
    $out.routes = $routes;
    $out.tracks = $tracks;
    return $out;
}

/**
 * Read one `Feature`.
 *
 * @param feature {json.Value} the feature
 * @param depth {int} how many levels deep this call is
 * @return {Document} a document holding only what this feature contributed
 * @throws {Error} when its geometry is malformed, or the nesting is too deep
 */
func readFeature(feature as json.Value, depth as int) {
    def name as string init featureProperty($feature, "name");
    def desc as string init featureProperty($feature, "description");
    def sym as string init featureProperty($feature, "sym");
    if (not json.has($feature, "/geometry")) {
        return document();
    }
    return readGeometry(json.get($feature, "/geometry"), $name, $desc, $sym, $depth);
}

/**
 * One of a feature's conventional string properties.
 *
 * @param feature {json.Value} the feature
 * @param key {string} the property to read
 * @return {string} its value, or `""` when it is absent or not a string
 */
func featureProperty(feature as json.Value, key as string) {
    return jsonString($feature, "/properties/" + $key);
}

/**
 * Read one geometry.
 *
 * @param geometry {json.Value} the geometry
 * @param name {string} what to call what comes out of it
 * @param desc {string} a longer description
 * @param sym {string} the symbol to draw a point with
 * @param depth {int} how many levels deep this call is
 * @return {Document} a document holding only what this geometry contributed
 * @throws {Error} when a position is malformed, or the nesting is too deep
 */
func readGeometry(
    geometry as json.Value,
    name as string,
    desc as string,
    sym as string,
    depth as int) {
    checkDepth($depth, "GeoJSON geometries");
    def kind as string init jsonString($geometry, "/type");
    if ($kind == "GeometryCollection") {
        return readGeometryCollection($geometry, $name, $desc, $sym, $depth);
    }
    if (not json.has($geometry, "/coordinates")) {
        return document();
    }
    def coords as json.Value init json.get($geometry, "/coordinates");
    if ($kind == "Point") {
        return pointDocument(readPosition($coords), $name, $desc, $sym);
    }
    if ($kind == "MultiPoint") {
        return multiPointDocument($coords, $name, $desc, $sym);
    }
    return lineDocument($kind, $coords, $name, $desc);
}

/**
 * Read a `GeometryCollection`.
 *
 * Appended into locals and assembled once, for the same reason
 * {@link readFeatureCollection} is.
 *
 * @param geometry {json.Value} the collection
 * @param name {string} what to call what comes out of it
 * @param desc {string} a longer description
 * @param sym {string} the symbol to draw a point with
 * @param depth {int} how many levels deep this call is
 * @return {Document} a document holding everything the collection contributed
 * @throws {Error} when a position is malformed, or the nesting is too deep
 */
func readGeometryCollection(
    geometry as json.Value,
    name as string,
    desc as string,
    sym as string,
    depth as int) {
    def out as Document init document();
    if (not json.has($geometry, "/geometries")) {
        return $out;
    }
    def waypoints as list of Point init [];
    def tracks as list of Track init [];
    def members as json.Value init json.get($geometry, "/geometries");
    def count as int init json.length(jsonArray($members, "GeoJSON geometries"));
    for (def i as int init 0; $i < $count; $i = $i + 1) {
        def at as string init "/geometries/" + convert.toString($i);
        def inner as json.Value init json.get($geometry, $at);
        def got as Document init readGeometry($inner, $name, $desc, $sym, $depth + 1);
        for (def p in $got.waypoints) {
            $waypoints[] = $p;
        }
        for (def t in $got.tracks) {
            $tracks[] = $t;
        }
    }
    $out.waypoints = $waypoints;
    $out.tracks = $tracks;
    return $out;
}

/**
 * A document holding one named waypoint.
 *
 * @param p {Point} the position
 * @param name {string} what to call it
 * @param desc {string} a longer description
 * @param sym {string} the symbol to draw it with
 * @return {Document} a document holding just that waypoint
 */
func pointDocument(p as Point, name as string, desc as string, sym as string) {
    def out as Document init document();
    def marked as Point init $p;
    $marked.name = $name;
    $marked.desc = $desc;
    $marked.sym = $sym;
    $out.waypoints = [$marked];
    return $out;
}

/**
 * A document holding every point of a `MultiPoint`.
 *
 * @param coords {json.Value} the coordinate array
 * @param name {string} what to call each point
 * @param desc {string} a longer description
 * @param sym {string} the symbol to draw them with
 * @return {Document} a document holding the waypoints
 * @throws {Error} when a position is malformed
 */
func multiPointDocument(coords as json.Value, name as string, desc as string, sym as string) {
    def out as Document init document();
    def waypoints as list of Point init [];
    for (def p in readPositions($coords)) {
        def marked as Point init $p;
        $marked.name = $name;
        $marked.desc = $desc;
        $marked.sym = $sym;
        $waypoints[] = $marked;
    }
    $out.waypoints = $waypoints;
    return $out;
}

/**
 * A document holding the track a line geometry describes.
 *
 * `LineString` is one segment. `MultiLineString` is one segment per line.
 * `Polygon` and `MultiPolygon` are read as their outer rings - the inner rings
 * that cut holes have nowhere to go in a point-and-path model.
 *
 * @param kind {string} the geometry's `type`
 * @param coords {json.Value} the coordinate array
 * @param name {string} what to call the track
 * @param desc {string} a longer description
 * @return {Document} a document holding the track, or nothing for a type this deck does not read
 * @throws {Error} when a position is malformed
 */
func lineDocument(kind as string, coords as json.Value, name as string, desc as string) {
    def out as Document init document();
    def runs as list of list of Point init [];
    if ($kind == "LineString") {
        $runs[] = readPositions($coords);
    } elseif ($kind == "MultiLineString" or $kind == "Polygon") {
        $runs = readPositionLists($coords);
    } elseif ($kind == "MultiPolygon") {
        $runs = readPolygonRings($coords);
    } else {
        return $out;
    }
    if ($kind == "Polygon" and len($runs) > 1) {
        $runs = [$runs[0]];
    }
    def segments as list of Segment init [];
    for (def run in $runs) {
        $segments[] = Segment{points: $run};
    }
    $out.tracks = [Track{name: $name, desc: $desc, kind: "", segments: $segments}];
    return $out;
}

/**
 * Read an array of position arrays.
 *
 * @param coords {json.Value} the array
 * @return {list of list of Point} one point list per entry
 * @throws {Error} when a position is malformed
 */
func readPositionLists(coords as json.Value) {
    def out as list of list of Point init [];
    def count as int init json.length(jsonArray($coords, "GeoJSON coordinates"));
    for (def i as int init 0; $i < $count; $i = $i + 1) {
        $out[] = readPositions(json.get($coords, "/" + convert.toString($i)));
    }
    return $out;
}

/**
 * Read the outer ring of every polygon in a `MultiPolygon`.
 *
 * @param coords {json.Value} the array of polygons
 * @return {list of list of Point} one ring per polygon
 * @throws {Error} when a position is malformed
 */
func readPolygonRings(coords as json.Value) {
    def out as list of list of Point init [];
    def count as int init json.length(jsonArray($coords, "GeoJSON coordinates"));
    for (def i as int init 0; $i < $count; $i = $i + 1) {
        def at as string init "/" + convert.toString($i);
        def rings as json.Value init jsonArray(json.get($coords, $at), "a GeoJSON polygon");
        if (json.length($rings) > 0) {
            $out[] = readPositions(json.get($rings, "/0"));
        }
    }
    return $out;
}

/**
 * Read an array of positions.
 *
 * @param coords {json.Value} the array
 * @return {list of Point} the points, in order
 * @throws {Error} when a position is malformed
 */
func readPositions(coords as json.Value) {
    def out as list of Point init [];
    def count as int init json.length(jsonArray($coords, "GeoJSON coordinates"));
    for (def i as int init 0; $i < $count; $i = $i + 1) {
        $out[] = readPosition(json.get($coords, "/" + convert.toString($i)));
    }
    return $out;
}

/**
 * Read one position array.
 *
 * @param position {json.Value} the array, `[lon, lat]` or `[lon, lat, ele]`
 * @return {Point} the point
 * @throws {Error} when it holds fewer than two numbers, or a coordinate is out of range
 */
func readPosition(position as json.Value) {
    if (json.length(jsonArray($position, "a GeoJSON position")) < 2) {
        fail("a GeoJSON position needs at least a longitude and a latitude");
    }
    def lon as float init jsonFloat($position, "/0", "a GeoJSON longitude");
    def lat as float init jsonFloat($position, "/1", "a GeoJSON latitude");
    checkCoord($lat, $lon);
    def out as Point init point($lat, $lon);
    if (json.length($position) > 2) {
        $out = withElevation($out, jsonFloat($position, "/2", "a GeoJSON elevation"));
    }
    return $out;
}

/**
 * A JSON value, checked to be an array before it is walked as one.
 *
 * `json.length` also counts the members of an object, and raises
 * `kind: "runtime"` on a number, a string or a null. A shape whose arrays are
 * the wrong type is bad data, not damage: there is no position to recover.
 *
 * @param node {json.Value} the value to check
 * @param what {string} what it should be, for the message
 * @return {json.Value} the same value
 * @throws {Error} when the value is not an array
 */
func jsonArray(node as json.Value, what as string) {
    def kind as string init json.typeOf($node);
    if ($kind != "list") {
        fail($what + " is a JSON " + $kind + ", not an array");
    }
    return $node;
}

/**
 * A JSON string, or `""` when it is absent or of another type.
 *
 * @param node {json.Value} the value to read from
 * @param pointer {string} the JSON Pointer to read
 * @return {string} the string, or `""`
 */
func jsonString(node as json.Value, pointer as string) {
    if (not json.has($node, $pointer)) {
        return "";
    }
    def found as json.Value init json.get($node, $pointer);
    if (json.typeOf($found) != "string") {
        return "";
    }
    return json.asString($found);
}

/**
 * A JSON number.
 *
 * @param node {json.Value} the value to read from
 * @param pointer {string} the JSON Pointer to read
 * @param what {string} the field being read, for the error message
 * @return {float} the number
 * @throws {Error} when it is absent or not a number
 */
func jsonFloat(node as json.Value, pointer as string, what as string) {
    if (not json.has($node, $pointer)) {
        fail($what + " is missing");
    }
    def found as json.Value init json.get($node, $pointer);
    def kind as string init json.typeOf($found);
    if ($kind != "number" and $kind != "int" and $kind != "float") {
        fail($what + " is a " + $kind + ", not a number");
    }
    return json.asFloat($found);
}

/**
 * Fold one document into another.
 *
 * @param into {Document} the document to add to
 * @param more {Document} what to add
 * @return {Document} a fresh document; neither argument is changed
 */
func mergeDocument(into as Document, more as Document) {
    def out as Document init $into;
    def waypoints as list of Point init $out.waypoints;
    for (def p in $more.waypoints) {
        $waypoints[] = $p;
    }
    def routes as list of Route init $out.routes;
    for (def r in $more.routes) {
        $routes[] = $r;
    }
    def tracks as list of Track init $out.tracks;
    for (def t in $more.tracks) {
        $tracks[] = $t;
    }
    $out.waypoints = $waypoints;
    $out.routes = $routes;
    $out.tracks = $tracks;
    return $out;
}

/**
 * Write a document as a GeoJSON `FeatureCollection`.
 *
 * One `Feature` per waypoint, route and track. A track with several segments
 * becomes a `MultiLineString`, one with a single segment a `LineString`; track
 * segments of fewer than two points are left out. Routes are not filtered.
 * `name`, `description` and `sym` go in `properties`; the document name is not
 * written, since a `FeatureCollection` has no title.
 *
 * @param doc {Document} what to write
 * @return {string} a complete GeoJSON document, indented
 * @example
 *   fs.writeString("out.geojson", geo.writeGeojson($doc));
 */
export func writeGeojson(doc as Document) {
    def features as list of string init [];
    for (def wpt in $doc.waypoints) {
        $features[] = pointFeature($wpt);
    }
    for (def rte in $doc.routes) {
        $features[] = lineFeature($rte.name, $rte.desc, [$rte.points]);
    }
    for (def trk in $doc.tracks) {
        def runs as list of list of Point init [];
        for (def seg in $trk.segments) {
            if (len($seg.points) > 1) {
                $runs[] = $seg.points;
            }
        }
        if (len($runs) > 0) {
            $features[] = lineFeature($trk.name, $trk.desc, $runs);
        }
    }
    def body as string init strings.join($features, ",\n");
    # Raw strings throughout the JSON writer: a brace in a cooked string opens
    # an interpolation slot, so every literal would need escaping.
    def head as string init '{' + "\n" + '  "type": "FeatureCollection",' + "\n";
    if (len($features) == 0) {
        return $head + '  "features": []' + "\n" + '}' + "\n";
    }
    return $head + '  "features": [' + "\n" + $body + "\n" + '  ]' + "\n" + '}' + "\n";
}

/**
 * Write one waypoint as a `Point` feature.
 *
 * @param p {Point} the waypoint
 * @return {string} the feature, indented four spaces
 */
func pointFeature(p as Point) {
    return geojsonFeature(
        $p.name,
        $p.desc,
        $p.sym,
        '"type": "Point", "coordinates": ' + positionText($p));
}

/**
 * Write one path as a `LineString` or `MultiLineString` feature.
 *
 * @param name {string} what to call it
 * @param desc {string} a longer description
 * @param runs {list of list of Point} one point list per unbroken run
 * @return {string} the feature, indented four spaces
 */
func lineFeature(name as string, desc as string, runs as list of list of Point) {
    def lines as list of string init [];
    for (def run in $runs) {
        def tuples as list of string init [];
        for (def p in $run) {
            $tuples[] = positionText($p);
        }
        $lines[] = "[" + strings.join($tuples, ", ") + "]";
    }
    if (len($lines) == 1) {
        return geojsonFeature(
            $name,
            $desc,
            "",
            '"type": "LineString", "coordinates": ' + $lines[0]);
    }
    return geojsonFeature(
        $name,
        $desc,
        "",
        '"type": "MultiLineString", ' + '"coordinates": [' + strings.join($lines, ", ") + "]");
}

/**
 * Write a feature around a geometry.
 *
 * @param name {string} what to call it
 * @param desc {string} a longer description
 * @param sym {string} the symbol to draw it with
 * @param geometry {string} the geometry's members, already rendered
 * @return {string} the feature, indented four spaces
 */
func geojsonFeature(name as string, desc as string, sym as string, geometry as string) {
    def properties as list of string init [];
    if (strings.trim($name) != "") {
        $properties[] = '"name": ' + jsonText($name);
    }
    if (strings.trim($desc) != "") {
        $properties[] = '"description": ' + jsonText($desc);
    }
    if (strings.trim($sym) != "") {
        $properties[] = '"sym": ' + jsonText($sym);
    }
    def props as string init '{' + strings.join($properties, ", ") + '}';
    def parts as list of string init ['    {' + "\n"];
    $parts[] = '      "type": "Feature",' + "\n";
    $parts[] = '      "properties": ' + $props + ',' + "\n";
    $parts[] = '      "geometry": {' + $geometry + '}' + "\n";
    $parts[] = '    }';
    return strings.join($parts, "");
}

/**
 * One point as a GeoJSON position.
 *
 * @param p {Point} the point
 * @return {string} `[lon, lat]` or `[lon, lat, ele]` - longitude first, as RFC 7946 requires
 */
func positionText(p as Point) {
    def out as string init "[" + decimal($p.lon, COORD_PLACES) + ", " +
        decimal($p.lat, COORD_PLACES);
    if ($p.hasElevation) {
        return $out + ", " + decimal($p.ele, ELEVATION_PLACES) + "]";
    }
    return $out + "]";
}

/**
 * A string as a JSON string literal.
 *
 * `json.encode` encodes any value, a bare string included, so the escaping of
 * every name and description this deck writes is the interpreter's rather than
 * one of this deck's.
 *
 * @param s {string} the text
 * @return {string} the quoted literal
 */
func jsonText(s as string) {
    return json.encode($s);
}
