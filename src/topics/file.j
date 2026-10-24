# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# geo - whole files, and the format dispatch over them.
# Spliced into geo.j via include - not a standalone module.

/** The format name {@link formatOf} returns for a file it does not recognise. */
export def const FORMAT_UNKNOWN as string init "";

/**
 * Which format a path names, from its extension, ignoring case.
 *
 * @param target {string} the path or filename
 * @return {string} `"gpx"`, `"kml"`, `"kmz"`, `"geojson"`, `"gml"`, or `FORMAT_UNKNOWN`
 * @example
 *   geo.formatOf("hike.GPX");        # "gpx"
 *   geo.formatOf("places.geojson");  # "geojson"
 */
export func formatOf(target as string) {
    def ext as string init strings.lower(path.ext($target));
    if ($ext == ".gpx") {
        return "gpx";
    }
    if ($ext == ".kml") {
        return "kml";
    }
    if ($ext == ".kmz") {
        return "kmz";
    }
    if ($ext == ".geojson" or $ext == ".json") {
        return "geojson";
    }
    if ($ext == ".gml" or $ext == ".xml") {
        return "gml";
    }
    return FORMAT_UNKNOWN;
}

/**
 * Read a file, in whichever format its extension names.
 *
 * XML formats honour a single-byte `encoding` in the declaration; GeoJSON is
 * read as UTF-8.
 *
 * @param target {string} the path to read
 * @return {Document} what the file held
 * @throws {Error} when the extension names no format, or the file does not parse
 * @example
 *   def doc as geo.Document init geo.open("hike.gpx");
 *   geo.save($doc, "hike.kml");
 */
export func open(target as string) {
    def format as string init formatOf($target);
    if ($format == FORMAT_UNKNOWN) {
        fail("no format for \"" + path.base($target) + "\": expected .gpx, .kml, " +
            ".kmz, .geojson or .gml");
    }
    if ($format == "kmz") {
        return readKmz(readFileBytes($target));
    }
    if ($format == "geojson") {
        # RFC 7946 is UTF-8 only, so there is no declaration to honour.
        def raw as bytes init readFileBytes($target);
        return readGeojson(byteText($raw, 0, len($raw)));
    }
    def src as bytes init toUtf8(readFileBytes($target));
    if ($format == "gpx") {
        return readGpxBytes($src);
    }
    if ($format == "kml") {
        return readKmlBytes($src);
    }
    return readGmlBytes($src);
}

/**
 * Write a document to a file, in whichever format its extension names.
 *
 * @param doc {Document} what to write
 * @param target {string} the path to write
 * @throws {Error} when the extension names no format, or the write fails
 * @example
 *   geo.save($doc, "out.kmz");
 */
export func save(doc as Document, target as string) {
    def format as string init formatOf($target);
    if ($format == FORMAT_UNKNOWN) {
        fail("no format for \"" + path.base($target) + "\": expected .gpx, .kml, " +
            ".kmz, .geojson or .gml");
    }
    if ($format == "kmz") {
        writeFileBytes($target, writeKmz($doc));
        return;
    }
    writeFileText($target, writeText($doc, $format));
}

/**
 * Render a document in a named format.
 *
 * Text formats only; a KMZ is bytes, see {@link writeKmz}.
 *
 * @param doc {Document} what to write
 * @param format {string} `"gpx"`, `"kml"`, `"geojson"` or `"gml"`
 * @return {string} the document
 * @throws {Error} when the format is not one of the four
 * @example
 *   io.printf("%s", geo.writeText($doc, "geojson"));
 */
export func writeText(doc as Document, format as string) {
    if ($format == "gpx") {
        return writeGpx($doc);
    }
    if ($format == "kml") {
        return writeKml($doc);
    }
    if ($format == "geojson") {
        return writeGeojson($doc);
    }
    if ($format == "gml") {
        return writeGml($doc);
    }
    fail("\"" + $format + "\" is not a text format this deck writes");
    return "";
}

