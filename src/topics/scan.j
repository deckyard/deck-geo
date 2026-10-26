# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# geo - the element scanner the XML codecs walk a document with.
# Spliced into geo.j via include - not a standalone module.

/**
 * Where one element sits in a buffer.
 *
 * Byte offsets into the buffer the scanner was handed, not rune offsets:
 * `binary.indexOf` works in bytes and scans at native speed, where
 * `strings.indexOf` would have to decode the whole document to count runes.
 *
 * @field name {string} the tag as written, namespace prefix and all
 * @field start {int} the offset of the opening `<`
 * @field end {int} the offset just past the element
 * @field openEnd {int} the offset just past the `>` of the open tag
 * @field innerEnd {int} the offset of the `<` that closes the element
 * @field closed {bool} whether a closing tag was found
 */
def struct Node {
    name as string,
    start as int,
    end as int,
    openEnd as int,
    innerEnd as int,
    closed as bool
};

/** The byte value of `<`. */
def const LT as int init 0x3c;

# The one-byte needles below are what turn the scan from an interpreted loop
# per byte into one `binary.indexOf` per element: `binary` scans at native
# speed, and `bytes` has no literal, so each probe is built once here rather
# than converted on every call.

/** `<` as a one-byte buffer, for `binary.indexOf`. */
def const LT_PROBE as bytes init convert.bytesFromString("<", "utf-8");

/** `>` as a one-byte buffer. */
def const GT_PROBE as bytes init convert.bytesFromString(">", "utf-8");

/** A double quote as a one-byte buffer. */
def const DQUOTE_PROBE as bytes init convert.bytesFromString("\"", "utf-8");

/** A single quote as a one-byte buffer. */
def const SQUOTE_PROBE as bytes init convert.bytesFromString("'", "utf-8");

/** The opening of a CDATA section. */
def const CDATA_PROBE as bytes init convert.bytesFromString("<![CDATA[", "utf-8");

/** An equals sign as a one-byte buffer, for walking attributes. */
def const EQUALS_PROBE as bytes init convert.bytesFromString("=", "utf-8");

/** The byte-order mark some editors put in front of a UTF-8 file. */
def const UTF8_BOM as bytes init convert.bytesFromString("\uFEFF", "utf-8");

/** The opening of an XML declaration. */
def const XML_DECL_PROBE as bytes init convert.bytesFromString("<?xml", "utf-8");

/** The opening of a comment. */
def const COMMENT_PROBE as bytes init convert.bytesFromString("<!--", "utf-8");

/** The byte value of `>`. */
def const GT as int init 0x3e;

/** The byte value of `/`. */
def const SLASH as int init 0x2f;

/** The byte value of `!`. */
def const BANG as int init 0x21;

/** The byte value of `?`. */
def const QUESTION as int init 0x3f;

/**
 * Whether a byte ends an XML name.
 *
 * Whitespace, `>` and `/` are the only things that can follow a tag name, so
 * this is what tells `<trk>` from `<trkseg>` without a regex.
 *
 * @param b {int} the byte to test
 * @return {bool} whether the byte terminates a name
 */
func isNameEnd(b as int) {
    return $b == GT or $b == SLASH or $b == 0x20 or $b == 0x09 or $b == 0x0a or $b == 0x0d;
}

/**
 * The next direct element child at or after an offset.
 *
 * The streaming half of the scanner, and the reason a track log of any size
 * costs the same memory as a short one. {@link childNodes} is the convenient
 * form, but it materialises a list - and a `<trkseg>` has as many children as
 * the track has points, so for 50,000 points that list is the largest thing in
 * the program. A reader that only ever holds one child at a time walks the same
 * document in a fraction of the memory.
 *
 * Comments, processing instructions, `DOCTYPE` declarations and CDATA sections
 * are skipped.
 *
 * @param src {bytes} the whole document
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {Node} the next child, or a node with `start` `-1` when there is none
 * @example
 *   def at as int init $node.openEnd;
 *   def child as Node init nextChild($src, $at, $node.innerEnd);
 *   while (isNode($child)) {
 *       $child = nextChild($src, $child.end, $node.innerEnd);
 *   }
 */
func nextChild(src as bytes, from as int, limit as int) {
    def at as int init $from;
    while ($at < $limit) {
        def lt as int init indexOfByte($src, LT_PROBE, $at, $limit);
        if ($lt < 0) {
            return missingNode();
        }
        def skip as int init skipNonElement($src, $lt, $limit);
        if ($skip >= 0) {
            $at = $skip;
        } else {
            def node as Node init readNode($src, $lt, $limit);
            if ($node.start < 0) {
                return missingNode();
            }
            return $node;
        }
    }
    return missingNode();
}

