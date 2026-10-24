# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - the shared primitives every other topic builds on.
# Spliced into geo.j via include - not a standalone module.

/** The `kind` every `Error` this deck raises carries. */
export def const ERROR_KIND as string init "geo";

/** How many decimal places a latitude or longitude is written with. */
export def const COORD_PLACES as int init 7;

/** How many decimal places an elevation is written with. */
export def const ELEVATION_PLACES as int init 2;

/**
 * How deeply a document may nest containers before a reader refuses it.
 *
 * KML nests `Folder`s, GML nests application-schema elements, and GeoJSON nests
 * `GeometryCollection`s, so a reader has to descend - and the depth comes from
 * the file, which means from whoever wrote the file. Two reasons for a ceiling:
 *
 *   The cost of descending is not linear. Each level rescans the range inside
 *   it, so a document nested `n` deep costs on the order of `n` squared to
 *   walk: 800 nested folders in a 13 KB file took 11 seconds to read before
 *   this limit existed, and 10,000 would have taken half an hour. That is a
 *   denial of service out of a file that fits in an email.
 *
 *   Jennifer caps recursion at 10,000 nested calls and raises there, but with
 *   `kind` `"runtime"` - so without a limit of its own this deck would break
 *   its own promise that every failure it raises carries `kind` `"geo"`.
 *
 * Real documents nest a handful of levels. 100 is far past anything a drawing
 * tool or a WFS produces, and bounds the walk at well under a second.
 */
export def const MAX_NESTING as int init 100;

/**
 * Check that a reader has not descended too far.
 *
 * @param depth {int} how many levels down the reader is
 * @param what {string} the kind of nesting, for the error message
 * @throws {Error} when `depth` is past `MAX_NESTING`
 */
func checkDepth(depth as int, what as string) {
    if ($depth > MAX_NESTING) {
        fail($what + " nested more than " + convert.toString(MAX_NESTING) +
            " deep; refusing to descend further");
    }
}

/**
 * A fragment of document text, bounded, for an error message.
 *
 * Error messages quote the input that caused them, and the input is whatever
 * the file said - a 500 KB attribute value produced a 500 KB error message
 * before this existed. A message that cannot be read, logged or stored is not a
 * better message for being complete.
 *
 * @param text {string} the text to quote
 * @return {string} the text in quotes, truncated past 48 characters
 */
func quoted(text as string) {
    if (len($text) <= 48) {
        return "\"" + $text + "\"";
    }
    return "\"" + strings.substring($text, 0, 48) + "\"... (" + convert.toString(len($text)) +
        " characters)";
}

/**
 * Raise a deck error.
 *
 * Every failure in the deck goes through here, so a caller can catch the
 * whole surface with one `kind` test. The message is written for a human: it
 * names the element, coordinate or file the operation was on.
 *
 * @param message {string} what went wrong, in plain words
 * @throws {Error} always, with `kind` `"geo"`
 */
func fail(message as string) {
    throw Error{kind: ERROR_KIND, message: $message, file: "", line: 0, col: 0};
}

/**
 * The local part of an XML tag name.
 *
 * Jennifer's `xml` keeps namespace prefixes verbatim and does not resolve
 * them, so `<kml:Placemark>` and `<Placemark>` are different tags to it. KML
 * and GML in the wild are written both ways - and GML is almost always
 * prefixed - so every tag this deck matches is matched on its local part.
 *
 * @param name {string} a tag name, with or without a prefix
 * @return {string} everything after the first colon, or the whole name
 * @example
 *   localName("gml:posList");   # "posList"
 *   localName("trkpt");         # "trkpt"
 */
func localName(name as string) {
    def colon as int init strings.indexOf($name, ":");
    if ($colon < 0) {
        return $name;
    }
    return strings.substring($name, $colon + 1, len($name));
}

/** The characters XML 1.0 cannot hold, as an RE2 class. */
def const XML_ILLEGAL as string init '[\x00-\x08\x0B\x0C\x0E-\x1F\x{FFFE}\x{FFFF}]';

/**
 * Escape a string for XML character data or an attribute value.
 *
 * All five predefined entities are written, not the three a text node
 * strictly needs, so the same function serves both positions.
 *
 * Characters XML 1.0 forbids outright - the C0 controls other than tab, line
 * feed and carriage return, and U+FFFE / U+FFFF - are dropped. No escape can
 * carry them (`&#1;` is just as illegal), and a strict parser rejects the
 * whole file over one.
 *
 * @param s {string} the text to escape
 * @return {string} the text with `& < > " '` replaced by their entities and
 *   characters XML cannot hold removed
 */
func xmlEscape(s as string) {
    def legal as string init regex.replace(XML_ILLEGAL, $s, "");
    def out as string init strings.replace($legal, "&", "&amp;");
    $out = strings.replace($out, "<", "&lt;");
    $out = strings.replace($out, ">", "&gt;");
    $out = strings.replace($out, "\"", "&quot;");
    return strings.replace($out, "'", "&apos;");
}

