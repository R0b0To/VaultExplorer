package com.aeidolon.vaultexplorer.officeviewer

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Pure-JVM tests: the converters have no Android dependency. */
class OfficeConverterTest {

    private val opts = ViewOptions(notesLabel = "Speaker notes")

    // ── helpers ───────────────────────────────────────────────────────────

    private fun zip(vararg parts: Pair<String, ByteArray>): ByteArray {
        val bos = ByteArrayOutputStream()
        ZipOutputStream(bos).use { z ->
            for ((name, data) in parts) {
                z.putNextEntry(ZipEntry(name)); z.write(data); z.closeEntry()
            }
        }
        return bos.toByteArray()
    }

    private fun p(name: String, text: String) = name to text.toByteArray(Charsets.UTF_8)

    private fun convert(bytes: ByteArray, ext: String): ConvertedDocument =
        OfficeDocumentConverter.convert(bytes, ext, opts)

    private fun expectError(error: OfficeError, bytes: ByteArray, ext: String) {
        try {
            convert(bytes, ext)
            fail("expected $error")
        } catch (e: OfficeException) {
            assertEquals(error, e.error)
        }
    }

    private val W = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" " +
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" " +
        "xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" " +
        "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""

    private val PNG = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3)

    private fun docx(body: String, vararg extra: Pair<String, ByteArray>): ByteArray = zip(
        p("_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"),
        p("word/document.xml", "<w:document $W><w:body>$body</w:body></w:document>"),
        *extra,
    )

    private fun body(doc: ConvertedDocument) = doc.html.substringAfter("<body>").substringBefore("</body>")

    // ── docx ──────────────────────────────────────────────────────────────

    @Test
    fun docxHeadingsFormattingListsAndTables() {
        val styles = "<w:styles $W>" +
            "<w:style w:type=\"paragraph\" w:styleId=\"Heading1\"><w:name w:val=\"heading 1\"/></w:style></w:styles>"
        val numbering = "<w:numbering $W>" +
            "<w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/></w:lvl></w:abstractNum>" +
            "<w:abstractNum w:abstractNumId=\"1\"><w:lvl w:ilvl=\"0\"><w:numFmt w:val=\"bullet\"/></w:lvl></w:abstractNum>" +
            "<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num><w:num w:numId=\"2\"><w:abstractNumId w:val=\"1\"/></w:num></w:numbering>"
        val bodyXml =
            "<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:r><w:t>Title here</w:t></w:r></w:p>" +
            "<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>bold</w:t></w:r><w:r><w:t xml:space=\"preserve\"> and </w:t></w:r>" +
            "<w:r><w:rPr><w:i/><w:color w:val=\"FF0000\"/></w:rPr><w:t>red italic</w:t></w:r></w:p>" +
            "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>one</w:t></w:r></w:p>" +
            "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>two</w:t></w:r></w:p>" +
            "<w:p><w:r><w:t>between</w:t></w:r></w:p>" +
            "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>three</w:t></w:r></w:p>" +
            "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"2\"/></w:numPr></w:pPr><w:r><w:t>dot</w:t></w:r></w:p>" +
            "<w:tbl><w:tr><w:tc><w:tcPr><w:gridSpan w:val=\"2\"/><w:shd w:fill=\"DDEEFF\"/></w:tcPr><w:p><w:r><w:t>wide</w:t></w:r></w:p></w:tc></w:tr>" +
            "<w:tr><w:tc><w:p><w:r><w:t>a</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>b</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"
        val html = body(convert(docx(bodyXml, p("word/styles.xml", styles), p("word/numbering.xml", numbering)), "docx"))
        assertTrue(html, html.contains("<h1>Title here</h1>"))
        assertTrue(html, html.contains("<strong>bold</strong>"))
        assertTrue(html, html.contains("<span style=\"color:#ff0000\"><em>red italic</em></span>"))
        assertTrue(html, html.contains("<ol><li>one</li><li>two</li></ol>"))
        // numbering continues after the interrupting paragraph
        assertTrue(html, html.contains("<ol start=\"3\"><li>three</li></ol>"))
        assertTrue(html, html.contains("<ul><li>dot</li></ul>"))
        assertTrue(html, html.contains("colspan=\"2\" style=\"background:#ddeeff\""))
    }

    @Test
    fun docxImagesAreServedAsResourcesNotInlined() {
        val rels = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId5\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/image1.png\"/>" +
            "<Relationship Id=\"rId6\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"https://evil.example/x.png\" TargetMode=\"External\"/></Relationships>"
        val drawing = { id: String -> "<w:p><w:r><w:drawing><wp:inline><wp:extent cx=\"952500\" cy=\"476250\"/><wp:docPr id=\"1\" descr=\"alt &lt;text&gt;\"/>" +
            "<a:graphic><a:graphicData><a:blip r:embed=\"$id\"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>" }
        val doc = convert(
            docx(drawing("rId5") + drawing("rId6"), p("word/_rels/document.xml.rels", rels), "word/media/image1.png" to PNG),
            "docx",
        )
        assertEquals(1, doc.resources.size)
        val (url, res) = doc.resources.entries.first()
        assertEquals("image/png", res.mime)
        val html = body(doc)
        assertTrue(html, html.contains("<img src=\"$url\" alt=\"alt &lt;text&gt;\" style=\"width:100px;max-width:100%\">"))
        // the external image must never become an <img>: only a placeholder
        assertEquals(1, Regex("<img ").findAll(html).count())
        assertFalse(html.contains("evil.example"))
    }

    @Test
    fun outputIsInertWhateverTheDocumentSays() {
        val html = convert(
            docx("<w:p><w:r><w:t>&lt;script&gt;alert(1)&lt;/script&gt;&lt;img src=x onerror=alert(2)&gt;</w:t></w:r></w:p>"),
            "docx",
        ).html
        // a real script/img element would contain these as raw markup
        assertFalse(html.contains("<script>alert"))
        assertFalse(html.contains("<img src=x"))
        assertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        assertTrue(html.contains("Content-Security-Policy"))
        assertTrue(html.contains("default-src 'none'"))
    }

    @Test
    fun hyperlinksAreInertSpansNotAnchors() {
        val rels = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId9\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"https://example.org/a?b=1&amp;c=2\" TargetMode=\"External\"/></Relationships>"
        val html = body(
            convert(
                docx("<w:p><w:hyperlink r:id=\"rId9\"><w:r><w:t>go</w:t></w:r></w:hyperlink></w:p>", p("word/_rels/document.xml.rels", rels)),
                "docx",
            ),
        )
        assertFalse(html.contains("<a "))
        assertTrue(html, html.contains("<span class=\"lnk\" title=\"https://example.org/a?b=1&amp;c=2\">go</span>"))
    }

    @Test
    fun docxRtlParagraphGetsDirection() {
        val html = body(convert(docx("<w:p><w:pPr><w:bidi/></w:pPr><w:r><w:t>\u0645\u0631\u062d\u0628\u0627</w:t></w:r></w:p>"), "docx"))
        assertTrue(html, html.contains("<p dir=\"rtl\">\u0645\u0631\u062d\u0628\u0627</p>"))
    }

    @Test
    fun docxPrefixesAreCanonicalised() {
        // same document, but the writer chose "x:" instead of "w:"
        val xml = "<x:document xmlns:x=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><x:body>" +
            "<x:p><x:r><x:t>odd prefix</x:t></x:r></x:p></x:body></x:document>"
        val bytes = zip(p("word/document.xml", xml))
        assertTrue(body(convert(bytes, "docx")).contains("<p>odd prefix</p>"))
    }

    // ── pptx ──────────────────────────────────────────────────────────────

    private val P = "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" " +
        "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" " +
        "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""

    @Test
    fun pptxSlidesTitlesBulletsAndNotes() {
        val pres = "<p:presentation $P><p:sldIdLst><p:sldId id=\"256\" r:id=\"rId2\"/></p:sldIdLst></p:presentation>"
        val presRels = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide1.xml\"/></Relationships>"
        val slideRels = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide\" Target=\"../notesSlides/notesSlide1.xml\"/></Relationships>"
        val slide = "<p:sld $P><p:cSld><p:spTree>" +
            "<p:sp><p:nvSpPr><p:nvPr><p:ph type=\"title\"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>Quarter</a:t></a:r></a:p></p:txBody></p:sp>" +
            "<p:sp><p:nvSpPr><p:nvPr><p:ph type=\"body\"/></p:nvPr></p:nvSpPr><p:txBody>" +
            "<a:p><a:r><a:t>Top</a:t></a:r></a:p><a:p><a:pPr lvl=\"1\"/><a:r><a:rPr b=\"1\"/><a:t>Nested</a:t></a:r></a:p></p:txBody></p:sp>" +
            "<p:sp><p:nvSpPr><p:nvPr><p:ph type=\"sldNum\"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>7</a:t></a:r></a:p></p:txBody></p:sp>" +
            "</p:spTree></p:cSld></p:sld>"
        val notes = "<p:notes $P><p:cSld><p:spTree><p:sp><p:nvSpPr><p:nvPr><p:ph type=\"body\"/></p:nvPr></p:nvSpPr>" +
            "<p:txBody><a:p><a:r><a:t>say hello</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:notes>"
        val bytes = zip(
            p("_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
                "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"ppt/presentation.xml\"/></Relationships>"),
            p("ppt/presentation.xml", pres), p("ppt/_rels/presentation.xml.rels", presRels),
            p("ppt/slides/slide1.xml", slide), p("ppt/slides/_rels/slide1.xml.rels", slideRels),
            p("ppt/notesSlides/notesSlide1.xml", notes),
        )
        val html = body(convert(bytes, "pptx"))
        assertTrue(html, html.contains("<h2 class=\"st\">Quarter</h2>"))
        assertTrue(html, html.contains("<ul><li>Top<ul><li><strong>Nested</strong></li></ul></li></ul>"))
        assertFalse("slide-number placeholder must be dropped", html.contains(">7<") && html.contains("<p>7"))
        assertTrue(html, html.contains("<summary>Speaker notes</summary><p>say hello</p>"))
    }

    // ── xlsx ──────────────────────────────────────────────────────────────

    @Test
    fun xlsxValuesFormatsMergesAndHiddenSheets() {
        val wb = "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">" +
            "<sheets><sheet name=\"Data\" sheetId=\"1\" r:id=\"rId1\"/><sheet name=\"Secret\" sheetId=\"2\" state=\"hidden\" r:id=\"rId2\"/></sheets></workbook>"
        val rels = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/>" +
            "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet2.xml\"/></Relationships>"
        val styles = "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">" +
            "<numFmts count=\"1\"><numFmt numFmtId=\"164\" formatCode=\"&quot;EUR &quot;#,##0.00\"/></numFmts>" +
            "<fonts><font/><font><b/></font></fonts><fills><fill/><fill><patternFill patternType=\"solid\"><fgColor rgb=\"FFDDEEFF\"/></patternFill></fill></fills>" +
            "<cellXfs><xf numFmtId=\"0\"/><xf numFmtId=\"14\"/><xf numFmtId=\"9\"/><xf numFmtId=\"164\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"1\"/></cellXfs></styleSheet>"
        val sst = "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><si><t>Hello &amp; bye</t></si><si><r><t>Rich</t></r><r><t> text</t></r><rPh><t>PHONETIC</t></rPh></si></sst>"
        val sheet = "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>" +
            "<row r=\"1\"><c r=\"A1\" t=\"s\" s=\"4\"><v>0</v></c><c r=\"B1\" t=\"s\"><v>1</v></c></row>" +
            "<row r=\"3\"><c r=\"A3\" s=\"1\"><v>46096</v></c><c r=\"B3\" s=\"2\"><v>0.125</v></c><c r=\"C3\" s=\"3\"><v>1234.5</v></c>" +
            "<c r=\"D3\" t=\"b\"><v>1</v></c><c r=\"E3\"><f>SUM(1,2)</f><v>3</v></c><c r=\"F3\" t=\"inlineStr\"><is><t>inline</t></is></c></row>" +
            "<row r=\"4\"><c r=\"A4\" t=\"s\"><v>0</v></c></row></sheetData><mergeCells><mergeCell ref=\"A4:C4\"/></mergeCells></worksheet>"
        val bytes = zip(
            p("_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
                "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"),
            p("xl/workbook.xml", wb), p("xl/_rels/workbook.xml.rels", rels), p("xl/styles.xml", styles),
            p("xl/sharedStrings.xml", sst), p("xl/worksheets/sheet1.xml", sheet),
            p("xl/worksheets/sheet2.xml", "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>HIDDEN-CONTENT</t></is></c></row></sheetData></worksheet>"),
        )
        val doc = convert(bytes, "xlsx")
        val html = body(doc)
        assertFalse("hidden sheet content must not appear", doc.html.contains("HIDDEN-CONTENT"))
        assertTrue(html, html.contains(">Hello &amp; bye</td>"))
        assertTrue("rich text joined, phonetic dropped: $html", html.contains(">Rich text</td>") && !html.contains("PHONETIC"))
        assertTrue(html, html.contains("2026-03-15"))          // serial 46096 with built-in date format
        assertTrue("built-in 0% rounds half up: $html", html.contains(">13%</td>"))
        assertTrue(html, html.contains(">EUR 1,234.50</td>"))
        assertTrue(html, html.contains(">TRUE</td>"))
        assertTrue("cached formula value shown", html.contains(">3</td>"))
        assertTrue(html, html.contains(">inline</td>"))
        assertTrue("merge spans three columns", html.contains("colspan=\"3\""))
        assertTrue("true row numbers are kept (row 2 absent)", html.contains("<th class=\"rn\">3</th>"))
        assertTrue(doc.html.contains("font-weight:700") && doc.html.contains("background:#ddeeff"))
    }

    // ── OpenDocument ──────────────────────────────────────────────────────

    private val O = "xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" " +
        "xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" " +
        "xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" " +
        "xmlns:draw=\"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0\" " +
        "xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" " +
        "xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" " +
        "xmlns:presentation=\"urn:oasis:names:tc:opendocument:xmlns:presentation:1.0\""

    private fun odf(mime: String, content: String) = zip(
        p("mimetype", mime),
        p("content.xml", "<office:document-content $O>$content</office:document-content>"),
    )

    @Test
    fun odtHeadingsSpansListsAndWhitespace() {
        val content = "<office:automatic-styles>" +
            "<style:style style:name=\"B\" style:family=\"text\"><style:text-properties fo:font-weight=\"bold\"/></style:style>" +
            "<text:list-style style:name=\"N\"><text:list-level-style-number text:level=\"1\" style:num-format=\"1\"/></text:list-style>" +
            "</office:automatic-styles><office:body><office:text>" +
            "<text:h text:outline-level=\"2\">Sub</text:h>" +
            "<text:p>Hello   <text:span text:style-name=\"B\">bold</text:span><text:s text:c=\"2\"/>end</text:p>" +
            "<text:list text:style-name=\"N\"><text:list-item><text:p>a</text:p></text:list-item><text:list-item><text:p>b</text:p></text:list-item></text:list>" +
            "<text:p>gap</text:p>" +
            "<text:list text:style-name=\"N\" text:continue-numbering=\"true\"><text:list-item><text:p>c</text:p></text:list-item></text:list>" +
            "</office:text></office:body>"
        val html = body(convert(odf("application/vnd.oasis.opendocument.text", content), "odt"))
        assertTrue(html, html.contains("<h2>Sub</h2>"))
        assertTrue("collapsed spaces, preserved text:s: $html", html.contains("<p>Hello <strong>bold</strong>&nbsp;&nbsp;end</p>"))
        assertTrue(html, html.contains("<ol><li><p>a</p></li><li><p>b</p></li></ol>"))
        assertTrue(html, html.contains("<ol start=\"3\"><li><p>c</p></li></ol>"))
    }

    @Test
    fun odsUsesDisplayTextAndSkipsHiddenSheets() {
        val content = "<office:automatic-styles>" +
            "<style:style style:name=\"ta_hidden\" style:family=\"table\"><style:table-properties table:display=\"false\"/></style:style>" +
            "</office:automatic-styles><office:body><office:spreadsheet>" +
            "<table:table table:name=\"Vis\"><table:table-row>" +
            "<table:table-cell office:value-type=\"float\" office:value=\"1234.5\"><text:p>1,234.50 \u20ac</text:p></table:table-cell>" +
            "<table:table-cell table:number-columns-repeated=\"3\"/>" +
            "</table:table-row><table:table-row table:number-rows-repeated=\"1000000\"><table:table-cell table:number-columns-repeated=\"1024\"/></table:table-row></table:table>" +
            "<table:table table:name=\"Hid\" table:style-name=\"ta_hidden\"><table:table-row><table:table-cell><text:p>HIDDEN-CONTENT</text:p></table:table-cell></table:table-row></table:table>" +
            "</office:spreadsheet></office:body>"
        val doc = convert(odf("application/vnd.oasis.opendocument.spreadsheet", content), "ods")
        assertTrue(doc.html.contains("1,234.50 \u20ac"))
        assertFalse(doc.html.contains("HIDDEN-CONTENT"))
        assertTrue("a million trailing empty rows must not explode: ${doc.html.length}", doc.html.length < 20_000)
    }

    @Test
    fun odpSlidesTitleAndNotes() {
        val content = "<office:body><office:presentation><draw:page>" +
            "<draw:frame presentation:class=\"title\"><draw:text-box><text:p>Deck title</text:p></draw:text-box></draw:frame>" +
            "<draw:frame presentation:class=\"outline\"><draw:text-box><text:list><text:list-item><text:p>point</text:p></text:list-item></text:list></draw:text-box></draw:frame>" +
            "<draw:frame presentation:class=\"page-number\"><draw:text-box><text:p>9</text:p></draw:text-box></draw:frame>" +
            "<presentation:notes><draw:frame presentation:class=\"notes\"><draw:text-box><text:p>remember</text:p></draw:text-box></draw:frame></presentation:notes>" +
            "</draw:page></office:presentation></office:body>"
        val html = body(convert(odf("application/vnd.oasis.opendocument.presentation", content), "odp"))
        assertTrue(html, html.contains("<h2 class=\"st\">Deck title</h2>"))
        assertTrue(html, html.contains("<li><p>point</p></li>"))
        assertFalse(html, html.contains(">9<"))
        assertTrue(html, html.contains("<summary>Speaker notes</summary><p>remember</p>"))
    }

    // ── legacy .ppt (synthetic compound file) ─────────────────────────────

    private fun rec(ver: Int, type: Int, payload: ByteArray, inst: Int = 0): ByteArray {
        val bb = ByteBuffer.allocate(8 + payload.size).order(ByteOrder.LITTLE_ENDIAN)
        bb.putShort(((inst shl 4) or ver).toShort()).putShort(type.toShort()).putInt(payload.size).put(payload)
        return bb.array()
    }

    private fun u32(v: Int) = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(v).array()

    private fun cfb(streamName: String, data: ByteArray): ByteArray {
        val padded = data.copyOf(maxOf(4096, (data.size + 511) / 512 * 512))
        val streamSectors = padded.size / 512
        val out = ByteBuffer.allocate(512 * (1 + 1 + 1 + streamSectors)).order(ByteOrder.LITTLE_ENDIAN)
        val sig = byteArrayOf(0xD0.toByte(), 0xCF.toByte(), 0x11, 0xE0.toByte(), 0xA1.toByte(), 0xB1.toByte(), 0x1A, 0xE1.toByte())
        out.put(sig)
        out.position(24); out.putShort(0x3E).putShort(3).putShort(0xFFFE.toShort()).putShort(9).putShort(6)
        out.position(44); out.putInt(1)            // number of FAT sectors
        out.putInt(1)                              // first directory sector
        out.position(56); out.putInt(4096)         // mini stream cutoff
        out.putInt(-2).putInt(0).putInt(-2).putInt(0) // mini FAT / DIFAT: none
        out.putInt(0)                              // DIFAT[0] = FAT sector 0
        for (i in 1 until 109) out.putInt(-1)
        // sector 0: FAT
        out.position(512)
        out.putInt(-3).putInt(-2)                  // FAT sector, directory sector (end of chain)
        for (i in 0 until streamSectors) out.putInt(if (i == streamSectors - 1) -2 else 2 + i + 1)
        while (out.position() < 1024) out.putInt(-1)
        // sector 1: directory
        out.position(1024)
        fun dirEntry(name: String, type: Int, start: Int, size: Int, child: Int) {
            val base = out.position()
            val nb = (name + "\u0000").toByteArray(Charsets.UTF_16LE)
            out.put(nb); out.position(base + 64); out.putShort(nb.size.toShort())
            out.put(type.toByte()).put(1)
            out.putInt(-1).putInt(-1).putInt(child)
            out.position(base + 116); out.putInt(start).putInt(size).putInt(0)
            out.position(base + 128)
        }
        dirEntry("Root Entry", 5, -2, 0, 1)
        dirEntry(streamName, 2, 2, data.size.coerceAtLeast(4096), -1)
        out.position(1536)
        out.put(padded)
        return out.array()
    }

    private fun text16(s: String) = s.toByteArray(Charsets.UTF_16LE)

    @Test
    fun legacyPptTextOnlyFromSlidesAndNotes() {
        fun box(type: Int, text: String) = rec(0xF, 0xF00D, rec(0, 0x0F9F, u32(type)) + rec(0, 0x0FA0, text16(text)))
        val slide1 = rec(0xF, 0x03EE, rec(0xF, 0x040C, box(0, "Legacy title") + box(1, "first\rsecond")))
        val slide2 = rec(0xF, 0x03EE, rec(0xF, 0x040C, box(4, "Only a text box")))
        val master = rec(0xF, 0x03F8, rec(0xF, 0x040C, box(0, "Click to edit Master title style")))
        val persist = { id: Int -> rec(0, 0x03F3, u32(0) + u32(0) + u32(0) + u32(id) + u32(0)) }
        val list = rec(0xF, 0x0FF0, persist(256) + persist(257), inst = 0)
        val doc = rec(0xF, 0x03E8, list)
        val notesAtom = rec(0, 0x03F1, u32(256) + u32(0))
        val notes = rec(0xF, 0x03F0, notesAtom + rec(0xF, 0x040C, box(2, "legacy note")))
        val stream = doc + master + slide1 + slide2 + notes
        val html = body(convert(cfb("PowerPoint Document", stream), "ppt"))
        assertTrue(html, html.contains("<h2 class=\"st\">Legacy title</h2>"))
        assertTrue(html, html.contains("<li>first</li><li>second</li>"))
        assertTrue(html, html.contains("<p>Only a text box</p>"))
        assertFalse("master template text must not appear", html.contains("Click to edit"))
        assertTrue(html, html.contains("<summary>Speaker notes</summary><p>legacy note</p>"))
    }

    // ── errors and limits ─────────────────────────────────────────────────

    @Test
    fun unsupportedAndMalformedInputsAreReportedNotCrashed() {
        expectError(OfficeError.UNSUPPORTED, ByteArray(0), "docx")
        expectError(OfficeError.UNSUPPORTED, "just text".toByteArray(), "docx")
        expectError(OfficeError.UNSUPPORTED, zip(p("hello.txt", "hi")), "docx")
        val good = docx("<w:p><w:r><w:t>x</w:t></w:r></w:p>")
        expectError(OfficeError.UNSUPPORTED, good.copyOf(good.size / 2), "docx")
        // a legacy binary .doc (compound file without PowerPoint stream)
        expectError(OfficeError.UNSUPPORTED, cfb("WordDocument", ByteArray(4096)), "doc")
    }

    @Test
    fun encryptedPackagesAreRecognised() {
        expectError(OfficeError.ENCRYPTED, cfb("EncryptedPackage", ByteArray(4096)), "docx")
        val manifest = "<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\">" +
            "<manifest:file-entry manifest:full-path=\"content.xml\"><manifest:encryption-data/></manifest:file-entry></manifest:manifest>"
        val enc = zip(
            p("mimetype", "application/vnd.oasis.opendocument.text"),
            p("content.xml", "<office:document-content $O/>"),
            p("META-INF/manifest.xml", manifest),
        )
        expectError(OfficeError.ENCRYPTED, enc, "odt")
    }

    @Test
    fun oversizedPartIsRejectedAsTooLarge() {
        val bos = ByteArrayOutputStream()
        ZipOutputStream(bos).use { z ->
            z.putNextEntry(ZipEntry("word/document.xml"))
            val chunk = ByteArray(1 shl 20) { 'a'.code.toByte() }
            repeat(100) { z.write(chunk) } // 100 MB > PART_CAP, compresses to ~100 KB
            z.closeEntry()
        }
        expectError(OfficeError.TOO_LARGE, bos.toByteArray(), "docx")
    }

    @Test
    fun deepNestingIsRejected() {
        val deep = "<w:document $W><w:body>" + "<w:sdt><w:sdtContent>".repeat(2000) + "</w:sdtContent></w:sdt>".repeat(2000) + "</w:body></w:document>"
        expectError(OfficeError.TOO_LARGE, zip(p("word/document.xml", deep)), "docx")
    }

    @Test
    fun doctypeEntitiesAreNeverExpandedOrFetched() {
        val xml = "<?xml version=\"1.0\"?><!DOCTYPE d [<!ENTITY xxe SYSTEM \"file:///etc/passwd\"><!ENTITY big \"AAAA\">]>" +
            "<w:document $W><w:body><w:p><w:r><w:t>&xxe;&big;ok</w:t></w:r></w:p></w:body></w:document>"
        val html = convert(zip(p("word/document.xml", xml)), "docx").html
        assertFalse(html.contains("root:"))
        assertFalse(html.contains("AAAA"))
        assertTrue(html.contains("ok"))
    }

    @Test
    fun contentDecidesFormatNotTheExtension() {
        val bytes = docx("<w:p><w:r><w:t>renamed</w:t></w:r></w:p>")
        assertTrue(body(convert(bytes, "xlsx")).contains("renamed"))
        assertTrue(body(convert(bytes, "")).contains("renamed"))
    }

    // ── view options ──────────────────────────────────────────────────────

    @Test
    fun themeColoursCannotInjectCss() {
        val o = ViewOptions(background = "red;}</style><script>alert(1)</script>", foreground = "#12ab9F", accent = "zzzzzz")
        assertEquals("#eceef2", o.background)
        assertEquals("#12ab9f", o.foreground)
        assertEquals("#3b6fd4", o.accent)
        val page = pageHtml("t</title><script>", "<p>x</p>", "", o)
        assertFalse(page.contains("<script>"))
    }

    // ── XML reader ────────────────────────────────────────────────────────

    @Test
    fun xmlReaderDecodesEntitiesAndCdataAndSkipsComments() {
        val n = XmlPull.parseTree("<a><!-- c --><b x=\"1&amp;2\">t&lt;&#65;&#x42;<![CDATA[<raw>]]></b><c/></a>".toByteArray())
        val b = n.first("b")!!
        assertEquals("1&2", b.attr("x"))
        assertEquals("t<AB<raw>", b.textContent())
        assertNotNull(n.first("c"))
    }

    @Test
    fun xmlReaderHandlesUtf16Bom() {
        val xml = "<a>h\u00e9llo</a>"
        val bytes = byteArrayOf(0xFF.toByte(), 0xFE.toByte()) + xml.toByteArray(Charsets.UTF_16LE)
        assertEquals("h\u00e9llo", XmlPull.parseTree(bytes).textContent())
    }

    @Test
    fun xmlReaderCanonicalisesNamespacePrefixes() {
        val n = XmlPull.parseTree(
            "<q:worksheet xmlns:q=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><q:row/></q:worksheet>".toByteArray(),
        )
        assertEquals("worksheet", n.name)
        assertNull(n.first("q:row"))
        assertNotNull(n.first("row"))
    }

    // ── number formats ────────────────────────────────────────────────────

    @Test
    fun numberFormats() {
        fun f(v: Double, code: String) = XlFormat.format(v, code, false)
        assertEquals("1234.5", XlFormat.general(1234.5))
        assertEquals("0.3", XlFormat.general(0.1 + 0.2))
        assertEquals("1.23457E+11", XlFormat.general(123456789012.0))
        assertEquals("1,234.50", f(1234.5, "#,##0.00"))
        assertEquals("12.5%", f(0.125, "0.0%"))
        assertEquals("1.23E+04", f(12345.0, "0.00E+00"))
        assertEquals("(5.50)", f(-5.5, "#,##0.00;(#,##0.00)"))
        assertEquals("-5.50", f(-5.5, "#,##0.00"))
        assertEquals("007", f(7.0, "000"))
        assertEquals("1.5", f(1.5, "0.0#"))
        assertEquals("1.25", f(1.25, "0.0#"))
        assertEquals("$1,000", f(1000.0, "\"$\"#,##0"))
        assertEquals("1.5 kg", f(1.5, "0.0 \"kg\""))
        assertEquals("1,235", f(1234567.0, "#,##0,"))
    }

    @Test
    fun dateAndTimeFormats() {
        fun f(v: Double, code: String) = XlFormat.format(v, code, false)
        assertTrue(XlFormat.isDateFormat("yyyy-mm-dd"))
        assertTrue(XlFormat.isDateFormat("[h]:mm:ss"))
        assertFalse(XlFormat.isDateFormat("#,##0.00"))
        assertFalse(XlFormat.isDateFormat("General"))
        assertEquals("2026-03-15", f(46096.0, "yyyy-mm-dd"))
        assertEquals("15/03/2026", f(46096.0, "dd/mm/yyyy"))
        assertEquals("14:30:05", f(46096.0 + (14 * 3600 + 30 * 60 + 5) / 86400.0, "hh:mm:ss"))
        assertEquals("2:30 PM", f(0.6041666667, "h:mm AM/PM"))
        assertEquals("26:00:00", f(1.0 + 2.0 / 24, "[h]:mm:ss"))
        assertEquals("05.5", f(5.5 / 86400.0, "ss.0"))
        // "m" is a minute next to h/s and a month otherwise
        assertEquals("3", f(46096.0, "m"))
        assertEquals("30", f(0.0 + 30 * 60 / 86400.0 + 0.5, "h:m").substringAfter(":"))
        assertEquals("1904-01-02", XlFormat.format(1.0, "yyyy-mm-dd", true))
    }
}