/**
 * The direct element children of a byte range, as a list.
 *
 * Convenient where the count is small and known to be - a document's header, a
 * waypoint's fields. For the children of a `<trkseg>` or a KML `<Folder>`,
 * which can number in the tens of thousands, walk them with
 * {@link nextChild} instead.
 *
 * @param src {bytes} the whole document
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {list of Node} the direct children, in document order
 */
func childNodes(src as bytes, from as int, limit as int) {
    def out as list of Node init [];
    def child as Node init nextChild($src, $from, $limit);
    while (isNode($child)) {
        $out[] = $child;
        $child = nextChild($src, $child.end, $limit);
    }
    return $out;
}

/**
 * A node that points at nothing.
 *
 * @return {Node} a node whose `start` is `-1`
 */
func missingNode() {
    return Node{name: "", start: -1, end: 0, openEnd: 0, innerEnd: 0, closed: false};
}

/**
 * Step over a comment, processing instruction, DOCTYPE, CDATA or close tag.
 *
 * @param src {bytes} the whole document
 * @param lt {int} the offset of a `<`
 * @param limit {int} the offset to stop at
 * @return {int} where to resume, or `-1` when the `<` opens an element
 */
func skipNonElement(src as bytes, lt as int, limit as int) {
    if ($lt + 1 >= $limit) {
        return $limit;
    }
    def next as int init $src[$lt + 1];
    if ($next == SLASH) {
        return skipPast($src, $lt, ">", $limit);
    }
    if ($next == QUESTION) {
        return skipPast($src, $lt, "?>", $limit);
    }
    if ($next != BANG) {
        return -1;
    }
    if (matchesAt($src, $lt, CDATA_PROBE)) {
        return skipPast($src, $lt, "]]>", $limit);
    }
    if (matchesAt($src, $lt, COMMENT_PROBE)) {
        return skipPast($src, $lt, "-->", $limit);
    }
    return skipPast($src, $lt, ">", $limit);
}

/**
 * Read the element that starts at a `<`.
 *
 * An element with no closing tag is taken to run to `limit` rather than being
 * discarded, so a truncated document yields what it did manage to write. An
 * element whose *open tag* is truncated carries no usable name or attributes,
 * and comes back as a missing node.
 *
 * @param src {bytes} the whole document
 * @param lt {int} the offset of the opening `<`
 * @param limit {int} the offset to stop at
 * @return {Node} the element, or a node with `start` `-1` when its open tag is unterminated
 */
func readNode(src as bytes, lt as int, limit as int) {
    def nameEnd as int init $lt + 1;
    while ($nameEnd < $limit and not isNameEnd($src[$nameEnd])) {
        $nameEnd = $nameEnd + 1;
    }
    def name as string init byteText($src, $lt + 1, $nameEnd);
    def openEnd as int init endOfOpenTag($src, $nameEnd, $limit);
    if ($openEnd < 0) {
        return Node{
            name: $name,
            start: -1,
            end: $limit,
            openEnd: $limit,
            innerEnd: $limit,
            closed: false
        };
    }
    if ($src[$openEnd - 2] == SLASH) {
        # <wpt ... /> - no content, so the element ends where its open tag does
        return Node{
            name: $name,
            start: $lt,
            end: $openEnd,
            openEnd: $openEnd,
            innerEnd: $openEnd - 2,
            closed: true
        };
    }
    def innerEnd as int init matchingClose($src, $name, $openEnd, $limit);
    if ($innerEnd < 0) {
        # No closing tag: a file whose write was cut short - a recorder that
        # lost power mid-track. The element is taken to run to the end of what
        # there is, so the points before the damage still read back. Only a
        # truncated *open tag*, below, is unusable.
        return Node{
            name: $name,
            start: $lt,
            end: $limit,
            openEnd: $openEnd,
            innerEnd: $limit,
            closed: false
        };
    }
    def closeLen as int init len($name) + 3;
    return Node{
        name: $name,
        start: $lt,
        end: $innerEnd + $closeLen,
        openEnd: $openEnd,
        innerEnd: $innerEnd,
        closed: true
    };
}

/**
 * The offset just past the `>` that ends an open tag.
 *
 * Quoted attribute values are stepped over, so a `>` inside one does not end
 * the tag. Driven by native searches for `>` and for the quotes, so the cost
 * is one hop per quoted attribute rather than one step per byte.
 *
 * @param src {bytes} the whole document
 * @param from {int} the offset just past the tag name
 * @param limit {int} the offset to stop at
 * @return {int} the offset just past the `>`, or `-1` when there is none
 */
func endOfOpenTag(src as bytes, from as int, limit as int) {
    def at as int init $from;
    while ($at < $limit) {
        def gt as int init indexOfByte($src, GT_PROBE, $at, $limit);
        if ($gt < 0) {
            return -1;
        }
        def quote as int init nextQuote($src, $at, $gt);
        if ($quote < 0) {
            return $gt + 1;
        }
        # The `>` is inside an attribute value; resume past the closing quote.
        # Both branches pass the probe constant straight to indexOfByte: binding
        # a `def const` of a compound type to a local deep-copies it, and this
        # runs twice per element.
        def close as int init closingQuote($src, $quote, $limit);
        if ($close < 0) {
            return -1;
        }
        $at = $close + 1;
    }
    return -1;
}