/**
 * Resolve one entity reference, without its `&` and `;`.
 *
 * @param body {string} what stood between the `&` and the `;`
 * @return {string} the replacement, or `""` when the name is not known
 */
func entityBody(body as string) {
    if ($body == "amp") {
        return "&";
    }
    if ($body == "lt") {
        return "<";
    }
    if ($body == "gt") {
        return ">";
    }
    if ($body == "quot") {
        return "\"";
    }
    if ($body == "apos") {
        return "'";
    }
    return numericEntity($body);
}

/**
 * Resolve a numeric character reference, without its `&` and `;`.
 *
 * @param body {string} `#NN` for decimal, `#xNN` for hexadecimal
 * @return {string} the character, or `""` when the body is not numeric
 */
func numericEntity(body as string) {
    if (len($body) < 2 or strings.substring($body, 0, 1) != "#") {
        return "";
    }
    def digits as string init strings.substring($body, 1, len($body));
    def hex as bool init false;
    if (len($digits) > 1 and strings.lower(strings.substring($digits, 0, 1)) == "x") {
        $hex = true;
        $digits = strings.substring($digits, 1, len($digits));
    }
    def code as int init digitsToInt($digits, $hex);
    if ($code <= 0) {
        return "";
    }
    def out as string init "";
    try {
        $out = convert.fromCodepoint($code);
    } catch (e) {
        return "";
    }
    return $out;
}

/**
 * Read an unsigned integer out of its digits.
 *
 * `convert.toInt` parses decimal only - it has no radix argument - so the
 * hexadecimal half of a numeric character reference is read here.
 *
 * @param digits {string} the digits, with no sign and no radix prefix
 * @param hex {bool} whether to read them as base 16 rather than base 10
 * @return {int} the value, or `-1` when a character is not a digit or the
 *   value is past the last Unicode code point
 */
func digitsToInt(digits as string, hex as bool) {
    def radix as int init 10;
    if ($hex) {
        $radix = 16;
    }
    def value as int init 0;
    for (def ch in strings.chars($digits)) {
        def d as int init digitValue($ch);
        if ($d < 0 or $d >= $radix) {
            return -1;
        }
        $value = $value * $radix + $d;
        # Stop at the last code point, 0x10FFFF. Twenty digits overflow int64,
        # which raised kind "runtime" out of a name or a creator attribute.
        if ($value > 0x10FFFF) {
            return -1;
        }
    }
    if (len($digits) == 0) {
        return -1;
    }
    return $value;
}

/**
 * The numeric value of one hexadecimal digit.
 *
 * @param ch {string} a single character
 * @return {int} 0-15, or `-1` when the character is not a hexadecimal digit
 */
func digitValue(ch as string) {
    def found as int init strings.indexOf("0123456789abcdef", strings.lower($ch));
    return $found;
}

/**
 * Decode the entity references in XML character data.
 *
 * The five predefined entities and numeric character references, decimal and
 * hexadecimal. An unknown entity is left standing rather than raising: a
 * reader that throws on one cannot open the files a GIS exporter writes.
 *
 * @param s {string} text that may carry entity references
 * @return {string} the text with every reference this deck knows resolved
 * @example
 *   xmlUnescape("Ca&#241;on &amp; Rim");   # "Cañon & Rim"
 */
func xmlUnescape(s as string) {
    if (strings.indexOf($s, "&") < 0) {
        return $s;
    }
    def parts as list of string init strings.split($s, "&");
    def out as list of string init [$parts[0]];
    for (def i as int init 1; $i < len($parts); $i = $i + 1) {
        $out[] = resolveReference($parts[$i]);
    }
    return strings.join($out, "");
}

/**
 * Resolve the leading entity reference of a fragment that followed an `&`.
 *
 * @param part {string} everything after one `&`, up to the next one
 * @return {string} the fragment with its leading reference resolved
 */
func resolveReference(part as string) {
    def semi as int init strings.indexOf($part, ";");
    if ($semi < 0) {
        return "&" + $part;
    }
    def body as string init strings.substring($part, 0, $semi);
    def replacement as string init entityBody($body);
    if ($replacement == "") {
        return "&" + $part;
    }
    return $replacement + strings.substring($part, $semi + 1, len($part));
}

/**
 * Format a float with a fixed number of decimals and no trailing zeros.
 *
 * Coordinates are written this way so a document round-trips without growing
 * noise digits: `47.2692` stays `47.2692` rather than becoming
 * `47.2692000`, and a value that needs all seven places keeps all seven.
 *
 * Negative zero is written as `0`, not `-0`.
 *
 * @param value {float} the number to write
 * @param places {int} how many decimals to keep, at most
 * @return {string} the shortest spelling of `value` at that precision
 * @example
 *   decimal(47.2692, COORD_PLACES);    # "47.2692"
 *   decimal(574.0, ELEVATION_PLACES);  # "574"
 *   decimal(-0.0, COORD_PLACES);       # "0"
 */
