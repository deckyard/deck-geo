# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# geo - white-box tests for the core topic.
# Spliced into geo_test.j via include - run with:
#   jennifer test src/geo_test.j

func testLocalNameStripsAPrefix() {
    testing.assertEqual(localName("trkpt"), "trkpt");
    testing.assertEqual(localName("kml:Placemark"), "Placemark");
    testing.assertEqual(localName("gml:posList"), "posList");
    testing.assertEqual(localName("a:b:c"), "b:c");
    testing.assertEqual(localName(""), "");
}

func testXmlEscapeWritesAllFiveEntities() {
    testing.assertEqual(xmlEscape("a & b"), "a &amp; b");
    testing.assertEqual(xmlEscape("<x>"), "&lt;x&gt;");
    testing.assertEqual(xmlEscape("say \"hi\""), "say &quot;hi&quot;");
    testing.assertEqual(xmlEscape("it's"), "it&apos;s");
    # the ampersand is replaced first, so an escape is not escaped twice
    testing.assertEqual(xmlEscape("&lt;"), "&amp;lt;");
}

func testXmlUnescapeResolvesTheFivePredefinedEntities() {
    testing.assertEqual(xmlUnescape("a &amp; b"), "a & b");
    testing.assertEqual(xmlUnescape("&lt;x&gt;"), "<x>");
    testing.assertEqual(xmlUnescape("&quot;q&quot;"), "\"q\"");
    testing.assertEqual(xmlUnescape("it&apos;s"), "it's");
    testing.assertEqual(xmlUnescape("nothing here"), "nothing here");
}

func testXmlUnescapeResolvesNumericReferences() {
    testing.assertEqual(xmlUnescape("Ca&#241;on"), "Cañon");
    testing.assertEqual(xmlUnescape("Ca&#xf1;on"), "Cañon");
    testing.assertEqual(xmlUnescape("Ca&#Xf1;on"), "Cañon");
    testing.assertEqual(xmlUnescape("&#65;&#66;"), "AB");
}

func testXmlUnescapeLeavesAnUnknownEntityStanding() {
    # a reader that throws on &deg; cannot open what a GIS exporter writes
    testing.assertEqual(xmlUnescape("90&deg; N"), "90&deg; N");
    testing.assertEqual(xmlUnescape("a & b"), "a & b");
    testing.assertEqual(xmlUnescape("&"), "&");
    testing.assertEqual(xmlUnescape("&#;"), "&#;");
    testing.assertEqual(xmlUnescape("&#xzz;"), "&#xzz;");
}

func testXmlUnescapeLeavesAnOutOfRangeReferenceStanding() {
    # past the last code point it is not a character, and twenty digits would
    # overflow int64 if the reader kept multiplying
    testing.assertEqual(xmlUnescape("&#1114112;"), "&#1114112;");
    testing.assertEqual(xmlUnescape("&#x110000;"), "&#x110000;");
    def huge as string init "&#99999999999999999999999;";
    testing.assertEqual(xmlUnescape($huge), $huge);
    testing.assertEqual(xmlUnescape("&#x10FFFF;"), convert.fromCodepoint(0x10FFFF));
}

func testXmlEscapeAndUnescapeRoundTrip() {
    def cases as list of string init [
        "plain",
        "a & b",
        "<tag>",
        "\"q\"",
        "it's",
        "all five: & < > \" '"
    ];
    for (def text in $cases) {
        testing.assertEqual(xmlUnescape(xmlEscape($text)), $text);
    }
}

func testDigitsToInt() {
    testing.assertEqual(digitsToInt("241", false), 241);
    testing.assertEqual(digitsToInt("f1", true), 241);
    testing.assertEqual(digitsToInt("F1", true), 241);
    testing.assertEqual(digitsToInt("", false), -1);
    testing.assertEqual(digitsToInt("12x", false), -1);
    # a hexadecimal letter is not a decimal digit
    testing.assertEqual(digitsToInt("f1", false), -1);
}

func testDecimalKeepsNoTrailingZeros() {
    testing.assertEqual(decimal(47.2692, COORD_PLACES), "47.2692");
    testing.assertEqual(decimal(574.0, ELEVATION_PLACES), "574");
    testing.assertEqual(decimal(574.5, ELEVATION_PLACES), "574.5");
    testing.assertEqual(decimal(0.0, COORD_PLACES), "0");
    testing.assertEqual(decimal(-11.4041, COORD_PLACES), "-11.4041");
}

func testDecimalWritesNegativeZeroAsZero() {
    # "-0" in a coordinate attribute is what a strict validator objects to
    testing.assertEqual(decimal(-0.0, COORD_PLACES), "0");
    testing.assertEqual(decimal(0.0, COORD_PLACES), "0");
    # a real negative value is untouched
    testing.assertEqual(decimal(-0.5, COORD_PLACES), "-0.5");
    testing.assertEqual(decimal(-0.0000001, COORD_PLACES), "-0.0000001");
    # and one that rounds away to nothing is zero, not minus zero
    testing.assertEqual(decimal(-0.00000001, COORD_PLACES), "0");
}