/**
 * The offset of the quote that closes the one at an offset.
 *
 * @param src {bytes} the buffer to search
 * @param quote {int} the offset of the opening quote
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the closing quote, or `-1` when there is none
 */
func closingQuote(src as bytes, quote as int, limit as int) {
    if ($src[$quote] == 0x22) {
        return indexOfByte($src, DQUOTE_PROBE, $quote + 1, $limit);
    }
    return indexOfByte($src, SQUOTE_PROBE, $quote + 1, $limit);
}

/**
 * The offset of the first quote character before a limit.
 *
 * @param src {bytes} the buffer to search
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the nearer quote, or `-1` when there is none
 */
func nextQuote(src as bytes, from as int, limit as int) {
    def double as int init indexOfByte($src, DQUOTE_PROBE, $from, $limit);
    def single as int init indexOfByte($src, SQUOTE_PROBE, $from, $limit);
    if ($double < 0) {
        return $single;
    }
    if ($single < 0) {
        return $double;
    }
    return math.min($double, $single);
}

/**
 * The offset of the `</name>` that closes an element, counting nesting.
 *
 * @param src {bytes} the whole document
 * @param name {string} the tag as written
 * @param from {int} the offset just past the open tag
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the closing `<`, or `-1` when it is missing
 */
func matchingClose(src as bytes, name as string, from as int, limit as int) {
    def openProbe as bytes init probeOf("<" + $name);
    def closeProbe as bytes init probeOf("</" + $name);
    def close as int init closeTagAt($src, $closeProbe, $from, $limit);
    if ($close < 0) {
        return -1;
    }
    # The common case by far: no element of the same name opens inside this
    # one, so the first close tag is the matching one and the whole search was
    # two native scans. Only a nested name - a KML <Folder> inside a
    # <Folder> - pays for the walk below.
    #
    # The boundary test is what makes this pay: `<trk` occurs inside every one
    # of a track's `<trkpt>`s, so a bare substring search would send every GPX
    # track down the slow path.
    def nested as int init openTagAt($src, $openProbe, $from, $close);
    if ($nested < 0) {
        return $close;
    }
    return nestedClose($src, $openProbe, $closeProbe, $from, $limit);
}

/**
 * The offset of the next close tag whose name is followed by its `>`.
 *
 * @param src {bytes} the whole document
 * @param closeProbe {bytes} `</` plus the tag name, as bytes
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the `<`, or `-1` when there is none
 */
func closeTagAt(src as bytes, closeProbe as bytes, from as int, limit as int) {
    def at as int init $from;
    while ($at < $limit) {
        def found as int init indexOfByte($src, $closeProbe, $at, $limit);
        if ($found < 0) {
            return -1;
        }
        if (isCloseEnd($src, $found + len($closeProbe), $limit)) {
            return $found;
        }
        $at = $found + 1;
    }
    return -1;
}

/**
 * The offset of the next open tag whose name ends where the probe does.
 *
 * @param src {bytes} the whole document
 * @param openProbe {bytes} `<` plus the tag name, as bytes
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the `<`, or `-1` when there is none
 */
func openTagAt(src as bytes, openProbe as bytes, from as int, limit as int) {
    def at as int init $from;
    while ($at < $limit) {
        def found as int init indexOfByte($src, $openProbe, $at, $limit);
        if ($found < 0) {
            return -1;
        }
        def after as int init $found + len($openProbe);
        if ($after >= $limit or isNameEnd($src[$after])) {
            return $found;
        }
        $at = $found + 1;
    }
    return -1;
}

/**
 * The matching close tag of an element that nests its own name.
 *
 * @param src {bytes} the whole document
 * @param openProbe {bytes} `<` plus the tag name, as bytes
 * @param closeProbe {bytes} `</` plus the tag name, as bytes
 * @param from {int} the offset just past the open tag
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the closing `<`, or `-1` when it is missing
 */
func nestedClose(src as bytes, openProbe as bytes, closeProbe as bytes, from as int, limit as int) {
    def depth as int init 1;
    def at as int init $from;
    while ($at < $limit) {
        def lt as int init indexOfByte($src, LT_PROBE, $at, $limit);
        if ($lt < 0) {
            return -1;
        }
        $depth = $depth + depthChange($src, $lt, $openProbe, $closeProbe, $limit);
        if ($depth == 0) {
            return $lt;
        }
        $at = $lt + 1;
    }
    return -1;
}

/**
 * What one `<` does to the nesting depth of a named element.
 *
 * @param src {bytes} the whole document
 * @param lt {int} the offset of the `<`
 * @param openProbe {bytes} `<` plus the tag name, as bytes
 * @param closeProbe {bytes} `</` plus the tag name, as bytes
 * @param limit {int} the offset to stop at
 * @return {int} `1` for a nested open tag, `-1` for a close tag, `0` otherwise
 */
