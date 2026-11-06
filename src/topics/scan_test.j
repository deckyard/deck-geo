# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# geo - white-box tests for the scan topic.
# Spliced into geo_test.j via include - run with:
#   jennifer test src/geo_test.j

/** A string as the byte buffer the scanner works on. */
func buffer(text as string) {
    return convert.bytesFromString($text, "utf-8");
}

/** The direct children of a document's root element. */
func rootChildren(text as string) {
    def src as bytes init buffer($text);
    def root as Node init rootNode($src);
    return childNodes($src, $root.openEnd, $root.innerEnd);
}

func testRootNodeFindsTheRootPastThePrologue() {
    def src as bytes init buffer("<?xml version=\"1.0\"?>\n<!-- note -->\n<gpx></gpx>");
    testing.assertEqual(rootNode($src).name, "gpx");
}

func testRootNodeSkipsADoctype() {
    def src as bytes init buffer("<!DOCTYPE kml><kml:kml></kml:kml>");
    testing.assertEqual(rootNode($src).name, "kml:kml");
}

func failOnNoElement() {
    rootNode(buffer("<?xml version=\"1.0\"?><!-- nothing here -->"));
}

func testRootNodeOfADocumentWithNoElement() {
    testing.assertThrows("failOnNoElement", ERROR_KIND);
}

func testChildNodesFindsDirectChildrenOnly() {
    def doc as string init "<gpx><wpt><name>A</name></wpt><wpt /><trk></trk></gpx>";
    def kids as list of Node init rootChildren($doc);
    testing.assertEqual(len($kids), 3);
    testing.assertEqual($kids[0].name, "wpt");
    testing.assertEqual($kids[1].name, "wpt");
    testing.assertEqual($kids[2].name, "trk");
}

func testChildNodesTellsATagFromAPrefixOfIt() {
    # <trk> and <trkseg> share five characters; a scanner that matched on the
    # prefix would see the wrong boundaries
    def kids as list of Node init rootChildren("<gpx><trkseg /><trk /></gpx>");
    testing.assertEqual($kids[0].name, "trkseg");
    testing.assertEqual($kids[1].name, "trk");
}

func testChildNodesCountsNestingOfTheSameName() {
    def doc as string init "<kml><Folder><Folder><Placemark /></Folder>" +
        "</Folder><Folder /></kml>";
    def src as bytes init buffer($doc);
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    # two outer folders, not four: the nested one does not close the outer one
    testing.assertEqual(len($kids), 2);
    def inner as list of Node init childNodes($src, $kids[0].openEnd, $kids[0].innerEnd);
    testing.assertEqual(len($inner), 1);
    testing.assertEqual($inner[0].name, "Folder");
}

func testChildNodesSkipsCommentsAndInstructions() {
    def doc as string init "<gpx><!-- <wpt /> --><?php echo 1; ?><wpt /></gpx>";
    def kids as list of Node init rootChildren($doc);
    # the commented-out waypoint is not an element
    testing.assertEqual(len($kids), 1);
}

func testChildNodesSkipsCdata() {
    def kids as list of Node init rootChildren("<gpx><![CDATA[<wpt />]]><trk /></gpx>");
    testing.assertEqual(len($kids), 1);
    testing.assertEqual($kids[0].name, "trk");
}

func testChildNodesIsNotFooledByAGreaterThanInAnAttribute() {
    def kids as list of Node init rootChildren("<gpx><wpt desc=\"a > b\" /><trk /></gpx>");
    testing.assertEqual(len($kids), 2);
    testing.assertEqual($kids[1].name, "trk");
}

func testChildNodesRecoversFromATruncatedDocument() {
    # a recorder that lost power mid-write: the elements before the damage
    # still read back rather than the whole file being refused
    def kids as list of Node init rootChildren("<gpx><wpt /><trk><trkseg>");
    testing.assertEqual(len($kids), 2);
    testing.assertEqual($kids[0].name, "wpt");
    testing.assertEqual($kids[1].name, "trk");
}

func testChildNodesIgnoresATruncatedOpenTag() {
    # no closing angle bracket at all: there is no name or attribute to read
    def kids as list of Node init rootChildren("<gpx><wpt /><trk");
    testing.assertEqual(len($kids), 1);
    testing.assertEqual($kids[0].name, "wpt");
}