func decimal(value as float, places as int) {
    def text as string init io.sprintf("%f|prec={$places}", $value);
    if (strings.indexOf($text, ".") < 0) {
        return $text;
    }
    def trimmed as string init trimTrailing(trimTrailing($text, "0"), ".");
    # A coordinate of negative zero is a real value that reaches here through
    # normalizeLongitude and through plain arithmetic, and "-0" in a document is
    # the kind of thing a strict downstream validator rejects.
    if ($trimmed == "-0" or $trimmed == "-") {
        return "0";
    }
    return $trimmed;
}

/**
 * Strip every trailing copy of one character.
 *
 * `strings.trimRight` trims whitespace and takes no cutset, so the
 * trailing-zero trim that keeps written coordinates short is done here.
 *
 * @param s {string} the text to trim
 * @param ch {string} the single character to strip from the end
 * @return {string} `s` with its trailing `ch` run removed
 */
func trimTrailing(s as string, ch as string) {
    def end as int init len($s);
    while ($end > 0 and strings.substring($s, $end - 1, $end) == $ch) {
        $end = $end - 1;
    }
    return strings.substring($s, 0, $end);
}

/**
 * Parse a decimal number out of document text.
 *
 * Leading and trailing whitespace is tolerated, because XML indentation puts
 * it there. Anything else is an error: a coordinate that does not parse is
 * damage a reader cannot work around.
 *
 * @param s {string} the text to read
 * @param what {string} the field being read, for the error message
 * @return {float} the value
 * @throws {Error} when the text is not a number
 */
func number(s as string, what as string) {
    def trimmed as string init strings.trim($s);
    if ($trimmed == "") {
        fail($what + " is empty");
    }
    # convert.toFloat accepts Jennifer's digit separators, so "1_0" read as a
    # latitude of 10. No coordinate format writes one.
    if (strings.contains($trimmed, "_")) {
        fail($what + " is not a number: " + quoted($trimmed));
    }
    def value as float init 0.0;
    try {
        $value = convert.toFloat($trimmed);
    } catch (e) {
        fail($what + " is not a number: " + quoted($trimmed));
    }
    return $value;
}

/**
 * Check that a latitude and longitude name a point on the Earth.
 *
 * @param lat {float} degrees north, -90 to 90
 * @param lon {float} degrees east, -180 to 180
 * @throws {Error} when either is outside its range
 */
func checkCoord(lat as float, lon as float) {
    # convert.toString rather than decimal(): a hostile file can reach 1e308,
    # which decimal() spells with 309 digits.
    if ($lat < -90.0 or $lat > 90.0) {
        fail("latitude " + convert.toString($lat) + " is outside -90..90");
    }
    if ($lon < -180.0 or $lon > 180.0) {
        fail("longitude " + convert.toString($lon) + " is outside -180..180");
    }
}

/**
 * Clamp a value into the closed range -1 to 1.
 *
 * `math.acos` and `math.asin` raise on an argument outside their domain
 * rather than returning a NaN, and the geodesy formulae reach `1.0` by
 * rounding for two points a few centimetres apart. Every argument to an
 * inverse trigonometric function in this deck goes through here.
 *
 * @param value {float} the argument to clamp
 * @return {float} `value`, or the nearer of -1.0 and 1.0
 */
func clampUnit(value as float) {
    if ($value > 1.0) {
        return 1.0;
    }
    if ($value < -1.0) {
        return -1.0;
    }
    return $value;
}

/**
 * Normalise a bearing into the half-open range 0 to 360 degrees.
 *
 * @param degrees {float} any angle in degrees
 * @return {float} the same direction, 0.0 <= result < 360.0
 */
func normalizeBearing(degrees as float) {
    def turns as float init $degrees / 360.0;
    def wrapped as float init $degrees - 360.0 * convert.toFloat(math.floor($turns));
    if ($wrapped < 0.0 or $wrapped >= 360.0) {
        return 0.0;
    }
    return $wrapped;
}

/**
 * Normalise a longitude into the half-open range -180 to 180 degrees.
 *
 * `destination` can walk a track past the antimeridian, and a longitude of
 * 181 degrees is not something a GPX or KML reader will accept.
 *
 * @param degrees {float} any longitude in degrees
 * @return {float} the same meridian, -180.0 <= result < 180.0
 */
func normalizeLongitude(degrees as float) {
    def wrapped as float init normalizeBearing($degrees + 180.0);
    return $wrapped - 180.0;
}

/**
 * The signed change in longitude from one meridian to another, the short way.
 *
 * Plain subtraction makes 179.5 to -179.5 a 359-degree swing west, when the
 * leg is one degree east across the antimeridian.
 *
 * @param from {float} the starting longitude in degrees
 * @param to2 {float} the ending longitude in degrees
 * @return {float} the change in degrees, -180.0 <= result < 180.0
 */
func longitudeDelta(from as float, to2 as float) {
    return normalizeLongitude($to2 - $from);
}