func depthChange(src as bytes, lt as int, openProbe as bytes, closeProbe as bytes, limit as int) {
    if (matchesAt($src, $lt, $closeProbe) and isCloseEnd($src, $lt + len($closeProbe), $limit)) {
        return -1;
    }
    if (not matchesAt($src, $lt, $openProbe)) {
        return 0;
    }
    def after as int init $lt + len($openProbe);
    if ($after < $limit and not isNameEnd($src[$after])) {
        return 0;
    }
    def openEnd as int init endOfOpenTag($src, $after, $limit);
    if ($openEnd > 1 and $src[$openEnd - 2] == SLASH) {
        return 0;
    }
    return 1;
}

/**
 * Whether a close tag's name is followed by its `>`.
 *
 * @param src {bytes} the whole document
 * @param at {int} the offset just past the name in a `</name` sequence
 * @param limit {int} the offset to stop at
 * @return {bool} whether only whitespace stands between `at` and a `>`
 */
func isCloseEnd(src as bytes, at as int, limit as int) {
    def i as int init $at;
    while ($i < $limit and
        ($src[$i] == 0x20 or $src[$i] == 0x09 or $src[$i] == 0x0a or $src[$i] == 0x0d)) {
        $i = $i + 1;
    }
    return $i < $limit and $src[$i] == GT;
}

/**
 * The offset of the next occurrence of a probe, inside a range.
 *
 * `binary.indexOf` searches to the end of the buffer and has no limit
 * argument, so the limit is applied to its answer.
 *
 * @param src {bytes} the buffer to search
 * @param probe {bytes} the bytes to find
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {int} the offset, or `-1` when the probe is not in the range
 */
func indexOfByte(src as bytes, probe as bytes, from as int, limit as int) {
    if ($from < 0 or $from >= $limit) {
        return -1;
    }
    # The limit goes to the native search too: without it a miss scans to the
    # end of the buffer, so a hostile file with a long tail made every tag cost
    # the rest of the file.
    return binary.indexOf($src, $probe, $from, math.min($limit, len($src)));
}

/**
 * Whether a probe stands at an offset.
 *
 * One native slice and one value comparison, rather than a loop per byte. The
 * probe is `bytes` so a caller in a loop converts it once, outside.
 *
 * @param src {bytes} the buffer to test
 * @param at {int} the offset to test at
 * @param probe {bytes} the bytes to look for
 * @return {bool} whether they are there
 */
func matchesAt(src as bytes, at as int, probe as bytes) {
    def size as int init len($probe);
    if ($at < 0 or $at + $size > len($src)) {
        return false;
    }
    return binary.slice($src, $at, $at + $size) == $probe;
}

/**
 * The offset just past the next occurrence of a literal.
 *
 * @param src {bytes} the buffer to search
 * @param from {int} the offset to start at
 * @param literal {string} the ASCII literal to find
 * @param limit {int} the offset to stop at
 * @return {int} the offset just past it, or `limit` when it is not there
 */
func skipPast(src as bytes, from as int, literal as string, limit as int) {
    def needle as bytes init convert.bytesFromString($literal, "utf-8");
    def found as int init indexOfByte($src, $needle, $from, $limit);
    if ($found < 0 or $found + len($needle) > $limit) {
        return $limit;
    }
    return $found + len($needle);
}

/**
 * One ASCII literal as a byte probe.
 *
 * @param literal {string} the literal to convert
 * @return {bytes} its UTF-8 bytes
 */
func probeOf(literal as string) {
    return convert.bytesFromString($literal, "utf-8");
}

/**
 * A byte range as text.
 *
 * @param src {bytes} the buffer to read from
 * @param from {int} the first offset
 * @param limit {int} the offset to stop at
 * @return {string} the range, decoded as UTF-8
 * @throws {Error} when the range is not valid UTF-8
 */
func byteText(src as bytes, from as int, limit as int) {
    if ($limit <= $from) {
        return "";
    }
    def out as string init "";
    try {
        $out = convert.stringFromBytes(binary.slice($src, $from, $limit), "utf-8");
    } catch (e) {
        fail("the document is not valid UTF-8 at byte " + convert.toString($from) +
            ", and declares no other encoding");
    }
    return $out;
}

/**
 * A file's raw bytes, transcoded to UTF-8 when its XML declaration names a
 * single-byte encoding.
 *
 * Older Garmin and GIS exports write `encoding="ISO-8859-1"` or
 * `windows-1252`, and the scanner reads UTF-8 only. Only raw file bytes come
 * through here: a `string` handed to `readGpx` is already decoded, and
 * transcoding it again by its declaration would garble every accented letter.
 *
 * @param src {bytes} the file as read from disk or out of a KMZ
 * @return {bytes} the same document as UTF-8
 * @throws {Error} when the file is UTF-16, or declares an encoding with no codec
 */