func testDecimalKeepsEveryPlaceThatMatters() {
    testing.assertEqual(decimal(47.2690914, COORD_PLACES), "47.2690914");
    # one place past the precision is rounded away, not kept
    testing.assertEqual(decimal(47.26909141, COORD_PLACES), "47.2690914");
}

func testTrimTrailing() {
    testing.assertEqual(trimTrailing("100", "0"), "1");
    testing.assertEqual(trimTrailing("1.", "."), "1");
    testing.assertEqual(trimTrailing("000", "0"), "");
    testing.assertEqual(trimTrailing("abc", "0"), "abc");
}

func testNumberParsesAndReports() {
    testing.assertEqual(number("47.2692", "lat"), 47.2692);
    testing.assertEqual(number("  574  ", "ele"), 574.0);
    testing.assertEqual(number("-1.5e2", "ele"), -150.0);
}

func failOnEmptyNumber() {
    number("   ", "<ele>");
}

func failOnWordNumber() {
    number("north", "<ele>");
}

func testNumberRejectsWhatIsNotANumber() {
    testing.assertThrows("failOnEmptyNumber", ERROR_KIND);
    testing.assertThrows("failOnWordNumber", ERROR_KIND);
}

func failOnHighLatitude() {
    checkCoord(90.1, 0.0);
}

func failOnLowLongitude() {
    checkCoord(0.0, -180.1);
}

func testCheckCoordBoundsAreInclusive() {
    checkCoord(90.0, 180.0);
    checkCoord(-90.0, -180.0);
    testing.assertThrows("failOnHighLatitude", ERROR_KIND);
    testing.assertThrows("failOnLowLongitude", ERROR_KIND);
}

func testClampUnitKeepsAcosInItsDomain() {
    testing.assertEqual(clampUnit(0.5), 0.5);
    testing.assertEqual(clampUnit(1.0), 1.0);
    testing.assertEqual(clampUnit(1.0000000000000002), 1.0);
    testing.assertEqual(clampUnit(-1.5), -1.0);
    # the reason it exists: math.acos raises rather than returning a NaN
    testing.assertEqual(math.acos(clampUnit(1.0000000000000002)), 0.0);
}

func testNormalizeBearingWraps() {
    testing.assertEqual(normalizeBearing(0.0), 0.0);
    testing.assertEqual(normalizeBearing(359.5), 359.5);
    testing.assertEqual(normalizeBearing(360.0), 0.0);
    testing.assertEqual(normalizeBearing(450.0), 90.0);
    testing.assertEqual(normalizeBearing(-90.0), 270.0);
    testing.assertEqual(normalizeBearing(-450.0), 270.0);
}

func testNormalizeLongitudeWraps() {
    testing.assertEqual(normalizeLongitude(11.4041), 11.4041);
    testing.assertEqual(normalizeLongitude(-179.0), -179.0);
    testing.assertEqual(normalizeLongitude(181.0), -179.0);
    testing.assertEqual(normalizeLongitude(-181.0), 179.0);
    testing.assertEqual(normalizeLongitude(540.0), -180.0);
}

func failOnTooDeep() {
    checkDepth(MAX_NESTING + 1, "test containers");
}

func testCheckDepthStopsAtTheCeiling() {
    checkDepth(0, "test containers");
    checkDepth(MAX_NESTING, "test containers");
    testing.assertThrows("failOnTooDeep", ERROR_KIND);
    testing.assertEqual(MAX_NESTING, 100);
}

func testQuotedBoundsWhatAnErrorMessageCanCarry() {
    testing.assertEqual(quoted("47.2692"), "\"47.2692\"");
    testing.assertEqual(quoted(""), "\"\"");
    # a hostile file can put half a megabyte in an attribute; the message that
    # quotes it must not be half a megabyte long
    def huge as string init strings.repeat("9", 500000);
    def message as string init quoted($huge);
    testing.assertTrue(len($message) < 100);
    testing.assertContains($message, "500000 characters");
}

func testErrorKindIsTheOneKind() {
    testing.assertEqual(ERROR_KIND, "geo");
    testing.assertEqual(COORD_PLACES, 7);
    testing.assertEqual(ELEVATION_PLACES, 2);
}

func failOnADigitSeparator() {
    number("1_0", "a latitude");
}

func testNumberRejectsADigitSeparator() {
    # convert.toFloat reads "1_0" as 10, which no coordinate format means
    testing.assertThrows("failOnADigitSeparator", ERROR_KIND);
}

func testXmlEscapeDropsWhatXmlCannotHold() {
    testing.assertEqual(xmlEscape("a\u0001b\u000Bc\u001Fd"), "abcd");
    testing.assertEqual(xmlEscape("x\uFFFEy\uFFFF"), "xy");
    # tab, line feed and carriage return are legal and stay
    testing.assertEqual(xmlEscape("a\tb\nc\rd"), "a\tb\nc\rd");
    testing.assertEqual(xmlEscape("Ca\u00f1on & <Rim>"), "Ca\u00f1on &amp; &lt;Rim&gt;");
}