func testReadGpxRecoversTheTrackPointsBeforeTheDamage() {
    def text as string init "<gpx><trk><trkseg>" +
        "<trkpt lat=\"47.0\" lon=\"11.0\" /><trkpt lat=\"47.1\" lon=\"11.1\" />";
    def doc as Document init readGpx($text);
    testing.assertEqual(len(trackPoints($doc.tracks[0])), 2);
}

func testNodeTextReadsCharacterData() {
    def src as bytes init buffer("<gpx><name>  Innsbruck loop  </name></gpx>");
    def kids as list of Node init childNodes($src, rootNode($src).openEnd, rootNode($src).innerEnd);
    testing.assertEqual(nodeText($src, $kids[0]), "Innsbruck loop");
}

func testNodeTextResolvesEntities() {
    def src as bytes init buffer("<gpx><name>Ca&#241;on &amp; Rim</name></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeText($src, $kids[0]), "Cañon & Rim");
}

func testNodeTextReadsCdata() {
    def src as bytes init buffer("<gpx><desc><![CDATA[a < b & c]]></desc></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    # a CDATA section is verbatim: the entities inside it are not entities
    testing.assertEqual(nodeText($src, $kids[0]), "a < b & c");
}

func testNodeTextDropsMarkupItDoesNotModel() {
    def src as bytes init buffer("<gpx><desc>a <b>bold</b> word</desc></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeText($src, $kids[0]), "a bold word");
}

func testNodeTextOfAnEmptyElement() {
    def src as bytes init buffer("<gpx><name /><desc></desc></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeText($src, $kids[0]), "");
    testing.assertEqual(nodeText($src, $kids[1]), "");
}

func testNodeAttrReadsEitherQuote() {
    def src as bytes init buffer("<gpx><trkpt lat=\"47.2692\" lon='11.4041' /></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "lat"), "47.2692");
    testing.assertEqual(nodeAttr($src, $kids[0], "lon"), "11.4041");
}

func testNodeAttrIsEmptyWhenAbsent() {
    def src as bytes init buffer("<gpx><trkpt lat=\"1\" /></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "lon"), "");
}

func testNodeAttrIgnoresAPrefixAndResolvesEntities() {
    def src as bytes init buffer("<gpx><trkpt gpx:lat=\"47.2692\" desc=\"a &amp; b\" /></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "lat"), "47.2692");
    testing.assertEqual(nodeAttr($src, $kids[0], "desc"), "a & b");
}

func testNodeAttrSurvivesAwkwardSpacing() {
    def src as bytes init buffer("<gpx><trkpt\n   lat = \"47.2692\"\n   lon=\"11\"\n/></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "lat"), "47.2692");
    testing.assertEqual(nodeAttr($src, $kids[0], "lon"), "11");
}

func testNodeAttrDoesNotReadTheChildrensAttributes() {
    def src as bytes init buffer("<gpx><trk><trkpt lat=\"1\" /></trk></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "lat"), "");
}

func testFindChildAndFindChildren() {
    def src as bytes init buffer("<gpx><wpt /><trk /><wpt /></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertTrue(isNode(findChild($kids, "trk")));
    testing.assertFalse(isNode(findChild($kids, "rte")));
    testing.assertEqual(len(findChildren($kids, "wpt")), 2);
    testing.assertEqual(len(findChildren($kids, "rte")), 0);
}

func testFindChildMatchesOnTheLocalName() {
    def src as bytes init buffer("<kml:kml><kml:Document /></kml:kml>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertTrue(isNode(findChild($kids, "Document")));
}

func testChildTextIsEmptyForAMissingChild() {
    def src as bytes init buffer("<gpx><name>A</name></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(childText($src, $kids, "name"), "A");
    testing.assertEqual(childText($src, $kids, "desc"), "");
}

func testFragmentCutsOutAWholeElement() {
    def src as bytes init buffer("<gpx><wpt lat=\"1\"><name>A</name></wpt></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(fragment($src, $kids[0]), "<wpt lat=\"1\"><name>A</name></wpt>");
}

func testMatchesAtAndIndexOfByte() {
    def src as bytes init buffer("<gpx><wpt /></gpx>");
    testing.assertTrue(matchesAt($src, 0, probeOf("<gpx")));
    testing.assertFalse(matchesAt($src, 1, probeOf("<gpx")));
    testing.assertFalse(matchesAt($src, -1, probeOf("<")));
    testing.assertFalse(matchesAt($src, 16, probeOf("</gpx>")));
    testing.assertEqual(indexOfByte($src, LT_PROBE, 0, len($src)), 0);
    testing.assertEqual(indexOfByte($src, LT_PROBE, 1, len($src)), 5);
    # the limit is applied to the answer, not just to where the search starts
    testing.assertEqual(indexOfByte($src, LT_PROBE, 1, 3), -1);
    testing.assertEqual(indexOfByte($src, LT_PROBE, 0, 0), -1);
}

func testProbeOf() {
    testing.assertEqual(probeOf("<"), LT_PROBE);
    testing.assertEqual(len(probeOf("<![CDATA[")), 9);
}

func testIsNameEndAndIsSpace() {
    testing.assertTrue(isNameEnd(GT));
    testing.assertTrue(isNameEnd(SLASH));
    testing.assertTrue(isNameEnd(0x20));
    testing.assertFalse(isNameEnd(0x61));
    testing.assertTrue(isSpace(" "));
    testing.assertTrue(isSpace("\n"));
    testing.assertFalse(isSpace("a"));
}

func testNodeAttrReadsAnUnquotedValue() {
    # not well-formed XML, but hand-edited files carry it and it costs nothing
    def src as bytes init buffer("<gpx><trkpt lat=47.2692 lon=11 /></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "lat"), "47.2692");
    testing.assertEqual(nodeAttr($src, $kids[0], "lon"), "11");
}

func testNodeAttrDoesNotMatchANameInsideAnother() {
    def src as bytes init buffer("<gpx><trkpt translate=\"7\" lat=\"47\" /></gpx>");
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "lat"), "47");
}

func testSkipSpaceBytesAndIsSpaceByte() {
    def src as bytes init buffer("a   b");
    testing.assertEqual(skipSpaceBytes($src, 1, len($src)), 4);
    testing.assertEqual(skipSpaceBytes($src, 0, len($src)), 0);
    testing.assertEqual(skipSpaceBytes($src, 1, 2), 2);
    testing.assertTrue(isSpaceByte(0x20));
    testing.assertFalse(isSpaceByte(0x61));
}

func testTextOnlyAndCdataText() {
    testing.assertEqual(textOnly("a <b>c</b> d"), "a c d");
    testing.assertEqual(textOnly("plain"), "plain");
    # the text between and around the sections is text too
    testing.assertEqual(cdataText("<![CDATA[one]]> and <![CDATA[two]]>"), "one and two");
    testing.assertEqual(cdataText("Rock <![CDATA[&]]> &amp; Roll"), "Rock & & Roll");
    # an unterminated section keeps what is left of it
    testing.assertEqual(cdataText("<![CDATA[tail"), "tail");
}

func testSkipPastStopsAtTheLimit() {
    def src as bytes init buffer("<!-- comment --><wpt />");
    testing.assertEqual(skipPast($src, 0, "-->", len($src)), 16);
    # the literal is past the limit, so the limit is the answer
    testing.assertEqual(skipPast($src, 0, "-->", 5), 5);
    testing.assertEqual(skipPast($src, 0, "nowhere", len($src)), len($src));
}

func testByteTextOfAnEmptyRange() {
    def src as bytes init buffer("<gpx />");
    testing.assertEqual(byteText($src, 3, 3), "");
    testing.assertEqual(byteText($src, 5, 3), "");
    testing.assertEqual(byteText($src, 1, 4), "gpx");
}

func testTextOnlyKeepsALiteralGreaterThan() {
    # a > outside a tag is text; a comment ends at -->, not at a > inside it
    testing.assertEqual(textOnly("a<!--c--> b > c"), "a b > c");
    testing.assertEqual(textOnly("x<!-- a > b -->y"), "xy");
    testing.assertEqual(textOnly("cut <b"), "cut ");
}

func testNodeAttrDoesNotMatchInsideAnotherValue() {
    def text as string init "<gpx><trkpt note=\"x lat=9 lon=9\" lat=\"1\" lon=\"2\" /></gpx>";
    def src as bytes init buffer($text);
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeAttr($src, $kids[0], "lat"), "1");
    testing.assertEqual(nodeAttr($src, $kids[0], "lon"), "2");
    testing.assertEqual(nodeAttr($src, $kids[0], "note"), "x lat=9 lon=9");
}

func testIndexOfByteStopsAtTheLimit() {
    def src as bytes init buffer("ab\"cd\"");
    testing.assertEqual(indexOfByte($src, DQUOTE_PROBE, 0, 2), -1);
    testing.assertEqual(indexOfByte($src, DQUOTE_PROBE, 0, 3), 2);
    testing.assertEqual(indexOfByte($src, DQUOTE_PROBE, 3, 100), 5);
}

func testToUtf8TranscodesADeclaredLatin1Document() {
    def head as string init "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><gpx><name>Ca";
    def parts as list of bytes init [
        buffer($head),
        encoding.encode("\u00f1", "iso-8859-1"),
        buffer("on</name></gpx>")
    ];
    def src as bytes init toUtf8(binary.join($parts));
    def root as Node init rootNode($src);
    def kids as list of Node init childNodes($src, $root.openEnd, $root.innerEnd);
    testing.assertEqual(nodeText($src, $kids[0]), "Ca\u00f1on");
}

func testToUtf8LeavesUtf8Alone() {
    def src as bytes init buffer("<?xml version='1.0' encoding='UTF-8'?><gpx/>");
    testing.assertEqual(toUtf8($src), $src);
    testing.assertEqual(toUtf8(buffer("<gpx/>")), buffer("<gpx/>"));
}

func failOnUtf16() {
    toUtf8(binary.join([binary.make(1, 0xff), binary.make(1, 0xfe), buffer("<")]));
}

func failOnAnUnknownEncoding() {
    toUtf8(buffer("<?xml version=\"1.0\" encoding=\"Shift_JIS\"?><gpx/>"));
}

func failOnInvalidUtf8() {
    def src as bytes init binary.join([
        buffer("<gpx><name>"),
        binary.make(1, 0xf1),
        buffer("</name></gpx>")
    ]);
    readGpxBytes($src);
}

func testToUtf8RejectsWhatItCannotRead() {
    testing.assertThrows("failOnUtf16", ERROR_KIND);
    testing.assertThrows("failOnAnUnknownEncoding", ERROR_KIND);
    testing.assertThrows("failOnInvalidUtf8", ERROR_KIND);
}

# The root's xmlns declarations, prefix to URI, with the default under "".
func testNamespaceBindingsReadsTheRoot() {
    def src as bytes init convert.bytesFromString(
        "<gpx xmlns=\"urn:d\" xmlns:a=\"urn:a\" version=\"1.1\"><wpt/></gpx>",
        "utf-8");
    def ns as map of string to string init namespaceBindings($src, rootNode($src));
    testing.assertEqual(len($ns), 2);
    testing.assertEqual($ns[""], "urn:d");
    testing.assertEqual($ns["a"], "urn:a");
    # A root with an undeclared prefix of its own still yields what it declares.
    def damaged as bytes init convert.bytesFromString("<x:gpx xmlns:a=\"urn:a\"/>", "utf-8");
    testing.assertEqual(namespaceBindings($damaged, rootNode($damaged))["a"], "urn:a");
}

# A leaf using a prefix nobody declared is damage, and still decodes.
func testDecodeLeafStandsInForAnUndeclaredPrefix() {
    def src as bytes init convert.bytesFromString(
        "<r><p:pt lat=\"1\"><p:name>n</p:name></p:pt></r>",
        "utf-8");
    def leaf as Node init childNodes($src, rootNode($src).openEnd, rootNode($src).innerEnd)[0];
    def tree as xml.Value init decodeLeaf($src, $leaf, {});
    testing.assertEqual(leafText($tree, "name"), "n");
    testing.assertEqual(
        withStandIns("<p:a q:b=\"1\"/>", {"p": "urn:p"})["q"],
        STAND_IN_NAMESPACE + "q");
    testing.assertEqual(withStandIns("<p:a/>", {"p": "urn:p"})["p"], "urn:p");
}

func testChildNodesIgnoresACloseTagInsideAComment() {
    # the comment's </gpx> is text: the root runs to the real close tag
    def kids as list of Node init rootChildren("<gpx><!-- end </gpx> --><wpt /></gpx>");
    testing.assertEqual(len($kids), 1);
    testing.assertEqual($kids[0].name, "wpt");
}

func testChildNodesIgnoresTagsInsideCdata() {
    # a </wpt> and a <wpt> inside CDATA neither close nor nest the element
    def doc as string init "<gpx><wpt><desc><![CDATA[x </wpt> <wpt> y]]></desc></wpt><trk /></gpx>";
    def kids as list of Node init rootChildren($doc);
    testing.assertEqual(len($kids), 2);
    testing.assertTrue($kids[0].closed);
    testing.assertEqual($kids[1].name, "trk");
    # the first child ends where the second begins: "<gpx>" is 5 bytes
    testing.assertEqual($kids[0].end, strings.indexOf($doc, "<trk />"));
}

func testReadNodeEndsPastACloseTagWithSpace() {
    # `</wpt >` is legal; the element ends after the `>`, not at len("</wpt>")
    def doc as string init "<gpx><wpt></wpt ><trk /></gpx>";
    def kids as list of Node init rootChildren($doc);
    testing.assertEqual($kids[0].end, strings.indexOf($doc, "<trk"));
    testing.assertEqual(fragment(buffer($doc), $kids[0]), "<wpt></wpt >");
}

func testOpenTagAtSkipsLongerNames() {
    def src as bytes init buffer("<gpx><trkpt /><trkseg><gpxtpx:hr/><trk >");
    # the first `<trk` hits are prefixes of `<trkpt` and `<trkseg`
    testing.assertEqual(openTagAt($src, probeOf("<trk"), 0, len($src)), 34);
    testing.assertEqual(openTagAt($src, probeOf("<gpx"), 1, len($src)), -1);
    testing.assertEqual(openTagAt($src, probeOf("<trk"), 0, 34), -1);
}

func testCloseTagAtSkipsLongerNamesAndStrayText() {
    def src as bytes init buffer("</trkpt></trkseg></trk x></trk\n>");
    # "</trkpt>" 8 + "</trkseg>" 9 + "</trk x>" 8 = 25: `</trk x>` is not a close tag
    testing.assertEqual(closeTagAt($src, probeOf("</trk"), 0, len($src)), 25);
    testing.assertEqual(closeTagAt($src, probeOf("</trkseg"), 0, len($src)), 8);
}

func testExactTagAtTakesTheEarliestSpelling() {
    def src as bytes init buffer("<a\t/><a><a/>");
    testing.assertEqual(exactTagAt($src, probeOf("<a"), false, 0, len($src)), 0);
    testing.assertEqual(exactTagAt($src, probeOf("<a"), false, 1, len($src)), 5);
    testing.assertEqual(exactTagAt($src, probeOf("</a"), true, 0, len($src)), -1);
}

func testNestedCloseCapsSameNameNesting() {
    # MAX_NESTING + 1 nested <f> under one more: deeper than any reader takes,
    # so the outer element reads as unclosed rather than costing a scan per level
    def inner as int init MAX_NESTING + 1;
    def doc as string init strings.repeat("<f>", $inner + 1) + strings.repeat("</f>", $inner + 1);
    def src as bytes init buffer($doc);
    testing.assertEqual(matchingClose($src, "f", 3, len($src)), -1);
    # one level less is read: the outer close is the last four bytes
    def ok as string init strings.repeat("<f>", $inner) + strings.repeat("</f>", $inner);
    def okSrc as bytes init buffer($ok);
    testing.assertEqual(matchingClose($okSrc, "f", 3, len($okSrc)), len($ok) - 4);
}

func testNestedCloseIsLinearInOpenTagPrefixes() {
    # One nested <trk>, then 80,000 `<trkx` inside a comment. Searching for the
    # close tag again for every `<trkx` hit made this quadratic: 2.8 s here on
    # the old scanner, against a few milliseconds when each position is kept.
    def doc as string init "<gpx><trk><trk></trk><!--" + strings.repeat("<trkx", 80000) +
        "--></trk></gpx>";
    def started as int init time.now().nanos;
    def kids as list of Node init rootChildren($doc);
    def elapsed as int init (time.now().nanos - $started) // 1000000;
    testing.assertEqual(len($kids), 1);
    testing.assertTrue($kids[0].closed);
    testing.assertTrue($elapsed < 1000);
}

func testSearchFromKeepsACurrentCursor() {
    # a hit still ahead of the walk is current
    testing.assertEqual(searchFrom(50, 10, 20, 100), -1);
    # a passed hit is searched again from the walk's position
    testing.assertEqual(searchFrom(15, 10, 20, 100), 20);
    # no hit up to the bound already searched: nothing to do
    testing.assertEqual(searchFrom(-1, 100, 20, 100), -1);
    # the bound moved on: search only the new stretch
    testing.assertEqual(searchFrom(-1, 60, 20, 100), 60);
}

func testSkipMarkupAndIsSelfClosing() {
    def src as bytes init buffer("<!-- a --><![CDATA[b]]><!DOCTYPE x><p/>");
    testing.assertEqual(skipMarkup($src, 0, len($src)), 10);
    testing.assertEqual(skipMarkup($src, 10, len($src)), 23);
    testing.assertEqual(skipMarkup($src, 23, len($src)), 25);
    testing.assertTrue(isSelfClosing($src, 37, len($src)));
    testing.assertFalse(isSelfClosing(buffer("<p>"), 2, 3));
}

func testEndOfOpenTagStepsOverQuotedGreaterThan() {
    def src as bytes init buffer("<a x='>' y=\"'>\" z=\">\">rest");
    # 22 bytes up to and including the real `>`
    testing.assertEqual(endOfOpenTag($src, 2, len($src)), 22);
    testing.assertEqual(endOfOpenTag(buffer("<a x=\">"), 2, 7), -1);
}

func testDecodeLeafKeepsAnUnknownEntityAsWritten() {
    def src as bytes init buffer("<wpt><name>10&deg; &amp; a & b<![CDATA[&x;]]></name></wpt>");
    def node as Node init rootNode($src);
    def leaf as xml.Value init decodeLeaf($src, $node, {});
    testing.assertEqual(leafText($leaf, "name"), "10&deg; & a & b&x;");
}

func testEscapeUnknownEntities() {
    testing.assertEqual(
        escapeUnknownEntities("a &deg; &lt; &#65; & b"),
        "a &amp;deg; &lt; &#65; &amp; b");
    testing.assertEqual(
        escapeUnknownEntities("<![CDATA[&deg;]]>&deg;"),
        "<![CDATA[&deg;]]>&amp;deg;");
    testing.assertEqual(escapeUnknownEntities("plain"), "plain");
    testing.assertEqual(escapeAmpersands("&nbsp;"), "&amp;nbsp;");
}

func testLeafCloseStopsAtTheNextOpenTagOfTheName() {
    # "<p>" + "<p></p>": nesting-aware search pairs the outer <p> with nothing
    # only after walking to the end; a leaf ends its search at the second <p>
    def src as bytes init buffer("<p><p></p><!-- x --><p></p>");
    testing.assertEqual(leafClose($src, "p", 3, len($src)), -1);
    testing.assertEqual(leafClose($src, "p", 6, len($src)), 6);
    # a comment before the close takes the comment-aware walk
    def commented as bytes init buffer("<p><!-- </p> --></p>");
    testing.assertEqual(leafClose($commented, "p", 3, len($commented)), 16);
}

func testNextChildOfReadsTheLeafNameFlat() {
    def src as bytes init buffer("<p a='1'><p a='2'></p>");
    testing.assertFalse(nextChildOf($src, 0, len($src), "p").closed);
    testing.assertTrue(nextChildOf($src, 9, len($src), "p").closed);
    # read nesting-aware, the first <p> holds the second and is unclosed too,
    # but only after a walk to the limit
    testing.assertFalse(nextChild($src, 0, len($src)).closed);
}