func toUtf8(src as bytes) {
    if (len($src) >= 2) {
        def first as int init $src[0];
        def second as int init $src[1];
        if (($first == 0xff and $second == 0xfe) or ($first == 0xfe and $second == 0xff) or
            ($first == LT and $second == 0) or ($first == 0 and $second == LT)) {
            fail("the document is UTF-16, which this deck does not read; save it as UTF-8");
        }
    }
    def codec as string init declaredEncoding($src);
    if ($codec == "") {
        return $src;
    }
    def text as string init "";
    try {
        $text = encoding.decode($src, $codec);
    } catch (e) {
        fail("the document is in " + quoted($codec) + ", an encoding this deck does not read");
    }
    return convert.bytesFromString($text, "utf-8");
}

/**
 * The codec an XML declaration names, when it is not UTF-8.
 *
 * @param src {bytes} the document
 * @return {string} an `encoding` codec name, or `""` for UTF-8, ASCII or no declaration
 */
func declaredEncoding(src as bytes) {
    def at as int init 0;
    if (matchesAt($src, 0, UTF8_BOM)) {
        $at = 3;
    }
    if (not matchesAt($src, $at, XML_DECL_PROBE)) {
        return "";
    }
    def end as int init indexOfByte($src, GT_PROBE, $at, math.min(len($src), $at + 256));
    if ($end < 0) {
        return "";
    }
    def decl as string init "";
    try {
        $decl = strings.lower(convert.stringFromBytes(binary.slice($src, $at, $end), "utf-8"));
    } catch (e) {
        return "";
    }
    def key as int init strings.indexOf($decl, "encoding");
    if ($key < 0) {
        return "";
    }
    def rest as string init strings.trimLeft(strings.substring($decl, $key + 8, len($decl)));
    if (not strings.startsWith($rest, "=")) {
        return "";
    }
    $rest = strings.trimLeft(strings.substring($rest, 1, len($rest)));
    if (len($rest) < 2) {
        return "";
    }
    def quote as string init strings.substring($rest, 0, 1);
    def close as int init strings.indexOf(strings.substring($rest, 1, len($rest)), $quote);
    if ($close < 0) {
        return "";
    }
    return codecFor(strings.trim(strings.substring($rest, 1, $close + 1)));
}

/**
 * The `encoding` codec for the name an XML declaration uses.
 *
 * @param name {string} the declared name, lower-cased
 * @return {string} the codec, or `""` when the document is already UTF-8
 */
func codecFor(name as string) {
    match ($name) {
        when "", "utf-8", "utf8", "us-ascii", "ascii" { return ""; }
        when "latin1", "latin-1", "l1", "iso8859-1", "iso_8859-1", "iso-latin-1" {
            return "iso-8859-1";
        }
        when "cp1252", "x-cp1252" { return "windows-1252"; }
        else { return $name; }
    }
}

/**
 * One element, as a standalone XML document.
 *
 * Not used by the codecs, which read leaves in place. It is how a fragment
 * becomes reportable: an error message, or a test, can quote the element it is
 * about without the caller tracking offsets.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the element to cut out
 * @return {string} the element and everything inside it
 */
func fragment(src as bytes, node as Node) {
    return byteText($src, $node.start, $node.end);
}

/**
 * The text content of an element, entities resolved.
 *
 * Only the element's own character data, not that of its children, which is
 * what every leaf in GPX, KML and GML needs.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the element to read
 * @return {string} the text, trimmed, with entity references resolved
 */
func nodeText(src as bytes, node as Node) {
    def raw as string init byteText($src, $node.openEnd, $node.innerEnd);
    if (strings.indexOf($raw, "<![CDATA[") >= 0) {
        return strings.trim(cdataText($raw));
    }
    if (strings.indexOf($raw, "<") >= 0) {
        return strings.trim(xmlUnescape(textOnly($raw)));
    }
    return strings.trim(xmlUnescape($raw));
}

/**
 * A run of character data that holds CDATA sections, as text.
 *
 * Each section's content is kept verbatim, and the text between and around
 * the sections is read as any other text: `Rock <![CDATA[&]]> Roll` is
 * `Rock & Roll`, not `&`.
 *
 * @param raw {string} the element's content as written
 * @return {string} the content, sections verbatim and the rest unescaped
 */
func cdataText(raw as string) {
    def parts as list of string init strings.split($raw, "<![CDATA[");
    def out as list of string init [plainText($parts[0])];
    for (def i as int init 1; $i < len($parts); $i = $i + 1) {
        def part as string init $parts[$i];
        def close as int init strings.indexOf($part, "]]>");
        if ($close < 0) {
            $out[] = $part;
        } else {
            $out[] = strings.substring($part, 0, $close);
            $out[] = plainText(strings.substring($part, $close + 3, len($part)));
        }
    }
    return strings.join($out, "");
}

