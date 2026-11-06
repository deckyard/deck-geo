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

func testDecimalTrimsOnlyFractionZeros() {
    # the zeros of an integer part are digits, not padding
    testing.assertEqual(decimal(100.0, COORD_PLACES), "100");
    testing.assertEqual(decimal(-180.0, COORD_PLACES), "-180");
    testing.assertEqual(decimal(10.5, ELEVATION_PLACES), "10.5");
}

func testDecimalWritesNegativeZeroAsZeroAtNoPlaces() {
    # -0.4 rounds to -0 at zero places; "%f|prec=0" has no "." to trim, and
    # the old check after the trim never saw it
    testing.assertEqual(decimal(-0.4, 0), "0");
    testing.assertEqual(decimal(-1.4, 0), "-1");
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

func testNormalizeBearingWrapsAnAngleTooLargeForFloor() {
    # 2^80 mod 360: 2^80 = 0 mod 8; 2^12 = 4096 = 1 mod 45, so 2^80 = 2^8 = 256 = 31
    # mod 45. The x in 0..359 with x = 0 mod 8 and x = 31 mod 45 is 256.
    def big as float init math.pow(2.0, 80.0);
    testing.assertEqual(normalizeBearing($big), 256.0);
    testing.assertEqual(normalizeBearing(-$big), 104.0);
    # 360 * 2^60 is a whole number of turns
    testing.assertEqual(normalizeBearing(360.0 * math.pow(2.0, 60.0)), 0.0);
    def huge as float init normalizeBearing(1.7e308);
    testing.assertTrue($huge >= 0.0 and $huge < 360.0);
    # just below the switch-over, the floor path still applies: 2^52 = 2^4 * 2^48;
    # 2^48 = 2^12^4 = 1 mod 45 and 2^52 = 0 mod 8, so 2^52 = 16 mod 45 -> 16
    testing.assertEqual(normalizeBearing(math.pow(2.0, 52.0)), 16.0);
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

func failOnAHexFloat() {
    number("0x1p4", "a latitude");
}

func failOnAHexInteger() {
    number("0x10", "a latitude");
}

func failOnInfinity() {
    number("Inf", "a latitude");
}

func failOnAnExponentWithNoDigits() {
    number("1e", "a latitude");
}

func testNumberRejectsJenniferOnlyLiterals() {
    # convert.toFloat reads "0x1p4" as 16 and "0x10" as 16; xsd:double has no
    # hexadecimal form
    testing.assertThrows("failOnAHexFloat", ERROR_KIND);
    testing.assertThrows("failOnAHexInteger", ERROR_KIND);
    testing.assertThrows("failOnInfinity", ERROR_KIND);
    testing.assertThrows("failOnAnExponentWithNoDigits", ERROR_KIND);
}

func testNumberReadsEveryXsdDoubleSpelling() {
    # xsd:double: optional sign, optional fraction, optional exponent
    testing.assertEqual(number("+1e1", "x"), 10.0);
    testing.assertEqual(number(".5", "x"), 0.5);
    testing.assertEqual(number("-2.", "x"), -2.0);
    testing.assertEqual(number("1E-2", "x"), 0.01);
}

func testXmlEscapeDropsWhatXmlCannotHold() {
    testing.assertEqual(xmlEscape("a\u0001b\u000Bc\u001Fd"), "abcd");
    testing.assertEqual(xmlEscape("x\uFFFEy\uFFFF"), "xy");
    # tab, line feed and carriage return are legal and stay
    testing.assertEqual(xmlEscape("a\tb\nc\rd"), "a\tb\nc&#13;d");
    testing.assertEqual(xmlEscape("Ca\u00f1on & <Rim>"), "Ca\u00f1on &amp; &lt;Rim&gt;");
}

func testXmlEscapeWritesACarriageReturnAsAReference() {
    # XML 1.0 2.11: a parser turns CR LF and lone CR into LF, so a raw CR is lost
    testing.assertEqual(xmlEscape("a\r\nb"), "a&#13;\nb");
    testing.assertEqual(xmlUnescape(xmlEscape("a\r\nb")), "a\r\nb");
}