/**
 * Parse a document from text in a named format.
 *
 * @param text {string} the document
 * @param format {string} `"gpx"`, `"kml"`, `"geojson"` or `"gml"`
 * @return {Document} what it held
 * @throws {Error} when the format is not one of the four, or the text does not parse
 */
export func readText(text as string, format as string) {
    if ($format == "gpx") {
        return readGpx($text);
    }
    if ($format == "kml") {
        return readKml($text);
    }
    if ($format == "geojson") {
        return readGeojson($text);
    }
    if ($format == "gml") {
        return readGml($text);
    }
    fail("\"" + $format + "\" is not a text format this deck reads");
    return document();
}

/**
 * Read a GPX file.
 *
 * Read as bytes and scanned directly, so a large file is never held as a
 * decoded string as well as a buffer. The extension is not checked.
 *
 * @param target {string} the path to read
 * @return {Document} what the file held
 * @throws {Error} when the file is missing or does not parse
 */
export func openGpx(target as string) {
    return readGpxBytes(toUtf8(readFileBytes($target)));
}

/**
 * Write a document to a file as GPX 1.1.
 *
 * @param doc {Document} what to write
 * @param target {string} the path to write
 * @throws {Error} when the write fails
 */
export func saveGpx(doc as Document, target as string) {
    writeFileText($target, writeGpx($doc));
}

/**
 * Read a KML file.
 *
 * @param target {string} the path to read
 * @return {Document} what the file held
 * @throws {Error} when the file is missing or does not parse
 */
export func openKml(target as string) {
    return readKmlBytes(toUtf8(readFileBytes($target)));
}

/**
 * Write a document to a file as KML 2.2.
 *
 * @param doc {Document} what to write
 * @param target {string} the path to write
 * @throws {Error} when the write fails
 */
export func saveKml(doc as Document, target as string) {
    writeFileText($target, writeKml($doc));
}

/**
 * Read a KMZ file.
 *
 * @param target {string} the path to read
 * @return {Document} what the KML inside held
 * @throws {Error} when the file is missing, is not a zip, or does not parse
 */
export func openKmz(target as string) {
    return readKmz(readFileBytes($target));
}

/**
 * Write a document to a file as KMZ.
 *
 * @param doc {Document} what to write
 * @param target {string} the path to write
 * @throws {Error} when the write fails
 */
export func saveKmz(doc as Document, target as string) {
    writeFileBytes($target, writeKmz($doc));
}

/**
 * Convert one file to another format.
 *
 * {@link open} on one path, {@link save} to the other.
 *
 * @param from {string} the path to read
 * @param to2 {string} the path to write
 * @return {Document} what was read, so a caller can measure what it converted
 * @throws {Error} when either extension names no format, or either side fails
 * @example
 *   geo.convertFile("hike.gpx", "hike.geojson");
 */
export func convertFile(from as string, to2 as string) {
    def doc as Document init open($from);
    save($doc, $to2);
    return $doc;
}

/**
 * A whole file as bytes, with a failure to read it raised as this deck's error.
 *
 * @param target {string} the path to read
 * @return {bytes} the file
 * @throws {Error} when the file is missing or cannot be read
 */
func readFileBytes(target as string) {
    def out as bytes;
    try {
        $out = fs.readBytes($target);
    } catch (e) {
        fail("cannot read " + quoted($target) + ": " + $e.message);
    }
    return $out;
}

/**
 * Write bytes to a file, with a failure raised as this deck's error.
 *
 * @param target {string} the path to write
 * @param data {bytes} what to write
 * @throws {Error} when the file cannot be written
 */
func writeFileBytes(target as string, data as bytes) {
    try {
        fs.writeBytes($target, $data);
    } catch (e) {
        fail("cannot write " + quoted($target) + ": " + $e.message);
    }
}

/**
 * Write text to a file as UTF-8, with a failure raised as this deck's error.
 *
 * @param target {string} the path to write
 * @param text {string} what to write
 * @throws {Error} when the file cannot be written
 */
func writeFileText(target as string, text as string) {
    try {
        fs.writeString($target, $text);
    } catch (e) {
        fail("cannot write " + quoted($target) + ": " + $e.message);
    }
}