/**
 * Character data outside any CDATA section, as the reader sees it.
 *
 * @param raw {string} the text as written
 * @return {string} the text with markup dropped and entities resolved
 */
func plainText(raw as string) {
    if (strings.indexOf($raw, "<") >= 0) {
        return xmlUnescape(textOnly($raw));
    }
    return xmlUnescape($raw);
}

/**
 * Character data with every tag dropped.
 *
 * A `<name>` that carries markup is not something this deck models, so the
 * markup is dropped and the words are kept.
 *
 * @param raw {string} the element's content as written
 * @return {string} the content with every tag and comment removed; a `>`
 *   outside a tag is text and is kept
 */
func textOnly(raw as string) {
    def out as list of string init [];
    def rest as string init $raw;
    def open as int init strings.indexOf($rest, "<");
    while ($open >= 0) {
        $out[] = strings.substring($rest, 0, $open);
        $rest = strings.substring($rest, $open, len($rest));
        # A comment ends at -->, not at the first > inside it.
        def closer as string init ">";
        if (strings.startsWith($rest, "<!--")) {
            $closer = "-->";
        }
        def close as int init strings.indexOf($rest, $closer);
        if ($close < 0) {
            return strings.join($out, "");
        }
        $rest = strings.substring($rest, $close + len($closer), len($rest));
        $open = strings.indexOf($rest, "<");
    }
    $out[] = $rest;
    return strings.join($out, "");
}

/**
 * An attribute of an element, entities resolved.
 *
 * Read straight out of the open tag's bytes, with native searches: a track
 * point's latitude costs no decode of the element and no per-character walk of
 * its tag. Matched on the attribute's local part, so `gpx:lat` answers to
 * `lat`, and tolerant of whitespace around the equals sign, which is legal XML.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the element to read
 * @param name {string} the attribute to read, matched on its local part
 * @return {string} the value, or `""` when the attribute is absent
 */
func nodeAttr(src as bytes, node as Node, name as string) {
    def limit as int init $node.openEnd;
    def at as int init $node.start + 1;
    # Walked one name=value pair at a time, stepping over each value whole.
    # Searching the tag for the name instead found it inside other values:
    # gml:id="a srsName=CRS:84" answered for srsName and swapped the axes.
    while ($at < $limit) {
        def eq as int init indexOfByte($src, EQUALS_PROBE, $at, $limit);
        if ($eq < 0) {
            return "";
        }
        if (localName(lastWord(byteText($src, $at, $eq))) == $name) {
            return attrValueAt($src, $eq + 1, $limit);
        }
        $at = attrValueEnd($src, $eq + 1, $limit);
    }
    return "";
}

/**
 * The last whitespace-separated word of a run of text.
 *
 * @param text {string} the text before an equals sign: a tag name, an earlier
 *   value's closing space, the attribute name
 * @return {string} the attribute name
 */
func lastWord(text as string) {
    def words as list of string init strings.split(strings.trim($text), " ");
    def word as string init $words[len($words) - 1];
    for (def sep in ["\n", "\t", "\r"]) {
        def pieces as list of string init strings.split($word, $sep);
        $word = $pieces[len($pieces) - 1];
    }
    return $word;
}

/**
 * The offset just past an attribute value, from just past its equals sign.
 *
 * @param src {bytes} the whole document
 * @param from {int} the offset just past the equals sign
 * @param limit {int} the offset to stop at
 * @return {int} the offset after the value, always past `from`
 */
func attrValueEnd(src as bytes, from as int, limit as int) {
    def at as int init skipSpaceBytes($src, $from, $limit);
    if ($at >= $limit) {
        return $limit;
    }
    def opener as int init $src[$at];
    if ($opener == 0x22 or $opener == 0x27) {
        def close as int init closingQuote($src, $at, $limit);
        if ($close < 0) {
            return $limit;
        }
        return $close + 1;
    }
    def end as int init $at + 1;
    while ($end < $limit and not isNameEnd($src[$end])) {
        $end = $end + 1;
    }
    return $end;
}

/**
 * The offset of the first byte that is not XML whitespace.
 *
 * @param src {bytes} the whole document
 * @param from {int} the offset to start at
 * @param limit {int} the offset to stop at
 * @return {int} the offset of the first non-space byte, or `limit`
 */
func skipSpaceBytes(src as bytes, from as int, limit as int) {
    def at as int init $from;
    while ($at < $limit and isSpaceByte($src[$at])) {
        $at = $at + 1;
    }
    return $at;
}

/**
 * Whether a byte is XML whitespace.
 *
 * @param b {int} the byte to test
 * @return {bool} whether it is a space, tab, newline or carriage return
 */
func isSpaceByte(b as int) {
    return $b == 0x20 or $b == 0x09 or $b == 0x0a or $b == 0x0d;
}

/**
 * An attribute value, from just past its equals sign.
 *
 * Quoted with either quote, or unquoted - which is not well-formed XML, but
 * turns up in hand-edited files and costs nothing to accept.
 *
 * @param src {bytes} the whole document
 * @param from {int} the offset just past the equals sign
 * @param limit {int} the offset to stop at
 * @return {string} the value, with entity references resolved
 */
func attrValueAt(src as bytes, from as int, limit as int) {
    def at as int init skipSpaceBytes($src, $from, $limit);
    if ($at >= $limit) {
        return "";
    }
    def opener as int init $src[$at];
    if ($opener == 0x22 or $opener == 0x27) {
        def close as int init closingQuote($src, $at, $limit);
        if ($close < 0) {
            return "";
        }
        return xmlUnescape(byteText($src, $at + 1, $close));
    }
    def end as int init $at;
    while ($end < $limit and not isNameEnd($src[$end])) {
        $end = $end + 1;
    }
    return xmlUnescape(byteText($src, $at, $end));
}

/**
 * Whether a character is XML whitespace.
 *
 * @param ch {string} a single character
 * @return {bool} whether it is a space, tab, newline or carriage return
 */
func isSpace(ch as string) {
    return $ch == " " or $ch == "\t" or $ch == "\n" or $ch == "\r";
}

/**
 * The first direct child with a local name, or a node with `start` `-1`.
 *
 * @param nodes {list of Node} the children to search
 * @param name {string} the local name to match
 * @return {Node} the child, or a missing node
 */
func findChild(nodes as list of Node, name as string) {
    for (def node in $nodes) {
        if (localName($node.name) == $name) {
            return $node;
        }
    }
    return missingNode();
}

/**
 * Every direct child with a local name.
 *
 * @param nodes {list of Node} the children to filter
 * @param name {string} the local name to match
 * @return {list of Node} the matching children, in document order
 */
func findChildren(nodes as list of Node, name as string) {
    def out as list of Node init [];
    for (def node in $nodes) {
        if (localName($node.name) == $name) {
            $out[] = $node;
        }
    }
    return $out;
}

/**
 * Whether a node was found.
 *
 * @param node {Node} the node to test
 * @return {bool} whether it points at an element
 */
func isNode(node as Node) {
    return $node.start >= 0;
}

/**
 * The text of a named child, or `""` when there is no such child.
 *
 * @param src {bytes} the whole document
 * @param nodes {list of Node} the children to search
 * @param name {string} the local name to match
 * @return {string} the child's text, or `""`
 */
func childText(src as bytes, nodes as list of Node, name as string) {
    def node as Node init findChild($nodes, $name);
    if (not isNode($node)) {
        return "";
    }
    return nodeText($src, $node);
}

/**
 * One element, decoded into a tree of its own.
 *
 * The other half of the strategy. Walking a leaf element's fields with the
 * scanner means an interpreted step per child; handing the fragment to
 * `xml.decode` is a native parse, and measurably the faster of the two - at the
 * same memory, because the tree that exists at any moment covers one track
 * point rather than the whole document.
 *
 * Use it for an element whose fields are wanted - a `<trkpt>`, a `<wpt>`. Do
 * not use it for a container: decoding a `<trk>` is decoding the whole file,
 * which is the thing this deck exists to avoid.
 *
 * A fragment cut out of the document has lost the `xmlns` declarations above
 * it, and `xml` rejects a prefix with no declaration in scope. `ns` puts the
 * root's bindings back (`namespaceBindings`), which covers every real file:
 * GPX declares its extension prefixes, `gpxtpx:` and the like, on the root. A
 * file that uses a prefix it never declares is damage, read anyway: the
 * fragment is decoded a second time with every prefix it uses bound to a
 * stand-in URI. Leaves are matched on their local part, so the URI is never
 * looked at, and well-formed files never pay for the second decode.
 *
 * @param src {bytes} the whole document
 * @param node {Node} the element to decode
 * @param ns {map of string to string} the root's namespace bindings, prefix to URI
 * @return {xml.Value} the element as a tree
 * @throws {Error} when the fragment is not well-formed XML
 */
func decodeLeaf(src as bytes, node as Node, ns as map of string to string) {
    def text as string init fragment($src, $node);
    try {
        return xml.decode($text, $ns);
    } catch (e) { # lint-disable: L103
        # An undeclared prefix, most likely; retried below with stand-ins.
    }
    def tree as xml.Value init xml.element("empty");
    try {
        $tree = xml.decode($text, withStandIns($text, $ns));
    } catch (e) {
        fail("<" + $node.name + "> is not well-formed: " + $e.message);
    }
    return $tree;
}

/** Where a stand-in namespace URI for an undeclared prefix starts. */
def const STAND_IN_NAMESPACE as string init "urn:x-deckyard-geo:undeclared:";

/** A prefix in front of an element or attribute name: `<gpx:`, ` gpx:`, `/gpx:`. */
def const PREFIX_PATTERN as string init '(?:^|[<\s/])([A-Za-z_][A-Za-z0-9._-]*):[A-Za-z_]';

/**
 * The bindings `ns` plus a stand-in URI for every other prefix `text` uses.
 *
 * Only the retry after a failed decode calls it, so its regex pass costs
 * nothing on a well-formed file.
 *
 * @param text {string} the fragment
 * @param ns {map of string to string} the bindings already known
 * @return {map of string to string} `ns` with a binding for each prefix in `text`
 */
func withStandIns(text as string, ns as map of string to string) {
    def out as map of string to string init $ns;
    for (def m in regex.findAll(PREFIX_PATTERN, $text)) {
        def prefix as string init $m.groups[0];
        if ($prefix != "xml" and $prefix != "xmlns" and not hasKey($out, $prefix)) {
            $out[$prefix] = STAND_IN_NAMESPACE + $prefix;
        }
    }
    return $out;
}

/**
 * Whether a map holds a key. A namespace map holds a handful of prefixes, so
 * a walk is as cheap as a lookup and keeps the deck off another library.
 *
 * @param m {map of string to string} the map
 * @param key {string} the key to look for
 * @return {bool} true when `m` has `key`
 */
func hasKey(m as map of string to string, key as string) {
    for (def k in $m) {
        if ($k == $key) {
            return true;
        }
    }
    return false;
}

/**
 * The namespace declarations on the root element, prefix to URI.
 *
 * Read once per document and handed to `decodeLeaf`, so each leaf decodes
 * against the bindings its cut-out text no longer carries. The default
 * namespace is under `""`. A root that does not parse on its own yields no
 * bindings; the leaves then fall back to stand-ins.
 *
 * @param src {bytes} the whole document
 * @param root {Node} the root element
 * @return {map of string to string} the root's `xmlns` bindings
 */
func namespaceBindings(src as bytes, root as Node) {
    def out as map of string to string init {};
    def open as string init byteText($src, $root.start, $root.openEnd);
    if (not strings.endsWith($open, "/>")) {
        $open = $open[..len($open) - 1] + "/>";
    }
    def tag as xml.Value init xml.element("empty");
    try {
        $tag = xml.decode($open, withStandIns($open, {}));
    } catch (e) {
        return $out;
    }
    for (def name in xml.attrs($tag)) {
        if ($name == "xmlns") {
            $out[""] = xml.attr($tag, $name);
        } elseif (strings.startsWith($name, "xmlns:")) {
            $out[$name[6..]] = xml.attr($tag, $name);
        }
    }
    return $out;
}

/**
 * An attribute of a decoded element, matched on its local part.
 *
 * `xml.attr` reads an attribute by its name as written, so a document written
 * `<gpx:trkpt gpx:lat="...">` would not answer to `lat`. The unprefixed case is
 * tried directly - one native lookup - and the prefixed one falls back to a
 * walk of the attribute names, which works whatever the prefix's namespace
 * (`xml.attrNS` would need the URI, and files differ in which one they use).
 *
 * @param element {xml.Value} the decoded element
 * @param name {string} the attribute to read, matched on its local part
 * @return {string} the value, or `""` when the attribute is absent
 */
func leafAttr(element as xml.Value, name as string) {
    if (xml.hasAttr($element, $name)) {
        return xml.attr($element, $name);
    }
    for (def written in xml.attrs($element)) {
        if (localName($written) == $name) {
            return xml.attr($element, $written);
        }
    }
    return "";
}

/**
 * The text of a decoded element's child, matched on its local part.
 *
 * @param element {xml.Value} the decoded element
 * @param name {string} the child to read, matched on its local part
 * @return {string} the child's text, or `""` when there is no such child
 */
func leafText(element as xml.Value, name as string) {
    for (def child in xml.children($element)) {
        if (localName(xml.tag($child)) == $name) {
            return strings.trim(xml.text($child));
        }
    }
    return "";
}

/**
 * Whether a decoded element has a child with a local name.
 *
 * Told apart from a child whose text is empty. That distinction is what lets
 * `<ele>0</ele>` mean sea level and a missing `<ele>` mean nothing was stated.
 *
 * @param element {xml.Value} the decoded element
 * @param name {string} the child to look for, matched on its local part
 * @return {bool} whether the child is there
 */
func hasLeafChild(element as xml.Value, name as string) {
    for (def child in xml.children($element)) {
        if (localName(xml.tag($child)) == $name) {
            return true;
        }
    }
    return false;
}

/**
 * The root element of a document.
 *
 * @param src {bytes} the whole document
 * @return {Node} the root
 * @throws {Error} when the buffer holds no element
 */
func rootNode(src as bytes) {
    def top as list of Node init childNodes($src, 0, len($src));
    if (len($top) == 0) {
        fail("no XML element in the document");
    }
    return $top[0];
}
